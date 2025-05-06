// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module manages the reading in the NTT RAMs.
// It also generates the control signal for new stage iteration.
// The reading is seen as the reading for the input of the new NTT stage iteration.
//
// Parameters:
//   RAM_LATENCY : RAM read latency
//   SEND_TO_SEQ : (1) output data are sent back to the sequencer.
//                 The synchronization is given by the sequencer: seq_ramrd_rden.
//                 (0) The output is sent to another processing level. Data are sent
//                 as soon as they are ready in RAM. No need to wait for some synchro signals.
//
// Pre-requisites:
// S > 1 : so that there is at least one "regular" stage, and a last stage.
//
// seq_ramrd_rden : pulse indicating that the reading of the stage can start, because all has been
//         received at the NTT input.
// ==============================================================================================

`include "ntt_core_common_macro_inc.sv"

module ntt_core_wmm_ram_rd_pcg
  import param_tfhe_pkg::*;
  import pep_common_param_pkg::*;
  import ntt_core_wmm_pkg::*;
  import ntt_core_wmm_ram_rd_pcg_pkg::*;
#(
  parameter int OP_W        = 32,
  parameter int R           = 8, // Butterfly Radix
  parameter int PSI         = 8, // Number of butterflies
  parameter int OUT_PSI_DIV = 2, // PSI/OUT_PSI_DIV : is the number of PSI for the following CLBU
  parameter int S           = $clog2(N)/$clog2(R), // Number of stages
  parameter int LPB_NB      = 1,
  parameter int RAM_LATENCY = 2,
  parameter int S_INIT      = S-2,
  parameter int S_DEC       = 1,
  parameter bit SEND_TO_SEQ = 1,
  parameter int TOKEN_W     = BATCH_TOKEN_W,
  `NTT_CORE_LOCALPARAM_HEADER(R,S,PSI)
) (
  input  logic                                  clk,     // clock
  input  logic                                  s_rst_n, // synchronous reset

  input  logic                                  seq_ramrd_rden, // pulse

  // RAM read interface
  output logic                                  ramrd_rsram_ren,
  output logic                                  ramrd_lsram_ren,
  output logic                 [STG_ITER_W-1:0] ramrd_ram_add,
  output logic                 [  INTL_L_W-1:0] ramrd_ram_intl_idx,
  output logic                 [   TOKEN_W-1:0] ramrd_ram_token,
  input  logic [PSI-1:0][R-1:0][      OP_W-1:0] ramrd_rsram_datar,
  input  logic [PSI-1:0][R-1:0][      OP_W-1:0] ramrd_lsram_datar,

  // Command FIFOs
  input  logic                                  rsfifo_ramrd_eob,
  input  logic [BPBS_ID_W-1:0]                   rsfifo_ramrd_pbs_id,
  input  logic [INTL_L_W-1:0]                   rsfifo_ramrd_intl_idx,
  input  logic                                  rsfifo_ramrd_vld,
  output logic                                  rsfifo_ramrd_rdy,

  input  logic                                  lsfifo_ramrd_eob,
  input  logic [BPBS_ID_W-1:0]                   lsfifo_ramrd_pbs_id,
  input  logic [INTL_L_W-1:0]                   lsfifo_ramrd_intl_idx,
  input  logic                                  lsfifo_ramrd_vld,
  output logic                                  lsfifo_ramrd_rdy,

  output logic                                  rstoken_release,
  output logic                                  lstoken_release,

  // Output to dispatch rotate
  output logic [PSI-1:0][R-1:0][    OP_W-1:0]   ramrd_drr_data,
  output logic [PSI-1:0][R-1:0]                 ramrd_drr_data_avail,

  output logic                                  ramrd_drr_sob,
  output logic                                  ramrd_drr_eob,
  output logic                                  ramrd_drr_sol,
  output logic                                  ramrd_drr_eol,
  output logic                                  ramrd_drr_sos,
  output logic                                  ramrd_drr_eos,
  output logic                 [BPBS_ID_W-1:0]   ramrd_drr_pbs_id,
  output logic                                  ramrd_drr_ctrl_avail

);

  // ============================================================================================== --
  // localparam
  // ============================================================================================== --
  localparam int RAM_LAT_LOCAL = get_ram_latency(RAM_LATENCY);
  localparam int TOKEN_NB      = 2**TOKEN_W;

  localparam int STG_ITER_NB_L = STG_ITER_NB * OUT_PSI_DIV;
  localparam int STG_ITER_W_L  = (STG_ITER_NB_L == 1) ? 1 : $clog2(STG_ITER_NB_L);

  localparam int S_INIT_L      = S_INIT % S;
  localparam int S_DEC_L       = S_DEC % S;
  localparam bit DO_LOOPBACK   = (S_DEC > 0);
  localparam bit NTT_BWD_INIT  = (S_INIT >= S);

  // Counter size to count from 0 to LPB_NB-1
  localparam int LPB_W         = $clog2(LPB_NB) == 0 ? 1 : $clog2(LPB_NB);
  // ============================================================================================== --
  // ntt_core_wmm_ram_rd_pcg
  // ============================================================================================== --
  // ---------------------------------------------------------------------------------------------- --
  // Counters
  // ---------------------------------------------------------------------------------------------- --
  // Keep track of :
  //   stg      : current stage
  //   stg_iter : current stage iteration (taking into account OUT_PSI_DIV)
  //   intl_idx : current interleaved level
  //   ntt_bwd  : current forward or backward NTT process
  //   lpb_cnt  : current loopback occurence
  logic [  INTL_L_W-1:0]    s0_intl_idx;
  logic [STG_ITER_W_L-1:0]  s0_stg_iter;
  logic [     STG_W-1:0]    s0_stg;
  logic                     s0_ntt_bwd;
  logic [LPB_W-1:0]         s0_lpb;

  logic [  INTL_L_W-1:0]    s0_intl_idxD;
  logic [STG_ITER_W_L-1:0]  s0_stg_iterD;
  logic [     STG_W-1:0]    s0_stgD;
  logic                     s0_ntt_bwdD;
  logic [LPB_W-1:0]         s0_lpbD;

  logic                  s0_first_stg;
  logic                  s0_wrap_stg;
  logic                  s0_first_intl_idx;
  logic                  s0_last_intl_idx;
  logic                  s0_first_stg_iter;
  logic                  s0_last_stg_iter;
  logic [  INTL_L_W-1:0] s0_intl_idx_max;
  logic [    STG_W-1:0]  s0_stg_dec;
  logic                  s0_last_lpb;

  logic                  s0_cmd_vld;
  logic                  s0_cmd_rdy;
  logic                  s0_cmd_sob;
  logic                  s0_cmd_eob;
  logic [  BPBS_ID_W-1:0] s0_cmd_pbs_id;
  logic [  INTL_L_W-1:0] s0_cmd_intl_idx;

  assign s0_intl_idx_max = (!s0_ntt_bwd && !s0_first_stg) ? INTL_L - 1 : (GLWE_K_P1 - 1);

  assign s0_last_lpb       = (s0_lpb == LPB_NB-1);
  assign s0_first_stg      = (s0_stg == (S - 1));
  assign s0_wrap_stg       = ~DO_LOOPBACK | (s0_stg < S_DEC);
  assign s0_first_intl_idx = (s0_intl_idx == 0);
  assign s0_last_intl_idx  = (s0_intl_idx == s0_intl_idx_max);
  assign s0_first_stg_iter = (s0_stg_iter == 0);
  assign s0_last_stg_iter  = (s0_stg_iter == (STG_ITER_NB_L - 1));
  assign s0_stg_dec        = s0_stg < S_DEC_L ? S-1 : s0_stg - S_DEC_L; // if S_DEC_L > s0_stg => last stage reached

  assign s0_lpbD      = (s0_cmd_vld && s0_cmd_rdy && s0_cmd_eob) ? s0_last_lpb ? '0 : s0_lpb + 1 : s0_lpb;
  assign s0_stgD      = (DO_LOOPBACK && s0_cmd_vld && s0_cmd_rdy && s0_cmd_eob) ? s0_last_lpb ? S_INIT_L : s0_stg_dec :
                        s0_stg;
  assign s0_stg_iterD = (s0_cmd_vld && s0_last_intl_idx) ? s0_last_stg_iter ? 0 : s0_stg_iter + 1 :
                        s0_stg_iter;
  assign s0_intl_idxD = s0_cmd_vld ? s0_last_intl_idx ? 0 : s0_intl_idx + 1 : s0_intl_idx;
  assign s0_ntt_bwdD  = (DO_LOOPBACK && s0_cmd_vld && s0_cmd_rdy && s0_cmd_eob && s0_wrap_stg) ? ~s0_ntt_bwd :
                        s0_ntt_bwd;

  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      s0_intl_idx <= 0;
      s0_stg_iter <= 0;
      s0_stg      <= S_INIT_L;
      s0_ntt_bwd  <= NTT_BWD_INIT;
      s0_lpb      <= '0;
    end else begin
      s0_intl_idx <= s0_intl_idxD;
      s0_stg_iter <= s0_stg_iterD;
      s0_stg      <= s0_stgD;
      s0_ntt_bwd  <= s0_ntt_bwdD;
      s0_lpb      <= s0_lpbD;
    end
  end

  // ---------------------------------------------------------------------------------------------- --
  // Current command
  // ---------------------------------------------------------------------------------------------- --
  logic       s0_sol;
  logic       s0_eol;
  logic       s0_sos;
  logic       s0_eos;
  logic       s0_sob;
  logic       s0_sobD;
  logic       s0_eob;
  logic [1:0] s0_rden_cnt;
  logic [1:0] s0_rden_cntD;
  logic       s0_rden;

  typedef enum integer {
                ST_XXX = 'x,
                ST_WAIT = '0,
                ST_READ} state_e;

  state_e state;
  state_e next_state;

  always_ff @(posedge clk) begin
    if (!s_rst_n) state <= ST_WAIT;
    else          state <= next_state;
  end

  always_comb begin
    next_state = ST_XXX;
    case(state)
      ST_WAIT :
        next_state = s0_rden ? ST_READ : state;
      ST_READ :
        next_state = (s0_cmd_vld && s0_cmd_rdy && s0_cmd_eob) ? 
                          s0_rden ? ST_READ : ST_WAIT : state;
    endcase
  end

  logic st_wait;
  logic st_read;
  assign st_wait = (state == ST_WAIT);
  assign st_read = (state == ST_READ);

  assign s0_sol           = s0_first_intl_idx;
  assign s0_eol           = s0_last_intl_idx;
  assign s0_sos           = s0_first_stg_iter & s0_first_intl_idx;
  assign s0_eos           = s0_last_stg_iter & s0_last_intl_idx;

  logic s0_cmd_vld_tmp;
  assign s0_cmd_vld_tmp   = s0_first_stg ? lsfifo_ramrd_vld : rsfifo_ramrd_vld;
  assign s0_cmd_vld       = st_read & s0_cmd_vld_tmp;
  assign lsfifo_ramrd_rdy = s0_first_stg & s0_cmd_rdy;
  assign rsfifo_ramrd_rdy = ~s0_first_stg & s0_cmd_rdy;

  assign s0_cmd_eob       = s0_first_stg ? lsfifo_ramrd_eob : rsfifo_ramrd_eob;
  assign s0_cmd_pbs_id    = s0_first_stg ? lsfifo_ramrd_pbs_id : rsfifo_ramrd_pbs_id;
  assign s0_cmd_intl_idx  = s0_first_stg ? lsfifo_ramrd_intl_idx : rsfifo_ramrd_intl_idx;

  // There is 1 cmd per level in the FIFO.
  // The presence of the command inside the FIFO indicates that the whole level has been received.
  // Accept the first levels' command once available. => The corresponding levels are present.
  // Sample the last level's command only at the end of the stage.
  assign s0_cmd_rdy       = st_read & ((~s0_last_intl_idx & s0_first_stg_iter) | (s0_last_intl_idx & s0_last_stg_iter));

  // Prepare next
  assign s0_sobD          = s0_cmd_vld ? (s0_eos && s0_cmd_eob) ? 1'b1 : 1'b0 : s0_sob;
  assign s0_eob           = s0_cmd_eob & s0_eos; // Since all the levels'commands except the last one have been parsed
                                                 // at the beginning of the stage.
                                                 // s0_cmd_eob is the one of the command last level. Take it into account only
                                                 // at the end of the stage.

  always_ff @(posedge clk)
    if (!s_rst_n) s0_sob      <= 1'b1;
    else          s0_sob      <= s0_sobD;

  generate
    if (SEND_TO_SEQ) begin : send_to_seq_gen
      assign s0_rden = (s0_rden_cnt > 0);

      assign s0_rden_cntD     = seq_ramrd_rden ? (s0_cmd_vld && s0_sob) ? s0_rden_cnt : s0_rden_cnt + 1 :
                                                 (s0_cmd_vld && s0_sob) ? s0_rden_cnt - 1 : s0_rden_cnt;
      always_ff @(posedge clk)
        if (!s_rst_n) s0_rden_cnt <= 1'b0;
        else          s0_rden_cnt <= s0_rden_cntD;

// pragma translate_off
      always_ff @(posedge clk)
        if (!s_rst_n) begin
          // do nothing
        end
        else begin
          if (seq_ramrd_rden)
            assert(s0_rden_cnt < 2)
            else $fatal(1,"> ERROR: seq_ramrd_rden occurs while s0_rden_cnt is equal to 2! Overflow!");
        end
// pragma translate_on
    end
    else begin: no_send_to_seq_gen
      assign s0_rden = 1'b1;
    end
  endgenerate

  // ---------------------------------------------------------------------------------------------- --
  // RAM read request
  // ---------------------------------------------------------------------------------------------- --
  logic [TOKEN_W-1:0] rsram_token;
  logic [TOKEN_W-1:0] rsram_tokenD;
  logic [TOKEN_W-1:0] lsram_token;
  logic [TOKEN_W-1:0] lsram_tokenD;

  assign rstoken_release = (rsfifo_ramrd_vld && rsfifo_ramrd_rdy && s0_eos);
  assign lstoken_release = (lsfifo_ramrd_vld && lsfifo_ramrd_rdy && s0_eos);

  assign rsram_tokenD = rstoken_release ? rsram_token + 1 : rsram_token;
  assign lsram_tokenD = lstoken_release ? lsram_token + 1 : lsram_token;


  always_ff @(posedge clk)
    if (!s_rst_n) begin
      rsram_token <= '0;
      lsram_token <= '0;
    end
    else begin
      rsram_token <= rsram_tokenD;
      lsram_token <= lsram_tokenD;
    end

  logic                  ramrd_rsram_renD;
  logic                  ramrd_lsram_renD;
  logic [STG_ITER_W-1:0] ramrd_ram_addD;
  logic [  INTL_L_W-1:0] ramrd_ram_intl_idxD;
  logic [ TOKEN_W-1:0]   ramrd_ram_tokenD;

  assign ramrd_rsram_renD    = s0_cmd_vld & ~s0_first_stg;
  assign ramrd_lsram_renD    = s0_cmd_vld & s0_first_stg;
  assign ramrd_ram_addD      = s0_stg_iter[$clog2(OUT_PSI_DIV)+:STG_ITER_W];
  assign ramrd_ram_intl_idxD = s0_intl_idx;
  assign ramrd_ram_tokenD    = s0_first_stg ? lsram_token : rsram_token;

  generate
    if (LAT_PIPE_MH[0]) begin : ram_req_reg
      always_ff @(posedge clk) begin
        if (!s_rst_n) begin
          ramrd_rsram_ren    <= 1'b0;
          ramrd_lsram_ren    <= 1'b0;
        end else begin
          ramrd_rsram_ren   <= ramrd_rsram_renD;
          ramrd_lsram_ren   <= ramrd_lsram_renD;
        end
      end
      always_ff @(posedge clk) begin
        ramrd_ram_add      <= ramrd_ram_addD;
        ramrd_ram_intl_idx <= ramrd_ram_intl_idxD;
        ramrd_ram_token    <= ramrd_ram_tokenD;
      end
    end else begin : no_req_reg
      assign ramrd_rsram_ren    = ramrd_rsram_renD;
      assign ramrd_lsram_ren    = ramrd_lsram_renD;
      assign ramrd_ram_add      = ramrd_ram_addD;
      assign ramrd_ram_intl_idx = ramrd_ram_intl_idxD;
      assign ramrd_ram_token    = ramrd_ram_tokenD;
    end
  endgenerate

  // ---------------------------------------------------------------------------------------------- --
  // Output
  // ---------------------------------------------------------------------------------------------- --
  logic [RAM_LAT_LOCAL-1:0]               s1_sob_dly;
  logic [RAM_LAT_LOCAL-1:0]               s1_eob_dly;
  logic [RAM_LAT_LOCAL-1:0]               s1_sol_dly;
  logic [RAM_LAT_LOCAL-1:0]               s1_eol_dly;
  logic [RAM_LAT_LOCAL-1:0]               s1_sos_dly;
  logic [RAM_LAT_LOCAL-1:0]               s1_eos_dly;
  logic [RAM_LAT_LOCAL-1:0][BPBS_ID_W-1:0] s1_pbs_id_dly;
  logic [RAM_LAT_LOCAL-1:0]               s1_avail_dly;
  logic [RAM_LAT_LOCAL-1:0]               s1_first_stg_dly;
  logic [PSI-1:0][R-1:0]                  s1_data_avail;

  logic [RAM_LAT_LOCAL-1:0]               s1_sob_dlyD;
  logic [RAM_LAT_LOCAL-1:0]               s1_eob_dlyD;
  logic [RAM_LAT_LOCAL-1:0]               s1_sol_dlyD;
  logic [RAM_LAT_LOCAL-1:0]               s1_eol_dlyD;
  logic [RAM_LAT_LOCAL-1:0]               s1_sos_dlyD;
  logic [RAM_LAT_LOCAL-1:0]               s1_eos_dlyD;
  logic [RAM_LAT_LOCAL-1:0][BPBS_ID_W-1:0] s1_pbs_id_dlyD;
  logic [RAM_LAT_LOCAL-1:0]               s1_avail_dlyD;
  logic [RAM_LAT_LOCAL-1:0]               s1_first_stg_dlyD;
  logic [PSI-1:0][R-1:0]                  s1_data_availD;

  assign s1_sob_dlyD[0]       = s0_sob;
  assign s1_eob_dlyD[0]       = s0_eob;
  assign s1_sol_dlyD[0]       = s0_sol;
  assign s1_eol_dlyD[0]       = s0_eol;
  assign s1_sos_dlyD[0]       = s0_sos;
  assign s1_eos_dlyD[0]       = s0_eos;
  assign s1_pbs_id_dlyD[0]    = s0_cmd_pbs_id;
  assign s1_avail_dlyD[0]     = s0_cmd_vld;
  assign s1_first_stg_dlyD[0] = s0_first_stg;

  generate
    if (RAM_LAT_LOCAL > 1) begin : RAM_LAT_LOCAL_gt_1
      assign s1_sob_dlyD[RAM_LAT_LOCAL-1:1]       = s1_sob_dly[RAM_LAT_LOCAL-2:0];
      assign s1_eob_dlyD[RAM_LAT_LOCAL-1:1]       = s1_eob_dly[RAM_LAT_LOCAL-2:0];
      assign s1_sol_dlyD[RAM_LAT_LOCAL-1:1]       = s1_sol_dly[RAM_LAT_LOCAL-2:0];
      assign s1_eol_dlyD[RAM_LAT_LOCAL-1:1]       = s1_eol_dly[RAM_LAT_LOCAL-2:0];
      assign s1_sos_dlyD[RAM_LAT_LOCAL-1:1]       = s1_sos_dly[RAM_LAT_LOCAL-2:0];
      assign s1_eos_dlyD[RAM_LAT_LOCAL-1:1]       = s1_eos_dly[RAM_LAT_LOCAL-2:0];
      assign s1_pbs_id_dlyD[RAM_LAT_LOCAL-1:1]    = s1_pbs_id_dly[RAM_LAT_LOCAL-2:0];
      assign s1_avail_dlyD[RAM_LAT_LOCAL-1:1]     = s1_avail_dly[RAM_LAT_LOCAL-2:0];
      assign s1_first_stg_dlyD[RAM_LAT_LOCAL-1:1] = s1_first_stg_dly[RAM_LAT_LOCAL-2:0];
    end
  endgenerate

  assign s1_data_availD = {PSI*R{s1_avail_dlyD[RAM_LAT_LOCAL-1]}}; // Duplicate "avail" to ease P&R

  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      s1_avail_dly  <= {RAM_LAT_LOCAL{1'b0}};
      s1_data_avail <= {PSI*R{1'b0}};
    end else begin
      s1_avail_dly  <= s1_avail_dlyD;
      s1_data_avail <= s1_data_availD;
    end
  end

  always_ff @(posedge clk) begin
    s1_sob_dly       <= s1_sob_dlyD;
    s1_eob_dly       <= s1_eob_dlyD;
    s1_sol_dly       <= s1_sol_dlyD;
    s1_eol_dly       <= s1_eol_dlyD;
    s1_sos_dly       <= s1_sos_dlyD;
    s1_eos_dly       <= s1_eos_dlyD;
    s1_pbs_id_dly    <= s1_pbs_id_dlyD;
    s1_first_stg_dly <= s1_first_stg_dlyD;
  end

  assign ramrd_drr_data       = s1_first_stg_dly[RAM_LAT_LOCAL-1] ? ramrd_lsram_datar : ramrd_rsram_datar;
  assign ramrd_drr_sob        = s1_sob_dly[RAM_LAT_LOCAL-1];
  assign ramrd_drr_eob        = s1_eob_dly[RAM_LAT_LOCAL-1];
  assign ramrd_drr_sol        = s1_sol_dly[RAM_LAT_LOCAL-1];
  assign ramrd_drr_eol        = s1_eol_dly[RAM_LAT_LOCAL-1];
  assign ramrd_drr_sos        = s1_sos_dly[RAM_LAT_LOCAL-1];
  assign ramrd_drr_eos        = s1_eos_dly[RAM_LAT_LOCAL-1];
  assign ramrd_drr_pbs_id     = s1_pbs_id_dly[RAM_LAT_LOCAL-1];
  assign ramrd_drr_ctrl_avail = s1_avail_dly[RAM_LAT_LOCAL-1];
  assign ramrd_drr_data_avail = s1_data_avail;

  // ---------------------------------------------------------------------------------------------- --
  // Assertion
  // ---------------------------------------------------------------------------------------------- --
  // pragma translate_off
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      // do nothing
    end else begin
      if (s0_cmd_vld && s0_cmd_rdy) begin
        assert (s0_cmd_intl_idx == s0_intl_idx)
        else
          $error(
              "%t > ERROR: Interleaved level mismatch: cmd=0x%x, cnt=0x%x", $time,
              s0_cmd_intl_idx,
              s0_intl_idx
          );
      end
    end
  end
  // pragma translate_on
endmodule
