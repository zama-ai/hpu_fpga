// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Testbench for instruction level scheduler
// ==============================================================================================

module tb_instruction_scheduler;
`timescale 1ns/10ps

 import param_tfhe_pkg::*;
 import instruction_scheduler_pkg::*;
 import pep_common_param_pkg::*;
 import isc_common_param_pkg::*;
 import hpu_common_instruction_pkg::*;
 import regf_common_param_pkg::*;

 import file_handler_pkg::*;
 import random_handler_pkg::*;

// ============================================================================================== --
// Parameters
// ============================================================================================== --
  parameter int USE_BPIP = 1;

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int CLK_HALF_PERIOD = 1;
  localparam int ARST_ACTIVATION = 17;

  localparam int SLOT_NB=8;

  // Input Files
  localparam string FILE_DATA_TYPE   = "ascii_hex";
  localparam string FILE_ASM_INSN    = "input/dop_stream.hex";
  localparam int    ASM_INSN_HALT    = 2; // Chance to draw long delay over 255 values

  localparam int DOP_SYNC_WORD = 'h4000fff0;
  localparam int DOP_ITER = 4;

  // Max time take by fake pe
  localparam int MAX_ACK_PEM = 10;
  localparam int MAX_ACK_PEA = 20;
  localparam int MAX_ACK_PEP = 4000;

// ============================================================================================== //
// Constant functions
// ============================================================================================== //

// ============================================================================================== --
// type
// ============================================================================================== --
  typedef struct packed {
    logic [PE_INST_W-1: 0]   insn;
    insn_kind_e              kind;
    logic [REGF_REG_NB-1: 0] wr_lock_mh;
    logic [REGF_REG_NB-1: 0] rd_lock_mh;
    logic                    flush;
  } info_t;

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

  always_ff @(posedge clk)
    if (error) begin
      $display("%t > FAILURE !", $time);
      $finish;
    end

// ============================================================================================== --
// input / output signals
// ============================================================================================== --
  // Insn stream interface
  logic                 insn_rdy;
  logic[PE_INST_W-1: 0] insn_pld;
  logic                 insn_vld;
  logic                 insn_ack_rdy;
  logic[PE_INST_W-1: 0] insn_ack_cnt;
  logic                 insn_ack_vld;

  // Pe_Mem interface
  logic                 pem_load_rdy;
  logic                 pem_store_rdy;
  logic                 pem_rdy;
  assign pem_rdy = pem_load_rdy && pem_store_rdy;
  logic[PE_INST_W-1: 0] pem_insn;
  logic                 pem_vld;
  logic                 pem_ack;

  // Pe_Arith interface
  logic                 pea_rdy;
  logic[PE_INST_W-1: 0] pea_insn;
  logic                 pea_vld;
  logic                 pea_ack;
  // Pe_Pbs interface
  logic                 pep_rdy;
  logic[PE_INST_W-1: 0] pep_insn;
  logic                 pep_vld;
  logic                 pep_rd_ack;
  logic                 pep_wr_ack;
  logic[LWE_K_W-1:0]    pep_ack_pld;

  // Quasi static
  logic                 use_bpip;

  logic                 pem_load_ack;
  logic                 pem_store_ack;

  assign use_bpip = USE_BPIP;

// ============================================================================================== --
// Design under test instance
// ============================================================================================== --
  instruction_scheduler #() dut (
    .clk                (clk    ),
    .s_rst_n            (s_rst_n),

    .use_bpip           (use_bpip),

    // Insn input stream and ack
    .insn_rdy(insn_rdy),
    .insn_pld(insn_pld),
    .insn_vld(insn_vld),

    .insn_ack_rdy(insn_ack_rdy),
    .insn_ack_cnt(insn_ack_cnt),
    .insn_ack_vld(insn_ack_vld),

    // PE interfaces
    .pem_rdy(pem_rdy),
    .pem_insn(pem_insn),
    .pem_vld(pem_vld),
    .pem_load_ack(pem_load_ack),
    .pem_store_ack(pem_store_ack),
    .pea_rdy(pea_rdy),
    .pea_insn(pea_insn),
    .pea_vld(pea_vld),
    .pea_ack(pea_ack),
    .pep_rdy(pep_rdy),
    .pep_insn(pep_insn),
    .pep_vld(pep_vld),
    // NB: This signal must be bound to pep_rd_ack.
    // However, the current order checker is not aware of the early rd_release
    // and thus generate false RAW violation.
    // Currently use the pep_wr_ack to circumvent the issue.
    // TODO FIXME
    .pep_rd_ack(pep_wr_ack),
    .pep_wr_ack(pep_wr_ack),
    .pep_ack_pld(pep_ack_pld),

    .isc_counter_inc(/*UNUSED*/),
    .isc_rif_info   (/*UNUSED*/)
  );

// ============================================================================================== --
// Insn stream
// ============================================================================================== --
// Axi4-stream insn endpoint
  axis_drv_if #(
  .AXIS_DATA_W(PE_INST_W)
  ) axis_insn_drv ( .clk(clk), .rst_n(s_rst_n));

  // Connect interface on testbench signals
  assign insn_pld = axis_insn_drv.tdata;
  assign axis_insn_drv.tready    = insn_rdy;
  assign insn_vld = axis_insn_drv.tvalid;

  // Use a random data generator for custom pattern on insn_vld
  random_data #(.DATA_W(32)) rand_insn_delay = new(0);

// Axi4-stream insn ack endpoint
  axis_ep_if #(
  .AXIS_DATA_W(PE_INST_W)
  ) axis_insn_ack_ep ( .clk(clk), .rst_n(s_rst_n));

  // Connect interface on testbench signals
  assign axis_insn_ack_ep.tdata = insn_ack_cnt;
  assign insn_ack_rdy = axis_insn_ack_ep.tready;
  assign axis_insn_ack_ep.tvalid = insn_ack_vld;

// ============================================================================================== --
// Fake pe
// ============================================================================================== --
// Simple component that buffer request and randomly consume and generate ack

  // Pem fake
  // Use two pe_fake for pem. In real life it's a single component with two ack channel
  pe_fake  #(
  .MAX_ACK_CYCLE(MAX_ACK_PEM)
  ) pem_load_fake
  (
    .clk(clk),
    .s_rst_n(s_rst_n),
    .pe_rdy(pem_load_rdy),
    .pe_insn(pem_insn),
    .pe_vld(pem_vld && ((pem_insn[PE_INST_W-1: PE_INST_W-6] & 6'b11_0001) == DOP_LD)),
    .pe_rd_ack(/*unused*/),
    .pe_wr_ack(pem_load_ack)
  );

  pe_fake  #(
  .MAX_ACK_CYCLE(MAX_ACK_PEM)
  ) pem_store_fake
  (
    .clk(clk),
    .s_rst_n(s_rst_n),
    .pe_rdy(pem_store_rdy),
    .pe_insn(pem_insn),
    .pe_vld(pem_vld && ((pem_insn[PE_INST_W-1: PE_INST_W-6] & 6'b11_0001) == DOP_ST)),
    .pe_rd_ack(/*unused*/),
    .pe_wr_ack(pem_store_ack)
  );

  // Pea fake
  pe_fake  #(
  .MAX_ACK_CYCLE(MAX_ACK_PEA)
  ) pea_fake
  (
    .clk(clk),
    .s_rst_n(s_rst_n),
    .pe_rdy(pea_rdy),
    .pe_insn(pea_insn),
    .pe_vld(pea_vld),
    .pe_rd_ack(/*unused*/),
    .pe_wr_ack(pea_ack)
  );

  // Pep fake
  pe_fake #(
  .MAX_CONS_CYCLE(2*BATCH_PBS_NB),
  .MAX_BATCH_ELEM(BATCH_PBS_NB),
  .MAX_ACK_CYCLE(MAX_ACK_PEP)
  ) pep_fake (
    .clk(clk),
    .s_rst_n(s_rst_n),
    .pe_rdy(pep_rdy),
    .pe_insn(pep_insn),
    .pe_vld(pep_vld),
    .pe_rd_ack(pep_rd_ack),
    .pe_wr_ack(pep_wr_ack)
  );

  // Generate random value for associated pep_pld
  initial begin
   pep_ack_pld = 'x;
   do begin
     do @(posedge clk); while(!pep_wr_ack);
     pep_ack_pld = $urandom();
   end while(1);
  end



// ============================================================================================== --
// Instruction parser and spy for dependencies analysis
// ============================================================================================== --
// Use RTL module for testbench purpose
// TODO: Bad practice, write a dedicated parser for verification purpose
logic [PE_INST_W-1: 0]   ip_insn;
insn_kind_e              ip_kind_1h;
logic [REGF_REG_NB-1: 0] ip_wr_reg_mh;
logic [REGF_REG_NB-1: 0] ip_rd_reg_mh;
logic                    ip_flush;

isc_parser_mh insn_parser_mh(
  .insn       (ip_insn),
  .kind_1h    (ip_kind_1h),
  .wr_reg_mh  (ip_wr_reg_mh),
  .rd_reg_mh  (ip_rd_reg_mh),
  .flush      (ip_flush)
);

// Axi4-stream insn endpoint
axis_ep_if #(
.AXIS_DATA_W(PE_INST_W)
) axis_insn_spy ( .clk(clk), .rst_n(s_rst_n));
// Connect interface on dut inner module signals
assign axis_insn_spy.tdata = dut.query_ack.info.insn.raw_insn;
assign axis_insn_spy.tvalid = dut.query_ack_vld && (dut.query_ack.status == SUCCESS) && (dut.query_ack.cmd == RETIRE);
assign axis_insn_spy.tlast = '0;


// ============================================================================================== --
// Utilities function to generate stimulus
// ============================================================================================== --
task automatic read_insn_stream;
  output bit[PE_INST_W-1: 0] insn_q[$];
  output int insn_cnt;
  logic [PE_INST_W-1: 0] d;
begin
    // Open file insn stream file
    read_data #(.DATA_W(PE_INST_W)) rdata_insn = new(.filename(FILE_ASM_INSN), .data_type(FILE_DATA_TYPE));
    if (!rdata_insn.open()) begin
      $display("%t > ERROR: opening file %0s failed\n", $time, FILE_ASM_INSN);
      $finish;
    end

    // Read file and flush in a queue
    insn_q.delete();
    d = rdata_insn.get_next_data();
    while (! rdata_insn.is_st_eof()) begin
      insn_q.push_back(d);
      d = rdata_insn.get_next_data();
    end
    insn_cnt = insn_q.size();

    assert ((insn_cnt+1)>= MIN_IOP_SIZE)
    else $fatal(1,"%t > ERROR: Instruction stream doesn't match minimum sized requirement. This could induce an overflow of the sync_id counter and a deadlock.", $time);
end
endtask

task automatic parse_insn_stream;
  input bit[PE_INST_W-1: 0] insn_q[$];
  output info_t info_q[$];

  info_t info;
begin
    // Extract info of every instructions
    // This will be used later one to enforce that generated order is correct
    // -> Enforce that all register dependencies are met
    info_q.delete();
    foreach(insn_q[i]) begin
      ip_insn = insn_q[i];
      @(posedge clk)
      info.insn = insn_q[i];
      info.kind = ip_kind_1h;
      info.wr_lock_mh = ip_wr_reg_mh;
      info.rd_lock_mh = ip_rd_reg_mh;
      info.flush = ip_flush;
      info_q.push_back(info);
    end

end
endtask

task automatic check_insn_stream;
  input bit[PE_INST_W-1: 0] insn_q[$];
  input bit[PE_INST_W-1: 0] retire_q[$];
  output int errors;

  int match_pos;
  bit match_found;

  info_t info_q[$];
  info_t cur_info, prd_info;
begin
  // Extract info from ref stream
  parse_insn_stream(insn_q, info_q);

  // For each insn in retire queue find matching entry in info_q
  // Check that it has not conflict with all previous insn
  // Remove matching entry from info_q
  errors = 0;
  if (retire_q.size() != insn_q.size()) begin
    $display("%t > ERROR: retired stream size doesn't match with expected one [%d, %d]", $time, retire_q.size(),insn_q.size());
    errors +=1;
  end

  foreach(retire_q[i]) begin
    match_pos = 0;
    match_found = 1'b0;

    do begin
      // $display( "try_match %x <=> %x", info_q[match_pos].insn, retire_q[i]);
      if (info_q[match_pos].insn == retire_q[i]) match_found = 1'b1;
      else match_pos += 1;
    end while (!match_found);
    // Try to replace with
    // At first glance this doesn't seems to work and always return 0
    // match_pos = info_q.find_first_index(x) with (x.insn == retire_q[i]);

    cur_info = info_q[match_pos];
    $display("%t > INFO: retire [%x]@%0d found @pos %0d", $time, retire_q[i], i, match_pos);
    for(int p = 0; p< match_pos; p++) begin
      bit error = 0;
      prd_info = info_q[p];

      if (|(cur_info.wr_lock_mh &(prd_info.wr_lock_mh | prd_info.rd_lock_mh))) begin
        error = 1;
        $display("%t > ERROR@%d: RAW violation [%x <- %x]",$time, i, cur_info.insn, prd_info.insn);
      end

      if (|(cur_info.rd_lock_mh & prd_info.wr_lock_mh)) begin
        error = 1;
        $display("%t > ERROR%d: WAR violation [%x <- %x]",$time, i, cur_info.insn, prd_info.insn);
      end

      if ((cur_info.flush != prd_info.flush) && (cur_info.kind & prd_info.kind & PBS) && USE_BPIP) begin
        error = 1;
        $display("%t > ERROR%d: FLUSH Barrier violation [%x <- %x]",$time, i, cur_info.insn, prd_info.insn);
      end

      if(error) begin
        $display("%t > check against [%x]@%0d", $time, prd_info.insn, p);
        $display("cur [WR_LOCK]  %b", cur_info.wr_lock_mh);
        $display("prd [WR_LOCK]  %b", prd_info.wr_lock_mh);
        $display("cur [RD_LOCK]  %b", cur_info.rd_lock_mh);
        $display("prd [RD_LOCK]  %b", prd_info.rd_lock_mh);
      end

      errors += error;
    end

    info_q.delete(match_pos);

  end
end
endtask

// ============================================================================================== --
// Scenario
// ============================================================================================== --
  bit [PE_INST_W-1: 0] insn_q[$];
  int insn_cnt;

  bit [PE_INST_W-1: 0] ref_q[$];
  bit [PE_INST_W-1: 0] insn_retire;
  bit [PE_INST_W-1: 0] retire_q[$];
  bit _is_last;
  bit [PE_INST_W-1: 0] _iop_retire;

  int order_errors;

  initial begin
  // Init axis
  axis_insn_drv.init();
  axis_insn_ack_ep.init();
  axis_insn_spy.init();

  // Read insn from file
  read_insn_stream(insn_q, insn_cnt);

  while (!s_rst_n) @(posedge clk);
  repeat(1000) @(posedge clk);

  fork
    begin // Populate dut insn stream
      for(int dop_iter=0; dop_iter < DOP_ITER; dop_iter++)
      begin
        foreach(insn_q[i]) begin
          axis_insn_drv.push(insn_q[i], 1'bx);
          ref_q.push_back(insn_q[i]);
          // Draw random value for stream delay
          if (!rand_insn_delay.randomize() with {rand_insn_delay.data dist {
                [0: 5] :/ ((2**8-1)-ASM_INSN_HALT),
                [MAX_ACK_PEP: 4*MAX_ACK_PEP] :/ ASM_INSN_HALT}; }) begin
            $display("%t > ERROR: randomization of rand_vld", $time);
            $finish;
          end
        repeat(rand_insn_delay.get_data) @(posedge clk);

        end
        $display("%t > INFO: All instruction pushed in DUT [%d]",$time, insn_cnt);
        // Append a sync for proper end of simulation
        axis_insn_drv.push(DOP_SYNC_WORD + dop_iter, 1'bx);
      end
    end
    fork
    begin // Store retire insn in queue
      do begin
       axis_insn_spy.pop(insn_retire, _is_last);
       retire_q.push_back(insn_retire);
       @(posedge clk);
      end while (1);
    end
    begin // Probe end condition
      for(int dop_iter=0; dop_iter < DOP_ITER; dop_iter++)
      begin
        axis_insn_ack_ep.pop(_iop_retire, _is_last);
        $display("%t > INFO: DUT generate Ack",$time);
      end
    end
    join_any
    disable fork;
  join

  // Check generated instruction order
  // 1. reload insn from file
  // 2. Check against generated retire stream
  check_insn_stream(ref_q, retire_q, order_errors);
  error = |order_errors;
  repeat(10) @(posedge clk);

  end_of_test = 1'b1;
  end
endmodule
