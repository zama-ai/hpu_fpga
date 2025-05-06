// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module is a processing element (PE) of the HPU.
// It deals with the storage of BLWE from the register_file into the memory (DDR or HBM)
// ==============================================================================================

module pem_store
  import param_tfhe_pkg::*;
  import regf_common_param_pkg::*;
  import axi_if_common_param_pkg::*;
  import axi_if_ct_axi_pkg::*;
  import hpu_common_instruction_pkg::*;
  import top_common_param_pkg::*;
  import pem_common_param_pkg::*;
#(
  parameter int INST_FIFO_DEPTH = 4 // Should be >= 4. To bear the PC latency differences
)
(
  input  logic                                   clk,        // clock
  input  logic                                   s_rst_n,    // synchronous reset

  // Configuration
  input logic [PEM_PC_MAX-1:0][AXI4_ADD_W-1:0]   ct_mem_addr, // Address offset for CT

  // Command
  input  logic [PEM_CMD_W-1:0]                   cmd,
  input  logic                                   cmd_vld,
  output logic                                   cmd_rdy,

  output logic                                   cmd_ack,

  // pem <-> regfile
  // read
  output logic                                   pem_regf_rd_req_vld,
  input  logic                                   pem_regf_rd_req_rdy,
  output logic [REGF_RD_REQ_W-1:0]               pem_regf_rd_req,

  input  logic [REGF_COEF_NB-1:0]                regf_pem_rd_data_avail,
  input  logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0]   regf_pem_rd_data,
  input  logic                                   regf_pem_rd_last_word, // valid with avail[0]
  input  logic                                   regf_pem_rd_is_body,
  input  logic                                   regf_pem_rd_last_mask,

  // AXI4 interface
  // Write channel
  output logic [PEM_PC-1:0][AXI4_ID_W-1:0]       m_axi4_awid,
  output logic [PEM_PC-1:0][AXI4_ADD_W-1:0]      m_axi4_awaddr,
  output logic [PEM_PC-1:0][AXI4_LEN_W-1:0]      m_axi4_awlen,
  output logic [PEM_PC-1:0][AXI4_SIZE_W-1:0]     m_axi4_awsize,
  output logic [PEM_PC-1:0][AXI4_BURST_W-1:0]    m_axi4_awburst,
  output logic [PEM_PC-1:0]                      m_axi4_awvalid,
  input  logic [PEM_PC-1:0]                      m_axi4_awready,
  output logic [PEM_PC-1:0][AXI4_DATA_W-1:0]     m_axi4_wdata,
  output logic [PEM_PC-1:0][AXI4_STRB_W-1:0]     m_axi4_wstrb,
  output logic [PEM_PC-1:0]                      m_axi4_wlast,
  output logic [PEM_PC-1:0]                      m_axi4_wvalid,
  input  logic [PEM_PC-1:0]                      m_axi4_wready,
  input  logic [PEM_PC-1:0][AXI4_ID_W-1:0]       m_axi4_bid,
  input  logic [PEM_PC-1:0][AXI4_RESP_W-1:0]     m_axi4_bresp,
  input  logic [PEM_PC-1:0]                      m_axi4_bvalid,
  output logic [PEM_PC-1:0]                      m_axi4_bready,

  output pem_st_info_t                           pem_st_info

);

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int RCP_FIFO_DEPTH      = 2; // TOREVIEW : according to memory latency.
  localparam int BRSP_FIFO_DEPTH     = RCP_FIFO_DEPTH;
  localparam int SEQ_PER_PC          = REGF_SEQ / PEM_PC == 0 ? 1 : REGF_SEQ / PEM_PC;
  localparam int SEQ_PER_PC_W        = $clog2(SEQ_PER_PC) == 0 ? 1 : $clog2(SEQ_PER_PC);

  localparam int DATA_THRESHOLD_TMP      = 8; // AXI word unit
  localparam int REGF_WORD_THRESHOLD_TMP = (SEQ_PER_PC * REGF_SEQ_COEF_NB) >= BLWE_COEF_PER_AXI4_WORD ? DATA_THRESHOLD_TMP / ((SEQ_PER_PC *REGF_SEQ_COEF_NB) / BLWE_COEF_PER_AXI4_WORD) :
                                       DATA_THRESHOLD_TMP * (BLWE_COEF_PER_AXI4_WORD / (SEQ_PER_PC* REGF_SEQ_COEF_NB));
  localparam int REGF_WORD_THRESHOLD = REGF_WORD_THRESHOLD_TMP > 0 ? REGF_WORD_THRESHOLD_TMP : 1;
  localparam int AXI_WORD_THRESHOLD  = (REGF_WORD_THRESHOLD * SEQ_PER_PC * REGF_SEQ_COEF_NB) / BLWE_COEF_PER_AXI4_WORD;
  localparam int DATA_THRESHOLD      = DATA_THRESHOLD_TMP > AXI_WORD_THRESHOLD  ? DATA_THRESHOLD_TMP : AXI_WORD_THRESHOLD;
  localparam int DATA_FIFO_DEPTH     = 2*DATA_THRESHOLD;
  localparam int DATA_CNT_W          = $clog2(DATA_FIFO_DEPTH+1)==0 ? 1 : $clog2(DATA_FIFO_DEPTH+1); // Counts from 0 to DATA_FIFO_DEPTH included

  localparam int AXI_BURST_NB_MAX    = ((AXI4_WORD_PER_PC0 + PAGE_AXI4_DATA-1) / PAGE_AXI4_DATA) + 1; // +1 in case of address non alignement
  localparam int AXI_BURST_NB_MAX_W  = $clog2(AXI_BURST_NB_MAX) == 0 ? 1 : $clog2(AXI_BURST_NB_MAX);
  localparam int AXI_BURST_NB_MAX_WW = $clog2(AXI_BURST_NB_MAX+1) == 0 ? 1 : $clog2(AXI_BURST_NB_MAX+1);

  localparam int REGF_CMD_NB         = (REGF_BLWE_WORD_PER_RAM + REGF_WORD_THRESHOLD - 1) / REGF_WORD_THRESHOLD; // Do not take body into account
  localparam int REGF_CMD_NB_W       = $clog2(REGF_CMD_NB) == 0 ? 1 : $clog2(REGF_CMD_NB);

  localparam int LAST_REGF_WORD_THRESHOLD = (REGF_BLWE_WORD_PER_RAM % REGF_WORD_THRESHOLD) == 0 ? REGF_WORD_THRESHOLD : (REGF_BLWE_WORD_PER_RAM % REGF_WORD_THRESHOLD);
  localparam int LAST_DATA_THRESHOLD      = (AXI4_WORD_PER_PC % DATA_THRESHOLD) == 0 ? DATA_THRESHOLD : (AXI4_WORD_PER_PC % DATA_THRESHOLD);

  localparam int BRSP_CNT_W          = AXI_BURST_NB_MAX_WW + 2; // Should be enough to assume x4

  localparam int BRSP_SEEN_CNT_MAX   = BRSP_FIFO_DEPTH+2 +1; // +2 : Input/output pipe in BRSP cmd FIFO + 1 before of the pipefor the decr
  localparam int BRSP_SEEN_CNT_W     = $clog2(BRSP_SEEN_CNT_MAX+1) == 0 ? 1 : $clog2(BRSP_SEEN_CNT_MAX+1); // +1 :count to BRSP_FIFO_DEPTH+2 included

  generate
    if (PEM_PC > REGF_SEQ) begin : __UNSUPPORTED_PEM_PC_REGF_SEQ_
      $fatal(1,"ERROR> Unsupported PEM_PC (%0d) and REGF_SEQ (%0d). PEM_PC must be smaller or equal to REGF_SEQ",PEM_PC, REGF_SEQ);
    end
    if ((PEM_PC < REGF_SEQ) && ((REGF_SEQ/PEM_PC)*PEM_PC != REGF_SEQ)) begin : __UNSUPPORTED_PEM_PC_REGF_SEQ_BIS_
      $fatal(1,"ERROR> Unsupported PEM_PC (%0d) and REGF_SEQ (%0d). PEM_PC must divide REGF_SEQ.",PEM_PC, REGF_SEQ);
    end
  endgenerate

// pragma translate_off
  initial begin
    $display("> INFO: PEM_ST : AXI4_WORD_PER_PC0=%0d",AXI4_WORD_PER_PC0);
    $display("> INFO: PEM_ST : REGF_COEF_PER_PC=%0d",REGF_COEF_PER_PC);
    $display("> INFO: PEM_ST : REGF_WORD_THRESHOLD=%0d",REGF_WORD_THRESHOLD);
    $display("> INFO: PEM_ST : REGF_CMD_NB=%0d",REGF_CMD_NB);
    $display("> INFO: PEM_ST : SEQ_PER_PC=%0d",SEQ_PER_PC);
    $display("> INFO: PEM_ST : REGF_SEQ_COEF_NB=%0d",REGF_SEQ_COEF_NB);
    $display("> INFO: PEM_ST : BLWE_COEF_PER_AXI4_WORD=%0d", BLWE_COEF_PER_AXI4_WORD);
  end
// pragma translate_on


// ============================================================================================== --
// typedef
// ============================================================================================== --
  typedef struct packed {
    logic [AXI4_LEN_W:0] len;
  } rcp_cmd_t;

  localparam int RCP_CMD_W = $bits(rcp_cmd_t);

  typedef struct packed {
    logic [AXI_BURST_NB_MAX_W-1:0] burst_cnt_m1;
  } brsp_cmd_t;

  localparam int BRSP_CMD_W = $bits(brsp_cmd_t);

// ============================================================================================== --
// Input FIFO
// ============================================================================================== --
  // For debug
  pem_st_info_t pem_st_infoD_tmp;

  //== bresp
  logic [PEM_PC-1:0][AXI4_RESP_W-1:0]  b0_axi_bresp;
  logic [PEM_PC-1:0]                   b0_axi_bvalid;
  logic [PEM_PC-1:0]                   b0_axi_bready;

  generate
    for (genvar gen_p=0; gen_p<PEM_PC; gen_p=gen_p+1) begin : gen_in_fifo_loop
      fifo_element #(
        .WIDTH          (AXI4_RESP_W),
        .DEPTH          (1),
        .TYPE_ARRAY     (4'h3), // TOREVIEW
        .DO_RESET_DATA  (1'b0),
        .RESET_DATA_VAL (0)
      ) sm1_fifo_element (
        .clk     (clk),
        .s_rst_n (s_rst_n),

        .in_data (m_axi4_bresp[gen_p]),
        .in_vld  (m_axi4_bvalid[gen_p]),
        .in_rdy  (m_axi4_bready[gen_p]),

        .out_data(b0_axi_bresp[gen_p]),
        .out_vld (b0_axi_bvalid[gen_p]),
        .out_rdy (b0_axi_bready[gen_p])
      );
    end
  endgenerate


  //== command
  pem_cmd_t              sm2_cmd;
  logic                  sm2_cmd_vld;
  logic                  sm2_cmd_rdy;
  logic [AXI4_ADD_W-1:0] sm2_cmd_add_init;

  fifo_reg #(
    .WIDTH       (PEM_CMD_W),
    .DEPTH       (INST_FIFO_DEPTH-2),
    .LAT_PIPE_MH ({1'b1, 1'b1})
  ) in_ld_fifo_reg (
    .clk      (clk),
    .s_rst_n  (s_rst_n),

    .in_data  (cmd),
    .in_vld   (cmd_vld),
    .in_rdy   (cmd_rdy),

    .out_data (sm2_cmd),
    .out_vld  (sm2_cmd_vld),
    .out_rdy  (sm2_cmd_rdy)
  );

  assign sm2_cmd_add_init = sm2_cmd.cid * CT_MEM_BYTES;

  // Fork between the AXI and regf requests
  logic [PEM_PC:0] sm2_cmd_req_vld;
  logic [PEM_PC:0] sm2_cmd_req_rdy;

  assign sm2_cmd_rdy = &sm2_cmd_req_rdy;

  always_comb
    for (int i=0; i<PEM_PC+1; i=i+1) begin
      logic [PEM_PC:0] mask;
      mask = 1 << i;
      sm2_cmd_req_vld[i] = sm2_cmd_vld & (&(sm2_cmd_req_rdy | mask));
    end

  // Compute Memory initial address

  pem_cmd_t [PEM_PC:0]                 s0_cmd;
  logic     [PEM_PC:0][AXI4_ADD_W-1:0] s0_cmd_add_init;
  logic     [PEM_PC:0]                 s0_cmd_vld;
  logic     [PEM_PC:0]                 s0_cmd_rdy;

  logic     [PEM_PC_MAX:0][AXI4_ADD_W-1:0] ct_mem_addr_ext;

  assign ct_mem_addr_ext = ct_mem_addr; // extend non existing PC with 0s.

  generate
    for (genvar gen_i=0; gen_i<PEM_PC+1; gen_i=gen_i+1) begin : gen_cmd_loop
      pem_cmd_t              sm1_cmd;
      logic                  sm1_cmd_vld;
      logic                  sm1_cmd_rdy;
      logic [AXI4_ADD_W-1:0] sm1_cmd_add_init;
      logic [AXI4_ADD_W-1:0] sm1_cmd_add_init_tmp;

      assign sm1_cmd_add_init_tmp = sm1_cmd_add_init + ct_mem_addr_ext[gen_i];

      fifo_element #(
        .WIDTH          (AXI4_ADD_W+PEM_CMD_W),
        .DEPTH          (1),
        .TYPE_ARRAY     (4'h3), // TOREVIEW
        .DO_RESET_DATA  (1'b0),
        .RESET_DATA_VAL (0)
      ) sm2_fifo_element (
        .clk     (clk),
        .s_rst_n (s_rst_n),

        .in_data ({sm2_cmd_add_init,sm2_cmd}),
        .in_vld  (sm2_cmd_req_vld[gen_i]),
        .in_rdy  (sm2_cmd_req_rdy[gen_i]),

        .out_data({sm1_cmd_add_init,sm1_cmd}),
        .out_vld (sm1_cmd_vld),
        .out_rdy (sm1_cmd_rdy)
      );

      fifo_element #(
        .WIDTH          (AXI4_ADD_W+PEM_CMD_W),
        .DEPTH          (1),
        .TYPE_ARRAY     (4'h3), // TOREVIEW
        .DO_RESET_DATA  (1'b0),
        .RESET_DATA_VAL (0)
      ) sm1_fifo_element (
        .clk     (clk),
        .s_rst_n (s_rst_n),

        .in_data ({sm1_cmd_add_init_tmp,sm1_cmd}),
        .in_vld  (sm1_cmd_vld),
        .in_rdy  (sm1_cmd_rdy),

        .out_data({s0_cmd_add_init[gen_i],s0_cmd[gen_i]}),
        .out_vld (s0_cmd_vld[gen_i]),
        .out_rdy (s0_cmd_rdy[gen_i])
      );

    end
  endgenerate

  // for the regf request
  pem_cmd_t c0_cmd;
  logic     c0_cmd_vld;
  logic     c0_cmd_rdy;

  assign c0_cmd             = s0_cmd[PEM_PC];
  assign c0_cmd_vld         = s0_cmd_vld[PEM_PC];
  assign s0_cmd_rdy[PEM_PC] = c0_cmd_rdy;

// ============================================================================================== --
// For each PC
// ============================================================================================== --
// Data from regf after dispatch
  logic [PEM_PC-1:0][REGF_SEQ_COEF_NB-1:0][MOD_Q_W-1:0] r0_data;
  logic [PEM_PC-1:0]                                    r0_data_avail;
  logic [PEM_PC-1:0]                                    r0_data_last;

  logic [PEM_PC-1:0]                                    brsp_ack;
  logic [PEM_PC-1:0]                                    brsp_ackD;

  logic [PEM_PC-1:0]                                    r1_fifo_inc;

  generate
    for (genvar gen_p=0; gen_p<PEM_PC; gen_p = gen_p+1) begin : gen_pc_req_loop
      // Additional word to sent for PC=0 => body coef.
      localparam int AXI4_WORD_PER_PC_L    = (gen_p == 0) ? AXI4_WORD_PER_PC0 : AXI4_WORD_PER_PC;
      localparam int AXI4_WORD_PER_PC_W_L  = (gen_p == 0) ? AXI4_WORD_PER_PC0_W : AXI4_WORD_PER_PC_W;
      localparam int AXI4_WORD_PER_PC_WW_L = (gen_p == 0) ? AXI4_WORD_PER_PC0_WW : AXI4_WORD_PER_PC_WW;

// ============================================================================================== --
// AXI request
// ============================================================================================== --
      //-------------------------------------
      // Signals
      //-------------------------------------
      //== Request done
      logic        req_done;

      //== AXI interface
      axi4_aw_if_t s0_axi;
      logic        s0_axi_awvalid;
      logic        s0_axi_awready;

      //== Reception FIFO
      rcp_cmd_t    rcp_fifo_in_cmd;
      logic        rcp_fifo_in_vld;
      logic        rcp_fifo_in_rdy;

      //== Bresp FIFO
      brsp_cmd_t   brsp_fifo_in_cmd;
      logic        brsp_fifo_in_vld;
      logic        brsp_fifo_in_rdy;

      //-------------------------------------
      // Counters
      //-------------------------------------
      logic [AXI4_WORD_PER_PC_WW_L-1:0] req_axi_word_remain; // counts from AXI4_WORD_PER_PC_L included to 0 - decremented
      logic [AXI4_WORD_PER_PC_WW_L-1:0] req_axi_word_remainD;

      logic [AXI4_LEN_W:0]              req_axi_word_nb; // = axi_len + 1. The size AXI4_LEN_W+1 correspond to the axi bus size +1
      logic                             req_last_axi_word_remain;

      logic                             req_pbs_first_burst;
      logic                             req_pbs_first_burstD;

      logic [AXI_BURST_NB_MAX_W-1:0]    req_burst_cnt_m1;
      logic [AXI_BURST_NB_MAX_W-1:0]    req_burst_cnt_m1D;

      logic                             req_send_axi_cmd;

      assign req_axi_word_remainD     = req_send_axi_cmd ? req_last_axi_word_remain ? AXI4_WORD_PER_PC_L : req_axi_word_remain - req_axi_word_nb : req_axi_word_remain;
      assign req_last_axi_word_remain = req_axi_word_remain == req_axi_word_nb;
      assign req_pbs_first_burstD     = req_send_axi_cmd ? req_last_axi_word_remain ? 1'b1 : 1'b0 : req_pbs_first_burst;
      assign req_burst_cnt_m1D        = req_send_axi_cmd ? req_last_axi_word_remain ? '0 : req_burst_cnt_m1 + 1 : req_burst_cnt_m1;

      always_ff @(posedge clk)
        if (!s_rst_n) begin
          req_axi_word_remain <= AXI4_WORD_PER_PC_L;
          req_pbs_first_burst <= 1'b1;
          req_burst_cnt_m1    <= '0;
        end
        else begin
          req_axi_word_remain <= req_axi_word_remainD;
          req_pbs_first_burst <= req_pbs_first_burstD;
          req_burst_cnt_m1    <= req_burst_cnt_m1D;
        end

      //-------------------------------------
      // Address
      //-------------------------------------
      logic [AXI4_ADD_W-1:0]    req_add;
      logic [AXI4_ADD_W-1:0]    req_addD;
      logic [AXI4_ADD_W-1:0]    req_add_start;
      logic [PAGE_BYTES_WW-1:0] req_page_word_remain;

      assign req_add_start = req_pbs_first_burst ? s0_cmd_add_init[gen_p] : req_add;
      assign req_addD      = req_send_axi_cmd ? req_add_start + req_axi_word_nb*AXI4_DATA_BYTES : req_add;

      always_ff @(posedge clk)
        if (!s_rst_n) req_add <= '0;
        else          req_add <= req_addD;

      assign req_page_word_remain = PAGE_AXI4_DATA - req_add_start[PAGE_BYTES_W-1:AXI4_DATA_BYTES_W];
      assign req_axi_word_nb = req_page_word_remain < req_axi_word_remain ? req_page_word_remain : req_axi_word_remain;
      assign s0_axi.awid     = BLWE_AXI_ARID;
      assign s0_axi.awsize   = AXI4_DATA_BYTES_W;
      assign s0_axi.awburst  = AXI4B_INCR;
      assign s0_axi.awaddr   = req_add_start;
      assign s0_axi.awlen    = req_axi_word_nb - 1;
      assign s0_axi_awvalid  = s0_cmd_vld[gen_p] & (~req_pbs_first_burst | rcp_fifo_in_rdy) & (~req_last_axi_word_remain | brsp_fifo_in_rdy);

      assign req_done   = req_send_axi_cmd & req_last_axi_word_remain;
      assign s0_cmd_rdy[gen_p] = req_done;

    // pragma translate_off
      always_ff @(posedge clk)
        if (s0_axi_awvalid)
          assert(s0_axi.awlen <= AXI4_LEN_MAX)
          else begin
            $fatal(1,"%t > ERROR: AXI4 len overflow. Should not exceed %0d. Seen %0d",$time, AXI4_LEN_MAX, s0_axi.awlen);
          end
    // pragma translate_on

      //---------------------------------
      // to AXI write request
      //---------------------------------
      axi4_aw_if_t m_axi4_aw;

      assign m_axi4_awid[gen_p]    = m_axi4_aw.awid   ;
      assign m_axi4_awaddr[gen_p]  = m_axi4_aw.awaddr ;
      assign m_axi4_awlen[gen_p]   = m_axi4_aw.awlen  ;
      assign m_axi4_awsize[gen_p]  = m_axi4_aw.awsize ;
      assign m_axi4_awburst[gen_p] = m_axi4_aw.awburst;

      fifo_element #(
        .WIDTH          ($bits(axi4_aw_if_t)),
        .DEPTH          (1),
        .TYPE_ARRAY     (4'h3),
        .DO_RESET_DATA  (1'b0),
        .RESET_DATA_VAL (0)
      ) fifo_element_a0 (
        .clk     (clk),
        .s_rst_n (s_rst_n),

        .in_data (s0_axi),
        .in_vld  (s0_axi_awvalid),
        .in_rdy  (s0_axi_awready),

        .out_data(m_axi4_aw),
        .out_vld (m_axi4_awvalid[gen_p]),
        .out_rdy (m_axi4_awready[gen_p])
      );

      assign req_send_axi_cmd = s0_axi_awvalid & s0_axi_awready;

      //---------------------------------
      // to Reception FIFO
      //---------------------------------
      // Store the number of words of the first burst of the BLWE
      rcp_cmd_t rcp_fifo_out_cmd;
      logic     rcp_fifo_out_vld;
      logic     rcp_fifo_out_rdy;

      assign rcp_fifo_in_cmd.len = req_axi_word_nb - 1;
      assign rcp_fifo_in_vld     = s0_cmd_vld[gen_p] & req_pbs_first_burst & s0_axi_awready & (~req_last_axi_word_remain | brsp_fifo_in_rdy);

      fifo_reg #(
        .WIDTH       (RCP_CMD_W),
        .DEPTH       (RCP_FIFO_DEPTH),
        .LAT_PIPE_MH ({1'b1, 1'b1})
      ) rcp_fifo_reg (
        .clk      (clk),
        .s_rst_n  (s_rst_n),

        .in_data  (rcp_fifo_in_cmd),
        .in_vld   (rcp_fifo_in_vld),
        .in_rdy   (rcp_fifo_in_rdy),

        .out_data (rcp_fifo_out_cmd),
        .out_vld  (rcp_fifo_out_vld),
        .out_rdy  (rcp_fifo_out_rdy)
      );

      //---------------------------------
      // to Bresp FIFO
      //---------------------------------
      // Store the number of bursts
      brsp_cmd_t brsp_fifo_out_cmd;
      logic      brsp_fifo_out_vld;
      logic      brsp_fifo_out_rdy;

      assign brsp_fifo_in_cmd.burst_cnt_m1 = req_burst_cnt_m1;
      assign brsp_fifo_in_vld              = s0_cmd_vld[gen_p] & req_last_axi_word_remain & s0_axi_awready & (~req_pbs_first_burst | rcp_fifo_in_rdy);

      fifo_reg #(
        .WIDTH       (BRSP_CMD_W),
        .DEPTH       (BRSP_FIFO_DEPTH),
        .LAT_PIPE_MH ({1'b1, 1'b1}) // WARNING: BRSP_SEEN_CNT_MAX depends on this value
      ) brsp_fifo_reg (
        .clk      (clk),
        .s_rst_n  (s_rst_n),

        .in_data  (brsp_fifo_in_cmd),
        .in_vld   (brsp_fifo_in_vld),
        .in_rdy   (brsp_fifo_in_rdy),

        .out_data (brsp_fifo_out_cmd),
        .out_vld  (brsp_fifo_out_vld),
        .out_rdy  (brsp_fifo_out_rdy)
      );

      assign pem_st_infoD_tmp.rcp_fifo_in_rdy[gen_p] = rcp_fifo_in_rdy;
      assign pem_st_infoD_tmp.rcp_fifo_in_vld[gen_p] = rcp_fifo_in_vld;
      assign pem_st_infoD_tmp.brsp_fifo_in_rdy[gen_p] = brsp_fifo_in_rdy;
      assign pem_st_infoD_tmp.brsp_fifo_in_vld[gen_p] = brsp_fifo_in_vld;

// ============================================================================================== --
// Data format
// ============================================================================================== --
      logic [BLWE_COEF_PER_AXI4_WORD-1:0][MOD_Q_W-1:0] r1_axi_data;
      logic                                            r1_axi_vld;
      logic                                            r1_axi_rdy;

      //= Reorg AXI input data
      if (REGF_SEQ_COEF_NB >= BLWE_COEF_PER_AXI4_WORD) begin : gen_regf_seq_coef_nb_ge_blwe_coef_per_axi4_word
        localparam int CHK_NB      = REGF_SEQ_COEF_NB / BLWE_COEF_PER_AXI4_WORD;
        localparam int CHK_COEF_NB = BLWE_COEF_PER_AXI4_WORD;
        localparam int CHK_NB_W    = $clog2(CHK_NB) == 0 ? 1 : $clog2(CHK_NB);

        localparam int LAST_OUT_CNT_TMP = AXI4_WORD_PER_PC_L % CHK_NB;
        localparam int LAST_OUT_CNT     = LAST_OUT_CNT_TMP == 0 ? CHK_NB-1 : LAST_OUT_CNT_TMP-1;

        logic [CHK_NB-1:0][CHK_COEF_NB-1:0][MOD_Q_W-1:0] sr_data;
        logic [CHK_NB-1:0][CHK_COEF_NB-1:0][MOD_Q_W-1:0] sr_data_tmp;
        logic [CHK_NB-1:0][CHK_COEF_NB-1:0][MOD_Q_W-1:0] sr_dataD;

        logic [CHK_NB_W-1:0]                             sr_out_cnt;
        logic [CHK_NB_W-1:0]                             sr_out_cntD;
        logic                                            sr_last_out_cnt;
        logic                                            sr_avail;
        logic                                            sr_availD;

        logic                                            r1_data_last;
        logic                                            r1_data_lastD;

        // Handle case when there are several sequences per PC
        // Use a buffer to receive the data.
        logic [REGF_SEQ_COEF_NB-1:0][MOD_Q_W-1:0]        buf_data_l;
        logic                                            buf_data_l_avail;
        logic                                            buf_data_l_last;
        if (SEQ_PER_PC > 1) begin : gen_seq_per_pc_gt_1
          // Need to bufferize
          logic [SEQ_PER_PC-2:0][REGF_SEQ_COEF_NB-1:0][MOD_Q_W-1:0] buf_data;
          logic [SEQ_PER_PC-2:0][REGF_SEQ_COEF_NB-1:0][MOD_Q_W-1:0] buf_dataD;
          logic [SEQ_PER_PC-1:0][REGF_SEQ_COEF_NB-1:0][MOD_Q_W-1:0] buf_dataD_tmp;
          logic [SEQ_PER_PC-2:0]                                    buf_last;
          logic [SEQ_PER_PC-2:0]                                    buf_lastD;
          logic [SEQ_PER_PC-1:0]                                    buf_lastD_tmp;

          logic [SEQ_PER_PC-1:0][REGF_SEQ_COEF_NB-1:0][MOD_Q_W-1:0] buf_data_ext;
          logic [SEQ_PER_PC-1:0]                                    buf_last_ext;

          logic [SEQ_PER_PC_W-1:0] buf_wp;
          logic [SEQ_PER_PC_W-1:0] buf_wpD;
          logic                    buf_empty;
          logic                    buf_rden;
          logic                    buf_wren;

          assign buf_data_ext = buf_data; // Extend to avoid warnings
          assign buf_last_ext = buf_last; //  "

          assign buf_empty = buf_wp == 0;
          assign buf_wpD   = buf_wren && !buf_rden ? buf_wp + 1 :
                             !buf_wren && buf_rden ? buf_wp - 1 : buf_wp;

          always_comb
            for (int i=0; i<SEQ_PER_PC; i=i+1) begin
              buf_dataD_tmp[i] = (buf_wren && (buf_wp == i)) ? r0_data[gen_p] : buf_data_ext[i];
              buf_lastD_tmp[i] = (buf_wren && (buf_wp == i)) ? r0_data_last[gen_p] : buf_last_ext[i];
            end

          assign buf_dataD = buf_rden ? buf_dataD_tmp[SEQ_PER_PC-1:1] // complete with 0s
                                      : buf_dataD_tmp[SEQ_PER_PC-2:0];

          assign buf_lastD = buf_rden ? buf_lastD_tmp[SEQ_PER_PC-1:1] // complete with 0s
                                      : buf_lastD_tmp[SEQ_PER_PC-2:0];

          assign buf_wren = r0_data_avail[gen_p];
          assign buf_rden = (~sr_avail | (r1_axi_rdy & sr_last_out_cnt)) & ~buf_empty;

          assign buf_data_l       = buf_data[0];
          assign buf_data_l_avail = buf_rden;
          assign buf_data_l_last  = buf_last[0];

          always_ff @(posedge clk)
            if (!s_rst_n) buf_wp <= '0;
            else          buf_wp <= buf_wpD;

          always_ff @(posedge clk) begin
            buf_data <= buf_dataD;
            buf_last <= buf_lastD;
          end
// pragma translate_off
        // Check that the sr is ready to reveive the input data
        always_ff @(posedge clk)
          if (!s_rst_n) begin
            // do nothing
          end
          else begin
            if (buf_wren) begin
              assert( buf_wp < (SEQ_PER_PC-1) | buf_rden)
              else begin
                $fatal(1, "%t> ERROR: Shift register not ready to accept input data! Overflow! (PC=%0d)",$time, gen_p);
              end
            end
          end
// pragma translate_on

        end
        else begin : gen_seq_per_pc_le_1
          assign buf_data_l       = r0_data[gen_p];
          assign buf_data_l_avail = r0_data_avail[gen_p];
          assign buf_data_l_last  = r0_data_last[gen_p];
// pragma translate_off
        // Check that the sr is ready to reveive the input data
        always_ff @(posedge clk)
          if (!s_rst_n) begin
            // do nothing
          end
          else begin
            if (buf_data_l_avail) begin
              assert( ~sr_avail | (r1_axi_rdy & sr_last_out_cnt))
              else begin
                $fatal(1, "%t> ERROR: Shift register not ready to accept input data! Overflow! (PC=%0d)",$time, gen_p);
              end
            end
          end
// pragma translate_on
        end

        assign sr_data_tmp = sr_data >> (MOD_Q_W * CHK_COEF_NB);
        assign sr_dataD = buf_data_l_avail ? buf_data_l :
                          //r1_axi_vld && r1_axi_rdy ? {sr_data[CHK_NB-1],sr_data[CHK_NB-1:1]} : sr_data;
                          r1_axi_vld && r1_axi_rdy ? sr_data_tmp : sr_data; // To avoid warning - when this branch of the generate is not used.

        assign sr_out_cntD     = r1_axi_vld && r1_axi_rdy ? sr_last_out_cnt ? '0 : sr_out_cnt + 1 : sr_out_cnt;
        assign sr_last_out_cnt = (sr_out_cnt == CHK_NB-1) | (r1_data_last & sr_out_cnt == LAST_OUT_CNT);
        assign sr_availD       = buf_data_l_avail ? 1'b1 :
                                 r1_axi_vld && r1_axi_rdy && sr_last_out_cnt ? 1'b0 : sr_avail;

        assign r1_axi_vld  = sr_avail;
        assign r1_axi_data = sr_data[0];

        always_ff @(posedge clk)
          if (!s_rst_n) begin
            sr_out_cnt <= '0;
            sr_avail   <= 1'b0;
          end
          else begin
            sr_out_cnt <= sr_out_cntD;
            sr_avail   <= sr_availD;
          end

        always_ff @(posedge clk)
          sr_data <= sr_dataD;

        assign r1_data_lastD = buf_data_l_avail ? buf_data_l_last : r1_data_last;

        always_ff @(posedge clk)
          r1_data_last <= r1_data_lastD;

      end // gen_regf_seq_coef_nb_ge_blwe_coef_per_axi4_word
      else begin : gen_regf_seq_coef_nb_lt_blwe_coef_per_axi4_word
        // REGF seq words are accumulated until a AXI4 word is complete
        localparam int CHK_NB      = BLWE_COEF_PER_AXI4_WORD / REGF_SEQ_COEF_NB;
        localparam int CHK_COEF_NB = REGF_SEQ_COEF_NB;
        localparam int CHK_NB_W    = $clog2(CHK_NB) == 0 ? 1 : $clog2(CHK_NB);

        logic [CHK_NB-1:1][CHK_COEF_NB-1:0][MOD_Q_W-1:0] acc_data;
        logic [CHK_NB-1:1][CHK_COEF_NB-1:0][MOD_Q_W-1:0] acc_dataD;

        logic [CHK_NB_W-1:0]                             acc_in_cnt;
        logic [CHK_NB_W-1:0]                             acc_in_cntD;
        logic                                            acc_last_in_cnt;

        assign acc_in_cntD     = r0_data_avail[gen_p] ? acc_last_in_cnt ? '0 : acc_in_cnt + 1 : acc_in_cnt;
        assign acc_last_in_cnt = r0_data_last[gen_p] | (acc_in_cnt == (CHK_NB-1));

        if (CHK_NB > 2) begin
          assign acc_dataD   = r0_data_avail[gen_p] ? {r0_data[gen_p], acc_data[CHK_NB-1:2]} : acc_data;
        end
        else begin
          assign acc_dataD   = r0_data_avail[gen_p] ? {r0_data[gen_p]} : acc_data;
        end
        // gen_p==0, we deal with the body. This latter is the last AXI word to be transfered, and it is alone in its AXI word.
        assign r1_axi_data = (r0_data_last[gen_p] && (gen_p == 0)) ? {CHK_NB{r0_data[gen_p]}} : {r0_data[gen_p], acc_data};
        assign r1_axi_vld  = r0_data_avail[gen_p] & acc_last_in_cnt;

        always_ff @(posedge clk)
          if (!s_rst_n) acc_in_cnt <= '0;
          else          acc_in_cnt <= acc_in_cntD;

        always_ff @(posedge clk)
          acc_data <= acc_dataD;

// pragma translate_off
        always_ff @(posedge clk)
          if (!s_rst_n) begin
            // Do nothing
          end
          else begin
            if (r0_data_avail[gen_p]) begin
              assert(!acc_last_in_cnt || r1_axi_rdy)
              else begin
                $fatal(1,"%t > ERROR: Not ready to accumulate input data. Overflow!",$time);
              end
            end
          end
// pragma translate_on
      end // gen_regf_seq_coef_nb_lt_blwe_coef_per_axi4_word

      //-------------------------
      // Fifo data
      //-------------------------
      logic [BLWE_COEF_PER_AXI4_WORD-1:0][MOD_Q_W-1:0] r2_axi_data;
      logic                                            r2_axi_vld;
      logic                                            r2_axi_rdy;

      assign r1_fifo_inc[gen_p] = r2_axi_vld & r2_axi_rdy;

      fifo_reg #(
        .WIDTH       (BLWE_COEF_PER_AXI4_WORD*MOD_Q_W),
        .DEPTH       (DATA_FIFO_DEPTH),
        .LAT_PIPE_MH ({1'b1, 1'b1})
      ) r1_fifo_reg (
        .clk      (clk),
        .s_rst_n  (s_rst_n),

        .in_data  (r1_axi_data),
        .in_vld   (r1_axi_vld),
        .in_rdy   (r1_axi_rdy),

        .out_data (r2_axi_data),
        .out_vld  (r2_axi_vld),
        .out_rdy  (r2_axi_rdy)
      );

      //-------------------------
      // AXI data
      //-------------------------
      //== Counters
      logic [AXI4_WORD_PER_PC_W_L-1:0] r2_word; // counts AXI words per BLWE
      logic [AXI4_LEN_W-1:0]           r2_burst_word; // counts the AXI words within a burst
      logic [AXI4_WORD_PER_PC_W_L-1:0] r2_wordD;
      logic [AXI4_LEN_W-1:0]           r2_burst_wordD;

      logic                            r2_last_word;
      logic                            r2_last_burst_word;

      logic                            r2_first_burst;
      logic                            r2_first_burstD;
      logic [AXI4_LEN_W-1:0]           r2_burst_word_max;

      logic                            r2_send_axi;

      assign r2_wordD           = r2_send_axi ? r2_last_word ? '0 : r2_word + 1 : r2_word;
      assign r2_burst_wordD     = r2_send_axi ? r2_last_burst_word ? '0 : r2_burst_word + 1 : r2_burst_word;
      assign r2_first_burstD    = (r2_send_axi && r2_last_burst_word) ? r2_last_word ? 1'b1 : 1'b0 : r2_first_burst;
      assign r2_last_word       = r2_word == AXI4_WORD_PER_PC_L-1;
      assign r2_burst_word_max  = r2_first_burst ? rcp_fifo_out_cmd.len : AXI4_LEN_MAX;
      assign r2_last_burst_word = r2_last_word | (r2_burst_word == r2_burst_word_max);

      always_ff @(posedge clk)
        if (!s_rst_n) begin
          r2_burst_word <= '0;
          r2_word       <= '0;
          r2_first_burst<= 1'b1;
        end
        else begin
          r2_burst_word <= r2_burst_wordD;
          r2_word       <= r2_wordD      ;
          r2_first_burst<= r2_first_burstD;
        end

      //== AXI wdata
      axi4_w_if_t r2_axi_w;
      logic       r2_axi_wvalid;
      logic       r2_axi_wready;

      axi4_w_if_t m_axi4_w;

      always_comb
        for (int i=0; i<BLWE_COEF_PER_AXI4_WORD; i=i+1)
          r2_axi_w.wdata[i*BLWE_ACS_W+:BLWE_ACS_W] = r2_axi_data[i]; // Msb are completed with 0s

      assign r2_axi_w.wstrb = '1;
      assign r2_axi_w.wlast = r2_last_burst_word;
      assign r2_axi_wvalid  = r2_axi_vld & rcp_fifo_out_vld;

      assign rcp_fifo_out_rdy = r2_axi_wready & r2_axi_vld & r2_last_word;
      assign r2_axi_rdy       = r2_axi_wready & rcp_fifo_out_vld;

      assign r2_send_axi = r2_axi_wvalid & r2_axi_wready;

      fifo_element #(
        .WIDTH          (AXI4_W_IF_W),
        .DEPTH          (2),
        .TYPE_ARRAY     ({4'h1,4'h2}),
        .DO_RESET_DATA  (0),
        .RESET_DATA_VAL (0)
      ) fifo_element_r2 (
        .clk     (clk),
        .s_rst_n (s_rst_n),

        .in_data (r2_axi_w),
        .in_vld  (r2_axi_wvalid),
        .in_rdy  (r2_axi_wready),

        .out_data(m_axi4_w),
        .out_vld (m_axi4_wvalid[gen_p]),
        .out_rdy (m_axi4_wready[gen_p])
      );

      assign m_axi4_wdata[gen_p] = m_axi4_w.wdata;
      assign m_axi4_wstrb[gen_p] = m_axi4_w.wstrb;
      assign m_axi4_wlast[gen_p] = m_axi4_w.wlast;

      assign pem_st_infoD_tmp.r2_axi_vld[gen_p] = r2_axi_vld;
      assign pem_st_infoD_tmp.r2_axi_rdy[gen_p] = r2_axi_rdy;

// ============================================================================================== --
// AXI Bresp
// ============================================================================================== --
      // Counts the number of bresp received. Do not block the bresp path, since we don't know
      // its depth. If the GLWE is big, we may fill all the bresp path, before sending the last
      // burst.
      logic [BRSP_CNT_W-1:0]          brsp_bresp_cnt;
      logic [BRSP_CNT_W-1:0]          brsp_bresp_cntD;
      logic                           brsp_bresp_cnt_inc;
      logic                           brsp_bresp_cnt_dec;
      logic [AXI_BURST_NB_MAX_WW-1:0] brsp_bresp_cnt_dec_val;
      logic [AXI_BURST_NB_MAX_WW-1:0] brsp_bresp_cnt_dec_val_m1;
      logic                           brsp_bresp_cnt_full;

      assign b0_axi_bready[gen_p] = ~brsp_bresp_cnt_full;
      assign brsp_bresp_cnt_full  = brsp_bresp_cnt == {BRSP_CNT_W{1'b1}};
      assign brsp_bresp_cnt_inc   = b0_axi_bready[gen_p] & b0_axi_bvalid[gen_p];
      assign brsp_bresp_cntD      = brsp_bresp_cnt_inc  && !brsp_bresp_cnt_dec ? brsp_bresp_cnt + 1 :
                                    !brsp_bresp_cnt_inc && brsp_bresp_cnt_dec  ? brsp_bresp_cnt - brsp_bresp_cnt_dec_val :
                                    brsp_bresp_cnt_inc  && brsp_bresp_cnt_dec  ? brsp_bresp_cnt - brsp_bresp_cnt_dec_val_m1 :
                                    brsp_bresp_cnt;

      always_ff @(posedge clk)
        if (!s_rst_n) brsp_bresp_cnt <= '0;
        else          brsp_bresp_cnt <= brsp_bresp_cntD;

      // Counts the number of burst sent.
      // Should receive as many bresp as burst commands per BLWE.
      logic                          brsp_all_bresp_received;

      assign brsp_all_bresp_received   = (brsp_bresp_cnt > brsp_fifo_out_cmd.burst_cnt_m1);
      assign brsp_bresp_cnt_dec        = brsp_fifo_out_vld & brsp_all_bresp_received;
      assign brsp_bresp_cnt_dec_val_m1 = brsp_fifo_out_cmd.burst_cnt_m1;
      assign brsp_bresp_cnt_dec_val    = brsp_fifo_out_cmd.burst_cnt_m1 + 1;

      assign brsp_ackD[gen_p]    = brsp_fifo_out_vld & brsp_all_bresp_received;
      assign brsp_fifo_out_rdy   = brsp_all_bresp_received;

      assign pem_st_infoD_tmp.brsp_bresp_cnt[gen_p] = brsp_bresp_cnt;

// pragma translate_off
      always_ff @(posedge clk)
        if (!s_rst_n) begin
          // Do nothing
        end
        else begin
          if (brsp_fifo_out_rdy) begin
            assert(brsp_fifo_out_vld)
            else begin
              $fatal(1,"%t> ERROR: brsp fifo command needed, but is not available. Underflow!",$time);
            end
          end

          if (b0_axi_bvalid[gen_p] && b0_axi_bready[gen_p]) begin
            assert(b0_axi_bresp[gen_p] == AXI4_OKAY)
            else begin
              $fatal(1,"%t > ERROR: Something went wrong : Bresp is not OK.",$time);
            end
          end
        end
// pragma translate_on

    end
  endgenerate // for gen_p

// ============================================================================================== --
// Command ack
// ============================================================================================== --
  logic [PEM_PC-1:0][BRSP_SEEN_CNT_W-1:0] brsp_ack_seen;
  logic [PEM_PC-1:0][BRSP_SEEN_CNT_W-1:0] brsp_ack_seenD;
  logic                                   cmd_ackD;


  always_comb begin
    cmd_ackD = 1'b1;
    for (int i=0; i<PEM_PC; i=i+1)
      cmd_ackD = cmd_ackD & (brsp_ack_seen[i] > 0);
  end

  always_comb
    for (int i=0; i<PEM_PC; i=i+1)
      brsp_ack_seenD[i] = cmd_ackD && !brsp_ack[i] ? brsp_ack_seen[i] - 1:
                          !cmd_ackD && brsp_ack[i] ? brsp_ack_seen[i] + 1 : brsp_ack_seen[i];

  always_ff @(posedge clk)
    if (!s_rst_n)
      brsp_ack <= '0;
    else
      brsp_ack <= brsp_ackD;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      cmd_ack       <= 1'b0;
      brsp_ack_seen <= '0;
    end
    else begin
      cmd_ack       <= cmd_ackD;
      brsp_ack_seen <= brsp_ack_seenD;
    end

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      for (int i=0; i<PEM_PC; i=i+1) begin
        if (brsp_ack[i]) begin
          assert((brsp_ack_seen[i] < BRSP_SEEN_CNT_MAX) || cmd_ackD)
          else begin
            $fatal(1,"%t> ERROR: brsp_ack_seen counter [PC=%0d] overflow!",$time,i);
          end
        end
      end
    end
// pragma translate_on

// ============================================================================================== --
// REGF request
// ============================================================================================== --
  //-----------------------
  // Data FIFO filling counter
  //-----------------------
  // Counts that data that are present in the AXI data fifo.
  // If there are enough free location a regf read request is sent.
  logic [PEM_PC-1:0][DATA_CNT_W-1:0] c0_free_loc_cnt;
  logic [PEM_PC-1:0][DATA_CNT_W-1:0] c0_free_loc_cntD;

  logic [PEM_PC-1:0]                 c0_free_loc_cnt_dec;
  logic [DATA_CNT_W-1:0]             c0_free_loc_cnt_dec_val;

  generate
    for (genvar gen_i=0; gen_i<PEM_PC; gen_i=gen_i+1) begin : gen_pc_loop
      assign pem_st_infoD_tmp.brsp_ack_seen[gen_i] = brsp_ack_seen[gen_i];
      assign pem_st_infoD_tmp.c0_free_loc_cnt[gen_i] = c0_free_loc_cnt[gen_i];
    end
  endgenerate

  always_comb
    for (int i=0; i<PEM_PC; i=i+1) begin
      logic [DATA_CNT_W-1:0] dec;
      dec = c0_free_loc_cnt_dec_val & {DATA_CNT_W{c0_free_loc_cnt_dec[i]}};
      c0_free_loc_cntD[i] = c0_free_loc_cnt[i] - dec + r1_fifo_inc[i];
    end

  always_ff @(posedge clk)
    if (!s_rst_n)
      for (int i=0; i<PEM_PC; i=i+1)
        c0_free_loc_cnt[i] <= DATA_FIFO_DEPTH;
    else
        c0_free_loc_cnt <= c0_free_loc_cntD;

  //-----------------------
  // Request
  //-----------------------
  logic         c0_regf_req_vld;
  logic         c0_regf_req_rdy;
  regf_rd_req_t c0_regf_req;

  //== Counters
  logic [REGF_CMD_NB_W-1:0]         c0_cmd_cnt;
  logic [REGF_BLWE_WORD_CNT_W-1:0]  c0_word_add;

  logic [REGF_CMD_NB_W-1:0]         c0_cmd_cntD;
  logic [REGF_BLWE_WORD_CNT_W-1:0]  c0_word_addD;

  logic                             c0_rd_body;
  logic                             c0_rd_bodyD;

  logic                             c0_last_cmd_cnt;
  logic                             c0_send_cmd;

  assign c0_last_cmd_cnt = c0_cmd_cnt == REGF_CMD_NB - 1;
  assign c0_cmd_cntD     = c0_send_cmd ? c0_rd_body ? '0 : c0_cmd_cnt + 1 : c0_cmd_cnt;
  assign c0_word_addD    = c0_send_cmd ? c0_rd_body ? '0 : c0_last_cmd_cnt ? REGF_BLWE_WORD_PER_RAM : c0_word_add + REGF_WORD_THRESHOLD : c0_word_add;
  assign c0_rd_bodyD     = c0_send_cmd ? c0_last_cmd_cnt ? 1'b1 : 1'b0 : c0_rd_body;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      c0_cmd_cnt  <= '0;
      c0_word_add <= '0;
      c0_rd_body  <= 1'b0;
    end
    else begin
      c0_cmd_cnt  <= c0_cmd_cntD;
      c0_word_add <= c0_word_addD;
      c0_rd_body  <= c0_rd_bodyD;
    end

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // Do nothing
    end
    else begin
      if (c0_last_cmd_cnt)
        assert(c0_word_add + LAST_REGF_WORD_THRESHOLD == REGF_BLWE_WORD_PER_RAM)
        else begin
          $fatal(1,"%t > ERROR: Wrong address computed until the body exp=0x%0x seen=0x%0x+0x%0x.",$time,REGF_BLWE_WORD_PER_RAM, c0_word_add,LAST_REGF_WORD_THRESHOLD);
        end
    end
// pragma translate_on

  // check location availability
  logic [PEM_PC-1:0] c0_enough_location;

  always_comb begin
    c0_free_loc_cnt_dec[0] = c0_send_cmd;
    c0_enough_location[0]  = c0_rd_body ?  (c0_free_loc_cnt[0] > 0) : (c0_free_loc_cnt[0] >= DATA_THRESHOLD);
    for (int i=1; i<PEM_PC; i=i+1) begin
      c0_free_loc_cnt_dec[i] = c0_send_cmd & ~c0_rd_body;
      c0_enough_location[i]  = c0_rd_body | (c0_free_loc_cnt[i] >= DATA_THRESHOLD);
    end
  end

  assign c0_free_loc_cnt_dec_val = c0_rd_body      ? 1 :
                                   c0_last_cmd_cnt ? LAST_DATA_THRESHOLD :
                                                     DATA_THRESHOLD;

  assign c0_regf_req_vld        = c0_cmd_vld & (&c0_enough_location);
  assign c0_send_cmd            = c0_regf_req_vld & c0_regf_req_rdy;
  assign c0_regf_req.start_word = c0_word_add;
  assign c0_regf_req.word_nb_m1 = c0_rd_body ? '0 :
                                  c0_last_cmd_cnt ? LAST_REGF_WORD_THRESHOLD-1: REGF_WORD_THRESHOLD-1;
  assign c0_regf_req.reg_id     = c0_cmd.reg_id;
  assign c0_regf_req.do_2_read  = 1'b0;

  assign c0_cmd_rdy             = c0_regf_req_rdy & (&c0_enough_location) & c0_rd_body;

  //-----------------------
  // Output FIFO
  //-----------------------
  fifo_element #(
    .WIDTH          (REGF_RD_REQ_W),
    .DEPTH          (1),
    .TYPE_ARRAY     (4'h3), // TOREVIEW
    .DO_RESET_DATA  (0),
    .RESET_DATA_VAL (0)
  ) regf_req_fifo_element (
    .clk     (clk),
    .s_rst_n (s_rst_n),

    .in_data (c0_regf_req),
    .in_vld  (c0_regf_req_vld),
    .in_rdy  (c0_regf_req_rdy),

    .out_data(pem_regf_rd_req),
    .out_vld (pem_regf_rd_req_vld),
    .out_rdy (pem_regf_rd_req_rdy)
  );

// ============================================================================================== --
// REGF Data dispatch
// ============================================================================================== --
  // Dispatch the data from the regfile to all the PCs.
  logic [REGF_SEQ-1:0] regf_pem_rd_is_body_sr;
  logic [REGF_SEQ-1:0] regf_pem_rd_is_body_sr_tmp;
  logic [REGF_SEQ-1:0] regf_pem_rd_is_body_sr_tmpD;

  logic [REGF_SEQ-1:0] regf_pem_rd_last_mask_sr;
  logic [REGF_SEQ-1:0] regf_pem_rd_last_mask_sr_tmp;
  logic [REGF_SEQ-1:0] regf_pem_rd_last_mask_sr_tmpD;

  assign regf_pem_rd_is_body_sr           = regf_pem_rd_is_body_sr_tmpD;
  assign regf_pem_rd_last_mask_sr         = regf_pem_rd_last_mask_sr_tmpD;
  assign regf_pem_rd_is_body_sr_tmpD[0]   = regf_pem_rd_is_body & regf_pem_rd_data_avail[0];
  assign regf_pem_rd_last_mask_sr_tmpD[0] = regf_pem_rd_last_mask & regf_pem_rd_data_avail[0];

  generate
    if (REGF_SEQ > 1) begin : gen_regf_seq_gt_1
      assign regf_pem_rd_is_body_sr_tmpD[REGF_SEQ-1:1]   = regf_pem_rd_is_body_sr_tmp[REGF_SEQ-2:0];
      assign regf_pem_rd_last_mask_sr_tmpD[REGF_SEQ-1:1] = regf_pem_rd_last_mask_sr_tmp[REGF_SEQ-2:0];
    end
  endgenerate

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      regf_pem_rd_is_body_sr_tmp   <= '0;
      regf_pem_rd_last_mask_sr_tmp <= '0;
    end
    else begin
      regf_pem_rd_is_body_sr_tmp   <= regf_pem_rd_is_body_sr_tmpD;
      regf_pem_rd_last_mask_sr_tmp <= regf_pem_rd_last_mask_sr_tmpD;
    end
  generate
    for (genvar gen_p=0; gen_p<PEM_PC; gen_p=gen_p+1) begin : gen_data_dispatch_loop
      logic [SEQ_PER_PC-1:0][REGF_SEQ_COEF_NB-1:0]              regf_pem_rd_data_avail_l;
      logic [SEQ_PER_PC-1:0][REGF_SEQ_COEF_NB-1:0][MOD_Q_W-1:0] regf_pem_rd_data_l;
      logic [SEQ_PER_PC-1:0]                                    regf_pem_rd_is_body_sr_l;
      logic [SEQ_PER_PC-1:0]                                    regf_pem_rd_last_mask_sr_l;

      logic [REGF_SEQ_COEF_NB-1:0][MOD_Q_W-1:0]                 rm1_data;
      logic                                                     rm1_data_avail;
      logic                                                     rm1_data_last;

      logic [REGF_SEQ_COEF_NB-1:0][MOD_Q_W-1:0]                 r0_data_l;
      logic                                                     r0_data_avail_l;
      logic                                                     r0_data_last_l;

      logic [SEQ_PER_PC-1:0]                                    regf_pem_rd_data_avail_masked;

      assign regf_pem_rd_data_avail_l   = regf_pem_rd_data_avail[gen_p*SEQ_PER_PC*REGF_SEQ_COEF_NB+:SEQ_PER_PC*REGF_SEQ_COEF_NB];
      assign regf_pem_rd_data_l         = regf_pem_rd_data[gen_p*SEQ_PER_PC*REGF_SEQ_COEF_NB+:SEQ_PER_PC*REGF_SEQ_COEF_NB];
      assign regf_pem_rd_is_body_sr_l   = regf_pem_rd_is_body_sr[gen_p*SEQ_PER_PC+:SEQ_PER_PC];
      assign regf_pem_rd_last_mask_sr_l = regf_pem_rd_last_mask_sr[gen_p*SEQ_PER_PC+:SEQ_PER_PC];

      // The body is part of the first sequence.
      assign rm1_data_last = (gen_p == 0) ? regf_pem_rd_is_body_sr_l[0] : regf_pem_rd_last_mask_sr_l[SEQ_PER_PC-1];

      always_comb
        for (int s=0; s<SEQ_PER_PC; s=s+1)
          regf_pem_rd_data_avail_masked[s] = regf_pem_rd_data_avail_l[s][0] & ((gen_p==0 && s==0) | ~regf_pem_rd_is_body_sr_l[s]);

      assign rm1_data_avail = |regf_pem_rd_data_avail_masked;

      always_comb
        for (int i=0; i<REGF_SEQ_COEF_NB; i=i+1) begin
          rm1_data[i] = '0;
          for (int s=0; s<SEQ_PER_PC; s=s+1) begin
            rm1_data[i] = rm1_data[i] | (regf_pem_rd_data_l[s][i] & {MOD_Q_W{regf_pem_rd_data_avail_l[s][i]}});
          end
        end

      always_ff @(posedge clk)
        if (!s_rst_n) r0_data_avail_l <= 1'b0;
        else          r0_data_avail_l <= rm1_data_avail;

      always_ff @(posedge clk) begin
        r0_data_l      <= rm1_data;
        r0_data_last_l <= rm1_data_last;
      end

      assign r0_data[gen_p]       = r0_data_l;
      assign r0_data_avail[gen_p] = r0_data_avail_l;
      assign r0_data_last[gen_p]  = r0_data_last_l;

// pragma translate_off
      always_ff @(posedge clk)
        if (!s_rst_n) begin
          // do nothing
        end
        else begin
          assert($countones(regf_pem_rd_data_avail_masked) <= 1)
          else begin
            $fatal(1,"%t > ERROR: Several sequences valid at the same time for a PC[%0d]. This is not supported.",$time, gen_p);
          end
        end
// pragma translate_on
    end // for gen_p - data dispatch
  endgenerate

// ============================================================================================== --
// Info
// ============================================================================================== --
  pem_st_info_t pem_st_infoD;

  always_comb begin
    pem_st_infoD = '0;

    pem_st_infoD.rcp_fifo_in_rdy[PEM_PC-1:0] = pem_st_infoD_tmp.rcp_fifo_in_rdy[PEM_PC-1:0];
    pem_st_infoD.rcp_fifo_in_vld[PEM_PC-1:0] = pem_st_infoD_tmp.rcp_fifo_in_vld[PEM_PC-1:0];
    pem_st_infoD.brsp_fifo_in_rdy[PEM_PC-1:0]= pem_st_infoD_tmp.brsp_fifo_in_rdy[PEM_PC-1:0];
    pem_st_infoD.brsp_fifo_in_vld[PEM_PC-1:0]= pem_st_infoD_tmp.brsp_fifo_in_vld[PEM_PC-1:0];
    pem_st_infoD.r2_axi_vld[PEM_PC-1:0]      = pem_st_infoD_tmp.r2_axi_vld[PEM_PC-1:0];
    pem_st_infoD.r2_axi_rdy[PEM_PC-1:0]      = pem_st_infoD_tmp.r2_axi_rdy[PEM_PC-1:0];
    pem_st_infoD.brsp_bresp_cnt[PEM_PC-1:0]  = pem_st_infoD_tmp.brsp_bresp_cnt[PEM_PC-1:0];
    pem_st_infoD.brsp_ack_seen[PEM_PC-1:0]   = pem_st_infoD_tmp.brsp_ack_seen[PEM_PC-1:0];
    pem_st_infoD.c0_free_loc_cnt[PEM_PC-1:0] = pem_st_infoD_tmp.c0_free_loc_cnt[PEM_PC-1:0];

    pem_st_infoD.s0_cmd_vld          = s0_cmd_vld;
    pem_st_infoD.s0_cmd_rdy          = s0_cmd_rdy;
    pem_st_infoD.c0_cmd_cnt          = c0_cmd_cnt;
    pem_st_infoD.c0_enough_location  = c0_enough_location;
    pem_st_infoD.m_axi4_awready      = m_axi4_awready;
    pem_st_infoD.m_axi4_awvalid      = m_axi4_awvalid;
    pem_st_infoD.m_axi4_wready       = m_axi4_wready;
    pem_st_infoD.m_axi4_wvalid       = m_axi4_wvalid;
    pem_st_infoD.m_axi4_bready       = m_axi4_bready;
    pem_st_infoD.m_axi4_bvalid       = m_axi4_bvalid;
    pem_st_infoD.pem_regf_rd_req_rdy = pem_regf_rd_req_rdy;
    pem_st_infoD.pem_regf_rd_req_vld = pem_regf_rd_req_vld;
    pem_st_infoD.cmd_rdy             = cmd_rdy;
    pem_st_infoD.cmd_vld             = cmd_vld;
  end

  always_ff @(posedge clk)
    if (!s_rst_n) pem_st_info <= '0;
    else          pem_st_info <= pem_st_infoD;

endmodule
