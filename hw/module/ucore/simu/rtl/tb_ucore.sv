// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Test ucore and associated firmware
// ----------------------------------------------------------------------------------------------
//
// Wait on command in the queue and check that the received IOps are correctly translated in correct
// sequence of DOps.
//
// Testbench body:
// Init translation memory and IOp2DOps translation lookup.
// Insert IOp in the work queue
// Wait on ack in the ack queue
// Compare generated DOps sequence with the expected one
//
// ==============================================================================================

`resetall
`timescale 1ns/10ps

module tb_ucore;

  import ucore_pkg::*;
  import param_tfhe_pkg::*;
  import axi_if_common_param_pkg::*;
  import axi_if_ucore_axi_pkg::*;
  import hpu_common_instruction_pkg::*;
  import file_handler_pkg::*;

  // =========================================================================================== --
  // Parameters
  // =========================================================================================== --
  parameter int IOP_NB = 1;
  parameter int IOP_INT_SIZE = 2;
  parameter int MSG_W = PAYLOAD_BIT / 2;
  parameter int DOP_NB = 1;

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int CLK_HALF_PERIOD = 1;
  localparam int ARST_ACTIVATION = 17;

  localparam int TEST_LEN = 2;

  localparam int EXPECTED_UCORE_VERSION_MAJOR = 2;
  localparam int EXPECTED_UCORE_VERSION_MINOR = 0;
  localparam int UCORE_VERSION_IOP            = 'h00FE0000;
  localparam int EMPTY_DST_IOP                = 'h60000000;
  localparam int EMPTY_SRC_IOP                = 'h20000000;

  localparam int SYNC_DOP_WORD='h4000ffff;

  // size of AXI4 addr bus during simulation
  localparam int AXI4_ADD_W = 24;
  localparam int REG_DATA_BYTES = AXI4_DATA_W/8;

  localparam bit[1:0] TB_DRIVE_HBM  = 2'b10;
  localparam bit[1:0] DUT_DRIVE_HBM = 2'b01;

  // TB parameters
  localparam string FILE_DATA_TYPE  = "ascii_hex";
  parameter string IOP_FILE_PREFIX  = "input/ucode/iop/iop";
  parameter string DOP_FILE_PREFIX  = "input/ucode/dop/dop";
  parameter IOP_MAX_WORD_NB = 6;

  // Index of the DOP
  parameter [DOP_NB-1:0][7:0]    DOP_LIST     = {8'h00};


// ============================================================================================== --
// functions
// ============================================================================================== --

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
  //== Axi4 Interface
  // NB: Dut connected on 0, beh driver on 1
  logic [1:0]                      axi4_select;
  // Write channel
  logic [1:0][AXI4_ID_W-1:0]       axi4_awid;
  logic [1:0][AXI4_ADD_W-1:0]      axi4_awaddr;
  logic [1:0][AXI4_LEN_W-1:0]      axi4_awlen;
  logic [1:0][AXI4_SIZE_W-1:0]     axi4_awsize;
  logic [1:0][AXI4_BURST_W-1:0]    axi4_awburst;
  logic [1:0]                      axi4_awvalid;
  logic [1:0]                      axi4_awready;
  logic [1:0][AXI4_DATA_W-1:0]     axi4_wdata;
  logic [1:0][(AXI4_DATA_W/8)-1:0] axi4_wstrb;
  logic [1:0]                      axi4_wlast;
  logic [1:0]                      axi4_wvalid;
  logic [1:0]                      axi4_wready;
  logic [1:0][AXI4_ID_W-1:0]       axi4_bid;
  logic [1:0][AXI4_RESP_W-1:0]     axi4_bresp;
  logic [1:0]                      axi4_bvalid;
  logic [1:0]                      axi4_bready;
  // Read channel
  logic [1:0][AXI4_ID_W-1:0]       axi4_arid;
  logic [1:0][AXI4_ADD_W-1:0]      axi4_araddr;
  logic [1:0][AXI4_LEN_W-1:0]      axi4_arlen;
  logic [1:0][AXI4_SIZE_W-1:0]     axi4_arsize;
  logic [1:0][AXI4_BURST_W-1:0]    axi4_arburst;
  logic [1:0]                      axi4_arvalid;
  logic [1:0]                      axi4_arready;
  logic [1:0][AXI4_ID_W-1:0]       axi4_rid;
  logic [1:0][AXI4_DATA_W-1:0]     axi4_rdata;
  logic [1:0][AXI4_RESP_W-1:0]     axi4_rresp;
  logic [1:0]                      axi4_rlast;
  logic [1:0]                      axi4_rvalid;
  logic [1:0]                      axi4_rready;

  //== Work_queue
  // Interface with a eR.Wa register
  logic [PE_INST_W-1:0]       workq;
  logic [PE_INST_W-1:0]       workq_upd;
  logic                       workq_wr_en = 1'b0;
  logic [PE_INST_W-1:0]       workq_wdata;

  //== Ack_queue
  // Interface with a eRn__ register
  logic [PE_INST_W-1:0]       ackq_upd;
  logic                       ackq_rd_en = 1'b0;

  // Dop stream: issue sequence of DOps
  logic [(PE_INST_W-1):0]     dop_data;
  logic                       dop_rdy;
  logic                       dop_vld;

  // Ack stream: received acknowledgment of DOp sync.
  logic [(PE_INST_W-1):0]     ack_data;
  logic                       ack_rdy;
  logic                       ack_vld;

  // Ucore irq line
  logic                       irq;



  // ============================================================================================== --
  // Design under test instance
  // ============================================================================================== --
  ucore #(.AXI4_ADD_W(AXI4_ADD_W)
  ) ucore_dut (
  // System interface ---------------------------------------------------------
   .clk    (clk),   // clock
   .s_rst_n(s_rst_n), // synchronous reset

  //== Axi4 Interface
  // Write channel
   .m_axi_awid   (axi4_awid   [0]),
   .m_axi_awaddr (axi4_awaddr [0]),
   .m_axi_awlen  (axi4_awlen  [0]),
   .m_axi_awsize (axi4_awsize [0]),
   .m_axi_awburst(axi4_awburst[0]),
   .m_axi_awvalid(axi4_awvalid[0]),
   .m_axi_awready(axi4_awready[0]),
   .m_axi_wdata  (axi4_wdata  [0]),
   .m_axi_wstrb  (axi4_wstrb  [0]),
   .m_axi_wlast  (axi4_wlast  [0]),
   .m_axi_wvalid (axi4_wvalid [0]),
   .m_axi_wready (axi4_wready [0]),
   .m_axi_bid    (axi4_bid    [0]),
   .m_axi_bresp  (axi4_bresp  [0]),
   .m_axi_bvalid (axi4_bvalid [0]),
   .m_axi_bready (axi4_bready [0]),
  // Read channel
   .m_axi_arid   (axi4_arid   [0]),
   .m_axi_araddr (axi4_araddr [0]),
   .m_axi_arlen  (axi4_arlen  [0]),
   .m_axi_arsize (axi4_arsize [0]),
   .m_axi_arburst(axi4_arburst[0]),
   .m_axi_arvalid(axi4_arvalid[0]),
   .m_axi_arready(axi4_arready[0]),
   .m_axi_rid    (axi4_rid    [0]),
   .m_axi_rdata  (axi4_rdata  [0]),
   .m_axi_rresp  (axi4_rresp  [0]),
   .m_axi_rlast  (axi4_rlast  [0]),
   .m_axi_rvalid (axi4_rvalid [0]),
   .m_axi_rready (axi4_rready [0]),

  //== Work_queue
  // Interface with a eR.Wa register
   .r_workq      (workq      ),
   .r_workq_upd  (workq_upd  ),
   .r_workq_wr_en(workq_wr_en),
   .r_workq_wdata(workq_wdata),

  //== Ack_queue
  // Interface with a eRn__ register
   .r_ackq_upd  (ackq_upd  ),
   .r_ackq_rd_en(ackq_rd_en),

  // Dop stream: issue sequence of DOps
   .dop_data(dop_data),
   .dop_rdy (dop_rdy),
   .dop_vld (dop_vld),

  // Ack stream: received acknowledgment of DOp sync.
   .ack_data(ack_data),
   .ack_rdy (ack_rdy),
   .ack_vld (ack_vld),

  // Ucore irq line
   .irq(irq)
);


  // ============================================================================================== --
  // HBM memory model for IOps/DOps translation table
  // ============================================================================================== --
  axi4_mem_with_select #(
  .SLAVE_IF    (2),
  .DATA_WIDTH  (AXI4_DATA_W),
  .ADDR_WIDTH  (AXI4_ADD_W),
  .ID_WIDTH    (AXI4_ID_W),
  // TODO: Wr/Rd random introduce deadlock in simulation
  // FIXME: This MUST be investigated further
  .USE_WR_RANDOM(0),
  .USE_RD_RANDOM(0)
) axi4_mem (
    .clk          (clk),
    .rst          (!s_rst_n),

    .s_axi4_select_1h(axi4_select),
    .s_axi4_awid     (axi4_awid),
    .s_axi4_awaddr   (axi4_awaddr),
    .s_axi4_awlen    (axi4_awlen),
    .s_axi4_awsize   (axi4_awsize),
    .s_axi4_awburst  (axi4_awburst),
    .s_axi4_awlock   ('0),
    .s_axi4_awcache  ('0),
    .s_axi4_awprot   ('0),
    .s_axi4_awvalid  (axi4_awvalid),
    .s_axi4_awready  (axi4_awready),
    .s_axi4_wdata    (axi4_wdata),
    .s_axi4_wstrb    (axi4_wstrb),
    .s_axi4_wlast    (axi4_wlast),
    .s_axi4_wvalid   (axi4_wvalid),
    .s_axi4_wready   (axi4_wready),
    .s_axi4_bid      (axi4_bid),
    .s_axi4_bresp    (axi4_bresp),
    .s_axi4_bvalid   (axi4_bvalid),
    .s_axi4_bready   (axi4_bready),

    .s_axi4_arid     (axi4_arid),
    .s_axi4_araddr   (axi4_araddr),
    .s_axi4_arlen    (axi4_arlen),
    .s_axi4_arsize   (axi4_arsize),
    .s_axi4_arburst  (axi4_arburst),
    .s_axi4_arlock   ('0),
    .s_axi4_arcache  ('0),
    .s_axi4_arprot   ('0),
    .s_axi4_arvalid  (axi4_arvalid),
    .s_axi4_arready  (axi4_arready),
    .s_axi4_rid      (axi4_rid),
    .s_axi4_rdata    (axi4_rdata),
    .s_axi4_rresp    (axi4_rresp),
    .s_axi4_rlast    (axi4_rlast),
    .s_axi4_rvalid   (axi4_rvalid),
    .s_axi4_rready   (axi4_rready)
);


  // Axi4 driver
  maxi4_if #(
  .AXI4_DATA_W(AXI4_DATA_W),
  .AXI4_ADD_W(AXI4_ADD_W)
  ) maxi4_drv_if ( .clk(clk), .rst_n(s_rst_n));

    assign axi4_awid   [1] = maxi4_drv_if.awid;
    assign axi4_awaddr [1] = maxi4_drv_if.awaddr;
    assign axi4_awlen  [1] = maxi4_drv_if.awlen;
    assign axi4_awsize [1] = maxi4_drv_if.awsize;
    assign axi4_awburst[1] = maxi4_drv_if.awburst;
    assign axi4_awvalid[1] = maxi4_drv_if.awvalid;
    assign axi4_wdata  [1] = maxi4_drv_if.wdata;
    assign axi4_wstrb  [1] = maxi4_drv_if.wstrb;
    assign axi4_wlast  [1] = maxi4_drv_if.wlast;
    assign axi4_wvalid [1] = maxi4_drv_if.wvalid;
    assign axi4_bready [1] = maxi4_drv_if.bready;
    assign maxi4_drv_if.awready = axi4_awready[1];
    assign maxi4_drv_if.wready  = axi4_wready[1];
    assign maxi4_drv_if.bid     = axi4_bid[1];
    assign maxi4_drv_if.bresp   = axi4_bresp[1];
    assign maxi4_drv_if.bvalid  = axi4_bvalid[1];

    assign axi4_arid   [1] = maxi4_drv_if.arid;
    assign axi4_araddr [1] = maxi4_drv_if.araddr;
    assign axi4_arlen  [1] = maxi4_drv_if.arlen;
    assign axi4_arsize [1] = maxi4_drv_if.arsize;
    assign axi4_arburst[1] = maxi4_drv_if.arburst;
    assign axi4_arvalid[1] = maxi4_drv_if.arvalid;
    assign axi4_rready [1] = maxi4_drv_if.rready;
    assign maxi4_drv_if.arready = axi4_arready[1];
    assign maxi4_drv_if.rid = axi4_rid[1];
    assign maxi4_drv_if.rdata = axi4_rdata[1];
    assign maxi4_drv_if.rresp = axi4_rresp[1];
    assign maxi4_drv_if.rlast = axi4_rlast[1];
    assign maxi4_drv_if.rvalid = axi4_rvalid[1];

  // Axi4-stream DOp endpoint
  axis_ep_if #(
  .AXIS_DATA_W(PE_INST_W)
  ) axis_dop_ep ( .clk(clk), .rst_n(s_rst_n));

  // Connect interface on testbench signals
  assign axis_dop_ep.tdata  = dop_data;
  assign axis_dop_ep.tlast  = '0;
  assign dop_rdy            = axis_dop_ep.tready;
  assign axis_dop_ep.tvalid = dop_vld;

  // Axi4-stream Ack driver
  axis_drv_if #(
  .AXIS_DATA_W(PE_INST_W)
  ) axis_ack_drv ( .clk(clk), .rst_n(s_rst_n));

  // Connect interface on testbench signals
  assign ack_data            = axis_ack_drv.tdata;
  assign ack_vld             = axis_ack_drv.tvalid;
  assign axis_ack_drv.tready = ack_rdy;

  // ============================================================================================== --
  // Utilities function to generate stimulus
  // ============================================================================================== --
// ---------------------------------------------------------------------------------------------- --
// read_op
// ---------------------------------------------------------------------------------------------- --
// Fill queue with DOp/IOp read from a file
task automatic read_op;
  input string op_filename;
  inout logic [AXI4_DATA_W-1:0] op_q[$];
  logic [AXI4_DATA_W-1:0] op;
begin
  // Open file associated with current dop
  automatic read_data #(.DATA_W(AXI4_DATA_W)) op_rd = new(.filename(op_filename), .data_type(FILE_DATA_TYPE));
  if (!op_rd.open()) begin
    $display("%t > ERROR: opening file %0s failed\n", $time, op_filename);
    $finish;
  end

  // Read file and flush in a queue
  op = op_rd.get_next_data();
  while (! op_rd.is_st_eof()) begin
    op_q.push_back(op);
    op = op_rd.get_next_data();
  end
end
endtask


// ---------------------------------------------------------------------------------------------- --
// init_iop2dop_table
// ---------------------------------------------------------------------------------------------- --
task automatic init_iop2dop_table;
  inout logic [PE_INST_W-1:0]   dop_q[DOP_NB-1:0][$];
  logic [AXI4_ADD_W-1:0]  lut_addr;
  logic [AXI4_ADD_W-1:0]  tr_addr;
  logic [AXI4_DATA_W-1:0] addr_q[$];
  logic [AXI4_DATA_W-1:0] size_q[$]; // Workaround
  logic [IOP_W-1:0]             iop_id;
  integer                       size;
begin
  // TB take control of the hbm
  axi4_select = TB_DRIVE_HBM;

  // Ucode handle multi-width, thus the lut_addr is now linked to integer_w
  // In simulation we alwaays simulate only one integer-width at a time, thus the tr_addr could be right
  // after the lut_addr range
  lut_addr = (REG_DATA_BYTES*(1 << IOP_W)) * ((IOP_INT_SIZE/MSG_W)-1);
  tr_addr = lut_addr + REG_DATA_BYTES*(1 << IOP_W);

  // Upload it in memory and update entry in lookup
  // Filter msb in table lookup -> used to addr in ram with reduced range
  // Iop currently have a sparse encoding on 8b -> Generate a zeroed array and update used entries
  addr_q.delete();
  // Set default to 0
  for (int i=0; i< 2**IOP_W; i++) begin
    addr_q[$+1] = 0;
  end

  for (int i=0; i<DOP_NB; i=i+1) begin
    iop_id         = DOP_LIST[i];
    addr_q[iop_id] = tr_addr;
    size           = dop_q[i].size();
    $display("%t > INFO: Write IOp 0x%02x tr_table @0x%0x of %0d elements", $time, iop_id,addr_q[iop_id],size);

    // Write the size.
    // Since maxi4_drv_if.write_trans only accepts queue, put the size in a queue of a single element.
    size_q.delete();
    size_q.push_back(size);
    maxi4_drv_if.write_trans(tr_addr, size_q);
    tr_addr += REG_DATA_BYTES;
    // Write DOP associated to the iop_id
    maxi4_drv_if.write_trans(tr_addr, dop_q[i]);
    tr_addr += REG_DATA_BYTES*size;
  end

  // Write cross-reference table iop_id <-> dop_code address
  maxi4_drv_if.write_trans(lut_addr, addr_q);

  // TB release control of the hbm
  axi4_select = DUT_DRIVE_HBM;
end
endtask

// ---------------------------------------------------------------------------------------------- --
// Write a value in WorkQ
// ---------------------------------------------------------------------------------------------- --
  task automatic wr_workq;
    input int value;
  begin
    workq_wdata = value;
    workq_wr_en = 1'b1;
    @(posedge clk);
    workq_wr_en = 1'b0;
  end
  endtask

  task automatic push_work;
    inout logic [AXI4_DATA_W-1:0] iopq[$];
    inout logic [AXI4_DATA_W-1:0] workq[$];
    logic [AXI4_DATA_W-1:0]       iop; // To identify
    logic [AXI4_DATA_W-1:0]       word;
  begin
    iop = iopq[0];
    while (iopq.size() > 0) begin
      word = iopq.pop_front();
      wr_workq(word);
    end
    $display("%t > INFO: Insert IOp with header %x", $time, iop);
    workq.push_back(iop);
  end
  endtask

// ---------------------------------------------------------------------------------------------- --
// Read a value from AckQ
// ---------------------------------------------------------------------------------------------- --
  task automatic rd_ackq;
    output int value;
  begin
    @(posedge clk) begin
      ackq_rd_en = 1'b1;
    end
    @(posedge clk)
      value      = ackq_upd;
      ackq_rd_en = 1'b0;
  end
  endtask

  task automatic pop_ack;
    inout logic [AXI4_DATA_W-1:0] workq[$];
    output bit [PE_INST_W-1:0] opcode_ack;
    logic [7:0] ucore_version_major;
    logic [7:0] ucore_version_minor;
  begin
    do begin
      repeat(500) @(posedge clk);
      rd_ackq(opcode_ack);
      // $display("%t > INFO: pop_ack opcode_ack=0x%0x", $time, opcode_ack);
    end while (opcode_ack == ACKQ_RD_ERR);

    // Check that received value match or is a version response
    if (workq[0] == UCORE_VERSION_IOP) begin
      ucore_version_major = opcode_ack[15:8];
      ucore_version_minor = opcode_ack[7:0];
      $display("%t > INFO: ucore version %02d.%02d", $time, ucore_version_major, ucore_version_minor);
      assert (ucore_version_major == EXPECTED_UCORE_VERSION_MAJOR
           && ucore_version_minor == EXPECTED_UCORE_VERSION_MINOR)
        else begin
          #5 $fatal(1, "%t > ERROR: version of ucore %02d.%02d is different from expected one %02d.%02d", $time,
              ucore_version_major, ucore_version_minor,
              EXPECTED_UCORE_VERSION_MAJOR, EXPECTED_UCORE_VERSION_MINOR);
        end
    end else begin
      assert(opcode_ack == workq[0])
        else begin
          #5 $fatal(1, "%t > ERROR: opcode ack mismatch [exp %x != %x dut]", $time, workq[0], opcode_ack);
        end
    end

    // Remove opcode from workq
    workq = workq[1:$];
  end
  endtask

  task automatic dop_loopback;
    output logic [PE_INST_W-1: 0] dop_q[$];
    logic [PE_INST_W-1: 0]       dop;
    bit is_last;
  begin
    dop_q = {};
    do begin
      axis_dop_ep.pop(dop, is_last);
      // $display("%t > INFO: DOp poped %x doq_q size %03d", $time, dop, dop_q.size());
      dop_q[$+1] = dop;
    end
    while (dop != SYNC_DOP_WORD);

    // Remove sync token and push 1 (number of SYNC received) back in ack stream
    axis_ack_drv.push(1, 1'b0);
    dop_q.pop_back();
  end
  endtask


  function bit dop_check_seq (
    input logic[PE_INST_W-1 :0] ref_q[$],
    input logic[PE_INST_W-1 :0] dop_q[$]
  );
  int mismatch;
  begin
    mismatch = 0;
    // Check that DOp stream length match
    if (ref_q.size() != dop_q.size()) begin
      $display("%t > ERROR: DOp stream length mismatch [exp: %x, dut: %x]\n", $time, ref_q.size(), dop_q.size());
      return 1'b0;
    end

    // Check that stream content match
    for(int i=0; i< ref_q.size(); i++) begin
      if (ref_q[i] != dop_q[i]) begin
        mismatch += 1;
        $display("%t > ERROR: DOp stream mismatch @%d [exp: %x, dut: %x]\n", $time, i, ref_q[i], dop_q[i]);
      end
    end

    if (mismatch != 0) begin
      return 1'b0;
    end else begin
      return 1'b1;
    end
  end
  endfunction

  // ============================================================================================== --
  // Scenario
  // ============================================================================================== --
  initial begin
    int iop_ack; 
    int iop_id;

    logic [AXI4_DATA_W-1:0]  work_q[$];
    logic [AXI4_DATA_W-1:0]  iop_q[IOP_NB-1:0][$];
    logic [AXI4_DATA_W-1:0]  iop_temp_q[$];
    logic [AXI4_DATA_W-1:0]  dop_ld_q[DOP_NB-1:0][$];
    logic [AXI4_DATA_W-1:0]  dop_patched_q[DOP_NB-1:0][$];
    logic [AXI4_DATA_W-1:0]  dop_q[$];

    maxi4_drv_if.init();
    axis_ack_drv.init();
    axis_dop_ep.init();

    while (!s_rst_n) @(posedge clk);
    repeat(10) @(posedge clk);

    //===============================
    // Load phase
    //===============================
    for (int i=0; i<IOP_NB; i=i+1) begin
      iop_q[i].delete();
    end
    for (int i=0; i<DOP_NB; i=i+1) begin
      dop_patched_q[i].delete();
      dop_ld_q[i].delete();
    end

    // 1st adds IOp 0x0 to read UCORE Version
    // works only with ublaze in simulation
    iop_temp_q.push_back(UCORE_VERSION_IOP);
    iop_temp_q.push_back(EMPTY_DST_IOP);
    iop_temp_q.push_back(EMPTY_SRC_IOP);
    push_work(iop_temp_q,work_q);
    $display("%t > INFO: Pushed Iop to read ucore version", $time);
    repeat(100) @(posedge clk);
    pop_ack(work_q, iop_ack);

    // Read Iop in a queue
    for (int i=0; i<IOP_NB; i=i+1) begin
      string fn;
      fn =  $sformatf("%s_%0d.hex", IOP_FILE_PREFIX, i);
      read_op(fn, iop_q[i]);
    end

    // Load Dops in queues
    for (int i=0; i<DOP_NB; i=i+1) begin
      string fn;
      fn =  $sformatf("%s_%02x.hex", DOP_FILE_PREFIX, DOP_LIST[i]);
      read_op(fn, dop_ld_q[i]);
    end
    // Load patched Dops in queues for check
    for (int i=0; i<DOP_NB; i=i+1) begin
      string fn;
      fn =  $sformatf("%s_patched_%02x.hex", DOP_FILE_PREFIX, DOP_LIST[i]);
      read_op(fn, dop_patched_q[i]);
      // Patch stream contain Sync -> remove it
      dop_patched_q[i].pop_back();
    end

    // // Debug -> Display queue content -----------------------------------------
    // for (int i=0; i<IOP_NB; i=i+1) begin
    //   $display("%t > Iop[%02d] queue content", $time, i);
    //   for (int q=0; q<iop_q[i].size(); q=q+1) begin
    //     $display("@[%02d] -> 0x%x", q, iop_q[i][q]);
    //   end
    // end

    // for (int i=0; i<DOP_NB; i=i+1) begin
    //   $display("%t > dop_ld[%02d] queue content", $time, i);
    //   for (int q=0; q<dop_ld_q[i].size(); q=q+1) begin
    //     $display("@[%02d] -> 0x%x", q, dop_ld_q[i][q]);
    //   end
    // end

    // for (int i=0; i<DOP_NB; i=i+1) begin
    //   $display("%t > dop_patched[%02d] queue content", $time, i);
    //   for (int q=0; q<dop_patched_q[i].size(); q=q+1) begin
    //     $display("@[%02d] -> 0x%x", q, dop_patched_q[i][q]);
    //   end
    // end
    // // ------------------------------------------------------------------------

    begin
      // Preload translation table
      $display("%t > INFO: Load IOP to DOP tables...", $time);
      init_iop2dop_table(dop_ld_q);
      $display("%t > INFO: Load IOP to DOP tables...Done", $time);
    end
    repeat(10) @(posedge clk); // end preload mode. Avoid access conflict

    //===============================
    // Run & check phase
    //===============================
    for (int i=0; i<IOP_NB; i=i+1) begin
      push_work(iop_q[i], work_q); // Push 1 IOP at a time.

      fork
        dop_loopback(dop_q);
        pop_ack(work_q, iop_ack);
      join
      $display("%t > INFO: Received ack for Iop %x", $time, iop_ack);

      // Check that received stream match with expected one
      assert(dop_check_seq(dop_patched_q[i], dop_q))
      else begin
        #5 $fatal(1, "%t > ERROR: Iop %x expansion failed", $time, iop_ack);
      end
    end

   end_of_test = 1'b1;
  end
endmodule
