// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Test the Arbiter with a fixed given N
// ==============================================================================================

`resetall
`timescale 1ns/10ps
module tb_arbiter;

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int CLK_HALF_PERIOD_A = 4;
  localparam int CLK_HALF_PERIOD_B = 1;
  localparam int ARST_ACTIVATION = 17;

  // Fixed for this test, we suppose three will be used, Read, Write & Notify
  localparam int N = 3;

  // =========================================================================================== --
  // clock, reset
  // =========================================================================================== --
    bit clk;

  initial begin
    clk = 1'b0;
  end

  always begin
    #CLK_HALF_PERIOD_A clk = ~clk;
  end
  bit a_rst_n; // asynchronous reset
  bit s_rstn;  // synchronous reset

  initial begin
    a_rst_n = 1'b0;                  // active reset
    #ARST_ACTIVATION a_rst_n = 1'b1; // disable reset
  end

  always_ff @(posedge clk) begin
    s_rstn <= a_rst_n;
  end

  // =========================================================================================== --
  // End of test
  // =========================================================================================== --
  bit end_of_test;

  initial begin
    wait (end_of_test);
    @(posedge clk) $display("%t > SUCCEED !", $time);
    $finish;
  end

  // =========================================================================================== --
  // Error
  // =========================================================================================== --
  bit error;

  always_ff @(posedge clk)
    if (error) begin
      $display("%t > FAILURE !", $time);
      $finish;
    end

  // =========================================================================================== --
  // input / output signals
  // =========================================================================================== --


  // =========================================================================================== --
  // Design under test instance
  // =========================================================================================== --
  logic [N-1:0] request;
  logic [N-1:0] grant;

  arbiter # (
    .N(N)
  ) arbiter (
    .clk   (clk),
    .resetn(s_rstn),

    .request    (request),
    .grant      (grant)
  );

  // =========================================================================================== --
  // Scenario
  // (a) we need to check that when we have a new request and change "request"
  //      => the corresponding granted request is valid
  // (b) we need to check that when several request are fired at the same time
  //      => the requests are granted one after the other
  // (c) we need to check that when a new request is issued and no "request" have been asked
  //      => no request have been granted
  // =========================================================================================== --
  initial begin
    request = 3'b000;
    repeat(20) @(posedge clk);

    // (a) checking normal use
    request = 3'b010;
    @(posedge clk);
    assert (grant[1] == 1) else begin
      $display("[ERROR] request 0 has not been granted");
      error = 1;
    end

    for (int i =1; i<N; i++) begin
      request = {request[0],request[N-1:1]};
      repeat(20) @(posedge clk);
      @(posedge clk);
      assert (grant[request>>1] == 1) else begin
        $display("[ERROR] request (%0d) has not been granted req %0d grant %0d", i, request, grant[request]);
        error = 1;
      end
    end

    request = 'h0;

    // (b) there is no priorisation, we can only check that there is only one bit in grant
    for (int j=0; j<150; j++) begin
      request = $urandom_range(7, 1);
      @(posedge clk);
      assert ( $countones(grant) == 1) else begin
        $display("[ERROR] grant is not only one bit!, %d", $countones(grant));
        error = 1;
      end
    end

    $display("%t > INFO: End simulation", $time);
    repeat(20) @(posedge clk);
    end_of_test = 1'b1;
  end

// ============================================================================================== --
// Tasks
// ============================================================================================== --
endmodule
