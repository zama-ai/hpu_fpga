// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the management of the blind rotation key (bsk).
// It delivers the keys at the pace given by the core.
// The host fills the values. They should be valid before running the blind rotation.
// Note that the keys should be given in reverse order on N basis.
// Also note that a unique bsk is used for the process.
// Xilinx UltraRAM are used : (72x4096) RAMs.
//
// This module handles a cut.
// ==============================================================================================

module bsk_mgr_cut
  import param_tfhe_pkg::*;
  import top_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import ntt_core_common_param_pkg::*;
  import bsk_mgr_common_param_pkg::*;
#(
  parameter  int OP_W        = 64,
  parameter  int RAM_RD_NB   = 1,
  parameter  int RAM_LATENCY = 3 // URAM
)
(
  input  logic                                                 clk,        // clock
  input  logic                                                 s_rst_n,    // synchronous reset

  output logic [BSK_CUT_FCOEF_NB-1:0][GLWE_K_P1-1:0][OP_W-1:0] bsk,
  output logic [BSK_CUT_FCOEF_NB-1:0][GLWE_K_P1-1:0]           bsk_vld,
  input  logic [BSK_CUT_FCOEF_NB-1:0][GLWE_K_P1-1:0]           bsk_rdy,

  // Write interface
  input  logic                                                 wr_en, // Write coefficients for 1 (stage iter,GLWE) at a time.
  input  logic [BSK_CUT_FCOEF_NB-1:0][OP_W-1:0]                wr_data,
  input  logic [BSK_RAM_ADD_W-1:0]                             wr_add,
  input  logic [GLWE_K_P1_W-1:0]                               wr_g_idx,

  // Batch cmd
  input  logic [BR_BATCH_CMD_W-1:0]                            s0_batch_cmd,
  input  logic [BSK_RAM_ADD_W-1:0]                             s0_batch_add_ofs,
  input  logic                                                 s0_batch_cmd_vld,
  output logic                                                 s0_batch_cmd_rdy
);

  // =================================================================================== --
  // localparam
  // =================================================================================== --
  localparam int RAM_LATENCY_L  = RAM_LATENCY + 1; // +1 to register read command
  localparam int BUF_DEPTH      = RAM_LATENCY_L + 2;
  localparam int LOC_NB         = RAM_LATENCY_L + BUF_DEPTH;
  localparam int LOC_W          = $clog2(LOC_NB);
  localparam int RAM_W          = OP_W * RAM_RD_NB;

  // =================================================================================== --
  // batch_cmd FIFO (final)
  // =================================================================================== --
  br_batch_cmd_t            s1_batch_cmd;
  logic [BSK_RAM_ADD_W-1:0] s1_batch_add_ofs;
  logic                     s1_batch_cmd_vld;
  logic                     s1_batch_cmd_rdy;
  fifo_element #(
    .WIDTH          (BR_BATCH_CMD_W + BSK_RAM_ADD_W),
    .DEPTH          (1),
    .TYPE_ARRAY     (1),
    .DO_RESET_DATA  (0),
    .RESET_DATA_VAL (0)
  ) fifo_element_cmd (
    .clk     (clk),
    .s_rst_n (s_rst_n),

    .in_data ({s0_batch_add_ofs,s0_batch_cmd}),
    .in_vld  (s0_batch_cmd_vld),
    .in_rdy  (s0_batch_cmd_rdy),

    .out_data({s1_batch_add_ofs,s1_batch_cmd}),
    .out_vld (s1_batch_cmd_vld),
    .out_rdy (s1_batch_cmd_rdy)
  );

  // =================================================================================== --
  // Read
  // =================================================================================== --
  // Use a common control for all the RAMs in the cut.
  // For a g_idx to the next one, use systolic architecture.
  // ----------------------------------------------------------------------------------- --
  // Counters
  // ----------------------------------------------------------------------------------- --
  logic [STG_ITER_W-1:0] s1_stg_iter;
  logic [STG_ITER_W-1:0] s1_stg_iterD;
  logic [BPBS_ID_W-1:0]  s1_pbs_id;
  logic [BPBS_ID_W-1:0]  s1_pbs_idD;
  logic [INTL_L_W-1:0]   s1_intl_idx;
  logic [INTL_L_W-1:0]   s1_intl_idxD;
  logic                  s1_first_stg_iter;
  logic                  s1_first_intl_idx;
  logic                  s1_first_pbs_id;
  logic                  s1_last_stg_iter;
  logic                  s1_last_intl_idx;
  logic                  s1_last_pbs_id;
  logic                  s1_do_read;

  assign s1_intl_idxD = s1_do_read ? s1_last_intl_idx ? '0 : s1_intl_idx + 1 : s1_intl_idx;
  assign s1_stg_iterD = (s1_do_read && s1_last_intl_idx) ? s1_last_stg_iter ?
                            '0 : s1_stg_iter + 1 : s1_stg_iter;
  assign s1_pbs_idD   = (s1_do_read && s1_last_intl_idx && s1_last_stg_iter)?
                            s1_last_pbs_id ? '0 : s1_pbs_id + 1 : s1_pbs_id;

  assign s1_first_intl_idx = (s1_intl_idx == '0);
  assign s1_first_stg_iter = (s1_stg_iter == '0);
  assign s1_first_pbs_id   = (s1_pbs_id == '0);
  assign s1_last_intl_idx  = (s1_intl_idx == (INTL_L-1));
  assign s1_last_stg_iter  = (s1_stg_iter == (STG_ITER_NB-1));
  assign s1_last_pbs_id    = (s1_pbs_id == (s1_batch_cmd.pbs_nb -1));

  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      s1_intl_idx <= '0;
      s1_stg_iter <= '0;
      s1_pbs_id   <= '0;
    end
    else begin
      s1_intl_idx <= s1_intl_idxD;
      s1_stg_iter <= s1_stg_iterD;
      s1_pbs_id   <= s1_pbs_idD;
    end
  end

  assign s1_batch_cmd_rdy = s1_do_read & s1_last_intl_idx & s1_last_stg_iter & s1_last_pbs_id;

  // ----------------------------------------------------------------------------------- --
  // Read pointer
  // ----------------------------------------------------------------------------------- --
  logic [BSK_RAM_ADD_W-1:0]  s1_rp;
  logic [BSK_RAM_ADD_W-1:0]  s1_rpD;

  assign s1_rpD = s1_do_read ?
                  (s1_last_intl_idx && s1_last_stg_iter) ? '0 : s1_rp + 1 : s1_rp;

  always_ff @(posedge clk)
    if (!s_rst_n) s1_rp <= '0;
    else          s1_rp <= s1_rpD;

  // ------------------------------------------------------------------------------- --
  // Read
  // ------------------------------------------------------------------------------- --
  // Read in RAM when there is a free location in the output buffer.
  logic [RAM_LATENCY_L-1:0] ram_data_avail_dly;
  logic [RAM_LATENCY_L-1:0] ram_data_avail_dlyD;
  logic [LOC_W-1:0]         s1_data_cnt;
  logic [LOC_NB-1:0]        s1_data_en;
  logic [BUF_DEPTH-1:0]     buf_en;
  logic                     buf_in_avail;

  assign ram_data_avail_dlyD[0] = s1_do_read;
  if (RAM_LATENCY_L > 1) begin : ram_latency_gt_1_gen
    assign ram_data_avail_dlyD[RAM_LATENCY_L-1:1] = ram_data_avail_dly[RAM_LATENCY_L-2:0];
  end

  always_ff @(posedge clk)
    if (!s_rst_n) ram_data_avail_dly <= '0;
    else          ram_data_avail_dly <= ram_data_avail_dlyD;

  assign s1_data_en =  {buf_en, ram_data_avail_dly};
  always_comb begin
    logic [LOC_W-1:0] cnt;
    cnt = '0;
    for (int i=0; i<LOC_NB; i=i+1) begin
      cnt = cnt + s1_data_en[i];
    end
    s1_data_cnt = cnt;
  end

  assign s1_do_read = (s1_data_cnt < BUF_DEPTH) & s1_batch_cmd_vld;

  // Buffer input
  assign buf_in_avail = ram_data_avail_dly[RAM_LATENCY_L-1];

  // ------------------------------------------------------------------------------- --
  // Command
  // ------------------------------------------------------------------------------- --
  node_cmd_t node_cmd;
  logic                     ram_rd_enD;
  logic [BSK_RAM_ADD_W-1:0] ram_rd_addD;

  assign ram_rd_addD = s1_rp + s1_batch_add_ofs;
  assign ram_rd_enD  = s1_do_read;

  assign node_cmd.buf_in_avail = buf_in_avail;
  assign node_cmd.ram_rd_enD   = ram_rd_enD ;
  assign node_cmd.ram_rd_addD  = ram_rd_addD;

  // ------------------------------------------------------------------------------- --
  // nodes
  // ------------------------------------------------------------------------------- --
  logic [GLWE_K_P1-1:0][BSK_CUT_FCOEF_NB-1:0][OP_W-1:0]                          bsk_tmp;
  logic [GLWE_K_P1-1:0][BSK_CUT_FCOEF_NB-1:0]                                    bsk_vld_tmp;
  logic [GLWE_K_P1-1:0][BSK_CUT_FCOEF_NB-1:0]                                    bsk_rdy_tmp;
  logic [GLWE_K_P1-1:0][BSK_CUT_FCOEF_NB/RAM_RD_NB-1:0][BUF_DEPTH-1:0]           buf_en_tmp;

  node_cmd_t [GLWE_K_P1-1:0][BSK_CUT_FCOEF_NB/RAM_RD_NB-1:0]                     prev_node_cmd;
  node_cmd_t [GLWE_K_P1-1:0][BSK_CUT_FCOEF_NB/RAM_RD_NB-1:0]                     next_x_node_cmd;

  logic [GLWE_K_P1-1:0][BSK_CUT_FCOEF_NB/RAM_RD_NB-1:0]                          prev_wr_en;
  logic [GLWE_K_P1-1:0][BSK_CUT_FCOEF_NB/RAM_RD_NB-1:0][RAM_RD_NB-1:0][OP_W-1:0] prev_wr_data;
  logic [GLWE_K_P1-1:0][BSK_CUT_FCOEF_NB/RAM_RD_NB-1:0][BSK_RAM_ADD_W-1:0]       prev_wr_add;
  logic [GLWE_K_P1-1:0][BSK_CUT_FCOEF_NB/RAM_RD_NB-1:0][GLWE_K_P1_W-1:0]         prev_wr_g_idx;

  logic [GLWE_K_P1-1:0][BSK_CUT_FCOEF_NB/RAM_RD_NB-1:0]                          next_x_wr_en;
  logic [GLWE_K_P1-1:0][BSK_CUT_FCOEF_NB/RAM_RD_NB-1:0][RAM_RD_NB-1:0][OP_W-1:0] next_x_wr_data;
  logic [GLWE_K_P1-1:0][BSK_CUT_FCOEF_NB/RAM_RD_NB-1:0][BSK_RAM_ADD_W-1:0]       next_x_wr_add;
  logic [GLWE_K_P1-1:0][BSK_CUT_FCOEF_NB/RAM_RD_NB-1:0][GLWE_K_P1_W-1:0]         next_x_wr_g_idx;

  assign prev_node_cmd[0]             = {BSK_CUT_FCOEF_NB/RAM_RD_NB{node_cmd}};
  assign prev_node_cmd[GLWE_K_P1-1:1] = next_x_node_cmd[GLWE_K_P1-2:0];

  assign prev_wr_en[0]                = {BSK_CUT_FCOEF_NB/RAM_RD_NB{wr_en}};
  assign prev_wr_data[0]              = wr_data;
  assign prev_wr_add[0]               = {BSK_CUT_FCOEF_NB/RAM_RD_NB{wr_add}};
  assign prev_wr_g_idx[0]             = {BSK_CUT_FCOEF_NB/RAM_RD_NB{wr_g_idx}};
  assign prev_wr_en[GLWE_K_P1-1:1]    = next_x_wr_en[GLWE_K_P1-2:0];
  assign prev_wr_data[GLWE_K_P1-1:1]  = next_x_wr_data[GLWE_K_P1-2:0];
  assign prev_wr_add[GLWE_K_P1-1:1]   = next_x_wr_add[GLWE_K_P1-2:0];
  assign prev_wr_g_idx[GLWE_K_P1-1:1] = next_x_wr_g_idx[GLWE_K_P1-2:0];

  assign buf_en = buf_en_tmp[0][0];

  for (genvar gen_g=0; gen_g < GLWE_K_P1; gen_g=gen_g+1) begin : gen_g_loop
    for (genvar gen_i=0; gen_i < BSK_CUT_FCOEF_NB/RAM_RD_NB; gen_i=gen_i+1) begin : gen_fcoef_loop
    bsk_mgr_node
    #(
      .OP_W          (OP_W),
      .RAM_RD_NB     (RAM_RD_NB),
      .G_ID          (gen_g),
      .RAM_LATENCY   (RAM_LATENCY),
      .BUF_DEPTH     (BUF_DEPTH)
    ) bsk_mgr_node (
      .clk             (clk),
      .s_rst_n         (s_rst_n),

      .bsk             (bsk_tmp[gen_g][gen_i*RAM_RD_NB+:RAM_RD_NB]),
      .bsk_vld         (bsk_vld_tmp[gen_g][gen_i*RAM_RD_NB+:RAM_RD_NB]),
      .bsk_rdy         (bsk_rdy_tmp[gen_g][gen_i*RAM_RD_NB+:RAM_RD_NB]),

      .prev_node_cmd   (prev_node_cmd[gen_g][gen_i]),
      .next_x_node_cmd (next_x_node_cmd[gen_g][gen_i]),

      .prev_wr_en      (prev_wr_en[gen_g][gen_i]),
      .prev_wr_data    (prev_wr_data[gen_g][gen_i]),
      .prev_wr_add     (prev_wr_add[gen_g][gen_i]),
      .prev_wr_g_idx   (prev_wr_g_idx[gen_g][gen_i]),

      .next_x_wr_en    (next_x_wr_en[gen_g][gen_i]),
      .next_x_wr_data  (next_x_wr_data[gen_g][gen_i]),
      .next_x_wr_add   (next_x_wr_add[gen_g][gen_i]),
      .next_x_wr_g_idx (next_x_wr_g_idx[gen_g][gen_i]),

      .buf_en          (buf_en_tmp[gen_g][gen_i])
    );
    end // gen_i
  end // gen_g

  // ------------------------------------------------------------------------------- --
  // Reorder
  // ------------------------------------------------------------------------------- --
  always_comb
    for (int g=0; g<GLWE_K_P1; g=g+1)
      for (int i=0; i<BSK_CUT_FCOEF_NB; i=i+1) begin
        bsk[i][g]         = bsk_tmp[g][i];
        bsk_vld[i][g]     = bsk_vld_tmp[g][i];
        bsk_rdy_tmp[g][i] = bsk_rdy[i][g];
      end

  // ------------------------------------------------------------------------------- --
  // Assertions
  // ------------------------------------------------------------------------------- --
// pragma translate_off
  logic [GLWE_K_P1-1:0][BSK_CUT_FCOEF_NB/RAM_RD_NB-1:0][BUF_DEPTH-1:0] buf_en_tmp_0_sr;
  logic [GLWE_K_P1-1:0][BSK_CUT_FCOEF_NB/RAM_RD_NB-1:0][BUF_DEPTH-1:0] buf_en_tmp_0_srD;

  assign buf_en_tmp_0_srD = {buf_en_tmp_0_sr[GLWE_K_P1-2:0],buf_en_tmp[0]};

  always_ff @(posedge clk)
    if (!s_rst_n) buf_en_tmp_0_sr <= '0;
    else          buf_en_tmp_0_sr <= buf_en_tmp_0_srD;

  logic _buf_en_coherent;
  always_comb begin
    logic [BUF_DEPTH-1:0] buf_en_ref;
    _buf_en_coherent = 1'b1;
    for (int g=1; g<GLWE_K_P1; g=g+1)
      for (int i=0; i<BSK_CUT_FCOEF_NB/RAM_RD_NB; i=i+1)
        _buf_en_coherent = _buf_en_coherent & (buf_en_tmp_0_sr[g-1][i] == buf_en_tmp[g][i]);
  end

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      assert(_buf_en_coherent)
      else begin
        $fatal(1,"%t > ERROR: buf_en are incoherent!", $time);
      end

      for (int g=0; g<GLWE_K_P1; g=g+1) begin
        assert(bsk_vld_tmp[g] == '0 || bsk_vld_tmp[g] == '1)
        else begin
          $fatal(1,"%t > ERROR: bsk_vld_tmp are incoherent!", $time);
        end
        assert(bsk_rdy_tmp[g] == '0 || bsk_rdy_tmp[g] == '1)
        else begin
          $fatal(1,"%t > ERROR: bsk_rdy_tmp are incoherent!", $time);
        end
      end
    end
// pragma translate_on

endmodule
