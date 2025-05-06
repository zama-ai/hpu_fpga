// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the verification of tb_pep_load_blwe.
// ==============================================================================================

module tb_pep_load_blwe;
`timescale 1ns/10ps

  import param_tfhe_pkg::*;
  import top_common_param_pkg::*;
  import regf_common_param_pkg::*;
  import pep_ks_common_param_pkg::*;
  import hpu_common_instruction_pkg::*;
  import pep_common_param_pkg::*;

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int CLK_HALF_PERIOD = 1;
  localparam int ARST_ACTIVATION = 17;

  parameter  int RAND_RANGE = 128;
  parameter  int INST_THROUGHPUT = RAND_RANGE / 10;

  parameter  int SAMPLE_NB       = 500;

  parameter  int PEA_PERIOD   = REGF_COEF_NB;
  parameter  int PEM_PERIOD   = 2;
  parameter  int PEP_PERIOD   = 1;
  localparam int URAM_LATENCY = 1+2;

  localparam int REGF_RD_LATENCY = URAM_LATENCY + 4; // Minimum latency

  localparam int KS_IF_COEF_NB   = (LBY < REGF_COEF_NB) ? LBY : REGF_SEQ_COEF_NB;
  localparam int KS_IF_SUBW_NB   = (LBY < REGF_COEF_NB) ? 1 : REGF_SEQ;

// ============================================================================================== --
// type
// ============================================================================================== --
  typedef struct packed {
    logic [15:0]  reg_id;
    logic [15:0]  idx;
  } data_t;

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
  bit [KS_IF_SUBW_NB-1:0] error_data_a;
  bit [KS_IF_SUBW_NB-1:0] error_pid_a;
  bit [KS_IF_SUBW_NB-1:0] error_last_a;
  bit                     error_ack;

  assign error = |error_data_a
                | |error_pid_a
                | |error_last_a
                | error_ack;

  always_ff @(posedge clk)
    if (error) begin
      $display("%t > FAILURE !", $time);
      $finish;
    end

// ============================================================================================== --
// input / output signals
// ============================================================================================== --
  // pep_seq : command
  logic [LOAD_BLWE_CMD_W-1:0]                                seq_ldb_cmd;
  logic                                                      seq_ldb_vld;
  logic                                                      seq_ldb_rdy;
  logic                                                      ldb_seq_done;

  // pep_ldb <-> Regfile
  // read
  logic                                                      pep_regf_rd_req_vld;
  logic                                                      pep_regf_rd_req_rdy;
  logic [REGF_RD_REQ_W-1:0]                                  pep_regf_rd_req;

  logic [REGF_COEF_NB-1:0]                                   regf_pep_rd_data_avail;
  logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0]                      regf_pep_rd_data;
  logic                                                      regf_pep_rd_last_word; // valid with avail[0]
  logic                                                      regf_pep_rd_is_body;
  logic                                                      regf_pep_rd_last_mask;

  // pep_ldb <-> Key switch
  // write
  logic [KS_IF_SUBW_NB-1:0]                                  pep_blram_wr_en;
  logic [KS_IF_SUBW_NB-1:0][PID_W-1:0]                       pep_blram_wr_pid;
  logic [KS_IF_SUBW_NB-1:0][KS_IF_COEF_NB-1:0][MOD_Q_W-1:0]  pep_blram_wr_data;
  logic                                                      pep_blram_wr_pbs_last; // associated to wr_en[0]

// ============================================================================================== --
// Design under test instance
// ============================================================================================== --
  pep_load_blwe #(
    .REGF_RD_LATENCY(REGF_RD_LATENCY),
    .KS_IF_COEF_NB  (KS_IF_COEF_NB),
    .KS_IF_SUBW_NB  (KS_IF_SUBW_NB)
  ) dut (
    .clk                    (clk    ),
    .s_rst_n                (s_rst_n),

    .seq_ldb_cmd            (seq_ldb_cmd),
    .seq_ldb_vld            (seq_ldb_vld),
    .seq_ldb_rdy            (seq_ldb_rdy),
    .ldb_seq_done           (ldb_seq_done),

    .pep_regf_rd_req_vld    (pep_regf_rd_req_vld),
    .pep_regf_rd_req_rdy    (pep_regf_rd_req_rdy),
    .pep_regf_rd_req        (pep_regf_rd_req),

    .regf_pep_rd_data_avail (regf_pep_rd_data_avail),
    .regf_pep_rd_data       (regf_pep_rd_data),
    .regf_pep_rd_last_word  (regf_pep_rd_last_word), // valid with avail[0]
    .regf_pep_rd_is_body    (regf_pep_rd_is_body),
    .regf_pep_rd_last_mask  (regf_pep_rd_last_mask),

    .pep_blram_wr_en         (pep_blram_wr_en),
    .pep_blram_wr_pid        (pep_blram_wr_pid),
    .pep_blram_wr_data       (pep_blram_wr_data),
    .pep_blram_wr_pbs_last   (pep_blram_wr_pbs_last)
  );

// ============================================================================================== --
// Regfile
// ============================================================================================== --
  logic                                 regf_wr_req_vld;
  logic                                 regf_wr_req_rdy;
  regf_wr_req_t                         regf_wr_req;

  logic [REGF_COEF_NB-1:0]              regf_wr_data_vld;
  logic [REGF_COEF_NB-1:0]              regf_wr_data_rdy;
  logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0] regf_wr_data;

  logic                                 pem_regf_rd_req_vld;
  logic                                 pem_regf_rd_req_rdy;
  regf_rd_req_t                         pem_regf_rd_req;

  logic [REGF_COEF_NB-1:0]              regf_pem_rd_data_avail;
  logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0] regf_pem_rd_data;
  logic                                 regf_pem_rd_last_word;
  logic                                 regf_pem_rd_is_body;
  logic                                 regf_pem_rd_last_mask;

  logic regf_pep_wr_ack;

  regfile
  #(
    .PEA_PERIOD (PEA_PERIOD),
    .PEM_PERIOD (PEM_PERIOD),
    .PEP_PERIOD (PEP_PERIOD),
    .URAM_LATENCY (URAM_LATENCY)
  ) regfile (
    .clk                    (clk),        // clock
    .s_rst_n                (s_rst_n),    // synchronous reset

    .pem_regf_wr_req_vld    (regf_wr_req_vld ),
    .pem_regf_wr_req_rdy    (regf_wr_req_rdy ),
    .pem_regf_wr_req        (regf_wr_req     ),

    .pem_regf_wr_data_vld   (regf_wr_data_vld),
    .pem_regf_wr_data_rdy   (regf_wr_data_rdy),
    .pem_regf_wr_data       (regf_wr_data    ),

    .pem_regf_rd_req_vld    (pem_regf_rd_req_vld   ),
    .pem_regf_rd_req_rdy    (pem_regf_rd_req_rdy   ),
    .pem_regf_rd_req        (pem_regf_rd_req       ),

    .regf_pem_rd_data_avail (regf_pem_rd_data_avail),
    .regf_pem_rd_data       (regf_pem_rd_data      ),
    .regf_pem_rd_last_word  (regf_pem_rd_last_word ),
    .regf_pem_rd_last_mask  (regf_pem_rd_last_mask ),
    .regf_pem_rd_is_body    (regf_pem_rd_is_body   ),

    .pea_regf_wr_req_vld    ('0),/*UNUSED*/
    .pea_regf_wr_req_rdy    (/*UNUSED*/),
    .pea_regf_wr_req        (/*UNUSED*/),

    .pea_regf_wr_data_vld   ('0),/*UNUSED*/
    .pea_regf_wr_data_rdy   (/*UNUSED*/),
    .pea_regf_wr_data       (/*UNUSED*/),


    .pea_regf_rd_req_vld    ('0),/*UNUSED*/
    .pea_regf_rd_req_rdy    (/*UNUSED*/),
    .pea_regf_rd_req        (/*UNUSED*/),

    .regf_pea_rd_data_avail (/*UNUSED*/),
    .regf_pea_rd_data       (/*UNUSED*/),
    .regf_pea_rd_last_word  (/*UNUSED*/),
    .regf_pea_rd_last_mask  (/*UNUSED*/),
    .regf_pea_rd_is_body    (/*UNUSED*/),

    .pep_regf_wr_req_vld    ('0),/*UNUSED*/
    .pep_regf_wr_req_rdy    (/*UNUSED*/),
    .pep_regf_wr_req        (/*UNUSED*/),

    .pep_regf_wr_data_vld   ('0),/*UNUSED*/
    .pep_regf_wr_data_rdy   (/*UNUSED*/),
    .pep_regf_wr_data       (/*UNUSED*/),

    .pep_regf_rd_req_vld    (pep_regf_rd_req_vld),
    .pep_regf_rd_req_rdy    (pep_regf_rd_req_rdy),
    .pep_regf_rd_req        (pep_regf_rd_req    ),

    .regf_pep_rd_data_avail (regf_pep_rd_data_avail),
    .regf_pep_rd_data       (regf_pep_rd_data      ),
    .regf_pep_rd_last_word  (regf_pep_rd_last_word ),
    .regf_pep_rd_last_mask  (regf_pep_rd_last_mask ),
    .regf_pep_rd_is_body    (regf_pep_rd_is_body   ),


    .pem_wr_ack             (regf_pem_wr_ack),
    .pea_wr_ack             (/*UNUSED*/),
    .pep_wr_ack             (regf_pep_wr_ack)
  );

// ============================================================================================== --
// Scenario
// ============================================================================================== --
//---------------------------------
// FSM
//---------------------------------
  typedef enum {ST_IDLE,
                ST_FILL_REGF,
                ST_PROCESS,
                ST_DONE} state_e;

  state_e state;
  state_e next_state;
  logic st_idle;
  logic st_fill_regf;
  logic st_process;
  logic st_done;

  logic start;
  logic fill_regf_done;
  logic proc_done;
  logic test_done;

  always_comb
    case (state)
      ST_IDLE:
        next_state = start ? ST_FILL_REGF : state;
      ST_FILL_REGF:
        next_state = fill_regf_done ? ST_PROCESS : state;
      ST_PROCESS:
        next_state = proc_done ? ST_DONE : state;
      ST_DONE:
        next_state = state;
    endcase

  always_ff @(posedge clk)
    if (!s_rst_n) state <= ST_IDLE;
    else          state <= next_state;

  assign st_idle      = state == ST_IDLE;
  assign st_fill_regf = state == ST_FILL_REGF;
  assign st_process   = state == ST_PROCESS;
  assign st_done      = state == ST_DONE;

//---------------------------------
// Fill regfile
//---------------------------------
  regf_wr_req_t       regf_wr_req_q[$];
  logic [MOD_Q_W-1:0] regf_wr_data_q [REGF_COEF_NB-1:0][$];

  initial begin
    regf_wr_req_t req;
    data_t        ct_data;

    fill_regf_done <= 1'b0;

    for (int b=0; b<REGF_REG_NB; b=b+1) begin
      // Build request
      req.reg_id     = b;
      req.start_word = 0;
      req.word_nb_m1 = REGF_BLWE_WORD_PER_RAM; // Includes body

      regf_wr_req_q.push_back(req);

      // Build data
      for (int i=0; i<((BLWE_K_P1+REGF_COEF_NB-1) / REGF_COEF_NB) * REGF_COEF_NB; i=i+1) begin
        ct_data.reg_id = b;
        ct_data.idx    = i;
        regf_wr_data_q[i%REGF_COEF_NB].push_back(ct_data);
      end
    end // for REGF_COEF_NB

    wait (regf_wr_req_q.size() == 0);
    for (int i=0; i<REGF_COEF_NB; i=i+1)
      wait(regf_wr_data_q[i].size() == 0);

    repeat(1+REGF_SEQ) @(posedge clk);
    fill_regf_done <= 1'b1;

  end // initial

  logic         wr_req_avail;
  regf_wr_req_t wr_req_tmp;
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      wr_req_avail <= 1'b0;
      wr_req_tmp   <= '0;
    end
    else
      if (st_fill_regf && (wr_req_avail == 1'b0 || (regf_wr_req_vld && regf_wr_req_rdy))) begin
        wr_req_avail <= regf_wr_req_q.size() > 0;
        if (regf_wr_req_q.size() > 0) begin
          wr_req_tmp <= regf_wr_req_q[0];
          regf_wr_req_q.pop_front();
        end
      end

  assign regf_wr_req_vld = wr_req_avail & st_fill_regf;
  assign regf_wr_req     = wr_req_tmp;

  for (genvar gen_c=0; gen_c<REGF_COEF_NB; gen_c=gen_c+1) begin
    logic               wr_data_avail;
    logic [MOD_Q_W-1:0] wr_data_tmp;
    always_ff @(posedge clk)
      if (!s_rst_n) begin
        wr_data_avail <= 1'b0;
        wr_data_tmp   <= '0;
      end
      else
        if (st_fill_regf && (wr_data_avail == 1'b0 || (regf_wr_data_vld[gen_c] && regf_wr_data_rdy[gen_c]))) begin
          wr_data_avail <= regf_wr_data_q[gen_c].size() > 0;
          if (regf_wr_data_q[gen_c].size() > 0) begin
            wr_data_tmp <= regf_wr_data_q[gen_c][0];
            regf_wr_data_q[gen_c].pop_front();
          end
        end

    assign regf_wr_data_vld[gen_c] = st_fill_regf & wr_data_avail;
    assign regf_wr_data[gen_c]     = wr_data_tmp;
  end // for gen_c

//---------------------------------
// Process
//---------------------------------
// parasite read access => to change the throughput to pep
// Generate dummy read commands.
  assign pem_regf_rd_req.do_2_read  = 1'b0;
  assign pem_regf_rd_req.reg_id_1   = '0;
  assign pem_regf_rd_req.reg_id     = '0; // Fake
  assign pem_regf_rd_req.start_word = '0;
  assign pem_regf_rd_req.word_nb_m1 = 11;

  stream_source
  #(
    .FILENAME   ("counter"),
    .DATA_TYPE  ("ascii_hex"),
    .DATA_W     (CID_W),
    .RAND_RANGE (RAND_RANGE),
    .KEEP_VLD   (1'b0),
    .MASK_DATA  ("x")
  ) pem_stream_source (
      .clk       (clk),
      .s_rst_n   (s_rst_n),

      .data      (/*UNUSED*/),
      .vld       (pem_regf_rd_req_vld),
      .rdy       (pem_regf_rd_req_rdy),

      .throughput(RAND_RANGE/50)
  );

  initial begin
    integer dummy;
    dummy = pem_stream_source.open();
    wait(st_process);
    @(posedge clk);
    pem_stream_source.start(0);
  end

// load_blwe commands
  integer         cmd_rid;
  load_blwe_cmd_t cmd;

  assign cmd.src_rid = cmd_rid % REGF_REG_NB;
  assign cmd.pid     = (cmd.src_rid + 1) % TOTAL_PBS_NB;
  assign seq_ldb_cmd = cmd;
  stream_source
  #(
    .FILENAME   ("counter"),
    .DATA_TYPE  ("ascii_hex"),
    .DATA_W     (32),
    .RAND_RANGE (RAND_RANGE),
    .KEEP_VLD   (1'b0),
    .MASK_DATA  ("x")
  ) cmd_stream_source (
      .clk       (clk),
      .s_rst_n   (s_rst_n),

      .data      (cmd_rid),
      .vld       (seq_ldb_vld),
      .rdy       (seq_ldb_rdy),

      .throughput(INST_THROUGHPUT)
  );

  logic in_cmd_done;
  assign proc_done = in_cmd_done;
  initial begin
    integer dummy;
    in_cmd_done = 1'b0;
    dummy = cmd_stream_source.open();
    wait(st_process);
    @(posedge clk);
    cmd_stream_source.start(SAMPLE_NB);
    wait (cmd_stream_source.running);
    wait (!cmd_stream_source.running);

    in_cmd_done = 1'b1;

  end

//---------------------------------
// Check
//---------------------------------
  localparam int INC      = KS_IF_SUBW_NB * KS_IF_COEF_NB;
  localparam int MAX_ITER = BLWE_K / INC; // body not taken into account

  integer ref_rid [KS_IF_SUBW_NB-1:0];
  integer ref_pid [KS_IF_SUBW_NB-1:0];
  integer ref_iter [KS_IF_SUBW_NB-1:0];

  integer ref_ridD  [KS_IF_SUBW_NB-1:0];
  integer ref_iterD [KS_IF_SUBW_NB-1:0];

  always_comb
    for (int i=0; i<KS_IF_SUBW_NB; i=i+1) begin
      logic last;
      last = (i==0) ? ref_iter[i] == MAX_ITER : ref_iter[i] == MAX_ITER-1;
      ref_iterD[i] = pep_blram_wr_en[i] ? last ? '0 : ref_iter[i]+1 : ref_iter[i];
      ref_ridD[i]  = pep_blram_wr_en[i] && last ? (ref_rid[i] + 1) % REGF_REG_NB : ref_rid[i];
      ref_pid[i]   = (ref_rid[i] + 1) % TOTAL_PBS_NB;
    end

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      ref_rid  <= '{default: 0};
      ref_iter <= '{default: 0};
    end
    else begin
      ref_rid  <= ref_ridD ;
      ref_iter <= ref_iterD;
    end

  generate
    for (genvar gen_i=0; gen_i<KS_IF_SUBW_NB; gen_i=gen_i+1) begin : gen_check_loop
      logic error_data;
      logic error_pid;
      logic error_last;
      assign error_data_a[gen_i] = error_data;
      assign error_pid_a[gen_i]  = error_pid;
      assign error_last_a[gen_i] = error_last;

      always_ff @(posedge clk)
        if (!s_rst_n) begin
          error_data <= 1'b0;
          error_pid  <= 1'b0;
          error_last <= 1'b0;
        end
        else begin
          if (pep_blram_wr_en[gen_i]) begin
            assert(pep_blram_wr_pid[gen_i] == ref_pid[gen_i])
            else begin
              $display("%t > ERROR: KS_IF[%0d] Wrong pid exp=%0d seen=%0d", $time, gen_i, ref_pid[gen_i], pep_blram_wr_pid[gen_i]);
              error_pid <= 1'b1;
            end

            if (gen_i==0) begin
              for (int i=0; i<KS_IF_COEF_NB; i=i+1) begin
                if (!pep_blram_wr_pbs_last || (i==0)) begin // check only body coef
                  data_t ref_d;
                  ref_d.reg_id = ref_rid[gen_i];
                  ref_d.idx    = ref_iter[gen_i]*INC + gen_i*KS_IF_COEF_NB + i;
                  assert(ref_d == pep_blram_wr_data[gen_i][i])
                  else begin
                    $display("%t > ERROR: KS_IF[%0d] (iter=%0d) Wrong data[%0d] exp=0x%0x seen=0x%0x", $time, gen_i, ref_iter[gen_i], i, ref_d, pep_blram_wr_data[gen_i][i]);
                    error_data <= 1'b1;
                  end
                end
              end // for

              assert(pep_blram_wr_pbs_last == (ref_iter[gen_i] == MAX_ITER))
              else begin
                $display("%t > ERROR: KS_IF[%0d] (iter=%0d) Wrong last exp=%0d seen=%0d", $time, gen_i, ref_iter[gen_i], (ref_iter[gen_i] == MAX_ITER), pep_blram_wr_pbs_last);
                error_last <= 1'b1;
              end
            end // gen_i==0
            else begin // gen_i != 0
              for (int i=0; i<KS_IF_COEF_NB; i=i+1) begin
                data_t ref_d;
                ref_d.reg_id = ref_rid[gen_i];
                ref_d.idx    = ref_iter[gen_i]*INC + gen_i*KS_IF_COEF_NB + i;
                assert(ref_d == pep_blram_wr_data[gen_i][i])
                else begin
                  $display("%t > ERROR: KS_IF[%0d] (iter=%0d) Wrong data[%0d] exp=0x%0x seen=0x%0x", $time, gen_i, ref_iter[gen_i], i, ref_d, pep_blram_wr_data[gen_i][i]);
                  error_data <= 1'b1;
                end
              end // for
            end // else
          end // if wr_en
        end
    end // gen_check_loop
  endgenerate


//---------------------------------
// Ack
//---------------------------------
  integer ack_cnt;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      ack_cnt   <= '0;
    end
    else begin
      ack_cnt   <= ldb_seq_done ? ack_cnt + 1 : ack_cnt;
    end
//---------------------------------
// End of test
//---------------------------------
  initial begin
    start       <= 1'b0;
    error_ack   <= 1'b0;
    end_of_test <= 1'b0;
    wait (s_rst_n);

    @(posedge clk)
    start <= 1'b1;

    $display("%t > Wait done state...",$time);
    wait(st_done);
    $display("%t > Done",$time);

    $display("%t > Wait all the ack...",$time);
    wait (ack_cnt == SAMPLE_NB);
    $display("%t > Done",$time);

    repeat(50) @(posedge clk);
    end_of_test <= 1'b1;
  end

endmodule
