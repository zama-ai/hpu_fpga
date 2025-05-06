// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module is a processing element (PE) of the HPU.
// It deals with the loading of BLWE from the memory (DDR or HBM) into
// the register_file.
// ==============================================================================================

module pem_load
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
  // write
  output logic                                   pem_regf_wr_req_vld,
  input  logic                                   pem_regf_wr_req_rdy,
  output logic [REGF_WR_REQ_W-1:0]               pem_regf_wr_req,

  output logic [REGF_COEF_NB-1:0]                pem_regf_wr_data_vld,
  input  logic [REGF_COEF_NB-1:0]                pem_regf_wr_data_rdy,
  output logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0]   pem_regf_wr_data,

  input  logic                                   regf_pem_wr_ack,

  // AXI4 interface
  // Read channel
  output logic [PEM_PC-1:0][AXI4_ID_W-1:0]       m_axi4_arid,
  output logic [PEM_PC-1:0][AXI4_ADD_W-1:0]      m_axi4_araddr,
  output logic [PEM_PC-1:0][AXI4_LEN_W-1:0]      m_axi4_arlen,
  output logic [PEM_PC-1:0][AXI4_SIZE_W-1:0]     m_axi4_arsize,
  output logic [PEM_PC-1:0][AXI4_BURST_W-1:0]    m_axi4_arburst,
  output logic [PEM_PC-1:0]                      m_axi4_arvalid,
  input  logic [PEM_PC-1:0]                      m_axi4_arready,
  input  logic [PEM_PC-1:0][AXI4_ID_W-1:0]       m_axi4_rid,
  input  logic [PEM_PC-1:0][AXI4_DATA_W-1:0]     m_axi4_rdata,
  input  logic [PEM_PC-1:0][AXI4_RESP_W-1:0]     m_axi4_rresp,
  input  logic [PEM_PC-1:0]                      m_axi4_rlast,
  input  logic [PEM_PC-1:0]                      m_axi4_rvalid,
  output logic [PEM_PC-1:0]                      m_axi4_rready,

  output pem_ld_info_t                           pem_ld_info
);

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int RCP_FIFO_DEPTH  = 8; // TOREVIEW : according to memory latency.
  localparam int DATA_FIFO_DEPTH = 16*REGF_COEF_PER_URAM_WORD; // TOREVIEW
  localparam int DATA_THRESHOLD  = 8*REGF_COEF_PER_URAM_WORD; // Should be less or equal to DATA_FIFO_DEPTH
                                                              // Should be a multiple of REGF_COEF_PER_URAM_WORD
  localparam int REGF_WORD_THRESHOLD   = DATA_THRESHOLD / REGF_COEF_PER_URAM_WORD;

  localparam int DATA_CNT_W            = $clog2(DATA_FIFO_DEPTH+1)==0 ? 1 : $clog2(DATA_FIFO_DEPTH+1); // Counts from 0 to DATA_FIFO_DEPTH included

  localparam int REGF_CMD_NB           = ((REGF_BLWE_WORD_PER_RAM+1) + REGF_WORD_THRESHOLD - 1) / REGF_WORD_THRESHOLD;
  localparam int REGF_CMD_NB_W         = $clog2(REGF_CMD_NB) == 0 ? 1 : $clog2(REGF_CMD_NB);
  localparam int REGF_LAST_CMD_WORD_NB = (REGF_BLWE_WORD_PER_RAM+1) % REGF_WORD_THRESHOLD;

  localparam int SUBW_COEF_NB          = (REGF_COEF_PER_PC < BLWE_COEF_PER_AXI4_WORD)? REGF_COEF_PER_PC : BLWE_COEF_PER_AXI4_WORD;
  localparam int SUBW_PER_AXI4_WORD    = (BLWE_COEF_PER_AXI4_WORD / SUBW_COEF_NB);
  localparam int SUBW_PER_REGF_PC      = (REGF_COEF_PER_PC / SUBW_COEF_NB);
  localparam int SUBW_PER_REGF_PC_W    = $clog2(SUBW_PER_REGF_PC) == 0 ? 1 : $clog2(SUBW_PER_REGF_PC);
  localparam int SUBW_PER_AXI4_WORD_W  = $clog2(SUBW_PER_AXI4_WORD) == 0 ? 1 : $clog2(SUBW_PER_AXI4_WORD);

  // On the data part, PCO will received the AXI word containing the body.
  // Concerning the other PCs, a fake word is created.
  // Therefore, the count here takes into account the word for the body, for all PCs.
  localparam int TOTAL_SUBW_NB         = (BLWE_K_P1 + SUBW_COEF_NB-1) / SUBW_COEF_NB;
  localparam int TOTAL_SUBW_NB_W       = $clog2(TOTAL_SUBW_NB) == 0 ? 1 : $clog2(TOTAL_SUBW_NB);

  // Check
  generate
    if ((AXI4_WORD_PER_BLWE/PEM_PC) * PEM_PC != AXI4_WORD_PER_BLWE) begin : __UNSUPPORTED_PEM_PC_
      $fatal(1,"ERROR> Unsupported PEM_PC (%0d). Must divide AXI4_WORD_PER_BLWE(%0d).", PEM_PC, AXI4_WORD_PER_BLWE);
    end
    if ((DATA_THRESHOLD % REGF_COEF_PER_URAM_WORD) != 0) begin : __UNSUPPORTED_DATA_THRESHOLD_
      $fatal(1,"> ERROR: DATA_THRESHOLD (%0d) should be a multiple of REGF_COEF_PER_URAM_WORD (%0d)", DATA_THRESHOLD, REGF_COEF_PER_URAM_WORD);
    end
  endgenerate

// pragma translate_off
  initial begin
    $display("> INFO: PEM_LD : REGF_BLWE_WORD_PER_RAM=%0d",REGF_BLWE_WORD_PER_RAM);
    $display("> INFO: PEM_LD : REGF_WORD_THRESHOLD=%0d",REGF_WORD_THRESHOLD);
    $display("> INFO: PEM_LD : REGF_CMD_NB=%0d",REGF_CMD_NB);
    $display("> INFO: PEM_LD : SUBW_PER_AXI4_WORD=%0d",SUBW_PER_AXI4_WORD);
    $display("> INFO: PEM_LD : SUBW_COEF_NB=%0d",SUBW_COEF_NB);
    $display("> INFO: PEM_LD : SUBW_PER_REGF_PC=0x%0d",SUBW_PER_REGF_PC);
  end
// pragma translate_on

// ============================================================================================== --
// typedef
// ============================================================================================== --
 typedef struct packed {
    logic [REGF_REGID_W-1:0] reg_id;
  } rcp_cmd_t;

  localparam int RCP_CMD_W = $bits(rcp_cmd_t);

// ============================================================================================== --
// Per PC
// ============================================================================================== --
  logic [PEM_PC-1:0] cmd_vld_tmp;
  logic [PEM_PC-1:0] cmd_rdy_tmp;

  assign cmd_rdy = &cmd_rdy_tmp;
  always_comb
    for (int i=0; i<PEM_PC; i=i+1) begin
      logic [PEM_PC-1:0] mask;
      mask = 1 << i;
      cmd_vld_tmp[i] = cmd_vld & (&(cmd_rdy_tmp | mask)); // all the other PC are ready
    end

  // Data received
  logic [PEM_PC-1:0][REGF_COEF_PER_PC-1:0][MOD_Q_W-1:0] r2_data;
  logic [PEM_PC-1:0]                                    r2_data_vld;
  logic [PEM_PC-1:0]                                    r2_data_rdy;

  rcp_cmd_t [PEM_PC-1:0]                                r2_cmd;
  logic     [PEM_PC-1:0]                                r2_cmd_vld;
  logic     [PEM_PC-1:0]                                r2_cmd_rdy;

  logic [PEM_PC-1:0][DATA_CNT_W-1:0]                    r2_word_cnt;
  logic                                                 r2_data_dec;
  logic [DATA_CNT_W-1:0]                                r2_data_dec_val;

  generate
    for (genvar gen_p=0; gen_p<PEM_PC; gen_p=gen_p+1) begin : gen_pc_loop
      // Since PEM_PC | AXI4_WORD_PER_BLWE, the body is processed by PC0
      localparam int AXI4_WORD_PER_PATH    = (gen_p == 0) ? AXI4_WORD_PER_PC0 : AXI4_WORD_PER_PC;
      localparam int AXI4_WORD_PER_PATH_W  = (gen_p == 0) ? AXI4_WORD_PER_PC0_W : AXI4_WORD_PER_PC_W;
      localparam int AXI4_WORD_PER_PATH_WW = (gen_p == 0) ? AXI4_WORD_PER_PC0_WW : AXI4_WORD_PER_PC_WW;

// ---------------------------------------------------------------------------------------------- --
// Input FIFO
// ---------------------------------------------------------------------------------------------- --
      pem_cmd_t s0_cmd;
      logic     s0_cmd_vld;
      logic     s0_cmd_rdy;
      logic     [AXI4_ADD_W-1:0] s0_cmd_add_init;

      pem_cmd_t sm1_cmd;
      logic     sm1_cmd_vld;
      logic     sm1_cmd_rdy;
      logic     [AXI4_ADD_W-1:0] sm1_cmd_add_init;
      logic     [AXI4_ADD_W-1:0] sm1_cmd_add_init_tmp;

      pem_cmd_t sm2_cmd;
      logic     sm2_cmd_vld;
      logic     sm2_cmd_rdy;
      logic     [AXI4_ADD_W-1:0] sm2_cmd_add_init;

      assign sm2_cmd_add_init     = sm2_cmd.cid * CT_MEM_BYTES;
      assign sm1_cmd_add_init_tmp = sm1_cmd_add_init + ct_mem_addr[gen_p];

      fifo_reg #(
        .WIDTH       (PEM_CMD_W),
        .DEPTH       (INST_FIFO_DEPTH-2),
        .LAT_PIPE_MH ({1'b1, 1'b1})
      ) in_ld_fifo_reg (
        .clk      (clk),
        .s_rst_n  (s_rst_n),

        .in_data  (cmd),
        .in_vld   (cmd_vld_tmp[gen_p]),
        .in_rdy   (cmd_rdy_tmp[gen_p]),

        .out_data (sm2_cmd),
        .out_vld  (sm2_cmd_vld),
        .out_rdy  (sm2_cmd_rdy)
      );

      fifo_element #(
        .WIDTH          (PEM_CMD_W+AXI4_ADD_W),
        .DEPTH          (1),
        .TYPE_ARRAY     (4'h3),// TOREVIEW
        .DO_RESET_DATA  (1'b0),
        .RESET_DATA_VAL (0)
      ) sm2_fifo_element (
        .clk      (clk),
        .s_rst_n  (s_rst_n),

        .in_data  ({sm2_cmd_add_init,sm2_cmd}),
        .in_vld   (sm2_cmd_vld),
        .in_rdy   (sm2_cmd_rdy),

        .out_data ({sm1_cmd_add_init,sm1_cmd}),
        .out_vld  (sm1_cmd_vld),
        .out_rdy  (sm1_cmd_rdy)
      );

      fifo_element #(
        .WIDTH          (PEM_CMD_W+AXI4_ADD_W),
        .DEPTH          (1),
        .TYPE_ARRAY     (4'h3),// TOREVIEW
        .DO_RESET_DATA  (1'b0),
        .RESET_DATA_VAL (0)
      ) sm1_fifo_element (
        .clk      (clk),
        .s_rst_n  (s_rst_n),

        .in_data  ({sm1_cmd_add_init_tmp,sm1_cmd}),
        .in_vld   (sm1_cmd_vld),
        .in_rdy   (sm1_cmd_rdy),

        .out_data ({s0_cmd_add_init,s0_cmd}),
        .out_vld  (s0_cmd_vld),
        .out_rdy  (s0_cmd_rdy)
      );

// ---------------------------------------------------------------------------------------------- --
// Load request
// ---------------------------------------------------------------------------------------------- --
      // AXI interface
      axi4_ar_if_t                      s0_axi;
      logic                             s0_axi_arvalid;
      logic                             s0_axi_arready;
      logic [AXI4_LEN_W:0]              req_axi_word_nb; // = axi_len + 1. The size 8 correspond to the axi bus size +1

      logic                             rcp_fifo_in_vld;
      logic                             rcp_fifo_in_rdy;
      rcp_cmd_t                         rcp_fifo_in_cmd;


      // Counters
      logic [AXI4_WORD_PER_PATH_WW-1:0] req_axi_word_remain; // counts from AXI4_WORD_PER_PATH included to 0 - decremented
      logic [AXI4_WORD_PER_PATH_WW-1:0] req_axi_word_remainD;
      logic                             req_last_axi_word_remain;
      logic [AXI4_WORD_PER_PATH_WW-1:0] req_axi_word_remain_init;

      logic                             req_pbs_first_burst;
      logic                             req_pbs_first_burstD;

      logic                             req_send_axi_cmd;

      assign req_axi_word_remainD     = req_send_axi_cmd ?
                                            req_last_axi_word_remain ? req_axi_word_remain_init : req_axi_word_remain - req_axi_word_nb :
                                            req_axi_word_remain;
      assign req_last_axi_word_remain = req_axi_word_remain == req_axi_word_nb;
      assign req_axi_word_remain_init = AXI4_WORD_PER_PATH;
      assign req_pbs_first_burstD     = req_send_axi_cmd ? req_last_axi_word_remain ? 1'b1 : 1'b0 : req_pbs_first_burst;

      always_ff @(posedge clk)
        if (!s_rst_n) begin
          req_axi_word_remain <= AXI4_WORD_PER_PATH;
          req_pbs_first_burst <= 1'b1;
        end
        else begin
          req_axi_word_remain <= req_axi_word_remainD;
          req_pbs_first_burst <= req_pbs_first_burstD;
        end

      // Address
      logic [AXI4_ADD_W-1:0]    req_add;
      logic [AXI4_ADD_W-1:0]    req_addD;
      logic [AXI4_ADD_W-1:0]    req_add_start;
      logic [PAGE_BYTES_WW-1:0] req_page_word_remain;
      logic                     req_blwe_done;

      // compute the address offset during the cycle when the command is sent to rcp FIFO
      // /!\ We assume that the BLWE addresses are AXI4_DATA_W aligned.
      // /!\ We assume that the address takes the PEM_CUT into account.
      assign req_add_start = req_pbs_first_burst ? s0_cmd_add_init : req_add;
      assign req_addD     = req_send_axi_cmd     ? req_add_start + req_axi_word_nb*AXI4_DATA_BYTES : req_add;

      always_ff @(posedge clk)
        if (!s_rst_n) req_add <= '0;
        else          req_add <= req_addD;

      assign req_page_word_remain = PAGE_AXI4_DATA - req_add_start[PAGE_BYTES_W-1:AXI4_DATA_BYTES_W];
      assign req_axi_word_nb = req_page_word_remain < req_axi_word_remain ? req_page_word_remain : req_axi_word_remain;
      assign s0_axi.arid     = BLWE_AXI_ARID;
      assign s0_axi.arsize   = AXI4_DATA_BYTES_W;
      assign s0_axi.arburst  = AXI4B_INCR;
      assign s0_axi.araddr   = req_add_start;
      assign s0_axi.arlen    = req_axi_word_nb - 1;
      assign s0_axi_arvalid  = s0_cmd_vld & (~req_pbs_first_burst | rcp_fifo_in_rdy);

      assign req_blwe_done   = req_send_axi_cmd & req_last_axi_word_remain;

      assign s0_cmd_rdy      = req_blwe_done & (~req_pbs_first_burst | rcp_fifo_in_rdy);
      assign rcp_fifo_in_vld = s0_cmd_vld & req_pbs_first_burst & s0_axi_arready;
      assign rcp_fifo_in_cmd.reg_id = s0_cmd.reg_id;

      // pragma translate_off
      always_ff @(posedge clk)
        if (s0_axi_arvalid)
          assert(s0_axi.arlen <= AXI4_LEN_MAX)
          else begin
            $fatal(1,"%t > ERROR: AXI4 len overflow. Should not exceed %0d. Seen %0d",$time, AXI4_LEN_MAX, s0_axi.arlen);
          end
      // pragma translate_on

      //---------------------------------
      // to AXI read request
      //---------------------------------
      axi4_ar_if_t m_axi4_a;

      assign m_axi4_arid[gen_p]    = m_axi4_a.arid   ;
      assign m_axi4_araddr[gen_p]  = m_axi4_a.araddr ;
      assign m_axi4_arlen[gen_p]   = m_axi4_a.arlen  ;
      assign m_axi4_arsize[gen_p]  = m_axi4_a.arsize ;
      assign m_axi4_arburst[gen_p] = m_axi4_a.arburst;

      fifo_element #(
        .WIDTH          ($bits(axi4_ar_if_t)),
        .DEPTH          (1),
        .TYPE_ARRAY     (4'h3), // TOREVIEW
        .DO_RESET_DATA  (1'b0),
        .RESET_DATA_VAL (0)
      ) fifo_element (
        .clk     (clk),
        .s_rst_n (s_rst_n),

        .in_data (s0_axi),
        .in_vld  (s0_axi_arvalid),
        .in_rdy  (s0_axi_arready),

        .out_data(m_axi4_a),
        .out_vld (m_axi4_arvalid[gen_p]),
        .out_rdy (m_axi4_arready[gen_p])
      );

      assign req_send_axi_cmd = s0_axi_arvalid & s0_axi_arready;

// ---------------------------------------------------------------------------------------------- --
// Data reception
// ---------------------------------------------------------------------------------------------- --
      //-------------------------
      // Reception command fifo
      //-------------------------
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

        .out_data (r2_cmd[gen_p]),
        .out_vld  (r2_cmd_vld[gen_p]),
        .out_rdy  (r2_cmd_rdy[gen_p])
      );

      //-------------------------
      // AXI data fifo
      //-------------------------
      axi4_r_if_t m_axi4_r;

      axi4_r_if_t r0_axi_r;
      logic       r0_axi_vld;
      logic       r0_axi_rdy;

      assign m_axi4_r.rid   = m_axi4_rid[gen_p];
      assign m_axi4_r.rdata = m_axi4_rdata[gen_p];
      assign m_axi4_r.rresp = m_axi4_rresp[gen_p];
      assign m_axi4_r.rlast = m_axi4_rlast[gen_p];

      fifo_element #(
        .WIDTH          (AXI4_R_IF_W),
        .DEPTH          (2),
        .TYPE_ARRAY     ({4'h1,4'h2}),
        .DO_RESET_DATA  (0),
        .RESET_DATA_VAL (0)
      ) axi_r_fifo_element (
        .clk     (clk),
        .s_rst_n (s_rst_n),

        .in_data (m_axi4_r),
        .in_vld  (m_axi4_rvalid[gen_p]),
        .in_rdy  (m_axi4_rready[gen_p]),

        .out_data(r0_axi_r),
        .out_vld (r0_axi_vld),
        .out_rdy (r0_axi_rdy)
      );

      //-------------------------
      // Process data
      //-------------------------
      // Data received
      logic [REGF_COEF_PER_PC-1:0][MOD_Q_W-1:0] r1_data;
      logic                                     r1_data_vld;
      logic                                     r1_data_rdy;


      logic [AXI4_WORD_PER_PATH_W-1:0] r0_axi_word_cnt;
      logic [AXI4_WORD_PER_PATH_W-1:0] r0_axi_word_cntD;
      logic                            r0_last_axi_word_cnt;


      assign r0_last_axi_word_cnt = r0_axi_word_cnt == AXI4_WORD_PER_PATH-1;
      assign r0_axi_word_cntD     = r0_axi_vld && r0_axi_rdy ? r0_last_axi_word_cnt ? '0 : r0_axi_word_cnt + 1 : r0_axi_word_cnt;

      always_ff @(posedge clk)
        if (!s_rst_n) r0_axi_word_cnt <= '0;
        else          r0_axi_word_cnt <= r0_axi_word_cntD;

      //= Reorg AXI input data
      if (SUBW_PER_REGF_PC < 2) begin : gen_subw_per_regf_pc_lt_2
        localparam int LAST_OUT_CNT_TMP = TOTAL_SUBW_NB % SUBW_PER_AXI4_WORD;
        localparam int LAST_OUT_CNT     = LAST_OUT_CNT_TMP == 0 ? SUBW_PER_AXI4_WORD-1 : LAST_OUT_CNT_TMP-1;

        logic [SUBW_PER_AXI4_WORD-1:0][SUBW_COEF_NB-1:0][BLWE_ACS_W-1:0] sr_data;
        logic [SUBW_PER_AXI4_WORD-1:0][SUBW_COEF_NB-1:0][BLWE_ACS_W-1:0] sr_data_tmp;
        logic [SUBW_PER_AXI4_WORD-1:0][SUBW_COEF_NB-1:0][BLWE_ACS_W-1:0] sr_dataD;

        logic [SUBW_PER_AXI4_WORD_W-1:0]                                 sr_out_cnt;
        logic [SUBW_PER_AXI4_WORD_W-1:0]                                 sr_out_cntD;
        logic                                                            sr_last_out_cnt;
        logic                                                            sr_avail;
        logic                                                            sr_availD;

        logic                                                            sr_insert_fake;
        logic                                                            sr_insert_fakeD;

        logic                                                            r0_axi_rdy_tmp;
        logic                                                            r1_last_axi_word_cnt;
        logic                                                            r1_last_axi_word_cntD;

        // When gen_p != 0 insert a fake AXI_WORD, to complete the body coefficient, that is handled
        // by gen_p=0
        assign sr_insert_fakeD = (gen_p != 0) & r0_axi_vld & r0_axi_rdy & r0_last_axi_word_cnt ? 1'b1 :
                                 r1_data_vld && r1_data_rdy && sr_last_out_cnt ? 1'b0 : sr_insert_fake;

        assign sr_data_tmp = sr_data >> (BLWE_ACS_W * SUBW_COEF_NB);
        assign sr_dataD = (r0_axi_vld || sr_insert_fake)  && r0_axi_rdy_tmp  ? r0_axi_r.rdata : // when sr_insert_fake=1, r0_axi_r.rdata seen as fake data
                          //r1_data_vld && r1_data_rdy ? {sr_data[SUBW_PER_AXI4_WORD-1],sr_data[SUBW_PER_AXI4_WORD-1:1]} : sr_data;
                          r1_data_vld && r1_data_rdy ? sr_data_tmp : sr_data; // To avoid warning - when this branch of the generate is not used.

        assign sr_out_cntD     = r1_data_vld && r1_data_rdy ? sr_last_out_cnt ? '0 : sr_out_cnt + 1 : sr_out_cnt;
        assign sr_last_out_cnt = (sr_out_cnt == SUBW_PER_AXI4_WORD -1) | (r1_last_axi_word_cnt & sr_out_cnt == LAST_OUT_CNT);
        assign sr_availD       = (r0_axi_vld || sr_insert_fake) && r0_axi_rdy_tmp  ? 1'b1 :
                                 r1_data_vld && r1_data_rdy && sr_last_out_cnt ? 1'b0 : sr_avail;

        assign r1_data_vld     = sr_avail;
        assign r0_axi_rdy_tmp  = ~sr_avail | (r1_data_rdy & sr_last_out_cnt);
        assign r0_axi_rdy      = r0_axi_rdy_tmp & ~sr_insert_fake;

        always_comb
          for (int y=0; y<SUBW_COEF_NB; y=y+1)
            r1_data[y] = sr_data[0][y][0+:MOD_Q_W]; // extract the MOD_Q_W bits

        always_ff @(posedge clk)
          if (!s_rst_n) begin
            sr_out_cnt     <= '0;
            sr_avail       <= 1'b0;
            sr_insert_fake <= 1'b0;
          end
          else begin
            sr_out_cnt     <= sr_out_cntD;
            sr_avail       <= sr_availD;
            sr_insert_fake <= sr_insert_fakeD;
          end

        always_ff @(posedge clk)
          sr_data <= sr_dataD;

        assign r1_last_axi_word_cntD = (gen_p == 0) ?  (r0_axi_vld && r0_axi_rdy ? r0_last_axi_word_cnt : r1_last_axi_word_cnt):
                                                       (r0_axi_vld || sr_insert_fake) && r0_axi_rdy_tmp ? sr_insert_fake : r1_last_axi_word_cnt;

        always_ff @(posedge clk)
          r1_last_axi_word_cnt <= r1_last_axi_word_cntD;

// pragma translate_off
        always_ff @(posedge clk)
          if (!s_rst_n) begin
            // do nothing
          end
          else begin
            assert(!(sr_insert_fake & r0_axi_rdy))
            else begin
              $fatal(1,"%t > ERROR: Insert a fake data at the same time as accepting new data [PC=%0d].",$time, gen_p);
            end
          end
// pragma translate_on

      end // gen_subw_per_axi4_word_gt_1
      else begin : gen_subw_per_regf_pc_ge_2
        // AXI4 words are accumulated until a REGF_COEF_PER_PC column is complete
        logic [SUBW_PER_REGF_PC-1:1][SUBW_COEF_NB-1:0][BLWE_ACS_W-1:0] acc_data;
        logic [SUBW_PER_REGF_PC-1:1][SUBW_COEF_NB-1:0][BLWE_ACS_W-1:0] acc_dataD;
        logic [REGF_COEF_NB-1:0][BLWE_ACS_W-1:0]                       r1_data_tmp;

        logic [SUBW_PER_REGF_PC_W-1:0]                                 acc_in_cnt;
        logic [SUBW_PER_REGF_PC_W-1:0]                                 acc_in_cntD;
        logic                                                          acc_last_in_cnt;

        logic                                                          acc_insert_fake;
        logic                                                          acc_insert_fakeD;

        logic                                                          r0_axi_rdy_tmp;
        logic                                                          r0_last_axi_word_cnt_tmp;

        // When gen_p != 0 insert a fake AXI_WORD, to complete the body coefficient, that is handled
        // by gen_p=0
        assign acc_insert_fakeD = (gen_p != 0) & r0_axi_vld & r0_axi_rdy & r0_last_axi_word_cnt ? 1'b1 :
                                   r1_data_vld && r1_data_rdy ? 1'b0 : acc_insert_fake;
        assign r0_last_axi_word_cnt_tmp = (gen_p == 0) ? r0_last_axi_word_cnt : acc_insert_fake;

        assign acc_in_cntD     = (r0_axi_vld || acc_insert_fake) && r0_axi_rdy_tmp ? acc_last_in_cnt ? '0 : acc_in_cnt + 1 : acc_in_cnt;
        assign acc_last_in_cnt = r0_last_axi_word_cnt_tmp | (acc_in_cnt == (SUBW_PER_REGF_PC-1));

        if (SUBW_PER_REGF_PC > 2) begin
          assign acc_dataD   = r0_axi_vld && r0_axi_rdy ? {r0_axi_r.rdata, acc_data[SUBW_PER_REGF_PC-1:2]} : acc_data;
        end
        else begin
          assign acc_dataD   = r0_axi_vld && r0_axi_rdy ? {r0_axi_r.rdata} : acc_data;
        end
        assign r1_data_tmp = r0_last_axi_word_cnt_tmp ? {SUBW_PER_REGF_PC{r0_axi_r.rdata}} : {r0_axi_r.rdata, acc_data};
        assign r1_data_vld = (r0_axi_vld|acc_insert_fake) & acc_last_in_cnt;
        assign r0_axi_rdy_tmp = (~acc_last_in_cnt | r1_data_rdy);
        assign r0_axi_rdy     = r0_axi_rdy_tmp & ~acc_insert_fake;

        always_comb
          for (int y=0; y<REGF_COEF_PER_PC; y=y+1)
            r1_data[y] = r1_data_tmp[y][0+:MOD_Q_W]; // extract the MOD_Q_W bits

        always_ff @(posedge clk)
          if (!s_rst_n) begin
            acc_in_cnt      <= '0;
            acc_insert_fake <= 1'b0;
          end
          else begin
            acc_in_cnt      <= acc_in_cntD;
            acc_insert_fake <= acc_insert_fakeD;
          end

        always_ff @(posedge clk)
          acc_data <= acc_dataD;

// pragma translate_off
        always_ff @(posedge clk)
          if (!s_rst_n) begin
            // do nothing
          end
          else begin
            assert(!(acc_insert_fake & r0_axi_rdy))
            else begin
              $fatal(1,"%t > ERROR: Insert a fake data at the same time as accepting new data [PC=%0d].",$time, gen_p);
            end
          end
// pragma translate_on
      end // gen_subw_per_axi4_word_eq_1

      //-------------------------
      // Fifo data
      //-------------------------
      fifo_reg #(
        .WIDTH       (REGF_COEF_PER_PC*MOD_Q_W),
        .DEPTH       (DATA_FIFO_DEPTH),
        .LAT_PIPE_MH ({1'b1, 1'b1})
      ) r1_fifo_reg (
        .clk      (clk),
        .s_rst_n  (s_rst_n),

        .in_data  (r1_data),
        .in_vld   (r1_data_vld),
        .in_rdy   (r1_data_rdy),

        .out_data (r2_data[gen_p]),
        .out_vld  (r2_data_vld[gen_p]),
        .out_rdy  (r2_data_rdy[gen_p])
      );

      //-------------------------
      // Data count
      //-------------------------
      // Counts the number of available data in the FIFO
      // Decrement the number of data that are / will be sent.
      logic [DATA_CNT_W-1:0] r2_word_cnt_l;
      logic [DATA_CNT_W-1:0] r2_word_cnt_lD;
      logic                  r2_word_cnt_inc;
      logic [DATA_CNT_W-1:0] r2_word_cnt_dec;

      assign r2_word_cnt_inc = r1_data_rdy & r1_data_vld;
      assign r2_word_cnt_dec = r2_data_dec ? r2_data_dec_val : '0;
      assign r2_word_cnt_lD  = r2_word_cnt_l + r2_word_cnt_inc - r2_word_cnt_dec;

      always_ff @(posedge clk)
        if (!s_rst_n) r2_word_cnt_l <= '0;
        else          r2_word_cnt_l <= r2_word_cnt_lD;

      assign r2_word_cnt[gen_p] = r2_word_cnt_l;

    end // for gen_p
  endgenerate

// ============================================================================================== --
// Regfile interface
// ============================================================================================== --
  logic     r2_rcp_cmd_vld;
  logic     r2_rcp_cmd_rdy;
  rcp_cmd_t r2_rcp_cmd;

  assign r2_rcp_cmd_vld = &r2_cmd_vld;
  assign r2_rcp_cmd     = r2_cmd[0];

  always_comb
    for (int i=0; i<PEM_PC; i=i+1) begin
      logic [PEM_PC-1:0] mask;
      mask = 1 << i;
      r2_cmd_rdy[i] = r2_rcp_cmd_rdy & (&(r2_cmd_vld | mask));
    end

  // Counters
  logic [REGF_CMD_NB_W-1:0]         r2_cmd_cnt;
  logic [REGF_BLWE_WORD_CNT_W-1:0]  r2_word_add;

  logic [REGF_CMD_NB_W-1:0]         r2_cmd_cntD;
  logic [REGF_BLWE_WORD_CNT_W-1:0]  r2_word_addD;

  logic                             r2_last_cmd_cnt;
  logic                             r2_send_cmd;

  assign r2_last_cmd_cnt = r2_cmd_cnt == REGF_CMD_NB - 1;
  assign r2_cmd_cntD     = r2_send_cmd ? r2_last_cmd_cnt ? 0 : r2_cmd_cnt + 1 : r2_cmd_cnt;
  assign r2_word_addD    = r2_send_cmd ? r2_last_cmd_cnt ? '0 : r2_word_add + REGF_WORD_THRESHOLD : r2_word_add;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      r2_cmd_cnt  <= '0;
      r2_word_add <= '0;
    end
    else begin
      r2_cmd_cnt  <= r2_cmd_cntD;
      r2_word_add <= r2_word_addD;
    end

  // Check data availability
  logic [PEM_PC-1:0] r2_enough_word;
  always_comb
    for (int i=0; i<PEM_PC; i=i+1)
      r2_enough_word[i] = (r2_word_cnt[i] >= REGF_WORD_THRESHOLD) | (r2_last_cmd_cnt & (r2_word_cnt[i] >= REGF_LAST_CMD_WORD_NB));

  regf_wr_req_t r2_regf_req;
  logic         r2_regf_req_vld;
  logic         r2_regf_req_rdy;

  assign r2_regf_req_vld        = r2_rcp_cmd_vld & (&r2_enough_word);
  assign r2_send_cmd            = r2_regf_req_vld & r2_regf_req_rdy;
  assign r2_rcp_cmd_rdy         = r2_regf_req_rdy & (&r2_enough_word) & r2_last_cmd_cnt;
  assign r2_regf_req.reg_id     = r2_rcp_cmd.reg_id;
  assign r2_regf_req.start_word = r2_word_add;
  assign r2_regf_req.word_nb_m1 = r2_last_cmd_cnt ? REGF_LAST_CMD_WORD_NB-1 : REGF_WORD_THRESHOLD-1;
  assign r2_data_dec            = r2_send_cmd;
  assign r2_data_dec_val        = r2_last_cmd_cnt ? REGF_LAST_CMD_WORD_NB : REGF_WORD_THRESHOLD;

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      if (r2_rcp_cmd_rdy) begin
        assert(r2_cmd_vld == '1)
        else begin
          $fatal(1,"%t > ERROR: all paths are not valid when the ready is set.", $time);
        end
      end
    end
// pragma translate_on

// ---------------------------------------------------------------------------------------------- --
// Regfile request pipe
// ---------------------------------------------------------------------------------------------- --
  fifo_element #(
    .WIDTH          (REGF_WR_REQ_W),
    .DEPTH          (1),
    .TYPE_ARRAY     (4'h3), // TOREVIEW
    .DO_RESET_DATA  (0),
    .RESET_DATA_VAL (0)
  ) regf_req_fifo_element (
    .clk     (clk),
    .s_rst_n (s_rst_n),

    .in_data (r2_regf_req),
    .in_vld  (r2_regf_req_vld),
    .in_rdy  (r2_regf_req_rdy),

    .out_data(pem_regf_wr_req),
    .out_vld (pem_regf_wr_req_vld),
    .out_rdy (pem_regf_wr_req_rdy)
  );

// ---------------------------------------------------------------------------------------------- --
// Regfile Data
// ---------------------------------------------------------------------------------------------- --
  logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0] r2_regf_data;
  logic                                 r2_regf_data_vld;
  logic                                 r2_regf_data_rdy;

  logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0] pem_regf_wr_data_tmp;
  logic                                 pem_regf_wr_data_vld_tmp;
  logic                                 pem_regf_wr_data_rdy_tmp;

  assign r2_regf_data     = r2_data;
  assign r2_regf_data_vld = &r2_data_vld;

  always_comb
    for (int i=0; i<PEM_PC; i=i+1) begin
      logic [PEM_PC-1:0] mask;
      mask = 1 << i;
      r2_data_rdy[i] = r2_regf_data_rdy & (&(r2_data_vld | mask));
    end

  fifo_element #(
    .WIDTH          (REGF_COEF_NB*MOD_Q_W),
    .DEPTH          (1),
    .TYPE_ARRAY     (4'h3), // TOREVIEW, because PEM_PERIOD > 1
    .DO_RESET_DATA  (0),
    .RESET_DATA_VAL (0)
  ) regf_data_fifo_element (
    .clk     (clk),
    .s_rst_n (s_rst_n),

    .in_data (r2_regf_data),
    .in_vld  (r2_regf_data_vld),
    .in_rdy  (r2_regf_data_rdy),

    .out_data(pem_regf_wr_data_tmp),
    .out_vld (pem_regf_wr_data_vld_tmp),
    .out_rdy (pem_regf_wr_data_rdy_tmp)
  );

  stream_to_seq #(
    .WIDTH(MOD_Q_W),
    .IN_NB(REGF_COEF_NB),
    .SEQ  (REGF_SEQ)
  ) stream_to_seq (
    .clk      (clk),
    .s_rst_n  (s_rst_n),

    .in_data  (pem_regf_wr_data_tmp),
    .in_vld   (pem_regf_wr_data_vld_tmp),
    .in_rdy   (pem_regf_wr_data_rdy_tmp),

    .out_data (pem_regf_wr_data),
    .out_vld  (pem_regf_wr_data_vld),
    .out_rdy  (pem_regf_wr_data_rdy)
  );

// ---------------------------------------------------------------------------------------------- --
// Acknowledge
// ---------------------------------------------------------------------------------------------- --
  // There are REGF_CMD_NB regfile requests sent per input command.
  // Then, all we need is count the ack from the regfile.
  logic [REGF_CMD_NB_W-1:0] regf_pem_wr_ack_cnt;
  logic [REGF_CMD_NB_W-1:0] regf_pem_wr_ack_cntD;
  logic                     cmd_ackD;

  logic last_regf_pem_wr_ack;

  assign last_regf_pem_wr_ack = regf_pem_wr_ack_cnt == REGF_CMD_NB-1;
  assign regf_pem_wr_ack_cntD = regf_pem_wr_ack ? last_regf_pem_wr_ack ? '0 : regf_pem_wr_ack_cnt + 1: regf_pem_wr_ack_cnt;
  assign cmd_ackD             = last_regf_pem_wr_ack & regf_pem_wr_ack;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      regf_pem_wr_ack_cnt <= '0;
      cmd_ack             <= 1'b0;
    end
    else begin
      regf_pem_wr_ack_cnt <= regf_pem_wr_ack_cntD;
      cmd_ack             <= cmd_ackD;
    end

// ============================================================================================== --
// Info
// ============================================================================================== --
  pem_ld_info_t pem_ld_info_tmp;

  always_comb begin
    pem_ld_info      = '0;
    pem_ld_info.add  = pem_ld_info_tmp.add;
    pem_ld_info.data = pem_ld_info_tmp.data;
  end

  generate
    for (genvar gen_pc=0; gen_pc<PEM_PC_MAX; gen_pc=gen_pc+1) begin : gen_pc_max_loop
      if (gen_pc < PEM_PC) begin : gen_pc_exists
        logic [AXI4_ADD_W-1:0] info_add;
        logic [AXI4_ADD_W-1:0] info_addD;
        logic                  info_add_done;
        logic                  info_add_doneD;
        logic [3:0][31:0]      info_data;
        logic [3:0][31:0]      info_dataD;
        logic                  info_data_done;
        logic                  info_data_doneD;

        assign info_add_doneD  = info_add_done  | (m_axi4_arvalid[gen_pc] & m_axi4_arready[gen_pc]);
        assign info_data_doneD = info_data_done | (m_axi4_rvalid[gen_pc] & m_axi4_rready[gen_pc]);

        assign info_addD  = !info_add_done && m_axi4_arvalid[gen_pc] && m_axi4_arready[gen_pc] ? m_axi4_araddr[gen_pc] : info_add;
        assign info_dataD = !info_data_done && m_axi4_rvalid[gen_pc] && m_axi4_rready[gen_pc]  ? m_axi4_rdata[gen_pc] : info_data; // truncated

        assign pem_ld_info_tmp.add[gen_pc]  = info_add;
        assign pem_ld_info_tmp.data[gen_pc] = info_data;

        always_ff @(posedge clk)
          if (!s_rst_n) begin
            info_add_done  <= 1'b0;
            info_data_done <= 1'b0;
          end
          else begin
            info_add_done  <= info_add_doneD ;
            info_data_done <= info_data_doneD;
          end

        always_ff @(posedge clk) begin
          info_add  <= info_addD;
          info_data <= info_dataD;
        end
      end // if gen_pc < PEM_PC
      else begin
        assign pem_ld_info_tmp.add[gen_pc]  = '0;
        assign pem_ld_info_tmp.data[gen_pc] = '0;
      end

    end
  endgenerate

endmodule
