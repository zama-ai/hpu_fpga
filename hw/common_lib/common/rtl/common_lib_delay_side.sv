// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : common_lib_delay_side
// ----------------------------------------------------------------------------------------------
//
// Module used to delay input side signa and avail.
// The purpose is to make the code of module that needs to delay signals clearer.
// Parameters :
//  LATENCY       : Number of cycles used for the delay.
//  SIDE_W        : Side signal width. Set to (0) if not used.
//  RST_SIDE      : [0] (1) Reset side value to 0. Set to (0) if not used.
//                  [1] (1) Reset side value to 1. Set to (0) if not used.
//                  Value 2'b11 is not supported.
//
// ==============================================================================================

module common_lib_delay_side #(
  parameter int   LATENCY    = 2,
  parameter int   SIDE_W     = 0,
  parameter [1:0] RST_SIDE   = {1'b0, 1'b0}
)
(
    input  logic                       clk,        // clock
    input  logic                       s_rst_n,    // synchronous reset

    input  logic                       in_avail,   // Control signal
    output logic                       out_avail,

    input  logic [SIDE_W-1:0]          in_side,
    output logic [SIDE_W-1:0]          out_side
);

// ============================================================================================== //
// Check parameter
// ============================================================================================== //
  generate
    if (RST_SIDE == 2'b11) begin : __UNSUPPORTED_RST_SIDE__
      initial begin
        assert(RST_SIDE != 2'b11)
        else begin
          $display("%t > ERROR: Unsupported RST_SIDE value for common_lib_delay_side.", $time);
          $finish;
        end
      end
    end
  endgenerate

// ============================================================================================== //
// Delay line
// ============================================================================================== //
// -- Delay line. Will be infered by synthesizer as cycles usable in the multiplication computation.
  generate
    //----------------- LATENCY = 0 -----------------------
    if (LATENCY == 0) begin
      assign out_avail = in_avail;
      assign out_side  = in_side;
    end // LATENCY == 0
    else begin : gen_latency
      logic [LATENCY-1:0]                      avail_dly;
      logic [LATENCY-1:0][SIDE_W-1:0]          side_dly;

    //----------------- LATENCY = 1 -----------------------
      if (LATENCY == 1) begin
        always_ff @(posedge clk)
          if (!s_rst_n) avail_dly    <= '0;
          else          avail_dly[0] <= in_avail;

        if (SIDE_W > 0) begin
          if (RST_SIDE != 0) begin
            always_ff @(posedge clk)
              if (!s_rst_n) side_dly    <= RST_SIDE[0] ? '0 : '1;
              else          side_dly[0] <= in_side;
          end
          else begin
            always_ff @(posedge clk)
              side_dly[0] <= in_side;
          end
        end // SIDE_W > 0
        else begin
          assign side_dly = 'x;
        end

      end // LATENCY == 1
    //----------------- LATENCY > 1 -----------------------
      else begin // LATENCY > 1
        always_ff @(posedge clk)
          if (!s_rst_n)
            avail_dly <= '0;
          else begin
            avail_dly[0]           <= in_avail;
            avail_dly[LATENCY-1:1] <= avail_dly[LATENCY-2:0];
          end

        if (SIDE_W > 0) begin
          if (RST_SIDE != 0) begin
            always_ff @(posedge clk)
              if (!s_rst_n)
                side_dly <= RST_SIDE[0] ? '0 : '1;
              else begin
                side_dly[0]           <= in_side;
                side_dly[LATENCY-1:1] <= side_dly[LATENCY-2:0];
              end
          end
          else begin
            always_ff @(posedge clk) begin
              side_dly[0]           <= in_side;
              side_dly[LATENCY-1:1] <= side_dly[LATENCY-2:0];
            end
          end // no RST_SIDE
        end // SIDE_W > 0
        else begin
          assign side_dly = 'x;
        end
      end // LATENCY > 1

      assign out_avail = avail_dly[LATENCY-1];
      assign out_side  = side_dly[LATENCY-1];

    end // gen_latency
  endgenerate
endmodule
