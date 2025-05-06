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

module tb_mod_switch_to_2powerN;
  import mod_switch_to_2powerN_pkg::*;
  import common_definition_pkg::*;

  `timescale 1ns/10ps

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int CLK_HALF_PERIOD = 1;
  localparam int ARST_ACTIVATION = 17;

  localparam int TEST_ITERATIONS = 100000;

  parameter  int           MOD_Q_W = 64; // Workaround to pass 64 bits value to the bench...
  localparam [MOD_Q_W:0]   MOD_Q = 2**MOD_Q_W;
  localparam int           MOD_P_W = MOD_Q_W;
  localparam [MOD_P_W-1:0] MOD_P = (MOD_P_W==64) ? 2**64-2**32+1 : 2**32-2**17-2**13+1;
  localparam int_type_e    MOD_P_INV_TYPE = (MOD_P_W==64) ? GOLDILOCKS_INV : SOLINAS3_INV;
  localparam int           PRECISION_W = MOD_Q_W + 32;
  // Note : Karatsuba architecture for the multiplier is not optimal here, since the operands
  // do not have the same size. Therefore use "OPTIMIZATION_NAME_CLB"
  localparam arith_mult_type_e MULT_TYPE  = set_mult_type(PRECISION_W,OPTIMIZATION_NAME_CLB);
  localparam int           SIDE_W = 8;
  localparam [1:0]         RST_SIDE = 2'b10;
  localparam bit           IN_PIPE = 1;

  localparam int           LAT = IN_PIPE + mod_switch_to_2powerN_pkg::get_latency(MOD_P_INV_TYPE,MULT_TYPE);

  initial begin
    $display("MOD_P   = 0x%x", MOD_P);
    $display("MOD_P_W = %0d", MOD_P_W);
    $display("MOD_Q   = 0x%x", MOD_Q);
    $display("MOD_Q_W = %0d", MOD_Q_W);
    $display("LAT     = %0d", LAT);
  end

// ============================================================================================== --
// functions
// ============================================================================================== --
function logic [MOD_Q_W-1:0] mod_switch_to_pow_of_2(logic [MOD_P_W-1:0] a);
  logic [MOD_Q_W-1:0] res;
  logic [MOD_Q_W+PRECISION_W+MOD_P_W+1:0] a_x_mult_cst;

  a_x_mult_cst = (a*(MOD_Q*(2**PRECISION_W)/MOD_P));
  //$display("a_x_mult_cst value 0: %h", a_x_mult_cst);

  res = a_x_mult_cst >> PRECISION_W;
  //$display("Res value: %h", res);
  
  if ((a_x_mult_cst >> (PRECISION_W-1)) & 1) begin
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
  logic [MOD_P_W-1:0]   a;
  logic [MOD_Q_W-1:0]   z;
  logic                 in_avail;
  logic                 out_avail;
  logic [SIDE_W-1:0]    in_side;
  logic [SIDE_W-1:0]    out_side;


// ============================================================================================== --
// Design under test instance
// ============================================================================================== --
  mod_switch_to_2powerN #(
    .MOD_Q_W   (MOD_Q_W),
    .MOD_P_W   (MOD_P_W),
    .MOD_P     (MOD_P),
    .MOD_P_INV_TYPE(MOD_P_INV_TYPE),
    .MULT_TYPE (MULT_TYPE ),
    .PRECISION_W(PRECISION_W),
    .IN_PIPE   (IN_PIPE   ),
    .SIDE_W    (SIDE_W    ),
    .RST_SIDE  (RST_SIDE  )
  ) mod_switch_to_2powerN_dut (
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
  logic [MOD_P_W-1:0]   a_tmp;
  assign a = a_tmp > MOD_P ? a_tmp - MOD_P : a_tmp;
  stream_source #(
    .FILENAME   ("random"),
    .DATA_TYPE  ("ascii_hex"), // UNUSED
    .DATA_W     (MOD_P_W + SIDE_W),
    .RAND_RANGE (2**32-1),
    .KEEP_VLD   (0),
    .MASK_DATA  ("none")
  ) source (
      .clk     (clk),
      .s_rst_n (s_rst_n),

      .data    ({in_side,a_tmp}),
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
        result_q.push_back(mod_switch_to_pow_of_2(a));
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
