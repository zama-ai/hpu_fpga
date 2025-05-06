// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// "Balanced decomposition with unfixed sign and rounding bit" testbench.
//
// ==============================================================================================

module tb_decomp_balanced_sequential;

`timescale 1ns/100ps

  import common_definition_pkg::*;
  import pep_common_param_pkg::*;
  import param_tfhe_pkg::*;
  import param_ntt_pkg::*;
  import ntt_core_common_param_pkg::*;
// ============================================================================================== --
// parameter
// ============================================================================================== --
  parameter int CHUNK_NB = PBS_L;

  parameter int BATCH_NB = 1000;

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int CLK_HALF_PERIOD = 1;
  localparam int ARST_ACTIVATION = 17;

  localparam int ACC_DECOMP_COEF_NB = (PSI*R + CHUNK_NB-1)/CHUNK_NB;
  localparam int IN_PERIOD   = (PBS_L + CHUNK_NB-1) / CHUNK_NB;

// ============================================================================================== --
// function
// ============================================================================================== --
  function logic [PBS_L-1:0][PBS_B_W:0] decomp (logic[MOD_Q_W-1:0] v);
    var [(PBS_L+1)*PBS_B_W-1:0] state;
    var [PBS_B_W:0]             res;
    var                         frac;
    var                         carry;

    frac  = v[MOD_Q_W-1-PBS_L*PBS_B_W];
    state = v[MOD_Q_W-1-:PBS_L*PBS_B_W] + frac;

    if ((state > ((PBS_B**PBS_L)/2)) || ((state == ((PBS_B**PBS_L)/2)) && frac))
      state = state - (PBS_B**PBS_L);


    //$display("v=0x%0x state=0x%x",v,state);
    for (int i=0; i<PBS_L; i=i+1) begin
      res = {1'b0,state[0+:PBS_B_W]};
      state = (state - res) >> PBS_B_W;
      carry = 1'b0;
      if ((res > (PBS_B/2)) || ((res == (PBS_B/2)) && (state[PBS_B_W-1:0] >=(PBS_B/2)))) begin
        carry = 1'b1;
        state = state + carry;
        res = res - PBS_B;
        //$display("         carry decomp[%0d]=0x%0x state=0x%0x",i,res,state);
      end
      decomp[i] = res;
      //$display("         decomp[%0d]=0x%0x state=0x%0x",i,res,state);

    end

  endfunction

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
  bit error_decomp;
  bit error_side;
  bit error_data;

  assign error = error_decomp
                | error_side
                | error_data;

  always_ff @(posedge clk)
    if (error) begin
      $display("%t > FAILURE !", $time);
      $finish;
    end

// ============================================================================================== --
// input / output signals
// ============================================================================================== --
  // ACC <> Decomposer
  logic                                       acc_decomp_ctrl_avail;
  logic [ACC_DECOMP_COEF_NB-1:0]              acc_decomp_data_avail;
  logic [ACC_DECOMP_COEF_NB-1:0][MOD_Q_W-1:0] acc_decomp_data;
  logic                                       acc_decomp_sob;
  logic                                       acc_decomp_eob;
  logic                                       acc_decomp_sog;
  logic                                       acc_decomp_eog;
  logic                                       acc_decomp_sol;
  logic                                       acc_decomp_eol;
  logic                                       acc_decomp_soc;
  logic                                       acc_decomp_eoc;
  logic [BPBS_ID_W-1:0]                       acc_decomp_pbs_id;
  logic                                       acc_decomp_last_pbs;
  logic                                       acc_decomp_full_throughput;

  // Decomposer <> NTT
  logic                                       decomp_ntt_ctrl_avail;
  logic [PSI-1:0][R-1:0]                      decomp_ntt_data_avail;
  logic [PSI-1:0][R-1:0][PBS_B_W:0]           decomp_ntt_data; // 2s complement
  logic                                       decomp_ntt_sob;
  logic                                       decomp_ntt_eob;
  logic                                       decomp_ntt_sog;
  logic                                       decomp_ntt_eog;
  logic                                       decomp_ntt_sol;
  logic                                       decomp_ntt_eol;
  logic [BPBS_ID_W-1:0]                       decomp_ntt_pbs_id;
  logic                                       decomp_ntt_last_pbs;
  logic                                       decomp_ntt_full_throughput;


// ============================================================================================== --
// Design under test instance
// ============================================================================================== --
  decomp_balanced_sequential #(
    .CHUNK_NB (CHUNK_NB)
  ) dut (
    .clk                        (clk),
    .s_rst_n                    (s_rst_n),

    .acc_decomp_ctrl_avail      (acc_decomp_ctrl_avail),
    .acc_decomp_data_avail      (acc_decomp_data_avail),
    .acc_decomp_data            (acc_decomp_data),
    .acc_decomp_sob             (acc_decomp_sob),
    .acc_decomp_eob             (acc_decomp_eob),
    .acc_decomp_sog             (acc_decomp_sog),
    .acc_decomp_eog             (acc_decomp_eog),
    .acc_decomp_sol             (acc_decomp_sol),
    .acc_decomp_eol             (acc_decomp_eol),
    .acc_decomp_soc             (acc_decomp_soc),
    .acc_decomp_eoc             (acc_decomp_eoc),
    .acc_decomp_pbs_id          (acc_decomp_pbs_id),
    .acc_decomp_last_pbs        (acc_decomp_last_pbs),
    .acc_decomp_full_throughput (acc_decomp_full_throughput),


    .decomp_ntt_ctrl_avail      (decomp_ntt_ctrl_avail),
    .decomp_ntt_data_avail      (decomp_ntt_data_avail),
    .decomp_ntt_data            (decomp_ntt_data),
    .decomp_ntt_sob             (decomp_ntt_sob),
    .decomp_ntt_eob             (decomp_ntt_eob),
    .decomp_ntt_sog             (decomp_ntt_sog),
    .decomp_ntt_eog             (decomp_ntt_eog),
    .decomp_ntt_sol             (decomp_ntt_sol),
    .decomp_ntt_eol             (decomp_ntt_eol),
    .decomp_ntt_pbs_id          (decomp_ntt_pbs_id),
    .decomp_ntt_last_pbs        (decomp_ntt_last_pbs),
    .decomp_ntt_full_throughput (decomp_ntt_full_throughput),

    .error                      (error_decomp)
  );

// ============================================================================================== --
// Scenario
// ============================================================================================== --
  //------------------
  // Input counters
  //------------------
  bit in_avail;
  int in_chunk_cnt;
  int in_poly_cnt;
  int in_stg_iter_cnt;
  int in_ct_cnt;
  int in_batch_cnt;

  bit first_in_chunk_cnt;
  bit first_in_poly_cnt;
  bit first_in_stg_iter_cnt;
  bit first_in_ct_cnt;

  bit last_in_chunk_cnt;
  bit last_in_poly_cnt;
  bit last_in_stg_iter_cnt;
  bit last_in_ct_cnt;

  assign first_in_chunk_cnt    = in_chunk_cnt == 0;
  assign first_in_poly_cnt     = in_poly_cnt == 0;
  assign first_in_stg_iter_cnt = in_stg_iter_cnt == 0;
  assign first_in_ct_cnt       = in_ct_cnt == 0;

  assign last_in_chunk_cnt     = in_chunk_cnt == CHUNK_NB-1;
  assign last_in_poly_cnt      = in_poly_cnt == GLWE_K_P1-1;
  assign last_in_stg_iter_cnt  = in_stg_iter_cnt == STG_ITER_NB-1;
  assign last_in_ct_cnt        = in_ct_cnt == BATCH_PBS_NB-1;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      in_chunk_cnt    <= '0;
      in_poly_cnt     <= '0;
      in_stg_iter_cnt <= '0;
      in_ct_cnt       <= '0;
      in_batch_cnt    <= '0;
    end
    else begin
      in_chunk_cnt    <= in_avail ? last_in_chunk_cnt ? '0 : in_chunk_cnt + 1: in_chunk_cnt;
      in_poly_cnt     <= in_avail && last_in_chunk_cnt ? last_in_poly_cnt  ? '0 : in_poly_cnt + 1 : in_poly_cnt;
      in_stg_iter_cnt <= in_avail && last_in_chunk_cnt && last_in_poly_cnt? last_in_stg_iter_cnt ? '0 : in_stg_iter_cnt + 1 : in_stg_iter_cnt;
      in_ct_cnt       <= in_avail && last_in_chunk_cnt && last_in_poly_cnt && last_in_stg_iter_cnt? last_in_ct_cnt    ? '0 : in_ct_cnt + 1 : in_ct_cnt;
      in_batch_cnt    <= in_avail && last_in_chunk_cnt && last_in_poly_cnt && last_in_stg_iter_cnt && last_in_ct_cnt ? in_batch_cnt + 1 : in_batch_cnt;
    end

  //------------------
  // Output counters
  //------------------
  bit out_avail;
  int out_level_cnt;
  int out_stg_iter_cnt;
  int out_ct_cnt;
  int out_batch_cnt;

  bit first_out_level_cnt;
  bit first_out_stg_iter_cnt;
  bit first_out_ct_cnt;

  bit last_out_level_cnt;
  bit last_out_stg_iter_cnt;
  bit last_out_ct_cnt;

  assign first_out_level_cnt    = out_level_cnt == 0;
  assign first_out_stg_iter_cnt = out_stg_iter_cnt == 0;
  assign first_out_ct_cnt       = out_ct_cnt == 0;

  assign last_out_level_cnt     = out_level_cnt == PBS_L*GLWE_K_P1-1;
  assign last_out_stg_iter_cnt  = out_stg_iter_cnt == STG_ITER_NB-1;
  assign last_out_ct_cnt        = out_ct_cnt == BATCH_PBS_NB-1;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      out_level_cnt    <= '0;
      out_stg_iter_cnt <= '0;
      out_ct_cnt       <= '0;
      out_batch_cnt    <= '0;
    end
    else begin
      out_level_cnt    <= out_avail ? last_out_level_cnt ? '0 : out_level_cnt + 1: out_level_cnt;
      out_stg_iter_cnt <= out_avail && last_out_level_cnt? last_out_stg_iter_cnt ? '0 : out_stg_iter_cnt + 1 : out_stg_iter_cnt;
      out_ct_cnt       <= out_avail && last_out_level_cnt && last_out_stg_iter_cnt? last_out_ct_cnt    ? '0 : out_ct_cnt + 1 : out_ct_cnt;
      out_batch_cnt    <= out_avail && last_out_level_cnt && last_out_stg_iter_cnt && last_out_ct_cnt ? out_batch_cnt + 1 : out_batch_cnt;
    end

  //------------------
  // Random
  //------------------
  // Send an input at most every PBS_L / CHUNK_NB cycles.
  int in_cycle;
  bit in_send_ok;
  bit in_cycle_max;
  bit max_throughput;

  assign in_cycle_max = in_cycle == (IN_PERIOD-1);
  assign in_send_ok   = in_cycle_max & (in_batch_cnt < BATCH_NB);
  assign max_throughput = in_batch_cnt < BATCH_NB/2;

  always_ff @(posedge clk)
    if (!s_rst_n) in_cycle <= '0;
    else          in_cycle <= in_avail ? '0:
                              in_cycle_max ? in_cycle : in_cycle + 1;


  logic [ACC_DECOMP_COEF_NB-1:0][MOD_Q_W-1:0] rand_in_data;
  bit rand_in_avail;

  always_ff @(posedge clk)
    rand_in_avail <= $urandom_range(1);

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      for (int i=0; i<ACC_DECOMP_COEF_NB; i=i+1)
        rand_in_data[i] <= i;
    end
    else begin
      for (int i=0; i<ACC_DECOMP_COEF_NB; i=i+1)
        if (MOD_Q_W <= 16)
          rand_in_data[i] <= in_avail ? rand_in_data[i] + ACC_DECOMP_COEF_NB : rand_in_data[i]; // decompose all values
        else
          rand_in_data[i] <= {$urandom(),$urandom()};
    end

  assign in_avail = max_throughput ? in_send_ok : rand_in_avail & in_send_ok;

  assign acc_decomp_data      = rand_in_data;
  assign acc_decomp_ctrl_avail= in_avail;
  assign acc_decomp_data_avail= {ACC_DECOMP_COEF_NB{in_avail}};
  assign acc_decomp_sob       = first_in_chunk_cnt & first_in_poly_cnt & first_in_stg_iter_cnt & first_in_ct_cnt;
  assign acc_decomp_eob       = last_in_chunk_cnt & last_in_poly_cnt & last_in_stg_iter_cnt & last_in_ct_cnt;
  assign acc_decomp_sog       = first_in_chunk_cnt & first_in_poly_cnt & first_in_stg_iter_cnt;
  assign acc_decomp_eog       = last_in_chunk_cnt & last_in_poly_cnt & last_in_stg_iter_cnt;
  assign acc_decomp_sol       = first_in_chunk_cnt & first_in_poly_cnt;
  assign acc_decomp_eol       = last_in_chunk_cnt & last_in_poly_cnt;
  assign acc_decomp_soc       = first_in_chunk_cnt;
  assign acc_decomp_eoc       = last_in_chunk_cnt;
  assign acc_decomp_pbs_id    = in_ct_cnt;
  assign acc_decomp_last_pbs  = last_in_ct_cnt;
  assign acc_decomp_full_throughput = 1'b1;

  //------------------
  // Reference
  //------------------
  logic                 ref_sob;
  logic                 ref_eob;
  logic                 ref_sog;
  logic                 ref_eog;
  logic                 ref_sol;
  logic                 ref_eol;
  logic [BPBS_ID_W-1:0] ref_pbs_id;
  logic                 ref_last_pbs;
  logic                 ref_full_throughput;

  assign ref_sob             = first_out_ct_cnt & first_out_stg_iter_cnt & first_out_level_cnt;
  assign ref_eob             = last_out_ct_cnt & last_out_stg_iter_cnt & last_out_level_cnt;
  assign ref_sog             = first_out_stg_iter_cnt & first_out_level_cnt;
  assign ref_eog             = last_out_stg_iter_cnt & last_out_level_cnt;
  assign ref_sol             = first_out_level_cnt;
  assign ref_eol             = last_out_level_cnt;
  assign ref_pbs_id          = out_ct_cnt;
  assign ref_last_pbs        = last_out_ct_cnt;
  assign ref_full_throughput = 1'b1;

  // Data
  logic [PBS_B_W:0] ref_data_q[R*PSI-1:0][$];

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // Do nothing
    end
    else begin
      if (acc_decomp_ctrl_avail) begin
        for (int i=0; i<ACC_DECOMP_COEF_NB; i=i+1) begin
          int idx;
          idx = in_chunk_cnt * ACC_DECOMP_COEF_NB + i;
          if (idx < R*PSI) begin
            var [PBS_L-1:0][PBS_B_W:0] val_a;
            val_a = decomp(acc_decomp_data[i]);
            for (int j=0; j<PBS_L; j=j+1)
              ref_data_q[idx].push_back(val_a[j]);
          end
        end
      end
    end

  assign out_avail = decomp_ntt_ctrl_avail;

  //------------------
  // Check
  //------------------
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      error_data <= 1'b0;
      error_side <= 1'b0;
    end
    else begin
      if (decomp_ntt_ctrl_avail) begin
        assert(  (decomp_ntt_sob == ref_sob)
              && (decomp_ntt_eob == ref_eob)
              && (decomp_ntt_sog == ref_sog)
              && (decomp_ntt_eog == ref_eog)
              && (decomp_ntt_sol == ref_sol)
              && (decomp_ntt_eol == ref_eol)
              && (decomp_ntt_pbs_id == ref_pbs_id)
              && (decomp_ntt_last_pbs == ref_last_pbs)
              && (decomp_ntt_full_throughput == ref_full_throughput))
        else begin
          $display("%t > ERROR: Side mismatch.",$time);
          $display("%t >        exp :  sob=%0d eob=%0d sog=%0d eog=%0d sol=%0d eol=%0d pbs_id=%0d last_pbs=%0d full_throughput=%0d",
                          $time, ref_sob, ref_eob, ref_sog, ref_eog, ref_sol, ref_eol, ref_pbs_id, ref_last_pbs, ref_full_throughput);
          $display("%t >        seen : sob=%0d eob=%0d sog=%0d eog=%0d sol=%0d eol=%0d pbs_id=%0d last_pbs=%0d full_throughput=%0d",
                          $time, decomp_ntt_sob, decomp_ntt_eob, decomp_ntt_sog, decomp_ntt_eog, decomp_ntt_sol, decomp_ntt_eol,
                          decomp_ntt_pbs_id, decomp_ntt_last_pbs, decomp_ntt_full_throughput);
          error_side <= 1'b1;
        end

        for (int p=0; p<PSI; p=p+1) begin
          for (int r=0; r<R; r=r+1) begin
            var [PBS_B_W:0] ref_val;
            ref_val = ref_data_q[p*R+r].pop_front();
            assert(decomp_ntt_data[p][r] == ref_val)
            else begin
              $display("%t > ERROR: Data mismatch: exp=0x%0x seen=0x%0x.",$time,ref_val,decomp_ntt_data[p][r]);
              error_data <= 1'b1;
            end
          end
        end

      end
    end

// ============================================================================================== --
// End of test
// ============================================================================================== --
  initial begin
    end_of_test <= 1'b0;

    wait(s_rst_n);
    @(posedge clk);
    wait(out_batch_cnt == BATCH_NB);
    repeat(10) @(posedge clk);
    end_of_test <= 1'b1;
  end

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // Do nothing
    end
    else begin
      if (decomp_ntt_ctrl_avail && decomp_ntt_eob && (out_batch_cnt%100) == 0)
        $display("%t > INFO: Run %0d batches.",$time,out_batch_cnt);
    end

endmodule
