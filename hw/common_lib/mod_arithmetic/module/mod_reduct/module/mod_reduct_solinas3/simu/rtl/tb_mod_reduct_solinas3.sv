// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description :
// ----------------------------------------------------------------------------------------------
//
// Test bench to test the solinas3 reduction.
// ==============================================================================================

module tb_mod_reduct_solinas3;
`timescale 1ns/10ps

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int           CLK_HALF_PERIOD = 1;
  localparam int           ARST_ACTIVATION = 17;

  parameter  int           MOD_W    = 64;
  parameter  int           POW0     = 42;
  parameter  int           POW1     = 21;
  parameter  [MOD_W-1:0]   MOD_M    = 2**MOD_W - 2**POW0 - 2**POW1 + 1;
  parameter  int           OP_W     = 2*MOD_W+1;

  localparam bit           IN_PIPE  = 1;
  localparam int           SIDE_W   = 8;
  localparam [1:0]         RST_SIDE = 2'b10;

  localparam bit           BIG_MOD_M = OP_W > 24;
  parameter  [MOD_W*2:0]   RESULT_NB = BIG_MOD_M ? 10000000 : 2**OP_W-1;

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
  bit error_value;
  bit error_side;

  assign error =  error_value
                | error_side;

  always_ff @(posedge clk)
    if (error) begin
      $display("%t > FAILURE !", $time);
      $finish;
    end

// ============================================================================================== --
// input / output signals
// ============================================================================================== --
  logic [OP_W-1:0]    a;
  logic [MOD_W-1:0]   z;

  logic               in_avail;
  logic               out_avail;

  logic [SIDE_W-1:0]  in_side;
  logic [SIDE_W-1:0]  out_side;

// ============================================================================================== --
// Design under test instance
// ============================================================================================== --
  mod_reduct_solinas3 #(
    .MOD_W        (MOD_W),
    .MOD_M        (MOD_M),
    .OP_W         (OP_W),
    .IN_PIPE      (IN_PIPE),
    .SIDE_W       (SIDE_W),
    .RST_SIDE     (RST_SIDE)
  ) dut (
    .clk      (clk      ),
    .s_rst_n  (s_rst_n  ),
    .a        (a        ),
    .z        (z        ),
    .in_avail (in_avail ),
    .out_avail(out_avail),
    .in_side  (in_side  ),
    .out_side (out_side )
  );

// ============================================================================================== --
// Scenario
// ============================================================================================== --
  initial begin
    int POS_NB;
    int INT_POW_NB;
    POS_NB     = dut.POS_NB;
    INT_POW_NB = dut.INT_POW_NB;
    $display("%t > INFO: MOD_W      = %0d"  , $time, MOD_W);
    $display("%t > INFO: MOD_M      = 0x%0x", $time, MOD_M);
    $display("%t > INFO: OP_W       = %0d"  , $time, OP_W);
    $display("%t > INFO: INT_POW_NB = %0d"  , $time, INT_POW_NB);
    $display("%t > INFO: POS_NB     = %0d"  , $time, POS_NB);
    for (int i=0; i<INT_POW_NB; i=i+1) begin
      $display("%t > INFO: INT_POW[%0d] = %0d", $time, i, dut.INT_POW[i]);
    end
    for (int i=0; i<INT_POW_NB+1; i=i+1) begin
      $display("%t > INFO: STRIDE[%0d] = %0d ADD_BIT[%0d] = %0d", $time, i, dut.STRIDE[i], i, dut.ADD_BIT[i]);
    end
    for (int i=0; i<POS_NB; i=i+1) begin
      $display("%t > INFO: POS[%0d]    = %0d", $time, i, dut.POS[i]);
    end
    $display("%t > INFO: WRAP_W     = %0d"  , $time, dut.WRAP_W);
  end

  always_ff @(posedge clk)
    if (!s_rst_n) in_avail     <= 1'b0;
    else          in_avail     <= $urandom_range(15) != 0;

  logic [MOD_W*2:0] out_cnt;
  always_ff @(posedge clk)
    if (!s_rst_n)  out_cnt  <= 0;
    else           out_cnt  <= out_avail ? out_cnt + 1 : out_cnt;

  always_ff @(posedge clk) begin
    if (!s_rst_n)
      a <= 2**OP_W-1;
    else
      if (in_avail)
        // If not too big, check all the possible values
        a <= BIG_MOD_M ? MOD_M + {$urandom, $urandom, $urandom} : a-1;
  end

  always_ff @(posedge clk)
    in_side <= $urandom;

  logic [MOD_W-1:0]  result_q[$];
  logic [SIDE_W-1:0] side_q[$];

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      error_value <= 0;
      error_side  <= 0;
    end
    else begin
      if (in_avail) begin
        result_q.push_back(a - (a /MOD_M)*MOD_M);
        side_q.push_back(in_side);
      end
      if (out_avail) begin
        logic [MOD_W-1:0]  ref_op;
        logic [SIDE_W-1:0] ref_side;
        ref_op   = result_q.pop_front();
        ref_side = side_q.pop_front();

        assert(ref_op == z)
        else begin
          $display("%t > ERROR: Data mismatch exp=0x%0x seen=0x%0x",$time, ref_op, z);
          error_value <= 1;
        end

        assert(ref_side == out_side)
        else begin
          $display("%t > ERROR: Side mismatch exp=0x%0x seen=0x%0x",$time, ref_side, out_side);
          error_side <= 1;
        end

        if (out_cnt % 100000 == 0)
          $display("%t > INFO: Output #%d / %d", $time,out_cnt,RESULT_NB);
      end
    end

  assign end_of_test = out_avail & (out_cnt == RESULT_NB);

endmodule
