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
//   a multiplication
//   an addition/subtraction according to the butterfly architecture
//   a modular reduction.
// ==============================================================================================

module ntt_radix_ct_mult_butterfly
  import common_definition_pkg::*;
#(
  parameter int        R             = 8, // Should be a power of 2.
  parameter mod_reduct_type_e     REDUCT_TYPE   = MOD_REDUCT_SOLINAS2,
  parameter mod_mult_type_e       MOD_MULT_TYPE = MOD_MULT_SOLINAS2,
  parameter arith_mult_type_e     MULT_TYPE     = MULT_KARATSUBA,
  parameter int        OP_W          = 32,
  parameter [OP_W-1:0] MOD_M         = 2**OP_W - 2**(OP_W/2) + 1,
  parameter bit        IN_PIPE       = 1'b1,
  parameter int        SIDE_W        = 0,// Side data size. Set to 0 if not used
  parameter [1:0]      RST_SIDE      = 0,// If side data is used,
                                       // [0] (1) reset them to 0.
                                       // [1] (1) reset them to 1.
  parameter bit        USE_MOD_MULT  = 1
)
(
  // System interface
  input  logic                   clk,
  input  logic                   s_rst_n,
  // Data interface
  input  logic [R-1:0][OP_W-1:0] in_x,
  output logic [R-1:0][OP_W-1:0] out_x,
  input  logic [R-1:1][OP_W-1:0] in_omg,
  // Control
  input  logic [R-1:0]           in_avail,
  output logic [R-1:0]           out_avail,
  // Optional
  input  logic [SIDE_W-1:0]      in_side,
  output logic [SIDE_W-1:0]      out_side
);
  import arith_mult_pkg::*;
  import mod_reduct_pkg::*;

  // ============================================================================================ //
  // localparam
  // ============================================================================================ //
  // If subtraction gives a negative value, add this constant to get a positive value in
  // [0,2**(2*OP_W+1)-1], which can be reduce.
  localparam [2*OP_W:0] MOD_CORR = ((2**(2*OP_W)-1+(MOD_M-1))/MOD_M)*MOD_M;
  // Check parameters
  generate
    if (2**$clog2(R) != R) begin: __UNSUPPORTED_R__
      $fatal(1,"> ERROR: R must be a power of 2! R=%d", R);
    end
  endgenerate


  generate
    if (!USE_MOD_MULT) begin : no_gen_use_mod_mult
      //============================================================================================ //
      // s1 : Multiplication
      //============================================================================================ //
      logic [R-1:0][2*OP_W-1:0] s1_mult;
      logic [R-1:0]             s1_avail;
      logic [SIDE_W-1:0]        s1_side;

      for (genvar gen_i = 1; gen_i < R; gen_i=gen_i+1) begin : gen_s0_loop
        if (gen_i == 1) begin : gen_s0_loop_1
          logic [OP_W+SIDE_W-1:0] in_data;
          logic [OP_W+SIDE_W-1:0] s1_data;
          if (SIDE_W > 0) begin
            assign in_data                         = {in_side,in_x[0]};
            assign {s1_side, s1_mult[0][OP_W-1:0]} = s1_data;
            assign s1_mult[0][OP_W+:OP_W]          = '0;
          end
          else begin
            assign in_data    = in_x[0];
            assign s1_mult[0] = s1_data; // extend msb with 0s
          end
          arith_mult #(
            .OP_A_W         (OP_W),
            .OP_B_W         (OP_W),
            .MULT_TYPE      (MULT_TYPE),
            .IN_PIPE        (IN_PIPE),
            .SIDE_W         (OP_W + SIDE_W),
            .RST_SIDE       (RST_SIDE)
          ) s0_arith_mult (
            .clk      (clk        ),
            .s_rst_n  (s_rst_n    ),
            .a        (in_x[1]    ),
            .b        (in_omg[1]  ),
            .z        (s1_mult[1] ),
            .in_avail (in_avail[1]),
            .out_avail(s1_avail[1]),
            .in_side  (in_data    ),
            .out_side (s1_data    )
          );
          assign s1_avail[0] = s1_avail[1];

        end
        else begin : gen_s0_loop_gt_1
          arith_mult #(
            .OP_A_W         (OP_W),
            .OP_B_W         (OP_W),
            .MULT_TYPE      (MULT_TYPE),
            .IN_PIPE        (IN_PIPE),
            .SIDE_W         (0),    // UNUSED
            .RST_SIDE       (2'b00) // UNUSED
          ) s0_arith_mult (
            .clk      (clk            ),
            .s_rst_n  (s_rst_n        ),
            .a        (in_x[gen_i]    ),
            .b        (in_omg[gen_i]  ),
            .z        (s1_mult[gen_i] ),
            .in_avail (in_avail[gen_i]),
            .out_avail(s1_avail[gen_i]),
            .in_side  ('x             ),
            .out_side (/*UNUSED*/     )
          );

        end
      end // gen_s0_loop

      //============================================================================================ //
      // s1 : Butterfly
      //============================================================================================ //
      logic [R-1:0][2*OP_W:0]   s2_add_sub;
      logic [R-1:R/2][2*OP_W:0] s2_sub; //signed
      logic [SIDE_W-1:0]        s2_side;
      logic [R-1:0]             s2_avail;

      for (genvar gen_i = 0; gen_i < R/2; gen_i=gen_i+1) begin : gen_s0_1_loop
        // Addition
        assign s2_add_sub[gen_i]     = s1_mult[gen_i] + s1_mult[gen_i+R/2];

        // Subtraction
        assign s2_sub[gen_i+R/2]     = {1'b0,s1_mult[gen_i]} - {1'b0,s1_mult[gen_i+R/2]};
        // If the subtraction is negative, correct it with MOD_CORR to retrieve a positive
        // value.
        assign s2_add_sub[gen_i+R/2] = s2_sub[gen_i+R/2][2*OP_W] ?
                                              s2_sub[gen_i+R/2] + MOD_CORR : s2_sub[gen_i+R/2];
  // pragma translate_off
  // Check that the corrected value does not exceed 2*OP_W+1 bits.
        logic [2*OP_W+1:0] _tmp;
        assign _tmp = {s2_sub[gen_i+R/2][2*OP_W],s2_sub[gen_i+R/2]} + MOD_CORR;
        always_ff @(posedge clk)
          if (s1_avail[gen_i]) begin
            assert(!s2_sub[gen_i+R/2][2*OP_W] || !_tmp[2*OP_W+1])
            else begin
              $fatal(1, "%t > ERROR: Negative value overflow! a_mult[%0d]=0x%0x b_mult[%0d]=0x%0x",
                        $time, gen_i,s1_mult[gen_i],gen_i+R/2,s1_mult[gen_i+R/2]);

            end
          end
  // pragma translate_on
      end

      assign s2_avail = s1_avail;
      assign s2_side  = s1_side;

      //============================================================================================ //
      // s2 : Modular reduction
      //============================================================================================ //
      logic [R-1:0][OP_W-1:0] s3_x;
      logic [SIDE_W-1:0]      s3_side;
      logic [R-1:0]           s3_avail;
      for (genvar gen_i = 0; gen_i < R; gen_i=gen_i+1) begin : gen_s2_loop
        if (gen_i == 0) begin: gen_s2_loop_0
          mod_reduct #(
            .REDUCT_TYPE (REDUCT_TYPE),
            .MOD_W       (OP_W),
            .MOD_M       (MOD_M),
            .OP_W        (2*OP_W+1),
            .MULT_TYPE   (MULT_TYPE),
            .IN_PIPE     (1),
            .SIDE_W      (SIDE_W),
            .RST_SIDE    (RST_SIDE)
          ) s2_mod_reduct (
              .clk      (clk              ),
              .s_rst_n  (s_rst_n          ),
              .a        (s2_add_sub[gen_i]),
              .z        (s3_x[gen_i]      ),
              .in_avail (s2_avail[gen_i]  ),
              .out_avail(s3_avail[gen_i]  ),
              .in_side  (s2_side          ),
              .out_side (s3_side          )
          );
        end
        else begin : gen_s2_loop_gt_0
          mod_reduct #(
            .REDUCT_TYPE (REDUCT_TYPE),
            .MOD_W       (OP_W),
            .MOD_M       (MOD_M),
            .OP_W        (2*OP_W+1),
            .MULT_TYPE   (MULT_TYPE),
            .IN_PIPE     (1),
            .SIDE_W      (0),    // UNUSED
            .RST_SIDE    (2'b00) // UNUSED
          ) s2_mod_reduct (
              .clk      (clk              ),
              .s_rst_n  (s_rst_n          ),
              .a        (s2_add_sub[gen_i]),
              .z        (s3_x[gen_i]      ),
              .in_avail (s2_avail[gen_i]  ),
              .out_avail(s3_avail[gen_i]  ),
              .in_side  ('x               ),
              .out_side (/*UNUSED*/)
          );
        end
      end

      //============================================================================================ //
      // s3 : output
      //============================================================================================ //
      assign out_x       = s3_x;
      assign out_avail   = s3_avail;
      assign out_side    = s3_side;

    end
    else begin : gen_use_mod_mult
      //============================================================================================ //
      // s1 : Modular Multiplication
      //============================================================================================ //
      logic [R-1:0][OP_W-1:0] s1_mult;
      logic [R-1:0]           s1_avail;
      logic [SIDE_W-1:0]      s1_side;

      for (genvar gen_i = 1; gen_i < R; gen_i=gen_i+1) begin : gen_s0_loop
        if (gen_i == 1) begin : gen_s0_loop_1
          logic [OP_W+SIDE_W-1:0] in_data;
          logic [OP_W+SIDE_W-1:0] s1_data;
          if (SIDE_W > 0) begin
            assign in_data                         = {in_side,in_x[0]};
            assign {s1_side, s1_mult[0][OP_W-1:0]} = s1_data;
          end
          else begin
            assign in_data    = in_x[0];
            assign s1_mult[0] = s1_data; // extend msb with 0s
          end
          mod_mult #(
            .MOD_MULT_TYPE (MOD_MULT_TYPE),
            .MOD_W         (OP_W         ),
            .MOD_M         (MOD_M        ),
            .MULT_TYPE     (MULT_TYPE    ),
            .IN_PIPE       (IN_PIPE      ),
            .SIDE_W        (OP_W+SIDE_W  ),
            .RST_SIDE      (RST_SIDE     )
          ) s0_mod_mult (
            .clk      (clk        ),
            .s_rst_n  (s_rst_n    ),
            .a        (in_x[1]    ),
            .b        (in_omg[1]  ),
            .z        (s1_mult[1] ),
            .in_avail (in_avail[1]),
            .out_avail(s1_avail[1]),
            .in_side  (in_data    ),
            .out_side (s1_data    )
          );
          assign s1_avail[0] = s1_avail[1];

        end
        else begin : gen_s0_loop_gt_1
          mod_mult #(
            .MOD_MULT_TYPE (MOD_MULT_TYPE),
            .MOD_W         (OP_W         ),
            .MOD_M         (MOD_M        ),
            .MULT_TYPE     (MULT_TYPE    ),
            .IN_PIPE       (IN_PIPE      ),
            .SIDE_W        (0            ), // UNUSED
            .RST_SIDE      (2'b00        )  // UNUSED
          ) s0_mod_mult (
            .clk      (clk            ),
            .s_rst_n  (s_rst_n        ),
            .a        (in_x[gen_i]    ),
            .b        (in_omg[gen_i]  ),
            .z        (s1_mult[gen_i] ),
            .in_avail (in_avail[gen_i]),
            .out_avail(s1_avail[gen_i]),
            .in_side  ('x             ),
            .out_side (/*UNUSED*/     )
          );

        end
      end // gen_s0_loop

      //============================================================================================ //
      // s2 : Butterfly
      //============================================================================================ //
      ntt_radix_ct_butterfly
      #(
        .R           (R       ),
        .OP_W        (OP_W    ),
        .MOD_M       (MOD_M   ),
        .IN_PIPE     (0       ),
        .OUT_PIPE    (1       ),
        .SIDE_W      (SIDE_W  ),
        .RST_SIDE    (RST_SIDE)
      ) s1_ntt_radix_ct_butterfly (
        .clk        (clk      ),
        .s_rst_n    (s_rst_n  ),
        .in_x       (s1_mult  ),
        .out_x      (out_x    ),
        .in_avail   (s1_avail ),
        .out_avail  (out_avail),
        .in_side    (s1_side  ),
        .out_side   (out_side )
      );
    end
  endgenerate

endmodule
