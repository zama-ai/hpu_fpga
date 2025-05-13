// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
// Post process testbench
// ==============================================================================================

`include "ntt_core_common_macro_inc.sv"

module tb_ntt_core_wmm_post_process
  import param_ntt_pkg::*;
  import param_tfhe_pkg::*;
  import pep_common_param_pkg::*;
  import common_definition_pkg::*;
#(
  parameter int           R               = 8, // Butterfly Radix
  parameter int           PSI             = 8, // Number of butterflies
  parameter int           S               = 3, // Number of stages
  parameter mod_mult_type_e          MOD_MULT_TYPE   = set_mod_mult_type(MOD_NTT_TYPE),
  parameter arith_mult_type_e        MULT_TYPE       = set_ntt_mult_type(MOD_NTT_W, MOD_NTT_TYPE),
  parameter bit           IN_PIPE         = 1'b1, // Recommended
  parameter bit           OUT_PIPE        = 1'b1  // Recommended
);

  `timescale 1ns/10ps

  import mod_arith::*;

  // ============================================================================================ //
  // localparam
  // ============================================================================================ //
  `NTT_CORE_LOCALPARAM(R,S,PSI)

  // system
  localparam int CLK_HALF_PERIOD   = 1;
  localparam int ARST_ACTIVATION   = 17;
  // testbench
  localparam int BATCH_NB          = 1000;
  localparam int BATCH_NB_W        = $clog2(BATCH_NB) == 0 ? 1 : $clog2(BATCH_NB);

  localparam int OP_W              = MOD_NTT_W;

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
    logic                ntt_bwd;
    logic                last_stg;
    logic [BPBS_ID_W-1:0] pbs_id;
  } control_t;

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
  bit error_rs;
  bit error_ls_bwd;
  bit error_ls_fwd;
  bit error_ls;
  bit error_module;

  assign error = error_ls_bwd
               | error_ls_fwd
               | error_ls
               | error_rs
               | error_module;

  always_ff @(posedge clk) begin
    if (error) begin
      $display("%t > FAILURE !", $time);
      $display(" error_rs   %1d", error_rs);
      $display(" error_ls_bwd  %1d", error_ls_bwd);
      $display(" error_ls_fwd  %1d", error_ls_fwd);
      $display(" error_ls     %1d", error_ls);
      $display(" error_module    %1d \n", error_module);
      $stop;
    end
  end

  // ============================================================================================ //
  // IO
  // ============================================================================================ //
  // Data from CLBU
  logic [     OP_W-1:0]           clbu_pp_data;
  logic                           clbu_pp_data_avail;
  logic                           clbu_pp_sob;
  logic                           clbu_pp_eob;
  logic                           clbu_pp_sol;
  logic                           clbu_pp_eol;
  logic                           clbu_pp_sos;
  logic                           clbu_pp_eos;
  logic                           clbu_pp_ntt_bwd;
  logic [ BPBS_ID_W-1:0]           clbu_pp_pbs_id;
  logic                           clbu_pp_ctrl_avail;
  logic                           clbu_pp_last_stg;
  // Output logic data to network regular stage
  logic [     OP_W-1:0]           pp_rsntw_data;
  logic                           pp_rsntw_sob;
  logic                           pp_rsntw_eob;
  logic                           pp_rsntw_sol;
  logic                           pp_rsntw_eol;
  logic                           pp_rsntw_sos;
  logic                           pp_rsntw_eos;
  logic [ BPBS_ID_W-1:0]           pp_rsntw_pbs_id;
  logic                           pp_rsntw_avail;
  // Output logic data tp network last stage
  logic [     OP_W-1:0]           pp_lsntw_fwd_data;
  logic                           pp_lsntw_fwd_sob;
  logic                           pp_lsntw_fwd_eob;
  logic                           pp_lsntw_fwd_sol;
  logic                           pp_lsntw_fwd_eol;
  logic                           pp_lsntw_fwd_sos;
  logic                           pp_lsntw_fwd_eos;
  logic [ BPBS_ID_W-1:0]           pp_lsntw_fwd_pbs_id;
  logic                           pp_lsntw_fwd_avail;
  // Output logic data tp network last stage
  logic [     OP_W-1:0]           pp_lsntw_bwd_data;
  logic                           pp_lsntw_bwd_sob;
  logic                           pp_lsntw_bwd_eob;
  logic                           pp_lsntw_bwd_sol;
  logic                           pp_lsntw_bwd_eol;
  logic                           pp_lsntw_bwd_sos;
  logic                           pp_lsntw_bwd_eos;
  logic [ BPBS_ID_W-1:0]           pp_lsntw_bwd_pbs_id;
  logic                           pp_lsntw_bwd_avail;
  // Output logic data tp network last stage
  logic [     OP_W-1:0]           pp_lsntw_data;
  logic                           pp_lsntw_sob;
  logic                           pp_lsntw_eob;
  logic                           pp_lsntw_sol;
  logic                           pp_lsntw_eol;
  logic                           pp_lsntw_sos;
  logic                           pp_lsntw_eos;
  logic [ BPBS_ID_W-1:0]           pp_lsntw_pbs_id;
  logic                           pp_lsntw_avail;
  // Error trigger
  logic                           pp_error;
  // Twiddles for final multiplication
  logic [     OP_W-1:0]           twd_intt_final;
  logic                           twd_intt_final_vld;
  logic                           twd_intt_final_rdy;
  // Matrix factors : BSK
  logic [GLWE_K_P1-1:0][OP_W-1:0] bsk;
  logic [GLWE_K_P1-1:0]           bsk_vld;
  logic [GLWE_K_P1-1:0]           bsk_rdy;

  // ============================================================================================ //
  // Design under test instance
  // ============================================================================================ //
  ntt_core_wmm_post_process #(
    .OP_W           (OP_W),
    .MOD_NTT        (MOD_NTT),
    .MOD_MULT_TYPE  (MOD_MULT_TYPE),
    .MULT_TYPE      (MULT_TYPE),
    .IN_PIPE        (IN_PIPE),
    .OUT_PIPE       (OUT_PIPE)
  ) ntt_core_wmm_post_process (
    .clk                 (clk),
    .s_rst_n             (s_rst_n),
    // data from CLBU
    .clbu_pp_data        (clbu_pp_data),
    .clbu_pp_data_avail  (clbu_pp_data_avail),
    .clbu_pp_sob         (clbu_pp_sob),
    .clbu_pp_eob         (clbu_pp_eob),
    .clbu_pp_sol         (clbu_pp_sol),
    .clbu_pp_eol         (clbu_pp_eol),
    .clbu_pp_sos         (clbu_pp_sos),
    .clbu_pp_eos         (clbu_pp_eos),
    .clbu_pp_ntt_bwd     (clbu_pp_ntt_bwd),
    .clbu_pp_pbs_id      (clbu_pp_pbs_id),
    .clbu_pp_ctrl_avail  (clbu_pp_ctrl_avail),
    .clbu_pp_last_stg    (clbu_pp_last_stg),
    // output regular stage network
    .pp_rsntw_data       (pp_rsntw_data),
    .pp_rsntw_sob        (pp_rsntw_sob),
    .pp_rsntw_eob        (pp_rsntw_eob),
    .pp_rsntw_sol        (pp_rsntw_sol),
    .pp_rsntw_eol        (pp_rsntw_eol),
    .pp_rsntw_sos        (pp_rsntw_sos),
    .pp_rsntw_eos        (pp_rsntw_eos),
    .pp_rsntw_pbs_id     (pp_rsntw_pbs_id),
    .pp_rsntw_avail      (pp_rsntw_avail),
    // output last stage network
    .pp_lsntw_data       (pp_lsntw_data),
    .pp_lsntw_sob        (pp_lsntw_sob),
    .pp_lsntw_eob        (pp_lsntw_eob),
    .pp_lsntw_sol        (pp_lsntw_sol),
    .pp_lsntw_eol        (pp_lsntw_eol),
    .pp_lsntw_sos        (pp_lsntw_sos),
    .pp_lsntw_eos        (pp_lsntw_eos),
    .pp_lsntw_pbs_id     (pp_lsntw_pbs_id),
    .pp_lsntw_avail      (pp_lsntw_avail),
    // output last stage network
    .pp_lsntw_fwd_data   (pp_lsntw_fwd_data),
    .pp_lsntw_fwd_sob    (pp_lsntw_fwd_sob),
    .pp_lsntw_fwd_eob    (pp_lsntw_fwd_eob),
    .pp_lsntw_fwd_sol    (pp_lsntw_fwd_sol),
    .pp_lsntw_fwd_eol    (pp_lsntw_fwd_eol),
    .pp_lsntw_fwd_sos    (pp_lsntw_fwd_sos),
    .pp_lsntw_fwd_eos    (pp_lsntw_fwd_eos),
    .pp_lsntw_fwd_pbs_id (pp_lsntw_fwd_pbs_id),
    .pp_lsntw_fwd_avail  (pp_lsntw_fwd_avail),
    // output last stage network
    .pp_lsntw_bwd_data   (pp_lsntw_bwd_data),
    .pp_lsntw_bwd_sob    (pp_lsntw_bwd_sob),
    .pp_lsntw_bwd_eob    (pp_lsntw_bwd_eob),
    .pp_lsntw_bwd_sol    (pp_lsntw_bwd_sol),
    .pp_lsntw_bwd_eol    (pp_lsntw_bwd_eol),
    .pp_lsntw_bwd_sos    (pp_lsntw_bwd_sos),
    .pp_lsntw_bwd_eos    (pp_lsntw_bwd_eos),
    .pp_lsntw_bwd_pbs_id (pp_lsntw_bwd_pbs_id),
    .pp_lsntw_bwd_avail  (pp_lsntw_bwd_avail),
    // error trigger
    .pp_error            (pp_error),
    // twiddles
    .twd_intt_final      (twd_intt_final),
    .twd_intt_final_vld  (twd_intt_final_vld),
    .twd_intt_final_rdy  (twd_intt_final_rdy),
    // bootstrapping key
    .bsk                 (bsk),
    .bsk_vld             (bsk_vld),
    .bsk_rdy             (bsk_rdy)
  );

  // ============================================================================================ //
  // Stimuli
  // ============================================================================================ //
  logic     [OP_W-1:0] data_in_q    [$];
  logic     [OP_W-1:0] tw_in_q      [$];
  logic     [OP_W-1:0] bsk_in_q     [GLWE_K_P1-1:0][$];

  // checker
  logic     [OP_W-1:0] data_ls_q     [$];
  logic     [OP_W-1:0] data_ls_bwd_q [$];
  logic     [OP_W-1:0] data_ls_fwd_q [$];
  logic     [OP_W-1:0] data_rs_q     [$];

  int                  pbs_nb_a     [BATCH_NB-1:0];

  // control
  control_t            ctrl_in_q     [$];
  control_t            ctrl_rs_q     [$];
  control_t            ctrl_ls_q     [$];
  control_t            ctrl_ls_fwd_q [$];
  control_t            ctrl_ls_bwd_q [$];

  initial begin

    for (int batch_id = 0; batch_id < BATCH_NB; batch_id++) begin
      int pbs_nb;

      pbs_nb             = $urandom_range(BATCH_PBS_NB, 1);
      pbs_nb_a[batch_id] = pbs_nb;

      for (int ntt_bwd = 0; ntt_bwd < 2; ntt_bwd++) begin
        for (int stg = S - 1; stg >= 0; stg--) begin

          for (int pbs_id = 0; pbs_id < pbs_nb; pbs_id++) begin
            // interleaving
            int intl_nb;
            intl_nb = (!ntt_bwd && (stg == 0)) ? INTL_L : GLWE_K_P1;

            // Insert intl_idx + control
            for (int stg_iter = 0; stg_iter < STG_ITER_NB; stg_iter = stg_iter + 1) begin
              logic     [INTL_L-1:0][GLWE_K_P1-1:0][OP_W-1:0] data_ls_fwd;
              logic     [     OP_W-1:0]           twiddle;
              if ((stg == 0) & (ntt_bwd == 1)) begin
                  twiddle     = {$urandom(), $urandom()}; // Same twiddle for all the levels
                  tw_in_q.push_back(twiddle);
              end
              for (int intl_idx = 0; intl_idx < intl_nb; intl_idx = intl_idx + 1) begin
                control_t                           c;
                logic     [     OP_W-1:0]           data;
                logic     [GLWE_K_P1-1:0][OP_W-1:0] data_bsk;
                logic     [     OP_W-1:0]           data_ls_bwd;


                // blocs
                c.sob = (stg_iter == 0) & (intl_idx == 0) & (pbs_id == 0);
                c.eob = (stg_iter == (STG_ITER_NB - 1)) & (intl_idx == (intl_nb - 1)) &
                    (pbs_id == (pbs_nb - 1));

                // levels
                c.sol = (intl_idx == 0);
                c.eol = (intl_idx == (intl_nb - 1));

                // stages
                c.sos = (stg_iter == 0) & (intl_idx == 0);
                c.eos = (stg_iter == STG_ITER_NB - 1) & (intl_idx == (intl_nb - 1));

                if (stg > 0) begin
                  c.last_stg = 0;
                end else begin
                  c.last_stg = 1;
                end

                // others
                c.ntt_bwd   = ntt_bwd;
                c.pbs_id    = pbs_id;

                // data generation
                // random range doesn't work when OP_W > 32
                data        = {$urandom(), $urandom()};

                // All time ------------------------------------------------------------------------
                ctrl_in_q.push_back(c);
                data_in_q.push_back(data);

                // BWD LAST STAGE ------------------------------------------------------------------
                if ((stg == 0) & (ntt_bwd == 1)) begin
                  data_ls_bwd = mod_red(data * twiddle, MOD_NTT);
                  data_ls_bwd_q.push_back(data_ls_bwd);
                  data_ls_q.push_back(data_ls_bwd);
                  ctrl_ls_bwd_q.push_back(c);
                  ctrl_ls_q.push_back(c);
                end  // backward last stage

                // FWD LAST STAGE ------------------------------------------------------------------
                if ((stg == 0) & (ntt_bwd == 0)) begin
                  for (int bsk_i = 0; bsk_i < GLWE_K_P1; bsk_i++) begin
                    data_bsk[bsk_i] = {$urandom(), $urandom()};
                    bsk_in_q[bsk_i].push_back(data_bsk[bsk_i]);
                    data_ls_fwd[intl_idx][bsk_i] = mod_red(data * data_bsk[bsk_i], MOD_NTT);
                  end
                end  // forward last stage

                // REGULAR STAGE ------------------------------------------------------------------
                if (stg > 0) begin
                  data_rs_q.push_back(data);
                  ctrl_rs_q.push_back(c);
                end
              end  // intl_idx

              // Do accumulation and control for FWD LAST STAGE
              if ((stg == 0) & (ntt_bwd == 0)) begin

                for (int i=0; i<GLWE_K_P1; i=i+1) begin
                  control_t        c;
                  logic [OP_W-1:0] d_acc;
                  d_acc = '0;
                  for (int j=0; j<INTL_L; j=j+1) begin
                    d_acc = mod_red(d_acc + data_ls_fwd[j][i], MOD_NTT);
                  end
                  data_ls_fwd_q.push_back(d_acc);
                  data_ls_q.push_back(d_acc);

                  // blocs
                  c.sob = (stg_iter == 0) & (i == 0) & (pbs_id == 0);
                  c.eob = (stg_iter == (STG_ITER_NB - 1)) & (i == (GLWE_K_P1 - 1)) &
                      (pbs_id == (pbs_nb - 1));

                  // levels
                  c.sol = (i == 0);
                  c.eol = (i == (GLWE_K_P1 - 1));

                  // stages
                  c.sos = (stg_iter == 0) & (i == 0);
                  c.eos = (stg_iter == STG_ITER_NB - 1) & (i == (GLWE_K_P1 - 1));

                  c.last_stg = 1;

                  // others
                  c.ntt_bwd   = ntt_bwd;
                  c.pbs_id    = pbs_id;

                  ctrl_ls_fwd_q.push_back(c);
                  ctrl_ls_q.push_back(c);
                end

              end

            end  // stg_iter

          end  // PBS ID

        end  // Stages

      end  // NTT backward

    end  // Batch ID

  end  // initial begin

  // ============================================================================================ //
  // Input
  // ============================================================================================ //
  logic start;
  always_ff @(posedge clk)
    if (!s_rst_n)
      start <= 1;
    else
      start <= 0;

  // -------------------------------------------------------------------------------------------- //
  // Data in
  // -------------------------------------------------------------------------------------------- //
  logic in_vld;
  logic in_vldD;
  logic rand_in_vld;

  always_ff @(posedge clk)
    rand_in_vld          <= $urandom_range(1);

  assign in_vldD = rand_in_vld;

  always_ff @(posedge clk)
    if (!s_rst_n ) in_vld <= 1'b0;
    else           in_vld <= in_vldD;

  assign clbu_pp_data_avail = in_vld;
  assign clbu_pp_ctrl_avail = in_vld;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      clbu_pp_data       <= 'x;
      clbu_pp_sob        <= 'x;
      clbu_pp_eob        <= 'x;
      clbu_pp_sol        <= 'x;
      clbu_pp_eol        <= 'x;
      clbu_pp_sos        <= 'x;
      clbu_pp_eos        <= 'x;
      clbu_pp_ntt_bwd    <= 'x;
      clbu_pp_pbs_id     <= 'x;
      clbu_pp_last_stg   <= 'x;
    end
    else if (start || clbu_pp_ctrl_avail) begin
      control_t c;
      logic [OP_W-1:0] d;
      c = ctrl_in_q.pop_front();
      d = data_in_q.pop_front();
      clbu_pp_data       <= d;
      clbu_pp_sob        <= c.sob     ;
      clbu_pp_eob        <= c.eob     ;
      clbu_pp_sol        <= c.sol     ;
      clbu_pp_eol        <= c.eol     ;
      clbu_pp_sos        <= c.sos     ;
      clbu_pp_eos        <= c.eos     ;
      clbu_pp_ntt_bwd    <= c.ntt_bwd ;
      clbu_pp_pbs_id     <= c.pbs_id  ;
      clbu_pp_last_stg   <= c.last_stg;
    end
  end

  // -------------------------------------------------------------------------------------------- //
  // BSK
  // -------------------------------------------------------------------------------------------- //
  // Do not test the unavailability of BSK here
  assign bsk_vld = '1;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      bsk <= 'x;
    end
    else begin
      for (int i=0; i<GLWE_K_P1; i=i+1) begin
        if (start || (bsk_vld[i] && (bsk_rdy[i]))) begin
          logic [OP_W-1:0] b;
          b = bsk_in_q[i].pop_front();
          bsk[i] <= b;
        end
      end
    end
  end

  // -------------------------------------------------------------------------------------------- //
  // Twiddle INTT final
  // -------------------------------------------------------------------------------------------- //
  // Do not test the unavailability of twiddles here
  assign twd_intt_final_vld = 1'b1;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      twd_intt_final <= 'x;
    end
    else begin
      if (start || (twd_intt_final_vld && (twd_intt_final_rdy))) begin
        logic [OP_W-1:0] b;
        b = tw_in_q.pop_front();
        twd_intt_final <= b;
      end
    end
  end


  // ============================================================================================ //
  // Checker
  // ============================================================================================ //
  assign error_module = pp_error;

  int valid_rs_cnt;
  int valid_ls_fwd_cnt;
  int valid_ls_bwd_cnt;
  int valid_ls_cnt;

  // rs stage ---------------------------------------------------------------------------------
  always_ff @(posedge clk) begin : checker_rs
    logic     [OP_W-1:0] data_rs;
    control_t            c;

    if (~s_rst_n) begin
      error_rs <= 0;
    end else begin
      if (pp_rsntw_avail) begin
        c       = ctrl_rs_q.pop_front();
        data_rs = data_rs_q.pop_front();

        // checking data
        assert ((data_rs == pp_rsntw_data)) begin
          valid_rs_cnt = valid_rs_cnt + 1;
        end else begin
          $display("%t > ERROR: RS Stage : data mismatch. exp=0x%0x seen=0x%0x", $time,data_rs, pp_rsntw_data);
          error_rs <= 1;
        end

        // checking control
        assert ((pp_rsntw_sob == c.sob)
              && (pp_rsntw_eob == c.eob)
              && (pp_rsntw_sol == c.sol)
              && (pp_rsntw_eol == c.eol)
              && (pp_rsntw_sos == c.sos)
              && (pp_rsntw_eos == c.eos)
              && (pp_rsntw_pbs_id == c.pbs_id))
        else begin
          $display("%t > ERROR: RS Stage : control mismatch",$time);
          $display("  sob : exp=%1d seen=%1d",c.sob,pp_rsntw_sob);
          $display("  eob : exp=%1d seen=%1d",c.eob,pp_rsntw_eob);
          $display("  sol : exp=%1d seen=%1d",c.sol,pp_rsntw_sol);
          $display("  eol : exp=%1d seen=%1d",c.eol,pp_rsntw_eol);
          $display("  sos : exp=%1d seen=%1d",c.sos,pp_rsntw_sos);
          $display("  eos : exp=%1d seen=%1d",c.eos,pp_rsntw_eos);
          $display("  pbs_id : exp=%1d seen=%1d",c.pbs_id,pp_rsntw_pbs_id);

          error_rs <= 1;
        end
      end

    end
  end

  // backward last stage ---------------------------------------------------------------------------
  always_ff @(posedge clk) begin : checker_ls_bwd
    logic     [OP_W-1:0] data_ls_bwd;
    control_t            c;

    if (~s_rst_n) begin
      error_ls_bwd <= 0;
    end else begin
      if (pp_lsntw_bwd_avail) begin
        c           = ctrl_ls_bwd_q.pop_front();
        data_ls_bwd = data_ls_bwd_q.pop_front();

        // checking data
        assert ((data_ls_bwd == pp_lsntw_bwd_data)) begin
          valid_ls_bwd_cnt = valid_ls_bwd_cnt + 1;
        end else begin
          $display("%t > ERROR: ls_bwd Stage : data mismatch. exp=0x%0x seen=0x%0x", $time,data_ls_bwd, pp_lsntw_bwd_data);
          error_ls_bwd <= 1;
        end

        // checking control
        assert ((pp_lsntw_bwd_sob == c.sob)
              && (pp_lsntw_bwd_eob == c.eob)
              && (pp_lsntw_bwd_sol == c.sol)
              && (pp_lsntw_bwd_eol == c.eol)
              && (pp_lsntw_bwd_sos == c.sos)
              && (pp_lsntw_bwd_eos == c.eos)
              && (pp_lsntw_bwd_pbs_id == c.pbs_id))
        else begin
          $display("%t > ERROR: ls_bwd Stage : control mismatch",$time);
          $display("  sob : exp=%1d seen=%1d",c.sob,pp_lsntw_bwd_sob);
          $display("  eob : exp=%1d seen=%1d",c.eob,pp_lsntw_bwd_eob);
          $display("  sol : exp=%1d seen=%1d",c.sol,pp_lsntw_bwd_sol);
          $display("  eol : exp=%1d seen=%1d",c.eol,pp_lsntw_bwd_eol);
          $display("  sos : exp=%1d seen=%1d",c.sos,pp_lsntw_bwd_sos);
          $display("  eos : exp=%1d seen=%1d",c.eos,pp_lsntw_bwd_eos);
          $display("  pbs_id : exp=%1d seen=%1d",c.pbs_id,pp_lsntw_bwd_pbs_id);

          error_ls_bwd <= 1;
        end
      end

    end
  end

  // forward last stage ---------------------------------------------------------------------------
  always_ff @(posedge clk) begin : checker_ls_fwd
    logic     [OP_W-1:0] data_ls_fwd;
    control_t            c;

    if (~s_rst_n) begin
      error_ls_fwd <= 0;
    end else begin
      if (pp_lsntw_fwd_avail) begin
        c           = ctrl_ls_fwd_q.pop_front();
        data_ls_fwd = data_ls_fwd_q.pop_front();

        // checking data
        assert ((data_ls_fwd == pp_lsntw_fwd_data)) begin
          valid_ls_fwd_cnt = valid_ls_fwd_cnt + 1;
        end else begin
          $display("%t > ERROR: ls_fwd Stage : data mismatch. exp=0x%0x seen=0x%0x", $time,data_ls_fwd, pp_lsntw_fwd_data);
          error_ls_fwd <= 1;
        end

        // checking control
        assert ((pp_lsntw_fwd_sob == c.sob)
              && (pp_lsntw_fwd_eob == c.eob)
              && (pp_lsntw_fwd_sol == c.sol)
              && (pp_lsntw_fwd_eol == c.eol)
              && (pp_lsntw_fwd_sos == c.sos)
              && (pp_lsntw_fwd_eos == c.eos)
              && (pp_lsntw_fwd_pbs_id == c.pbs_id))
        else begin
          $display("%t > ERROR: ls_fwd Stage : control mismatch",$time);
          $display("  sob : exp=%1d seen=%1d",c.sob,pp_lsntw_fwd_sob);
          $display("  eob : exp=%1d seen=%1d",c.eob,pp_lsntw_fwd_eob);
          $display("  sol : exp=%1d seen=%1d",c.sol,pp_lsntw_fwd_sol);
          $display("  eol : exp=%1d seen=%1d",c.eol,pp_lsntw_fwd_eol);
          $display("  sos : exp=%1d seen=%1d",c.sos,pp_lsntw_fwd_sos);
          $display("  eos : exp=%1d seen=%1d",c.eos,pp_lsntw_fwd_eos);
          $display("  pbs_id : exp=%1d seen=%1d",c.pbs_id,pp_lsntw_fwd_pbs_id);

          error_ls_fwd <= 1;
        end
      end

    end
  end

  // last stage ---------------------------------------------------------------------------
  always_ff @(posedge clk) begin : checker_ls
    logic     [OP_W-1:0] data_ls;
    control_t            c;

    if (~s_rst_n) begin
      error_ls <= 0;
    end else begin
      if (pp_lsntw_avail) begin
        c           = ctrl_ls_q.pop_front();
        data_ls = data_ls_q.pop_front();

        // checking data
        assert ((data_ls == pp_lsntw_data)) begin
          valid_ls_cnt = valid_ls_cnt + 1;
        end else begin
          $display("%t > ERROR: ls Stage : data mismatch. exp=0x%0x seen=0x%0x", $time,data_ls, pp_lsntw_data);
          error_ls <= 1;
        end

        // checking control
        assert ((pp_lsntw_sob == c.sob)
              && (pp_lsntw_eob == c.eob)
              && (pp_lsntw_sol == c.sol)
              && (pp_lsntw_eol == c.eol)
              && (pp_lsntw_sos == c.sos)
              && (pp_lsntw_eos == c.eos)
              && (pp_lsntw_pbs_id == c.pbs_id))
        else begin
          $display("%t > ERROR: ls Stage : control mismatch",$time);
          $display("  sob : exp=%1d seen=%1d",c.sob,pp_lsntw_sob);
          $display("  eob : exp=%1d seen=%1d",c.eob,pp_lsntw_eob);
          $display("  sol : exp=%1d seen=%1d",c.sol,pp_lsntw_sol);
          $display("  eol : exp=%1d seen=%1d",c.eol,pp_lsntw_eol);
          $display("  sos : exp=%1d seen=%1d",c.sos,pp_lsntw_sos);
          $display("  eos : exp=%1d seen=%1d",c.eos,pp_lsntw_eos);
          $display("  pbs_id : exp=%1d seen=%1d",c.pbs_id,pp_lsntw_pbs_id);

          error_ls <= 1;
        end
      end

    end
  end

  // ============================================================================================ //
  // End of test management
  // ============================================================================================ //

  initial begin
    end_of_test = 0;

    // input queue
    wait (data_in_q.size() == 0);
    wait (ctrl_in_q.size() == 0);

    // reference queue
    wait (data_rs_q.size() == 0);
    wait (ctrl_rs_q.size() == 0);
    wait (data_ls_bwd_q.size() == 0);
    wait (ctrl_ls_bwd_q.size() == 0);
    wait (data_ls_fwd_q.size() == 0);
    wait (ctrl_ls_fwd_q.size() == 0);
    wait (data_ls_q.size() == 0);
    wait (ctrl_ls_q.size() == 0);

    $display("%t > INFO: ---------------------------------------------------------------------------------", $time);
    $display("%t > INFO: %4d chunk of last stage bwd tested are valid", $time, valid_ls_bwd_cnt);
    $display("%t > INFO: %4d chunk of last stage fwd tested are valid", $time, valid_ls_fwd_cnt);
    $display("%t > INFO: %4d chunk of regular stage tested are valid", $time, valid_rs_cnt);
    $display("%t > INFO: %4d chunk of last stage tested are valid", $time, valid_ls_cnt);
    $display("%t > INFO: ---------------------------------------------------------------------------------", $time);

    @(posedge clk);
    end_of_test = 1'b1;
  end

endmodule
