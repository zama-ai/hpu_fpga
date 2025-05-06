// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Instruction scheduler query
// ----------------------------------------------------------------------------------------------
//
// Handle query sequence to generate required pool updates
// Three query is availables:
//  * REFILL -> Insert new instruction in the pool
//  * ISSUE  -> Issue "ready" instruction on PE
//  * RETIRE -> Remove retired instruction from the pool
//
// ==============================================================================================

module isc_query
  import instruction_scheduler_pkg::*;
  import hpu_common_instruction_pkg::*;
  import regf_common_param_pkg::*;
  #()(
    input  logic                                    clk,        // clock
    input  logic                                    s_rst_n,    // synchronous reset

    // Quasi static
    input  logic                                    use_bpip,

    // Query interface with Rdy/Vld
    // Wrap filter/updt and ack fields. Ack is considered valid while rdy is on
    output logic                                    query_rdy,
    input  isc_query_cmd_e                          query_cmd,
    input  isc_insn_t                               query_refill,
    input  logic [INSN_KIND_W-1: 0]                 query_pe_rd_ack,
    input  logic [INSN_KIND_W-1: 0]                 query_pe_wr_ack,
    input  logic [INSN_KIND_W-1: 0]                 query_pe_rdy,
    input  logic                                    query_vld,

    output isc_query_ack_t                          query_ack,
    output logic                                    query_ack_vld,

    // Pool request interface with Rdy/Vld
    output isc_pool_info_t                          pool_req_info,
    output isc_pool_filter_t                        pool_req_filter,
    output isc_pool_updt_t                          pool_req_updt,
    output logic                                    pool_req_vld,

    input  isc_pool_ack_t                           pool_ack,
    input  logic                                    pool_ack_vld
);

// ============================================================================================== //
// Signal used in Sub-fsm
// ============================================================================================== //
  logic [SYNC_ID_W-1: 0] r_sync_id, nxt_sync_id;
  isc_pool_info_t   refill_req_info  , rdunlock_req_info  , retire_req_info  , issue_req_info;
  isc_pool_filter_t refill_req_filter, rdunlock_req_filter, retire_req_filter, issue_req_filter;
  isc_pool_updt_t   refill_req_updt  , rdunlock_req_updt  , retire_req_updt  , issue_req_updt;
  logic             refill_req_vld   , rdunlock_req_vld   , retire_req_vld   , issue_req_vld;
  isc_query_ack_t   refill_query_ack , rdunlock_query_ack , retire_query_ack , issue_query_ack;

// Store command 
  isc_query_cmd_e r_query_cmd, nxt_query_cmd;
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      r_query_cmd <= NONE;
    end
    else begin
      r_query_cmd <= nxt_query_cmd;
    end

    assign nxt_query_cmd = (query_vld && query_rdy)? query_cmd: r_query_cmd;

// ============================================================================================== //
// Refill FSM
// ============================================================================================== //
// Fsm in charge of generating refill request sequence
  typedef enum integer {
    REFILL_XXX = 'x,
    REFILL_IDLE = 0,
    REFILL_SYNC_LOCK,
    REFILL_RD_LOCK,
    REFILL_WR_LOCK,
    REFILL_INSERT,
    REFILL_ISSUE_LOCK
  } refill_fsm_e;
  refill_fsm_e r_refill, nxt_refill;
  logic [POOL_SLOT_W: 0] r_refill_rd_lock, nxt_refill_rd_lock;
  logic [POOL_SLOT_W: 0] r_refill_wr_lock, nxt_refill_wr_lock;
  logic [POOL_SLOT_W: 0] r_refill_flush_lock, nxt_refill_flush_lock;

  logic refill_idle, refill_sync_lock, refill_rd_lock, refill_wr_lock, refill_insert,
        refill_issue_lock;
  assign refill_idle = (r_refill == REFILL_IDLE);
  assign refill_sync_lock = (r_refill == REFILL_SYNC_LOCK);
  assign refill_rd_lock = (r_refill == REFILL_RD_LOCK);
  assign refill_wr_lock = (r_refill == REFILL_WR_LOCK);
  assign refill_issue_lock = (r_refill == REFILL_ISSUE_LOCK);
  assign refill_insert = (r_refill == REFILL_INSERT);

// FSM structure =============================================================================== //
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      r_refill <= REFILL_IDLE;
      r_refill_rd_lock <= '0;
      r_refill_wr_lock <= '0;
      r_refill_flush_lock <= '0;
    end
    else begin
      r_refill <= nxt_refill;
      r_refill_rd_lock <= nxt_refill_rd_lock ;
      r_refill_wr_lock <= nxt_refill_wr_lock ;
      r_refill_flush_lock <= nxt_refill_flush_lock;
    end

always_comb begin
  case (r_refill)
    // ------------------------------------------------------------------------
    REFILL_IDLE: begin
    if (query_rdy && query_vld && (query_cmd == REFILL))
      nxt_refill = (query_refill.kind == SYNC) ? REFILL_SYNC_LOCK :
                   (query_refill.kind & PBS) ? REFILL_ISSUE_LOCK :
                   REFILL_RD_LOCK;
    else
      nxt_refill = r_refill;
    end

    // ------------------------------------------------------------------------
    REFILL_ISSUE_LOCK: begin
    if (pool_ack_vld)
      nxt_refill = REFILL_RD_LOCK;
    else
      nxt_refill = r_refill;
    end

    // ------------------------------------------------------------------------
    REFILL_SYNC_LOCK: begin
    if (pool_ack_vld)
      nxt_refill = REFILL_INSERT;
    else
      nxt_refill = r_refill;
    end

    // ------------------------------------------------------------------------
    REFILL_RD_LOCK: begin
    if (pool_ack_vld)
      nxt_refill = REFILL_WR_LOCK;
    else
      nxt_refill = r_refill;
    end

    // ------------------------------------------------------------------------
    REFILL_WR_LOCK: begin
    if (pool_ack_vld)
      nxt_refill = REFILL_INSERT;
    else
      nxt_refill = r_refill;
    end

    // ------------------------------------------------------------------------
    REFILL_INSERT: begin
    if(pool_ack_vld)
      nxt_refill = REFILL_IDLE;
    else
      nxt_refill = r_refill;
    end
    default: nxt_refill = REFILL_XXX;
  endcase
end

// FSM logic =============================================================================== //
// Refill query construct based on current state
always_comb begin
  // Default value
  refill_req_info.insn = query_refill;
  refill_req_info.state = '{sync_id: r_sync_id, rd_lock: '0, wr_lock: '0, issue_lock: '0, vld: 1'b0, rd_pdg: '0, pdg: '0};
  refill_req_filter = '{match_sync_id: '0, match_vld: '0, match_rd_pdg: '0, match_pdg: '0, match_lock_rdy: '0,
                            match_insn_kind: '0, match_dst_on_srcs: '0, match_srcs_on_dst: '0, match_dst_on_dst: '0, match_flush: '0};
  refill_req_updt = '{cmd: POOL_UPDATE, reorder: '0, toggle_vld: '0, toggle_rd_pdg: '0, toggle_pdg: '0, dec_rd_lock: '0, dec_wr_lock: '0, dec_issue_lock: '0};
  refill_req_vld = 1'b0;
  refill_query_ack = '0;

  nxt_refill_rd_lock = r_refill_rd_lock;
  nxt_refill_wr_lock = r_refill_wr_lock;

  // Clear the flush lock in idle state. The state machine might not go
  // through refill_issue_lock.
  nxt_refill_flush_lock = refill_idle ? '0 : r_refill_flush_lock;

  if (refill_issue_lock) begin
    // Build a request that counts the number of PBSs not issued in the Pool with a different flush
    // bit.
    refill_req_info.state.vld = 1'b1;
    refill_req_info.state.pdg = 1'b0;
    refill_req_info.insn.flush = !query_refill.flush;
    refill_req_filter.match_vld = 1'b1;
    refill_req_filter.match_pdg = 1'b1;
    refill_req_filter.match_insn_kind = 1'b1;
    refill_req_filter.match_flush = 1'b1;

    refill_req_vld = 1'b1;
    if (pool_ack_vld & use_bpip) // Only lock if we are using the BPIP
      nxt_refill_flush_lock = pool_ack.nb_match;
  end
  if (refill_sync_lock) begin
    // Build a request that count vld pool entries where sync_id match current one
    refill_req_info.state.vld = 1'b1;
    refill_req_filter.match_vld = 1'b1;
    refill_req_filter.match_sync_id = 1'b1;

    refill_req_vld = 1'b1;
    if (pool_ack_vld) begin
      nxt_refill_rd_lock = '0; // rd_lock unused for sync
      nxt_refill_wr_lock = pool_ack.nb_match;
    end
  end
  if (refill_rd_lock) begin
    // Build a request that count vld pool entries where srcs match with our refill_dst
    refill_req_info.state.vld = 1'b1;
    refill_req_info.state.rd_pdg = 1'b1;
    refill_req_filter.match_vld = 1'b1;
    refill_req_filter.match_rd_pdg = 1'b1;
    refill_req_filter.match_dst_on_srcs = 1'b1;

    refill_req_vld = 1'b1;
    if (pool_ack_vld) begin
      nxt_refill_rd_lock = pool_ack.nb_match;
    end
  end
  else if (refill_wr_lock) begin
    // Build a request that count vld pool entries where dst match with our src
    refill_req_info.state.vld = 1'b1;
    refill_req_filter.match_vld = 1'b1;
    refill_req_filter.match_srcs_on_dst = 1'b1;
    refill_req_filter.match_dst_on_dst = 1'b1;

    refill_req_vld = 1'b1;
    if (pool_ack_vld) begin
      nxt_refill_wr_lock = pool_ack.nb_match;
    end
  end
  else if (refill_insert) begin
    // Update state and insert in the pool
    // Found an invalid slot and fill it with refill info and toggle vld/rd_pdg bit
    refill_req_info.state= '{sync_id: r_sync_id, vld: 1'b0, rd_pdg: 1'b0, pdg: 1'b0, rd_lock: r_refill_rd_lock, wr_lock: r_refill_wr_lock , issue_lock: r_refill_flush_lock};
    refill_req_filter.match_vld = 1'b1;
    refill_req_updt.cmd = POOL_REFILL;
    refill_req_updt.reorder = 1'b1;
    refill_req_updt.toggle_vld = 1'b1;
    refill_req_updt.toggle_rd_pdg = 1'b1;

    refill_req_vld = 1'b1;

    // Query ack in refill is based on the last pool request => directly map the pool ack on it
    // No buffering required
    refill_query_ack.cmd = r_query_cmd;
    refill_query_ack.status = pool_ack.status;
    refill_query_ack.info = pool_ack.info;
  end
end

// ============================================================================================== //
// rdunlock FSM
// ============================================================================================== //
// Fsm in charge of generating rdunlock request sequence
  typedef enum integer {
    RDUNLOCK_XXX = 'x,
    RDUNLOCK_IDLE = '0,
    RDUNLOCK_SLOT,
    RDUNLOCK_RD_LOCK
  } rdunlock_fsm_e;
  rdunlock_fsm_e r_rdunlock, nxt_rdunlock;
  isc_pool_info_t r_rdunlock_info, nxt_rdunlock_info;
  isc_ack_status_e r_rdunlock_status, nxt_rdunlock_status;
  logic rdunlock_idle, rdunlock_slot, rdunlock_rd_lock;
  assign rdunlock_idle = (r_rdunlock      == RDUNLOCK_IDLE);
  assign rdunlock_slot = (r_rdunlock      == RDUNLOCK_SLOT);
  assign rdunlock_rd_lock = (r_rdunlock   == RDUNLOCK_RD_LOCK);

// FSM structure =============================================================================== //
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      r_rdunlock <= RDUNLOCK_IDLE;
      r_rdunlock_info <= '0;
      r_rdunlock_status <= FAILURE;
    end
    else begin
      r_rdunlock <= nxt_rdunlock;
      r_rdunlock_info <= nxt_rdunlock_info;
      r_rdunlock_status <= nxt_rdunlock_status;
    end

always_comb begin
  case (r_rdunlock)
    // ------------------------------------------------------------------------
    RDUNLOCK_IDLE: begin
    if (query_rdy && query_vld && (query_cmd == RDUNLOCK)) 
      nxt_rdunlock = RDUNLOCK_SLOT;
    else 
      nxt_rdunlock = r_rdunlock;
    end

    // ------------------------------------------------------------------------
    RDUNLOCK_SLOT: begin
    if (pool_ack_vld) 
      nxt_rdunlock = RDUNLOCK_RD_LOCK;
    else 
      nxt_rdunlock = r_rdunlock;
    end

    // ------------------------------------------------------------------------
    RDUNLOCK_RD_LOCK: begin
    if (pool_ack_vld) 
      nxt_rdunlock = RDUNLOCK_IDLE;
    else 
      nxt_rdunlock = r_rdunlock;
    end
    default: nxt_rdunlock = RDUNLOCK_XXX;
  endcase
end

// FSM logic =============================================================================== //
// rdunlock query construct based on current state
always_comb begin
  // Default value
  rdunlock_req_info.insn = '0;
  rdunlock_req_info.state = '0;
  rdunlock_req_filter = '0;
  rdunlock_req_updt = '0;
  rdunlock_req_vld = 1'b0;

  nxt_rdunlock_info = r_rdunlock_info;
  nxt_rdunlock_status = r_rdunlock_status;

  if (rdunlock_slot) begin
    // Build a request that match oldest issued insn with matching pe_ack
    rdunlock_req_info.state.vld = 1'b1;
    rdunlock_req_info.state.rd_pdg = 1'b1;
    rdunlock_req_info.state.pdg = 1'b1;
    rdunlock_req_info.insn.kind = query_pe_rd_ack; 

    rdunlock_req_filter.match_vld = 1'b1;
    rdunlock_req_filter.match_rd_pdg = 1'b1;
    rdunlock_req_filter.match_pdg = 1'b1;
    rdunlock_req_filter.match_insn_kind= 1'b1;

    rdunlock_req_updt.cmd = POOL_UPDATE;
    rdunlock_req_updt.reorder = 1'b1;
    rdunlock_req_updt.toggle_rd_pdg = 1'b1;

    rdunlock_req_vld = 1'b1;
    if (pool_ack_vld) begin
      nxt_rdunlock_info = pool_ack.info;
      nxt_rdunlock_status = pool_ack.status;
    end
  end
  else if (rdunlock_rd_lock) begin
    // Build a request that match all vld and unissued insn where
    // -> dst == (rdunlock_srcA || rdunlock_srcB)
    // And required an rd_lock cnt update
    rdunlock_req_info = r_rdunlock_info;
    rdunlock_req_info.state.vld = 1'b1;
    rdunlock_req_info.state.pdg = 1'b0;

    rdunlock_req_filter.match_vld = 1'b1;
    rdunlock_req_filter.match_pdg = 1'b1;
    rdunlock_req_filter.match_srcs_on_dst = 1'b1;
    rdunlock_req_updt.cmd = POOL_UPDATE;
    rdunlock_req_updt.reorder = 1'b0;
    rdunlock_req_updt.dec_rd_lock = 1'b1;

    rdunlock_req_vld = 1'b1;
  end
end

// Query ack in rdunlock is based on the first pool request => info & status must be buffered
assign rdunlock_query_ack.status = r_rdunlock_status;
assign rdunlock_query_ack.cmd = r_query_cmd;
assign rdunlock_query_ack.info = r_rdunlock_info;

// ============================================================================================== //
// Retire FSM
// ============================================================================================== //
// Fsm in charge of generating retire request sequence
  typedef enum integer {
    RETIRE_XXX = 'x,
    RETIRE_IDLE = '0,
    RETIRE_SLOT,
    RETIRE_WR_LOCK,
    RETIRE_SYNC_LOCK
  } retire_fsm_e;
  retire_fsm_e r_retire, nxt_retire;
  isc_pool_info_t r_retire_info, nxt_retire_info;
  isc_ack_status_e r_retire_status, nxt_retire_status;
  logic retire_idle, retire_slot, retire_wr_lock, retire_sync_lock;
  assign retire_idle = (r_retire == RETIRE_IDLE);
  assign retire_slot = (r_retire == RETIRE_SLOT);
  assign retire_wr_lock = (r_retire == RETIRE_WR_LOCK);
  assign retire_sync_lock = (r_retire == RETIRE_SYNC_LOCK);

// FSM structure =============================================================================== //
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      r_retire <= RETIRE_IDLE;
      r_retire_info <= '0;
      r_retire_status <= FAILURE;
    end
    else begin
      r_retire <= nxt_retire;
      r_retire_info <= nxt_retire_info;
      r_retire_status <= nxt_retire_status;
    end

always_comb begin
  case (r_retire)
    // ------------------------------------------------------------------------
    RETIRE_IDLE: begin
    if (query_rdy && query_vld && (query_cmd == RETIRE)) 
      nxt_retire = RETIRE_SLOT;
    else 
      nxt_retire = r_retire;
    end

    // ------------------------------------------------------------------------
    RETIRE_SLOT: begin
    if (pool_ack_vld) 
      nxt_retire = RETIRE_WR_LOCK;
    else 
      nxt_retire = r_retire;
    end

    // ------------------------------------------------------------------------
    RETIRE_WR_LOCK: begin
    if (pool_ack_vld) 
      nxt_retire = RETIRE_SYNC_LOCK;
    else 
      nxt_retire = r_retire;
    end

    // ------------------------------------------------------------------------
    RETIRE_SYNC_LOCK: begin
    if (pool_ack_vld) 
      nxt_retire = RETIRE_IDLE;
    else 
      nxt_retire = r_retire;
    end
    default: nxt_retire = RETIRE_XXX;
  endcase
end

// FSM logic =============================================================================== //
// Retire query construct based on current state
always_comb begin
  // Default value
  retire_req_info.insn = '0;
  retire_req_info.state = '0;
  retire_req_filter = '0;
  retire_req_updt = '0;
  retire_req_vld = 1'b0;

  nxt_retire_info = r_retire_info;
  nxt_retire_status = r_retire_status;

  if (retire_slot) begin
    // Build a request that match oldest issued insn with matching pe_ack
    retire_req_info.state.vld = 1'b1;
    retire_req_info.state.rd_pdg = 1'b0;
    retire_req_info.state.pdg = 1'b1;
    retire_req_info.insn.kind = query_pe_wr_ack; 

    retire_req_filter.match_vld = 1'b1;
    retire_req_filter.match_rd_pdg = 1'b1;
    retire_req_filter.match_pdg = 1'b1;
    retire_req_filter.match_insn_kind= 1'b1;

    retire_req_updt.cmd = POOL_UPDATE;
    retire_req_updt.reorder = 1'b1;
    retire_req_updt.toggle_vld = 1'b1;
    retire_req_updt.toggle_pdg = 1'b1;

    retire_req_vld = 1'b1;
    if (pool_ack_vld) begin
      nxt_retire_info = pool_ack.info;
      nxt_retire_status = pool_ack.status;
    end
  end
  else if (retire_wr_lock) begin
    // Build a request that match all vld and unissued insn where
    // -> (srcA || srcB) == retire_dst
    // And required an wr_lock cnt update
    retire_req_info = r_retire_info;
    retire_req_info.state.vld = 1'b1;
    retire_req_info.state.rd_pdg = 1'b1;
    retire_req_info.state.pdg = 1'b0;
    retire_req_filter.match_vld = 1'b1;
    retire_req_filter.match_rd_pdg = 1'h1;
    retire_req_filter.match_pdg = 1'h1;
    retire_req_filter.match_dst_on_srcs = 1'b1;
    retire_req_filter.match_dst_on_dst = 1'b1;
    retire_req_updt.cmd = POOL_UPDATE;
    retire_req_updt.reorder = 1'b0;
    retire_req_updt.dec_wr_lock = 1'b1;

    retire_req_vld = 1'b1;
  end
  else if (retire_sync_lock) begin
    // Build a request that match all SYNC with matching sync_id
    // And required an wr_lock cnt update
    retire_req_info = r_retire_info;
    retire_req_info.state.vld = 1'b1;
    retire_req_info.insn.kind = SYNC;

    retire_req_filter.match_vld = 1'b1;
    retire_req_filter.match_sync_id = 1'b1;
    retire_req_filter.match_insn_kind = 1'b1;

    retire_req_updt.cmd = POOL_UPDATE;
    retire_req_updt.reorder = 1'b0;
    retire_req_updt.dec_wr_lock = 1'b1;

    retire_req_vld = 1'b1;
  end
end

// Query ack in retire is based on the first pool request => info & status must be buffered
assign retire_query_ack.status = r_retire_status;
assign retire_query_ack.cmd = r_query_cmd;
assign retire_query_ack.info = r_retire_info;

// ============================================================================================== //
// Issue FSM
// ============================================================================================== //
// Fsm in charge of generating retire request sequence
  typedef enum integer {
    ISSUE_XXX = 'x,
    ISSUE_IDLE = 0,
    ISSUE_SLOT,
    ISSUE_UNLOCK
  } issue_fsm_e;
  issue_fsm_e r_issue, nxt_issue;

  logic issue_idle, issue_unlock, issue_slot;
  assign issue_idle = (r_issue == ISSUE_IDLE);
  assign issue_slot = (r_issue == ISSUE_SLOT);
  assign issue_unlock = (r_issue == ISSUE_UNLOCK);

// FSM structure =============================================================================== //
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      r_issue <= ISSUE_IDLE;
    end
    else begin
      r_issue <= nxt_issue;
    end

always_comb begin
  case (r_issue)
    // ------------------------------------------------------------------------
    ISSUE_IDLE: begin
    if (query_rdy && query_vld && (query_cmd == ISSUE)) 
      nxt_issue = ISSUE_SLOT;
    else 
      nxt_issue = r_issue;
    end

    // ------------------------------------------------------------------------
    ISSUE_SLOT: begin
    if (pool_ack_vld) 
      nxt_issue = ISSUE_UNLOCK;
    else 
      nxt_issue = r_issue;
    end

    // ------------------------------------------------------------------------
    ISSUE_UNLOCK: begin
    if (pool_ack_vld) 
      nxt_issue = ISSUE_IDLE;
    else 
      nxt_issue = r_issue;
    end
    default: nxt_issue = ISSUE_XXX;
  endcase
end

// FSM logic =============================================================================== //
isc_pool_info_t r_issue_info, nxt_issue_info;
isc_ack_status_e r_issue_status, nxt_issue_status;

// Issue query logic
always_comb begin
  issue_req_vld = 1'b0;
  issue_req_info = '0;
  issue_req_filter = '0;
  issue_req_updt = '{
    cmd            : POOL_UPDATE,
    reorder        : '0,
    toggle_vld     : '0,
    toggle_rd_pdg  : '0,
    toggle_pdg     : '0,
    dec_rd_lock    : '0,
    dec_wr_lock    : '0,
    dec_issue_lock : '0
  };
  nxt_issue_info = r_issue_info;
  nxt_issue_status = r_issue_status;

  if (issue_slot) begin
    issue_req_info.state.vld = 1'b1;
    issue_req_info.state.rd_pdg = 1'b1;
    issue_req_info.state.pdg = 1'b0;
    issue_req_info.insn.kind = query_pe_rdy;

    issue_req_filter.match_vld = 1'b1;
    issue_req_filter.match_rd_pdg = 1'b1;
    issue_req_filter.match_pdg = 1'b1;
    issue_req_filter.match_insn_kind = 1'b1;
    issue_req_filter.match_lock_rdy = 1'b1;

    issue_req_updt.toggle_pdg = 1'b1;
    issue_req_updt.reorder = 1'b1;

    issue_req_vld = 1'b1;

    if (pool_ack_vld) begin
      nxt_issue_info = pool_ack.info;
      nxt_issue_status = pool_ack.status;
    end
  end

  if (issue_unlock) begin
    issue_req_info.state.vld = 1'b1;
    issue_req_info.state.rd_pdg = 1'b1;
    issue_req_info.state.pdg = 1'b0;
    // Match on the same kind with a different flush flavour. This will make flush issuing
    // decrement non flush PBS locks and vice versa.
    issue_req_info.insn.flush = !r_issue_info.insn.flush;
    issue_req_info.insn.kind = r_issue_status == SUCCESS ? r_issue_info.insn.kind : NULL_KIND;

    issue_req_filter.match_insn_kind = 1'b1;
    issue_req_filter.match_flush = 1'b1;
    issue_req_updt.dec_issue_lock = 1'b1;

    issue_req_vld = 1'b1;
  end
end

always_ff @(posedge clk)
  if (!s_rst_n) begin
    r_issue_info <= '0;
    r_issue_status <= FAILURE;
  end else begin
    r_issue_info <= nxt_issue_info;
    r_issue_status <= nxt_issue_status;
  end

assign issue_query_ack.cmd    = r_query_cmd;
assign issue_query_ack.status = r_issue_status;
assign issue_query_ack.info   = r_issue_info;

// ============================================================================================== //
// Sub-fsm muxing
// ============================================================================================== //
// Muxing default to issue request
assign pool_req_info = (!refill_idle) ? refill_req_info
                     : (!rdunlock_idle) ? rdunlock_req_info
                     : (!retire_idle) ? retire_req_info
                     : issue_req_info;
assign pool_req_filter = (!refill_idle) ? refill_req_filter
                     : (!rdunlock_idle) ? rdunlock_req_filter
                     : (!retire_idle) ? retire_req_filter
                     : issue_req_filter;
assign pool_req_updt = (!refill_idle) ? refill_req_updt
                     : (!rdunlock_idle) ? rdunlock_req_updt
                     : (!retire_idle) ? retire_req_updt
                     : issue_req_updt;
assign pool_req_vld = (!refill_idle) ? refill_req_vld
                     : (!rdunlock_idle) ? rdunlock_req_vld
                     : (!retire_idle) ? retire_req_vld
                     : issue_req_vld;
assign query_ack =  (!refill_idle) ? refill_query_ack
                     : (!rdunlock_idle) ? rdunlock_query_ack
                     : (!retire_idle) ? retire_query_ack
                     : issue_query_ack;
assign query_rdy = refill_idle && rdunlock_idle && retire_idle && issue_idle;
assign query_ack_vld = pool_ack_vld && (refill_insert || rdunlock_rd_lock || retire_sync_lock || issue_unlock);

// ============================================================================================== //
// SyncId counter
// ============================================================================================== //
// Used to attach DOp to a given IOp Id and properly generate Sync
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      r_sync_id <= '0;
    end
    else begin
      r_sync_id <= nxt_sync_id;
    end

  // Inc Sync counter on successfull SYNC insertion
  assign nxt_sync_id = (pool_ack_vld && refill_insert && (refill_req_info.insn.kind == SYNC))? $bits(r_sync_id)'(r_sync_id +1) : r_sync_id;

// ============================================================================================== //
// Assertions
// ============================================================================================== //

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      // assert($countones(upd_req_br_loop_rp_1h) <= 1)
      // else begin
      //   $fatal(1,"%t > ERROR: inc_bsk_rp hits more than 1 requestor!", $time);
      // end
    end
// pragma translate_on

endmodule
