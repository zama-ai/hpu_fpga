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
  input  logic                                   clk_cfg,
  input  logic                                   resetn_cfg,
  // Ethernet fast clock interface --------------------------------------------
  input  logic                                   clk_mrmac,
  input  logic                                   resetn_mrmac,
  // Axi4 interface for NMU ---------------------------------------------------
  // Read channel
  output logic [ETH_PC-1:0][   AXI4_ID_W-1:0]    m_axi4_arid,
  output logic [ETH_PC-1:0][  AXI4_ADD_W-1:0]    m_axi4_araddr,
  output logic [ETH_PC-1:0][  AXI4_LEN_W-1:0]    m_axi4_arlen,
  output logic [ETH_PC-1:0][ AXI4_SIZE_W-1:0]    m_axi4_arsize,
  output logic [ETH_PC-1:0][AXI4_BURST_W-1:0]    m_axi4_arburst,
  output logic [ETH_PC-1:0]                      m_axi4_arvalid,
  input  logic [ETH_PC-1:0]                      m_axi4_arready,
  input  logic [ETH_PC-1:0][  AXI4_ID_W-1:0]     m_axi4_rid,
  input  logic [ETH_PC-1:0][AXI4_DATA_W-1:0]     m_axi4_rdata,
  input  logic [ETH_PC-1:0][AXI4_RESP_W-1:0]     m_axi4_rresp,
  input  logic [ETH_PC-1:0]                      m_axi4_rlast,
  input  logic [ETH_PC-1:0]                      m_axi4_rvalid,
  output logic [ETH_PC-1:0]                      m_axi4_rready,
  // Write channel
  output logic [ETH_PC-1:0][   AXI4_ID_W-1:0]    m_axi4_awid,
  output logic [ETH_PC-1:0][  AXI4_ADD_W-1:0]    m_axi4_awaddr,
  output logic [ETH_PC-1:0][  AXI4_LEN_W-1:0]    m_axi4_awlen,
  output logic [ETH_PC-1:0][ AXI4_SIZE_W-1:0]    m_axi4_awsize,
  output logic [ETH_PC-1:0][AXI4_BURST_W-1:0]    m_axi4_awburst,
  output logic [ETH_PC-1:0]                      m_axi4_awvalid,
  input  logic [ETH_PC-1:0]                      m_axi4_awready,
  output logic [ETH_PC-1:0][AXI4_DATA_W-1:0]     m_axi4_wdata,
  output logic [ETH_PC-1:0][AXI4_STRB_W-1:0]     m_axi4_wstrb,
  output logic [ETH_PC-1:0]                      m_axi4_wlast,
  output logic [ETH_PC-1:0]                      m_axi4_wvalid,
  input  logic [ETH_PC-1:0]                      m_axi4_wready,
  input  logic [ETH_PC-1:0][  AXI4_ID_W-1:0]     m_axi4_bid,
  input  logic [ETH_PC-1:0][AXI4_RESP_W-1:0]     m_axi4_bresp,
  input  logic [ETH_PC-1:0]                      m_axi4_bvalid,
  output logic [ETH_PC-1:0]                      m_axi4_bready,
  // regf interface -----------------------------------------------------------
  input  logic [NB_MAX_HPU-1:0][REGF_WORD_W-1:0] regf_hpu_ids,
  input  logic [REGF_WORD_W-1:0]                 regf_req_id,
  input  logic [REGF_WORD_W-1:0]                 regf_req_addr,
  input  logic [ 1:0]                            received_req,
  output logic                                   request_consumed,
  output logic [REGF_WORD_W-1:0]                 regf_notify_payload,
  // statistics ---------------------------------------------------------------
  output logic [15:0]                            stat_cnt_notify_ack,
  output logic [15:0]                            stat_cnt_notify_read,
  // reset counters
  input  logic                                   rst_cnt_notify,
  // interrupts ---------------------------------------------------------------
  input  logic                                   clear_interrupt_notify,
  output logic                                   interrupt_notify,
  output logic                                   interrupt_read_request,
  input  logic [15:0]                            timeout_duration,
  // QSFP system interface ----------------------------------------------------
  // == TX
  output logic [MRMAC_AXIS_W-1:0]                qsfp_tx_tdata,
  output logic [MRMAC_TKEEP_W-1:0]               qsfp_tx_tkeep_user,
  output logic                                   qsfp_tx_tlast,
  output logic                                   qsfp_tx_tvalid,
  input  logic                                   qsfp_tx_tready,
  // == RX
  input  logic [MRMAC_AXIS_W-1:0]                qsfp_rx_tdata,
  input  logic [MRMAC_TKEEP_W-1:0]               qsfp_rx_tkeep_user,
  input  logic                                   qsfp_rx_tlast,
  input  logic                                   qsfp_rx_tvalid
);

  // =========================================================================================== //
  // localparam
  // =========================================================================================== //
  localparam int CDC_SYNC_STAGES = 2;

  // =========================================================================================== //
  // CDC from regf to mrmac clock
  // =========================================================================================== //
  // theses signals are quasi static: they should move rarely
  logic [CDC_SYNC_STAGES-1:0][NB_MAX_HPU-1:0][REGF_WORD_W-1:0] hpu_ids_cdc;
  logic                      [NB_MAX_HPU-1:0][REGF_WORD_W-1:0] hpu_ids; // just for naming

  generate
    for (genvar gen_i_id = 0; gen_i_id < NB_MAX_HPU; gen_i_id++)
      always_ff @(posedge clk_mrmac)
        hpu_ids_cdc[0][gen_i_id] <= regf_hpu_ids[gen_i_id];

    for (genvar gen_i_cdc = 1; gen_i_cdc < CDC_SYNC_STAGES ; gen_i_cdc = gen_i_cdc + 1)
      for (genvar gen_i_id = 0; gen_i_id < NB_MAX_HPU; gen_i_id++)
        always_ff @(posedge clk_mrmac)
          hpu_ids_cdc[gen_i_cdc][gen_i_id] <= hpu_ids_cdc[gen_i_cdc-1][gen_i_id];
  endgenerate

  // ReQuest Queues -------------------------------------------------------------------------------
  logic rrqq_wr_en; // read request queue write enable
  logic nrqq_wr_en; // notify request queue write enable
  // when we have the data of both request identifier and addresses, we consume the information
  // once consumed, the top will receive the flag and toggle received requests
  assign request_consumed = (rrqq_wr_en | nrqq_wr_en) ? 1'b1 : 1'b0;
  // new pending requests on qsfp tx
  logic new_notify_request_pending;
  logic new_notify_ack_pending;
  logic new_read_request_pending;
  logic new_ct_emission_request_pending;

  logic notify_request_granted;
  logic notify_ack_granted;
  logic read_request_granted;
  logic ciphertext_emission_granted;

  logic notify_request_in_use;
  logic read_request_in_use;
  logic ct_emission_request_in_use;

  // Read ReQuest Queue (RRQQ) --------------------------------------------------------------------
  // config clock
  logic                        rrqq_wr_rst_busy;
  logic                        rrqq_full;
  // mrmac clock
  logic                        rrqq_rd_rst_busy;
  logic                        rrqq_data_valid;
  logic                        rrqq_rd_en;
  logic [       RQQ_WIDTH-1:0] rrqq_rd_data;
  logic                        rrqq_empty;
  logic [RQQ_DATA_COUNT_W-1:0] rrqq_rd_data_count;
  // needed control signals for sampling (mrmac clock)

  // cfg
  assign rrqq_wr_en = (&received_req) & ~rrqq_wr_rst_busy & ~rrqq_full & (regf_req_id[23:20] == REQ_ID_READ);
  // mrmac
  assign new_read_request_pending = ((rrqq_rd_data_count == 0) & ~read_request_in_use) ? 1'b0 : 1'b1;
  assign rrqq_rd_en =  new_read_request_pending & ~rrqq_rd_rst_busy & ~rrqq_empty;

  fifo_ram_rdy_vld_2clk # (
    .CDC_SYNC_STAGES (CDC_SYNC_STAGES),
    .WIDTH           (RQQ_WIDTH),
    // tweak theses parameters in package
    .DEPTH           (XPM_MIN_FIFO_DEPTH),
    .FIFO_MEMORY_TYPE(RQQ_MEMORY_TYPE)
  ) rrqq_fifo_ram_rdy_vld_2clk (
    // Write Domain ports: CFG domain
    .wr_rstn      (resetn_cfg),
    .wr_clk       (clk_cfg),
    .wr_en        (rrqq_wr_en),
    .wr_data      ({regf_req_id, regf_req_addr}),
    .full         (rrqq_full),
    .wr_rst_busy  (rrqq_wr_rst_busy),
    // Read Domain ports: MRMAC domain
    .rd_clk       (clk_mrmac),
    .rd_en        (rrqq_rd_en),
    .rd_data      (rrqq_rd_data),
    .rd_data_count(rrqq_rd_data_count),
    .empty        (rrqq_empty),
    .rd_rst_busy  (rrqq_rd_rst_busy),
    .data_valid   (rrqq_data_valid)
  );

  // current read request, sampled when valid is toggled
  logic [DST_ADDR_W-1:0] rrqq_dst_addr;
  logic [SRC_ADDR_W-1:0] rrqq_src_addr;
  logic [  SIZE_B_W-1:0] rrqq_size_b;
  logic [  REQ_ID_W-1:0] rrqq_req_id;
  logic [  IOP_ID_W-1:0] rrqq_iop_id;
  logic [  HPU_ID_W-1:0] rrqq_node_id;

  always_ff @(posedge clk_mrmac) begin : read_request_sampling
    if (~resetn_mrmac) begin
      rrqq_dst_addr <= 'h0;
      rrqq_src_addr  <= 'h0;
      rrqq_size_b    <= 'h0;
      rrqq_iop_id    <= 'h0;
      rrqq_req_id    <= 'h0;
      rrqq_node_id   <= 'h0;
    end else begin
      if (rrqq_data_valid) begin
        rrqq_dst_addr <= rrqq_rd_data[15:00];
        rrqq_src_addr <= rrqq_rd_data[31:16];
        rrqq_size_b   <= rrqq_rd_data[47:32];
        rrqq_node_id  <= rrqq_rd_data[51:48];
        rrqq_req_id   <= rrqq_rd_data[55:52];
        rrqq_iop_id   <= rrqq_rd_data[59:56];
      end
    end
  end

  // Notify ReQuest Queue (NRQQ) ------------------------------------------------------------------
  // config clock
  logic                        nrqq_wr_rst_busy;
  logic                        nrqq_full;
  // mrmac clock
  logic                        nrqq_rd_rst_busy;
  logic                        nrqq_data_valid;
  logic                        nrqq_rd_en;
  logic [      NRQQ_WIDTH-1:0] nrqq_rd_data;
  logic                        nrqq_empty;
  logic [NRQQ_DATA_COUNT_W-1:0] nrqq_rd_data_count;

  // cfg
  assign nrqq_wr_en = (&received_req) & ~nrqq_wr_rst_busy & ~nrqq_full & (regf_req_id[23:20] == REQ_ID_NOTIFY_TX);
  // mrmac
  assign new_notify_request_pending = (nrqq_rd_data_count == 0) ? 1'b0 : 1'b1;
  assign nrqq_rd_en =  new_notify_request_pending & notify_request_in_use & ~nrqq_rd_rst_busy & ~nrqq_empty;

  fifo_ram_rdy_vld_2clk # (
    .CDC_SYNC_STAGES (CDC_SYNC_STAGES),
    // tweak theses parameters in package
    .WIDTH           (NRQQ_WIDTH),
    .DEPTH           (XPM_MIN_FIFO_DEPTH),
    .FIFO_MEMORY_TYPE(NRQQ_MEMORY_TYPE)
  ) nrqq_fifo_ram_rdy_vld_2clk (
    // Write Domain ports: CFG domain
    .wr_rstn      (resetn_cfg),
    .wr_clk       (clk_cfg),
    .wr_en        (nrqq_wr_en),
    .wr_data      ({regf_req_id, regf_req_addr}),
    .full         (nrqq_full),
    .wr_rst_busy  (nrqq_wr_rst_busy),
    // Read Domain ports: MRMAC domain
    .rd_clk       (clk_mrmac),
    .rd_en        (nrqq_rd_en),
    .rd_data      (nrqq_rd_data),
    .rd_data_count(nrqq_rd_data_count),
    .empty        (nrqq_empty),
    .rd_rst_busy  (nrqq_rd_rst_busy),
    .data_valid   (nrqq_data_valid)
  );

  // current notify request, sampled when valid is toggled
  logic [SRC_ADDR_W-1:0] nrqq_src_addr;
  logic [IOP_ID_W-1:0]   nrqq_iop_id;
  logic [SIZE_B_W-1:0]   nrqq_size_b;
  logic [REQ_ID_W-1:0]   nrqq_req_id;
  logic [HPU_ID_W-1:0]   nrqq_node_id;

  // none of theses information are in the first word:
  //  => sampled on the same clock cycle as sending first frame
  always_ff @(posedge clk_mrmac) begin : notify_request_sampling
    if (~resetn_mrmac) begin
      nrqq_src_addr  <= 'h0;
      nrqq_size_b    <= 'h0;
      nrqq_iop_id    <= 'h0;
      nrqq_req_id    <= 'h0;
    end else begin
      if (nrqq_data_valid) begin
        nrqq_src_addr  <= nrqq_rd_data[SRC_ADDR_W-1:0];
        nrqq_size_b    <= nrqq_rd_data[SIZE_B_W+32-1:32];
        nrqq_req_id    <= nrqq_rd_data[REQ_ID_W+HPU_ID_W+SIZE_B_W+32-1:HPU_ID_W+SIZE_B_W+32];
        nrqq_iop_id    <= nrqq_rd_data[IOP_ID_W+REQ_ID_W+HPU_ID_W+SIZE_B_W+32-1:REQ_ID_W+HPU_ID_W+SIZE_B_W+32];
      end
    end
  end

  // needed directly to not wait
  assign nrqq_node_id = nrqq_data_valid ? nrqq_rd_data[HPU_ID_W+SIZE_B_W+32-1:SIZE_B_W+32] : 1'b0;

  // =========================================================================================== //
  // CDC from fast to slow clock
  // =========================================================================================== //
  // interrupt on notify doesn't need to be cdc'd here, it is done on NRX side with fifo


  // ==============================================================================================
  // hpu identification
  // ==============================================================================================
  logic [NB_MAX_HPU-1:0][HPU_ID_W-1:0]   hpu_id_table;
  logic [NB_MAX_HPU-1:0][MAC_ADDR_W-1:0] hpu_mac_table;
  logic [NB_MAX_HPU-1:0]                 one_hot_id; // one hot

  assign hpu_ids = hpu_ids_cdc[CDC_SYNC_STAGES-1];

  generate
    for (genvar i=0; i<NB_MAX_HPU; i++) begin
      always_ff @(posedge clk_mrmac) begin : hpu_id_table_creation
       if (~resetn_mrmac) begin
         hpu_id_table[i]  <= 'h0;
         hpu_mac_table[i] <= 'h0;
         one_hot_id[i]    <= 'h0;
       end else begin
          hpu_id_table[i]  <= hpu_ids[i][HPU_ID_W+MAC_ADDR_W-1:MAC_ADDR_W];
          hpu_mac_table[i] <= hpu_ids[i][MAC_ADDR_W-1:0];
          one_hot_id[i]    <= hpu_ids[i][31];
        end
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

  // ==============================================================================================
  // packet decoder
  // ==============================================================================================
  // On RX lanes, should know as soon as possible what type of packets I should see
  // First frame I can check that the destination address is me
  logic [MAC_ADDR_W-1:0] rx_dst_mac_addr;
  // Second frame I will know who is the sender, request ID, seq num
  logic [SEQ_NUM_W-1:0]  rx_sec_num;
  logic [HPU_ID_W-1:0]   rx_hpu_id;
  logic [REQ_ID_W-1:0]   rx_req_id;
  logic [MAC_ADDR_W-1:0] rx_src_mac_addr;
  // third frame, ct src/dst address, iop id, size_byte
  logic [SIZE_B_W-1:0]   rx_size_b;
  logic [IOP_ID_W-1:0]   rx_iop_id;
  logic [SRC_ADDR_W-1:0] rx_ct_src_addr;
  logic [DST_ADDR_W-1:0] rx_ct_dst_addr;

  // rx status signals
  logic read_request_received;
  logic ciphertext_emission_received;
  logic notify_request_received;
  logic notify_ack_received;
  logic new_notify_request_received;

  // ==============================================================================================
  // FSM
  // ==============================================================================================
  logic tx_frame_last; // last signal of qsfp-tx

  // Notify TX (NTX) ------------------------------------------------------------------------------
  logic        ntx_timeout;
  logic [15:0] cnt_notify_ack;

  typedef enum {
    ST_WAIT_REQUEST,
    ST_WAIT_ACK,
    ST_SEND_NOTIFY
  } st_ntx;

  st_ntx ntx_state;
  st_ntx ntx_next_state;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) ntx_state <= ST_WAIT_REQUEST;
    else ntx_state <= ntx_next_state;
  end

  always_comb begin
    case (ntx_state)
      ST_WAIT_REQUEST:
        ntx_next_state = (new_notify_request_pending & notify_request_granted) ? ST_SEND_NOTIFY : ST_WAIT_REQUEST;
      ST_SEND_NOTIFY:
        ntx_next_state = tx_frame_last ? ST_WAIT_ACK : ST_SEND_NOTIFY;
      ST_WAIT_ACK:
        ntx_next_state = notify_ack_received ? ST_WAIT_REQUEST : (ntx_timeout ? ST_SEND_NOTIFY : ntx_next_state);
    endcase
  end

  assign notify_request_in_use = (ntx_state == ST_SEND_NOTIFY) | (ntx_state == ST_WAIT_ACK) ? 1'b1: 1'b0;

  // TODO: in cfg mode?
  always_ff @(posedge clk_cfg) begin
    if (~resetn_cfg) begin
      ntx_timeout <= 1'b0;
    end else begin
      if (cnt_notify_ack >= timeout_duration) begin
        ntx_timeout <= 1'b1;
      end else begin
        ntx_timeout <= 1'b0;
      end
    end
  end

  // Notify RX (NRX) ------------------------------------------------------------------------------
  // => must transmit to regfile IOP_ID, HPU_ID and src_addr
  // => must trigger interrupt signal when registers are ready to be read
  // TODO: no need of FSM..
  typedef enum {
    NTX_WAIT_REQUEST,
    NTX_TRANSMIT_ACK
  } st_nrx;

  st_nrx nrx_state;
  st_nrx nrx_next_state;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) nrx_state <= NTX_WAIT_REQUEST;
    else nrx_state <= nrx_next_state;
  end

  always_comb begin
    case (nrx_state)
      NTX_WAIT_REQUEST:
        nrx_next_state = new_notify_request_received ? NTX_TRANSMIT_ACK : NTX_WAIT_REQUEST;
      NTX_TRANSMIT_ACK:
        nrx_next_state = tx_frame_last ? NTX_WAIT_REQUEST : NTX_TRANSMIT_ACK;
    endcase
  end

  // MRMAC domain
  logic nrxq_wr_en;
  logic nrxq_full;
  logic nrxq_wr_rst_busy;

  // enable when are sure that we have received a notify request + all words of the frames have been received
  // payload data will ready before last pulse will be triggered
  assign nrxq_wr_en = notify_request_received & qsfp_rx_tlast & ~nrxq_full & ~nrxq_wr_rst_busy;

  // CFG domain
  logic [NRX_DATA_COUNT_W-1:0] nrxq_rd_data_count;
  logic                        nrxq_empty;
  logic                        nrxq_rd_rst_busy;
  logic                        nrxq_data_valid;
  logic                        nrxq_rd_en;
  logic                        new_notify_read_pending;
  logic                        itr_notify;

  assign new_notify_read_pending = (nrxq_rd_data_count == 0) ? 1'b0 : 1'b1;
  assign nrxq_rd_en = new_notify_read_pending & ~nrxq_rd_rst_busy & ~nrxq_empty;

  // this fifo transforms rx commands into a 32 bit readable word for regfile
  fifo_ram_rdy_vld_2clk # (
    .CDC_SYNC_STAGES (CDC_SYNC_STAGES),
    .WIDTH           (NRX_WIDTH),
    // tweak theses parameters in package
    .DEPTH           (XPM_MIN_FIFO_DEPTH),
    .FIFO_MEMORY_TYPE(NRX_MEMORY_TYPE)
  ) nrx_fifo_ram_rdy_vld_2clk (
    // Write Domain ports: MRMAC domain
    .wr_rstn      (resetn_mrmac),
    .wr_clk       (clk_mrmac),
    .wr_en        (nrxq_wr_en),
    .wr_data      ({rx_ct_src_addr, 8'b0, rx_hpu_id, rx_iop_id}),
    .full         (nrxq_full),
    .wr_rst_busy  (nrxq_wr_rst_busy),
    // Read Domain ports: CFG domain
    .rd_clk       (clk_cfg),
    .rd_en        (nrxq_rd_en),
    .rd_data      (regf_notify_payload),
    .rd_data_count(nrxq_rd_data_count),
    .empty        (nrxq_empty),
    .rd_rst_busy  (nrxq_rd_rst_busy),
    .data_valid   (nrxq_data_valid)
  );

  always_ff @(posedge clk_cfg) begin
    if (~resetn_cfg) begin
      itr_notify <= 1'b0;
    end else begin
      if(nrxq_data_valid) begin
        itr_notify <= 1'b1;
      end else if (clear_interrupt_notify) begin
        itr_notify <= 1'b0;
      end
    end
  end
  assign interrupt_notify = itr_notify;

  // Read request ---------------------------------------------------------------------------------
  logic rreq_timeout;
  logic rreq_timeout_cdc;
  logic rreq_ct_transmitted;
  logic rreq_send_request;
  logic error_packet_id_mismatch;

  typedef enum {
    ST_WAIT_READ_REQUEST,
    ST_SEND_READ_REQUEST,
    ST_WAIT_PACKETS
  } st_read_req;

  st_read_req rreq_state;
  st_read_req rreq_next_state;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) rreq_state <= ST_WAIT_READ_REQUEST;
    else rreq_state <= rreq_next_state;
  end

  always_comb begin
    case (rreq_state)
      ST_WAIT_READ_REQUEST:
        rreq_next_state = new_read_request_pending ? ST_SEND_READ_REQUEST : ST_WAIT_READ_REQUEST;
      ST_SEND_READ_REQUEST:
        rreq_next_state = tx_frame_last ? ST_WAIT_PACKETS : ST_SEND_READ_REQUEST;
      ST_WAIT_PACKETS:
        // if error_packet_id_mismatch or timeout => ST_SEND_READ_REQUEST
        // if write into hbm is finished => ST_WAIT_READ_REQUEST
        rreq_next_state = (error_packet_id_mismatch | rreq_timeout_cdc) ? ST_SEND_READ_REQUEST : (rreq_ct_transmitted? ST_WAIT_READ_REQUEST: ST_WAIT_PACKETS);
    endcase
  end

  // TODO:
  assign error_packet_id_mismatch = 1'b0;
  assign rreq_timeout_cdc = 1'b0;
  assign rreq_ct_transmitted = 1'b0;

  assign rreq_send_request = (rreq_state == ST_SEND_READ_REQUEST) ? 1'b1: 1'b0;

  // Ciphertext EMission (CEM) --------------------------------------------------------------------
  logic currently_emitting_ct;
  logic cem_over;

  typedef enum {
    CEM_WAIT_REQUEST,
    CEM_READ_N_SEND
  } st_cem;

  st_cem cem_state;
  st_cem cem_next_state;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) cem_state <= CEM_WAIT_REQUEST;
    else cem_state <= cem_next_state;
  end

  always_comb begin
    case (cem_state)
      CEM_WAIT_REQUEST:
        cem_next_state = new_ct_emission_request_pending ? CEM_READ_N_SEND : CEM_WAIT_REQUEST;
      CEM_READ_N_SEND:
        cem_next_state = cem_over ? CEM_WAIT_REQUEST : CEM_READ_N_SEND;
    endcase
  end

  assign currently_emitting_ct = (cem_state == CEM_READ_N_SEND) ? 1'b1: 1'b0;

  // TODO:
  assign ct_emission_request_in_use = 1'b0;
  assign cem_over = 1'b0;

  // =========================================================================================== //
  // arbiter
  // =========================================================================================== //
  // very simple round robin arbiter
  arbiter # (
    .N(4)
  ) arbiter (
    .clk    (clk_mrmac),
    .resetn (resetn_mrmac),

    .request({new_notify_request_pending, new_notify_ack_pending, new_read_request_pending, new_ct_emission_request_pending}),
    .grant(  {notify_request_granted    , notify_ack_granted    , read_request_granted    , ciphertext_emission_granted})
  );

  // =========================================================================================== //
  // QSFP RX
  // =========================================================================================== //
  // We must gather RX data as soon as possible and redirect commands into their respective
  // command queue or signal.
  // - ACK Notify TX is only a reception signal     : ntx_ack
  // - Notify RX goes to respective queue           : NRXQ
  // - Read request goes to write fifo to go to HBM : RRFIFO
  // - Ciphertext Emission goes to queue            : CEQ
  logic qsfp_rx_tsop;
  logic qsfp_rx_tvalidD;

  always_ff @(posedge clk_mrmac)
    qsfp_rx_tvalidD <= qsfp_rx_tvalid;

  assign qsfp_rx_tsop = qsfp_rx_tvalid & ~qsfp_rx_tvalidD;

  logic [$clog2(ETH_LEN_MAX):0] rx_counter;
  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      rx_counter <= 'h0;
    end else begin
      if (qsfp_rx_tvalid) begin
        rx_counter <= rx_counter+1;
      end else begin
        rx_counter <= 0;
      end
    end
  end

  /* First frame:
   * rx_dst_mac_addr
   *    destination mac address is not needed from the first clock cycle
   *    this register will help define if next words in receptions are valid
   */
  logic rx_valid;
  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      rx_dst_mac_addr <= 'h0;
    end else begin
      if (qsfp_rx_tvalid) begin
        if (qsfp_rx_tsop) begin
          rx_dst_mac_addr <=  qsfp_rx_tdata[16+MAC_ADDR_W-1:16];
        end
      end else begin
        rx_dst_mac_addr <= 'h0;
      end
    end
  end
  assign rx_valid = (current_hpu_mac == rx_dst_mac_addr) ? 1'b1 : 1'b0;

  /* Second frame:
   * sec_num, request_id, hpu_id, src_mac_address
   * ethernet len is skipped: not used for now
   */
  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      rx_sec_num <= 'h0;
      rx_req_id <= 'h0;
      rx_hpu_id <= 'h0;
      rx_src_mac_addr <= 'h0;
    end else begin
      if (qsfp_rx_tvalid) begin
        if (rx_counter == 1) begin
          rx_sec_num <= qsfp_rx_tdata[SEQ_NUM_W-1:0];
          rx_req_id <= qsfp_rx_tdata[SEQ_NUM_W+HPU_ID_W+REQ_ID_W-1:SEQ_NUM_W+HPU_ID_W];
          rx_hpu_id <= qsfp_rx_tdata[SEQ_NUM_W+HPU_ID_W-1:SEQ_NUM_W];
          rx_src_mac_addr <= qsfp_rx_tdata[SEQ_NUM_W+HPU_ID_W+REQ_ID_W+ETHERNET_LEN+MAC_ADDR_W-1:SEQ_NUM_W+HPU_ID_W+REQ_ID_W+ETHERNET_LEN];
        end
      end else begin
        rx_sec_num <= 'h0;
        rx_req_id <= 'h0;
        rx_hpu_id <= 'h0;
        rx_src_mac_addr <= 'h0;
      end
    end
  end

  /* Third frame:
   * iop_id, src/dst addresses
   * size_b for triggering error
   */
  always_ff @(posedge clk_mrmac) begin
    if(~resetn_mrmac)begin
      rx_iop_id       <= 'h0;
      rx_ct_src_addr  <= 'h0;
      rx_ct_dst_addr  <= 'h0;
    end else begin
      if (qsfp_rx_tvalid) begin
        if (rx_counter == 2) begin
          rx_iop_id      <= qsfp_rx_tdata[8+SIZE_B_W+IOP_ID_W-1:8+SIZE_B_W];
          rx_ct_dst_addr <= qsfp_rx_tdata[8+SIZE_B_W+IOP_ID_W+SRC_ADDR_W-1:8+SIZE_B_W+IOP_ID_W];
          rx_ct_src_addr <= qsfp_rx_tdata[8+SIZE_B_W+IOP_ID_W+SRC_ADDR_W+DST_ADDR_W-1:8+SIZE_B_W+IOP_ID_W+SRC_ADDR_W];
        end
      end else begin
        rx_iop_id       <= 'h0;
        rx_ct_src_addr  <= 'h0;
        rx_ct_dst_addr  <= 'h0;
      end
    end
  end

  assign rx_size_b = ((rx_counter == 2) & rx_valid) ? qsfp_rx_tdata[8+SIZE_B_W-1:8] : 'h0;

  // switch between components -----------------------------------------------------------------

  assign notify_ack_received            = (rx_valid & (rx_req_id == REQ_ID_ACK_NOTIFY_TX)) ? 1'b1 : 1'b0;
  assign notify_request_received        = (rx_valid & (rx_req_id == REQ_ID_NOTIFY_TX))     ? 1'b1 : 1'b0;
  assign read_request_received          = (rx_valid & (rx_req_id == REQ_ID_READ))          ? 1'b1 : 1'b0;
  assign ciphertext_emission_received   = (rx_valid & (rx_req_id == REQ_ID_EMISSION))      ? 1'b1 : 1'b0;

  // sending command to read request command queue ------------------------------------------------
  // when qsfp tlast is ready we are sure that all commands have been correctly received
  // we need to pass along:
  //    > IOP ID
  //    > HPU ID
  //    > DST ADDR
  //    > SRC ADDR
  // RREQ_CMD_DATA_W is defined in the package

  logic [RREQ_CMD_DATA_W-1:0] rreq_cmd_data_in;
  logic [RREQ_CMD_DATA_W-1:0] rreq_cmd_out_data;
  logic                       rreq_cmd_ready; // ~full
  logic                       rreq_cmd_we;
  logic                       rreq_cmd_out_valid;
  logic                       rreq_cmd_out_ready;

  assign rreq_cmd_data_in = {rx_hpu_id, rx_iop_id, rx_ct_dst_addr, rx_ct_src_addr};
  assign rreq_cmd_we = qsfp_rx_tlast & rreq_cmd_ready & read_request_received;
  assign rreq_cmd_out_ready = ~currently_emitting_ct;

  fifo_ram_rdy_vld # (
    .WIDTH      (RREQ_CMD_DATA_W),
    .DEPTH      (RREQ_CMD_DEPTH),
    .RAM_LATENCY(RREQ_CMD_RAM_LATENCY)
  ) rreq_command_queue (
    .clk    (clk_mrmac),
    .s_rst_n(~resetn_mrmac),

    .in_data(rreq_cmd_data_in),
    .in_vld (rreq_cmd_we),
    .in_rdy (rreq_cmd_ready),

    .out_data(rreq_cmd_out_data),
    .out_vld (rreq_cmd_out_valid),
    .out_rdy (rreq_cmd_out_ready)
  );

  logic [RQQ_CMD_DATA_COUNT_W-1:0] rreq_cnt;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      rreq_cnt <= 'h0;
    end else begin
      if (rreq_cmd_we) begin
        rreq_cnt <= rreq_cnt + 1;
      end else if (rreq_cmd_out_valid) begin
        rreq_cnt <= rreq_cnt - 1;
      end
    end
  end
  assign new_ct_emission_request_pending = (rreq_cnt != 0) ? 1'b1 : 1'b0;

  logic error_rreq_cmd_full_packet_drop;
  assign error_rreq_cmd_full_packet_drop = qsfp_rx_tlast & ~rreq_cmd_ready;

  // sending notify ack as fast as possible -------------------------------------------------------
  logic notify_request_receivedD;
  always_ff @(posedge clk_mrmac)
    notify_request_receivedD <= notify_request_received;

  logic                            send_ack;
  logic                            nack_tlast;
  logic [MRMAC_AXIS_W-1:0]         nack_tdata;
  logic                            nack_tvalid;
  logic [$clog2(NB_WORDS_MIN)+1:0] nack_cnt;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      send_ack <= 1'b0;
    end else begin
      if (notify_request_received & ~notify_request_receivedD) begin
        send_ack <= 1'b1;
      end else if (nack_tlast) begin
        send_ack <= 1'b0;
      end
    end
  end

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      nack_cnt <= 'h0;
    end else begin
      if (send_ack) begin
        if((nack_cnt < NB_WORDS_MIN+1) & qsfp_tx_tready & notify_ack_granted) begin
          nack_cnt <= nack_cnt+1;
        end
      end else begin
        nack_cnt <= 'h0;
      end
    end
  end

  assign new_notify_ack_pending = send_ack;
  assign nack_tlast = (nack_cnt == NB_WORDS_MIN) ? 1'b1 : 1'b0;
  assign notify_ack_in_use = notify_ack_granted & send_ack;

  // Errors on RX path ---------------------------------------------------------------------------
  logic error_rx_tkeep;
  logic error_rx_unexpected_size_b;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      error_rx_tkeep <= 1'b0;
    end else begin
      if (qsfp_rx_tvalid & (qsfp_rx_tkeep_user != 'hff))
        error_rx_tkeep <= 1'b1;
    end
  end

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      error_rx_unexpected_size_b <= 1'b0;
    end else begin
      if ((rx_counter == 2) & (rx_size_b != SIZE_B))
        error_rx_unexpected_size_b <= 1'b1;
    end
  end

  // =========================================================================================== //
  // Read into HBM
  // all @mrmac domain
  // =========================================================================================== //
  // phys_addr = hbm_pc_offset + ctId * ciphertext_size

  logic [RREQ_CMD_DATA_W-1:0] read_request_cmd;
  logic [       SIZE_B_W-1:0] rr_size_b;
  logic [       IOP_ID_W-1:0] rr_iop_id;
  logic [     SRC_ADDR_W-1:0] rr_ct_src_addr;
  logic [     DST_ADDR_W-1:0] rr_ct_dst_addr;


  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      read_request_cmd <= 'h0;
    end else begin
      if (rreq_cmd_out_valid) begin
        read_request_cmd <= rreq_cmd_out_data;
      end
    end
  end

  assign rr_size_b      = read_request_cmd[SRC_ADDR_W+DST_ADDR_W+IOP_ID_W+SIZE_B_W-1:0];
  assign rr_iop_id      = read_request_cmd[SRC_ADDR_W+DST_ADDR_W+IOP_ID_W-1:0];
  assign rr_ct_dst_addr = read_request_cmd[SRC_ADDR_W+DST_ADDR_W-1:0];
  assign rr_ct_src_addr = read_request_cmd[SRC_ADDR_W-1:0];

  // where to read ?
  // we have two NMU to address, each NMU addresses a different pseudo channel

  // fifo_ram_rdy_vld # (
  //   .WIDTH      (CE_READ_DATA_W),
  //   .DEPTH      (CE_READ_DEPTH),
  //   .RAM_LATENCY(CE_READ_RAM_LATENCY)
  // ) ce_read_fifo_ping (
  //   .clk    (clk_mrmac),
  //   .s_rst_n(~resetn_mrmac),

  //   .in_data(),
  //   .in_vld (),
  //   .in_rdy (),

  //   .out_data(),
  //   .out_vld (),
  //   .out_rdy ()
  // );

  // fifo_ram_rdy_vld # (
  //   .WIDTH      (CE_READ_DATA_W),
  //   .DEPTH      (CE_READ_DEPTH),
  //   .RAM_LATENCY(CE_READ_RAM_LATENCY)
  // ) ce_read_fifo_pong (
  //   .clk    (clk_mrmac),
  //   .s_rst_n(~resetn_mrmac),

  //   .in_data(),
  //   .in_vld (),
  //   .in_rdy (),

  //   .out_data(),
  //   .out_vld (),
  //   .out_rdy ()
  // );

  // =========================================================================================== //
  // QSFP TX
  // =========================================================================================== //
  // We must be able to send frames into tx link for:
  // - Notify TX
  // - Notify RX (ack)
  // - Read request
  // - Ciphertext emissions

  // building output signals --------------------------------------------------
  logic [MRMAC_AXIS_W-1:0]         tx_frame;
  logic                            tx_frame_valid;
  logic [$clog2(NB_WORDS_MIN)+1:0] tx_cnt;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      tx_cnt        <= 'h0;
    end else begin
      if ((ntx_state == ST_SEND_NOTIFY) | (rreq_state == ST_SEND_READ_REQUEST))begin
        if((tx_cnt < NB_WORDS_MIN+1) & qsfp_tx_tready) begin
          tx_cnt <= tx_cnt +1;
        end else begin
          tx_cnt <= 'h0;
        end
      end else begin
        tx_cnt <= 'h0;
      end
    end
  end

  assign tx_frame_last = (tx_cnt == NB_WORDS_MIN+1) ? 1'b1: 1'b0;
  assign tx_frame_valid = (tx_cnt == 'h0) ? 1'b0 : 1'b1 ;

  logic [  MAC_ADDR_W-1:0] tx_target_hpu_mac;
  logic [ETHERNET_LEN-1:0] tx_eth_len;
  logic [    REQ_ID_W-1:0] tx_req_id;
  logic [   SEQ_NUM_W-1:0] tx_seq_num;
  logic [  SRC_ADDR_W-1:0] tx_src_addr;
  logic [  DST_ADDR_W-1:0] tx_dst_addr;
  logic [    IOP_ID_W-1:0] tx_iop_id;
  logic [    SIZE_B_W-1:0] tx_size_b;

  assign tx_target_hpu_mac = rreq_send_request ? hpu_mac_table[rrqq_node_id] : hpu_mac_table[nrqq_node_id];
  assign tx_eth_len  = ETH_LEN_MIN;
  assign tx_req_id   = rreq_send_request ? REQ_ID_READ : REQ_ID_NOTIFY_TX;
  assign tx_seq_num  = 'h0;
  assign tx_src_addr = rreq_send_request ? rrqq_src_addr : nrqq_src_addr;
  assign tx_dst_addr = rreq_send_request ? rrqq_dst_addr : 'h0;
  assign tx_iop_id   = rreq_send_request ? rrqq_iop_id   : nrqq_iop_id;
  assign tx_size_b   = rreq_send_request ? rrqq_size_b   : nrqq_size_b;

  // this is an hardcoded configuration
  always_comb begin
    case (tx_cnt)
      'h1 :
        tx_frame = {MAC_OUI, tx_target_hpu_mac, MAC_OUI[MAC_OUI_W-1:8]};
      'h2 :
        tx_frame = {MAC_OUI[7:0], current_hpu_mac, tx_eth_len, tx_req_id, current_hpu_id, tx_seq_num};
      'h3 :
        tx_frame = {tx_src_addr, tx_dst_addr, tx_iop_id, tx_size_b, 8'b0};
      'h0, 'h3, 'h4 , 'h5 , 'h6, 'h7: begin
        tx_frame = 'h0;
      end
      default:
        tx_frame = 'h0;
    endcase
  end

  // Notify ack -----------------------------------------------------------------------------------
  // in case notify request received
  logic [ETH_HEADER_SIZE-1:0][MRMAC_AXIS_W-1:0] nack_frame;

  // nack_frame[2] is ready when nack_cnt==1 which is perfectly fine as it will be sent @nack_cnt=2
  always_ff @(posedge clk_mrmac) begin
    if (~ resetn_mrmac) begin
      nack_frame <= 'h0;
    end else begin
      if (notify_request_received) begin
        nack_frame[0] <= {MAC_OUI, rx_src_mac_addr, MAC_OUI[MAC_OUI_W-1:8]};
        nack_frame[1] <= {MAC_OUI[7:0], current_hpu_mac, ETH_LEN_MIN, REQ_ID_ACK_NOTIFY_TX, rx_hpu_id, tx_seq_num};
        nack_frame[2] <= {rx_ct_src_addr, rx_ct_dst_addr, rx_iop_id, {SIZE_B_W{1'b0}}, 8'b0};
      end
    end
  end

  // this is an hardcoded configuration
  always_comb begin
    case (nack_cnt)
      'h1 :
        nack_tdata = nack_frame[0];
      'h2 :
        nack_tdata = nack_frame[1];
      'h3 :
        nack_tdata = nack_frame[2];
      'h0, 'h3, 'h4 , 'h5 , 'h6, 'h7: begin
        nack_tdata = 'h0;
      end
      default:
        nack_tdata = 'h0;
    endcase
  end

  assign nack_tvalid = (nack_cnt == 'h0) ? 1'b0 : 1'b1 ;

  logic [3:0] use_tx;

  always_ff @(posedge clk_mrmac) begin : read_rq_control_ready
    if (~resetn_mrmac) begin
      read_request_in_use <= 1'b0;
    end else begin
      if (read_request_granted) begin
        read_request_in_use <= 1'b1;
      end else if (tx_frame_last) begin
        read_request_in_use <= 1'b0;
      end
    end
  end

  // note that thanks to the arbiter it's not possible to have several *_in_use at the same time
  assign use_tx = {notify_request_in_use, notify_ack_in_use, read_request_in_use, ct_emission_request_in_use};

  always_comb begin
    case (use_tx)
    4'b1000:
    begin
      qsfp_tx_tvalid     = tx_frame_valid;
      qsfp_tx_tdata      = qsfp_tx_tvalid ? tx_frame : 'h0 ;
      qsfp_tx_tkeep_user = qsfp_tx_tvalid ? 'hFF : 0;
      qsfp_tx_tlast      = tx_frame_last;
    end
    4'b0100:
    begin
      qsfp_tx_tvalid     = nack_tvalid;
      qsfp_tx_tdata      = qsfp_tx_tvalid ? nack_tdata : 'h0 ;
      qsfp_tx_tkeep_user = qsfp_tx_tvalid ? 'hFF : 0;
      qsfp_tx_tlast      = nack_tlast;
    end
    4'b0010:
    begin
      qsfp_tx_tvalid     = tx_frame_valid;
      qsfp_tx_tdata      = qsfp_tx_tvalid ? tx_frame : 'h0 ;
      qsfp_tx_tkeep_user = qsfp_tx_tvalid ? 'hFF : 0;
      qsfp_tx_tlast      = tx_frame_last;
    end
    // 4'b0001:
    default:
    begin
      qsfp_tx_tdata      = 'h0;
      qsfp_tx_tlast      = 'h0;
      qsfp_tx_tvalid     = 'h0;
      qsfp_tx_tkeep_user = 'h0;
    end
    endcase
  end

  // =========================================================================================== //
  // Statistics
  // specific for FPGA
  // =========================================================================================== //
  // logic [15:0] cnt_notify_ack; defined before for timeout
  logic [15:0] cnt_notify_read;

  logic start_cnt_notify_ack;
  logic notify_ack_received_cdc;

  /* how long it is between sending a notify request and receiving an acknowledge
   *  - starts when received_req (clk_cfg) is ones
   *  - stops when notify_ack_received (clk mrmac) is one
   */
  always_ff @(posedge clk_cfg) begin
    if (~resetn_cfg) begin
      start_cnt_notify_ack <= 1'b0;
    end else begin
      if (&received_req & (regf_req_id[23:20] == REQ_ID_NOTIFY_TX)) begin
        start_cnt_notify_ack <= 1'b1;
      end else if(notify_ack_received_cdc) begin
        start_cnt_notify_ack <= 1'b0;
      end
    end
  end

  always_ff @(posedge clk_cfg) begin
    if (~resetn_cfg) begin
      cnt_notify_ack <= 'h0;
    end else begin
      if (start_cnt_notify_ack) begin
        cnt_notify_ack <= cnt_notify_ack + 1;
      end else if (rst_cnt_notify | ntx_timeout) begin
        cnt_notify_ack <= 'h0;
      end
    end
  end

  xpm_cdc_single_wrapper # (
    .CDC_SYNC_STAGES(CDC_SYNC_STAGES),
    .SRC_INPUT_REG  (0)
  ) ack_xpm_cdc_single_wrapper (
    .src_clk(clk_mrmac),
    .src_in (notify_ack_received),

    .dest_clk(clk_cfg),
    .dest_out(notify_ack_received_cdc)
  );

  /* How long has the data been ready in the regif
   *  - counts when interruption is raised
   *  - itr_notify is on config clock
   */
  always_ff @(posedge clk_cfg) begin
    if (~resetn_cfg) begin
      cnt_notify_read <= 'h0;
    end else begin
      if (itr_notify) begin
        cnt_notify_read <= cnt_notify_read +1;
      end else if (rst_cnt_notify) begin
        cnt_notify_read <= 'h0;
      end
    end
  end

  assign stat_cnt_notify_ack  = cnt_notify_ack;
  assign stat_cnt_notify_read = cnt_notify_read;

  // =========================================================================================== //
  // Error agreggation
  // =========================================================================================== //
  // error_id_def: Definition of HPUs are not correct, several are defined as current
  // error_packet_id_mismatch: sec_num received is unexpected


endmodule
