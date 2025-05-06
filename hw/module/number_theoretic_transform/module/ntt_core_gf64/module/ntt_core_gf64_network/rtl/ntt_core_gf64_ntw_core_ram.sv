// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module handles the RAM of the ntt_core_gf64 network.
//
// ==============================================================================================

`include "ntt_core_gf64_ntw_macro_inc.sv"

module ntt_core_gf64_ntw_core_ram
  import pep_common_param_pkg::*;
  import param_tfhe_pkg::*;
  import ntt_core_common_param_pkg::*;
  import ntt_core_gf64_common_param_pkg::*;
#(
  parameter int    RDX_CUT_ID      = 0, // increasing numbering for FWD, decreasing for BWD
                                        // FWD : 1 means ngc
                                        // BWD : 0 means ngc
                                        // Column that precedes the network.
  parameter bit BWD         = 1'b0,
  parameter int OP_W        = 66,
  parameter int RAM_LATENCY = 2,
  parameter int TOKEN_W     = 2 // Store up to 2**TOKEN_W working block
)
(
  input  logic                             clk,        // clock
  input  logic                             s_rst_n,    // synchronous reset

  // RAM
  input  logic [PSI*R-1:0][OP_W-1:0]       ram_wr_data,
  input  logic [PSI*R-1:0]                 ram_wr_avail,
  input  logic [PSI*R-1:0][STG_ITER_W-1:0] ram_wr_add, // Only ITER_W bits are used.
  input  logic [INTL_L_W-1:0]              ram_wr_intl_idx,
  input  logic [TOKEN_W-1:0]               ram_wr_token,

  // Token
  output logic                             token_release,

  // Command FIFO
  input  logic                             cmd_fifo_avail,
  input  logic [BPBS_ID_W-1:0]             cmd_fifo_pbs_id,
  input  logic [INTL_L_W-1:0]              cmd_fifo_intl_idx,
  input  logic                             cmd_fifo_eob,

  // Output data
  output logic [PSI*R-1:0][OP_W-1:0]       out_data,
  output logic [PSI*R-1:0]                 out_avail,
  output logic                             out_sob,
  output logic                             out_eob,
  output logic                             out_sol,
  output logic                             out_eol,
  output logic                             out_sos,
  output logic                             out_eos,
  output logic [BPBS_ID_W-1:0]             out_pbs_id
);

  // ============================================================================================== --
  // localparam
  // ============================================================================================== --
  `NTT_CORE_GF64_NTW_LOCALPARAM(RDX_CUT_ID,BWD,R,PSI)

  localparam int TOKEN_NB    = 2**TOKEN_W;

  localparam int LVL_NB      = BWD ? GLWE_K_P1 : INTL_L;
  localparam int LVL_W       = BWD ? GLWE_K_P1_W : INTL_L_W;

  localparam int SR_DEPTH    = RAM_LATENCY + 1; // +1 : RAM input reg

  // ============================================================================================== --
  // type
  // ============================================================================================== --
  typedef struct packed {
    logic                 eob;
    logic [BPBS_ID_W-1:0] pbs_id;
    logic [INTL_L_W-1:0]  intl_idx;
  } cmd_t;

  // To describe the RAM address
  typedef struct packed {
    logic [LVL_W-1:0]    intl_idx; // In MSB, because not necessarily a power of 2
    logic [TOKEN_W-1:0]  token;
    logic [ITER_W-1:0]   iter;
  } ram_add_t;

  typedef struct packed {
    logic                 sob;
    logic                 eob;
    logic                 sol;
    logic                 eol;
    logic                 sos;
    logic                 eos;
    logic [BPBS_ID_W-1:0] pbs_id;
  } ctrl_t;

  localparam int RAM_ADD_W    = $bits(ram_add_t);
  localparam int RAM_DEPTH    = 2 ** RAM_ADD_W;

  // ============================================================================================== --
  // Command FIFO
  // ============================================================================================== --
  cmd_t cfifo_in_cmd;
  logic cfifo_in_vld;
  logic cfifo_in_rdy;

  cmd_t cfifo_out_cmd;
  logic cfifo_out_vld;
  logic cfifo_out_rdy;

  assign cfifo_in_cmd.eob      = cmd_fifo_eob;
  assign cfifo_in_cmd.pbs_id   = cmd_fifo_pbs_id;
  assign cfifo_in_cmd.intl_idx = cmd_fifo_intl_idx;

  assign cfifo_in_vld = cmd_fifo_avail;

  fifo_reg #(
    .WIDTH      ($bits(cmd_t)),
    .DEPTH      (TOKEN_NB*LVL_NB),
    .LAT_PIPE_MH(2'b11)
  ) cmd_fifo(
    .clk      (clk),
    .s_rst_n  (s_rst_n),

    .in_data  (cfifo_in_cmd),
    .in_vld   (cfifo_in_vld),
    .in_rdy   (cfifo_in_rdy),

    .out_data (cfifo_out_cmd),
    .out_vld  (cfifo_out_vld),
    .out_rdy  (cfifo_out_rdy)
  );

// pragma translate_off
  always_ff @(posedge clk)
    if (cfifo_in_vld) begin
      assert(cfifo_in_rdy)
      else begin
        $fatal(1,"%t > ERROR: cmd_fifo overflow : not ready for input command.", $time);
      end
    end
// pragma translate_on

  // ============================================================================================== --
  // RAM
  // ============================================================================================== --
  logic                         ram_rd_en;
  ram_add_t                     ram_rd_add_s;
  logic [C-1:0][OP_W-1:0]       ram_rd_data;
  logic [C-1:0]                 ram_rd_data_avail;

  logic [C-1:0]                 ram_wr_en;
  ram_add_t [C-1:0]             ram_wr_add_s;

  always_comb
    for (int i=0; i<C; i=i+1) begin
      ram_wr_add_s[i].intl_idx = ram_wr_intl_idx[LVL_W-1:0]; // Truncated
      ram_wr_add_s[i].token    = ram_wr_token;
      ram_wr_add_s[i].iter     = ram_wr_add[i][ITER_W-1:0]; // Truncated
    end

  assign ram_wr_en = ram_wr_avail;

  generate
    for (genvar gen_i=0; gen_i<C; gen_i=gen_i+1) begin : gen_ram_loop
      logic [RAM_LATENCY-1:0] ram_rd_data_avail_sr;
      logic [RAM_LATENCY-1:0] ram_rd_data_avail_srD;

      assign ram_rd_data_avail[gen_i] = ram_rd_data_avail_sr[RAM_LATENCY-1];

      assign ram_rd_data_avail_srD[0] = ram_rd_en;
      if (RAM_LATENCY>1) begin
        assign ram_rd_data_avail_srD[RAM_LATENCY-1:1] = ram_rd_data_avail_sr[RAM_LATENCY-2:0];
      end

      always_ff @(posedge clk)
        if (!s_rst_n) ram_rd_data_avail_sr <= '0;
        else          ram_rd_data_avail_sr <= ram_rd_data_avail_srD;

      ram_wrapper_1R1W #(
        .WIDTH            (OP_W),
        .DEPTH            (RAM_DEPTH),
        .RD_WR_ACCESS_TYPE(1),
        .KEEP_RD_DATA     (0),
        .RAM_LATENCY      (RAM_LATENCY)
      ) ntt_ntw_ram (
        .clk    (clk),
        .s_rst_n(s_rst_n),

        .rd_en  (ram_rd_en),
        .rd_add (ram_rd_add_s),
        .rd_data(ram_rd_data[gen_i]),

        .wr_en  (ram_wr_en[gen_i]),
        .wr_add (ram_wr_add_s[gen_i]),
        .wr_data(ram_wr_data[gen_i])
      );
    end // gen_ram_loop
  endgenerate

  // ============================================================================================== --
  // RAM read
  // ============================================================================================== --
  // ---------------------------------------------------------------------------------------------- --
  // Counters
  // ---------------------------------------------------------------------------------------------- --
  // Keep track of :
  //   wb       : current working block
  //   iter     : current iteration inside the working block
  //   intl_idx : current level index

  logic [LVL_W-1:0]   s0_intl_idx;
  logic [WB_W-1:0]    s0_wb; // working block
  logic [ITER_W-1:0]  s0_iter;

  logic [LVL_W-1:0]   s0_intl_idxD;
  logic [WB_W-1:0]    s0_wbD; // working block
  logic [ITER_W-1:0]  s0_iterD;

  logic               s0_first_intl_idx;
  logic               s0_first_wb;
  logic               s0_first_iter;

  logic               s0_last_intl_idx;
  logic               s0_last_wb;
  logic               s0_last_iter;

  logic               s0_end_of_wb;

  logic               s0_rd_en;

  assign s0_first_intl_idx= s0_intl_idx == 0;
  assign s0_first_iter    = s0_iter == 0;
  assign s0_first_wb      = s0_wb == 0;

  assign s0_last_intl_idx = s0_intl_idx == LVL_NB-1;
  assign s0_last_iter     = s0_iter == ITER_NB-1;
  assign s0_last_wb       = s0_wb == WB_NB-1;

  assign s0_intl_idxD     = s0_rd_en ? s0_last_intl_idx ? '0 : s0_intl_idx + 1 : s0_intl_idx;
  assign s0_iterD         = (s0_rd_en && s0_last_intl_idx) ? s0_last_iter ? '0 : s0_iter + 1 : s0_iter;
  assign s0_wbD           = (s0_rd_en && s0_last_intl_idx && s0_last_iter) ? s0_last_wb ? '0 : s0_wb + 1 : s0_wb;

  assign s0_end_of_wb     = s0_last_intl_idx & s0_last_iter;

  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      s0_wb       <= '0;
      s0_iter     <= '0;
      s0_intl_idx <= '0;
    end else begin
      s0_wb       <= s0_wbD;
      s0_iter     <= s0_iterD;
      s0_intl_idx <= s0_intl_idxD;
    end
  end

  // ---------------------------------------------------------------------------------------------- --
  // Parse cfifo
  // ---------------------------------------------------------------------------------------------- --
  logic s0_sob;
  logic s0_sobD;

  ctrl_t s0_ctrl;

  assign s0_ctrl.sol = s0_first_intl_idx;
  assign s0_ctrl.eol = s0_last_intl_idx;
  assign s0_ctrl.sos = s0_first_iter & s0_first_wb & s0_first_intl_idx;
  assign s0_ctrl.eos = s0_last_iter & s0_last_wb & s0_last_intl_idx;
  assign s0_ctrl.sob = s0_sob;
  assign s0_ctrl.pbs_id = cfifo_out_cmd.pbs_id;

  // There is 1 cmd per level in the FIFO.
  // The presence of the command inside the FIFO indicates that the whole level has been received.
  // Accept the first levels' command once available. => The corresponding levels are present.
  // Sample the last level's command only at the end of the stage.
  assign cfifo_out_rdy = (~s0_last_intl_idx & s0_first_iter) | (s0_last_intl_idx & s0_last_iter);

  // Prepare next
  assign s0_sobD     = cfifo_out_vld ? (s0_ctrl.eos && cfifo_out_cmd.eob) ? 1'b1 : 1'b0 : s0_sob;
  assign s0_ctrl.eob = cfifo_out_cmd.eob & s0_ctrl.eos; // Since all the levels'commands except the last one have been parsed
                                                 // at the beginning of the stage.
                                                 // cfifo_out_cmd.eob is the one of the command last level. Take it into account only
                                                 // at the end of the stage.
  always_ff @(posedge clk)
    if (!s_rst_n) s0_sob      <= 1'b1;
    else          s0_sob      <= s0_sobD;

  // ---------------------------------------------------------------------------------------------- --
  // Token
  // ---------------------------------------------------------------------------------------------- --
  logic [TOKEN_W-1:0] rd_token;
  logic [TOKEN_W-1:0] rd_tokenD;

  assign token_release = (cfifo_out_vld & cfifo_out_rdy & s0_end_of_wb);

  assign rd_tokenD = token_release ? rd_token + 1 : rd_token;

  always_ff @(posedge clk)
    if (!s_rst_n) rd_token <= '0;
    else          rd_token <= rd_tokenD;

  // ---------------------------------------------------------------------------------------------- --
  // RAM read request
  // ---------------------------------------------------------------------------------------------- --
  logic      ram_rd_enD;
  ram_add_t  ram_rd_add_sD;

  assign s0_rd_en               = cfifo_out_vld;
  assign ram_rd_enD             = cfifo_out_vld;
  assign ram_rd_add_sD.iter     = s0_iter;
  assign ram_rd_add_sD.intl_idx = s0_intl_idx;
  assign ram_rd_add_sD.token    = rd_token;

  always_ff @(posedge clk)
    if (!s_rst_n) ram_rd_en <= 1'b0;
    else          ram_rd_en <= ram_rd_enD;

  always_ff @(posedge clk)
    ram_rd_add_s <= ram_rd_add_sD;

  // ---------------------------------------------------------------------------------------------- --
  // Output
  // ---------------------------------------------------------------------------------------------- --
  ctrl_t [SR_DEPTH-1:0] s1_ctrl_sr;
  ctrl_t [SR_DEPTH-1:0] s1_ctrl_srD;

  assign s1_ctrl_srD[0] = s0_ctrl;
  generate
    if (SR_DEPTH > 1) begin : gen_s1_sr
      assign s1_ctrl_srD[SR_DEPTH-1:1] = s1_ctrl_sr[SR_DEPTH-2:0];
    end
  endgenerate

  always_ff @(posedge clk)
    s1_ctrl_sr <= s1_ctrl_srD;

  // Register RAM output
  ctrl_t                  s2_ctrl;
  logic [C-1:0]           s2_avail;
  logic [C-1:0][OP_W-1:0] s2_data;

  always_ff @(posedge clk)
    if (!s_rst_n) s2_avail <= '0;
    else          s2_avail <= ram_rd_data_avail;

  always_ff @(posedge clk) begin
    s2_data <= ram_rd_data;
    s2_ctrl <= s1_ctrl_sr[SR_DEPTH-1];
  end

  assign out_data       = s2_data;
  assign out_sob        = s2_ctrl.sob   ;
  assign out_eob        = s2_ctrl.eob   ;
  assign out_sol        = s2_ctrl.sol   ;
  assign out_eol        = s2_ctrl.eol   ;
  assign out_sos        = s2_ctrl.sos   ;
  assign out_eos        = s2_ctrl.eos   ;
  assign out_pbs_id     = s2_ctrl.pbs_id;
  assign out_avail      = s2_avail;

  // ============================================================================================== --
  // Assertion
  // ============================================================================================== --
// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      if (cfifo_out_vld && cfifo_out_rdy) begin
        assert (cfifo_out_cmd.intl_idx == s0_intl_idx)
        else begin
          $fatal(1,"%t > ERROR: Interleaved level mismatch: cmd=0x%x, cnt=0x%x", $time,
              cfifo_out_cmd.intl_idx, s0_intl_idx);
        end
      end
    end
// pragma translate_on

endmodule
