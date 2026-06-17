// ================================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ------------------------------------------------------------------------------------------------
// Description  : Multi-HPU DMA (MHDMA) top-level module
//
// Orchestrates data movement between multiple HPUs over Ethernet (QSFP) and HBM memory.
// Integrates the register file, the bridge (decoder + master + formatter + slave),
// clock-domain crossing (CFG <-> ETH), and a QSFP lane multiplexer.
//
// Clock domains:
//   - clk_mhdma_cfg : slow configuration clock (AXI4-Lite, register file, request handling)
//   - clk_mhdma     : fast Ethernet clock (QSFP datapath & HBM AXI4 interfaces)
// clk_mhdma's frequency depends on MRMAC axi interface. Here we chose to be in "independent
// Non-Segmented 25GE 64 bit".
//
// Interfaces:
//   - AXI4-Lite slave  : register file access from host / RPU
//   - AXI4-Full master : single NMU port for HBM read/write (all ETH_PC PCs share one port)
//   - AXI-Stream       : QSFP TX/RX per lane (QSFP_LANE_NB lanes, one selected via line_sel)
//   - Interrupts       : notify and read_request to host
//   - GT control       : transceiver reset and loopback configuration
//
// Assumptions / Limitations:
//  - Only one QSFP lane is active at a time, selected by r_system_lane[1:0] (regfile)
//  - Request from host requires two consecutive register writes (any order)
//  - Interrupt will be cleared on *_req_id register read
//  - CDC for stat counters uses handshake; counters may lag by a few cfg-clock cycles
//  - Top module cannot use ETH_PC != 2 because of regfile. for >= 4 XPM CDC fifos will overflow
//
// ================================================================================================

module multi_hpu_dma
  import mhdma_pkg::*;                                             // multi-hpu-dma
  import axi_if_shell_axil_pkg::*;                                 // axi4-lite + REG_DATA_W
  import axi_if_common_param_pkg::*;                               // general axi4
  import hpu_regif_core_mhdma_2in3_pkg::*;                         // ethernet regif
(
  // Ethernet configuration interface -------------------------------------------------------------
  input logic                                                      clk_mhdma_cfg,
  input logic                                                      resetn_mhdma_cfg,
  // Ethernet fast clock interface ----------------------------------------------------------------
  input logic                                                      clk_mhdma,
  input logic                                                      resetn_mhdma,
  // Axi4-lite slave interface for regfile --------------------------------------------------------
  input  logic [AXIL_ADD_W-1:0]                                    s_axil_mhdma_awaddr,
  input  logic                                                     s_axil_mhdma_awvalid,
  output logic                                                     s_axil_mhdma_awready,
  input  logic [AXIL_DATA_W-1:0]                                   s_axil_mhdma_wdata,
  input  logic [AXIL_DATA_BYTES-1:0]                               s_axil_mhdma_wstrb,        // unused
  input  logic                                                     s_axil_mhdma_wvalid,
  output logic                                                     s_axil_mhdma_wready,
  output logic [1:0]                                               s_axil_mhdma_bresp,
  output logic                                                     s_axil_mhdma_bvalid,
  input  logic                                                     s_axil_mhdma_bready,
  input  logic [AXIL_ADD_W-1:0]                                    s_axil_mhdma_araddr,
  input  logic                                                     s_axil_mhdma_arvalid,
  output logic                                                     s_axil_mhdma_arready,
  output logic [AXIL_DATA_W-1:0]                                   s_axil_mhdma_rdata,
  output logic [1:0]                                               s_axil_mhdma_rresp,
  output logic                                                     s_axil_mhdma_rvalid,
  input  logic                                                     s_axil_mhdma_rready,
  // Axi4-full HBM interface (single NMU) ---------------------------------------------------------
  // Write channel
  output logic [axi_if_mhdma_axi_pkg::AXI4_ID_W-1:0]                m_axi4_mhdma_hbm_awid,
  output logic [axi_if_mhdma_axi_pkg::AXI4_ADD_W-1:0]               m_axi4_mhdma_hbm_awaddr,
  output logic [AXI4_LEN_W-1:0]                                     m_axi4_mhdma_hbm_awlen,
  output logic [AXI4_SIZE_W-1:0]                                    m_axi4_mhdma_hbm_awsize,
  output logic [AXI4_BURST_W-1:0]                                   m_axi4_mhdma_hbm_awburst,
  output logic                                                      m_axi4_mhdma_hbm_awvalid,
  input  logic                                                      m_axi4_mhdma_hbm_awready,
  output logic [axi_if_mhdma_axi_pkg::AXI4_DATA_W-1:0]              m_axi4_mhdma_hbm_wdata,
  output logic [axi_if_mhdma_axi_pkg::AXI4_STRB_W-1:0]              m_axi4_mhdma_hbm_wstrb,
  output logic                                                      m_axi4_mhdma_hbm_wlast,
  output logic                                                      m_axi4_mhdma_hbm_wvalid,
  input  logic                                                      m_axi4_mhdma_hbm_wready,
  // Write response channel
  input  logic [axi_if_mhdma_axi_pkg::AXI4_ID_W-1:0]                m_axi4_mhdma_hbm_bid,
  input  logic [AXI4_RESP_W-1:0]                                    m_axi4_mhdma_hbm_bresp,
  input  logic                                                      m_axi4_mhdma_hbm_bvalid,
  output logic                                                      m_axi4_mhdma_hbm_bready,
  // Read channel
  output logic [axi_if_mhdma_axi_pkg::AXI4_ADD_W-1:0]               m_axi4_mhdma_hbm_araddr,
  output logic [AXI4_LEN_W-1:0]                                     m_axi4_mhdma_hbm_arlen,
  output logic [AXI4_SIZE_W-1:0]                                    m_axi4_mhdma_hbm_arsize,
  output logic [AXI4_BURST_W-1:0]                                   m_axi4_mhdma_hbm_arburst,
  output logic                                                      m_axi4_mhdma_hbm_arvalid,
  input  logic                                                      m_axi4_mhdma_hbm_arready,
  output logic [axi_if_mhdma_axi_pkg::AXI4_ID_W-1:0]                m_axi4_mhdma_hbm_arid,
  input  logic [axi_if_mhdma_axi_pkg::AXI4_DATA_W-1:0]              m_axi4_mhdma_hbm_rdata,
  input  logic                                                      m_axi4_mhdma_hbm_rlast,
  input  logic                                                      m_axi4_mhdma_hbm_rvalid,
  output logic                                                      m_axi4_mhdma_hbm_rready,
  input  logic [axi_if_mhdma_axi_pkg::AXI4_ID_W-1:0]                m_axi4_mhdma_hbm_rid,
  input  logic [AXI4_RESP_W-1:0]                                    m_axi4_mhdma_hbm_rresp,
  // QSFP system interface ------------------------------------------------------------------------
  // == TX
  output logic [QSFP_LANE_NB-1:0][MRMAC_AXIS_W-1:0  ]              qsfp_tx_tdata,
  output logic [QSFP_LANE_NB-1:0][MRMAC_TKEEP_W-1:0 ]              qsfp_tx_tkeep_user,
  output logic [QSFP_LANE_NB-1:0]                                  qsfp_tx_tlast,
  output logic [QSFP_LANE_NB-1:0]                                  qsfp_tx_tvalid,
  input  logic [QSFP_LANE_NB-1:0]                                  qsfp_tx_tready,
  // == RX
  input  logic [QSFP_LANE_NB-1:0][MRMAC_AXIS_W-1:0  ]              qsfp_rx_tdata,
  input  logic [QSFP_LANE_NB-1:0][MRMAC_TKEEP_W-1:0 ]              qsfp_rx_tkeep_user,
  input  logic [QSFP_LANE_NB-1:0]                                  qsfp_rx_tlast,
  input  logic [QSFP_LANE_NB-1:0]                                  qsfp_rx_tvalid,
  // interrupt interface --------------------------------------------------------------------------
  output logic                                                     interrupt_notify,
  output logic                                                     interrupt_read_request,
  // Giga transceivers interface ------------------------------------------------------------------
  output logic [QSFP_LANE_NB-1:0]                                  gt_reset_rx_datapath,
  output logic [QSFP_LANE_NB-1:0]                                  gt_reset_tx_datapath,
  output logic [QSFP_LANE_NB-1:0]                                  gt_reset_all,
  input  logic [QSFP_LANE_NB-1:0]                                  gt_rx_reset_done,
  input  logic [QSFP_LANE_NB-1:0]                                  gt_tx_reset_done,
  // line rate, should be set to zero
  output logic [7:0]                                               gt_line_rate,
  // loopback mode, will be applied to all channels
  //  * 000: disabled
  //  * 010: near end pma
  //  * 100: near end pcs
  output logic [2:0]                                               gt_loopback
);

  // ============================================================================================ //
  // Localparams
  // ============================================================================================ //
  localparam int CDC_SYNC_STAGES = 4;

  // ============================================================================================ //
  // Signals
  // ============================================================================================ //
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
  mhdma_system_retry_max_t                 r_system_retry_max;
  logic [    ETH_PC-1:0][2*REG_DATA_W-1:0] r_ct_mem_addr;
  logic [    ETH_PC-1:0][2*REG_DATA_W-1:0] r_ct_mem_addr_regf;
  // lane control
  logic                 [REG_DATA_W-1:0]   r_system_lane;
  logic                 [REG_DATA_W-1:0]   r_reset_datapath;
  logic                 [REG_DATA_W-1:0]   r_reset_monitor;

  // Statistics using CDC structs ------------------------------------------------------------------
  mhdma_stat_rst_t    stat_rst_mhdma;
  mhdma_stat_rst_t    stat_rst_cfg;

  mhdma_stat_to_cfg_t stat_mhdma;
  mhdma_stat_to_cfg_t stat_cfg;

  // cfg-domain master errors (overflow detection) -----------------------------------------------
  master_error_cfg_t master_error_cfg;

  // Merge cfg-domain master errors with CDC'd mhdma-domain errors (all on cfg clock)
  logic [REG_DATA_W-1:0] mhdma_errors_cfg_merged;
  mhdma_error_all_t      mhdma_error_all;

  // Transceivers ---------------------------------------------------------------------------------
  assign line_sel             = r_system_lane[1:0];
  assign gt_loopback          = r_system_lane[4:2];
  assign gt_line_rate         = r_system_lane[13:5];

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

  always_ff @(posedge clk_mhdma_cfg) begin
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
  assign fsm_value_composed = {7'b0, 2'b0, stat_cfg.formatter.fsm_formatter,
                                     2'b0, stat_cfg.slave.fsm_cem,
                                     2'b0, stat_cfg.slave.fsm_notify_rx,
                                     2'b0, stat_cfg.master.fsm_burst,
                                     2'b0, stat_cfg.master.fsm_read_req,
                                     2'b0, stat_cfg.master.fsm_notify};

  // ============================================================================================ //
  // Regfile PC1 intermediates (regfile always has PC0+PC1 ports; tie off when ETH_PC==1)
  // ============================================================================================ //
  for (genvar i = 0; i < ETH_PC; i++) begin : gen_ct_mem_addr
    assign r_ct_mem_addr[i] = r_ct_mem_addr_regf[i];
  end

  logic [REG_DATA_W-1:0]   regf_nb_words_rx_pc1;
  logic                    regf_rst_nb_words_rx_pc1;
  logic [REG_DATA_W-1:0]   regf_t_rr_wait_pc1;
  logic [2*REG_DATA_W-1:0] regf_rr_phy_addr_pc1;

  generate if (ETH_PC > 1) begin : gen_pc1_regf
    assign regf_nb_words_rx_pc1     = stat_cfg.slave.nb_words_received_pc[1];
    assign stat_rst_cfg.slave.nb_words_received_pc[1] = regf_rst_nb_words_rx_pc1;
    assign regf_t_rr_wait_pc1       = stat_cfg.slave.t_rr_wait_words_pc[1];
    assign regf_rr_phy_addr_pc1     = stat_cfg.slave.rr_phy_addr[1];
  end else begin : gen_pc1_regf_tieoff
    assign regf_nb_words_rx_pc1     = 'h0;
    // regf_rst_nb_words_rx_pc1 driven by regfile _rd_en output, unused when ETH_PC==1
    assign regf_t_rr_wait_pc1       = 'h0;
    assign regf_rr_phy_addr_pc1     = 'h0;
  end endgenerate

  // ============================================================================================ //
  // Register file
  // ============================================================================================ //
  logic r_request_req_id_wr_en;
  logic r_request_req_addr_wr_en;

  hpu_regif_core_mhdma_2in3 hpu_regif_core_mhdma_2in3 (
    // configuration interface -----------------------------------------------------------------------------------
    .clk                                                  (clk_mhdma_cfg                                         ),
    .s_rst_n                                              (resetn_mhdma_cfg                                      ),
    // axi4-lite -------------------------------------------------------------------------------------------------
    .s_axil_awaddr                                        (s_axil_mhdma_awaddr                                   ),
    .s_axil_awvalid                                       (s_axil_mhdma_awvalid                                  ),
    .s_axil_awready                                       (s_axil_mhdma_awready                                  ),
    .s_axil_wdata                                         (s_axil_mhdma_wdata                                    ),
    .s_axil_wvalid                                        (s_axil_mhdma_wvalid                                   ),
    .s_axil_wready                                        (s_axil_mhdma_wready                                   ),
    .s_axil_bresp                                         (s_axil_mhdma_bresp                                    ),
    .s_axil_bvalid                                        (s_axil_mhdma_bvalid                                   ),
    .s_axil_bready                                        (s_axil_mhdma_bready                                   ),
    .s_axil_araddr                                        (s_axil_mhdma_araddr                                   ),
    .s_axil_arvalid                                       (s_axil_mhdma_arvalid                                  ),
    .s_axil_arready                                       (s_axil_mhdma_arready                                  ),
    .s_axil_rdata                                         (s_axil_mhdma_rdata                                    ),
    .s_axil_rresp                                         (s_axil_mhdma_rresp                                    ),
    .s_axil_rvalid                                        (s_axil_mhdma_rvalid                                   ),
    .s_axil_rready                                        (s_axil_mhdma_rready                                   ),
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
    .r_mhdma_hbm_axi4_addr_2in3_ct_pc0_lsb                (r_ct_mem_addr_regf[0][0*REG_DATA_W+:REG_DATA_W]       ),
    .r_mhdma_hbm_axi4_addr_2in3_ct_pc0_msb                (r_ct_mem_addr_regf[0][1*REG_DATA_W+:REG_DATA_W]       ),
    .r_mhdma_hbm_axi4_addr_2in3_ct_pc1_lsb                (r_ct_mem_addr_regf[1][0*REG_DATA_W+:REG_DATA_W]       ),
    .r_mhdma_hbm_axi4_addr_2in3_ct_pc1_msb                (r_ct_mem_addr_regf[1][1*REG_DATA_W+:REG_DATA_W]       ),
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
    .r_mhdma_system_lane                                  (r_system_lane                                         ),
    .r_mhdma_reset_datapath                               (r_reset_datapath                                      ),
    .r_mhdma_reset_monitor                                (/* UNUSED - register output, only _upd used */        ),
    .r_mhdma_reset_monitor_upd                            (reset_monitor_tmp                                     ),
    .r_mhdma_lane_debug                                   (/* UNUSED */                                          ),
    .r_mhdma_system_timeout_notify                        (r_system_timeout_notify                               ),
    .r_mhdma_system_timeout_read_req                      (r_system_timeout_read_req                             ),
    .r_mhdma_system_retry_max                             (r_system_retry_max                                    ),
    // stats -----------------------------------------------------------------------------------------------------
    .r_mhdma_request_stat_notify                          (/* UNUSED - register output, only _upd/_rd_en used */ ),
    .r_mhdma_request_stat_notify_upd                      (stat_cfg.master.cnt_notify                            ),
    .r_mhdma_request_stat_notify_rd_en                    (stat_rst_cfg.master.cnt_notify                        ),
    .r_mhdma_request_stat_notify_ack                      (/* UNUSED - register output, only _upd/_rd_en used */ ),
    .r_mhdma_request_stat_notify_ack_upd                  (stat_cfg.master.cnt_notify_ack                        ),
    .r_mhdma_request_stat_notify_ack_rd_en                (stat_rst_cfg.master.cnt_notify_ack                    ),
    .r_mhdma_request_stat_cur_notify_to_ack               (/* UNUSED - register output, only _upd/_rd_en used */ ),
    .r_mhdma_request_stat_cur_notify_to_ack_upd           (stat_cfg.master.t_cur_notify_to_ack                   ),
    .r_mhdma_request_stat_notify_timeout_retry            (/* UNUSED - register output, only _upd/_rd_en used */ ),
    .r_mhdma_request_stat_notify_timeout_retry_upd        (stat_cfg.master.cnt_notify_retries                    ),
    .r_mhdma_request_stat_notify_timeout_retry_rd_en      (stat_rst_cfg.master.cnt_notify_retry                  ),
    .r_mhdma_request_stat_read_req_timeout_retry          (/* UNUSED - register output, only _upd/_rd_en used */ ),
    .r_mhdma_request_stat_read_req_timeout_retry_upd      (stat_cfg.master.cnt_read_req_timeout_retries          ),
    .r_mhdma_request_stat_read_req_timeout_retry_rd_en    (stat_rst_cfg.master.cnt_read_req_timeout_retry        ),
    .r_mhdma_request_stat_read_req_seq_num_retry          (/* UNUSED - register output, only _upd/_rd_en used */ ),
    .r_mhdma_request_stat_read_req_seq_num_retry_upd      (stat_cfg.master.cnt_read_req_seq_num_retries          ),
    .r_mhdma_request_stat_read_req_seq_num_retry_rd_en    (stat_rst_cfg.master.cnt_read_req_seq_num_retry        ),
    .r_mhdma_request_stat_nb_nack_received                (/* UNUSED - register output, only _upd/_rd_en used */ ),
    .r_mhdma_request_stat_nb_nack_received_upd            (stat_cfg.decoder.cnt_nack_received                    ),
    .r_mhdma_request_stat_nb_nack_received_rd_en          (stat_rst_cfg.decoder.cnt_nack_received                ),
    .r_mhdma_request_stat_nb_notify_received              (/* UNUSED - register output, only _upd/_rd_en used */ ),
    .r_mhdma_request_stat_nb_notify_received_upd          (stat_cfg.decoder.cnt_notify_received                  ),
    .r_mhdma_request_stat_nb_notify_received_rd_en        (stat_rst_cfg.decoder.cnt_notify_received              ),
    .r_mhdma_request_stat_nb_read_req_received            (/* UNUSED - register output, only _upd/_rd_en used */ ),
    .r_mhdma_request_stat_nb_read_req_received_upd        (stat_cfg.decoder.cnt_read_req_received                ),
    .r_mhdma_request_stat_nb_read_req_received_rd_en      (stat_rst_cfg.decoder.cnt_read_req_received            ),
    .r_mhdma_request_stat_nb_ce_received                  (/* UNUSED - register output, only _upd/_rd_en used */ ),
    .r_mhdma_request_stat_nb_ce_received_upd              (stat_cfg.decoder.cnt_ce_received                      ),
    .r_mhdma_request_stat_nb_ce_received_rd_en            (stat_rst_cfg.decoder.cnt_ce_received                  ),
    .r_mhdma_request_stat_nb_ce_words_received            (/* UNUSED - register output, only _upd/_rd_en used */ ),
    .r_mhdma_request_stat_nb_ce_words_received_upd        (stat_cfg.master.nb_ce_words_received                  ),
    .r_mhdma_request_stat_nb_ce_words_received_rd_en      (stat_rst_cfg.master.nb_ce_words_received              ),
    .r_mhdma_request_stat_nb_read_to_hbm                  (/* UNUSED - register output, only _upd/_rd_en used */ ),
    .r_mhdma_request_stat_nb_read_to_hbm_upd              (stat_cfg.slave.nb_read_to_hbm                         ),
    .r_mhdma_request_stat_nb_read_to_hbm_rd_en            (stat_rst_cfg.slave.nb_read_to_hbm                     ),
    .r_mhdma_request_stat_nb_words_received_pc_pc0        (/* UNUSED - register output, only _upd/_rd_en used */ ),
    .r_mhdma_request_stat_nb_words_received_pc_pc0_upd    (stat_cfg.slave.nb_words_received_pc[0]                ),
    .r_mhdma_request_stat_nb_words_received_pc_pc0_rd_en  (stat_rst_cfg.slave.nb_words_received_pc[0]            ),
    .r_mhdma_request_stat_nb_words_received_pc_pc1        (/* UNUSED - register output, only _upd/_rd_en used */ ),
    .r_mhdma_request_stat_nb_words_received_pc_pc1_upd    (regf_nb_words_rx_pc1                                  ),
    .r_mhdma_request_stat_nb_words_received_pc_pc1_rd_en  (regf_rst_nb_words_rx_pc1                              ),
    .r_mhdma_request_stat_cnt_nb_write_complete           (/* UNUSED - register output, only _upd used */        ),
    .r_mhdma_request_stat_cnt_nb_write_complete_upd       (stat_cfg.master.nb_write_complete_cnt                 ),
    // timing
    .r_mhdma_request_stat_t_notify_to_ack                 (/* UNUSED - register output, only _upd used */        ),
    .r_mhdma_request_stat_t_notify_to_ack_upd             (stat_cfg.master.t_notify_to_ack                       ),
    .r_mhdma_request_stat_t_notify_to_ack_max             (/* UNUSED - register output, only _upd used */        ),
    .r_mhdma_request_stat_t_notify_to_ack_max_upd         (stat_cfg.master.t_notify_to_ack_max                   ),
    .r_mhdma_request_stat_t_rr_to_ce_received             (/* UNUSED - register output, only _upd used */        ),
    .r_mhdma_request_stat_t_rr_to_ce_received_upd         (stat_cfg.master.t_rr_to_ce_received                   ),
    .r_mhdma_request_stat_t_rr_to_ce_received_max         (/* UNUSED - register output, only _upd used */        ),
    .r_mhdma_request_stat_t_rr_to_ce_received_max_upd     (stat_cfg.master.t_rr_to_ce_received_max               ),
    .r_mhdma_request_stat_t_ce_first_to_last_pkt          (/* UNUSED - register output, only _upd used */        ),
    .r_mhdma_request_stat_t_ce_first_to_last_pkt_upd      (stat_cfg.decoder.t_ce_first_to_last_pkt               ),
    .r_mhdma_request_stat_t_rr_wait_words_pc_pc0          (/* UNUSED - register output, only _upd used */        ),
    .r_mhdma_request_stat_t_rr_wait_words_pc_pc0_upd      (stat_cfg.slave.t_rr_wait_words_pc[0]                  ),
    .r_mhdma_request_stat_t_rr_wait_words_pc_pc1          (/* UNUSED - register output, only _upd used */        ),
    .r_mhdma_request_stat_t_rr_wait_words_pc_pc1_upd      (regf_t_rr_wait_pc1                                    ),
    // registers
    .r_mhdma_system_fsm_value                             (/* UNUSED - register output, only _upd used */        ),
    .r_mhdma_system_fsm_value_upd                         (fsm_value_composed                                    ),
    .r_mhdma_request_stat_physical_addr_pc0_lsb           (/* UNUSED - register output, only _upd used */        ),
    .r_mhdma_request_stat_physical_addr_pc0_lsb_upd       (stat_cfg.slave.rr_phy_addr[0][REG_DATA_W-1:0]         ),
    .r_mhdma_request_stat_physical_addr_pc0_msb           (/* UNUSED - register output, only _upd used */        ),
    .r_mhdma_request_stat_physical_addr_pc0_msb_upd       (stat_cfg.slave.rr_phy_addr[0][2*REG_DATA_W-1:REG_DATA_W]),
    .r_mhdma_request_stat_physical_addr_pc1_lsb           (/* UNUSED - register output, only _upd used */        ),
    .r_mhdma_request_stat_physical_addr_pc1_lsb_upd       (regf_rr_phy_addr_pc1[REG_DATA_W-1:0]                  ),
    .r_mhdma_request_stat_physical_addr_pc1_msb           (/* UNUSED - register output, only _upd used */        ),
    .r_mhdma_request_stat_physical_addr_pc1_msb_upd       (regf_rr_phy_addr_pc1[2*REG_DATA_W-1:REG_DATA_W]       ),
    .r_mhdma_system_errors                                (/* UNUSED - register output, only _upd/_rd_en used */ ),
    .r_mhdma_system_errors_upd                            (mhdma_errors_cfg_merged                               ),
    .r_mhdma_system_errors_rd_en                          (stat_rst_cfg.mhdma_errors                             ),
    // new TX-side counters (formatter)
    .r_mhdma_request_stat_nb_notify_sent                  (/* UNUSED - register output, only _upd/_rd_en used */ ),
    .r_mhdma_request_stat_nb_notify_sent_upd              (stat_cfg.formatter.cnt_notify_sent                    ),
    .r_mhdma_request_stat_nb_notify_sent_rd_en            (stat_rst_cfg.formatter.cnt_notify_sent                ),
    .r_mhdma_request_stat_nb_ce_sent                      (/* UNUSED - register output, only _upd/_rd_en used */ ),
    .r_mhdma_request_stat_nb_ce_sent_upd                  (stat_cfg.formatter.cnt_ce_sent                        ),
    .r_mhdma_request_stat_nb_ce_sent_rd_en                (stat_rst_cfg.formatter.cnt_ce_sent                    ),
    .r_mhdma_request_stat_nb_notify_ack_sent              (/* UNUSED - register output, only _upd/_rd_en used */ ),
    .r_mhdma_request_stat_nb_notify_ack_sent_upd          (stat_cfg.formatter.cnt_notify_ack_sent                ),
    .r_mhdma_request_stat_nb_notify_ack_sent_rd_en        (stat_rst_cfg.formatter.cnt_notify_ack_sent            ),
    // read-request sent counter (formatter)
    .r_mhdma_request_stat_nb_read_req_sent                (/* UNUSED - register output, only _upd/_rd_en used */ ),
    .r_mhdma_request_stat_nb_read_req_sent_upd            (stat_cfg.formatter.cnt_read_req_sent                  ),
    .r_mhdma_request_stat_nb_read_req_sent_rd_en          (stat_rst_cfg.formatter.cnt_read_req_sent              ),
    // HBM write latency
    .r_mhdma_request_stat_t_hbm_write_latency             (/* UNUSED - register output, only _upd used */        ),
    .r_mhdma_request_stat_t_hbm_write_latency_upd         (stat_cfg.master.t_hbm_write_latency                   ),
    .r_mhdma_request_stat_t_hbm_write_latency_max         (/* UNUSED - register output, only _upd used */        ),
    .r_mhdma_request_stat_t_hbm_write_latency_max_upd     (stat_cfg.master.t_hbm_write_latency_max               ),
    .r_mhdma_request_stat_t_hbm_write_latency_min         (/* UNUSED - register output, only _upd used */        ),
    .r_mhdma_request_stat_t_hbm_write_latency_min_upd     (stat_cfg.master.t_hbm_write_latency_min               ),
    // min latency variants
    .r_mhdma_request_stat_t_notify_to_ack_min             (/* UNUSED - register output, only _upd used */        ),
    .r_mhdma_request_stat_t_notify_to_ack_min_upd         (stat_cfg.master.t_notify_to_ack_min                   ),
    .r_mhdma_request_stat_t_rr_to_ce_received_min         (/* UNUSED - register output, only _upd used */        ),
    .r_mhdma_request_stat_t_rr_to_ce_received_min_upd     (stat_cfg.master.t_rr_to_ce_received_min               ),
    // decoder dropped counter
    .r_mhdma_request_stat_nb_decoder_dropped              (/* UNUSED - register output, only _upd/_rd_en used */ ),
    .r_mhdma_request_stat_nb_decoder_dropped_upd          (stat_cfg.decoder.cnt_dropped                          ),
    .r_mhdma_request_stat_nb_decoder_dropped_rd_en        (stat_rst_cfg.decoder.cnt_dropped                      )
  );

  // ============================================================================================ //
  // Request handling logic
  // ============================================================================================ //
  logic [1:0] received_req;
  logic       request_consumed;

  // received_req signals lower module that we have received a command from regfile
  always_ff @(posedge clk_mhdma_cfg) begin
    if (~resetn_mhdma_cfg) begin
      received_req <= '0;
    end else begin
      if (r_request_req_id_wr_en) begin
        received_req[0] <= 1'b1;
      end else if (r_request_req_addr_wr_en) begin
        received_req[1] <= 1'b1;
      end else if (request_consumed) begin
        received_req    <= '0;
      end
    end
  end

  // ============================================================================================ //
  // CDC
  // ============================================================================================ //
  // CDC: Reset signals (CFG -> ETH)
  localparam int STAT_RST_W = $bits(mhdma_stat_rst_t);
  logic [STAT_RST_W-1:0] stat_rst_mhdma_flat;

  assign stat_rst_mhdma = mhdma_stat_rst_t'(stat_rst_mhdma_flat);

  for (genvar i = 0; i < STAT_RST_W; i++) begin : gen_cdc_stat_rst
    xpm_cdc_single_wrapper #(
      .CDC_SYNC_STAGES (CDC_SYNC_STAGES),
      .SRC_INPUT_REG   (1              )
    ) cdc_stat_rst (
      .src_clk  (clk_mhdma_cfg       ),
      .dest_clk (clk_mhdma           ),
      .src_in   (stat_rst_cfg[i]     ),
      .dest_out (stat_rst_mhdma_flat[i])
    );
  end

  // CDC: retry_max config bus (CFG -> ETH).
  // The regif drives it on clk_mhdma_cfg; the master uses it on clk_mhdma (independent clocks).
  // It is quasi-static (written once via AXI-Lite and stable during operation), so a per-bit 2-FF array synchronizer is sufficient.
  localparam int RETRY_MAX_CDC_W = 2*RETRY_CNT_W;
  logic [RETRY_MAX_CDC_W-1:0] retry_max_cfg_flat;
  logic [RETRY_MAX_CDC_W-1:0] retry_max_mhdma_flat;
  logic [   RETRY_CNT_W-1:0]  retry_max_notify_mhdma;
  logic [   RETRY_CNT_W-1:0]  retry_max_read_req_mhdma;

  assign retry_max_cfg_flat = {r_system_retry_max.retry_max_read_request, r_system_retry_max.retry_max_notify};

  for (genvar i = 0; i < RETRY_MAX_CDC_W; i++) begin : gen_cdc_retry_max
    xpm_cdc_single_wrapper #(
      .CDC_SYNC_STAGES (CDC_SYNC_STAGES),
      .SRC_INPUT_REG   (1              )
    ) cdc_retry_max (
      .src_clk  (clk_mhdma_cfg          ),
      .dest_clk (clk_mhdma              ),
      .src_in   (retry_max_cfg_flat[i]  ),
      .dest_out (retry_max_mhdma_flat[i])
    );
  end

  assign retry_max_notify_mhdma   = retry_max_mhdma_flat[RETRY_CNT_W-1:0];
  assign retry_max_read_req_mhdma = retry_max_mhdma_flat[2*RETRY_CNT_W-1:RETRY_CNT_W];

  // CDC: Counter values (ETH -> CFG)
  // Split into two xpm_cdc_handshake instances because of the XPM limit: 1024 bits width max
  localparam int STAT_DATA_W    = $bits(mhdma_stat_to_cfg_t);
  localparam int STAT_MASTER_W  = $bits(master_stat_t);
  localparam int STAT_REST_W    = STAT_DATA_W - STAT_MASTER_W;

  logic [STAT_DATA_W-1:0] stat_mhdma_flat;
  logic [STAT_DATA_W-1:0] stat_cfg_flat;

  assign stat_mhdma_flat = stat_mhdma;
  assign stat_cfg        = mhdma_stat_to_cfg_t'(stat_cfg_flat);

  xpm_cdc_handshake_wrapper #(
    .WIDTH           (STAT_MASTER_W    ),
    .CDC_SYNC_STAGES (CDC_SYNC_STAGES  )
  ) cdc_stat_master (
    .src_clk   (clk_mhdma                                      ),
    .src_rst_n (resetn_mhdma                                   ),
    .dest_clk  (clk_mhdma_cfg                                  ),
    .src_in    (stat_mhdma_flat[STAT_DATA_W-1 -: STAT_MASTER_W]),
    .dest_out  (stat_cfg_flat[STAT_DATA_W-1 -: STAT_MASTER_W]  )
  );

  xpm_cdc_handshake_wrapper #(
    .WIDTH           (STAT_REST_W      ),
    .CDC_SYNC_STAGES (CDC_SYNC_STAGES  )
  ) cdc_stat_slave_dec_fmt (
    .src_clk   (clk_mhdma                       ),
    .src_rst_n (resetn_mhdma                    ),
    .dest_clk  (clk_mhdma_cfg                   ),
    .src_in    (stat_mhdma_flat[STAT_REST_W-1:0]),
    .dest_out  (stat_cfg_flat[STAT_REST_W-1:0]  )
  );

  // Assemble the mhdma_system_errors word (all on cfg clock): cfg-domain master cmd-queue overflow
  // bits on top, then the CDC'd mhdma-domain errors. Layout = packing of mhdma_error_all_t (see pkg).
  assign mhdma_error_all.master_error_cfg = master_error_cfg;
  assign mhdma_error_all.mhdma_error      = mhdma_error_t'(stat_cfg.mhdma_errors[$bits(mhdma_error_t)-1:0]);
  assign mhdma_errors_cfg_merged          = {{(REG_DATA_W-$bits(mhdma_error_all_t)){1'b0}}, mhdma_error_all};

  // ============================================================================================ //
  // Multi-HPU-DMA bridge
  // ============================================================================================ //
  logic [MRMAC_AXIS_W-1:0 ]                     axis_rx_tdata;
  logic [MRMAC_TKEEP_W-1:0]                     axis_rx_tkeep_user;
  logic                                         axis_rx_tlast;
  logic                                         axis_rx_tvalid;

  logic [MRMAC_AXIS_W-1:0 ]                     axis_tx_tdata;
  logic [MRMAC_TKEEP_W-1:0]                     axis_tx_tkeep_user;
  logic                                         axis_tx_tlast;
  logic                                         axis_tx_tvalid;
  logic                                         axis_tx_tready;

  // Single AXI4 between bridge and NMU pipe
  logic [axi_if_mhdma_axi_pkg::AXI4_ID_W-1:0]   bridge_arid;
  logic [axi_if_mhdma_axi_pkg::AXI4_ADD_W-1:0]  bridge_araddr;
  logic [AXI4_LEN_W-1:0]                        bridge_arlen;
  logic [AXI4_SIZE_W-1:0]                       bridge_arsize;
  logic [AXI4_BURST_W-1:0]                      bridge_arburst;
  logic                                         bridge_arvalid;
  logic                                         bridge_arready;
  logic [axi_if_mhdma_axi_pkg::AXI4_ID_W-1:0]   bridge_rid;
  logic [axi_if_mhdma_axi_pkg::AXI4_DATA_W-1:0] bridge_rdata;
  logic [AXI4_RESP_W-1:0]                       bridge_rresp;
  logic                                         bridge_rlast;
  logic                                         bridge_rvalid;
  logic                                         bridge_rready;

  logic [axi_if_mhdma_axi_pkg::AXI4_ID_W-1:0]   bridge_awid;
  logic [axi_if_mhdma_axi_pkg::AXI4_ADD_W-1:0]  bridge_awaddr;
  logic [AXI4_LEN_W-1:0]                        bridge_awlen;
  logic [AXI4_SIZE_W-1:0]                       bridge_awsize;
  logic [AXI4_BURST_W-1:0]                      bridge_awburst;
  logic                                         bridge_awvalid;
  logic                                         bridge_awready;
  logic [axi_if_mhdma_axi_pkg::AXI4_DATA_W-1:0] bridge_wdata;
  logic [axi_if_mhdma_axi_pkg::AXI4_STRB_W-1:0] bridge_wstrb;
  logic                                         bridge_wlast;
  logic                                         bridge_wvalid;
  logic                                         bridge_wready;

  mhdma_bridge mhdma_bridge (
    .clk_mhdma_cfg                  (clk_mhdma_cfg                                                ),
    .resetn_mhdma_cfg               (resetn_mhdma_cfg                                             ),
    .clk_mhdma                      (clk_mhdma                                                    ),
    .resetn_mhdma                   (resetn_mhdma                                                 ),
    // Single AXI4 read interface ----------------------------------------------------------------
    .m_axi4_arid                    (bridge_arid                                                  ),
    .m_axi4_araddr                  (bridge_araddr                                                ),
    .m_axi4_arlen                   (bridge_arlen                                                 ),
    .m_axi4_arsize                  (bridge_arsize                                                ),
    .m_axi4_arburst                 (bridge_arburst                                               ),
    .m_axi4_arvalid                 (bridge_arvalid                                               ),
    .m_axi4_arready                 (bridge_arready                                               ),
    .m_axi4_rid                     (bridge_rid                                                   ),
    .m_axi4_rdata                   (bridge_rdata                                                 ),
    .m_axi4_rresp                   (bridge_rresp                                                 ),
    .m_axi4_rlast                   (bridge_rlast                                                 ),
    .m_axi4_rvalid                  (bridge_rvalid                                                ),
    .m_axi4_rready                  (bridge_rready                                                ),
    // Single AXI4 write interface ---------------------------------------------------------------
    .m_axi4_awid                    (bridge_awid                                                  ),
    .m_axi4_awaddr                  (bridge_awaddr                                                ),
    .m_axi4_awlen                   (bridge_awlen                                                 ),
    .m_axi4_awsize                  (bridge_awsize                                                ),
    .m_axi4_awburst                 (bridge_awburst                                               ),
    .m_axi4_awvalid                 (bridge_awvalid                                               ),
    .m_axi4_awready                 (bridge_awready                                               ),
    .m_axi4_wdata                   (bridge_wdata                                                 ),
    .m_axi4_wstrb                   (bridge_wstrb                                                 ),
    .m_axi4_wlast                   (bridge_wlast                                                 ),
    .m_axi4_wvalid                  (bridge_wvalid                                                ),
    .m_axi4_wready                  (bridge_wready                                                ),
    // B channel ----------------------------------------------------------------------------------
    .m_axi4_bid                     (m_axi4_mhdma_hbm_bid                                         ),
    .m_axi4_bresp                   (m_axi4_mhdma_hbm_bresp                                       ),
    .m_axi4_bvalid                  (m_axi4_mhdma_hbm_bvalid                                      ),
    .m_axi4_bready                  (m_axi4_mhdma_hbm_bready                                      ),
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
    .regf_retry_max_notify          (retry_max_notify_mhdma                                       ),
    .regf_retry_max_read_req        (retry_max_read_req_mhdma                                     ),
    // interruptions and control ------------------------------------------------------------------
    .received_req                   (&received_req                                                ),
    .request_consumed               (request_consumed                                             ),
    .clear_interrupt_notify         (clear_interrupt_notify                                       ),
    .clear_interrupt_rr             (clear_interrupt_rr                                           ),
    .interrupt_notify               (interrupt_notify                                             ),
    .interrupt_read_request         (interrupt_read_request                                       ),
    // statistics ---------------------------------------------------------------------------------
    .stat_to_cfg                    (stat_mhdma                                                   ),
    .stat_rst                       (stat_rst_mhdma                                               ),
    // cfg-domain errors (merged here on cfg clock) -----------------------------------------------
    .master_error_cfg               (master_error_cfg                                             ),
    .rst_errors_cfg                 (stat_rst_cfg.mhdma_errors                                    ),
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
  // NMU pipeline: bridge AXI4 -> pipeline stages -> single NMU port
  // All ETH_PC processing contexts share this single AXI4 port. PCs are processed sequentially
  // by the burst FSM; the NMU accesses both PC address regions within the same HBM pseudo-channel.
  // ============================================================================================ //
  mhdma_nmu_pipe mhdma_nmu_pipe (
    .clk                            (clk_mhdma                                                    ),
    .s_rst_n                        (resetn_mhdma                                                 ),
    // Single AXI4 read from bridge
    .s_axi4_arid                    (bridge_arid                                                  ),
    .s_axi4_araddr                  (bridge_araddr                                                ),
    .s_axi4_arlen                   (bridge_arlen                                                 ),
    .s_axi4_arsize                  (bridge_arsize                                                ),
    .s_axi4_arburst                 (bridge_arburst                                               ),
    .s_axi4_arvalid                 (bridge_arvalid                                               ),
    .s_axi4_arready                 (bridge_arready                                               ),
    .s_axi4_rdata                   (bridge_rdata                                                 ),
    .s_axi4_rresp                   (bridge_rresp                                                 ),
    .s_axi4_rid                     (bridge_rid                                                   ),
    .s_axi4_rlast                   (bridge_rlast                                                 ),
    .s_axi4_rvalid                  (bridge_rvalid                                                ),
    .s_axi4_rready                  (bridge_rready                                                ),
    // Single AXI4 write from bridge
    .s_axi4_awid                    (bridge_awid                                                  ),
    .s_axi4_awaddr                  (bridge_awaddr                                                ),
    .s_axi4_awlen                   (bridge_awlen                                                 ),
    .s_axi4_awsize                  (bridge_awsize                                                ),
    .s_axi4_awburst                 (bridge_awburst                                               ),
    .s_axi4_awvalid                 (bridge_awvalid                                               ),
    .s_axi4_awready                 (bridge_awready                                               ),
    .s_axi4_wdata                   (bridge_wdata                                                 ),
    .s_axi4_wstrb                   (bridge_wstrb                                                 ),
    .s_axi4_wlast                   (bridge_wlast                                                 ),
    .s_axi4_wvalid                  (bridge_wvalid                                                ),
    .s_axi4_wready                  (bridge_wready                                                ),
    // Single NMU port
    .m_axi4_arid                    (m_axi4_mhdma_hbm_arid                                        ),
    .m_axi4_araddr                  (m_axi4_mhdma_hbm_araddr                                      ),
    .m_axi4_arlen                   (m_axi4_mhdma_hbm_arlen                                       ),
    .m_axi4_arsize                  (m_axi4_mhdma_hbm_arsize                                      ),
    .m_axi4_arburst                 (m_axi4_mhdma_hbm_arburst                                     ),
    .m_axi4_arvalid                 (m_axi4_mhdma_hbm_arvalid                                     ),
    .m_axi4_arready                 (m_axi4_mhdma_hbm_arready                                     ),
    .m_axi4_rdata                   (m_axi4_mhdma_hbm_rdata                                       ),
    .m_axi4_rresp                   (m_axi4_mhdma_hbm_rresp                                       ),
    .m_axi4_rid                     (m_axi4_mhdma_hbm_rid                                         ),
    .m_axi4_rlast                   (m_axi4_mhdma_hbm_rlast                                       ),
    .m_axi4_rvalid                  (m_axi4_mhdma_hbm_rvalid                                      ),
    .m_axi4_rready                  (m_axi4_mhdma_hbm_rready                                      ),
    .m_axi4_awid                    (m_axi4_mhdma_hbm_awid                                        ),
    .m_axi4_awaddr                  (m_axi4_mhdma_hbm_awaddr                                      ),
    .m_axi4_awlen                   (m_axi4_mhdma_hbm_awlen                                       ),
    .m_axi4_awsize                  (m_axi4_mhdma_hbm_awsize                                      ),
    .m_axi4_awburst                 (m_axi4_mhdma_hbm_awburst                                     ),
    .m_axi4_awvalid                 (m_axi4_mhdma_hbm_awvalid                                     ),
    .m_axi4_awready                 (m_axi4_mhdma_hbm_awready                                     ),
    .m_axi4_wdata                   (m_axi4_mhdma_hbm_wdata                                       ),
    .m_axi4_wstrb                   (m_axi4_mhdma_hbm_wstrb                                       ),
    .m_axi4_wlast                   (m_axi4_mhdma_hbm_wlast                                       ),
    .m_axi4_wvalid                  (m_axi4_mhdma_hbm_wvalid                                      ),
    .m_axi4_wready                  (m_axi4_mhdma_hbm_wready                                      )
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
