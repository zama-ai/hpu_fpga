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
  localparam int FIFO_DEPTH = 512;
  localparam int NB_WORD_W = $clog2(FIFO_DEPTH)+1;

  // arbitrary number of words for simulation
  localparam int NB_WORDS = 18;

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
  logic error_data;

  always_ff @(posedge clk_control)
    if (error_data) begin
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
  logic [NB_WORD_W-1:0]    r_nb_word;
  logic [AXIS_TDATA_W-1:0] r_wr_word;
  logic [NB_WORD_W-1:0]    r_wr_data_count;
  logic [NB_WORD_W-1:0]    r_rd_data_count;
  logic [AXIS_TDATA_W-1:0] r_rd_word;
  logic                    read_ack;
  logic                    write_ack;
  logic                    tx_loop;
  logic                    rx_to_tx;
  logic                    reset_registers;

  // ============================================================================================== --
  // Design under test instance
  // ============================================================================================== --
  fifo_handle # (
    .AXIS_TDATA_W(AXIS_TDATA_W),
    .AXIS_TKEEP_W(AXIS_TKEEP_W),
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
    .r_wr_word         (r_wr_word),
    .r_wr_data_count   (r_wr_data_count),
    .r_rd_data_count   (r_rd_data_count),
    .r_rd_word         (r_rd_word),
    .read_ack          (read_ack),
    .write_ack         (write_ack),

    .reset_registers   (reset_registers),

    .tx_loop           (tx_loop),
    .rx_to_tx          (rx_to_tx)
  );

// ============================================================================================== --
// Scenario
// ============================================================================================== --
  logic trigger_rx_link;

  initial begin
    $display("%t > INFO: Initialization",$time);
    read_ack = 1'b0;
    write_ack = 1'b0;
    r_nb_word = 0;
    r_wr_word = 0;
    qsfp_tx_tready = 1'b0;
    trigger_rx_link = 1'b0;
    tx_loop = 1'b0;
    rx_to_tx = 1'b0;
    reset_registers = 1'b0;

    repeat(100) @(posedge clk_control);
    qsfp_tx_tready = 1'b1; // let's consider tx ready always 1

    // --------------------------------------------------------------------------------------------
    $display("%t > INFO: Test sequence on TX link",$time);
    // with an arbitrary given number of word we will
    //  1- write nb_word+1 into the fifo
    //  -- wait
    //  2- write nb_word-3 into the fifo
    //  -- wait
    //  3- write 2*r_nb_word into the fifo
    //
    // ` at the end of (1) we should see a axi4-stream tx frame going through
    // ` in (2) there are not enough words into the fifo, nothing should appear in qsfp tx
    // ` at the very start of (3) we should see a axi4-stream tx frame going through and pause
    //   beforethe second one. Pausing by waiting the fifo to fill up again with nb_words
    // --------------------------------------------------------------------------------------------
    r_nb_word = NB_WORDS; // coming from the register file. should be quite static signal.

    @(posedge clk_control);

    // (1)
    for (int i = 0; i < r_nb_word+1 ; i++) begin
      @(posedge clk_control);
      r_wr_word = {$urandom, $urandom};
      write_ack = 1'b1;
      @(posedge clk_control);
      write_ack = 1'b0;
    end

    // --
    repeat(20) @(posedge clk_control);

    // (2)
    for (int i = 0; i < r_nb_word-3 ; i++) begin
      @(posedge clk_control);
      r_wr_word = {$urandom, $urandom};
      write_ack = 1'b1;
      @(posedge clk_control);
      write_ack = 1'b0;
    end

    repeat(20) @(posedge clk_control);

    // (3)
    for (int i = 0; i < 2*r_nb_word+2 ; i++) begin
      @(posedge clk_control);
      r_wr_word = {$urandom, $urandom};
      write_ack = 1'b1;
      @(posedge clk_control);
      write_ack = 1'b0;
    end

    repeat(20) @(posedge clk_control);

    // --------------------------------------------------------------------------------------------
    $display("%t > INFO: Test sequence on RX link",$time);
    // goal here is to check that the data from qsfp rx can correctly be read from fifo
    //  1- enable the qsfp axi4-stream link to emit
    //  -- wait
    //  2- launch several reads
    //
    // a checker below is checking that the values seen in r_rd_word has changed and that the
    // values match the ones we send trhough axi4-stream
    // --------------------------------------------------------------------------------------------

    // (1)
    trigger_rx_link = 1'b1;
    repeat(10) @(posedge clk_control);

    // (2)
    for (int nb = 0; nb <= 5*r_nb_word; nb++) begin
      read_ack = 1'b1;
      @(posedge clk_control);
      read_ack = 1'b0;
      repeat(2) @(posedge clk_control);
    end
    @(posedge clk_control);
    trigger_rx_link = 1'b0;
    repeat(10) @(posedge clk_control);

    // // --------------------------------------------------------------------------------------------
    // $display("%t > INFO: sending TX while being in rx to tx mode ",$time);
    // // with an arbitrary given number of word we will
    // //  1- write nb_word into the fifo
    // //  -- wait
    // //  2- stop the process
    // //  3- reset our status registers
    // //
    // // --------------------------------------------------------------------------------------------
    rx_to_tx = 1'b1;
    trigger_rx_link = 1'b1;
    @(posedge clk_control);


    repeat(100) @(posedge clk_control);

    @(posedge clk_control);
    rx_to_tx = 1'b0;
    trigger_rx_link = 1'b0;
    repeat(10) @(posedge clk_control);

    reset_registers <= 1'b1;
    @(posedge clk_control);
    reset_registers <= 1'b1;
    // --------------------------------------------------------------------------------------------
    $display("%t > INFO: sending TX while being in fifo loop mode ",$time);
    // write 64 words of 64bits
    //  1- write nb_word into the fifo
    //  -- wait
    //  2- stop the process
    //  3- reset our status registers
    //
    // --------------------------------------------------------------------------------------------
    tx_loop = 1'b1;
    r_nb_word = 64; // coming from the register file. should be quite static signal.

    @(posedge clk_control);

    // (1)
    for (int i = 0; i < 64 ; i++) begin
      @(posedge clk_control);
      r_wr_word = {$urandom, $urandom};
      write_ack = 1'b1;
      @(posedge clk_control);
      write_ack = 1'b0;
    end
    repeat(20) @(posedge clk_control);
    qsfp_tx_tready <= 1'b0;
    repeat(10) @(posedge clk_control);
    qsfp_tx_tready <= 1'b1;
    repeat(50) @(posedge clk_control);
    tx_loop = 1'b0;
    repeat(10) @(posedge clk_control);


    // --------------------------------------------------------------------------------------------
    $display("%t > INFO: End simulation",$time);
    // --------------------------------------------------------------------------------------------
    repeat(200) @(posedge clk_control);
    end_of_test = 1'b1;
  end

  // ============================================================================================== --
  // axi4-stream write into the fifo
  // ============================================================================================== --
  logic [AXIS_TDATA_W-1:0] tdata;
  logic [AXIS_TKEEP_W-1:0] tkeep_user;
  logic                    tlast;
  logic                    tvalid;

  assign qsfp_rx_tdata      = tdata;
  assign qsfp_rx_tkeep_user = tkeep_user;
  assign qsfp_rx_tlast      = tlast;
  assign qsfp_rx_tvalid     = tvalid;


  logic [$clog2(NB_WORDS):0] rx_cnt;

  always_ff @(posedge clk_mrmac) begin
    if (!s_rstn_mrmac) begin
        rx_cnt     <= 'h0;
        tdata      <= 'h0;
        tkeep_user <= 'h0;
        tlast      <= 'h0;
        tvalid     <= 'h0;
    end else begin
      if (trigger_rx_link) begin
        rx_cnt <= rx_cnt +1;
        tdata <= $urandom;
        tkeep_user <= $urandom;
        tlast  <= (rx_cnt == NB_WORDS-1) ? 1'b1 : 1'b0;
        tvalid <= 1'b1;
      end else begin
        rx_cnt     <= 'h0;
        tdata      <= 'h0;
        tkeep_user <= 'h0;
        tlast      <= 'h0;
        tvalid     <= 'h0;
      end
    end
  end

  // ============================================================================================== --
  // Checkers
  // ============================================================================================== --
  logic [AXIS_TDATA_W-1:0] data_ref_q[$:FIFO_DEPTH];
  logic [AXIS_TDATA_W-1:0] r_rd_word_d;
  logic word_has_updated;

  always_ff @(posedge clk_mrmac) begin
    logic [AXIS_TDATA_W-1:0] data_ref;
    if (!s_rstn_mrmac) begin
      error_data <= 1'b0;
    end else begin
      if (tvalid) begin
        data_ref_q.push_front(tdata);
      end
      if (word_has_updated) begin
        data_ref = data_ref_q.pop_back();
        assert (r_rd_word == data_ref)
        else begin
          $display("> ERROR: Data mismatch: exp=0x%x seen=0x%x", data_ref, r_rd_word);
          error_data <= 1;
        end
      end
    end
  end

  always_ff @(posedge clk_mrmac)
    r_rd_word_d <= r_rd_word;

  always_ff @(posedge clk_mrmac) begin
    if (s_rstn_mrmac) begin
      word_has_updated <= 1'b0;
    end else begin
      if (r_rd_word_d != r_rd_word) begin
        word_has_updated <= 1'b1;
      end else begin
        word_has_updated <= 1'b0;
      end
    end
  end

endmodule
