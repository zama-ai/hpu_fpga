// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Testbench to test bsk_if.
// ==============================================================================================

module tb_bsk_if;
`timescale 1ns/10ps

  import param_tfhe_pkg::*;
  import param_ntt_pkg::*;
  import top_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import ntt_core_common_param_pkg::*;
  import bsk_mgr_common_param_pkg::*;
  import bsk_if_common_param_pkg::*;
  import axi_if_bsk_axi_pkg::*;
  import axi_if_common_param_pkg::*;

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int CLK_HALF_PERIOD = 1;
  localparam int ARST_ACTIVATION = 17;

  localparam int BSK_START_ADD_RANGE = 2**4;
  localparam int AXI4_ADD_W          = 24; // to ease simulation duration

  parameter int PROC_BATCH_NB        = 70;
  parameter int ITER_NB              = 2; // 1 to 16

  parameter int MEM_WR_CMD_BUF_DEPTH = 4;
  parameter int MEM_RD_CMD_BUF_DEPTH = 4;
  parameter int MEM_WR_DATA_LATENCY  = 40;
  parameter int MEM_RD_DATA_LATENCY  = 100;

  localparam [BSK_PC-1:0][31:0] BSK_CUT_PER_PC_A = get_cut_per_pc(BSK_CUT_NB, BSK_PC);
  localparam [BSK_PC-1:0][31:0] BSK_CUT_OFS_A    = get_cut_ofs(BSK_CUT_PER_PC_A);

  localparam int BSK_PC_MAX = 16; // Max of this testbench

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

// ============================================================================================== --
// type
// ============================================================================================== --
  typedef struct packed {
    logic [3:0]                 iter_loop;
    logic [LWE_K_W-1:0]         br_loop;
    logic [GLWE_K_P1_W-1:0]     g_idx;
    logic [STG_ITER_W-1:0]      stg_iter;
    logic [INTL_L_W-1:0]        l;
    logic [PSI_W-1:0]           p;
    logic [R_W-1:0]             r;
  } bsk_data_t;

  localparam int BSK_DATA_W = $bits(bsk_data_t);

  initial begin
    if ($bits(bsk_data_t) > MOD_NTT_W)
      $fatal(1,"> ERROR: bench only support MOD_NTT_W (%0d) > $bits(bsk_data_t) (%0d)", MOD_NTT_W, $bits(bsk_data_t));
  end

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
  bit [BSK_CUT_NB-1:0] error_data;
  bit [BSK_CUT_NB-1:0] error_add;

  assign error = |error_data | |error_add;

  always_ff @(posedge clk)
    if (error) begin
      $display("%t > FAILURE !", $time);
      $finish;
    end

// ============================================================================================== --
// input / output signals
// ============================================================================================== --
  // AXI4 Master interface
  // NB: Only AXI Read channel exposed here
  // /!\ Workaround : declare more AXI than needed.
  logic [BSK_PC_MAX-1:0][AXI4_ID_W-1:0]    m_axi4_arid;
  logic [BSK_PC_MAX-1:0][AXI4_ADD_W-1:0]   m_axi4_araddr;
  logic [BSK_PC_MAX-1:0][7:0]              m_axi4_arlen;
  logic [BSK_PC_MAX-1:0][2:0]              m_axi4_arsize;
  logic [BSK_PC_MAX-1:0][1:0]              m_axi4_arburst;
  logic [BSK_PC_MAX-1:0]                   m_axi4_arvalid;
  logic [BSK_PC_MAX-1:0]                   m_axi4_arready;
  logic [BSK_PC_MAX-1:0][AXI4_ID_W-1:0]    m_axi4_rid;
  logic [BSK_PC_MAX-1:0][AXI4_DATA_W-1:0]  m_axi4_rdata;
  logic [BSK_PC_MAX-1:0][1:0]              m_axi4_rresp;
  logic [BSK_PC_MAX-1:0]                   m_axi4_rlast;
  logic [BSK_PC_MAX-1:0]                   m_axi4_rvalid;
  logic [BSK_PC_MAX-1:0]                   m_axi4_rready;

  // bsk available in DDR. Ready to be ready through AXI
  logic                                    bsk_mem_avail;
  logic [BSK_PC_MAX-1:0][axi_if_bsk_axi_pkg::AXI4_ADD_W-1: 0]  bsk_mem_addr;

  // Reset the cache
  logic                                    reset_cache;
  logic                                    reset_cache_done;

  // batch start
  logic [TOTAL_BATCH_NB-1:0]               batch_start_1h; // One-hot : can only start 1 at a time.

  // bsk pointer
  logic [TOTAL_BATCH_NB-1: 0]              inc_bsk_wr_ptr;
  logic [TOTAL_BATCH_NB-1: 0]              inc_bsk_rd_ptr;

  // bsk manager
  logic [BSK_CUT_NB-1:0]                                   bsk_mgr_wr_en; // Write coefficients for 1 (stage iter,GLWE) at a time.
  logic [BSK_CUT_NB-1:0][BSK_CUT_FCOEF_NB-1:0][MOD_NTT_W-1:0] bsk_mgr_wr_data;
  logic [BSK_CUT_NB-1:0][BSK_RAM_ADD_W-1:0]                bsk_mgr_wr_add;
  logic [BSK_CUT_NB-1:0][GLWE_K_P1_W-1:0]                  bsk_mgr_wr_g_idx;
  logic [BSK_CUT_NB-1:0][BSK_SLOT_W-1:0]                   bsk_mgr_wr_slot;
  logic [BSK_CUT_NB-1:0][LWE_K_W-1:0]                      bsk_mgr_wr_br_loop;

// ============================================================================================== --
// Design under test instance
// ============================================================================================== --
  // Resize, due to bench constraints on AXI4 address range
  logic [BSK_PC_MAX-1:0][axi_if_bsk_axi_pkg::AXI4_ADD_W-1:0]   m_axi4_araddr_tmp;
  always_comb
    for (int i=0; i<BSK_PC_MAX; i=i+1)
      m_axi4_araddr[i] =  m_axi4_araddr_tmp[i][AXI4_ADD_W-1:0];


  bsk_if
  dut (
    .clk                (clk    ),
    .s_rst_n            (s_rst_n),

    .reset_cache        (reset_cache),
    .reset_cache_done   (reset_cache_done),

    .m_axi4_arid        (m_axi4_arid[BSK_PC-1:0]),
    .m_axi4_araddr      (m_axi4_araddr_tmp[BSK_PC-1:0]),
    .m_axi4_arlen       (m_axi4_arlen[BSK_PC-1:0]),
    .m_axi4_arsize      (m_axi4_arsize[BSK_PC-1:0]),
    .m_axi4_arburst     (m_axi4_arburst[BSK_PC-1:0]),
    .m_axi4_arvalid     (m_axi4_arvalid[BSK_PC-1:0]),
    .m_axi4_arready     (m_axi4_arready[BSK_PC-1:0]),
    .m_axi4_rid         (m_axi4_rid[BSK_PC-1:0]),
    .m_axi4_rdata       (m_axi4_rdata[BSK_PC-1:0]),
    .m_axi4_rresp       (m_axi4_rresp[BSK_PC-1:0]),
    .m_axi4_rlast       (m_axi4_rlast[BSK_PC-1:0]),
    .m_axi4_rvalid      (m_axi4_rvalid[BSK_PC-1:0]),
    .m_axi4_rready      (m_axi4_rready[BSK_PC-1:0]),

    .bsk_mem_avail      (bsk_mem_avail),
    .bsk_mem_addr       (bsk_mem_addr[top_common_param_pkg::BSK_PC_MAX-1:0]),

    .batch_start_1h     (batch_start_1h),

    .inc_bsk_wr_ptr     (inc_bsk_wr_ptr),
    .inc_bsk_rd_ptr     (inc_bsk_rd_ptr),

    .bsk_mgr_wr_en      (bsk_mgr_wr_en),
    .bsk_mgr_wr_data    (bsk_mgr_wr_data),
    .bsk_mgr_wr_add     (bsk_mgr_wr_add),
    .bsk_mgr_wr_g_idx   (bsk_mgr_wr_g_idx),
    .bsk_mgr_wr_slot    (bsk_mgr_wr_slot),
    .bsk_mgr_wr_br_loop (bsk_mgr_wr_br_loop)
  );

// ============================================================================================== --
// Memory
// ============================================================================================== --
  generate
    for (genvar gen_p=0; gen_p<BSK_PC_MAX; gen_p=gen_p+1) begin : gen_pc_loop
      logic [AXI4_ID_W-1:0]       axi4_bsk_awid;
      logic [AXI4_ADD_W-1:0]      axi4_bsk_awaddr;
      logic [7:0]                 axi4_bsk_awlen;
      logic [2:0]                 axi4_bsk_awsize;
      logic [1:0]                 axi4_bsk_awburst;
      logic                       axi4_bsk_awvalid;
      logic                       axi4_bsk_awready;
      logic [AXI4_DATA_W-1:0]     axi4_bsk_wdata;
      logic [(AXI4_DATA_W/8)-1:0] axi4_bsk_wstrb;
      logic                       axi4_bsk_wlast;
      logic                       axi4_bsk_wvalid;
      logic                       axi4_bsk_wready;
      logic [AXI4_ID_W-1:0]       axi4_bsk_bid;
      logic [1:0]                 axi4_bsk_bresp;
      logic                       axi4_bsk_bvalid;
      logic                       axi4_bsk_bready;

      axi4_mem #(
          .DATA_WIDTH(AXI4_DATA_W),
          .ADDR_WIDTH(AXI4_ADD_W),
          .ID_WIDTH  (AXI4_ID_W),
          .WR_CMD_BUF_DEPTH(MEM_WR_CMD_BUF_DEPTH),
          .RD_CMD_BUF_DEPTH(MEM_RD_CMD_BUF_DEPTH),
          .WR_DATA_LATENCY (MEM_WR_DATA_LATENCY),
          .RD_DATA_LATENCY (MEM_RD_DATA_LATENCY+gen_p*30),
          .USE_WR_RANDOM (1'b0),
          .USE_RD_RANDOM (1'b1)
      ) axi4_ram_bsk // {{{
      (
        .clk          (clk),
        .rst          (!s_rst_n),

        .s_axi4_awid   (axi4_bsk_awid   ),
        .s_axi4_awaddr (axi4_bsk_awaddr ),
        .s_axi4_awlen  (axi4_bsk_awlen  ),
        .s_axi4_awsize (axi4_bsk_awsize ),
        .s_axi4_awburst(axi4_bsk_awburst),
        .s_axi4_awlock ('0), // disable
        .s_axi4_awcache('0), // disable
        .s_axi4_awprot ('0), // disable
        .s_axi4_awvalid(axi4_bsk_awvalid),
        .s_axi4_awready(axi4_bsk_awready),
        .s_axi4_wdata  (axi4_bsk_wdata  ),
        .s_axi4_wstrb  (axi4_bsk_wstrb  ),
        .s_axi4_wlast  (axi4_bsk_wlast  ),
        .s_axi4_wvalid (axi4_bsk_wvalid ),
        .s_axi4_wready (axi4_bsk_wready ),
        .s_axi4_bid    (axi4_bsk_bid    ),
        .s_axi4_bresp  (axi4_bsk_bresp  ),
        .s_axi4_bvalid (axi4_bsk_bvalid ),
        .s_axi4_bready (axi4_bsk_bready ),
        .s_axi4_arid   (m_axi4_arid[gen_p]   ),
        .s_axi4_araddr (m_axi4_araddr[gen_p] ),
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

      // AXI4 bsk driver
      maxi4_if #(
        .AXI4_DATA_W(AXI4_DATA_W),
        .AXI4_ADD_W (AXI4_ADD_W),
        .AXI4_ID_W  (AXI4_ID_W)
      ) maxi4_bsk (
        .clk(clk),
        .rst_n(s_rst_n)
      );

      // Connect interface on testbench signals
      // Write channel
      assign axi4_bsk_awid         = maxi4_bsk.awid   ;
      assign axi4_bsk_awaddr       = maxi4_bsk.awaddr ;
      assign axi4_bsk_awlen        = maxi4_bsk.awlen  ;
      assign axi4_bsk_awsize       = maxi4_bsk.awsize ;
      assign axi4_bsk_awburst      = maxi4_bsk.awburst;
      assign axi4_bsk_awvalid      = maxi4_bsk.awvalid;
      assign axi4_bsk_wdata        = maxi4_bsk.wdata  ;
      assign axi4_bsk_wstrb        = maxi4_bsk.wstrb  ;
      assign axi4_bsk_wlast        = maxi4_bsk.wlast  ;
      assign axi4_bsk_wvalid       = maxi4_bsk.wvalid ;
      assign axi4_bsk_bready       = maxi4_bsk.bready ;

      assign maxi4_bsk.awready    = axi4_bsk_awready;
      assign maxi4_bsk.wready     = axi4_bsk_wready;
      assign maxi4_bsk.bid        = axi4_bsk_bid;
      assign maxi4_bsk.bresp      = axi4_bsk_bresp;
      assign maxi4_bsk.bvalid     = axi4_bsk_bvalid;

      // Read channel
      assign maxi4_bsk.arready    = 1'b0;
      assign maxi4_bsk.rid        = '0;
      assign maxi4_bsk.rdata      = 'x  ;
      assign maxi4_bsk.rresp      = '0 ;
      assign maxi4_bsk.rlast      = '0;
      assign maxi4_bsk.rvalid     = 1'b0;

    end // for gen_p
  endgenerate

// ============================================================================================== --
// Scenario
// ============================================================================================== --
  initial begin
    for (int i=0; i<BSK_PC_MAX; i=i+1)
      bsk_mem_addr[i] = {$urandom_range(0,BSK_START_ADD_RANGE-1),{AXI4_DATA_BYTES_W{1'b0}}}; // AXI4_DATA_BYTES align
  end

//---------------------------------
// FSM
//---------------------------------
  typedef enum {ST_IDLE,
                ST_FILL_BSK,
                ST_PROCESS,
                ST_WAIT,
                ST_RESET_CACHE,
                ST_DONE} state_e;

  state_e state;
  state_e next_state;
  logic st_idle;
  logic st_fill_bsk;
  logic st_wait;
  logic st_reset_cache;
  logic st_process;
  logic st_done;

  integer iter_cnt;

  logic start;
  logic fill_bsk_done;
  logic proc_done;
  logic wait_done;
  logic reset_done;

  always_comb
    case (state)
      ST_IDLE:
        next_state = start ? ST_FILL_BSK : state;
      ST_FILL_BSK:
        next_state = fill_bsk_done ? ST_PROCESS : state;
      ST_PROCESS:
        next_state = proc_done ? ST_WAIT : state;
      ST_WAIT:
        next_state = wait_done ? iter_cnt == (ITER_NB-1) ? ST_DONE : ST_RESET_CACHE : state;
      ST_RESET_CACHE:
        next_state = reset_done ? ST_IDLE : state;
      ST_DONE:
        next_state = state;
    endcase

  always_ff @(posedge clk)
    if (!s_rst_n) state <= ST_IDLE;
    else          state <= next_state;

  assign st_idle     = state == ST_IDLE;
  assign st_fill_bsk = state == ST_FILL_BSK;
  assign st_process  = state == ST_PROCESS;
  assign st_done     = state == ST_DONE;
  assign st_reset_cache = state == ST_RESET_CACHE;
  assign st_wait     = state == ST_WAIT;

//---------------------------------
// Fill bsk
//---------------------------------
  initial begin
    bsk_data_t bsk_q[BSK_PC-1:0][$];
    bsk_data_t bsk_data;
    logic [BSK_COEF_PER_AXI4_WORD-1:0][BSK_ACS_W-1:0] axi_word;

    for (int pc=0; pc<BSK_PC_MAX; pc=pc+1) begin
      case (pc)
        0: gen_pc_loop[0].maxi4_bsk.init();
        1: gen_pc_loop[1].maxi4_bsk.init();
        2: gen_pc_loop[2].maxi4_bsk.init();
        3: gen_pc_loop[3].maxi4_bsk.init();
        4: gen_pc_loop[4].maxi4_bsk.init();
        5: gen_pc_loop[5].maxi4_bsk.init();
        6: gen_pc_loop[6].maxi4_bsk.init();
        7: gen_pc_loop[7].maxi4_bsk.init();
        8: gen_pc_loop[8].maxi4_bsk.init();
        9: gen_pc_loop[9].maxi4_bsk.init();
        10: gen_pc_loop[10].maxi4_bsk.init();
        11: gen_pc_loop[11].maxi4_bsk.init();
        12: gen_pc_loop[12].maxi4_bsk.init();
        13: gen_pc_loop[13].maxi4_bsk.init();
        14: gen_pc_loop[14].maxi4_bsk.init();
        15: gen_pc_loop[15].maxi4_bsk.init();
        default: $display("%t > WARNING: init of maxi4_bsk for pc %0d could not be done", $time, pc);
      endcase
    end
    bsk_mem_avail <= 1'b0;
    fill_bsk_done <= 1'b0;
    repeat(ITER_NB) begin
      wait (st_fill_bsk);
      @(posedge clk);
      $display("%t > INFO: Load bsk iter %0d.", $time, iter_cnt);

      for (int k=0; k<LWE_K; k=k+1)
        for (int c=0; c<GLWE_K_P1; c=c+1)
          for (int stg_iter=0; stg_iter<STG_ITER_NB; stg_iter=stg_iter+1)
            for (int l=0; l<INTL_L; l=l+1)
              for (int p=0; p<PSI; p=p+1)
                for (int r=0; r<R; r=r+1) begin
                  bsk_data.iter_loop = iter_cnt;
                  bsk_data.br_loop  = k;
                  bsk_data.g_idx    = c;
                  bsk_data.stg_iter = stg_iter;
                  bsk_data.l        = l;
                  bsk_data.p        = p;
                  bsk_data.r        = r;
                  for (int pc=0; pc<BSK_PC; pc=pc+1) begin
                    if (   ((r+p*R) >= BSK_CUT_OFS_A[pc]*BSK_CUT_FCOEF_NB)
                        && ((r+p*R) < (BSK_CUT_OFS_A[pc]+BSK_CUT_PER_PC_A[pc])*BSK_CUT_FCOEF_NB))
                      bsk_q[pc].push_back(bsk_data);
                  end
                end

      for (int pc=0; pc<BSK_PC; pc=pc+1) begin
        logic [AXI4_DATA_W-1:0] axi_q[$];
        while (bsk_q[pc].size() > 0) begin
          axi_word = '0;
          for (int i=0; i<BSK_COEF_PER_AXI4_WORD; i=i+1) begin
            if (bsk_q[pc].size() == 0)
              $fatal(1,"> ERROR: bsk [pc=%0d] number mismatch!", pc);
            // Workaround : for queue pop
            axi_word[i][0+:MOD_NTT_W] = bsk_q[pc][0][BSK_DATA_W-1:0]; // complete with 0s in MSB
            //$display(">>> [%0d] axi_word=0x%0x", i , axi_word[i]);
            bsk_q[pc].pop_front();
          end
          axi_q.push_back(axi_word);
          //$display("0x%0128x",axi_word);
        end

        // /!\ Workaround, because pc is considered a variable...
        case (pc)
          0: gen_pc_loop[0].maxi4_bsk.write_trans(bsk_mem_addr[pc], axi_q);
          1: gen_pc_loop[1].maxi4_bsk.write_trans(bsk_mem_addr[pc], axi_q);
          2: gen_pc_loop[2].maxi4_bsk.write_trans(bsk_mem_addr[pc], axi_q);
          3: gen_pc_loop[3].maxi4_bsk.write_trans(bsk_mem_addr[pc], axi_q);
          4: gen_pc_loop[4].maxi4_bsk.write_trans(bsk_mem_addr[pc], axi_q);
          5: gen_pc_loop[5].maxi4_bsk.write_trans(bsk_mem_addr[pc], axi_q);
          6: gen_pc_loop[6].maxi4_bsk.write_trans(bsk_mem_addr[pc], axi_q);
          7: gen_pc_loop[7].maxi4_bsk.write_trans(bsk_mem_addr[pc], axi_q);
          8: gen_pc_loop[8].maxi4_bsk.write_trans(bsk_mem_addr[pc], axi_q);
          9: gen_pc_loop[9].maxi4_bsk.write_trans(bsk_mem_addr[pc], axi_q);
          10: gen_pc_loop[10].maxi4_bsk.write_trans(bsk_mem_addr[pc], axi_q);
          11: gen_pc_loop[11].maxi4_bsk.write_trans(bsk_mem_addr[pc], axi_q);
          12: gen_pc_loop[12].maxi4_bsk.write_trans(bsk_mem_addr[pc], axi_q);
          13: gen_pc_loop[13].maxi4_bsk.write_trans(bsk_mem_addr[pc], axi_q);
          14: gen_pc_loop[14].maxi4_bsk.write_trans(bsk_mem_addr[pc], axi_q);
          15: gen_pc_loop[15].maxi4_bsk.write_trans(bsk_mem_addr[pc], axi_q);
        endcase
        axi_q.delete();
      end // for pc
      @(posedge clk) begin
        bsk_mem_avail <= 1'b1;
        fill_bsk_done <= 1'b1;
      end
      $display("%t > INFO: Start process.", $time);
      wait (st_process);
      wait (st_reset_cache);
      @(posedge clk) begin
        bsk_mem_avail <= 1'b0;
        fill_bsk_done <= 1'b0;
      end

    end // repeat
  end

//---------------------------------
// Process
//---------------------------------
  logic [TOTAL_BATCH_NB-1:0] running_batch_id_mh;
  logic [TOTAL_BATCH_NB-1:0] running_batch_id_mhD;
  integer                    batch_start_id;
  logic [TOTAL_BATCH_NB-1:0] batch_done_1h;
  logic                      do_proc_batch;
  integer                    batch_start_nb;
  logic                      do_start_batch_rand;
  integer                    do_start_batch_rand_tmp;

  assign running_batch_id_mhD = (st_process || st_wait) ? (running_batch_id_mh | batch_start_1h) ^ batch_done_1h : '0;

  always_ff @(posedge clk)
    if (!s_rst_n) running_batch_id_mh <= '0;
    else          running_batch_id_mh <= running_batch_id_mhD;

  always_ff @(posedge clk) begin
    batch_start_id          <= $urandom_range(0,TOTAL_BATCH_NB-1);
    do_start_batch_rand_tmp <= $urandom;
  end

  assign do_start_batch_rand = do_start_batch_rand_tmp < 2**16; // Arbitrary value
  assign do_proc_batch  = st_process & ~running_batch_id_mh[batch_start_id] & do_start_batch_rand;
  assign batch_start_1h = {TOTAL_BATCH_NB{do_proc_batch}} & (1 << batch_start_id);

  //== Pointer management
  integer avail_bsk_slice_nb      [TOTAL_BATCH_NB-1:0];
  integer avail_bsk_slice_nbD     [TOTAL_BATCH_NB-1:0];
  integer inc_bsk_wr_ptr_seen     [TOTAL_BATCH_NB-1:0];
  integer inc_bsk_rd_ptr_seen     [TOTAL_BATCH_NB-1:0];
  integer inc_bsk_wr_ptr_expected [TOTAL_BATCH_NB-1:0];

  always_comb
    for (int i=0; i<TOTAL_BATCH_NB; i=i+1)
      avail_bsk_slice_nbD[i] = inc_bsk_wr_ptr[i] && !inc_bsk_rd_ptr[i] ? avail_bsk_slice_nb[i] + 1 :
                               !inc_bsk_wr_ptr[i] && inc_bsk_rd_ptr[i] ? avail_bsk_slice_nb[i] - 1 : avail_bsk_slice_nb[i];

  always_ff @(posedge clk)
    if (!s_rst_n) avail_bsk_slice_nb <= '{TOTAL_BATCH_NB{0}};
    else          avail_bsk_slice_nb <= avail_bsk_slice_nbD;

  integer inc_bsk_rd_ptr_rand;
  integer inc_bsk_batch_id_rand;
  logic   do_inc_bsk_rd_ptr;

  assign do_inc_bsk_rd_ptr = (avail_bsk_slice_nb[inc_bsk_batch_id_rand] > 0) & (inc_bsk_rd_ptr_rand > 2**28); // arbitrary value

  assign inc_bsk_rd_ptr    = (1 << inc_bsk_batch_id_rand) & {TOTAL_BATCH_NB{do_inc_bsk_rd_ptr}};

  always_ff @(posedge clk) begin
    inc_bsk_rd_ptr_rand   <= $urandom();
    inc_bsk_batch_id_rand <= $urandom_range(0, TOTAL_BATCH_NB-1);
  end

  always_ff @(posedge clk)
    if (!s_rst_n || st_idle)
      batch_start_nb <= '0;
    else
      if (|batch_start_1h)
        batch_start_nb <= batch_start_nb + 1;

  assign proc_done = |batch_start_1h & (batch_start_nb == PROC_BATCH_NB-1);

  always_ff @(posedge clk)
    if (!s_rst_n || st_idle) begin
      inc_bsk_wr_ptr_seen     <= '{TOTAL_BATCH_NB{32'd0}};
      inc_bsk_rd_ptr_seen     <= '{TOTAL_BATCH_NB{32'd0}};
      inc_bsk_wr_ptr_expected <= '{TOTAL_BATCH_NB{32'd0}};
    end
    else begin
      for (int i=0; i<TOTAL_BATCH_NB; i=i+1) begin
        inc_bsk_wr_ptr_seen[i]     <= inc_bsk_wr_ptr[i] ? inc_bsk_wr_ptr_seen[i] + 1 : inc_bsk_wr_ptr_seen[i];
        inc_bsk_rd_ptr_seen[i]     <= inc_bsk_rd_ptr[i] ? inc_bsk_rd_ptr_seen[i] + 1 : inc_bsk_rd_ptr_seen[i];
        inc_bsk_wr_ptr_expected[i] <= batch_start_1h[i] ? inc_bsk_wr_ptr_expected[i] + LWE_K : inc_bsk_wr_ptr_expected[i];
      end
    end

  always_comb
    for (int i=0; i<TOTAL_BATCH_NB; i=i+1)
      batch_done_1h[i] = inc_bsk_rd_ptr[i] && (inc_bsk_rd_ptr_seen[i] % LWE_K == LWE_K-1);

// ============================================================================================== --
// Check
// ============================================================================================== --
  // For each cut, check the data and address
  generate
    for (genvar gen_c=0; gen_c<BSK_CUT_NB; gen_c=gen_c+1) begin : gen_check_cut_loop
      integer out_stg_iter;
      integer out_intl;
      integer out_stg_iterD;
      integer out_intlD;
      logic   out_last_stg_iter;
      logic   out_last_intl;
      logic   error_data_l;
      logic   error_add_l;

      assign error_data[gen_c] = error_data_l;
      assign error_add[gen_c]  = error_add_l;

      assign out_last_stg_iter = out_stg_iter == STG_ITER_NB-1;
      assign out_last_intl    = out_intl == INTL_L-1;

      assign out_intlD        = bsk_mgr_wr_en[gen_c] ? out_last_intl ? '0 : out_intl + 1 : out_intl;
      assign out_stg_iterD    = bsk_mgr_wr_en[gen_c] && out_last_intl ? out_last_stg_iter ? '0 : out_stg_iter + 1 : out_stg_iter;

      always_ff @(posedge clk)
        if (!s_rst_n) begin
          out_intl     <= '0;
          out_stg_iter <= '0;
        end
        else begin
          out_intl     <= out_intlD   ;
          out_stg_iter <= out_stg_iterD;
        end

      always_ff @(posedge clk)
        if (!s_rst_n) begin
          error_data_l   <= 1'b0;
          error_add_l    <= 1'b0;
        end
        else begin
          if (bsk_mgr_wr_en[gen_c]) begin
            bsk_data_t bsk_d;
            logic [BSK_RAM_ADD_W-1:0] ref_add;

            // check data
            bsk_d.iter_loop = iter_cnt;
            bsk_d.br_loop  = bsk_mgr_wr_br_loop[gen_c];
            bsk_d.g_idx    = bsk_mgr_wr_g_idx[gen_c];
            bsk_d.stg_iter = out_stg_iter;
            bsk_d.l        = out_intl;

            for (int c=0; c<BSK_CUT_FCOEF_NB; c=c+1) begin
              integer p;
              integer r;
              r = (gen_c*BSK_CUT_FCOEF_NB + c) % R;
              p = (gen_c*BSK_CUT_FCOEF_NB + c) / R;

              bsk_d.p     = p;
              bsk_d.r     = r;

              assert(bsk_mgr_wr_data[gen_c][c] == bsk_d)
              else begin
                $display("%t > ERROR: [%0d] Data mismatch br_loop=%0d g_idx=%0d stg_iter=%0d l=%0d c=%0d p=%0d r=%0d exp=0x%0x seen=0x%0x.",
                      $time, gen_c, bsk_mgr_wr_br_loop[gen_c], bsk_mgr_wr_g_idx[gen_c], out_stg_iter,out_intl,c,p,r,bsk_d,bsk_mgr_wr_data[gen_c][c]);
                error_data_l <= 1'b1;
              end
            end

            // check address
            ref_add = bsk_mgr_wr_slot[gen_c] * BSK_SLOT_DEPTH + out_stg_iter * INTL_L + out_intl;
            assert(ref_add == bsk_mgr_wr_add[gen_c])
            else begin
              $display("%t > ERROR: [%0d] Address mismatch exp=0x%0x seen=0x%0x", $time, gen_c, ref_add, bsk_mgr_wr_add[gen_c]);
              error_add_l <= 1'b1;
            end

          end // if bsk_mgr_wr_en
        end // else
    end // for gen_c
  endgenerate

  logic [BSK_SLOT_NB-1:0] slot_seen;
  always_ff @(posedge clk)
    if (!s_rst_n) slot_seen <= '0;
    else begin
      if (bsk_mgr_wr_en[0]) begin
        slot_seen <= slot_seen | (1 << bsk_mgr_wr_slot[0]);
      end
    end

// ============================================================================================== --
// Reset cache
// ============================================================================================== --
  // sticky signal
  logic reset_doneD;
  assign reset_doneD = reset_cache_done ? 1'b1 : reset_done;

  always_ff @(posedge clk)
    if (!s_rst_n || st_idle) reset_done <= 1'b0;
    else                     reset_done <= reset_doneD;

  assign reset_cache = st_reset_cache;

// ============================================================================================== --
// Control
// ============================================================================================== --
  always_ff @(posedge clk) begin
    if (!s_rst_n) start <= 1'b0;
    else          start <= 1'b1;
  end

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      if (|batch_done_1h)
        $display("%t > INFO: Batch done : batch_id_1h='b%04b", $time, batch_done_1h);
    end

  integer iter_cntD;
  assign  iter_cntD = st_idle && start ? iter_cnt + 1 : iter_cnt;

  always_ff @(posedge clk)
    if (!s_rst_n) iter_cnt <= '1;
    else          iter_cnt <= iter_cntD;

  logic [TOTAL_BATCH_NB-1:0] inc_bsk_wr_ptr_match;
  always_comb
    for (int i=0; i<TOTAL_BATCH_NB; i=i+1)
      inc_bsk_wr_ptr_match[i] = inc_bsk_wr_ptr_seen[i] == inc_bsk_wr_ptr_expected[i];

  assign wait_done = (inc_bsk_wr_ptr_match == '1) & (running_batch_id_mh == '0);

  initial begin
    end_of_test = 1'b0;
    wait (st_done);
    wait (inc_bsk_wr_ptr_match == '1);

    // check that all slots have been used.
    assert(slot_seen == '1)
    else begin
      $display("%t > INFO: All slots have not been used slot_seen=0x%0x", $time, slot_seen);
      @(posedge clk);
    end

    @(posedge clk);
    end_of_test = 1'b1;
  end

endmodule
