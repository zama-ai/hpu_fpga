// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : This is the explicit title of the testbench module
// ----------------------------------------------------------------------------------------------
//
// This testbench tests the fifo_delay.
// The different phases are:
// ST_FULL          : Fill the FIFO until it is full
// ST_EMPTY         : Read the FIFO until it is empty
// ST_RANDOM_ACCESS : Do random accesses.
// ==============================================================================================

module tb_fifo_delay;
  `timescale 1ns/10ps

  // ============================================================================================== --
  // localparam
  // ============================================================================================== --
  localparam int CLK_HALF_PERIOD   = 1;
  localparam int ARST_ACTIVATION   = 17;

  parameter  int DEPTH             = 13;
  parameter  int DELAY             = 8;
  parameter  int TIMESTAMP_W       = 32;

  localparam int WIDTH             = TIMESTAMP_W;

  localparam int DEPTH_LOCAL       = DEPTH;
  localparam int DEPTH_LOCAL_W     = $clog2(DEPTH_LOCAL);
  localparam int RANDOM_ACCESS_CNT = DEPTH*10;

  localparam int FULL_BANDWIDTH_CYCLES = DEPTH * 100;
  localparam int TOTAL_NB_CYCLES       = FULL_BANDWIDTH_CYCLES + 1000;

  // ============================================================================================== --
  // clock, reset
  // ============================================================================================== --
  bit clk;
  bit a_rst_n;  // asynchronous reset
  bit s_rst_n;  // synchronous reset

  initial begin
    clk     = 1'b0;
    a_rst_n = 1'b0;  // active reset
    #ARST_ACTIVATION a_rst_n = 1'b1;  // disable reset
  end

  always begin
    #CLK_HALF_PERIOD clk = ~clk;
  end

  always_ff @(posedge clk) begin
    s_rst_n <= a_rst_n;
  end

  // ============================================================================================== --
  // End of test
  // ============================================================================================== --
  bit end_of_test;

  initial begin
    wait (end_of_test);
    @(posedge clk) $display("%t > SUCCEED !", $time);
    $finish;
  end

  // ============================================================================================== --
  // Error
  // ============================================================================================== --
  bit error;
  bit error_data;
  bit error_delay;
  bit error_bw;

  assign error = error_delay | error_data | error_bw;
  always_ff @(posedge clk)
    if (error) begin
      $display("%t > FAILURE !", $time);
      $finish;
    end

  // ============================================================================================== --
  // input / output signals
  // ============================================================================================== --
  logic [WIDTH-1:0] in_data;
  logic             in_vld;
  logic             in_rdy;

  logic [WIDTH-1:0] out_data;
  logic             out_vld;
  logic             out_rdy;

  // ============================================================================================== --
  // Design under test instance
  // ============================================================================================== --
  fifo_delay #(
    .WIDTH         (WIDTH),
    .DEPTH         (DEPTH),
    .DELAY         (DELAY),
    .TIMESTAMP_W   (TIMESTAMP_W)
  ) dut (
    .clk    (clk),
    .s_rst_n(s_rst_n),

    .in_data(in_data),
    .in_vld (in_vld),
    .in_rdy (in_rdy),

    .out_data(out_data),
    .out_vld (out_vld),
    .out_rdy (out_rdy)
  );


  // ============================================================================================== --
  // Scenario
  // ============================================================================================== --
  int   cycle_cnt;
  logic do_full_bandwidth;

  assign do_full_bandwidth = cycle_cnt < FULL_BANDWIDTH_CYCLES;

  always_ff @(posedge clk)
    if (!s_rst_n) cycle_cnt <= 0;
    else          cycle_cnt <= cycle_cnt + 1;

  assign end_of_test = cycle_cnt == TOTAL_NB_CYCLES;

  logic [TIMESTAMP_W-1:0] timestamp;
  logic             rand_vld;
  logic             rand_rdy;
  always_ff @(posedge clk) begin
    rand_vld  <= $urandom_range(1);
    rand_rdy  <= $urandom_range(16) != 0;
  end
  always_ff @(posedge clk)
    if (!s_rst_n) timestamp <= '0;
    else          timestamp <= timestamp + 1;

  assign in_data = timestamp;
  assign in_vld  = do_full_bandwidth ? 1'b1 : rand_vld;
  assign out_rdy = do_full_bandwidth ? 1'b1 : rand_rdy;

  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      error_bw <= 1'b0;
    end else begin
      if (do_full_bandwidth) begin
        assert (in_rdy == 1'b1)
        else begin
          $display("> ERROR: in_rdy is not maintained to 1 during the full bandwidth period.");
          error_bw <= 1'b1;
        end
      end
    end
  end

  //== Check data
  // Use a queue to store the reference data
  logic [WIDTH-1:0] data_ref_q[$:DEPTH];

  always_ff @(posedge clk) begin
    logic [WIDTH-1:0] data_ref;
    if (!s_rst_n) begin
      error_data <= 0;
      error_delay <= 0;
    end else begin
      if (in_rdy && in_vld) begin
        data_ref_q.push_front(in_data);
      end
      if (out_rdy && out_vld) begin
        logic [TIMESTAMP_W-1:0] diff;
        data_ref = data_ref_q.pop_back();
        assert (out_data == data_ref)
        else begin
          $display("> ERROR: Data mismatch: exp=0x%x seen=0x%x", data_ref, out_data);
          error_data <= 1;
        end

        if (out_data > timestamp)
          diff = out_data - timestamp;
        else if (out_data < timestamp)
          diff = timestamp - out_data;
        else
          diff = DELAY; // here the delay must have been respected.

        assert(diff >= DELAY)
        else begin
          $display("> ERROR: Delay not respected: data_timestamp=0x%x cur_timestamp=0x%x", out_data, timestamp);
          error_delay <= 1;
        end
      end
    end
  end

endmodule
