// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module tests ks_control + ks_blwe_ram.
// ==============================================================================================

module tb_pep_key_switch;
  import common_definition_pkg::*;
  import param_tfhe_pkg::*;
  import pep_common_param_pkg::*;
  import pep_ks_common_param_pkg::*;

  `timescale 1ns/10ps
// ============================================================================================== --
// localparam / parameter
// ============================================================================================== --
  parameter  int BLWE_RAM_DEPTH   = KS_BLOCK_LINE_NB * TOTAL_PBS_NB;
  localparam int BLWE_RAM_ADD_W   = $clog2(BLWE_RAM_DEPTH);
  parameter  int DATA_LATENCY     = 6; // BLRAM access read latency
  parameter  int RAM_LATENCY      = 2;

  parameter  int KS_IF_COEF_NB   = LBY;
  parameter  int KS_IF_SUBW_NB   = 1;
  localparam int BLWE_SUBW_COEF_NB = KS_IF_COEF_NB * KS_IF_SUBW_NB;

  localparam int CLK_HALF_PERIOD = 1;
  localparam int ARST_ACTIVATION = 17;

  parameter  int SAMPLE_CMD_NB   = ((LWE_K_P1 + LBX-1) / LBX) * 4;

  localparam int PBS_SUBW_NB     = (BLWE_K_P1+BLWE_SUBW_COEF_NB-1)/BLWE_SUBW_COEF_NB;
  localparam int KSK_BLOCK_NB_PER_SLOT = KS_LG_NB * KS_BLOCK_LINE_NB * LBX;

  localparam bit SEND_OFIFO_INC_ON_LAST_BCOL = LWE_K % LBX != 0;

  localparam int ALMOST_DONE_BLINE_ID = KS_BLOCK_LINE_NB < 2 ? 0 : KS_BLOCK_LINE_NB - 2;

  localparam int    DATA_RAND_RANGE = 1023;
  localparam string FILE_DATA_TYPE  = "ascii_hex";
  localparam int    DATA_RAND_RANGE_W = $clog2(DATA_RAND_RANGE+1);

  generate
    if (PBS_SUBW_NB < 2) begin : __UNSUPPORTED_PBS_SUBW_NB_
      initial begin
        $fatal(1,"> ERROR: This bench only supports PBS_SUBW_NB (%0d) >= 2.", PBS_SUBW_NB);
      end
    end
  endgenerate

// ============================================================================================== --
// structure
// ============================================================================================== --
  typedef struct packed {
    logic [TOTAL_BATCH_NB_W-1:0] batch_id;
    logic [BPBS_ID_W-1:0]        pbs_id;
    logic [BLWE_K_P1_W:0]        coef; // Additional bit to count "extra" unused coefficient.
    logic                        padding; // For fake decomp
  } data_t;

  localparam int DATA_W = $bits(data_t);

  typedef struct packed {
    integer batch_id;
    integer pbs_nb;
  } cmd_t;


  initial begin
    if (DATA_W > MOD_Q_W)
      $fatal(1,"> ERROR: MOD_Q_W is not big enough to contain the structure data_t.");
  end

// ============================================================================================== --
// function
// ============================================================================================== --
  localparam int CLOSEST_REP_W   = KS_L * KS_B_W;
  localparam int CLOSEST_REP_OFS = MOD_Q_W - CLOSEST_REP_W;

  // Input_word to be "rounded", decomposition parameters level_count and base_log
  // Outputs: Computes the closest representable number by the decomposition defined by
  //  level_count and base_log.
  function logic [MOD_Q_W-1:0] closest_representable(logic [MOD_Q_W-1:0] input_word);
    logic               non_rep_msb;
    logic [MOD_Q_W-1:0] res;

    non_rep_msb = input_word[CLOSEST_REP_OFS - 1];
    res = input_word >> CLOSEST_REP_OFS;
    res = res + non_rep_msb;
    res = res << CLOSEST_REP_OFS;
    return res;
  endfunction

  // Inputs:
  //  Coefficient decomp_input to be decomposed with decomposition parameters level_l and base_log
  // Output: list of level_l coefficients representing the closest representable number
  function logic [KS_L-1:0][KS_B_W:0] decompose(logic [MOD_Q_W-1:0] decomp_input);
    logic [MOD_Q_W-1:0]        closest_rep;
    logic [KS_L-1:0][KS_B_W:0] res;
    logic [MOD_Q_W-1:0]        state;
    logic [KS_B_W:0]           mod_b_mask;
    logic [KS_B_W:0]           decomp_output;
    logic [MOD_Q_W-1:0]        carry;
    logic [MOD_Q_W-1:0]        recons;

    closest_rep = closest_representable(decomp_input);

    state = closest_rep >> CLOSEST_REP_OFS;
    mod_b_mask = (1 << KS_B_W) - 1;
    for (int i=0; i<KS_L; i=i+1) begin
      // Decompose the current level
      decomp_output = state & mod_b_mask;
      state = state >> KS_B_W;
      carry = ((decomp_output-1) | state) & decomp_output;
      carry >>= KS_B_W - 1;
      state += carry;
      decomp_output = decomp_output - (carry << KS_B_W);
      res[i][KS_B_W]     = decomp_output[KS_B_W];
      res[i][KS_B_W-1:0] = decomp_output[KS_B_W] ? -decomp_output : decomp_output;

    end
    return res;
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
// Error
// ============================================================================================== --
  bit error;
  bit error_ks;
  bit error_body_cnt;
  bit error_enquiry;

  assign error = error_ks | error_body_cnt;

  always_ff @(posedge clk)
    if (error) begin
      $display("%t > ERROR: error_ks seen=0x%0d", $time, error_ks);
      $display("%t > FAILURE !", $time);
      $finish;
    end

// ============================================================================================== --
// input / output signals
// ============================================================================================== --
  logic                                            ks_seq_cmd_enquiry;
  logic [KS_CMD_W-1:0]                             seq_ks_cmd;
  logic                                            seq_ks_cmd_avail;

  logic                                            inc_ksk_wr_ptr;
  logic                                            inc_ksk_rd_ptr;

  logic [KS_IF_SUBW_NB-1:0]                        ldb_blram_wr_en;
  logic [KS_IF_SUBW_NB-1:0][PID_W-1:0]             ldb_blram_wr_pid;
  logic [KS_IF_SUBW_NB-1:0][KS_IF_COEF_NB-1:0][MOD_Q_W-1:0] ldb_blram_wr_data;
  logic [KS_IF_SUBW_NB-1:0]                        ldb_blram_wr_pbs_last;

  logic [KS_BATCH_CMD_W-1:0]                       batch_cmd;
  logic                                            batch_cmd_avail; // pulse

  // KSK
  logic [LBX-1:0][LBY-1:0][LBZ-1:0][MOD_KSK_W-1:0] ksk;
  logic [LBX-1:0][LBY-1:0]                         ksk_vld;
  logic [LBX-1:0][LBY-1:0]                         ksk_rdy;

  // LWE coeff
  logic [KS_RESULT_W-1:0]                          ks_seq_result;
  logic                                            ks_seq_result_vld;
  logic                                            ks_seq_result_rdy;

  // Wr access to body RAM
  logic                                            boram_wr_en;
  logic [MOD_KSK_W-1:0]                            boram_data;
  logic [PID_W-1:0]                                boram_pid;
  logic                                            boram_parity;

// ============================================================================================== --
// Design under test instance
// ============================================================================================== --
  pep_key_switch
  #(
    .RAM_LATENCY          (RAM_LATENCY),
    .ALMOST_DONE_BLINE_ID (ALMOST_DONE_BLINE_ID),
    .KS_IF_SUBW_NB        (KS_IF_SUBW_NB),
    .KS_IF_COEF_NB        (KS_IF_COEF_NB)
  ) dut (
    .clk                   (clk),
    .s_rst_n               (s_rst_n),

    .ks_seq_cmd_enquiry    (ks_seq_cmd_enquiry),
    .seq_ks_cmd            (seq_ks_cmd),
    .seq_ks_cmd_avail      (seq_ks_cmd_avail),

    .inc_ksk_wr_ptr        (inc_ksk_wr_ptr),
    .inc_ksk_rd_ptr        (inc_ksk_rd_ptr),


    .batch_cmd             (batch_cmd),
    .batch_cmd_avail       (batch_cmd_avail),

    .ldb_blram_wr_en       (ldb_blram_wr_en),
    .ldb_blram_wr_pid      (ldb_blram_wr_pid),
    .ldb_blram_wr_data     (ldb_blram_wr_data),
    .ldb_blram_wr_pbs_last (ldb_blram_wr_pbs_last),


    .ksk                   (ksk),
    .ksk_vld               (ksk_vld),
    .ksk_rdy               (ksk_rdy),


    .ks_seq_result         (ks_seq_result),
    .ks_seq_result_vld     (ks_seq_result_vld),
    .ks_seq_result_rdy     (ks_seq_result_rdy),


    .boram_wr_en           (boram_wr_en),
    .boram_data            (boram_data),
    .boram_pid             (boram_pid),
    .boram_parity          (boram_parity),

    .reset_cache           ('0), // Not checked here

    .ks_error              (error_ks)
  );

// ============================================================================================== --
// Scenario
// ============================================================================================== --
// ---------------------------------------------------------------------------------------------- --
// FSM
// ---------------------------------------------------------------------------------------------- --
  typedef enum {ST_IDLE,
                ST_FILL_BLRAM,
                ST_PROCESS,
                ST_DONE} state_e;

  state_e state;
  state_e next_state;
  logic start;
  logic fill_blram_done;
  logic process_done;

  logic st_idle;
  logic st_fill_blram;
  logic st_process;
  logic st_done;

  always_comb begin
    case (state)
      ST_IDLE:
        next_state = start ? ST_FILL_BLRAM : state;
      ST_FILL_BLRAM:
        next_state = fill_blram_done ? ST_PROCESS : state;
      ST_PROCESS:
        next_state = process_done ? ST_DONE : state;
      ST_DONE:
        next_state = state;
    endcase
  end

  assign st_idle       = state == ST_IDLE;
  assign st_fill_blram = state == ST_FILL_BLRAM;
  assign st_process    = state == ST_PROCESS;
  assign st_done       = state == ST_DONE;

  always_ff @(posedge clk)
    if (!s_rst_n) state <= ST_IDLE;
    else          state <= next_state;

// ---------------------------------------------------------------------------------------------- --
// Fill BLRAM
// ---------------------------------------------------------------------------------------------- --
  // counters
  integer fb_pbs_id;
  integer fb_pbs_subw;
  integer fb_pbs_idD;
  integer fb_pbs_subwD;

  logic   fb_last_pbs_subw;
  logic   fb_penult_pbs_subw;
  logic   fb_last_pbs_id;
  logic   fb_inc;

  assign fb_last_pbs_subw   = fb_pbs_subw == PBS_SUBW_NB-1;
  assign fb_penult_pbs_subw = fb_pbs_subw == PBS_SUBW_NB-2;
  assign fb_last_pbs_id     = fb_pbs_id == TOTAL_PBS_NB-1;

  assign fb_pbs_subwD = fb_inc ?                     fb_last_pbs_subw ? '0 : fb_pbs_subw + 1 : fb_pbs_subw;
  assign fb_pbs_idD   = fb_inc && fb_last_pbs_subw ? fb_last_pbs_id   ? '0 : fb_pbs_id   + 1 : fb_pbs_id;

  assign fb_inc = st_fill_blram;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      fb_pbs_subw <= '0;
      fb_pbs_id   <= '0;
    end
    else begin
      fb_pbs_subw <= fb_pbs_subwD;
      fb_pbs_id   <= fb_pbs_idD  ;
    end

  assign fill_blram_done = fb_inc & fb_last_pbs_id & fb_last_pbs_subw;

  // Interface
  logic [KS_BLOCK_LINE_NB:0][LBY-1:0][MOD_Q_W-1:0] in_data;
  logic [KS_IF_SUBW_NB-1:0][KS_IF_COEF_NB-1:0][MOD_Q_W-1:0]    fb_wr_in_data;
  logic [KS_IF_SUBW_NB-1:0][KS_IF_COEF_NB*MOD_Q_W+1+1+PID_W-1:0] fb_wr_in_elt;

  logic [KS_IF_SUBW_NB-1:0]                                    fb_out_wr_vld;
  logic [KS_IF_SUBW_NB-1:0]                                    fb_out_wr_rdy;
  logic [KS_IF_SUBW_NB-1:0]                                    fb_out_wr_pbs_last;
  logic [KS_IF_SUBW_NB-1:0]                                    fb_out_wr_pbs_penult;
  logic [KS_IF_SUBW_NB-1:0][PID_W-1:0]                         fb_out_wr_pid;
  logic [KS_IF_SUBW_NB-1:0][KS_IF_COEF_NB-1:0][MOD_Q_W-1:0]    fb_wr_out_data;
  logic [KS_IF_SUBW_NB-1:0][KS_IF_COEF_NB*MOD_Q_W+1+1+PID_W-1:0] fb_wr_out_elt;

  // Reorder in_data
  always_comb
    for (int j=0; j<KS_IF_SUBW_NB; j=j+1)
      for (int i=0; i<KS_IF_COEF_NB; i=i+1) begin
        integer k;
        k = (fb_pbs_subw*BLWE_SUBW_COEF_NB + j*KS_IF_COEF_NB + i);
        fb_wr_in_data[j][i] = in_data[k/LBY][k%LBY];
      end

  always_comb
    for (int j=0; j<KS_IF_SUBW_NB; j=j+1)
      fb_wr_in_elt[j] = {fb_penult_pbs_subw,fb_last_pbs_subw, fb_pbs_id[PID_W-1:0], fb_wr_in_data[j]};

  stream_to_seq #(
    .WIDTH (KS_IF_COEF_NB*MOD_Q_W+1+1+PID_W),
    .IN_NB (KS_IF_SUBW_NB),
    .SEQ   (KS_IF_SUBW_NB)
  ) stream_to_seq (
    .clk      (clk),
    .s_rst_n  (s_rst_n),

    .in_data  (fb_wr_in_elt),
    .in_vld   (fb_inc),
    .in_rdy   (/*UNUSED*/),

    .out_data (fb_wr_out_elt),
    .out_vld  (fb_out_wr_vld),
    .out_rdy  (fb_out_wr_rdy)
  );

  assign fb_out_wr_rdy = '1;

  always_comb
    for (int j=0; j<KS_IF_SUBW_NB; j=j+1) begin
      {fb_out_wr_pbs_penult[j],fb_out_wr_pbs_last[j],fb_out_wr_pid[j],fb_wr_out_data[j]} = fb_wr_out_elt[j];
    end

  assign ldb_blram_wr_data       = fb_wr_out_data;
  assign ldb_blram_wr_pid        = fb_out_wr_pid;

  always_comb begin
    ldb_blram_wr_pbs_last[0]   = fb_out_wr_pbs_last[0];
    ldb_blram_wr_en[0]         = fb_out_wr_vld[0];
    for (int j=1; j<KS_IF_SUBW_NB; j=j+1) begin
      ldb_blram_wr_pbs_last[j]   = fb_out_wr_pbs_penult[j];
      ldb_blram_wr_en[j]         = fb_out_wr_vld[j] & ~fb_out_wr_pbs_last[j];
    end
  end

// ---------------------------------------------------------------------------------------------- --
// fill_in_data
// ---------------------------------------------------------------------------------------------- --
// Do this to avoid too much memory usage
/*  logic fill_in_data;
  logic start_dly;

  always_ff @(posedge clk)
    if (fill_in_data) begin
      logic [KS_L-1:0][KS_B_W:0] d_tmp2;
      for (int l=0; l<KS_BLOCK_LINE_NB; l=l+1) begin
        for (int y=0; y<LBY; y=y+1) begin
          in_data[l][y] <= {$urandom,$urandom};
        end // for y
      end // for l
      //== body
      if (BLWE_K%LBY == 0) begin
        in_data[KS_BLOCK_LINE_NB][0] <= {$urandom,$urandom}; // Add body
        for (int y=1; y<LBY; y=y+1)
          in_data[KS_BLOCK_LINE_NB][y] <= '1;// identifiable dummy values
      end
    end

  assign fill_in_data = (~start & start_dly) // initialization
                      | (fb_inc & fb_last_pbs_subw); // process new PBS

  always_ff @(posedge clk)
    if (!s_rst_n) start_dly <= 1'b0;
    else          start_dly <= start;
*/

// ---------------------------------------------------------------------------------------------- --
// Process
// ---------------------------------------------------------------------------------------------- --
// Keep track of the enquiry
  logic error_enquiry_tmp;
  logic ks_seq_cmd_enquiry_vld;
  logic ks_seq_cmd_enquiry_rdy;

  common_lib_pulse_to_rdy_vld
  #(
    .FIFO_DEPTH(1)
  ) common_lib_pulse_to_rdy_vld  (
    .clk     (clk),
    .s_rst_n (s_rst_n),

    .in_pulse(ks_seq_cmd_enquiry),

    .out_vld (ks_seq_cmd_enquiry_vld),
    .out_rdy (ks_seq_cmd_enquiry_rdy),

    .error   (error_enquiry_tmp)
  );

  always_ff @(posedge clk)
    if (!s_rst_n) error_enquiry <= 1'b0;
    else begin
      assert(!error_enquiry_tmp)
      else begin
        $display("%t > ERROR: Enquiry overflow!",$time);
        error_enquiry <= 1'b1;
      end
    end

// Build command
  integer proc_ks_koop;
  integer proc_ks_koopD;
  logic   proc_last_ks_loop;

  assign proc_last_ks_loop = proc_ks_koop == KS_BLOCK_COL_NB-1;
  assign proc_ks_koopD = seq_ks_cmd_avail ? proc_last_ks_loop ? '0 : proc_ks_koop + 1 : proc_ks_koop;

  always_ff @(posedge clk)
    if (!s_rst_n) proc_ks_koop <= '0;
    else          proc_ks_koop <= proc_ks_koopD;

  ks_cmd_t               proc_cmd;
  logic [PID_W-1:0]      proc_rp;
  logic [BPBS_NB_WW-1:0] proc_ct_nb;
  logic [PID_W:0]        proc_wp;
  logic [PID_W:0]        proc_wp_tmp;
  logic                  rand_cmd_avail;
  ks_cmd_t               cmd_q[$];

  assign proc_wp_tmp        = (proc_rp + proc_ct_nb) > TOTAL_PBS_NB ? proc_ct_nb + proc_rp - TOTAL_PBS_NB : proc_rp + proc_ct_nb;
  assign proc_wp[PID_W]     = (proc_rp + proc_ct_nb) > TOTAL_PBS_NB;
  assign proc_wp[PID_W-1:0] = proc_wp_tmp[PID_W-1:0];

  always_ff @(posedge clk) begin
    proc_rp        <= $urandom_range(0,TOTAL_PBS_NB-1);
    proc_ct_nb     <= $urandom_range(1,BATCH_PBS_NB);
    rand_cmd_avail <= $urandom();
  end

  assign proc_cmd.ks_loop = proc_ks_koop * LBX;
  assign proc_cmd.rp      = proc_rp; // Extend with 0
  assign proc_cmd.wp      = proc_wp;

  assign seq_ks_cmd             = proc_cmd;
  assign seq_ks_cmd_avail       = st_process & ks_seq_cmd_enquiry_vld & rand_cmd_avail;
  assign ks_seq_cmd_enquiry_rdy = st_process & rand_cmd_avail;

  always_ff @(posedge clk)
    if (seq_ks_cmd_avail)
      cmd_q.push_back(seq_ks_cmd);

// ============================================================================================== --
// KSK
// ============================================================================================== --
  // Fake loading of the KSK in the ksk_mgr
  integer inc_ksk_wr_ptr_cnt ;
  integer inc_ksk_wr_ptr_cntD;

  assign inc_ksk_wr_ptr_cntD = seq_ks_cmd_avail ? 1 :
                               inc_ksk_wr_ptr_cnt > 0 ? inc_ksk_wr_ptr_cnt - 1 : inc_ksk_wr_ptr_cnt;
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      inc_ksk_wr_ptr     <= '0;
      inc_ksk_wr_ptr_cnt <= '0;
    end
    else begin
      inc_ksk_wr_ptr      <= inc_ksk_wr_ptr_cnt > 0;
      inc_ksk_wr_ptr_cnt  <= inc_ksk_wr_ptr_cntD;
    end


  // KSK mgr interface
  generate
    for (genvar gen_x=0; gen_x<LBX; gen_x=gen_x+1) begin : gen_ksk_x
      for (genvar gen_y=0; gen_y<LBY; gen_y=gen_y+1)  begin : gen_ksk_y

        stream_source
        #(
          .FILENAME   ("random"),
          .DATA_TYPE  ("ascii_hex"),
          .DATA_W     (LBZ*MOD_KSK_W),
          .RAND_RANGE (DATA_RAND_RANGE),
          .KEEP_VLD   (1),
          .MASK_DATA  ("x")
        )
        source_ksk
        (
          .clk        (clk),
          .s_rst_n    (s_rst_n),

          .data       (ksk[gen_x][gen_y]),
          .vld        (ksk_vld[gen_x][gen_y]),
          .rdy        (ksk_rdy[gen_x][gen_y]),

          .throughput (DATA_RAND_RANGE_W'(DATA_RAND_RANGE))
        );

        initial begin
          if (!source_ksk.open()) begin
            $fatal(1, "%t > ERROR: Opening source_ksk stream source", $time);
          end
          source_ksk.start(0);
        end

      end
    end
  endgenerate

// ============================================================================================== --
// Sink
// ============================================================================================== --
  stream_sink
  #(
    .FILENAME_REF   (""),
    .DATA_TYPE_REF  (FILE_DATA_TYPE),
    .FILENAME       (""),
    .DATA_TYPE      (FILE_DATA_TYPE),
    .DATA_W         (KS_RESULT_W),
    .RAND_RANGE     (DATA_RAND_RANGE),
    .KEEP_RDY       (1)
  )
  sink_result
  (
      .clk        (clk),
      .s_rst_n    (s_rst_n),

      .data       (ks_seq_result),
      .vld        (ks_seq_result_vld),
      .rdy        (ks_seq_result_rdy),

      .error      (/*UNUSED*/),
      .throughput (DATA_RAND_RANGE_W'(DATA_RAND_RANGE/10))
  );

  initial begin
    sink_result.set_do_ref(0);
    sink_result.set_do_write(0);
    sink_result.start(0);
  end

// ============================================================================================== --
// Control
// ============================================================================================== --
  localparam int RESULT_NB = (SAMPLE_CMD_NB / KS_BLOCK_COL_NB) * LWE_K + (SAMPLE_CMD_NB % KS_BLOCK_COL_NB) * LBX;
  localparam int BODY_NB   = (SAMPLE_CMD_NB / KS_BLOCK_COL_NB); // Minimum number of body
  always_ff @(posedge clk) begin
    if (!s_rst_n) start <= 1'b0;
    else          start <= 1'b1;
  end

  integer proc_cmd_cnt;
  integer result_cnt;
  integer body_cnt;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      proc_cmd_cnt <= '0;
      result_cnt   <= '0;
      body_cnt     <= '0;
    end
    else begin
      proc_cmd_cnt <= seq_ks_cmd_avail ? proc_cmd_cnt + 1 : proc_cmd_cnt;
      result_cnt   <= ks_seq_result_vld && ks_seq_result_rdy ? result_cnt + 1 : result_cnt;
      body_cnt     <= boram_wr_en ? body_cnt + 1 : body_cnt;
    end

  assign process_done = proc_cmd_cnt >= SAMPLE_CMD_NB;

  initial begin
    error_body_cnt <= 1'b0;
    end_of_test = 0;
    wait(s_rst_n);
    wait(st_fill_blram);
    $display("%t > INFO: Fill BLRAM done.", $time);
    wait(st_process);
    $display("%t > INFO: Process...", $time);
    wait(st_done);
    $display("%t > INFO: Process... done", $time);
    @(posedge clk);
    wait(ks_seq_cmd_enquiry_vld);
    @(posedge clk);
    wait (result_cnt == RESULT_NB);
    @(posedge clk);
    if (body_cnt < BODY_NB) begin
      $display("%t > ERROR: Wrong number of body seen at the end of the simulation. exp=%0d seen=%0d", $time, BODY_NB, body_cnt);
      error_body_cnt <= 1'b1;
    end
    end_of_test = 1;
  end


  always_ff @(posedge clk)
    if (ks_seq_result_vld && ks_seq_result_rdy && result_cnt%10 == 0)
      $display("%t > INFO : Result %0d", $time, result_cnt);



endmodule
