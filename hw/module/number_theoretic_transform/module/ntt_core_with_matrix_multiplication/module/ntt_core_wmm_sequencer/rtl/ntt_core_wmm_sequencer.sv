// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the NTT input. It selects the data that will be processed by the NTT
// core.
//
// Parameters:
//   NTW_RD_LATENCY : Used to synchronize the current input ending and the next one sent by
//               the loopback, to avoid idle cycles.
//               This gives the number of cycles before sending the eob signal. At this moment,
//               a read enable is sent to the ramrd module.
//               For the very last stage of the batch, no synchronization is needed, since the
//               data read is for the accumulator and not the sequencer.
//
// Signals:
//   infifo_seq_full_throughput : signal from the IN FIFO that ensures that if there won't be any
//               bubble (vld=0) in the reading until the eob is reached.
// ==============================================================================================

`include "ntt_core_common_macro_inc.sv"

module ntt_core_wmm_sequencer
  import param_tfhe_pkg::*;
  import pep_common_param_pkg::*;
#(
  parameter int OP_W           = 32,
  parameter int R              = 8, // Butterfly Radix
  parameter int PSI            = 8, // Number of butterflies
  parameter int S              = $clog2(N)/$clog2(R), // Number of stages
  parameter int NTW_RD_LATENCY = 6,
  parameter int S_DEC          = 1,
  parameter int LPB_NB         = 4
) (
  input  logic                                clk,     // clock
  input  logic                                s_rst_n, // synchronous reset

  // Data from input  logic FIFO
  input  logic [PSI-1:0][R-1:0][    OP_W-1:0] infifo_seq_data,
  input  logic [PSI-1:0][R-1:0]               infifo_seq_data_vld,
  output logic [PSI-1:0][R-1:0]               infifo_seq_data_rdy,

  input  logic                                infifo_seq_sob,
  input  logic                                infifo_seq_eob,
  input  logic                                infifo_seq_sol,
  input  logic                                infifo_seq_eol,
  input  logic                                infifo_seq_sog,
  input  logic                                infifo_seq_eog,
  input  logic                 [BPBS_ID_W-1:0] infifo_seq_pbs_id,
  input  logic                                infifo_seq_last_pbs,
  input  logic                                infifo_seq_full_throughput,
  input  logic                                infifo_seq_ctrl_vld,
  output logic                                infifo_seq_ctrl_rdy,

  // Data from NTT loopback
  input  logic [PSI-1:0][R-1:0][    OP_W-1:0] ntw_seq_data,
  input  logic [PSI-1:0][R-1:0]               ntw_seq_data_avail,
  input  logic                                ntw_seq_sob,
  input  logic                                ntw_seq_eob,
  input  logic                                ntw_seq_sol,
  input  logic                                ntw_seq_eol,
  input  logic                                ntw_seq_sos,
  input  logic                                ntw_seq_eos,
  input  logic                 [BPBS_ID_W-1:0] ntw_seq_pbs_id,
  input  logic                                ntw_seq_ctrl_avail,
  
  // Data to CLBU
  output logic [PSI-1:0][R-1:0][   OP_W-1:0] seq_clbu_data,
  output logic [PSI-1:0]                     seq_clbu_data_avail,

  output logic                               seq_clbu_sob,
  output logic                               seq_clbu_eob,
  output logic                               seq_clbu_sol,
  output logic                               seq_clbu_eol,
  output logic                               seq_clbu_sos,
  output logic                               seq_clbu_eos,
  output logic                [BPBS_ID_W-1:0] seq_clbu_pbs_id,
  output logic                               seq_clbu_ntt_bwd,
  output logic                               seq_clbu_ctrl_avail,
  
  // Read enable for ramrd
  output logic                               seq_ntw_fwd_rden, // pulse
  output logic                               seq_ntw_bwd_rden  // pulse

);

  // ============================================================================================== --
  // localparam
  // ============================================================================================== --
  `NTT_CORE_LOCALPARAM(R,S,PSI)

  localparam int FWD_STG_CYCLE_NB = STG_ITER_NB * INTL_L;
  localparam int BWD_STG_CYCLE_NB = STG_ITER_NB * GLWE_K_P1;
  localparam int MAX_STG_CYCLE_NB = FWD_STG_CYCLE_NB > BWD_STG_CYCLE_NB ?
                                      FWD_STG_CYCLE_NB : BWD_STG_CYCLE_NB;
  localparam int STG_CYCLE_W      = $clog2(MAX_STG_CYCLE_NB) == 0 ? 1 : $clog2(MAX_STG_CYCLE_NB);

  // Additional cycle due to local pipe.
  localparam int FWD_SEND_RDEN_CYCLE_TMP = FWD_STG_CYCLE_NB - NTW_RD_LATENCY - 1;
  localparam int BWD_SEND_RDEN_CYCLE_TMP = BWD_STG_CYCLE_NB - NTW_RD_LATENCY - 1;
  localparam int FWD_SEND_RDEN_CYCLE = FWD_SEND_RDEN_CYCLE_TMP < 0 ? 0 : FWD_SEND_RDEN_CYCLE_TMP;
  localparam int BWD_SEND_RDEN_CYCLE = BWD_SEND_RDEN_CYCLE_TMP < 0 ? 0 : BWD_SEND_RDEN_CYCLE_TMP;

  localparam bit DO_LOOPBACK     = (S_DEC > 0); // if 1 this means that this module is used
                                                // for different stages (fwd-bwd taken into account)
  // Note : controlling the throughput is necessary when loopback is used.
  localparam int S_INIT          = S-1;
  localparam int S_DEC_L         = S_DEC % S;
  localparam bit NTT_BWD_INIT    = 0;

  localparam int LPB_W           = LPB_NB < 2 ? 1 : $clog2(LPB_NB);

  // ============================================================================================== --
  // ntt_core_wmm_sequencer
  // ============================================================================================== --
  // ---------------------------------------------------------------------------------------------- --
  // FSM
  // ---------------------------------------------------------------------------------------------- --
  typedef enum integer {ST_XXX = 'x,
                ST_IN = '0,
                ST_WAIT_IN,
                ST_LOOPBACK
                } state_e;

  state_e state;
  state_e next_state;
  logic s0_wrap_stg;
  logic s0_last_ntt_bwd;

  always_ff @(posedge clk) begin
    if (!s_rst_n) state <= DO_LOOPBACK == 0 ? ST_IN : ST_WAIT_IN;
    else          state <= next_state;
  end

  always_comb begin
    next_state = ST_XXX;
    case(state)
      ST_IN:
        next_state = DO_LOOPBACK == 0 ? state :
                    (infifo_seq_ctrl_vld && infifo_seq_ctrl_rdy && infifo_seq_eob && DO_LOOPBACK) ? ST_LOOPBACK :
                     infifo_seq_full_throughput ? state : ST_WAIT_IN;
      ST_WAIT_IN:
        next_state = infifo_seq_full_throughput ? ST_IN : state;
      ST_LOOPBACK:
        next_state = (s0_last_ntt_bwd && s0_wrap_stg && ntw_seq_ctrl_avail && ntw_seq_eob) ?
                        infifo_seq_full_throughput ? ST_IN : ST_WAIT_IN :
                        state;
    endcase
  end

  logic st_in;
  logic st_wait_in;
  logic st_loopback;

  assign st_in        = (state == ST_IN);
  assign st_wait_in   = (state == ST_WAIT_IN);
  assign st_loopback  = (state == ST_LOOPBACK);

  // ---------------------------------------------------------------------------------------------- --
  // Counters
  // ---------------------------------------------------------------------------------------------- --
  //   stg      : current stage
  //   ntt_bwd  : current forward or backward NTT process
  logic [STG_W-1:0]    s0_stg;
  logic                s0_ntt_bwd;
  logic [BPBS_ID_W-1:0] s0_pbs_idx_max;
  logic [BPBS_ID_W-1:0] s0_pbs_idx;
  logic [LPB_W-1:0]    s0_lpb_cnt;
  logic [STG_W-1:0]    s0_stgD;
  logic                s0_ntt_bwdD;
  logic                s0_in_eob_avail;
  logic                s0_in_eos_avail;
  logic [BPBS_ID_W-1:0] s0_pbs_idx_maxD;
  logic [BPBS_ID_W-1:0] s0_pbs_idxD;
  logic [LPB_W-1:0]    s0_lpb_cntD;
  logic                s0_last_stg;
  logic [STG_W-1:0]    s0_start_stg;
  logic                s0_last_lpb;


  assign s0_lpb_cntD     = s0_in_eob_avail ? s0_last_lpb ? '0 : s0_lpb_cnt + 1 : s0_lpb_cnt;

  assign s0_start_stg    = S-1;
  assign s0_stgD         = (DO_LOOPBACK && s0_in_eob_avail) ? s0_wrap_stg ? s0_start_stg : s0_stg - S_DEC_L : s0_stg;
  assign s0_ntt_bwdD     = (DO_LOOPBACK && s0_in_eob_avail && s0_wrap_stg) ? ~s0_ntt_bwd : s0_ntt_bwd;

  // Keep the total 
  assign s0_pbs_idx_maxD  = (infifo_seq_ctrl_vld && infifo_seq_ctrl_rdy && infifo_seq_sob) ? 0 :
                           (infifo_seq_ctrl_vld && infifo_seq_ctrl_rdy && infifo_seq_eog && !infifo_seq_eob) ? s0_pbs_idx_max + 1 : s0_pbs_idx_max;
  assign s0_pbs_idxD      = s0_in_eos_avail ? s0_in_eob_avail ? 0 : s0_pbs_idx + 1 : s0_pbs_idx;

  assign s0_in_eob_avail = (infifo_seq_ctrl_vld & infifo_seq_ctrl_rdy & infifo_seq_eob) 
                        | (ntw_seq_eob & ntw_seq_ctrl_avail);
  assign s0_in_eos_avail = (infifo_seq_ctrl_vld & infifo_seq_ctrl_rdy & infifo_seq_eog) 
                        | (ntw_seq_eos & ntw_seq_ctrl_avail);

  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      s0_stg         <= S_INIT;
      s0_ntt_bwd     <= NTT_BWD_INIT;
      s0_pbs_idx_max <= '0;
      s0_pbs_idx     <= '0;
      s0_lpb_cnt     <= '0;
    end else begin
      s0_stg         <= s0_stgD;
      s0_ntt_bwd     <= s0_ntt_bwdD;
      s0_pbs_idx_max <= s0_pbs_idx_maxD;
      s0_pbs_idx     <= s0_pbs_idxD;
      s0_lpb_cnt     <= s0_lpb_cntD;
    end
  end
  assign s0_last_lpb     = s0_lpb_cnt == (LPB_NB-1);
  assign s0_last_stg     = (s0_stg == 0);
  assign s0_wrap_stg     = s0_last_lpb;
  assign s0_last_ntt_bwd = ~DO_LOOPBACK | (s0_ntt_bwd != NTT_BWD_INIT);

  // ---------------------------------------------------------------------------------------------- --
  // Mux
  // ---------------------------------------------------------------------------------------------- --
  logic [PSI-1:0][R-1:0][    OP_W-1:0] s0_mux_data;
  logic                                s0_mux_sob;
  logic                                s0_mux_eob;
  logic                                s0_mux_sol;
  logic                                s0_mux_eol;
  logic                                s0_mux_sos;
  logic                                s0_mux_eos;
  logic                 [BPBS_ID_W-1:0] s0_mux_pbs_id;
  logic                                s0_mux_ctrl_avail;
  logic [PSI-1:0][R-1:0]               s0_mux_data_avail;
  logic                                s0_mux_last_pbs;

  assign s0_mux_data       = st_loopback ? ntw_seq_data  : infifo_seq_data  ;
  assign s0_mux_sob        = st_loopback ? ntw_seq_sob   : infifo_seq_sob   ;
  assign s0_mux_eob        = st_loopback ? ntw_seq_eob   : infifo_seq_eob   ;
  assign s0_mux_sol        = st_loopback ? ntw_seq_sol   : infifo_seq_sol   ;
  assign s0_mux_eol        = st_loopback ? ntw_seq_eol   : infifo_seq_eol   ;
  assign s0_mux_sos        = st_loopback ? ntw_seq_sos   : infifo_seq_sog   ;
  assign s0_mux_eos        = st_loopback ? ntw_seq_eos   : infifo_seq_eog   ;
  assign s0_mux_pbs_id     = st_loopback ? ntw_seq_pbs_id: infifo_seq_pbs_id;
  assign s0_mux_ctrl_avail = st_loopback ? ntw_seq_ctrl_avail : st_in & infifo_seq_ctrl_vld;
  assign s0_mux_data_avail = st_loopback ? ntw_seq_data_avail : {PSI*R{st_in}} & infifo_seq_data_vld;
  assign s0_mux_last_pbs   = st_loopback ? (s0_pbs_idx == s0_pbs_idx_max) : infifo_seq_last_pbs;

  // ---------------------------------------------------------------------------------------------- --
  // rden
  // ---------------------------------------------------------------------------------------------- --
  logic [STG_CYCLE_W-1:0] s0_stg_cycle_cnt;
  logic [STG_CYCLE_W-1:0] s0_stg_cycle_cntD;
  logic                   s0_rden;
  logic                   s0_rdenD;
  logic                   s0_rdenD_tmp;

  assign s0_stg_cycle_cntD = s0_mux_ctrl_avail ?
                                  s0_mux_eos ? 0 : s0_stg_cycle_cnt + 1 : s0_stg_cycle_cnt;

  assign s0_rdenD_tmp = s0_last_ntt_bwd ?
                               s0_last_stg ? (s0_stg_cycle_cnt == 0) : (s0_stg_cycle_cnt == BWD_SEND_RDEN_CYCLE) :
                               (s0_stg_cycle_cnt == FWD_SEND_RDEN_CYCLE);
  assign s0_rdenD     = s0_rdenD_tmp & s0_mux_ctrl_avail & s0_mux_last_pbs;

  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      s0_rden          <= 0;
      s0_stg_cycle_cnt <= 0;
    end else begin
      s0_rden          <= s0_rdenD;
      s0_stg_cycle_cnt <= s0_stg_cycle_cntD;
    end
  end

  // ---------------------------------------------------------------------------------------------- --
  // Output
  // ---------------------------------------------------------------------------------------------- --
  assign seq_clbu_data       = s0_mux_data;
  assign seq_clbu_sob        = s0_mux_sob;
  assign seq_clbu_eob        = s0_mux_eob;
  assign seq_clbu_sol        = s0_mux_sol;
  assign seq_clbu_eol        = s0_mux_eol;
  assign seq_clbu_sos        = s0_mux_sos;
  assign seq_clbu_eos        = s0_mux_eos;
  assign seq_clbu_pbs_id     = s0_mux_pbs_id;
  assign seq_clbu_ntt_bwd    = s0_ntt_bwd;
  assign seq_clbu_ctrl_avail = s0_mux_ctrl_avail;

  always_comb begin
    for (int i=0; i<PSI; i=i+1)
      seq_clbu_data_avail[i] = s0_mux_data_avail[i]; // Need only 1 available per CLBU
  end

  assign seq_ntw_bwd_rden    = s0_rden & s0_ntt_bwd;
  assign seq_ntw_fwd_rden    = s0_rden & ~s0_ntt_bwd;
  assign infifo_seq_ctrl_rdy = st_in;
  assign infifo_seq_data_rdy = {PSI*R{st_in}};

  // ---------------------------------------------------------------------------------------------- --
  // Assertion
  // ---------------------------------------------------------------------------------------------- --
// pragma translate_off
  // Check that while in st_in, once infifo_seq_ctrl_vld = 1 occurs, the signal stays to 1 until eob
  // is reached. Which means no bubbles.
  logic infifo_seq_ctrl_vld_dly;
  always_ff @(posedge clk) begin
    if (!s_rst_n)
      infifo_seq_ctrl_vld_dly <= 0;
    else
      infifo_seq_ctrl_vld_dly <= infifo_seq_ctrl_vld;
  end

  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      if (st_in && infifo_seq_ctrl_vld_dly && DO_LOOPBACK) begin
        assert(infifo_seq_ctrl_vld)
        else $fatal(1,"%t > ERROR: full throughput at the input is not ensured.", $time);
      end
    end
  end

  // check that the input avail / valid are always the same
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      // Do nothing
    end
    else begin
      assert(infifo_seq_data_vld == {PSI*R{infifo_seq_ctrl_vld}})
      else $fatal(1, "%t > ERROR: infifo_seq valids are not coherent.",$time);

      assert(ntw_seq_data_avail == {PSI*R{ntw_seq_ctrl_avail}})
      else $fatal(1, "%t > ERROR: ntw_seq valids are not coherent.",$time);
    end
  end
// pragma translate_on

endmodule

