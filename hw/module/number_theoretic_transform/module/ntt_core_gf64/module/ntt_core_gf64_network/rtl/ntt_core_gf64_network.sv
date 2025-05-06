// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module handles the network between radix columns.
//
// ==============================================================================================

`include "ntt_core_gf64_ntw_macro_inc.sv"

module ntt_core_gf64_network
  import pep_common_param_pkg::*;
  import param_tfhe_pkg::*;
  import ntt_core_common_param_pkg::*;
  import ntt_core_gf64_common_param_pkg::*;
#(
  parameter int    RDX_CUT_ID      = 0, // increasing numbering for FWD, decreasing for BWD
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
  `NTT_CORE_GF64_NTW_LOCALPARAM(RDX_CUT_ID,BWD,R,PSI)

  generate
    if ((BWD && RDX_CUT_ID==0) || (!BWD && RDX_CUT_ID==NTT_RDX_CUT_NB-1)) begin : _UNSUPPORTED_RDX_CUT_ID_0
      $fatal(1,"> ERROR: Do not support the implementation of a network after the last radix column BWD=%0d RDX_CUT_ID=%0d!", BWD, RDX_CUT_ID);
    end
  endgenerate
// ============================================================================================== --
// Instances
// ============================================================================================== --
  generate
    if (C >= N_L) begin : gen_cst
      ntt_core_gf64_ntw_cst
      #(
        .RDX_CUT_ID  (RDX_CUT_ID),
        .BWD         (BWD),
        .OP_W        (OP_W),
        .IN_PIPE     (IN_PIPE),
        .OUT_PIPE    (1'b1) // Since PSI*R could be big, give a whole cycle for the connection.
      ) ntt_core_gf64_ntw_cst (
        .clk        (clk),
        .s_rst_n    (s_rst_n),

        .in_data    (in_data),
        .in_avail   (in_avail),
        .in_sob     (in_sob),
        .in_eob     (in_eob),
        .in_sol     (in_sol),
        .in_eol     (in_eol),
        .in_sos     (in_sos),
        .in_eos     (in_eos),
        .in_pbs_id  (in_pbs_id),

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
    end
    else begin : gen_no_cst
      ntt_core_gf64_ntw_core
      #(
        .RDX_CUT_ID      (RDX_CUT_ID),
        .BWD             (BWD),
        .OP_W            (OP_W),
        .IN_PIPE         (IN_PIPE),
        .RAM_LATENCY     (RAM_LATENCY)
      ) ntt_core_gf64_ntw_core (
        .clk        (clk),
        .s_rst_n    (s_rst_n),

        .in_data    (in_data),
        .in_avail   (in_avail),
        .in_sob     (in_sob),
        .in_eob     (in_eob),
        .in_sol     (in_sol),
        .in_eol     (in_eol),
        .in_sos     (in_sos),
        .in_eos     (in_eos),
        .in_pbs_id  (in_pbs_id),

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

    end
  endgenerate
endmodule
