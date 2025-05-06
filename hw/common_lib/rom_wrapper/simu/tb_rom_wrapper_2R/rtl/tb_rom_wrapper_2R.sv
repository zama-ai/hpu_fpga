// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : 2R ROM tb
// ----------------------------------------------------------------------------------------------
//
// Testbench testing all values of the read-only memory of size DEPTH.
// Read enable is random and stalls simulation when not ready.
// Number of tries and hits on the memory is notified at the end of the testbench
//
// ==============================================================================================

module tb_rom_wrapper_2R;
  `timescale 1ns/10ps

  parameter         KEEP_RD_DATA    = 0;
  parameter         ROM_LATENCY     = 1;

  // ============================================================================================ //
  // localparam
  // ============================================================================================ //
  localparam string FILENAME        = "memory_file/rom_test/test_64.mem";
  localparam        WIDTH           = 33;
  localparam        DEPTH           = 64;

  localparam CLK_HALF_PERIOD        = 1;
  localparam ARST_ACTIVATION        = 17;

  // Number of read and write accesses in random access phase.
  localparam int MAX_ACCESS         = DEPTH * 2;
  localparam int DEPTH_W            = $clog2(DEPTH);

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

  assign end_of_test = (cnt == MAX_ACCESS) ? 1 : 0;

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
  logic error_d;
  logic [1:0] error_k;

  assign error = error_d | (|error_k);

  always_ff @(posedge clk)
    if (error) begin
      $display("%t > FAILURE !", $time);
      $finish;
    end

  // ============================================================================================ //
  // input / output signals
  // ============================================================================================ //
  // Read port
  logic               a_rd_en;
  logic [DEPTH_W-1:0] a_rd_add;
  logic [  WIDTH-1:0] a_rd_data;
  logic               b_rd_en;
  logic [DEPTH_W-1:0] b_rd_add;
  logic [  WIDTH-1:0] b_rd_data;

  logic               start;

  always_ff @(posedge clk)
    if (!s_rst_n) start <= 0;
    else start <= 1;

  // ============================================================================================ //
  // Design under test instance
  // ============================================================================================ //
  rom_wrapper_2R #(
    .FILENAME    (FILENAME),
    .WIDTH       (WIDTH),
    .DEPTH       (DEPTH),
    .KEEP_RD_DATA(KEEP_RD_DATA),
    .ROM_LATENCY (ROM_LATENCY)
  ) dut (
    // system interface
    .clk      (clk),
    .s_rst_n  (s_rst_n),
    // data interface a
    .a_rd_en  (a_rd_en),
    .a_rd_add (a_rd_add),
    .a_rd_data(a_rd_data),
    // data interface b
    .b_rd_en  (b_rd_en),
    .b_rd_add (b_rd_add),
    .b_rd_data(b_rd_data)
  );

  // ============================================================================================ //
  // Stimuli
  // ============================================================================================ //

  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      cnt <= 0;
    end else begin
      if (start) begin
        if ((a_rd_en & b_rd_en)) begin
          cnt <= cnt + 1;
        end
      end
    end
  end

  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      b_rd_en  <= 0;
      a_rd_en  <= 0;
      b_rd_add <= 0;
      a_rd_add <= 0;
    end else begin
      b_rd_en  <= $urandom();
      a_rd_en  <= $urandom();
      b_rd_add <= $urandom();
      a_rd_add <= $urandom();
    end
  end

  // ============================================================================================ //
  // Checker
  // ============================================================================================ //  
  logic [WIDTH-1:0]                               mem              [DEPTH-1:0];
  logic [      1:0][DEPTH_W-1:0]                  rd_add_a;
  logic [      1:0][ROM_LATENCY-1:0][  DEPTH-1:0] rd_data_ref_a;
  logic [      1:0][ROM_LATENCY-1:0]              rd_en_a;
  logic [      1:0][ROM_LATENCY-1:0]              rd_data_ref_ready;
  logic [      1:0][      WIDTH-1:0]              rd_data_a;

  assign rd_add_a   = {a_rd_add, b_rd_add};
  assign rd_en_a    = {a_rd_en, b_rd_en};
  assign rd_data_a  = {a_rd_data, b_rd_data};

  // reading the memory file
  initial begin
    $readmemh(FILENAME, mem, 0, DEPTH - 1);
  end

  generate
    for (genvar gen_i = 0; gen_i < 2; gen_i = gen_i + 1) begin : gen_loop
      always_ff @(posedge clk) begin
        rd_data_ref_ready[gen_i][0] <= rd_en_a[gen_i];
        if (ROM_LATENCY > 1) begin
          rd_data_ref_ready[gen_i][ROM_LATENCY-1:1] <= rd_data_ref_ready[gen_i][ROM_LATENCY-2:0];
        end
      end  // process

      always_ff @(posedge clk) begin
        if (ROM_LATENCY > 1) begin
          rd_data_ref_a[gen_i][ROM_LATENCY-1:1] <= rd_data_ref_a[gen_i][ROM_LATENCY-2:0];
        end  // end sr

        if (rd_en_a[gen_i]) begin
          rd_data_ref_a[gen_i][0] <= mem[rd_add_a[gen_i]];
        end  // end enable

      end  // endprocess line b
    end  // for loop
  endgenerate

  // checking output data --------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (~s_rst_n) begin
      error_d    <= 0;
      cnt_pass <= 1;
    end else begin
        if (rd_data_ref_ready[1][ROM_LATENCY-1]) begin
          assert (rd_data_ref_a[1][ROM_LATENCY-1] == a_rd_data) begin
            cnt_pass = cnt_pass + 1;
          end else begin
            $display("%t > ERROR: line B Datar mismatch: exp=%0d, seen=%0d", $time, rd_data_ref_a[1][ROM_LATENCY-1], a_rd_data);
            error_d <= 1;
          end  // assert line a
        end // line A

        if (rd_data_ref_ready[0][ROM_LATENCY-1]) begin
          assert ((rd_data_ref_a[0][ROM_LATENCY-1] == b_rd_data)) begin
            cnt_pass = cnt_pass + 1;
          end else begin
            $display("%t > ERROR: line A Datar mismatch: exp=%0d, seen=%0d", $time, rd_data_ref_a[0][ROM_LATENCY-1], b_rd_data);
            error_d <= 1;
          end  // assert line b
        end // line B
    end  // s_rst_n      
  end  // end process

  // check KEEP_RD_DATA ----------------------------------------------------------------------------
  generate
    for (genvar gen_i=0; gen_i<2; gen_i=gen_i+1) begin : gen_loop_kept
      logic [ROM_LATENCY-1:0][WIDTH-1:0] rd_data_ref_dly;
      logic [ROM_LATENCY-1:0] rd_avail_dly;
      logic [ROM_LATENCY-1:0] rd_avail_dlyD;

      assign rd_avail_dlyD[0]    = rd_en_a[gen_i];

      if (ROM_LATENCY>1) begin
        assign rd_avail_dlyD[ROM_LATENCY-1:1]    = rd_avail_dly[ROM_LATENCY-2:0];
      end

      always_ff @(posedge clk) begin
        rd_data_ref_dly <= rd_data_ref_a;
      end

      always_ff @(posedge clk) begin
        if (!s_rst_n) begin
          rd_avail_dly <= '0;
        end
        else begin
          rd_avail_dly <= rd_avail_dlyD;
        end
      end

      if (KEEP_RD_DATA != 0) begin: keep_data_check_gen
        logic [WIDTH-1:0] rd_data_dly;
        logic             start_check_keep_datar;

        always_ff @(posedge clk) begin
          if (!s_rst_n) begin 
            start_check_keep_datar <= 1'b0;
          end else begin
            start_check_keep_datar <= rd_avail_dly[ROM_LATENCY-1] ? 1'b1 : start_check_keep_datar;
          end
        end

        always_ff @(posedge clk) begin
          if (rd_avail_dly[ROM_LATENCY-1]) begin
            rd_data_dly <= rd_data_a[gen_i];
          end
        end

        always_ff @(posedge clk) begin
          if (!s_rst_n) begin
            error_k[gen_i] <= 1'b0;
          end else begin
            if (start_check_keep_datar) begin
              if (!rd_avail_dly[ROM_LATENCY-1])
                assert(rd_data_a[gen_i] === rd_data_dly)
                else begin
                  error_k[gen_i] <= 1'b1;
                  $display("%t > ERROR: Datar not kept [%d]: exp=0x%0x, seen=0x%0x",$time, gen_i, rd_data_dly, rd_data_a[gen_i]);
                end
            end
          end
        end
      end

    end 
  endgenerate

endmodule
