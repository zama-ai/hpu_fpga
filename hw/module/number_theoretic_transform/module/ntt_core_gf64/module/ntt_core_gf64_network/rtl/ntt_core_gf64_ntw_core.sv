// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the network between the radix columns.
//
// ==============================================================================================

module ntt_core_gf64_ntw_core
  import pep_common_param_pkg::*;
  import param_tfhe_pkg::*;
  import ntt_core_common_param_pkg::*;
  import ntt_core_gf64_common_param_pkg::*;
#(
  parameter int    RDX_CUT_ID      = 1, // increasing numbering for FWD, decreasing for BWD
                                        // FWD : 1 means ngc
                                        // BWD : 0 means ngc
                                        // Column that precedes the network.
  parameter bit    BWD             = 1'b0,
  parameter int    OP_W            = 66,
  parameter bit    IN_PIPE         = 1'b1, // Recommended
  parameter int    RAM_LATENCY     = 2
)
(
  input  logic                            clk,        // clock
  input  logic                            s_rst_n,    // synchronous reset


  input  logic [PSI*R-1:0][OP_W-1:0]      in_data,
  input  logic [PSI*R-1:0]                in_avail,
  input  logic                            in_sob,
  input  logic                            in_eob,
  input  logic                            in_sol,
  input  logic                            in_eol,
  input  logic                            in_sos,
  input  logic                            in_eos,
  input  logic [BPBS_ID_W-1:0]            in_pbs_id,

  output logic [PSI*R-1:0][OP_W-1:0]      out_data,
  output logic [PSI*R-1:0]                out_avail,
  output logic                            out_sob,
  output logic                            out_eob,
  output logic                            out_sol,
  output logic                            out_eol,
  output logic                            out_sos,
  output logic                            out_eos,
  output logic [BPBS_ID_W-1:0]            out_pbs_id
);

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int TOKEN_W = 2; // 2**TOKEN_W working blocks are stored.
                              // 2 are needed for the ping-pong. Additional one for read/write margin
                              // to avoid overflow.

// ============================================================================================== --
// Signals
// ============================================================================================== --
  // RAM
  logic [PSI*R-1:0][OP_W-1:0]       ram_wr_data;
  logic [PSI*R-1:0]                 ram_wr_avail;
  logic [PSI*R-1:0][STG_ITER_W-1:0] ram_wr_add;
  logic [INTL_L_W-1:0]              ram_wr_intl_idx;
  logic [TOKEN_W-1:0]               ram_wr_token;

  // Token
  logic                             token_release;

  // Command FIFO
  logic                             cmd_fifo_avail;
  logic [BPBS_ID_W-1:0]             cmd_fifo_pbs_id;
  logic [INTL_L_W-1:0]              cmd_fifo_intl_idx;
  logic                             cmd_fifo_eob;

  // RAM rd data
  logic [PSI*R-1:0][OP_W-1:0]       ram_rd_data;
  logic [PSI*R-1:0]                 ram_rd_avail;
  logic                             ram_rd_sob;
  logic                             ram_rd_eob;
  logic                             ram_rd_sol;
  logic                             ram_rd_eol;
  logic                             ram_rd_sos;
  logic                             ram_rd_eos;
  logic [BPBS_ID_W-1:0]             ram_rd_pbs_id;

// ============================================================================================== --
// Write
// ============================================================================================== --
  ntt_core_gf64_ntw_core_wr
  #(
    .RDX_CUT_ID      (RDX_CUT_ID),
    .BWD             (BWD),
    .IN_PIPE         (1'b1),
    .OP_W            (OP_W),
    .TOKEN_W         (TOKEN_W)
  ) ntt_core_gf64_ntw_core_wr (
    .clk               (clk),
    .s_rst_n           (s_rst_n),

    .in_data           (in_data),
    .in_avail          (in_avail),
    .in_sob            (in_sob),
    .in_eob            (in_eob),
    .in_sol            (in_sol),
    .in_eol            (in_eol),
    .in_sos            (in_sos),
    .in_eos            (in_eos),
    .in_pbs_id         (in_pbs_id),

    .ram_wr_data       (ram_wr_data),
    .ram_wr_avail      (ram_wr_avail),
    .ram_wr_add        (ram_wr_add),
    .ram_wr_intl_idx   (ram_wr_intl_idx),
    .ram_wr_token      (ram_wr_token),

    .token_release     (token_release),

    .cmd_fifo_avail    (cmd_fifo_avail),
    .cmd_fifo_pbs_id   (cmd_fifo_pbs_id),
    .cmd_fifo_intl_idx (cmd_fifo_intl_idx),
    .cmd_fifo_eob      (cmd_fifo_eob)
  );

// ============================================================================================== --
// Read
// ============================================================================================== --
  ntt_core_gf64_ntw_core_rd
  #(
    .RDX_CUT_ID      (RDX_CUT_ID),
    .BWD             (BWD),
    .IN_PIPE         (1'b1),
    .OP_W            (OP_W),
    .TOKEN_W         (TOKEN_W)
  ) ntt_core_gf64_ntw_core_rd (
    .clk        (clk),
    .s_rst_n    (s_rst_n),

    .in_data    (ram_rd_data),
    .in_avail   (ram_rd_avail),
    .in_sob     (ram_rd_sob),
    .in_eob     (ram_rd_eob),
    .in_sol     (ram_rd_sol),
    .in_eol     (ram_rd_eol),
    .in_sos     (ram_rd_sos),
    .in_eos     (ram_rd_eos),
    .in_pbs_id  (ram_rd_pbs_id),

    .out_data   (out_data),
    .out_avail  (out_avail),
    .out_sob    (out_sob),
    .out_eob    (out_eob),
    .out_sol    (out_sol),
    .out_eol    (out_eol),
    .out_sos    (out_sos),
    .out_eos    (out_eos),
    .out_pbs_id (out_pbs_id)
  );

// ============================================================================================== --
// RAM
// ============================================================================================== --
  ntt_core_gf64_ntw_core_ram
  #(
    .RDX_CUT_ID  (RDX_CUT_ID),
    .BWD         (BWD),
    .OP_W        (OP_W),
    .RAM_LATENCY (RAM_LATENCY),
    .TOKEN_W     (TOKEN_W)
  ) ntt_core_gf64_ntw_core_ram (
    .clk               (clk),
    .s_rst_n           (s_rst_n),

    .ram_wr_data       (ram_wr_data),
    .ram_wr_avail      (ram_wr_avail),
    .ram_wr_add        (ram_wr_add),
    .ram_wr_intl_idx   (ram_wr_intl_idx),
    .ram_wr_token      (ram_wr_token),

    .token_release     (token_release),

    .cmd_fifo_avail    (cmd_fifo_avail),
    .cmd_fifo_pbs_id   (cmd_fifo_pbs_id),
    .cmd_fifo_intl_idx (cmd_fifo_intl_idx),
    .cmd_fifo_eob      (cmd_fifo_eob),

    .out_data          (ram_rd_data),
    .out_avail         (ram_rd_avail),
    .out_sob           (ram_rd_sob),
    .out_eob           (ram_rd_eob),
    .out_sol           (ram_rd_sol),
    .out_eol           (ram_rd_eol),
    .out_sos           (ram_rd_sos),
    .out_eos           (ram_rd_eos),
    .out_pbs_id        (ram_rd_pbs_id)
  );
endmodule
