// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the reading of GLWE in regfile for the blind rotation.
// Note that we only read the "body" polynomial. Indeed, the mask part is 0.
// The GLWE is then written in the GRAM.
//
// To ease the P&R the GRAM is split into 4, corresponding to 1/4 of the R*PSI coefficients.
// ==============================================================================================

module pep_ldg_splitc_entry
  import axi_if_common_param_pkg::*;
  import axi_if_glwe_axi_pkg::*;
  import param_tfhe_pkg::*;
  import top_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import ntt_core_common_param_pkg::*;
(
  input  logic                                                   clk,        // clock
  input  logic                                                   s_rst_n,    // synchronous reset

  input  logic [AXI4_ADD_W-1:0]                                  gid_offset, // quasi static

  // pep_seq : command
  input  logic [LOAD_GLWE_CMD_W-1:0]                             seq_ldg_cmd,
  input  logic                                                   seq_ldg_vld,
  output logic                                                   seq_ldg_rdy,
  output logic                                                   ldg_seq_done,

  // AXI4 Master interface
  // NB: Only AXI Read channel exposed here
  output logic [AXI4_ID_W-1:0]                                   m_axi4_arid,
  output logic [AXI4_ADD_W-1:0]                                  m_axi4_araddr,
  output logic [7:0]                                             m_axi4_arlen,
  output logic [2:0]                                             m_axi4_arsize,
  output logic [1:0]                                             m_axi4_arburst,
  output logic                                                   m_axi4_arvalid,
  input  logic                                                   m_axi4_arready,
  input  logic [AXI4_ID_W-1:0]                                   m_axi4_rid,
  input  logic [AXI4_DATA_W-1:0]                                 m_axi4_rdata,
  input  logic [1:0]                                             m_axi4_rresp,
  input  logic                                                   m_axi4_rlast,
  input  logic                                                   m_axi4_rvalid,
  output logic                                                   m_axi4_rready,

  // Command
  output logic [LOAD_GLWE_CMD_W-1:0]                             subs_cmd,
  output logic                                                   subs_cmd_vld,
  input  logic                                                   subs_cmd_rdy,

  output logic [LOAD_GLWE_CMD_W-1:0]                             main_cmd,
  output logic                                                   main_cmd_vld,
  input  logic                                                   main_cmd_rdy,

  input  logic                                                   subs_cmd_done,
  input  logic                                                   main_cmd_done,

  output logic [GLWE_COEF_PER_AXI4_WORD-1:0][MOD_Q_W-1:0]        axi_data,
  output logic                                                   axi_data_vld,
  input  logic                                                   axi_data_rdy,

  output logic                                                   ldg_rif_req_dur,

  // Error
  output logic                                                   error // done FIFO overflow.
);

// ============================================================================================== //
// localparam
// ============================================================================================== //
  localparam int RCP_FIFO_DEPTH       = 8; // TOREVIEW : according to memory latency. Should be > 2

  localparam int AXI4_WORD_PER_GLWE_BODY  = (N*GLWE_ACS_W + AXI4_DATA_W-1)/AXI4_DATA_W;
  localparam int AXI4_WORD_PER_GLWE_BODY_WW = $clog2(AXI4_WORD_PER_GLWE_BODY+1) == 0 ? 1 : $clog2(AXI4_WORD_PER_GLWE_BODY+1);

  localparam int GLWE_BODY_BYTES      = N * GLWE_ACS_W/8;

// pragma translate_off
  generate
    if (GLWE_BODY_BYTES % AXI4_DATA_BYTES != 0) begin
      $fatal(1,"ERROR > GLWE_BODY_BYTES (%0d) should be AXI4_DATA_BYTES (%0d) aligned", GLWE_BODY_BYTES, AXI4_DATA_BYTES);
    end
  endgenerate
// pragma translate_on

// ============================================================================================== //
// Input pipe
// ============================================================================================== //
  //== Command
  load_glwe_cmd_t c0_cmd;
  logic           c0_cmd_vld;
  logic           c0_cmd_rdy;

  fifo_element #(
    .WIDTH          (LOAD_GLWE_CMD_W),
    .DEPTH          (1), // TOREVIEW
    .TYPE_ARRAY     (4'h3),
    .DO_RESET_DATA  (1'b0),
    .RESET_DATA_VAL (0)
  ) ldg_cmd_fifo_element (
    .clk     (clk),
    .s_rst_n (s_rst_n),

    .in_data (seq_ldg_cmd),
    .in_vld  (seq_ldg_vld),
    .in_rdy  (seq_ldg_rdy),

    .out_data(c0_cmd),
    .out_vld (c0_cmd_vld),
    .out_rdy (c0_cmd_rdy)
  );

  //== Data
  axi4_r_if_t rm1_axi_if;
  logic       rm1_axi_vld;
  logic       rm1_axi_rdy;

  axi4_r_if_t m_axi4_if;

  assign m_axi4_if.rid   = m_axi4_rid;
  assign m_axi4_if.rdata = m_axi4_rdata;
  assign m_axi4_if.rresp = m_axi4_rresp;
  assign m_axi4_if.rlast = m_axi4_rlast;

  fifo_element #(
    .WIDTH          (AXI4_R_IF_W),
    .DEPTH          (2),
    .TYPE_ARRAY     (8'h12),
    .DO_RESET_DATA  (0),
    .RESET_DATA_VAL (0)
  ) axi_r_fifo_element (
    .clk     (clk),
    .s_rst_n (s_rst_n),

    .in_data (m_axi4_if),
    .in_vld  (m_axi4_rvalid),
    .in_rdy  (m_axi4_rready),

    .out_data(rm1_axi_if),
    .out_vld (rm1_axi_vld),
    .out_rdy (rm1_axi_rdy)
  );

// ============================================================================================== //
// Output data
// ============================================================================================== //
  always_comb
    for (int i=0; i<GLWE_COEF_PER_AXI4_WORD; i=i+1)
      axi_data[i] = rm1_axi_if.rdata[i*GLWE_ACS_W+:MOD_Q_W];

  assign axi_data_vld = rm1_axi_vld;
  assign rm1_axi_rdy  = axi_data_rdy;

// ============================================================================================== //
// Fork command
// ============================================================================================== //
// Fork the command between the request path and the reception paths.
  logic           c0_req_cmd_vld;
  logic           c0_req_cmd_rdy;
  logic           c0_rcp_cmd_vld;
  logic           c0_rcp_cmd_rdy;

  assign c0_req_cmd_vld = c0_cmd_vld & c0_rcp_cmd_rdy;
  assign c0_rcp_cmd_vld = c0_cmd_vld & c0_req_cmd_rdy;
  assign c0_cmd_rdy     = c0_req_cmd_rdy & c0_rcp_cmd_rdy;

  //== Request
  load_glwe_cmd_t        req_fifo_out_cmd;
  logic                  req_fifo_out_vld;
  logic                  req_fifo_out_rdy;

  logic [AXI4_ADD_W-1:0] c0_gid_add_ofs;
  logic [AXI4_ADD_W-1:0] req_fifo_out_gid_add_ofs;

  assign c0_gid_add_ofs = gid_offset + c0_cmd.gid * GLWE_BODY_BYTES;

  fifo_element #(
    .WIDTH          (AXI4_ADD_W + LOAD_GLWE_CMD_W),
    .DEPTH          (1),
    .TYPE_ARRAY     (4'h1),
    .DO_RESET_DATA  (1'b0),
    .RESET_DATA_VAL (0)
  ) req_fifo_element (
    .clk     (clk),
    .s_rst_n (s_rst_n),

    .in_data ({c0_gid_add_ofs,c0_cmd}),
    .in_vld  (c0_req_cmd_vld),
    .in_rdy  (c0_req_cmd_rdy),

    .out_data({req_fifo_out_gid_add_ofs,req_fifo_out_cmd}),
    .out_vld (req_fifo_out_vld),
    .out_rdy (req_fifo_out_rdy)
  );

  //== Reception
  load_glwe_cmd_t        rcp_fifo_out_cmd;
  logic                  rcp_fifo_out_vld;
  logic                  rcp_fifo_out_rdy;

  logic                  rcp_fifo_out_vld_main;
  logic                  rcp_fifo_out_rdy_main;

  logic                  rcp_fifo_out_vld_subs;
  logic                  rcp_fifo_out_rdy_subs;

  // fork between main and subs
  assign rcp_fifo_out_vld_main = rcp_fifo_out_vld & rcp_fifo_out_rdy_subs;
  assign rcp_fifo_out_vld_subs = rcp_fifo_out_vld & rcp_fifo_out_rdy_main;
  assign rcp_fifo_out_rdy      = rcp_fifo_out_rdy_main & rcp_fifo_out_rdy_subs;

  fifo_reg #(
    .WIDTH       (LOAD_GLWE_CMD_W),
    .DEPTH       (RCP_FIFO_DEPTH-2),
    .LAT_PIPE_MH ({1'b1, 1'b1})
  ) rcp_fifo_reg (
    .clk      (clk),
    .s_rst_n  (s_rst_n),

    .in_data  (c0_cmd),
    .in_vld   (c0_rcp_cmd_vld),
    .in_rdy   (c0_rcp_cmd_rdy),

    .out_data (rcp_fifo_out_cmd),
    .out_vld  (rcp_fifo_out_vld),
    .out_rdy  (rcp_fifo_out_rdy)
  );

  fifo_element #(
    .WIDTH          (LOAD_GLWE_CMD_W),
    .DEPTH          (2),
    .TYPE_ARRAY     ({4'h1,4'h2}),
    .DO_RESET_DATA  (1'b0),
    .RESET_DATA_VAL (0)
  ) rcp_subs_fifo_element (
    .clk     (clk),
    .s_rst_n (s_rst_n),

    .in_data (rcp_fifo_out_cmd),
    .in_vld  (rcp_fifo_out_vld_subs),
    .in_rdy  (rcp_fifo_out_rdy_subs),

    .out_data(subs_cmd),
    .out_vld (subs_cmd_vld),
    .out_rdy (subs_cmd_rdy)
  );

  fifo_element #(
    .WIDTH          (LOAD_GLWE_CMD_W),
    .DEPTH          (2),
    .TYPE_ARRAY     ({4'h1,4'h2}),
    .DO_RESET_DATA  (1'b0),
    .RESET_DATA_VAL (0)
  ) rcp_main_fifo_element (
    .clk     (clk),
    .s_rst_n (s_rst_n),

    .in_data (rcp_fifo_out_cmd),
    .in_vld  (rcp_fifo_out_vld_main),
    .in_rdy  (rcp_fifo_out_rdy_main),

    .out_data(main_cmd),
    .out_vld (main_cmd_vld),
    .out_rdy (main_cmd_rdy)
  );

// ============================================================================================== //
// Load request
// ============================================================================================== //
  // AXI interface
  axi4_ar_if_t                           s0_axi;
  logic                                  s0_axi_arvalid;
  logic                                  s0_axi_arready;
  logic [8:0]                            req_axi_word_nb; // = axi_len + 1. The size 8 correspond to the axi bus size +1

  // Counters
  logic [AXI4_WORD_PER_GLWE_BODY_WW-1:0] req_axi_word_remain; // counts from AXI4_WORD_PER_GLWE_BODY included to 0 - decremented
  logic [AXI4_WORD_PER_GLWE_BODY_WW-1:0] req_axi_word_remainD;
  logic                                  req_last_axi_word_remain;

  logic                                  req_send_axi_cmd;
  logic                                  req_first_burst;
  logic                                  req_first_burstD;

  assign req_axi_word_remainD     = req_send_axi_cmd ? req_last_axi_word_remain ? AXI4_WORD_PER_GLWE_BODY : req_axi_word_remain - req_axi_word_nb : req_axi_word_remain;
  assign req_last_axi_word_remain = req_axi_word_remain == req_axi_word_nb;
  assign req_first_burstD         = req_send_axi_cmd ? req_last_axi_word_remain ? 1'b1 : 1'b0 : req_first_burst;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      req_axi_word_remain <= AXI4_WORD_PER_GLWE_BODY;
      req_first_burst     <= 1'b1;
    end
    else begin
      req_axi_word_remain <= req_axi_word_remainD;
      req_first_burst     <= req_first_burstD;
    end

  // Address
  logic [AXI4_ADD_W-1:0]    req_add;
  logic [AXI4_ADD_W-1:0]    req_add_keep;
  logic [AXI4_ADD_W-1:0]    req_add_keepD;
  logic [PAGE_BYTES_WW-1:0] req_page_word_remain;

  assign req_add  = req_first_burst ? req_fifo_out_gid_add_ofs : req_add_keep;

  assign req_add_keepD = req_send_axi_cmd ? req_add + req_axi_word_nb*AXI4_DATA_BYTES : req_add_keep;

  always_ff @(posedge clk)
    if (!s_rst_n) req_add_keep <= '0;
    else          req_add_keep <= req_add_keepD;

  assign req_page_word_remain = PAGE_AXI4_DATA - req_add[PAGE_BYTES_W-1:AXI4_DATA_BYTES_W];
  assign req_axi_word_nb      = req_page_word_remain < req_axi_word_remain ? req_page_word_remain : req_axi_word_remain;
  assign s0_axi.arid          = '0; // UNUSED
  assign s0_axi.arsize        = AXI4_DATA_BYTES_W;
  assign s0_axi.arburst       = AXI4B_INCR;
  assign s0_axi.araddr        = req_add;
  assign s0_axi.arlen         = req_axi_word_nb - 1;
  assign s0_axi_arvalid       = req_fifo_out_vld;

  assign req_fifo_out_rdy     = req_send_axi_cmd & req_last_axi_word_remain;

// pragma translate_off
  always_ff @(posedge clk)
    if (s0_axi_arvalid)
      assert(s0_axi.arlen <= AXI4_LEN_MAX)
      else begin
        $fatal(1,"%t > ERROR: AXI4 len overflow. Should not exceed %0d. Seen %0d",$time, AXI4_LEN_MAX, s0_axi.arlen);
      end
// pragma translate_on

//---------------------------------
// to AXI read request
//---------------------------------
  axi4_ar_if_t m_axi4_a;

  assign m_axi4_arid    = m_axi4_a.arid   ;
  assign m_axi4_araddr  = m_axi4_a.araddr ;
  assign m_axi4_arlen   = m_axi4_a.arlen  ;
  assign m_axi4_arsize  = m_axi4_a.arsize ;
  assign m_axi4_arburst = m_axi4_a.arburst;

  fifo_element #(
    .WIDTH          ($bits(axi4_ar_if_t)),
    .DEPTH          (2),
    .TYPE_ARRAY     (8'h12),
    .DO_RESET_DATA  (1'b0),
    .RESET_DATA_VAL (0)
  ) fifo_element (
    .clk     (clk),
    .s_rst_n (s_rst_n),

    .in_data (s0_axi),
    .in_vld  (s0_axi_arvalid),
    .in_rdy  (s0_axi_arready),

    .out_data(m_axi4_a),
    .out_vld (m_axi4_arvalid),
    .out_rdy (m_axi4_arready)
  );

  assign req_send_axi_cmd = s0_axi_arvalid & s0_axi_arready;

// ============================================================================================== //
// Done
// ============================================================================================== //
  logic main_done_error;
  logic subs_done_error;

  logic main_done_vld;
  logic main_done_rdy;
  logic subs_done_vld;
  logic subs_done_rdy;

  common_lib_pulse_to_rdy_vld #(
    .FIFO_DEPTH (2*RCP_FIFO_DEPTH) // TOREVIEW
  ) common_lib_pulse_to_rdy_vld_main (
    .clk     (clk),
    .s_rst_n (s_rst_n),

    .in_pulse(main_cmd_done),

    .out_vld (main_done_vld),
    .out_rdy (main_done_rdy),

    .error   (main_done_error)
  );

  common_lib_pulse_to_rdy_vld #(
    .FIFO_DEPTH (2*RCP_FIFO_DEPTH)
  ) common_lib_pulse_to_rdy_vld_subs (
    .clk     (clk),
    .s_rst_n (s_rst_n),

    .in_pulse(subs_cmd_done),

    .out_vld (subs_done_vld),
    .out_rdy (subs_done_rdy),

    .error   (subs_done_error)
  );

  // Output
  logic ldg_seq_doneD;

  assign ldg_seq_doneD = subs_done_vld & main_done_vld;
  assign main_done_rdy = subs_done_vld;
  assign subs_done_rdy = main_done_vld;

  always_ff @(posedge clk)
    if (!s_rst_n) ldg_seq_done <= 1'b0;
    else          ldg_seq_done <= ldg_seq_doneD;

// ============================================================================================== //
// Duration signals for register if
// ============================================================================================== //
  logic ldg_rif_req_durD;

  assign ldg_rif_req_durD = (req_fifo_out_vld && req_fifo_out_rdy) ? 1'b0 : req_fifo_out_vld;

  always_ff @(posedge clk)
    if (!s_rst_n) ldg_rif_req_dur <= 1'b0;
    else          ldg_rif_req_dur <= ldg_rif_req_durD;

// ============================================================================================== //
// Error
// ============================================================================================== //
  logic errorD;

  assign errorD = subs_done_error | main_done_error;

  always_ff @(posedge clk)
    if (!s_rst_n) error <= 1'b0;
    else          error <= errorD;

endmodule
