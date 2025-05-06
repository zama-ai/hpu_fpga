// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// stream_dispatch testbench.
// ==============================================================================================

module tb_stream_dispatch;

`timescale 1ns/10ps

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int CLK_HALF_PERIOD = 1;
  localparam int ARST_ACTIVATION = 17;

  localparam int RAND_RANGE = 1024-1;

  parameter int OP_W      = 32;
  parameter int IN_COEF   = 16;
  parameter int OUT_COEF  = 4;
  parameter int OUT_NB    = 1;
  parameter int DISP_COEF = 8; // consecutive coef for each output
  parameter bit IN_PIPE   = 1'b1;
  parameter bit OUT_PIPE  = 1'b1;

  parameter int OUT_SAMPLE_NB = 10000;
  parameter int IN_SAMPLE_NB  = (OUT_SAMPLE_NB * DISP_COEF * OUT_NB + (IN_COEF-1)) / IN_COEF;
  parameter int OUT_ITER_NB   = DISP_COEF / OUT_COEF;

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
  logic [OUT_NB-1:0] error_data_a;

  assign error = |error_data_a;

  always_ff @(posedge clk)
    if (error) begin
      $display("%t > FAILURE !", $time);
      $finish;
    end

// ============================================================================================== --
// input / output signals
// ============================================================================================== --
  logic [IN_COEF-1:0][OP_W-1:0]              in_data;
  logic                                      in_vld;
  logic                                      in_rdy;

  logic [OUT_NB-1:0][OUT_COEF-1:0][OP_W-1:0] out_data;
  logic [OUT_NB-1:0]                         out_vld;
  logic [OUT_NB-1:0]                         out_rdy;

// ============================================================================================== --
// Design under test instance
// ============================================================================================== --
  stream_dispatch #(
    .OP_W      (OP_W),
    .IN_COEF   (IN_COEF),
    .OUT_COEF  (OUT_COEF),
    .OUT_NB    (OUT_NB),
    .DISP_COEF (DISP_COEF),
    .IN_PIPE   (IN_PIPE),
    .OUT_PIPE  (OUT_PIPE)
  ) dut (
    .clk     (clk    ),
    .s_rst_n (s_rst_n),

    .in_data (in_data),
    .in_vld  (in_vld),
    .in_rdy  (in_rdy),

    .out_data(out_data),
    .out_vld (out_vld),
    .out_rdy (out_rdy)
  );

// ============================================================================================== --
// Scenario
// ============================================================================================== --
// Send a data containing increasing values => ease the attribution of each data.
  //== Input
  integer in_cnt;
  stream_source
  #(
    .FILENAME   ("counter"),
    .DATA_TYPE  ("ascii_hex"),
    .DATA_W     (32),
    .RAND_RANGE (RAND_RANGE),
    .KEEP_VLD   (1),
    .MASK_DATA  ("x")
  )
  source_in
  (
    .clk        (clk),
    .s_rst_n    (s_rst_n),

    .data       (in_cnt),
    .vld        (in_vld),
    .rdy        (in_rdy),

    .throughput ('0)
  );

  always_comb
    for (int c=0; c<IN_COEF; c=c+1)
      in_data[c] = in_cnt * IN_COEF + c;

  initial begin
    if (!source_in.open()) begin
      $fatal(1, "%t > ERROR: Opening source_in stream source", $time);
    end
    wait(s_rst_n);
    @(posedge clk);
    source_in.start(IN_SAMPLE_NB);
  end

  //== Output
  logic [OUT_NB-1:0] out_done;
  generate
    for (genvar gen_i=0; gen_i<OUT_NB; gen_i=gen_i+1) begin : gen_loop
      stream_sink
      #(
        .FILENAME_REF   (""),
        .FILENAME       (""),
        .DATA_TYPE_REF  ("ascii_hex"),
        .DATA_TYPE      ("ascii_hex"),
        .DATA_W         (1),
        .RAND_RANGE     (RAND_RANGE),
        .KEEP_RDY       (1'b0)
      ) sink_out (
        .clk        (clk),
        .s_rst_n    (s_rst_n),

        .data       (1'bx), /*UNUSED*/
        .vld        (out_vld[gen_i]),
        .rdy        (out_rdy[gen_i]),

        .error      (/*UNUSED*/),
        .throughput ('0)
      );

      logic out_done_l;
      assign out_done[gen_i] = out_done_l;
      initial begin
        out_done_l = 1'b0;

        sink_out.set_do_ref(0);
        sink_out.set_do_write(0);

        wait(s_rst_n);
        @(posedge clk);
        sink_out.start(OUT_SAMPLE_NB*OUT_ITER_NB);
        wait (sink_out.running);
        $display("%t > INFO: Sink %0d Running==1",$time, gen_i);
        wait (!sink_out.running);
        $display("%t > INFO: Sink %0d Running==0",$time, gen_i);

        @(posedge clk);
        out_done_l = 1'b1;
      end

      //== Check
      integer out_word_cnt;
      integer out_part_cnt;

      always_ff @(posedge clk)
        if (!s_rst_n) begin
          out_word_cnt <= '0;
          out_part_cnt <= '0;
        end
        else begin
          if (out_vld[gen_i] && out_rdy[gen_i]) begin
            out_part_cnt <= (out_part_cnt == OUT_ITER_NB-1) ? '0 : out_part_cnt + 1;
            out_word_cnt <= (out_part_cnt == OUT_ITER_NB-1) ? out_word_cnt + 1 : out_word_cnt;

            if (out_word_cnt % 1000 == 0 && (out_part_cnt == OUT_ITER_NB-1)) begin
              $display("%t > INFO : Out[%0d] Output word #%0d", $time, gen_i,out_word_cnt);
            end
          end
        end

      logic error_data_l;
      assign error_data_a[gen_i] = error_data_l;
      always_ff @(posedge clk)
        if (!s_rst_n) begin
          error_data_l <= 1'b0;
        end
        else begin
          if (out_vld[gen_i] && out_rdy[gen_i]) begin
            for (int i=0; i<OUT_COEF; i=i+1) begin
              integer ref_d;
              ref_d = out_word_cnt * OUT_NB * DISP_COEF + gen_i * DISP_COEF + out_part_cnt * OUT_COEF + i;
              assert(out_data[gen_i][i] == ref_d)
              else begin
                $display("%t > ERROR: Mismatch data out[%0d][%0d] exp=0x%0x seen=0x%0x",$time,gen_i,i,ref_d,out_data[gen_i][i]);
                error_data_l <= 1'b1;
              end
            end

          end
        end
    end
  endgenerate

// ============================================================================================== --
// End of test
// ============================================================================================== --
  initial begin
    end_of_test = 1'b0;
    wait(s_rst_n);
    wait(&out_done);
    @(posedge clk)
      end_of_test = 1'b1;
  end

endmodule
