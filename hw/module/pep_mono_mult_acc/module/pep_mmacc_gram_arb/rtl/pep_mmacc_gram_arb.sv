// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Arbiter for the GRAM access.
// The actors are :
//    monomult feed : most priority
//    monomult acc  : 2nd priority
//    monomult sxt  : opportunist
//    GLWE LUT load : opportunist also.
// ==============================================================================================

module pep_mmacc_gram_arb
  import pep_common_param_pkg::*;
  import pep_mmacc_common_param_pkg::*;
(
  input  logic                  clk,        // clock
  input  logic                  s_rst_n,    // synchronous reset

  input  logic [GARB_CMD_W-1:0] mmfeed_garb_req,
  input  logic                  mmfeed_garb_req_vld,
  output logic                  mmfeed_garb_req_rdy,

  input  logic [GARB_CMD_W-1:0] mmacc_garb_req,
  input  logic                  mmacc_garb_req_vld,
  output logic                  mmacc_garb_req_rdy,

  output logic                  garb_mmfeed_grant, // request granted. Avail will be set for next-next time slot
  output logic                  garb_mmacc_grant,  // "

  output logic [GRAM_NB-1:0]    garb_mmfeed_rot_avail_1h, // GRAM <i> is avail for mmfeed read rot
  output logic [GRAM_NB-1:0]    garb_mmfeed_dat_avail_1h, // GRAM <i> is avail for mmfeed read data
  output logic [GRAM_NB-1:0]    garb_mmacc_rd_avail_1h,  // GRAM <i> is avail for mmacc read
  output logic [GRAM_NB-1:0]    garb_mmacc_wr_avail_1h,  // GRAM <i> is avail for mmacc write
  output logic [GRAM_NB-1:0]    garb_mmsxt_avail_1h,  // GRAM <i> is avail for mmsxt
  output logic [GRAM_NB-1:0]    garb_ldg_avail_1h     // GRAM <i> is avail for ld
);

// ============================================================================================== --
// localparam
// ============================================================================================== --
  // GRAM is a 2RW RAM.
  // The arbitration is done for each RW port.
  // Port A : Feed rot, acc rd, ldg wr
  // Port B : Feed dat, acc wr, sxt rd
  localparam int SRC_NB   = 3; // Number of sources per port
  localparam int REQ_NB   = 2;
  localparam int REQ_W    = $clog2(REQ_NB) == 0 ? 1 : $clog2(REQ_NB);

  localparam int FEED_REQ = 0;
  localparam int ACC_REQ  = 1;

  localparam int FEED_SRC = 0;
  localparam int ACC_SRC  = 1;
  localparam int OPP_SRC  = 2;

  localparam int ARB_SLOT    = 1;
  localparam int ARB_CYCLE   = REQ_NB + 1;

  // RAM ports
  localparam int PORT_NB = 2;
  localparam int PA      = 0;
  localparam int PB      = 1;

  generate
    if (GARB_SLOT_NB < ARB_CYCLE) begin : __UNSUPPORTED_GARB_SLOT_NB
      $fatal(1,"> ERROR: Unsupported GARB_SLOT_NB (%0d), should greater or equal to ARB_CYCLE(%0d)",
                GARB_SLOT_NB, ARB_CYCLE);
    end
    if (ACC_WR_START_DLY_SLOT_NB * GARB_SLOT_CYCLE  > GLWE_ACC_CYCLE) begin : __UNSUPPORTED_STG_ITER_NB_ACC
      $fatal(1,"> ERROR: Unsupported STG_ITER_NB : too small, there is no overlap between the acc rd and wr arbitration available. The arbiter cannot arbitrate correctly. We should have ACC_WR_START_DLY_SLOT_NB(%0d) * GARB_SLOT_CYCLE(%0d)  <= GLWE_ACC_CYCLE(%0d)", ACC_WR_START_DLY_SLOT_NB, GARB_SLOT_CYCLE, GLWE_ACC_CYCLE);
    end
    if (FEED_DAT_START_DLY_SLOT_NB * GARB_SLOT_CYCLE  > GLWE_FEED_CYCLE) begin : __UNSUPPORTED_STG_ITER_NB_FEED
      $fatal(1,"> ERROR: Unsupported STG_ITER_NB : too small, there is no overlap between the feed dat and rot arbitration available. The arbiter cannot arbitrate correctly. We should have FEED_DAT_START_DLY_SLOT_NB(%0d) * GARB_SLOT_CYCLE(%0d)  <= GLWE_FEED_CYCLE(%0d)", FEED_DAT_START_DLY_SLOT_NB, GARB_SLOT_CYCLE, GLWE_FEED_CYCLE);
    end
  endgenerate



// ============================================================================================== --
// Input Pipe
// ============================================================================================== --
  garb_cmd_t [REQ_NB-1:0] in_req;
  logic [REQ_NB-1:0]      in_req_vld;
  logic [REQ_NB-1:0]      in_req_rdy;

  garb_cmd_t [REQ_NB-1:0] s0_req;
  logic [REQ_NB-1:0]      s0_req_vld;
  logic [REQ_NB-1:0]      s0_req_rdy;

  assign in_req[FEED_REQ]     = mmfeed_garb_req;
  assign in_req_vld[FEED_REQ] = mmfeed_garb_req_vld;
  assign mmfeed_garb_req_rdy  = in_req_rdy[FEED_REQ];

  assign in_req[ACC_REQ]      = mmacc_garb_req;
  assign in_req_vld[ACC_REQ]  = mmacc_garb_req_vld;
  assign mmacc_garb_req_rdy   = in_req_rdy[ACC_REQ];

  generate
    for (genvar gen_i=0; gen_i<REQ_NB; gen_i=gen_i+1) begin : gen_in_loop
      fifo_element #(
        .WIDTH          (GARB_CMD_W),
        .DEPTH          (1),
        .TYPE_ARRAY     (4'h3),
        .DO_RESET_DATA  (1'b0),
        .RESET_DATA_VAL (0)
      ) in_fifo_element (
        .clk      (clk),
        .s_rst_n  (s_rst_n),

        .in_data  (in_req[gen_i]),
        .in_vld   (in_req_vld[gen_i]),
        .in_rdy   (in_req_rdy[gen_i]),

        .out_data (s0_req[gen_i]),
        .out_vld  (s0_req_vld[gen_i]),
        .out_rdy  (s0_req_rdy[gen_i])
      );
    end
  endgenerate

// ============================================================================================== --
// Plan table
// ============================================================================================== --
  logic [PORT_NB-1:0][GRAM_NB-1:0][GARB_SLOT_NB-1:0][SRC_NB-1:0] planning;
  logic [PORT_NB-1:0][GRAM_NB-1:0][GARB_SLOT_NB-1:0][SRC_NB-1:0] planningD;
  logic [PORT_NB-1:0][GRAM_NB-1:0][GARB_SLOT_NB-1:1][SRC_NB-1:0] planningD_upd;

  logic [PORT_NB-1:0][GRAM_NB-1:0][GARB_SLOT_NB-1:0]             planning_free;

  logic [GARB_SLOT_CYCLE_W-1:0]                          slot_cycle;
  logic [GARB_SLOT_CYCLE_W-1:0]                          slot_cycleD;
  logic                                                  slot_last_cycle;

  assign slot_last_cycle = slot_cycle == '0;
  assign slot_cycleD     = slot_last_cycle ? GARB_SLOT_CYCLE-1 : slot_cycle - 1;

  always_ff @(posedge clk)
    if (!s_rst_n) slot_cycle <= GARB_SLOT_CYCLE-1;
    else          slot_cycle <= slot_cycleD;

  always_comb
    for (int p=0; p<PORT_NB; p=p+1)
      for (int i=0; i<GRAM_NB; i=i+1)
        planningD[p][i] = slot_last_cycle ? {{SRC_NB{1'b0}}, planningD_upd[p][i][GARB_SLOT_NB-1:1]} :
                                             planning[p][i];

  always_comb
    for (int p=0; p<PORT_NB; p=p+1)
      for (int i=0; i<GRAM_NB; i=i+1)
        for (int j=0; j<GARB_SLOT_NB; j=j+1)
          planning_free[p][i][j] = planning[p][i][j] == '0;

  always_ff @(posedge clk)
    if (!s_rst_n) planning <= '0;
    else          planning <= planningD;

// ============================================================================================== --
// FSM
// ============================================================================================== --
// The arbiter has GARB_SLOT_CYCLE clock cycles to make its decision.
// We use 1 cycle per source.
// Note that SXT only needs to do read, and LD, to write.
// Therefore, they are not conflicting with each other. They
// can be arbitrated together.
//
// Arbiter from the less priority to the most.

  typedef enum integer {
    ST_XXX = 'x,
    ST_IDLE = 0,
    ST_ARB_ACC,
    ST_ARB_FEED,
    ST_ARB_GRANT
  } state_e;

  state_e state;
  state_e next_state;

  logic start_arb;

  always_comb begin
    next_state = ST_XXX; // default
    case (state)
      ST_IDLE: // state used when GARB_SLOT_CYCLE > ARB_CYCLE
        next_state = start_arb ? ST_ARB_ACC : state;
      ST_ARB_ACC:
        next_state = ST_ARB_FEED;
      ST_ARB_FEED:
        next_state = ST_ARB_GRANT;
      ST_ARB_GRANT:
        next_state = (GARB_SLOT_CYCLE > ARB_CYCLE) ? ST_IDLE : ST_ARB_ACC;
    endcase
  end

  always_ff @(posedge clk)
    if (!s_rst_n) state <= (GARB_SLOT_CYCLE > ARB_CYCLE) ? ST_IDLE : ST_ARB_FEED;
    else          state <= next_state;

  logic st_idle;
  logic st_arb_feed;
  logic st_arb_acc;
  logic st_arb_grant;

  assign st_idle       = state == ST_IDLE;
  assign st_arb_feed   = state == ST_ARB_FEED;
  assign st_arb_acc    = state == ST_ARB_ACC;
  assign st_arb_grant  = state == ST_ARB_GRANT;

  assign start_arb = slot_cycle == ARB_CYCLE;

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      if (st_arb_grant)
        assert(slot_last_cycle)
        else begin
          $fatal(1,"%t > ERROR: planning update and FSM are not synchronized!",$time);
        end
    end
// pragma translate_on

// ============================================================================================== --
// Arbitration
// ============================================================================================== --
  // slot_is_free content is valid for the whole arbitration, since planning is not changed during this period.
  logic [PORT_NB-1:0][GRAM_NB-1:0]              slot_is_free;
  logic [GRAM_NB-1:0]                           slot_is_free_accstart;
  logic [GRAM_NB-1:0]                           slot_is_free_feedstart;

  // With current way of arbitration, there is no need to look at the other slots
  // than the first one.
  always_comb
    for (int g=0; g<GRAM_NB; g=g+1) begin
      slot_is_free_accstart[g]   = planning_free[PB][g][ARB_SLOT+ACC_WR_START_DLY_SLOT_NB];
      slot_is_free_feedstart[g]  = planning_free[PB][g][ARB_SLOT+FEED_DAT_START_DLY_SLOT_NB];
      for (int p=0; p<PORT_NB; p=p+1) begin
        slot_is_free[p][g]          = planning_free[p][g][ARB_SLOT];
      end
    end

  // -------------------------------------------------------------------------------------------- --
  // ST_ARB_ACC
  // -------------------------------------------------------------------------------------------- --
  // Update planning_mask, which will be extended during st_arb_grant.
  logic [GRAM_NB-1:0][SRC_NB-1:0]      a0_planning_mask_acc;
  logic                                a0_already_arbitrated;

  // check that there is not a pending acc command on another GRAM
  // Overlap is authorized for the write part.
  always_comb begin
    a0_already_arbitrated = 1'b0;
    for (int g=0; g<GRAM_NB; g=g+1)
      a0_already_arbitrated = a0_already_arbitrated | planning[PA][g][ARB_SLOT][ACC_SRC]; // take only read into account
  end

  // To prevent feed to wait too long, and create bubbles, check that
  // feed is not asking the same GRID
  logic [GRAM_NB-1:0] a0_feed_requesting;
  logic [GRAM_NB-1:0] a1_feed_already_arbitrated_prev; // set by previous arbitration round
  always_comb
    for (int g=0; g<GRAM_NB; g=g+1)
      a0_feed_requesting[g] = s0_req_vld[FEED_REQ] & (s0_req[FEED_REQ].grid == g);

  // Do not give priority to feed, when this later is requesting, but not twice in a row
  always_comb
    for (int g=0; g<GRAM_NB; g=g+1)
      a0_planning_mask_acc[g] = slot_is_free[PA][g] && slot_is_free_accstart[g]
                                && (s0_req[ACC_REQ].grid == g) && s0_req_vld[ACC_REQ]
                                && !a0_already_arbitrated
                                && !(a0_feed_requesting[g] && !a1_feed_already_arbitrated_prev[g] && !s0_req[ACC_REQ].critical)
                                ? (1 << ACC_SRC) : '0;

  // -------------------------------------------------------------------------------------------- --
  // ST_ARB_FEED
  // -------------------------------------------------------------------------------------------- --
  logic [GRAM_NB-1:0][SRC_NB-1:0]      a1_planning_mask;
  logic [GRAM_NB-1:0][SRC_NB-1:0]      a1_planning_mask_acc;
  logic                                a1_already_arbitrated;
  logic [PORT_NB-1:0][GRAM_NB-1:0]     a1_already_arbitrated_a;

  always_ff @(posedge clk)
    a1_planning_mask_acc <= a0_planning_mask_acc;

  // check that there is not a pending feed command on another GRAM
  assign a1_already_arbitrated       = |a1_already_arbitrated_a[PA];
  always_comb
    for (int g=0; g<GRAM_NB; g=g+1)
      for (int p=0; p<PORT_NB; p=p+1)
        a1_already_arbitrated_a[p][g] = planning[p][g][ARB_SLOT][FEED_SRC];

  // To avoid infifo overflow, do not arbitrate twice in a row the feed on the same grid
  // when acc is asking the same location.
  logic [GRAM_NB-1:0]                  a1_feed_already_arbitrated_prevD;
  logic [GRAM_NB-1:0]                  a1_feed_already_arbitrated_prevD_tmp;
  logic                                a1_do_not_arbitrate;

  assign a1_feed_already_arbitrated_prevD_tmp = a1_already_arbitrated_a[PA] | a1_already_arbitrated_a[PB];
  assign a1_feed_already_arbitrated_prevD     = st_arb_feed ? a1_feed_already_arbitrated_prevD_tmp : a1_feed_already_arbitrated_prev;

  always_ff @(posedge clk)
    if (!s_rst_n) a1_feed_already_arbitrated_prev <= '0;
    else          a1_feed_already_arbitrated_prev <= a1_feed_already_arbitrated_prevD;

  assign a1_do_not_arbitrate = a1_planning_mask_acc[s0_req[FEED_REQ].grid][ACC_SRC];

  always_comb
    for (int g=0; g<GRAM_NB; g=g+1)
      a1_planning_mask[g] =  slot_is_free[PA][g] && slot_is_free_feedstart[g]
                             && (s0_req[FEED_REQ].grid == g) && s0_req_vld[FEED_REQ]
                             && ~a1_already_arbitrated && ~a1_do_not_arbitrate       ? (1 << FEED_SRC) : a1_planning_mask_acc[g];

  // -------------------------------------------------------------------------------------------- --
  // ST_ARB_GRANT : Update planning
  // -------------------------------------------------------------------------------------------- --
  // During this cycle the planning mask is expanded.
  // The requests are consumed.
  logic [GRAM_NB-1:0][SRC_NB-1:0]      a2_planning_mask;

  always_ff @(posedge clk)
    a2_planning_mask <= a1_planning_mask;

  // PORT A:
  // Feed asks for GLWE_SLOT_NB consecutive locations on RAM grid.
  // Acc also asks for GLWE_SLOT_NB consecutive locations on RAM grid.
  // LDG takes what remains.
  // PORT B:
  // Feed asks for GLWE_SLOT_NB+1 slots starting from instant + FEED_DAT_START_DLY_SLOT_NB
  // Acc asks for GLWE_SLOT_NB+1 slots starting from instant + ACC_WR_START_DLY_SLOT_NB
  // SXT takes what remains.

  // The following are constants.
  logic [PORT_NB-1:0][GARB_SLOT_NB-1:0][SRC_NB-1:0] planningD_upd_acc;
  logic [PORT_NB-1:0][GARB_SLOT_NB-1:0][SRC_NB-1:0] planningD_upd_feed;
  logic [PORT_NB-1:0][GARB_SLOT_NB-1:0][SRC_NB-1:0] planningD_upd_opp;

  always_comb begin
    planningD_upd_acc = '0;
    for (int i=0; i<GLWE_SLOT_NB; i=i+1)
      planningD_upd_acc[PA][ARB_SLOT+i] = (1 << ACC_SRC);

    for (int i=0; i<ACC_WR_START_DLY_SLOT_NB; i=i+1)
      if (i==0) // ARB_SLOT
        planningD_upd_acc[PB][ARB_SLOT+i] = slot_is_free[PB][s0_req[ACC_REQ].grid] ? (1 << OPP_SRC) : planning[PB][s0_req[ACC_REQ].grid][ARB_SLOT+i];
      else
        planningD_upd_acc[PB][ARB_SLOT+i] = planning[PB][s0_req[ACC_REQ].grid][ARB_SLOT+i];
    for (int i=ACC_WR_START_DLY_SLOT_NB; i<ACC_WR_START_DLY_SLOT_NB+GLWE_SLOT_NB+ACC_ADD_SLOT; i=i+1)
      planningD_upd_acc[PB][ARB_SLOT+i] = (1 << ACC_SRC);
  end

  always_comb begin
    planningD_upd_feed = '0;
    for (int i=0; i<GLWE_SLOT_NB; i=i+1)
      planningD_upd_feed[PA][ARB_SLOT+i] = (1 << FEED_SRC);

    for (int i=0; i<FEED_DAT_START_DLY_SLOT_NB; i=i+1)
      if (i==0)
        planningD_upd_feed[PB][ARB_SLOT+i] = slot_is_free[PB][s0_req[FEED_REQ].grid] ? (1 << OPP_SRC) : planning[PB][s0_req[FEED_REQ].grid][ARB_SLOT+i];
      else
        planningD_upd_feed[PB][ARB_SLOT+i] = planning[PB][s0_req[FEED_REQ].grid][ARB_SLOT+i];
    for (int i=FEED_DAT_START_DLY_SLOT_NB; i<FEED_DAT_START_DLY_SLOT_NB+GLWE_SLOT_NB+FEED_ADD_SLOT; i=i+1)
      planningD_upd_feed[PB][ARB_SLOT+i] = (1 << FEED_SRC);
  end

  always_comb begin
    planningD_upd_opp = '0;
    planningD_upd_opp[PA][ARB_SLOT] = (1 << OPP_SRC);
    planningD_upd_opp[PB][ARB_SLOT] = (1 << OPP_SRC);
  end

  always_comb
    for (int p=0; p<PORT_NB; p=p+1)
      for (int g=0; g<GRAM_NB; g=g+1) begin
        planningD_upd[p][g][ARB_SLOT] = a2_planning_mask[g][FEED_SRC] ? planningD_upd_feed[p][ARB_SLOT]:
                                        a2_planning_mask[g][ACC_SRC]  ? planningD_upd_acc[p][ARB_SLOT]:
                                        slot_is_free[p][g]            ? planningD_upd_opp[p][ARB_SLOT]:
                                        planning[p][g][ARB_SLOT];
        planningD_upd[p][g][GARB_SLOT_NB-1:ARB_SLOT+1] = a2_planning_mask[g][FEED_SRC] ? planningD_upd_feed[p][GARB_SLOT_NB-1:ARB_SLOT+1]:
                                                         a2_planning_mask[g][ACC_SRC]  ? planningD_upd_acc[p][GARB_SLOT_NB-1:ARB_SLOT+1]:
                                                         planning[p][g][GARB_SLOT_NB-1:ARB_SLOT+1];
      end

// ============================================================================================== --
// Grant
// ============================================================================================== --
  logic [REQ_NB-1:0] arb_grant;
  logic [REQ_NB-1:0] arb_grantD;
  logic [REQ_NB-1:0] arb_grantD_tmp;

  always_ff @(posedge clk)
    if (!s_rst_n) arb_grant <= '0;
    else          arb_grant <= arb_grantD;

  assign arb_grantD = {REQ_NB{st_arb_grant}} & arb_grantD_tmp;

  always_comb begin
    arb_grantD_tmp = '0;
    for (int i=0; i<REQ_NB; i=i+1)
      for (int g=0; g<GRAM_NB; g=g+1)
        arb_grantD_tmp[i] = arb_grantD_tmp[i] | a2_planning_mask[g][i];
  end

  // request ready
  assign s0_req_rdy = arb_grantD;

  assign garb_mmfeed_grant = arb_grant[FEED_REQ];
  assign garb_mmacc_grant  = arb_grant[ACC_REQ];


// ============================================================================================== --
// Execution of current slot
// ============================================================================================== --
  logic [GRAM_NB-1:0]    garb_mmfeed_rot_avail_1hD;
  logic [GRAM_NB-1:0]    garb_mmfeed_dat_avail_1hD;
  logic [GRAM_NB-1:0]    garb_mmacc_rd_avail_1hD;
  logic [GRAM_NB-1:0]    garb_mmacc_wr_avail_1hD;
  logic [GRAM_NB-1:0]    garb_mmsxt_avail_1hD;
  logic [GRAM_NB-1:0]    garb_ldg_avail_1hD;

  always_comb
    for (int i=0; i<GRAM_NB; i=i+1) begin
      garb_mmfeed_rot_avail_1hD[i] = planning[PA][i][0][FEED_SRC];
      garb_mmfeed_dat_avail_1hD[i] = planning[PB][i][0][FEED_SRC];
      garb_mmacc_rd_avail_1hD[i]   = planning[PA][i][0][ACC_SRC];
      garb_mmacc_wr_avail_1hD[i]   = planning[PB][i][0][ACC_SRC];
      garb_mmsxt_avail_1hD[i]      = planning[PB][i][0][OPP_SRC];
      garb_ldg_avail_1hD[i]        = planning[PA][i][0][OPP_SRC];
    end

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      garb_mmfeed_rot_avail_1h <= '0;
      garb_mmfeed_dat_avail_1h <= '0;
      garb_mmacc_rd_avail_1h   <= '0;
      garb_mmacc_wr_avail_1h   <= '0;
      garb_mmsxt_avail_1h      <= '0;
      garb_ldg_avail_1h        <= '0;
    end
    else begin
      garb_mmfeed_rot_avail_1h <= garb_mmfeed_rot_avail_1hD;
      garb_mmfeed_dat_avail_1h <= garb_mmfeed_dat_avail_1hD;
      garb_mmacc_rd_avail_1h   <= garb_mmacc_rd_avail_1hD;
      garb_mmacc_wr_avail_1h   <= garb_mmacc_wr_avail_1hD;
      garb_mmsxt_avail_1h      <= garb_mmsxt_avail_1hD;
      garb_ldg_avail_1h        <= garb_ldg_avail_1hD;
    end

endmodule
