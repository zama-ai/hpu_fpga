// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Bench that tests the twiddle_phi_ru_manager.
// The tests focuses on the correctness of the twiddles and the variation in twiddle consumption
// pace.
// ==============================================================================================

`include "ntt_core_common_macro_inc.sv"

module tb_twiddle_phi_ru_manager;
  `timescale 1ns/10ps

  import pep_common_param_pkg::*;

  // ============================================================================================ //
  // parameter
  // ============================================================================================ //
  parameter  string FILE_TWD_PREFIX = "input/data";
  parameter  int    OP_W            = 32;
  parameter  int    R               = 8; // Butterfly Radix
  parameter  int    PSI             = 8; // Number of butterflies
  parameter  int    S               = 3; // Number of stages
  parameter  int    S_INIT          = S - 1;
  parameter  int    S_DEC           = 1;
  parameter  int    ROM_LATENCY     = 1;

  // ============================================================================================ //
  // localparam
  // ============================================================================================ //
  localparam int CLK_HALF_PERIOD  = 1;
  localparam int ARST_ACTIVATION  = 17;

  `NTT_CORE_LOCALPARAM(R,S,PSI)

  localparam int BATCH_RAND_BW_NB = 100 ;
  localparam int BATCH_FULL_BW_NB = 100;
  localparam int BATCH_NB         = BATCH_FULL_BW_NB + BATCH_RAND_BW_NB;

  localparam int CMD_FIFO_DEPTH   = 4;
  localparam int TWD_ERROR_NB     = 2;
  localparam int RD_NB            = R<4? 1 : 2;

  localparam int FIFO_REG_DLY     = (2+1) + (1 + ROM_LATENCY + 1); // cmd FIFO  + read in ROM

  localparam bit DO_LOOPBACK      = (S_DEC > 0); // if 1 this means that this module is used
                                                 // for different stages (fwd-bwd taken into account)
  localparam int S_INIT_L        = S_INIT >= S ? S_INIT - S : S_INIT;
  localparam int S_DEC_L         = S_DEC % S;
  localparam bit NTT_BWD_INIT    = S_INIT >= S;

  localparam int NTT_BWD_NB      = DO_LOOPBACK ? 2 : 1;

  localparam int LPB_NB          = DO_LOOPBACK == 0 ? 1 : (S_INIT+1 + S_DEC-1)/S_DEC;

  // ============================================================================================ //
  // Type
  // ============================================================================================ //
  typedef struct packed {
    logic                  ntt_bwd;
    logic [STG_W-1:0]      stg;
    logic [STG_ITER_W-1:0] stg_iter;
    logic [PSI_W-1:0]      p;
    logic [R_W-1:0]        r;
  } data_t;

  localparam int DATA_W = $bits(data_t);

  // Check parameters
  // If OP_W is not big enough to store object of data_t, redefine OP_W with DATA_W.
  initial begin
    assert(DATA_W <= OP_W)
    else $fatal(1, "%t > ERROR: Redefine OP_W to make this bench works.", $time);
  end

  // ============================================================================================ //
  // clock, reset
  // ============================================================================================ //
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

  // ============================================================================================ //
  // End of test
  // ============================================================================================ //
  bit end_of_test;

  initial begin
    $display("%t > INFO : S_INIT = %0d, S_DEC = %0d LPB_NB = %0d", $time, S_INIT, S_DEC, LPB_NB);
    $display("%t > INFO : Launching w/ PSI = %0d, R = %0d, S = %0d", $time,PSI, R, S);
    wait (end_of_test);
    @(posedge clk) begin
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
  bit error_data_kept;

  assign error = error_data | error_valid | error_data_kept;

  always_ff @(posedge clk)
    if (error) begin
      $display("%t > FAILURE !", $time);
      $finish;
    end

  // ============================================================================================ //
  // input / output signals
  // ============================================================================================ //
  // Output to NTT core
  logic [PSI-1:0][R-1:1][OP_W-1:0]    twd_phi_ru;
  logic [PSI-1:0]                     twd_phi_ru_vld;
  logic [PSI-1:0]                     twd_phi_ru_rdy;

  // Broadcast from acc
  br_batch_cmd_t                      batch_cmd;
  logic                               batch_cmd_avail;

  // Control : signal indicating that the twiddles are available in the ROM.
  // posedge of this signal is used.
  logic [TWD_ERROR_NB-1:0]            twd_error;

  // ============================================================================================ //
  // Design under test instance
  // ============================================================================================ //
  twiddle_phi_ru_manager #(
    .FILE_TWD_PREFIX (FILE_TWD_PREFIX),
    .OP_W            (OP_W),
    .ROM_LATENCY     (ROM_LATENCY),
    .R               (R),
    .PSI             (PSI),
    .S               (S),
    .S_INIT          (S_INIT),
    .S_DEC           (S_DEC),
    .LPB_NB          (LPB_NB)
  ) dut (
    .clk             (clk    ),
    .s_rst_n         (s_rst_n),

    .twd_phi_ru      (twd_phi_ru),
    .twd_phi_ru_vld  (twd_phi_ru_vld),
    .twd_phi_ru_rdy  (twd_phi_ru_rdy),

    .batch_cmd       (batch_cmd      ),
    .batch_cmd_avail (batch_cmd_avail),

    .error           (twd_error)
  );

  // ============================================================================================ //
  // Stimuli
  // ============================================================================================ //
  // Build the stimuli.
  logic [OP_W-1:0] data_ref_q[$];
  integer pbs_nb_a [BATCH_NB-1:0];

  initial begin
    // Write data
    int s_init;
    int stg;

    // Output data + ctrl
    for (int batch_id=0; batch_id<BATCH_NB; batch_id=batch_id+1) begin
      int pbs_nb;
      pbs_nb = $urandom_range(BATCH_PBS_NB,1);
      pbs_nb_a[batch_id] = pbs_nb;
      for (int i=0; i < NTT_BWD_NB; i=i+1) begin
        int ntt_bwd;
        int stg_nb;
        ntt_bwd = (NTT_BWD_INIT + i) % 2;
        s_init = (ntt_bwd != NTT_BWD_INIT) ? (stg - S_DEC_L + S)%S : S_INIT_L;
        stg_nb = S_DEC_L == 0 ? 1 : 1 + s_init / S_DEC_L;
        for (int j = 0; j < stg_nb; j=j+1) begin
          stg = s_init - j*S_DEC_L;
          for (int pbs_id=0; pbs_id < pbs_nb; pbs_id=pbs_id+1) begin
            for (int stg_iter=0; stg_iter<STG_ITER_NB; stg_iter=stg_iter+1) begin
                for (int p=0; p<PSI; p=p+1) begin
                  for (int r=1; r<R; r=r+1) begin
                    data_t d;
                    d.p        = p;
                    d.r        = r;
                    d.stg      = stg;
                    d.stg_iter = stg_iter;
                    d.ntt_bwd  = ntt_bwd;
                    data_ref_q.push_back(d);
                    //$display("REF DATA pbs_id=%1d data[%2d][%2d][%1d][%2d][%2d] : 0x%08x",pbs_id, ntt_bwd, stg, stg_iter, p, r, d);
                  end
                end
            end // stg_iter
          end // pbs_id
        end // stg
      end // ntt_bwd
    end // batch_id
  end

  // ============================================================================================ //
  // Scenario
  // ============================================================================================ //
  // The scenario is the following :
  // - Read with 100% throughput
  // - Read with random accesses
  typedef enum { ST_IDLE,
                ST_FULL_BW,
                ST_RAND_BW,
                ST_DONE,
                XXX} state_e;

  state_e state;
  state_e next_state;
  logic   start;
  logic   start_dly;
  integer batch_id;
  integer batch_idD;
  logic   proc_batch_last;

  always_ff @(posedge clk) begin
    if (!s_rst_n) state <= ST_IDLE;
    else          state <= next_state;
  end

  always_comb begin
    case(state)
      ST_IDLE:
        next_state = start ? ST_FULL_BW : state;
      ST_FULL_BW:
        next_state = (proc_batch_last && batch_id == BATCH_FULL_BW_NB-1) ? ST_RAND_BW : state;
      ST_RAND_BW:
        next_state = (proc_batch_last && batch_id == BATCH_NB-1) ? ST_DONE : state;
      ST_DONE:
        next_state = state;
      default:
        next_state = XXX;
   endcase
  end

  logic st_idle;
  logic st_full_bw;
  logic st_rand_bw;
  logic st_done;

  assign st_idle        = state == ST_IDLE;
  assign st_full_bw     = state == ST_FULL_BW;
  assign st_rand_bw     = state == ST_RAND_BW;
  assign st_done        = state == ST_DONE;

  logic st_process;
  assign st_process = st_full_bw | st_rand_bw;

  // ============================================================================================ //
  // Counters
  // ============================================================================================ //
  int   stg;
  int   stg_iter;
  logic ntt_bwd;
  int   pbs_id;
  int   stgD;
  int   stg_iterD;
  int   ntt_bwdD;
  int   pbs_idD;
  logic last_wrap_stg;
  logic last_stg_iter;
  logic last_pbs_id;
  logic proc_batch_last_dly;
  int   stg_start;
  logic last_ntt_bwd;


  assign stgD      = (DO_LOOPBACK && twd_phi_ru_vld[0] && twd_phi_ru_rdy[0] && last_stg_iter && last_pbs_id) ?
                        last_wrap_stg ? stg_start: stg - S_DEC : stg;
  assign stg_iterD = (twd_phi_ru_vld[0] && twd_phi_ru_rdy[0]) ?
                        last_stg_iter ? 0 : stg_iter + 1 : stg_iter;
  assign ntt_bwdD  = (DO_LOOPBACK && twd_phi_ru_vld[0] && twd_phi_ru_rdy[0] && last_stg_iter && last_wrap_stg && last_pbs_id) ?
                        ~ntt_bwd : ntt_bwd;
  assign pbs_idD   = (twd_phi_ru_vld[0] && twd_phi_ru_rdy[0] && last_stg_iter) ?
                        last_pbs_id ? 0: pbs_id + 1 : pbs_id;

  assign batch_idD = proc_batch_last ? batch_id + 1 : batch_id;

  assign last_wrap_stg = ~DO_LOOPBACK | (stg < S_DEC);
  assign stg_start     = DO_LOOPBACK ? stg - S_DEC + S : S_INIT_L;
  assign last_stg_iter = (stg_iter == STG_ITER_NB-1);
  assign last_pbs_id   = (pbs_id == pbs_nb_a[batch_id]-1);
  assign last_ntt_bwd  = ~DO_LOOPBACK | (ntt_bwd != NTT_BWD_INIT);

  assign proc_batch_last = twd_phi_ru_vld[0] & twd_phi_ru_rdy[0]
                           & last_wrap_stg & last_stg_iter & last_ntt_bwd & last_pbs_id;


  always_ff @(posedge clk)
    if (!s_rst_n) begin
      batch_id <= 0;
      stg      <= S_INIT_L;
      stg_iter <= 0;
      ntt_bwd  <= NTT_BWD_INIT;
      pbs_id   <= 0;
      proc_batch_last_dly <= 1'b0;
    end
    else begin
      batch_id <= batch_idD;
      stg      <= stgD     ;
      stg_iter <= stg_iterD;
      ntt_bwd  <= ntt_bwdD ;
      pbs_id   <= pbs_idD  ;
      proc_batch_last_dly <= proc_batch_last;
    end

  // ============================================================================================ //
  // Output
  // ============================================================================================ //
  //-------------------
  // batch cmd
  //-------------------
  int cmd_batch_id;
  int cmd_batch_id_dly  [FIFO_REG_DLY-1:0];
  int cmd_batch_id_dlyD [FIFO_REG_DLY-1:0];

  int rand_val;
  int rand_cmd_vld;

  always_ff @(posedge clk) begin
    rand_val     <= $urandom;
    rand_cmd_vld <= (rand_val & 'hFF) == 0;
  end

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

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      cmd_batch_id    <= 0;
      batch_cmd_avail <= 0;
    end
    else begin
      if (((cmd_batch_id - batch_id) < CMD_FIFO_DEPTH) && rand_cmd_vld && st_process && (cmd_batch_id < BATCH_NB)) begin
        batch_cmd.pbs_nb <= pbs_nb_a[cmd_batch_id];
        batch_cmd.br_loop<= 0; // unused
        batch_cmd_avail  <= 1'b1;
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

  //-------------------
  // data
  //-------------------
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      twd_phi_ru_rdy      <= '0;
    end
    else begin
      if (st_process) begin
        if (twd_phi_ru_rdy)
          twd_phi_ru_rdy <= '0; // At least 2 cycles between 2 ready
        else begin
          logic rdy_tmp;
          rdy_tmp = st_full_bw ? '1 : $urandom_range(1);
          if (proc_batch_last_dly)
            rdy_tmp = rdy_tmp & (cmd_batch_id_dly[FIFO_REG_DLY-1] > (batch_id + 1));
          else
            rdy_tmp = rdy_tmp & (cmd_batch_id_dly[FIFO_REG_DLY-1] > (batch_id));
          twd_phi_ru_rdy      <= {PSI{rdy_tmp}};
        end
      end
    end
  end

// ============================================================================================ //
// Check
// ============================================================================================ //
  always_ff @(posedge clk) begin
    if (!s_rst_n)
      error_data <= 0;
    else begin
      logic [PSI-1:0][R-1:1][OP_W-1:0] ref_data;
      if (twd_phi_ru_vld[0] && twd_phi_ru_rdy[0]) begin
        for (int p=0; p<PSI; p=p+1)
          for(int r=1; r<R; r=r+1)
            ref_data[p][r] = data_ref_q.pop_front();
        assert(twd_phi_ru == ref_data)
        else begin
          $display("%t > ERROR: Output data mismatch.", $time);
          for (int p=0; p<PSI; p=p+1)
            for(int r=0; r<R; r=r+1)
              $display("  data[%2d][%2d] : exp=0x%08x seen=0x%08x",p,r,ref_data[p][r],twd_phi_ru[p][r]);
          error_data <= 1;
        end
      end
    end
  end

  always_ff @(posedge clk) begin
    if (!s_rst_n)
      error_valid <= 0;
    else begin
      if (twd_phi_ru_rdy != 0) begin
        assert(twd_phi_ru_vld == {PSI{1'b1}})
        else begin
          $display("%t > ERROR: Twiddles not valid, while output needs them.", $time);
          error_valid <= 1;
        end
      end
    end
  end

  // When sampled, the data was the same 1 cycle before
  logic [PSI-1:0][R-1:1][OP_W-1:0] twd_phi_ru_dly;
  always_ff @(posedge clk)
    twd_phi_ru_dly <= twd_phi_ru;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      error_data_kept <= 0;
    end
    else begin
      for (int i=0; i<PSI; i=i+1) begin
        if (twd_phi_ru_vld[i] && twd_phi_ru_rdy[i])
          assert(twd_phi_ru == twd_phi_ru_dly)
          else begin
            $display("%t > ERROR: Twiddles value is not maintained.", $time);
            error_data_kept <= 1;
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
      start     <= 1'b0;
      start_dly <= 1'b0;
    end
    else begin
      start     <= 1'b1;
      start_dly <= start;
    end
  end

endmodule
