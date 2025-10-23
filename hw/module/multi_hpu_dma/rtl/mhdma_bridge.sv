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


  // ReQuest Queues - -----------------------------------------------------------------------------
  logic rrqq_wr_en; // read request queue write enable
  logic nrqq_wr_en; // notify request queue write enable
  // when we have the data of both request identifier and addreses, we consume the information
  // once consumed, the top will receive the flag and toggle received requests
  always_ff @(posedge clk_cfg) begin
    if (~resetn_cfg) begin
      request_consumed <= 1'b0;
    end else begin
      if (rrqq_wr_en | nrqq_wr_en) begin
        request_consumed <= 1'b1;
      end else begin
        request_consumed <= 1'b0;
      end
    end
  end

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
  logic                        new_request_pending;

  // cfg
  assign rrqq_wr_en = (&received_req) & ~rrqq_wr_rst_busy & ~rrqq_full & (regf_req_id[23:20] == REQ_ID_READ);
  // mrmac
  assign new_request_pending = (rrqq_rd_data_count == 0) ? 1'b0 : 1'b1;
  assign rrqq_rd_en =  new_request_pending & read_request_ready & ~rrqq_rd_rst_busy & ~rrqq_empty;

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
  logic [15:0] rrqq_dest_addr;
  logic [15:0] rrqq_src_addr;
  logic [15:0] rrqq_size_b;
  logic [ 3:0] rrqq_req_id;
  logic [ 3:0] rrqq_iop_id;
  logic [ 3:0] rrqq_node_id;

  always_ff @(posedge clk_mrmac) begin : read_request_sampling
    if (~resetn_mrmac) begin
      rrqq_dest_addr <= 'h0;
      rrqq_src_addr  <= 'h0;
      rrqq_size_b    <= 'h0;
      rrqq_iop_id    <= 'h0;
      rrqq_req_id    <= 'h0;
      rrqq_node_id   <= 'h0;
    end else begin
      if (rrqq_data_valid) begin
        rrqq_dest_addr <= rrqq_rd_data[15:00];
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
  // needed control signals for sampling (mrmac clock)
  logic                        notify_request_ready;
  logic                        new_notify_request_pending;

  // cfg
  assign nrqq_wr_en = (&received_req) & ~nrqq_wr_rst_busy & ~nrqq_full & (regf_req_id[23:20] == REQ_ID_NOTIFY_TX);
  // mrmac
  assign new_notify_request_pending = (nrqq_rd_data_count == 0) ? 1'b0 : 1'b1;
  assign nrqq_rd_en =  new_notify_request_pending & notify_request_ready & ~nrqq_rd_rst_busy & ~nrqq_empty;

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
  logic [15:0] nrqq_dest_addr;
  logic [15:0] nrqq_src_addr;
  logic [15:0] nrqq_size_b;
  logic [ 3:0] nrqq_req_id;
  logic [ 3:0] nrqq_iop_id;
  logic [ 3:0] nrqq_node_id;

  always_ff @(posedge clk_mrmac) begin : notify_request_sampling
    if (~resetn_mrmac) begin
      nrqq_dest_addr <= 'h0;
      nrqq_src_addr  <= 'h0;
      nrqq_size_b    <= 'h0;
      nrqq_iop_id    <= 'h0;
      nrqq_req_id    <= 'h0;
      nrqq_node_id   <= 'h0;
    end else begin
      if (nrqq_data_valid) begin
        nrqq_dest_addr <= nrqq_rd_data[15:00];
        nrqq_src_addr  <= nrqq_rd_data[31:16];
        nrqq_size_b    <= nrqq_rd_data[47:32];
        nrqq_iop_id    <= nrqq_rd_data[51:48];
        nrqq_req_id    <= nrqq_rd_data[55:52];
        nrqq_node_id   <= nrqq_rd_data[59:56];
      end
    end
  end

  // ==============================================================================================
  // hpu identification
  // ==============================================================================================
  logic [NB_MAX_HPU-1:0][HPU_ID_W-1:0]   hpu_id_table;
  logic [NB_MAX_HPU-1:0][MAC_ADDR_W-1:0] hpu_mac_table;
  logic [NB_MAX_HPU-1:0]                 current_hpu_id; //one hot
  logic                                  identification_error;

  assign hpu_ids = hpu_ids_cdc[CDC_SYNC_STAGES-1];

  generate
    for (genvar i=0; i<NB_MAX_HPU; i++) begin
      always_ff @(posedge clk_mrmac) begin : hpu_id_table_creation
       if (~resetn_mrmac) begin
         hpu_id_table[i]    <= 'h0;
         hpu_mac_table[i]   <= 'h0;
         current_hpu_id[i]  <= 'h0;
       end else begin
          hpu_id_table[i]   <= hpu_ids[i][HPU_ID_W+MAC_ADDR_W-1:MAC_ADDR_W];
          hpu_mac_table[i]  <= hpu_ids[i][MAC_ADDR_W-1:0];
          current_hpu_id[i] <= hpu_ids[i][31];
        end
      end
    end
  endgenerate

  // if ever two hpu ids are set as "current", raise an error
  // when current_hpu_id is all zeros, we cannot conclude if there is an error or not
  always_ff @(posedge clk_mrmac) begin : error_on_hpu_id
    if (~resetn_mrmac) begin
      identification_error <= 1'b0;
    end else begin
      identification_error <= (current_hpu_id==0) ? 'b0: ~ (^current_hpu_id);
    end
  end

  // just to simplify notations
  logic [          HPU_ID_W-1:0] curent_hpu_id;
  logic [        MAC_ADDR_W-1:0] curent_hpu_mac;
  logic [$clog2(NB_MAX_HPU)-1:0] hpu_index;

  always_comb begin
      hpu_index = '0;
      for (int i = 0; i < NB_MAX_HPU; i++)
          if (current_hpu_id[i])
              hpu_index = i;
  end

  assign curent_hpu_mac = identification_error | (current_hpu_id==0)? 'h0 : hpu_mac_table[hpu_index];
  assign curent_hpu_id  = identification_error | (current_hpu_id==0)? 'h0 : hpu_id_table[hpu_index];


  // ==============================================================================================
  // packet decoder
  // ==============================================================================================
  // On RX lanes, should know as soon as possible what type of packets I should see

  // ==============================================================================================
  // FSM
  // ==============================================================================================
  // input lane_write_busy
  logic notify_tx_ack_received;
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

  always_ff @(posedge clk_mrmac) begin : notify_tx_control_ready
    if (~resetn_mrmac) begin
      notify_request_ready <= 1'b0;
    end else begin
      if (nrqq_req_id == REQ_ID_NOTIFY_TX) begin
        notify_request_ready <= 1'b1;
      end else if (notify_tx_ack_received) begin
        notify_request_ready <= 1'b0;
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

  typedef enum {
    ST_WAIT_REQUEST,
    ST_WAIT_ACK,
    ST_SEND_NOTIFY
  } st_notify_tx;

  // st_notify_tx state;
  // st_notify_tx next_state;


endmodule
