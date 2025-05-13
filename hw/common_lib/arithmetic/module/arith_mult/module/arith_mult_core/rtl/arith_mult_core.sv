// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : arith_mult_core
// ----------------------------------------------------------------------------------------------
//
// arith_mult_core : z = a * b.
//
// Parameters :
//  LATENCY       : Number of cycles used for the multiplication.
//                  These cycles will be used by the synthesizer for inferring the
//                  best implementation of this operation.
//                  In Xilinx architecture, the DSP 27x18 needs 2 cycles,
//                  or 3, according to the frequency.
//  OP_A_W,
//  OP_B_W        : Operand width
//
// ==============================================================================================

module arith_mult_core
#(
  parameter bit IN_PIPE  = 0, // Additional input pipe if needed.
  parameter int OP_A_W   = 16,
  parameter int OP_B_W   = 16

)
(
    input  logic                       clk,        // clock
    input  logic [OP_A_W-1:0]          a,          // operand a
    input  logic [OP_B_W-1:0]          b,          // operand b
    output logic [OP_A_W + OP_B_W-1:0] z           // result
);

  import arith_mult_core_pkg::*;

// ============================================================================================== //
// Check parameters
// ============================================================================================== //
  generate
    if (LATENCY < 1) begin : __UNSUPPORTED_LATENCY__
      $fatal(1, "> ERROR: Unsupported LATENCY value for arith_mult_core : should be >= 1.");
    end

    if (get_latency() != LATENCY) begin : __FUNCTION_OUT_OF_DATE__
      $fatal(1, "> ERROR: function get_latency is not aligned with the parameter LATENCY value. LATENCY=%0d get_latency=%0d",
                  LATENCY, get_latency());
    end
  endgenerate

// ============================================================================================== //
// Input pipe
// ============================================================================================== //
  logic [OP_A_W-1:0] s0_a;
  logic [OP_B_W-1:0] s0_b;

  generate
    if (IN_PIPE) begin
      always_ff @(posedge clk) begin
        s0_a <= a;
        s0_b <= b;
      end
    end
    else begin
      assign s0_a = a;
      assign s0_b = b;
    end
  endgenerate

// ============================================================================================== //
// Multiplication
// ============================================================================================== //
  logic [OP_A_W + OP_B_W-1:0] s0_result;

  assign s0_result = s0_a * s0_b;

// ============================================================================================== //
// Delay line
// ============================================================================================== //
//-- Delay line. Will be inferred by synthesizer as cycles usable in the multiplication computation.
  logic [LATENCY-1:0][OP_A_W + OP_B_W-1:0] result_dly;
  generate
    if (LATENCY >= 2) begin
      always_ff @(posedge clk) begin
        result_dly[0]           <= s0_result;
        result_dly[LATENCY-1:1] <= result_dly[LATENCY-2:0];
      end
    end else begin  // LATENCY < 2
      always_ff @(posedge clk)
        result_dly[0] <= s0_result;
    end
  endgenerate

  assign z = result_dly[LATENCY-1];

endmodule
