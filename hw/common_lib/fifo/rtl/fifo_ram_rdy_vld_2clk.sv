// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Double clock FIFO wrapper
//
// ==============================================================================================

module fifo_ram_rdy_vld_2clk #(
  parameter int CDC_SYNC_STAGES  = 2,

  parameter int WIDTH            = 32,
  parameter int DEPTH            = 512,
  // read and write data count w are the same
  parameter int DATA_COUNT_WIDTH = $clog2(DEPTH)+1,

  // for xpm simulation assertion
  parameter int FIFO_MEMORY_TYPE = "auto",
  parameter int SIM_ASSERT_CHK   = 0
) (
  // Write Domain ports
  input  logic                        wr_rstn,
  input  logic                        wr_clk,
  input  logic                        wr_en,
  input  logic [WIDTH-1:0]            wr_data,
  output logic                        full,
  output logic [DATA_COUNT_WIDTH-1:0] wr_data_count,
  output logic                        wr_rst_busy,

  // Read Domain ports
  input  logic                        rd_rstn,
  input  logic                        rd_clk,
  input  logic                        rd_en,
  output logic [WIDTH-1:0]            rd_data,
  output logic                        empty,
  output logic [DATA_COUNT_WIDTH-1:0] rd_data_count,
  output logic                        rd_rst_busy,
  output logic                        data_valid
);
  // =========================================================================================== --
  // XPM MACRO
  // =========================================================================================== --
  xpm_fifo_async_wrapper # (
    .CDC_SYNC_STAGES  (CDC_SYNC_STAGES),

    .DATA_W           (WIDTH),
    .FIFO_DEPTH       (DEPTH),
    .DATA_COUNT_WIDTH (DATA_COUNT_WIDTH),

    .FIFO_MEMORY_TYPE (FIFO_MEMORY_TYPE),
    .SIM_ASSERT_CHK   (SIM_ASSERT_CHK)
  ) xpm_fifo_async_wrapper (
    // common module port
    .sleep(  1'b0),    // Unused for now
    .rst  (~wr_rstn),  // Must be synchronous to wr_clk

    // Write Domain ports
    .wr_clk       (       wr_clk),
    .wr_en        (        wr_en),
    .wr_data      (      wr_data),
    .full         (         full),
    .wr_data_count(wr_data_count),
    .wr_rst_busy  (  wr_rst_busy),
    .prog_full    ( /* UNUSED */),
    .overflow     ( /* UNUSED */),
    .almost_full  ( /* UNUSED */),
    .wr_ack       ( /* UNUSED */),

    // Read Domain ports
    .rd_clk       (       rd_clk),
    .rd_en        (        rd_en),
    .rd_data      (      rd_data),
    .empty        (        empty),
    .rd_data_count(rd_data_count),
    .rd_rst_busy  (  rd_rst_busy),
    .data_valid   (   data_valid),
    .prog_empty   ( /* UNUSED */),
    .underflow    ( /* UNUSED */),
    .almost_empty ( /* UNUSED */),

    // optional arguments
    .injectsbiterr(1'b0),
    .injectdbiterr(1'b0),
    .sbiterr(/* UNUSED */),
    .dbiterr(/* UNUSED */)
  );

endmodule
