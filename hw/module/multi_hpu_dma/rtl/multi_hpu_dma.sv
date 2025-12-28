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
#(
  parameter int FIFO_DEPTH = 512,
  parameter int NB_WORD_W = $clog2(FIFO_DEPTH)+1
) (
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
  input  logic [AXIL_DATA_BYTES-1:0]                             s_axil_dma_wstrb, /* UNUSED */
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
  output logic [ETH_PC-1:0][axi_if_eth_axi_pkg::AXI4_ID_W-1:0]   m_axi4_eth_hbm_arid,
  output logic [ETH_PC-1:0][axi_if_eth_axi_pkg::AXI4_ADD_W-1:0]  m_axi4_eth_hbm_araddr,
  output logic [ETH_PC-1:0][AXI4_LEN_W-1:0]                      m_axi4_eth_hbm_arlen,
  output logic [ETH_PC-1:0][AXI4_SIZE_W-1:0]                     m_axi4_eth_hbm_arsize,
  output logic [ETH_PC-1:0][AXI4_BURST_W-1:0]                    m_axi4_eth_hbm_arburst,
  output logic [ETH_PC-1:0]                                      m_axi4_eth_hbm_arvalid,
  input  logic [ETH_PC-1:0]                                      m_axi4_eth_hbm_arready,
  input  logic [ETH_PC-1:0][axi_if_eth_axi_pkg::AXI4_DATA_W-1:0] m_axi4_eth_hbm_rdata,
  input  logic [ETH_PC-1:0]                                      m_axi4_eth_hbm_rlast,
  input  logic [ETH_PC-1:0][axi_if_eth_axi_pkg::AXI4_ID_W-1:0]   m_axi4_eth_hbm_rid,
  input  logic [ETH_PC-1:0][AXI4_RESP_W-1:0]                     m_axi4_eth_hbm_rresp,
  input  logic [ETH_PC-1:0]                                      m_axi4_eth_hbm_rvalid,
  output logic [ETH_PC-1:0]                                      m_axi4_eth_hbm_rready,
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
  // interrupt interface ------------------------------------------------------------
  output logic                                                   interrupt_notify,
  output logic                                                   interrupt_read_request,
  // Giga traceivers interface ------------------------------------------------
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
  // Signal
  // ============================================================================================ --
  logic [$clog2(QSFP_LANE_NB)-1:0] line_sel;
  logic                            clear_interrupt_notify;
  logic                            clear_interrupt_rr;

  // ============================================================================================ //
  // Register file
  // ============================================================================================ //
  // bridge
  logic [NB_MAX_HPU-1:0][REG_DATA_W-1:0]   r_regf_hpu_ids;
  logic                 [REG_DATA_W-1:0]   r_request_notify;
  logic                 [REG_DATA_W-1:0]   r_request_read;
  logic                 [REG_DATA_W-1:0]   r_request_req_id;
  logic                 [REG_DATA_W-1:0]   r_request_req_addr;
  logic                 [REG_DATA_W-1:0]   r_system_timeout_notify;
  logic                 [REG_DATA_W-1:0]   r_system_timeout_read_req;
  logic [    ETH_PC-1:0][2*REG_DATA_W-1:0] r_ct_mem_addr;
  // lane control & debug
  logic                 [REG_DATA_W-1:0]   r_system_line;
  logic                 [REG_DATA_W-1:0]   r_reset_datapath;
  logic                 [REG_DATA_W-1:0]   r_reset_monitor;
  logic                 [REG_DATA_W-1:0]   r_line_debug;
  logic                 [REG_DATA_W-1:0]   r_status_debug;


  // Statistics Counters --------------------------------------------------------------------------
  // counters @eth
  logic [REG_DATA_W-1:0] cnt_notify_eth;
  logic [REG_DATA_W-1:0] cnt_notify_ack_eth;
  logic [REG_DATA_W-1:0] cnt_timeout_eth;
  logic [REG_DATA_W-1:0] cnt_retry_notify_eth;
  // counters @cfg
  logic [REG_DATA_W-1:0] cnt_notify_cfg;
  logic [REG_DATA_W-1:0] cnt_notify_ack_cfg;
  logic [REG_DATA_W-1:0] cnt_timeout_cfg;
  logic [REG_DATA_W-1:0] cnt_retry_notify_cfg;

  // reset counters @eth
  logic                 rst_cnt_notify_eth;
  logic                 rst_cnt_notify_ack_eth;
  logic                 rst_cnt_timeout_eth;
  logic                 rst_cnt_retry_notify_eth;
  // reset counters @cfg
  logic                 rst_cnt_notify_cfg;
  logic                 rst_cnt_notify_ack_cfg;
  logic                 rst_cnt_timeout_cfg;
  logic                 rst_cnt_retry_notify_cfg;

  // Statistics Registers -------------------------------------------------------------------------
  //timing @eth
  logic [REG_DATA_W-1:0] t_notify_to_ack_eth;
  logic [REG_DATA_W-1:0] t_rr_to_ce_received_eth;
  logic [REG_DATA_W-1:0] t_ce_first_to_last_pkt_eth;
  //timing @cfg
  logic [REG_DATA_W-1:0] t_notify_to_ack_cfg;
  logic [REG_DATA_W-1:0] t_rr_to_ce_received_cfg;
  logic [REG_DATA_W-1:0] t_ce_first_to_last_pkt_cfg;

  // FSM value
  logic [REG_DATA_W-1:0] r_fsm_value_eth;
  logic [REG_DATA_W-1:0] r_fsm_value_cfg;


  logic [15:0] r_cnt_notify_ack;
  logic [15:0] r_cnt_notify_read;
  logic        rst_cnt_notify;

  // signals derived from registers
  logic                 tx_loop;
  logic                 rx_to_tx;
  logic                 reset_registers;
  logic                 debug;

  logic                 stat_tx_empty;
  logic                 stat_tx_rd_rst_busy;
  logic                 stat_tx_data_valid;
  logic [NB_WORD_W-1:0] stat_rd_data_count;
  logic                 stat_tx_full;
  logic                 stat_tx_wr_rst_busy;
  logic                 stat_qsfp_tx_tready;

  assign line_sel      = r_system_line[1:0];
  assign gt_loopback   = r_system_line[4:2];
  assign gt_line_rate  = r_system_line[13:5];
  assign debug         = r_system_line[31];

  assign gt_reset_all         = r_reset_datapath[3:0];
  assign gt_reset_tx_datapath = r_reset_datapath[7:4];
  assign gt_reset_rx_datapath = r_reset_datapath[11:8];

  assign r_reset_monitor[3:0] = gt_tx_reset_done;
  assign r_reset_monitor[7:4] = gt_rx_reset_done;
  assign r_reset_monitor[31:8] = 'h0;

  assign rx_to_tx        = r_line_debug[29];
  assign tx_loop         = r_line_debug[30];
  assign reset_registers = r_line_debug[31];

  assign r_status_debug = {stat_tx_empty, stat_tx_rd_rst_busy, stat_tx_data_valid,
                          stat_tx_full, stat_tx_wr_rst_busy, stat_qsfp_tx_tready,
                          {(AXIL_DATA_W-NB_WORD_W-6){1'b0}},
                          stat_rd_data_count};


  // status directly from fifo
  logic [NB_WORD_W-1:0]    r_nb_word;
  logic [MRMAC_AXIS_W-1:0] r_wr_word;
  logic [AXIL_DATA_W-1:0]  r_wr_word_a;
  logic [AXIL_DATA_W-1:0]  r_wr_word_b;
  logic [NB_WORD_W-1:0]    r_wr_data_count;
  logic [NB_WORD_W-1:0]    r_rd_data_count;
  logic [MRMAC_AXIS_W-1:0] r_rd_word;

  logic [63:0]             clk_cnt_out;
  logic [63:0]             valid_words_out;
  logic [63:0]             sop_cnt_out;
  logic [31:0]             trigger_rd_cnt_out;
  logic [31:0]             tx_wr_en_cnt;

  // updated registers ----------------------------------------------------------------------------
  // This registers are needed to ease timing
  logic [REG_DATA_W-1:0] request_read_tmp;
  logic [REG_DATA_W-1:0] request_notify_tmp;
  logic [REG_DATA_W-1:0] reset_monitor_tmp;

  always_ff @(posedge clk_eth_cfg) begin
    request_read_tmp   <= r_request_read;
    request_notify_tmp <= r_request_notify;
    reset_monitor_tmp  <= r_reset_monitor;
  end

  // this module is the regif controlling and accessing registers of MHMDA
  hpu_regif_core_eth_2in3  hpu_regif_core_eth_2in3 (
    // configuration interface --------------------------------------------------------------------
    .clk                                   (clk_eth_cfg                                           ),
    .s_rst_n                               (resetn_eth_cfg                                        ),
    // axi4-lite ----------------------------------------------------------------------------------
    .s_axil_awaddr                         (s_axil_dma_awaddr                                     ),
    .s_axil_awvalid                        (s_axil_dma_awvalid                                    ),
    .s_axil_awready                        (s_axil_dma_awready                                    ),
    .s_axil_wdata                          (s_axil_dma_wdata                                      ),
    .s_axil_wvalid                         (s_axil_dma_wvalid                                     ),
    .s_axil_wready                         (s_axil_dma_wready                                     ),
    .s_axil_bresp                          (s_axil_dma_bresp                                      ),
    .s_axil_bvalid                         (s_axil_dma_bvalid                                     ),
    .s_axil_bready                         (s_axil_dma_bready                                     ),
    .s_axil_araddr                         (s_axil_dma_araddr                                     ),
    .s_axil_arvalid                        (s_axil_dma_arvalid                                    ),
    .s_axil_arready                        (s_axil_dma_arready                                    ),
    .s_axil_rdata                          (s_axil_dma_rdata                                      ),
    .s_axil_rresp                          (s_axil_dma_rresp                                      ),
    .s_axil_rvalid                         (s_axil_dma_rvalid                                     ),
    .s_axil_rready                         (s_axil_dma_rready                                     ),
    .r_axil_wdata                          (/* UNUSED */                                          ),
    // HPU ids ------------------------------------------------------------------------------------
    .r_mhdma_hpu_id_zero                   (r_regf_hpu_ids[0]                                     ),
    .r_mhdma_hpu_id_one                    (r_regf_hpu_ids[1]                                     ),
    .r_mhdma_hpu_id_two                    (r_regf_hpu_ids[2]                                     ),
    .r_mhdma_hpu_id_three                  (r_regf_hpu_ids[3]                                     ),
    .r_mhdma_hpu_id_four                   (r_regf_hpu_ids[4]                                     ),
    .r_mhdma_hpu_id_five                   (r_regf_hpu_ids[5]                                     ),
    .r_mhdma_hpu_id_six                    (r_regf_hpu_ids[6]                                     ),
    .r_mhdma_hpu_id_seven                  (r_regf_hpu_ids[7]                                     ),
    // HBM ----------------------------------------------------------------------------------------
    .r_mhdma_hbm_axi4_addr_2in3_ct_pc0_lsb (r_ct_mem_addr[0][0*REG_DATA_W+:REG_DATA_W]            ),
    .r_mhdma_hbm_axi4_addr_2in3_ct_pc0_msb (r_ct_mem_addr[0][1*REG_DATA_W+:REG_DATA_W]            ),
    .r_mhdma_hbm_axi4_addr_2in3_ct_pc1_lsb (r_ct_mem_addr[1][0*REG_DATA_W+:REG_DATA_W]            ),
    .r_mhdma_hbm_axi4_addr_2in3_ct_pc1_msb (r_ct_mem_addr[1][1*REG_DATA_W+:REG_DATA_W]            ),
    // RPU requests -------------------------------------------------------------------------------
    .r_mhdma_request_req_id_wr_en          (r_request_req_id_wr_en                                ),
    .r_mhdma_request_req_id                (r_request_req_id                                      ),

    .r_mhdma_request_req_addr_wr_en        (r_request_req_addr_wr_en                              ),
    .r_mhdma_request_req_addr              (r_request_req_addr                                    ),
    // Updated from RTL only ----------------------------------------------------------------------
    .r_mhdma_request_read_request_upd      (request_read_tmp                                      ),
    .r_mhdma_request_read_request_rd_en    (clear_interrupt_rr                                    ),

    .r_mhdma_request_notify_upd            (request_notify_tmp                                    ),
    .r_mhdma_request_notify_rd_en          (clear_interrupt_notify                                ),
    // control ------------------------------------------------------------------------------------
    .r_mhdma_system_lane                   (r_system_line                                         ),
    .r_mhdma_reset_datapath                (r_reset_datapath                                      ),
    .r_mhdma_reset_monitor_upd             (reset_monitor_tmp                                     ),
    .r_mhdma_lane_debug                    (r_line_debug                                          ),
    .r_mhdma_system_timeout_notify         (r_system_timeout_notify                               ),
    .r_mhdma_system_timeout_read_req       (r_system_timeout_read_req                             ),
    // stats --------------------------------------------------------------------------------------
    .r_mhdma_request_stat_notify_upd                (cnt_notify_cfg                               ),
    .r_mhdma_request_stat_notify_rd_en              (rst_cnt_notify_cfg                           ),
    .r_mhdma_request_stat_notify_ack_upd            (cnt_notify_ack_cfg                           ),
    .r_mhdma_request_stat_notify_ack_rd_en          (rst_cnt_notify_ack_cfg                       ),
    .r_mhdma_request_stat_notify_timeout_upd        (cnt_timeout_cfg                              ),
    .r_mhdma_request_stat_notify_timeout_rd_en      (rst_cnt_timeout_cfg                          ),
    .r_mhdma_request_stat_notify_timeout_retry_upd  (cnt_retry_notify_cfg                         ),
    .r_mhdma_request_stat_notify_timeout_retry_rd_en(rst_cnt_retry_notify_cfg                     ),
    // timing
    .r_mhdma_request_stat_t_notify_to_ack_upd       (t_notify_to_ack_cfg                          ),
    .r_mhdma_request_stat_t_rr_to_ce_received_upd   (t_rr_to_ce_received_cfg                      ),
    .r_mhdma_request_stat_t_ce_first_to_last_pkt_upd(t_ce_first_to_last_pkt_cfg                   ),
    // registers
    .r_mhdma_system_fsm_value_upd                   (r_fsm_value_cfg                              ),
    // from trace module --------------------------------------------------------------------------
    .r_fifo_write_number_of_words          (r_nb_word                                             ), // to be removed or renamed?
    .r_fifo_write_words_to_write_a         (r_wr_word_a                                           ), // to be removed or renamed?
    .r_fifo_write_words_to_write_b         (r_wr_word_b                                           ), // to be removed or renamed?
    .r_fifo_write_fifo_write_data_count_upd({ {(AXIL_DATA_W-NB_WORD_W){1'b0}}, r_wr_data_count}   ), // to be removed or renamed?
    .r_fifo_read_words_to_read_a_upd       (r_rd_word[AXIL_DATA_W-1:0]                            ), // to be removed or renamed?
    .r_fifo_read_words_to_read_b_upd       (r_rd_word[2*AXIL_DATA_W-1:AXIL_DATA_W]                ), // to be removed or renamed?
    .r_fifo_read_fifo_read_data_count_upd  ({ {(AXIL_DATA_W-NB_WORD_W){1'b0}}, r_rd_data_count}   ), // to be removed or renamed?
    .r_cnt_trig_rd_upd                     (trigger_rd_cnt_out                                    ), // to be removed or renamed?
    .r_cnt_tx_wr_upd                       (tx_wr_en_cnt                                          ), // to be removed or renamed?
    .r_mhdma_stat_clk_a_upd                (clk_cnt_out[31:0]                                     ),
    .r_mhdma_stat_clk_b_upd                (clk_cnt_out[63:32]                                    ),
    .r_mhdma_stat_valid_words_a_upd        (valid_words_out[31:0]                                 ),
    .r_mhdma_stat_valid_words_b_upd        (valid_words_out[63:32]                                ),
    .r_mhdma_stat_sop_cnt_a_upd            (sop_cnt_out[31:0]                                     ),
    .r_mhdma_stat_sop_cnt_b_upd            (sop_cnt_out[63:32]                                    ),
    .r_mhdma_stat_status_upd               (r_status_debug                                        )
  );

  // Logic around regfile -------------------------------------------------------------------------
  // building requests flags for sampling and properly create the request cmd queue in the bridge
  logic [1:0] received_req;
  logic request_consumed;

  always_ff @(posedge clk_eth_cfg) begin : received_req_id
    if (~resetn_eth_cfg) begin
      received_req[0]   <= 1'b0;
    end else begin
      if (r_request_req_id_wr_en)  begin
        received_req[0] <= 1'b1;
      end else if (request_consumed) begin
        received_req[0] <= 1'b0;
      end
    end
  end

  always_ff @(posedge clk_eth_cfg) begin : received_req_addr
    if (~resetn_eth_cfg) begin
      received_req[1] <= 1'b0;
    end else begin
      if (r_request_req_addr_wr_en)  begin
        received_req[1] <= 1'b1;
      end else if (request_consumed) begin
        received_req[1] <= 1'b0;
      end
    end
  end

  // clear statistic counter on notify //TODO
  assign rst_cnt_notify = (s_axil_dma_araddr == MHDMA_REQUEST_STAT_NOTIFY_OFS) && s_axil_dma_arready;

  // for the trace module --
  // read_ack is a pulse that partly controls the rx_fifo read, must be in configuration clock freq
  // because axi4-lite is limited in word number, the ack is triggered only when the second word is read
  logic read_ack;

  always_ff @(posedge clk_eth_cfg) begin
    if (~resetn_eth_cfg) begin
      read_ack <= 1'b0;
    end else begin
      if ((s_axil_dma_araddr == FIFO_READ_WORDS_TO_READ_B_OFS) && s_axil_dma_arready) begin
        read_ack <= 1'b1;
      end else begin
        read_ack <= 1'b0;
      end
    end
  end

  // write ack: same fashion as read_ack, a pulse is generated
  logic write_ack;
  always_ff @(posedge clk_eth_cfg) begin
    if (~resetn_eth_cfg) begin
      write_ack <= 1'b0;
    end else begin
      if ((s_axil_dma_awaddr == FIFO_WRITE_WORDS_TO_WRITE_B_OFS) && s_axil_dma_awready) begin
        write_ack <= 1'b1;
      end else begin
        write_ack <= 1'b0;
      end
    end
  end

  // merging half words into a single one
  assign r_wr_word = write_ack ? {r_wr_word_a, r_wr_word_b} :0;

  // ============================================================================================ //
  // CDC for regfile
  // TODO: this is temporary
  // ============================================================================================ //

  // Counters ===================================================================================
  xpm_cdc_single_wrapper #(
    .CDC_SYNC_STAGES ( 2 ) ,
    .SRC_INPUT_REG   ( 0 )
  ) cdc_rst_cnt_notify (
    .src_clk  ( clk_eth_cfg     ) ,
    .dest_clk ( clk_eth_mrmac ) ,
    .src_in   ( rst_cnt_notify_cfg ) ,
    .dest_out ( rst_cnt_notify_eth )
  ); //temporary
  xpm_cdc_gray #(
    .DEST_SYNC_FF(4),                   // Range: 2-10 synchronizer stages
    .INIT_SYNC_FF(0),                   // 0=disable simulation init values
    .REG_OUTPUT(0),                     // 0=combinatorial output, 1=registered output
    .SIM_ASSERT_CHK(0),                 // 0=disable simulation messages
    .SIM_LOSSLESS_GRAY_CHK(0),          // 0=disable lossless check
    .WIDTH(REG_DATA_W)                   // REG_DATA_W-bit counter width (range: 2-32)
  ) xpm_cdc_gray_cnt_notify (
    .src_clk(clk_eth_mrmac),            // 1-bit input: source clock
    .src_in_bin(cnt_notify_eth),        // REG_DATA_W-bit input: binary counter to synchronize

    .dest_clk(clk_eth_cfg),             // 1-bit input: destination clock
    .dest_out_bin(cnt_notify_cfg)       // REG_DATA_W-bit output: binary value in dest domain
  );//temporary

  xpm_cdc_single_wrapper #(
    .CDC_SYNC_STAGES ( 2 ) ,
    .SRC_INPUT_REG   ( 0 )
  ) cdc_rst_cnt_notify_ack (
    .src_clk  ( clk_eth_cfg     ) ,
    .dest_clk ( clk_eth_mrmac ) ,
    .src_in   ( rst_cnt_notify_ack_cfg ) ,
    .dest_out ( rst_cnt_notify_ack_eth )
  );//temporary
  xpm_cdc_gray #(
    .DEST_SYNC_FF(4),                   // Range: 2-10 synchronizer stages
    .INIT_SYNC_FF(0),                   // 0=disable simulation init values
    .REG_OUTPUT(0),                     // 0=combinatorial output, 1=registered output
    .SIM_ASSERT_CHK(0),                 // 0=disable simulation messages
    .SIM_LOSSLESS_GRAY_CHK(0),          // 0=disable lossless check
    .WIDTH(REG_DATA_W)                   // REG_DATA_W-bit counter width (range: 2-32)
  ) xpm_cdc_gray_cnt_notify_ack (
    .src_clk(clk_eth_mrmac),            // 1-bit input: source clock
    .src_in_bin(cnt_notify_ack_eth),    // REG_DATA_W-bit input: binary counter to synchronize

    .dest_clk(clk_eth_cfg),             // 1-bit input: destination clock
    .dest_out_bin(cnt_notify_ack_cfg)   // REG_DATA_W-bit output: binary value in dest domain
  );//temporary

  xpm_cdc_single_wrapper #(
    .CDC_SYNC_STAGES ( 2 ) ,
    .SRC_INPUT_REG   ( 0 )
  ) cdc_rst_cnt_timeout (
    .src_clk  ( clk_eth_cfg     ) ,
    .dest_clk ( clk_eth_mrmac ) ,
    .src_in   ( rst_cnt_timeout_cfg ) ,
    .dest_out ( rst_cnt_timeout_eth )
  );//temporary
  xpm_cdc_gray #(
    .DEST_SYNC_FF(4),                   // Range: 2-10 synchronizer stages
    .INIT_SYNC_FF(0),                   // 0=disable simulation init values
    .REG_OUTPUT(0),                     // 0=combinatorial output, 1=registered output
    .SIM_ASSERT_CHK(0),                 // 0=disable simulation messages
    .SIM_LOSSLESS_GRAY_CHK(0),          // 0=disable lossless check
    .WIDTH(REG_DATA_W)                   // REG_DATA_W-bit counter width (range: 2-32)
  ) xpm_cdc_gray_cnt_notify_to (
    .src_clk(clk_eth_mrmac),            // 1-bit input: source clock
    .src_in_bin(cnt_timeout_eth),       // REG_DATA_W-bit input: binary counter to synchronize

    .dest_clk(clk_eth_cfg),             // 1-bit input: destination clock
    .dest_out_bin(cnt_timeout_cfg)      // REG_DATA_W-bit output: binary value in dest domain
  );//temporary

  xpm_cdc_single_wrapper #(
    .CDC_SYNC_STAGES ( 2 ) ,
    .SRC_INPUT_REG   ( 0 )
  ) cdc_rst_cnt_notify_retry (
    .src_clk  ( clk_eth_cfg     ) ,
    .dest_clk ( clk_eth_mrmac ) ,
    .src_in   ( rst_cnt_retry_notify_cfg ) ,
    .dest_out ( rst_cnt_retry_notify_eth )
  );//temporary
  xpm_cdc_gray #(
    .DEST_SYNC_FF(4),                   // Range: 2-10 synchronizer stages
    .INIT_SYNC_FF(0),                   // 0=disable simulation init values
    .REG_OUTPUT(0),                     // 0=combinatorial output, 1=registered output
    .SIM_ASSERT_CHK(0),                 // 0=disable simulation messages
    .SIM_LOSSLESS_GRAY_CHK(0),          // 0=disable lossless check
    .WIDTH(REG_DATA_W)                   // REG_DATA_W-bit counter width (range: 2-32)
  ) xpm_cdc_gray_cnt_notify_retry (
    .src_clk(clk_eth_mrmac),            // 1-bit input: source clock
    .src_in_bin(cnt_retry_notify_eth),  // REG_DATA_W-bit input: binary counter to synchronize

    .dest_clk(clk_eth_cfg),             // 1-bit input: destination clock
    .dest_out_bin(cnt_retry_notify_cfg) // REG_DATA_W-bit output: binary value in dest domain
  );//temporary
  // Registers ETH -> CFG =========================================================================
  xpm_cdc_gray #(
    .DEST_SYNC_FF(4),                   // Range: 2-10 synchronizer stages
    .INIT_SYNC_FF(0),                   // 0=disable simulation init values
    .REG_OUTPUT(0),                     // 0=combinatorial output, 1=registered output
    .SIM_ASSERT_CHK(0),                 // 0=disable simulation messages
    .SIM_LOSSLESS_GRAY_CHK(0),          // 0=disable lossless check
    .WIDTH(REG_DATA_W)                  // REG_DATA_W-bit counter width (range: 2-32)
  ) xpm_cdc_gray_reg_fsm (
    .src_clk(clk_eth_mrmac),            // 1-bit input: source clock
    .src_in_bin(r_fsm_value_eth),       // REG_DATA_W-bit input: binary counter to synchronize

    .dest_clk(clk_eth_cfg),             // 1-bit input: destination clock
    .dest_out_bin(r_fsm_value_cfg)      // REG_DATA_W-bit output: binary value in dest domain
  );//temporary
  xpm_cdc_gray #(
    .DEST_SYNC_FF(4),                   // Range: 2-10 synchronizer stages
    .INIT_SYNC_FF(0),                   // 0=disable simulation init values
    .REG_OUTPUT(0),                     // 0=combinatorial output, 1=registered output
    .SIM_ASSERT_CHK(0),                 // 0=disable simulation messages
    .SIM_LOSSLESS_GRAY_CHK(0),          // 0=disable lossless check
    .WIDTH(REG_DATA_W)                  // REG_DATA_W-bit counter width (range: 2-32)
  ) xpm_cdc_gray_t_notify_ack (
    .src_clk(clk_eth_mrmac),            // 1-bit input: source clock
    .src_in_bin(t_notify_to_ack_eth),       // REG_DATA_W-bit input: binary counter to synchronize

    .dest_clk(clk_eth_cfg),             // 1-bit input: destination clock
    .dest_out_bin(t_notify_to_ack_cfg)      // REG_DATA_W-bit output: binary value in dest domain
  );//temporary
  xpm_cdc_gray #(
    .DEST_SYNC_FF(4),                   // Range: 2-10 synchronizer stages
    .INIT_SYNC_FF(0),                   // 0=disable simulation init values
    .REG_OUTPUT(0),                     // 0=combinatorial output, 1=registered output
    .SIM_ASSERT_CHK(0),                 // 0=disable simulation messages
    .SIM_LOSSLESS_GRAY_CHK(0),          // 0=disable lossless check
    .WIDTH(REG_DATA_W)                  // REG_DATA_W-bit counter width (range: 2-32)
  ) xpm_cdc_gray_t_rr_ce (
    .src_clk(clk_eth_mrmac),                // 1-bit input: source clock
    .src_in_bin(t_rr_to_ce_received_eth),   // REG_DATA_W-bit input: binary counter to synchronize

    .dest_clk(clk_eth_cfg),                 // 1-bit input: destination clock
    .dest_out_bin(t_rr_to_ce_received_cfg)  // REG_DATA_W-bit output: binary value in dest domain
  );//temporary
  xpm_cdc_gray #(
    .DEST_SYNC_FF(4),                   // Range: 2-10 synchronizer stages
    .INIT_SYNC_FF(0),                   // 0=disable simulation init values
    .REG_OUTPUT(0),                     // 0=combinatorial output, 1=registered output
    .SIM_ASSERT_CHK(0),                 // 0=disable simulation messages
    .SIM_LOSSLESS_GRAY_CHK(0),          // 0=disable lossless check
    .WIDTH(REG_DATA_W)                  // REG_DATA_W-bit counter width (range: 2-32)
  ) xpm_cdc_gray_t_ce_first_last_pkt (
    .src_clk(clk_eth_mrmac),                // 1-bit input: source clock
    .src_in_bin(t_ce_first_to_last_pkt_eth),   // REG_DATA_W-bit input: binary counter to synchronize

    .dest_clk(clk_eth_cfg),                 // 1-bit input: destination clock
    .dest_out_bin(t_ce_first_to_last_pkt_cfg)  // REG_DATA_W-bit output: binary value in dest domain
  );//temporary
  // ==============================================================================================

  // ============================================================================================ //
  // Multi-HPU-DMA bridge
  // ============================================================================================ //
  logic [MRMAC_AXIS_W-1:0  ] axis_rx_tdata;
  logic [MRMAC_TKEEP_W-1:0 ] axis_rx_tkeep_user;
  logic                      axis_rx_tlast;
  logic                      axis_rx_tvalid;

  logic [MRMAC_AXIS_W-1:0 ] axis_tx_tdata;
  logic [MRMAC_TKEEP_W-1:0] axis_tx_tkeep_user;
  logic                     axis_tx_tlast;
  logic                     axis_tx_tvalid;
  logic                     axis_tx_tready;

  // this module is the core of the multi hpu dma: it's the bridge between HBM and MRMAC IP
  mhdma_bridge mhdma_bridge (
    .clk_cfg                        (clk_eth_cfg                                                 ),
    .resetn_cfg                     (resetn_eth_cfg                                              ),
    .clk_mrmac                      (clk_eth_mrmac                                               ),
    .resetn_mrmac                   (resetn_eth_mrmac                                            ),
    // axi4-full for each ETH_PC ------------------------------------------------------------------
    .m_axi4_arid                    (m_axi4_eth_hbm_arid                                         ),
    .m_axi4_araddr                  (m_axi4_eth_hbm_araddr                                       ),
    .m_axi4_arlen                   (m_axi4_eth_hbm_arlen                                        ),
    .m_axi4_arsize                  (m_axi4_eth_hbm_arsize                                       ),
    .m_axi4_arburst                 (m_axi4_eth_hbm_arburst                                      ),
    .m_axi4_arvalid                 (m_axi4_eth_hbm_arvalid                                      ),
    .m_axi4_arready                 (m_axi4_eth_hbm_arready                                      ),
    .m_axi4_rid                     (m_axi4_eth_hbm_rid                                          ),
    .m_axi4_rdata                   (m_axi4_eth_hbm_rdata                                        ),
    .m_axi4_rresp                   (m_axi4_eth_hbm_rresp                                        ),
    .m_axi4_rlast                   (m_axi4_eth_hbm_rlast                                        ),
    .m_axi4_rvalid                  (m_axi4_eth_hbm_rvalid                                       ),
    .m_axi4_rready                  (m_axi4_eth_hbm_rready                                       ),
    .m_axi4_awid                    (m_axi4_eth_hbm_awid                                         ),
    .m_axi4_awaddr                  (m_axi4_eth_hbm_awaddr                                       ),
    .m_axi4_awlen                   (m_axi4_eth_hbm_awlen                                        ),
    .m_axi4_awsize                  (m_axi4_eth_hbm_awsize                                       ),
    .m_axi4_awburst                 (m_axi4_eth_hbm_awburst                                      ),
    .m_axi4_awvalid                 (m_axi4_eth_hbm_awvalid                                      ),
    .m_axi4_awready                 (m_axi4_eth_hbm_awready                                      ),
    .m_axi4_wdata                   (m_axi4_eth_hbm_wdata                                        ),
    .m_axi4_wstrb                   (m_axi4_eth_hbm_wstrb                                        ),
    .m_axi4_wlast                   (m_axi4_eth_hbm_wlast                                        ),
    .m_axi4_wvalid                  (m_axi4_eth_hbm_wvalid                                       ),
    .m_axi4_wready                  (m_axi4_eth_hbm_wready                                       ),
    .m_axi4_bid                     (m_axi4_eth_hbm_bid                                          ),
    .m_axi4_bresp                   (m_axi4_eth_hbm_bresp                                        ),
    .m_axi4_bvalid                  (m_axi4_eth_hbm_bvalid                                       ),
    .m_axi4_bready                  (m_axi4_eth_hbm_bready                                       ),
    // Register interface -------------------------------------------------------------------------
    .regf_hpu_ids                   (r_regf_hpu_ids                                              ),
    .regf_ct_mem_addr               (r_ct_mem_addr                                               ),
    .regf_req_id                    (r_request_req_id                                            ),
    .regf_req_addr                  (r_request_req_addr                                          ),
    .regf_notify_payload            (r_request_notify                                            ),
    .regf_read_payload              (r_request_read                                              ),
    .regf_timeout_duration_notify   (r_system_timeout_notify                                     ),
    .regf_timeout_duration_read_req (r_system_timeout_read_req                                   ),
    // interruptions and control ------------------------------------------------------------------
    .received_req                   (&received_req                                               ),
    .request_consumed               (request_consumed                                            ),
    .clear_interrupt_notify         (clear_interrupt_notify                                      ),
    .clear_interrupt_rr             (clear_interrupt_rr                                          ),
    .interrupt_notify               (interrupt_notify                                            ),
    .interrupt_read_request         (interrupt_read_request                                      ),
    // statistics ---------------------------------------------------------------------------------
    // counters
    .stat_cnt_notify                (cnt_notify_eth                                              ),
    .stat_cnt_notify_ack            (cnt_notify_ack_eth                                          ),
    .stat_cnt_notify_timeout        (cnt_timeout_eth                                             ),
    .stat_cnt_notify_retries        (cnt_retry_notify_eth                                        ),
    // timing
    .stat_t_notify_to_ack           (t_notify_to_ack_eth                                         ),
    .stat_t_rr_to_ce_received       (t_rr_to_ce_received_eth                                     ),
    .stat_t_ce_first_to_last_pkt    (t_ce_first_to_last_pkt_eth                                  ),
    // resets
    .rst_cnt_notify                 (rst_cnt_notify_eth                                          ),
    .rst_cnt_notify_ack             (rst_cnt_notify_ack_eth                                      ),
    .rst_cnt_timeout                (rst_cnt_timeout_eth                                         ),
    .rst_cnt_notify_retry           (rst_cnt_retry_notify_eth                                    ),
    // registers
    .stat_reg_fsm                   (r_fsm_value_eth                                             ),
    // QSFP interface one lane --------------------------------------------------------------------
    // tx
    .qsfp_tx_tdata                  (axis_tx_tdata                                               ),
    .qsfp_tx_tkeep_user             (axis_tx_tkeep_user                                          ),
    .qsfp_tx_tlast                  (axis_tx_tlast                                               ),
    .qsfp_tx_tvalid                 (axis_tx_tvalid                                              ),
    .qsfp_tx_tready                 (axis_tx_tready                                              ),
    // rx
    .qsfp_rx_tdata                  (axis_rx_tdata                                               ),
    .qsfp_rx_tkeep_user             (axis_rx_tkeep_user                                          ),
    .qsfp_rx_tlast                  (axis_rx_tlast                                               ),
    .qsfp_rx_tvalid                 (axis_rx_tvalid                                              )
  );

  // ============================================================================================ //
  // Trace module
  // TODO:
  // must be able to read last frame and write a new packet into ethernet
  // ============================================================================================ //
  mhdma_trace # (
    .FIFO_DEPTH(FIFO_DEPTH),
    .SIM_ASSERT_CHK(0)
  ) mhdma_trace (
    // system interface
    .clk_control        (clk_eth_cfg),
    .s_rstn_control     (resetn_eth_cfg),
    .clk_mrmac          (clk_eth_mrmac),
    .s_rstn_mrmac       (resetn_eth_mrmac),
    // MRMAC RX interface
    .qsfp_rx_tdata      (axis_rx_tdata),
    .qsfp_rx_tkeep_user (axis_rx_tkeep_user),
    .qsfp_rx_tlast      (axis_rx_tlast),
    .qsfp_rx_tvalid     (axis_rx_tvalid),
    // MRMAC TX interface
    // .qsfp_tx_tdata      (axis_tx_tdata),
    // .qsfp_tx_tkeep_user (axis_tx_tkeep_user),
    // .qsfp_tx_tlast      (axis_tx_tlast),
    // .qsfp_tx_tvalid     (axis_tx_tvalid),
    // .qsfp_tx_tready     (axis_tx_tready),
    // register interface
    .r_nb_word          (r_nb_word),
    .r_wr_word          (r_wr_word),
    .r_wr_data_count    (r_wr_data_count),
    .r_rd_data_count    (r_rd_data_count),
    .r_rd_word          (r_rd_word),
    .read_ack           (read_ack),
    .write_ack          (write_ack),
    .tx_loop            (tx_loop),
    .rx_to_tx           (rx_to_tx),
    .reset_registers    (reset_registers),
    // debug interface
    .clk_cnt_out         (clk_cnt_out),
    .valid_words_out     (valid_words_out),
    .sop_cnt_out         (sop_cnt_out),
    .trigger_rd_cnt_out  (trigger_rd_cnt_out),
    .tx_wr_en_cnt        (tx_wr_en_cnt),
    .stat_tx_empty       (stat_tx_empty),
    .stat_tx_rd_rst_busy (stat_tx_rd_rst_busy),
    .stat_tx_data_valid  (stat_tx_data_valid),
    .stat_tx_full        (stat_tx_full),
    .stat_tx_wr_rst_busy (stat_tx_wr_rst_busy),
    .stat_qsfp_tx_tready (stat_qsfp_tx_tready),
    .stat_rd_data_count  (stat_rd_data_count)
  );

  // ============================================================================================ //
  // AXI4-stream switch
  // ==================
  // depending on line_sel signal, selects and outputs the correct line
  // ============================================================================================ //
  // Rx Link
  assign axis_rx_tdata      = qsfp_rx_tdata[line_sel];
  assign axis_rx_tkeep_user = qsfp_rx_tkeep_user[line_sel];
  assign axis_rx_tlast      = qsfp_rx_tlast[line_sel];
  assign axis_rx_tvalid     = qsfp_rx_tvalid[line_sel];

  // TX link
  assign axis_tx_tready = qsfp_tx_tready[line_sel];

  generate
    for (genvar i = 0; i < QSFP_LANE_NB; i++) begin
      assign qsfp_tx_tdata[i]       = (line_sel == i) ? axis_tx_tdata      : 'h0;
      assign qsfp_tx_tkeep_user[i]  = (line_sel == i) ? axis_tx_tkeep_user : 'h0;
      assign qsfp_tx_tlast[i]       = (line_sel == i) ? axis_tx_tlast      : 'h0;
      assign qsfp_tx_tvalid[i]      = (line_sel == i) ? axis_tx_tvalid     : 'h0;
    end
  endgenerate

endmodule
