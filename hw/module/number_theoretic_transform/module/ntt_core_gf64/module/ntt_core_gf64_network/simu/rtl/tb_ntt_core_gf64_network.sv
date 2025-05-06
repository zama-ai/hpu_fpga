// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This testbench checks the ntt_core_gf64_network.
// ==============================================================================================

`include "ntt_core_gf64_ntw_macro_inc.sv"

module tb_ntt_core_gf64_network;

`timescale 1ns/10ps

  import pep_common_param_pkg::*;
  import param_tfhe_pkg::*;
  import ntt_core_common_param_pkg::*;
  import ntt_core_gf64_common_param_pkg::*;

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int CLK_HALF_PERIOD = 1;
  localparam int ARST_ACTIVATION = 17;

  parameter int RDX_CUT_ID  = 1;
  parameter bit BWD         = 1'b1;

  parameter int RAM_LATENCY = 2;
  parameter bit IN_PIPE     = 1'b1;

  localparam int LVL_NB     = BWD ? GLWE_K_P1 : INTL_L;
  localparam int LVL_W      = $clog2(LVL_NB)==0 ? 1 : $clog2(LVL_NB);
  
  localparam int DATA_W     = 16;
  localparam int OP_W       = DATA_W + LVL_W;

  localparam int SAMPLE_BATCH_NB = 10;

  `NTT_CORE_GF64_NTW_LOCALPARAM(RDX_CUT_ID,BWD,R,PSI)

// ============================================================================================== --
// type
// ============================================================================================== --
  typedef struct packed {
    logic [LVL_W-1:0]  intl_idx;
    logic [DATA_W-1:0] data;
  } elt_t;

  localparam int ELT_W = $bits(elt_t);

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
  bit error_avail;

  assign error = error_data | error_ctrl | error_avail;

  always_ff @(posedge clk)
    if (error) begin
      $display("%t > FAILURE !", $time);
      $finish;
    end

// ============================================================================================== --
// input / output signals
// ============================================================================================== --
  logic [PSI*R-1:0][OP_W-1:0]      in_data;
  logic [PSI*R-1:0]                in_avail;
  logic                            in_sob;
  logic                            in_eob;
  logic                            in_sol;
  logic                            in_eol;
  logic                            in_sos;
  logic                            in_eos;
  logic [BPBS_ID_W-1:0]            in_pbs_id;

  logic [PSI*R-1:0][OP_W-1:0]      out_data;
  logic [PSI*R-1:0]                out_avail;
  logic                            out_sob;
  logic                            out_eob;
  logic                            out_sol;
  logic                            out_eol;
  logic                            out_sos;
  logic                            out_eos;
  logic [BPBS_ID_W-1:0]            out_pbs_id;

// ============================================================================================== --
// Design under test instance
// ============================================================================================== --
  ntt_core_gf64_network #(
    .RDX_CUT_ID      (RDX_CUT_ID),
    .BWD             (BWD),
    .OP_W            (OP_W),
    .IN_PIPE         (IN_PIPE),
    .RAM_LATENCY     (RAM_LATENCY)
  ) dut (
    .clk     (clk    ),
    .s_rst_n (s_rst_n),

    .in_data    (in_data),
    .in_avail   (in_avail),
    .in_sob     (in_sob),
    .in_eob     (in_eob),
    .in_sol     (in_sol),
    .in_eol     (in_eol),
    .in_sos     (in_sos),
    .in_eos     (in_eos),
    .in_pbs_id  (in_pbs_id),

    .out_data   (out_data),
    .out_avail  (out_avail),
    .out_sob    (out_sob),
    .out_eob    (out_eob),
    .out_sol    (out_sol),
    .out_eol    (out_eol),
    .out_sos    (out_sos),
    .out_eos    (out_eos),
    .out_pbs_id (out_pbs_id)
  );

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
  assign in_first_pbs_idx   = in_pbs_idx == '0;

  assign in_last_intl_idx = in_intl_idx == LVL_NB-1;
  assign in_last_stg_iter = in_stg_iter == STG_ITER_NB-1;
  assign in_last_pbs_idx   = in_pbs_idx == in_pbs_nb-1;

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
  assign out_first_pbs_idx   = out_pbs_idx == '0;

  assign out_last_intl_idx = out_intl_idx == LVL_NB-1;
  assign out_last_stg_iter = out_stg_iter == STG_ITER_NB-1;
  assign out_last_pbs_idx   = out_pbs_idx == out_pbs_nb-1;

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

  assign in_avail  = {PSI*R{rand_in_avail}};
  assign in_sob    = in_first_intl_idx & in_first_stg_iter & in_first_pbs_idx;
  assign in_eob    = in_last_intl_idx & in_last_stg_iter & in_last_pbs_idx;
  assign in_sol    = in_first_intl_idx;
  assign in_eol    = in_last_intl_idx;
  assign in_sos    = in_first_intl_idx & in_first_stg_iter;
  assign in_eos    = in_last_intl_idx & in_last_stg_iter;
  assign in_pbs_id = in_pbs_idx;

  logic [N-1:0][DATA_W-1:0]                      ref_in_data; // constant
  logic [STG_ITER_NB-1:0][PSI*R-1:0][DATA_W-1:0] ref_in_data_a;

  always_comb
    for (int i=0; i<N; i=i+1)
      ref_in_data[i] = i;

  assign ref_in_data_a = ref_in_data;

  always_comb
    for (int i=0; i<PSI*R; i=i+1) begin
      elt_t d;
      d.data     = ref_in_data_a[in_stg_iter][i]; 
      d.intl_idx = in_intl_idx;
      in_data[i] = d;
    end

// ---------------------------------------------------------------------------------------------- --
// Output ref
// ---------------------------------------------------------------------------------------------- --
  logic                       ref_sob;
  logic                       ref_eob;
  logic                       ref_sol;
  logic                       ref_eol;
  logic                       ref_sos;
  logic                       ref_eos;
  logic [BPBS_ID_W-1:0]       ref_pbs_id;

  assign ref_sob    = out_first_intl_idx & out_first_stg_iter & out_first_pbs_idx;
  assign ref_eob    = out_last_intl_idx & out_last_stg_iter & out_last_pbs_idx;
  assign ref_sol    = out_first_intl_idx;
  assign ref_eol    = out_last_intl_idx;
  assign ref_sos    = out_first_intl_idx & out_first_stg_iter;
  assign ref_eos    = out_last_intl_idx & out_last_stg_iter;
  assign ref_pbs_id = out_pbs_idx;

  logic [WB_NB-1:0][R_L-1:0][L_NB-1:0][DATA_W-1:0] ref_in_data_aa;
  logic [WB_NB-1:0][L_NB-1:0][R_L-1:0][DATA_W-1:0] ref_out_data_aa;
  logic [STG_ITER_NB-1:0][PSI*R-1:0][DATA_W-1:0]   ref_out_data_a;
  logic [PSI*R-1:0][OP_W-1:0]                      ref_out_elt;

  assign ref_in_data_aa = ref_in_data;
  assign ref_out_data_a = ref_out_data_aa;

  always_comb
    for (int b=0; b<WB_NB; b=b+1)
      for (int r=0; r<R_L; r=r+1)
        for (int i=0; i<L_NB; i=i+1)
          ref_out_data_aa[b][i][r] = ref_in_data_aa[b][r][i];

  always_comb
    for (int i=0; i<PSI*R; i=i+1) begin
      elt_t d;
      d.data     = ref_out_data_a[out_stg_iter][i]; 
      d.intl_idx = out_intl_idx;
      ref_out_elt[i] = d;
    end

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
        for (int i=0; i<PSI*R; i=i+1) begin
          assert(out_data[i] == ref_out_elt[i])
          else begin
            $display("%t > ERROR: Mismatch data iter=%0d [%0d] exp=0x%03x seen=0x%03x",$time, out_stg_iter, i,ref_out_elt[i],out_data[i]);
            error_data <= 1'b1;
          end
        end

        assert({out_sob, out_eob, out_sol, out_eol, out_sos, out_eos, out_pbs_id}
                == {ref_sob, ref_eob, ref_sol, ref_eol, ref_sos, ref_eos, ref_pbs_id})
        else begin
          $display("%t > ERROR: Mismatch ctrl.", $time);
          $display("%t >   ref_sob : exp=%0d seen=%0d",$time, ref_sob, out_sob);
          $display("%t >   ref_eob : exp=%0d seen=%0d",$time, ref_eob, out_eob);
          $display("%t >   ref_sol : exp=%0d seen=%0d",$time, ref_sol, out_sol);
          $display("%t >   ref_eol : exp=%0d seen=%0d",$time, ref_eol, out_eol);
          $display("%t >   ref_sos : exp=%0d seen=%0d",$time, ref_sos, out_sos);
          $display("%t >   ref_eos : exp=%0d seen=%0d",$time, ref_eos, out_eos);
          $display("%t >   ref_pbs_id : exp=%0d seen=%0d",$time, ref_pbs_id, out_pbs_id);
          error_ctrl <= 1'b1;
        end
      end
    end

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      error_avail <= 1'b0;
    end
    else begin
      assert(out_avail == '1 || out_avail == '0)
      else begin
        $display("%t > ERROR: Mismatch ctrl.", $time);
        error_avail <= 1'b1;
      end
    end

// ---------------------------------------------------------------------------------------------- --
// End of test
// ---------------------------------------------------------------------------------------------- --
  integer batch_cnt;
  always_ff @(posedge clk)
    if (!s_rst_n) batch_cnt <= '0;
    else          batch_cnt <= (out_avail[0] && out_eob) ? batch_cnt + 1 : batch_cnt;

  initial begin
    end_of_test <= 1'b0;
    wait(batch_cnt == SAMPLE_BATCH_NB);
    repeat(10) @(posedge clk);
    end_of_test <= 1'b1;
  end
endmodule
