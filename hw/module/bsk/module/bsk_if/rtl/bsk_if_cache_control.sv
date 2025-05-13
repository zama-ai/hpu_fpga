// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : bsk interface
// ----------------------------------------------------------------------------------------------
//
// Handle the bsk_manager buffer as a cache.
// Load from DDR through AXI4 interface.
//
// ==============================================================================================

module bsk_if_cache_control
  import param_tfhe_pkg::*;
  import pep_common_param_pkg::*;
  import bsk_mgr_common_param_pkg::*;
  import bsk_if_common_param_pkg::*;
(
    input  logic                                    clk,        // clock
    input  logic                                    s_rst_n,    // synchronous reset

    // bsk available in DDR. Ready to be ready through AXI
    // From configuration register
    // Quasi static signals
    input  logic                                    bsk_mem_avail,

    // Reset the cache
    input  logic                                    reset_cache,
    output logic                                    reset_cache_done,

    // batch start
    input  logic [TOTAL_BATCH_NB-1:0]               batch_start_1h, // One-hot : can only start 1 at a time.

    // bsk pointer for the KS process path
    output logic [TOTAL_BATCH_NB-1:0]               inc_bsk_wr_ptr, // Indicate that the bsk slice is available
    input  logic [TOTAL_BATCH_NB-1:0]               inc_bsk_rd_ptr, // Indicate that the bsk slice has been consumed

    // bsk_if_axi4_read
    output logic                                    cctrl_rd_vld,
    input  logic                                    cctrl_rd_rdy,
    output logic [BSK_READ_CMD_W-1:0]               cctrl_rd_cmd,
    input  logic                                    rd_cctrl_slot_done, // bsk slice read from mem
    input  logic [BSK_SLOT_W-1:0]                   rd_cctrl_slot_id,

    // Info for rif
    output bskif_info_t                             bskif_rif_info
);

// ============================================================================================== //
// localparam
// ============================================================================================== //
// Share the slots between the running batches
  localparam int PREFETCH_MAX_TMP = BSK_SLOT_NB / BATCH_NB; // More efficient occupancy if BSK_SLOT_NB is a multiple of BATCH_NB
  localparam int PREFETCH_MAX     = LWE_K < PREFETCH_MAX_TMP ? LWE_K : PREFETCH_MAX_TMP;
  localparam int PREFETCH_WW      = $clog2(PREFETCH_MAX+1) == 0 ? 1 : $clog2(PREFETCH_MAX+1); // Count from 0 to PREFETCH_MAX included

  localparam int RFIFO_DEPTH      = 4; // TOREVIEW

// ============================================================================================== //
// type
// ============================================================================================== //
  typedef enum bit[1:0] {
    SLOT_EMPTY = 0,
    SLOT_FILL,
    SLOT_WIP
  } slot_status_e;

  typedef struct packed {
    logic                      assigned;
    logic                      parity;
    logic [TOTAL_BATCH_NB-1:0] batch_id_1h;
    logic [PREFETCH_WW-1:0]    prefetch_cnt;
    logic [LWE_K_W:0]          prf_br_loop; // br_loop to be loaded
    logic [LWE_K_W:0]          br_loop_wp;  // br_loop for KS
    logic [LWE_K_W:0]          br_loop_rp;  // br_loop processed
  } req_t;

  typedef struct packed {
    logic [LWE_K_W-1:0]        br_loop;
    slot_status_e              status;
    logic [BATCH_NB-1:0]       lock_mh;
    logic [BSK_SLOT_W-1:0]     slot_id;
  } cache_info_t;

  typedef struct packed {
    logic [LWE_K_W-1:0]        br_loop;
    logic [BATCH_NB-1:0]       req_id_1h;
  } cin_cmd_t;

// ============================================================================================== //
// Signals
// ============================================================================================== //
  req_t        [BATCH_NB-1:0]    req_a;
  cache_info_t [BSK_SLOT_NB-1:0] cinfo_a;

// ============================================================================================== //
// Info
// ============================================================================================== //
  bskif_info_t bskif_rif_infoD;

  always_comb begin
    bskif_rif_infoD = '0;
    bskif_rif_infoD.req_assigned    = req_a[0].assigned;
    bskif_rif_infoD.req_parity      = req_a[0].parity;
    bskif_rif_infoD.req_prf_br_loop = req_a[0].prf_br_loop;
    bskif_rif_infoD.req_br_loop_wp  = req_a[0].br_loop_wp;
    bskif_rif_infoD.req_br_loop_rp  = req_a[0].br_loop_rp;
  end

  always_ff @(posedge clk)
    if (!s_rst_n) bskif_rif_info <= '0;
    else          bskif_rif_info <= bskif_rif_infoD;

// ============================================================================================== //
// Input pipe
// ============================================================================================== //
  logic [TOTAL_BATCH_NB-1: 0] s0_inc_bsk_rd_ptr;
  logic [TOTAL_BATCH_NB-1:0]  s0_batch_start_1h;
  logic                       s0_rd_cctrl_slot_done;
  logic [BSK_SLOT_W-1:0]      s0_rd_cctrl_slot_id;
  logic                       s0_reset_cache;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      s0_inc_bsk_rd_ptr     <= '0;
      s0_batch_start_1h     <= '0;
      s0_rd_cctrl_slot_done <= '0;
      s0_reset_cache        <= 1'b0;
    end
    else begin
      s0_inc_bsk_rd_ptr     <= inc_bsk_rd_ptr;
      s0_batch_start_1h     <= batch_start_1h;
      s0_rd_cctrl_slot_done <= rd_cctrl_slot_done;
      s0_reset_cache        <= reset_cache;
    end

  always_ff @(posedge clk)
    s0_rd_cctrl_slot_id <= rd_cctrl_slot_id;

// ============================================================================================== //
// Reset cache
// ============================================================================================== //
// During the sw reset of the cache,
// * We assume that there is no pending batch
// * The requesters are not allowed to generate new commands
// * Wait for the pending Memory commands to be back
// * Once the cinfo status of all slots is FILL or EMPTY, reset the cache registers.
// * Trigger the done signal for the SW
  logic s0_reset_cache_dly;
  logic do_clear_cache;
  logic do_clear_cacheD;
  logic clear_cache_done;
  logic trigger_clear_cache;

  // Trigger the reset of the cache at posedge of s0_reset_cache
  // Maintain it until the done is received.
  assign do_clear_cacheD = (s0_reset_cache && !s0_reset_cache_dly) ? 1'b1 :
                           clear_cache_done                        ? 1'b0 : do_clear_cache;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      s0_reset_cache_dly <= 1'b0;
      do_clear_cache     <= 1'b0;
    end
    else begin
      s0_reset_cache_dly <= s0_reset_cache;
      do_clear_cache     <= do_clear_cacheD;
    end

// ============================================================================================== --
// Command queue
// ============================================================================================== --
  // To keep track of the order of batches that have been started
  // Only 1 batch is started at a time.
  logic                      qfifo_in_vld;
  logic                      qfifo_in_rdy;
  logic                      qfifo_out_vld;
  logic                      qfifo_out_rdy;
  logic [TOTAL_BATCH_NB-1:0] qfifo_out_start_1h;

  assign qfifo_in_vld      = |s0_batch_start_1h;

  fifo_reg #(
   .WIDTH       (TOTAL_BATCH_NB),
   .DEPTH       (TOTAL_BATCH_NB),
   .LAT_PIPE_MH ({1'b1, 1'b1})
  ) queue_fifo (
    .clk      (clk),
    .s_rst_n  (s_rst_n),

    .in_data  (s0_batch_start_1h),
    .in_vld   (qfifo_in_vld),
    .in_rdy   (qfifo_in_rdy),

    .out_data (qfifo_out_start_1h),
    .out_vld  (qfifo_out_vld),
    .out_rdy  (qfifo_out_rdy)
  );

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      if (qfifo_in_vld) begin
        assert(qfifo_in_rdy)
        else begin
          $fatal(1,"%t > ERROR: queue_fifo overflow!", $time);
        end
      end

      if (do_clear_cache) begin
        assert(qfifo_in_vld == 1'b0)
        else begin
          $fatal(1,"%t > ERROR: New batch received, while the BSK cache is being reset.", $time);
        end
      end
    end
// pragma translate_on

// ============================================================================================== //
// External update signals
// ============================================================================================== //
  //-------------------------
  //== bsk slice process done
  //-------------------------
  logic [BATCH_NB-1:0]       upd_req_br_loop_rp_1h;
  logic [BATCH_NB_W-1:0]     upd_req_br_loop_rp;
  logic [BATCH_NB-1:0]       upd_req_assigned_1h;

  // Once identified among the requestors, broadcast the update to the cache info : rbdc
  logic [LWE_K_W-1:0]        rbdc_br_loop;
  logic [BATCH_NB-1:0]       rbdc_req_id_1h;
  logic [LWE_K_W-1:0]        rbdc_br_loopD;
  logic [BATCH_NB-1:0]       rbdc_req_id_1hD;
  logic                      rbdc_avail;
  logic                      rbdc_availD;
  logic [BSK_SLOT_NB-1:0]    upd_pos_lock_1h;


  always_comb
    for (int i=0; i<BATCH_NB; i=i+1) begin
      upd_req_br_loop_rp_1h[i] = req_a[i].assigned & (req_a[i].batch_id_1h == s0_inc_bsk_rd_ptr);
      upd_req_assigned_1h[i]   = upd_req_br_loop_rp_1h[i] & (req_a[i].br_loop_rp[LWE_K_W-1:0] == LWE_K-1);
    end

  common_lib_one_hot_to_bin #(
    .ONE_HOT_W (BATCH_NB)
  ) upd_req_one_hot_to_bin(
    .in_1h     (upd_req_br_loop_rp_1h),
    .out_value (upd_req_br_loop_rp)
  );

  assign rbdc_br_loopD    = req_a[upd_req_br_loop_rp].br_loop_rp[LWE_K_W-1:0];
  assign rbdc_req_id_1hD  = upd_req_br_loop_rp_1h;
  assign rbdc_availD      = |s0_inc_bsk_rd_ptr;

  always_comb
    for (int i=0; i<BSK_SLOT_NB; i=i+1)
      upd_pos_lock_1h[i] = rbdc_avail & (rbdc_br_loop == cinfo_a[i].br_loop) & (cinfo_a[i].status == SLOT_FILL);

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      rbdc_req_id_1h  <= '0;
      rbdc_avail      <= 1'b0;
    end
    else begin
      rbdc_req_id_1h  <= rbdc_req_id_1hD;
      rbdc_avail      <= rbdc_availD;
    end

  always_ff @(posedge clk)
    rbdc_br_loop <= rbdc_br_loopD;

  //-------------------------
  //== bsk slice load done
  //-------------------------
  logic [BSK_SLOT_NB-1:0] upd_pos_status_1h;

  always_comb
    for (int i=0; i<BSK_SLOT_NB; i=i+1) begin
      upd_pos_status_1h[i] = s0_rd_cctrl_slot_done & (cinfo_a[i].slot_id == s0_rd_cctrl_slot_id);
    end

  //== Query
  // The requestors ask the cache info for an update.
  // The answer is broadcasted.
  //== Question the cache info
  logic                      qin_avail;
  logic [LWE_K_W-1:0]        qin_br_loop;
  logic [BATCH_NB-1:0]       qin_req_id_1h;
  logic [BSK_SLOT_NB-1:0]    qin_pos;

  always_comb
    for (int i=0; i<BSK_SLOT_NB; i=i+1)
      qin_pos[i] = (cinfo_a[i].br_loop == qin_br_loop)
                  & (cinfo_a[i].status == SLOT_FILL)
                  & |(cinfo_a[i].lock_mh & qin_req_id_1h);
  // Check that the slot has been locked by the current requestor.
  // Indeed this is necessary to avoid any race condition between the
  // requests.

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      if (qin_avail)
        assert($countones(qin_pos) <= 1)
        else begin
          $fatal(1,"%t > ERROR: query hit more than 1 slot !",$time);
        end
    end
// pragma translate_on

  //== Broadcast
  logic                      qbdc_avail;
  logic [BATCH_NB-1:0]       qbdc_req_id_1h;
  logic [LWE_K_W-1:0]        qbdc_br_loop;
  logic [BATCH_NB-1:0]       upd_req_br_loop_wp_1h;
  logic [BATCH_NB-1:0]       upd_req_br_loop_wp_1hD;

  always_ff @(posedge clk)
    if (!s_rst_n) qbdc_avail <= 1'b0;
    else          qbdc_avail <= |qin_pos & qin_avail;

  always_ff @(posedge clk) begin
    qbdc_req_id_1h <= qin_req_id_1h;
    qbdc_br_loop   <= qin_br_loop;
  end

  // Check that the broadcast concerns the current requestor.
  // The check with the br_loop is used to discard eventual
  // duplicate query, that has already been solved.

  always_comb
    for (int i=0; i<BATCH_NB; i=i+1)
      upd_req_br_loop_wp_1hD[i] = qbdc_avail
                              & qbdc_req_id_1h[i]
                              & (qbdc_br_loop == req_a[i].br_loop_wp[LWE_K_W-1:0])
                              & req_a[i].assigned
                              & req_a[i].parity == req_a[i].br_loop_wp[LWE_K_W];

  always_ff @(posedge clk)
    if (!s_rst_n) upd_req_br_loop_wp_1h <= 1'b0;
    else          upd_req_br_loop_wp_1h <= upd_req_br_loop_wp_1hD;

// ============================================================================================== //
// Requestor
// ============================================================================================== //
// Once the bsk is available in memory (bsk_mem_avail), the resquestors start to work.
// There are as many requestors as the number of interleaved batches that are processed in the
// processing path.
// Each requestor will prefetch the bsk slice that will be needed.
// When a batch is started, a requestor is associated to it.
  req_t [BATCH_NB-1:0]                     req_aD;
  req_t [BATCH_NB-1:0]                     req_a_upd;

  logic [BATCH_NB-1:0][PREFETCH_WW-1:0]    req_prefetch_cntD;
  logic [BATCH_NB-1:0]                     req_assignedD;
  logic [BATCH_NB-1:0][TOTAL_BATCH_NB-1:0] req_batch_id_1hD;
  logic [BATCH_NB-1:0][LWE_K_W:0]          req_prf_br_loopD;
  logic [BATCH_NB-1:0][LWE_K_W:0]          req_br_loop_wpD;
  logic [BATCH_NB-1:0][LWE_K_W:0]          req_br_loop_rpD;
  logic [BATCH_NB-1:0]                     req_parityD;

  always_comb
    for (int i=0; i<BATCH_NB; i=i+1) begin
      req_aD[i].prefetch_cnt = req_prefetch_cntD[i];
      req_aD[i].assigned     = req_assignedD[i];
      req_aD[i].parity       = req_parityD[i];
      req_aD[i].batch_id_1h  = req_batch_id_1hD[i];
      req_aD[i].prf_br_loop  = req_prf_br_loopD[i];
      req_aD[i].br_loop_wp   = req_br_loop_wpD[i];
      req_aD[i].br_loop_rp   = req_br_loop_rpD[i];
    end

  always_ff @(posedge clk)
    if (!s_rst_n || trigger_clear_cache) begin
      for (int i=0; i<BATCH_NB; i=i+1) begin
        req_a[i]        <= '0;
        req_a[i].parity <= 1'b1;
      end
    end
    else begin
      req_a <= req_aD;
    end

  logic [BATCH_NB-1:0] req_prf_br_loop_empty;
  logic [BATCH_NB-1:0] req_prf_br_loop_full;
  always_comb
    for (int i=0; i<BATCH_NB; i=i+1) begin
      req_prf_br_loop_empty[i] = req_a[i].prf_br_loop == req_a[i].br_loop_wp;
      req_prf_br_loop_full[i]  = req_a[i].prf_br_loop == {~req_a[i].br_loop_wp[LWE_K_W],req_a[i].br_loop_wp[LWE_K_W-1:0]};
    end

  always_comb
    for (int i=0; i<BATCH_NB; i=i+1) begin
      req_a_upd[i] = req_a[i];
      req_a_upd[i].prefetch_cnt = upd_req_br_loop_rp_1h[i] ? req_a[i].prefetch_cnt - 1 : req_a[i].prefetch_cnt;
      req_a_upd[i].br_loop_wp   = upd_req_br_loop_wp_1h[i] ?
                                    req_a[i].br_loop_wp[LWE_K_W-1:0] == LWE_K-1 ? {~req_a[i].br_loop_wp[LWE_K_W],{LWE_K_W{1'b0}}}:
                                    req_a[i].br_loop_wp + 1 : req_a[i].br_loop_wp;
      req_a_upd[i].br_loop_rp   = upd_req_br_loop_rp_1h[i] ?
                                    req_a[i].br_loop_rp[LWE_K_W-1:0] == LWE_K-1 ? {~req_a[i].br_loop_rp[LWE_K_W],{LWE_K_W{1'b0}}}:
                                    req_a[i].br_loop_rp + 1 : req_a[i].br_loop_rp;
      req_a_upd[i].assigned     = upd_req_assigned_1h[i] ? 1'b0 : req_a[i].assigned;
    end


  //-------------------------
  // Prefetch
  //-------------------------
  logic [BATCH_NB-1:0]   req_vld;
  logic [BATCH_NB-1:0]   req_rdy;

  always_comb
    for (int i=0; i<BATCH_NB; i=i+1) begin
      req_vld[i]           = ~do_clear_cache & bsk_mem_avail & (req_a[i].prefetch_cnt < PREFETCH_MAX) & ~req_prf_br_loop_full[i];
      req_prefetch_cntD[i] = req_vld[i] && req_rdy[i] ? req_a_upd[i].prefetch_cnt + 1 : req_a_upd[i].prefetch_cnt;
      req_prf_br_loopD[i]  = req_vld[i] && req_rdy[i] ?
                             req_a_upd[i].prf_br_loop[LWE_K_W-1:0] == LWE_K-1 ? {~req_a_upd[i].prf_br_loop[LWE_K_W],{LWE_K_W{1'b0}}}:
                             req_a_upd[i].prf_br_loop + 1 : req_a_upd[i].prf_br_loop;
    end


  //-------------------------
  // Assignment
  //-------------------------
  logic [BATCH_NB-1:0] req_assigned;
  logic [BATCH_NB-1:0] req_assign_1h;

  always_comb
    for (int i=0; i<BATCH_NB; i=i+1) begin
      req_assigned[i]     = req_a_upd[i].assigned;
      req_assignedD[i]    = qfifo_out_vld && req_assign_1h[i] ? 1'b1 : req_assigned[i];
      req_parityD[i]      = qfifo_out_vld && req_assign_1h[i] ? ~req_a_upd[i].parity : req_a_upd[i].parity;
      req_batch_id_1hD[i] = qfifo_out_vld && req_assign_1h[i] ? qfifo_out_start_1h : req_a_upd[i].batch_id_1h;
    end

  assign qfifo_out_rdy = |(~req_assigned);

  common_lib_find_first_bit_equal_to_1
  #(
    .NB_BITS(BATCH_NB)
  ) req_find_first_bit_equal_to_1 (
    .in_vect_mh          (~req_assigned),
    .out_vect_1h         (req_assign_1h),
    .out_vect_ext_to_msb (/*UNUSED*/)
  );

  //-------------------------
  // Update bsk pointer
  //-------------------------
  logic [TOTAL_BATCH_NB-1:0] inc_bsk_wr_ptrD;

  always_comb begin
    inc_bsk_wr_ptrD = '0;
    for (int i=0; i<BATCH_NB; i=i+1) begin
      req_br_loop_wpD[i] = req_a_upd[i].br_loop_wp;
      req_br_loop_rpD[i] = req_a_upd[i].br_loop_rp;

      inc_bsk_wr_ptrD = inc_bsk_wr_ptrD | ({TOTAL_BATCH_NB{upd_req_br_loop_wp_1h[i]}} & req_a_upd[i].batch_id_1h);
    end
  end

  always_ff @(posedge clk)
    if (!s_rst_n) inc_bsk_wr_ptr   <= '0;
    else          inc_bsk_wr_ptr   <= inc_bsk_wr_ptrD;

// ============================================================================================== //
// Request Arbiter
// ============================================================================================== //
// No need to rush here.
// We implement a simple round-robin.
// If BATCH_NB == 1, arbiter 1 cycle over 2
  logic [BATCH_NB-1:0]       arb_sel_1h;
  logic [BATCH_NB:0]         arb_sel_1h_rot;
  logic [BATCH_NB-1:0]       arb_sel_1hD;
  logic [BATCH_NB_W-1:0]     arb_sel;
  logic                      arb_vld;
  logic                      arb_rdy;
  logic [LWE_K_W-1:0]        arb_prf_br_loop;
  logic                      arb_mask; // Used when BATCH_NB == 1

  common_lib_one_hot_to_bin #(
    .ONE_HOT_W (BATCH_NB)
  ) arb_one_hot_to_bin(
    .in_1h     (arb_sel_1h),
    .out_value (arb_sel)
  );

  assign arb_sel_1h_rot  = {arb_sel_1h[BATCH_NB-1:0],arb_sel_1h[BATCH_NB-1]};
  assign req_rdy         = arb_sel_1h & {BATCH_NB{arb_rdy}};
  assign arb_vld         = |(arb_sel_1h & req_vld) & ~arb_mask;
  assign arb_prf_br_loop = req_a[arb_sel].prf_br_loop[LWE_K_W-1:0];
  assign arb_sel_1hD     = (!arb_vld || arb_rdy) ? arb_sel_1h_rot[BATCH_NB-1:0] : arb_sel_1h;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      arb_sel_1h <= 1;
      arb_mask   <= 1'b0;
    end
    else begin
      arb_sel_1h <= arb_sel_1hD;
      arb_mask   <= arb_vld & arb_rdy & (BATCH_NB == 1);
    end

  cin_cmd_t                  arb_cmd;
  cin_cmd_t                  cin_cmd;
  logic                      cin_vld;
  logic                      cin_rdy;

  assign arb_cmd.br_loop     = arb_prf_br_loop;
  assign arb_cmd.req_id_1h   = arb_sel_1h;

  // Use a type 3 : no need to rush.
  fifo_element #(
    .WIDTH          ($bits(cin_cmd_t)),
    .DEPTH          (1), // Keep this depth - for the cache reset
    .TYPE_ARRAY     (3),
    .DO_RESET_DATA  (1'b0),
    .RESET_DATA_VAL (0)
  ) cin_fifo_element (
    .clk     (clk),
    .s_rst_n (s_rst_n),

    .in_data (arb_cmd),
    .in_vld  (arb_vld),
    .in_rdy  (arb_rdy),

    .out_data(cin_cmd),
    .out_vld (cin_vld),
    .out_rdy (cin_rdy)
  );

// ============================================================================================== //
// Cache info
// ============================================================================================== //
  cache_info_t [BSK_SLOT_NB-1:0] cinfo_aD;
  cache_info_t [BSK_SLOT_NB-1:0] cinfo_a_upd;

  always_comb
    for (int i=0; i<BSK_SLOT_NB; i=i+1) begin
      cinfo_a_upd[i] = cinfo_a[i];
      cinfo_a_upd[i].status  = upd_pos_status_1h[i] ? SLOT_FILL : cinfo_a[i].status;
      cinfo_a_upd[i].lock_mh = upd_pos_lock_1h[i]   ? rbdc_req_id_1h ^ cinfo_a[i].lock_mh : cinfo_a[i].lock_mh;
    end

  always_ff @(posedge clk)
    if (!s_rst_n || trigger_clear_cache) begin
      for (int i=0; i<BSK_SLOT_NB; i=i+1) begin
        cinfo_a[i]         <= '0;
        cinfo_a[i].slot_id <= i; // initialize slot_id
      end
    end
    else
      cinfo_a <= cinfo_aD;

  //-------------------------
  // Control
  //-------------------------
  // Use several cycles to update the cache info.
  // Indeed there is no need to rush here.
  // During the first state identify the hit/miss status of the command.
  // During the second state retrieve the slot
  // During the third state, update the slot.
  // Note that if the output FIFO is not ready, the process is stalled.

  typedef enum integer {
    ST_XXX = 'x,
    ST_HIT_MISS = 0,
    ST_UPDATE,
    ST_SEND
  } cin_state_e;

  cin_state_e cin_state;
  cin_state_e next_cin_state;
  logic       cin_st_hit_miss;
  logic       cin_st_update;
  logic       cin_st_send;

  logic       cout_vld;
  logic       cout_rdy;

  always_comb begin
    next_cin_state = ST_XXX; // default
    case (cin_state)
      ST_HIT_MISS:
        next_cin_state = (cin_vld && cout_rdy) ? ST_UPDATE : cin_state; // Output fifo is not full and input command is valid
      ST_UPDATE:
        next_cin_state = ST_SEND;
      ST_SEND:
        next_cin_state = ST_HIT_MISS;
    endcase
  end

  always_ff @(posedge clk)
    if (!s_rst_n) cin_state <= ST_HIT_MISS;
    else          cin_state <= next_cin_state;

  assign cin_st_hit_miss      = cin_state == ST_HIT_MISS;
  assign cin_st_update        = cin_state == ST_UPDATE;
  assign cin_st_send          = cin_state == ST_SEND;

  //-------------------------
  // c0 : hit / miss
  //-------------------------
  logic                   c0_miss;
  logic [BSK_SLOT_NB-1:0] c0_hit;

  assign c0_miss = ~(|c0_hit);

  // There is a hit either
  // * if the bsk slice is already present (SLOT_FILL)
  // * or the bsk slice is currently being loaded (SLOT_WIP)
  // In both cases, we do not need to read the bsk slice from memory.
  always_comb
    for (int i=0; i<BSK_SLOT_NB; i=i+1)
      c0_hit[i] = (cinfo_a[i].br_loop == cin_cmd.br_loop) & (cinfo_a[i].status != SLOT_EMPTY);

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      assert($countones(c0_hit) <= 1)
      else begin
        $fatal(1,"%t > ERROR: Hit in several locations!", $time);
      end
    end
// pragma translate_on
  //== Hit
  logic [BSK_SLOT_NB-1:0] c0_hit_lock_1h;

  assign c0_hit_lock_1h = {BSK_SLOT_NB{cin_st_hit_miss}} & c0_hit;

  //== Miss
  // Note that prefetch mechanism is a simple one.
  // Each requestor never exceeds SLOT/BATCH_NB requests.
  // When a request is sent, a there must be a free slot.
  logic [BSK_SLOT_NB-1:0] c0_miss_lock_1h;
  logic [BSK_SLOT_NB-1:0] c0_miss_lock_1h_tmp;
  logic [BSK_SLOT_NB-1:0] c0_free_slot_mh;

  always_comb
    for (int i=0; i<BSK_SLOT_NB; i=i+1)
      c0_free_slot_mh[i] = (cinfo_a[i].status != SLOT_WIP) & (cinfo_a[i].lock_mh == 0);

  common_lib_find_first_bit_equal_to_1
  #(
    .NB_BITS(BSK_SLOT_NB)
  ) c0_find_first_bit_equal_to_1 (
    .in_vect_mh          (c0_free_slot_mh),
    .out_vect_1h         (c0_miss_lock_1h_tmp),
    .out_vect_ext_to_msb (/*UNUSED*/)
  );

  assign c0_miss_lock_1h = {BSK_SLOT_NB{cin_st_hit_miss & c0_miss}}  & c0_miss_lock_1h_tmp;

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      assert(!(cin_vld & cin_st_hit_miss & c0_miss) || |c0_free_slot_mh)
      else begin
        $fatal(1,"%t > ERROR: No available free slot for a miss request!",$time);
      end
    end
// pragma translate_on

  logic [BSK_SLOT_NB-1:0] c0_lock_1h;
  assign c0_lock_1h = c0_hit_lock_1h | c0_miss_lock_1h;

  //-------------------------
  // c1 : update
  //-------------------------
  logic [BSK_SLOT_NB-1:0] c1_hit_lock_1h;
  logic [BSK_SLOT_NB-1:0] c1_miss_lock_1h;
  logic [BSK_SLOT_NB-1:0] c1_lock_1h;
  logic [BSK_SLOT_W-1:0]  c1_pos;
  logic                   c1_miss;
  cache_info_t            c1_cinfo;
  cache_info_t            c1_cinfo_upd;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      c1_hit_lock_1h  <= '0;
      c1_miss_lock_1h <= '0;
      c1_lock_1h      <= '0;
      c1_miss         <= 1'b0;
    end
    else begin
      c1_hit_lock_1h  <= c0_hit_lock_1h ;
      c1_miss_lock_1h <= c0_miss_lock_1h;
      c1_lock_1h      <= c0_lock_1h;
      c1_miss         <= c0_miss;
    end

  assign c1_cinfo = cinfo_a_upd[c1_pos];

  always_comb begin
    c1_cinfo_upd             = c1_cinfo;
    c1_cinfo_upd.status      = c1_miss ? SLOT_WIP : c1_cinfo.status;
    c1_cinfo_upd.br_loop     = c1_miss ? cin_cmd.br_loop : c1_cinfo.br_loop;
    c1_cinfo_upd.lock_mh     = cin_cmd.req_id_1h | c1_cinfo.lock_mh;
  end

  common_lib_one_hot_to_bin #(
    .ONE_HOT_W (BSK_SLOT_NB)
  ) c1_one_hot_to_bin (
    .in_1h     (c1_lock_1h),
    .out_value (c1_pos)
  );

  // Change positions, so that the MRU is at [BSK_SLOT_NB-1] position.
  logic [BSK_SLOT_NB-1:0] c1_pos_move;

  common_lib_find_first_bit_equal_to_1
  #(
    .NB_BITS(BSK_SLOT_NB)
  ) c1_find_first_bit_equal_to_1 (
    .in_vect_mh          (c1_lock_1h),
    .out_vect_1h         (/*UNUSED*/),
    .out_vect_ext_to_msb (c1_pos_move)
  );

  //== Update cinfo_a
  always_comb begin
    for (int i=0; i<BSK_SLOT_NB-1; i=i+1) begin
      cinfo_aD[i] = cin_st_update && c1_pos_move[i] ? cinfo_a_upd[i+1] : cinfo_a_upd[i];
    end
    cinfo_aD[BSK_SLOT_NB-1] = cin_st_update ? c1_cinfo_upd : cinfo_a_upd[BSK_SLOT_NB-1];
  end


  bsk_read_cmd_t c1_cout_cmd;
  bsk_read_cmd_t c2_cout_cmd;

  assign c1_cout_cmd.slot_id     = c1_cinfo.slot_id;
  assign c1_cout_cmd.br_loop     = cin_cmd.br_loop;

  //-------------------------
  // c2 : Send
  //-------------------------
  logic c2_miss;

  always_ff @(posedge clk)
    if (!s_rst_n) c2_miss <= 1'b0;
    else          c2_miss <= c1_miss;

  always_ff @(posedge clk)
    c2_cout_cmd <= c1_cout_cmd;

  //== FIFO
  // Store read command in a FIFO

  assign cout_vld             = cin_st_send & c2_miss;
  assign cin_rdy              = cin_st_send;

  fifo_reg #(
   .WIDTH       (BSK_READ_CMD_W),
   .DEPTH       (RFIFO_DEPTH),
   .LAT_PIPE_MH ({1'b1, 1'b1})
  ) read_fifo (
    .clk      (clk),
    .s_rst_n  (s_rst_n),

    .in_data  (c2_cout_cmd),
    .in_vld   (cout_vld),
    .in_rdy   (cout_rdy),

    .out_data (cctrl_rd_cmd),
    .out_vld  (cctrl_rd_vld),
    .out_rdy  (cctrl_rd_rdy)
  );

// ============================================================================================== //
// Query
// ============================================================================================== //
  // In order to avoid several comparison trees, we
  // use a "query" system.
  // The requestor asks for some news about the br_loop they have to send (br_loop_wp)
  // The cache_info answers with a broadcast.
  // Again we do not need to rush. There is 1 query at a time.
  // When BATCH_NB == 1, only arbiter 1 cycle over 2.

  logic [BATCH_NB-1:0]              query_avail;
  logic [BATCH_NB-1:0][LWE_K_W-1:0] query_br_loop;

  //== query arbiter
  // Use a simple round robin
  logic [BATCH_NB-1:0]       qarb_sel_1h;
  logic [BATCH_NB:0]         qarb_sel_1h_rot;
  logic [BATCH_NB-1:0]       qarb_sel_1hD;
  logic [BATCH_NB_W-1:0]     qarb_sel;
  logic                      qarb_avail;
  logic                      qarb_avail_mask; // Used when BATCH_NB == 1
  logic [LWE_K_W-1:0]        qarb_br_loop;

  assign qarb_sel_1h_rot = {qarb_sel_1h[BATCH_NB-1:0],qarb_sel_1h[BATCH_NB-1]};
  assign qarb_sel_1hD = qarb_avail ? qarb_sel_1h_rot[BATCH_NB-1:0] : qarb_sel_1h;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      qarb_sel_1h     <= 1;
      qarb_avail_mask <= 1'b0;
    end
    else begin
      qarb_sel_1h     <= qarb_sel_1hD;
      qarb_avail_mask <= qarb_avail & (BATCH_NB == 1);
    end

  common_lib_one_hot_to_bin #(
    .ONE_HOT_W (BATCH_NB)
  ) qarb_one_hot_to_bin(
    .in_1h     (qarb_sel_1h),
    .out_value (qarb_sel)
  );

  always_ff @(posedge clk)
    if (!s_rst_n) qin_avail <= 1'b0;
    else          qin_avail <= qarb_avail;

  always_ff @(posedge clk) begin
    qin_br_loop   <= qarb_br_loop;
    qin_req_id_1h <= qarb_sel_1h;
  end

  assign qarb_avail       = |query_avail & ~qarb_avail_mask;
  assign qarb_br_loop     = query_br_loop[qarb_sel];

  always_comb
    for (int i=0; i<BATCH_NB; i=i+1) begin
      // Do not send a query
      query_avail[i]       = ~req_prf_br_loop_empty[i] & req_a[i].assigned & req_a[i].parity == req_a[i].br_loop_wp[LWE_K_W];
      query_br_loop[i]     = req_a[i].br_loop_wp[LWE_K_W-1:0];
    end

// ============================================================================================== //
// Reset cache cont'd
// ============================================================================================== //
  // cache_info commands are stored in a fifo_element 3.
  // When do_clear_cache is set, there might still be a command inside.
  //
  // For timing consideration, consider the registered signals of the cache state.
  logic cin_cmd_fifo_empty;
  logic cinfo_all_fill;
  logic cinfo_all_fillD;
  logic trigger_clear_cacheD;
  logic clear_cache_done_keep; // Wait for mem_avail to be unset
  logic clear_cache_done_keepD;
  logic clear_cache_doneD;

  always_comb begin
    cinfo_all_fillD = 1'b1;
    for (int i=0; i<BSK_SLOT_NB; i=i+1)
      cinfo_all_fillD = cinfo_all_fillD & (cinfo_a[i].status != SLOT_WIP);
  end

  always_ff @(posedge clk)
    if (!s_rst_n || !do_clear_cache) begin
      cin_cmd_fifo_empty <= 1'b0; // by default consider it as not empty => wait for it to be empty
      cinfo_all_fill     <= 1'b0;
    end
    else begin
      cin_cmd_fifo_empty <= ~cin_vld;
      cinfo_all_fill     <= cinfo_all_fillD;
    end

  assign trigger_clear_cacheD   = do_clear_cache & cinfo_all_fill & cin_cmd_fifo_empty;
  assign clear_cache_doneD      = clear_cache_done_keep & ~bsk_mem_avail;
  assign clear_cache_done_keepD = trigger_clear_cache ? 1'b1 :
                                  clear_cache_doneD   ? 1'b0 : clear_cache_done_keep;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      trigger_clear_cache   <= 1'b0;
      clear_cache_done      <= 1'b0;
      reset_cache_done      <= 1'b0;
      clear_cache_done_keep <= 1'b0;
    end
    else begin
      trigger_clear_cache   <= trigger_clear_cacheD;
      clear_cache_done      <= clear_cache_doneD;
      reset_cache_done      <= trigger_clear_cache;
      clear_cache_done_keep <= clear_cache_done_keepD;
    end

// ============================================================================================== //
// Assertions
// ============================================================================================== //

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n || reset_cache) begin
      // do nothing
    end
    else begin
      logic [BSK_SLOT_NB-1:0] _bdc_slot_done_1h_wip;

//      assert(upd_req_br_loop_wp_1h == '0 | |(upd_req_br_loop_wp_1h & req_assigned))
//      else begin
//        $display("%t > INFO: Query broadcast hit while requestor is not assigned.",$time);
//      end
//
//      assert(!qbdc_avail | |upd_req_br_loop_wp_1hD)
//      else begin
//        $display("%t > INFO: Query broadcast does not correspond to any requestor.",$time);
//      end

      assert($countones(upd_req_br_loop_rp_1h) <= 1)
      else begin
        $fatal(1,"%t > ERROR: inc_bsk_rp hits more than 1 requestor!", $time);
      end

      for (int i=0; i<BSK_SLOT_NB; i=i+1)
        _bdc_slot_done_1h_wip[i] = (rbdc_br_loop == cinfo_a[i].br_loop) & (cinfo_a[i].status == SLOT_WIP) & rbdc_avail;

      assert(_bdc_slot_done_1h_wip == '0)
      else begin
        $fatal(1,"%t > ERROR: Broadcast slice done hits a slot which state is WIP!", $time);
      end

    end
// pragma translate_on

endmodule
