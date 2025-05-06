// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Testbench to test ksk_if.
// ==============================================================================================

module tb_ksk_if;
`timescale 1ns/10ps

  import param_tfhe_pkg::*;
  import top_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import pep_ks_common_param_pkg::*;
  import ksk_mgr_common_param_pkg::*;
  import ksk_if_common_param_pkg::*;
  import axi_if_ksk_axi_pkg::*;
  import axi_if_common_param_pkg::*;

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int CLK_HALF_PERIOD = 1;
  localparam int ARST_ACTIVATION = 17;

  localparam int KSK_START_ADD_RANGE = 2**4;
  localparam int AXI4_ADD_W          = 24; // to ease simulation duration

  parameter int PROC_BATCH_NB        = 70;
  parameter int ITER_NB              = 2; // 1 to 4

  parameter int MEM_WR_CMD_BUF_DEPTH = 4;
  parameter int MEM_RD_CMD_BUF_DEPTH = 4;
  parameter int MEM_WR_DATA_LATENCY  = 40;
  parameter int MEM_RD_DATA_LATENCY  = 100;

  localparam [KSK_PC-1:0][31:0] KSK_CUT_PER_PC_A    = get_cut_per_pc(KSK_CUT_NB, KSK_PC);
  localparam [KSK_PC-1:0][31:0] KSK_CUT_OFS_A       = get_cut_ofs(KSK_CUT_PER_PC_A);
  localparam [KSK_PC-1:0][31:0] PROC_BCOL_COEF_NB_A = get_bcol_coef(KSK_CUT_NB,KSK_CUT_PER_PC_A);
  localparam [KSK_PC-1:0][31:0] PROC_BCOL_COEF_NB_ROUND_A = round(PROC_BCOL_COEF_NB_A,KSK_COEF_PER_AXI4_WORD*LBZ);

  initial begin
    $display("INFO > KS_BLOCK_LINE_NB=%0d",KS_BLOCK_LINE_NB);
    $display("INFO > LBY=%0d",LBY);
    $display("INFO > KS_LG_NB=%0d",KS_LG_NB);
    $display("INFO > KSK_CUT_NB=%0d",KSK_CUT_NB);
    $display("INFO > KSK_CUT_FCOEF_NB=%0d",KSK_CUT_FCOEF_NB);
    for (int i=0; i<KSK_PC; i=i+1) begin
      $display("INFO > KSK_CUT_PER_PC_A[%0d]=%0d",i, KSK_CUT_PER_PC_A[i]);
      $display("INFO > PROC_BCOL_COEF_NB_A[%0d]=%0d",i, PROC_BCOL_COEF_NB_A[i]);
      $display("INFO > PROC_BCOL_COEF_NB_ROUND_A[%0d]=%0d",i, PROC_BCOL_COEF_NB_ROUND_A[i]);
    end
  end

  localparam int KSK_PC_MAX = 16; // Max of this testbench

// ============================================================================================== //
// Constant functions
// ============================================================================================== //
  function [KSK_PC-1:0][31:0] get_cut_per_pc (int ksk_cut_nb, int ksk_pc);
    bit [KSK_PC-1:0][31:0] cut_per_pc;
    int cut_cnt;
    int cut_dist;
    cut_dist = (ksk_cut_nb + ksk_pc - 1) / ksk_pc;
    cut_cnt  = ksk_cut_nb;
    for (int i=0; i<KSK_PC; i=i+1) begin
      cut_per_pc[i] = cut_cnt < cut_dist ? cut_cnt : cut_dist;
      cut_cnt = cut_cnt - cut_dist;
    end
    return cut_per_pc;
  endfunction

  function [KSK_PC-1:0][31:0] get_cut_ofs (input [KSK_PC-1:0][31:0] cut_per_pc);
    bit [KSK_PC-1:0][31:0] cut_ofs;
    cut_ofs[0] = '0;
    for (int i=1; i<KSK_PC; i=i+1) begin
      cut_ofs[i] = cut_ofs[i-1] + cut_per_pc[i-1];
    end
    return cut_ofs;
  endfunction

  function [KSK_PC-1:0][31:0] get_bcol_coef(int cut_nb, input [KSK_PC-1:0][31:0] cut_per_pc_a);
    bit [KSK_PC-1:0][31:0] coef_nb;
    for (int i=0; i<KSK_PC; i=i+1) begin
      coef_nb[i] = ((LBY*KS_BLOCK_LINE_NB*KS_LG_NB*LBZ)+(cut_nb/cut_per_pc_a[i])-1) / (cut_nb/cut_per_pc_a[i]);
    end
    return coef_nb;
  endfunction

  function [KSK_PC-1:0][31:0] round(input [KSK_PC-1:0][31:0] cut_per_pc_a, int round_val);
    bit [KSK_PC-1:0][31:0] coef_nb;
    for (int i=0; i<KSK_PC; i=i+1) begin
      coef_nb[i] = ((cut_per_pc_a[i] + round_val-1) / round_val) * round_val;
    end
    return coef_nb;
  endfunction

// ============================================================================================== --
// type
// ============================================================================================== --
  typedef struct packed {
    logic [1:0]                 iter_loop;
    logic [KS_BLOCK_COL_W-1:0]  bcol;
    logic [KS_BLOCK_LINE_W-1:0] bline;
    logic [LBX_W-1:0]           x;
    logic [LBY_W-1:0]           y;
    logic [KS_LG_W-1:0]         lg;
    logic [LBZ_W-1:0]           z;
  } ksk_data_t;

  localparam int KSK_DATA_W = $bits(ksk_data_t);

  initial begin
    if ($bits(ksk_data_t) > MOD_KSK_W)
      $fatal(1,"> ERROR: bench only support MOD_KSK_W (%0d) > $bits(ksk_data_t) (%0d)", MOD_KSK_W, $bits(ksk_data_t));
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
  bit [KSK_CUT_NB-1:0] error_data;
  bit [KSK_CUT_NB-1:0] error_add;
  bit [KSK_CUT_NB-1:0] error_last_x;

  assign error = |error_data
                | |error_add
                | |error_last_x;

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
  logic [KSK_PC_MAX-1:0][AXI4_ID_W-1:0]                    m_axi4_arid;
  logic [KSK_PC_MAX-1:0][AXI4_ADD_W-1:0]                   m_axi4_araddr;
  logic [KSK_PC_MAX-1:0][7:0]                              m_axi4_arlen;
  logic [KSK_PC_MAX-1:0][2:0]                              m_axi4_arsize;
  logic [KSK_PC_MAX-1:0][1:0]                              m_axi4_arburst;
  logic [KSK_PC_MAX-1:0]                                   m_axi4_arvalid;
  logic [KSK_PC_MAX-1:0]                                   m_axi4_arready;
  logic [KSK_PC_MAX-1:0][AXI4_ID_W-1:0]                    m_axi4_rid;
  logic [KSK_PC_MAX-1:0][AXI4_DATA_W-1:0]                  m_axi4_rdata;
  logic [KSK_PC_MAX-1:0][1:0]                              m_axi4_rresp;
  logic [KSK_PC_MAX-1:0]                                   m_axi4_rlast;
  logic [KSK_PC_MAX-1:0]                                   m_axi4_rvalid;
  logic [KSK_PC_MAX-1:0]                                   m_axi4_rready;

  // KSK available in DDR. Ready to be ready through AXI
  logic                                                    ksk_mem_avail;
  logic [KSK_PC_MAX-1:0][axi_if_ksk_axi_pkg::AXI4_ADD_W-1: 0]  ksk_mem_addr;

  // Reset the cache
  logic                                                    reset_cache;
  logic                                                    reset_cache_done;

  // batch start
  logic [TOTAL_BATCH_NB-1:0]                               batch_start_1h; // One-hot : can only start 1 at a time.

  // KSK pointer
  logic [TOTAL_BATCH_NB-1: 0]                              inc_ksk_wr_ptr;
  logic [TOTAL_BATCH_NB-1: 0]                              inc_ksk_rd_ptr;

  // KSK manager
  logic [KSK_CUT_NB-1:0]                                   ksk_mgr_wr_en; // Write coefficients for 1 (stage iter,GLWE) at a time.
  logic [KSK_CUT_NB-1:0][KSK_CUT_FCOEF_NB-1:0][LBZ-1:0][MOD_KSK_W-1:0]  ksk_mgr_wr_data;
  logic [KSK_CUT_NB-1:0][KSK_RAM_ADD_W-1:0]                ksk_mgr_wr_add;
  logic [KSK_CUT_NB-1:0][LBX_W-1:0]                        ksk_mgr_wr_x_idx;
  logic [KSK_CUT_NB-1:0][KSK_SLOT_W-1:0]                   ksk_mgr_wr_slot;
  logic [KSK_CUT_NB-1:0][KS_BLOCK_COL_W-1:0]               ksk_mgr_wr_ks_loop;

// ============================================================================================== --
// Design under test instance
// ============================================================================================== --
  // Resize, due to bench constraints on AXI4 address range
  logic [KSK_PC_MAX-1:0][axi_if_ksk_axi_pkg::AXI4_ADD_W-1:0]   m_axi4_araddr_tmp;
  always_comb
    for (int i=0; i<KSK_PC_MAX; i=i+1)
      m_axi4_araddr[i] =  m_axi4_araddr_tmp[i][AXI4_ADD_W-1:0];

  ksk_if
  dut (
    .clk                (clk    ),
    .s_rst_n            (s_rst_n),

    .reset_cache        (reset_cache),
    .reset_cache_done   (reset_cache_done),

    .m_axi4_arid        (m_axi4_arid[KSK_PC-1:0]),
    .m_axi4_araddr      (m_axi4_araddr_tmp[KSK_PC-1:0]),
    .m_axi4_arlen       (m_axi4_arlen[KSK_PC-1:0]),
    .m_axi4_arsize      (m_axi4_arsize[KSK_PC-1:0]),
    .m_axi4_arburst     (m_axi4_arburst[KSK_PC-1:0]),
    .m_axi4_arvalid     (m_axi4_arvalid[KSK_PC-1:0]),
    .m_axi4_arready     (m_axi4_arready[KSK_PC-1:0]),
    .m_axi4_rid         (m_axi4_rid[KSK_PC-1:0]),
    .m_axi4_rdata       (m_axi4_rdata[KSK_PC-1:0]),
    .m_axi4_rresp       (m_axi4_rresp[KSK_PC-1:0]),
    .m_axi4_rlast       (m_axi4_rlast[KSK_PC-1:0]),
    .m_axi4_rvalid      (m_axi4_rvalid[KSK_PC-1:0]),
    .m_axi4_rready      (m_axi4_rready[KSK_PC-1:0]),

    .ksk_mem_avail      (ksk_mem_avail),
    .ksk_mem_addr       (ksk_mem_addr[top_common_param_pkg::KSK_PC_MAX-1:0]),

    .batch_start_1h     (batch_start_1h),

    .inc_ksk_wr_ptr     (inc_ksk_wr_ptr),
    .inc_ksk_rd_ptr     (inc_ksk_rd_ptr),

    .ksk_mgr_wr_en      (ksk_mgr_wr_en),
    .ksk_mgr_wr_data    (ksk_mgr_wr_data),
    .ksk_mgr_wr_add     (ksk_mgr_wr_add),
    .ksk_mgr_wr_x_idx   (ksk_mgr_wr_x_idx),
    .ksk_mgr_wr_slot    (ksk_mgr_wr_slot),
    .ksk_mgr_wr_ks_loop (ksk_mgr_wr_ks_loop)
  );

// ============================================================================================== --
// Memory
// ============================================================================================== --
  generate
    for (genvar gen_p=0; gen_p<KSK_PC_MAX; gen_p=gen_p+1) begin : gen_pc_loop
      logic [AXI4_ID_W-1:0]       axi4_ksk_awid;
      logic [AXI4_ADD_W-1:0]      axi4_ksk_awaddr;
      logic [7:0]                 axi4_ksk_awlen;
      logic [2:0]                 axi4_ksk_awsize;
      logic [1:0]                 axi4_ksk_awburst;
      logic                       axi4_ksk_awvalid;
      logic                       axi4_ksk_awready;
      logic [AXI4_DATA_W-1:0]     axi4_ksk_wdata;
      logic [(AXI4_DATA_W/8)-1:0] axi4_ksk_wstrb;
      logic                       axi4_ksk_wlast;
      logic                       axi4_ksk_wvalid;
      logic                       axi4_ksk_wready;
      logic [AXI4_ID_W-1:0]       axi4_ksk_bid;
      logic [1:0]                 axi4_ksk_bresp;
      logic                       axi4_ksk_bvalid;
      logic                       axi4_ksk_bready;

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
      ) axi4_ram_ksk // {{{
      (
        .clk          (clk),
        .rst          (!s_rst_n),

        .s_axi4_awid   (axi4_ksk_awid   ),
        .s_axi4_awaddr (axi4_ksk_awaddr ),
        .s_axi4_awlen  (axi4_ksk_awlen  ),
        .s_axi4_awsize (axi4_ksk_awsize ),
        .s_axi4_awburst(axi4_ksk_awburst),
        .s_axi4_awlock ('0), // disable
        .s_axi4_awcache('0), // disable
        .s_axi4_awprot ('0), // disable
        .s_axi4_awvalid(axi4_ksk_awvalid),
        .s_axi4_awready(axi4_ksk_awready),
        .s_axi4_wdata  (axi4_ksk_wdata  ),
        .s_axi4_wstrb  (axi4_ksk_wstrb  ),
        .s_axi4_wlast  (axi4_ksk_wlast  ),
        .s_axi4_wvalid (axi4_ksk_wvalid ),
        .s_axi4_wready (axi4_ksk_wready ),
        .s_axi4_bid    (axi4_ksk_bid    ),
        .s_axi4_bresp  (axi4_ksk_bresp  ),
        .s_axi4_bvalid (axi4_ksk_bvalid ),
        .s_axi4_bready (axi4_ksk_bready ),
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

      // AXI4 KSK driver
      maxi4_if #(
        .AXI4_DATA_W(AXI4_DATA_W),
        .AXI4_ADD_W (AXI4_ADD_W),
        .AXI4_ID_W  (AXI4_ID_W)
      ) maxi4_ksk (
        .clk(clk),
        .rst_n(s_rst_n)
      );

      // Connect interface on testbench signals
      // Write channel
      assign axi4_ksk_awid         = maxi4_ksk.awid   ;
      assign axi4_ksk_awaddr       = maxi4_ksk.awaddr ;
      assign axi4_ksk_awlen        = maxi4_ksk.awlen  ;
      assign axi4_ksk_awsize       = maxi4_ksk.awsize ;
      assign axi4_ksk_awburst      = maxi4_ksk.awburst;
      assign axi4_ksk_awvalid      = maxi4_ksk.awvalid;
      assign axi4_ksk_wdata        = maxi4_ksk.wdata  ;
      assign axi4_ksk_wstrb        = maxi4_ksk.wstrb  ;
      assign axi4_ksk_wlast        = maxi4_ksk.wlast  ;
      assign axi4_ksk_wvalid       = maxi4_ksk.wvalid ;
      assign axi4_ksk_bready       = maxi4_ksk.bready ;

      assign maxi4_ksk.awready    = axi4_ksk_awready;
      assign maxi4_ksk.wready     = axi4_ksk_wready;
      assign maxi4_ksk.bid        = axi4_ksk_bid;
      assign maxi4_ksk.bresp      = axi4_ksk_bresp;
      assign maxi4_ksk.bvalid     = axi4_ksk_bvalid;

      // Read channel
      assign maxi4_ksk.arready    = 1'b0;
      assign maxi4_ksk.rid        = '0;
      assign maxi4_ksk.rdata      = 'x  ;
      assign maxi4_ksk.rresp      = '0 ;
      assign maxi4_ksk.rlast      = '0;
      assign maxi4_ksk.rvalid     = 1'b0;

    end // for gen_p
  endgenerate

// ============================================================================================== --
// Scenario
// ============================================================================================== --
  initial begin
    for (int i=0; i<KSK_PC_MAX; i=i+1)
      ksk_mem_addr[i] = {$urandom_range(0,KSK_START_ADD_RANGE-1),{AXI4_DATA_BYTES_W{1'b0}}}; // AXI4_DATA_BYTES align
  end

//---------------------------------
// FSM
//---------------------------------
  typedef enum {ST_IDLE,
                ST_FILL_KSK,
                ST_PROCESS,
                ST_WAIT,
                ST_RESET_CACHE,
                ST_DONE} state_e;

  state_e state;
  state_e next_state;
  logic st_idle;
  logic st_fill_ksk;
  logic st_wait;
  logic st_reset_cache;
  logic st_process;
  logic st_done;

  integer iter_cnt;

  logic start;
  logic fill_ksk_done;
  logic proc_done;
  logic wait_done;
  logic reset_done;

  always_comb
    case (state)
      ST_IDLE:
        next_state = start ? ST_FILL_KSK : state;
      ST_FILL_KSK:
        next_state = fill_ksk_done ? ST_PROCESS : state;
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
  assign st_fill_ksk = state == ST_FILL_KSK;
  assign st_process  = state == ST_PROCESS;
  assign st_done     = state == ST_DONE;
  assign st_reset_cache = state == ST_RESET_CACHE;
  assign st_wait     = state == ST_WAIT;

//---------------------------------
// Fill ksk
//---------------------------------
  initial begin
    ksk_data_t ksk_q[KSK_PC-1:0][$];
    ksk_data_t ksk_data;
    logic [AXI4_DATA_W-1:0] axi_q[$];
    logic [KSK_COEF_PER_AXI4_WORD-1:0][KSK_ACS_W-1:0] axi_word;

    for (int pc=0; pc<KSK_PC_MAX; pc=pc+1) begin
      case (pc)
        0: gen_pc_loop[0].maxi4_ksk.init();
        1: gen_pc_loop[1].maxi4_ksk.init();
        2: gen_pc_loop[2].maxi4_ksk.init();
        3: gen_pc_loop[3].maxi4_ksk.init();
        4: gen_pc_loop[4].maxi4_ksk.init();
        5: gen_pc_loop[5].maxi4_ksk.init();
        6: gen_pc_loop[6].maxi4_ksk.init();
        7: gen_pc_loop[7].maxi4_ksk.init();
        8: gen_pc_loop[8].maxi4_ksk.init();
        9: gen_pc_loop[9].maxi4_ksk.init();
        10: gen_pc_loop[10].maxi4_ksk.init();
        11: gen_pc_loop[11].maxi4_ksk.init();
        12: gen_pc_loop[12].maxi4_ksk.init();
        13: gen_pc_loop[13].maxi4_ksk.init();
        14: gen_pc_loop[14].maxi4_ksk.init();
        15: gen_pc_loop[15].maxi4_ksk.init();
        default: $display("%t > WARNING: init of maxi4_ksk for pc %0d could not be done", $time, pc);
      endcase
    end
    ksk_mem_avail <= 1'b0;
    fill_ksk_done <= 1'b0;
    repeat(ITER_NB) begin
      wait (st_fill_ksk);
      @(posedge clk);
      $display("%t > INFO: Load KSK iter %0d.", $time, iter_cnt);

      for (int c=0; c<KS_BLOCK_COL_NB; c=c+1)
        for (int x=0; x<LBX; x=x+1)
          for (int l=0; l<KS_BLOCK_LINE_NB; l=l+1)
            for (int lg=0; lg<KS_LG_NB; lg=lg+1)
              for (int y=0; y<LBY; y=y+1)
                for (int z=0; z<LBZ; z=z+1) begin
                  ksk_data.iter_loop = iter_cnt;
                  ksk_data.bcol  = c;
                  ksk_data.bline = l;
                  ksk_data.x     = x;
                  ksk_data.y     = y;
                  ksk_data.lg    = lg;
                  ksk_data.z     = z;
                  for (int pc=0; pc<KSK_PC; pc=pc+1) begin
                    if (   (y >= KSK_CUT_OFS_A[pc]*KSK_CUT_FCOEF_NB)
                        && (y < (KSK_CUT_OFS_A[pc]+KSK_CUT_PER_PC_A[pc])*KSK_CUT_FCOEF_NB)) begin
                      ksk_q[pc].push_back(ksk_data);
                      if (ksk_q[pc].size() % PROC_BCOL_COEF_NB_ROUND_A[pc] == PROC_BCOL_COEF_NB_A[pc]) begin
                        for (int j=PROC_BCOL_COEF_NB_A[pc]; j<PROC_BCOL_COEF_NB_ROUND_A[pc]; j=j+1)
                          ksk_q[pc].push_back('1); // dummy data to complete the AXI word
                      end
                    end
                  end

                end

      for (int pc=0; pc<KSK_PC; pc=pc+1) begin
        logic [AXI4_DATA_W-1:0] axi_q[$];
        while (ksk_q[pc].size() > 0) begin
          axi_word = '0;
          for (int i=0; i<KSK_COEF_PER_AXI4_WORD; i=i+1) begin
            for (int z=0; z<LBZ; z=z+1) begin
              if (ksk_q[pc].size() == 0)
                $fatal(1,"> ERROR: KSK[pc=%0d] number mismatch!", pc);
              axi_word[i][z*MOD_KSK_W+:MOD_KSK_W] = ksk_q[pc][0][KSK_DATA_W-1:0]; // complete with 0s in MSB
              ksk_q[pc].pop_front();
            end
          end
          axi_q.push_back(axi_word);
          //$display("0x%0128x",axi_word);
        end

        // /!\ Workaround, because pc is considered a variable...
        case (pc)
          0:gen_pc_loop[0].maxi4_ksk.write_trans(ksk_mem_addr[pc], axi_q);
          1:gen_pc_loop[1].maxi4_ksk.write_trans(ksk_mem_addr[pc], axi_q);
          2:gen_pc_loop[2].maxi4_ksk.write_trans(ksk_mem_addr[pc], axi_q);
          3:gen_pc_loop[3].maxi4_ksk.write_trans(ksk_mem_addr[pc], axi_q);
          4: gen_pc_loop[4].maxi4_ksk.write_trans(ksk_mem_addr[pc], axi_q);
          5: gen_pc_loop[5].maxi4_ksk.write_trans(ksk_mem_addr[pc], axi_q);
          6: gen_pc_loop[6].maxi4_ksk.write_trans(ksk_mem_addr[pc], axi_q);
          7: gen_pc_loop[7].maxi4_ksk.write_trans(ksk_mem_addr[pc], axi_q);
          8: gen_pc_loop[8].maxi4_ksk.write_trans(ksk_mem_addr[pc], axi_q);
          9: gen_pc_loop[9].maxi4_ksk.write_trans(ksk_mem_addr[pc], axi_q);
          10: gen_pc_loop[10].maxi4_ksk.write_trans(ksk_mem_addr[pc], axi_q);
          11: gen_pc_loop[11].maxi4_ksk.write_trans(ksk_mem_addr[pc], axi_q);
          12: gen_pc_loop[12].maxi4_ksk.write_trans(ksk_mem_addr[pc], axi_q);
          13: gen_pc_loop[13].maxi4_ksk.write_trans(ksk_mem_addr[pc], axi_q);
          14: gen_pc_loop[14].maxi4_ksk.write_trans(ksk_mem_addr[pc], axi_q);
          15: gen_pc_loop[15].maxi4_ksk.write_trans(ksk_mem_addr[pc], axi_q);
        endcase
        axi_q.delete();
      end // for pc
      @(posedge clk) begin
        ksk_mem_avail <= 1'b1;
        fill_ksk_done <= 1'b1;
      end
      $display("%t > INFO: Start process.", $time);
      wait (st_process);
      wait (st_reset_cache);
      @(posedge clk) begin
        ksk_mem_avail <= 1'b0;
        fill_ksk_done <= 1'b0;
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

  assign do_start_batch_rand = do_start_batch_rand_tmp < 2**27; // Arbitrary value
  assign do_proc_batch  = st_process & ~running_batch_id_mh[batch_start_id] & do_start_batch_rand;
  assign batch_start_1h = {TOTAL_BATCH_NB{do_proc_batch}} & (1 << batch_start_id);

  //== Pointer management
  integer avail_ksk_slice_nb      [TOTAL_BATCH_NB-1:0];
  integer avail_ksk_slice_nbD     [TOTAL_BATCH_NB-1:0];
  integer inc_ksk_wr_ptr_seen     [TOTAL_BATCH_NB-1:0];
  integer inc_ksk_rd_ptr_seen     [TOTAL_BATCH_NB-1:0];
  integer inc_ksk_wr_ptr_expected [TOTAL_BATCH_NB-1:0];

  always_comb
    for (int i=0; i<TOTAL_BATCH_NB; i=i+1)
      avail_ksk_slice_nbD[i] = inc_ksk_wr_ptr[i] && !inc_ksk_rd_ptr[i] ? avail_ksk_slice_nb[i] + 1 :
                               !inc_ksk_wr_ptr[i] && inc_ksk_rd_ptr[i] ? avail_ksk_slice_nb[i] - 1 : avail_ksk_slice_nb[i];

  always_ff @(posedge clk)
    if (!s_rst_n) avail_ksk_slice_nb <= '{TOTAL_BATCH_NB{0}};
    else          avail_ksk_slice_nb <= avail_ksk_slice_nbD;

  integer inc_ksk_rd_ptr_rand;
  integer inc_ksk_batch_id_rand;
  logic   do_inc_ksk_rd_ptr;

  assign do_inc_ksk_rd_ptr = (avail_ksk_slice_nb[inc_ksk_batch_id_rand] > 0) & (inc_ksk_rd_ptr_rand > 2**28); // arbitrary value

  assign inc_ksk_rd_ptr    = (1 << inc_ksk_batch_id_rand) & {TOTAL_BATCH_NB{do_inc_ksk_rd_ptr}};

  always_ff @(posedge clk) begin
    inc_ksk_rd_ptr_rand   <= $urandom();
    inc_ksk_batch_id_rand <= $urandom_range(0, TOTAL_BATCH_NB-1);
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
      inc_ksk_wr_ptr_seen     <= '{TOTAL_BATCH_NB{32'd0}};
      inc_ksk_rd_ptr_seen     <= '{TOTAL_BATCH_NB{32'd0}};
      inc_ksk_wr_ptr_expected <= '{TOTAL_BATCH_NB{32'd0}};
    end
    else begin
      for (int i=0; i<TOTAL_BATCH_NB; i=i+1) begin
        inc_ksk_wr_ptr_seen[i]     <= inc_ksk_wr_ptr[i] ? inc_ksk_wr_ptr_seen[i] + 1 : inc_ksk_wr_ptr_seen[i];
        inc_ksk_rd_ptr_seen[i]     <= inc_ksk_rd_ptr[i] ? inc_ksk_rd_ptr_seen[i] + 1 : inc_ksk_rd_ptr_seen[i];
        inc_ksk_wr_ptr_expected[i] <= batch_start_1h[i] ? inc_ksk_wr_ptr_expected[i] + KS_BLOCK_COL_NB : inc_ksk_wr_ptr_expected[i];
      end
    end

  always_comb
    for (int i=0; i<TOTAL_BATCH_NB; i=i+1)
      batch_done_1h[i] = inc_ksk_rd_ptr[i] && (inc_ksk_rd_ptr_seen[i] % KS_BLOCK_COL_NB == KS_BLOCK_COL_NB-1);

// ============================================================================================== --
// Check
// ============================================================================================== --
  // For each cut, check the data and address
  generate
    for (genvar gen_c=0; gen_c<KSK_CUT_NB; gen_c=gen_c+1) begin : gen_check_cut_loop
      integer out_bline;
      integer out_lg;
      integer out_blineD;
      integer out_lgD;
      logic   out_last_bline;
      logic   out_last_lg;
      logic   error_data_l;
      logic   error_add_l;
      logic   error_last_x_l;

      assign error_data[gen_c]   = error_data_l;
      assign error_add[gen_c]    = error_add_l;
      assign error_last_x[gen_c] = error_last_x_l;

      assign out_last_bline = out_bline == KS_BLOCK_LINE_NB-1;
      assign out_last_lg    = out_lg == KS_LG_NB-1;

      assign out_lgD        = ksk_mgr_wr_en[gen_c] ? out_last_lg ? '0 : out_lg + 1 : out_lg;
      assign out_blineD     = ksk_mgr_wr_en[gen_c] && out_last_lg ? out_last_bline ? '0 : out_bline + 1 : out_bline;

      always_ff @(posedge clk)
        if (!s_rst_n) begin
          out_lg    <= '0;
          out_bline <= '0;
        end
        else begin
          out_lg    <= out_lgD   ;
          out_bline <= out_blineD;
        end

      always_ff @(posedge clk)
        if (!s_rst_n) begin
          error_data_l   <= 1'b0;
          error_add_l    <= 1'b0;
          error_last_x_l <= 1'b0;
        end
        else begin
          if (ksk_mgr_wr_en[gen_c]) begin
            ksk_data_t ksk_d;
            logic [KSK_RAM_ADD_W-1:0] ref_add;

            // check data
            ksk_d.iter_loop = iter_cnt;
            ksk_d.bcol  = ksk_mgr_wr_ks_loop[gen_c];
            ksk_d.bline = out_bline;
            ksk_d.x     = ksk_mgr_wr_x_idx[gen_c];
            ksk_d.lg    = out_lg;

            for (int c=0; c<KSK_CUT_FCOEF_NB; c=c+1) begin
              integer y;
              y = (gen_c*KSK_CUT_FCOEF_NB + c);
              for (int z=0; z<LBZ; z=z+1) begin
                ksk_d.z     = z;
                ksk_d.y     = y;

                assert(ksk_mgr_wr_data[gen_c][c][z] == ksk_d)
                else begin
                  $display("%t > ERROR: [%0d] Data mismatch ks_loop=%0d x=%0d bline=%0d y=%0d z=%0d lg=%0d exp=0x%0x seen=0x%0x.",
                        $time, gen_c, ksk_mgr_wr_ks_loop[gen_c], ksk_mgr_wr_x_idx[gen_c], out_bline,y,z,out_lg,ksk_d,ksk_mgr_wr_data[gen_c][c][z]);
                  error_data_l <= 1'b1;
                end
              end
            end

            // check address
            ref_add = ksk_mgr_wr_slot[gen_c] * KSK_SLOT_DEPTH + out_bline * KS_LG_NB + out_lg;

            assert(ref_add == ksk_mgr_wr_add[gen_c])
            else begin
              $display("%t > ERROR: [%0d] Address mismatch exp=0x%0x seen=0x%0x", $time, gen_c, ref_add, ksk_mgr_wr_add[gen_c]);
              error_add_l <= 1'b1;
            end

            // If the last bcol is incomplete, the x col is not read from the DDR
            // So we should never see for ks_loop == last x_id that is not used.
            assert((LWE_K_P1%LBX == 0) || (ksk_mgr_wr_ks_loop[gen_c] != KS_BLOCK_COL_NB-1) || (ksk_mgr_wr_x_idx[gen_c] < LWE_K_P1%LBX))
            else begin
                $display("%t > ERROR:[%0d] Sending unused last x column", $time, gen_c);
                error_last_x_l <= 1'b1;
            end
          end
        end

    end // for gen_c
  endgenerate

  logic [KSK_SLOT_NB-1:0] slot_seen;
  always_ff @(posedge clk)
    if (!s_rst_n) slot_seen <= '0;
    else begin
      if (ksk_mgr_wr_en[0]) begin
        slot_seen <= slot_seen | (1 << ksk_mgr_wr_slot[0]);
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

  logic [TOTAL_BATCH_NB-1:0] inc_ksk_wr_ptr_match;
  always_comb
    for (int i=0; i<TOTAL_BATCH_NB; i=i+1)
      inc_ksk_wr_ptr_match[i] = inc_ksk_wr_ptr_seen[i] == inc_ksk_wr_ptr_expected[i];

  assign wait_done = (inc_ksk_wr_ptr_match == '1) & (running_batch_id_mh == '0);

  initial begin
    end_of_test = 1'b0;
    wait (st_done);
    wait (inc_ksk_wr_ptr_match == '1);

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
