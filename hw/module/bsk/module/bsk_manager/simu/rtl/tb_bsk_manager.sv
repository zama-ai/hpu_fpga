// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Bench testing bsk_manager, as if this latter could contain all the BSK slices.
// ==============================================================================================

`include "ntt_core_common_macro_inc.sv"

module tb_bsk_manager;
`timescale 1ns/10ps

  import param_tfhe_pkg::*;
  import top_common_param_pkg::*;
  import ntt_core_common_param_pkg::*;
  import bsk_mgr_common_param_pkg::*;
  import pep_common_param_pkg::*;

// ============================================================================================== --
// localparam
// ============================================================================================== --
  parameter int OP_W            = 32;
  parameter int RAM_LATENCY     = 1;

// ============================================================================================== --
// localparam
// ============================================================================================== --
  `NTT_CORE_LOCALPARAM(R,S,PSI)

  localparam int CLK_HALF_PERIOD = 1;
  localparam int ARST_ACTIVATION = 17;

  localparam int PROC_BATCH_NB  = 100;
  localparam int BSK_ERROR_NB   = 1;
  localparam int CMD_FIFO_DEPTH = TOTAL_BATCH_NB;

  localparam int FIFO_REG_DLY   = (2+1) + (1 + RAM_LATENCY + 1) + 1; // cmd FIFO  + read in RAM + input pipe

// ============================================================================================== --
// Type
// ============================================================================================== --
  typedef struct packed {
    logic [LWE_K_W-1:0]     br_loop;
    logic [GLWE_K_P1_W-1:0] glwe_idx;
    logic [STG_ITER_W-1:0]  stg_iter;
    logic [INTL_L_W-1:0]    intl_idx;
    logic [PSI_W-1:0]       p;
    logic [R_W-1:0]         r;
  } data_t;

  typedef struct packed {
    logic [BSK_RAM_ADD_W-1:0] wr_add;
    logic [GLWE_K_P1_W-1:0]   glwe_idx;
    logic [BSK_SLOT_W-1:0]    slot;
    logic [LWE_K_W-1:0]       br_loop;
  } wr_ctrl_t;

  localparam int DATA_W = $bits(data_t);

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
  bit error_valid;
  pep_bsk_error_t bsk_error;

  assign error = error_data | error_valid | |bsk_error;

  always_ff @(posedge clk)
    if (error) begin
      $display("%t > FAILURE !", $time);
      $finish;
    end

// ============================================================================================== --
// input / output signals
// ============================================================================================== --

  logic [PSI-1:0][R-1:0][GLWE_K_P1-1:0][OP_W-1:0]  bsk;
  logic [PSI-1:0][R-1:0][GLWE_K_P1-1:0]            bsk_vld;
  logic [PSI-1:0][R-1:0][GLWE_K_P1-1:0]            bsk_rdy;
  // Broadcast from acc
  logic [BR_BATCH_CMD_W-1:0]                       batch_cmd;
  logic                                            batch_cmd_avail;

  // Write interface
  logic [BSK_CUT_NB-1:0]                                 wr_en;
  logic [BSK_CUT_NB-1:0][BSK_CUT_FCOEF_NB-1:0][OP_W-1:0] wr_data;
  logic [BSK_CUT_NB-1:0][BSK_RAM_ADD_W-1:0]              wr_add;
  logic [BSK_CUT_NB-1:0][GLWE_K_P1_W-1:0]                wr_g_idx;
  logic [BSK_CUT_NB-1:0][BSK_SLOT_W-1:0]                 wr_slot;
  logic [BSK_CUT_NB-1:0][LWE_K_W-1:0]                    wr_br_loop;

  logic                                             reset_cache;

// ============================================================================================== --
// Design under test instance
// ============================================================================================== --
  assign reset_cache = 1'b0; // Not tested here.

  bsk_manager #(
    .OP_W       (OP_W),
    .RAM_LATENCY(RAM_LATENCY)
  ) dut (
    .clk            (clk            ),
    .s_rst_n        (s_rst_n        ),

    .reset_cache    (reset_cache    ),

    .bsk            (bsk            ),
    .bsk_vld        (bsk_vld        ),
    .bsk_rdy        (bsk_rdy        ),

    .batch_cmd      (batch_cmd      ),
    .batch_cmd_avail(batch_cmd_avail),

    .wr_en          (wr_en          ),
    .wr_data        (wr_data        ),
    .wr_add         (wr_add         ),
    .wr_g_idx       (wr_g_idx       ),
    .wr_slot        (wr_slot        ),
    .wr_br_loop     (wr_br_loop     ),

    .bsk_mgr_error  (bsk_error      )

  );

// ============================================================================================== --
// Stimuli
// ============================================================================================== --
// Build the stimuli.
  logic [OP_W-1:0] wr_data_q[BSK_CUT_NB-1:0][$];
  wr_ctrl_t        wr_ctrl_q[BSK_CUT_NB-1:0][$];
  logic [OP_W-1:0] data_ref_q[GLWE_K_P1-1:0][$];
  br_batch_cmd_t   batch_cmd_q[$];
  br_batch_cmd_t batch_cmd_a [PROC_BATCH_NB-1:0];

  initial begin
    // Write data
    for (int br_loop=0; br_loop<LWE_K; br_loop=br_loop+1) begin
      for (int stg_iter=0; stg_iter<STG_ITER_NB; stg_iter=stg_iter+1) begin
        for (int intl_idx=0; intl_idx<INTL_L; intl_idx=intl_idx+1) begin
          for (int glwe_idx=0; glwe_idx<GLWE_K_P1; glwe_idx=glwe_idx+1) begin
            wr_ctrl_t c;
            c.wr_add   = br_loop*BSK_SLOT_DEPTH + stg_iter*INTL_L + intl_idx;
            c.glwe_idx = glwe_idx;
            c.slot     = br_loop; // TODO : set a constrained random value
            c.br_loop  = br_loop;
            for (int cut=0; cut<BSK_CUT_NB; cut=cut+1) begin
              wr_ctrl_q[cut].push_back(c);
              //$display("WR CTRL cut=%0d ctrl[%2d][%2d][%2d][%2d] : 0x%08x",cut, c.wr_add, glwe_idx,br_loop, br_loop, c);
              for (int i=0; i<BSK_CUT_FCOEF_NB; i=i+1) begin
                integer p;
                integer r;
                data_t d;
                p = (cut*BSK_CUT_FCOEF_NB + i) / R;
                r = (cut*BSK_CUT_FCOEF_NB + i) % R;
                d.br_loop  = br_loop;
                d.glwe_idx = glwe_idx;
                d.stg_iter = stg_iter;
                d.intl_idx = intl_idx;
                d.p        = p;
                d.r        = r;
                wr_data_q[cut].push_back(d);
                //$display("WR DATA cut=%0d wr_data[%2d][%2d][%2d][%2d][%2d][%2d] : 0x%08x",cut,br_loop,glwe_idx,stg_iter,intl_idx,p,r,d);
              end // i
            end // c
          end// glwe_idx
        end // intl_idx
      end // stg_iter
    end// br_loop

    // Output data
    for (int batch_id=0; batch_id<PROC_BATCH_NB; batch_id=batch_id+1) begin
      int pbs_nb;
      int br_loop;
      pbs_nb  = $urandom_range(BATCH_PBS_NB,1);
      br_loop = $urandom_range(LWE_K-1);
      batch_cmd_a[batch_id].pbs_nb  = pbs_nb;
      batch_cmd_a[batch_id].br_loop = br_loop;
      batch_cmd_q.push_back(batch_cmd_a[batch_id]);
      for (int pbs_id=0; pbs_id < pbs_nb; pbs_id=pbs_id+1) begin
        for (int stg_iter=0; stg_iter<STG_ITER_NB; stg_iter=stg_iter+1) begin
          for (int intl_idx=0; intl_idx<INTL_L; intl_idx=intl_idx+1) begin
            for (int p=0; p<PSI; p=p+1) begin
              for (int r=0; r<R; r=r+1) begin
                for (int glwe_idx=0; glwe_idx<GLWE_K_P1; glwe_idx=glwe_idx+1) begin
                  data_t d;
                  d.br_loop  = br_loop;
                  d.glwe_idx = glwe_idx;
                  d.stg_iter = stg_iter;
                  d.intl_idx = intl_idx;
                  d.p        = p;
                  d.r        = r;
                  data_ref_q[glwe_idx].push_back(d);
                  //$display("REF DATA data[%2d][%2d][%2d][%2d][%2d][%2d] : 0x%08x",br_loop,glwe_idx,stg_iter,intl_idx,p,r,d);
                end // glwe
              end // r
            end // p
          end // intl_idx
        end // stg_iter
      end // pbs_id
    end // batch_id
  end // initial

// ============================================================================================== --
// Scenario
// ============================================================================================== --
// The scenario is the following :
  // - Fill the RAM
  // - Read with 100% throughput
  // - Read with random accesses
  typedef enum { ST_IDLE,
                ST_WR,
                ST_PROCESS,
                ST_DONE,
                XXX} state_e;

  state_e state;
  state_e next_state;
  logic   start;
  integer batch_id;
  integer batch_idD;
  logic   [BSK_CUT_NB-1:0] wr_last;
  logic   proc_batch_last;

  always_ff @(posedge clk) begin
    if (!s_rst_n) state <= ST_IDLE;
    else          state <= next_state;
  end

  always_comb begin
    case(state)
      ST_IDLE:
        next_state = start ? ST_WR : state;
      ST_WR:
        next_state = (wr_last == '1)? ST_PROCESS : state;
      ST_PROCESS:
        next_state = (proc_batch_last && batch_id == PROC_BATCH_NB-1) ? ST_DONE : state;
      ST_DONE:
        next_state = state;
      default:
        next_state = XXX;
   endcase
  end

  logic st_idle;
  logic st_wr;
  logic st_process;
  logic st_done;

  assign st_idle        = state == ST_IDLE;
  assign st_wr          = state == ST_WR;
  assign st_process     = state == ST_PROCESS;
  assign st_done        = state == ST_DONE;

// ============================================================================================== --
// Counters
// ============================================================================================== --
  int intl_idx;
  int intl_idxD;
  int stg_iter;
  int stg_iterD;
  int pbs_id;
  int pbs_idD;
  logic last_intl_idx;
  logic last_stg_iter;
  logic last_pbs_id;

  assign intl_idxD = (bsk_vld[0][0][0] && bsk_rdy[0][0][0]) ? last_intl_idx ? 0 : intl_idx + 1 : intl_idx;
  assign stg_iterD = (bsk_vld[0][0][0] && bsk_rdy[0][0][0] && last_intl_idx) ?
                        last_stg_iter ? 0 : stg_iter + 1 : stg_iter;
  assign batch_idD = proc_batch_last ? batch_id + 1 : batch_id;
  assign pbs_idD   = (bsk_vld[0][0][0] && bsk_rdy[0][0][0] && last_intl_idx && last_stg_iter) ?
                        last_pbs_id ? 0 : pbs_id + 1 : pbs_id;

  assign last_intl_idx = (intl_idx == INTL_L-1);
  assign last_stg_iter = (stg_iter == STG_ITER_NB-1);
  assign last_pbs_id   = (pbs_id == batch_cmd_a[batch_id].pbs_nb -1);

  assign proc_batch_last = bsk_vld[0][0][0] & bsk_rdy[0][0][0] & last_intl_idx
                           & last_stg_iter & last_pbs_id;


  always_ff @(posedge clk)
    if (!s_rst_n) begin
      batch_id <= 0;
      intl_idx <= 0;
      stg_iter <= 0;
      pbs_id   <= 0;
    end
    else begin
      batch_id <= batch_idD;
      intl_idx <= intl_idxD;
      stg_iter <= stg_iterD;
      pbs_id   <= pbs_idD;
    end

// ============================================================================================== --
// Write in RAM
// ============================================================================================== --
  generate
    for (genvar gen_c=0; gen_c<BSK_CUT_NB; gen_c=gen_c+1) begin
      logic                                  rand_wr_en;
      logic [BSK_CUT_FCOEF_NB-1:0][OP_W-1:0] wr_data_tmp;
      logic                                  wr_last_l;

      logic                                  wr_en_l;
      logic [BSK_RAM_ADD_W-1:0]              wr_add_l;
      logic [GLWE_K_P1_W-1:0]                wr_g_idx_l;
      logic [BSK_SLOT_W-1:0]                 wr_slot_l;
      logic [LWE_K_W-1:0]                    wr_br_loop_l;

      logic                                  wr_en_lD;

      always_ff @(posedge clk)
        if (!s_rst_n) rand_wr_en <= '0;
        else          rand_wr_en <= $urandom;

      assign wr_en_lD = st_wr & rand_wr_en & ~wr_last_l;

      always_ff @(posedge clk)
        if (!s_rst_n) begin
          wr_add_l  <= 0;
          wr_last_l <= 0;
          wr_en_l   <= 1'b0;
        end
        else begin
          wr_ctrl_t c;
          bit q_empty;
          wr_en_l   <= wr_en_lD;
          if (wr_en_lD) begin
            c = wr_ctrl_q[gen_c].pop_front();
            q_empty = (wr_ctrl_q[gen_c].size() == 0);
            wr_add_l      <= c.wr_add;
            wr_g_idx_l    <= c.glwe_idx;
            wr_slot_l     <= c.slot;
            wr_br_loop_l  <= c.br_loop;
            wr_last_l     <= q_empty;
          end
        end

      always_ff @(posedge clk) begin
        logic [OP_W-1:0] d;
        if (wr_en_lD) begin
          for (int p=0; p<BSK_CUT_FCOEF_NB; p=p+1) begin
              d = wr_data_q[gen_c].pop_front();
              wr_data_tmp[p] <= d;
          end
        end
      end

      assign wr_data[gen_c]    = wr_en_l ? wr_data_tmp : 'x;
      assign wr_last[gen_c]    = wr_last_l;
      assign wr_en[gen_c]      = wr_en_l;
      assign wr_add[gen_c]     = wr_add_l;
      assign wr_g_idx[gen_c]   = wr_g_idx_l;
      assign wr_slot[gen_c]    = wr_slot_l;
      assign wr_br_loop[gen_c] = wr_br_loop_l;

    end // for gen_c
  endgenerate

// ============================================================================================== --
// Output
// ============================================================================================== --
  int cmd_batch_id;
  int cmd_batch_id_dly  [FIFO_REG_DLY-1:0];
  int cmd_batch_id_dlyD [FIFO_REG_DLY-1:0];

  int rand_val;
  int rand_cmd_vld;


  assign cmd_batch_id_dlyD[0] = cmd_batch_id;
  generate
    if (FIFO_REG_DLY > 1) begin
      assign cmd_batch_id_dlyD[FIFO_REG_DLY-1:1] = cmd_batch_id_dly[FIFO_REG_DLY-2:0];
    end
  endgenerate
  always_ff @(posedge clk)
    if (!s_rst_n)
      cmd_batch_id_dly <= '{FIFO_REG_DLY{0}};
    else
      cmd_batch_id_dly <= cmd_batch_id_dlyD;


  always_ff @(posedge clk) begin
    rand_val     <= $urandom;
    rand_cmd_vld <= (rand_val & 'hFF) == 0;
  end

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      cmd_batch_id    <= 0;
      batch_cmd_avail <= 0;
    end
    else begin
      if (((cmd_batch_id - batch_id) < CMD_FIFO_DEPTH) && rand_cmd_vld && st_process && (cmd_batch_id < PROC_BATCH_NB)) begin
        batch_cmd       <= batch_cmd_a[cmd_batch_id];
        batch_cmd_avail <= 1'b1;
        if (cmd_batch_id%10 == 0)
          $display("%t > INFO: CMD batch #%0d sent.", $time, cmd_batch_id);
        cmd_batch_id    <= cmd_batch_id + 1;
      end
      else begin
        batch_cmd       <= 'x;
        batch_cmd_avail <= 1'b0;
        cmd_batch_id    <= cmd_batch_id;
      end
    end

  logic bsk_rdy_0;
  logic [GLWE_K_P1-1:0] bsk_rdy_0_sr;
  logic [GLWE_K_P1-1:0] bsk_rdy_0_srD;

  assign bsk_rdy_0_srD = {bsk_rdy_0_sr[GLWE_K_P1-2:0],bsk_rdy_0};
  always_ff @(posedge clk)
    if (!s_rst_n) bsk_rdy_0_sr <= '0;
    else          bsk_rdy_0_sr <= bsk_rdy_0_srD;

  always_comb
    for (int g=0; g<GLWE_K_P1; g=g+1)
      for (int p=0; p<PSI; p=p+1)
        for (int r=0; r<R; r=r+1)
          bsk_rdy[p][r][g] = bsk_rdy_0_srD[g];


  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      bsk_rdy_0      <= '0;
    end
    else begin
      if (st_process) begin
        logic rdy_tmp;
        if (proc_batch_last) begin
          rdy_tmp = $urandom_range(1);
          rdy_tmp = rdy_tmp & (cmd_batch_id_dly[FIFO_REG_DLY-1] > (batch_id + 1));
          bsk_rdy_0      <= rdy_tmp;
        end
        else begin
          if (bsk_rdy_0 == 0) begin
            rdy_tmp = $urandom_range(1);
            rdy_tmp = rdy_tmp & (cmd_batch_id_dly[FIFO_REG_DLY-1] > (batch_id));
            bsk_rdy_0      <= rdy_tmp;
          end
          else begin
            bsk_rdy_0      <= bsk_rdy_0;
          end
        end
      end
    end
  end

// ============================================================================================== --
// Check
// ============================================================================================== --
  always_ff @(posedge clk)
    if (!s_rst_n)
      error_data <= 0;
    else begin
      logic [OP_W-1:0] ref_data;
      for (int g=0; g<GLWE_K_P1; g=g+1)
        if (bsk_vld[0][0][g] && bsk_rdy[0][0][g])
          for (int p=0; p<PSI; p=p+1)
            for(int r=0; r<R; r=r+1) begin
              ref_data = data_ref_q[g].pop_front();
              assert(bsk[p][r][g] == ref_data)
              else begin
                $display("%t > ERROR: Output data mismatch g=%0d, p=%0d, r=%0d.  exp=0x%08x seen=0x%08x", $time, g, p, r, ref_data,bsk[p][r][g]);
                error_data <= 1;
              end
            end
    end

  always_ff @(posedge clk)
    if (!s_rst_n)
      error_valid <= 0;
    else begin
      for (int g=0; g<GLWE_K_P1; g=g+1)
        for (int p=0; p<PSI; p=p+1)
          for(int r=0; r<R; r=r+1)
            if (bsk_rdy[p][r][g] != 0) begin
              assert(bsk_vld[p][r][g] == 1'b1)
              else begin
                $display("%t > ERROR: BSK not valid, while output needs them. g=%0d, p=%0d, r=%0d", $time, g, p, r);
                error_valid <= 1;
              end
            end
    end


// ============================================================================================== --
// End of test
// ============================================================================================== --
  initial begin
    end_of_test = 0;
    wait (wr_last);
    $display("%t > INFO: Write BSK done.", $time);
    wait (st_done);
    @(posedge clk);
    for (int i=0; i<GLWE_K_P1; i=i+1)
      wait (data_ref_q[i].size() == 0);
    @(posedge clk);
    end_of_test = 1'b1;
  end

  always_ff @(posedge clk)
    if (!s_rst_n) start <= 1'b0;
    else          start <= 1'b1;

endmodule
