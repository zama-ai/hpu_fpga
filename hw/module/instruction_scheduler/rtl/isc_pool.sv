// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Instruction scheduler pool
// ----------------------------------------------------------------------------------------------
//
// Custom command pool that support filter/update requests.
// Store properties and states of inflight instructions
//
//
// ==============================================================================================

module isc_pool
  import instruction_scheduler_pkg::*;
  import hpu_common_instruction_pkg::*;
  import regf_common_param_pkg::*;
  (
    input  logic                                    clk,        // clock
    input  logic                                    s_rst_n,    // synchronous reset

    // request interface with Rdy/Vld
    // Wrap info/filter/updt in same rdy/vld bundle
    input  isc_pool_info_t                          req_info,
    input  isc_pool_filter_t                        req_filter,
    input  isc_pool_updt_t                          req_updt,
    input  logic                                    req_vld,

    output logic                                    ack_vld,
    output isc_pool_ack_t                           ack,

    // Report number of invalid slot
    output logic [POOL_SLOT_W: 0]                   free_slot
);

// ============================================================================================== //
// Pool info
// ============================================================================================== //
  isc_pool_info_t [POOL_SLOT_NB-1:0] r_pinfo, nxt_pinfo;
  logic r_pinfo_ce;

  // Just reset the valid signal
  always_ff @(posedge clk) begin
    for (int i = 0; i < POOL_SLOT_NB; i++)
      if (!s_rst_n) begin
        r_pinfo[i].state.vld <= '0;
      end else if(r_pinfo_ce) begin
        r_pinfo[i].state.vld <= nxt_pinfo[i].state.vld;
      end
  end

  always_ff @(posedge clk)
    for (int i = 0; i < POOL_SLOT_NB; i++)
      if(r_pinfo_ce) begin
        r_pinfo[i].insn             <= nxt_pinfo[i].insn;
        r_pinfo[i].state.sync_id    <= nxt_pinfo[i].state.sync_id    ;
        r_pinfo[i].state.rd_lock    <= nxt_pinfo[i].state.rd_lock    ;
        r_pinfo[i].state.wr_lock    <= nxt_pinfo[i].state.wr_lock    ;
        r_pinfo[i].state.issue_lock <= nxt_pinfo[i].state.issue_lock ;
        r_pinfo[i].state.rd_pdg     <= nxt_pinfo[i].state.rd_pdg     ;
        r_pinfo[i].state.pdg        <= nxt_pinfo[i].state.pdg        ;
      end

// ============================================================================================== //
// Pool control
// ============================================================================================== //
// Pool request is hand pipelined with the following stages:
// c0 -> Filter matching slots based on req_info and req_filter
// c1 -> Combine filter results
// c2 -> Count the number of matches and find the first match
// c3 -> Update pool state bosed on req_updt and acknowledge the request

  logic r_busy;
  always_ff @(posedge clk)
    if(!s_rst_n) begin
      r_busy <= '0;
    end else begin
      // set with req_vld, reset with ack_vld;
      r_busy <= (req_vld || r_busy) && !ack_vld;
    end

  typedef struct packed {
    isc_pool_info_t   info;
    isc_pool_filter_t filter;
    isc_pool_updt_t   updt;
    logic             vld;
  } req_t;
  req_t req;

  always_ff @(posedge clk)
    if(!s_rst_n) begin
      req.vld  <= '0;
    end else begin
      req.vld  <= req_vld && !r_busy;
    end

  always_ff @(posedge clk) begin
    req.info   <= req_info;
    req.filter <= req_filter;
    req.updt   <= req_updt;
  end

// ============================================================================================== //
// C0: Filter stage
// Aims is to extract multi-hot vector of slot matching the current info/filter
// ============================================================================================== //

  logic [POOL_SLOT_NB-1:0] sync_id_match_mh, vld_match_mh, rd_pdg_match_mh, pdg_match_mh, lock_rdy_match_mh;
  logic [POOL_SLOT_NB-1:0] insn_kind_match_mh, dst_on_srcs_match_mh, srcs_on_dst_match_mh, dst_on_dst_match_mh, insn_flush_match_mh;

  typedef struct packed {
    logic vld;
    logic [2:0][POOL_SLOT_NB-1:0] filter_mh;
  } c0_data_t;
  c0_data_t c0_data;

  // 1. describe filter logic
  // There is match when slot info masked by query match the query.
  // Indeed, field used one-hot encoding to be able to match on multiple states or bypass entries
  // All this logic runs in parallel for each slot. While it takes a bunch of
  // resources, adding more slots won't affect the critical path.

  always_comb for (int i=0; i<POOL_SLOT_NB; i=i+1) begin
      sync_id_match_mh[i]     = (!req.filter.match_sync_id)? 1'b1
                                 : (req.info.state.sync_id == r_pinfo[i].state.sync_id);
      vld_match_mh[i]         = (!req.filter.match_vld        )? 1'b1
                                 : (req.info.state.vld     == r_pinfo[i].state.vld);
      rd_pdg_match_mh[i]      = (!req.filter.match_rd_pdg  )? 1'b1
                                 : (req.info.state.rd_pdg  == r_pinfo[i].state.rd_pdg);
      pdg_match_mh[i]         = (!req.filter.match_pdg  )? 1'b1
                                 : (req.info.state.pdg     == r_pinfo[i].state.pdg);
      lock_rdy_match_mh[i]    = (!req.filter.match_lock_rdy   )? 1'b1
                                 : (r_pinfo[i].state.wr_lock == 0 && r_pinfo[i].state.rd_lock == 0
                                                                  && r_pinfo[i].state.issue_lock == 0);
      insn_kind_match_mh[i]   = (!req.filter.match_insn_kind  )? 1'b1
                                 : (r_pinfo[i].insn.kind & req.info.insn.kind) == r_pinfo[i].insn.kind;
      insn_flush_match_mh[i]  = (!req.filter.match_flush)? 1'b1
                                 : (req.info.insn.flush == r_pinfo[i].insn.flush);
      dst_on_srcs_match_mh[i] = (!req.filter.match_dst_on_srcs)? 1'b1
                                 : ((req.info.insn.dst_id.isc.mode != UNUSED)
                                 && (dest_within(req.info.insn.dst_id, r_pinfo[i].insn.srcA_id)
                                    || dest_within(req.info.insn.dst_id, r_pinfo[i].insn.srcB_id)));
      dst_on_dst_match_mh[i]  = (!req.filter.match_dst_on_dst)? 1'b0
                                 : ((req.info.insn.dst_id.isc.mode != UNUSED)
                                 && dest_within_dest(req.info.insn.dst_id, r_pinfo[i].insn.dst_id));
      srcs_on_dst_match_mh[i] = (!req.filter.match_srcs_on_dst)? 1'b1
                                 : (((req.info.insn.srcA_id.mode != UNUSED)
                                 && dest_within(r_pinfo[i].insn.dst_id, req.info.insn.srcA_id))
                                 || ((req.info.insn.srcB_id.mode != UNUSED)
                                 && dest_within(r_pinfo[i].insn.dst_id, req.info.insn.srcB_id)));
  end

  // Combining her up to 4 filters at this cycle

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      c0_data.vld <= '0;
    end else begin
      c0_data.vld <= req.vld;
    end

  always_ff @(posedge clk) begin
    c0_data.filter_mh[0] <= sync_id_match_mh & vld_match_mh & rd_pdg_match_mh & pdg_match_mh;
    c0_data.filter_mh[1] <= lock_rdy_match_mh & insn_kind_match_mh & insn_flush_match_mh;
    c0_data.filter_mh[2] <= ((dst_on_srcs_match_mh & srcs_on_dst_match_mh) | dst_on_dst_match_mh);
  end

  // ============================================================================================== //
  // C1: Filter Combination
  // Combine all the filter logic. Adding one more slot here, will affect the
  // critical path. However, this grows with log(n) complexity, where n are the
  // number of slots and the number of filters, so it is not as bad as it might seem.
  // ============================================================================================== //
  typedef struct packed {
    logic vld;
    logic [POOL_SLOT_NB-1:0] match_mh;
  } c1_data_t ;
  c1_data_t c1_data;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      c1_data.vld <= '0;
    end else begin
      c1_data.vld <= c0_data.vld;
    end

  always_ff @(posedge clk)
    c1_data.match_mh <= c0_data.filter_mh[0] & c0_data.filter_mh[1] & c0_data.filter_mh[2];

// ============================================================================================== //
// C2: Match Count
// Counts the number of matches and finds the first match
// ============================================================================================== //

  // 2. Extract global information
  logic [POOL_SLOT_NB-1:0] c1_match_oldest_1h;
  logic [POOL_SLOT_W-1:0]  c1_match_oldest_id;
  logic [POOL_SLOT_W:0]    c1_match_count;

  // Matching could be order from oldest to newest (LSB -> MSB)
  // Thus the oldest one is always the first bit equal to 1
  common_lib_find_first_bit_equal_to_1
  #(
    .NB_BITS(POOL_SLOT_NB)
  ) c1_find_oldest_match (
    .in_vect_mh          (c1_data.match_mh),
    .out_vect_1h         (c1_match_oldest_1h),
    .out_vect_ext_to_msb (/*UNUSED*/)
  );

  // Convert oldest 1h in id
  common_lib_one_hot_to_bin #(
    .ONE_HOT_W (POOL_SLOT_NB)
  ) c1_match_oldest_htb (
    .in_1h     (c1_match_oldest_1h),
    .out_value (c1_match_oldest_id)
  );

  // Compute the number of matches
  common_lib_count_ones #(
    .MULTI_HOT_W (POOL_SLOT_NB)
  ) c1_count_matches (
    .in_mh   (c1_data.match_mh),
    .out_cnt (c1_match_count)
  );

  typedef struct packed {
    logic                    vld;
    logic [POOL_SLOT_NB-1:0] match_oldest_1h;
    logic [POOL_SLOT_W-1:0]  match_oldest_id;
    logic [POOL_SLOT_W:0]    match_count;
    logic [POOL_SLOT_NB-1:0] match_mh;
    logic                    has_match;
  } c2_data_t;
  c2_data_t c2_data;

  always_ff @(posedge clk)
    if(!s_rst_n) begin
      c2_data.vld <= '0;
    end else begin
      c2_data.vld <= c1_data.vld;
    end

  always_ff @(posedge clk) begin
    c2_data.match_oldest_1h <= c1_match_oldest_1h;
    c2_data.match_oldest_id <= c1_match_oldest_id;
    c2_data.match_count     <= c1_match_count;
    c2_data.match_mh        <= c1_data.match_mh;
    c2_data.has_match       <= |c1_data.match_mh;
  end

// ============================================================================================== //
// C3: Ack
// Compute next pool state and Ack
// ============================================================================================== //

  // 3. Describe Update logic
  // Update structure
  isc_pool_info_t [POOL_SLOT_NB:0] extend_pinfo;
  isc_pool_info_t [POOL_SLOT_NB-1:0] updt_pinfo, ordered_pinfo;
  isc_pool_info_t updt_req_info;

  // Pool structure is update from left to write with partial Update/Reorder
  // New entry is always insert on the left. Slot could take update value from the left-slot
  // or from the same-slot
  // Apply requested update on matching entry
  always_comb begin
    for (int i=0; i < POOL_SLOT_NB; i=i+1) begin
      updt_pinfo[i] = r_pinfo[i];
      // vld/pdg update are single-slot update
      if (c2_data.match_oldest_1h[i]) begin
        if (r_pinfo[i].insn.kind == SYNC) begin
          // Custom handling of Sync instruction -> Issue directly release the slot
          updt_pinfo[i].state.vld = r_pinfo[i].state.vld ^ req.updt.toggle_pdg;
        end else begin
          // Standard update path
          updt_pinfo[i].state.vld    = r_pinfo[i].state.vld    ^ req.updt.toggle_vld;
          updt_pinfo[i].state.rd_pdg = r_pinfo[i].state.rd_pdg ^ req.updt.toggle_rd_pdg;
          updt_pinfo[i].state.pdg    = r_pinfo[i].state.pdg    ^ req.updt.toggle_pdg;
        end
      end

      // RdWr- Lock are muli-slot update
      if (c2_data.match_mh[i]) begin
        updt_pinfo[i].state.rd_lock = (r_pinfo[i].state.rd_lock != 0)? r_pinfo[i].state.rd_lock - req.updt.dec_rd_lock: '0;
        updt_pinfo[i].state.wr_lock = (r_pinfo[i].state.wr_lock != 0)? r_pinfo[i].state.wr_lock - req.updt.dec_wr_lock: '0;
        updt_pinfo[i].state.issue_lock = (r_pinfo[i].state.issue_lock != 0)? r_pinfo[i].state.issue_lock - req.updt.dec_issue_lock: '0;
      end
    end
  end

  // Extend vector with inserted value
  // Left slot could be from pinfo or from updt_req_info
  // NB: Also apply vld/pdg update on refill entry (Enable to match on a condition and insert an updated value)
  always_comb begin
    updt_req_info              = req.info;
    updt_req_info.state.vld    = req.info.state.vld    ^ req.updt.toggle_vld;
    updt_req_info.state.rd_pdg = req.info.state.rd_pdg ^ req.updt.toggle_rd_pdg;
    updt_req_info.state.pdg    = req.info.state.pdg    ^ req.updt.toggle_pdg;

    for (int i=0; i< POOL_SLOT_NB; i=i+1) begin
      extend_pinfo[i] = updt_pinfo[i];
    end
    extend_pinfo[POOL_SLOT_NB] = (req.updt.cmd == POOL_UPDATE) ? updt_pinfo[c2_data.match_oldest_id]: updt_req_info;
  end

  // Apply reorder
  always_comb begin
    for (int i=0; i< POOL_SLOT_NB; i=i+1) begin
      ordered_pinfo[i] = (req.updt.reorder && c2_data.has_match
                      && (c2_data.match_oldest_id <= POOL_SLOT_W'(i))) ?
                         extend_pinfo[i+1]: extend_pinfo[i];
    end
  end

  assign r_pinfo_ce = c2_data.vld;
  assign nxt_pinfo  = ordered_pinfo;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      ack_vld <= '0;
    end else begin
      ack_vld <= c2_data.vld;
    end

  always_ff @(posedge clk) begin
    if (c2_data.vld) begin
      ack.status   <= c2_data.has_match ? SUCCESS : FAILURE;
      ack.nb_match <= c2_data.match_count;
      ack.info     <= r_pinfo[c2_data.match_oldest_id]; // Return the slot before update
    end
  end

// ============================================================================================== //
// Keep track of unused slot
// ============================================================================================== //
  logic [POOL_SLOT_NB-1:0] free_slot_mh;
  logic [POOL_SLOT_W:0]  free_slot_count;

  always_comb begin
      for (int i=0; i<POOL_SLOT_NB; i=i+1) begin
        free_slot_mh[i] = !r_pinfo[i].state.vld;
      end
  end

  // Compute the number of free_slot
    common_lib_count_ones #(
    .MULTI_HOT_W (POOL_SLOT_NB)
  ) count_free_slot (
    .in_mh   (free_slot_mh),
    .out_cnt (free_slot_count)
  );
  assign free_slot = free_slot_count;

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

  // These are here just to help debug the pool register file. It is
  // encapsulated in layers of structures and it is very hard to see what's
  // going on in the wave viewer.
  logic [POOL_SLOT_NB-1:0]                  _slot_vld;
  int                                       _slot_vld_nb;
  logic [POOL_SLOT_NB-1:0]                  _slot_rd_pdg;
  logic [POOL_SLOT_NB-1:0]                  _slot_pdg;
  logic [POOL_SLOT_NB-1:0][INSN_KIND_W-1:0] _slot_kind;
  logic [POOL_SLOT_NB-1:0][PE_INST_W-1:0]   _slot_raw_insn;
  logic [POOL_SLOT_NB-1:0][POOL_SLOT_W:0]   _slot_rd_lock;
  logic [POOL_SLOT_NB-1:0][POOL_SLOT_W:0]   _slot_wr_lock;
  logic [POOL_SLOT_NB-1:0][POOL_SLOT_W:0]   _slot_issue_lock;
  logic [POOL_SLOT_NB-1:0]                  _slot_issue_ready;
  logic [POOL_SLOT_NB-1:0]                  _pe_inflight;
  int                                       _pe_inflight_nb;

  generate for(genvar i = 0; i < POOL_SLOT_NB; i++) begin: gen_debug_info
    assign _slot_vld[i]         = r_pinfo[i].state.vld;
    assign _slot_rd_pdg[i]      = r_pinfo[i].state.rd_pdg;
    assign _slot_pdg[i]         = r_pinfo[i].state.pdg;
    assign _slot_kind[i]        = r_pinfo[i].insn.kind;
    assign _slot_raw_insn[i]    = r_pinfo[i].insn.raw_insn;
    assign _slot_rd_lock[i]     = r_pinfo[i].state.rd_lock;
    assign _slot_wr_lock[i]     = r_pinfo[i].state.wr_lock;
    assign _slot_issue_lock[i]     = r_pinfo[i].state.issue_lock;
    assign _pe_inflight[i]      = _slot_vld[i] & _slot_pdg[i];
    assign _slot_issue_ready[i] = _slot_vld[i] & _slot_rd_pdg[i] & ~(_slot_pdg[i]) &
                                  (_slot_rd_lock[i] == '0) & (_slot_wr_lock[i] == '0) &
                                  (_slot_issue_lock[i] == '0);
  end
  endgenerate

  assign _pe_inflight_nb = $countones(_pe_inflight);
  assign _slot_vld_nb = $countones(_slot_vld);
// pragma translate_on

endmodule
