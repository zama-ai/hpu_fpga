// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Double clock FIFO wrapper
// > ALMOST_FULL_REMAIN cannot be 1. min value is 5
// ==============================================================================================

module fifo_ram_rdy_vld_2clk #(
  parameter int CDC_SYNC_STAGES  = 2,

  parameter int WIDTH              = 32,
  parameter int DEPTH              = 512,
  parameter int RAM_LATENCY        = 1,
  parameter int ALMOST_FULL_REMAIN = 5,

  parameter int OUT_FIFO_DEPTH     = 2,
  // for xpm simulation assertion
  parameter int FIFO_MEMORY_TYPE   = "auto",
  parameter int SIM_ASSERT_CHK     = 0
) (
  input  logic                        in_rstn,
  input  logic                        in_clk,
  input  logic [WIDTH-1:0]            in_data,
  input  logic                        in_vld,
  output logic                        in_rdy,
  output logic                        almost_full,

  input  logic                        out_rstn,
  input  logic                        out_clk,
  output logic [WIDTH-1:0]            out_data,
  output logic                        out_vld,
  input  logic                        out_rdy
);

  // =========================================================================================== --
  // Adaptation from read and write enable to ready-valid
  // =========================================================================================== --
  // FIFO interface
  logic             wr_en;
  logic             wr_rst_busy;

  logic             rd_en;
  logic [WIDTH-1:0] rd_data;
  logic             rd_rst_busy;
  logic             rd_data_valid;
  logic             empty;
  logic             full;

  // Temporary signals
  logic [WIDTH-1:0] tmp_data;
  logic             tmp_vld;
  logic             tmp_rdy;

  logic [WIDTH-1:0] data_kept;
  logic             data_kept_available;


  assign in_rdy = ~full;

  assign wr_en = in_vld  & ~full  & ~wr_rst_busy;
  assign rd_en = tmp_rdy & ~empty & ~rd_rst_busy;

  assign tmp_vld = rd_data_valid | data_kept_available;

  always_ff @(posedge out_clk)
    if (~tmp_rdy & rd_data_valid)
      data_kept <= rd_data;

  always_ff @(posedge out_clk) begin
    if (~out_rstn) begin
      data_kept_available <= 1'b0;
    end else begin
      if (~tmp_rdy & rd_data_valid) begin
        data_kept_available <= 1'b1;
      end else if (tmp_vld & tmp_rdy) begin
        data_kept_available <= 1'b0;
      end
    end
  end

  assign tmp_data = rd_data_valid ? rd_data : data_kept;

  // =========================================================================================== --
  // XPM MACRO
  // =========================================================================================== --
  // Notes :
  // (1) only one reset is used, the one on the input interface
  // (2) read and write rst_busy should not be negliged
  // (3) almost full on xpm fifo async is non-programmable and one clock cycle away from full.
  // here we want almost_full depending on parameter ALMOST_FULL_REMAIN. almost full = prog_full

  xpm_fifo_async_wrapper # (
    .CDC_SYNC_STAGES  (   CDC_SYNC_STAGES),

    .DATA_W           (             WIDTH),
    .FIFO_DEPTH       (             DEPTH),
    .PROG_FULL_THRESH (ALMOST_FULL_REMAIN),

    .FIFO_MEMORY_TYPE (  FIFO_MEMORY_TYPE),
    .SIM_ASSERT_CHK   (    SIM_ASSERT_CHK)
  ) xpm_fifo_async_wrapper (
    // common module port
    .sleep(  1'b0),    // Unused for now
    .rst  (~in_rstn),  // Must be synchronous to wr_clk

    // Write Domain ports
    .wr_clk       (       in_clk),
    .wr_en        (        wr_en),
    .wr_data      (      in_data),
    .full         (         full),
    .wr_data_count( /* UNUSED */),
    .wr_rst_busy  (  wr_rst_busy),
    .prog_full    (  almost_full),
    .overflow     ( /* UNUSED */),
    .almost_full  ( /* UNUSED */),
    .wr_ack       ( /* UNUSED */),

    // Read Domain ports
    .rd_clk       (      out_clk),
    .rd_en        (        rd_en),
    .rd_data      (      rd_data),
    .empty        (        empty),
    .rd_data_count( /* UNUSED */),
    .rd_rst_busy  (  rd_rst_busy),
    .data_valid   (rd_data_valid),
    .prog_empty   ( /* UNUSED */),
    .underflow    ( /* UNUSED */),
    .almost_empty ( /* UNUSED */),

    // optional arguments
    .injectsbiterr(1'b0),
    .injectdbiterr(1'b0),
    .sbiterr(/* UNUSED */),
    .dbiterr(/* UNUSED */)
  );

  // =========================================================================================== --
  // FIFO element
  // =========================================================================================== --
  fifo_element #(
    .WIDTH          (WIDTH),
    .DEPTH          (OUT_FIFO_DEPTH),
    .TYPE_ARRAY     (8'h12),
    .DO_RESET_DATA  ( 1'b0),
    .RESET_DATA_VAL (    0)
  ) fifo_element (
    .clk     (out_clk),
    .s_rst_n (out_rstn),

    .in_data (tmp_data),
    .in_vld  (tmp_vld ),
    .in_rdy  (tmp_rdy ),

    .out_data(out_data),
    .out_vld (out_vld ),
    .out_rdy (out_rdy )
  );

endmodule
