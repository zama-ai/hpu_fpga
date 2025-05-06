// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Testbench to check pep_mmacc_body_ram
// ==============================================================================================

module tb_pep_mmacc_body_ram;
  import param_tfhe_pkg::*;
  import pep_common_param_pkg::*;

`timescale 1ns/10ps

// ============================================================================================== --
// Parameter / localparam
// ============================================================================================== --
  localparam int CLK_HALF_PERIOD = 1;
  localparam int ARST_ACTIVATION = 17;

  parameter int SAMPLE_NB = 1000;

  localparam int DATA_RAND_RANGE = 1023;

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
// input / output signals
// ============================================================================================== --
  logic                  ks_boram_wr_en;
  logic [LWE_COEF_W-1:0] ks_boram_wr_data;
  logic [PID_W-1:0]      ks_boram_wr_pid;
  logic                  ks_boram_wr_parity;

  logic [PID_W-1:0]      boram_rd_pid;
  logic                  boram_rd_vld;
  logic                  boram_rd_rdy;
  logic                  boram_rd_parity;

  logic [LWE_COEF_W-1:0] boram_sxt_data;
  logic                  boram_sxt_data_vld;
  logic                  boram_sxt_data_rdy;

// ============================================================================================== --
// Error
// ============================================================================================== --
  bit error;
  bit error_data;

  assign error = error_data;

  always_ff @(posedge clk)
    if (error) begin
      $display("%t > FAILURE !", $time);
      $finish;
    end

// ============================================================================================== --
// Design under test instance
// ============================================================================================== --
  pep_mmacc_body_ram
  dut
  (
    .clk                (clk),
    .s_rst_n            (s_rst_n),

    .ks_boram_wr_en     (ks_boram_wr_en),
    .ks_boram_wr_data   (ks_boram_wr_data),
    .ks_boram_wr_pid    (ks_boram_wr_pid),
    .ks_boram_wr_parity (ks_boram_wr_parity),

    .boram_rd_pid       (boram_rd_pid),
    .boram_rd_vld       (boram_rd_vld),
    .boram_rd_rdy       (boram_rd_rdy),
    .boram_rd_parity    (boram_rd_parity),

    .boram_sxt_data     (boram_sxt_data),
    .boram_sxt_data_vld (boram_sxt_data_vld),
    .boram_sxt_data_rdy (boram_sxt_data_rdy)
  );

// ============================================================================================== --
// Scenario
// ============================================================================================== --
// Write LWE randomly.
// Keep track that the LWE has been read, to write again.
// States:
// 'b10 // Write First data
// 'b01 // Write 2nd data
// 'b00 // all writes done
// 'b11 // rd command sent => do not write anymore
  logic [TOTAL_PBS_NB-1:0][1:0] wr_enable;
  logic [TOTAL_PBS_NB-1:0][1:0] wr_enableD;

  logic                    rd_done;
  logic [PID_W-1:0]        rd_done_pid;

  logic                    wr_done;
  logic [PID_W-1:0]        wr_done_pid;

  always_comb
    for (int i=0; i<TOTAL_PBS_NB; i=i+1)
      wr_enableD[i] = (boram_rd_vld && boram_rd_rdy && (boram_rd_pid == i) && wr_enable[i]==2'b01) ? 2'b11 :
                      wr_done && (wr_done_pid==i) ? wr_enable[i] >> 1:
                      rd_done && (rd_done_pid==i) ? 2'b10 : wr_enable[i];

  always_ff @(posedge clk)
    if (!s_rst_n) wr_enable <= {TOTAL_PBS_NB{2'b10}};
    else          wr_enable <= wr_enableD;

  // Keep track of data value
  logic [LWE_COEF_W-1:0] lwe_a [TOTAL_PBS_NB-1:0];
  logic [LWE_COEF_W-1:0] prev_lwe_a [TOTAL_PBS_NB-1:0];

  always_ff @(posedge clk)
    if (ks_boram_wr_en)
      lwe_a[ks_boram_wr_pid] <= ks_boram_wr_data;

  always_ff @(posedge clk)
    if (rd_done)
      prev_lwe_a[rd_done_pid] <= lwe_a[rd_done_pid];

  //== Write
  logic                  wr_vld;
  logic                  wr_rdy;
  logic [LWE_COEF_W-1:0] wr_lwe;
  logic                  wr_parity;
  stream_source
  #(
    .FILENAME   ("random"),
    .DATA_TYPE  ("ascii_hex"),
    .DATA_W     (LWE_COEF_W),
    .RAND_RANGE (DATA_RAND_RANGE),
    .KEEP_VLD   (0),
    .MASK_DATA  ("x")
  )
  source_wr
  (
    .clk        (clk),
    .s_rst_n    (s_rst_n),

    .data       (wr_lwe),
    .vld        (wr_vld),
    .rdy        (wr_rdy),

    .throughput (0)
  );

  initial begin
    int r;
    r = source_wr.open();
    wait(s_rst_n);
    @(posedge clk) source_wr.start(0);
  end

  logic [PID_W-1:0] rand_pid;
  always_ff @(posedge clk)
    rand_pid    <= $urandom_range(0,TOTAL_PBS_NB-1);

  assign ks_boram_wr_pid    = rand_pid;
  assign ks_boram_wr_parity = wr_parity;
  //assign ks_boram_wr_data = (prev_lwe_a[ks_boram_wr_pid] === wr_lwe) ? wr_lwe + 1 : wr_lwe; // === take X into account
  assign ks_boram_wr_data = (wr_enable[ks_boram_wr_pid] == 2'b10) ? (prev_lwe_a[ks_boram_wr_pid] === wr_lwe) ? wr_lwe + 1 : wr_lwe: lwe_a[ks_boram_wr_pid];
  assign ks_boram_wr_en   = wr_vld & ^wr_enable[ks_boram_wr_pid];
  assign wr_rdy           = ^wr_enable[ks_boram_wr_pid];
  assign wr_done          = ks_boram_wr_en;
  assign wr_done_pid      = ks_boram_wr_pid;

  // parity
  // Simulate the fact that 2 writings at the same location could occur.
  // The writing contain the same value but different parities.
  // The reading is at a given parity. Therefore the 2nd writing has the correct parity.
  // Thus we will check that the reading is blocked until the correct parity is seen.

  // Indicate final parity value => parity that will be read
  logic [TOTAL_PBS_NB-1:0] wr_parity_a;
  logic [TOTAL_PBS_NB-1:0] wr_parity_aD;

  assign wr_parity = (wr_enable[ks_boram_wr_pid] == 2'b10) ^ wr_parity_a[ks_boram_wr_pid];

  always_comb
    for (int i=0; i<TOTAL_PBS_NB; i=i+1)
      wr_parity_aD[i] = (ks_boram_wr_en && (ks_boram_wr_pid == i) && wr_enable[ks_boram_wr_pid] == 2'b01) ? ~wr_parity_a[i] : wr_parity_a[i]; // Update parity on 2nd writing

  always_ff @(posedge clk)
    if (!s_rst_n) wr_parity_a <= '0;
    else          wr_parity_a <= wr_parity_aD;

  //== Read
  logic             rd_vld;
  logic             rd_rdy;
  logic [PID_W-1:0] rd_add;
  logic             rd_parity;
  stream_source
  #(
    .FILENAME   ("random"),
    .DATA_TYPE  ("ascii_hex"),
    .DATA_W     (PID_W),
    .RAND_RANGE (DATA_RAND_RANGE),
    .KEEP_VLD   (0),
    .MASK_DATA  ("x")
  )
  source_rd
  (
    .clk        (clk),
    .s_rst_n    (s_rst_n),

    .data       () /* UNUSED*/,
    .vld        (rd_vld),
    .rdy        (rd_rdy),

    .throughput (0)
  );

  initial begin
    int r;
    r = source_rd.open();
    wait(s_rst_n);
    @(posedge clk) source_rd.start(SAMPLE_NB);
  end

  logic [PID_W-1:0] rd_pid_q [$];
  always_ff @(posedge clk) begin
    if (ks_boram_wr_en && wr_enable[ks_boram_wr_pid] == 2'b10) begin
      rd_pid_q.push_back(ks_boram_wr_pid);
    end
    if (boram_rd_vld && boram_rd_rdy) begin
      rd_pid_q.pop_front();
    end
  end

  bit rd_mask;
  
  always @(*) begin
    rd_mask = (rd_pid_q.size() > 0);
    rd_add  = rd_pid_q[0];
  end

  assign boram_rd_vld = rd_vld & rd_mask;
  assign boram_rd_pid = rd_add % TOTAL_PBS_NB;
  assign boram_rd_parity  = rd_parity;
  assign rd_rdy           = boram_rd_rdy & rd_mask;

  logic [PID_W-1:0] rd_add_q [$];
  always_ff @(posedge clk)
    if (boram_rd_vld && boram_rd_rdy)
      rd_add_q.push_back(boram_rd_pid);

  // Parity
  logic [TOTAL_PBS_NB-1:0] rd_parity_a;
  logic [TOTAL_PBS_NB-1:0] rd_parity_aD;

  assign rd_parity = rd_parity_a[boram_rd_pid];

  always_comb
    for (int i=0; i<TOTAL_PBS_NB; i=i+1)
      rd_parity_aD[i] = (boram_rd_vld && boram_rd_rdy && boram_rd_pid == i) ? ~rd_parity_a[i] : rd_parity_a[i];

  always_ff @(posedge clk)
    if (!s_rst_n) rd_parity_a <= '0;
    else          rd_parity_a <= rd_parity_aD;

// ---------------------------------------------------------------------------------------------- --
// Check data
// ---------------------------------------------------------------------------------------------- --
  stream_sink
  #(
    .FILENAME_REF   (""),
    .DATA_TYPE_REF  ("ascii_hex"),
    .FILENAME       (""),
    .DATA_TYPE      ("ascii_hex"),
    .DATA_W         (1), // UNUSED
    .RAND_RANGE     (DATA_RAND_RANGE),
    .KEEP_RDY       (1)
  )
  sink_rdata
  (
      .clk        (clk),
      .s_rst_n    (s_rst_n),

      .data       ('x), /*UNUSED*/
      .vld        (boram_sxt_data_vld),
      .rdy        (boram_sxt_data_rdy),

      .error      (), // UNUSED
      .throughput (0)
  );

  initial begin
    sink_rdata.set_do_ref(0);
    sink_rdata.start(0);
  end


  always_ff @(posedge clk)
    if (!s_rst_n) begin
      error_data <= 1'b0;
      rd_done    <= 1'b0;
    end
    else begin
      rd_done    <= 1'b0;
      if (boram_sxt_data_vld && boram_sxt_data_rdy) begin
        logic [PID_W-1:0]      ref_pid;
        logic [LWE_COEF_W-1:0] ref_lwe;
        logic [LWE_COEF_W-1:0] prev_lwe;
        ref_pid  = rd_add_q.pop_front();
        ref_lwe  = lwe_a[ref_pid];
        prev_lwe = prev_lwe_a[ref_pid];

        assert(ref_lwe == boram_sxt_data)
        else begin
          $display("%t > ERROR: Data mismatch pid=%0d exp=0x%0x seen=0x%0x",$time,ref_pid,ref_lwe,boram_sxt_data);
          error_data <= 1'b1;
        end

        assert(prev_lwe !== boram_sxt_data)
        else begin
          $display("%t > ERROR: Data match previous value pid=%0d exp=0x%0x seen=0x%0x",$time,ref_pid,ref_lwe,boram_sxt_data);
          error_data <= 1'b1;
        end

        rd_done     <= 1'b1;
        rd_done_pid <= ref_pid;
      end
    end

// ---------------------------------------------------------------------------------------------- --
// End of test
// ---------------------------------------------------------------------------------------------- --

  initial begin
    end_of_test = 1'b0;
    wait(source_rd.running);
    @(posedge clk)
    wait(!source_rd.running);
    @(posedge clk);
    end_of_test = 1'b1;
  end

endmodule
