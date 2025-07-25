// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : A small testbench around the fpga_clock_reset block
// ==============================================================================================

`timescale 1ns/1ps

module tb_fpga_clock_reset;
  // ----------------------------------------------------------------------------------------------
  // Parameters
  // ----------------------------------------------------------------------------------------------
  parameter int unsigned STIMULUS     = 10;
  parameter int unsigned HOLD_MARGIN  = 4;
  parameter int unsigned SETUP_MARGIN = 4;
  parameter int unsigned CE_MARGIN    = 4;
  parameter int unsigned MAX_RESET_TIME = 100;
  parameter int unsigned MIN_RESET_TIME = 10;
  parameter int unsigned MAX_RUN_TIME   = 100;
  parameter int unsigned MIN_RUN_TIME   = 10;

  localparam realtime CLK_HALF_PERIOD = 2.5/2;

  // ----------------------------------------------------------------------------------------------
  // Signals
  // ----------------------------------------------------------------------------------------------
  logic clk_in;
  logic rst_in;
  logic clk_en;
  logic rst_out;
  logic clk_out;

  // ----------------------------------------------------------------------------------------------
  // Stimulus
  // ----------------------------------------------------------------------------------------------
  initial begin
    int unsigned reset_time;
    int unsigned run_time;

    rst_in = 1'b0;
    clk_in = 1'b0;

    #100; // Wait for the global reset time

    for (int unsigned i = 0; i < STIMULUS; i++) begin
      void'(std::randomize(reset_time) with {reset_time > MIN_RESET_TIME && reset_time < MAX_RESET_TIME;});
      void'(std::randomize(run_time) with {run_time > MIN_RESET_TIME && run_time < MAX_RESET_TIME;});

      #(run_time) @(posedge clk_in)
        rst_in <= 1'b0;
      #(reset_time) @(posedge clk_in)
        rst_in <= 1'b1;

      wait(rst_out && clk_out);
    end

    $display("> SUCCEED !");
    $finish();
  end

  always begin
    #(CLK_HALF_PERIOD) clk_in = ~clk_in;
  end

  realtime last_clk_out_edge = 0.0;
  realtime last_reset_edge = 0.0;

  always @(posedge clk_out) last_clk_out_edge = $realtime();
  always @(rst_out)         last_reset_edge = $realtime();

  always @(rst_out) begin
    int unsigned cycles;
    cycles = ($realtime() - last_clk_out_edge) / (2*CLK_HALF_PERIOD);
    assert($realtime() == 0.0 || (cycles >= HOLD_MARGIN)) else begin
      $fatal(1, "Error> %0d cycles do not meet the hold time requirements of %0d cycles.",
        cycles, HOLD_MARGIN);
    end
  end

  always @(posedge clk_out) begin
    int unsigned cycles;
    cycles = ($realtime() - last_reset_edge) / (2*CLK_HALF_PERIOD);
    assert($realtime() == 0.0 || (cycles >= SETUP_MARGIN+CE_MARGIN)) else begin
      $fatal(1, "Error> %0d cycles do not meet the setup time requirements of %0d cycles.",
        cycles, SETUP_MARGIN);
    end
  end

  // ----------------------------------------------------------------------------------------------
  // DUT
  // ----------------------------------------------------------------------------------------------
  fpga_clock_reset #(
    .HOLD_MARGIN  ( HOLD_MARGIN  ) ,
    .SETUP_MARGIN ( SETUP_MARGIN ) ,
    .CE_MARGIN    ( CE_MARGIN    )
  ) dut (
    .clk_in  ( clk_in     ) ,
    .rst_in  ( rst_in     ) ,
    .rst_nxt ( /*Unused*/ ) ,
    .clk_en  ( clk_en     ) ,
    .rst_out ( rst_out    )
  );

  BUFGCE #(
    .CE_TYPE    ( "HARDSYNC"   ) ,
    .SIM_DEVICE ( "VERSAL_HBM" )
  ) clock_gate (
    .CE ( clk_en  ) ,
    .I  ( clk_in  ) ,
    .O  ( clk_out )
  );
endmodule
