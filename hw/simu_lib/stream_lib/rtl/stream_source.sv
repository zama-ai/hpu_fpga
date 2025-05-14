// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Module that reads from a file.
// Outputs the data through a rdy/vld interface.
//
// Parameters
//   FILENAME : file where to read.
//     Supports : "counter" : output data is a counter
//                "random"  : output data are random
//                ""        : default input file : <instance_name>_source .dat
// ----------------------------------------------------------------------------------------------
//    DATA_TYPE: File data format :
//                "binary"
//                "ascii_hex", "ascii_bin" : 1 data per line. In this format, comment lines and
//                                           comment at the end of line are supported
//                                           (starts with #).
//
//    DATA_W   : Data width
//    RAND_RANGE : when random is used, gives the range in which to consider "throughput" signal.
//    KEEP_VLD : (1) ; when vld=1, and rdy=0, the valid is maintained to 1.
//    MASK_DATA : data value when vld = 0. Supports "none" (next data), "x" and "random"
// ==============================================================================================

module stream_source
  import file_handler_pkg::*;
  import random_handler_pkg::*;
#(
  parameter string  FILENAME   = "",
  parameter string  DATA_TYPE  = "ascii_hex", // Support "ascii_bin", "binary"
  parameter integer DATA_W     = 16,
  parameter integer RAND_RANGE = 2**32-1,
  parameter bit     KEEP_VLD   = 0,
  parameter string  MASK_DATA  = "none" // Support "none", "x","random"
)
(
    input               clk,        // clock
    input               s_rst_n,    // synchronous reset

    output [DATA_W-1:0] data,
    output              vld,
    input               rdy,

    input [$clog2(RAND_RANGE+1)-1:0] throughput // 0 : random vld
                                            // RAND_RANGE : 100% (vld = 1)
                                            // ]0..RAND_RANGE[ : throughput/RAND_RANGE
);

// ============================================================================================== --
// localparam
// ============================================================================================== --
    typedef enum {ACT_GET_CUR         ,
                  ACT_GET_NEXT        ,
                  ACT_GET_NEXT_FORCE_0,
                  ACT_GET_NEXT_FORCE_1
                  } action_e;

// ============================================================================================== --
// Internal variables
// ============================================================================================== --
  logic                      eof;
  string                     cur_file_name;
  bit                        running;
  bit                        suspend_running;

  logic [DATA_W-1:0]         data_tmp;
  bit                        vld_ctrl;
  bit                        keep_vld_mask;

  integer                    sample_cnt_max;
  integer                    sample_cnt;

  event                      start_event;


// ============================================================================================== --
// read_data
// ============================================================================================== --
  read_data #(.DATA_W(DATA_W))     rdata    = new(.filename(FILENAME), .data_type(DATA_TYPE));
  random_data #(.DATA_W(1))        rand_vld = new(0);

// ============================================================================================== --
// Functions
// ============================================================================================== --
  function static bit get_vld(input action_e action);
    bit v;
    logic [$clog2(RAND_RANGE+1)-1:0] t;
    t = throughput;
    case (action)
      ACT_GET_CUR         :
        v = vld_ctrl;
      ACT_GET_NEXT        :
        case (throughput)
          0:
            begin
              if (!rand_vld.randomize()) begin
                $display("%t > ERROR: randomization of rand_vld", $time);
                $finish;
              end
              v = rand_vld.get_data;
            end
          default:
            begin
              if (!rand_vld.randomize() with {rand_vld.data dist { 0 := RAND_RANGE-t, 1 := t }; }) begin
                $display("%t > ERROR: randomization of rand_vld", $time);
                $finish;
              end
              v = rand_vld.get_data;
            end
        endcase
      ACT_GET_NEXT_FORCE_0:
        v = 0;
      ACT_GET_NEXT_FORCE_1:
        v = 1;
    endcase
    return v;
  endfunction

// ============================================================================================== --
// Tasks / Functions
// ============================================================================================== --
//--------------------------------------
// open
//--------------------------------------
  function int open (input string name = FILENAME);
    int r;
    cur_file_name   = name;
    eof             = 0;

    r = rdata.open(cur_file_name, DATA_TYPE);
    if (!r) begin
      eof = 1;
      $display("%t > ERROR: %m opening file %0s failed\n", $time, cur_file_name);
      $finish;
    end

    return r;
  endfunction

//--------------------------------------
// start
//--------------------------------------
  task start (input integer count);
    rdata.start;
    -> start_event;
    @(posedge clk) begin
      sample_cnt_max <= count;
      eof <= rdata.eof;
      prepare_next_data_and_valid(ACT_GET_CUR, ACT_GET_NEXT);
    end
  endtask

//--------------------------------------
// stop
//--------------------------------------
  task stop ();
    if (!running)
      $display ("%t > WARNING: %m stopped but was not running\n", $time);
    else begin
      @(posedge clk) begin
        eof <= 1;
        suspend_running <= 1;
      end
    end
  endtask


//--------------------------------------
// prepare_next_data_and_valid
//--------------------------------------
// Set value in data and vld.
  task prepare_next_data_and_valid(input action_e act_data, input action_e act_vld);
    if (act_data == ACT_GET_NEXT) begin
      data_tmp <= rdata.get_next_data;
      eof <= rdata.eof;
    end
    else
      data_tmp <= rdata.get_cur_data;
    vld_ctrl <= get_vld(act_vld);
  endtask // prepare_next_data_and_valid

// ============================================================================================== --
// Process
// ============================================================================================== --
// -----------------------------
// Control
// -----------------------------
  bit start_pulse;

  initial begin
    start_pulse     <= 1'b0;
    suspend_running <= 1'b1;
    forever begin
      wait(start_event.triggered);
      @(posedge clk)
        start_pulse <= 1'b1;
      @(posedge clk) begin
        start_pulse     <= 1'b0;
        suspend_running <= 1'b0;
      end
    end
  end

  always_ff @(posedge clk)
    if (!s_rst_n || start_pulse)
      sample_cnt <= 0;
    else if (vld && rdy)
        sample_cnt <= sample_cnt + 1;

  assign running = ((sample_cnt_max == 0) || (sample_cnt < sample_cnt_max))
                   & ~eof & ~suspend_running;

// -----------------------------
// data / vld
// -----------------------------
  initial begin
    vld_ctrl = 1'b0;
    data_tmp = 'x;
    wait (s_rst_n);
    while (1) begin
      @(posedge clk) begin
        if (rdy && vld)
          prepare_next_data_and_valid(ACT_GET_NEXT,ACT_GET_NEXT);
        else if (!vld_ctrl) // regenerate a vld
          prepare_next_data_and_valid(ACT_GET_CUR,ACT_GET_NEXT);
      end
    end
  end




  always_ff @(posedge clk)
    if (KEEP_VLD)
      keep_vld_mask <= 1'b1;
    else
      if ((vld && rdy) || !vld_ctrl) // do not mask when prepare is setting a new vld value.
        keep_vld_mask <= 1'b1;
      else if ((vld && !rdy) || !keep_vld_mask)
        keep_vld_mask <= $urandom_range(1);

  assign vld  = vld_ctrl & running & keep_vld_mask & s_rst_n;
  assign data = (MASK_DATA == "none" || vld) ? data_tmp:
                (MASK_DATA == "random")      ? {<<{~data_tmp}}: // Put some randomness
                'x; // MASK_DATA == "x"

endmodule
