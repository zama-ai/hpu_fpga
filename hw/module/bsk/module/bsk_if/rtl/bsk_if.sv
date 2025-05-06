// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : bsk interface
// ----------------------------------------------------------------------------------------------
//
// Handle the bsk_manager buffer as a cache.
// Load from DDR through AXI4 interface.
//
// ==============================================================================================

module bsk_if
  import param_tfhe_pkg::*;
  import param_ntt_pkg::*;
  import top_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import ntt_core_common_param_pkg::*;
  import bsk_mgr_common_param_pkg::*;
  import bsk_if_common_param_pkg::*;
  import axi_if_bsk_axi_pkg::*;
  import axi_if_common_param_pkg::*;
(
    input logic                                                    clk,        // clock
    input logic                                                    s_rst_n,    // synchronous reset

    // Reset the cache
    input  logic                                                   reset_cache,
    output logic                                                   reset_cache_done, // pulse

    // AXI4 Master interface
    // NB: Only AXI Read channel exposed here
    output logic [BSK_PC-1:0][AXI4_ID_W-1:0]                       m_axi4_arid,
    output logic [BSK_PC-1:0][AXI4_ADD_W-1:0]                      m_axi4_araddr,
    output logic [BSK_PC-1:0][7:0]                                 m_axi4_arlen,
    output logic [BSK_PC-1:0][2:0]                                 m_axi4_arsize,
    output logic [BSK_PC-1:0][1:0]                                 m_axi4_arburst,
    output logic [BSK_PC-1:0]                                      m_axi4_arvalid,
    input  logic [BSK_PC-1:0]                                      m_axi4_arready,
    input  logic [BSK_PC-1:0][AXI4_ID_W-1:0]                       m_axi4_rid,
    input  logic [BSK_PC-1:0][AXI4_DATA_W-1:0]                     m_axi4_rdata,
    input  logic [BSK_PC-1:0][1:0]                                 m_axi4_rresp,
    input  logic [BSK_PC-1:0]                                      m_axi4_rlast,
    input  logic [BSK_PC-1:0]                                      m_axi4_rvalid,
    output logic [BSK_PC-1:0]                                      m_axi4_rready,

    // bsk available in DDR. Ready to be ready through AXI
    input logic                                                    bsk_mem_avail,
    input logic [BSK_PC_MAX-1:0][AXI4_ADD_W-1: 0]                  bsk_mem_addr,

    // batch start
    input  logic [TOTAL_BATCH_NB-1:0]                               batch_start_1h, // One-hot : can only start 1 at a time.

    // bsk pointer
    output logic [TOTAL_BATCH_NB-1: 0]                              inc_bsk_wr_ptr,
    input  logic [TOTAL_BATCH_NB-1: 0]                              inc_bsk_rd_ptr,

    // bsk manager
    output logic [BSK_CUT_NB-1:0]                                   bsk_mgr_wr_en, // Write coefficients for 1 (stage iter,GLWE) at a time.
    output logic [BSK_CUT_NB-1:0][BSK_CUT_FCOEF_NB-1:0][MOD_NTT_W-1:0] bsk_mgr_wr_data,
    output logic [BSK_CUT_NB-1:0][BSK_RAM_ADD_W-1:0]                bsk_mgr_wr_add,
    output logic [BSK_CUT_NB-1:0][GLWE_K_P1_W-1:0]                  bsk_mgr_wr_g_idx,
    output logic [BSK_CUT_NB-1:0][BSK_SLOT_W-1:0]                   bsk_mgr_wr_slot,
    output logic [BSK_CUT_NB-1:0][LWE_K_W-1:0]                      bsk_mgr_wr_br_loop,

    // debug info
    output logic [BSK_PC-1:0]                                       load_bsk_pc_recp_dur,
    // Info for rif
    output bskif_info_t                                             bskif_rif_info
);

// ============================================================================================== //
// parameter
// ============================================================================================== //
  // Check parameters
  generate
    if (BSK_PC > BSK_PC_MAX) begin : __UNSUPPORTED_BSK_PC
      $fatal(1,"> ERROR: BSK_PC (%0d) should be less or equal to BSK_PC_MAX (%0d)", BSK_PC, BSK_PC_MAX);
    end
  endgenerate

// ============================================================================================== //
// Signals
// ============================================================================================== //
  logic                       cctrl_rd_vld;
  logic                       cctrl_rd_rdy;
  logic [BSK_READ_CMD_W-1:0]  cctrl_rd_cmd;
  logic                       rd_cctrl_slot_done;
  logic [BSK_SLOT_W-1:0]      rd_cctrl_slot_id;

// ============================================================================================== //
// Instances
// ============================================================================================== //
  bsk_if_cache_control
  bsk_if_cache_control
  (
      .clk                   (clk),
      .s_rst_n               (s_rst_n),

      .bsk_mem_avail         (bsk_mem_avail),

      .reset_cache           (reset_cache     ),
      .reset_cache_done      (reset_cache_done),

      .batch_start_1h        (batch_start_1h),

      .inc_bsk_wr_ptr        (inc_bsk_wr_ptr),
      .inc_bsk_rd_ptr        (inc_bsk_rd_ptr),

      .cctrl_rd_vld          (cctrl_rd_vld),
      .cctrl_rd_rdy          (cctrl_rd_rdy),
      .cctrl_rd_cmd          (cctrl_rd_cmd),
      .rd_cctrl_slot_done    (rd_cctrl_slot_done),
      .rd_cctrl_slot_id      (rd_cctrl_slot_id),

      .bskif_rif_info        (bskif_rif_info)
  );

  bsk_if_axi4_read
  bsk_if_axi4_read
  (
      .clk                   (clk),
      .s_rst_n               (s_rst_n),

      .bsk_mem_avail         (bsk_mem_avail),
      .bsk_mem_addr          (bsk_mem_addr),

      .m_axi4_arid           (m_axi4_arid),
      .m_axi4_araddr         (m_axi4_araddr),
      .m_axi4_arlen          (m_axi4_arlen),
      .m_axi4_arsize         (m_axi4_arsize),
      .m_axi4_arburst        (m_axi4_arburst),
      .m_axi4_arvalid        (m_axi4_arvalid),
      .m_axi4_arready        (m_axi4_arready),
      .m_axi4_rid            (m_axi4_rid),
      .m_axi4_rdata          (m_axi4_rdata),
      .m_axi4_rresp          (m_axi4_rresp),
      .m_axi4_rlast          (m_axi4_rlast),
      .m_axi4_rvalid         (m_axi4_rvalid),
      .m_axi4_rready         (m_axi4_rready),

      .bsk_mgr_wr_en         (bsk_mgr_wr_en),
      .bsk_mgr_wr_data       (bsk_mgr_wr_data),
      .bsk_mgr_wr_add        (bsk_mgr_wr_add),
      .bsk_mgr_wr_g_idx      (bsk_mgr_wr_g_idx),
      .bsk_mgr_wr_slot       (bsk_mgr_wr_slot),
      .bsk_mgr_wr_br_loop    (bsk_mgr_wr_br_loop),

      .cctrl_rd_vld          (cctrl_rd_vld),
      .cctrl_rd_rdy          (cctrl_rd_rdy),
      .cctrl_rd_cmd          (cctrl_rd_cmd),
      .rd_cctrl_slot_done    (rd_cctrl_slot_done),
      .rd_cctrl_slot_id      (rd_cctrl_slot_id),

      .load_bsk_pc_recp_dur  (load_bsk_pc_recp_dur)
  );

endmodule
