// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Bridge between HBM and MRMAC IP
// ----------------------------------------------------------------------------------------------
// includes other module for all the control for notify, read request and ciphertext emission
// ==============================================================================================

module mhdma_bridge
  import mhdma_pkg::*;                            // multi-hpu-dma
  import axi_if_shell_axil_pkg::*;                // REG_DATA_W
  import axi_if_common_param_pkg::*;              // general axi4
  import axi_if_eth_axi_pkg::*;                   // AXI ethernet
#() (
  // Ethernet configuration interface -----------------------------------------
  input  logic                                    clk_cfg,
  input  logic                                    resetn_cfg,
  // Ethernet fast clock interface --------------------------------------------
  input  logic                                    clk_mrmac,
  input  logic                                    resetn_mrmac,
  // Axi4 interface for NMU ---------------------------------------------------
  // Read channel
  output logic [ETH_PC-1:0][   AXI4_ID_W-1:0]     m_axi4_arid,      // unused
  output logic [ETH_PC-1:0][  AXI4_ADD_W-1:0]     m_axi4_araddr,
  output logic [ETH_PC-1:0][  AXI4_LEN_W-1:0]     m_axi4_arlen,
  output logic [ETH_PC-1:0][ AXI4_SIZE_W-1:0]     m_axi4_arsize,
  output logic [ETH_PC-1:0][AXI4_BURST_W-1:0]     m_axi4_arburst,
  output logic [ETH_PC-1:0]                       m_axi4_arvalid,
  input  logic [ETH_PC-1:0]                       m_axi4_arready,
  input  logic [ETH_PC-1:0][  AXI4_ID_W-1:0]      m_axi4_rid,       // unused
  input  logic [ETH_PC-1:0][AXI4_DATA_W-1:0]      m_axi4_rdata,
  input  logic [ETH_PC-1:0][AXI4_RESP_W-1:0]      m_axi4_rresp,     // unused
  input  logic [ETH_PC-1:0]                       m_axi4_rlast,
  input  logic [ETH_PC-1:0]                       m_axi4_rvalid,
  output logic [ETH_PC-1:0]                       m_axi4_rready,
  // Write channel
  output logic [ETH_PC-1:0][   AXI4_ID_W-1:0]     m_axi4_awid,
  output logic [ETH_PC-1:0][  AXI4_ADD_W-1:0]     m_axi4_awaddr,
  output logic [ETH_PC-1:0][  AXI4_LEN_W-1:0]     m_axi4_awlen,
  output logic [ETH_PC-1:0][ AXI4_SIZE_W-1:0]     m_axi4_awsize,
  output logic [ETH_PC-1:0][AXI4_BURST_W-1:0]     m_axi4_awburst,
  output logic [ETH_PC-1:0]                       m_axi4_awvalid,
  input  logic [ETH_PC-1:0]                       m_axi4_awready,
  output logic [ETH_PC-1:0][AXI4_DATA_W-1:0]      m_axi4_wdata,
  output logic [ETH_PC-1:0][AXI4_STRB_W-1:0]      m_axi4_wstrb,
  output logic [ETH_PC-1:0]                       m_axi4_wlast,
  output logic [ETH_PC-1:0]                       m_axi4_wvalid,
  input  logic [ETH_PC-1:0]                       m_axi4_wready,
  // Write response channel
  input  logic [ETH_PC-1:0][  AXI4_ID_W-1:0]      m_axi4_bid,
  input  logic [ETH_PC-1:0][AXI4_RESP_W-1:0]      m_axi4_bresp,
  input  logic [ETH_PC-1:0]                       m_axi4_bvalid,
  output logic [ETH_PC-1:0]                       m_axi4_bready,
  // regf interface -----------------------------------------------------------
  input  logic [NB_MAX_HPU-1:0][  REG_DATA_W-1:0] regf_hpu_ids,
  input  logic [    ETH_PC-1:0][2*REG_DATA_W-1:0] regf_ct_mem_addr,
  input  logic                 [  REG_DATA_W-1:0] regf_req_id,
  input  logic                 [  REG_DATA_W-1:0] regf_req_addr,
  output logic                 [  REG_DATA_W-1:0] regf_notify_payload,
  output logic                 [  REG_DATA_W-1:0] regf_read_payload,
  input  logic                 [  REG_DATA_W-1:0] regf_timeout_duration_notify,
  input  logic                 [  REG_DATA_W-1:0] regf_timeout_duration_read_req,
  // control ------------------------------------------------------------------
  input  logic                                    received_req,
  output logic                                    request_consumed,
  // statistics ---------------------------------------------------------------
  output logic [REG_DATA_W-1:0]                   stat_cnt_notify,
  output logic [REG_DATA_W-1:0]                   stat_cnt_notify_ack,
  output logic [REG_DATA_W-1:0]                   stat_cnt_notify_timeout,
  output logic [REG_DATA_W-1:0]                   stat_cnt_notify_retries,
  output logic [REG_DATA_W-1:0]                   stat_nb_write_complete_cnt,

  output logic [REG_DATA_W-1:0]                   stat_cnt_nack_received,
  output logic [REG_DATA_W-1:0]                   stat_cnt_notify_received,
  output logic [REG_DATA_W-1:0]                   stat_cnt_read_req_received,
  output logic [REG_DATA_W-1:0]                   stat_cnt_ce_received,

  output logic [ETH_PC-1:0][REG_DATA_W-1:0]       stat_nb_words_received_pc,
  output logic             [REG_DATA_W-1:0]       stat_nb_read_to_hbm,
  output logic             [REG_DATA_W-1:0]       stat_nb_ce_words_received,

  // timing
  output logic [REG_DATA_W-1:0]                   stat_t_notify_to_ack,
  output logic [REG_DATA_W-1:0]                   stat_t_rr_to_ce_received,
  output logic [REG_DATA_W-1:0]                   stat_t_ce_first_to_last_pkt,
  output logic [ETH_PC-1:0][REG_DATA_W-1:0]       stat_t_rr_wait_words_pc,

  // reset counters
  input  logic                                    rst_cnt_notify,
  input  logic                                    rst_cnt_notify_ack,
  input  logic                                    rst_cnt_notify_retry,
  input  logic                                    rst_cnt_timeout,
  input  logic                                    rst_cnt_nack_received,
  input  logic                                    rst_cnt_notify_received,
  input  logic                                    rst_cnt_read_req_received,
  input  logic                                    rst_cnt_ce_received,
  input  logic                                    rst_nb_read_to_hbm,
  input  logic [ETH_PC-1:0]                       rst_nb_words_received_pc,
  input  logic                                    rst_nb_ce_words_received,
  // registers
  output logic [REG_DATA_W-1:0]                   stat_reg_fsm,
  output logic [ETH_PC-1:0][2*REG_DATA_W-1:0]     stat_rr_phy_addr,
  // statistics ---------------------------------------------------------------
  input  logic                                    clear_interrupt_notify,
  output logic                                    interrupt_notify,
  input  logic                                    clear_interrupt_rr,
  output logic                                    interrupt_read_request,
  // QSFP system interface ----------------------------------------------------
  // == TX
  output logic [MRMAC_AXIS_W-1:0]                 qsfp_tx_tdata,
  output logic [MRMAC_TKEEP_W-1:0]                qsfp_tx_tkeep_user,
  output logic                                    qsfp_tx_tlast,
  output logic                                    qsfp_tx_tvalid,
  input  logic                                    qsfp_tx_tready,
  // == RX
  input  logic [MRMAC_AXIS_W-1:0]                 qsfp_rx_tdata,
  input  logic [MRMAC_TKEEP_W-1:0]                qsfp_rx_tkeep_user,
  input  logic                                    qsfp_rx_tlast,
  input  logic                                    qsfp_rx_tvalid
);

  // =========================================================================================== //
  // localparam
  // =========================================================================================== //
  localparam int CDC_SYNC_STAGES = 2;

  //TODO: review theses two values, if not divisible by 32 it will be wrong
  localparam [3:0] PC_STRIDE          = 'hB;
  localparam int PC_CT_BYTES [ETH_PC] = '{'h2000, 'h2020};

  localparam int MAX_BURST_SIZE = PAGE_BYTES/AXI4_DATA_BYTES;

  localparam int PC_NB_WORDS [ETH_PC] = compute_nb_words(PC_CT_BYTES);
  localparam int PC_NB_BURST [ETH_PC] = compute_nb_bursts(PC_NB_WORDS, MAX_BURST_SIZE);
  localparam int PC_REMAINS  [ETH_PC] = compute_remaining_words(PC_NB_WORDS, MAX_BURST_SIZE);
  localparam int PC_NB_TRANS [ETH_PC] = compute_nb_transactions(PC_REMAINS,PC_NB_BURST);

  // statistics/debug that needs to be propagated to regif
  logic [2:0] stat_fsm_formatter;
  logic [1:0] stat_fsm_notify_rx;
  logic [1:0] stat_fsm_cem;
  logic [1:0] stat_fsm_notify;
  logic [1:0] stat_fsm_read_req;

  // =========================================================================================== //
  // CDC from regf to mrmac clock
  // =========================================================================================== //
  // theses signals are quasi static: they should move rarely
  logic [CDC_SYNC_STAGES-1:0][NB_MAX_HPU-1:0][REG_DATA_W-1:0] hpu_ids_cdc;
  logic                      [NB_MAX_HPU-1:0][REG_DATA_W-1:0] hpu_ids; // just for naming

  generate
    for (genvar gen_i_id = 0; gen_i_id < NB_MAX_HPU; gen_i_id++)
      always_ff @(posedge clk_mrmac)
        hpu_ids_cdc[0][gen_i_id] <= regf_hpu_ids[gen_i_id];

    for (genvar gen_i_cdc = 1; gen_i_cdc < CDC_SYNC_STAGES ; gen_i_cdc = gen_i_cdc + 1)
      for (genvar gen_i_id = 0; gen_i_id < NB_MAX_HPU; gen_i_id++)
        always_ff @(posedge clk_mrmac)
          hpu_ids_cdc[gen_i_cdc][gen_i_id] <= hpu_ids_cdc[gen_i_cdc-1][gen_i_id];
  endgenerate

  // ==============================================================================================
  // hpu identification
  // ==============================================================================================
  logic [NB_MAX_HPU-1:0][HPU_ID_W-1:0]   hpu_id_table;
  logic [NB_MAX_HPU-1:0][MAC_ADDR_W-1:0] hpu_mac_table;
  logic [NB_MAX_HPU-1:0]                 one_hot_id;

  assign hpu_ids = hpu_ids_cdc[CDC_SYNC_STAGES-1];

  generate
    for (genvar i=0; i<NB_MAX_HPU; i++) begin
      always_ff @(posedge clk_mrmac) begin : hpu_id_table_creation
        hpu_id_table[i]  <= hpu_ids[i][HPU_ID_W+MAC_ADDR_W-1:MAC_ADDR_W];
        hpu_mac_table[i] <= hpu_ids[i][MAC_ADDR_W-1:0];
        one_hot_id[i]    <= hpu_ids[i][31];
      end
    end
  endgenerate

  // if ever two hpu ids are set as "current", raise an error
  // when one_hot_id is all zeros, we cannot conclude if there is an error or not
  // TODO: if half is ones and the rest are zeros, error not raised
  logic error_id_def;
  always_ff @(posedge clk_mrmac) begin : error_on_hpu_id
    if (~resetn_mrmac) begin
      error_id_def <= 1'b0;
    end else begin
      error_id_def <= (one_hot_id==0) ? 'b0: ~ (^one_hot_id);
    end
  end

  // just to simplify notations
  logic [          HPU_ID_W-1:0] current_hpu_idD;
  logic [        MAC_ADDR_W-1:0] current_hpu_macD;
  logic [$clog2(NB_MAX_HPU)-1:0] hpu_index;

  always_comb begin
      hpu_index = '0;
      for (int i = 0; i < NB_MAX_HPU; i++)
          if (one_hot_id[i])
              hpu_index = i;
  end

  assign current_hpu_macD = error_id_def | (one_hot_id==0)? 'h0 : hpu_mac_table[hpu_index];
  assign current_hpu_idD  = error_id_def | (one_hot_id==0)? 'h0 : hpu_id_table[hpu_index];

  // theses two registers are here to ease P&R
  logic [  HPU_ID_W-1:0] current_hpu_id;
  logic [MAC_ADDR_W-1:0] current_hpu_mac;

  always_ff @(posedge clk_mrmac) begin
    current_hpu_id  <= current_hpu_idD;
    current_hpu_mac <= current_hpu_macD;
  end

  // ==============================================================================================
  // Core Instances of mhdma
  // ==============================================================================================
  // Control interface
  logic ct_emission_allowed;
  logic notify_ack_allowed;
  logic read_request_allowed;
  logic notify_request_allowed;

  logic new_ct_emission_request_pending;
  logic new_notify_ack_pending;
  logic new_read_request_pending;
  logic new_notify_request_pending;

  logic notify_ack_received;
  logic notify_request_received;
  logic read_request_received;
  logic ciphertext_emission_received;

  logic format_packets_emitted;
  logic format_ct_received;

  // master -> formatter
  header_t format_header;
  logic retry_notify;
  logic retry_read_request;

  // formatter -> master
  logic notify_sent;
  logic rreq_sent;

  header_t decoded_header;

  // Slave payload and header for ciphertext emission
  logic [NRX_WIDTH-1:0]     nrx_cmd_payload;
  logic                     nrx_cmd_valid;

  logic                     notify_ack_sent;
  header_t                  ce_header;
  logic [ MRMAC_AXIS_W-1:0] ce_payload;
  logic                     ce_ready;
  logic                     ce_valid;

  // payload for ciphertext reception
  logic [MRMAC_AXIS_W-1:0]  decoder_rx_tdata;
  logic                     decoder_rx_tvalid;
  logic                     decoder_rx_tlast;
  logic                     cerx_reception_ready;

  // Master module does the controls for sending read request and Notifies requests
  mhdma_master #(
    .PC_STRIDE                       (PC_STRIDE                               ),
    .PC_NB_WORDS                     (PC_NB_WORDS                             ),
    .PC_REMAINS                      (PC_REMAINS                              ),
    .PC_NB_WRITES                    (PC_NB_TRANS                             )
  ) mhdma_master (
    // Ethernet configuration interface ---------------------------------------
    .clk_cfg                         (clk_cfg                                 ),
    .resetn_cfg                      (resetn_cfg                              ),
    // Axi4 interface ---------------------------------------------------------
    .m_axi4_awid                     (m_axi4_awid                             ),
    .m_axi4_awaddr                   (m_axi4_awaddr                           ),
    .m_axi4_awlen                    (m_axi4_awlen                            ),
    .m_axi4_awsize                   (m_axi4_awsize                           ),
    .m_axi4_awburst                  (m_axi4_awburst                          ),
    .m_axi4_awvalid                  (m_axi4_awvalid                          ),
    .m_axi4_awready                  (m_axi4_awready                          ),
    .m_axi4_wdata                    (m_axi4_wdata                            ),
    .m_axi4_wstrb                    (m_axi4_wstrb                            ),
    .m_axi4_wlast                    (m_axi4_wlast                            ),
    .m_axi4_wvalid                   (m_axi4_wvalid                           ),
    .m_axi4_wready                   (m_axi4_wready                           ),
    .m_axi4_bid                      (m_axi4_bid                              ),
    .m_axi4_bresp                    (m_axi4_bresp                            ),
    .m_axi4_bvalid                   (m_axi4_bvalid                           ),
    .m_axi4_bready                   (m_axi4_bready                           ),
    // Ethernet fast clock interface ------------------------------------------
    .clk_mrmac                       (clk_mrmac                               ),
    .resetn_mrmac                    (resetn_mrmac                            ),
    // regf interface ---------------------------------------------------------
    .regf_ct_mem_addr                (regf_ct_mem_addr                        ),
    .regf_req_id                     (regf_req_id                             ),
    .regf_req_addr                   (regf_req_addr                           ),
    .regf_read_payload               (regf_read_payload                       ),
    .regf_timeout_duration_notify    (regf_timeout_duration_notify            ),
    .regf_timeout_duration_read_req  (regf_timeout_duration_read_req          ),
    // register control -------------------------------------------------------
    .received_req                    (received_req                            ),
    .request_consumed                (request_consumed                        ),
    // statistics -------------------------------------------------------------
    // counters
    .stat_cnt_notify                 (stat_cnt_notify                         ),
    .stat_cnt_notify_ack             (stat_cnt_notify_ack                     ),
    .stat_cnt_notify_timeout         (stat_cnt_notify_timeout                 ),
    .stat_cnt_notify_retries         (stat_cnt_notify_retries                 ),
    .stat_nb_ce_words_received       (stat_nb_ce_words_received               ),
    .stat_nb_write_complete_cnt      (stat_nb_write_complete_cnt              ),
    // timing
    .stat_t_notify_to_ack            (stat_t_notify_to_ack                    ),
    .stat_t_rr_to_ce_received        (stat_t_rr_to_ce_received                ),
    // reset counters
    .rst_cnt_notify                  (rst_cnt_notify                          ),
    .rst_cnt_notify_ack              (rst_cnt_notify_ack                      ),
    .rst_cnt_notify_retry            (rst_cnt_notify_retry                    ),
    .rst_cnt_timeout                 (rst_cnt_timeout                         ),
    .rst_nb_ce_words_received        (rst_nb_ce_words_received                ),
    // fsms
    .stat_fsm_notify                 (stat_fsm_notify                         ),
    .stat_fsm_read_req               (stat_fsm_read_req                       ),
    // flags ------------------------------------------------------------------
    .read_request_allowed            (read_request_allowed                    ),
    .notify_request_allowed          (notify_request_allowed                  ),
    .new_read_request_pending        (new_read_request_pending                ),
    .new_notify_request_pending      (new_notify_request_pending              ),
    .notify_ack_received             (notify_ack_received                     ),
    .cerx_reception_ready            (cerx_reception_ready                    ),
    // payload from decoder ---------------------------------------------------
    .rx_tdata                        (decoder_rx_tdata                        ),
    .rx_tvalid                       (decoder_rx_tvalid                       ),
    .rx_tlast                        (decoder_rx_tlast                        ),
    // interrupt --------------------------------------------------------------
    .clear_interrupt_rr              (clear_interrupt_rr                      ),
    .interrupt_read_request          (interrupt_read_request                  ),
    // formatter interface ----------------------------------------------------
    .format_notify_sent              (notify_sent                             ),
    .format_rreq_sent                (rreq_sent                               ),
    .format_header                   (format_header                           ),
    .format_retry_notify             (retry_notify                            ),
    .format_retry_read_request       (retry_read_request                      ),
    .packets_received                (format_ct_received                      ),
    // header interface -------------------------------------------------------
    .decoded_header                  (decoded_header                          ),
    .error_packet_id_mismatch        (/* UNUSED */                            )
  );

  // Slave module does the control for Notify ack and ciphertext emission
  mhdma_slave # (
    .CDC_SYNC_STAGES                (CDC_SYNC_STAGES                          ),
    .MAX_BURST_SIZE                 (MAX_BURST_SIZE                           ),
    .PC_STRIDE                      (PC_STRIDE                                ),
    .PC_NB_WORDS                    (PC_NB_WORDS                              ),
    .PC_REMAINS                     (PC_REMAINS                               ),
    .PC_NB_READS                    (PC_NB_TRANS                              )
  ) mhdma_slave (
    // Ethernet configuration interface ---------------------------------------
    .clk_cfg                        (clk_cfg                                  ),
    .resetn_cfg                     (resetn_cfg                               ),
    // Ethernet fast clock interface ------------------------------------------
    .clk_mrmac                      (clk_mrmac                                ),
    .resetn_mrmac                   (resetn_mrmac                             ),
    // regf interface ---------------------------------------------------------
    .regf_ct_mem_addr               (regf_ct_mem_addr                         ),
    .regf_notify_payload            (regf_notify_payload                      ),
    // header interface -------------------------------------------------------
    .decoded_header                 (decoded_header                           ),
    // command interface ------------------------------------------------------
    .notify_request_received        (notify_request_received                  ),
    .read_request_received          (read_request_received                    ),
    .new_notify_ack_pending         (new_notify_ack_pending                   ),
    .new_ct_emission_request_pending(new_ct_emission_request_pending          ),
    .notify_ack_allowed             (notify_ack_allowed                       ),
    .ct_emission_allowed            (ct_emission_allowed                      ),
    // formatter ---------------------------------------------------------------
    .ct_emission_finished           (format_packets_emitted                   ),
    // notify ack payload -----------------------------------------------------
    .nrx_cmd_payload                (nrx_cmd_payload                          ),
    .nrx_cmd_valid                  (nrx_cmd_valid                            ),
    .notify_ack_sent                (notify_ack_sent                          ),
    .ce_header                      (ce_header                                ),
    .ce_payload                     (ce_payload                               ),
    .ce_ready                       (ce_ready                                 ),
    .ce_valid                       (ce_valid                                 ),
    // statistics -------------------------------------------------------------
    // counters
    .stat_nb_read_to_hbm            (stat_nb_read_to_hbm                      ),
    .stat_nb_words_received_pc      (stat_nb_words_received_pc                ),
    .stat_t_rr_wait_words_pc        (stat_t_rr_wait_words_pc                  ),
    // rst
    .rst_nb_read_to_hbm             (rst_nb_read_to_hbm                       ),
    .rst_nb_words_received_pc       (rst_nb_words_received_pc                 ),
    // register
    .stat_fsm_notify_rx             (stat_fsm_notify_rx                       ),
    .stat_fsm_cem                   (stat_fsm_cem                             ),
    .stat_rr_phy_addr               (stat_rr_phy_addr                         ),
    // AXI4-4 full read interface ---------------------------------------------
    .m_axi4_araddr                  (m_axi4_araddr                            ),
    .m_axi4_arlen                   (m_axi4_arlen                             ),
    .m_axi4_arsize                  (m_axi4_arsize                            ),
    .m_axi4_arburst                 (m_axi4_arburst                           ),
    .m_axi4_arvalid                 (m_axi4_arvalid                           ),
    .m_axi4_arready                 (m_axi4_arready                           ),

    .m_axi4_rdata                   (m_axi4_rdata                             ),
    .m_axi4_rlast                   (m_axi4_rlast                             ),
    .m_axi4_rvalid                  (m_axi4_rvalid                            ),
    .m_axi4_rready                  (m_axi4_rready                            ),
    // interrupt interface ----------------------------------------------------
    .clear_interrupt_notify         (clear_interrupt_notify                   ),
    .interrupt_notify               (interrupt_notify                         )
  );

  // The decoder gathers axi-stream RX and decodes the received command
  mhdma_decoder mhdma_decoder (
    // Ethernet fast clock interface ------------------------------------------
    .clk_mrmac                   (clk_mrmac                                   ),
    .resetn_mrmac                (resetn_mrmac                                ),
    // Command interface ------------------------------------------------------
    .notify_ack_received         (notify_ack_received                         ),
    .notify_request_received     (notify_request_received                     ),
    .read_request_received       (read_request_received                       ),
    .ciphertext_emission_received(ciphertext_emission_received                ),
    // Header information -----------------------------------------------------
    .current_hpu_mac             (current_hpu_mac                             ),
    .rx_header                   (decoded_header                              ),
    // statistics -------------------------------------------------------------
    .stat_t_ce_first_to_last_pkt (stat_t_ce_first_to_last_pkt                 ),

    .stat_cnt_nack_received      (stat_cnt_nack_received                      ),
    .stat_cnt_notify_received    (stat_cnt_notify_received                    ),
    .stat_cnt_read_req_received  (stat_cnt_read_req_received                  ),
    .stat_cnt_ce_received        (stat_cnt_ce_received                        ),

    .rst_cnt_nack_received       (rst_cnt_nack_received                       ),
    .rst_cnt_notify_received     (rst_cnt_notify_received                     ),
    .rst_cnt_read_req_received   (rst_cnt_read_req_received                   ),
    .rst_cnt_ce_received         (rst_cnt_ce_received                         ),
    // RX payload -------------------------------------------------------------
    .rx_tdata_out                (decoder_rx_tdata                            ),
    .rx_tvalid_out               (decoder_rx_tvalid                           ),
    .rx_tlast_out                (decoder_rx_tlast                            ),
    // QSFP RX interface ------------------------------------------------------
    .qsfp_rx_tdata               (qsfp_rx_tdata                               ),
    .qsfp_rx_tkeep_user          (qsfp_rx_tkeep_user                          ),
    .qsfp_rx_tlast               (qsfp_rx_tlast                               ),
    .qsfp_rx_tvalid              (qsfp_rx_tvalid                              )
  );

  // the formatter gathers commands from master & slave module and sends it to axis
  mhdma_formatter mhdma_formatter (
    // Ethernet fast clock interface ------------------------------------------
    .clk_mrmac                       (clk_mrmac                               ),
    .resetn_mrmac                    (resetn_mrmac                            ),
    // Bridge interface -------------------------------------------------------
    .hpu_mac_table                   (hpu_mac_table                           ),
    .current_hpu_id                  (current_hpu_id                          ),
    .current_hpu_mac                 (current_hpu_mac                         ),
    // Command interface ------------------------------------------------------
    .ct_emission_allowed             (ct_emission_allowed                     ),
    .notify_ack_allowed              (notify_ack_allowed                      ),
    .read_request_allowed            (read_request_allowed                    ),
    .notify_request_allowed          (notify_request_allowed                  ),
    .new_ct_emission_request_pending (new_ct_emission_request_pending         ),
    .new_notify_ack_pending          (new_notify_ack_pending                  ),
    .new_read_request_pending        (new_read_request_pending                ),
    .new_notify_request_pending      (new_notify_request_pending              ),
    .cerx_reception_ready            (cerx_reception_ready                    ),
    .ce_received                     (format_ct_received                      ),
    .nack_received                   (notify_ack_received                     ),
    // statistics -------------------------------------------------------------
    // registers
    .stat_fsm_formatter              (stat_fsm_formatter                      ),
    // slave interface --------------------------------------------------------
    .packets_emitted                 (format_packets_emitted                  ),
    // master interface -------------------------------------------------------
    .format_header                   (format_header                           ),
    .retry_notify                    (retry_notify                            ),
    .retry_read_request              (retry_read_request                      ),
    .notify_sent                     (notify_sent                             ),
    .rreq_sent                       (rreq_sent                               ),
    // slave interface --------------------------------------------------------
    .nrx_cmd_payload                 (nrx_cmd_payload                         ),
    .nrx_cmd_valid                   (nrx_cmd_valid                           ),
    .notify_ack_sent                 (notify_ack_sent                         ),
    .ce_header               (ce_header                       ),
    .ce_payload                      (ce_payload                              ),
    .ce_ready                        (ce_ready                                ),
    .ce_valid                        (ce_valid                                ),
    // QSFP TX interface ------------------------------------------------------
    .qsfp_tx_tdata                   (qsfp_tx_tdata                           ),
    .qsfp_tx_tkeep_user              (qsfp_tx_tkeep_user                      ),
    .qsfp_tx_tlast                   (qsfp_tx_tlast                           ),
    .qsfp_tx_tvalid                  (qsfp_tx_tvalid                          ),
    .qsfp_tx_tready                  (qsfp_tx_tready                          )
  );

  // ==============================================================================================
  // Errors
  // ==============================================================================================
  // Errors on RX path ---------------------------------------------------------------------------
  // logic error_rx_tkeep;
  // logic error_rx_unexpected_size_b;

  // always_ff @(posedge clk_mrmac) begin
  //   if (~resetn_mrmac) begin
  //     error_rx_tkeep <= 1'b0;
  //   end else begin
  //     if (qsfp_rx_tvalid & (qsfp_rx_tkeep_user != 'hff))
  //       error_rx_tkeep <= 1'b1;
  //   end
  // end

  // always_ff @(posedge clk_mrmac) begin
  //   if (~resetn_mrmac) begin
  //     error_rx_unexpected_size_b <= 1'b0;
  //   end else begin
  //     if ((rx_counter == 2) & (rx_size_b != SIZE_B))
  //       error_rx_unexpected_size_b <= 1'b1;
  //   end
  // end

  // =========================================================================================== //
  // Statistics
  // =========================================================================================== //
  assign stat_reg_fsm = {12'b0, 2'b0, stat_fsm_formatter,  2'b0,stat_fsm_read_req, 2'b0,stat_fsm_cem, 2'b0,stat_fsm_notify_rx,  2'b0,stat_fsm_notify};

  // =========================================================================================== //
  // Error agreggation
  // =========================================================================================== //
  // error_id_def: Definition of HPUs are not correct, several are defined as current
  // error_packet_id_mismatch: sec_num received is unexpected


endmodule
