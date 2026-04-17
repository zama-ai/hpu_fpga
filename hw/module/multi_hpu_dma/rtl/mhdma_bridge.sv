// ================================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ------------------------------------------------------------------------------------------------
// Description  : MHDMA Bridge between HBM and QSFP
//
// Instantiates and interconnects the four core sub-modules of the MHDMA datapath:
//   - mhdma_decoder   : QSFP RX frame parsing, sends decoded commands & ciphertext stream
//   - mhdma_master    : notify / read-request FSM, ciphertext write to HBM
//   - mhdma_slave     : notify-ack / ciphertext-read from HBM
//   - mhdma_formatter : takes commands and sends custom ethernet header & payload
//
// Additionally handles:
//   - HPU identification: CDC of hpu_ids from cfg_clock to one-hot lookup & current_hpu_mac/id
//   - Decoded-command arbitration: decoder output is shared between master and slave via
//     OR'd ready (decoded_command_rdy = rdy_slave | rdy_master)
//   - Error aggregation: per-submodule errors are packed into mhdma_error_t for regfile readback
//   - Stat multiplexing: per-submodule stat structs are mapped into mhdma_stat_to_cfg_t
//
// Assumptions / Limitations:
//   - Exactly one hpu_ids entry must have bit [31] set (one-hot). multiple bits set raises
//     error_id. All-zeros is treated as "no HPU selected" (current_hpu_mac = 0).
//   - Decoded command dispatch relies on req_id partitioning: master consumes NOTIFY_ACK and
//     CT EMISSION commands, slave consumes NOTIFY and READ commands.
//     Bridge OR's their ready signals : correctness depends on these req_id sets being disjoint.
//   - regf_ct_mem_addr, regf_req_id/addr cross from cfg to eth domain inside sub-modules.
//
// ================================================================================================

module mhdma_bridge
  import mhdma_pkg::*;                            // multi-hpu-dma
  import axi_if_shell_axil_pkg::*;                // REG_DATA_W
  import axi_if_common_param_pkg::*;              // general axi4
  import axi_if_mhdma_axi_pkg::*;                 // AXI ethernet
#() (
  // Ethernet configuration interface -----------------------------------------
  input  logic                                    clk_mhdma_cfg,
  input  logic                                    resetn_mhdma_cfg,
  // Ethernet fast clock interface --------------------------------------------
  input  logic                                    clk_mhdma,
  input  logic                                    resetn_mhdma,
  // Axi4 interface for NMU ---------------------------------------------------
  // Read channel
  output logic [   AXI4_ID_W-1:0]                 m_axi4_arid,
  output logic [  AXI4_ADD_W-1:0]                 m_axi4_araddr,
  output logic [  AXI4_LEN_W-1:0]                 m_axi4_arlen,
  output logic [ AXI4_SIZE_W-1:0]                 m_axi4_arsize,
  output logic [AXI4_BURST_W-1:0]                 m_axi4_arburst,
  output logic                                    m_axi4_arvalid,
  input  logic                                    m_axi4_arready,
  input  logic [  AXI4_ID_W-1:0]                  m_axi4_rid,
  input  logic [AXI4_DATA_W-1:0]                  m_axi4_rdata,
  input  logic [AXI4_RESP_W-1:0]                  m_axi4_rresp,
  input  logic                                    m_axi4_rlast,
  input  logic                                    m_axi4_rvalid,
  output logic                                    m_axi4_rready,
  // Write channel
  output logic [   AXI4_ID_W-1:0]                 m_axi4_awid,
  output logic [  AXI4_ADD_W-1:0]                 m_axi4_awaddr,
  output logic [  AXI4_LEN_W-1:0]                 m_axi4_awlen,
  output logic [ AXI4_SIZE_W-1:0]                 m_axi4_awsize,
  output logic [AXI4_BURST_W-1:0]                 m_axi4_awburst,
  output logic                                    m_axi4_awvalid,
  input  logic                                    m_axi4_awready,
  output logic [AXI4_DATA_W-1:0]                  m_axi4_wdata,
  output logic [AXI4_STRB_W-1:0]                  m_axi4_wstrb,
  output logic                                    m_axi4_wlast,
  output logic                                    m_axi4_wvalid,
  input  logic                                    m_axi4_wready,
  // Write response channel
  input  logic [  AXI4_ID_W-1:0]                  m_axi4_bid,
  input  logic [AXI4_RESP_W-1:0]                  m_axi4_bresp,
  input  logic                                    m_axi4_bvalid,
  output logic                                    m_axi4_bready,
  // regf interface -----------------------------------------------------------
  input  logic [NB_MAX_HPU-1:0][  REG_DATA_W-1:0] regf_hpu_ids,
  input  logic [    ETH_PC-1:0][2*REG_DATA_W-1:0] regf_ct_mem_addr,
  input  logic                 [  REG_DATA_W-1:0] regf_req_id,
  input  logic                 [  REG_DATA_W-1:0] regf_req_addr,
  output logic                 [  REG_DATA_W-1:0] regf_notify_req_id,
  output logic                 [  REG_DATA_W-1:0] regf_notify_req_addr,
  output logic                 [  REG_DATA_W-1:0] regf_read_req_id,
  output logic                 [  REG_DATA_W-1:0] regf_read_addr,
  input  logic                 [  REG_DATA_W-1:0] regf_timeout_duration_notify,
  input  logic                 [  REG_DATA_W-1:0] regf_timeout_duration_read_req,
  // control ------------------------------------------------------------------
  input  logic                                    received_req,
  output logic                                    request_consumed,
  // statistics ---------------------------------------------------------------
  output mhdma_stat_to_cfg_t                      stat_to_cfg,
  input  mhdma_stat_rst_t                         stat_rst,
  // cfg-domain errors --------------------------------------------------------
  output master_error_cfg_t                       master_error_cfg,
  input  logic                                    rst_errors_cfg,
  // interrupts ---------------------------------------------------------------
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

  // per-submodule stat/rst struct wires
  master_stat_t        master_stat;
  master_stat_rst_t    master_stat_rst;
  slave_stat_t         slave_stat;
  slave_stat_rst_t     slave_stat_rst;
  decoder_stat_t       decoder_stat;
  decoder_stat_rst_t   decoder_stat_rst;
  formatter_stat_t     formatter_stat;
  formatter_stat_rst_t formatter_stat_rst;

  // =========================================================================================== //
  // CDC from regf to mrmac clock
  // =========================================================================================== //
  // these signals are quasi static: they should move rarely
  logic [CDC_SYNC_STAGES-1:0][NB_MAX_HPU-1:0][REG_DATA_W-1:0] hpu_ids_cdc;
  logic                      [NB_MAX_HPU-1:0][REG_DATA_W-1:0] hpu_ids; // just for naming

  generate
    for (genvar gen_i_id = 0; gen_i_id < NB_MAX_HPU; gen_i_id++)
      always_ff @(posedge clk_mhdma)
        hpu_ids_cdc[0][gen_i_id] <= regf_hpu_ids[gen_i_id];

    for (genvar gen_i_cdc = 1; gen_i_cdc < CDC_SYNC_STAGES ; gen_i_cdc = gen_i_cdc + 1)
      for (genvar gen_i_id = 0; gen_i_id < NB_MAX_HPU; gen_i_id++)
        always_ff @(posedge clk_mhdma)
          hpu_ids_cdc[gen_i_cdc][gen_i_id] <= hpu_ids_cdc[gen_i_cdc-1][gen_i_id];
  endgenerate

  // ==============================================================================================
  // hpu identification
  // ==============================================================================================
  logic [NB_MAX_HPU-1:0][MAC_ADDR_W-1:0] hpu_mac_table;
  logic [NB_MAX_HPU-1:0]                 one_hot_id;

  assign hpu_ids = hpu_ids_cdc[CDC_SYNC_STAGES-1];

  generate
    for (genvar i=0; i<NB_MAX_HPU; i++) begin
      always_ff @(posedge clk_mhdma) begin : hpu_id_table_creation
        hpu_mac_table[i] <= hpu_ids[i][MAC_ADDR_W-1:0];
        one_hot_id[i]    <= hpu_ids[i][31];
      end
    end
  endgenerate

  // if ever two hpu ids are set as "current", raise an error
  // when one_hot_id is all zeros, we cannot conclude if there is an error or not
  logic error_id;
  always_ff @(posedge clk_mhdma) begin : error_on_hpu_id
    if (~resetn_mhdma) begin
      error_id <= 1'b0;
    end else begin
      error_id <= (one_hot_id != '0) && !$onehot(one_hot_id);
    end
  end

  // hpu_index : position of the set bit in one_hot_id (regf_hpu_ids[].bit[31]).
  // Used as MAC table index and, by SW convention, as current_hpu_id.
  logic [          HPU_ID_W-1:0] current_hpu_idD;
  logic [        MAC_ADDR_W-1:0] current_hpu_macD;
  logic [$clog2(NB_MAX_HPU)-1:0] hpu_index;

  always_comb begin
      hpu_index = '0;
      for (int i = 0; i < NB_MAX_HPU; i++)
          if (one_hot_id[i])
              hpu_index = i;
  end

  assign current_hpu_macD = (one_hot_id==0) ? 'h0 : hpu_mac_table[hpu_index];
  assign current_hpu_idD  = (one_hot_id==0) ? 'h0 : HPU_ID_W'(hpu_index);

  // these two registers are here to ease P&R
  logic [  HPU_ID_W-1:0] current_hpu_id;
  logic [MAC_ADDR_W-1:0] current_hpu_mac;

  always_ff @(posedge clk_mhdma) begin
    current_hpu_id  <= current_hpu_idD;
    current_hpu_mac <= current_hpu_macD;
  end

  // ==============================================================================================
  // Core Instances of mhdma
  // ==============================================================================================
  // Master <-> Formatter
  command_t master_command;
  logic     master_command_vld;
  logic     master_command_rdy;

  logic     notify_sent;
  logic     read_request_sent;

  // Slave <-> Formatter
  logic [MRMAC_AXIS_W-1:0] ce_payload;
  logic                    ce_vld;
  logic                    ce_rdy;

  command_t slave_command;
  logic     slave_command_vld;
  logic     slave_command_rdy;

  logic     ciphertext_sent;
  logic     notify_ack_sent;

  // Decoder <-> (Master & Slave)
  command_t decoded_command;
  logic     decoded_command_rdy;
  logic     decoded_command_vld;
  logic     decoded_command_rdy_slave;
  logic     decoded_command_rdy_master;

  assign decoded_command_rdy = decoded_command_rdy_slave | decoded_command_rdy_master;

  // Decoder <-> Master
  logic [MRMAC_AXIS_W-1:0] decoder_rx_tdata;
  logic                    decoder_rx_tvalid;

  logic notify_ack_received;

  // Errors
  mhdma_error_t mhdma_errors;
  decoder_error_t decoder_error;
  format_error_t format_error;
  master_error_t master_error;
  slave_error_t slave_error;

  // Master module does the controls for sending read request and Notifies requests
  mhdma_master mhdma_master (
    // Ethernet configuration interface ---------------------------------------
    .clk_mhdma_cfg                   (clk_mhdma_cfg                           ),
    .resetn_mhdma_cfg                (resetn_mhdma_cfg                        ),
    // Ethernet fast clock interface ------------------------------------------
    .clk_mhdma                       (clk_mhdma                               ),
    .resetn_mhdma                    (resetn_mhdma                            ),
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
    // regf interface ---------------------------------------------------------
    .regf_ct_mem_addr                (regf_ct_mem_addr                        ),
    .regf_req_id                     (regf_req_id                             ),
    .regf_req_addr                   (regf_req_addr                           ),
    .regf_read_req_id                (regf_read_req_id                        ),
    .regf_read_addr                  (regf_read_addr                          ),
    .regf_timeout_duration_notify    (regf_timeout_duration_notify            ),
    .regf_timeout_duration_read_req  (regf_timeout_duration_read_req          ),
    // register control
    .received_req                    (received_req                            ),
    .request_consumed                (request_consumed                        ),
    // interrupt --------------------------------------------------------------
    .clear_interrupt_rr              (clear_interrupt_rr                      ),
    .interrupt_read_request          (interrupt_read_request                  ),
    // decoder interface ------------------------------------------------------
    .decoded_command                 (decoded_command                         ),
    .decoded_command_rdy             (decoded_command_rdy_master              ),
    .decoded_command_vld             (decoded_command_vld                     ),
    // ciphertext reception
    .decoder_rx_tdata                (decoder_rx_tdata                        ),
    .decoder_rx_tvalid               (decoder_rx_tvalid                       ),
    // pulse on ack reception
    .notify_ack_received             (notify_ack_received                     ),
    // formatter interface ----------------------------------------------------
    .master_command                  (master_command                          ),
    .master_command_vld              (master_command_vld                      ),
    .master_command_rdy              (master_command_rdy                      ),
    .read_request_sent               (read_request_sent                       ),
    .notify_sent                     (notify_sent                             ),
    // errors -----------------------------------------------------------------
    .master_error                    (master_error                            ),
    .master_error_cfg                (master_error_cfg                        ),
    .rst_errors                      (stat_rst.mhdma_errors                    ),
    .rst_errors_cfg                  (rst_errors_cfg                          ),
    // statistics -------------------------------------------------------------
    .stat                            (master_stat                             ),
    .stat_rst                        (master_stat_rst                         )
  );

  // Slave module does the control for Notify ack and ciphertext emission
  mhdma_slave # (
    .CDC_SYNC_STAGES                (CDC_SYNC_STAGES                          )
  ) mhdma_slave (
    // Ethernet configuration interface ---------------------------------------
    .clk_mhdma_cfg                  (clk_mhdma_cfg                            ),
    .resetn_mhdma_cfg               (resetn_mhdma_cfg                         ),
    // Ethernet fast clock interface ------------------------------------------
    .clk_mhdma                      (clk_mhdma                                ),
    .resetn_mhdma                   (resetn_mhdma                             ),
    // AXI4-4 full read interface ---------------------------------------------
    .m_axi4_araddr                  (m_axi4_araddr                            ),
    .m_axi4_arlen                   (m_axi4_arlen                             ),
    .m_axi4_arsize                  (m_axi4_arsize                            ),
    .m_axi4_arburst                 (m_axi4_arburst                           ),
    .m_axi4_arvalid                 (m_axi4_arvalid                           ),
    .m_axi4_arready                 (m_axi4_arready                           ),
    .m_axi4_arid                    (m_axi4_arid                              ),

    .m_axi4_rdata                   (m_axi4_rdata                             ),
    .m_axi4_rresp                   (m_axi4_rresp                             ),
    .m_axi4_rid                     (m_axi4_rid                               ),
    .m_axi4_rlast                   (m_axi4_rlast                             ),
    .m_axi4_rvalid                  (m_axi4_rvalid                            ),
    .m_axi4_rready                  (m_axi4_rready                            ),
    // regf interface ---------------------------------------------------------
    .regf_ct_mem_addr               (regf_ct_mem_addr                         ),
    .regf_notify_req_id             (regf_notify_req_id                       ),
    .regf_notify_req_addr           (regf_notify_req_addr                     ),
    // interrupt interface ----------------------------------------------------
    .clear_interrupt_notify         (clear_interrupt_notify                   ),
    .interrupt_notify               (interrupt_notify                         ),
    // decoder interface ------------------------------------------------------
    .decoded_command                (decoded_command                          ),
    .decoded_command_rdy            (decoded_command_rdy_slave                ),
    .decoded_command_vld            (decoded_command_vld                      ),
    // formatter interface ----------------------------------------------------
    .slave_command                  (slave_command                            ),
    .slave_command_vld              (slave_command_vld                        ),
    .slave_command_rdy              (slave_command_rdy                        ),
    // stream of ciphertext
    .ce_payload                     (ce_payload                               ),
    .ce_rdy                         (ce_rdy                                   ),
    .ce_vld                         (ce_vld                                   ),
    // sent ack
    .ciphertext_sent                (ciphertext_sent                          ),
    .notify_ack_sent                (notify_ack_sent                          ),
    // errors -----------------------------------------------------------------
    .slave_error                    (slave_error                              ),
    .rst_errors                     (stat_rst.mhdma_errors                     ),
    // statistics -------------------------------------------------------------
    .stat                           (slave_stat                               ),
    .stat_rst                       (slave_stat_rst                           )
  );

  // The decoder gathers axi-stream RX and decodes the received command
  mhdma_decoder mhdma_decoder (
    // Ethernet fast clock interface ------------------------------------------
    .clk_mhdma                   (clk_mhdma                                   ),
    .resetn_mhdma                (resetn_mhdma                                ),
    // Command interface ------------------------------------------------------
    .notify_ack_received         (notify_ack_received                         ),
    .current_hpu_mac             (current_hpu_mac                             ),
    // Header information -----------------------------------------------------
    .decoded_command             (decoded_command                             ),
    .decoded_command_rdy         (decoded_command_rdy                         ),
    .decoded_command_vld         (decoded_command_vld                         ),
    // RX payload -------------------------------------------------------------
    .rx_tdata_out                (decoder_rx_tdata                            ),
    .rx_tvalid_out               (decoder_rx_tvalid                           ),
    // QSFP RX interface ------------------------------------------------------
    .qsfp_rx_tdata               (qsfp_rx_tdata                               ),
    .qsfp_rx_tkeep_user          (qsfp_rx_tkeep_user                          ),
    .qsfp_rx_tlast               (qsfp_rx_tlast                               ),
    .qsfp_rx_tvalid              (qsfp_rx_tvalid                              ),
    // errors -----------------------------------------------------------------
    .decoder_error               (decoder_error                               ),
    .rst_errors                  (stat_rst.mhdma_errors                       ),
    // statistics -------------------------------------------------------------
    .stat                        (decoder_stat                                ),
    .stat_rst                    (decoder_stat_rst                            )
  );

  // the formatter gathers commands from master & slave module and sends it to axis
  mhdma_formatter mhdma_formatter (
    // Ethernet fast clock interface ------------------------------------------
    .clk_mhdma                       (clk_mhdma                               ),
    .resetn_mhdma                    (resetn_mhdma                            ),
    // Bridge interface -------------------------------------------------------
    .hpu_mac_table                   (hpu_mac_table                           ),
    .current_hpu_id                  (current_hpu_id                          ),
    .current_hpu_mac                 (current_hpu_mac                         ),
    // slave interface --------------------------------------------------------
    .slave_command                   (slave_command                           ),
    .slave_command_vld               (slave_command_vld                       ),
    .slave_command_rdy               (slave_command_rdy                       ),

    .ce_payload                      (ce_payload                              ),
    .ce_rdy                          (ce_rdy                                  ),
    .ce_vld                          (ce_vld                                  ),

    .notify_ack_sent                 (notify_ack_sent                         ),
    .ciphertext_sent                 (ciphertext_sent                         ),
    // master interface -------------------------------------------------------
    .master_command                  (master_command                          ),
    .master_command_vld              (master_command_vld                      ),
    .master_command_rdy              (master_command_rdy                      ),

    .notify_sent                     (notify_sent                             ),
    .read_request_sent               (read_request_sent                       ),
    // QSFP TX interface ------------------------------------------------------
    .qsfp_tx_tdata                   (qsfp_tx_tdata                           ),
    .qsfp_tx_tkeep_user              (qsfp_tx_tkeep_user                      ),
    .qsfp_tx_tlast                   (qsfp_tx_tlast                           ),
    .qsfp_tx_tvalid                  (qsfp_tx_tvalid                          ),
    .qsfp_tx_tready                  (qsfp_tx_tready                          ),
    // errors -----------------------------------------------------------------
    .format_error                    (format_error                            ),
    .rst_errors                      (stat_rst.mhdma_errors                   ),
    // statistics -------------------------------------------------------------
    .stat                            (formatter_stat                          ),
    .stat_rst                        (formatter_stat_rst                      )
  );

  // ==============================================================================================
  // Errors
  // ==============================================================================================
  assign mhdma_errors.format_error     = format_error;
  assign mhdma_errors.decoder_error   = decoder_error;
  assign mhdma_errors.slave_error     = slave_error;
  assign mhdma_errors.master_error    = master_error;
  assign mhdma_errors.error_id        = error_id;
  assign stat_to_cfg.mhdma_errors = {{(32-$bits(mhdma_error_t)){1'b0}}, mhdma_errors};

  // =========================================================================================== //
  // Statistics: map per-submodule structs to CDC structs
  // =========================================================================================== //
  assign stat_to_cfg.master    = master_stat;
  assign stat_to_cfg.slave     = slave_stat;
  assign stat_to_cfg.decoder   = decoder_stat;
  assign stat_to_cfg.formatter = formatter_stat;

  // reset mapping (stat_rst -> per-submodule stat_rst)
  assign master_stat_rst    = stat_rst.master;
  assign slave_stat_rst     = stat_rst.slave;
  assign decoder_stat_rst   = stat_rst.decoder;
  assign formatter_stat_rst = stat_rst.formatter;

endmodule
