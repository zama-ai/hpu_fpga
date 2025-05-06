// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// class that handles file IO.
// ==============================================================================================

package file_handler_pkg;
  import random_handler_pkg::*;

// ============================================================================================== --
// class read_data
// ============================================================================================== --
// Class that handles data generation.
// According to filename, data can be :
//   * counter
//   * random data
//   * data from a file.
// data_type: File data format :
//                "binary"
//                "ascii_hex", "ascii_bin" :
//                         1 data per line. In this format, comment lines and
//                         comment at the end of line are supported
//                            (starts with #).
// DATA_W: Data width

  class read_data #(parameter int DATA_W = 8);
  //--------------------------------------------
  // type
  //--------------------------------------------
    typedef enum { ST_IDLE,
                  ST_UNINITIALIZED,
                  ST_RUN,
                  ST_EOF} state_e;

  //--------------------------------------------
  // Data members
  //--------------------------------------------
    local string                      filename;
    local string                      data_type;
    local state_e                     state;
    local logic [DATA_W-1:0]          cur_data;
    local int                         fd; // file descriptor

    local logic [DATA_W-1:0]          counter_data;
    random_data#(DATA_W)              rand_data;
    local int                         data_cnt;
    local int                         line_cnt;

    event                             eof_event;

  //--------------------------------------------
  // Constructor
  //--------------------------------------------
    function new (
      input string data_type = "ascii_hex",
      input string filename  = ""
    );
      this.data_type    = data_type;
      this.filename     = filename;
      this.state        = ST_IDLE;
      this.fd           = 0;
      this.cur_data     = 'x;
      this.counter_data = -1;
      this.rand_data    = new;
    endfunction : new

  //--------------------------------------------
  // Functions
  //--------------------------------------------
  //----------------------
  // print
  //----------------------
    function void print;
      $display ("read_data :");
      $display (" DATA_W     : %0d"  , this.DATA_W    );
      $display (" filename   : %s"   , this.filename  );
      $display (" data_type  : %s"   , this.data_type );
      $display (" state      : %s"   , this.state     );
      $display (" cur_data   : 0x%0x", this.cur_data  );
    endfunction : print

  //----------------------
  // open
  //----------------------
    function int open(input string filename = this.filename, input string data_type = this.data_type);
      // check current state
      if (state != ST_IDLE && state != ST_EOF) begin
        $display("%t > WARNING: %m was not in idle or eof state when open for %s is called.", $time, filename);
        // close previous file
        if (fd != 0)
          $fclose (fd);
      end
      fd            = 0;
      state         = ST_IDLE;
      data_cnt      = 0;
      line_cnt      = 0;
      this.data_type = data_type;
      this.filename  = filename;
      if (filename != "counter" && filename != "random") begin
        $display("%t > INFO: Opening file %s", $time, this.filename);
        fd = $fopen(this.filename,"r");
        if (fd == 0) begin
          $display("%t > ERROR: opening file %s", $time, this.filename);
        end
        else begin
          state = ST_UNINITIALIZED;
        end
      end
      else begin
        // no file needed
        state = ST_UNINITIALIZED;
      end
      return  state == ST_UNINITIALIZED; // if (1) success, if (0) Failure
    endfunction : open

  //----------------------
  // start
  //----------------------
  // initialize cur_data
    function void start;
      if (state == ST_UNINITIALIZED)
        cur_data = get_next_data();
      state = ST_RUN;
    endfunction

  //----------------------
  // get_cur_data
  //----------------------
    function [DATA_W-1:0] get_cur_data;
      return cur_data;
    endfunction

  //----------------------
  // get_next_data
  //----------------------
  // Update cur_data and output its value
    function [DATA_W-1:0] get_next_data;
      data_cnt = data_cnt + 1;
      case (filename)
        "counter":
          begin
            counter_data = counter_data + 1;
            cur_data = counter_data;
          end
        "random":
          begin
            rand_data.randomize();
            cur_data = rand_data.get_data();
          end
        default:
          begin
            cur_data = get_file_next_data();
          end
      endcase
      return cur_data;
    endfunction

  //----------------------
  // get_file_next_data
  //----------------------
    local function [DATA_W-1:0] get_file_next_data();
      integer              r;
      logic [DATA_W-1:0]   file_data;

      if (data_type == "binary") begin
        r = 0;
        if (!$feof(fd))
          r = $fread(file_data, fd);
        if (r == 0) begin // Error occurs while reading
          state     = ST_EOF;
          file_data = cur_data;
          $display("%t > INFO: No more data in %0s at data_cnt %0d", $time, filename, data_cnt);
          data_cnt  = data_cnt -1;
        end
        else begin
          if (r != (DATA_W / 8))
            $display ("%t > WARNING: Truncated data in %0s at data_cnt %0d", $time, filename, data_cnt);  
        end
      end
      else begin // ascii
        r = 0;
        while (!r && !$feof(fd)) begin
          r = get_next_line(file_data);
        end
        if (r == 0) begin // data not found
           state     = ST_EOF;
           file_data = cur_data;
           $display("%t > INFO: No more data in %0s at data_cnt %0d", $time, filename, data_cnt);
           data_cnt  = data_cnt -1;
        end
      end

      return file_data;
    endfunction

  //----------------------
  // get_next_line
  //----------------------
    local function integer get_next_line (output [DATA_W-1:0] line_data);
      integer r;
      string  line_buffer;

      if (data_type == "binary") begin
        $fatal (1, "%t > %m : Unsupported call to next_line function for binary input file", $time);
      end
      else begin
        line_cnt         = line_cnt + 1;
        r                = $fgets (line_buffer, fd);
        if (r == 0) begin // no more data
          state = ST_EOF;
          line_data = 'x;
          $display ("%t > INFO: No more line in %0s at line %0d", $time, filename, line_cnt);
          line_cnt  = line_cnt - 1;
        end
        else begin
          if (line_buffer[0] == "#") begin // Comment line
            // Do nothing
            //$display ("%t > INFO: L.%0d - comment : %s",$time, line_cnt, line_buffer);
            r = 0;
          end
          else if (line_buffer.len() == 1) begin
            // Do nothing: size 1 means line_buffer contains only a carriage
            // return which we do not care about
            r = 0;
          end
          else begin // Not a comment line
            // Remove comment at the end of the line if present
            integer v;
            string s0, s1;
            v = $sscanf(line_buffer,"%s#%s",s0, s1);
            if (v == 2)
              line_buffer = s0; // keep data part of the line
            case (data_type)
              "ascii_hex" :
                r = $sscanf (line_buffer, "%h", line_data);
              "ascii_bin" :
                r = $sscanf (line_buffer, "%b", line_data);
              default :
                $display("%t > ERROR: Unknown data type.", $time);
            endcase
          end
        end
        return r;
      end // no binary

    endfunction

  //----------------------
  // get_state
  //----------------------
    function state_e get_state;
      return state;
    endfunction

  //----------------------
  // is_running
  //----------------------
    function bit is_st_running;
      return state == ST_RUN;
    endfunction


  //----------------------
  // is_idle
  //----------------------
    function bit is_st_idle;
      return state == ST_IDLE;
    endfunction

  //----------------------
  // is_st_eof
  //----------------------
    function bit is_st_eof;
      return state == ST_EOF;
    endfunction

  //----------------------
  // eof
  //----------------------
    function int eof;
      if (is_file())
        return $feof(fd);
      else
        return 0;
    endfunction

  //----------------------
  // is_file
  //----------------------
    function bit is_file;
      return ~(filename == "counter" || filename == "random");
    endfunction

  //----------------------
  // set_counter
  //----------------------
    function void set_counter(input [DATA_W-1:0] val);
      this.counter_data = val;
    endfunction

  //----------------------
  // set_counter_and_update
  //----------------------
    function void set_counter_and_update(input [DATA_W-1:0] val);
      this.counter_data = val;
      this.cur_data     = val;
    endfunction

  endclass : read_data



// ============================================================================================== --
// class write_data
// ============================================================================================== --
// Class that writes data into a file
// data_type: File data format :
//                "binary"
//                "ascii_hex", "ascii_bin", "ascii" :
//                        1 data per line.
// DATA_W: Data width

  class write_data #(parameter int DATA_W = 8);
  //--------------------------------------------
  // type
  //--------------------------------------------
    typedef enum { ST_IDLE,
                   ST_RUN} state_e;

  //--------------------------------------------
  // Data members
  //--------------------------------------------
    local string                      filename;
    local string                      data_type;
    local state_e                     state;
    local logic [DATA_W-1:0]          cur_data;
    local int                         fd; // file descriptor
    local bit                         append;

    local int                         data_cnt;
    local bit                         warning_printed;

  //--------------------------------------------
  // Constructor
  //--------------------------------------------
    function new (
      input string data_type = "ascii_hex",
      input string filename  = "",
      input bit    append = 0
    );
      this.data_type    = data_type;
      this.filename     = filename;
      this.state        = ST_IDLE;
      this.fd           = 0;
      this.cur_data     = 'x;
      this.append       = 1'b0;
    endfunction : new

  //--------------------------------------------
  // Functions
  //--------------------------------------------
  //----------------------
  // print
  //----------------------
    function void print;
      $display ("read_data :");
      $display (" DATA_W     : %0d"  , this.DATA_W    );
      $display (" filename   : %s"   , this.filename  );
      $display (" data_type  : %s"   , this.data_type );
      $display (" state      : %s"   , this.state     );
      $display (" cur_data   : 0x%0x", this.cur_data  );
      $display (" append     : %0b"  , this.append  );
    endfunction : print

  //----------------------
  // open
  //----------------------
    function int open(input string filename  = this.filename,
                      input string data_type = this.data_type,
                      input bit    append    = this.append);
      string access;
      // check current state
      if (state != ST_IDLE) begin
        $display("%t > WARNING: %m was not in idle or stop state when open for %s is called.", $time, filename);
        // close previous file
        if (fd != 0)
          $fclose (fd);
      end
      fd              = 0;
      state           = ST_IDLE;
      data_cnt        = 0;
      warning_printed = 0;
      this.data_type  = data_type;
      this.filename   = filename;
      access          = append ? "a" : "w";
      $display("%t > INFO: Opening file %s", $time, this.filename);
      fd = $fopen(this.filename, access);
      if (fd == 0) begin
        $display("%t > ERROR: opening file %s", $time, this.filename);
      end
      else begin
        state = ST_RUN;
      end
      return  state == ST_RUN; // if (1) success, if (0) Failure
    endfunction : open

  //----------------------
  // close
  //----------------------
    function void close;
      if (!fd) begin
        $display("%t > WARNING: %m closing a file that has not been opened.", $time);
      end
      else begin
        $fclose (fd);
        fd  = 0;
      end
      state = ST_IDLE;
    endfunction

  //----------------------
  // set_data
  //----------------------
  function void set_data(logic[DATA_W-1:0] data);
    reg [7:0] c;
    int       j;
    begin
      data_cnt = data_cnt + 1;
      cur_data = data;
      case (data_type)
        "ascii_hex" :
          $fwrite (fd, "%h\n", data);
        "ascii_bin" :
          $fwrite (fd, "%b\n", data);
        "ascii" :
          $fwrite (fd, "%0s\n", data);
        "binary" :
          begin
             if ((^data !== 1'b 0) && (^data !== 1'b 1) && warning_printed == 0) begin
                  $display ("%t > WARNING: Trying to write x in binary file%m", $time);
                  warning_printed = 1;
             end
             for (int i = 0; i < DATA_W; i = i + 8) begin
                  c = data >> (DATA_W - i - 8);
                  $fwrite (fd, "%c", c);
             end
          end
        default :
          $fwrite (fd, "%h", data);
      endcase // case(data_type)
    end
  endfunction

  //----------------------
  // get_state
  //----------------------
    function state_e get_state;
      return state;
    endfunction

  //----------------------
  // is_running
  //----------------------
    function bit is_st_running;
      return state == ST_RUN;
    endfunction

  //----------------------
  // is_idle
  //----------------------
    function bit is_st_idle;
      return state == ST_IDLE;
    endfunction

  endclass : write_data

endpackage
