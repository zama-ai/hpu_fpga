// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : This is the explicit title of the testbench module
// ----------------------------------------------------------------------------------------------
//
// More details on the test bench scenario.
//
// Describe the steps the test bench goes through:
//  1. First step
//  2. Second step
//  3. Third step
//     Elaborate if needed
//  4. Fourth step
//
// ==============================================================================================

module tb_pep_sequencer;
`timescale 1ns/10ps

  import top_common_param_pkg::*;
  import param_tfhe_pkg::*;
  import pep_ks_common_param_pkg::*;
  import hpu_common_instruction_pkg::*;
  import pep_common_param_pkg::*;

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int CLK_HALF_PERIOD = 1;
  localparam int ARST_ACTIVATION = 17;

  parameter  int SAMPLE_ITER = 100;
  localparam int SAMPLE_NB   = TOTAL_PBS_NB * SAMPLE_ITER;

  parameter int INST_FIFO_DEPTH   = 8; // Should be >= 2

  localparam int LDG_IDX = 0;
  localparam int LDB_IDX = 1;
  localparam [1:0][31:0] LD_LATENCY = {32'd23,32'd139};

  localparam int KS_LATENCY = 40;
  localparam int KS_LOOP_MAX = ((LWE_K_P1 + LBX-1) / LBX) * LBX;

  localparam int PBS_LATENCY = 50;
  localparam int SXT_LATENCY = 13;

  parameter  int RAND_RANGE = 1024-1;
  parameter  int INST_THROUGHPUT = RAND_RANGE / 100; // 0 : random, 1: very rare, RAND_RANGE : always valid

  parameter  bit USE_BPIP = 1'b0;
  parameter  bit USE_OPPORTUNISM = 1'b0;
  parameter  int BPIP_TIMEOUT = BATCH_PBS_NB*256;

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
  bit error_map;
  bit error_bpip;
  bit error_map2;
  bit error_ack;
  bit error_iter;
  pep_seq_error_t seq_error;

  assign error = error_map2 |
                 error_map  |
                 error_ack  |
                 error_iter |
                 error_bpip |
                 |seq_error;

  always_ff @(posedge clk)
    if (error) begin
      $display("%t > FAILURE !", $time);
      $finish;
    end

// ============================================================================================== --
// input / output signals
// ============================================================================================== --
   logic [PE_INST_W-1:0]       inst;
   logic                       inst_vld;
   logic                       inst_rdy;

   logic                       inst_ack;
   logic [LWE_K_W-1:0]         inst_ack_br_loop;
   logic                       inst_load_blwe_ack;

  // Configuration
   logic                        use_bpip;
   logic [TIMEOUT_CNT_W-1:0]    bpip_timeout;

  // To Loading units
   logic [LOAD_GLWE_CMD_W-1:0] seq_ldg_cmd;
   logic                       seq_ldg_vld;
   logic                       seq_ldg_rdy;

   logic [LOAD_BLWE_CMD_W-1:0] seq_ldb_cmd;
   logic                       seq_ldb_vld;
   logic                       seq_ldb_rdy;

  // From loading units
   logic                       ldg_seq_done;
   logic                       ldb_seq_done;

  // Keyswitch command
   logic                       ks_seq_cmd_enquiry;
   logic [KS_CMD_W-1:0]        seq_ks_cmd;
   logic                       seq_ks_cmd_avail;

  // Keyswitch result
   logic [KS_RESULT_W-1:0]     ks_seq_result;
   logic                       ks_seq_result_vld;
   logic                       ks_seq_result_rdy;

  // PBS command
   logic                       pbs_seq_cmd_enquiry;
   logic [PBS_CMD_W-1:0]       seq_pbs_cmd;
   logic                       seq_pbs_cmd_avail;

  // From sample extract
   logic                       sxt_seq_done;
   logic [PID_W-1:0]           sxt_seq_done_pid;

  // bsk_if and ksk_if start
    logic                      bsk_if_batch_start_1h;
    logic                      ksk_if_batch_start_1h;


  // Info for register_if
  pep_seq_info_t               seq_rif_info;
  pep_seq_counter_inc_t        seq_rif_counter_inc;

// ============================================================================================== --
// Design under test instance
// ============================================================================================== --
  pep_sequencer #(
    .INST_FIFO_DEPTH   (INST_FIFO_DEPTH)
  ) dut (
    .clk                 (clk    ),
    .s_rst_n             (s_rst_n),

    .use_bpip            (use_bpip    ),
    .bpip_timeout        (bpip_timeout),
    .use_bpip_opportunism (use_bpip_opportunism),

    .inst                (inst),
    .inst_vld            (inst_vld),
    .inst_rdy            (inst_rdy),

    .inst_ack            (inst_ack),
    .inst_ack_br_loop    (inst_ack_br_loop),
    .inst_load_blwe_ack  (inst_load_blwe_ack),

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

    .bsk_if_batch_start_1h (bsk_if_batch_start_1h), // TODO check this
    .ksk_if_batch_start_1h (ksk_if_batch_start_1h), // TODO check this

    .reset_cache         (1'b0), // TODO check this

    .seq_error           (seq_error),

    .seq_rif_info        (seq_rif_info),
    .seq_rif_counter_inc (seq_rif_counter_inc)
  );

// ============================================================================================== --
// Scenario
// ============================================================================================== --
  assign use_bpip     = USE_BPIP;
  assign bpip_timeout = BPIP_TIMEOUT;
  assign use_bpip_opportunism = USE_OPPORTUNISM;

//---------------------------------------
// Instruction
//---------------------------------------
  integer rand_inst;
  always_ff @(posedge clk)
    rand_inst <= $urandom();

  pep_inst_t inst_tmp;
  pep_inst_t inst_tmp2;

  assign inst_tmp2.dop     = rand_inst[5:0] == 0 ? DOP_PBS_F : DOP_PBS;
  assign inst_tmp2.gid     = inst_tmp.gid;
  assign inst_tmp2.src_rid = inst_tmp.src_rid;
  assign inst_tmp2.dst_rid = inst_tmp.dst_rid;

  assign inst = inst_tmp2;

  stream_source #(
    .FILENAME   ("random"),
    .DATA_TYPE  ("ascii_hex"),
    .DATA_W     (PEP_INST_W),
    .RAND_RANGE (RAND_RANGE),
    .KEEP_VLD   (1'b0),
    .MASK_DATA  ("x")
  ) inst_stream_source (
      .clk       (clk),
      .s_rst_n   (s_rst_n),

      .data      (inst_tmp),
      .vld       (inst_vld),
      .rdy       (inst_rdy),

      .throughput(INST_THROUGHPUT)
  );

  initial begin
    if (!inst_stream_source.open()) begin
      $fatal(1, "%t > ERROR: Opening inst_stream_source stream source", $time);
    end
    wait(s_rst_n);
    @(posedge clk);
    inst_stream_source.start(SAMPLE_NB);
  end


//---------------------------------------
// Load
//---------------------------------------
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

//---------------------------------------
// Start enquiry
//---------------------------------------
  logic start_enquiry;

  always_ff @(posedge clk)
    if (!s_rst_n) start_enquiry <= 1'b1;
    else          start_enquiry <= 1'b0;

//---------------------------------------
// Key switch
//---------------------------------------
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
      ks_res_lwe_a[i] = ((ks_res_rp + i) << LWE_K_W) + ks_res_loop;
    end

  assign ks_res_vld_tmp = |ks_cmd_avail_sr[KS_LATENCY +: LBX];
  assign ks_res_vld     = ks_res_vld_tmp & ks_res_loop < LWE_K ;
  assign ks_res.lwe_a   = ks_res_lwe_a;
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

//---------------------------------------
// PBS
//---------------------------------------
  logic [PBS_LATENCY-1:0]     pbs_cmd_avail_sr;
  logic [PBS_LATENCY-1:0]     pbs_cmd_avail_srD;
  pbs_cmd_t [PBS_LATENCY-1:0] pbs_cmd_sr;
  pbs_cmd_t [PBS_LATENCY-1:0] pbs_cmd_srD;

  assign pbs_cmd_avail_srD[0] = seq_pbs_cmd_avail;
  assign pbs_cmd_srD[0]       = seq_pbs_cmd;

  assign pbs_cmd_avail_srD[PBS_LATENCY-1:1] = pbs_cmd_avail_sr[PBS_LATENCY-2:0];
  assign pbs_cmd_srD[PBS_LATENCY-1:1]       = pbs_cmd_sr[PBS_LATENCY-2:0];

  always_ff @(posedge clk)
    if (!s_rst_n) pbs_cmd_avail_sr <= '0;
    else          pbs_cmd_avail_sr <= pbs_cmd_avail_srD;

  always_ff @(posedge clk)
    pbs_cmd_sr <= pbs_cmd_srD;

  assign pbs_seq_cmd_enquiry = pbs_cmd_avail_sr[PBS_LATENCY-1] | start_enquiry;

//---------------------------------------
// SXT
//---------------------------------------
  logic [SXT_LATENCY-1:0]     sxt_cmd_avail_sr;
  logic [SXT_LATENCY-1:0]     sxt_cmd_avail_srD;
  pbs_cmd_t [SXT_LATENCY-1:0] sxt_cmd_sr;
  pbs_cmd_t [SXT_LATENCY-1:0] sxt_cmd_srD;

  assign sxt_cmd_avail_srD[0] = pbs_cmd_avail_sr[PBS_LATENCY-1];
  assign sxt_cmd_srD[0]       = pbs_cmd_sr[PBS_LATENCY-1];

  assign sxt_cmd_avail_srD[SXT_LATENCY-1:1] = sxt_cmd_avail_sr[SXT_LATENCY-2:0];
  assign sxt_cmd_srD[SXT_LATENCY-1:1]       = sxt_cmd_sr[SXT_LATENCY-2:0];

  always_ff @(posedge clk)
    if (!s_rst_n) sxt_cmd_avail_sr <= '0;
    else          sxt_cmd_avail_sr <= sxt_cmd_avail_srD;

  always_ff @(posedge clk)
    sxt_cmd_sr <= sxt_cmd_srD;

  pbs_cmd_t sxt_in;
  logic     sxt_in_vld;
  logic     sxt_in_rdy;

  pbs_cmd_t sxt_out;
  logic     sxt_out_vld;
  logic     sxt_out_rdy;

  assign sxt_in_vld = sxt_cmd_avail_sr[SXT_LATENCY-1];
  assign sxt_in     = sxt_cmd_sr[SXT_LATENCY-1];

  fifo_reg #(
    .WIDTH       (PBS_CMD_W),
    .DEPTH       (2),
    .LAT_PIPE_MH ({1'b1, 1'b1})
  ) sxt_fifo_reg (
    .clk      (clk),
    .s_rst_n  (s_rst_n),

    .in_data  (sxt_in),
    .in_vld   (sxt_in_vld),
    .in_rdy   (sxt_in_rdy),

    .out_data (sxt_out),
    .out_vld  (sxt_out_vld),
    .out_rdy  (sxt_out_rdy)
  );

  integer sxt_ct_cnt;
  integer sxt_ct_cntD;

  assign sxt_ct_cntD = (sxt_out_vld && sxt_out_rdy) ? '0 :
                      sxt_out_vld ? sxt_ct_cnt + 1 : sxt_ct_cnt;

  always_ff @(posedge clk)
    if (!s_rst_n) sxt_ct_cnt <= '0;
    else          sxt_ct_cnt <= sxt_ct_cntD;

  assign sxt_out_rdy = sxt_ct_cnt == BATCH_PBS_NB-1;

  assign sxt_seq_done     = sxt_out_vld & sxt_out.map[sxt_ct_cnt/GRAM_NB][sxt_ct_cnt%GRAM_NB].avail & sxt_out.map[sxt_ct_cnt/GRAM_NB][sxt_ct_cnt%GRAM_NB].last;
  assign sxt_seq_done_pid = sxt_out.map[sxt_ct_cnt/GRAM_NB][sxt_ct_cnt%GRAM_NB].pid.pid;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      if (sxt_in_vld)
        assert(sxt_in_rdy)
        else begin
          $fatal(1,"%t > ERROR: sxt_fifo_reg overflow!", $time);
        end
    end


// ============================================================================================== --
// Check
// ============================================================================================== --
  pbs_cmd_t seq_pbs_cmd_s;
  integer ref_br_loop;
  integer ref_br_loopD;

  assign seq_pbs_cmd_s = seq_pbs_cmd;
  assign ref_br_loopD  = seq_pbs_cmd_avail ? ref_br_loop == LWE_K-1 ? '0 : ref_br_loop+1 : ref_br_loop;

  always_ff @(posedge clk)
    if (!s_rst_n) ref_br_loop <= '0;
    else          ref_br_loop <= ref_br_loopD;

  always_ff @(posedge clk)
    if (!s_rst_n)
      error_map <= 1'b0;
    else begin
      if (seq_pbs_cmd_avail) begin
        if (seq_pbs_cmd_s.is_flush) begin
          // check that all avail bits of the map are null
          for (int i=0; i<RANK_NB; i=i+1)
            for (int j=0; j<GRAM_NB; j=j+1)
              assert(seq_pbs_cmd_s.map[i][j].avail == 1'b0)
              else begin
                $display("%t > ERROR: PBS flush command : map avail bits are not all null [rank=%0d][grid=%0d]",$time, i,j);
                error_map <= 1'b1;
              end

        end
        else begin
          for (int i=0; i<RANK_NB; i=i+1)
            for (int j=0; j<GRAM_NB; j=j+1)
              if (seq_pbs_cmd_s.map[i][j].avail) begin
                assert((seq_pbs_cmd_s.map[i][j].lwe & ((1 << LWE_K_W)-1)) == ref_br_loop)
                else begin
                  $display("%t > ERROR: map lwe br_loop : exp=0x%0x seen=0x%0x",$time, ref_br_loop, seq_pbs_cmd_s.map[i][j].lwe & ((1 << LWE_K_W)-1));
                  error_map <= 1'b1;
                end
              end
        end
      end
    end

  always_ff @(posedge clk)
    if (!s_rst_n)
      error_bpip <= 1'b0;
    else if (USE_BPIP) begin
      if (seq_pbs_cmd_avail) begin
        for (int i=0; i<RANK_NB; i=i+1)
          for (int j=0; j<GRAM_NB; j=j+1)
            if (seq_pbs_cmd_s.map[i][j].avail) begin
              assert(seq_pbs_cmd_s.map[i][j].first == (seq_pbs_cmd_s.br_loop == 0))
              else begin
                $display("%t > ERROR: BPIP first br_loop should be 0: seen=0x%0x",$time, seq_pbs_cmd_s.br_loop);
                error_bpip <= 1'b1;
              end
            end
      end
    end

//---------------------------------------
// Check ct order in map
//---------------------------------------
  // Keep track of rank for each ct
  logic [TOTAL_PBS_NB-1:0][RANK_W-1:0] ref_ct_rank;
  logic [TOTAL_PBS_NB-1:0][RANK_W-1:0] ref_ct_rankD;

  integer ref_iteration [TOTAL_PBS_NB-1:0];
  integer ref_iterationD [TOTAL_PBS_NB-1:0];

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      ref_iteration <= '{TOTAL_PBS_NB{32'd0}};
      for (int i=0; i<TOTAL_PBS_NB; i=i+1)
        ref_ct_rank[i] <= (i / GRAM_NB) % RANK_NB;
    end
    else begin
      ref_iteration <= ref_iterationD;
      ref_ct_rank   <= ref_ct_rankD;
    end


  always_comb begin
    ref_ct_rankD = ref_ct_rank;
    ref_iterationD = ref_iteration;
    if (seq_pbs_cmd_avail)
      for (int i=0; i<RANK_NB; i=i+1)
        for (int j=0; j<GRAM_NB; j=j+1)
          if (seq_pbs_cmd_s.map[i][j].avail && seq_pbs_cmd_s.map[i][j].last) begin
            ref_ct_rankD[seq_pbs_cmd_s.map[i][j].pid.pid] = (ref_ct_rank[seq_pbs_cmd_s.map[i][j].pid.pid] + ((TOTAL_PBS_NB/GRAM_NB) % RANK_NB))%RANK_NB;
            ref_iterationD[seq_pbs_cmd_s.map[i][j].pid.pid] = ref_iteration[seq_pbs_cmd_s.map[i][j].pid.pid] + 1;
          end
  end

  always_ff @(posedge clk)
    if (!s_rst_n)
      error_map2 <= 1'b0;
    else begin
      if (seq_pbs_cmd_avail)
        for (int i=0; i<RANK_NB; i=i+1)
          for (int j=0; j<GRAM_NB; j=j+1)
            if (seq_pbs_cmd_s.map[i][j].avail) begin
              assert((i == ref_ct_rank[seq_pbs_cmd_s.map[i][j].pid.pid]) && (j == seq_pbs_cmd_s.map[i][j].pid.grid))
              else begin
                $display("%t > ERROR: ITER[%0d] pbs_id[%0d] is not at its correct location. exp=(rk=%0d, grid=%0d) seen=(rk=%0d, grid=%0d)",
                          $time,ref_iteration[seq_pbs_cmd_s.map[i][j].pid.pid], seq_pbs_cmd_s.map[i][j].pid.pid,
                          ref_ct_rank[seq_pbs_cmd_s.map[i][j].pid.pid], seq_pbs_cmd_s.map[i][j].pid.grid,i,j);
                error_map2 <= 1'b1;
              end
            end
    end


// ============================================================================================== --
// End of test
// ============================================================================================== --
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
      if (inst_vld && inst_rdy && (inst_cntD%100 == 0))
        $display("%t > INFO: INPUT instruction #%0d", $time, inst_cntD);
      if (sxt_seq_done && (sxt_cntD%100 == 0))
        $display("%t > INFO: DONE sxt cmd #%0d", $time, sxt_cntD);
    end

  initial begin
    end_of_test <= 1'b0;
    error_ack   <= 1'b0;
    error_iter  <= 1'b0;

    wait (inst_cnt == SAMPLE_NB);
    $display("%t > INFO: All instructions sent",$time);
    wait (sxt_cnt == SAMPLE_NB);
    $display("%t > INFO: All ciphertexts processed",$time);

    repeat(100) @(posedge clk);

    assert(inst_ack_cnt == SAMPLE_NB)
    else begin
      $display("%t > ERROR: Wrong number of inst_ack. exp=%0d seen=%0d", $time, SAMPLE_NB, inst_ack_cnt);
      error_ack <= 1'b1;
    end

    for (int i=0; i<TOTAL_PBS_NB; i=i+1)
      assert(ref_iteration[i] == SAMPLE_ITER)
      else begin
        $display("%t > ERROR: Wrong number of iteration for ct[%0d]. exp=%0d seen=%0d", $time, i, SAMPLE_ITER, ref_iteration[i]);
        error_iter <= 1'b1;
      end

    end_of_test <= 1'b1;

  end

endmodule
