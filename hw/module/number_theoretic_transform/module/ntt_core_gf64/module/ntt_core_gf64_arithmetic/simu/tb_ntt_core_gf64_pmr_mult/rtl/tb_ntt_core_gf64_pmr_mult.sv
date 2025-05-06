// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Check arith_mult_core.
//
// ==============================================================================================

module tb_ntt_core_gf64_pmr_mult;
`timescale 1ns/10ps

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int CLK_HALF_PERIOD = 1;
  localparam int ARST_ACTIVATION = 17;

  parameter  int          MOD_NTT_W  = 64;
  parameter  int          OP_W       = MOD_NTT_W+2;

  parameter  bit          PROC_ALL   = OP_W < 24;
  parameter  int          RESULT_NB  = PROC_ALL ? 2**OP_W : 10_000_000;

  localparam [MOD_NTT_W-1:0] MOD_M   = 2**MOD_NTT_W - 2**(MOD_NTT_W/2) + 1;
  localparam bit          IN_PIPE    = 1;

  localparam int          SIDE_W     = 1*OP_W;
  localparam [1:0]        RST_SIDE   = 2'b01;

  localparam int          LATENCY = 1 + IN_PIPE;

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
  bit error_result;
  bit error_side;

  assign error =  error_result
                | error_side;

  always_ff @(posedge clk)
    if (error) begin
      $display("%t > FAILURE !", $time);
      $finish;
    end

// ============================================================================================== --
// input / output signals
// ============================================================================================== --
  logic [OP_W-1:0]      a; // 2s complement
  logic [MOD_NTT_W+1:0] z;

  logic [MOD_NTT_W-1:0] m; // unsigned
  logic                 m_vld;
  logic                 m_rdy;

  logic                 in_avail;
  logic                 out_avail;
  logic [SIDE_W-1:0]    in_side;
  logic [SIDE_W-1:0]    out_side;

// ============================================================================================== --
// Design under test instance
// ============================================================================================== --
  ntt_core_gf64_pmr_mult #(
    .OP_W           (OP_W          ),
    .MOD_NTT_W      (MOD_NTT_W     ),
    .IN_PIPE        (IN_PIPE       ),
    .SIDE_W         (SIDE_W        ),
    .RST_SIDE       (RST_SIDE      )
  ) dut (
    .clk       (clk),
    .s_rst_n   (s_rst_n),
    .a         (a),
    .z         (z),
    
    .m         (m),
    .m_vld     (m_vld),
    .m_rdy     (m_rdy),

    .in_avail  (in_avail),
    .out_avail (out_avail),
    .in_side   (in_side),
    .out_side  (out_side)
  );

// ============================================================================================== --
// Scenario
// ============================================================================================== --
  logic [OP_W-1:0] b;
  assign in_side = b;

  stream_source #(
    .FILENAME   (PROC_ALL ? "counter" : "random"),
    .DATA_TYPE  ("ascii_hex"), // UNUSED
    .DATA_W     (OP_W + OP_W),
    .RAND_RANGE (2**32-1),
    .KEEP_VLD   (0),
    .MASK_DATA  ("none")
  ) source (
      .clk     (clk),
      .s_rst_n (s_rst_n),

      .data    ({b,a}),
      .vld     (in_avail),
      .rdy     (1'b1),

      .throughput(0)
  );

  stream_source #(
    .FILENAME   ("random"),
    .DATA_TYPE  ("ascii_hex"), // UNUSED
    .DATA_W     (MOD_NTT_W),
    .RAND_RANGE (15),
    .KEEP_VLD   (1),
    .MASK_DATA  ("none")
  ) m_source (
      .clk     (clk),
      .s_rst_n (s_rst_n),

      .data    (m),
      .vld     (m_vld),
      .rdy     (m_rdy),

      .throughput(15)
  );

  integer out_cnt;
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      out_cnt  <= 0;
    end
    else begin
      if (out_avail && (out_cnt % 10000) == 0)
        $display("%t > INFO: Output # %d", $time, out_cnt);
      out_cnt  <= out_avail ? out_cnt + 1 : out_cnt;
    end

  initial begin
    int r0, r1;
    end_of_test <= 1'b0;
    r0 = source.open();
    r1 = m_source.open();
    wait(s_rst_n);
    @(posedge clk);
    source.start(RESULT_NB);
    m_source.start(RESULT_NB);
    wait(out_cnt == RESULT_NB);
    @(posedge clk) end_of_test <= 1'b1;
  end


// ============================================================================================== --
// Check
// ============================================================================================== --
// === Check data
  logic [OP_W-1:0]      a_q[$];
  logic [MOD_NTT_W-1:0] result_q[$];
  logic [SIDE_W-1:0]    side_q[$];

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      error_result <= 0;
      error_side   <= 0;
    end
    else begin
      if (in_avail) begin
        a_q.push_back(a);
        side_q.push_back(in_side);
      end
      if (m_vld && m_rdy) begin
        logic[OP_W-1:0] a_val;
        logic[OP_W-1:0] a_abs;

        logic[OP_W+MOD_NTT_W-1:0] mult_abs;
        logic[MOD_NTT_W-1:0] mult_abs_reduc;
        logic[MOD_NTT_W-1:0] mult_reduc;
        logic         sign;
        a_val          = a_q.pop_front();
        sign           = a_val[OP_W-1];
        a_abs          = sign ? (1 << OP_W) - a_val[OP_W-1:0] : a_val[OP_W-1:0];

        mult_abs       = a_abs * m;
        mult_abs_reduc = mult_abs - (mult_abs/MOD_M)*MOD_M;
        mult_reduc     = (sign && (mult_abs_reduc!=0)) ? MOD_M - mult_abs_reduc : mult_abs_reduc;

        result_q.push_back(mult_reduc);
      end
      if (out_avail) begin
        logic [MOD_NTT_W-1:0] ref_result;
        logic [SIDE_W-1:0]    ref_side;
        logic [MOD_NTT_W-1:0] res_reduct;
        logic                 res_sign;
        logic [MOD_NTT_W:0]   res_abs;
        logic [MOD_NTT_W-1:0] res_abs_reduct;

        ref_result = result_q.pop_front();
        ref_side   = side_q.pop_front();

        res_sign = z[MOD_NTT_W+1];
        res_abs  = res_sign ? (1 << MOD_NTT_W+1)-z[MOD_NTT_W:0] : z[MOD_NTT_W:0];
        res_abs_reduct = res_abs - (res_abs/MOD_M)*MOD_M;
        res_reduct = (res_sign && (res_abs_reduct!=0)) ? MOD_M - res_abs_reduct : res_abs_reduct;

        assert(ref_result == res_reduct)
        else begin
          $display("%t > ERROR: Result mismatches: reduced exp=0x%0x seen=0x%0x (seen=0x%0x)",$time, ref_result, res_reduct,z);
          error_result <= 1;
        end
        assert(ref_side == out_side)
        else begin
          $display("%t > ERROR: Side mismatches: exp=0x%0x seen=0x%0x",$time, ref_side, out_side);
          error_side <= 1;
        end

      end
    end

endmodule
