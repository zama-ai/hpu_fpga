// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : This is the explicit title of the testbench module
// ----------------------------------------------------------------------------------------------
//
// ==============================================================================================

`resetall
`timescale 1ns/10ps
module tb_dma;
  import axi_if_common_param_pkg::*;
  import axi_if_shell_axil_pkg::*;
  import hpu_regif_core_eth_2in3_pkg::*;

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int CLK_HALF_PERIOD_A = 4;
  localparam int CLK_HALF_PERIOD_B = 1;
  localparam int ARST_ACTIVATION = 17;

  localparam int LINE_NB = 4;
  localparam int AXIS_TDATA_W = 64;
  localparam int AXIS_TKEEP_W = 11;

  localparam int FIFO_DEPTH = 512;

  // number of words in an axi4-stream transactions
  localparam int WORD_NB = 25;
  localparam int NB_WORDS_FRAME = 15;

  // stalls for an arbitrary number of clock cycles
  localparam int ARBITRARY_STALL = 55;

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
  logic [LINE_NB-1:0][AXIS_TDATA_W-1:0] qsfp_tx_tdata;
  logic [LINE_NB-1:0][AXIS_TKEEP_W-1:0] qsfp_tx_tkeep_user;
  logic [LINE_NB-1:0]                   qsfp_tx_tlast;
  logic [LINE_NB-1:0]                   qsfp_tx_tvalid;
  logic [LINE_NB-1:0]                   qsfp_tx_tready;
  // == RX
  logic [LINE_NB-1:0][AXIS_TDATA_W-1:0] qsfp_rx_tdata;
  logic [LINE_NB-1:0][AXIS_TKEEP_W-1:0] qsfp_rx_tkeep_user;
  logic [LINE_NB-1:0]                   qsfp_rx_tlast;
  logic [LINE_NB-1:0]                   qsfp_rx_tvalid;

  // ============================================================================================== --
  // Design under test instance
  // ============================================================================================== --
  logic [LINE_NB-1:0] dummy_rx_tready;

  // gt configuration signals
  logic [7:0]         gt_line_rate;
  logic [2:0]         gt_loopback;
  logic [LINE_NB-1:0] gt_reset_rx_datapath;
  logic [LINE_NB-1:0] gt_reset_tx_datapath;
  logic [LINE_NB-1:0] gt_reset_all;
  logic [LINE_NB-1:0] gt_rx_reset_done;
  logic [LINE_NB-1:0] gt_tx_reset_done;

  dma #(
    .LINE_NB(LINE_NB),
    .AXIS_TDATA_W(AXIS_TDATA_W),
    .AXIS_TKEEP_W(AXIS_TKEEP_W),
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

  generate
    for (genvar gen_i=0 ; gen_i<LINE_NB; gen_i++ ) begin
      // Axi4-stream tx driver
      axis_drv_if #(
      .AXIS_DATA_W(AXIS_TDATA_W)
      ) axis_tx_driver ( .clk(clk_mrmac), .rst_n(s_rstn_mrmac));

      // Connect interface on testbench signals
      assign qsfp_rx_tdata[gen_i]  = axis_tx_driver.tdata;
      assign qsfp_rx_tvalid[gen_i] = axis_tx_driver.tvalid;
      assign axis_tx_driver.tready = dummy_rx_tready[gen_i];
    end
  endgenerate

  logic [7:0]  line_rate;
  logic [2:0]  line_loopback;
  logic [1:0]  line_select;
  logic [31:0] line_parameter;

  logic [LINE_NB-1:0] rst_rx_datapath;
  logic [LINE_NB-1:0] rst_tx_datapath;
  logic [LINE_NB-1:0] rst_all;
  logic [31:0]        reset_datpath;

  logic [31:0]        reset_monitor;

  logic [1:0] line_ref_tx_q[$:FIFO_DEPTH];
  logic [AXIS_TDATA_W-1:0] data_ref_tx_q[$:FIFO_DEPTH];
  logic [AXIS_TDATA_W-1:0] data_ref_rx_q[LINE_NB-1:0][$];

  logic en_rx_datapath;
  logic [AXIS_TDATA_W-1:0] expected_data;
  logic [AXIS_TDATA_W-1:0] read_data;

  initial begin
    logic [31:0] rdata;
    logic [AXIS_TDATA_W:0] tx_tdata;

    $display("%t > INFO: Initialization",$time);
    init_axis;
    maxil_drv_if.init();
    gt_rx_reset_done = 'h0;
    gt_tx_reset_done = 'h0;
    en_rx_datapath = 1'b0;
    repeat(20) @(posedge clk_control);

    // --------------------------------------------------------------------------------------------
    $display("%t > INFO: Register configuration",$time);
    //  We need to configure correctly different signals.
    //  By doing this we will verify axi4-lite communication with regfile
    //
    // 1 - we will read the first register segment, with dummy default values we know
    // 2 - we will setup line rate, loopback and line selection
    // once everything setup we can try to send a frame through register file on the correct lane
    // 3 - Send a frame using register file
    // 4 - trigger all qsfp-rx lanes + check that we read into fifo correct value on selected lane
    // 5 - reading that the fifo depths are accessible and has changed, that means not zeros
    // --------------------------------------------------------------------------------------------

    // (1) Reading dummy values -------------------------------------------------------------------
    maxil_drv_if.read_trans(ENTRY_ETH_2IN3_DUMMY_VAL0_OFS, rdata);
    if (rdata != 'h05050504) begin
      $display("%t >    ERROR: ENTRY_ETH_2IN3_DUMMY_VAL0_OFS: %x != h05050504",$time, rdata);
      error = 1'b1;
    end
    maxil_drv_if.read_trans(ENTRY_ETH_2IN3_DUMMY_VAL1_OFS, rdata);
    if (rdata != 'h15151515) begin
      $display("%t >    ERROR: ENTRY_ETH_2IN3_DUMMY_VAL1_OFS: %x != h15151515",$time, rdata);
      error = 1'b1;
    end
    maxil_drv_if.read_trans(ENTRY_ETH_2IN3_DUMMY_VAL2_OFS, rdata);
    if (rdata != 'h25252525) begin
      $display("%t >    ERROR: ENTRY_ETH_2IN3_DUMMY_VAL2_OFS: %x != h25252525",$time, rdata);
      error = 1'b1;
    end
    maxil_drv_if.read_trans(ENTRY_ETH_2IN3_DUMMY_VAL3_OFS, rdata);
    if (rdata != 'h35353535) begin
      $display("%t >    ERROR: ENTRY_ETH_2IN3_DUMMY_VAL3_OFS: %x != h35353535",$time, rdata);
      error = 1'b1;
    end
    $display("%t >    INFO: dummy section correctly read",$time);

    // (2) Applying configuration & checking signals are correctly set ----------------------------
    line_rate     = 8'hAB;  // random, no idea what it should be
    line_loopback = 3'b100; // 3 near end pcs loopback
    line_select   = 2'b10;  // 2nd line selected
    line_parameter = {19'b0, line_rate, line_loopback , line_select};
    maxil_drv_if.write_trans(LINE_PARAMETER_OFS, line_parameter);
    repeat(5) @(posedge clk_control);

    rst_rx_datapath = 4'b0100;
    rst_tx_datapath = 4'b1011;
    rst_all         = 4'b0101;
    reset_datpath = {20'h0, rst_rx_datapath, rst_tx_datapath, rst_all};
    maxil_drv_if.write_trans(RESET_DATAPATH_OFS, reset_datpath);
    repeat(5) @(posedge clk_control);

    if ((gt_line_rate == line_rate) && (gt_loopback == line_loopback) && (dut.line_sel == line_select)) begin
      $display("%t >    INFO: line parameter correctly configured",$time);
    end else begin
      $display("%t >    ERROR: configuration doesn't match to what have been selected",$time);
      error = 1'b1;
    end

    if ((gt_reset_rx_datapath == rst_rx_datapath) && (gt_reset_tx_datapath == rst_tx_datapath) && (gt_reset_all == rst_all)) begin
      $display("%t >    INFO: reset lines have been triggered correctly",$time);
    end else begin
      $display("%t >    ERROR: reset configuration has not been applied correctly",$time);
      error = 1'b1;
    end

    // read reset register
    gt_rx_reset_done= 4'b0101;
    gt_tx_reset_done= 4'b1010;
    repeat(5) @(posedge clk_control);
    maxil_drv_if.read_trans(RESET_MONITOR_OFS, reset_monitor);

    if(( reset_monitor[3:0] == gt_tx_reset_done) && ( reset_monitor[7:4] == gt_rx_reset_done)) begin
      $display("%t >    INFO: reset monitor register correctly read",$time);
    end else begin
      $display("%t >    ERROR: reset monitor has not been read correctly",$time);
      $display(" %x %x", gt_tx_reset_done, reset_monitor[3:0]);
      $display(" %x %x", gt_rx_reset_done, reset_monitor[7:4]);
      error = 1'b1;
    end

    $display("%t > INFO: Configuration successful\n",$time);

    // (3) Send a frame through regif -------------------------------------------------------------
    // On lane 2 we send a frame with known words: from 0 to wr_frame

    // lane qsfp tx ready must be 1 from here
    qsfp_tx_tready[line_select] = 1'b1;
    @(posedge clk_mrmac);

    maxil_drv_if.write_trans(FIFO_WRITE_NUMBER_OF_WORDS_OFS, NB_WORDS_FRAME);
    for (int wr_frame = 0; wr_frame < NB_WORDS_FRAME+1; wr_frame++) begin
      tx_tdata = {$urandom, $urandom};
      maxil_drv_if.write_trans(FIFO_WRITE_WORDS_TO_WRITE_A_OFS, tx_tdata[AXIL_DATA_W-1:0]);
      maxil_drv_if.write_trans(FIFO_WRITE_WORDS_TO_WRITE_B_OFS, tx_tdata[2*AXIL_DATA_W-1:AXIL_DATA_W]);
      data_ref_tx_q.push_front(tx_tdata);
      line_ref_tx_q.push_front(line_select);
    end

    // (4) Checks the rx datapath -----------------------------------------------------------------
    en_rx_datapath = 1'b1;
    repeat(3*NB_WORDS_FRAME) @(posedge clk_mrmac);
    en_rx_datapath = 1'b0;
    repeat(20) @(posedge clk_control);
    // read the first value to trigger fifo pull
    maxil_drv_if.read_trans(FIFO_READ_WORDS_TO_READ_B_OFS, read_data);
    repeat(20) @(posedge clk_control);

    for (int rd_i = 0; rd_i< NB_WORDS_FRAME; rd_i++ ) begin
      maxil_drv_if.read_trans(FIFO_READ_WORDS_TO_READ_A_OFS, read_data[AXIL_DATA_W-1:0]);
      maxil_drv_if.read_trans(FIFO_READ_WORDS_TO_READ_B_OFS, read_data[2*AXIL_DATA_W-1:AXIL_DATA_W]);
      expected_data = data_ref_rx_q[line_select].pop_back();

      if (expected_data == read_data) begin
        $display("%t >    INFO: reset lines have been triggered correctly",$time);
      end else begin
        $display("%t >    ERROR: aaaah %x %x",$time, expected_data, read_data);
        error = 1'b1;
      end

      repeat(20) @(posedge clk_control);
    end

    // (5) Checks that fifo depths are accessible -------------------------------------------------
    maxil_drv_if.read_trans(FIFO_WRITE_FIFO_WRITE_DATA_COUNT_OFS, read_data);

    if(read_data == 0) begin
      $display("%t >    ERROR: FIFO write data count has not been changed",$time);
      error = 1'b1;
    end

    maxil_drv_if.read_trans(FIFO_READ_FIFO_READ_DATA_COUNT_OFS, read_data);

    if(read_data == 0) begin
      $display("%t >    ERROR: FIFO read data count has not been changed",$time);
      error = 1'b1;
    end

    $display("%t > INFO: End simulation",$time);
    repeat(20) @(posedge clk_control);
    end_of_test = 1'b1;
  end

// ============================================================================================== --
// Tasks
// ============================================================================================== --

// initialize qsfp link
  task automatic init_axis;
  int lanes;
    for (lanes = '0; lanes < LINE_NB ; lanes++) begin
      qsfp_rx_tdata = 'h0;
      qsfp_rx_tkeep_user = 'h0;
      qsfp_rx_tlast = 'h0;
      qsfp_rx_tvalid = 'h0;
      qsfp_tx_tready = 'h0;
    end
  endtask

// ---------------------------------------------------------------------------------------------- --
// AXI4-stream
// ---------------------------------------------------------------------------------------------- --
  // we have LINE_NB lines + the tx one in input !
  logic [LINE_NB-1 + 1 :0][AXIS_TDATA_W-1:0] tdata;
  logic [LINE_NB-1 + 1 :0][AXIS_TKEEP_W-1:0] tkeep_user;
  logic [LINE_NB-1 + 1 :0]                   tlast;
  logic [LINE_NB-1 + 1 :0]                   tvalid;

  // for initialization
  initial begin
    for (int lanes = '0; lanes < LINE_NB+1 ; lanes++) begin
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
      for (int lane = 0; lane <= LINE_NB; lane++) begin
        automatic int lanes = lane;
        fork
          forever begin
            automatic int i;
            @(posedge clk_mrmac);
            for (i = 0; i < WORD_NB; i++) begin
              if (en_rx_datapath == 1'b1) begin
                tdata[lanes] = {$urandom,$urandom};
                tkeep_user[lanes] = $urandom;
                tlast[lanes] = (i == WORD_NB-1);
                tvalid[lanes] = 1'b1;

                if (lanes == LINE_NB) begin
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

always_ff @(posedge clk_mrmac)
  for (int i=1; i<LINE_NB; i=i+1)
    if (qsfp_rx_tvalid[i])
      data_ref_rx_q[i].push_front(qsfp_rx_tdata[i]);

  always_comb begin
    for (int lanes = '0; lanes < LINE_NB ; lanes++) begin
      qsfp_rx_tdata[lanes]      = tdata[lanes];
      qsfp_rx_tkeep_user[lanes] = tkeep_user[lanes];
      qsfp_rx_tlast[lanes]      = tlast[lanes];
      qsfp_rx_tvalid[lanes]     = tvalid[lanes];
    end
  end

endmodule
