// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
// NTT computation part model : CLBU + PP.
// This model modelize the latency of these modules, and the number of data change.
// To modelize the computation, data value part is increased by 1.
//
// Parameters:
//   S_INIT : initial S value
//   S_DEC  : stage counter decrement
//   CLBU_LAT : CLBU latency
//   PP_LAT : post process latency
// ==============================================================================================

module tb_ntt_core_wmm_clbu_pp_model
  import tb_ntt_core_wmm_clbu_pp_model_pkg::*;
  import param_tfhe_pkg::*;
  import pep_common_param_pkg::*;
  import ntt_core_common_param_pkg::*;
#(
  parameter int OP_W     = 32,
  parameter int S_INIT   = S-1, // initial value of stage counter
  parameter int S_DEC    = 1,    // stage counter decrement value.
  parameter int CLBU_LAT = 30,
  parameter int PP_LAT   = 15
)
(
  input                                     clk, // clock
  input                                     s_rst_n, // synchronous reset

  input logic [PSI-1:0][R-1:0][   OP_W-1:0] in_clbu_data,
  input logic [PSI-1:0]                     in_clbu_data_avail,

  input logic                               in_clbu_sob,
  input logic                               in_clbu_eob,
  input logic                               in_clbu_sol,
  input logic                               in_clbu_eol,
  input logic                               in_clbu_sos,
  input logic                               in_clbu_eos,
  input logic                [BPBS_ID_W-1:0] in_clbu_pbs_id,
  input logic                               in_clbu_ctrl_avail,

  // output data to regular stage
  output [PSI-1:0][R-1:0][    OP_W-1:0]     out_rsntw_data,
  output                                    out_rsntw_sob,
  output                                    out_rsntw_eob,
  output                                    out_rsntw_sol,
  output                                    out_rsntw_eol,
  output                                    out_rsntw_sos,
  output                                    out_rsntw_eos,
  output                 [BPBS_ID_W-1:0]     out_rsntw_pbs_id,
  output                                    out_rsntw_avail,
  // output data to last stage fwd and bwd, if this model is process other stages than
  // last stage. If not contains the fwd last stage.
  output [PSI-1:0][R-1:0][    OP_W-1:0]     out_lsntw_data,
  output                                    out_lsntw_sob,
  output                                    out_lsntw_eob,
  output                                    out_lsntw_sol,
  output                                    out_lsntw_eol,
  output                                    out_lsntw_sos,
  output                                    out_lsntw_eos,
  output                 [BPBS_ID_W-1:0]     out_lsntw_pbs_id,
  output                                    out_lsntw_avail,

  // output data to last stage bwd only, if this model processes only the last stage
  output [PSI-1:0][R-1:0][    OP_W-1:0]     out_bwd_lsntw_data,
  output                                    out_bwd_lsntw_sob,
  output                                    out_bwd_lsntw_eob,
  output                                    out_bwd_lsntw_sol,
  output                                    out_bwd_lsntw_eol,
  output                                    out_bwd_lsntw_sos,
  output                                    out_bwd_lsntw_eos,
  output                 [BPBS_ID_W-1:0]     out_bwd_lsntw_pbs_id,
  output                                    out_bwd_lsntw_avail
);

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int BWD_LAST_STAGE_PP_LAT = CLBU_LAT+PP_LAT; // should be > 1
  localparam int FWD_LAST_STAGE_PP_LAT = BWD_LAST_STAGE_PP_LAT + 2; // + 2 for the FWD PP acc
  localparam int DLY_DEPTH             = FWD_LAST_STAGE_PP_LAT + INTL_L; // Wait for all the levels before outputting the result
  localparam bit PROC_LS_ONLY          = (S_INIT%S) == 0 && (S_DEC % S) == 0;

// ============================================================================================== --
// type
// ============================================================================================== --
  typedef struct packed {
    logic [PSI-1:0][R-1:0][    OP_W-1:0] data;
    logic                                sob;
    logic                                eob;
    logic                                sol;
    logic                                eol;
    logic                                sos;
    logic                                eos;
    logic                 [BPBS_ID_W-1:0] pbs_id;
    logic                                rs_avail;
    logic                                ls_avail;
    logic                                ntt_bwd;
  } set_t;

// ============================================================================================== --
// tb_ntt_core_wmm_clbu_pp_model
// ============================================================================================== --
//-------------------------------------
// Counters
//-------------------------------------
  int   stg;
  int   intl_idx;
  logic ntt_bwd;

  int   stgD;
  int   intl_idxD;
  logic ntt_bwdD;

  logic last_stg;
  logic last_cnt_stg;

  assign stgD          = (in_clbu_ctrl_avail && in_clbu_eob) ? last_cnt_stg ? S_INIT : stg - S_DEC: stg;
  assign intl_idxD     = in_clbu_ctrl_avail ? in_clbu_eol ? 0 : intl_idx + 1 : intl_idx;
  assign ntt_bwdD      = (in_clbu_ctrl_avail && in_clbu_eob && last_cnt_stg) ? ~ntt_bwd : ntt_bwd;
  assign last_cnt_stg  = (stg < S_DEC);
  assign last_stg      = (stg == 0);

  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      stg      <= S_INIT;
      intl_idx <= 0;
      ntt_bwd  <= 0;
    end
    else begin
      stg      <= stgD     ;
      intl_idx <= intl_idxD;
      ntt_bwd  <= ntt_bwdD ;
    end
  end

//-------------------------------------
// Data process
//-------------------------------------
  logic [PSI-1:0][R-1:0][OP_W-1:0] clbu_data;

  always_comb begin
    for (int p=0; p<PSI; p=p+1) begin
      for (int r=0; r<R; r=r+1) begin
        clbu_pp_data_t d;
        d     = in_clbu_data[p][r];
        d.val = d.val + 1;
        clbu_data[p][r] = d;
      end
    end
  end

//-------------------------------------
// Delay lines
//-------------------------------------
  logic clbu_rs_ctrl_avail;
  logic clbu_ls_ctrl_avail;

  assign clbu_rs_ctrl_avail = in_clbu_ctrl_avail & ~last_stg;
  assign clbu_ls_ctrl_avail = in_clbu_ctrl_avail & last_stg & (ntt_bwd | (intl_idx >= (INTL_L - GLWE_K_P1)));

  set_t [DLY_DEPTH-1:0] set_dly  ;
  set_t [DLY_DEPTH-1:0] set_dlyD ;

  assign set_dlyD[0].data     = clbu_data;
  assign set_dlyD[0].sob      = in_clbu_sob;
  assign set_dlyD[0].eob      = in_clbu_eob;
  assign set_dlyD[0].sol      = in_clbu_sol;
  assign set_dlyD[0].eol      = in_clbu_eol;
  assign set_dlyD[0].sos      = in_clbu_sos;
  assign set_dlyD[0].eos      = in_clbu_eos;
  assign set_dlyD[0].pbs_id   = in_clbu_pbs_id;
  assign set_dlyD[0].rs_avail = clbu_rs_ctrl_avail;
  assign set_dlyD[0].ls_avail = clbu_ls_ctrl_avail;
  assign set_dlyD[0].ntt_bwd  = ntt_bwd;

  assign set_dlyD[DLY_DEPTH-1:1] = set_dly[DLY_DEPTH-2:0];

  always_ff @(posedge clk) begin
    if (!s_rst_n)
      set_dly <= 0;
    else
      set_dly <= set_dlyD;
  end

//-------------------------------------
// To network data
//-------------------------------------
  set_t set_dly_rs;
  set_t set_dly_ls_fwd;
  set_t set_dly_ls_bwd;
  set_t set_dly_ls_fwd_delayed;
  logic sel_bwd_ls;

  assign set_dly_rs     = set_dly[CLBU_LAT-1];
  assign set_dly_ls_fwd = set_dly[FWD_LAST_STAGE_PP_LAT-1];
  assign set_dly_ls_bwd = set_dly[BWD_LAST_STAGE_PP_LAT-1];
  assign set_dly_ls_fwd_delayed = set_dly[DLY_DEPTH-1];
  assign out_rsntw_data    = set_dly_rs.data   ;
  assign out_rsntw_sob     = set_dly_rs.sob    ;
  assign out_rsntw_eob     = set_dly_rs.eob    ;
  assign out_rsntw_sol     = set_dly_rs.sol    ;
  assign out_rsntw_eol     = set_dly_rs.eol    ;
  assign out_rsntw_sos     = set_dly_rs.sos    ;
  assign out_rsntw_eos     = set_dly_rs.eos    ;
  assign out_rsntw_pbs_id  = set_dly_rs.pbs_id ;
  assign out_rsntw_avail   = set_dly_rs.rs_avail;

  // logic data from post-process for last stage
  assign sel_bwd_ls = PROC_LS_ONLY ? 1'b0 : (set_dly_ls_bwd.ntt_bwd & set_dly_ls_bwd.ls_avail);
  assign out_lsntw_data    = sel_bwd_ls ? set_dly_ls_bwd.data    : set_dly_ls_fwd.data;
  assign out_lsntw_sob     = sel_bwd_ls ? set_dly_ls_bwd.sob     : set_dly_ls_fwd_delayed.sob;
  assign out_lsntw_eob     = sel_bwd_ls ? set_dly_ls_bwd.eob     : set_dly_ls_fwd.eob    ;
  assign out_lsntw_sol     = sel_bwd_ls ? set_dly_ls_bwd.sol     : set_dly_ls_fwd_delayed.sol;
  assign out_lsntw_eol     = sel_bwd_ls ? set_dly_ls_bwd.eol     : set_dly_ls_fwd.eol    ;
  assign out_lsntw_sos     = sel_bwd_ls ? set_dly_ls_bwd.sos     : set_dly_ls_fwd_delayed.sos;
  assign out_lsntw_eos     = sel_bwd_ls ? set_dly_ls_bwd.eos     : set_dly_ls_fwd.eos    ;
  assign out_lsntw_pbs_id  = sel_bwd_ls ? set_dly_ls_bwd.pbs_id  : set_dly_ls_fwd.pbs_id ;
  assign out_lsntw_avail   = sel_bwd_ls ? set_dly_ls_bwd.ls_avail & set_dly_ls_bwd.ntt_bwd :
                                         set_dly_ls_fwd.ls_avail & ~set_dly_ls_fwd.ntt_bwd;
  // logic data from post-process for last stage
  assign out_bwd_lsntw_data    = set_dly_ls_bwd.data    ;
  assign out_bwd_lsntw_sob     = set_dly_ls_bwd.sob     ;
  assign out_bwd_lsntw_eob     = set_dly_ls_bwd.eob     ;
  assign out_bwd_lsntw_sol     = set_dly_ls_bwd.sol     ;
  assign out_bwd_lsntw_eol     = set_dly_ls_bwd.eol     ;
  assign out_bwd_lsntw_sos     = set_dly_ls_bwd.sos     ;
  assign out_bwd_lsntw_eos     = set_dly_ls_bwd.eos     ;
  assign out_bwd_lsntw_pbs_id  = set_dly_ls_bwd.pbs_id  ;
  assign out_bwd_lsntw_avail   = PROC_LS_ONLY & set_dly_ls_bwd.ls_avail & set_dly_ls_bwd.ntt_bwd;

endmodule

