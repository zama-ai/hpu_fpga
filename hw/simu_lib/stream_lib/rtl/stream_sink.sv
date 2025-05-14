// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Module that:
//   reads from a file for the reference.
//   writes in another file.
// Inputs the data through a rdy/vld interface.
//
// Parameters
//    FILENAME_REF : reference file where to read for the checking.
//    FILENAME     : file where to write.
//    DATA_TYPE_REF: reference file data format :
//    DATA_TYPE    : write file data format :
//                "binary"
//                "ascii_hex", "ascii_bin" : 1 data per line.
//
//    DATA_W   : Data width
//    RAND_RANGE : when random is used for the ready, gives the range in which to consider "throughput" signal.
//    KEEP_RDY : (1) ; when rdy=1, and vld=0, the ready is maintained to 1.
// ==============================================================================================

module stream_sink
  import file_handler_pkg::*;
  import random_handler_pkg::*;
#(
  parameter string  FILENAME_REF   = "",
  parameter string  FILENAME       = "",
  parameter string  DATA_TYPE_REF  = "ascii_hex", // Support "ascii_bin", "binary"
  parameter string  DATA_TYPE      = "ascii_hex", // Support "ascii_bin", "binary"
  parameter integer DATA_W         = 16,
  parameter integer RAND_RANGE     = 2**32-1,
  parameter bit     KEEP_RDY       = 0
)
(
    input               clk,        // clock
    input               s_rst_n,    // synchronous reset

    input [DATA_W-1:0]  data,
    input               vld,
    output              rdy,

    output              error,
    input [$clog2(RAND_RANGE+1)-1:0] throughput // 0 : random rdy
                                            // RAND_RANGE : 100% (rdy = 1)
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
  bit                        running;
  bit                        eof;

  bit                        rdy_ctrl;
  bit                        keep_rdy_mask;

  integer                    sample_cnt_max;
  integer                    sample_cnt;

  event                      start_event;


// ============================================================================================== --
// random_data
// ============================================================================================== --
  random_data #(.DATA_W(1))        rand_rdy = new(0);

// ============================================================================================== --
// Stream spy instance
// ============================================================================================== --
  stream_spy
  #(
    .FILENAME      (FILENAME),
    .DATA_TYPE     (DATA_TYPE),
    .FILENAME_REF  (FILENAME_REF),
    .DATA_TYPE_REF (DATA_TYPE_REF),
    .DATA_W        (DATA_W)
  )
  stream_spy
  (
      .clk     (clk),
      .s_rst_n (s_rst_n),

      .data    (data),
      .vld     (vld),
      .rdy     (rdy),

      .error   (error)
  );

// ============================================================================================== --
// Functions
// ============================================================================================== --
  function static bit get_rdy(input action_e action);
    bit v;
    logic [$clog2(RAND_RANGE+1)-1:0] t;
    t = throughput;
    case (action)
      ACT_GET_CUR         :
        v = rdy_ctrl;
      ACT_GET_NEXT        :
        case (throughput)
          0:
            begin
              if (!rand_rdy.randomize()) begin
                $display("%t > ERROR: randomization of rand_rdy", $time);
                $finish;
              end
              v = rand_rdy.get_data;
            end
          default:
            begin
              if (!rand_rdy.randomize() with {rand_rdy.data dist { 0 := RAND_RANGE-t, 1 := t }; }) begin
                $display("%t > ERROR: randomization of rand_rdy", $time);
                $finish;
              end
              v = rand_rdy.get_data;
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
// set_do_write
//--------------------------------------
  function void set_do_write(input bit v);
    stream_spy.do_write = v;
  endfunction

//--------------------------------------
// set_do_ref
//--------------------------------------
  function void set_do_ref(input bit v);
    stream_spy.do_ref = v;
  endfunction

//--------------------------------------
// open
//--------------------------------------
  function int open (input string name_ref = FILENAME_REF, input string name = FILENAME);
    int r;
    r = stream_spy.open(name, name_ref);
    eof = 1;
    return r;
  endfunction

//--------------------------------------
// open
//--------------------------------------
  function void close;
    stream_spy.close;
  endfunction

//--------------------------------------
// start
//--------------------------------------
  task start (input integer count);
    fork
      begin
        stream_spy.start;
      end
      begin
        @(posedge clk) begin
          sample_cnt_max <= count;
          prepare_next_rdy(ACT_GET_NEXT);
        end
      end
    join

    eof <= 0;
    -> start_event;
  endtask

//--------------------------------------
// stop
//--------------------------------------
  task stop ();
    eof <= 1;
    stream_spy.stop;
  endtask

//--------------------------------------
// prepare_next_rdy
//--------------------------------------
// Set value in rdy.
  task prepare_next_rdy(input action_e act_rdy);
    rdy_ctrl <= get_rdy(act_rdy);
  endtask // prepare_next_rdy

// ============================================================================================== --
// Process
// ============================================================================================== --
// -----------------------------
// Control
// -----------------------------
  bit start_pulse;

  initial begin
    start_pulse <= 1'b0;
    forever begin
      wait(start_event.triggered);
      @(posedge clk)
        start_pulse <= 1'b1;
      @(posedge clk)
        start_pulse <= 1'b0;
    end
  end

  always_ff @(posedge clk)
    if (!s_rst_n || start_pulse)
      sample_cnt <= 0;
    else if (rdy && vld)
        sample_cnt <= sample_cnt + 1;

  assign running = ~eof & ((sample_cnt_max == 0) || (sample_cnt < sample_cnt_max));

// -----------------------------
// rdy
// -----------------------------
  initial begin
    rdy_ctrl <= 1'b0;
    wait(s_rst_n);
    while (1) begin
      @(posedge clk);
      if ((rdy && vld) || !rdy_ctrl) // data sampled
        prepare_next_rdy(ACT_GET_NEXT);
    end
  end

  always_ff @(posedge clk)
    if (KEEP_RDY)
      keep_rdy_mask <= 1'b1;
    else
      if ((rdy && vld) || !rdy_ctrl) // do not mask when prepare is setting a new rdy value.
        keep_rdy_mask <= 1'b1;
      else if ((vld && !rdy) || !keep_rdy_mask)
        keep_rdy_mask <= $urandom_range(1);

  assign rdy  = rdy_ctrl & running & keep_rdy_mask & s_rst_n;
endmodule

