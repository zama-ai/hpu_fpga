// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Testbench to check ngc/cyc radix NTT/INTT
// ==============================================================================================

module tb_ntt_core_gf64_bu_radix;
  import param_ntt_pkg::*;
  import ntt_core_common_param_pkg::*;

`timescale 1ns/10ps

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int CLK_HALF_PERIOD = 1;
  localparam int ARST_ACTIVATION = 17;

  localparam int    SIDE_W     = 16;
  localparam [1:0]  RST_SIDE   = 0;

  parameter bit IS_NGC = 1'b0;
  localparam int S_INIT = IS_NGC ? 0 : 5;

  localparam int STG = $clog2(R*PSI);
  localparam int NN  = 2**STG; // bench NTT size

  parameter int SAMPLE_NB = 100;

  generate
    if (IS_NGC) begin : check_ngc
      if (R*PSI > 32) begin : _UNSUPPORTED_R_PSI
        $fatal(1,"> ERROR: For this testbench, only support ngc NTT up to 32");
      end
    end
    else begin : check_cyc
      if (R*PSI > 64) begin : _UNSUPPORTED_R_PSI
        $fatal(1,"> ERROR: For this testbench, only support cyc NTT up to 64");
      end
    end
  endgenerate

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
  bit ntt_error;
  bit ntt_side_error;

  assign error = ntt_error
                | ntt_side_error;

  always_ff @(posedge clk)
    if (error) begin
      $display("%t > FAILURE !", $time);
      $finish;
    end

// ============================================================================================== --
// input / output signals
// ============================================================================================== --
  logic [PSI*R-1:0][MOD_NTT_W+1:0] in_data;
  logic [PSI*R-1:0][MOD_NTT_W+1:0] out_data;
  logic [PSI*R-1:0]                in_avail;
  logic [PSI*R-1:0]                out_avail;
  logic [SIDE_W-1:0]               in_side;
  logic [SIDE_W-1:0]               out_side;
  
  logic [STG:0][PSI*R-1:0][MOD_NTT_W+1:0] ntt_data;
  logic [STG:0][PSI*R-1:0]                ntt_avail;
  logic [STG:0][SIDE_W-1:0]               ntt_side;

  logic [STG:0][PSI*R-1:0][MOD_NTT_W+1:0] intt_data;
  logic [STG:0][PSI*R-1:0]                intt_avail;
  logic [STG:0][SIDE_W-1:0]               intt_side;

// ============================================================================================== --
// Design under test instance
// ============================================================================================== --
  assign ntt_data[0]  = in_data;
  assign ntt_avail[0] = in_avail;
  assign ntt_side[0]  = in_side;

  assign intt_data[STG]  = ntt_data[STG];
  assign intt_avail[STG] = ntt_avail[STG];
  assign intt_side[STG]  = ntt_side[STG];

  assign out_data  = intt_data[0];
  assign out_side  = intt_side[0];
  assign out_avail = intt_avail[0];
  generate
    for (genvar  gen_i=0; gen_i<STG; gen_i=gen_i+1) begin : gen_loop
      ntt_core_gf64_bu_stage_column_fwd
      #(
        .NTT_STG_ID (S_INIT + gen_i),
        .IN_PIPE    (gen_i==0),
        .SIDE_W     (SIDE_W),
        .RST_SIDE   (RST_SIDE)
      ) ntt_core_gf64_bu_stage_column_fwd (
        .clk       (clk),
        .s_rst_n   (s_rst_n),

        .in_data   (ntt_data[gen_i]),
        .out_data  (ntt_data[gen_i+1]),
        .in_avail  (ntt_avail[gen_i]),
        .out_avail (ntt_avail[gen_i+1]),
        .in_side   (ntt_side[gen_i]),
        .out_side  (ntt_side[gen_i+1])
      );


      ntt_core_gf64_bu_stage_column_bwd
      #(
        .NTT_STG_ID (S_INIT + gen_i),
        .IN_PIPE    (gen_i==STG-1),
        .SIDE_W     (SIDE_W),
        .RST_SIDE   (RST_SIDE)
      ) ntt_core_gf64_bu_stage_column_bwd (
        .clk       (clk),
        .s_rst_n   (s_rst_n),

        .in_data   (intt_data[gen_i+1]),
        .out_data  (intt_data[gen_i]),
        .in_avail  (intt_avail[gen_i+1]),
        .out_avail (intt_avail[gen_i]),
        .in_side   (intt_side[gen_i+1]),
        .out_side  (intt_side[gen_i])
      );

    end
  endgenerate

// ============================================================================================== --
// Scenario
// ============================================================================================== --
  logic [PSI*R-1:0][MOD_NTT_W-1:0] data_q[$];
  logic [SIDE_W-1:0]               side_q[$];

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      in_avail <= '0;
      in_data  <= 'x;
      in_side  <= 'x;
    end
    else begin
      var tmp_avail;
      tmp_avail = $urandom();
      in_avail <= {PSI*R{tmp_avail}};
      for (int i=0; i<R*PSI; i=i+1)
        in_data[i]  <= {$urandom(),$urandom()};
      in_side  <= $urandom();
    end

  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      ntt_error      <= 1'b0;
      ntt_side_error <= 1'b0;
    end
    else begin
      if (in_avail[0]) begin
        logic [PSI*R-1:0][MOD_NTT_W-1:0] data_reduct;
        side_q.push_back(in_side);
        for (int i=0; i<R*PSI; i=i+1) begin
          logic                 data_sign;
          logic [MOD_NTT_W+1:0] data_abs;
          logic [MOD_NTT_W+S+1:0] data_abs_xNN;
          logic [MOD_NTT_W-1:0] data_abs_reduct;
          data_sign = in_data[i][MOD_NTT_W+1];
          data_abs  = data_sign ?  (1 << MOD_NTT_W+1)-in_data[i][MOD_NTT_W:0] : in_data[i][MOD_NTT_W:0];
          data_abs_xNN = data_abs * NN; // In this testbench, there is no multiplication by 1/NN
          data_abs_reduct = data_abs_xNN - (data_abs_xNN/MOD_NTT)*MOD_NTT;
          data_reduct[i] = (data_sign && (data_abs_reduct!=0)) ? MOD_NTT - data_abs_reduct : data_abs_reduct;
        end
        data_q.push_back(data_reduct);
      end

      if (out_avail[0]) begin
        logic [SIDE_W-1:0]               ref_side;
        logic [PSI*R-1:0][MOD_NTT_W-1:0] ref_data;
        // Check side
        ref_side = side_q.pop_front();
        assert (ref_side == out_side)
        else begin
          $display("%t > ERROR: Side mismatch : exp=0x%0x seen=0x%0x",$time, ref_side, out_side);
          ntt_side_error <= 1'b1;
        end

        // Check data
        ref_data = data_q.pop_front();
        for (int i=0; i<R*PSI; i=i+1) begin
          logic                 res_sign;
          logic [MOD_NTT_W+1:0] res_abs;
          logic [MOD_NTT_W-1:0] res_abs_reduct;
          logic [MOD_NTT_W-1:0] res_reduct;
          res_sign = out_data[i][MOD_NTT_W+1];
          res_abs  = res_sign ?  (1 << MOD_NTT_W+1)-out_data[i][MOD_NTT_W:0] : out_data[i][MOD_NTT_W:0];
          res_abs_reduct = res_abs - (res_abs/MOD_NTT)*MOD_NTT;
          res_reduct = (res_sign && (res_abs_reduct!=0)) ? MOD_NTT - res_abs_reduct : res_abs_reduct;

          assert(ref_data[i] == res_reduct)
          else begin
            $display("%t > ERROR: data[%0d] mismatch : exp=0x%0x seen=0x%0x",$time, i, ref_data[i], res_reduct);
            ntt_error <= 1'b1;
          end
        end
      end
    end
  end

// ============================================================================================== --
// End of test
// ============================================================================================== --
  integer out_cnt;
  always_ff @(posedge clk)
    if (!s_rst_n) out_cnt <= '0;
    else          out_cnt <= out_avail[0] ? out_cnt + 1 : out_cnt;

  initial begin
    end_of_test = 1'b0;
    wait (out_cnt == SAMPLE_NB);
    @(posedge clk);
    end_of_test = 1'b1;
  end


endmodule
