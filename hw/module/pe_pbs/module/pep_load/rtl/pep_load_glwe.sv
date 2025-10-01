// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the reading of GLWE in regfile for the blind rotation.
// Note that we only read the "body" polynomial. Indeed, the mask part is 0.
// ==============================================================================================

module pep_load_glwe
  import axi_if_common_param_pkg::*;
  import axi_if_glwe_axi_pkg::*;
  import param_tfhe_pkg::*;
  import top_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import ntt_core_common_param_pkg::*;
(
  input  logic                                                   clk,        // clock
  input  logic                                                   s_rst_n,    // synchronous reset

  input  logic [AXI4_ADD_W-1:0]                                  gid_offset, // quasi static

  // From GRAM arbiter
  input  logic [GRAM_NB-1:0]                                     garb_ldg_avail_1h,

  // pep_seq : command
  input  logic [LOAD_GLWE_CMD_W-1:0]                             seq_ldg_cmd,
  input  logic                                                   seq_ldg_vld,
  output logic                                                   seq_ldg_rdy,
  output logic                                                   ldg_seq_done,

  // AXI4 Master interface
  // NB: Only AXI Read channel exposed here
  output logic [AXI4_ID_W-1:0]                                   m_axi_arid,
  output logic [AXI4_ADD_W-1:0]                                  m_axi_araddr,
  output logic [7:0]                                             m_axi_arlen,
  output logic [2:0]                                             m_axi_arsize,
  output logic [1:0]                                             m_axi_arburst,
  output logic                                                   m_axi_arvalid,
  input  logic                                                   m_axi_arready,
  input  logic [AXI4_ID_W-1:0]                                   m_axi_rid,
  input  logic [AXI4_DATA_W-1:0]                                 m_axi_rdata,
  input  logic [1:0]                                             m_axi_rresp,
  input  logic                                                   m_axi_rlast,
  input  logic                                                   m_axi_rvalid,
  output logic                                                   m_axi_rready,

  // Write GLWE RAM
  // This memory is composed of GRAM_NB independent RAMs
  output logic [GRAM_NB-1:0][PSI-1:0][R-1:0]                     glwe_ram_wr_en,
  output logic [GRAM_NB-1:0][PSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0] glwe_ram_wr_add ,
  output logic [GRAM_NB-1:0][PSI-1:0][R-1:0][MOD_Q_W-1:0]        glwe_ram_wr_data,

  output logic                                                   ldg_rif_req_dur,
  output logic                                                   ldg_rif_rcp_dur
);

// ============================================================================================== //
// localparam
// ============================================================================================== //
  localparam int RCP_FIFO_DEPTH       = 8; // TOREVIEW : according to memory latency.

  // Introduce an intermediate format to ease the design, and minimize the number of buffers.
  localparam int GLWE_SUBW_COEF_NB        = (PSI*R < (AXI4_DATA_W / GLWE_ACS_W))? (PSI*R): (AXI4_DATA_W / GLWE_ACS_W);
  localparam int GLWE_SUBW_NB             = (PSI*R)/GLWE_SUBW_COEF_NB;
  localparam int GLWE_SUBW_NB_W           = ($clog2(GLWE_SUBW_NB) == 0) ? 1 : $clog2(GLWE_SUBW_NB);
  localparam int GLWE_SUBW_NB_SZ          = $clog2(GLWE_SUBW_NB);
  localparam int GLWE_RAM_DEPTH_PBS       = STG_ITER_NB * GLWE_K_P1;
  localparam int GLWE_RAM_MASK_DEPTH_PBS  = STG_ITER_NB * GLWE_K;

  localparam int AXI4_WORD_PER_GLWE_BODY  = (N*GLWE_ACS_W + AXI4_DATA_W-1)/AXI4_DATA_W;

  localparam int GLWE_SUBW_PER_AXI4_WORD  = (GLWE_COEF_PER_AXI4_WORD + GLWE_SUBW_COEF_NB -1) / GLWE_SUBW_COEF_NB;
  localparam int GLWE_BODY_SUBW_NB        = (N + GLWE_SUBW_COEF_NB-1)/ GLWE_SUBW_COEF_NB;

  localparam int AXI4_WORD_PER_GLWE_BODY_WW = $clog2(AXI4_WORD_PER_GLWE_BODY+1) == 0 ? 1 : $clog2(AXI4_WORD_PER_GLWE_BODY+1);

  localparam int GLWE_SUBW_PER_AXI4_WORD_W = $clog2(GLWE_SUBW_PER_AXI4_WORD) == 0 ? 1 : $clog2(GLWE_SUBW_PER_AXI4_WORD);


  localparam int GLWE_BODY_BYTES      = N * GLWE_ACS_W/8;
  localparam int RAM_PBS_ADD_OFS      = GLWE_RAM_DEPTH_PBS * GLWE_SUBW_NB;
  localparam int RAM_PBS_BODY_ADD_OFS = GLWE_RAM_MASK_DEPTH_PBS * GLWE_SUBW_NB;
  localparam int TOTAL_SUBW_NB        = GLWE_BODY_SUBW_NB;
  localparam int TOTAL_SUBW_NB_W      = $clog2(TOTAL_SUBW_NB) == 0 ? 1 : $clog2(TOTAL_SUBW_NB);
  localparam int SUBW_DEPTH           = GLWE_RAM_DEPTH * GLWE_SUBW_NB;
  localparam int SUBW_ADD_W           = $clog2(SUBW_DEPTH) == 0 ? 1 : $clog2(SUBW_DEPTH);

// pragma translate_off
  generate
    if (2**($clog2(GLWE_SUBW_COEF_NB)) != GLWE_SUBW_COEF_NB) begin
      initial begin
        $fatal(1,"ERROR > RTL choices were made with the assumption that GLWE_SUBW_COEF_NB (%0d) is a power of 2",GLWE_SUBW_COEF_NB);
      end
    end

    if (GLWE_BODY_BYTES % AXI4_DATA_BYTES != 0) begin
      initial begin
        $fatal(1,"ERROR > GLWE_BODY_BYTES (%0d) should be AXI4_DATA_BYTES (%0d) aligned", GLWE_BODY_BYTES, AXI4_DATA_BYTES);
      end
    end

    if ((GRAM_NB*GLWE_RAM_DEPTH) < TOTAL_PBS_NB * GLWE_RAM_DEPTH_PBS) begin
      initial begin
        $fatal(1,"ERROR > GRAM_NB (%0d) * GLWE_RAM_DEPTH (%0d) has not the expected value TOTAL_PBS_NB (%0d) * GLWE_RAM_DEPTH_PBS (%0d)",GRAM_NB, GLWE_RAM_DEPTH,TOTAL_PBS_NB,GLWE_RAM_DEPTH_PBS);
      end
    end
  endgenerate
// pragma translate_on

// ============================================================================================== //
// Input pipe
// ============================================================================================== //
  //== Command
  load_glwe_cmd_t c0_cmd;
  logic           c0_cmd_vld;
  logic           c0_cmd_rdy;

  fifo_element #(
    .WIDTH          (LOAD_GLWE_CMD_W),
    .DEPTH          (1), // TOREVIEW
    .TYPE_ARRAY     (4'h3),
    .DO_RESET_DATA  (1'b0),
    .RESET_DATA_VAL (0)
  ) ldg_cmd_fifo_element (
    .clk     (clk),
    .s_rst_n (s_rst_n),

    .in_data (seq_ldg_cmd),
    .in_vld  (seq_ldg_vld),
    .in_rdy  (seq_ldg_rdy),

    .out_data(c0_cmd),
    .out_vld (c0_cmd_vld),
    .out_rdy (c0_cmd_rdy)
  );

  //== Data
  axi4_r_if_t r0_axi_if;
  logic       r0_axi_vld;
  logic       r0_axi_rdy;

  axi4_r_if_t m_axi_if;

  assign m_axi_if.rid   = m_axi_rid;
  assign m_axi_if.rdata = m_axi_rdata;
  assign m_axi_if.rresp = m_axi_rresp;
  assign m_axi_if.rlast = m_axi_rlast;

  fifo_element #(
    .WIDTH          (AXI4_R_IF_W),
    .DEPTH          (2),
    .TYPE_ARRAY     (8'h12),
    .DO_RESET_DATA  (0),
    .RESET_DATA_VAL (0)
  ) axi_r_fifo_element (
    .clk     (clk),
    .s_rst_n (s_rst_n),

    .in_data (m_axi_if),
    .in_vld  (m_axi_rvalid),
    .in_rdy  (m_axi_rready),

    .out_data(r0_axi_if),
    .out_vld (r0_axi_vld),
    .out_rdy (r0_axi_rdy)
  );

  //== access avail
  logic [GRAM_NB-1:0] gram_avail_1h;

  always_ff @(posedge clk)
    if (!s_rst_n) gram_avail_1h <= '0;
    else          gram_avail_1h <= garb_ldg_avail_1h;

// ============================================================================================== //
// Fork command
// ============================================================================================== //
// Fork the command between the request path and the reception path.
  logic           c0_req_cmd_vld;
  logic           c0_req_cmd_rdy;
  logic           c0_rcp_cmd_vld;
  logic           c0_rcp_cmd_rdy;

  load_glwe_cmd_t rcp_fifo_out_cmd;
  logic           rcp_fifo_out_vld;
  logic           rcp_fifo_out_rdy;

  load_glwe_cmd_t req_fifo_out_cmd;
  logic           req_fifo_out_vld;
  logic           req_fifo_out_rdy;

  logic [AXI4_ADD_W-1:0] c0_gid_add_ofs;
  logic [AXI4_ADD_W-1:0] req_fifo_out_gid_add_ofs;
  logic [SUBW_ADD_W-1:0] c0_pid_add_ofs;
  logic [SUBW_ADD_W-1:0] rcp_fifo_out_pid_add_ofs;

  assign c0_req_cmd_vld = c0_cmd_vld & c0_rcp_cmd_rdy;
  assign c0_rcp_cmd_vld = c0_cmd_vld & c0_req_cmd_rdy;
  assign c0_cmd_rdy     = c0_req_cmd_rdy & c0_rcp_cmd_rdy;

  assign c0_gid_add_ofs = gid_offset + c0_cmd.gid * GLWE_BODY_BYTES;
  // Address in the GRAM
  assign c0_pid_add_ofs = c0_cmd.pid.grof * RAM_PBS_ADD_OFS + RAM_PBS_BODY_ADD_OFS; // We only write the body part.

  fifo_element #(
    .WIDTH          (AXI4_ADD_W + LOAD_GLWE_CMD_W),
    .DEPTH          (1),
    .TYPE_ARRAY     (4'h1),
    .DO_RESET_DATA  (1'b0),
    .RESET_DATA_VAL (0)
  ) req_fifo_element (
    .clk     (clk),
    .s_rst_n (s_rst_n),

    .in_data ({c0_gid_add_ofs,c0_cmd}),
    .in_vld  (c0_req_cmd_vld),
    .in_rdy  (c0_req_cmd_rdy),

    .out_data({req_fifo_out_gid_add_ofs,req_fifo_out_cmd}),
    .out_vld (req_fifo_out_vld),
    .out_rdy (req_fifo_out_rdy)
  );

  fifo_reg #(
    .WIDTH       (SUBW_ADD_W + LOAD_GLWE_CMD_W),
    .DEPTH       (RCP_FIFO_DEPTH),
    .LAT_PIPE_MH ({1'b1, 1'b1})
  ) rcp_fifo_reg (
    .clk      (clk),
    .s_rst_n  (s_rst_n),

    .in_data  ({c0_pid_add_ofs,c0_cmd}),
    .in_vld   (c0_rcp_cmd_vld),
    .in_rdy   (c0_rcp_cmd_rdy),

    .out_data ({rcp_fifo_out_pid_add_ofs,rcp_fifo_out_cmd}),
    .out_vld  (rcp_fifo_out_vld),
    .out_rdy  (rcp_fifo_out_rdy)
  );

// ============================================================================================== //
// Load request
// ============================================================================================== //
  // AXI interface
  axi4_ar_if_t                           s0_axi;
  logic                                  s0_axi_arvalid;
  logic                                  s0_axi_arready;
  logic [8:0]                            req_axi_word_nb; // = axi_len + 1. The size 8 correspond to the axi bus size +1

  // Counters
  logic [AXI4_WORD_PER_GLWE_BODY_WW-1:0] req_axi_word_remain; // counts from AXI4_WORD_PER_GLWE_BODY included to 0 - decremented
  logic [AXI4_WORD_PER_GLWE_BODY_WW-1:0] req_axi_word_remainD;
  logic                                  req_last_axi_word_remain;

  logic                                  req_send_axi_cmd;
  logic                                  req_first_burst;
  logic                                  req_first_burstD;

  assign req_axi_word_remainD     = req_send_axi_cmd ? req_last_axi_word_remain ? AXI4_WORD_PER_GLWE_BODY : req_axi_word_remain - req_axi_word_nb : req_axi_word_remain;
  assign req_last_axi_word_remain = req_axi_word_remain == req_axi_word_nb;
  assign req_first_burstD         = req_send_axi_cmd ? req_last_axi_word_remain ? 1'b1 : 1'b0 : req_first_burst;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      req_axi_word_remain <= AXI4_WORD_PER_GLWE_BODY;
      req_first_burst     <= 1'b1;
    end
    else begin
      req_axi_word_remain <= req_axi_word_remainD;
      req_first_burst     <= req_first_burstD;
    end

  // Address
  logic [AXI4_ADD_W-1:0]    req_add;
  logic [AXI4_ADD_W-1:0]    req_add_keep;
  logic [AXI4_ADD_W-1:0]    req_add_keepD;
  logic [PAGE_BYTES_WW-1:0] req_page_word_remain;

  assign req_add  = req_first_burst ? req_fifo_out_gid_add_ofs : req_add_keep;

  assign req_add_keepD = req_send_axi_cmd ? req_add + req_axi_word_nb*AXI4_DATA_BYTES : req_add_keep;

  always_ff @(posedge clk)
    if (!s_rst_n) req_add_keep <= '0;
    else          req_add_keep <= req_add_keepD;

  assign req_page_word_remain = PAGE_AXI4_DATA - req_add[PAGE_BYTES_W-1:AXI4_DATA_BYTES_W];
  assign req_axi_word_nb      = req_page_word_remain < req_axi_word_remain ? req_page_word_remain : req_axi_word_remain;
  assign s0_axi.arid          = '0; // UNUSED
  assign s0_axi.arsize        = AXI4_DATA_BYTES_W;
  assign s0_axi.arburst       = AXI4B_INCR;
  assign s0_axi.araddr        = req_add;
  assign s0_axi.arlen         = req_axi_word_nb - 1;
  assign s0_axi_arvalid       = req_fifo_out_vld;

  assign req_fifo_out_rdy     = req_send_axi_cmd & req_last_axi_word_remain;

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
  axi4_ar_if_t m_axi_a;

  assign m_axi_arid    = m_axi_a.arid   ;
  assign m_axi_araddr  = m_axi_a.araddr ;
  assign m_axi_arlen   = m_axi_a.arlen  ;
  assign m_axi_arsize  = m_axi_a.arsize ;
  assign m_axi_arburst = m_axi_a.arburst;

  fifo_element #(
    .WIDTH          ($bits(axi4_ar_if_t)),
    .DEPTH          (2),
    .TYPE_ARRAY     (8'h12),
    .DO_RESET_DATA  (1'b0),
    .RESET_DATA_VAL (0)
  ) fifo_element (
    .clk     (clk),
    .s_rst_n (s_rst_n),

    .in_data (s0_axi),
    .in_vld  (s0_axi_arvalid),
    .in_rdy  (s0_axi_arready),

    .out_data(m_axi_a),
    .out_vld (m_axi_arvalid),
    .out_rdy (m_axi_arready)
  );

  assign req_send_axi_cmd = s0_axi_arvalid & s0_axi_arready;

// ============================================================================================== //
// Data reception process
// ============================================================================================== //
  //-------------------------
  // Process data
  //-------------------------
  logic [GLWE_SUBW_COEF_NB-1:0][MOD_Q_W-1:0] r1_data;
  logic                                      r1_data_vld;
  logic                                      r1_data_rdy;
  load_glwe_cmd_t                            r1_cmd;
  logic                                      r1_batch_last;
  logic                                      r1_pbs_last;
  logic [SUBW_ADD_W-1:0]                     r1_pid_add_ofs;

  logic [AXI4_WORD_PER_GLWE_BODY-1:0]        r0_axi_word_cnt;
  logic [AXI4_WORD_PER_GLWE_BODY-1:0]        r0_axi_word_cntD;
  logic                                      r0_last_axi_word_cnt;

  logic                                      r1_last_axi_word_cnt;

  assign r0_last_axi_word_cnt = r0_axi_word_cnt == AXI4_WORD_PER_GLWE_BODY-1;
  assign r0_axi_word_cntD     = r0_axi_vld && r0_axi_rdy ? r0_last_axi_word_cnt ? '0 : r0_axi_word_cnt + 1 : r0_axi_word_cnt;

  assign rcp_fifo_out_rdy     = r0_axi_vld & r0_axi_rdy & r0_last_axi_word_cnt;

  always_ff @(posedge clk)
    if (!s_rst_n) r0_axi_word_cnt <= '0;
    else          r0_axi_word_cnt <= r0_axi_word_cntD;

  //= Reorg AXI input data
  generate
    if (GLWE_SUBW_PER_AXI4_WORD > 1) begin : gen_glwe_subw_per_axi4_word_gt_1
      localparam int LAST_OUT_CNT_TMP = TOTAL_SUBW_NB % GLWE_SUBW_PER_AXI4_WORD;
      localparam int LAST_OUT_CNT     = LAST_OUT_CNT_TMP == 0 ? GLWE_SUBW_PER_AXI4_WORD-1 : LAST_OUT_CNT_TMP-1;

      logic [GLWE_SUBW_PER_AXI4_WORD-1:0][GLWE_SUBW_COEF_NB-1:0][GLWE_ACS_W-1:0] sr_data;
      logic [GLWE_SUBW_PER_AXI4_WORD-1:0][GLWE_SUBW_COEF_NB-1:0][GLWE_ACS_W-1:0] sr_data_tmp;
      logic [GLWE_SUBW_PER_AXI4_WORD-1:0][GLWE_SUBW_COEF_NB-1:0][GLWE_ACS_W-1:0] sr_dataD;

      // Count number of subwords
      logic [GLWE_SUBW_PER_AXI4_WORD_W-1:0]                                      sr_out_cnt;
      logic [GLWE_SUBW_PER_AXI4_WORD_W-1:0]                                      sr_out_cntD;
      logic                                                                      sr_last_out_cnt;
      logic                                                                      sr_avail;
      logic                                                                      sr_availD;

      assign sr_data_tmp = sr_data >> (GLWE_ACS_W * GLWE_SUBW_COEF_NB);
      assign sr_dataD    = r0_axi_vld  && r0_axi_rdy  ? r0_axi_if.rdata :
                           //r1_data_vld && r1_data_rdy ? {sr_data[GLWE_SUBW_PER_AXI4_WORD-1],sr_data[GLWE_SUBW_PER_AXI4_WORD-1:1]} : sr_data;
                           r1_data_vld && r1_data_rdy ? sr_data_tmp : sr_data; // To avoid warning - when this branch of the generate is not used.

      assign sr_out_cntD     = r1_data_vld && r1_data_rdy ? sr_last_out_cnt ? '0 : sr_out_cnt + 1 : sr_out_cnt;
      assign sr_last_out_cnt = (sr_out_cnt == GLWE_SUBW_PER_AXI4_WORD -1) | (r1_last_axi_word_cnt & sr_out_cnt == LAST_OUT_CNT);
      assign sr_availD       = r0_axi_vld  && r0_axi_rdy  ? 1'b1 :
                               r1_data_vld && r1_data_rdy && sr_last_out_cnt ? 1'b0 : sr_avail;

      assign r1_data_vld   = sr_avail;
      assign r0_axi_rdy    = ~sr_avail | (r1_data_rdy & sr_last_out_cnt);
      assign r1_pbs_last   = r1_last_axi_word_cnt & sr_last_out_cnt;
      assign r1_batch_last = r1_pbs_last;

      always_comb
        for (int y=0; y<GLWE_SUBW_COEF_NB; y=y+1)
          r1_data[y] = sr_data[0][y][0+:MOD_Q_W]; // extract the MOD_Q_W bits

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

      // Keep command and counters for r1 phase.
      load_glwe_cmd_t            r1_cmdD;
      logic                      r1_last_axi_word_cntD;
      logic [SUBW_ADD_W-1:0]     r1_pid_add_ofsD;

      assign r1_cmdD               = r0_axi_vld  && r0_axi_rdy ? rcp_fifo_out_cmd : r1_cmd;
      assign r1_last_axi_word_cntD = r0_axi_vld  && r0_axi_rdy ? r0_last_axi_word_cnt : r1_last_axi_word_cnt;
      assign r1_pid_add_ofsD       = r0_axi_vld  && r0_axi_rdy ? rcp_fifo_out_pid_add_ofs : r1_pid_add_ofs;

      always_ff @(posedge clk) begin
        r1_cmd               <= r1_cmdD;
        r1_last_axi_word_cnt <= r1_last_axi_word_cntD;
        r1_pid_add_ofs       <= r1_pid_add_ofsD;
      end

    end // gen_GLWE_SUBW_PER_AXI4_WORD_gt_1
    else begin : gen_glwe_subw_per_axi4_word_eq_1
// pragma translate_off
      if (GLWE_SUBW_PER_AXI4_WORD != 1) begin
        initial begin
          $fatal(1,"ERROR> Incoherent GLWE_SUBW_PER_AXI4_WORD (%0d) value. Should be 1",GLWE_SUBW_PER_AXI4_WORD);
        end
      end
// pragma translate_on

      logic [GLWE_SUBW_COEF_NB-1:0][GLWE_ACS_W-1:0] r0_axi_data;

      assign r0_axi_data    = r0_axi_if.rdata;
      assign r1_data_vld    = r0_axi_vld;
      assign r0_axi_rdy     = r1_data_rdy;
      assign r1_pbs_last    = r1_last_axi_word_cnt;
      assign r1_batch_last  = r1_pbs_last;

      always_comb
        for (int y=0; y<GLWE_SUBW_COEF_NB; y=y+1)
          r1_data[y] = r0_axi_data[y][0+:MOD_Q_W]; // extract the MOD_Q_W bits

      // Keep command and counters for r1 phase.
      assign r1_cmd               = rcp_fifo_out_cmd;
      assign r1_last_axi_word_cnt = r0_last_axi_word_cnt;
      assign r1_pid_add_ofs       = rcp_fifo_out_pid_add_ofs;

    end // gen_glwe_subw_per_axi4_word_eq_1
  endgenerate

  //== Counter
  logic [TOTAL_SUBW_NB_W-1:0] r1_subw_cnt;
  logic [TOTAL_SUBW_NB_W-1:0] r1_subw_cntD;
  logic                       r1_last_subw_cnt;

  logic [SUBW_ADD_W-1:0]      r1_subw_add_ofsD;
  logic [SUBW_ADD_W-1:0]      r1_subw_add;
  logic                       r1_gram_avail;

  logic                                        r1_ram_wr_en;
  logic [GRAM_ID_W-1:0]                        r1_ram_wr_grid;
  logic [GLWE_SUBW_COEF_NB-1:0][MOD_Q_W-1:0]   r1_ram_wr_data;
  logic                                        r1_ram_wr_batch_last;
  logic                                        r1_ram_wr_pbs_last;
  logic [GLWE_SUBW_NB-1:0]                     r1_ram_wr_subw_en;
  logic [GLWE_RAM_ADD_W-1:0]                   r1_ram_wr_add;

  assign r1_last_subw_cnt = r1_subw_cnt == TOTAL_SUBW_NB-1;
  assign r1_subw_cntD     = r1_data_vld && r1_data_rdy ? r1_last_subw_cnt ? '0 : r1_subw_cnt + 1 : r1_subw_cnt;
  assign r1_subw_add      = r1_pid_add_ofs + r1_subw_cnt;

  always_ff @(posedge clk)
    if (!s_rst_n) r1_subw_cnt    <= '0;
    else          r1_subw_cnt    <= r1_subw_cntD;

  assign r1_gram_avail = gram_avail_1h[r1_cmd.pid.grid];
  assign r1_data_rdy   = r1_gram_avail;

  //== Output
  // NOTE : arbiter access authorization used here. Command must be sent in 2 cycles exactly.
  // This is done in all the GRAM masters.
  assign r1_ram_wr_en         = r1_data_vld & r1_gram_avail;
  assign r1_ram_wr_grid       = r1_cmd.pid.grid;
  assign r1_ram_wr_data       = r1_data;
  assign r1_ram_wr_batch_last = r1_batch_last;
  assign r1_ram_wr_pbs_last   = r1_pbs_last;

  if (GLWE_SUBW_NB == 1) begin
    assign r1_ram_wr_subw_en = 1;
    assign r1_ram_wr_add     = r1_subw_add;
  end
  else begin
    assign r1_ram_wr_subw_en = 1 << r1_subw_add[GLWE_SUBW_NB_SZ-1:0];  // Used only for GLWE
    assign r1_ram_wr_add     = r1_subw_add >> GLWE_SUBW_NB_SZ;
  end

// ============================================================================================== //
// Done
// ============================================================================================== //
  logic ldg_seq_doneD;

  assign ldg_seq_doneD = r1_ram_wr_en & r1_ram_wr_pbs_last;

  always_ff @(posedge clk)
    if (!s_rst_n) ldg_seq_done <= 1'b0;
    else          ldg_seq_done <= ldg_seq_doneD;

// ============================================================================================== //
// Format the output
// ============================================================================================== //
// ---------------------------------------------------------------------------------------------- //
// Extend to RxPSI
// ---------------------------------------------------------------------------------------------- //
  // Note : GLWE_SUBW_NB * GLWE_SUBW_COEF_NB = PSI*R
  logic [PSI-1:0][R-1:0]                     r2_ram_wr_en;
  logic [GRAM_NB-1:0]                        r2_ram_wr_grid_1h;
  logic [PSI-1:0][R-1:0][MOD_Q_W-1:0]        r2_ram_wr_data;
  logic [PSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0] r2_ram_wr_add;

  logic [GLWE_SUBW_NB-1:0][GLWE_SUBW_COEF_NB-1:0]                     r2_ram_wr_enD;
  logic [GLWE_SUBW_NB-1:0][GLWE_SUBW_COEF_NB-1:0][MOD_Q_W-1:0]        r2_ram_wr_dataD;
  logic [GLWE_SUBW_NB-1:0][GLWE_SUBW_COEF_NB-1:0][GLWE_RAM_ADD_W-1:0] r2_ram_wr_addD;
  logic [GRAM_NB-1:0]                                                 r2_ram_wr_grid_1hD;

  assign r2_ram_wr_grid_1hD = 1 << r1_ram_wr_grid;

  always_comb
    for (int i=0; i<GLWE_SUBW_NB; i=i+1) begin
      r2_ram_wr_enD[i]   = {GLWE_SUBW_COEF_NB{r1_ram_wr_en & r1_ram_wr_subw_en[i]}};
      r2_ram_wr_dataD[i] = r1_ram_wr_data;
      r2_ram_wr_addD[i]  = {GLWE_SUBW_COEF_NB{r1_ram_wr_add}};
    end

  always_ff @(posedge clk)
    if (!s_rst_n) r2_ram_wr_en <= '0;
    else          r2_ram_wr_en <= r2_ram_wr_enD;

  always_ff @(posedge clk) begin
    r2_ram_wr_grid_1h <= r2_ram_wr_grid_1hD;
    r2_ram_wr_data    <= r2_ram_wr_dataD;
    r2_ram_wr_add     <= r2_ram_wr_addD;
  end

// ---------------------------------------------------------------------------------------------- //
// Extend to GRAM_NB
// ---------------------------------------------------------------------------------------------- //
  logic [GRAM_NB-1:0][PSI-1:0][R-1:0]                     r3_ram_wr_en;
  logic [GRAM_NB-1:0][PSI-1:0][R-1:0][MOD_Q_W-1:0]        r3_ram_wr_data;
  logic [GRAM_NB-1:0][PSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0] r3_ram_wr_add;

  logic [GRAM_NB-1:0][PSI-1:0][R-1:0]                     r3_ram_wr_enD;
  logic [GRAM_NB-1:0][PSI-1:0][R-1:0][MOD_Q_W-1:0]        r3_ram_wr_dataD;
  logic [GRAM_NB-1:0][PSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0] r3_ram_wr_addD;

  assign r3_ram_wr_dataD = {GRAM_NB{r2_ram_wr_data}};
  assign r3_ram_wr_addD  = {GRAM_NB{r2_ram_wr_add}};

  always_comb
    for (int i=0; i<GRAM_NB; i=i+1)
      r3_ram_wr_enD[i] = {R*PSI{r2_ram_wr_grid_1h[i]}} & r2_ram_wr_en;

  always_ff @(posedge clk)
    if (!s_rst_n) r3_ram_wr_en <= '0;
    else          r3_ram_wr_en <= r3_ram_wr_enD;

  always_ff @(posedge clk) begin
    r3_ram_wr_data <= r3_ram_wr_dataD;
    r3_ram_wr_add  <= r3_ram_wr_addD;
  end

// ---------------------------------------------------------------------------------------------- //
// Send
// ---------------------------------------------------------------------------------------------- //
  assign glwe_ram_wr_en   = r3_ram_wr_en;
  assign glwe_ram_wr_add  = r3_ram_wr_add;
  assign glwe_ram_wr_data = r3_ram_wr_data;

// ============================================================================================== //
// Duration signals for register if
// ============================================================================================== //
  logic ldg_rif_req_durD;
  logic ldg_rif_rcp_durD;

  assign ldg_rif_req_durD = (req_fifo_out_vld && req_fifo_out_rdy) ? 1'b0 : req_fifo_out_vld;
  assign ldg_rif_rcp_durD = (rcp_fifo_out_vld && rcp_fifo_out_rdy) ? 1'b0 : rcp_fifo_out_vld;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      ldg_rif_req_dur <= 1'b0;
      ldg_rif_rcp_dur <= 1'b0;
    end
    else begin
      ldg_rif_req_dur <= ldg_rif_req_durD;
      ldg_rif_rcp_dur <= ldg_rif_rcp_durD;
    end

endmodule
