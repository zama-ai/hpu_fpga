// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Instruction scheduler ack counter.
// Circumvent the axis stream limitation of ublaze. Instead of presenting it n-values in a stream,
// We will present only a value containing the number of ack.
// This value will be reset on read, on his side the microblaze is in charge of matching back ack
// with associated iop.
// NB: this isn't an issue since Sync operation couldn't be reorder
// Parameters:
//  CNT_W: Ack counter width
//
// ==============================================================================================

module isc_ack #(
  parameter int  CNT_W = 4
) (
  input  logic       clk,     // clock
  input  logic       s_rst_n, // synchronous reset

  input  logic       in_pulse,

  output logic [CNT_W-1: 0] out_cnt,
  output logic              out_vld,
  input  logic              out_rdy
);

  // ---------------------------------------------------------------------------------------------- --
  // Signals
  // ---------------------------------------------------------------------------------------------- --
  logic [  CNT_W-1:0] r_cnt, nxt_cnt;

  always_ff @(posedge clk)
  if (!s_rst_n) r_cnt <= 'h0;
  else          r_cnt <= nxt_cnt;

  assign out_vld = |(r_cnt); // (r_cnt != 0)

  assign nxt_cnt =  (out_vld & out_rdy) ? (in_pulse? 1: 0)
                   : in_pulse? r_cnt +1 : r_cnt;

  assign out_cnt = r_cnt;
  endmodule
