// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// pep_mmacc_sample_extract testbench.
// Support natural and reverse (=pcg) order.
// ==============================================================================================

`include "pep_mmacc_splitc_sxt_macro_inc.sv"

module tb_pep_mmacc_sample_extract;
  import common_definition_pkg::*;
  import param_tfhe_pkg::*;
  import ntt_core_common_param_pkg::*;
  import top_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import pep_mmacc_common_param_pkg::*;
  import regf_common_param_pkg::*;
  import pep_mmacc_splitc_sxt_pkg::*;
  import hpu_common_instruction_pkg::*;

`timescale 1ns/10ps

// ============================================================================================== --
// Parameter / localparam
// ============================================================================================== --
  localparam int CLK_HALF_PERIOD = 1;
  localparam int ARST_ACTIVATION = 17;

  localparam int RAM_LATENCY         = 2;
  localparam int PHYS_RAM_DEPTH      = 1024;
  parameter  int DATA_LATENCY        = RAM_LATENCY+3; // Latency for read data to come back

  // For split architecture
  parameter  int SLR_LATENCY         = 2*3; // Number of cycles needed for a return journey through an SLR boundary
  parameter  int DATA_THRESHOLD      = 8; // Number of data sent to regf for 1 request

  parameter  int TPUT_SAMPLE_NB = 500;
  parameter  int RAND_SAMPLE_NB = 500;
  localparam int SAMPLE_NB      = TPUT_SAMPLE_NB + RAND_SAMPLE_NB;

  parameter int DATA_RAND_RANGE = 1023;
  parameter int OP_W            = MOD_Q_W;

  localparam int POLY_CHUNK_NB = N/REGF_COEF_NB;
  localparam int PBS_CHUNK_NB  = POLY_CHUNK_NB*GLWE_K + 1;

  parameter int PEA_PERIOD   = REGF_COEF_NB;
  parameter int PEM_PERIOD   = 8;
  parameter int PEP_PERIOD   = 1;
  parameter int URAM_LATENCY = 1+RAM_LATENCY;

  localparam int GLWE_WORD_NB_IN_GRAM = (STG_ITER_NB * GLWE_K_P1);

  `PEP_MMACC_SPLITC_SXT_LOCALPARAM(R,PSI,DATA_LATENCY,REGF_COEF_NB,REGF_COEF_PER_URAM_WORD,REGF_BLWE_WORD_PER_RAM,DATA_THRESHOLD)

  initial begin
    $display("> INFO: POLY_CHUNK_NB = %0d",POLY_CHUNK_NB);
    $display("> INFO: PBS_CHUNK_NB  = %0d",PBS_CHUNK_NB);
    $display("> INFO: GRAM_CHUNK_NB = %0d",GRAM_CHUNK_NB);
    $display("> INFO: CHUNK_GRAM_NB = %0d",CHUNK_GRAM_NB);
    $display("> INFO: REGF_COEF_NB  = %0d",REGF_COEF_NB);
    $display("> INFO: RD_COEF_NB    = %0d",RD_COEF_NB);
    $display("> INFO: RD_DEPTH_GUNIT    = %0d",RD_DEPTH_GUNIT);
    $display("> INFO: RD_DEPTH_MIN    = %0d",RD_DEPTH_MIN);
    $display("> INFO: DATA_LATENCY    = %0d",DATA_LATENCY);
    $display("> INFO: PERM_CYCLE_NB    = %0d",PERM_CYCLE_NB);
  end


// ============================================================================================== --
// type
// ============================================================================================== --
  typedef struct packed {
    logic [7:0]               pbs_id;
    logic [7:0]               poly_id;
    logic [STG_ITER_W-1:0]    stg_iter;
    logic [PSI_W-1:0]         psi;
    logic [R_W-1:0]           r;
  } data_t;

  localparam int DATA_W = $bits(data_t);

  initial begin
    if (DATA_W > OP_W)
      $fatal(1,"> ERROR: DATA_W must be <= OP_W in this testbench.");
  end

  typedef struct packed {
    logic [7:0]                     batch_id;
    logic [7:0]                     pbs_nb;
  } batch_info_t;

  localparam int BATCH_INFO_W = $bits(batch_info_t);

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
  // From GRAM arbiter
  logic [GRAM_NB-1:0]                                     garb_sxt_avail_1h;

  // From sfifo
  logic [MMACC_INTERN_CMD_W-1:0]                          sfifo_sxt_icmd;
  logic                                                   sfifo_sxt_vld;
  logic                                                   sfifo_sxt_rdy;

  // sxt <-> body RAM
  logic [LWE_COEF_W-1:0]                                  boram_sxt_data;
  logic                                                   boram_sxt_data_vld;
  logic                                                   boram_sxt_data_rdy;

  // sxt <-> regfile
  // write
  logic                                                   sxt_regf_wr_req_vld;
  logic                                                   sxt_regf_wr_req_rdy;
  logic [REGF_WR_REQ_W-1:0]                               sxt_regf_wr_req;

  logic [REGF_COEF_NB-1:0]                                sxt_regf_wr_data_vld;
  logic [REGF_COEF_NB-1:0]                                sxt_regf_wr_data_rdy;
  logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0]                   sxt_regf_wr_data;

  logic                                                   regf_sxt_wr_ack;

  // CT done
  logic                                                   sxt_seq_done; // pulse
  logic [PID_W-1:0]                                       sxt_seq_done_pid;

  // Fake pem write req
  logic                                                   pem_regf_wr_req_vld;
  logic                                                   pem_regf_wr_req_rdy;
  regf_wr_req_t                                           pem_regf_wr_req;

  logic [REGF_COEF_NB-1:0]                                pem_regf_wr_data_vld;
  logic [REGF_COEF_NB-1:0]                                pem_regf_wr_data_rdy;
  logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0]                   pem_regf_wr_data;

  logic                                                   gram_error;

  // To fill the GRAM
  logic [GRAM_NB-1:0][PSI-1:0][R-1:0]                     ext_gram_wr_en;
  logic [GRAM_NB-1:0][PSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0] ext_gram_wr_add;
  logic [GRAM_NB-1:0][PSI-1:0][R-1:0][OP_W-1:0]           ext_gram_wr_data;

  // Create disturbance on regfile access
  logic                                                   pep_regf_wr_req_vld;
  logic                                                   pep_regf_wr_req_rdy;
  logic [REGF_WR_REQ_W-1:0]                               pep_regf_wr_req;

  logic [REGF_COEF_NB-1:0]                                pep_regf_wr_data_vld;
  logic [REGF_COEF_NB-1:0]                                pep_regf_wr_data_rdy;
  logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0]                   pep_regf_wr_data;

// ============================================================================================== --
// Error
// ============================================================================================== --
  bit error;
  bit error_data;
  bit error_req;
  bit error_ack;
  bit [1:0] error_gram;

  assign error = error_data | error_req | error_ack | |error_gram;

  always_ff @(posedge clk)
    if (error) begin
      $display("%t > FAILURE !", $time);
      $finish;
    end

// ============================================================================================== --
// Design under test instance
// ============================================================================================== --
  // Read from GRAM
  logic [GRAM_NB-1:0][PSI-1:0][R-1:0]                     sxt_gram_rd_en;
  logic [GRAM_NB-1:0][PSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0] sxt_gram_rd_add;
  logic [GRAM_NB-1:0][PSI-1:0][R-1:0][OP_W-1:0]           gram_sxt_rd_data;
  logic [GRAM_NB-1:0][PSI-1:0][R-1:0]                     gram_sxt_rd_data_avail;
  pep_mmacc_splitc_sxt_assembly
  #(
    .DATA_LATENCY       (DATA_LATENCY),
    .SLR_LATENCY        (SLR_LATENCY)
  ) pep_mmacc_splitc_sxt_assembly (
    .clk                    (clk),
    .s_rst_n                (s_rst_n),

    .sfifo_sxt_icmd         (sfifo_sxt_icmd),
    .sfifo_sxt_vld          (sfifo_sxt_vld),
    .sfifo_sxt_rdy          (sfifo_sxt_rdy),

    .boram_sxt_data         (boram_sxt_data),
    .boram_sxt_data_vld     (boram_sxt_data_vld),
    .boram_sxt_data_rdy     (boram_sxt_data_rdy),

    .sxt_regf_wr_req_vld    (sxt_regf_wr_req_vld),
    .sxt_regf_wr_req_rdy    (sxt_regf_wr_req_rdy),
    .sxt_regf_wr_req        (sxt_regf_wr_req),

    .sxt_regf_wr_data_vld   (sxt_regf_wr_data_vld),
    .sxt_regf_wr_data_rdy   (sxt_regf_wr_data_rdy),
    .sxt_regf_wr_data       (sxt_regf_wr_data),

    .regf_sxt_wr_ack        (regf_sxt_wr_ack),

    .garb_sxt_avail_1h      (garb_sxt_avail_1h),

    .sxt_gram_rd_en         (sxt_gram_rd_en),
    .sxt_gram_rd_add        (sxt_gram_rd_add),
    .gram_sxt_rd_data       (gram_sxt_rd_data),
    .gram_sxt_rd_data_avail (gram_sxt_rd_data_avail),

    .sxt_seq_done           (sxt_seq_done),
    .sxt_seq_done_pid       (sxt_seq_done_pid),

    .sxt_rif_cmd_wait_b_dur (sxt_rif_cmd_wait_b_dur),
    .sxt_rif_rcp_dur        (sxt_rif_rcp_dur),
    .sxt_rif_req_dur        (sxt_rif_req_dur)
  );

  pep_mmacc_glwe_ram
  #(
    .OP_W            (OP_W),
    .PSI             (PSI),
    .R               (R),
    .RAM_LATENCY     (RAM_LATENCY),
    .GRAM_NB         (GRAM_NB),
    .GLWE_RAM_DEPTH  (GLWE_RAM_DEPTH),
    .IN_PIPE         (1),
    .OUT_PIPE        (1)
  ) pep_mmacc_glwe_ram (
    .clk                     (clk),        // clock
    .s_rst_n                 (s_rst_n),    // synchronous reset

    .ext_gram_wr_en          (ext_gram_wr_en),
    .ext_gram_wr_add         (ext_gram_wr_add),
    .ext_gram_wr_data        (ext_gram_wr_data),

    .sxt_gram_rd_en          (sxt_gram_rd_en),
    .sxt_gram_rd_add         (sxt_gram_rd_add),
    .gram_sxt_rd_data        (gram_sxt_rd_data),
    .gram_sxt_rd_data_avail  (gram_sxt_rd_data_avail),

    .feed_gram_rd_en         ('0), /*UNUSED*/
    .feed_gram_rd_add        ('x), /*UNUSED*/
    .gram_feed_rd_data       (),   /*UNUSED*/
    .gram_feed_rd_data_avail (),   /*UNUSED*/

    .acc_gram_rd_en          ('0), /*UNUSED*/
    .acc_gram_rd_add         ('x), /*UNUSED*/
    .gram_acc_rd_data        (),   /*UNUSED*/
    .gram_acc_rd_data_avail  (),   /*UNUSED*/

    .acc_gram_wr_en          ('0), /*UNUSED*/
    .acc_gram_wr_add         ('x), /*UNUSED*/
    .acc_gram_wr_data        ('x), /*UNUSED*/

    .error                   (error_gram[0])
  );

  assign error_gram[1] = 1'b0;

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

  // Body RAM
  stream_source
  #(
    .FILENAME   ("counter"),
    .DATA_TYPE  ("ascii_hex"),
    .DATA_W     (LWE_COEF_W),
    .RAND_RANGE (DATA_RAND_RANGE),
    .KEEP_VLD   (0),
    .MASK_DATA  ("x")
  )
  source_boram
  (
    .clk        (clk),
    .s_rst_n    (s_rst_n),

    .data       (boram_sxt_data),
    .vld        (boram_sxt_data_vld),
    .rdy        (boram_sxt_data_rdy),

    .throughput (DATA_RAND_RANGE/10)
  );

  initial begin
    int r;
    r = source_boram.open();
    wait(s_rst_n);
    @(posedge clk) source_boram.start(0);
  end

// ============================================================================================== --
// Scenario
// ============================================================================================== --
// Write a GLWE in GRAM for a pid, in a given GRAM.
// Once done build the corresponding SXT command. Send it to SXT via a queue.
// The SXT sample the command and the corresponding LWE, and write the result in the regfile.
//
// The bench contains 2 phases. During the first one all the accesses are at full throughput.
// See if the full throughput is reached. During the second phase, random external
// interaction.

  typedef enum {
    ST_FULL_THROUGHPUT,
    ST_RANDOM,
    ST_DONE
  } state_e;

  state_e state;
  state_e next_state;

  logic phase_full_tput_done;
  logic phase_random_done;

  always_comb begin
    case(state)
      ST_FULL_THROUGHPUT:
        next_state = phase_full_tput_done ? ST_RANDOM : state;
      ST_RANDOM:
        next_state = phase_random_done ? ST_DONE : state;
      ST_DONE:
        next_state = state;
    endcase
  end

  always_ff @(posedge clk)
    if (!s_rst_n) state <= ST_FULL_THROUGHPUT;
    else          state <= next_state;

  logic st_full_throughput;
  logic st_random;
  logic st_done;

  assign st_full_throughput = state == ST_FULL_THROUGHPUT;
  assign st_random          = state == ST_RANDOM;
  assign st_done            = state == ST_DONE;

// ---------------------------------------------------------------------------------------------- --
// External stimuli
// ---------------------------------------------------------------------------------------------- --
// Fake a pem accessing the regfile, to make it answer not on every cycle.

  // GRAM arbiter grant
  always_ff @(posedge clk)
    if (!s_rst_n) garb_sxt_avail_1h <= '0;
    else          garb_sxt_avail_1h <= st_full_throughput ? '1 : $urandom();

  // Fake pem access
  assign pem_regf_wr_req.reg_id     = 0;
  assign pem_regf_wr_req.start_word = 0;
  assign pem_regf_wr_req.word_nb_m1 = REGF_BLWE_WORD_PER_RAM+1;

  assign pem_regf_wr_data_vld = '1;
  assign pem_regf_wr_data     = '1;

  always_ff @(posedge clk)
    if (!s_rst_n) pem_regf_wr_req_vld  <= 1'b0;
    else          pem_regf_wr_req_vld  <= st_full_throughput ? 1'b0 : $urandom();

// ---------------------------------------------------------------------------------------------- --
// Fill GLWE and create command
// ---------------------------------------------------------------------------------------------- --
  //== Keep track of pending pid
  logic [PID_W-1:0] gram_free_pid_q[$];
  logic [PID_W-1:0] ack_pid_q[$];

  initial begin
    logic [TOTAL_PBS_NB-1:0] chosen;
    chosen = '0;
    while (chosen != '1) begin
      integer pid;
      pid = $urandom_range(0,TOTAL_PBS_NB-1);
      if (!chosen[pid]) begin
        gram_free_pid_q.push_back(pid);
        chosen[pid] = 1'b1;
      end
    end
  end

  mmacc_intern_cmd_t       sxt_icmd_q[$];
  logic [REGF_REGID_W-1:0] dst_rid_q[$];
  logic [LOG_LUT_NB_W-1:0] sxt_icmd_lut_q[$];

  integer wr_gram_word_cnt;
  integer wr_gram_word_cntD;
  logic   wr_last_gram_word_cnt;

  logic [GRAM_NB-1:0]              wr_gram_wr_en;
  logic [PSI-1:0][R-1:0][OP_W-1:0] wr_gram_data;

  assign wr_last_gram_word_cnt = wr_gram_word_cnt == GLWE_WORD_NB_IN_GRAM-1;
  assign wr_gram_word_cntD     = |wr_gram_wr_en ? wr_last_gram_word_cnt ? '0 : wr_gram_word_cnt + 1 : wr_gram_word_cnt;

  always_ff @(posedge clk)
    if (!s_rst_n) wr_gram_word_cnt <= '0;
    else          wr_gram_word_cnt <= wr_gram_word_cntD;

  integer                          wr_gram_sample_cnt;
  logic [GLWE_RAM_ADD_W-1:0]       wr_gram_add_ofs;
  logic [PSI-1:0][R-1:0][OP_W-1:0] in_data_q[$];
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      wr_gram_wr_en      <= '0;
      wr_gram_sample_cnt <= '0;
      wr_gram_data       <= 'x;
      wr_gram_add_ofs    <= 'x;
    end
    else begin
      wr_gram_wr_en <= '0;
      if (gram_free_pid_q.size() > 0) begin
        logic [PID_W-1:0] pid;
        logic [PSI-1:0][R-1:0][OP_W-1:0] wr_data;

        pid = gram_free_pid_q[0];
        wr_gram_wr_en   <= 1 << (pid % GRAM_NB);
        wr_gram_add_ofs <= (pid / GRAM_NB) * GLWE_WORD_NB_IN_GRAM;

        for (int p=0; p<PSI; p=p+1)
          for (int r=0; r<R; r=r+1) begin
            //wr_data[p][r] = {$urandom(),$urandom()};
            // Use the following instead to ease debug
            wr_data[p][r] = rev_order((wr_gram_sample_cnt*R*PSI)%N + p*R+r);
            wr_data[p][r] = (wr_gram_sample_cnt*R*PSI)/N * N + wr_data[p][r];
            //$display("PID=%0d [%0d] data=0x%0x",pid,wr_gram_sample_cnt*R*PSI+p*R+r,wr_data[p][r]);
          end

        wr_gram_data <= {GRAM_NB{wr_data}};
        in_data_q.push_back(wr_data);

        if (wr_gram_sample_cnt == GLWE_WORD_NB_IN_GRAM-1) begin
          logic [REGF_REGID_W-1:0] reg_mask;
          mmacc_intern_cmd_t icmd;
          gram_free_pid_q.pop_front();
          icmd                 = '0; // set unused fields to 0
          icmd.batch_first_ct  = 1'b0; // UNUSED
          icmd.batch_last_ct   = 1'b0; // UNUSED
          icmd.map_idx         = '0;   // UNUSED
          icmd.map_elt.avail   = 1'b1; // UNUSED
          icmd.map_elt.first   = 1'b0; // UNUSED
          icmd.map_elt.last    = 1'b1; // UNUSED
          icmd.map_elt.log_lut_nb = $random() % LOG_MAX_LUT_NB;
          // Note that destination IDs need to be aligned to the number of LUTs
          reg_mask = {REGF_REGID_W{1'b1}} << icmd.map_elt.log_lut_nb;
          icmd.map_elt.dst_rid = ((pid + 1) % REGF_REG_NB) & reg_mask;
          icmd.map_elt.lwe     = '0; // UNUSED
          icmd.map_elt.pid.pid = pid;
          icmd.map_elt.pid.grid = pid % GRAM_NB;
          icmd.map_elt.pid.grof = pid / GRAM_NB;

          begin
            sxt_icmd_q.push_back(icmd);
            sxt_icmd_lut_q.push_back(icmd.map_elt.log_lut_nb);
            for(int lut = 0; lut < (1 << icmd.map_elt.log_lut_nb); lut++)
              dst_rid_q.push_back(icmd.map_elt.dst_rid | lut);
            ack_pid_q.push_back(pid);
            wr_gram_sample_cnt <= '0;
          end
        end
        else begin
          wr_gram_sample_cnt <= wr_gram_sample_cnt + 1;
        end
      end
    end

  // Write in GRAM
  always_comb
    for (int g=0; g<GRAM_NB; g=g+1)
      for (int p=0; p<PSI; p=p+1)
        for (int r=0; r<R; r=r+1) begin
          ext_gram_wr_en[g][p][r]   = wr_gram_wr_en[g];
          ext_gram_wr_add[g][p][r]  = wr_gram_word_cnt + wr_gram_add_ofs;
          ext_gram_wr_data[g][p][r] = wr_gram_data[p][r];
        end

// ---------------------------------------------------------------------------------------------- --
// Command
// ---------------------------------------------------------------------------------------------- --
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      sfifo_sxt_icmd <= 'x;
      sfifo_sxt_vld  <= 1'b0;
    end
    else begin
      logic next_vld;
      if (sfifo_sxt_vld && sfifo_sxt_rdy)
        sxt_icmd_q.pop_front();

      if (!sfifo_sxt_vld | sfifo_sxt_rdy) begin
        next_vld = $urandom();
        next_vld = next_vld & (sxt_icmd_q.size() > 0) & ~st_done;
      end
      else
        next_vld = sfifo_sxt_vld;

      sfifo_sxt_vld  <= next_vld;
      sfifo_sxt_icmd <= sxt_icmd_q[0];
    end

// ---------------------------------------------------------------------------------------------- --
// Reference
// ---------------------------------------------------------------------------------------------- --
  logic [OP_W-1:0] ref_q[REGF_COEF_NB-1:0] [$];
  logic [LWE_COEF_W-1:0] b_coef_q[$];

  always_ff @(posedge clk)
    if (boram_sxt_data_vld && boram_sxt_data_rdy)
      b_coef_q.push_back(boram_sxt_data);


  always_ff @(posedge clk)
    if (b_coef_q.size() > 0 && sxt_icmd_lut_q.size() > 0) begin
      logic [GLWE_K_P1-1:0][N-1:0][OP_W-1:0] d;
      logic [GLWE_K_P1-1:0][N-1:0][OP_W-1:0] v;
      logic [GLWE_K_P1-1:0][N-1:0][OP_W-1:0] w;
      logic [GLWE_K_P1-1:0][N-1:0][OP_W-1:0] x;

      logic [STG_ITER_NB*GLWE_K_P1-1:0][PSI*R-1:0][OP_W-1:0] dd;
      logic [GLWE_K_P1-1:0][N-1:0][OP_W-1:0] ddd_r;

      logic [LWE_COEF_W-1:0] b_coef;
      integer lut_nb;

      lut_nb = (1 << sxt_icmd_lut_q.pop_front());
      b_coef = b_coef_q.pop_front();
      for (int i=0; i<STG_ITER_NB*GLWE_K_P1; i=i+1)
        dd[i] = in_data_q.pop_front();

      ddd_r = dd; // cast. Here the data are in reverse order
      // Set back to natural order.
      for (int i=0; i<GLWE_K_P1; i=i+1)
        for (int n=0; n<N; n=n+1) begin
          d[i][n] = ddd_r[i][rev_order(n)];
          //$display("NAT i=%0d n=%0d -> %0d d[i][n]=0x%0x",i,n,i*N+rev_order(n),d[i][n]);
        end

      // rotation with b_coef
      for (int g=0; g<GLWE_K_P1; g=g+1)
        for (int n=0; n<N; n=n+1) begin
          int idx;
          bit sign;
          idx = n+b_coef;
          sign = (idx >= N && idx < 2*N) ? 1'b1 : 1'b0;
          idx = idx % N;
          v[g][n] = d[g][idx];
          v[g][n] = sign ? 2**OP_W - v[g][n] : v[g][n];
        end

//    $display("ROT > ROT=%0d",b_coef );
//    for (int g=0; g<GLWE_K_P1; g=g+1)
//        for (int n=0; n<N; n=n+1)
//            $display("ROT > v[%0d][%0d] = 0x%0x 0x%0x", g,n,v[g][n], d[g][n]);

    for (int lut = 0; lut < lut_nb; lut++) begin
      logic [N-1:0] coeff_offs;
      coeff_offs = lut*N/lut_nb;

      // sample extract
      for (int g=0; g<GLWE_K_P1; g=g+1) begin
        for (int n=0; n<N; n=n+1) begin
            integer coeff_i;
            bit neg;
            coeff_i = coeff_offs - n;
            neg = (coeff_i < 0);
            w[g][n] = unsigned'(OP_W'(1-2*neg) * v[g][neg * N + coeff_i]);
        end
      end

//      $display("SXT >" );
//      for (int g=0; g<GLWE_K_P1; g=g+1)
//        for (int n=0; n<N; n=n+1)
//          $display("SXT > w[%0d][%0d] = 0x%0x", g,n,w[g][n]);

      // reverse
      for (int g=0; g<GLWE_K_P1; g=g+1) begin
        for (int n=0; n<N; n=n+1) begin
          int rev_n;
          rev_n = rev_order(n);
          x[g][n] = w[g][rev_n];
        end
      end

//      $display("REV >" );
//      for (int g=0; g<GLWE_K_P1; g=g+1)
//        for (int n=0; n<N; n=n+1)
//          $display("REV > x[%0d][%0d] = 0x%0x", g,n,x[g][n]);


      // chunk
//      $display("CHK >" );
      for (int g=0; g<GLWE_K; g=g+1)
        for (int i=0; i<POLY_CHUNK_NB; i=i+1)
          for (int j=0; j<REGF_COEF_NB; j=j+1) begin
            ref_q[j].push_back(x[g][i*REGF_COEF_NB+j]);
//            $display("CHK > x[%0d][%0d*X+%0d] = 0x%0x", g,i,j,x[g][i*REGF_COEF_NB+j]);
          end
      for (int j=0; j<REGF_COEF_NB; j=j+1) begin
        ref_q[j].push_back(x[GLWE_K][j]); // body
//        $display("CHK > x[%0d][body+%0d] = 0x%0x", GLWE_K,j,x[GLWE_K][j]);
      end
    end //for lut
  end // if (|(boram_sxt_data_vld & boram_sxt_data_rdy))

// ---------------------------------------------------------------------------------------------- --
// Check
// ---------------------------------------------------------------------------------------------- --
//== Check regfile request
  integer       regf_req_data_cnt;
  integer       regf_req_data_cntD;
  regf_wr_req_t sxt_regf_wr_req_s;

  logic         regf_last_req_data_cnt;
  integer       out_pid_cnt;

  assign sxt_regf_wr_req_s      = sxt_regf_wr_req;
  assign regf_last_req_data_cnt = regf_req_data_cnt + (sxt_regf_wr_req_s.word_nb_m1 + 1) == (REGF_BLWE_WORD_PER_RAM + 1);
  assign regf_req_data_cntD     = (sxt_regf_wr_req_vld && sxt_regf_wr_req_rdy) ?
                                    regf_last_req_data_cnt ? '0 : regf_req_data_cnt + (sxt_regf_wr_req_s.word_nb_m1 + 1) : regf_req_data_cnt;

  always_ff @(posedge clk)
    if (!s_rst_n) regf_req_data_cnt <= '0;
    else          regf_req_data_cnt <= regf_req_data_cntD;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      error_req   <= 1'b0;
    end
    else begin
      if (sxt_regf_wr_req_vld && sxt_regf_wr_req_rdy) begin
        assert(sxt_regf_wr_req_s.reg_id == dst_rid_q[0])
        else begin
          $display("%t > ERROR: Mismatch regf command reg_id exp=%0d seen=%0d", $time, dst_rid_q[0], sxt_regf_wr_req_s.reg_id);
          error_req <= 1'b1;
        end

        assert(sxt_regf_wr_req_s.start_word == regf_req_data_cnt)
        else begin
          $display("%t > ERROR: Mismatch regf command start_word exp=0x%0x seen=0x%0x", $time, regf_req_data_cnt, sxt_regf_wr_req_s.start_word);
          error_req <= 1'b1;
        end

        assert(regf_req_data_cnt + (sxt_regf_wr_req_s.word_nb_m1 + 1) <= (REGF_BLWE_WORD_PER_RAM + 1))
        else begin
          $display("%t > ERROR: Data_cnt overflow word_nb_m1 exp=%0d seen=%0d", $time, (REGF_BLWE_WORD_PER_RAM + 1) - regf_req_data_cnt - 1, sxt_regf_wr_req_s.word_nb_m1);
          error_req <= 1'b1;
        end

        if (regf_last_req_data_cnt) begin
          dst_rid_q.pop_front();
        end
      end
    end

//== Check regfile data
  integer out_cnt [REGF_COEF_NB-1:0];
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      error_data <= 1'b0;
      for (int i=0; i<REGF_COEF_NB; i=i+1)
        out_cnt[i] <= '0;
    end
    else begin
      for (int i=0; i<REGF_COEF_NB; i=i+1) begin
        if (sxt_regf_wr_data_vld[i] && sxt_regf_wr_data_rdy[i]) begin
          logic [OP_W-1:0] ref_val;
          if (ref_q[i].size() == 0) begin
            error_data <= 1'b1;
            $display("%t > ERROR: No reference for data %0d", $time,i);
          end
          else begin
            ref_val = ref_q[i].pop_front();
            if (out_cnt[i] == PBS_CHUNK_NB-1) begin // body
              if (i==0) begin
                assert(ref_val == sxt_regf_wr_data[i])
                else begin
                  $display("%t > ERROR: body data mismatches out_cnt[%0d]=%0d exp=0x%0x seen=0x%0x", $time, i,out_cnt[i], ref_val, sxt_regf_wr_data[i]);
                  error_data <= 1'b1;
                end
              end
            end
            else begin
              assert(ref_val == sxt_regf_wr_data[i])
              else begin
                $display("%t > ERROR: Data mismatches out_cnt[%0d]=%0d exp=0x%0x seen=0x%0x", $time, i,out_cnt[i], ref_val, sxt_regf_wr_data[i]);
                error_data <= 1'b1;
              end
            end

            out_cnt[i] <= out_cnt[i] == PBS_CHUNK_NB-1 ? '0 : out_cnt[i] + 1;
          end // else size
        end // if rdy && vld
      end // for i REGF_COEF_NB
    end


  //== Check ack
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      error_ack <= 1'b0;
      out_pid_cnt <= '0;
    end else begin
      if (sxt_seq_done) begin
        logic [PID_W-1:0] pid;
        pid = ack_pid_q.pop_front();
        assert(pid == sxt_seq_done_pid)
        else begin
          $display("%t > ERROR: Mismatch done pid exp=%0d seen=%0d", $time, pid, sxt_seq_done_pid);
          error_ack <= 1'b1;
        end
        gram_free_pid_q.push_back(pid);
        out_pid_cnt <= out_pid_cnt + 1;
      end
    end
// ---------------------------------------------------------------------------------------------- --
// End of test
// ---------------------------------------------------------------------------------------------- --
  integer cmd_cnt;
  integer ack_cnt;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      cmd_cnt <= '0;
      ack_cnt <= '0;
    end
    else begin
      cmd_cnt <= (sfifo_sxt_vld && sfifo_sxt_rdy) ? cmd_cnt + 1 : cmd_cnt;
      ack_cnt <= sxt_seq_done ? ack_cnt + 1 : ack_cnt;
    end

  assign phase_full_tput_done = (cmd_cnt == TPUT_SAMPLE_NB-1) & sfifo_sxt_vld & sfifo_sxt_rdy;
  assign phase_random_done    = (cmd_cnt == SAMPLE_NB-1) & sfifo_sxt_vld & sfifo_sxt_rdy;

  initial begin
    end_of_test = 1'b0;
    wait(st_done);
    $display("%t > INFO: All commands sent", $time);
    wait(out_pid_cnt >= SAMPLE_NB);
    $display("%t > INFO: All regfile request sent", $time);
    wait(ack_cnt >= SAMPLE_NB);
    $display("%t > INFO: All acknowledges sent", $time);
    repeat(50)@(posedge clk);
    end_of_test = 1'b1;
  end

  always_ff @(posedge clk)
    if (sfifo_sxt_vld && sfifo_sxt_rdy)
      if (cmd_cnt%50 == 0)
        $display("%t > INFO : Send sfifo_sxt cmd #%0d", $time,cmd_cnt);

// ---------------------------------------------------------------------------------------------- --
// Debug signals
// ---------------------------------------------------------------------------------------------- --
  logic or_pem_regf_wr_data_rdy;

  assign or_pem_regf_wr_data_rdy = |or_pem_regf_wr_data_rdy;
endmodule
