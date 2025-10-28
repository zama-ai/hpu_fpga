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
#(
  parameter int FIFO_DEPTH    = 512,
  parameter int NB_WORD_W     = $clog2(FIFO_DEPTH)+1
) (
  // Ethernet configuration interface -----------------------------------------
  input  logic clk_cfg,
  input  logic resetn_cfg,
  // Ethernet fast clock interface --------------------------------------------
  input  logic clk_mrmac,
  input  logic resetn_mrmac,
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
  input  logic                        regf_tx_notify,
  output logic                        regf_rx_notify,
  input  logic [NB_MAX_HPU-1:0][31:0] regf_hpu_ids,

  input  logic [31:0]                 regf_req_id,
  input  logic [31:0]                 regf_req_addr,
  input  logic [ 1:0]                 received_req,
  output logic                        request_consumed,
  // QSFP system interface ----------------------------------------------------
  // == TX
  output logic [MRMAC_AXIS_W-1:0]  qsfp_tx_tdata,
  output logic [MRMAC_TKEEP_W-1:0] qsfp_tx_tkeep_user,
  output logic                     qsfp_tx_tlast,
  output logic                     qsfp_tx_tvalid,
  input  logic                     qsfp_tx_tready,
  // == RX
  input  logic [MRMAC_AXIS_W-1:0]  qsfp_rx_tdata,
  input  logic [MRMAC_TKEEP_W-1:0] qsfp_rx_tkeep_user,
  input  logic                     qsfp_rx_tlast,
  input  logic                     qsfp_rx_tvalid
);

  // =========================================================================================== //
  // localparam
  // =========================================================================================== //
  localparam int CDC_SYNC_STAGES = 2;

  // =========================================================================================== //
  // CDC from regf to mrmac clock
  // =========================================================================================== //
  // theses signals are quasi static: they should move rarely
  logic [CDC_SYNC_STAGES-1:0][NB_MAX_HPU-1:0][31:0] hpu_ids_cdc;
  logic                      [NB_MAX_HPU-1:0][31:0] hpu_ids; // just for naming simplification

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
  // when we have the data of both request identifier and addreses, we consume the information
  // once consumed, the top will receive the flag and toggle received requests
  assign request_consumed = (rrqq_wr_en | nrqq_wr_en) ? 1'b1 : 1'b0;
  // new pending requests on qsfp tx
  logic new_notify_request_pending;
  logic new_notify_ack_pending;
  logic new_read_request_pending;
  logic new_ct_emission_request_pending;

  logic notify_request_in_use;
  logic notify_ack_in_use;
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
  logic                        read_request_ready;

  // cfg
  assign rrqq_wr_en = (&received_req) & ~rrqq_wr_rst_busy & ~rrqq_full & (regf_req_id[23:20] == REQ_ID_READ);
  // mrmac
  assign new_read_request_pending = (rrqq_rd_data_count == 0) ? 1'b0 : 1'b1;
  assign rrqq_rd_en =  new_read_request_pending & read_request_ready & ~rrqq_rd_rst_busy & ~rrqq_empty;

  fifo_ram_rdy_vld_2clk # (
    .CDC_SYNC_STAGES (CDC_SYNC_STAGES),
    .WIDTH           (RQQ_WIDTH),
    // tweak theses parameters in package
    .DEPTH           (RQQ_DEPTH),
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
  logic [15:0] rrqq_dst_addr;
  logic [15:0] rrqq_src_addr;
  logic [15:0] rrqq_size_b;
  logic [ 3:0] rrqq_req_id;
  logic [ 3:0] rrqq_iop_id;
  logic [ 3:0] rrqq_node_id;

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
        rrqq_src_addr  <= rrqq_rd_data[31:16];
        rrqq_size_b    <= rrqq_rd_data[47:32];
        rrqq_iop_id    <= rrqq_rd_data[51:48];
        rrqq_req_id    <= rrqq_rd_data[55:52];
        rrqq_node_id   <= rrqq_rd_data[59:56];
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
  logic [       RQQ_WIDTH-1:0] nrqq_rd_data;
  logic                        nrqq_empty;
  logic [RQQ_DATA_COUNT_W-1:0] nrqq_rd_data_count;

  // cfg
  assign nrqq_wr_en = (&received_req) & ~nrqq_wr_rst_busy & ~nrqq_full & (regf_req_id[23:20] == REQ_ID_NOTIFY_TX);
  // mrmac
  assign new_notify_request_pending = (nrqq_rd_data_count == 0) ? 1'b0 : 1'b1;
  assign nrqq_rd_en =  new_notify_request_pending & notify_request_in_use & ~nrqq_rd_rst_busy & ~nrqq_empty;

  fifo_ram_rdy_vld_2clk # (
    .CDC_SYNC_STAGES (CDC_SYNC_STAGES),
    .WIDTH           (RQQ_WIDTH),
    // tweak theses parameters in package
    .DEPTH           (RQQ_DEPTH),
    .FIFO_MEMORY_TYPE(RQQ_MEMORY_TYPE)
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

  // none of theses informations are in the first word:
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
         hpu_id_table[i]    <= 'h0;
         hpu_mac_table[i]   <= 'h0;
         one_hot_id[i]  <= 'h0;
       end else begin
          hpu_id_table[i]   <= hpu_ids[i][HPU_ID_W+MAC_ADDR_W-1:MAC_ADDR_W];
          hpu_mac_table[i]  <= hpu_ids[i][MAC_ADDR_W-1:0];
          one_hot_id[i] <= hpu_ids[i][31];
        end
      end
    end
  endgenerate

  // if ever two hpu ids are set as "current", raise an error
  // when one_hot_id is all zeros, we cannot conclude if there is an error or not
  // TODO: if half is ones and the rest are zeros, erorr not raised
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

  // ==============================================================================================
  // FSM
  // ==============================================================================================
  logic notify_request_granted;
  logic notify_ack_granted;
  logic read_request_granted;
  logic ciphertext_emission_granted;

  logic nack_frame_valid;
  logic rr_frame_valid;
  logic ce_frame_valid;

  assign nack_frame_valid = 'h0;
  assign rr_frame_valid = 'h0;
  assign ce_frame_valid = 'h0;

  logic tx_line_in_use;
  assign tx_line_in_use = notify_request_in_use | notify_ack_in_use | read_request_in_use | ct_emission_request_in_use;

  // Notify TX (NTX) ------------------------------------------------------------------------------
  logic notify_ack_received;
  logic ntx_frame_last;
  logic ntx_timeout;
  // TODO
  assign ntx_timeout = 1'b0;

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
        ntx_next_state = ntx_frame_last ? ST_WAIT_ACK : ST_SEND_NOTIFY;
      ST_WAIT_ACK:
      ntx_next_state = notify_ack_received ? ST_WAIT_REQUEST : (ntx_timeout ? ST_SEND_NOTIFY : ntx_next_state);
    endcase
  end

  assign notify_request_in_use = (ntx_state == ST_SEND_NOTIFY) | (ntx_state == ST_WAIT_ACK) ? 1'b1: 1'b0;

  logic [$clog2(NB_WORDS_MIN)+1:0] ntx_cnt;

  assign ntx_frame_last = (ntx_cnt == NB_WORDS_MIN+1) ? 1'b1: 1'b0;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      ntx_cnt        <= 'h0;
    end else begin
      if(ntx_state == ST_SEND_NOTIFY) begin
        if((ntx_cnt < NB_WORDS_MIN+1) & qsfp_tx_tready) begin
          ntx_cnt <= ntx_cnt +1;
        end else begin
          ntx_cnt <= 'h0;
        end
      end else begin
        ntx_cnt <= 'h0;
      end
    end
  end

  // building output signals --------------------------------------------------
  logic [MRMAC_AXIS_W-1:0] ntx_frame;
  logic                    ntx_frame_valid;

  assign ntx_frame_valid = (ntx_cnt == 'h0) ? 1'b0 : 1'b1 ;

  logic [MAC_ADDR_W-1:0] ntx_target_hpu_mac;
  logic [DST_ADDR_W-1:0] nrqq_dst_addr;
  logic [ SEQ_NUM_W-1:0] nrqq_seq_num;

  // there is no seq num for notify request
  assign nrqq_seq_num = 'h0;
  assign nrqq_dst_addr = 'h0;
  assign ntx_target_hpu_mac = hpu_mac_table[nrqq_node_id];

  // this is an hardcoded configuration
  always_comb begin
    case (ntx_cnt)
      'h1 :
        ntx_frame = {MAC_OUI, ntx_target_hpu_mac, MAC_OUI[MAC_OUI_W-1:8]};
      'h2 :
        ntx_frame = {MAC_OUI[7:0], current_hpu_mac, ETH_LEN_MIN, REQ_ID_NOTIFY_TX, current_hpu_id, nrqq_seq_num};
      'h3 :
        ntx_frame = {nrqq_src_addr, nrqq_dst_addr, nrqq_iop_id, nrqq_size_b, 8'b0};
      'h0, 'h3, 'h4 , 'h5 , 'h6, 'h7: begin
        ntx_frame = 'h0;
      end
      default:
        ntx_frame = 'h0;
    endcase
  end

  // Notify RX (NRX) ------------------------------------------------------------------------------

  // input lane_write_busy
  logic read_rq_interrupt_toggled;

  always_ff @(posedge clk_mrmac) begin : read_rq_control_ready
    if (~resetn_mrmac) begin
      read_request_ready <= 1'b0;
    end else begin
      if (rrqq_req_id == REQ_ID_READ) begin
        read_request_ready <= 1'b1;
      end else if (read_rq_interrupt_toggled) begin
        read_request_ready <= 1'b0;
      end
    end
  end

  // tx_notify_ack
  // tx_notify_new_rq
  // tx_notify_timeout

  // rx_notify_new_rq
  // rx_notify_interrupt

  // ct_emission_new_rq
  // ct_emission_finished

  // read_request_new_rq
  // read_request_timeout

  // TODO:
  assign new_notify_ack_pending = 1'b0;
  assign new_ct_emission_request_pending = 1'b0;
  assign notify_ack_in_use = 1'b0;
  assign read_request_in_use = 1'b0;
  assign ct_emission_request_in_use = 1'b0;


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
  logic qsfp_rx_tsop;

  logic qsfp_rx_tvalidD;
  always_ff @(posedge clk_mrmac)
    qsfp_rx_tvalidD <= qsfp_rx_tvalid;

  assign qsfp_rx_tsop = qsfp_rx_tvalid & ~qsfp_rx_tvalidD;

  // We must gather RX data as soon as possible and redirect commands into their respective
  // command queue or signal.
  // - ACK Notify TX is only a reception signal     : ntx_ack
  // - Notify RX goes to respective queue           : NRXQ
  // - Read request goes to write fifo to go to HBM : RRFIFO
  // - Ciphertext Emission goes to queue            : CEQ

  // control signals
  logic [$clog2(ETH_LEN_MAX):0] rx_counter;
  logic                         rx_target_valid;
  logic                         rx_valid;
  logic [       MAC_ADDR_W-1:0] source_hpu_mac;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      rx_counter <= 'h0;
    end else begin
      if (qsfp_rx_tvalid) begin
        rx_counter <= rx_counter+1;
      end else if (qsfp_rx_tlast) begin
        rx_counter <= 0;
      end
    end
  end

  // First frame I can check that the dstination address is me
  logic [MAC_ADDR_W-1:0] rx_dst_mac_addr;
  // Second frame I will know who is the sender, request ID, seq num
  logic [SEQ_NUM_W-1:0]  rx_sec_num;
  logic [HPU_ID_W-1:0]   rx_hpu_id;
  logic [REQ_ID_W-1:0]   rx_req_id;
  logic [MAC_ADDR_W-1:0] rx_src_mac_addr;
  // third frame, ct src/dst address, iop id, size_byte
  logic [SIZE_B_W-1:0]   rx_size_b;
  logic [SIZE_B_W-1:0]   rx_iop_id;
  logic [SRC_ADDR_W-1:0] rx_ct_src_addr;
  logic [DST_ADDR_W-1:0] rx_ct_dst_addr;

  /* First frame:
   * rx_dst_mac_addr
   *    destination mac address is not needed from the first clock cycle
   *    => register to make a decision for next cc
   */
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
          rx_req_id  <= qsfp_rx_tdata[SEQ_NUM_W+HPU_ID_W+REQ_ID_W-1:SEQ_NUM_W+HPU_ID_W];
          rx_hpu_id       <= qsfp_rx_tdata[SEQ_NUM_W+HPU_ID_W-1:SEQ_NUM_W];
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

  // switch betweeen components -----------------------------------------------------------------
  assign source_hpu_mac =  qsfp_rx_tvalid ? hpu_mac_table[rx_hpu_id] : 1'b0;
  assign rx_target_valid = (current_hpu_mac == rx_dst_mac_addr) ? 1'b1 : 1'b0;
  assign rx_valid = (rx_target_valid & (source_hpu_mac == rx_src_mac_addr)) ? 1'b1 : 1'b0;

  assign notify_ack_received            = (rx_valid & (rx_req_id == REQ_ID_ACK_NOTIFY_TX)) ? 1'b1 : 1'b0;
  assign notify_request_received        = (rx_valid & (rx_req_id == REQ_ID_NOTIFY_TX))     ? 1'b1 : 1'b0;
  assign read_request_received          = (rx_valid & (rx_req_id == REQ_ID_READ))          ? 1'b1 : 1'b0;
  assign ciphertext_emission_received   = (rx_valid & (rx_req_id == REQ_ID_EMISSION))      ? 1'b1 : 1'b0;


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
  // QSFP TX
  // =========================================================================================== //
  // We must be able to send frames into tx link for:
  // - Notify TX
  // - Notify RX (ack)
  // - Read request
  // - Ciphertext emissions

  logic [3:0] use_tx;

  // note that thanks to the arbiter it's not possible to have several *_in_use at the same time
  assign use_tx = {notify_request_in_use, notify_ack_in_use, read_request_in_use, ct_emission_request_in_use};

  always_comb begin
    case (use_tx)
    4'b1000:
    begin
      qsfp_tx_tvalid     = ntx_frame_valid;
      qsfp_tx_tdata      = qsfp_tx_tvalid ? ntx_frame : 'h0 ;
      qsfp_tx_tkeep_user = qsfp_tx_tvalid ? 'hFF : 0;
      qsfp_tx_tlast      = ntx_frame_last;
    end
    // 4'b0100:
    // 4'b0010:
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

endmodule
