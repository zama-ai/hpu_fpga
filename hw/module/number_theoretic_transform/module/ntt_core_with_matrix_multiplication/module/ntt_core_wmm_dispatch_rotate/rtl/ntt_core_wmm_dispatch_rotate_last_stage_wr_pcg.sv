// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
// This module deals with the dispatch and rotation of data before the writing in RAM.
// The data come from a pseudo constant geometric CLBU (pcg).
//
// Note: support only PSI = R^k.
//
// Assumption: Output RAM BU are ordered in reverse order.
//
// /!\ Warning: the command is written in the FIFO at s0 stage, i.e. as earlier as possible.
//   The data are sent to the RAM at stage s2.
//   Make sure with the different module latencies (dispatch_rotate_wr, FIFO, and ram_rd) that the
//   data are written before being read.
//
// ==============================================================================================

`include "ntt_core_common_macro_inc.sv"

module ntt_core_wmm_dispatch_rotate_last_stage_wr_pcg
  import param_tfhe_pkg::*;
  import pep_common_param_pkg::*;
  import ntt_core_wmm_pkg::*;
  import ntt_core_wmm_dispatch_rotate_pcg_pkg::*;
  import ntt_core_wmm_dispatch_rotate_last_stage_wr_pcg_pkg::*;
#(
  parameter int OP_W        = 32,
  parameter int R           = 2, // Butterfly Radix
  parameter int PSI         = 8, // Number of butterflies
  parameter int S           = $clog2(N)/$clog2(R), // Number of stages
  parameter bit IN_PIPE     = 1'b1, // recommended
  parameter int S_INIT      = S-1,
  parameter int S_DEC       = 1,
  parameter int DELTA       = S-1, // Number of BU steps
  parameter int TOKEN_W     = BATCH_TOKEN_W,
  parameter bit CLBU_OUT_WITH_NTW = 1'b1, // Same value as the CLBU connected to this module.
  `NTT_CORE_LOCALPARAM_HEADER(R,S,PSI)
) (
  input  logic                               clk,     // clock
  input  logic                               s_rst_n, // synchronous reset

  // input data from post-process
  input  logic [PSI-1:0][R-1:0][OP_W-1:0]       pp_drw_data,
  input  logic                                  pp_drw_sob,
  input  logic                                  pp_drw_eob,
  input  logic                                  pp_drw_sol,
  input  logic                                  pp_drw_eol,
  input  logic                                  pp_drw_sos,
  input  logic                                  pp_drw_eos,
  input  logic [BPBS_ID_W-1:0]                   pp_drw_pbs_id,
  input  logic                                  pp_drw_avail,

  // output data to RAM
  output logic [PSI-1:0][R-1:0][OP_W-1:0]       drw_ram_data,
  output logic                                  drw_ram_sob,
  output logic                                  drw_ram_eob,
  output logic                                  drw_ram_sol,
  output logic                                  drw_ram_eol,
  output logic                                  drw_ram_sos,
  output logic                                  drw_ram_eos,
  output logic [BPBS_ID_W-1:0]                   drw_ram_pbs_id,
  output logic [TOKEN_W-1:0]                    drw_ram_token,
  output logic [PSI-1:0][R-1:0][STG_ITER_W-1:0] drw_ram_add,
  output logic [INTL_L_W-1:0]                   drw_ram_intl_idx,
  output logic                                  drw_ram_avail,

  input  logic                                  token_release,

  // output command to FIFO
  output logic                                  drw_fifo_eob,
  output logic [BPBS_ID_W-1:0]                   drw_fifo_pbs_id,
  output logic [INTL_L_W-1:0]                   drw_fifo_intl_idx,
  output logic                                  drw_fifo_avail
);

  // =========================================================================================== --
  // localparam
  // =========================================================================================== --
  localparam int DELTA_IDX = DELTA - 1;
  localparam [LS_PARAM_NB-1:0][31:0] PARAM_LIST = get_pcg_ls_param(R, PSI, S, STG_ITER_NB, DELTA_IDX);

  localparam int SET_NB             = PARAM_LIST[LS_PARAM_OFS_SET_NB];
  localparam int CONS_NB            = PARAM_LIST[LS_PARAM_OFS_CONS_NB];
  localparam int OCC_NB             = PARAM_LIST[LS_PARAM_OFS_OCC_NB];
  localparam int ITER_CONS_NB       = PARAM_LIST[LS_PARAM_OFS_ITER_CONS_NB];

  localparam int SET_W              = $clog2(SET_NB);
  localparam int OCC_W              = $clog2(OCC_NB);
  localparam int CONS_W             = $clog2(CONS_NB);
  localparam int ITER_CONS_W        = $clog2(ITER_CONS_NB);

  localparam int S_DEC_L     = S_DEC % S;
  localparam int S_INIT_L    = S_INIT % S;
  localparam bit DO_LOOPBACK = (S_DEC > 0); // (1) : means that the current modules is used for different
                                            // stages (forward and backward taken into account)

  // Number of different write positions
  localparam int WR_POS_NB = (PSI * R + (STG_BU_NB - 1)) / STG_BU_NB;  // Is a power of 2
  localparam int WR_POS_W  = $clog2(WR_POS_NB);
  localparam int TOKEN_NB  = 2**TOKEN_W;

  localparam int SET_BU    = PSI / SET_NB;

  initial begin
    $display("R                  = %0d",R);
    $display("PSI                = %0d",PSI);
    $display("S                  = %0d",S);
    $display("DELTA              = %0d",DELTA);
    $display("SET_NB             = %0d",SET_NB);
    $display("CONS_NB            = %0d",CONS_NB);
    $display("OCC_NB             = %0d",OCC_NB);
    $display("ITER_CONS_NB       = %0d",ITER_CONS_NB);
  end

  // =========================================================================================== --
  // type
  // =========================================================================================== --
  typedef struct packed {
    logic                last_stg_iter;
    logic                sob;
    logic                eob;
    logic                sol;
    logic                eol;
    logic                sos;
    logic                eos;
    logic [BPBS_ID_W-1:0] pbs_id;
    logic [INTL_L_W-1:0] intl_idx;
  } control_t;

  localparam CTRL_W = $bits(control_t);

  typedef struct packed {
    logic [OP_W-1:0]       data;
    logic [STG_ITER_W-1:0] add;
  } data_t;

  localparam DT_W = $bits(data_t);

  // =========================================================================================== --
  // Input pipe
  // =========================================================================================== --
  logic [PSI-1:0][R-1:0][OP_W-1:0] s0_data;
  logic                            s0_sob;
  logic                            s0_eob;
  logic                            s0_sol;
  logic                            s0_eol;
  logic                            s0_sos;
  logic                            s0_eos;
  logic [BPBS_ID_W-1:0]             s0_pbs_id;
  logic                            s0_avail;

  generate
    if (IN_PIPE) begin : gen_in_reg
      always_ff @(posedge clk) begin
        if (!s_rst_n) s0_avail <= 1'b0;
        else          s0_avail <= pp_drw_avail;
      end

      // NOTE : if the synthesis enables it, we can use pp_drw_avail as enable
      // to save some power.
      always_ff @(posedge clk) begin
        s0_data    <= pp_drw_data;
        s0_sob     <= pp_drw_sob;
        s0_eob     <= pp_drw_eob;
        s0_sol     <= pp_drw_sol;
        s0_eol     <= pp_drw_eol;
        s0_sos     <= pp_drw_sos;
        s0_eos     <= pp_drw_eos;
        s0_pbs_id  <= pp_drw_pbs_id;
      end
    end else begin : gen_no_in_reg
      assign s0_data    = pp_drw_data;
      assign s0_sob     = pp_drw_sob;
      assign s0_eob     = pp_drw_eob;
      assign s0_sol     = pp_drw_sol;
      assign s0_eol     = pp_drw_eol;
      assign s0_sos     = pp_drw_sos;
      assign s0_eos     = pp_drw_eos;
      assign s0_pbs_id  = pp_drw_pbs_id;
      assign s0_avail   = pp_drw_avail;
    end
  endgenerate

  // =========================================================================================== --
  // Counters
  // =========================================================================================== --
  // Keep track of :
  //   stg_iter : current stage iteration
  //   stg      : current stage
  //   intl_idx : current level index

  logic [STG_ITER_W-1:0] s0_stg_iter;
  logic [INTL_L_W-1:0]   s0_intl_idx;
  logic [STG_ITER_W-1:0] s0_stg_iterD;
  logic [INTL_L_W-1:0]   s0_intl_idxD;
  logic                  s0_last_stg_iter;

  assign s0_stg_iterD = (s0_avail && s0_eol) ? s0_eos ? 0 : s0_stg_iter + 1 : s0_stg_iter;
  assign s0_intl_idxD = s0_avail ? s0_eol ? 0 : s0_intl_idx + 1 : s0_intl_idx;

  assign s0_last_stg_iter = (s0_stg_iter == (STG_ITER_NB -1));

  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      s0_stg_iter <= 0;
      s0_intl_idx <= 0;
    end else begin
      s0_stg_iter <= s0_stg_iterD;
      s0_intl_idx <= s0_intl_idxD;
    end
  end

  //== Prepare rotation
  logic [PSI_W-1:0] s0_rot_bu_factor;

  // Rot BU is done to place the BU correctly according to the destination BU_id
  logic [PSI_W-SET_W-CONS_W-1:0] s0_rot_idx;
  logic [PSI_W-SET_W-CONS_W-1:0] s0_rot_id;

  assign s0_rot_idx = s0_stg_iter >> ITER_CONS_W;

  //rot_id  = pseudo_reverse_order(rot_idx, R,PSI_SZ-SET_W-CONS_W, 0)
  always_comb begin
    s0_rot_id = '0;
    for (int i=0; i<PSI_SZ-SET_W-CONS_W; i=i+1)
      s0_rot_id[i] = s0_rot_idx[PSI_W-SET_W-CONS_W-1-i];
  end

  assign s0_rot_bu_factor = s0_rot_id << CONS_W;

  //== Prepare address
  logic [PSI-1:0][R-1:0][STG_ITER_W-1:0] s0_add;
  logic [S-2:0]                          s0_node_idx_0;
  logic [PSI-1:0][S-2:0]                 s0_next_stg_iter_0;

  assign s0_node_idx_0 = s0_stg_iter * PSI;

  always_comb
    for (int p=0; p<PSI; p=p+1) begin
      var [S-2:0] node_idx;
      var [S-2:0] node_id;
      var [S-2:0] next_node_id;
      var [STG_ITER_W-1:0] s0_next_stg_iter_0_tmp;

      node_idx = s0_node_idx_0 | p;
      //node_id = pseudo_everse_order(node_idx, R, S-1, DELTA_IDX)
      for (int i=0; i<S-1; i=i+1) begin
        if (i<DELTA_IDX)
          node_id[i] = node_idx[i];
        else
          node_id[i] = node_idx[S-2-(i-DELTA_IDX)];
      end
      next_node_id = node_id;
      s0_next_stg_iter_0_tmp = next_node_id >> PSI_SZ;

      s0_next_stg_iter_0[p] = s0_next_stg_iter_0_tmp;
      for (int r=0; r<R; r=r+1) begin
        s0_add[p][r] = s0_next_stg_iter_0[p];
      end
    end

  //== structure
  control_t                        s0_ctrl;
  logic [PSI-1:0][R-1:0][DT_W-1:0] s0_dt;

  assign s0_ctrl.last_stg_iter = s0_last_stg_iter;
  assign s0_ctrl.sob           = s0_sob;
  assign s0_ctrl.eob           = s0_eob;
  assign s0_ctrl.sol           = s0_sol;
  assign s0_ctrl.eol           = s0_eol;
  assign s0_ctrl.sos           = s0_sos;
  assign s0_ctrl.eos           = s0_eos;
  assign s0_ctrl.pbs_id        = s0_pbs_id;
  assign s0_ctrl.intl_idx      = s0_intl_idx;

  always_comb
    for (int p=0; p<PSI; p=p+1)
      for (int r=0; r<R; r=r+1) begin
        data_t d;
        d.add  = s0_add[p][r];
        d.data = s0_data[p][r];
        s0_dt[p][r] = d;
      end

  // =========================================================================================== --
  // s0
  // =========================================================================================== --
  // ------------------------------------------------------------------------------------------- --
  // s0 : Dispatch BU
  // ------------------------------------------------------------------------------------------- --
  // Note that the following dispatch is hardwired.
  logic [PSI-1:0][R-1:0][DT_W-1:0] s0_dp1_dt;

  generate
    for (genvar gen_p=0; gen_p<PSI; gen_p=gen_p+1) begin : s0_dp1_p_loop
      logic [S-2:0] s0_node_idx;
      logic [S-2:0] s0_node_id;
      logic [PSI_W-1:0] s0_next_bu_ofs;
      logic [OCC_W-1:0] s0_occ_id;
      logic [PSI_W-1:0] s0_next_bu;

      assign s0_node_idx = gen_p;

      // node_id = pseudo_reverse_order(node_idx, R, S-1, delta)
      always_comb
        for (int i=0; i<S-1; i=i+1) begin
          if (i<DELTA_IDX)
            s0_node_id[i] = s0_node_idx[i];
          else
            s0_node_id[i] = s0_node_idx[S-2-(i-DELTA_IDX)];
        end

      assign s0_next_bu_ofs = (PSI == 1) ? '0 : s0_node_id[PSI_W-1:0];

      if (OCC_NB > 1) begin : gen_s0_occ_gt_1
        logic [OCC_W-1:0] s0_occ_idx;
        assign s0_occ_idx = gen_p >> CONS_W;
        //occ_id = pseudo_reverse_order(occ_idx, R,int(log(occ_nb,2))//R_W, 0)
        always_comb
          for (int i=0; i<OCC_W; i=i+1)
            s0_occ_id[i] = s0_occ_idx[OCC_W-1-i];
      end
      else begin
        assign s0_occ_id = '0;
      end

      assign s0_next_bu = s0_next_bu_ofs + (s0_occ_id << CONS_W);

      assign s0_dp1_dt[gen_p] = s0_dt[s0_next_bu];
    end
  endgenerate

  // ------------------------------------------------------------------------------------------- --
  // s0 : Output to FIFO command
  // ------------------------------------------------------------------------------------------- --
  // Write a command at every stage end.
  assign drw_fifo_eob      = s0_ctrl.eob;
  assign drw_fifo_pbs_id   = s0_ctrl.pbs_id;
  assign drw_fifo_intl_idx = s0_ctrl.intl_idx;
  assign drw_fifo_avail    = s0_avail & s0_ctrl.last_stg_iter;

  // ------------------------------------------------------------------------------------------- --
  // s0-s1 pipe
  // ------------------------------------------------------------------------------------------- --
  logic [PSI-1:0][R-1:0][DT_W-1:0]       s1_dp1_dt;
  control_t                              s1_ctrl;
  logic [PSI_W-1:0]                      s1_rot_bu_factor;
  logic                                  s1_avail;

  generate
    if (LAT_PIPE_MH[0]) begin : gen_s0_s1_reg
      always_ff @(posedge clk) begin
        if (!s_rst_n) s1_avail <= 1'b0;
        else          s1_avail <= s0_avail;
      end

      always_ff @(posedge clk) begin
        s1_dp1_dt        <= s0_dp1_dt;
        s1_ctrl          <= s0_ctrl;
        s1_rot_bu_factor <= s0_rot_bu_factor;
      end
    end else begin : gen_no_s0_s1_reg
      assign s1_avail         = s0_avail;
      assign s1_dp1_dt        = s0_dp1_dt;
      assign s1_ctrl          = s0_ctrl;
      assign s1_rot_bu_factor = s0_rot_bu_factor;
    end
  endgenerate

  // =========================================================================================== --
  // s1
  // =========================================================================================== --
  // ------------------------------------------------------------------------------------------- --
  // s1 : Rotation BU
  // ------------------------------------------------------------------------------------------- --
  logic [PSI-1:0][R-1:0][DT_W-1:0] s1_rot1_dt;

  always_comb
    for (int p=0; p<PSI; p=p+1) begin
      var [PSI_W-1:0] rot_fact;
      rot_fact      = p - s1_rot_bu_factor;
      s1_rot1_dt[p] = s1_dp1_dt[rot_fact];
    end

  // ---------------------------------------------------------------------------------------------- --
  // s1 : PBS location in RAM
  // ---------------------------------------------------------------------------------------------- --
  logic [TOKEN_W:0]   s1_token_rp;
  logic [TOKEN_W:0]   s1_token_wp;
  logic [TOKEN_W:0]   s1_token_rpD;
  logic [TOKEN_W:0]   s1_token_wpD;
  logic [TOKEN_W-1:0] s1_token;
  logic               s1_token_full;
  logic               s1_token_empty;

  assign s1_token_rpD = (s1_avail && s1_ctrl.eos) ? s1_token_rp + 1 : s1_token_rp;
  assign s1_token_wpD = token_release ? s1_token_wp + 1: s1_token_wp;

  assign s1_token      = s1_token_rp;
  assign s1_token_full = (s1_token_wp[TOKEN_W-1:0] == s1_token_rp[TOKEN_W-1:0])
                        & (s1_token_wp[TOKEN_W] != s1_token_rp[TOKEN_W]);
  assign s1_token_empty = s1_token_rp == s1_token_wp;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      s1_token_rp <= '0;
      s1_token_wp <= TOKEN_NB; // It is a power of 2
    end
    else begin
      s1_token_rp <= s1_token_rpD;
      s1_token_wp <= s1_token_wpD;
    end

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // Do nothing
    end
    else begin
      if (s1_avail) begin
        assert(!s1_token_empty)
        else $fatal(1,"%t > ERROR: No more available token!", $time);
      end
      if (token_release) begin
        assert(!s1_token_full)
        else  $fatal(1,"%t > ERROR: Token stack overflow!", $time);
      end
    end
// pragma translate_on

  // ------------------------------------------------------------------------------------------- --
  // s1-s2 pipe
  // ------------------------------------------------------------------------------------------- --
  logic [PSI-1:0][R-1:0][DT_W-1:0]       s2_rot1_dt;
  control_t                              s2_ctrl;
  logic                                  s2_avail;
  logic [TOKEN_W-1:0]                    s2_token;

  generate
    if (LAT_PIPE_MH[1]) begin : gen_s1_s2_reg
      always_ff @(posedge clk) begin
        if (!s_rst_n) s2_avail <= 1'b0;
        else          s2_avail <= s1_avail;
      end

      always_ff @(posedge clk) begin
        s2_rot1_dt <= s1_rot1_dt;
        s2_ctrl    <= s1_ctrl;
        s2_token   <= s1_token;
      end
    end else begin : gen_no_s1_s2_reg
      assign s2_avail   = s1_avail;
      assign s2_rot1_dt = s1_rot1_dt;
      assign s2_ctrl    = s1_ctrl;
      assign s2_token   = s1_token;
    end
  endgenerate

  // =========================================================================================== --
  // s2
  // =========================================================================================== --
  // ------------------------------------------------------------------------------------------- --
  // Write in RAM
  // ------------------------------------------------------------------------------------------- --
  assign drw_ram_sob      = s2_ctrl.sob;
  assign drw_ram_eob      = s2_ctrl.eob;
  assign drw_ram_sol      = s2_ctrl.sol;
  assign drw_ram_eol      = s2_ctrl.eol;
  assign drw_ram_sos      = s2_ctrl.sos;
  assign drw_ram_eos      = s2_ctrl.eos;
  assign drw_ram_pbs_id   = s2_ctrl.pbs_id;
  assign drw_ram_token    = s2_token;
  assign drw_ram_intl_idx = s2_ctrl.intl_idx;
  assign drw_ram_avail    = s2_avail;

  always_comb
    for (int p=0; p<PSI; p=p+1)
      for (int r=0; r<R; r=r+1) begin
        data_t d;
        d = s2_rot1_dt[p][r];
        drw_ram_add[p][r]  = d.add;
        drw_ram_data[p][r] = d.data;
      end

endmodule
