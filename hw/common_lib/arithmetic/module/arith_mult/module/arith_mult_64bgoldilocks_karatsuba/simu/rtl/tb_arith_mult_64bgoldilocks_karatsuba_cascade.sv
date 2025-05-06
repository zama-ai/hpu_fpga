// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Check arith_mult_64bgoldilocks_karatsuba_cascade.
//
// ==============================================================================================

module tb_arith_mult_64bgoldilocks_karatsuba_cascade;
`timescale 1ns/10ps

  import arith_mult_64bgoldilocks_karatsuba_cascade_pkg::*;

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int CLK_HALF_PERIOD = 1;
  localparam int ARST_ACTIVATION = 17;

  parameter  int   RESULT_NB      = 1000000;
  parameter  int   OP_A_W         = 64;
  parameter  int   OP_B_W         = 64;
  parameter  int   RES_Z_W        = 98;
  parameter  int   KARATSUBA_OP_W = 32;
  localparam int   SIDE_W         = 8;
  localparam [1:0] RST_SIDE       = 2'b10;

  localparam int LATENCY = get_latency();

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
  logic [ OP_A_W-1:0] a;
  logic [ OP_B_W-1:0] b;
  logic [RES_Z_W-1:0] z;
  logic               in_avail;
  logic               out_avail;
  logic [SIDE_W-1:0]  in_side;
  logic [SIDE_W-1:0]  out_side;

// ============================================================================================== --
// Design under test instance
// ============================================================================================== --
  arith_mult_64bgoldilocks_karatsuba_cascade #(
    .SIDE_W         (SIDE_W        ),
    .RST_SIDE       (RST_SIDE      )
  ) dut (
    .clk      (clk),
    .s_rst_n  (s_rst_n),
    .a        (a),
    .b        (b),
    .z        (z),
    .in_avail (in_avail),
    .out_avail(out_avail),
    .in_side  (in_side),
    .out_side (out_side)
  );

// ============================================================================================== --
// Scenario
// ============================================================================================== --
  stream_source #(
    .FILENAME   ("random"),
    .DATA_TYPE  ("ascii_hex"), // UNUSED
    .DATA_W     (OP_A_W + OP_B_W + SIDE_W),
    .RAND_RANGE (2**64-2**32+1),
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
// === Check out_avail
  logic [LATENCY-1:0] avail_dly;

  always_ff @(posedge clk)
    if (!s_rst_n) avail_dly <= '0;
    else          avail_dly <= {avail_dly[LATENCY-1:0],in_avail};

  always_ff @(posedge clk)
    if (!s_rst_n)
      error_avail <= 1'b0;
    else begin
      assert(avail_dly[LATENCY-1] == out_avail)
      else begin
        $display("%t > ERROR: output avail mismatches: exp=%b seen=%b",
                  $time, avail_dly[LATENCY-1],out_avail);
        error_avail <= 1'b1;
      end
    end

// === Check data
  logic [RES_Z_W-1:0]  result_q[$];
  logic [SIDE_W-1:0]   side_q[$];
  logic [RES_Z_W-1:0]  tmp_res;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      error_result <= 0;
      error_side   <= 0;
    end
    else begin
      if (in_avail) begin
        tmp_res = (a[31:0]*b[31:0]-a[63:32]*b[63:32]) 
                  + (((a[31:0]+a[63:32])*(b[31:0]+b[63:32])-a[31:0]*b[31:0]) << 32);
        result_q.push_back(tmp_res);
        side_q.push_back(in_side);        
      end
      if (out_avail) begin
        logic [OP_A_W+OP_B_W-1:0] ref_result;
        logic [SIDE_W-1:0]        ref_side;
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

