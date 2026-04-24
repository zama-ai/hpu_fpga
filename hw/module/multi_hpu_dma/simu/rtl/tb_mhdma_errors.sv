// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : This testbench triggers all error flags in the multi_hpu_dma module
//
// Error signals tested:
//   error_fifo_rx_ovf             - Decoder: RX FIFO overflow (ciphertext emission FIFO full)
//   error_fifo_nrx_commands_ovf   - Slave: Notify RX commands FIFO overflow
//   error_rreq_command_queue_ovf  - Slave: Read Request command queue overflow
//   write_error[ETH_PC-1:0]       - Master: AXI write response SLVERR/DECERR
//   seq_num_error                 - Master: seq num mismatch
//   rrqq_cmd_ovf_error            - Master: Read Request Queue FIFO overflow (command lost)
//   nrqq_cmd_ovf_error            - Master: Notify Request Queue FIFO overflow (command lost)
//   error_id                      - Bridge: Multiple HPUs defined as current (not one-hot)
//
// Not tested here:
//   - ce_underrun_error           - Formatter: tvalid gap during CE payload (tb_mhdma_formatter
//                                   checks the gating prevents it, but no test triggers it)
//   - slave_discard_error         - Formatter: slave command with unrecognized req_id. Tested in
//                                   tb_mhdma_formatter unit TB (upstream slave/master only emit
//                                   legal req_ids, so the defensive discard path cannot be
//                                   reached from the integration-level stimuli).
//   - master_discard_error        - Formatter: master command with unrecognized req_id. Tested
//                                   in tb_mhdma_formatter unit TB (same rationale as above).
//
// ==============================================================================================

`resetall
`timescale 1ns/10ps
module tb_mhdma_errors;
  import mhdma_pkg::*;                     // multi-hpu-dma
  import axi_if_shell_axil_pkg::*;         // axi4-lite + REG_DATA_W
  import axi_if_common_param_pkg::*;       // general axi4
  import hpu_regif_core_mhdma_2in3_pkg::*; // ethernet regif
  import axi_if_mhdma_axi_pkg::*;          // AXI ethernet

  `include "tb_mhdma_tasks.sv"

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int CLK_HALF_PERIOD_CFG   = 4;
  localparam int CLK_HALF_PERIOD_MRMAC = 1;
  localparam int ARST_ACTIVATION = 17;

  localparam int MEM_SIM_SIZE = 8;

// ============================================================================================== --
// clock, reset
// ============================================================================================== --
  bit clk_mhdma_cfg;
  bit clk_mhdma;

  initial begin
    clk_mhdma_cfg = 1'b0;
    clk_mhdma = 1'b0;
  end

  always #CLK_HALF_PERIOD_CFG clk_mhdma_cfg = ~clk_mhdma_cfg;
  always #CLK_HALF_PERIOD_MRMAC clk_mhdma = ~clk_mhdma;

  bit a_rst_n;
  bit s_rstn_cfg;
  bit s_rstn_mhdma;

  initial begin
    a_rst_n = 1'b0;
    #ARST_ACTIVATION a_rst_n = 1'b1;
  end

  always_ff @(posedge clk_mhdma_cfg) s_rstn_cfg <= a_rst_n;
  always_ff @(posedge clk_mhdma) s_rstn_mhdma <= a_rst_n;

// ============================================================================================== --
// End of test
// ============================================================================================== --
  bit end_of_test;
  int test_SCENARIO;

  initial begin
    wait (end_of_test);
    @(posedge clk_mhdma_cfg) $display("%t > SUCCEED ! All error tests completed", $time);
    $finish;
  end

// ============================================================================================== --
// Error tracking
// ============================================================================================== --
  bit error;
  bit error_test_timeout;
  bit error_unexpected;

  assign error = error_test_timeout | error_unexpected;

  always_ff @(posedge clk_mhdma_cfg)
    if (error) begin
      $display("%t > FAILURE !", $time);
      $finish;
    end

// ============================================================================================== --
// DUT signals
// ============================================================================================== --
  logic [MRMAC_AXIS_W-1:0]                unused_payload [$];

  // AXI4-Lite interface
  logic [AXIL_ADD_W-1:0]                  s_axil_mhdma_awaddr;
  logic                                   s_axil_mhdma_awvalid;
  logic                                   s_axil_mhdma_awready;
  logic [AXIL_DATA_W-1:0]                 s_axil_mhdma_wdata;
  logic [AXIL_DATA_BYTES-1:0]             s_axil_mhdma_wstrb;
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

  // AXI4 HBM interface (single NMU)
  logic [AXI4_ID_W-1:0]       m_axi4_awid;
  logic [AXI4_ADD_W-1:0]      m_axi4_awaddr;
  logic [7:0]                 m_axi4_awlen;
  logic [2:0]                 m_axi4_awsize;
  logic [1:0]                 m_axi4_awburst;
  logic                       m_axi4_awvalid;
  logic                       m_axi4_awready;
  logic [AXI4_DATA_W-1:0]     m_axi4_wdata;
  logic [(AXI4_DATA_W/8)-1:0] m_axi4_wstrb;
  logic                       m_axi4_wlast;
  logic                       m_axi4_wvalid;
  logic                       m_axi4_wready;
  logic [AXI4_ID_W-1:0]       m_axi4_bid;
  logic [1:0]                 m_axi4_bresp;
  logic                       m_axi4_bvalid;
  logic                       m_axi4_bready;

  logic [AXI4_ID_W-1:0]       m_axi4_arid;
  logic [AXI4_ADD_W-1:0]      m_axi4_araddr;
  logic [7:0]                 m_axi4_arlen;
  logic [2:0]                 m_axi4_arsize;
  logic [1:0]                 m_axi4_arburst;
  logic                       m_axi4_arvalid;
  logic                       m_axi4_arready;
  logic [AXI4_ID_W-1:0]       m_axi4_rid;
  logic [AXI4_DATA_W-1:0]     m_axi4_rdata;
  logic [1:0]                 m_axi4_rresp;
  logic                       m_axi4_rlast;
  logic                       m_axi4_rvalid;
  logic                       m_axi4_rready;

  // QSFP interface
  logic [QSFP_LANE_NB-1:0][MRMAC_AXIS_W-1:0 ] qsfp_tx_tdata;
  logic [QSFP_LANE_NB-1:0][MRMAC_TKEEP_W-1:0] qsfp_tx_tkeep_user;
  logic [QSFP_LANE_NB-1:0]                    qsfp_tx_tlast;
  logic [QSFP_LANE_NB-1:0]                    qsfp_tx_tvalid;
  logic [QSFP_LANE_NB-1:0]                    qsfp_tx_tready;

  logic [QSFP_LANE_NB-1:0][MRMAC_AXIS_W-1:0 ] qsfp_rx_tdata;
  logic [QSFP_LANE_NB-1:0][MRMAC_TKEEP_W-1:0] qsfp_rx_tkeep_user;
  logic [QSFP_LANE_NB-1:0]                    qsfp_rx_tlast;
  logic [QSFP_LANE_NB-1:0]                    qsfp_rx_tvalid;

  // Interrupts and GT signals
  logic interrupt_notify;
  logic interrupt_read_request;

  logic [QSFP_LANE_NB-1:0] gt_reset_rx_datapath;
  logic [QSFP_LANE_NB-1:0] gt_reset_tx_datapath;
  logic [QSFP_LANE_NB-1:0] gt_reset_all;
  logic [QSFP_LANE_NB-1:0] gt_rx_reset_done;
  logic [QSFP_LANE_NB-1:0] gt_tx_reset_done;
  logic [7:0]              gt_line_rate;
  logic [2:0]              gt_loopback;

  // Test control signals
  logic       inject_axi_write_error;
  logic [1:0] axi_error_type;

// ============================================================================================== --
// QSFP interface
// ============================================================================================== --
  qsfp_if qsfp_rx_vif[QSFP_LANE_NB] (clk_mhdma);

  generate
    for (genvar gen_i=0; gen_i<QSFP_LANE_NB; gen_i=gen_i+1) begin
      assign qsfp_rx_tdata[gen_i]      = qsfp_rx_vif[gen_i].tdata;
      assign qsfp_rx_tkeep_user[gen_i] = qsfp_rx_vif[gen_i].tkeep_user;
      assign qsfp_rx_tlast[gen_i]      = qsfp_rx_vif[gen_i].tlast;
      assign qsfp_rx_tvalid[gen_i]     = qsfp_rx_vif[gen_i].tvalid;

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
// DUT instantiation
// ============================================================================================== --
  multi_hpu_dma #(
  ) multi_hpu_dma (
    .clk_mhdma_cfg            (clk_mhdma_cfg           ),
    .resetn_mhdma_cfg         (s_rstn_cfg        ),
    .clk_mhdma          (clk_mhdma         ),
    .resetn_mhdma       (s_rstn_mhdma      ),

    .s_axil_mhdma_awaddr      (s_axil_mhdma_awaddr ),
    .s_axil_mhdma_awvalid     (s_axil_mhdma_awvalid),
    .s_axil_mhdma_awready     (s_axil_mhdma_awready),
    .s_axil_mhdma_wdata       (s_axil_mhdma_wdata  ),
    .s_axil_mhdma_wstrb       (s_axil_mhdma_wstrb  ),
    .s_axil_mhdma_wvalid      (s_axil_mhdma_wvalid ),
    .s_axil_mhdma_wready      (s_axil_mhdma_wready ),
    .s_axil_mhdma_bresp       (s_axil_mhdma_bresp  ),
    .s_axil_mhdma_bvalid      (s_axil_mhdma_bvalid ),
    .s_axil_mhdma_bready      (s_axil_mhdma_bready ),
    .s_axil_mhdma_araddr      (s_axil_mhdma_araddr ),
    .s_axil_mhdma_arvalid     (s_axil_mhdma_arvalid),
    .s_axil_mhdma_arready     (s_axil_mhdma_arready),
    .s_axil_mhdma_rdata       (s_axil_mhdma_rdata  ),
    .s_axil_mhdma_rresp       (s_axil_mhdma_rresp  ),
    .s_axil_mhdma_rvalid      (s_axil_mhdma_rvalid ),
    .s_axil_mhdma_rready      (s_axil_mhdma_rready ),

    .m_axi4_mhdma_hbm_arid    (m_axi4_arid   ),
    .m_axi4_mhdma_hbm_araddr  (m_axi4_araddr ),
    .m_axi4_mhdma_hbm_arlen   (m_axi4_arlen  ),
    .m_axi4_mhdma_hbm_arsize  (m_axi4_arsize ),
    .m_axi4_mhdma_hbm_arburst (m_axi4_arburst),
    .m_axi4_mhdma_hbm_arvalid (m_axi4_arvalid),
    .m_axi4_mhdma_hbm_arready (m_axi4_arready),
    .m_axi4_mhdma_hbm_rid     (m_axi4_rid    ),
    .m_axi4_mhdma_hbm_rdata   (m_axi4_rdata  ),
    .m_axi4_mhdma_hbm_rresp   (m_axi4_rresp  ),
    .m_axi4_mhdma_hbm_rlast   (m_axi4_rlast  ),
    .m_axi4_mhdma_hbm_rvalid  (m_axi4_rvalid ),
    .m_axi4_mhdma_hbm_rready  (m_axi4_rready ),
    .m_axi4_mhdma_hbm_awid    (m_axi4_awid   ),
    .m_axi4_mhdma_hbm_awaddr  (m_axi4_awaddr ),
    .m_axi4_mhdma_hbm_awlen   (m_axi4_awlen  ),
    .m_axi4_mhdma_hbm_awsize  (m_axi4_awsize ),
    .m_axi4_mhdma_hbm_awburst (m_axi4_awburst),
    .m_axi4_mhdma_hbm_awvalid (m_axi4_awvalid),
    .m_axi4_mhdma_hbm_awready (m_axi4_awready),
    .m_axi4_mhdma_hbm_wdata   (m_axi4_wdata  ),
    .m_axi4_mhdma_hbm_wstrb   (m_axi4_wstrb  ),
    .m_axi4_mhdma_hbm_wlast   (m_axi4_wlast  ),
    .m_axi4_mhdma_hbm_wvalid  (m_axi4_wvalid ),
    .m_axi4_mhdma_hbm_wready  (m_axi4_wready ),
    .m_axi4_mhdma_hbm_bid     (m_axi4_bid    ),
    .m_axi4_mhdma_hbm_bresp   (m_axi4_bresp  ),
    .m_axi4_mhdma_hbm_bvalid  (m_axi4_bvalid ),
    .m_axi4_mhdma_hbm_bready  (m_axi4_bready ),

    .qsfp_tx_tdata          (qsfp_tx_tdata     ),
    .qsfp_tx_tkeep_user     (qsfp_tx_tkeep_user),
    .qsfp_tx_tlast          (qsfp_tx_tlast     ),
    .qsfp_tx_tvalid         (qsfp_tx_tvalid    ),
    .qsfp_tx_tready         (qsfp_tx_tready    ),

    .qsfp_rx_tdata          (qsfp_rx_tdata     ),
    .qsfp_rx_tkeep_user     (qsfp_rx_tkeep_user),
    .qsfp_rx_tlast          (qsfp_rx_tlast     ),
    .qsfp_rx_tvalid         (qsfp_rx_tvalid    ),

    .interrupt_notify       (interrupt_notify       ),
    .interrupt_read_request (interrupt_read_request ),

    .gt_line_rate           (gt_line_rate        ),
    .gt_loopback            (gt_loopback         ),
    .gt_reset_rx_datapath   (gt_reset_rx_datapath),
    .gt_reset_tx_datapath   (gt_reset_tx_datapath),
    .gt_reset_all           (gt_reset_all        ),
    .gt_rx_reset_done       (gt_rx_reset_done    ),
    .gt_tx_reset_done       (gt_tx_reset_done    )
  );

// ============================================================================================== --
// AXI4-Lite Master Driver
// ============================================================================================== --
  maxil_if #(
    .AXIL_ADD_W (AXIL_ADD_W ),
    .AXIL_DATA_W(AXIL_DATA_W)
  ) maxil_drv (
    .clk   (clk_mhdma_cfg            ),
    .rst_n (s_rstn_cfg         )
  );

  // Connect interface on testbench signals
  assign s_axil_mhdma_awaddr  = maxil_drv.awaddr;
  assign s_axil_mhdma_awvalid = maxil_drv.awvalid;
  assign s_axil_mhdma_wdata   = maxil_drv.wdata;
  assign s_axil_mhdma_wstrb   = maxil_drv.wstrb;
  assign s_axil_mhdma_wvalid  = maxil_drv.wvalid;
  assign s_axil_mhdma_bready  = maxil_drv.bready;
  assign s_axil_mhdma_araddr  = maxil_drv.araddr;
  assign s_axil_mhdma_arvalid = maxil_drv.arvalid;
  assign s_axil_mhdma_rready  = maxil_drv.rready;

  assign maxil_drv.awready = s_axil_mhdma_awready;
  assign maxil_drv.wready  = s_axil_mhdma_wready;
  assign maxil_drv.bresp   = s_axil_mhdma_bresp;
  assign maxil_drv.bvalid  = s_axil_mhdma_bvalid;
  assign maxil_drv.arready = s_axil_mhdma_arready;
  assign maxil_drv.rdata   = s_axil_mhdma_rdata;
  assign maxil_drv.rresp   = s_axil_mhdma_rresp;
  assign maxil_drv.rvalid  = s_axil_mhdma_rvalid;

// ============================================================================================== --
// Simple AXI4 Memory Model with Error Injection
// ============================================================================================== --
  // Memory for read data
  logic [AXI4_DATA_W-1:0] axi_mem [2**MEM_SIM_SIZE];

  // Initialize memory
  initial begin
    for (int i = 0; i < 2**MEM_SIM_SIZE; i++) begin
      for (int w = 0; w < AXI4_DATA_W; w += 32)
        axi_mem[i][w +: 32] = $urandom();
    end
  end

  // AXI Read response - simple model (single NMU)
  logic [7:0] rd_beat_cnt;
  logic [7:0] rd_len;
  logic [AXI4_ID_W-1:0] rd_id;
  logic rd_active;

  always_ff @(posedge clk_mhdma) begin
    if (~s_rstn_mhdma) begin
      m_axi4_arready <= 1'b1;
      m_axi4_rvalid  <= 1'b0;
      m_axi4_rlast   <= 1'b0;
      m_axi4_rresp   <= AXI4_OKAY;
      rd_active       <= 1'b0;
      rd_beat_cnt     <= '0;
    end else begin
      // Accept read address
      if (m_axi4_arvalid && m_axi4_arready) begin
        rd_len      <= m_axi4_arlen;
        rd_id       <= m_axi4_arid;
        rd_active   <= 1'b1;
        rd_beat_cnt <= '0;
        m_axi4_arready <= 1'b0;
      end

      // Generate read data
      if (rd_active) begin
        m_axi4_rvalid <= 1'b1;
        m_axi4_rid    <= rd_id;
        m_axi4_rdata  <= axi_mem[rd_beat_cnt[7:0]];
        m_axi4_rlast  <= (rd_beat_cnt == rd_len);

        if (m_axi4_rready) begin
          if (rd_beat_cnt == rd_len) begin
            rd_active      <= 1'b0;
            m_axi4_rvalid  <= 1'b0;
            m_axi4_rlast   <= 1'b0;
            m_axi4_arready <= 1'b1;
          end else begin
            rd_beat_cnt <= rd_beat_cnt + 1;
          end
        end
      end
    end
  end

  // AXI Write response with error injection (single NMU)
  logic [7:0] wr_beat_cnt;
  logic [7:0] wr_len;
  logic [AXI4_ID_W-1:0] wr_id;
  logic wr_addr_received;
  logic wr_data_done;

  always_ff @(posedge clk_mhdma) begin
    if (~s_rstn_mhdma) begin
      m_axi4_awready   <= 1'b1;
      m_axi4_wready    <= 1'b1;
      m_axi4_bvalid    <= 1'b0;
      m_axi4_bresp     <= AXI4_OKAY;
      wr_addr_received <= 1'b0;
      wr_data_done     <= 1'b0;
      wr_beat_cnt      <= '0;
    end else begin
      // Accept write address
      if (m_axi4_awvalid && m_axi4_awready) begin
        wr_len           <= m_axi4_awlen;
        wr_id            <= m_axi4_awid;
        wr_addr_received <= 1'b1;
        m_axi4_awready   <= 1'b0;
        wr_beat_cnt      <= '0;
      end

      // Accept write data
      if (m_axi4_wvalid && m_axi4_wready) begin
        if (m_axi4_wlast) begin
          wr_data_done  <= 1'b1;
          m_axi4_wready <= 1'b0;
        end
      end

      // Generate write response
      if (wr_addr_received && wr_data_done && !m_axi4_bvalid) begin
        m_axi4_bvalid <= 1'b1;
        m_axi4_bid    <= wr_id;
        // Inject error if requested
        if (inject_axi_write_error) begin
          m_axi4_bresp <= axi_error_type;
        end else begin
          m_axi4_bresp <= AXI4_OKAY;
        end
      end

      // Clear write response when acknowledged
      if (m_axi4_bvalid && m_axi4_bready) begin
        m_axi4_bvalid    <= 1'b0;
        m_axi4_awready   <= 1'b1;
        m_axi4_wready    <= 1'b1;
        wr_addr_received <= 1'b0;
        wr_data_done     <= 1'b0;
      end
    end
  end

  // GT signals
  initial begin
    gt_rx_reset_done = '1;
    gt_tx_reset_done = '1;
  end

// ============================================================================================== --
// Test Variables
// ============================================================================================== --
  logic [REG_DATA_W-1:0] read_data;

  logic [RSVD_W+FLAG_W+MODE_W-1:0] req_rfm;
  logic [MAC_ADDR_W-1:0] dst_mac_addr;
  logic [MAC_ADDR_W-1:0] src_mac_addr;
  logic [HPU_ID_W-1:0]   dst_hpu_id;
  logic [HPU_ID_W-1:0]   src_hpu_id;
  logic [IOP_ID_W-1:0]   iop_id;
  logic [SRC_ADDR_W-1:0] src_addr;
  logic [DST_ADDR_W-1:0] dst_addr;
  logic [REG_DATA_W-1:0] read_req_id;
  logic [REG_DATA_W-1:0] read_req_addr;
  logic [REG_DATA_W-1:0] notify_req_id;
  logic [REG_DATA_W-1:0] notify_req_addr;

  assign req_rfm = 'h0; // not something we test here

// ============================================================================================== --
// Main Test Scenario
// ============================================================================================== --
  int scenario_id;
  logic [REG_DATA_W-1:0] reg_error;
  mhdma_error_all_t      errors_t;

  initial begin
    maxil_drv.init();
    inject_axi_write_error = 1'b0;
    axi_error_type = AXI4_OKAY;
    scenario_id = 0;

    repeat(30) @(posedge clk_mhdma_cfg);

    $display("\n==================================================================================================");
    $display("  Initialization");
    $display("==================================================================================================");

    init_config();

    // Read initial error register - should be 0
    maxil_drv.read_trans(MHDMA_SYSTEM_ERRORS_OFS, reg_error);
    display_errors(reg_error);
    assert (reg_error == 0) else begin
      $display("%t > [ERROR] Error register not zero at startup", $time);
      error_unexpected = 1'b1;
    end

    repeat(50) @(posedge clk_mhdma_cfg);

    $display("\n==================================================================================================");
    $display("  SCENARIO %0d: Testing error_id (multiple HPUs as current)", scenario_id);
    $display("==================================================================================================");

    test_error_id();

    $display("\n==================================================================================================");
    $display("  SCENARIO %0d: Testing write_error (AXI SLVERR/DECERR)", scenario_id);
    $display("==================================================================================================");

    test_write_error();

    $display("\n==================================================================================================");
    $display("  SCENARIO %0d: Testing a mismatch in sec num during CE", scenario_id);
    $display("==================================================================================================\n");

    test_seq_num();

    $display("\n==================================================================================================");
    $display("  SCENARIO %0d: Testing FIFO overflow errors", scenario_id);
    $display("==================================================================================================\n");

    test_fifo_overflow_errors();

    $display("\n==================================================================================================");
    $display("  SCENARIO %0d: Testing rrqq_cmd_ovf_error (Read Request Queue overflow)", scenario_id);
    $display("==================================================================================================\n");

    test_rrqq_cmd_ovf_error();

    $display("\n==================================================================================================");
    $display("  SCENARIO %0d: Testing nrqq_cmd_ovf_error (Notify Request Queue overflow)", scenario_id);
    $display("==================================================================================================\n");

    test_nrqq_cmd_ovf_error();

    $display("\n==================================================================================================");
    $display("  SCENARIO %0d: Testing decoder dropped packet counter (wrong MAC + unknown opcode)", scenario_id);
    $display("==================================================================================================\n");

    test_decoder_dropped();

    $display("\n==================================================================================================");
    $display("  END of test : checking that none errors sticked & are reset");
    $display("==================================================================================================\n");

    maxil_drv.read_trans(MHDMA_SYSTEM_ERRORS_OFS, reg_error);
    display_errors(reg_error);
    assert (reg_error == 0 ) else begin
      $display("%t > [ERROR] reg_error has not been properly reset by reading into them", $time);
      error_unexpected = 1'b1;
    end

    repeat(100) @(posedge clk_mhdma_cfg);
    end_of_test = 1'b1;
  end

// ============================================================================================== --
// Tasks
// ============================================================================================== --

  // Basic configuration task
  task automatic init_config();
    begin
      // Set lane to 0, no loopback
      maxil_drv.write_trans(MHDMA_SYSTEM_LANE_OFS, 32'h0);

      // Set HBM addresses
      maxil_drv.write_trans(MHDMA_HBM_AXI4_ADDR_2IN3_CT_PC0_LSB_OFS, 32'h0000_1000);
      maxil_drv.write_trans(MHDMA_HBM_AXI4_ADDR_2IN3_CT_PC0_MSB_OFS, 32'h0);
      maxil_drv.write_trans(MHDMA_HBM_AXI4_ADDR_2IN3_CT_PC1_LSB_OFS, 32'h0000_2000);
      maxil_drv.write_trans(MHDMA_HBM_AXI4_ADDR_2IN3_CT_PC1_MSB_OFS, 32'h0);

      // Configure ONE HPU as current (correct configuration)
      // HPU 0 is current, others are not
      maxil_drv.write_trans(MHDMA_SYSTEM_HPU_ID_0_OFS, {1'b1, 3'b0, 4'h0, 24'hABCDE0});  // HPU 0 - current
      maxil_drv.write_trans(MHDMA_SYSTEM_HPU_ID_1_OFS, {1'b0, 3'b0, 4'h1, 24'hABCDE1});  // HPU 1
      maxil_drv.write_trans(MHDMA_SYSTEM_HPU_ID_2_OFS, {1'b0, 3'b0, 4'h2, 24'hABCDE2});  // HPU 2
      maxil_drv.write_trans(MHDMA_SYSTEM_HPU_ID_3_OFS, {1'b0, 3'b0, 4'h3, 24'hABCDE3});  // HPU 3
      maxil_drv.write_trans(MHDMA_SYSTEM_HPU_ID_4_OFS, {1'b0, 3'b0, 4'h4, 24'hABCDE4});  // HPU 4
      maxil_drv.write_trans(MHDMA_SYSTEM_HPU_ID_5_OFS, {1'b0, 3'b0, 4'h5, 24'hABCDE5});  // HPU 5
      maxil_drv.write_trans(MHDMA_SYSTEM_HPU_ID_6_OFS, {1'b0, 3'b0, 4'h6, 24'hABCDE6});  // HPU 6
      maxil_drv.write_trans(MHDMA_SYSTEM_HPU_ID_7_OFS, {1'b0, 3'b0, 4'h7, 24'hABCDE7});  // HPU 7

      repeat(20) @(posedge clk_mhdma_cfg);

      dst_mac_addr = 24'hABCDE0;
      src_mac_addr = 24'hABCDE1;
      dst_hpu_id   = 4'h0;
      src_hpu_id   = 4'h1;

    end
  endtask

  // Test error_id by configuring multiple HPUs as current
  task automatic test_error_id();
    begin

      // Configure TWO HPUs as current (invalid - not one-hot)
      maxil_drv.write_trans(MHDMA_SYSTEM_HPU_ID_0_OFS, {1'b1, 3'b0, 4'h0, 24'hABCDE0});
      maxil_drv.write_trans(MHDMA_SYSTEM_HPU_ID_1_OFS, {1'b1, 3'b0, 4'h1, 24'hABCDE1});

      // Wait for error to propagate through CDC
      repeat(50) @(posedge clk_mhdma_cfg);

      // Read error status
      maxil_drv.read_trans(MHDMA_SYSTEM_ERRORS_OFS, reg_error);
      errors_t = mhdma_error_all_t'(reg_error);
      $display("%t > Error register value :  0x%08b", $time, reg_error);

      // Check error_id bit
      if (~errors_t.mhdma_error.error_id) begin
        $display("%t > [ERROR] error_id NOT triggered", $time);
        error_unexpected = 1'b1;
      end

      // Restore correct configuration (only one HPU as current)
      maxil_drv.write_trans(MHDMA_SYSTEM_HPU_ID_0_OFS, {1'b1, 3'b0, 4'h0, 24'hABCDE0});
      maxil_drv.write_trans(MHDMA_SYSTEM_HPU_ID_1_OFS, {1'b0, 3'b0, 4'h1, 24'hABCDE1});

      repeat(20) @(posedge clk_mhdma_cfg);
      scenario_id = scenario_id + 1;
    end
  endtask

  // Test write_error by injecting AXI write response errors
  // Flow: 1) Initiate read request via AXIL -> 2) Master sends RR packet -> 3) "Remote" sends CE packets back
  //       4) Master writes CE data to HBM -> 5) AXI slave returns error -> 6) write_error is set
  task automatic test_write_error();
    begin

      // Enable AXI write error injection BEFORE any write transactions
      inject_axi_write_error = 1'b1;
      axi_error_type = AXI4_SLVERR;

      // Step 1: Initiate a read request
      read_req_id   = {8'h42, REQ_ID_READ, 4'h1, req_rfm};
      read_req_addr = {16'h5678, 16'h1234};

      maxil_drv.write_trans(MHDMA_REQUEST_REQ_ADDR_OFS, read_req_addr);
      maxil_drv.write_trans(MHDMA_REQUEST_REQ_ID_OFS, read_req_id);

      // Wait for read request to be sent out via TX
      repeat(200) @(posedge clk_mhdma_cfg);

      // Step 2: Send ciphertext emission packets as if we're the remote HPU responding
      for (int pkt = 0; pkt < NB_PACKETS_FULL + 1; pkt++) begin
        iop_id = $urandom();
        src_addr = $urandom();
        dst_addr = $urandom();
        send_ciphertext_emission_packet(qsfp_rx_vif[0], dst_mac_addr, src_mac_addr, dst_hpu_id, iop_id, src_addr, dst_addr, pkt[7:0], unused_payload);
        repeat(10) @(posedge clk_mhdma);
      end

      // Wait for write transactions and error to propagate through CDC
      repeat(1000) @(posedge clk_mhdma_cfg);

      // Read error status
      maxil_drv.read_trans(MHDMA_SYSTEM_ERRORS_OFS, reg_error);
      errors_t = mhdma_error_all_t'(reg_error);
      $display("%t > Error register value :  0x%08b", $time, reg_error);

      // Check write_error bits (bits 3 and 4)
      assert (|errors_t.mhdma_error.master_error.write_error) else begin
        $display("%t > [ERROR] write_error not triggered", $time);
        error_unexpected = 1'b1;
      end

      // Disable error injection
      inject_axi_write_error = 1'b0;
      axi_error_type = AXI4_OKAY;

      repeat(50) @(posedge clk_mhdma_cfg);
      scenario_id = scenario_id + 1;
    end
  endtask

  // Test FIFO overflow errors
  task automatic test_fifo_overflow_errors();
    logic [FLAG_W-1:0]     flag;
    logic [MODE_W-1:0]     mode;
    begin

      // Send many ciphertext emission packets without consuming (error_fifo_rx_ovf)
      for (int i = 0; i < 2*RX_FIFO_DEPTH; i++) begin
        iop_id = $urandom();
        src_addr = $urandom();
        flag = $urandom();
        mode = $urandom();
        // using notifies here as Ciphertext emission is too slow for fifo to not be consumed
        send_notify_packet(qsfp_rx_vif[0], dst_mac_addr, src_mac_addr, dst_hpu_id, iop_id, src_addr, flag, mode);
      end

      repeat(200) @(posedge clk_mhdma_cfg);
      maxil_drv.read_trans(MHDMA_SYSTEM_ERRORS_OFS, reg_error);
      $display("%t > Error register value :  0x%08b", $time, reg_error);
      errors_t = mhdma_error_all_t'(reg_error);

      assert (errors_t.mhdma_error.decoder_error.error_fifo_rx_ovf) else begin
        $display("%t > [ERROR] error_fifo_rx_ovf not triggered", $time);
        error_unexpected = 1'b1;
      end

      // because the system is now stuck
      reset_system();

      scenario_id = scenario_id + 1;
    end
  endtask

  // Test FIFO overflow errors
  task automatic test_seq_num();
    begin

      // Step 1: Initiate a read request
      read_req_id   = {8'h42, REQ_ID_READ, 4'h1, req_rfm};
      read_req_addr = {16'h5678, 16'h1234};

      maxil_drv.write_trans(MHDMA_REQUEST_REQ_ADDR_OFS, read_req_addr);
      maxil_drv.write_trans(MHDMA_REQUEST_REQ_ID_OFS, read_req_id);

      // Wait for read request to be sent out via TX
      repeat(200) @(posedge clk_mhdma_cfg);

      // Step 2: Send ciphertext emission packets as if we're the remote HPU responding
      // Inject seq_num mismatch on packet NB_PACKETS_FULL-1: send (NB_PACKETS_FULL-2) instead
      for (int pkt = 0; pkt < NB_PACKETS_FULL + 1; pkt++) begin
        iop_id = $urandom();
        src_addr = $urandom();
        dst_addr = $urandom();
        if (pkt == NB_PACKETS_FULL - 1) begin
          send_ciphertext_emission_packet(qsfp_rx_vif[0], dst_mac_addr, src_mac_addr, dst_hpu_id, iop_id, src_addr, dst_addr, (NB_PACKETS_FULL-2), unused_payload);
        end else begin
          send_ciphertext_emission_packet(qsfp_rx_vif[0], dst_mac_addr, src_mac_addr, dst_hpu_id, iop_id, src_addr, dst_addr, pkt[7:0], unused_payload);
        end
        repeat(10) @(posedge clk_mhdma);
      end

      maxil_drv.read_trans(MHDMA_SYSTEM_ERRORS_OFS, reg_error);
      errors_t = mhdma_error_all_t'(reg_error);
      $display("%t > Error register value :  0x%08b", $time, reg_error);

      assert (errors_t.mhdma_error.master_error.seq_num_error) else begin
        $display("%t > [ERROR] seq_num_error not triggered", $time);
        error_unexpected = 1'b1;
      end

      reset_system();

      scenario_id = scenario_id + 1;
    end
  endtask

  task automatic reset_system();
    // when triggering errors, system can get stuck
    begin
      a_rst_n = 1'b0;
      #ARST_ACTIVATION a_rst_n = 1'b1;
      init_config();
    end
  endtask

  // Test rrqq_cmd_ovf_error: flood read request queue until overflow
  task automatic test_rrqq_cmd_ovf_error();
    begin
      // Flood RRQQ FIFO with read requests (more than REQ_FIFO_DEPTH)
      for (int i = 0; i < 2*REQ_FIFO_DEPTH; i++) begin
        read_request(src_hpu_id, $urandom(), $urandom(), $urandom());
      end

      repeat(200) @(posedge clk_mhdma_cfg);
      maxil_drv.read_trans(MHDMA_SYSTEM_ERRORS_OFS, reg_error);
      errors_t = mhdma_error_all_t'(reg_error);
      $display("%t > Error register value :  0x%08b", $time, reg_error);

      assert (errors_t.master_error_cfg.rrqq_cmd_ovf_error) else begin
        $display("%t > [ERROR] rrqq_cmd_ovf_error not triggered", $time);
        error_unexpected = 1'b1;
      end

      reset_system();
      scenario_id = scenario_id + 1;
    end
  endtask

  // Test nrqq_cmd_ovf_error: flood notify request queue until overflow
  task automatic test_nrqq_cmd_ovf_error();
    begin
      // Flood NRQQ FIFO with notify requests (more than REQ_FIFO_DEPTH)
      for (int i = 0; i < 2*REQ_FIFO_DEPTH; i++) begin
        notify_req_addr = {16'($urandom()), 16'($urandom())};
        notify_req_id   = {8'($urandom()), REQ_ID_NOTIFY, src_hpu_id, req_rfm};
        maxil_drv.write_trans(MHDMA_REQUEST_REQ_ADDR_OFS, notify_req_addr);
        maxil_drv.write_trans(MHDMA_REQUEST_REQ_ID_OFS, notify_req_id);
      end

      repeat(200) @(posedge clk_mhdma_cfg);
      maxil_drv.read_trans(MHDMA_SYSTEM_ERRORS_OFS, reg_error);
      errors_t = mhdma_error_all_t'(reg_error);
      $display("%t > Error register value :  0x%08b", $time, reg_error);

      assert (errors_t.master_error_cfg.nrqq_cmd_ovf_error) else begin
        $display("%t > [ERROR] nrqq_cmd_ovf_error not triggered", $time);
        error_unexpected = 1'b1;
      end

      reset_system();
      scenario_id = scenario_id + 1;
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
    begin
      read_req_addr = {dest_addr, src_addr};
      read_req_id = {iop_id, REQ_ID_READ, node_id, req_rfm};

      maxil_drv.write_trans(MHDMA_REQUEST_REQ_ADDR_OFS, read_req_addr);
      maxil_drv.write_trans(MHDMA_REQUEST_REQ_ID_OFS, read_req_id);
    end
  endtask

  // Test decoder dropped packet counter by sending packets with wrong MAC and unknown opcode
  task automatic test_decoder_dropped();
    logic [REG_DATA_W-1:0] stat_dropped;
    logic [MAC_ADDR_W-1:0] wrong_mac;
    logic [MRMAC_AXIS_W-1:0] unused_payload [$];
    begin
      // Read initial drop counter: should be 0
      maxil_drv.read_trans(MHDMA_REQUEST_STAT_NB_DECODER_DROPPED_OFS, stat_dropped);
      assert (stat_dropped == 0) else begin
        $display("%t > [ERROR] stat_nb_decoder_dropped not zero before test (%0d)", $time, stat_dropped);
        error_unexpected = 1'b1;
      end

      // 1) Send a notify packet with wrong destination MAC (should be dropped)
      wrong_mac = 24'hFFFFFF;
      send_notify_packet(qsfp_rx_vif[0], wrong_mac, src_mac_addr, dst_hpu_id, 8'hAA, 16'h1234);

      // 2) Send a packet with correct MAC but unknown req_id (opcode 0xF = undefined)
      //    Reuse notify packet structure but patch req_id to unknown value
      begin
        logic [MRMAC_AXIS_W-1:0] pkt_data [8];
        pkt_data[0] = {MAC_OUI, dst_mac_addr, MAC_OUI[MAC_OUI_W-1:8]};
        pkt_data[1] = {MAC_OUI[7:0], src_mac_addr, ETH_LEN_MIN, LLC_DSAP, LLC_SSAP};
        pkt_data[2] = {LLC_CTRL, 4'hF, dst_hpu_id, 8'h00, 16'h0, 16'h0, 8'h0}; // req_id=0xF (unknown)
        pkt_data[3] = {8'h0, 6'h0, 2'b0, 48'h0};
        for (int i = 4; i < 8; i++) pkt_data[i] = 64'h0;

        for (int i = 0; i < 8; i++) begin
          @(posedge qsfp_rx_vif[0].clk);
          qsfp_rx_vif[0].tdata      = byte_swap(pkt_data[i]);
          qsfp_rx_vif[0].tkeep_user = (i < 7) ? 11'h0FF : 11'h00F;
          qsfp_rx_vif[0].tlast      = (i == 7);
          qsfp_rx_vif[0].tvalid     = 1'b1;
        end
        @(posedge qsfp_rx_vif[0].clk);
        qsfp_rx_vif[0].tvalid     = 1'b0;
        qsfp_rx_vif[0].tlast      = 1'b0;
        qsfp_rx_vif[0].tkeep_user = 'h0;
      end

      // Wait for CDC propagation
      repeat(200) @(posedge clk_mhdma_cfg);

      // Read drop counter: should be 2 (one wrong MAC + one unknown opcode)
      maxil_drv.read_trans(MHDMA_REQUEST_STAT_NB_DECODER_DROPPED_OFS, stat_dropped);
      $display("%t > stat_nb_decoder_dropped = %0d (expected 2)", $time, stat_dropped);
      assert (stat_dropped == 2) else begin
        $display("%t > [ERROR] stat_nb_decoder_dropped = %0d, expected 2", $time, stat_dropped);
        error_unexpected = 1'b1;
      end

      scenario_id = scenario_id + 1;
    end
  endtask

endmodule
