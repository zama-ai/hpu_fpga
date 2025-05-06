// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the network between the radix columns.
// This sub-module deals with the read part.
// ==============================================================================================

`include "ntt_core_gf64_ntw_macro_inc.sv"

module ntt_core_gf64_ntw_core_rd
  import pep_common_param_pkg::*;
  import param_tfhe_pkg::*;
  import ntt_core_common_param_pkg::*;
  import ntt_core_gf64_common_param_pkg::*;
#(
  parameter int    RDX_CUT_ID      = 0, // increasing numbering for FWD, decreasing for BWD
                                        // FWD : 1 means ngc
                                        // BWD : 0 means ngc
                                        // Column that precedes the network.
  parameter bit    BWD             = 1'b0,
  parameter bit    IN_PIPE         = 1'b1, // Recommended
  parameter int    OP_W            = 66,
  parameter int    TOKEN_W         = 2 // Store up to 2**TOKEN_W working block
)
(
  input  logic                             clk,        // clock
  input  logic                             s_rst_n,    // synchronous reset

  input  logic [PSI*R-1:0][OP_W-1:0]       in_data,
  input  logic [PSI*R-1:0]                 in_avail,
  input  logic                             in_sob,
  input  logic                             in_eob,
  input  logic                             in_sol,
  input  logic                             in_eol,
  input  logic                             in_sos,
  input  logic                             in_eos,
  input  logic [BPBS_ID_W-1:0]             in_pbs_id,

  output logic [PSI*R-1:0][OP_W-1:0]       out_data,
  output logic [PSI*R-1:0]                 out_avail,
  output logic                             out_sob,
  output logic                             out_eob,
  output logic                             out_sol,
  output logic                             out_eol,
  output logic                             out_sos,
  output logic                             out_eos,
  output logic [BPBS_ID_W-1:0]             out_pbs_id
);

// ============================================================================================== --
// localparam
// ============================================================================================== --
  `NTT_CORE_GF64_NTW_LOCALPARAM(RDX_CUT_ID,BWD,R,PSI)

  localparam int ROT_C       = C <= 32 ? C/2 :
                               C < 512 ? 16  : 32; // TODO TOREVIEW best split
  localparam int ROT_SUBW_NB = C / ROT_C;

  generate
    if (N_L <= C) begin : __UNSUPPORTED_N_L
      $fatal(1,"> ERROR: ntt_core_gf64_ntw_core should be used with N_L (%0d) greater than R*PSI (%0d).", N_L, C);
    end
    if (ROT_C < 2) begin : __UNSUPPORTED_C
      $fatal(1,"> ERROR: Support only C (%0d) > 2, for the ntt gf64 network rotation", C);
    end
    if (ROT_SUBW_NB > 32) begin : __WARNING_ROT_SIZE
      initial begin
        $display("> WARNING: NTT GF64 network rotation 2nd part is done with %0d sub-words, which may be not optimal.",ROT_SUBW_NB);
      end
    end
  endgenerate

  // =========================================================================================== --
  // type
  // =========================================================================================== --
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

  // =========================================================================================== --
  // Input pipe
  // =========================================================================================== --
  logic [C-1:0][OP_W-1:0] s0_data;
  ctrl_t                  s0_ctrl;
  logic [C-1:0]           s0_avail;

  generate
    if (IN_PIPE) begin : gen_in_pipe
      always_ff @(posedge clk)
        if (!s_rst_n) s0_avail <= '0;
        else          s0_avail <= in_avail;

      always_ff @(posedge clk) begin
        s0_data         <= in_data;
        s0_ctrl.sob     <= in_sob;
        s0_ctrl.eob     <= in_eob;
        s0_ctrl.sol     <= in_sol;
        s0_ctrl.eol     <= in_eol;
        s0_ctrl.sos     <= in_sos;
        s0_ctrl.eos     <= in_eos;
        s0_ctrl.pbs_id  <= in_pbs_id;
      end
    end else begin : gen_no_in_pipe
      assign s0_data         = in_data;
      assign s0_ctrl.sob     = in_sob;
      assign s0_ctrl.eob     = in_eob;
      assign s0_ctrl.sol     = in_sol;
      assign s0_ctrl.eol     = in_eol;
      assign s0_ctrl.sos     = in_sos;
      assign s0_ctrl.eos     = in_eos;
      assign s0_ctrl.pbs_id  = in_pbs_id;
      assign s0_avail        = in_avail;
    end
  endgenerate

  // =========================================================================================== --
  // s0
  // =========================================================================================== --
  // ------------------------------------------------------------------------------------------- --
  // Counters
  // ------------------------------------------------------------------------------------------- --
  // ------------------------------------------------------------------------------------------- --
  // Counters
  // ------------------------------------------------------------------------------------------- --
  // Keep track of :
  //   wb       : current working block
  //   iter     : current iteration inside the working block
  //   intl_idx : current level index

  logic [INTL_L_W-1:0]   s0_intl_idx;
  logic [WB_W-1:0]       s0_wb; // working block
  logic [ITER_W-1:0]     s0_iter;

  logic [INTL_L_W-1:0]   s0_intl_idxD;
  logic [WB_W-1:0]       s0_wbD; // working block
  logic [ITER_W-1:0]     s0_iterD;

  logic                  s0_last_intl_idx;
  logic                  s0_last_wb;
  logic                  s0_last_iter;

  assign s0_last_intl_idx = s0_ctrl.eol;
  assign s0_last_iter     = s0_iter == ITER_NB-1;
  assign s0_last_wb       = s0_wb == WB_NB-1;

  assign s0_intl_idxD     = s0_avail[0] ? s0_last_intl_idx ? '0 : s0_intl_idx + 1 : s0_intl_idx;
  assign s0_iterD         = (s0_avail[0] && s0_last_intl_idx) ? s0_last_iter ? '0 : s0_iter + 1 : s0_iter;
  assign s0_wbD           = (s0_avail[0] && s0_last_intl_idx && s0_last_iter) ? s0_last_wb ? '0 : s0_wb + 1 : s0_wb;

  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      s0_wb       <= '0;
      s0_iter     <= '0;
      s0_intl_idx <= '0;
    end else begin
      s0_wb       <= s0_wbD;
      s0_iter     <= s0_iterD;
      s0_intl_idx <= s0_intl_idxD;
    end
  end

  // ------------------------------------------------------------------------------------------- --
  // rotation factor
  // ------------------------------------------------------------------------------------------- --
  // rdx_1_id = (iter * coef) // rdx_1
  //
  // if (rdx_1 > coef):
  //     rot_factor = (rdx_1_id % (coef // cons_nb)) * cons_nb
  // else:
  //     rot_factor = (rdx_1_id % set_nb) * rdx_1 + ((rdx_1_id//set_nb)%(rdx_1//cons_nb))*cons_nb
  //
  logic [C_W-1:0]        s0_rot_factor;
  logic [L_NB_W-1:0]     s0_rdx_l_id;
  logic [ITER_W+C_Z-1:0] s0_rdx_l_id_tmp;

  assign s0_rdx_l_id_tmp = s0_iter << C_Z;
  assign s0_rdx_l_id     = s0_rdx_l_id_tmp >> R_L_Z;

  generate
    if (R_L > C) begin : gen_r_l_gt_c
      logic [C_Z-CONS_Z-1:0] s0_rot_factor_tmp;
      assign s0_rot_factor_tmp = s0_rdx_l_id[C_Z-CONS_Z-1:0];
      assign s0_rot_factor     = s0_rot_factor_tmp << CONS_Z;
    end
    else begin : gen_no_r_l_gt_c
      logic [SET_W-1:0]        s0_rot_factor_tmp0;
      logic [C_W-1:0]          s0_rot_factor_tmp1;
      logic [C_W-1:0]          s0_rot_factor_tmp2;
      logic [R_L_Z-CONS_Z-1:0] s0_rot_factor_tmp3;
      logic [C_W-1:0]          s0_rot_factor_tmp4;

      if (SET_NB == 1) begin : gen_set_nb_eq_1
        assign s0_rot_factor_tmp0 = 0;
      end
      else begin : gen_no_set_nb_eq_1
        assign s0_rot_factor_tmp0 = s0_rdx_l_id[SET_Z-1:0];
      end

      assign s0_rot_factor_tmp1 = s0_rot_factor_tmp0 << R_L_Z;

      assign s0_rot_factor_tmp2 = s0_rdx_l_id >> SET_Z;
      assign s0_rot_factor_tmp3 = s0_rot_factor_tmp2[R_L_Z-CONS_Z-1:0];
      assign s0_rot_factor_tmp4 = s0_rot_factor_tmp3 << CONS_Z;

      assign s0_rot_factor = s0_rot_factor_tmp1 + s0_rot_factor_tmp4;
    end
  endgenerate

  // =========================================================================================== --
  // Rotation instance
  // =========================================================================================== --
  logic [C-1:0][OP_W-1:0]       s2_rot_data;
  logic [C-1:0]                 s2_avail;
  ctrl_t                        s2_ctrl;

  ntt_core_gf64_ntw_rot
  #(
    .IN_PIPE         (1'b0),
    .OP_W            (OP_W),
    .C               (C),
    .ROT_C           (ROT_C),
    .DIR             (1'b1),
    .SIDE_W          (CTRL_W),
    .RST_SIDE        (2'b00)
  ) ntt_core_gf64_ntw_rot (
    .clk           (clk),
    .s_rst_n       (s_rst_n),

    .in_data       (s0_data),
    .in_avail      (s0_avail),
    .in_side       (s0_ctrl),
    .in_rot_factor (s0_rot_factor),

    .out_data      (s2_rot_data),
    .out_avail     (s2_avail),
    .out_side      (s2_ctrl),

    .penult_avail  (/*UNUSED*/),
    .penult_side   (/*UNUSED*/)
  );

  // =========================================================================================== --
  // Output
  // =========================================================================================== --
  assign out_data   = s2_rot_data;
  assign out_avail  = s2_avail;
  assign out_sob    = s2_ctrl.sob;
  assign out_eob    = s2_ctrl.eob;
  assign out_sol    = s2_ctrl.sol;
  assign out_eol    = s2_ctrl.eol;
  assign out_sos    = s2_ctrl.sos;
  assign out_eos    = s2_ctrl.eos;
  assign out_pbs_id = s2_ctrl.pbs_id;

endmodule
