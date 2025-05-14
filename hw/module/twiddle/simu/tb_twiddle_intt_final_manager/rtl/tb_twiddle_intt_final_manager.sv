// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This bench tests the twiddle_intt_final_manager.
// ==============================================================================================

`include "ntt_core_common_macro_inc.sv"

module tb_twiddle_intt_final_manager;
  `timescale 1ns/10ps

  import pep_common_param_pkg::*;

  parameter  int OP_W         = 32;
  parameter  int ROM_LATENCY  = 1;
  parameter  int R            = 8;
  parameter  int PSI          = 8;
  parameter  int S            = 3;

  // ============================================================================================ //
  // localparam
  // ============================================================================================ //
  `NTT_CORE_LOCALPARAM(R,S,PSI)

  localparam int    CLK_HALF_PERIOD  = 1;
  localparam int    ARST_ACTIVATION  = 17;

  localparam string FILE_TWD_PREFIX  = "input/data";
  localparam int    BATCH_FULL_BW_NB = 100;
  localparam int    BATCH_RAND_BW_NB = 100;
  localparam int    BATCH_NB         = BATCH_FULL_BW_NB + BATCH_RAND_BW_NB;

  // ============================================================================================ //
  // Type
  // ============================================================================================ //
  typedef struct packed {
    logic [STG_ITER_W-1:0] stg_iter;
    logic [R_W+PSI_W-1:0]  pos;
  } data_t;

  localparam int DATA_W = $bits(data_t);

  // ============================================================================================ //
  // clock, reset
  // ============================================================================================ //
  bit clk;
  bit a_rst_n;  // asynchronous reset
  bit s_rst_n;  // synchronous reset

  initial begin
    clk     = 1'b0;
    a_rst_n = 1'b0;  // active reset
    #ARST_ACTIVATION a_rst_n = 1'b1;  // disable reset
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
    @(posedge clk) begin
      $display("%t > INFO : Launching w/ PSI = %0d, R = %0d", $time, PSI, R);
      $display("%t > SUCCEED !", $time);
    end
    $finish;
  end

  // ============================================================================================ //
  // Error
  // ============================================================================================ //
  bit error;
  bit error_data;
  bit error_valid;

  assign error = error_data | error_valid;

  always_ff @(posedge clk)
    if (error) begin
      $display("%t > FAILURE !", $time);
      $finish;
    end

  // ============================================================================================ //
  // input / output signals
  // ============================================================================================ //
  // Output to NTT core
  logic [PSI-1:0][R-1:0][OP_W-1:0] twd_intt_final;
  logic [PSI-1:0][R-1:0]           twd_intt_final_vld;
  logic [PSI-1:0][R-1:0]           twd_intt_final_rdy;

  // ============================================================================================ //
  // Design under test instance
  // ============================================================================================ //
  twiddle_intt_final_manager #(
    .FILE_TWD_PREFIX    (FILE_TWD_PREFIX),
    .OP_W               (OP_W),
    .ROM_LATENCY        (ROM_LATENCY),
    .R                  (R),
    .S                  (S),
    .PSI                (PSI)
  ) dut (
    .clk                (clk),
    .s_rst_n            (s_rst_n),

    .twd_intt_final     (twd_intt_final),
    .twd_intt_final_vld (twd_intt_final_vld),
    .twd_intt_final_rdy (twd_intt_final_rdy)
  );

  // ============================================================================================ //
  // Stimuli
  // ============================================================================================ //
  // Build the stimuli.
  logic   [OP_W-1:0] data_ref_q[           $];
  integer            pbs_nb_a  [BATCH_NB-1:0];

  initial begin

    // Output data + ctrl
    for (int batch_id = 0; batch_id < BATCH_NB; batch_id = batch_id + 1) begin
      int pbs_nb;
      pbs_nb             = $urandom_range(BATCH_PBS_NB, 1);
      pbs_nb_a[batch_id] = pbs_nb;
      for (int pbs_id = 0; pbs_id < pbs_nb; pbs_id = pbs_id + 1) begin
        for (int stg_iter = 0; stg_iter < STG_ITER_NB; stg_iter = stg_iter + 1) begin
          for (int p = 0; p < PSI; p = p + 1) begin
            for (int r = 0; r < R; r = r + 1) begin
              data_t d;
              d.pos      = r + p * R;
              d.stg_iter = stg_iter;
              data_ref_q.push_back(d);
              //$display("REF DATA pbs_id=%1d data[%2d][%2d][%1d][%2d] : 0x%08x",pbs_id, ntt_bwd, stg, stg_iter, r+p*R, d);
            end
          end
        end  // stg_iter
      end  // pbs_id
    end  // batch_id
  end

  // ============================================================================================ //
  // Scenario
  // ============================================================================================ //
  // The scenario is the following :
  // - Fill the RAM
  // - Read with 100% throughput
  // - Read with random accesses
  typedef enum {
    ST_IDLE,
    ST_WAIT_STABLE,
    ST_FULL_BW,
    ST_RAND_BW,
    ST_DONE,
    XXX
  } state_e;

  state_e state;
  state_e next_state;
  logic   start;
  integer batch_id;
  integer batch_idD;
  logic   proc_batch_last;
  integer wait_cnt;
  integer wait_cntD;

  always_ff @(posedge clk) begin
    if (!s_rst_n) state <= ST_IDLE;
    else state <= next_state;
  end

  always_comb begin
    case (state)
      ST_IDLE: next_state = start ? ST_WAIT_STABLE : state;
      ST_WAIT_STABLE:  // Wait for the first reading to be ready
      next_state = (wait_cnt == ROM_LATENCY + 1) ? ST_FULL_BW : state;
      ST_FULL_BW:
      next_state = (proc_batch_last && batch_id == BATCH_FULL_BW_NB - 1) ? ST_RAND_BW : state;
      ST_RAND_BW: next_state = (proc_batch_last && batch_id == BATCH_NB - 1) ? ST_DONE : state;
      ST_DONE: next_state = state;
      default: next_state = XXX;
    endcase
  end

  logic st_idle;
  logic st_wait_stable;
  logic st_full_bw;
  logic st_rand_bw;
  logic st_done;

  assign st_idle        = state == ST_IDLE;
  assign st_wait_stable = state == ST_WAIT_STABLE;
  assign st_full_bw     = state == ST_FULL_BW;
  assign st_rand_bw     = state == ST_RAND_BW;
  assign st_done        = state == ST_DONE;

  // ============================================================================================ //
  // Counters
  // ============================================================================================ //
  int   stg_iter;
  int   stg_iterD;
  int   pbs_id;
  int   pbs_idD;
  logic last_stg_iter;
  logic last_pbs_id;

  assign stg_iterD = (twd_intt_final_vld[0][0] && twd_intt_final_rdy[0][0]) ?
      last_stg_iter ? 0 : stg_iter + 1 : stg_iter;
  assign batch_idD = proc_batch_last ? batch_id + 1 : batch_id;
  assign pbs_idD = (twd_intt_final_vld[0][0] && twd_intt_final_rdy[0][0] & last_stg_iter) ?
      last_pbs_id ? 0 : pbs_id + 1 : pbs_id;

  assign last_stg_iter = (stg_iter == STG_ITER_NB - 1);
  assign last_pbs_id = (pbs_id == pbs_nb_a[batch_id] - 1);

  assign proc_batch_last = twd_intt_final_vld[0][0] & twd_intt_final_rdy[0][0] & last_stg_iter &
      last_pbs_id;

  assign wait_cntD = st_wait_stable ? wait_cnt + 1 : wait_cnt;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      batch_id <= 0;
      stg_iter <= 0;
      pbs_id   <= 0;
      wait_cnt <= 0;
    end else begin
      batch_id <= batch_idD;
      stg_iter <= stg_iterD;
      pbs_id   <= pbs_idD;
      wait_cnt <= wait_cntD;
    end

  // ============================================================================================ //
  // Output
  // ============================================================================================ //
  logic rand_rdy;
  logic twd_intt_final_rdy_tmp;
  logic twd_intt_final_rdy_dly;

  always_ff @(posedge clk) begin
    if (!s_rst_n) rand_rdy <= 0;
    else rand_rdy <= $urandom_range(1);
  end

  always_ff @(posedge clk) begin
    if (!s_rst_n) twd_intt_final_rdy_dly <= 0;
    else twd_intt_final_rdy_dly <= twd_intt_final_rdy[0][0];
  end

  assign twd_intt_final_rdy_tmp = st_full_bw ? 1'b1 : st_rand_bw ? rand_rdy : 1'b0;
  // leave at least 1 idle cycle between 2 ready. It modelizes the GLWE_K_P1 cycles between
  // 2 ready.
  assign twd_intt_final_rdy     = {PSI * R{twd_intt_final_rdy_tmp & ~twd_intt_final_rdy_dly}};

  // ============================================================================================ //
  // Check
  // ============================================================================================ //
  always_ff @(posedge clk) begin
    if (!s_rst_n) error_data <= 0;
    else begin
      logic [PSI-1:0][R-1:0][OP_W-1:0] ref_data;
      if (twd_intt_final_vld[0][0] && twd_intt_final_rdy[0][0]) begin
        for (int p = 0; p < PSI; p = p + 1)
          for (int r = 0; r < R; r = r + 1) ref_data[p][r] = data_ref_q.pop_front();
        assert (twd_intt_final == ref_data)
        else begin
          $display("%t > ERROR: Output data mismatch.", $time);
          for (int p = 0; p < PSI; p = p + 1)
            for (int r = 0; r < R; r = r + 1)
              $display(
                  "  data[%2d][%2d] : exp=0x%08x seen=0x%08x",
                  p,
                  r,
                  ref_data[p][r],
                  twd_intt_final[p][r]
              );
          error_data <= 1;
        end
      end
    end
  end

  logic twd_vld_seen;
  logic twd_vld_seenD;

  assign twd_vld_seenD = twd_intt_final_vld ? 1'b1 : twd_vld_seen;

  always_ff @(posedge clk)
    if (!s_rst_n) twd_vld_seen <= 1'b0;
    else          twd_vld_seen <= twd_vld_seenD;

  always_ff @(posedge clk) begin
    if (!s_rst_n) error_valid <= 0;
    else begin
      if (twd_intt_final_rdy != '0) begin
        assert (twd_intt_final_vld == {PSI * R{1'b1}})
        else begin
          $display("%t > ERROR: Twiddles not valid, while output needs them.", $time);
          error_valid <= 1;
        end
      end
      if (twd_vld_seen) begin
        assert(twd_intt_final_vld)
        else begin
          $display("%t > ERROR: Twiddles' valid not maintained.", $time);
          error_valid <= 1;
        end
      end
    end
  end

  // ============================================================================================ //
  // End of test
  // ============================================================================================ //
  initial begin
    end_of_test = 0;
    wait (st_done);
    @(posedge clk);
    wait (data_ref_q.size() == 0);
    @(posedge clk);
    end_of_test = 1'b1;
  end

  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      start <= 1'b0;
    end else begin
      start <= 1'b1;
    end
  end

endmodule
