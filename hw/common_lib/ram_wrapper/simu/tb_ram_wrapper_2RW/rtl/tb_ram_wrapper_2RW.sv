// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description :
// ----------------------------------------------------------------------------------------------
//
// Bench that checks ram_wrapper_1R1W.
// The sceanrio is split into the following parts:
// ST_WRITE_A : fill the RAM with write accesses from port A
// ST_READ_B  : read the RAM content from port B
// ST_WRITE_B : fill the RAM with write accesses from port A
// ST_READ_A  : read the RAM content from port B
// ST_READ_A_AND_WRITE_B : read and write access at the same time without conflict
// ST_READ_B_AND_WRITE_A : read and write access at the same time without conflict
// ST_CONFLICT_ACCESS_RD_A_WR_B : read and write at the same address
// ST_CONFLICT_ACCESS_RD_B_WR_A : read and write at the same address
// ST_RANDOM_ACCESS : random read and write accesses.
//
// Data have the following format : {wr_id, add}, where wr_id is writing identifier
// (depends on the state), and add is the current address.
// Note that in the last step : ST_RANDOM_ACCESS, wr_id is not checked, since, the bench does not
// control the read/write order.
// ==============================================================================================

module tb_ram_wrapper_2RW;
`timescale 1ns/10ps

  import ram_wrapper_pkg::*;

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int CLK_HALF_PERIOD = 1;
  localparam int ARST_ACTIVATION = 17;

  parameter int   RAM_LATENCY       = 1;
  parameter int   RD_WR_ACCESS_TYPE = 1;
  parameter bit   KEEP_RD_DATA      = 0;

  localparam int DEPTH      = 11; // For this bench, should be at least 8.
  localparam int DEPTH_W    = $clog2(DEPTH);
  localparam int WR_ID_W    = 3; // Write identifier width
  localparam int WIDTH      = WR_ID_W+DEPTH_W;   // For this bench, should be at least 2+clog2(DEPTH).
  localparam int MAX_ACCESS = DEPTH*8; // Number of read and write accesses in random access phase.

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
  // Port a
  logic                     a_en;
  logic                     a_wen;
  logic [DEPTH_W-1:0]       a_add;
  logic [WIDTH-1:0]         a_wr_data;
  logic [WIDTH-1:0]         a_rd_data;

  // Port b
  logic                     b_en;
  logic                     b_wen;
  logic [DEPTH_W-1:0]       b_add;
  logic [WIDTH-1:0]         b_wr_data;
  logic [WIDTH-1:0]         b_rd_data;

// ============================================================================================== --
// Design under test instance
// ============================================================================================== --
  ram_wrapper_2RW #(
    .WIDTH             (WIDTH            ),
    .DEPTH             (DEPTH            ),
    .RD_WR_ACCESS_TYPE (RD_WR_ACCESS_TYPE),
    .KEEP_RD_DATA      (KEEP_RD_DATA     ),
    .RAM_LATENCY       (RAM_LATENCY      )
  ) dut (
    .clk         (clk    ),
    .s_rst_n     (s_rst_n),

    .a_en        (a_en     ),
    .a_wen       (a_wen    ),
    .a_add       (a_add    ),
    .a_wr_data   (a_wr_data),
    .a_rd_data   (a_rd_data),

    .b_en        (b_en     ),
    .b_wen       (b_wen    ),
    .b_add       (b_add    ),
    .b_wr_data   (b_wr_data),
    .b_rd_data   (b_rd_data)
  );

// ============================================================================================== --
// Scenario
// ============================================================================================== --
// ---------------------------------------------------------------------------------------------- --
// FSM
// ---------------------------------------------------------------------------------------------- --
  typedef enum {ST_IDLE,
                ST_WR_A,
                ST_RD_B,
                ST_WR_B,
                ST_RD_A,
                ST_RD_A_WR_B,
                ST_RD_B_WR_A,
                ST_CONFLICT_ACCESS_RD_A_WR_B,
                ST_CONFLICT_ACCESS_RD_B_WR_A,
                ST_RANDOM_ACCESS,
                ST_DONE} state_e;
  state_e state;
  state_e next_state;
 
  logic start;
  logic [1:0] wr_done;
  logic [1:0] rd_done;
  int access_cnt;


  always_ff @(posedge clk) begin
    if (!s_rst_n) state <= ST_IDLE;
    else          state <= next_state;
  end

  always_comb begin
    case (state)
      ST_IDLE:
        next_state = start ? ST_WR_A : ST_IDLE;
      ST_WR_A:
        if (wr_done[0])
          next_state = ST_RD_B;
        else
          next_state = state;
      ST_RD_B:
        if (rd_done[1])
          next_state = ST_WR_B;
        else
          next_state = state;
      ST_WR_B:
        if (wr_done[1])
          next_state = ST_RD_A;
        else
          next_state = state;
      ST_RD_A:
        if (rd_done[0])
          next_state = ST_RD_B_WR_A;
        else
          next_state = state;
      ST_RD_B_WR_A:
        if (wr_done[0])
          next_state = ST_RD_A_WR_B;
        else
          next_state = state;
      ST_RD_A_WR_B:
        if (wr_done[1])
          next_state = ST_CONFLICT_ACCESS_RD_B_WR_A;
        else
          next_state = state;
      ST_CONFLICT_ACCESS_RD_B_WR_A:
        if (wr_done[0])
          next_state = ST_CONFLICT_ACCESS_RD_A_WR_B;
        else
          next_state = state;
      ST_CONFLICT_ACCESS_RD_A_WR_B:
        if (wr_done[1])
          next_state = ST_RANDOM_ACCESS;
        else
          next_state = state;
      ST_RANDOM_ACCESS:
        if (access_cnt >= MAX_ACCESS && (a_en || b_en))
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
  logic st_wr_a;
  logic st_rd_b;
  logic st_wr_b;
  logic st_rd_a;
  logic st_rd_a_wr_b;
  logic st_rd_b_wr_a;
  logic st_conflict_access_rd_a_wr_b;
  logic st_conflict_access_rd_b_wr_a;
  logic st_random_access;
  logic st_done;

  assign st_idle                      = (state == ST_IDLE);
  assign st_wr_a                      = (state == ST_WR_A);
  assign st_rd_b                      = (state == ST_RD_B);
  assign st_wr_b                      = (state == ST_WR_B);
  assign st_rd_a                      = (state == ST_RD_A);
  assign st_rd_a_wr_b                 = (state == ST_RD_A_WR_B);
  assign st_rd_b_wr_a                 = (state == ST_RD_B_WR_A);
  assign st_conflict_access_rd_a_wr_b = (state == ST_CONFLICT_ACCESS_RD_A_WR_B);
  assign st_conflict_access_rd_b_wr_a = (state == ST_CONFLICT_ACCESS_RD_B_WR_A);
  assign st_random_access             = (state == ST_RANDOM_ACCESS);
  assign st_done                      = (state == ST_DONE);

// ---------------------------------------------------------------------------------------------- --
// Control
// ---------------------------------------------------------------------------------------------- --
  logic [DEPTH_W-1:0] last_wr_add;
  logic [DEPTH_W-1:0] last_rd_add;
  logic                    a_parity;
  logic                    b_parity;

  logic [1:0]              en_a;
  logic [1:0]              wen_a;
  logic [1:0][DEPTH_W-1:0] add_a;
  logic [1:0][WIDTH-1:0]   wr_data_a;
  logic [1:0][WIDTH-1:0]   rd_data_a;
  logic [1:0]              parity_a;

  assign en_a      = {b_en, a_en};
  assign wen_a     = {b_wen, a_wen};
  assign add_a     = {b_add, a_add};
  assign wr_data_a = {b_wr_data, a_wr_data};
  assign rd_data_a = {b_rd_data, a_rd_data};
  assign parity_a  = {b_parity, a_parity};

  always_ff @(posedge clk) begin
    if (!s_rst_n) start <= 1'b0;
    else          start <= 1'b1;
  end

  assign last_wr_add = DEPTH-1;
  assign last_rd_add = (st_rd_a_wr_b || st_rd_b_wr_a) ? DEPTH/2-1 : DEPTH-1;

  always_comb begin
    for (int i=0; i<2; i=i+1) begin
      wr_done[i] = (add_a[i] == last_wr_add) & en_a[i] & wen_a[i];
      rd_done[i] = (add_a[i] == last_rd_add) & en_a[i] & ~wen_a[i];
    end
  end

  logic [WR_ID_W-1:0] wr_id;
  // b write odd wr_id (+ 1), a write even wr_id (+ 0).
  assign wr_id = (st_wr_a || st_wr_b || st_rd_a || st_rd_b) ? 0 :
                 (st_rd_a_wr_b || st_rd_b_wr_a) ? 2:
                 (st_conflict_access_rd_a_wr_b || st_conflict_access_rd_b_wr_a) ? 4:
                 6;

  always_ff @(posedge clk) begin
    if (!s_rst_n) access_cnt <= 0;
    else if (st_random_access) access_cnt <= access_cnt + a_en + b_en;
  end


// ---------------------------------------------------------------------------------------------- --
// Stimuli
// ---------------------------------------------------------------------------------------------- --
  logic [1:0][DEPTH_W-1:0] cnt;
  logic [1:0]              cnt_parity;
  logic [1:0][DEPTH_W-1:0] rand_add;
  logic [1:0]              rand_en;
  logic [1:0]              rand_wen;

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
      rand_wen[i] <= $urandom_range(1);
    end
  end

  assign a_wr_data = {wr_id, a_add};
  assign b_wr_data = {wr_id+1, b_add};
  always_comb begin
    case (state)
      ST_WR_A:
        begin
          a_en  = 1;
          b_en  = 0;
          a_wen = 1;
          b_wen = 'x;
          a_add = cnt[0];
          b_add = 'x;
          a_parity = cnt_parity[0];
          b_parity = 'x;
        end
      ST_WR_B:
        begin
          a_en  = 0;
          b_en  = 1;
          a_wen = 'x;
          b_wen = 1;
          a_add = 'x;
          b_add = cnt[0];
          a_parity = 'x;
          b_parity = cnt_parity[0];
        end
      ST_RD_A:
        begin
          a_en  = 1;
          b_en  = 0;
          a_wen = 0;
          b_wen = 'x;
          a_add = cnt[0];
          b_add = 'x;
          a_parity = cnt_parity[0];
          b_parity = 'x;
        end
      ST_RD_B:
        begin
          a_en  = 0;
          b_en  = 1;
          a_wen = 'x;
          b_wen = 0;
          a_add = 'x;
          b_add = cnt[0];
          a_parity = 'x;
          b_parity = cnt_parity[0];
        end
      ST_RD_A_WR_B:
        begin
          a_en  = 1;
          b_en  = 1;
          a_wen = 0;
          b_wen = 1;
          a_add = cnt[1];
          b_add = cnt[0];
          a_parity = cnt_parity[1];
          b_parity = cnt_parity[0];
        end
      ST_RD_B_WR_A:
        begin
          a_en  = 1;
          b_en  = 1;
          a_wen = 1;
          b_wen = 0;
          a_add = cnt[0];
          b_add = cnt[1];
          a_parity = cnt_parity[0];
          b_parity = cnt_parity[1];
        end
      ST_CONFLICT_ACCESS_RD_A_WR_B:
        begin
          a_en  = 1;
          b_en  = 1;
          a_wen = 0;
          b_wen = 1;
          a_add = cnt[0];
          b_add = cnt[0];
          a_parity = cnt_parity[0];
          b_parity = cnt_parity[0];
        end
      ST_CONFLICT_ACCESS_RD_B_WR_A:
        begin
          a_en  = 1;
          b_en  = 1;
          a_wen = 1;
          b_wen = 0;
          a_add = cnt[0];
          b_add = cnt[0];
          a_parity = cnt_parity[0];
          b_parity = cnt_parity[0];
        end
      ST_RANDOM_ACCESS:
        begin
          a_en  = rand_en[0];
          b_en  = rand_en[1];
          a_add = a_en ? rand_add[0] : 'x;
          b_add = b_en ? rand_add[1] : 'x;
          a_wen = a_en ? rand_wen[0] : 'x;
          b_wen = b_en ? (a_en && a_wen && a_add == b_add) ? 0 : rand_wen[1]
                       : 'x; // to avoid wr conflict
          a_parity = 'x;
          b_parity = 'x;
        end
      default:
        begin
          a_en  = 0;
          b_en  = 0;
          a_wen = 'x;
          b_wen = 'x;
          a_add = 'x;
          b_add = 'x;
          a_parity = 'x;
          b_parity = 'x;
        end
    endcase
  end

// ---------------------------------------------------------------------------------------------- --
// Check
// ---------------------------------------------------------------------------------------------- --
  logic [1:0] error_datar;
  logic [1:0] error_keep;

  logic [1:0] st_read;
  logic [1:0] st_read_and_write;
  logic [1:0] st_conflict_access;

  assign st_read            = {st_rd_b, st_rd_a};
  assign st_read_and_write  = {st_rd_b_wr_a, st_rd_a_wr_b};
  assign st_conflict_access = {st_conflict_access_rd_b_wr_a,st_conflict_access_rd_a_wr_b};

  genvar gen_i;
  generate
    for (gen_i=0; gen_i<2; gen_i=gen_i+1) begin : gen_loop
      int j; // other port
      assign j = (gen_i == 0) ? 1 : 0;

      logic access_conflict;
      logic [WIDTH-1:0] rd_data_ref_tmp;
      logic [RAM_LATENCY-1:0][WIDTH-1:0] rd_data_ref_dly;
      logic [RAM_LATENCY-1:0][WIDTH-1:0] rd_data_ref_dlyD;
      logic [RAM_LATENCY-1:0] rd_avail_dly;
      logic [RAM_LATENCY-1:0] rd_avail_dlyD;
      logic [DEPTH_W-1:0] rd_data_ref_lsb;

      assign access_conflict = en_a == 2'b11 & (add_a[0] == add_a[1]) &  ~wen_a[gen_i] & wen_a[j];
      assign rd_data_ref_lsb = (RD_WR_ACCESS_TYPE == RD_WR_ACCESS_TYPE_CONFLICT) ? 'x :
                               (RD_WR_ACCESS_TYPE == RD_WR_ACCESS_TYPE_READ_OLD) ? wr_id - (gen_i%2) : wr_id + 1 - (gen_i%2);
      assign rd_data_ref_tmp[DEPTH_W-1:0] = (access_conflict && (RD_WR_ACCESS_TYPE == RD_WR_ACCESS_TYPE_CONFLICT)) ? 'x: add_a[gen_i];
      assign rd_data_ref_tmp[DEPTH_W+:WR_ID_W] = st_read[gen_i]           ? wr_id + 1 - (gen_i%2):
                                                st_read_and_write[gen_i] ? (parity_a[0]!= parity_a[1]) ? wr_id + 1 - (gen_i%2) : wr_id - (gen_i%2):
                                                st_conflict_access[gen_i] ? rd_data_ref_lsb:
                                                st_random_access ? 'x : 'x; 

      assign rd_data_ref_dlyD[0] = rd_data_ref_tmp;
      assign rd_avail_dlyD[0]    = en_a[gen_i] & ~wen_a[gen_i];

      if (RAM_LATENCY>1) begin
        assign rd_data_ref_dlyD[RAM_LATENCY-1:1] = rd_data_ref_dly[RAM_LATENCY-2:0];
        assign rd_avail_dlyD[RAM_LATENCY-1:1]    = rd_avail_dly[RAM_LATENCY-2:0];
      end

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
      logic error_d;
      assign error_datar[gen_i] = error_d;
      always_ff @(posedge clk) begin
        if (!s_rst_n) begin
          error_d <= 1'b0;
        end
        else begin
          if (rd_avail_dly[RAM_LATENCY-1]) begin
            assert(rd_data_a[gen_i][DEPTH_W-1:0] === rd_data_ref_dly[RAM_LATENCY-1][DEPTH_W-1:0])
            else begin
              error_d <= 1'b1;
              $error("> ERROR: Datar mismatches [%d]: exp=0x%0x seen=0x%0x",gen_i, rd_data_ref_dly[RAM_LATENCY-1][DEPTH_W-1:0],rd_data_a[gen_i][DEPTH_W-1:0]);
            end
          
            if (rd_data_ref_dly[RAM_LATENCY-1][DEPTH_W+:2] !== 2'bxx)
              assert(rd_data_a[gen_i][DEPTH_W+:2] === rd_data_ref_dly[RAM_LATENCY-1][DEPTH_W+:2])
              else begin
                error_d <= 1'b1;
                $error("> ERROR: Datar MSB mismatches [%d]: exp=0x%0x seen=0x%0x",gen_i,rd_data_ref_dly[RAM_LATENCY-1][DEPTH_W+:2],rd_data_a[gen_i][DEPTH_W+:2]);
              end
          end
        end
      end

      // check KEEP_RD_DATA
      logic error_k;
      assign error_keep[gen_i] = error_k;
      if (KEEP_RD_DATA != 0) begin: keep_data_check_gen
        logic [WIDTH-1:0] rd_data_dly;
        logic             start_check_keep_datar;
        always_ff @(posedge clk)
          if (!s_rst_n) start_check_keep_datar <= 1'b0;
          else          start_check_keep_datar <= rd_avail_dly[RAM_LATENCY-1] ? 1'b1 : start_check_keep_datar;
        always_ff @(posedge clk) begin
          if (rd_avail_dly[RAM_LATENCY-1])
            rd_data_dly <= rd_data_a[gen_i];
        end

        always_ff @(posedge clk) begin
          if (!s_rst_n)
            error_k <= 1'b0;
          else
            if (start_check_keep_datar) begin
              if (!rd_avail_dly[RAM_LATENCY-1])
                assert(rd_data_a[gen_i] === rd_data_dly)
                else begin
                  error_k <= 1'b1;
                  $error("> ERROR: Datar not kept [%d]: exp=0x%0x, seen=0x%0x",gen_i,rd_data_dly,rd_data_a[gen_i]);
                end
            end
        end
      end
      else begin
        assign error_k = 1'b0;
      end
    end // for gen_i
  endgenerate

  assign error = |error_keep | |error_datar;

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
