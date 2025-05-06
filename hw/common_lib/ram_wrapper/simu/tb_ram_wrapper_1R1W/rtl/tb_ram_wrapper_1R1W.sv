// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Bench that checks ram_wrapper_1R1W.
// The sceanrio is split into the following parts:
// ST_WRITE : fill the RAM with write accesses
// ST_READ  : read the RAM content
// ST_READ_AND_WRITE : read and write access at the same time without conflict
// ST_CONFLICT_ACCESS : read and write at the same address
// ST_RANDOM_ACCESS : random read and write accesses.
//
// Data have the following format : {wr_id, add}, where wr_id is writing identifier
// (depends on the state), and add is the current address.
// Note that in the last step : ST_RANDOM_ACCESS, wr_id is not checked, since, the bench does not
// control the read/write order.
// ==============================================================================================

module tb_ram_wrapper_1R1W;
`timescale 1ns/10ps

  import ram_wrapper_pkg::*;

// ============================================================================================== --
// localparam / parameter
// ============================================================================================== --
  localparam int  CLK_HALF_PERIOD = 1;
  localparam int  ARST_ACTIVATION = 17;

  parameter int   RAM_LATENCY       = 1;
  parameter int   RD_WR_ACCESS_TYPE = 1;
  parameter bit   KEEP_RD_DATA      = 0;

  localparam int  DEPTH      = 11; // For this bench, should be at least 8.
  localparam int  DEPTH_W    = $clog2(DEPTH);
  localparam int  WIDTH      = 2+DEPTH_W;   // For this bench, should be at least 2+clog2(DEPTH).
  localparam int  MAX_ACCESS = DEPTH*4; // Number of read and write accesses in random access phase.

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

// ============================================================================================== --
// Error
// ============================================================================================== --
  bit error;

// ============================================================================================== --
// input / output signals
// ============================================================================================== --
  // Read port
  logic                     rd_en;
  logic [DEPTH_W-1:0]       rd_add;
  logic [WIDTH-1:0]         rd_data;

  // Write port
  logic                     wr_en;
  logic [DEPTH_W-1:0]       wr_add;
  logic [WIDTH-1:0]         wr_data;

// ============================================================================================== --
// Design under test instance
// ============================================================================================== --
  ram_wrapper_1R1W #(
    .WIDTH             (WIDTH            ),
    .DEPTH             (DEPTH            ),
    .RD_WR_ACCESS_TYPE (RD_WR_ACCESS_TYPE),
    .KEEP_RD_DATA      (KEEP_RD_DATA     ),
    .RAM_LATENCY       (RAM_LATENCY      )
  ) dut (
    .clk     (clk    ),
    .s_rst_n (s_rst_n),

    .rd_en   (rd_en  ),
    .rd_add  (rd_add ),
    .rd_data (rd_data),

    .wr_en   (wr_en  ),
    .wr_add  (wr_add ),
    .wr_data (wr_data)
  );

// ============================================================================================== --
// Scenario
// ============================================================================================== --
// ---------------------------------------------------------------------------------------------- --
// FSM
// ---------------------------------------------------------------------------------------------- --
  typedef enum {ST_IDLE,
                ST_WRITE,
                ST_READ,
                ST_READ_AND_WRITE,
                ST_CONFLICT_ACCESS,
                ST_RANDOM_ACCESS,
                ST_DONE} state_e;
  state_e state;
  state_e next_state;
 
  logic start;
  logic wr_done;
  logic rd_done;
  int access_cnt;


  always_ff @(posedge clk) begin
    if (!s_rst_n) state <= ST_IDLE;
    else          state <= next_state;
  end

  always_comb begin
    case (state)
      ST_IDLE:
        next_state = start ? ST_WRITE : ST_IDLE;
      ST_WRITE:
        if (wr_done)
          next_state = ST_READ;
        else
          next_state = state;
      ST_READ:
        if (rd_done)
          next_state = ST_READ_AND_WRITE;
        else
          next_state = state;
      ST_READ_AND_WRITE:
        if (wr_done)
          next_state = ST_CONFLICT_ACCESS;
        else
          next_state = state;
      ST_CONFLICT_ACCESS:
        if (wr_done)
          next_state = ST_RANDOM_ACCESS;
        else
          next_state = state;
      ST_RANDOM_ACCESS:
        if (access_cnt >= MAX_ACCESS && (rd_en || wr_en))
          next_state = ST_DONE;
        else
          next_state = state;
      ST_DONE:
        next_state = state;
      default:
        $error("> ERROR: Unknown state.");
    endcase
  end

  logic st_idle;
  logic st_write;
  logic st_read;
  logic st_read_and_write;
  logic st_conflict_access;
  logic st_random_access;

  assign st_idle           = (state == ST_IDLE);
  assign st_write          = (state == ST_WRITE);
  assign st_read           = (state == ST_READ);
  assign st_read_and_write = (state == ST_READ_AND_WRITE);
  assign st_conflict_access= (state == ST_CONFLICT_ACCESS);
  assign st_random_access  = (state == ST_RANDOM_ACCESS);
  assign st_done           = (state == ST_DONE);

// ---------------------------------------------------------------------------------------------- --
// Control
// ---------------------------------------------------------------------------------------------- --
  logic [DEPTH_W-1:0] last_wr_add;
  logic [DEPTH_W-1:0] last_rd_add;

  always_ff @(posedge clk) begin
    if (!s_rst_n) start <= 1'b0;
    else          start <= 1'b1;
  end

  assign last_wr_add = DEPTH-1;
  assign last_rd_add = st_read ? DEPTH-1 : DEPTH/2-1;

  assign wr_done = (wr_add == last_wr_add & wr_en);
  assign rd_done = (rd_add == last_rd_add & rd_en);

  logic [1:0] wr_id;

  assign wr_id = st_write ? 0 : st_read_and_write ? 1 : st_conflict_access ? 2 : 3;

  always_ff @(posedge clk) begin
    if (!s_rst_n) access_cnt <= 0;
    else if (st_random_access) access_cnt <= access_cnt + rd_en + wr_en;
  end


// ---------------------------------------------------------------------------------------------- --
// Stimuli
// ---------------------------------------------------------------------------------------------- --
  logic [1:0][DEPTH_W-1:0] cnt;
  logic [1:0]              cnt_parity;
  logic [1:0][DEPTH_W-1:0] rand_add;
  logic [1:0]              rand_en;
  logic                    rd_parity;
  logic                    wr_parity;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      cnt[0]     <= 0;
      cnt[1]     <= DEPTH/2;
      cnt_parity <= 2'b00;
    end
    else begin
      for (int i = 0; i< 2; i=i+1) begin
        if (!st_idle) begin
          if (cnt[i] == DEPTH-1) begin
            cnt[i] <= 0;
            cnt_parity[i] <= ~cnt_parity[i];
          end
          else begin
            cnt[i] <= cnt[i] + 1;
            cnt_parity[i] <= cnt_parity[i];
          end
        end
      end
    end

  always_ff @(posedge clk) begin
    for (int i = 0; i< 2; i=i+1) begin
      rand_add[i] <= $urandom_range(DEPTH-1);
      rand_en[i]  <= $urandom_range(1);
    end
  end

  assign wr_data = {wr_id, wr_add};
  always_comb begin
    case (state)
      ST_WRITE:
        begin
          rd_en  = 0;
          wr_en  = 1;
          rd_add = 'x;
          wr_add = cnt[0];
          rd_parity = 'x;
          wr_parity = cnt_parity[0];
        end
      ST_READ:
        begin
          rd_en  = 1;
          wr_en  = 0;
          rd_add = cnt[0];
          wr_add = 'x;
          rd_parity = cnt_parity[0];
          wr_parity = 'x;
        end
      ST_READ_AND_WRITE:
        begin
          rd_en  = 1;
          wr_en  = 1;
          rd_add = cnt[1];
          wr_add = cnt[0];
          rd_parity = cnt_parity[1];
          wr_parity = cnt_parity[0];
        end
      ST_CONFLICT_ACCESS:
        begin
          rd_en  = 1;
          wr_en  = 1;
          rd_add = cnt[0];
          wr_add = cnt[0];
          rd_parity = cnt_parity[0];
          wr_parity = cnt_parity[0];
        end
      ST_RANDOM_ACCESS:
        begin
          rd_en  = rand_en[0];
          wr_en  = rand_en[1];
          rd_add = rd_en ? rand_add[0] : 'x;
          wr_add = wr_en ? rand_add[1] : 'x;
          rd_parity = 'x; // Unused
          wr_parity = 'x; // Unused
        end
      default:
        begin
          rd_en  = 0;
          wr_en  = 0;
          rd_add = 'x;
          wr_add = 'x;
          rd_parity = 'x; // Unused
          wr_parity = 'x; // Unused
        end
    endcase
  end

// ---------------------------------------------------------------------------------------------- --
// Check
// ---------------------------------------------------------------------------------------------- --
  logic [WIDTH-1:0] rd_data_ref_tmp;
  logic [RAM_LATENCY-1:0][WIDTH-1:0] rd_data_ref_dly;
  logic [RAM_LATENCY-1:0][WIDTH-1:0] rd_data_ref_dlyD;
  logic [RAM_LATENCY-1:0] rd_avail_dly;
  logic [RAM_LATENCY-1:0] rd_avail_dlyD;
  logic error_datar;
  logic error_keep;
  logic access_conflict;

  assign access_conflict = rd_en & wr_en & (rd_add == wr_add);

  assign rd_data_ref_tmp = st_read            ? {2'd0, rd_add} :
                           st_read_and_write  ? (rd_parity != wr_parity) ? {2'd1, rd_add} : {2'd0, rd_add}:
                           st_conflict_access ? (RD_WR_ACCESS_TYPE == RD_WR_ACCESS_TYPE_CONFLICT) ? 'x:
                                                (RD_WR_ACCESS_TYPE == RD_WR_ACCESS_TYPE_READ_OLD) ? {2'd1, rd_add}:
                                                st_conflict_access ? {2'd2, rd_add}:{2'bxx, rd_add}:
                           (access_conflict && (RD_WR_ACCESS_TYPE == RD_WR_ACCESS_TYPE_CONFLICT)) ? 'x : {2'bxx, rd_add};
  assign rd_data_ref_dlyD[0] = rd_data_ref_tmp;
  assign rd_avail_dlyD[0]    = rd_en;
  generate
    if (RAM_LATENCY>1) begin
      assign rd_data_ref_dlyD[RAM_LATENCY-1:1] = rd_data_ref_dly[RAM_LATENCY-2:0];
      assign rd_avail_dlyD[RAM_LATENCY-1:1]    = rd_avail_dly[RAM_LATENCY-2:0];
    end
  endgenerate

  always_ff @(posedge clk) begin
    rd_data_ref_dly <= rd_data_ref_dlyD;
  end

  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      rd_avail_dly <= '0;
    end
    else begin
      rd_avail_dly <= rd_avail_dlyD;
    end
  end

  // check
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      error_datar <= 1'b0;
    end
    else begin
      if (rd_avail_dly[RAM_LATENCY-1]) begin
        assert(rd_data[DEPTH_W-1:0] === rd_data_ref_dly[RAM_LATENCY-1][DEPTH_W-1:0])
        else begin
          error_datar <= 1'b1;
          $error("> ERROR: Datar mismatches: exp=0x%0x seen=0x%0x",rd_data_ref_dly[RAM_LATENCY-1][DEPTH_W-1:0],rd_data[DEPTH_W-1:0]);
        end
      
        if (rd_data_ref_dly[RAM_LATENCY-1][DEPTH_W+:2] !== 2'bxx)
          assert(rd_data[DEPTH_W+:2] === rd_data_ref_dly[RAM_LATENCY-1][DEPTH_W+:2])
          else begin
            error_datar <= 1'b1;
            $error("> ERROR: Datar MSB mismatches: exp=0x%0x seen=0x%0x",rd_data_ref_dly[RAM_LATENCY-1][DEPTH_W+:2],rd_data[DEPTH_W+:2]);
          end
      end
    end
  end

  // check KEEP_RD_DATA
  generate
    if (KEEP_RD_DATA != 0) begin: keep_data_check_gen
      logic [WIDTH-1:0] rd_data_dly;
      logic             start_check_keep_datar;
      always_ff @(posedge clk)
        if (!s_rst_n) start_check_keep_datar <= 1'b0;
        else          start_check_keep_datar <= rd_avail_dly[RAM_LATENCY-1] ? 1'b1 : start_check_keep_datar;
      always_ff @(posedge clk) begin
        if (rd_avail_dly[RAM_LATENCY-1])
          rd_data_dly <= rd_data;
      end

      always_ff @(posedge clk) begin
        if (start_check_keep_datar) begin
          if (!rd_avail_dly[RAM_LATENCY-1])
            assert(rd_data === rd_data_dly)
            else begin
              error_keep <= 1'b1;
              $error("> ERROR: Datar not kept: exp=0x%0x, seen=0x%0x",rd_data_dly,rd_data);
            end
        end
      end
    end
    else begin
      assign error_keep = 1'b0;
    end
  endgenerate

  assign error = error_keep | error_datar;

  always_ff @(posedge clk)
    if (error) begin
      $display("%t > FAILURE !", $time);
      $finish;
    end
// ---------------------------------------------------------------------------------------------- --
// End of bench
// ---------------------------------------------------------------------------------------------- --
  assign end_of_test = st_done;

  initial begin
    wait(end_of_test);
    @(posedge clk)
        $display("%t > SUCCEED !", $time);
    $finish;
  end
endmodule
