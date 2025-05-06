// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Multiplication with a constant.
// If the constant is a particular type, accelerate the operation.
// ==============================================================================================

module arith_mult_constant
  import common_definition_pkg::*;
#(
  parameter int         IN_W           = 32,
  parameter int         CST_W          = 32,
  parameter [CST_W-1:0] CST            = 2**CST_W-2**(2*CST_W/3)-2**(CST_W/3)+1,
  parameter int_type_e  CST_TYPE       = INT_UNKNOWN,
  parameter arith_mult_type_e MULT_TYPE= MULT_KARATSUBA, // in case the constant has nothing special, choose the multiplier
  parameter             IN_PIPE        = 1'b1,
  parameter int         SIDE_W         = 0,// Side data size. Set to 0 if not used
  parameter [1:0]       RST_SIDE       = 0 // If side data is used,
                                       // [0] (1) reset them to 0.
                                       // [1] (1) reset them to 1.
)
(
  input  logic                  clk,        // clock
  input  logic                  s_rst_n,    // synchronous reset

  input  logic [IN_W-1:0]       a,
  output logic [IN_W+CST_W-1:0] z,
  input  logic                  in_avail,
  output logic                  out_avail,
  input  logic [SIDE_W-1:0]     in_side,
  output logic [SIDE_W-1:0]     out_side
);

// ============================================================================================== --
// arith_mult_constant
// ============================================================================================== --

  generate
    if (CST_TYPE == MERSENNE) begin : gen_mersenne
      arith_mult_cst_mersenne #(
        .IN_PIPE        (IN_PIPE      ),
        .IN_W           (IN_W         ),
        .CST_W          (CST_W        ),
        .CST            (CST          ),
        .SIDE_W         (SIDE_W       ),
        .RST_SIDE       (RST_SIDE     )
      ) arith_mult_cst (
        .clk      (clk      ),
        .s_rst_n  (s_rst_n  ),
        .a        (a        ),
        .z        (z        ),
        .in_avail (in_avail ),
        .out_avail(out_avail),               
        .in_side  (in_side  ),
        .out_side (out_side )
      );
    end
    else if (CST_TYPE == SOLINAS2
          || CST_TYPE == GOLDILOCKS) begin : gen_solinas2
      arith_mult_cst_solinas2 #(
        .IN_PIPE        (IN_PIPE      ),
        .IN_W           (IN_W         ),
        .CST_W          (CST_W        ),
        .CST            (CST          ),
        .SIDE_W         (SIDE_W       ),
        .RST_SIDE       (RST_SIDE     )
      ) arith_mult_cst (
        .clk      (clk      ),
        .s_rst_n  (s_rst_n  ),
        .a        (a        ),
        .z        (z        ),
        .in_avail (in_avail ),
        .out_avail(out_avail),
        .in_side  (in_side  ),
        .out_side (out_side )
      );
    end
    else if (CST_TYPE == SOLINAS3) begin : gen_solinas3
      arith_mult_cst_solinas3 #(
        .IN_PIPE        (IN_PIPE      ),
        .IN_W           (IN_W         ),
        .CST_W          (CST_W        ),
        .CST            (CST          ),
        .SIDE_W         (SIDE_W       ),
        .RST_SIDE       (RST_SIDE     )
      ) arith_mult_cst (
        .clk      (clk      ),
        .s_rst_n  (s_rst_n  ),
        .a        (a        ),
        .z        (z        ),
        .in_avail (in_avail ),
        .out_avail(out_avail),
        .in_side  (in_side  ),
        .out_side (out_side )
      );
    end
    else if (CST_TYPE == GOLDILOCKS_INV && CST_W==97) begin : gen_goldilocks_inv
      arith_mult_cst_goldilocks_inv #(
        .IN_PIPE        (IN_PIPE      ),
        .IN_W           (IN_W         ),
        .CST_W          (CST_W        ),
        .CST            (CST          ),
        .SIDE_W         (SIDE_W       ),
        .RST_SIDE       (RST_SIDE     )
      ) arith_mult_cst (
        .clk      (clk      ),
        .s_rst_n  (s_rst_n  ),
        .a        (a        ),
        .z        (z        ),
        .in_avail (in_avail ),
        .out_avail(out_avail),
        .in_side  (in_side  ),
        .out_side (out_side )
      );
    end
    else if (CST_TYPE == SOLINAS2_44_14_INV && CST_W==77) begin : gen_goldilocks_inv
      arith_mult_cst_solinas2_44_14_inv #(
        .IN_PIPE        (IN_PIPE      ),
        .IN_W           (IN_W         ),
        .CST_W          (CST_W        ),
        .CST            (CST          ),
        .SIDE_W         (SIDE_W       ),
        .RST_SIDE       (RST_SIDE     )
      ) arith_mult_cst (
        .clk      (clk      ),
        .s_rst_n  (s_rst_n  ),
        .a        (a        ),
        .z        (z        ),
        .in_avail (in_avail ),
        .out_avail(out_avail),
        .in_side  (in_side  ),
        .out_side (out_side )
      );
    end
    else begin : gen_unknown_type
        arith_mult #(
          .OP_A_W   (IN_W     ),
          .OP_B_W   (CST_W    ),
          .IN_PIPE  (IN_PIPE  ),
          .MULT_TYPE(MULT_TYPE),
          .SIDE_W   (SIDE_W   ),
          .RST_SIDE (RST_SIDE )
        ) mult (
          .clk      (clk      ),
          .s_rst_n  (s_rst_n  ),
          .a        (a        ),
          .b        (CST      ),
          .z        (z        ),
          .in_avail (in_avail ),
          .out_avail(out_avail),
          .in_side  (in_side  ),
          .out_side (out_side )
        );

    end
  endgenerate


endmodule
