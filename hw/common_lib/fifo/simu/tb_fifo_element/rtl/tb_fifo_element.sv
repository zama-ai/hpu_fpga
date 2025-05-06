// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : This is the explicit title of the testbench module
// ----------------------------------------------------------------------------------------------
//
// This testbench tests the fifo_element.
// This bench has 2 phases.
// During the first one, we test the max throughput of the fifo element.
// During the second phase, random accesses are made.
// ==============================================================================================

module tb_fifo_element;
  `timescale 1ns/10ps

  // ============================================================================================== --
  // localparam
  // ============================================================================================== --
  localparam int CLK_HALF_PERIOD = 1;
  localparam int ARST_ACTIVATION = 17;

  parameter int DEPTH                 = 1;
  parameter     [DEPTH-1:0][3:0] TYPE_ARRAY = 1;  // fifo element type

  localparam int         WIDTH          = 8;
  localparam bit         DO_RESET_DATA  = 0;
  localparam [WIDTH-1:0] RESET_DATA_VAL = 0;

  localparam int FULL_BANDWIDTH_CYCLES = DEPTH * 100;
  localparam int TOTAL_NB_CYCLES       = FULL_BANDWIDTH_CYCLES + 1000;

  // Constant function
  function bit type_is_present([DEPTH-1:0][3:0] a, int val);
    bit is_present;
    begin
      is_present = 0;
      for (int i = 0; i < DEPTH; i = i + 1) begin
        is_present = is_present | (a[i] == val);
      end
      type_is_present = is_present;
    end
  endfunction

  localparam bit CHECK_FULL_BANDWIDTH = ~type_is_present(TYPE_ARRAY, 3);

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
  bit error_bw;
  bit error_data;

  assign error = error_bw | error_data;
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
  fifo_element #(
    .WIDTH         (WIDTH),
    .DEPTH         (DEPTH),
    .TYPE_ARRAY    (TYPE_ARRAY),
    .DO_RESET_DATA (DO_RESET_DATA),
    .RESET_DATA_VAL(RESET_DATA_VAL)
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
    else cycle_cnt <= cycle_cnt + 1;

  assign end_of_test = cycle_cnt == TOTAL_NB_CYCLES;

  logic [WIDTH-1:0] rand_data;
  logic             rand_vld;
  logic             rand_rdy;
  always_ff @(posedge clk) begin
    rand_data <= $urandom_range(2 ** WIDTH - 1);
    rand_vld  <= $urandom_range(1);
    rand_rdy  <= $urandom_range(1);
  end

  assign in_data = rand_data;
  assign in_vld  = do_full_bandwidth ? 1'b1 : rand_vld;
  assign out_rdy = do_full_bandwidth ? 1'b1 : rand_rdy;

  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      error_bw <= 1'b0;
    end else begin
      if (CHECK_FULL_BANDWIDTH && do_full_bandwidth) begin
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
    end else begin
      if (in_rdy && in_vld) begin
        data_ref_q.push_front(in_data);
      end
      if (out_rdy && out_vld) begin
        data_ref = data_ref_q.pop_back();
        assert (out_data == data_ref)
        else begin
          $display("> ERROR: Data mismatch: exp=0x%x seen=0x%x", data_ref, out_data);
          error_data <= 1;
        end
      end
    end
  end
endmodule
