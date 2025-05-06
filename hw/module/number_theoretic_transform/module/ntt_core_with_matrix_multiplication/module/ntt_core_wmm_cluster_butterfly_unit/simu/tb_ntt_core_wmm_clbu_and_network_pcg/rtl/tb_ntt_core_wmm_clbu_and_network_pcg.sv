// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ==============================================================================================

`include "ntt_core_common_macro_inc.sv"

module tb_ntt_core_wmm_clbu_and_network_pcg;
  import param_tfhe_pkg::*;
  import pep_common_param_pkg::*;
  import common_definition_pkg::*;

  `timescale 1ns/10ps

  // ============================================================================================ //
  // parameter
  // ============================================================================================ //
  parameter  int        OP_W          = 32;
  parameter  [OP_W-1:0] MOD_NTT       = 2**32-2**17-2**13+1;
  parameter  int        R             = 2; // Butterfly Radix
  parameter  int        PSI           = 8; // Number of butterflies
  parameter  int        S             = 11;
  parameter  int        RS_DELTA_0    = 5;
  parameter  int        LS_DELTA_0    = RS_DELTA_0;
  parameter  int        LS_DELTA_1    = S - RS_DELTA_0;
  parameter  int        RS_DELTA_1    = LS_DELTA_1;
  parameter  mod_reduct_type_e     REDUCT_TYPE   = MOD_REDUCT_SOLINAS3;
  parameter  mod_mult_type_e       MOD_MULT_TYPE = MOD_MULT_SOLINAS3;
  parameter  arith_mult_type_e     MULT_TYPE     = MULT_KARATSUBA;
  parameter  int        OUT_PSI_DIV   = 1;
  parameter  int        RAM_LATENCY   = 2;
  parameter  bit        NTW_IN_PIPE   = 1'b1;
  parameter  int        S_INIT_0      = S - RS_DELTA_0;
  parameter  int        S_INIT_1      = S;
  parameter  int        S_DEC_0       = 0;
  parameter  int        S_DEC_1       = 0;
  parameter  bit        SEND_TO_SEQ   = 1'b0;
  parameter  int        TOKEN_W       = 16;
  parameter  int        LPB_NB        = 1;

  parameter  bit        RS_OUT_WITH_NTW_0 = 1'b1;
  parameter  bit        LS_OUT_WITH_NTW_0 = 1'b1;
  parameter  bit        RS_OUT_WITH_NTW_1 = 1'b0;
  parameter  bit        LS_OUT_WITH_NTW_1 = 1'b0;
  parameter  int        SIMU_BATCH_NB = 20;

  localparam int        OUT_PSI       = PSI / OUT_PSI_DIV;
  localparam int        IN_PIPE       = 1'b0;

  // ============================================================================================ //
  // localparam
  // ============================================================================================ //
  `NTT_CORE_LOCALPARAM(R,S,PSI)

  // system
  localparam int CLK_HALF_PERIOD   = 1;
  localparam int ARST_ACTIVATION   = 17;

  localparam int S_W = $clog2(S);

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
  function [S-1:0][R_W-1:0] pseudo_invert(logic [S-1:0][R_W-1:0] val, int step);
    // S-2, because nb of Bu is N/R
    for (int i=0; i<S; i=i+1) begin
      pseudo_invert[i] = (i<step) ? val[S-1-i]: val[i-step];
    end
  endfunction

  function [S-1:0][R_W-1:0] inv_reverse(logic [S-1:0][R_W-1:0] val, int step);
    // S-2, because nb of Bu is N/R
    for (int i=0; i<S; i=i+1) begin
      inv_reverse[i] = (i<S-step) ? val[S-step-1-i]: val[i];
    end
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
  bit error_final_ctrl;
  bit error_final_data;


  assign error =   error_final_ctrl
                 | error_final_data;

  always_ff @(posedge clk) begin
    if (error) begin
      $display("%t > ERROR: error_final_ctrl  : %2b", $time,error_final_ctrl);
      $display("%t > ERROR: error_final_data  : %2b", $time, error_final_data);
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
  logic [PSI-1:0][R-1:0][OP_W-1:0]            clbu0_out_ls_z;
  logic                                       clbu0_out_ls_sob;
  logic                                       clbu0_out_ls_eob;
  logic                                       clbu0_out_ls_sol;
  logic                                       clbu0_out_ls_eol;
  logic                                       clbu0_out_ls_sos;
  logic                                       clbu0_out_ls_eos;
  logic [BPBS_ID_W-1:0]                        clbu0_out_ls_pbs_id;
  logic [PSI-1:0]                             clbu0_out_ls_avail;

  logic [PSI-1:0][R-1:0][OP_W-1:0]            clbu0_out_rs_z;
  logic                                       clbu0_out_rs_sob;
  logic                                       clbu0_out_rs_eob;
  logic                                       clbu0_out_rs_sol;
  logic                                       clbu0_out_rs_eol;
  logic                                       clbu0_out_rs_sos;
  logic                                       clbu0_out_rs_eos;
  logic [BPBS_ID_W-1:0]                        clbu0_out_rs_pbs_id;
  logic [PSI-1:0]                             clbu0_out_rs_avail;

  // Twiddles
  logic [1:0][R/2-1:0][OP_W-1:0]              twd_omg_ru_r_pow; // [0] NTT, [1] INTT
  // [i] = omg_ru_r ** i
  logic [RS_DELTA_0-1:0][PSI-1:0][R-1:1][OP_W-1:0] twd0_phi_ru;
  logic [RS_DELTA_0-1:0][PSI-1:0]                  twd0_phi_ru_vld;
  logic [RS_DELTA_0-1:0][PSI-1:0]                  twd0_phi_ru_rdy;
  // Error
  logic                                       error_twd0_phi;

  // logic data to sequencer
  logic [OUT_PSI-1:0][R-1:0][OP_W-1:0] ntw0_seq_data;
  logic [OUT_PSI-1:0][R-1:0]           ntw0_seq_data_avail;
  logic                                ntw0_seq_sob;
  logic                                ntw0_seq_eob;
  logic                                ntw0_seq_sol;
  logic                                ntw0_seq_eol;
  logic                                ntw0_seq_sos;
  logic                                ntw0_seq_eos;
  logic                 [BPBS_ID_W-1:0] ntw0_seq_pbs_id;
  logic                                ntw0_seq_ctrl_avail;

  // logic data to the accumulator
  logic [OUT_PSI-1:0][R-1:0][OP_W-1:0] ntw0_acc_data;
  logic [OUT_PSI-1:0][R-1:0]           ntw0_acc_data_avail;
  logic                                ntw0_acc_sob;
  logic                                ntw0_acc_eob;
  logic                                ntw0_acc_sol;
  logic                                ntw0_acc_eol;
  logic                                ntw0_acc_sog;
  logic                                ntw0_acc_eog;
  logic                 [BPBS_ID_W-1:0] ntw0_acc_pbs_id;
  logic                                ntw0_acc_ctrl_avail;

  // Output data : in pseudo-reverse(R;S,DELTA) order
  logic [PSI-1:0][R-1:0][OP_W-1:0]            clbu1_out_ls_z;
  logic                                       clbu1_out_ls_sob;
  logic                                       clbu1_out_ls_eob;
  logic                                       clbu1_out_ls_sol;
  logic                                       clbu1_out_ls_eol;
  logic                                       clbu1_out_ls_sos;
  logic                                       clbu1_out_ls_eos;
  logic [BPBS_ID_W-1:0]                        clbu1_out_ls_pbs_id;
  logic [PSI-1:0]                             clbu1_out_ls_avail;

  logic [PSI-1:0][R-1:0][OP_W-1:0]            clbu1_out_rs_z;
  logic                                       clbu1_out_rs_sob;
  logic                                       clbu1_out_rs_eob;
  logic                                       clbu1_out_rs_sol;
  logic                                       clbu1_out_rs_eol;
  logic                                       clbu1_out_rs_sos;
  logic                                       clbu1_out_rs_eos;
  logic [BPBS_ID_W-1:0]                        clbu1_out_rs_pbs_id;
  logic [PSI-1:0]                             clbu1_out_rs_avail;

  // [i] = omg_ru_r ** i
  logic [LS_DELTA_1-1:0][PSI-1:0][R-1:1][OP_W-1:0] twd1_phi_ru;
  logic [LS_DELTA_1-1:0][PSI-1:0]                  twd1_phi_ru_vld;
  logic [LS_DELTA_1-1:0][PSI-1:0]                  twd1_phi_ru_rdy;
  // Error
  logic                                       error_twd1_phi;


  // logic data to sequencer
  logic [OUT_PSI-1:0][R-1:0][OP_W-1:0] ntw1_seq_data;
  logic [OUT_PSI-1:0][R-1:0]           ntw1_seq_data_avail;
  logic                                ntw1_seq_sob;
  logic                                ntw1_seq_eob;
  logic                                ntw1_seq_sol;
  logic                                ntw1_seq_eol;
  logic                                ntw1_seq_sos;
  logic                                ntw1_seq_eos;
  logic                 [BPBS_ID_W-1:0] ntw1_seq_pbs_id;
  logic                                ntw1_seq_ctrl_avail;

  // logic data to the accumulator
  logic [OUT_PSI-1:0][R-1:0][OP_W-1:0] ntw1_acc_data;
  logic [OUT_PSI-1:0][R-1:0]           ntw1_acc_data_avail;
  logic                                ntw1_acc_sob;
  logic                                ntw1_acc_eob;
  logic                                ntw1_acc_sol;
  logic                                ntw1_acc_eol;
  logic                                ntw1_acc_sog;
  logic                                ntw1_acc_eog;
  logic                 [BPBS_ID_W-1:0] ntw1_acc_pbs_id;
  logic                                ntw1_acc_ctrl_avail;

  logic                                ntw0_seq_ntt_bwd;

  always_ff @(posedge clk)
    if (!s_rst_n) ntw0_seq_ntt_bwd <= 1'b0;
    else          ntw0_seq_ntt_bwd <= (ntw1_seq_ctrl_avail && ntw1_seq_eob) ? ~ntw0_seq_ntt_bwd : ntw0_seq_ntt_bwd;
  // ============================================================================================ //
  // Design under test instance
  // ============================================================================================ //
  // Only 1 LPB : use LS output
  ntt_core_wmm_clbu_pcg
  #(
    .OP_W          (OP_W),
    .MOD_NTT       (MOD_NTT),
    .R             (R),
    .PSI           (PSI),
    .S             (S),
    .RS_DELTA      (RS_DELTA_0),
    .LS_DELTA      (LS_DELTA_0),
    .RS_OUT_WITH_NTW (RS_OUT_WITH_NTW_0),
    .LS_OUT_WITH_NTW (LS_OUT_WITH_NTW_0),
    .LPB_NB        (LPB_NB),
    .REDUCT_TYPE   (REDUCT_TYPE),
    .MOD_MULT_TYPE (MOD_MULT_TYPE),
    .MULT_TYPE     (MULT_TYPE)

  ) ntt_core_wmm_clbu_pcg_0 (
    .clk            (clk),
    .s_rst_n        (s_rst_n),

    .in_a           (in_a),
    .in_ntt_bwd     (in_ntt_bwd),
    .in_sob         (in_sob),
    .in_eob         (in_eob),
    .in_sol         (in_sol),
    .in_eol         (in_eol),
    .in_sos         (in_sos),
    .in_eos         (in_eos),
    .in_pbs_id      (in_pbs_id),
    .in_avail       (in_avail),

    .ls_z           (clbu0_out_ls_z),
    .ls_sob         (clbu0_out_ls_sob),
    .ls_eob         (clbu0_out_ls_eob),
    .ls_sol         (clbu0_out_ls_sol),
    .ls_eol         (clbu0_out_ls_eol),
    .ls_sos         (clbu0_out_ls_sos),
    .ls_eos         (clbu0_out_ls_eos),
    .ls_pbs_id      (clbu0_out_ls_pbs_id),
    .ls_ntt_bwd     (/*UNUSED*/),
    .ls_avail       (clbu0_out_ls_avail),

    .rs_z           (clbu0_out_rs_z),
    .rs_sob         (clbu0_out_rs_sob),
    .rs_eob         (clbu0_out_rs_eob),
    .rs_sol         (clbu0_out_rs_sol),
    .rs_eol         (clbu0_out_rs_eol),
    .rs_sos         (clbu0_out_rs_sos),
    .rs_eos         (clbu0_out_rs_eos),
    .rs_pbs_id      (clbu0_out_rs_pbs_id),
    .rs_ntt_bwd     (/*UNUSED*/),
    .rs_avail       (clbu0_out_rs_avail),

    .twd_omg_ru_r_pow(twd_omg_ru_r_pow),

    .twd_phi_ru      (twd0_phi_ru),
    .twd_phi_ru_vld  (twd0_phi_ru_vld),
    .twd_phi_ru_rdy  (twd0_phi_ru_rdy),

    .error_twd_phi   (error_twd0_phi)
  );

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      assert(clbu0_out_rs_avail == '0)
      else begin
        $fatal(1,"%t > ERROR: CLBU_0 RS path avail is not null.", $time);
      end
    end

  ntt_core_wmm_network_pcg
  #(
    .OP_W         (OP_W),
    .R            (R),
    .PSI          (PSI),
    .S            (S),
    .RAM_LATENCY  (RAM_LATENCY),
    .IN_PIPE      (IN_PIPE),
    .S_INIT       (S_INIT_0),
    .S_DEC        (S_DEC_0),
    .SEND_TO_SEQ  (1'b0),
    .TOKEN_W      (TOKEN_W),
    .OUT_PSI_DIV  (OUT_PSI_DIV),
    .RS_DELTA     (RS_DELTA_0),
    .LS_DELTA     (LS_DELTA_0),
    .LPB_NB       (LPB_NB),
    .RS_OUT_WITH_NTW (RS_OUT_WITH_NTW_0),
    .LS_OUT_WITH_NTW (LS_OUT_WITH_NTW_0),
    .USE_RS       (1'b1),
    .USE_LS       (1'b0)
  ) ntt_core_wmm_network_pcg_0 (
    .clk (clk),     // clock
    .s_rst_n (s_rst_n), // synchronous reset

    // Input read enable from sequencer
    .seq_ntw_rden (1'b0),

    // Input data from post-process
    .pp_rsntw_data   (clbu0_out_ls_z),
    .pp_rsntw_sob    (clbu0_out_ls_sob),
    .pp_rsntw_eob    (clbu0_out_ls_eob),
    .pp_rsntw_sol    (clbu0_out_ls_sol),
    .pp_rsntw_eol    (clbu0_out_ls_eol),
    .pp_rsntw_sos    (clbu0_out_ls_sos),
    .pp_rsntw_eos    (clbu0_out_ls_eos),
    .pp_rsntw_pbs_id (clbu0_out_ls_pbs_id),
    .pp_rsntw_avail  (clbu0_out_ls_avail[0]),

    // Input data from post-process for last stage
    .pp_lsntw_data   (),
    .pp_lsntw_sob    (),
    .pp_lsntw_eob    (),
    .pp_lsntw_sol    (),
    .pp_lsntw_eol    (),
    .pp_lsntw_sos    (),
    .pp_lsntw_eos    (),
    .pp_lsntw_pbs_id (),
    .pp_lsntw_avail  ('0),

    // output data to sequencer
    .ntw_seq_data       (ntw0_seq_data),
    .ntw_seq_data_avail (ntw0_seq_data_avail),
    .ntw_seq_sob        (ntw0_seq_sob),
    .ntw_seq_eob        (ntw0_seq_eob),
    .ntw_seq_sol        (ntw0_seq_sol),
    .ntw_seq_eol        (ntw0_seq_eol),
    .ntw_seq_sos        (ntw0_seq_sos),
    .ntw_seq_eos        (ntw0_seq_eos),
    .ntw_seq_pbs_id     (ntw0_seq_pbs_id),
    .ntw_seq_ctrl_avail (ntw0_seq_ctrl_avail),

    // output data to the accumulator
    .ntw_acc_data       (ntw0_acc_data),
    .ntw_acc_data_avail (ntw0_acc_data_avail),
    .ntw_acc_sob        (ntw0_acc_sob),
    .ntw_acc_eob        (ntw0_acc_eob),
    .ntw_acc_sol        (ntw0_acc_sol),
    .ntw_acc_eol        (ntw0_acc_eol),
    .ntw_acc_sog        (ntw0_acc_sog),
    .ntw_acc_eog        (ntw0_acc_eog),
    .ntw_acc_pbs_id     (ntw0_acc_pbs_id),
    .ntw_acc_ctrl_avail (ntw0_acc_ctrl_avail)

  );

  ntt_core_wmm_clbu_pcg
  #(
    .OP_W          (OP_W),
    .MOD_NTT       (MOD_NTT),
    .R             (R),
    .PSI           (PSI),
    .S             (S),
    .RS_DELTA      (RS_DELTA_1),
    .LS_DELTA      (LS_DELTA_1),
    .RS_OUT_WITH_NTW (RS_OUT_WITH_NTW_1),
    .LS_OUT_WITH_NTW (LS_OUT_WITH_NTW_1),
    .LPB_NB        (LPB_NB),
    .REDUCT_TYPE   (REDUCT_TYPE),
    .MOD_MULT_TYPE (MOD_MULT_TYPE),
    .MULT_TYPE     (MULT_TYPE)

  ) ntt_core_wmm_clbu_pcg_1 (
    .clk             (clk),
    .s_rst_n         (s_rst_n),

    .in_a            (ntw0_seq_data),
    .in_ntt_bwd      ({PSI{ntw0_seq_ntt_bwd}}),
    .in_sob          (ntw0_seq_sob),
    .in_eob          (ntw0_seq_eob),
    .in_sol          (ntw0_seq_sol),
    .in_eol          (ntw0_seq_eol),
    .in_sos          (ntw0_seq_sos),
    .in_eos          (ntw0_seq_eos),
    .in_pbs_id       (ntw0_seq_pbs_id),
    .in_avail        ({PSI{ntw0_seq_ctrl_avail}}),

    .ls_z           (clbu1_out_ls_z),
    .ls_sob         (clbu1_out_ls_sob),
    .ls_eob         (clbu1_out_ls_eob),
    .ls_sol         (clbu1_out_ls_sol),
    .ls_eol         (clbu1_out_ls_eol),
    .ls_sos         (clbu1_out_ls_sos),
    .ls_eos         (clbu1_out_ls_eos),
    .ls_pbs_id      (clbu1_out_ls_pbs_id),
    .ls_ntt_bwd     (/*UNUSED*/),
    .ls_avail       (clbu1_out_ls_avail),

    .rs_z           (clbu1_out_rs_z),
    .rs_sob         (clbu1_out_rs_sob),
    .rs_eob         (clbu1_out_rs_eob),
    .rs_sol         (clbu1_out_rs_sol),
    .rs_eol         (clbu1_out_rs_eol),
    .rs_sos         (clbu1_out_rs_sos),
    .rs_eos         (clbu1_out_rs_eos),
    .rs_pbs_id      (clbu1_out_rs_pbs_id),
    .rs_ntt_bwd     (/*UNUSED*/),
    .rs_avail       (clbu1_out_rs_avail),

    .twd_omg_ru_r_pow(twd_omg_ru_r_pow),

    .twd_phi_ru      (),
    .twd_phi_ru_vld  (),
    .twd_phi_ru_rdy  (),

    .error_twd_phi   ()
  );

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      assert(clbu1_out_rs_avail == '0)
      else begin
        $fatal(1,"%t > ERROR: CLBU_1 RS path avail is not null.", $time);
      end
    end

  ntt_core_wmm_network_pcg
  #(
    .OP_W         (OP_W),
    .R            (R),
    .PSI          (PSI),
    .S            (S),
    .RAM_LATENCY  (RAM_LATENCY),
    .IN_PIPE      (IN_PIPE),
    .S_INIT       (S_INIT_1),
    .S_DEC        (S_DEC_1),
    .SEND_TO_SEQ  (1'b0),
    .TOKEN_W      (TOKEN_W),
    .OUT_PSI_DIV  (OUT_PSI_DIV),
    .RS_DELTA     (RS_DELTA_1),
    .LS_DELTA     (LS_DELTA_1),
    .LPB_NB        (LPB_NB),
    .RS_OUT_WITH_NTW (RS_OUT_WITH_NTW_1),
    .LS_OUT_WITH_NTW (LS_OUT_WITH_NTW_1),
    .USE_RS       (1'b0),
    .USE_LS       (1'b1)
  ) ntt_core_wmm_network_pcg_1 (
    .clk (clk),     // clock
    .s_rst_n (s_rst_n), // synchronous reset

    // Input read enable from sequencer
    .seq_ntw_rden (1'b0),

    // Input data from post-process
    .pp_rsntw_data   (clbu1_out_rs_z),
    .pp_rsntw_sob    (clbu1_out_rs_sob),
    .pp_rsntw_eob    (clbu1_out_rs_eob),
    .pp_rsntw_sol    (clbu1_out_rs_sol),
    .pp_rsntw_eol    (clbu1_out_rs_eol),
    .pp_rsntw_sos    (clbu1_out_rs_sos),
    .pp_rsntw_eos    (clbu1_out_rs_eos),
    .pp_rsntw_pbs_id (clbu1_out_rs_pbs_id),
    .pp_rsntw_avail  (clbu1_out_rs_avail[0]),

    // Input data from post-process for last stage
    .pp_lsntw_data   (clbu1_out_ls_z),
    .pp_lsntw_sob    (clbu1_out_ls_sob),
    .pp_lsntw_eob    (clbu1_out_ls_eob),
    .pp_lsntw_sol    (clbu1_out_ls_sol),
    .pp_lsntw_eol    (clbu1_out_ls_eol),
    .pp_lsntw_sos    (clbu1_out_ls_sos),
    .pp_lsntw_eos    (clbu1_out_ls_eos),
    .pp_lsntw_pbs_id (clbu1_out_ls_pbs_id),
    .pp_lsntw_avail  (clbu1_out_ls_avail[0]),

    // output data to sequencer
    .ntw_seq_data       (ntw1_seq_data),
    .ntw_seq_data_avail (ntw1_seq_data_avail),
    .ntw_seq_sob        (ntw1_seq_sob),
    .ntw_seq_eob        (ntw1_seq_eob),
    .ntw_seq_sol        (ntw1_seq_sol),
    .ntw_seq_eol        (ntw1_seq_eol),
    .ntw_seq_sos        (ntw1_seq_sos),
    .ntw_seq_eos        (ntw1_seq_eos),
    .ntw_seq_pbs_id     (ntw1_seq_pbs_id),
    .ntw_seq_ctrl_avail (ntw1_seq_ctrl_avail),

    // output data to the accumulator
    .ntw_acc_data       (ntw1_acc_data),
    .ntw_acc_data_avail (ntw1_acc_data_avail),
    .ntw_acc_sob        (ntw1_acc_sob),
    .ntw_acc_eob        (ntw1_acc_eob),
    .ntw_acc_sol        (ntw1_acc_sol),
    .ntw_acc_eol        (ntw1_acc_eol),
    .ntw_acc_sog        (ntw1_acc_sog),
    .ntw_acc_eog        (ntw1_acc_eog),
    .ntw_acc_pbs_id     (ntw1_acc_pbs_id),
    .ntw_acc_ctrl_avail (ntw1_acc_ctrl_avail)

  );

  // ============================================================================================ //
  // Stimuli
  // ============================================================================================ //
  logic s0_avail;

  integer s0_lvl_id;
  integer s0_stg_iter;
  integer s0_stg;
  integer s0_pbs_id;
  logic   s0_ntt_bwd;
  integer s0_batch_cnt;
  integer s0_loop_cnt;

  integer s0_lvl_idD;
  integer s0_stg_iterD;
  //integer s0_stgD;
  integer s0_pbs_idD;
  logic   s0_ntt_bwdD;
  integer s0_batch_cntD;
  integer s0_loop_cntD;

  integer s0_lvl_id_max;
  logic s0_first_lvl_id;
  logic s0_last_lvl_id;
  logic s0_first_stg_iter;
  logic s0_last_stg_iter;
  //logic s0_first_stg;
  //logic s0_last_stg;
  logic s0_first_pbs_id;
  logic s0_last_pbs_id;
  logic s0_last_batch_cnt;
  logic s0_last_loop;

  assign s0_lvl_id_max     = s0_ntt_bwd ? GLWE_K_P1-1: INTL_L-1;
  assign s0_first_lvl_id   = s0_lvl_id == 0;
  assign s0_last_lvl_id    = s0_lvl_id == s0_lvl_id_max;
  assign s0_first_stg_iter = s0_stg_iter == 0;
  assign s0_last_stg_iter  = s0_stg_iter == (STG_ITER_NB-1);
  //assign s0_first_stg      = s0_stg == (S-1);
  //assign s0_last_stg       = s0_stg == 0;
  assign s0_first_pbs_id   = s0_pbs_id == 0;
  assign s0_last_pbs_id    = s0_pbs_id == (BATCH_PBS_NB-1);
  assign s0_last_batch_cnt = s0_batch_cnt == (SIMU_BATCH_NB-1);
  assign s0_last_loop      = s0_loop_cnt == (LPB_NB-1);

  assign s0_lvl_idD    = s0_avail ? s0_last_lvl_id ? '0 : s0_lvl_id + 1: s0_lvl_id;
  assign s0_stg_iterD  = (s0_avail && s0_last_lvl_id) ? s0_last_stg_iter ? '0 : s0_stg_iter + 1 : s0_stg_iter;
  assign s0_pbs_idD    = (s0_avail && s0_last_lvl_id && s0_last_stg_iter) ? s0_last_pbs_id ? 0 : s0_pbs_id + 1 : s0_pbs_id;
  assign s0_loop_cntD  = (s0_avail && s0_last_lvl_id && s0_last_stg_iter && s0_last_pbs_id) ? s0_last_loop ? 0 : s0_loop_cnt+1 : s0_loop_cnt;
  assign s0_ntt_bwdD   = (s0_avail && s0_last_lvl_id && s0_last_stg_iter && s0_last_pbs_id && s0_last_loop) ? ~s0_ntt_bwd : s0_ntt_bwd;
  assign s0_batch_cntD = (s0_avail && s0_last_lvl_id && s0_last_stg_iter && s0_last_pbs_id && s0_last_loop && s0_ntt_bwd) ? s0_batch_cnt + 1 : s0_batch_cnt;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      s0_lvl_id    <= '0;
      s0_stg_iter  <= '0;
      s0_loop_cnt  <= '0;
      s0_pbs_id    <= '0;
      s0_ntt_bwd   <= 1'b0;
      s0_batch_cnt <= '0;
    end
    else begin
      s0_lvl_id   <= s0_lvl_idD  ;
      s0_stg_iter <= s0_stg_iterD;
      s0_loop_cnt <= s0_loop_cntD;
      s0_pbs_id   <= s0_pbs_idD  ;
      s0_ntt_bwd  <= s0_ntt_bwdD ;
      s0_batch_cnt <= s0_batch_cntD;
    end

  assign s0_stg = S-1 - s0_loop_cnt * RS_DELTA_0;

  assign in_sol    = s0_first_lvl_id;
  assign in_eol    = s0_last_lvl_id;
  assign in_sos    = in_sol & s0_first_stg_iter;
  assign in_eos    = in_eol & s0_last_stg_iter;
  assign in_sob    = in_sos & s0_first_pbs_id;
  assign in_eob    = in_eos & s0_last_pbs_id;
  assign in_ntt_bwd = s0_ntt_bwd;
  assign in_pbs_id  = s0_pbs_id;

  logic s0_avail_tmp;
  assign s0_avail = s0_avail_tmp & (s0_batch_cnt < SIMU_BATCH_NB);

  assign in_avail = {PSI{s0_avail}};

  always_ff @(posedge clk)
    if (!s_rst_n) s0_avail_tmp <= 1'b0;
    else          s0_avail_tmp <= $urandom;

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
  // Check final output
  // ============================================================================================ //
  integer ref_batch_cnt;

  integer final_lvl_id;
  integer final_stg_iter;
  integer final_stg;
  integer final_pbs_id;
  logic   final_ntt_bwd;
  integer final_batch_cnt;
  integer final_loop_cnt;

  integer final_lvl_idD;
  integer final_stg_iterD;
  integer final_pbs_idD;
  logic   final_ntt_bwdD;
  integer final_batch_cntD;
  integer final_loop_cntD;

  integer final_lvl_id_max;
  logic final_first_lvl_id;
  logic final_last_lvl_id;
  //logic final_first_stg_iter;
  //logic final_last_stg_iter;
  logic final_first_stg;
  logic final_last_stg;
  logic final_first_pbs_id;
  logic final_last_pbs_id;
  logic final_last_batch_cnt;
  logic final_last_loop;

  assign final_lvl_id_max     = final_ntt_bwd ? GLWE_K_P1-1: INTL_L-1;
  assign final_first_lvl_id   = final_lvl_id == 0;
  assign final_last_lvl_id    = final_lvl_id == final_lvl_id_max;
  assign final_first_stg_iter = final_stg_iter == 0;
  assign final_last_stg_iter  = final_stg_iter == (STG_ITER_NB-1);
  //assign final_first_stg      = final_stg == (S-1);
  //assign final_last_stg       = final_stg == 0;
  assign final_first_pbs_id   = final_pbs_id == 0;
  assign final_last_pbs_id    = final_pbs_id == (BATCH_PBS_NB-1);
  assign final_last_batch_cnt = final_batch_cnt == (SIMU_BATCH_NB-1);
  assign final_last_loop      = final_loop_cnt == (LPB_NB-1);

  assign final_lvl_idD    = ntw1_acc_ctrl_avail ? final_last_lvl_id ? '0 : final_lvl_id + 1: final_lvl_id;
  assign final_stg_iterD  = (ntw1_acc_ctrl_avail && final_last_lvl_id) ? final_last_stg_iter ? '0 : final_stg_iter + 1 : final_stg_iter;
  assign final_pbs_idD    = (ntw1_acc_ctrl_avail && final_last_lvl_id && final_last_stg_iter) ? final_last_pbs_id ? 0 : final_pbs_id + 1 : final_pbs_id;
  assign final_loop_cntD  = (ntw1_acc_ctrl_avail && final_last_lvl_id && final_last_stg_iter && final_last_pbs_id) ? final_last_loop ? '0 : final_loop_cnt + 1 : final_loop_cnt;
  assign final_ntt_bwdD   = (ntw1_acc_ctrl_avail && final_last_lvl_id && final_last_stg_iter && final_last_pbs_id && final_last_loop) ? ~final_ntt_bwd : final_ntt_bwd;
  assign final_batch_cntD = (ntw1_acc_ctrl_avail && final_last_lvl_id && final_last_stg_iter && final_last_pbs_id && final_last_loop && final_ntt_bwd) ? final_batch_cnt + 1 : final_batch_cnt;

  assign ref_batch_cnt = final_batch_cnt;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      final_lvl_id   <= '0;
      final_stg_iter <= '0;
      final_loop_cnt <= '0;
      final_pbs_id   <= '0;
      final_ntt_bwd  <= 1'b0;
      final_batch_cnt <= '0;
    end
    else begin
      final_lvl_id   <= final_lvl_idD  ;
      final_stg_iter <= final_stg_iterD;
      final_loop_cnt <= final_loop_cntD;
      final_pbs_id   <= final_pbs_idD  ;
      final_ntt_bwd  <= final_ntt_bwdD ;
      final_batch_cnt <= final_batch_cntD;
    end

  assign final_stg    = S-1 - final_loop_cnt * (RS_DELTA_0 + LS_DELTA_1);

  assign final_sol    = final_first_lvl_id;
  assign final_eol    = final_last_lvl_id;
  assign final_sos    = final_sol & final_first_stg_iter;
  assign final_eos    = final_eol & final_last_stg_iter;
  assign final_sob    = final_sos & final_first_pbs_id;
  assign final_eob    = final_eos & final_last_pbs_id;

  logic [PSI-1:0][R-1:0][OP_W-1:0] final_z;
  logic error_ctrl;
  logic error_data;

  assign error_final_ctrl = error_ctrl;
  assign error_final_data = error_data;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      error_ctrl <= 1'b0;
      error_data <= 1'b0;
    end
    else begin
      if (ntw1_acc_ctrl_avail) begin
        assert((ntw1_acc_sol == final_sol)
                && (ntw1_acc_eol == final_eol)
                && (ntw1_acc_sog == final_sos)
                && (ntw1_acc_eog == final_eos)
                && (ntw1_acc_sob == final_sob)
                && (ntw1_acc_eob == final_eob)
                && (ntw1_acc_pbs_id == final_pbs_id)
                )
        else begin
          $display("%t > ERROR: control mismatch.", $time);
          $display("%t > sol exp=%0d seen=%0d", $time, final_sol, ntw1_acc_sol);
          $display("%t > eol exp=%0d seen=%0d", $time, final_eol, ntw1_acc_eol);
          $display("%t > sos exp=%0d seen=%0d", $time, final_sos, ntw1_acc_sog);
          $display("%t > eos exp=%0d seen=%0d", $time, final_eos, ntw1_acc_eog);
          $display("%t > sob exp=%0d seen=%0d", $time, final_sob, ntw1_acc_sob);
          $display("%t > eob exp=%0d seen=%0d", $time, final_eob, ntw1_acc_eob);
          $display("%t > pbs_id exp=%0d seen=%0d", $time, final_pbs_id, ntw1_acc_pbs_id);
          error_ctrl <= 1'b1;
        end


        for (int p=0; p<PSI; p=p+1) begin
          for (int r=0; r<R; r=r+1) begin
            logic [S*R_W-1:0] v_tmp;
            logic [S-1:0][R_W-1:0] v;
            logic [S-1:0][R_W-1:0] v_rev;
            data_t d;
            v_tmp = final_stg_iter * R * PSI + p*R + r;
            v = v_tmp;
            //for (int s=0; s<S; s=s+1)
            //  v_rev[s] = v[S-1-s];

            //d.coef     = v_rev;
            d.coef     = v;
            d.stg      = final_stg;
            d.ntt_bwd  = final_ntt_bwd;
            d.lvl_id   = final_lvl_id;
            d.pbs_id   = final_pbs_id;
            final_z[p][r] = d;

            assert(ntw1_acc_data[p][r] == final_z[p][r])
            else begin
              $display("%t > ERROR: Final data mismatch (p=%0d, r=%0d, stg_iter=%0d) exp=0x%0x seen=0x%0x.",$time, p,r,final_stg_iter,final_z[p][r], ntw1_acc_data[p][r]);
              error_data <= 1'b1;
            end

          end
        end

      end
    end


  // ============================================================================================ //
  // End of test
  // ============================================================================================ //
  assign end_of_test = (s0_batch_cnt == SIMU_BATCH_NB) && (ref_batch_cnt == SIMU_BATCH_NB);

  integer ref_batch_cnt_dly;

  always_ff @(posedge clk)
    ref_batch_cnt_dly <= ref_batch_cnt;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      if ((ref_batch_cnt!=ref_batch_cnt_dly) && ref_batch_cnt%10 == 0)
       $display("%t > INFO: ref_batch_cnt #%0d / %0d", $time, ref_batch_cnt, SIMU_BATCH_NB);
    end
endmodule
