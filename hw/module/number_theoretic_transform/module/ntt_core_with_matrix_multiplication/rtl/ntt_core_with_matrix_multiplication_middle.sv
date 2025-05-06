// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// NTT core tackles the NTT and INTT computations by using the same DIT butterfly-units.
// It also computes a matrix multiplication.
// This module includes the twiddle phi run and twiddle intt final, since their instance is
// architecture dependent.
//
// Prerequisites :
// Input data are interleaved in time, to avoid an output accumulator.
// Input order is the "incremental stride" order, with R**(S-1) as the stride.
// Output data are also interleaved in time.
// Output order is also the "incremental stride" order.
//
// 5 flavors are available (NTT_CORE_ARCH):
// NTT_CORE_ARCH_WMM_COMPACT  : The compact architecture uses the same logic to implement all the stages.
// NTT_CORE_ARCH_WMM_PIPELINE : The pipeline architecture: the forward process is done entirely before the loopback.
// NTT_CORE_ARCH_WMM_UNFOLD   : The unfold architecture: NTT and INTT are executed sequentially.
// NTT_CORE_ARCH_WMM_COMPACT_PCG  : The compact pcg architecture uses the same logic to implement all the stages.
// NTT_CORE_ARCH_WMM_UNFOLD_PCG   : The unfold pcg architecture: NTT and INTT are executed sequentially.
//
// This is defined in the ntt_core_wmm_pkg.
//
// The "dimension" of the NTT (R, PSI, DELTA) is given by ntt_core_common_param_pkg
//
// To fit the SLRs, the current version proposes a partition into several parts.
// Note : Only NTT_CORE_ARCH_WMM_UNFOLD_PCG flavor is used.
//
// ==============================================================================================

`include "ntt_core_common_macro_inc.sv"

module ntt_core_with_matrix_multiplication_middle
  import param_tfhe_pkg::*;
  import pep_common_param_pkg::*;
  import common_definition_pkg::*;
  import ntt_core_wmm_pkg::*;
#(
  parameter  int           OP_W                  = 32,
  parameter  [OP_W-1:0]    MOD_NTT               = 2**32-2**17-2**13+1,
  parameter  int_type_e    MOD_NTT_TYPE          = SOLINAS3,
  parameter  mod_mult_type_e   MOD_MULT_TYPE     = MOD_MULT_SOLINAS3,
  parameter  mod_reduct_type_e REDUCT_TYPE       = MOD_REDUCT_SOLINAS3,
  parameter  arith_mult_type_e MULT_TYPE         = MULT_KARATSUBA,
  parameter  mod_mult_type_e   PP_MOD_MULT_TYPE  = MOD_MULT_SOLINAS3,
  parameter  arith_mult_type_e PP_MULT_TYPE      = MULT_KARATSUBA,
  parameter  ntt_core_arch_e   NTT_CORE_ARCH     = NTT_CORE_ARCH_WMM_UNFOLD_PCG,
  parameter  int           R                     = 8, // Butterfly Radix
  parameter  int           PSI                   = 8, // Number of butterflies
  parameter  int           S                     = $clog2(N)/$clog2(R), // Number of stages
  parameter  int           DELTA                 = 4,
  parameter  int           BWD_PSI_DIV           = 1,
  parameter  int           RAM_LATENCY           = 1,
  parameter  int           ROM_LATENCY           = 1,
  parameter  int           S_INIT                = S/2, // First stage index
  parameter  int           S_NB                  = S, // Number of NTT stages
  parameter  bit           USE_PP                = 1, // If this part has the PP as border, indicates if the PP is included.
                                                      // Note that if the FWD and BWD NTT are both present, the PP
                                                      // is instanciated
  parameter  string        TWD_IFNL_FILE_PREFIX  = NTT_CORE_ARCH == NTT_CORE_ARCH_WMM_UNFOLD ?
                                                        "memory_file/twiddle/NTT_CORE_ARCH_WMM/R8_PSI8_S3/SOLINAS3_32_17_13/twd_ifnl_bwd"    :
                                                        "memory_file/twiddle/NTT_CORE_ARCH_WMM/R8_PSI8_S3/SOLINAS3_32_17_13/twd_ifnl",
  parameter  string        TWD_PHRU_FILE_PREFIX  = "memory_file/twiddle/NTT_CORE_ARCH_WMM/R8_PSI8_S3/SOLINAS3_32_17_13/twd_phru",
  localparam int           ERROR_W               = 2    // [1:0] ntt
                                                   + 2  // [3:2] twd phru
) (
  input                                            clk,
  input                                            s_rst_n,

  // Input data from previous part
  // If this part starts with BWD, use only R*BWD_PSI coefficients
  input  [PSI-1:0][R-1:0][OP_W-1:0]                prev_data,
  input  [PSI-1:0][R-1:0]                          prev_data_avail,
  input                                            prev_sob,
  input                                            prev_eob,
  input                                            prev_sol,
  input                                            prev_eol,
  input                                            prev_sos,
  input                                            prev_eos,
  input  [BPBS_ID_W-1:0]                           prev_pbs_id,
  input                                            prev_ctrl_avail,

  // Output data to next part
  // Note that if this partition outputs before the PP, the
  // output has R*PSI coefficients
  // If not then only R*BWD_PSI coefficients are used.
  output [PSI-1:0][R-1:0][OP_W-1:0]                next_data,
  output [PSI-1:0][R-1:0]                          next_data_avail,
  output                                           next_sob,
  output                                           next_eob,
  output                                           next_sol,
  output                                           next_eol,
  output                                           next_sos,
  output                                           next_eos,
  output [BPBS_ID_W-1:0]                           next_pbs_id,
  output                                           next_ctrl_avail,

  // Twiddles
  // Powers of omega : [i] = omg_ru_r ** i
  // quasi static signal
  input  [1:0][R/2-1:0][OP_W-1:0]                  twd_omg_ru_r_pow, // Not used when R=2

  // Matrix factors : BSK
  // Only used if the PP is in this part.
  input  [PSI-1:0][R-1:0][GLWE_K_P1-1:0][OP_W-1:0] bsk,
  input  [PSI-1:0][R-1:0][GLWE_K_P1-1:0]           bsk_vld,
  output [PSI-1:0][R-1:0][GLWE_K_P1-1:0]           bsk_rdy,

  // batch command from accumulator
  input  [BR_BATCH_CMD_W-1:0]                      batch_cmd,
  input                                            batch_cmd_avail,
  // Error
  output [ERROR_W-1:0]                             ntt_error
);

  // ============================================================================================ //
  // localparam
  // ============================================================================================ //
  `NTT_CORE_LOCALPARAM(R,S,PSI)

  localparam int BWD_PSI           = PSI / BWD_PSI_DIV;

  //== Error
  localparam int NTT_ERROR_NB      = 2;
  localparam int TWD_PHRU_ERROR_NB = 2;

  localparam int NTT_ERROR_OFS      = 0;
  localparam int TWD_PHRU_ERROR_OFS = NTT_ERROR_OFS + NTT_ERROR_NB;

  //== NTT core param
  localparam int LPB_NB = 1;

  localparam int LS_DELTA = S % DELTA == 0 ? DELTA : S % DELTA;
  localparam int RS_DELTA = DELTA;

  localparam bit USE_FWD = S_INIT < S;
  localparam bit USE_BWD = (S_INIT > S-1) | ((S_INIT - S_NB) < -1);

  localparam int FWD_S_INIT = S_INIT;
  localparam int BWD_S_INIT = USE_FWD ? S+S-1 : S_INIT;

  localparam int FWD_S_IDX_INIT = S-1-FWD_S_INIT;
  localparam int BWD_S_IDX_INIT = 2*S-1-BWD_S_INIT;

  localparam int FWD_S_NB   = USE_FWD ? S - FWD_S_IDX_INIT > S_NB ? S_NB : S - FWD_S_IDX_INIT : 0;
  localparam int BWD_S_NB   = USE_FWD ? S_NB - FWD_S_NB : S_NB;

  localparam bit USE_FWD_RS = USE_FWD & (FWD_S_INIT >= (S-RS_DELTA));
  localparam bit USE_FWD_LS = (USE_FWD_RS & ((FWD_S_IDX_INIT + FWD_S_NB) > RS_DELTA)) | (USE_FWD & ~USE_FWD_RS);

  localparam bit USE_BWD_RS = USE_BWD & (BWD_S_INIT >= (2*S-RS_DELTA));
  localparam bit USE_BWD_LS = (USE_BWD_RS & ((BWD_S_IDX_INIT + BWD_S_NB) > RS_DELTA)) | (USE_BWD & ~USE_BWD_RS);

  localparam int FWD_D_NB_0 = USE_FWD_RS ? (RS_DELTA - FWD_S_IDX_INIT) > FWD_S_NB ? FWD_S_NB : RS_DELTA - FWD_S_IDX_INIT : 0;
  localparam int FWD_D_NB_1 = USE_FWD_LS ? USE_FWD_RS ? FWD_S_NB - FWD_D_NB_0 : FWD_S_NB : 0;

  localparam int BWD_D_NB_0 = USE_BWD_RS ? (RS_DELTA - BWD_S_IDX_INIT) > BWD_S_NB ? BWD_S_NB : RS_DELTA - BWD_S_IDX_INIT : 0;
  localparam int BWD_D_NB_1 = USE_BWD_LS ? USE_BWD_RS ? BWD_S_NB - BWD_D_NB_0 : BWD_S_NB : 0;

  // To avoid warning, when used as signal width
  localparam int FWD_D_NB_0_W = FWD_D_NB_0 == 0 ? 1 : FWD_D_NB_0;
  localparam int FWD_D_NB_1_W = FWD_D_NB_1 == 0 ? 1 : FWD_D_NB_1;

  localparam int BWD_D_NB_0_W = BWD_D_NB_0 == 0 ? 1 : BWD_D_NB_0;
  localparam int BWD_D_NB_1_W = BWD_D_NB_1 == 0 ? 1 : BWD_D_NB_1;

  localparam int FWD_D_INIT_0 = FWD_S_IDX_INIT;
  localparam int FWD_D_INIT_1 = USE_FWD_RS ? 0 : FWD_S_IDX_INIT - RS_DELTA;

  localparam int BWD_D_INIT_0 = USE_FWD_LS ? 0 : BWD_S_IDX_INIT;
  localparam int BWD_D_INIT_1 = USE_BWD_RS ? 0 : BWD_S_IDX_INIT - RS_DELTA;

  localparam int FWD_S_INIT_0 = FWD_S_INIT;
  localparam int FWD_S_INIT_1 = USE_FWD_RS ? S-1 - RS_DELTA : FWD_S_INIT;

  localparam int BWD_S_INIT_0 = BWD_S_INIT;
  localparam int BWD_S_INIT_1 = USE_BWD_RS ? S-1 - RS_DELTA : BWD_S_INIT;

  localparam bit LOCAL_USE_PP = (USE_FWD && USE_BWD) ? 1 : USE_PP;

  // ============================================================================================ //
  // Signals
  // ============================================================================================ //
  logic [PSI-1:0]                                             prev_data_avail_tmp;

  //== FWD signals
  logic [1:0][PSI-1:0][R-1:0][OP_W-1:0]                       in_clbu_fwd_data;
  logic [1:0][PSI-1:0]                                        in_clbu_fwd_data_avail;
  logic [1:0]                                                 in_clbu_fwd_sob;
  logic [1:0]                                                 in_clbu_fwd_eob;
  logic [1:0]                                                 in_clbu_fwd_sol;
  logic [1:0]                                                 in_clbu_fwd_eol;
  logic [1:0]                                                 in_clbu_fwd_sos;
  logic [1:0]                                                 in_clbu_fwd_eos;
  logic [1:0][BPBS_ID_W-1:0]                                  in_clbu_fwd_pbs_id;
  logic [1:0]                                                 in_clbu_fwd_ctrl_avail;

  logic [1:0][PSI-1:0][R-1:0][OP_W-1:0]                       out_clbu_fwd_data;
  logic [1:0][PSI-1:0]                                        out_clbu_fwd_data_avail;
  logic [1:0][PSI-1:0][R-1:0]                                 out_clbu_fwd_data_avail_ext;
  logic [1:0]                                                 out_clbu_fwd_sob;
  logic [1:0]                                                 out_clbu_fwd_eob;
  logic [1:0]                                                 out_clbu_fwd_sol;
  logic [1:0]                                                 out_clbu_fwd_eol;
  logic [1:0]                                                 out_clbu_fwd_sos;
  logic [1:0]                                                 out_clbu_fwd_eos;
  logic [1:0][BPBS_ID_W-1:0]                                  out_clbu_fwd_pbs_id;
  logic [1:0]                                                 out_clbu_fwd_ctrl_avail;

  logic [PSI-1:0][R-1:0][OP_W-1:0]                            out_ntw_fwd_data;
  logic [PSI-1:0][R-1:0]                                      out_ntw_fwd_data_avail;
  logic [PSI-1:0]                                             out_ntw_fwd_data_avail_tmp;
  logic                                                       out_ntw_fwd_sob;
  logic                                                       out_ntw_fwd_eob;
  logic                                                       out_ntw_fwd_sol;
  logic                                                       out_ntw_fwd_eol;
  logic                                                       out_ntw_fwd_sos;
  logic                                                       out_ntw_fwd_eos;
  logic [BPBS_ID_W-1:0]                                       out_ntw_fwd_pbs_id;
  logic                                                       out_ntw_fwd_ctrl_avail;

  //== BWD
  logic [1:0][BWD_PSI-1:0][R-1:0][OP_W-1:0]                   in_clbu_bwd_data;
  logic [1:0][BWD_PSI-1:0]                                    in_clbu_bwd_data_avail;
  logic [1:0][BWD_PSI-1:0][R-1:0]                             in_clbu_bwd_data_avail_ext;
  logic [1:0]                                                 in_clbu_bwd_sob;
  logic [1:0]                                                 in_clbu_bwd_eob;
  logic [1:0]                                                 in_clbu_bwd_sol;
  logic [1:0]                                                 in_clbu_bwd_eol;
  logic [1:0]                                                 in_clbu_bwd_sos;
  logic [1:0]                                                 in_clbu_bwd_eos;
  logic [1:0][BPBS_ID_W-1:0]                                  in_clbu_bwd_pbs_id;
  logic [1:0]                                                 in_clbu_bwd_ctrl_avail;

  logic [1:0][BWD_PSI-1:0][R-1:0][OP_W-1:0]                   out_clbu_bwd_data;
  logic [1:0][BWD_PSI-1:0]                                    out_clbu_bwd_data_avail;
  logic [1:0][BWD_PSI-1:0][R-1:0]                             out_clbu_bwd_data_avail_ext;
  logic [1:0]                                                 out_clbu_bwd_sob;
  logic [1:0]                                                 out_clbu_bwd_eob;
  logic [1:0]                                                 out_clbu_bwd_sol;
  logic [1:0]                                                 out_clbu_bwd_eol;
  logic [1:0]                                                 out_clbu_bwd_sos;
  logic [1:0]                                                 out_clbu_bwd_eos;
  logic [1:0][BPBS_ID_W-1:0]                                  out_clbu_bwd_pbs_id;
  logic [1:0]                                                 out_clbu_bwd_ctrl_avail;

  logic [BWD_PSI-1:0][R-1:0][OP_W-1:0]                        out_ntw_bwd_data;
  logic [BWD_PSI-1:0][R-1:0]                                  out_ntw_bwd_data_avail;
  logic [BWD_PSI-1:0]                                         out_ntw_bwd_data_avail_tmp;
  logic                                                       out_ntw_bwd_sob;
  logic                                                       out_ntw_bwd_eob;
  logic                                                       out_ntw_bwd_sol;
  logic                                                       out_ntw_bwd_eol;
  logic                                                       out_ntw_bwd_sos;
  logic                                                       out_ntw_bwd_eos;
  logic [BPBS_ID_W-1:0]                                       out_ntw_bwd_pbs_id;
  logic                                                       out_ntw_bwd_ctrl_avail;

  logic [PSI-1:0][R-1:0][OP_W-1:0]                            ntt_acc_data;
  logic [PSI-1:0][R-1:0]                                      ntt_acc_data_avail;
  logic                                                       ntt_acc_sob;
  logic                                                       ntt_acc_eob;
  logic                                                       ntt_acc_sol;
  logic                                                       ntt_acc_eol;
  logic                                                       ntt_acc_sog;
  logic                                                       ntt_acc_eog;
  logic [BPBS_ID_W-1:0]                                       ntt_acc_pbs_id;
  logic                                                       ntt_acc_ctrl_avail;

  logic [FWD_S_IDX_INIT+FWD_S_NB-1:FWD_S_IDX_INIT][PSI-1:0][R-1:1][OP_W-1:0]    twd_phi_ru_fwd; // [0] is for the 1rst stage
  logic [FWD_S_IDX_INIT+FWD_S_NB-1:FWD_S_IDX_INIT][PSI-1:0]                     twd_phi_ru_fwd_vld;
  logic [FWD_S_IDX_INIT+FWD_S_NB-1:FWD_S_IDX_INIT][PSI-1:0]                     twd_phi_ru_fwd_rdy;

  logic [BWD_S_IDX_INIT+BWD_S_NB-1:BWD_S_IDX_INIT][BWD_PSI-1:0][R-1:1][OP_W-1:0]twd_phi_ru_bwd; // [0] is for the 1rst stage
  logic [BWD_S_IDX_INIT+BWD_S_NB-1:BWD_S_IDX_INIT][BWD_PSI-1:0]                 twd_phi_ru_bwd_vld;
  logic [BWD_S_IDX_INIT+BWD_S_NB-1:BWD_S_IDX_INIT][BWD_PSI-1:0]                 twd_phi_ru_bwd_rdy;

  logic [BWD_PSI-1:0][R-1:0][OP_W-1:0]                                          twd_intt_final;
  logic [BWD_PSI-1:0][R-1:0]                                                    twd_intt_final_vld;
  logic [BWD_PSI-1:0][R-1:0]                                                    twd_intt_final_rdy;

  logic [1:0][NTT_ERROR_NB-1:0]                                                 ntt_error_fwd;
  logic [1:0][NTT_ERROR_NB-1:0]                                                 ntt_error_bwd;
  logic [FWD_S_IDX_INIT+FWD_S_NB-1:FWD_S_IDX_INIT][TWD_PHRU_ERROR_NB-1:0]       twd_phru_error_fwd_l;
  logic [BWD_S_IDX_INIT+BWD_S_NB-1:BWD_S_IDX_INIT][TWD_PHRU_ERROR_NB-1:0]       twd_phru_error_bwd_l;

  // ============================================================================================ //
  // Error
  // ============================================================================================ //
  logic [TWD_PHRU_ERROR_NB-1:0] twd_phru_error_l_tmp;

  assign ntt_error[NTT_ERROR_OFS+:NTT_ERROR_NB]           = ntt_error_fwd[0]
                                                          | ntt_error_fwd[1]
                                                          | ntt_error_bwd[0]
                                                          | ntt_error_bwd[1];
  assign ntt_error[TWD_PHRU_ERROR_OFS+:TWD_PHRU_ERROR_NB] = twd_phru_error_l_tmp;
  always_comb begin
    var [TWD_PHRU_ERROR_NB-1:0] tmp;
    tmp = 0;
    for (int i=FWD_S_IDX_INIT; i<FWD_S_IDX_INIT+FWD_S_NB; i=i+1)
      tmp = tmp | twd_phru_error_fwd_l[i];
    for (int i=BWD_S_IDX_INIT; i<BWD_S_IDX_INIT+BWD_S_NB; i=i+1)
      tmp = tmp | twd_phru_error_bwd_l[i];
    twd_phru_error_l_tmp = tmp;
  end

  // ============================================================================================ //
  // Format signal
  // ============================================================================================ //
    always_comb
      for (int p=0; p<PSI; p=p+1) begin
        prev_data_avail_tmp[p]        = prev_data_avail[p][0];
        out_ntw_fwd_data_avail_tmp[p] = out_ntw_fwd_data_avail[p][0];
      end

    always_comb
      for (int p=0; p<PSI; p=p+1)
        for (int i=0; i<2; i=i+1)
          out_clbu_fwd_data_avail_ext[i][p] = {R{out_clbu_fwd_data_avail[i][p]}};

    always_comb
      for (int p=0; p<BWD_PSI; p=p+1)
        for (int i=0; i<2; i=i+1) begin
          out_clbu_bwd_data_avail_ext[i][p] = {R{out_clbu_bwd_data_avail[i][p]}};
          in_clbu_bwd_data_avail_ext[i][p]  = {R{in_clbu_bwd_data_avail[i][p]}};
        end

    always_comb
      for (int p=0; p<BWD_PSI; p=p+1)
        out_ntw_bwd_data_avail_tmp[p] = out_ntw_bwd_data_avail[p][0];

  // ============================================================================================ //
  // Instances
  // ============================================================================================ //
  // ------------------------------------------------------------------------------------------- --
  // FWD RS
  // ------------------------------------------------------------------------------------------- --
  generate
    if (USE_FWD_RS) begin : gen_fwd_rs
      assign in_clbu_fwd_data[0]       = prev_data;
      assign in_clbu_fwd_data_avail[0] = prev_data_avail_tmp;
      assign in_clbu_fwd_sob[0]        = prev_sob;
      assign in_clbu_fwd_eob[0]        = prev_eob;
      assign in_clbu_fwd_sol[0]        = prev_sol;
      assign in_clbu_fwd_eol[0]        = prev_eol;
      assign in_clbu_fwd_sos[0]        = prev_sos;
      assign in_clbu_fwd_eos[0]        = prev_eos;
      assign in_clbu_fwd_pbs_id[0]     = prev_pbs_id;
      assign in_clbu_fwd_ctrl_avail[0] = prev_ctrl_avail;

      ntt_core_with_matrix_multiplication_unfold_pcg_middle_fwd
      #(
        .OP_W          (OP_W),
        .MOD_NTT       (MOD_NTT),
        .MOD_NTT_TYPE  (MOD_NTT_TYPE),
        .MOD_MULT_TYPE (MOD_MULT_TYPE),
        .REDUCT_TYPE   (REDUCT_TYPE),
        .MULT_TYPE     (MULT_TYPE),
        .PP_MOD_MULT_TYPE (PP_MOD_MULT_TYPE),
        .PP_MULT_TYPE     (PP_MULT_TYPE),
        .R             (R),
        .PSI           (PSI),
        .S             (S),
        .DELTA         (RS_DELTA),
        .BWD_PSI_DIV   (BWD_PSI_DIV),
        .S_INIT        (FWD_S_INIT_0),
        .D_INIT        (FWD_D_INIT_0),
        .D_NB          (FWD_D_NB_0),
        .IS_LS         (0),
        .USE_PP        (0),
        .RAM_LATENCY   (RAM_LATENCY)
      ) ntt_core_with_matrix_multiplication_unfold_pcg_middle_fwd_rs (
        .clk                     (clk),
        .s_rst_n                 (s_rst_n),

        .in_clbu_fwd_data        (in_clbu_fwd_data[0]      ),
        .in_clbu_fwd_data_avail  (in_clbu_fwd_data_avail[0]),
        .in_clbu_fwd_sob         (in_clbu_fwd_sob[0]       ),
        .in_clbu_fwd_eob         (in_clbu_fwd_eob[0]       ),
        .in_clbu_fwd_sol         (in_clbu_fwd_sol[0]       ),
        .in_clbu_fwd_eol         (in_clbu_fwd_eol[0]       ),
        .in_clbu_fwd_sos         (in_clbu_fwd_sos[0]       ),
        .in_clbu_fwd_eos         (in_clbu_fwd_eos[0]       ),
        .in_clbu_fwd_pbs_id      (in_clbu_fwd_pbs_id[0]    ),
        .in_clbu_fwd_ctrl_avail  (in_clbu_fwd_ctrl_avail[0]),

        .out_clbu_fwd_data       (out_clbu_fwd_data[0]      ),
        .out_clbu_fwd_data_avail (out_clbu_fwd_data_avail[0]),
        .out_clbu_fwd_sob        (out_clbu_fwd_sob[0]       ),
        .out_clbu_fwd_eob        (out_clbu_fwd_eob[0]       ),
        .out_clbu_fwd_sol        (out_clbu_fwd_sol[0]       ),
        .out_clbu_fwd_eol        (out_clbu_fwd_eol[0]       ),
        .out_clbu_fwd_sos        (out_clbu_fwd_sos[0]       ),
        .out_clbu_fwd_eos        (out_clbu_fwd_eos[0]       ),
        .out_clbu_fwd_pbs_id     (out_clbu_fwd_pbs_id[0]    ),
        .out_clbu_fwd_ctrl_avail (out_clbu_fwd_ctrl_avail[0]),

        .out_ntw_fwd_data        (out_ntw_fwd_data),
        .out_ntw_fwd_data_avail  (out_ntw_fwd_data_avail),
        .out_ntw_fwd_sob         (out_ntw_fwd_sob),
        .out_ntw_fwd_eob         (out_ntw_fwd_eob),
        .out_ntw_fwd_sol         (out_ntw_fwd_sol),
        .out_ntw_fwd_eol         (out_ntw_fwd_eol),
        .out_ntw_fwd_sos         (out_ntw_fwd_sos),
        .out_ntw_fwd_eos         (out_ntw_fwd_eos),
        .out_ntw_fwd_pbs_id      (out_ntw_fwd_pbs_id),
        .out_ntw_fwd_ctrl_avail  (out_ntw_fwd_ctrl_avail),

        .in_clbu_bwd_data        (/*UNUSED*/),
        .in_clbu_bwd_data_avail  (/*UNUSED*/),
        .in_clbu_bwd_sob         (/*UNUSED*/),
        .in_clbu_bwd_eob         (/*UNUSED*/),
        .in_clbu_bwd_sol         (/*UNUSED*/),
        .in_clbu_bwd_eol         (/*UNUSED*/),
        .in_clbu_bwd_sos         (/*UNUSED*/),
        .in_clbu_bwd_eos         (/*UNUSED*/),
        .in_clbu_bwd_pbs_id      (/*UNUSED*/),
        .in_clbu_bwd_ctrl_avail  (/*UNUSED*/),

        .twd_omg_ru_r_pow        (twd_omg_ru_r_pow),

        .twd_phi_ru_fwd          (twd_phi_ru_fwd[FWD_D_INIT_0+:FWD_D_NB_0_W]),
        .twd_phi_ru_fwd_vld      (twd_phi_ru_fwd_vld[FWD_D_INIT_0+:FWD_D_NB_0_W]),
        .twd_phi_ru_fwd_rdy      (twd_phi_ru_fwd_rdy[FWD_D_INIT_0+:FWD_D_NB_0_W]),

        .bsk                     (/*UNUSED*/),
        .bsk_vld                 (/*UNUSED*/),
        .bsk_rdy                 (/*UNUSED*/),

        .ntt_error               (ntt_error_fwd[0])
      );

  // ------------------------------------------------------------------------------------------- --
  // Twiddles FWD RS
  // ------------------------------------------------------------------------------------------- --
      for (genvar gen_d=0; gen_d<FWD_D_NB_0; gen_d=gen_d+1) begin : gen_twd_phru_fwd_rs_d_loop
        twiddle_phi_ru_manager
        #(
          .FILE_TWD_PREFIX($sformatf("%s_C%0d_D%0d_fwd",TWD_PHRU_FILE_PREFIX, 0, FWD_D_INIT_0+gen_d)),
          .OP_W        (OP_W),
          .R           (R),
          .PSI         (PSI),
          .S           (S),
          .ROM_LATENCY (ROM_LATENCY),
          .S_INIT      (S-1-(FWD_D_INIT_0+gen_d)),
          .S_DEC       (0),
          .LPB_NB      (LPB_NB)
        )
        twiddle_phi_ru_manager_fwd_rs
        (
          .clk             (clk),
          .s_rst_n         (s_rst_n),

          .twd_phi_ru      (twd_phi_ru_fwd[FWD_D_INIT_0+gen_d]),
          .twd_phi_ru_vld  (twd_phi_ru_fwd_vld[FWD_D_INIT_0+gen_d]),
          .twd_phi_ru_rdy  (twd_phi_ru_fwd_rdy[FWD_D_INIT_0+gen_d]),

          .batch_cmd       (batch_cmd),
          .batch_cmd_avail (batch_cmd_avail),

          .error           (twd_phru_error_fwd_l[FWD_D_INIT_0+gen_d])
        );
      end // gen_twd_phru_fwd_rs_d_loop
    end // gen_fwd_rs
    else begin : gen_no_fwd_rs
      assign ntt_error_fwd[0] = '0;
    end

  // ------------------------------------------------------------------------------------------- --
  // FWD LS
  // ------------------------------------------------------------------------------------------- --
    if (USE_FWD_LS) begin : gen_fwd_ls

      assign in_clbu_fwd_data[1]       = USE_FWD_RS ? out_ntw_fwd_data           : prev_data;
      assign in_clbu_fwd_data_avail[1] = USE_FWD_RS ? out_ntw_fwd_data_avail_tmp : prev_data_avail_tmp;
      assign in_clbu_fwd_sob[1]        = USE_FWD_RS ? out_ntw_fwd_sob            : prev_sob;
      assign in_clbu_fwd_eob[1]        = USE_FWD_RS ? out_ntw_fwd_eob            : prev_eob;
      assign in_clbu_fwd_sol[1]        = USE_FWD_RS ? out_ntw_fwd_sol            : prev_sol;
      assign in_clbu_fwd_eol[1]        = USE_FWD_RS ? out_ntw_fwd_eol            : prev_eol;
      assign in_clbu_fwd_sos[1]        = USE_FWD_RS ? out_ntw_fwd_sos            : prev_sos;
      assign in_clbu_fwd_eos[1]        = USE_FWD_RS ? out_ntw_fwd_eos            : prev_eos;
      assign in_clbu_fwd_pbs_id[1]     = USE_FWD_RS ? out_ntw_fwd_pbs_id         : prev_pbs_id;
      assign in_clbu_fwd_ctrl_avail[1] = USE_FWD_RS ? out_ntw_fwd_ctrl_avail     : prev_ctrl_avail;

      ntt_core_with_matrix_multiplication_unfold_pcg_middle_fwd
      #(
        .OP_W          (OP_W),
        .MOD_NTT       (MOD_NTT),
        .MOD_NTT_TYPE  (MOD_NTT_TYPE),
        .MOD_MULT_TYPE (MOD_MULT_TYPE),
        .REDUCT_TYPE   (REDUCT_TYPE),
        .MULT_TYPE     (MULT_TYPE),
        .PP_MOD_MULT_TYPE (PP_MOD_MULT_TYPE),
        .PP_MULT_TYPE     (PP_MULT_TYPE),
        .R             (R),
        .PSI           (PSI),
        .S             (S),
        .DELTA         (LS_DELTA),
        .BWD_PSI_DIV   (BWD_PSI_DIV),
        .S_INIT        (FWD_S_INIT_1),
        .D_INIT        (FWD_D_INIT_1),
        .D_NB          (FWD_D_NB_1),
        .IS_LS         (1),
        .USE_PP        (LOCAL_USE_PP),
        .RAM_LATENCY   (RAM_LATENCY)
      ) ntt_core_with_matrix_multiplication_unfold_pcg_middle_fwd_ls (
        .clk                     (clk),
        .s_rst_n                 (s_rst_n),

        .in_clbu_fwd_data        (in_clbu_fwd_data[1]),
        .in_clbu_fwd_data_avail  (in_clbu_fwd_data_avail[1]),
        .in_clbu_fwd_sob         (in_clbu_fwd_sob[1]),
        .in_clbu_fwd_eob         (in_clbu_fwd_eob[1]),
        .in_clbu_fwd_sol         (in_clbu_fwd_sol[1]),
        .in_clbu_fwd_eol         (in_clbu_fwd_eol[1]),
        .in_clbu_fwd_sos         (in_clbu_fwd_sos[1]),
        .in_clbu_fwd_eos         (in_clbu_fwd_eos[1]),
        .in_clbu_fwd_pbs_id      (in_clbu_fwd_pbs_id[1]),
        .in_clbu_fwd_ctrl_avail  (in_clbu_fwd_ctrl_avail[1]),

        .out_clbu_fwd_data       (out_clbu_fwd_data[1]      ),
        .out_clbu_fwd_data_avail (out_clbu_fwd_data_avail[1]),
        .out_clbu_fwd_sob        (out_clbu_fwd_sob[1]       ),
        .out_clbu_fwd_eob        (out_clbu_fwd_eob[1]       ),
        .out_clbu_fwd_sol        (out_clbu_fwd_sol[1]       ),
        .out_clbu_fwd_eol        (out_clbu_fwd_eol[1]       ),
        .out_clbu_fwd_sos        (out_clbu_fwd_sos[1]       ),
        .out_clbu_fwd_eos        (out_clbu_fwd_eos[1]       ),
        .out_clbu_fwd_pbs_id     (out_clbu_fwd_pbs_id[1]    ),
        .out_clbu_fwd_ctrl_avail (out_clbu_fwd_ctrl_avail[1]),

        .out_ntw_fwd_data        (/*UNUSED*/),
        .out_ntw_fwd_data_avail  (/*UNUSED*/),
        .out_ntw_fwd_sob         (/*UNUSED*/),
        .out_ntw_fwd_eob         (/*UNUSED*/),
        .out_ntw_fwd_sol         (/*UNUSED*/),
        .out_ntw_fwd_eol         (/*UNUSED*/),
        .out_ntw_fwd_sos         (/*UNUSED*/),
        .out_ntw_fwd_eos         (/*UNUSED*/),
        .out_ntw_fwd_pbs_id      (/*UNUSED*/),
        .out_ntw_fwd_ctrl_avail  (/*UNUSED*/),

        .in_clbu_bwd_data        (in_clbu_bwd_data[0]      ),
        .in_clbu_bwd_data_avail  (in_clbu_bwd_data_avail[0]),
        .in_clbu_bwd_sob         (in_clbu_bwd_sob[0]       ),
        .in_clbu_bwd_eob         (in_clbu_bwd_eob[0]       ),
        .in_clbu_bwd_sol         (in_clbu_bwd_sol[0]       ),
        .in_clbu_bwd_eol         (in_clbu_bwd_eol[0]       ),
        .in_clbu_bwd_sos         (in_clbu_bwd_sos[0]       ),
        .in_clbu_bwd_eos         (in_clbu_bwd_eos[0]       ),
        .in_clbu_bwd_pbs_id      (in_clbu_bwd_pbs_id[0]    ),
        .in_clbu_bwd_ctrl_avail  (in_clbu_bwd_ctrl_avail[0]),

        .twd_omg_ru_r_pow        (twd_omg_ru_r_pow),

        .twd_phi_ru_fwd          (twd_phi_ru_fwd[RS_DELTA+FWD_D_INIT_1+:FWD_D_NB_1_W]),
        .twd_phi_ru_fwd_vld      (twd_phi_ru_fwd_vld[RS_DELTA+FWD_D_INIT_1+:FWD_D_NB_1_W]),
        .twd_phi_ru_fwd_rdy      (twd_phi_ru_fwd_rdy[RS_DELTA+FWD_D_INIT_1+:FWD_D_NB_1_W]),

        .bsk                     (bsk    ),
        .bsk_vld                 (bsk_vld),
        .bsk_rdy                 (bsk_rdy),

        .ntt_error               (ntt_error_fwd[1])
      );

    // ------------------------------------------------------------------------------------------- --
    // Twiddles FWD LS
    // ------------------------------------------------------------------------------------------- --
      for (genvar gen_d=0; gen_d<FWD_D_NB_1; gen_d=gen_d+1) begin : gen_twd_phru_fwd_ls_d_loop
        twiddle_phi_ru_manager
        #(
          .FILE_TWD_PREFIX($sformatf("%s_C%0d_D%0d_fwd",TWD_PHRU_FILE_PREFIX, 1, FWD_D_INIT_1+gen_d)),
          .OP_W        (OP_W),
          .R           (R),
          .PSI         (PSI),
          .S           (S),
          .ROM_LATENCY (ROM_LATENCY),
          .S_INIT      (S-1-(RS_DELTA+FWD_D_INIT_1+gen_d)),
          .S_DEC       (0),
          .LPB_NB      (LPB_NB)
        )
        twiddle_phi_ru_manager_fwd_ls
        (
          .clk             (clk),
          .s_rst_n         (s_rst_n),

          .twd_phi_ru      (twd_phi_ru_fwd[RS_DELTA+FWD_D_INIT_1+gen_d]),
          .twd_phi_ru_vld  (twd_phi_ru_fwd_vld[RS_DELTA+FWD_D_INIT_1+gen_d]),
          .twd_phi_ru_rdy  (twd_phi_ru_fwd_rdy[RS_DELTA+FWD_D_INIT_1+gen_d]),

          .batch_cmd       (batch_cmd),
          .batch_cmd_avail (batch_cmd_avail),

          .error           (twd_phru_error_fwd_l[RS_DELTA+FWD_D_INIT_1+gen_d])
        );
      end // gen_twd_phru_fwd_ls_d_loop
    end // gen_fwd_ls
    else begin : gen_no_fwd_ls
      assign ntt_error_fwd[1] = '0;

      assign in_clbu_bwd_data[0]       = prev_data[BWD_PSI-1:0];
      assign in_clbu_bwd_data_avail[0] = prev_data_avail_tmp[BWD_PSI-1:0];
      assign in_clbu_bwd_sob[0]        = prev_sob;
      assign in_clbu_bwd_eob[0]        = prev_eob;
      assign in_clbu_bwd_sol[0]        = prev_sol;
      assign in_clbu_bwd_eol[0]        = prev_eol;
      assign in_clbu_bwd_sos[0]        = prev_sos;
      assign in_clbu_bwd_eos[0]        = prev_eos;
      assign in_clbu_bwd_pbs_id[0]     = prev_pbs_id;
      assign in_clbu_bwd_ctrl_avail[0] = prev_ctrl_avail;
    end

  // ------------------------------------------------------------------------------------------- --
  // BWD RS
  // ------------------------------------------------------------------------------------------- --
    if (USE_BWD_RS) begin : gen_bwd_rs

      ntt_core_with_matrix_multiplication_unfold_pcg_middle_bwd
      #(
        .OP_W          (OP_W),
        .MOD_NTT       (MOD_NTT),
        .MOD_NTT_TYPE  (MOD_NTT_TYPE),
        .MOD_MULT_TYPE (MOD_MULT_TYPE),
        .REDUCT_TYPE   (REDUCT_TYPE),
        .MULT_TYPE     (MULT_TYPE),
        .PP_MOD_MULT_TYPE (PP_MOD_MULT_TYPE),
        .PP_MULT_TYPE     (PP_MULT_TYPE),
        .R             (R),
        .PSI           (PSI),
        .S             (S),
        .DELTA         (RS_DELTA),
        .BWD_PSI_DIV   (BWD_PSI_DIV),
        .S_INIT        (BWD_S_INIT_0),
        .D_INIT        (BWD_D_INIT_0),
        .D_NB          (BWD_D_NB_0),
        .IS_LS         (0),
        .RAM_LATENCY   (RAM_LATENCY)
      ) ntt_core_with_matrix_multiplication_unfold_pcg_middle_bwd_rs (
        .clk                    (clk),
        .s_rst_n                (s_rst_n),

        .in_clbu_bwd_data       (in_clbu_bwd_data[0]),
        .in_clbu_bwd_data_avail (in_clbu_bwd_data_avail[0]),
        .in_clbu_bwd_sob        (in_clbu_bwd_sob[0]),
        .in_clbu_bwd_eob        (in_clbu_bwd_eob[0]),
        .in_clbu_bwd_sol        (in_clbu_bwd_sol[0]),
        .in_clbu_bwd_eol        (in_clbu_bwd_eol[0]),
        .in_clbu_bwd_sos        (in_clbu_bwd_sos[0]),
        .in_clbu_bwd_eos        (in_clbu_bwd_eos[0]),
        .in_clbu_bwd_pbs_id     (in_clbu_bwd_pbs_id[0]),
        .in_clbu_bwd_ctrl_avail (in_clbu_bwd_ctrl_avail[0]),

        .out_clbu_bwd_data      (out_clbu_bwd_data[0]),
        .out_clbu_bwd_data_avail(out_clbu_bwd_data_avail[0]),
        .out_clbu_bwd_sob       (out_clbu_bwd_sob[0]),
        .out_clbu_bwd_eob       (out_clbu_bwd_eob[0]),
        .out_clbu_bwd_sol       (out_clbu_bwd_sol[0]),
        .out_clbu_bwd_eol       (out_clbu_bwd_eol[0]),
        .out_clbu_bwd_sos       (out_clbu_bwd_sos[0]),
        .out_clbu_bwd_eos       (out_clbu_bwd_eos[0]),
        .out_clbu_bwd_pbs_id    (out_clbu_bwd_pbs_id[0]),
        .out_clbu_bwd_ctrl_avail(out_clbu_bwd_ctrl_avail[0]),

        .out_ntw_bwd_data       (out_ntw_bwd_data      ),
        .out_ntw_bwd_data_avail (out_ntw_bwd_data_avail),
        .out_ntw_bwd_sob        (out_ntw_bwd_sob       ),
        .out_ntw_bwd_eob        (out_ntw_bwd_eob       ),
        .out_ntw_bwd_sol        (out_ntw_bwd_sol       ),
        .out_ntw_bwd_eol        (out_ntw_bwd_eol       ),
        .out_ntw_bwd_sos        (out_ntw_bwd_sos       ),
        .out_ntw_bwd_eos        (out_ntw_bwd_eos       ),
        .out_ntw_bwd_pbs_id     (out_ntw_bwd_pbs_id    ),
        .out_ntw_bwd_ctrl_avail (out_ntw_bwd_ctrl_avail),

        .ntt_acc_data           (/*UNUSED*/),
        .ntt_acc_data_avail     (/*UNUSED*/),
        .ntt_acc_sob            (/*UNUSED*/),
        .ntt_acc_eob            (/*UNUSED*/),
        .ntt_acc_sol            (/*UNUSED*/),
        .ntt_acc_eol            (/*UNUSED*/),
        .ntt_acc_sog            (/*UNUSED*/),
        .ntt_acc_eog            (/*UNUSED*/),
        .ntt_acc_pbs_id         (/*UNUSED*/),
        .ntt_acc_ctrl_avail     (/*UNUSED*/),

        .twd_omg_ru_r_pow       (twd_omg_ru_r_pow),

        .twd_phi_ru_bwd         (twd_phi_ru_bwd[BWD_D_INIT_0+:BWD_D_NB_0_W]),
        .twd_phi_ru_bwd_vld     (twd_phi_ru_bwd_vld[BWD_D_INIT_0+:BWD_D_NB_0_W]),
        .twd_phi_ru_bwd_rdy     (twd_phi_ru_bwd_rdy[BWD_D_INIT_0+:BWD_D_NB_0_W]),

        .twd_intt_final         (/*UNUSED*/),
        .twd_intt_final_vld     (/*UNUSED*/),
        .twd_intt_final_rdy     (/*UNUSED*/),

        .ntt_error              (ntt_error_bwd[0])

      );

    // ------------------------------------------------------------------------------------------- --
    // Twiddles BWD RS
    // ------------------------------------------------------------------------------------------- --
      for (genvar gen_d=0; gen_d<BWD_D_NB_0; gen_d=gen_d+1) begin : gen_twd_phru_bwd_rs_d_loop
        twiddle_phi_ru_manager
        #(
          .FILE_TWD_PREFIX($sformatf("%s_C%0d_D%0d_bwd",TWD_PHRU_FILE_PREFIX, 0, BWD_D_INIT_0+gen_d)),
          .OP_W        (OP_W),
          .R           (R),
          .PSI         (BWD_PSI),
          .S           (S),
          .ROM_LATENCY (ROM_LATENCY),
          .S_INIT      (2*S-1-(BWD_D_INIT_0+gen_d)),
          .S_DEC       (0),
          .LPB_NB      (LPB_NB)
        )
        twiddle_phi_ru_manager_bwd_rs
        (
          .clk             (clk),
          .s_rst_n         (s_rst_n),

          .twd_phi_ru      (twd_phi_ru_bwd[BWD_D_INIT_0+gen_d]),
          .twd_phi_ru_vld  (twd_phi_ru_bwd_vld[BWD_D_INIT_0+gen_d]),
          .twd_phi_ru_rdy  (twd_phi_ru_bwd_rdy[BWD_D_INIT_0+gen_d]),

          .batch_cmd       (batch_cmd),
          .batch_cmd_avail (batch_cmd_avail),

          .error           (twd_phru_error_bwd_l[BWD_D_INIT_0+gen_d])
        );
      end
    end // gen_bwd_rs
    else begin : gen_no_bwd_rs
        assign ntt_error_bwd[0] = '0;
    end

    // ------------------------------------------------------------------------------------------- --
    // BWD LS
    // ------------------------------------------------------------------------------------------- --
    if (USE_BWD_LS) begin : gen_bwd_ls

      assign in_clbu_bwd_data[1]       = USE_BWD_RS ? out_ntw_bwd_data           : prev_data[BWD_PSI-1:0];
      assign in_clbu_bwd_data_avail[1] = USE_BWD_RS ? out_ntw_bwd_data_avail_tmp : prev_data_avail_tmp[BWD_PSI-1:0];
      assign in_clbu_bwd_sob[1]        = USE_BWD_RS ? out_ntw_bwd_sob            : prev_sob;
      assign in_clbu_bwd_eob[1]        = USE_BWD_RS ? out_ntw_bwd_eob            : prev_eob;
      assign in_clbu_bwd_sol[1]        = USE_BWD_RS ? out_ntw_bwd_sol            : prev_sol;
      assign in_clbu_bwd_eol[1]        = USE_BWD_RS ? out_ntw_bwd_eol            : prev_eol;
      assign in_clbu_bwd_sos[1]        = USE_BWD_RS ? out_ntw_bwd_sos            : prev_sos;
      assign in_clbu_bwd_eos[1]        = USE_BWD_RS ? out_ntw_bwd_eos            : prev_eos;
      assign in_clbu_bwd_pbs_id[1]     = USE_BWD_RS ? out_ntw_bwd_pbs_id         : prev_pbs_id;
      assign in_clbu_bwd_ctrl_avail[1] = USE_BWD_RS ? out_ntw_bwd_ctrl_avail     : prev_ctrl_avail;

      ntt_core_with_matrix_multiplication_unfold_pcg_middle_bwd
      #(
        .OP_W          (OP_W),
        .MOD_NTT       (MOD_NTT),
        .MOD_NTT_TYPE  (MOD_NTT_TYPE),
        .MOD_MULT_TYPE (MOD_MULT_TYPE),
        .REDUCT_TYPE   (REDUCT_TYPE),
        .MULT_TYPE     (MULT_TYPE),
        .PP_MOD_MULT_TYPE (PP_MOD_MULT_TYPE),
        .PP_MULT_TYPE     (PP_MULT_TYPE),
        .R             (R),
        .PSI           (PSI),
        .S             (S),
        .DELTA         (LS_DELTA),
        .BWD_PSI_DIV   (BWD_PSI_DIV),
        .S_INIT        (BWD_S_INIT_1),
        .D_INIT        (BWD_D_INIT_1),
        .D_NB          (BWD_D_NB_1),
        .IS_LS         (1),
        .RAM_LATENCY   (RAM_LATENCY)
      ) ntt_core_with_matrix_multiplication_unfold_pcg_middle_bwd_ls (
        .clk                    (clk),
        .s_rst_n                (s_rst_n),

        .in_clbu_bwd_data       (in_clbu_bwd_data[1]      ),
        .in_clbu_bwd_data_avail (in_clbu_bwd_data_avail[1]),
        .in_clbu_bwd_sob        (in_clbu_bwd_sob[1]       ),
        .in_clbu_bwd_eob        (in_clbu_bwd_eob[1]       ),
        .in_clbu_bwd_sol        (in_clbu_bwd_sol[1]       ),
        .in_clbu_bwd_eol        (in_clbu_bwd_eol[1]       ),
        .in_clbu_bwd_sos        (in_clbu_bwd_sos[1]       ),
        .in_clbu_bwd_eos        (in_clbu_bwd_eos[1]       ),
        .in_clbu_bwd_pbs_id     (in_clbu_bwd_pbs_id[1]    ),
        .in_clbu_bwd_ctrl_avail (in_clbu_bwd_ctrl_avail[1]),

        .out_clbu_bwd_data      (out_clbu_bwd_data[1]),
        .out_clbu_bwd_data_avail(out_clbu_bwd_data_avail[1]),
        .out_clbu_bwd_sob       (out_clbu_bwd_sob[1]),
        .out_clbu_bwd_eob       (out_clbu_bwd_eob[1]),
        .out_clbu_bwd_sol       (out_clbu_bwd_sol[1]),
        .out_clbu_bwd_eol       (out_clbu_bwd_eol[1]),
        .out_clbu_bwd_sos       (out_clbu_bwd_sos[1]),
        .out_clbu_bwd_eos       (out_clbu_bwd_eos[1]),
        .out_clbu_bwd_pbs_id    (out_clbu_bwd_pbs_id[1]),
        .out_clbu_bwd_ctrl_avail(out_clbu_bwd_ctrl_avail[1]),

        .out_ntw_bwd_data       (/*UNUSED*/),
        .out_ntw_bwd_data_avail (/*UNUSED*/),
        .out_ntw_bwd_sob        (/*UNUSED*/),
        .out_ntw_bwd_eob        (/*UNUSED*/),
        .out_ntw_bwd_sol        (/*UNUSED*/),
        .out_ntw_bwd_eol        (/*UNUSED*/),
        .out_ntw_bwd_sos        (/*UNUSED*/),
        .out_ntw_bwd_eos        (/*UNUSED*/),
        .out_ntw_bwd_pbs_id     (/*UNUSED*/),
        .out_ntw_bwd_ctrl_avail (/*UNUSED*/),

        .ntt_acc_data           (ntt_acc_data      ),
        .ntt_acc_data_avail     (ntt_acc_data_avail),
        .ntt_acc_sob            (ntt_acc_sob       ),
        .ntt_acc_eob            (ntt_acc_eob       ),
        .ntt_acc_sol            (ntt_acc_sol       ),
        .ntt_acc_eol            (ntt_acc_eol       ),
        .ntt_acc_sog            (ntt_acc_sog       ),
        .ntt_acc_eog            (ntt_acc_eog       ),
        .ntt_acc_pbs_id         (ntt_acc_pbs_id    ),
        .ntt_acc_ctrl_avail     (ntt_acc_ctrl_avail),

        .twd_omg_ru_r_pow       (twd_omg_ru_r_pow),

        .twd_phi_ru_bwd         (twd_phi_ru_bwd[RS_DELTA+BWD_D_INIT_1+:BWD_D_NB_1_W]),
        .twd_phi_ru_bwd_vld     (twd_phi_ru_bwd_vld[RS_DELTA+BWD_D_INIT_1+:BWD_D_NB_1_W]),
        .twd_phi_ru_bwd_rdy     (twd_phi_ru_bwd_rdy[RS_DELTA+BWD_D_INIT_1+:BWD_D_NB_1_W]),

        .twd_intt_final         (twd_intt_final    ),
        .twd_intt_final_vld     (twd_intt_final_vld),
        .twd_intt_final_rdy     (twd_intt_final_rdy),

        .ntt_error              (ntt_error_bwd[1])

      );

    // ------------------------------------------------------------------------------------------- --
    // Twiddles BWD LS
    // ------------------------------------------------------------------------------------------- --
      for (genvar gen_d=0; gen_d<BWD_D_NB_1; gen_d=gen_d+1) begin : gen_twd_phru_bwd_ls_d_loop
        twiddle_phi_ru_manager
        #(
          .FILE_TWD_PREFIX($sformatf("%s_C%0d_D%0d_bwd",TWD_PHRU_FILE_PREFIX, 1, BWD_D_INIT_1+gen_d)),
          .OP_W        (OP_W),
          .R           (R),
          .PSI         (BWD_PSI),
          .S           (S),
          .ROM_LATENCY (ROM_LATENCY),
          .S_INIT      (2*S-1-(RS_DELTA+BWD_D_INIT_1+gen_d)),
          .S_DEC       (0),
          .LPB_NB      (LPB_NB)
        )
        twiddle_phi_ru_manager_bwd_ls
        (
          .clk             (clk),
          .s_rst_n         (s_rst_n),

          .twd_phi_ru      (twd_phi_ru_bwd[RS_DELTA+BWD_D_INIT_1+gen_d]),
          .twd_phi_ru_vld  (twd_phi_ru_bwd_vld[RS_DELTA+BWD_D_INIT_1+gen_d]),
          .twd_phi_ru_rdy  (twd_phi_ru_bwd_rdy[RS_DELTA+BWD_D_INIT_1+gen_d]),

          .batch_cmd       (batch_cmd),
          .batch_cmd_avail (batch_cmd_avail),

          .error           (twd_phru_error_bwd_l[RS_DELTA+BWD_D_INIT_1+gen_d])
        );
      end

    //-------------------------------------------------------------------------------------------------
    // twiddle_intt_final_manager
    //-------------------------------------------------------------------------------------------------
      if ((BWD_D_INIT_1 + BWD_D_NB_1) == LS_DELTA) begin : gen_twd_ifnl
        twiddle_intt_final_manager
        #(
          .FILE_TWD_PREFIX(TWD_IFNL_FILE_PREFIX),
          .OP_W        (OP_W),
          .R           (R),
          .PSI         (BWD_PSI),
          .S           (S),
          .ROM_LATENCY (ROM_LATENCY)
        )
        twiddle_intt_final_manager
        (
          .clk                (clk),
          .s_rst_n            (s_rst_n),

          .twd_intt_final     (twd_intt_final),
          .twd_intt_final_vld (twd_intt_final_vld),
          .twd_intt_final_rdy (twd_intt_final_rdy)
        );
      end // gen_twd_ifnl
      else begin : gen_no_twd_ifnl
        assign twd_intt_final_vld = '0;
      end
    end // gen_bwd_ls
    else begin : gen_no_bwd_ls
      assign ntt_error_bwd[1] = '0;
    end

    // ------------------------------------------------------------------------------------------- --
    // Output
    // ------------------------------------------------------------------------------------------- --
    if (USE_BWD_LS) begin : gen_bwd_ls_out
      assign next_data       = (BWD_D_INIT_1 + BWD_D_NB_1) == LS_DELTA ? ntt_acc_data       : out_clbu_bwd_data[1];
      assign next_data_avail = (BWD_D_INIT_1 + BWD_D_NB_1) == LS_DELTA ? ntt_acc_data_avail : out_clbu_bwd_data_avail_ext[1];
      assign next_sob        = (BWD_D_INIT_1 + BWD_D_NB_1) == LS_DELTA ? ntt_acc_sob        : out_clbu_bwd_sob[1];
      assign next_eob        = (BWD_D_INIT_1 + BWD_D_NB_1) == LS_DELTA ? ntt_acc_eob        : out_clbu_bwd_eob[1];
      assign next_sol        = (BWD_D_INIT_1 + BWD_D_NB_1) == LS_DELTA ? ntt_acc_sol        : out_clbu_bwd_sol[1];
      assign next_eol        = (BWD_D_INIT_1 + BWD_D_NB_1) == LS_DELTA ? ntt_acc_eol        : out_clbu_bwd_eol[1];
      assign next_sos        = (BWD_D_INIT_1 + BWD_D_NB_1) == LS_DELTA ? ntt_acc_sog        : out_clbu_bwd_sos[1];
      assign next_eos        = (BWD_D_INIT_1 + BWD_D_NB_1) == LS_DELTA ? ntt_acc_eog        : out_clbu_bwd_eos[1];
      assign next_pbs_id     = (BWD_D_INIT_1 + BWD_D_NB_1) == LS_DELTA ? ntt_acc_pbs_id     : out_clbu_bwd_pbs_id[1];
      assign next_ctrl_avail = (BWD_D_INIT_1 + BWD_D_NB_1) == LS_DELTA ? ntt_acc_ctrl_avail : out_clbu_bwd_ctrl_avail[1];
    end // gen_bwd_ls_out
    else if (USE_BWD_RS) begin : gen_bwd_rs_out
      assign next_data       = (BWD_D_INIT_0 + BWD_D_NB_0) == RS_DELTA ? out_ntw_bwd_data       : out_clbu_bwd_data[0];
      assign next_data_avail = (BWD_D_INIT_0 + BWD_D_NB_0) == RS_DELTA ? out_ntw_bwd_data_avail : out_clbu_bwd_data_avail_ext[0];
      assign next_sob        = (BWD_D_INIT_0 + BWD_D_NB_0) == RS_DELTA ? out_ntw_bwd_sob        : out_clbu_bwd_sob[0];
      assign next_eob        = (BWD_D_INIT_0 + BWD_D_NB_0) == RS_DELTA ? out_ntw_bwd_eob        : out_clbu_bwd_eob[0];
      assign next_sol        = (BWD_D_INIT_0 + BWD_D_NB_0) == RS_DELTA ? out_ntw_bwd_sol        : out_clbu_bwd_sol[0];
      assign next_eol        = (BWD_D_INIT_0 + BWD_D_NB_0) == RS_DELTA ? out_ntw_bwd_eol        : out_clbu_bwd_eol[0];
      assign next_sos        = (BWD_D_INIT_0 + BWD_D_NB_0) == RS_DELTA ? out_ntw_bwd_sos        : out_clbu_bwd_sos[0];
      assign next_eos        = (BWD_D_INIT_0 + BWD_D_NB_0) == RS_DELTA ? out_ntw_bwd_eos        : out_clbu_bwd_eos[0];
      assign next_pbs_id     = (BWD_D_INIT_0 + BWD_D_NB_0) == RS_DELTA ? out_ntw_bwd_pbs_id     : out_clbu_bwd_pbs_id[0];
      assign next_ctrl_avail = (BWD_D_INIT_0 + BWD_D_NB_0) == RS_DELTA ? out_ntw_bwd_ctrl_avail : out_clbu_bwd_ctrl_avail[0];
    end // gen_bwd_rs_out
    else if (USE_FWD_LS) begin : gen_fwd_ls_out
      assign next_data       = ((FWD_D_INIT_1 + FWD_D_NB_1) == LS_DELTA) && LOCAL_USE_PP ? in_clbu_bwd_data[0]          : out_clbu_fwd_data[1];
      assign next_data_avail = ((FWD_D_INIT_1 + FWD_D_NB_1) == LS_DELTA) && LOCAL_USE_PP ? in_clbu_bwd_data_avail_ext[0]: out_clbu_fwd_data_avail_ext[1];
      assign next_sob        = ((FWD_D_INIT_1 + FWD_D_NB_1) == LS_DELTA) && LOCAL_USE_PP ? in_clbu_bwd_sob[0]           : out_clbu_fwd_sob[1];
      assign next_eob        = ((FWD_D_INIT_1 + FWD_D_NB_1) == LS_DELTA) && LOCAL_USE_PP ? in_clbu_bwd_eob[0]           : out_clbu_fwd_eob[1];
      assign next_sol        = ((FWD_D_INIT_1 + FWD_D_NB_1) == LS_DELTA) && LOCAL_USE_PP ? in_clbu_bwd_sol[0]           : out_clbu_fwd_sol[1];
      assign next_eol        = ((FWD_D_INIT_1 + FWD_D_NB_1) == LS_DELTA) && LOCAL_USE_PP ? in_clbu_bwd_eol[0]           : out_clbu_fwd_eol[1];
      assign next_sos        = ((FWD_D_INIT_1 + FWD_D_NB_1) == LS_DELTA) && LOCAL_USE_PP ? in_clbu_bwd_sos[0]           : out_clbu_fwd_sos[1];
      assign next_eos        = ((FWD_D_INIT_1 + FWD_D_NB_1) == LS_DELTA) && LOCAL_USE_PP ? in_clbu_bwd_eos[0]           : out_clbu_fwd_eos[1];
      assign next_pbs_id     = ((FWD_D_INIT_1 + FWD_D_NB_1) == LS_DELTA) && LOCAL_USE_PP ? in_clbu_bwd_pbs_id[0]        : out_clbu_fwd_pbs_id[1];
      assign next_ctrl_avail = ((FWD_D_INIT_1 + FWD_D_NB_1) == LS_DELTA) && LOCAL_USE_PP ? in_clbu_bwd_ctrl_avail[0]    : out_clbu_fwd_ctrl_avail[1];
    end // gen_fwd_ls_out
    else begin : gen_fwd_rs_out
      assign next_data       = (FWD_D_INIT_0 + FWD_D_NB_0) == RS_DELTA ? out_ntw_fwd_data       : out_clbu_fwd_data[0];
      assign next_data_avail = (FWD_D_INIT_0 + FWD_D_NB_0) == RS_DELTA ? out_ntw_fwd_data_avail : out_clbu_fwd_data_avail_ext[0];
      assign next_sob        = (FWD_D_INIT_0 + FWD_D_NB_0) == RS_DELTA ? out_ntw_fwd_sob        : out_clbu_fwd_sob[0];
      assign next_eob        = (FWD_D_INIT_0 + FWD_D_NB_0) == RS_DELTA ? out_ntw_fwd_eob        : out_clbu_fwd_eob[0];
      assign next_sol        = (FWD_D_INIT_0 + FWD_D_NB_0) == RS_DELTA ? out_ntw_fwd_sol        : out_clbu_fwd_sol[0];
      assign next_eol        = (FWD_D_INIT_0 + FWD_D_NB_0) == RS_DELTA ? out_ntw_fwd_eol        : out_clbu_fwd_eol[0];
      assign next_sos        = (FWD_D_INIT_0 + FWD_D_NB_0) == RS_DELTA ? out_ntw_fwd_sos        : out_clbu_fwd_sos[0];
      assign next_eos        = (FWD_D_INIT_0 + FWD_D_NB_0) == RS_DELTA ? out_ntw_fwd_eos        : out_clbu_fwd_eos[0];
      assign next_pbs_id     = (FWD_D_INIT_0 + FWD_D_NB_0) == RS_DELTA ? out_ntw_fwd_pbs_id     : out_clbu_fwd_pbs_id[0];
      assign next_ctrl_avail = (FWD_D_INIT_0 + FWD_D_NB_0) == RS_DELTA ? out_ntw_fwd_ctrl_avail : out_clbu_fwd_ctrl_avail[0];
    end // gen_fwd_rs_out
  endgenerate

endmodule
