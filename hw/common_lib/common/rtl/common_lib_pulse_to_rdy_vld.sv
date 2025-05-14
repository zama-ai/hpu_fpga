// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module samples a pulse, and exposes it through a rdy/vld interface.
// An internal FIFO is implemented to keep track if several pulses are seen.
// An error is triggered, if the FIFO is overflown.
// ==============================================================================================

module common_lib_pulse_to_rdy_vld
#(
  parameter int FIFO_DEPTH = 8 // Should be at least 1
)
(
  input  logic clk,        // clock
  input  logic s_rst_n,    // synchronous reset

  input  logic in_pulse,

  output logic out_vld,
  input  logic out_rdy,

  output logic error
);

// ============================================================================================== //
// Input FIFO
// ============================================================================================== //
  logic in_vld;
  logic in_rdy;

  assign in_vld = in_pulse;

  generate
    if (FIFO_DEPTH < 0) begin : __UNSUPPORTED_FIFO_DEPTH
      $fatal(1,"> ERROR: Unsupported FIFO_DEPTH : should be >= 1.");
    end
    else if (FIFO_DEPTH == 1) begin : gen_fifo_depth_1
      fifo_element #(
        .WIDTH          (1),
        .DEPTH          (1),
        .TYPE_ARRAY     (4'h1),
        .DO_RESET_DATA  (1'b0),
        .RESET_DATA_VAL (0)
      ) fifo_element (
        .clk     (clk),
        .s_rst_n (s_rst_n),

        .in_data (1'b1), /*UNUSED*/
        .in_vld  (in_vld),
        .in_rdy  (in_rdy),

        .out_data(/*UNUSED*/),
        .out_vld (out_vld),
        .out_rdy (out_rdy)
      );
    end
    else if (FIFO_DEPTH == 2) begin : gen_fifo_depth_2
      fifo_element #(
        .WIDTH          (1),
        .DEPTH          (2),
        .TYPE_ARRAY     (8'h12),
        .DO_RESET_DATA  (1'b0),
        .RESET_DATA_VAL (0)
      ) fifo_element (
        .clk     (clk),
        .s_rst_n (s_rst_n),

        .in_data (1'b1), /*UNUSED*/
        .in_vld  (in_vld),
        .in_rdy  (in_rdy),

        .out_data(/*UNUSED*/),
        .out_vld (out_vld),
        .out_rdy (out_rdy)
      );
    end
    else begin : gen_fifo_depth_gt1
      fifo_reg #(
        .WIDTH          (1),
        .DEPTH          (FIFO_DEPTH),
        .LAT_PIPE_MH    ({1'b1, 1'b1})
      ) fifo_reg (
        .clk     (clk),
        .s_rst_n (s_rst_n),

        .in_data (1'b1), /*UNUSED*/
        .in_vld  (in_vld),
        .in_rdy  (in_rdy),

        .out_data(/*UNUSED*/),
        .out_vld (out_vld),
        .out_rdy (out_rdy)
      );
    end
  endgenerate


// ============================================================================================== //
// Error
// ============================================================================================== //
  logic errorD;

  assign errorD = in_vld & ~in_rdy;

  always_ff @(posedge clk)
    if (!s_rst_n) error <= 1'b0;
    else          error <= errorD;

endmodule
