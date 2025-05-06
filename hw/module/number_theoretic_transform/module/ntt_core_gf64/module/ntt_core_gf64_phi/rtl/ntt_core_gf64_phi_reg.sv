// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the PHI root of unity for ntt_core_gf64.
// This modules handles cases with few unfriendly PHI per port. They are stored in a shift register.
// ==============================================================================================

module ntt_core_gf64_phi_reg
  import ntt_core_common_param_pkg::NTT_RDX_CUT_NB;
  import ntt_core_gf64_common_param_pkg::*;
  import ntt_core_gf64_phi_pkg::*;
  import ntt_core_gf64_phi_phi_pkg::*; // Contains list of Phis
#(
  parameter int    RDX_CUT_ID      = 1, // increasing numbering for FWD, decreasing for BWD
                                        // FWD : 1 means ngc
                                        // BWD : 0 means ngc
  parameter int    R               = 2, // Supports only value 2
  parameter int    PSI             = 16,
  parameter bit    BWD             = 1'b0,
  parameter int    LVL_NB          = 2 // Number of times the twd is kept
)
(
  input  logic                            clk,        // clock
  input  logic                            s_rst_n,    // synchronous reset

  output logic [PSI-1:0][R-1:0][63:0]     twd_phi,
  output logic [PSI-1:0]                  twd_phi_vld,
  input  logic [PSI-1:0]                  twd_phi_rdy

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
  localparam int LVL_W   = $clog2(LVL_NB) == 0 ? 1 : $clog2(LVL_NB);

  localparam [PSI-1:0][R-1:0][ITER_NB-1:0][63:0] PHI_L = get_phi_list();

  localparam int OP_W = 64;

  generate
    if (N_L <= R*PSI) begin : __UNSUPPORTED_N_L
      $fatal(1,"> ERROR: N_L(%0d) <= R*PSI (%0d) : should not use ntt_core_gf64_phi_reg!",N_L, R*PSI);
    end
    if ((!BWD && RDX_CUT_ID==0) || (BWD && RDX_CUT_ID==NTT_RDX_CUT_NB-1)) begin : __UNSUPPORTED_RDX_CUT_ID
      $fatal(1,"> ERROR: Architecture with phi multiplication before the radix column. Therefore, do not support FWD and RDX_CUT_ID==0 or BWD and RDX_CUT_ID==NTT_RDX_CUT_NB-1");
    end
    if (S_L > 11) begin : __UNSUPPORTED_S_L
      $fatal(1,"> ERROR: Twiddles were generated for N_L up to 2048. Here we need S_L=%0d",S_L);
    end
  endgenerate

// ============================================================================================== --
// function
// ============================================================================================== --
  function [PSI*R-1:0][ITER_NB-1:0][63:0] get_phi_list ();
    var [PSI*R-1:0][ITER_NB-1:0][63:0] iter_phi_l;
    var [N_L-1:0][63:0]                phi_l;
    // Order for phi multiplication at column input
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
        else begin // FWD
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

    for (int i=0; i<R*PSI; i=i+1)
      for (int j=0; j<ITER_NB; j=j+1)
        iter_phi_l[i][j] = phi_l[j*R*PSI+i];

    return iter_phi_l;
  endfunction

// ============================================================================================== --
// ntt_core_gf64_phi_reg
// ============================================================================================== --
  generate
    for (genvar gen_p=0; gen_p<PSI; gen_p=gen_p+1) begin
        localparam [R-1:0][ITER_NB-1:0][63:0] LL = PHI_L[gen_p];

        logic [R-1:0][OP_W-1:0] in_data;
        logic                   in_vld;
        logic                   in_rdy;

        // counter
        logic [LVL_W-1:0]  lvl;
        logic [ITER_W-1:0] iter;
        logic [LVL_W-1:0]  lvlD;
        logic [ITER_W-1:0] iterD;
        logic              last_lvl;
        logic              last_iter;

        assign last_lvl  = lvl == LVL_NB-1;
        assign last_iter = iter == ITER_NB-1;
        assign lvlD      = (in_vld && in_rdy) ? last_lvl  ? '0 : lvl + 1 : lvl;
        assign iterD     = (in_vld && in_rdy && last_lvl) ? last_iter ? '0 : iter + 1 : iter;

        assign in_data = {LL[1][iter],LL[0][iter]};

        always_ff @(posedge clk)
          if (!s_rst_n) begin
            lvl    <= '0;
            iter   <= '0;
            in_vld <= 1'b0;
          end
          else begin
            lvl    <= lvlD;
            iter   <= iterD;
            in_vld <= 1'b1;
          end

        fifo_element #(
          .WIDTH          (2*OP_W),
          .DEPTH          (2),
          .TYPE_ARRAY     ({4'h1,4'h2}),
          .DO_RESET_DATA  (1'b0),
          .RESET_DATA_VAL ('0)
        ) fifo_element (
           .clk      (clk),
           .s_rst_n  (s_rst_n),

           .in_data  (in_data),
           .in_vld   (in_vld),
           .in_rdy   (in_rdy),

           .out_data (twd_phi[gen_p]),
           .out_vld  (twd_phi_vld[gen_p]),
           .out_rdy  (twd_phi_rdy[gen_p])
          );

    end // for gen_p
  endgenerate
endmodule
