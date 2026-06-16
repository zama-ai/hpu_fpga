// ================================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ------------------------------------------------------------------------------------------------
// Description  : Testbench for testing interlacing of Notify during a CE on multi-HPU DMA.
//
// NOTE: It is important to read notify and read request words otherwise this test gets stuck
//
// ================================================================================================

`resetall
`timescale 1ns/10ps
module tb_mhdma_notify_insertion;
  import mhdma_pkg::*;                    // multi-hpu-dma
  import axi_if_shell_axil_pkg::*;        // axi4-lite + REG_DATA_W
  import axi_if_common_param_pkg::*;      // general axi4
  import hpu_regif_core_mhdma_2in3_pkg::*;  // ethernet regif
  import axi_if_mhdma_axi_pkg::*;           // AXI ethernet
  import pem_common_param_pkg::*;         // CT_MEM_BYTES, AXI4_WORD_PER_PC*

  `include "tb_mhdma_tasks.sv"

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int CLK_HALF_PERIOD_A = 4;
  localparam int CLK_HALF_PERIOD_B = 1;
  localparam int ARST_ACTIVATION = 17;

  localparam int FIFO_DEPTH = 512;

  localparam int HPU_NB = 1; // in this test we will try to connect two mhdma (or HPUs)

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
  localparam int RFM_SIM      = 'h0;

  localparam int MAX_BURST_SIZE  = PAGE_BYTES/AXI4_DATA_BYTES;

  localparam int TOTAL_NB_PACKETS = $ceil(CT_NB_COEF / NB_WORDS_PAYLOAD) + 1;

  // Timeout guard: maximum cycles before declaring failure
  // otherworise tis testbench can run forever
  localparam int TIMEOUT_CYCLES = 5_000_000;

// ============================================================================================== --
// clock, reset
// ============================================================================================== --
  bit clk_control;
  bit clk_mhdma;

  initial begin
    clk_control = 1'b0;
    clk_mhdma = 1'b0;
  end

  always begin
    #CLK_HALF_PERIOD_A clk_control = ~clk_control;
  end
  always begin
    #CLK_HALF_PERIOD_B clk_mhdma = ~clk_mhdma;
  end

  bit a_rst_n; // asynchronous reset
  bit s_rstn_control; // synchronous reset
  bit s_rstn_mhdma; // synchronous reset

  initial begin
    a_rst_n = 1'b0;                  // active reset
    #ARST_ACTIVATION a_rst_n = 1'b1; // disable reset
  end

  always_ff @(posedge clk_control) begin
    s_rstn_control <= a_rst_n;
  end
  always_ff @(posedge clk_mhdma) begin
    s_rstn_mhdma <= a_rst_n;
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
  bit error_interrupt;

  assign error = error_ack | error_retry | error_tb_notify | error_register_read | error_fsm | error_interrupt;

  always_ff @(posedge clk_control)
    if (error) begin
      $display("%t > FAILURE !", $time);
      $finish;
    end

  // Timeout watchdog
  initial begin
    repeat (TIMEOUT_CYCLES) @(posedge  clk_mhdma);
    $display("%t > FAILURE: timeout reached !", $time);
    $finish;
  end

// ============================================================================================== --
// input / output signals
// ============================================================================================== --
  logic [MRMAC_AXIS_W-1:0]               unused_payload [$];

  logic [AXIL_ADD_W-1:0]                  s_axil_mhdma_awaddr;
  logic                                   s_axil_mhdma_awvalid;
  logic                                   s_axil_mhdma_awready;
  logic [AXIL_DATA_W-1:0]                 s_axil_mhdma_wdata;
  logic [AXIL_DATA_BYTES-1:0]             s_axil_mhdma_wstrb; /* UNUSED */
  logic                                   s_axil_mhdma_wvalid;
  logic                                   s_axil_mhdma_wready;
  logic [1:0]                             s_axil_mhdma_bresp;
  logic                                   s_axil_mhdma_bvalid;
  logic                                   s_axil_mhdma_bready;
  logic [AXIL_ADD_W-1:0]                  s_axil_mhdma_araddr;
  logic                                   s_axil_mhdma_arvalid;
  logic                                   s_axil_mhdma_arready;
  logic [AXIL_DATA_W-1:0]                 s_axil_mhdma_rdata;
  logic [1:0]                             s_axil_mhdma_rresp;
  logic                                   s_axil_mhdma_rvalid;
  logic                                   s_axil_mhdma_rready;

  // Interrupt interface
  logic                                   interrupt_notify;
  logic                                   interrupt_read_request;

  // AXI4 to HBM: HPUA (single NMU) ----------------------------------------------------------------
  logic [AXI4_ID_W-1:0]       axi4_ct_awid;
  logic [AXI4_ADD_W-1:0]      axi4_ct_awaddr;
  logic [7:0]                 axi4_ct_awlen;
  logic [2:0]                 axi4_ct_awsize;
  logic [1:0]                 axi4_ct_awburst;
  logic                       axi4_ct_awvalid;
  logic                       axi4_ct_awready;
  logic [AXI4_DATA_W-1:0]     axi4_ct_wdata;
  logic [(AXI4_DATA_W/8)-1:0] axi4_ct_wstrb;
  logic                       axi4_ct_wlast;
  logic                       axi4_ct_wvalid;
  logic                       axi4_ct_wready;
  logic [AXI4_ID_W-1:0]       axi4_ct_bid;
  logic [1:0]                 axi4_ct_bresp;
  logic                       axi4_ct_bvalid;
  logic                       axi4_ct_bready;

  logic [AXI4_ID_W-1:0]       axi4_ct_arid;
  logic [AXI4_ADD_W-1:0]      axi4_ct_araddr;
  logic [7:0]                 axi4_ct_arlen;
  logic [2:0]                 axi4_ct_arsize;
  logic [1:0]                 axi4_ct_arburst;
  logic                       axi4_ct_arvalid;
  logic                       axi4_ct_arready;
  logic [AXI4_ID_W-1:0]       axi4_ct_rid;
  logic [AXI4_DATA_W-1:0]     axi4_ct_rdata;
  logic [1:0]                 axi4_ct_rresp;
  logic                       axi4_ct_rlast;
  logic                       axi4_ct_rvalid;
  logic                       axi4_ct_rready;

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
  qsfp_if qsfp_rx_vif[QSFP_LANE_NB] (clk_mhdma);

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
  multi_hpu_dma multi_hpu_dma (
    .clk_mhdma_cfg            (clk_control                ),
    .resetn_mhdma_cfg         (s_rstn_control             ),

    .clk_mhdma          (clk_mhdma                  ),
    .resetn_mhdma       (s_rstn_mhdma               ),

    .s_axil_mhdma_awaddr      (s_axil_mhdma_awaddr          ),
    .s_axil_mhdma_awvalid     (s_axil_mhdma_awvalid         ),
    .s_axil_mhdma_awready     (s_axil_mhdma_awready         ),
    .s_axil_mhdma_wdata       (s_axil_mhdma_wdata           ),
    .s_axil_mhdma_wstrb       (s_axil_mhdma_wstrb           ),
    .s_axil_mhdma_wvalid      (s_axil_mhdma_wvalid          ),
    .s_axil_mhdma_wready      (s_axil_mhdma_wready          ),
    .s_axil_mhdma_bresp       (s_axil_mhdma_bresp           ),
    .s_axil_mhdma_bvalid      (s_axil_mhdma_bvalid          ),
    .s_axil_mhdma_bready      (s_axil_mhdma_bready          ),
    .s_axil_mhdma_araddr      (s_axil_mhdma_araddr          ),
    .s_axil_mhdma_arvalid     (s_axil_mhdma_arvalid         ),
    .s_axil_mhdma_arready     (s_axil_mhdma_arready         ),
    .s_axil_mhdma_rdata       (s_axil_mhdma_rdata           ),
    .s_axil_mhdma_rresp       (s_axil_mhdma_rresp           ),
    .s_axil_mhdma_rvalid      (s_axil_mhdma_rvalid          ),
    .s_axil_mhdma_rready      (s_axil_mhdma_rready          ),

    .m_axi4_mhdma_hbm_arid    (axi4_ct_arid               ),
    .m_axi4_mhdma_hbm_araddr  (axi4_ct_araddr             ),
    .m_axi4_mhdma_hbm_arlen   (axi4_ct_arlen              ),
    .m_axi4_mhdma_hbm_arsize  (axi4_ct_arsize             ),
    .m_axi4_mhdma_hbm_arburst (axi4_ct_arburst            ),
    .m_axi4_mhdma_hbm_arvalid (axi4_ct_arvalid            ),
    .m_axi4_mhdma_hbm_arready (axi4_ct_arready            ),
    .m_axi4_mhdma_hbm_rid     (axi4_ct_rid                ),
    .m_axi4_mhdma_hbm_rdata   (axi4_ct_rdata              ),
    .m_axi4_mhdma_hbm_rresp   (axi4_ct_rresp              ),
    .m_axi4_mhdma_hbm_rlast   (axi4_ct_rlast              ),
    .m_axi4_mhdma_hbm_rvalid  (axi4_ct_rvalid             ),
    .m_axi4_mhdma_hbm_rready  (axi4_ct_rready             ),
    .m_axi4_mhdma_hbm_awid    (axi4_ct_awid               ),
    .m_axi4_mhdma_hbm_awaddr  (axi4_ct_awaddr             ),
    .m_axi4_mhdma_hbm_awlen   (axi4_ct_awlen              ),
    .m_axi4_mhdma_hbm_awsize  (axi4_ct_awsize             ),
    .m_axi4_mhdma_hbm_awburst (axi4_ct_awburst            ),
    .m_axi4_mhdma_hbm_awvalid (axi4_ct_awvalid            ),
    .m_axi4_mhdma_hbm_awready (axi4_ct_awready            ),
    .m_axi4_mhdma_hbm_wdata   (axi4_ct_wdata              ),
    .m_axi4_mhdma_hbm_wstrb   (axi4_ct_wstrb              ),
    .m_axi4_mhdma_hbm_wlast   (axi4_ct_wlast              ),
    .m_axi4_mhdma_hbm_wvalid  (axi4_ct_wvalid             ),
    .m_axi4_mhdma_hbm_wready  (axi4_ct_wready             ),
    .m_axi4_mhdma_hbm_bid     (axi4_ct_bid                ),
    .m_axi4_mhdma_hbm_bresp   (axi4_ct_bresp              ),
    .m_axi4_mhdma_hbm_bvalid  (axi4_ct_bvalid             ),
    .m_axi4_mhdma_hbm_bready  (axi4_ct_bready             ),

    .qsfp_tx_tdata          (qsfp_tx_tdata              ),
    .qsfp_tx_tkeep_user     (qsfp_tx_tkeep_user         ),
    .qsfp_tx_tlast          (qsfp_tx_tlast              ),
    .qsfp_tx_tvalid         (qsfp_tx_tvalid             ),
    .qsfp_tx_tready         (qsfp_tx_tready             ),

    .qsfp_rx_tdata          (qsfp_rx_tdata_delayed      ),
    .qsfp_rx_tkeep_user     (qsfp_rx_tkeep_user_delayed ),
    .qsfp_rx_tlast          (qsfp_rx_tlast_delayed      ),
    .qsfp_rx_tvalid         (qsfp_rx_tvalid_delayed     ),

    .interrupt_notify       (interrupt_notify           ),
    .interrupt_read_request (interrupt_read_request     ),

    .gt_line_rate           (gt_line_rate               ),
    .gt_loopback            (gt_loopback                ),
    .gt_reset_rx_datapath   (gt_reset_rx_datapath       ),
    .gt_reset_tx_datapath   (gt_reset_tx_datapath       ),
    .gt_reset_all           (gt_reset_all               ),
    .gt_rx_reset_done       (gt_rx_reset_done           ),
    .gt_tx_reset_done       (gt_tx_reset_done           )
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
logic [REG_DATA_W-1:0] stat_errors;

logic [SRC_ADDR_W-1:0] iop_src_addr;
logic [DST_ADDR_W-1:0] iop_dst_addr;
logic [FLAG_W-1:0]     flag;
logic [MODE_W-1:0]     mode;
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
  assign s_axil_mhdma_awaddr  = maxil_drv_if.awaddr;
  assign s_axil_mhdma_awvalid = maxil_drv_if.awvalid;
  assign s_axil_mhdma_wdata   = maxil_drv_if.wdata;
  assign s_axil_mhdma_wstrb   = maxil_drv_if.wstrb;
  assign s_axil_mhdma_wvalid  = maxil_drv_if.wvalid;
  assign s_axil_mhdma_bready  = maxil_drv_if.bready;
  assign s_axil_mhdma_araddr  = maxil_drv_if.araddr;
  assign s_axil_mhdma_arvalid = maxil_drv_if.arvalid;
  assign s_axil_mhdma_rready  = maxil_drv_if.rready;

  assign maxil_drv_if.awready = s_axil_mhdma_awready;
  assign maxil_drv_if.wready  = s_axil_mhdma_wready;
  assign maxil_drv_if.bresp   = s_axil_mhdma_bresp;
  assign maxil_drv_if.bvalid  = s_axil_mhdma_bvalid;
  assign maxil_drv_if.arready = s_axil_mhdma_arready;
  assign maxil_drv_if.rdata   = s_axil_mhdma_rdata;
  assign maxil_drv_if.rresp   = s_axil_mhdma_rresp;
  assign maxil_drv_if.rvalid  = s_axil_mhdma_rvalid;

  axi4_mem #(
    .DATA_WIDTH       (AXI4_DATA_W                     ),
    .ADDR_WIDTH       (MEM_SIM_SIZE                    ),
    .ID_WIDTH         (AXI4_ID_W                       ),
    .WR_CMD_BUF_DEPTH (MEM_WR_CMD_BUF_DEPTH            ),
    .RD_CMD_BUF_DEPTH (MEM_RD_CMD_BUF_DEPTH            ),
    .WR_DATA_LATENCY  (MEM_WR_DATA_LATENCY             ),
    .RD_DATA_LATENCY  (MEM_RD_DATA_LATENCY             ),
    .USE_WR_RANDOM    (MEM_USE_WR_RANDOM               ),
    .USE_RD_RANDOM    (MEM_USE_RD_RANDOM               )
  ) axi4_mem_ct (
    .clk              (clk_mhdma                       ),
    .rst              (~s_rstn_mhdma                   ),
    .s_axi4_awid      (axi4_ct_awid                    ),
    .s_axi4_awaddr    (axi4_ct_awaddr[MEM_SIM_SIZE-1:0]),
    .s_axi4_awlen     (axi4_ct_awlen                   ),
    .s_axi4_awsize    (axi4_ct_awsize                  ),
    .s_axi4_awburst   (axi4_ct_awburst                 ),
    .s_axi4_awlock    (/* UNUSED */                    ),
    .s_axi4_awcache   (/* UNUSED */                    ),
    .s_axi4_awprot    (/* UNUSED */                    ),
    .s_axi4_awqos     (/* UNUSED */                    ),
    .s_axi4_awregion  (/* UNUSED */                    ),
    .s_axi4_awvalid   (axi4_ct_awvalid                 ),
    .s_axi4_awready   (axi4_ct_awready                 ),
    .s_axi4_wdata     (axi4_ct_wdata                   ),
    .s_axi4_wstrb     (axi4_ct_wstrb                   ),
    .s_axi4_wlast     (axi4_ct_wlast                   ),
    .s_axi4_wvalid    (axi4_ct_wvalid                  ),
    .s_axi4_wready    (axi4_ct_wready                  ),
    .s_axi4_bid       (axi4_ct_bid                     ),
    .s_axi4_bresp     (axi4_ct_bresp                   ),
    .s_axi4_bvalid    (axi4_ct_bvalid                  ),
    .s_axi4_bready    (axi4_ct_bready                  ),
    .s_axi4_arid      (axi4_ct_arid                    ),
    .s_axi4_araddr    (axi4_ct_araddr[MEM_SIM_SIZE-1:0]),
    .s_axi4_arlen     (axi4_ct_arlen                   ),
    .s_axi4_arsize    (axi4_ct_arsize                  ),
    .s_axi4_arburst   (axi4_ct_arburst                 ),
    .s_axi4_arlock    (/* UNUSED */                    ),
    .s_axi4_arcache   (/* UNUSED */                    ),
    .s_axi4_arprot    (/* UNUSED */                    ),
    .s_axi4_arqos     (/* UNUSED */                    ),
    .s_axi4_arregion  (/* UNUSED */                    ),
    .s_axi4_arvalid   (axi4_ct_arvalid                 ),
    .s_axi4_arready   (axi4_ct_arready                 ),
    .s_axi4_rid       (axi4_ct_rid                     ),
    .s_axi4_rdata     (axi4_ct_rdata                   ),
    .s_axi4_rresp     (axi4_ct_rresp                   ),
    .s_axi4_rlast     (axi4_ct_rlast                   ),
    .s_axi4_rvalid    (axi4_ct_rvalid                  ),
    .s_axi4_rready    (axi4_ct_rready                  )
  );

  // Initialize memory
  initial begin
    for (int k = 0; k < 2**MEM_SIM_SIZE; k++) begin
      logic [AXI4_DATA_W-1:0] value;
      value = '0;
      for (int j = 0; j < AXI4_DATA_W/64; j++) begin
        logic [63:0] w;
        w[63:32] = $urandom();
        w[31:0]  = $urandom();
        value |= (w << (j*64));
      end
      axi4_mem_ct.axi4_ram_ct_wr.mem[k] = value;
    end
  end

  // Decoder --------------------------------------------------------------------------------------
  // Decoder now exposes two role-split command streams; merge them back into a single rx_header
  // view and drain both queues (slave-role shown first; READ/NOTIFY live there).
  command_t rx_header_master;
  logic     rx_header_master_vld;
  logic     rx_header_master_rdy;

  command_t rx_header_slave;
  logic     rx_header_slave_vld;
  logic     rx_header_slave_rdy;

  command_t rx_header;
  logic     rx_header_vld;
  logic     rx_header_rdy;
  logic notify_ack_received;

  assign rx_header            = rx_header_slave_vld ? rx_header_slave : rx_header_master;
  assign rx_header_vld        = rx_header_slave_vld | rx_header_master_vld;
  assign rx_header_slave_rdy  = rx_header_rdy &  rx_header_slave_vld;
  assign rx_header_master_rdy = rx_header_rdy & ~rx_header_slave_vld;

  // this is supposed to be HPU_B decoder
  mhdma_decoder mhdma_decoder (
    .clk_mhdma                  (clk_mhdma               ),
    .resetn_mhdma               (s_rstn_mhdma            ),

    .notify_ack_received        (notify_ack_received     ),
    .current_hpu_mac            (src_mac_addr            ),

    .decoded_command_master     (rx_header_master        ),
    .decoded_command_master_vld (rx_header_master_vld    ),
    .decoded_command_master_rdy (rx_header_master_rdy    ),
    .decoded_command_slave      (rx_header_slave         ),
    .decoded_command_slave_vld  (rx_header_slave_vld     ),
    .decoded_command_slave_rdy  (rx_header_slave_rdy     ),

    .rx_tdata_out               (/*    unused          */),
    .rx_tvalid_out              (/*    unused          */),

    // stats are completely ignored here
    .stat                       (/*    unused          */),
    .stat_rst                   (/*    unused          */),

    .decoder_error              (/*    unused          */),
    .rst_errors                 (/*    unused          */),

    // only one lane is used in this tb
    .qsfp_rx_tdata              (qsfp_tx_tdata[lane]     ),
    .qsfp_rx_tkeep_user         (qsfp_tx_tkeep_user[lane]),
    .qsfp_rx_tlast              (qsfp_tx_tlast[lane]     ),
    .qsfp_rx_tvalid             (qsfp_tx_tvalid[lane]    )
  );

  always_ff @(posedge clk_mhdma)
   rx_header_rdy <= ($urandom() % 100 < 50);

  // scenario -------------------------------------------------------------------------------------
  logic [HPU_ID_W-1:0]   target_hpu;
  logic [MAC_ADDR_W-1:0] target_mac_addr;
  logic [REG_DATA_W-1:0] rdata;

  int random_insersion;
  int random_iterations;

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

    random_iterations = $urandom_range(100, 500);

    for (int i = 0; i < random_iterations; i++) begin
      random_insersion = $urandom_range(1, NB_PACKETS_FULL);
      $display("\n==================================================================================================");
      $display("  Scenario %0d: During CE, at packet %0d we inset a Notify", i, random_insersion);
      $display("==================================================================================================");
      // Only one scenario here:
      // We need to check if whether receiving a notify during a ciphertext emission breaks the system
      // MHDMA must :
      //  - Respond Notify with an ack during CE reception
      //  - CE reception must end correctly after being interrupted by Notifies
      // We will do standalones CE & Notify to check that the module does dont gets blocked

      target_hpu = 4'h0;
      target_mac_addr = dst_mac_addr;

      randomize_command_fields(target_hpu, src_hpu_id, iop_id, iop_src_addr, iop_dst_addr, flag, mode);

      read_request(4'h1, iop_id, iop_src_addr, iop_dst_addr, flag, mode);

      fork
      begin
        for (int pkt = 0; pkt < random_insersion; pkt++) begin
          send_ciphertext_emission_packet(qsfp_rx_vif[0], src_mac_addr, target_mac_addr, src_hpu_id, iop_id, iop_src_addr, iop_dst_addr, pkt[7:0], unused_payload);
          repeat(10) @(posedge clk_mhdma);
        end

        // Notify insersion
        send_notify_packet(qsfp_rx_vif[0], src_mac_addr, target_mac_addr, target_hpu, iop_id, iop_src_addr, flag, mode);

        for (int pkt = random_insersion; pkt < NB_PACKETS_FULL+1; pkt++) begin
          send_ciphertext_emission_packet(qsfp_rx_vif[0], src_mac_addr, target_mac_addr, src_hpu_id, iop_id, iop_src_addr, iop_dst_addr, pkt[7:0], unused_payload);
          repeat(10) @(posedge clk_mhdma);
        end
      end

      begin
        wait(notify_ack_received);
        $display("[INFO]: Notify ACK received from DUT!");
        // Drain fifo_nrx_regf: read the Notify register to clear the interrupt
        wait(interrupt_notify);
        maxil_drv_if.read_trans(MHDMA_REQUEST_NOTIFY_REQ_ID_OFS, rdata);
      end

      begin
        wait(multi_hpu_dma.mhdma_bridge.mhdma_master.ciphertext_received);
        $display("[INFO]: Ciphertext correctly processed on module!");
        // Drain fifo_rr_regf: read the Read Request register to clear the interrupt
        wait(interrupt_read_request);
        maxil_drv_if.read_trans(MHDMA_REQUEST_READ_REQUEST_REQ_ID_OFS, rdata);
      end

      join


      $display("[INFO] Checking that standalone RR ends correctly after notify packet insersion");

      read_request(4'h1, iop_id, iop_src_addr, iop_dst_addr, flag, mode);

      fork
        begin
          for (int pkt = 0; pkt < NB_PACKETS_FULL+1; pkt++) begin
            send_ciphertext_emission_packet(qsfp_rx_vif[0], src_mac_addr, target_mac_addr, src_hpu_id, iop_id, iop_src_addr, iop_dst_addr, pkt[7:0], unused_payload);
            repeat(10) @(posedge clk_mhdma);
          end
        end

        begin
          wait(multi_hpu_dma.mhdma_bridge.mhdma_master.ciphertext_received);
          $display("[INFO]: Ciphertext correctly processed on module!");
          // Drain fifo_rr_regf: read the Read Request register to clear the interrupt
          wait(interrupt_read_request);
          maxil_drv_if.read_trans(MHDMA_REQUEST_READ_REQUEST_REQ_ID_OFS, rdata);
        end
      join


      $display("[INFO] Checking that standalone Notify produces a correct ack");

      fork
        begin
          send_notify_packet(qsfp_rx_vif[0], src_mac_addr, target_mac_addr, target_hpu, iop_id, iop_src_addr, flag, mode);
        end

        begin
          wait(notify_ack_received);
          $display("[INFO]: Notiy ACK received from DUT!");
          // Drain fifo_nrx_regf: read the Notify register to clear the interrupt
          wait(interrupt_notify);
          maxil_drv_if.read_trans(MHDMA_REQUEST_NOTIFY_REQ_ID_OFS, rdata);
        end
      join
    end

    $display("%t > INFO: End simulation",$time);
    repeat(20) @(posedge clk_control);
    end_of_test = 1'b1;
  end

// ============================================================================================== --
// Tasks
// ============================================================================================== --
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
      line_rate        = 8'h0;
      line_loopback    = 3'b000;
      lane             = 2'b00;
      debug_flag       = 1'b0;
      rst_rx_datapath  = 4'b0000;
      rst_tx_datapath  = 4'b0000;
      rst_all          = 4'b0000;
      gt_rx_reset_done = 4'b1111;
      gt_tx_reset_done = 4'b1111;

      maxil_drv_if.write_trans(MHDMA_SYSTEM_LANE_OFS, line_parameter);
      @(posedge clk_control);

      src_hpu_id = 0;
      dst_hpu_id = 1;

      src_mac_addr = $urandom();
      dst_mac_addr = $urandom();

      maxil_drv_if.write_trans(MHDMA_SYSTEM_HPU_ID_0_OFS,  {1'b1, 7'b0, src_mac_addr});
      maxil_drv_if.write_trans(MHDMA_SYSTEM_HPU_ID_1_OFS,  {1'b0, 7'b0, dst_mac_addr});

      $display("%t > INFO: Configuration successful\n", $time);
    end
  endtask

  /* Performs a Read request from HPU A to HPU B
    - Since HPU A and HPU B are the same no need to be able to be able to send from both
    - There is two registers to write to send a read request */
  task automatic read_request(
    input logic [  HPU_ID_W-1:0] node_id,
    input logic [  IOP_ID_W-1:0] iop_id,
    input logic [SRC_ADDR_W-1:0] src_addr,
    input logic [DST_ADDR_W-1:0] dest_addr,
    input logic [    FLAG_W-1:0] flag,
    input logic [    MODE_W-1:0] mode
  );
    logic [REG_DATA_W-1:0] read_req_id;
    logic [REG_DATA_W-1:0] read_req_addr;
    begin
      // see package
      read_req_addr = {dest_addr, src_addr};
      read_req_id = {iop_id, REQ_ID_READ, node_id, mode, flag, 8'b0};

      maxil_drv_if.write_trans(MHDMA_REQUEST_REQ_ADDR_OFS, read_req_addr);
      maxil_drv_if.write_trans(MHDMA_REQUEST_REQ_ID_OFS, read_req_id);

      repeat(50) @(posedge clk_mhdma);

    end
  endtask

  task automatic check_fsm_initialized();
    begin
      if (multi_hpu_dma.mhdma_bridge.mhdma_master.ntx_retry != 0) begin
        $display("%t > [ERROR] : FSM mhdma_master.ntx_retry has not been back to IDLE", $time);
        error_fsm = 1 ;
      end
      if (multi_hpu_dma.mhdma_bridge.mhdma_master.rreq_state != 0) begin
        $display("%t > [ERROR] : FSM mhdma_master.rreq_state has not been back to IDLE", $time);
        error_fsm = 1 ;
      end
      if (multi_hpu_dma.mhdma_bridge.mhdma_slave.nrx_state != 0) begin
        $display("%t > [ERROR] : FSM mhdma_slave.nrx_state has not been back to IDLE", $time);
        error_fsm = 1 ;
      end
      if (multi_hpu_dma.mhdma_bridge.mhdma_slave.cem_state != 0) begin
        $display("%t > [ERROR] : FSM mhdma_slave.cem_state has not been back to IDLE", $time);
        error_fsm = 1 ;
      end
      if (multi_hpu_dma.mhdma_bridge.mhdma_formatter.tx_state != 0) begin
        $display("%t > [ERROR] : FSM mhdma_slave.tx_state has not been back to IDLE", $time);
        error_fsm = 1 ;
      end

      repeat(50) @(posedge clk_mhdma);
      $display("%t > [INFO]: all FSMs are back to IDLE", $time);

    end
  endtask

endmodule
