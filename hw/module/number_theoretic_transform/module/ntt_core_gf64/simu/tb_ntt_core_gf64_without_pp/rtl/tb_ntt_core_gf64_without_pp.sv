// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Testbench to check the NTT and INTT.
// The post_process is not instantiated here.
//
// We use different split of ntt_core_gf64.
// The DUTs will do an NTT followed by an INTT
// The testbench is mainly a sanity check.
// The output should be equal to the input.
//
// ==============================================================================================

module tb_ntt_core_gf64_without_pp;

`timescale 1ns/10ps

  import pep_common_param_pkg::*;
  import common_definition_pkg::*;
  import param_ntt_pkg::*;
  import param_tfhe_pkg::*;
  import ntt_core_common_param_pkg::*;
  import ntt_core_gf64_common_param_pkg::*;

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int CLK_HALF_PERIOD = 1;
  localparam int ARST_ACTIVATION = 17;

  localparam int ERROR_W = 1;

  parameter int SPLIT_NB                   = 4; // Split NTT and INTT into 2
  parameter [SPLIT_NB-1:0][31:0]  S_NB_L   = {S-3*(S/2),S/2,S/2,S/2};
  localparam [SPLIT_NB-1:0][31:0] S_INIT_L = get_s_init();

  parameter  arith_mult_type_e PHI_MULT_TYPE = MULT_CORE; // PHI multiplier, when needed
  parameter  arith_mult_type_e PP_MULT_TYPE  = MULT_CORE; // Multiplier used in PP

  localparam int RAM_LATENCY = 2;
  localparam int ROM_LATENCY = 2;

  localparam string TWD_GF64_FILE_PREFIX = "input/twd_phi";

  localparam int SAMPLE_BATCH_NB = 25;

  localparam bit USE_PP = 1'b0; // Support only this

  generate
    if (USE_PP != 0) begin : __UNSUPPORTED_USE_PP
      $fatal(1,"> ERROR: This testbench does not support the post_process.");
    end
    if (PBS_L > 1 && USE_PP == 0) begin : __UNSUPPORTED_PBS_L
      $fatal(1, "> ERROR: This testbench does not implement the post_process. Therefore, it does not support PBS_L > 1.");
    end
    if (!check_s_nb_l()) begin : __UNSUPPORTED_SPLIT
      $fatal(1,"> ERROR: the sum of the splits should be equal to 2*S (%0d)",2*S);
    end
  endgenerate

// ============================================================================================== --
// function
// ============================================================================================== --
  function [SPLIT_NB-1:0][31:0] get_s_init();
    var [SPLIT_NB-1:0][31:0] pos;
    pos[0] = 0;
    for (int i=1; i<SPLIT_NB; i=i+1)
      pos[i] = pos[i-1] + S_NB_L[i-1];
    for (int i=0; i<SPLIT_NB; i=i+1)
      get_s_init[i] = pos[i] < S ? S-1 - pos[i] : 3*S-1 - pos[i];
  endfunction

  function logic check_s_nb_l();
    integer s_total;
    s_total = 0;
    for (int i=0; i<SPLIT_NB; i=i+1)
      s_total = s_total + S_NB_L[i];
    return s_total == 2*S;
  endfunction

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

// ============================================================================================== --
// clock, reset
// ============================================================================================== --
  bit clk;
  bit a_rst_n; // asynchronous reset
  bit s_rst_n; // synchronous reset

  initial begin
    clk     = 1'b0;
    a_rst_n = 1'b0;                   // active reset
    #ARST_ACTIVATION a_rst_n = 1'b1; // disable reset
  end

  always begin
    #CLK_HALF_PERIOD clk = ~clk;
  end

  always_ff @(posedge clk) begin
    s_rst_n <= a_rst_n;
  end

// ============================================================================================== --
// End of test
// ============================================================================================== --
  bit end_of_test;

  initial begin
    wait (end_of_test);
    @(posedge clk) $display("%t > SUCCEED !", $time);
    $finish;
  end

// ============================================================================================== --
// Error
// ============================================================================================== --
  bit error;
  bit error_data;
  bit error_ctrl;
  logic [SPLIT_NB-1:0][ERROR_W-1:0]                     ntt_error;

  assign error = error_data | error_ctrl | |ntt_error;

  always_ff @(posedge clk)
    if (error) begin
      $display("%t > FAILURE !", $time);
      $finish;
    end

// ============================================================================================== --
// input / output signals
// ============================================================================================== --
  logic [PSI-1:0][R-1:0][MOD_NTT_W-1:0]                 in_data;
  logic [PSI-1:0][R-1:0]                                in_avail;
  ctrl_t                                                in_ctrl;

  logic [PSI-1:0][R-1:0][MOD_NTT_W+1:0]                 out_data;
  logic [PSI-1:0][R-1:0]                                out_avail;
  ctrl_t                                                out_ctrl;

  logic [SPLIT_NB:0][PSI-1:0][R-1:0][MOD_NTT_W+1:0]     ntt_data;
  logic [SPLIT_NB:0][PSI-1:0][R-1:0]                    ntt_avail;
  ctrl_t [SPLIT_NB:0]                                   ntt_ctrl;

  // Matrix factors : BSK
  // Not used here
  /*
  logic  [PSI-1:0][R-1:0][GLWE_K_P1-1:0][MOD_NTT_W-1:0] bsk;
  logic  [PSI-1:0][R-1:0][GLWE_K_P1-1:0]                bsk_vld;
  logic [PSI-1:0][R-1:0][GLWE_K_P1-1:0]                 bsk_rdy;
  */

// ============================================================================================== --
// Design under test instance
// ============================================================================================== --
  assign ntt_avail[0]  = in_avail;
  assign ntt_ctrl[0]   = in_ctrl;

  assign out_data      = ntt_data[SPLIT_NB];
  assign out_avail     = ntt_avail[SPLIT_NB];
  assign out_ctrl      = ntt_ctrl[SPLIT_NB];

  always_comb
    for (int p=0; p<PSI; p=p+1)
      for (int r=0; r<R; r=r+1)
        ntt_data[0][p][r] = {2'b00,in_data[p][r]}; // extend

  generate
    for (genvar gen_i=0; gen_i<SPLIT_NB; gen_i=gen_i+1) begin : gen_loop

      if (S_NB_L[gen_i] > 0) begin : gen_inst
        ntt_core_gf64_middle
        #(
          .S_INIT           (S_INIT_L[gen_i]),
          .S_NB             (S_NB_L[gen_i]),
          .USE_PP           (1'b0), // Not tested here
          .PHI_MULT_TYPE    (PHI_MULT_TYPE),
          .PP_MULT_TYPE     (PP_MULT_TYPE),
          .RAM_LATENCY      (RAM_LATENCY),
          .ROM_LATENCY      (ROM_LATENCY),
          .IN_PIPE          (gen_i==0),
          .TWD_GF64_FILE_PREFIX (TWD_GF64_FILE_PREFIX)
        ) ntt_core_gf64_middle (
          .clk         (clk),
          .s_rst_n     (s_rst_n),

          .prev_data   (ntt_data[gen_i]),
          .prev_avail  (ntt_avail[gen_i]),
          .prev_sob    (ntt_ctrl[gen_i].sob),
          .prev_eob    (ntt_ctrl[gen_i].eob),
          .prev_sol    (ntt_ctrl[gen_i].sol),
          .prev_eol    (ntt_ctrl[gen_i].eol),
          .prev_sos    (ntt_ctrl[gen_i].sos),
          .prev_eos    (ntt_ctrl[gen_i].eos),
          .prev_pbs_id (ntt_ctrl[gen_i].pbs_id),

          .next_data   (ntt_data[gen_i+1]),
          .next_avail  (ntt_avail[gen_i+1]),
          .next_sob    (ntt_ctrl[gen_i+1].sob),
          .next_eob    (ntt_ctrl[gen_i+1].eob),
          .next_sol    (ntt_ctrl[gen_i+1].sol),
          .next_eol    (ntt_ctrl[gen_i+1].eol),
          .next_sos    (ntt_ctrl[gen_i+1].sos),
          .next_eos    (ntt_ctrl[gen_i+1].eos),
          .next_pbs_id (ntt_ctrl[gen_i+1].pbs_id),

          .bsk         ('x), /*UNUSED*/
          .bsk_vld     ('0), /*UNUSED*/
          .bsk_rdy     (/*UNUSED*/),

          .error       (ntt_error[gen_i])
        );
      end
      else begin : gen_no_inst
        assign ntt_data[gen_i+1]  = ntt_data[gen_i];
        assign ntt_avail[gen_i+1] = ntt_avail[gen_i];
        assign ntt_ctrl[gen_i+1]  = ntt_ctrl[gen_i];
        assign ntt_error[gen_i]   = 1'b0;
      end
    end
  endgenerate

// ============================================================================================== --
// Scenario
// ============================================================================================== --
// ---------------------------------------------------------------------------------------------- --
// Input Counters
// ---------------------------------------------------------------------------------------------- --
  integer in_pbs_nb;

  integer in_intl_idx;
  integer in_stg_iter;
  integer in_pbs_idx;

  logic   in_first_intl_idx;
  logic   in_first_stg_iter;
  logic   in_first_pbs_idx;

  logic   in_last_intl_idx;
  logic   in_last_stg_iter;
  logic   in_last_pbs_idx;

  assign in_first_intl_idx = in_intl_idx == '0;
  assign in_first_stg_iter = in_stg_iter == '0;
  assign in_first_pbs_idx  = in_pbs_idx == '0;

  assign in_last_intl_idx = in_intl_idx == INTL_L-1;
  assign in_last_stg_iter = in_stg_iter == STG_ITER_NB-1;
  assign in_last_pbs_idx  = in_pbs_idx == in_pbs_nb-1;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      in_intl_idx <= '0;
      in_stg_iter <= '0;
      in_pbs_idx  <= '0;
      in_pbs_nb   <= $urandom_range(1,8);
    end
    else begin
      in_intl_idx <= in_avail[0] ? in_last_intl_idx ? '0 : in_intl_idx + 1 : in_intl_idx;
      in_stg_iter <= in_avail[0] && in_last_intl_idx ? in_last_stg_iter ? '0 : in_stg_iter + 1 : in_stg_iter;
      in_pbs_idx  <= in_avail[0] && in_last_intl_idx && in_last_stg_iter ? in_last_pbs_idx ? '0 : in_pbs_idx + 1 : in_pbs_idx;
      in_pbs_nb   <= in_avail[0] && in_last_intl_idx && in_last_stg_iter && in_last_pbs_idx ? $urandom_range(1,8) : in_pbs_nb;
    end

  integer pbs_nb_q [$];

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // Do nothing
    end
    else begin
      if (in_avail[0] && in_first_intl_idx && in_first_stg_iter && in_first_pbs_idx)
        pbs_nb_q.push_back(in_pbs_nb);
    end

// ---------------------------------------------------------------------------------------------- --
// Output Counters
// ---------------------------------------------------------------------------------------------- --
  integer out_pbs_nb;

  integer out_intl_idx;
  integer out_stg_iter;
  integer out_pbs_idx;

  logic   out_first_intl_idx;
  logic   out_first_stg_iter;
  logic   out_first_pbs_idx;

  logic   out_last_intl_idx;
  logic   out_last_stg_iter;
  logic   out_last_pbs_idx;

  assign out_first_intl_idx = out_intl_idx == '0;
  assign out_first_stg_iter = out_stg_iter == '0;
  assign out_first_pbs_idx  = out_pbs_idx == '0;

  assign out_last_intl_idx = out_intl_idx == INTL_L-1;
  assign out_last_stg_iter = out_stg_iter == STG_ITER_NB-1;
  assign out_last_pbs_idx  = out_pbs_idx == out_pbs_nb-1;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      out_intl_idx <= '0;
      out_stg_iter <= '0;
      out_pbs_idx  <= '0;
    end
    else begin
      out_intl_idx <= out_avail[0] ? out_last_intl_idx ? '0 : out_intl_idx + 1 : out_intl_idx;
      out_stg_iter <= out_avail[0] && out_last_intl_idx ? out_last_stg_iter ? '0 : out_stg_iter + 1 : out_stg_iter;
      out_pbs_idx  <= out_avail[0] && out_last_intl_idx && out_last_stg_iter ? out_last_pbs_idx ? '0 : out_pbs_idx + 1 : out_pbs_idx;
    end

  logic init_out_pbs_nb;
  logic upd_out_pbs_nb;

  assign upd_out_pbs_nb = out_avail[0] && out_last_intl_idx && out_last_stg_iter && out_last_pbs_idx;

  always_ff@(posedge clk)
    if (!s_rst_n) init_out_pbs_nb <= 1'b1;
    else          init_out_pbs_nb <= (init_out_pbs_nb && (pbs_nb_q.size() > 0)) ? 1'b0 :
                                     (upd_out_pbs_nb  && (pbs_nb_q.size() == 0)) ? 1'b1 : init_out_pbs_nb;

  always_ff @(posedge clk)
    if (!s_rst_n)  out_pbs_nb <= '0;
    else begin
      if (init_out_pbs_nb) begin
        if (pbs_nb_q.size() > 0) begin
          integer v;
          v = pbs_nb_q.pop_front();
          out_pbs_nb <= v;
        end
      end
      else begin
        if (upd_out_pbs_nb) begin
          integer v;
          v = pbs_nb_q.pop_front();
          out_pbs_nb <= v;
        end
      end
    end

// ---------------------------------------------------------------------------------------------- --
// Input stimuli
// ---------------------------------------------------------------------------------------------- --
  logic rand_in_avail;

  always_ff @(posedge clk)
    if (!s_rst_n) rand_in_avail <= 1'b0;
    else          rand_in_avail <= $urandom_range(0,1);

  assign in_avail       = {PSI*R{rand_in_avail}};
  assign in_ctrl.sob    = in_first_intl_idx & in_first_stg_iter & in_first_pbs_idx;
  assign in_ctrl.eob    = in_last_intl_idx & in_last_stg_iter & in_last_pbs_idx;
  assign in_ctrl.sol    = in_first_intl_idx;
  assign in_ctrl.eol    = in_last_intl_idx;
  assign in_ctrl.sos    = in_first_intl_idx & in_first_stg_iter;
  assign in_ctrl.eos    = in_last_intl_idx & in_last_stg_iter;
  assign in_ctrl.pbs_id = in_pbs_idx;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      for (int p=0; p<PSI; p=p+1)
        for (int r=0; r<R; r=r+1)
          in_data[p][r] = {$urandom(),$urandom()};
    end
    else begin
      if (in_avail[0])
      for (int p=0; p<PSI; p=p+1)
        for (int r=0; r<R; r=r+1)
          in_data[p][r] = {$urandom(),$urandom()};
    end

/*
  always_comb
    for (int p=0; p<PSI; p=p+1)
      for (int r=0; r<R; r=r+1)
        in_data[p][r] = in_stg_iter*PSI*R + +p*R + r;
*/

  logic [PSI*R-1:0][MOD_NTT_W+1:0] ref_data_q[$];

  always_ff @(posedge clk)
    if (in_avail[0]) begin
      var [PSI*R-1:0][MOD_NTT_W+1:0] v;
      var [PSI*R-1:0][MOD_NTT_W+1:0] in;
      in = ntt_data[0];
      for (int i=0; i<PSI*R; i=i+1)
        v[i] = in[i] % MOD_NTT;
      ref_data_q.push_back(v);
    end

// ---------------------------------------------------------------------------------------------- --
// Output ref
// ---------------------------------------------------------------------------------------------- --
  ctrl_t ref_ctrl;

  assign ref_ctrl.sob    = out_first_intl_idx & out_first_stg_iter & out_first_pbs_idx;
  assign ref_ctrl.eob    = out_last_intl_idx & out_last_stg_iter & out_last_pbs_idx;
  assign ref_ctrl.sol    = out_first_intl_idx;
  assign ref_ctrl.eol    = out_last_intl_idx;
  assign ref_ctrl.sos    = out_first_intl_idx & out_first_stg_iter;
  assign ref_ctrl.eos    = out_last_intl_idx & out_last_stg_iter;
  assign ref_ctrl.pbs_id = out_pbs_idx;

// ---------------------------------------------------------------------------------------------- --
// Check
// ---------------------------------------------------------------------------------------------- --
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      error_data <= 1'b0;
      error_ctrl <= 1'b0;
    end
    else begin
      if (out_avail[0]) begin
        var [PSI*R-1:0][MOD_NTT_W+1:0] ref_data;
        ref_data = ref_data_q.pop_front();

        for (int p=0; p<PSI; p=p+1) begin
          for (int r=0; r<R; r=r+1) begin
            assert(out_data[p][r] == ref_data[p*R+r])
            else begin
              $display("%t > ERROR: Mismatch data iter=%0d [%0d] exp=0x%03x seen=0x%03x",$time, out_stg_iter, p*R+r,ref_data[p*R+r],out_data[p][r]);
              error_data <= 1'b1;
            end
          end
        end

        assert({out_ctrl.sob, out_ctrl.eob, out_ctrl.sol, out_ctrl.eol, out_ctrl.sos, out_ctrl.eos, out_ctrl.pbs_id}
                == {ref_ctrl.sob, ref_ctrl.eob, ref_ctrl.sol, ref_ctrl.eol, ref_ctrl.sos, ref_ctrl.eos, ref_ctrl.pbs_id})
        else begin
          $display("%t > ERROR: Mismatch ctrl.", $time);
          $display("%t >   ref_ctrl.sob : exp=%0d seen=%0d",$time, ref_ctrl.sob, out_ctrl.sob);
          $display("%t >   ref_ctrl.eob : exp=%0d seen=%0d",$time, ref_ctrl.eob, out_ctrl.eob);
          $display("%t >   ref_ctrl.sol : exp=%0d seen=%0d",$time, ref_ctrl.sol, out_ctrl.sol);
          $display("%t >   ref_ctrl.eol : exp=%0d seen=%0d",$time, ref_ctrl.eol, out_ctrl.eol);
          $display("%t >   ref_ctrl.sos : exp=%0d seen=%0d",$time, ref_ctrl.sos, out_ctrl.sos);
          $display("%t >   ref_ctrl.eos : exp=%0d seen=%0d",$time, ref_ctrl.eos, out_ctrl.eos);
          $display("%t >   ref_ctrl.pbs_id : exp=%0d seen=%0d",$time, ref_ctrl.pbs_id, out_ctrl.pbs_id);
          error_ctrl <= 1'b1;
        end

      end
    end

// ---------------------------------------------------------------------------------------------- --
// End of test
// ---------------------------------------------------------------------------------------------- --
  integer batch_cnt;
  always_ff @(posedge clk)
    if (!s_rst_n) batch_cnt <= '0;
    else          batch_cnt <= (out_avail[0] && out_ctrl.eob) ? batch_cnt + 1 : batch_cnt;

  initial begin
    end_of_test <= 1'b0;
    wait(batch_cnt == SAMPLE_BATCH_NB);
    repeat(10) @(posedge clk);
    end_of_test <= 1'b1;
  end

endmodule
