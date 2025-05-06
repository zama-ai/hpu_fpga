// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the complete modular reduction.
//
// ==============================================================================================

module ntt_core_gf64_reduction
#(
  parameter int    C         = 32,// Number of coefficients
  parameter int    MOD_NTT_W = 64,
  parameter int    OP_W      = 66,
  parameter bit    IN_PIPE   = 1'b1,
  parameter int    SIDE_W    = 0, // Side data size. Set to 0 if not used
  parameter [1:0]  RST_SIDE  = 0  // If side data is used,
                                  // [0] (1) reset them to 0.
                                  // [1] (1) reset them to 1.
)
(
    input  logic                        clk,        // clock
    input  logic                        s_rst_n,    // synchronous reset

    input  logic [C-1:0][OP_W-1:0]      in_data, // 2s complement
    output logic [C-1:0][MOD_NTT_W-1:0] out_data,

    input  logic [C-1:0]                in_avail,
    output logic [C-1:0]                out_avail,
    input  logic [SIDE_W-1:0]           in_side,
    output logic [SIDE_W-1:0]           out_side
);

  generate
    for (genvar gen_i=0; gen_i<C; gen_i=gen_i+1) begin : gen_loop
      if (gen_i==0) begin : gen_0
        ntt_core_gf64_sign_reduction #(
          .MOD_NTT_W (MOD_NTT_W),
          .OP_W      (OP_W),
          .IN_PIPE   (IN_PIPE),
          .SIDE_W    (SIDE_W),
          .RST_SIDE  (RST_SIDE)
        ) ntt_core_gf64_sign_reduction (
          .clk        (clk),
          .s_rst_n    (s_rst_n),

          .a          (in_data[gen_i]),
          .z          (out_data[gen_i]),

          .in_avail   (in_avail[gen_i]),
          .out_avail  (out_avail[gen_i]),
          .in_side    (in_side),
          .out_side   (out_side)
        );
      end
      else begin : gen_no_0
        ntt_core_gf64_sign_reduction #(
          .MOD_NTT_W (MOD_NTT_W),
          .OP_W      (OP_W),
          .IN_PIPE   (IN_PIPE),
          .SIDE_W    ('0),
          .RST_SIDE  (RST_SIDE)
        ) ntt_core_gf64_sign_reduction (
          .clk        (clk),
          .s_rst_n    (s_rst_n),

          .a          (in_data[gen_i]),
          .z          (out_data[gen_i]),

          .in_avail   (in_avail[gen_i]),
          .out_avail  (out_avail[gen_i]),
          .in_side    ('x), /*UNUSED*/
          .out_side   (/*UNUSED*/)
        );
      end
    end
  endgenerate

endmodule
