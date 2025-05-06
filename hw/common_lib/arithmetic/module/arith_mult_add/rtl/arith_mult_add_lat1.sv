// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : arith_mult_add
// ----------------------------------------------------------------------------------------------
//
// Multiplication followed by an addition : z = a * b + c.
//
// Written in such a way that the synthesizer may infer down to 1 clock cycle at least.
//
// ==============================================================================================

module arith_mult_add_lat1 #(
  parameter LATENCY = 1,   // Should be >= 1
                           // Number of cycles used for the multiplication + addition.
                           // These cycles will be used by the synthesizer for infering the
                           // best implementation of this operation.
  parameter OP_A_W  = 32,
  parameter OP_B_W  = 32,
  parameter OP_C_W  = 32   // Should be less or equal to OP_A_W + OP_B_W

  
)
(
    input  logic                       clk,        // clock
    input  logic [OP_A_W-1:0]          a,          // operand a
    input  logic [OP_B_W-1:0]          b,          // operand b
    input  logic [OP_C_W-1:0]          c,          // operand b
    output logic [OP_A_W + OP_B_W:0]   z           // result
);

  logic [OP_A_W + OP_B_W:0] s0_result;
  logic [OP_A_W-1:0]          s0_a;
  logic [OP_B_W-1:0]          s0_b;
  logic [OP_C_W-1:0]          s0_c;

  assign s0_a = a;
  assign s0_b = b;
  assign s0_c = c;

  //-- Step 0 : multiplication followed by addition
  assign s0_result = s0_a * s0_b + s0_c;
  

  // -- Delay line. Will be infered by synthesizer as cycles usable in the multiplication computation.
  logic [LATENCY-1:0][OP_A_W + OP_B_W:0] result_dly;

  generate
    if (LATENCY > 2) begin
      always_ff @(posedge clk) begin
        result_dly[0]           <= s0_result;
        result_dly[LATENCY-1:1] <= result_dly[LATENCY-2:0];
      end
    end else begin  // LATENCY < 2
      always_ff @(posedge clk) begin
        result_dly[0] <= s0_result;
      end
    end
  endgenerate


  assign z = result_dly[LATENCY-1];

endmodule

