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

module pep_load_glwe_splitc_main
  import common_definition_pkg::*;
  import axi_if_common_param_pkg::*;
  import axi_if_glwe_axi_pkg::*;
  import param_tfhe_pkg::*;
  import top_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import ntt_core_common_param_pkg::*;
#(
  localparam int MAIN_PSI = MSPLIT_MAIN_FACTOR * PSI / MSPLIT_DIV,
  localparam int SUBS_PSI = MSPLIT_SUBS_FACTOR * PSI / MSPLIT_DIV
)
(
  input  logic                                                     clk,        // clock
  input  logic                                                     s_rst_n,    // synchronous reset

  input  logic [AXI4_ADD_W-1:0]                                    gid_offset, // quasi static

  // From GRAM arbiter
  input  logic [GRAM_NB-1:0]                                       garb_ldg_avail_1h,

  // pep_seq : command
  input  logic [LOAD_GLWE_CMD_W-1:0]                               seq_ldg_cmd,
  input  logic                                                     seq_ldg_vld,
  output logic                                                     seq_ldg_rdy,
  output logic                                                     ldg_seq_done,

  // AXI4 Master interface
  // NB: Only AXI Read channel exposed here
  output logic [AXI4_ID_W-1:0]                                     m_axi4_arid,
  output logic [AXI4_ADD_W-1:0]                                    m_axi4_araddr,
  output logic [7:0]                                               m_axi4_arlen,
  output logic [2:0]                                               m_axi4_arsize,
  output logic [1:0]                                               m_axi4_arburst,
  output logic                                                     m_axi4_arvalid,
  input  logic                                                     m_axi4_arready,
  input  logic [AXI4_ID_W-1:0]                                     m_axi4_rid,
  input  logic [AXI4_DATA_W-1:0]                                   m_axi4_rdata,
  input  logic [1:0]                                               m_axi4_rresp,
  input  logic                                                     m_axi4_rlast,
  input  logic                                                     m_axi4_rvalid,
  output logic                                                     m_axi4_rready,

  // Command
  output logic [LOAD_GLWE_CMD_W-1:0]                               subs_cmd,
  output logic                                                     subs_cmd_vld,
  input  logic                                                     subs_cmd_rdy,
  input  logic                                                     subs_cmd_done,

  // Data
  output logic [GLWE_SPLITC_COEF-1:0][MOD_Q_W-1:0]                 subs_data,
  output logic                                                     subs_data_vld,
  input  logic                                                     subs_data_rdy,

  // Write GLWE RAM
  // This memory is composed of GRAM_NB independent RAMs
  output logic [GRAM_NB-1:0][MAIN_PSI-1:0][R-1:0]                     glwe_ram_wr_en,
  output logic [GRAM_NB-1:0][MAIN_PSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0] glwe_ram_wr_add,
  output logic [GRAM_NB-1:0][MAIN_PSI-1:0][R-1:0][MOD_Q_W-1:0]        glwe_ram_wr_data,

  output pep_ldg_counter_inc_t                                     pep_ldg_counter_inc,
  output pep_ldg_error_t                                           ldg_error
);

// ============================================================================================== //
// localparam
// ============================================================================================== //
  localparam int HPSI = MAIN_PSI;

  generate
    if (GLWE_SPLITC_COEF > HPSI*R) begin : _UNSUPPORTED_GLWE_SPLITC_COEF
      $fatal(1,"> ERROR: Unsupported GLWE_SPLITC_COEF (%0d), should be less or equal to MAIN_PSI*R (%0d)", GLWE_SPLITC_COEF, HPSI*R);
    end
  endgenerate
// ============================================================================================== //
// Signals
// ============================================================================================== //
  logic [LOAD_GLWE_CMD_W-1:0]                       main_cmd;
  logic                                             main_cmd_vld;
  logic                                             main_cmd_rdy;
  logic                                             main_cmd_done;

  logic [GLWE_COEF_PER_AXI4_WORD-1:0][MOD_Q_W-1:0]  axi_data;
  logic                                             axi_data_vld;
  logic                                             axi_data_rdy;

  logic [GLWE_SPLITC_COEF-1:0][MOD_Q_W-1:0]         main_data;
  logic                                             main_data_vld;
  logic                                             main_data_rdy;

// ============================================================================================== //
// Error / Inc
// ============================================================================================== //
  pep_ldg_error_t       ldg_errorD;
  pep_ldg_counter_inc_t pep_ldg_counter_incD;

  logic                          entry_error;
  logic                          core_error;

  logic [MSPLIT_MAIN_FACTOR-1:0] ldg_rif_rcp_dur;
  logic                          ldg_rif_req_dur;

  always_comb begin
    ldg_errorD                   = '0;
    pep_ldg_counter_incD         = '0;
    ldg_errorD.done_ovf          = core_error | entry_error;
    pep_ldg_counter_incD.rcp_dur[MSPLIT_SUBS_FACTOR+:MSPLIT_MAIN_FACTOR] = ldg_rif_rcp_dur;
    pep_ldg_counter_incD.req_dur = ldg_rif_req_dur;
  end

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      ldg_error           <= '0;
      pep_ldg_counter_inc <= '0;
    end
    else begin
      ldg_error           <= ldg_errorD;
      pep_ldg_counter_inc <= pep_ldg_counter_incD;
    end

// ============================================================================================== //
// Entry
// ============================================================================================== //
  pep_ldg_splitc_entry
  pep_ldg_splitc_entry (
    .clk             (clk),
    .s_rst_n         (s_rst_n),

    .gid_offset      (gid_offset),

    .seq_ldg_cmd     (seq_ldg_cmd),
    .seq_ldg_vld     (seq_ldg_vld),
    .seq_ldg_rdy     (seq_ldg_rdy),
    .ldg_seq_done    (ldg_seq_done),

    .m_axi4_arid     (m_axi4_arid),
    .m_axi4_araddr   (m_axi4_araddr),
    .m_axi4_arlen    (m_axi4_arlen),
    .m_axi4_arsize   (m_axi4_arsize),
    .m_axi4_arburst  (m_axi4_arburst),
    .m_axi4_arvalid  (m_axi4_arvalid),
    .m_axi4_arready  (m_axi4_arready),
    .m_axi4_rid      (m_axi4_rid),
    .m_axi4_rdata    (m_axi4_rdata),
    .m_axi4_rresp    (m_axi4_rresp),
    .m_axi4_rlast    (m_axi4_rlast),
    .m_axi4_rvalid   (m_axi4_rvalid),
    .m_axi4_rready   (m_axi4_rready),

    .subs_cmd        (subs_cmd),
    .subs_cmd_vld    (subs_cmd_vld),
    .subs_cmd_rdy    (subs_cmd_rdy),

    .main_cmd        (main_cmd),
    .main_cmd_vld    (main_cmd_vld),
    .main_cmd_rdy    (main_cmd_rdy),

    .subs_cmd_done   (subs_cmd_done),
    .main_cmd_done   (main_cmd_done),

    .axi_data        (axi_data),
    .axi_data_vld    (axi_data_vld),
    .axi_data_rdy    (axi_data_rdy),

    .ldg_rif_req_dur (ldg_rif_req_dur),

    .error           (entry_error)
  );

// ============================================================================================== //
// Dispatch main/subsidiary
// ============================================================================================== //
  logic [1:0][GLWE_SPLITC_COEF-1:0][MOD_Q_W-1:0] disp_data;
  logic [1:0]                                    disp_data_vld;
  logic [1:0]                                    disp_data_rdy;

  assign {main_data, subs_data}         = disp_data;
  assign {main_data_vld, subs_data_vld} = disp_data_vld;
  assign disp_data_rdy                  = {main_data_rdy, subs_data_rdy};

  pep_ldg_splitc_dispatch
  #(
    .OP_W      (MOD_Q_W),
    .IN_COEF   (GLWE_COEF_PER_AXI4_WORD),
    .OUT_COEF  (GLWE_SPLITC_COEF),
    .UNIT_COEF (R*PSI / MSPLIT_DIV),
    .OUT0_UNIT_NB (MSPLIT_SUBS_FACTOR),
    .OUT1_UNIT_NB (MSPLIT_MAIN_FACTOR),
    .IN_PIPE   (1'b1),
    .OUT_PIPE  (1'b1)
  ) pep_ldg_splitc_dispatch (
    .clk      (clk),
    .s_rst_n  (s_rst_n),

    .in_data  (axi_data),
    .in_vld   (axi_data_vld),
    .in_rdy   (axi_data_rdy),

    .out_data (disp_data),
    .out_vld  (disp_data_vld),
    .out_rdy  (disp_data_rdy)
  );

// ============================================================================================== //
// Core
// ============================================================================================== //
  pep_ldg_splitc_core
  #(
    .COEF_NB      (GLWE_SPLITC_COEF),
    .HPSI_SET_ID  (1),
    .MSPLIT_FACTOR(MSPLIT_MAIN_FACTOR)
  ) pep_ldg_splitc_core (
    .clk               (clk),
    .s_rst_n           (s_rst_n),

    .garb_ldg_avail_1h (garb_ldg_avail_1h),

    .in_cmd            (main_cmd),
    .in_cmd_vld        (main_cmd_vld),
    .in_cmd_rdy        (main_cmd_rdy),
    .cmd_done          (main_cmd_done),

    .in_data           (main_data),
    .in_data_vld       (main_data_vld),
    .in_data_rdy       (main_data_rdy),

    .glwe_ram_wr_en    (glwe_ram_wr_en),
    .glwe_ram_wr_add   (glwe_ram_wr_add),
    .glwe_ram_wr_data  (glwe_ram_wr_data),

    .error             (core_error),
    .ldg_rif_rcp_dur   (ldg_rif_rcp_dur)
  );

endmodule
