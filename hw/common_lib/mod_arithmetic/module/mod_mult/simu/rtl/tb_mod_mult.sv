// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Check mod_mult.
//
// ==============================================================================================

module tb_mod_mult;
`timescale 1ns/10ps

  import common_definition_pkg::*;
  import mod_mult_pkg::*;

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int CLK_HALF_PERIOD = 1;
  localparam int ARST_ACTIVATION = 17;

  parameter  int         RESULT_NB     = 100000;
  parameter  int         MOD_W         = 64; // Do not modify this for regression test
  parameter  [MOD_W-1:0] MOD_M         = 2**MOD_W - 2**(MOD_W/2) + 1; // "

  parameter  int         MOD_MULT_TYPE_INT = MOD_MULT_GOLDILOCKS;
  parameter  int         MULT_TYPE_INT     = MULT_GOLDILOCKS_CASCADE;

  parameter  mod_mult_type_e        MOD_MULT_TYPE = mod_mult_type_e'(MOD_MULT_TYPE_INT);
  parameter  arith_mult_type_e      MULT_TYPE     = arith_mult_type_e'(MULT_TYPE_INT);

  localparam bit         IN_PIPE       = 1;
  localparam int         SIDE_W        = 8;
  localparam [1:0]       RST_SIDE      = 2'b01;

  localparam int         LAT           = IN_PIPE + mod_mult_pkg::get_latency(MOD_MULT_TYPE, MULT_TYPE);

  initial begin
    $display("MOD_W=%0d",MOD_W);
    $display("MOD_M=0x%0x",MOD_M);
    $display("MOD_MULT_TYPE=%s",MOD_MULT_TYPE.name());
    $display("MULT_TYPE=%s",MULT_TYPE.name());
  end

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
  bit error_result;
  bit error_side;
  bit error_avail;

  assign error =  error_result
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
  logic [MOD_W-1:0]  a;
  logic [MOD_W-1:0]  b;
  logic [MOD_W-1:0]  z;
  logic              in_avail;
  logic              out_avail;
  logic [SIDE_W-1:0] in_side;
  logic [SIDE_W-1:0] out_side;

// ============================================================================================== --
// Design under test instance
// ============================================================================================== --
  mod_mult #(
    .MOD_MULT_TYPE (MOD_MULT_TYPE),
    .MOD_W         (MOD_W        ),
    .MOD_M         (MOD_M        ),
    .MULT_TYPE     (MULT_TYPE    ),
    .IN_PIPE       (IN_PIPE      ),
    .SIDE_W        (SIDE_W       ),
    .RST_SIDE      (RST_SIDE     )
  ) dut (
    .clk       (clk),
    .s_rst_n   (s_rst_n),
    .a         (a),
    .b         (b),
    .z         (z),
    .in_avail  (in_avail),
    .out_avail (out_avail),
    .in_side   (in_side),
    .out_side  (out_side)
  );

// ============================================================================================== --
// Scenario
// ============================================================================================== --
  stream_source #(
    .FILENAME   ("random"),
    .DATA_TYPE  ("ascii_hex"), // UNUSED
    .DATA_W     (MOD_W + MOD_W + SIDE_W),
    .RAND_RANGE (2**32-1),
    .KEEP_VLD   (0),
    .MASK_DATA  ("none")
  ) source (
      .clk     (clk),
      .s_rst_n (s_rst_n),

      .data    ({in_side,b,a}),
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
    @(posedge clk) source.start(RESULT_NB);
    wait(out_cnt == RESULT_NB);
    @(posedge clk)end_of_test <= 1'b1;
  end


// ============================================================================================== --
// Check
// ============================================================================================== --
// === Check data
  logic [MOD_W+MOD_W-1:0] result_q[$];
  logic [SIDE_W-1:0]        side_q[$];

  always_ff @(posedge clk) begin
    var [MOD_W*2-1:0] mult;

    if (!s_rst_n) begin
      error_result <= 0;
      error_side   <= 0;
    end
    else begin
      if (in_avail) begin
        mult = a*b;
        result_q.push_back(mult - (mult /MOD_M)*MOD_M);
        side_q.push_back(in_side);
      end
      if (out_avail) begin
        logic [2*MOD_W-1:0] ref_result;
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
  end

  // check avail
  logic [LAT-1:0] ref_out_avail;
  always_ff @(posedge clk)
    if (!s_rst_n) ref_out_avail <= '0;
    else ref_out_avail          <= {ref_out_avail[LAT-2:0],in_avail};

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      error_avail <= 1'b0;
    end
    else begin
      assert(out_avail == ref_out_avail[LAT-1])
      else begin
        $display("%t > ERROR: out_avail mismatch", $time);
        error_avail <= 1'b1;
      end
    end

endmodule
