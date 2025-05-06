// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the verification of tb_pem_load.
// ==============================================================================================

module tb_pem_load;
`timescale 1ns/10ps

  import param_tfhe_pkg::*;
  import regf_common_param_pkg::*;
  import hpu_common_instruction_pkg::*;
  import axi_if_common_param_pkg::*;
  import axi_if_ct_axi_pkg::*;
  import top_common_param_pkg::*;
  import pem_common_param_pkg::*;
// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int CLK_HALF_PERIOD = 1;
  localparam int ARST_ACTIVATION = 17;

  localparam int RAND_RANGE = 2**12;

  localparam int START_ADD_RANGE_W = 4;
  localparam int START_ADD_RANGE = 2**START_ADD_RANGE_W;
  localparam int AXI4_ADD_W      = 24; // to ease simulation duration
  localparam int AXI4_ADD_ALIGN  = AXI4_DATA_BYTES_W;

  localparam int INST_FIFO_DEPTH = 4;

  parameter  int PROC_CT_NB      = 32;
  parameter  int SAMPLE_NB       = 400;
  localparam int CT_PAGE_NB      = CT_MEM_BYTES / PAGE_BYTES;

  parameter  int PEA_PERIOD   = REGF_COEF_NB;
  parameter  int PEM_PERIOD   = 4;
  parameter  int PEP_PERIOD   = 1;
  localparam int URAM_LATENCY = 1+2;

  parameter int MEM_WR_CMD_BUF_DEPTH = 1; // Should be >= 1
  parameter int MEM_RD_CMD_BUF_DEPTH = 4; // Should be >= 1
  // Data latency
  parameter int MEM_WR_DATA_LATENCY = 1; // Should be >= 1
  parameter int MEM_RD_DATA_LATENCY = 53; // Should be >= 1
  // Set random on ready valid, on write path
  parameter bit MEM_USE_WR_RANDOM = 0; // Check path, no need random
  // Set random on ready valid, on read path
  parameter bit MEM_USE_RD_RANDOM = 1;

  localparam int PEM_PC_MAX = 4;

// ============================================================================================== --
// type
// ============================================================================================== --
  typedef struct packed {
    logic [15:0]  cid;
    logic [15:0]  idx;
  } data_t;

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
  bit error_data;
  bit error_req;
  bit error_ack;

  assign error = error_data | error_req | error_ack;

  always_ff @(posedge clk)
    if (error) begin
      $display("%t > FAILURE !", $time);
      $finish;
    end

// ============================================================================================== --
// input / output signals
// ============================================================================================== --
 // Configuration
  logic [PEM_PC_MAX-1:0][axi_if_ct_axi_pkg::AXI4_ADD_W-1:0] ct_mem_addr;

  // Command
  logic [PEM_CMD_W-1:0]                   cmd;
  logic                                   cmd_vld;
  logic                                   cmd_rdy;

  logic                                   cmd_ack;

  // pem <-> regfile
  // write
  logic                                   pem_regf_wr_req_vld;
  logic                                   pem_regf_wr_req_rdy;
  logic [REGF_WR_REQ_W-1:0]               pem_regf_wr_req;

  logic [REGF_COEF_NB-1:0]                pem_regf_wr_data_vld;
  logic [REGF_COEF_NB-1:0]                pem_regf_wr_data_rdy;
  logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0]   pem_regf_wr_data;

  logic                                   regf_pem_wr_ack;

  // AXI4 interface
  // Read channel
  logic [PEM_PC_MAX-1:0][AXI4_ID_W-1:0]       m_axi4_arid;
  logic [PEM_PC_MAX-1:0][axi_if_ct_axi_pkg::AXI4_ADD_W-1:0]      m_axi4_araddr;
  logic [PEM_PC_MAX-1:0][7:0]                 m_axi4_arlen;
  logic [PEM_PC_MAX-1:0][2:0]                 m_axi4_arsize;
  logic [PEM_PC_MAX-1:0][1:0]                 m_axi4_arburst;
  logic [PEM_PC_MAX-1:0]                      m_axi4_arvalid;
  logic [PEM_PC_MAX-1:0]                      m_axi4_arready;
  logic [PEM_PC_MAX-1:0][AXI4_ID_W-1:0]       m_axi4_rid;
  logic [PEM_PC_MAX-1:0][AXI4_DATA_W-1:0]     m_axi4_rdata;
  logic [PEM_PC_MAX-1:0][1:0]                 m_axi4_rresp;
  logic [PEM_PC_MAX-1:0]                      m_axi4_rlast;
  logic [PEM_PC_MAX-1:0]                      m_axi4_rvalid;
  logic [PEM_PC_MAX-1:0]                      m_axi4_rready;

// ============================================================================================== --
// Design under test instance
// ============================================================================================== --
  pem_load #(
    .INST_FIFO_DEPTH(INST_FIFO_DEPTH)
  ) dut (
    .clk                  (clk    ),
    .s_rst_n              (s_rst_n),

    .ct_mem_addr          (ct_mem_addr),

    .cmd                  (cmd),
    .cmd_vld              (cmd_vld),
    .cmd_rdy              (cmd_rdy),

    .cmd_ack              (cmd_ack),

    .pem_regf_wr_req_vld  (pem_regf_wr_req_vld),
    .pem_regf_wr_req_rdy  (pem_regf_wr_req_rdy),
    .pem_regf_wr_req      (pem_regf_wr_req),

    .pem_regf_wr_data_vld (pem_regf_wr_data_vld),
    .pem_regf_wr_data_rdy (pem_regf_wr_data_rdy),
    .pem_regf_wr_data     (pem_regf_wr_data),

    .regf_pem_wr_ack      (regf_pem_wr_ack),

    .m_axi4_arid           (m_axi4_arid[PEM_PC-1:0]),
    .m_axi4_araddr         (m_axi4_araddr[PEM_PC-1:0]),
    .m_axi4_arlen          (m_axi4_arlen[PEM_PC-1:0]),
    .m_axi4_arsize         (m_axi4_arsize[PEM_PC-1:0]),
    .m_axi4_arburst        (m_axi4_arburst[PEM_PC-1:0]),
    .m_axi4_arvalid        (m_axi4_arvalid[PEM_PC-1:0]),
    .m_axi4_arready        (m_axi4_arready[PEM_PC-1:0]),
    .m_axi4_rid            (m_axi4_rid[PEM_PC-1:0]),
    .m_axi4_rdata          (m_axi4_rdata[PEM_PC-1:0]),
    .m_axi4_rresp          (m_axi4_rresp[PEM_PC-1:0]),
    .m_axi4_rlast          (m_axi4_rlast[PEM_PC-1:0]),
    .m_axi4_rvalid         (m_axi4_rvalid[PEM_PC-1:0]),
    .m_axi4_rready         (m_axi4_rready[PEM_PC-1:0])

  );

// ============================================================================================== --
// Memory
// ============================================================================================== --
  generate
    for (genvar gen_p=0; gen_p<PEM_PC_MAX; gen_p=gen_p+1) begin : gen_mem_loop
      logic [AXI4_ID_W-1:0]       axi4_wr_awid;
      logic [AXI4_ADD_W-1:0]      axi4_wr_awaddr;
      logic [7:0]                 axi4_wr_awlen;
      logic [2:0]                 axi4_wr_awsize;
      logic [1:0]                 axi4_wr_awburst;
      logic                       axi4_wr_awvalid;
      logic                       axi4_wr_awready;
      logic [AXI4_DATA_W-1:0]     axi4_wr_wdata;
      logic [(AXI4_DATA_W/8)-1:0] axi4_wr_wstrb;
      logic                       axi4_wr_wlast;
      logic                       axi4_wr_wvalid;
      logic                       axi4_wr_wready;
      logic [AXI4_ID_W-1:0]       axi4_wr_bid;
      logic [1:0]                 axi4_wr_bresp;
      logic                       axi4_wr_bvalid;
      logic                       axi4_wr_bready;

      logic [AXI4_ID_W-1:0]       axi4_rd_arid;
      logic [AXI4_ADD_W-1:0]      axi4_rd_araddr;
      logic [7:0]                 axi4_rd_arlen;
      logic [2:0]                 axi4_rd_arsize;
      logic [1:0]                 axi4_rd_arburst;
      logic                       axi4_rd_arvalid;
      logic                       axi4_rd_arready;

      axi4_mem #(
        .DATA_WIDTH(AXI4_DATA_W),
        .ADDR_WIDTH(AXI4_ADD_W),
        .ID_WIDTH  (AXI4_ID_W),
        .WR_CMD_BUF_DEPTH (MEM_WR_CMD_BUF_DEPTH),
        .RD_CMD_BUF_DEPTH (MEM_RD_CMD_BUF_DEPTH),
        .WR_DATA_LATENCY (MEM_WR_DATA_LATENCY),
        .RD_DATA_LATENCY (MEM_RD_DATA_LATENCY + gen_p * 50),
        .USE_WR_RANDOM (MEM_USE_WR_RANDOM),
        .USE_RD_RANDOM (MEM_USE_RD_RANDOM)
      ) axi4_mem_ct (
        .clk          (clk),
        .rst          (!s_rst_n),

        .s_axi4_awid   (axi4_wr_awid   ),
        .s_axi4_awaddr (axi4_wr_awaddr ),
        .s_axi4_awlen  (axi4_wr_awlen  ),
        .s_axi4_awsize (axi4_wr_awsize ),
        .s_axi4_awburst(axi4_wr_awburst),
        .s_axi4_awlock ('0), // disable
        .s_axi4_awcache('0), // disable
        .s_axi4_awprot ('0), // disable
        .s_axi4_awvalid(axi4_wr_awvalid),
        .s_axi4_awready(axi4_wr_awready),
        .s_axi4_wdata  (axi4_wr_wdata  ),
        .s_axi4_wstrb  (axi4_wr_wstrb  ),
        .s_axi4_wlast  (axi4_wr_wlast  ),
        .s_axi4_wvalid (axi4_wr_wvalid ),
        .s_axi4_wready (axi4_wr_wready ),
        .s_axi4_bid    (axi4_wr_bid    ),
        .s_axi4_bresp  (axi4_wr_bresp  ),
        .s_axi4_bvalid (axi4_wr_bvalid ),
        .s_axi4_bready (axi4_wr_bready ),
        .s_axi4_arid   (m_axi4_arid[gen_p]   ),
        .s_axi4_araddr (m_axi4_araddr[gen_p][AXI4_ADD_W-1:0]),
        .s_axi4_arlen  (m_axi4_arlen[gen_p]  ),
        .s_axi4_arsize (m_axi4_arsize[gen_p] ),
        .s_axi4_arburst(m_axi4_arburst[gen_p]),
        .s_axi4_arlock ('0), // disable
        .s_axi4_arcache('0), // disable
        .s_axi4_arprot ('0), // disable
        .s_axi4_arvalid(m_axi4_arvalid[gen_p]),
        .s_axi4_arready(m_axi4_arready[gen_p]),
        .s_axi4_rid    (m_axi4_rid[gen_p]    ),
        .s_axi4_rdata  (m_axi4_rdata[gen_p]  ),
        .s_axi4_rresp  (m_axi4_rresp[gen_p]  ),
        .s_axi4_rlast  (m_axi4_rlast[gen_p]  ),
        .s_axi4_rvalid (m_axi4_rvalid[gen_p] ),
        .s_axi4_rready (m_axi4_rready[gen_p] )
      );

      // AXI4 ct driver
      maxi4_if #(
        .AXI4_DATA_W(AXI4_DATA_W),
        .AXI4_ADD_W (AXI4_ADD_W),
        .AXI4_ID_W  (AXI4_ID_W)
      ) maxi4_if (
        .clk(clk),
        .rst_n(s_rst_n)
      );

      // Connect interface on testbench signals
      // Write channel
      assign axi4_wr_awid        = maxi4_if.awid   ;
      assign axi4_wr_awaddr      = maxi4_if.awaddr ;
      assign axi4_wr_awlen       = maxi4_if.awlen  ;
      assign axi4_wr_awsize      = maxi4_if.awsize ;
      assign axi4_wr_awburst     = maxi4_if.awburst;
      assign axi4_wr_awvalid     = maxi4_if.awvalid;
      assign axi4_wr_wdata       = maxi4_if.wdata  ;
      assign axi4_wr_wstrb       = maxi4_if.wstrb  ;
      assign axi4_wr_wlast       = maxi4_if.wlast  ;
      assign axi4_wr_wvalid      = maxi4_if.wvalid ;
      assign axi4_wr_bready      = maxi4_if.bready ;

      assign maxi4_if.awready    = axi4_wr_awready;
      assign maxi4_if.wready     = axi4_wr_wready;
      assign maxi4_if.bid        = axi4_wr_bid;
      assign maxi4_if.bresp      = axi4_wr_bresp;
      assign maxi4_if.bvalid     = axi4_wr_bvalid;

      // Read channel
      assign maxi4_if.arready    = 1'b0;
      assign maxi4_if.rid        = '0;
      assign maxi4_if.rdata      = 'x  ;
      assign maxi4_if.rresp      = '0 ;
      assign maxi4_if.rlast      = '0;
      assign maxi4_if.rvalid     = 1'b0;
    end
  endgenerate

// ============================================================================================== --
// Scenario
// ============================================================================================== --
// Page aligned addresses
  initial begin
    ct_mem_addr = '0;
    for (int j=0; j<PEM_PC_MAX; j=j+1) begin
      ct_mem_addr[j][AXI4_ADD_ALIGN+:START_ADD_RANGE_W] = $urandom_range(0,START_ADD_RANGE-1);
      $display("> INFO: ct_mem_addr[PC%0d]=0x%08x",j,ct_mem_addr[j]);
    end
  end
//---------------------------------
// FSM
//---------------------------------
  typedef enum {ST_IDLE,
                ST_FILL_MEM,
                ST_PROCESS,
                ST_DONE} state_e;

  state_e state;
  state_e next_state;
  logic st_idle;
  logic st_fill_mem;
  logic st_process;
  logic st_done;

  logic start;
  logic fill_mem_done;
  logic proc_done;
  logic test_done;

  always_comb
    case (state)
      ST_IDLE:
        next_state = start ? ST_FILL_MEM : state;
      ST_FILL_MEM:
        next_state = fill_mem_done ? ST_PROCESS : state;
      ST_PROCESS:
        next_state = proc_done ? ST_DONE : state;
      ST_DONE:
        next_state = state;
    endcase

  always_ff @(posedge clk)
    if (!s_rst_n) state <= ST_IDLE;
    else          state <= next_state;

  assign st_idle     = state == ST_IDLE;
  assign st_fill_mem = state == ST_FILL_MEM;
  assign st_process  = state == ST_PROCESS;
  assign st_done     = state == ST_DONE;

//---------------------------------
// Fill memory
//---------------------------------
  initial begin
    data_t blwe_q[PEM_PC-1:0][$];
    data_t ct_data;
    logic [AXI4_DATA_W-1:0] axi_q[$];
    logic [BLWE_COEF_PER_AXI4_WORD-1:0][BLWE_ACS_W-1:0] b_axi_word;

    for (int pc=0; pc<PEM_PC_MAX; pc=pc+1) begin
      case (pc)
        0: gen_mem_loop[0].maxi4_if.init();
        1: gen_mem_loop[1].maxi4_if.init();
        2: gen_mem_loop[2].maxi4_if.init();
        3: gen_mem_loop[3].maxi4_if.init();
        default: $display("%t > WARNING: init of maxi_if for pc %0d could not be done", $time, pc);
      endcase
    end
    fill_mem_done <= 1'b0;

    wait (st_fill_mem);
    @(posedge clk);
    $display("%t > INFO: Load ciphertexts in memory.", $time);
    for (int b=0; b<PROC_CT_NB; b=b+1) begin

      // Write BLWE
      for (int i=0; i<(AXI4_WORD_PER_BLWE+PEM_PC)*BLWE_COEF_PER_AXI4_WORD; i=i+1) begin // +PEM_PC to avoid sending 'x'
        integer pc;
        pc = (i / REGF_COEF_PER_PC) % PEM_PC;
        ct_data.cid = b;
        ct_data.idx   = i;
        blwe_q[pc].push_back(ct_data);
      end
      for (int p=0; p<PEM_PC; p=p+1) begin
        axi_q.delete();
        while (blwe_q[p].size() > 0) begin
          b_axi_word = '0;
          for (int i=0; i<BLWE_COEF_PER_AXI4_WORD; i=i+1) begin
            // Workaround
            // The following line is misinterpreted by xsim
            //b_axi_word[i] = blwe_q[p].pop_front();
            ct_data = blwe_q[p].pop_front();
            b_axi_word[i] = ct_data;
            //$display("[PC=%0d][%0d] val=0x%016x",p,i,b_axi_word[i]);
          end
          axi_q.push_back(b_axi_word);
        end // while

        $display("%t > INFO: BLWE %0d in memory at @=0x%016x.", $time, b, b * CT_MEM_BYTES + ct_mem_addr[p]);
        if (p == 0)
          gen_mem_loop[0].maxi4_if.write_trans(b * CT_MEM_BYTES + ct_mem_addr[p], axi_q);
        else if (p == 1)
          gen_mem_loop[1].maxi4_if.write_trans(b * CT_MEM_BYTES + ct_mem_addr[p], axi_q);
        else if (p == 2)
          gen_mem_loop[2].maxi4_if.write_trans(b * CT_MEM_BYTES + ct_mem_addr[p], axi_q);
        else if (p == 3)
          gen_mem_loop[3].maxi4_if.write_trans(b * CT_MEM_BYTES + ct_mem_addr[p], axi_q);
        else
          $fatal(1,"> ERROR: Unsupported number of PEM_PC (%0d). The testbench must be modified to support it.", PEM_PC);
      end

    end // for PROC_CT_NB

    @(posedge clk) begin
      fill_mem_done <= 1'b1;
    end
    $display("%t > INFO: Start process.", $time);
  end // initial

//---------------------------------
// Process
//---------------------------------
  pem_cmd_t cmd_t;
  logic [CID_W-1:0] cmd_cid;

  assign cmd = cmd_t;
  assign cmd_t.cid  = cmd_cid % PROC_CT_NB;
  assign cmd_t.reg_id = cmd_cid % REGF_REG_NB;
  stream_source
  #(
    .FILENAME   ("counter"),
    .DATA_TYPE  ("ascii_hex"),
    .DATA_W     (CID_W),
    .RAND_RANGE (RAND_RANGE),
    .KEEP_VLD   (1'b0),
    .MASK_DATA  ("x")
  ) stream_source (
      .clk       (clk),
      .s_rst_n   (s_rst_n),

      .data      (cmd_cid),
      .vld       (cmd_vld),
      .rdy       (cmd_rdy),

      .throughput(0)
  );

  logic in_cmd_done;
  assign proc_done = in_cmd_done;
  initial begin
    integer dummy;
    in_cmd_done = 1'b0;
    dummy = stream_source.open();
    wait(st_process);
    @(posedge clk);
    stream_source.start(SAMPLE_NB);
    wait (stream_source.running);
    wait (!stream_source.running);

    in_cmd_done = 1'b1;

  end

//---------------------------------
// Regfile
//---------------------------------
  regfile
  #(
    .PEA_PERIOD (PEA_PERIOD),
    .PEM_PERIOD (PEM_PERIOD),
    .PEP_PERIOD (PEP_PERIOD),
    .URAM_LATENCY (URAM_LATENCY)
  ) regfile (
    .clk                    (clk),        // clock
    .s_rst_n                (s_rst_n),    // synchronous reset

    .pem_regf_wr_req_vld    (pem_regf_wr_req_vld ),
    .pem_regf_wr_req_rdy    (pem_regf_wr_req_rdy ),
    .pem_regf_wr_req        (pem_regf_wr_req     ),

    .pem_regf_wr_data_vld   (pem_regf_wr_data_vld),
    .pem_regf_wr_data_rdy   (pem_regf_wr_data_rdy),
    .pem_regf_wr_data       (pem_regf_wr_data    ),

    .pem_regf_rd_req_vld    ('0),/*UNUSED*/
    .pem_regf_rd_req_rdy    (/*UNUSED*/),
    .pem_regf_rd_req        (/*UNUSED*/),

    .regf_pem_rd_data_avail (/*UNUSED*/),
    .regf_pem_rd_data       (/*UNUSED*/),
    .regf_pem_rd_last_word  (/*UNUSED*/), // valid with avail[0]
    .regf_pem_rd_last_mask  (/*UNUSED*/), // valid with avail[0]
    .regf_pem_rd_is_body    (/*UNUSED*/),

    .pea_regf_wr_req_vld    ('0),/*UNUSED*/
    .pea_regf_wr_req_rdy    (/*UNUSED*/),
    .pea_regf_wr_req        (/*UNUSED*/),

    .pea_regf_wr_data_vld   ('0),/*UNUSED*/
    .pea_regf_wr_data_rdy   (/*UNUSED*/),
    .pea_regf_wr_data       (/*UNUSED*/),


    .pea_regf_rd_req_vld    ('0),/*UNUSED*/
    .pea_regf_rd_req_rdy    (/*UNUSED*/),
    .pea_regf_rd_req        (/*UNUSED*/),

    .regf_pea_rd_data_avail (/*UNUSED*/),
    .regf_pea_rd_data       (/*UNUSED*/),
    .regf_pea_rd_last_word  (/*UNUSED*/), // valid with avail[0]
    .regf_pea_rd_last_mask  (/*UNUSED*/), // valid with avail[0]
    .regf_pea_rd_is_body    (/*UNUSED*/),

    .pep_regf_wr_req_vld    ('0),/*UNUSED*/
    .pep_regf_wr_req_rdy    (/*UNUSED*/),
    .pep_regf_wr_req        (/*UNUSED*/),

    .pep_regf_wr_data_vld   ('0),/*UNUSED*/
    .pep_regf_wr_data_rdy   (/*UNUSED*/),
    .pep_regf_wr_data       (/*UNUSED*/),

    .pep_regf_rd_req_vld    ('0),/*UNUSED*/
    .pep_regf_rd_req_rdy    (/*UNUSED*/),
    .pep_regf_rd_req        (/*UNUSED*/),

    .regf_pep_rd_data_avail (/*UNUSED*/),
    .regf_pep_rd_data       (/*UNUSED*/),
    .regf_pep_rd_last_word  (/*UNUSED*/), // valid with avail[0]
    .regf_pep_rd_last_mask  (/*UNUSED*/), // valid with avail[0]
    .regf_pep_rd_is_body    (/*UNUSED*/),


    .pem_wr_ack             (regf_pem_wr_ack),
    .pea_wr_ack             (/*UNUSED*/),
    .pep_wr_ack             (/*UNUSED*/)
  );

//---------------------------------
// Check req
//---------------------------------
  regf_wr_req_t pem_regf_wr_req_s;
  integer cur_add;
  integer req_cnt;

  assign pem_regf_wr_req_s = pem_regf_wr_req;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      cur_add    <= REGF_BLWE_WORD_PER_RAM+1;
      req_cnt    <= -1;
    end
    else begin
      if (pem_regf_wr_req_vld && pem_regf_wr_req_rdy) begin
        if (pem_regf_wr_req_s.reg_id != (req_cnt % REGF_REG_NB)) begin
          cur_add <= pem_regf_wr_req_s.start_word + pem_regf_wr_req_s.word_nb_m1 + 1;
          req_cnt <= req_cnt + 1;
        end
        else begin
          cur_add <= cur_add + pem_regf_wr_req_s.word_nb_m1 + 1;
          req_cnt <= req_cnt;
        end
      end
    end

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      error_req <= 1'b0;
    end
    else begin
      if (pem_regf_wr_req_vld && pem_regf_wr_req_rdy) begin
        if(pem_regf_wr_req_s.reg_id != (req_cnt % REGF_REG_NB)) begin

          assert(pem_regf_wr_req_s.start_word == 0)
          else begin
            $display("%t> ERROR: Mismatch request start_word (1rst ct req). exp=0x%0x seen=0x%0x", $time, 0, pem_regf_wr_req_s.start_word);
            error_req <= 1'b1;
          end

          assert(cur_add == REGF_BLWE_WORD_PER_RAM+1)
          else begin
            $display("%t> ERROR: Not the correct of word sent for previous reg. exp=%0d seen=%0d", $time, REGF_BLWE_WORD_PER_RAM+1, cur_add);
            error_req <= 1'b1;
          end
        end
        else begin
          assert(pem_regf_wr_req_s.start_word == cur_add)
          else begin
            $display("%t> ERROR: Mismatch request start_word. exp=0x%0x seen=0x%0x", $time, cur_add, pem_regf_wr_req_s.start_word);
            error_req <= 1'b1;
          end
        end // reg_id == req_cnt % REGF_REG_NB
      end // if rdy & vld
    end // else

//---------------------------------
// Check data
//---------------------------------
  integer ref_data_idx[REGF_COEF_NB];
  integer ref_data_cid[REGF_COEF_NB];
  data_t [REGF_COEF_NB-1:0] pem_regf_wr_data_s;
  bit [REGF_COEF_NB-1:0] ref_data_done;

  always_comb
    for (int i=0; i<REGF_COEF_NB; i=i+1)
      pem_regf_wr_data_s[i] = pem_regf_wr_data[i];

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      for (int i=0;i<REGF_COEF_NB; i=i+1)
        ref_data_idx[i]   = i;
      ref_data_cid = '{REGF_COEF_NB{0}};
      error_data <= 1'b0;
      ref_data_done <= '0;
    end
    else begin
      for (int c=0; c<REGF_COEF_NB; c=c+1) begin
        if (pem_regf_wr_data_vld[c] && pem_regf_wr_data_rdy[c]) begin
          integer idx_tmp;

          if (ref_data_idx[c] < BLWE_K_P1) begin // Do not check dummy coef, that are here to accompany the body coef
            assert((pem_regf_wr_data_s[c].idx == ref_data_idx[c]) && (pem_regf_wr_data_s[c].cid == (ref_data_cid[c] % PROC_CT_NB)))
            else begin
              $display("%t> ERROR: Mismatch data [%0d] exp=0x%0x seen=0x%0x ,  cid exp=0x%0x seen=0x%0x", $time,
                      c, ref_data_idx[c], pem_regf_wr_data_s[c].idx, ref_data_cid[c] % PROC_CT_NB, pem_regf_wr_data_s[c].cid);
              error_data <= 1'b1;
            end
          end

          idx_tmp = ref_data_idx[c] + REGF_COEF_NB;
          ref_data_idx[c] <= idx_tmp >= BLWE_K_P1 + c ? c : ref_data_idx[c] + REGF_COEF_NB;
          ref_data_cid[c] <= idx_tmp >= BLWE_K_P1 + c ? ref_data_cid[c] + 1 : ref_data_cid[c];
        end
        ref_data_done[c] <= (ref_data_cid[c] == SAMPLE_NB) ? 1'b1 : 1'b0;
      end
    end

//---------------------------------
// Count ack
//---------------------------------
  integer ack_cnt;

  always_ff @(posedge clk)
    if (!s_rst_n)
      ack_cnt <= '0;
    else
      if (cmd_ack)
        ack_cnt <= ack_cnt + 1;

//---------------------------------
// End of test
//---------------------------------
  initial begin
    start       <= 1'b0;
    error_ack   <= 1'b0;
    end_of_test <= 1'b0;
    wait (s_rst_n);

    @(posedge clk)
    start <= 1'b1;

    $display("%t > Wait done...",$time);
    wait(st_done);
    $display("%t > Done",$time);
    $display("%t > Wait all data...",$time);
    wait(ref_data_done == '1);
    $display("%t > Done",$time);

    repeat(50) @(posedge clk);
    assert(ack_cnt == SAMPLE_NB)
    else begin
      $display("%t> ERROR: Not enough acknowledge", $time);
      error_ack <= 1'b1;
    end

    repeat(50) @(posedge clk);
    end_of_test <= 1'b1;
  end

endmodule
