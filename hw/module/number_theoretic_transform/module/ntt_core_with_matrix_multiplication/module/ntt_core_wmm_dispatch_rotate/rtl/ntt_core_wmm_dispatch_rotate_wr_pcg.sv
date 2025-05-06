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
// /!\ Warning: the command is written in the FIFO at s2 stage, i.e. as earlier as possible.
//   The data are sent to the RAM at stage s3.
//   Make sure with the different module latencies (dispatch_rotate_wr, FIFO, and ram_rd) that the
//   data are written before being read.
//
// ==============================================================================================

`include "ntt_core_common_macro_inc.sv"

module ntt_core_wmm_dispatch_rotate_wr_pcg
  import param_tfhe_pkg::*;
  import pep_common_param_pkg::*;
  import ntt_core_wmm_pkg::*;
  import ntt_core_wmm_dispatch_rotate_pcg_pkg::*;
  import ntt_core_wmm_dispatch_rotate_wr_pcg_pkg::*;
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
  input  logic [BPBS_ID_W-1:0]                  pp_drw_pbs_id,
  input  logic                                  pp_drw_avail,

  // output data to RAM
  output logic [PSI-1:0][R-1:0][OP_W-1:0]       drw_ram_data,
  output logic                                  drw_ram_sob,
  output logic                                  drw_ram_eob,
  output logic                                  drw_ram_sol,
  output logic                                  drw_ram_eol,
  output logic                                  drw_ram_sos,
  output logic                                  drw_ram_eos,
  output logic [BPBS_ID_W-1:0]                  drw_ram_pbs_id,
  output logic [TOKEN_W-1:0]                    drw_ram_token,
  output logic [PSI-1:0][R-1:0][STG_ITER_W-1:0] drw_ram_add,
  output logic [INTL_L_W-1:0]                   drw_ram_intl_idx,
  output logic                                  drw_ram_avail,

  input  logic                                  token_release,

  // output command to FIFO
  output logic                                  drw_fifo_eob,
  output logic [BPBS_ID_W-1:0]                  drw_fifo_pbs_id,
  output logic [INTL_L_W-1:0]                   drw_fifo_intl_idx,
  output logic                                  drw_fifo_avail
);

  // =========================================================================================== --
  // localparam
  // =========================================================================================== --
  localparam int DELTA_IDX = DELTA - 1;
  localparam [PARAM_NB-1:0][31:0] PARAM_LIST = get_pcg_param(R, PSI, S, STG_ITER_NB, DELTA_IDX);

  localparam int GROUP_SIZE         = PARAM_LIST[PARAM_OFS_GROUP_SIZE];
  localparam int GROUP_NB           = PARAM_LIST[PARAM_OFS_GROUP_NB];
  localparam int TOTAL_GROUP_NB     = PARAM_LIST[PARAM_OFS_TOTAL_GROUP_NB];
  localparam int GROUP_NB_L         = PARAM_LIST[PARAM_OFS_GROUP_NB_L];
  localparam int GROUP_NODE         = PARAM_LIST[PARAM_OFS_GROUP_NODE];
  localparam int GROUP_STG_ITER_NB  = PARAM_LIST[PARAM_OFS_GROUP_STG_ITER_NB];
  localparam int POS_NB             = PARAM_LIST[PARAM_OFS_POS_NB];
  localparam int STG_ITER_THRESHOLD = PARAM_LIST[PARAM_OFS_STG_ITER_THRESHOLD];
  localparam int SET_NB             = PARAM_LIST[PARAM_OFS_SET_NB];
  localparam int CONS_NB            = PARAM_LIST[PARAM_OFS_CONS_NB];
  localparam int ITER_CONS_NB       = PARAM_LIST[PARAM_OFS_ITER_CONS_NB];
  localparam int ITER_SET_NB        = PARAM_LIST[PARAM_OFS_ITER_SET_NB];

  localparam int S_DEC_L     = S_DEC % S;
  localparam int S_INIT_L    = S_INIT % S;
  localparam bit DO_LOOPBACK = (S_DEC > 0); // (1) : means that the current modules is used for different
                                            // stages (forward and backward taken into account)

  // Number of different write positions
  localparam int WR_POS_NB = (PSI * R + (STG_BU_NB - 1)) / STG_BU_NB;  // Is a power of 2
  localparam int WR_POS_W  = $clog2(WR_POS_NB);
  localparam int TOKEN_NB  = 2**TOKEN_W;

  localparam int GROUP_NODE_W = $clog2(GROUP_NODE);
  localparam int SET_W        = $clog2(SET_NB);
  localparam int ITER_CONS_W  = $clog2(ITER_CONS_NB);
  localparam int ITER_SET_W   = $clog2(ITER_SET_NB);
  localparam int SET_BU_NB    = PSI / SET_NB;

  // check parameters
  generate
    // For now support only PSI that is a power of R <=> Groups are entire.
    if ((POS_NB > 1) && (PSI*R < GROUP_NODE)) begin : __UNSUPPORTED_PSI_
      $fatal(1,"> ERROR: Unsupported PSI value (%d). Should be a power of R (R^k). GROUP_NODE=%d",PSI,GROUP_NODE);
    end
  endgenerate

  initial begin
    $display("R                  =%d",R);
    $display("PSI                =%d",PSI);
    $display("S                  =%d",S);
    $display("DELTA              =%d",DELTA);
    $display("GROUP_SIZE         =%d",GROUP_SIZE);
    $display("GROUP_NB           =%d",GROUP_NB);
    $display("TOTAL_GROUP_NB     =%d",TOTAL_GROUP_NB);
    $display("GROUP_NB_L         =%d",GROUP_NB_L);
    $display("GROUP_NODE         =%d",GROUP_NODE);
    $display("GROUP_STG_ITER_NB  =%d",GROUP_STG_ITER_NB);
    $display("POS_NB             =%d",POS_NB);
    $display("STG_ITER_THRESHOLD =%d",STG_ITER_THRESHOLD);
    $display("SET_NB             =%d",SET_NB);
    $display("CONS_NB            =%d",CONS_NB);
    $display("ITER_CONS_NB       =%d",ITER_CONS_NB);
    $display("ITER_SET_NB        =%d",ITER_SET_NB);
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
    logic [STG_ITER_W-1:0] add;
    logic [OP_W-1:0]       data;
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
  logic [R_W-1:0]   s0_rot_r_factor;
  logic [PSI_W-1:0] s0_rot_bu_factor;

  // Rot R is done to place the data correctly according to its pos_id
  assign s0_rot_r_factor = (s0_stg_iter * (PSI*R)) / GROUP_NODE;

  // Rot BU is done to place the BU correctly according to the destination BU_id
  generate
    if (PSI == 1) begin : gen_rot_bu_factor_psi_eq_1
      assign s0_rot_bu_factor = '0;
    end
    else begin : gen_rot_bu_factor_psi_gt_1
      if (POS_NB > 1) begin : gen_rot_bu_factor_pos_nb_gt_1
        logic [GROUP_NODE_W-1:0] s0_stg_iter_lsb;
        logic [PSI_W-SET_W-1:0]  s0_rot_bu_factor_tmp;

        assign s0_stg_iter_lsb = s0_stg_iter; // truncate or extend with 0
        assign s0_rot_bu_factor_tmp = s0_stg_iter_lsb * CONS_NB;
        assign s0_rot_bu_factor = s0_rot_bu_factor_tmp; // extend with 0
      end
      else begin : gen_rot_bu_factor_pos_nb_eq_1
        if (ITER_SET_NB == 1) begin : gen_iter_set_eq_1
          assign s0_rot_bu_factor = s0_stg_iter >> (R_W+ITER_CONS_W);
        end
        else begin : gen_iter_set_gt_1
          logic [PSI_W-1:0] s0_rot_bu_factor_tmp1;
          logic [PSI_W-SET_W-1:0] s0_iter_set_idx;
          logic [PSI_W-SET_W-1:0] s0_iter_set_id;
          logic [STG_ITER_W-1:0] s0_stg_iter_msb;

          assign s0_iter_set_idx = s0_stg_iter[ITER_CONS_W+:ITER_SET_W];

          // TODO : for R!=2
          always_comb begin begin
            s0_iter_set_id = '0;
            for (int i=0; i<PSI_SZ-SET_W; i=i+1)
              s0_iter_set_id[i] = s0_iter_set_idx[PSI_W-SET_W-1-i];
          end
          end
          assign s0_stg_iter_msb = s0_stg_iter >> (R_W+ITER_SET_W+ITER_CONS_W);
          assign s0_rot_bu_factor = s0_iter_set_id + s0_stg_iter_msb;
        end
      end
    end
  endgenerate

  //== Prepare address
  logic [PSI-1:0][R-1:0][STG_ITER_W-1:0] s0_add_bef_ntw;
  logic [PSI-1:0][R-1:0][STG_ITER_W-1:0] s0_add;
  logic [S-2:0]                          s0_node_idx_0;
  logic [PSI-1:0][STG_ITER_W-1:0]        s0_next_stg_iter_0;

  assign s0_node_idx_0 = s0_stg_iter * PSI;

  generate
    always_comb
      for (int p=0; p<PSI; p=p+1) begin
        var [S-2:0] node_idx;
        var [S-2:0] node_id;
        var [S-2:0] next_node_id;
        var [STG_ITER_W-1:0] s0_next_stg_iter_0_tmp;

        node_idx = s0_node_idx_0 | p;
        //node_id = pseudo_reverse_order(node_idx, R, S-1, delta)
        for (int i=0; i<S-1; i=i+1) begin
          if (i<DELTA_IDX)
            node_id[i] = node_idx[i];
          else
            node_id[i] = node_idx[S-2-(i-DELTA_IDX)];
        end
        next_node_id = (node_id << R_W);
        s0_next_stg_iter_0_tmp = next_node_id[STG_ITER_W-1:0];

        s0_next_stg_iter_0[p] = s0_next_stg_iter_0_tmp;
        for (int r=0; r<R; r=r+1) begin
          var [STG_ITER_W-1:0] next_stg_iter_tmp;
          next_stg_iter_tmp = s0_next_stg_iter_0[p] | r;
          //next_stg_iter     = pseudo_reverse_order(next_stg_iter_tmp, R, STG_ITER_W, 0)
          if (STG_ITER_NB > 1) begin
            for (int i=0; i<STG_ITER_W; i=i+1) begin
              s0_add_bef_ntw[p][r][i] = next_stg_iter_tmp[STG_ITER_W-1-i];
            end
          end
          else begin
            s0_add_bef_ntw[p][r] = '0;
          end
        end
      end
  endgenerate

  // Apply CLBU network on it
  generate
    if (CLBU_OUT_WITH_NTW) begin : gen_s0_add_ntw
      // POS_NB > 1
      if (POS_NB > 1) begin : gen_s0_add_pos_nb_gt_1
        localparam int GR_PSI_POS = GROUP_NODE / R;

        logic [PSI*R-1:0][STG_ITER_W-1:0] s0_add_bef_ntw_a;
        logic [PSI*R-1:0][STG_ITER_W-1:0] s0_add_a;

        assign s0_add_bef_ntw_a = s0_add_bef_ntw;
        assign s0_add           = s0_add_a;

        always_comb
          for (int g=0; g<GROUP_NB; g=g+1) begin
            var [GROUP_SIZE-1:0][STG_ITER_W-1:0]        add_a;
            var [GROUP_NODE-1:0][R-1:0][STG_ITER_W-1:0] gr_add;
            add_a = s0_add_bef_ntw_a[g*GROUP_SIZE+:GROUP_SIZE];

            for (int p=0; p<GROUP_NODE; p=p+1)
              for (int r=0; r<R; r=r+1)
                gr_add[p][r] = add_a[r*GR_PSI_POS*R+p];

            s0_add_a[g*GROUP_SIZE+:GROUP_SIZE] = gr_add;
          end
      end
      // POS_NB == 1
      else begin : gen_s0_add_pos_nb_eq_1
        assign s0_add = s0_add_bef_ntw;
      end
    end
    else begin : gen_no_s0_add_ntw
      assign s0_add = s0_add_bef_ntw;
    end
  endgenerate

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
  // s0 : Rotation R
  // ------------------------------------------------------------------------------------------- --
  logic [PSI-1:0][R-1:0][DT_W-1:0] s0_rot1_dt;

  generate
    if (POS_NB == 1) begin : gen_rot1_pos_nb_eq_1
      always_comb
        for (int p=0; p<PSI; p=p+1)
          for (int r=0; r<R; r=r+1) begin
            var [R_W-1:0] rot_fact;
            rot_fact = r - s0_rot_r_factor;
            s0_rot1_dt[p][r] = s0_dt[p][rot_fact];
          end
    end
    else begin : gen_rot1_pos_nb_gt_1
      // Do nothing
      assign s0_rot1_dt = s0_dt;
    end
  endgenerate

  // ------------------------------------------------------------------------------------------- --
  // s0-s1 pipe
  // ------------------------------------------------------------------------------------------- --
  logic [PSI-1:0][R-1:0][DT_W-1:0] s1_rot1_dt;
  control_t                        s1_ctrl;
  logic [PSI_W-1:0]                s1_rot_bu_factor;
  logic                            s1_avail;

  generate
    if (LAT_PIPE_MH[0]) begin : gen_s0_s1_reg
      always_ff @(posedge clk) begin
        if (!s_rst_n) s1_avail <= 1'b0;
        else          s1_avail <= s0_avail;
      end

      always_ff @(posedge clk) begin
        s1_rot1_dt     <= s0_rot1_dt;
        s1_ctrl          <= s0_ctrl;
        s1_rot_bu_factor <= s0_rot_bu_factor;
      end
    end else begin : gen_no_s0_s1_reg
      assign s1_avail         = s0_avail;
      assign s1_rot1_dt       = s0_rot1_dt;
      assign s1_ctrl          = s0_ctrl;
      assign s1_rot_bu_factor = s0_rot_bu_factor;
    end
  endgenerate

  // =========================================================================================== --
  // s1
  // =========================================================================================== --
  // ------------------------------------------------------------------------------------------- --
  // s1 : Dispatch BU
  // ------------------------------------------------------------------------------------------- --
  // The BU dispatch is done in 2 steps.
  // The first interleave the groups when POS_NB > 1
  // The second one, reorder the sets in reverse order.
  logic [PSI-1:0][R-1:0][DT_W-1:0] s1_dp2_dt;

  generate
    if (POS_NB > 1) begin : gen_dp2
      logic [GROUP_NB*GROUP_NODE-1:0][R-1:0][DT_W-1:0] s1_dp2_dt_a;
      logic [GROUP_NB*GROUP_NODE-1:0][R-1:0][DT_W-1:0] s1_rot1_dt_a;
      assign s1_dp2_dt    = s1_dp2_dt_a;
      assign s1_rot1_dt_a = s1_rot1_dt;
      always_comb
        for (int i=0; i<GROUP_NB*GROUP_NODE; i=i+1) begin
          int ofs;
          ofs = i/GROUP_NB + (i%GROUP_NB)*GROUP_NODE;
          s1_dp2_dt_a[i] = s1_rot1_dt[ofs];
        end
    end
    else begin : gen_no_dp2
      // Do nothing
      assign s1_dp2_dt = s1_rot1_dt;
    end
  endgenerate


  logic [PSI-1:0][R-1:0][DT_W-1:0]                   s1_dp3_dt;
  logic [SET_NB-1:0][SET_BU_NB-1:0][R-1:0][DT_W-1:0] s1_dp2_dt_a;
  logic [SET_NB-1:0][SET_BU_NB-1:0][R-1:0][DT_W-1:0] s1_dp3_dt_a;

  assign s1_dp2_dt_a = s1_dp2_dt;
  assign s1_dp3_dt   = s1_dp3_dt_a;

  generate
    if (SET_NB > 1) begin : gen_s1_dp3
      always_comb
        for (int i=0; i<SET_NB; i=i+1) begin
          var [SET_W-1:0] rev_i;

          for (int j=0; j<SET_W; j=j+1)
            rev_i[j] = i[SET_W-1-j];

          s1_dp3_dt_a[i] = s1_dp2_dt_a[rev_i];
        end
      end
    else begin
      assign s1_dp3_dt_a = s1_dp2_dt_a;
    end
  endgenerate

  // ------------------------------------------------------------------------------------------- --
  // s1 : Output to FIFO command
  // ------------------------------------------------------------------------------------------- --
  // Write a command at every stage end.
  assign drw_fifo_eob      = s1_ctrl.eob;
  assign drw_fifo_pbs_id   = s1_ctrl.pbs_id;
  assign drw_fifo_intl_idx = s1_ctrl.intl_idx;
  assign drw_fifo_avail    = s1_avail & s1_ctrl.last_stg_iter;

  // ------------------------------------------------------------------------------------------- --
  // s1-s2 pipe
  // ------------------------------------------------------------------------------------------- --
  logic [PSI-1:0][R-1:0][DT_W-1:0]       s2_dp3_dt;
  control_t                              s2_ctrl;
  logic [PSI_W-1:0]                      s2_rot_bu_factor;
  logic                                  s2_avail;

  generate
    if (LAT_PIPE_MH[1]) begin : gen_s1_s2_reg
      always_ff @(posedge clk) begin
        if (!s_rst_n) s2_avail <= 1'b0;
        else          s2_avail <= s1_avail;
      end

      always_ff @(posedge clk) begin
        s2_dp3_dt        <= s1_dp3_dt;
        s2_ctrl          <= s1_ctrl;
        s2_rot_bu_factor <= s1_rot_bu_factor;
      end
    end else begin : gen_no_s1_s2_reg
      assign s2_avail         = s1_avail;
      assign s2_dp3_dt        = s1_dp3_dt;
      assign s2_ctrl          = s1_ctrl;
      assign s2_rot_bu_factor = s1_rot_bu_factor;
    end
  endgenerate

  // =========================================================================================== --
  // s2
  // =========================================================================================== --
  // ------------------------------------------------------------------------------------------- --
  // s2 : Rotation BU
  // ------------------------------------------------------------------------------------------- --
  logic [PSI-1:0][R-1:0][DT_W-1:0] s2_rot2_dt;

  always_comb
    for (int p=0; p<PSI; p=p+1) begin
      var [PSI_W-1:0] rot_fact;
      rot_fact      = p - s2_rot_bu_factor;
      s2_rot2_dt[p] = s2_dp3_dt[rot_fact];
    end

  // ---------------------------------------------------------------------------------------------- --
  // s2 : PBS location in RAM
  // ---------------------------------------------------------------------------------------------- --
  logic [TOKEN_W:0]   s2_token_rp;
  logic [TOKEN_W:0]   s2_token_wp;
  logic [TOKEN_W:0]   s2_token_rpD;
  logic [TOKEN_W:0]   s2_token_wpD;
  logic [TOKEN_W-1:0] s2_token;
  logic               s2_token_full;
  logic               s2_token_empty;

  assign s2_token_rpD = (s2_avail && s2_ctrl.eos) ? s2_token_rp + 1 : s2_token_rp;
  assign s2_token_wpD = token_release ? s2_token_wp + 1: s2_token_wp;

  assign s2_token      = s2_token_rp;
  assign s2_token_full = (s2_token_wp[TOKEN_W-1:0] == s2_token_rp[TOKEN_W-1:0])
                        & (s2_token_wp[TOKEN_W] != s2_token_rp[TOKEN_W]);
  assign s2_token_empty = s2_token_rp == s2_token_wp;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      s2_token_rp <= '0;
      s2_token_wp <= TOKEN_NB; // It is a power of 2
    end
    else begin
      s2_token_rp <= s2_token_rpD;
      s2_token_wp <= s2_token_wpD;
    end

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // Do nothing
    end
    else begin
      if (s2_avail) begin
        assert(!s2_token_empty)
        else $fatal(1,"%t > ERROR: No more available token!", $time);
      end
      if (token_release) begin
        assert(!s2_token_full)
        else  $fatal(1,"%t > ERROR: Token stack overflow!", $time);
      end
    end
// pragma translate_on

  // ------------------------------------------------------------------------------------------- --
  // s2-s3 pipe
  // ------------------------------------------------------------------------------------------- --
  logic [PSI-1:0][R-1:0][DT_W-1:0]       s3_rot2_dt;
  control_t                              s3_ctrl;
  logic                                  s3_avail;
  logic [TOKEN_W-1:0]                    s3_token;

  generate
    if (LAT_PIPE_MH[2]) begin : gen_s2_s3_reg
      always_ff @(posedge clk) begin
        if (!s_rst_n) s3_avail <= 1'b0;
        else          s3_avail <= s2_avail;
      end

      always_ff @(posedge clk) begin
        s3_rot2_dt <= s2_rot2_dt;
        s3_ctrl    <= s2_ctrl;
        s3_token   <= s2_token;
      end
    end else begin : gen_no_s2_s3_reg
      assign s3_avail   = s2_avail;
      assign s3_rot2_dt = s2_rot2_dt;
      assign s3_ctrl    = s2_ctrl;
      assign s3_token   = s2_token;
    end
  endgenerate

  // =========================================================================================== --
  // s3
  // =========================================================================================== --
  // ------------------------------------------------------------------------------------------- --
  // Write in RAM
  // ------------------------------------------------------------------------------------------- --
  assign drw_ram_sob      = s3_ctrl.sob;
  assign drw_ram_eob      = s3_ctrl.eob;
  assign drw_ram_sol      = s3_ctrl.sol;
  assign drw_ram_eol      = s3_ctrl.eol;
  assign drw_ram_sos      = s3_ctrl.sos;
  assign drw_ram_eos      = s3_ctrl.eos;
  assign drw_ram_pbs_id   = s3_ctrl.pbs_id;
  assign drw_ram_token    = s3_token;
  assign drw_ram_intl_idx = s3_ctrl.intl_idx;
  assign drw_ram_avail    = s3_avail;

  always_comb
    for (int p=0; p<PSI; p=p+1)
      for (int r=0; r<R; r=r+1) begin
        data_t d;
        d = s3_rot2_dt[p][r];
        drw_ram_add[p][r]  = d.add;
        drw_ram_data[p][r] = d.data;
      end

endmodule
