// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Instruction lookahead scheduler
// ----------------------------------------------------------------------------------------------
//
// Scheduler that extract instruction level parallelism with the help of lookahead buffer
//
// ==============================================================================================

module instruction_scheduler
  import param_tfhe_pkg::*;
  import pep_common_param_pkg::*;
  import instruction_scheduler_pkg::*;
  import hpu_common_instruction_pkg::*;
  import regf_common_param_pkg::*;
  import isc_common_param_pkg::*;
  (
    input logic  clk,        // clock
    input logic  s_rst_n,    // synchronous reset

    // Quasi static
    input logic use_bpip,

    // Insn stream interface
    output logic                 insn_rdy,
    input  logic[PE_INST_W-1: 0] insn_pld,
    input  logic                 insn_vld,

    // Pseudo stream for ack
    input  logic                 insn_ack_rdy,
    output logic[PE_INST_W-1: 0] insn_ack_cnt,
    output logic                 insn_ack_vld,

    // PE interface
    // Each PE have a rdy/vld interface with insn as payload
    // PE acknowledge work completion trough an ack signal
    input  logic                 pem_rdy,
    output logic[PE_INST_W-1: 0] pem_insn,
    output logic                 pem_vld,
    input  logic                 pem_load_ack,
    input  logic                 pem_store_ack,

    input  logic                 pea_rdy,
    output logic[PE_INST_W-1: 0] pea_insn,
    output logic                 pea_vld,
    input  logic                 pea_ack,

    input  logic                 pep_rdy,
    output logic[PE_INST_W-1: 0] pep_insn,
    output logic                 pep_vld,
    input  logic                 pep_rd_ack,
    input  logic                 pep_wr_ack,
    input  logic[LWE_K_W-1:0]    pep_ack_pld,

    // Stats and Trace interface
    // Stats reported to regif
    output isc_counter_inc_t     isc_counter_inc,
    output isc_info_t            isc_rif_info,
    // Trace manager
    output logic                 trace_wr_en,
    output isc_trace_t           trace_data

);

// ============================================================================================== //
// type
// ============================================================================================== //
// Pe signals are merged in a vector with following order
  typedef enum integer {
    PEM_OFS=0,
    PEA_OFS=1,
    PEP_OFS=2
  } pex_ofs_e;
  localparam int PE_NB = 3;

// ============================================================================================== //
// Signals
// ============================================================================================== //
  // PeX merged signal
  // Two version internal one and output one with fifoelem between for timing purpose
  logic [PE_NB-1:0] pe_rdy, pe_rdy_out;
  logic [PE_NB-1:0] pe_vld, pe_vld_out;
  logic [PE_NB-1:0][PE_INST_W-1: 0] pe_insn_out;
  isc_pool_ack_t                pool_ack;

  // Pool Query 
  logic                    query_rdy;
  isc_query_cmd_e              query_cmd;
  isc_insn_t               query_refill;
  logic [INSN_KIND_W-1: 0] query_pe_rd_ack;
  logic [INSN_KIND_W-1: 0] query_pe_wr_ack;
  logic [INSN_KIND_W-1: 0] query_pe_rdy;
  logic                    query_vld;
  isc_query_ack_t          query_ack;
  logic                    query_ack_vld;


// ============================================================================================== //
// Insn & Insn_ack stream Rdy/Vld buffering
// ============================================================================================== //
logic                  f2_insn_rdy;
logic [PE_INST_W-1: 0] f2_insn_pld;
logic                  f2_insn_vld;

// Use FifoElem type 3 to cut the rdy/vld and data path for timing purpose
fifo_element #(
  .WIDTH          (PE_INST_W),
  .DEPTH          (1),
  .TYPE_ARRAY     (4'h3),
  .DO_RESET_DATA  (0),
  .RESET_DATA_VAL (0)
) insn_fifo_element (
  .clk     (clk),
  .s_rst_n(s_rst_n),

  .in_data (insn_pld),
  .in_vld  (insn_vld),
  .in_rdy  (insn_rdy),

  .out_data(f2_insn_pld),
  .out_vld (f2_insn_vld),
  .out_rdy (f2_insn_rdy)
);

logic                  f2_insn_ack_rdy;
logic [PE_INST_W-1: 0] f2_insn_ack_cnt;
logic                  f2_insn_ack_vld;

// Use FifoElem type 3 to cut the rdy path for timing purpose
fifo_element #(
  .WIDTH          (PE_INST_W),
  .DEPTH          (1),
  .TYPE_ARRAY     (4'h3),
  .DO_RESET_DATA  (0),
  .RESET_DATA_VAL (0)
) insn_ack_fifo_element (
  .clk     (clk),
  .s_rst_n(s_rst_n),

  .in_data (f2_insn_ack_cnt),
  .in_vld  (f2_insn_ack_vld),
  .in_rdy  (f2_insn_ack_rdy),

  .out_data(insn_ack_cnt),
  .out_vld (insn_ack_vld),
  .out_rdy (insn_ack_rdy)
);

// ============================================================================================== //
// PE ACK buffering
// ============================================================================================== //
// No real rules constraints the ack signal generation.
// They could arise at the same time without rdy/vld interface
// => To prevent ack lost, we buffer them with a custom no_data_fifo that buffer ack signals
//    with a rdy/vld itf
// Pack each pe ack in a vector
// 3: pep
// 2: pea
// 1: pem_store
// 0: pem_load

// PePbs generate ack in 2 phase rd_unlock/ wr_done
// Query and Pool handle these two steps for all pe
// -> Thus, we artificially duplicate pe_ack in pe_rd_ack/pe_wr_ack

logic [INSN_KIND_W-2: 0] raw_rd_ack, rd_ack_vld, rd_ack_rdy;
logic [INSN_KIND_W-2: 0] raw_wr_ack, wr_ack_vld, wr_ack_rdy;

// WARN: This binding must be kept align with insn_state_e one-hot definition
assign raw_rd_ack = {pep_rd_ack, pea_ack, pem_store_ack, pem_load_ack};
assign raw_wr_ack = {pep_wr_ack, pea_ack, pem_store_ack, pem_load_ack};

generate
  for (genvar gen_i = 0; gen_i < INSN_KIND_W-1; gen_i = gen_i + 1) begin : ack_loop_gen
    // Ensure that no overflow can occur. Independently on the processing
    // elements, no more than POOL_SLOT_NB can be inflight.
    isc_evt #(
      .CNT_W(POOL_SLOT_W+1)
    ) rd_ack_cnt_gen_i (
      .clk(clk),
      .s_rst_n(s_rst_n),
      .in_evt(raw_rd_ack[gen_i]),
      .out_vld(rd_ack_vld[gen_i]),
      .out_rdy(rd_ack_rdy[gen_i])
    );

    isc_evt #(
      .CNT_W(POOL_SLOT_W+1)
    ) wr_ack_cnt_gen_i (
      .clk(clk),
      .s_rst_n(s_rst_n),
      .in_evt(raw_wr_ack[gen_i]),
      .out_vld(wr_ack_vld[gen_i]),
      .out_rdy(wr_ack_rdy[gen_i])
    );
  end
endgenerate

// Also buffered pep_ack_pld for proper use in trace manager
logic                 f_pep_ack_vld;
logic                 f_pep_ack_rdy;
logic[LWE_K_W-1:0]    f_pep_ack_pld;

fifo_reg #(
  .WIDTH(LWE_K_W),
  .DEPTH(BATCH_PBS_NB),
  // This gets implemented as a RAM, with a very short C2Q time. No need for the output register
  .LAT_PIPE_MH({1'b0, 1'b0})
) pep_ack_pld_fifo(
  .clk(clk),     // clock
  .s_rst_n(s_rst_n), // synchronous reset

  .in_data(pep_ack_pld),
  .in_vld(pep_wr_ack),
  .in_rdy(/*Not used*/),

  .out_data(f_pep_ack_pld),
  .out_vld(f_pep_ack_vld),
  .out_rdy(f_pep_ack_rdy)
);

// ============================================================================================== //
// PE Rdy/Vld buffering
// ============================================================================================== //
// Use FifoElem type 2 to cut the rdy path for timing purpose

generate
  for (genvar gen_i = 0; gen_i < PE_NB; gen_i = gen_i + 1) begin : pe_loop_gen
    fifo_element #(
      .WIDTH          (PE_INST_W),
      .DEPTH          (1),
      .TYPE_ARRAY     (4'h3),
      .DO_RESET_DATA  (0),
      .RESET_DATA_VAL (0)
    ) pe_out_fifo_element (
      .clk     (clk),
      .s_rst_n(s_rst_n),

      .in_data (query_ack.info.insn.raw_insn),
      .in_vld  (pe_vld[gen_i]),
      .in_rdy  (pe_rdy[gen_i]),

      .out_data(pe_insn_out[gen_i]),
      .out_vld (pe_vld_out[gen_i]),
      .out_rdy (pe_rdy_out[gen_i])
    );
  end
  endgenerate

  // Connect module input ready fifo_elem
  assign pe_rdy_out = {pep_rdy, pea_rdy, pem_rdy};

  // Construct multi-hot ready that duplicated pem_rdy (For kind LD/ kind ST)
  // And also assert SYNC rdy
  assign query_pe_rdy = {1'b1, pe_rdy, pe_rdy[0]};
  // Connect pe_ack to query_pe_ack
  assign query_pe_rd_ack = rd_ack_vld;
  assign query_pe_wr_ack = wr_ack_vld;

  // Connect buffered output to module out
  assign pem_insn = pe_insn_out[PEM_OFS];
  assign pem_vld = pe_vld_out[PEM_OFS];

  assign pea_insn = pe_insn_out[PEA_OFS];
  assign pea_vld = pe_vld_out[PEA_OFS];

  assign pep_insn = pe_insn_out[PEP_OFS];
  assign pep_vld = pe_vld_out[PEP_OFS];

// ============================================================================================== //
// Ack generation
// ============================================================================================== //
// Convert ack pulse in pseudo stream for easy interfacing with hpu
logic insn_ack;
isc_ack #(
  .CNT_W(PE_INST_W)
) ack_pseudo_stream (
      .clk(clk),
      .s_rst_n(s_rst_n),
      .in_pulse(insn_ack),
      .out_vld(f2_insn_ack_vld),
      .out_cnt(f2_insn_ack_cnt),
      .out_rdy(f2_insn_ack_rdy)
    );

// ============================================================================================== //
// Instances of Query/Pool and instruction parser
// ============================================================================================== //
// Contain the main module logic:
//  * Pool is the data store with simple request/update interface
//  * Query is the high level logic that issue sequence of request/update to construct the targeted function
isc_pool_info_t          pool_req_info;
isc_pool_filter_t        pool_req_filter;
isc_pool_updt_t          pool_req_updt;
logic                    pool_req_vld;

logic                    pool_ack_vld;
logic [POOL_SLOT_W: 0]   pool_free_slot;

isc_query #() isc_query (
  .clk(clk),
  .s_rst_n(s_rst_n),

  .use_bpip(use_bpip),

  .query_rdy(query_rdy),
  .query_cmd(query_cmd),
  .query_refill(query_refill),
  .query_pe_rd_ack(query_pe_rd_ack),
  .query_pe_wr_ack(query_pe_wr_ack),
  .query_pe_rdy(query_pe_rdy),
  .query_vld(query_vld),
  .query_ack(query_ack),
  .query_ack_vld(query_ack_vld),

  .pool_req_info(pool_req_info),
  .pool_req_filter(pool_req_filter),
  .pool_req_updt(pool_req_updt),
  .pool_req_vld(pool_req_vld),
  .pool_ack(pool_ack),
  .pool_ack_vld(pool_ack_vld)
);

isc_pool #() isc_pool (
  .clk(clk),
  .s_rst_n(s_rst_n),

  .req_info(pool_req_info),
  .req_filter(pool_req_filter),
  .req_updt(pool_req_updt),
  .req_vld(pool_req_vld),

  .ack_vld(pool_ack_vld),
  .ack(pool_ack),

  .free_slot(pool_free_slot)
);

isc_parser #() isc_parser (
  .insn(f2_insn_pld),
  .kind(query_refill.kind),
  .dst_id(query_refill.dst_id),
  .srcA_id(query_refill.srcA_id),
  .srcB_id(query_refill.srcB_id),
  .flush(query_refill.flush)
);
assign query_refill.raw_insn = f2_insn_pld;

// Convert query/pool ack in internal signal
// Insn Ack generated while a SYNC instruction is retired with success
// Pe_ack is generated for other retired insn
//NB: MSB filtered out implicitly -> No ack for sync kind
logic rdunlock_ack;
logic retired_ack;

// RDUNLOCK:
assign rdunlock_ack = query_ack_vld && (query_ack.status == SUCCESS) && (query_ack.cmd == RDUNLOCK);
assign rd_ack_rdy =  {INSN_KIND_W{rdunlock_ack}} & query_ack.info.insn.kind;

// RETIRE:
assign retired_ack = query_ack_vld && (query_ack.status == SUCCESS) && (query_ack.cmd == RETIRE);
assign wr_ack_rdy =  {INSN_KIND_W{retired_ack}} & query_ack.info.insn.kind;

// REFILL -> Consume entry in the input stream
assign f2_insn_rdy = (query_ack_vld && (query_ack.status == SUCCESS) && (query_ack.cmd == REFILL));

// ISSUE -> Generate pe_vld
assign pe_vld[PEM_OFS] = (query_ack_vld && (query_ack.status == SUCCESS) && (query_ack.cmd == ISSUE) && |(query_ack.info.insn.kind & (MEM_LD|MEM_ST)));
assign pe_vld[PEA_OFS] = (query_ack_vld && (query_ack.status == SUCCESS) && (query_ack.cmd == ISSUE) && (query_ack.info.insn.kind == ARITH));
assign pe_vld[PEP_OFS] = (query_ack_vld && (query_ack.status == SUCCESS) && (query_ack.cmd == ISSUE) && (query_ack.info.insn.kind == PBS));

// NB: PE_sync slighly differ from other pe
// Indeed no need to issue then retire sync instruction
// Thus the sync ack is directly generated at the issue stage.
// Internally pool that issue a SYNC directly release the slot
assign insn_ack = (query_ack_vld && (query_ack.status == SUCCESS) && (query_ack.cmd == ISSUE) && (query_ack.info.insn.kind == SYNC));

// ============================================================================================== //
// Arbiter
// ============================================================================================== //
// Aims is to remove finish instruction asap and to ensure that the pool is filled as much as possible
assign query_cmd = |rd_ack_vld ? RDUNLOCK
                 : |wr_ack_vld ? RETIRE
                 : (f2_insn_vld & (|pool_free_slot))? REFILL
                 : (|pe_rdy) ? ISSUE
                 : NONE;

// TODO fixme completly useless vld signal ...
assign query_vld = !query_ack_vld;


// ============================================================================================== //
// Counters and info for regif
// ============================================================================================== //
  isc_counter_inc_t isc_counter_incD;
  isc_info_t        isc_rif_infoD;

  always_comb begin
    isc_counter_incD = '0;
    isc_rif_infoD    = '0;

    isc_counter_incD.ack_inc  = f2_insn_ack_rdy & f2_insn_ack_vld;
    isc_counter_incD.inst_inc = f2_insn_rdy & f2_insn_vld;

    isc_rif_infoD.insn_pld[0]   = f2_insn_rdy && f2_insn_vld ? f2_insn_pld : isc_rif_info.insn_pld[0];
    isc_rif_infoD.insn_pld[3:1] = f2_insn_rdy && f2_insn_vld ? isc_rif_info.insn_pld[2:0] : isc_rif_info.insn_pld[3:1];
  end


  always_ff @(posedge clk)
    if (!s_rst_n) begin
      isc_counter_inc <= '0;
      isc_rif_info    <= '0;
    end
    else begin
      isc_counter_inc <= isc_counter_incD;
      isc_rif_info    <= isc_rif_infoD;
    end
    
// ============================================================================================== //
// Timestamp and Trace generation
// ============================================================================================== //
  logic [TIMESTAMP_W-1:0] nxt_timestamp;

  // Timestamp is a free running counter
  assign nxt_timestamp = trace_data.timestamp + 1;
  
  // Flop all trace data
  always_ff @(posedge clk)
    if(!s_rst_n) begin
      trace_wr_en <= 1'b0;
    end else begin
      // Write trace for each successfull query
      trace_wr_en <= (query_ack.status == SUCCESS) && query_ack_vld;
    end

  always_ff @(posedge clk) begin
    trace_data.timestamp <= nxt_timestamp;
    trace_data.insn <= query_ack.info.insn.raw_insn;
    trace_data.cmd <= query_ack.cmd;
    trace_data.state <= query_ack.info.state;
    trace_data.pe_reserved <=
      ((query_ack.cmd == RETIRE) && (query_ack.info.insn.kind == PBS)) ?
        f_pep_ack_pld : '0;
  end

  // Consume pep_ack_fifo
  assign f_pep_ack_rdy = trace_wr_en && (query_ack.cmd == RETIRE) && (query_ack.info.insn.kind == PBS);

// ============================================================================================== //
// Assertions
// ============================================================================================== //
// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      // Following assert help to found root cause of pipeline issue
      // Inner pipeline of isc_pool is only for timing purpose

      // Check correct update of pinfo in case of retire
      if (query_ack_vld && (query_ack.status == SUCCESS) && (query_ack.cmd == RETIRE)) begin
        assert ( !isc_pool.r_pinfo[POOL_SLOT_NB-1].state.rd_pdg && !isc_pool.r_pinfo[POOL_SLOT_NB-1].state.pdg && !isc_pool.r_pinfo[POOL_SLOT_NB-1].state.vld) 
        else begin
          $fatal(1,"%t > ERROR: Instruction RETIRED but slot not properly released.", $time);
        end
      end

      // Check correct update of pinfo in case of RDUNLOCK
      if (query_ack_vld && (query_ack.status == SUCCESS) && (query_ack.cmd == RDUNLOCK)) begin
        assert ( !isc_pool.r_pinfo[POOL_SLOT_NB-1].state.rd_pdg && isc_pool.r_pinfo[POOL_SLOT_NB-1].state.pdg && isc_pool.r_pinfo[POOL_SLOT_NB-1].state.vld) 
        else begin
          $fatal(1,"%t > ERROR: Instruction %x RDUNLOCK but slot state not properly updated.", $time, query_ack.info.insn.raw_insn);
        end
      end

      // Check correct update of pinfo in case of issue
      if (query_ack_vld && (query_ack.status == SUCCESS) && (query_ack.cmd == ISSUE)
         && query_ack.info.insn.kind != SYNC /*SYNC have particular handling */) begin
        assert ( isc_pool.r_pinfo[POOL_SLOT_NB-1].state.rd_pdg && isc_pool.r_pinfo[POOL_SLOT_NB-1].state.pdg && isc_pool.r_pinfo[POOL_SLOT_NB-1].state.vld) 
        else begin
          $fatal(1,"%t > ERROR: Instruction %x ISSUED but slot state not properly updated.", $time, query_ack.info.insn.raw_insn);
        end
      end

      // Check correct update of pinfo in case of refill
      if (query_ack_vld && (query_ack.status == SUCCESS) && (query_ack.cmd == REFILL)
         && query_ack.info.insn.kind != SYNC /*SYNC have particular handling */) begin
        assert ( isc_pool.r_pinfo[POOL_SLOT_NB-1].state.rd_pdg && !isc_pool.r_pinfo[POOL_SLOT_NB-1].state.pdg && isc_pool.r_pinfo[POOL_SLOT_NB-1].state.vld) 
        else begin
          $fatal(1,"%t > ERROR: Instruction REFILLED but slot state not properly updated.", $time);
        end
      end

      if (f2_insn_rdy & f2_insn_vld & (query_refill.kind == PBS)) begin
        assert(~|(query_refill.dst_id.isc.id & ~query_refill.dst_id.mask))
        else begin
          $fatal(1, {"%0t > ERROR: ManyLUT destination RID doesn't align to the ",
            "number of PBS outputs. Destination RID: 0x%0x, ",
            "Number of PBS outputs: %0d"},
            $realtime, query_refill.dst_id.isc.id, query_refill.dst_id.mask+1);
        end
      end
    end
// pragma translate_on
endmodule
