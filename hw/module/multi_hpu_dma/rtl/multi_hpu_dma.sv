// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : multi-HPU DMA
// ----------------------------------------------------------------------------------------------
// phys_addr = hbm_pc_offset + ctId * ciphertext_size
// ==============================================================================================

module multi_hpu_dma
  import mhdma_pkg::*;                    // multi-hpu-dma
  import axi_if_shell_axil_pkg::*;        // axi4-lite + REG_DATA_W
  import axi_if_common_param_pkg::*;      // general axi4
  import hpu_regif_core_eth_2in3_pkg::*;  // ethernet regif
(
  // Ethernet configuration interface -----------------------------------------
  input logic                                                    clk_eth_cfg,
  input logic                                                    resetn_eth_cfg,
  // Ethernet fast clock interface --------------------------------------------
  input logic                                                    clk_eth_mrmac,
  input logic                                                    resetn_eth_mrmac,
  // Axi4-lite slave interface for regfile ------------------------------------
  input  logic [AXIL_ADD_W-1:0]                                  s_axil_dma_awaddr,
  input  logic                                                   s_axil_dma_awvalid,
  output logic                                                   s_axil_dma_awready,
  input  logic [AXIL_DATA_W-1:0]                                 s_axil_dma_wdata,
  input  logic [AXIL_DATA_BYTES-1:0]                             s_axil_dma_wstrb,        // unused
  input  logic                                                   s_axil_dma_wvalid,
  output logic                                                   s_axil_dma_wready,
  output logic [1:0]                                             s_axil_dma_bresp,
  output logic                                                   s_axil_dma_bvalid,
  input  logic                                                   s_axil_dma_bready,
  input  logic [AXIL_ADD_W-1:0]                                  s_axil_dma_araddr,
  input  logic                                                   s_axil_dma_arvalid,
  output logic                                                   s_axil_dma_arready,
  output logic [AXIL_DATA_W-1:0]                                 s_axil_dma_rdata,
  output logic [1:0]                                             s_axil_dma_rresp,
  output logic                                                   s_axil_dma_rvalid,
  input  logic                                                   s_axil_dma_rready,
  // Axi4-full HBM interface --------------------------------------------------
  // Write channel
  output logic [ETH_PC-1:0][axi_if_eth_axi_pkg::AXI4_ID_W-1:0]   m_axi4_eth_hbm_awid,
  output logic [ETH_PC-1:0][axi_if_eth_axi_pkg::AXI4_ADD_W-1:0]  m_axi4_eth_hbm_awaddr,
  output logic [ETH_PC-1:0][AXI4_LEN_W-1:0]                      m_axi4_eth_hbm_awlen,
  output logic [ETH_PC-1:0][AXI4_SIZE_W-1:0]                     m_axi4_eth_hbm_awsize,
  output logic [ETH_PC-1:0][AXI4_BURST_W-1:0]                    m_axi4_eth_hbm_awburst,
  output logic [ETH_PC-1:0]                                      m_axi4_eth_hbm_awvalid,
  input  logic [ETH_PC-1:0]                                      m_axi4_eth_hbm_awready,
  output logic [ETH_PC-1:0][axi_if_eth_axi_pkg::AXI4_DATA_W-1:0] m_axi4_eth_hbm_wdata,
  output logic [ETH_PC-1:0][axi_if_eth_axi_pkg::AXI4_STRB_W-1:0] m_axi4_eth_hbm_wstrb,
  output logic [ETH_PC-1:0]                                      m_axi4_eth_hbm_wlast,
  output logic [ETH_PC-1:0]                                      m_axi4_eth_hbm_wvalid,
  input  logic [ETH_PC-1:0]                                      m_axi4_eth_hbm_wready,
  // Write response channel
  input  logic [ETH_PC-1:0][axi_if_eth_axi_pkg::AXI4_ID_W-1:0]   m_axi4_eth_hbm_bid,
  input  logic [ETH_PC-1:0][AXI4_RESP_W-1:0]                     m_axi4_eth_hbm_bresp,
  input  logic [ETH_PC-1:0]                                      m_axi4_eth_hbm_bvalid,
  output logic [ETH_PC-1:0]                                      m_axi4_eth_hbm_bready,
  // Read channel
  output logic [ETH_PC-1:0][axi_if_eth_axi_pkg::AXI4_ADD_W-1:0]  m_axi4_eth_hbm_araddr,
  output logic [ETH_PC-1:0][AXI4_LEN_W-1:0]                      m_axi4_eth_hbm_arlen,
  output logic [ETH_PC-1:0][AXI4_SIZE_W-1:0]                     m_axi4_eth_hbm_arsize,
  output logic [ETH_PC-1:0][AXI4_BURST_W-1:0]                    m_axi4_eth_hbm_arburst,
  output logic [ETH_PC-1:0]                                      m_axi4_eth_hbm_arvalid,
  input  logic [ETH_PC-1:0]                                      m_axi4_eth_hbm_arready,
  output logic [ETH_PC-1:0][axi_if_eth_axi_pkg::AXI4_ID_W-1:0]   m_axi4_eth_hbm_arid,     // unused
  input  logic [ETH_PC-1:0][axi_if_eth_axi_pkg::AXI4_DATA_W-1:0] m_axi4_eth_hbm_rdata,
  input  logic [ETH_PC-1:0]                                      m_axi4_eth_hbm_rlast,
  input  logic [ETH_PC-1:0]                                      m_axi4_eth_hbm_rvalid,
  output logic [ETH_PC-1:0]                                      m_axi4_eth_hbm_rready,
  input  logic [ETH_PC-1:0][axi_if_eth_axi_pkg::AXI4_ID_W-1:0]   m_axi4_eth_hbm_rid,      // unused
  input  logic [ETH_PC-1:0][AXI4_RESP_W-1:0]                     m_axi4_eth_hbm_rresp,    // unused
  // QSFP system interface ----------------------------------------------------
  // == TX
  output logic [QSFP_LANE_NB-1:0][MRMAC_AXIS_W-1:0  ]            qsfp_tx_tdata,
  output logic [QSFP_LANE_NB-1:0][MRMAC_TKEEP_W-1:0 ]            qsfp_tx_tkeep_user,
  output logic [QSFP_LANE_NB-1:0]                                qsfp_tx_tlast,
  output logic [QSFP_LANE_NB-1:0]                                qsfp_tx_tvalid,
  input  logic [QSFP_LANE_NB-1:0]                                qsfp_tx_tready,
  // == RX
  input  logic [QSFP_LANE_NB-1:0][MRMAC_AXIS_W-1:0  ]            qsfp_rx_tdata,
  input  logic [QSFP_LANE_NB-1:0][MRMAC_TKEEP_W-1:0 ]            qsfp_rx_tkeep_user,
  input  logic [QSFP_LANE_NB-1:0]                                qsfp_rx_tlast,
  input  logic [QSFP_LANE_NB-1:0]                                qsfp_rx_tvalid,
  // interrupt interface ------------------------------------------------------
  output logic                                                   interrupt_notify,
  output logic                                                   interrupt_read_request,
  // Giga transceivers interface ----------------------------------------------
  output logic [QSFP_LANE_NB-1:0]                                gt_reset_rx_datapath,
  output logic [QSFP_LANE_NB-1:0]                                gt_reset_tx_datapath,
  output logic [QSFP_LANE_NB-1:0]                                gt_reset_all,
  input  logic [QSFP_LANE_NB-1:0]                                gt_rx_reset_done,
  input  logic [QSFP_LANE_NB-1:0]                                gt_tx_reset_done,
  // line rate, should be set to zero
  output logic [7:0]                                             gt_line_rate,
  // loopback mode, will be applied to all channels
  //  * 000: disabled
  //  * 010: near end pma
  //  * 100: near end pcs
  output logic [2:0]                                             gt_loopback
);

  // ============================================================================================ --
  // Localparams
  // ============================================================================================ --
  localparam int CDC_SYNC_STAGES = 4;

  // ============================================================================================ --
  // Signals
  // ============================================================================================ --
  logic [$clog2(QSFP_LANE_NB)-1:0] line_sel;
  logic                            clear_interrupt_notify;
  logic                            clear_interrupt_rr;

  // ============================================================================================ //
  // Register file
  // ============================================================================================ //
  logic [NB_MAX_HPU-1:0][REG_DATA_W-1:0]   r_regf_hpu_ids;
  logic                 [REG_DATA_W-1:0]   r_request_notify_req_id;
  logic                 [REG_DATA_W-1:0]   r_request_notify_req_addr;
  logic                 [REG_DATA_W-1:0]   r_request_read_req_id;
  logic                 [REG_DATA_W-1:0]   r_request_read_addr;
  logic                 [REG_DATA_W-1:0]   r_request_req_id;
  logic                 [REG_DATA_W-1:0]   r_request_req_addr;
  logic                 [REG_DATA_W-1:0]   r_system_timeout_notify;
  logic                 [REG_DATA_W-1:0]   r_system_timeout_read_req;
  logic [    ETH_PC-1:0][2*REG_DATA_W-1:0] r_ct_mem_addr;
  // lane control
  logic                 [REG_DATA_W-1:0]   r_system_line;
  logic                 [REG_DATA_W-1:0]   r_reset_datapath;
  logic                 [REG_DATA_W-1:0]   r_reset_monitor;

  // Statistics using CDC structs ------------------------------------------------------------------
  mhdma_rst_cnt_t  rst_cnt_eth;
  mhdma_rst_cnt_t  rst_cnt_cfg;

  mhdma_cnt_t      cnt_eth;
  mhdma_cnt_t      cnt_cfg;

  // Transceivers ---------------------------------------------------------------------------------
  assign line_sel             = r_system_line[1:0];
  assign gt_loopback          = r_system_line[4:2];
  assign gt_line_rate         = r_system_line[13:5];

  assign gt_reset_all         = r_reset_datapath[3:0];
  assign gt_reset_tx_datapath = r_reset_datapath[7:4];
  assign gt_reset_rx_datapath = r_reset_datapath[11:8];

  assign r_reset_monitor[3:0]  = gt_tx_reset_done;
  assign r_reset_monitor[7:4]  = gt_rx_reset_done;
  assign r_reset_monitor[31:8] = '0;

  // updated registers ----------------------------------------------------------------------------
  // These registers are needed to ease timing
  logic [REG_DATA_W-1:0] request_notify_req_id_tmp;
  logic [REG_DATA_W-1:0] request_notify_req_addr_tmp;
  logic [REG_DATA_W-1:0] request_read_req_id_tmp;
  logic [REG_DATA_W-1:0] request_read_addr_tmp;
  logic [REG_DATA_W-1:0] reset_monitor_tmp;

  always_ff @(posedge clk_eth_cfg) begin
    request_notify_req_id_tmp   <= r_request_notify_req_id;
    request_notify_req_addr_tmp <= r_request_notify_req_addr;
    request_read_req_id_tmp     <= r_request_read_req_id;
    request_read_addr_tmp       <= r_request_read_addr;
    reset_monitor_tmp           <= r_reset_monitor;
  end

  // ============================================================================================ //
  // FSM value composition (from nested submodule stats after CDC)
  // ============================================================================================ //
  logic [REG_DATA_W-1:0] fsm_value_composed;
  assign fsm_value_composed = {11'b0, 2'b0, cnt_cfg.formatter.fsm_formatter,
                                      2'b0, cnt_cfg.master.fsm_read_req,
                                      2'b0, cnt_cfg.slave.fsm_cem,
                                      2'b0, cnt_cfg.slave.fsm_notify_rx,
                                      2'b0, cnt_cfg.master.fsm_notify};

  // ============================================================================================ //
  // Register file
  // ============================================================================================ //
  hpu_regif_core_eth_2in3 hpu_regif_core_eth_2in3 (
    // configuration interface -----------------------------------------------------------------------------------
    .clk                                                  (clk_eth_cfg                                           ),
    .s_rst_n                                              (resetn_eth_cfg                                        ),
    // axi4-lite -------------------------------------------------------------------------------------------------
    .s_axil_awaddr                                        (s_axil_dma_awaddr                                     ),
    .s_axil_awvalid                                       (s_axil_dma_awvalid                                    ),
    .s_axil_awready                                       (s_axil_dma_awready                                    ),
    .s_axil_wdata                                         (s_axil_dma_wdata                                      ),
    .s_axil_wvalid                                        (s_axil_dma_wvalid                                     ),
    .s_axil_wready                                        (s_axil_dma_wready                                     ),
    .s_axil_bresp                                         (s_axil_dma_bresp                                      ),
    .s_axil_bvalid                                        (s_axil_dma_bvalid                                     ),
    .s_axil_bready                                        (s_axil_dma_bready                                     ),
    .s_axil_araddr                                        (s_axil_dma_araddr                                     ),
    .s_axil_arvalid                                       (s_axil_dma_arvalid                                    ),
    .s_axil_arready                                       (s_axil_dma_arready                                    ),
    .s_axil_rdata                                         (s_axil_dma_rdata                                      ),
    .s_axil_rresp                                         (s_axil_dma_rresp                                      ),
    .s_axil_rvalid                                        (s_axil_dma_rvalid                                     ),
    .s_axil_rready                                        (s_axil_dma_rready                                     ),
    .r_axil_wdata                                         (/* UNUSED */                                          ),
    // HPU ids ---------------------------------------------------------------------------------------------------
    .r_mhdma_system_hpu_id_0                              (r_regf_hpu_ids[0]                                     ),
    .r_mhdma_system_hpu_id_1                              (r_regf_hpu_ids[1]                                     ),
    .r_mhdma_system_hpu_id_2                              (r_regf_hpu_ids[2]                                     ),
    .r_mhdma_system_hpu_id_3                              (r_regf_hpu_ids[3]                                     ),
    .r_mhdma_system_hpu_id_4                              (r_regf_hpu_ids[4]                                     ),
    .r_mhdma_system_hpu_id_5                              (r_regf_hpu_ids[5]                                     ),
    .r_mhdma_system_hpu_id_6                              (r_regf_hpu_ids[6]                                     ),
    .r_mhdma_system_hpu_id_7                              (r_regf_hpu_ids[7]                                     ),
    // HBM -------------------------------------------------------------------------------------------------------
    .r_mhdma_hbm_axi4_addr_2in3_ct_pc0_lsb                (r_ct_mem_addr[0][0*REG_DATA_W+:REG_DATA_W]            ),
    .r_mhdma_hbm_axi4_addr_2in3_ct_pc0_msb                (r_ct_mem_addr[0][1*REG_DATA_W+:REG_DATA_W]            ),
    .r_mhdma_hbm_axi4_addr_2in3_ct_pc1_lsb                (r_ct_mem_addr[1][0*REG_DATA_W+:REG_DATA_W]            ),
    .r_mhdma_hbm_axi4_addr_2in3_ct_pc1_msb                (r_ct_mem_addr[1][1*REG_DATA_W+:REG_DATA_W]            ),
    // RPU requests ----------------------------------------------------------------------------------------------
    .r_mhdma_request_req_id_wr_en                         (r_request_req_id_wr_en                                ),
    .r_mhdma_request_req_id                               (r_request_req_id                                      ),
    .r_mhdma_request_req_addr_wr_en                       (r_request_req_addr_wr_en                              ),
    .r_mhdma_request_req_addr                             (r_request_req_addr                                    ),
    // Updated from RTL only -------------------------------------------------------------------------------------
    .r_mhdma_request_notify_req_id                        (/* UNUSED - register output, only _upd/_rd_en used */ ),
    .r_mhdma_request_notify_req_id_upd                    (request_notify_req_id_tmp                             ),
    .r_mhdma_request_notify_req_id_rd_en                  (clear_interrupt_notify                                ),
    .r_mhdma_request_notify_req_addr                      (/* UNUSED - register output, only _upd/_rd_en used */ ),
    .r_mhdma_request_notify_req_addr_upd                  (request_notify_req_addr_tmp                           ),
    .r_mhdma_request_notify_req_addr_rd_en                (/* UNUSED */                                          ),
    .r_mhdma_request_read_request_req_id                  (/* UNUSED - register output, only _upd/_rd_en used */ ),
    .r_mhdma_request_read_request_req_id_upd              (request_read_req_id_tmp                               ),
    .r_mhdma_request_read_request_req_id_rd_en            (clear_interrupt_rr                                    ),
    .r_mhdma_request_read_request                         (/* UNUSED - register output, only _upd/_rd_en used */ ),
    .r_mhdma_request_read_request_upd                     (request_read_addr_tmp                                 ),
    .r_mhdma_request_read_request_rd_en                   (/* UNUSED */                                          ),
    // control ---------------------------------------------------------------------------------------------------
    .r_mhdma_system_lane                                  (r_system_line                                         ),
    .r_mhdma_reset_datapath                               (r_reset_datapath                                      ),
    .r_mhdma_reset_monitor                                (/* UNUSED - register output, only _upd used */        ),
    .r_mhdma_reset_monitor_upd                            (reset_monitor_tmp                                     ),
    .r_mhdma_lane_debug                                   (/* UNUSED */                                          ),
    .r_mhdma_system_timeout_notify                        (r_system_timeout_notify                               ),
    .r_mhdma_system_timeout_read_req                      (r_system_timeout_read_req                             ),
    // stats -----------------------------------------------------------------------------------------------------
    .r_mhdma_request_stat_notify                          (/* UNUSED - register output, only _upd/_rd_en used */ ),
    .r_mhdma_request_stat_notify_upd                      (cnt_cfg.master.cnt_notify                             ),
    .r_mhdma_request_stat_notify_rd_en                    (rst_cnt_cfg.master.cnt_notify                         ),
    .r_mhdma_request_stat_notify_ack                      (/* UNUSED - register output, only _upd/_rd_en used */ ),
    .r_mhdma_request_stat_notify_ack_upd                  (cnt_cfg.master.cnt_notify_ack                         ),
    .r_mhdma_request_stat_notify_ack_rd_en                (rst_cnt_cfg.master.cnt_notify_ack                     ),
    .r_mhdma_request_stat_notify_timeout                  (/* UNUSED - register output, only _upd/_rd_en used */ ),
    .r_mhdma_request_stat_notify_timeout_upd              (cnt_cfg.master.cnt_notify_timeout                     ),
    .r_mhdma_request_stat_notify_timeout_rd_en            (rst_cnt_cfg.master.cnt_timeout                        ),
    .r_mhdma_request_stat_notify_timeout_retry            (/* UNUSED - register output, only _upd/_rd_en used */ ),
    .r_mhdma_request_stat_notify_timeout_retry_upd        (cnt_cfg.master.cnt_notify_retries                     ),
    .r_mhdma_request_stat_notify_timeout_retry_rd_en      (rst_cnt_cfg.master.cnt_notify_retry                   ),
    .r_mhdma_request_stat_read_req_timeout_retry          (/* UNUSED - register output, only _upd/_rd_en used */ ),
    .r_mhdma_request_stat_read_req_timeout_retry_upd      (cnt_cfg.master.cnt_read_req_retries                   ),
    .r_mhdma_request_stat_read_req_timeout_retry_rd_en    (rst_cnt_cfg.master.cnt_read_req_retry                 ),
    .r_mhdma_request_stat_nb_nack_received                (/* UNUSED - register output, only _upd/_rd_en used */ ),
    .r_mhdma_request_stat_nb_nack_received_upd            (cnt_cfg.decoder.cnt_nack_received                     ),
    .r_mhdma_request_stat_nb_nack_received_rd_en          (rst_cnt_cfg.decoder.cnt_nack_received                 ),
    .r_mhdma_request_stat_nb_notify_received              (/* UNUSED - register output, only _upd/_rd_en used */ ),
    .r_mhdma_request_stat_nb_notify_received_upd          (cnt_cfg.decoder.cnt_notify_received                   ),
    .r_mhdma_request_stat_nb_notify_received_rd_en        (rst_cnt_cfg.decoder.cnt_notify_received               ),
    .r_mhdma_request_stat_nb_read_req_received            (/* UNUSED - register output, only _upd/_rd_en used */ ),
    .r_mhdma_request_stat_nb_read_req_received_upd        (cnt_cfg.decoder.cnt_read_req_received                 ),
    .r_mhdma_request_stat_nb_read_req_received_rd_en      (rst_cnt_cfg.decoder.cnt_read_req_received             ),
    .r_mhdma_request_stat_nb_ce_received                  (/* UNUSED - register output, only _upd/_rd_en used */ ),
    .r_mhdma_request_stat_nb_ce_received_upd              (cnt_cfg.decoder.cnt_ce_received                       ),
    .r_mhdma_request_stat_nb_ce_received_rd_en            (rst_cnt_cfg.decoder.cnt_ce_received                   ),
    .r_mhdma_request_stat_nb_ce_words_received            (/* UNUSED - register output, only _upd/_rd_en used */ ),
    .r_mhdma_request_stat_nb_ce_words_received_upd        (cnt_cfg.master.nb_ce_words_received                   ),
    .r_mhdma_request_stat_nb_ce_words_received_rd_en      (rst_cnt_cfg.master.nb_ce_words_received               ),
    .r_mhdma_request_stat_nb_read_to_hbm                  (/* UNUSED - register output, only _upd/_rd_en used */ ),
    .r_mhdma_request_stat_nb_read_to_hbm_upd              (cnt_cfg.slave.nb_read_to_hbm                          ),
    .r_mhdma_request_stat_nb_read_to_hbm_rd_en            (rst_cnt_cfg.slave.nb_read_to_hbm                      ),
    .r_mhdma_request_stat_nb_words_received_pc_pc0        (/* UNUSED - register output, only _upd/_rd_en used */ ),
    .r_mhdma_request_stat_nb_words_received_pc_pc0_upd    (cnt_cfg.slave.nb_words_received_pc[0]                 ),
    .r_mhdma_request_stat_nb_words_received_pc_pc0_rd_en  (rst_cnt_cfg.slave.nb_words_received_pc[0]             ),
    .r_mhdma_request_stat_nb_words_received_pc_pc1        (/* UNUSED - register output, only _upd/_rd_en used */ ),
    .r_mhdma_request_stat_nb_words_received_pc_pc1_upd    (cnt_cfg.slave.nb_words_received_pc[1]                 ),
    .r_mhdma_request_stat_nb_words_received_pc_pc1_rd_en  (rst_cnt_cfg.slave.nb_words_received_pc[1]             ),
    .r_mhdma_request_stat_cnt_nb_write_complete           (/* UNUSED - register output, only _upd used */        ),
    .r_mhdma_request_stat_cnt_nb_write_complete_upd       (cnt_cfg.master.nb_write_complete_cnt                  ),
    // timing
    .r_mhdma_request_stat_t_notify_to_ack                 (/* UNUSED - register output, only _upd used */        ),
    .r_mhdma_request_stat_t_notify_to_ack_upd             (cnt_cfg.master.t_notify_to_ack                        ),
    .r_mhdma_request_stat_t_rr_to_ce_received             (/* UNUSED - register output, only _upd used */        ),
    .r_mhdma_request_stat_t_rr_to_ce_received_upd         (cnt_cfg.master.t_rr_to_ce_received                    ),
    .r_mhdma_request_stat_t_ce_first_to_last_pkt          (/* UNUSED - register output, only _upd used */        ),
    .r_mhdma_request_stat_t_ce_first_to_last_pkt_upd      (cnt_cfg.decoder.t_ce_first_to_last_pkt                ),
    .r_mhdma_request_stat_t_rr_wait_words_pc_pc0          (/* UNUSED - register output, only _upd used */        ),
    .r_mhdma_request_stat_t_rr_wait_words_pc_pc0_upd      (cnt_cfg.slave.t_rr_wait_words_pc[0]                   ),
    .r_mhdma_request_stat_t_rr_wait_words_pc_pc1          (/* UNUSED - register output, only _upd used */        ),
    .r_mhdma_request_stat_t_rr_wait_words_pc_pc1_upd      (cnt_cfg.slave.t_rr_wait_words_pc[1]                   ),
    // registers
    .r_mhdma_system_fsm_value                             (/* UNUSED - register output, only _upd used */        ),
    .r_mhdma_system_fsm_value_upd                         (fsm_value_composed                                    ),
    .r_mhdma_request_stat_physical_addr_pc0_lsb           (/* UNUSED - register output, only _upd used */        ),
    .r_mhdma_request_stat_physical_addr_pc0_lsb_upd       (cnt_cfg.slave.rr_phy_addr[0][REG_DATA_W-1:0]          ),
    .r_mhdma_request_stat_physical_addr_pc0_msb           (/* UNUSED - register output, only _upd used */        ),
    .r_mhdma_request_stat_physical_addr_pc0_msb_upd       (cnt_cfg.slave.rr_phy_addr[0][2*REG_DATA_W-1:REG_DATA_W]),
    .r_mhdma_request_stat_physical_addr_pc1_lsb           (/* UNUSED - register output, only _upd used */        ),
    .r_mhdma_request_stat_physical_addr_pc1_lsb_upd       (cnt_cfg.slave.rr_phy_addr[1][REG_DATA_W-1:0]          ),
    .r_mhdma_request_stat_physical_addr_pc1_msb           (/* UNUSED - register output, only _upd used */        ),
    .r_mhdma_request_stat_physical_addr_pc1_msb_upd       (cnt_cfg.slave.rr_phy_addr[1][2*REG_DATA_W-1:REG_DATA_W]),
    .r_mhdma_system_errors                                (/* UNUSED - register output, only _upd/_rd_en used */ ),
    .r_mhdma_system_errors_upd                            (cnt_cfg.mhdma_errors                                  ),
    .r_mhdma_system_errors_rd_en                          (rst_cnt_cfg.mhdma_errors                              )
  );

  // ============================================================================================ //
  // Request handling logic
  // ============================================================================================ //
  logic [1:0] received_req;
  logic       request_consumed;

  // received_req signals lower module that
  always_ff @(posedge clk_eth_cfg) begin
    if (~resetn_eth_cfg) begin
      received_req <= '0;
    end else begin
      if (r_request_req_id_wr_en)   received_req[0] <= 1'b1;
      if (r_request_req_addr_wr_en) received_req[1] <= 1'b1;
      if (request_consumed)         received_req    <= '0;
    end
  end

  // ============================================================================================ //
  // CDC
  // ============================================================================================ //
  // CDC: Reset signals (CFG -> ETH)
  localparam int RST_CNT_W = $bits(mhdma_rst_cnt_t);
  logic [RST_CNT_W-1:0] rst_cnt_cfg_flat;
  logic [RST_CNT_W-1:0] rst_cnt_eth_flat;

  assign rst_cnt_cfg_flat = rst_cnt_cfg;
  assign rst_cnt_eth      = mhdma_rst_cnt_t'(rst_cnt_eth_flat);

  for (genvar i = 0; i < RST_CNT_W; i++) begin : gen_cdc_rst_cnt
    xpm_cdc_single_wrapper #(
      .CDC_SYNC_STAGES (CDC_SYNC_STAGES),
      .SRC_INPUT_REG   (1              )
    ) cdc_rst_cnt (
      .src_clk  (clk_eth_cfg        ),
      .dest_clk (clk_eth_mrmac      ),
      .src_in   (rst_cnt_cfg_flat[i] ),
      .dest_out (rst_cnt_eth_flat[i] )
    );
  end

  // CDC: Counter values (ETH -> CFG)
  xpm_cdc_handshake_wrapper #(
    .WIDTH           ($bits(mhdma_cnt_t)),
    .CDC_SYNC_STAGES (CDC_SYNC_STAGES   )
  ) cdc_cnt (
    .src_clk   (clk_eth_mrmac  ),
    .src_rst_n (resetn_eth_mrmac),
    .dest_clk  (clk_eth_cfg    ),
    .src_in    (cnt_eth        ),
    .dest_out  (cnt_cfg        )
  );

  // ============================================================================================ //
  // Multi-HPU-DMA bridge
  // ============================================================================================ //
  logic [MRMAC_AXIS_W-1:0 ] axis_rx_tdata;
  logic [MRMAC_TKEEP_W-1:0] axis_rx_tkeep_user;
  logic                     axis_rx_tlast;
  logic                     axis_rx_tvalid;

  logic [MRMAC_AXIS_W-1:0 ] axis_tx_tdata;
  logic [MRMAC_TKEEP_W-1:0] axis_tx_tkeep_user;
  logic                     axis_tx_tlast;
  logic                     axis_tx_tvalid;
  logic                     axis_tx_tready;

  mhdma_bridge mhdma_bridge (
    .clk_cfg                        (clk_eth_cfg                                                  ),
    .resetn_cfg                     (resetn_eth_cfg                                               ),
    .clk_mrmac                      (clk_eth_mrmac                                                ),
    .resetn_mrmac                   (resetn_eth_mrmac                                             ),
    // axi4-full for each ETH_PC ------------------------------------------------------------------
    .m_axi4_arid                    (m_axi4_eth_hbm_arid                                          ),
    .m_axi4_araddr                  (m_axi4_eth_hbm_araddr                                        ),
    .m_axi4_arlen                   (m_axi4_eth_hbm_arlen                                         ),
    .m_axi4_arsize                  (m_axi4_eth_hbm_arsize                                        ),
    .m_axi4_arburst                 (m_axi4_eth_hbm_arburst                                       ),
    .m_axi4_arvalid                 (m_axi4_eth_hbm_arvalid                                       ),
    .m_axi4_arready                 (m_axi4_eth_hbm_arready                                       ),
    .m_axi4_rid                     (m_axi4_eth_hbm_rid                                           ),
    .m_axi4_rdata                   (m_axi4_eth_hbm_rdata                                         ),
    .m_axi4_rresp                   (m_axi4_eth_hbm_rresp                                         ),
    .m_axi4_rlast                   (m_axi4_eth_hbm_rlast                                         ),
    .m_axi4_rvalid                  (m_axi4_eth_hbm_rvalid                                        ),
    .m_axi4_rready                  (m_axi4_eth_hbm_rready                                        ),
    .m_axi4_awid                    (m_axi4_eth_hbm_awid                                          ),
    .m_axi4_awaddr                  (m_axi4_eth_hbm_awaddr                                        ),
    .m_axi4_awlen                   (m_axi4_eth_hbm_awlen                                         ),
    .m_axi4_awsize                  (m_axi4_eth_hbm_awsize                                        ),
    .m_axi4_awburst                 (m_axi4_eth_hbm_awburst                                       ),
    .m_axi4_awvalid                 (m_axi4_eth_hbm_awvalid                                       ),
    .m_axi4_awready                 (m_axi4_eth_hbm_awready                                       ),
    .m_axi4_wdata                   (m_axi4_eth_hbm_wdata                                         ),
    .m_axi4_wstrb                   (m_axi4_eth_hbm_wstrb                                         ),
    .m_axi4_wlast                   (m_axi4_eth_hbm_wlast                                         ),
    .m_axi4_wvalid                  (m_axi4_eth_hbm_wvalid                                        ),
    .m_axi4_wready                  (m_axi4_eth_hbm_wready                                        ),
    .m_axi4_bid                     (m_axi4_eth_hbm_bid                                           ),
    .m_axi4_bresp                   (m_axi4_eth_hbm_bresp                                         ),
    .m_axi4_bvalid                  (m_axi4_eth_hbm_bvalid                                        ),
    .m_axi4_bready                  (m_axi4_eth_hbm_bready                                        ),
    // Register interface -------------------------------------------------------------------------
    .regf_hpu_ids                   (r_regf_hpu_ids                                               ),
    .regf_ct_mem_addr               (r_ct_mem_addr                                                ),
    .regf_req_id                    (r_request_req_id                                             ),
    .regf_req_addr                  (r_request_req_addr                                           ),
    .regf_notify_req_id             (r_request_notify_req_id                                      ),
    .regf_notify_req_addr           (r_request_notify_req_addr                                    ),
    .regf_read_req_id               (r_request_read_req_id                                        ),
    .regf_read_addr                 (r_request_read_addr                                          ),
    .regf_timeout_duration_notify   (r_system_timeout_notify                                      ),
    .regf_timeout_duration_read_req (r_system_timeout_read_req                                    ),
    // interruptions and control ------------------------------------------------------------------
    .received_req                   (&received_req                                                ),
    .request_consumed               (request_consumed                                             ),
    .clear_interrupt_notify         (clear_interrupt_notify                                       ),
    .clear_interrupt_rr             (clear_interrupt_rr                                           ),
    .interrupt_notify               (interrupt_notify                                             ),
    .interrupt_read_request         (interrupt_read_request                                       ),
    // statistics ---------------------------------------------------------------------------------
    .stat_cnt                       (cnt_eth                                                      ),
    .rst_cnt                        (rst_cnt_eth                                                  ),
    // QSFP interface one lane --------------------------------------------------------------------
    // tx
    .qsfp_tx_tdata                  (axis_tx_tdata                                                ),
    .qsfp_tx_tkeep_user             (axis_tx_tkeep_user                                           ),
    .qsfp_tx_tlast                  (axis_tx_tlast                                                ),
    .qsfp_tx_tvalid                 (axis_tx_tvalid                                               ),
    .qsfp_tx_tready                 (axis_tx_tready                                               ),
    // rx
    .qsfp_rx_tdata                  (axis_rx_tdata                                                ),
    .qsfp_rx_tkeep_user             (axis_rx_tkeep_user                                           ),
    .qsfp_rx_tlast                  (axis_rx_tlast                                                ),
    .qsfp_rx_tvalid                 (axis_rx_tvalid                                               )
  );

  // ============================================================================================ //
  // AXI4-stream lane switch
  // ============================================================================================ //
  // Rx Link
  assign axis_rx_tdata      = qsfp_rx_tdata[line_sel];
  assign axis_rx_tkeep_user = qsfp_rx_tkeep_user[line_sel];
  assign axis_rx_tlast      = qsfp_rx_tlast[line_sel];
  assign axis_rx_tvalid     = qsfp_rx_tvalid[line_sel];

  // TX link
  assign axis_tx_tready = qsfp_tx_tready[line_sel];

  generate
    for (genvar i = 0; i < QSFP_LANE_NB; i++) begin : gen_tx_lane_switch
      assign qsfp_tx_tdata[i]      = (line_sel == i) ? axis_tx_tdata      : '0;
      assign qsfp_tx_tkeep_user[i] = (line_sel == i) ? axis_tx_tkeep_user : '0;
      assign qsfp_tx_tlast[i]      = (line_sel == i) ? axis_tx_tlast      : '0;
      assign qsfp_tx_tvalid[i]     = (line_sel == i) ? axis_tx_tvalid     : '0;
    end
  endgenerate

endmodule
