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
//   - seq_num_mismatch            - Master: seq num received during CE missmatched expected
//   error_id                      - Bridge: Multiple HPUs defined as current (not one-hot)
//
// Not tested (hardcoded to 0 in RTL):
//   - formatter_error           - Formatter: Currently disabled
//
// ==============================================================================================

`resetall
`timescale 1ns/10ps
module tb_mhdma_errors;
  import mhdma_pkg::*;                   // multi-hpu-dma
  import axi_if_shell_axil_pkg::*;       // axi4-lite + REG_DATA_W
  import axi_if_common_param_pkg::*;     // general axi4
  import hpu_regif_core_eth_2in3_pkg::*; // ethernet regif
  import axi_if_eth_axi_pkg::*;          // AXI ethernet

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int CLK_HALF_PERIOD_CFG   = 4;
  localparam int CLK_HALF_PERIOD_MRMAC = 1;
  localparam int ARST_ACTIVATION = 17;

// ============================================================================================== --
// clock, reset
// ============================================================================================== --
  bit clk_cfg;
  bit clk_mrmac;

  initial begin
    clk_cfg = 1'b0;
    clk_mrmac = 1'b0;
  end

  always #CLK_HALF_PERIOD_CFG clk_cfg = ~clk_cfg;
  always #CLK_HALF_PERIOD_MRMAC clk_mrmac = ~clk_mrmac;

  bit a_rst_n;
  bit s_rstn_cfg;
  bit s_rstn_mrmac;

  initial begin
    a_rst_n = 1'b0;
    #ARST_ACTIVATION a_rst_n = 1'b1;
  end

  always_ff @(posedge clk_cfg) s_rstn_cfg <= a_rst_n;
  always_ff @(posedge clk_mrmac) s_rstn_mrmac <= a_rst_n;

// ============================================================================================== --
// End of test
// ============================================================================================== --
  bit end_of_test;
  int test_SCENARIO;

  initial begin
    wait (end_of_test);
    @(posedge clk_cfg) $display("%t > SUCCEED - All error tests completed!", $time);
    $finish;
  end

// ============================================================================================== --
// Error tracking
// ============================================================================================== --
  bit error;
  bit error_test_timeout;
  bit error_unexpected;

  assign error = error_test_timeout | error_unexpected;

  always_ff @(posedge clk_cfg)
    if (error) begin
      $display("%t > FAILURE !", $time);
      $finish;
    end

// ============================================================================================== --
// DUT signals
// ============================================================================================== --
  // AXI4-Lite interface
  logic [AXIL_ADD_W-1:0]                  s_axil_dma_awaddr;
  logic                                   s_axil_dma_awvalid;
  logic                                   s_axil_dma_awready;
  logic [AXIL_DATA_W-1:0]                 s_axil_dma_wdata;
  logic [AXIL_DATA_BYTES-1:0]             s_axil_dma_wstrb;
  logic                                   s_axil_dma_wvalid;
  logic                                   s_axil_dma_wready;
  logic [1:0]                             s_axil_dma_bresp;
  logic                                   s_axil_dma_bvalid;
  logic                                   s_axil_dma_bready;
  logic [AXIL_ADD_W-1:0]                  s_axil_dma_araddr;
  logic                                   s_axil_dma_arvalid;
  logic                                   s_axil_dma_arready;
  logic [AXIL_DATA_W-1:0]                 s_axil_dma_rdata;
  logic [1:0]                             s_axil_dma_rresp;
  logic                                   s_axil_dma_rvalid;
  logic                                   s_axil_dma_rready;

  // AXI4 HBM interface
  logic [ETH_PC-1:0][AXI4_ID_W-1:0]       m_axi4_awid;
  logic [ETH_PC-1:0][AXI4_ADD_W-1:0]      m_axi4_awaddr;
  logic [ETH_PC-1:0][7:0]                 m_axi4_awlen;
  logic [ETH_PC-1:0][2:0]                 m_axi4_awsize;
  logic [ETH_PC-1:0][1:0]                 m_axi4_awburst;
  logic [ETH_PC-1:0]                      m_axi4_awvalid;
  logic [ETH_PC-1:0]                      m_axi4_awready;
  logic [ETH_PC-1:0][AXI4_DATA_W-1:0]     m_axi4_wdata;
  logic [ETH_PC-1:0][(AXI4_DATA_W/8)-1:0] m_axi4_wstrb;
  logic [ETH_PC-1:0]                      m_axi4_wlast;
  logic [ETH_PC-1:0]                      m_axi4_wvalid;
  logic [ETH_PC-1:0]                      m_axi4_wready;
  logic [ETH_PC-1:0][AXI4_ID_W-1:0]       m_axi4_bid;
  logic [ETH_PC-1:0][1:0]                 m_axi4_bresp;
  logic [ETH_PC-1:0]                      m_axi4_bvalid;
  logic [ETH_PC-1:0]                      m_axi4_bready;

  logic [ETH_PC-1:0][AXI4_ID_W-1:0]       m_axi4_arid;
  logic [ETH_PC-1:0][AXI4_ADD_W-1:0]      m_axi4_araddr;
  logic [ETH_PC-1:0][7:0]                 m_axi4_arlen;
  logic [ETH_PC-1:0][2:0]                 m_axi4_arsize;
  logic [ETH_PC-1:0][1:0]                 m_axi4_arburst;
  logic [ETH_PC-1:0]                      m_axi4_arvalid;
  logic [ETH_PC-1:0]                      m_axi4_arready;
  logic [ETH_PC-1:0][AXI4_ID_W-1:0]       m_axi4_rid;
  logic [ETH_PC-1:0][AXI4_DATA_W-1:0]     m_axi4_rdata;
  logic [ETH_PC-1:0][1:0]                 m_axi4_rresp;
  logic [ETH_PC-1:0]                      m_axi4_rlast;
  logic [ETH_PC-1:0]                      m_axi4_rvalid;
  logic [ETH_PC-1:0]                      m_axi4_rready;

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
  logic inject_axi_write_error;
  logic [1:0] axi_error_type;  // SLVERR or DECERR

// ============================================================================================== --
// DUT instantiation
// ============================================================================================== --
  multi_hpu_dma #(
  ) multi_hpu_dma (
    .clk_eth_cfg            (clk_cfg           ),
    .resetn_eth_cfg         (s_rstn_cfg        ),
    .clk_eth_mrmac          (clk_mrmac         ),
    .resetn_eth_mrmac       (s_rstn_mrmac      ),

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

    .m_axi4_eth_hbm_arid    (m_axi4_arid   ),
    .m_axi4_eth_hbm_araddr  (m_axi4_araddr ),
    .m_axi4_eth_hbm_arlen   (m_axi4_arlen  ),
    .m_axi4_eth_hbm_arsize  (m_axi4_arsize ),
    .m_axi4_eth_hbm_arburst (m_axi4_arburst),
    .m_axi4_eth_hbm_arvalid (m_axi4_arvalid),
    .m_axi4_eth_hbm_arready (m_axi4_arready),
    .m_axi4_eth_hbm_rid     (m_axi4_rid    ),
    .m_axi4_eth_hbm_rdata   (m_axi4_rdata  ),
    .m_axi4_eth_hbm_rresp   (m_axi4_rresp  ),
    .m_axi4_eth_hbm_rlast   (m_axi4_rlast  ),
    .m_axi4_eth_hbm_rvalid  (m_axi4_rvalid ),
    .m_axi4_eth_hbm_rready  (m_axi4_rready ),
    .m_axi4_eth_hbm_awid    (m_axi4_awid   ),
    .m_axi4_eth_hbm_awaddr  (m_axi4_awaddr ),
    .m_axi4_eth_hbm_awlen   (m_axi4_awlen  ),
    .m_axi4_eth_hbm_awsize  (m_axi4_awsize ),
    .m_axi4_eth_hbm_awburst (m_axi4_awburst),
    .m_axi4_eth_hbm_awvalid (m_axi4_awvalid),
    .m_axi4_eth_hbm_awready (m_axi4_awready),
    .m_axi4_eth_hbm_wdata   (m_axi4_wdata  ),
    .m_axi4_eth_hbm_wstrb   (m_axi4_wstrb  ),
    .m_axi4_eth_hbm_wlast   (m_axi4_wlast  ),
    .m_axi4_eth_hbm_wvalid  (m_axi4_wvalid ),
    .m_axi4_eth_hbm_wready  (m_axi4_wready ),
    .m_axi4_eth_hbm_bid     (m_axi4_bid    ),
    .m_axi4_eth_hbm_bresp   (m_axi4_bresp  ),
    .m_axi4_eth_hbm_bvalid  (m_axi4_bvalid ),
    .m_axi4_eth_hbm_bready  (m_axi4_bready ),

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
    .clk   (clk_cfg            ),
    .rst_n (s_rstn_cfg         )
  );

  // Connect interface on testbench signals
  assign s_axil_dma_awaddr  = maxil_drv.awaddr;
  assign s_axil_dma_awvalid = maxil_drv.awvalid;
  assign s_axil_dma_wdata   = maxil_drv.wdata;
  assign s_axil_dma_wstrb   = maxil_drv.wstrb;
  assign s_axil_dma_wvalid  = maxil_drv.wvalid;
  assign s_axil_dma_bready  = maxil_drv.bready;
  assign s_axil_dma_araddr  = maxil_drv.araddr;
  assign s_axil_dma_arvalid = maxil_drv.arvalid;
  assign s_axil_dma_rready  = maxil_drv.rready;

  assign maxil_drv.awready = s_axil_dma_awready;
  assign maxil_drv.wready  = s_axil_dma_wready;
  assign maxil_drv.bresp   = s_axil_dma_bresp;
  assign maxil_drv.bvalid  = s_axil_dma_bvalid;
  assign maxil_drv.arready = s_axil_dma_arready;
  assign maxil_drv.rdata   = s_axil_dma_rdata;
  assign maxil_drv.rresp   = s_axil_dma_rresp;
  assign maxil_drv.rvalid  = s_axil_dma_rvalid;

// ============================================================================================== --
// Simple AXI4 Memory Model with Error Injection
// ============================================================================================== --
  // Memory for read data
  logic [255:0] axi_mem [2**16];

  // Initialize memory
  initial begin
    for (int i = 0; i < 2**16; i++) begin
      axi_mem[i] = {$urandom(), $urandom(), $urandom(), $urandom(),
                    $urandom(), $urandom(), $urandom(), $urandom()};
    end
  end

  // AXI Read response - simple model
  generate
    for (genvar pc = 0; pc < ETH_PC; pc++) begin : gen_axi_mem
      logic [7:0] rd_beat_cnt;
      logic [7:0] rd_len;
      logic [AXI4_ID_W-1:0] rd_id;
      logic rd_active;

      always_ff @(posedge clk_mrmac) begin
        if (~s_rstn_mrmac) begin
          m_axi4_arready[pc] <= 1'b1;
          m_axi4_rvalid[pc]  <= 1'b0;
          m_axi4_rlast[pc]   <= 1'b0;
          m_axi4_rresp[pc]   <= AXI4_OKAY;
          rd_active          <= 1'b0;
          rd_beat_cnt        <= '0;
        end else begin
          // Accept read address
          if (m_axi4_arvalid[pc] && m_axi4_arready[pc]) begin
            rd_len     <= m_axi4_arlen[pc];
            rd_id      <= m_axi4_arid[pc];
            rd_active  <= 1'b1;
            rd_beat_cnt <= '0;
            m_axi4_arready[pc] <= 1'b0;
          end

          // Generate read data
          if (rd_active) begin
            m_axi4_rvalid[pc] <= 1'b1;
            m_axi4_rid[pc]    <= rd_id;
            m_axi4_rdata[pc]  <= axi_mem[rd_beat_cnt[15:0]];
            m_axi4_rlast[pc]  <= (rd_beat_cnt == rd_len);

            if (m_axi4_rready[pc]) begin
              if (rd_beat_cnt == rd_len) begin
                rd_active <= 1'b0;
                m_axi4_rvalid[pc] <= 1'b0;
                m_axi4_rlast[pc]  <= 1'b0;
                m_axi4_arready[pc] <= 1'b1;
              end else begin
                rd_beat_cnt <= rd_beat_cnt + 1;
              end
            end
          end
        end
      end

      // AXI Write response with error injection
      logic [7:0] wr_beat_cnt;
      logic [7:0] wr_len;
      logic [AXI4_ID_W-1:0] wr_id;
      logic wr_addr_received;
      logic wr_data_done;

      always_ff @(posedge clk_mrmac) begin
        if (~s_rstn_mrmac) begin
          m_axi4_awready[pc] <= 1'b1;
          m_axi4_wready[pc]  <= 1'b1;
          m_axi4_bvalid[pc]  <= 1'b0;
          m_axi4_bresp[pc]   <= AXI4_OKAY;
          wr_addr_received   <= 1'b0;
          wr_data_done       <= 1'b0;
          wr_beat_cnt        <= '0;
        end else begin
          // Accept write address
          if (m_axi4_awvalid[pc] && m_axi4_awready[pc]) begin
            wr_len  <= m_axi4_awlen[pc];
            wr_id   <= m_axi4_awid[pc];
            wr_addr_received <= 1'b1;
            m_axi4_awready[pc] <= 1'b0;
            wr_beat_cnt <= '0;
          end

          // Accept write data
          if (m_axi4_wvalid[pc] && m_axi4_wready[pc]) begin
            if (m_axi4_wlast[pc]) begin
              wr_data_done <= 1'b1;
              m_axi4_wready[pc] <= 1'b0;
            end
          end

          // Generate write response
          if (wr_addr_received && wr_data_done && !m_axi4_bvalid[pc]) begin
            m_axi4_bvalid[pc] <= 1'b1;
            m_axi4_bid[pc]    <= wr_id;
            // Inject error if requested
            if (inject_axi_write_error) begin
              m_axi4_bresp[pc] <= axi_error_type;
            end else begin
              m_axi4_bresp[pc] <= AXI4_OKAY;
            end
          end

          // Clear write response when acknowledged
          if (m_axi4_bvalid[pc] && m_axi4_bready[pc]) begin
            m_axi4_bvalid[pc]  <= 1'b0;
            m_axi4_awready[pc] <= 1'b1;
            m_axi4_wready[pc]  <= 1'b1;
            wr_addr_received   <= 1'b0;
            wr_data_done       <= 1'b0;
          end
        end
      end
    end
  endgenerate

// ============================================================================================== --
// QSFP interface - simple loopback with delay and packet generation
// ============================================================================================== --
  // Default: accept all TX, no RX
  initial begin
    for (int i = 0; i < QSFP_LANE_NB; i++) begin
      qsfp_tx_tready[i] = 1'b1;
      qsfp_rx_tdata[i]  = '0;
      qsfp_rx_tkeep_user[i] = '0;
      qsfp_rx_tlast[i]  = 1'b0;
      qsfp_rx_tvalid[i] = 1'b0;
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
  logic [REG_DATA_W-1:0] stat_errors;
  mhdma_error_t          errors_struct;

  logic [HPU_ID_W-1:0]   random_hpu_id;
  logic [IOP_ID_W-1:0]   iop_id;
  logic [SRC_ADDR_W-1:0] src_addr;
  logic [DST_ADDR_W-1:0] dst_addr;
  logic [SIZE_B_W-1:0]   req_size_b;

  assign req_size_b = 'h4000;

// ============================================================================================== --
// Main Test Scenario
// ============================================================================================== --
  int scenario_id;

  initial begin
    maxil_drv.init();
    inject_axi_write_error = 1'b0;
    axi_error_type = AXI4_OKAY;
    scenario_id = 0;

    repeat(30) @(posedge clk_cfg);

    $display("\n================================================================");
    $display("  Initialization");
    $display("================================================================");

    init_config();

    // Read initial error register - should be 0
    maxil_drv.read_trans(MHDMA_SYSTEM_ERRORS_OFS, stat_errors);
    $display("%t > Initial error register: 0x%08x", $time, stat_errors);
    assert (stat_errors == 0) else begin
      $display("%t > [ERROR] Error register not zero at startup", $time);
      error_unexpected = 1'b1;
    end

    repeat(50) @(posedge clk_cfg);

    $display("\n================================================================");
    $display("  SCENARIO %0d: Testing error_id (multiple HPUs as current)", scenario_id);
    $display("================================================================");

    test_error_id();

    $display("\n================================================================");
    $display("  SCENARIO %0d: Testing write_error (AXI SLVERR/DECERR)", scenario_id);
    $display("================================================================");

    test_write_error();

    $display("\n================================================================");
    $display("  SCENARIO %0d: Testing a mismatch in sec num during CE", scenario_id);
    $display("================================================================\n");

    test_seq_num();

    $display("\n================================================================");
    $display("  SCENARIO %0d: Testing FIFO overflow errors", scenario_id);
    $display("================================================================\n");

    test_fifo_overflow_errors();

    repeat(100) @(posedge clk_cfg);
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
      maxil_drv.write_trans(MHDMA_HPU_ID_ZERO_OFS,  {1'b1, 3'b0, 4'h0, 24'hABCDE0});  // HPU 0 - current
      maxil_drv.write_trans(MHDMA_HPU_ID_ONE_OFS,   {1'b0, 3'b0, 4'h1, 24'hABCDE1});  // HPU 1
      maxil_drv.write_trans(MHDMA_HPU_ID_TWO_OFS,   {1'b0, 3'b0, 4'h2, 24'hABCDE2});  // HPU 2
      maxil_drv.write_trans(MHDMA_HPU_ID_THREE_OFS, {1'b0, 3'b0, 4'h3, 24'hABCDE3});  // HPU 3
      maxil_drv.write_trans(MHDMA_HPU_ID_FOUR_OFS,  {1'b0, 3'b0, 4'h4, 24'hABCDE4});  // HPU 4
      maxil_drv.write_trans(MHDMA_HPU_ID_FIVE_OFS,  {1'b0, 3'b0, 4'h5, 24'hABCDE5});  // HPU 5
      maxil_drv.write_trans(MHDMA_HPU_ID_SIX_OFS,   {1'b0, 3'b0, 4'h6, 24'hABCDE6});  // HPU 6
      maxil_drv.write_trans(MHDMA_HPU_ID_SEVEN_OFS, {1'b0, 3'b0, 4'h7, 24'hABCDE7});  // HPU 7

      repeat(20) @(posedge clk_cfg);
    end
  endtask

  // Test error_id by configuring multiple HPUs as current
  task automatic test_error_id();
    logic [REG_DATA_W-1:0] reg_error;
    mhdma_error_t          errors_t;
    begin

      // Configure TWO HPUs as current (invalid - not one-hot)
      maxil_drv.write_trans(MHDMA_HPU_ID_ZERO_OFS, {1'b1, 3'b0, 4'h0, 24'hABCDE0});
      maxil_drv.write_trans(MHDMA_HPU_ID_ONE_OFS,  {1'b1, 3'b0, 4'h1, 24'hABCDE1});

      // Wait for error to propagate through CDC
      repeat(50) @(posedge clk_cfg);

      // Read error status
      maxil_drv.read_trans(MHDMA_SYSTEM_ERRORS_OFS, reg_error);
      errors_t = mhdma_error_t'(reg_error);
      $display("%t > Error register value :  0x%08b", $time, reg_error);

      // Check error_id bit
      if (~errors_t.error_id) begin
        $display("%t > [ERROR] error_id NOT triggered", $time);
        error_unexpected = 1'b1;
      end

      // Restore correct configuration (only one HPU as current)
      maxil_drv.write_trans(MHDMA_HPU_ID_ONE_OFS, {1'b0, 3'b0, 4'h1, 24'hABCDE1});  // HPU 1 - not current

      repeat(20) @(posedge clk_cfg);
      scenario_id = scenario_id + 1;
    end
  endtask

  // Test write_error by injecting AXI write response errors
  // Flow: 1) Initiate read request via AXIL -> 2) Master sends RR packet -> 3) "Remote" sends CE packets back
  //       4) Master writes CE data to HBM -> 5) AXI slave returns error -> 6) write_error is set
  task automatic test_write_error();
    logic [REG_DATA_W-1:0] reg_error;
    logic [REG_DATA_W-1:0] read_req_id;
    logic [REG_DATA_W-1:0] read_req_addr;
    mhdma_error_t          errors_t;
    begin

      // Enable AXI write error injection BEFORE any write transactions
      inject_axi_write_error = 1'b1;
      axi_error_type = AXI4_SLVERR;

      // Step 1: Initiate a read request
      read_req_id   = {8'h42, REQ_ID_READ, 4'h1, 16'h4000};  // Request to HPU 1
      read_req_addr = {16'h5678, 16'h1234};  // dst_addr, src_addr

      maxil_drv.write_trans(MHDMA_REQUEST_REQ_ADDR_OFS, read_req_addr);
      maxil_drv.write_trans(MHDMA_REQUEST_REQ_ID_OFS, read_req_id);

      // Wait for read request to be sent out via TX
      repeat(200) @(posedge clk_cfg);

      // Step 2: Send ciphertext emission packets as if we're the remote HPU responding
      for (int pkt = 0; pkt < NB_PACKETS_FULL + 1; pkt++) begin
        send_ce_response_packet(8'h42, pkt[7:0], 16'h1234, 16'h5678);
        repeat(10) @(posedge clk_mrmac);
      end

      // Wait for write transactions and error to propagate through CDC
      repeat(1000) @(posedge clk_cfg);

      // Read error status
      maxil_drv.read_trans(MHDMA_SYSTEM_ERRORS_OFS, reg_error);
      errors_t = mhdma_error_t'(reg_error);
      $display("%t > Error register value :  0x%08b", $time, reg_error);

      // Check write_error bits (bits 3 and 4)
      assert (|errors_t.master_error.write_error) else begin
        $display("%t > [ERROR] write_error not triggered", $time);
        error_unexpected = 1'b1;
      end

      // Disable error injection
      inject_axi_write_error = 1'b0;
      axi_error_type = AXI4_OKAY;

      repeat(50) @(posedge clk_cfg);
      scenario_id = scenario_id + 1;
    end
  endtask

  // Test FIFO overflow errors
  task automatic test_fifo_overflow_errors();
    logic [REG_DATA_W-1:0] reg_error;
    logic [REG_DATA_W-1:0] read_req_id;
    logic [REG_DATA_W-1:0] read_req_addr;
    mhdma_error_t          errors_t;
    begin

      // error_fifo_rx_ovf Will overflow with this command
      // Send many notify packets without consuming them (error_fifo_nrx_commands_ovf)
      for (int i = 0; i < 2*RX_FIFO_DEPTH; i++) begin
        send_notify_packet(i[7:0], $urandom());
        repeat(5) @(posedge clk_mrmac);
      end

      maxil_drv.read_trans(MHDMA_SYSTEM_ERRORS_OFS, reg_error);
      $display("%t > Error register value :  0x%08b", $time, reg_error);
      errors_t = mhdma_error_t'(reg_error);

      assert (errors_t.slave_error.error_fifo_nrx_commands_ovf) else begin
        $display("%t > [ERROR] error_fifo_nrx_commands_ovf not triggered", $time);
        error_unexpected = 1'b1;
      end

      // because the system is now stuck with decoder fifo full we reset and reinit
      reset_system();

      // Send many read requests without processing them (error_rreq_command_queue_ovf)
      for (int i = 0; i < 2*RREQ_CMD_DEPTH; i++) begin
        send_read_request_packet(i[7:0], $urandom(), $urandom());
        repeat(5) @(posedge clk_mrmac);
      end

      maxil_drv.read_trans(MHDMA_SYSTEM_ERRORS_OFS, reg_error);
      $display("%t > Error register value :  0x%08b", $time, reg_error);
      errors_t = mhdma_error_t'(reg_error);

      assert (errors_t.slave_error.error_rreq_command_queue_ovf) else begin
        $display("%t > [ERROR] error_rreq_command_queue_ovf not triggered", $time);
        error_unexpected = 1'b1;
      end

      // because the system is now stuck with decoder fifo full we reset and reinit
      reset_system();

      // Send many ciphertext emission packets without consuming (error_fifo_rx_ovf)
      for (int i = 0; i < 2*RX_FIFO_DEPTH; i++) begin
        send_ciphertext_emission_packet();
        repeat(5) @(posedge clk_mrmac);
      end

      repeat(200) @(posedge clk_cfg);
      maxil_drv.read_trans(MHDMA_SYSTEM_ERRORS_OFS, reg_error);
      $display("%t > Error register value :  0x%08b", $time, reg_error);
      errors_t = mhdma_error_t'(reg_error);

      assert (errors_t.decoder_error.error_fifo_rx_ovf) else begin
        $display("%t > [ERROR] error_rreq_command_queue_ovf not triggered", $time);
        error_unexpected = 1'b1;
      end

      // because the system is now stuck
      reset_system();

      scenario_id = scenario_id + 1;
    end
  endtask

  // Test FIFO overflow errors
  task automatic test_seq_num();
    logic [REG_DATA_W-1:0] reg_error;
    logic [REG_DATA_W-1:0] read_req_id;
    logic [REG_DATA_W-1:0] read_req_addr;
    mhdma_error_t          errors_t;
    begin

      // Step 1: Initiate a read request
      read_req_id   = {8'h42, REQ_ID_READ, 4'h1, 16'h4000};  // Request to HPU 1
      read_req_addr = {16'h5678, 16'h1234};  // dst_addr, src_addr

      maxil_drv.write_trans(MHDMA_REQUEST_REQ_ADDR_OFS, read_req_addr);
      maxil_drv.write_trans(MHDMA_REQUEST_REQ_ID_OFS, read_req_id);

      // Wait for read request to be sent out via TX
      repeat(200) @(posedge clk_cfg);

      // Step 2: Send ciphertext emission packets as if we're the remote HPU responding
      // sec num value missmatch : istead of 6 we get 5
      for (int pkt = 0; pkt < NB_PACKETS_FULL + 1; pkt++) begin
        if (pkt == 6) begin
          send_ce_response_packet(8'h42, 5, 16'h1234, 16'h5678);
        end else begin
          send_ce_response_packet(8'h42, pkt[7:0], 16'h1234, 16'h5678);
        end
        repeat(10) @(posedge clk_mrmac);
      end

      maxil_drv.read_trans(MHDMA_SYSTEM_ERRORS_OFS, reg_error);
      errors_t = mhdma_error_t'(reg_error);
      $display("%t > Error register value :  0x%08b", $time, reg_error);

      assert (errors_t.master_error.seq_num_mismatch) else begin
        $display("%t > [ERROR] seq_num_mismatch not triggered", $time);
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

  task automatic send_notify_packet(
    input logic [IOP_ID_W-1:0]   iop_id_in,
    input logic [SRC_ADDR_W-1:0] src_addr_in
  );
    logic [MRMAC_AXIS_W-1:0] pkt_data [8];
    begin
      // Build notify packet header
      pkt_data[0] = {MAC_OUI, 24'hABCDE0, MAC_OUI[MAC_OUI_W-1:8]};
      pkt_data[1] = {MAC_OUI[7:0], 24'hABCDE1, ETH_LEN_MIN, LLC_DSAP, LLC_SSAP};
      pkt_data[2] = {LLC_CTRL, REQ_ID_NOTIFY, 4'h1, 8'h00, src_addr_in, 16'h0000, iop_id_in};
      pkt_data[3] = {16'h4000, 48'h0};
      for (int i = 4; i < 8; i++) pkt_data[i] = 64'h0; // Word 4-7: Padding

      // Send packet on lane 0
      for (int i = 0; i < 8; i++) begin
        @(posedge clk_mrmac);
        qsfp_rx_tdata[0]      <= byte_swap(pkt_data[i]);
        qsfp_rx_tkeep_user[0] <= (i < 7) ? 11'h0FF : 11'h00F;
        qsfp_rx_tlast[0]      <= (i == 7);
        qsfp_rx_tvalid[0]     <= 1'b1;
      end

      @(posedge clk_mrmac);
      qsfp_rx_tvalid[0]     <= 1'b0;
      qsfp_rx_tlast[0]      <= 1'b0;
      qsfp_rx_tkeep_user[0] <= 'h0;
    end
  endtask

  task automatic send_read_request_packet(
    input logic [IOP_ID_W-1:0] iop_id_in,
    input logic [SRC_ADDR_W-1:0] src_addr_in,
    input logic [DST_ADDR_W-1:0] dst_addr_in
  );
    logic [MRMAC_AXIS_W-1:0] pkt_data [8];
    begin
      // Build read request packet header
      pkt_data[0] = {MAC_OUI, 24'hABCDE0, MAC_OUI[MAC_OUI_W-1:8]};
      pkt_data[1] = {MAC_OUI[7:0], 24'hABCDE1, ETH_LEN_MIN, LLC_DSAP, LLC_SSAP};
      pkt_data[2] = {LLC_CTRL, REQ_ID_READ, 4'h1, 8'h00, src_addr_in, dst_addr_in, iop_id_in};
      pkt_data[3] = {16'h4000, 48'h0};
      for (int i = 4; i < 8; i++) pkt_data[i] = 64'h0;

      // Send packet on lane 0
      for (int i = 0; i < 8; i++) begin
        @(posedge clk_mrmac);
        qsfp_rx_tdata[0]      <= byte_swap(pkt_data[i]);
        qsfp_rx_tkeep_user[0] <= (i < 7) ? 11'h0FF : 11'h00F;
        qsfp_rx_tlast[0]      <= (i == 7);
        qsfp_rx_tvalid[0]     <= 1'b1;
      end

      @(posedge clk_mrmac);
      qsfp_rx_tvalid[0]     <= 1'b0;
      qsfp_rx_tlast[0]      <= 1'b0;
      qsfp_rx_tkeep_user[0] <= 'h0;
    end
  endtask

  task automatic send_ciphertext_emission_packet();
    logic [MRMAC_AXIS_W-1:0] pkt_data [200];  // Large packet for CT data
    int num_words;
    begin
      num_words = NB_WORDS_MAX;

      // Build ciphertext emission packet header
      pkt_data[0] = {MAC_OUI, 24'hABCDE0, MAC_OUI[MAC_OUI_W-1:8]};
      pkt_data[1] = {MAC_OUI[7:0], 24'hABCDE1, ETH_LEN_MIN, LLC_DSAP, LLC_SSAP};
      pkt_data[2] = {LLC_CTRL, REQ_ID_EMISSION, 4'h1, 8'h00, 16'h1234, 16'h5678, 8'h0};
      pkt_data[3] = {16'h4000, 48'h0};

      // Fill payload with data
      for (int i = 4; i < num_words; i++) begin
        pkt_data[i] = {$urandom(), $urandom()};
      end

      // Send packet on lane 0
      for (int i = 0; i < num_words; i++) begin
        @(posedge clk_mrmac);
        qsfp_rx_tdata[0]      <= byte_swap(pkt_data[i]);
        qsfp_rx_tkeep_user[0] <= (i < num_words-1) ? 11'h0FF : 11'h00F;
        qsfp_rx_tlast[0]      <= (i == num_words-1);
        qsfp_rx_tvalid[0]     <= 1'b1;
      end

      @(posedge clk_mrmac);
      qsfp_rx_tvalid[0] <= 1'b0;
      qsfp_rx_tlast[0]  <= 1'b0;
      qsfp_rx_tkeep_user[0] <= 'h0;
    end
  endtask

  task automatic send_ce_response_packet(
    input logic [IOP_ID_W-1:0]   iop_id_in,
    input logic [SEQ_NUM_W-1:0]  seq_num_in,
    input logic [SRC_ADDR_W-1:0] src_addr_in,
    input logic [DST_ADDR_W-1:0] dst_addr_in
  );
    logic [MRMAC_AXIS_W-1:0] pkt_data [200];
    int num_words;
    int payload_bytes;
    begin
      // Determine packet size based on sequence number
      if (seq_num_in < NB_PACKETS_FULL) begin
        num_words = NB_WORDS_MAX;
        payload_bytes = ETH_NB_BYTES_PAYLOAD;
      end else begin
        num_words = NB_WORDS_LAST_PACKET + NB_WORDS_CUST_HEADER_SIZE;
        payload_bytes = LAST_PACKET_BYTE_SIZE;
      end

      // Build CE packet header
      pkt_data[0] = {MAC_OUI, 24'hABCDE0, MAC_OUI[MAC_OUI_W-1:8]};
      pkt_data[1] = {MAC_OUI[7:0], 24'hABCDE1, payload_bytes[15:0], LLC_DSAP, LLC_SSAP};
      pkt_data[2] = {LLC_CTRL, REQ_ID_EMISSION, 4'h1, seq_num_in, src_addr_in, dst_addr_in, iop_id_in};
      pkt_data[3] = {16'h4000, 48'h0};

      // Fill payload with random data
      for (int i = 4; i < num_words; i++) begin
        pkt_data[i] = {$urandom(), $urandom()};
      end

      // Send packet on lane 0
      for (int i = 0; i < num_words; i++) begin
        @(posedge clk_mrmac);
        qsfp_rx_tdata[0]      <= byte_swap(pkt_data[i]);
        qsfp_rx_tkeep_user[0] <= (i < num_words-1) ? 11'h0FF : 11'h00F;
        qsfp_rx_tlast[0]      <= (i == num_words-1);
        qsfp_rx_tvalid[0]     <= 1'b1;
      end

      @(posedge clk_mrmac);
      qsfp_rx_tvalid[0] <= 1'b0;
      qsfp_rx_tlast[0]  <= 1'b0;
      qsfp_rx_tkeep_user[0] <= 'h0;
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
      read_req_addr = {dest_addr, src_addr};
      read_req_id = {iop_id, REQ_ID_READ, node_id, req_size_b};

      maxil_drv.write_trans(MHDMA_REQUEST_REQ_ADDR_OFS, read_req_addr);
      maxil_drv.write_trans(MHDMA_REQUEST_REQ_ID_OFS, read_req_id);
    end
  endtask
endmodule
