// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the network between the radix columns.
// This network is hardwired.
// ==============================================================================================

`include "ntt_core_gf64_ntw_macro_inc.sv"

module ntt_core_gf64_ntw_cst
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
  parameter bit    IN_PIPE         = 1'b1, // Recommended : at least one of the 2 : IN_PIPE or OUT_PIPE
  parameter bit    OUT_PIPE        = 1'b1  // "
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

  // =========================================================================================== --
  // localparam
  // =========================================================================================== --
  `NTT_CORE_GF64_NTW_LOCALPARAM(RDX_CUT_ID,BWD,R,PSI)

  // =========================================================================================== --
  // type
  // =========================================================================================== --
  typedef struct packed {
    logic                 sob;
    logic                 eob;
    logic                 sol;
    logic                 eol;
    logic                 sos;
    logic                 eos;
    logic [BPBS_ID_W-1:0] pbs_id;
  } ctrl_t;

  localparam CTRL_W = $bits(ctrl_t);

  // =========================================================================================== --
  // Input pipe
  // =========================================================================================== --
  logic [C-1:0][OP_W-1:0] s0_data;
  ctrl_t                  s0_ctrl;
  logic [C-1:0]           s0_avail;

  generate
    if (IN_PIPE) begin : gen_in_pipe
      always_ff @(posedge clk)
        if (!s_rst_n) s0_avail <= '0;
        else          s0_avail <= in_avail;

      always_ff @(posedge clk) begin
        s0_data         <= in_data;
        s0_ctrl.sob     <= in_sob;
        s0_ctrl.eob     <= in_eob;
        s0_ctrl.sol     <= in_sol;
        s0_ctrl.eol     <= in_eol;
        s0_ctrl.sos     <= in_sos;
        s0_ctrl.eos     <= in_eos;
        s0_ctrl.pbs_id  <= in_pbs_id;
      end
    end else begin : gen_no_in_pipe
      assign s0_data         = in_data;
      assign s0_ctrl.sob     = in_sob;
      assign s0_ctrl.eob     = in_eob;
      assign s0_ctrl.sol     = in_sol;
      assign s0_ctrl.eol     = in_eol;
      assign s0_ctrl.sos     = in_sos;
      assign s0_ctrl.eos     = in_eos;
      assign s0_ctrl.pbs_id  = in_pbs_id;
      assign s0_avail        = in_avail;
    end
  endgenerate

  // =========================================================================================== --
  // Network
  // =========================================================================================== --
  logic [WB_NB-1:0][R_L-1:0][L_NB-1:0][OP_W-1:0] s0_data_a;
  logic [WB_NB-1:0][L_NB-1:0][R_L-1:0][OP_W-1:0] s0_disp_a;

  assign s0_data_a = s0_data;

  always_comb
    for (int b=0; b<WB_NB; b=b+1)
      for (int i=0; i<L_NB; i=i+1)
        for (int j=0; j<R_L; j=j+1)
          s0_disp_a[b][i][j] = s0_data_a[b][j][i];

  // =========================================================================================== --
  // Output
  // =========================================================================================== --
  logic [C-1:0][OP_W-1:0] s1_disp;
  ctrl_t                  s1_ctrl;
  logic [C-1:0]           s1_avail;

  generate
    if (OUT_PIPE) begin : gen_out_pipe
      always_ff @(posedge clk)
        if (!s_rst_n) s1_avail <= '0;
        else          s1_avail <= s0_avail;

      always_ff @(posedge clk) begin
        s1_disp  <= s0_disp_a;
        s1_ctrl  <= s0_ctrl;
      end
    end else begin : gen_no_s0_pipe
      assign s1_disp   = s0_disp_a;
      assign s1_ctrl   = s0_ctrl;
      assign s1_avail  = s0_avail;
    end
  endgenerate

  assign out_data   = s1_disp;
  assign out_avail  = s1_avail;
  assign out_sob    = s1_ctrl.sob;
  assign out_eob    = s1_ctrl.eob;
  assign out_sol    = s1_ctrl.sol;
  assign out_eol    = s1_ctrl.eol;
  assign out_sos    = s1_ctrl.sos;
  assign out_eos    = s1_ctrl.eos;
  assign out_pbs_id = s1_ctrl.pbs_id;

endmodule
