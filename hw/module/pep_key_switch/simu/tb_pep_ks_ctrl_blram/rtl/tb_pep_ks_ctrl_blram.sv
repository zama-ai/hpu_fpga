// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module tests ks_control + ks_blwe_ram.
// ==============================================================================================

module tb_pep_ks_ctrl_blram;
  import common_definition_pkg::*;
  import param_tfhe_pkg::*;
  import pep_common_param_pkg::*;
  import pep_ks_common_param_pkg::*;

  `timescale 1ns/10ps
// ============================================================================================== --
// localparam / parameter
// ============================================================================================== --
  parameter  int OP_W             = MOD_Q_W;
  parameter  int BLWE_RAM_DEPTH   = KS_BLOCK_LINE_NB * TOTAL_PBS_NB;
  localparam int BLWE_RAM_ADD_W   = $clog2(BLWE_RAM_DEPTH);
  parameter  int DATA_LATENCY     = 6; // BLRAM access read latency
  parameter  int RAM_LATENCY      = 2;

  localparam int KS_B  = 2**KS_B_W;

  parameter  int KS_IF_COEF_NB   = LBY;
  parameter  int KS_IF_SUBW_NB   = 1;
  localparam int BLWE_SUBW_COEF_NB = KS_IF_COEF_NB * KS_IF_SUBW_NB;

  localparam int CLK_HALF_PERIOD = 1;
  localparam int ARST_ACTIVATION = 17;

  parameter  int SAMPLE_CMD_NB   = ((LWE_K_P1 + LBX-1) / LBX) * 4;

  localparam int PBS_SUBW_NB     = (BLWE_K_P1+BLWE_SUBW_COEF_NB-1)/BLWE_SUBW_COEF_NB;

  localparam bit SEND_OFIFO_INC_ON_LAST_BCOL = LWE_K % LBX != 0;

  localparam int ALMOST_DONE_BLINE_ID = KS_BLOCK_LINE_NB < 2 ? 0 : KS_BLOCK_LINE_NB - 2;

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
    logic [MOD_Q_W-1:0]        state_tmp;
    logic [(KS_L+1)*KS_B_W-1:0]state;
    logic [KS_B_W:0]           mod_b_mask;
    logic [KS_B_W:0]           decomp_output;
    logic [MOD_Q_W-1:0]        carry;
    logic [MOD_Q_W-1:0]        recons;

    closest_rep = closest_representable(decomp_input);

    state_tmp = closest_rep >> CLOSEST_REP_OFS;

    //if state > base**level/2 or (state == base**level/2 and bit == 1):
    //    state = state - base**level

    state = state_tmp;
    if (state > (KS_B**KS_L)/2 || (state == (KS_B**KS_L)/2 && decomp_input[CLOSEST_REP_OFS - 1] == 1))
      state = state_tmp - KS_B**KS_L;

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
  bit error_mask;
  bit error_body;
  bit error_info;
  bit error_enquiry;

  assign error = error_mask | error_body | error_info | error_enquiry;

  always_ff @(posedge clk)
    if (error) begin
      $display("%t > error_mask=%1d",$time, error_mask);
      $display("%t > error_body=%1d",$time, error_body);
      $display("%t > error_info=%1d",$time, error_info);
      $display("%t > error_enquiry=%1d",$time, error_enquiry);
      $display("%t > FAILURE !", $time);
      $finish;
    end

// ============================================================================================== --
// input / output signals
// ============================================================================================== --
  logic                                           ks_seq_cmd_enquiry;
  logic [KS_CMD_W-1:0]                            seq_ks_cmd;
  logic                                           seq_ks_cmd_avail;

  logic [TOTAL_BATCH_NB-1:0]                      inc_ksk_wr_ptr;
  logic [TOTAL_BATCH_NB-1:0]                      outp_ks_loop_done_mh;

  logic [LBY-1:0]                                 ctrl_blram_rd_en;
  logic [LBY-1:0][BLWE_RAM_ADD_W-1:0]             ctrl_blram_rd_add;
  logic [LBY-1:0][KS_DECOMP_W-1:0]                blram_ctrl_rd_data;
  logic [LBY-1:0]                                 blram_ctrl_rd_data_avail;

  logic [KS_IF_SUBW_NB-1:0]                       blwe_ram_wr_en;
  logic [KS_IF_SUBW_NB-1:0][PID_W-1:0]            blwe_ram_wr_pid;
  logic [KS_IF_SUBW_NB-1:0][KS_IF_COEF_NB-1:0][MOD_Q_W-1:0] blwe_ram_wr_data;
  logic [KS_IF_SUBW_NB-1:0]                       blwe_ram_wr_pbs_last;
  logic [KS_IF_SUBW_NB-1:0]                       blwe_ram_wr_batch_last;

  logic [TOTAL_BATCH_NB-1:0]                      blram_bfifo_wr_en;
  logic [PID_W-1:0]                               blram_bfifo_wr_pid;
  logic [OP_W-1:0]                                blram_bfifo_wr_data;

  logic [LBY-1:0][LBZ-1:0][KS_B_W-1:0]            ctrl_mult_data;
  logic [LBY-1:0][LBZ-1:0]                        ctrl_mult_sign;
  logic [LBY-1:0]                                 ctrl_mult_avail;

  logic                                           ctrl_mult_last_eol;
  logic                                           ctrl_mult_last_eoy;
  logic                                           ctrl_mult_last_last_iter;
  logic [TOTAL_BATCH_NB_W-1:0]                    ctrl_mult_last_batch_id;

  logic [KS_BATCH_CMD_W-1:0]                      batch_cmd;
  logic                                           batch_cmd_avail; // pulse

  logic [KS_CMD_W-1:0]                            ctrl_res_cmd;
  logic                                           ctrl_res_cmd_vld;
  logic                                           ctrl_res_cmd_rdy;

  logic [KS_CMD_W-1:0]                            ctrl_bmap_cmd;
  logic                                           ctrl_bmap_cmd_vld;
  logic                                           ctrl_bmap_cmd_rdy;

// ============================================================================================== --
// Design under test instance
// ============================================================================================== --
  pep_ks_control #(
    .OP_W          (OP_W          ),
    .BLWE_RAM_DEPTH(BLWE_RAM_DEPTH),
    .DATA_LATENCY  (DATA_LATENCY  ),
    .ALMOST_DONE_BLINE_ID (ALMOST_DONE_BLINE_ID)
  ) pep_ks_control (
    .clk                       (clk    ),
    .s_rst_n                   (s_rst_n),

    .ks_seq_cmd_enquiry        (ks_seq_cmd_enquiry),
    .seq_ks_cmd                (seq_ks_cmd        ),
    .seq_ks_cmd_avail          (seq_ks_cmd_avail  ),

    .ctrl_res_cmd              (ctrl_res_cmd),
    .ctrl_res_cmd_vld          (ctrl_res_cmd_vld),
    .ctrl_res_cmd_rdy          (ctrl_res_cmd_rdy),

    .ctrl_bmap_cmd             (ctrl_bmap_cmd),
    .ctrl_bmap_cmd_vld         (ctrl_bmap_cmd_vld),
    .ctrl_bmap_cmd_rdy         (ctrl_bmap_cmd_rdy),

    .inc_ksk_wr_ptr            (inc_ksk_wr_ptr),
    .outp_ks_loop_done_mh      (outp_ks_loop_done_mh),

    .ctrl_blram_rd_en          (ctrl_blram_rd_en),
    .ctrl_blram_rd_add         (ctrl_blram_rd_add),
    .blram_ctrl_rd_data        (blram_ctrl_rd_data),
    .blram_ctrl_rd_data_avail  (blram_ctrl_rd_data_avail),

    .ctrl_mult_data            (ctrl_mult_data),
    .ctrl_mult_sign            (ctrl_mult_sign),
    .ctrl_mult_avail           (ctrl_mult_avail),

    .ctrl_mult_last_eol        (ctrl_mult_last_eol),
    .ctrl_mult_last_eoy        (ctrl_mult_last_eoy),
    .ctrl_mult_last_last_iter  (ctrl_mult_last_last_iter),
    .ctrl_mult_last_batch_id   (ctrl_mult_last_batch_id),

    .batch_cmd                 (batch_cmd),
    .batch_cmd_avail           (batch_cmd_avail),

    .reset_cache               ('0) // Not tested here
  );

  pep_ks_blwe_ram
  #(
    .OP_W             (OP_W),
    .SUBW_NB          (KS_IF_SUBW_NB),
    .SUBW_COEF_NB     (KS_IF_COEF_NB),
    .RAM_LATENCY      (RAM_LATENCY),
    .BLWE_RAM_DEPTH   (BLWE_RAM_DEPTH)
  ) pep_ks_blwe_ram (
    .clk                      (clk),
    .s_rst_n                  (s_rst_n),

    .blwe_ram_wr_en           (blwe_ram_wr_en),
    .blwe_ram_wr_batch_id     ('0),/*UNUSED*/
    .blwe_ram_wr_pid          (blwe_ram_wr_pid),
    .blwe_ram_wr_data         (blwe_ram_wr_data),
    .blwe_ram_wr_pbs_last     (blwe_ram_wr_pbs_last),
    .blwe_ram_wr_batch_last   (blwe_ram_wr_batch_last),

    .ctrl_blram_rd_en         (ctrl_blram_rd_en),
    .ctrl_blram_rd_add        (ctrl_blram_rd_add),
    .blram_ctrl_rd_data       (blram_ctrl_rd_data),
    .blram_ctrl_rd_data_avail (blram_ctrl_rd_data_avail),

    .blram_bfifo_wr_en        (blram_bfifo_wr_en),
    .blram_bfifo_wr_pid       (blram_bfifo_wr_pid),
    .blram_bfifo_wr_data      (blram_bfifo_wr_data)
  );


// ============================================================================================== --
// Scenario
// ============================================================================================== --
// ---------------------------------------------------------------------------------------------- --
// Data
// ---------------------------------------------------------------------------------------------- --
  logic [TOTAL_PBS_NB-1:0][KS_BLOCK_LINE_NB:0][LBY-1:0][MOD_Q_W-1:0] in_data;
  logic [TOTAL_PBS_NB-1:0][KS_BLOCK_LINE_NB-1:0][LBY-1:0][KS_LG_NB-1:0][LBZ-1:0][KS_B_W:0] out_data;
  logic [TOTAL_PBS_NB-1:0][OP_W-1:0] out_body;

  initial begin
      for (int p=0; p<TOTAL_PBS_NB; p=p+1) begin
        logic [MOD_Q_W-1:0] d_tmp;
        logic [KS_L-1:0][KS_B_W:0] d_tmp2;
        for (int l=0; l<KS_BLOCK_LINE_NB; l=l+1) begin
          for (int y=0; y<LBY; y=y+1) begin
            in_data[p][l][y] = {$urandom,$urandom};
            if ((l == KS_BLOCK_LINE_NB-1) && (BLWE_K%LBY > 0) && (y >= BLWE_K%LBY)) begin
              out_data[p][l][y] = '0;
            end
            else begin
              d_tmp2 = decompose(in_data[p][l][y]);
              out_data[p][l][y] = d_tmp2; // extend with 0
              //$display("pbs_id=%0d line=%0d y=%0d in_data=0x%x out_data=0x%0x",p,l,y,in_data[p][l][y], out_data[p][l][y]);
            end
          end // for y
        end // for l
        //== body
        if (BLWE_K%LBY == 0) begin
          in_data[p][KS_BLOCK_LINE_NB][0] = {$urandom,$urandom}; // Add body
          d_tmp = in_data[p][KS_BLOCK_LINE_NB][0];
          for (int y=1; y<LBY; y=y+1)
            in_data[p][KS_BLOCK_LINE_NB][y] = '1;// dummy values
        end
        else
          d_tmp = in_data[p][KS_BLOCK_LINE_NB-1][BLWE_K%LBY];
        if (OP_W < MOD_Q_W)
          // mod switch
          out_body[p] = d_tmp[MOD_Q_W-1-:OP_W] + d_tmp[MOD_Q_W-1-OP_W];
        else
          out_body[p] = d_tmp;
      end // for p
  end
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
  logic [KS_IF_SUBW_NB-1:0][KS_IF_COEF_NB-1:0][MOD_Q_W-1:0]    fb_wr_in_data;
  logic [KS_IF_SUBW_NB-1:0][KS_IF_COEF_NB*MOD_Q_W+1+1+PID_W-1:0] fb_wr_in_elt;

  logic [KS_IF_SUBW_NB-1:0]                                    fb_out_wr_vld;
  logic [KS_IF_SUBW_NB-1:0]                                    fb_out_wr_rdy;
  logic [KS_IF_SUBW_NB-1:0]                                    fb_out_wr_pbs_last;
  logic [KS_IF_SUBW_NB-1:0]                                    fb_out_wr_pbs_penult;
  logic [KS_IF_SUBW_NB-1:0][PID_W-1:0]                         fb_out_wr_pid;
  logic [KS_IF_SUBW_NB-1:0][KS_IF_COEF_NB-1:0][MOD_Q_W-1:0]    fb_wr_out_data;
  logic [KS_IF_SUBW_NB-1:0][KS_IF_COEF_NB*MOD_Q_W+1+1+PID_W-1:0] fb_wr_out_elt;

  always_comb
    for (int j=0; j<KS_IF_SUBW_NB; j=j+1)
      for (int i=0; i<KS_IF_COEF_NB; i=i+1) begin
        integer k;
        k = (fb_pbs_subw*BLWE_SUBW_COEF_NB + j*KS_IF_COEF_NB + i);
        fb_wr_in_data[j][i] = in_data[fb_pbs_id][k/LBY][k%LBY];
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

  assign blwe_ram_wr_data       = fb_wr_out_data;
  assign blwe_ram_wr_pid        = fb_out_wr_pid;

  always_comb begin
    blwe_ram_wr_pbs_last[0]   = fb_out_wr_pbs_last[0];
    blwe_ram_wr_batch_last[0] = fb_out_wr_pbs_last[0];
    blwe_ram_wr_en[0]         = fb_out_wr_vld[0];
    for (int j=1; j<KS_IF_SUBW_NB; j=j+1) begin
      blwe_ram_wr_pbs_last[j]   = fb_out_wr_pbs_penult[j];
      blwe_ram_wr_batch_last[j] = fb_out_wr_pbs_penult[j];
      blwe_ram_wr_en[j]         = fb_out_wr_vld[j] & ~fb_out_wr_pbs_last[j];
    end
  end

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

  assign proc_wp_tmp        = (proc_rp + proc_ct_nb) >= TOTAL_PBS_NB ? proc_ct_nb + proc_rp - TOTAL_PBS_NB : proc_rp + proc_ct_nb;
  assign proc_wp[PID_W]     = (proc_rp + proc_ct_nb) >= TOTAL_PBS_NB;
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


  // TOREVIEW : shortcut
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

  // result_format and body_map
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      ctrl_res_cmd_rdy  <= 1'b0;
      ctrl_bmap_cmd_rdy <= 1'b0;
    end
    else begin
      ctrl_res_cmd_rdy  <= $urandom();
      ctrl_bmap_cmd_rdy <= $urandom();
    end


// ============================================================================================== --
// Check
// ============================================================================================== --
// Gather out data
  logic [LBZ-1:0][KS_B_W-1:0] ctrl_out_data_q[LBY-2:0][$];
  logic [LBZ-1:0]             ctrl_out_sign_q[LBY-2:0][$];

  always_ff@(posedge clk)
    for (int i=0; i<LBY-1; i=i+1)
      if (ctrl_mult_avail[i]) begin
        ctrl_out_data_q[i].push_back(ctrl_mult_data[i]);
        ctrl_out_sign_q[i].push_back(ctrl_mult_sign[i]);
      end

// Output counter
  integer out_ct_cnt;
  integer out_lg    ;
  integer out_col   ;
  integer out_line  ;

  // Use the same process to handle the out counters, to avoid race condition on cmd_q
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      error_mask <= 1'b0;
      error_info <= 1'b0;

      out_lg     <= '0;
      out_ct_cnt <= '0;
      out_col    <= '0;
      out_line   <= '0;

    end
    else begin
      if (ctrl_mult_avail[LBY-1]) begin
        var[LBY-1:0][LBZ-1:0][KS_B_W-1:0] d;
        var[LBY-1:0][LBZ-1:0]             s;
        int out_pid;
        int ct_nb;
        int rp;
        var last_lg;
        var last_ct_cnt;
        var last_line;
        var last_col;

        rp          = cmd_q[0].rp;
        ct_nb       = pt_elt_nb(cmd_q[0].wp, cmd_q[0].rp);
        last_lg     = out_lg == KS_LG_NB-1;
        last_ct_cnt = out_ct_cnt == ct_nb-1;
        last_line   = out_line == KS_BLOCK_LINE_NB-1;
        last_col    = out_col == KS_BLOCK_COL_NB-1;
        out_pid     = (rp + out_ct_cnt) % TOTAL_PBS_NB;

        // Counters
        out_lg     <= last_lg ? '0 : out_lg + 1;
        out_ct_cnt <= last_lg ? last_ct_cnt ? '0 : out_ct_cnt + 1 : out_ct_cnt;
        out_line   <= last_lg && last_ct_cnt ? last_line ? '0 : out_line+1 : out_line;
        out_col    <= last_lg && last_ct_cnt && last_line ? last_col ? '0 : out_col+1 : out_col;

        // Check
        d[LBY-1] = ctrl_mult_data[LBY-1];
        s[LBY-1] = ctrl_mult_sign[LBY-1];
        for (int i=0; i<LBY-1; i=i+1) begin
          d[i] = ctrl_out_data_q[i].pop_front();
          s[i] = ctrl_out_sign_q[i].pop_front();
        end
        //check
        for (int i=0; i<LBY; i=i+1) begin
          for (int j=0; j<LBZ; j=j+1) begin
            assert({s[i][j], d[i][j]} == out_data[out_pid][out_line][i][out_lg][j])
            else begin
              $display("%t > ERROR: Data mismatches pbs_id=%0d line=%0d y=%0d z=%0d col=%0d exp=0x%0x seen=0x%0x",
                      $time, out_pid, out_line, i, j, out_col,
                      out_data[out_pid][out_line][i][out_lg][j],
                      {s[i][j], d[i][j]});
              error_mask <= 1'b1;
            end
          end // for j
        end // for i

        assert(ctrl_mult_last_eol == (out_lg == KS_LG_NB-1))
        else begin
          $display("%t > ERROR: eol mismatches pbs_id=%0d line=%0d col=%0d exp=%0b seen=%0b",
                      $time, out_pid, out_line, out_col,
                      out_lg == KS_LG_NB-1,
                      ctrl_mult_last_eol);
          error_info <= 1'b1;
        end

        assert(ctrl_mult_last_eoy == (out_ct_cnt == ct_nb-1))
        else begin
          $display("%t > ERROR: eoy mismatches pbs_id=%0d line=%0d col=%0d ct_nb=%0d exp=%0b seen=%0b",
                      $time, out_pid, out_line, out_col,ct_nb,
                      (out_ct_cnt == ct_nb-1),
                      ctrl_mult_last_eoy);
          error_info <= 1'b1;
        end

        assert(ctrl_mult_last_last_iter == (out_line == KS_BLOCK_LINE_NB-1))
        else begin
          $display("%t > ERROR: last_iter mismatches pbs_id=%0d line=%0d col=%0d exp=%0b seen=%0b",
                      $time, out_pid, out_line, out_col,
                      out_line == KS_BLOCK_LINE_NB-1,
                      ctrl_mult_last_last_iter);
          error_info <= 1'b1;
        end

        if (ctrl_mult_last_eol && ctrl_mult_last_eoy && ctrl_mult_last_last_iter) begin
          cmd_q.pop_front();
        end
      end // if ctrl_mult_avail
    end

  integer out_done_cnt [TOTAL_BATCH_NB-1:0];
  integer out_cnt      [TOTAL_BATCH_NB-1:0];
  logic [TOTAL_BATCH_NB-1:0] out_done;
  logic [TOTAL_BATCH_NB-1:0] send_ofifo_inc_on_last_bcol;


  always_comb
    for (int i=0; i<TOTAL_BATCH_NB; i=i+1) begin
      out_done[i] = ctrl_mult_avail[LBY-1]
                    & (ctrl_mult_last_batch_id == i)
                    & ctrl_mult_last_eol
                    & ctrl_mult_last_eoy
                    & ctrl_mult_last_last_iter;
      send_ofifo_inc_on_last_bcol[i] = ((out_cnt[i]%KS_BLOCK_COL_NB) < KS_BLOCK_COL_NB - 1) || SEND_OFIFO_INC_ON_LAST_BCOL;
    end

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      out_done_cnt <= '{TOTAL_BATCH_NB{32'd0}};
      out_cnt      <= '{TOTAL_BATCH_NB{32'd0}};
    end
    else begin
      for (int i=0; i<TOTAL_BATCH_NB; i=i+1) begin
        out_done_cnt[i] <= out_done[i] && !outp_ks_loop_done_mh[i] ? out_done_cnt[i] + send_ofifo_inc_on_last_bcol[i]:
                           !out_done[i] && outp_ks_loop_done_mh[i] ? out_done_cnt[i] - 1:
                           out_done[i] && outp_ks_loop_done_mh[i]  ? out_done_cnt[i] + send_ofifo_inc_on_last_bcol[i] - 1: out_done_cnt[i];
        out_cnt[i]      <= out_done[i] ? out_cnt[i] + 1 : out_cnt[i];
      end
    end

  logic [TOTAL_BATCH_NB-1:0] send_out_done;
  always_ff @(posedge clk)
    for (int i=0; i<TOTAL_BATCH_NB; i=i+1)
      send_out_done[i] <= $urandom_range(1, 64) == 1 ? 1'b1 : 1'b0;

  always_comb
    for (int i=0; i<TOTAL_BATCH_NB; i=i+1)
      outp_ks_loop_done_mh[i] = send_out_done[i] & (out_done_cnt[i] > 0);


  // Check body
  always_ff @(posedge clk)
    if (!s_rst_n)
      error_body <= 1'b0;
    else begin
      if (blram_bfifo_wr_en)
        assert(out_body[blram_bfifo_wr_pid] == blram_bfifo_wr_data)
        else begin
          $display("%t > ERROR: Mismatch body exp=0x%0x seen=0x%0x", $time, out_body[blram_bfifo_wr_pid], blram_bfifo_wr_data);
          error_body <= 1'b1;
        end
    end

// ============================================================================================== --
// Control
// ============================================================================================== --
  always_ff @(posedge clk) begin
    if (!s_rst_n) start <= 1'b0;
    else          start <= 1'b1;
  end

  integer proc_cmd_cnt;
  always_ff @(posedge clk)
    if (!s_rst_n) proc_cmd_cnt <= '0;
    else          proc_cmd_cnt <= seq_ks_cmd_avail ? proc_cmd_cnt + 1 : proc_cmd_cnt;

  assign process_done = proc_cmd_cnt >= SAMPLE_CMD_NB;

  initial begin
    end_of_test = 0;
    wait(s_rst_n);
    wait(st_fill_blram);
    $display("%t > INFO: Fill BLRAM done.", $time);
    wait(st_process);
    $display("%t > INFO: Process done.", $time);
    wait(st_done);
    @(posedge clk);
    wait(ks_seq_cmd_enquiry_vld);
    @(posedge clk);
    end_of_test = 1;
  end

endmodule
