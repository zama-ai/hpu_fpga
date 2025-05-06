// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
//  Description  :
// ----------------------------------------------------------------------------------------------
//
//  This module is the FIFO on the ntt_acc path. The FIFO is necessary when the process is fast, and
//  therefore the monomult is still reading data for a given batch while the first results of this
//  batch are available/
//  If BYPASS = 1: Use a fifo_element.
//
//  Duplicate the ready valid path to ease the P&R.
// ----------------------------------------------------------------------------------------------
// `include "ntt_core_common_macro_inc.sv"
// ==============================================================================================

module pep_mmacc_infifo
  import param_tfhe_pkg::*;
  import pep_common_param_pkg::*;
#(
  parameter  int OP_W        = 32,
  parameter  int R           = 8, // Butterfly Radix
  parameter  int PSI         = 8, // Number of butterflies
  parameter  int RAM_LATENCY = 1,
  parameter  int DEPTH       = 1024,
  parameter  bit BYPASS      = 1'b0
) (
  input  logic                                clk,     // clock
  input  logic                                s_rst_n, // synchronous reset

  // Data from ntt
  input  logic [PSI-1:0][R-1:0][OP_W-1:0]     ntt_acc_data,
  input  logic                                ntt_acc_sob,
  input  logic                                ntt_acc_eob,
  input  logic                                ntt_acc_sol,
  input  logic                                ntt_acc_eol,
  input  logic                                ntt_acc_sog,
  input  logic                                ntt_acc_eog,
  input  logic [BPBS_ID_W-1:0]                ntt_acc_pbs_id,
  input  logic                                ntt_acc_avail,

  // Data to accumulator
  output logic [PSI-1:0][R-1:0][OP_W-1:0]     infifo_acc_data,
  output logic                                infifo_acc_sob,
  output logic                                infifo_acc_eob,
  output logic                                infifo_acc_sol,
  output logic                                infifo_acc_eol,
  output logic                                infifo_acc_sog,
  output logic                                infifo_acc_eog,
  output logic [BPBS_ID_W-1:0]                infifo_acc_pbs_id,
  output logic                                infifo_acc_avail,

  // Control
  // Do not use direct rdy/vld flow control to ease P&R
  output logic                                infifo_acc_data_inc,
  input  logic                                infifo_acc_data_sample,

  output logic                                error // FIFO overflow error
);

// ============================================================================================== --
// Localparam
// ============================================================================================== --
  localparam int INFIFO_LAT = 1; // fifo_rdy_vld latency

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
} ctrl_t;

localparam int CTRL_W = $bits(ctrl_t);

// ============================================================================================== --
// mmacc_infifo
// ============================================================================================== --
  // ---------------------------------------------------------------------------------------------- --
  // FIFO instance : Data
  // ---------------------------------------------------------------------------------------------- --
  logic [PSI-1:0][R-1:0][OP_W-1:0]     interm_acc_data;
  logic [PSI-1:0][R-1:0]               interm_acc_data_vld;
  logic [PSI-1:0][R-1:0]               interm_acc_data_rdy;

  ctrl_t                               interm_acc_ctrl;
  logic                                interm_acc_ctrl_vld;
  logic                                interm_acc_ctrl_rdy;

  ctrl_t                               ntt_acc_ctrl;
  ctrl_t                               infifo_acc_ctrl;

  // ---------------------------------------------------------------------------------------------- --
  // Rename
  // ---------------------------------------------------------------------------------------------- --
  assign ntt_acc_ctrl.sob     = ntt_acc_sob   ;
  assign ntt_acc_ctrl.eob     = ntt_acc_eob   ;
  assign ntt_acc_ctrl.sol     = ntt_acc_sol   ;
  assign ntt_acc_ctrl.eol     = ntt_acc_eol   ;
  assign ntt_acc_ctrl.sog     = ntt_acc_sog   ;
  assign ntt_acc_ctrl.eog     = ntt_acc_eog   ;
  assign ntt_acc_ctrl.pbs_id  = ntt_acc_pbs_id;

  assign infifo_acc_sob       = infifo_acc_ctrl.sob   ;
  assign infifo_acc_eob       = infifo_acc_ctrl.eob   ;
  assign infifo_acc_sol       = infifo_acc_ctrl.sol   ;
  assign infifo_acc_eol       = infifo_acc_ctrl.eol   ;
  assign infifo_acc_sog       = infifo_acc_ctrl.sog   ;
  assign infifo_acc_eog       = infifo_acc_ctrl.eog   ;
  assign infifo_acc_pbs_id    = infifo_acc_ctrl.pbs_id;

  // ---------------------------------------------------------------------------------------------- --
  // FIFO instance : Data
  // ---------------------------------------------------------------------------------------------- --
  logic [PSI-1:0][R-1:0] ntt_acc_data_vld;
  logic [PSI-1:0][R-1:0] ntt_acc_data_rdy;
  logic [PSI-1:0][R-1:0] ntt_acc_data_error;
  logic [PSI-1:0][R-1:0] ntt_acc_data_error_dly;
  logic                  error_data;
  logic                  error_dataD;

  assign ntt_acc_data_vld   = {PSI*R{ntt_acc_avail}};
  assign ntt_acc_data_error = ntt_acc_data_vld & ~ntt_acc_data_rdy;
  assign error_dataD        = |ntt_acc_data_error_dly;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      error_data             <= 1'b0;
      ntt_acc_data_error_dly <= '0;
    end
    else begin
      error_data             <= error_dataD;
      ntt_acc_data_error_dly <= ntt_acc_data_error;
    end

  generate
    for (genvar gen_p=0; gen_p<PSI; gen_p=gen_p+1) begin : gen_psi_loop
      for (genvar gen_r=0; gen_r<R; gen_r=gen_r+1) begin : gen_r_loop
        if (BYPASS == 1'b1) begin : gen_bypass
          assign interm_acc_data[gen_p][gen_r]      = ntt_acc_data[gen_p][gen_r];
          assign interm_acc_data_vld[gen_p][gen_r]  = ntt_acc_data_vld[gen_p][gen_r];
          assign ntt_acc_data_rdy[gen_p][gen_r]     = interm_acc_data_rdy[gen_p][gen_r];
        end
        else begin : gen_fifo
          fifo_ram_rdy_vld #(
            .WIDTH         (OP_W),
            .DEPTH         (DEPTH),
            .RAM_LATENCY   (RAM_LATENCY),
            .ALMOST_FULL_REMAIN (0) // UNUSED
          ) fifo_data (
            .clk     (clk),
            .s_rst_n (s_rst_n),

            .in_data (ntt_acc_data[gen_p][gen_r]),
            .in_vld  (ntt_acc_data_vld[gen_p][gen_r]),
            .in_rdy  (ntt_acc_data_rdy[gen_p][gen_r]),

            .out_data(interm_acc_data[gen_p][gen_r]),
            .out_vld (interm_acc_data_vld[gen_p][gen_r]),
            .out_rdy (interm_acc_data_rdy[gen_p][gen_r]),

            .almost_full() // UNUSED
          );
        end
      end
    end
  endgenerate

  // ---------------------------------------------------------------------------------------------- --
  // FIFO instance : Control
  // ---------------------------------------------------------------------------------------------- --
  logic ntt_acc_ctrl_vld;
  logic ntt_acc_ctrl_rdy;
  logic ntt_acc_ctrl_error;
  logic error_ctrl;

  assign ntt_acc_ctrl_vld   = ntt_acc_avail;
  assign ntt_acc_ctrl_error = ntt_acc_ctrl_vld & ~ntt_acc_ctrl_rdy;

  always_ff @(posedge clk)
    if (!s_rst_n) error_ctrl <= 1'b0;
    else          error_ctrl <= ntt_acc_ctrl_error;

  generate
    if (BYPASS == 1'b1) begin : gen_bypass
      assign interm_acc_ctrl     = ntt_acc_ctrl;
      assign interm_acc_ctrl_vld = ntt_acc_ctrl_vld;
      assign ntt_acc_ctrl_rdy    = interm_acc_ctrl_rdy;

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

        .in_data(ntt_acc_ctrl),
        .in_vld (ntt_acc_ctrl_vld),
        .in_rdy (ntt_acc_ctrl_rdy),

        .out_data(interm_acc_ctrl),
        .out_vld (interm_acc_ctrl_vld),
        .out_rdy (interm_acc_ctrl_rdy),

        .almost_full() // UNUSED
      );
    end
  endgenerate

  // ---------------------------------------------------------------------------------------------- --
  // Sample
  // ---------------------------------------------------------------------------------------------- --
  logic [INFIFO_LAT-1:0] data_inc_sr;
  logic [INFIFO_LAT-1:0] data_inc_srD;
  logic                  infifo_acc_data_incD;

  assign data_inc_srD[0] = ntt_acc_avail;
  generate
    if (INFIFO_LAT > 1) begin : gen_infifo_lat_gt_1
      assign data_inc_srD[INFIFO_LAT-1:1] = data_inc_sr[INFIFO_LAT-2:0];
    end
  endgenerate

  assign infifo_acc_data_incD = data_inc_sr[INFIFO_LAT-1];

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      data_inc_sr         <= '0;
      infifo_acc_data_inc <= 1'b0;
    end
    else begin
      data_inc_sr         <= data_inc_srD;
      infifo_acc_data_inc <= infifo_acc_data_incD;
    end
// pragma translate_off
  logic _check_latency;
  logic _check_latencyD;

  assign _check_latencyD = infifo_acc_data_incD ? 1'b0 : _check_latency;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      _check_latency <= 1'b1;
    end
    else begin
      _check_latency <= _check_latencyD;
      if (_check_latency) begin
        assert(infifo_acc_data_incD == interm_acc_ctrl_vld)
        else begin
          $fatal(1,"%t > ERROR: data_inc and vld are not synchronized.", $time);
        end
      end
    end
// pragma translate_on

  logic data_sample;

  // Input pipe
  always_ff @(posedge clk)
    if (!s_rst_n) data_sample <= 1'b0;
    else          data_sample <= infifo_acc_data_sample;

  assign interm_acc_ctrl_rdy = data_sample;
  assign interm_acc_data_rdy = {R*PSI{interm_acc_ctrl_rdy}};

  // ---------------------------------------------------------------------------------------------- --
  // Output pipe
  // ---------------------------------------------------------------------------------------------- --
  logic [PSI-1:0][R-1:0][OP_W-1:0] infifo_acc_dataD;
  ctrl_t                           infifo_acc_ctrlD;
  logic                            infifo_acc_availD;

  assign infifo_acc_dataD   = interm_acc_data;
  assign infifo_acc_ctrlD   = interm_acc_ctrl;
  assign infifo_acc_availD  = interm_acc_ctrl_vld & interm_acc_ctrl_rdy;

  // Do not increase this number of pipes without reviewing the
  //shift register depth in pep_mmacc_acc.
  always_ff @(posedge clk)
    if (!s_rst_n) infifo_acc_avail <= 1'b0;
    else          infifo_acc_avail <= infifo_acc_availD;

  always_ff @(posedge clk) begin
    infifo_acc_data   <= infifo_acc_dataD;
    infifo_acc_ctrl   <= infifo_acc_ctrlD;
  end

  // ---------------------------------------------------------------------------------------------- --
  // Error
  // ---------------------------------------------------------------------------------------------- --
  logic errorD;

  assign errorD = error_ctrl | error_data;

  always_ff @(posedge clk)
    if (!s_rst_n) error <= 1'b0;
    else          error <= errorD;

endmodule
