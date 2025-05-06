// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Event counter.
// Buffer event occurence and expose a rdy/vld interface to handle them at a custom pace
// Ready/valid interface is used.
// out_vld = 0 : Event counter is empty.
//
// Parameters:
//  CNT_W: Event counter width
//
// ==============================================================================================

module isc_evt #(
  parameter int  CNT_W = 4
) (
  input              clk,     // clock
  input              s_rst_n, // synchronous reset

  input              in_evt,
  output             out_vld,
  input              out_rdy
);

  // ---------------------------------------------------------------------------------------------- --
  // Signals
  // ---------------------------------------------------------------------------------------------- --
  logic [  CNT_W-1:0] r_evt, nxt_evt;
  logic               evt_rdy;

  always_ff @(posedge clk)
  if (!s_rst_n) r_evt <= '0;
  else          r_evt <= nxt_evt;

  assign evt_rdy = |(r_evt); // (r_evt != 0)

  assign nxt_evt =  in_evt & !(evt_rdy & out_rdy) ? r_evt +1
                 : !in_evt &  (evt_rdy & out_rdy) ? r_evt -1
                   : r_evt;
  assign out_vld = evt_rdy;
  endmodule
