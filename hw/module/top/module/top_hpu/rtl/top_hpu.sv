// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Template
// ----------------------------------------------------------------------------------------------
//
//
// ==============================================================================================

module top_hpu #(
  parameter int VERSION_MAJOR   = 2,
  parameter int VERSION_MINOR   = 1,
  parameter int INTER_PART_PIPE = 1
) (
  // PCIE Link ----------------------------------------------------------------
  input  logic        top_gt_pcie_refclk_clk_n,
  input  logic        top_gt_pcie_refclk_clk_p,
  input  logic [7:0]  top_gt_pciea1_grx_n,
  input  logic [7:0]  top_gt_pciea1_grx_p,
  output logic [7:0]  top_gt_pciea1_gtx_n,
  output logic [7:0]  top_gt_pciea1_gtx_p,
  // DDR 4 --------------------------------------------------------------------
  // First channel
  output logic [0:0]  top_CH0_DDR4_0_0_act_n,
  output logic [16:0] top_CH0_DDR4_0_0_adr,
  output logic [1:0]  top_CH0_DDR4_0_0_ba,
  output logic [0:0]  top_CH0_DDR4_0_0_bg,
  output logic [0:0]  top_CH0_DDR4_0_0_ck_c,
  output logic [0:0]  top_CH0_DDR4_0_0_ck_t,
  output logic [0:0]  top_CH0_DDR4_0_0_cke,
  output logic [0:0]  top_CH0_DDR4_0_0_cs_n,
  inout  logic [8:0]  top_CH0_DDR4_0_0_dm_n,
  inout  logic [71:0] top_CH0_DDR4_0_0_dq,
  inout  logic [8:0]  top_CH0_DDR4_0_0_dqs_c,
  inout  logic [8:0]  top_CH0_DDR4_0_0_dqs_t,
  output logic [0:0]  top_CH0_DDR4_0_0_odt,
  output logic [0:0]  top_CH0_DDR4_0_0_reset_n,
  // Second channel
  output logic [0:0]  top_CH0_DDR4_0_1_act_n,
  output logic [17:0] top_CH0_DDR4_0_1_adr,
  input  logic [0:0]  top_CH0_DDR4_0_1_alert_n,
  output logic [1:0]  top_CH0_DDR4_0_1_ba,
  output logic [1:0]  top_CH0_DDR4_0_1_bg,
  output logic [0:0]  top_CH0_DDR4_0_1_ck_c,
  output logic [0:0]  top_CH0_DDR4_0_1_ck_t,
  output logic [0:0]  top_CH0_DDR4_0_1_cke,
  output logic [0:0]  top_CH0_DDR4_0_1_cs_n,
  inout  logic [71:0] top_CH0_DDR4_0_1_dq,
  inout  logic [17:0] top_CH0_DDR4_0_1_dqs_c,
  inout  logic [17:0] top_CH0_DDR4_0_1_dqs_t,
  output logic [0:0]  top_CH0_DDR4_0_1_odt,
  output logic [0:0]  top_CH0_DDR4_0_1_par,
  output logic [0:0]  top_CH0_DDR4_0_1_reset_n,
  // Clocks -------------------------------------------------------------------
  input  logic        top_sys_clk0_0_clk_n,
  input  logic        top_sys_clk0_0_clk_p,
  input  logic        top_sys_clk0_1_clk_n,
  input  logic        top_sys_clk0_1_clk_p,

  input  logic        gt_ref_clk_n,
  input  logic        gt_ref_clk_p,

  // HBM ----------------------------------------------------------------------
  input  logic [0:0]  top_hbm_ref_clk_0_clk_n,
  input  logic [0:0]  top_hbm_ref_clk_0_clk_p,
  input  logic [0:0]  top_hbm_ref_clk_1_clk_p,
  input  logic [0:0]  top_hbm_ref_clk_1_clk_n,

  // Transceivers --------------------------------------------------------------
  // bank 111: for use with GTM in the lower clock region X0Y7, GTM_QUAD_X0Y9
  input  logic [3:0] qsfp3_4x_grx_n,
  input  logic [3:0] qsfp3_4x_grx_p,
  output logic [3:0] qsfp3_4x_gtx_n,
  output logic [3:0] qsfp3_4x_gtx_p
);

// ----------------------------------------------------------------------------------------- //
// localparam
// ----------------------------------------------------------------------------------------- //
  import top_common_param_pkg::*;
  import axi_if_common_param_pkg::*;
  import axi_if_trc_axi_pkg::*;
  import axi_if_ct_axi_pkg::*;
  import axi_if_glwe_axi_pkg::*;
  import axi_if_bsk_axi_pkg::*;
  import axi_if_ksk_axi_pkg::*;
  import axi_if_shell_axil_pkg::*;

  localparam int AXI4_TRC_ADD_W       = axi_if_trc_axi_pkg::AXI4_ADD_W;
  localparam int AXI4_TRC_DATA_W      = axi_if_trc_axi_pkg::AXI4_DATA_W;
  localparam int AXI4_TRC_DATA_BYTES  = axi_if_trc_axi_pkg::AXI4_DATA_BYTES;
  localparam int AXI4_TRC_ID_W        = axi_if_trc_axi_pkg::AXI4_ID_W;
  localparam int AXI4_PEM_ADD_W       = axi_if_ct_axi_pkg::AXI4_ADD_W;
  localparam int AXI4_PEM_DATA_W      = axi_if_ct_axi_pkg::AXI4_DATA_W;
  localparam int AXI4_PEM_DATA_BYTES  = axi_if_ct_axi_pkg::AXI4_DATA_BYTES;
  localparam int AXI4_PEM_ID_W        = axi_if_ct_axi_pkg::AXI4_ID_W;
  localparam int AXI4_GLWE_ADD_W      = axi_if_glwe_axi_pkg::AXI4_ADD_W;
  localparam int AXI4_GLWE_DATA_W     = axi_if_glwe_axi_pkg::AXI4_DATA_W;
  localparam int AXI4_GLWE_DATA_BYTES = axi_if_glwe_axi_pkg::AXI4_DATA_BYTES;
  localparam int AXI4_GLWE_ID_W       = axi_if_glwe_axi_pkg::AXI4_ID_W;
  localparam int AXI4_BSK_ADD_W       = axi_if_bsk_axi_pkg::AXI4_ADD_W;
  localparam int AXI4_BSK_DATA_W      = axi_if_bsk_axi_pkg::AXI4_DATA_W;
  localparam int AXI4_BSK_DATA_BYTES  = axi_if_bsk_axi_pkg::AXI4_DATA_BYTES;
  localparam int AXI4_BSK_ID_W        = axi_if_bsk_axi_pkg::AXI4_ID_W;
  localparam int AXI4_KSK_ADD_W       = axi_if_ksk_axi_pkg::AXI4_ADD_W;
  localparam int AXI4_KSK_DATA_W      = axi_if_ksk_axi_pkg::AXI4_DATA_W;
  localparam int AXI4_KSK_DATA_BYTES  = axi_if_ksk_axi_pkg::AXI4_DATA_BYTES;
  localparam int AXI4_KSK_ID_W        = axi_if_ksk_axi_pkg::AXI4_ID_W;

  // Ethernet: Do not modify ----------------------------------------------------------------------
  // number of QSFP lines: do not modify
  localparam int QSFP_LANE_NB = 4;
  // Number of PCs
  localparam int ETH_PC       = 2;
  // Ethernet preamble
  localparam [7:0]  START_FRAME_DELIMITER = 'hD5;
  localparam [47:0] PREAMBLE = 'h555555555555;
  // tx preamble is only 56 bits: we are in  custom mode due to non-segmented configuration
  localparam [55:0] TX_PREAMBLE = {PREAMBLE, START_FRAME_DELIMITER};
  // axi4-stream ethernet
  localparam int AXIS_TDATA_W = 64;
  localparam int AXIS_TKEEP_W = 11;
  // ------------------------------------------------------------------------------------------- //

  // ----------------------------------------------------------------------------------------- //
  // Signals
  /* Axi stream ---------------------------------------------------------------
   * used between the shell and the rtl moule
   * sizes are fixed by block design
   */
  logic [31:0]  axis_m_rx_tdata_tmp;
  logic [127:0] axis_m_rx_tdata;
  logic         axis_m_rx_tlast;
  logic         axis_m_rx_tready;
  logic         axis_m_rx_tvalid;
  logic [31:0]  axis_m_tx_tdata_tmp;
  logic [127:0] axis_m_tx_tdata;
  logic         axis_m_tx_tlast;
  logic         axis_m_tx_tready;
  logic         axis_m_tx_tvalid;

  logic [31:0]  axis_s_rx_tdata_tmp;
  logic [127:0] axis_s_rx_tdata;
  logic         axis_s_rx_tlast;
  logic         axis_s_rx_tready;
  logic         axis_s_rx_tvalid;
  logic [31:0]  axis_s_tx_tdata_tmp;
  logic [127:0] axis_s_tx_tdata;
  logic         axis_s_tx_tlast;
  logic         axis_s_tx_tready;
  logic         axis_s_tx_tvalid;

  /* Interrupts ---------------------------------------------------------------
   * only one interrupt on the rtl side but inside block design
   * the maximum number is defined
   */
  logic [3:0] hpu_interrupt;
  logic [5:0] rtl_interrupt;

  /* Clock Reset --------------------------------------------------------------
  */
  // Process clock (fast, free running)
  logic prc_free_clk;
  logic prc_free_srst_n;

  // Process clock (fast, gated)
  logic prc_clk;
  logic prc_ce;
  logic prc_srst_n;

  // Configuration clock (slow)
  logic cfg_clk;
  logic cfg_srst_n;

  // Ethernet configuration clock
  logic eth_cfg_clk;
  logic eth_cfg_srst_n;

  /* AXI4 ---------------------------------------------------------------------
  * in direction to RTL register interface, size is fixed.
  */
  logic [31:0]                                      axi_lpd_araddr;
  logic [1:0]                                       axi_lpd_arburst;
  logic [3:0]                                       axi_lpd_arcache;
  logic [7:0]                                       axi_lpd_arlen;
  logic [0:0]                                       axi_lpd_arlock;
  logic [2:0]                                       axi_lpd_arprot;
  logic [3:0]                                       axi_lpd_arqos;
  logic                                             axi_lpd_arready;
  logic [2:0]                                       axi_lpd_arsize;
  logic [15:0]                                      axi_lpd_aruser;
  logic                                             axi_lpd_arvalid;
  logic [31:0]                                      axi_lpd_awaddr;
  logic [1:0]                                       axi_lpd_awburst;
  logic [3:0]                                       axi_lpd_awcache;
  logic [7:0]                                       axi_lpd_awlen;
  logic [0:0]                                       axi_lpd_awlock;
  logic [2:0]                                       axi_lpd_awprot;
  logic [3:0]                                       axi_lpd_awqos;
  logic                                             axi_lpd_awready;
  logic [2:0]                                       axi_lpd_awsize;
  logic [15:0]                                      axi_lpd_awuser;
  logic                                             axi_lpd_awvalid;
  logic                                             axi_lpd_bready;
  logic [1:0]                                       axi_lpd_bresp;
  logic                                             axi_lpd_bvalid;
  logic [31:0]                                      axi_lpd_rdata;
  logic                                             axi_lpd_rlast;
  logic                                             axi_lpd_rready;
  logic [1:0]                                       axi_lpd_rresp;
  logic                                             axi_lpd_rvalid;
  logic [31:0]                                      axi_lpd_wdata;
  logic                                             axi_lpd_wlast;
  logic                                             axi_lpd_wready;
  logic [3:0]                                       axi_lpd_wstrb;
  logic                                             axi_lpd_wvalid;

  // AXI4-lite
  logic [1:0][31:0]                                 axi_regif_prc_awaddr;
  logic [1:0]                                       axi_regif_prc_awvalid;
  logic [1:0]                                       axi_regif_prc_awready;
  logic [1:0][31:0]                                 axi_regif_prc_wdata;
  logic [1:0]                                       axi_regif_prc_wvalid;
  logic [1:0]                                       axi_regif_prc_wready;
  logic [1:0][3:0]                                  axi_regif_prc_wstrb;
  logic [1:0][1:0]                                  axi_regif_prc_bresp;
  logic [1:0]                                       axi_regif_prc_bvalid;
  logic [1:0]                                       axi_regif_prc_bready;
  logic [1:0][31:0]                                 axi_regif_prc_araddr;
  logic [1:0]                                       axi_regif_prc_arvalid;
  logic [1:0]                                       axi_regif_prc_arready;
  logic [1:0][31:0]                                 axi_regif_prc_rdata;
  logic [1:0][1:0]                                  axi_regif_prc_rresp;
  logic [1:0]                                       axi_regif_prc_rvalid;
  logic [1:0]                                       axi_regif_prc_rready;
  // unused for axi lite
  logic [1:0][2:0]                                  axi_regif_prc_arprot;
  logic [1:0][2:0]                                  axi_regif_prc_awprot;

  logic [1:0][31:0]                                 axi_regif_cfg_awaddr;
  logic [1:0]                                       axi_regif_cfg_awvalid;
  logic [1:0]                                       axi_regif_cfg_awready;
  logic [1:0][31:0]                                 axi_regif_cfg_wdata;
  logic [1:0]                                       axi_regif_cfg_wvalid;
  logic [1:0]                                       axi_regif_cfg_wready;
  logic [1:0][3:0]                                  axi_regif_cfg_wstrb;
  logic [1:0][1:0]                                  axi_regif_cfg_bresp;
  logic [1:0]                                       axi_regif_cfg_bvalid;
  logic [1:0]                                       axi_regif_cfg_bready;
  logic [1:0][31:0]                                 axi_regif_cfg_araddr;
  logic [1:0]                                       axi_regif_cfg_arvalid;
  logic [1:0]                                       axi_regif_cfg_arready;
  logic [1:0][31:0]                                 axi_regif_cfg_rdata;
  logic [1:0][1:0]                                  axi_regif_cfg_rresp;
  logic [1:0]                                       axi_regif_cfg_rvalid;
  logic [1:0]                                       axi_regif_cfg_rready;
  // unused for axi lite
  logic [1:0][2:0]                                  axi_regif_cfg_arprot;
  logic [1:0][2:0]                                  axi_regif_cfg_awprot;

  // == Ethernet
  // axi4-lite direct access to mrmac registers
  logic [31:0]                                      axi_eth_mrmac_awaddr;
  logic                                             axi_eth_mrmac_awvalid;
  logic                                             axi_eth_mrmac_awready;
  logic [31:0]                                      axi_eth_mrmac_wdata;
  logic                                             axi_eth_mrmac_wvalid;
  logic                                             axi_eth_mrmac_wready;
  logic [3:0]                                       axi_eth_mrmac_wstrb;
  logic [1:0]                                       axi_eth_mrmac_bresp;
  logic                                             axi_eth_mrmac_bvalid;
  logic                                             axi_eth_mrmac_bready;
  logic [31:0]                                      axi_eth_mrmac_araddr;
  logic                                             axi_eth_mrmac_arvalid;
  logic                                             axi_eth_mrmac_arready;
  logic [31:0]                                      axi_eth_mrmac_rdata;
  logic [1:0]                                       axi_eth_mrmac_rresp;
  logic                                             axi_eth_mrmac_rvalid;
  logic                                             axi_eth_mrmac_rready;
  // unused for axi lite
  logic [2:0]                                       axi_eth_mrmac_arprot;
  logic [2:0]                                       axi_eth_mrmac_awprot;

  // axi4-lite direct access to axi-stream FIFO
  logic [31:0]                                      axi_eth_dbg_awaddr;
  logic                                             axi_eth_dbg_awvalid;
  logic                                             axi_eth_dbg_awready;
  logic [31:0]                                      axi_eth_dbg_wdata;
  logic                                             axi_eth_dbg_wvalid;
  logic                                             axi_eth_dbg_wready;
  logic [3:0]                                       axi_eth_dbg_wstrb;
  logic [1:0]                                       axi_eth_dbg_bresp;
  logic                                             axi_eth_dbg_bvalid;
  logic                                             axi_eth_dbg_bready;
  logic [31:0]                                      axi_eth_dbg_araddr;
  logic                                             axi_eth_dbg_arvalid;
  logic                                             axi_eth_dbg_arready;
  logic [31:0]                                      axi_eth_dbg_rdata;
  logic [1:0]                                       axi_eth_dbg_rresp;
  logic                                             axi_eth_dbg_rvalid;
  logic                                             axi_eth_dbg_rready;
  // unused for axi lite
  logic [2:0]                                       axi_eth_dbg_arprot;
  logic [2:0]                                       axi_eth_dbg_awprot;

  logic [31:0]                                      axi_eth_fifo_awaddr;
  logic                                             axi_eth_fifo_awvalid;
  logic                                             axi_eth_fifo_awready;
  logic [31:0]                                      axi_eth_fifo_wdata;
  logic                                             axi_eth_fifo_wvalid;
  logic                                             axi_eth_fifo_wready;
  logic [3:0]                                       axi_eth_fifo_wstrb;
  logic [1:0]                                       axi_eth_fifo_bresp;
  logic                                             axi_eth_fifo_bvalid;
  logic                                             axi_eth_fifo_bready;
  logic [31:0]                                      axi_eth_fifo_araddr;
  logic                                             axi_eth_fifo_arvalid;
  logic                                             axi_eth_fifo_arready;
  logic [31:0]                                      axi_eth_fifo_rdata;
  logic [1:0]                                       axi_eth_fifo_rresp;
  logic                                             axi_eth_fifo_rvalid;
  logic                                             axi_eth_fifo_rready;
  // unused for axi lite
  logic [2:0]                                       axi_eth_fifo_arprot;
  logic [2:0]                                       axi_eth_fifo_awprot;

  // axi4-lite direct access to dma controller interface
  logic [31:0]                                      axi_eth_dma_awaddr;
  logic                                             axi_eth_dma_awvalid;
  logic                                             axi_eth_dma_awready;
  logic [31:0]                                      axi_eth_dma_wdata;
  logic                                             axi_eth_dma_wvalid;
  logic                                             axi_eth_dma_wready;
  logic [3:0]                                       axi_eth_dma_wstrb;
  logic [1:0]                                       axi_eth_dma_bresp;
  logic                                             axi_eth_dma_bvalid;
  logic                                             axi_eth_dma_bready;
  logic [31:0]                                      axi_eth_dma_araddr;
  logic                                             axi_eth_dma_arvalid;
  logic                                             axi_eth_dma_arready;
  logic [31:0]                                      axi_eth_dma_rdata;
  logic [1:0]                                       axi_eth_dma_rresp;
  logic                                             axi_eth_dma_rvalid;
  logic                                             axi_eth_dma_rready;
  // unused for axi lite
  logic [2:0]                                       axi_eth_dma_arprot;
  logic [2:0]                                       axi_eth_dma_awprot;

  /* TRACE
   *
   */
  // `HPU_AXI4_TRC_SIGNAL
   /*Write channel*/
  logic [AXI4_TRC_ID_W-1:0]                         m_axi4_trc_awid;
  logic [AXI4_TRC_ADD_W-1:0]                        m_axi4_trc_awaddr;
  logic [AXI4_LEN_W-1:0]                            m_axi4_trc_awlen;
  logic [AXI4_SIZE_W-1:0]                           m_axi4_trc_awsize;
  logic [AXI4_BURST_W-1:0]                          m_axi4_trc_awburst;
  logic                                             m_axi4_trc_awvalid;
  logic                                             m_axi4_trc_awready;
  logic [AXI4_TRC_DATA_W-1:0]                       m_axi4_trc_wdata;
  logic [AXI4_TRC_DATA_BYTES-1:0]                   m_axi4_trc_wstrb;
  logic                                             m_axi4_trc_wlast;
  logic                                             m_axi4_trc_wvalid;
  logic                                             m_axi4_trc_wready;
  logic [AXI4_TRC_ID_W-1:0]                         m_axi4_trc_bid;
  logic [AXI4_RESP_W-1:0]                           m_axi4_trc_bresp;
  logic                                             m_axi4_trc_bvalid;
  logic                                             m_axi4_trc_bready;
  /*Unused signal tie to constant in the top*/
  logic [AXI4_AWLOCK_W-1:0]                         m_axi4_trc_awlock;  /*UNUSED*/
  logic [AXI4_AWCACHE_W-1:0]                        m_axi4_trc_awcache; /*UNUSED*/
  logic [AXI4_AWPROT_W-1:0]                         m_axi4_trc_awprot;  /*UNUSED*/
  logic [AXI4_AWQOS_W-1:0]                          m_axi4_trc_awqos;   /*UNUSED*/
  logic [AXI4_AWREGION_W-1:0]                       m_axi4_trc_awregion;/*UNUSED*/
  /*Read channel*/
  logic [AXI4_TRC_ID_W-1:0]                         m_axi4_trc_arid;
  logic [AXI4_TRC_ADD_W-1:0]                        m_axi4_trc_araddr;
  logic [AXI4_LEN_W-1:0]                            m_axi4_trc_arlen;
  logic [AXI4_SIZE_W-1:0]                           m_axi4_trc_arsize;
  logic [AXI4_BURST_W-1:0]                          m_axi4_trc_arburst;
  logic                                             m_axi4_trc_arvalid;
  logic                                             m_axi4_trc_arready;
  logic [AXI4_TRC_ID_W-1:0]                         m_axi4_trc_rid;
  logic [AXI4_TRC_DATA_W-1:0]                       m_axi4_trc_rdata;
  logic [AXI4_RESP_W-1:0]                           m_axi4_trc_rresp;
  logic                                             m_axi4_trc_rlast;
  logic                                             m_axi4_trc_rvalid;
  logic                                             m_axi4_trc_rready;
  /*Unused signal tight to constant in the top*/
  logic [AXI4_ARLOCK_W-1:0]                         m_axi4_trc_arlock;  /*UNUSED*/
  logic [AXI4_ARCACHE_W-1:0]                        m_axi4_trc_arcache; /*UNUSED*/
  logic [AXI4_ARPROT_W-1:0]                         m_axi4_trc_arprot;  /*UNUSED*/
  logic [AXI4_ARQOS_W-1:0]                          m_axi4_trc_arqos;   /*UNUSED*/
  logic [AXI4_ARREGION_W-1:0]                       m_axi4_trc_arregion;/*UNUSED*/

  // `HPU_AXI4_PEM_SIGNAL
  /*PC 0*/
  /*Write channel*/
  logic [PEM_PC_MAX-1:0][AXI4_PEM_ID_W-1:0]         m_axi4_pem_awid;
  logic [PEM_PC_MAX-1:0][AXI4_PEM_ADD_W-1:0]        m_axi4_pem_awaddr;
  logic [PEM_PC_MAX-1:0][AXI4_LEN_W-1:0]            m_axi4_pem_awlen;
  logic [PEM_PC_MAX-1:0][AXI4_SIZE_W-1:0]           m_axi4_pem_awsize;
  logic [PEM_PC_MAX-1:0][AXI4_BURST_W-1:0]          m_axi4_pem_awburst;
  logic [PEM_PC_MAX-1:0]                            m_axi4_pem_awvalid;
  logic [PEM_PC_MAX-1:0]                            m_axi4_pem_awready;
  logic [PEM_PC_MAX-1:0][AXI4_PEM_DATA_W-1:0]       m_axi4_pem_wdata;
  logic [PEM_PC_MAX-1:0][AXI4_PEM_DATA_BYTES-1:0]   m_axi4_pem_wstrb;
  logic [PEM_PC_MAX-1:0]                            m_axi4_pem_wlast;
  logic [PEM_PC_MAX-1:0]                            m_axi4_pem_wvalid;
  logic [PEM_PC_MAX-1:0]                            m_axi4_pem_wready;
  logic [PEM_PC_MAX-1:0][AXI4_PEM_ID_W-1:0]         m_axi4_pem_bid;
  logic [PEM_PC_MAX-1:0][AXI4_RESP_W-1:0]           m_axi4_pem_bresp;
  logic [PEM_PC_MAX-1:0]                            m_axi4_pem_bvalid;
  logic [PEM_PC_MAX-1:0]                            m_axi4_pem_bready;
  /*Unused signal tight to constant in the top*/
  logic [PEM_PC_MAX-1:0][AXI4_AWLOCK_W-1:0]         m_axi4_pem_awlock;  /*UNUSED*/
  logic [PEM_PC_MAX-1:0][AXI4_AWCACHE_W-1:0]        m_axi4_pem_awcache; /*UNUSED*/
  logic [PEM_PC_MAX-1:0][AXI4_AWPROT_W-1:0]         m_axi4_pem_awprot;  /*UNUSED*/
  logic [PEM_PC_MAX-1:0][AXI4_AWQOS_W-1:0]          m_axi4_pem_awqos;   /*UNUSED*/
  logic [PEM_PC_MAX-1:0][AXI4_AWREGION_W-1:0]       m_axi4_pem_awregion;/*UNUSED*/
  /*Read channel*/
  logic [PEM_PC_MAX-1:0][AXI4_PEM_ID_W-1:0]         m_axi4_pem_arid;
  logic [PEM_PC_MAX-1:0][AXI4_PEM_ADD_W-1:0]        m_axi4_pem_araddr;
  logic [PEM_PC_MAX-1:0][AXI4_LEN_W-1:0]            m_axi4_pem_arlen;
  logic [PEM_PC_MAX-1:0][AXI4_SIZE_W-1:0]           m_axi4_pem_arsize;
  logic [PEM_PC_MAX-1:0][AXI4_BURST_W-1:0]          m_axi4_pem_arburst;
  logic [PEM_PC_MAX-1:0]                            m_axi4_pem_arvalid;
  logic [PEM_PC_MAX-1:0]                            m_axi4_pem_arready;
  logic [PEM_PC_MAX-1:0][AXI4_PEM_ID_W-1:0]         m_axi4_pem_rid;
  logic [PEM_PC_MAX-1:0][AXI4_PEM_DATA_W-1:0]       m_axi4_pem_rdata;
  logic [PEM_PC_MAX-1:0][AXI4_RESP_W-1:0]           m_axi4_pem_rresp;
  logic [PEM_PC_MAX-1:0]                            m_axi4_pem_rlast;
  logic [PEM_PC_MAX-1:0]                            m_axi4_pem_rvalid;
  logic [PEM_PC_MAX-1:0]                            m_axi4_pem_rready;
  /*Unused signal tight to constant in the top*/
  logic [PEM_PC_MAX-1:0][AXI4_ARLOCK_W-1:0]         m_axi4_pem_arlock;  /*UNUSED*/
  logic [PEM_PC_MAX-1:0][AXI4_ARCACHE_W-1:0]        m_axi4_pem_arcache; /*UNUSED*/
  logic [PEM_PC_MAX-1:0][AXI4_ARPROT_W-1:0]         m_axi4_pem_arprot;  /*UNUSED*/
  logic [PEM_PC_MAX-1:0][AXI4_ARQOS_W-1:0]          m_axi4_pem_arqos;   /*UNUSED*/
  logic [PEM_PC_MAX-1:0][AXI4_ARREGION_W-1:0]       m_axi4_pem_arregion;/*UNUSED*/

  // `HPU_AXI4_GLWE_SIGNAL
  /*Write channel*/
  logic [GLWE_PC_MAX-1:0][AXI4_GLWE_ID_W-1:0]       m_axi4_glwe_awid;
  logic [GLWE_PC_MAX-1:0][AXI4_GLWE_ADD_W-1:0]      m_axi4_glwe_awaddr;
  logic [GLWE_PC_MAX-1:0][AXI4_LEN_W-1:0]           m_axi4_glwe_awlen;
  logic [GLWE_PC_MAX-1:0][AXI4_SIZE_W-1:0]          m_axi4_glwe_awsize;
  logic [GLWE_PC_MAX-1:0][AXI4_BURST_W-1:0]         m_axi4_glwe_awburst;
  logic [GLWE_PC_MAX-1:0]                           m_axi4_glwe_awvalid;
  logic [GLWE_PC_MAX-1:0]                           m_axi4_glwe_awready;
  logic [GLWE_PC_MAX-1:0][AXI4_GLWE_DATA_W-1:0]     m_axi4_glwe_wdata;
  logic [GLWE_PC_MAX-1:0][AXI4_GLWE_DATA_BYTES-1:0] m_axi4_glwe_wstrb;
  logic [GLWE_PC_MAX-1:0]                           m_axi4_glwe_wlast;
  logic [GLWE_PC_MAX-1:0]                           m_axi4_glwe_wvalid;
  logic [GLWE_PC_MAX-1:0]                           m_axi4_glwe_wready;
  logic [GLWE_PC_MAX-1:0][AXI4_GLWE_ID_W-1:0]       m_axi4_glwe_bid;
  logic [GLWE_PC_MAX-1:0][AXI4_RESP_W-1:0]          m_axi4_glwe_bresp;
  logic [GLWE_PC_MAX-1:0]                           m_axi4_glwe_bvalid;
  logic [GLWE_PC_MAX-1:0]                           m_axi4_glwe_bready;
  /*Unused signal tight to constant in the top*/
  logic [GLWE_PC_MAX-1:0][AXI4_AWLOCK_W-1:0]        m_axi4_glwe_awlock;  /*UNUSED*/
  logic [GLWE_PC_MAX-1:0][AXI4_AWCACHE_W-1:0]       m_axi4_glwe_awcache; /*UNUSED*/
  logic [GLWE_PC_MAX-1:0][AXI4_AWPROT_W-1:0]        m_axi4_glwe_awprot;  /*UNUSED*/
  logic [GLWE_PC_MAX-1:0][AXI4_AWQOS_W-1:0]         m_axi4_glwe_awqos;   /*UNUSED*/
  logic [GLWE_PC_MAX-1:0][AXI4_AWREGION_W-1:0]      m_axi4_glwe_awregion;/*UNUSED*/
  /*Read channel*/
  logic [GLWE_PC_MAX-1:0][AXI4_GLWE_ID_W-1:0]       m_axi4_glwe_arid;
  logic [GLWE_PC_MAX-1:0][AXI4_GLWE_ADD_W-1:0]      m_axi4_glwe_araddr;
  logic [GLWE_PC_MAX-1:0][AXI4_LEN_W-1:0]           m_axi4_glwe_arlen;
  logic [GLWE_PC_MAX-1:0][AXI4_SIZE_W-1:0]          m_axi4_glwe_arsize;
  logic [GLWE_PC_MAX-1:0][AXI4_BURST_W-1:0]         m_axi4_glwe_arburst;
  logic [GLWE_PC_MAX-1:0]                           m_axi4_glwe_arvalid;
  logic [GLWE_PC_MAX-1:0]                           m_axi4_glwe_arready;
  logic [GLWE_PC_MAX-1:0][AXI4_GLWE_ID_W-1:0]       m_axi4_glwe_rid;
  logic [GLWE_PC_MAX-1:0][AXI4_GLWE_DATA_W-1:0]     m_axi4_glwe_rdata;
  logic [GLWE_PC_MAX-1:0][AXI4_RESP_W-1:0]          m_axi4_glwe_rresp;
  logic [GLWE_PC_MAX-1:0]                           m_axi4_glwe_rlast;
  logic [GLWE_PC_MAX-1:0]                           m_axi4_glwe_rvalid;
  logic [GLWE_PC_MAX-1:0]                           m_axi4_glwe_rready;
  /*Unused signal tight to constant in the top*/
  logic [GLWE_PC_MAX-1:0][AXI4_ARLOCK_W-1:0]        m_axi4_glwe_arlock;  /*UNUSED*/
  logic [GLWE_PC_MAX-1:0][AXI4_ARCACHE_W-1:0]       m_axi4_glwe_arcache; /*UNUSED*/
  logic [GLWE_PC_MAX-1:0][AXI4_ARPROT_W-1:0]        m_axi4_glwe_arprot;  /*UNUSED*/
  logic [GLWE_PC_MAX-1:0][AXI4_ARQOS_W-1:0]         m_axi4_glwe_arqos;   /*UNUSED*/
  logic [GLWE_PC_MAX-1:0][AXI4_ARREGION_W-1:0]      m_axi4_glwe_arregion;/*UNUSED*/

  // `HPU_AXI4_BSK_SIGNAL
  /*Write channel*/
  logic [BSK_PC_MAX-1:0][AXI4_BSK_ID_W-1:0]         m_axi4_bsk_awid;
  logic [BSK_PC_MAX-1:0][AXI4_BSK_ADD_W-1:0]        m_axi4_bsk_awaddr;
  logic [BSK_PC_MAX-1:0][AXI4_LEN_W-1:0]            m_axi4_bsk_awlen;
  logic [BSK_PC_MAX-1:0][AXI4_SIZE_W-1:0]           m_axi4_bsk_awsize;
  logic [BSK_PC_MAX-1:0][AXI4_BURST_W-1:0]          m_axi4_bsk_awburst;
  logic [BSK_PC_MAX-1:0]                            m_axi4_bsk_awvalid;
  logic [BSK_PC_MAX-1:0]                            m_axi4_bsk_awready;
  logic [BSK_PC_MAX-1:0][AXI4_BSK_DATA_W-1:0]       m_axi4_bsk_wdata;
  logic [BSK_PC_MAX-1:0][AXI4_BSK_DATA_BYTES-1:0]   m_axi4_bsk_wstrb;
  logic [BSK_PC_MAX-1:0]                            m_axi4_bsk_wlast;
  logic [BSK_PC_MAX-1:0]                            m_axi4_bsk_wvalid;
  logic [BSK_PC_MAX-1:0]                            m_axi4_bsk_wready;
  logic [BSK_PC_MAX-1:0][AXI4_BSK_ID_W-1:0]         m_axi4_bsk_bid;
  logic [BSK_PC_MAX-1:0][AXI4_RESP_W-1:0]           m_axi4_bsk_bresp;
  logic [BSK_PC_MAX-1:0]                            m_axi4_bsk_bvalid;
  logic [BSK_PC_MAX-1:0]                            m_axi4_bsk_bready;
  /*Unused signal tight to constant in the top*/
  logic [BSK_PC_MAX-1:0][AXI4_AWLOCK_W-1:0]         m_axi4_bsk_awlock;  /*UNUSED*/
  logic [BSK_PC_MAX-1:0][AXI4_AWCACHE_W-1:0]        m_axi4_bsk_awcache; /*UNUSED*/
  logic [BSK_PC_MAX-1:0][AXI4_AWPROT_W-1:0]         m_axi4_bsk_awprot;  /*UNUSED*/
  logic [BSK_PC_MAX-1:0][AXI4_AWQOS_W-1:0]          m_axi4_bsk_awqos;   /*UNUSED*/
  logic [BSK_PC_MAX-1:0][AXI4_AWREGION_W-1:0]       m_axi4_bsk_awregion;/*UNUSED*/
  /*Read channel*/
  logic [BSK_PC_MAX-1:0][AXI4_BSK_ID_W-1:0]         m_axi4_bsk_arid;
  logic [BSK_PC_MAX-1:0][AXI4_BSK_ADD_W-1:0]        m_axi4_bsk_araddr;
  logic [BSK_PC_MAX-1:0][AXI4_LEN_W-1:0]            m_axi4_bsk_arlen;
  logic [BSK_PC_MAX-1:0][AXI4_SIZE_W-1:0]           m_axi4_bsk_arsize;
  logic [BSK_PC_MAX-1:0][AXI4_BURST_W-1:0]          m_axi4_bsk_arburst;
  logic [BSK_PC_MAX-1:0]                            m_axi4_bsk_arvalid;
  logic [BSK_PC_MAX-1:0]                            m_axi4_bsk_arready;
  logic [BSK_PC_MAX-1:0][AXI4_BSK_ID_W-1:0]         m_axi4_bsk_rid;
  logic [BSK_PC_MAX-1:0][AXI4_BSK_DATA_W-1:0]       m_axi4_bsk_rdata;
  logic [BSK_PC_MAX-1:0][AXI4_RESP_W-1:0]           m_axi4_bsk_rresp;
  logic [BSK_PC_MAX-1:0]                            m_axi4_bsk_rlast;
  logic [BSK_PC_MAX-1:0]                            m_axi4_bsk_rvalid;
  logic [BSK_PC_MAX-1:0]                            m_axi4_bsk_rready;
  /*Unused signal tight to constant in the top*/
  logic [BSK_PC_MAX-1:0][AXI4_ARLOCK_W-1:0]         m_axi4_bsk_arlock;  /*UNUSED*/
  logic [BSK_PC_MAX-1:0][AXI4_ARCACHE_W-1:0]        m_axi4_bsk_arcache; /*UNUSED*/
  logic [BSK_PC_MAX-1:0][AXI4_ARPROT_W-1:0]         m_axi4_bsk_arprot;  /*UNUSED*/
  logic [BSK_PC_MAX-1:0][AXI4_ARQOS_W-1:0]          m_axi4_bsk_arqos;   /*UNUSED*/
  logic [BSK_PC_MAX-1:0][AXI4_ARREGION_W-1:0]       m_axi4_bsk_arregion;/*UNUSED*/

  // `HPU_AXI4_KSK_SIGNAL
  /*Write channel*/
  logic [KSK_PC_MAX-1:0][AXI4_KSK_ID_W-1:0]         m_axi4_ksk_awid;
  logic [KSK_PC_MAX-1:0][AXI4_KSK_ADD_W-1:0]        m_axi4_ksk_awaddr;
  logic [KSK_PC_MAX-1:0][AXI4_LEN_W-1:0]            m_axi4_ksk_awlen;
  logic [KSK_PC_MAX-1:0][AXI4_SIZE_W-1:0]           m_axi4_ksk_awsize;
  logic [KSK_PC_MAX-1:0][AXI4_BURST_W-1:0]          m_axi4_ksk_awburst;
  logic [KSK_PC_MAX-1:0]                            m_axi4_ksk_awvalid;
  logic [KSK_PC_MAX-1:0]                            m_axi4_ksk_awready;
  logic [KSK_PC_MAX-1:0][AXI4_KSK_DATA_W-1:0]       m_axi4_ksk_wdata;
  logic [KSK_PC_MAX-1:0][AXI4_KSK_DATA_BYTES-1:0]   m_axi4_ksk_wstrb;
  logic [KSK_PC_MAX-1:0]                            m_axi4_ksk_wlast;
  logic [KSK_PC_MAX-1:0]                            m_axi4_ksk_wvalid;
  logic [KSK_PC_MAX-1:0]                            m_axi4_ksk_wready;
  logic [KSK_PC_MAX-1:0][AXI4_KSK_ID_W-1:0]         m_axi4_ksk_bid;
  logic [KSK_PC_MAX-1:0][AXI4_RESP_W-1:0]           m_axi4_ksk_bresp;
  logic [KSK_PC_MAX-1:0]                            m_axi4_ksk_bvalid;
  logic [KSK_PC_MAX-1:0]                            m_axi4_ksk_bready;
  /*Unused signal tight to constant in the top*/
  logic [KSK_PC_MAX-1:0][AXI4_AWLOCK_W-1:0]         m_axi4_ksk_awlock;
  logic [KSK_PC_MAX-1:0][AXI4_AWCACHE_W-1:0]        m_axi4_ksk_awcache;
  logic [KSK_PC_MAX-1:0][AXI4_AWPROT_W-1:0]         m_axi4_ksk_awprot;
  logic [KSK_PC_MAX-1:0][AXI4_AWQOS_W-1:0]          m_axi4_ksk_awqos;
  logic [KSK_PC_MAX-1:0][AXI4_AWREGION_W-1:0]       m_axi4_ksk_awregion;
  /*Read channel*/
  logic [KSK_PC_MAX-1:0][AXI4_KSK_ID_W-1:0]         m_axi4_ksk_arid;
  logic [KSK_PC_MAX-1:0][AXI4_KSK_ADD_W-1:0]        m_axi4_ksk_araddr;
  logic [KSK_PC_MAX-1:0][AXI4_LEN_W-1:0]            m_axi4_ksk_arlen;
  logic [KSK_PC_MAX-1:0][AXI4_SIZE_W-1:0]           m_axi4_ksk_arsize;
  logic [KSK_PC_MAX-1:0][AXI4_BURST_W-1:0]          m_axi4_ksk_arburst;
  logic [KSK_PC_MAX-1:0]                            m_axi4_ksk_arvalid;
  logic [KSK_PC_MAX-1:0]                            m_axi4_ksk_arready;
  logic [KSK_PC_MAX-1:0][AXI4_KSK_ID_W-1:0]         m_axi4_ksk_rid;
  logic [KSK_PC_MAX-1:0][AXI4_KSK_DATA_W-1:0]       m_axi4_ksk_rdata;
  logic [KSK_PC_MAX-1:0][AXI4_RESP_W-1:0]           m_axi4_ksk_rresp;
  logic [KSK_PC_MAX-1:0]                            m_axi4_ksk_rlast;
  logic [KSK_PC_MAX-1:0]                            m_axi4_ksk_rvalid;
  logic [KSK_PC_MAX-1:0]                            m_axi4_ksk_rready;
  /*Unused signal tight to constant in the top*/
  logic [KSK_PC_MAX-1:0][AXI4_ARLOCK_W-1:0]         m_axi4_ksk_arlock;
  logic [KSK_PC_MAX-1:0][AXI4_ARCACHE_W-1:0]        m_axi4_ksk_arcache;
  logic [KSK_PC_MAX-1:0][AXI4_ARPROT_W-1:0]         m_axi4_ksk_arprot;
  logic [KSK_PC_MAX-1:0][AXI4_ARQOS_W-1:0]          m_axi4_ksk_arqos;
  logic [KSK_PC_MAX-1:0][AXI4_ARREGION_W-1:0]       m_axi4_ksk_arregion;

  // HPU_AXI4_ETH_HBM
  /*Write channel*/
  logic [ETH_PC-1:0][AXI4_KSK_ID_W-1:0]         m_axi4_eth_hbm_awid;
  logic [ETH_PC-1:0][AXI4_KSK_ADD_W-1:0]        m_axi4_eth_hbm_awaddr;
  logic [ETH_PC-1:0][AXI4_LEN_W-1:0]            m_axi4_eth_hbm_awlen;
  logic [ETH_PC-1:0][AXI4_SIZE_W-1:0]           m_axi4_eth_hbm_awsize;
  logic [ETH_PC-1:0][AXI4_BURST_W-1:0]          m_axi4_eth_hbm_awburst;
  logic [ETH_PC-1:0]                            m_axi4_eth_hbm_awvalid;
  logic [ETH_PC-1:0]                            m_axi4_eth_hbm_awready;
  logic [ETH_PC-1:0][AXI4_KSK_DATA_W-1:0]       m_axi4_eth_hbm_wdata;
  logic [ETH_PC-1:0][AXI4_KSK_DATA_BYTES-1:0]   m_axi4_eth_hbm_wstrb;
  logic [ETH_PC-1:0]                            m_axi4_eth_hbm_wlast;
  logic [ETH_PC-1:0]                            m_axi4_eth_hbm_wvalid;
  logic [ETH_PC-1:0]                            m_axi4_eth_hbm_wready;
  logic [ETH_PC-1:0][AXI4_KSK_ID_W-1:0]         m_axi4_eth_hbm_bid;
  logic [ETH_PC-1:0][AXI4_RESP_W-1:0]           m_axi4_eth_hbm_bresp;
  logic [ETH_PC-1:0]                            m_axi4_eth_hbm_bvalid;
  logic [ETH_PC-1:0]                            m_axi4_eth_hbm_bready;
  /*Unused signal tight to constant in the top*/
  logic [ETH_PC-1:0][AXI4_AWLOCK_W-1:0]         m_axi4_eth_hbm_awlock;
  logic [ETH_PC-1:0][AXI4_AWCACHE_W-1:0]        m_axi4_eth_hbm_awcache;
  logic [ETH_PC-1:0][AXI4_AWPROT_W-1:0]         m_axi4_eth_hbm_awprot;
  logic [ETH_PC-1:0][AXI4_AWQOS_W-1:0]          m_axi4_eth_hbm_awqos;
  logic [ETH_PC-1:0][AXI4_AWREGION_W-1:0]       m_axi4_eth_hbm_awregion;
  /*Read channel*/
  logic [ETH_PC-1:0][AXI4_KSK_ID_W-1:0]         m_axi4_eth_hbm_arid;
  logic [ETH_PC-1:0][AXI4_KSK_ADD_W-1:0]        m_axi4_eth_hbm_araddr;
  logic [ETH_PC-1:0][AXI4_LEN_W-1:0]            m_axi4_eth_hbm_arlen;
  logic [ETH_PC-1:0][AXI4_SIZE_W-1:0]           m_axi4_eth_hbm_arsize;
  logic [ETH_PC-1:0][AXI4_BURST_W-1:0]          m_axi4_eth_hbm_arburst;
  logic [ETH_PC-1:0]                            m_axi4_eth_hbm_arvalid;
  logic [ETH_PC-1:0]                            m_axi4_eth_hbm_arready;
  logic [ETH_PC-1:0][AXI4_KSK_ID_W-1:0]         m_axi4_eth_hbm_rid;
  logic [ETH_PC-1:0][AXI4_KSK_DATA_W-1:0]       m_axi4_eth_hbm_rdata;
  logic [ETH_PC-1:0][AXI4_RESP_W-1:0]           m_axi4_eth_hbm_rresp;
  logic [ETH_PC-1:0]                            m_axi4_eth_hbm_rlast;
  logic [ETH_PC-1:0]                            m_axi4_eth_hbm_rvalid;
  logic [ETH_PC-1:0]                            m_axi4_eth_hbm_rready;
  /*Unused signal tight to constant in the top*/
  logic [ETH_PC-1:0][AXI4_ARLOCK_W-1:0]         m_axi4_eth_hbm_arlock;
  logic [ETH_PC-1:0][AXI4_ARCACHE_W-1:0]        m_axi4_eth_hbm_arcache;
  logic [ETH_PC-1:0][AXI4_ARPROT_W-1:0]         m_axi4_eth_hbm_arprot;
  logic [ETH_PC-1:0][AXI4_ARQOS_W-1:0]          m_axi4_eth_hbm_arqos;
  logic [ETH_PC-1:0][AXI4_ARREGION_W-1:0]       m_axi4_eth_hbm_arregion;

  // ======================================================================= //
  // Ethernet link: MRMAC, GTM and DMA
  // ======================================================================= //
  // mrmac axi4-stream interface
  logic resetn_axis_mrmac;
  logic clk_axis_mrmac;
  // ----------------------------------------------------------------------- //
  // coming from regif: dma
  // ---------------------- //
  // Line rate
  logic [31:0]             SW_REG_GT_LINE_RATE;
  logic [7:0]              gt_line_rate;
  // loopback
  logic [2:0]              gt_loopback;
  // controlled resets
  logic [QSFP_LANE_NB-1:0] gt_reset_rx_datapath;
  logic [QSFP_LANE_NB-1:0] gt_reset_tx_datapath;
  logic [QSFP_LANE_NB-1:0] gt_reset_all;
  // reset monitoring
  logic [QSFP_LANE_NB-1:0] gt_rx_reset_done;
  logic [QSFP_LANE_NB-1:0] gt_tx_reset_done;
  // ----------------------------------------------------------------------- //
  // Multi-hpu-dma
  // ---------------------- //
  logic                                      interrupt_notify;
  logic                                      interrupt_read_request;
  // QSFP RX axi4-stream
  logic [QSFP_LANE_NB-1:0][AXIS_TDATA_W-1:0] qsfp_rx_tdata;
  logic [QSFP_LANE_NB-1:0][AXIS_TKEEP_W-1:0] qsfp_rx_tkeep_user;
  logic [QSFP_LANE_NB-1:0]                   qsfp_rx_tlast;
  logic [QSFP_LANE_NB-1:0]                   qsfp_rx_tvalid;
  // QSFP TX axi4-stream
  logic [QSFP_LANE_NB-1:0][AXIS_TDATA_W-1:0] qsfp_tx_tdata;
  logic [QSFP_LANE_NB-1:0][AXIS_TKEEP_W-1:0] qsfp_tx_tkeep_user;
  logic [QSFP_LANE_NB-1:0]                   qsfp_tx_tlast;
  logic [QSFP_LANE_NB-1:0]                   qsfp_tx_tvalid;
  logic [QSFP_LANE_NB-1:0]                   qsfp_tx_tready;
  // ----------------------------------------------------------------------- //

  // =========================================================================================== //
  // Connections
  // =========================================================================================== //
  assign rtl_interrupt[0]   = hpu_interrupt[0]; // TODO
  assign rtl_interrupt[3:1] = 3'b0;
  assign rtl_interrupt[4]   = interrupt_notify;
  assign rtl_interrupt[5]   = interrupt_read_request;

  // from isc to bd, stream is one word at a time
  assign axis_s_rx_tlast = 1'b1;

  // The NOC support at least 128b.
  assign axis_s_rx_tdata     = {{128-32{1'b0}},axis_s_rx_tdata_tmp};
  assign axis_s_tx_tdata_tmp = axis_s_tx_tdata[31:0];
  assign axis_m_rx_tdata     = {{128-32{1'b0}},axis_m_rx_tdata_tmp};
  assign axis_m_tx_tdata_tmp = axis_m_tx_tdata[31:0];

  logic [31:0] isc_dop;
  logic        isc_dop_vld;
  logic        isc_dop_rdy;

  logic [31:0] isc_ack;
  logic        isc_ack_vld;
  logic        isc_ack_rdy;

  assign isc_dop          = axis_m_tx_tdata_tmp;
  assign isc_dop_vld      = axis_m_tx_tvalid;
  assign axis_m_tx_tready = isc_dop_rdy;

  assign axis_s_rx_tdata_tmp = isc_ack;
  assign axis_s_rx_tvalid    = isc_ack_vld;
  assign isc_ack_rdy         = axis_s_rx_tready;

  // line rate
  assign SW_REG_GT_LINE_RATE = {gt_line_rate, gt_line_rate, gt_line_rate, gt_line_rate};

  // =========================================================================================== //
  // SHELL
  // based on aved example design
  // + AXI-4-full interface
  // + AXI-4-stream interface
  // =========================================================================================== //
  hpu_plug_wrapper hpu_plug_wrapper (
    /* Interrupts
    * -> PL RPU lpd
    *    - has two interrupts already :
    *    - pl_ps_irq0 is linked to irq_gcq_m2r
    *    - from 1:6 we define them by rtl
    * -> CPM
    *    - cpm_irq_0 is linked to axistream module
    */
    .rtl_interrupt(rtl_interrupt),

    /* DDR connection
    * this must pass on top module IOs
    */
    // First channel
    .CH0_DDR4_0_0_act_n  (top_CH0_DDR4_0_0_act_n  ),
    .CH0_DDR4_0_0_adr    (top_CH0_DDR4_0_0_adr    ),
    .CH0_DDR4_0_0_ba     (top_CH0_DDR4_0_0_ba     ),
    .CH0_DDR4_0_0_bg     (top_CH0_DDR4_0_0_bg     ),
    .CH0_DDR4_0_0_ck_c   (top_CH0_DDR4_0_0_ck_c   ),
    .CH0_DDR4_0_0_ck_t   (top_CH0_DDR4_0_0_ck_t   ),
    .CH0_DDR4_0_0_cke    (top_CH0_DDR4_0_0_cke    ),
    .CH0_DDR4_0_0_cs_n   (top_CH0_DDR4_0_0_cs_n   ),
    .CH0_DDR4_0_0_dm_n   (top_CH0_DDR4_0_0_dm_n   ),
    .CH0_DDR4_0_0_dq     (top_CH0_DDR4_0_0_dq     ),
    .CH0_DDR4_0_0_dqs_c  (top_CH0_DDR4_0_0_dqs_c  ),
    .CH0_DDR4_0_0_dqs_t  (top_CH0_DDR4_0_0_dqs_t  ),
    .CH0_DDR4_0_0_odt    (top_CH0_DDR4_0_0_odt    ),
    .CH0_DDR4_0_0_reset_n(top_CH0_DDR4_0_0_reset_n),
    // Second channel
    .CH0_DDR4_0_1_act_n  (top_CH0_DDR4_0_1_act_n  ),
    .CH0_DDR4_0_1_adr    (top_CH0_DDR4_0_1_adr    ),
    .CH0_DDR4_0_1_alert_n(top_CH0_DDR4_0_1_alert_n),
    .CH0_DDR4_0_1_ba     (top_CH0_DDR4_0_1_ba     ),
    .CH0_DDR4_0_1_bg     (top_CH0_DDR4_0_1_bg     ),
    .CH0_DDR4_0_1_ck_c   (top_CH0_DDR4_0_1_ck_c   ),
    .CH0_DDR4_0_1_ck_t   (top_CH0_DDR4_0_1_ck_t   ),
    .CH0_DDR4_0_1_cke    (top_CH0_DDR4_0_1_cke    ),
    .CH0_DDR4_0_1_cs_n   (top_CH0_DDR4_0_1_cs_n   ),
    .CH0_DDR4_0_1_dq     (top_CH0_DDR4_0_1_dq     ),
    .CH0_DDR4_0_1_dqs_c  (top_CH0_DDR4_0_1_dqs_c  ),
    .CH0_DDR4_0_1_dqs_t  (top_CH0_DDR4_0_1_dqs_t  ),
    .CH0_DDR4_0_1_odt    (top_CH0_DDR4_0_1_odt    ),
    .CH0_DDR4_0_1_par    (top_CH0_DDR4_0_1_par    ),
    .CH0_DDR4_0_1_reset_n(top_CH0_DDR4_0_1_reset_n),

    /* AXI-4
     * low power domain coming from RPU through NoC
     * axi_lpd is coming out from block design with address space >= x8000'0000
     * S_REGIF_AXI_* is targeting NSU, address must be over 0x201'0000'0000
     * M_REGF_AXI_* going to NMU
     */
    .axi_lpd_araddr  (axi_lpd_araddr  ),
    .axi_lpd_arburst (axi_lpd_arburst ),
    .axi_lpd_arcache (axi_lpd_arcache ),
    .axi_lpd_arlen   (axi_lpd_arlen   ),
    .axi_lpd_arlock  (axi_lpd_arlock  ),
    .axi_lpd_arprot  (axi_lpd_arprot  ),
    .axi_lpd_arqos   (axi_lpd_arqos   ),
    .axi_lpd_arready (axi_lpd_arready ),
    .axi_lpd_arsize  (axi_lpd_arsize  ),
    .axi_lpd_aruser  (axi_lpd_aruser  ),
    .axi_lpd_arvalid (axi_lpd_arvalid ),
    .axi_lpd_awaddr  (axi_lpd_awaddr  ),
    .axi_lpd_awburst (axi_lpd_awburst ),
    .axi_lpd_awcache (axi_lpd_awcache ),
    .axi_lpd_awlen   (axi_lpd_awlen   ),
    .axi_lpd_awlock  (axi_lpd_awlock  ),
    .axi_lpd_awprot  (axi_lpd_awprot  ),
    .axi_lpd_awqos   (axi_lpd_awqos   ),
    .axi_lpd_awready (axi_lpd_awready ),
    .axi_lpd_awsize  (axi_lpd_awsize  ),
    .axi_lpd_awuser  (axi_lpd_awuser  ),
    .axi_lpd_awvalid (axi_lpd_awvalid ),
    .axi_lpd_bready  (axi_lpd_bready  ),
    .axi_lpd_bresp   (axi_lpd_bresp   ),
    .axi_lpd_bvalid  (axi_lpd_bvalid  ),
    .axi_lpd_rdata   (axi_lpd_rdata   ),
    .axi_lpd_rlast   (axi_lpd_rlast   ),
    .axi_lpd_rready  (axi_lpd_rready  ),
    .axi_lpd_rresp   (axi_lpd_rresp   ),
    .axi_lpd_rvalid  (axi_lpd_rvalid  ),
    .axi_lpd_wdata   (axi_lpd_wdata   ),
    .axi_lpd_wlast   (axi_lpd_wlast   ),
    .axi_lpd_wready  (axi_lpd_wready  ),
    .axi_lpd_wstrb   (axi_lpd_wstrb   ),
    .axi_lpd_wvalid  (axi_lpd_wvalid  ),

    // insertion of axi4 axi_lpd into noc
    // note that axi_lpd_aXaddr are 32 bit words
    .S_REGIF_AXI_0_araddr   ({'h00000201, axi_lpd_araddr}),
    .S_REGIF_AXI_0_arburst  (axi_lpd_arburst),
    .S_REGIF_AXI_0_arcache  (axi_lpd_arcache),
    .S_REGIF_AXI_0_arlen    (axi_lpd_arlen),
    .S_REGIF_AXI_0_arlock   (axi_lpd_arlock),
    .S_REGIF_AXI_0_arprot   (axi_lpd_arprot),
    .S_REGIF_AXI_0_arqos    (axi_lpd_arqos),
    .S_REGIF_AXI_0_arready  (axi_lpd_arready),
    .S_REGIF_AXI_0_arregion ('0), // UNUSED
    .S_REGIF_AXI_0_arsize   (axi_lpd_arsize),
    .S_REGIF_AXI_0_arvalid  (axi_lpd_arvalid),
    .S_REGIF_AXI_0_awaddr   ({'h00000201, axi_lpd_awaddr}),
    .S_REGIF_AXI_0_awburst  (axi_lpd_awburst),
    .S_REGIF_AXI_0_awcache  (axi_lpd_awcache),
    .S_REGIF_AXI_0_awlen    (axi_lpd_awlen),
    .S_REGIF_AXI_0_awlock   (axi_lpd_awlock),
    .S_REGIF_AXI_0_awprot   (axi_lpd_awprot),
    .S_REGIF_AXI_0_awqos    (axi_lpd_awqos),
    .S_REGIF_AXI_0_awready  (axi_lpd_awready),
    .S_REGIF_AXI_0_awregion ('0), // UNUSED
    .S_REGIF_AXI_0_awsize   (axi_lpd_awsize),
    .S_REGIF_AXI_0_awvalid  (axi_lpd_awvalid),
    .S_REGIF_AXI_0_bready   (axi_lpd_bready),
    .S_REGIF_AXI_0_bresp    (axi_lpd_bresp),
    .S_REGIF_AXI_0_bvalid   (axi_lpd_bvalid),
    .S_REGIF_AXI_0_rdata    (axi_lpd_rdata),
    .S_REGIF_AXI_0_rlast    (axi_lpd_rlast),
    .S_REGIF_AXI_0_rready   (axi_lpd_rready),
    .S_REGIF_AXI_0_rresp    (axi_lpd_rresp),
    .S_REGIF_AXI_0_rvalid   (axi_lpd_rvalid),
    .S_REGIF_AXI_0_wdata    (axi_lpd_wdata),
    .S_REGIF_AXI_0_wlast    (axi_lpd_wlast),
    .S_REGIF_AXI_0_wready   (axi_lpd_wready),
    .S_REGIF_AXI_0_wstrb    (axi_lpd_wstrb),
    .S_REGIF_AXI_0_wvalid   (axi_lpd_wvalid),

    // axi4-lite going to regfile
    .REGIF_AXI_0_0_araddr   (axi_regif_prc_araddr[0]),
    .REGIF_AXI_0_0_arprot   (axi_regif_prc_arprot[0]),
    .REGIF_AXI_0_0_arready  (axi_regif_prc_arready[0]),
    .REGIF_AXI_0_0_arvalid  (axi_regif_prc_arvalid[0]),
    .REGIF_AXI_0_0_awaddr   (axi_regif_prc_awaddr[0]),
    .REGIF_AXI_0_0_awprot   (axi_regif_prc_awprot[0]),
    .REGIF_AXI_0_0_awready  (axi_regif_prc_awready[0]),
    .REGIF_AXI_0_0_awvalid  (axi_regif_prc_awvalid[0]),
    .REGIF_AXI_0_0_bready   (axi_regif_prc_bready[0]),
    .REGIF_AXI_0_0_bresp    (axi_regif_prc_bresp[0]),
    .REGIF_AXI_0_0_bvalid   (axi_regif_prc_bvalid[0]),
    .REGIF_AXI_0_0_rdata    (axi_regif_prc_rdata[0]),
    .REGIF_AXI_0_0_rready   (axi_regif_prc_rready[0]),
    .REGIF_AXI_0_0_rresp    (axi_regif_prc_rresp[0]),
    .REGIF_AXI_0_0_rvalid   (axi_regif_prc_rvalid[0]),
    .REGIF_AXI_0_0_wdata    (axi_regif_prc_wdata[0]),
    .REGIF_AXI_0_0_wready   (axi_regif_prc_wready[0]),
    .REGIF_AXI_0_0_wstrb    (axi_regif_prc_wstrb[0]),
    .REGIF_AXI_0_0_wvalid   (axi_regif_prc_wvalid[0]),

    .REGIF_AXI_0_1_araddr   (axi_regif_cfg_araddr[0]),
    .REGIF_AXI_0_1_arprot   (axi_regif_cfg_arprot[0]),
    .REGIF_AXI_0_1_arready  (axi_regif_cfg_arready[0]),
    .REGIF_AXI_0_1_arvalid  (axi_regif_cfg_arvalid[0]),
    .REGIF_AXI_0_1_awaddr   (axi_regif_cfg_awaddr[0]),
    .REGIF_AXI_0_1_awprot   (axi_regif_cfg_awprot[0]),
    .REGIF_AXI_0_1_awready  (axi_regif_cfg_awready[0]),
    .REGIF_AXI_0_1_awvalid  (axi_regif_cfg_awvalid[0]),
    .REGIF_AXI_0_1_bready   (axi_regif_cfg_bready[0]),
    .REGIF_AXI_0_1_bresp    (axi_regif_cfg_bresp[0]),
    .REGIF_AXI_0_1_bvalid   (axi_regif_cfg_bvalid[0]),
    .REGIF_AXI_0_1_rdata    (axi_regif_cfg_rdata[0]),
    .REGIF_AXI_0_1_rready   (axi_regif_cfg_rready[0]),
    .REGIF_AXI_0_1_rresp    (axi_regif_cfg_rresp[0]),
    .REGIF_AXI_0_1_rvalid   (axi_regif_cfg_rvalid[0]),
    .REGIF_AXI_0_1_wdata    (axi_regif_cfg_wdata[0]),
    .REGIF_AXI_0_1_wready   (axi_regif_cfg_wready[0]),
    .REGIF_AXI_0_1_wstrb    (axi_regif_cfg_wstrb[0]),
    .REGIF_AXI_0_1_wvalid   (axi_regif_cfg_wvalid[0]),

    .REGIF_AXI_1_0_araddr   (axi_regif_prc_araddr[1]),
    .REGIF_AXI_1_0_arprot   (axi_regif_prc_arprot[1]),
    .REGIF_AXI_1_0_arready  (axi_regif_prc_arready[1]),
    .REGIF_AXI_1_0_arvalid  (axi_regif_prc_arvalid[1]),
    .REGIF_AXI_1_0_awaddr   (axi_regif_prc_awaddr[1]),
    .REGIF_AXI_1_0_awprot   (axi_regif_prc_awprot[1]),
    .REGIF_AXI_1_0_awready  (axi_regif_prc_awready[1]),
    .REGIF_AXI_1_0_awvalid  (axi_regif_prc_awvalid[1]),
    .REGIF_AXI_1_0_bready   (axi_regif_prc_bready[1]),
    .REGIF_AXI_1_0_bresp    (axi_regif_prc_bresp[1]),
    .REGIF_AXI_1_0_bvalid   (axi_regif_prc_bvalid[1]),
    .REGIF_AXI_1_0_rdata    (axi_regif_prc_rdata[1]),
    .REGIF_AXI_1_0_rready   (axi_regif_prc_rready[1]),
    .REGIF_AXI_1_0_rresp    (axi_regif_prc_rresp[1]),
    .REGIF_AXI_1_0_rvalid   (axi_regif_prc_rvalid[1]),
    .REGIF_AXI_1_0_wdata    (axi_regif_prc_wdata[1]),
    .REGIF_AXI_1_0_wready   (axi_regif_prc_wready[1]),
    .REGIF_AXI_1_0_wstrb    (axi_regif_prc_wstrb[1]),
    .REGIF_AXI_1_0_wvalid   (axi_regif_prc_wvalid[1]),

    .REGIF_AXI_1_1_araddr   (axi_regif_cfg_araddr[1]),
    .REGIF_AXI_1_1_arprot   (axi_regif_cfg_arprot[1]),
    .REGIF_AXI_1_1_arready  (axi_regif_cfg_arready[1]),
    .REGIF_AXI_1_1_arvalid  (axi_regif_cfg_arvalid[1]),
    .REGIF_AXI_1_1_awaddr   (axi_regif_cfg_awaddr[1]),
    .REGIF_AXI_1_1_awprot   (axi_regif_cfg_awprot[1]),
    .REGIF_AXI_1_1_awready  (axi_regif_cfg_awready[1]),
    .REGIF_AXI_1_1_awvalid  (axi_regif_cfg_awvalid[1]),
    .REGIF_AXI_1_1_bready   (axi_regif_cfg_bready[1]),
    .REGIF_AXI_1_1_bresp    (axi_regif_cfg_bresp[1]),
    .REGIF_AXI_1_1_bvalid   (axi_regif_cfg_bvalid[1]),
    .REGIF_AXI_1_1_rdata    (axi_regif_cfg_rdata[1]),
    .REGIF_AXI_1_1_rready   (axi_regif_cfg_rready[1]),
    .REGIF_AXI_1_1_rresp    (axi_regif_cfg_rresp[1]),
    .REGIF_AXI_1_1_rvalid   (axi_regif_cfg_rvalid[1]),
    .REGIF_AXI_1_1_wdata    (axi_regif_cfg_wdata[1]),
    .REGIF_AXI_1_1_wready   (axi_regif_cfg_wready[1]),
    .REGIF_AXI_1_1_wstrb    (axi_regif_cfg_wstrb[1]),
    .REGIF_AXI_1_1_wvalid   (axi_regif_cfg_wvalid[1]),

    /* AXI-4 to HBMs */
    // 1 trace
    .TRC_AXI_0_awaddr  (m_axi4_trc_awaddr  ),
    .TRC_AXI_0_awburst (m_axi4_trc_awburst ),
    .TRC_AXI_0_awcache (m_axi4_trc_awcache ),
    .TRC_AXI_0_awid    (m_axi4_trc_awid    ),
    .TRC_AXI_0_awlen   (m_axi4_trc_awlen   ),
    .TRC_AXI_0_awlock  (m_axi4_trc_awlock  ),
    .TRC_AXI_0_awprot  (m_axi4_trc_awprot  ),
    .TRC_AXI_0_awready (m_axi4_trc_awready ),
    .TRC_AXI_0_awsize  (m_axi4_trc_awsize  ),
    .TRC_AXI_0_awuser  ('0 /*UNUSED*/      ),
    .TRC_AXI_0_awvalid (m_axi4_trc_awvalid ),
    .TRC_AXI_0_bid     (m_axi4_trc_bid     ),
    .TRC_AXI_0_bready  (m_axi4_trc_bready  ),
    .TRC_AXI_0_bresp   (m_axi4_trc_bresp   ),
    .TRC_AXI_0_bvalid  (m_axi4_trc_bvalid  ),
    .TRC_AXI_0_wdata   (m_axi4_trc_wdata   ),
    .TRC_AXI_0_wlast   (m_axi4_trc_wlast   ),
    .TRC_AXI_0_wready  (m_axi4_trc_wready  ),
    .TRC_AXI_0_wstrb   (m_axi4_trc_wstrb   ),
    .TRC_AXI_0_wvalid  (m_axi4_trc_wvalid  ),
    .TRC_AXI_0_araddr  (m_axi4_trc_araddr  ),
    .TRC_AXI_0_arburst (m_axi4_trc_arburst ),
    .TRC_AXI_0_arcache (m_axi4_trc_arcache ),
    .TRC_AXI_0_arid    (m_axi4_trc_arid    ),
    .TRC_AXI_0_arlen   (m_axi4_trc_arlen   ),
    .TRC_AXI_0_arlock  (m_axi4_trc_arlock  ),
    .TRC_AXI_0_arprot  (m_axi4_trc_arprot  ),
    .TRC_AXI_0_arready (m_axi4_trc_arready ),
    .TRC_AXI_0_arsize  (m_axi4_trc_arsize  ),
    //.TRC_AXI_0_aruser  (m_axi4_trc_aruser  ),
    .TRC_AXI_0_arvalid (m_axi4_trc_arvalid ),

    // 2 pem
    .CT_AXI_0_araddr  (m_axi4_pem_araddr[0]  ),
    .CT_AXI_0_arburst (m_axi4_pem_arburst[0] ),
    .CT_AXI_0_arcache (m_axi4_pem_arcache[0] ),
    .CT_AXI_0_arid    (m_axi4_pem_arid[0]    ),
    .CT_AXI_0_arlen   (m_axi4_pem_arlen[0]   ),
    .CT_AXI_0_arlock  (m_axi4_pem_arlock[0]  ),
    .CT_AXI_0_arprot  (m_axi4_pem_arprot[0]  ),
    .CT_AXI_0_arready (m_axi4_pem_arready[0] ),
    .CT_AXI_0_arsize  (m_axi4_pem_arsize[0]  ),
    //.CT_AXI_0_aruser  (m_axi4_pem_aruser[0]  ),
    .CT_AXI_0_arvalid (m_axi4_pem_arvalid[0] ),
    .CT_AXI_0_awaddr  (m_axi4_pem_awaddr[0]  ),
    .CT_AXI_0_awburst (m_axi4_pem_awburst[0] ),
    .CT_AXI_0_awcache (m_axi4_pem_awcache[0] ),
    .CT_AXI_0_awid    (m_axi4_pem_awid[0]    ),
    .CT_AXI_0_awlen   (m_axi4_pem_awlen[0]   ),
    .CT_AXI_0_awlock  (m_axi4_pem_awlock[0]  ),
    .CT_AXI_0_awprot  (m_axi4_pem_awprot[0]  ),
    .CT_AXI_0_awready (m_axi4_pem_awready[0] ),
    .CT_AXI_0_awsize  (m_axi4_pem_awsize[0]  ),
    //.CT_AXI_0_awuser  (m_axi4_pem_awuser[0]  ),
    .CT_AXI_0_awvalid (m_axi4_pem_awvalid[0] ),
    .CT_AXI_0_bid     (m_axi4_pem_bid[0]     ),
    .CT_AXI_0_bready  (m_axi4_pem_bready[0]  ),
    .CT_AXI_0_bresp   (m_axi4_pem_bresp[0]   ),
    //.CT_AXI_0_buser   (m_axi4_pem_buser[0]   ),
    .CT_AXI_0_bvalid  (m_axi4_pem_bvalid[0]  ),
    .CT_AXI_0_rdata   (m_axi4_pem_rdata[0]   ),
    .CT_AXI_0_rid     (m_axi4_pem_rid[0]     ),
    .CT_AXI_0_rlast   (m_axi4_pem_rlast[0]   ),
    .CT_AXI_0_rready  (m_axi4_pem_rready[0]  ),
    .CT_AXI_0_rresp   (m_axi4_pem_rresp[0]   ),
    .CT_AXI_0_rvalid  (m_axi4_pem_rvalid[0]  ),
    .CT_AXI_0_wdata   (m_axi4_pem_wdata[0]   ),
    .CT_AXI_0_wlast   (m_axi4_pem_wlast[0]   ),
    .CT_AXI_0_wready  (m_axi4_pem_wready[0]  ),
    .CT_AXI_0_wstrb   (m_axi4_pem_wstrb[0]   ),
    .CT_AXI_0_wvalid  (m_axi4_pem_wvalid[0]  ),
    .CT_AXI_1_araddr  (m_axi4_pem_araddr[1]  ),
    .CT_AXI_1_arburst (m_axi4_pem_arburst[1] ),
    .CT_AXI_1_arcache (m_axi4_pem_arcache[1] ),
    .CT_AXI_1_arid    (m_axi4_pem_arid[1]    ),
    .CT_AXI_1_arlen   (m_axi4_pem_arlen[1]   ),
    .CT_AXI_1_arlock  (m_axi4_pem_arlock[1]  ),
    .CT_AXI_1_arprot  (m_axi4_pem_arprot[1]  ),
    .CT_AXI_1_arready (m_axi4_pem_arready[1] ),
    .CT_AXI_1_arsize  (m_axi4_pem_arsize[1]  ),
    //.CT_AXI_1_aruser  (m_axi4_pem_aruser[1]  ),
    .CT_AXI_1_arvalid (m_axi4_pem_arvalid[1] ),
    .CT_AXI_1_awaddr  (m_axi4_pem_awaddr[1]  ),
    .CT_AXI_1_awburst (m_axi4_pem_awburst[1] ),
    .CT_AXI_1_awcache (m_axi4_pem_awcache[1] ),
    .CT_AXI_1_awid    (m_axi4_pem_awid[1]    ),
    .CT_AXI_1_awlen   (m_axi4_pem_awlen[1]   ),
    .CT_AXI_1_awlock  (m_axi4_pem_awlock[1]  ),
    .CT_AXI_1_awprot  (m_axi4_pem_awprot[1]  ),
    .CT_AXI_1_awready (m_axi4_pem_awready[1] ),
    .CT_AXI_1_awsize  (m_axi4_pem_awsize[1]  ),
    //.CT_AXI_1_awuser  (m_axi4_pem_awuser[1]  ),
    .CT_AXI_1_awvalid (m_axi4_pem_awvalid[1] ),
    .CT_AXI_1_bid     (m_axi4_pem_bid[1]     ),
    .CT_AXI_1_bready  (m_axi4_pem_bready[1]  ),
    .CT_AXI_1_bresp   (m_axi4_pem_bresp[1]   ),
    //.CT_AXI_1_buser   (m_axi4_pem_buser[1]   ),
    .CT_AXI_1_bvalid  (m_axi4_pem_bvalid[1]  ),
    .CT_AXI_1_rdata   (m_axi4_pem_rdata[1]   ),
    .CT_AXI_1_rid     (m_axi4_pem_rid[1]     ),
    .CT_AXI_1_rlast   (m_axi4_pem_rlast[1]   ),
    .CT_AXI_1_rready  (m_axi4_pem_rready[1]  ),
    .CT_AXI_1_rresp   (m_axi4_pem_rresp[1]   ),
    .CT_AXI_1_rvalid  (m_axi4_pem_rvalid[1]  ),
    .CT_AXI_1_wdata   (m_axi4_pem_wdata[1]   ),
    .CT_AXI_1_wlast   (m_axi4_pem_wlast[1]   ),
    .CT_AXI_1_wready  (m_axi4_pem_wready[1]  ),
    .CT_AXI_1_wstrb   (m_axi4_pem_wstrb[1]   ),
    .CT_AXI_1_wvalid  (m_axi4_pem_wvalid[1]  ),

    .GLWE_AXI_0_araddr  (m_axi4_glwe_araddr[0]  ),
    .GLWE_AXI_0_arburst (m_axi4_glwe_arburst[0] ),
    .GLWE_AXI_0_arcache (m_axi4_glwe_arcache[0] ),
    .GLWE_AXI_0_arid    (m_axi4_glwe_arid[0]    ),
    .GLWE_AXI_0_arlen   (m_axi4_glwe_arlen[0]   ),
    .GLWE_AXI_0_arlock  (m_axi4_glwe_arlock[0]  ),
    .GLWE_AXI_0_arprot  (m_axi4_glwe_arprot[0]  ),
    .GLWE_AXI_0_arready (m_axi4_glwe_arready[0] ),
    .GLWE_AXI_0_arsize  (m_axi4_glwe_arsize[0]  ),
    //.GLWE_AXI_0_aruser  (m_axi4_glwe_aruser[0]  ),
    .GLWE_AXI_0_arvalid (m_axi4_glwe_arvalid[0] ),
    .GLWE_AXI_0_awaddr  (m_axi4_glwe_awaddr[0]  ),
    .GLWE_AXI_0_awburst (m_axi4_glwe_awburst[0] ),
    .GLWE_AXI_0_awcache (m_axi4_glwe_awcache[0] ),
    .GLWE_AXI_0_awid    (m_axi4_glwe_awid[0]    ),
    .GLWE_AXI_0_awlen   (m_axi4_glwe_awlen[0]   ),
    .GLWE_AXI_0_awlock  (m_axi4_glwe_awlock[0]  ),
    .GLWE_AXI_0_awprot  (m_axi4_glwe_awprot[0]  ),
    .GLWE_AXI_0_awready (m_axi4_glwe_awready[0] ),
    .GLWE_AXI_0_awsize  (m_axi4_glwe_awsize[0]  ),
    //.GLWE_AXI_0_awuser  (m_axi4_glwe_awuser[0]  ),
    .GLWE_AXI_0_awvalid (m_axi4_glwe_awvalid[0] ),
    .GLWE_AXI_0_bid     (m_axi4_glwe_bid[0]     ),
    .GLWE_AXI_0_bready  (m_axi4_glwe_bready[0]  ),
    .GLWE_AXI_0_bresp   (m_axi4_glwe_bresp[0]   ),
    //.GLWE_AXI_0_buser   (m_axi4_glwe_buser[0]   ),
    .GLWE_AXI_0_bvalid  (m_axi4_glwe_bvalid[0]  ),
    .GLWE_AXI_0_rdata   (m_axi4_glwe_rdata[0]   ),
    .GLWE_AXI_0_rid     (m_axi4_glwe_rid[0]     ),
    .GLWE_AXI_0_rlast   (m_axi4_glwe_rlast[0]   ),
    .GLWE_AXI_0_rready  (m_axi4_glwe_rready[0]  ),
    .GLWE_AXI_0_rresp   (m_axi4_glwe_rresp[0]   ),
    .GLWE_AXI_0_rvalid  (m_axi4_glwe_rvalid[0]  ),
    .GLWE_AXI_0_wdata   (m_axi4_glwe_wdata[0]   ),
    .GLWE_AXI_0_wlast   (m_axi4_glwe_wlast[0]   ),
    .GLWE_AXI_0_wready  (m_axi4_glwe_wready[0]  ),
    .GLWE_AXI_0_wstrb   (m_axi4_glwe_wstrb[0]   ),
    .GLWE_AXI_0_wvalid  (m_axi4_glwe_wvalid[0]  ),

    .BSK_AXI_0_araddr  (m_axi4_bsk_araddr[0]  ),
    .BSK_AXI_0_arburst (m_axi4_bsk_arburst[0] ),
    .BSK_AXI_0_arcache (m_axi4_bsk_arcache[0] ),
    //.BSK_AXI_0_arid    (m_axi4_bsk_arid[0]    ),
    .BSK_AXI_0_arlen   (m_axi4_bsk_arlen[0]   ),
    .BSK_AXI_0_arlock  (m_axi4_bsk_arlock[0]  ),
    .BSK_AXI_0_arprot  (m_axi4_bsk_arprot[0]  ),
    .BSK_AXI_0_arready (m_axi4_bsk_arready[0] ),
    .BSK_AXI_0_arsize  (m_axi4_bsk_arsize[0]  ),
    //.BSK_AXI_0_aruser  (m_axi4_bsk_aruser[0]  ),
    .BSK_AXI_0_arvalid (m_axi4_bsk_arvalid[0] ),
    .BSK_AXI_0_awaddr  (m_axi4_bsk_awaddr[0]  ),
    .BSK_AXI_0_awburst (m_axi4_bsk_awburst[0] ),
    .BSK_AXI_0_awcache (m_axi4_bsk_awcache[0] ),
    //.BSK_AXI_0_awid    (m_axi4_bsk_awid[0]    ),
    .BSK_AXI_0_awlen   (m_axi4_bsk_awlen[0]   ),
    .BSK_AXI_0_awlock  (m_axi4_bsk_awlock[0]  ),
    .BSK_AXI_0_awprot  (m_axi4_bsk_awprot[0]  ),
    .BSK_AXI_0_awready (m_axi4_bsk_awready[0] ),
    .BSK_AXI_0_awsize  (m_axi4_bsk_awsize[0]  ),
    //.BSK_AXI_0_awuser  (m_axi4_bsk_awuser[0]  ),
    .BSK_AXI_0_awvalid (m_axi4_bsk_awvalid[0] ),
    //.BSK_AXI_0_bid     (m_axi4_bsk_bid[0]     ),
    .BSK_AXI_0_bready  (m_axi4_bsk_bready[0]  ),
    .BSK_AXI_0_bresp   (m_axi4_bsk_bresp[0]   ),
    //.BSK_AXI_0_buser   (m_axi4_bsk_buser[0]   ),
    .BSK_AXI_0_bvalid  (m_axi4_bsk_bvalid[0]  ),
    .BSK_AXI_0_rdata   (m_axi4_bsk_rdata[0]   ),
    //.BSK_AXI_0_rid     (m_axi4_bsk_rid[0]     ),
    .BSK_AXI_0_rlast   (m_axi4_bsk_rlast[0]   ),
    .BSK_AXI_0_rready  (m_axi4_bsk_rready[0]  ),
    .BSK_AXI_0_rresp   (m_axi4_bsk_rresp[0]   ),
    .BSK_AXI_0_rvalid  (m_axi4_bsk_rvalid[0]  ),
    .BSK_AXI_0_wdata   (m_axi4_bsk_wdata[0]   ),
    .BSK_AXI_0_wlast   (m_axi4_bsk_wlast[0]   ),
    .BSK_AXI_0_wready  (m_axi4_bsk_wready[0]  ),
    .BSK_AXI_0_wstrb   (m_axi4_bsk_wstrb[0]   ),
    .BSK_AXI_0_wvalid  (m_axi4_bsk_wvalid[0]  ),
    .BSK_AXI_1_araddr  (m_axi4_bsk_araddr[1]  ),
    .BSK_AXI_1_arburst (m_axi4_bsk_arburst[1] ),
    .BSK_AXI_1_arcache (m_axi4_bsk_arcache[1] ),
    //.BSK_AXI_1_arid    (m_axi4_bsk_arid[1]    ),
    .BSK_AXI_1_arlen   (m_axi4_bsk_arlen[1]   ),
    .BSK_AXI_1_arlock  (m_axi4_bsk_arlock[1]  ),
    .BSK_AXI_1_arprot  (m_axi4_bsk_arprot[1]  ),
    .BSK_AXI_1_arready (m_axi4_bsk_arready[1] ),
    .BSK_AXI_1_arsize  (m_axi4_bsk_arsize[1]  ),
    //.BSK_AXI_1_aruser  (m_axi4_bsk_aruser[1]  ),
    .BSK_AXI_1_arvalid (m_axi4_bsk_arvalid[1] ),
    .BSK_AXI_1_awaddr  (m_axi4_bsk_awaddr[1]  ),
    .BSK_AXI_1_awburst (m_axi4_bsk_awburst[1] ),
    .BSK_AXI_1_awcache (m_axi4_bsk_awcache[1] ),
    //.BSK_AXI_1_awid    (m_axi4_bsk_awid[1]    ),
    .BSK_AXI_1_awlen   (m_axi4_bsk_awlen[1]   ),
    .BSK_AXI_1_awlock  (m_axi4_bsk_awlock[1]  ),
    .BSK_AXI_1_awprot  (m_axi4_bsk_awprot[1]  ),
    .BSK_AXI_1_awready (m_axi4_bsk_awready[1] ),
    .BSK_AXI_1_awsize  (m_axi4_bsk_awsize[1]  ),
    //.BSK_AXI_1_awuser  (m_axi4_bsk_awuser[1]  ),
    .BSK_AXI_1_awvalid (m_axi4_bsk_awvalid[1] ),
    //.BSK_AXI_1_bid     (m_axi4_bsk_bid[1]     ),
    .BSK_AXI_1_bready  (m_axi4_bsk_bready[1]  ),
    .BSK_AXI_1_bresp   (m_axi4_bsk_bresp[1]   ),
    //.BSK_AXI_1_buser   (m_axi4_bsk_buser[1]   ),
    .BSK_AXI_1_bvalid  (m_axi4_bsk_bvalid[1]  ),
    .BSK_AXI_1_rdata   (m_axi4_bsk_rdata[1]   ),
    //.BSK_AXI_1_rid     (m_axi4_bsk_rid[1]     ),
    .BSK_AXI_1_rlast   (m_axi4_bsk_rlast[1]   ),
    .BSK_AXI_1_rready  (m_axi4_bsk_rready[1]  ),
    .BSK_AXI_1_rresp   (m_axi4_bsk_rresp[1]   ),
    .BSK_AXI_1_rvalid  (m_axi4_bsk_rvalid[1]  ),
    .BSK_AXI_1_wdata   (m_axi4_bsk_wdata[1]   ),
    .BSK_AXI_1_wlast   (m_axi4_bsk_wlast[1]   ),
    .BSK_AXI_1_wready  (m_axi4_bsk_wready[1]  ),
    .BSK_AXI_1_wstrb   (m_axi4_bsk_wstrb[1]   ),
    .BSK_AXI_1_wvalid  (m_axi4_bsk_wvalid[1]  ),
    .BSK_AXI_2_araddr  (m_axi4_bsk_araddr[2]  ),
    .BSK_AXI_2_arburst (m_axi4_bsk_arburst[2] ),
    .BSK_AXI_2_arcache (m_axi4_bsk_arcache[2] ),
    //.BSK_AXI_2_arid    (m_axi4_bsk_arid[2]    ),
    .BSK_AXI_2_arlen   (m_axi4_bsk_arlen[2]   ),
    .BSK_AXI_2_arlock  (m_axi4_bsk_arlock[2]  ),
    .BSK_AXI_2_arprot  (m_axi4_bsk_arprot[2]  ),
    .BSK_AXI_2_arready (m_axi4_bsk_arready[2] ),
    .BSK_AXI_2_arsize  (m_axi4_bsk_arsize[2]  ),
    //.BSK_AXI_2_aruser  (m_axi4_bsk_aruser[2]  ),
    .BSK_AXI_2_arvalid (m_axi4_bsk_arvalid[2] ),
    .BSK_AXI_2_awaddr  (m_axi4_bsk_awaddr[2]  ),
    .BSK_AXI_2_awburst (m_axi4_bsk_awburst[2] ),
    .BSK_AXI_2_awcache (m_axi4_bsk_awcache[2] ),
    //.BSK_AXI_2_awid    (m_axi4_bsk_awid[2]    ),
    .BSK_AXI_2_awlen   (m_axi4_bsk_awlen[2]   ),
    .BSK_AXI_2_awlock  (m_axi4_bsk_awlock[2]  ),
    .BSK_AXI_2_awprot  (m_axi4_bsk_awprot[2]  ),
    .BSK_AXI_2_awready (m_axi4_bsk_awready[2] ),
    .BSK_AXI_2_awsize  (m_axi4_bsk_awsize[2]  ),
    //.BSK_AXI_2_awuser  (m_axi4_bsk_awuser[2]  ),
    .BSK_AXI_2_awvalid (m_axi4_bsk_awvalid[2] ),
    //.BSK_AXI_2_bid     (m_axi4_bsk_bid[2]     ),
    .BSK_AXI_2_bready  (m_axi4_bsk_bready[2]  ),
    .BSK_AXI_2_bresp   (m_axi4_bsk_bresp[2]   ),
    //.BSK_AXI_2_buser   (m_axi4_bsk_buser[2]   ),
    .BSK_AXI_2_bvalid  (m_axi4_bsk_bvalid[2]  ),
    .BSK_AXI_2_rdata   (m_axi4_bsk_rdata[2]   ),
    //.BSK_AXI_2_rid     (m_axi4_bsk_rid[2]     ),
    .BSK_AXI_2_rlast   (m_axi4_bsk_rlast[2]   ),
    .BSK_AXI_2_rready  (m_axi4_bsk_rready[2]  ),
    .BSK_AXI_2_rresp   (m_axi4_bsk_rresp[2]   ),
    .BSK_AXI_2_rvalid  (m_axi4_bsk_rvalid[2]  ),
    .BSK_AXI_2_wdata   (m_axi4_bsk_wdata[2]   ),
    .BSK_AXI_2_wlast   (m_axi4_bsk_wlast[2]   ),
    .BSK_AXI_2_wready  (m_axi4_bsk_wready[2]  ),
    .BSK_AXI_2_wstrb   (m_axi4_bsk_wstrb[2]   ),
    .BSK_AXI_2_wvalid  (m_axi4_bsk_wvalid[2]  ),
    .BSK_AXI_3_araddr  (m_axi4_bsk_araddr[3]  ),
    .BSK_AXI_3_arburst (m_axi4_bsk_arburst[3] ),
    .BSK_AXI_3_arcache (m_axi4_bsk_arcache[3] ),
    //.BSK_AXI_3_arid    (m_axi4_bsk_arid[3]    ),
    .BSK_AXI_3_arlen   (m_axi4_bsk_arlen[3]   ),
    .BSK_AXI_3_arlock  (m_axi4_bsk_arlock[3]  ),
    .BSK_AXI_3_arprot  (m_axi4_bsk_arprot[3]  ),
    .BSK_AXI_3_arready (m_axi4_bsk_arready[3] ),
    .BSK_AXI_3_arsize  (m_axi4_bsk_arsize[3]  ),
    //.BSK_AXI_3_aruser  (m_axi4_bsk_aruser[3]  ),
    .BSK_AXI_3_arvalid (m_axi4_bsk_arvalid[3] ),
    .BSK_AXI_3_awaddr  (m_axi4_bsk_awaddr[3]  ),
    .BSK_AXI_3_awburst (m_axi4_bsk_awburst[3] ),
    .BSK_AXI_3_awcache (m_axi4_bsk_awcache[3] ),
    //.BSK_AXI_3_awid    (m_axi4_bsk_awid[3]    ),
    .BSK_AXI_3_awlen   (m_axi4_bsk_awlen[3]   ),
    .BSK_AXI_3_awlock  (m_axi4_bsk_awlock[3]  ),
    .BSK_AXI_3_awprot  (m_axi4_bsk_awprot[3]  ),
    .BSK_AXI_3_awready (m_axi4_bsk_awready[3] ),
    .BSK_AXI_3_awsize  (m_axi4_bsk_awsize[3]  ),
    //.BSK_AXI_3_awuser  (m_axi4_bsk_awuser[3]  ),
    .BSK_AXI_3_awvalid (m_axi4_bsk_awvalid[3] ),
    //.BSK_AXI_3_bid     (m_axi4_bsk_bid[3]     ),
    .BSK_AXI_3_bready  (m_axi4_bsk_bready[3]  ),
    .BSK_AXI_3_bresp   (m_axi4_bsk_bresp[3]   ),
    //.BSK_AXI_3_buser   (m_axi4_bsk_buser[3]   ),
    .BSK_AXI_3_bvalid  (m_axi4_bsk_bvalid[3]  ),
    .BSK_AXI_3_rdata   (m_axi4_bsk_rdata[3]   ),
    //.BSK_AXI_3_rid     (m_axi4_bsk_rid[3]     ),
    .BSK_AXI_3_rlast   (m_axi4_bsk_rlast[3]   ),
    .BSK_AXI_3_rready  (m_axi4_bsk_rready[3]  ),
    .BSK_AXI_3_rresp   (m_axi4_bsk_rresp[3]   ),
    .BSK_AXI_3_rvalid  (m_axi4_bsk_rvalid[3]  ),
    .BSK_AXI_3_wdata   (m_axi4_bsk_wdata[3]   ),
    .BSK_AXI_3_wlast   (m_axi4_bsk_wlast[3]   ),
    .BSK_AXI_3_wready  (m_axi4_bsk_wready[3]  ),
    .BSK_AXI_3_wstrb   (m_axi4_bsk_wstrb[3]   ),
    .BSK_AXI_3_wvalid  (m_axi4_bsk_wvalid[3]  ),
    .BSK_AXI_4_araddr  (m_axi4_bsk_araddr[4]  ),
    .BSK_AXI_4_arburst (m_axi4_bsk_arburst[4] ),
    .BSK_AXI_4_arcache (m_axi4_bsk_arcache[4] ),
    //.BSK_AXI_4_arid    (m_axi4_bsk_arid[4]    ),
    .BSK_AXI_4_arlen   (m_axi4_bsk_arlen[4]   ),
    .BSK_AXI_4_arlock  (m_axi4_bsk_arlock[4]  ),
    .BSK_AXI_4_arprot  (m_axi4_bsk_arprot[4]  ),
    .BSK_AXI_4_arready (m_axi4_bsk_arready[4] ),
    .BSK_AXI_4_arsize  (m_axi4_bsk_arsize[4]  ),
    //.BSK_AXI_4_aruser  (m_axi4_bsk_aruser[4]  ),
    .BSK_AXI_4_arvalid (m_axi4_bsk_arvalid[4] ),
    .BSK_AXI_4_awaddr  (m_axi4_bsk_awaddr[4]  ),
    .BSK_AXI_4_awburst (m_axi4_bsk_awburst[4] ),
    .BSK_AXI_4_awcache (m_axi4_bsk_awcache[4] ),
    //.BSK_AXI_4_awid    (m_axi4_bsk_awid[4]    ),
    .BSK_AXI_4_awlen   (m_axi4_bsk_awlen[4]   ),
    .BSK_AXI_4_awlock  (m_axi4_bsk_awlock[4]  ),
    .BSK_AXI_4_awprot  (m_axi4_bsk_awprot[4]  ),
    .BSK_AXI_4_awready (m_axi4_bsk_awready[4] ),
    .BSK_AXI_4_awsize  (m_axi4_bsk_awsize[4]  ),
    //.BSK_AXI_4_awuser  (m_axi4_bsk_awuser[4]  ),
    .BSK_AXI_4_awvalid (m_axi4_bsk_awvalid[4] ),
    //.BSK_AXI_4_bid     (m_axi4_bsk_bid[4]     ),
    .BSK_AXI_4_bready  (m_axi4_bsk_bready[4]  ),
    .BSK_AXI_4_bresp   (m_axi4_bsk_bresp[4]   ),
    //.BSK_AXI_4_buser   (m_axi4_bsk_buser[4]   ),
    .BSK_AXI_4_bvalid  (m_axi4_bsk_bvalid[4]  ),
    .BSK_AXI_4_rdata   (m_axi4_bsk_rdata[4]   ),
    //.BSK_AXI_4_rid     (m_axi4_bsk_rid[4]     ),
    .BSK_AXI_4_rlast   (m_axi4_bsk_rlast[4]   ),
    .BSK_AXI_4_rready  (m_axi4_bsk_rready[4]  ),
    .BSK_AXI_4_rresp   (m_axi4_bsk_rresp[4]   ),
    .BSK_AXI_4_rvalid  (m_axi4_bsk_rvalid[4]  ),
    .BSK_AXI_4_wdata   (m_axi4_bsk_wdata[4]   ),
    .BSK_AXI_4_wlast   (m_axi4_bsk_wlast[4]   ),
    .BSK_AXI_4_wready  (m_axi4_bsk_wready[4]  ),
    .BSK_AXI_4_wstrb   (m_axi4_bsk_wstrb[4]   ),
    .BSK_AXI_4_wvalid  (m_axi4_bsk_wvalid[4]  ),
    .BSK_AXI_5_araddr  (m_axi4_bsk_araddr[5]  ),
    .BSK_AXI_5_arburst (m_axi4_bsk_arburst[5] ),
    .BSK_AXI_5_arcache (m_axi4_bsk_arcache[5] ),
    //.BSK_AXI_5_arid    (m_axi4_bsk_arid[5]    ),
    .BSK_AXI_5_arlen   (m_axi4_bsk_arlen[5]   ),
    .BSK_AXI_5_arlock  (m_axi4_bsk_arlock[5]  ),
    .BSK_AXI_5_arprot  (m_axi4_bsk_arprot[5]  ),
    .BSK_AXI_5_arready (m_axi4_bsk_arready[5] ),
    .BSK_AXI_5_arsize  (m_axi4_bsk_arsize[5]  ),
    //.BSK_AXI_5_aruser  (m_axi4_bsk_aruser[5]  ),
    .BSK_AXI_5_arvalid (m_axi4_bsk_arvalid[5] ),
    .BSK_AXI_5_awaddr  (m_axi4_bsk_awaddr[5]  ),
    .BSK_AXI_5_awburst (m_axi4_bsk_awburst[5] ),
    .BSK_AXI_5_awcache (m_axi4_bsk_awcache[5] ),
    //.BSK_AXI_5_awid    (m_axi4_bsk_awid[5]    ),
    .BSK_AXI_5_awlen   (m_axi4_bsk_awlen[5]   ),
    .BSK_AXI_5_awlock  (m_axi4_bsk_awlock[5]  ),
    .BSK_AXI_5_awprot  (m_axi4_bsk_awprot[5]  ),
    .BSK_AXI_5_awready (m_axi4_bsk_awready[5] ),
    .BSK_AXI_5_awsize  (m_axi4_bsk_awsize[5]  ),
    //.BSK_AXI_5_awuser  (m_axi4_bsk_awuser[5]  ),
    .BSK_AXI_5_awvalid (m_axi4_bsk_awvalid[5] ),
    //.BSK_AXI_5_bid     (m_axi4_bsk_bid[5]     ),
    .BSK_AXI_5_bready  (m_axi4_bsk_bready[5]  ),
    .BSK_AXI_5_bresp   (m_axi4_bsk_bresp[5]   ),
    //.BSK_AXI_5_buser   (m_axi4_bsk_buser[5]   ),
    .BSK_AXI_5_bvalid  (m_axi4_bsk_bvalid[5]  ),
    .BSK_AXI_5_rdata   (m_axi4_bsk_rdata[5]   ),
    //.BSK_AXI_5_rid     (m_axi4_bsk_rid[5]     ),
    .BSK_AXI_5_rlast   (m_axi4_bsk_rlast[5]   ),
    .BSK_AXI_5_rready  (m_axi4_bsk_rready[5]  ),
    .BSK_AXI_5_rresp   (m_axi4_bsk_rresp[5]   ),
    .BSK_AXI_5_rvalid  (m_axi4_bsk_rvalid[5]  ),
    .BSK_AXI_5_wdata   (m_axi4_bsk_wdata[5]   ),
    .BSK_AXI_5_wlast   (m_axi4_bsk_wlast[5]   ),
    .BSK_AXI_5_wready  (m_axi4_bsk_wready[5]  ),
    .BSK_AXI_5_wstrb   (m_axi4_bsk_wstrb[5]   ),
    .BSK_AXI_5_wvalid  (m_axi4_bsk_wvalid[5]  ),
    .BSK_AXI_6_araddr  (m_axi4_bsk_araddr[6]  ),
    .BSK_AXI_6_arburst (m_axi4_bsk_arburst[6] ),
    .BSK_AXI_6_arcache (m_axi4_bsk_arcache[6] ),
    //.BSK_AXI_6_arid    (m_axi4_bsk_arid[6]    ),
    .BSK_AXI_6_arlen   (m_axi4_bsk_arlen[6]   ),
    .BSK_AXI_6_arlock  (m_axi4_bsk_arlock[6]  ),
    .BSK_AXI_6_arprot  (m_axi4_bsk_arprot[6]  ),
    .BSK_AXI_6_arready (m_axi4_bsk_arready[6] ),
    .BSK_AXI_6_arsize  (m_axi4_bsk_arsize[6]  ),
    //.BSK_AXI_6_aruser  (m_axi4_bsk_aruser[6]  ),
    .BSK_AXI_6_arvalid (m_axi4_bsk_arvalid[6] ),
    .BSK_AXI_6_awaddr  (m_axi4_bsk_awaddr[6]  ),
    .BSK_AXI_6_awburst (m_axi4_bsk_awburst[6] ),
    .BSK_AXI_6_awcache (m_axi4_bsk_awcache[6] ),
    //.BSK_AXI_6_awid    (m_axi4_bsk_awid[6]    ),
    .BSK_AXI_6_awlen   (m_axi4_bsk_awlen[6]   ),
    .BSK_AXI_6_awlock  (m_axi4_bsk_awlock[6]  ),
    .BSK_AXI_6_awprot  (m_axi4_bsk_awprot[6]  ),
    .BSK_AXI_6_awready (m_axi4_bsk_awready[6] ),
    .BSK_AXI_6_awsize  (m_axi4_bsk_awsize[6]  ),
    //.BSK_AXI_6_awuser  (m_axi4_bsk_awuser[6]  ),
    .BSK_AXI_6_awvalid (m_axi4_bsk_awvalid[6] ),
    //.BSK_AXI_6_bid     (m_axi4_bsk_bid[6]     ),
    .BSK_AXI_6_bready  (m_axi4_bsk_bready[6]  ),
    .BSK_AXI_6_bresp   (m_axi4_bsk_bresp[6]   ),
    //.BSK_AXI_6_buser   (m_axi4_bsk_buser[6]   ),
    .BSK_AXI_6_bvalid  (m_axi4_bsk_bvalid[6]  ),
    .BSK_AXI_6_rdata   (m_axi4_bsk_rdata[6]   ),
    //.BSK_AXI_6_rid     (m_axi4_bsk_rid[6]     ),
    .BSK_AXI_6_rlast   (m_axi4_bsk_rlast[6]   ),
    .BSK_AXI_6_rready  (m_axi4_bsk_rready[6]  ),
    .BSK_AXI_6_rresp   (m_axi4_bsk_rresp[6]   ),
    .BSK_AXI_6_rvalid  (m_axi4_bsk_rvalid[6]  ),
    .BSK_AXI_6_wdata   (m_axi4_bsk_wdata[6]   ),
    .BSK_AXI_6_wlast   (m_axi4_bsk_wlast[6]   ),
    .BSK_AXI_6_wready  (m_axi4_bsk_wready[6]  ),
    .BSK_AXI_6_wstrb   (m_axi4_bsk_wstrb[6]   ),
    .BSK_AXI_6_wvalid  (m_axi4_bsk_wvalid[6]  ),
    .BSK_AXI_7_araddr  (m_axi4_bsk_araddr[7]  ),
    .BSK_AXI_7_arburst (m_axi4_bsk_arburst[7] ),
    .BSK_AXI_7_arcache (m_axi4_bsk_arcache[7] ),
    //.BSK_AXI_7_arid    (m_axi4_bsk_arid[7]    ),
    .BSK_AXI_7_arlen   (m_axi4_bsk_arlen[7]   ),
    .BSK_AXI_7_arlock  (m_axi4_bsk_arlock[7]  ),
    .BSK_AXI_7_arprot  (m_axi4_bsk_arprot[7]  ),
    .BSK_AXI_7_arready (m_axi4_bsk_arready[7] ),
    .BSK_AXI_7_arsize  (m_axi4_bsk_arsize[7]  ),
    //.BSK_AXI_7_aruser  (m_axi4_bsk_aruser[7]  ),
    .BSK_AXI_7_arvalid (m_axi4_bsk_arvalid[7] ),
    .BSK_AXI_7_awaddr  (m_axi4_bsk_awaddr[7]  ),
    .BSK_AXI_7_awburst (m_axi4_bsk_awburst[7] ),
    .BSK_AXI_7_awcache (m_axi4_bsk_awcache[7] ),
    //.BSK_AXI_7_awid    (m_axi4_bsk_awid[7]    ),
    .BSK_AXI_7_awlen   (m_axi4_bsk_awlen[7]   ),
    .BSK_AXI_7_awlock  (m_axi4_bsk_awlock[7]  ),
    .BSK_AXI_7_awprot  (m_axi4_bsk_awprot[7]  ),
    .BSK_AXI_7_awready (m_axi4_bsk_awready[7] ),
    .BSK_AXI_7_awsize  (m_axi4_bsk_awsize[7]  ),
    //.BSK_AXI_7_awuser  (m_axi4_bsk_awuser[7]  ),
    .BSK_AXI_7_awvalid (m_axi4_bsk_awvalid[7] ),
    //.BSK_AXI_7_bid     (m_axi4_bsk_bid[7]     ),
    .BSK_AXI_7_bready  (m_axi4_bsk_bready[7]  ),
    .BSK_AXI_7_bresp   (m_axi4_bsk_bresp[7]   ),
    //.BSK_AXI_7_buser   (m_axi4_bsk_buser[7]   ),
    .BSK_AXI_7_bvalid  (m_axi4_bsk_bvalid[7]  ),
    .BSK_AXI_7_rdata   (m_axi4_bsk_rdata[7]   ),
    //.BSK_AXI_7_rid     (m_axi4_bsk_rid[7]     ),
    .BSK_AXI_7_rlast   (m_axi4_bsk_rlast[7]   ),
    .BSK_AXI_7_rready  (m_axi4_bsk_rready[7]  ),
    .BSK_AXI_7_rresp   (m_axi4_bsk_rresp[7]   ),
    .BSK_AXI_7_rvalid  (m_axi4_bsk_rvalid[7]  ),
    .BSK_AXI_7_wdata   (m_axi4_bsk_wdata[7]   ),
    .BSK_AXI_7_wlast   (m_axi4_bsk_wlast[7]   ),
    .BSK_AXI_7_wready  (m_axi4_bsk_wready[7]  ),
    .BSK_AXI_7_wstrb   (m_axi4_bsk_wstrb[7]   ),
    .BSK_AXI_7_wvalid  (m_axi4_bsk_wvalid[7]  ),

    .BSK_AXI_8_araddr  (m_axi4_bsk_araddr[8]  ),
    .BSK_AXI_8_arburst (m_axi4_bsk_arburst[8] ),
    .BSK_AXI_8_arcache (m_axi4_bsk_arcache[8] ),
    //.BSK_AXI_8_arid    (m_axi4_bsk_arid[8]    ),
    .BSK_AXI_8_arlen   (m_axi4_bsk_arlen[8]   ),
    .BSK_AXI_8_arlock  (m_axi4_bsk_arlock[8]  ),
    .BSK_AXI_8_arprot  (m_axi4_bsk_arprot[8]  ),
    .BSK_AXI_8_arready (m_axi4_bsk_arready[8] ),
    .BSK_AXI_8_arsize  (m_axi4_bsk_arsize[8]  ),
    //.BSK_AXI_8_aruser  (m_axi4_bsk_aruser[8]  ),
    .BSK_AXI_8_arvalid (m_axi4_bsk_arvalid[8] ),
    .BSK_AXI_8_awaddr  (m_axi4_bsk_awaddr[8]  ),
    .BSK_AXI_8_awburst (m_axi4_bsk_awburst[8] ),
    .BSK_AXI_8_awcache (m_axi4_bsk_awcache[8] ),
    //.BSK_AXI_8_awid    (m_axi4_bsk_awid[8]    ),
    .BSK_AXI_8_awlen   (m_axi4_bsk_awlen[8]   ),
    .BSK_AXI_8_awlock  (m_axi4_bsk_awlock[8]  ),
    .BSK_AXI_8_awprot  (m_axi4_bsk_awprot[8]  ),
    .BSK_AXI_8_awready (m_axi4_bsk_awready[8] ),
    .BSK_AXI_8_awsize  (m_axi4_bsk_awsize[8]  ),
    //.BSK_AXI_8_awuser  (m_axi4_bsk_awuser[8]  ),
    .BSK_AXI_8_awvalid (m_axi4_bsk_awvalid[8] ),
    //.BSK_AXI_8_bid     (m_axi4_bsk_bid[8]     ),
    .BSK_AXI_8_bready  (m_axi4_bsk_bready[8]  ),
    .BSK_AXI_8_bresp   (m_axi4_bsk_bresp[8]   ),
    //.BSK_AXI_8_buser   (m_axi4_bsk_buser[8]   ),
    .BSK_AXI_8_bvalid  (m_axi4_bsk_bvalid[8]  ),
    .BSK_AXI_8_rdata   (m_axi4_bsk_rdata[8]   ),
    //.BSK_AXI_8_rid     (m_axi4_bsk_rid[8]     ),
    .BSK_AXI_8_rlast   (m_axi4_bsk_rlast[8]   ),
    .BSK_AXI_8_rready  (m_axi4_bsk_rready[8]  ),
    .BSK_AXI_8_rresp   (m_axi4_bsk_rresp[8]   ),
    .BSK_AXI_8_rvalid  (m_axi4_bsk_rvalid[8]  ),
    .BSK_AXI_8_wdata   (m_axi4_bsk_wdata[8]   ),
    .BSK_AXI_8_wlast   (m_axi4_bsk_wlast[8]   ),
    .BSK_AXI_8_wready  (m_axi4_bsk_wready[8]  ),
    .BSK_AXI_8_wstrb   (m_axi4_bsk_wstrb[8]   ),
    .BSK_AXI_8_wvalid  (m_axi4_bsk_wvalid[8]  ),

    .BSK_AXI_9_araddr  (m_axi4_bsk_araddr[9]  ),
    .BSK_AXI_9_arburst (m_axi4_bsk_arburst[9] ),
    .BSK_AXI_9_arcache (m_axi4_bsk_arcache[9] ),
    //.BSK_AXI_9_arid    (m_axi4_bsk_arid[9]    ),
    .BSK_AXI_9_arlen   (m_axi4_bsk_arlen[9]   ),
    .BSK_AXI_9_arlock  (m_axi4_bsk_arlock[9]  ),
    .BSK_AXI_9_arprot  (m_axi4_bsk_arprot[9]  ),
    .BSK_AXI_9_arready (m_axi4_bsk_arready[9] ),
    .BSK_AXI_9_arsize  (m_axi4_bsk_arsize[9]  ),
    //.BSK_AXI_9_aruser  (m_axi4_bsk_aruser[9]  ),
    .BSK_AXI_9_arvalid (m_axi4_bsk_arvalid[9] ),
    .BSK_AXI_9_awaddr  (m_axi4_bsk_awaddr[9]  ),
    .BSK_AXI_9_awburst (m_axi4_bsk_awburst[9] ),
    .BSK_AXI_9_awcache (m_axi4_bsk_awcache[9] ),
    //.BSK_AXI_9_awid    (m_axi4_bsk_awid[9]    ),
    .BSK_AXI_9_awlen   (m_axi4_bsk_awlen[9]   ),
    .BSK_AXI_9_awlock  (m_axi4_bsk_awlock[9]  ),
    .BSK_AXI_9_awprot  (m_axi4_bsk_awprot[9]  ),
    .BSK_AXI_9_awready (m_axi4_bsk_awready[9] ),
    .BSK_AXI_9_awsize  (m_axi4_bsk_awsize[9]  ),
    //.BSK_AXI_9_awuser  (m_axi4_bsk_awuser[9]  ),
    .BSK_AXI_9_awvalid (m_axi4_bsk_awvalid[9] ),
    //.BSK_AXI_9_bid     (m_axi4_bsk_bid[9]     ),
    .BSK_AXI_9_bready  (m_axi4_bsk_bready[9]  ),
    .BSK_AXI_9_bresp   (m_axi4_bsk_bresp[9]   ),
    //.BSK_AXI_9_buser   (m_axi4_bsk_buser[9]   ),
    .BSK_AXI_9_bvalid  (m_axi4_bsk_bvalid[9]  ),
    .BSK_AXI_9_rdata   (m_axi4_bsk_rdata[9]   ),
    //.BSK_AXI_9_rid     (m_axi4_bsk_rid[9]     ),
    .BSK_AXI_9_rlast   (m_axi4_bsk_rlast[9]   ),
    .BSK_AXI_9_rready  (m_axi4_bsk_rready[9]  ),
    .BSK_AXI_9_rresp   (m_axi4_bsk_rresp[9]   ),
    .BSK_AXI_9_rvalid  (m_axi4_bsk_rvalid[9]  ),
    .BSK_AXI_9_wdata   (m_axi4_bsk_wdata[9]   ),
    .BSK_AXI_9_wlast   (m_axi4_bsk_wlast[9]   ),
    .BSK_AXI_9_wready  (m_axi4_bsk_wready[9]  ),
    .BSK_AXI_9_wstrb   (m_axi4_bsk_wstrb[9]   ),
    .BSK_AXI_9_wvalid  (m_axi4_bsk_wvalid[9]  ),

    .BSK_AXI_10_araddr  (m_axi4_bsk_araddr[10]  ),
    .BSK_AXI_10_arburst (m_axi4_bsk_arburst[10] ),
    .BSK_AXI_10_arcache (m_axi4_bsk_arcache[10] ),
    //.BSK_AXI_10_arid    (m_axi4_bsk_arid[10]    ),
    .BSK_AXI_10_arlen   (m_axi4_bsk_arlen[10]   ),
    .BSK_AXI_10_arlock  (m_axi4_bsk_arlock[10]  ),
    .BSK_AXI_10_arprot  (m_axi4_bsk_arprot[10]  ),
    .BSK_AXI_10_arready (m_axi4_bsk_arready[10] ),
    .BSK_AXI_10_arsize  (m_axi4_bsk_arsize[10]  ),
    //.BSK_AXI_10_aruser  (m_axi4_bsk_aruser[10]  ),
    .BSK_AXI_10_arvalid (m_axi4_bsk_arvalid[10] ),
    .BSK_AXI_10_awaddr  (m_axi4_bsk_awaddr[10]  ),
    .BSK_AXI_10_awburst (m_axi4_bsk_awburst[10] ),
    .BSK_AXI_10_awcache (m_axi4_bsk_awcache[10] ),
    //.BSK_AXI_10_awid    (m_axi4_bsk_awid[10]    ),
    .BSK_AXI_10_awlen   (m_axi4_bsk_awlen[10]   ),
    .BSK_AXI_10_awlock  (m_axi4_bsk_awlock[10]  ),
    .BSK_AXI_10_awprot  (m_axi4_bsk_awprot[10]  ),
    .BSK_AXI_10_awready (m_axi4_bsk_awready[10] ),
    .BSK_AXI_10_awsize  (m_axi4_bsk_awsize[10]  ),
    //.BSK_AXI_10_awuser  (m_axi4_bsk_awuser[10]  ),
    .BSK_AXI_10_awvalid (m_axi4_bsk_awvalid[10] ),
    //.BSK_AXI_10_bid     (m_axi4_bsk_bid[10]     ),
    .BSK_AXI_10_bready  (m_axi4_bsk_bready[10]  ),
    .BSK_AXI_10_bresp   (m_axi4_bsk_bresp[10]   ),
    //.BSK_AXI_10_buser   (m_axi4_bsk_buser[10]   ),
    .BSK_AXI_10_bvalid  (m_axi4_bsk_bvalid[10]  ),
    .BSK_AXI_10_rdata   (m_axi4_bsk_rdata[10]   ),
    //.BSK_AXI_10_rid     (m_axi4_bsk_rid[10]     ),
    .BSK_AXI_10_rlast   (m_axi4_bsk_rlast[10]   ),
    .BSK_AXI_10_rready  (m_axi4_bsk_rready[10]  ),
    .BSK_AXI_10_rresp   (m_axi4_bsk_rresp[10]   ),
    .BSK_AXI_10_rvalid  (m_axi4_bsk_rvalid[10]  ),
    .BSK_AXI_10_wdata   (m_axi4_bsk_wdata[10]   ),
    .BSK_AXI_10_wlast   (m_axi4_bsk_wlast[10]   ),
    .BSK_AXI_10_wready  (m_axi4_bsk_wready[10]  ),
    .BSK_AXI_10_wstrb   (m_axi4_bsk_wstrb[10]   ),
    .BSK_AXI_10_wvalid  (m_axi4_bsk_wvalid[10]  ),

    .BSK_AXI_11_araddr  (m_axi4_bsk_araddr[11]  ),
    .BSK_AXI_11_arburst (m_axi4_bsk_arburst[11] ),
    .BSK_AXI_11_arcache (m_axi4_bsk_arcache[11] ),
    //.BSK_AXI_11_arid    (m_axi4_bsk_arid[11]    ),
    .BSK_AXI_11_arlen   (m_axi4_bsk_arlen[11]   ),
    .BSK_AXI_11_arlock  (m_axi4_bsk_arlock[11]  ),
    .BSK_AXI_11_arprot  (m_axi4_bsk_arprot[11]  ),
    .BSK_AXI_11_arready (m_axi4_bsk_arready[11] ),
    .BSK_AXI_11_arsize  (m_axi4_bsk_arsize[11]  ),
    //.BSK_AXI_11_aruser  (m_axi4_bsk_aruser[11]  ),
    .BSK_AXI_11_arvalid (m_axi4_bsk_arvalid[11] ),
    .BSK_AXI_11_awaddr  (m_axi4_bsk_awaddr[11]  ),
    .BSK_AXI_11_awburst (m_axi4_bsk_awburst[11] ),
    .BSK_AXI_11_awcache (m_axi4_bsk_awcache[11] ),
    //.BSK_AXI_11_awid    (m_axi4_bsk_awid[11]    ),
    .BSK_AXI_11_awlen   (m_axi4_bsk_awlen[11]   ),
    .BSK_AXI_11_awlock  (m_axi4_bsk_awlock[11]  ),
    .BSK_AXI_11_awprot  (m_axi4_bsk_awprot[11]  ),
    .BSK_AXI_11_awready (m_axi4_bsk_awready[11] ),
    .BSK_AXI_11_awsize  (m_axi4_bsk_awsize[11]  ),
    //.BSK_AXI_11_awuser  (m_axi4_bsk_awuser[11]  ),
    .BSK_AXI_11_awvalid (m_axi4_bsk_awvalid[11] ),
    //.BSK_AXI_11_bid     (m_axi4_bsk_bid[11]     ),
    .BSK_AXI_11_bready  (m_axi4_bsk_bready[11]  ),
    .BSK_AXI_11_bresp   (m_axi4_bsk_bresp[11]   ),
    //.BSK_AXI_11_buser   (m_axi4_bsk_buser[11]   ),
    .BSK_AXI_11_bvalid  (m_axi4_bsk_bvalid[11]  ),
    .BSK_AXI_11_rdata   (m_axi4_bsk_rdata[11]   ),
    //.BSK_AXI_11_rid     (m_axi4_bsk_rid[11]     ),
    .BSK_AXI_11_rlast   (m_axi4_bsk_rlast[11]   ),
    .BSK_AXI_11_rready  (m_axi4_bsk_rready[11]  ),
    .BSK_AXI_11_rresp   (m_axi4_bsk_rresp[11]   ),
    .BSK_AXI_11_rvalid  (m_axi4_bsk_rvalid[11]  ),
    .BSK_AXI_11_wdata   (m_axi4_bsk_wdata[11]   ),
    .BSK_AXI_11_wlast   (m_axi4_bsk_wlast[11]   ),
    .BSK_AXI_11_wready  (m_axi4_bsk_wready[11]  ),
    .BSK_AXI_11_wstrb   (m_axi4_bsk_wstrb[11]   ),
    .BSK_AXI_11_wvalid  (m_axi4_bsk_wvalid[11]  ),

    .BSK_AXI_12_araddr  (m_axi4_bsk_araddr[12]  ),
    .BSK_AXI_12_arburst (m_axi4_bsk_arburst[12] ),
    .BSK_AXI_12_arcache (m_axi4_bsk_arcache[12] ),
    //.BSK_AXI_12_arid    (m_axi4_bsk_arid[12]    ),
    .BSK_AXI_12_arlen   (m_axi4_bsk_arlen[12]   ),
    .BSK_AXI_12_arlock  (m_axi4_bsk_arlock[12]  ),
    .BSK_AXI_12_arprot  (m_axi4_bsk_arprot[12]  ),
    .BSK_AXI_12_arready (m_axi4_bsk_arready[12] ),
    .BSK_AXI_12_arsize  (m_axi4_bsk_arsize[12]  ),
    //.BSK_AXI_12_aruser  (m_axi4_bsk_aruser[12]  ),
    .BSK_AXI_12_arvalid (m_axi4_bsk_arvalid[12] ),
    .BSK_AXI_12_awaddr  (m_axi4_bsk_awaddr[12]  ),
    .BSK_AXI_12_awburst (m_axi4_bsk_awburst[12] ),
    .BSK_AXI_12_awcache (m_axi4_bsk_awcache[12] ),
    //.BSK_AXI_12_awid    (m_axi4_bsk_awid[12]    ),
    .BSK_AXI_12_awlen   (m_axi4_bsk_awlen[12]   ),
    .BSK_AXI_12_awlock  (m_axi4_bsk_awlock[12]  ),
    .BSK_AXI_12_awprot  (m_axi4_bsk_awprot[12]  ),
    .BSK_AXI_12_awready (m_axi4_bsk_awready[12] ),
    .BSK_AXI_12_awsize  (m_axi4_bsk_awsize[12]  ),
    //.BSK_AXI_12_awuser  (m_axi4_bsk_awuser[12]  ),
    .BSK_AXI_12_awvalid (m_axi4_bsk_awvalid[12] ),
    //.BSK_AXI_12_bid     (m_axi4_bsk_bid[12]     ),
    .BSK_AXI_12_bready  (m_axi4_bsk_bready[12]  ),
    .BSK_AXI_12_bresp   (m_axi4_bsk_bresp[12]   ),
    //.BSK_AXI_12_buser   (m_axi4_bsk_buser[12]   ),
    .BSK_AXI_12_bvalid  (m_axi4_bsk_bvalid[12]  ),
    .BSK_AXI_12_rdata   (m_axi4_bsk_rdata[12]   ),
    //.BSK_AXI_12_rid     (m_axi4_bsk_rid[12]     ),
    .BSK_AXI_12_rlast   (m_axi4_bsk_rlast[12]   ),
    .BSK_AXI_12_rready  (m_axi4_bsk_rready[12]  ),
    .BSK_AXI_12_rresp   (m_axi4_bsk_rresp[12]   ),
    .BSK_AXI_12_rvalid  (m_axi4_bsk_rvalid[12]  ),
    .BSK_AXI_12_wdata   (m_axi4_bsk_wdata[12]   ),
    .BSK_AXI_12_wlast   (m_axi4_bsk_wlast[12]   ),
    .BSK_AXI_12_wready  (m_axi4_bsk_wready[12]  ),
    .BSK_AXI_12_wstrb   (m_axi4_bsk_wstrb[12]   ),
    .BSK_AXI_12_wvalid  (m_axi4_bsk_wvalid[12]  ),

    .BSK_AXI_13_araddr  (m_axi4_bsk_araddr[13]  ),
    .BSK_AXI_13_arburst (m_axi4_bsk_arburst[13] ),
    .BSK_AXI_13_arcache (m_axi4_bsk_arcache[13] ),
    //.BSK_AXI_13_arid    (m_axi4_bsk_arid[13]    ),
    .BSK_AXI_13_arlen   (m_axi4_bsk_arlen[13]   ),
    .BSK_AXI_13_arlock  (m_axi4_bsk_arlock[13]  ),
    .BSK_AXI_13_arprot  (m_axi4_bsk_arprot[13]  ),
    .BSK_AXI_13_arready (m_axi4_bsk_arready[13] ),
    .BSK_AXI_13_arsize  (m_axi4_bsk_arsize[13]  ),
    //.BSK_AXI_13_aruser  (m_axi4_bsk_aruser[13]  ),
    .BSK_AXI_13_arvalid (m_axi4_bsk_arvalid[13] ),
    .BSK_AXI_13_awaddr  (m_axi4_bsk_awaddr[13]  ),
    .BSK_AXI_13_awburst (m_axi4_bsk_awburst[13] ),
    .BSK_AXI_13_awcache (m_axi4_bsk_awcache[13] ),
    //.BSK_AXI_13_awid    (m_axi4_bsk_awid[13]    ),
    .BSK_AXI_13_awlen   (m_axi4_bsk_awlen[13]   ),
    .BSK_AXI_13_awlock  (m_axi4_bsk_awlock[13]  ),
    .BSK_AXI_13_awprot  (m_axi4_bsk_awprot[13]  ),
    .BSK_AXI_13_awready (m_axi4_bsk_awready[13] ),
    .BSK_AXI_13_awsize  (m_axi4_bsk_awsize[13]  ),
    //.BSK_AXI_13_awuser  (m_axi4_bsk_awuser[13]  ),
    .BSK_AXI_13_awvalid (m_axi4_bsk_awvalid[13] ),
    //.BSK_AXI_13_bid     (m_axi4_bsk_bid[13]     ),
    .BSK_AXI_13_bready  (m_axi4_bsk_bready[13]  ),
    .BSK_AXI_13_bresp   (m_axi4_bsk_bresp[13]   ),
    //.BSK_AXI_13_buser   (m_axi4_bsk_buser[13]   ),
    .BSK_AXI_13_bvalid  (m_axi4_bsk_bvalid[13]  ),
    .BSK_AXI_13_rdata   (m_axi4_bsk_rdata[13]   ),
    //.BSK_AXI_13_rid     (m_axi4_bsk_rid[13]     ),
    .BSK_AXI_13_rlast   (m_axi4_bsk_rlast[13]   ),
    .BSK_AXI_13_rready  (m_axi4_bsk_rready[13]  ),
    .BSK_AXI_13_rresp   (m_axi4_bsk_rresp[13]   ),
    .BSK_AXI_13_rvalid  (m_axi4_bsk_rvalid[13]  ),
    .BSK_AXI_13_wdata   (m_axi4_bsk_wdata[13]   ),
    .BSK_AXI_13_wlast   (m_axi4_bsk_wlast[13]   ),
    .BSK_AXI_13_wready  (m_axi4_bsk_wready[13]  ),
    .BSK_AXI_13_wstrb   (m_axi4_bsk_wstrb[13]   ),
    .BSK_AXI_13_wvalid  (m_axi4_bsk_wvalid[13]  ),

    .BSK_AXI_14_araddr  (m_axi4_bsk_araddr[14]  ),
    .BSK_AXI_14_arburst (m_axi4_bsk_arburst[14] ),
    .BSK_AXI_14_arcache (m_axi4_bsk_arcache[14] ),
    //.BSK_AXI_14_arid    (m_axi4_bsk_arid[14]    ),
    .BSK_AXI_14_arlen   (m_axi4_bsk_arlen[14]   ),
    .BSK_AXI_14_arlock  (m_axi4_bsk_arlock[14]  ),
    .BSK_AXI_14_arprot  (m_axi4_bsk_arprot[14]  ),
    .BSK_AXI_14_arready (m_axi4_bsk_arready[14] ),
    .BSK_AXI_14_arsize  (m_axi4_bsk_arsize[14]  ),
    //.BSK_AXI_14_aruser  (m_axi4_bsk_aruser[14]  ),
    .BSK_AXI_14_arvalid (m_axi4_bsk_arvalid[14] ),
    .BSK_AXI_14_awaddr  (m_axi4_bsk_awaddr[14]  ),
    .BSK_AXI_14_awburst (m_axi4_bsk_awburst[14] ),
    .BSK_AXI_14_awcache (m_axi4_bsk_awcache[14] ),
    //.BSK_AXI_14_awid    (m_axi4_bsk_awid[14]    ),
    .BSK_AXI_14_awlen   (m_axi4_bsk_awlen[14]   ),
    .BSK_AXI_14_awlock  (m_axi4_bsk_awlock[14]  ),
    .BSK_AXI_14_awprot  (m_axi4_bsk_awprot[14]  ),
    .BSK_AXI_14_awready (m_axi4_bsk_awready[14] ),
    .BSK_AXI_14_awsize  (m_axi4_bsk_awsize[14]  ),
    //.BSK_AXI_14_awuser  (m_axi4_bsk_awuser[14]  ),
    .BSK_AXI_14_awvalid (m_axi4_bsk_awvalid[14] ),
    //.BSK_AXI_14_bid     (m_axi4_bsk_bid[14]     ),
    .BSK_AXI_14_bready  (m_axi4_bsk_bready[14]  ),
    .BSK_AXI_14_bresp   (m_axi4_bsk_bresp[14]   ),
    //.BSK_AXI_14_buser   (m_axi4_bsk_buser[14]   ),
    .BSK_AXI_14_bvalid  (m_axi4_bsk_bvalid[14]  ),
    .BSK_AXI_14_rdata   (m_axi4_bsk_rdata[14]   ),
    //.BSK_AXI_14_rid     (m_axi4_bsk_rid[14]     ),
    .BSK_AXI_14_rlast   (m_axi4_bsk_rlast[14]   ),
    .BSK_AXI_14_rready  (m_axi4_bsk_rready[14]  ),
    .BSK_AXI_14_rresp   (m_axi4_bsk_rresp[14]   ),
    .BSK_AXI_14_rvalid  (m_axi4_bsk_rvalid[14]  ),
    .BSK_AXI_14_wdata   (m_axi4_bsk_wdata[14]   ),
    .BSK_AXI_14_wlast   (m_axi4_bsk_wlast[14]   ),
    .BSK_AXI_14_wready  (m_axi4_bsk_wready[14]  ),
    .BSK_AXI_14_wstrb   (m_axi4_bsk_wstrb[14]   ),
    .BSK_AXI_14_wvalid  (m_axi4_bsk_wvalid[14]  ),

    .BSK_AXI_15_araddr  (m_axi4_bsk_araddr[15]  ),
    .BSK_AXI_15_arburst (m_axi4_bsk_arburst[15] ),
    .BSK_AXI_15_arcache (m_axi4_bsk_arcache[15] ),
    //.BSK_AXI_15_arid    (m_axi4_bsk_arid[15]    ),
    .BSK_AXI_15_arlen   (m_axi4_bsk_arlen[15]   ),
    .BSK_AXI_15_arlock  (m_axi4_bsk_arlock[15]  ),
    .BSK_AXI_15_arprot  (m_axi4_bsk_arprot[15]  ),
    .BSK_AXI_15_arready (m_axi4_bsk_arready[15] ),
    .BSK_AXI_15_arsize  (m_axi4_bsk_arsize[15]  ),
    //.BSK_AXI_15_aruser  (m_axi4_bsk_aruser[15]  ),
    .BSK_AXI_15_arvalid (m_axi4_bsk_arvalid[15] ),
    .BSK_AXI_15_awaddr  (m_axi4_bsk_awaddr[15]  ),
    .BSK_AXI_15_awburst (m_axi4_bsk_awburst[15] ),
    .BSK_AXI_15_awcache (m_axi4_bsk_awcache[15] ),
    //.BSK_AXI_15_awid    (m_axi4_bsk_awid[15]    ),
    .BSK_AXI_15_awlen   (m_axi4_bsk_awlen[15]   ),
    .BSK_AXI_15_awlock  (m_axi4_bsk_awlock[15]  ),
    .BSK_AXI_15_awprot  (m_axi4_bsk_awprot[15]  ),
    .BSK_AXI_15_awready (m_axi4_bsk_awready[15] ),
    .BSK_AXI_15_awsize  (m_axi4_bsk_awsize[15]  ),
    //.BSK_AXI_15_awuser  (m_axi4_bsk_awuser[15]  ),
    .BSK_AXI_15_awvalid (m_axi4_bsk_awvalid[15] ),
    //.BSK_AXI_15_bid     (m_axi4_bsk_bid[15]     ),
    .BSK_AXI_15_bready  (m_axi4_bsk_bready[15]  ),
    .BSK_AXI_15_bresp   (m_axi4_bsk_bresp[15]   ),
    //.BSK_AXI_15_buser   (m_axi4_bsk_buser[15]   ),
    .BSK_AXI_15_bvalid  (m_axi4_bsk_bvalid[15]  ),
    .BSK_AXI_15_rdata   (m_axi4_bsk_rdata[15]   ),
    //.BSK_AXI_15_rid     (m_axi4_bsk_rid[15]     ),
    .BSK_AXI_15_rlast   (m_axi4_bsk_rlast[15]   ),
    .BSK_AXI_15_rready  (m_axi4_bsk_rready[15]  ),
    .BSK_AXI_15_rresp   (m_axi4_bsk_rresp[15]   ),
    .BSK_AXI_15_rvalid  (m_axi4_bsk_rvalid[15]  ),
    .BSK_AXI_15_wdata   (m_axi4_bsk_wdata[15]   ),
    .BSK_AXI_15_wlast   (m_axi4_bsk_wlast[15]   ),
    .BSK_AXI_15_wready  (m_axi4_bsk_wready[15]  ),
    .BSK_AXI_15_wstrb   (m_axi4_bsk_wstrb[15]   ),
    .BSK_AXI_15_wvalid  (m_axi4_bsk_wvalid[15]  ),

    .KSK_AXI_0_araddr  (m_axi4_ksk_araddr[0]  ),
    .KSK_AXI_0_arburst (m_axi4_ksk_arburst[0] ),
    .KSK_AXI_0_arcache (m_axi4_ksk_arcache[0] ),
    .KSK_AXI_0_arid    (m_axi4_ksk_arid[0]    ),
    .KSK_AXI_0_arlen   (m_axi4_ksk_arlen[0]   ),
    .KSK_AXI_0_arlock  (m_axi4_ksk_arlock[0]  ),
    .KSK_AXI_0_arprot  (m_axi4_ksk_arprot[0]  ),
    .KSK_AXI_0_arready (m_axi4_ksk_arready[0] ),
    .KSK_AXI_0_arsize  (m_axi4_ksk_arsize[0]  ),
    //.KSK_AXI_0_aruser  (m_axi4_ksk_aruser[0]  ),
    .KSK_AXI_0_arvalid (m_axi4_ksk_arvalid[0] ),
    .KSK_AXI_0_awaddr  (m_axi4_ksk_awaddr[0]  ),
    .KSK_AXI_0_awburst (m_axi4_ksk_awburst[0] ),
    .KSK_AXI_0_awcache (m_axi4_ksk_awcache[0] ),
    .KSK_AXI_0_awid    (m_axi4_ksk_awid[0]    ),
    .KSK_AXI_0_awlen   (m_axi4_ksk_awlen[0]   ),
    .KSK_AXI_0_awlock  (m_axi4_ksk_awlock[0]  ),
    .KSK_AXI_0_awprot  (m_axi4_ksk_awprot[0]  ),
    .KSK_AXI_0_awready (m_axi4_ksk_awready[0] ),
    .KSK_AXI_0_awsize  (m_axi4_ksk_awsize[0]  ),
    //.KSK_AXI_0_awuser  (m_axi4_ksk_awuser[0]  ),
    .KSK_AXI_0_awvalid (m_axi4_ksk_awvalid[0] ),
    .KSK_AXI_0_bid     (m_axi4_ksk_bid[0]     ),
    .KSK_AXI_0_bready  (m_axi4_ksk_bready[0]  ),
    .KSK_AXI_0_bresp   (m_axi4_ksk_bresp[0]   ),
    //.KSK_AXI_0_buser   (m_axi4_ksk_buser[0]   ),
    .KSK_AXI_0_bvalid  (m_axi4_ksk_bvalid[0]  ),
    .KSK_AXI_0_rdata   (m_axi4_ksk_rdata[0]   ),
    .KSK_AXI_0_rid     (m_axi4_ksk_rid[0]     ),
    .KSK_AXI_0_rlast   (m_axi4_ksk_rlast[0]   ),
    .KSK_AXI_0_rready  (m_axi4_ksk_rready[0]  ),
    .KSK_AXI_0_rresp   (m_axi4_ksk_rresp[0]   ),
    .KSK_AXI_0_rvalid  (m_axi4_ksk_rvalid[0]  ),
    .KSK_AXI_0_wdata   (m_axi4_ksk_wdata[0]   ),
    .KSK_AXI_0_wlast   (m_axi4_ksk_wlast[0]   ),
    .KSK_AXI_0_wready  (m_axi4_ksk_wready[0]  ),
    .KSK_AXI_0_wstrb   (m_axi4_ksk_wstrb[0]   ),
    .KSK_AXI_0_wvalid  (m_axi4_ksk_wvalid[0]  ),
    .KSK_AXI_1_araddr  (m_axi4_ksk_araddr[1]  ),
    .KSK_AXI_1_arburst (m_axi4_ksk_arburst[1] ),
    .KSK_AXI_1_arcache (m_axi4_ksk_arcache[1] ),
    .KSK_AXI_1_arid    (m_axi4_ksk_arid[1]    ),
    .KSK_AXI_1_arlen   (m_axi4_ksk_arlen[1]   ),
    .KSK_AXI_1_arlock  (m_axi4_ksk_arlock[1]  ),
    .KSK_AXI_1_arprot  (m_axi4_ksk_arprot[1]  ),
    .KSK_AXI_1_arready (m_axi4_ksk_arready[1] ),
    .KSK_AXI_1_arsize  (m_axi4_ksk_arsize[1]  ),
    //.KSK_AXI_1_aruser  (m_axi4_ksk_aruser[1]  ),
    .KSK_AXI_1_arvalid (m_axi4_ksk_arvalid[1] ),
    .KSK_AXI_1_awaddr  (m_axi4_ksk_awaddr[1]  ),
    .KSK_AXI_1_awburst (m_axi4_ksk_awburst[1] ),
    .KSK_AXI_1_awcache (m_axi4_ksk_awcache[1] ),
    .KSK_AXI_1_awid    (m_axi4_ksk_awid[1]    ),
    .KSK_AXI_1_awlen   (m_axi4_ksk_awlen[1]   ),
    .KSK_AXI_1_awlock  (m_axi4_ksk_awlock[1]  ),
    .KSK_AXI_1_awprot  (m_axi4_ksk_awprot[1]  ),
    .KSK_AXI_1_awready (m_axi4_ksk_awready[1] ),
    .KSK_AXI_1_awsize  (m_axi4_ksk_awsize[1]  ),
    //.KSK_AXI_1_awuser  (m_axi4_ksk_awuser[1]  ),
    .KSK_AXI_1_awvalid (m_axi4_ksk_awvalid[1] ),
    .KSK_AXI_1_bid     (m_axi4_ksk_bid[1]     ),
    .KSK_AXI_1_bready  (m_axi4_ksk_bready[1]  ),
    .KSK_AXI_1_bresp   (m_axi4_ksk_bresp[1]   ),
    //.KSK_AXI_1_buser   (m_axi4_ksk_buser[1]   ),
    .KSK_AXI_1_bvalid  (m_axi4_ksk_bvalid[1]  ),
    .KSK_AXI_1_rdata   (m_axi4_ksk_rdata[1]   ),
    .KSK_AXI_1_rid     (m_axi4_ksk_rid[1]     ),
    .KSK_AXI_1_rlast   (m_axi4_ksk_rlast[1]   ),
    .KSK_AXI_1_rready  (m_axi4_ksk_rready[1]  ),
    .KSK_AXI_1_rresp   (m_axi4_ksk_rresp[1]   ),
    .KSK_AXI_1_rvalid  (m_axi4_ksk_rvalid[1]  ),
    .KSK_AXI_1_wdata   (m_axi4_ksk_wdata[1]   ),
    .KSK_AXI_1_wlast   (m_axi4_ksk_wlast[1]   ),
    .KSK_AXI_1_wready  (m_axi4_ksk_wready[1]  ),
    .KSK_AXI_1_wstrb   (m_axi4_ksk_wstrb[1]   ),
    .KSK_AXI_1_wvalid  (m_axi4_ksk_wvalid[1]  ),
    .KSK_AXI_2_araddr  (m_axi4_ksk_araddr[2]  ),
    .KSK_AXI_2_arburst (m_axi4_ksk_arburst[2] ),
    .KSK_AXI_2_arcache (m_axi4_ksk_arcache[2] ),
    .KSK_AXI_2_arid    (m_axi4_ksk_arid[2]    ),
    .KSK_AXI_2_arlen   (m_axi4_ksk_arlen[2]   ),
    .KSK_AXI_2_arlock  (m_axi4_ksk_arlock[2]  ),
    .KSK_AXI_2_arprot  (m_axi4_ksk_arprot[2]  ),
    .KSK_AXI_2_arready (m_axi4_ksk_arready[2] ),
    .KSK_AXI_2_arsize  (m_axi4_ksk_arsize[2]  ),
    //.KSK_AXI_2_aruser  (m_axi4_ksk_aruser[2]  ),
    .KSK_AXI_2_arvalid (m_axi4_ksk_arvalid[2] ),
    .KSK_AXI_2_awaddr  (m_axi4_ksk_awaddr[2]  ),
    .KSK_AXI_2_awburst (m_axi4_ksk_awburst[2] ),
    .KSK_AXI_2_awcache (m_axi4_ksk_awcache[2] ),
    .KSK_AXI_2_awid    (m_axi4_ksk_awid[2]    ),
    .KSK_AXI_2_awlen   (m_axi4_ksk_awlen[2]   ),
    .KSK_AXI_2_awlock  (m_axi4_ksk_awlock[2]  ),
    .KSK_AXI_2_awprot  (m_axi4_ksk_awprot[2]  ),
    .KSK_AXI_2_awready (m_axi4_ksk_awready[2] ),
    .KSK_AXI_2_awsize  (m_axi4_ksk_awsize[2]  ),
    //.KSK_AXI_2_awuser  (m_axi4_ksk_awuser[2]  ),
    .KSK_AXI_2_awvalid (m_axi4_ksk_awvalid[2] ),
    .KSK_AXI_2_bid     (m_axi4_ksk_bid[2]     ),
    .KSK_AXI_2_bready  (m_axi4_ksk_bready[2]  ),
    .KSK_AXI_2_bresp   (m_axi4_ksk_bresp[2]   ),
    //.KSK_AXI_2_buser   (m_axi4_ksk_buser[2]   ),
    .KSK_AXI_2_bvalid  (m_axi4_ksk_bvalid[2]  ),
    .KSK_AXI_2_rdata   (m_axi4_ksk_rdata[2]   ),
    .KSK_AXI_2_rid     (m_axi4_ksk_rid[2]     ),
    .KSK_AXI_2_rlast   (m_axi4_ksk_rlast[2]   ),
    .KSK_AXI_2_rready  (m_axi4_ksk_rready[2]  ),
    .KSK_AXI_2_rresp   (m_axi4_ksk_rresp[2]   ),
    .KSK_AXI_2_rvalid  (m_axi4_ksk_rvalid[2]  ),
    .KSK_AXI_2_wdata   (m_axi4_ksk_wdata[2]   ),
    .KSK_AXI_2_wlast   (m_axi4_ksk_wlast[2]   ),
    .KSK_AXI_2_wready  (m_axi4_ksk_wready[2]  ),
    .KSK_AXI_2_wstrb   (m_axi4_ksk_wstrb[2]   ),
    .KSK_AXI_2_wvalid  (m_axi4_ksk_wvalid[2]  ),
    .KSK_AXI_3_araddr  (m_axi4_ksk_araddr[3]  ),
    .KSK_AXI_3_arburst (m_axi4_ksk_arburst[3] ),
    .KSK_AXI_3_arcache (m_axi4_ksk_arcache[3] ),
    .KSK_AXI_3_arid    (m_axi4_ksk_arid[3]    ),
    .KSK_AXI_3_arlen   (m_axi4_ksk_arlen[3]   ),
    .KSK_AXI_3_arlock  (m_axi4_ksk_arlock[3]  ),
    .KSK_AXI_3_arprot  (m_axi4_ksk_arprot[3]  ),
    .KSK_AXI_3_arready (m_axi4_ksk_arready[3] ),
    .KSK_AXI_3_arsize  (m_axi4_ksk_arsize[3]  ),
    //.KSK_AXI_3_aruser  (m_axi4_ksk_aruser[3]  ),
    .KSK_AXI_3_arvalid (m_axi4_ksk_arvalid[3] ),
    .KSK_AXI_3_awaddr  (m_axi4_ksk_awaddr[3]  ),
    .KSK_AXI_3_awburst (m_axi4_ksk_awburst[3] ),
    .KSK_AXI_3_awcache (m_axi4_ksk_awcache[3] ),
    .KSK_AXI_3_awid    (m_axi4_ksk_awid[3]    ),
    .KSK_AXI_3_awlen   (m_axi4_ksk_awlen[3]   ),
    .KSK_AXI_3_awlock  (m_axi4_ksk_awlock[3]  ),
    .KSK_AXI_3_awprot  (m_axi4_ksk_awprot[3]  ),
    .KSK_AXI_3_awready (m_axi4_ksk_awready[3] ),
    .KSK_AXI_3_awsize  (m_axi4_ksk_awsize[3]  ),
    //.KSK_AXI_3_awuser  (m_axi4_ksk_awuser[3]  ),
    .KSK_AXI_3_awvalid (m_axi4_ksk_awvalid[3] ),
    .KSK_AXI_3_bid     (m_axi4_ksk_bid[3]     ),
    .KSK_AXI_3_bready  (m_axi4_ksk_bready[3]  ),
    .KSK_AXI_3_bresp   (m_axi4_ksk_bresp[3]   ),
    //.KSK_AXI_3_buser   (m_axi4_ksk_buser[3]   ),
    .KSK_AXI_3_bvalid  (m_axi4_ksk_bvalid[3]  ),
    .KSK_AXI_3_rdata   (m_axi4_ksk_rdata[3]   ),
    .KSK_AXI_3_rid     (m_axi4_ksk_rid[3]     ),
    .KSK_AXI_3_rlast   (m_axi4_ksk_rlast[3]   ),
    .KSK_AXI_3_rready  (m_axi4_ksk_rready[3]  ),
    .KSK_AXI_3_rresp   (m_axi4_ksk_rresp[3]   ),
    .KSK_AXI_3_rvalid  (m_axi4_ksk_rvalid[3]  ),
    .KSK_AXI_3_wdata   (m_axi4_ksk_wdata[3]   ),
    .KSK_AXI_3_wlast   (m_axi4_ksk_wlast[3]   ),
    .KSK_AXI_3_wready  (m_axi4_ksk_wready[3]  ),
    .KSK_AXI_3_wstrb   (m_axi4_ksk_wstrb[3]   ),
    .KSK_AXI_3_wvalid  (m_axi4_ksk_wvalid[3]  ),
    .KSK_AXI_4_araddr  (m_axi4_ksk_araddr[4]  ),
    .KSK_AXI_4_arburst (m_axi4_ksk_arburst[4] ),
    .KSK_AXI_4_arcache (m_axi4_ksk_arcache[4] ),
    .KSK_AXI_4_arid    (m_axi4_ksk_arid[4]    ),
    .KSK_AXI_4_arlen   (m_axi4_ksk_arlen[4]   ),
    .KSK_AXI_4_arlock  (m_axi4_ksk_arlock[4]  ),
    .KSK_AXI_4_arprot  (m_axi4_ksk_arprot[4]  ),
    .KSK_AXI_4_arready (m_axi4_ksk_arready[4] ),
    .KSK_AXI_4_arsize  (m_axi4_ksk_arsize[4]  ),
    //.KSK_AXI_4_aruser  (m_axi4_ksk_aruser[4]  ),
    .KSK_AXI_4_arvalid (m_axi4_ksk_arvalid[4] ),
    .KSK_AXI_4_awaddr  (m_axi4_ksk_awaddr[4]  ),
    .KSK_AXI_4_awburst (m_axi4_ksk_awburst[4] ),
    .KSK_AXI_4_awcache (m_axi4_ksk_awcache[4] ),
    .KSK_AXI_4_awid    (m_axi4_ksk_awid[4]    ),
    .KSK_AXI_4_awlen   (m_axi4_ksk_awlen[4]   ),
    .KSK_AXI_4_awlock  (m_axi4_ksk_awlock[4]  ),
    .KSK_AXI_4_awprot  (m_axi4_ksk_awprot[4]  ),
    .KSK_AXI_4_awready (m_axi4_ksk_awready[4] ),
    .KSK_AXI_4_awsize  (m_axi4_ksk_awsize[4]  ),
    //.KSK_AXI_4_awuser  (m_axi4_ksk_awuser[4]  ),
    .KSK_AXI_4_awvalid (m_axi4_ksk_awvalid[4] ),
    .KSK_AXI_4_bid     (m_axi4_ksk_bid[4]     ),
    .KSK_AXI_4_bready  (m_axi4_ksk_bready[4]  ),
    .KSK_AXI_4_bresp   (m_axi4_ksk_bresp[4]   ),
    //.KSK_AXI_4_buser   (m_axi4_ksk_buser[4]   ),
    .KSK_AXI_4_bvalid  (m_axi4_ksk_bvalid[4]  ),
    .KSK_AXI_4_rdata   (m_axi4_ksk_rdata[4]   ),
    .KSK_AXI_4_rid     (m_axi4_ksk_rid[4]     ),
    .KSK_AXI_4_rlast   (m_axi4_ksk_rlast[4]   ),
    .KSK_AXI_4_rready  (m_axi4_ksk_rready[4]  ),
    .KSK_AXI_4_rresp   (m_axi4_ksk_rresp[4]   ),
    .KSK_AXI_4_rvalid  (m_axi4_ksk_rvalid[4]  ),
    .KSK_AXI_4_wdata   (m_axi4_ksk_wdata[4]   ),
    .KSK_AXI_4_wlast   (m_axi4_ksk_wlast[4]   ),
    .KSK_AXI_4_wready  (m_axi4_ksk_wready[4]  ),
    .KSK_AXI_4_wstrb   (m_axi4_ksk_wstrb[4]   ),
    .KSK_AXI_4_wvalid  (m_axi4_ksk_wvalid[4]  ),
    .KSK_AXI_5_araddr  (m_axi4_ksk_araddr[5]  ),
    .KSK_AXI_5_arburst (m_axi4_ksk_arburst[5] ),
    .KSK_AXI_5_arcache (m_axi4_ksk_arcache[5] ),
    .KSK_AXI_5_arid    (m_axi4_ksk_arid[5]    ),
    .KSK_AXI_5_arlen   (m_axi4_ksk_arlen[5]   ),
    .KSK_AXI_5_arlock  (m_axi4_ksk_arlock[5]  ),
    .KSK_AXI_5_arprot  (m_axi4_ksk_arprot[5]  ),
    .KSK_AXI_5_arready (m_axi4_ksk_arready[5] ),
    .KSK_AXI_5_arsize  (m_axi4_ksk_arsize[5]  ),
    //.KSK_AXI_5_aruser  (m_axi4_ksk_aruser[5]  ),
    .KSK_AXI_5_arvalid (m_axi4_ksk_arvalid[5] ),
    .KSK_AXI_5_awaddr  (m_axi4_ksk_awaddr[5]  ),
    .KSK_AXI_5_awburst (m_axi4_ksk_awburst[5] ),
    .KSK_AXI_5_awcache (m_axi4_ksk_awcache[5] ),
    .KSK_AXI_5_awid    (m_axi4_ksk_awid[5]    ),
    .KSK_AXI_5_awlen   (m_axi4_ksk_awlen[5]   ),
    .KSK_AXI_5_awlock  (m_axi4_ksk_awlock[5]  ),
    .KSK_AXI_5_awprot  (m_axi4_ksk_awprot[5]  ),
    .KSK_AXI_5_awready (m_axi4_ksk_awready[5] ),
    .KSK_AXI_5_awsize  (m_axi4_ksk_awsize[5]  ),
    //.KSK_AXI_5_awuser  (m_axi4_ksk_awuser[5]  ),
    .KSK_AXI_5_awvalid (m_axi4_ksk_awvalid[5] ),
    .KSK_AXI_5_bid     (m_axi4_ksk_bid[5]     ),
    .KSK_AXI_5_bready  (m_axi4_ksk_bready[5]  ),
    .KSK_AXI_5_bresp   (m_axi4_ksk_bresp[5]   ),
    //.KSK_AXI_5_buser   (m_axi4_ksk_buser[5]   ),
    .KSK_AXI_5_bvalid  (m_axi4_ksk_bvalid[5]  ),
    .KSK_AXI_5_rdata   (m_axi4_ksk_rdata[5]   ),
    .KSK_AXI_5_rid     (m_axi4_ksk_rid[5]     ),
    .KSK_AXI_5_rlast   (m_axi4_ksk_rlast[5]   ),
    .KSK_AXI_5_rready  (m_axi4_ksk_rready[5]  ),
    .KSK_AXI_5_rresp   (m_axi4_ksk_rresp[5]   ),
    .KSK_AXI_5_rvalid  (m_axi4_ksk_rvalid[5]  ),
    .KSK_AXI_5_wdata   (m_axi4_ksk_wdata[5]   ),
    .KSK_AXI_5_wlast   (m_axi4_ksk_wlast[5]   ),
    .KSK_AXI_5_wready  (m_axi4_ksk_wready[5]  ),
    .KSK_AXI_5_wstrb   (m_axi4_ksk_wstrb[5]   ),
    .KSK_AXI_5_wvalid  (m_axi4_ksk_wvalid[5]  ),
    .KSK_AXI_6_araddr  (m_axi4_ksk_araddr[6]  ),
    .KSK_AXI_6_arburst (m_axi4_ksk_arburst[6] ),
    .KSK_AXI_6_arcache (m_axi4_ksk_arcache[6] ),
    .KSK_AXI_6_arid    (m_axi4_ksk_arid[6]    ),
    .KSK_AXI_6_arlen   (m_axi4_ksk_arlen[6]   ),
    .KSK_AXI_6_arlock  (m_axi4_ksk_arlock[6]  ),
    .KSK_AXI_6_arprot  (m_axi4_ksk_arprot[6]  ),
    .KSK_AXI_6_arready (m_axi4_ksk_arready[6] ),
    .KSK_AXI_6_arsize  (m_axi4_ksk_arsize[6]  ),
    //.KSK_AXI_6_aruser  (m_axi4_ksk_aruser[6]  ),
    .KSK_AXI_6_arvalid (m_axi4_ksk_arvalid[6] ),
    .KSK_AXI_6_awaddr  (m_axi4_ksk_awaddr[6]  ),
    .KSK_AXI_6_awburst (m_axi4_ksk_awburst[6] ),
    .KSK_AXI_6_awcache (m_axi4_ksk_awcache[6] ),
    .KSK_AXI_6_awid    (m_axi4_ksk_awid[6]    ),
    .KSK_AXI_6_awlen   (m_axi4_ksk_awlen[6]   ),
    .KSK_AXI_6_awlock  (m_axi4_ksk_awlock[6]  ),
    .KSK_AXI_6_awprot  (m_axi4_ksk_awprot[6]  ),
    .KSK_AXI_6_awready (m_axi4_ksk_awready[6] ),
    .KSK_AXI_6_awsize  (m_axi4_ksk_awsize[6]  ),
    //.KSK_AXI_6_awuser  (m_axi4_ksk_awuser[6]  ),
    .KSK_AXI_6_awvalid (m_axi4_ksk_awvalid[6] ),
    .KSK_AXI_6_bid     (m_axi4_ksk_bid[6]     ),
    .KSK_AXI_6_bready  (m_axi4_ksk_bready[6]  ),
    .KSK_AXI_6_bresp   (m_axi4_ksk_bresp[6]   ),
    //.KSK_AXI_6_buser   (m_axi4_ksk_buser[6]   ),
    .KSK_AXI_6_bvalid  (m_axi4_ksk_bvalid[6]  ),
    .KSK_AXI_6_rdata   (m_axi4_ksk_rdata[6]   ),
    .KSK_AXI_6_rid     (m_axi4_ksk_rid[6]     ),
    .KSK_AXI_6_rlast   (m_axi4_ksk_rlast[6]   ),
    .KSK_AXI_6_rready  (m_axi4_ksk_rready[6]  ),
    .KSK_AXI_6_rresp   (m_axi4_ksk_rresp[6]   ),
    .KSK_AXI_6_rvalid  (m_axi4_ksk_rvalid[6]  ),
    .KSK_AXI_6_wdata   (m_axi4_ksk_wdata[6]   ),
    .KSK_AXI_6_wlast   (m_axi4_ksk_wlast[6]   ),
    .KSK_AXI_6_wready  (m_axi4_ksk_wready[6]  ),
    .KSK_AXI_6_wstrb   (m_axi4_ksk_wstrb[6]   ),
    .KSK_AXI_6_wvalid  (m_axi4_ksk_wvalid[6]  ),
    .KSK_AXI_7_araddr  (m_axi4_ksk_araddr[7]  ),
    .KSK_AXI_7_arburst (m_axi4_ksk_arburst[7] ),
    .KSK_AXI_7_arcache (m_axi4_ksk_arcache[7] ),
    .KSK_AXI_7_arid    (m_axi4_ksk_arid[7]    ),
    .KSK_AXI_7_arlen   (m_axi4_ksk_arlen[7]   ),
    .KSK_AXI_7_arlock  (m_axi4_ksk_arlock[7]  ),
    .KSK_AXI_7_arprot  (m_axi4_ksk_arprot[7]  ),
    .KSK_AXI_7_arready (m_axi4_ksk_arready[7] ),
    .KSK_AXI_7_arsize  (m_axi4_ksk_arsize[7]  ),
    //.KSK_AXI_7_aruser  (m_axi4_ksk_aruser[7]  ),
    .KSK_AXI_7_arvalid (m_axi4_ksk_arvalid[7] ),
    .KSK_AXI_7_awaddr  (m_axi4_ksk_awaddr[7]  ),
    .KSK_AXI_7_awburst (m_axi4_ksk_awburst[7] ),
    .KSK_AXI_7_awcache (m_axi4_ksk_awcache[7] ),
    .KSK_AXI_7_awid    (m_axi4_ksk_awid[7]    ),
    .KSK_AXI_7_awlen   (m_axi4_ksk_awlen[7]   ),
    .KSK_AXI_7_awlock  (m_axi4_ksk_awlock[7]  ),
    .KSK_AXI_7_awprot  (m_axi4_ksk_awprot[7]  ),
    .KSK_AXI_7_awready (m_axi4_ksk_awready[7] ),
    .KSK_AXI_7_awsize  (m_axi4_ksk_awsize[7]  ),
    //.KSK_AXI_7_awuser  (m_axi4_ksk_awuser[7]  ),
    .KSK_AXI_7_awvalid (m_axi4_ksk_awvalid[7] ),
    .KSK_AXI_7_bid     (m_axi4_ksk_bid[7]     ),
    .KSK_AXI_7_bready  (m_axi4_ksk_bready[7]  ),
    .KSK_AXI_7_bresp   (m_axi4_ksk_bresp[7]   ),
    //.KSK_AXI_7_buser   (m_axi4_ksk_buser[7]   ),
    .KSK_AXI_7_bvalid  (m_axi4_ksk_bvalid[7]  ),
    .KSK_AXI_7_rdata   (m_axi4_ksk_rdata[7]   ),
    .KSK_AXI_7_rid     (m_axi4_ksk_rid[7]     ),
    .KSK_AXI_7_rlast   (m_axi4_ksk_rlast[7]   ),
    .KSK_AXI_7_rready  (m_axi4_ksk_rready[7]  ),
    .KSK_AXI_7_rresp   (m_axi4_ksk_rresp[7]   ),
    .KSK_AXI_7_rvalid  (m_axi4_ksk_rvalid[7]  ),
    .KSK_AXI_7_wdata   (m_axi4_ksk_wdata[7]   ),
    .KSK_AXI_7_wlast   (m_axi4_ksk_wlast[7]   ),
    .KSK_AXI_7_wready  (m_axi4_ksk_wready[7]  ),
    .KSK_AXI_7_wstrb   (m_axi4_ksk_wstrb[7]   ),
    .KSK_AXI_7_wvalid  (m_axi4_ksk_wvalid[7]  ),
    .KSK_AXI_8_araddr  (m_axi4_ksk_araddr[8]  ),
    .KSK_AXI_8_arburst (m_axi4_ksk_arburst[8] ),
    .KSK_AXI_8_arcache (m_axi4_ksk_arcache[8] ),
    .KSK_AXI_8_arid    (m_axi4_ksk_arid[8]    ),
    .KSK_AXI_8_arlen   (m_axi4_ksk_arlen[8]   ),
    .KSK_AXI_8_arlock  (m_axi4_ksk_arlock[8]  ),
    .KSK_AXI_8_arprot  (m_axi4_ksk_arprot[8]  ),
    .KSK_AXI_8_arready (m_axi4_ksk_arready[8] ),
    .KSK_AXI_8_arsize  (m_axi4_ksk_arsize[8]  ),
    //.KSK_AXI_8_aruser  (m_axi4_ksk_aruser[8]  ),
    .KSK_AXI_8_arvalid (m_axi4_ksk_arvalid[8] ),
    .KSK_AXI_8_awaddr  (m_axi4_ksk_awaddr[8]  ),
    .KSK_AXI_8_awburst (m_axi4_ksk_awburst[8] ),
    .KSK_AXI_8_awcache (m_axi4_ksk_awcache[8] ),
    .KSK_AXI_8_awid    (m_axi4_ksk_awid[8]    ),
    .KSK_AXI_8_awlen   (m_axi4_ksk_awlen[8]   ),
    .KSK_AXI_8_awlock  (m_axi4_ksk_awlock[8]  ),
    .KSK_AXI_8_awprot  (m_axi4_ksk_awprot[8]  ),
    .KSK_AXI_8_awready (m_axi4_ksk_awready[8] ),
    .KSK_AXI_8_awsize  (m_axi4_ksk_awsize[8]  ),
    //.KSK_AXI_8_awuser  (m_axi4_ksk_awuser[8]  ),
    .KSK_AXI_8_awvalid (m_axi4_ksk_awvalid[8] ),
    .KSK_AXI_8_bid     (m_axi4_ksk_bid[8]     ),
    .KSK_AXI_8_bready  (m_axi4_ksk_bready[8]  ),
    .KSK_AXI_8_bresp   (m_axi4_ksk_bresp[8]   ),
    //.KSK_AXI_8_buser   (m_axi4_ksk_buser[8]   ),
    .KSK_AXI_8_bvalid  (m_axi4_ksk_bvalid[8]  ),
    .KSK_AXI_8_rdata   (m_axi4_ksk_rdata[8]   ),
    .KSK_AXI_8_rid     (m_axi4_ksk_rid[8]     ),
    .KSK_AXI_8_rlast   (m_axi4_ksk_rlast[8]   ),
    .KSK_AXI_8_rready  (m_axi4_ksk_rready[8]  ),
    .KSK_AXI_8_rresp   (m_axi4_ksk_rresp[8]   ),
    .KSK_AXI_8_rvalid  (m_axi4_ksk_rvalid[8]  ),
    .KSK_AXI_8_wdata   (m_axi4_ksk_wdata[8]   ),
    .KSK_AXI_8_wlast   (m_axi4_ksk_wlast[8]   ),
    .KSK_AXI_8_wready  (m_axi4_ksk_wready[8]  ),
    .KSK_AXI_8_wstrb   (m_axi4_ksk_wstrb[8]   ),
    .KSK_AXI_8_wvalid  (m_axi4_ksk_wvalid[8]  ),
    .KSK_AXI_9_araddr  (m_axi4_ksk_araddr[9]  ),
    .KSK_AXI_9_arburst (m_axi4_ksk_arburst[9] ),
    .KSK_AXI_9_arcache (m_axi4_ksk_arcache[9] ),
    .KSK_AXI_9_arid    (m_axi4_ksk_arid[9]    ),
    .KSK_AXI_9_arlen   (m_axi4_ksk_arlen[9]   ),
    .KSK_AXI_9_arlock  (m_axi4_ksk_arlock[9]  ),
    .KSK_AXI_9_arprot  (m_axi4_ksk_arprot[9]  ),
    .KSK_AXI_9_arready (m_axi4_ksk_arready[9] ),
    .KSK_AXI_9_arsize  (m_axi4_ksk_arsize[9]  ),
    //.KSK_AXI_9_aruser  (m_axi4_ksk_aruser[9]  ),
    .KSK_AXI_9_arvalid (m_axi4_ksk_arvalid[9] ),
    .KSK_AXI_9_awaddr  (m_axi4_ksk_awaddr[9]  ),
    .KSK_AXI_9_awburst (m_axi4_ksk_awburst[9] ),
    .KSK_AXI_9_awcache (m_axi4_ksk_awcache[9] ),
    .KSK_AXI_9_awid    (m_axi4_ksk_awid[9]    ),
    .KSK_AXI_9_awlen   (m_axi4_ksk_awlen[9]   ),
    .KSK_AXI_9_awlock  (m_axi4_ksk_awlock[9]  ),
    .KSK_AXI_9_awprot  (m_axi4_ksk_awprot[9]  ),
    .KSK_AXI_9_awready (m_axi4_ksk_awready[9] ),
    .KSK_AXI_9_awsize  (m_axi4_ksk_awsize[9]  ),
    //.KSK_AXI_9_awuser  (m_axi4_ksk_awuser[9]  ),
    .KSK_AXI_9_awvalid (m_axi4_ksk_awvalid[9] ),
    .KSK_AXI_9_bid     (m_axi4_ksk_bid[9]     ),
    .KSK_AXI_9_bready  (m_axi4_ksk_bready[9]  ),
    .KSK_AXI_9_bresp   (m_axi4_ksk_bresp[9]   ),
    //.KSK_AXI_9_buser   (m_axi4_ksk_buser[9]   ),
    .KSK_AXI_9_bvalid  (m_axi4_ksk_bvalid[9]  ),
    .KSK_AXI_9_rdata   (m_axi4_ksk_rdata[9]   ),
    .KSK_AXI_9_rid     (m_axi4_ksk_rid[9]     ),
    .KSK_AXI_9_rlast   (m_axi4_ksk_rlast[9]   ),
    .KSK_AXI_9_rready  (m_axi4_ksk_rready[9]  ),
    .KSK_AXI_9_rresp   (m_axi4_ksk_rresp[9]   ),
    .KSK_AXI_9_rvalid  (m_axi4_ksk_rvalid[9]  ),
    .KSK_AXI_9_wdata   (m_axi4_ksk_wdata[9]   ),
    .KSK_AXI_9_wlast   (m_axi4_ksk_wlast[9]   ),
    .KSK_AXI_9_wready  (m_axi4_ksk_wready[9]  ),
    .KSK_AXI_9_wstrb   (m_axi4_ksk_wstrb[9]   ),
    .KSK_AXI_9_wvalid  (m_axi4_ksk_wvalid[9]  ),
    .KSK_AXI_10_araddr  (m_axi4_ksk_araddr[10]  ),
    .KSK_AXI_10_arburst (m_axi4_ksk_arburst[10] ),
    .KSK_AXI_10_arcache (m_axi4_ksk_arcache[10] ),
    .KSK_AXI_10_arid    (m_axi4_ksk_arid[10]    ),
    .KSK_AXI_10_arlen   (m_axi4_ksk_arlen[10]   ),
    .KSK_AXI_10_arlock  (m_axi4_ksk_arlock[10]  ),
    .KSK_AXI_10_arprot  (m_axi4_ksk_arprot[10]  ),
    .KSK_AXI_10_arready (m_axi4_ksk_arready[10] ),
    .KSK_AXI_10_arsize  (m_axi4_ksk_arsize[10]  ),
    //.KSK_AXI_10_aruser  (m_axi4_ksk_aruser[10]  ),
    .KSK_AXI_10_arvalid (m_axi4_ksk_arvalid[10] ),
    .KSK_AXI_10_awaddr  (m_axi4_ksk_awaddr[10]  ),
    .KSK_AXI_10_awburst (m_axi4_ksk_awburst[10] ),
    .KSK_AXI_10_awcache (m_axi4_ksk_awcache[10] ),
    .KSK_AXI_10_awid    (m_axi4_ksk_awid[10]    ),
    .KSK_AXI_10_awlen   (m_axi4_ksk_awlen[10]   ),
    .KSK_AXI_10_awlock  (m_axi4_ksk_awlock[10]  ),
    .KSK_AXI_10_awprot  (m_axi4_ksk_awprot[10]  ),
    .KSK_AXI_10_awready (m_axi4_ksk_awready[10] ),
    .KSK_AXI_10_awsize  (m_axi4_ksk_awsize[10]  ),
    //.KSK_AXI_10_awuser  (m_axi4_ksk_awuser[10]  ),
    .KSK_AXI_10_awvalid (m_axi4_ksk_awvalid[10] ),
    .KSK_AXI_10_bid     (m_axi4_ksk_bid[10]     ),
    .KSK_AXI_10_bready  (m_axi4_ksk_bready[10]  ),
    .KSK_AXI_10_bresp   (m_axi4_ksk_bresp[10]   ),
    //.KSK_AXI_10_buser   (m_axi4_ksk_buser[10]   ),
    .KSK_AXI_10_bvalid  (m_axi4_ksk_bvalid[10]  ),
    .KSK_AXI_10_rdata   (m_axi4_ksk_rdata[10]   ),
    .KSK_AXI_10_rid     (m_axi4_ksk_rid[10]     ),
    .KSK_AXI_10_rlast   (m_axi4_ksk_rlast[10]   ),
    .KSK_AXI_10_rready  (m_axi4_ksk_rready[10]  ),
    .KSK_AXI_10_rresp   (m_axi4_ksk_rresp[10]   ),
    .KSK_AXI_10_rvalid  (m_axi4_ksk_rvalid[10]  ),
    .KSK_AXI_10_wdata   (m_axi4_ksk_wdata[10]   ),
    .KSK_AXI_10_wlast   (m_axi4_ksk_wlast[10]   ),
    .KSK_AXI_10_wready  (m_axi4_ksk_wready[10]  ),
    .KSK_AXI_10_wstrb   (m_axi4_ksk_wstrb[10]   ),
    .KSK_AXI_10_wvalid  (m_axi4_ksk_wvalid[10]  ),
    .KSK_AXI_11_araddr  (m_axi4_ksk_araddr[11]  ),
    .KSK_AXI_11_arburst (m_axi4_ksk_arburst[11] ),
    .KSK_AXI_11_arcache (m_axi4_ksk_arcache[11] ),
    .KSK_AXI_11_arid    (m_axi4_ksk_arid[11]    ),
    .KSK_AXI_11_arlen   (m_axi4_ksk_arlen[11]   ),
    .KSK_AXI_11_arlock  (m_axi4_ksk_arlock[11]  ),
    .KSK_AXI_11_arprot  (m_axi4_ksk_arprot[11]  ),
    .KSK_AXI_11_arready (m_axi4_ksk_arready[11] ),
    .KSK_AXI_11_arsize  (m_axi4_ksk_arsize[11]  ),
    //.KSK_AXI_11_aruser  (m_axi4_ksk_aruser[11]  ),
    .KSK_AXI_11_arvalid (m_axi4_ksk_arvalid[11] ),
    .KSK_AXI_11_awaddr  (m_axi4_ksk_awaddr[11]  ),
    .KSK_AXI_11_awburst (m_axi4_ksk_awburst[11] ),
    .KSK_AXI_11_awcache (m_axi4_ksk_awcache[11] ),
    .KSK_AXI_11_awid    (m_axi4_ksk_awid[11]    ),
    .KSK_AXI_11_awlen   (m_axi4_ksk_awlen[11]   ),
    .KSK_AXI_11_awlock  (m_axi4_ksk_awlock[11]  ),
    .KSK_AXI_11_awprot  (m_axi4_ksk_awprot[11]  ),
    .KSK_AXI_11_awready (m_axi4_ksk_awready[11] ),
    .KSK_AXI_11_awsize  (m_axi4_ksk_awsize[11]  ),
    //.KSK_AXI_11_awuser  (m_axi4_ksk_awuser[11]  ),
    .KSK_AXI_11_awvalid (m_axi4_ksk_awvalid[11] ),
    .KSK_AXI_11_bid     (m_axi4_ksk_bid[11]     ),
    .KSK_AXI_11_bready  (m_axi4_ksk_bready[11]  ),
    .KSK_AXI_11_bresp   (m_axi4_ksk_bresp[11]   ),
    //.KSK_AXI_11_buser   (m_axi4_ksk_buser[11]   ),
    .KSK_AXI_11_bvalid  (m_axi4_ksk_bvalid[11]  ),
    .KSK_AXI_11_rdata   (m_axi4_ksk_rdata[11]   ),
    .KSK_AXI_11_rid     (m_axi4_ksk_rid[11]     ),
    .KSK_AXI_11_rlast   (m_axi4_ksk_rlast[11]   ),
    .KSK_AXI_11_rready  (m_axi4_ksk_rready[11]  ),
    .KSK_AXI_11_rresp   (m_axi4_ksk_rresp[11]   ),
    .KSK_AXI_11_rvalid  (m_axi4_ksk_rvalid[11]  ),
    .KSK_AXI_11_wdata   (m_axi4_ksk_wdata[11]   ),
    .KSK_AXI_11_wlast   (m_axi4_ksk_wlast[11]   ),
    .KSK_AXI_11_wready  (m_axi4_ksk_wready[11]  ),
    .KSK_AXI_11_wstrb   (m_axi4_ksk_wstrb[11]   ),
    .KSK_AXI_11_wvalid  (m_axi4_ksk_wvalid[11]  ),
    .KSK_AXI_12_araddr  (m_axi4_ksk_araddr[12]  ),
    .KSK_AXI_12_arburst (m_axi4_ksk_arburst[12] ),
    .KSK_AXI_12_arcache (m_axi4_ksk_arcache[12] ),
    .KSK_AXI_12_arid    (m_axi4_ksk_arid[12]    ),
    .KSK_AXI_12_arlen   (m_axi4_ksk_arlen[12]   ),
    .KSK_AXI_12_arlock  (m_axi4_ksk_arlock[12]  ),
    .KSK_AXI_12_arprot  (m_axi4_ksk_arprot[12]  ),
    .KSK_AXI_12_arready (m_axi4_ksk_arready[12] ),
    .KSK_AXI_12_arsize  (m_axi4_ksk_arsize[12]  ),
    //.KSK_AXI_12_aruser  (m_axi4_ksk_aruser[12]  ),
    .KSK_AXI_12_arvalid (m_axi4_ksk_arvalid[12] ),
    .KSK_AXI_12_awaddr  (m_axi4_ksk_awaddr[12]  ),
    .KSK_AXI_12_awburst (m_axi4_ksk_awburst[12] ),
    .KSK_AXI_12_awcache (m_axi4_ksk_awcache[12] ),
    .KSK_AXI_12_awid    (m_axi4_ksk_awid[12]    ),
    .KSK_AXI_12_awlen   (m_axi4_ksk_awlen[12]   ),
    .KSK_AXI_12_awlock  (m_axi4_ksk_awlock[12]  ),
    .KSK_AXI_12_awprot  (m_axi4_ksk_awprot[12]  ),
    .KSK_AXI_12_awready (m_axi4_ksk_awready[12] ),
    .KSK_AXI_12_awsize  (m_axi4_ksk_awsize[12]  ),
    //.KSK_AXI_12_awuser  (m_axi4_ksk_awuser[12]  ),
    .KSK_AXI_12_awvalid (m_axi4_ksk_awvalid[12] ),
    .KSK_AXI_12_bid     (m_axi4_ksk_bid[12]     ),
    .KSK_AXI_12_bready  (m_axi4_ksk_bready[12]  ),
    .KSK_AXI_12_bresp   (m_axi4_ksk_bresp[12]   ),
    //.KSK_AXI_12_buser   (m_axi4_ksk_buser[12]   ),
    .KSK_AXI_12_bvalid  (m_axi4_ksk_bvalid[12]  ),
    .KSK_AXI_12_rdata   (m_axi4_ksk_rdata[12]   ),
    .KSK_AXI_12_rid     (m_axi4_ksk_rid[12]     ),
    .KSK_AXI_12_rlast   (m_axi4_ksk_rlast[12]   ),
    .KSK_AXI_12_rready  (m_axi4_ksk_rready[12]  ),
    .KSK_AXI_12_rresp   (m_axi4_ksk_rresp[12]   ),
    .KSK_AXI_12_rvalid  (m_axi4_ksk_rvalid[12]  ),
    .KSK_AXI_12_wdata   (m_axi4_ksk_wdata[12]   ),
    .KSK_AXI_12_wlast   (m_axi4_ksk_wlast[12]   ),
    .KSK_AXI_12_wready  (m_axi4_ksk_wready[12]  ),
    .KSK_AXI_12_wstrb   (m_axi4_ksk_wstrb[12]   ),
    .KSK_AXI_12_wvalid  (m_axi4_ksk_wvalid[12]  ),
    .KSK_AXI_13_araddr  (m_axi4_ksk_araddr[13]  ),
    .KSK_AXI_13_arburst (m_axi4_ksk_arburst[13] ),
    .KSK_AXI_13_arcache (m_axi4_ksk_arcache[13] ),
    .KSK_AXI_13_arid    (m_axi4_ksk_arid[13]    ),
    .KSK_AXI_13_arlen   (m_axi4_ksk_arlen[13]   ),
    .KSK_AXI_13_arlock  (m_axi4_ksk_arlock[13]  ),
    .KSK_AXI_13_arprot  (m_axi4_ksk_arprot[13]  ),
    .KSK_AXI_13_arready (m_axi4_ksk_arready[13] ),
    .KSK_AXI_13_arsize  (m_axi4_ksk_arsize[13]  ),
    //.KSK_AXI_13_aruser  (m_axi4_ksk_aruser[13]  ),
    .KSK_AXI_13_arvalid (m_axi4_ksk_arvalid[13] ),
    .KSK_AXI_13_awaddr  (m_axi4_ksk_awaddr[13]  ),
    .KSK_AXI_13_awburst (m_axi4_ksk_awburst[13] ),
    .KSK_AXI_13_awcache (m_axi4_ksk_awcache[13] ),
    .KSK_AXI_13_awid    (m_axi4_ksk_awid[13]    ),
    .KSK_AXI_13_awlen   (m_axi4_ksk_awlen[13]   ),
    .KSK_AXI_13_awlock  (m_axi4_ksk_awlock[13]  ),
    .KSK_AXI_13_awprot  (m_axi4_ksk_awprot[13]  ),
    .KSK_AXI_13_awready (m_axi4_ksk_awready[13] ),
    .KSK_AXI_13_awsize  (m_axi4_ksk_awsize[13]  ),
    //.KSK_AXI_13_awuser  (m_axi4_ksk_awuser[13]  ),
    .KSK_AXI_13_awvalid (m_axi4_ksk_awvalid[13] ),
    .KSK_AXI_13_bid     (m_axi4_ksk_bid[13]     ),
    .KSK_AXI_13_bready  (m_axi4_ksk_bready[13]  ),
    .KSK_AXI_13_bresp   (m_axi4_ksk_bresp[13]   ),
    //.KSK_AXI_13_buser   (m_axi4_ksk_buser[13]   ),
    .KSK_AXI_13_bvalid  (m_axi4_ksk_bvalid[13]  ),
    .KSK_AXI_13_rdata   (m_axi4_ksk_rdata[13]   ),
    .KSK_AXI_13_rid     (m_axi4_ksk_rid[13]     ),
    .KSK_AXI_13_rlast   (m_axi4_ksk_rlast[13]   ),
    .KSK_AXI_13_rready  (m_axi4_ksk_rready[13]  ),
    .KSK_AXI_13_rresp   (m_axi4_ksk_rresp[13]   ),
    .KSK_AXI_13_rvalid  (m_axi4_ksk_rvalid[13]  ),
    .KSK_AXI_13_wdata   (m_axi4_ksk_wdata[13]   ),
    .KSK_AXI_13_wlast   (m_axi4_ksk_wlast[13]   ),
    .KSK_AXI_13_wready  (m_axi4_ksk_wready[13]  ),
    .KSK_AXI_13_wstrb   (m_axi4_ksk_wstrb[13]   ),
    .KSK_AXI_13_wvalid  (m_axi4_ksk_wvalid[13]  ),
    .KSK_AXI_14_araddr  (m_axi4_ksk_araddr[14]  ),
    .KSK_AXI_14_arburst (m_axi4_ksk_arburst[14] ),
    .KSK_AXI_14_arcache (m_axi4_ksk_arcache[14] ),
    .KSK_AXI_14_arid    (m_axi4_ksk_arid[14]    ),
    .KSK_AXI_14_arlen   (m_axi4_ksk_arlen[14]   ),
    .KSK_AXI_14_arlock  (m_axi4_ksk_arlock[14]  ),
    .KSK_AXI_14_arprot  (m_axi4_ksk_arprot[14]  ),
    .KSK_AXI_14_arready (m_axi4_ksk_arready[14] ),
    .KSK_AXI_14_arsize  (m_axi4_ksk_arsize[14]  ),
    //.KSK_AXI_14_aruser  (m_axi4_ksk_aruser[14]  ),
    .KSK_AXI_14_arvalid (m_axi4_ksk_arvalid[14] ),
    .KSK_AXI_14_awaddr  (m_axi4_ksk_awaddr[14]  ),
    .KSK_AXI_14_awburst (m_axi4_ksk_awburst[14] ),
    .KSK_AXI_14_awcache (m_axi4_ksk_awcache[14] ),
    .KSK_AXI_14_awid    (m_axi4_ksk_awid[14]    ),
    .KSK_AXI_14_awlen   (m_axi4_ksk_awlen[14]   ),
    .KSK_AXI_14_awlock  (m_axi4_ksk_awlock[14]  ),
    .KSK_AXI_14_awprot  (m_axi4_ksk_awprot[14]  ),
    .KSK_AXI_14_awready (m_axi4_ksk_awready[14] ),
    .KSK_AXI_14_awsize  (m_axi4_ksk_awsize[14]  ),
    //.KSK_AXI_14_awuser  (m_axi4_ksk_awuser[14]  ),
    .KSK_AXI_14_awvalid (m_axi4_ksk_awvalid[14] ),
    .KSK_AXI_14_bid     (m_axi4_ksk_bid[14]     ),
    .KSK_AXI_14_bready  (m_axi4_ksk_bready[14]  ),
    .KSK_AXI_14_bresp   (m_axi4_ksk_bresp[14]   ),
    //.KSK_AXI_14_buser   (m_axi4_ksk_buser[14]   ),
    .KSK_AXI_14_bvalid  (m_axi4_ksk_bvalid[14]  ),
    .KSK_AXI_14_rdata   (m_axi4_ksk_rdata[14]   ),
    .KSK_AXI_14_rid     (m_axi4_ksk_rid[14]     ),
    .KSK_AXI_14_rlast   (m_axi4_ksk_rlast[14]   ),
    .KSK_AXI_14_rready  (m_axi4_ksk_rready[14]  ),
    .KSK_AXI_14_rresp   (m_axi4_ksk_rresp[14]   ),
    .KSK_AXI_14_rvalid  (m_axi4_ksk_rvalid[14]  ),
    .KSK_AXI_14_wdata   (m_axi4_ksk_wdata[14]   ),
    .KSK_AXI_14_wlast   (m_axi4_ksk_wlast[14]   ),
    .KSK_AXI_14_wready  (m_axi4_ksk_wready[14]  ),
    .KSK_AXI_14_wstrb   (m_axi4_ksk_wstrb[14]   ),
    .KSK_AXI_14_wvalid  (m_axi4_ksk_wvalid[14]  ),
    .KSK_AXI_15_araddr  (m_axi4_ksk_araddr[15]  ),
    .KSK_AXI_15_arburst (m_axi4_ksk_arburst[15] ),
    .KSK_AXI_15_arcache (m_axi4_ksk_arcache[15] ),
    .KSK_AXI_15_arid    (m_axi4_ksk_arid[15]    ),
    .KSK_AXI_15_arlen   (m_axi4_ksk_arlen[15]   ),
    .KSK_AXI_15_arlock  (m_axi4_ksk_arlock[15]  ),
    .KSK_AXI_15_arprot  (m_axi4_ksk_arprot[15]  ),
    .KSK_AXI_15_arready (m_axi4_ksk_arready[15] ),
    .KSK_AXI_15_arsize  (m_axi4_ksk_arsize[15]  ),
    //.KSK_AXI_15_aruser  (m_axi4_ksk_aruser[15]  ),
    .KSK_AXI_15_arvalid (m_axi4_ksk_arvalid[15] ),
    .KSK_AXI_15_awaddr  (m_axi4_ksk_awaddr[15]  ),
    .KSK_AXI_15_awburst (m_axi4_ksk_awburst[15] ),
    .KSK_AXI_15_awcache (m_axi4_ksk_awcache[15] ),
    .KSK_AXI_15_awid    (m_axi4_ksk_awid[15]    ),
    .KSK_AXI_15_awlen   (m_axi4_ksk_awlen[15]   ),
    .KSK_AXI_15_awlock  (m_axi4_ksk_awlock[15]  ),
    .KSK_AXI_15_awprot  (m_axi4_ksk_awprot[15]  ),
    .KSK_AXI_15_awready (m_axi4_ksk_awready[15] ),
    .KSK_AXI_15_awsize  (m_axi4_ksk_awsize[15]  ),
    //.KSK_AXI_15_awuser  (m_axi4_ksk_awuser[15]  ),
    .KSK_AXI_15_awvalid (m_axi4_ksk_awvalid[15] ),
    .KSK_AXI_15_bid     (m_axi4_ksk_bid[15]     ),
    .KSK_AXI_15_bready  (m_axi4_ksk_bready[15]  ),
    .KSK_AXI_15_bresp   (m_axi4_ksk_bresp[15]   ),
    //.KSK_AXI_15_buser   (m_axi4_ksk_buser[15]   ),
    .KSK_AXI_15_bvalid  (m_axi4_ksk_bvalid[15]  ),
    .KSK_AXI_15_rdata   (m_axi4_ksk_rdata[15]   ),
    .KSK_AXI_15_rid     (m_axi4_ksk_rid[15]     ),
    .KSK_AXI_15_rlast   (m_axi4_ksk_rlast[15]   ),
    .KSK_AXI_15_rready  (m_axi4_ksk_rready[15]  ),
    .KSK_AXI_15_rresp   (m_axi4_ksk_rresp[15]   ),
    .KSK_AXI_15_rvalid  (m_axi4_ksk_rvalid[15]  ),
    .KSK_AXI_15_wdata   (m_axi4_ksk_wdata[15]   ),
    .KSK_AXI_15_wlast   (m_axi4_ksk_wlast[15]   ),
    .KSK_AXI_15_wready  (m_axi4_ksk_wready[15]  ),
    .KSK_AXI_15_wstrb   (m_axi4_ksk_wstrb[15]   ),
    .KSK_AXI_15_wvalid  (m_axi4_ksk_wvalid[15]  ),

    .ETH_HBM_AXI_0_araddr  (m_axi4_eth_hbm_araddr[0]  ),
    .ETH_HBM_AXI_0_arburst (m_axi4_eth_hbm_arburst[0] ),
    .ETH_HBM_AXI_0_arcache (m_axi4_eth_hbm_arcache[0] ),
    // .ETH_HBM_AXI_0_arid    (m_axi4_eth_hbm_arid[0]    ),
    .ETH_HBM_AXI_0_arlen   (m_axi4_eth_hbm_arlen[0]   ),
    .ETH_HBM_AXI_0_arlock  (m_axi4_eth_hbm_arlock[0]  ),
    .ETH_HBM_AXI_0_arprot  (m_axi4_eth_hbm_arprot[0]  ),
    .ETH_HBM_AXI_0_arready (m_axi4_eth_hbm_arready[0] ),
    .ETH_HBM_AXI_0_arsize  (m_axi4_eth_hbm_arsize[0]  ),
    // .ETH_HBM_AXI_0_aruser  (m_axi4_eth_hbm_aruser[0]  ),//
    .ETH_HBM_AXI_0_arvalid (m_axi4_eth_hbm_arvalid[0] ),
    .ETH_HBM_AXI_0_awaddr  (m_axi4_eth_hbm_awaddr[0]  ),
    .ETH_HBM_AXI_0_awburst (m_axi4_eth_hbm_awburst[0] ),
    .ETH_HBM_AXI_0_awcache (m_axi4_eth_hbm_awcache[0] ),
    // .ETH_HBM_AXI_0_awid    (m_axi4_eth_hbm_awid[0]    ),
    .ETH_HBM_AXI_0_awlen   (m_axi4_eth_hbm_awlen[0]   ),
    .ETH_HBM_AXI_0_awlock  (m_axi4_eth_hbm_awlock[0]  ),
    .ETH_HBM_AXI_0_awprot  (m_axi4_eth_hbm_awprot[0]  ),
    .ETH_HBM_AXI_0_awready (m_axi4_eth_hbm_awready[0] ),
    .ETH_HBM_AXI_0_awsize  (m_axi4_eth_hbm_awsize[0]  ),
    // .ETH_HBM_AXI_0_awuser  (m_axi4_eth_hbm_awuser[0]  ),//
    .ETH_HBM_AXI_0_awvalid (m_axi4_eth_hbm_awvalid[0] ),
    // .ETH_HBM_AXI_0_bid     (m_axi4_eth_hbm_bid[0]     ),
    .ETH_HBM_AXI_0_bready  (m_axi4_eth_hbm_bready[0]  ),
    .ETH_HBM_AXI_0_bresp   (m_axi4_eth_hbm_bresp[0]   ),
    // .ETH_HBM_AXI_0_buser   (m_axi4_eth_hbm_buser[0]   ),//
    .ETH_HBM_AXI_0_bvalid  (m_axi4_eth_hbm_bvalid[0]  ),
    .ETH_HBM_AXI_0_rdata   (m_axi4_eth_hbm_rdata[0]   ),
    // .ETH_HBM_AXI_0_rid     (m_axi4_eth_hbm_rid[0]     ),
    .ETH_HBM_AXI_0_rlast   (m_axi4_eth_hbm_rlast[0]   ),
    .ETH_HBM_AXI_0_rready  (m_axi4_eth_hbm_rready[0]  ),
    .ETH_HBM_AXI_0_rresp   (m_axi4_eth_hbm_rresp[0]   ),
    .ETH_HBM_AXI_0_rvalid  (m_axi4_eth_hbm_rvalid[0]  ),
    .ETH_HBM_AXI_0_wdata   (m_axi4_eth_hbm_wdata[0]   ),
    .ETH_HBM_AXI_0_wlast   (m_axi4_eth_hbm_wlast[0]   ),
    .ETH_HBM_AXI_0_wready  (m_axi4_eth_hbm_wready[0]  ),
    .ETH_HBM_AXI_0_wstrb   (m_axi4_eth_hbm_wstrb[0]   ),
    .ETH_HBM_AXI_0_wvalid  (m_axi4_eth_hbm_wvalid[0]  ),

    .ETH_HBM_AXI_1_araddr  (m_axi4_eth_hbm_araddr[1]  ),
    .ETH_HBM_AXI_1_arburst (m_axi4_eth_hbm_arburst[1] ),
    .ETH_HBM_AXI_1_arcache (m_axi4_eth_hbm_arcache[1] ),
    // .ETH_HBM_AXI_1_arid    (m_axi4_eth_hbm_arid[1]    ),
    .ETH_HBM_AXI_1_arlen   (m_axi4_eth_hbm_arlen[1]   ),
    .ETH_HBM_AXI_1_arlock  (m_axi4_eth_hbm_arlock[1]  ),
    .ETH_HBM_AXI_1_arprot  (m_axi4_eth_hbm_arprot[1]  ),
    .ETH_HBM_AXI_1_arready (m_axi4_eth_hbm_arready[1] ),
    .ETH_HBM_AXI_1_arsize  (m_axi4_eth_hbm_arsize[1]  ),
    // .ETH_HBM_AXI_1_aruser  (m_axi4_eth_hbm_aruser[1]  ),//
    .ETH_HBM_AXI_1_arvalid (m_axi4_eth_hbm_arvalid[1] ),
    .ETH_HBM_AXI_1_awaddr  (m_axi4_eth_hbm_awaddr[1]  ),
    .ETH_HBM_AXI_1_awburst (m_axi4_eth_hbm_awburst[1] ),
    .ETH_HBM_AXI_1_awcache (m_axi4_eth_hbm_awcache[1] ),
    // .ETH_HBM_AXI_1_awid    (m_axi4_eth_hbm_awid[1]    ),
    .ETH_HBM_AXI_1_awlen   (m_axi4_eth_hbm_awlen[1]   ),
    .ETH_HBM_AXI_1_awlock  (m_axi4_eth_hbm_awlock[1]  ),
    .ETH_HBM_AXI_1_awprot  (m_axi4_eth_hbm_awprot[1]  ),
    .ETH_HBM_AXI_1_awready (m_axi4_eth_hbm_awready[1] ),
    .ETH_HBM_AXI_1_awsize  (m_axi4_eth_hbm_awsize[1]  ),
    // .ETH_HBM_AXI_1_awuser  (m_axi4_eth_hbm_awuser[1]  ),//
    .ETH_HBM_AXI_1_awvalid (m_axi4_eth_hbm_awvalid[1] ),
    // .ETH_HBM_AXI_1_bid     (m_axi4_eth_hbm_bid[1]     ),
    .ETH_HBM_AXI_1_bready  (m_axi4_eth_hbm_bready[1]  ),
    .ETH_HBM_AXI_1_bresp   (m_axi4_eth_hbm_bresp[1]   ),
    // .ETH_HBM_AXI_1_buser   (m_axi4_eth_hbm_buser[1]   ),//
    .ETH_HBM_AXI_1_bvalid  (m_axi4_eth_hbm_bvalid[1]  ),
    .ETH_HBM_AXI_1_rdata   (m_axi4_eth_hbm_rdata[1]   ),
    // .ETH_HBM_AXI_1_rid     (m_axi4_eth_hbm_rid[1]     ),
    .ETH_HBM_AXI_1_rlast   (m_axi4_eth_hbm_rlast[1]   ),
    .ETH_HBM_AXI_1_rready  (m_axi4_eth_hbm_rready[1]  ),
    .ETH_HBM_AXI_1_rresp   (m_axi4_eth_hbm_rresp[1]   ),
    .ETH_HBM_AXI_1_rvalid  (m_axi4_eth_hbm_rvalid[1]  ),
    .ETH_HBM_AXI_1_wdata   (m_axi4_eth_hbm_wdata[1]   ),
    .ETH_HBM_AXI_1_wlast   (m_axi4_eth_hbm_wlast[1]   ),
    .ETH_HBM_AXI_1_wready  (m_axi4_eth_hbm_wready[1]  ),
    .ETH_HBM_AXI_1_wstrb   (m_axi4_eth_hbm_wstrb[1]   ),
    .ETH_HBM_AXI_1_wvalid  (m_axi4_eth_hbm_wvalid[1]  ),

    /* AXI stream
     */
    .axis_m_lpd_tdata  (axis_m_rx_tdata_tmp ),
    .axis_m_lpd_tlast  (axis_m_rx_tlast ),
    .axis_m_lpd_tready (axis_m_rx_tready),
    .axis_m_lpd_tvalid (axis_m_rx_tvalid),

    .axis_m_rx_tdata   (axis_m_rx_tdata),
    .axis_m_rx_tdest   ('h0),
    .axis_m_rx_tkeep   ({16{1'b1}}),
    .axis_m_rx_tlast   (axis_m_rx_tlast),
    .axis_m_rx_tready  (axis_m_rx_tready),
    .axis_m_rx_tvalid  (axis_m_rx_tvalid),

    .axis_m_tx_tdata   (axis_m_tx_tdata),
    .axis_m_tx_tdest   (/* UNUSED */),
    .axis_m_tx_tkeep   (/* UNUSED */),
    .axis_m_tx_tlast   (/* UNUSED */),
    .axis_m_tx_tready  (axis_m_tx_tready),
    .axis_m_tx_tvalid  (axis_m_tx_tvalid),

    .axis_s_lpd_tdata  (axis_s_tx_tdata_tmp ),
    .axis_s_lpd_tlast  (axis_s_tx_tlast ),
    .axis_s_lpd_tready (axis_s_tx_tready),
    .axis_s_lpd_tvalid (axis_s_tx_tvalid),

    .axis_s_rx_tdata   (axis_s_rx_tdata),
    .axis_s_rx_tdest   ('h0),
    .axis_s_rx_tkeep   ({16{1'b1}}),
    .axis_s_rx_tlast   (axis_s_rx_tlast),
    .axis_s_rx_tready  (axis_s_rx_tready),
    .axis_s_rx_tvalid  (axis_s_rx_tvalid),

    .axis_s_tx_tdata   (axis_s_tx_tdata),
    .axis_s_tx_tdest   (/* UNUSED */),
    .axis_s_tx_tkeep   (/* UNUSED */),
    .axis_s_tx_tlast   (axis_s_tx_tlast),
    .axis_s_tx_tready  (axis_s_tx_tready),
    .axis_s_tx_tvalid  (axis_s_tx_tvalid),

    /* PCIEXPRESS
     * Same parameters as AVED example design
     */
    .gt_pcie_refclk_clk_n(top_gt_pcie_refclk_clk_n),
    .gt_pcie_refclk_clk_p(top_gt_pcie_refclk_clk_p),

    .gt_pciea1_grx_n(top_gt_pciea1_grx_n),
    .gt_pciea1_grx_p(top_gt_pciea1_grx_p),
    .gt_pciea1_gtx_n(top_gt_pciea1_gtx_n),
    .gt_pciea1_gtx_p(top_gt_pciea1_gtx_p),

    /* Axi4-lite loopback
     * in order to set correct address-space to access ethernet configuration link
     * ETH_AXI_X_ corresponds to the X'th output of the NOC
     * ETH_AXI_ID corresponds to "ID" block
      * address is x8008'0000 + offset while the two IPs are expecting for x0000'XXXX
     *
     * AXI 0 -> id=cfg (IP) mrmac configuration registers
     * AXI 1 -> direct access to dma regfile
     */
    .ETH_AXI_0_araddr   (axi_eth_mrmac_araddr),
    .ETH_AXI_0_arready  (axi_eth_mrmac_arready),
    .ETH_AXI_0_arvalid  (axi_eth_mrmac_arvalid),
    .ETH_AXI_0_awaddr   (axi_eth_mrmac_awaddr),
    .ETH_AXI_0_awready  (axi_eth_mrmac_awready),
    .ETH_AXI_0_awvalid  (axi_eth_mrmac_awvalid),
    .ETH_AXI_0_bready   (axi_eth_mrmac_bready),
    .ETH_AXI_0_bresp    (axi_eth_mrmac_bresp),
    .ETH_AXI_0_bvalid   (axi_eth_mrmac_bvalid),
    .ETH_AXI_0_rdata    (axi_eth_mrmac_rdata),
    .ETH_AXI_0_rready   (axi_eth_mrmac_rready),
    .ETH_AXI_0_rresp    (axi_eth_mrmac_rresp),
    .ETH_AXI_0_rvalid   (axi_eth_mrmac_rvalid),
    .ETH_AXI_0_wdata    (axi_eth_mrmac_wdata),
    .ETH_AXI_0_wready   (axi_eth_mrmac_wready),
    .ETH_AXI_0_wvalid   (axi_eth_mrmac_wvalid),
    // unused after loopback
    .ETH_AXI_0_arprot   (axi_eth_mrmac_arprot),
    .ETH_AXI_0_awprot   (axi_eth_mrmac_awprot),
    .ETH_AXI_0_wstrb    (axi_eth_mrmac_wstrb),

    .ETH_AXI_CFG_araddr   ({'h0000, axi_eth_mrmac_araddr[15:0]}),
    .ETH_AXI_CFG_arready  (axi_eth_mrmac_arready),
    .ETH_AXI_CFG_arvalid  (axi_eth_mrmac_arvalid),
    .ETH_AXI_CFG_awaddr   ({'h0000, axi_eth_mrmac_awaddr[15:0]}),
    .ETH_AXI_CFG_awready  (axi_eth_mrmac_awready),
    .ETH_AXI_CFG_awvalid  (axi_eth_mrmac_awvalid),
    .ETH_AXI_CFG_bready   (axi_eth_mrmac_bready),
    .ETH_AXI_CFG_bresp    (axi_eth_mrmac_bresp),
    .ETH_AXI_CFG_bvalid   (axi_eth_mrmac_bvalid),
    .ETH_AXI_CFG_rdata    (axi_eth_mrmac_rdata),
    .ETH_AXI_CFG_rready   (axi_eth_mrmac_rready),
    .ETH_AXI_CFG_rresp    (axi_eth_mrmac_rresp),
    .ETH_AXI_CFG_rvalid   (axi_eth_mrmac_rvalid),
    .ETH_AXI_CFG_wdata    (axi_eth_mrmac_wdata),
    .ETH_AXI_CFG_wready   (axi_eth_mrmac_wready),
    .ETH_AXI_CFG_wvalid   (axi_eth_mrmac_wvalid),

    // access to regfile in dma
    .ETH_AXI_1_araddr   (axi_eth_dma_araddr),
    .ETH_AXI_1_arready  (axi_eth_dma_arready),
    .ETH_AXI_1_arvalid  (axi_eth_dma_arvalid),
    .ETH_AXI_1_awaddr   (axi_eth_dma_awaddr),
    .ETH_AXI_1_awready  (axi_eth_dma_awready),
    .ETH_AXI_1_awvalid  (axi_eth_dma_awvalid),
    .ETH_AXI_1_bready   (axi_eth_dma_bready),
    .ETH_AXI_1_bresp    (axi_eth_dma_bresp),
    .ETH_AXI_1_bvalid   (axi_eth_dma_bvalid),
    .ETH_AXI_1_rdata    (axi_eth_dma_rdata),
    .ETH_AXI_1_rready   (axi_eth_dma_rready),
    .ETH_AXI_1_rresp    (axi_eth_dma_rresp),
    .ETH_AXI_1_rvalid   (axi_eth_dma_rvalid),
    .ETH_AXI_1_wdata    (axi_eth_dma_wdata),
    .ETH_AXI_1_wready   (axi_eth_dma_wready),
    .ETH_AXI_1_wvalid   (axi_eth_dma_wvalid),
    // unused after loopback
    .ETH_AXI_1_arprot   (axi_eth_dma_arprot),
    .ETH_AXI_1_awprot   (axi_eth_dma_awprot),
    .ETH_AXI_1_wstrb    (axi_eth_dma_wstrb),

    /* Transceivers ------------------------------------------------------------------- //
     * -> GTM for one QSFP port
     * -> NRZ modulation
     * -> four lanes
    //  ------------------------------------------------------------------------------ */
    .gt_rxn_in_0  (qsfp3_4x_grx_n),
    .gt_rxp_in_0  (qsfp3_4x_grx_p),
    .gt_txn_out_0 (qsfp3_4x_gtx_n),
    .gt_txp_out_0 (qsfp3_4x_gtx_p),
    // input clocks
    .CLK_IN_D_clk_n  (gt_ref_clk_n),
    .CLK_IN_D_clk_p  (gt_ref_clk_p),
    // control signals
    .ch0_loopback (gt_loopback),
    .ch0_rxrate   (SW_REG_GT_LINE_RATE[7:0]),
    .ch0_txrate   (SW_REG_GT_LINE_RATE[7:0]),
    .ch1_loopback (gt_loopback),
    .ch1_rxrate   (SW_REG_GT_LINE_RATE[15:8]),
    .ch1_txrate   (SW_REG_GT_LINE_RATE[15:8]),
    .ch2_loopback (gt_loopback),
    .ch2_rxrate   (SW_REG_GT_LINE_RATE[23:16]),
    .ch2_txrate   (SW_REG_GT_LINE_RATE[23:16]),
    .ch3_loopback (gt_loopback),
    .ch3_rxrate   (SW_REG_GT_LINE_RATE[31:24]),
    .ch3_txrate   (SW_REG_GT_LINE_RATE[31:24]),

    /* MRMAC: MultiRate MAC subsystem ---------------------------------------------------
     * -> includes MAC + PCS
     * -> Site is chosen by a loc in bd
     * -> Segmented 4x25G (NRZ)
    //  ------------------------------------------------------------------------------ */
    // == RX datapath
    // Lane 0
    .rx_axis_tdata_0     (qsfp_rx_tdata[0]),
    .rx_axis_tkeep_user_0(qsfp_rx_tkeep_user[0]),
    .rx_axis_tlast_0     (qsfp_rx_tlast[0]),
    .rx_axis_tvalid_0    (qsfp_rx_tvalid[0]),
    // Lane 1
    .rx_axis_tdata_2     (qsfp_rx_tdata[1]),
    .rx_axis_tkeep_user_2(qsfp_rx_tkeep_user[1]),
    .rx_axis_tlast_2     (qsfp_rx_tlast[1]),
    .rx_axis_tvalid_2    (qsfp_rx_tvalid[1]),
    // Lane 2
    .rx_axis_tdata_4     (qsfp_rx_tdata[2]),
    .rx_axis_tkeep_user_4(qsfp_rx_tkeep_user[2]),
    .rx_axis_tlast_4     (qsfp_rx_tlast[2]),
    .rx_axis_tvalid_4    (qsfp_rx_tvalid[2]),
    // Lane 3
    .rx_axis_tdata_6     (qsfp_rx_tdata[3]),
    .rx_axis_tkeep_user_6(qsfp_rx_tkeep_user[3]),
    .rx_axis_tlast_6     (qsfp_rx_tlast[3]),
    .rx_axis_tvalid_6    (qsfp_rx_tvalid[3]),
    // == TX datapath
    // Lane 0
    .tx_axis_tdata_0     (qsfp_tx_tdata[0]),
    .tx_axis_tkeep_user_0(qsfp_tx_tkeep_user[0]),
    .tx_axis_tlast_0     (qsfp_tx_tlast[0]),
    .tx_axis_tvalid_0    (qsfp_tx_tvalid[0]),
    .tx_axis_tready_0    (qsfp_tx_tready[0]),
    // Lane 1
    .tx_axis_tdata_2     (qsfp_tx_tdata[1]),
    .tx_axis_tkeep_user_2(qsfp_tx_tkeep_user[1]),
    .tx_axis_tlast_2     (qsfp_tx_tlast[1]),
    .tx_axis_tvalid_2    (qsfp_tx_tvalid[1]),
    .tx_axis_tready_2    (qsfp_tx_tready[1]),
    // Lane 2
    .tx_axis_tdata_4     (qsfp_tx_tdata[2]),
    .tx_axis_tkeep_user_4(qsfp_tx_tkeep_user[2]),
    .tx_axis_tlast_4     (qsfp_tx_tlast[2]),
    .tx_axis_tvalid_4    (qsfp_tx_tvalid[2]),
    .tx_axis_tready_4    (qsfp_tx_tready[2]),
    // Lane 3
    .tx_axis_tdata_6     (qsfp_tx_tdata[3]),
    .tx_axis_tkeep_user_6(qsfp_tx_tkeep_user[3]),
    .tx_axis_tlast_6     (qsfp_tx_tlast[3]),
    .tx_axis_tvalid_6    (qsfp_tx_tvalid[3]),
    .tx_axis_tready_6    (qsfp_tx_tready[3]),
    //  ----------------------------------- reset ------------------------------------ //
    .gt_tx_reset_done_out    (gt_tx_reset_done),
    .gt_rx_reset_done_out    (gt_rx_reset_done),
    // programmable resets
    .gt_reset_all_in         (gt_reset_all),
    .gt_reset_tx_datapath_in (gt_reset_tx_datapath),
    .gt_reset_rx_datapath_in (gt_reset_rx_datapath),
    //  ---------------------------------- control ----------------------------------- //
    // performance monitoring
    .pm_rdy                  (pm_rdy),
    // Control tx
    .ctl_tx_port0_ctl_tx_lane0_vlm_bip7_override       (1'b0),
    .ctl_tx_port0_ctl_tx_lane0_vlm_bip7_override_value (8'd0),
    .ctl_tx_port0_ctl_tx_send_idle_in                  (1'b0),
    .ctl_tx_port0_ctl_tx_send_lfi_in                   (1'b0),
    .ctl_tx_port0_ctl_tx_send_rfi_in                   (1'b0),
    .ctl_tx_port1_ctl_tx_send_idle_in                  (1'b0),
    .ctl_tx_port1_ctl_tx_send_lfi_in                   (1'b0),
    .ctl_tx_port1_ctl_tx_send_rfi_in                   (1'b0),
    .ctl_tx_port2_ctl_tx_lane0_vlm_bip7_override       (1'b0),
    .ctl_tx_port2_ctl_tx_lane0_vlm_bip7_override_value (8'd0),
    .ctl_tx_port2_ctl_tx_send_idle_in                  (1'b0),
    .ctl_tx_port2_ctl_tx_send_lfi_in                   (1'b0),
    .ctl_tx_port2_ctl_tx_send_rfi_in                   (1'b0),
    .ctl_tx_port3_ctl_tx_send_idle_in                  (1'b0),
    .ctl_tx_port3_ctl_tx_send_lfi_in                   (1'b0),
    .ctl_tx_port3_ctl_tx_send_rfi_in                   (1'b0),
    // hardcoded tx preamble
    .tx_preamblein_tx_preamblein_0 (TX_PREAMBLE),
    .tx_preamblein_tx_preamblein_1 (TX_PREAMBLE),
    .tx_preamblein_tx_preamblein_2 (TX_PREAMBLE),
    .tx_preamblein_tx_preamblein_3 (TX_PREAMBLE),
    /* Clocks Resets Generator ----------------------------------------------------------
     * -> register
     * -> ethernet
     * -> DDR
    //  ------------------------------------------------------------------------------ */
    //  direct form CIPS
    .pl0_ref_clk_0  (),
    .pl0_resetn_0   (),

    .resetn_usr_0_ic_0(prc_free_srst_n),
    .resetn_usr_0_ic_0_gated(prc_srst_n),
    .resetn_usr_1_ic_0(cfg_srst_n),

    .clk_usr_0_0(prc_clk),
    .clk_usr_0_0_fr(prc_free_clk),
    .clk_usr_1_0(cfg_clk),
    .clk_usr_0_0_ce(prc_ce),

    // == Ethernet
    // MRMAC clock - axi4-stream
    .clk_axis_mrmac    (clk_axis_mrmac),
    .resetn_axis_mrmac (resetn_axis_mrmac),
    // configuration clock - axi4-lite
    .clk_eth_cfg_0      (eth_cfg_clk),
    .resetn_eth_cfg_ic_0(eth_cfg_srst_n),

    // == DDR
    .sys_clk0_0_clk_n(top_sys_clk0_0_clk_n),
    .sys_clk0_0_clk_p(top_sys_clk0_0_clk_p),
    .sys_clk0_1_clk_n(top_sys_clk0_1_clk_n),
    .sys_clk0_1_clk_p(top_sys_clk0_1_clk_p)
  );

//=====================================
// HPU
//=====================================
  hpu_3parts # (
    .VERSION_MAJOR    (VERSION_MAJOR),
    .VERSION_MINOR    (VERSION_MINOR),
    .AXI4_TRC_ADD_W   (AXI4_TRC_ADD_W),
    .AXI4_PEM_ADD_W   (AXI4_PEM_ADD_W),
    .AXI4_GLWE_ADD_W  (AXI4_GLWE_ADD_W),
    .AXI4_BSK_ADD_W   (AXI4_BSK_ADD_W),
    .AXI4_KSK_ADD_W   (AXI4_KSK_ADD_W),
    .INTER_PART_PIPE  (INTER_PART_PIPE),
    .QSFP_LANE_NB          (QSFP_LANE_NB),
    .AXIS_TDATA_W     (AXIS_TDATA_W),
    .AXIS_TKEEP_W     (AXIS_TKEEP_W)
  ) hpu_3parts (
    .prc_free_clk                  (prc_free_clk),
    .prc_free_srst_n               (prc_free_srst_n),

    .prc_clk                       (prc_clk),
    .prc_ce                        (prc_ce),
    .prc_srst_n                    (prc_srst_n),

    .cfg_clk                       (cfg_clk),
    .cfg_srst_n                    (cfg_srst_n),

    .cfg_eth_clk                   (eth_cfg_clk),
    .cfg_eth_srst_n                (eth_cfg_srst_n),

    .prc_mrmac_clk                 (clk_axis_mrmac),
    .prc_mrmac_srst_n              (resetn_axis_mrmac),

    /* AXI-LITE
     * Direct connection to the hpu regif
     */
    .s_axil_prc_1in3_awaddr        (axi_regif_prc_awaddr[0]),
    .s_axil_prc_1in3_awvalid       (axi_regif_prc_awvalid[0]),
    .s_axil_prc_1in3_awready       (axi_regif_prc_awready[0]),
    .s_axil_prc_1in3_wdata         (axi_regif_prc_wdata[0]),
    .s_axil_prc_1in3_wstrb         (axi_regif_prc_wstrb[0]),
    .s_axil_prc_1in3_wvalid        (axi_regif_prc_wvalid[0]),
    .s_axil_prc_1in3_wready        (axi_regif_prc_wready[0]),
    .s_axil_prc_1in3_bresp         (axi_regif_prc_bresp[0]),
    .s_axil_prc_1in3_bvalid        (axi_regif_prc_bvalid[0]),
    .s_axil_prc_1in3_bready        (axi_regif_prc_bready[0]),
    .s_axil_prc_1in3_araddr        (axi_regif_prc_araddr[0]),
    .s_axil_prc_1in3_arvalid       (axi_regif_prc_arvalid[0]),
    .s_axil_prc_1in3_arready       (axi_regif_prc_arready[0]),
    .s_axil_prc_1in3_rdata         (axi_regif_prc_rdata[0]),
    .s_axil_prc_1in3_rresp         (axi_regif_prc_rresp[0]),
    .s_axil_prc_1in3_rvalid        (axi_regif_prc_rvalid[0]),
    .s_axil_prc_1in3_rready        (axi_regif_prc_rready[0]),

    .s_axil_cfg_1in3_awaddr        (axi_regif_cfg_awaddr[0]),
    .s_axil_cfg_1in3_awvalid       (axi_regif_cfg_awvalid[0]),
    .s_axil_cfg_1in3_awready       (axi_regif_cfg_awready[0]),
    .s_axil_cfg_1in3_wdata         (axi_regif_cfg_wdata[0]),
    .s_axil_cfg_1in3_wstrb         (axi_regif_cfg_wstrb[0]),
    .s_axil_cfg_1in3_wvalid        (axi_regif_cfg_wvalid[0]),
    .s_axil_cfg_1in3_wready        (axi_regif_cfg_wready[0]),
    .s_axil_cfg_1in3_bresp         (axi_regif_cfg_bresp[0]),
    .s_axil_cfg_1in3_bvalid        (axi_regif_cfg_bvalid[0]),
    .s_axil_cfg_1in3_bready        (axi_regif_cfg_bready[0]),
    .s_axil_cfg_1in3_araddr        (axi_regif_cfg_araddr[0]),
    .s_axil_cfg_1in3_arvalid       (axi_regif_cfg_arvalid[0]),
    .s_axil_cfg_1in3_arready       (axi_regif_cfg_arready[0]),
    .s_axil_cfg_1in3_rdata         (axi_regif_cfg_rdata[0]),
    .s_axil_cfg_1in3_rresp         (axi_regif_cfg_rresp[0]),
    .s_axil_cfg_1in3_rvalid        (axi_regif_cfg_rvalid[0]),
    .s_axil_cfg_1in3_rready        (axi_regif_cfg_rready[0]),

    .s_axil_prc_3in3_awaddr        (axi_regif_prc_awaddr[1]),
    .s_axil_prc_3in3_awvalid       (axi_regif_prc_awvalid[1]),
    .s_axil_prc_3in3_awready       (axi_regif_prc_awready[1]),
    .s_axil_prc_3in3_wdata         (axi_regif_prc_wdata[1]),
    .s_axil_prc_3in3_wstrb         (axi_regif_prc_wstrb[1]),
    .s_axil_prc_3in3_wvalid        (axi_regif_prc_wvalid[1]),
    .s_axil_prc_3in3_wready        (axi_regif_prc_wready[1]),
    .s_axil_prc_3in3_bresp         (axi_regif_prc_bresp[1]),
    .s_axil_prc_3in3_bvalid        (axi_regif_prc_bvalid[1]),
    .s_axil_prc_3in3_bready        (axi_regif_prc_bready[1]),
    .s_axil_prc_3in3_araddr        (axi_regif_prc_araddr[1]),
    .s_axil_prc_3in3_arvalid       (axi_regif_prc_arvalid[1]),
    .s_axil_prc_3in3_arready       (axi_regif_prc_arready[1]),
    .s_axil_prc_3in3_rdata         (axi_regif_prc_rdata[1]),
    .s_axil_prc_3in3_rresp         (axi_regif_prc_rresp[1]),
    .s_axil_prc_3in3_rvalid        (axi_regif_prc_rvalid[1]),
    .s_axil_prc_3in3_rready        (axi_regif_prc_rready[1]),

    .s_axil_cfg_3in3_awaddr        (axi_regif_cfg_awaddr[1]),
    .s_axil_cfg_3in3_awvalid       (axi_regif_cfg_awvalid[1]),
    .s_axil_cfg_3in3_awready       (axi_regif_cfg_awready[1]),
    .s_axil_cfg_3in3_wdata         (axi_regif_cfg_wdata[1]),
    .s_axil_cfg_3in3_wstrb         (axi_regif_cfg_wstrb[1]),
    .s_axil_cfg_3in3_wvalid        (axi_regif_cfg_wvalid[1]),
    .s_axil_cfg_3in3_wready        (axi_regif_cfg_wready[1]),
    .s_axil_cfg_3in3_bresp         (axi_regif_cfg_bresp[1]),
    .s_axil_cfg_3in3_bvalid        (axi_regif_cfg_bvalid[1]),
    .s_axil_cfg_3in3_bready        (axi_regif_cfg_bready[1]),
    .s_axil_cfg_3in3_araddr        (axi_regif_cfg_araddr[1]),
    .s_axil_cfg_3in3_arvalid       (axi_regif_cfg_arvalid[1]),
    .s_axil_cfg_3in3_arready       (axi_regif_cfg_arready[1]),
    .s_axil_cfg_3in3_rdata         (axi_regif_cfg_rdata[1]),
    .s_axil_cfg_3in3_rresp         (axi_regif_cfg_rresp[1]),
    .s_axil_cfg_3in3_rvalid        (axi_regif_cfg_rvalid[1]),
    .s_axil_cfg_3in3_rready        (axi_regif_cfg_rready[1]),

    .s_axil_dma_2in3_awaddr        (axi_eth_dma_awaddr),
    .s_axil_dma_2in3_awvalid       (axi_eth_dma_awvalid),
    .s_axil_dma_2in3_awready       (axi_eth_dma_awready),
    .s_axil_dma_2in3_wdata         (axi_eth_dma_wdata),
    .s_axil_dma_2in3_wstrb         (axi_eth_dma_wstrb),
    .s_axil_dma_2in3_wvalid        (axi_eth_dma_wvalid),
    .s_axil_dma_2in3_wready        (axi_eth_dma_wready),
    .s_axil_dma_2in3_bresp         (axi_eth_dma_bresp),
    .s_axil_dma_2in3_bvalid        (axi_eth_dma_bvalid),
    .s_axil_dma_2in3_bready        (axi_eth_dma_bready),
    .s_axil_dma_2in3_araddr        (axi_eth_dma_araddr),
    .s_axil_dma_2in3_arvalid       (axi_eth_dma_arvalid),
    .s_axil_dma_2in3_arready       (axi_eth_dma_arready),
    .s_axil_dma_2in3_rdata         (axi_eth_dma_rdata),
    .s_axil_dma_2in3_rresp         (axi_eth_dma_rresp),
    .s_axil_dma_2in3_rvalid        (axi_eth_dma_rvalid),
    .s_axil_dma_2in3_rready        (axi_eth_dma_rready),

    .m_axi4_trc_awid               (m_axi4_trc_awid),
    .m_axi4_trc_awaddr             (m_axi4_trc_awaddr),
    .m_axi4_trc_awlen              (m_axi4_trc_awlen),
    .m_axi4_trc_awsize             (m_axi4_trc_awsize),
    .m_axi4_trc_awburst            (m_axi4_trc_awburst),
    .m_axi4_trc_awvalid            (m_axi4_trc_awvalid),
    .m_axi4_trc_awready            (m_axi4_trc_awready),
    .m_axi4_trc_wdata              (m_axi4_trc_wdata),
    .m_axi4_trc_wstrb              (m_axi4_trc_wstrb),
    .m_axi4_trc_wlast              (m_axi4_trc_wlast),
    .m_axi4_trc_wvalid             (m_axi4_trc_wvalid),
    .m_axi4_trc_wready             (m_axi4_trc_wready),
    .m_axi4_trc_bid                (m_axi4_trc_bid),
    .m_axi4_trc_bresp              (m_axi4_trc_bresp),
    .m_axi4_trc_bvalid             (m_axi4_trc_bvalid),
    .m_axi4_trc_bready             (m_axi4_trc_bready),
    .m_axi4_trc_awlock             (m_axi4_trc_awlock),
    .m_axi4_trc_awcache            (m_axi4_trc_awcache),
    .m_axi4_trc_awprot             (m_axi4_trc_awprot),
    .m_axi4_trc_awqos              (m_axi4_trc_awqos),
    .m_axi4_trc_awregion           (m_axi4_trc_awregion),
    .m_axi4_trc_arid               (m_axi4_trc_arid),
    .m_axi4_trc_araddr             (m_axi4_trc_araddr),
    .m_axi4_trc_arlen              (m_axi4_trc_arlen),
    .m_axi4_trc_arsize             (m_axi4_trc_arsize),
    .m_axi4_trc_arburst            (m_axi4_trc_arburst),
    .m_axi4_trc_arvalid            (m_axi4_trc_arvalid),
    .m_axi4_trc_arready            (m_axi4_trc_arready),
    .m_axi4_trc_rid                (m_axi4_trc_rid),
    .m_axi4_trc_rdata              (m_axi4_trc_rdata),
    .m_axi4_trc_rresp              (m_axi4_trc_rresp),
    .m_axi4_trc_rlast              (m_axi4_trc_rlast),
    .m_axi4_trc_rvalid             (m_axi4_trc_rvalid),
    .m_axi4_trc_rready             (m_axi4_trc_rready),
    .m_axi4_trc_arlock             (m_axi4_trc_arlock),
    .m_axi4_trc_arcache            (m_axi4_trc_arcache),
    .m_axi4_trc_arprot             (m_axi4_trc_arprot),
    .m_axi4_trc_arqos              (m_axi4_trc_arqos),
    .m_axi4_trc_arregion           (m_axi4_trc_arregion),

    .m_axi4_pem_awid               (m_axi4_pem_awid),
    .m_axi4_pem_awaddr             (m_axi4_pem_awaddr),
    .m_axi4_pem_awlen              (m_axi4_pem_awlen),
    .m_axi4_pem_awsize             (m_axi4_pem_awsize),
    .m_axi4_pem_awburst            (m_axi4_pem_awburst),
    .m_axi4_pem_awvalid            (m_axi4_pem_awvalid),
    .m_axi4_pem_awready            (m_axi4_pem_awready),
    .m_axi4_pem_wdata              (m_axi4_pem_wdata),
    .m_axi4_pem_wstrb              (m_axi4_pem_wstrb),
    .m_axi4_pem_wlast              (m_axi4_pem_wlast),
    .m_axi4_pem_wvalid             (m_axi4_pem_wvalid),
    .m_axi4_pem_wready             (m_axi4_pem_wready),
    .m_axi4_pem_bid                (m_axi4_pem_bid),
    .m_axi4_pem_bresp              (m_axi4_pem_bresp),
    .m_axi4_pem_bvalid             (m_axi4_pem_bvalid),
    .m_axi4_pem_bready             (m_axi4_pem_bready),
    .m_axi4_pem_awlock             (m_axi4_pem_awlock),
    .m_axi4_pem_awcache            (m_axi4_pem_awcache),
    .m_axi4_pem_awprot             (m_axi4_pem_awprot),
    .m_axi4_pem_awqos              (m_axi4_pem_awqos),
    .m_axi4_pem_awregion           (m_axi4_pem_awregion),
    .m_axi4_pem_arid               (m_axi4_pem_arid),
    .m_axi4_pem_araddr             (m_axi4_pem_araddr),
    .m_axi4_pem_arlen              (m_axi4_pem_arlen),
    .m_axi4_pem_arsize             (m_axi4_pem_arsize),
    .m_axi4_pem_arburst            (m_axi4_pem_arburst),
    .m_axi4_pem_arvalid            (m_axi4_pem_arvalid),
    .m_axi4_pem_arready            (m_axi4_pem_arready),
    .m_axi4_pem_rid                (m_axi4_pem_rid),
    .m_axi4_pem_rdata              (m_axi4_pem_rdata),
    .m_axi4_pem_rresp              (m_axi4_pem_rresp),
    .m_axi4_pem_rlast              (m_axi4_pem_rlast),
    .m_axi4_pem_rvalid             (m_axi4_pem_rvalid),
    .m_axi4_pem_rready             (m_axi4_pem_rready),
    .m_axi4_pem_arlock             (m_axi4_pem_arlock),
    .m_axi4_pem_arcache            (m_axi4_pem_arcache),
    .m_axi4_pem_arprot             (m_axi4_pem_arprot),
    .m_axi4_pem_arqos              (m_axi4_pem_arqos),
    .m_axi4_pem_arregion           (m_axi4_pem_arregion),

    .m_axi4_glwe_awid              (m_axi4_glwe_awid),
    .m_axi4_glwe_awaddr            (m_axi4_glwe_awaddr),
    .m_axi4_glwe_awlen             (m_axi4_glwe_awlen),
    .m_axi4_glwe_awsize            (m_axi4_glwe_awsize),
    .m_axi4_glwe_awburst           (m_axi4_glwe_awburst),
    .m_axi4_glwe_awvalid           (m_axi4_glwe_awvalid),
    .m_axi4_glwe_awready           (m_axi4_glwe_awready),
    .m_axi4_glwe_wdata             (m_axi4_glwe_wdata),
    .m_axi4_glwe_wstrb             (m_axi4_glwe_wstrb),
    .m_axi4_glwe_wlast             (m_axi4_glwe_wlast),
    .m_axi4_glwe_wvalid            (m_axi4_glwe_wvalid),
    .m_axi4_glwe_wready            (m_axi4_glwe_wready),
    .m_axi4_glwe_bid               (m_axi4_glwe_bid),
    .m_axi4_glwe_bresp             (m_axi4_glwe_bresp),
    .m_axi4_glwe_bvalid            (m_axi4_glwe_bvalid),
    .m_axi4_glwe_bready            (m_axi4_glwe_bready),
    .m_axi4_glwe_awlock            (m_axi4_glwe_awlock),
    .m_axi4_glwe_awcache           (m_axi4_glwe_awcache),
    .m_axi4_glwe_awprot            (m_axi4_glwe_awprot),
    .m_axi4_glwe_awqos             (m_axi4_glwe_awqos),
    .m_axi4_glwe_awregion          (m_axi4_glwe_awregion),
    .m_axi4_glwe_arid              (m_axi4_glwe_arid),
    .m_axi4_glwe_araddr            (m_axi4_glwe_araddr),
    .m_axi4_glwe_arlen             (m_axi4_glwe_arlen),
    .m_axi4_glwe_arsize            (m_axi4_glwe_arsize),
    .m_axi4_glwe_arburst           (m_axi4_glwe_arburst),
    .m_axi4_glwe_arvalid           (m_axi4_glwe_arvalid),
    .m_axi4_glwe_arready           (m_axi4_glwe_arready),
    .m_axi4_glwe_rid               (m_axi4_glwe_rid),
    .m_axi4_glwe_rdata             (m_axi4_glwe_rdata),
    .m_axi4_glwe_rresp             (m_axi4_glwe_rresp),
    .m_axi4_glwe_rlast             (m_axi4_glwe_rlast),
    .m_axi4_glwe_rvalid            (m_axi4_glwe_rvalid),
    .m_axi4_glwe_rready            (m_axi4_glwe_rready),
    .m_axi4_glwe_arlock            (m_axi4_glwe_arlock),
    .m_axi4_glwe_arcache           (m_axi4_glwe_arcache),
    .m_axi4_glwe_arprot            (m_axi4_glwe_arprot),
    .m_axi4_glwe_arqos             (m_axi4_glwe_arqos),
    .m_axi4_glwe_arregion          (m_axi4_glwe_arregion),

    .m_axi4_bsk_awid               (m_axi4_bsk_awid),
    .m_axi4_bsk_awaddr             (m_axi4_bsk_awaddr),
    .m_axi4_bsk_awlen              (m_axi4_bsk_awlen),
    .m_axi4_bsk_awsize             (m_axi4_bsk_awsize),
    .m_axi4_bsk_awburst            (m_axi4_bsk_awburst),
    .m_axi4_bsk_awvalid            (m_axi4_bsk_awvalid),
    .m_axi4_bsk_awready            (m_axi4_bsk_awready),
    .m_axi4_bsk_wdata              (m_axi4_bsk_wdata),
    .m_axi4_bsk_wstrb              (m_axi4_bsk_wstrb),
    .m_axi4_bsk_wlast              (m_axi4_bsk_wlast),
    .m_axi4_bsk_wvalid             (m_axi4_bsk_wvalid),
    .m_axi4_bsk_wready             (m_axi4_bsk_wready),
    .m_axi4_bsk_bid                (m_axi4_bsk_bid),
    .m_axi4_bsk_bresp              (m_axi4_bsk_bresp),
    .m_axi4_bsk_bvalid             (m_axi4_bsk_bvalid),
    .m_axi4_bsk_bready             (m_axi4_bsk_bready),
    .m_axi4_bsk_awlock             (m_axi4_bsk_awlock),
    .m_axi4_bsk_awcache            (m_axi4_bsk_awcache),
    .m_axi4_bsk_awprot             (m_axi4_bsk_awprot),
    .m_axi4_bsk_awqos              (m_axi4_bsk_awqos),
    .m_axi4_bsk_awregion           (m_axi4_bsk_awregion),
    .m_axi4_bsk_arid               (m_axi4_bsk_arid),
    .m_axi4_bsk_araddr             (m_axi4_bsk_araddr),
    .m_axi4_bsk_arlen              (m_axi4_bsk_arlen),
    .m_axi4_bsk_arsize             (m_axi4_bsk_arsize),
    .m_axi4_bsk_arburst            (m_axi4_bsk_arburst),
    .m_axi4_bsk_arvalid            (m_axi4_bsk_arvalid),
    .m_axi4_bsk_arready            (m_axi4_bsk_arready),
    .m_axi4_bsk_rid                (m_axi4_bsk_rid),
    .m_axi4_bsk_rdata              (m_axi4_bsk_rdata),
    .m_axi4_bsk_rresp              (m_axi4_bsk_rresp),
    .m_axi4_bsk_rlast              (m_axi4_bsk_rlast),
    .m_axi4_bsk_rvalid             (m_axi4_bsk_rvalid),
    .m_axi4_bsk_rready             (m_axi4_bsk_rready),
    .m_axi4_bsk_arlock             (m_axi4_bsk_arlock),
    .m_axi4_bsk_arcache            (m_axi4_bsk_arcache),
    .m_axi4_bsk_arprot             (m_axi4_bsk_arprot),
    .m_axi4_bsk_arqos              (m_axi4_bsk_arqos),
    .m_axi4_bsk_arregion           (m_axi4_bsk_arregion),

    .m_axi4_ksk_awid               (m_axi4_ksk_awid),
    .m_axi4_ksk_awaddr             (m_axi4_ksk_awaddr),
    .m_axi4_ksk_awlen              (m_axi4_ksk_awlen),
    .m_axi4_ksk_awsize             (m_axi4_ksk_awsize),
    .m_axi4_ksk_awburst            (m_axi4_ksk_awburst),
    .m_axi4_ksk_awvalid            (m_axi4_ksk_awvalid),
    .m_axi4_ksk_awready            (m_axi4_ksk_awready),
    .m_axi4_ksk_wdata              (m_axi4_ksk_wdata),
    .m_axi4_ksk_wstrb              (m_axi4_ksk_wstrb),
    .m_axi4_ksk_wlast              (m_axi4_ksk_wlast),
    .m_axi4_ksk_wvalid             (m_axi4_ksk_wvalid),
    .m_axi4_ksk_wready             (m_axi4_ksk_wready),
    .m_axi4_ksk_bid                (m_axi4_ksk_bid),
    .m_axi4_ksk_bresp              (m_axi4_ksk_bresp),
    .m_axi4_ksk_bvalid             (m_axi4_ksk_bvalid),
    .m_axi4_ksk_bready             (m_axi4_ksk_bready),
    .m_axi4_ksk_awlock             (m_axi4_ksk_awlock),
    .m_axi4_ksk_awcache            (m_axi4_ksk_awcache),
    .m_axi4_ksk_awprot             (m_axi4_ksk_awprot),
    .m_axi4_ksk_awqos              (m_axi4_ksk_awqos),
    .m_axi4_ksk_awregion           (m_axi4_ksk_awregion),
    .m_axi4_ksk_arid               (m_axi4_ksk_arid),
    .m_axi4_ksk_araddr             (m_axi4_ksk_araddr),
    .m_axi4_ksk_arlen              (m_axi4_ksk_arlen),
    .m_axi4_ksk_arsize             (m_axi4_ksk_arsize),
    .m_axi4_ksk_arburst            (m_axi4_ksk_arburst),
    .m_axi4_ksk_arvalid            (m_axi4_ksk_arvalid),
    .m_axi4_ksk_arready            (m_axi4_ksk_arready),
    .m_axi4_ksk_rid                (m_axi4_ksk_rid),
    .m_axi4_ksk_rdata              (m_axi4_ksk_rdata),
    .m_axi4_ksk_rresp              (m_axi4_ksk_rresp),
    .m_axi4_ksk_rlast              (m_axi4_ksk_rlast),
    .m_axi4_ksk_rvalid             (m_axi4_ksk_rvalid),
    .m_axi4_ksk_rready             (m_axi4_ksk_rready),
    .m_axi4_ksk_arlock             (m_axi4_ksk_arlock),
    .m_axi4_ksk_arcache            (m_axi4_ksk_arcache),
    .m_axi4_ksk_arprot             (m_axi4_ksk_arprot),
    .m_axi4_ksk_arqos              (m_axi4_ksk_arqos),
    .m_axi4_ksk_arregion           (m_axi4_ksk_arregion),

    .m_axi4_eth_hbm_awid           (m_axi4_eth_hbm_awid),
    .m_axi4_eth_hbm_awaddr         (m_axi4_eth_hbm_awaddr),
    .m_axi4_eth_hbm_awlen          (m_axi4_eth_hbm_awlen),
    .m_axi4_eth_hbm_awsize         (m_axi4_eth_hbm_awsize),
    .m_axi4_eth_hbm_awburst        (m_axi4_eth_hbm_awburst),
    .m_axi4_eth_hbm_awvalid        (m_axi4_eth_hbm_awvalid),
    .m_axi4_eth_hbm_awready        (m_axi4_eth_hbm_awready),
    .m_axi4_eth_hbm_wdata          (m_axi4_eth_hbm_wdata),
    .m_axi4_eth_hbm_wstrb          (m_axi4_eth_hbm_wstrb),
    .m_axi4_eth_hbm_wlast          (m_axi4_eth_hbm_wlast),
    .m_axi4_eth_hbm_wvalid         (m_axi4_eth_hbm_wvalid),
    .m_axi4_eth_hbm_wready         (m_axi4_eth_hbm_wready),
    .m_axi4_eth_hbm_bid            (m_axi4_eth_hbm_bid),
    .m_axi4_eth_hbm_bresp          (m_axi4_eth_hbm_bresp),
    .m_axi4_eth_hbm_bvalid         (m_axi4_eth_hbm_bvalid),
    .m_axi4_eth_hbm_bready         (m_axi4_eth_hbm_bready),
    .m_axi4_eth_hbm_awlock         (m_axi4_eth_hbm_awlock),
    .m_axi4_eth_hbm_awcache        (m_axi4_eth_hbm_awcache),
    .m_axi4_eth_hbm_awprot         (m_axi4_eth_hbm_awprot),
    .m_axi4_eth_hbm_awqos          (m_axi4_eth_hbm_awqos),
    .m_axi4_eth_hbm_awregion       (m_axi4_eth_hbm_awregion),
    .m_axi4_eth_hbm_arid           (m_axi4_eth_hbm_arid),
    .m_axi4_eth_hbm_araddr         (m_axi4_eth_hbm_araddr),
    .m_axi4_eth_hbm_arlen          (m_axi4_eth_hbm_arlen),
    .m_axi4_eth_hbm_arsize         (m_axi4_eth_hbm_arsize),
    .m_axi4_eth_hbm_arburst        (m_axi4_eth_hbm_arburst),
    .m_axi4_eth_hbm_arvalid        (m_axi4_eth_hbm_arvalid),
    .m_axi4_eth_hbm_arready        (m_axi4_eth_hbm_arready),
    .m_axi4_eth_hbm_rid            (m_axi4_eth_hbm_rid),
    .m_axi4_eth_hbm_rdata          (m_axi4_eth_hbm_rdata),
    .m_axi4_eth_hbm_rresp          (m_axi4_eth_hbm_rresp),
    .m_axi4_eth_hbm_rlast          (m_axi4_eth_hbm_rlast),
    .m_axi4_eth_hbm_rvalid         (m_axi4_eth_hbm_rvalid),
    .m_axi4_eth_hbm_rready         (m_axi4_eth_hbm_rready),
    .m_axi4_eth_hbm_arlock         (m_axi4_eth_hbm_arlock),
    .m_axi4_eth_hbm_arcache        (m_axi4_eth_hbm_arcache),
    .m_axi4_eth_hbm_arprot         (m_axi4_eth_hbm_arprot),
    .m_axi4_eth_hbm_arqos          (m_axi4_eth_hbm_arqos),
    .m_axi4_eth_hbm_arregion       (m_axi4_eth_hbm_arregion),

    /* AXI-STREAM interface
     * Instruction scheduler
     */
    // master
    .isc_dop                       (isc_dop),
    .isc_dop_rdy                   (isc_dop_rdy),
    .isc_dop_vld                   (isc_dop_vld),
    // slave
    .isc_ack                       (isc_ack),
    .isc_ack_rdy                   (isc_ack_rdy),
    .isc_ack_vld                   (isc_ack_vld),

    // interrupts
    .interrupt                     (hpu_interrupt), //TODO
    .interrupt_notify              (interrupt_notify),
    .interrupt_read_request        (interrupt_read_request),

    // QSFP system interface
    .qsfp_tx_tdata                 (qsfp_tx_tdata),
    .qsfp_tx_tkeep_user            (qsfp_tx_tkeep_user),
    .qsfp_tx_tlast                 (qsfp_tx_tlast),
    .qsfp_tx_tvalid                (qsfp_tx_tvalid),
    .qsfp_tx_tready                (qsfp_tx_tready),

    .qsfp_rx_tdata                 (qsfp_rx_tdata),
    .qsfp_rx_tkeep_user            (qsfp_rx_tkeep_user),
    .qsfp_rx_tlast                 (qsfp_rx_tlast),
    .qsfp_rx_tvalid                (qsfp_rx_tvalid),

    // transceivers
    .gt_loopback                   (gt_loopback),
    .gt_line_rate                  (gt_line_rate),
    .gt_reset_rx_datapath          (gt_reset_rx_datapath),
    .gt_reset_tx_datapath          (gt_reset_tx_datapath),
    .gt_reset_all                  (gt_reset_all),
    .gt_rx_reset_done              (gt_rx_reset_done),
    .gt_tx_reset_done              (gt_tx_reset_done)
  );

endmodule
