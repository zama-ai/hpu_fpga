// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ==============================================================================================

`include "ntt_core_common_macro_inc.sv"

module ntt_core_wmm_dispatch_rotate_rd_pcg
  import param_tfhe_pkg::*;
  import pep_common_param_pkg::*;
  import ntt_core_wmm_dispatch_rotate_pcg_pkg::*;
  import ntt_core_wmm_dispatch_rotate_rd_pcg_pkg::*;
#(
  parameter int OP_W        = 32,
  parameter int R           = 8, // Butterfly Radix
  parameter int PSI         = 8, // Number of butterflies
  parameter int OUT_PSI_DIV = 2, // PSI/OUT_PSI_DIV : is the number of PSI for the following CLBU
  parameter int S           = $clog2(N)/$clog2(R), // Number of stages
  parameter bit IN_PIPE     = 1'b1, // Recommended
  parameter int S_INIT      = S-2,
  parameter int S_DEC       = 1,
  parameter int RS_DELTA    = S-1,
  parameter int LS_DELTA    = S-1,
  parameter int LPB_NB      = S,
  localparam int OUT_PSI    = PSI/OUT_PSI_DIV,
  `NTT_CORE_LOCALPARAM_HEADER(R,S,PSI)
) (
  input  logic                                clk,     // clock
  input  logic                                s_rst_n, // synchronous reset

  // input data from RAM
  input  logic [PSI-1:0][R-1:0][OP_W-1:0]     ram_drr_data,
  input  logic [PSI-1:0][R-1:0]               ram_drr_data_avail,
  input  logic                                ram_drr_sob,
  input  logic                                ram_drr_eob,
  input  logic                                ram_drr_sol,
  input  logic                                ram_drr_eol,
  input  logic                                ram_drr_sos,
  input  logic                                ram_drr_eos,
  input  logic [BPBS_ID_W-1:0]                 ram_drr_pbs_id,
  input  logic                                ram_drr_ctrl_avail,

  // output data to sequencer
  output logic [OUT_PSI-1:0][R-1:0][OP_W-1:0] drr_seq_data,
  output logic [OUT_PSI-1:0][R-1:0]           drr_seq_data_avail,
  output logic [OUT_PSI-1:0][R-1:0]           drr_acc_data_avail,
  output logic                                drr_seq_sob,
  output logic                                drr_seq_eob,
  output logic                                drr_seq_sol,
  output logic                                drr_seq_eol,
  output logic                                drr_seq_sos,  // when output for the acc, equivalent to sog
  output logic                                drr_seq_eos,  // when output for the acc, equivalent to eog
  output logic [BPBS_ID_W-1:0]                 drr_seq_pbs_id,
  output logic                                drr_seq_ctrl_avail,
  output logic                                drr_acc_ctrl_avail
);

  // =========================================================================================== --
  // localparam
  // =========================================================================================== --
  localparam int RS_DELTA_IDX = RS_DELTA - 1;
  localparam int LS_DELTA_IDX = LS_DELTA - 1;
  localparam [PARAM_NB-1:0][31:0]    RS_PARAM_LIST = get_pcg_param(R, PSI, S, STG_ITER_NB, RS_DELTA_IDX);
  localparam [LS_PARAM_NB-1:0][31:0] LS_PARAM_LIST = get_pcg_ls_param(R, PSI, S, STG_ITER_NB, LS_DELTA_IDX);

  localparam int RS = 0;
  localparam int LS = 1;

  localparam [1:0][31:0] ITER_CONS_NB = {LS_PARAM_LIST[LS_PARAM_OFS_ITER_CONS_NB],
                                         32'd1}; // UNUSED
  localparam [1:0][31:0] CONS_NB = {LS_PARAM_LIST[LS_PARAM_OFS_CONS_NB],
                                    RS_PARAM_LIST[PARAM_OFS_CONS_NB]};
  localparam [1:0][31:0] SET_NB  = {LS_PARAM_LIST[LS_PARAM_OFS_SET_NB],
                                    RS_PARAM_LIST[PARAM_OFS_SET_NB]};
  localparam [1:0][31:0] POS_NB  = {32'd0, // UNUSED
                                    RS_PARAM_LIST[PARAM_OFS_POS_NB]};
  localparam [1:0][31:0] STG_ITER_THRESHOLD = {32'd1, // UNUSED
                                               RS_PARAM_LIST[PARAM_OFS_STG_ITER_THRESHOLD]};
  localparam [1:0][31:0] CONS_W = {$clog2(CONS_NB[1]),
                                   $clog2(CONS_NB[0])};
  localparam [1:0][31:0] SET_W  = {$clog2(SET_NB[1]),
                                   $clog2(SET_NB[0])};
  localparam [1:0][31:0] ITER_CONS_W  = {$clog2(ITER_CONS_NB[1]),
                                         $clog2(ITER_CONS_NB[0])};
  localparam [1:0][31:0] STG_ITER_THRESHOLD_W = {$clog2(STG_ITER_THRESHOLD[1]),
                                                 $clog2(STG_ITER_THRESHOLD[0])};
  localparam [1:0][PSI_W-1:0] ROT_FACTOR_MASK  = {(1 << PSI_SZ-SET_W[1])-1,(1 << PSI_SZ-SET_W[0])-1};

  localparam int S_INIT_L      = S_INIT % S;
  localparam int S_DEC_L       = S_DEC % S;
  localparam bit DO_LOOPBACK   = (S_DEC > 0);
  localparam bit NTT_BWD_INIT  = (S_INIT >= S);

  localparam int STG_ITER_NB_L = STG_ITER_NB * OUT_PSI_DIV;
  localparam int STG_ITER_W_L  = (STG_ITER_NB_L == 1) ? 1 : $clog2(STG_ITER_NB_L);
  localparam int OUT_SELECT_W  = OUT_PSI_DIV == 1 ? 1 : $clog2(OUT_PSI_DIV);

  // For counter size that counts from 0 to LPB_NB-1
  localparam int LPB_W = $clog2(LPB_NB) == 0 ? 1 : $clog2(LPB_NB);

  // =========================================================================================== --
  // type
  // =========================================================================================== --
  typedef struct packed {
    logic                sob;
    logic                eob;
    logic                sol;
    logic                eol;
    logic                sos;
    logic                eos;
    logic                ntt_bwd;
    logic [BPBS_ID_W-1:0] pbs_id;
  } control_t;

  localparam CTRL_W = $bits(control_t);

  // =========================================================================================== --
  // Input pipe
  // =========================================================================================== --
  logic [PSI-1:0][R-1:0][OP_W-1:0] s0_data;
  logic [PSI-1:0][R-1:0]           s0_data_avail;
  logic                            s0_sob;
  logic                            s0_eob;
  logic                            s0_sol;
  logic                            s0_eol;
  logic                            s0_sos;
  logic                            s0_eos;
  logic [BPBS_ID_W-1:0]             s0_pbs_id;
  logic                            s0_ctrl_avail;

  generate
    if (IN_PIPE) begin : in_reg
      always_ff @(posedge clk) begin
        if (!s_rst_n) begin
          s0_ctrl_avail <= 1'b0;
          s0_data_avail <= '0;
        end
        else begin
          s0_ctrl_avail <= ram_drr_ctrl_avail;
          s0_data_avail <= ram_drr_data_avail;
        end
      end

      // NOTE : if the synthesis enables it, we can use ram_drr_ctrl_avail and ram_drr_data_avail
      // as enable to save some power.
      always_ff @(posedge clk) begin
        s0_data    <= ram_drr_data;
        s0_sob     <= ram_drr_sob;
        s0_eob     <= ram_drr_eob;
        s0_sol     <= ram_drr_sol;
        s0_eol     <= ram_drr_eol;
        s0_sos     <= ram_drr_sos;
        s0_eos     <= ram_drr_eos;
        s0_pbs_id  <= ram_drr_pbs_id;
      end
    end else begin : no_in_reg
      assign s0_data       = ram_drr_data;
      assign s0_sob        = ram_drr_sob;
      assign s0_eob        = ram_drr_eob;
      assign s0_sol        = ram_drr_sol;
      assign s0_eol        = ram_drr_eol;
      assign s0_sos        = ram_drr_sos;
      assign s0_eos        = ram_drr_eos;
      assign s0_pbs_id     = ram_drr_pbs_id;
      assign s0_ctrl_avail = ram_drr_ctrl_avail;
      assign s0_data_avail = ram_drr_data_avail;
    end
  endgenerate

  // =========================================================================================== --
  // Counters
  // =========================================================================================== --
  // Keep track of :
  //   stg_iter : current stage iteration
  logic [STG_ITER_W_L-1:0] s0_stg_iter;
  logic [STG_W-1:0]        s0_stg;
  logic                    s0_ntt_bwd;
  logic [LPB_W-1:0]        s0_lpb;
  logic [STG_ITER_W_L-1:0] s0_stg_iterD;
  logic [STG_W-1:0]        s0_stgD;
  logic                    s0_ntt_bwdD;
  logic [LPB_W-1:0]        s0_lpbD;
  logic                    s0_first_stg;
  logic                    s0_wrap_stg;
  //logic [STG_W-1:0]        s0_start_stg;
  logic                    s0_last_lpb;
  logic [    STG_W-1:0]    s0_stg_dec;


  logic [STG_ITER_W-1:0]   s0_stg_iter_rd;
  logic [OUT_SELECT_W-1:0] s0_out_sel_rd;

  assign s0_first_stg   = (s0_stg == S - 1);
  assign s0_wrap_stg    = ~DO_LOOPBACK | (s0_stg < S_DEC);
  //assign s0_start_stg   = S_INIT_L;
  assign s0_stg_iter_rd = s0_stg_iter[$clog2(OUT_PSI_DIV)+:STG_ITER_W];
  assign s0_out_sel_rd  = (OUT_PSI_DIV == 1) ? 0 : s0_stg_iter[0+:OUT_SELECT_W];
  assign s0_last_lpb    = s0_lpb == (LPB_NB-1);
  assign s0_stg_dec     = s0_stg < S_DEC_L ? S-1 : s0_stg - S_DEC_L; // if S_DEC_L > s0_stg => last stage reached

  assign s0_lpbD      = (s0_ctrl_avail && s0_eob) ? s0_last_lpb ? '0 : s0_lpb + 1 : s0_lpb;
  assign s0_stgD      = (DO_LOOPBACK && s0_ctrl_avail && s0_eob) ? s0_last_lpb ? S_INIT_L : s0_stg_dec : s0_stg;
  assign s0_stg_iterD = (s0_ctrl_avail && s0_eol) ? s0_eos ? 0 : s0_stg_iter + 1 : s0_stg_iter;
  assign s0_ntt_bwdD  = (DO_LOOPBACK && s0_ctrl_avail && s0_eob && s0_wrap_stg) ?
                                  ~s0_ntt_bwd : s0_ntt_bwd;

  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      s0_stg_iter <= '0;
      s0_stg      <= S_INIT_L;
      s0_ntt_bwd  <= NTT_BWD_INIT;
      s0_lpb      <= '0;
    end else begin
      s0_stg_iter <= s0_stg_iterD;
      s0_stg      <= s0_stgD;
      s0_ntt_bwd  <= s0_ntt_bwdD;
      s0_lpb      <= s0_lpbD;
    end
  end

  control_t s0_ctrl;

  assign s0_ctrl.sob     = s0_sob;
  assign s0_ctrl.eob     = s0_eob;
  assign s0_ctrl.sol     = s0_sol;
  assign s0_ctrl.eol     = s0_eol;
  assign s0_ctrl.sos     = s0_sos;
  assign s0_ctrl.eos     = s0_eos;
  assign s0_ctrl.ntt_bwd = s0_ntt_bwd;
  assign s0_ctrl.pbs_id  = s0_pbs_id;

  logic [R_W-1:0] s0_rot_r_factor; // used only when POS_NB == 1 for RS
  logic           s0_pos_nb_eq_1;

  assign s0_pos_nb_eq_1  = (POS_NB[RS] == 1);
  assign s0_rot_r_factor = (s0_pos_nb_eq_1 && !s0_first_stg) ? s0_stg_iter_rd >> (STG_ITER_W-R_W) : '0;

  // =========================================================================================== --
  // S0
  // =========================================================================================== --
  // ------------------------------------------------------------------------------------------- --
  // s0 : Availability
  // ------------------------------------------------------------------------------------------- --
  logic s0_seq_ctrl_avail;
  logic s0_acc_ctrl_avail;
  logic [OUT_PSI-1:0][R-1:0] s0_seq_data_avail;
  logic [OUT_PSI-1:0][R-1:0] s0_acc_data_avail;
  logic s0_send_to_acc;

  assign s0_send_to_acc = s0_first_stg & ~s0_ntt_bwd;

  assign s0_seq_ctrl_avail   = s0_ctrl_avail & ~s0_send_to_acc;
  assign s0_acc_ctrl_avail   = s0_ctrl_avail & s0_send_to_acc;
  assign s0_seq_data_avail   = s0_data_avail[OUT_PSI-1:0] & {OUT_PSI*R{~s0_send_to_acc}};
  assign s0_acc_data_avail   = s0_data_avail[OUT_PSI-1:0] & {OUT_PSI*R{s0_send_to_acc}};

  // ------------------------------------------------------------------------------------------- --
  // s0 : Rot BU
  // ------------------------------------------------------------------------------------------- --
  logic [PSI-1:0][R-1:0][OP_W-1:0] s0_rot1_data;
  logic [1:0][PSI_W-1:0]           s0_rot_bu_factor_a; // [0] RS, [1] LS
  logic [PSI_W-1:0]                s0_rot_bu_factor_rs;
  logic [PSI_W-1:0]                s0_rot_bu_factor_ls;
  logic [PSI_W-1:0]                s0_rot_bu_factor_ls_tmp;
  logic [PSI_W-SET_W[LS]-1:0]      s0_rot_bu_factor_ls_tmp2;
  logic [PSI_W-1:0]                s0_rot_bu_factor;

  assign s0_rot_bu_factor = PSI == 1 ? '0 :
                            s0_first_stg ? s0_rot_bu_factor_ls : s0_rot_bu_factor_rs;

  assign s0_rot_bu_factor_ls_tmp  = (s0_stg_iter_rd >> ITER_CONS_W[LS]) << CONS_W[LS];
  assign s0_rot_bu_factor_ls_tmp2 = s0_rot_bu_factor_ls_tmp;
  assign s0_rot_bu_factor_ls      = s0_rot_bu_factor_ls_tmp2;

  generate
    if (POS_NB[RS] > 1) begin : gen_s0_pos_nb_gt_1
      logic [PSI_W-1:0] s0_rot_idx;
      logic [PSI_W-1:0] s0_rot_idx_rev;
      logic [PSI_W-SET_W[RS]-1:0] s0_rot_bu_factor_tmp;

      assign s0_rot_idx = s0_stg_iter_rd >> STG_ITER_THRESHOLD_W[RS];

      // pseudo_reverse_order(rot_idx, R, int(log(PSI//(cons_nb*set_nb),2))//R_W, 0)
      always_comb begin
        s0_rot_idx_rev = '0;
        for (int i=0; i<PSI_SZ-CONS_W[RS]-SET_W[RS];i=i+1)
          s0_rot_idx_rev[i] = s0_rot_idx[PSI_W-CONS_W[RS]-SET_W[RS]-1-i];
      end

      assign s0_rot_bu_factor_tmp  = (s0_rot_idx_rev * CONS_NB[RS]); // truncate for % (PSI//set_nb)
      assign s0_rot_bu_factor_rs = s0_rot_bu_factor_tmp;
    end
    else begin : gen_s0_pos_nb_eq_1
      localparam int SET_WIDTH = SET_W[RS];
      logic [PSI_W-SET_WIDTH-1:0] s0_rot_idx;
      logic [PSI_W-1:0] s0_rot_idx_rev;

      assign s0_rot_idx = s0_stg_iter_rd >> STG_ITER_THRESHOLD_W[RS]; // truncate for % (PSI//set_nb)
      //pseudo_reverse_order(rot_idx, R, int(log(PSI//set_nb,2))//R_W, 0)
      always_comb begin
        s0_rot_idx_rev = '0;
        for (int i=0; i<PSI_SZ-SET_W[RS]; i=i+1)
          s0_rot_idx_rev[i] = s0_rot_idx[PSI_W-SET_W[RS]-1-i];
      end

      assign s0_rot_bu_factor_rs = s0_rot_idx_rev;
    end
  endgenerate

  always_comb
    for (int p=0; p<PSI; p=p+1) begin
      var [PSI_W-1:0]      rot_fact;
      rot_fact        = p + s0_rot_bu_factor;
      s0_rot1_data[p] = s0_data[rot_fact];
    end

  // ------------------------------------------------------------------------------------------- --
  // S0-S1 pipe
  // ------------------------------------------------------------------------------------------- --
  logic [PSI-1:0][R-1:0][OP_W-1:0] s1_rot1_data;
  control_t                        s1_ctrl;
  logic [R_W-1:0]                  s1_rot_r_factor;
  logic                            s1_pos_nb_eq_1;
  logic                            s1_seq_ctrl_avail;
  logic                            s1_acc_ctrl_avail;
  logic [OUT_PSI-1:0][R-1:0]       s1_seq_data_avail;
  logic [OUT_PSI-1:0][R-1:0]       s1_acc_data_avail;
  logic [OUT_SELECT_W-1:0]         s1_out_sel_rd;

  generate
    if (LAT_PIPE_MH[0]) begin : gen_s0_s1_reg
      always_ff @(posedge clk) begin
        if (!s_rst_n) begin
          s1_seq_ctrl_avail <= 1'b0;
          s1_acc_ctrl_avail <= 1'b0;
          s1_seq_data_avail <= '0;
          s1_acc_data_avail <= '0;
        end
        else begin
          s1_seq_ctrl_avail <= s0_seq_ctrl_avail;
          s1_acc_ctrl_avail <= s0_acc_ctrl_avail;
          s1_seq_data_avail <= s0_seq_data_avail;
          s1_acc_data_avail <= s0_acc_data_avail;
        end
      end

      always_ff @(posedge clk) begin
        s1_rot1_data     <= s0_rot1_data;
        s1_ctrl          <= s0_ctrl;
        s1_rot_r_factor  <= s0_rot_r_factor;
        s1_pos_nb_eq_1   <= s0_pos_nb_eq_1;
        s1_out_sel_rd    <= s0_out_sel_rd;
      end
    end else begin : gen_no_s0_s1_reg
      assign s1_seq_ctrl_avail = s0_seq_ctrl_avail;
      assign s1_acc_ctrl_avail = s0_acc_ctrl_avail;
      assign s1_seq_data_avail = s0_seq_data_avail;
      assign s1_acc_data_avail = s0_acc_data_avail;
      assign s1_rot1_data      = s0_rot1_data;
      assign s1_ctrl           = s0_ctrl;
      assign s1_rot_r_factor   = s0_rot_r_factor;
      assign s1_pos_nb_eq_1    = s0_pos_nb_eq_1;
      assign s1_out_sel_rd     = s0_out_sel_rd;
    end
  endgenerate

  // =========================================================================================== --
  // S1
  // =========================================================================================== --
  // ------------------------------------------------------------------------------------------- --
  // s1 : Rot R
  // ------------------------------------------------------------------------------------------- --
  logic [PSI-1:0][R-1:0][OP_W-1:0] s1_rot2_data;

  always_comb
    for (int p=0; p<PSI; p=p+1)
      for (int r=0; r<R; r=r+1) begin
        var [R_W-1:0] rot_fact;
        rot_fact = r + s1_rot_r_factor;
        s1_rot2_data[p][r] = s1_rot1_data[p][rot_fact];
      end

  // ---------------------------------------------------------------------------------------------- --
  // s1 : Data Mux
  // ---------------------------------------------------------------------------------------------- --
  logic [OUT_PSI_DIV-1:0][OUT_PSI-1:0][R-1:0][OP_W-1:0] s1_mux_data;
  logic [OUT_PSI-1:0][R-1:0][OP_W-1:0]                  s1_mux_data_rd;
  assign s1_mux_data    = s1_rot2_data;
  assign s1_mux_data_rd = s1_mux_data[s1_out_sel_rd];

  // ------------------------------------------------------------------------------------------- --
  // S1-S2 pipe
  // ------------------------------------------------------------------------------------------- --
  logic [PSI-1:0][R-1:0][OP_W-1:0] s2_mux_data_rd;
  control_t                        s2_ctrl;
  logic                            s2_seq_ctrl_avail;
  logic                            s2_acc_ctrl_avail;
  logic [OUT_PSI-1:0][R-1:0]       s2_seq_data_avail;
  logic [OUT_PSI-1:0][R-1:0]       s2_acc_data_avail;

  generate
    if (LAT_PIPE_MH[1]) begin : gen_s1_s2_reg
      always_ff @(posedge clk) begin
        if (!s_rst_n) begin
          s2_seq_ctrl_avail <= 1'b0;
          s2_acc_ctrl_avail <= 1'b0;
          s2_seq_data_avail <= '0;
          s2_acc_data_avail <= '0;
        end
        else begin
          s2_seq_ctrl_avail <= s1_seq_ctrl_avail;
          s2_acc_ctrl_avail <= s1_acc_ctrl_avail;
          s2_seq_data_avail <= s1_seq_data_avail;
          s2_acc_data_avail <= s1_acc_data_avail;
        end
      end

      always_ff @(posedge clk) begin
        s2_mux_data_rd   <= s1_mux_data_rd;
        s2_ctrl          <= s1_ctrl;
      end
    end else begin : gen_no_s1_s2_reg
      assign s2_seq_ctrl_avail = s1_seq_ctrl_avail;
      assign s2_acc_ctrl_avail = s1_acc_ctrl_avail;
      assign s2_seq_data_avail = s1_seq_data_avail;
      assign s2_acc_data_avail = s1_acc_data_avail;
      assign s2_mux_data_rd    = s1_mux_data_rd;
      assign s2_ctrl           = s1_ctrl;
    end
  endgenerate

  // =========================================================================================== --
  // S2
  // =========================================================================================== --
  // Output
  assign drr_seq_sob        = s2_ctrl.sob;
  assign drr_seq_eob        = s2_ctrl.eob;
  assign drr_seq_sol        = s2_ctrl.sol;
  assign drr_seq_eol        = s2_ctrl.eol;
  assign drr_seq_sos        = s2_ctrl.sos;
  assign drr_seq_eos        = s2_ctrl.eos;
  assign drr_seq_pbs_id     = s2_ctrl.pbs_id;
  assign drr_seq_data       = s2_mux_data_rd;
  assign drr_seq_ctrl_avail = s2_seq_ctrl_avail;
  assign drr_acc_ctrl_avail = s2_acc_ctrl_avail;
  assign drr_seq_data_avail = s2_seq_data_avail;
  assign drr_acc_data_avail = s2_acc_data_avail;

endmodule
