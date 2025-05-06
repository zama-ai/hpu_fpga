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

module pep_load_glwe_splitc_subs
  import common_definition_pkg::*;
  import axi_if_common_param_pkg::*;
  import axi_if_glwe_axi_pkg::*;
  import param_tfhe_pkg::*;
  import top_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import ntt_core_common_param_pkg::*;
#(
  localparam int SUBS_PSI = MSPLIT_SUBS_FACTOR * PSI / MSPLIT_DIV
)
(
  input  logic                                                     clk,        // clock
  input  logic                                                     s_rst_n,    // synchronous reset

  // From GRAM arbiter
  input  logic [GRAM_NB-1:0]                                       garb_ldg_avail_1h,

  // Command
  input  logic [LOAD_GLWE_CMD_W-1:0]                               subs_cmd,
  input  logic                                                     subs_cmd_vld,
  output logic                                                     subs_cmd_rdy,
  output logic                                                     subs_cmd_done,

  // Data
  input  logic [GLWE_SPLITC_COEF-1:0][MOD_Q_W-1:0]                 subs_data,
  input  logic                                                     subs_data_vld,
  output logic                                                     subs_data_rdy,

  // Write GLWE RAM
  // This memory is composed of GRAM_NB independent RAMs
  output logic [GRAM_NB-1:0][SUBS_PSI-1:0][R-1:0]                     glwe_ram_wr_en,
  output logic [GRAM_NB-1:0][SUBS_PSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0] glwe_ram_wr_add,
  output logic [GRAM_NB-1:0][SUBS_PSI-1:0][R-1:0][MOD_Q_W-1:0]        glwe_ram_wr_data,

  output pep_ldg_counter_inc_t                                     pep_ldg_counter_inc,
  output pep_ldg_error_t                                           ldg_error
);

// ============================================================================================== //
// localparam
// ============================================================================================== //
  localparam int HPSI = SUBS_PSI;

  generate
    if (GLWE_SPLITC_COEF > HPSI*R) begin : _UNSUPPORTED_GLWE_SPLITC_COEF
      $fatal(1,"> ERROR: Unsupported GLWE_SPLITC_COEF (%0d), should be less or equal to PSI/2*R (%0d)", GLWE_SPLITC_COEF, HPSI*R);
    end
  endgenerate

// ============================================================================================== //
// Error / Inc
// ============================================================================================== //
  pep_ldg_error_t       ldg_errorD;
  pep_ldg_counter_inc_t pep_ldg_counter_incD;

  logic                          core_error;

  logic [MSPLIT_SUBS_FACTOR-1:0] ldg_rif_rcp_dur;

  always_comb begin
    ldg_errorD                   = '0;
    pep_ldg_counter_incD         = '0;
    ldg_errorD.done_ovf          = core_error;
    pep_ldg_counter_incD.rcp_dur[0+:MSPLIT_SUBS_FACTOR] = ldg_rif_rcp_dur;
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
// Core
// ============================================================================================== //
  // Process QPSI 0, and 1
  pep_ldg_splitc_core
  #(
    .COEF_NB      (GLWE_SPLITC_COEF),
    .HPSI_SET_ID  (0),
    .MSPLIT_FACTOR(MSPLIT_SUBS_FACTOR)
  ) pep_ldg_splitc_core (
    .clk               (clk),
    .s_rst_n           (s_rst_n),

    .garb_ldg_avail_1h (garb_ldg_avail_1h),

    .in_cmd            (subs_cmd),
    .in_cmd_vld        (subs_cmd_vld),
    .in_cmd_rdy        (subs_cmd_rdy),
    .cmd_done          (subs_cmd_done),

    .in_data           (subs_data),
    .in_data_vld       (subs_data_vld),
    .in_data_rdy       (subs_data_rdy),

    .glwe_ram_wr_en    (glwe_ram_wr_en),
    .glwe_ram_wr_add   (glwe_ram_wr_add),
    .glwe_ram_wr_data  (glwe_ram_wr_data),

    .ldg_rif_rcp_dur   (ldg_rif_rcp_dur),

    .error             (core_error)
  );

endmodule
