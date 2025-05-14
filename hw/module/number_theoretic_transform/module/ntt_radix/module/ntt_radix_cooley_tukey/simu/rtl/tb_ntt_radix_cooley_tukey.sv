// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : This is the explicit title of the testbench module
// ----------------------------------------------------------------------------------------------
//
// More details on the test bench scenario.
//
// Describe the steps the test bench goes through:
//  1. First step
//  2. Second step
//  3. Third step
//     Elaborate if needed
//  4. Fourth step
//
// ==============================================================================================

module tb_ntt_radix_cooley_tukey;
`timescale 1ns/10ps

  import mod_arith::*;
  import common_definition_pkg::*;

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int CLK_HALF_PERIOD = 1;
  localparam int ARST_ACTIVATION = 17;

  parameter int        R             = 8;
  parameter mod_reduct_type_e     REDUCT_TYPE   = MOD_REDUCT_GOLDILOCKS;
  parameter mod_mult_type_e       MOD_MULT_TYPE = MOD_MULT_GOLDILOCKS;
  parameter arith_mult_type_e     MULT_TYPE     = MULT_GOLDILOCKS_CASCADE;
  parameter int        OP_W          = 64;
  parameter [OP_W-1:0] MOD_M         = 2**OP_W - 2**(OP_W/2) + 1;
  parameter int        OMG_SEL_NB    = 2;
  parameter bit        USE_MOD_MULT  = 1;
  parameter  bit       OUT_NATURAL_ORDER = 1; //(0) Output in reverse2 order, (1) natural order
  localparam bit       IN_PIPE       = 1'b1;
  localparam int       SIDE_W        = 8;// Side data size. Set to 0 if not used
  localparam [1:0]     RST_SIDE      = 2'b00; // If side data is used;
                                       // [0] (1) reset them to 0.
                                       // [1] (1) reset them to 1.
  localparam int       OMG_SEL_W     = $clog2(OMG_SEL_NB);

  localparam int       S_NB          = $clog2(R);

  localparam int       TOTAL_NB      = 50000;
// ============================================================================================== --
// functions
// ============================================================================================== --
  function [R-1:0][OP_W-1:0] ntt(input [R-1:0][OP_W-1:0] xt_a,
                                 input [R-1:0][OP_W-1:0] phi_a,    // complete [0] with 1
                                 input [R/2-1:0][OP_W-1:0] omg_a,
                                 input bit OUT_NATURAL_ORDER); // "
    // Point-wise multiplication
    logic [S_NB:1][R-1:0][OP_W-1:0]   s_mult;
    logic [S_NB:1][R-1:0][OP_W-1:0]   s_x;

    // Butterfly : stage 0
    for (int i=0; i<R; i=i+1)
      s_mult[1][i] = mod_red((xt_a[i] * phi_a[i]), MOD_M);
    for (int i=0; i<R/2; i=i+1) begin
      s_x[1][i]     = mod_add(s_mult[1][i],s_mult[1][i+R/2], MOD_M);
      s_x[1][i+R/2] = mod_sub(s_mult[1][i],s_mult[1][i+R/2], MOD_M);
    end

//    for (int i=0; i<R; i=i+1)
//      $display("S0 >> xt_a[%0d]=0x%0x phi_a[%0d]=0x%0x s_mult[1][%0d]=0x%0x",
//                i, xt_a[i], i, phi_a[i], i, s_mult[1][i]);
//    for (int i=0; i<R; i=i+1)
//      $display("S0 >> s_x[1][%0d]=0x%0x", i, s_x[1][i]);

    // Butterfly
    for (int s=1; s < S_NB; s=s+1) begin
      for (int g=0; g<2**(s-1); g=g+1) begin
        int g_ofs;
        int g_elt;
        g_elt = R/(2**(s-1)); // Number of coef in the group
        g_ofs = g*g_elt;      // Offset to go to another group

        for (int i=0; i<g_elt/2; i=i+1) begin
          s_mult[s+1][g_ofs+i] = s_x[s][g_ofs+i];
        end
        for (int i=g_elt/2, int j=0; i<g_elt; i=i+1, j=j+1) begin
          s_mult[s+1][g_ofs+i] = mod_red((s_x[s][g_ofs+i]* omg_a[(j*(2**(s-1))) % (R/2)]), MOD_M) ;
//          $display("S%0d >> s_x[%0d]=0x%0x omg_a[%0d]=0x%0x s_mult[%0d]=0x%0x",
//                   s, g_ofs+i, s_x[s][g_ofs+i], (j*s) % (R/2), omg_a[(j*s) % (R/2)],g_ofs+i, s_mult[s+1][g_ofs+i]);
        end

        for (int i=0; i<g_elt/4; i=i+1) begin
          s_x[s+1][g_ofs+i]         = mod_add(s_mult[s+1][g_ofs+i],s_mult[s+1][g_ofs+i+g_elt/4], MOD_M);
          s_x[s+1][g_ofs+i+g_elt/4] = mod_sub(s_mult[s+1][g_ofs+i],s_mult[s+1][g_ofs+i+g_elt/4], MOD_M);
        end
        for (int i=g_elt/2; i<3*g_elt/4; i=i+1) begin
          s_x[s+1][g_ofs+i]         = mod_add(s_mult[s+1][g_ofs+i],s_mult[s+1][g_ofs+i+g_elt/4], MOD_M);
          s_x[s+1][g_ofs+i+g_elt/4] = mod_sub(s_mult[s+1][g_ofs+i],s_mult[s+1][g_ofs+i+g_elt/4], MOD_M);
        end

      end // for g

//      for (int i=0; i<R; i=i+1)
//        $display("S%0d >> s_x[%0d]=0x%0x", s, i, s_x[s+1][i]);



    end // for s

    if (OUT_NATURAL_ORDER) begin
      logic [R-1:0][OP_W-1:0]   s_out_x;
      var [$clog2(R)-1:0] idx;
      for (int i=0; i<R; i=i+1) begin
        idx = {<<{i[$clog2(R)-1:0]}}; // reverse the bit order
        s_out_x[i] = s_x[S_NB][idx];
      end
      return s_out_x;
    end
    else
      return s_x[S_NB];
  endfunction

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

  assign error = error_value | error_side;

  always_ff @(posedge clk)
    if (error) begin
      $display("%t > FAILURE !", $time);
      $finish;
    end

// ============================================================================================== --
// input / output signals
// ============================================================================================== --
  logic [R-1:0][OP_W-1:0]                   xt_a;
  logic [R-1:0][OP_W-1:0]                   xf_a;
  logic [R-1:0][OP_W-1:0]                   phi_a;   // Phi root of unity
  logic [OMG_SEL_NB-1:0][R/2-1:0][OP_W-1:0] omg_a;   // quasi static signal
  logic [OMG_SEL_W-1:0]                     omg_sel; // data dependent selector
  // Control
  logic                                     in_avail;
  logic                                     out_avail;
  // Optional
  logic [SIDE_W-1:0]                        in_side;
  logic [SIDE_W-1:0]                        out_side;

// ============================================================================================== --
// Design under test instance
// ============================================================================================== --
  ntt_radix_cooley_tukey #(
    .R             (R),
    .REDUCT_TYPE   (REDUCT_TYPE),
    .MOD_MULT_TYPE (MOD_MULT_TYPE),
    .MULT_TYPE     (MULT_TYPE),
    .USE_MOD_MULT  (USE_MOD_MULT),
    .OUT_NATURAL_ORDER(OUT_NATURAL_ORDER),
    .OP_W          (OP_W),
    .MOD_M         (MOD_M),
    .OMG_SEL_NB    (OMG_SEL_NB),
    .IN_PIPE       (IN_PIPE),
    .SIDE_W        (SIDE_W),
    .RST_SIDE      (RST_SIDE)

  ) dut (
    .clk      (clk),
    .s_rst_n  (s_rst_n),
    .xt_a     (xt_a),
    .xf_a     (xf_a),
    .phi_a    (phi_a[R-1:1]),
    .omg_a    (omg_a),
    .omg_sel  (omg_sel),
    .in_avail (in_avail),
    .out_avail(out_avail),
    .in_side  (in_side),
    .out_side (out_side)
  );

// ============================================================================================== --
// Scenario
// ============================================================================================== --
  initial begin
    for (int i=0; i<OMG_SEL_NB; i=i+1) begin
      omg_a[i][0] = 1;
      for (int j=1; j<R/2; j=j+1)
        omg_a[i][j] = {$urandom(), $urandom()};
    end
  end

  logic [R-1:0][OP_W-1:0] ref_data_q[$];
  logic [SIDE_W-1:0]      ref_side_q[$];

  always_ff @(posedge clk)
    if (!s_rst_n)
      in_avail <= 1'b0;
    else begin
      logic avail;
      logic [R-1:0][OP_W-1:0] x;
      logic [R-1:0][OP_W-1:0] y;
      logic [R-1:0][OP_W-1:0] p;
      logic [OMG_SEL_W-1:0]   sel;
      logic [SIDE_W-1:0]      side;
      avail = $urandom_range(1);
      if (avail) begin
        for (int i=0; i<R; i=i+1) begin
          x[i] = {$urandom(), $urandom()};
          p[i] = {$urandom(), $urandom()};
          x[i] = x[i] > MOD_M ? x[i] - MOD_M : x[i];
        end
        sel  = $urandom_range(OMG_SEL_NB);
        side = $urandom();
        p[0] = 1;
        y = ntt(x,p,omg_a[sel], OUT_NATURAL_ORDER);
        ref_data_q.push_front(y);
        ref_side_q.push_front(side);
      end
      in_avail <= avail;
      xt_a     <= x;
      phi_a    <= p;
      omg_sel  <= sel;
      in_side  <= side;
    end

// ============================================================================================== --
// Check
// ============================================================================================== --
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      error_value <= 1'b0;
      error_side  <= 1'b0;
    end
    else begin
      if (out_avail) begin
        logic [R-1:0][OP_W-1:0] ref_data;
        logic [SIDE_W-1:0]      ref_side;
        ref_data = ref_data_q.pop_back();
        ref_side = ref_side_q.pop_back();
        assert(ref_side == out_side)
        else begin
          $display("%t > ERROR: Side mismatch : exp=0x%0x seen=0x%0x", $time, ref_side, out_side);
          error_side <= 1'b1;
        end

        for (int i=0; i<R; i=i+1) begin
          assert(ref_data[i] == xf_a[i])
          else begin
            $display("%t > ERROR: Data[%0d] mismatch : exp=0x%0x seen=0x%0x", $time, i, ref_data[i], xf_a[i]);
            error_value <= 1'b1;
          end
        end

      end
    end

// ============================================================================================== --
// End test
// ============================================================================================== --
  integer out_cnt;
  always_ff @(posedge clk)
    if (!s_rst_n)
      out_cnt <= '0;
    else begin
      out_cnt <= out_avail ? out_cnt + 1 : out_cnt;
      if (out_avail && out_cnt % 10000 == 0)
        $display("%t > INFO: Output # %d / %d", $time, out_cnt, TOTAL_NB);
    end

  assign end_of_test = (out_cnt == TOTAL_NB);
endmodule
