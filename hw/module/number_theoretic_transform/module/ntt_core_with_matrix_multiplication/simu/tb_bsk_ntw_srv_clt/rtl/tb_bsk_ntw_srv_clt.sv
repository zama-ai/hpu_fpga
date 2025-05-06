// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Test the bsk_ntw_cmd_arbiter + bsk_ntw_server + bsk_ntw_client
// ==============================================================================================

module tb_bsk_ntw_srv_clt;
`timescale 1ns/10ps

  import param_tfhe_pkg::*;
  import pep_common_param_pkg::*;
  import ntt_core_common_param_pkg::*;
  import bsk_ntw_common_param_pkg::*;

// ============================================================================================= --
// parameter
// ============================================================================================= --
  parameter int OP_W = 32;
  parameter int BATCH_NB   = 2;
  parameter int BSK_SRV_NB = 3;
  parameter int BSK_CLT_NB = 3;

  parameter int URAM_LATENCY = 1+4;

// ============================================================================================= --
// localparam
// ============================================================================================= --
  localparam int CLK_HALF_PERIOD = 1;
  localparam int ARST_ACTIVATION = 17;

  parameter  int RAM_LATENCY     = 1;

  localparam int INST_BR_LOOP_NB = 10; // Not too many, in order to provoke some collisions.
  localparam int BR_LOOP_NB      = INST_BR_LOOP_NB * BSK_SRV_NB;
  localparam int CMD_NB          = 1000;
  localparam int NEIGH_SERVER_NB = BSK_SRV_NB-1;

  localparam int RAM_DEPTH       = INST_BR_LOOP_NB * BSK_BATCH_COEF_NB / BSK_DIST_COEF_NB;
  localparam int RAM_ADD_W       = $clog2(RAM_DEPTH);

  // Number of cycle for a client, once the BSK is loaded, to output a BSK
  localparam int CL_LAT_MAX      = 1 + 1 + 1 + RAM_LATENCY + 1 -1;
  // 1 : duplication 1 cycle
  // 1 : wp => cl_ntt_bsk complete
  // 1 : ram_ren pipe
  // 1 : output pipe
  // -1 : bench need 1 cycle to change state

// ============================================================================================= --
// Type
// ============================================================================================= --
  typedef struct packed {
    logic [LWE_K_W-1:0]     br_loop;
    logic [GLWE_K_P1_W-1:0] glwe_idx;
    logic [STG_ITER_W-1:0]  stg_iter;
    logic [INTL_L_W-1:0]    intl_idx;
    logic [PSI_W-1:0]       p;
    logic [R_W-1:0]         r;
  } data_t;

  typedef struct packed {
    logic [RAM_ADD_W-1:0]   wr_add;
  } wr_ctrl_t;

  typedef struct packed {
    logic [BATCH_NB-1:0] batch_id_1h;
    logic [LWE_K_W-1:0]  br_loop;
    logic [BPBS_NB_WW-1:0] pbs_nb;
  } cmd_t;


// ============================================================================================= --
// clock, reset
// ============================================================================================= --
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

// ============================================================================================= --
// End of test
// ============================================================================================= --
  bit end_of_test;

  initial begin
    wait (end_of_test);
    @(posedge clk) $display("%t > SUCCEED !", $time);
    $finish;
  end

// ============================================================================================= --
// Error
// ============================================================================================= --
  bit                                       error;
  bit   [BSK_CLT_NB-1:0]                     error_data;
  logic [BSK_SRV_NB-1:0][SRV_ERROR_NB-1:0] error_server;
  bit                                       error_bsk_hit;
  logic [BSK_CLT_NB-1:0][CLT_ERROR_NB-1:0]   error_client;

  assign error = |error_data | |error_server | error_bsk_hit;

  always_ff @(posedge clk)
    if (error) begin
      $display("%t > FAILURE !", $time);
      $finish;
    end

// ============================================================================================= --
// input / output signals
// ============================================================================================= --
  logic [BSK_SRV_NB-1:0][BSK_DIST_COEF_NB-1:0][OP_W-1:0]          srv_bdc_bsk;
  logic [BSK_SRV_NB-1:0][BSK_DIST_COEF_NB-1:0]                    srv_bdc_avail;
  logic [BSK_SRV_NB-1:0][BSK_UNIT_W-1:0]                          srv_bdc_unit;
  logic [BSK_SRV_NB-1:0][BSK_GROUP_W-1:0]                         srv_bdc_group;
  logic [BSK_SRV_NB-1:0][LWE_K_W-1:0]                             srv_bdc_br_loop;

  logic [BSK_SRV_NB-1:0][NEIGH_SERVER_NB-1:0]                     neigh_srv_bdc_avail;

  br_batch_cmd_t [BSK_CLT_NB-1:0]                                    batch_cmd;
  logic  [BSK_CLT_NB-1:0]                                         batch_cmd_avail;

  logic  [BR_BATCH_CMD_W-1:0]                                     arb_srv_batch_cmd;
  logic                                                           arb_srv_batch_cmd_avail;

  logic  [BSK_SRV_NB-1:0]                                         wr_en;
  logic  [BSK_SRV_NB-1:0][BSK_DIST_COEF_NB-1:0][OP_W-1:0]         wr_data;
  logic  [BSK_SRV_NB-1:0][RAM_ADD_W-1:0]                          wr_add;

  logic [BSK_CLT_NB-1:0][PSI-1:0][R-1:0][GLWE_K_P1-1:0][OP_W-1:0] cl_ntt_bsk;
  logic [BSK_CLT_NB-1:0][PSI-1:0][R-1:0][GLWE_K_P1-1:0]           cl_ntt_vld;
  logic [BSK_CLT_NB-1:0][PSI-1:0][R-1:0][GLWE_K_P1-1:0]           cl_ntt_rdy;

// ============================================================================================= --
// Bench general signals
// ============================================================================================= --
  logic [BSK_DIST_COEF_NB-1:0][OP_W-1:0]                          bdc_merged_bsk;
  logic [BSK_DIST_COEF_NB-1:0]                                    bdc_merged_avail;
  logic [BSK_UNIT_W-1:0]                                          bdc_merged_unit;
  logic [BSK_GROUP_W-1:0]                                         bdc_merged_group;
  logic [LWE_K_W-1:0]                                             bdc_merged_br_loop;

// ============================================================================================= --
// Design under test instance
// ============================================================================================= --
  bsk_ntw_cmd_arbiter
  #(
    .BATCH_NB   (BATCH_NB  ),
    .BSK_CLT_NB (BSK_CLT_NB)
  )
  bsk_ntw_cmd_arbiter
  (
    .clk                    (clk                    ),
    .s_rst_n                (s_rst_n                ),

    .batch_cmd              (batch_cmd              ),
    .batch_cmd_avail        (batch_cmd_avail        ),

    .arb_srv_batch_cmd      (arb_srv_batch_cmd      ),
    .arb_srv_batch_cmd_avail(arb_srv_batch_cmd_avail),

    .srv_bdc_avail          (bdc_merged_avail[0])
  );

  genvar gen_i;
  generate
    for (gen_i=0; gen_i<BSK_SRV_NB; gen_i=gen_i+1) begin : srv_inst_loop_gen
      bsk_ntw_server
      #(
        .OP_W             (OP_W),
        .NEIGH_SERVER_NB  (NEIGH_SERVER_NB),
        .BR_LOOP_OFS      (gen_i*INST_BR_LOOP_NB),
        .BR_LOOP_NB       (INST_BR_LOOP_NB),
        .URAM_LATENCY     (URAM_LATENCY)
      )
      bsk_ntw_server
      (
        .clk                      (clk),
        .s_rst_n                  (s_rst_n),

        .srv_bdc_bsk              (srv_bdc_bsk[gen_i]),
        .srv_bdc_avail            (srv_bdc_avail[gen_i]),
        .srv_bdc_unit             (srv_bdc_unit[gen_i]),
        .srv_bdc_group            (srv_bdc_group[gen_i]),
        .srv_bdc_br_loop          (srv_bdc_br_loop[gen_i]),

        .neigh_srv_bdc_avail      (neigh_srv_bdc_avail[gen_i]),

        .arb_srv_batch_cmd        (arb_srv_batch_cmd),
        .arb_srv_batch_cmd_avail  (arb_srv_batch_cmd_avail),

        .wr_en                    (wr_en[gen_i]),
        .wr_data                  (wr_data[gen_i]),
        .wr_add                   (wr_add[gen_i]),

        .error                    (error_server[gen_i])
      );
    end
  endgenerate

  generate
    for (gen_i=0; gen_i<BSK_CLT_NB; gen_i=gen_i+1) begin : clt_inst_loop_gen
      bsk_ntw_client
      #(
        .OP_W        (OP_W),
        .BATCH_NB    (BATCH_NB),
        .RAM_LATENCY (RAM_LATENCY)
      )
      bsk_ntw_client
      (
        .clk             (clk),
        .s_rst_n         (s_rst_n),

        .srv_cl_bsk      (bdc_merged_bsk),
        .srv_cl_avail    (bdc_merged_avail),
        .srv_cl_unit     (bdc_merged_unit),
        .srv_cl_group    (bdc_merged_group),
        .srv_cl_br_loop  (bdc_merged_br_loop),

        .cl_ntt_bsk      (cl_ntt_bsk[gen_i]),
        .cl_ntt_vld      (cl_ntt_vld[gen_i]),
        .cl_ntt_rdy      (cl_ntt_rdy[gen_i]),

        .batch_cmd       (batch_cmd[gen_i]),
        .batch_cmd_avail (batch_cmd_avail[gen_i]),

        .error           (error_client[gen_i])
      );
    end
  endgenerate
// ============================================================================================= --
// Scenario
// ============================================================================================= --
// The scenario is the following :
// - Fill the RAM
// - Read with 100% throughput
// - Read with random accesses
  typedef enum { ST_IDLE,
                 ST_WR,
                 ST_PROCESS,
                 ST_WAIT_FLUSH,
                 ST_DONE,
                 XXX} state_e;

  state_e state;
  state_e next_state;
  logic   start;
  integer cmd_cnt;
  integer cmd_cntD;
  logic   wr_last;
  logic   cl_all_idle;

  always_ff @(posedge clk) begin
    if (!s_rst_n) state <= ST_IDLE;
    else          state <= next_state;
  end

  always_comb begin
    case(state)
      ST_IDLE:
        next_state = start ? ST_WR : state;
      ST_WR:
        next_state = wr_last ? ST_PROCESS : state;
      ST_PROCESS:
        next_state = (cmd_cnt >= CMD_NB) ? ST_WAIT_FLUSH : state;
      ST_WAIT_FLUSH:
        next_state = cl_all_idle ? ST_DONE : state;
      ST_DONE:
        next_state = state;
      default:
        next_state = XXX;
   endcase
  end

  logic st_idle;
  logic st_wr;
  logic st_process;
  logic st_wait_flush;
  logic st_done;

  assign st_idle        = state == ST_IDLE;
  assign st_wr          = state == ST_WR;
  assign st_process     = state == ST_PROCESS;
  assign st_wait_flush  = state == ST_WAIT_FLUSH;
  assign st_done        = state == ST_DONE;

// ============================================================================================= --
// Clients
// ============================================================================================= --
// Here the clients are the command generators
// Each client can generate up to BATCH_NB pending commands.
// To ease the bench, we instanciate BSK_CLT_NB*BATCH_NB clients,
// each is able to handle a single command.
// The only constraint is that 2 "bench_client" cannot generate a command at the same time.
  typedef enum { ST_WAIT_CMD,
                 ST_CMD,
                 ST_WAIT_BSK,
                 ST_WAIT_CLIENT_LATENCY,
                 ST_WAIT_PROC,
                 ST_XXX} client_state_e;


  logic [BSK_CLT_NB-1:0][BATCH_NB-1:0]  cl_bsk_hit;
  logic [BSK_CLT_NB-1:0]                cl_all_idle_a;

  genvar gen_j;
  generate
    for (gen_i=0; gen_i<BSK_CLT_NB; gen_i=gen_i+1) begin : client_loop_gen
      client_state_e                    client_state     [BATCH_NB-1:0];
      client_state_e                    next_client_state[BATCH_NB-1:0];
      logic [BATCH_NB-1:0]              cl_st_wait_cmd;
      logic [BATCH_NB-1:0]              cl_st_cmd;
      logic [BATCH_NB-1:0]              cl_st_wait_bsk;
      logic [BATCH_NB-1:0]              cl_st_wait_proc;
      logic [BATCH_NB-1:0]              cl_st_wait_client_latency;
      logic [BATCH_NB-1:0][LWE_K_W-1:0] cl_br_loop;
      logic [BATCH_NB-1:0][LWE_K_W-1:0] cl_br_loopD;
      logic [BATCH_NB-1:0]              cl_bsk_done;
      logic                             cl_data_done;
      br_batch_cmd_t                    cl_batch_cmd;
      logic                             cl_batch_cmd_avail;
      cmd_t                             cl_cmd_q[$]; // keep track of the br_loop that are processed.
      logic [BATCH_NB-1:0]              cl_proc_done;
      logic                             cl_cur_cmd_en;
      cmd_t                             cl_cur_cmd;
      integer                           cl_lat_cnt[BATCH_NB-1:0];

      //-----------------------
      // FSM
      //-----------------------
      always_ff @(posedge clk) begin
        if (!s_rst_n) client_state <= '{BATCH_NB{ST_WAIT_CMD}};
        else          client_state <= next_client_state;
      end

      always_comb begin
        for (int i=0; i<BATCH_NB; i=i+1) begin
          cl_st_wait_cmd[i]  = client_state[i] == ST_WAIT_CMD;
          cl_st_cmd[i]       = client_state[i] == ST_CMD;
          cl_st_wait_bsk[i]  = client_state[i] == ST_WAIT_BSK;
          cl_st_wait_proc[i] = client_state[i] == ST_WAIT_PROC;
          cl_st_wait_client_latency[i] = client_state[i] == ST_WAIT_CLIENT_LATENCY;
        end
      end

      always_comb begin
        for (int i=0; i<BATCH_NB; i=i+1) begin
          logic [BATCH_NB-1:0] pos_mask;
          pos_mask = ~({BATCH_NB{1'b1}} << i);
          case(client_state[i])
            ST_WAIT_CMD:
              next_client_state[i] = (st_process && (cl_st_cmd == 0) && (cl_st_wait_cmd & pos_mask) == 0) ? ST_CMD : client_state[i];
            ST_CMD:
              next_client_state[i] = cl_batch_cmd_avail ? ST_WAIT_BSK : client_state[i];
            ST_WAIT_BSK:
              next_client_state[i] = cl_bsk_done[i] ? ST_WAIT_CLIENT_LATENCY : client_state[i];
            ST_WAIT_CLIENT_LATENCY:
              next_client_state[i] = cl_lat_cnt[i] == CL_LAT_MAX-1 ? ST_WAIT_PROC : client_state[i];
            ST_WAIT_PROC:
              next_client_state[i] = cl_proc_done[i] ? ST_WAIT_CMD : client_state[i];
            default:
              next_client_state[i] = ST_XXX;
          endcase
        end
      end

      always_ff @(posedge clk)
        if (!s_rst_n) begin
          cl_br_loop      <= {BATCH_NB{{LWE_K_W{1'b1}}}}; // unreachable initial value
        end
        else begin
          cl_br_loop      <= cl_br_loopD;
        end

      assign cl_all_idle_a[gen_i] = &cl_st_wait_cmd;

      always_ff @(posedge clk)
        if (!s_rst_n)
          cl_lat_cnt <= '{BATCH_NB{0}};
        else
          for (int i = 0; i<BATCH_NB; i=i+1)
            if (cl_st_wait_client_latency[i])
              cl_lat_cnt[i] <= cl_lat_cnt[i] + 1;
            else
              cl_lat_cnt[i] <= 0;


      //---------------------
      // Send command
      //---------------------
      logic [LWE_K_W-1:0] rand_batch_cmd_br_loop;
      logic [BPBS_NB_WW-1:0]rand_batch_cmd_pbs_nb;
      logic               rand_batch_cmd_avail;

      always_ff @(posedge clk) begin
        rand_batch_cmd_br_loop <= $urandom_range(BR_LOOP_NB-1);
        rand_batch_cmd_pbs_nb  <= $urandom_range(BATCH_PBS_NB,1);
        rand_batch_cmd_avail   <= ($urandom_range(15) == 0);
      end

      assign cl_batch_cmd_avail   = rand_batch_cmd_avail & (cl_st_cmd != 0);
      assign cl_batch_cmd.br_loop = rand_batch_cmd_br_loop;
      assign cl_batch_cmd.pbs_nb  = rand_batch_cmd_pbs_nb;

      assign batch_cmd[gen_i]       = cl_batch_cmd;
      assign batch_cmd_avail[gen_i] = cl_batch_cmd_avail;

      //---------------------
      // Batch
      //---------------------
      for (gen_j=0; gen_j<BATCH_NB; gen_j=gen_j+1) begin : batch_loop_gen
        integer cl_bsk_cnt;
        integer cl_bsk_cntD;
        logic   last_cl_bsk_cnt;

        assign cl_bsk_hit[gen_i][gen_j] = cl_st_wait_bsk[gen_j] & bdc_merged_avail[0] & bdc_merged_br_loop == cl_br_loop[gen_j];
        assign last_cl_bsk_cnt          = cl_bsk_cnt == (BSK_DIST_ITER_NB-1);

        assign cl_br_loopD[gen_j] = (cl_st_cmd[gen_j] && batch_cmd_avail[gen_i]) ?
                                        batch_cmd[gen_i].br_loop : cl_br_loop[gen_j];
        assign cl_bsk_cntD        = cl_bsk_hit[gen_i][gen_j] ? last_cl_bsk_cnt ? 0 : cl_bsk_cnt + 1 : cl_bsk_cnt;
        assign cl_bsk_done[gen_j] = (cl_bsk_hit[gen_i][gen_j] & last_cl_bsk_cnt);

        always_ff @(posedge clk)
          if (!s_rst_n) begin
            cl_bsk_cnt          <= 0;
          end
          else begin
            cl_bsk_cnt          <= cl_bsk_cntD;
          end

      end // batch_loop_gen

      //---------------------
      // Command queue
      //---------------------
      always_ff @(posedge clk) begin
        if (!s_rst_n) begin
          cl_proc_done <= '0;
        end
        else begin
          cl_proc_done <= '0;
          if (batch_cmd_avail[gen_i]) begin
            cmd_t c;
            c.br_loop     = batch_cmd[gen_i].br_loop;
            c.pbs_nb      = batch_cmd[gen_i].pbs_nb;
            c.batch_id_1h = cl_st_cmd;
            cl_cmd_q.push_back(c);
          end
          if (cl_data_done) begin
            cl_proc_done <= cl_cur_cmd.batch_id_1h;
          end
        end
      end

      always_ff @(posedge clk) begin
        if (!s_rst_n) begin
          cl_cur_cmd_en <= 1'b0;
          cl_cur_cmd    <= 'x;
        end
        else begin
          if (cl_data_done)
            cl_cur_cmd_en <= 1'b0;
          else
            if (!cl_cur_cmd_en && cl_cmd_q.size() > 0) begin
              cmd_t c2;
              c2 = cl_cmd_q.pop_front();
              cl_cur_cmd_en <= 1'b1;
              cl_cur_cmd    <= c2;
            end
        end
      end


      //---------------------
      // Count output data
      //---------------------
      logic [STG_ITER_W-1:0]            stg_iter;
      logic [INTL_L_W-1:0]              intl_idx;
      logic [BPBS_ID_W-1:0]              pbs_id;
      logic [STG_ITER_W-1:0]            stg_iterD;
      logic [INTL_L_W-1:0]              intl_idxD;
      logic [BPBS_ID_W-1:0]              pbs_idD;
      logic                             last_stg_iter;
      logic                             last_intl_idx;
      logic                             last_pbs_id;

      assign last_stg_iter = stg_iter == STG_ITER_NB-1;
      assign last_intl_idx = intl_idx == INTL_L-1;
      assign last_pbs_id   = (pbs_id == (cl_cur_cmd.pbs_nb-1));
      assign intl_idxD = (cl_ntt_vld[gen_i] && cl_ntt_rdy[gen_i]) ? last_intl_idx ? '0 : intl_idx + 1 : intl_idx;
      assign stg_iterD = (cl_ntt_vld[gen_i] && cl_ntt_rdy[gen_i] && last_intl_idx) ? last_stg_iter ? '0 : stg_iter + 1 : stg_iter;
      assign pbs_idD   = (cl_ntt_vld[gen_i] && cl_ntt_rdy[gen_i] && last_intl_idx && last_stg_iter) ? last_pbs_id ? '0 : pbs_id + 1 : pbs_id;

      assign cl_data_done = cl_ntt_vld[gen_i] & cl_ntt_rdy[gen_i] & last_intl_idx & last_stg_iter & last_pbs_id;

      always_ff @(posedge clk)
        if (!s_rst_n) begin
          stg_iter <= '0;
          intl_idx <= '0;
          pbs_id   <= '0;
        end
        else begin
          stg_iter <= stg_iterD;
          intl_idx <= intl_idxD;
          pbs_id   <= pbs_idD  ;
        end

      //---------------------
      // Check client output data
      //---------------------
      logic   cl_error_data;
      assign error_data[gen_i] = cl_error_data;
      always_ff @(posedge clk) begin
        if (!s_rst_n) begin
          cl_error_data <= 1'b0;
        end
        else begin
          if (cl_ntt_vld[gen_i] && cl_ntt_rdy[gen_i]) begin
            for (int p=0; p<PSI; p=p+1) begin
              for (int r=0; r<R; r=r+1) begin
                for (int glwe_idx=0; glwe_idx<GLWE_K_P1; glwe_idx=glwe_idx+1) begin
                  data_t ref_d;
                  data_t d;
                  ref_d.br_loop = cl_cur_cmd.br_loop;
                  ref_d.glwe_idx = glwe_idx;
                  ref_d.stg_iter = stg_iter;
                  ref_d.intl_idx = intl_idx;
                  ref_d.p        = p;
                  ref_d.r        = r;
                  d = cl_ntt_bsk[gen_i][p][r][glwe_idx];
                  assert(d == ref_d)
                  else begin
                    $display("%t > ERROR: cl_ntt_bsk mismatch for client %1d.", $time, gen_i);
                    $display("  br_loop : exp=%0d seen=%0d", ref_d.br_loop,d.br_loop);
                    $display("  stg_iter: exp=%0d seen=%0d", ref_d.stg_iter,d.stg_iter);
                    $display("  intl_idx: exp=%0d seen=%0d", ref_d.intl_idx,d.intl_idx);
                    $display("  p       : exp=%0d seen=%0d", ref_d.p,d.p);
                    $display("  r       : exp=%0d seen=%0d", ref_d.r,d.r);
                    $display("  glwe_idx: exp=%0d seen=%0d", ref_d.glwe_idx,d.glwe_idx);
                    cl_error_data <= 1'b1;
                  end
                end // glwe_idx
              end // r
            end // p
          end
        end
      end

  // ----------------------
  // cl_ntt_rdy
  // ----------------------
  logic cl_ntt_rdy_tmp;
  assign cl_ntt_rdy[gen_i] = {PSI*R*GLWE_K_P1{cl_ntt_rdy_tmp}};
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      cl_ntt_rdy_tmp      <= 1'b0;
    end
    else begin
      if (st_process || st_wait_flush) begin
        logic rdy_tmp;
        if (cl_data_done) begin
          cl_ntt_rdy_tmp <= '0; // wait for the next batch
        end
        else begin
          if (cl_ntt_rdy_tmp == 0 && cl_cur_cmd_en == 1 && (cl_st_wait_proc & cl_cur_cmd.batch_id_1h) != 0) begin
          // All the key has been recieved.
            rdy_tmp = $urandom_range(1);
            cl_ntt_rdy_tmp <= rdy_tmp;
          end
        end
      end
    end
  end

    end // client_loop_gen
  endgenerate

// ============================================================================================= --
// Merge signals for clients
// ============================================================================================= --
  always_comb begin
    bdc_merged_bsk     = '0;
    bdc_merged_avail   = '0;
    bdc_merged_unit    = '0;
    bdc_merged_group   = '0;
    bdc_merged_br_loop = '0;
    for (int i=0; i<BSK_SRV_NB; i=i+1) begin
      bdc_merged_bsk     = bdc_merged_bsk     | srv_bdc_bsk[i];
      bdc_merged_avail   = bdc_merged_avail   | srv_bdc_avail[i];
      bdc_merged_unit    = bdc_merged_unit    | srv_bdc_unit[i];
      bdc_merged_group   = bdc_merged_group   | srv_bdc_group[i];
      bdc_merged_br_loop = bdc_merged_br_loop | srv_bdc_br_loop[i];
    end
  end

// ============================================================================================= --
// Neighbours
// ============================================================================================= --
  logic [BSK_SRV_NB-1:0] srv_bdc_avail_0_a;
  always_comb
    for (int i=0; i<BSK_SRV_NB; i=i+1)
      srv_bdc_avail_0_a[i] = srv_bdc_avail[i][0];

  generate
    for (gen_i=0; gen_i<BSK_SRV_NB; gen_i=gen_i+1) begin : neigh_loop_gen
      if (gen_i == 0) begin
        assign neigh_srv_bdc_avail[0]             = srv_bdc_avail_0_a[BSK_SRV_NB-1:1];
      end
      else if (gen_i == BSK_SRV_NB-1) begin
        assign neigh_srv_bdc_avail[BSK_SRV_NB-1] = srv_bdc_avail_0_a[BSK_SRV_NB-2:0];
      end
      else begin
        assign neigh_srv_bdc_avail[gen_i] = {srv_bdc_avail_0_a[BSK_SRV_NB-1:gen_i+1],srv_bdc_avail_0_a[gen_i-1:0]};
      end
    end
  endgenerate

// ============================================================================================= --
// Write stimuli
// ============================================================================================= --
  logic     [OP_W-1:0] wr_data_q[BSK_SRV_NB-1:0][$];
  wr_ctrl_t            wr_ctrl_q[BSK_SRV_NB-1:0][$];

  initial begin
    // Write data
    for (int i=0; i<BSK_SRV_NB; i=i+1) begin
      for (int br_loop=0; br_loop<INST_BR_LOOP_NB; br_loop=br_loop+1) begin
        for (int stg_iter=0; stg_iter<STG_ITER_NB; stg_iter=stg_iter+1) begin
          for (int intl_idx=0; intl_idx<INTL_L; intl_idx=intl_idx+1) begin
            for (int p=0; p<PSI; p=p+1) begin
              for (int r=0; r<R; r=r+1) begin
                for (int glwe_idx=0; glwe_idx<GLWE_K_P1; glwe_idx=glwe_idx+1) begin
                  wr_ctrl_t c;
                  data_t    d;
                  if (((p*(R*GLWE_K_P1) + r*GLWE_K_P1 + glwe_idx)%BSK_DIST_COEF_NB) == 0) begin
                    c.wr_add = (br_loop*BSK_BATCH_COEF_NB
                                + stg_iter * PSI*R*GLWE_K_P1*INTL_L
                                + intl_idx * PSI*R*GLWE_K_P1
                                + p*(R*GLWE_K_P1)
                                + r*GLWE_K_P1
                                + glwe_idx) / BSK_DIST_COEF_NB;
                    wr_ctrl_q[i].push_back(c);
                  end
                  d.br_loop  = br_loop + i*INST_BR_LOOP_NB;
                  d.glwe_idx = glwe_idx;
                  d.stg_iter = stg_iter;
                  d.intl_idx = intl_idx;
                  d.p        = p;
                  d.r        = r;
                  wr_data_q[i].push_back(d);
                  //$display("WR DATA wr_data[%2d][%2d][%2d][%2d][%2d][%2d] : 0x%08x",br_loop,glwe_idx,stg_iter,p,r,d);
                end// glwe_idx
              end // r
            end // p
          end // intl_idx
        end // stg_iter
      end// br_loop
    end // inst
  end // initial

// ============================================================================================= --
// Write in RAM
// ============================================================================================= --
  logic                            rand_wr_en;
  logic                            wr_en_tmp;
  logic                            wr_en_tmpD;
  logic [BSK_DIST_COEF_NB-1:0][OP_W-1:0]    wr_data_tmp;
  logic [RAM_ADD_W-1:0]            wr_add_tmp;

  integer                          wr_inst_id;
  integer                          wr_inst_idD;

  always_ff @(posedge clk)
    if (!s_rst_n) rand_wr_en <= 0;
    else          rand_wr_en <= $urandom_range(1);

  assign wr_en_tmpD = st_wr & rand_wr_en & ~wr_last;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      wr_en_tmp  <= 0;
      wr_inst_id <= 0;
    end
    else begin
      wr_en_tmp  <= wr_en_tmpD;
      wr_inst_id <= wr_inst_idD;
    end

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      wr_add_tmp  <= 0;
      wr_last     <= 0;
      wr_inst_idD <= 0;
    end
    else begin
      wr_ctrl_t c;
      bit q_empty;
      if (wr_en_tmpD) begin
        c = wr_ctrl_q[wr_inst_idD].pop_front();
        q_empty = (wr_ctrl_q[wr_inst_idD].size() == 0);
        wr_add_tmp  <= c.wr_add;
        wr_last     <= q_empty && (wr_inst_idD == BSK_SRV_NB-1);
        wr_inst_idD <= q_empty ? wr_inst_idD + 1 : wr_inst_idD;
      end
    end

  always_ff @(posedge clk) begin
    logic [OP_W-1:0] d;
    if (wr_en_tmpD) begin
      for (int i=0; i<BSK_DIST_COEF_NB; i=i+1) begin
          d = wr_data_q[wr_inst_idD].pop_front();
          wr_data_tmp[i] <= d;
      end
    end
  end

  always_comb begin
    for (int i=0; i<BSK_SRV_NB; i=i+1) begin
      wr_en[i]   = wr_en_tmp & (wr_inst_id == i);
      wr_data[i] = wr_data_tmp;
      wr_add[i]  = wr_add_tmp;
    end
  end

// ============================================================================================= --
// Check
// ============================================================================================= --
  integer br_loop_bsk_cnt [BR_LOOP_NB-1:0];
  integer br_loop_cmd_cnt [BR_LOOP_NB-1:0];

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      for (int i=0; i<BR_LOOP_NB; i=i+1) begin
        br_loop_bsk_cnt[i] <= 0;
      end
    end
    else begin
      for (int i=0; i<BR_LOOP_NB; i=i+1) begin
        if (bdc_merged_avail[0] && bdc_merged_unit == 0 && bdc_merged_group == 0)
          br_loop_bsk_cnt[bdc_merged_br_loop] <= br_loop_bsk_cnt[bdc_merged_br_loop]+1;
      end
    end

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      for (int i=0; i<BR_LOOP_NB; i=i+1) begin
        br_loop_cmd_cnt[i] <= 0;
      end
    end
    else begin
        integer tmp [BR_LOOP_NB-1:0];
        tmp = br_loop_cmd_cnt;
        for (int j=0; j<BSK_CLT_NB; j=j+1) begin
          if (batch_cmd_avail[j])
            tmp[batch_cmd[j].br_loop] = tmp[batch_cmd[j].br_loop] + 1;
        end
        br_loop_cmd_cnt <= tmp;
    end

  initial begin
    error_bsk_hit = 1'b0;
    wait(st_done);
    @(posedge clk);
    for (int i = 0; i<BR_LOOP_NB; i=i+1) begin
      assert(br_loop_bsk_cnt[i] <= br_loop_cmd_cnt[i])
      else begin
        $display("%t > ERROR: Broadcasted cl_ntt_bsk does not belong to any client: br_loop=0x%0x!", $time, i);
        error_bsk_hit = 1'b1;
      end
    end
  end

// ============================================================================================= --
// End of test
// ============================================================================================= --
  assign cl_all_idle = &cl_all_idle_a;
  assign cmd_cntD = cmd_cnt + $countones(batch_cmd_avail);

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      cmd_cnt <= 0;
    end
    else begin
      cmd_cnt <= cmd_cntD;
      if (|batch_cmd_avail && cmd_cnt % 100 == 0)
        $display("%t > INFO: Processing cmd #%0d",$time, cmd_cnt);
    end

  initial begin
    end_of_test = 0;
    wait (wr_last);
    $display("%t > INFO: Write cl_ntt_bsk done.", $time);
    wait (st_done);
    @(posedge clk);
    end_of_test = 1'b1;
  end

  always_ff @(posedge clk)
    if (!s_rst_n) start     <= 1'b0;
    else          start     <= 1'b1;

endmodule
