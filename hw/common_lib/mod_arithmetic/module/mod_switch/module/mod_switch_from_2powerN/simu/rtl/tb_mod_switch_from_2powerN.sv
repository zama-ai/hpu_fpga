// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Testbench for the Upwards Modulo Switch
// ----------------------------------------------------------------------------------------------
//
// Test bench generates a queue of inputs and corresponding outputs and tests their correctness.
//
// ==============================================================================================

module tb_mod_switch_from_2powerN;
  import mod_switch_from_2powerN_pkg::*;
  import common_definition_pkg::*;

  `timescale 1ns/10ps

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int CLK_HALF_PERIOD = 1;
  localparam int ARST_ACTIVATION = 17;

  localparam int TEST_ITERATIONS = 100000;

  localparam int           MOD_Q_W = 32;
  localparam int           MOD_P_W = 32;
  localparam [MOD_P_W-1:0] MOD_P = 2**32-2**17-2**13+1;
  localparam int_type_e    MOD_P_TYPE = SOLINAS3;
  localparam arith_mult_type_e MULT_TYPE  = MULT_KARATSUBA;
  localparam int           SIDE_W = 8;
  localparam [1:0]         RST_SIDE = 2'b10;
  localparam bit           IN_PIPE = 1;

  localparam int           IN_W = 8;

  localparam int           LAT = IN_PIPE + mod_switch_from_2powerN_pkg::get_latency(MOD_P_TYPE,MULT_TYPE);

// ============================================================================================== --
// functions
// ============================================================================================== --
  function logic [MOD_P_W-1:0] mod_switch_from_pow_of_2(logic [IN_W:0] a, logic [MOD_P_W-1:0] prime_p);
    logic [MOD_P_W-1:0] res;
    logic [MOD_P_W+MOD_Q_W-1:0] abs_a;
    logic [IN_W-1:0] a_magn;

    if ($signed(a) < 0) begin // Sign bit is set...
      abs_a = (2**MOD_Q_W + {{(MOD_Q_W-IN_W-1){1'b1}}, a}) % 2**MOD_Q_W;
    end else begin
      abs_a = a;
    end
    //$display("Abs value: %h", abs_a);
    res = (abs_a*prime_p) >> MOD_Q_W;
    //$display("Res value: %h", res);

    if (((abs_a*prime_p) >> (MOD_Q_W-1)) & 1) begin
      res = res + 1;
    end
    //$display("Res value: %h", res);

    return res;
  endfunction

// ============================================================================================== --
// clock, reset
// ============================================================================================== --
  bit clk;
  bit a_rst_n; // asynchronous reset
  bit s_rst_n; // synchronous reset

  initial begin
    clk     = 1'b0;
    a_rst_n = 1'b0;                  // active reset
    #ARST_ACTIVATION a_rst_n = 1'b1; // disable reset
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
  bit error_avail;
  bit error_result;
  bit error_side;

  assign error = error_avail
                | error_result
                | error_side;

  always_ff @(posedge clk)
    if (error) begin
      $display("%t > FAILURE !", $time);
      $finish;
    end

// ============================================================================================== --
// input / output signals
// ============================================================================================== --
  logic [IN_W:0]        a;
  logic [MOD_P_W-1:0]   z;
  logic                 in_avail;
  logic                 out_avail;
  logic [SIDE_W-1:0]    in_side;
  logic [SIDE_W-1:0]    out_side;


// ============================================================================================== --
// Design under test instance
// ============================================================================================== --
  mod_switch_from_2powerN #(
    .MOD_Q_W   (MOD_Q_W),
    .MOD_P_W   (MOD_P_W),
    .MOD_P     (MOD_P),
    .IN_W      (IN_W),
    .MOD_P_TYPE(MOD_P_TYPE),
    .MULT_TYPE (MULT_TYPE ),
    .IN_PIPE   (IN_PIPE   ),
    .SIDE_W    (SIDE_W    ),
    .RST_SIDE  (RST_SIDE  )
  ) mod_switch_from_2powerN_dut (
    .clk           (clk),
    .s_rst_n       (s_rst_n),
    .a             (a),
    .z             (z),
    .in_avail      (in_avail),
    .out_avail     (out_avail),
    .in_side       (in_side),
    .out_side      (out_side)
  );

// ============================================================================================== --
// Scenario
// ============================================================================================== --
  stream_source #(
    .FILENAME   ("random"),
    .DATA_TYPE  ("ascii_hex"), // UNUSED
    .DATA_W     (IN_W+1 + SIDE_W),
    .RAND_RANGE (2**32-1),
    .KEEP_VLD   (0),
    .MASK_DATA  ("none")
  ) source (
      .clk     (clk),
      .s_rst_n (s_rst_n),

      .data    ({in_side,a}),
      .vld     (in_avail),
      .rdy     (1'b1),

      .throughput(0)
  );

  integer out_cnt;
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      out_cnt  <= 0;
    end
    else begin
      if (out_avail && (out_cnt % 10000) == 0)
        $display("%t > INFO: Output # %d", $time, out_cnt);
      out_cnt  <= out_avail ? out_cnt + 1 : out_cnt;
    end

  initial begin
    int r;
    end_of_test <= 1'b0;
    r = source.open();
    wait(s_rst_n);
    @(posedge clk) source.start(TEST_ITERATIONS);
    wait(out_cnt == TEST_ITERATIONS);
    @(posedge clk) end_of_test <= 1'b1;
  end


// ============================================================================================== --
// Check
// ============================================================================================== --
// === Check out_avail
  logic [LAT-1:0] avail_dly;

  always_ff @(posedge clk)
    if (!s_rst_n) avail_dly <= '0;
    else          avail_dly <= {avail_dly[LAT-1:0],in_avail};

  always_ff @(posedge clk)
    if (!s_rst_n)
      error_avail <= 1'b0;
    else begin
      assert(avail_dly[LAT-1] == out_avail)
      else begin
        $display("%t > ERROR: output avail mismatches: exp=%b seen=%b",
                  $time, avail_dly[LAT-1],out_avail);
        error_avail <= 1'b1;
      end
    end

// === Check data
  logic [MOD_P_W-1:0] result_q[$];
  logic [SIDE_W-1:0]  side_q[$];

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      error_result <= 0;
      error_side   <= 0;
    end
    else begin
      if (in_avail) begin
        result_q.push_back(mod_switch_from_pow_of_2(a,MOD_P));
        side_q.push_back(in_side);
      end
      if (out_avail) begin
        logic [MOD_P_W-1:0] ref_result;
        logic [SIDE_W-1:0]  ref_side;
        ref_result = result_q.pop_front();
        ref_side   = side_q.pop_front();

        assert(ref_result == z)
        else begin
          $display("%t > ERROR: Result mismatches: exp=0x%0x seen=0x%0x",$time, ref_result, z);
          error_result <= 1;
        end
        assert(ref_side == out_side)
        else begin
          $display("%t > ERROR: Side mismatches: exp=0x%0x seen=0x%0x",$time, ref_side, out_side);
          error_side <= 1;
        end

      end
    end
endmodule
