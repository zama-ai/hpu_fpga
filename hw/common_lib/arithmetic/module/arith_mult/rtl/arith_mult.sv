// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : arith_mult
// ----------------------------------------------------------------------------------------------
//
// arith_mult : z = a * b.
//
// Parameters :
//  OP_A_W,
//  OP_B_W        : Operand width
//  MULT_TYPE     : Type of multiplier.
//                  Supported values are : "MULT_CORE", "MULT_KARATSUBA",
//                                         "MULT_GOLDILOCKS", "MULT_GOLDILOCKS_CASCADE"
// ==============================================================================================

module arith_mult
  import common_definition_pkg::*;
  import arith_mult_pkg::*;
#(
  parameter int     OP_A_W         = 64,
  parameter int     OP_B_W         = 64,
  parameter arith_mult_type_e MULT_TYPE = MULT_GOLDILOCKS_CASCADE,
  parameter bit     IN_PIPE        = 1, // Input pipe
  parameter int     SIDE_W         = 0, // Side data size. Set to 0 if not used
  parameter [1:0]   RST_SIDE       = 0  // If side data is used,
                                        // [0] (1) reset them to 0.
                                        // [1] (1) reset them to 1.
)
(
  // System interface
  input  logic                       clk,        // clock
  input  logic                       s_rst_n,    // synchronous reset
  // Data interface
  input  logic [OP_A_W-1:0]          a,          // operand a
  input  logic [OP_B_W-1:0]          b,          // operand b
  output logic [OP_A_W + OP_B_W-1:0] z,          // result
  // Control + side interface - optional
  input  logic                       in_avail,
  output logic                       out_avail,
  input  logic [SIDE_W-1:0]          in_side,
  output logic [SIDE_W-1:0]          out_side
);
// ============================================================================================== //
// arith_mult
// ============================================================================================== //
  generate
      if (MULT_TYPE == MULT_CORE) begin : gen_core
        arith_mult_core_with_side #(
          .OP_A_W  (OP_A_W   ),
          .OP_B_W  (OP_B_W   ),
          .IN_PIPE (IN_PIPE  ),
          .SIDE_W  (SIDE_W   ),
          .RST_SIDE(RST_SIDE )
        ) mult (
          .clk      (clk      ),
          .s_rst_n  (s_rst_n  ),
          .a        (a        ),
          .b        (b        ),
          .z        (z        ),
          .in_avail (in_avail ),
          .out_avail(out_avail),
          .in_side  (in_side  ),
          .out_side (out_side )
        );
      end
      else if (MULT_TYPE == MULT_KARATSUBA) begin : gen_karatsuba
        arith_mult_karatsuba #(
          .OP_A_W   (OP_A_W   ),
          .OP_B_W   (OP_B_W   ),
          .IN_PIPE  (IN_PIPE  ),
          .SIDE_W   (SIDE_W   ),
          .RST_SIDE (RST_SIDE )
        ) mult (
          .clk      (clk      ),
          .s_rst_n  (s_rst_n  ),
          .a        (a        ),
          .b        (b        ),
          .z        (z        ),
          .in_avail (in_avail ),
          .out_avail(out_avail),
          .in_side  (in_side  ),
          .out_side (out_side )
        );
      end
      else if (MULT_TYPE == MULT_KARATSUBA_CASCADE) begin : gen_karatsuba_cascade
        arith_mult_karatsuba_cascade #(
          .OP_A_W   (OP_A_W   ),
          .OP_B_W   (OP_B_W   ),
          .SIDE_W   (SIDE_W   ),
          .RST_SIDE (RST_SIDE )
        ) mult (
          .clk      (clk      ),
          .s_rst_n  (s_rst_n  ),
          .a        (a        ),
          .b        (b        ),
          .z        (z        ),
          .in_avail (in_avail ),
          .out_avail(out_avail),
          .in_side  (in_side  ),
          .out_side (out_side )
        );
      end
      else if (MULT_TYPE == MULT_GOLDILOCKS) begin : gen_goldilocks
        logic [97:0] z_int;
        arith_mult_64bgoldilocks_karatsuba #(
          .IN_PIPE  (IN_PIPE  ),
          .INTL_PIPE(INTL_PIPE), // Fixed in the arith_mult_pkg to '1'
          .SIDE_W   (SIDE_W   ),
          .RST_SIDE (RST_SIDE )
        ) mult (
          .clk      (clk      ),
          .s_rst_n  (s_rst_n  ),
          .a        (a        ),
          .b        (b        ),
          .z        (z_int    ),
          .in_avail (in_avail ),
          .out_avail(out_avail),
          .in_side  (in_side  ),
          .out_side (out_side )
        );
        assign z = {30'b0, z_int};
      end
      else if (MULT_TYPE == MULT_GOLDILOCKS_CASCADE) begin : gen_goldilocks_cascade
        logic [97:0] z_int;
        arith_mult_64bgoldilocks_karatsuba_cascade #(
          .SIDE_W   (SIDE_W   ),
          .RST_SIDE (RST_SIDE )
        ) mult (
          .clk      (clk      ),
          .s_rst_n  (s_rst_n  ),
          .a        (a        ),
          .b        (b        ),
          .z        (z_int    ),
          .in_avail (in_avail ),
          .out_avail(out_avail),
          .in_side  (in_side  ),
          .out_side (out_side )
        );
        assign z = {30'b0, z_int};
      end else begin : __GEN_UNKNOWN__
        $fatal(1,"> ERROR: Unknown MULT_TYPE %d", MULT_TYPE);
    end
  endgenerate


endmodule
