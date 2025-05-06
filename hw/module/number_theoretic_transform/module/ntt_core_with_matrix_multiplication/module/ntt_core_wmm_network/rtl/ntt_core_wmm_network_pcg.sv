// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the NTT network PCG that handles the data for the writing and reading
// from RAM.
//
// According to the values of S_INIT and S_DEC, the logic linked to the regular or the last
// stage won't be present.
// ==============================================================================================

`include "ntt_core_common_macro_inc.sv"

module ntt_core_wmm_network_pcg
  import param_tfhe_pkg::*;
  import pep_common_param_pkg::*;
  import ntt_core_wmm_pkg::*;
  import ntt_core_wmm_ram_rd_pcg_pkg::*;
  import ntt_core_wmm_dispatch_rotate_wr_pcg_pkg::*;
  import ntt_core_wmm_network_pcg_pkg::*;
#(
  parameter  int OP_W                 = 32,
  parameter  int R                    = 8,
  parameter  int PSI                  = 8,
  parameter  int S                    = $clog2(N)/$clog2(R),
  parameter  int RAM_LATENCY          = 1, // Should be >= 1
  parameter  bit IN_PIPE              = 1'b1, // Recommended - for dispatch-rotate wr
  parameter  int S_INIT               = S-1,
  parameter  int S_DEC                = 1,
  parameter  bit SEND_TO_SEQ          = 1,
  parameter  int TOKEN_W              = BATCH_TOKEN_W,
  parameter  int OUT_PSI_DIV          = 1, // When the following NTT has not the
                                          // same size as the previous part.
  parameter  int RS_DELTA             = S-2,
  parameter  int LS_DELTA             = S-2,
  parameter  int LPB_NB               = 1,
  parameter  bit RS_OUT_WITH_NTW      = 1'b1,
  parameter  bit LS_OUT_WITH_NTW      = 1'b1,
  parameter  bit USE_RS               = 1'b1,
  parameter  bit USE_LS               = 1'b1,

  localparam int OUT_PSI              = PSI / OUT_PSI_DIV
) (
  input logic                                 clk,     // clock
  input logic                                 s_rst_n, // synchronous reset

  // input logic read enable from sequencer
  input logic                                 seq_ntw_rden,

  // input logic data from post-process
  input logic [PSI-1:0][R-1:0][OP_W-1:0]      pp_rsntw_data,
  input logic                                 pp_rsntw_sob,
  input logic                                 pp_rsntw_eob,
  input logic                                 pp_rsntw_sol,
  input logic                                 pp_rsntw_eol,
  input logic                                 pp_rsntw_sos,
  input logic                                 pp_rsntw_eos,
  input logic [BPBS_ID_W-1:0]                 pp_rsntw_pbs_id,
  input logic                                 pp_rsntw_avail,

  // input logic data from post-process for last stage
  input logic [PSI-1:0][R-1:0][OP_W-1:0]      pp_lsntw_data,
  input logic                                 pp_lsntw_sob,
  input logic                                 pp_lsntw_eob,
  input logic                                 pp_lsntw_sol,
  input logic                                 pp_lsntw_eol,
  input logic                                 pp_lsntw_sos,
  input logic                                 pp_lsntw_eos,
  input logic [BPBS_ID_W-1:0]                 pp_lsntw_pbs_id,
  input logic                                 pp_lsntw_avail,

  // output logic data to sequencer
  output logic [OUT_PSI-1:0][R-1:0][OP_W-1:0] ntw_seq_data,
  output logic [OUT_PSI-1:0][R-1:0]           ntw_seq_data_avail,
  output logic                                ntw_seq_sob,
  output logic                                ntw_seq_eob,
  output logic                                ntw_seq_sol,
  output logic                                ntw_seq_eol,
  output logic                                ntw_seq_sos,
  output logic                                ntw_seq_eos,
  output logic [BPBS_ID_W-1:0]                ntw_seq_pbs_id,
  output logic                                ntw_seq_ctrl_avail,

  // output logic data to the accumulator
  output logic [OUT_PSI-1:0][R-1:0][OP_W-1:0] ntw_acc_data,
  output logic [OUT_PSI-1:0][R-1:0]           ntw_acc_data_avail,
  output logic                                ntw_acc_sob,
  output logic                                ntw_acc_eob,
  output logic                                ntw_acc_sol,
  output logic                                ntw_acc_eol,
  output logic                                ntw_acc_sog,
  output logic                                ntw_acc_eog,
  output logic [BPBS_ID_W-1:0]                ntw_acc_pbs_id,
  output logic                                ntw_acc_ctrl_avail

);
  // ============================================================================================== --
  // Type
  // ============================================================================================== --
  typedef struct packed {
    logic                  eob;
    logic [BPBS_ID_W-1:0]   pbs_id;
    logic [INTL_L_W-1:0]   intl_idx;
  } cmd_t;

  // ============================================================================================== --
  // localparam
  // ============================================================================================== --
  `NTT_CORE_LOCALPARAM(R,S,PSI)

  localparam bit LS_ONLY      = (USE_RS == 0) & (USE_LS == 1);
  localparam int S_INIT_NEXT  = (S_INIT == 0) ? 2*S-1 : S_INIT-1;

  // If the network processes only the last stage, the number of interleaved level is GLWE_K_P1,
  // instead of INTL_L. Therefore some RAM reduction can be done.
  // Note that NTW_INTL_L_W <= INTL_L. intl_idx given by modules will be cropped for the address.
  localparam int NTW_INTL_L_W = LS_ONLY ? GLWE_K_P1_W : INTL_L_W;
  // To describe the RAM address
  typedef struct packed {
    logic [NTW_INTL_L_W-1:0] intl_idx;
    logic [TOKEN_W-1:0]      token;
    logic [STG_ITER_W-1:0]   stg_iter;
  } ram_add_t;

  localparam int RAM_ADD_W    = $bits(ram_add_t);
  localparam int RAM_DEPTH    = 2 ** RAM_ADD_W;

  // CMD_FIFO_LAT_PIPE_MH | [0] should be 1 by construction
  localparam int                    CMD_FIFO_LAT_MAX     = 2;
  localparam [CMD_FIFO_LAT_MAX-1:0] CMD_FIFO_LAT_PIPE_MH = 2'b11;

  // Check that we never read in RAM before writing in it.
  generate
    if (($countones(CMD_FIFO_LAT_PIPE_MH) + ntt_core_wmm_ram_rd_pcg_pkg::get_ram_cmd_latency() + ntt_core_wmm_dispatch_rotate_wr_pcg_pkg::get_cmd_latency())
          < (ntt_core_wmm_dispatch_rotate_wr_pcg_pkg::get_latency() + DRW_OUT_PIPE)) begin : __UNSUPPORTED_LATENCY__
        $fatal(1, "> ERROR: Read in RAM before writing in it! Change the latency pipe parameters.");
    end
  endgenerate

  // ============================================================================================== --
  // Internal signals
  // ============================================================================================== --
  // Dispatch rotate write regular stage - RAM write
  logic [PSI-1:0][R-1:0][OP_W-1:0] rsdrw_ram_data;
  logic                                            rsdrw_ram_sob;
  logic                                            rsdrw_ram_eob;
  logic                                            rsdrw_ram_sol;
  logic                                            rsdrw_ram_eol;
  logic                                            rsdrw_ram_sos;
  logic                                            rsdrw_ram_eos;
  logic [TOKEN_W-1:0]                              rsdrw_ram_token;
  logic [BPBS_ID_W-1:0]                            rsdrw_ram_pbs_id;
  logic [PSI-1:0][R-1:0][STG_ITER_W-1:0]           rsdrw_ram_add;
  logic [INTL_L_W-1:0]                             rsdrw_ram_intl_idx;
  logic                                            rsdrw_ram_avail;

  // Dispatch rotate write last stage - RAM write
  logic [PSI-1:0][R-1:0][OP_W-1:0] lsdrw_ram_data;
  logic                                            lsdrw_ram_sob;
  logic                                            lsdrw_ram_eob;
  logic                                            lsdrw_ram_sol;
  logic                                            lsdrw_ram_eol;
  logic                                            lsdrw_ram_sos;
  logic                                            lsdrw_ram_eos;
  logic [TOKEN_W-1:0]                              lsdrw_ram_token;
  logic [BPBS_ID_W-1:0]                            lsdrw_ram_pbs_id;
  logic [PSI-1:0][R-1:0][STG_ITER_W-1:0]           lsdrw_ram_add;
  logic [INTL_L_W-1:0]                             lsdrw_ram_intl_idx;
  logic                                            lsdrw_ram_avail;

  // RAM - RAM read
  logic                                            ramrd_rsram_ren;
  logic                                            ramrd_lsram_ren;
  logic [STG_ITER_W-1:0]                           ramrd_ram_add;
  logic [INTL_L_W-1:0]                             ramrd_ram_intl_idx;
  logic [TOKEN_W-1:0]                              ramrd_ram_token;
  logic [PSI-1:0][R-1:0][OP_W-1:0]                 ramrd_rsram_datar;
  logic [PSI-1:0][R-1:0][OP_W-1:0]                 ramrd_lsram_datar;

  // RAM read - dispatch rotate read
  logic [PSI-1:0][R-1:0][OP_W-1:0]                 ramrd_drr_data;
  logic [PSI-1:0][R-1:0]                           ramrd_drr_data_avail;
  logic                                            ramrd_drr_sob;
  logic                                            ramrd_drr_eob;
  logic                                            ramrd_drr_sol;
  logic                                            ramrd_drr_eol;
  logic                                            ramrd_drr_sos;
  logic                                            ramrd_drr_eos;
  logic [BPBS_ID_W-1:0]                            ramrd_drr_pbs_id;
  logic                                            ramrd_drr_ctrl_avail;

  // Command FIFOs
  logic                                            rsdrw_fifo_eob;
  logic [BPBS_ID_W-1:0]                            rsdrw_fifo_pbs_id;
  logic [INTL_L_W-1:0]                             rsdrw_fifo_intl_idx;
  logic                                            rsdrw_fifo_vld;
  logic                                            rsdrw_fifo_rdy;
  cmd_t                                            rsdrw_fifo_cmd;

  logic                                            lsdrw_fifo_eob;
  logic [BPBS_ID_W-1:0]                            lsdrw_fifo_pbs_id;
  logic [INTL_L_W-1:0]                             lsdrw_fifo_intl_idx;
  logic                                            lsdrw_fifo_vld;
  logic                                            lsdrw_fifo_rdy;
  cmd_t                                            lsdrw_fifo_cmd;

  logic                                            rsfifo_ramrd_eob;
  logic [BPBS_ID_W-1:0]                            rsfifo_ramrd_pbs_id;
  logic [INTL_L_W-1:0]                             rsfifo_ramrd_intl_idx;
  logic                                            rsfifo_ramrd_vld;
  logic                                            rsfifo_ramrd_rdy;
  cmd_t                                            rsfifo_ramrd_cmd;

  logic                                            lsfifo_ramrd_eob;
  logic [BPBS_ID_W-1:0]                            lsfifo_ramrd_pbs_id;
  logic [INTL_L_W-1:0]                             lsfifo_ramrd_intl_idx;
  logic                                            lsfifo_ramrd_vld;
  logic                                            lsfifo_ramrd_rdy;
  cmd_t                                            lsfifo_ramrd_cmd;

  logic                                            rstoken_release;
  logic                                            lstoken_release;

  // ============================================================================================== --
  // Instances
  // ============================================================================================== --
  // ---------------------------------------------------------------------------------------------- --
  // Regular stages
  // ---------------------------------------------------------------------------------------------- --
  generate
    if (USE_RS) begin: wr_rs_gen
      ntt_core_wmm_dispatch_rotate_wr_pcg #(
        .OP_W       (OP_W),
        .R          (R),
        .PSI        (PSI),
        .S          (S),
        .IN_PIPE    (IN_PIPE),
        .S_INIT     (S_INIT),
        .S_DEC      (S_DEC),
        .DELTA      (RS_DELTA),
        .TOKEN_W    (TOKEN_W),
        .CLBU_OUT_WITH_NTW(RS_OUT_WITH_NTW)
      ) ntt_core_wmm_dispatch_rotate_wr_pcg (
        .clk              (clk),
        .s_rst_n          (s_rst_n),

        .pp_drw_data      (pp_rsntw_data),
        .pp_drw_sob       (pp_rsntw_sob),
        .pp_drw_eob       (pp_rsntw_eob),
        .pp_drw_sol       (pp_rsntw_sol),
        .pp_drw_eol       (pp_rsntw_eol),
        .pp_drw_sos       (pp_rsntw_sos),
        .pp_drw_eos       (pp_rsntw_eos),
        .pp_drw_pbs_id    (pp_rsntw_pbs_id),
        .pp_drw_avail     (pp_rsntw_avail),

        .drw_ram_data     (rsdrw_ram_data),
        .drw_ram_sob      (rsdrw_ram_sob),
        .drw_ram_eob      (rsdrw_ram_eob),
        .drw_ram_sol      (rsdrw_ram_sol),
        .drw_ram_eol      (rsdrw_ram_eol),
        .drw_ram_sos      (rsdrw_ram_sos),
        .drw_ram_eos      (rsdrw_ram_eos),
        .drw_ram_token    (rsdrw_ram_token),
        .drw_ram_pbs_id   (rsdrw_ram_pbs_id),
        .drw_ram_add      (rsdrw_ram_add),
        .drw_ram_intl_idx (rsdrw_ram_intl_idx),
        .drw_ram_avail    (rsdrw_ram_avail),

        .token_release    (rstoken_release),

        .drw_fifo_eob     (rsdrw_fifo_eob),
        .drw_fifo_pbs_id  (rsdrw_fifo_pbs_id),
        .drw_fifo_intl_idx(rsdrw_fifo_intl_idx),
        .drw_fifo_avail   (rsdrw_fifo_vld)
      );
    end
    else begin: no_wr_rs_gen
      assign rsdrw_ram_data     = 'x;
      assign rsdrw_ram_sob      = 'x;
      assign rsdrw_ram_eob      = 'x;
      assign rsdrw_ram_sol      = 'x;
      assign rsdrw_ram_eol      = 'x;
      assign rsdrw_ram_sos      = 'x;
      assign rsdrw_ram_eos      = 'x;
      assign rsdrw_ram_token    = 'x;
      assign rsdrw_ram_pbs_id   = 'x;
      assign rsdrw_ram_add      = 'x;
      assign rsdrw_ram_intl_idx = 'x;
      assign rsdrw_ram_avail    = 1'b0;

      assign rsdrw_fifo_vld      = 1'b0;
      assign rsdrw_fifo_eob      = 'x;
      assign rsdrw_fifo_pbs_id   = 'x;
      assign rsdrw_fifo_intl_idx = 'x;
    end
  endgenerate

  // ---------------------------------------------------------------------------------------------- --
  // Last stage
  // ---------------------------------------------------------------------------------------------- --
  generate
    if (USE_LS) begin: wr_ls_gen
      ntt_core_wmm_dispatch_rotate_last_stage_wr_pcg #(
        .OP_W       (OP_W),
        .R          (R),
        .PSI        (PSI),
        .S          (S),
        .IN_PIPE    (IN_PIPE),
        .S_INIT     (0),
        .S_DEC      (S_DEC == 0 ? 0 : S),
        .DELTA      (LS_DELTA),
        .TOKEN_W    (TOKEN_W),
        .CLBU_OUT_WITH_NTW(LS_OUT_WITH_NTW)
      ) ntt_core_wmm_dispatch_rotate_last_stage_wr_pcg (
        .clk              (clk),
        .s_rst_n          (s_rst_n),

        .pp_drw_data      (pp_lsntw_data),
        .pp_drw_sob       (pp_lsntw_sob),
        .pp_drw_eob       (pp_lsntw_eob),
        .pp_drw_sol       (pp_lsntw_sol),
        .pp_drw_eol       (pp_lsntw_eol),
        .pp_drw_sos       (pp_lsntw_sos),
        .pp_drw_eos       (pp_lsntw_eos),
        .pp_drw_pbs_id    (pp_lsntw_pbs_id),
        .pp_drw_avail     (pp_lsntw_avail),

        .drw_ram_data     (lsdrw_ram_data),
        .drw_ram_sob      (lsdrw_ram_sob),
        .drw_ram_eob      (lsdrw_ram_eob),
        .drw_ram_sol      (lsdrw_ram_sol),
        .drw_ram_eol      (lsdrw_ram_eol),
        .drw_ram_sos      (lsdrw_ram_sos),
        .drw_ram_eos      (lsdrw_ram_eos),
        .drw_ram_token    (lsdrw_ram_token),
        .drw_ram_pbs_id   (lsdrw_ram_pbs_id),
        .drw_ram_add      (lsdrw_ram_add),
        .drw_ram_intl_idx (lsdrw_ram_intl_idx),
        .drw_ram_avail    (lsdrw_ram_avail),

        .token_release    (lstoken_release),

        .drw_fifo_eob     (lsdrw_fifo_eob),
        .drw_fifo_pbs_id  (lsdrw_fifo_pbs_id),
        .drw_fifo_intl_idx(lsdrw_fifo_intl_idx),
        .drw_fifo_avail   (lsdrw_fifo_vld)
      );
    end
    else begin : no_wr_ls_gen
      assign lsdrw_ram_data     = 'x;
      assign lsdrw_ram_sob      = 'x;
      assign lsdrw_ram_eob      = 'x;
      assign lsdrw_ram_sol      = 'x;
      assign lsdrw_ram_eol      = 'x;
      assign lsdrw_ram_sos      = 'x;
      assign lsdrw_ram_eos      = 'x;
      assign lsdrw_ram_token    = 'x;
      assign lsdrw_ram_pbs_id   = 'x;
      assign lsdrw_ram_add      = 'x;
      assign lsdrw_ram_intl_idx = 'x;
      assign lsdrw_ram_avail    = 1'b0;

      assign lsdrw_fifo_vld      = 1'b0;
      assign lsdrw_fifo_eob      = 'x;
      assign lsdrw_fifo_pbs_id   = 'x;
      assign lsdrw_fifo_intl_idx = 'x;
    end
  endgenerate

  // ---------------------------------------------------------------------------------------------- --
  // RAM read
  // ---------------------------------------------------------------------------------------------- --
  ntt_core_wmm_ram_rd_pcg #(
    .OP_W       (OP_W),
    .R          (R),
    .PSI        (PSI),
    .S          (S),
    .OUT_PSI_DIV(OUT_PSI_DIV),
    .RAM_LATENCY(RAM_LATENCY),
    .S_INIT     (S_INIT_NEXT),
    .S_DEC      (S_DEC),
    .SEND_TO_SEQ(SEND_TO_SEQ),
    .TOKEN_W    (TOKEN_W),
    .LPB_NB     (LPB_NB)
  ) ntt_core_wmm_ram_rd_pcg (
    .clk                  (clk),
    .s_rst_n              (s_rst_n),

    .seq_ramrd_rden       (seq_ntw_rden),

    .ramrd_rsram_ren      (ramrd_rsram_ren),
    .ramrd_lsram_ren      (ramrd_lsram_ren),
    .ramrd_ram_add        (ramrd_ram_add),
    .ramrd_ram_intl_idx   (ramrd_ram_intl_idx),
    .ramrd_ram_token      (ramrd_ram_token),
    .ramrd_rsram_datar    (ramrd_rsram_datar),
    .ramrd_lsram_datar    (ramrd_lsram_datar),

    .rsfifo_ramrd_eob     (rsfifo_ramrd_eob),
    .rsfifo_ramrd_pbs_id  (rsfifo_ramrd_pbs_id),
    .rsfifo_ramrd_intl_idx(rsfifo_ramrd_intl_idx),
    .rsfifo_ramrd_vld     (rsfifo_ramrd_vld),
    .rsfifo_ramrd_rdy     (rsfifo_ramrd_rdy),

    .lsfifo_ramrd_eob     (lsfifo_ramrd_eob),
    .lsfifo_ramrd_pbs_id  (lsfifo_ramrd_pbs_id),
    .lsfifo_ramrd_intl_idx(lsfifo_ramrd_intl_idx),
    .lsfifo_ramrd_vld     (lsfifo_ramrd_vld),
    .lsfifo_ramrd_rdy     (lsfifo_ramrd_rdy),

    .rstoken_release      (rstoken_release),
    .lstoken_release      (lstoken_release),

    .ramrd_drr_data       (ramrd_drr_data),
    .ramrd_drr_data_avail (ramrd_drr_data_avail),
    .ramrd_drr_sob        (ramrd_drr_sob),
    .ramrd_drr_eob        (ramrd_drr_eob),
    .ramrd_drr_sol        (ramrd_drr_sol),
    .ramrd_drr_eol        (ramrd_drr_eol),
    .ramrd_drr_sos        (ramrd_drr_sos),
    .ramrd_drr_eos        (ramrd_drr_eos),
    .ramrd_drr_pbs_id     (ramrd_drr_pbs_id),
    .ramrd_drr_ctrl_avail (ramrd_drr_ctrl_avail)
  );

  // ---------------------------------------------------------------------------------------------- --
  // Dispatch Rotate read
  // ---------------------------------------------------------------------------------------------- --
  ntt_core_wmm_dispatch_rotate_rd_pcg #(
    .OP_W       (OP_W),
    .R          (R),
    .PSI        (PSI),
    .S          (S),
    .OUT_PSI_DIV(OUT_PSI_DIV),
    .IN_PIPE    (DRR_IN_PIPE),
    .S_INIT     (S_INIT_NEXT),
    .S_DEC      (S_DEC      ),
    .RS_DELTA   (RS_DELTA   ),
    .LS_DELTA   (LS_DELTA   ),
    .LPB_NB     (LPB_NB     )
  ) ntt_core_wmm_dispatch_rotate_rd_pcg (
    .clk            (clk),
    .s_rst_n        (s_rst_n),

    .ram_drr_data       (ramrd_drr_data),
    .ram_drr_data_avail (ramrd_drr_data_avail),
    .ram_drr_sob        (ramrd_drr_sob),
    .ram_drr_eob        (ramrd_drr_eob),
    .ram_drr_sol        (ramrd_drr_sol),
    .ram_drr_eol        (ramrd_drr_eol),
    .ram_drr_sos        (ramrd_drr_sos),
    .ram_drr_eos        (ramrd_drr_eos),
    .ram_drr_pbs_id     (ramrd_drr_pbs_id),
    .ram_drr_ctrl_avail (ramrd_drr_ctrl_avail),

    .drr_seq_data       (ntw_seq_data),
    .drr_seq_data_avail (ntw_seq_data_avail),
    .drr_acc_data_avail (ntw_acc_data_avail),
    .drr_seq_sob        (ntw_seq_sob),
    .drr_seq_eob        (ntw_seq_eob),
    .drr_seq_sol        (ntw_seq_sol),
    .drr_seq_eol        (ntw_seq_eol),
    .drr_seq_sos        (ntw_seq_sos),
    .drr_seq_eos        (ntw_seq_eos),
    .drr_seq_pbs_id     (ntw_seq_pbs_id),
    .drr_seq_ctrl_avail (ntw_seq_ctrl_avail),
    .drr_acc_ctrl_avail (ntw_acc_ctrl_avail)
  );

  assign ntw_acc_data   = ntw_seq_data;
  assign ntw_acc_sob    = ntw_seq_sob;
  assign ntw_acc_eob    = ntw_seq_eob;
  assign ntw_acc_sol    = ntw_seq_sol;
  assign ntw_acc_eol    = ntw_seq_eol;
  assign ntw_acc_sog    = ntw_seq_sos;
  assign ntw_acc_eog    = ntw_seq_eos;
  assign ntw_acc_pbs_id = ntw_seq_pbs_id;

  // ---------------------------------------------------------------------------------------------- --
  // Command FIFO
  // ---------------------------------------------------------------------------------------------- --
  //== Regular stage
  generate
    if (USE_RS) begin : cmd_fifo_rs_gen
      assign rsdrw_fifo_cmd.eob      = rsdrw_fifo_eob;
      assign rsdrw_fifo_cmd.pbs_id   = rsdrw_fifo_pbs_id;
      assign rsdrw_fifo_cmd.intl_idx = rsdrw_fifo_intl_idx;
      assign rsfifo_ramrd_eob        = rsfifo_ramrd_cmd.eob;
      assign rsfifo_ramrd_pbs_id     = rsfifo_ramrd_cmd.pbs_id;
      assign rsfifo_ramrd_intl_idx   = rsfifo_ramrd_cmd.intl_idx;

      fifo_reg #(
        .WIDTH      ($bits(cmd_t)),
        .DEPTH      (BATCH_PBS_NB*INTL_L),
        .LAT_PIPE_MH(CMD_FIFO_LAT_PIPE_MH)
      ) rs_cmd_fifo(
        .clk      (clk),
        .s_rst_n  (s_rst_n),

        .in_data  (rsdrw_fifo_cmd),
        .in_vld   (rsdrw_fifo_vld),
        .in_rdy   (rsdrw_fifo_rdy),

        .out_data (rsfifo_ramrd_cmd),
        .out_vld  (rsfifo_ramrd_vld),
        .out_rdy  (rsfifo_ramrd_rdy)
      );
    end
    else begin : no_cmd_fifo_rs_gen
      assign rsdrw_fifo_rdy          = 1'b0;
      assign rsfifo_ramrd_vld        = 1'b0;
      assign rsfifo_ramrd_eob        = 'x;
      assign rsfifo_ramrd_pbs_id     = 'x;
      assign rsfifo_ramrd_intl_idx   = 'x;
    end
  endgenerate

  //== Last stage
  generate
    if (USE_LS) begin : cmd_fifo_ls_gen
      assign lsdrw_fifo_cmd.eob      = lsdrw_fifo_eob;
      assign lsdrw_fifo_cmd.pbs_id   = lsdrw_fifo_pbs_id;
      assign lsdrw_fifo_cmd.intl_idx = lsdrw_fifo_intl_idx;
      assign lsfifo_ramrd_eob        = lsfifo_ramrd_cmd.eob;
      assign lsfifo_ramrd_pbs_id     = lsfifo_ramrd_cmd.pbs_id;
      assign lsfifo_ramrd_intl_idx   = lsfifo_ramrd_cmd.intl_idx;

      fifo_reg #(
        .WIDTH      ($bits(cmd_t)),
        .DEPTH      (BATCH_PBS_NB*GLWE_K_P1),
        .LAT_PIPE_MH(CMD_FIFO_LAT_PIPE_MH) // NOTE [0] should always be 1 by
                                    // construction.
      ) ls_cmd_fifo(
        .clk      (clk),
        .s_rst_n  (s_rst_n),

        .in_data  (lsdrw_fifo_cmd),
        .in_vld   (lsdrw_fifo_vld),
        .in_rdy   (lsdrw_fifo_rdy),

        .out_data (lsfifo_ramrd_cmd),
        .out_vld  (lsfifo_ramrd_vld),
        .out_rdy  (lsfifo_ramrd_rdy)
      );
    end
    else begin : no_cmd_fifo_ls_gen
      assign lsdrw_fifo_rdy          = 1'b0;
      assign lsfifo_ramrd_vld        = 1'b0;
      assign lsfifo_ramrd_eob        = 'x;
      assign lsfifo_ramrd_pbs_id     = 'x;
      assign lsfifo_ramrd_intl_idx   = 'x;
    end
  endgenerate

// pragma translate_off
// These FIFOs should always be ready to store the command.
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      if (rsdrw_fifo_vld) begin
        assert(rsdrw_fifo_rdy)
        else begin
          $fatal(1, "%t > ERROR: regular stage FIFO is full!", $time);
          $finish;
        end
      end
    end
  end

  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      if (lsdrw_fifo_vld) begin
        assert(lsdrw_fifo_rdy)
        else begin
          $fatal(1, "%t > ERROR: last stage FIFO is full!", $time);
          $finish;
        end
      end
    end
  end
// pragma translate_on

  // ---------------------------------------------------------------------------------------------- --
  // RAM
  // ---------------------------------------------------------------------------------------------- --
  // ----------------------------------
  // Regular stage
  // ----------------------------------
  genvar gen_r, gen_p;
  generate
    if (USE_RS) begin : ram_rs_gen
      logic                                 rsram_wr_en;
      ram_add_t [PSI-1:0][R-1:0]            rsram_wr_add;
      logic     [PSI-1:0][R-1:0][OP_W-1:0]  rsram_wr_data;

      logic                                 rsram_rd_en;
      ram_add_t [PSI-1:0][R-1:0]            rsram_rd_add;

      // Write request
      assign rsram_wr_en   = rsdrw_ram_avail;
      assign rsram_wr_data = rsdrw_ram_data;

      always_comb begin
        for (int r = 0; r < R; r = r + 1) begin
          for (int p = 0; p < PSI; p = p + 1) begin
            rsram_wr_add[p][r].token    = rsdrw_ram_token;
            rsram_wr_add[p][r].intl_idx = rsdrw_ram_intl_idx[NTW_INTL_L_W-1:0];
            rsram_wr_add[p][r].stg_iter = rsdrw_ram_add[p][r];
          end
        end
      end
      // Read request
      assign rsram_rd_en = ramrd_rsram_ren;

      always_comb begin
        for (int r = 0; r < R; r = r + 1) begin
          for (int p = 0; p < PSI; p = p + 1) begin
            rsram_rd_add[p][r].token    = ramrd_ram_token;
            rsram_rd_add[p][r].intl_idx = ramrd_ram_intl_idx[NTW_INTL_L_W-1:0];
            rsram_rd_add[p][r].stg_iter = ramrd_ram_add;
          end
        end
      end

      // RAM instance
      for (gen_p = 0; gen_p < PSI; gen_p = gen_p + 1) begin : rs_psi_loop_gen
        for (gen_r = 0; gen_r < R; gen_r = gen_r + 1) begin : rs_r_loop_gen
          ram_wrapper_1R1W #(
            .WIDTH            (OP_W),
            .DEPTH            (RAM_DEPTH),
            .RD_WR_ACCESS_TYPE(1),
            .KEEP_RD_DATA     (0),
            .RAM_LATENCY      (RAM_LATENCY)
          ) regular_stage_ram (
            .clk    (clk),
            .s_rst_n(s_rst_n),

            .rd_en  (rsram_rd_en),
            .rd_add (rsram_rd_add[gen_p][gen_r]),
            .rd_data(ramrd_rsram_datar[gen_p][gen_r]),

            .wr_en  (rsram_wr_en),
            .wr_add (rsram_wr_add[gen_p][gen_r]),
            .wr_data(rsram_wr_data[gen_p][gen_r])
          );
        end
      end

    end // ram_rs_gen
    else begin : no_ram_rs_gen
      assign ramrd_rsram_datar = 'x;
    end
  endgenerate


  // ----------------------------------
  // Last stage
  // ----------------------------------
  generate
    if (USE_LS) begin : ram_ls_gen
      logic                                lsram_wr_en;
      ram_add_t [PSI-1:0][R-1:0]           lsram_wr_add;
      logic     [PSI-1:0][R-1:0][OP_W-1:0] lsram_wr_data;

      logic                                lsram_rd_en;
      ram_add_t [PSI-1:0][R-1:0]           lsram_rd_add;

      // Write request
      assign lsram_wr_en   = lsdrw_ram_avail;
      assign lsram_wr_data = lsdrw_ram_data;

      always_comb begin
        for (int r = 0; r < R; r = r + 1) begin
          for (int p = 0; p < PSI; p = p + 1) begin
            lsram_wr_add[p][r].token    = lsdrw_ram_token;
            lsram_wr_add[p][r].intl_idx = lsdrw_ram_intl_idx[NTW_INTL_L_W-1:0];
            lsram_wr_add[p][r].stg_iter = lsdrw_ram_add[p][r];
          end
        end
      end

      // Read request
      assign lsram_rd_en = ramrd_lsram_ren;

      always_comb begin
        for (int r = 0; r < R; r = r + 1) begin
          for (int p = 0; p < PSI; p = p + 1) begin
            lsram_rd_add[p][r].token    = ramrd_ram_token;
            lsram_rd_add[p][r].intl_idx = ramrd_ram_intl_idx[NTW_INTL_L_W-1:0];
            lsram_rd_add[p][r].stg_iter = ramrd_ram_add;
          end
        end
      end

      // RAM instance
      for (gen_p = 0; gen_p < PSI; gen_p = gen_p + 1) begin : psi_loop_gen
        for (gen_r = 0; gen_r < R; gen_r = gen_r + 1) begin : r_loop_gen
          ram_wrapper_1R1W #(
            .WIDTH            (OP_W),
            .DEPTH            (RAM_DEPTH),
            .RD_WR_ACCESS_TYPE(1),
            .KEEP_RD_DATA     (0),
            .RAM_LATENCY      (RAM_LATENCY)
          ) last_stage_ram (
            .clk    (clk),
            .s_rst_n(s_rst_n),

            .rd_en  (lsram_rd_en),
            .rd_add (lsram_rd_add[gen_p][gen_r]),
            .rd_data(ramrd_lsram_datar[gen_p][gen_r]),

            .wr_en  (lsram_wr_en),
            .wr_add (lsram_wr_add[gen_p][gen_r]),
            .wr_data(lsram_wr_data[gen_p][gen_r])
          );
        end
      end
    end // if ram_ls_gen
    else begin : no_ram_ls_gen
      assign ramrd_lsram_datar = 'x;
    end
  endgenerate


endmodule
