// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : This is the explicit title of the testbench module
// ----------------------------------------------------------------------------------------------
//
// This testbench is really close to fifo_ram_rdy_vld.
// Differences are:
//  - two clocks interface with reset have been added
//  - splitting logic between in and out domains
//  - Testbench's FSM had to be split
//
// Must be taken into account:
//  - FIFO depth with XPM must be a power of two -> mandatory from XPM
//
// ==============================================================================================

module tb_fifo_ram_rdy_vld_2clk;
  `timescale 1ns/10ps

  // ============================================================================================== --
  // localparam / parameter
  // ============================================================================================== --
  localparam int CLK_HALF_PERIOD_A = 2;
  localparam int CLK_HALF_PERIOD_B = 1;
  localparam int ARST_ACTIVATION   = 17;

  parameter int CDC_SYNC_STAGES    = 2;
  parameter int DEPTH              = 128;
  parameter int OUT_FIFO_DEPTH     = 2;
  parameter int RAM_LATENCY        = 0; // TODO: because no ram latency, we must count up to DEPTH_LOCAL-1
  parameter int ALMOST_FULL_REMAIN = 1;

  localparam int WIDTH             = 8;

  localparam int DEPTH_LOCAL       = DEPTH + OUT_FIFO_DEPTH;

  localparam int DEPTH_LOCAL_W     = $clog2(DEPTH_LOCAL);
  localparam int RANDOM_ACCESS_CNT = DEPTH*10;
  // 1 wr_clk + (cdc sync stages + 2)*rd_clk
  localparam LAT_MODULE = 1 + CDC_SYNC_STAGES + 2;

  // ============================================================================================== --
  // clock, reset
  // ============================================================================================== --
  bit in_clk;
  bit a_in_rst_n;  // asynchronous reset
  bit s_in_rst_n;  // synchronous reset

  initial begin
    in_clk     = 1'b0;
    a_in_rst_n = 1'b0;  // active reset
    #CLK_HALF_PERIOD_A a_in_rst_n = 1'b1;  // disable reset
  end

  always begin
    #CLK_HALF_PERIOD_A in_clk = ~in_clk;
  end

  always_ff @(posedge in_clk) begin
    s_in_rst_n <= a_in_rst_n;
  end

  bit out_clk;
  bit a_out_rst_n;  // asynchronous reset
  bit s_out_rst_n;  // synchronous reset

  initial begin
    out_clk     = 1'b0;
    a_out_rst_n = 1'b0;  // active reset
    #CLK_HALF_PERIOD_B a_out_rst_n = 1'b1;  // disable reset
  end

  always begin
    #CLK_HALF_PERIOD_B out_clk = ~out_clk;
  end

  always_ff @(posedge out_clk) begin
    s_out_rst_n <= a_out_rst_n;
  end

  // ============================================================================================== --
  // End of test
  // ============================================================================================== --
  bit end_of_test;

  initial begin
    wait (end_of_test);
    @(posedge in_clk) $display("%t > SUCCEED !", $time);
    $finish;
  end

  // ============================================================================================== --
  // Error
  // ============================================================================================== --
  bit error;
  bit error_data;
  bit error_full;
  bit error_empty;
  bit error_empty_throughput;
  bit error_almost_full;

  assign error = error_full | error_empty | error_data | error_almost_full | error_empty_throughput;
  always_ff @(posedge in_clk)
    if (error) begin
      $display("%t > FAILURE !", $time);
      $finish;
    end

  // ============================================================================================== --
  // input / output signals
  // ============================================================================================== --
  logic [WIDTH-1:0] in_data;
  logic             in_vld;
  logic             in_rdy;

  logic [WIDTH-1:0] out_data;
  logic             out_vld;
  logic             out_rdy;

  logic             almost_full;

  // ============================================================================================== --
  // Design under test instance
  // ============================================================================================== --
  fifo_ram_rdy_vld_2clk #(
    .CDC_SYNC_STAGES    (   CDC_SYNC_STAGES),
    .WIDTH              (             WIDTH),
    .DEPTH              (             DEPTH),
    .OUT_FIFO_DEPTH     (    OUT_FIFO_DEPTH),
    .ALMOST_FULL_REMAIN (ALMOST_FULL_REMAIN)
  ) dut (
    .in_clk (in_clk),
    .in_rstn(s_in_rst_n),
    .in_data(in_data),
    .in_vld (in_vld),
    .in_rdy (in_rdy),

    .out_clk (out_clk),
    .out_rstn(s_out_rst_n),
    .out_data(out_data),
    .out_vld (out_vld),
    .out_rdy (out_rdy),

    .almost_full(almost_full)
  );

  // ============================================================================================== --
  // Scenario
  // ============================================================================================== --
  logic start;
  logic start_rd;
  logic start_wr;

  int   write_access_cnt;
  int   read_access_cnt;
  logic read_trans;
  logic write_trans;

  logic write_reset_full;
  logic write_reset_random;

  logic read_reset_empty;
  logic read_reset_random;

  // we need a small delay here to exit properly read and write reset busy; this is XPM specific
  initial begin
    start = 1'b0;
    #2500ns;
    start = 1'b1;
  end

  assign write_trans = in_vld & in_rdy;
  assign read_trans  = out_vld & out_rdy;

  // we need to count the number of writes
  always_ff @(posedge in_clk) begin
    if (~s_in_rst_n) begin
      write_access_cnt <= 'h0;
    end else begin
      if (write_reset_random | write_reset_full) begin
        write_access_cnt <= 0;
      end else if (start_wr & write_trans) begin
        write_access_cnt <= write_access_cnt+1;
      end
    end
  end

  // we need to count the number of writes
  always_ff @(posedge out_clk) begin
    if (~s_in_rst_n) begin
      read_access_cnt <= 'h0;
    end else begin
      if (read_reset_empty | read_reset_random) begin
        read_access_cnt <= 0;
      end else if (start_rd & read_trans) begin
        read_access_cnt <= read_access_cnt+1;
      end
    end
  end

  // write FSM ------------------------------------------------------------------------------------
  int cnt_full;
  logic st_full_1;
  logic st_random_access_1;
  logic st_full_2;
  logic st_done_write;
  logic full_is_stable;

  typedef enum {ST_IDLE_WR,
                ST_FULL_1,
                ST_RANDOM_ACCESS_1,
                ST_FULL_2,
                ST_DONE_WR,
                WR_XXX} state_write;

  state_write state_wr;
  state_write next_state_wr;

  always_ff @(posedge in_clk) begin
    if (!s_in_rst_n) state_wr <= ST_IDLE_WR;
    else             state_wr <= next_state_wr;
  end

  always_comb begin
    next_state_wr = WR_XXX;
    case (state_wr)
      ST_IDLE_WR:
        next_state_wr = start_wr ? ST_FULL_1 : state_wr;
      ST_FULL_1:
        next_state_wr = write_access_cnt == DEPTH_LOCAL-1 ? ST_RANDOM_ACCESS_1 : state_wr;
      ST_RANDOM_ACCESS_1:
        next_state_wr = write_access_cnt == RANDOM_ACCESS_CNT-1  ? ST_FULL_2 : state_wr;
      ST_FULL_2:
        next_state_wr = full_is_stable ? ST_DONE_WR : state_wr;
      ST_DONE_WR:
        next_state_wr = state_wr;
    endcase
  end

  assign st_full_1          = (state_wr == ST_FULL_1);
  assign st_random_access_1 = (state_wr == ST_RANDOM_ACCESS_1);
  assign st_full_2          = (state_wr == ST_FULL_2);
  assign st_done_write      = (state_wr == ST_DONE_WR);

  assign write_reset_full   = ((write_access_cnt==DEPTH_LOCAL-1) & st_full_1);
  assign write_reset_random = ((write_access_cnt==RANDOM_ACCESS_CNT-1) & st_random_access_1);

  // we must count the number of fullms and wait for the signal to be stable.
  // because frequency of clock in and out can be different and we MUST read in ST_RANDOM_ACCESS_1 we must wait that all words from read request are flushed
  assign full_is_stable = (cnt_full == 10) ? 1'b1: 1'b0;

  // -> First thing we do is that we start writing into FIFO when testbench start flag is up
  always_ff @(posedge in_clk) begin
    if (~s_in_rst_n) begin
      start_wr <= 1'b0;
    end else begin
      if (state_wr != ST_DONE_WR) begin
        start_wr <= start;
      end else begin
        start_wr <= 1'b0;
      end
    end
  end

  always_ff @(posedge in_clk) begin
    if (~s_in_rst_n) begin
      cnt_full <= 'h0;
    end else begin
      if (st_full_2 & ~in_rdy) begin
        cnt_full <= cnt_full + 1;
      end
    end
  end

  // read FSM -------------------------------------------------------------------------------------
  logic st_random_access_2;
  logic st_empty;
  logic st_empty_throughput;

  typedef enum {ST_IDLE_RD,
                ST_EMPTY,
                ST_EMPTY_THROUGHPUT,
                ST_RANDOM_ACCESS_2,
                ST_DONE_RD,
                RD_XXX} state_read;

  state_read  state_rd;
  state_read  next_state_rd;


  always_ff @(posedge out_clk) begin
    if (!s_in_rst_n) state_rd <= ST_IDLE_RD;
    else             state_rd <= next_state_rd;
  end

  // we start the read FSM only when write FSM is done
  always_ff @(posedge out_clk)
    start_rd <= state_wr == ST_DONE_WR;

  always_comb begin
    next_state_rd = RD_XXX;
    case (state_rd)
      ST_IDLE_RD:
        next_state_rd = start_rd ? ST_EMPTY : state_rd;
      ST_EMPTY:
        next_state_rd = read_access_cnt == DEPTH_LOCAL-1 ? ST_EMPTY_THROUGHPUT : state_rd;
      ST_EMPTY_THROUGHPUT:
        next_state_rd = read_access_cnt == DEPTH_LOCAL-1 ? ST_RANDOM_ACCESS_2 : state_rd;
      ST_RANDOM_ACCESS_2:
        next_state_rd = read_access_cnt == RANDOM_ACCESS_CNT-1 ? ST_DONE_RD : state_rd;
      ST_DONE_RD:
        next_state_rd = state_rd;
    endcase
  end

  assign st_random_access_2 = (state_rd == ST_RANDOM_ACCESS_2);
  assign st_empty           = (state_rd == ST_EMPTY);
  assign st_empty_throughput= (state_rd == ST_EMPTY_THROUGHPUT);

  assign read_reset_empty   = ((read_access_cnt==DEPTH_LOCAL-1) & (st_empty | st_empty_throughput));
  assign read_reset_random = ((read_access_cnt==RANDOM_ACCESS_CNT-1) & st_random_access_1);

  assign end_of_test = state_rd == ST_DONE_RD;

  // ---------------------------------------------------------------------------------------------- --
  // Data
  // ---------------------------------------------------------------------------------------------- --
  logic [WIDTH-1:0] rand_data;
  logic             rand_vld;
  logic             rand_rdy;
  always_ff @(posedge in_clk) begin
    rand_data <= $urandom_range(2 ** WIDTH - 1);
    rand_vld  <= $urandom_range(1);
  end

  // we accept only here to enable reads when a flag is up: if we read while writing we will never see
  // the fifo getting full when we expect it to be.
  // when rand_rdy start we should see the data we filled earlier and see the control behaving as expected
  always_ff @(posedge out_clk) begin
    if (st_random_access_1 | st_random_access_2) begin
      rand_rdy  <= $urandom_range(1);
    end else begin
      rand_rdy  <= 1'b0;
    end
  end

  assign in_data = rand_data;
  assign in_vld  = (st_full_1 || st_full_2) ? 1'b1 :
                   (st_random_access_1 || st_random_access_2 || st_empty_throughput) ? rand_vld : 1'b0;
  assign out_rdy = (st_empty || st_empty_throughput) ? 1'b1 :
                   (st_random_access_1 || st_random_access_2) ? rand_rdy : 1'b0;
  //== Check data
  // Use a queue to store the reference data
  logic [WIDTH-1:0] data_ref_q[$:DEPTH_LOCAL];

  always_ff @(posedge in_clk) begin
    if (in_rdy & in_vld) begin
      data_ref_q.push_front(in_data);
    end
  end

  always_ff @(posedge out_clk) begin
    logic [WIDTH-1:0] data_ref;
    if (!s_out_rst_n) begin
      error_data <= 0;
    end else begin
      if (out_rdy && out_vld) begin
        data_ref = data_ref_q.pop_back();
        assert (out_data == data_ref)
        else begin
          $display("> ERROR: Data mismatch: exp=0x%x seen=0x%x", data_ref, out_data);
          error_data <= 1;
        end
      end
    end
  end

  //== check full
  always_ff @(posedge in_clk) begin
    if (!s_in_rst_n) begin
      error_full <= 0;
    end
    else begin
      if ((st_full_1) && write_access_cnt == DEPTH_LOCAL) begin
        assert(in_rdy == 0)
        else begin
          $display ("> ERROR: FIFO is full, but in_rdy is not 0!");
          error_full <= 1;
        end
      end
    end
  end

  //== check empty
  always_ff @(posedge in_clk) begin
    if (!s_in_rst_n) begin
      error_empty <= 0;
    end
    else begin
      if (st_empty && read_access_cnt == DEPTH_LOCAL) begin
        assert(out_vld == 0)
        else begin
          $display ("> ERROR: FIFO is empty, but out_vld is not 0!");
          error_empty <= 1;
        end
      end
    end
  end

  //== check empty throughput
  logic in_vld_dly;
  logic [5:0] in_fifo_dly;
  logic [WIDTH-1:0] in_data_dly;

  always_ff @(posedge in_clk)
    if (!s_in_rst_n) in_vld_dly <= 0;
    else          in_vld_dly <= in_vld;

  always_ff @(posedge in_clk)
    in_fifo_dly[0] <= in_vld;

  always_ff @(posedge out_clk)
    for (int i = 1; i < 5; i++)
      in_fifo_dly[i] <= in_fifo_dly[i-1];

  always_ff @(posedge in_clk)
    in_data_dly <= in_data;

  always_ff @(posedge out_clk) begin
    if (!s_out_rst_n) begin //todo
      error_empty_throughput <= 0;
    end
    else begin
      if (st_empty_throughput && in_fifo_dly[5]) begin
        assert((out_vld == 1) && (out_data == in_data_dly))
        else begin
          $display("> ERROR: Empty throughput : exp=(%1d, 0x%0x), seen=(%1d,0x%0x)",
                      in_vld_dly, in_data_dly, out_vld, out_data);
          error_empty_throughput <= 1;
        end
      end
    end
  end

  //== check almost_full
  always_ff @(posedge in_clk) begin
    if (!s_in_rst_n) begin
      error_almost_full <= 0;
    end
    else begin
      if (st_full_1 && write_access_cnt > (DEPTH_LOCAL - ALMOST_FULL_REMAIN)) begin
        assert(almost_full)
        else begin
          $display("> ERROR: almost_full signal not triggered.");
          error_almost_full <= 1;
        end
      end
    end
  end
endmodule
