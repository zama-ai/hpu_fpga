// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This testbench checks ntt_core_gf64_phi_rom.
// ==============================================================================================

module tb_ntt_core_gf64_phi_rom;

`timescale 1ns/10ps

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int CLK_HALF_PERIOD = 1;
  localparam int ARST_ACTIVATION = 17;

  parameter  int N_L                = 2048;
  localparam int R                  = 2; // Do not modify
  parameter  int PSI                = 32; // Should be a power of 2
  parameter  int OP_W               = 16;
  parameter  int ROM_LATENCY        = 2;
  parameter  string TWD_GF64_FILE_PREFIX = "input/twd_phi";

  localparam int ITER_NB            = N_L / (R*PSI);
  parameter  int LVL_NB             = 2;

  parameter  int LOOP_NB = 100;
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
  bit error_vld;

  assign error = error_data | error_vld;

  always_ff @(posedge clk)
    if (error) begin
      $display("%t > FAILURE !", $time);
      $finish;
    end

// ============================================================================================== --
// input / output signals
// ============================================================================================== --
  logic [PSI-1:0][R-1:0][OP_W-1:0] twd_phi;
  logic [PSI-1:0]                  twd_phi_vld;
  logic [PSI-1:0]                  twd_phi_rdy;

// ============================================================================================== --
// Design under test instance
// ============================================================================================== --
  ntt_core_gf64_phi_rom #(
      .N_L             (N_L),
      .R               (R),
      .PSI             (PSI),
      .OP_W            (OP_W),
      .LVL_NB          (LVL_NB),
      .TWD_GF64_FILE_PREFIX (TWD_GF64_FILE_PREFIX),
      .ROM_LATENCY     (ROM_LATENCY)
  ) dut (
    .clk         (clk    ),
    .s_rst_n     (s_rst_n),

    .twd_phi     (twd_phi    ),
    .twd_phi_vld (twd_phi_vld),
    .twd_phi_rdy (twd_phi_rdy)
  );

// ============================================================================================== --
// Scenario
// ============================================================================================== --
  logic out_rdy;
  logic out_vld;

  assign out_vld = twd_phi_vld[0];
  assign twd_phi_rdy = {R*PSI{out_rdy}};

  always_ff @(posedge clk)
    if (!s_rst_n) out_rdy <= 1'b0;
    else          out_rdy <= $urandom();


  integer out_cnt;
  integer loop_cnt;
  integer out_lvl;
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      out_cnt  <= '0;
      loop_cnt <= '0;
      out_lvl  <= '0;
    end
    else begin
      out_lvl  <= (out_vld && out_rdy) ? (out_lvl + 1)%LVL_NB : out_lvl;
      out_cnt  <= (out_vld && out_rdy && (out_lvl == (LVL_NB-1))) ? (out_cnt + 1)%ITER_NB : out_cnt;
      loop_cnt <= (out_vld && out_rdy && (out_lvl == (LVL_NB-1)) && (out_cnt == (ITER_NB-1))) ? loop_cnt + 1: loop_cnt;
    end

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      error_data <= 1'b0;
      error_vld  <= 1'b0;
    end
    else begin
      assert(twd_phi_vld == '1 || twd_phi_vld == '0)
      else begin
        $display("%t > ERROR: twd_phi_vld bits are incoherent!", $time);
        error_vld <= 1'b1;
      end

      if (out_vld && out_rdy) begin
        for (int p=0; p<PSI; p=p+1)
          for (int r=0; r<R; r=r+1)
            assert(twd_phi[p][r] == (out_cnt * PSI * R + p*R + r))
            else begin
              $display("%t > ERROR: Mismatch twd_phi[%0d][%0d] exp=0x%0x seen=0x%0x", $time, p, r, (out_cnt * PSI * R + p*R + r), twd_phi[p][r]);
              error_data <= 1'b1;
            end
      end
    end
// ============================================================================================== --
// End of test
// ============================================================================================== --
  initial begin
    end_of_test = 1'b0;
    wait (loop_cnt == LOOP_NB);
    @(posedge clk);
    end_of_test = 1'b1;
  end

endmodule
