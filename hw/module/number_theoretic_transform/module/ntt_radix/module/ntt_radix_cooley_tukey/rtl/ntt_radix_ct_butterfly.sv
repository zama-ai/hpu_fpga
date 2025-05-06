// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Performs a step of a Cooley-Tukey (CT) Butterfly
// ----------------------------------------------------------------------------------------------
//
// This module performs a step of a Radix-R Decimation-in-Time Cooley-Tukey Butterfly to be used in
// the NTT.
// It deals with:
//   a modular addition/substraction according to the butterfly architecture
// ==============================================================================================

module ntt_radix_ct_butterfly
#(
  parameter int        R           = 8, // Should be a power of 2.
  parameter int        OP_W        = 32,
  parameter [OP_W-1:0] MOD_M       = 2**OP_W - 2**(OP_W/2) + 1,
  parameter bit        IN_PIPE     = 1'b1,
  parameter bit        OUT_PIPE    = 1'b1,
  parameter int        SIDE_W      = 0,// Side data size. Set to 0 if not used
  parameter [1:0]      RST_SIDE    = 0 // If side data is used,
                                       // [0] (1) reset them to 0.
                                       // [1] (1) reset them to 1.

)
(
  // System interface
  input  logic                                   clk,
  input  logic                                   s_rst_n,
  // Data inteface
  input  logic [R-1:0][OP_W-1:0]                 in_x,
  output logic [R-1:0][OP_W-1:0]                 out_x,
  // Control
  input  logic [R-1:0]                           in_avail,
  output logic [R-1:0]                           out_avail,
  // Optional
  input  logic [SIDE_W-1:0]                      in_side,
  output logic [SIDE_W-1:0]                      out_side
);
  import mod_add_sub_pkg::*;

  // ============================================================================================ //
  // localparam
  // ============================================================================================ //
  // Check parameters
  generate
    if (2**$clog2(R) != R) begin: __UNSUPPORTED_R__
      $fatal(1,"> ERROR: R must be a power of 2! R=%d", R);
    end
  endgenerate

  // ============================================================================================ //
  // s0 : Modular addition and substraction
  // ============================================================================================ //
  logic [R-1:0][OP_W-1:0]         s1_x;
  logic [R-1:0]                   s1_avail;
  logic [SIDE_W-1:0]              s1_side;

  generate
    for (genvar gen_i = 0; gen_i < R/2; gen_i=gen_i+1) begin : gen_s0_loop
      // Modular addition
      if (gen_i == 0) begin: gen_s0_loop_0
        mod_add #(
          .OP_W     (OP_W),
          .MOD_M    (MOD_M),
          .IN_PIPE  (IN_PIPE),
          .OUT_PIPE (OUT_PIPE),
          .SIDE_W   (SIDE_W),
          .RST_SIDE (RST_SIDE)
        ) s0_mod_add (
          .clk      (clk             ),
          .s_rst_n  (s_rst_n         ),
          .a        (in_x[gen_i]     ),
          .b        (in_x[gen_i+R/2] ),
          .z        (s1_x[gen_i]     ),
          .in_avail (in_avail[gen_i] ),
          .out_avail(s1_avail[gen_i] ),
          .in_side  (in_side         ),
          .out_side (s1_side         )
        );
      end
      else begin: gen_s0_loop_gt_0
        mod_add #(
          .OP_W     (OP_W),
          .MOD_M    (MOD_M),
          .IN_PIPE  (IN_PIPE),
          .OUT_PIPE (OUT_PIPE),
          .SIDE_W   (0),    // UNUSED
          .RST_SIDE (2'b00) // UNUSED
        ) s0_mod_add (
          .clk      (clk            ),
          .s_rst_n  (s_rst_n        ),
          .a        (in_x[gen_i]    ),
          .b        (in_x[gen_i+R/2]),
          .z        (s1_x[gen_i]    ),
          .in_avail (in_avail[gen_i]),
          .out_avail(s1_avail[gen_i]),
          .in_side  ('x             ),
          .out_side (/*UNUSED*/     )
        );
      end

      // Modular substraction
      mod_sub #(
        .OP_W     (OP_W),
        .MOD_M    (MOD_M),
        .IN_PIPE  (IN_PIPE),
        .OUT_PIPE (OUT_PIPE),
        .SIDE_W   (0),    // UNUSED
        .RST_SIDE (2'b00) // UNUSED
      ) s0_mod_sub (
        .clk      (clk                ),
        .s_rst_n  (s_rst_n            ),
        .a        (in_x[gen_i]        ),
        .b        (in_x[gen_i+R/2]    ),
        .z        (s1_x[gen_i+R/2]    ),
        .in_avail (in_avail[gen_i+R/2]),
        .out_avail(s1_avail[gen_i+R/2]),
        .in_side  ('x                 ),
        .out_side (/*UNUSED*/         )
      );
    end
  endgenerate

  //============================================================================================ //
  // s1 : output
  //============================================================================================ //
  assign out_x       = s1_x;
  assign out_avail   = s1_avail;
  assign out_side    = s1_side;

endmodule
