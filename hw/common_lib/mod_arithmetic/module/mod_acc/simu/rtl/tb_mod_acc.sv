// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Test the modular accumulator.
// ==============================================================================================

module tb_mod_acc;
`timescale 1ns/10ps

  import mod_acc_pkg::*;

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam CLK_HALF_PERIOD = 1;
  localparam ARST_ACTIVATION = 17;

  parameter  int        RESULT_NB = 1000000;
  parameter  int        INTL_L    = 10; // maximum number of element to accumulate

  parameter  int        OP_W  = 33;
  parameter  [OP_W-1:0] MOD_M = 2**OP_W - 2**(OP_W/2) + 1;
  parameter  bit        IN_PIPE  = 1'b1;
  parameter  bit        OUT_PIPE = 1'b1;
  localparam int        SIDE_W   = 8;
  localparam [1:0]      RST_SIDE = 2'b10;

  localparam int LATENCY = get_latency() + IN_PIPE + OUT_PIPE;

// ============================================================================================== --
// clock, reset
// ============================================================================================== --
  bit clk;
  bit a_rst_n; // asynchronous reset
  bit s_rst_n; // synchronous reset

  initial begin
    clk     = 1'b0;
    a_rst_n = 1'b0;                   // active reset
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
  bit error_avail;

  assign error = error_value
                | error_side
                | error_avail;

  always_ff @(posedge clk)
    if (error) begin
      $display("%t > FAILURE !", $time);
      $finish;
    end

// ============================================================================================== --
// input / output signals
// ============================================================================================== --
  logic [OP_W-1:0]   in_op;
  logic [OP_W-1:0]   out_op;
  logic              in_sol;
  logic              in_eol;
  logic              in_avail;
  logic              out_avail;
  logic [SIDE_W-1:0] in_side;
  logic [SIDE_W-1:0] out_side;

// ============================================================================================== --
// Design under test instance
// ============================================================================================== --
  mod_acc #(
    .OP_W    (OP_W    ),
    .MOD_M   (MOD_M   ),
    .IN_PIPE (IN_PIPE ),
    .OUT_PIPE(OUT_PIPE),
    .SIDE_W  (SIDE_W  ),
    .RST_SIDE(RST_SIDE)
  ) dut (
    .clk     (clk    ),
    .s_rst_n (s_rst_n),

    .in_op    (in_op    ),
    .out_op   (out_op   ),
    .in_sol   (in_sol   ),
    .in_eol   (in_eol   ),
    .in_avail (in_avail ),
    .out_avail(out_avail),
    .in_side  (in_side  ),
    .out_side (out_side )
  );

// ============================================================================================== --
// Stimuli
// ============================================================================================== --
  integer in_cnt;
  integer out_cnt;
  logic [LATENCY-1:0] last_in_avail_dly;
  logic ref_out_avail;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      in_avail          <= 1'b0;
      in_cnt            <= 0;
      out_cnt           <= 0;
      last_in_avail_dly <= '0;
    end
    else begin
      in_avail          <= $urandom_range(1);
      in_cnt            <= in_avail  ? in_eol ? 0 : in_cnt + 1 : in_cnt;
      out_cnt           <= out_avail ? out_cnt + 1 : out_cnt;
      last_in_avail_dly <= {last_in_avail_dly[LATENCY-2:0], in_avail & in_eol};
      if (out_avail && (out_cnt % 10000) == 0)
        $display("%t > INFO: Output # %d", $time, out_cnt);
    end

  assign ref_out_avail = last_in_avail_dly[LATENCY-1];

  integer rand_val;
  integer l_nb; // Number of input to be accumulated.
  always_ff @(posedge clk)
    rand_val <= $urandom;

  always_ff @(posedge clk)
    if (!s_rst_n)                l_nb <= $urandom_range(INTL_L,1);
    else if (in_avail && in_eol) l_nb <= $urandom_range(INTL_L,1);

  assign in_sol = in_cnt == 0;
  assign in_eol = in_cnt == l_nb-1;

  assign in_op   = MOD_M - rand_val[31:0];
  assign in_side = rand_val[SIDE_W-1:0];

  assign end_of_test = out_avail & (out_cnt == RESULT_NB);

  logic [OP_W-1:0] result_q[$];
  logic [OP_W-1:0] side_q[$];
  logic [OP_W:0]   tmp;
  logic store;
  always_ff @(posedge clk)
    if (!s_rst_n) store <= 0;
    else          store <= in_avail & in_eol;

  always_ff @(posedge clk)
    if (in_avail) begin
      if (in_sol) tmp <= in_op;
      else        tmp <= (tmp + in_op) > MOD_M ? (tmp + in_op - MOD_M) : tmp + in_op;
    end

  // Check value + side
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      error_value <= 0;
      error_side  <= 0;
    end
    else begin
      if (store)
        result_q.push_back(tmp);
      if (in_avail && in_eol)
        side_q.push_back(in_side);

      if (out_avail) begin
        logic [OP_W-1:0]   ref_op;
        logic [SIDE_W-1:0] ref_side;
        ref_op   = result_q.pop_front();
        ref_side = side_q.pop_front();
        assert(ref_op == out_op)
        else begin
          $display("%t > ERROR: Result mismatches exp=0x%0x seen=0x%0x",$time, ref_op, out_op);
          error_value <= 1;
        end
        assert(ref_side == out_side)
        else begin
          $display("%t > ERROR: Side mismatches exp=0x%0x seen=0x%0x",$time, ref_side, out_side);
          error_side <= 1;
        end
      end
    end

  always_ff @(posedge clk)
    if (!s_rst_n)
      error_avail <= 1'b0;
    else begin
      assert(out_avail == ref_out_avail)
      else begin
        $display("%t > ERROR: out_avail mismatches exp=%1b seen=%1b", $time, ref_out_avail, out_avail);
        error_avail <= 1'b1;
      end
    end

endmodule
