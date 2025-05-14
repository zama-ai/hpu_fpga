// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : 1R ROM tb
// ----------------------------------------------------------------------------------------------
//
// Testbench testing all values of the read-only memory of size DEPTH.
// Read enable is random and stalls simulation when not ready.
// Number of tries and hits on the memory is notified at the end of the testbench
//
// ==============================================================================================

module tb_rom_wrapper_1R;
  `timescale 1ns/10ps

  parameter int ROM_LATENCY       = 1;
  parameter int KEEP_RD_DATA      = 0;
  // ============================================================================================ //
  // localparam
  // ============================================================================================ //
  localparam string FILENAME        = "memory_file/rom_test/test_64.mem";
  localparam        WIDTH           = 32;
  localparam        DEPTH           = 64;

  localparam CLK_HALF_PERIOD = 1;
  localparam ARST_ACTIVATION = 17;
  // Number of read and write accesses in random access phase.
  localparam int  MAX_ACCESS = DEPTH * 2;
  localparam int  DEPTH_W = $clog2(DEPTH);

  // ============================================================================================ //
  // clock, reset
  // ============================================================================================ //
  bit clk;
  bit a_rst_n;
  bit s_rst_n;

  initial begin
    clk     = 1'b0;
    a_rst_n = 1'b0;
    #ARST_ACTIVATION a_rst_n = 1'b1;
  end

  always begin
    #CLK_HALF_PERIOD clk = ~clk;
  end

  always_ff @(posedge clk) begin
    s_rst_n <= a_rst_n;
  end

  // ============================================================================================ //
  // End of test
  // ============================================================================================ //
  bit end_of_test;
  int cnt_pass;
  int cnt;

  assign end_of_test = (cnt_pass == MAX_ACCESS);

  initial begin
    wait (end_of_test);
    @(posedge clk) begin
      $display("%t > SUCCEED !", $time);
      $display("%t > INFO: %0d tries %0d Hits", $time, cnt + 1, cnt_pass);
    end
    $finish;
  end

  // ============================================================================================ //
  // Error
  // ============================================================================================ //
  bit error;

  always_ff @(posedge clk)
    if (error) begin
      $display("%t > FAILURE !", $time);
      $finish;
    end

  // ============================================================================================ //
  // input / output signals
  // ============================================================================================ //
  // Read port
  logic               rd_en;
  logic [DEPTH_W-1:0] rd_add;
  logic [  WIDTH-1:0] rd_data;

  logic               start;
  always_ff @(posedge clk)
    if (!s_rst_n) start <= 0;
    else start <= 1;

  // ============================================================================================ //
  // Design under test instance
  // ============================================================================================ //
  rom_wrapper_1R #(
    .FILENAME    (FILENAME),
    .WIDTH       (WIDTH),
    .DEPTH       (DEPTH),
    .KEEP_RD_DATA(KEEP_RD_DATA),
    .ROM_LATENCY (ROM_LATENCY)
  ) dut (
    // system interface
    .clk    (clk),
    .s_rst_n(s_rst_n),
    // data interface
    .rd_en  (rd_en),
    .rd_add (rd_add),
    .rd_data(rd_data)
  );

  // ============================================================================================ //
  // Stimuli
  // ============================================================================================ //

  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      cnt <= 0;
    end else begin
      if (start) begin
        rd_en  <= $random();
        rd_add <= $random();

        if (rd_en) begin
          cnt <= cnt + 1;
        end

      end
    end
  end

  // ============================================================================================ //
  // Checker
  // ============================================================================================ //
  logic [      WIDTH-1:0]            mem               [DEPTH-1:0];
  logic [ROM_LATENCY-1:0][DEPTH-1:0] rd_data_ref;
  logic [ROM_LATENCY-1:0]            rd_data_ref_ready;

  // reading the memory file
  initial begin
    $readmemh(FILENAME, mem, 0, DEPTH - 1);
  end


  always_ff @(posedge clk) begin
    rd_data_ref_ready[0] <= rd_en;
    if (ROM_LATENCY > 1) begin
      rd_data_ref_ready[ROM_LATENCY-1:1] <= rd_data_ref_ready[ROM_LATENCY-2:0];;
    end
  end

  always_ff @(posedge clk) begin
    if (ROM_LATENCY > 1) begin
      rd_data_ref[ROM_LATENCY-1:1] <= rd_data_ref[ROM_LATENCY-2:0];
    end

    if (rd_en) begin
      rd_data_ref[0] <= mem[rd_add];
    end
  end

  always_ff @(posedge clk) begin
    if (~s_rst_n) begin
      error    <= 0;
      cnt_pass <= 1;
    end else begin
        if (rd_data_ref_ready[ROM_LATENCY-1]) begin
          assert (rd_data_ref[ROM_LATENCY-1] == rd_data) begin
            cnt_pass = cnt_pass + 1;
          end else begin
            $display("%t > ERROR: Datar not kept: exp=0x%0d, seen=0x%0d", $time, rd_data_ref,
                   rd_data);
            error <= 1;
          end
      end
    end
  end

endmodule
