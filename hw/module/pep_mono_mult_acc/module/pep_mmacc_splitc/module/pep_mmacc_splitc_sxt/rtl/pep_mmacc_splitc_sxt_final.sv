// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the sample extraction, and the rotation with b.
// It reads the coefficients from GRAM, and orders them according to b and, does the negation
// when necessary.
// Data in GRAM are assumed to be in reverse order.
//
// This module outputs REGF_COEF_NB coefficients at a time.
// If the number of coefficients of a BLWE is not a multiple of BLWE_COEF_NB, the last word
// is completed with garbage.
// ==============================================================================================

`include "pep_mmacc_splitc_sxt_macro_inc.sv"

module pep_mmacc_splitc_sxt_final
  import param_tfhe_pkg::*;
  import top_common_param_pkg::*;
  import ntt_core_common_param_pkg::*;
  import regf_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import pep_mmacc_common_param_pkg::*;
  import pep_mmacc_splitc_sxt_pkg::*;
#(
  parameter bit INPUT_PIPE    = 1'b0,
  parameter int DATA_LATENCY  = 6    // Latency for read data to come back
)
(
  input  logic                                                   clk,        // clock
  input  logic                                                   s_rst_n,    // synchronous reset

  // Input data
  input  logic [PSI/2-1:0][R-1:0][MOD_Q_W-1:0]                   in0_data_data,
  input  logic                                                   in0_data_vld,
  output logic                                                   in0_data_rdy,

  input  logic [PSI/2-1:0][R-1:0][MOD_Q_W-1:0]                   in1_data_data,
  input  logic [PERM_W-1:0]                                      in1_data_perm_select,
  input  logic [CMD_X_W-1:0]                                     in1_data_cmd,
  input  logic                                                   in1_data_vld,
  output logic                                                   in1_data_rdy,

  // sxt <-> regfile
  // write
  output logic                                                   sxt_regf_wr_req_vld,
  input  logic                                                   sxt_regf_wr_req_rdy,
  output logic [REGF_WR_REQ_W-1:0]                               sxt_regf_wr_req,

  output logic [REGF_COEF_NB-1:0]                                sxt_regf_wr_data_vld,
  input  logic [REGF_COEF_NB-1:0]                                sxt_regf_wr_data_rdy,
  output logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0]                   sxt_regf_wr_data,

  input  logic                                                   regf_sxt_wr_ack,

  // CT done
  output logic                                                   sxt_seq_done, // pulse
  output logic [PID_W-1:0]                                       sxt_seq_done_pid,

  // For register if
  output logic                                                   sxt_rif_rcp_dur
);

//=================================================================================================
// localparam
//=================================================================================================
  localparam int RCP_FIFO_DEPTH = 3; // Should be >=2
  localparam int ACK_FIFO_DEPTH = 2; // Should be >=2 - depends on regfile ack latency

  localparam int HPSI = PSI/2;

  `PEP_MMACC_SPLITC_SXT_LOCALPARAM(R,PSI,DATA_LATENCY,REGF_COEF_NB,REGF_COEF_PER_URAM_WORD,REGF_BLWE_WORD_PER_RAM,DATA_THRESHOLD)

  localparam int REGF_WORD_THRESHOLD   = DATA_THRESHOLD / REGF_COEF_PER_URAM_WORD;
  localparam int REGF_CMD_NB           = ((REGF_BLWE_WORD_PER_RAM+1) + REGF_WORD_THRESHOLD - 1) / REGF_WORD_THRESHOLD; // +1 for the body
  localparam int REGF_CMD_NB_W         = $clog2(REGF_CMD_NB) == 0 ? 1 : $clog2(REGF_CMD_NB);
  localparam int REGF_LAST_CMD_WORD_NB = (REGF_BLWE_WORD_PER_RAM+1) % REGF_WORD_THRESHOLD; // +1 for the body

// ============================================================================================= --
// typedef
// ============================================================================================= --
  typedef struct packed {
    logic [PID_W-1:0]            pid;
    logic [REGF_REGID_W-1:0]     dst_rid;
    logic                        is_last;
  } rcp_cmd_t;

  localparam int RCP_CMD_W = $bits(rcp_cmd_t);

  typedef struct packed {
    logic [PID_W-1:0] pid;
    logic             is_last;
  } ack_cmd_t;

  localparam int ACK_CMD_W = $bits(ack_cmd_t);
//=================================================================================================
// Input pipe
//=================================================================================================
  logic [HPSI-1:0][R-1:0][MOD_Q_W-1:0] x2_0_subs_rot_data;
  logic                                x2_0_subs_vld;
  logic                                x2_0_subs_rdy;

  logic [HPSI-1:0][R-1:0][MOD_Q_W-1:0] x2_0_main_rot_data;
  logic [PERM_W-1:0]                   x2_0_main_data_perm_select;
  logic                                x2_0_main_vld;
  logic                                x2_0_main_rdy;
  cmd_x_t                              x2_0_cmd;

  generate
    if (INPUT_PIPE) begin : gen_in_pipe
      fifo_element #(
        .WIDTH          (HPSI*R*MOD_Q_W+PERM_W+CMD_X_W),
        .DEPTH          (2),
        .TYPE_ARRAY     (8'h12),
        .DO_RESET_DATA  (0),
        .RESET_DATA_VAL (0)
      ) in1_fifo_element (
        .clk     (clk),
        .s_rst_n(s_rst_n),

        .in_data ({in1_data_cmd,in1_data_perm_select,in1_data_data}),
        .in_vld  (in1_data_vld),
        .in_rdy  (in1_data_rdy),

        .out_data({x2_0_cmd,x2_0_main_data_perm_select,x2_0_main_rot_data}),
        .out_vld (x2_0_main_vld),
        .out_rdy (x2_0_main_rdy)
      );

      fifo_element #(
        .WIDTH          (HPSI*R*MOD_Q_W),
        .DEPTH          (2),
        .TYPE_ARRAY     (8'h12),
        .DO_RESET_DATA  (0),
        .RESET_DATA_VAL (0)
      ) in0_fifo_element (
        .clk     (clk),
        .s_rst_n(s_rst_n),

        .in_data (in0_data_data),
        .in_vld  (in0_data_vld),
        .in_rdy  (in0_data_rdy),

        .out_data(x2_0_subs_rot_data),
        .out_vld (x2_0_subs_vld),
        .out_rdy (x2_0_subs_rdy)
      );

    end
    else begin : gen_no_in_pipe
      assign x2_0_subs_vld              = in0_data_vld;
      assign in0_data_rdy               = x2_0_subs_rdy;
      assign x2_0_main_vld              = in1_data_vld;
      assign in1_data_rdy               = x2_0_main_rdy;
      assign x2_0_subs_rot_data         = in0_data_data;
      assign x2_0_main_rot_data         = in1_data_data;
      assign x2_0_main_data_perm_select = in1_data_perm_select;
      assign x2_0_cmd                   = in1_data_cmd;
    end
  endgenerate

  //== regf ack
  logic regf_wr_ack;
  always_ff @(posedge clk)
    if (!s_rst_n) regf_wr_ack <= 1'b0;
    else          regf_wr_ack <= regf_sxt_wr_ack;

//=================================================================================================
// X2_0 Permutation : last level
//=================================================================================================
  logic [1:0][HPSI-1:0][R-1:0][MOD_Q_W-1:0] x2_0_rot_data;
  logic                                     x2_0_perm_select;
  logic                                     x2_0_vld;
  logic                                     x2_0_rdy;

  assign x2_0_rot_data[0] = x2_0_subs_rot_data;
  assign x2_0_rot_data[1] = x2_0_main_rot_data;

  assign x2_0_perm_select = x2_0_main_data_perm_select[0];

  assign x2_0_vld = x2_0_subs_vld & x2_0_main_vld;
  assign x2_0_subs_rdy = x2_0_rdy & x2_0_main_vld;
  assign x2_0_main_rdy = x2_0_rdy & x2_0_subs_vld;

  logic [1:0][HPSI-1:0][R-1:0][MOD_Q_W-1:0] x2_0_perm_data;

  assign x2_0_perm_data[0] = x2_0_perm_select ? x2_0_rot_data[1] : x2_0_rot_data[0];
  assign x2_0_perm_data[1] = x2_0_perm_select ? x2_0_rot_data[0] : x2_0_rot_data[1];

// ============================================================================================= --
// X2_0 : Fork between data path and reception command path.
// ============================================================================================= --
  logic                               x2_vld;
  logic                               x2_rdy;

  logic                               x3_vld;
  logic                               x3_rdy;
  logic [PSI-1:0][R-1:0][MOD_Q_W-1:0] x3_perm_data;
  logic                               x3_is_body;

  rcp_cmd_t                           rcp_in_cmd;
  logic                               rcp_in_vld;
  logic                               rcp_in_rdy;

  logic                               x2_0_sos;
  logic                               x2_0_sosD;

  assign x2_0_sosD = x2_0_vld && x2_0_rdy ? x2_0_cmd.is_body : x2_0_sos;

  always_ff @(posedge clk)
    if (!s_rst_n) x2_0_sos <= 1'b1;
    else          x2_0_sos <= x2_0_sosD;

  assign rcp_in_cmd.pid     = x2_0_cmd.pid;
  assign rcp_in_cmd.dst_rid = x2_0_cmd.dst_rid;
  assign rcp_in_cmd.is_last = x2_0_cmd.is_last;

  assign x2_vld     = x2_0_vld & (rcp_in_rdy | ~x2_0_sos);
  assign rcp_in_vld = x2_0_vld & x2_rdy & x2_0_sos;
  assign x2_0_rdy   = (rcp_in_rdy | ~x2_0_sos) & x2_rdy;

  fifo_element #(
    .WIDTH          (PSI*R*MOD_Q_W+1),
    .DEPTH          (2),
    .TYPE_ARRAY     (8'h12),
    .DO_RESET_DATA  (0),
    .RESET_DATA_VAL (0)
  ) x2_fifo_element (
    .clk     (clk),
    .s_rst_n (s_rst_n),

    .in_data ({x2_0_cmd.is_body,x2_0_perm_data}),
    .in_vld  (x2_vld),
    .in_rdy  (x2_rdy),

    .out_data({x3_is_body,x3_perm_data}),
    .out_vld (x3_vld),
    .out_rdy (x3_rdy)
  );

// ============================================================================================= --
// X3 : Format for the output
// ============================================================================================= --
  logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0] x4_data;
  logic                                 x4_vld;
  logic                                 x4_rdy;

  generate
    if (RD_COEF_NB > REGF_COEF_NB) begin : gen_sr
      // Split the GRAM words into regf coef chunks
      logic [GRAM_CHUNK_NB-1:0][REGF_COEF_NB-1:0][MOD_Q_W-1:0] sr_data;
      logic [GRAM_CHUNK_NB-1:0][REGF_COEF_NB-1:0][MOD_Q_W-1:0] sr_data_tmp;
      logic [GRAM_CHUNK_NB-1:0][REGF_COEF_NB-1:0][MOD_Q_W-1:0] sr_dataD;

      logic [GRAM_CHUNK_NB_W-1:0]                              sr_out_cnt;
      logic [GRAM_CHUNK_NB_W-1:0]                              sr_out_cntD;
      logic                                                    sr_last_out_cnt;

      logic                                                    sr_avail;
      logic                                                    sr_availD;
      logic                                                    sr_is_body;
      logic                                                    sr_is_bodyD;

      logic                                                    x3_avail;

      assign x3_avail = x3_vld & x3_rdy;

      // Count the chunks
      assign sr_last_out_cnt = (sr_out_cnt == GRAM_CHUNK_NB-1) | sr_is_body;
      assign sr_out_cntD     = (x4_vld && x4_rdy) ? sr_last_out_cnt ? '0 : sr_out_cnt + 1 : sr_out_cnt;
      assign sr_availD       = x3_vld ? 1'b1 :
                               x4_vld && x4_rdy && sr_last_out_cnt ? 1'b0 : sr_avail;
      assign sr_is_bodyD     = x3_avail ? x3_is_body : sr_is_body;

      // Data shifter
      assign sr_data_tmp = sr_data >> (MOD_Q_W*REGF_COEF_NB); // Use this to avoid compilation warning due to parameter for the other branch.
      assign sr_dataD    = x3_avail ? x3_perm_data :
                           x4_vld && x4_rdy ? sr_data_tmp : sr_data;

      always_ff @(posedge clk)
        if (!s_rst_n) begin
          sr_avail   <= 1'b0;
          sr_out_cnt <= '0;
        end
        else begin
          sr_avail   <= sr_availD;
          sr_out_cnt <= sr_out_cntD;
        end

      always_ff @(posedge clk) begin
        sr_data    <= sr_dataD;
        sr_is_body <= sr_is_bodyD;
      end

      assign x4_data    = sr_data[0];
      assign x4_vld     = sr_avail;
      assign x3_rdy     = (sr_last_out_cnt & x4_rdy) | ~sr_avail;

 // pragma translate_off
      always_ff @(posedge clk)
        if (!s_rst_n) begin
          // do nothing
        end
        else begin
          assert(!x3_avail | !sr_avail | sr_last_out_cnt)
          else begin
            $fatal(1,"%t > ERROR: sr_data overflow!", $time);
          end
        end
 // pragma translate_on
    end
    else if (RD_COEF_NB < REGF_COEF_NB) begin : gen_acc
      // Accumulate GRAM words to form a BLWE chunk
      logic [CHUNK_GRAM_NB_W-1:0] acc_in_cnt;
      logic [CHUNK_GRAM_NB_W-1:0] acc_in_cntD;
      logic                       acc_last_in_cnt;

      logic                       x3_avail;

      assign x3_avail = x3_vld & x3_rdy;

      assign acc_last_in_cnt = (acc_in_cnt == (CHUNK_GRAM_NB-1)) | x3_is_body;
      assign acc_in_cntD     = x3_avail ? acc_last_in_cnt ? '0 : acc_in_cnt + 1 : acc_in_cnt;

      always_ff @(posedge clk)
        if (!s_rst_n) acc_in_cnt <= '0;
        else          acc_in_cnt <= acc_in_cntD;

      logic [CHUNK_GRAM_NB-1:1][RD_COEF_NB-1:0][MOD_Q_W-1:0] acc_data;
      logic [CHUNK_GRAM_NB-1:1][RD_COEF_NB-1:0][MOD_Q_W-1:0] acc_dataD;
      logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0]                  x4_data_tmp;

      if (CHUNK_GRAM_NB > 2) begin
        assign acc_dataD = x3_avail ? {x3_perm_data, acc_data[CHUNK_GRAM_NB-1:2]} : acc_data;
      end
      else begin
        assign acc_dataD = x3_avail ? x3_perm_data : acc_data;
      end

      assign x4_data_tmp = {x3_perm_data, acc_data};
      assign x4_data[0]  = x3_is_body ? x3_perm_data[0] : x4_data_tmp[0];
      assign x4_data[REGF_COEF_NB-1:1] = x4_data_tmp[REGF_COEF_NB-1:1];
      assign x4_vld      = acc_last_in_cnt & x3_vld;

      always_ff @(posedge clk)
        acc_data <= acc_dataD;

      assign x3_rdy = ~acc_last_in_cnt | x4_rdy;

    end
    else begin : gen_same_size
      // nothing to do
      assign x4_data     = x3_perm_data;
      assign x4_vld      = x3_vld;
      assign x3_rdy      = x4_rdy;
    end
  endgenerate

// ============================================================================================= --
// Data Buffer
// ============================================================================================= --
  logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0] x5_data;
  logic                                 x5_vld;
  logic                                 x5_rdy;

  fifo_reg #(
    .WIDTH       (REGF_COEF_NB*MOD_Q_W),
    .DEPTH       (DATA_THRESHOLD),
    .LAT_PIPE_MH ({1'b1, 1'b1})
  ) final_fifo (
    .clk     (clk),
    .s_rst_n (s_rst_n),

    .in_data (x4_data),
    .in_vld  (x4_vld),
    .in_rdy  (x4_rdy),

    .out_data(x5_data),
    .out_vld (x5_vld),
    .out_rdy (x5_rdy)
  );

// ============================================================================================= --
// Stream to seq
// ============================================================================================= --
  stream_to_seq #(
    .WIDTH(MOD_Q_W),
    .IN_NB(REGF_COEF_NB),
    .SEQ  (REGF_SEQ)
  ) stream_to_seq (
    .clk      (clk),
    .s_rst_n  (s_rst_n),

    .in_data  (x5_data),
    .in_vld   (x5_vld),
    .in_rdy   (x5_rdy),

    .out_data (sxt_regf_wr_data),
    .out_vld  (sxt_regf_wr_data_vld),
    .out_rdy  (sxt_regf_wr_data_rdy)
  );

// ============================================================================================= --
// Regfile request
// ============================================================================================= --
// --------------------------------------------------------------------------------------------- --
// Reception FIFO
// --------------------------------------------------------------------------------------------- --
  rcp_cmd_t rcp_out_cmd;
  logic     rcp_out_vld;
  logic     rcp_out_rdy;

  fifo_reg #(
    .WIDTH       (RCP_CMD_W),
    .DEPTH       (RCP_FIFO_DEPTH),
    .LAT_PIPE_MH ({1'b1, 1'b1})
  ) rcp_fifo_reg (
    .clk      (clk),
    .s_rst_n  (s_rst_n),

    .in_data  (rcp_in_cmd),
    .in_vld   (rcp_in_vld),
    .in_rdy   (rcp_in_rdy),

    .out_data (rcp_out_cmd),
    .out_vld  (rcp_out_vld),
    .out_rdy  (rcp_out_rdy)
  );

// --------------------------------------------------------------------------------------------- --
// Data count
// --------------------------------------------------------------------------------------------- --
  // From the output point of view
  // Counts the number of available regfile words in the output buffer.
  // Decrement the number of words that are / will be sent.
  // NOTE : Additional bit in r0_word_cnt. This is necessary for subs path.
  //        Indeed, the inc is given by subs_sxt. Pipes needed to transfer
  //        subs_sxt data to main_sxt have to be taken into account.
  logic [DATA_THRESHOLD_WW:0]        r0_word_cnt;
  logic [DATA_THRESHOLD_WW:0]        r0_word_cntD;
  logic                              r0_word_cnt_inc;
  logic [DATA_THRESHOLD_WW:0]        r0_word_cnt_dec;
  logic                              r0_do_dec;
  logic [DATA_THRESHOLD_WW-1:0]      r0_do_dec_val;

  assign r0_word_cnt_inc = x4_vld & x4_rdy;
  assign r0_word_cnt_dec = r0_do_dec ? r0_do_dec_val : '0;
  assign r0_word_cntD    = r0_word_cnt + r0_word_cnt_inc - r0_word_cnt_dec;

  always_ff @(posedge clk)
    if (!s_rst_n) r0_word_cnt <= '0;
    else          r0_word_cnt <= r0_word_cntD;

// --------------------------------------------------------------------------------------------- --
// Request
// --------------------------------------------------------------------------------------------- --
  logic [REGF_CMD_NB_W-1:0]         r0_cmd_cnt;
  logic [REGF_BLWE_WORD_CNT_W-1:0]  r0_word_add;

  logic [REGF_CMD_NB_W-1:0]         r0_cmd_cntD;
  logic [REGF_BLWE_WORD_CNT_W-1:0]  r0_word_addD;

  logic                             r0_last_cmd_cnt;
  logic                             r0_send_cmd;

  assign r0_last_cmd_cnt = r0_cmd_cnt == REGF_CMD_NB - 1;
  assign r0_cmd_cntD     = r0_send_cmd ? r0_last_cmd_cnt ? 0 : r0_cmd_cnt + 1 : r0_cmd_cnt;
  assign r0_word_addD    = r0_send_cmd ? r0_last_cmd_cnt ? '0 : r0_word_add + REGF_WORD_THRESHOLD : r0_word_add;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      r0_cmd_cnt  <= '0;
      r0_word_add <= '0;
    end
    else begin
      r0_cmd_cnt  <= r0_cmd_cntD;
      r0_word_add <= r0_word_addD;
    end

  // Check data availability
  logic r0_enough_word;
  assign r0_enough_word = (r0_word_cnt >= REGF_WORD_THRESHOLD)
                        | (r0_last_cmd_cnt & (r0_word_cnt >= REGF_LAST_CMD_WORD_NB));

  regf_wr_req_t r0_regf_req;
  logic         r0_regf_req_vld;
  logic         r0_regf_req_rdy;

  assign r0_regf_req_vld        = rcp_out_vld & r0_enough_word;
  assign r0_send_cmd            = r0_regf_req_vld & r0_regf_req_rdy;
  assign rcp_out_rdy            = r0_regf_req_rdy & r0_enough_word & r0_last_cmd_cnt;
  assign r0_regf_req.reg_id     = rcp_out_cmd.dst_rid;
  assign r0_regf_req.start_word = r0_word_add;
  assign r0_regf_req.word_nb_m1 = r0_last_cmd_cnt ? REGF_LAST_CMD_WORD_NB-1 : REGF_WORD_THRESHOLD-1;
  assign r0_do_dec              = r0_send_cmd;
  assign r0_do_dec_val          = r0_last_cmd_cnt ? REGF_LAST_CMD_WORD_NB : REGF_WORD_THRESHOLD;

  //== Send pid to ack fifo
  ack_cmd_t         ack_in_cmd;
  logic             ack_in_vld;
  logic             ack_in_rdy;

  assign ack_in_cmd.pid     = rcp_out_cmd.pid;
  assign ack_in_cmd.is_last = rcp_out_cmd.is_last;
  assign ack_in_vld         = rcp_out_rdy & rcp_out_vld;

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      if (ack_in_vld) begin
        assert(ack_in_rdy)
        else begin
          $fatal(1,"%t > ERROR: ack fifo is not ready when needed! Overflow!",$time);
        end
      end
    end
// pragma translate_on

// ---------------------------------------------------------------------------------------------- --
// Regfile request pipe
// ---------------------------------------------------------------------------------------------- --
  fifo_element #(
    .WIDTH          (REGF_WR_REQ_W),
    .DEPTH          (1),
    .TYPE_ARRAY     (4'h3), // TOREVIEW
    .DO_RESET_DATA  (0),
    .RESET_DATA_VAL (0)
  ) regf_req_fifo_element (
    .clk     (clk),
    .s_rst_n (s_rst_n),

    .in_data (r0_regf_req),
    .in_vld  (r0_regf_req_vld),
    .in_rdy  (r0_regf_req_rdy),

    .out_data(sxt_regf_wr_req),
    .out_vld (sxt_regf_wr_req_vld),
    .out_rdy (sxt_regf_wr_req_rdy)
  );

// ============================================================================================= --
// Command done
// ============================================================================================= --
// --------------------------------------------------------------------------------------------- --
// Acknowledge FIFO
// --------------------------------------------------------------------------------------------- --
  ack_cmd_t ack_out_cmd;
  logic     ack_out_vld;
  logic     ack_out_rdy;

  fifo_reg #(
    .WIDTH       (ACK_CMD_W),
    .DEPTH       (ACK_FIFO_DEPTH),
    .LAT_PIPE_MH ({1'b1, 1'b1})
  ) ack_fifo_reg (
    .clk      (clk),
    .s_rst_n  (s_rst_n),

    .in_data  (ack_in_cmd),
    .in_vld   (ack_in_vld),
    .in_rdy   (ack_in_rdy),

    .out_data (ack_out_cmd),
    .out_vld  (ack_out_vld),
    .out_rdy  (ack_out_rdy)
  );

  // Count the write acknowledges
  logic [REGF_CMD_NB_W-1:0] a0_ack_cnt;
  logic [REGF_CMD_NB_W-1:0] a0_ack_cntD;
  logic                     a0_last_ack_cnt;

  assign a0_last_ack_cnt = a0_ack_cnt == REGF_CMD_NB-1;
  assign a0_ack_cntD     = regf_wr_ack ? a0_last_ack_cnt ? '0: a0_ack_cnt + 1 : a0_ack_cnt;

  // Pid done
  logic sxt_seq_doneD;

  assign ack_out_rdy   = regf_wr_ack & a0_last_ack_cnt;
  assign sxt_seq_doneD = ack_out_rdy & ack_out_cmd.is_last;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      a0_ack_cnt   <= '0;
      sxt_seq_done <= 1'b0;
    end
    else begin
      a0_ack_cnt   <= a0_ack_cntD;
      sxt_seq_done <= sxt_seq_doneD;
    end

  always_ff @(posedge clk)
    sxt_seq_done_pid <= ack_out_cmd.pid;

// pragma translate_off
  always_ff @(posedge clk)
    if (ack_out_rdy)
      assert(ack_out_vld)
      else begin
        $fatal(1,"%t > ERROR: ack fifo not valid when needed!",$time);
      end
// pragma translate_on

// ============================================================================================= --
// Info for register if
// ============================================================================================= --
  logic sxt_rif_rcp_durD;

  assign sxt_rif_rcp_durD        = (rcp_out_vld && rcp_out_rdy) ? 1'b0 : rcp_out_vld;

  always_ff @(posedge clk)
    if (!s_rst_n) sxt_rif_rcp_dur        <= 1'b0;
    else          sxt_rif_rcp_dur        <= sxt_rif_rcp_durD;

endmodule
