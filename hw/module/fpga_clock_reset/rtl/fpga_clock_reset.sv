// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Generic FPGA clock and reset conditioning module
// ==============================================================================================
// The main idea here is to give setup and hold margin to resets. To that effect, the clock will be
// stopped while the reset changes state. This will only help if you set a multi cycle path onto the
// reset signal, so don't forget that. For example:
//
//     set rst_pin [get_pins -hier -regexp {clk_rst/rst_ff.*/C}]
//     set_multicycle_path $SETUP_MARGIN -setup -from $rst_pin
//     set_multicycle_path [expr 2*$HOLD_MARGIN-1] -hold -from $rst_pin
//
// You also need a maximum delay constraint to the clock gate enable input, because the clock gate
// input is synchronized with a three stage synchronizer. This means that the actual time of the
// clock going off/on is uncertain, so a max_delay constraint here makes the corner case known:
//
//     set_max_delay [expr $CE_MARGIN * period] -to [get_pins clk_rst/clock_gate/CE]
//
// There should only be a single module in the whole design. If you replicate this block for every SLR
// make sure each SLR gets out of reset at the same time. Still, this was designed to have margin to
// spare.
//
// Note that you'll now need to hold the reset low for HOLD_MARGIN + SETUP_MARGIN + CE_MARGIN extra
// cycles to reset the design, not counting with the number of cycles you already needed before.
// At FPGA startup the module comes out with the reset asserted and the clock gate on, so it is
// guaranteed that the whole design will see some reset cycles at startup.

(* keep_hierarchy = "yes" *)
module fpga_clock_reset #(
  parameter int unsigned HOLD_MARGIN  = 5, // Make sure to exagerate here, There's no point in
                                           // making synthesis struggle with something unimportant.
  parameter int unsigned SETUP_MARGIN = 5, // Make sure to exagerate here
  parameter int unsigned CE_MARGIN    = 5, // The maximum latency allowed from clock enable flop to clock gate

  parameter bit          RST_POL         = 1'b0, // Active low = 0 or high = 1
  parameter int unsigned INTER_PART_PIPE = 3,    // Latency to the next part
  parameter int unsigned INTRA_PART_PIPE = 3     // Latency to this part
) (
  input  logic clk_in,
  input  logic rst_in,

  output logic rst_nxt,
  output logic clk_en,
  output logic rst_out
);
  // --------------------------------------------------------------------------
  // Local parameters
  // --------------------------------------------------------------------------
  localparam int unsigned CE_MIN_DELAY   = 4;
  localparam int unsigned CE_MAX_DELAY   = CE_MIN_DELAY + CE_MARGIN;
  localparam int unsigned CE_UNCERTAINTY = CE_MAX_DELAY - CE_MIN_DELAY;

  // Hold is special, in that the last edge is always the previous.
  localparam int unsigned HOLD_TIME  = HOLD_MARGIN - 1 + CE_UNCERTAINTY;
  localparam int unsigned SETUP_TIME = HOLD_TIME + SETUP_MARGIN + CE_UNCERTAINTY;
  localparam int unsigned COUNTER_W  = $clog2(SETUP_TIME);

  localparam int unsigned HOLD_VAL  = HOLD_TIME - 1 < 0 ? 0 : (HOLD_TIME - 1);
  localparam int unsigned SETUP_VAL = SETUP_TIME - 1 < 0 ? 0 : (SETUP_TIME - 1);

  // --------------------------------------------------------------------------
  // Reset distribution
  // --------------------------------------------------------------------------

  logic rst_dist;
  fpga_reset_dist #(
    .RST_POL         ( RST_POL         ) ,
    .INTER_PART_PIPE ( INTER_PART_PIPE ) ,
    .INTRA_PART_PIPE ( INTRA_PART_PIPE )
  ) reset_dist (
    .clk     ( clk_in   ) ,
    .rst_in  ( rst_in   ) ,
    .rst_nxt ( rst_nxt  ) ,
    .rst_out ( rst_dist )
  );

  // --------------------------------------------------------------------------
  // State registers
  // --------------------------------------------------------------------------
  // The initial state is important. We'll come out initialized with the output
  // reset asserted and ready to receive a new change.
  logic [CE_MIN_DELAY-1:0] rst;
  logic rst_ff;
  logic next_rst;
  logic [COUNTER_W-1:0] counter;

  // For FPGA only
  initial begin
    next_rst = 1'b0;
    rst      = '0;
    rst_ff   = 1'b0;
    clk_en   = 1'b1;
    counter  = COUNTER_W'(SETUP_VAL);
  end

  // --------------------------------------------------------------------------
  // Counter
  // --------------------------------------------------------------------------
  logic trigger;

  always @(posedge clk_in) begin
    if(trigger) begin
      counter <= '0;
    end else if(counter < COUNTER_W'(SETUP_VAL)) begin
      counter <= counter + COUNTER_W'(1'b1);
    end
  end

  // --------------------------------------------------------------------------
  // Counter comparators
  // --------------------------------------------------------------------------
  logic hold_done;
  logic setup_done;

  assign hold_done  = counter == COUNTER_W'(HOLD_VAL);
  assign setup_done = counter == COUNTER_W'(SETUP_VAL);
  assign trigger    = (setup_done && next_rst != rst_dist);

  // --------------------------------------------------------------------------
  // State logic
  // --------------------------------------------------------------------------
  // Trigger starts the whole sequence, setup_done ends the sequence
  // Note: All flops are not always_ff, to be able to set their initial value
  always @(posedge clk_in) begin
    clk_en <= setup_done && !trigger;
  end

  always @(posedge clk_in) begin
    if(trigger)
      next_rst <= rst_dist;
  end

  always @(posedge clk_in) begin
    if(hold_done)
      rst[0] <= next_rst;
  end

  // --------------------------------------------------------------------------
  // Output flops and buffers
  // --------------------------------------------------------------------------
  // The rst flop just balances the latency of the BUFGCE
  generate if (CE_MIN_DELAY > 1) begin: with_delay
    always @(posedge clk_in) begin
      rst[CE_MIN_DELAY-1:1] <= rst[CE_MIN_DELAY-2:0];
    end
  end endgenerate

  always @(posedge clk_in) begin
    rst_ff <= rst[CE_MIN_DELAY-1];
  end

  BUFG_FABRIC reset_buffer (
    .I ( rst_ff  ) ,
    .O ( rst_out )
  );

endmodule
