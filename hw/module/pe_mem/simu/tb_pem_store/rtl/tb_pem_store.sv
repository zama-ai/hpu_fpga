// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the verification of tb_pem_store.
// ==============================================================================================

module tb_pem_store;
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

  parameter  int PROC_CT_NB      = 64;
  parameter  int SAMPLE_NB       = 400;
  localparam int CT_PAGE_NB      = CT_MEM_BYTES / PAGE_BYTES;

  parameter  int PEA_PERIOD   = REGF_COEF_NB;
  parameter  int PEM_PERIOD   = (REGF_COEF_NB / BLWE_COEF_PER_AXI4_WORD) == 0 ? 1: (REGF_COEF_NB / BLWE_COEF_PER_AXI4_WORD);
  parameter  int PEP_PERIOD   = 2;
  localparam int URAM_LATENCY = 1+2;

  localparam int PEM_PC_MAX = 4;

  parameter int MEM_WR_CMD_BUF_DEPTH = 4; // Should be >= 1
  parameter int MEM_RD_CMD_BUF_DEPTH = 1; // Should be >= 1
  // Data latency
  parameter int MEM_WR_DATA_LATENCY = 42; // Should be >= 1
  parameter int MEM_RD_DATA_LATENCY = 1; // Should be >= 1
  // Set random on ready valid, on write path
  parameter bit MEM_USE_WR_RANDOM = 1;
  // Set random on ready valid, on read path
  parameter bit MEM_USE_RD_RANDOM = 0; // check path, no need random

  // Number of consecutive AXI4 words within a PC
  localparam int CONS_AXI4_WORD_IN_PC = REGF_COEF_PER_PC / BLWE_COEF_PER_AXI4_WORD;
  // AXI4 word partitioning
  localparam int AXI4_WORD_PART_NB = BLWE_COEF_PER_AXI4_WORD / REGF_COEF_PER_PC;

  initial begin
    $display("> INFO: PEM_PC=%0d",PEM_PC);
    $display("> INFO: REGF_COEF_NB=%0d",REGF_COEF_NB);
    $display("> INFO: REGF_REG_NB=%0d",REGF_REG_NB);
  end


// ============================================================================================== --
// type
// ============================================================================================== --
  typedef struct packed {
    logic [15:0]  reg_id;
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

  assign error = error_data;

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
  logic                                   pem_regf_rd_req_vld;
  logic                                   pem_regf_rd_req_rdy;
  logic [REGF_RD_REQ_W-1:0]               pem_regf_rd_req;

  logic [REGF_COEF_NB-1:0]                regf_pem_rd_data_avail;
  logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0]   regf_pem_rd_data;
  logic                                   regf_pem_rd_last_word; // valid with avail[0]
  logic                                   regf_pem_rd_is_body;
  logic                                   regf_pem_rd_last_mask;

  // AXI4 interface
  // Write channel
  logic [PEM_PC_MAX-1:0][AXI4_ID_W-1:0]       m_axi4_awid;
  logic [PEM_PC_MAX-1:0][axi_if_ct_axi_pkg::AXI4_ADD_W-1:0]      m_axi4_awaddr;
  logic [PEM_PC_MAX-1:0][7:0]                 m_axi4_awlen;
  logic [PEM_PC_MAX-1:0][2:0]                 m_axi4_awsize;
  logic [PEM_PC_MAX-1:0][1:0]                 m_axi4_awburst;
  logic [PEM_PC_MAX-1:0]                      m_axi4_awvalid;
  logic [PEM_PC_MAX-1:0]                      m_axi4_awready;
  logic [PEM_PC_MAX-1:0][AXI4_DATA_W-1:0]     m_axi4_wdata;
  logic [PEM_PC_MAX-1:0][(AXI4_DATA_W/8)-1:0] m_axi4_wstrb;
  logic [PEM_PC_MAX-1:0]                      m_axi4_wlast;
  logic [PEM_PC_MAX-1:0]                      m_axi4_wvalid;
  logic [PEM_PC_MAX-1:0]                      m_axi4_wready;
  logic [PEM_PC_MAX-1:0][AXI4_ID_W-1:0]       m_axi4_bid;
  logic [PEM_PC_MAX-1:0][1:0]                 m_axi4_bresp;
  logic [PEM_PC_MAX-1:0]                      m_axi4_bvalid;
  logic [PEM_PC_MAX-1:0]                      m_axi4_bready;

// ============================================================================================== --
// Design under test instance
// ============================================================================================== --
  pem_store #(
    .INST_FIFO_DEPTH(INST_FIFO_DEPTH)
  ) dut (
    .clk                    (clk    ),
    .s_rst_n                (s_rst_n),

    .ct_mem_addr            (ct_mem_addr), // Address offset for CT

    .cmd                    (cmd),
    .cmd_vld                (cmd_vld),
    .cmd_rdy                (cmd_rdy),

    .cmd_ack                (cmd_ack),

    .pem_regf_rd_req_vld    (pem_regf_rd_req_vld),
    .pem_regf_rd_req_rdy    (pem_regf_rd_req_rdy),
    .pem_regf_rd_req        (pem_regf_rd_req),

    .regf_pem_rd_data_avail (regf_pem_rd_data_avail),
    .regf_pem_rd_data       (regf_pem_rd_data),
    .regf_pem_rd_last_word  (regf_pem_rd_last_word),
    .regf_pem_rd_is_body    (regf_pem_rd_is_body),
    .regf_pem_rd_last_mask  (regf_pem_rd_last_mask),

    .m_axi4_awid            (m_axi4_awid[PEM_PC-1:0]),
    .m_axi4_awaddr          (m_axi4_awaddr[PEM_PC-1:0]),
    .m_axi4_awlen           (m_axi4_awlen[PEM_PC-1:0]),
    .m_axi4_awsize          (m_axi4_awsize[PEM_PC-1:0]),
    .m_axi4_awburst         (m_axi4_awburst[PEM_PC-1:0]),
    .m_axi4_awvalid         (m_axi4_awvalid[PEM_PC-1:0]),
    .m_axi4_awready         (m_axi4_awready[PEM_PC-1:0]),
    .m_axi4_wdata           (m_axi4_wdata[PEM_PC-1:0]),
    .m_axi4_wstrb           (m_axi4_wstrb[PEM_PC-1:0]),
    .m_axi4_wlast           (m_axi4_wlast[PEM_PC-1:0]),
    .m_axi4_wvalid          (m_axi4_wvalid[PEM_PC-1:0]),
    .m_axi4_wready          (m_axi4_wready[PEM_PC-1:0]),
    .m_axi4_bid             (m_axi4_bid[PEM_PC-1:0]),
    .m_axi4_bresp           (m_axi4_bresp[PEM_PC-1:0]),
    .m_axi4_bvalid          (m_axi4_bvalid[PEM_PC-1:0]),
    .m_axi4_bready          (m_axi4_bready[PEM_PC-1:0])
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
      logic [AXI4_ID_W-1:0]       axi4_rd_rid;
      logic [AXI4_DATA_W-1:0]     axi4_rd_rdata;
      logic [1:0]                 axi4_rd_rresp;
      logic                       axi4_rd_rlast;
      logic                       axi4_rd_rvalid;
      logic                       axi4_rd_rready;

      integer axi_w_elt_nb_q[$];

      always_ff @(posedge clk)
        if (m_axi4_awvalid[gen_p] && m_axi4_awready[gen_p])
          axi_w_elt_nb_q.push_back(m_axi4_awlen[gen_p]+1);

      integer axi_wdata_cnt;
      logic axi_wdata_mask;

      assign axi_wdata_mask = axi_wdata_cnt > 0;

      always_ff @(posedge clk)
        if (!s_rst_n)
          axi_wdata_cnt <= '0;
        else begin
          if (axi_wdata_cnt == 0 && axi_w_elt_nb_q.size() > 0)
            axi_wdata_cnt <= axi_w_elt_nb_q.pop_front();
          else if (axi_wdata_cnt > 0)
            if (m_axi4_wvalid[gen_p] && m_axi4_wready[gen_p])
              axi_wdata_cnt <= axi_wdata_cnt - 1;
        end


      logic m_axi4_wvalid_tmp;
      logic m_axi4_wready_tmp;

      assign m_axi4_wvalid_tmp = m_axi4_wvalid[gen_p] & axi_wdata_mask;
      assign m_axi4_wready[gen_p] = m_axi4_wready_tmp & axi_wdata_mask;

      axi4_mem #(
        .DATA_WIDTH(AXI4_DATA_W),
        .ADDR_WIDTH(AXI4_ADD_W),
        .ID_WIDTH  (AXI4_ID_W),
        .WR_CMD_BUF_DEPTH (MEM_WR_CMD_BUF_DEPTH),
        .RD_CMD_BUF_DEPTH (MEM_RD_CMD_BUF_DEPTH),
        .WR_DATA_LATENCY (MEM_WR_DATA_LATENCY + gen_p * 50),
        .RD_DATA_LATENCY (MEM_RD_DATA_LATENCY),
        .USE_WR_RANDOM (MEM_USE_WR_RANDOM),
        .USE_RD_RANDOM (MEM_USE_RD_RANDOM)
      ) axi4_mem_ct (
        .clk          (clk),
        .rst          (!s_rst_n),

        .s_axi4_awid   (m_axi4_awid[gen_p]   ),
        .s_axi4_awaddr (m_axi4_awaddr[gen_p] ),
        .s_axi4_awlen  (m_axi4_awlen[gen_p]  ),
        .s_axi4_awsize (m_axi4_awsize[gen_p] ),
        .s_axi4_awburst(m_axi4_awburst[gen_p]),
        .s_axi4_awlock ('0), // disable
        .s_axi4_awcache('0), // disable
        .s_axi4_awprot ('0), // disable
        .s_axi4_awvalid(m_axi4_awvalid[gen_p]),
        .s_axi4_awready(m_axi4_awready[gen_p]),
        .s_axi4_wdata  (m_axi4_wdata[gen_p]  ),
        .s_axi4_wstrb  (m_axi4_wstrb[gen_p]  ),
        .s_axi4_wlast  (m_axi4_wlast[gen_p]  ),
        .s_axi4_wvalid (m_axi4_wvalid_tmp ),
        .s_axi4_wready (m_axi4_wready_tmp ),
        .s_axi4_bid    (m_axi4_bid[gen_p]    ),
        .s_axi4_bresp  (m_axi4_bresp[gen_p]  ),
        .s_axi4_bvalid (m_axi4_bvalid[gen_p] ),
        .s_axi4_bready (m_axi4_bready[gen_p] ),
        .s_axi4_arid   (axi4_rd_arid   ),
        .s_axi4_araddr (axi4_rd_araddr ),
        .s_axi4_arlen  (axi4_rd_arlen  ),
        .s_axi4_arsize (axi4_rd_arsize ),
        .s_axi4_arburst(axi4_rd_arburst),
        .s_axi4_arlock ('0), // disable
        .s_axi4_arcache('0), // disable
        .s_axi4_arprot ('0), // disable
        .s_axi4_arvalid(axi4_rd_arvalid),
        .s_axi4_arready(axi4_rd_arready),
        .s_axi4_rid    (axi4_rd_rid    ),
        .s_axi4_rdata  (axi4_rd_rdata  ),
        .s_axi4_rresp  (axi4_rd_rresp  ),
        .s_axi4_rlast  (axi4_rd_rlast  ),
        .s_axi4_rvalid (axi4_rd_rvalid ),
        .s_axi4_rready (axi4_rd_rready )
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
      // Read interface
      assign axi4_rd_arid      = maxi4_if.arid;
      assign axi4_rd_araddr    = maxi4_if.araddr;
      assign axi4_rd_arlen     = maxi4_if.arlen;
      assign axi4_rd_arsize    = maxi4_if.arsize;
      assign axi4_rd_arburst   = maxi4_if.arburst;
      assign axi4_rd_arvalid   = maxi4_if.arvalid;
      assign maxi4_if.arready = axi4_rd_arready;
      assign maxi4_if.rid     = axi4_rd_rid   ;
      assign maxi4_if.rdata   = axi4_rd_rdata ;
      assign maxi4_if.rresp   = axi4_rd_rresp ;
      assign maxi4_if.rlast   = axi4_rd_rlast ;
      assign maxi4_if.rvalid  = axi4_rd_rvalid;
      assign axi4_rd_rready    = maxi4_if.rready;

      // Write interface
      assign maxi4_if.awready = 1'b0;
      assign maxi4_if.wready  = 1'b0;
      assign maxi4_if.bresp   = AXI4_OKAY;
      assign maxi4_if.bvalid  = 1'b0;
    end
  endgenerate

// ============================================================================================== --
// Regfile
// ============================================================================================== --
  logic                                 regf_wr_req_vld;
  logic                                 regf_wr_req_rdy;
  regf_wr_req_t                         regf_wr_req;

  logic [REGF_COEF_NB-1:0]              regf_wr_data_vld;
  logic [REGF_COEF_NB-1:0]              regf_wr_data_rdy;
  logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0] regf_wr_data;

  regfile
  #(
    .PEA_PERIOD (PEA_PERIOD),
    .PEM_PERIOD (PEM_PERIOD),
    .PEP_PERIOD (PEP_PERIOD),
    .URAM_LATENCY (URAM_LATENCY)
  ) regfile (
    .clk                    (clk),        // clock
    .s_rst_n                (s_rst_n),    // synchronous reset

    .pem_regf_wr_req_vld    (regf_wr_req_vld ),
    .pem_regf_wr_req_rdy    (regf_wr_req_rdy ),
    .pem_regf_wr_req        (regf_wr_req     ),

    .pem_regf_wr_data_vld   (regf_wr_data_vld),
    .pem_regf_wr_data_rdy   (regf_wr_data_rdy),
    .pem_regf_wr_data       (regf_wr_data    ),

    .pem_regf_rd_req_vld    (pem_regf_rd_req_vld   ),
    .pem_regf_rd_req_rdy    (pem_regf_rd_req_rdy   ),
    .pem_regf_rd_req        (pem_regf_rd_req       ),

    .regf_pem_rd_data_avail (regf_pem_rd_data_avail),
    .regf_pem_rd_data       (regf_pem_rd_data      ),
    .regf_pem_rd_last_word  (regf_pem_rd_last_word ),
    .regf_pem_rd_last_mask  (regf_pem_rd_last_mask ),
    .regf_pem_rd_is_body    (regf_pem_rd_is_body   ),

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


// ============================================================================================== --
// Scenario
// ============================================================================================== --
  // page aligned addresses
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
                ST_FILL_REGF,
                ST_PROCESS,
                ST_DONE} state_e;

  state_e state;
  state_e next_state;
  logic st_idle;
  logic st_fill_regf;
  logic st_process;
  logic st_done;

  logic start;
  logic fill_regf_done;
  logic proc_done;
  logic test_done;

  always_comb
    case (state)
      ST_IDLE:
        next_state = start ? ST_FILL_REGF : state;
      ST_FILL_REGF:
        next_state = fill_regf_done ? ST_PROCESS : state;
      ST_PROCESS:
        next_state = proc_done ? ST_DONE : state;
      ST_DONE:
        next_state = state;
    endcase

  always_ff @(posedge clk)
    if (!s_rst_n) state <= ST_IDLE;
    else          state <= next_state;

  assign st_idle      = state == ST_IDLE;
  assign st_fill_regf = state == ST_FILL_REGF;
  assign st_process   = state == ST_PROCESS;
  assign st_done      = state == ST_DONE;

//---------------------------------
// Fill regfile
//---------------------------------
  regf_wr_req_t       regf_wr_req_q[$];
  logic [MOD_Q_W-1:0] regf_wr_data_q [REGF_COEF_NB-1:0][$];

  initial begin
    regf_wr_req_t req;
    data_t        ct_data;

    fill_regf_done <= 1'b0;

    for (int b=0; b<REGF_REG_NB; b=b+1) begin
      // Build request
      req.reg_id     = b;
      req.start_word = 0;
      req.word_nb_m1 = REGF_BLWE_WORD_PER_RAM; // Includes body

      regf_wr_req_q.push_back(req);

      // Build data
      for (int i=0; i<((BLWE_K_P1+REGF_COEF_NB-1) / REGF_COEF_NB) * REGF_COEF_NB; i=i+1) begin
        ct_data.reg_id = b;
        ct_data.idx    = i;
        regf_wr_data_q[i%REGF_COEF_NB].push_back(ct_data);
      end
    end // for REGF_COEF_NB

    wait (regf_wr_req_q.size() == 0);
    for (int i=0; i<REGF_COEF_NB; i=i+1)
      wait(regf_wr_data_q[i].size() == 0);

    repeat(10+REGF_SEQ) @(posedge clk);
    fill_regf_done <= 1'b1;

  end // initial

  logic         wr_req_avail;
  regf_wr_req_t wr_req_tmp;
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      wr_req_avail <= 1'b0;
      wr_req_tmp   <= '0;
    end
    else
      if (st_fill_regf && (wr_req_avail == 1'b0 || (regf_wr_req_vld && regf_wr_req_rdy))) begin
        wr_req_avail <= regf_wr_req_q.size() > 0;
        if (regf_wr_req_q.size() > 0) begin
          wr_req_tmp <= regf_wr_req_q[0];
          regf_wr_req_q.pop_front();
        end
      end

  assign regf_wr_req_vld = wr_req_avail & st_fill_regf;
  assign regf_wr_req     = wr_req_tmp;

  for (genvar gen_c=0; gen_c<REGF_COEF_NB; gen_c=gen_c+1) begin
    logic               wr_data_avail;
    logic [MOD_Q_W-1:0] wr_data_tmp;
    always_ff @(posedge clk)
      if (!s_rst_n) begin
        wr_data_avail <= 1'b0;
        wr_data_tmp   <= '0;
      end
      else
        if (st_fill_regf && (wr_data_avail == 1'b0 || (regf_wr_data_vld[gen_c] && regf_wr_data_rdy[gen_c]))) begin
          wr_data_avail <= regf_wr_data_q[gen_c].size() > 0;
          if (regf_wr_data_q[gen_c].size() > 0) begin
            wr_data_tmp <= regf_wr_data_q[gen_c][0];
            regf_wr_data_q[gen_c].pop_front();
          end
        end

    assign regf_wr_data_vld[gen_c] = st_fill_regf & wr_data_avail;
    assign regf_wr_data[gen_c]     = wr_data_tmp;
  end // for gen_c

//---------------------------------
// Process
//---------------------------------
  pem_cmd_t cmd_t;
  logic [CID_W-1:0] cmd_cid;

  assign cmd = cmd_t;
  assign cmd_t.cid  = cmd_cid % PROC_CT_NB;
  assign cmd_t.reg_id = cmd_t.cid % REGF_REG_NB;
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
// Check
//---------------------------------
  logic cmd_ack_q[$];

  always_ff @(posedge clk)
    if (cmd_ack)
      cmd_ack_q.push_back(1);


  initial begin
    integer cid;
    logic [AXI4_DATA_W-1: 0] ram_q[PEM_PC-1:0][$];

    for (int pc=0; pc<PEM_PC_MAX; pc=pc+1) begin
      case (pc)
        0: gen_mem_loop[0].maxi4_if.init();
        1: gen_mem_loop[1].maxi4_if.init();
        2: gen_mem_loop[2].maxi4_if.init();
        3: gen_mem_loop[3].maxi4_if.init();
        default: $display("%t > WARNING: init of maxi4_if for pc %0d could not be done", $time, pc);
      endcase
    end

    error_data <= 1'b0;
    cid = 0;
    repeat(SAMPLE_NB) begin
      wait(cmd_ack_q.size() > 0);

      if (cid%10 == 0)
        $display("%t> INFO: Reading results for CT=%0d", $time, cid);
      // 1 BLWE is available in RAM
      // Read it
      fork
        begin : to_isolate
          for (int p=0; p<PEM_PC; p=p+1) begin
            fork
              automatic int k = p;
              begin
                ram_q[k].delete();
                if (k==0)
                  //\gen_mem_loop[0].maxi4_if .read_trans((cid%PROC_CT_NB) * CT_MEM_BYTES + ct_mem_addr[k] , k==0 ? AXI4_WORD_PER_PC0:AXI4_WORD_PER_PC, ram_q[k]);
                  begin
                    int idx;
                    idx=0;
                    while (idx < AXI4_WORD_PER_PC0) begin
                      ram_q[k].push_back(gen_mem_loop[0].axi4_mem_ct.axi4_ram_ct_wr.mem[((cid%PROC_CT_NB) * CT_MEM_BYTES + ct_mem_addr[k])/AXI4_DATA_BYTES + idx]);
                      idx = idx + 1;
                    end
                  end
                else if (k==1)
                  //\gen_mem_loop[1].maxi4_if .read_trans((cid%PROC_CT_NB) * CT_MEM_BYTES + ct_mem_addr[k] , k==0 ? AXI4_WORD_PER_PC0:AXI4_WORD_PER_PC, ram_q[k]);
                  begin
                    int idx;
                    idx=0;
                    while (idx < AXI4_WORD_PER_PC) begin
                      ram_q[k].push_back(gen_mem_loop[1].axi4_mem_ct.axi4_ram_ct_wr.mem[((cid%PROC_CT_NB) * CT_MEM_BYTES + ct_mem_addr[k])/AXI4_DATA_BYTES + idx]);
                      idx = idx + 1;
                    end
                  end
                else if (k==2)
                  //\gen_mem_loop[2].maxi4_if .read_trans((cid%PROC_CT_NB) * CT_MEM_BYTES + ct_mem_addr[k] , k==0 ? AXI4_WORD_PER_PC0:AXI4_WORD_PER_PC, ram_q[k]);
                  begin
                    int idx;
                    idx=0;
                    while (idx < AXI4_WORD_PER_PC) begin
                      ram_q[k].push_back(gen_mem_loop[2].axi4_mem_ct.axi4_ram_ct_wr.mem[((cid%PROC_CT_NB) * CT_MEM_BYTES + ct_mem_addr[k])/AXI4_DATA_BYTES + idx]);
                      idx = idx + 1;
                    end
                  end
                else if (k==3)
                  //\gen_mem_loop[3].maxi4_if .read_trans((cid%PROC_CT_NB) * CT_MEM_BYTES + ct_mem_addr[k] , k==0 ? AXI4_WORD_PER_PC0:AXI4_WORD_PER_PC, ram_q[k]);
                  begin
                    int idx;
                    idx=0;
                    while (idx < AXI4_WORD_PER_PC) begin
                      ram_q[k].push_back(gen_mem_loop[3].axi4_mem_ct.axi4_ram_ct_wr.mem[((cid%PROC_CT_NB) * CT_MEM_BYTES + ct_mem_addr[k])/AXI4_DATA_BYTES + idx]);
                      idx = idx + 1;
                    end
                  end
                else
                  $fatal(1,"%t> ERROR: Only PEM_PC_MAX=4 is supported by the bench.", $time);
              end
            join_none
          end // for p
          wait fork; // will not wait for some other process
        end : to_isolate
      join

      if (cid%10 == 0)
        $display("%t> INFO: Start check results for CT=%0d ...", $time, cid);
      // Check data
      if (BLWE_COEF_PER_AXI4_WORD <= REGF_COEF_PER_PC) begin
        for (int w=0; w<(AXI4_WORD_PER_BLWE+1); w=w+1) begin // + 1 for the body
          integer pc;
          integer idx, idx_0;
          integer part_idx;
          integer subpart_idx;
          logic [BLWE_COEF_PER_AXI4_WORD-1:0][BLWE_ACS_W-1:0] rd_data;
          part_idx = w / CONS_AXI4_WORD_IN_PC;
          subpart_idx = w % CONS_AXI4_WORD_IN_PC;
          idx_0 = (part_idx*CONS_AXI4_WORD_IN_PC + subpart_idx) * BLWE_COEF_PER_AXI4_WORD;
          pc = part_idx % PEM_PC;
          rd_data = ram_q[pc].pop_front();
          for (int i=0; i<BLWE_COEF_PER_AXI4_WORD; i=i+1) begin
            data_t d_ref;
            logic [BLWE_ACS_W-1:0] d_ref_ext;
            idx = idx_0 + i;
            if (idx < BLWE_K+1) begin
              d_ref.reg_id = (cid%PROC_CT_NB) % REGF_REG_NB;
              d_ref.idx    = idx;
              d_ref_ext = d_ref; // extend with 0s
              assert(d_ref_ext == rd_data[i])
              else begin
                $display("%t > ERROR: Data mismatch cid=%0d axi_w=%0d coef=%0d idx=%0d PC=%0d exp=0x%0x seen=0x%0x",$time, cid, w, i, idx, pc, d_ref_ext, rd_data[i]);
                @(posedge clk) error_data <= 1'b1;
              end
            end // if check
          end // for i
        end // for w
      end
      else begin
        for (int w=0; w<(AXI4_WORD_PER_BLWE+1); w=w+1) begin // + 1 for the body
          integer pc;
          integer part_idx, part_idx_0;
          integer idx, idx_0;
          logic [BLWE_COEF_PER_AXI4_WORD-1:0][BLWE_ACS_W-1:0] rd_data;
          pc = w % PEM_PC;
          rd_data = ram_q[pc].pop_front();
          part_idx_0 = (w / PEM_PC) * PEM_PC*AXI4_WORD_PART_NB + w % PEM_PC;
          for (int i=0; i<BLWE_COEF_PER_AXI4_WORD; i=i+1) begin
            data_t d_ref;
            logic [BLWE_ACS_W-1:0] d_ref_ext;
            part_idx = part_idx_0 + (i / REGF_COEF_PER_PC)*PEM_PC;
            idx_0 = part_idx * REGF_COEF_PER_PC;
            idx = idx_0 + i % REGF_COEF_PER_PC;
            if (idx < BLWE_K+1) begin
              d_ref.reg_id = (cid%PROC_CT_NB) % REGF_REG_NB;
              d_ref.idx    = idx;
              d_ref_ext = d_ref; // extend with 0s
              assert(d_ref_ext == rd_data[i])
              else begin
                $display("%t > ERROR: Data mismatch cid=%0d axi_w=%0d coef=%0d idx=%0d PC=%0d exp=0x%0x seen=0x%0x",$time, cid, w, i, idx, pc, d_ref_ext, rd_data[i]);
                @(posedge clk) error_data <= 1'b1;
              end
            end // if check
          end // for i
        end // for w
      end
      if (cid%10 == 0)
        $display("%t> INFO: Done check results for CT=%0d.", $time, cid);
      cid = cid + 1;
      cmd_ack_q.pop_front();
    end // repeat
  end

//---------------------------------
// Ack
//---------------------------------
  integer ack_cnt;
  integer bresp_cnt [PEM_PC];

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      ack_cnt   <= '0;
      bresp_cnt <= '{PEM_PC{0}};
    end
    else begin
      ack_cnt   <= cmd_ack ? ack_cnt + 1 : ack_cnt;
      for (int i=0; i<PEM_PC; i=i+1)
        bresp_cnt[i] <= m_axi4_bvalid[i] && m_axi4_bready[i] ? bresp_cnt[i] + 1 : bresp_cnt[i];
    end
//---------------------------------
// End of test
//---------------------------------
  initial begin
    start       <= 1'b0;
    end_of_test <= 1'b0;
    wait (s_rst_n);

    @(posedge clk)
    start <= 1'b1;

    $display("%t > Wait done state...",$time);
    wait(st_done);
    $display("%t > Done",$time);

    $display("%t > Wait all the ack...",$time);
    wait (ack_cnt == SAMPLE_NB);
    $display("%t > Done",$time);

    $display("%t > Wait all the check...",$time);
    wait (cmd_ack_q.size() == 0);
    $display("%t > Done",$time);

    repeat(50) @(posedge clk);
    end_of_test <= 1'b1;
  end

endmodule
