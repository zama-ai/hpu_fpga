// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
// Bench to test stream_to_pipe.
// ==============================================================================================

module tb_stream_to_pipe;
`timescale 1ns/10ps

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int CLK_HALF_PERIOD = 1;
  localparam int ARST_ACTIVATION = 17;

  parameter int WIDTH    = 32;
  parameter bit OUT_PIPE = 1'b1;
  parameter int IN_NB    = 4;
  parameter [IN_NB-1:0][31:0] DESYNC = {32'd6, 32'd0, 32'd2, 32'd1}; // The maximum desync is DEPTH
  parameter int DEPTH    = max_desync(DESYNC) + 1;

  parameter int SAMPLE_NB = 100_000;

  localparam int RAND_RANGE = 128;

  function [31:0] max_desync  (input [IN_NB-1:0][31:0] D);
    var [31:0] tmp;
    tmp = D[0];
    for (int i=0; i<IN_NB; i=i+1)
      tmp = tmp > D[i] ? tmp : D[i];
    return tmp;
  endfunction

// ============================================================================================== --
// clock, reset
// ============================================================================================== --
  bit clk;
  bit a_rst_n; // asynchronous reset
  bit s_rst_n; // synchronous reset

  initial begin
    clk     = 1'b0;
    a_rst_n = 1'b0;                  // active reset
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
  bit error_overflow;
  bit error_data;

  assign error = error_overflow
                | error_data;

  always_ff @(posedge clk)
    if (error) begin
      $display("%t > FAILURE !", $time);
      $finish;
    end

// ============================================================================================== --
// input / output signals
// ============================================================================================== --
  logic [IN_NB-1:0][WIDTH-1:0] in_data;
  logic [IN_NB-1:0]            in_vld;
  logic [IN_NB-1:0]            in_rdy;

  logic [IN_NB*WIDTH-1:0]      out_data;
  logic                        out_avail;

  logic                        error_full;

// ============================================================================================== --
// Design under test instance
// ============================================================================================== --
  stream_to_pipe #(
    .WIDTH   (WIDTH),
    .DEPTH   (DEPTH),
    .IN_NB   (IN_NB)
  ) dut (
    .clk       (clk    ),
    .s_rst_n   (s_rst_n),

    .in_data   (in_data),
    .in_vld    (in_vld),
    .in_rdy    (in_rdy),

    .out_data  (out_data),
    .out_avail (out_avail),

    .error_full(error_full)
  );

// ============================================================================================== --
// Scenario
// ============================================================================================== --
//-------------------------
// stream source
//-------------------------
// Input data are coming from the same source.
// The CDC desynchronizes them. The maximum desync is DEPTH
  logic [IN_NB-1:0][WIDTH-1:0] in_data_tmp;
  logic                        in_vld_tmp;
  logic                        in_rdy_tmp;
  logic [IN_NB-1:0]            in_rdy_tmp_a;

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

      .data      (in_data_tmp),
      .vld       (in_vld_tmp),
      .rdy       (1'b1),

      .throughput(0)
  );

  generate
    for (genvar gen_i=0; gen_i<IN_NB; gen_i=gen_i+1) begin : gen_loop
      localparam LOCAL_DESYNC = (DESYNC[gen_i] != 0) ? DESYNC[gen_i] : 4;
      fifo_element #(
        .WIDTH          (WIDTH),
        .DEPTH          (DESYNC[gen_i]),
        .TYPE_ARRAY     ({LOCAL_DESYNC{4'h1}}),
        .DO_RESET_DATA  (1'b0),
        .RESET_DATA_VAL ('0)
      ) fifo_element (
        .clk       (clk),
        .s_rst_n   (s_rst_n),

        .in_data   (in_data_tmp[gen_i]),
        .in_vld    (in_vld_tmp),
        .in_rdy    (in_rdy_tmp_a[gen_i]),

        .out_data  (in_data[gen_i]),
        .out_vld   (in_vld[gen_i]),
        .out_rdy   (in_rdy[gen_i])
      );
    end
  endgenerate

//-------------------------
// start stream
//-------------------------
  initial begin
    int tmp;
    end_of_test = 1'b0;

    tmp = stream_source.open();
    stream_source.start(SAMPLE_NB);

    wait (stream_source.running);
    wait (!stream_source.running);

    end_of_test = 1'b1;
  end

//-------------------------
// Check data
//-------------------------
  logic [IN_NB-1:0][WIDTH-1:0] ref_q[$];

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else if (in_vld_tmp)
      ref_q.push_back(in_data_tmp);

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      error_data <= 1'b0;
    end
    else if (out_avail) begin
      var [IN_NB-1:0][WIDTH-1:0] ref_data;
      ref_data = ref_q.pop_front();
      if (ref_data != out_data) begin
        error_data <= 1'b1;
        $display("%t > ERROR: Data mismatch. exp=0x%0x seen=0x%0x.", $time, ref_data, out_data);
      end
    end

  assign error_overflow = error_full;

endmodule

