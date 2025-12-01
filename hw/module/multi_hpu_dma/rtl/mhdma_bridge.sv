// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Ethernet bridge to PL and HBM
// ----------------------------------------------------------------------------------------------
//
// ==============================================================================================

module mhdma_bridge
  import mhdma_pkg::*;
  import axi_if_shell_axil_pkg::*;
  import hpu_regif_core_eth_2in3_pkg::*;
  import axi_if_common_param_pkg::*;
  import axi_if_eth_axi_pkg::*;
#() (
  // Ethernet configuration interface -----------------------------------------
  input  logic                                    clk_cfg,
  input  logic                                    resetn_cfg,
  // Ethernet fast clock interface --------------------------------------------
  input  logic                                    clk_mrmac,
  input  logic                                    resetn_mrmac,
  // Axi4 interface for NMU ---------------------------------------------------
  // Read channel
  output logic [ETH_PC-1:0][   AXI4_ID_W-1:0]     m_axi4_arid,
  output logic [ETH_PC-1:0][  AXI4_ADD_W-1:0]     m_axi4_araddr,
  output logic [ETH_PC-1:0][  AXI4_LEN_W-1:0]     m_axi4_arlen,
  output logic [ETH_PC-1:0][ AXI4_SIZE_W-1:0]     m_axi4_arsize,
  output logic [ETH_PC-1:0][AXI4_BURST_W-1:0]     m_axi4_arburst,
  output logic [ETH_PC-1:0]                       m_axi4_arvalid,
  input  logic [ETH_PC-1:0]                       m_axi4_arready,
  input  logic [ETH_PC-1:0][  AXI4_ID_W-1:0]      m_axi4_rid,
  input  logic [ETH_PC-1:0][AXI4_DATA_W-1:0]      m_axi4_rdata,
  input  logic [ETH_PC-1:0][AXI4_RESP_W-1:0]      m_axi4_rresp,
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
  // control ------------------------------------------------------------------
  input  logic                                    received_req,
  output logic                                    request_consumed,
  // statistics ---------------------------------------------------------------
  output logic [15:0]                             stat_cnt_notify_ack,
  output logic [15:0]                             stat_cnt_notify_read,
  // reset counters
  input  logic                                    rst_cnt_notify,
  // statistics ---------------------------------------------------------------
  input  logic                                    clear_interrupt_notify,
  output logic                                    interrupt_notify,
  output logic                                    interrupt_read_request,
  input  logic [15:0]                             timeout_duration,
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
  localparam [3:0] PC_STRIDE                = 'hB;
  localparam [ETH_PC-1:0][15:0] PC_CT_BYTES = '{'h2000, 'h2020};

  localparam int MAX_BURST_SIZE = PAGE_BYTES/AXI4_DATA_BYTES;

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
  logic [          HPU_ID_W-1:0] current_hpu_id;
  logic [        MAC_ADDR_W-1:0] current_hpu_mac;
  logic [$clog2(NB_MAX_HPU)-1:0] hpu_index;

  always_comb begin
      hpu_index = '0;
      for (int i = 0; i < NB_MAX_HPU; i++)
          if (one_hot_id[i])
              hpu_index = i;
  end

  assign current_hpu_mac = error_id_def | (one_hot_id==0)? 'h0 : hpu_mac_table[hpu_index];
  assign current_hpu_id  = error_id_def | (one_hot_id==0)? 'h0 : hpu_id_table[hpu_index];

  // theses two registers are here to ease P&R
  logic [  HPU_ID_W-1:0] current_hpu_idD;
  logic [MAC_ADDR_W-1:0] current_hpu_macD;

  always_ff @(posedge clk_mrmac) begin
    current_hpu_idD  <= current_hpu_id;
    current_hpu_macD <= current_hpu_mac;
  end

  // ==============================================================================================
  // Core Instances of mhdma
  // ==============================================================================================
  logic                     ct_emission_allowed;
  logic                     notify_ack_allowed;
  logic                     read_request_allowed;
  logic                     notify_request_allowed;

  logic                     new_ct_emission_request_pending;
  logic                     new_notify_ack_pending;
  logic                     new_read_request_pending;
  logic                     new_notify_request_pending;

  logic                     notify_ack_received;
  logic                     notify_request_received;
  logic                     read_request_received;
  logic                     ciphertext_emission_received;

  logic [DST_ADDR_W-1:0]    master_dst_addr;
  logic [SRC_ADDR_W-1:0]    master_src_addr;
  logic [  SIZE_B_W-1:0]    master_size_b;
  logic [  REQ_ID_W-1:0]    master_req_id;
  logic [  IOP_ID_W-1:0]    master_iop_id;
  logic [  HPU_ID_W-1:0]    master_hpu_id;
  logic                     master_valid;

  logic [MAC_ADDR_W-1:0]    rx_dst_mac_addr;
  logic [SEQ_NUM_W-1:0]     rx_sec_num;
  logic [HPU_ID_W-1:0]      rx_hpu_id;
  logic [REQ_ID_W-1:0]      rx_req_id;
  logic [MAC_ADDR_W-1:0]    rx_src_mac_addr;
  logic [SIZE_B_W-1:0]      rx_size_b;
  logic [IOP_ID_W-1:0]      rx_iop_id;
  logic [SRC_ADDR_W-1:0]    rx_ct_src_addr;
  logic [DST_ADDR_W-1:0]    rx_ct_dst_addr;
  logic                     rx_header_valid;

  logic [MRMAC_AXIS_W-1:0]  format_tdata;
  logic [MRMAC_TKEEP_W-1:0] format_tkeep_user;
  logic                     format_tlast;
  logic                     format_tvalid;
  logic                     format_tready;
  // == RX
  logic [MRMAC_AXIS_W-1:0]  decode_tdata;
  logic [MRMAC_TKEEP_W-1:0] decode_tkeep_user;
  logic                     decode_tlast;
  logic                     decode_tvalid;

  logic [NRX_WIDTH-1:0]     nrx_cmd_payload;
  logic                     nrx_valid;
  logic                     notify_ack_sent;
  logic [    CEH_WIDTH-1:0] ce_header_payload;
  logic                     ce_start_of_batch;
  logic [ MRMAC_AXIS_W-1:0] ce_payload;
  logic                     ce_ready;
  logic                     ce_valid;

  mhdma_master mhdma_master (
    // Ethernet configuration interface ---------------------------------------
    .clk_cfg                   (clk_cfg                                       ),
    .resetn_cfg                (resetn_cfg                                    ),
    // Ethernet fast clock interface ------------------------------------------
    .clk_mrmac                 (clk_mrmac                                     ),
    .resetn_mrmac              (resetn_mrmac                                  ),
    // regf interface ---------------------------------------------------------
    .regf_ct_mem_addr          (regf_ct_mem_addr                              ),
    .regf_req_id               (regf_req_id                                   ),
    .regf_req_addr             (regf_req_addr                                 ),
    // register control -------------------------------------------------------
    .received_req              (received_req                                  ),
    .request_consumed          (request_consumed                              ),
    // flags ------------------------------------------------------------------
    .read_request_allowed      (read_request_allowed                          ),
    .notify_request_allowed    (notify_request_allowed                        ),
    .new_read_request_pending  (new_read_request_pending                      ),
    .new_notify_request_pending(new_notify_request_pending                    ),
    .notify_ack_received       (notify_ack_received                           ),
    // from decoder -----------------------------------------------------------
    .master_dst_addr           (master_dst_addr                               ),
    .master_src_addr           (master_src_addr                               ),
    .master_size_b             (master_size_b                                 ),
    .master_req_id             (master_req_id                                 ),
    .master_iop_id             (master_iop_id                                 ),
    .master_hpu_id             (master_hpu_id                                 ),
    .master_header_valid       (master_valid                                  )
  );

  mhdma_slave # (
    .CDC_SYNC_STAGES                (CDC_SYNC_STAGES                          ),
    .MAX_BURST_SIZE                 (MAX_BURST_SIZE                           ),
    .PC_CT_BYTES                    (PC_CT_BYTES                              ),
    .PC_STRIDE                      (PC_STRIDE                                )
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
    .rx_dst_mac_addr                (rx_dst_mac_addr                          ),
    .rx_sec_num                     (rx_sec_num                               ),
    .rx_hpu_id                      (rx_hpu_id                                ),
    .rx_req_id                      (rx_req_id                                ),
    .rx_src_mac_addr                (rx_src_mac_addr                          ),
    .rx_size_b                      (rx_size_b                                ),
    .rx_iop_id                      (rx_iop_id                                ),
    .rx_ct_src_addr                 (rx_ct_src_addr                           ),
    .rx_ct_dst_addr                 (rx_ct_dst_addr                           ),
    .rx_header_valid                (rx_header_valid                          ),
    // command interface ------------------------------------------------------
    .notify_request_received        (notify_request_received                  ),
    .read_request_received          (read_request_received                    ),
    .new_notify_ack_pending         (new_notify_ack_pending                   ),
    .new_ct_emission_request_pending(new_ct_emission_request_pending          ),
    .notify_ack_allowed             (notify_ack_allowed                       ),
    .ct_emission_allowed            (ct_emission_allowed                      ),
    // notify ack payload -----------------------------------------------------
    .nrx_cmd_payload                (nrx_cmd_payload                          ),
    .nrx_valid                      (nrx_valid                                ),
    .notify_ack_sent                (notify_ack_sent                          ),
    .ce_header_payload              (ce_header_payload                        ),
    .ce_start_of_batch              (ce_start_of_batch                        ),
    .ce_payload                     (ce_payload                               ),
    .ce_ready                       (ce_ready                                 ),
    .ce_valid                       (ce_valid                                 ),
    // AXI4-4 full read interface ---------------------------------------------
    .m_axi4_arid                    (m_axi4_arid                              ),
    .m_axi4_araddr                  (m_axi4_araddr                            ),
    .m_axi4_arlen                   (m_axi4_arlen                             ),
    .m_axi4_arsize                  (m_axi4_arsize                            ),
    .m_axi4_arburst                 (m_axi4_arburst                           ),
    .m_axi4_arvalid                 (m_axi4_arvalid                           ),
    .m_axi4_arready                 (m_axi4_arready                           ),
    .m_axi4_rid                     (m_axi4_rid                               ),
    .m_axi4_rdata                   (m_axi4_rdata                             ),
    .m_axi4_rresp                   (m_axi4_rresp                             ),
    .m_axi4_rlast                   (m_axi4_rlast                             ),
    .m_axi4_rvalid                  (m_axi4_rvalid                            ),
    .m_axi4_rready                  (m_axi4_rready                            ),
    // interrupt interface ----------------------------------------------------
    .clear_interrupt_notify         (clear_interrupt_notify                   ),
    .interrupt_notify               (interrupt_notify                         )
  );

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
    .current_hpu_mac             (current_hpu_macD                            ),
    .rx_dst_mac_addr             (rx_dst_mac_addr                             ),
    .rx_sec_num                  (rx_sec_num                                  ),
    .rx_hpu_id                   (rx_hpu_id                                   ),
    .rx_req_id                   (rx_req_id                                   ),
    .rx_src_mac_addr             (rx_src_mac_addr                             ),
    .rx_size_b                   (rx_size_b                                   ),
    .rx_iop_id                   (rx_iop_id                                   ),
    .rx_ct_src_addr              (rx_ct_src_addr                              ),
    .rx_ct_dst_addr              (rx_ct_dst_addr                              ),
    .rx_header_valid             (rx_header_valid                             ),
     // RX payload ------------------------------------------------------------
    .rx_tdata                    (rx_tdata                                    ),
    .rx_tsop                     (rx_tsop                                     ),
    .rx_tlast                    (rx_tlast                                    ),
    .rx_tvalid                   (rx_tvalid                                   ),
    // QSFP RX interface ------------------------------------------------------
    .qsfp_rx_tdata               (qsfp_rx_tdata                               ),
    .qsfp_rx_tkeep_user          (qsfp_rx_tkeep_user                          ),
    .qsfp_rx_tlast               (qsfp_rx_tlast                               ),
    .qsfp_rx_tvalid              (qsfp_rx_tvalid                              )
  );

  mhdma_formatter mhdma_formatter (
    // Ethernet fast clock interface ------------------------------------------
    .clk_mrmac                      (clk_mrmac                                ),
    .resetn_mrmac                   (resetn_mrmac                             ),
    // Bridge interface -------------------------------------------------------
    .hpu_mac_table                  (hpu_mac_table                            ),
    .current_hpu_id                 (current_hpu_idD                          ),
    .current_hpu_mac                (current_hpu_macD                         ),
    // Command interface ------------------------------------------------------
    .ct_emission_allowed            (ct_emission_allowed                      ),
    .notify_ack_allowed             (notify_ack_allowed                       ),
    .read_request_allowed           (read_request_allowed                     ),
    .notify_request_allowed         (notify_request_allowed                   ),
    .new_ct_emission_request_pending(new_ct_emission_request_pending          ),
    .new_notify_ack_pending         (new_notify_ack_pending                   ),
    .new_read_request_pending       (new_read_request_pending                 ),
    .new_notify_request_pending     (new_notify_request_pending               ),
    // master interface -------------------------------------------------------
    .master_dst_addr                (master_dst_addr                          ),
    .master_src_addr                (master_src_addr                          ),
    .master_size_b                  (master_size_b                            ),
    .master_req_id                  (master_req_id                            ),
    .master_iop_id                  (master_iop_id                            ),
    .master_hpu_id                  (master_hpu_id                            ),
    .master_valid                   (master_valid                             ),
    // slave interface --------------------------------------------------------
    .nrx_cmd_payload                (nrx_cmd_payload                          ),
    .nrx_valid                      (nrx_valid                                ),
    .notify_ack_sent                (notify_ack_sent                          ),
    .ce_header_payload              (ce_header_payload                        ),
    .ce_valid                       (ce_valid                                 ),
    .ce_start_of_batch                         (ce_start_of_batch                                   ),
    .ce_payload                     (ce_payload                               ),
    .ce_ready                       (ce_ready                                 ),
    // QSFP TX interface ------------------------------------------------------
    .qsfp_tx_tdata                  (qsfp_tx_tdata                            ),
    .qsfp_tx_tkeep_user             (qsfp_tx_tkeep_user                       ),
    .qsfp_tx_tlast                  (qsfp_tx_tlast                            ),
    .qsfp_tx_tvalid                 (qsfp_tx_tvalid                           ),
    .qsfp_tx_tready                 (qsfp_tx_tready                           )
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
  // specific for FPGA
  // TODO: reseync miust be reworked
  // =========================================================================================== //
  // logic [15:0] cnt_notify_ack; defined before for timeout
  // logic [15:0] cnt_notify_read;

  // logic start_cnt_notify_ack;
  // logic notify_ack_received_cdc;

  // /* how long it is between sending a notify request and receiving an acknowledge
  //  *  - starts when received_req (clk_cfg) is ones
  //  *  - stops when notify_ack_received (clk mrmac) is one
  //  */
  // always_ff @(posedge clk_cfg) begin
  //   if (~resetn_cfg) begin
  //     start_cnt_notify_ack <= 1'b0;
  //   end else begin
  //     if (received_req & (regf_req_id[23:20] == REQ_ID_NOTIFY_TX)) begin
  //       start_cnt_notify_ack <= 1'b1;
  //     end else if(notify_ack_received_cdc) begin
  //       start_cnt_notify_ack <= 1'b0;
  //     end
  //   end
  // end

  // always_ff @(posedge clk_cfg) begin
  //   if (~resetn_cfg) begin
  //     cnt_notify_ack <= 'h0;
  //   end else begin
  //     if (start_cnt_notify_ack) begin
  //       cnt_notify_ack <= cnt_notify_ack + 1;
  //     end else if (rst_cnt_notify | ntx_timeout) begin
  //       cnt_notify_ack <= 'h0;
  //     end
  //   end
  // end

  // xpm_cdc_single_wrapper # (
  //   .CDC_SYNC_STAGES(CDC_SYNC_STAGES),
  //   .SRC_INPUT_REG  (0)
  // ) ack_xpm_cdc_single_wrapper (
  //   .src_clk(clk_mrmac),
  //   .src_in (notify_ack_received),

  //   .dest_clk(clk_cfg),
  //   .dest_out(notify_ack_received_cdc)
  // );

  // /* How long has the data been ready in the regif
  //  *  - counts when interruption is raised
  //  *  - itr_notify is on config clock
  //  */
  // always_ff @(posedge clk_cfg) begin
  //   if (~resetn_cfg) begin
  //     cnt_notify_read <= 'h0;
  //   end else begin
  //     if (itr_notify) begin
  //       cnt_notify_read <= cnt_notify_read +1;
  //     end else if (rst_cnt_notify) begin
  //       cnt_notify_read <= 'h0;
  //     end
  //   end
  // end

  // assign stat_cnt_notify_ack  = cnt_notify_ack;
  // assign stat_cnt_notify_read = cnt_notify_read;

  // =========================================================================================== //
  // Error agreggation
  // =========================================================================================== //
  // error_id_def: Definition of HPUs are not correct, several are defined as current
  // error_packet_id_mismatch: sec_num received is unexpected


endmodule
