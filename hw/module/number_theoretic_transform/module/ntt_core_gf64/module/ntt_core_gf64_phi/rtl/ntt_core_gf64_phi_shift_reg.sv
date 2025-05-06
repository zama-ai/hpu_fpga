// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the PHI root of unity for ntt_core_gf64.
// This modules handles cases with few unfriendly PHI per port. They are stored in a shift register.
// Here the phis are power of 2. This occurs for cyclic working block of size <= 64.
// ==============================================================================================

module ntt_core_gf64_phi_shift_reg
  import ntt_core_common_param_pkg::NTT_RDX_CUT_NB;
  import ntt_core_gf64_common_param_pkg::*;
  import ntt_core_gf64_phi_pkg::*;
  import ntt_core_gf64_phi_phi_pkg::*; // Contains list of Phis
#(
  parameter int    RDX_CUT_ID      = 2, // increasing numbering for FWD, decreasing for BWD
                                        // FWD : 1 means ngc
                                        // BWD : 0 means ngc
  parameter int    R               = 2, // Supports only value 2
  parameter int    PSI             = 16,
  parameter bit    BWD             = 1'b0, // (1) BWD NTT, (0) FWD NTT
  parameter int    LVL_NB          = 2, // Number of times the twd is maintained at the output
  parameter int    SHIFT_W         = 8 // Number of bits to describe the shift value
)
(
  input  logic                            clk,        // clock
  input  logic                            s_rst_n,    // synchronous reset

  output logic [PSI-1:0][R-1:0][SHIFT_W-1:0] twd_phi_shift,
  output logic [PSI-1:0][R-1:0]           twd_phi_shift_sign, // (0) pos, (1) neg
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

  localparam int N_FACTOR = 64 / N_L;


  localparam [PSI-1:0][R-1:0][ITER_NB-1:0][31:0] SHIFT_L = get_shift_list();
  localparam [PSI-1:0][R-1:0][ITER_NB-1:0]       SIGN_L  = get_shift_sign_list();

  generate
    if (N_L <= R*PSI) begin : __UNSUPPORTED_N_L
      $fatal(1,"> ERROR: N_L(%0d) <= R*PSI (%0d) : should not use ntt_core_gf64_phi_shift_reg!",N_L, R*PSI);
    end
    if ((!BWD && RDX_CUT_ID < 2) || (BWD && RDX_CUT_ID==NTT_RDX_CUT_NB-1) || (BWD && RDX_CUT_ID==0)) begin : __UNSUPPORTED_RDX_CUT_ID
      $fatal(1,"> ERROR: Architecture with phi multiplication before the radix column. Therefore, do not support FWD and RDX_CUT_ID==0 nor BWD and RDX_CUT_ID==NTT_RDX_CUT_NB-1. For cyclic phi, so does not support FWD and RDX_CUT_ID==1 nor BWD and RDX_CUT_ID==0");
    end
    if (N_L > 64) begin : __UNSUPPORTED_N_L_2
      $fatal(1,"> ERROR: shift used for phi, is only possible for N_L (%0d) <= 64", N_L);
    end
  endgenerate

// ============================================================================================== --
// function
// ============================================================================================== --
  function [PSI*R-1:0][ITER_NB-1:0][31:0] get_shift_list ();
    var [PSI*R-1:0][ITER_NB-1:0][31:0] iter_shift_l;
    var [N_L-1:0][31:0]                w64_power_l;
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

    for (int i=0; i<R*PSI; i=i+1)
      for (int j=0; j<ITER_NB; j=j+1)
        iter_shift_l[i][j] = (w64_power_l[j*R*PSI+i]%32)*W64_2POWER;

    return iter_shift_l;
  endfunction

  function [PSI*R-1:0][ITER_NB-1:0] get_shift_sign_list ();
    var [PSI*R-1:0][ITER_NB-1:0] iter_sign_l;
    var [N_L-1:0][31:0]          w64_power_l;
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

    for (int i=0; i<R*PSI; i=i+1)
      for (int j=0; j<ITER_NB; j=j+1)
        iter_sign_l[i][j] = w64_power_l[j*R*PSI+i] >= 32; // W64**32 = -1

    return iter_sign_l;
  endfunction

// ============================================================================================== --
// ntt_core_gf64_phi_shift_reg
// ============================================================================================== --
  generate
    for (genvar gen_p=0; gen_p<PSI; gen_p=gen_p+1) begin
        localparam [R-1:0][ITER_NB-1:0][31:0] SH_L = SHIFT_L[gen_p];
        localparam [R-1:0][ITER_NB-1:0]       SI_L = SIGN_L[gen_p];

        logic [R-1:0][SHIFT_W-1:0] in_shift;
        logic [R-1:0]              in_sign;
        logic                      in_vld;
        logic                      in_rdy;

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

        assign in_shift = {SH_L[1][iter][SHIFT_W-1:0],SH_L[0][iter][SHIFT_W-1:0]};
        assign in_sign  = {SI_L[1][iter],SI_L[0][iter]};

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
          .WIDTH          (2*SHIFT_W+2),
          .DEPTH          (2),
          .TYPE_ARRAY     ({4'h1,4'h2}),
          .DO_RESET_DATA  (1'b0),
          .RESET_DATA_VAL ('0)
        ) fifo_element (
           .clk      (clk),
           .s_rst_n  (s_rst_n),

           .in_data  ({in_sign,in_shift}),
           .in_vld   (in_vld),
           .in_rdy   (in_rdy),

           .out_data ({twd_phi_shift_sign[gen_p],twd_phi_shift[gen_p]}),
           .out_vld  (twd_phi_vld[gen_p]),
           .out_rdy  (twd_phi_rdy[gen_p])
          );

    end // for gen_p
  endgenerate
endmodule
