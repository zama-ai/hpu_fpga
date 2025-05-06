// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Test bench that checks stream_source and stream_sink.
//
// ==============================================================================================

module tb_stream_sink;
`timescale 1ns/10ps

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam CLK_HALF_PERIOD = 1;
  localparam ARST_ACTIVATION = 17;

  localparam string  FILENAME     = "input/rdata.dat";
  localparam string  FILENAME_REF = "input/ref.dat";
  localparam string  FILENAME_WR  = "output/stream_spy.dat";
  localparam string  DATA_TYPE      = "ascii_hex";
  localparam string  DATA_TYPE_REF  = "binary";
  localparam string  DATA_TYPE_WR   = "ascii_bin";
  localparam integer DATA_W     = 16;
  localparam integer RAND_RANGE = 2**3-1;
  localparam bit     KEEP_RDY   = 1;

  localparam integer DATA_START_NB  = 20;
  localparam integer DATA_FILE_OFS  = 50;

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
  bit error_data;
  bit error_cnt;
  bit error_spy;
  bit error_rdy;

  assign error = error_data | error_cnt | error_spy | error_rdy;

  always_ff @(posedge clk)
    if (error) begin
      $display("%t > FAILURE !", $time);
      $finish;
    end

// ============================================================================================== --
// input / output signals
// ============================================================================================== --
  logic [DATA_W-1:0] data;
  logic              vld;
  logic              rdy;
  logic [$clog2(RAND_RANGE)-1:0] throughput;
  logic              mismatch;

// ============================================================================================== --
// Design under test instance
// ============================================================================================== --
  stream_source #(
    .FILENAME   (FILENAME  ),
    .DATA_TYPE  (DATA_TYPE ),
    .DATA_W     (DATA_W    ),
    .RAND_RANGE (RAND_RANGE),
    .KEEP_VLD   (1),
    .MASK_DATA  ("none")
  ) stream_source (
    .clk     (clk    ),
    .s_rst_n (s_rst_n),

    .data    (data),
    .vld     (vld ),
    .rdy     (rdy ),

    .throughput (RAND_RANGE)
  );

  stream_sink #(
    .FILENAME      (FILENAME_WR   ),
    .DATA_TYPE     (DATA_TYPE_WR  ),
    .FILENAME_REF  (FILENAME_REF  ),
    .DATA_TYPE_REF (DATA_TYPE_REF ),
    .DATA_W        (DATA_W      ),
    .RAND_RANGE    (RAND_RANGE  ),
    .KEEP_RDY      (KEEP_RDY    )
  ) stream_sink (
    .clk     (clk    ),
    .s_rst_n (s_rst_n),

    .data    (data),
    .vld     (vld ),
    .rdy     (rdy ),

    .error   (mismatch),
    .throughput (throughput)
  );

// ============================================================================================== --
// Scenario
// ============================================================================================== --
  logic [DATA_W-1:0] data_cnt;

  always_ff @(posedge clk)
    if (!s_rst_n)
      data_cnt <= '0;
    else
      if (vld && rdy)
        data_cnt <= data_cnt + 1;

  initial begin
    bit r;
    error_cnt <= 0;
    error_rdy <= 0;

    // active spy and write
    stream_sink.set_do_ref(1);
    stream_sink.set_do_write(1);

    if (!stream_source.open(FILENAME))
      $error("%t > ERROR: Something went wrong when opening stream_source",$time);
    if (!stream_sink.open(FILENAME_REF, FILENAME_WR))
      $error("%t > ERROR: Something went wrong when opening stream_sink",$time);

    @(posedge clk)
      throughput <= RAND_RANGE;

    stream_sink.start(DATA_START_NB);
    stream_source.start(0);
    wait (stream_sink.running);
    $display("%t > INFO: Sink Running==1",$time);
    wait (!stream_sink.running);
    $display("%t > INFO: Sink Running==0",$time);

    assert(data_cnt == DATA_START_NB)
    else begin
      $display("%t > ERROR: Total number of data mismatches. exp=%0d seen=%0d",$time, DATA_START_NB, data_cnt);
      error_cnt = 1;
    end

    // Check ready
    repeat(100) begin
      @(posedge clk);
      assert(rdy == 0)
      else begin
        $display("%t > ERROR: rdy not equal to 0 when not running.", $time);
        error_rdy <= 1;
      end
    end

    @(posedge clk)
      throughput <= 2;

    stream_sink.start(0);
    wait (stream_source.running);
    $display("%t > INFO: Source Running==1",$time);
    wait (!stream_source.running);
    $display("%t > INFO: Source Running==0",$time);

    assert(data_cnt == DATA_FILE_OFS)
    else begin
      $display("%t > ERROR: Total number of data mismatches. exp=%0d seen=%0d",$time, DATA_FILE_OFS, data_cnt);
      error_cnt <= 1;
    end

    stream_sink.close;

    @(posedge clk)
      end_of_test = 1;
  end

// ============================================================================================== --
// Check
// ============================================================================================== --
  always_ff @(posedge clk) begin
    if (!s_rst_n)
      error_spy <= 1'b0;
    else begin
      if (vld && rdy && stream_sink.running) begin
        if (data == 'h132D || data == 'h133D)
          assert(mismatch)
          else begin
            $display("%t > ERROR: Stream_spy did not detect the mismatch.", $time);
            error_spy <= 1'b1;
          end
      end
    end
  end

endmodule
