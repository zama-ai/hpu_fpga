// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Implement LBY nodes that work in parallel.
// The nodes are connected in a systolic architecture way.
// Therefore the input data are sent accordingly.
// An accumulator is used on the last node output to get the final result.
//
// Input data order:
//
// We process the LWE_K x N*GLWE_K matrix as follows:
//                                  X (0 -> LWE_K/LBX - 1)
//                           <----------------------------->
//                           ^ | | |   | | | | | | | | | | |
//                           |0|3|6|...| | | | | | | | | | |
//                           |-----------------------------
//                           | | | |   | | | | | | | | | | |
// Y (0 -> N*GLWE_K/LAMBDA)  |1|4|7|   | | | | | | | | | | |
//                           |-----------------------------
//                           | | | |   | | | | | | | | | | |
//                           |2|5|8|   | | | | | | | | | | |
//                           V
// A block is composed of LBX x LBY x LBZ coefficients.
// Coef in LBZ dimension are decomposition levels of the same original coef.
// We process block column by column.
// An entire block column is processed, before interleaving another batch.
// Each element of a block are processed in parallel.
// Within a block, the data of each line are sent shifted by 1 cycle from 1 data
// to the other.
//
// For an input BLWE coefficient, all the decomposition levels of that coefficient
// are received, then the decomposition levels of a coefficient of another BLWE
// of the same batch are received.
// Therefore at the output of the block we obtain the result of the accumulation
// of the coefficients in this set.
// An accumulator is implemented after the block, to accumulate between the decomposition levels,
// and between the sets.
// ==============================================================================================

module pep_ks_mult
  import param_tfhe_pkg::*;
  import pep_common_param_pkg::*;
  import pep_ks_common_param_pkg::*;
#(
  parameter int OP_W           = 64
)
(
  input  logic                                        clk,        // clock
  input  logic                                        s_rst_n,    // synchronous reset

  input  logic [LBY-1:0][LBZ-1:0][KS_B_W-1:0]         ctrl_mult_data,
  input  logic [LBY-1:0][LBZ-1:0]                     ctrl_mult_sign,
  input  logic [LBY-1:0]                              ctrl_mult_avail,

  // Information of the last coefficient. Sent at the same time of
  // this coefficient.
  input  logic                                        ctrl_mult_last_eol,
  input  logic                                        ctrl_mult_last_eoy,
  input  logic                                        ctrl_mult_last_last_iter, // last iteration within the column
  input  logic [TOTAL_BATCH_NB_W-1:0]                 ctrl_mult_last_batch_id,

  input  logic [LBX-1:0][LBY-1:0][LBZ-1:0][OP_W-1:0]  ksk,
  input  logic [LBX-1:0][LBY-1:0]                     ksk_vld,
  output logic [LBX-1:0][LBY-1:0]                     ksk_rdy,

  output logic [LBX-1:0][OP_W-1:0]                    mult_outp_data,
  output logic [LBX-1:0]                              mult_outp_avail,
  output logic [LBX-1:0]                              mult_outp_last_pbs,
  output logic [LBX-1:0][TOTAL_BATCH_NB_W-1:0]        mult_outp_batch_id,

  output logic                                        error
);

//===============================================
// type
//===============================================
  typedef struct packed {
    logic                        eol;
    logic                        eoy;
    logic                        last_iter;
    logic [TOTAL_BATCH_NB_W-1:0] batch_id;
  } info_t;

  localparam int INFO_W = $bits(info_t);

//===============================================
// LBX, LBY rectangle
//===============================================
  // results go through the column
  logic [LBX-1:0][LBY:0][OP_W-1:0]            node_result;
  logic [LBX-1:0][LBY:0]                      node_res_avail;
  info_t [LBX:0]                              node_res_info;

  // data go through the line
  logic [LBX:0][LBY-1:0][LBZ-1:0][KS_B_W-1:0] node_data;
  logic [LBX:0][LBY-1:0][LBZ-1:0]             node_sign;
  logic [LBX:0][LBY-1:0]                      node_avail;

  logic [LBX-1:0][LBY-1:0]                    node_error;
  info_t [LBX:0]                              node_info;

  info_t                                      ctrl_mult_info;

  logic [LBX-1:0][OP_W-1:0]                   mult_outp_dataD;
  logic [LBX-1:0]                             mult_outp_availD;
  logic [LBX-1:0]                             mult_outp_last_iterD;
  logic [LBX-1:0][TOTAL_BATCH_NB_W-1:0]       mult_outp_batch_idD;

  assign ctrl_mult_info.eol       = ctrl_mult_last_eol;
  assign ctrl_mult_info.eoy       = ctrl_mult_last_eoy;
  assign ctrl_mult_info.last_iter = ctrl_mult_last_last_iter;
  assign ctrl_mult_info.batch_id  = ctrl_mult_last_batch_id;

  assign node_info[0]  = ctrl_mult_info;

  generate
    for (genvar gen_y=0; gen_y<LBY; gen_y=gen_y+1) begin : gen_in_y_loop
      assign node_data[0][gen_y]  = ctrl_mult_data[gen_y];
      assign node_sign[0][gen_y]  = ctrl_mult_sign[gen_y];
      assign node_avail[0][gen_y] = ctrl_mult_avail[gen_y];
    end

    //===============================================
    // Node instances
    //===============================================
    for (genvar gen_x=0; gen_x<LBX; gen_x=gen_x+1) begin : gen_node_x_loop
      assign node_res_avail[gen_x][0] = 1'b1;
      assign node_result[gen_x][0]    = '0;
      for (genvar gen_y=0; gen_y<LBY; gen_y=gen_y+1) begin : gen_node_y_loop
        if (gen_y < LBY-1) begin : gen_not_last_y
          pep_ks_mult_node #(
            .KS_B_W   (KS_B_W),
            .LBZ      (LBZ),
            .OP_W     (OP_W),
            .SIDE_W   (0) // UNUSED
          ) pep_ks_mult_node (
            .clk          (clk),
            .s_rst_n      (s_rst_n),

            .prevx_data   (node_data[gen_x][gen_y]),
            .prevx_sign   (node_sign[gen_x][gen_y]),
            .prevx_avail  (node_avail[gen_x][gen_y]),
            .prevx_side   ('x), // UNUSED

            .nextx_data   (node_data[gen_x+1][gen_y]),
            .nextx_sign   (node_sign[gen_x+1][gen_y]),
            .nextx_avail  (node_avail[gen_x+1][gen_y]),
            .nextx_side   (/*UNUSED*/),

            .ksk          (ksk[gen_x][gen_y]),
            .ksk_vld      (ksk_vld[gen_x][gen_y]),
            .ksk_rdy      (ksk_rdy[gen_x][gen_y]),

            .prevy_result (node_result[gen_x][gen_y]),
            .prevy_avail  (node_res_avail[gen_x][gen_y]),

            .nexty_result (node_result[gen_x][gen_y+1]),
            .nexty_avail  (node_res_avail[gen_x][gen_y+1]),
            .nexty_side   (/*UNUSED*/),

            .error        (node_error[gen_x][gen_y])
          );
        end
        else begin : gen_last_y
          pep_ks_mult_node #(
            .KS_B_W   (KS_B_W),
            .LBZ      (LBZ),
            .OP_W     (OP_W),
            .SIDE_W   (INFO_W)
          ) pep_ks_mult_node (
            .clk          (clk),
            .s_rst_n      (s_rst_n),

            .prevx_data   (node_data[gen_x][gen_y]),
            .prevx_sign   (node_sign[gen_x][gen_y]),
            .prevx_avail  (node_avail[gen_x][gen_y]),
            .prevx_side   (node_info[gen_x]),

            .nextx_data   (node_data[gen_x+1][gen_y]),
            .nextx_sign   (node_sign[gen_x+1][gen_y]),
            .nextx_avail  (node_avail[gen_x+1][gen_y]),
            .nextx_side   (node_info[gen_x+1]),

            .ksk          (ksk[gen_x][gen_y]),
            .ksk_vld      (ksk_vld[gen_x][gen_y]),
            .ksk_rdy      (ksk_rdy[gen_x][gen_y]),

            .prevy_result (node_result[gen_x][gen_y]),
            .prevy_avail  (node_res_avail[gen_x][gen_y]),

            .nexty_result (node_result[gen_x][gen_y+1]),
            .nexty_avail  (node_res_avail[gen_x][gen_y+1]),
            .nexty_side   (node_res_info[gen_x]),

            .error        (node_error[gen_x][gen_y])
          );

        end
      end // for gen_y

      //===============================================
      // Accumulator
      //===============================================
      //== buffer
      logic [BATCH_PBS_NB-1:0][OP_W-1:0] buff_data;
      logic [BATCH_PBS_NB-1:0][OP_W-1:0] buff_dataD;
      logic [OP_W-1:0]                   acc;
      logic [OP_W-1:0]                   accD;

      //----------------------
      // s0
      //----------------------
      //== Input
      logic [OP_W-1:0] s0_node_result;
      logic            s0_node_res_avail;
      info_t           s0_node_res_info;

      assign s0_node_result    = node_result[gen_x][LBY];
      assign s0_node_res_avail = node_res_avail[gen_x][LBY];
      assign s0_node_res_info  = node_res_info[gen_x];

      //== Counters
      logic [BPBS_ID_W-1:0] s0_pbs_id;
      logic [BPBS_ID_W-1:0] s0_pbs_idD;

      assign s0_pbs_idD = s0_node_res_avail && s0_node_res_info.eol ?
                              s0_node_res_info.eoy ? '0 : s0_pbs_id + 1 :
                              s0_pbs_id;

      //== Accumulation
      // If it is the result of the first block line, accumulate with 0
      // If it is the same batch and same pid as previous computation,
      // accumulate in the intermediary acc register.
      // Else acc with the buffer selected value.

      logic [TOTAL_BATCH_NB-1:0] s0_prev_batch_id;
      logic [BPBS_ID_W-1:0]      s0_prev_pbs_id;
      logic                      s0_is_bcol_first;
      logic                      s0_prev_avail;

      logic [TOTAL_BATCH_NB-1:0] s0_prev_batch_idD;
      logic [BPBS_ID_W-1:0]      s0_prev_pbs_idD;
      logic                      s0_is_bcol_firstD;
      logic                      s0_prev_availD;

      assign s0_prev_batch_idD = s0_node_res_avail ? s0_node_res_info.batch_id : s0_prev_batch_id;
      assign s0_prev_pbs_idD   = s0_node_res_avail ? s0_pbs_id                 : s0_prev_pbs_id;
      assign s0_is_bcol_firstD = s0_node_res_avail ? s0_node_res_info.last_iter && s0_node_res_info.eol && s0_node_res_info.eoy ? 1'b1 : 1'b0 : s0_is_bcol_first;
      assign s0_prev_availD    = s0_node_res_avail;

      always_ff @(posedge clk)
        if (!s_rst_n) begin
          s0_pbs_id        <= '0;
          s0_is_bcol_first <= 1'b1;
          s0_prev_avail    <= 1'b0;
        end
        else begin
          s0_pbs_id        <= s0_pbs_idD;
          s0_is_bcol_first <= s0_is_bcol_firstD;
          s0_prev_avail    <= s0_prev_availD;
        end

      always_ff @(posedge clk) begin
        s0_prev_batch_id <= s0_prev_batch_idD;
        s0_prev_pbs_id   <= s0_prev_pbs_idD;
      end

      logic [OP_W-1:0] s0_sel_buff_data;
      logic [OP_W-1:0] s0_op;
      logic            s0_use_acc;

      assign s0_use_acc      = s0_prev_avail & (s0_prev_pbs_id == s0_pbs_id) & (s0_prev_batch_id == s0_node_res_info.batch_id);
      assign s0_sel_buff_data = buff_data[s0_pbs_id];
      assign s0_op = s0_is_bcol_first ? '0 :
                     s0_use_acc       ? acc : s0_sel_buff_data;

      // Accumulator
      assign accD = s0_op + s0_node_result;

      // Update
      logic            s0_update_buff;
      logic            s0_clear_buff;
      logic            s0_result_avail;

      assign s0_update_buff  = s0_node_res_avail & s0_node_res_info.eol;
      assign s0_result_avail = s0_update_buff & s0_node_res_info.last_iter;
      assign s0_clear_buff   = s0_result_avail;

      //----------------------
      // s1: update buffer
      //----------------------
      logic                        s1_update_buff;
      logic                        s1_clear_buff;
      logic                        s1_result_avail;
      info_t                       s1_node_res_info;
      logic [BPBS_ID_W-1:0]        s1_pbs_id;

      always_ff @(posedge clk)
        if (!s_rst_n) begin
          s1_update_buff  <= 1'b0;
          s1_clear_buff   <= 1'b0;
          s1_result_avail <= 1'b0;
        end
        else begin
          s1_update_buff  <= s0_update_buff;
          s1_clear_buff   <= s0_clear_buff;
          s1_result_avail <= s0_result_avail;
        end

      always_ff @(posedge clk) begin
        s1_pbs_id        <= s0_pbs_id;
        s1_node_res_info <= s0_node_res_info;
      end

      always_comb
        for (int p=0; p<BATCH_PBS_NB; p=p+1) begin
          if (s1_update_buff && s1_pbs_id == p)
            buff_dataD[p] = s1_clear_buff ? '0 : acc;
          else
            buff_dataD[p] = buff_data[p];
        end

      always_ff @(posedge clk) begin
        if (!s_rst_n) buff_data <= '0;
        else          buff_data <= buff_dataD;
      end

      always_ff @(posedge clk)
        acc <= accD;

// pragma translate_off
      // We made the assumption that there is no bubble while receiving the levels
      // of the same pbs.
      // Note [KS_LG_NB-1] is not used. Write it this way to avoid warning when KS_LG_NB == 2.
      if (KS_LG_NB > 1) begin : __gen_assert_
        logic [KS_LG_NB-1:0] _s0_node_res_avail_sr;
        logic [KS_LG_NB-1:0] _s0_node_res_avail_srD;
        assign _s0_node_res_avail_srD = {_s0_node_res_avail_sr[KS_LG_NB-2:0], s0_node_res_avail};
        always_ff @(posedge clk)
          if (!s_rst_n) _s0_node_res_avail_sr <= '0;
          else          _s0_node_res_avail_sr <= _s0_node_res_avail_srD;
        always_ff @(posedge clk)
          if (!s_rst_n) begin
            // do nothing
          end
          else begin
            if (s0_node_res_avail && s0_node_res_info.eol) begin
              assert(_s0_node_res_avail_sr[KS_LG_NB-2:0] == '1)
              else begin
                $fatal(1,"%t > ERROR: Bubble while receiving levels for the same pbs_id",$time);
              end
            end
          end
        end
// pragma translate_on


      //===============================================
      // Output
      //===============================================
      assign mult_outp_availD[gen_x]     = s1_result_avail;
      assign mult_outp_dataD[gen_x]      = acc;
      assign mult_outp_last_iterD[gen_x] = s1_node_res_info.eoy;
      assign mult_outp_batch_idD[gen_x]  = s1_node_res_info.batch_id;

    end // for gen_x
  endgenerate

//===============================================
// Output pipe
//===============================================
  always_ff @(posedge clk)
    if (!s_rst_n) mult_outp_avail <= 1'b0;
    else          mult_outp_avail <= mult_outp_availD;

  always_ff @(posedge clk) begin
    mult_outp_data     <= mult_outp_dataD;
    mult_outp_last_pbs <= mult_outp_last_iterD;
    mult_outp_batch_id <= mult_outp_batch_idD;
  end

//===============================================
// Error
//===============================================
  logic errorD;

  assign errorD = node_error != '0;

  always_ff @(posedge clk)
    if (!s_rst_n) error <= 1'b0;
    else          error <= errorD;

endmodule
