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
//    FILENAME_REF : file where to read for the reference
//    FILENAME     : file where to write
// ----------------------------------------------------------------------------------------------
//    DATA_TYPE_REF : Read reference file data format :
//                "binary"
//                "ascii_hex", "ascii_bin" : 1 data per line. In this format, comment lines and
//                                           comment at the end of line are supported
//                                           (starts with #).
//    DATA_TYPE   : write file data format :
//                "binary"
//                "ascii_hex", "ascii_bin" : 1 data per line.
//
//    DATA_W   : Data width
// ==============================================================================================

module stream_spy 
  import file_handler_pkg::*;
#(
  parameter string  FILENAME       = "",
  parameter string  DATA_TYPE      = "ascii_hex", // Support "ascii_bin", "binary"
  parameter string  FILENAME_REF   = "",
  parameter string  DATA_TYPE_REF  = "ascii_hex", // Support "ascii_bin", "binary"
  parameter integer DATA_W         = 16
)
(
    input               clk,        // clock
    input               s_rst_n,    // synchronous reset

    input [DATA_W-1:0]  data,
    input               vld,
    input               rdy,

    output              error // pulse
);

// ============================================================================================== --
// Internal variables
// ============================================================================================== --
  logic                      ref_eof;
  string                     ref_file_name;
  string                     write_file_name;
  bit                        ref_running;
  bit                        write_running;

  event                      mismatch_event;
  logic [DATA_W-1:0]         data_ref;

  bit                        do_write = 1'b0;
  bit                        do_ref   = 1'b0;

// ============================================================================================== --
// read_data
// ============================================================================================== --
  read_data #(.DATA_W(DATA_W))     rdata = new(.filename(FILENAME_REF), .data_type(DATA_TYPE_REF));
  write_data #(.DATA_W(DATA_W))    wdata = new(.filename(FILENAME), .data_type(DATA_TYPE), .append(0));

// ============================================================================================== --
// Tasks / Functions
// ============================================================================================== --
//--------------------------------------
// set_do_write
//--------------------------------------
  function void set_do_write(input bit v);
    do_write = v;
  endfunction

//--------------------------------------
// set_do_ref
//--------------------------------------
  function void set_do_ref(input bit v);
    do_ref = v;
  endfunction

//--------------------------------------
// open
//--------------------------------------
  function int open(input string name = FILENAME, input string name_ref = FILENAME_REF);
    int r0, r1;
    r0 = 1;
    r1 = 1;
    if (do_write) begin
      write_file_name = name;
      write_running = 1;

      r0 = wdata.open(name,DATA_TYPE,0);
      if (!r0) begin
        $display("%t > ERROR: %m opening reference file %0s failed\n", $time, name);
        $finish;
      end
    end
    else
      write_running = 0;

    if (do_ref) begin
      ref_file_name = name_ref;
      ref_eof       = 0;

      r1 = rdata.open(name_ref,DATA_TYPE_REF);
      if (!r1) begin
        ref_eof = 1;
        $display("%t > ERROR: %m opening reference file %0s failed\n", $time, name_ref);
        $finish;
      end
    end
    else
      ref_eof = 1;

    return r0 || r1;
  endfunction

//--------------------------------------
// start
//--------------------------------------
  task start;
    if (do_ref) begin
      rdata.start;
      @(posedge clk) begin
        ref_eof  <= rdata.eof;
        data_ref <= rdata.get_cur_data;
      end
    end
  endtask

//--------------------------------------
// stop
//--------------------------------------
  task stop;
    fork
      begin
        if (!ref_running)
          $display ("%t > WARNING: %m stopped but ref was not running\n", $time);
        else begin
          @(posedge clk)
            ref_eof <= 1;
        end
      end
      begin
        if (!write_running)
          $display ("%t > WARNING: %m stopped but write was not running\n", $time);
        else begin
          @(posedge clk)
            write_running <= 1;
        end
      end
    join
  endtask

//--------------------------------------
// close
//--------------------------------------
    function void close;
      if (do_write) begin
        write_running = 0;
        wdata.close();
      end
    endfunction

// ============================================================================================== --
// Process
// ============================================================================================== --
  assign ref_running = ~ref_eof;

// -----------------------------
// Check data
// -----------------------------
  initial begin
    while (1) begin
      @(posedge clk)
      if (ref_running) begin
        if (rdy && vld) begin
          assert(data == data_ref)
          else begin
            $display("%t > ERROR: Data mismatch %m : exp=0x%0x, seen=0x%0x.",$time, data_ref, data);
            -> mismatch_event;
          end
          data_ref <= rdata.get_next_data;
          ref_eof  <= rdata.eof;
        end
      end
    end
  end

  assign error = ref_running & vld & rdy & (data !== data_ref);

// -----------------------------
// Write data
// -----------------------------
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      if (write_running) begin
        if (rdy && vld)
          wdata.set_data(data);
      end
    end

endmodule

