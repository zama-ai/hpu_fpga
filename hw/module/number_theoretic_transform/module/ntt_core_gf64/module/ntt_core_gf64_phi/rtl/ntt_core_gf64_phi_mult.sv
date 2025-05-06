// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the multiplication with phis.
//
// ==============================================================================================

module ntt_core_gf64_phi_mult
  import common_definition_pkg::*;
  import param_ntt_pkg::*;
  import ntt_core_common_param_pkg::*;
  import ntt_core_gf64_common_param_pkg::*;
  import ntt_core_gf64_phi_pkg::*;
  import ntt_core_gf64_phi_phi_pkg::*; // Contains list of Phis
#(
  parameter int    RDX_CUT_ID      = 1, // increasing numbering for FWD, decreasing for BWD
                                        // FWD : 1 means ngc
                                        // BWD : 0 means ngc
  parameter bit    BWD             = 1'b0,
  parameter arith_mult_type_e MULT_TYPE = MULT_CORE,
  parameter int    ROM_ITER_THRESHOLD   = 128,
  parameter int    ROM_LATENCY     = 2,
  parameter int    LVL_NB          = 2, // Number of interleaved levels
  parameter bit    IN_PIPE         = 1'b1, // Recommended
  parameter string TWD_GF64_FILE_PREFIX = "memory_file/twiddle/NTT_CORE_ARCH_GF64/R2_PSI16/twd_phi", // will be completed with the suffix _<b/fwd>_N<N_L>
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

  localparam bit USE_ROM = ITER_NB >= ROM_ITER_THRESHOLD;
  localparam bit USE_CST = ITER_NB < ROM_ITER_THRESHOLD && N_L <= R*PSI;

  localparam int OP_W    = MOD_NTT_W+2;

  localparam int WBLK_NB = N_L <= R*PSI ? (R*PSI) / N_L : 1;

  generate
    if (S_L > 11) begin : __UNSUPPORTED_S_L
      $fatal(1,"> ERROR: Twiddles were generated for N_L up to 2048. Here we need S_L=%0d",S_L);
    end
  endgenerate

// ============================================================================================== --
// s0
// ============================================================================================== --
// Input pipe
  logic [PSI*R-1:0][OP_W-1:0] s0_data;
  logic [PSI*R-1:0]           s0_avail;
  logic [SIDE_W-1:0]          s0_side;

  generate
    if (IN_PIPE) begin: gen_in_pipe
      always_ff @(posedge clk)
        if (!s_rst_n) s0_avail <= '0;
        else          s0_avail <= in_avail;

      always_ff @(posedge clk)
        s0_data <= in_data;
    end
    else begin : gen_no_in_pip
      assign s0_avail = in_avail;
      assign s0_data  = in_data;
    end
  endgenerate

  common_lib_delay_side #(
    .LATENCY    (IN_PIPE ),
    .SIDE_W     (SIDE_W  ),
    .RST_SIDE   (RST_SIDE)
  ) in_delay_side (
    .clk      (clk      ),
    .s_rst_n  (s_rst_n  ),

    .in_avail (in_avail[0] ),
    .out_avail(/*UNUSED*/),

    .in_side  (in_side  ),
    .out_side (s0_side  )
  );

// ============================================================================================== --
// function
// ============================================================================================== --
  function [PSI*R-1:0][63:0] get_cst_phi();
    var [N_L-1:0][63:0] phi_l;
    for (int l=0; l<L_NB; l=l+1)
      for (int a=0; a<A_NB; a=a+1)
        if (BWD) begin
          integer rev_l;
          rev_l = reverse_int(l,L_NB);
          if (IS_NGC)
            case (N_L)
              4   : phi_l[l*A_NB+a] = NTT_GF64_BWD_WDIV_N4_PHI_L[rev_l*(2*a+IS_NGC)];
              8   : phi_l[l*A_NB+a] = NTT_GF64_BWD_WDIV_N8_PHI_L[rev_l*(2*a+IS_NGC)];
              16  : phi_l[l*A_NB+a] = NTT_GF64_BWD_WDIV_N16_PHI_L[rev_l*(2*a+IS_NGC)];
              32  : phi_l[l*A_NB+a] = NTT_GF64_BWD_WDIV_N32_PHI_L[rev_l*(2*a+IS_NGC)];
              64  : phi_l[l*A_NB+a] = NTT_GF64_BWD_WDIV_N64_PHI_L[rev_l*(2*a+IS_NGC)];
              128 : phi_l[l*A_NB+a] = NTT_GF64_BWD_WDIV_N128_PHI_L[rev_l*(2*a+IS_NGC)];
              256 : phi_l[l*A_NB+a] = NTT_GF64_BWD_WDIV_N256_PHI_L[rev_l*(2*a+IS_NGC)];
              512 : phi_l[l*A_NB+a] = NTT_GF64_BWD_WDIV_N512_PHI_L[rev_l*(2*a+IS_NGC)];
              1024: phi_l[l*A_NB+a] = NTT_GF64_BWD_WDIV_N1024_PHI_L[rev_l*(2*a+IS_NGC)];
              2048: phi_l[l*A_NB+a] = NTT_GF64_BWD_WDIV_N2048_PHI_L[rev_l*(2*a+IS_NGC)];
              default:
                $fatal(1,"> ERROR: PHI for greater than 2048 is not supported.");
            endcase
          else
            case (N_L)
              4   : phi_l[l*A_NB+a] = NTT_GF64_BWD_N4_PHI_L[rev_l*(2*a+IS_NGC)];
              8   : phi_l[l*A_NB+a] = NTT_GF64_BWD_N8_PHI_L[rev_l*(2*a+IS_NGC)];
              16  : phi_l[l*A_NB+a] = NTT_GF64_BWD_N16_PHI_L[rev_l*(2*a+IS_NGC)];
              32  : phi_l[l*A_NB+a] = NTT_GF64_BWD_N32_PHI_L[rev_l*(2*a+IS_NGC)];
              64  : phi_l[l*A_NB+a] = NTT_GF64_BWD_N64_PHI_L[rev_l*(2*a+IS_NGC)];
              128 : phi_l[l*A_NB+a] = NTT_GF64_BWD_N128_PHI_L[rev_l*(2*a+IS_NGC)];
              256 : phi_l[l*A_NB+a] = NTT_GF64_BWD_N256_PHI_L[rev_l*(2*a+IS_NGC)];
              512 : phi_l[l*A_NB+a] = NTT_GF64_BWD_N512_PHI_L[rev_l*(2*a+IS_NGC)];
              1024: phi_l[l*A_NB+a] = NTT_GF64_BWD_N1024_PHI_L[rev_l*(2*a+IS_NGC)];
              2048: phi_l[l*A_NB+a] = NTT_GF64_BWD_N2048_PHI_L[rev_l*(2*a+IS_NGC)];
              default:
                $fatal(1,"> ERROR: PHI for greater than 2048 is not supported.");
            endcase
        end
        else begin
          integer rev_a;
          rev_a = reverse_int(a,A_NB);
          case (N_L)
            4   : phi_l[l*A_NB+a] = NTT_GF64_FWD_N4_PHI_L[rev_a*(2*l+IS_NGC)];
            8   : phi_l[l*A_NB+a] = NTT_GF64_FWD_N8_PHI_L[rev_a*(2*l+IS_NGC)];
            16  : phi_l[l*A_NB+a] = NTT_GF64_FWD_N16_PHI_L[rev_a*(2*l+IS_NGC)];
            32  : phi_l[l*A_NB+a] = NTT_GF64_FWD_N32_PHI_L[rev_a*(2*l+IS_NGC)];
            64  : phi_l[l*A_NB+a] = NTT_GF64_FWD_N64_PHI_L[rev_a*(2*l+IS_NGC)];
            128 : phi_l[l*A_NB+a] = NTT_GF64_FWD_N128_PHI_L[rev_a*(2*l+IS_NGC)];
            256 : phi_l[l*A_NB+a] = NTT_GF64_FWD_N256_PHI_L[rev_a*(2*l+IS_NGC)];
            512 : phi_l[l*A_NB+a] = NTT_GF64_FWD_N512_PHI_L[rev_a*(2*l+IS_NGC)];
            1024: phi_l[l*A_NB+a] = NTT_GF64_FWD_N1024_PHI_L[rev_a*(2*l+IS_NGC)];
            2048: phi_l[l*A_NB+a] = NTT_GF64_FWD_N2048_PHI_L[rev_a*(2*l+IS_NGC)];
            default:
              $fatal(1,"> ERROR: PHI for greater than 2048 is not supported.");
          endcase
        end

    get_cst_phi = {WBLK_NB{phi_l}};

  endfunction

// ============================================================================================== --
// Phi
// ============================================================================================== --
  logic [PSI-1:0][R-1:0][MOD_NTT_W-1:0] twd_phi;
  logic [PSI-1:0]                       twd_phi_vld;
  logic [PSI-1:0]                       twd_phi_rdy;

  generate
    if (USE_ROM) begin : gen_rom
      ntt_core_gf64_phi_rom #(
        .N_L             (N_L),
        .R               (R),
        .PSI             (PSI),
        .OP_W            (MOD_NTT_W),
        .LVL_NB          (LVL_NB),
        .TWD_GF64_FILE_PREFIX ($sformatf("%s_%s_N%0d",TWD_GF64_FILE_PREFIX, BWD ? "bwd":"fwd",N_L)),
        .ROM_LATENCY     (ROM_LATENCY)
      ) ntt_core_gf64_phi_rom (
        .clk         (clk),
        .s_rst_n     (s_rst_n),

        .twd_phi     (twd_phi),
        .twd_phi_vld (twd_phi_vld),
        .twd_phi_rdy (twd_phi_rdy)
      );
    end
    else if (USE_CST) begin : gen_cst
      localparam [PSI*R-1:0][63:0] PHI_CST = get_cst_phi();

      assign twd_phi_vld = '1;
      assign twd_phi     = PHI_CST;
    end
    else begin : gen_reg
      ntt_core_gf64_phi_reg
      #(
        .RDX_CUT_ID (RDX_CUT_ID),
        .R          (R),
        .PSI        (PSI),
        .BWD        (BWD),
        .LVL_NB     (LVL_NB)
      ) ntt_core_gf64_phi_reg (
        .clk         (clk),
        .s_rst_n     (s_rst_n),

        .twd_phi     (twd_phi),
        .twd_phi_vld (twd_phi_vld),
        .twd_phi_rdy (twd_phi_rdy)
      );
    end
  endgenerate

// ============================================================================================== --
// PMR multiplication
// ============================================================================================== --
  logic [PSI-1:0][R-1:0] twd_phi_rdy_tmp;

  always_comb
    for (int p=0; p<PSI; p=p+1)
      twd_phi_rdy[p] = twd_phi_rdy_tmp[p][0];

//pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      for (int p=0; p<PSI; p=p+1)
        assert(^twd_phi_rdy_tmp[p] == 1'b0)
        else begin
          $fatal(1,"%t > ERROR: twd_phi_rdy are not coherent for the R output for psi=%0d", $time, p);
        end
    end
//pragma translate_on

  generate
    for (genvar gen_p=0; gen_p<PSI; gen_p=gen_p+1) begin : gen_psi_loop
      for (genvar gen_r=0; gen_r<R; gen_r=gen_r+1) begin : gen_r_loop
        localparam int gen_i = gen_p*R+gen_r; // To ease the writing

        if (gen_i==0) begin : gen_0 // this path contains the side
          ntt_core_gf64_pmr_mult
          #(
            .MOD_NTT_W (MOD_NTT_W),
            .OP_W      (OP_W),
            .MULT_TYPE (MULT_TYPE),
            .IN_PIPE   (IN_PIPE),
            .SIDE_W    (SIDE_W),
            .RST_SIDE  (RST_SIDE)
          ) ntt_core_gf64_pmr_mult (
            .clk       (clk),
            .s_rst_n   (s_rst_n),

            .a         (in_data[gen_i]),
            .z         (out_data[gen_i]),

            .m         (twd_phi[gen_p][gen_r]),
            .m_vld     (twd_phi_vld[gen_p]),
            .m_rdy     (twd_phi_rdy_tmp[gen_p][gen_r]),

            .in_avail  (in_avail[gen_i]),
            .out_avail (out_avail[gen_i]),
            .in_side   (in_side),
            .out_side  (out_side)
          );

        end
        else begin : gen_no_0
          ntt_core_gf64_pmr_mult
          #(
            .MOD_NTT_W (MOD_NTT_W),
            .OP_W      (OP_W),
            .MULT_TYPE (MULT_TYPE),
            .IN_PIPE   (IN_PIPE),
            .SIDE_W    ('0), /* UNUSED*/
            .RST_SIDE  (2'b00) /*UNUSED*/
          ) ntt_core_gf64_pmr_mult (
            .clk       (clk),
            .s_rst_n   (s_rst_n),

            .a         (in_data[gen_i]),
            .z         (out_data[gen_i]),

            .m         (twd_phi[gen_p][gen_r]),
            .m_vld     (twd_phi_vld[gen_p]),
            .m_rdy     (twd_phi_rdy_tmp[gen_p][gen_r]),

            .in_avail  (in_avail[gen_i]),
            .out_avail (out_avail[gen_i]),
            .in_side   ('x), /*UNUSED*/
            .out_side  ()    /*UNUSED*/
          );
        end

      end // for gen_r
    end // for gen_p
  endgenerate

endmodule
