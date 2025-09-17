// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ==============================================================================================
// Description  : Simple wrapper around fifo async
// ----------------------------------------------------------------------------------------------
//
// Wrapper around the XPM FIFO ASYNC.
//
// Documentation about XPM module can be found here :
// https://docs.amd.com/r/en-US/ug974-vivado-ultrascale-libraries/XPM_FIFO_ASYNC
//
// ==============================================================================================

module xpm_fifo_async_wrapper #(
  // Synchronization stages ---------------------------------------------------------------------
  // Specifies the number of synchronization stages on the CDC path.
  // For proper operation, the input data must be sampled two or more times by destination clock.
  parameter int CDC_SYNC_STAGES  = 2,

  parameter int DATA_W            = 32,
  parameter int FIFO_DEPTH        = 512,

  // read and write data count w are the same
  parameter int DATA_COUNT_WIDTH = $clog2(FIFO_DEPTH)+1,

  // Simulation asserts flag --------------------------------------------------------------------
  parameter int SIM_ASSERT_CHK    = 0
  )(
  // Common module ports
  input  logic                        sleep,
  input  logic                        rst,

  // Write Domain ports
  input  logic                        wr_clk,
  input  logic                        wr_en,
  input  logic [DATA_W-1:0]           wr_data,
  output logic                        full,
  output logic                        prog_full,
  output logic [DATA_COUNT_WIDTH-1:0] wr_data_count,
  output logic                        overflow,
  output logic                        wr_rst_busy,
  output logic                        almost_full,
  output logic                        wr_ack,

  // Read Domain ports
  input  logic                        rd_clk,
  input  logic                        rd_en,
  output logic [DATA_W-1:0]           rd_data,
  output logic                        empty,
  output logic                        prog_empty,
  output logic [DATA_COUNT_WIDTH-1:0] rd_data_count,
  output logic                        underflow,
  output logic                        rd_rst_busy,
  output logic                        almost_empty,
  output logic                        data_valid,

  // ECC Related ports
  input  logic                        injectsbiterr,
  input  logic                        injectdbiterr,
  output logic                        sbiterr,
  output logic                        dbiterr
);

  // xpm_fifo_async: Asynchronous FIFO
  // Xilinx Parameterized Macro, version 2025.1
  xpm_fifo_async #(
    .CASCADE_HEIGHT     (0),                // DECIMAL
    .CDC_SYNC_STAGES    (CDC_SYNC_STAGES),  // DECIMAL
    .DOUT_RESET_VALUE   ("0"),              // String
    .ECC_MODE           ("no_ecc"),         // String
    .EN_SIM_ASSERT_ERR  ("warning"),        // String
    .FIFO_MEMORY_TYPE   ("auto"),           // String
    .FIFO_READ_LATENCY  (1),                // DECIMAL
    .FIFO_WRITE_DEPTH   (FIFO_DEPTH),       // DECIMAL
    .FULL_RESET_VALUE   (0),                // DECIMAL
    .PROG_EMPTY_THRESH  (10),               // DECIMAL
    .PROG_FULL_THRESH   (10),               // DECIMAL
    .RD_DATA_COUNT_WIDTH(DATA_COUNT_WIDTH), // DECIMAL
    .READ_DATA_WIDTH    (DATA_W),           // DECIMAL
    .READ_MODE          ("std"),            // String
    .RELATED_CLOCKS     (0),                // DECIMAL
    .SIM_ASSERT_CHK     (SIM_ASSERT_CHK),   // DECIMAL; 0=disable simulation messages, 1=enable simulation messages
    .USE_ADV_FEATURES   ("1707"),           // String
    .WAKEUP_TIME        (0),                // DECIMAL
    .WRITE_DATA_WIDTH   (DATA_W),           // DECIMAL
    .WR_DATA_COUNT_WIDTH(DATA_COUNT_WIDTH)  // DECIMAL
  ) xpm_fifo_async (
    .almost_empty (almost_empty),
    .almost_full  (almost_full),
    .data_valid   (data_valid),
    .dbiterr      (dbiterr),
    .dout         (rd_data),
    .empty        (empty),
    .full         (full),
    .overflow     (overflow),
    .prog_empty   (prog_empty),
    .prog_full    (prog_full),
    .rd_data_count(rd_data_count),
    .rd_rst_busy  (rd_rst_busy),
    .sbiterr      (sbiterr),
    .underflow    (underflow),
    .wr_ack       (wr_ack),
    .wr_data_count(wr_data_count),
    .wr_rst_busy  (wr_rst_busy),
    .din          (wr_data),
    .injectdbiterr(injectdbiterr),
    .injectsbiterr(injectsbiterr),
    .rd_clk       (rd_clk),
    .rd_en        (rd_en),
    .rst          (rst),
    .sleep        (sleep),
    .wr_clk       (wr_clk),
    .wr_en        (wr_en)
  );

endmodule
