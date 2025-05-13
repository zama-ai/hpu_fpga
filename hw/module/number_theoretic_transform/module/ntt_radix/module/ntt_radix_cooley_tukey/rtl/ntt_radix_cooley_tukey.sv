// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Performs a Cooley-Tukey (CT) Butterfly
// ----------------------------------------------------------------------------------------------
//
// This module performs a Radix-8 Decimation-in-Time Cooley-Tukey Butterfly to be used in
// the NTT.
//
// Assumptions :
//  > input array xt_a is in natural order
//  > output array xf_a is in reverse order
//  > input array phi_a contains the powers of phi, index of the array corresponds to the power.
//      Phi are the factors used for the point-wise multiplication part.
//  > input array omega_a contains the powers of omega, index of the array corresponds to the power.
//      Omega are the factor used in the matrix part.
//  > Concerning the omega, it is possible to choose between several sets.
//
// ==============================================================================================

module ntt_radix_cooley_tukey
  import common_definition_pkg::*;
#(
  parameter int        R             = 8,
  parameter mod_reduct_type_e     REDUCT_TYPE   = MOD_REDUCT_SOLINAS2,
  parameter mod_mult_type_e       MOD_MULT_TYPE = MOD_MULT_SOLINAS2,
  parameter arith_mult_type_e     MULT_TYPE     = MULT_KARATSUBA,
  parameter int        OP_W          = 32,
  parameter [OP_W-1:0] MOD_M         = 2**OP_W - 2**(OP_W/2) + 1,
  parameter int        OMG_SEL_NB    = 2,
  parameter bit        IN_PIPE       = 1'b1,
  parameter int        SIDE_W        = 0,// Side data size. Set to 0 if not used
  parameter [1:0]      RST_SIDE      = 0, // If side data is used,
                                       // [0] (1) reset them to 0.
                                       // [1] (1) reset them to 1.
  parameter  bit       USE_MOD_MULT  = 1,
  parameter  bit       OUT_NATURAL_ORDER = 1, //(0) Output in reverse2 order, (1) natural order
  localparam int       OMG_SEL_W     = OMG_SEL_NB == 1 ? 1 : $clog2(OMG_SEL_NB)
)
(
  // System interface
  input  logic                                     clk,
  input  logic                                     s_rst_n,
  // Data interface
  input  logic [R-1:0][OP_W-1:0]                   xt_a,
  output logic [R-1:0][OP_W-1:0]                   xf_a,
  input  logic [R-1:1][OP_W-1:0]                   phi_a,   // Phi root of unity
  input  logic [OMG_SEL_NB-1:0][R/2-1:0][OP_W-1:0] omg_a,   // quasi static signal
  input  logic [OMG_SEL_W-1:0]                     omg_sel, // data dependent selector
  // Control
  input  logic                                     in_avail,
  output logic                                     out_avail,
  // Optional
  input  logic [SIDE_W-1:0]                        in_side,
  output logic [SIDE_W-1:0]                        out_side
);
  import ntt_radix_cooley_tukey_pkg::*;

  // ============================================================================================ //
  // localparam
  // ============================================================================================ //
  // Architecture localparam
  localparam bit USE_OUT_FIFO       = 0; // To choose between FIFO or shift register for output sync.
  // Note that FIFO consumes less, but needs more logic

  // Design constant
  localparam int S_NB               = $clog2(R);
  localparam int LAT_MULT_BUTTERFLY = get_latency_mult_butterfly(MULT_TYPE, REDUCT_TYPE,
                                                                 MOD_MULT_TYPE, USE_MOD_MULT);
  localparam int LAT_BUTTERFLY      = get_latency_butterfly();

  // Check parameters
  generate
    if (2**$clog2(R) != R) begin: __UNSUPPORTED_R__
      $fatal(1,"> ERROR: R must be a power of 2! R=%d", R);
    end
  endgenerate

  // ============================================================================================ //
  // function
  // ============================================================================================ //
  // Per stage > 0, there are G groups.
  // Half data of a group are destinated to the butterfly, the other half to the mult_butterfly.
  function int get_group_nb (int stg); // for stg > 0
    return 2**(stg-1);
  endfunction

  function int get_group_halfelt_nb (int stg); // for stg > 0
    return R/(2**stg);
  endfunction

  function [R/2-1:0][31:0] get_omg_index(int stg);
    // The stage gives the stride.
    bit [R/2-1:0][31:0] pos;
    pos[0] = '0;
    for (int i=1; i<R/2; i=i+1) begin
      pos[i] = (pos[i-1] + get_group_nb(stg)) % (R/2);
    end
    return pos;
  endfunction

  function [R/2-1:0][31:0] get_fifo_depth(int stg);
    bit [R/2-1:0][31:0] depth;
    depth = '0;
    if (R > 2) begin
      for (int s=1; s<stg; s=s+1) begin
        int gr_nb;
        int elt_nb;
        gr_nb = get_group_nb(s);
        elt_nb = get_group_halfelt_nb(s);

        for (int g=0; g<gr_nb; g=g+1) begin
          for (int i=0; i<elt_nb/2; i=i+1) begin
            depth[g*elt_nb+i]          = depth[g*elt_nb+i]          + LAT_MULT_BUTTERFLY;
            depth[g*elt_nb+i+elt_nb/2] = depth[g*elt_nb+i+elt_nb/2] + LAT_BUTTERFLY;
          end
        end
      end
      for (int i=0; i<R/2; i=i+1) begin
        depth[i] = depth[i] - depth[R/2-1];
// pragma translate_off
        assert(depth[i] >= 0)
        else begin
          $fatal(1,"> ERROR: FIFO depth should be >= 0. R=%0d stg=%0d", R, stg);
        end
// pragma translate_on
      end
    end
    return depth;
  endfunction

  localparam [R/2-1:0][31:0] FIFO_DEPTH = get_fifo_depth(S_NB);

//  initial begin
//    for (int i=0; i<R/2; i=i+1) begin
//      $display("FIFO_DEPTH[%0d] = %0d", i, FIFO_DEPTH[i]);
//    end
//  end


  // ============================================================================================ //
  // s0
  // ============================================================================================ //
  // Stage 0 contains 1 group.
  // This group processes an input point-wise multiplication with the PHI root of unity,
  // followed by the butterfly.
  logic [R-1:0][OP_W-1:0]       s1_x;
  logic [R-1:0]                 s1_avail;
  logic [OMG_SEL_W-1:0]         s1_omg_sel;
  logic [SIDE_W-1:0]            s1_side;
  logic [OMG_SEL_W+SIDE_W-1:0]  in_side_tmp;
  logic [OMG_SEL_W+SIDE_W-1:0]  s1_side_tmp;

  generate
    if (SIDE_W > 0) begin : gen_in_side
      assign in_side_tmp           = {in_side, omg_sel};
      assign {s1_side, s1_omg_sel} = s1_side_tmp;
    end
    else begin : no_gen_in_side
      assign in_side_tmp = omg_sel;
      assign s1_omg_sel  = s1_side_tmp;
    end
  endgenerate

  ntt_radix_ct_mult_butterfly
  #(
    .R             (R),
    .REDUCT_TYPE   (REDUCT_TYPE),
    .MOD_MULT_TYPE (MOD_MULT_TYPE),
    .MULT_TYPE     (MULT_TYPE),
    .OP_W          (OP_W),
    .MOD_M         (MOD_M),
    .IN_PIPE       (IN_PIPE),
    .SIDE_W        (SIDE_W+OMG_SEL_W),
    .RST_SIDE      (RST_SIDE),
    .USE_MOD_MULT  (USE_MOD_MULT)
  ) s0_ntt_radix_ct_mult_butterfly (
    .clk        (clk          ),
    .s_rst_n    (s_rst_n      ),
    .in_x       (xt_a         ),
    .out_x      (s1_x         ),
    .in_omg     (phi_a        ),
    .in_avail   ({R{in_avail}}),
    .out_avail  (s1_avail     ),
    .in_side    (in_side_tmp  ),
    .out_side   (s1_side_tmp  )
  );

  // ============================================================================================ //
  // sn
  // ============================================================================================ //
  logic [S_NB:1][R-1:0  ][OP_W-1:0]      sn_x;
  logic [S_NB:1][R/2-1:0][OMG_SEL_W-1:0] sn_omg_sel;
  logic [S_NB:1][R-1:0  ]                sn_avail;
  logic [S_NB:1]         [SIDE_W-1:0]    sn_side;

  assign sn_side[1]    = s1_side;
  assign sn_x[1]       = s1_x;
  assign sn_avail[1]   = s1_avail;
  assign sn_omg_sel[1] = {R/2{s1_omg_sel}};

  // Extend omg_a, to avoid warning when selecting coeff [0]
  logic [OMG_SEL_NB-1:0][R/2-1:0][OP_W-1:0] omg_a_ext;

  generate
    if (R > 2) begin
      always_comb begin
        for (int i=0; i<OMG_SEL_NB; i=i+1) begin
          omg_a_ext[i][0]       = 1; // ^0 = constant 1
          omg_a_ext[i][R/2-1:1] = omg_a[i];
        end
      end
    end else begin
      assign omg_a_ext = 'x; // should not be used
    end
  endgenerate

  generate
    for (genvar gen_s=1; gen_s < S_NB; gen_s=gen_s+1) begin : gen_s_loop
      localparam int             R_NB    = get_group_halfelt_nb(gen_s);
      localparam [R/2-1:0][31:0] OMG_IDX = get_omg_index(gen_s);

//initial begin
//  $display(">>> gen_s=%0d R_NB=%0d", gen_s, R_NB);
//  for (int i=0; i<R/2; i=i+1) begin
//    $display("  OMG_IDX[%0d]=%0d", i, OMG_IDX[i]);
//  end
//end

      for (genvar gen_g=0; gen_g < get_group_nb(gen_s); gen_g=gen_g+1) begin : gen_g_loop
        logic [R/2-1:0][OP_W-1:0] sn_omg;

        always_comb begin
          sn_omg[0] = 1;
          for (int i=1; i<R/2; i=i+1) begin
            sn_omg[i] = omg_a[sn_omg_sel[gen_s][gen_g]][OMG_IDX[i]];
          end
        end

        ntt_radix_ct_butterfly
        #(
          .R           (R_NB),
          .OP_W        (OP_W),
          .MOD_M       (MOD_M),
          .IN_PIPE     (BUTTERFLY_IN_PIPE),
          .OUT_PIPE    (BUTTERFLY_OUT_PIPE),
          .SIDE_W      (OMG_SEL_W),
          .RST_SIDE    (2'b00)

        ) sn_ntt_radix_ct_butterfly (

          .clk        (clk                                  ),
          .s_rst_n    (s_rst_n                              ),
          .in_x       (sn_x[gen_s  ][2*gen_g*R_NB+:R_NB]    ),
          .out_x      (sn_x[gen_s+1][2*gen_g*R_NB+:R_NB]    ),
          .in_avail   (sn_avail[gen_s  ][2*gen_g*R_NB+:R_NB]),
          .out_avail  (sn_avail[gen_s+1][2*gen_g*R_NB+:R_NB]),
          .in_side    (sn_omg_sel[gen_s  ][gen_g]           ),
          .out_side   (sn_omg_sel[gen_s+1][2*gen_g]         )
        );

        ntt_radix_ct_mult_butterfly
        #(
          .R             (R_NB),
          .REDUCT_TYPE   (REDUCT_TYPE),
          .MOD_MULT_TYPE (MOD_MULT_TYPE),
          .MULT_TYPE     (MULT_TYPE),
          .OP_W          (OP_W),
          .MOD_M         (MOD_M),
          .IN_PIPE       (MULT_BUTTERFLY_IN_PIPE),
          .SIDE_W        (OMG_SEL_W),
          .RST_SIDE      (2'b00),
          .USE_MOD_MULT  (USE_MOD_MULT)
        ) sn_ntt_radix_ct_mult_butterfly (
          .clk        (clk                                      ),
          .s_rst_n    (s_rst_n                                  ),
          .in_x       (sn_x[gen_s  ][(2*gen_g+1)*R_NB+:R_NB]    ),
          .out_x      (sn_x[gen_s+1][(2*gen_g+1)*R_NB+:R_NB]    ),
          .in_omg     (sn_omg[1+:R_NB-1]             ),//(sn_omg[gen_g*R_NB+1+:R_NB-1]), // different way of writing
          .in_avail   (sn_avail[gen_s  ][(2*gen_g+1)*R_NB+:R_NB]),
          .out_avail  (sn_avail[gen_s+1][(2*gen_g+1)*R_NB+:R_NB]),
          .in_side    (sn_omg_sel[gen_s  ][gen_g]               ),
          .out_side   (sn_omg_sel[gen_s+1][2*gen_g+1]           )
        );

      end // for gen_g
      common_lib_delay_side #(
        .LATENCY    (LAT_MULT_BUTTERFLY ),
        .SIDE_W     (SIDE_W  ),
        .RST_SIDE   (RST_SIDE)
      ) sn_delay_side (
        .clk      (clk             ),
        .s_rst_n  (s_rst_n         ),
        .in_avail ('x              ),
        .out_avail(/*UNUSED*/      ),
        .in_side  (sn_side[gen_s  ]),
        .out_side (sn_side[gen_s+1])
      );

    end // for gen_s
  endgenerate

  // ============================================================================================ //
  // sl
  // ============================================================================================ //
  // Last stage : FIFO
  logic [R-1:0][OP_W-1:0]  sl_x;
  logic [R-1:0]            sl_avail;
  logic [SIDE_W-1:0]       sl_side;

  assign sl_x[R-2+:2]     = sn_x[S_NB][R-2+:2];
  assign sl_avail[R-2+:2] = sn_avail[S_NB][R-2+:2];
  assign sl_side          = sn_side[S_NB];
  generate
    if (USE_OUT_FIFO) begin : gen_out_fifo
      for (genvar gen_i=0; gen_i<R/2-1; gen_i=gen_i+1) begin : gen_fifo_loop
        logic sl_in_rdy;

        fifo_reg #(
          .WIDTH       (2*OP_W),
          .DEPTH       (FIFO_DEPTH[gen_i]),
          .LAT_PIPE_MH ({1'b1, 1'b1})
        ) sl_fifo (
          .clk     (clk                    ),
          .s_rst_n (s_rst_n                ),

          .in_data (sn_x[S_NB][2*gen_i+:2] ),
          .in_vld  (sn_avail[S_NB][2*gen_i]),
          .in_rdy  (sl_in_rdy              ),

          .out_data(sl_x[2*gen_i+:2]       ),
          .out_vld (sl_avail[2*gen_i]      ),
          .out_rdy (sl_avail[R-1]          )
        );
  // pragma translate_off
        // This FIFO must always be ready for input
        // This FIFO must always be valid for output
        always_ff @(posedge clk)
          if (!s_rst_n) begin
            // Do nothing
          end
          else begin
            if (sn_avail[S_NB][2*gen_i]) begin
              assert(sl_in_rdy)
              else begin
                $fatal(1, "%t > ERROR: Fifo[%0d] overflow!", $time, gen_i);
              end
            end
            if (sl_avail[R-1]) begin
              assert(sl_avail[2*gen_i])
              else begin
                $fatal(1, "%t > ERROR: Fifo[%0d] underflow!", $time, gen_i);
              end
            end
          end
  // pragma translate_on
      end
    end // gen_out_fifo
    else begin : gen_out_sr
      for (genvar gen_i=0; gen_i<R/2-1; gen_i=gen_i+1) begin : gen_sr_loop
        logic [FIFO_DEPTH[gen_i]-1:0][2*OP_W-1:0] sl_x_dly;
        logic [FIFO_DEPTH[gen_i]-1:0][1:0]        sl_avail_dly;
        logic [FIFO_DEPTH[gen_i]-1:0][2*OP_W-1:0] sl_x_dlyD;
        logic [FIFO_DEPTH[gen_i]-1:0][1:0]        sl_avail_dlyD;
        assign sl_x_dlyD[0]     = sn_x[S_NB][2*gen_i+:2];
        assign sl_avail_dlyD[0] = sn_avail[S_NB][2*gen_i+:2];
        if (FIFO_DEPTH[gen_i] > 1) begin
          assign sl_x_dlyD[FIFO_DEPTH[gen_i]-1:1]     = sl_x_dly[FIFO_DEPTH[gen_i]-2:0];
          assign sl_avail_dlyD[FIFO_DEPTH[gen_i]-1:1] = sl_avail_dly[FIFO_DEPTH[gen_i]-2:0];
        end

        always_ff @(posedge clk)
          if (!s_rst_n) sl_avail_dly <= '0;
          else          sl_avail_dly <= sl_avail_dlyD;

        always_ff @(posedge clk)
          sl_x_dly <= sl_x_dlyD;

        assign sl_x[2*gen_i+:2]     = sl_x_dly[FIFO_DEPTH[gen_i]-1];
        assign sl_avail[2*gen_i+:2] = sl_avail_dly[FIFO_DEPTH[gen_i]-1];
      end // for
// pragma translate_off
      always_ff @(posedge clk)
        if (!s_rst_n) begin
          // Do nothing
        end
        else begin
          assert(sl_avail == '0 || sl_avail == '1)
          else begin
            $fatal(1, "%t > ERROR: Desynchronization in the paths.", $time);
          end
        end
// pragma translate_on
    end // gen_out_sr
  endgenerate

  // ============================================================================================ //
  // Output
  // ============================================================================================ //
  generate
    if (OUT_NATURAL_ORDER) begin : gen_natural_order
      always_comb begin
        var [$clog2(R)-1:0] idx;
        for (int i=0; i<R; i=i+1) begin
          idx = {<<{i[$clog2(R)-1:0]}}; // reverse the bit order
          xf_a[i] = sl_x[idx];
        end
      end
    end
    else begin : gen_reverse_order
      assign xf_a      = sl_x;
    end
  endgenerate
  assign out_avail = sl_avail[R-1];
  assign out_side  = sl_side;


endmodule
