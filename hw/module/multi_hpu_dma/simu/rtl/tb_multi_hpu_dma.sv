// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : This testbench only tests debug mode
// Debug mode corresponds to the control of one lane through register file
//
// TODO:
// - test interrupts are correctly clear when read and that no read packet is lost
// - test behavior when saying several HPUs are the current one by mistake
//
// ==============================================================================================

`resetall
`timescale 1ns/10ps
module tb_multi_hpu_dma;
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

  localparam int HPU_NB = 2; // in this test we will try to connect two mhdma (or HPUs)

  localparam int FIFO_DEPTH = 512;

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
  localparam [ETH_PC-1:0][15:0] PC_CT_BYTES = '{'h2000, 'h2020};
  localparam              [3:0] PC_STRIDE   = 'hB;


  // TOREVIEW
  // generate cannot be in packages, same snippet must be in slave & master module
  generate
    for (genvar gen_i = 0; gen_i < ETH_PC; gen_i = gen_i + 1) begin : gen_localparam
      localparam int PC_NB_WORDS = (PC_CT_BYTES[gen_i] / AXI4_DATA_BYTES);
      localparam int PC_NB_BURST = (PC_NB_WORDS / MAX_BURST_SIZE);
      localparam int PC_REMAINS = (PC_NB_WORDS % MAX_BURST_SIZE);
      localparam int PC_NB = (PC_REMAINS!=0) ? PC_NB_BURST + 1 : PC_NB_BURST;
    end
  endgenerate

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
  bit error_write_missmatch;
  bit error_interrupt_notify;

  assign error = error_tb_notify | error_register_read | error_notify_rx | error_rr_payload | error_write_missmatch | error_interrupt_notify;

  always_ff @(posedge clk_control)
    if (error) begin
      $display("%t > FAILURE !", $time);
      $finish;
    end

// ============================================================================================== --
// input / output signals
// ============================================================================================== --
  logic [AXIL_ADD_W-1:0]      s_axil_dma_awaddr_hpu_a;
  logic                       s_axil_dma_awvalid_hpu_a;
  logic                       s_axil_dma_awready_hpu_a;
  logic [AXIL_DATA_W-1:0]     s_axil_dma_wdata_hpu_a;
  logic [AXIL_DATA_BYTES-1:0] s_axil_dma_wstrb_hpu_a; /* UNUSED */
  logic                       s_axil_dma_wvalid_hpu_a;
  logic                       s_axil_dma_wready_hpu_a;
  logic [1:0]                 s_axil_dma_bresp_hpu_a;
  logic                       s_axil_dma_bvalid_hpu_a;
  logic                       s_axil_dma_bready_hpu_a;
  logic [AXIL_ADD_W-1:0]      s_axil_dma_araddr_hpu_a;
  logic                       s_axil_dma_arvalid_hpu_a;
  logic                       s_axil_dma_arready_hpu_a;
  logic [AXIL_DATA_W-1:0]     s_axil_dma_rdata_hpu_a;
  logic [1:0]                 s_axil_dma_rresp_hpu_a;
  logic                       s_axil_dma_rvalid_hpu_a;
  logic                       s_axil_dma_rready_hpu_a;

  logic [AXIL_ADD_W-1:0]      s_axil_dma_awaddr_hpu_b;
  logic                       s_axil_dma_awvalid_hpu_b;
  logic                       s_axil_dma_awready_hpu_b;
  logic [AXIL_DATA_W-1:0]     s_axil_dma_wdata_hpu_b;
  logic [AXIL_DATA_BYTES-1:0] s_axil_dma_wstrb_hpu_b; /* UNUSED */
  logic                       s_axil_dma_wvalid_hpu_b;
  logic                       s_axil_dma_wready_hpu_b;
  logic [1:0]                 s_axil_dma_bresp_hpu_b;
  logic                       s_axil_dma_bvalid_hpu_b;
  logic                       s_axil_dma_bready_hpu_b;
  logic [AXIL_ADD_W-1:0]      s_axil_dma_araddr_hpu_b;
  logic                       s_axil_dma_arvalid_hpu_b;
  logic                       s_axil_dma_arready_hpu_b;
  logic [AXIL_DATA_W-1:0]     s_axil_dma_rdata_hpu_b;
  logic [1:0]                 s_axil_dma_rresp_hpu_b;
  logic                       s_axil_dma_rvalid_hpu_b;
  logic                       s_axil_dma_rready_hpu_b;
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

  // TODO: for now always ready
  assign sim_qsfp_tx_tready = 4'b1111;

  // AXI4 to HBM: HPUA ----------------------------------------------------------------------------
  // Read channel
  logic [ETH_PC-1:0][   AXI4_ID_W-1:0]    hpu_a_axi4_arid;
  logic [ETH_PC-1:0][  AXI4_ADD_W-1:0]    hpu_a_axi4_araddr;
  logic [ETH_PC-1:0][  AXI4_LEN_W-1:0]    hpu_a_axi4_arlen;
  logic [ETH_PC-1:0][ AXI4_SIZE_W-1:0]    hpu_a_axi4_arsize;
  logic [ETH_PC-1:0][AXI4_BURST_W-1:0]    hpu_a_axi4_arburst;
  logic [ETH_PC-1:0]                      hpu_a_axi4_arvalid;
  logic [ETH_PC-1:0]                      hpu_a_axi4_arready;
  logic [ETH_PC-1:0][  AXI4_ID_W-1:0]     hpu_a_axi4_rid;
  logic [ETH_PC-1:0][AXI4_DATA_W-1:0]     hpu_a_axi4_rdata;
  logic [ETH_PC-1:0][AXI4_RESP_W-1:0]     hpu_a_axi4_rresp;
  logic [ETH_PC-1:0]                      hpu_a_axi4_rlast;
  logic [ETH_PC-1:0]                      hpu_a_axi4_rvalid;
  logic [ETH_PC-1:0]                      hpu_a_axi4_rready;
  // Write channel
  logic [ETH_PC-1:0][   AXI4_ID_W-1:0]    hpu_a_axi4_awid;
  logic [ETH_PC-1:0][  AXI4_ADD_W-1:0]    hpu_a_axi4_awaddr;
  logic [ETH_PC-1:0][  AXI4_LEN_W-1:0]    hpu_a_axi4_awlen;
  logic [ETH_PC-1:0][ AXI4_SIZE_W-1:0]    hpu_a_axi4_awsize;
  logic [ETH_PC-1:0][AXI4_BURST_W-1:0]    hpu_a_axi4_awburst;
  logic [ETH_PC-1:0]                      hpu_a_axi4_awvalid;
  logic [ETH_PC-1:0]                      hpu_a_axi4_awready;
  logic [ETH_PC-1:0][AXI4_DATA_W-1:0]     hpu_a_axi4_wdata;
  logic [ETH_PC-1:0][AXI4_STRB_W-1:0]     hpu_a_axi4_wstrb;
  logic [ETH_PC-1:0]                      hpu_a_axi4_wlast;
  logic [ETH_PC-1:0]                      hpu_a_axi4_wvalid;
  logic [ETH_PC-1:0]                      hpu_a_axi4_wready;
  logic [ETH_PC-1:0][  AXI4_ID_W-1:0]     hpu_a_axi4_bid;
  logic [ETH_PC-1:0][AXI4_RESP_W-1:0]     hpu_a_axi4_bresp;
  logic [ETH_PC-1:0]                      hpu_a_axi4_bvalid;
  logic [ETH_PC-1:0]                      hpu_a_axi4_bready;
  // cnx to memory models -------------------------------------------------------------------------
  logic [ETH_PC-1:0][HPU_NB-1:0][AXI4_ID_W-1:0]       axi4_ct_awid;
  logic [ETH_PC-1:0][HPU_NB-1:0][AXI4_ADD_W-1:0]      axi4_ct_awaddr;
  logic [ETH_PC-1:0][HPU_NB-1:0][7:0]                 axi4_ct_awlen;
  logic [ETH_PC-1:0][HPU_NB-1:0][2:0]                 axi4_ct_awsize;
  logic [ETH_PC-1:0][HPU_NB-1:0][1:0]                 axi4_ct_awburst;
  logic [ETH_PC-1:0][HPU_NB-1:0]                      axi4_ct_awvalid;
  logic [ETH_PC-1:0][HPU_NB-1:0]                      axi4_ct_awready;
  logic [ETH_PC-1:0][HPU_NB-1:0][AXI4_DATA_W-1:0]     axi4_ct_wdata;
  logic [ETH_PC-1:0][HPU_NB-1:0][(AXI4_DATA_W/8)-1:0] axi4_ct_wstrb;
  logic [ETH_PC-1:0][HPU_NB-1:0]                      axi4_ct_wlast;
  logic [ETH_PC-1:0][HPU_NB-1:0]                      axi4_ct_wvalid;
  logic [ETH_PC-1:0][HPU_NB-1:0]                      axi4_ct_wready;
  logic [ETH_PC-1:0][HPU_NB-1:0][AXI4_ID_W-1:0]       axi4_ct_bid;
  logic [ETH_PC-1:0][HPU_NB-1:0][1:0]                 axi4_ct_bresp;
  logic [ETH_PC-1:0][HPU_NB-1:0]                      axi4_ct_bvalid;
  logic [ETH_PC-1:0][HPU_NB-1:0]                      axi4_ct_bready;

  logic [ETH_PC-1:0][HPU_NB-1:0][AXI4_ID_W-1:0]       axi4_ct_arid;
  logic [ETH_PC-1:0][HPU_NB-1:0][AXI4_ADD_W-1:0]      axi4_ct_araddr;
  logic [ETH_PC-1:0][HPU_NB-1:0][7:0]                 axi4_ct_arlen;
  logic [ETH_PC-1:0][HPU_NB-1:0][2:0]                 axi4_ct_arsize;
  logic [ETH_PC-1:0][HPU_NB-1:0][1:0]                 axi4_ct_arburst;
  logic [ETH_PC-1:0][HPU_NB-1:0]                      axi4_ct_arvalid;
  logic [ETH_PC-1:0][HPU_NB-1:0]                      axi4_ct_arready;
  logic [ETH_PC-1:0][HPU_NB-1:0][AXI4_ID_W-1:0]       axi4_ct_rid;
  logic [ETH_PC-1:0][HPU_NB-1:0][AXI4_DATA_W-1:0]     axi4_ct_rdata;
  logic [ETH_PC-1:0][HPU_NB-1:0][1:0]                 axi4_ct_rresp;
  logic [ETH_PC-1:0][HPU_NB-1:0]                      axi4_ct_rlast;
  logic [ETH_PC-1:0][HPU_NB-1:0]                      axi4_ct_rvalid;
  logic [ETH_PC-1:0][HPU_NB-1:0]                      axi4_ct_rready;

  // ============================================================================================== --
  // Design under test instance
  // ============================================================================================== --
  // gt configuration signals
  logic [HPU_NB-1:0][7:0]              gt_line_rate;
  logic [HPU_NB-1:0][2:0]              gt_loopback;
  logic [HPU_NB-1:0][QSFP_LANE_NB-1:0] gt_reset_rx_datapath;
  logic [HPU_NB-1:0][QSFP_LANE_NB-1:0] gt_reset_tx_datapath;
  logic [HPU_NB-1:0][QSFP_LANE_NB-1:0] gt_reset_all;
  logic [HPU_NB-1:0][QSFP_LANE_NB-1:0] gt_rx_reset_done;
  logic [HPU_NB-1:0][QSFP_LANE_NB-1:0] gt_tx_reset_done;

  // [section] line parameter -------------------------------------------------
  logic [REG_DATA_W-1:0] line_parameter;
  logic        debug_flag;
  logic [2:0]  line_loopback;
  logic [7:0]  line_rate;
  logic [1:0]  line_select;

  assign line_parameter[1:0]   = line_select;
  assign line_parameter[4:2]   = line_loopback;
  assign line_parameter[12:5]  = line_rate;
  assign line_parameter[27:13] = 'h0;
  assign line_parameter[31]    = debug_flag;

  // [section] line debug -----------------------------------------------------
  logic [REG_DATA_W-1:0] line_debug;
  logic        reset_registers;
  logic        tx_loop;
  logic        rx_to_tx;

  assign line_debug[28:0] = 'h0;
  assign line_debug[29]   = rx_to_tx;
  assign line_debug[30]   = tx_loop;
  assign line_debug[31]   = reset_registers;

  // [section] reset ----------------------------------------------------------
  logic [REG_DATA_W-1:00] reset_parameter;
  logic [QSFP_LANE_NB-1:0] rst_rx_datapath;
  logic [QSFP_LANE_NB-1:0] rst_tx_datapath;
  logic [QSFP_LANE_NB-1:0] rst_all;

  assign reset_parameter = {20'h0, rst_rx_datapath, rst_tx_datapath, rst_all};

  // monitoring of reset done
  logic [HPU_NB-1:0][REG_DATA_W-1:00] reset_monitor;

  // HPU A ----------------------------------------------------------------------------------------
  multi_hpu_dma #(
    .FIFO_DEPTH(FIFO_DEPTH)
  ) hpu_a (
    .clk_eth_cfg   (clk_control    ),
    .resetn_eth_cfg(s_rstn_control ),

    .clk_eth_mrmac   (clk_mrmac    ),
    .resetn_eth_mrmac(s_rstn_mrmac ),

    .s_axil_dma_awaddr (s_axil_dma_awaddr_hpu_a ),
    .s_axil_dma_awvalid(s_axil_dma_awvalid_hpu_a),
    .s_axil_dma_awready(s_axil_dma_awready_hpu_a),
    .s_axil_dma_wdata  (s_axil_dma_wdata_hpu_a  ),
    .s_axil_dma_wstrb  (s_axil_dma_wstrb_hpu_a  ),
    .s_axil_dma_wvalid (s_axil_dma_wvalid_hpu_a ),
    .s_axil_dma_wready (s_axil_dma_wready_hpu_a ),
    .s_axil_dma_bresp  (s_axil_dma_bresp_hpu_a  ),
    .s_axil_dma_bvalid (s_axil_dma_bvalid_hpu_a ),
    .s_axil_dma_bready (s_axil_dma_bready_hpu_a ),
    .s_axil_dma_araddr (s_axil_dma_araddr_hpu_a ),
    .s_axil_dma_arvalid(s_axil_dma_arvalid_hpu_a),
    .s_axil_dma_arready(s_axil_dma_arready_hpu_a),
    .s_axil_dma_rdata  (s_axil_dma_rdata_hpu_a  ),
    .s_axil_dma_rresp  (s_axil_dma_rresp_hpu_a  ),
    .s_axil_dma_rvalid (s_axil_dma_rvalid_hpu_a ),
    .s_axil_dma_rready (s_axil_dma_rready_hpu_a ),

    .m_axi4_eth_hbm_arid       (axi4_ct_arid[0]         ),
    .m_axi4_eth_hbm_araddr     (axi4_ct_araddr[0]       ),
    .m_axi4_eth_hbm_arlen      (axi4_ct_arlen[0]        ),
    .m_axi4_eth_hbm_arsize     (axi4_ct_arsize[0]       ),
    .m_axi4_eth_hbm_arburst    (axi4_ct_arburst[0]      ),
    .m_axi4_eth_hbm_arvalid    (axi4_ct_arvalid[0]      ),
    .m_axi4_eth_hbm_arready    (axi4_ct_arready[0]      ),
    .m_axi4_eth_hbm_rid        (axi4_ct_rid[0]          ),
    .m_axi4_eth_hbm_rdata      (axi4_ct_rdata[0]        ),
    .m_axi4_eth_hbm_rresp      (axi4_ct_rresp[0]        ),
    .m_axi4_eth_hbm_rlast      (axi4_ct_rlast[0]        ),
    .m_axi4_eth_hbm_rvalid     (axi4_ct_rvalid[0]       ),
    .m_axi4_eth_hbm_rready     (axi4_ct_rready[0]       ),
    .m_axi4_eth_hbm_awid       (axi4_ct_awid[0]         ),
    .m_axi4_eth_hbm_awaddr     (axi4_ct_awaddr[0]       ),
    .m_axi4_eth_hbm_awlen      (axi4_ct_awlen[0]        ),
    .m_axi4_eth_hbm_awsize     (axi4_ct_awsize[0]       ),
    .m_axi4_eth_hbm_awburst    (axi4_ct_awburst[0]      ),
    .m_axi4_eth_hbm_awvalid    (axi4_ct_awvalid[0]      ),
    .m_axi4_eth_hbm_awready    (axi4_ct_awready[0]      ),
    .m_axi4_eth_hbm_wdata      (axi4_ct_wdata[0]        ),
    .m_axi4_eth_hbm_wstrb      (axi4_ct_wstrb[0]        ),
    .m_axi4_eth_hbm_wlast      (axi4_ct_wlast[0]        ),
    .m_axi4_eth_hbm_wvalid     (axi4_ct_wvalid[0]       ),
    .m_axi4_eth_hbm_wready     (axi4_ct_wready[0]       ),
    .m_axi4_eth_hbm_bid        (axi4_ct_bid[0]          ),
    .m_axi4_eth_hbm_bresp      (axi4_ct_bresp[0]        ),
    .m_axi4_eth_hbm_bvalid     (axi4_ct_bvalid[0]       ),
    .m_axi4_eth_hbm_bready     (axi4_ct_bready[0]       ),

    .qsfp_tx_tdata     (qsfp_tx_tdata           ),
    .qsfp_tx_tkeep_user(qsfp_tx_tkeep_user      ),
    .qsfp_tx_tlast     (qsfp_tx_tlast           ),
    .qsfp_tx_tvalid    (qsfp_tx_tvalid          ),
    .qsfp_tx_tready    (sim_qsfp_tx_tready      ),

    .qsfp_rx_tdata     (qsfp_rx_tdata           ),
    .qsfp_rx_tkeep_user(qsfp_rx_tkeep_user      ),
    .qsfp_rx_tlast     (qsfp_rx_tlast           ),
    .qsfp_rx_tvalid    (qsfp_rx_tvalid          ),

    .gt_line_rate        (gt_line_rate[0]        ),
    .gt_loopback         (gt_loopback[0]         ),
    .gt_reset_rx_datapath(gt_reset_rx_datapath[0]),
    .gt_reset_tx_datapath(gt_reset_tx_datapath[0]),
    .gt_reset_all        (gt_reset_all[0]        ),
    .gt_rx_reset_done    (gt_rx_reset_done[0]    ),
    .gt_tx_reset_done    (gt_tx_reset_done[0]    )
);

  // HPU B ----------------------------------------------------------------------------------------
  multi_hpu_dma #(
    .FIFO_DEPTH(FIFO_DEPTH)
  ) hpu_b (
    .clk_eth_cfg   (clk_control    ),
    .resetn_eth_cfg(s_rstn_control ),

    .clk_eth_mrmac   (clk_mrmac    ),
    .resetn_eth_mrmac(s_rstn_mrmac ),

    .s_axil_dma_awaddr (s_axil_dma_awaddr_hpu_b ),
    .s_axil_dma_awvalid(s_axil_dma_awvalid_hpu_b),
    .s_axil_dma_awready(s_axil_dma_awready_hpu_b),
    .s_axil_dma_wdata  (s_axil_dma_wdata_hpu_b  ),
    .s_axil_dma_wstrb  (s_axil_dma_wstrb_hpu_b  ),
    .s_axil_dma_wvalid (s_axil_dma_wvalid_hpu_b ),
    .s_axil_dma_wready (s_axil_dma_wready_hpu_b ),
    .s_axil_dma_bresp  (s_axil_dma_bresp_hpu_b  ),
    .s_axil_dma_bvalid (s_axil_dma_bvalid_hpu_b ),
    .s_axil_dma_bready (s_axil_dma_bready_hpu_b ),
    .s_axil_dma_araddr (s_axil_dma_araddr_hpu_b ),
    .s_axil_dma_arvalid(s_axil_dma_arvalid_hpu_b),
    .s_axil_dma_arready(s_axil_dma_arready_hpu_b),
    .s_axil_dma_rdata  (s_axil_dma_rdata_hpu_b  ),
    .s_axil_dma_rresp  (s_axil_dma_rresp_hpu_b  ),
    .s_axil_dma_rvalid (s_axil_dma_rvalid_hpu_b ),
    .s_axil_dma_rready (s_axil_dma_rready_hpu_b ),

    .m_axi4_eth_hbm_arid       (axi4_ct_arid[1]       ),
    .m_axi4_eth_hbm_araddr     (axi4_ct_araddr[1]     ),
    .m_axi4_eth_hbm_arlen      (axi4_ct_arlen[1]      ),
    .m_axi4_eth_hbm_arsize     (axi4_ct_arsize[1]     ),
    .m_axi4_eth_hbm_arburst    (axi4_ct_arburst[1]    ),
    .m_axi4_eth_hbm_arvalid    (axi4_ct_arvalid[1]    ),
    .m_axi4_eth_hbm_arready    (axi4_ct_arready[1]    ),
    .m_axi4_eth_hbm_rid        (axi4_ct_rid[1]        ),
    .m_axi4_eth_hbm_rdata      (axi4_ct_rdata[1]      ),
    .m_axi4_eth_hbm_rresp      (axi4_ct_rresp[1]      ),
    .m_axi4_eth_hbm_rlast      (axi4_ct_rlast[1]      ),
    .m_axi4_eth_hbm_rvalid     (axi4_ct_rvalid[1]     ),
    .m_axi4_eth_hbm_rready     (axi4_ct_rready[1]     ),
    .m_axi4_eth_hbm_awid       (axi4_ct_awid[1]       ),
    .m_axi4_eth_hbm_awaddr     (axi4_ct_awaddr[1]     ),
    .m_axi4_eth_hbm_awlen      (axi4_ct_awlen[1]      ),
    .m_axi4_eth_hbm_awsize     (axi4_ct_awsize[1]     ),
    .m_axi4_eth_hbm_awburst    (axi4_ct_awburst[1]    ),
    .m_axi4_eth_hbm_awvalid    (axi4_ct_awvalid[1]    ),
    .m_axi4_eth_hbm_awready    (axi4_ct_awready[1]    ),
    .m_axi4_eth_hbm_wdata      (axi4_ct_wdata[1]      ),
    .m_axi4_eth_hbm_wstrb      (axi4_ct_wstrb[1]      ),
    .m_axi4_eth_hbm_wlast      (axi4_ct_wlast[1]      ),
    .m_axi4_eth_hbm_wvalid     (axi4_ct_wvalid[1]     ),
    .m_axi4_eth_hbm_wready     (axi4_ct_wready[1]     ),
    .m_axi4_eth_hbm_bid        (axi4_ct_bid[1]        ),
    .m_axi4_eth_hbm_bresp      (axi4_ct_bresp[1]      ),
    .m_axi4_eth_hbm_bvalid     (axi4_ct_bvalid[1]     ),
    .m_axi4_eth_hbm_bready     (axi4_ct_bready[1]     ),

    .qsfp_tx_tdata     (qsfp_rx_tdata),
    .qsfp_tx_tkeep_user(qsfp_rx_tkeep_user),
    .qsfp_tx_tlast     (qsfp_rx_tlast),
    .qsfp_tx_tvalid    (qsfp_rx_tvalid),
    .qsfp_tx_tready    (sim_qsfp_tx_tready),

    .qsfp_rx_tdata     (qsfp_tx_tdata),
    .qsfp_rx_tkeep_user(qsfp_tx_tkeep_user),
    .qsfp_rx_tlast     (qsfp_tx_tlast),
    .qsfp_rx_tvalid    (qsfp_tx_tvalid),

    .gt_line_rate        (gt_line_rate[1]        ),
    .gt_loopback         (gt_loopback[1]         ),
    .gt_reset_rx_datapath(gt_reset_rx_datapath[1]),
    .gt_reset_tx_datapath(gt_reset_tx_datapath[1]),
    .gt_reset_all        (gt_reset_all[1]        ),
    .gt_rx_reset_done    (gt_rx_reset_done[1]    ),
    .gt_tx_reset_done    (gt_tx_reset_done[1]    )
);

// ============================================================================================== --
// Scenario
// ============================================================================================== --

  // AXI4-LITE drivers ----------------------------------------------------------------------------
  maxil_if #(
  .AXIL_DATA_W(AXIL_DATA_W),
  .AXIL_ADD_W  (AXIL_ADD_W)
  ) maxil_drv_if_hpu_a ( .clk(clk_control), .rst_n(s_rstn_control));

  // Connect interface on testbench signals
  assign s_axil_dma_awaddr_hpu_a  = maxil_drv_if_hpu_a.awaddr;
  assign s_axil_dma_awvalid_hpu_a = maxil_drv_if_hpu_a.awvalid;
  assign s_axil_dma_wdata_hpu_a   = maxil_drv_if_hpu_a.wdata;
  assign s_axil_dma_wstrb_hpu_a   = maxil_drv_if_hpu_a.wstrb;
  assign s_axil_dma_wvalid_hpu_a  = maxil_drv_if_hpu_a.wvalid;
  assign s_axil_dma_bready_hpu_a  = maxil_drv_if_hpu_a.bready;
  assign s_axil_dma_araddr_hpu_a  = maxil_drv_if_hpu_a.araddr;
  assign s_axil_dma_arvalid_hpu_a = maxil_drv_if_hpu_a.arvalid;
  assign s_axil_dma_rready_hpu_a  = maxil_drv_if_hpu_a.rready;

  assign maxil_drv_if_hpu_a.awready = s_axil_dma_awready_hpu_a;
  assign maxil_drv_if_hpu_a.wready  = s_axil_dma_wready_hpu_a;
  assign maxil_drv_if_hpu_a.bresp   = s_axil_dma_bresp_hpu_a;
  assign maxil_drv_if_hpu_a.bvalid  = s_axil_dma_bvalid_hpu_a;
  assign maxil_drv_if_hpu_a.arready = s_axil_dma_arready_hpu_a;
  assign maxil_drv_if_hpu_a.rdata   = s_axil_dma_rdata_hpu_a;
  assign maxil_drv_if_hpu_a.rresp   = s_axil_dma_rresp_hpu_a;
  assign maxil_drv_if_hpu_a.rvalid  = s_axil_dma_rvalid_hpu_a;

  maxil_if #(
  .AXIL_DATA_W(AXIL_DATA_W),
  .AXIL_ADD_W  (AXIL_ADD_W)
  ) maxil_drv_if_hpu_b ( .clk(clk_control), .rst_n(s_rstn_control));

  // Connect interface on testbench signals
  assign s_axil_dma_awaddr_hpu_b  = maxil_drv_if_hpu_b.awaddr;
  assign s_axil_dma_awvalid_hpu_b = maxil_drv_if_hpu_b.awvalid;
  assign s_axil_dma_wdata_hpu_b   = maxil_drv_if_hpu_b.wdata;
  assign s_axil_dma_wstrb_hpu_b   = maxil_drv_if_hpu_b.wstrb;
  assign s_axil_dma_wvalid_hpu_b  = maxil_drv_if_hpu_b.wvalid;
  assign s_axil_dma_bready_hpu_b  = maxil_drv_if_hpu_b.bready;
  assign s_axil_dma_araddr_hpu_b  = maxil_drv_if_hpu_b.araddr;
  assign s_axil_dma_arvalid_hpu_b = maxil_drv_if_hpu_b.arvalid;
  assign s_axil_dma_rready_hpu_b  = maxil_drv_if_hpu_b.rready;

  assign maxil_drv_if_hpu_b.awready = s_axil_dma_awready_hpu_b;
  assign maxil_drv_if_hpu_b.wready  = s_axil_dma_wready_hpu_b;
  assign maxil_drv_if_hpu_b.bresp   = s_axil_dma_bresp_hpu_b;
  assign maxil_drv_if_hpu_b.bvalid  = s_axil_dma_bvalid_hpu_b;
  assign maxil_drv_if_hpu_b.arready = s_axil_dma_arready_hpu_b;
  assign maxil_drv_if_hpu_b.rdata   = s_axil_dma_rdata_hpu_b;
  assign maxil_drv_if_hpu_b.rresp   = s_axil_dma_rresp_hpu_b;
  assign maxil_drv_if_hpu_b.rvalid  = s_axil_dma_rvalid_hpu_b;

  generate
    for (genvar gen_hpu=0; gen_hpu<HPU_NB; gen_hpu=gen_hpu+1) begin : gen_mem_hpu
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
          .s_axi4_awid   (axi4_ct_awid[gen_hpu][gen_pc]     ),
          .s_axi4_awaddr (axi4_ct_awaddr[gen_hpu][gen_pc]   ),
          .s_axi4_awlen  (axi4_ct_awlen[gen_hpu][gen_pc]    ),
          .s_axi4_awsize (axi4_ct_awsize[gen_hpu][gen_pc]   ),
          .s_axi4_awburst(axi4_ct_awburst[gen_hpu][gen_pc]  ),
          .s_axi4_awlock ('0), // disable
          .s_axi4_awcache('0), // disable
          .s_axi4_awprot ('0), // disable
          .s_axi4_awvalid(axi4_ct_awvalid[gen_hpu][gen_pc]  ),
          .s_axi4_awready(axi4_ct_awready[gen_hpu][gen_pc]  ),
          .s_axi4_wdata  (axi4_ct_wdata[gen_hpu][gen_pc]    ),
          .s_axi4_wstrb  (axi4_ct_wstrb[gen_hpu][gen_pc]    ),
          .s_axi4_wlast  (axi4_ct_wlast[gen_hpu][gen_pc]    ),
          .s_axi4_wvalid (axi4_ct_wvalid[gen_hpu][gen_pc]   ),
          .s_axi4_wready (axi4_ct_wready[gen_hpu][gen_pc]   ),
          .s_axi4_bid    (axi4_ct_bid[gen_hpu][gen_pc]      ),
          .s_axi4_bresp  (axi4_ct_bresp[gen_hpu][gen_pc]    ),
          .s_axi4_bvalid (axi4_ct_bvalid[gen_hpu][gen_pc]   ),
          .s_axi4_bready (axi4_ct_bready[gen_hpu][gen_pc]   ),
          .s_axi4_arid   (axi4_ct_arid[gen_hpu][gen_pc]     ),
          .s_axi4_araddr (axi4_ct_araddr[gen_hpu][gen_pc]   ),
          .s_axi4_arlen  (axi4_ct_arlen[gen_hpu][gen_pc]    ),
          .s_axi4_arsize (axi4_ct_arsize[gen_hpu][gen_pc]   ),
          .s_axi4_arburst(axi4_ct_arburst[gen_hpu][gen_pc]  ),
          .s_axi4_arlock ('0), // disable
          .s_axi4_arcache('0), // disable
          .s_axi4_arprot ('0), // disable
          .s_axi4_arvalid(axi4_ct_arvalid[gen_hpu][gen_pc]  ),
          .s_axi4_arready(axi4_ct_arready[gen_hpu][gen_pc]  ),
          .s_axi4_rid    (axi4_ct_rid[gen_hpu][gen_pc]      ),
          .s_axi4_rdata  (axi4_ct_rdata[gen_hpu][gen_pc]    ),
          .s_axi4_rresp  (axi4_ct_rresp[gen_hpu][gen_pc]    ),
          .s_axi4_rlast  (axi4_ct_rlast[gen_hpu][gen_pc]    ),
          .s_axi4_rvalid (axi4_ct_rvalid[gen_hpu][gen_pc]   ),
          .s_axi4_rready (axi4_ct_rready[gen_hpu][gen_pc]   )
        );
      end
    end
  endgenerate

  int random_iter;
  // Signals --------------------------------------------------------------------------------------
  logic [REG_DATA_W-1:0] read_data;
  // must not bee too short, not too long
  logic [REG_DATA_W-1:0] timeout_size;

  // HPU-A and HPU-B node id will be set randomly and mandatorily different
  logic [HPU_ID_W-1:0] random_hpu_a;
  logic [HPU_ID_W-1:0] random_hpu_b;

  // IOP related signals
  logic [  IOP_ID_W-1:0] iop_id;
  logic [SRC_ADDR_W-1:0] iop_src_addr;
  logic [DST_ADDR_W-1:0] iop_dst_addr;

  // for checking
  logic [  REG_DATA_W-1:0] notify_payload;
  logic [  REG_DATA_W-1:0] expected_notify_payload;
  logic [MRMAC_AXIS_W-1:0] notify_payload_ref_q[$];

  logic [  REG_DATA_W-1:0] rr_payload;
  logic [  REG_DATA_W-1:0] rr_payload_expected;
  logic [MRMAC_AXIS_W-1:0] rr_payload_ref_q[$];

  // Fixed for now, might evolve later
  logic [SIZE_B_W-1:0] req_size_b;
  assign req_size_b = 'h4000;


  logic [DST_ADDR_W-1:0] received_address;
  logic [HPU_ID_W-1:0] received_hpu_id;
  logic [IOP_ID_W-1:0] received_iop_id;

  logic [31:0] regf_start_addr_ofs;

  int arbitrary_notify_nb;
  int arbitrary_read_req_nb;

  // scenario -------------------------------------------------------------------------------------
  initial begin
    maxil_drv_if_hpu_a.init();
    maxil_drv_if_hpu_b.init();

    reset_registers = 'h0;
    tx_loop         = 'h0;
    rx_to_tx        = 'h0;
    regf_start_addr_ofs = 'h0;
    repeat(20) @(posedge clk_control);

    /* In this scenario we must define theses test-cases :
     ==============================================================================================
     * - classical use:
     *                > X Notifies to Y that a ciphertext is ready
     *                > Y then reads this ciphertext
     *  -------------------------------------------------------------------------------------------
     * > we must see that the ciphertext moved from memory X to Y
     *  ===========================================================================================
     * - Piling requests:
     *                > X Notifies to Y that several ciphertexts are ready
     *                > Y then reads all ciphertexts
     *  -------------------------------------------------------------------------------------------
     * > all ciphertexts must have moved from memory X to Y
     *  ===========================================================================================
     * - Notfiy timeout
     *                > X Notifies to Y that a ciphertexts is ready
     *                > X doesn't receive the ack
     *  -------------------------------------------------------------------------------------------
     * > Does the timeout is triggered correctly and the Notify request resent properly ?
     *  ===========================================================================================
     * - Read request timeout #1
     *                > X does a read request to Y
     *                > no packets is then received
     *  -------------------------------------------------------------------------------------------
     * > Does the timeout is triggered correctly and the Read request resent properly ?
     *  ===========================================================================================
     * - Read request timeout #2
     *                > X does a read request to Y
     *                > a packet is lost
     *  -------------------------------------------------------------------------------------------
     * > Does the timeout is triggered correctly and the Read request resent properly ?
     */
    $display("\n\n"); // sperating from xpm fifo information

    // Initialization =============================================================================
    $display("A - Initial register check and definition");
    init_registers();

    // Defining MAC addresses for both instances of HPU -------------------------------------------
    write_mac_addresses();

    // TODO: add checker

    // Classical use-case =========================================================================
    random_iter = $urandom_range(32, 2);
    $display("\nB - Notification that a ciphertext is ready from one HPU to another, done %0d times", random_iter);

    for (int i = 0; i < random_iter; i++) begin
      // for now size_b is fixed, all our ciphertext are 16.384kB (size_b=0x4000)
      iop_id       = $urandom();
      iop_src_addr = $urandom_range(0, 1<<SRC_ADDR_W);
      iop_dst_addr = $urandom_range(0, 1<<DST_ADDR_W);

      repeat(100) @(posedge clk_control);
      // Sending a NOTIFY from HPU-B to HPU-A -------------------------------------------------------
      notify_request(random_hpu_b, random_hpu_a, iop_id, iop_src_addr);

      // if a Notify is received by HPU A we should be able to confirm it by reading in the regf
      notify_payload = {iop_src_addr, 4'b0, random_hpu_b, iop_id};

      wait (hpu_a.interrupt_notify == 1'b1);

      // Interrupt detected, checking Notify payload
      maxil_drv_if_hpu_a.read_trans(MHDMA_REQUEST_NOTIFY_OFS, read_data);

      assert (read_data == notify_payload) else begin
        $display("%t > [ERROR]: Payload DATA incorrect %x %x", $time, read_data, notify_payload);
        $display("%t > [ERROR]: iop_src_addr  = %x ", $time, iop_src_addr);
        $display("%t > [ERROR]: random_hpu_b  = %x ", $time, random_hpu_b);
        $display("%t > [ERROR]: iop_id        = %x ", $time, iop_id);

        error_notify_rx = 1'b1;
      end

      // TODO: check stats
      // maxil_drv_if_hpu_a.read_trans(MHDMA_REQUEST_STAT_NOTIFY_OFS, read_data);
      // $display("[INFO]: stat @HPU_A: how long data stayed before read? %x", read_data[15:0]);
      // maxil_drv_if_hpu_b.read_trans(MHDMA_REQUEST_STAT_NOTIFY_OFS, read_data);
      // $display("[INFO]: stat @HPU_B: how long acknowledge took? %x", read_data[31:16]);

      repeat(100) @(posedge clk_control);
      // Sending a read request from HPU-A to HPU-B -------------------------------------------------
      read_request(random_hpu_b, iop_id, iop_src_addr, iop_dst_addr);

      wait (hpu_a.interrupt_read_request == 1'b1);
      maxil_drv_if_hpu_a.read_trans(MHDMA_REQUEST_READ_REQUEST_OFS, read_data);

      received_address = read_data[31:16];
      received_hpu_id  = read_data[11:8];
      received_iop_id  = read_data[7:0];

      assert (read_data == {iop_dst_addr, 4'b0, random_hpu_b, iop_id}) else begin
        $display("%t > [ERROR]: Missmatch between expected and received read request payload on regif", $time);
        $display("%t > [ERROR]: address : %2x :: %2x", $time, received_address, iop_dst_addr);
        $display("%t > [ERROR]:  iop:id : %2x :: %2x", $time, received_iop_id, iop_id);
        $display("%t > [ERROR]:  hpu:id : %2x :: %2x", $time, received_hpu_id, random_hpu_b);
        error_rr_payload = 1'b1;
      end

      check_memories(iop_src_addr, iop_dst_addr);
    end

    // Piling notify requests =====================================================================
    arbitrary_notify_nb = XPM_MIN_FIFO_DEPTH; // if we have a full fifo on fifo_nrx_regf, we will lose notifies
    $display("\nC - Notification that a ciphertext is ready from one HPU to another, x %0d", arbitrary_notify_nb);

    for (int i = 0; i < arbitrary_notify_nb; i++) begin
      // for now size_b is fixed, all our ciphertext are 16.384kB (size_b=0x4000)
      iop_id       = $urandom();
      iop_src_addr = $urandom_range(0, 1<<SRC_ADDR_W);
      iop_dst_addr = $urandom_range(0, 1<<DST_ADDR_W);

      repeat(10) @(posedge clk_control);
      // Sending a NOTIFY from HPU-B to HPU-A -------------------------------------------------------
      notify_request(random_hpu_b, random_hpu_a, iop_id, iop_src_addr);

      // if a Notify is received by HPU A we should be able to confirm it by reading in the regf
      notify_payload = {iop_src_addr, 4'b0, random_hpu_b, iop_id};
      notify_payload_ref_q.push_front(notify_payload);
    end

    $display("%t > INFO : All %0d Notify have been sent from B to A \n", $time, arbitrary_notify_nb);

    for (int i = 0; i < arbitrary_notify_nb; i++) begin

      // we must wait for interrupt to be raised before reading
      wait (hpu_a.interrupt_notify == 1'b1);
      maxil_drv_if_hpu_a.read_trans(MHDMA_REQUEST_NOTIFY_OFS, read_data);
      expected_notify_payload = notify_payload_ref_q.pop_back();

      assert (read_data == expected_notify_payload) else begin
        $display("%t > [ERROR]: Payload DATA incorrect (received %x) =! (exp %x)", $time, read_data, expected_notify_payload);
        $display("%t > [ERROR]: iop_src_addr  = %x ", $time, iop_src_addr);
        $display("%t > [ERROR]: random_hpu_b  = %x ", $time, random_hpu_b);
        $display("%t > [ERROR]: iop_id        = %x ", $time, iop_id);
        error_notify_rx = 1'b1;
      end
    end

    @(posedge clk_control);
    if (hpu_a.interrupt_notify == 1'b1) begin
      $display("%t > [ERROR]: Interrupt on HPU_A has not been lowered\n",$time);
      error_interrupt_notify = 1'b1;
    end

    // Piling read requests =====================================================================
    arbitrary_read_req_nb = XPM_MIN_FIFO_DEPTH;
    $display("\nD - read request from one HPU to another, x %0d times", arbitrary_notify_nb);

    for (int i = 0; i < arbitrary_read_req_nb; i ++) begin
      iop_id       = i;//$urandom();
      iop_src_addr = 0;//$urandom_range(0, 1<<SRC_ADDR_W);
      iop_dst_addr = 0;//$urandom_range(0, 1<<DST_ADDR_W);
      read_request(random_hpu_b, iop_id, iop_src_addr, iop_dst_addr);

      rr_payload = {iop_dst_addr, 4'b0, random_hpu_b, iop_id};
      rr_payload_ref_q.push_front(rr_payload);
      // TODO: toreview if we send a read request before we did actually the read request we loose data
      wait (hpu_a.mhdma_bridge.mhdma_master.itr_read_request == 1'b1);
    end

    for (int i = 0; i < arbitrary_read_req_nb; i++) begin
      // we must wait for interrupt to be raised before reading
      wait (hpu_a.interrupt_read_request == 1'b1);
      maxil_drv_if_hpu_a.read_trans(MHDMA_REQUEST_READ_REQUEST_OFS, read_data);
      rr_payload_expected = rr_payload_ref_q.pop_back();

      assert (read_data == rr_payload_expected) else begin
        $display("%t > [ERROR]: Payload DATA incorrect (received %x) =! (exp %x)", $time, read_data, rr_payload_expected);
        $display("%t > [ERROR]: iop_dst_addr  = %x ", $time, iop_dst_addr);
        $display("%t > [ERROR]: random_hpu_b  = %x ", $time, random_hpu_b);
        $display("%t > [ERROR]: iop_id        = %x ", $time, iop_id);
        error_notify_rx = 1'b1;
      end
    end

    $display("%t > INFO : All %0d read request have been sent \n",$time, arbitrary_read_req_nb);

    $display("%t > INFO: End simulation",$time);
    repeat(20) @(posedge clk_control);
    end_of_test = 1'b1;
  end

// ============================================================================================== --
// Initialize memory
// ============================================================================================== --
  logic [59:0] val_id = 0;

  initial begin
    // for (int gen_hpu = 0; gen_hpu < HPU_NB; ++gen_hpu) begin
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
          // TODO: why this don't work?
          // gen_mem_hpu[gen_hpu].gen_mem_pc[gen_pc].axi4_mem_ct.axi4_ram_ct_wr.mem[k] = value;
          gen_mem_hpu[1].gen_mem_pc[0].axi4_mem_ct.axi4_ram_ct_wr.mem[k] = value;
          gen_mem_hpu[1].gen_mem_pc[1].axi4_mem_ct.axi4_ram_ct_wr.mem[k] = value;
        end
      end
      for (int gen_pc = 0; gen_pc < ETH_PC; ++gen_pc) begin
        for (int k = 0; k < 2**MEM_SIM_SIZE; ++k) begin
          gen_mem_hpu[0].gen_mem_pc[0].axi4_mem_ct.axi4_ram_ct_wr.mem[k] = 'h0;
          gen_mem_hpu[0].gen_mem_pc[1].axi4_mem_ct.axi4_ram_ct_wr.mem[k] = 'h0;
      end
      end
    // end
  end

// ============================================================================================== --
// Tasks
// ============================================================================================== --
  logic [REG_DATA_W-1:00] rdata;

  task automatic init_registers;
    begin
    // Reading system REGISTERS -------------------------------------------------------------------
      maxil_drv_if_hpu_a.read_trans(MHDMA_SYSTEM_LANE_OFS, rdata);
      assert (rdata == 'h0) else begin
        $display("%t > ERROR:register SYSTEM_LINE_OFS not correctly read %h",$time, rdata);
        error_register_read = 1'b1;
      end

    // ASSIGN REGISTERS & CHECK -------------------------------------------------------------------
    line_rate     = 8'hAB;  // random, no idea what it should be
    line_loopback = 3'b100; // 3 near end pcs loopback
    line_select   = 2'b10;  // 2nd line selected
    debug_flag    = 1'b0;
    @(posedge clk_control);

    maxil_drv_if_hpu_a.write_trans(MHDMA_SYSTEM_LANE_OFS, line_parameter);
    maxil_drv_if_hpu_b.write_trans(MHDMA_SYSTEM_LANE_OFS, line_parameter);

    rst_rx_datapath = 4'b0100;
    rst_tx_datapath = 4'b1011;
    rst_all         = 4'b0101;
    @(posedge clk_control);

    maxil_drv_if_hpu_a.write_trans(MHDMA_RESET_DATAPATH_OFS, reset_parameter);
    maxil_drv_if_hpu_b.write_trans(MHDMA_RESET_DATAPATH_OFS, reset_parameter);

    assert ((gt_line_rate[0] == line_rate) && (gt_line_rate[1] == line_rate)) else begin
      $display("[ERROR] line_rate has unexpected value %x %x %x",gt_line_rate[0], gt_line_rate[1], line_rate);
      error_register_read = 1;
    end
    assert ((gt_loopback[0] ==line_loopback) && (gt_loopback[1] == line_loopback)) else begin
      $display("[ERROR] gt_loopback has unexpected value");
      error_register_read = 1;
    end
    assert ((hpu_a.line_sel == line_select) &&  (hpu_b.line_sel == line_select)) else begin
      $display("[ERROR] line_sel has unexpected value");
      error_register_read = 1;
    end

    for (int i = 0; i<2; i++) begin
      assert ((gt_reset_rx_datapath[i] == rst_rx_datapath) && (gt_reset_tx_datapath[i] == rst_tx_datapath) && (gt_reset_all[i] == rst_all)) else begin
        $display("%t >    ERROR: reset configuration has not been applied correctly",$time);
        error_register_read = 1'b1;
      end
    end

    // read reset register ------------------------------------------------------------------------
    // fake stimulation
    for (int i = 0; i<2; i++) begin
      gt_rx_reset_done[i]= 4'b1111;
      gt_tx_reset_done[i]= 4'b1111;
    end
    @(posedge clk_control);

    maxil_drv_if_hpu_a.read_trans(MHDMA_RESET_MONITOR_OFS, reset_monitor[0]);
    maxil_drv_if_hpu_b.read_trans(MHDMA_RESET_MONITOR_OFS, reset_monitor[1]);

    assert ((reset_monitor[3:0] != gt_tx_reset_done) | (reset_monitor[7:4] != gt_rx_reset_done)) else begin
      $display("[ERROR] reset monitor has not been read correctly");
      error_register_read = 1'b1;
    end

    // Setting timeout size to both HPUs ----------------------------------------------------------
    // keeping default value

    // Setting up credible values -------------------------------------------------------------
    // no loopback, no reset, not in debug lane0 selected
    line_rate     = 8'h0;
    line_loopback = 3'b000;
    line_select   = 2'b00;
    debug_flag    = 1'b0;
    rst_rx_datapath = 4'b0000;
    rst_tx_datapath = 4'b0000;
    rst_all         = 4'b0000;
    @(posedge clk_control);

    $display("%t > INFO: Configuration successful\n",$time);
    end
  endtask

  /* Performs writes to according registers to define all possible MAC addresses
   *  - HPU-A and HPU-B are random and different at each runs
   *  - We have at most 8 HPUs: we will write them all
   */
  task automatic write_mac_addresses();
    logic [ MAC_ADDR_W-1:0] mac_addr;
    logic [   HPU_ID_W-1:0] hpu_id;
    logic                   hpu_current;
    logic [REG_DATA_W-1:00] register_mac_addr_a;
    logic [REG_DATA_W-1:00] register_mac_addr_b;
    begin
      random_hpu_a = $urandom_range(7, 0);

      // let's avoid saying that we are the same HPU
      do begin
        random_hpu_b = $urandom_range(7, 0);
      end while (random_hpu_b == random_hpu_a);

      $display("┌------------------------┐");
      $display("| For this run....       |");
      $display("| ---------------------- |");
      $display("| HPU_A:id=%d            |", random_hpu_a);
      $display("| HPU_B:id=%d            |", random_hpu_b);
      $display("| ---------------------- |");
      for (int i = 0 ; i < 8 ; i++ ) begin
        mac_addr = $urandom();
        hpu_id = i;

        if(i == random_hpu_a) begin
          register_mac_addr_a = {1'b1, 3'b000, hpu_id, mac_addr};
        end else begin
          register_mac_addr_a = {1'b0, 3'b000, hpu_id, mac_addr};
        end

        if(i == random_hpu_b) begin
          register_mac_addr_b = {1'b1, 3'b000, hpu_id, mac_addr};
        end else begin
          register_mac_addr_b = {1'b0, 3'b000, hpu_id, mac_addr};
        end

        $display("| HPU_ID=%0d :: MAC=%6x |", i, mac_addr);
        maxil_drv_if_hpu_a.write_trans(MHDMA_HPU_ID_ZERO_OFS+(4*i), register_mac_addr_a);
        maxil_drv_if_hpu_b.write_trans(MHDMA_HPU_ID_ZERO_OFS+(4*i), register_mac_addr_b);
      end
      $display("└------------------------┘");

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
    logic [REG_DATA_W-1:00] read_req_id;
    logic [REG_DATA_W-1:00] read_req_addr;
    begin
      // see package
      read_req_addr = {dest_addr, src_addr};
      read_req_id = {iop_id, REQ_ID_READ, node_id, req_size_b};

      maxil_drv_if_hpu_a.write_trans(MHDMA_REQUEST_REQ_ADDR_OFS, read_req_addr);
      maxil_drv_if_hpu_a.write_trans(MHDMA_REQUEST_REQ_ID_OFS, read_req_id);
      // there is as well the hbm pc offsets to write from RPU pov but in simulation we let it set to 0
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

      read_req_addr = {16'b0, src_addr}; //TODO
      read_req_id = {iop_id, REQ_ID_NOTIFY_TX, dst_node_id, req_size_b};

      if (src_node_id == random_hpu_a) begin
        maxil_drv_if_hpu_a.write_trans(MHDMA_REQUEST_REQ_ADDR_OFS, read_req_addr);
        maxil_drv_if_hpu_a.write_trans(MHDMA_REQUEST_REQ_ID_OFS, read_req_id);
      end else if (src_node_id == random_hpu_b) begin
        maxil_drv_if_hpu_b.write_trans(MHDMA_REQUEST_REQ_ADDR_OFS, read_req_addr);
        maxil_drv_if_hpu_b.write_trans(MHDMA_REQUEST_REQ_ID_OFS, read_req_id);
      end else begin
        $display("[ERROR] you are trying to send a Notify request from an HPU non instantiated");
        error_tb_notify = 1'b1;
      end

    end
  endtask

// ============================================================================================== --
// Checker
// ============================================================================================== --
  /* Checker
  * memory content should be the same between HPU_A and HPU_B for PC_0 and PC_1
  * assumption: we chose in this test to do read request from HPU A to B
  * anything can be in HPU B memory. on HPU A we have only the copied values of hpu B
  */
  task automatic check_memories(
    input logic [SRC_ADDR_W-1:0] src_addr,
    input logic [DST_ADDR_W-1:0] dst_addr
  );
    int addr_hpu_0;
    int addr_hpu_1;
    logic mismatch_found;
    begin
      mismatch_found = 1'b0;

      // PC 0
      addr_hpu_0 = regf_start_addr_ofs + ((dst_addr << PC_STRIDE))/32 ; // where copied word should be
      addr_hpu_1 = regf_start_addr_ofs + ((src_addr << PC_STRIDE))/32 ;

      $display("addr_hpu_0 = %x", addr_hpu_0);
      $display("addr_hpu_1 = %x", addr_hpu_1);

      // Direct comparison of memory locations
      for (int k = 0; k < gen_localparam[0].PC_NB_WORDS; k++) begin

        // I read from 0 to PC_NB_WORDS in HPU_B and
        if (gen_mem_hpu[0].gen_mem_pc[0].axi4_mem_ct.axi4_ram_ct_wr.mem[addr_hpu_0 + k] != gen_mem_hpu[1].gen_mem_pc[0].axi4_mem_ct.axi4_ram_ct_wr.mem[addr_hpu_1 + k]) begin
          $display("Memory mismatch at PC=%0d, offset=%0d: HPU_0[%0d]=%0h != HPU_1[%0d]=%0h", 0, k,
                    addr_hpu_0 + k, gen_mem_hpu[0].gen_mem_pc[0].axi4_mem_ct.axi4_ram_ct_wr.mem[addr_hpu_0 + k],
                    addr_hpu_1 + k, gen_mem_hpu[1].gen_mem_pc[0].axi4_mem_ct.axi4_ram_ct_wr.mem[addr_hpu_1 + k]);
          mismatch_found = 1;
          error_write_missmatch = 1'b1;
        end
      end
      // PC 1
      // Direct comparison of memory locations
      for (int k = 0; k < gen_localparam[1].PC_NB_WORDS; k++) begin

        // I read from 0 to PC_NB_WORDS in HPU_B and
        if (gen_mem_hpu[0].gen_mem_pc[1].axi4_mem_ct.axi4_ram_ct_wr.mem[addr_hpu_0 + k] != gen_mem_hpu[1].gen_mem_pc[1].axi4_mem_ct.axi4_ram_ct_wr.mem[addr_hpu_1 + k]) begin
          $display("Memory mismatch at PC=%0d, offset=%0d: HPU_0[%0d]=%0h != HPU_1[%0d]=%0h", 1, k,
                    addr_hpu_0 + k, gen_mem_hpu[0].gen_mem_pc[1].axi4_mem_ct.axi4_ram_ct_wr.mem[addr_hpu_0 + k],
                    addr_hpu_1 + k, gen_mem_hpu[1].gen_mem_pc[1].axi4_mem_ct.axi4_ram_ct_wr.mem[addr_hpu_1 + k]);
          mismatch_found = 1;
          error_write_missmatch = 1'b1;
        end
      end

      if (~mismatch_found)
        $display("[INFO]: Memory check PASSED: HPU_A and HPU_B contents match");
    end
  endtask

endmodule
