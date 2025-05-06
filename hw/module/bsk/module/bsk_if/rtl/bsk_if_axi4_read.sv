// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : bsk interface
// ----------------------------------------------------------------------------------------------
//
// This module deals with the memory read command via AXI4.
//
// ==============================================================================================

module bsk_if_axi4_read
  import param_tfhe_pkg::*;
  import param_ntt_pkg::*;
  import top_common_param_pkg::*;
  import ntt_core_common_param_pkg::*;
  import bsk_mgr_common_param_pkg::*;
  import bsk_if_common_param_pkg::*;
  import axi_if_bsk_axi_pkg::*;
  import axi_if_common_param_pkg::*;
(
    input logic                                                        clk,        // clock
    input logic                                                        s_rst_n,    // synchronous reset

    input logic                                                        bsk_mem_avail,
    input logic [BSK_PC_MAX-1:0][AXI4_ADD_W-1: 0]                      bsk_mem_addr,

    // AXI4 Master interface
    // NB: Only AXI Read channel exposed here
    output logic [BSK_PC-1:0][AXI4_ID_W-1:0]                           m_axi4_arid,
    output logic [BSK_PC-1:0][AXI4_ADD_W-1:0]                          m_axi4_araddr,
    output logic [BSK_PC-1:0][7:0]                                     m_axi4_arlen,
    output logic [BSK_PC-1:0][2:0]                                     m_axi4_arsize,
    output logic [BSK_PC-1:0][1:0]                                     m_axi4_arburst,
    output logic [BSK_PC-1:0]                                          m_axi4_arvalid,
    input  logic [BSK_PC-1:0]                                          m_axi4_arready,
    input  logic [BSK_PC-1:0][AXI4_ID_W-1:0]                           m_axi4_rid,
    input  logic [BSK_PC-1:0][AXI4_DATA_W-1:0]                         m_axi4_rdata,
    input  logic [BSK_PC-1:0][1:0]                                     m_axi4_rresp,
    input  logic [BSK_PC-1:0]                                          m_axi4_rlast,
    input  logic [BSK_PC-1:0]                                          m_axi4_rvalid,
    output logic [BSK_PC-1:0]                                          m_axi4_rready,

    // BSK manager
    output logic [BSK_CUT_NB-1:0]                                      bsk_mgr_wr_en,
    output logic [BSK_CUT_NB-1:0][BSK_CUT_FCOEF_NB-1:0][MOD_NTT_W-1:0] bsk_mgr_wr_data,
    output logic [BSK_CUT_NB-1:0][BSK_RAM_ADD_W-1:0]                   bsk_mgr_wr_add,
    output logic [BSK_CUT_NB-1:0][GLWE_K_P1_W-1:0]                     bsk_mgr_wr_g_idx,
    output logic [BSK_CUT_NB-1:0][BSK_SLOT_W-1:0]                      bsk_mgr_wr_slot,
    output logic [BSK_CUT_NB-1:0][LWE_K_W-1:0]                         bsk_mgr_wr_br_loop,

    // bsk_if_cache_control
    input  logic                                                       cctrl_rd_vld,
    output logic                                                       cctrl_rd_rdy,
    input  logic [BSK_READ_CMD_W-1:0]                                  cctrl_rd_cmd,
    output logic                                                       rd_cctrl_slot_done, // bsk slice read from mem
    output logic [BSK_SLOT_W-1:0]                                      rd_cctrl_slot_id,

    // debug info
    output logic [BSK_PC-1:0]                                          load_bsk_pc_recp_dur
);

// ============================================================================================== //
// localparam
// ============================================================================================== //
  localparam int                RECP_FIFO_DEPTH  = 8; // TOREVIEW : according to memory latency.
  localparam [BSK_PC-1:0][31:0] BSK_CUT_PER_PC_A = get_cut_per_pc(BSK_CUT_NB, BSK_PC);
  localparam [BSK_PC-1:0][31:0] BSK_CUT_OFS_A    = get_cut_ofs(BSK_CUT_PER_PC_A);
  localparam int                PENDING_SLOT_NB  = 2; // If not 2, adapt the associated fifo_element type.
  localparam int                PENDING_SLOT_WW  = $clog2(PENDING_SLOT_NB+1);

  //== Check
  generate
    if (BSK_CUT_FCOEF_NB > BSK_COEF_PER_AXI4_WORD && (BSK_CUT_FCOEF_NB / BSK_COEF_PER_AXI4_WORD)*BSK_COEF_PER_AXI4_WORD != BSK_CUT_FCOEF_NB ) begin : __UNSUPPORTED_BSK_CUT_FCOEF_NB__
      $fatal(1,"> ERROR: Unsupported : BSK_CUT_FCOEF_NB (%0d) should be a multiple of BSK_COEF_PER_AXI4_WORD BSK_CUT_FCOEF_NB",BSK_CUT_FCOEF_NB,BSK_COEF_PER_AXI4_WORD);
    end
    if (BSK_CUT_FCOEF_NB < BSK_COEF_PER_AXI4_WORD && (BSK_COEF_PER_AXI4_WORD/BSK_CUT_FCOEF_NB)*BSK_CUT_FCOEF_NB != BSK_COEF_PER_AXI4_WORD ) begin : __UNSUPPORTED_BSK_CUT_FCOEF_NB_BIS__
      $fatal(1,"> ERROR: Unsupported : BSK_CUT_FCOEF_NB (%0d) should divide BSK_COEF_PER_AXI4_WORD (%0d)",BSK_CUT_FCOEF_NB,BSK_COEF_PER_AXI4_WORD);
    end
  endgenerate

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // Do nothing
    end
    else begin
      if (bsk_mem_avail) begin
        for (int i=0; i<BSK_PC; i=i+1) begin
          assert (bsk_mem_addr[i][AXI4_DATA_BYTES_W-1:0] == 0)
          else begin
            $fatal(1,"%t > ERROR: bsk_mem_addr[%0d] should be AXI4_DATA_BYTES (%0d) aligned.",$time,i,AXI4_DATA_BYTES);
          end
        end
      end
    end
// pragma translate_on

// ============================================================================================== //
// Constant functions
// ============================================================================================== //
  function [BSK_PC-1:0][31:0] get_cut_per_pc (int bsk_cut_nb, int bsk_pc);
    bit [BSK_PC-1:0][31:0] cut_per_pc;
    int cut_cnt;
    int cut_dist;
    cut_dist = (bsk_cut_nb + bsk_pc - 1) / bsk_pc;
    cut_cnt  = bsk_cut_nb;
    for (int i=0; i<BSK_PC; i=i+1) begin
      cut_per_pc[i] = cut_cnt < cut_dist ? cut_cnt : cut_dist;
      cut_cnt = cut_cnt - cut_dist;
    end
    return cut_per_pc;
  endfunction

  function [BSK_PC-1:0][31:0] get_cut_ofs (input [BSK_PC-1:0][31:0] cut_per_pc);
    bit [BSK_PC-1:0][31:0] cut_ofs;
    cut_ofs[0] = '0;
    for (int i=1; i<BSK_PC; i=i+1) begin
      cut_ofs[i] = cut_ofs[i-1] + cut_per_pc[i-1];
    end
    return cut_ofs;
  endfunction

// ============================================================================================== //
// Input command pipe
// ============================================================================================== //
  logic                      s0_cctrl_rd_vld_tmp;
  logic                      s0_cctrl_rd_rdy_tmp;
  bsk_read_cmd_t             s0_cctrl_rd_cmd_tmp;
  logic [BSK_PC:0]           s0_cctrl_rd_vld_tmp2;
  logic [BSK_PC:0]           s0_cctrl_rd_rdy_tmp2;
  logic                      rcp_vld;
  logic                      rcp_rdy;
  logic [BSK_SLOT_W-1:0]     rcp_slot_id;


  // Use a type 3 : no need to rush.
  fifo_element #(
    .WIDTH          (BSK_READ_CMD_W),
    .DEPTH          (1),
    .TYPE_ARRAY     (3),
    .DO_RESET_DATA  (1'b0),
    .RESET_DATA_VAL (0)
  ) cctrl_rd_fifo_element (
    .clk     (clk),
    .s_rst_n (s_rst_n),

    .in_data (cctrl_rd_cmd),
    .in_vld  (cctrl_rd_vld),
    .in_rdy  (cctrl_rd_rdy),

    .out_data(s0_cctrl_rd_cmd_tmp),
    .out_vld (s0_cctrl_rd_vld_tmp),
    .out_rdy (s0_cctrl_rd_rdy_tmp)
  );

  // Fork the command to the BSK_PC paths + slot_id path
  assign s0_cctrl_rd_rdy_tmp = &s0_cctrl_rd_rdy_tmp2;
  always_comb
    for (int i=0; i<BSK_PC+1; i=i+1) begin
      logic [BSK_PC:0] mask;
      mask = (1 << i); // To avoid rdy/vld dependency
      s0_cctrl_rd_vld_tmp2[i] = s0_cctrl_rd_vld_tmp & (&(s0_cctrl_rd_rdy_tmp2 | mask));
    end

  // This is used to keep track of the slot_id that is being processed.
  fifo_element #(
    .WIDTH          (BSK_SLOT_W),
    .DEPTH          (PENDING_SLOT_NB+1),
    .TYPE_ARRAY     (12'h122), // Update this if PENDING_SLOT_NB != 2
    .DO_RESET_DATA  (0),
    .RESET_DATA_VAL (0)
  ) slot_id_fifo_element (
    .clk     (clk),
    .s_rst_n (s_rst_n),

    .in_data (s0_cctrl_rd_cmd_tmp.slot_id),
    .in_vld  (s0_cctrl_rd_vld_tmp2[BSK_PC]),
    .in_rdy  (s0_cctrl_rd_rdy_tmp2[BSK_PC]),

    .out_data(rcp_slot_id),
    .out_vld (rcp_vld),
    .out_rdy (rcp_rdy)
  );

// ============================================================================================== //
// Output
// ============================================================================================== //
  logic [BSK_CUT_NB-1:0]                                      bsk_mgr_wr_enD;
  logic [BSK_CUT_NB-1:0][BSK_CUT_FCOEF_NB-1:0][MOD_NTT_W-1:0] bsk_mgr_wr_dataD;
  logic [BSK_CUT_NB-1:0][BSK_RAM_ADD_W-1:0]                   bsk_mgr_wr_addD;
  logic [BSK_CUT_NB-1:0][GLWE_K_P1_W-1:0]                     bsk_mgr_wr_g_idxD;
  logic [BSK_CUT_NB-1:0][BSK_SLOT_W-1:0]                      bsk_mgr_wr_slotD;
  logic [BSK_CUT_NB-1:0][LWE_K_W-1:0]                         bsk_mgr_wr_br_loopD;

  logic [BSK_PC-1:0]                                          slot_done; // pulse
  logic [BSK_PC-1:0]                                          slot_doneD;
  logic [BSK_PC-1:0][PENDING_SLOT_WW-1:0]                     slot_done_cnt; // keep track of the "done" of each PC
  logic [BSK_PC-1:0][PENDING_SLOT_WW-1:0]                     slot_done_cntD;
  logic [BSK_PC-1:0]                                          slot_done_present;
  logic                                                       rd_cctrl_slot_doneD;
  logic [BSK_SLOT_W-1:0]                                      rd_cctrl_slot_idD;

  logic [BSK_PC-1:0]                                          load_bsk_pc_recp_durD;

  always_ff @(posedge clk)
    if (!s_rst_n)
      load_bsk_pc_recp_dur <= '0;
    else
      load_bsk_pc_recp_dur <= load_bsk_pc_recp_durD;

  assign rd_cctrl_slot_doneD = &slot_done_present;
  assign rd_cctrl_slot_idD   = rcp_slot_id;

  assign rcp_rdy = rd_cctrl_slot_doneD;

  always_comb
    for (int i=0; i<BSK_PC; i=i+1) begin
      slot_done_present[i] = slot_done_cnt[i] > 0;
      slot_done_cntD[i] = rd_cctrl_slot_doneD && !slot_done[i] ? slot_done_cnt[i]-1 :
                          !rd_cctrl_slot_doneD && slot_done[i] ? slot_done_cnt[i]+1 : slot_done_cnt[i];
    end

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      slot_done          <= '0;
      slot_done_cnt      <= '0;
      rd_cctrl_slot_done <= 1'b0;
      bsk_mgr_wr_en      <= '0;
    end
    else begin
      slot_done          <= slot_doneD     ;
      slot_done_cnt      <= slot_done_cntD;
      rd_cctrl_slot_done <= rd_cctrl_slot_doneD;
      bsk_mgr_wr_en      <= bsk_mgr_wr_enD;
    end

  always_ff @(posedge clk) begin
    bsk_mgr_wr_data    <= bsk_mgr_wr_dataD;
    bsk_mgr_wr_add     <= bsk_mgr_wr_addD;
    bsk_mgr_wr_g_idx   <= bsk_mgr_wr_g_idxD;
    bsk_mgr_wr_slot    <= bsk_mgr_wr_slotD;
    bsk_mgr_wr_br_loop <= bsk_mgr_wr_br_loopD;
    rd_cctrl_slot_id   <= rd_cctrl_slot_idD;
  end

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // no nothing
    end
    else begin
      if (rcp_rdy)
        assert(rcp_vld)
        else begin
          $fatal(1,"%t > ERROR: No slot_id available when needed!", $time);
        end
    end
// pragma translate_on

// ============================================================================================== //
// For each PC
// ============================================================================================== //
  // Load output g_idx, by g_idx. (Called G column)
  // Within a g_idx "column", the INTL_L levels and polynomials are interleaved.
  // The slots are stored one after the other in the RAM.
  //
  // Deal with the BSK_PC pseudo-channels in parallel.
  generate
    for (genvar gen_pc=0; gen_pc<BSK_PC; gen_pc=gen_pc+1) begin : gen_pc_loop
      localparam int BSK_CUT_PER_PC_L            = BSK_CUT_PER_PC_A[gen_pc];
      localparam int BSK_CUT_OFS_L               = BSK_CUT_OFS_A[gen_pc];
      localparam int PROC_GCOL_COEF_NB           = ((N*GLWE_K_P1*PBS_L)+(BSK_CUT_NB/BSK_CUT_PER_PC_L)-1) / (BSK_CUT_NB/BSK_CUT_PER_PC_L);
      localparam int AXI4_WORD_PER_BSK_GCOL_L    = (PROC_GCOL_COEF_NB*BSK_ACS_W + AXI4_DATA_W-1)/AXI4_DATA_W;
      localparam int AXI4_WORD_PER_BSK_GCOL_L_W  = $clog2(AXI4_WORD_PER_BSK_GCOL_L) == 0 ? 1 : $clog2(AXI4_WORD_PER_BSK_GCOL_L);
      localparam int AXI4_WORD_PER_BSK_GCOL_L_WW = $clog2(AXI4_WORD_PER_BSK_GCOL_L+1) == 0 ? 1 : $clog2(AXI4_WORD_PER_BSK_GCOL_L+1);
      localparam int BSK_PC_SLOT_BYTES_L         = AXI4_WORD_PER_BSK_GCOL_L * AXI4_DATA_BYTES * GLWE_K_P1;

      localparam int BSK_BLOCK_PER_AXI4_WORD = BSK_COEF_PER_AXI4_WORD / BSK_CUT_FCOEF_NB;
      // Number of cuts that are processed in parallel
      localparam int PROC_CUT_NB             = BSK_BLOCK_PER_AXI4_WORD == 0 ? 1 :
                                               BSK_CUT_PER_PC_L > BSK_BLOCK_PER_AXI4_WORD ? BSK_BLOCK_PER_AXI4_WORD : BSK_CUT_PER_PC_L;
      localparam int PROC_CUT_GROUP_NB       = BSK_CUT_PER_PC_L / PROC_CUT_NB;
      localparam int PROC_CUT_GROUP_W        = $clog2(PROC_CUT_GROUP_NB) == 0 ? 1 : $clog2(PROC_CUT_GROUP_NB);

// ---------------------------------------------------------------------------------------------- //
// Input pipe
// ---------------------------------------------------------------------------------------------- //
      logic          s0_cctrl_rd_vld;
      logic          s0_cctrl_rd_rdy;
      bsk_read_cmd_t s0_cctrl_rd_cmd;
      axi4_r_if_t    m_axi4_r;
      axi4_r_if_t    r0_axi;
      logic          r0_axi_vld;
      logic          r0_axi_rdy;

      logic          s0_cctrl_rd_vld_tmp1;
      logic          s0_cctrl_rd_rdy_tmp1;
      bsk_read_cmd_t s0_cctrl_rd_cmd_tmp1;

      logic [AXI4_ADD_W-1:0] s0_cctrl_add_init;
      logic [AXI4_ADD_W-1:0] s0_cctrl_add_init_tmp1_1;
      logic [1:0][AXI4_ADD_W-1:0] s0_cctrl_add_init_tmp1;
      logic [1:0][AXI4_ADD_W-1:0] s0_cctrl_add_init_tmp2;

      // Do multiplication here due to timing constraints
      assign s0_cctrl_add_init_tmp2[0] = s0_cctrl_rd_cmd_tmp.br_loop[LWE_K_W/2-1:0]*BSK_PC_SLOT_BYTES_L;
      assign s0_cctrl_add_init_tmp2[1] = s0_cctrl_rd_cmd_tmp.br_loop[LWE_K_W-1:LWE_K_W/2]*BSK_PC_SLOT_BYTES_L;

      assign s0_cctrl_add_init_tmp1_1 = s0_cctrl_add_init_tmp1[0]
                                      + (s0_cctrl_add_init_tmp1[1] << LWE_K_W/2);

      // command
      fifo_element #(
        .WIDTH          (BSK_READ_CMD_W + 2*AXI4_ADD_W),
        .DEPTH          (1),
        .TYPE_ARRAY     (4'h3),
        .DO_RESET_DATA  (1'b0),
        .RESET_DATA_VAL (0)
      ) cctrl_rd_fifo_element_tmp2 (
        .clk     (clk),
        .s_rst_n (s_rst_n),

        .in_data ({s0_cctrl_add_init_tmp2,s0_cctrl_rd_cmd_tmp}),
        .in_vld  (s0_cctrl_rd_vld_tmp2[gen_pc]),
        .in_rdy  (s0_cctrl_rd_rdy_tmp2[gen_pc]),

        .out_data({s0_cctrl_add_init_tmp1,s0_cctrl_rd_cmd_tmp1}),
        .out_vld (s0_cctrl_rd_vld_tmp1),
        .out_rdy (s0_cctrl_rd_rdy_tmp1)
      );

      fifo_element #(
        .WIDTH          (BSK_READ_CMD_W + AXI4_ADD_W),
        .DEPTH          (PENDING_SLOT_NB), // Depth 2, to enable the other paths to start the next command, when possible.
        .TYPE_ARRAY     (8'h12),// If PENDING_SLOT_NB!=2, update this.
        .DO_RESET_DATA  (1'b0),
        .RESET_DATA_VAL (0)
      ) cctrl_rd_fifo_element_tmp1 (
        .clk     (clk),
        .s_rst_n (s_rst_n),

        .in_data ({s0_cctrl_add_init_tmp1_1,s0_cctrl_rd_cmd_tmp1}),
        .in_vld  (s0_cctrl_rd_vld_tmp1),
        .in_rdy  (s0_cctrl_rd_rdy_tmp1),

        .out_data({s0_cctrl_add_init,s0_cctrl_rd_cmd}),
        .out_vld (s0_cctrl_rd_vld),
        .out_rdy (s0_cctrl_rd_rdy)
      );

      // read data
      assign m_axi4_r.rid   = m_axi4_rid[gen_pc];
      assign m_axi4_r.rdata = m_axi4_rdata[gen_pc];
      assign m_axi4_r.rresp = m_axi4_rresp[gen_pc];
      assign m_axi4_r.rlast = m_axi4_rlast[gen_pc];

      fifo_element #(
        .WIDTH          (AXI4_R_IF_W),
        .DEPTH          (2),
        .TYPE_ARRAY     (8'h12),
        .DO_RESET_DATA  (0),
        .RESET_DATA_VAL (0)
      ) axi_r_fifo_element (
        .clk     (clk),
        .s_rst_n (s_rst_n),

        .in_data (m_axi4_r),
        .in_vld  (m_axi4_rvalid[gen_pc]),
        .in_rdy  (m_axi4_rready[gen_pc]),

        .out_data(r0_axi),
        .out_vld (r0_axi_vld),
        .out_rdy (r0_axi_rdy)
      );

// ============================================================================================== //
// Load request
// ============================================================================================== //
    //---------------------------------
    // s0
    //---------------------------------
    // This step is decomposed into 2 phases.
    // The first one consists in sending the command to the reception FIFO.
    // If this latter is full, there is no need to prepare a new request command.
    // The second one consists in building the AXI request command.

      // AXI interface
      axi4_ar_if_t                            s0_axi;
      logic                                   s0_axi_arvalid;
      logic                                   s0_axi_arready;
      logic [8:0]                             s0_axi_word_nb;

      // Counters
      logic [GLWE_K_P1_W-1:0]                 s0_g_idx;
      logic [AXI4_WORD_PER_BSK_GCOL_L_WW-1:0] s0_axi_word_remain; // counts from 0 to AXI4_WORD_PER_BSK_GCOL_L included
      logic [GLWE_K_P1_W-1:0]                 s0_g_idxD;
      logic [AXI4_WORD_PER_BSK_GCOL_L_WW-1:0] s0_axi_word_remainD;
      logic                                   s0_last_g_idx;
      logic                                   s0_last_axi_word_remain;
      logic [GLWE_K_P1_W-1:0]                 s0_g_idx_max;

      logic                                   s0_send_axi_cmd;
      logic                                   s0_recp_cmd_sent;

      assign s0_g_idx_max        = GLWE_K_P1 - 1;
      assign s0_g_idxD           = (s0_send_axi_cmd && s0_last_axi_word_remain) ? s0_last_g_idx ? '0 : s0_g_idx + 1 : s0_g_idx;
      assign s0_axi_word_remainD = s0_send_axi_cmd ? s0_last_axi_word_remain ? AXI4_WORD_PER_BSK_GCOL_L : s0_axi_word_remain - s0_axi_word_nb : s0_axi_word_remain;
      assign s0_last_g_idx       = s0_g_idx == s0_g_idx_max;
      assign s0_last_axi_word_remain = s0_axi_word_remain == s0_axi_word_nb;

      always_ff @(posedge clk)
        if (!s_rst_n) begin
          s0_g_idx           <= '0;
          s0_axi_word_remain <= AXI4_WORD_PER_BSK_GCOL_L;
        end
        else begin
          s0_g_idx           <= s0_g_idxD    ;
          s0_axi_word_remain <= s0_axi_word_remainD;
        end

      // Address
      logic [AXI4_ADD_W-1:0]    s0_add;
      logic [AXI4_ADD_W-1:0]    s0_addD;
      logic [PAGE_BYTES_WW-1:0] s0_page_word_remain;

      // compute the address offset during the cycle when the command is sent to recp FIFO
      assign s0_addD = ~s0_cctrl_rd_vld  ? s0_add :
                       ~s0_recp_cmd_sent ? bsk_mem_addr[gen_pc] + s0_cctrl_add_init : // initialize the add
                       s0_send_axi_cmd   ? s0_add + s0_axi_word_nb*AXI4_DATA_BYTES : s0_add;

      always_ff @(posedge clk)
        if (!s_rst_n) s0_add <= '0;
        else          s0_add <= s0_addD;

      assign s0_page_word_remain = PAGE_AXI4_DATA - s0_add[PAGE_BYTES_W-1:AXI4_DATA_BYTES_W];
      assign s0_axi_word_nb = s0_page_word_remain < s0_axi_word_remain ? s0_page_word_remain : s0_axi_word_remain;
      assign s0_axi.arid    = '0; // Only 1 ID is used
      assign s0_axi.arsize  = AXI4_DATA_BYTES_W;
      assign s0_axi.arburst = AXI4B_INCR;
      assign s0_axi.araddr  = s0_add;
      assign s0_axi.arlen   = s0_axi_word_nb - 1;
      assign s0_axi_arvalid = s0_cctrl_rd_vld & s0_recp_cmd_sent;

      assign s0_cctrl_rd_rdy = s0_axi_arready & s0_last_axi_word_remain & s0_last_g_idx & s0_recp_cmd_sent;

    //---------------------------------
    // to AXI read request
    //---------------------------------
      axi4_ar_if_t m_axi4_a;

      assign m_axi4_arid[gen_pc]    = m_axi4_a.arid   ;
      assign m_axi4_araddr[gen_pc]  = m_axi4_a.araddr ;
      assign m_axi4_arlen[gen_pc]   = m_axi4_a.arlen  ;
      assign m_axi4_arsize[gen_pc]  = m_axi4_a.arsize ;
      assign m_axi4_arburst[gen_pc] = m_axi4_a.arburst;

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

        .out_data(m_axi4_a),
        .out_vld (m_axi4_arvalid[gen_pc]),
        .out_rdy (m_axi4_arready[gen_pc])
      );

      assign s0_send_axi_cmd = s0_axi_arvalid & s0_axi_arready;

    // ============================================================================================== //
    // Data reception
    // ============================================================================================== //
      // Send the cctrl_rd_cmd to the reception FIFO.
      logic          s0_recp_cmd_sentD;
      bsk_read_cmd_t recp_fifo_in_cmd;
      logic          recp_fifo_in_vld;
      logic          recp_fifo_in_rdy;
      bsk_read_cmd_t recp_fifo_out_cmd;
      logic          recp_fifo_out_vld;
      logic          recp_fifo_out_rdy;

      assign s0_recp_cmd_sentD = s0_cctrl_rd_rdy ? 1'b0 :
                                 recp_fifo_in_vld && recp_fifo_in_rdy ? 1'b1 : s0_recp_cmd_sent;
      assign recp_fifo_in_vld  = s0_cctrl_rd_vld & ~s0_recp_cmd_sent;
      assign recp_fifo_in_cmd = s0_cctrl_rd_cmd;

      always_ff @(posedge clk)
        if (!s_rst_n) s0_recp_cmd_sent <= 1'b0;
        else          s0_recp_cmd_sent <= s0_recp_cmd_sentD;

      fifo_reg #(
        .WIDTH       (BSK_READ_CMD_W),
        .DEPTH       (RECP_FIFO_DEPTH),
        .LAT_PIPE_MH ({1'b1, 1'b1})
      ) recp_fifo_reg (
        .clk      (clk),
        .s_rst_n  (s_rst_n),

        .in_data  (recp_fifo_in_cmd),
        .in_vld   (recp_fifo_in_vld),
        .in_rdy   (recp_fifo_in_rdy),

        .out_data (recp_fifo_out_cmd),
        .out_vld  (recp_fifo_out_vld),
        .out_rdy  (recp_fifo_out_rdy)
      );

      assign load_bsk_pc_recp_durD[gen_pc] = (recp_fifo_out_vld && recp_fifo_out_rdy) ? 1'b0 : recp_fifo_out_vld;

      //---------------------------------------
      // Process data
      //---------------------------------------
      logic [PROC_CUT_NB-1:0][BSK_CUT_FCOEF_NB-1:0][MOD_NTT_W-1:0] r1_data;
      logic                                                        r1_data_vld;
      logic                                                        r1_data_rdy;
      bsk_read_cmd_t                              r1_cmd;
      bsk_read_cmd_t                              r1_cmdD;
      logic [GLWE_K_P1_W-1:0]                     r1_g_idx;
      logic [GLWE_K_P1_W-1:0]                     r1_g_idxD;

      logic [GLWE_K_P1_W-1:0]                     r0_g_cnt;
      logic [AXI4_WORD_PER_BSK_GCOL_L_W-1:0]      r0_axi_word_cnt;
      logic [GLWE_K_P1_W-1:0]                     r0_g_cntD;
      logic [AXI4_WORD_PER_BSK_GCOL_L_W-1:0]      r0_axi_word_cntD;
      logic                                       r0_last_g_cnt;
      logic                                       r0_last_axi_word_cnt;
      logic [GLWE_K_P1_W-1:0]                     r0_g_cnt_max;

      logic [BSK_RAM_ADD_W-1:0]                   r1_add_ofs;
      logic [BSK_RAM_ADD_W-1:0]                   r1_add_ofsD;

      logic                                       r1_last_axi_word_cnt;
      logic                                       r1_last_axi_word_cntD;

      assign r0_g_cnt_max         = GLWE_K_P1-1;
      assign r0_last_axi_word_cnt = r0_axi_word_cnt == AXI4_WORD_PER_BSK_GCOL_L-1;
      assign r0_last_g_cnt        = r0_g_cnt == r0_g_cnt_max;
      assign r0_axi_word_cntD     = r0_axi_vld && r0_axi_rdy ? r0_last_axi_word_cnt ? '0 : r0_axi_word_cnt + 1 : r0_axi_word_cnt;
      assign r0_g_cntD            = r0_axi_vld && r0_axi_rdy && r0_last_axi_word_cnt ? r0_last_g_cnt ? '0 : r0_g_cnt + 1 : r0_g_cnt;
      assign r1_last_axi_word_cntD= r0_axi_vld && r0_axi_rdy ? r0_last_axi_word_cnt : r1_last_axi_word_cnt;

      assign recp_fifo_out_rdy    = r0_axi_vld & r0_axi_rdy & r0_last_axi_word_cnt & r0_last_g_cnt;

      always_ff @(posedge clk)
        if (!s_rst_n) begin
          r0_axi_word_cnt <= '0;
          r0_g_cnt        <= '0;
        end
        else begin
          r0_axi_word_cnt <= r0_axi_word_cntD;
          r0_g_cnt        <= r0_g_cntD;
        end

      // Keep command and counters for r1 phase.
      assign r1_cmdD     = r0_axi_vld && r0_axi_rdy ? recp_fifo_out_cmd : r1_cmd;
      assign r1_g_idxD   = r0_axi_vld && r0_axi_rdy ? r0_g_cnt          : r1_g_idx;
      assign r1_add_ofsD = r0_axi_vld && r0_axi_rdy ? recp_fifo_out_cmd.slot_id * BSK_SLOT_DEPTH : r1_add_ofs;
      always_ff @(posedge clk) begin
        r1_cmd       <= r1_cmdD;
        r1_g_idx     <= r1_g_idxD;
        r1_add_ofs   <= r1_add_ofsD;
        r1_last_axi_word_cnt <= r1_last_axi_word_cntD;
      end

      //= Reorg AXI input data
      if (BSK_CUT_FCOEF_NB > BSK_COEF_PER_AXI4_WORD) begin : gen_fcoef_gt_bsk_coef_per_axi4_word
        // Here PROC_CUT_NB = 1
        // A cut cannot fit inside an AXI word
        localparam int AXI4_WORD_PER_BSK_BLOCK   = BSK_CUT_FCOEF_NB / BSK_COEF_PER_AXI4_WORD;
        localparam int AXI4_WORD_PER_BSK_BLOCK_W = $clog2(AXI4_WORD_PER_BSK_BLOCK) == 0 ? 1 : $clog2(AXI4_WORD_PER_BSK_BLOCK);

        // AXI4 words are accumulated until a G column is complete
        logic [AXI4_WORD_PER_BSK_BLOCK-1:1][BSK_COEF_PER_AXI4_WORD-1:0][BSK_ACS_W-1:0] acc_data;
        logic [AXI4_WORD_PER_BSK_BLOCK-1:1][BSK_COEF_PER_AXI4_WORD-1:0][BSK_ACS_W-1:0] acc_dataD;
        logic [BSK_CUT_FCOEF_NB-1:0][BSK_ACS_W-1:0]                                    r1_data_tmp;

        logic [AXI4_WORD_PER_BSK_BLOCK_W-1:0] acc_in_cnt;
        logic [AXI4_WORD_PER_BSK_BLOCK_W-1:0] acc_in_cntD;
        logic                                 acc_last_in_cnt;

        assign acc_in_cntD     = r0_axi_vld && r0_axi_rdy ? acc_last_in_cnt ? '0 : acc_in_cnt + 1 : acc_in_cnt;
        assign acc_last_in_cnt = acc_in_cnt == AXI4_WORD_PER_BSK_BLOCK - 1;

        if (AXI4_WORD_PER_BSK_BLOCK > 2) begin
          assign acc_dataD   = r0_axi_vld && r0_axi_rdy ? {r0_axi.rdata, acc_data[AXI4_WORD_PER_BSK_BLOCK-1:2]} : acc_data;
        end
        else begin
          assign acc_dataD   = r0_axi_vld && r0_axi_rdy ? {r0_axi.rdata} : acc_data;
        end
        assign r1_data_tmp = {r0_axi.rdata, acc_data};
        assign r1_data_vld = r0_axi_vld & acc_last_in_cnt;
        assign r0_axi_rdy  = (~acc_last_in_cnt | r1_data_rdy);

        always_comb
          for (int p=0; p<BSK_CUT_FCOEF_NB; p=p+1)
            r1_data[0][p] = r1_data_tmp[p][0+:MOD_NTT_W];

        always_ff @(posedge clk)
          if (!s_rst_n) acc_in_cnt <= '0;
          else          acc_in_cnt <= acc_in_cntD;

        always_ff @(posedge clk)
          acc_data <= acc_dataD;
      end
      else begin : gen_fcoef_le_bsk_coef_per_axi4_word
        // One or several cuts can fit inside the AXI word
        localparam int PROC_COEF_NB            = PROC_CUT_NB * BSK_CUT_FCOEF_NB;
        localparam int PROC_BLOCK_NB           = BSK_BLOCK_PER_AXI4_WORD / PROC_CUT_NB;
        localparam int PROC_BLOCK_NB_W         = $clog2(PROC_BLOCK_NB) == 0 ? 1 : $clog2(PROC_BLOCK_NB);
        localparam int PROC_GCOL_BLOCK_NB      = PROC_GCOL_COEF_NB / PROC_COEF_NB;
        localparam int LAST_OUT_CNT_TMP        = PROC_GCOL_BLOCK_NB % PROC_BLOCK_NB;
        localparam int LAST_OUT_CNT            = LAST_OUT_CNT_TMP == 0 ? BSK_BLOCK_PER_AXI4_WORD-1 : LAST_OUT_CNT_TMP-1;

        logic [PROC_BLOCK_NB-1:0][PROC_COEF_NB-1:0][BSK_ACS_W-1:0] sr_data;
        logic [PROC_BLOCK_NB-1:0][PROC_COEF_NB-1:0][BSK_ACS_W-1:0] sr_data_tmp;
        logic [PROC_BLOCK_NB-1:0][PROC_COEF_NB-1:0][BSK_ACS_W-1:0] sr_dataD;

        logic [PROC_BLOCK_NB_W-1:0]                                sr_out_cnt;
        logic [PROC_BLOCK_NB_W-1:0]                                sr_out_cntD;
        logic                                                      sr_last_out_cnt;
        logic                                                      sr_avail;
        logic                                                      sr_availD;

        assign sr_data_tmp = sr_data >> (BSK_ACS_W * PROC_COEF_NB);
        assign sr_dataD = r0_axi_vld && r0_axi_rdy  ? r0_axi.rdata :
                          //r1_data_vld && r1_data_rdy ? {sr_data[PROC_BLOCK_NB-1],sr_data[PROC_BLOCK_NB-1:1]} : sr_data;
                          r1_data_vld && r1_data_rdy ? sr_data_tmp : sr_data; // To avoid warning - when this branch of the generate is not used.

        assign sr_out_cntD     = r1_data_vld && r1_data_rdy ? sr_last_out_cnt ? '0 : sr_out_cnt + 1 : sr_out_cnt;
        assign sr_last_out_cnt = (sr_out_cnt == PROC_BLOCK_NB -1) | (r1_last_axi_word_cnt & sr_out_cnt == LAST_OUT_CNT);
        assign sr_availD       = r0_axi_vld  && r0_axi_rdy  ? 1'b1 :
                                 r1_data_vld && r1_data_rdy && sr_last_out_cnt ? 1'b0 : sr_avail;

        assign r1_data_vld = sr_avail;
        assign r0_axi_rdy  = ~sr_avail | (r1_data_rdy & sr_last_out_cnt);

        always_comb
          for (int c=0; c<PROC_CUT_NB; c=c+1)
            for (int p=0; p<BSK_CUT_FCOEF_NB; p=p+1) begin
              integer i;
              i = c * BSK_CUT_FCOEF_NB + p;
              r1_data[c][p] = sr_data[0][i][0+:MOD_NTT_W];
            end

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

      end //if (BSK_CUT_FCOEF_NB <= BSK_COEF_PER_AXI4_WORD)

      //== Counter
      // PROC_CUT_NB cuts is addressed per cycle.
      logic [PROC_CUT_GROUP_W-1:0] r1_cutg_id;
      logic [PROC_CUT_GROUP_W-1:0] r1_cutg_idD;
      logic [BSK_SLOT_ADD_W-1:0]   r1_slot_elt;
      logic [BSK_SLOT_ADD_W-1:0]   r1_slot_eltD;
      logic                        r1_last_slot_elt;
      logic                        r1_last_cutg_id;

      assign r1_last_cutg_id  = r1_cutg_id == PROC_CUT_GROUP_NB-1;
      assign r1_last_slot_elt = r1_slot_elt == BSK_SLOT_DEPTH-1;
      assign r1_slot_eltD     = r1_data_vld && r1_data_rdy && r1_last_cutg_id ? r1_last_slot_elt ? '0 : r1_slot_elt + 1 : r1_slot_elt;
      assign r1_cutg_idD      = r1_data_vld && r1_data_rdy ? r1_last_cutg_id ? '0 : r1_cutg_id + 1 : r1_cutg_id;

      always_ff @(posedge clk)
        if (!s_rst_n) begin
          r1_slot_elt <= '0;
          r1_cutg_id   <= '0;
        end
        else begin
          r1_slot_elt <= r1_slot_eltD;
          r1_cutg_id   <= r1_cutg_idD;
        end

      assign r1_data_rdy = 1'b1;

      //== bsk_mgr interface
      logic [BSK_CUT_PER_PC_L-1:0]                                 r1_bsk_mgr_wr_en;
      logic [PROC_CUT_NB-1:0][BSK_CUT_FCOEF_NB-1:0][MOD_NTT_W-1:0] r1_bsk_mgr_wr_data;
      logic [BSK_RAM_ADD_W-1:0]                                    r1_bsk_mgr_wr_add;
      logic [GLWE_K_P1_W-1:0]                                      r1_bsk_mgr_wr_g_idx;
      logic [BSK_SLOT_W-1:0]                                       r1_bsk_mgr_wr_slot;
      logic [LWE_K_W-1:0]                                          r1_bsk_mgr_wr_br_loop;

      logic [PROC_CUT_GROUP_NB-1:0]                                r1_bsk_mgr_wr_en_tmp;

      assign r1_bsk_mgr_wr_en_tmp = r1_data_vld << r1_cutg_id;
      always_comb
        for (int i=0; i<PROC_CUT_GROUP_NB; i=i+1)
          r1_bsk_mgr_wr_en[i*PROC_CUT_NB+:PROC_CUT_NB] = {PROC_CUT_NB{r1_bsk_mgr_wr_en_tmp[i]}};

      assign r1_bsk_mgr_wr_data    = r1_data;
      assign r1_bsk_mgr_wr_add     = r1_add_ofs + r1_slot_elt;
      assign r1_bsk_mgr_wr_g_idx   = r1_g_idx;
      assign r1_bsk_mgr_wr_slot    = r1_cmd.slot_id;
      assign r1_bsk_mgr_wr_br_loop = r1_cmd.br_loop;

      //---------------------------------------
      // Output
      //---------------------------------------
      assign bsk_mgr_wr_enD[BSK_CUT_OFS_L+:BSK_CUT_PER_PC_L]      = r1_bsk_mgr_wr_en;
      assign bsk_mgr_wr_dataD [BSK_CUT_OFS_L+:BSK_CUT_PER_PC_L]   = {PROC_CUT_GROUP_NB{r1_bsk_mgr_wr_data}};
      assign bsk_mgr_wr_addD[BSK_CUT_OFS_L+:BSK_CUT_PER_PC_L]     = {BSK_CUT_PER_PC_L{r1_bsk_mgr_wr_add}};
      assign bsk_mgr_wr_g_idxD[BSK_CUT_OFS_L+:BSK_CUT_PER_PC_L]   = {BSK_CUT_PER_PC_L{r1_bsk_mgr_wr_g_idx}};
      assign bsk_mgr_wr_slotD[BSK_CUT_OFS_L+:BSK_CUT_PER_PC_L]    = {BSK_CUT_PER_PC_L{r1_bsk_mgr_wr_slot}};
      assign bsk_mgr_wr_br_loopD[BSK_CUT_OFS_L+:BSK_CUT_PER_PC_L] = {BSK_CUT_PER_PC_L{r1_bsk_mgr_wr_br_loop}};

      //---------------------------------------
      // Process done
      //---------------------------------------
      logic [GLWE_K_P1_W-1:0] r1_g_cnt_max;

      assign r1_g_cnt_max       = GLWE_K_P1-1;
      assign slot_doneD[gen_pc] = r1_data_vld & r1_last_cutg_id & r1_last_slot_elt & (r1_g_idx == r1_g_cnt_max);

    end // for gen_pc
  endgenerate
endmodule
