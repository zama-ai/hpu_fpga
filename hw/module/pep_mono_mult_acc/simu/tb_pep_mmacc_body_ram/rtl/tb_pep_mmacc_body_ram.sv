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

  parameter int SAMPLE_NB = 10000;

  localparam int DATA_RAND_RANGE = 1023;
  localparam int CORR_DATA_RAND_RANGE = ~(KS_MAX_ERROR_W'(0));

// ============================================================================================== --
// Types
// ============================================================================================== --
  // Note: seq_corr_t absolutely needs to be signed, otherwise all the expected computations in the
  // checker become a mess. I prefer that the expected model is as pure and abstracted as possible
  // to minimize the number of possible errors in the testbench.

  typedef logic        [LWE_COEF_W-1:0]     modsw_coeff_t;
  typedef logic        [MOD_KSK_W-1:0]      ks_coeff_t;
  typedef logic signed [KS_CORR_W-1:0]      seq_corr_t;
  typedef logic signed [KS_MAX_ERROR_W-1:0] corr_t;
  typedef logic        [PID_W-1:0]          pid_t;

  typedef enum logic [1:0] {
    WRITE_FIRST = 2'b10,  // Write First data
    WRITE_2ND   = 2'b01,  // Write 2nd data
    WRITE_DONE  = 2'b00,  // all writes done
    RD_SENT     = 2'b11   // rd command sent => do not write anymore
  } state_t;

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
  logic         ks_boram_wr_en;
  ks_coeff_t    ks_boram_wr_data;
  pid_t         ks_boram_wr_pid;
  logic         ks_boram_wr_parity;

  logic         seq_boram_corr_wr_en;
  seq_corr_t    seq_boram_corr_wr_data;
  pid_t         seq_boram_corr_wr_pid;

  pid_t         boram_rd_pid;
  logic         boram_rd_vld;
  logic         boram_rd_rdy;
  logic         boram_rd_parity;

  modsw_coeff_t boram_sxt_data;
  logic         boram_sxt_data_vld;
  logic         boram_sxt_data_rdy;

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
    .clk                   (clk),
    .s_rst_n               (s_rst_n),
    .reset_cache           (1'b0),

    .ks_boram_wr_en        (ks_boram_wr_en),
    .ks_boram_wr_data      (ks_boram_wr_data),
    .ks_boram_wr_pid       (ks_boram_wr_pid),
    .ks_boram_wr_parity    (ks_boram_wr_parity),

    .seq_boram_corr_wr_en  (seq_boram_corr_wr_en),
    .seq_boram_corr_wr_data(seq_boram_corr_wr_data),
    .seq_boram_corr_wr_pid (seq_boram_corr_wr_pid),

    .boram_rd_pid          (boram_rd_pid),
    .boram_rd_vld          (boram_rd_vld),
    .boram_rd_rdy          (boram_rd_rdy),
    .boram_rd_parity       (boram_rd_parity),

    .boram_sxt_data        (boram_sxt_data),
    .boram_sxt_data_vld    (boram_sxt_data_vld),
    .boram_sxt_data_rdy    (boram_sxt_data_rdy)
  );

// ============================================================================================== --
// Scenario
// ============================================================================================== --
// Write LWE randomly.
// Keep track that the LWE has been read, to write again.
  ks_coeff_t    ks_lwe_a      [TOTAL_PBS_NB-1:0];
  ks_coeff_t    prev_ks_lwe_a [TOTAL_PBS_NB-1:0];
  seq_corr_t    prev_corr_acc [TOTAL_PBS_NB-1:0];

  state_t wr_enable  [TOTAL_PBS_NB-1:0];
  state_t wr_enableD [TOTAL_PBS_NB-1:0];

 logic rd_done;
 pid_t rd_done_pid;

 logic wr_done;
 pid_t wr_done_pid;

  always_comb
    for (int i=0; i<TOTAL_PBS_NB; i=i+1)
      wr_enableD[i] = (boram_rd_vld && boram_rd_rdy && (boram_rd_pid == pid_t'(i)) && wr_enable[i]==WRITE_2ND) ? RD_SENT :
                      wr_done && (wr_done_pid==pid_t'(i)) ? state_t'(wr_enable[i] >> 1):
                      rd_done && (rd_done_pid==pid_t'(i)) ? WRITE_FIRST : wr_enable[i];

  generate for (genvar i = 0; i < TOTAL_PBS_NB; i++) begin: gen_wr_enable
    always_ff @(posedge clk)
      if (!s_rst_n) wr_enable[i] <= WRITE_FIRST;
      else          wr_enable[i] <= wr_enableD[i];
  end endgenerate

  //== Write
  logic      wr_vld;
  logic      wr_rdy;
  ks_coeff_t wr_lwe;
  logic      wr_parity;
  stream_source
  #(
    .FILENAME   ("random"),
    .DATA_TYPE  ("ascii_hex"),
    .DATA_W     ($bits(ks_coeff_t)),
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

    .throughput ('0)
  );

  initial begin
    int r;
    r = source_wr.open();
    wait(s_rst_n);
    @(posedge clk) source_wr.start(0);
  end

  pid_t rand_pid;
  always_ff @(posedge clk)
    rand_pid <= pid_t'($urandom_range(0,TOTAL_PBS_NB-1));

  assign ks_boram_wr_pid    = rand_pid;
  assign ks_boram_wr_parity = wr_parity;
  //assign ks_boram_wr_data = (prev_ks_lwe_a[ks_boram_wr_pid] === wr_lwe) ? wr_lwe + 1 : wr_lwe; // === take X into account
  assign ks_boram_wr_data = (wr_enable[ks_boram_wr_pid] == WRITE_FIRST) ?
                            (prev_ks_lwe_a[ks_boram_wr_pid] === wr_lwe) ? wr_lwe + ks_coeff_t'(1) : wr_lwe
                            : ks_lwe_a[ks_boram_wr_pid];
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

  assign wr_parity = (wr_enable[ks_boram_wr_pid] == WRITE_FIRST) ^ wr_parity_a[ks_boram_wr_pid];

  always_comb
    for (int i=0; i<TOTAL_PBS_NB; i=i+1)
      wr_parity_aD[i] = (ks_boram_wr_en && (ks_boram_wr_pid == pid_t'(i)) && wr_enable[ks_boram_wr_pid] == WRITE_2ND) ? ~wr_parity_a[i] : wr_parity_a[i]; // Update parity on 2nd writing

  always_ff @(posedge clk)
    if (!s_rst_n) wr_parity_a <= '0;
    else          wr_parity_a <= wr_parity_aD;

// ============================================================================================== --
// Scenario 2
// Write the correction RAM randomly
// ============================================================================================== --
  //== Correction RAM Write
  logic     seq_corr_wr_vld;
  logic     seq_corr_wr_rdy;
  seq_corr_t seq_corr_wr_lwe;

  stream_source
  #(
    .FILENAME   ("random"),
    .DATA_TYPE  ("ascii_hex"),
    .DATA_W     ($bits(seq_corr_t)),
    .RAND_RANGE (CORR_DATA_RAND_RANGE),
    .KEEP_VLD   (0),
    .MASK_DATA  ("x")
  )
  source_seq_corr_wr
  (
    .clk        (clk),
    .s_rst_n    (s_rst_n),

    .data       (seq_corr_wr_lwe),
    .vld        (seq_corr_wr_vld),
    .rdy        (seq_corr_wr_rdy),

    .throughput ('0)
  );

  initial begin
    void'(source_seq_corr_wr.open());
    wait(s_rst_n);
    @(posedge clk) source_seq_corr_wr.start(0);
  end

  integer     seq_corr_wr_cnt [TOTAL_PBS_NB];
  corr_t      seq_corr_acc    [TOTAL_PBS_NB];

  generate for (genvar i = 0; i < TOTAL_PBS_NB; i++) begin: gen_seq_corr_wr_cnt
    always_ff @(posedge clk) begin
      if(!s_rst_n || (rd_done && rd_done_pid == pid_t'(i))) begin
        seq_corr_wr_cnt[i] <= '0;
        seq_corr_acc[i]    <= '0;
      end else if(seq_boram_corr_wr_en && seq_boram_corr_wr_pid == pid_t'(i)) begin
        seq_corr_wr_cnt[i] <= seq_corr_wr_cnt[i] + 1;
        seq_corr_acc[i]    <= seq_corr_acc[i] + {{KS_MAX_ERROR_W-KS_CORR_W{seq_boram_corr_wr_data[KS_CORR_W-1]}}, seq_boram_corr_wr_data};
      end
    end
  end endgenerate

  pid_t rand_seq_corr_pid;
  always_ff @(posedge clk)
    rand_seq_corr_pid <= pid_t'($urandom_range(0,TOTAL_PBS_NB-1));

  assign seq_boram_corr_wr_pid  = rand_seq_corr_pid;
  assign seq_boram_corr_wr_data = (seq_corr_wr_cnt[rand_seq_corr_pid] == LWE_K-1) ?
                                  seq_corr_wr_lwe : seq_corr_wr_lwe;
  assign seq_corr_wr_rdy        = (seq_corr_wr_cnt[seq_boram_corr_wr_pid] < LWE_K);
  assign seq_boram_corr_wr_en   = seq_corr_wr_vld & seq_corr_wr_rdy;

  // Keep track of data value
  always_ff @(posedge clk)
    if (ks_boram_wr_en)
      ks_lwe_a[ks_boram_wr_pid] <= ks_boram_wr_data;

  always_ff @(posedge clk)
    if (rd_done) begin
      prev_corr_acc[rd_done_pid] <= seq_corr_acc[rd_done_pid];
      prev_ks_lwe_a[rd_done_pid] <= ks_lwe_a[rd_done_pid];
    end

  //== Read
 logic rd_vld;
 logic rd_rdy;
 pid_t rd_add;
 logic rd_parity;
  stream_source
  #(
    .FILENAME   ("random"),
    .DATA_TYPE  ("ascii_hex"),
    .DATA_W     ($bits(pid_t)),
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

    .throughput ('0)
  );

  initial begin
    int r;
    r = source_rd.open();
    wait(s_rst_n);
    @(posedge clk) source_rd.start(SAMPLE_NB);
  end

  pid_t rd_pid_q [$];
  always_ff @(posedge clk) begin
    if (ks_boram_wr_en && wr_enable[ks_boram_wr_pid] == WRITE_FIRST) begin
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
  assign boram_rd_pid = pid_t'(rd_add % TOTAL_PBS_NB);
  assign boram_rd_parity  = rd_parity;
  assign rd_rdy           = boram_rd_rdy & rd_mask;

  pid_t rd_add_q [$];
  always_ff @(posedge clk)
    if (boram_rd_vld && boram_rd_rdy)
      rd_add_q.push_back(boram_rd_pid);

  // Parity
  logic [TOTAL_PBS_NB-1:0] rd_parity_a;
  logic [TOTAL_PBS_NB-1:0] rd_parity_aD;

  assign rd_parity = rd_parity_a[boram_rd_pid];

  always_comb
    for (int i=0; i<TOTAL_PBS_NB; i=i+1)
      rd_parity_aD[i] = (boram_rd_vld && boram_rd_rdy && boram_rd_pid == pid_t'(i)) ? ~rd_parity_a[i] : rd_parity_a[i];

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
      .throughput ('0)
  );

  initial begin
    sink_rdata.set_do_ref(0);
    sink_rdata.start(0);
  end

  function ks_coeff_t center(input ks_coeff_t value); // For the shifted modulo switch
    if (USE_MEAN_COMP)
      return (value - (MOD_KSK / (2*2*N))) % MOD_KSK;
    else
      return value;
  endfunction

  function modsw_coeff_t mod_switch(input real value);
    return $floor(value / (2**(MOD_KSK_W-LWE_COEF_W)) + 0.5);
  endfunction

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      error_data <= 1'b0;
      rd_done    <= 1'b0;
    end
    else begin
      rd_done    <= 1'b0;
      if (boram_sxt_data_vld && boram_sxt_data_rdy) begin
        pid_t         ref_pid;
        modsw_coeff_t ref_lwe;

        ref_pid  = rd_add_q.pop_front();
        ref_lwe  = mod_switch(real'(center(ks_lwe_a[ref_pid])) - real'(seq_corr_acc[ref_pid]) * KS_KEY_MEAN_R);

        // Not using assert because it causes lint warnings about side effects
        if(ref_lwe != boram_sxt_data) begin
          $display("%t > ERROR: Data mismatch pid=%0d exp=0x%0x seen=0x%0x",$time,ref_pid,ref_lwe,boram_sxt_data);
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
