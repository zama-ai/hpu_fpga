// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : mod_reduct
// ----------------------------------------------------------------------------------------------
//
// Modular reduction wrapper.
// For more information, please see the concerned mod_reduct_* file.
//
// Supported REDUCT_TYPE are :
//   MERSENNE
//   BARRETT
//   SOLINAS2
// ==============================================================================================

module mod_reduct
  import common_definition_pkg::*;
#(
  parameter mod_reduct_type_e REDUCT_TYPE = MOD_REDUCT_SOLINAS2,
  parameter int          MOD_W       = 33,
  parameter [MOD_W-1:0]  MOD_M       = 2**MOD_W - 2**(MOD_W/2) + 1,
  parameter int          OP_W        = 2*MOD_W+1, // Should be in [MOD_W:2*MOD_W+1]
  parameter arith_mult_type_e MULT_TYPE   = MULT_CORE, // For Barrett
  parameter bit          IN_PIPE     = 1,
  parameter int          SIDE_W      = 0, // Side data size. Set to 0 if not used
  parameter [1:0]        RST_SIDE    = 0  // If side data is used,
                                          // [0] (1) reset them to 0.
                                          // [1] (1) reset them to 1.
)
(
    // System interface
    input  logic               clk,
    input  logic               s_rst_n,
    // Data interface
    input  logic [OP_W-1:0]    a,
    output logic [MOD_W-1:0]   z,
    // Control
    input  logic               in_avail,
    output logic               out_avail,

    input  logic [SIDE_W-1:0]  in_side,
    output logic [SIDE_W-1:0]  out_side
);

  generate
    if (REDUCT_TYPE == MOD_REDUCT_MERSENNE) begin : gen_mersenne
      mod_reduct_mersenne #(
        .MOD_W        (MOD_W),
        .MOD_M        (MOD_M),
        .OP_W         (OP_W),
        .IN_PIPE      (IN_PIPE),
        .SIDE_W       (SIDE_W),
        .RST_SIDE     (RST_SIDE)
      ) mod_reduct (
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
    else if (REDUCT_TYPE == MOD_REDUCT_BARRETT) begin : gen_barrett
      mod_reduct_barrett #(
        .MOD_W        (MOD_W),
        .MOD_M        (MOD_M),
        .OP_W         (OP_W),
        .MULT_TYPE    (MULT_TYPE),
        .IN_PIPE      (IN_PIPE),
        .SIDE_W       (SIDE_W),
        .RST_SIDE     (RST_SIDE)
      ) mod_reduct (
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
    else if (REDUCT_TYPE == MOD_REDUCT_SOLINAS2) begin : gen_solinas2
      mod_reduct_solinas2 #(
        .MOD_W        (MOD_W),
        .MOD_M        (MOD_M),
        .OP_W         (OP_W),
        .IN_PIPE      (IN_PIPE),
        .SIDE_W       (SIDE_W),
        .RST_SIDE     (RST_SIDE)
      ) mod_reduct (
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
    else if (REDUCT_TYPE == MOD_REDUCT_SOLINAS3) begin : gen_solinas3
      mod_reduct_solinas3 #(
        .MOD_W        (MOD_W),
        .MOD_M        (MOD_M),
        .OP_W         (OP_W),
        .IN_PIPE      (IN_PIPE),
        .SIDE_W       (SIDE_W),
        .RST_SIDE     (RST_SIDE)
      ) mod_reduct (
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
    else if (REDUCT_TYPE == MOD_REDUCT_GOLDILOCKS) begin : gen_64bgoldilocks
      mod_reduct_64bgoldilocks_karatsuba #(
        .OP_W         (OP_W),
        .IN_PIPE      (IN_PIPE),
        .SIDE_W       (SIDE_W),
        .RST_SIDE     (RST_SIDE)
      ) dut (
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
    else begin : __UNKNOWN_REDUCT_TYPE__
      $fatal(1, "> ERROR: Unknown REDUCT_TYPE %s", REDUCT_TYPE);
    end
  endgenerate
endmodule
