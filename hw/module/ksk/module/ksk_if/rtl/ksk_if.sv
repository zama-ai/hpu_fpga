// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : KSK interface
// ----------------------------------------------------------------------------------------------
//
// Handle the KSK_manager buffer as a cache.
// Load from DDR through AXI4 interface.
//
// ==============================================================================================

module ksk_if
  import param_tfhe_pkg::*;
  import top_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import pep_ks_common_param_pkg::*;
  import ksk_mgr_common_param_pkg::*;
  import ksk_if_common_param_pkg::*;
  import axi_if_ksk_axi_pkg::*;
  import axi_if_common_param_pkg::*;
(
    input logic                                                     clk,        // clock
    input logic                                                     s_rst_n,    // synchronous reset

    // Reset the cache
    input  logic                                                    reset_cache,
    output logic                                                    reset_cache_done, // pulse

    // AXI4 Master interface
    // NB: Only AXI Read channel exposed here
    output logic [KSK_PC-1:0][AXI4_ID_W-1:0]                        m_axi4_arid,
    output logic [KSK_PC-1:0][AXI4_ADD_W-1:0]                       m_axi4_araddr,
    output logic [KSK_PC-1:0][7:0]                                  m_axi4_arlen,
    output logic [KSK_PC-1:0][2:0]                                  m_axi4_arsize,
    output logic [KSK_PC-1:0][1:0]                                  m_axi4_arburst,
    output logic [KSK_PC-1:0]                                       m_axi4_arvalid,
    input  logic [KSK_PC-1:0]                                       m_axi4_arready,
    input  logic [KSK_PC-1:0][AXI4_ID_W-1:0]                        m_axi4_rid,
    input  logic [KSK_PC-1:0][AXI4_DATA_W-1:0]                      m_axi4_rdata,
    input  logic [KSK_PC-1:0][1:0]                                  m_axi4_rresp,
    input  logic [KSK_PC-1:0]                                       m_axi4_rlast,
    input  logic [KSK_PC-1:0]                                       m_axi4_rvalid,
    output logic [KSK_PC-1:0]                                       m_axi4_rready,

    // KSK available in DDR. Ready to be ready through AXI
    input logic                                                     ksk_mem_avail,
    input logic [KSK_PC_MAX-1:0][AXI4_ADD_W-1: 0]                   ksk_mem_addr,

    // batch start
    input  logic [TOTAL_BATCH_NB-1:0]                               batch_start_1h, // One-hot : can only start 1 at a time.

    // KSK pointer
    output logic [TOTAL_BATCH_NB-1: 0]                              inc_ksk_wr_ptr,
    input  logic [TOTAL_BATCH_NB-1: 0]                              inc_ksk_rd_ptr,

    // KSK manager
    output logic [KSK_CUT_NB-1:0]                                   ksk_mgr_wr_en, // Write coefficients for 1 (stage iter,GLWE) at a time.
    output logic [KSK_CUT_NB-1:0][KSK_CUT_FCOEF_NB-1:0][LBZ-1:0][MOD_KSK_W-1:0]  ksk_mgr_wr_data,
    output logic [KSK_CUT_NB-1:0][KSK_RAM_ADD_W-1:0]                ksk_mgr_wr_add,
    output logic [KSK_CUT_NB-1:0][LBX_W-1:0]                        ksk_mgr_wr_x_idx,
    output logic [KSK_CUT_NB-1:0][KSK_SLOT_W-1:0]                   ksk_mgr_wr_slot,
    output logic [KSK_CUT_NB-1:0][KS_BLOCK_COL_W-1:0]               ksk_mgr_wr_ks_loop,

    // debug info
    output logic [KSK_PC-1:0]                                       load_ksk_pc_recp_dur
);

// ============================================================================================== //
// parameter
// ============================================================================================== //
  // Check parameters
  generate
    if (KSK_PC > KSK_PC_MAX) begin : __UNSUPPORTED_KSK_PC
      $fatal(1,"> ERROR: KSK_PC (%0d) should be less or equal to KSK_PC_MAX (%0d)", KSK_PC, KSK_PC_MAX);
    end
  endgenerate

// ============================================================================================== //
// Signals
// ============================================================================================== //
  logic                       cctrl_rd_vld;
  logic                       cctrl_rd_rdy;
  logic [KSK_READ_CMD_W-1:0]  cctrl_rd_cmd;
  logic                       rd_cctrl_slot_done;
  logic [KSK_SLOT_W-1:0]      rd_cctrl_slot_id;

// ============================================================================================== //
// Instances
// ============================================================================================== //
  ksk_if_cache_control
  ksk_if_cache_control
  (
      .clk                   (clk),
      .s_rst_n               (s_rst_n),

      .ksk_mem_avail         (ksk_mem_avail),

      .reset_cache           (reset_cache     ),
      .reset_cache_done      (reset_cache_done),

      .batch_start_1h        (batch_start_1h),

      .inc_ksk_wr_ptr        (inc_ksk_wr_ptr),
      .inc_ksk_rd_ptr        (inc_ksk_rd_ptr),

      .cctrl_rd_vld          (cctrl_rd_vld),
      .cctrl_rd_rdy          (cctrl_rd_rdy),
      .cctrl_rd_cmd          (cctrl_rd_cmd),
      .rd_cctrl_slot_done    (rd_cctrl_slot_done),
      .rd_cctrl_slot_id      (rd_cctrl_slot_id)
  );

  ksk_if_axi4_read
  ksk_if_axi4_read
  (
      .clk                   (clk),
      .s_rst_n               (s_rst_n),

      .ksk_mem_avail         (ksk_mem_avail),
      .ksk_mem_addr          (ksk_mem_addr),

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

      .ksk_mgr_wr_en         (ksk_mgr_wr_en),
      .ksk_mgr_wr_data       (ksk_mgr_wr_data),
      .ksk_mgr_wr_add        (ksk_mgr_wr_add),
      .ksk_mgr_wr_x_idx      (ksk_mgr_wr_x_idx),
      .ksk_mgr_wr_slot       (ksk_mgr_wr_slot),
      .ksk_mgr_wr_ks_loop    (ksk_mgr_wr_ks_loop),

      .cctrl_rd_vld          (cctrl_rd_vld),
      .cctrl_rd_rdy          (cctrl_rd_rdy),
      .cctrl_rd_cmd          (cctrl_rd_cmd),
      .rd_cctrl_slot_done    (rd_cctrl_slot_done),
      .rd_cctrl_slot_id      (rd_cctrl_slot_id),

      .load_ksk_pc_recp_dur  (load_ksk_pc_recp_dur)
  );

endmodule
