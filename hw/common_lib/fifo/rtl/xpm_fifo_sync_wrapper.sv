// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Wrapper for Xilinx XPM_FIFO_SYNC.
// ==============================================================================================

module xpm_fifo_sync_wrapper #(
  parameter int WIDTH             = 32,
  parameter int DEPTH             = 256,
  parameter int FULL_RESET_VALUE  = 0,
  parameter int PROG_EMPTY_THRESH = 3,  // Supported range : 3 - 253
  parameter int PROG_FULL_THRESH  = 100,
  parameter int FIFO_READ_LATENCY = 1,
  parameter int COUNTER_W         = 1   // Size of counters that counts the total number of data
                                        // read or written.
)
(
  input clk,                 // clock
  input s_rst_n,             // synchronous reset
  output rd_rst_busy,        // 1-bit output: Read Reset Busy: Active-High indicator that the FIFO read
                             // domain is currently in a reset state.
  output wr_rst_busy,        // 1-bit output: Write Reset Busy: Active-High indicator that the FIFO
                             // write domain is currently in a reset state.
   input sleep,              // 1-bit input: Dynamic power saving- If sleep is High, the memory/fifo
                             // block is in power saving mode.

  // Data in
  input wr_en,               // 1-bit input: Write Enable: If the FIFO is not full, asserting this
                             // signal causes data (on din) to be written to the FIFO Must be held
                             // active-low when rst or wr_rst_busy or rd_rst_busy is active high.
  output wr_ack,             // 1-bit output: Write Acknowledge: This signal indicates that a write
                             // request (wr_en) during the prior clock cycle is succeeded.
  input[WIDTH-1:0] din,     // WRITE_DATA_WIDTH-bit input: Write Data: The input data bus used when
                             // writing the FIFO.

  // Data out
  input rd_en,               // 1-bit input: Read Enable: If the FIFO is not empty, asserting this
                             // signal causes data (on dout) to be read from the FIFO. Must be held
                             // active-low when rd_rst_busy is active high.
  output data_valid,         // 1-bit output: Read Data Valid: When asserted, this signal indicates
                             // that valid data is available on the output bus (dout).
  output [WIDTH-1:0] dout,  // READ_DATA_WIDTH-bit output: Read Data: The output data bus is driven
                             // when reading the FIFO.

  // Control
  output empty,              // 1-bit output: Empty Flag: When asserted, this signal indicates that the
                             // FIFO is empty. Read requests are ignored when the FIFO is empty,
                             // initiating a read while empty is not destructive to the FIFO.
  output full,               // 1-bit output: Full Flag: When asserted, this signal indicates that the
                             // FIFO is full. Write requests are ignored when the FIFO is full,
                             // initiating a write when the FIFO is full is not destructive to the
                             // contents of the FIFO.
  // Info
  output almost_empty,       // 1-bit output: Almost Empty : When asserted, this signal indicates that
                             // only one more read can be performed before the FIFO goes to empty.
  output almost_full,        // 1-bit output: Almost Full: When asserted, this signal indicates that
                             // only one more write can be performed before the FIFO is full.
  output prog_empty,         // 1-bit output: Programmable Empty: This signal is asserted when the
                             // number of words in the FIFO is less than or equal to the programmable
                             // empty threshold value. It is de-asserted when the number of words in
                             // the FIFO exceeds the programmable empty threshold value.
  output prog_full,          // 1-bit output: Programmable Full: This signal is asserted when the
                             // number of words in the FIFO is greater than or equal to the
                             // programmable full threshold value. It is de-asserted when the number of
                             // words in the FIFO is less than the programmable full threshold value.
  output [COUNTER_W-1:0] rd_data_count, // RD_DATA_COUNT_WIDTH-bit output: Read Data Count: This bus indicates the
                                        // number of words read from the FIFO.
  output [COUNTER_W-1:0] wr_data_count, // WR_DATA_COUNT_WIDTH-bit output: Write Data Count: This bus indicates
                                        // the number of words written into the FIFO.

  // Error
  output overflow,           // 1-bit output: Overflow: This signal indicates that a write request
                             // (wren) during the prior clock cycle was rejected, because the FIFO is
                             // full. Overflowing the FIFO is not destructive to the contents of the
                             // FIFO.
  output underflow           // 1-bit output: Underflow: Indicates that the read request (rd_en) during
                             // the previous clock cycle was rejected because the FIFO is empty. Under
                             // flowing the FIFO is not destructive to the FIFO.


);

// ============================================================================================== --
// Signals
// ============================================================================================== --
  logic s_rst;

  assign s_rst = ~s_rst_n;

  //== Unused signals
  // Do not use ECC
  logic dbiterr;
  logic sbiterr;
  logic injectdbiterr;
  logic injectsbiterr;

  assign injectdbiterr = 1'b0;
  assign injectsbiterr = 1'b0;

// ============================================================================================== --
// xpm_fifo_sync instance
// ============================================================================================== --

//** code **//
// xpm_fifo_sync: Synchronous FIFO
// Xilinx Parameterized Macro, version 2018.1
xpm_fifo_sync #(
   .DOUT_RESET_VALUE("0"),    // String
   .ECC_MODE("no_ecc"),       // String
   .FIFO_MEMORY_TYPE("auto"), // String
   .FIFO_READ_LATENCY(FIFO_READ_LATENCY),     // DECIMAL
   .FIFO_WRITE_DEPTH(DEPTH),   // DECIMAL
   .FULL_RESET_VALUE(FULL_RESET_VALUE),      // DECIMAL
   .PROG_EMPTY_THRESH(PROG_EMPTY_THRESH),     // DECIMAL
   .PROG_FULL_THRESH(PROG_FULL_THRESH),      // DECIMAL
   .RD_DATA_COUNT_WIDTH(COUNTER_W),   // DECIMAL
   .READ_DATA_WIDTH(WIDTH),      // DECIMAL
   .READ_MODE("std"),         // String
   .USE_ADV_FEATURES("0707"), // String
   .WAKEUP_TIME(0),           // DECIMAL
   .WRITE_DATA_WIDTH(WIDTH),     // DECIMAL
   .WR_DATA_COUNT_WIDTH(COUNTER_W)    // DECIMAL
)
xpm_fifo_sync_inst (
   .almost_empty(almost_empty),   // 1-bit output: Almost Empty : When asserted, this signal indicates that
                                  // only one more read can be performed before the FIFO goes to empty.

   .almost_full(almost_full),     // 1-bit output: Almost Full: When asserted, this signal indicates that
                                  // only one more write can be performed before the FIFO is full.

   .data_valid(data_valid),       // 1-bit output: Read Data Valid: When asserted, this signal indicates
                                  // that valid data is available on the output bus (dout).

   .dbiterr(dbiterr),             // 1-bit output: Double Bit Error: Indicates that the ECC decoder detected
                                  // a double-bit error and data in the FIFO core is corrupted.

   .dout(dout),                   // READ_DATA_WIDTH-bit output: Read Data: The output data bus is driven
                                  // when reading the FIFO.

   .empty(empty),                 // 1-bit output: Empty Flag: When asserted, this signal indicates that the
                                  // FIFO is empty. Read requests are ignored when the FIFO is empty,
                                  // initiating a read while empty is not destructive to the FIFO.

   .full(full),                   // 1-bit output: Full Flag: When asserted, this signal indicates that the
                                  // FIFO is full. Write requests are ignored when the FIFO is full,
                                  // initiating a write when the FIFO is full is not destructive to the
                                  // contents of the FIFO.

   .overflow(overflow),           // 1-bit output: Overflow: This signal indicates that a write request
                                  // (wren) during the prior clock cycle was rejected, because the FIFO is
                                  // full. Overflowing the FIFO is not destructive to the contents of the
                                  // FIFO.

   .prog_empty(prog_empty),       // 1-bit output: Programmable Empty: This signal is asserted when the
                                  // number of words in the FIFO is less than or equal to the programmable
                                  // empty threshold value. It is de-asserted when the number of words in
                                  // the FIFO exceeds the programmable empty threshold value.

   .prog_full(prog_full),         // 1-bit output: Programmable Full: This signal is asserted when the
                                  // number of words in the FIFO is greater than or equal to the
                                  // programmable full threshold value. It is de-asserted when the number of
                                  // words in the FIFO is less than the programmable full threshold value.

   .rd_data_count(rd_data_count), // RD_DATA_COUNT_WIDTH-bit output: Read Data Count: This bus indicates the
                                  // number of words read from the FIFO.

   .rd_rst_busy(rd_rst_busy),     // 1-bit output: Read Reset Busy: Active-High indicator that the FIFO read
                                  // domain is currently in a reset state.

   .sbiterr(sbiterr),             // 1-bit output: Single Bit Error: Indicates that the ECC decoder detected
                                  // and fixed a single-bit error.

   .underflow(underflow),         // 1-bit output: Underflow: Indicates that the read request (rd_en) during
                                  // the previous clock cycle was rejected because the FIFO is empty. Under
                                  // flowing the FIFO is not destructive to the FIFO.

   .wr_ack(wr_ack),               // 1-bit output: Write Acknowledge: This signal indicates that a write
                                  // request (wr_en) during the prior clock cycle is succeeded.

   .wr_data_count(wr_data_count), // WR_DATA_COUNT_WIDTH-bit output: Write Data Count: This bus indicates
                                  // the number of words written into the FIFO.

   .wr_rst_busy(wr_rst_busy),     // 1-bit output: Write Reset Busy: Active-High indicator that the FIFO
                                  // write domain is currently in a reset state.

   .din(din),                     // WRITE_DATA_WIDTH-bit input: Write Data: The input data bus used when
                                  // writing the FIFO.

   .injectdbiterr(injectdbiterr), // 1-bit input: Double Bit Error Injection: Injects a double bit error if
                                  // the ECC feature is used on block RAMs or UltraRAM macros.

   .injectsbiterr(injectsbiterr), // 1-bit input: Single Bit Error Injection: Injects a single bit error if
                                  // the ECC feature is used on block RAMs or UltraRAM macros.

   .rd_en(rd_en),                 // 1-bit input: Read Enable: If the FIFO is not empty, asserting this
                                  // signal causes data (on dout) to be read from the FIFO. Must be held
                                  // active-low when rd_rst_busy is active high. .

   .rst(s_rst),                   // 1-bit input: Reset: Must be synchronous to wr_clk. Must be applied only
                                  // when wr_clk is stable and free-running.

   .sleep(sleep),                 // 1-bit input: Dynamic power saving- If sleep is High, the memory/fifo
                                  // block is in power saving mode.

   .wr_clk(clk),                  // 1-bit input: Write clock: Used for write operation. wr_clk must be a
                                  // free running clock.

   .wr_en(wr_en)                  // 1-bit input: Write Enable: If the FIFO is not full, asserting this
                                  // signal causes data (on din) to be written to the FIFO Must be held
                                  // active-low when rst or wr_rst_busy or rd_rst_busy is active high

);

// End of xpm_fifo_sync_inst instantiation
endmodule
