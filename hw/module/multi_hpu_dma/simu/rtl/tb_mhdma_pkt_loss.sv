// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : This testbench tests packet losses
//
// Let's say HPU_A sends and receive data from HPU_B (HPU_B is this testbench)
//
// Notify:
// - Loss of an ack:
//   -> HPU_A send a Notify and doesn't receive an ack, after a timeout request is re-sent
//
// Read request:
// - seq_num is incorrect
//   -> HPU_A performs a read request to B, B sends an incorrect seq_num. A must resend request
// - timeout is reached
//   -> HPU_A performs a read request into B and no answer is performed
//
// ==============================================================================================

`resetall
`timescale 1ns/10ps
module tb_mhdma_pkt_loss;
  import mhdma_pkg::*;                    // multi-hpu-dma
  import axi_if_shell_axil_pkg::*;        // axi4-lite + REG_DATA_W
  import axi_if_common_param_pkg::*;      // general axi4
  import hpu_regif_core_eth_2in3_pkg::*;  // ethernet regif
  import axi_if_eth_axi_pkg::*;           // AXI ethernet

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int CLK_HALF_PERIOD_A = 4;
  localparam int CLK_HALF_PERIOD_B = 1;
  localparam int ARST_ACTIVATION = 17;

  localparam int FIFO_DEPTH = 512;

  localparam int NB_HPU = 8;
  localparam [31:0] TIMEOUT_DUR_NOTIFY = 'd80;
  localparam [31:0] TIMEOUT_DUR_READ_REQ = 'd4000;

  // ciphertext memories -------------------------------------------------------------------------
  localparam int MEM_WR_CMD_BUF_DEPTH = 4;  // Should be >= 1
  localparam int MEM_RD_CMD_BUF_DEPTH = 1;  // Should be >= 1
  // Data latency
  localparam int MEM_WR_DATA_LATENCY = 42;  // Should be >= 1
  localparam int MEM_RD_DATA_LATENCY = 1;   // Should be >= 1
  // Set random on ready valid, on write path
  localparam bit MEM_USE_WR_RANDOM = 1;
  // Set random on ready valid, on read path
  localparam bit MEM_USE_RD_RANDOM = 0;     // check path, no need random

  // simulation sizes to reduce runtime
  localparam int MEM_SIM_SIZE = 18;         // must be < 22
  localparam int SIZE_B_SIM   = 'h40;

  localparam int MAX_BURST_SIZE  = PAGE_BYTES/AXI4_DATA_BYTES;

  localparam [3:0] PC_STRIDE          = 'hB;
  localparam int PC_CT_BYTES [ETH_PC] = '{'h2000, 'h2020};

  localparam int PC_NB_WORDS [ETH_PC] = compute_nb_words(PC_CT_BYTES);
  localparam int PC_NB_BURST [ETH_PC] = compute_nb_bursts(PC_NB_WORDS, MAX_BURST_SIZE);
  localparam int PC_REMAINS  [ETH_PC] = compute_remaining_words(PC_NB_WORDS, MAX_BURST_SIZE);
  localparam int PC_NB_TRANS [ETH_PC] = compute_nb_transactions(PC_REMAINS,PC_NB_BURST);

  localparam int TOTAL_NB_PACKETS = $ceil(CT_NB_COEF / NB_WORDS_PAYLOAD) + 1;
// ============================================================================================== --
// clock, reset
// ============================================================================================== --
  bit clk_control;
  bit clk_mrmac;

  initial begin
    clk_control = 1'b0;
    clk_mrmac = 1'b0;
  end

  always begin
    #CLK_HALF_PERIOD_A clk_control = ~clk_control;
  end
  always begin
    #CLK_HALF_PERIOD_B clk_mrmac = ~clk_mrmac;
  end

  bit a_rst_n; // asynchronous reset
  bit s_rstn_control; // synchronous reset
  bit s_rstn_mrmac; // synchronous reset

  initial begin
    a_rst_n = 1'b0;                  // active reset
    #ARST_ACTIVATION a_rst_n = 1'b1; // disable reset
  end

  always_ff @(posedge clk_control) begin
    s_rstn_control <= a_rst_n;
  end
  always_ff @(posedge clk_mrmac) begin
    s_rstn_mrmac <= a_rst_n;
  end

// ============================================================================================== --
// End of test
// ============================================================================================== --
  bit end_of_test;

  initial begin
    wait (end_of_test);
    @(posedge clk_control) $display("%t > SUCCEED !", $time);
    $finish;
  end

// ============================================================================================== --
// Error
// ============================================================================================== --
  bit error;
  bit error_tb_notify;
  bit error_register_read;
  bit error_notify_rx;
  bit error_rr_payload;
  bit error_write_mismatch;

  assign error = error_tb_notify | error_register_read | error_notify_rx | error_rr_payload | error_write_mismatch;

  always_ff @(posedge clk_control)
    if (error) begin
      $display("%t > FAILURE !", $time);
      $finish;
    end

// ============================================================================================== --
// input / output signals
// ============================================================================================== --
  logic [AXIL_ADD_W-1:0]      s_axil_dma_awaddr;
  logic                       s_axil_dma_awvalid;
  logic                       s_axil_dma_awready;
  logic [AXIL_DATA_W-1:0]     s_axil_dma_wdata;
  logic [AXIL_DATA_BYTES-1:0] s_axil_dma_wstrb; /* UNUSED */
  logic                       s_axil_dma_wvalid;
  logic                       s_axil_dma_wready;
  logic [1:0]                 s_axil_dma_bresp;
  logic                       s_axil_dma_bvalid;
  logic                       s_axil_dma_bready;
  logic [AXIL_ADD_W-1:0]      s_axil_dma_araddr;
  logic                       s_axil_dma_arvalid;
  logic                       s_axil_dma_arready;
  logic [AXIL_DATA_W-1:0]     s_axil_dma_rdata;
  logic [1:0]                 s_axil_dma_rresp;
  logic                       s_axil_dma_rvalid;
  logic                       s_axil_dma_rready;

  // HPUs
  logic [HPU_ID_W-1:0] hpu_a_id;
  logic [HPU_ID_W-1:0] hpu_b_id;

  logic [NB_HPU-1:0][MAC_ADDR_W-1:0] mac_addr_l;
  logic [MAC_ADDR_W-1:0] hpu_a_mac_addr;
  logic [MAC_ADDR_W-1:0] hpu_b_mac_addr;

  // QSFP system interface ----------------------------------------------------
  // == TX
  logic [QSFP_LANE_NB-1:0][MRMAC_AXIS_W-1:0 ] qsfp_tx_tdata;
  logic [QSFP_LANE_NB-1:0][MRMAC_TKEEP_W-1:0] qsfp_tx_tkeep_user;
  logic [QSFP_LANE_NB-1:0]                    qsfp_tx_tlast;
  logic [QSFP_LANE_NB-1:0]                    qsfp_tx_tvalid;
  logic [QSFP_LANE_NB-1:0]                    sim_qsfp_tx_tready;
  // == RX
  logic [QSFP_LANE_NB-1:0][MRMAC_AXIS_W-1:0 ] qsfp_rx_tdata;
  logic [QSFP_LANE_NB-1:0][MRMAC_TKEEP_W-1:0] qsfp_rx_tkeep_user;
  logic [QSFP_LANE_NB-1:0]                    qsfp_rx_tlast;
  logic [QSFP_LANE_NB-1:0]                    qsfp_rx_tvalid;

  // for this test, always ready
  assign sim_qsfp_tx_tready = 4'b1111;

  // AXI4 to HBM: HPUA ----------------------------------------------------------------------------
  // Read channel
  logic [ETH_PC-1:0][   AXI4_ID_W-1:0]    axi4_arid;
  logic [ETH_PC-1:0][  AXI4_ADD_W-1:0]    axi4_araddr;
  logic [ETH_PC-1:0][  AXI4_LEN_W-1:0]    axi4_arlen;
  logic [ETH_PC-1:0][ AXI4_SIZE_W-1:0]    axi4_arsize;
  logic [ETH_PC-1:0][AXI4_BURST_W-1:0]    axi4_arburst;
  logic [ETH_PC-1:0]                      axi4_arvalid;
  logic [ETH_PC-1:0]                      axi4_arready;
  logic [ETH_PC-1:0][  AXI4_ID_W-1:0]     axi4_rid;
  logic [ETH_PC-1:0][AXI4_DATA_W-1:0]     axi4_rdata;
  logic [ETH_PC-1:0][AXI4_RESP_W-1:0]     axi4_rresp;
  logic [ETH_PC-1:0]                      axi4_rlast;
  logic [ETH_PC-1:0]                      axi4_rvalid;
  logic [ETH_PC-1:0]                      axi4_rready;
  // Write channel
  logic [ETH_PC-1:0][   AXI4_ID_W-1:0]    axi4_awid;
  logic [ETH_PC-1:0][  AXI4_ADD_W-1:0]    axi4_awaddr;
  logic [ETH_PC-1:0][  AXI4_LEN_W-1:0]    axi4_awlen;
  logic [ETH_PC-1:0][ AXI4_SIZE_W-1:0]    axi4_awsize;
  logic [ETH_PC-1:0][AXI4_BURST_W-1:0]    axi4_awburst;
  logic [ETH_PC-1:0]                      axi4_awvalid;
  logic [ETH_PC-1:0]                      axi4_awready;
  logic [ETH_PC-1:0][AXI4_DATA_W-1:0]     axi4_wdata;
  logic [ETH_PC-1:0][AXI4_STRB_W-1:0]     axi4_wstrb;
  logic [ETH_PC-1:0]                      axi4_wlast;
  logic [ETH_PC-1:0]                      axi4_wvalid;
  logic [ETH_PC-1:0]                      axi4_wready;
  logic [ETH_PC-1:0][  AXI4_ID_W-1:0]     axi4_bid;
  logic [ETH_PC-1:0][AXI4_RESP_W-1:0]     axi4_bresp;
  logic [ETH_PC-1:0]                      axi4_bvalid;
  logic [ETH_PC-1:0]                      axi4_bready;
  // cnx to memory models -------------------------------------------------------------------------
  logic [ETH_PC-1:0][AXI4_ID_W-1:0]       axi4_ct_awid;
  logic [ETH_PC-1:0][AXI4_ADD_W-1:0]      axi4_ct_awaddr;
  logic [ETH_PC-1:0][7:0]                 axi4_ct_awlen;
  logic [ETH_PC-1:0][2:0]                 axi4_ct_awsize;
  logic [ETH_PC-1:0][1:0]                 axi4_ct_awburst;
  logic [ETH_PC-1:0]                      axi4_ct_awvalid;
  logic [ETH_PC-1:0]                      axi4_ct_awready;
  logic [ETH_PC-1:0][AXI4_DATA_W-1:0]     axi4_ct_wdata;
  logic [ETH_PC-1:0][(AXI4_DATA_W/8)-1:0] axi4_ct_wstrb;
  logic [ETH_PC-1:0]                      axi4_ct_wlast;
  logic [ETH_PC-1:0]                      axi4_ct_wvalid;
  logic [ETH_PC-1:0]                      axi4_ct_wready;
  logic [ETH_PC-1:0][AXI4_ID_W-1:0]       axi4_ct_bid;
  logic [ETH_PC-1:0][1:0]                 axi4_ct_bresp;
  logic [ETH_PC-1:0]                      axi4_ct_bvalid;
  logic [ETH_PC-1:0]                      axi4_ct_bready;

  logic [ETH_PC-1:0][AXI4_ID_W-1:0]       axi4_ct_arid;
  logic [ETH_PC-1:0][AXI4_ADD_W-1:0]      axi4_ct_araddr;
  logic [ETH_PC-1:0][7:0]                 axi4_ct_arlen;
  logic [ETH_PC-1:0][2:0]                 axi4_ct_arsize;
  logic [ETH_PC-1:0][1:0]                 axi4_ct_arburst;
  logic [ETH_PC-1:0]                      axi4_ct_arvalid;
  logic [ETH_PC-1:0]                      axi4_ct_arready;
  logic [ETH_PC-1:0][AXI4_ID_W-1:0]       axi4_ct_rid;
  logic [ETH_PC-1:0][AXI4_DATA_W-1:0]     axi4_ct_rdata;
  logic [ETH_PC-1:0][1:0]                 axi4_ct_rresp;
  logic [ETH_PC-1:0]                      axi4_ct_rlast;
  logic [ETH_PC-1:0]                      axi4_ct_rvalid;
  logic [ETH_PC-1:0]                      axi4_ct_rready;

  // ============================================================================================== --
  // Design under test instance
  // ============================================================================================== --
  // gt configuration signals
  logic [7:0]              gt_line_rate;
  logic [2:0]              gt_loopback;
  logic [QSFP_LANE_NB-1:0] gt_reset_rx_datapath;
  logic [QSFP_LANE_NB-1:0] gt_reset_tx_datapath;
  logic [QSFP_LANE_NB-1:0] gt_reset_all;
  logic [QSFP_LANE_NB-1:0] gt_rx_reset_done;
  logic [QSFP_LANE_NB-1:0] gt_tx_reset_done;

  // [section] lane parameter -------------------------------------------------
  logic [REG_DATA_W-1:0] line_parameter;
  logic        debug_flag;
  logic [2:0]  line_loopback;
  logic [7:0]  line_rate;
  logic [1:0]  lane;

  assign line_parameter[1:0]   = lane;
  assign line_parameter[4:2]   = line_loopback;
  assign line_parameter[12:5]  = line_rate;
  assign line_parameter[27:13] = 'h0;
  assign line_parameter[31]    = debug_flag;

  // [section] lane debug -----------------------------------------------------
  logic [REG_DATA_W-1:0] line_debug;
  logic        reset_registers;
  logic        tx_loop;
  logic        rx_to_tx;

  assign line_debug[28:0] = 'h0;
  assign line_debug[29]   = rx_to_tx;
  assign line_debug[30]   = tx_loop;
  assign line_debug[31]   = reset_registers;

  // [section] reset ----------------------------------------------------------
  logic [  REG_DATA_W-1:0] reset_parameter;
  logic [QSFP_LANE_NB-1:0] rst_rx_datapath;
  logic [QSFP_LANE_NB-1:0] rst_tx_datapath;
  logic [QSFP_LANE_NB-1:0] rst_all;

  assign reset_parameter = {20'h0, rst_rx_datapath, rst_tx_datapath, rst_all};

  // monitoring of reset done
  logic [REG_DATA_W-1:00] reset_monitor;

  // HPU ------------------------------------------------------------------------------------------
  logic [QSFP_LANE_NB-1:0][MRMAC_AXIS_W-1:0 ] qsfp_rx_tdata_delayed;
  logic [QSFP_LANE_NB-1:0][MRMAC_TKEEP_W-1:0] qsfp_rx_tkeep_user_delayed;
  logic [QSFP_LANE_NB-1:0]                    qsfp_rx_tlast_delayed;
  logic [QSFP_LANE_NB-1:0]                    qsfp_rx_tvalid_delayed;

  multi_hpu_dma #(
    .FIFO_DEPTH(FIFO_DEPTH)
  ) hpu_a (
    .clk_eth_cfg            (clk_control    ),
    .resetn_eth_cfg         (s_rstn_control ),

    .clk_eth_mrmac          (clk_mrmac    ),
    .resetn_eth_mrmac       (s_rstn_mrmac ),

    .s_axil_dma_awaddr      (s_axil_dma_awaddr ),
    .s_axil_dma_awvalid     (s_axil_dma_awvalid),
    .s_axil_dma_awready     (s_axil_dma_awready),
    .s_axil_dma_wdata       (s_axil_dma_wdata  ),
    .s_axil_dma_wstrb       (s_axil_dma_wstrb  ),
    .s_axil_dma_wvalid      (s_axil_dma_wvalid ),
    .s_axil_dma_wready      (s_axil_dma_wready ),
    .s_axil_dma_bresp       (s_axil_dma_bresp  ),
    .s_axil_dma_bvalid      (s_axil_dma_bvalid ),
    .s_axil_dma_bready      (s_axil_dma_bready ),
    .s_axil_dma_araddr      (s_axil_dma_araddr ),
    .s_axil_dma_arvalid     (s_axil_dma_arvalid),
    .s_axil_dma_arready     (s_axil_dma_arready),
    .s_axil_dma_rdata       (s_axil_dma_rdata  ),
    .s_axil_dma_rresp       (s_axil_dma_rresp  ),
    .s_axil_dma_rvalid      (s_axil_dma_rvalid ),
    .s_axil_dma_rready      (s_axil_dma_rready ),

    .m_axi4_eth_hbm_arid    (axi4_ct_arid         ),
    .m_axi4_eth_hbm_araddr  (axi4_ct_araddr       ),
    .m_axi4_eth_hbm_arlen   (axi4_ct_arlen        ),
    .m_axi4_eth_hbm_arsize  (axi4_ct_arsize       ),
    .m_axi4_eth_hbm_arburst (axi4_ct_arburst      ),
    .m_axi4_eth_hbm_arvalid (axi4_ct_arvalid      ),
    .m_axi4_eth_hbm_arready (axi4_ct_arready      ),
    .m_axi4_eth_hbm_rid     (axi4_ct_rid          ),
    .m_axi4_eth_hbm_rdata   (axi4_ct_rdata        ),
    .m_axi4_eth_hbm_rresp   (axi4_ct_rresp        ),
    .m_axi4_eth_hbm_rlast   (axi4_ct_rlast        ),
    .m_axi4_eth_hbm_rvalid  (axi4_ct_rvalid       ),
    .m_axi4_eth_hbm_rready  (axi4_ct_rready       ),
    .m_axi4_eth_hbm_awid    (axi4_ct_awid         ),
    .m_axi4_eth_hbm_awaddr  (axi4_ct_awaddr       ),
    .m_axi4_eth_hbm_awlen   (axi4_ct_awlen        ),
    .m_axi4_eth_hbm_awsize  (axi4_ct_awsize       ),
    .m_axi4_eth_hbm_awburst (axi4_ct_awburst      ),
    .m_axi4_eth_hbm_awvalid (axi4_ct_awvalid      ),
    .m_axi4_eth_hbm_awready (axi4_ct_awready      ),
    .m_axi4_eth_hbm_wdata   (axi4_ct_wdata        ),
    .m_axi4_eth_hbm_wstrb   (axi4_ct_wstrb        ),
    .m_axi4_eth_hbm_wlast   (axi4_ct_wlast        ),
    .m_axi4_eth_hbm_wvalid  (axi4_ct_wvalid       ),
    .m_axi4_eth_hbm_wready  (axi4_ct_wready       ),
    .m_axi4_eth_hbm_bid     (axi4_ct_bid          ),
    .m_axi4_eth_hbm_bresp   (axi4_ct_bresp        ),
    .m_axi4_eth_hbm_bvalid  (axi4_ct_bvalid       ),
    .m_axi4_eth_hbm_bready  (axi4_ct_bready       ),

    .qsfp_tx_tdata          (qsfp_tx_tdata           ),
    .qsfp_tx_tkeep_user     (qsfp_tx_tkeep_user      ),
    .qsfp_tx_tlast          (qsfp_tx_tlast           ),
    .qsfp_tx_tvalid         (qsfp_tx_tvalid          ),
    .qsfp_tx_tready         (sim_qsfp_tx_tready      ),

    .qsfp_rx_tdata          (byte_swap(qsfp_rx_tdata_delayed)),
    .qsfp_rx_tkeep_user     (qsfp_rx_tkeep_user_delayed      ),
    .qsfp_rx_tlast          (qsfp_rx_tlast_delayed           ),
    .qsfp_rx_tvalid         (qsfp_rx_tvalid_delayed          ),

    .gt_line_rate           (gt_line_rate            ),
    .gt_loopback            (gt_loopback            ),
    .gt_reset_rx_datapath   (gt_reset_rx_datapath    ),
    .gt_reset_tx_datapath   (gt_reset_tx_datapath    ),
    .gt_reset_all           (gt_reset_all            ),
    .gt_rx_reset_done       (gt_rx_reset_done        ),
    .gt_tx_reset_done       (gt_tx_reset_done        )
);

  always @(*) begin
    qsfp_rx_tdata_delayed      <= #100ns qsfp_rx_tdata;
    qsfp_rx_tkeep_user_delayed <= #100ns qsfp_rx_tkeep_user;
    qsfp_rx_tlast_delayed      <= #100ns qsfp_rx_tlast;
    qsfp_rx_tvalid_delayed     <= #100ns qsfp_rx_tvalid;
  end

  // Decoder --------------------------------------------------------------------------------------
  command_t rx_header;
  logic rx_header_vld;
  logic rx_header_rdy;

  // this is supposed to be HPU_B decoder
  mhdma_decoder mhdma_decoder (
    .clk_mrmac                   (clk_mrmac),
    .resetn_mrmac                (s_rstn_mrmac),

    .notify_ack_received         (/* unused */),
    .notify_request_received     (/* unused */),
    .read_request_received       (/* unused */),
    .ciphertext_emission_received(/* unused */),

    .current_hpu_mac             (hpu_b_mac_addr),

    .decoded_command             (rx_header),
    .decoded_command_vld         (rx_header_vld),
    .decoded_command_rdy         (rx_header_rdy),

    .rx_tdata_out                (/*   unused          */),
    .rx_tvalid_out               (/*   unused          */),

    // stats are completely ignored here

    // only one lane is used in this tb
    .qsfp_rx_tdata               (qsfp_tx_tdata[lane]),
    .qsfp_rx_tkeep_user          (qsfp_tx_tkeep_user[lane]),
    .qsfp_rx_tlast               (qsfp_tx_tlast[lane]),
    .qsfp_rx_tvalid              (qsfp_tx_tvalid[lane])
  );

  assign rx_header_rdy = ($urandom() % 100 < 50);
// ============================================================================================== --
// Scenario
// ============================================================================================== --
  // AXI4-LITE drivers ----------------------------------------------------------------------------
  maxil_if #(
  .AXIL_DATA_W(AXIL_DATA_W),
  .AXIL_ADD_W  (AXIL_ADD_W)
  ) maxil_drv_if ( .clk(clk_control), .rst_n(s_rstn_control));

  // Connect interface on testbench signals
  assign s_axil_dma_awaddr  = maxil_drv_if.awaddr;
  assign s_axil_dma_awvalid = maxil_drv_if.awvalid;
  assign s_axil_dma_wdata   = maxil_drv_if.wdata;
  assign s_axil_dma_wstrb   = maxil_drv_if.wstrb;
  assign s_axil_dma_wvalid  = maxil_drv_if.wvalid;
  assign s_axil_dma_bready  = maxil_drv_if.bready;
  assign s_axil_dma_araddr  = maxil_drv_if.araddr;
  assign s_axil_dma_arvalid = maxil_drv_if.arvalid;
  assign s_axil_dma_rready  = maxil_drv_if.rready;

  assign maxil_drv_if.awready = s_axil_dma_awready;
  assign maxil_drv_if.wready  = s_axil_dma_wready;
  assign maxil_drv_if.bresp   = s_axil_dma_bresp;
  assign maxil_drv_if.bvalid  = s_axil_dma_bvalid;
  assign maxil_drv_if.arready = s_axil_dma_arready;
  assign maxil_drv_if.rdata   = s_axil_dma_rdata;
  assign maxil_drv_if.rresp   = s_axil_dma_rresp;
  assign maxil_drv_if.rvalid  = s_axil_dma_rvalid;

  generate
      for (genvar gen_pc=0; gen_pc<ETH_PC; gen_pc=gen_pc+1) begin : gen_mem_pc
        axi4_mem #(
          .DATA_WIDTH      (AXI4_DATA_W                     ),
          .ADDR_WIDTH      (MEM_SIM_SIZE                    ), //64?!
          .ID_WIDTH        (AXI4_ID_W                       ),
          .WR_CMD_BUF_DEPTH(MEM_WR_CMD_BUF_DEPTH            ),
          .RD_CMD_BUF_DEPTH(MEM_RD_CMD_BUF_DEPTH            ),
          .WR_DATA_LATENCY (MEM_WR_DATA_LATENCY+ gen_pc * 50),
          .RD_DATA_LATENCY (MEM_RD_DATA_LATENCY             ),
          .USE_WR_RANDOM   (MEM_USE_WR_RANDOM               ),
          .USE_RD_RANDOM   (MEM_USE_RD_RANDOM               )
        ) axi4_mem_ct (
          .clk           (clk_mrmac                         ),
          .rst           (~s_rstn_mrmac                     ),
          .s_axi4_awid   (axi4_ct_awid[gen_pc]     ),
          .s_axi4_awaddr (axi4_ct_awaddr[gen_pc]   ),
          .s_axi4_awlen  (axi4_ct_awlen[gen_pc]    ),
          .s_axi4_awsize (axi4_ct_awsize[gen_pc]   ),
          .s_axi4_awburst(axi4_ct_awburst[gen_pc]  ),
          .s_axi4_awlock ('0), // disable
          .s_axi4_awcache('0), // disable
          .s_axi4_awprot ('0), // disable
          .s_axi4_awvalid(axi4_ct_awvalid[gen_pc]  ),
          .s_axi4_awready(axi4_ct_awready[gen_pc]  ),
          .s_axi4_wdata  (axi4_ct_wdata[gen_pc]    ),
          .s_axi4_wstrb  (axi4_ct_wstrb[gen_pc]    ),
          .s_axi4_wlast  (axi4_ct_wlast[gen_pc]    ),
          .s_axi4_wvalid (axi4_ct_wvalid[gen_pc]   ),
          .s_axi4_wready (axi4_ct_wready[gen_pc]   ),
          .s_axi4_bid    (axi4_ct_bid[gen_pc]      ),
          .s_axi4_bresp  (axi4_ct_bresp[gen_pc]    ),
          .s_axi4_bvalid (axi4_ct_bvalid[gen_pc]   ),
          .s_axi4_bready (axi4_ct_bready[gen_pc]   ),
          .s_axi4_arid   (axi4_ct_arid[gen_pc]     ),
          .s_axi4_araddr (axi4_ct_araddr[gen_pc]   ),
          .s_axi4_arlen  (axi4_ct_arlen[gen_pc]    ),
          .s_axi4_arsize (axi4_ct_arsize[gen_pc]   ),
          .s_axi4_arburst(axi4_ct_arburst[gen_pc]  ),
          .s_axi4_arlock ('0), // disable
          .s_axi4_arcache('0), // disable
          .s_axi4_arprot ('0), // disable
          .s_axi4_arvalid(axi4_ct_arvalid[gen_pc]  ),
          .s_axi4_arready(axi4_ct_arready[gen_pc]  ),
          .s_axi4_rid    (axi4_ct_rid[gen_pc]      ),
          .s_axi4_rdata  (axi4_ct_rdata[gen_pc]    ),
          .s_axi4_rresp  (axi4_ct_rresp[gen_pc]    ),
          .s_axi4_rlast  (axi4_ct_rlast[gen_pc]    ),
          .s_axi4_rvalid (axi4_ct_rvalid[gen_pc]   ),
          .s_axi4_rready (axi4_ct_rready[gen_pc]   )
        );
      end
  endgenerate

  int random_iter;
  // Signals --------------------------------------------------------------------------------------
  logic [REG_DATA_W-1:0] read_data;
  // must not bee too short, not too long
  logic [REG_DATA_W-1:0] timeout_size;


  // IOP related signals
  logic [  IOP_ID_W-1:0] iop_id;
  logic [SRC_ADDR_W-1:0] iop_src_addr;
  logic [DST_ADDR_W-1:0] iop_dst_addr;

  // for checking
  logic [REG_DATA_W-1:0] notify_payload;

  // Fixed for now, might evolve later
  logic [SIZE_B_W-1:0] req_size_b;
  assign req_size_b = 'h4000;

  logic [REG_DATA_W-1:0] regf_start_addr_ofs;

  logic [REG_DATA_W-1:0] stat_notify;
  logic [REG_DATA_W-1:0] stat_notify_ack;
  logic [REG_DATA_W-1:0] stat_notify_retry;
  logic [REG_DATA_W-1:0] stat_notify_timeout;
  logic [REG_DATA_W-1:0] stat_t_notify_to_ack;
  logic [REG_DATA_W-1:0] stat_t_rr_to_ce_received;
  logic [REG_DATA_W-1:0] stat_t_ce_first_to_last_pkt;

  // scenario -------------------------------------------------------------------------------------
  initial begin
    maxil_drv_if.init();

    reset_registers = 'h0;
    tx_loop         = 'h0;
    rx_to_tx        = 'h0;
    regf_start_addr_ofs = 'h0;
    repeat(20) @(posedge clk_control);

    $display("\n\n"); // sperating from xpm fifo information

    // Initialization =============================================================================
    $display("A - Initial register check and definition");
    init_registers();

    // Defining MAC addresses for both instances of HPU -------------------------------------------
    hpu_a_id     = 6;
    hpu_b_id     = 3;

    write_mac_addresses();

    hpu_a_mac_addr = mac_addr_l[hpu_a_id];
    hpu_b_mac_addr = mac_addr_l[hpu_b_id];

    // Loss of an ack =============================================================================
    // HPU_A sends a Notify request and receives
    // - (a) a correct ack
    // - (b) nothing
    // - (c) an incorrect ack (wrong mac addr)
    // - (d) no ack and a new request is pending
    $display("Loss of acknowledge ==============================================================");
    $display("A - default behavior: a correct ack is received"); // -------------------------------
    iop_id       = $urandom();
    iop_src_addr = $urandom_range(0, 1<<SRC_ADDR_W);

    notify_request(hpu_a_id, hpu_b_id, iop_id, iop_src_addr);
    notify_ack(hpu_a_id, hpu_a_mac_addr, hpu_b_id, hpu_b_mac_addr);

    wait(hpu_a.mhdma_bridge.mhdma_formatter.tx_state == 3'b001);
    $display("%t > [INFO]: formatter FSM has gotten back to IDLE", $time);

    $display("B - no ack is sent to hpu_a: timeout must be hit and request resent"); // -----------
    iop_id       = $urandom();
    iop_src_addr = $urandom_range(0, 1<<SRC_ADDR_W);
    notify_request(hpu_a_id, hpu_b_id, iop_id, iop_src_addr);

    repeat(2*TIMEOUT_DUR_NOTIFY[15:0]) @(posedge clk_mrmac);

    notify_ack(hpu_a_id, hpu_a_mac_addr, hpu_b_id, hpu_b_mac_addr);

    wait(hpu_a.mhdma_bridge.mhdma_formatter.tx_state == 3'b001);
    $display("%t > [INFO]: formatter FSM has gotten back to IDLE", $time);

    $display("C - an incorrect ack is sent to hpu"); // -------------------------------------------
    iop_id       = $urandom();
    iop_src_addr = $urandom_range(0, 1<<SRC_ADDR_W);

    notify_request(hpu_a_id, hpu_b_id, iop_id, iop_src_addr);
    notify_ack(hpu_a_id, hpu_b_mac_addr, hpu_b_id, hpu_b_mac_addr);

    repeat(20) @(posedge clk_mrmac);

    if (hpu_a.mhdma_bridge.mhdma_master.ntx_state == 2'b10) begin
      $display("%t > [INFO]: When sending incorrect ack, state is still waiting", $time);
    end else begin
      $display("%t > [ERROR]: When sending incorrect ack state is not waiting", $time);
      error_notify_rx = 1'b1;
    end

    notify_ack(hpu_a_id, hpu_a_mac_addr, hpu_b_id, hpu_b_mac_addr);

    wait(hpu_a.mhdma_bridge.mhdma_formatter.tx_state == 3'b001);
    $display("%t > [INFO]: formatter FSM has gotten back to IDLE", $time);

    maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_NOTIFY_OFS, read_data);
    $display("[INFO] MHDMA_REQUEST_STAT_NOTIFY_OFS                 : %0x ", read_data);
    maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_NOTIFY_ACK_OFS, read_data);
    $display("[INFO] MHDMA_REQUEST_STAT_NOTIFY_ACK_OFS             : %0x ", read_data);
    maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_NOTIFY_TIMEOUT_OFS, read_data);
    $display("[INFO] MHDMA_REQUEST_STAT_NOTIFY_TIMEOUT_OFS         : %0x ", read_data);
    maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_NOTIFY_TIMEOUT_RETRY_OFS, read_data);
    $display("[INFO] MHDMA_REQUEST_STAT_NOTIFY_TIMEOUT_RETRY_OFS   : %0x ", read_data);

    $display("[INFO] re-read after reset --------------------------------------------");
    maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_NOTIFY_OFS, read_data);
    $display("[INFO] MHDMA_REQUEST_STAT_NOTIFY_OFS                 : %0x ", read_data);
    maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_NOTIFY_ACK_OFS, read_data);
    $display("[INFO] MHDMA_REQUEST_STAT_NOTIFY_ACK_OFS             : %0x ", read_data);
    maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_NOTIFY_TIMEOUT_OFS, read_data);
    $display("[INFO] MHDMA_REQUEST_STAT_NOTIFY_TIMEOUT_OFS         : %0x ", read_data);
    maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_NOTIFY_TIMEOUT_RETRY_OFS, read_data);
    $display("[INFO] MHDMA_REQUEST_STAT_NOTIFY_TIMEOUT_RETRY_OFS   : %0x ", read_data);

    $display("D - no ack for a time and a new notify pending"); // --------------------------------
    // timeout is not what we want to test here : we 10x it
    maxil_drv_if.write_trans(MHDMA_SYSTEM_TIMEOUT_NOTIFY_OFS, 10*TIMEOUT_DUR_NOTIFY);
    iop_id       = 678;
    iop_src_addr = 99;
    notify_request(hpu_a_id, hpu_b_id, iop_id, iop_src_addr);

    iop_id       = 777;
    iop_src_addr = 98;
    notify_request(hpu_a_id, hpu_b_id, iop_id, iop_src_addr);

    notify_ack(hpu_a_id, hpu_a_mac_addr, hpu_b_id, hpu_b_mac_addr);

    notify_ack(hpu_a_id, hpu_a_mac_addr, hpu_b_id, hpu_b_mac_addr);

    wait(hpu_a.mhdma_bridge.mhdma_master.ntx_state == 3'b001);

    // Ciphertext emission error ==================================================================
    // HPU_A sends a read request and receives
    // - (e) a correct ciphertext
    // - (f) nothing
    // - (g) an incorrect ce (wrong seq_num)
    iop_id       = $urandom();
    iop_src_addr = $urandom_range(0, 1<<SRC_ADDR_W);

    $display("E - Read request is emitted by HPU_A and correctly answered"); // -------------------
    read_request(hpu_b_id, iop_id, iop_src_addr, iop_dst_addr);

    emulate_ciphertext_emission(hpu_a_id, hpu_a_mac_addr, hpu_b_id, hpu_b_mac_addr, 0);

    wait(hpu_a.mhdma_bridge.mhdma_formatter.tx_state == 3'b001);
    $display("%t > [INFO-E]: formatter FSM has gotten back to IDLE", $time);

    $display("F - Read request is emitted by HPU_A and not answered for twice timeout amount"); // -
    read_request(hpu_b_id, iop_id, iop_src_addr, iop_dst_addr);

    repeat(2*TIMEOUT_DUR_READ_REQ[31:16]) @(posedge clk_mrmac);

    emulate_ciphertext_emission(hpu_a_id, hpu_a_mac_addr, hpu_b_id, hpu_b_mac_addr, 0);

    wait(hpu_a.mhdma_bridge.mhdma_formatter.tx_state == 3'b001);
    $display("%t > [INFO-F]: formatter FSM has gotten back to IDLE", $time);

    // TODO: missing wrong seq_num

    $display("\n ----------------- HPU_A -------------------------------------");
    maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_NOTIFY_OFS, stat_notify);
    maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_NOTIFY_ACK_OFS, stat_notify_ack);
    maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_NOTIFY_TIMEOUT_RETRY_OFS, stat_notify_retry);
    maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_NOTIFY_TIMEOUT_OFS, stat_notify_timeout);
    maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_T_NOTIFY_TO_ACK_OFS, stat_t_notify_to_ack);
    maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_T_RR_TO_CE_RECEIVED_OFS, stat_t_rr_to_ce_received);
    maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_T_CE_FIRST_TO_LAST_PKT_OFS, stat_t_ce_first_to_last_pkt);
    $display(" stat_notify                 : %0d", stat_notify);
    $display(" stat_notify_ack             : %0d", stat_notify_ack);
    $display(" stat_notify_retry           : %0d", stat_notify_retry);
    $display(" stat_notify_timeout         : %0d", stat_notify_timeout);
    $display(" stat_t_notify_to_ack        : %0d", stat_t_notify_to_ack);
    $display(" stat_t_rr_to_ce_received    : %0d", stat_t_rr_to_ce_received);
    $display(" stat_t_ce_first_to_last_pkt : %0d", stat_t_ce_first_to_last_pkt);
    $display(" ------------------------------------------------------------- \n");

    $display("%t > INFO: End simulation",$time);
    repeat(20) @(posedge clk_control);
    end_of_test = 1'b1;
  end

// ============================================================================================== --
// Initialize memory
// ============================================================================================== --
  logic [59:0] val_id = 0;

  initial begin
    for (int gen_pc = 0; gen_pc < ETH_PC; ++gen_pc) begin
      for (int k = 0; k < 2**MEM_SIM_SIZE; ++k) begin
        automatic logic [255:0] value = '0;
        for (int j = 0; j < 4; ++j) begin
          logic [63:0] w;
          w[63:62] = 0;
          w[61:60] = 0;//gen_pc;
          w[59:46] = 'h0;
          w[47:40] = 0;//k;
          w[39:32] = 'h0;
          w[31:0] = val_id;
          value |= (w << (j*64));
          val_id++;
        end

        gen_mem_pc[0].axi4_mem_ct.axi4_ram_ct_wr.mem[k] = value;
        gen_mem_pc[1].axi4_mem_ct.axi4_ram_ct_wr.mem[k] = value;
      end
    end
    for (int gen_pc = 0; gen_pc < ETH_PC; ++gen_pc) begin
      for (int k = 0; k < 2**MEM_SIM_SIZE; ++k) begin
        gen_mem_pc[0].axi4_mem_ct.axi4_ram_ct_wr.mem[k] = 'h0;
        gen_mem_pc[1].axi4_mem_ct.axi4_ram_ct_wr.mem[k] = 'h0;
    end
    end
  end

// ============================================================================================== --
// Tasks
// ============================================================================================== --
  logic [REG_DATA_W-1:00] rdata;

  task automatic init_registers;
    begin
      // Reading system REGISTERS -----------------------------------------------------------------
      maxil_drv_if.read_trans(MHDMA_SYSTEM_LANE_OFS, rdata);
      assert (rdata == 'h0) else begin
        $display("%t > ERROR:register MHDMA_SYSTEM_LANE_OFS not correctly read %h",$time, rdata);
        error_register_read = 1'b1;
      end

      qsfp_rx_tdata = 'h0;
      qsfp_rx_tkeep_user = 'h0;
      qsfp_rx_tlast = 'h0;
      qsfp_rx_tvalid = 'h0;

      // Setting timeout size ---------------------------------------------------------------------
      maxil_drv_if.write_trans(MHDMA_SYSTEM_TIMEOUT_NOTIFY_OFS, TIMEOUT_DUR_NOTIFY);
      maxil_drv_if.write_trans(MHDMA_SYSTEM_TIMEOUT_READ_REQ_OFS, TIMEOUT_DUR_READ_REQ);

      // Setting up credible values -------------------------------------------------------------
      // no loopback, no reset, not in debug lane0 selected
      line_rate     = 8'h0;
      line_loopback = 3'b000;
      lane   = 2'b00;
      debug_flag    = 1'b0;
      rst_rx_datapath = 4'b0000;
      rst_tx_datapath = 4'b0000;
      rst_all         = 4'b0000;
      maxil_drv_if.write_trans(MHDMA_SYSTEM_LANE_OFS, line_parameter);
      @(posedge clk_control);
      $display("%t > INFO: Configuration successful\n",$time);
    end
  endtask

  /* Performs writes to according registers to define all possible MAC addresses
   *  - HPU-A and HPU-B are random and different at each runs
   *  - We have at most 8 (NB_HPU) HPUs: we will write them all
   */
  task automatic write_mac_addresses();
    logic [ MAC_ADDR_W-1:0] mac_addr;
    logic [   HPU_ID_W-1:0] hpu_id;
    logic                   hpu_current;
    logic [REG_DATA_W-1:00] register_mac_addr_a;
    begin
      // in this testbench we do not set random hpu ids.

      $display("┌------------------------┐");
      $display("| For this run....       |");
      $display("| ---------------------- |");
      $display("| HPU_A:id=%d            |", hpu_a_id);
      $display("| ---------------------- |");
      for (int i = 0 ; i < NB_HPU ; i++ ) begin
        mac_addr = $urandom();
        mac_addr_l[i] = mac_addr;
        hpu_id = i;

        if(i == hpu_a_id) begin
          register_mac_addr_a = {1'b1, 3'b000, hpu_id, mac_addr};
        end else begin
          register_mac_addr_a = {1'b0, 3'b000, hpu_id, mac_addr};
        end

        $display("| HPU_ID=%0d :: MAC=%6x |", i, mac_addr);
        maxil_drv_if.write_trans(MHDMA_HPU_ID_ZERO_OFS+(4*i), register_mac_addr_a);
      end
      $display("└------------------------┘");
    end
  endtask

  /* Performs a Notify request from an HPU to another
   * - HPU-A and HPU-B can be both side here
   * - if you chose a wrong HPU-id you will get an error
   */
  task automatic notify_request(
    input logic [  HPU_ID_W-1:0] src_node_id,
    input logic [  HPU_ID_W-1:0] dst_node_id,
    input logic [  IOP_ID_W-1:0] iop_id,
    input logic [SRC_ADDR_W-1:0] src_addr
  );
    logic [REG_DATA_W-1:00] read_req_id;
    logic [REG_DATA_W-1:00] read_req_addr;
    begin

      read_req_addr = {16'b0, src_addr};
      read_req_id = {iop_id, REQ_ID_NOTIFY, dst_node_id, req_size_b};

      maxil_drv_if.write_trans(MHDMA_REQUEST_REQ_ADDR_OFS, read_req_addr);
      maxil_drv_if.write_trans(MHDMA_REQUEST_REQ_ID_OFS, read_req_id);
    end
  endtask


  /* Sends a correct Notify ack
  */
  task automatic notify_ack(
    input logic [  HPU_ID_W-1:0] target_node_id,
    input logic [MAC_ADDR_W-1:0] target_mac_addr,
    input logic [  HPU_ID_W-1:0] source_node_id,
    input logic [MAC_ADDR_W-1:0] source_mac_addr
  );
    begin
      wait(rx_header_vld);

      // First clock cycle ----------------------------------------------------
      qsfp_rx_tdata[lane]      = {MAC_OUI, target_mac_addr, MAC_OUI[MAC_OUI_W-1:8]};
      qsfp_rx_tkeep_user[lane] = 'hff;
      qsfp_rx_tlast[lane]      = 1'b0;
      qsfp_rx_tvalid[lane]     = 1'b1;
      @(posedge clk_mrmac);

      // Second clock cycle ----------------------------------------------------
      qsfp_rx_tdata[lane]      = {MAC_OUI[7:0], source_mac_addr, ETH_LEN_MIN, LLC_DSAP, LLC_SSAP};
      qsfp_rx_tkeep_user[lane] = 'hff;
      qsfp_rx_tlast[lane]      = 1'b0;
      qsfp_rx_tvalid[lane]     = 1'b1;
      @(posedge clk_mrmac);

      // Third clock cycle ----------------------------------------------------
      qsfp_rx_tdata[lane]      = {LLC_CTRL, REQ_ID_NOTIFY_ACK, target_node_id, 8'b0, rx_header.src_addr, rx_header.dst_addr, rx_header.iop_id};
      qsfp_rx_tkeep_user[lane] = 'hff;
      qsfp_rx_tlast[lane]      = 1'b0;
      qsfp_rx_tvalid[lane]     = 1'b1;
      @(posedge clk_mrmac);

      // Fourth clock cycle ----------------------------------------------------
      qsfp_rx_tdata[lane]      = {SIZE_B, 24'b0};
      qsfp_rx_tkeep_user[lane] = 'hff;
      qsfp_rx_tlast[lane]      = 1'b0;
      qsfp_rx_tvalid[lane]     = 1'b1;
      @(posedge clk_mrmac);

      // empty - to fill 64bytes ---------------------------------------------
      for (int i = 0; i < 3; i ++) begin
        qsfp_rx_tdata[lane]      = 'h0;
        qsfp_rx_tkeep_user[lane] = 'hff;
        qsfp_rx_tlast[lane]      = 1'b0;
        qsfp_rx_tvalid[lane]     = 1'b1;
      @(posedge clk_mrmac);
      end

      //  Last clock cycle ----------------------------------------------------
      qsfp_rx_tdata[lane]      = 'h0;
      qsfp_rx_tkeep_user[lane] = 'hff;
      qsfp_rx_tlast[lane]      = 1'b1;
      qsfp_rx_tvalid[lane]     = 1'b1;
      @(posedge clk_mrmac);

      qsfp_rx_tdata[lane]      = 'h0;
      qsfp_rx_tkeep_user[lane] = 'h0;
      qsfp_rx_tlast[lane]      = 1'b0;
      qsfp_rx_tvalid[lane]     = 1'b0;
    end
  endtask

  /* Performs a Read request from HPU A to HPU B
    - Since HPU A and HPU B are the same no need to be able to be able to send from both
    - There is two registers to write to send a read request */
  task automatic read_request(
    input logic [  HPU_ID_W-1:0] node_id,
    input logic [  IOP_ID_W-1:0] iop_id,
    input logic [SRC_ADDR_W-1:0] src_addr,
    input logic [DST_ADDR_W-1:0] dest_addr
  );
    logic [REG_DATA_W-1:0] read_req_id;
    logic [REG_DATA_W-1:0] read_req_addr;
    begin
      // see package
      read_req_addr = {dest_addr, src_addr};
      read_req_id = {iop_id, REQ_ID_READ, node_id, req_size_b};

      maxil_drv_if.write_trans(MHDMA_REQUEST_REQ_ADDR_OFS, read_req_addr);
      maxil_drv_if.write_trans(MHDMA_REQUEST_REQ_ID_OFS, read_req_id);
      // there is as well the hbm pc offsets to write from RPU pov but in simulation we let it set to 0
    end
  endtask

  /* Sends a correct ciphertext emission
  */
  task automatic emulate_ciphertext_emission(
    input logic [  HPU_ID_W-1:0] target_node_id,
    input logic [MAC_ADDR_W-1:0] target_mac_addr,
    input logic [  HPU_ID_W-1:0] source_node_id,
    input logic [MAC_ADDR_W-1:0] source_mac_addr,
    input logic                  failure_on_seq_num
  );
    begin
      logic [SEC_NUM_W-1:0] seq_num_id;

      wait(rx_header_vld);

      for (int i = 0; i < TOTAL_NB_PACKETS; i++) begin

        // TODO: failure
        seq_num_id = i;

        // First clock cycle ----------------------------------------------------
        qsfp_rx_tdata[lane]      = {MAC_OUI, target_mac_addr, MAC_OUI[MAC_OUI_W-1:8]};
        qsfp_rx_tkeep_user[lane] = 'hff;
        qsfp_rx_tlast[lane]      = 1'b0;
        qsfp_rx_tvalid[lane]     = 1'b1;
        @(posedge clk_mrmac);

        // Second clock cycle ----------------------------------------------------
        qsfp_rx_tdata[lane]      = {MAC_OUI[7:0], source_mac_addr, ETH_LEN_MIN, LLC_DSAP, LLC_SSAP};
        qsfp_rx_tkeep_user[lane] = 'hff;
        qsfp_rx_tlast[lane]      = 1'b0;
        qsfp_rx_tvalid[lane]     = 1'b1;
        @(posedge clk_mrmac);

        // Third clock cycle ----------------------------------------------------
        qsfp_rx_tdata[lane]      = {LLC_CTRL, REQ_ID_EMISSION, target_node_id, seq_num_id, rx_header.src_addr, rx_header.dst_addr, rx_header.iop_id};
        qsfp_rx_tkeep_user[lane] = 'hff;
        qsfp_rx_tlast[lane]      = 1'b0;
        qsfp_rx_tvalid[lane]     = 1'b1;
        @(posedge clk_mrmac);

        // Fourth clock cycle ----------------------------------------------------
        qsfp_rx_tdata[lane]      = {SIZE_B, 24'b0};
        qsfp_rx_tkeep_user[lane] = 'hff;
        qsfp_rx_tlast[lane]      = 1'b0;
        qsfp_rx_tvalid[lane]     = 1'b1;
        @(posedge clk_mrmac);

        for (int payload_i = 0; payload_i < NB_WORDS_PAYLOAD  -1 ; payload_i++) begin
          qsfp_rx_tdata[lane]      = {i,payload_i};
          qsfp_rx_tkeep_user[lane] = 'hff;
          qsfp_rx_tlast[lane]      = 1'b0;
          qsfp_rx_tvalid[lane]     = 1'b1;
          @(posedge clk_mrmac);
        end

        // last clock cycle ----------------------------------------------------
        qsfp_rx_tdata[lane]      = 55;
        qsfp_rx_tkeep_user[lane] = 'hff;
        qsfp_rx_tlast[lane]      = 1'b1;
        qsfp_rx_tvalid[lane]     = 1'b1;
        @(posedge clk_mrmac);

        // reset
        qsfp_rx_tdata[lane]      = 'h0;
        qsfp_rx_tkeep_user[lane] = 'h0;
        qsfp_rx_tlast[lane]      = 1'b0;
        qsfp_rx_tvalid[lane]     = 1'b0;
        repeat(50) @(posedge clk_mrmac);
      end
    end

  endtask

endmodule
