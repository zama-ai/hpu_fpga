// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// NTT core gf64 computes the NTT and INTT in goldilocks 64 domain.
// This prime = 2**64-2**32+1 has many properties. In particular :
// 1. We use the following one to simplify all the twiddle multiplications :
//    It exists a 64th root of unity in GF64 which value is 8=2**3 : w_64 = 2**3, so
//    a power of 2.
// 2. This prime is a solinas2, with the following pattern : 2**W-2**W/2+1.
//    The modular reduction can be done efficiently, especially if we do partial
//    modular reduction (PMR). Which means that we do not reduce completely,
//    and the data path contains additional bits.
//
// This module also performs the external multiplication with the BSK.
//
// This version is the middle part of the NTT core gf64.
// ==============================================================================================

module ntt_core_gf64_middle
  import common_definition_pkg::*;
  import pep_common_param_pkg::*;
  import param_tfhe_pkg::*;
  import param_ntt_pkg::*;
  import ntt_core_common_param_pkg::*;
  import ntt_core_gf64_common_param_pkg::*;
#(
  parameter  int               S_INIT           = S-1,// First stage ID
                                                      // Reverse numbering.
                                                      // FWD part : S-1 -> 0
                                                      // BWD part : 2S-1 -> S
  parameter  int               S_NB             = 2*S, // Number of NTT stages.
  parameter  bit               USE_PP           = 1, // If this partition contains the entire FWD NTT,
                                                     // this parameter indicates if the PP is instantiated.
  parameter  arith_mult_type_e PHI_MULT_TYPE    = MULT_KARATSUBA, // PHI multiplier, when needed
  parameter  arith_mult_type_e PP_MULT_TYPE     = MULT_KARATSUBA, // Multiplier used in PP
  parameter  int               RAM_LATENCY      = 1,
  parameter  int               ROM_LATENCY      = 1,
  parameter  bit               IN_PIPE          = 1'b1,
  parameter  string            TWD_GF64_FILE_PREFIX  = $sformatf("memory_file/twiddle/NTT_CORE_ARCH_GF64/R%0d_PSI%0d/twd_phi",R,PSI),
  localparam int               ERROR_W          = 1    // pp
)
(
  input  logic                                                 clk,
  input  logic                                                 s_rst_n,

  // Data from previous ntt_core or input logic
  input  logic  [PSI-1:0][R-1:0][MOD_NTT_W+1:0]                prev_data,
  input  logic  [PSI-1:0][R-1:0]                               prev_avail,
  input  logic                                                 prev_sob,
  input  logic                                                 prev_eob,
  input  logic                                                 prev_sol,
  input  logic                                                 prev_eol,
  input  logic                                                 prev_sos,
  input  logic                                                 prev_eos,
  input  logic [BPBS_ID_W-1:0]                                 prev_pbs_id,

  // To next ntt_core or output logic
  output logic [PSI-1:0][R-1:0][MOD_NTT_W+1:0]                 next_data,
  output logic [PSI-1:0][R-1:0]                                next_avail,
  output logic                                                 next_sob,
  output logic                                                 next_eob,
  output logic                                                 next_sol,
  output logic                                                 next_eol,
  output logic                                                 next_sos,
  output logic                                                 next_eos,
  output logic [BPBS_ID_W-1:0]                                 next_pbs_id,

  // Matrix factors : BSK
  // Only used if the PP is in this part.
  input  logic  [PSI-1:0][R-1:0][GLWE_K_P1-1:0][MOD_NTT_W-1:0] bsk,
  input  logic  [PSI-1:0][R-1:0][GLWE_K_P1-1:0]                bsk_vld,
  output logic [PSI-1:0][R-1:0][GLWE_K_P1-1:0]                 bsk_rdy,

  // Error
  output logic [ERROR_W-1:0]                                   error
);

  // ============================================================================================ //
  // localparam
  // ============================================================================================ //
  localparam bit USE_FWD = S_INIT < S;
  localparam bit USE_BWD = (S_INIT >= S) | (USE_FWD & ((S_INIT+1-S_NB) < 0));

  localparam int FWD_S_NB = S_INIT+1 >= S_NB ? S_NB : (S_INIT+1);
  localparam int BWD_S_NB = USE_FWD ? S_NB - FWD_S_NB : S_NB;

  localparam int FWD_STG_OFS = S-1-S_INIT;
  localparam int BWD_STG_OFS = USE_FWD ? 0 : 2*S-1-S_INIT;

  // To avoid warning
  localparam [S:-1][31:0] NTT_STG_RDX_ID_EXT = {32'hxx,NTT_STG_RDX_ID,32'hxx};

  // ============================================================================================ //
  // type
  // ============================================================================================ //
  typedef struct packed {
    logic                 sob;
    logic                 eob;
    logic                 sol;
    logic                 eol;
    logic                 sos;
    logic                 eos;
    logic [BPBS_ID_W-1:0] pbs_id;
  } ctrl_t;

  localparam CTRL_W = $bits(ctrl_t);

  // ============================================================================================ //
  // Signals
  // ============================================================================================ //
  ctrl_t                                prev_ctrl;
  ctrl_t                                next_ctrl;

  logic [PSI-1:0][R-1:0][MOD_NTT_W+1:0] fwd_out_data;
  ctrl_t                                fwd_out_ctrl;
  logic [PSI-1:0][R-1:0]                fwd_out_avail;

  logic [PSI-1:0][R-1:0][MOD_NTT_W+1:0] bwd_out_data;
  ctrl_t                                bwd_out_ctrl;
  logic [PSI-1:0][R-1:0]                bwd_out_avail;

  logic [PSI-1:0][R-1:0][MOD_NTT_W+1:0] pp_out_data;
  ctrl_t                                pp_out_ctrl;
  logic [PSI-1:0][R-1:0]                pp_out_avail;

  logic                                 pp_error;

  // ============================================================================================ //
  // Rename
  // ============================================================================================ //
  assign prev_ctrl.sob    = prev_sob;
  assign prev_ctrl.eob    = prev_eob;
  assign prev_ctrl.sol    = prev_sol;
  assign prev_ctrl.eol    = prev_eol;
  assign prev_ctrl.sos    = prev_sos;
  assign prev_ctrl.eos    = prev_eos;
  assign prev_ctrl.pbs_id = prev_pbs_id;

  assign next_sob    = next_ctrl.sob   ;
  assign next_eob    = next_ctrl.eob   ;
  assign next_sol    = next_ctrl.sol   ;
  assign next_eol    = next_ctrl.eol   ;
  assign next_sos    = next_ctrl.sos   ;
  assign next_eos    = next_ctrl.eos   ;
  assign next_pbs_id = next_ctrl.pbs_id;

  // ============================================================================================ //
  // Instance
  // ============================================================================================ //

  generate
  // -------------------------------------------------------------------------------------------- //
  // FWD NTT
  // -------------------------------------------------------------------------------------------- //
    if (USE_FWD) begin : gen_fwd_ntt
      logic  [FWD_S_NB:0][PSI-1:0][R-1:0][MOD_NTT_W+1:0] col_data;
      logic  [FWD_S_NB:0][PSI-1:0][R-1:0]                col_avail;
      ctrl_t [FWD_S_NB:0]                                col_ctrl;

      assign col_data[0]  = prev_data;
      assign col_ctrl[0]  = prev_ctrl;
      assign col_avail[0] = prev_avail;

      assign fwd_out_data  = col_data[FWD_S_NB];
      assign fwd_out_ctrl  = col_ctrl[FWD_S_NB];
      assign fwd_out_avail = col_avail[FWD_S_NB];

      for (genvar gen_i=0; gen_i<FWD_S_NB; gen_i=gen_i+1) begin : gen_fwd_loop
        localparam int NTT_STG_ID       = FWD_STG_OFS + gen_i;
        localparam int RDX_CUT_ID       = NTT_RDX_CUT_ID_LIST[NTT_STG_ID]; // Rdx column ID
        localparam int CUR_NTT_STG_RDX_POS  = NTT_STG_RDX_ID[NTT_STG_ID]-1; // Since NTT_STG_RDX_ID gives the radix size in log
        localparam int NEXT_NTT_STG_RDX_POS = NTT_STG_RDX_ID_EXT[NTT_STG_ID+1]-1;
        localparam bit IS_RDX_FIRST_COL = (NTT_STG_ID != 0) & (CUR_NTT_STG_RDX_POS == 0);
        localparam bit IS_RDX_LAST_COL  = (NTT_STG_ID != S-1) & (NEXT_NTT_STG_RDX_POS == 0);
        localparam bit USE_IN_PIPE      = (gen_i==0) & IN_PIPE;

        logic [PSI-1:0][R-1:0][MOD_NTT_W+1:0] phi_out_data;
        ctrl_t                                phi_out_ctrl;
        logic [PSI-1:0][R-1:0]                phi_out_avail;

        logic [PSI-1:0][R-1:0][MOD_NTT_W+1:0] rdx_out_data;
        ctrl_t                                rdx_out_ctrl;
        logic [PSI-1:0][R-1:0]                rdx_out_avail;

        if (IS_RDX_FIRST_COL) begin : gen_phi
          ntt_core_gf64_phi
          #(
            .RDX_CUT_ID      (RDX_CUT_ID),
            .BWD             (1'b0), // FWD
            .IN_PIPE         (USE_IN_PIPE),
            .ROM_LATENCY     (ROM_LATENCY),
            .LVL_NB          (INTL_L),
            .TWD_GF64_FILE_PREFIX (TWD_GF64_FILE_PREFIX),
            .MULT_TYPE       (PHI_MULT_TYPE),
            .SIDE_W          (CTRL_W),
            .RST_SIDE        (2'b00)
          ) ntt_core_gf64_phi (
            .clk       (clk),
            .s_rst_n   (s_rst_n),

            .in_data   (col_data[gen_i]),
            .out_data  (phi_out_data),

            .in_avail  (col_avail[gen_i]),
            .out_avail (phi_out_avail),
            .in_side   (col_ctrl[gen_i]),
            .out_side  (phi_out_ctrl)
          );
        end
        else begin : gen_no_phi
          assign phi_out_data  = col_data[gen_i];
          assign phi_out_ctrl  = col_ctrl[gen_i];
          assign phi_out_avail = col_avail[gen_i];
        end

        ntt_core_gf64_bu_stage_column_fwd
        #(
          .NTT_STG_ID (NTT_STG_ID),
          .IN_PIPE    (USE_IN_PIPE & !IS_RDX_FIRST_COL),
          .SIDE_W     (CTRL_W),
          .RST_SIDE   (2'b00)
        ) ntt_core_gf64_bu_stage_column_fwd (
          .clk       (clk),
          .s_rst_n   (s_rst_n),

          .in_data   (phi_out_data),
          .out_data  (rdx_out_data),
          .in_avail  (phi_out_avail),
          .out_avail (rdx_out_avail),
          .in_side   (phi_out_ctrl),
          .out_side  (rdx_out_ctrl)
        );

        if (IS_RDX_LAST_COL) begin : gen_ntw
          ntt_core_gf64_network
          #(
            .RDX_CUT_ID      (RDX_CUT_ID),
            .BWD             (1'b0), // FWD
            .OP_W            (MOD_NTT_W+2),
            .IN_PIPE         (1'b0),
            .RAM_LATENCY     (RAM_LATENCY)
          ) ntt_core_gf64_network (
            .clk        (clk),
            .s_rst_n    (s_rst_n),

            .in_data    (rdx_out_data),
            .in_avail   (rdx_out_avail),
            .in_sob     (rdx_out_ctrl.sob),
            .in_eob     (rdx_out_ctrl.eob),
            .in_sol     (rdx_out_ctrl.sol),
            .in_eol     (rdx_out_ctrl.eol),
            .in_sos     (rdx_out_ctrl.sos),
            .in_eos     (rdx_out_ctrl.eos),
            .in_pbs_id  (rdx_out_ctrl.pbs_id),

            .out_data   (col_data[gen_i+1]),
            .out_avail  (col_avail[gen_i+1]),
            .out_sob    (col_ctrl[gen_i+1].sob),
            .out_eob    (col_ctrl[gen_i+1].eob),
            .out_sol    (col_ctrl[gen_i+1].sol),
            .out_eol    (col_ctrl[gen_i+1].eol),
            .out_sos    (col_ctrl[gen_i+1].sos),
            .out_eos    (col_ctrl[gen_i+1].eos),
            .out_pbs_id (col_ctrl[gen_i+1].pbs_id)
          );
        end
        else begin : gen_no_ntw
          assign col_data[gen_i+1]  = rdx_out_data;
          assign col_ctrl[gen_i+1]  = rdx_out_ctrl;
          assign col_avail[gen_i+1] = rdx_out_avail;
        end
      end // gen_fwd_loop
    end // gen_fwd_ntt
    else begin : gen_no_fwd_ntt
      assign fwd_out_data  = prev_data;
      assign fwd_out_ctrl  = prev_ctrl;
      assign fwd_out_avail = prev_avail;
    end

  // -------------------------------------------------------------------------------------------- //
  // PP
  // -------------------------------------------------------------------------------------------- //
    if (USE_PP) begin : gen_pp
      ntt_core_gf64_post_process
      #(
        .MULT_TYPE (PP_MULT_TYPE),
        .IN_PIPE   (!USE_FWD)
      ) ntt_core_gf64_post_process (
        .clk        (clk),
        .s_rst_n    (s_rst_n),

        .in_data    (fwd_out_data),
        .in_avail   (fwd_out_avail),
        .in_sob     (fwd_out_ctrl.sob),
        .in_eob     (fwd_out_ctrl.eob),
        .in_sol     (fwd_out_ctrl.sol),
        .in_eol     (fwd_out_ctrl.eol),
        .in_sos     (fwd_out_ctrl.sos),
        .in_eos     (fwd_out_ctrl.eos),
        .in_pbs_id  (fwd_out_ctrl.pbs_id),

        .out_data   (pp_out_data),
        .out_avail  (pp_out_avail),
        .out_sob    (pp_out_ctrl.sob),
        .out_eob    (pp_out_ctrl.eob),
        .out_sol    (pp_out_ctrl.sol),
        .out_eol    (pp_out_ctrl.eol),
        .out_sos    (pp_out_ctrl.sos),
        .out_eos    (pp_out_ctrl.eos),
        .out_pbs_id (pp_out_ctrl.pbs_id),

        .bsk        (bsk),
        .bsk_vld    (bsk_vld),
        .bsk_rdy    (bsk_rdy),

        .error      (pp_error)
      );

    end
    else begin : gen_no_pp
      assign pp_out_data  = fwd_out_data;
      assign pp_out_ctrl  = fwd_out_ctrl;
      assign pp_out_avail = fwd_out_avail;

      assign bsk_rdy = '0; /*UNUSED*/
      assign pp_error = 1'b0;
    end

  // -------------------------------------------------------------------------------------------- //
  // BWD NTT
  // -------------------------------------------------------------------------------------------- //
    if (USE_BWD) begin : gen_bwd_ntt
      logic  [BWD_S_NB:0][PSI-1:0][R-1:0][MOD_NTT_W+1:0] col_data;
      logic  [BWD_S_NB:0][PSI-1:0][R-1:0]                col_avail;
      ctrl_t [BWD_S_NB:0]                                col_ctrl;

      assign col_data[0]  = pp_out_data;
      assign col_ctrl[0]  = pp_out_ctrl;
      assign col_avail[0] = pp_out_avail;

      assign bwd_out_data  = col_data[BWD_S_NB];
      assign bwd_out_ctrl  = col_ctrl[BWD_S_NB];
      assign bwd_out_avail = col_avail[BWD_S_NB];

      for (genvar gen_i=0; gen_i<BWD_S_NB; gen_i=gen_i+1) begin : gen_bwd_loop
        localparam int NTT_STG_ID_TMP   = BWD_STG_OFS + gen_i;
        localparam int NTT_STG_ID       = S-1-NTT_STG_ID_TMP; // inverse numbering
        localparam int RDX_CUT_ID       = NTT_RDX_CUT_ID_LIST[NTT_STG_ID]; // Rdx column ID
        localparam int CUR_NTT_STG_RDX_POS  = NTT_STG_RDX_ID[NTT_STG_ID]-1; // Since NTT_STG_RDX_ID gives the radix size in log
        localparam int PREV_NTT_STG_RDX_POS = NTT_STG_RDX_ID_EXT[NTT_STG_ID+1]-1;
        localparam bit IS_RDX_FIRST_COL = (NTT_STG_ID_TMP != 0) & (PREV_NTT_STG_RDX_POS == 0);
        localparam bit IS_RDX_LAST_COL  = (NTT_STG_ID_TMP != S-1) & (CUR_NTT_STG_RDX_POS == 0);
        localparam bit IS_LAST_COL      = NTT_STG_ID_TMP == S-1;
        localparam bit USE_IN_PIPE      = (gen_i==0) & !USE_FWD & !USE_PP & IN_PIPE;

        logic [PSI-1:0][R-1:0][MOD_NTT_W+1:0] phi_out_data;
        ctrl_t                                phi_out_ctrl;
        logic [PSI-1:0][R-1:0]                phi_out_avail;

        logic [PSI-1:0][R-1:0][MOD_NTT_W+1:0] rdx_out_data;
        ctrl_t                                rdx_out_ctrl;
        logic [PSI-1:0][R-1:0]                rdx_out_avail;

        logic [PSI-1:0][R-1:0][MOD_NTT_W+1:0] ntw_out_data;
        ctrl_t                                ntw_out_ctrl;
        logic [PSI-1:0][R-1:0]                ntw_out_avail;

        if (IS_RDX_FIRST_COL) begin : gen_phi
          ntt_core_gf64_phi
          #(
            .RDX_CUT_ID      (RDX_CUT_ID),
            .BWD             (1'b1), // BWD
            .IN_PIPE         (USE_IN_PIPE),
            .ROM_LATENCY     (ROM_LATENCY),
            .LVL_NB          (GLWE_K_P1),
            .TWD_GF64_FILE_PREFIX (TWD_GF64_FILE_PREFIX),
            .MULT_TYPE       (PHI_MULT_TYPE),
            .SIDE_W          (CTRL_W),
            .RST_SIDE        (2'b00)
          ) ntt_core_gf64_phi (
            .clk       (clk),
            .s_rst_n   (s_rst_n),

            .in_data   (col_data[gen_i]),
            .out_data  (phi_out_data),

            .in_avail  (col_avail[gen_i]),
            .out_avail (phi_out_avail),
            .in_side   (col_ctrl[gen_i]),
            .out_side  (phi_out_ctrl)
          );
        end
        else begin : gen_no_phi
          assign phi_out_data  = col_data[gen_i];
          assign phi_out_ctrl  = col_ctrl[gen_i];
          assign phi_out_avail = col_avail[gen_i];
        end

        ntt_core_gf64_bu_stage_column_bwd
        #(
          .NTT_STG_ID (NTT_STG_ID),
          .IN_PIPE    (USE_IN_PIPE & !IS_RDX_FIRST_COL),
          .SIDE_W     (CTRL_W),
          .RST_SIDE   (2'b00)
        ) ntt_core_gf64_bu_stage_column_bwd (
          .clk       (clk),
          .s_rst_n   (s_rst_n),

          .in_data   (phi_out_data),
          .out_data  (rdx_out_data),
          .in_avail  (phi_out_avail),
          .out_avail (rdx_out_avail),
          .in_side   (phi_out_ctrl),
          .out_side  (rdx_out_ctrl)
        );

        if (IS_RDX_LAST_COL) begin : gen_ntw
          ntt_core_gf64_network
          #(
            .RDX_CUT_ID      (RDX_CUT_ID),
            .BWD             (1'b1), // BWD
            .OP_W            (MOD_NTT_W+2),
            .IN_PIPE         (1'b0),
            .RAM_LATENCY     (RAM_LATENCY)
          ) ntt_core_gf64_network (
            .clk        (clk),
            .s_rst_n    (s_rst_n),

            .in_data    (rdx_out_data),
            .in_avail   (rdx_out_avail),
            .in_sob     (rdx_out_ctrl.sob),
            .in_eob     (rdx_out_ctrl.eob),
            .in_sol     (rdx_out_ctrl.sol),
            .in_eol     (rdx_out_ctrl.eol),
            .in_sos     (rdx_out_ctrl.sos),
            .in_eos     (rdx_out_ctrl.eos),
            .in_pbs_id  (rdx_out_ctrl.pbs_id),

            .out_data   (ntw_out_data),
            .out_avail  (ntw_out_avail),
            .out_sob    (ntw_out_ctrl.sob),
            .out_eob    (ntw_out_ctrl.eob),
            .out_sol    (ntw_out_ctrl.sol),
            .out_eol    (ntw_out_ctrl.eol),
            .out_sos    (ntw_out_ctrl.sos),
            .out_eos    (ntw_out_ctrl.eos),
            .out_pbs_id (ntw_out_ctrl.pbs_id)
          );
        end
        else begin : gen_no_ntw
          assign ntw_out_data  = rdx_out_data;
          assign ntw_out_ctrl  = rdx_out_ctrl;
          assign ntw_out_avail = rdx_out_avail;
        end

        if (IS_LAST_COL) begin : gen_reduc
          logic [PSI*R-1:0][MOD_NTT_W-1:0] reduct_out_data;

          for (genvar gen_p=0; gen_p<PSI; gen_p=gen_p+1)
            for (genvar gen_r=0; gen_r<R; gen_r=gen_r+1)
              assign col_data[gen_i+1][gen_p][gen_r] = reduct_out_data[gen_p*R+gen_r]; // Extend with 0s

          ntt_core_gf64_reduction
          #(
            .C         (PSI*R),
            .MOD_NTT_W (MOD_NTT_W),
            .OP_W      (MOD_NTT_W+2),
            .IN_PIPE   (1'b0),
            .SIDE_W    (CTRL_W),
            .RST_SIDE  (2'b00)
          ) ntt_core_gf64_reduction (
              .clk       (clk),
              .s_rst_n   (s_rst_n),

              .in_data   (ntw_out_data),
              .out_data  (reduct_out_data),

              .in_avail  (ntw_out_avail),
              .out_avail (col_avail[gen_i+1]),
              .in_side   (ntw_out_ctrl),
              .out_side  (col_ctrl[gen_i+1])
          );
        end
        else begin : gen_no_reduc
          assign col_data[gen_i+1]  = ntw_out_data;
          assign col_ctrl[gen_i+1]  = ntw_out_ctrl;
          assign col_avail[gen_i+1] = ntw_out_avail;
        end
      end // gen_bwd_loop
    end // gen_bwd_ntt
    else begin : gen_no_bwd_ntt
      assign bwd_out_data  = pp_out_data;
      assign bwd_out_ctrl  = pp_out_ctrl;
      assign bwd_out_avail = pp_out_avail;
    end

  endgenerate

  // ============================================================================================ //
  // Output
  // ============================================================================================ //
  assign next_data  = bwd_out_data;
  assign next_avail = bwd_out_avail;
  assign next_ctrl  = bwd_out_ctrl;

  // ============================================================================================ //
  // Error
  // ============================================================================================ //
  assign error = pp_error;

endmodule
