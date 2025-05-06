// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// FIFO using registers.
// This FIFO ensures that the output data is kept during at least DELAY cycles
// before being output.
// Ready/valid interface is used.
// in_rdy = 0 : the FIFO is full.
// out_vld = 0 : the FIFO is empty.
//
// Note: timestamp wrapping are not handled. Ensure that TIMESTAMP_W is big enough.
//
// Parameters:
//  WIDTH : data width
//  DEPTH : FIFO depth
//  DELAY : Number of cycles to keep the data before being output
//
// ==============================================================================================

module fifo_delay #(
  parameter int               WIDTH       = 8,
  parameter int               DEPTH       = 32, // Should be >= 2
  parameter int               DELAY       = 4, // Should be > 2.
  parameter int               TIMESTAMP_W = 32
) (
  input  logic             clk,     // clock
  input  logic             s_rst_n, // synchronous reset

  input  logic [WIDTH-1:0] in_data,
  input  logic             in_vld,
  output logic             in_rdy,

  output logic [WIDTH-1:0] out_data,
  output logic             out_vld,
  input  logic             out_rdy
);

// ============================================================================================== --
// localparam
// ============================================================================================== --
  generate
    if (DELAY <= 2) begin : __UNSUPPORTED_DELAY_
      $fatal(1,"> ERROR: Unsupported DELAY (%0d) value, should be > 2.", DELAY);
    end
    if (DEPTH < 2) begin : __UNSUPPORTED_DEPTH_
      $fatal(1,"> ERROR: Unsupported DEPTH (%0d) value, should be >= 2.", DEPTH);
    end
  endgenerate

// ============================================================================================== --
// timestamp
// ============================================================================================== --
  // All input data are "timestamped".
  logic [TIMESTAMP_W-1:0] timestamp;

  always_ff @(posedge clk)
    if (!s_rst_n) timestamp <= '0;
    else          timestamp <= timestamp + 1;

// ============================================================================================== --
// FIFO
// ============================================================================================== --
  logic [WIDTH-1:0]       fifo_data;
  logic [TIMESTAMP_W-1:0] fifo_timestamp;
  logic                   fifo_vld;
  logic                   fifo_rdy;

  fifo_reg #(
    .WIDTH       (WIDTH + TIMESTAMP_W),
    .DEPTH       (DEPTH-2),
    .LAT_PIPE_MH ({1'b1, 1'b1})
  ) fifo (
    .clk     (clk),
    .s_rst_n (s_rst_n),

    .in_data ({in_data,timestamp}),
    .in_vld  (in_vld),
    .in_rdy  (in_rdy),

    .out_data({fifo_data,fifo_timestamp}),
    .out_vld (fifo_vld),
    .out_rdy (fifo_rdy)
  );

// ============================================================================================== --
// Output
// ============================================================================================== --
  logic                   res_vld;
  logic                   res_rdy;
  logic [TIMESTAMP_W-1:0] res_diff;
  logic                   res_delay_ok;

  assign res_diff     = timestamp - fifo_timestamp;
  assign res_delay_ok = res_diff > DELAY - 2; // additional -1, since we count the output fifo_element.
  assign res_vld      = fifo_vld & res_delay_ok;
  assign fifo_rdy     = res_rdy  & res_delay_ok;

  fifo_element #(
    .WIDTH         (WIDTH),
    .DEPTH         (1),
    .TYPE_ARRAY    (1), // Use type 1 to put a register on the data path.
    .DO_RESET_DATA (0),
    .RESET_DATA_VAL(0) // UNUSED
  ) out_fifo_element (
    .clk    (clk),
    .s_rst_n(s_rst_n),

    .in_data(fifo_data),
    .in_vld (res_vld),
    .in_rdy (res_rdy),

    .out_data(out_data),
    .out_vld (out_vld),
    .out_rdy (out_rdy)
  );


endmodule
