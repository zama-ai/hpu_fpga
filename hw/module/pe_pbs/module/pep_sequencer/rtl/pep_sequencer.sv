// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module tracks the ciphertext process.
// It deals with the start of the CT loading (GLWE and BLWE), and the process start (KS and PBS).
// It builds a map, that indicates which pid has to be processed.
// ==============================================================================================

module pep_sequencer
  import top_common_param_pkg::*;
  import param_tfhe_pkg::*;
  import pep_ks_common_param_pkg::*;
  import hpu_common_instruction_pkg::*;
  import pep_common_param_pkg::*;
#(
  parameter int INST_FIFO_DEPTH   = 8 // Should be >= 2
)
(
  input  logic                        clk,        // clock
  input  logic                        s_rst_n,    // synchronous reset

  input  logic                        use_bpip,   // quasi static
  input  logic                        use_bpip_opportunism,// quasi static
  input  logic [TIMEOUT_CNT_W-1:0]    bpip_timeout, // quasi static

  input  logic [PE_INST_W-1:0]        inst,
  input  logic                        inst_vld,
  output logic                        inst_rdy,

  output logic                        inst_ack,
  output logic [LWE_K_W-1:0]          inst_ack_br_loop,
  output logic                        inst_load_blwe_ack,

  // To Loading units
  output logic [LOAD_GLWE_CMD_W-1:0]  seq_ldg_cmd,
  output logic                        seq_ldg_vld,
  input  logic                        seq_ldg_rdy,

  output logic [LOAD_BLWE_CMD_W-1:0]  seq_ldb_cmd,
  output logic                        seq_ldb_vld,
  input  logic                        seq_ldb_rdy,

  // From loading units
  input  logic                        ldg_seq_done,
  input  logic                        ldb_seq_done,

  // Keyswitch command
  input  logic                        ks_seq_cmd_enquiry,
  output logic [KS_CMD_W-1:0]         seq_ks_cmd,
  output logic                        seq_ks_cmd_avail,

  // Keyswitch result
  input  logic [KS_RESULT_W-1:0]      ks_seq_result,
  input  logic                        ks_seq_result_vld,
  output logic                        ks_seq_result_rdy,

  // PBS command
  input  logic                        pbs_seq_cmd_enquiry,
  output logic [PBS_CMD_W-1:0]        seq_pbs_cmd,
  output logic                        seq_pbs_cmd_avail,

  // From sample extract
  input  logic                        sxt_seq_done,
  input  logic [PID_W-1:0]            sxt_seq_done_pid,

  // To bsk_if and ksk_if
  output logic                        bsk_if_batch_start_1h,
  output logic                        ksk_if_batch_start_1h,

  // reset cache
  input  logic                        reset_cache,
  output logic                        reset_ks,

  // Wr correction to body RAM
  output logic                        seq_boram_corr_wr_en,
  output logic [KS_CORR_W-1:0]        seq_boram_corr_data,
  output logic [PID_W-1:0]            seq_boram_corr_pid,

  // Error
  output pep_seq_error_t              seq_error,

  // Info for register_if
  output pep_seq_info_t               seq_rif_info,
  output pep_seq_counter_inc_t        seq_rif_counter_inc
);

// ============================================================================================== //
// localparam
// ============================================================================================== //
  localparam int KS_ENQ_FIFO_DEPTH  = 1;
  localparam int PBS_ENQ_FIFO_DEPTH = 1;

  localparam int LINE_NB            = TOTAL_PBS_NB / GRAM_NB;
  localparam int LINE_NB_EXT        = LINE_NB + RANK_NB;
  localparam int RANK_LINE_NB       = ((LINE_NB_EXT + RANK_NB -1)/ RANK_NB);
  localparam int TOTAL_PBS_NB_EXT   = RANK_LINE_NB * RANK_NB * GRAM_NB;
  localparam int TOTAL_PBS_NB_DIFF  = TOTAL_PBS_NB_EXT - TOTAL_PBS_NB;

  localparam int RANK_OFS_INC       = (TOTAL_PBS_NB/GRAM_NB) % RANK_NB;

  localparam int CORR_BUF_DEPTH     = 2; // 1 free location + 1 waiting.

// Check
  generate
    if (GRAM_NB * RANK_NB != BATCH_PBS_NB) begin : __UNSUPPORTED_BATCH_PBS_NB
      $fatal(1,"> ERROR: We should have : GRAM_NB (%0d) * RANK_NB (%0d) == BATCH_PBS_NB (%0d)",GRAM_NB,RANK_NB,TOTAL_PBS_NB);
    end
    if (TOTAL_PBS_NB % GRAM_NB != 0) begin : __UNSUPPORTED_TOTAL_PBS_NB
      $fatal(1,"> ERROR: GRAM_NB (%0d) should divide TOTAL_PBS_NB (%0d)",GRAM_NB,TOTAL_PBS_NB);
    end
    if (TOTAL_PBS_NB <= BATCH_PBS_NB) begin : __UNSUPPORTED_TOTAL_PBS_NB_2
      $fatal(1,"> ERROR: TOTAL_PBS_NB (%0d) should be greater than BATCH_PBS_NB (%0d)",TOTAL_PBS_NB,BATCH_PBS_NB);
    end
    if (LWE_K < 2*LBX) begin:  __UNSUPPORTED_LWE_K_LBX
      $fatal(1,"> ERROR: pep_sequencer only supports LWE_K (%0d) >= 2*LBX (%0d), because of the br_loop_avail tag.", LWE_K, LBX);
    end
  endgenerate

// ============================================================================================== //
// Type
// ============================================================================================== //
  // br_loop field has several significations according to status
  // status == PID_LD_DONE => indicates the ks_br_loop from which the ct is ready for the PBS process
  // status == PID_PBS     => indicates current iteration 0 : first, LWE-1 : last
  typedef struct packed {
    logic                      avail;
    logic                      br_loop_avail;
    logic                      force_pbs;
    logic [LWE_COEF_W-1:0]     lwe;
    logic [KS_CORR_W-1:0]      corr;
    logic [RID_W-1:0]          dst_rid;
    logic [LOG_LUT_NB_W-1:0]   log_lut_nb;
    logic                      br_loop_c; // start loop parity
    logic [LWE_K_W-1:0]        br_loop; // start loop index
    pid_t                      pid;
  } ct_info_t;

  localparam int CT_INFO_W = $bits(ct_info_t);

  typedef struct packed {
    logic                      avail;
    logic [KS_CORR_W-1:0]      corr;
    logic [PID_W-1:0]          pid;
  } corr_elt_t;

  localparam int CORR_ELT_W = $bits(corr_elt_t);

// ============================================================================================== //
// Function
// ============================================================================================== //
  // Increment pid pointer
  function [PID_W:0] pt_inc_1 (input [PID_W:0] pt);
    pt_inc_1[PID_W-1:0] = pt[PID_W-1:0] == TOTAL_PBS_NB-1 ? '0 : pt[PID_W-1:0] + 1;
    pt_inc_1[PID_W]     = pt[PID_W-1:0] == TOTAL_PBS_NB-1 ? ~pt[PID_W] : pt[PID_W];
  endfunction

  function [PID_W:0] pt_dec_1 (input [PID_W:0] pt);
    pt_dec_1[PID_W-1:0] = pt[PID_W-1:0] == '0 ? TOTAL_PBS_NB-1 : pt[PID_W-1:0] - 1;
    pt_dec_1[PID_W]     = pt[PID_W-1:0] == '0 ? ~pt[PID_W] : pt[PID_W];
  endfunction

  function pt_inc_any_wrap (input [PID_W:0] pt, input [PID_W-1:0] val);
    logic [PID_W:0] tmp;
    tmp  = pt[PID_W-1:0] + val;
    pt_inc_any_wrap = tmp > TOTAL_PBS_NB-1;
  endfunction

  function [PID_W:0] pt_inc_any (input [PID_W:0] pt, input [PID_W-1:0] val);
    logic [PID_W:0] tmp;
    logic           wrap; // result of pt_inc_any_wrap
    tmp  = pt[PID_W-1:0] + val;
    wrap = tmp > TOTAL_PBS_NB-1;
    pt_inc_any[PID_W-1:0] = wrap ? tmp - TOTAL_PBS_NB : tmp;
    pt_inc_any[PID_W]     = wrap ? ~pt[PID_W] : pt[PID_W];
  endfunction

  // Compare 2 pointers
  function logic pt_full (input [PID_W:0] wp, input [PID_W:0] rp);
    pt_full = (rp[PID_W-1:0] == wp[PID_W-1:0]) & (rp[PID_W] != wp[PID_W]);
  endfunction

  function logic pt_empty (input [PID_W:0] wp, input [PID_W:0] rp);
    pt_empty = rp == wp;
  endfunction

// ============================================================================================== //
// Input pipe
// ============================================================================================== //
  logic ldg_done; // GLWE load is done
  logic ldb_done; // BLWE load is done
  logic sxt_done; // PBS process is over. Data have been extracted by the sample extract. Invalidate the ct_info

  logic [TOTAL_PBS_NB-1:0] sxt_done_pid_1h;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      ldg_done    <= 1'b0;
      ldb_done    <= 1'b0;
      sxt_done    <= 1'b0;
    end
    else begin
      ldg_done    <= ldg_seq_done;
      ldb_done    <= ldb_seq_done;
      sxt_done    <= sxt_seq_done;
    end

  always_ff @(posedge clk)
    sxt_done_pid_1h <= 1 << sxt_seq_done_pid;

// ============================================================================================== //
// Reset cache part1
// ============================================================================================== //
  logic reset_loop;
  logic reset_clear; // used to reset ks and br loop counters
  logic reset_clearD;
  logic reset_clear_busy;

  assign reset_clearD = reset_loop & ~reset_clear_busy;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      reset_loop  <= 1'b0;
      reset_clear <= 1'b0;
      reset_ks    <= 1'b0;
    end
    else begin
      reset_loop  <= reset_cache;
      reset_clear <= reset_clearD;
      reset_ks    <= reset_clear;
    end

// ============================================================================================== //
// Instruction FIFO
// ============================================================================================== //
  pep_inst_t s0_inst;
  logic      s0_inst_vld;
  logic      s0_inst_rdy;

  fifo_reg #(
    .WIDTH       (PE_INST_W),
    .DEPTH       (INST_FIFO_DEPTH),
    .LAT_PIPE_MH ({1'b1, 1'b1})
  ) inst_fifo_reg (
    .clk      (clk),
    .s_rst_n  (s_rst_n),

    .in_data  (inst),
    .in_vld   (inst_vld),
    .in_rdy   (inst_rdy),

    .out_data (s0_inst),
    .out_vld  (s0_inst_vld),
    .out_rdy  (s0_inst_rdy)
  );

// ============================================================================================== //
// Enquiry FIFO
// ============================================================================================== //
  logic ks_cmd_enq_vld;
  logic ks_cmd_enq_rdy;
  logic pbs_cmd_enq_vld;
  logic pbs_cmd_enq_rdy;

  logic ks_cmd_enq_error;
  logic pbs_cmd_enq_error;

  common_lib_pulse_to_rdy_vld #(
    .FIFO_DEPTH (KS_ENQ_FIFO_DEPTH)
  ) ks_common_lib_pulse_to_rdy_vld (
    .clk     (clk),
    .s_rst_n (s_rst_n),
    .in_pulse(ks_seq_cmd_enquiry),
    .out_vld (ks_cmd_enq_vld),
    .out_rdy (ks_cmd_enq_rdy),
    .error   (ks_cmd_enq_error)
  );

  common_lib_pulse_to_rdy_vld #(
    .FIFO_DEPTH (PBS_ENQ_FIFO_DEPTH)
  ) pbs_common_lib_pulse_to_rdy_vld (
    .clk     (clk),
    .s_rst_n (s_rst_n),
    .in_pulse(pbs_seq_cmd_enquiry),
    .out_vld (pbs_cmd_enq_vld),
    .out_rdy (pbs_cmd_enq_rdy),
    .error   (pbs_cmd_enq_error)
  );

// ============================================================================================== //
// KS result FIFO
// ============================================================================================== //
  ks_result_t ks_res;
  logic       ks_res_vld;
  logic       ks_res_rdy;

  fifo_element #(
    .WIDTH          (KS_RESULT_W),
    .DEPTH          (1),
    .TYPE_ARRAY     (4'h3),
    .DO_RESET_DATA  (1'b0),
    .RESET_DATA_VAL (0)
  ) ks_res_fifo_element (
    .clk      (clk),
    .s_rst_n  (s_rst_n),

    .in_data  (ks_seq_result),
    .in_vld   (ks_seq_result_vld),
    .in_rdy   (ks_seq_result_rdy),

    .out_data (ks_res),
    .out_vld  (ks_res_vld),
    .out_rdy  (ks_res_rdy)
  );

// ============================================================================================== //
// Pointers
// ============================================================================================== //
  // The ciphertexts are processed in order. Therefore it is very convenient to track
  // the progress in the processing path with pointers.
  // Here we use several ones.
  // They are listed here for clarity, to distinguish them. They are affected later in the code.

  // pid pointers
  // General occupancy
  // Indicates if the ct location is occupied of not.
  pointer_t              pool_rp;
  pointer_t              pool_wp;

  // ldg / ldb pointers
  // Indicates the next GLWE/BLWE that will be loaded in local RAM.
  pointer_t              ldg_pt;
  pointer_t              ldb_pt;

  // Indicates the position after a force PBS position that
  // is already loaded by ldb, and not processed by the KS.
  // Note that if there is no force PBS, this pointer is equal to
  // ldb_pt.
  pointer_t              pbs_force_pt;

  // ks_in pointers
  // List the ct that have to be processed by the KS
  pointer_t              ks_in_wp;
  pointer_t              ks_in_rp;
  logic [LWE_K_P1_W-1:0] ks_in_loop;
  logic                  ks_in_loop_c; // Used in simulation to avoid wrapping.

  // ks_out pointers
  // List the ct that are concerned by KS result
  pointer_t              ks_out_wp;
  pointer_t              ks_out_rp;
  logic [LWE_K_P1_W:0]   ks_out_loop; // Should be in [0..LWE_K-1], since the body is not sent to the sequencer

  // pbs_in pointers
  // List the ct that have to be processed by the PBS
  pointer_t              pbs_in_rp;
  pointer_t              pbs_in_wp;
  logic [LWE_K_W-1:0]    pbs_in_loop;
  logic                  pbs_in_loop_c; // Used in simulation to avoid wrapping.
  logic [RANK_W-1:0]     pbs_in_rp_rank_ofs;

  logic                  loop_full; // Necessary in simulation to avoid wrapping, because LWE_K is too small.
  logic                  loop_full_tmp;
  logic [LWE_K_P1_W:0]   ks_in_loop_range_max;
  // If KS has to process only the body, do not consider it as full.
  logic                  ks_in_body_only;

  assign ks_in_body_only      = ks_in_loop == LWE_K;
  assign ks_in_loop_range_max = ks_in_loop + LBX;
  assign loop_full_tmp        = ((pbs_in_loop < ks_in_loop_range_max)) & (ks_in_loop_c != pbs_in_loop_c);
  assign loop_full            = ~ks_in_body_only & loop_full_tmp;

// pragma translate_off
  logic _loop_full_dly;
  logic _loop_full_tmp_dly;
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      _loop_full_dly     <= 1'b0;
      _loop_full_tmp_dly <= 1'b0;
    end
    else begin
      _loop_full_dly     <= loop_full;
      _loop_full_tmp_dly <= loop_full_tmp;
      if (loop_full && !_loop_full_dly)
        $display("%t > INFO: loop_full seen. Stops ks_in to avoid overflow for the simulation (ks_in_loop=%0d pbs_in_loop=%0d). (Note this won't occur in real because LWE_K is big enough.)", $time,ks_in_loop, pbs_in_loop);
      if (loop_full_tmp && !_loop_full_tmp_dly && !loop_full)
        $display("%t > INFO: loop_full seen. Processing body. No stop ks_in (ks_in_loop=%0d pbs_in_loop=%0d).", $time,ks_in_loop, pbs_in_loop);
    end
// pragma translate_on

// ============================================================================================== //
// Ciphertext pool
// ============================================================================================== //
  ct_info_t [TOTAL_PBS_NB-1:0] ct_pool;
  ct_info_t [TOTAL_PBS_NB-1:0] ct_poolD;

  always_ff @(posedge clk)
    if (!s_rst_n)
      for (int i=0; i<TOTAL_PBS_NB; i=i+1) begin
        ct_info_t c;
        c       = 'x;
        c.pid   = '{i, i / GRAM_NB, i % GRAM_NB};
        c.avail = 1'b0;
        ct_pool[i] <= c;
      end
    else
      ct_pool <= ct_poolD;

  // Rename
  logic [TOTAL_PBS_NB-1:0] ct_pool_force_pbs;
  logic [TOTAL_PBS_NB-1:0] ct_pool_avail;

  always_comb
    for (int i=0; i<TOTAL_PBS_NB; i=i+1) begin
      ct_pool_force_pbs[i] = ct_pool[i].force_pbs;
      ct_pool_avail[i]     = ct_pool[i].avail;
    end

// ============================================================================================== //
// Pool pointers
// ============================================================================================== //
// Keep track of the global occupancy of ct_pool
// The ciphertexts are processed in their arriving order.
// Each ciphertext is given a pid (PBS ID).
  pointer_t pool_rpD;
  pointer_t pool_wpD;

  logic     pool_empty;
  logic     pool_full;

  logic     s0_load_ct;
  logic     s0_ct_done;
  logic     [LWE_K_W-1:0] s0_ct_done_br_loop;

  assign pool_empty = pt_empty(pool_wp, pool_rp);
  assign pool_full  = pt_full(pool_wp, pool_rp);

  assign pool_rpD   = s0_ct_done ? pt_inc_1(pool_rp) : pool_rp;
  assign pool_wpD   = s0_load_ct ? pt_inc_1(pool_wp) : pool_wp;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      pool_rp   <= '0;
      pool_wp   <= '0;
      inst_ack           <= 1'b0;
      inst_load_blwe_ack <= 1'b0;
    end
    else begin
      pool_rp   <= pool_rpD ;
      pool_wp   <= pool_wpD ;
      inst_ack           <= s0_ct_done;
      inst_load_blwe_ack <= ldb_done;
    end

  always_ff @(posedge clk)
    inst_ack_br_loop <= s0_ct_done_br_loop;

// ============================================================================================== //
// Send loading requests
// ============================================================================================== //
  load_glwe_cmd_t s0_ldg_cmd;
  logic           s0_ldg_cmd_vld;
  logic           s0_ldg_cmd_rdy;

  load_blwe_cmd_t s0_ldb_cmd;
  logic           s0_ldb_cmd_vld;
  logic           s0_ldb_cmd_rdy;

  logic           s0_load_ct_tmp;

  assign s0_load_ct_tmp = s0_inst_vld & ~pool_full;
  assign s0_load_ct     = s0_load_ct_tmp & s0_ldg_cmd_rdy & s0_ldb_cmd_rdy;
  assign s0_ldg_cmd_vld = s0_load_ct_tmp & s0_ldb_cmd_rdy;
  assign s0_ldb_cmd_vld = s0_load_ct_tmp & s0_ldg_cmd_rdy;
  assign s0_inst_rdy    = ~pool_full & s0_ldg_cmd_rdy & s0_ldb_cmd_rdy;

  assign s0_ldg_cmd.gid      = s0_inst.gid;
  assign s0_ldg_cmd.pid.pid  = pool_wp.pt;
  assign s0_ldg_cmd.pid.grof = pool_wp.pt / GRAM_NB;
  assign s0_ldg_cmd.pid.grid = pool_wp.pt % GRAM_NB;

  assign s0_ldb_cmd.src_rid = s0_inst.src_rid;
  assign s0_ldb_cmd.pid     = pool_wp.pt;

  // load units request FIFO elements
  fifo_element #(
    .WIDTH          (LOAD_GLWE_CMD_W),
    .DEPTH          (1),
    .TYPE_ARRAY     (4'h3),
    .DO_RESET_DATA  (1'b0),
    .RESET_DATA_VAL (0)
  ) ldg_cmd_fifo_element (
    .clk     (clk),
    .s_rst_n (s_rst_n),

    .in_data (s0_ldg_cmd),
    .in_vld  (s0_ldg_cmd_vld),
    .in_rdy  (s0_ldg_cmd_rdy),

    .out_data(seq_ldg_cmd),
    .out_vld (seq_ldg_vld),
    .out_rdy (seq_ldg_rdy)
  );

  fifo_element #(
    .WIDTH          (LOAD_BLWE_CMD_W),
    .DEPTH          (1),
    .TYPE_ARRAY     (4'h3),
    .DO_RESET_DATA  (1'b0),
    .RESET_DATA_VAL (0)
  ) ldb_cmd_fifo_element (
    .clk     (clk),
    .s_rst_n (s_rst_n),

    .in_data (s0_ldb_cmd),
    .in_vld  (s0_ldb_cmd_vld),
    .in_rdy  (s0_ldb_cmd_rdy),

    .out_data(seq_ldb_cmd),
    .out_vld (seq_ldb_vld),
    .out_rdy (seq_ldb_rdy)
  );

// ============================================================================================== //
// Load pointers
// ============================================================================================== //
  pointer_t ldg_ptD;
  pointer_t ldb_ptD;

  assign ldg_ptD = ldg_done ? pt_inc_1(ldg_pt) : ldg_pt;
  assign ldb_ptD = ldb_done ? pt_inc_1(ldb_pt) : ldb_pt;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      ldg_pt <= '0;
      ldb_pt <= '0;
    end
    else begin
      ldg_pt <= ldg_ptD;
      ldb_pt <= ldb_ptD;
    end

// ============================================================================================== //
// Update ks_in_wp
// ============================================================================================== //
  typedef enum logic [1:0] {
    KS_IN_XXX  = 'x,
    KS_IN_IDLE = '0,
    KS_IN_UPD_0
  } ks_in_state_e;

  ks_in_state_e ks_in_state;
  ks_in_state_e next_ks_in_state;

  logic ks_in_do_update;
  logic ks_in_do_update_ipip;
  logic ks_in_do_update_bpip;
  logic ks_in_do_update_bpip_cond;

  always_comb begin
    next_ks_in_state = KS_IN_XXX;
    case (ks_in_state)
      KS_IN_IDLE:
        next_ks_in_state = ks_in_do_update ? KS_IN_UPD_0 : ks_in_state;
      KS_IN_UPD_0:
        next_ks_in_state = KS_IN_IDLE;
    endcase
  end

  always_ff @(posedge clk)
    if (!s_rst_n) ks_in_state <= KS_IN_IDLE;
    else          ks_in_state <= next_ks_in_state;

  logic ks_in_st_idle;
  logic ks_in_st_upd_0;

  assign ks_in_st_idle  = ks_in_state == KS_IN_IDLE;
  assign ks_in_st_upd_0 = ks_in_state == KS_IN_UPD_0;

  //== Step 0 : analyze pointers
  logic                    ks_in_proc_full;
  logic                    k0_new_ct_exists;
  logic [PID_WW-1:0]       k0_new_ct_nb;
  logic [BPBS_NB_WW-1:0]   ks_in_ct_nb;
  logic [PID_WW-1:0]       ks_in_free_loc_nb;
  logic [TIMEOUT_CNT_W-1:0]ks_in_timeout_cnt;
  logic [TIMEOUT_CNT_W-1:0]ks_in_timeout_cntD;
  logic                    ks_in_timeout_reached;
  logic                    ks_in_empty;
  pointer_t                ks_in_ldb_pt;


  logic [TOTAL_PBS_NB-1:0] k0_mask;
  logic [TOTAL_PBS_NB-1:0] k0_mask_wpB;
  logic [TOTAL_PBS_NB-1:0] k0_mask_ldb_pt;
  logic                    k0_force_update;

  assign ks_in_ldb_pt      = !use_bpip || use_bpip_opportunism ? ldb_pt : pbs_force_pt;

  assign ks_in_empty       = pt_empty(ks_in_wp, ks_in_rp);
  assign ks_in_ct_nb       = pt_elt_nb(ks_in_wp, ks_in_rp);
  assign ks_in_proc_full   = ks_in_ct_nb == BATCH_PBS_NB;
  assign k0_new_ct_exists  = ~pt_empty(ks_in_ldb_pt,ks_in_wp);
  assign k0_new_ct_nb      = pt_elt_nb(ks_in_ldb_pt,ks_in_wp);
  assign ks_in_free_loc_nb = BATCH_PBS_NB - ks_in_ct_nb;

  // IPIP
  // Update ks_in_wp whenever a newer one is available, and there are free slots in the batch.
  assign ks_in_do_update_ipip = ~ks_in_proc_full
                               & k0_new_ct_exists;

  // BPIP
  // Update ks_in_wp
  // * only when ks_in_loop = 0 => force to start at iteration 0.
  // * when the batch is full, or a timeout is reached, or a force_pbs signal is received.
  assign ks_in_timeout_reached = ks_in_timeout_cnt == bpip_timeout;
  assign ks_in_timeout_cntD    = (ks_in_loop == 0) && ks_in_do_update_ipip ? ks_in_timeout_reached ? ks_in_timeout_cnt : ks_in_timeout_cnt + 1 : '0;

  assign k0_mask_wpB     = {TOTAL_PBS_NB{1'b1}} << ks_in_wp.pt;
  assign k0_mask_ldb_pt  = (1 << ks_in_ldb_pt.pt) -1;
  assign k0_mask         = (ks_in_ldb_pt.c != ks_in_wp.c) ?  k0_mask_ldb_pt | k0_mask_wpB : k0_mask_ldb_pt & k0_mask_wpB;
  assign k0_force_update = (ct_pool_force_pbs & k0_mask) != 0;

  // Do update ks_in_wp, if it has already been done (ks_in_empty==0).
  // Indeed, a command may have already been launched.
  assign ks_in_do_update_bpip_cond = (ks_in_loop == 0) & ks_in_do_update_ipip & ks_in_empty; // There are ct to be processed
  assign ks_in_do_update_bpip      = ks_in_do_update_bpip_cond &
                                  // and wait for trigger condition
                                 ( ks_in_timeout_reached
                                  | (k0_new_ct_nb >= BATCH_PBS_NB) // full batch
                                  | k0_force_update);

  assign ks_in_do_update =  use_bpip ? ks_in_do_update_bpip : ks_in_do_update_ipip;

  always_ff @(posedge clk)
    if (!s_rst_n) ks_in_timeout_cnt <= '0;
    else          ks_in_timeout_cnt <= ks_in_timeout_cntD;

// pragma translate_off
  always_ff @(posedge clk)
    if (use_bpip && ks_in_st_idle && ks_in_do_update_bpip) begin
      $display("%t > INFO: PEP sequencer: Batch sent to PBS filled with %0d ct, %0d ct were available (ks_in_wp={%1d, %0d}, BATCH_PBS_NB=%0d)",
        $time,k0_new_ct_nb > ks_in_free_loc_nb ? ks_in_free_loc_nb : k0_new_ct_nb, k0_new_ct_nb,ks_in_wp.c,ks_in_wp.pt,BATCH_PBS_NB);
      if (ks_in_timeout_reached)
        $display("%t > INFO: => Timeout triggered", $time);
      if (k0_force_update)
        $display("%t > INFO: => Force triggered", $time);
      if (k0_new_ct_nb >= BATCH_PBS_NB)
        $display("%t > INFO: => Full triggered", $time);
    end
// pragma translate_on


  //== Step 1 Update pointer
  logic [PID_WW-1:0]       k1_new_ct_nb;
  logic [PID_WW-1:0]       k1_free_loc_nb;

  always_ff @(posedge clk) begin
    k1_new_ct_nb   <= k0_new_ct_nb;
    k1_free_loc_nb <= ks_in_free_loc_nb;
  end

  logic [PID_WW:0]         k1_new_ct_minus_free_loc;
  logic [BPBS_NB_WW-1:0]   k1_wp_inc;
  pointer_t                ks_in_wpD;

  // Find minimum between k1_new_ct_nb and k1_free_loc_nb
  assign k1_new_ct_minus_free_loc = {1'b0,k1_new_ct_nb} - {1'b0, k1_free_loc_nb};
  assign k1_wp_inc                = k1_new_ct_minus_free_loc[PID_WW] ? k1_new_ct_nb : k1_free_loc_nb;
  assign ks_in_wpD                = ks_in_st_upd_0 ? pt_inc_any(ks_in_wp, k1_wp_inc) : ks_in_wp;

  always_ff @(posedge clk)
    if (!s_rst_n) ks_in_wp   <= '0;
    else          ks_in_wp   <= ks_in_wpD;

// ============================================================================================== //
// Send Key switching command
// ============================================================================================== //
// A command is sent when the KS is ready, i.e. when an enquiry is available.
// A command can be sent when:
// * there are ciphertexts to be processed.

  typedef enum logic [1:0] {
    KS_SEND_XXX  = 'x,
    KS_SEND_IDLE = '0,
    KS_SEND_SEND,
    KS_SEND_UPD
  } ks_send_state_e;

  logic           u0_send_cmd;
  logic           u0_send_cmd_tmp;

  ks_send_state_e   ks_send_state;
  ks_send_state_e   next_ks_send_state;

  always_comb begin
    next_ks_send_state = KS_SEND_XXX;
    case (ks_send_state)
      KS_SEND_IDLE:
        next_ks_send_state = u0_send_cmd ? KS_SEND_SEND : ks_send_state;
      KS_SEND_SEND:
        next_ks_send_state = KS_SEND_UPD;
      KS_SEND_UPD :
        next_ks_send_state = KS_SEND_IDLE;
    endcase
  end

  always_ff @(posedge clk)
    if (!s_rst_n) ks_send_state <= KS_SEND_IDLE;
    else          ks_send_state <= next_ks_send_state;

  logic ks_send_st_idle;
  logic ks_send_st_send;
  logic ks_send_st_upd;

  assign ks_send_st_idle = ks_send_state == KS_SEND_IDLE;
  assign ks_send_st_send = ks_send_state == KS_SEND_SEND;
  assign ks_send_st_upd  = ks_send_state == KS_SEND_UPD;

  //== Step 0 : analyze pointers
  assign u0_send_cmd_tmp = ~ks_in_empty & ~loop_full;
  assign u0_send_cmd     = u0_send_cmd_tmp & ks_cmd_enq_vld;
  assign ks_cmd_enq_rdy  = u0_send_cmd_tmp & ks_send_st_idle;

  // Last KS iteration flag
  // In ct_pool, we store the first iteration index.
  // So the last iteration index is given by end : start + LWE_K_P1 -1.
  // The current KS process will deliver index : [curr .. curr+LBX-1]
  // So the current is the last one if : end - curr < LBX
  logic [TOTAL_PBS_NB-1:0]                 u0_last;
  logic [TOTAL_PBS_NB-1:0][LWE_K_P1_W-1:0] u0_end_br_loop;
  logic [TOTAL_PBS_NB-1:0][LWE_K_P1_W+1:0] u0_diff_loop1;
  logic [TOTAL_PBS_NB-1:0][LWE_K_P1_W+1:0] u0_diff_loop2;

  always_comb
    for (int i=0; i<TOTAL_PBS_NB; i=i+1) begin
      u0_end_br_loop[i] = ct_pool[i].br_loop == 0 ? LWE_K_P1 - 1 : ct_pool[i].br_loop - 1;
      u0_diff_loop1[i]  = {2'b00,u0_end_br_loop[i]} - {2'b00,ks_in_loop};
      u0_diff_loop2[i]  = u0_diff_loop1[i] - LBX;
      u0_last[i]        = ct_pool[i].br_loop_avail
                             & ~u0_diff_loop1[i][LWE_K_P1_W+1] // end_br_loop >= ks_in_loop
                             & u0_diff_loop2[i][LWE_K_P1_W+1]; // end_br_loop < ks_in_loop + LBX
    end

  // NOTE: LWE_K is big enough so that :
  // * newly entered ct are tagged as not last, and they can stay
  //   this way without conflict, until the pbs_in part tagged them with br_loop_avail = 1,
  //   and they are still not in their last iteration.

  //== Step 1 : Send
  // + prepare ks_in_rp update
  logic [TOTAL_PBS_NB-1:0] u1_last;

  always_ff @(posedge clk)
    u1_last <= u0_last;

  logic [TOTAL_PBS_NB-1:0] u1_mask;
  logic [TOTAL_PBS_NB-1:0] u1_mask_rpB;
  logic [TOTAL_PBS_NB-1:0] u1_mask_wp;
  logic [TOTAL_PBS_NB-1:0] u1_last_masked;
  logic [BPBS_NB_WW-1:0]   u1_rp_inc;

  ks_cmd_t                 u1_cmd;
  logic                    u1_cmd_avail;

  // Send command
  assign u1_cmd_avail   = ks_send_st_send;

  assign u1_cmd.ks_loop_c = ks_in_loop_c;
  assign u1_cmd.ks_loop   = ks_in_loop;
  assign u1_cmd.wp        = ks_in_wp;
  assign u1_cmd.rp        = ks_in_rp;

  // Mask to keep only the last elements that are currently processed.
  assign u1_mask_rpB = {TOTAL_PBS_NB{1'b1}} << ks_in_rp.pt;
  assign u1_mask_wp  = ((1 << ks_in_wp.pt)-1);
  assign u1_mask     = (ks_in_wp.c != ks_in_rp.c) ?  u1_mask_wp | u1_mask_rpB : u1_mask_wp & u1_mask_rpB;

  assign u1_last_masked = u1_last & u1_mask;
  always_comb begin
    u1_rp_inc = '0;
    for (int i=0; i<TOTAL_PBS_NB; i=i+1)
      u1_rp_inc = u1_rp_inc + u1_last_masked[i];
  end

  // start ksk_if
  logic ksk_if_batch_start_1hD;

  assign ksk_if_batch_start_1hD = ks_send_st_send & (ks_in_loop == '0);

  always_ff @(posedge clk)
    if (!s_rst_n) ksk_if_batch_start_1h <= '0;
    else          ksk_if_batch_start_1h <= ksk_if_batch_start_1hD;

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      assert($countones(u1_mask) <= BATCH_PBS_NB)
      else begin
        $fatal(1,"%t > ERROR: ks_in mask (u1_mask) should contain at most BATCH_PBS_NB bits equal to 1!",$time);
      end
    end

  // Check that LWE_K is not too small.
  // In BPIP, should not occur that the last ks loop is sent while the corresponding ct are not tagged
  // as br_loop_avail

  logic [TOTAL_PBS_NB-1:0] _u1_ct_pool_br_loop_avail;
  always_comb
    for (int i=0; i<TOTAL_PBS_NB; i=i+1)
      _u1_ct_pool_br_loop_avail[i] = ~u1_mask[i] | ct_pool[i].br_loop_avail;

  always_ff @(posedge clk)
    if (use_bpip && ks_send_st_send && (ks_in_loop > (LWE_K-LBX))) begin // last iteration
      assert(_u1_ct_pool_br_loop_avail == '1)
      else begin
        $fatal(1,"%t > ERROR: LWE_K (%0d) is too small. All LWE coef have been processed, and PBS has not started. ks_in_loop=%0d",$time, LWE_K, ks_in_loop);
      end
    end
// pragma translate_on

  //== Step 2 : Update ks_in_rp
  logic [BPBS_NB_WW-1:0] u2_rp_inc;

  always_ff @(posedge clk)
    u2_rp_inc <= u1_rp_inc;

  // The KS processes LBX iterations at a time.
  logic [LWE_K_P1_W-1:0] ks_in_loopD;
  logic                  ks_in_loop_cD;
  pointer_t              ks_in_rpD;

  assign ks_in_loopD   = ks_send_st_upd ? ks_in_loop > (LWE_K-LBX) ? '0 : (ks_in_loop + LBX) : ks_in_loop;
  assign ks_in_rpD     = ks_send_st_upd ? pt_inc_any(ks_in_rp, u2_rp_inc) : ks_in_rp;
  assign ks_in_loop_cD = ks_send_st_upd && (ks_in_loop > (LWE_K-LBX)) ? ~ks_in_loop_c : ks_in_loop_c;

  always_ff @(posedge clk)
    if (!s_rst_n) ks_in_rp <= '0;
    else          ks_in_rp <= ks_in_rpD;

  always_ff @(posedge clk)
    if (!s_rst_n || reset_clear) begin
      ks_in_loop   <= '0;
      ks_in_loop_c <= '0;
    end
    else begin
      ks_in_loop   <= ks_in_loopD;
      ks_in_loop_c <= ks_in_loop_cD;
    end

  //== Output pipe
  always_ff @(posedge clk)
    if (!s_rst_n) seq_ks_cmd_avail <= 1'b0;
    else          seq_ks_cmd_avail <= u1_cmd_avail;

  always_ff @(posedge clk)
    seq_ks_cmd <= u1_cmd;

// pragma translate_off
  always_ff @(posedge clk)
    if (!use_bpip && ks_send_st_send) begin
      $display("%t > INFO: PEP sequencer: KS  loop (%1d,%0d) sent with %0d ct (ks_in_wp={%1d, %0d}, ks_in_rp={%1d, %0d}, BATCH_PBS_NB=%0d)",
        $time, ks_in_loop_c, ks_in_loop, pt_elt_nb(ks_in_wp,ks_in_rp),ks_in_wp.c,ks_in_wp.pt,ks_in_rp.c,ks_in_rp.pt,BATCH_PBS_NB);
    end
// pragma translate_on

  // Keep track of the pointers sent in the latest seq_ks command.
  // This is used to check that the KS is flushed.
  pointer_t              seq_ks_latest_in_wp;
  pointer_t              seq_ks_latest_in_rp;
  logic [LWE_K_P1_W-1:0] seq_ks_latest_max_in_loop;
  pointer_t              seq_ks_latest_in_wpD;
  pointer_t              seq_ks_latest_in_rpD;
  logic [LWE_K_P1_W-1:0] seq_ks_latest_max_in_loopD;
  logic [LWE_K_P1_W-1:0] seq_ks_latest_max_in_loopD_tmp;

  logic                  u1_cmd_body_only;

  assign u1_cmd_body_only     = u1_cmd.ks_loop == LWE_K;
  assign seq_ks_latest_in_wpD = u1_cmd_avail && !u1_cmd_body_only ? u1_cmd.wp : seq_ks_latest_in_wp;
  assign seq_ks_latest_in_rpD = u1_cmd_avail && !u1_cmd_body_only ? u1_cmd.rp : seq_ks_latest_in_rp;
  assign seq_ks_latest_max_in_loopD_tmp = u1_cmd.ks_loop > (LWE_K-LBX) ? LWE_K-1 : u1_cmd.ks_loop + LBX-1;
  assign seq_ks_latest_max_in_loopD     = u1_cmd_avail && !u1_cmd_body_only ?
                                            seq_ks_latest_max_in_loopD_tmp : seq_ks_latest_max_in_loop;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      seq_ks_latest_in_wp       <= '0;
      seq_ks_latest_in_rp       <= '0;
    end
    else begin
      seq_ks_latest_in_wp       <= seq_ks_latest_in_wpD;
      seq_ks_latest_in_rp       <= seq_ks_latest_in_rpD;
    end

  always_ff @(posedge clk)
    if (!s_rst_n || reset_clear) begin
      seq_ks_latest_max_in_loop <= LWE_K-1;
    end
    else begin
      seq_ks_latest_max_in_loop <= seq_ks_latest_max_in_loopD;
    end

// ============================================================================================== //
// Force PBS pointer
// ============================================================================================== //
// Used in BPIP.
// Points position after the oldest PBS force to be processed.
// Note : there is no need to rush the update here.
//        Indeed, once the KS has started, we have the PBS duration
//        to update this pointer; i.e. find the next position with
//        a force or the latest ldb_pt.
  pointer_t pbs_force_ptD;
  pointer_t pbs_force_pt_inc_1;

  logic                    ks_in_st_upd_0_dly;
  logic [TOTAL_PBS_NB-1:0] pbs_force_pt_is_force_tmp;
  logic                    pbs_force_pt_is_force;

  typedef enum logic [1:0] {
    FORCE_UPD_XXX  = 'x,
    FORCE_UPD_ACTIVE = '0,
    FORCE_UPD_WAIT_KS,
    FORCE_UPD_WAIT_UPD
  } force_upd_state_e;

  force_upd_state_e force_upd_state;
  force_upd_state_e next_force_upd_state;

  always_comb begin
    next_force_upd_state = FORCE_UPD_XXX;
    case (force_upd_state)
      FORCE_UPD_ACTIVE:
        next_force_upd_state = (pbs_force_pt != ldb_pt) && pbs_force_pt_is_force ? FORCE_UPD_WAIT_KS : force_upd_state;
      FORCE_UPD_WAIT_KS:
        next_force_upd_state = ks_in_st_upd_0_dly && (pbs_force_pt == ks_in_wp) ? FORCE_UPD_WAIT_UPD : force_upd_state; // ks_in_wp has taken pbs_force_pt into account.
      FORCE_UPD_WAIT_UPD :
        next_force_upd_state = (pbs_force_pt != ldb_pt) ? FORCE_UPD_ACTIVE : force_upd_state;
    endcase
  end

  always_ff @(posedge clk)
    if (!s_rst_n) force_upd_state <= FORCE_UPD_ACTIVE;
    else          force_upd_state <= next_force_upd_state;

  logic force_upd_st_active;
  logic force_upd_st_wait_ks;
  logic force_upd_st_wait_upd;

  assign force_upd_st_active   = force_upd_state == FORCE_UPD_ACTIVE;
  assign force_upd_st_wait_ks  = force_upd_state == FORCE_UPD_WAIT_KS;
  assign force_upd_st_wait_upd = force_upd_state == FORCE_UPD_WAIT_UPD;

  assign pbs_force_pt_inc_1    = pt_inc_1(pbs_force_pt);
  assign pbs_force_pt_is_force_tmp = ct_pool_force_pbs & ct_pool_avail;
  assign pbs_force_pt_is_force = pbs_force_pt_is_force_tmp[pbs_force_pt.pt];
  assign pbs_force_ptD         = ((pbs_force_pt != ldb_pt)
                                    && (force_upd_st_wait_upd || force_upd_st_active))?
                                  pbs_force_pt_inc_1 : pbs_force_pt;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      pbs_force_pt       <= '0;
      ks_in_st_upd_0_dly <= 1'b0;
    end
    else begin
      pbs_force_pt       <= pbs_force_ptD;
      ks_in_st_upd_0_dly <= ks_in_st_upd_0;
    end

// ============================================================================================== //
// Update pbs_in_wp
// ============================================================================================== //
  logic [PID_W:0] pbs_in_wpD;

  typedef enum logic [1:0] {
    PBS_IN_XXX  = 'x,
    PBS_IN_IDLE = '0,
    PBS_IN_UPD_0,
    PBS_IN_UPD_1
  } pbs_in_state_e;

  pbs_in_state_e pbs_in_state;
  pbs_in_state_e next_pbs_in_state;

  logic pbs_in_do_update;
  logic pbs_in_do_update_ipip;
  logic pbs_in_do_update_bpip;

  always_comb begin
    next_pbs_in_state = PBS_IN_XXX;
    case (pbs_in_state)
      PBS_IN_IDLE:
        next_pbs_in_state = pbs_in_do_update ? PBS_IN_UPD_0 : pbs_in_state;
      PBS_IN_UPD_0:
        next_pbs_in_state = PBS_IN_UPD_1;
      PBS_IN_UPD_1:
        next_pbs_in_state = PBS_IN_IDLE;
    endcase
  end

  always_ff @(posedge clk)
    if (!s_rst_n) pbs_in_state <= PBS_IN_IDLE;
    else          pbs_in_state <= next_pbs_in_state;

  logic pbs_in_st_idle;
  logic pbs_in_st_upd_0;
  logic pbs_in_st_upd_1;

  assign pbs_in_st_idle  = pbs_in_state == PBS_IN_IDLE;
  assign pbs_in_st_upd_0 = pbs_in_state == PBS_IN_UPD_0;
  assign pbs_in_st_upd_1 = pbs_in_state == PBS_IN_UPD_1;

  //== Step 0 : analyze pointers
  logic                  pbs_in_proc_full;
  logic                  p0_new_g_ct_exists;
  logic                  p0_new_ks_ct_exists;
  logic [PID_WW-1:0]     p0_new_g_ct_nb;
  logic [PID_WW-1:0]     p0_new_ks_ct_nb;
  logic [PID_WW-1:0]     pbs_in_free_loc_nb;
  logic [PID_WW-1:0]     pbs_in_ct_nb;

  assign pbs_in_ct_nb        = pt_elt_nb(pbs_in_wp, pbs_in_rp);
  assign pbs_in_proc_full    = pbs_in_ct_nb == BATCH_PBS_NB;
  assign p0_new_g_ct_exists  = ~pt_empty(ldg_pt,pbs_in_wp);
  assign p0_new_ks_ct_exists = ~pt_empty(ks_out_wp,pbs_in_wp);
  assign p0_new_g_ct_nb      = pt_elt_nb(ldg_pt,pbs_in_wp);
  assign p0_new_ks_ct_nb     = pt_elt_nb(ks_out_wp,pbs_in_wp);
  assign pbs_in_free_loc_nb  = BATCH_PBS_NB - pbs_in_ct_nb;

  // IPIP
  assign pbs_in_do_update_ipip = ~pbs_in_proc_full
                                & p0_new_g_ct_exists
                                & p0_new_ks_ct_exists
                                & (ks_out_loop == pbs_in_loop);

  // BPIP
  assign pbs_in_do_update_bpip = (pbs_in_loop == 0)
                                & (p0_new_g_ct_nb >= p0_new_ks_ct_nb)
                                & pbs_in_do_update_ipip;

  assign pbs_in_do_update = use_bpip ? pbs_in_do_update_bpip : pbs_in_do_update_ipip;

  //== Step 1 : Update pointer
  logic [BPBS_NB_WW-1:0]   p1_wp_inc;
  logic [TOTAL_PBS_NB-1:0] p2_upd_pool_br_loop_mh;
  logic [TOTAL_PBS_NB-1:0] p2_upd_pool_br_loop_mhD_tmp;
  logic [2*TOTAL_PBS_NB-1:0] p2_upd_pool_br_loop_mhD_tmp2;
  logic [TOTAL_PBS_NB-1:0] p2_upd_pool_br_loop_mhD;

  logic [PID_WW-1:0]       p1_new_g_ct_nb;
  logic [PID_WW-1:0]       p1_new_ks_ct_nb;
  logic [PID_WW-1:0]       p1_free_loc_nb;

  logic [PID_WW:0]         p1_new_g_ct_minus_free_loc;
  logic [PID_WW:0]         p1_new_ks_ct_minus_free_loc;
  logic [PID_WW:0]         p1_free_loc_minus_new_g_ct;
  logic [PID_WW:0]         p1_free_loc_minus_new_ks_ct;
  logic [PID_WW:0]         p1_new_g_ct_minus_new_ks_ct;
  logic [PID_WW:0]         p1_new_ks_ct_minus_new_g_ct;

  always_ff @(posedge clk) begin
    p1_new_g_ct_nb  <= p0_new_g_ct_nb;
    p1_new_ks_ct_nb <= p0_new_ks_ct_nb;
    p1_free_loc_nb  <= pbs_in_free_loc_nb;
  end

  // Find the minimum between p1_free_loc_nb, p1_new_g_ct_nb, p1_new_ks_ct_nb
  assign p1_new_g_ct_minus_free_loc  = {1'b0,p1_new_g_ct_nb}  - {1'b0,p1_free_loc_nb};
  assign p1_new_ks_ct_minus_free_loc = {1'b0,p1_new_ks_ct_nb} - {1'b0,p1_free_loc_nb};
  assign p1_free_loc_minus_new_g_ct  = {1'b0,p1_free_loc_nb}  - {1'b0,p1_new_g_ct_nb};
  assign p1_free_loc_minus_new_ks_ct = {1'b0,p1_free_loc_nb}  - {1'b0,p1_new_ks_ct_nb};
  assign p1_new_g_ct_minus_new_ks_ct = {1'b0,p1_new_g_ct_nb}  - {1'b0,p1_new_ks_ct_nb};
  assign p1_new_ks_ct_minus_new_g_ct = {1'b0,p1_new_ks_ct_nb} - {1'b0,p1_new_g_ct_nb};

  assign p1_wp_inc = p1_new_g_ct_minus_new_ks_ct[PID_WW] ? p1_new_g_ct_minus_free_loc[PID_WW]  ? p1_new_g_ct_nb[BPBS_NB_WW-1:0] : p1_free_loc_nb[BPBS_NB_WW-1:0]:
                                                           p1_new_ks_ct_minus_free_loc[PID_WW] ? p1_new_ks_ct_nb[BPBS_NB_WW-1:0] : p1_free_loc_nb[BPBS_NB_WW-1:0];
  assign pbs_in_wpD = pbs_in_st_upd_0 ? pt_inc_any(pbs_in_wp,p1_wp_inc) : pbs_in_wp;

  assign p2_upd_pool_br_loop_mhD_tmp  = (1 << p1_wp_inc)-1;
  assign p2_upd_pool_br_loop_mhD_tmp2 = ({2{p2_upd_pool_br_loop_mhD_tmp}} << pbs_in_wp.pt);
  assign p2_upd_pool_br_loop_mhD      = p2_upd_pool_br_loop_mhD_tmp2[2*TOTAL_PBS_NB-1:TOTAL_PBS_NB] & {TOTAL_PBS_NB{pbs_in_st_upd_0}};

  always_ff @(posedge clk)
    if (!s_rst_n) pbs_in_wp <= '0;
    else          pbs_in_wp <= pbs_in_wpD;

  //== Step 2 : Update ct_pool br_loop field
  always_ff @(posedge clk)
    if (!s_rst_n) p2_upd_pool_br_loop_mh <= '0;
    else          p2_upd_pool_br_loop_mh <= p2_upd_pool_br_loop_mhD;

// ============================================================================================== //
// Send PBS command
// ============================================================================================== //
// A PBS command is sent when the PBS is ready, i.e. an enquiry is available.
// Do not send when pbs_in_wp and the ct_pool are being updated, or when a command
// is already in the pipe:
//   pbs_in_st_upd_0, pbs_in_st_upd_1, pbs_send_st_wrap, pbs_send_st_send.
// Step 0 : wrap on RANK_NB*GRAM_NB lines
// Step 1 : rotate
// Step 2 : Send - update ct_pool
//
// Particular case:
// the KS result proposes a ct that has already been entirely processed.
// This could occur since the KS processes several br_loop per iteration.
// These results should be flushed.
// This happens when : pbs_in_empty & (ks_out_wp == pbs_in_wp) & (ks_out_loop == pbs_in_loop).
// The pbs_in_loop is then updated.
// A PBS command is sent so that the BSK manager could update its cache.
// Note that in order to avoid race between real commands that are
// being process and flush, this latter is sent only when all the real
// commands are done: i.e. pool_rp == pbs_in_rp

  typedef enum logic [1:0] {
    PBS_SEND_XXX  = 'x,
    PBS_SEND_IDLE = '0,
    PBS_SEND_WRAP,
    PBS_SEND_SEND
  } pbs_send_state_e;

  pbs_send_state_e pbs_send_state;
  pbs_send_state_e next_pbs_send_state;

  logic r0_send_cmd;

  always_comb begin
    next_pbs_send_state = PBS_SEND_XXX;
    case (pbs_send_state)
      PBS_SEND_IDLE:
        next_pbs_send_state = r0_send_cmd ? PBS_SEND_WRAP : pbs_send_state;
      PBS_SEND_WRAP:
        next_pbs_send_state = PBS_SEND_SEND;
      PBS_SEND_SEND:
        next_pbs_send_state = PBS_SEND_IDLE;
    endcase
  end

  always_ff @(posedge clk)
    if (!s_rst_n) pbs_send_state <= PBS_SEND_IDLE;
    else          pbs_send_state <= next_pbs_send_state;

  logic pbs_send_st_idle;
  logic pbs_send_st_wrap;
  logic pbs_send_st_send;

  assign pbs_send_st_idle = pbs_send_state == PBS_SEND_IDLE;
  assign pbs_send_st_wrap = pbs_send_state == PBS_SEND_WRAP;
  assign pbs_send_st_send = pbs_send_state == PBS_SEND_SEND;

  logic               r0_send_cmd_tmp;
  logic               pbs_in_cmd_flush;
  logic               pbs_in_cmd_regular;
  logic               pbs_in_empty;

  logic               corr_buffer_free_loc;

  assign pbs_in_empty       = pt_empty(pbs_in_wp,pbs_in_rp);
  assign pbs_in_cmd_regular = ~pbs_in_empty;
  assign pbs_in_cmd_flush   = pbs_in_empty & (ks_out_wp == pbs_in_wp) & (pool_rp == pbs_in_rp);
  assign r0_send_cmd_tmp    = pbs_send_st_idle
                             & corr_buffer_free_loc
                             & (pbs_in_st_idle & ~pbs_in_do_update)
                             & (ks_out_loop == pbs_in_loop)
                             & (pbs_in_cmd_regular | pbs_in_cmd_flush);
  assign r0_send_cmd        = r0_send_cmd_tmp & pbs_cmd_enq_vld;
  assign pbs_cmd_enq_rdy    = r0_send_cmd_tmp;

// ---------------------------------------------------------------------------------------------- //
// Prepare map
// ---------------------------------------------------------------------------------------------- //
  // Build the map that will be used by the PBS process.
  // Collect the corrections for the mean compensation.

  //== Step 0
  logic [TOTAL_PBS_NB_EXT-1:0]                           r0_mask;
  logic [TOTAL_PBS_NB_EXT-1:0]                           r0_mask_wp;
  logic [TOTAL_PBS_NB_EXT-1:0]                           r0_mask_rpB;
  ct_info_t [TOTAL_PBS_NB_EXT-1:0]                       r0_pool_ext; // Copy lsb in msb position, to represent the wrapping.
  ct_info_t [TOTAL_PBS_NB_EXT-1:0]                       r0_pool_ext_masked;
  ct_info_t [RANK_LINE_NB-1:0][RANK_NB-1:0][GRAM_NB-1:0] r0_pool_ext_masked_a;
  ct_info_t [RANK_NB-1:0][GRAM_NB-1:0]                   r0_pool_wrap;
  logic [RANK_W-1:0]                                     r0_rot;
  ct_info_t [TOTAL_PBS_NB_DIFF-1:0]                      ct_pool_ext;

  assign ct_pool_ext = ct_pool; // extend with 0s if needed

  // Rotation factor. To rotate the wrapped array
  assign r0_rot = pbs_in_rp_rank_ofs == 0 ? '0 : RANK_NB - pbs_in_rp_rank_ofs;

  assign r0_mask_rpB = {TOTAL_PBS_NB_EXT{1'b1}} << pbs_in_rp.pt;
  assign r0_mask_wp  = (1 << pbs_in_wp.pt)-1;
  assign r0_mask     = (pbs_in_rp.c != pbs_in_wp.c) ? r0_mask_rpB & {r0_mask_wp[0+:TOTAL_PBS_NB_DIFF], {TOTAL_PBS_NB{1'b1}}}: r0_mask_rpB & r0_mask_wp;
  assign r0_pool_ext = {ct_pool_ext,ct_pool};

  always_comb
    for (int i=0; i<TOTAL_PBS_NB_EXT; i=i+1)
      r0_pool_ext_masked[i] = r0_pool_ext[i] & {CT_INFO_W{r0_mask[i]}};

  assign r0_pool_ext_masked_a  = r0_pool_ext_masked; // Cast

  always_comb begin
    r0_pool_wrap = '0;
    for (int i=0; i<RANK_LINE_NB; i=i+1)
      r0_pool_wrap = r0_pool_wrap | r0_pool_ext_masked_a[i];
  end

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      assert($countones(r0_mask) <= BATCH_PBS_NB)
      else begin
        $fatal(1,"%t > ERROR: pbs_in mask should contain at most BATCH_PBS_NB bits equal to 1!",$time);
      end
    end
// pragma translate_on

  //== Step 1
  logic [RANK_W-1:0]                     r1_rot;
  ct_info_t [RANK_NB-1:0][GRAM_NB-1:0]   r1_pool_wrap;
  map_elt_t [RANK_NB-1:0][GRAM_NB-1:0]   r1_map_tmp;
  map_elt_t [RANK_NB*2-1:0][GRAM_NB-1:0] r1_map_tmp_ext;
  map_elt_t [RANK_NB-1:0][GRAM_NB-1:0]   r1_map;
  logic [BATCH_PBS_NB-1:0]               r1_last;
  logic [BPBS_NB_WW-1:0]                 r1_last_nb;
  logic [LWE_K_W-1:0]                    pbs_in_last_loop;
  logic [PID_WW-1:0]                     r1_ct_nb;
  corr_elt_t [RANK_NB-1:0][GRAM_NB-1:0]  r1_corr_map;

  always_ff @(posedge clk) begin
    r1_rot       <= r0_rot;
    r1_pool_wrap <= r0_pool_wrap;
    r1_ct_nb     <= pbs_in_ct_nb;
  end

  // Start loop index, for which current br_loop represents the last one.
  assign pbs_in_last_loop = pbs_in_loop == LWE_K-1 ? '0 : pbs_in_loop+1;

  always_comb
    for (int i=0; i<RANK_NB; i=i+1)
      for (int j=0; j<GRAM_NB; j=j+1) begin
        r1_map_tmp[i][j].pid            = r1_pool_wrap[i][j].pid;
        r1_map_tmp[i][j].avail          = r1_pool_wrap[i][j].avail; // Note : if not avail, this has been set to 0 by the mask.
        r1_map_tmp[i][j].br_loop_parity = r1_pool_wrap[i][j].br_loop_c;
        r1_map_tmp[i][j].last           = r1_pool_wrap[i][j].br_loop == pbs_in_last_loop;
        r1_map_tmp[i][j].first          = r1_pool_wrap[i][j].br_loop == pbs_in_loop;
        r1_map_tmp[i][j].lwe            = r1_pool_wrap[i][j].lwe;
        r1_map_tmp[i][j].dst_rid        = r1_pool_wrap[i][j].dst_rid;
        r1_map_tmp[i][j].log_lut_nb     = r1_pool_wrap[i][j].log_lut_nb;

        r1_corr_map[i][j].avail         = r1_pool_wrap[i][j].avail;
        r1_corr_map[i][j].corr          = r1_pool_wrap[i][j].corr;
        r1_corr_map[i][j].pid           = r1_pool_wrap[i][j].pid.pid;
      end

  // Rotate
  assign r1_map_tmp_ext = {2{r1_map_tmp}};
  always_comb
    for (int i=0; i<RANK_NB; i=i+1)
      r1_map[i] = r1_map_tmp_ext[i+r1_rot];

  // Rename
  always_comb
    for (int i=0; i<RANK_NB; i=i+1)
      for (int j=0; j<GRAM_NB; j=j+1)
        r1_last[i*GRAM_NB+j] = r1_map_tmp[i][j].last & r1_map_tmp[i][j].avail;

  always_comb begin
    r1_last_nb = '0;
    for (int i=0; i<BATCH_PBS_NB; i=i+1)
      r1_last_nb = r1_last_nb + r1_last[i];
  end


  //== Step 2
  map_elt_t [RANK_NB-1:0][GRAM_NB-1:0] r2_map;
  logic [BPBS_NB_WW-1:0]               r2_last_nb;
  logic [PID_W-1:0]                    r2_ct_nb_m1;
  pbs_cmd_t                            seq_pbs_cmd_s;

  always_ff @(posedge clk) begin
    r2_map      <= r1_map;
    r2_last_nb  <= r1_last_nb;
    r2_ct_nb_m1 <= r1_ct_nb - 1;
  end

  assign seq_pbs_cmd_s.br_loop   = pbs_in_loop;
  assign seq_pbs_cmd_s.map       = r2_map;
  assign seq_pbs_cmd_s.ct_nb_m1  = pbs_in_cmd_flush ? '0 : r2_ct_nb_m1;
  assign seq_pbs_cmd_s.is_flush  = pbs_in_cmd_flush;
  assign seq_pbs_cmd             = seq_pbs_cmd_s;
  assign seq_pbs_cmd_avail       = pbs_send_st_send;

  // Update pbs_in_rp
  pointer_t              pbs_in_rpD;
  logic [LWE_K_W-1:0]    pbs_in_loopD;
  logic                  pbs_in_loop_cD;
  logic                  pbs_in_rp_wrap;
  logic [RANK_W-1:0]     pbs_in_rp_rank_ofsD;

  assign pbs_in_rp_wrap      = pt_inc_any_wrap(pbs_in_rp,r2_last_nb);
  assign pbs_in_rpD          = pbs_send_st_send ? pt_inc_any(pbs_in_rp,r2_last_nb) : pbs_in_rp;
  assign pbs_in_rp_rank_ofsD = pbs_send_st_send && pbs_in_rp_wrap ?
                                pbs_in_rp_rank_ofs + RANK_OFS_INC < RANK_NB ? pbs_in_rp_rank_ofs + RANK_OFS_INC : pbs_in_rp_rank_ofs + RANK_OFS_INC - RANK_NB :
                                pbs_in_rp_rank_ofs;

  // Update the BR loop index
  assign pbs_in_loopD        = pbs_send_st_send ? pbs_in_loop == LWE_K-1 ? '0 : pbs_in_loop + 1 : pbs_in_loop;
  assign pbs_in_loop_cD      = pbs_send_st_send && (pbs_in_loop == LWE_K-1) ? ~pbs_in_loop_c : pbs_in_loop_c;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      pbs_in_rp          <= '0;
      pbs_in_rp_rank_ofs <= '0;
    end
    else begin
      pbs_in_rp          <= pbs_in_rpD;
      pbs_in_rp_rank_ofs <= pbs_in_rp_rank_ofsD;
    end

  always_ff @(posedge clk)
    if (!s_rst_n || reset_clear) begin
      pbs_in_loop        <= '0;
      pbs_in_loop_c      <= 1'b0;
    end
    else begin
      pbs_in_loop        <= pbs_in_loopD;
      pbs_in_loop_c      <= pbs_in_loop_cD;
    end

  // Send start to bsk_if
  logic bsk_if_batch_start_1hD;

  assign bsk_if_batch_start_1hD = pbs_send_st_send & (pbs_in_loop == '0);

  // reset_cache: the bsk_if is currently being reset. Do not send
  // fake batch_start to it.
  always_ff @(posedge clk)
    if (!s_rst_n || reset_loop) bsk_if_batch_start_1h <= '0;
    else                        bsk_if_batch_start_1h <= bsk_if_batch_start_1hD;


// pragma translate_off
  always_ff @(posedge clk)
    if (seq_pbs_cmd_avail && seq_pbs_cmd_s.is_flush) begin
      $display("%t > INFO: PEP_SEQ Flushing at br_loop = {%1d, %0d}",$time, pbs_in_loop_c, pbs_in_loop);
    end

  always_ff @(posedge clk)
    if (!use_bpip && pbs_send_st_send) begin
      $display("%t > INFO: PEP sequencer: PBS loop (%1d,%0d) sent with %0d ct (pbs_in_wp={%1d, %0d}, pbs_in_rp={%1d, %0d})",
        $time, pbs_in_loop_c, pbs_in_loop, pt_elt_nb(pbs_in_wp,pbs_in_rp),pbs_in_wp.c,pbs_in_wp.pt,pbs_in_rp.c,pbs_in_rp.pt);
    end

// pragma translate_on

// ============================================================================================== //
// Receive KS result
// ============================================================================================== //
  // Update ct_pool with the LWE of KS result when ks_out_loop != pbs_in_loop

  typedef enum logic [1:0] {
    KS_UPD_XXX  = 'x,
    KS_UPD_IDLE = '0,
    KS_UPD_UPD
  } ks_upd_state_e;

  ks_upd_state_e ks_upd_state;
  ks_upd_state_e next_ks_upd_state;

  logic t0_do_upd_lwe;

  always_comb begin
    next_ks_upd_state = KS_UPD_XXX;
    case (ks_upd_state)
      KS_UPD_IDLE:
        next_ks_upd_state = t0_do_upd_lwe ? KS_UPD_UPD : ks_upd_state;
      KS_UPD_UPD:
        next_ks_upd_state = KS_UPD_IDLE;
    endcase
  end

  always_ff @(posedge clk)
    if (!s_rst_n) ks_upd_state <= KS_UPD_IDLE;
    else          ks_upd_state <= next_ks_upd_state;

  logic ks_upd_st_idle;
  logic ks_upd_st_upd;

  assign ks_upd_st_idle = ks_upd_state == KS_UPD_IDLE;
  assign ks_upd_st_upd  = ks_upd_state == KS_UPD_UPD;

  //== Step 0 :
  logic [TOTAL_PBS_NB-1:0]                                 t0_upd_mask;
  logic [TOTAL_PBS_NB-1:0]                                 t0_upd_mask_wp;
  logic [TOTAL_PBS_NB-1:0]                                 t0_upd_mask_rpB;
  logic [TOTAL_PBS_NB-1:0][LWE_COEF_W-1:0]                 t0_upd_pool_lwe;
  logic [TOTAL_PBS_NB-1:0][KS_CORR_W-1:0]                  t0_upd_pool_corr;
  logic [TOTAL_PBS_NB-1:-TOTAL_PBS_NB][LWE_COEF_W-1:0]     t0_upd_pool_lwe_tmp;
  logic [TOTAL_PBS_NB-1:-TOTAL_PBS_NB][KS_CORR_W-1:0]      t0_upd_pool_corr_tmp;
  logic [TOTAL_PBS_NB-1:0][LWE_COEF_W-1:0]                 t0_ks_res_lwe_ext;
  logic [TOTAL_PBS_NB-1:0][KS_CORR_W-1:0]                  t0_ks_res_corr_ext;
  logic [TOTAL_PBS_NB-1:0]                                 t1_upd_pool_lwe_mh;
  logic [TOTAL_PBS_NB-1:0]                                 t1_upd_pool_lwe_mhD;

  assign t0_do_upd_lwe = ks_res_vld & (ks_out_loop != pbs_in_loop);
  assign t0_upd_mask_rpB = {TOTAL_PBS_NB{1'b1}} << ks_res.rp.pt;
  assign t0_upd_mask_wp  = (1 << ks_res.wp.pt) - 1;
  assign t0_upd_mask     = (ks_res.rp.c != ks_res.wp.c) ? t0_upd_mask_wp | t0_upd_mask_rpB : t0_upd_mask_wp & t0_upd_mask_rpB;

  assign t0_ks_res_lwe_ext = ks_res.lwe_a; // extend with 0s
  assign t0_upd_pool_lwe_tmp = {2{t0_ks_res_lwe_ext}};

  assign t0_ks_res_corr_ext = ks_res.corr_a; // extend with 0s
  assign t0_upd_pool_corr_tmp = {2{t0_ks_res_corr_ext}};

  // Rotation
  always_comb
    for (int i=0; i<TOTAL_PBS_NB; i=i+1) begin
      int idx; // signed
      idx = i-ks_res.rp.pt;
      t0_upd_pool_lwe[i]  = t0_upd_pool_lwe_tmp[idx];
      t0_upd_pool_corr[i] = t0_upd_pool_corr_tmp[idx];
    end

  assign t1_upd_pool_lwe_mhD = t0_upd_mask & {TOTAL_PBS_NB{t0_do_upd_lwe}};

  //== Step 1
  // Update ks_out pointers
  // Update ct_pool lwe field
  logic [TOTAL_PBS_NB-1:0][LWE_COEF_W-1:0]     t1_upd_pool_lwe;
  logic [TOTAL_PBS_NB-1:0][KS_CORR_W-1:0]      t1_upd_pool_corr;
  pointer_t              ks_out_wpD;
  pointer_t              ks_out_rpD;
  logic [LWE_K_P1_W-1:0] ks_out_loopD;

  assign ks_out_wpD   = ks_upd_st_upd ? ks_res.wp : ks_out_wp;
  assign ks_out_rpD   = ks_upd_st_upd ? ks_res.rp : ks_out_rp;
  assign ks_out_loopD = ks_upd_st_upd ? ks_res.ks_loop : ks_out_loop;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      t1_upd_pool_lwe_mh <= '0;
      ks_out_wp          <= '0;
      ks_out_rp          <= '0;
    end
    else begin
      t1_upd_pool_lwe_mh <= t1_upd_pool_lwe_mhD;
      ks_out_wp          <= ks_out_wpD;
      ks_out_rp          <= ks_out_rpD;
    end

  always_ff @(posedge clk)
    if (!s_rst_n || reset_clear) ks_out_loop <= LWE_K-1;
    else                         ks_out_loop <= ks_out_loopD;

  always_ff @(posedge clk) begin
    t1_upd_pool_lwe  <= t0_upd_pool_lwe;
    t1_upd_pool_corr <= t0_upd_pool_corr;
  end

  assign ks_res_rdy = ks_upd_st_upd;

// pragma translate_off
  logic [LWE_K_W-1:0] _pbs_in_loop_p1;
  assign _pbs_in_loop_p1 = pbs_in_loop == LWE_K-1 ? '0 : pbs_in_loop + 1;

  always_ff @(posedge clk)
    if (!s_rst_n || reset_clear) begin
      // do nothing
    end
    else begin
      if (ks_res_vld) begin
        assert((ks_res.ks_loop == pbs_in_loop) || (ks_res.ks_loop == _pbs_in_loop_p1))
        else begin
          $fatal(1,"%t > ERROR: KS result ks_loop (%0d) is incoherent with pbs_in_loop (%0d)!",$time,ks_res.ks_loop,pbs_in_loop);
        end
      end
    end
// pragma translate_on

// ============================================================================================== //
// Ciphertext pool update
// ============================================================================================== //
//-----------------------------------------------
// Update with input
//-----------------------------------------------
  logic [TOTAL_PBS_NB-1:0] pool_wp_1h;

  logic [TOTAL_PBS_NB-1:0] s1_upd_pool_in_1h;
  logic [TOTAL_PBS_NB-1:0] s1_upd_pool_in_1hD;
  logic [RID_W-1:0]        s1_dst_rid;
  logic [LOG_LUT_NB_W-1:0] s1_log_lut_nb;
  logic                    s1_force_pbs;

  common_lib_bin_to_one_hot #(
    .ONE_HOT_W (TOTAL_PBS_NB)
  ) s0_common_lib_bin_to_one_hot (
    .in_value (pool_wp.pt),
    .out_1h   (pool_wp_1h)
  );

  assign s1_upd_pool_in_1hD = {TOTAL_PBS_NB{s0_load_ct}} & pool_wp_1h;

  always_ff @(posedge clk)
    if (!s_rst_n) s1_upd_pool_in_1h <= '0;
    else          s1_upd_pool_in_1h <= s1_upd_pool_in_1hD;

  always_ff @(posedge clk) begin
    s1_dst_rid    <= s0_inst.dst_rid;
    s1_log_lut_nb <= s0_inst.dop.log_lut_nb;
    s1_force_pbs  <= s0_inst.dop.flush_pbs;
  end

//-----------------------------------------------
// Update with ct done
//-----------------------------------------------
  logic [TOTAL_PBS_NB-1:0] s1_upd_pool_done_1h;
  logic [TOTAL_PBS_NB-1:0] s1_upd_pool_done_1hD;

  assign s1_upd_pool_done_1hD = {TOTAL_PBS_NB{sxt_done}} & sxt_done_pid_1h;

  always_ff @(posedge clk)
    if (!s_rst_n) s1_upd_pool_done_1h <= '0;
    else          s1_upd_pool_done_1h <= s1_upd_pool_done_1hD;

// pragma translate_off
  always_ff @(posedge clk)
    for (int i=0; i<TOTAL_PBS_NB; i=i+1)
      if (s1_upd_pool_done_1h[i])
        assert(ct_pool[i].avail)
        else begin
          $fatal(1,"%t > ERROR: SXT done for a CT that is not available!", $time);
        end
// pragma translate_on

//-----------------------------------------------
// Update
//-----------------------------------------------
  always_comb
    for (int i=0; i<TOTAL_PBS_NB; i=i+1) begin
      ct_poolD[i] = ct_pool[i];
      if (s1_upd_pool_done_1h[i])
        ct_poolD[i].avail         = 1'b0;
      if (s1_upd_pool_in_1h[i]) begin
        ct_poolD[i].avail         = 1'b1;
        ct_poolD[i].dst_rid       = s1_dst_rid;
        ct_poolD[i].br_loop_avail = 1'b0;
        ct_poolD[i].force_pbs     = s1_force_pbs;
        ct_poolD[i].log_lut_nb    = s1_log_lut_nb;
      end
      if (p2_upd_pool_br_loop_mh[i]) begin
        ct_poolD[i].br_loop_c     = pbs_in_loop_c;
        ct_poolD[i].br_loop       = pbs_in_loop;
        ct_poolD[i].br_loop_avail = 1'b1;
      end
      if (t1_upd_pool_lwe_mh[i]) begin
        ct_poolD[i].lwe           = t1_upd_pool_lwe[i];
        ct_poolD[i].corr          = t1_upd_pool_corr[i];
      end
    end

// ============================================================================================== //
// Update pool rp
// ============================================================================================== //
  assign s0_ct_done = ~pool_empty & ~ct_pool[pool_rp.pt].avail
                      & ~(|s1_upd_pool_in_1h); // avoid considering the pool while it is being updated by the input.
  assign s0_ct_done_br_loop = ct_pool[pool_rp.pt].br_loop;

// ============================================================================================== //
// Error / Inc / Info
// ============================================================================================== //
  pep_seq_error_t       seq_errorD;
  pep_seq_info_t        seq_rif_infoD;
  pep_seq_counter_inc_t seq_rif_counter_incD;
  logic [LWE_K_W-1:0] ipip_flush_last_pbs_in_loop;
  logic [LWE_K_W-1:0] ipip_flush_last_pbs_in_loopD;

  logic [BATCH_PBS_NB-1:0] seq_rif_bpip_batch_filling_inc;
  // Use delayed signals to ease P&R
  logic                    ks_in_send_bpip_cmd_dly;
  logic [1:0]              ks_in_st_idle_sr;
  logic                    ks_in_do_update_bpip_dly;
  logic [PID_WW-1:0]       k0_new_ct_nb_dly;
  logic                    ks_in_timeout_reached_dly;
  logic                    k0_force_update_dly;
  logic [1:0]              ks_in_do_update_bpip_cond_sr;


  assign ipip_flush_last_pbs_in_loopD = pbs_send_st_send && pbs_in_cmd_flush ? pbs_in_loop : ipip_flush_last_pbs_in_loop;

  always_ff @(posedge clk)
    if (!s_rst_n) ipip_flush_last_pbs_in_loop <= '0;
    else          ipip_flush_last_pbs_in_loop <= ipip_flush_last_pbs_in_loopD;


  assign ks_in_send_bpip_cmd_dly = ks_in_st_idle_sr[0] & ks_in_do_update_bpip_dly;
  // To ease P&R, use delayed signals
  always_comb begin
    seq_rif_bpip_batch_filling_inc[BATCH_PBS_NB-1] = ks_in_send_bpip_cmd_dly & (k0_new_ct_nb_dly >= BATCH_PBS_NB);
    for (int i=0; i<BATCH_PBS_NB-1; i=i+1)
      seq_rif_bpip_batch_filling_inc[i] = ks_in_send_bpip_cmd_dly & (k0_new_ct_nb_dly == (i+1));
  end

  always_comb begin
    seq_errorD              = '0;
    seq_rif_infoD           = '0;

    seq_errorD.ks_enq_ovf   = ks_cmd_enq_error;
    seq_errorD.pbs_enq_ovf  = pbs_cmd_enq_error;

    seq_rif_infoD.br_loop_c = pbs_in_loop_c;
    seq_rif_infoD.br_loop   = pbs_in_loop;
    seq_rif_infoD.ks_loop_c = ks_in_loop_c;
    seq_rif_infoD.ks_loop   = ks_in_loop;
    seq_rif_infoD.pool_rp   = pool_rp;
    seq_rif_infoD.pool_wp   = pool_wp;
    seq_rif_infoD.ldg_pt    = ldg_pt;
    seq_rif_infoD.ldb_pt    = ldb_pt;
    seq_rif_infoD.ks_in_rp  = ks_in_rp;
    seq_rif_infoD.ks_in_wp  = ks_in_wp;
    seq_rif_infoD.ks_out_rp = ks_out_rp;
    seq_rif_infoD.ks_out_wp = ks_out_wp;
    seq_rif_infoD.pbs_in_rp = pbs_in_rp;
    seq_rif_infoD.pbs_in_wp = pbs_in_wp;
    seq_rif_infoD.ipip_flush_last_pbs_in_loop = ipip_flush_last_pbs_in_loop;

    seq_rif_counter_incD.load_ack_inc            = inst_load_blwe_ack;
    seq_rif_counter_incD.cmux_not_full_batch_inc = seq_pbs_cmd_avail & (seq_pbs_cmd_s.ct_nb_m1 != BATCH_PBS_NB-1);
    seq_rif_counter_incD.bpip_batch_inc          = ks_in_st_idle & ks_in_do_update_bpip;
    seq_rif_counter_incD.bpip_batch_timeout_inc  = ks_in_st_idle & ks_in_do_update_bpip & (k0_new_ct_nb < BATCH_PBS_NB) & ks_in_timeout_reached & ~k0_force_update;
    seq_rif_counter_incD.bpip_batch_flush_inc    = ks_in_st_idle & ks_in_do_update_bpip & (k0_new_ct_nb < BATCH_PBS_NB) & ~ks_in_timeout_reached & k0_force_update;
    seq_rif_counter_incD.bpip_batch_filling_inc  = seq_rif_bpip_batch_filling_inc;
  // BPIP : The conditions to start a batch were present, but not the trigger (full/timeout/force)
    seq_rif_counter_incD.bpip_waiting_batch_inc  = ks_in_send_bpip_cmd_dly & ks_in_do_update_bpip_cond_sr[1] & ks_in_st_idle_sr[1];
    seq_rif_counter_incD.ipip_flush_inc          = pbs_send_st_send & pbs_in_cmd_flush;
  end

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      seq_error                    <= '0;
      seq_rif_info                 <= '0;
      seq_rif_counter_inc          <= '0;

      ks_in_st_idle_sr             <= '0;
      ks_in_do_update_bpip_dly     <= 1'b0;
      ks_in_do_update_bpip_cond_sr <= '0;
    end
    else begin
      seq_error                    <= seq_errorD;
      seq_rif_info                 <= seq_rif_infoD;
      seq_rif_counter_inc          <= seq_rif_counter_incD;

      ks_in_st_idle_sr             <= {ks_in_st_idle_sr[0],ks_in_st_idle};
      ks_in_do_update_bpip_dly     <= ks_in_do_update_bpip;
      ks_in_do_update_bpip_cond_sr <= {ks_in_do_update_bpip_cond_sr[0],ks_in_do_update_bpip_cond};
    end

  always_ff @(posedge clk) begin
    k0_new_ct_nb_dly          <= k0_new_ct_nb;
    ks_in_timeout_reached_dly <= ks_in_timeout_reached;
    k0_force_update_dly       <= k0_force_update;
  end

// ============================================================================================== //
// Reset cache part2
// ============================================================================================== //
  assign reset_clear_busy = (seq_ks_latest_in_rp != ks_out_rp)
                          | (seq_ks_latest_in_wp != ks_out_wp)
                          | (seq_ks_latest_max_in_loop != ks_out_loop)
                          | ks_res_vld;

// ============================================================================================== //
// Send correction.
// ============================================================================================== //
// Map containing the corrections is available when pbs_send_st_wrap = 1.
// The correction is in r1_corr_map;
// Store the correction in a buffer. Send 1 correction per cycle.
  corr_elt_t [CORR_BUF_DEPTH-1:0][RANK_NB*GRAM_NB-1:0] corr_buffer;
  logic      [CORR_BUF_DEPTH-1:0]                      corr_buffer_avail;
  corr_elt_t [RANK_NB*GRAM_NB-1:0]                     corr_sr;
  logic      [RANK_NB*GRAM_NB-1:0]                     corr_sr_avail;

  corr_elt_t [CORR_BUF_DEPTH-1:0][RANK_NB*GRAM_NB-1:0] corr_bufferD;
  logic      [CORR_BUF_DEPTH-1:0]                      corr_buffer_availD;
  corr_elt_t [RANK_NB*GRAM_NB-1:0]                     corr_srD;
  logic      [RANK_NB*GRAM_NB-1:0]                     corr_sr_availD;

  logic      [CORR_BUF_DEPTH-1:0]                      corr_buffer_do_shift;
  logic      [CORR_BUF_DEPTH-1:-1]                     corr_buffer_do_shift_ext;
  logic                                                corr_sr_do_sample;

  logic      [CORR_BUF_DEPTH:0]                        corr_buffer_avail_ext;
  corr_elt_t [CORR_BUF_DEPTH:0][RANK_NB*GRAM_NB-1:0]   corr_buffer_ext;

  // Do not send correction when processing flush
  assign corr_buffer_avail_ext = {pbs_send_st_wrap & ~pbs_in_cmd_flush, corr_buffer_avail};
  assign corr_buffer_ext       = {r1_corr_map, corr_buffer};
  assign corr_buffer_do_shift_ext = {corr_buffer_do_shift,corr_sr_do_sample};

  always_comb
    for (int i=0; i<CORR_BUF_DEPTH; i=i+1)
      corr_buffer_do_shift[i] = ~corr_buffer_avail[i] & corr_buffer_avail_ext[i+1];

  // Note: there is no need to rush here: wait for the sr to be empty
  // before reloading it.
  assign corr_sr_do_sample    = corr_sr_avail == '0;
  assign corr_buffer_free_loc = ~corr_buffer_avail[CORR_BUF_DEPTH-1];

  // avail field is not used here. Will be simplified by the synthesizer.
  assign corr_srD = (corr_sr_do_sample && corr_buffer_avail[0]) ? corr_buffer[0] : // sample
                    corr_sr_avail != '0 ? {CORR_ELT_W'(0), corr_sr[RANK_NB*GRAM_NB-1:1]}: // shift
                    corr_sr;

  always_comb
    for (int i=0; i<RANK_NB*GRAM_NB; i=i+1)
      corr_sr_availD[i] = (corr_sr_do_sample && corr_buffer_avail[0]) ? corr_buffer[0][i].avail : // sample
                          corr_sr_avail != '0 ? i == RANK_NB*GRAM_NB-1 ? 1'b0 : corr_sr[i+1].avail: // shift
                          corr_sr_avail[i];

  always_comb
    for (int i=0; i<CORR_BUF_DEPTH; i=i+1) begin
      corr_buffer_availD[i] = corr_buffer_do_shift[i] ? corr_buffer_avail_ext[i+1] :
                              corr_buffer_do_shift_ext[i-1] ? 1'b0 :
                              corr_buffer_avail[i];
      corr_bufferD[i]       = corr_buffer_do_shift[i] ? corr_buffer_ext[i+1] :
                              corr_buffer[i];
    end

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      corr_sr_avail     <= '0;
      corr_buffer_avail <= '0;
    end
    else begin
      corr_sr_avail     <= corr_sr_availD    ;
      corr_buffer_avail <= corr_buffer_availD;
    end

  always_ff @(posedge clk) begin
    corr_buffer <= corr_bufferD;
    corr_sr     <= corr_srD;
  end

  // Send correction
  logic                        seq_boram_corr_wr_enD;
  logic [KS_CORR_W-1:0]        seq_boram_corr_dataD;
  logic [PID_W-1:0]            seq_boram_corr_pidD;

  assign seq_boram_corr_wr_enD = corr_sr_avail[0];
  assign seq_boram_corr_dataD  = corr_sr[0].corr;
  assign seq_boram_corr_pidD   = corr_sr[0].pid;

  always_ff @(posedge clk)
    if (!s_rst_n) seq_boram_corr_wr_en <= 1'b0;
    else          seq_boram_corr_wr_en <= seq_boram_corr_wr_enD;

  always_ff @(posedge clk) begin
    seq_boram_corr_data <= seq_boram_corr_dataD;
    seq_boram_corr_pid  <= seq_boram_corr_pidD;
  end

// ============================================================================================== //
// Assertion
// ============================================================================================== //
// pragma translate_off
  always_ff @(posedge clk)
    if (reset_loop) begin
      for (int i=0; i<TOTAL_PBS_NB; i=i+1) begin
        assert(ct_pool[i].avail == 0)
        else begin
          $fatal(1,"%t > ERROR: Reset cache when pep_sequencer ct_pool is not empty [%0d] is still available.",$time, i);
        end
      end
    end
// pragma translate_on

endmodule
