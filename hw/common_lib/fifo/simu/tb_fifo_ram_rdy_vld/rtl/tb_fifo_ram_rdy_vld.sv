// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : This is the explicit title of the testbench module
// ----------------------------------------------------------------------------------------------
//
// This testbench tests the fifo_ram_rdy_vld.
// The different phases are:
// ST_FULL          : Fill the FIFO until it is full
// ST_EMPTY         : Read the FIFO until it is empty
// ST_RANDOM_ACCESS : Do random accesses.
// ==============================================================================================

module tb_fifo_ram_rdy_vld;
  `timescale 1ns/10ps

  // ============================================================================================== --
  // localparam / parameter
  // ============================================================================================== --
  localparam int CLK_HALF_PERIOD   = 1;
  localparam int ARST_ACTIVATION   = 17;

  parameter int DEPTH              = 129;
  parameter int RAM_LATENCY        = 2;
  parameter int ALMOST_FULL_REMAIN = 1;

  localparam int WIDTH             = 8;
  localparam int DEPTH_LOCAL       = DEPTH + RAM_LATENCY + 1; // real capacity of the FIFO.
  localparam int DEPTH_LOCAL_W     = $clog2(DEPTH_LOCAL);
  localparam int RANDOM_ACCESS_CNT = DEPTH*10;
  // ============================================================================================== --
  // clock, reset
  // ============================================================================================== --
  bit clk;
  bit a_rst_n;  // asynchronous reset
  bit s_rst_n;  // synchronous reset

  initial begin
    clk     = 1'b0;
    a_rst_n = 1'b0;  // active reset
    #ARST_ACTIVATION a_rst_n = 1'b1;  // disable reset
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
  bit error_full;
  bit error_empty;
  bit error_empty_throughput;
  bit error_almost_full;

  assign error = error_full | error_empty | error_data | error_almost_full | error_empty_throughput;
  always_ff @(posedge clk)
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
  fifo_ram_rdy_vld #(
    .WIDTH         (WIDTH),
    .DEPTH         (DEPTH),
    .RAM_LATENCY   (RAM_LATENCY),
    .ALMOST_FULL_REMAIN (ALMOST_FULL_REMAIN)
  ) dut (
    .clk    (clk),
    .s_rst_n(s_rst_n),

    .in_data(in_data),
    .in_vld (in_vld),
    .in_rdy (in_rdy),

    .out_data(out_data),
    .out_vld (out_vld),
    .out_rdy (out_rdy),

    .almost_full(almost_full)
  );

  // ============================================================================================== --
  // Scenario
  // ============================================================================================== --
  // ---------------------------------------------------------------------------------------------- --
  // FSM
  // ---------------------------------------------------------------------------------------------- --
  typedef enum {ST_IDLE,
                ST_FULL_1,
                ST_RANDOM_ACCESS_1,
                ST_FULL_2,
                ST_EMPTY,
                ST_EMPTY_THROUGHPUT,
                ST_RANDOM_ACCESS_2,
                ST_DONE,
                XXX} state_e;

  state_e state;
  state_e next_state;
  logic start;
  int access_cnt;

  always_ff @(posedge clk) begin
    if (!s_rst_n) state <= ST_IDLE;
    else          state <= next_state;
  end

  always_comb begin
    next_state = XXX;
    case (state)
      ST_IDLE:
        next_state = start ? ST_FULL_1 : state;
      ST_FULL_1:
        next_state = access_cnt == DEPTH_LOCAL ? ST_RANDOM_ACCESS_1 : state;
      ST_RANDOM_ACCESS_1:
        next_state = access_cnt == RANDOM_ACCESS_CNT ? ST_FULL_2 : state;
      ST_FULL_2:
        next_state = (in_rdy == 0) ? ST_EMPTY : state;
      ST_EMPTY:
        next_state = access_cnt == DEPTH_LOCAL ? ST_EMPTY_THROUGHPUT : state;
      ST_EMPTY_THROUGHPUT:
        next_state = access_cnt == DEPTH_LOCAL ? ST_RANDOM_ACCESS_2 : state;
      ST_RANDOM_ACCESS_2:
        next_state = access_cnt == RANDOM_ACCESS_CNT ? ST_DONE : state;
      ST_DONE:
        next_state = state;
    endcase
  end

  logic st_idle;
  logic st_full_1;
  logic st_full_2;
  logic st_random_access_1;
  logic st_random_access_2;
  logic st_empty;
  logic st_empty_throughput;
  logic st_done;

  assign st_idle            = (state == ST_IDLE);
  assign st_full_1          = (state == ST_FULL_1);
  assign st_full_2          = (state == ST_FULL_2);
  assign st_random_access_1 = (state == ST_RANDOM_ACCESS_1);
  assign st_random_access_2 = (state == ST_RANDOM_ACCESS_2);
  assign st_empty           = (state == ST_EMPTY);
  assign st_empty_throughput= (state == ST_EMPTY_THROUGHPUT);
  assign st_done            = (state == ST_DONE);

  // ---------------------------------------------------------------------------------------------- --
  // Control
  // ---------------------------------------------------------------------------------------------- --
  logic reset_access_cnt;

  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      access_cnt <= 0;
    end
    else begin
      if (reset_access_cnt)
        access_cnt <= 0;
      else if (st_full_1 || st_full_2)  begin
        access_cnt <= (in_vld && in_rdy) ? access_cnt + 1 : access_cnt;
      end
      else if (st_empty || st_empty_throughput)  begin
        access_cnt <= (out_vld && out_rdy) ? access_cnt + 1 : access_cnt;
      end
      else if (st_random_access_1 || st_random_access_2)  begin
        access_cnt <= (in_vld && in_rdy) ? (out_vld && out_rdy) ? access_cnt + 2 : access_cnt + 1 :
                      (out_vld && out_rdy) ? access_cnt + 1 : access_cnt;
      end
    end
  end

  always_comb begin
    case (state)
      ST_FULL_1, ST_EMPTY, ST_EMPTY_THROUGHPUT:
        reset_access_cnt = access_cnt == DEPTH_LOCAL;
      ST_RANDOM_ACCESS_1, ST_RANDOM_ACCESS_2:
        reset_access_cnt = access_cnt > RANDOM_ACCESS_CNT;
      default:
        reset_access_cnt = 1;
    endcase
  end

  always_ff @(posedge clk) begin
    if (!s_rst_n) start <= 1'b0;
    else          start <= 1'b1;
  end

  assign end_of_test = st_done;

  // ---------------------------------------------------------------------------------------------- --
  // Data
  // ---------------------------------------------------------------------------------------------- --
  logic [WIDTH-1:0] rand_data;
  logic             rand_vld;
  logic             rand_rdy;
  always_ff @(posedge clk) begin
    rand_data <= $urandom_range(2 ** WIDTH - 1);
    rand_vld  <= $urandom_range(1);
    rand_rdy  <= $urandom_range(1);
  end

  assign in_data = rand_data;
  assign in_vld  = (st_full_1 || st_full_2) ? 1'b1 :
                   (st_random_access_1 || st_random_access_2 || st_empty_throughput) ? rand_vld : 1'b0;
  assign out_rdy = (st_empty || st_empty_throughput) ? 1'b1 :
                   (st_random_access_1 || st_random_access_2) ? rand_rdy : 1'b0;

  //== Check data
  // Use a queue to store the reference data
  logic [WIDTH-1:0] data_ref_q[$:DEPTH_LOCAL];

  always_ff @(posedge clk) begin
    logic [WIDTH-1:0] data_ref;
    if (!s_rst_n) begin
      error_data <= 0;
    end else begin
      if (in_rdy && in_vld) begin
        data_ref_q.push_front(in_data);
      end
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
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      error_full <= 0;
    end
    else begin
      if ((st_full_1) && access_cnt == DEPTH_LOCAL) begin
        assert(in_rdy == 0)
        else begin
          $display ("> ERROR: FIFO is full, but in_rdy is not 0!");
          error_full <= 1;
        end
      end
    end
  end

  //== check empty
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      error_empty <= 0;
    end
    else begin
      if (st_empty && access_cnt == DEPTH_LOCAL) begin
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
  logic [WIDTH-1:0] in_data_dly;

  always_ff @(posedge clk)
    if (!s_rst_n) in_vld_dly <= 0;
    else          in_vld_dly <= in_vld;

  always_ff @(posedge clk)
    in_data_dly <= in_data;

  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      error_empty_throughput <= 0;
    end
    else begin
      if (st_empty_throughput && in_vld_dly) begin
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
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      error_almost_full <= 0;
    end
    else begin
      if (st_full_1 && access_cnt > (DEPTH_LOCAL - ALMOST_FULL_REMAIN)) begin
        assert(almost_full)
        else begin
          $display("> ERROR: almost_full signal not triggered.");
          error_almost_full <= 1;
        end
      end
    end
  end
endmodule
