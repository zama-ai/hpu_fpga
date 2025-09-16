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
module tb_fifo_handle;
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
  localparam int AXIS_TDATA_W  = 64;
  localparam int AXIS_TKEEP_W  = 11;

  // number of words in an axi4-stream transactions
  localparam int DATA_W = 32;
  localparam int FIFO_DEPTH = 512;
  localparam int NB_WORD_W = $clog2(FIFO_DEPTH)+1;

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
  // axi4-stream from RX selected line ----------------------------------------
  logic [AXIS_TDATA_W-1:0] qsfp_rx_tdata;
  logic [AXIS_TKEEP_W-1:0] qsfp_rx_tkeep_user;
  logic                    qsfp_rx_tlast;
  logic                    qsfp_rx_tvalid;
  // axi4-stream from TX selected line ----------------------------------------
  logic [AXIS_TDATA_W-1:0] qsfp_tx_tdata;
  logic [AXIS_TKEEP_W-1:0] qsfp_tx_tkeep_user;
  logic                    qsfp_tx_tlast;
  logic                    qsfp_tx_tvalid;
  logic                    qsfp_tx_tready;
  // to/from register interface -----------------------------------------------
  logic [NB_WORD_W-1:0] r_nb_word;
  logic [DATA_W-1:0]    r_word;
  logic [NB_WORD_W-1:0] r_wr_data_count;

  // ============================================================================================== --
  // Design under test instance
  // ============================================================================================== --
  fifo_handle # (
    .AXIS_TDATA_W(AXIS_TDATA_W),
    .AXIS_TKEEP_W(AXIS_TKEEP_W),
    .DATA_W(DATA_W),
    .SIM_ASSERT_CHK(1)
  ) fifo_handle (
    // system interface
    .clk_control       (clk_control),
    .s_rstn_control    (s_rstn_control),
    .clk_mrmac         (clk_mrmac),
    .s_rstn_mrmac      (s_rstn_mrmac),
    // axi4-stream insterface
    .qsfp_rx_tdata     (qsfp_rx_tdata),
    .qsfp_rx_tkeep_user(qsfp_rx_tkeep_user),
    .qsfp_rx_tlast     (qsfp_rx_tlast),
    .qsfp_rx_tvalid    (qsfp_rx_tvalid),
    .qsfp_tx_tdata     (qsfp_tx_tdata),
    .qsfp_tx_tkeep_user(qsfp_tx_tkeep_user),
    .qsfp_tx_tlast     (qsfp_tx_tlast),
    .qsfp_tx_tvalid    (qsfp_tx_tvalid),
    .qsfp_tx_tready    (qsfp_tx_tready),
    // register interface
    .r_nb_word         (r_nb_word),
    .r_word            (r_word),
    .r_wr_data_count   (r_wr_data_count)
  );

// ============================================================================================== --
// Scenario
// ============================================================================================== --
  initial begin
    logic [31:0] rdata;

    $display("%t > INFO: Initialization",$time);
    r_nb_word = 0;
    r_word = 0;
    repeat(100) @(posedge clk_control);

    $display("%t > INFO: ",$time);
    r_nb_word = 16;
    r_word = 0;
    @(posedge clk_control);

    for (int i = 0; i < 17 ; i++) begin
      @(posedge clk_control);
      r_word = {$urandom, $urandom};
    end
    repeat(20) @(posedge clk_control);

    for (int i = 0; i < 15 ; i++) begin
      @(posedge clk_control);
      r_word = {$urandom, $urandom};
    end

    repeat(20) @(posedge clk_control);

    for (int i = 0; i < 34 ; i++) begin
      @(posedge clk_control);
      r_word = {$urandom, $urandom};
    end

    $display("%t > INFO: End simulation",$time);
    repeat(200) @(posedge clk_control);
    end_of_test = 1'b1;
  end

// ============================================================================================== --
// Tasks
// ============================================================================================== --


endmodule
