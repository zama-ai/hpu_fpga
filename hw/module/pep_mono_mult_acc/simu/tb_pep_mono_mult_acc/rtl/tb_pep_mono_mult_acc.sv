// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Testbench to test pep_mono_mult_acc : sanity check.
// ==============================================================================================

module tb_pep_mono_mult_acc;
  import common_definition_pkg::*;
  import param_tfhe_pkg::*;
  import ntt_core_common_param_pkg::*;
  import top_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import regf_common_param_pkg::*;
  import hpu_common_instruction_pkg::*;
  import pep_ks_common_param_pkg::*;
  import pep_mmacc_common_param_pkg::*;

`timescale 1ns/10ps

// ============================================================================================== --
// Parameter / localparam
// ============================================================================================== --
  localparam int CLK_HALF_PERIOD = 1;
  localparam int ARST_ACTIVATION = 17;

  parameter  int RAM_LATENCY              = 2;
  parameter  int PHYS_RAM_DEPTH           = 1024; // Physical RAM depth. Should be a power of 2

  localparam int MAIN_PSI                 = MSPLIT_MAIN_FACTOR * PSI / MSPLIT_DIV;
  localparam int SUBS_PSI                 = MSPLIT_SUBS_FACTOR * PSI / MSPLIT_DIV;

  localparam int GLWE_WORD_NB_IN_GRAM = (STG_ITER_NB * GLWE_K_P1);

  // Regfile
  parameter int PEA_PERIOD   = REGF_COEF_NB;
  parameter int PEM_PERIOD   = 8;
  parameter int PEP_PERIOD   = 1;
  parameter int URAM_LATENCY = 1+RAM_LATENCY;

  // sequencer
  parameter int INST_FIFO_DEPTH   = 8; // Should be >= 2

  // Testbench
  localparam int SAMPLE_THROUGHPUT_NB = 200;
  localparam int SAMPLE_RANDOM_NB     = 200;
  localparam int SAMPLE_NB       = SAMPLE_THROUGHPUT_NB + SAMPLE_RANDOM_NB;
  parameter  int DATA_RAND_RANGE = 1023;
  localparam int DATA_RAND_RANGE_W = $clog2(DATA_RAND_RANGE+1);
  parameter  int INST_THROUGHPUT = DATA_RAND_RANGE / 50; // 0 : random, 1: very rare, RAND_RANGE : always valid
  localparam int NTT_SR_DEPTH    = 100;

  localparam int LDG_IDX = 0;
  localparam int LDB_IDX = 1;
  localparam [1:0][31:0] LD_LATENCY = {32'd23,32'd139};

  localparam int KS_LATENCY = 40;
  localparam int KS_LOOP_MAX = ((LWE_K_P1 + LBX-1) / LBX) * LBX;

  parameter  int BSK_SR_DEPTH = 10;

  parameter  int SLR_LATENCY          = 2*2;
  parameter  bit USE_BPIP             = 1'b0;
  parameter  bit USE_BPIP_OPPORTUNISM = 1'b0;
  parameter  [31:0] TIMEOUT           = 'hFFFFF;

  initial begin
    $display("> INFO: PERM_LVL_NB                = %0d",PERM_LVL_NB);
    $display("> INFO: PERM_STAGE_NB              = %0d",PERM_STAGE_NB);
    $display("> INFO: PERM_CYCLE_NB              = %0d",PERM_CYCLE_NB);
    $display("> INFO: ACC_WR_START_DLY_SLOT_NB   = %0d",ACC_WR_START_DLY_SLOT_NB  );
    $display("> INFO: ACC_WR_END_DLY_SLOT_NB     = %0d",ACC_WR_END_DLY_SLOT_NB    );
    $display("> INFO: FEED_DAT_START_DLY_SLOT_NB = %0d",FEED_DAT_START_DLY_SLOT_NB);
    $display("> INFO: FEED_DAT_END_DLY_SLOT_NB   = %0d",FEED_DAT_END_DLY_SLOT_NB  );
  end

// ============================================================================================== --
// function
// ============================================================================================== --
  function int rev_order(int i);
    logic [S-1:0][R_W-1:0] r_v;
    logic [S-1:0][R_W-1:0] v_a;

    v_a = i;

    for (int i=0; i<S; i=i+1)
      r_v[i] = v_a[S-1-i];
    return r_v;
  endfunction

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
  // ACC -> Decomposer
  logic [ACC_DECOMP_COEF_NB-1:0]                          acc_decomp_data_avail;
  logic                                                   acc_decomp_ctrl_avail;
  logic [ACC_DECOMP_COEF_NB-1:0][MOD_Q_W-1:0]             acc_decomp_data;
  logic                                                   acc_decomp_sob;
  logic                                                   acc_decomp_eob;
  logic                                                   acc_decomp_sog;
  logic                                                   acc_decomp_eog;
  logic                                                   acc_decomp_sol;
  logic                                                   acc_decomp_eol;
  logic                                                   acc_decomp_soc;
  logic                                                   acc_decomp_eoc;
  logic [BPBS_ID_W-1:0]                                   acc_decomp_pbs_id;
  logic                                                   acc_decomp_last_pbs;
  logic                                                   acc_decomp_full_throughput;

  // NTT core -> ACC
  logic [PSI-1:0][R-1:0]                                  ntt_acc_data_avail;
  logic                                                   ntt_acc_ctrl_avail;
  logic [PSI-1:0][R-1:0][MOD_Q_W-1:0]                     ntt_acc_data;
  logic                                                   ntt_acc_sob;
  logic                                                   ntt_acc_eob;
  logic                                                   ntt_acc_sol;
  logic                                                   ntt_acc_eol;
  logic                                                   ntt_acc_sog;
  logic                                                   ntt_acc_eog;
  logic [BPBS_ID_W-1:0]                                   ntt_acc_pbs_id;

  // batch_cmd
  logic [BR_BATCH_CMD_W-1:0]                              batch_cmd;
  logic                                                   batch_cmd_avail;

  // Wr access to GLWE RAM
  // This memory is composed of GRAM_NB independent RAMs
  logic [GRAM_NB-1:0][PSI-1:0][R-1:0]                       ldg_gram_wr_en;
  logic [GRAM_NB-1:0][PSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0]   ldg_gram_wr_add;
  logic [GRAM_NB-1:0][PSI-1:0][R-1:0][MOD_Q_W-1:0]          ldg_gram_wr_data;

  logic [GRAM_NB-1:0]                                       garb_ldg_avail_1h;

  logic [GRAM_NB-1:0][MAIN_PSI-1:0][R-1:0]                     ldg_gram_main_wr_en;
  logic [GRAM_NB-1:0][MAIN_PSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0] ldg_gram_main_wr_add;
  logic [GRAM_NB-1:0][MAIN_PSI-1:0][R-1:0][MOD_Q_W-1:0]        ldg_gram_main_wr_data;

  logic [GRAM_NB-1:0][SUBS_PSI-1:0][R-1:0]                     ldg_gram_subs_wr_en;
  logic [GRAM_NB-1:0][SUBS_PSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0] ldg_gram_subs_wr_add;
  logic [GRAM_NB-1:0][SUBS_PSI-1:0][R-1:0][MOD_Q_W-1:0]        ldg_gram_subs_wr_data;

  logic [GRAM_NB-1:0]                                     garb_ldg_main_avail_1h;
  logic [GRAM_NB-1:0]                                     garb_ldg_subs_avail_1h;

  // SXT <-> regfile
  logic                                                   sxt_regf_wr_req_vld;
  logic                                                   sxt_regf_wr_req_rdy;
  logic [REGF_WR_REQ_W-1:0]                               sxt_regf_wr_req;

  logic [REGF_COEF_NB-1:0]                                sxt_regf_wr_data_vld;
  logic [REGF_COEF_NB-1:0]                                sxt_regf_wr_data_rdy;
  logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0]                   sxt_regf_wr_data;

  logic                                                   regf_sxt_wr_ack;

  // mmacc <-> pep_sequencer
  logic                                                   pbs_seq_cmd_enquiry;
  logic [PBS_CMD_W-1:0]                                   seq_pbs_cmd;
  logic                                                   seq_pbs_cmd_avail;

  logic                                                   sxt_seq_done;
  logic [PID_W-1:0]                                       sxt_seq_done_pid;

  // From KS
  logic                                                   ks_boram_wr_en;
  logic [MOD_KSK_W-1:0]                                   ks_boram_data;
  logic [PID_W-1:0]                                       ks_boram_pid;
  logic                                                   ks_boram_parity;

  logic                                                   seq_boram_corr_wr_en;
  logic [KS_MAX_ERROR_W-1:0]                              seq_boram_corr_data;
  logic [PID_W-1:0]                                       seq_boram_corr_pid;

  // BSK
  logic                                                   inc_bsk_wr_ptr;
  logic                                                   inc_bsk_rd_ptr;

  pep_mmacc_error_t                                       mmacc_error;

  // sequencer
  logic [PE_INST_W-1:0]                                   inst;
  logic                                                   inst_vld;
  logic                                                   inst_rdy;

  logic                                                   inst_ack;

  // To Loading units
  logic [LOAD_GLWE_CMD_W-1:0]                             seq_ldg_cmd;
  logic                                                   seq_ldg_vld;
  logic                                                   seq_ldg_rdy;

  logic [LOAD_BLWE_CMD_W-1:0]                             seq_ldb_cmd;
  logic                                                   seq_ldb_vld;
  logic                                                   seq_ldb_rdy;

  // From loading units
  logic                                                   ldg_seq_done;
  logic                                                   ldb_seq_done;

  // Keyswitch command
  logic                                                   ks_seq_cmd_enquiry;
  logic [KS_CMD_W-1:0]                                    seq_ks_cmd;
  logic                                                   seq_ks_cmd_avail;

  // Keyswitch result
  logic [KS_RESULT_W-1:0]                                 ks_seq_result;
  logic                                                   ks_seq_result_vld;
  logic                                                   ks_seq_result_rdy;

  // Error
  pep_seq_error_t                                         seq_error;

  // Create disturbance on regfile access
  logic                                                   pem_regf_wr_req_vld;
  logic                                                   pem_regf_wr_req_rdy;
  regf_wr_req_t                                           pem_regf_wr_req;

  logic [REGF_COEF_NB-1:0]                                pem_regf_wr_data_vld;
  logic [REGF_COEF_NB-1:0]                                pem_regf_wr_data_rdy;
  logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0]                   pem_regf_wr_data;

  logic                                                   reset_cache;

// ============================================================================================== --
// Error
// ============================================================================================== --
  bit error;
  bit error_sxt_pid; // TODO
  bit error_ack;
  bit error_iter;

  assign error = |mmacc_error
                 | seq_error;

  always_ff @(posedge clk)
    if (error) begin
      $display("%t > INFO: mmacc_error = 0x%0x", $time, mmacc_error);
      $display("%t > INFO: seq_error = 0x%0x", $time, seq_error);
      $display("%t > FAILURE !", $time);
      $finish;
    end

// ============================================================================================== --
// Design under test instance
// ============================================================================================== --
  assign reset_cache = 1'b0; // TODO not tested here.

  pep_mmacc_splitc_assembly
  #(
    .RAM_LATENCY               (RAM_LATENCY),
    .URAM_LATENCY              (URAM_LATENCY),
    .SLR_LATENCY               (SLR_LATENCY),
    .PHYS_RAM_DEPTH            (PHYS_RAM_DEPTH)
  ) pep_mmacc_splitc_assembly (
    .clk                        (clk),        // clock
    .s_rst_n                    (s_rst_n),    // synchronous reset

    .acc_decomp_data_avail      (acc_decomp_data_avail),
    .acc_decomp_ctrl_avail      (acc_decomp_ctrl_avail),
    .acc_decomp_data            (acc_decomp_data),
    .acc_decomp_sob             (acc_decomp_sob),
    .acc_decomp_eob             (acc_decomp_eob),
    .acc_decomp_sog             (acc_decomp_sog),
    .acc_decomp_eog             (acc_decomp_eog),
    .acc_decomp_sol             (acc_decomp_sol),
    .acc_decomp_eol             (acc_decomp_eol),
    .acc_decomp_soc             (acc_decomp_soc),
    .acc_decomp_eoc             (acc_decomp_eoc),
    .acc_decomp_pbs_id          (acc_decomp_pbs_id),
    .acc_decomp_last_pbs        (acc_decomp_last_pbs),
    .acc_decomp_full_throughput (acc_decomp_full_throughput),

    .ntt_acc_data_avail         (ntt_acc_data_avail),
    .ntt_acc_ctrl_avail         (ntt_acc_ctrl_avail),
    .ntt_acc_data               (ntt_acc_data),
    .ntt_acc_sob                (ntt_acc_sob),
    .ntt_acc_eob                (ntt_acc_eob),
    .ntt_acc_sol                (ntt_acc_sol),
    .ntt_acc_eol                (ntt_acc_eol),
    .ntt_acc_sog                (ntt_acc_sog),
    .ntt_acc_eog                (ntt_acc_eog),
    .ntt_acc_pbs_id             (ntt_acc_pbs_id),

    .batch_cmd                  (batch_cmd),
    .batch_cmd_avail            (batch_cmd_avail),

    .ldg_gram_main_wr_en        (ldg_gram_main_wr_en),
    .ldg_gram_main_wr_add       (ldg_gram_main_wr_add),
    .ldg_gram_main_wr_data      (ldg_gram_main_wr_data),

    .ldg_gram_subs_wr_en        (ldg_gram_subs_wr_en),
    .ldg_gram_subs_wr_add       (ldg_gram_subs_wr_add),
    .ldg_gram_subs_wr_data      (ldg_gram_subs_wr_data),

    .garb_ldg_main_avail_1h     (garb_ldg_main_avail_1h),
    .garb_ldg_subs_avail_1h     (garb_ldg_subs_avail_1h),

    .sxt_regf_wr_req_vld        (sxt_regf_wr_req_vld),
    .sxt_regf_wr_req_rdy        (sxt_regf_wr_req_rdy),
    .sxt_regf_wr_req            (sxt_regf_wr_req),

    .sxt_regf_wr_data_vld       (sxt_regf_wr_data_vld),
    .sxt_regf_wr_data_rdy       (sxt_regf_wr_data_rdy),
    .sxt_regf_wr_data           (sxt_regf_wr_data),

    .regf_sxt_wr_ack            (regf_sxt_wr_ack),

    .pbs_seq_cmd_enquiry        (pbs_seq_cmd_enquiry),
    .seq_pbs_cmd                (seq_pbs_cmd),
    .seq_pbs_cmd_avail          (seq_pbs_cmd_avail),

    .sxt_seq_done               (sxt_seq_done),
    .sxt_seq_done_pid           (sxt_seq_done_pid),

    .ks_boram_wr_en             (ks_boram_wr_en),
    .ks_boram_data              (ks_boram_data),
    .ks_boram_pid               (ks_boram_pid),
    .ks_boram_parity            (ks_boram_parity),

    .seq_boram_corr_wr_en       (seq_boram_corr_wr_en),
    .seq_boram_corr_data        (seq_boram_corr_data),
    .seq_boram_corr_pid         (seq_boram_corr_pid),

    .inc_bsk_wr_ptr             (inc_bsk_wr_ptr),
    .inc_bsk_rd_ptr             (inc_bsk_rd_ptr),

    .reset_cache                (reset_cache),

    .mmacc_error                (mmacc_error),
    .mmacc_rif_counter_inc      (/*UNUSED*/)
  );

  pep_sequencer #(
    .INST_FIFO_DEPTH   (INST_FIFO_DEPTH)
  ) pep_sequencer (
    .clk                 (clk    ),
    .s_rst_n             (s_rst_n),

    .use_bpip            (USE_BPIP),
    .use_bpip_opportunism(USE_BPIP_OPPORTUNISM),
    .bpip_timeout        ('hFFFFF),

    .inst                (inst),
    .inst_vld            (inst_vld),
    .inst_rdy            (inst_rdy),

    .inst_ack            (inst_ack),
    .inst_ack_br_loop    (/*UNUSED*/), // Not checked here
    .inst_load_blwe_ack  (/*UNUSED*/), // Not checked here

    .seq_ldg_cmd         (seq_ldg_cmd),
    .seq_ldg_vld         (seq_ldg_vld),
    .seq_ldg_rdy         (seq_ldg_rdy),

    .seq_ldb_cmd         (seq_ldb_cmd),
    .seq_ldb_vld         (seq_ldb_vld),
    .seq_ldb_rdy         (seq_ldb_rdy),

    .ldg_seq_done        (ldg_seq_done),
    .ldb_seq_done        (ldb_seq_done),

    .ks_seq_cmd_enquiry  (ks_seq_cmd_enquiry),
    .seq_ks_cmd          (seq_ks_cmd),
    .seq_ks_cmd_avail    (seq_ks_cmd_avail),

    .ks_seq_result       (ks_seq_result),
    .ks_seq_result_vld   (ks_seq_result_vld),
    .ks_seq_result_rdy   (ks_seq_result_rdy),

    .pbs_seq_cmd_enquiry (pbs_seq_cmd_enquiry),
    .seq_pbs_cmd         (seq_pbs_cmd),
    .seq_pbs_cmd_avail   (seq_pbs_cmd_avail),

    .sxt_seq_done        (sxt_seq_done),
    .sxt_seq_done_pid    (sxt_seq_done_pid),

    .bsk_if_batch_start_1h(/*UNUSED*/),
    .ksk_if_batch_start_1h(/*UNUSED*/),

    .seq_boram_corr_wr_en(seq_boram_corr_wr_en),
    .seq_boram_corr_data (seq_boram_corr_data),
    .seq_boram_corr_pid  (seq_boram_corr_pid),

    .reset_cache         (reset_cache),
    .reset_ks            (/*UNUSED*/),

    .seq_error           (seq_error),
    .seq_rif_info        (/*UNUSED*/),
    .seq_rif_counter_inc (/*UNUSED*/)

  );

  regfile
  #(
    .PEA_PERIOD   (PEA_PERIOD),
    .PEM_PERIOD   (PEM_PERIOD),
    .PEP_PERIOD   (PEP_PERIOD),
    .URAM_LATENCY (URAM_LATENCY)
  ) regfile (
    .clk                    (clk),
    .s_rst_n                (s_rst_n),

    .pem_regf_wr_req_vld    (pem_regf_wr_req_vld),
    .pem_regf_wr_req_rdy    (pem_regf_wr_req_rdy),
    .pem_regf_wr_req        (pem_regf_wr_req),

    .pem_regf_wr_data_vld   (pem_regf_wr_data_vld),
    .pem_regf_wr_data_rdy   (pem_regf_wr_data_rdy),
    .pem_regf_wr_data       (pem_regf_wr_data),

    .pem_regf_rd_req_vld    ('0),/*UNUSED*/
    .pem_regf_rd_req_rdy    (),  /*UNUSED*/
    .pem_regf_rd_req        (),  /*UNUSED*/

    .regf_pem_rd_data_avail (),  /*UNUSED*/
    .regf_pem_rd_data       (),  /*UNUSED*/
    .regf_pem_rd_last_word  (),  /*UNUSED*/
    .regf_pem_rd_is_body    (),  /*UNUSED*/
    .regf_pem_rd_last_mask  (),  /*UNUSED*/

    .pea_regf_wr_req_vld    ('0),/*UNUSED*/
    .pea_regf_wr_req_rdy    (),  /*UNUSED*/
    .pea_regf_wr_req        (),  /*UNUSED*/

    .pea_regf_wr_data_vld   ('0),  /*UNUSED*/
    .pea_regf_wr_data_rdy   (),  /*UNUSED*/
    .pea_regf_wr_data       (),  /*UNUSED*/

    .pea_regf_rd_req_vld    ('0),/*UNUSED*/
    .pea_regf_rd_req_rdy    (),  /*UNUSED*/
    .pea_regf_rd_req        (),  /*UNUSED*/

    .regf_pea_rd_data_avail (),  /*UNUSED*/
    .regf_pea_rd_data       (),  /*UNUSED*/
    .regf_pea_rd_last_word  (),  /*UNUSED*/
    .regf_pea_rd_is_body    (),  /*UNUSED*/
    .regf_pea_rd_last_mask  (),  /*UNUSED*/

    .pep_regf_wr_req_vld    (sxt_regf_wr_req_vld),
    .pep_regf_wr_req_rdy    (sxt_regf_wr_req_rdy),
    .pep_regf_wr_req        (sxt_regf_wr_req),

    .pep_regf_wr_data_vld   (sxt_regf_wr_data_vld),
    .pep_regf_wr_data_rdy   (sxt_regf_wr_data_rdy),
    .pep_regf_wr_data       (sxt_regf_wr_data),

    .pep_regf_rd_req_vld    ('0),/*UNUSED*/
    .pep_regf_rd_req_rdy    (),  /*UNUSED*/
    .pep_regf_rd_req        (),  /*UNUSED*/

    .regf_pep_rd_data_avail (),  /*UNUSED*/
    .regf_pep_rd_data       (),  /*UNUSED*/
    .regf_pep_rd_last_word  (),  /*UNUSED*/
    .regf_pep_rd_is_body    (),  /*UNUSED*/
    .regf_pep_rd_last_mask  (),  /*UNUSED*/

    .pem_wr_ack             (),  /*UNUSED*/
    .pea_wr_ack             (),  /*UNUSED*/
    .pep_wr_ack             (regf_sxt_wr_ack)
  );

// ============================================================================================== --
// NTT loopback
// ============================================================================================== --
  logic [NTT_SR_DEPTH-1:0]                                ntt_acc_ctrl_avail_sr;
  logic [NTT_SR_DEPTH-1:0][PSI-1:0][R-1:0][MOD_Q_W-1:0]   ntt_acc_data_sr;
  logic [NTT_SR_DEPTH-1:0]                                ntt_acc_sob_sr;
  logic [NTT_SR_DEPTH-1:0]                                ntt_acc_eob_sr;
  logic [NTT_SR_DEPTH-1:0]                                ntt_acc_sol_sr;
  logic [NTT_SR_DEPTH-1:0]                                ntt_acc_eol_sr;
  logic [NTT_SR_DEPTH-1:0]                                ntt_acc_sog_sr;
  logic [NTT_SR_DEPTH-1:0]                                ntt_acc_eog_sr;
  logic [NTT_SR_DEPTH-1:0][BPBS_ID_W-1:0]                 ntt_acc_pbs_id_sr;

  logic                                                     ntt_in_avail;
  logic [CHUNK_NB-1:0][ACC_DECOMP_COEF_NB-1:0][MOD_Q_W-1:0] ntt_in_data;
  logic [CHUNK_NB-1:0]                                      ntt_in_sob;
  logic [CHUNK_NB-1:0]                                      ntt_in_sog;
  logic [CHUNK_NB-1:0]                                      ntt_in_sol;
  logic                                                     ntt_in_eob;
  logic                                                     ntt_in_eog;
  logic                                                     ntt_in_eol;
  logic [BPBS_ID_W-1:0]                                     ntt_in_pbs_id;

  always_ff @(posedge clk)
    if (!s_rst_n) ntt_in_avail <= 1'b0;
    else          ntt_in_avail <= acc_decomp_ctrl_avail & acc_decomp_eoc;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      ntt_in_eob <= 1'b0;
      ntt_in_eog <= 1'b0;
      ntt_in_eol <= 1'b0;
      ntt_in_pbs_id <= '0;
    end
    else begin
      ntt_in_eob <= acc_decomp_eob;
      ntt_in_eog <= acc_decomp_eog;
      ntt_in_eol <= acc_decomp_eol;
      ntt_in_pbs_id <= acc_decomp_pbs_id;
    end

  generate
    if (CHUNK_NB > 1) begin : gen_chunk
      always_ff @(posedge clk)
        if (!s_rst_n) begin
          ntt_in_data <= '0;
          ntt_in_sob  <= '0;
          ntt_in_sog  <= '0;
          ntt_in_sol  <= '0;
        end
        else begin
          if (acc_decomp_ctrl_avail) begin
            ntt_in_data <= {ntt_in_data[CHUNK_NB-2:0],acc_decomp_data};
            ntt_in_sob  <= {ntt_in_sob[CHUNK_NB-2:0],acc_decomp_sob};
            ntt_in_sog  <= {ntt_in_sog[CHUNK_NB-2:0],acc_decomp_sog};
            ntt_in_sol  <= {ntt_in_sol[CHUNK_NB-2:0],acc_decomp_sol};
          end
        end
    end
    else begin : gen_no_chunk
      always_ff @(posedge clk)
        if (!s_rst_n) begin
          ntt_in_data <= '0;
          ntt_in_sob  <= '0;
          ntt_in_sog  <= '0;
          ntt_in_sol  <= '0;
        end
        else begin
          if (acc_decomp_ctrl_avail) begin
            ntt_in_data <= acc_decomp_data;
            ntt_in_sob  <= acc_decomp_sob;
            ntt_in_sog  <= acc_decomp_sog;
            ntt_in_sol  <= acc_decomp_sol;
          end
        end
    end
  endgenerate

  always_ff @(posedge clk)
    if (!s_rst_n) ntt_acc_ctrl_avail_sr <= '0;
    else          ntt_acc_ctrl_avail_sr <= {ntt_acc_ctrl_avail_sr[NTT_SR_DEPTH-2:0],ntt_in_avail};

  always_ff @(posedge clk) begin
    ntt_acc_data_sr       <= {ntt_acc_data_sr[NTT_SR_DEPTH-2:0],  ntt_in_data};
    ntt_acc_sob_sr        <= {ntt_acc_sob_sr[NTT_SR_DEPTH-2:0],   |ntt_in_sob};
    ntt_acc_eob_sr        <= {ntt_acc_eob_sr[NTT_SR_DEPTH-2:0],   ntt_in_eob};
    ntt_acc_sol_sr        <= {ntt_acc_sol_sr[NTT_SR_DEPTH-2:0],   |ntt_in_sol};
    ntt_acc_eol_sr        <= {ntt_acc_eol_sr[NTT_SR_DEPTH-2:0],   ntt_in_eol};
    ntt_acc_sog_sr        <= {ntt_acc_sog_sr[NTT_SR_DEPTH-2:0],   |ntt_in_sog};
    ntt_acc_eog_sr        <= {ntt_acc_eog_sr[NTT_SR_DEPTH-2:0],   ntt_in_eog};
    ntt_acc_pbs_id_sr     <= {ntt_acc_pbs_id_sr[NTT_SR_DEPTH-2:0],ntt_in_pbs_id};
  end

  assign ntt_acc_data_avail = {PSI*R{ntt_acc_ctrl_avail_sr[NTT_SR_DEPTH-1]}};
  assign ntt_acc_ctrl_avail = ntt_acc_ctrl_avail_sr[NTT_SR_DEPTH-1];
  assign ntt_acc_data       = ntt_acc_data_sr[NTT_SR_DEPTH-1];
  assign ntt_acc_sob        = ntt_acc_sob_sr[NTT_SR_DEPTH-1];
  assign ntt_acc_eob        = ntt_acc_eob_sr[NTT_SR_DEPTH-1];
  assign ntt_acc_sol        = ntt_acc_sol_sr[NTT_SR_DEPTH-1];
  assign ntt_acc_eol        = ntt_acc_eol_sr[NTT_SR_DEPTH-1];
  assign ntt_acc_sog        = ntt_acc_sog_sr[NTT_SR_DEPTH-1];
  assign ntt_acc_eog        = ntt_acc_eog_sr[NTT_SR_DEPTH-1];
  assign ntt_acc_pbs_id     = ntt_acc_pbs_id_sr[NTT_SR_DEPTH-1];

// ============================================================================================== --
// Scenario
// ============================================================================================== --
// ---------------------------------------------------------------------------------------------- --
// FSM
// ---------------------------------------------------------------------------------------------- --
  typedef enum {ST_IDLE,
                ST_FILL_MEM,
                ST_PROCESS_FULL_THROUGHPUT,
                ST_PROCESS_RANDOM,
                ST_DONE} state_e;

  state_e state;
  state_e next_state;
  logic st_idle;
  logic st_fill_mem;
  logic st_process_full_throughput;
  logic st_process_random;
  logic st_done;

  logic start;
  logic [1:0] fill_mem_done;
  logic proc_tput_done;
  logic proc_random_done;

  always_comb
    case (state)
      ST_IDLE:
        next_state = start ? ST_FILL_MEM : state;
      ST_FILL_MEM:
        next_state = (fill_mem_done == '1) ? ST_PROCESS_FULL_THROUGHPUT : state;
      ST_PROCESS_FULL_THROUGHPUT:
        next_state = proc_tput_done ? ST_PROCESS_RANDOM : state;
      ST_PROCESS_RANDOM:
        next_state = proc_random_done ? ST_DONE : state;
      ST_DONE:
        next_state = state;
    endcase

  always_ff @(posedge clk)
    if (!s_rst_n) state <= ST_IDLE;
    else          state <= next_state;

  assign st_idle                    = state == ST_IDLE;
  assign st_fill_mem                = state == ST_FILL_MEM;
  assign st_process_full_throughput = state == ST_PROCESS_FULL_THROUGHPUT;
  assign st_process_random          = state == ST_PROCESS_RANDOM;
  assign st_done                    = state == ST_DONE;

// ---------------------------------------------------------------------------------------------- --
// External stimuli
// ---------------------------------------------------------------------------------------------- --
// Fake a pem accessing the regfile, to make it answer not on every cycle.

  // Fake pem access
  assign pem_regf_wr_req.reg_id     = 0;
  assign pem_regf_wr_req.start_word = 0;
  assign pem_regf_wr_req.word_nb_m1 = REGF_BLWE_WORD_PER_RAM+1;

  assign pem_regf_wr_data_vld = '1;
  assign pem_regf_wr_data     = '1;

  always_ff @(posedge clk)
    if (!s_rst_n) pem_regf_wr_req_vld  <= 1'b0;
    else          pem_regf_wr_req_vld  <= st_process_random ? $urandom() : 1'b0;

// ---------------------------------------------------------------------------------------------- --
// Fill GLWE
// ---------------------------------------------------------------------------------------------- --
  // [0] : main, [1] subs
  logic [1:0][GRAM_NB-1:0]                 wr_gram_wr_en;
  integer                                  wr_gram_word_cnt[1:0];
  logic [1:0][GLWE_RAM_ADD_W-1:0]          wr_gram_add_ofs;
  logic [1:0][PSI-1:0][R-1:0][MOD_Q_W-1:0] wr_gram_data;

  logic [1:0][GRAM_NB-1:0]                 garb_avail_1h;
  assign garb_avail_1h = {garb_ldg_subs_avail_1h,
                          garb_ldg_main_avail_1h};


  // Write in GRAM
  always_comb
    for (int g=0; g<GRAM_NB; g=g+1) begin
      ldg_gram_main_wr_en[g]   = wr_gram_wr_en[0][g];
      ldg_gram_main_wr_add[g]  = wr_gram_word_cnt[0] + wr_gram_add_ofs[0];
      ldg_gram_main_wr_data[g] = wr_gram_data[0][SUBS_PSI+:MAIN_PSI];

      ldg_gram_subs_wr_en[g]   = wr_gram_wr_en[1][g];
      ldg_gram_subs_wr_add[g]  = wr_gram_word_cnt[1] + wr_gram_add_ofs[1];
      ldg_gram_subs_wr_data[g] = wr_gram_data[1][0+:SUBS_PSI];
    end

  generate
    for (genvar gen_i=0; gen_i<2; gen_i=gen_i+1) begin : gen_split_loop // [0] main, [1] subs
      integer                    wr_gram_word_cnt_l;
      logic [GRAM_NB-1:0]        wr_gram_wr_en_l;
      logic [GLWE_RAM_ADD_W-1:0] wr_gram_add_ofs_l;
      logic [PSI-1:0][R-1:0][MOD_Q_W-1:0] wr_gram_data_l;

      integer                    wr_gram_word_cnt_lD;
      logic                      wr_last_gram_word_cnt;

      assign wr_gram_word_cnt[gen_i] = wr_gram_word_cnt_l;
      assign wr_gram_wr_en[gen_i]    = wr_gram_wr_en_l;
      assign wr_gram_add_ofs[gen_i]  = wr_gram_add_ofs_l;

        for (genvar gen_p=0; gen_p<PSI; gen_p=gen_p+1)
          for (genvar gen_r=0; gen_r<R; gen_r=gen_r+1)
            assign wr_gram_data[gen_i][gen_p][gen_r] = wr_gram_data_l[gen_p][gen_r];

      assign wr_last_gram_word_cnt = wr_gram_word_cnt_l == GLWE_WORD_NB_IN_GRAM-1;
      assign wr_gram_word_cnt_lD   = |wr_gram_wr_en_l ? wr_last_gram_word_cnt ? '0 : wr_gram_word_cnt_l + 1 : wr_gram_word_cnt_l;

      always_ff @(posedge clk)
        if (!s_rst_n) wr_gram_word_cnt_l <= '0;
        else          wr_gram_word_cnt_l <= wr_gram_word_cnt_lD;

      integer                          wr_gram_pid;
      integer                          wr_gram_sample_cnt;

      assign fill_mem_done[gen_i] = wr_gram_pid == TOTAL_PBS_NB;
      always_ff @(posedge clk)
        if (!s_rst_n) begin
          wr_gram_wr_en_l    <= '0;
          wr_gram_sample_cnt <= '0;
          wr_gram_data_l     <= 'x;
          wr_gram_add_ofs_l  <= 'x;
          wr_gram_pid        <= '0;
        end
        else begin
          wr_gram_wr_en_l <= '0;
          if (st_fill_mem && (wr_gram_pid < TOTAL_PBS_NB) && (garb_avail_1h[gen_i] == '1)) begin
            logic [PID_W-1:0] pid;
            logic [PSI-1:0][R-1:0][MOD_Q_W-1:0] wr_data;

            pid = wr_gram_pid;
            wr_gram_wr_en_l   <= 1 << (pid % GRAM_NB);
            wr_gram_add_ofs_l <= (pid / GRAM_NB) * GLWE_WORD_NB_IN_GRAM;

            for (int p=0; p<PSI; p=p+1)
              for (int r=0; r<R; r=r+1) begin
                //wr_data[p][r] = {$urandom(),$urandom()};
                // Use the following instead to ease debug
                wr_data[p][r] = rev_order((wr_gram_sample_cnt*R*PSI)%N + p*R+r);
                wr_data[p][r] = (wr_gram_sample_cnt*R*PSI)/N * N + wr_data[p][r];
                //$display("PID=%0d [%0d] data=0x%0x",pid,wr_gram_sample_cnt*R*PSI+p*R+r,wr_data[p][r]);
              end

            wr_gram_data_l <= wr_data;

            if (wr_gram_sample_cnt == GLWE_WORD_NB_IN_GRAM-1) begin
              wr_gram_pid <= wr_gram_pid + 1;

              wr_gram_sample_cnt <= '0;
            end
            else begin
              wr_gram_sample_cnt <= wr_gram_sample_cnt + 1;
            end
          end
        end

    end // gen_split_loop
  endgenerate
// ---------------------------------------------------------------------------------------------- --
// DOP Instruction
// ---------------------------------------------------------------------------------------------- --
  pep_inst_t inst_tmp;
  pep_inst_t inst_tmp2;

  assign inst_tmp2.dop     = DOP_PBS;
  assign inst_tmp2.gid     = inst_tmp.gid;
  assign inst_tmp2.src_rid = inst_tmp.src_rid % REGF_REG_NB;
  assign inst_tmp2.dst_rid = inst_tmp.dst_rid % REGF_REG_NB;

  assign inst = inst_tmp2;

  stream_source #(
    .FILENAME   ("random"),
    .DATA_TYPE  ("ascii_hex"),
    .DATA_W     (PEP_INST_W),
    .RAND_RANGE (DATA_RAND_RANGE),
    .KEEP_VLD   (1'b0),
    .MASK_DATA  ("x")
  ) inst_stream_source (
      .clk       (clk),
      .s_rst_n   (s_rst_n),

      .data      (inst_tmp),
      .vld       (inst_vld),
      .rdy       (inst_rdy),

      .throughput(DATA_RAND_RANGE_W'(INST_THROUGHPUT))
  );

  initial begin
    if (!inst_stream_source.open()) begin
      $fatal(1, "%t > ERROR: Opening inst_stream_source stream source", $time);
    end
    wait(s_rst_n);
    @(posedge clk);
    wait (st_process_full_throughput);
    inst_stream_source.start(SAMPLE_NB);
  end

// ---------------------------------------------------------------------------------------------- --
// Load
// ---------------------------------------------------------------------------------------------- --
  localparam int LD_CMD_W = LOAD_BLWE_CMD_W > LOAD_GLWE_CMD_W ? LOAD_BLWE_CMD_W : LOAD_GLWE_CMD_W;

  logic [1:0][LD_CMD_W-1:0] ld_cmd;
  logic [1:0]               ld_cmd_vld;
  logic [1:0]               ld_cmd_rdy;
  logic [1:0]               ld_done;

  assign ld_cmd[LDG_IDX]     = seq_ldg_cmd;
  assign ld_cmd_vld[LDG_IDX] = seq_ldg_vld;
  assign seq_ldg_rdy         = ld_cmd_rdy[LDG_IDX];
  assign ldg_seq_done        = ld_done[LDG_IDX];

  assign ld_cmd[LDB_IDX]     = seq_ldb_cmd;
  assign ld_cmd_vld[LDB_IDX] = seq_ldb_vld;
  assign seq_ldb_rdy         = ld_cmd_rdy[LDB_IDX];
  assign ldb_seq_done        = ld_done[LDB_IDX];

  // Do a shift register to modelize the load path.
  generate
    for (genvar gen_i=0; gen_i<2; gen_i=gen_i+1) begin : gen_ld_loop
      localparam int LAT_L = LD_LATENCY[gen_i];
      logic [LAT_L-1:0] ld_avail_sr;
      logic [LAT_L-1:0] ld_avail_srD;

      logic [LAT_L-1:0][LD_CMD_W-1:0] ld_cmd_sr;
      logic [LAT_L-1:0][LD_CMD_W-1:0] ld_cmd_srD;

      logic rand_val;
      always_ff @(posedge clk)
        rand_val <= $urandom();

      assign ld_cmd_rdy[gen_i] = rand_val;

      assign ld_avail_srD[0]         = ld_cmd_vld[gen_i] & ld_cmd_rdy[gen_i];
      assign ld_avail_srD[LAT_L-1:1] = ld_avail_sr[LAT_L-2:0];

      assign ld_cmd_srD[0]         = ld_cmd[gen_i];
      assign ld_cmd_srD[LAT_L-1:1] = ld_cmd_sr[LAT_L-2:0];

      always_ff @(posedge clk)
        if (!s_rst_n) ld_avail_sr <= '0;
        else          ld_avail_sr <= ld_avail_srD;

      always_ff @(posedge clk)
        ld_cmd_sr <= ld_cmd_srD; // for debug

      assign ld_done[gen_i] = ld_avail_sr[LAT_L-1];
    end
  endgenerate

// ---------------------------------------------------------------------------------------------- --
// Start enquiry
// ---------------------------------------------------------------------------------------------- --
  logic start_enquiry;

  always_ff @(posedge clk)
    if (!s_rst_n) start_enquiry <= 1'b1;
    else          start_enquiry <= 1'b0;

// ---------------------------------------------------------------------------------------------- --
// Key switch
// ---------------------------------------------------------------------------------------------- --
  logic [KS_LATENCY + LBX-1:0]    ks_cmd_avail_sr;
  logic [KS_LATENCY + LBX-1:0]    ks_cmd_avail_srD;
  ks_cmd_t [KS_LATENCY + LBX-1:0] ks_cmd_sr;
  ks_cmd_t [KS_LATENCY + LBX-1:0] ks_cmd_srD;

  assign ks_cmd_avail_srD[0] = seq_ks_cmd_avail;
  assign ks_cmd_srD[0]       = seq_ks_cmd;

  assign ks_cmd_avail_srD[KS_LATENCY + LBX-1:1] = ks_cmd_avail_sr[KS_LATENCY + LBX-2:0];
  assign ks_cmd_srD[KS_LATENCY + LBX-1:1]       = ks_cmd_sr[KS_LATENCY + LBX-2:0];

  always_ff @(posedge clk)
    if (!s_rst_n) ks_cmd_avail_sr <= '0;
    else          ks_cmd_avail_sr <= ks_cmd_avail_srD;

  always_ff @(posedge clk)
    ks_cmd_sr <= ks_cmd_srD;

  ks_result_t ks_res;
  logic       ks_res_vld;
  logic       ks_res_vld_tmp;
  logic       ks_res_rdy;
  integer     ks_res_loop;
  integer     ks_res_loopD;
  logic [BATCH_PBS_NB-1:0][LWE_COEF_W-1:0] ks_res_lwe_a;
  logic [BATCH_PBS_NB-1:0][KS_MAX_ERROR_W-1:0] ks_res_corr_a;
  pointer_t                                ks_res_wp;
  pointer_t                                ks_res_rp;

  assign ks_res_loopD = ks_res_vld_tmp ? ks_res_loop == KS_LOOP_MAX-1 ? '0 : ks_res_loop + 1 : ks_res_loop;

  always_comb begin
    ks_res_wp = '0;
    ks_res_rp = '0;
    for (int i=0; i<LBX; i=i+1) begin
      ks_res_wp = ks_cmd_avail_sr[KS_LATENCY+i] ? ks_cmd_sr[KS_LATENCY+i].wp : ks_res_wp;
      ks_res_rp = ks_cmd_avail_sr[KS_LATENCY+i] ? ks_cmd_sr[KS_LATENCY+i].rp : ks_res_rp;
    end
  end

  always_comb
    for (int i=0; i<BATCH_PBS_NB; i=i+1) begin
      ks_res_lwe_a[i][3:0]            = (ks_res_rp + i);
      ks_res_lwe_a[i][LWE_COEF_W-1:4] = ks_res_loop;
      ks_res_corr_a[i]                = i;
    end

  assign ks_res_vld_tmp = |ks_cmd_avail_sr[KS_LATENCY +: LBX];
  assign ks_res_vld     = ks_res_vld_tmp & (ks_res_loop < LWE_K);
  assign ks_res.lwe_a   = ks_res_lwe_a;
  assign ks_res.corr_a  = ks_res_corr_a;
  assign ks_res.ks_loop = ks_res_loop;
  assign ks_res.wp      = ks_res_wp;
  assign ks_res.rp      = ks_res_rp;

  always_ff @(posedge clk)
    if (!s_rst_n) ks_res_loop <= '0;
    else          ks_res_loop <= ks_res_loopD;

  fifo_reg #(
    .WIDTH       (KS_RESULT_W),
    .DEPTH       (2*LBX),
    .LAT_PIPE_MH ({1'b1, 1'b1})
  ) ks_fifo_reg (
    .clk      (clk),
    .s_rst_n  (s_rst_n),

    .in_data  (ks_res),
    .in_vld   (ks_res_vld),
    .in_rdy   (ks_res_rdy),

    .out_data (ks_seq_result),
    .out_vld  (ks_seq_result_vld),
    .out_rdy  (ks_seq_result_rdy)
  );

  integer ks_res_cnt;
  integer ks_res_cntD;

  assign ks_res_cntD = (ks_seq_result_vld && ks_seq_result_rdy) ? ks_res_cnt == LWE_K-1 ? '0 : ks_res_cnt + 1 : ks_res_cnt;

  always_ff @(posedge clk)
    if (!s_rst_n) ks_res_cnt <= '0;
    else          ks_res_cnt <= ks_res_cntD;

  assign ks_seq_cmd_enquiry = (ks_seq_result_vld & ks_seq_result_rdy & ((ks_res_cnt % LBX == LBX-1)))
                             | start_enquiry
                             | (ks_cmd_avail_sr[KS_LATENCY +LBX-1] & (ks_res_loop >= LWE_K));


  always_ff @(posedge clk)
    if ((ks_seq_result_vld && ks_seq_result_rdy && ((ks_res_cnt % LBX == LBX-1)))
        && (ks_cmd_avail_sr[KS_LATENCY +LBX-1] && (ks_res_loop >= LWE_K)))
      $fatal(1,"%t > ERROR: KS enquiry overflow!",$time);


  always_ff @(posedge clk)
    if (ks_res_vld)
      assert(ks_res_rdy)
      else begin
        $fatal(1,"%t > ERROR: ks_fifo_reg overflow!",$time);
      end

  logic [PID_W:0] ks_boram_q [$];

  always_ff @(posedge clk)
    if (ks_cmd_avail_sr[0] && ((ks_cmd_sr[0].ks_loop + LBX) >= LWE_K_P1)) begin
      pointer_t max;
      logic parity;
      max.pt = ks_cmd_sr[0].wp.pt;
      max.c  = ks_cmd_sr[0].wp.c ^ ks_cmd_sr[0].rp.c;
      parity = ks_cmd_sr[0].ks_loop_c;
      for (int i=0; i<TOTAL_PBS_NB; i=i+1) begin
        pointer_t p;
        p.pt = (ks_cmd_sr[0].rp.pt + i) % TOTAL_PBS_NB;
        p.c  = (ks_cmd_sr[0].rp.pt + i) / TOTAL_PBS_NB;

        if (p < max) begin
          logic [PID_W:0] tmp;
          tmp[PID_W-1:0] = p.pt;
          tmp[PID_W]     = parity;
          ks_boram_q.push_back(tmp);
          //$display("%t > INFO: Push pid=0x%0x parity=%d",$time,p.pt,parity);
        end
      end
    end

  always_ff @(posedge clk) begin
    ks_boram_wr_en <= 1'b0;
    if (ks_boram_q.size() > 0) begin
      logic [PID_W-1:0] pid;
      logic             parity;
      {parity,pid} = ks_boram_q.pop_front();
      ks_boram_wr_en  <= 1'b1;
      ks_boram_pid    <= pid;
      ks_boram_parity <= parity;
      ks_boram_data   <= pid; //$urandom(); -- cannot put random, due to boram internal check...
                              // TODO find a way to keep the value, if the CT has not been output.
    end
  end


// ---------------------------------------------------------------------------------------------- --
// BSK
// ---------------------------------------------------------------------------------------------- --
  logic [BSK_SR_DEPTH-1:0] inc_bsk_wr_ptr_sr;

  assign inc_bsk_wr_ptr = inc_bsk_wr_ptr_sr[BSK_SR_DEPTH-1];

  always_ff @(posedge clk)
    if (!s_rst_n) inc_bsk_wr_ptr_sr <= '0;
    else          inc_bsk_wr_ptr_sr <= {inc_bsk_wr_ptr_sr, seq_pbs_cmd_avail};

// ---------------------------------------------------------------------------------------------- --
// Check
// ---------------------------------------------------------------------------------------------- --
  // Check SXT pid are in order.
  integer sxt_pid;
  bit warn_sxt_pid;

  always_ff @(posedge clk)
    if (!s_rst_n) sxt_pid <= '0;
    else          sxt_pid <= sxt_seq_done ? (sxt_pid + 1) % TOTAL_PBS_NB : sxt_pid;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      warn_sxt_pid <= 1'b0;
    end
    else begin
      warn_sxt_pid <= 1'b0;
      if (sxt_seq_done)
        assert(sxt_pid == sxt_seq_done_pid)
        else begin
          $display("%t > INFO: Disorder SXT pid exp=%0d seen=%0d", $time, sxt_pid, sxt_seq_done_pid);
          warn_sxt_pid <= 1'b1;
        end
    end

// ---------------------------------------------------------------------------------------------- --
// End of test
// ---------------------------------------------------------------------------------------------- --
  integer inst_cnt;
  integer inst_cntD;

  integer sxt_cnt;
  integer sxt_cntD;

  integer inst_ack_cnt;
  integer inst_ack_cntD;

  assign inst_cntD     = (inst_vld && inst_rdy) ? inst_cnt + 1 : inst_cnt;
  assign sxt_cntD      = sxt_seq_done ? sxt_cnt + 1 : sxt_cnt;
  assign inst_ack_cntD = inst_ack ? inst_ack_cnt + 1 : inst_ack_cnt;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      inst_cnt     <= '0;
      sxt_cnt      <= '0;
      inst_ack_cnt <= '0;
    end
    else begin
      inst_cnt     <= inst_cntD;
      sxt_cnt      <= sxt_cntD;
      inst_ack_cnt <= inst_ack_cntD;
    end

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      if (inst_vld && inst_rdy && (inst_cntD%50 == 0))
        $display("%t > INFO: INPUT instruction #%0d", $time, inst_cntD);
      if (sxt_seq_done && (sxt_cntD%50 == 0))
        $display("%t > INFO: DONE sxt cmd #%0d", $time, sxt_cntD);
    end

  assign proc_tput_done   = inst_vld & inst_rdy & (inst_cnt == SAMPLE_THROUGHPUT_NB-1);
  assign proc_random_done = inst_vld & inst_rdy & (inst_cnt == SAMPLE_NB-1);

  initial begin
    end_of_test <= 1'b0;
    error_ack   <= 1'b0;
    error_iter  <= 1'b0;

    start       <= 1'b0;

    wait (s_rst_n);
    @(posedge clk) start <= 1'b1;

    wait (inst_cnt == SAMPLE_NB);
    $display("%t > INFO: All instructions sent",$time);
    wait (sxt_cnt == SAMPLE_NB);
    $display("%t > INFO: All ciphertexts processed",$time);

    repeat(10) @(posedge clk);

    assert(inst_ack_cnt == SAMPLE_NB)
    else begin
      $display("%t > ERROR: Wrong number of inst_ack. exp=%0d seen=%0d", $time, SAMPLE_NB, inst_ack_cnt);
      error_ack <= 1'b1;
    end

    end_of_test <= 1'b1;

  end


endmodule
