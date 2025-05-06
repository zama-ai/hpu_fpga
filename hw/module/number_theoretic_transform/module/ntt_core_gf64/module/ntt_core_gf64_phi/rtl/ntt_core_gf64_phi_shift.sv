// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with friendly phis, where a shift could be done instead of a multiplication.
//
// ==============================================================================================

module ntt_core_gf64_phi_shift
  import common_definition_pkg::*;
  import param_ntt_pkg::*;
  import ntt_core_common_param_pkg::*;
  import ntt_core_gf64_common_param_pkg::*;
  import ntt_core_gf64_phi_pkg::*;
  import ntt_core_gf64_phi_phi_pkg::*; // Contains list of Phis
#(
  parameter int    RDX_CUT_ID      = 1, // increasing numbering for FWD, decreasing for BWD
                                        // FWD : 1 means ngc
                                        // BWD : 0 means ngc,
  parameter bit    BWD             = 1'b0,
  parameter int    LVL_NB          = 2, // Number of interleaved levels
  parameter bit    IN_PIPE         = 1'b1, // Recommended
  parameter int    SIDE_W          = 0, // Side data size. Set to 0 if not used
  parameter [1:0]  RST_SIDE        = 0  // If side data is used,
                                          // [0] (1) reset them to 0.
                                          // [1] (1) reset them to 1
)
(
    input  logic                            clk,        // clock
    input  logic                            s_rst_n,    // synchronous reset

    input  logic [PSI*R-1:0][MOD_NTT_W+1:0] in_data,
    output logic [PSI*R-1:0][MOD_NTT_W+1:0] out_data,

    input  logic [PSI*R-1:0]                in_avail,
    output logic [PSI*R-1:0]                out_avail,
    input  logic [SIDE_W-1:0]               in_side,
    output logic [SIDE_W-1:0]               out_side

);

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int S_L     = get_s_l(RDX_CUT_ID,BWD);
  localparam int N_L     = 2**S_L; // current working block size
  // Number of blocks in left radix column in the working block
  localparam int A_NB    = get_a_nb(RDX_CUT_ID,BWD);
  // Number of blocks in right radix column in the working block
  localparam int L_NB    = get_l_nb(RDX_CUT_ID,BWD);
  localparam bit IS_NGC  = is_ngc(RDX_CUT_ID, BWD);
  localparam int ITER_NB = get_iter_nb(RDX_CUT_ID,BWD);
  localparam int ITER_W  = $clog2(ITER_NB) == 0 ? 1 : $clog2(ITER_NB);

  localparam bit USE_CST = !IS_NGC && N_L <= R*PSI;

  localparam int OP_W    = MOD_NTT_W+2;
  localparam int SHIFT_W = $clog2(MOD_NTT_W + MOD_NTT_W/2); // max shift size

  localparam int N_FACTOR = 64 / N_L;
  localparam int WBLK_NB  = N_L <= R*PSI ? (R*PSI) / N_L : 1;

// ============================================================================================== --
// function
// ============================================================================================== --
  function [PSI*R-1:0][31:0] get_shift_list ();
    var [PSI*R-1:0][31:0] iter_shift_l;
    var [N_L-1:0][31:0]   w64_power_l;
    // Order for phi multiplication at column input
    for (int l=0; l<L_NB; l=l+1) begin
      integer rev_l;
      integer ll;
      rev_l = reverse_int(l,L_NB);
      ll = BWD ? rev_l : l;
      for (int a=0; a<A_NB; a=a+1) begin
        integer rev_a;
        integer aa;
        rev_a = reverse_int(a,A_NB);
        aa = BWD ? a : rev_a;
        w64_power_l[l*A_NB+a] = N_FACTOR * aa * ll; // W_{N_L} ** (aa*ll)
        if (BWD) begin // negative exponent
          w64_power_l[l*A_NB+a] = w64_power_l[l*A_NB+a] == 0 ? 0 : 64 - w64_power_l[l*A_NB+a];
        end
      end
    end
    iter_shift_l = {WBLK_NB{w64_power_l}};

    for (int i=0; i<PSI*R; i=i+1)
      get_shift_list[i] = (iter_shift_l[i]%32)*W64_2POWER;
  endfunction

  function [PSI*R-1:0] get_shift_sign_list ();
    var [PSI*R-1:0][31:0] iter_shift_l;
    var [N_L-1:0][31:0]   w64_power_l;
    // Order for phi multiplication at column input
    for (int l=0; l<L_NB; l=l+1) begin
      integer rev_l;
      integer ll;
      rev_l = reverse_int(l,L_NB);
      ll = BWD ? rev_l : l;
      for (int a=0; a<A_NB; a=a+1) begin
        integer rev_a;
        integer aa;
        rev_a = reverse_int(a,A_NB);
        aa = BWD ? a : rev_a;
        w64_power_l[l*A_NB+a] = N_FACTOR * aa * ll; // W_{N_L} ** (aa*ll)
        if (BWD) begin // negative exponent
          w64_power_l[l*A_NB+a] = w64_power_l[l*A_NB+a] == 0 ? 0 : 64 - w64_power_l[l*A_NB+a];
        end
      end
    end
    iter_shift_l = {WBLK_NB{w64_power_l}};

    for (int i=0; i<R*PSI; i=i+1)
      get_shift_sign_list[i] = iter_shift_l[i] >= 32; // W64**32 = -1
  endfunction


// ============================================================================================== --
// Shift
// ============================================================================================== --
  generate
    if (USE_CST) begin : gen_cst
      localparam [PSI*R-1:0][31:0] SHIFT_CST = get_shift_list();
      localparam [PSI*R-1:0]       SIGN_CST  = get_shift_sign_list();

      for (genvar gen_p=0; gen_p<PSI; gen_p=gen_p+1) begin : gen_psi_loop
        for (genvar gen_r=0; gen_r<R; gen_r=gen_r+1) begin : gen_r_loop
          localparam int gen_i = gen_p*R+gen_r; // To ease the writing


          if (gen_i==0) begin : gen_0 // this path contains the side
            ntt_core_gf64_pmr_shift_cst #(
              .MOD_NTT_W (MOD_NTT_W),
              .OP_W      (OP_W),
              .CST       (SHIFT_CST[gen_i]),
              .CST_SIGN  (SIGN_CST[gen_i]),
              .IN_PIPE   (IN_PIPE),
              .SIDE_W    (SIDE_W),
              .RST_SIDE  (RST_SIDE)
            ) ntt_core_gf64_pmr_shift_cst (
              .clk       (clk),
              .s_rst_n   (s_rst_n),

              .a         (in_data[gen_i]),
              .z         (out_data[gen_i]),

              .in_avail  (in_avail[gen_i]),
              .out_avail (out_avail[gen_i]),
              .in_side   (in_side),
              .out_side  (out_side)
            );

          end // gen_0
          else begin : gen_no_0
            ntt_core_gf64_pmr_shift_cst #(
              .MOD_NTT_W (MOD_NTT_W),
              .OP_W      (OP_W),
              .CST       (SHIFT_CST[gen_i]),
              .CST_SIGN  (SIGN_CST[gen_i]),
              .IN_PIPE   (IN_PIPE),
              .SIDE_W    ('0),
              .RST_SIDE  (RST_SIDE)
            ) ntt_core_gf64_pmr_shift_cst (
              .clk       (clk),
              .s_rst_n   (s_rst_n),

              .a         (in_data[gen_i]),
              .z         (out_data[gen_i]),

              .in_avail  (in_avail[gen_i]),
              .out_avail (out_avail[gen_i]),
              .in_side   ('x),
              .out_side  () /*UNUSED*/
            );
          end //gen_no_0

        end // gen_r
      end // gen_psi
    end // gen_cst
    else begin : gen_no_cst
      logic [PSI-1:0][R-1:0][SHIFT_W-1:0] twd_phi_shift;
      logic [PSI-1:0][R-1:0]              twd_phi_shift_sign; // (0) pos, (1) neg
      logic [PSI-1:0]                     twd_phi_vld;
      logic [PSI-1:0]                     twd_phi_rdy;

      ntt_core_gf64_phi_shift_reg
      #(
        .RDX_CUT_ID (RDX_CUT_ID),
        .R          (R),
        .PSI        (PSI),
        .BWD        (BWD),
        .LVL_NB     (LVL_NB),
        .SHIFT_W    (SHIFT_W)
      ) ntt_core_gf64_phi_shift_reg (
        .clk                 (clk),
        .s_rst_n             (s_rst_n),

        .twd_phi_shift       (twd_phi_shift),
        .twd_phi_shift_sign  (twd_phi_shift_sign),
        .twd_phi_vld         (twd_phi_vld),
        .twd_phi_rdy         (twd_phi_rdy)
      );

      always_comb
        for (int p=0; p<PSI; p=p+1)
          twd_phi_rdy[p] = in_avail[p*R + 0];

      for (genvar gen_p=0; gen_p<PSI; gen_p=gen_p+1) begin : gen_psi_loop
        for (genvar gen_r=0; gen_r<R; gen_r=gen_r+1) begin : gen_r_loop
          localparam int gen_i = gen_p*R+gen_r; // To ease the writing

          if (gen_i==0) begin : gen_0 // this path contains the side
            ntt_core_gf64_pmr_shift #(
              .MOD_NTT_W (MOD_NTT_W),
              .OP_W      (OP_W),
              .IN_PIPE   (IN_PIPE),
              .SIDE_W    (SIDE_W),
              .RST_SIDE  (RST_SIDE)
            ) ntt_core_gf64_pmr_shift (
              .clk       (clk),
              .s_rst_n   (s_rst_n),

              .a         (in_data[gen_i]),
              .s         (twd_phi_shift[gen_p][gen_r]),
              .s_sign    (twd_phi_shift_sign[gen_p][gen_r]),
              .z         (out_data[gen_i]),

              .in_avail  (in_avail[gen_i]),
              .out_avail (out_avail[gen_i]),
              .in_side   (in_side),
              .out_side  (out_side)
            );

          end // gen_0
          else begin : gen_no_0
            ntt_core_gf64_pmr_shift #(
              .MOD_NTT_W (MOD_NTT_W),
              .OP_W      (OP_W),
              .IN_PIPE   (IN_PIPE),
              .SIDE_W    (SIDE_W),
              .RST_SIDE  (RST_SIDE)
            ) ntt_core_gf64_pmr_shift (
              .clk       (clk),
              .s_rst_n   (s_rst_n),

              .a         (in_data[gen_i]),
              .s         (twd_phi_shift[gen_p][gen_r]),
              .s_sign    (twd_phi_shift_sign[gen_p][gen_r]),
              .z         (out_data[gen_i]),

              .in_avail  (in_avail[gen_i]),
              .out_avail (out_avail[gen_i]),
              .in_side   ('x),
              .out_side  () /*UNUSED*/
            );

          end // gen_no_0
        end
      end
    end // gen_no_cst
  endgenerate

endmodule
