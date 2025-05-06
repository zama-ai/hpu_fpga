// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// NTT core tackles the NTT and INTT computations by using the same DIT butterfly-units.
// It also computes a matrix multiplication.
//
// Prerequisites :
// Input data are interleaved in time, to avoid an output accumulator.
// Input order is the "incremental stride" order, with R**(S-1) as the stride.
// Output data are also interleaved in time.
// Output order is also the "incremental stride" order.
//
// The unfold_pcg architecture:
//   NTT and INTT are sequential.
//   Use pseudo constant geometry architecture (PCG)
//
// The 'head' module is the first part of the module, used when split into pieces.
// It contains the input fifo and the sequencer.
//
// ==============================================================================================

module ntt_core_with_matrix_multiplication_unfold_pcg_head
  import pep_common_param_pkg::*;
#(
  parameter  int           OP_W          = 32,
  parameter  int           R             = 2, // Butterfly Radix
  parameter  int           PSI           = 4,  // Number of butterflies in parallel
  parameter  int           S             = 11, // Total number of stages
  parameter  int           RAM_LATENCY   = 1

) (
  input  logic                            clk,
  input  logic                            s_rst_n,
  // Data from decomposition
  input  logic [PSI-1:0][R-1:0][OP_W-1:0] decomp_ntt_data,
  input  logic [PSI-1:0][R-1:0]           decomp_ntt_data_vld,
  output logic [PSI-1:0][R-1:0]           decomp_ntt_data_rdy,
  input  logic                            decomp_ntt_sob,
  input  logic                            decomp_ntt_eob,
  input  logic                            decomp_ntt_sol,
  input  logic                            decomp_ntt_eol,
  input  logic                            decomp_ntt_sog,
  input  logic                            decomp_ntt_eog,
  input  logic  [BPBS_ID_W-1:0]           decomp_ntt_pbs_id,
  input  logic                            decomp_ntt_last_pbs,
  input  logic                            decomp_ntt_full_throughput,
  input  logic                            decomp_ntt_ctrl_vld,
  output logic                            decomp_ntt_ctrl_rdy,

  // seq -> clbu
  output logic [PSI-1:0][R-1:0][OP_W-1:0] seq_clbu_data,
  output logic [PSI-1:0]                  seq_clbu_data_avail,
  output logic                            seq_clbu_sob,
  output logic                            seq_clbu_eob,
  output logic                            seq_clbu_sol,
  output logic                            seq_clbu_eol,
  output logic                            seq_clbu_sos,
  output logic                            seq_clbu_eos,
  output logic [BPBS_ID_W-1:0]            seq_clbu_pbs_id,
  output logic                            seq_clbu_ntt_bwd,
  output logic                            seq_clbu_ctrl_avail
);
  // =========================================================================================== //
  // localparam
  // =========================================================================================== //
  localparam int LPB_NB       = 1; // No loopback in unfold architecture
  localparam int INFIFO_DEPTH = 0; // UNUSED

  // =========================================================================================== //
  // Signals
  // =========================================================================================== //
  // infifo -> seq
  logic [     PSI-1:0][       R-1:0][OP_W-1:0]           infifo_seq_data;
  logic [     PSI-1:0][       R-1:0]                     infifo_seq_data_vld;
  logic [     PSI-1:0][       R-1:0]                     infifo_seq_data_rdy;
  logic                                                  infifo_seq_sob;
  logic                                                  infifo_seq_eob;
  logic                                                  infifo_seq_sol;
  logic                                                  infifo_seq_eol;
  logic                                                  infifo_seq_sog;
  logic                                                  infifo_seq_eog;
  logic [BPBS_ID_W-1:0]                                   infifo_seq_pbs_id;
  logic                                                  infifo_seq_last_pbs;
  logic                                                  infifo_seq_full_throughput;
  logic                                                  infifo_seq_ctrl_vld;
  logic                                                  infifo_seq_ctrl_rdy; 

  // ============================================================================================ //
  // Infifo
  // ============================================================================================ //
  ntt_core_wmm_infifo #(
    .OP_W       (OP_W),
    .R          (R),
    .PSI        (PSI),
    .RAM_LATENCY(RAM_LATENCY),
    .DEPTH      (INFIFO_DEPTH),   // UNUSED
    .BYPASS     (1'b1) // Unfold architecture does not need infifo to bufferize input data.
  ) ntt_core_wmm_infifo (
    // system
    .clk                          (clk),
    .s_rst_n                      (s_rst_n),
    // decomp -> infifo
    .decomp_infifo_data           (decomp_ntt_data),
    .decomp_infifo_data_vld       (decomp_ntt_data_vld),
    .decomp_infifo_data_rdy       (decomp_ntt_data_rdy),
    .decomp_infifo_sob            (decomp_ntt_sob),
    .decomp_infifo_eob            (decomp_ntt_eob),
    .decomp_infifo_sol            (decomp_ntt_sol),
    .decomp_infifo_eol            (decomp_ntt_eol),
    .decomp_infifo_sog            (decomp_ntt_sog),
    .decomp_infifo_eog            (decomp_ntt_eog),
    .decomp_infifo_pbs_id         (decomp_ntt_pbs_id),
    .decomp_infifo_last_pbs       (decomp_ntt_last_pbs),
    .decomp_infifo_full_throughput(decomp_ntt_full_throughput),
    .decomp_infifo_ctrl_vld       (decomp_ntt_ctrl_vld),
    .decomp_infifo_ctrl_rdy       (decomp_ntt_ctrl_rdy),
    // infifo -> sequencer
    .infifo_seq_data              (infifo_seq_data),
    .infifo_seq_data_vld          (infifo_seq_data_vld),
    .infifo_seq_data_rdy          (infifo_seq_data_rdy),
    .infifo_seq_sob               (infifo_seq_sob),
    .infifo_seq_eob               (infifo_seq_eob),
    .infifo_seq_sol               (infifo_seq_sol),
    .infifo_seq_eol               (infifo_seq_eol),
    .infifo_seq_sog               (infifo_seq_sog),
    .infifo_seq_eog               (infifo_seq_eog),
    .infifo_seq_pbs_id            (infifo_seq_pbs_id),
    .infifo_seq_last_pbs          (infifo_seq_last_pbs),
    .infifo_seq_full_throughput   (infifo_seq_full_throughput),
    .infifo_seq_ctrl_vld          (infifo_seq_ctrl_vld),
    .infifo_seq_ctrl_rdy          (infifo_seq_ctrl_rdy)
  );

  // ============================================================================================ //
  // Sequencer
  // ============================================================================================ //
  ntt_core_wmm_sequencer #(
    .OP_W          (OP_W),
    .R             (R),
    .PSI           (PSI),
    .S             (S),
    .NTW_RD_LATENCY(0), // UNUSED
    .S_DEC         (0),
    .LPB_NB        (LPB_NB) // No loopback in unfold architecture
  ) ntt_core_wmm_sequencer (
    // system
    .clk                       (clk),
    .s_rst_n                   (s_rst_n),
    // infifo -> sequencer
    .infifo_seq_data           (infifo_seq_data),
    .infifo_seq_data_vld       (infifo_seq_data_vld),
    .infifo_seq_data_rdy       (infifo_seq_data_rdy),
    .infifo_seq_sob            (infifo_seq_sob),
    .infifo_seq_eob            (infifo_seq_eob),
    .infifo_seq_sol            (infifo_seq_sol),
    .infifo_seq_eol            (infifo_seq_eol),
    .infifo_seq_sog            (infifo_seq_sog),
    .infifo_seq_eog            (infifo_seq_eog),
    .infifo_seq_pbs_id         (infifo_seq_pbs_id),
    .infifo_seq_last_pbs       (infifo_seq_last_pbs),
    .infifo_seq_full_throughput(infifo_seq_full_throughput),
    .infifo_seq_ctrl_vld       (infifo_seq_ctrl_vld),
    .infifo_seq_ctrl_rdy       (infifo_seq_ctrl_rdy),
    // network -> sequencer
    .ntw_seq_data              (/*UNUSED*/),
    .ntw_seq_data_avail        ('0),
    .ntw_seq_sob               (/*UNUSED*/),
    .ntw_seq_eob               (/*UNUSED*/),
    .ntw_seq_sol               (/*UNUSED*/),
    .ntw_seq_eol               (/*UNUSED*/),
    .ntw_seq_sos               (/*UNUSED*/),
    .ntw_seq_eos               (/*UNUSED*/),
    .ntw_seq_pbs_id            (/*UNUSED*/),
    .ntw_seq_ctrl_avail        (1'b0),
    // sequencer -> CLBU
    .seq_clbu_data             (seq_clbu_data),
    .seq_clbu_data_avail       (seq_clbu_data_avail),
    .seq_clbu_sob              (seq_clbu_sob),
    .seq_clbu_eob              (seq_clbu_eob),
    .seq_clbu_sol              (seq_clbu_sol),
    .seq_clbu_eol              (seq_clbu_eol),
    .seq_clbu_sos              (seq_clbu_sos),
    .seq_clbu_eos              (seq_clbu_eos),
    .seq_clbu_pbs_id           (seq_clbu_pbs_id),
    .seq_clbu_ntt_bwd          (seq_clbu_ntt_bwd),
    .seq_clbu_ctrl_avail       (seq_clbu_ctrl_avail),
    // sequencer -> ntw read enable
    .seq_ntw_fwd_rden          (/*UNUSED*/),
    .seq_ntw_bwd_rden          (/*UNUSED*/)
  );

endmodule
