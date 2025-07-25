// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Top level of HPU
// ----------------------------------------------------------------------------------------------
//
// This module is a subpart of hpu, to ease the P&R.
// It contains :
//  * regif
// ==============================================================================================

module hpu_with_entry_3in3
  import common_definition_pkg::*;
  import param_tfhe_pkg::*;
  import top_common_param_pkg::*;
  import hpu_common_param_pkg::*;
  import hpu_common_instruction_pkg::*;
  import axi_if_bsk_axi_pkg::*;
  import axi_if_ksk_axi_pkg::*;
  import axi_if_glwe_axi_pkg::*;
  import axi_if_ct_axi_pkg::*;
  import axi_if_ucore_axi_pkg::*;
  import axi_if_trc_axi_pkg::*;
  import axi_if_common_param_pkg::*;
  import axi_if_shell_axil_pkg::*;
  import regf_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import pem_common_param_pkg::*;
  import pea_common_param_pkg::*;
  import isc_common_param_pkg::*;
#(
  parameter int ERROR_NB         = 13
)
(
  input  logic                                                         prc_clk,   // clock
  input  logic                                                         prc_srst_n, // synchronous reset

  input  logic                                                         cfg_clk,   // clock
  input  logic                                                         cfg_srst_n, // synchronous reset

  //== Axi4 lite Slave Interface sAxi4
  input  logic [AXIL_ADD_W-1:0]                                        s_axil_prc_awaddr,
  input  logic                                                         s_axil_prc_awvalid,
  output logic                                                         s_axil_prc_awready,
  input  logic [AXIL_DATA_W-1:0]                                       s_axil_prc_wdata,
  input  logic [AXIL_DATA_BYTES-1:0]                                   s_axil_prc_wstrb, /* UNUSED */
  input  logic                                                         s_axil_prc_wvalid,
  output logic                                                         s_axil_prc_wready,
  output logic [1:0]                                                   s_axil_prc_bresp,
  output logic                                                         s_axil_prc_bvalid,
  input  logic                                                         s_axil_prc_bready,
  input  logic [AXIL_ADD_W-1:0]                                        s_axil_prc_araddr,
  input  logic                                                         s_axil_prc_arvalid,
  output logic                                                         s_axil_prc_arready,
  output logic [AXIL_DATA_W-1:0]                                       s_axil_prc_rdata,
  output logic [1:0]                                                   s_axil_prc_rresp,
  output logic                                                         s_axil_prc_rvalid,
  input  logic                                                         s_axil_prc_rready,

  input  logic [AXIL_ADD_W-1:0]                                        s_axil_cfg_awaddr,
  input  logic                                                         s_axil_cfg_awvalid,
  output logic                                                         s_axil_cfg_awready,
  input  logic [AXIL_DATA_W-1:0]                                       s_axil_cfg_wdata,
  input  logic [AXIL_DATA_BYTES-1:0]                                   s_axil_cfg_wstrb, /* UNUSED */
  input  logic                                                         s_axil_cfg_wvalid,
  output logic                                                         s_axil_cfg_wready,
  output logic [1:0]                                                   s_axil_cfg_bresp,
  output logic                                                         s_axil_cfg_bvalid,
  input  logic                                                         s_axil_cfg_bready,
  input  logic [AXIL_ADD_W-1:0]                                        s_axil_cfg_araddr,
  input  logic                                                         s_axil_cfg_arvalid,
  output logic                                                         s_axil_cfg_arready,
  output logic [AXIL_DATA_W-1:0]                                       s_axil_cfg_rdata,
  output logic [1:0]                                                   s_axil_cfg_rresp,
  output logic                                                         s_axil_cfg_rvalid,
  input  logic                                                         s_axil_cfg_rready,

  // Regif -----------------------------------------------------------------------------------------
  // mem addr spread on 2 word (msb/lsb)
  output logic                                                         reset_bsk_cache,
  input  logic                                                         reset_bsk_cache_done,
  output logic                                                         bsk_mem_avail,
  output logic [BSK_PC_MAX-1:0][axi_if_bsk_axi_pkg::AXI4_ADD_W-1:0]    bsk_mem_addr,

  output logic                                                         reset_cache,

  // Errors ------------------------------------------------------------------------------------------
  input  logic [ERROR_NB-1:0]                                          error,

  // Counters/Infos ----------------------------------------------------------------------------------
  input  pep_info_t                                                    pep_rif_info,
  input  pep_counter_inc_t                                             pep_rif_counter_inc,

  output logic [1:0]                                                   interrupt, // TODO

  // Reset three way handshake -----------------------------------------------------------------------
  output logic                                                         hpu_reset,
  input  logic                                                         hpu_reset_done
);

// ============================================================================================== --
// localparam
// ============================================================================================== --

// ============================================================================================== --
// regif @ cfg_clk
// ============================================================================================== --
  hpu_regif_cfg_3in3
  hpu_regif_cfg_3in3 (
    .cfg_clk                   (cfg_clk),
    .cfg_srst_n                (cfg_srst_n),

    // Axi lite interface
    .s_axil_awaddr             (s_axil_cfg_awaddr),
    .s_axil_awvalid            (s_axil_cfg_awvalid),
    .s_axil_awready            (s_axil_cfg_awready),
    .s_axil_wdata              (s_axil_cfg_wdata),
    .s_axil_wvalid             (s_axil_cfg_wvalid),
    .s_axil_wready             (s_axil_cfg_wready),
    .s_axil_bresp              (s_axil_cfg_bresp),
    .s_axil_bvalid             (s_axil_cfg_bvalid),
    .s_axil_bready             (s_axil_cfg_bready),
    .s_axil_araddr             (s_axil_cfg_araddr),
    .s_axil_arvalid            (s_axil_cfg_arvalid),
    .s_axil_arready            (s_axil_cfg_arready),
    .s_axil_rdata              (s_axil_cfg_rdata),
    .s_axil_rresp              (s_axil_cfg_rresp),
    .s_axil_rvalid             (s_axil_cfg_rvalid),
    .s_axil_rready             (s_axil_cfg_rready),

    // Registers IO
    .bsk_mem_addr              (bsk_mem_addr),
    .hpu_reset                 (hpu_reset),
    .hpu_reset_done            (hpu_reset_done)
  );

// ============================================================================================== --
// regif @ prc_clk
// ============================================================================================== --
  hpu_regif_prc_3in3 #(
    .ERROR_NB      (ERROR_NB)
  ) hpu_regif_prc_3in3 (
    .prc_clk                   (prc_clk),
    .prc_srst_n                (prc_srst_n),

    // Axi lite interface
    .s_axil_awaddr             (s_axil_prc_awaddr),
    .s_axil_awvalid            (s_axil_prc_awvalid),
    .s_axil_awready            (s_axil_prc_awready),
    .s_axil_wdata              (s_axil_prc_wdata),
    .s_axil_wvalid             (s_axil_prc_wvalid),
    .s_axil_wready             (s_axil_prc_wready),
    .s_axil_bresp              (s_axil_prc_bresp),
    .s_axil_bvalid             (s_axil_prc_bvalid),
    .s_axil_bready             (s_axil_prc_bready),
    .s_axil_araddr             (s_axil_prc_araddr),
    .s_axil_arvalid            (s_axil_prc_arvalid),
    .s_axil_arready            (s_axil_prc_arready),
    .s_axil_rdata              (s_axil_prc_rdata),
    .s_axil_rresp              (s_axil_prc_rresp),
    .s_axil_rvalid             (s_axil_prc_rvalid),
    .s_axil_rready             (s_axil_prc_rready),

    // Registers IO
    .bsk_mem_avail             (bsk_mem_avail),
    .reset_bsk_cache           (reset_bsk_cache),
    .reset_bsk_cache_done      (reset_bsk_cache_done),
    .reset_cache               (reset_cache),

    .error                     (error),
    .pep_info                  (pep_rif_info),
    .pep_counter_inc           (pep_rif_counter_inc)
  );

endmodule
