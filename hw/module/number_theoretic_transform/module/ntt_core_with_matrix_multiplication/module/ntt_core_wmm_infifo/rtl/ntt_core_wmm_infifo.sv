// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module is the NTT input FIFO. It bufferizes data from the monomial mult path.
// If BYPASS = 1: Use a fifo_element.
//
// Duplicate the ready valid path to ease the P&R.
// ==============================================================================================

`include "ntt_core_common_macro_inc.sv"

module ntt_core_wmm_infifo
  import param_tfhe_pkg::*;
  import pep_common_param_pkg::*;
#(
  parameter  int OP_W        = 32,
  parameter  int R           = 8, // Butterfly Radix
  parameter  int PSI         = 8, // Number of butterflies
  parameter  int RAM_LATENCY = 1,
  localparam int S           = $clog2(N)/$clog2(R),
  `NTT_CORE_LOCALPARAM_HEADER(R,S,PSI),
  parameter  int DEPTH       = BATCH_PBS_NB * STG_ITER_NB * INTL_L,
  parameter  bit BYPASS      = 1'b0
) (
  input                                 clk,     // clock
  input                                 s_rst_n, // synchronous reset

  // Data from decomposition
  input [PSI-1:0][R-1:0][    OP_W-1:0]  decomp_infifo_data,
  input [PSI-1:0][R-1:0]                decomp_infifo_data_vld,
  output[PSI-1:0][R-1:0]                decomp_infifo_data_rdy,

  input                                 decomp_infifo_sob,
  input                                 decomp_infifo_eob,
  input                                 decomp_infifo_sol,
  input                                 decomp_infifo_eol,
  input                                 decomp_infifo_sog,
  input                                 decomp_infifo_eog,
  input                 [BPBS_ID_W-1:0]  decomp_infifo_pbs_id,
  input                                 decomp_infifo_last_pbs,
  input                                 decomp_infifo_full_throughput,
  input                                 decomp_infifo_ctrl_vld,
  output                                decomp_infifo_ctrl_rdy,

  // Data to sequencer
  output [PSI-1:0][R-1:0][    OP_W-1:0] infifo_seq_data,
  output [PSI-1:0][R-1:0]               infifo_seq_data_vld,
  input  [PSI-1:0][R-1:0]               infifo_seq_data_rdy,

  output                                infifo_seq_sob,
  output                                infifo_seq_eob,
  output                                infifo_seq_sol,
  output                                infifo_seq_eol,
  output                                infifo_seq_sog,
  output                                infifo_seq_eog,
  output                 [BPBS_ID_W-1:0] infifo_seq_pbs_id,
  output                                infifo_seq_last_pbs,
  output                                infifo_seq_full_throughput,
  output                                infifo_seq_ctrl_vld,
  input                                 infifo_seq_ctrl_rdy
);

// ============================================================================================== --
// Type
// ============================================================================================== --
typedef struct packed {
    logic                sob;
    logic                eob;
    logic                sol;
    logic                eol;
    logic                sog;
    logic                eog;
    logic [BPBS_ID_W-1:0] pbs_id;
    logic                last_pbs;
} ctrl_t;

localparam int CTRL_W = $bits(ctrl_t);

// ============================================================================================== --
// ntt_core_wmm_infifo
// ============================================================================================== --
  // ---------------------------------------------------------------------------------------------- --
  // FIFO instance : Data
  // ---------------------------------------------------------------------------------------------- --
  generate
    for (genvar gen_p=0; gen_p<PSI; gen_p=gen_p+1) begin : psi_loop_gen
      for (genvar gen_r=0; gen_r<R; gen_r=gen_r+1) begin : r_loop_gen
        if (BYPASS == 1'b1) begin : gen_bypass
          fifo_element #(
            .WIDTH          (OP_W),
            .DEPTH          (2),
            .TYPE_ARRAY     (8'h12),
            .DO_RESET_DATA  ('0),
            .RESET_DATA_VAL ('0)
          ) fifo_element_data (
            .clk    (clk),
            .s_rst_n(s_rst_n),

            .in_data(decomp_infifo_data[gen_p][gen_r]),
            .in_vld (decomp_infifo_data_vld[gen_p][gen_r]),
            .in_rdy (decomp_infifo_data_rdy[gen_p][gen_r]),

            .out_data(infifo_seq_data[gen_p][gen_r]),
            .out_vld (infifo_seq_data_vld[gen_p][gen_r]),
            .out_rdy (infifo_seq_data_rdy[gen_p][gen_r])
          );
        end
        else begin : gen_fifo
          fifo_ram_rdy_vld #(
            .WIDTH         (OP_W),
            .DEPTH         (DEPTH),
            .RAM_LATENCY   (RAM_LATENCY),
            .ALMOST_FULL_REMAIN (0) // UNUSED
          ) fifo_data (
            .clk    (clk),
            .s_rst_n(s_rst_n),

            .in_data(decomp_infifo_data[gen_p][gen_r]),
            .in_vld (decomp_infifo_data_vld[gen_p][gen_r]),
            .in_rdy (decomp_infifo_data_rdy[gen_p][gen_r]),

            .out_data(infifo_seq_data[gen_p][gen_r]),
            .out_vld (infifo_seq_data_vld[gen_p][gen_r]),
            .out_rdy (infifo_seq_data_rdy[gen_p][gen_r]),

            .almost_full() // UNUSED
          );
        end
      end
    end
  endgenerate

  // ---------------------------------------------------------------------------------------------- --
  // FIFO instance : Control
  // ---------------------------------------------------------------------------------------------- --
  ctrl_t decomp_infifo_ctrl;
  ctrl_t infifo_seq_ctrl;

  assign decomp_infifo_ctrl.sob     = decomp_infifo_sob     ;
  assign decomp_infifo_ctrl.eob     = decomp_infifo_eob     ;
  assign decomp_infifo_ctrl.sol     = decomp_infifo_sol     ;
  assign decomp_infifo_ctrl.eol     = decomp_infifo_eol     ;
  assign decomp_infifo_ctrl.sog     = decomp_infifo_sog     ;
  assign decomp_infifo_ctrl.eog     = decomp_infifo_eog     ;
  assign decomp_infifo_ctrl.pbs_id  = decomp_infifo_pbs_id  ;
  assign decomp_infifo_ctrl.last_pbs= decomp_infifo_last_pbs;

  assign infifo_seq_sob            = infifo_seq_ctrl.sob     ;
  assign infifo_seq_eob            = infifo_seq_ctrl.eob     ;
  assign infifo_seq_sol            = infifo_seq_ctrl.sol     ;
  assign infifo_seq_eol            = infifo_seq_ctrl.eol     ;
  assign infifo_seq_sog            = infifo_seq_ctrl.sog     ;
  assign infifo_seq_eog            = infifo_seq_ctrl.eog     ;
  assign infifo_seq_pbs_id         = infifo_seq_ctrl.pbs_id  ;
  assign infifo_seq_last_pbs       = infifo_seq_ctrl.last_pbs;

  generate
    if (BYPASS == 1'b1) begin : gen_bypass
      fifo_element #(
        .WIDTH          (CTRL_W),
        .DEPTH          (2),
        .TYPE_ARRAY     (8'h12),
        .DO_RESET_DATA  ('0),
        .RESET_DATA_VAL ('0)
      ) fifo_element_data (
        .clk    (clk),
        .s_rst_n(s_rst_n),

        .in_data(decomp_infifo_ctrl),
        .in_vld (decomp_infifo_ctrl_vld),
        .in_rdy (decomp_infifo_ctrl_rdy),

        .out_data(infifo_seq_ctrl),
        .out_vld (infifo_seq_ctrl_vld),
        .out_rdy (infifo_seq_ctrl_rdy)
      );

    end
    else begin : gen_fifo
      fifo_ram_rdy_vld #(
        .WIDTH         (CTRL_W),
        .DEPTH         (DEPTH),
        .RAM_LATENCY   (RAM_LATENCY),
        .ALMOST_FULL_REMAIN (0) // UNUSED
      ) fifo_ctrl (
        .clk    (clk),
        .s_rst_n(s_rst_n),

        .in_data(decomp_infifo_ctrl),
        .in_vld (decomp_infifo_ctrl_vld),
        .in_rdy (decomp_infifo_ctrl_rdy),

        .out_data(infifo_seq_ctrl),
        .out_vld (infifo_seq_ctrl_vld),
        .out_rdy (infifo_seq_ctrl_rdy),

        .almost_full() // UNUSED
      );
    end
  endgenerate

  // ---------------------------------------------------------------------------------------------- --
  // Full throughput
  // ---------------------------------------------------------------------------------------------- --
  logic [BPBS_ID_W:0] eob_cnt;
  logic [BPBS_ID_W:0] eob_cntD;
  logic              eob_present;
  logic              in_full_throughput;

  assign eob_cntD = (decomp_infifo_ctrl_vld && decomp_infifo_ctrl_rdy && decomp_infifo_eob) ?
                      (infifo_seq_ctrl_vld && infifo_seq_ctrl_rdy && infifo_seq_eob) ? eob_cnt : eob_cnt + 1 :
                    (infifo_seq_ctrl_vld && infifo_seq_ctrl_rdy && infifo_seq_eob) ? eob_cnt - 1 : eob_cnt;
  always_ff @(posedge clk)
    if (!s_rst_n) eob_cnt <= '0;
    else          eob_cnt <= eob_cntD;

  assign eob_present = eob_cnt > 0;

  always_ff @(posedge clk)
    if (!s_rst_n) in_full_throughput <= 1'b0;
    else          in_full_throughput <= (decomp_infifo_full_throughput & decomp_infifo_ctrl_vld);

  assign infifo_seq_full_throughput = eob_present | in_full_throughput;
endmodule
