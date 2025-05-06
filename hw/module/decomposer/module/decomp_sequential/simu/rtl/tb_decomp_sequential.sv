// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
//
// ============================================================================================== --
// Description  : Testbench for the decomp_sequential
// ---------------------------------------------------------------------------------------------- --
//
// ============================================================================================== --

module tb_decomp_sequential;
`timescale 1ns/10ps

// ============================================================================================= --
// parameter
// ============================================================================================= --
  parameter int MOD_Q_W = 32;
  parameter int PBS_L   = 4;
  parameter int PBS_B_W = 7;
  parameter bit OUT_2SCOMPL = 1'b1;
// ============================================================================================= --
// localparam
// ============================================================================================= --
  localparam int CLK_HALF_PERIOD = 1;
  localparam int ARST_ACTIVATION = 17;

  localparam int SAMPLE_NB      = 100_000;
  localparam [2:0] LAT_PIPE_MH  = {3{1'b0}};

  localparam int SIDE_W = 16;

  localparam int CLOSEST_REP_W   = PBS_L * PBS_B_W;
  localparam int CLOSEST_REP_OFS = MOD_Q_W - CLOSEST_REP_W;

// ============================================================================================= --
// functions
// ============================================================================================= -- // Inputs:
  // Input_word to be "rounded", decomposition parameters level_count and base_log
  // Outputs: Computes the closest representable number by the decomposition defined by
  //  level_count and base_log.
  function logic [MOD_Q_W-1:0] closest_representable(logic [MOD_Q_W-1:0] input_word);
    logic               non_rep_msb;
    logic [MOD_Q_W-1:0] res;

    non_rep_msb = input_word[CLOSEST_REP_OFS - 1];
    res = input_word >> CLOSEST_REP_OFS;
    res = res + non_rep_msb;
    res = res << CLOSEST_REP_OFS;
    return res;
  endfunction

  // Inputs:
  //  Coefficient decomp_input to be decomposed with decomposition parameters level_l and base_log
  // Output: list of level_l coefficients representing the closest representable number
  function logic [PBS_L-1:0][PBS_B_W:0] decompose(logic [MOD_Q_W-1:0] decomp_input);
    logic [MOD_Q_W-1:0]   closest_rep;
    logic [PBS_L-1:0][PBS_B_W:0] res;
    logic [MOD_Q_W-1:0]          state;
    logic [PBS_B_W:0]            mod_b_mask;
    logic [PBS_B_W:0]            decomp_output;
    logic [MOD_Q_W-1:0]          carry;
    logic [MOD_Q_W-1:0]          recons;

    closest_rep = closest_representable(decomp_input);
    //$display("> Closest Repr Input is: %d", closest_rep);

    state = closest_rep >> CLOSEST_REP_OFS;
    mod_b_mask = (1 << PBS_B_W) - 1;
    for (int i=0; i<PBS_L; i=i+1) begin
      //$display("> Current level: %d", i);
      // Decompose the current level
      decomp_output = state & mod_b_mask;
      state = state >> PBS_B_W;
      carry = ((decomp_output-1) | state) & decomp_output;
      carry >>= PBS_B_W - 1;
      state += carry;
      //$display(">           carry at level %d is: %d", i, carry);
        decomp_output = decomp_output - (carry << PBS_B_W);
      if (OUT_2SCOMPL)
        res[i] = decomp_output;
      else begin
        res[i][PBS_B_W]     = decomp_output[PBS_B_W];
        res[i][PBS_B_W-1:0] = decomp_output[PBS_B_W] ? -decomp_output : decomp_output;
      end
      //$display("> Decomposed word at level %d is: %d", i , res[i]);
    end

    // Reconstruct to check
    if (OUT_2SCOMPL) begin
      recons = 0;
      for (int i=0; i<PBS_L; i++) begin
        recons += res[i]*2**(i*PBS_B_W+CLOSEST_REP_OFS) % 2**MOD_Q_W;
      end

      if (recons!=closest_rep) begin
        $display("problem decomposing");
      end
      //$display("Reconstruction: %d ", recons, " vs Closest Repr Input: %d", closest_rep);
    end

    return res;
  endfunction


// ============================================================================================= --
// clock, reset
// ============================================================================================= --
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


// ============================================================================================= --
// End of test
// ============================================================================================= --
  bit end_of_test;

  initial begin
    wait (end_of_test);
    @(posedge clk) $display("%t > SUCCEED !", $time);
    $finish;
  end

// ============================================================================================= --
// Error
// ============================================================================================= --
  bit             error;
  bit             error_value;
  bit             error_side;
  bit             error_info;
  logic           decomp_error;

  assign error = error_value
                | error_side
                | error_info
                | decomp_error;

  always_ff @(posedge clk)
    if (error) begin
      $display("%t > FAILURE !", $time);
      $finish;
    end

// ============================================================================================= --
// input / output signals
// ============================================================================================= --
  logic [MOD_Q_W-1:0]          decomposer_in;
  logic                        in_avail;
  logic [SIDE_W-1:0]           in_side;
  logic [PBS_B_W:0]            decomposer_out;
  logic                        out_avail;
  logic [SIDE_W-1:0]           out_side;
  logic                        out_sol;
  logic                        out_eol;

// ============================================================================================= --
// Design under test instance
// ============================================================================================= --
  decomp_sequential
  #(
    .OP_W    (MOD_Q_W),
    .L       (PBS_L),
    .B_W     (PBS_B_W),
    .SIDE_W  (SIDE_W),
    .OUT_2SCOMPL (OUT_2SCOMPL)
  )
  dut
  (
    .clk       (clk),
    .s_rst_n   (s_rst_n),
    .in_data   (decomposer_in),
    .in_avail  (in_avail),
    .in_side   (in_side),
    .out_data  (decomposer_out),
    .out_avail (out_avail),
    .out_side  (out_side),
    .out_sol   (out_sol),
    .out_eol   (out_eol),

    .error     (decomp_error)
  );

// ============================================================================================= --
// Scenario
// ============================================================================================= --
  integer in_cycle_cnt;
  integer in_cycle_cntD;

  assign in_cycle_cntD = in_avail ? 1 : in_cycle_cnt + 1;

  always_ff @(posedge clk)
    if (!s_rst_n) in_cycle_cnt <= '0;
    else          in_cycle_cnt <= in_cycle_cntD;

  logic [PBS_L-1:0][PBS_B_W:0] ref_data_q[$];
  logic [SIDE_W-1:0]           ref_side_q[$];

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      in_avail      <= 1'b0;
      decomposer_in <= 'x;
    end
    else begin
      logic avail;
      logic [MOD_Q_W-1:0] data_in;
      logic [PBS_L-1:0][PBS_B_W:0] ref_out;
      logic [SIDE_W-1:0] side_in;
      avail = ((PBS_L == 1) || ((in_cycle_cnt >= PBS_L-1) && !in_avail)) ? $urandom_range(1) : 1'b0;
      //avail = ((PBS_L == 1) || ((in_cycle_cnt >= PBS_L-1) && !in_avail)) ? 1'b1 : 1'b0;
      if (avail) begin
        data_in = {$urandom(), $urandom()};
        side_in = $urandom();
        ref_out = decompose(data_in);
        for (int i=0; i<PBS_L; i=i+1) begin
          ref_data_q.push_front(ref_out[i]);
          ref_side_q.push_front(side_in);
        end
      end
      in_avail      <= avail;
      decomposer_in <= data_in;
      in_side       <= side_in;
    end

  integer lvl_cnt;
  integer lvl_cntD;
  logic ref_sol;
  logic ref_eol;

  assign lvl_cntD = out_avail ? lvl_cnt == PBS_L-1 ? '0 : lvl_cnt + 1 : lvl_cnt;
  assign ref_sol  = lvl_cnt == '0;
  assign ref_eol  = lvl_cnt == PBS_L-1;

  always_ff @(posedge clk)
    if (!s_rst_n) lvl_cnt <= '0;
    else          lvl_cnt <= lvl_cntD;

// ============================================================================================== --
// Check
// ============================================================================================== --
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      error_value <= '0;
      error_side  <= '0;
      error_info  <= '0;
    end
    else begin
      if (out_avail) begin
        logic [PBS_L-1:0][PBS_B_W:0] ref_data;
        logic [SIDE_W-1:0]           ref_side;
        ref_data = ref_data_q.pop_back();
        ref_side = ref_side_q.pop_back();
        assert(ref_data == decomposer_out)
        else begin
          $display("%t > ERROR: Output mismatch : exp=0x%0x seen=0x%0x", $time, ref_data, decomposer_out);
          error_value <= 1'b1;
        end
        assert(ref_side == out_side)
        else begin
          $display("%t > ERROR: Side mismatch : exp=0x%0x seen=0x%0x", $time, ref_side, out_side);
          error_side <= 1'b1;
        end
        assert (ref_eol == out_eol && ref_sol == out_sol)
        else begin
          $display("%t > ERROR: Info mismatch : eol exp=%0d seen=%0d, sol exp=%0d seen=%0d", $time, ref_eol, out_eol, ref_sol, out_sol);
          error_info <= 1'b1;
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
        $display("%t > INFO: Output # %d / %d", $time, out_cnt, SAMPLE_NB);
    end

  assign end_of_test = (out_cnt == SAMPLE_NB);

endmodule
