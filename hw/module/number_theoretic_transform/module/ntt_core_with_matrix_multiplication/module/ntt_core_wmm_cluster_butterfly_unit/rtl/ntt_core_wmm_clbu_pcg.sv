// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module performs DELTA stages iteration of NTT with a radix R.
// Input data is in reverse(R,S) order.
// Use constant geometry connection.
// ==============================================================================================

`include "ntt_core_common_macro_inc.sv"

module ntt_core_wmm_clbu_pcg
  import param_tfhe_pkg::*;
  import pep_common_param_pkg::*;
  import common_definition_pkg::*;
#(

  parameter  int        OP_W          = 32,
  parameter  [OP_W-1:0] MOD_NTT       = 2**32-2**17-2**13+1,
  parameter  int        R             = 2, // Butterfly Radix
  parameter  int        PSI           = 32, // Number of butterflies
  parameter  int        S             = 11,
  parameter  int        D_INIT        = 0,
  parameter  int        RS_DELTA      = 6,
  parameter  int        LS_DELTA      = 6,
  parameter  bit        RS_OUT_WITH_NTW = 1'b1,
  parameter  bit        LS_OUT_WITH_NTW = 1'b1,
  parameter  int        LPB_NB        = 1,
  parameter  mod_reduct_type_e     REDUCT_TYPE   = MOD_REDUCT_SOLINAS3,
  parameter  mod_mult_type_e       MOD_MULT_TYPE = MOD_MULT_SOLINAS3,
  parameter  arith_mult_type_e     MULT_TYPE     = MULT_KARATSUBA,
  localparam int        DELTA         = RS_DELTA > LS_DELTA ? RS_DELTA : LS_DELTA

) (
  input logic                                        clk,
  input logic                                        s_rst_n,
  // Input data : in reverse(R,S) order
  input  logic [PSI-1:0][R-1:0][OP_W-1:0]            in_a,
  input  logic [PSI-1:0]                             in_ntt_bwd, // For omg_ru selection
  input  logic                                       in_sob,
  input  logic                                       in_eob,
  input  logic                                       in_sol,
  input  logic                                       in_eol,
  input  logic                                       in_sos,
  input  logic                                       in_eos,
  input  logic [BPBS_ID_W-1:0]                       in_pbs_id,
  input  logic [PSI-1:0]                             in_avail,
  // Output data : in pseudo-reverse(R,S,DELTA) order
  output logic [PSI-1:0][R-1:0][OP_W-1:0]            rs_z,
  output logic                                       rs_sob,
  output logic                                       rs_eob,
  output logic                                       rs_sol,
  output logic                                       rs_eol,
  output logic                                       rs_sos,
  output logic                                       rs_eos,
  output logic [BPBS_ID_W-1:0]                       rs_pbs_id,
  output logic                                       rs_ntt_bwd,
  output logic [PSI-1:0]                             rs_avail,

  // Output when lbp_cnt = LPB_NB-1
  output logic [PSI-1:0][R-1:0][OP_W-1:0]            ls_z,
  output logic                                       ls_sob,
  output logic                                       ls_eob,
  output logic                                       ls_sol,
  output logic                                       ls_eol,
  output logic                                       ls_sos,
  output logic                                       ls_eos,
  output logic [BPBS_ID_W-1:0]                       ls_pbs_id,
  output logic                                       ls_ntt_bwd,
  output logic [PSI-1:0]                             ls_avail,

  // Twiddles
  input  logic [1:0][R/2-1:0][OP_W-1:0]              twd_omg_ru_r_pow, // [0] NTT, [1] INTT
  // [i] = omg_ru_r ** i
  input  logic [DELTA-1:D_INIT][PSI-1:0][OP_W-1:0]   twd_phi_ru,
  input  logic [DELTA-1:D_INIT][PSI-1:0]             twd_phi_ru_vld,
  output logic [DELTA-1:D_INIT][PSI-1:0]             twd_phi_ru_rdy,
  // Error
  output logic                                       error_twd_phi

);
  // =========================================================================================== --
  // localparam
  // =========================================================================================== --
  `NTT_CORE_LOCALPARAM(R,S,PSI)

  // Note that [DELTA-1] is not used - here to avoid warnings
  // For each step, get the group size
  localparam [DELTA-1:0][31:0] GROUP_SIZE = get_group_size();
  // For each step, get the number of groups that entirely fits inside the butterfly
  localparam [DELTA-1:0][31:0] FIT_GROUP_NB = get_fit_group_nb();
  // For each step, get the number of groups
  localparam [DELTA-1:0][31:0] GROUP_NB = get_group_nb();

  localparam int RS = 0;
  localparam int LS = 1;

  localparam int D_0          = D_INIT > 0 ? D_INIT-1 : D_INIT;
  localparam int LS_DELTA_IDX = LS_DELTA - 1;
  localparam int RS_DELTA_IDX = RS_DELTA - 1;

  localparam [1:0][31:0] RLS_TO_DELTA         = {LS_DELTA,RS_DELTA};
  localparam [1:0][31:0] RLS_TO_DELTA_IDX     = {LS_DELTA_IDX,RS_DELTA_IDX};
  localparam bit [1:0]   RLS_TO_OUT_WITH_NTW  = {LS_OUT_WITH_NTW,RS_OUT_WITH_NTW};

  localparam int LPB_W = $clog2(LPB_NB) == 0 ? 1 : $clog2(LPB_NB);

  localparam bit BFLY_IN_PIPE  = 1'b1;
  localparam bit PIPE_IN_PIPE  = 1'b1;
  localparam bit PIPE_OUT_PIPE = 1'b0; // Set to 0 : mandatory

  localparam bit SKIP_FIRST_CLBU = D_INIT > 0;

  // =========================================================================================== --
  // functions
  // =========================================================================================== --
  function [DELTA-1:0][31:0] get_group_size ();
    var [DELTA-1:0][31:0] gr_size;
    for (int i=0; i<DELTA; i=i+1)
      gr_size[i] = R ** (i+2);
    return gr_size;
  endfunction

  function [DELTA-1:0][31:0] get_fit_group_nb ();
    var [DELTA-1:0][31:0] gr_nb;
    for (int i=0; i<DELTA; i=i+1)
      gr_nb[i] = (PSI*R)/GROUP_SIZE[i];
    return gr_nb;
  endfunction

  function [DELTA-1:0][31:0] get_group_nb ();
    var [DELTA-1:0][31:0] gr_nb;
    for (int i=0; i<DELTA; i=i+1)
      gr_nb[i] = N/GROUP_SIZE[i];
    return gr_nb;
  endfunction

  // ============================================================================================== --
  // Type
  // ============================================================================================== --
  typedef struct packed {
    logic                last_lpb;
    logic                sob;
    logic                eob;
    logic                sol;
    logic                eol;
    logic                sos;
    logic                eos;
    logic                ntt_bwd;
    logic [BPBS_ID_W-1:0] pbs_id;
  } control_t;

  localparam int CONTROL_W = $bits(control_t);

  // =========================================================================================== --
  // Loop counter
  // =========================================================================================== --
  logic [LPB_W-1:0] in_lpb_cnt;
  logic [LPB_W-1:0] in_lpb_cntD;
  logic             in_last_lpb;

  always_ff @(posedge clk)
    if (!s_rst_n) in_lpb_cnt <= '0;
    else          in_lpb_cnt <= in_lpb_cntD;

  assign in_last_lpb = in_lpb_cnt == (LPB_NB-1);
  assign in_lpb_cntD = (in_avail[0] && in_eob) ? in_last_lpb ? '0 : in_lpb_cnt + 1 : in_lpb_cnt;

  // =========================================================================================== --
  // control
  // =========================================================================================== --
  control_t in_ctrl;

  assign in_ctrl.last_lpb= in_last_lpb;
  assign in_ctrl.sob     = in_sob    ;
  assign in_ctrl.eob     = in_eob    ;
  assign in_ctrl.sol     = in_sol    ;
  assign in_ctrl.eol     = in_eol    ;
  assign in_ctrl.sos     = in_sos    ;
  assign in_ctrl.eos     = in_eos    ;
  assign in_ctrl.ntt_bwd = in_ntt_bwd;
  assign in_ctrl.pbs_id  = in_pbs_id ;

  // =========================================================================================== --
  // Butterfly instance
  // =========================================================================================== --
  // Addition location to have an additional network at the end.
  logic [DELTA:0][PSI-1:0][R-1:0][OP_W-1:0]   rdx_in_data;
  logic [DELTA:0][PSI-1:0]                    rdx_in_avail;
  logic [DELTA:0][PSI-1:0]                    rdx_in_ntt_bwd;
  control_t                                   rdx_in_ctrl[DELTA:0][PSI-1:0];
  logic [DELTA-1:0][PSI-1:0][R-1:0][OP_W-1:0] rdx_out_data;
  logic [DELTA-1:0][PSI-1:0]                  rdx_out_avail;
  logic [DELTA-1:0][PSI-1:0]                  rdx_out_ntt_bwd;
  control_t                                   rdx_out_ctrl[DELTA-1:0][PSI-1:0];

  generate
    for (genvar gen_d=D_0; gen_d<DELTA; gen_d=gen_d+1) begin : gen_inst_d_loop
      logic [PSI-1:0] rdx_out_ntt_bwd_l;
      logic [PSI-1:0] twd_phi_ru_rdy_l;
      for (genvar gen_p = 0; gen_p < PSI; gen_p = gen_p + 1) begin : gen_inst_p_loop

        if (SKIP_FIRST_CLBU && gen_d==D_0) begin : gen_skip_first_clbu
          assign rdx_out_data[gen_d][gen_p]  = rdx_in_data[gen_d][gen_p];
          assign rdx_out_avail[gen_d][gen_p] = rdx_in_avail[gen_d][gen_p];
          assign rdx_out_ctrl[gen_d][gen_p]  = rdx_in_ctrl[gen_d][gen_p];
        end
        else begin : gen_no_skip_first_clbu
          // Note that unused signals are simplified during the synthesis
          ntt_radix_cooley_tukey #(
            .R            (R),
            .REDUCT_TYPE  (REDUCT_TYPE),
            .MOD_MULT_TYPE(MOD_MULT_TYPE),
            .MULT_TYPE    (MULT_TYPE),
            .OP_W         (OP_W),
            .MOD_M        (MOD_NTT),
            .OMG_SEL_NB   (2), // Choose between NTT and INTT factors
            .OUT_NATURAL_ORDER(1), // Use natural output order in this arch
            .IN_PIPE      (BFLY_IN_PIPE),
            .SIDE_W       (CONTROL_W),
            .RST_SIDE     (2'b00)
          ) ntt_radix_cooley_tukey (
            .clk      (clk),
            .s_rst_n  (s_rst_n),
            .xt_a     (rdx_in_data[gen_d][gen_p]),
            .xf_a     (rdx_out_data[gen_d][gen_p]),
            .phi_a    (twd_phi_ru[gen_d][gen_p]),
            .omg_a    (twd_omg_ru_r_pow),
            .omg_sel  (rdx_in_ntt_bwd[gen_d][gen_p]),
            .in_avail (rdx_in_avail[gen_d][gen_p]),
            .out_avail(rdx_out_avail[gen_d][gen_p]),
            .in_side  (rdx_in_ctrl[gen_d][gen_p]),
            .out_side (rdx_out_ctrl[gen_d][gen_p])
          );

        end
      end

      always_comb
        for (int p=0; p<PSI; p=p+1)
          twd_phi_ru_rdy_l[p]  = rdx_in_avail[gen_d][p] & rdx_in_ctrl[gen_d][p].eol;

      if (!(SKIP_FIRST_CLBU && gen_d==D_0)) begin : gen_skip_first_clbu_fix
        assign twd_phi_ru_rdy[gen_d] = twd_phi_ru_rdy_l;
      end

      always_comb
        for (int p=0; p<PSI; p=p+1)
          rdx_out_ntt_bwd_l[p] = rdx_out_ctrl[gen_d][p].ntt_bwd;

      assign rdx_out_ntt_bwd[gen_d] = rdx_out_ntt_bwd_l;
    end
  endgenerate

  assign rdx_in_data[D_0]    = in_a;
  assign rdx_in_ntt_bwd[D_0] = in_ntt_bwd;
  assign rdx_in_avail[D_0]   = in_avail;
  assign rdx_in_ctrl[D_0]    = '{PSI{in_ctrl}};

  // =========================================================================================== --
  // Network
  // =========================================================================================== --
  logic [DELTA-1:0][PSI-1:0][R-1:0]           send_to_next;
  logic [DELTA-1:0][PSI-1:0][R-1:0][OP_W-1:0] ntw_out_data;
  generate
    for (genvar gen_d=D_0; gen_d<DELTA; gen_d=gen_d+1) begin : gen_ntw_d_loop
      //--------------------
      // Entire group
      //--------------------
      if (FIT_GROUP_NB[gen_d] > 0) begin : gen_entire_group
        localparam int GR_PSI     = GROUP_SIZE[gen_d] / R;
        localparam int GR_PSI_POS = GR_PSI / R;

        // avail : direct connection
        logic [PSI-1:0][R-1:0] ntw_out_avail_l;

        assign rdx_in_avail[gen_d+1] = ntw_out_avail_l & send_to_next[gen_d];

        always_comb
          for (int p=0; p<PSI; p=p+1)
            ntw_out_avail_l[p] = {R{rdx_out_avail[gen_d][p]}};

        // Data : butterfly
        for (genvar gen_g=0; gen_g<FIT_GROUP_NB[gen_d]; gen_g=gen_g+1) begin : gen_g_loop
          logic[GR_PSI*R-1:0][OP_W-1:0]      gr_in_data;
          logic[GR_PSI-1:0][R-1:0][OP_W-1:0] gr_out_data;

          assign gr_in_data = rdx_out_data[gen_d][gen_g*GR_PSI+:GR_PSI];

          always_comb
            for (int p=0; p<GR_PSI; p=p+1)
              for (int r=0; r<R; r=r+1)
                gr_out_data[p][r] = gr_in_data[r*GR_PSI_POS*R+p];

          assign rdx_in_data[gen_d+1][gen_g*GR_PSI+:GR_PSI] = gr_out_data;
          assign ntw_out_data[gen_d][gen_g*GR_PSI+:GR_PSI] = gr_out_data;
        end // gen_g_loop

        assign rdx_in_ntt_bwd[gen_d+1]= rdx_out_ntt_bwd[gen_d];
        assign rdx_in_ctrl[gen_d+1]   = rdx_out_ctrl[gen_d];
      end
      //--------------------
      // Split group
      //--------------------
      else begin : gen_split_group
        localparam int POS_OCC     = GROUP_SIZE[gen_d] / (PSI*R*R); // number of cycles during which the same position is sent : is a power of 2
        localparam int POS_OCC_W   = $clog2(POS_OCC) > 0 ? $clog2(POS_OCC) : 1;
        localparam int GROUP_CNT_W = $clog2(GROUP_NB[gen_d]);

        logic[PSI*R-1:0][OP_W-1:0]       gr_in_data;
        logic[PSI-1:0][R-1:0][OP_W-1:0]  gr_out_data;

        logic [PSI-1:0][R-1:0]           pipe_in_avail;
        logic [PSI-1:0][R-1:0]           pipe_in_inc;
        logic [PSI-1:0][R-1:0]           pipe_in_eol;
        logic [PSI-1:0][R-1:0][OP_W-1:0] pipe_out_data;
        logic [PSI-1:0][R-1:0]           pipe_out_avail;
        control_t                        pipe_out_ctrl[PSI-1:0];
        logic [PSI-1:0]                  pipe_out_ntt_bwd;

        assign gr_in_data = rdx_out_data[gen_d];

        // Data : butterfly
        always_comb
          for (int p=0; p<PSI; p=p+1)
            for (int r=0; r<R; r=r+1)
              gr_out_data[p][r] = gr_in_data[r*PSI+p];

        assign ntw_out_data[gen_d] = gr_in_data;//gr_out_data;

        // Avail
        for (genvar gen_p=0; gen_p<PSI; gen_p=gen_p+1) begin : gen_p_loop
          logic [POS_OCC_W-1:0]   occ_cnt;
          logic [R-1:0]           r_cnt_1h;
          //logic [GROUP_CNT_W-1:0] gr_cnt;
          logic [POS_OCC_W-1:0]   occ_cntD;
          logic [R-1:0]           r_cnt_1hD;
          //logic [GROUP_CNT_W-1:0] gr_cntD;

          logic                 last_occ_cnt;
          //logic                 last_gr_cnt;
          logic                 last_r_cnt;
          logic [R-1:0]         r_avail;

          assign last_occ_cnt = occ_cnt == (POS_OCC-1);
          //assign last_gr_cnt  = gr_cnt  == (GROUP_NB[gen_d]-1);
          assign last_r_cnt   = r_cnt_1h[R-1];

          assign occ_cntD  = (rdx_out_avail[gen_d][gen_p] && rdx_out_ctrl[gen_d][gen_p].eol) ? last_occ_cnt ? '0 : occ_cnt + 1 : occ_cnt;
          assign r_cnt_1hD = (rdx_out_avail[gen_d][gen_p] && rdx_out_ctrl[gen_d][gen_p].eol && last_occ_cnt) ? {r_cnt_1h[R-2:0], r_cnt_1h[R-1]}: r_cnt_1h;
          //assign gr_cntD   = (rdx_out_avail[gen_d][gen_p] && rdx_out_ctrl[gen_d][gen_p].eol && last_occ_cnt && last_r_cnt) ? gr_cnt + 1 : gr_cnt;

          always_ff @(posedge clk)
            if (!s_rst_n) begin
              occ_cnt  <= '0;
              r_cnt_1h <= 1;
             // gr_cnt   <= '0;
            end
            else begin
              occ_cnt  <= occ_cntD;
              r_cnt_1h <= r_cnt_1hD;
             // gr_cnt   <= gr_cntD;
            end

          // TOREVIEW : for R!=2 - depending on PSI, there might be several positions available.
          assign r_avail = r_cnt_1h & {R{rdx_out_avail[gen_d][gen_p]}};

          assign pipe_in_avail[gen_p] = r_avail & send_to_next[gen_d];
          assign pipe_in_eol[gen_p]   = {R{rdx_out_ctrl[gen_d][gen_p].eol}};

          // Pipe - first coef
          ntt_core_wmm_clbu_pcg_pipe
          #(
            .OP_W     (OP_W),
            .R        (R),
            .STEP     ($clog2(POS_OCC)),
            .POS      (0),
            .LVL_NB   (INTL_L),
            .MIN_LVL_NB (GLWE_K_P1),
            .BPBS_ID_W (BPBS_ID_W),
            .IN_PIPE  (PIPE_IN_PIPE),
            .OUT_PIPE (PIPE_OUT_PIPE)
          ) ntt_core_wmm_clbu_pcg_pipe_0 (
            .clk        (clk),
            .s_rst_n    (s_rst_n),
            .in_data    (gr_out_data[gen_p]),
            .in_avail   (pipe_in_avail[gen_p][0]),
            .in_eol     (pipe_in_eol[gen_p][0]),
            .in_inc     (pipe_in_inc[gen_p][0]),
            .out_data   (pipe_out_data[gen_p][0]),
            .out_avail  (pipe_out_avail[gen_p][0]),

            .in_ctrl_sol     (rdx_out_ctrl[gen_d][gen_p].sol),
            .in_ctrl_eol     (/*UNUSED*/),
            .in_ctrl_sob     (rdx_out_ctrl[gen_d][gen_p].sob),
            .in_ctrl_eob     (/*UNUSED*/),
            .in_ctrl_sos     (rdx_out_ctrl[gen_d][gen_p].sos),
            .in_ctrl_eos     (/*UNUSED*/),
            .in_ctrl_ntt_bwd (rdx_out_ctrl[gen_d][gen_p].ntt_bwd),
            .in_ctrl_pbs_id  (rdx_out_ctrl[gen_d][gen_p].pbs_id),
            .in_ctrl_last_lpb(rdx_out_ctrl[gen_d][gen_p].last_lpb),
            .out_ctrl_sol    (pipe_out_ctrl[gen_p].sol),
            .out_ctrl_eol    (/*UNUSED*/),
            .out_ctrl_sob    (pipe_out_ctrl[gen_p].sob),
            .out_ctrl_eob    (/*UNUSED*/),
            .out_ctrl_sos    (pipe_out_ctrl[gen_p].sos),
            .out_ctrl_eos    (/*UNUSED*/),
            .out_ctrl_ntt_bwd(pipe_out_ctrl[gen_p].ntt_bwd),
            .out_ctrl_pbs_id (pipe_out_ctrl[gen_p].pbs_id),
            .out_ctrl_last_lpb(pipe_out_ctrl[gen_p].last_lpb)
          );

          // Pipe last coef
          ntt_core_wmm_clbu_pcg_pipe
          #(
            .OP_W     (OP_W),
            .R        (R),
            .STEP     ($clog2(POS_OCC)),
            .POS      (R-1),
            .LVL_NB   (INTL_L),
            .MIN_LVL_NB (GLWE_K_P1),
            .BPBS_ID_W (BPBS_ID_W),
            .IN_PIPE  (PIPE_IN_PIPE),
            .OUT_PIPE (PIPE_OUT_PIPE)
          ) ntt_core_wmm_clbu_pcg_pipe_Rm1 (
            .clk        (clk),
            .s_rst_n    (s_rst_n),
            .in_data    (gr_out_data[gen_p]),
            .in_avail   (pipe_in_avail[gen_p][R-1]),
            .in_eol     (pipe_in_eol[gen_p][R-1]),
            .in_inc     (pipe_in_inc[gen_p][R-1]),
            .out_data   (pipe_out_data[gen_p][R-1]),
            .out_avail  (pipe_out_avail[gen_p][R-1]),

            .in_ctrl_sol     ('x),
            .in_ctrl_eol     (rdx_out_ctrl[gen_d][gen_p].eol),
            .in_ctrl_sob     ('x),
            .in_ctrl_eob     (rdx_out_ctrl[gen_d][gen_p].eob),
            .in_ctrl_sos     ('x),
            .in_ctrl_eos     (rdx_out_ctrl[gen_d][gen_p].eos),
            .in_ctrl_ntt_bwd ('x),
            .in_ctrl_pbs_id  ('x),
            .in_ctrl_last_lpb('x),
            .out_ctrl_sol    (/*UNUSED*/),
            .out_ctrl_eol    (pipe_out_ctrl[gen_p].eol),
            .out_ctrl_sob    (/*UNUSED*/),
            .out_ctrl_eob    (pipe_out_ctrl[gen_p].eob),
            .out_ctrl_sos    (/*UNUSED*/),
            .out_ctrl_eos    (pipe_out_ctrl[gen_p].eos),
            .out_ctrl_ntt_bwd(/*UNUSED*/),
            .out_ctrl_pbs_id (/*UNUSED*/),
            .out_ctrl_last_lpb(/*UNUSED*/)
          );

          for (genvar gen_r=1; gen_r<R-1; gen_r=gen_r+1) begin : gen_r_loop
              ntt_core_wmm_clbu_pcg_pipe
              #(
                .OP_W     (OP_W),
                .R        (R),
                .STEP     ($clog2(POS_OCC)),
                .POS      (gen_r),
                .LVL_NB   (INTL_L),
                .MIN_LVL_NB (GLWE_K_P1),
                .BPBS_ID_W (BPBS_ID_W),
                .IN_PIPE  (PIPE_IN_PIPE),
                .OUT_PIPE (PIPE_OUT_PIPE)
              ) ntt_core_wmm_clbu_pcg_pipe (
                .clk        (clk),
                .s_rst_n    (s_rst_n),
                .in_data    (gr_out_data[gen_p]),
                .in_avail   (pipe_in_avail[gen_p][gen_r]),
                .in_eol     (pipe_in_eol[gen_p][gen_r]),
                .in_inc     (pipe_in_inc[gen_p][gen_r]),
                .out_data   (pipe_out_data[gen_p][gen_r]),
                .out_avail  (pipe_out_avail[gen_p][gen_r]),

                .in_ctrl_sol     ('x),
                .in_ctrl_eol     ('x),
                .in_ctrl_sob     ('x),
                .in_ctrl_eob     ('x),
                .in_ctrl_sos     ('x),
                .in_ctrl_eos     ('x),
                .in_ctrl_ntt_bwd ('x),
                .in_ctrl_pbs_id  ('x),
                .in_ctrl_last_lpb('x),
                .out_ctrl_sol    (/*UNUSED*/),
                .out_ctrl_eol    (/*UNUSED*/),
                .out_ctrl_sob    (/*UNUSED*/),
                .out_ctrl_eob    (/*UNUSED*/),
                .out_ctrl_sos    (/*UNUSED*/),
                .out_ctrl_eos    (/*UNUSED*/),
                .out_ctrl_ntt_bwd(/*UNUSED*/),
                .out_ctrl_pbs_id (/*UNUSED*/),
                .out_ctrl_last_lpb(/*UNUSED*/)

              );
          end // gen_r_loop

          assign pipe_in_inc[gen_p]     = {R{pipe_out_avail[gen_p][R-1]}};

        end // gen_p_loop
        logic [PSI-1:0] rdx_in_avail_l;
        assign rdx_in_data[gen_d+1]  = pipe_out_data;
        always_comb
          for (int p=0; p<PSI; p=p+1)
            rdx_in_avail_l[p] = pipe_out_avail[p][R-1];

        assign rdx_in_avail[gen_d+1]   = rdx_in_avail_l;
        assign rdx_in_ctrl[gen_d+1]    = pipe_out_ctrl;

        always_comb
          for (int p=0; p<PSI; p=p+1)
            rdx_in_ntt_bwd[gen_d+1][p] = pipe_out_ctrl[p].ntt_bwd;
      end // split group
    end // gen_ntw_d_loop
  endgenerate


  // =========================================================================================== --
  // Output
  // =========================================================================================== --
  logic [1:0][PSI-1:0][R-1:0][OP_W-1:0] out_z;
  control_t [1:0]                       out_ctrl;
  logic [1:0][PSI-1:0]                  out_avail;
  logic [1:0]                           out_send_to_next;

  generate
    for (genvar gen_i=0; gen_i<2; gen_i=gen_i+1) begin : gen_out // rs and ls
      logic             out_last_lpb;
      logic [PSI-1:0]   out_avail_tmp;
      control_t         out_ctrl_tmp;

      assign out_avail_tmp = rdx_out_avail[RLS_TO_DELTA_IDX[gen_i]];
      assign out_ctrl_tmp  = rdx_out_ctrl[RLS_TO_DELTA_IDX[gen_i]][0];
      assign out_last_lpb  = out_ctrl_tmp.last_lpb;

      assign out_send_to_next[gen_i] = (gen_i == LS) && out_last_lpb  ? 1'b0 :
                                       (gen_i == RS) && !out_last_lpb ? 1'b0 : 1'b1;

      assign out_z[gen_i]     = RLS_TO_OUT_WITH_NTW[gen_i] ?
                                    ntw_out_data[RLS_TO_DELTA_IDX[gen_i]] :
                                    rdx_out_data[RLS_TO_DELTA_IDX[gen_i]];
      assign out_ctrl[gen_i]  = out_ctrl_tmp;
      assign out_avail[gen_i] = out_avail_tmp & {PSI{~out_send_to_next[gen_i]}};
    end
  endgenerate

  always_comb
    for (int i=D_0; i<DELTA; i=i+1) begin
      if (i == DELTA-1)
        send_to_next[i] = '0; // necessarily the output
      else if (i == RS_DELTA_IDX && i != LS_DELTA_IDX)
        send_to_next[i] = {PSI*R{out_send_to_next[RS]}};
      else if (i == LS_DELTA_IDX && i != RS_DELTA_IDX)
        send_to_next[i] = {PSI*R{out_send_to_next[LS]}};
      else if (i == LS_DELTA_IDX && i == RS_DELTA_IDX)
        send_to_next[i] = '0;
      else
        send_to_next[i] = '1;
    end

  assign ls_z     = out_z[LS];
  assign ls_avail = out_avail[LS];

  assign ls_sob    = out_ctrl[LS].sob;
  assign ls_eob    = out_ctrl[LS].eob;
  assign ls_sol    = out_ctrl[LS].sol;
  assign ls_eol    = out_ctrl[LS].eol;
  assign ls_sos    = out_ctrl[LS].sos;
  assign ls_eos    = out_ctrl[LS].eos;
  assign ls_pbs_id = out_ctrl[LS].pbs_id;
  assign ls_ntt_bwd= out_ctrl[LS].ntt_bwd;

  assign rs_z     = out_z[RS];
  assign rs_avail = out_avail[RS];

  assign rs_sob    = out_ctrl[RS].sob;
  assign rs_eob    = out_ctrl[RS].eob;
  assign rs_sol    = out_ctrl[RS].sol;
  assign rs_eol    = out_ctrl[RS].eol;
  assign rs_sos    = out_ctrl[RS].sos;
  assign rs_eos    = out_ctrl[RS].eos;
  assign rs_pbs_id = out_ctrl[RS].pbs_id;
  assign rs_ntt_bwd= out_ctrl[RS].ntt_bwd;

  // =========================================================================================== --
  // Error
  // =========================================================================================== --
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      error_twd_phi <= 1'b0;
    end
    else begin
      error_twd_phi <= 1'b0;
    end

endmodule

