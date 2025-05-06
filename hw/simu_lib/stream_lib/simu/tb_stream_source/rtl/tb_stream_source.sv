// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Test bench that checks stream_source and stream_spy.
//
// ==============================================================================================

module tb_stream_source
  import file_handler_pkg::*;
  import random_handler_pkg::*;
#();
`timescale 1ns/10ps

//import "DPI-C" function string getenv(input string env_name);

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int CLK_HALF_PERIOD = 1;
  localparam int ARST_ACTIVATION = 17;

  //  /!\ Does not work with xsim
  //localparam string PROJECT_DIR = $sformatf("%s", getenv("PROJECT_DIR"));
  //localparam string PWD = $sformatf("%s", getenv("PWD"));
  
  localparam string  FILENAME      = "input/rdata.dat";
  localparam string  FILENAME_REF  = "input/ref.dat";
  localparam string  FILENAME_WR   = "output/stream_spy.dat";
  localparam string  DATA_TYPE     = "ascii_hex";
  localparam string  DATA_TYPE_WR  = "binary";
  localparam integer DATA_W     = 16;
  localparam integer RAND_RANGE = 2**3-1;
  localparam bit     KEEP_VLD   = 1;
  localparam string  MASK_DATA  = "x"; // Support "none"; "x";"random"

  localparam integer DATA_START_NB  = 20;
  localparam integer DATA_CNT_OFS   = DATA_START_NB + 5;
  localparam integer DATA_RAND_OFS  = DATA_CNT_OFS + DATA_START_NB + 5;
  localparam integer DATA_FILE_CNT  = 50;

  localparam integer DATA_MIN = 'h10;
  localparam integer DATA_MAX = 'h1F;

// ============================================================================================== --
// class
// ============================================================================================== --
// To define some random contraints.
  class rand_d_mod #(parameter int DATA_W = DATA_W) extends random_data#(DATA_W);
    constraint data_mod {data inside {[DATA_MIN:DATA_MAX]};}
  endclass
  class rand_v_mod extends random_data#(1);
    constraint v_mod {data dist { 0 := 100, 1 := 1 };}
  endclass

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

  assign error = error_data | error_cnt | error_spy;

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
  rand_d_mod#(.DATA_W(DATA_W)) d;
  rand_v_mod v;

  stream_source #(
    .FILENAME   (FILENAME  ),
    .DATA_TYPE  (DATA_TYPE ),
    .DATA_W     (DATA_W    ),
    .RAND_RANGE (RAND_RANGE),
    .KEEP_VLD   (KEEP_VLD  ),
    .MASK_DATA  (MASK_DATA )
  ) stream_source (
    .clk     (clk    ),
    .s_rst_n (s_rst_n),

    .data    (data),
    .vld     (vld ),
    .rdy     (rdy ),

    .throughput (throughput)
  );

  stream_spy #(
    .FILENAME      (FILENAME_WR    ),
    .DATA_TYPE     (DATA_TYPE_WR   ),
    .FILENAME_REF  (FILENAME_REF   ),
    .DATA_TYPE_REF (DATA_TYPE      ),
    .DATA_W        (DATA_W         )
  ) stream_spy (
    .clk     (clk    ),
    .s_rst_n (s_rst_n),

    .data    (data),
    .vld     (vld ),
    .rdy     (rdy ),

    .error   (mismatch)
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

  integer data_cnt_ofs;

  initial begin
    bit r;
    error_cnt = 0;
    end_of_test =0;

    // Replace element in order to apply the random constraint
    d = new;
    v = new;
    stream_source.rdata.rand_data = d;
    stream_source.rand_vld = v;

    // active spy and write
    stream_spy.set_do_ref(1);
    stream_spy.set_do_write(1);

    $display("%t > ----------- OPEN counter---------------",$time);
    if (!stream_source.open("counter"))
      $error("%t > ERROR: Something went wrong when opening stream_source",$time);

    @(posedge clk)
      throughput <= RAND_RANGE;

    $display("%t > ----------- START counter---------------",$time);
    stream_source.start(DATA_START_NB);
    wait (stream_source.running);
    $display("%t > INFO: Running==1",$time);
    wait (!stream_source.running);
    $display("%t > INFO: Running==0",$time);
 
    assert(data_cnt == DATA_START_NB)
    else begin
      $display("%t > ERROR: Total number of data mismatches. exp=%0d seen=%0d",$time, DATA_START_NB, data_cnt);
      error_cnt = 1;
    end

    stream_source.start(0);
    wait(data_cnt == DATA_CNT_OFS);
    stream_source.stop;
    @(posedge clk);
    data_cnt_ofs = data_cnt; // Because stop takes 1 cycle, there may be 1 additional data that is processed.
                              // Keep this count in data_cnt_ofs.


    $display("%t > ----------- OPEN random---------------",$time);
    if (!stream_source.open("random"))
      $error("%t > ERROR: Something went wrong when opening stream_source",$time);

    @(posedge clk)
      throughput <= 0;

    $display("%t > ----------- START random---------------",$time);
    stream_source.start(DATA_START_NB);
    wait (stream_source.running);
    $display("%t > INFO: Running==1",$time);
    wait (!stream_source.running);
    $display("%t > INFO: Running==0",$time);
 
    assert(data_cnt == data_cnt_ofs + DATA_START_NB)
    else begin
      $display("%t > ERROR: Total number of data mismatches. exp=%0d seen=%0d",$time, data_cnt_ofs + DATA_START_NB, data_cnt);
      error_cnt = 1;
    end

    stream_source.start(0);
    wait(data_cnt == DATA_RAND_OFS);
    stream_source.stop;
    @(posedge clk);
    data_cnt_ofs = data_cnt; // Because stop takes 1 cycle, there may be 1 additional data that is processed.
                              // Keep this count in data_cnt_ofs.

    $display("%t > ----------- OPEN file---------------",$time);
    r = stream_source.open(FILENAME);
    r = stream_spy.open(FILENAME_WR, FILENAME_REF);

    @(posedge clk)
      throughput <= RAND_RANGE-1;

    $display("%t > ----------- START file---------------",$time);
    stream_spy.start;
    stream_source.start(0);
    wait (stream_source.running);
    $display("%t > INFO: Running==1",$time);
    wait (!stream_source.running);
    $display("%t > INFO: Running==0",$time);
    if (stream_source.eof)
      $display("%t > INFO: EOF==1",$time);

    assert(data_cnt == data_cnt_ofs + DATA_FILE_CNT)
    else begin
      $display("%t > ERROR: Total number of data mismatches. exp=%0d seen=%0d",$time, DATA_FILE_CNT+data_cnt_ofs, data_cnt);
      error_cnt = 1;
    end

    @(posedge clk)
      end_of_test = 1;
  end

  assign rdy = 1;
// ============================================================================================== --
// Check
// ============================================================================================== --
  // check counter
  always_ff @(posedge clk) begin 
    logic [DATA_W-1:0] data_ref;
    if (!s_rst_n)
      error_data <= 1'b0;
    else
      if (vld && rdy) begin
        case (stream_source.cur_file_name)
          "counter": begin
            assert(data == data_cnt)
            else begin
              $display("%t > ERROR: Data counter mismatch exp=0x%0x seen=0x%0x.",$time, data_cnt, data);
              error_data <= 1'b1;
            end
          end
          "random": begin
            assert(data >=DATA_MIN && data <= DATA_MAX)
            else begin
              $display("%t > ERROR: Data random out of expected range [0x%0x:0x%0x] seen=0x%0x.",$time, DATA_MIN, DATA_MAX, data);
              error_data <= 1'b1;
            end
          end
          default : begin
            data_ref = 'h1320 + data_cnt - data_cnt_ofs;
            assert(data == data_ref)
            else begin
              $display("%t > ERROR: Data file mismatch exp=0x%0x seen=0x%0x. (data_cnt=%0d, DATA_RAND_OFS=0x%0x)",$time, data_ref, data, data_cnt, data_cnt_ofs);
              error_data <= 1'b1;
            end
          end
        endcase
      end
  end

  always_ff @(posedge clk) begin
    if (!s_rst_n)
      error_spy <= 1'b0;
    else begin
      if (vld && rdy && stream_spy.ref_running) begin
        if (data == 'h132D || data == 'h133D)
          assert(mismatch) $display("%t > INFO: Stream_spy has correctly detected the mismatch.", $time);
          else begin
            $display("%t > ERROR: Stream_spy did not detect the mismatch.", $time);
            error_spy <= 1'b1;
          end
      end
    end
  end

endmodule
