// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ==============================================================================================

`include "ntt_core_common_macro_inc.sv"

module tb_ntt_core_wmm_clbu_pcg_partition;
  import param_tfhe_pkg::*;
  import pep_common_param_pkg::*;
  import common_definition_pkg::*;

  `timescale 1ns/10ps

  // ============================================================================================ //
  // parameter
  // ============================================================================================ //
  parameter  int        OP_W          = 64;
  parameter  [OP_W-1:0] MOD_NTT       = 2**OP_W - 2**(OP_W/2) + 1;
  parameter  int        R             = 2; // Butterfly Radix
  parameter  int        PSI           = 4; // Number of butterflies
  parameter  mod_reduct_type_e     REDUCT_TYPE   = MOD_REDUCT_GOLDILOCKS;
  parameter  mod_mult_type_e       MOD_MULT_TYPE = MOD_MULT_GOLDILOCKS;
  parameter  arith_mult_type_e     MULT_TYPE     = MULT_GOLDILOCKS_CASCADE;

  parameter  int        S             = 6; // for this bench, set an even number
  parameter  int        RS_DELTA      = 3;//S-1;
  parameter  int        LS_DELTA      = 3;
  parameter  int        D_INIT        = 2;
  parameter  bit        RS_OUT_WITH_NTW = 1'b1;
  parameter  bit        LS_OUT_WITH_NTW = 1'b0;
  localparam int        LPB_NB        = 2;
  localparam int        DELTA         = RS_DELTA > LS_DELTA ? RS_DELTA : LS_DELTA;

  localparam int LS_S     = S-1;
  localparam int LS_S_DEC = 2;

  localparam int RS_S     = S;
  localparam int RS_S_DEC = 2;

  parameter  int        SIMU_BATCH_NB = 20;

  // ============================================================================================ //
  // localparam
  // ============================================================================================ //
  `NTT_CORE_LOCALPARAM(R,S,PSI)

  // system
  localparam int CLK_HALF_PERIOD   = 1;
  localparam int ARST_ACTIVATION   = 17;

  localparam int S_W = $clog2(S);

  localparam int RS_DELTA_IDX = RS_DELTA - 1;
  localparam int LS_DELTA_IDX = LS_DELTA - 1;

  localparam int RS_GROUP_SIZE = R**(RS_DELTA_IDX + 2);
  localparam int LS_GROUP_SIZE = R**(LS_DELTA_IDX + 2);

  localparam int RS_REV_DEPTH = (PSI*R) >= RS_GROUP_SIZE ? RS_DELTA+RS_OUT_WITH_NTW : RS_DELTA;
  localparam int LS_REV_DEPTH = (PSI*R) >= LS_GROUP_SIZE ? LS_DELTA+LS_OUT_WITH_NTW : LS_DELTA;

  initial begin
    // Check bench parameters
    if ((S % 2) == 1) begin : __UNSUPPORTED_BENCH_S_VALUE
      $fatal(1,"> ERROR: This bench only supports even number for S");
    end
  end

  // ============================================================================================ //
  // type
  // ============================================================================================ //
  typedef struct packed {
    logic                sob;
    logic                eob;
    logic                sol;
    logic                eol;
    logic                sos;
    logic                eos;
    logic                in_ntt_bwd;
    logic [BPBS_ID_W-1:0] in_pbs_id;
  } control_t;

  typedef struct packed {
    logic                  ntt_bwd;
    logic [S_W-1:0]        stg;
    logic [BPBS_ID_W-1:0]   pbs_id;
    logic [INTL_L_W-1:0]   lvl_id;
    logic [S-1:0][R_W-1:0] coef;
  } data_t;

  // ============================================================================================ //
  // function
  // ============================================================================================ //
  function [S-1:0] rev_value(logic[S-1:0] v, int delta);
    logic [S-1:0] rev_v;
    logic [S-1:0] tmp0;
    logic [S-1:0] tmp1;

    for (int i=0; i<S; i=i+1)
      if (i < delta)
        rev_v[i] = v[i];
      else
        rev_v[i] = v[S-1-(i-delta)];

    tmp0 = rev_v << (S-delta);
    tmp1 = rev_v >> delta;
    //$display("v='b%b rev='b%0b tmp0='b%0b tmp1='b%0b res='b%0b step=%0d",v,rev_v,tmp0,tmp1,tmp0|tmp1,delta);
    return tmp0 | tmp1;
  endfunction

  // ============================================================================================ //
  // clock, reset
  // ============================================================================================ //
  bit clk;
  bit a_rst_n;
  bit s_rst_n;

  initial begin
    clk     = 1'b0;
    a_rst_n = 1'b0;
    #ARST_ACTIVATION a_rst_n = 1'b1;
  end

  always begin
    #CLK_HALF_PERIOD clk = ~clk;
  end

  always_ff @(posedge clk) begin
    s_rst_n <= a_rst_n;
  end

  // ============================================================================================ //
  // End of test
  // ============================================================================================ //
  bit end_of_test;

  initial begin
    wait (end_of_test);
    @(posedge clk) $display("%t > SUCCEED !", $time);
    $finish;
  end

  // ============================================================================================ //
  // Error
  // ============================================================================================ //
  bit error;
  bit error_ctrl_rs;
  bit error_data_rs;
  bit error_ctrl_ls;
  bit error_data_ls;

  assign error = error_ctrl_rs
               | error_data_rs
               | error_ctrl_ls
               | error_data_ls;

  always_ff @(posedge clk) begin
    if (error) begin
      $display("%t > ERROR: error_ctrl_rs : %b", $time,error_ctrl_rs);
      $display("%t > ERROR: error_data_rs : %b", $time, error_data_rs);
      $display("%t > ERROR: error_ctrl_ls : %b", $time,error_ctrl_ls);
      $display("%t > ERROR: error_data_ls : %b", $time, error_data_ls);
      $display("%t > FAILURE !", $time);
      $stop;
    end
  end

  // ============================================================================================ //
  // IO
  // ============================================================================================ //
  // Input data : in reverse(R,S) order
  logic [PSI-1:0][R-1:0][OP_W-1:0]            in_a;
  logic [PSI-1:0]                             in_ntt_bwd; // For omg_ru selection
  logic                                       in_sob;
  logic                                       in_eob;
  logic                                       in_sol;
  logic                                       in_eol;
  logic                                       in_sos;
  logic                                       in_eos;
  logic [BPBS_ID_W-1:0]                        in_pbs_id;
  logic [PSI-1:0]                             in_avail;
  // Output data : in pseudo-reverse(R;S,DELTA) order
  logic [PSI-1:0][R-1:0][OP_W-1:0]            out_z;
  logic                                       out_sob;
  logic                                       out_eob;
  logic                                       out_sol;
  logic                                       out_eol;
  logic                                       out_sos;
  logic                                       out_eos;
  logic [BPBS_ID_W-1:0]                        out_pbs_id;
  logic [PSI-1:0]                             out_avail;

  // Output data : in pseudo-reverse(R,S,DELTA) order
  logic [PSI-1:0][R-1:0][OP_W-1:0]            rs_z;
  logic                                       rs_sob;
  logic                                       rs_eob;
  logic                                       rs_sol;
  logic                                       rs_eol;
  logic                                       rs_sos;
  logic                                       rs_eos;
  logic [BPBS_ID_W-1:0]                        rs_pbs_id;
  logic                                       rs_ntt_bwd;
  logic [PSI-1:0]                             rs_avail;

  // Output when lbp_cnt = LPB_NB-1
  logic [PSI-1:0][R-1:0][OP_W-1:0]            ls_z;
  logic                                       ls_sob;
  logic                                       ls_eob;
  logic                                       ls_sol;
  logic                                       ls_eol;
  logic                                       ls_sos;
  logic                                       ls_eos;
  logic [BPBS_ID_W-1:0]                        ls_pbs_id;
  logic                                       ls_ntt_bwd;
  logic [PSI-1:0]                             ls_avail;

  // Intermediate
  logic [PSI-1:0][R-1:0][OP_W-1:0]            interm_z;
  logic                                       interm_sob;
  logic                                       interm_eob;
  logic                                       interm_sol;
  logic                                       interm_eol;
  logic                                       interm_sos;
  logic                                       interm_eos;
  logic [BPBS_ID_W-1:0]                        interm_pbs_id;
  logic                                       interm_ntt_bwd;
  logic [PSI-1:0]                             interm_avail;

  // Twiddles
  logic [1:0][R/2-1:0][OP_W-1:0]              twd_omg_ru_r_pow; // [0] NTT, [1] INTT
  // [i] = omg_ru_r ** i
  logic [DELTA-1:0][PSI-1:0][R-1:1][OP_W-1:0] twd_phi_ru;
  logic [DELTA-1:0][PSI-1:0]                  twd_phi_ru_vld;
  logic [DELTA-1:0][PSI-1:0]                  twd_phi_ru_rdy;
  // Error
  logic                                       error_twd_phi;
  logic                                       error_twd_phi_interm;


  // ============================================================================================ //
  // Design under test instance
  // ============================================================================================ //
  ntt_core_wmm_clbu_pcg
  #(
    .OP_W            (OP_W),
    .MOD_NTT         (MOD_NTT),
    .R               (R),
    .PSI             (PSI),
    .S               (S),
    .D_INIT     (0),
    .RS_DELTA        (D_INIT),
    .LS_DELTA        (D_INIT),
    .LPB_NB          (1), // Output on LS path
    .RS_OUT_WITH_NTW (1'b0),
    .LS_OUT_WITH_NTW (1'b0),
    .REDUCT_TYPE     (REDUCT_TYPE),
    .MOD_MULT_TYPE   (MOD_MULT_TYPE),
    .MULT_TYPE       (MULT_TYPE)

  ) dut_part1 (
    .clk             (clk),
    .s_rst_n         (s_rst_n),

    .in_a            (in_a),
    .in_ntt_bwd      (in_ntt_bwd),
    .in_sob          (in_sob),
    .in_eob          (in_eob),
    .in_sol          (in_sol),
    .in_eol          (in_eol),
    .in_sos          (in_sos),
    .in_eos          (in_eos),
    .in_pbs_id       (in_pbs_id),
    .in_avail        (in_avail),

    .ls_z           (interm_z),
    .ls_sob         (interm_sob),
    .ls_eob         (interm_eob),
    .ls_sol         (interm_sol),
    .ls_eol         (interm_eol),
    .ls_sos         (interm_sos),
    .ls_eos         (interm_eos),
    .ls_pbs_id      (interm_pbs_id),
    .ls_ntt_bwd     (interm_ntt_bwd),
    .ls_avail       (interm_avail),

    .rs_z           (/*UNUSED*/),
    .rs_sob         (/*UNUSED*/),
    .rs_eob         (/*UNUSED*/),
    .rs_sol         (/*UNUSED*/),
    .rs_eol         (/*UNUSED*/),
    .rs_sos         (/*UNUSED*/),
    .rs_eos         (/*UNUSED*/),
    .rs_pbs_id      (/*UNUSED*/),
    .rs_ntt_bwd     (/*UNUSED*/),
    .rs_avail       (/*UNUSED*/),

    .twd_omg_ru_r_pow(twd_omg_ru_r_pow),

    .twd_phi_ru      (twd_phi_ru[D_INIT-1:0]),
    .twd_phi_ru_vld  (twd_phi_ru_vld[D_INIT-1:0]),
    .twd_phi_ru_rdy  (twd_phi_ru_rdy[D_INIT-1:0]),

    .error_twd_phi   (error_twd_phi_interm)
  );

  ntt_core_wmm_clbu_pcg
  #(
    .OP_W            (OP_W),
    .MOD_NTT         (MOD_NTT),
    .R               (R),
    .PSI             (PSI),
    .S               (S),
    .D_INIT     (D_INIT),
    .RS_DELTA        (RS_DELTA),
    .LS_DELTA        (LS_DELTA),
    .LPB_NB          (LPB_NB),
    .RS_OUT_WITH_NTW (RS_OUT_WITH_NTW),
    .LS_OUT_WITH_NTW (LS_OUT_WITH_NTW),
    .REDUCT_TYPE     (REDUCT_TYPE),
    .MOD_MULT_TYPE   (MOD_MULT_TYPE),
    .MULT_TYPE       (MULT_TYPE)

  ) dut_part2 (
    .clk             (clk),
    .s_rst_n         (s_rst_n),

    .in_a            (interm_z),
    .in_ntt_bwd      (interm_ntt_bwd),
    .in_sob          (interm_sob),
    .in_eob          (interm_eob),
    .in_sol          (interm_sol),
    .in_eol          (interm_eol),
    .in_sos          (interm_sos),
    .in_eos          (interm_eos),
    .in_pbs_id       (interm_pbs_id),
    .in_avail        (interm_avail),

    .ls_z           (ls_z),
    .ls_sob         (ls_sob),
    .ls_eob         (ls_eob),
    .ls_sol         (ls_sol),
    .ls_eol         (ls_eol),
    .ls_sos         (ls_sos),
    .ls_eos         (ls_eos),
    .ls_pbs_id      (ls_pbs_id),
    .ls_avail       (ls_avail),

    .rs_z           (rs_z),
    .rs_sob         (rs_sob),
    .rs_eob         (rs_eob),
    .rs_sol         (rs_sol),
    .rs_eol         (rs_eol),
    .rs_sos         (rs_sos),
    .rs_eos         (rs_eos),
    .rs_pbs_id      (rs_pbs_id),
    .rs_avail       (rs_avail),

    .twd_omg_ru_r_pow(twd_omg_ru_r_pow),

    .twd_phi_ru      (twd_phi_ru[DELTA-1:D_INIT]),
    .twd_phi_ru_vld  (twd_phi_ru_vld[DELTA-1:D_INIT]),
    .twd_phi_ru_rdy  (twd_phi_ru_rdy[DELTA-1:D_INIT]),

    .error_twd_phi   (error_twd_phi)
  );

  // ============================================================================================ //
  // Stimuli
  // ============================================================================================ //
  logic s0_avail_tmp;

  integer s0_lvl_id;
  integer s0_stg_iter;
  integer s0_stg;
  integer s0_pbs_id;
  logic   s0_ntt_bwd;
  integer s0_batch_cnt;

  integer s0_lvl_idD;
  integer s0_stg_iterD;
  integer s0_stgD;
  integer s0_pbs_idD;
  logic   s0_ntt_bwdD;
  integer s0_batch_cntD;

  integer s0_lvl_id_max;
  logic s0_first_lvl_id;
  logic s0_last_lvl_id;
  logic s0_first_stg_iter;
  logic s0_last_stg_iter;
  logic s0_first_stg;
  logic s0_last_stg;
  logic s0_first_pbs_id;
  logic s0_last_pbs_id;
  logic s0_last_batch_cnt;

  assign s0_lvl_id_max     = s0_ntt_bwd ? GLWE_K_P1-1: INTL_L-1;
  assign s0_first_lvl_id   = s0_lvl_id == 0;
  assign s0_last_lvl_id    = s0_lvl_id == s0_lvl_id_max;
  assign s0_first_stg_iter = s0_stg_iter == 0;
  assign s0_last_stg_iter  = s0_stg_iter == (STG_ITER_NB-1);
  assign s0_first_stg      = s0_stg == (S-1);
  assign s0_last_stg       = s0_stg == 0;
  assign s0_first_pbs_id   = s0_pbs_id == 0;
  assign s0_last_pbs_id    = s0_pbs_id == (BATCH_PBS_NB-1);
  assign s0_last_batch_cnt = s0_batch_cnt == (SIMU_BATCH_NB-1);

  assign s0_lvl_idD    = s0_avail_tmp ? s0_last_lvl_id ? '0 : s0_lvl_id + 1: s0_lvl_id;
  assign s0_stg_iterD  = (s0_avail_tmp && s0_last_lvl_id) ? s0_last_stg_iter ? '0 : s0_stg_iter + 1 : s0_stg_iter;
  assign s0_pbs_idD    = (s0_avail_tmp && s0_last_lvl_id && s0_last_stg_iter) ? s0_last_pbs_id ? 0 : s0_pbs_id + 1 : s0_pbs_id;
  assign s0_stgD       = (s0_avail_tmp && s0_last_lvl_id && s0_last_stg_iter && s0_last_pbs_id) ? s0_last_stg ? S-1 : s0_stg - 1 : s0_stg;
  assign s0_ntt_bwdD   = (s0_avail_tmp && s0_last_lvl_id && s0_last_stg_iter && s0_last_pbs_id && s0_last_stg) ? ~s0_ntt_bwd : s0_ntt_bwd;
  assign s0_batch_cntD = (s0_avail_tmp && s0_last_lvl_id && s0_last_stg_iter && s0_last_pbs_id && s0_last_stg && s0_ntt_bwd) ? s0_batch_cnt + 1 : s0_batch_cnt;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      s0_lvl_id   <= '0;
      s0_stg_iter <= '0;
      s0_stg      <= S-1;
      s0_pbs_id   <= '0;
      s0_ntt_bwd  <= 1'b0;
      s0_batch_cnt <= '0;
    end
    else begin
      s0_lvl_id   <= s0_lvl_idD  ;
      s0_stg_iter <= s0_stg_iterD;
      s0_stg      <= s0_stgD     ;
      s0_pbs_id   <= s0_pbs_idD  ;
      s0_ntt_bwd  <= s0_ntt_bwdD ;
      s0_batch_cnt <= s0_batch_cntD;
    end

  assign in_sol    = s0_first_lvl_id;
  assign in_eol    = s0_last_lvl_id;
  assign in_sos    = in_sol & s0_first_stg_iter;
  assign in_eos    = in_eol & s0_last_stg_iter;
  assign in_sob    = in_sos & s0_first_pbs_id;
  assign in_eob    = in_eos & s0_last_pbs_id;
  assign in_ntt_bwd = s0_ntt_bwd;
  assign in_pbs_id  = s0_pbs_id;

  assign in_avail = {PSI{s0_avail_tmp}};

  always_ff @(posedge clk)
    if (!s_rst_n) s0_avail_tmp <= 1'b0;
    else          s0_avail_tmp <= 1'b1;//$urandom;

  // Data
  always_comb
    for (int p=0; p<PSI; p=p+1) begin
      for (int r=0; r<R; r=r+1) begin
        logic [S*R_W-1:0] v_tmp;
        logic [S-1:0][R_W-1:0] v;
        logic [S-1:0][R_W-1:0] v_rev;
        data_t d;
        v_tmp = s0_stg_iter * R * PSI + p*R + r;
        v = v_tmp;
        for (int s=0; s<S; s=s+1)
          v_rev[s] = v[S-1-s];

        d.coef     = v_rev;
        d.stg      = s0_stg;
        d.ntt_bwd  = s0_ntt_bwd;
        d.lvl_id   = s0_lvl_id;
        d.pbs_id   = s0_pbs_id;
        in_a[p][r] = d;
      end
    end

  // ============================================================================================ //
  // Output check
  // ============================================================================================ //
  //--------------------------
  // LS
  //--------------------------
  logic ls_avail_tmp;

  integer ref_ls_lvl_id;
  integer ref_ls_stg_iter;
  integer ref_ls_stg;
  integer ref_ls_pbs_id;
  logic   ref_ls_ntt_bwd;
  integer ref_ls_batch_cnt;

  integer ref_ls_lvl_idD;
  integer ref_ls_stg_iterD;
  integer ref_ls_stgD;
  integer ref_ls_pbs_idD;
  logic   ref_ls_ntt_bwdD;
  integer ref_ls_batch_cntD;

  integer ref_ls_lvl_id_max;
  logic ref_ls_first_lvl_id;
  logic ref_ls_last_lvl_id;
  logic ref_ls_first_stg_iter;
  logic ref_ls_last_stg_iter;
  logic ref_ls_first_stg;
  logic ref_ls_wrap_stg;
  logic ref_ls_first_pbs_id;
  logic ref_ls_last_pbs_id;
  logic ref_ls_last_batch_cnt;

  assign ref_ls_lvl_id_max     = ref_ls_ntt_bwd ? GLWE_K_P1-1: INTL_L-1;
  assign ref_ls_first_lvl_id   = ref_ls_lvl_id == 0;
  assign ref_ls_last_lvl_id    = ref_ls_lvl_id == ref_ls_lvl_id_max;
  assign ref_ls_first_stg_iter = ref_ls_stg_iter == 0;
  assign ref_ls_last_stg_iter  = ref_ls_stg_iter == (STG_ITER_NB-1);
  assign ref_ls_first_stg      = ref_ls_stg == (LS_S-1);
  assign ref_ls_wrap_stg       = ref_ls_stg < LS_S_DEC;
  assign ref_ls_first_pbs_id   = ref_ls_pbs_id == 0;
  assign ref_ls_last_pbs_id    = ref_ls_pbs_id == (BATCH_PBS_NB-1);
  assign ref_ls_last_batch_cnt = ref_ls_batch_cnt == (SIMU_BATCH_NB-1);

  assign ref_ls_lvl_idD    = ls_avail_tmp ? ref_ls_last_lvl_id ? '0 : ref_ls_lvl_id + 1: ref_ls_lvl_id;
  assign ref_ls_stg_iterD  = (ls_avail_tmp && ref_ls_last_lvl_id) ? ref_ls_last_stg_iter ? '0 : ref_ls_stg_iter + 1 : ref_ls_stg_iter;
  assign ref_ls_pbs_idD    = (ls_avail_tmp && ref_ls_last_lvl_id && ref_ls_last_stg_iter) ? ref_ls_last_pbs_id ? 0 : ref_ls_pbs_id + 1 : ref_ls_pbs_id;
  assign ref_ls_stgD       = (ls_avail_tmp && ref_ls_last_lvl_id && ref_ls_last_stg_iter && ref_ls_last_pbs_id) ? ref_ls_wrap_stg ? LS_S-1 : ref_ls_stg - LS_S_DEC : ref_ls_stg;
  assign ref_ls_ntt_bwdD   = (ls_avail_tmp && ref_ls_last_lvl_id && ref_ls_last_stg_iter && ref_ls_last_pbs_id && ref_ls_wrap_stg) ? ~ref_ls_ntt_bwd : ref_ls_ntt_bwd;
  assign ref_ls_batch_cntD = (ls_avail_tmp && ref_ls_last_lvl_id && ref_ls_last_stg_iter && ref_ls_last_pbs_id && ref_ls_wrap_stg && ref_ls_ntt_bwd) ? ref_ls_batch_cnt + 1 : ref_ls_batch_cnt;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      ref_ls_lvl_id    <= '0;
      ref_ls_stg_iter  <= '0;
      ref_ls_stg       <= LS_S-1;
      ref_ls_pbs_id    <= '0;
      ref_ls_ntt_bwd   <= 1'b0;
      ref_ls_batch_cnt <= '0;
    end
    else begin
      ref_ls_lvl_id   <= ref_ls_lvl_idD  ;
      ref_ls_stg_iter <= ref_ls_stg_iterD;
      ref_ls_stg      <= ref_ls_stgD     ;
      ref_ls_pbs_id   <= ref_ls_pbs_idD  ;
      ref_ls_ntt_bwd  <= ref_ls_ntt_bwdD ;
      ref_ls_batch_cnt <= ref_ls_batch_cntD;
    end

  assign ref_ls_sol    = ref_ls_first_lvl_id;
  assign ref_ls_eol    = ref_ls_last_lvl_id;
  assign ref_ls_sos    = ref_ls_sol & ref_ls_first_stg_iter;
  assign ref_ls_eos    = ref_ls_eol & ref_ls_last_stg_iter;
  assign ref_ls_sob    = ref_ls_sos & ref_ls_first_pbs_id;
  assign ref_ls_eob    = ref_ls_eos & ref_ls_last_pbs_id;

  assign ls_avail_tmp = ls_avail[0];

  logic [PSI-1:0][R-1:0][OP_W-1:0] ref_ls_z;
  logic [PSI-1:0][R-1:0][OP_W-1:0] ref_ls_z_tmp;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      error_ctrl_ls <= 1'b0;
      error_data_ls <= 1'b0;
    end
    else begin
      if (ls_avail_tmp) begin
        assert((ls_sol == ref_ls_sol)
                && (ls_eol == ref_ls_eol)
                && (ls_sos == ref_ls_sos)
                && (ls_eos == ref_ls_eos)
                && (ls_sob == ref_ls_sob)
                && (ls_eob == ref_ls_eob)
                //&& (ls_ntt_bwd == ref_ls_ntt_bwd)
                && (ls_pbs_id == ref_ls_pbs_id)
                )
        else begin
          $display("%t > ERROR: control mismatch.", $time);
          $display("%t > sol exp=%0d seen=%0d", $time, ref_ls_sol, ls_sol);
          $display("%t > eol exp=%0d seen=%0d", $time, ref_ls_eol, ls_eol);
          $display("%t > sos exp=%0d seen=%0d", $time, ref_ls_sos, ls_sos);
          $display("%t > eos exp=%0d seen=%0d", $time, ref_ls_eos, ls_eos);
          $display("%t > sob exp=%0d seen=%0d", $time, ref_ls_sob, ls_sob);
          $display("%t > eob exp=%0d seen=%0d", $time, ref_ls_eob, ls_eob);
          //$display("%t > ntt_bwd exp=%0d seen=%0d", ref_ls_ntt_bwd, ls_ntt_bwd);
          $display("%t > pbs_id exp=%0d seen=%0d", $time, ref_ls_pbs_id, ls_pbs_id);
          error_ctrl_ls <= 1'b1;
        end


        for (int p=0; p<PSI; p=p+1) begin
          for (int r=0; r<R; r=r+1) begin
            logic [S*R_W-1:0] v_tmp;
            logic [S-1:0][R_W-1:0] v;
            data_t d;
            v_tmp = ref_ls_stg_iter * R * PSI + p*R + r;
            v = rev_value(v_tmp, LS_REV_DEPTH);

            d.coef     = v;
            d.stg      = ref_ls_stg;
            d.ntt_bwd  = ref_ls_ntt_bwd;
            d.lvl_id   = ref_ls_lvl_id;
            d.pbs_id   = ref_ls_pbs_id;
            ref_ls_z_tmp[p][r] = d;

          end
        end

// Uncomment the following if the network is connected when POS_NB == 1 for the output
//        if (((PSI*R) < LS_GROUP_SIZE) && LS_OUT_WITH_NTW) begin
//          logic [PSI*R-1:0][OP_W-1:0] ref_ls_z_tmp2;
//          ref_ls_z_tmp2 = ref_ls_z_tmp;
//          // reorder with stride
//          for (int p=0; p<PSI; p=p+1) begin
//            for (int r=0; r<R; r=r+1) begin
//              data_t d;
//              //$display(">>> Reorder ref_ls_z_tmp='b%0d ref_ls_z='b%0d LS_GROUP_SIZE=%0d PSI*R=%0d",ref_ls_z_tmp[p][r],ref_ls_z_tmp2[r*PSI+p],LS_GROUP_SIZE,PSI*R);
//              d.coef = ref_ls_z_tmp2[r*PSI+p];
//              d.stg      = ref_ls_stg;
//              d.ntt_bwd  = ref_ls_ntt_bwd;
//              d.lvl_id   = ref_ls_lvl_id;
//              d.pbs_id   = ref_ls_pbs_id;
//
//              ref_ls_z[p][r] = d;
//            end
//          end
//        end
//        else begin
//          ref_ls_z = ref_ls_z_tmp;
//        end

        assign ref_ls_z = ref_ls_z_tmp;

        for (int p=0; p<PSI; p=p+1) begin
          for (int r=0; r<R; r=r+1) begin
            assert(ls_z[p][r] == ref_ls_z[p][r])
            else begin
              $display("%t > ERROR: data mismatch LS (p=%0d, r=%0d) exp=0x%0x seen=%0x.",$time, p,r,ref_ls_z[p][r], ls_z[p][r]);
              error_data_ls <= 1'b1;
            end

          end
        end

      end
    end

  //--------------------------
  // RS
  //--------------------------
  logic rs_avail_tmp;

  integer ref_rs_lvl_id;
  integer ref_rs_stg_iter;
  integer ref_rs_stg;
  integer ref_rs_pbs_id;
  logic   ref_rs_ntt_bwd;
  integer ref_rs_batch_cnt;

  integer ref_rs_lvl_idD;
  integer ref_rs_stg_iterD;
  integer ref_rs_stgD;
  integer ref_rs_pbs_idD;
  logic   ref_rs_ntt_bwdD;
  integer ref_rs_batch_cntD;

  integer ref_rs_lvl_id_max;
  logic ref_rs_first_lvl_id;
  logic ref_rs_last_lvl_id;
  logic ref_rs_first_stg_iter;
  logic ref_rs_last_stg_iter;
  logic ref_rs_first_stg;
  logic ref_rs_wrap_stg;
  logic ref_rs_first_pbs_id;
  logic ref_rs_last_pbs_id;
  logic ref_rs_last_batch_cnt;

  assign ref_rs_lvl_id_max     = ref_rs_ntt_bwd ? GLWE_K_P1-1: INTL_L-1;
  assign ref_rs_first_lvl_id   = ref_rs_lvl_id == 0;
  assign ref_rs_last_lvl_id    = ref_rs_lvl_id == ref_rs_lvl_id_max;
  assign ref_rs_first_stg_iter = ref_rs_stg_iter == 0;
  assign ref_rs_last_stg_iter  = ref_rs_stg_iter == (STG_ITER_NB-1);
  assign ref_rs_first_stg      = ref_rs_stg == (RS_S-1);
  assign ref_rs_wrap_stg       = ref_rs_stg < RS_S_DEC;
  assign ref_rs_first_pbs_id   = ref_rs_pbs_id == 0;
  assign ref_rs_last_pbs_id    = ref_rs_pbs_id == (BATCH_PBS_NB-1);
  assign ref_rs_last_batch_cnt = ref_rs_batch_cnt == (SIMU_BATCH_NB-1);

  assign ref_rs_lvl_idD    = rs_avail_tmp ? ref_rs_last_lvl_id ? '0 : ref_rs_lvl_id + 1: ref_rs_lvl_id;
  assign ref_rs_stg_iterD  = (rs_avail_tmp && ref_rs_last_lvl_id) ? ref_rs_last_stg_iter ? '0 : ref_rs_stg_iter + 1 : ref_rs_stg_iter;
  assign ref_rs_pbs_idD    = (rs_avail_tmp && ref_rs_last_lvl_id && ref_rs_last_stg_iter) ? ref_rs_last_pbs_id ? 0 : ref_rs_pbs_id + 1 : ref_rs_pbs_id;
  assign ref_rs_stgD       = (rs_avail_tmp && ref_rs_last_lvl_id && ref_rs_last_stg_iter && ref_rs_last_pbs_id) ? ref_rs_wrap_stg ? RS_S-1 : ref_rs_stg - RS_S_DEC : ref_rs_stg;
  assign ref_rs_ntt_bwdD   = (rs_avail_tmp && ref_rs_last_lvl_id && ref_rs_last_stg_iter && ref_rs_last_pbs_id && ref_rs_wrap_stg) ? ~ref_rs_ntt_bwd : ref_rs_ntt_bwd;
  assign ref_rs_batch_cntD = (rs_avail_tmp && ref_rs_last_lvl_id && ref_rs_last_stg_iter && ref_rs_last_pbs_id && ref_rs_wrap_stg && ref_rs_ntt_bwd) ? ref_rs_batch_cnt + 1 : ref_rs_batch_cnt;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      ref_rs_lvl_id   <= '0;
      ref_rs_stg_iter <= '0;
      ref_rs_stg      <= RS_S-1;
      ref_rs_pbs_id   <= '0;
      ref_rs_ntt_bwd  <= 1'b0;
      ref_rs_batch_cnt <= '0;
    end
    else begin
      ref_rs_lvl_id   <= ref_rs_lvl_idD  ;
      ref_rs_stg_iter <= ref_rs_stg_iterD;
      ref_rs_stg      <= ref_rs_stgD     ;
      ref_rs_pbs_id   <= ref_rs_pbs_idD  ;
      ref_rs_ntt_bwd  <= ref_rs_ntt_bwdD ;
      ref_rs_batch_cnt <= ref_rs_batch_cntD;
    end

  assign ref_rs_sol    = ref_rs_first_lvl_id;
  assign ref_rs_eol    = ref_rs_last_lvl_id;
  assign ref_rs_sos    = ref_rs_sol & ref_rs_first_stg_iter;
  assign ref_rs_eos    = ref_rs_eol & ref_rs_last_stg_iter;
  assign ref_rs_sob    = ref_rs_sos & ref_rs_first_pbs_id;
  assign ref_rs_eob    = ref_rs_eos & ref_rs_last_pbs_id;

  assign rs_avail_tmp = rs_avail[0];

  logic [PSI-1:0][R-1:0][OP_W-1:0] ref_rs_z;
  logic [PSI-1:0][R-1:0][OP_W-1:0] ref_rs_z_tmp;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      error_ctrl_rs <= 1'b0;
      error_data_rs <= 1'b0;
    end
    else begin
      if (rs_avail_tmp) begin
        assert((rs_sol == ref_rs_sol)
                && (rs_eol == ref_rs_eol)
                && (rs_sos == ref_rs_sos)
                && (rs_eos == ref_rs_eos)
                && (rs_sob == ref_rs_sob)
                && (rs_eob == ref_rs_eob)
                //&& (rs_ntt_bwd == ref_rs_ntt_bwd)
                && (rs_pbs_id == ref_rs_pbs_id)
                )
        else begin
          $display("%t > ERROR: control mismatch.", $time);
          $display("%t > sol exp=%0d seen=%0d", $time, ref_rs_sol, rs_sol);
          $display("%t > eol exp=%0d seen=%0d", $time, ref_rs_eol, rs_eol);
          $display("%t > sos exp=%0d seen=%0d", $time, ref_rs_sos, rs_sos);
          $display("%t > eos exp=%0d seen=%0d", $time, ref_rs_eos, rs_eos);
          $display("%t > sob exp=%0d seen=%0d", $time, ref_rs_sob, rs_sob);
          $display("%t > eob exp=%0d seen=%0d", $time, ref_rs_eob, rs_eob);
          //$display("%t > ntt_bwd exp=%0d seen=%0d", ref_rs_ntt_bwd, rs_ntt_bwd);
          $display("%t > pbs_id exp=%0d seen=%0d", $time, ref_rs_pbs_id, rs_pbs_id);
          error_ctrl_rs <= 1'b1;
        end


        for (int p=0; p<PSI; p=p+1) begin
          for (int r=0; r<R; r=r+1) begin
            logic [S*R_W-1:0] v_tmp;
            logic [S-1:0][R_W-1:0] v;
            logic [OP_W-1:0] z;
            data_t d;
            v_tmp = ref_rs_stg_iter * R * PSI + p*R + r;
            v = rev_value(v_tmp, RS_REV_DEPTH);

            d.coef     = v;
            d.stg      = ref_rs_stg;
            d.ntt_bwd  = ref_rs_ntt_bwd;
            d.lvl_id   = ref_rs_lvl_id;
            d.pbs_id   = ref_rs_pbs_id;
            ref_rs_z_tmp[p][r] = d;

          end
        end

// Uncomment the following if the network is connected when POS_NB == 1 for the output
//        if (((PSI*R) < RS_GROUP_SIZE) && RS_OUT_WITH_NTW) begin
//          logic [PSI*R-1:0][OP_W-1:0] ref_rs_z_tmp2;
//          ref_rs_z_tmp2 = ref_rs_z_tmp;
//          // reorder with stride
//          for (int p=0; p<PSI; p=p+1) begin
//            for (int r=0; r<R; r=r+1) begin
//              data_t d;
//              //$display(">>> Reorder ref_rs_z_tmp='b%0d ref_rs_z='b%0d RS_GROUP_SIZE=%0d PSI*R=%0d",ref_rs_z_tmp[p][r],ref_rs_z_tmp2[r*PSI+p],RS_GROUP_SIZE,PSI*R);
//              d.coef = ref_rs_z_tmp2[r*PSI+p];
//              d.stg      = ref_rs_stg;
//              d.ntt_bwd  = ref_rs_ntt_bwd;
//              d.lvl_id   = ref_rs_lvl_id;
//              d.pbs_id   = ref_rs_pbs_id;
//
//              ref_rs_z[p][r] = d;
//            end
//          end
//
//        end
//        else begin
//          ref_rs_z = ref_rs_z_tmp;
//        end

        assign ref_rs_z = ref_rs_z_tmp;

        for (int p=0; p<PSI; p=p+1) begin
          for (int r=0; r<R; r=r+1) begin
            assert(rs_z[p][r] == ref_rs_z[p][r])
            else begin
              $display("%t > ERROR: data mismatch RS (p=%0d, r=%0d) exp=0x%0x seen=%0x.",$time, p,r,ref_rs_z[p][r], rs_z[p][r]);
              error_data_rs <= 1'b1;
            end

          end
        end

      end
    end

  // ============================================================================================ //
  // End of test
  // ============================================================================================ //
  assign end_of_test = (s0_batch_cnt == SIMU_BATCH_NB) && (ref_ls_batch_cnt == SIMU_BATCH_NB);

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      if (ls_avail_tmp && ref_ls_last_lvl_id && ref_ls_last_stg_iter && ref_ls_last_pbs_id && ref_ls_wrap_stg && ref_ls_ntt_bwd && ref_ls_batch_cnt%10 == 0)
       $display("%t > INFO: ref_ls_batch_cnt #%0d / %0d", $time, ref_ls_batch_cnt, SIMU_BATCH_NB);
    end
endmodule
