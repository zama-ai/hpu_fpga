// ================================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ------------------------------------------------------------------------------------------------
// Description  : Testbench for packet loss and retries in multi-HPU DMA.
//
// Scenarios:
//   - Normal notify/ack handshake
//   - Notify retry on missing and incorrect ack
//   - Multiple pending notifies
//   - Read request retry on timeout
//   - Read request receiving wrong and then correct seq num
//
// HPU_A is the DUT, HPU_B is emulated by this testbench.
//
// Beware : as we assume that if an ack is received during a retry, the ack of the retry will be
// the one that resets the notify FSM, with small timeout values we could, in this testbench send
// an ack during a notify retry. This could lead the testbench to fail if wait time are changed.
//
// ================================================================================================

`resetall
`timescale 1ns/10ps
module tb_mhdma_pkt_loss;
  import mhdma_pkg::*;                    // multi-hpu-dma
  import axi_if_shell_axil_pkg::*;        // axi4-lite + REG_DATA_W
  import axi_if_common_param_pkg::*;      // general axi4
  import hpu_regif_core_eth_2in3_pkg::*;  // ethernet regif
  import axi_if_eth_axi_pkg::*;           // AXI ethernet
  import pem_common_param_pkg::*;         // CT_MEM_BYTES, AXI4_WORD_PER_PC*

  `include "tb_mhdma_tasks.sv"

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int CLK_HALF_PERIOD_A = 4;
  localparam int CLK_HALF_PERIOD_B = 1;
  localparam int ARST_ACTIVATION = 17;

  localparam int FIFO_DEPTH = 512;

  localparam int NB_HPU = 8;
  localparam [31:0] TIMEOUT_DUR_NOTIFY = 'd180;
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

  // Use CT_MEM_BYTES from pem_common_param_pkg for address calculation
  localparam int PC_CT_BYTES [ETH_PC] = '{default: CT_MEM_BYTES};

  // PC0 has one extra word (body word), remaining PCs use AXI4_WORD_PER_PC

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
  bit error_ack;
  bit error_retry;
  bit error_tb_notify;
  bit error_register_read;
  bit error_fsm;

  assign error = error_ack | error_retry | error_tb_notify | error_register_read | error_fsm;

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
  logic [NB_HPU-1:0][MAC_ADDR_W-1:0] mac_addr_l;

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
  // gt configuration signals -------------------------------------------------
  logic [7:0]              gt_line_rate;
  logic [2:0]              gt_loopback;
  logic [QSFP_LANE_NB-1:0] gt_reset_rx_datapath;
  logic [QSFP_LANE_NB-1:0] gt_reset_tx_datapath;
  logic [QSFP_LANE_NB-1:0] gt_reset_all;
  logic [QSFP_LANE_NB-1:0] gt_rx_reset_done;
  logic [QSFP_LANE_NB-1:0] gt_tx_reset_done;

  // lane parameters ----------------------------------------------------------
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

  // lane debug ---------------------------------------------------------------
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

  // HPU ----------------------------------------------------------------------
  logic [QSFP_LANE_NB-1:0][MRMAC_AXIS_W-1:0 ] qsfp_rx_tdata_delayed;
  logic [QSFP_LANE_NB-1:0][MRMAC_TKEEP_W-1:0] qsfp_rx_tkeep_user_delayed;
  logic [QSFP_LANE_NB-1:0]                    qsfp_rx_tlast_delayed;
  logic [QSFP_LANE_NB-1:0]                    qsfp_rx_tvalid_delayed;

  // ============================================================================================== --
  // QSFP interface
  // ============================================================================================== --
    qsfp_if qsfp_rx_vif[QSFP_LANE_NB] (clk_mrmac);

    // == TX
    logic [QSFP_LANE_NB-1:0][MRMAC_AXIS_W-1:0 ] qsfp_tx_tdata;
    logic [QSFP_LANE_NB-1:0][MRMAC_TKEEP_W-1:0] qsfp_tx_tkeep_user;
    logic [QSFP_LANE_NB-1:0]                    qsfp_tx_tlast;
    logic [QSFP_LANE_NB-1:0]                    qsfp_tx_tvalid;
    logic [QSFP_LANE_NB-1:0]                    qsfp_tx_tready;
    //
    // == RX
    logic [QSFP_LANE_NB-1:0][MRMAC_AXIS_W-1:0 ] qsfp_rx_tdata;
    logic [QSFP_LANE_NB-1:0][MRMAC_TKEEP_W-1:0] qsfp_rx_tkeep_user;
    logic [QSFP_LANE_NB-1:0]                    qsfp_rx_tlast;
    logic [QSFP_LANE_NB-1:0]                    qsfp_rx_tvalid;

    generate
      for (genvar gen_i=0; gen_i<QSFP_LANE_NB; gen_i=gen_i+1) begin
        always @(*) begin
          qsfp_rx_tdata_delayed[gen_i]      <= #100ns qsfp_rx_vif[gen_i].tdata;
          qsfp_rx_tkeep_user_delayed[gen_i] <= #100ns qsfp_rx_vif[gen_i].tkeep_user;
          qsfp_rx_tlast_delayed[gen_i]      <= #100ns qsfp_rx_vif[gen_i].tlast;
          qsfp_rx_tvalid_delayed[gen_i]     <= #100ns qsfp_rx_vif[gen_i].tvalid;
        end

        initial begin
          qsfp_rx_vif[gen_i].tdata      = 'h0;
          qsfp_rx_vif[gen_i].tkeep_user = 'h0;
          qsfp_rx_vif[gen_i].tlast      = 1'b0;
          qsfp_rx_vif[gen_i].tvalid     = 1'b0;
          qsfp_rx_vif[gen_i].tready     = 1'b1; // Always ready (no backpressure in this tb)
          qsfp_tx_tready[gen_i]         = 1'b1;
        end
      end
    endgenerate

  // ============================================================================================== --
  // DUT
  // ============================================================================================== --
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
    .qsfp_tx_tready         (qsfp_tx_tready          ),

    .qsfp_rx_tdata          (qsfp_rx_tdata_delayed      ),
    .qsfp_rx_tkeep_user     (qsfp_rx_tkeep_user_delayed ),
    .qsfp_rx_tlast          (qsfp_rx_tlast_delayed      ),
    .qsfp_rx_tvalid         (qsfp_rx_tvalid_delayed     ),

    .gt_line_rate           (gt_line_rate            ),
    .gt_loopback            (gt_loopback            ),
    .gt_reset_rx_datapath   (gt_reset_rx_datapath    ),
    .gt_reset_tx_datapath   (gt_reset_tx_datapath    ),
    .gt_reset_all           (gt_reset_all            ),
    .gt_rx_reset_done       (gt_rx_reset_done        ),
    .gt_tx_reset_done       (gt_tx_reset_done        )
);

// ============================================================================================== --
// Scenario
// ============================================================================================== --
// Signals --------------------------------------------------------------------------------------
logic [REG_DATA_W-1:0] read_data;
logic [REG_DATA_W-1:0] timeout_size;

logic [REG_DATA_W-1:0] regf_start_addr_ofs;

logic [REG_DATA_W-1:0] stat_notify;
logic [REG_DATA_W-1:0] stat_notify_ack;
logic [REG_DATA_W-1:0] stat_notify_retry;
logic [REG_DATA_W-1:0] stat_read_req_retry;
logic [REG_DATA_W-1:0] stat_notify_timeout;
logic [REG_DATA_W-1:0] stat_t_notify_to_ack;
logic [REG_DATA_W-1:0] stat_t_rr_to_ce_received;
logic [REG_DATA_W-1:0] stat_t_ce_first_to_last_pkt;
logic [REG_DATA_W-1:0] stat_cnt_nack_received;
logic [REG_DATA_W-1:0] stat_cnt_notify_received;
logic [REG_DATA_W-1:0] stat_cnt_read_req_received;
logic [REG_DATA_W-1:0] stat_cnt_ce_received;
logic [REG_DATA_W-1:0] stat_read_req_timeout_retry;

logic [SRC_ADDR_W-1:0] iop_src_addr;
logic [DST_ADDR_W-1:0] iop_dst_addr;
logic [SIZE_B_W-1:0]   req_size_b;
logic [MAC_ADDR_W-1:0] dst_mac_addr;
logic [MAC_ADDR_W-1:0] src_mac_addr;
logic [HPU_ID_W-1:0]   dst_hpu_id;
logic [HPU_ID_W-1:0]   src_hpu_id;
logic [IOP_ID_W-1:0]   iop_id;
logic [SRC_ADDR_W-1:0] src_addr;
logic [DST_ADDR_W-1:0] dst_addr;

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
        .s_axi4_awlock  (/* UNUSED */),
        .s_axi4_awcache (/* UNUSED */),
        .s_axi4_awprot  (/* UNUSED */),
        .s_axi4_awqos   (/* UNUSED */),
        .s_axi4_awregion(/* UNUSED */),
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
        .s_axi4_arlock  (/* UNUSED */),
        .s_axi4_arcache (/* UNUSED */),
        .s_axi4_arprot  (/* UNUSED */),
        .s_axi4_arqos   (/* UNUSED */),
        .s_axi4_arregion(/* UNUSED */),
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

  // Decoder --------------------------------------------------------------------------------------
  command_t rx_header;
  logic rx_header_vld;
  logic rx_header_rdy;

  // this is supposed to be HPU_B decoder
  mhdma_decoder mhdma_decoder (
    .clk_mrmac                   (clk_mrmac   ),
    .resetn_mrmac                (s_rstn_mrmac),

    .notify_ack_received         (/* unused */),
    .notify_request_received     (/* unused */),
    .read_request_received       (/* unused */),
    .ciphertext_emission_received(/* unused */),

    .current_hpu_mac             (src_mac_addr),

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

  always_ff @(posedge clk_mrmac)
   rx_header_rdy <= ($urandom() % 100 < 50);

  assign req_size_b = 'h4000;

  // scenario -------------------------------------------------------------------------------------
  int scenario_id;
  initial begin
    maxil_drv_if.init();

    reset_registers = 'h0;
    tx_loop         = 'h0;
    rx_to_tx        = 'h0;
    regf_start_addr_ofs = 'h0;
    repeat(20) @(posedge clk_control);

    $display("\n==================================================================================================");
    $display("  Initial register check and definition");
    $display("==================================================================================================");
    init_config();

    $display("\n==================================================================================================");
    $display("  SCENARIO %0d: Default behavior", scenario_id);
    $display("==================================================================================================");
    iop_id   = scenario_id;
    src_addr = $urandom_range(0, 1<<SRC_ADDR_W);

    notify_request(src_hpu_id, dst_hpu_id, iop_id, iop_src_addr);

    repeat(2) @(posedge clk_mrmac);

    send_notify_ack_packet(qsfp_rx_vif[0], dst_mac_addr, src_mac_addr, dst_hpu_id, iop_id, src_addr, 16'h0);

    repeat (50) @(posedge clk_control);

    maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_NB_NACK_RECEIVED_OFS, stat_cnt_nack_received);
    maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_NOTIFY_OFS, stat_notify);

    assert (stat_cnt_nack_received == 1) begin
      $display("%t > [INFO]: Received %0d ack after Notify", $time, stat_cnt_nack_received);
    end else begin
      $display("%t > [ERROR]: HPU didn't receive the ack from testbench", $time);
      error_ack = 1'b1;
    end

    check_fsm_initialized();

    scenario_id = scenario_id + 1;

    $display("\n==================================================================================================");
    $display("  SCENARIO %0d: no ack is sent to hpu_a", scenario_id);
    $display("==================================================================================================");
    iop_id       = scenario_id;
    iop_src_addr = $urandom_range(0, 1<<SRC_ADDR_W);
    notify_request(src_hpu_id, dst_hpu_id, iop_id, iop_src_addr);

    repeat(2*TIMEOUT_DUR_NOTIFY+5) @(posedge clk_mrmac);

    send_notify_ack_packet(qsfp_rx_vif[0], dst_mac_addr, src_mac_addr, dst_hpu_id, iop_id, src_addr, 16'h0);

    repeat (50) @(posedge clk_control);

    maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_NB_NACK_RECEIVED_OFS, stat_cnt_nack_received);
    maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_NOTIFY_TIMEOUT_RETRY_OFS, stat_notify_retry);

    assert (stat_notify_retry != 0) begin
      $display("%t > [INFO]: Did %0d retries", $time, stat_notify_retry);
      $display("%t > [INFO]: Received %0d ack after Notify", $time, stat_cnt_nack_received);
    end else begin
      $display("%t > [ERROR]: HPU didn't retry sending other Notifies", $time);
      error_retry = 1'b1;
    end

    check_fsm_initialized();

    scenario_id = scenario_id + 1;

    $display("\n==================================================================================================");
    $display("  SCENARIO %0d: an incorrect ack is sent to hpu", scenario_id);
    $display("==================================================================================================");
    iop_id       = scenario_id;
    iop_src_addr = $urandom_range(0, 1<<SRC_ADDR_W);
    notify_request(src_hpu_id, dst_hpu_id, iop_id, iop_src_addr);

    repeat(2*TIMEOUT_DUR_NOTIFY + 5) @(posedge clk_mrmac);
    send_notify_ack_packet(qsfp_rx_vif[0], 24'b0, src_mac_addr, dst_hpu_id, iop_id, src_addr, 16'h0);

    repeat(2*TIMEOUT_DUR_NOTIFY + 5 ) @(posedge clk_mrmac);
    send_notify_ack_packet(qsfp_rx_vif[0], dst_mac_addr, src_mac_addr, dst_hpu_id, iop_id, src_addr, 16'h0);

    repeat (50) @(posedge clk_control);
    maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_NB_NACK_RECEIVED_OFS, stat_cnt_nack_received);
    maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_NOTIFY_TIMEOUT_RETRY_OFS, stat_notify_retry);

    assert (stat_notify_retry != 0) begin
      $display("%t > [INFO]: Did %0d retries", $time, stat_notify_retry);
      $display("%t > [INFO]: Received %0d ack after Notify", $time, stat_cnt_nack_received);
    end else begin
      $display("%t > [ERROR]: HPU didn't retry sending other Notifies", $time);
      error_retry = 1'b1;
    end

    check_fsm_initialized();

    scenario_id = scenario_id + 1;

    $display("\n==================================================================================================");
    $display("  SCENARIO %0d: no ack for a time and a new notify is pending", scenario_id);
    $display("==================================================================================================");
    iop_id       = 'd58;
    iop_src_addr = $urandom_range(0, 1<<SRC_ADDR_W);
    notify_request(src_hpu_id, dst_hpu_id, iop_id, iop_src_addr);

    iop_id       = 'd98;
    iop_src_addr = $urandom_range(0, 1<<SRC_ADDR_W);
    notify_request(src_hpu_id, dst_hpu_id, iop_id, iop_src_addr);

    // Wait for decoder to receive first notify (with possible retries)
    wait(rx_header_vld && rx_header.req_id == REQ_ID_NOTIFY && rx_header.iop_id == 'd58);
    $display("%t > [TB] Decoder saw notify iop_id=58", $time);
    send_notify_ack_packet(qsfp_rx_vif[0], dst_mac_addr, src_mac_addr, dst_hpu_id, 'd58, src_addr, 16'h0);

    // Wait for decoder to receive second notify
    wait(rx_header_vld && rx_header.req_id == REQ_ID_NOTIFY && rx_header.iop_id == 'd98);
    $display("%t > [TB] Decoder saw notify iop_id=98", $time);
    send_notify_ack_packet(qsfp_rx_vif[0], dst_mac_addr, src_mac_addr, dst_hpu_id, 'd98, src_addr, 16'h0);

    // Verify we received the expected notifies
    repeat(50) @(posedge clk_control);

    check_fsm_initialized();

    scenario_id = scenario_id + 1;

    $display("\n==================================================================================================");
    $display("  SCENARIO %0d: Ciphertext emission - Default behavior", scenario_id);
    $display("==================================================================================================");
    iop_id       = scenario_id;
    iop_src_addr = $urandom_range(0, 1<<SRC_ADDR_W);
    iop_dst_addr = $urandom_range(0, 1<<DST_ADDR_W);
    read_request(dst_hpu_id, iop_id, iop_src_addr, iop_dst_addr);

    wait(rx_header_vld & (rx_header.req_id == REQ_ID_READ));

    // Send ciphertext emission packets as if we're the remote HPU responding
    for (int pkt = 0; pkt < NB_PACKETS_FULL+1; pkt++) begin
      send_ciphertext_emission_packet(qsfp_rx_vif[0], dst_mac_addr, src_mac_addr, dst_hpu_id, iop_id, src_addr, dst_addr, pkt[7:0]);
      repeat(10) @(posedge clk_mrmac);
    end

    repeat(50) @(posedge clk_control);

    maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_NB_READ_REQ_RECEIVED_OFS, stat_cnt_read_req_received);
    maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_NB_CE_RECEIVED_OFS, stat_cnt_ce_received);

    assert (stat_cnt_ce_received == NB_PACKETS_FULL+1) begin
      $display("%t > [INFO]: stat_cnt_ce_received : %0d", $time, stat_cnt_ce_received);
    end else begin
      $display("%t > [ERROR]: HPU didn't receive correct amount of CE packets (%0d) expected %0d", $time, stat_cnt_ce_received, NB_PACKETS_FULL+1);
      error_retry = 1'b1;
    end

    repeat(100) @(posedge clk_control);

    check_fsm_initialized();

    scenario_id = scenario_id + 1;

    $display("\n==================================================================================================");
    $display("  SCENARIO %0d: Read request is emitted but not answered", scenario_id);
    $display("==================================================================================================");
    iop_id       = scenario_id;
    iop_src_addr = $urandom_range(0, 1<<SRC_ADDR_W);
    iop_dst_addr = $urandom_range(0, 1<<DST_ADDR_W);
    read_request(dst_hpu_id, iop_id, iop_src_addr, iop_dst_addr);

    repeat(2*TIMEOUT_DUR_READ_REQ + 10 ) @(posedge clk_mrmac);

    $display("%t > [INFO]: answering only after %0d clock cycles", $time, 2*TIMEOUT_DUR_READ_REQ + 10 );

  // Send ciphertext emission packets as if we're the remote HPU responding
    for (int pkt = 0; pkt < NB_PACKETS_FULL+1; pkt++) begin
      send_ciphertext_emission_packet(qsfp_rx_vif[0], dst_mac_addr, src_mac_addr, dst_hpu_id, iop_id, src_addr, dst_addr, pkt[7:0]);
      repeat(10) @(posedge clk_mrmac);
    end

    maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_READ_REQ_TIMEOUT_RETRY_OFS, stat_read_req_timeout_retry);

    assert (stat_read_req_timeout_retry != 0) begin
      $display("%t > [INFO]: Did %0d retries", $time, stat_read_req_timeout_retry);
    end else begin
      $display("%t > [ERROR]: HPU didn't retry sending other Notifies", $time);
      error_retry = 1'b1;
    end

    repeat(100) @(posedge clk_control);

    check_fsm_initialized();

    scenario_id = scenario_id + 1;

    $display("\n==================================================================================================");
    $display("  SCENARIO %0d: Sending a wrong seq num", scenario_id);
    $display("==================================================================================================");
    // emptying stat_read_req_timeout_retry value
    maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_READ_REQ_TIMEOUT_RETRY_OFS, stat_read_req_timeout_retry);

    iop_id       = scenario_id;
    iop_src_addr = $urandom_range(0, 1<<SRC_ADDR_W);
    iop_dst_addr = $urandom_range(0, 1<<DST_ADDR_W);
    read_request(dst_hpu_id, iop_id, iop_src_addr, iop_dst_addr);

    wait(rx_header_vld & (rx_header.req_id == REQ_ID_READ));

    // Send ciphertext emission packets as if we're the remote HPU responding
    for (int pkt = 0; pkt < NB_PACKETS_FULL+1; pkt++) begin
      if (pkt == 8) begin
        // for 8th packet we send a wrong arbitrary seq_num
        send_ciphertext_emission_packet(qsfp_rx_vif[0], dst_mac_addr, src_mac_addr, dst_hpu_id, iop_id, src_addr, dst_addr, 3);
      end else begin
        send_ciphertext_emission_packet(qsfp_rx_vif[0], dst_mac_addr, src_mac_addr, dst_hpu_id, iop_id, src_addr, dst_addr, pkt[7:0]);
      end
      repeat(10) @(posedge clk_mrmac);
    end

    repeat(500) @(posedge clk_control);

    maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_READ_REQ_TIMEOUT_RETRY_OFS, stat_read_req_timeout_retry);

    // we must have a retry
    assert (stat_read_req_timeout_retry != 0) begin
      $display("%t > [INFO]: Did %0d retries after wrong seq num", $time, stat_read_req_timeout_retry);
    end else begin
      $display("%t > [ERROR]: HPU didn't retry sending other Notifies", $time);
      error_retry = 1'b1;
    end

    // Send ciphertext emission packets as if we're the remote HPU responding
    for (int pkt = 0; pkt < NB_PACKETS_FULL+1; pkt++) begin
      send_ciphertext_emission_packet(qsfp_rx_vif[0], dst_mac_addr, src_mac_addr, dst_hpu_id, iop_id, src_addr, dst_addr, pkt[7:0]);
      repeat(10) @(posedge clk_mrmac);
    end

    repeat(500) @(posedge clk_control);

    check_fsm_initialized();

    $display("\n ----------------- HPU_A Final Summary -----------------------");
    maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_NOTIFY_OFS, stat_notify);
    maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_NOTIFY_ACK_OFS, stat_notify_ack);
    maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_NOTIFY_TIMEOUT_RETRY_OFS, stat_notify_retry);
    maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_READ_REQ_TIMEOUT_RETRY_OFS, stat_read_req_retry);
    maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_NOTIFY_TIMEOUT_OFS, stat_notify_timeout);
    maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_T_NOTIFY_TO_ACK_OFS, stat_t_notify_to_ack);
    maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_T_RR_TO_CE_RECEIVED_OFS, stat_t_rr_to_ce_received);
    maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_T_CE_FIRST_TO_LAST_PKT_OFS, stat_t_ce_first_to_last_pkt);
    maxil_drv_if.read_trans(MHDMA_REQUEST_STAT_NB_NACK_RECEIVED_OFS, stat_cnt_nack_received);
    $display(" stat_notify                 : %0d", stat_notify);
    $display(" stat_notify_ack             : %0d", stat_notify_ack);
    $display(" stat_nack_received          : %0d", stat_cnt_nack_received);
    $display(" stat_notify_retry           : %0d", stat_notify_retry);
    $display(" stat_read_req_retry         : %0d", stat_read_req_retry);
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

        gen_mem_pc[gen_pc].axi4_mem_ct.axi4_ram_ct_wr.mem[k] = value;
      end
    end
    for (int gen_pc = 0; gen_pc < ETH_PC; ++gen_pc) begin
      for (int k = 0; k < 2**MEM_SIM_SIZE; ++k) begin
        gen_mem_pc[gen_pc].axi4_mem_ct.axi4_ram_ct_wr.mem[k] = 'h0;
    end
    end
  end

// ============================================================================================== --
// Tasks
// ============================================================================================== --
  logic [REG_DATA_W-1:00] rdata;

  task automatic init_config;
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

      src_hpu_id = 0;
      dst_hpu_id = 1;

      src_mac_addr = $urandom();
      dst_mac_addr = $urandom();

      write_mac_addresses(dst_mac_addr, src_mac_addr);

      $display("%t > INFO: Configuration successful\n",$time);
    end
  endtask

  task automatic write_mac_addresses(
    input logic [MAC_ADDR_W-1:0] src_mac_addr,
    input logic [MAC_ADDR_W-1:0] dst_mac_addr
  );
    begin
      maxil_drv_if.write_trans(MHDMA_SYSTEM_HPU_ID_0_OFS,  {1'b1, 3'b0, 4'h0, src_mac_addr});
      maxil_drv_if.write_trans(MHDMA_SYSTEM_HPU_ID_1_OFS,   {1'b0, 3'b0, 4'h1, dst_mac_addr});

      repeat(50) @(posedge clk_mrmac);

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

      repeat(50) @(posedge clk_mrmac);

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

      repeat(50) @(posedge clk_mrmac);

    end
  endtask

  task automatic check_fsm_initialized();
    begin
      if (hpu_a.mhdma_bridge.mhdma_master.ntx_retry != 0) begin
        $display("%t > [ERROR] : FSM mhdma_master.ntx_retry has not been back to IDLE", $time);
        error_fsm = 1 ;
      end
      if (hpu_a.mhdma_bridge.mhdma_master.rreq_state != 0) begin
        $display("%t > [ERROR] : FSM mhdma_master.rreq_state has not been back to IDLE", $time);
        error_fsm = 1 ;
      end
      if (hpu_a.mhdma_bridge.mhdma_slave.nrx_state != 0) begin
        $display("%t > [ERROR] : FSM mhdma_slave.nrx_state has not been back to IDLE", $time);
        error_fsm = 1 ;
      end
      if (hpu_a.mhdma_bridge.mhdma_slave.cem_state != 0) begin
        $display("%t > [ERROR] : FSM mhdma_slave.cem_state has not been back to IDLE", $time);
        error_fsm = 1 ;
      end
      if (hpu_a.mhdma_bridge.mhdma_formatter.tx_state != 0) begin
        $display("%t > [ERROR] : FSM mhdma_slave.tx_state has not been back to IDLE", $time);
        error_fsm = 1 ;
      end

      repeat(50) @(posedge clk_mrmac);
      $display("%t > [INFO]: all FSMs are back to IDLE", $time);

    end
  endtask

endmodule
