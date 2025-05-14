// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : This is the explicit title of the testbench module
// ----------------------------------------------------------------------------------------------
//
// More details on the test bench scenario.
//
// Describe the steps the test bench goes through:
//  1. First step
//  2. Second step
//  3. Third step
//     Elaborate if needed
//  4. Fourth step
//
// ==============================================================================================

module tb_stream_to_seq;
  `timescale 1ns/10ps

// ============================================================================================== --
// parameter
// ============================================================================================== --
  parameter int WIDTH = 8;
  parameter int IN_NB = 8;
  parameter int SEQ   = 4;

  parameter int SAMPLE_NB = 10_000;

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int CLK_HALF_PERIOD = 1;
  localparam int ARST_ACTIVATION = 17;

  localparam int RAND_RANGE = 128;

// ============================================================================================== --
// clock, reset
// ============================================================================================== --
  bit clk;
  bit a_rst_n; // asynchronous reset
  bit s_rst_n; // synchronous reset

  initial begin
    clk     = 1'b0;
    a_rst_n = 1'b0;                   // active reset
    #ARST_ACTIVATION a_rst_n = 1'b1; // disable reset
  end

  always begin
    #CLK_HALF_PERIOD clk = ~clk;
  end

  always_ff @(posedge clk) begin
    s_rst_n <= a_rst_n;
  end

// ============================================================================================== --
// End of test
// ============================================================================================== --
  bit end_of_test;

  initial begin
    wait (end_of_test);
    @(posedge clk) $display("%t > SUCCEED !", $time);
    $finish;
  end

// ============================================================================================== --
// Error
// ============================================================================================== --
  bit error;

  always_ff @(posedge clk)
    if (error) begin
      $display("%t > FAILURE !", $time);
      $finish;
    end

// ============================================================================================== --
// input / output signals
// ============================================================================================== --
  logic [IN_NB-1:0][WIDTH-1:0] in_data;
  logic                        in_vld;
  logic                        in_rdy;

  logic [IN_NB-1:0][WIDTH-1:0] out_data;
  logic [IN_NB-1:0]            out_vld;
  logic [IN_NB-1:0]            out_rdy;

// ============================================================================================== --
// Design under test instance
// ============================================================================================== --
  stream_to_seq #(
    .WIDTH (WIDTH),
    .IN_NB (IN_NB),
    .SEQ   (SEQ)
  ) dut (
    .clk      (clk    ),
    .s_rst_n  (s_rst_n),

    .in_data  (in_data),
    .in_vld   (in_vld),
    .in_rdy   (in_rdy),

    .out_data (out_data),
    .out_vld  (out_vld),
    .out_rdy  (out_rdy)
  );

// ============================================================================================== --
// Scenario
// ============================================================================================== --
  stream_source
  #(
    .FILENAME   ("random"),
    .DATA_TYPE  ("ascii_hex"),
    .DATA_W     (IN_NB*WIDTH),
    .RAND_RANGE (RAND_RANGE),
    .KEEP_VLD   (1'b0),
    .MASK_DATA  ("x")
  ) stream_source (
      .clk       (clk),
      .s_rst_n   (s_rst_n),

      .data      (in_data),
      .vld       (in_vld),
      .rdy       (in_rdy),

      .throughput(0)
  );

  logic out_rdy_tmp;
  logic [SEQ-1:0] sr_out_rdy;
  logic [SEQ-1:0] sr_out_rdyD;
  stream_sink
  #(
    .FILENAME   (""),
    .DATA_TYPE  ("ascii_hex"),
    .DATA_W     (1),
    .RAND_RANGE (RAND_RANGE)
  ) stream_sink (
      .clk       (clk),
      .s_rst_n   (s_rst_n),

      .data      (),
      .vld       (out_vld[0]),
      .rdy       (out_rdy_tmp),
      .error     (/*UNUSED*/),
      .throughput(0)
  );

  assign sr_out_rdyD[0] = out_rdy_tmp & out_vld[0];
  generate
    if (SEQ > 1) begin
      assign sr_out_rdyD[SEQ-1:1] = sr_out_rdy[SEQ-2:0];
    end
  endgenerate

  always_ff @(posedge clk)
    if (!s_rst_n) sr_out_rdy <= '0;
    else          sr_out_rdy <= sr_out_rdyD;

  always_comb begin
    out_rdy[0*IN_NB/SEQ+:IN_NB/SEQ] = {IN_NB/SEQ{out_rdy_tmp}};
    for (int s=1; s<SEQ; s=s+1)
      out_rdy[s*IN_NB/SEQ+:IN_NB/SEQ] = {IN_NB/SEQ{sr_out_rdyD[s]}};
  end




  // Keep data in queues
  logic [WIDTH-1:0] ref_q[IN_NB-1:1][$];

  always_ff @(posedge clk)
    if (in_vld && in_rdy)
      for (int i=1; i<IN_NB-1; i=i+1) begin
        ref_q[i].push_back(in_data[i]);
      end


  // Check data
  always_ff @(posedge clk)
    if (!s_rst_n)
      error <= 1'b0;
    else begin
      for (int i=1; i<IN_NB-1; i=i+1) begin
        if (out_vld[i] && out_rdy[i]) begin
          logic [WIDTH-1:0] ref_d;
          ref_d = ref_q[i].pop_front();
          assert(out_data[i] == ref_d)
          else begin
            $display("%t > ERROR: Mismatch [%0d] exp=0x%0x seen=0x%0x", $time, i, ref_d, out_data[i]);
            error <= 1'b1;
          end
        end
      end
      for (int s=1; s<SEQ; s=s+1) begin
        for (int i=0; i<IN_NB/SEQ; i=i+1) begin
          if (out_rdy[s*IN_NB/SEQ+i]) begin
            assert(out_vld[s*IN_NB/SEQ+i])
            else begin
              $display("%t > ERROR: Data not valid as expected [%0d]", $time, s*IN_NB/SEQ+i);
              error <= 1'b1;
            end
          end
        end
      end
    end

// ============================================================================================== --
// Control
// ============================================================================================== --
  initial begin
    int tmp;
    end_of_test = 1'b0;

    tmp = stream_sink.open();
    stream_sink.start(0);

    tmp = stream_source.open();
    stream_source.start(SAMPLE_NB);

    wait (stream_source.running);
    wait (!stream_source.running);

    end_of_test = 1'b1;
  end

endmodule
