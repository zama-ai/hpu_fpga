// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : This testbench only tests debug mode
// Debug mode corresponds to the control of one lane through register file
//
// ==============================================================================================

`resetall
`timescale 1ns/10ps
module tb_debug_mode;
  import axi_if_common_param_pkg::*;
  import axi_if_shell_axil_pkg::*;
  import hpu_regif_core_eth_2in3_pkg::*;
  import mhdma_pkg::*;

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int CLK_HALF_PERIOD_A = 4;
  localparam int CLK_HALF_PERIOD_B = 1;
  localparam int ARST_ACTIVATION = 17;

  localparam int MRMAC_AXIS_W = 64;
  localparam int MRMAC_TKEEP_W = 11;

  localparam int FIFO_DEPTH = 512;

  // number of words in an axi4-stream transactions
  localparam int WORD_NB = 25;
  localparam int NB_WORDS_FRAME = 15;

  // stalls for an arbitrary number of clock cycles
  localparam int ARBITRARY_STALL = 55;

  // OUI is not part of this mac address
  localparam [31:0] DEFAULT_SRC_MAC_ADDR_OFS = 'h2418F0;
  localparam [31:0] DEFAULT_DST_MAC_ADDR_OFS = 'h265A0D;
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
  logic [QSFP_LANE_NB-1:0] error_loopback;
  bit error_lb_nepcs; // near end pcs
  bit error_register;
  bit error_noise;
  bit error_tx_loop;
  bit error;

  assign error = |error_loopback | error_register | error_lb_nepcs | error_noise | error_tx_loop;
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
  // QSFP system interface ----------------------------------------------------
  // == TX
  logic [QSFP_LANE_NB-1:0][MRMAC_AXIS_W-1:0] qsfp_tx_tdata;
  logic [QSFP_LANE_NB-1:0][MRMAC_TKEEP_W-1:0] qsfp_tx_tkeep_user;
  logic [QSFP_LANE_NB-1:0]                   qsfp_tx_tlast;
  logic [QSFP_LANE_NB-1:0]                   qsfp_tx_tvalid;
  logic [QSFP_LANE_NB-1:0]                   qsfp_tx_tready;
  // == RX
  logic [QSFP_LANE_NB-1:0][MRMAC_AXIS_W-1:0] qsfp_rx_tdata;
  logic [QSFP_LANE_NB-1:0][MRMAC_TKEEP_W-1:0] qsfp_rx_tkeep_user;
  logic [QSFP_LANE_NB-1:0]                   qsfp_rx_tlast;
  logic [QSFP_LANE_NB-1:0]                   qsfp_rx_tvalid;

  // ============================================================================================== --
  // Design under test instance
  // ============================================================================================== --
  // gt configuration signals
  logic [7:0]         gt_line_rate;
  logic [2:0]         gt_loopback;
  logic [QSFP_LANE_NB-1:0] gt_reset_rx_datapath;
  logic [QSFP_LANE_NB-1:0] gt_reset_tx_datapath;
  logic [QSFP_LANE_NB-1:0] gt_reset_all;
  logic [QSFP_LANE_NB-1:0] gt_rx_reset_done;
  logic [QSFP_LANE_NB-1:0] gt_tx_reset_done;

  // [section] line parameter -------------------------------------------------
  logic [31:0] line_parameter;
  logic        debug_flag;
  logic [2:0]  line_loopback;
  logic [7:0]  line_rate;
  logic [1:0]  line_select;

  assign line_parameter[1:0]   = line_select;
  assign line_parameter[4:2]   = line_loopback;
  assign line_parameter[12:5]  = line_rate;
  assign line_parameter[27:13] = 'h0;
  assign line_parameter[31]    = debug_flag;

  // [section] line parameter -------------------------------------------------
  logic [31:0] line_debug;
  logic        reset_registers;
  logic        tx_loop;
  logic        rx_to_tx;

  assign line_debug[28:0] = 'h0;
  assign line_debug[29]   = rx_to_tx;
  assign line_debug[30]   = tx_loop;
  assign line_debug[31]   = reset_registers;

  // [section] reset ----------------------------------------------------------
  logic [31:0]        reset_parameter;
  logic [QSFP_LANE_NB-1:0] rst_rx_datapath;
  logic [QSFP_LANE_NB-1:0] rst_tx_datapath;
  logic [QSFP_LANE_NB-1:0] rst_all;

  assign reset_parameter = {20'h0, rst_rx_datapath, rst_tx_datapath, rst_all};

  // monitoring of reset done
  logic [31:0] reset_monitor;

  // DUT ------------------------------------------------------------------------------------------
  multi_hpu_dma #(
    .FIFO_DEPTH(FIFO_DEPTH)
  ) dut (
    .clk_eth_cfg   (clk_control    ),
    .resetn_eth_cfg(s_rstn_control ),

    .clk_eth_mrmac   (clk_mrmac    ),
    .resetn_eth_mrmac(s_rstn_mrmac ),

    .s_axil_dma_awaddr(s_axil_dma_awaddr),
    .s_axil_dma_awvalid(s_axil_dma_awvalid),
    .s_axil_dma_awready(s_axil_dma_awready),
    .s_axil_dma_wdata(s_axil_dma_wdata),
    .s_axil_dma_wstrb(s_axil_dma_wstrb),
    .s_axil_dma_wvalid(s_axil_dma_wvalid),
    .s_axil_dma_wready(s_axil_dma_wready),
    .s_axil_dma_bresp(s_axil_dma_bresp),
    .s_axil_dma_bvalid(s_axil_dma_bvalid),
    .s_axil_dma_bready(s_axil_dma_bready),
    .s_axil_dma_araddr(s_axil_dma_araddr),
    .s_axil_dma_arvalid(s_axil_dma_arvalid),
    .s_axil_dma_arready(s_axil_dma_arready),
    .s_axil_dma_rdata(s_axil_dma_rdata),
    .s_axil_dma_rresp(s_axil_dma_rresp),
    .s_axil_dma_rvalid(s_axil_dma_rvalid),
    .s_axil_dma_rready(s_axil_dma_rready),

    .qsfp_tx_tdata(qsfp_tx_tdata),
    .qsfp_tx_tkeep_user(qsfp_tx_tkeep_user),
    .qsfp_tx_tlast(qsfp_tx_tlast),
    .qsfp_tx_tvalid(qsfp_tx_tvalid),
    .qsfp_tx_tready(qsfp_tx_tready),

    .qsfp_rx_tdata(qsfp_rx_tdata),
    .qsfp_rx_tkeep_user(qsfp_rx_tkeep_user),
    .qsfp_rx_tlast(qsfp_rx_tlast),
    .qsfp_rx_tvalid(qsfp_rx_tvalid),

    .gt_line_rate(gt_line_rate),
    .gt_loopback(gt_loopback),
    .gt_reset_rx_datapath(gt_reset_rx_datapath),
    .gt_reset_tx_datapath(gt_reset_tx_datapath),
    .gt_reset_all(gt_reset_all),
    .gt_rx_reset_done(gt_rx_reset_done),
    .gt_tx_reset_done(gt_tx_reset_done)
);

  logic [QSFP_LANE_NB-1:0][MRMAC_AXIS_W-1:0] rx_tdata;
  logic [QSFP_LANE_NB-1:0][MRMAC_TKEEP_W-1:0] rx_tkeep_user;
  logic [QSFP_LANE_NB-1:0]                   rx_tlast;
  logic [QSFP_LANE_NB-1:0]                   rx_tvalid;

  // ----------------------------------------------------------------------------------------------
  model_loopback # () model_loopback (
    .clk_eth_mrmac   (clk_mrmac),
    .resetn_eth_mrmac(s_rstn_mrmac),

    // from DMA
    .qsfp_tx_tdata     (qsfp_tx_tdata),
    .qsfp_tx_tkeep_user(qsfp_tx_tkeep_user),
    .qsfp_tx_tlast     (qsfp_tx_tlast),
    .qsfp_tx_tvalid    (qsfp_tx_tvalid),
    // I want to be able to control qsfp_tx_tready within this tb

    // to DMA
    .qsfp_rx_tdata     (rx_tdata),
    .qsfp_rx_tkeep_user(rx_tkeep_user),
    .qsfp_rx_tlast     (rx_tlast),
    .qsfp_rx_tvalid    (rx_tvalid),

    .loopback          (line_loopback)
  );

// ============================================================================================== --
// Scenario
// ============================================================================================== --
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

  logic [63:0] clk_count;
  logic [63:0] valid_words_count;
  logic [63:0] sop_count;

  logic [MRMAC_AXIS_W-1:0] data_noise_ref_rx_q[QSFP_LANE_NB-1:0][$];
  logic [MRMAC_AXIS_W-1:0] data_lb_ref_rx_q[QSFP_LANE_NB-1:0][$];

  logic enable_noise_on_rx;
  logic [MRMAC_AXIS_W-1:0] read_data;

  logic [31:0] rdata;
  initial begin
    maxil_drv_if.init();
    enable_noise_on_rx = 1'b0;

    reset_registers = 'h0;
    tx_loop         = 'h0;
    rx_to_tx        = 'h0;
    repeat(20) @(posedge clk_control);
    $display("\n"); // just to unclog view from FIFO warnings

    $display("A - Initial register check and definition");
    init_registers();

    $display("B - Setting near end pcs and launching a frame - receiving data");
    test_lb_near_end_pcs();

    $display("C - looping over tx to measure throughput");
    debug_mode_tx_loop();

    $display("D - Sending to TX all the values we receive from RX");
    debug_mode_rx_2_tx();

    $display("E - When we receive noise on RX, do we see it correctly in the fifo ?");
    test_receive_noise_rx();

    $display("%t > INFO: End simulation",$time);
    repeat(20) @(posedge clk_control);
    end_of_test = 1'b1;
  end

// ============================================================================================== --
// Tasks
// ============================================================================================== --
  task automatic init_registers;
    begin
    // (1) Reading MAC REGISTERS ------------------------------------------------------------------
      maxil_drv_if.read_trans(MHDMA_SYSTEM_LANE_OFS, rdata);
      assert (rdata == 'h0) else begin
        $display("%t > ERROR:register SYSTEM_LINE_OFS not correctly read %h",$time, rdata);
        error_register = 1'b1;
      end
      // (2) ASSIGN REGISTERS & CHECK -------------------------------------------------------------
    line_rate     = 8'hAB;  // random, no idea what it should be
    line_loopback = 3'b100; // 3 near end pcs loopback
    line_select   = 2'b10;  // 2nd line selected
    debug_flag    = 1'b0;
    @(posedge clk_control);

    maxil_drv_if.write_trans(MHDMA_SYSTEM_LANE_OFS, line_parameter);

    rst_rx_datapath = 4'b0100;
    rst_tx_datapath = 4'b1011;
    rst_all         = 4'b0101;
    @(posedge clk_control);

    maxil_drv_if.write_trans(MHDMA_RESET_DATAPATH_OFS, reset_parameter);

    if ((gt_line_rate == line_rate) && (gt_loopback == line_loopback) && (dut.line_sel == line_select)) begin
      $display("    > line parameter correctly configured");
    end else begin
      $display("%t >    ERROR: configuration doesn't match to what have been selected",$time);
      error_register = 1'b1;
    end

    if ((gt_reset_rx_datapath == rst_rx_datapath) && (gt_reset_tx_datapath == rst_tx_datapath) && (gt_reset_all == rst_all)) begin
      $display("    > reset lines have been triggered correctly");
    end else begin
      $display("%t >    ERROR: reset configuration has not been applied correctly",$time);
      error_register = 1'b1;
    end

    // read reset register
    gt_rx_reset_done= 4'b1111;
    gt_tx_reset_done= 4'b1111;
    @(posedge clk_control);

    maxil_drv_if.read_trans(MHDMA_RESET_MONITOR_OFS, reset_monitor);

    if(( reset_monitor[3:0] == gt_tx_reset_done) && ( reset_monitor[7:4] == gt_rx_reset_done)) begin
      $display("    > reset monitor register correctly read");
    end else begin
      $display("%t >    ERROR: reset monitor has not been read correctly",$time);
      error_register = 1'b1;
    end

    // (4) Setting up credible values -------------------------------------------------------------
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

  task automatic test_lb_near_end_pcs;
    logic [MRMAC_AXIS_W:0] tx_tdata;
    begin
      // (1) setting up configuration -------------------------------------------------------------
      $display("    > Configuration: Debug mode - Lane 0 - near end pcs");
      debug_flag    = 1'b1;
      line_select   = 2'b00;
      line_loopback = 3'b010;
      @(posedge clk_control);

      maxil_drv_if.write_trans(MHDMA_SYSTEM_LANE_OFS, line_parameter);

      // ready starts
      qsfp_tx_tready[line_select] = 1'b1;
      @(posedge clk_control);

    // (2) write to the fifo ----------------------------------------------------------------------
      $display("    > writing NB_WORDS_FRAME %0x words into FIFO", NB_WORDS_FRAME);
      maxil_drv_if.write_trans(FIFO_WRITE_NUMBER_OF_WORDS_OFS, NB_WORDS_FRAME);
      for (int wr_frame = 0; wr_frame < NB_WORDS_FRAME; wr_frame++) begin
        tx_tdata = {$urandom, $urandom};
        maxil_drv_if.write_trans(FIFO_WRITE_WORDS_TO_WRITE_A_OFS, tx_tdata[AXIL_DATA_W-1:0]);
        maxil_drv_if.write_trans(FIFO_WRITE_WORDS_TO_WRITE_B_OFS, tx_tdata[2*AXIL_DATA_W-1:AXIL_DATA_W]);
        if (wr_frame == NB_WORDS_FRAME-1) begin
          repeat(11) @(posedge clk_mrmac);
          qsfp_tx_tready[line_select] = 1'b0;
          repeat(5) @(posedge clk_mrmac);
          qsfp_tx_tready[line_select] = 1'b1;
        end
      end

      // (3) Checks that fifo depths are accessible and has changed -----------------------------
      $display("    > check that FIFO depth registers are accessible and not zeros");
      maxil_drv_if.read_trans(FIFO_WRITE_FIFO_WRITE_DATA_COUNT_OFS, read_data);

      if(read_data == 0) begin
        $display("%t >    ERROR: FIFO write data count has not changed",$time);
        error_lb_nepcs = 1'b1;
      end

      maxil_drv_if.read_trans(FIFO_READ_FIFO_READ_DATA_COUNT_OFS, read_data);

      if(read_data == 0) begin
        $display("%t >    ERROR: FIFO read data count has not changed",$time);
        error_lb_nepcs = 1'b1;
      end

      // has the register count from start of packet to start of packet changed ?
      maxil_drv_if.read_trans(MHDMA_STAT_SOP_CNT_A_OFS, sop_count[31:0]);
      maxil_drv_if.read_trans(MHDMA_STAT_SOP_CNT_B_OFS, sop_count[63:32]);


      assert (sop_count == 11) else begin
        $display("%t >    ERROR: unexpected sop count %0d", $time, sop_count);
        error_lb_nepcs = 1'b1;
      end

      empty_fifo();
    end
  endtask

  task automatic test_receive_noise_rx;
    logic [MRMAC_AXIS_W-1:0] expected_data[QSFP_LANE_NB-1:0];
    begin
      // setting up configuration -----------------------------------------------------------------
      // Debug mode - Lane 0 - near end pcs
      debug_flag    = 1'b1;
      line_select   = 2'b00;
      line_loopback = 3'b000;
      @(posedge clk_control);

      maxil_drv_if.write_trans(MHDMA_SYSTEM_LANE_OFS, line_parameter);

      // Checks the rx datapath -------------------------------------------------------------------
      enable_noise_on_rx = 1'b1;
      repeat(3*NB_WORDS_FRAME) @(posedge clk_mrmac);
      enable_noise_on_rx = 1'b0;
      repeat(20) @(posedge clk_control);
      // read the first value to trigger fifo pull
      maxil_drv_if.read_trans(FIFO_READ_WORDS_TO_READ_B_OFS, read_data);
      repeat(20) @(posedge clk_control);

      for (int rd_i = 0; rd_i< NB_WORDS_FRAME; rd_i++ ) begin
        maxil_drv_if.read_trans(FIFO_READ_WORDS_TO_READ_A_OFS, read_data[AXIL_DATA_W-1:0]);
        maxil_drv_if.read_trans(FIFO_READ_WORDS_TO_READ_B_OFS, read_data[2*AXIL_DATA_W-1:AXIL_DATA_W]);
        expected_data[line_select] = data_noise_ref_rx_q[line_select].pop_back();

        assert (expected_data[line_select] == read_data) else begin
          $display("%t >    ERROR: error while reading into the fifo: unexpected value %x %x",$time, expected_data[line_select], read_data);
          error_noise = 1'b1;
        end

        repeat(20) @(posedge clk_control);
      end
    end
  endtask


  // task automatic measure_sop_2_sop();
  // endtask

  task automatic debug_mode_tx_loop();
    // needs to be checked that
    //  1 configuration of tx_loop mode
    //  2 send an ethernet frame that will be looped
    //  3 we can stop properly the mode
    //  x do we see the correct values in loopback ?
    //  x do the counters properly works ?
    //  x reset the register and check their value are now zero
    logic [MRMAC_AXIS_W:0] tx_tdata;
   begin
      // (1) setting tx_loop configuration --------------------------------------------------------
      debug_flag    = 1'b1;
      line_loopback = 3'b010; // 3 near end pcs loopback
      line_select   = 2'b01;  // 1st line selected
      tx_loop       = 1'b1;

      maxil_drv_if.write_trans(MHDMA_SYSTEM_LANE_OFS, line_parameter);
      maxil_drv_if.write_trans(MHDMA_LANE_DEBUG_OFS,  line_debug);

      qsfp_tx_tready[line_select] = 1'b1;

      // what values are clk_count and valid_words_count?
      maxil_drv_if.read_trans(MHDMA_STAT_CLK_A_OFS, clk_count[31:00]);
      maxil_drv_if.read_trans(MHDMA_STAT_CLK_B_OFS, clk_count[63:32]);
      maxil_drv_if.read_trans(MHDMA_STAT_VALID_WORDS_A_OFS, valid_words_count[31:00]);
      maxil_drv_if.read_trans(MHDMA_STAT_VALID_WORDS_B_OFS, valid_words_count[63:32]);

      $display("    >  @ init nb valid words %0d and nb of clock went by %0d", valid_words_count, clk_count);

      // (2) sending ethernet frame ---------------------------------------------------------------
      maxil_drv_if.write_trans(FIFO_WRITE_NUMBER_OF_WORDS_OFS, 64);

      for (int wr_frame = 0; wr_frame < 64; wr_frame++) begin
        tx_tdata = {$urandom, $urandom};
        maxil_drv_if.write_trans(FIFO_WRITE_WORDS_TO_WRITE_A_OFS, tx_tdata[AXIL_DATA_W-1:0]);
        maxil_drv_if.write_trans(FIFO_WRITE_WORDS_TO_WRITE_B_OFS, tx_tdata[2*AXIL_DATA_W-1:AXIL_DATA_W]);
      end

      repeat(50) @(clk_control);

      // (3) stopping mode ------------------------------------------------------------------------
      tx_loop = 1'b0;
      @(clk_control);

      maxil_drv_if.write_trans(MHDMA_LANE_DEBUG_OFS,  line_debug);

      maxil_drv_if.read_trans(MHDMA_STAT_CLK_A_OFS, clk_count[31:00]);
      maxil_drv_if.read_trans(MHDMA_STAT_CLK_B_OFS, clk_count[63:32]);
      maxil_drv_if.read_trans(MHDMA_STAT_VALID_WORDS_A_OFS, valid_words_count[31:00]);
      maxil_drv_if.read_trans(MHDMA_STAT_VALID_WORDS_B_OFS, valid_words_count[63:32]);

      $display("    >  after 50cc: nb valid words %0d and nb of clock went by %0d", valid_words_count, clk_count);

      assert ((valid_words_count != 0) || ( clk_count != 0  )) else begin
              $display("%t >    ERROR: error while reading txloop registers, they have not moved",$time);
              error_tx_loop = 1'b1;
            end
      // emptying the FIFO
      empty_fifo();
   end
  endtask

  task automatic debug_mode_rx_2_tx();
    begin
      // let's reset the registers
      reset_registers = 1'b1;
      @(posedge clk_control);

      maxil_drv_if.write_trans(MHDMA_LANE_DEBUG_OFS,  line_debug);

      line_loopback      = 3'b000;
      reset_registers    = 1'b0;
      rx_to_tx           = 1'b1;

      @(posedge clk_control);
      maxil_drv_if.write_trans(MHDMA_LANE_DEBUG_OFS,  line_debug);
      maxil_drv_if.write_trans(MHDMA_SYSTEM_LANE_OFS, line_parameter);


      enable_noise_on_rx = 1'b1;

      repeat(50) @(posedge clk_control);

      enable_noise_on_rx = 1'b0;
      rx_to_tx           = 1'b0;

      @(posedge clk_control);
      maxil_drv_if.write_trans(MHDMA_LANE_DEBUG_OFS,  line_debug);

      maxil_drv_if.read_trans(MHDMA_STAT_CLK_A_OFS, clk_count[31:00]);
      maxil_drv_if.read_trans(MHDMA_STAT_CLK_B_OFS, clk_count[63:32]);
      maxil_drv_if.read_trans(MHDMA_STAT_VALID_WORDS_A_OFS, valid_words_count[31:00]);
      maxil_drv_if.read_trans(MHDMA_STAT_VALID_WORDS_B_OFS, valid_words_count[63:32]);
      $display(" nb of valid words %0d and nb of clock went by %0d after rx to tx mode", valid_words_count, clk_count);

      empty_fifo();
      for (int lane = 0; lane < QSFP_LANE_NB ; lane++) begin
        data_noise_ref_rx_q[lane].delete();
      end
    end
  endtask

  task automatic empty_fifo();
    $display("    > emptying FIFO for next test");
    // this task is testing the loopback and we check that the values are back on rx
    // Let's empty the fifo in order to start clean for the next test that will check FIFO values
    // TODO: create a way to empty the debug fifo more cleanly
    // TODO: When there is a stall in t_ready we see duplicated words in the FIFO
    maxil_drv_if.read_trans(FIFO_READ_WORDS_TO_READ_B_OFS, read_data);
    for (int rd_i = 0; rd_i< 512; rd_i++ ) begin
      maxil_drv_if.read_trans(FIFO_READ_WORDS_TO_READ_B_OFS, read_data[2*AXIL_DATA_W-1:AXIL_DATA_W]);
    end
  endtask //automatic

// ---------------------------------------------------------------------------------------------- --
// AXI4-stream
// ---------------------------------------------------------------------------------------------- --
  // we have QSFP_LANE_NB lines + the tx one in input !
  logic [QSFP_LANE_NB-1 + 1 :0][MRMAC_AXIS_W-1:0] tdata;
  logic [QSFP_LANE_NB-1 + 1 :0][MRMAC_TKEEP_W-1:0] tkeep_user;
  logic [QSFP_LANE_NB-1 + 1 :0]                   tlast;
  logic [QSFP_LANE_NB-1 + 1 :0]                   tvalid;

  // for initialization
  initial begin
    for (int lanes = '0; lanes < QSFP_LANE_NB+1 ; lanes++) begin
      tdata[lanes]      = 'h0;
      tkeep_user[lanes] = 'h0;
      tlast[lanes]      = 'h0;
      tvalid[lanes]     = 'h0;
    end
  end

  // Send one AXIS transaction of WORD_NB beats
  initial begin
    wait (s_rstn_mrmac);
    // Launch all lanes concurrently
    // each iterators needs an automatic copy for each forked process
    fork
      for (int lane = 0; lane <= QSFP_LANE_NB; lane++) begin
        automatic int lanes = lane;
        fork
          forever begin
            automatic int i;
            @(posedge clk_mrmac);
            for (i = 0; i < WORD_NB; i++) begin
              if (enable_noise_on_rx == 1'b1) begin
                tdata[lanes] = {$urandom,$urandom};
                tkeep_user[lanes] = $urandom;
                tlast[lanes] = (i == WORD_NB-1);
                tvalid[lanes] = 1'b1;

                if (lanes == QSFP_LANE_NB) begin
                  do @(posedge clk_mrmac); while (!(tvalid[lanes]));
                end else begin
                  @(posedge clk_mrmac);
                end

                tvalid[lanes] = 1'b0;
                tlast[lanes] = 1'b0;
              end else begin
                tdata = 'h0;
                tkeep_user = 'h0;
                tlast = 'h0;
                tvalid = 'h0;
              end
            end
          end
        join_none
      end
    join_none
  end

  // checker: push noise into queue when signal is up
  // assert is directly in the task
  always_ff @(posedge clk_mrmac)
    for (int i=0; i<QSFP_LANE_NB; i=i+1)
      if (qsfp_rx_tvalid[i])
        if (enable_noise_on_rx)
          data_noise_ref_rx_q[i].push_front(qsfp_rx_tdata[i]);

  // Loopback -------------------------------------------------------------------------------------
  // checker: push loopback values into queue
  always_ff @(posedge clk_mrmac)
    for (int i=0; i<QSFP_LANE_NB; i=i+1)
      if (qsfp_tx_tvalid[i] && (gt_loopback != 0))
          data_lb_ref_rx_q[i].push_front(qsfp_tx_tdata[i]);

  // checker: are values from loopback correct ?
  generate
    logic [MRMAC_AXIS_W-1:0] expected_data[QSFP_LANE_NB-1:0];
    for (genvar lanes = '0; lanes < QSFP_LANE_NB ; lanes++) begin
      always_ff @(posedge clk_mrmac) begin
        if (gt_loopback != 0) begin
          if (qsfp_rx_tvalid[lanes] == 1'b1) begin
            expected_data[lanes] = data_lb_ref_rx_q[lanes].pop_back();

            assert (expected_data[lanes] == qsfp_rx_tdata[lanes]) else begin
              $display("%t >    ERROR: error while reading into the fifo: unexpected value %x %x",$time, expected_data[lanes], qsfp_rx_tdata[lanes]);
              error_loopback[lanes] = 1'b1;
            end
          end
        end
      end
    end
  endgenerate

  always_comb begin
    for (int lanes = '0; lanes < QSFP_LANE_NB ; lanes++) begin
      if (enable_noise_on_rx) begin
        qsfp_rx_tdata[lanes]      = tdata[lanes];
        qsfp_rx_tkeep_user[lanes] = tkeep_user[lanes];
        qsfp_rx_tlast[lanes]      = tlast[lanes];
        qsfp_rx_tvalid[lanes]     = tvalid[lanes];
      end else begin
        qsfp_rx_tdata[lanes]      = rx_tdata[lanes];
        qsfp_rx_tkeep_user[lanes] = rx_tkeep_user[lanes];
        qsfp_rx_tlast[lanes]      = rx_tlast[lanes];
        qsfp_rx_tvalid[lanes]     = rx_tvalid[lanes];
      end
    end
  end
endmodule
