// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Test bench to test hpu.
// ==============================================================================================

`include "tb_hpu_macro_inc.sv"

`resetall
`timescale 1ns/10ps
module tb_hpu;

  import hpu_common_instruction_pkg::*;
  import hpu_common_param_pkg::*;
  import common_definition_pkg::*;
  import param_tfhe_pkg::*;
  import top_common_param_pkg::*;
  import axi_if_common_param_pkg::*;
  import axi_if_ucore_axi_pkg::*;
  import axi_if_trc_axi_pkg::*;
  import axi_if_ct_axi_pkg::*;
  import axi_if_glwe_axi_pkg::*;
  import axi_if_bsk_axi_pkg::*;
  import axi_if_ksk_axi_pkg::*;
  import axi_if_shell_axil_pkg::*;
  import hpu_regif_core_cfg_1in3_pkg::*;
  import hpu_regif_core_prc_1in3_pkg::*;
  import hpu_regif_core_cfg_3in3_pkg::*;
  import hpu_regif_core_prc_3in3_pkg::*;
  import file_handler_pkg::*;
  import pep_ks_common_param_pkg::*;
  import pem_common_param_pkg::*; // CT alignment in mem
  import pep_common_param_pkg::*;
  import instruction_scheduler_pkg::*;

  // Package used to modelize the communication between the host and the testbench ublaze
  import tb_hpu_ucore_regif_pkg::*;
// ============================================================================================== --
// parameter / localparam
// ============================================================================================== --
  localparam int CLK_HALF_PERIOD     = 1;
  localparam int LPD_CLK_HALF_PERIOD = 5;
  localparam int ARST_ACTIVATION     = 100 + 17; // 100 to allow for FPGA global reset to happen

  localparam int MEM_WR_CMD_BUF_DEPTH = 1; // Should be >= 1
  localparam int MEM_RD_CMD_BUF_DEPTH = 4; // Should be >= 1
  // Data latency
  localparam int MEM_WR_DATA_LATENCY = 1; // Should be >= 1
  localparam int MEM_RD_DATA_LATENCY = 53; // Should be >= 1
  // Set random on ready valid, on write path
  localparam bit MEM_USE_WR_RANDOM = 1; // TOREVIEW
  // Set random on ready valid, on read path
  localparam bit MEM_USE_RD_RANDOM = 1; // TOREVIEW

  localparam bit[1:0] TB_DRIVE_HBM  = 2'b10;
  localparam bit[1:0] DUT_DRIVE_HBM = 2'b01;

  localparam string FILE_DATA_TYPE        = "ascii_hex";

  // Stimuli files
  localparam string BSK_FILE_PREFIX       = "input/ucode/key/bsk";
  localparam string KSK_FILE_PREFIX       = "input/ucode/key/ksk";

  // Workaround for axi_ram limitation
  // => Reduce addr range for simulation time purpose
  localparam int    AXIL_ADD_W       = 18;
  localparam int    AXIL_DATA_W      = 32;
  localparam int    AXI4_UCORE_ADD_W = 16;
  localparam int    AXI4_UCORE_DATA_W= axi_if_ucore_axi_pkg::AXI4_DATA_W;
  localparam int    AXI4_UCORE_ID_W  = axi_if_ucore_axi_pkg::AXI4_ID_W;
  localparam int    AXI4_TRC_ADD_W   = 20;
  localparam int    AXI4_TRC_DATA_W  = axi_if_trc_axi_pkg::AXI4_DATA_W;
  localparam int    AXI4_TRC_ID_W    = axi_if_trc_axi_pkg::AXI4_ID_W;
  localparam int    AXI4_PEM_ADD_W   = 24;
  localparam int    AXI4_PEM_DATA_W  = axi_if_ct_axi_pkg::AXI4_DATA_W;
  localparam int    AXI4_PEM_DATA_BYTES = axi_if_ct_axi_pkg::AXI4_DATA_BYTES;
  localparam int    AXI4_PEM_ID_W    = axi_if_ct_axi_pkg::AXI4_ID_W;
  localparam int    AXI4_GLWE_ADD_W  = 24;
  localparam int    AXI4_GLWE_DATA_W = axi_if_glwe_axi_pkg::AXI4_DATA_W;
  localparam int    AXI4_GLWE_DATA_BYTES = axi_if_glwe_axi_pkg::AXI4_DATA_BYTES;
  localparam int    AXI4_GLWE_ID_W   = axi_if_glwe_axi_pkg::AXI4_ID_W;
  localparam int    AXI4_BSK_ADD_W   = 24;
  localparam int    AXI4_BSK_DATA_W  = axi_if_bsk_axi_pkg::AXI4_DATA_W;
  localparam int    AXI4_BSK_DATA_BYTES = axi_if_bsk_axi_pkg::AXI4_DATA_BYTES;
  localparam int    AXI4_BSK_ID_W    = axi_if_bsk_axi_pkg::AXI4_ID_W;
  localparam int    AXI4_KSK_ADD_W   = 24;
  localparam int    AXI4_KSK_DATA_W  = axi_if_ksk_axi_pkg::AXI4_DATA_W;
  localparam int    AXI4_KSK_DATA_BYTES = axi_if_ksk_axi_pkg::AXI4_DATA_BYTES;
  localparam int    AXI4_KSK_ID_W    = axi_if_ksk_axi_pkg::AXI4_ID_W;

  // TB parameters
  parameter int    IOP_NB = 1;
  parameter int    IOP_INT_SIZE = 2;
  parameter int    MSG_W = PAYLOAD_BIT / 2;
  parameter int    DOP_NB = 1;
  parameter int    GLWE_NB = 1;
  parameter int    BLWE_NB = 1;
  parameter int    OUT_BLWE_NB = 1;
  parameter string IOP_FILE_PREFIX  = "input/ucode/iop/iop";
  parameter string DOP_FILE_PREFIX  = "input/ucode/dop/dop";
  parameter string GLWE_FILE_PREFIX = "input/ucode/glwe/glwe";
  parameter string BLWE_FILE_PREFIX = "input/ucode/blwe/input/blwe";
  parameter string OUT_BLWE_FILE_PREFIX = "input/ucode/blwe/output/blwe";
  // ucore parameters
  localparam int   EXPECTED_UCORE_VERSION_MAJOR = 2;
  localparam int   EXPECTED_UCORE_VERSION_MINOR = 0;
  localparam int   UCORE_VERSION_IOP            = 'h00FE0000;
  localparam int   EMPTY_DST_IOP                = 'h60000000;
  localparam int   EMPTY_SRC_IOP                = 'h20000000;
  // Index of the DOP/GLWE
  parameter [DOP_NB-1:0][7:0]    DOP_LIST     = {8'h00};
  parameter [GLWE_NB-1:0][7:0]   GLWE_LIST    = {8'h00};
  parameter [BLWE_NB-1:0][15:0]  BLWE_LIST      = {16'h0000};
  parameter [OUT_BLWE_NB-1:0][15:0]  OUT_BLWE_LIST      = {16'h0000};

  parameter bit USE_BPIP     = 1'b1;
  parameter bit USE_BPIP_OPPORTUNISM = 1'b0;
  parameter int BPIP_TIMEOUT = BATCH_PBS_NB * 128;
  parameter int INTER_PART_PIPE = 1;
  parameter bit MOD_SWITCH_MEAN_COMP = 1'b1;

  parameter bit DO_CHECK     = USE_BPIP;
  parameter int SIMU_ITERATION_NB = 2;

  localparam int IOP_BASE_W        = 32;
  localparam int IOP_AXI4L_WORD_NB = IOP_BASE_W / AXIL_DATA_W; // AXIL_DATA_W should divide IOP_BASE_W

  localparam int GLWE_ACS_W        = MOD_Q_W > 32 ? 64 : 32; // Read and write GLWE coef width. Should be >= MOD_Q_W
  localparam int GLWE_BODY_BYTES   = N * GLWE_ACS_W/8;

  localparam int TEST_PS = IOP_NB > 1 ? 2 : IOP_NB;

  localparam int ACKQ_RD_ERR = 'hdeadc0de;

  localparam int BSK_PC_MAX_L  = 16;
  localparam int KSK_PC_MAX_L  = 16;
  localparam int PEM_PC_MAX_L  = 2;
  localparam int GLWE_PC_MAX_L = 1;

  localparam int P1_OFS = 0;
  localparam int P3_OFS = 1;

  generate
    if (BSK_PC_MAX > BSK_PC_MAX_L) begin : __UNSUPPORTED_BSK_PC_MAX
      $fatal(1, "> ERROR Unsupported BSK_PC_MAX (%0d). Should be less or equal to %0d.", BSK_PC_MAX, BSK_PC_MAX_L);
    end
    if (KSK_PC_MAX > KSK_PC_MAX_L) begin : __UNSUPPORTED_KSK_PC_MAX
      $fatal(1, "> ERROR Unsupported KSK_PC_MAX (%0d). Should be less or equal to %0d.", KSK_PC_MAX, KSK_PC_MAX_L);
    end
    if (PEM_PC_MAX >PEM_PC_MAX_L) begin : __UNSUPPORTED_PEM_PC_MAX
      $fatal(1, "> ERROR Unsupported PEM_PC_MAX (%0d). Should be less or equal to %0d.", PEM_PC_MAX, PEM_PC_MAX_L);
    end
    if (GLWE_PC_MAX >GLWE_PC_MAX_L) begin : __UNSUPPORTED_GLWE_PC_MAX
      $fatal(1, "> ERROR Unsupported GLWE_PC_MAX (%0d). Should be less or equal to %0d.", GLWE_PC_MAX, GLWE_PC_MAX_L);
    end
    if (GLWE_PC != 1) begin : __UNSUPPORTED_GLWE_PC_MAX_L
      $fatal(1, "> ERROR Support only GLWE_PC = 1");
    end
  endgenerate
// ============================================================================================== --
// clock, reset
// ============================================================================================== --
  bit clk;
  bit cfg_clk;
  bit a_rst_n; // asynchronous reset
  bit s_rst_n; // synchronous reset
  bit cfg_srst_n; // synchronous clock

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

  always begin
    #LPD_CLK_HALF_PERIOD cfg_clk = ~cfg_clk;
  end

  always_ff @(posedge cfg_clk) begin
    cfg_srst_n <= a_rst_n;
  end

  logic clk_ce;
  logic clk_g;

  BUFGCE #(
    // We need the CE path to be synchronized. There's no way a path from a flop with the huge
    // insertion delay of the FPGA clock tree will be able to meet timing back to the clock's root
    // @ 350MHz.
    .CE_TYPE    ( "HARDSYNC"   ) ,
    .SIM_DEVICE ( "VERSAL_HBM" )
  ) clock_gate (
    .CE ( clk_ce ) ,
    .I  ( clk    ) ,
    .O  ( clk_g  )
  );

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

  assign error = 1'b0; // TODO : connect internal error bits of HPU

  always_ff @(posedge clk)
    if (error) begin
      $display("%t > FAILURE !", $time);
      $finish;
    end

// ============================================================================================== --
// input / output signals
// ============================================================================================== --
logic [3:0]                          hpu_irq;

// AxiLite interface ======================================================================
logic [1:0][AXIL_ADD_W-1:0]          tb_axil_prc_awaddr;
logic [1:0]                          tb_axil_prc_awvalid;
logic [1:0]                          tb_axil_prc_awready;
logic [1:0][AXIL_DATA_W-1:0]         tb_axil_prc_wdata;
logic [1:0][AXIL_DATA_W/8-1:0]       tb_axil_prc_wstrb;
logic [1:0]                          tb_axil_prc_wvalid;
logic [1:0]                          tb_axil_prc_wready;
logic [1:0][1:0]                     tb_axil_prc_bresp;
logic [1:0]                          tb_axil_prc_bvalid;
logic [1:0]                          tb_axil_prc_bready;
logic [1:0][AXIL_ADD_W-1:0]          tb_axil_prc_araddr;
logic [1:0]                          tb_axil_prc_arvalid;
logic [1:0]                          tb_axil_prc_arready;
logic [1:0][AXIL_DATA_W-1:0]         tb_axil_prc_rdata;
logic [1:0][1:0]                     tb_axil_prc_rresp;
logic [1:0]                          tb_axil_prc_rvalid;
logic [1:0]                          tb_axil_prc_rready;

logic [1:0][AXIL_ADD_W-1:0]          tb_axil_cfg_awaddr;
logic [1:0]                          tb_axil_cfg_awvalid;
logic [1:0]                          tb_axil_cfg_awready;
logic [1:0][AXIL_DATA_W-1:0]         tb_axil_cfg_wdata;
logic [1:0][AXIL_DATA_W/8-1:0]       tb_axil_cfg_wstrb;
logic [1:0]                          tb_axil_cfg_wvalid;
logic [1:0]                          tb_axil_cfg_wready;
logic [1:0][1:0]                     tb_axil_cfg_bresp;
logic [1:0]                          tb_axil_cfg_bvalid;
logic [1:0]                          tb_axil_cfg_bready;
logic [1:0][AXIL_ADD_W-1:0]          tb_axil_cfg_araddr;
logic [1:0]                          tb_axil_cfg_arvalid;
logic [1:0]                          tb_axil_cfg_arready;
logic [1:0][AXIL_DATA_W-1:0]         tb_axil_cfg_rdata;
logic [1:0][1:0]                     tb_axil_cfg_rresp;
logic [1:0]                          tb_axil_cfg_rvalid;
logic [1:0]                          tb_axil_cfg_rready;

// AXI4 HBM_UCORE interface =======================================================================
// Selector for internal axi_ram muxing
logic [1:0]              axi4_ucore_select;
// AXI4 HBM<->DUT interface
/* Read channel */
logic [AXI4_UCORE_ID_W-1:0]                   dut_axi4_ucore_arid;
logic [AXI4_UCORE_ADD_W-1:0]                  dut_axi4_ucore_araddr;
logic [7:0]                                   dut_axi4_ucore_arlen;
logic [2:0]                                   dut_axi4_ucore_arsize;
logic [1:0]                                   dut_axi4_ucore_arburst;
logic                                         dut_axi4_ucore_arvalid;
logic                                         dut_axi4_ucore_arready;
logic [AXI4_UCORE_ID_W-1:0]                   dut_axi4_ucore_rid;
logic [AXI4_UCORE_DATA_W-1:0]                 dut_axi4_ucore_rdata;
logic [1:0]                                   dut_axi4_ucore_rresp;
logic                                         dut_axi4_ucore_rlast;
logic                                         dut_axi4_ucore_rvalid;
logic                                         dut_axi4_ucore_rready;

/*Write channel*/
logic [AXI4_UCORE_ID_W-1:0]                   dut_axi4_ucore_awid;
logic [AXI4_UCORE_ADD_W-1:0]                  dut_axi4_ucore_awaddr;
logic [7:0]                                   dut_axi4_ucore_awlen;
logic [2:0]                                   dut_axi4_ucore_awsize;
logic [1:0]                                   dut_axi4_ucore_awburst;
logic                                         dut_axi4_ucore_awvalid;
logic                                         dut_axi4_ucore_awready;
logic [AXI4_UCORE_DATA_W-1:0]                 dut_axi4_ucore_wdata;
logic [axi_if_ucore_axi_pkg::AXI4_STRB_W-1:0] dut_axi4_ucore_wstrb;
logic                                         dut_axi4_ucore_wlast;
logic                                         dut_axi4_ucore_wvalid;
logic                                         dut_axi4_ucore_wready;
logic [AXI4_UCORE_ID_W-1:0]                   dut_axi4_ucore_bid;
logic [1:0]                                   dut_axi4_ucore_bresp;
logic                                         dut_axi4_ucore_bvalid;
logic                                         dut_axi4_ucore_bready;
// AXI4 HBM<->TB interface
/* Read channel */
logic [AXI4_UCORE_ID_W-1:0]                   tb_axi4_ucore_arid;
logic [AXI4_UCORE_ADD_W-1:0]                  tb_axi4_ucore_araddr;
logic [7:0]                                   tb_axi4_ucore_arlen;
logic [2:0]                                   tb_axi4_ucore_arsize;
logic [1:0]                                   tb_axi4_ucore_arburst;
logic                                         tb_axi4_ucore_arvalid;
logic                                         tb_axi4_ucore_arready;
logic [AXI4_UCORE_ID_W-1:0]                   tb_axi4_ucore_rid;
logic [AXI4_UCORE_DATA_W-1:0]                 tb_axi4_ucore_rdata;
logic [1:0]                                   tb_axi4_ucore_rresp;
logic                                         tb_axi4_ucore_rlast;
logic                                         tb_axi4_ucore_rvalid;
logic                                         tb_axi4_ucore_rready;

/*Write channel*/
logic [AXI4_UCORE_ID_W-1:0]                   tb_axi4_ucore_awid;
logic [AXI4_UCORE_ADD_W-1:0]                  tb_axi4_ucore_awaddr;
logic [7:0]                                   tb_axi4_ucore_awlen;
logic [2:0]                                   tb_axi4_ucore_awsize;
logic [1:0]                                   tb_axi4_ucore_awburst;
logic                                         tb_axi4_ucore_awvalid;
logic                                         tb_axi4_ucore_awready;
logic [AXI4_UCORE_DATA_W-1:0]                 tb_axi4_ucore_wdata;
logic [axi_if_ucore_axi_pkg::AXI4_STRB_W-1:0] tb_axi4_ucore_wstrb;
logic                                         tb_axi4_ucore_wlast;
logic                                         tb_axi4_ucore_wvalid;
logic                                         tb_axi4_ucore_wready;
logic [AXI4_UCORE_ID_W-1:0]                   tb_axi4_ucore_bid;
logic [1:0]                                   tb_axi4_ucore_bresp;
logic                                         tb_axi4_ucore_bvalid;
logic                                         tb_axi4_ucore_bready;


// AXI4 HBM_trc interface ======================================================================
// DUT is in Wo mode and Tb in Ro -> No need for muxing
// AXI4 HBM<->DUT interface
/* Read channel */
logic [AXI4_TRC_ID_W-1:0]                   axi4_trc_arid;
logic [AXI4_TRC_ADD_W-1:0]                  axi4_trc_araddr;
logic [7:0]                                 axi4_trc_arlen;
logic [2:0]                                 axi4_trc_arsize;
logic [1:0]                                 axi4_trc_arburst;
logic                                       axi4_trc_arvalid;
logic                                       axi4_trc_arready;
logic [AXI4_TRC_ID_W-1:0]                   axi4_trc_rid;
logic [AXI4_TRC_DATA_W-1:0]                 axi4_trc_rdata;
logic [1:0]                                 axi4_trc_rresp;
logic                                       axi4_trc_rlast;
logic                                       axi4_trc_rvalid;
logic                                       axi4_trc_rready;

/*Write channel*/
logic [AXI4_TRC_ID_W-1:0]                    axi4_trc_awid;
logic [AXI4_TRC_ADD_W-1:0]                   axi4_trc_awaddr;
logic [7:0]                                  axi4_trc_awlen;
logic [2:0]                                  axi4_trc_awsize;
logic [1:0]                                  axi4_trc_awburst;
logic                                        axi4_trc_awvalid;
logic                                        axi4_trc_awready;
logic [AXI4_TRC_DATA_W-1:0]                  axi4_trc_wdata;
logic [axi_if_trc_axi_pkg::AXI4_STRB_W-1:0]  axi4_trc_wstrb;
logic                                        axi4_trc_wlast;
logic                                        axi4_trc_wvalid;
logic                                        axi4_trc_wready;
logic [AXI4_TRC_ID_W-1:0]                    axi4_trc_bid;
logic [1:0]                                  axi4_trc_bresp;
logic                                        axi4_trc_bvalid;
logic                                        axi4_trc_bready;

// AXI4 HBM_PEM interface ==========================================================================
// Selector for internal axi_ram muxing
  logic [1:0]              axi4_pem_select;

// AXI4 HBM<->DUT interface
  /* Read channel */
  logic [PEM_PC_MAX_L-1 :0][AXI4_PEM_ID_W-1:0]                 dut_axi4_pem_arid;
  logic [PEM_PC_MAX_L-1 :0][AXI4_PEM_ADD_W-1:0]                dut_axi4_pem_araddr;
  logic [PEM_PC_MAX_L-1 :0][7:0]                               dut_axi4_pem_arlen;
  logic [PEM_PC_MAX_L-1 :0][2:0]                               dut_axi4_pem_arsize;
  logic [PEM_PC_MAX_L-1 :0][1:0]                               dut_axi4_pem_arburst;
  logic [PEM_PC_MAX_L-1 :0]                                    dut_axi4_pem_arvalid;
  logic [PEM_PC_MAX_L-1 :0]                                    dut_axi4_pem_arready;
  logic [PEM_PC_MAX_L-1 :0][AXI4_PEM_ID_W-1:0]                 dut_axi4_pem_rid;
  logic [PEM_PC_MAX_L-1 :0][AXI4_PEM_DATA_W-1:0]               dut_axi4_pem_rdata;
  logic [PEM_PC_MAX_L-1 :0][1:0]                               dut_axi4_pem_rresp;
  logic [PEM_PC_MAX_L-1 :0]                                    dut_axi4_pem_rlast;
  logic [PEM_PC_MAX_L-1 :0]                                    dut_axi4_pem_rvalid;
  logic [PEM_PC_MAX_L-1 :0]                                    dut_axi4_pem_rready;

  /*Write channel*/
  logic [PEM_PC_MAX_L-1 :0][AXI4_PEM_ID_W-1:0]                 dut_axi4_pem_awid;
  logic [PEM_PC_MAX_L-1 :0][AXI4_PEM_ADD_W-1:0]                dut_axi4_pem_awaddr;
  logic [PEM_PC_MAX_L-1 :0][7:0]                               dut_axi4_pem_awlen;
  logic [PEM_PC_MAX_L-1 :0][2:0]                               dut_axi4_pem_awsize;
  logic [PEM_PC_MAX_L-1 :0][1:0]                               dut_axi4_pem_awburst;
  logic [PEM_PC_MAX_L-1 :0]                                    dut_axi4_pem_awvalid;
  logic [PEM_PC_MAX_L-1 :0]                                    dut_axi4_pem_awready;
  logic [PEM_PC_MAX_L-1 :0][AXI4_PEM_DATA_W-1:0]               dut_axi4_pem_wdata;
  logic [PEM_PC_MAX_L-1 :0][axi_if_ct_axi_pkg::AXI4_STRB_W-1:0]dut_axi4_pem_wstrb;
  logic [PEM_PC_MAX_L-1 :0]                                    dut_axi4_pem_wlast;
  logic [PEM_PC_MAX_L-1 :0]                                    dut_axi4_pem_wvalid;
  logic [PEM_PC_MAX_L-1 :0]                                    dut_axi4_pem_wready;
  logic [PEM_PC_MAX_L-1 :0][AXI4_PEM_ID_W-1:0]                 dut_axi4_pem_bid;
  logic [PEM_PC_MAX_L-1 :0][1:0]                               dut_axi4_pem_bresp;
  logic [PEM_PC_MAX_L-1 :0]                                    dut_axi4_pem_bvalid;
  logic [PEM_PC_MAX_L-1 :0]                                    dut_axi4_pem_bready;


// AXI4 HBM<->TB interface
  /* Read channel */
  logic [PEM_PC_MAX_L-1 :0][AXI4_PEM_ID_W-1:0]                 tb_axi4_pem_arid;
  logic [PEM_PC_MAX_L-1 :0][AXI4_PEM_ADD_W-1:0]                tb_axi4_pem_araddr;
  logic [PEM_PC_MAX_L-1 :0][7:0]                               tb_axi4_pem_arlen;
  logic [PEM_PC_MAX_L-1 :0][2:0]                               tb_axi4_pem_arsize;
  logic [PEM_PC_MAX_L-1 :0][1:0]                               tb_axi4_pem_arburst;
  logic [PEM_PC_MAX_L-1 :0]                                    tb_axi4_pem_arvalid;
  logic [PEM_PC_MAX_L-1 :0]                                    tb_axi4_pem_arready;
  logic [PEM_PC_MAX_L-1 :0][AXI4_PEM_ID_W-1:0]                 tb_axi4_pem_rid;
  logic [PEM_PC_MAX_L-1 :0][AXI4_PEM_DATA_W-1:0]               tb_axi4_pem_rdata;
  logic [PEM_PC_MAX_L-1 :0][1:0]                               tb_axi4_pem_rresp;
  logic [PEM_PC_MAX_L-1 :0]                                    tb_axi4_pem_rlast;
  logic [PEM_PC_MAX_L-1 :0]                                    tb_axi4_pem_rvalid;
  logic [PEM_PC_MAX_L-1 :0]                                    tb_axi4_pem_rready;

  /*Write channel*/
  logic [PEM_PC_MAX_L-1 :0][AXI4_PEM_ID_W-1:0]                 tb_axi4_pem_awid;
  logic [PEM_PC_MAX_L-1 :0][AXI4_PEM_ADD_W-1:0]                tb_axi4_pem_awaddr;
  logic [PEM_PC_MAX_L-1 :0][7:0]                               tb_axi4_pem_awlen;
  logic [PEM_PC_MAX_L-1 :0][2:0]                               tb_axi4_pem_awsize;
  logic [PEM_PC_MAX_L-1 :0][1:0]                               tb_axi4_pem_awburst;
  logic [PEM_PC_MAX_L-1 :0]                                    tb_axi4_pem_awvalid;
  logic [PEM_PC_MAX_L-1 :0]                                    tb_axi4_pem_awready;
  logic [PEM_PC_MAX_L-1 :0][AXI4_PEM_DATA_W-1:0]               tb_axi4_pem_wdata;
  logic [PEM_PC_MAX_L-1 :0][axi_if_ct_axi_pkg::AXI4_STRB_W-1:0]tb_axi4_pem_wstrb;
  logic [PEM_PC_MAX_L-1 :0]                                    tb_axi4_pem_wlast;
  logic [PEM_PC_MAX_L-1 :0]                                    tb_axi4_pem_wvalid;
  logic [PEM_PC_MAX_L-1 :0]                                    tb_axi4_pem_wready;
  logic [PEM_PC_MAX_L-1 :0][AXI4_PEM_ID_W-1:0]                 tb_axi4_pem_bid;
  logic [PEM_PC_MAX_L-1 :0][1:0]                               tb_axi4_pem_bresp;
  logic [PEM_PC_MAX_L-1 :0]                                    tb_axi4_pem_bvalid;
  logic [PEM_PC_MAX_L-1 :0]                                    tb_axi4_pem_bready;

// AXI4 GLWE
  /* Read channel */
  logic [GLWE_PC_MAX_L-1 :0][AXI4_GLWE_ID_W-1:0]               dut_axi4_glwe_arid;
  logic [GLWE_PC_MAX_L-1 :0][AXI4_GLWE_ADD_W-1:0]              dut_axi4_glwe_araddr;
  logic [GLWE_PC_MAX_L-1 :0][7:0]                              dut_axi4_glwe_arlen;
  logic [GLWE_PC_MAX_L-1 :0][2:0]                              dut_axi4_glwe_arsize;
  logic [GLWE_PC_MAX_L-1 :0][1:0]                              dut_axi4_glwe_arburst;
  logic [GLWE_PC_MAX_L-1 :0]                                   dut_axi4_glwe_arvalid;
  logic [GLWE_PC_MAX_L-1 :0]                                   dut_axi4_glwe_arready;
  logic [GLWE_PC_MAX_L-1 :0][AXI4_GLWE_ID_W-1:0]               dut_axi4_glwe_rid;
  logic [GLWE_PC_MAX_L-1 :0][AXI4_GLWE_DATA_W-1:0]             dut_axi4_glwe_rdata;
  logic [GLWE_PC_MAX_L-1 :0][1:0]                              dut_axi4_glwe_rresp;
  logic [GLWE_PC_MAX_L-1 :0]                                   dut_axi4_glwe_rlast;
  logic [GLWE_PC_MAX_L-1 :0]                                   dut_axi4_glwe_rvalid;
  logic [GLWE_PC_MAX_L-1 :0]                                   dut_axi4_glwe_rready;

  /*Write channel*/
  logic [GLWE_PC_MAX_L-1 :0][AXI4_GLWE_ID_W-1:0]               tb_axi4_glwe_awid;
  logic [GLWE_PC_MAX_L-1 :0][AXI4_GLWE_ADD_W-1:0]              tb_axi4_glwe_awaddr;
  logic [GLWE_PC_MAX_L-1 :0][7:0]                              tb_axi4_glwe_awlen;
  logic [GLWE_PC_MAX_L-1 :0][2:0]                              tb_axi4_glwe_awsize;
  logic [GLWE_PC_MAX_L-1 :0][1:0]                              tb_axi4_glwe_awburst;
  logic [GLWE_PC_MAX_L-1 :0]                                   tb_axi4_glwe_awvalid;
  logic [GLWE_PC_MAX_L-1 :0]                                   tb_axi4_glwe_awready;
  logic [GLWE_PC_MAX_L-1 :0][AXI4_GLWE_DATA_W-1:0]             tb_axi4_glwe_wdata;
  logic [GLWE_PC_MAX_L-1 :0][AXI4_GLWE_DATA_W/8-1:0]           tb_axi4_glwe_wstrb;
  logic [GLWE_PC_MAX_L-1 :0]                                   tb_axi4_glwe_wlast;
  logic [GLWE_PC_MAX_L-1 :0]                                   tb_axi4_glwe_wvalid;
  logic [GLWE_PC_MAX_L-1 :0]                                   tb_axi4_glwe_wready;
  logic [GLWE_PC_MAX_L-1 :0][AXI4_GLWE_ID_W-1:0]               tb_axi4_glwe_bid;
  logic [GLWE_PC_MAX_L-1 :0][1:0]                              tb_axi4_glwe_bresp;
  logic [GLWE_PC_MAX_L-1 :0]                                   tb_axi4_glwe_bvalid;
  logic [GLWE_PC_MAX_L-1 :0]                                   tb_axi4_glwe_bready;

// AXI4 BSK
  /* Read channel */
  logic [BSK_PC_MAX_L-1 :0][AXI4_BSK_ID_W-1:0]                 dut_axi4_bsk_arid;
  logic [BSK_PC_MAX_L-1 :0][AXI4_BSK_ADD_W-1:0]                dut_axi4_bsk_araddr;
  logic [BSK_PC_MAX_L-1 :0][7:0]                               dut_axi4_bsk_arlen;
  logic [BSK_PC_MAX_L-1 :0][2:0]                               dut_axi4_bsk_arsize;
  logic [BSK_PC_MAX_L-1 :0][1:0]                               dut_axi4_bsk_arburst;
  logic [BSK_PC_MAX_L-1 :0]                                    dut_axi4_bsk_arvalid;
  logic [BSK_PC_MAX_L-1 :0]                                    dut_axi4_bsk_arready;
  logic [BSK_PC_MAX_L-1 :0][AXI4_BSK_ID_W-1:0]                 dut_axi4_bsk_rid;
  logic [BSK_PC_MAX_L-1 :0][AXI4_BSK_DATA_W-1:0]               dut_axi4_bsk_rdata;
  logic [BSK_PC_MAX_L-1 :0][1:0]                               dut_axi4_bsk_rresp;
  logic [BSK_PC_MAX_L-1 :0]                                    dut_axi4_bsk_rlast;
  logic [BSK_PC_MAX_L-1 :0]                                    dut_axi4_bsk_rvalid;
  logic [BSK_PC_MAX_L-1 :0]                                    dut_axi4_bsk_rready;

  /*Write channel*/
  logic [BSK_PC_MAX_L-1 :0][AXI4_BSK_ID_W-1:0]                 tb_axi4_bsk_awid;
  logic [BSK_PC_MAX_L-1 :0][AXI4_BSK_ADD_W-1:0]                tb_axi4_bsk_awaddr;
  logic [BSK_PC_MAX_L-1 :0][7:0]                               tb_axi4_bsk_awlen;
  logic [BSK_PC_MAX_L-1 :0][2:0]                               tb_axi4_bsk_awsize;
  logic [BSK_PC_MAX_L-1 :0][1:0]                               tb_axi4_bsk_awburst;
  logic [BSK_PC_MAX_L-1 :0]                                    tb_axi4_bsk_awvalid;
  logic [BSK_PC_MAX_L-1 :0]                                    tb_axi4_bsk_awready;
  logic [BSK_PC_MAX_L-1 :0][AXI4_BSK_DATA_W-1:0]               tb_axi4_bsk_wdata;
  logic [BSK_PC_MAX_L-1 :0][AXI4_BSK_DATA_W/8-1:0]             tb_axi4_bsk_wstrb;
  logic [BSK_PC_MAX_L-1 :0]                                    tb_axi4_bsk_wlast;
  logic [BSK_PC_MAX_L-1 :0]                                    tb_axi4_bsk_wvalid;
  logic [BSK_PC_MAX_L-1 :0]                                    tb_axi4_bsk_wready;
  logic [BSK_PC_MAX_L-1 :0][AXI4_BSK_ID_W-1:0]                 tb_axi4_bsk_bid;
  logic [BSK_PC_MAX_L-1 :0][1:0]                               tb_axi4_bsk_bresp;
  logic [BSK_PC_MAX_L-1 :0]                                    tb_axi4_bsk_bvalid;
  logic [BSK_PC_MAX_L-1 :0]                                    tb_axi4_bsk_bready;

// AXI4 KSK
  /* Read channel */
  logic [KSK_PC_MAX_L-1 :0][AXI4_KSK_ID_W-1:0]                 dut_axi4_ksk_arid;
  logic [KSK_PC_MAX_L-1 :0][AXI4_KSK_ADD_W-1:0]                dut_axi4_ksk_araddr;
  logic [KSK_PC_MAX_L-1 :0][7:0]                               dut_axi4_ksk_arlen;
  logic [KSK_PC_MAX_L-1 :0][2:0]                               dut_axi4_ksk_arsize;
  logic [KSK_PC_MAX_L-1 :0][1:0]                               dut_axi4_ksk_arburst;
  logic [KSK_PC_MAX_L-1 :0]                                    dut_axi4_ksk_arvalid;
  logic [KSK_PC_MAX_L-1 :0]                                    dut_axi4_ksk_arready;
  logic [KSK_PC_MAX_L-1 :0][AXI4_KSK_ID_W-1:0]                 dut_axi4_ksk_rid;
  logic [KSK_PC_MAX_L-1 :0][AXI4_KSK_DATA_W-1:0]               dut_axi4_ksk_rdata;
  logic [KSK_PC_MAX_L-1 :0][1:0]                               dut_axi4_ksk_rresp;
  logic [KSK_PC_MAX_L-1 :0]                                    dut_axi4_ksk_rlast;
  logic [KSK_PC_MAX_L-1 :0]                                    dut_axi4_ksk_rvalid;
  logic [KSK_PC_MAX_L-1 :0]                                    dut_axi4_ksk_rready;

  /*Write channel*/
  logic [KSK_PC_MAX_L-1 :0][AXI4_KSK_ID_W-1:0]                 tb_axi4_ksk_awid;
  logic [KSK_PC_MAX_L-1 :0][AXI4_KSK_ADD_W-1:0]                tb_axi4_ksk_awaddr;
  logic [KSK_PC_MAX_L-1 :0][7:0]                               tb_axi4_ksk_awlen;
  logic [KSK_PC_MAX_L-1 :0][2:0]                               tb_axi4_ksk_awsize;
  logic [KSK_PC_MAX_L-1 :0][1:0]                               tb_axi4_ksk_awburst;
  logic [KSK_PC_MAX_L-1 :0]                                    tb_axi4_ksk_awvalid;
  logic [KSK_PC_MAX_L-1 :0]                                    tb_axi4_ksk_awready;
  logic [KSK_PC_MAX_L-1 :0][AXI4_KSK_DATA_W-1:0]               tb_axi4_ksk_wdata;
  logic [KSK_PC_MAX_L-1 :0][AXI4_KSK_DATA_W/8-1:0]             tb_axi4_ksk_wstrb;
  logic [KSK_PC_MAX_L-1 :0]                                    tb_axi4_ksk_wlast;
  logic [KSK_PC_MAX_L-1 :0]                                    tb_axi4_ksk_wvalid;
  logic [KSK_PC_MAX_L-1 :0]                                    tb_axi4_ksk_wready;
  logic [KSK_PC_MAX_L-1 :0][AXI4_KSK_ID_W-1:0]                 tb_axi4_ksk_bid;
  logic [KSK_PC_MAX_L-1 :0][1:0]                               tb_axi4_ksk_bresp;
  logic [KSK_PC_MAX_L-1 :0]                                    tb_axi4_ksk_bvalid;
  logic [KSK_PC_MAX_L-1 :0]                                    tb_axi4_ksk_bready;

  // Instruction scheduler input / used in v80
  logic [PE_INST_W-1:0]                                        isc_dop;
  logic                                                        isc_dop_rdy;
  logic                                                        isc_dop_vld;

  logic [PE_INST_W-1:0]                                        isc_ack;
  logic                                                        isc_ack_rdy;
  logic                                                        isc_ack_vld;


// ============================================================================================== --
// Design under test instance
// ============================================================================================== --
  hpu_3parts #(
    .AXI4_TRC_ADD_W   (AXI4_TRC_ADD_W   ),
    .AXI4_PEM_ADD_W   (AXI4_PEM_ADD_W   ),
    .AXI4_GLWE_ADD_W  (AXI4_GLWE_ADD_W  ),
    .AXI4_BSK_ADD_W   (AXI4_BSK_ADD_W   ),
    .AXI4_KSK_ADD_W   (AXI4_KSK_ADD_W   ),
    .INTER_PART_PIPE  (INTER_PART_PIPE  )
  ) dut (
    .prc_free_clk    (clk        ) ,
    .prc_free_srst_n (s_rst_n    ) ,

    .prc_clk         (clk_g      ) ,
    .prc_ce          (clk_ce     ) ,
    .prc_srst_n      (/*UNUSED*/ ) ,

    .cfg_clk         (cfg_clk    ) ,
    .cfg_srst_n      (cfg_srst_n ) ,

    .isc_dop         (isc_dop    ) ,
    .isc_dop_rdy     (isc_dop_rdy) ,
    .isc_dop_vld     (isc_dop_vld) ,

    .isc_ack         (isc_ack    ) ,
    .isc_ack_rdy     (isc_ack_rdy) ,
    .isc_ack_vld     (isc_ack_vld) ,

    `AXIL_INSTANCE(s_axil_prc_1in3,tb_axil_prc,[P1_OFS])
    `AXIL_INSTANCE(s_axil_cfg_1in3,tb_axil_cfg,[P1_OFS])
    `AXIL_INSTANCE(s_axil_prc_3in3,tb_axil_prc,[P3_OFS])
    `AXIL_INSTANCE(s_axil_cfg_3in3,tb_axil_cfg,[P3_OFS])

    `AXI4_WR_INSTANCE(m_axi4_trc,axi4_trc,)
    `AXI4_RD_UNUSED_INSTANCE(m_axi4_trc)

    `AXI4_WR_INSTANCE(m_axi4_pem,dut_axi4_pem,[PEM_PC_MAX-1:0])
    `AXI4_RD_INSTANCE(m_axi4_pem,dut_axi4_pem,[PEM_PC_MAX-1:0])

    `AXI4_WR_UNUSED_INSTANCE(m_axi4_glwe)
    `AXI4_RD_INSTANCE(m_axi4_glwe,dut_axi4_glwe,[GLWE_PC_MAX-1:0])

    `AXI4_WR_UNUSED_INSTANCE(m_axi4_bsk)
    `AXI4_RD_INSTANCE(m_axi4_bsk,dut_axi4_bsk,[BSK_PC_MAX-1:0])

    `AXI4_WR_UNUSED_INSTANCE(m_axi4_ksk)
    `AXI4_RD_INSTANCE(m_axi4_ksk,dut_axi4_ksk,[KSK_PC_MAX-1:0])

    .interrupt      (hpu_irq)

  );

// ============================================================================================== --
// Ublaze
// ============================================================================================== --
// V80's RPU is modelized with the ublaze.

`ifdef FPGA_V80
  tb_hpu_ucore
  #(
    .AXI4_ADD_W    (AXI4_UCORE_ADD_W),
    .AXI4_DATA_W   (AXI4_UCORE_DATA_W),
    .AXI4_ID_W     (AXI4_UCORE_ID_W)
  ) tb_hpu_ucore (
    .clk           (clk),
    .s_rst_n       (s_rst_n),

    `AXI4_WR_INSTANCE(m_axi4,dut_axi4_ucore,)
    `AXI4_RD_INSTANCE(m_axi4,dut_axi4_ucore,)

    .isc_dop       (isc_dop),
    .isc_dop_rdy   (isc_dop_rdy),
    .isc_dop_vld   (isc_dop_vld),

    .isc_ack       (isc_ack),
    .isc_ack_rdy   (isc_ack_rdy),
    .isc_ack_vld   (isc_ack_vld)
  );
`endif


// ============================================================================================== --
// HBM memory emulation
// ============================================================================================== --
// ---------------------------------------------------------------------------------------------- --
// Memory used by UCORE (of the HPU or the testbench)
// ---------------------------------------------------------------------------------------------- --
  axi4_mem_with_select #(
    .SLAVE_IF(2),
    .DATA_WIDTH(AXI4_UCORE_DATA_W),
    .ADDR_WIDTH(AXI4_UCORE_ADD_W),
    .ID_WIDTH  (AXI4_UCORE_ID_W),
    .WR_CMD_BUF_DEPTH (MEM_WR_CMD_BUF_DEPTH),
    .RD_CMD_BUF_DEPTH (MEM_RD_CMD_BUF_DEPTH),
    .WR_DATA_LATENCY (MEM_WR_DATA_LATENCY),
    .RD_DATA_LATENCY (MEM_RD_DATA_LATENCY),
    .USE_WR_RANDOM (MEM_USE_WR_RANDOM),
    .USE_RD_RANDOM (MEM_USE_RD_RANDOM)
  ) axi4_mem_ucore (
    .clk          (clk),
    .rst          (!s_rst_n),

    .s_axi4_select_1h(axi4_ucore_select),
    .s_axi4_awid   ({tb_axi4_ucore_awid   , dut_axi4_ucore_awid   }),
    .s_axi4_awaddr ({tb_axi4_ucore_awaddr , dut_axi4_ucore_awaddr }),
    .s_axi4_awlen  ({tb_axi4_ucore_awlen  , dut_axi4_ucore_awlen  }),
    .s_axi4_awsize ({tb_axi4_ucore_awsize , dut_axi4_ucore_awsize }),
    .s_axi4_awburst({tb_axi4_ucore_awburst, dut_axi4_ucore_awburst}),
    .s_axi4_awlock ('0), // disable
    .s_axi4_awcache('0), // disable
    .s_axi4_awprot ('0), // disable
    .s_axi4_awqos  ('0), // disable
    .s_axi4_awregion('0), // disable
    .s_axi4_awvalid({tb_axi4_ucore_awvalid, dut_axi4_ucore_awvalid}),
    .s_axi4_awready({tb_axi4_ucore_awready, dut_axi4_ucore_awready}),
    .s_axi4_wdata  ({tb_axi4_ucore_wdata  , dut_axi4_ucore_wdata  }),
    .s_axi4_wstrb  ({tb_axi4_ucore_wstrb  , dut_axi4_ucore_wstrb  }),
    .s_axi4_wlast  ({tb_axi4_ucore_wlast  , dut_axi4_ucore_wlast  }),
    .s_axi4_wvalid ({tb_axi4_ucore_wvalid , dut_axi4_ucore_wvalid }),
    .s_axi4_wready ({tb_axi4_ucore_wready , dut_axi4_ucore_wready }),
    .s_axi4_bid    ({tb_axi4_ucore_bid    , dut_axi4_ucore_bid    }),
    .s_axi4_bresp  ({tb_axi4_ucore_bresp  , dut_axi4_ucore_bresp  }),
    .s_axi4_bvalid ({tb_axi4_ucore_bvalid , dut_axi4_ucore_bvalid }),
    .s_axi4_bready ({tb_axi4_ucore_bready , dut_axi4_ucore_bready }),
    .s_axi4_arid   ({tb_axi4_ucore_arid   , dut_axi4_ucore_arid   }),
    .s_axi4_araddr ({tb_axi4_ucore_araddr , dut_axi4_ucore_araddr }),
    .s_axi4_arlen  ({tb_axi4_ucore_arlen  , dut_axi4_ucore_arlen  }),
    .s_axi4_arsize ({tb_axi4_ucore_arsize , dut_axi4_ucore_arsize }),
    .s_axi4_arburst({tb_axi4_ucore_arburst, dut_axi4_ucore_arburst}),
    .s_axi4_arlock ('0), // disable
    .s_axi4_arcache('0), // disable
    .s_axi4_arprot ('0), // disable
    .s_axi4_arqos  ('0), // disable
    .s_axi4_arregion('0), // disable
    .s_axi4_arvalid({tb_axi4_ucore_arvalid, dut_axi4_ucore_arvalid}),
    .s_axi4_arready({tb_axi4_ucore_arready, dut_axi4_ucore_arready}),
    .s_axi4_rid    ({tb_axi4_ucore_rid    , dut_axi4_ucore_rid    }),
    .s_axi4_rdata  ({tb_axi4_ucore_rdata  , dut_axi4_ucore_rdata  }),
    .s_axi4_rresp  ({tb_axi4_ucore_rresp  , dut_axi4_ucore_rresp  }),
    .s_axi4_rlast  ({tb_axi4_ucore_rlast  , dut_axi4_ucore_rlast  }),
    .s_axi4_rvalid ({tb_axi4_ucore_rvalid , dut_axi4_ucore_rvalid }),
    .s_axi4_rready ({tb_axi4_ucore_rready , dut_axi4_ucore_rready })
  );

  // AXI4 hbm tb driver
  maxi4_if #(
    .AXI4_DATA_W(AXI4_UCORE_DATA_W),
    .AXI4_ADD_W (AXI4_UCORE_ADD_W),
    .AXI4_ID_W  (AXI4_UCORE_ID_W)
  ) maxi4_ucore_if (
    .clk(clk),
    .rst_n(s_rst_n)
  );

  // Connect interface on testbench signals
  // Write channel
  assign tb_axi4_ucore_awid         = maxi4_ucore_if.awid   ;
  assign tb_axi4_ucore_awaddr       = maxi4_ucore_if.awaddr ;
  assign tb_axi4_ucore_awlen        = maxi4_ucore_if.awlen  ;
  assign tb_axi4_ucore_awsize       = maxi4_ucore_if.awsize ;
  assign tb_axi4_ucore_awburst      = maxi4_ucore_if.awburst;
  assign tb_axi4_ucore_awvalid      = maxi4_ucore_if.awvalid;
  assign tb_axi4_ucore_wdata        = maxi4_ucore_if.wdata  ;
  assign tb_axi4_ucore_wstrb        = maxi4_ucore_if.wstrb  ;
  assign tb_axi4_ucore_wlast        = maxi4_ucore_if.wlast  ;
  assign tb_axi4_ucore_wvalid       = maxi4_ucore_if.wvalid ;
  assign tb_axi4_ucore_bready       = maxi4_ucore_if.bready ;

  assign maxi4_ucore_if.awready    = tb_axi4_ucore_awready;
  assign maxi4_ucore_if.wready     = tb_axi4_ucore_wready;
  assign maxi4_ucore_if.bid        = tb_axi4_ucore_bid;
  assign maxi4_ucore_if.bresp      = tb_axi4_ucore_bresp;
  assign maxi4_ucore_if.bvalid     = tb_axi4_ucore_bvalid;

  // Read channel
  assign tb_axi4_ucore_arid         = maxi4_ucore_if.arid   ;
  assign tb_axi4_ucore_araddr       = maxi4_ucore_if.araddr ;
  assign tb_axi4_ucore_arlen        = maxi4_ucore_if.arlen  ;
  assign tb_axi4_ucore_arsize       = maxi4_ucore_if.arsize ;
  assign tb_axi4_ucore_arburst      = maxi4_ucore_if.arburst;
  assign tb_axi4_ucore_arvalid      = maxi4_ucore_if.arvalid;
  assign tb_axi4_ucore_rready       = maxi4_ucore_if.rready;

  assign maxi4_ucore_if.arready    = tb_axi4_ucore_arready;
  assign maxi4_ucore_if.rid        = tb_axi4_ucore_rid;
  assign maxi4_ucore_if.rdata      = tb_axi4_ucore_rdata;
  assign maxi4_ucore_if.rresp      = tb_axi4_ucore_rresp;
  assign maxi4_ucore_if.rlast      = tb_axi4_ucore_rlast;
  assign maxi4_ucore_if.rvalid     = tb_axi4_ucore_rvalid;

// ---------------------------------------------------------------------------------------------- --
// HBM PC used by TraceManager
// ---------------------------------------------------------------------------------------------- --
  axi4_mem #(
    .DATA_WIDTH(AXI4_TRC_DATA_W),
    .ADDR_WIDTH(AXI4_TRC_ADD_W),
    .ID_WIDTH  (AXI4_TRC_ID_W),
    .WR_CMD_BUF_DEPTH (MEM_WR_CMD_BUF_DEPTH),
    .RD_CMD_BUF_DEPTH (MEM_RD_CMD_BUF_DEPTH),
    .WR_DATA_LATENCY (MEM_WR_DATA_LATENCY),
    .RD_DATA_LATENCY (MEM_RD_DATA_LATENCY),
    .USE_WR_RANDOM (MEM_USE_WR_RANDOM),
    .USE_RD_RANDOM (MEM_USE_RD_RANDOM)
  ) axi4_mem_trc (
    `AXI4_WR_INSTANCE(s_axi4,axi4_trc,)
    `AXI4_RD_INSTANCE(s_axi4,axi4_trc,)

    .clk          (clk),
    .rst          (!s_rst_n)

  );

  // AXI4 hbm tb driver
  maxi4_if #(
    .AXI4_DATA_W(AXI4_TRC_DATA_W),
    .AXI4_ADD_W (AXI4_TRC_ADD_W),
    .AXI4_ID_W  (AXI4_TRC_ID_W)
  ) maxi4_trc_if (
    .clk(clk),
    .rst_n(s_rst_n)
  );

  // Connect interface on testbench signals
  // Read channel
  assign axi4_trc_arid         = maxi4_trc_if.arid   ;
  assign axi4_trc_araddr       = maxi4_trc_if.araddr ;
  assign axi4_trc_arlen        = maxi4_trc_if.arlen  ;
  assign axi4_trc_arsize       = maxi4_trc_if.arsize ;
  assign axi4_trc_arburst      = maxi4_trc_if.arburst;
  assign axi4_trc_arvalid      = maxi4_trc_if.arvalid;
  assign axi4_trc_rready       = maxi4_trc_if.rready;

  assign maxi4_trc_if.arready    = axi4_trc_arready;
  assign maxi4_trc_if.rid        = axi4_trc_rid;
  assign maxi4_trc_if.rdata      = axi4_trc_rdata;
  assign maxi4_trc_if.rresp      = axi4_trc_rresp;
  assign maxi4_trc_if.rlast      = axi4_trc_rlast;
  assign maxi4_trc_if.rvalid     = axi4_trc_rvalid;

// ---------------------------------------------------------------------------------------------- --
// HBM PC used by PEM
// ---------------------------------------------------------------------------------------------- --
  generate
    for (genvar gen_p=0; gen_p<PEM_PC_MAX_L; gen_p=gen_p+1) begin : gen_ct_mem_loop
      axi4_mem_with_select #(
        .SLAVE_IF(2),
        .DATA_WIDTH(AXI4_PEM_DATA_W),
        .ADDR_WIDTH(AXI4_PEM_ADD_W),
        .ID_WIDTH  (AXI4_PEM_ID_W),
        .WR_CMD_BUF_DEPTH (MEM_WR_CMD_BUF_DEPTH),
        .RD_CMD_BUF_DEPTH (MEM_RD_CMD_BUF_DEPTH),
        .WR_DATA_LATENCY (MEM_WR_DATA_LATENCY + gen_p * 300),
        .RD_DATA_LATENCY (MEM_RD_DATA_LATENCY + gen_p * 350),
        .USE_WR_RANDOM (MEM_USE_WR_RANDOM),
        .USE_RD_RANDOM (MEM_USE_RD_RANDOM)
      ) axi4_mem_ct (
        .clk          (clk),
        .rst          (!s_rst_n),

        .s_axi4_select_1h(axi4_pem_select),
        .s_axi4_awid   ({tb_axi4_pem_awid   [gen_p], dut_axi4_pem_awid   [gen_p]}),
        .s_axi4_awaddr ({tb_axi4_pem_awaddr [gen_p], dut_axi4_pem_awaddr [gen_p]}),
        .s_axi4_awlen  ({tb_axi4_pem_awlen  [gen_p], dut_axi4_pem_awlen  [gen_p]}),
        .s_axi4_awsize ({tb_axi4_pem_awsize [gen_p], dut_axi4_pem_awsize [gen_p]}),
        .s_axi4_awburst({tb_axi4_pem_awburst[gen_p], dut_axi4_pem_awburst[gen_p]}),
        .s_axi4_awlock ('0), // disable
        .s_axi4_awcache('0), // disable
        .s_axi4_awprot ('0), // disable
        .s_axi4_awqos  ('0), // disable
        .s_axi4_awregion('0), // disable
        .s_axi4_awvalid({tb_axi4_pem_awvalid[gen_p], dut_axi4_pem_awvalid[gen_p]}),
        .s_axi4_awready({tb_axi4_pem_awready[gen_p], dut_axi4_pem_awready[gen_p]}),
        .s_axi4_wdata  ({tb_axi4_pem_wdata  [gen_p], dut_axi4_pem_wdata  [gen_p]}),
        .s_axi4_wstrb  ({tb_axi4_pem_wstrb  [gen_p], dut_axi4_pem_wstrb  [gen_p]}),
        .s_axi4_wlast  ({tb_axi4_pem_wlast  [gen_p], dut_axi4_pem_wlast  [gen_p]}),
        .s_axi4_wvalid ({tb_axi4_pem_wvalid [gen_p], dut_axi4_pem_wvalid [gen_p]}),
        .s_axi4_wready ({tb_axi4_pem_wready [gen_p], dut_axi4_pem_wready [gen_p]}),
        .s_axi4_bid    ({tb_axi4_pem_bid    [gen_p], dut_axi4_pem_bid    [gen_p]}),
        .s_axi4_bresp  ({tb_axi4_pem_bresp  [gen_p], dut_axi4_pem_bresp  [gen_p]}),
        .s_axi4_bvalid ({tb_axi4_pem_bvalid [gen_p], dut_axi4_pem_bvalid [gen_p]}),
        .s_axi4_bready ({tb_axi4_pem_bready [gen_p], dut_axi4_pem_bready [gen_p]}),
        .s_axi4_arid   ({tb_axi4_pem_arid   [gen_p], dut_axi4_pem_arid   [gen_p]}),
        .s_axi4_araddr ({tb_axi4_pem_araddr [gen_p], dut_axi4_pem_araddr [gen_p]}),
        .s_axi4_arlen  ({tb_axi4_pem_arlen  [gen_p], dut_axi4_pem_arlen  [gen_p]}),
        .s_axi4_arsize ({tb_axi4_pem_arsize [gen_p], dut_axi4_pem_arsize [gen_p]}),
        .s_axi4_arburst({tb_axi4_pem_arburst[gen_p], dut_axi4_pem_arburst[gen_p]}),
        .s_axi4_arlock ('0), // disable
        .s_axi4_arcache('0), // disable
        .s_axi4_arprot ('0), // disable
        .s_axi4_arqos  ('0), // disable
        .s_axi4_arregion('0), // disable
        .s_axi4_arvalid({tb_axi4_pem_arvalid[gen_p], dut_axi4_pem_arvalid[gen_p]}),
        .s_axi4_arready({tb_axi4_pem_arready[gen_p], dut_axi4_pem_arready[gen_p]}),
        .s_axi4_rid    ({tb_axi4_pem_rid    [gen_p], dut_axi4_pem_rid    [gen_p]}),
        .s_axi4_rdata  ({tb_axi4_pem_rdata  [gen_p], dut_axi4_pem_rdata  [gen_p]}),
        .s_axi4_rresp  ({tb_axi4_pem_rresp  [gen_p], dut_axi4_pem_rresp  [gen_p]}),
        .s_axi4_rlast  ({tb_axi4_pem_rlast  [gen_p], dut_axi4_pem_rlast  [gen_p]}),
        .s_axi4_rvalid ({tb_axi4_pem_rvalid [gen_p], dut_axi4_pem_rvalid [gen_p]}),
        .s_axi4_rready ({tb_axi4_pem_rready [gen_p], dut_axi4_pem_rready [gen_p]})
      );

      // AXI4 hbm tb driver
      maxi4_if #(
        .AXI4_DATA_W(AXI4_PEM_DATA_W),
        .AXI4_ADD_W (AXI4_PEM_ADD_W),
        .AXI4_ID_W  (AXI4_PEM_ID_W)
      ) maxi4_pem_if (
        .clk(clk),
        .rst_n(s_rst_n)
      );

      // Connect interface on testbench signals
      // Write channel
      assign tb_axi4_pem_awid[gen_p]         = maxi4_pem_if.awid   ;
      assign tb_axi4_pem_awaddr[gen_p]       = maxi4_pem_if.awaddr ;
      assign tb_axi4_pem_awlen[gen_p]        = maxi4_pem_if.awlen  ;
      assign tb_axi4_pem_awsize[gen_p]       = maxi4_pem_if.awsize ;
      assign tb_axi4_pem_awburst[gen_p]      = maxi4_pem_if.awburst;
      assign tb_axi4_pem_awvalid[gen_p]      = maxi4_pem_if.awvalid;
      assign tb_axi4_pem_wdata[gen_p]        = maxi4_pem_if.wdata  ;
      assign tb_axi4_pem_wstrb[gen_p]        = maxi4_pem_if.wstrb  ;
      assign tb_axi4_pem_wlast[gen_p]        = maxi4_pem_if.wlast  ;
      assign tb_axi4_pem_wvalid[gen_p]       = maxi4_pem_if.wvalid ;
      assign tb_axi4_pem_bready[gen_p]       = maxi4_pem_if.bready ;

      assign maxi4_pem_if.awready    = tb_axi4_pem_awready[gen_p];
      assign maxi4_pem_if.wready     = tb_axi4_pem_wready[gen_p];
      assign maxi4_pem_if.bid        = tb_axi4_pem_bid[gen_p];
      assign maxi4_pem_if.bresp      = tb_axi4_pem_bresp[gen_p];
      assign maxi4_pem_if.bvalid     = tb_axi4_pem_bvalid[gen_p];

      // Read channel
      assign tb_axi4_pem_arid[gen_p]         = maxi4_pem_if.arid   ;
      assign tb_axi4_pem_araddr[gen_p]       = maxi4_pem_if.araddr ;
      assign tb_axi4_pem_arlen[gen_p]        = maxi4_pem_if.arlen  ;
      assign tb_axi4_pem_arsize[gen_p]       = maxi4_pem_if.arsize ;
      assign tb_axi4_pem_arburst[gen_p]      = maxi4_pem_if.arburst;
      assign tb_axi4_pem_arvalid[gen_p]      = maxi4_pem_if.arvalid;
      assign tb_axi4_pem_rready[gen_p]       = maxi4_pem_if.rready;

      assign maxi4_pem_if.arready    = tb_axi4_pem_arready[gen_p];
      assign maxi4_pem_if.rid        = tb_axi4_pem_rid[gen_p];
      assign maxi4_pem_if.rdata      = tb_axi4_pem_rdata[gen_p];
      assign maxi4_pem_if.rresp      = tb_axi4_pem_rresp[gen_p];
      assign maxi4_pem_if.rlast      = tb_axi4_pem_rlast[gen_p];
      assign maxi4_pem_if.rvalid     = tb_axi4_pem_rvalid[gen_p];
    end
  endgenerate

// ---------------------------------------------------------------------------------------------- --
// HBM PC used by GLWE loading
// ---------------------------------------------------------------------------------------------- --
  generate
    for (genvar gen_p=0; gen_p<GLWE_PC_MAX_L; gen_p=gen_p+1) begin : gen_glwe_mem_loop
      axi4_mem #(
        .DATA_WIDTH(AXI4_GLWE_DATA_W),
        .ADDR_WIDTH(AXI4_GLWE_ADD_W),
        .ID_WIDTH  (AXI4_GLWE_ID_W),
        .WR_CMD_BUF_DEPTH (MEM_WR_CMD_BUF_DEPTH),
        .RD_CMD_BUF_DEPTH (MEM_RD_CMD_BUF_DEPTH),
        .WR_DATA_LATENCY (MEM_WR_DATA_LATENCY + gen_p * 300),
        .RD_DATA_LATENCY (MEM_RD_DATA_LATENCY + gen_p * 350),
        .USE_WR_RANDOM (1'b0),
        .USE_RD_RANDOM (MEM_USE_RD_RANDOM)
      ) axi4_mem_glwe (
        `AXI4_WR_INSTANCE(s_axi4,tb_axi4_glwe,[gen_p])
        `AXI4_RD_INSTANCE(s_axi4,dut_axi4_glwe,[gen_p])

        .clk          (clk),
        .rst          (!s_rst_n)

      );

      // AXI4 hbm tb driver
      maxi4_if #(
        .AXI4_DATA_W(AXI4_GLWE_DATA_W),
        .AXI4_ADD_W (AXI4_GLWE_ADD_W),
        .AXI4_ID_W  (AXI4_GLWE_ID_W)
      ) maxi4_glwe_if (
        .clk(clk),
        .rst_n(s_rst_n)
      );

      // Connect interface on testbench signals
      // Write channel
      assign tb_axi4_glwe_awid[gen_p]         = maxi4_glwe_if.awid   ;
      assign tb_axi4_glwe_awaddr[gen_p]       = maxi4_glwe_if.awaddr ;
      assign tb_axi4_glwe_awlen[gen_p]        = maxi4_glwe_if.awlen  ;
      assign tb_axi4_glwe_awsize[gen_p]       = maxi4_glwe_if.awsize ;
      assign tb_axi4_glwe_awburst[gen_p]      = maxi4_glwe_if.awburst;
      assign tb_axi4_glwe_awvalid[gen_p]      = maxi4_glwe_if.awvalid;
      assign tb_axi4_glwe_wdata[gen_p]        = maxi4_glwe_if.wdata  ;
      assign tb_axi4_glwe_wstrb[gen_p]        = maxi4_glwe_if.wstrb  ;
      assign tb_axi4_glwe_wlast[gen_p]        = maxi4_glwe_if.wlast  ;
      assign tb_axi4_glwe_wvalid[gen_p]       = maxi4_glwe_if.wvalid ;
      assign tb_axi4_glwe_bready[gen_p]       = maxi4_glwe_if.bready ;

      assign maxi4_glwe_if.awready    = tb_axi4_glwe_awready[gen_p];
      assign maxi4_glwe_if.wready     = tb_axi4_glwe_wready[gen_p];
      assign maxi4_glwe_if.bid        = tb_axi4_glwe_bid[gen_p];
      assign maxi4_glwe_if.bresp      = tb_axi4_glwe_bresp[gen_p];
      assign maxi4_glwe_if.bvalid     = tb_axi4_glwe_bvalid[gen_p];
    end
  endgenerate

// ---------------------------------------------------------------------------------------------- --
// HBM PC used by BSK
// ---------------------------------------------------------------------------------------------- --
  generate
    for (genvar gen_p=0; gen_p<BSK_PC_MAX_L; gen_p=gen_p+1) begin : gen_bsk_mem_loop
      axi4_mem #(
        .DATA_WIDTH(AXI4_BSK_DATA_W),
        .ADDR_WIDTH(AXI4_BSK_ADD_W),
        .ID_WIDTH  (AXI4_BSK_ID_W),
        .WR_CMD_BUF_DEPTH (MEM_WR_CMD_BUF_DEPTH),
        .RD_CMD_BUF_DEPTH (MEM_RD_CMD_BUF_DEPTH),
        .WR_DATA_LATENCY (MEM_WR_DATA_LATENCY + gen_p * 300),
        .RD_DATA_LATENCY (MEM_RD_DATA_LATENCY + gen_p * 350),
        .USE_WR_RANDOM (1'b0),
        .USE_RD_RANDOM (MEM_USE_RD_RANDOM)
      ) axi4_mem_bsk (
        `AXI4_WR_INSTANCE(s_axi4,tb_axi4_bsk,[gen_p])
        `AXI4_RD_INSTANCE(s_axi4,dut_axi4_bsk,[gen_p])

        .clk          (clk),
        .rst          (!s_rst_n)
      );

      // AXI4 hbm tb driver
      maxi4_if #(
        .AXI4_DATA_W(AXI4_BSK_DATA_W),
        .AXI4_ADD_W (AXI4_BSK_ADD_W),
        .AXI4_ID_W  (AXI4_BSK_ID_W)
      ) maxi4_bsk_if (
        .clk(clk),
        .rst_n(s_rst_n)
      );

      // Connect interface on testbench signals
      // Write channel
      assign tb_axi4_bsk_awid[gen_p]         = maxi4_bsk_if.awid   ;
      assign tb_axi4_bsk_awaddr[gen_p]       = maxi4_bsk_if.awaddr ;
      assign tb_axi4_bsk_awlen[gen_p]        = maxi4_bsk_if.awlen  ;
      assign tb_axi4_bsk_awsize[gen_p]       = maxi4_bsk_if.awsize ;
      assign tb_axi4_bsk_awburst[gen_p]      = maxi4_bsk_if.awburst;
      assign tb_axi4_bsk_awvalid[gen_p]      = maxi4_bsk_if.awvalid;
      assign tb_axi4_bsk_wdata[gen_p]        = maxi4_bsk_if.wdata  ;
      assign tb_axi4_bsk_wstrb[gen_p]        = maxi4_bsk_if.wstrb  ;
      assign tb_axi4_bsk_wlast[gen_p]        = maxi4_bsk_if.wlast  ;
      assign tb_axi4_bsk_wvalid[gen_p]       = maxi4_bsk_if.wvalid ;
      assign tb_axi4_bsk_bready[gen_p]       = maxi4_bsk_if.bready ;

      assign maxi4_bsk_if.awready    = tb_axi4_bsk_awready[gen_p];
      assign maxi4_bsk_if.wready     = tb_axi4_bsk_wready[gen_p];
      assign maxi4_bsk_if.bid        = tb_axi4_bsk_bid[gen_p];
      assign maxi4_bsk_if.bresp      = tb_axi4_bsk_bresp[gen_p];
      assign maxi4_bsk_if.bvalid     = tb_axi4_bsk_bvalid[gen_p];
    end
  endgenerate

// ---------------------------------------------------------------------------------------------- --
// HBM PC used by KSK
// ---------------------------------------------------------------------------------------------- --
  generate
    for (genvar gen_p=0; gen_p<KSK_PC_MAX_L; gen_p=gen_p+1) begin : gen_ksk_mem_loop
      axi4_mem #(
        .DATA_WIDTH(AXI4_KSK_DATA_W),
        .ADDR_WIDTH(AXI4_KSK_ADD_W),
        .ID_WIDTH  (AXI4_KSK_ID_W),
        .WR_CMD_BUF_DEPTH (MEM_WR_CMD_BUF_DEPTH),
        .RD_CMD_BUF_DEPTH (MEM_RD_CMD_BUF_DEPTH),
        .WR_DATA_LATENCY (MEM_WR_DATA_LATENCY + gen_p * 300),
        .RD_DATA_LATENCY (MEM_RD_DATA_LATENCY + gen_p * 350),
        .USE_WR_RANDOM (1'b0),
        .USE_RD_RANDOM (MEM_USE_RD_RANDOM)
      ) axi4_mem_ksk (
        `AXI4_WR_INSTANCE(s_axi4,tb_axi4_ksk,[gen_p])
        `AXI4_RD_INSTANCE(s_axi4,dut_axi4_ksk,[gen_p])

        .clk          (clk),
        .rst          (!s_rst_n)
      );

      // AXI4 hbm tb driver
      maxi4_if #(
        .AXI4_DATA_W(AXI4_KSK_DATA_W),
        .AXI4_ADD_W (AXI4_KSK_ADD_W),
        .AXI4_ID_W  (AXI4_KSK_ID_W)
      ) maxi4_ksk_if (
        .clk(clk),
        .rst_n(s_rst_n)
      );

      // Connect interface on testbench signals
      // Write channel
      assign tb_axi4_ksk_awid[gen_p]         = maxi4_ksk_if.awid   ;
      assign tb_axi4_ksk_awaddr[gen_p]       = maxi4_ksk_if.awaddr ;
      assign tb_axi4_ksk_awlen[gen_p]        = maxi4_ksk_if.awlen  ;
      assign tb_axi4_ksk_awsize[gen_p]       = maxi4_ksk_if.awsize ;
      assign tb_axi4_ksk_awburst[gen_p]      = maxi4_ksk_if.awburst;
      assign tb_axi4_ksk_awvalid[gen_p]      = maxi4_ksk_if.awvalid;
      assign tb_axi4_ksk_wdata[gen_p]        = maxi4_ksk_if.wdata  ;
      assign tb_axi4_ksk_wstrb[gen_p]        = maxi4_ksk_if.wstrb  ;
      assign tb_axi4_ksk_wlast[gen_p]        = maxi4_ksk_if.wlast  ;
      assign tb_axi4_ksk_wvalid[gen_p]       = maxi4_ksk_if.wvalid ;
      assign tb_axi4_ksk_bready[gen_p]       = maxi4_ksk_if.bready ;

      assign maxi4_ksk_if.awready    = tb_axi4_ksk_awready[gen_p];
      assign maxi4_ksk_if.wready     = tb_axi4_ksk_wready[gen_p];
      assign maxi4_ksk_if.bid        = tb_axi4_ksk_bid[gen_p];
      assign maxi4_ksk_if.bresp      = tb_axi4_ksk_bresp[gen_p];
      assign maxi4_ksk_if.bvalid     = tb_axi4_ksk_bvalid[gen_p];
    end
  endgenerate

// ---------------------------------------------------------------------------------------------- --
// AXIL
// ---------------------------------------------------------------------------------------------- --
  generate
    for (genvar gen_i=0; gen_i<2; gen_i=gen_i+1) begin : gen_prc_axil_loop
      // Axi4l driver
      maxil_if #(
      .AXIL_DATA_W(AXIL_DATA_W),
      .AXIL_ADD_W  (AXIL_ADD_W)
      ) maxil_drv_if ( .clk(clk), .rst_n(s_rst_n));

      // Connect interface on testbench signals
      assign tb_axil_prc_awaddr[gen_i]  = maxil_drv_if.awaddr;
      assign tb_axil_prc_awvalid[gen_i] = maxil_drv_if.awvalid;
      assign tb_axil_prc_wdata[gen_i]   = maxil_drv_if.wdata;
      assign tb_axil_prc_wstrb[gen_i]   = maxil_drv_if.wstrb;
      assign tb_axil_prc_wvalid[gen_i]  = maxil_drv_if.wvalid;
      assign tb_axil_prc_bready[gen_i]  = maxil_drv_if.bready;
      assign tb_axil_prc_araddr[gen_i]  = maxil_drv_if.araddr;
      assign tb_axil_prc_arvalid[gen_i] = maxil_drv_if.arvalid;
      assign tb_axil_prc_rready[gen_i]  = maxil_drv_if.rready;

      assign maxil_drv_if.awready = tb_axil_prc_awready[gen_i];
      assign maxil_drv_if.wready  = tb_axil_prc_wready[gen_i];
      assign maxil_drv_if.bresp   = tb_axil_prc_bresp[gen_i];
      assign maxil_drv_if.bvalid  = tb_axil_prc_bvalid[gen_i];
      assign maxil_drv_if.arready = tb_axil_prc_arready[gen_i];
      assign maxil_drv_if.rdata   = tb_axil_prc_rdata[gen_i];
      assign maxil_drv_if.rresp   = tb_axil_prc_rresp[gen_i];
      assign maxil_drv_if.rvalid  = tb_axil_prc_rvalid[gen_i];
    end // gen_prc_axil_loop
    for (genvar gen_i=0; gen_i<2; gen_i=gen_i+1) begin : gen_cfg_axil_loop
      // Axi4l driver
      maxil_if #(
      .AXIL_DATA_W(AXIL_DATA_W),
      .AXIL_ADD_W  (AXIL_ADD_W)
      ) maxil_drv_if ( .clk(cfg_clk), .rst_n(cfg_srst_n));

      // Connect interface on testbench signals
      assign tb_axil_cfg_awaddr[gen_i]  = maxil_drv_if.awaddr;
      assign tb_axil_cfg_awvalid[gen_i] = maxil_drv_if.awvalid;
      assign tb_axil_cfg_wdata[gen_i]   = maxil_drv_if.wdata;
      assign tb_axil_cfg_wstrb[gen_i]   = maxil_drv_if.wstrb;
      assign tb_axil_cfg_wvalid[gen_i]  = maxil_drv_if.wvalid;
      assign tb_axil_cfg_bready[gen_i]  = maxil_drv_if.bready;
      assign tb_axil_cfg_araddr[gen_i]  = maxil_drv_if.araddr;
      assign tb_axil_cfg_arvalid[gen_i] = maxil_drv_if.arvalid;
      assign tb_axil_cfg_rready[gen_i]  = maxil_drv_if.rready;

      assign maxil_drv_if.awready = tb_axil_cfg_awready[gen_i];
      assign maxil_drv_if.wready  = tb_axil_cfg_wready[gen_i];
      assign maxil_drv_if.bresp   = tb_axil_cfg_bresp[gen_i];
      assign maxil_drv_if.bvalid  = tb_axil_cfg_bvalid[gen_i];
      assign maxil_drv_if.arready = tb_axil_cfg_arready[gen_i];
      assign maxil_drv_if.rdata   = tb_axil_cfg_rdata[gen_i];
      assign maxil_drv_if.rresp   = tb_axil_cfg_rresp[gen_i];
      assign maxil_drv_if.rvalid  = tb_axil_cfg_rvalid[gen_i];
    end // gen_cfg_axil_loop
  endgenerate

// ============================================================================================== --
// Utilities function to generate stimulus
// ============================================================================================== --

// ---------------------------------------------------------------------------------------------- --
// Soft Reset
// ---------------------------------------------------------------------------------------------- --
task automatic soft_reset;
begin
  logic [REG_DATA_W-1:0] rdata;

  $display("%t > INFO: Soft Reset",$time);

  gen_cfg_axil_loop[P3_OFS].maxil_drv_if.write_trans(HPU_RESET_TRIGGER_OFS, 1);
  for(rdata = '0; !rdata[REG_DATA_W-1];)
    gen_cfg_axil_loop[P3_OFS].maxil_drv_if.read_trans(HPU_RESET_TRIGGER_OFS, rdata);
end
endtask

// ---------------------------------------------------------------------------------------------- --
// check_dummy_reg
// ---------------------------------------------------------------------------------------------- --
task automatic check_dummy_reg;
begin
  logic [1:0][1:0][3:0][REG_DATA_W-1:0] rdata;
  logic [1:0][1:0][3:0][REG_DATA_W-1:0] ref_rdata;

  for (int i=0; i<2; i=i+1) // each part
    for (int k=0; k<2; k=k+1) // each clock
      for (int j=0; j<4; j=j+1) // 4 dummy registers
        ref_rdata[i][k][j] = {4{{4'(j),4'(i*2+k+1)}}};

  $display("%t > INFO: Check dummy registers",$time);

  for (int j=0; j<4; j=j+1) begin
    gen_cfg_axil_loop[P1_OFS].maxil_drv_if.read_trans(ENTRY_CFG_1IN3_DUMMY_VAL0_OFS + j*REG_DATA_BYTES, rdata[P1_OFS][0][j]);
    gen_prc_axil_loop[P1_OFS].maxil_drv_if.read_trans(ENTRY_PRC_1IN3_DUMMY_VAL0_OFS + j*REG_DATA_BYTES, rdata[P1_OFS][1][j]);
    $display("%t > INFO: Read Dummy reg P_1 cfg[%0d] : 0x%08x",$time, j,rdata[P1_OFS][0][j]);
    $display("%t > INFO: Read Dummy reg P_1 prc[%0d] : 0x%08x",$time, j,rdata[P1_OFS][1][j]);

    assert(rdata[P1_OFS][0][j] == ref_rdata[P1_OFS][0][j])
    else begin
      $fatal(1,"%t > ERROR: Wrong value read in P_1 dummy cfg reg[%0d]. exp=0x%08x seen=0x%08x",
             $time, j, ref_rdata[P1_OFS][0][j], rdata[P1_OFS][0][j]);
    end
    assert(rdata[P1_OFS][1][j] == ref_rdata[P1_OFS][1][j])
    else begin
      $fatal(1,"%t > ERROR: Wrong value read in P_1 dummy prc reg[%0d]. exp=0x%08x seen=0x%08x",
             $time, j, ref_rdata[P1_OFS][1][j], rdata[P1_OFS][1][j]);
    end
  end
  for (int j=0; j<4; j=j+1) begin
    gen_cfg_axil_loop[P3_OFS].maxil_drv_if.read_trans(ENTRY_CFG_3IN3_DUMMY_VAL0_OFS + j*REG_DATA_BYTES, rdata[P3_OFS][0][j]);
    gen_prc_axil_loop[P3_OFS].maxil_drv_if.read_trans(ENTRY_PRC_3IN3_DUMMY_VAL0_OFS + j*REG_DATA_BYTES, rdata[P3_OFS][1][j]);
    $display("%t > INFO: Read Dummy reg P_1 cfg[%0d] : 0x%08x",$time, j,rdata[P3_OFS][0][j]);
    $display("%t > INFO: Read Dummy reg P_1 prc[%0d] : 0x%08x",$time, j,rdata[P3_OFS][1][j]);

    assert(rdata[P3_OFS][0][j] == ref_rdata[P3_OFS][0][j])
    else begin
      $fatal(1,"%t > ERROR: Wrong value read in P_1 dummy cfg reg[%0d]. exp=0x%08x seen=0x%08x",
             $time, j, ref_rdata[P3_OFS][0][j], rdata[P3_OFS][0][j]);
    end
    assert(rdata[P3_OFS][1][j] == ref_rdata[P3_OFS][1][j])
    else begin
      $fatal(1,"%t > ERROR: Wrong value read in P_1 dummy prc reg[%0d]. exp=0x%08x seen=0x%08x",
             $time, j, ref_rdata[P3_OFS][1][j], rdata[P3_OFS][1][j]);
    end
  end

end
endtask

// ---------------------------------------------------------------------------------------------- --
// configure_hpu
// ---------------------------------------------------------------------------------------------- --
task automatic configure_hpu;
begin
  bpip_use_t bpip_use;
  keyswitch_config_t ks_config;

  $display("%t > INFO: Configure HPU",$time);

  bpip_use.use_bpip        = USE_BPIP;
  bpip_use.use_opportunism = USE_BPIP_OPPORTUNISM;

  gen_cfg_axil_loop[P1_OFS].maxil_drv_if.write_trans(BPIP_USE_OFS, bpip_use);
  gen_cfg_axil_loop[P1_OFS].maxil_drv_if.write_trans(BPIP_TIMEOUT_OFS, BPIP_TIMEOUT);

  ks_config.mod_switch_mean_comp = MOD_SWITCH_MEAN_COMP;
  gen_cfg_axil_loop[P1_OFS].maxil_drv_if.write_trans(KEYSWITCH_CONFIG_OFS, ks_config);
end
endtask

// ---------------------------------------------------------------------------------------------- --
// init_iop2dop_table
// ---------------------------------------------------------------------------------------------- --
task automatic init_iop2dop_table;
  inout logic [PE_INST_W-1:0]   dop_q[DOP_NB-1:0][$];
  logic [AXI4_UCORE_ADD_W-1:0]  lut_addr;
  logic [AXI4_UCORE_ADD_W-1:0]  tr_addr;
  logic [AXI4_UCORE_DATA_W-1:0] addr_q[$];
  logic [AXI4_UCORE_DATA_W-1:0] size_q[$]; // Workaround
  logic [IOP_W-1:0]             iop_id;
  integer                       size;
begin
  // TB take control of the hbm
  axi4_ucore_select = TB_DRIVE_HBM;

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
    assert ((size+1)>= MIN_IOP_SIZE)
    else $fatal(1,"%t > ERROR: Instruction stream doesn't match minimum sized requirement. This could induce an overflow of the sync_id counter and a deadlock.", $time);
    $display("%t > INFO: Write IOp 0x%02x tr_table @0x%0x of %0d elements", $time, iop_id,addr_q[iop_id],size);

    // Write the size.
    // Since maxi4_ucore_if.write_trans only accepts queue, put the size in a queue of a single element.
    size_q.delete();
    size_q.push_back(size);
    maxi4_ucore_if.write_trans(tr_addr, size_q);
    tr_addr += REG_DATA_BYTES;
    // Write DOP associated to the iop_id
    maxi4_ucore_if.write_trans(tr_addr, dop_q[i]);
    tr_addr += REG_DATA_BYTES*size;
  end

  // Write cross-reference table iop_id <-> dop_code address
  maxi4_ucore_if.write_trans(lut_addr, addr_q);

  // TB release control of the hbm
  axi4_ucore_select = DUT_DRIVE_HBM;
end
endtask

// ---------------------------------------------------------------------------------------------- --
// push_work
// ---------------------------------------------------------------------------------------------- --
task automatic push_work;
  inout logic [AXIL_DATA_W-1:0] iopq[$];
  inout int                      workq[$];
  logic [AXIL_DATA_W-1:0]     iop; // To identify
  logic [AXIL_DATA_W:0]       word;
begin
  iop = iopq[0];
  while (iopq.size() > 0) begin
    word = iopq.pop_front();
    `WORKQ_DRV_IF .write_trans(`WORKQ_REG_PKG ::WORKACK_WORKQ_OFS, word);
  end

  $display("%t > INFO: Insert IOp %x", $time, iop);

  workq.push_back(iop);
end
endtask

// ---------------------------------------------------------------------------------------------- --
// pop_ack
// ---------------------------------------------------------------------------------------------- --
task automatic pop_ack;
  inout int work_q[$];
  output int opcode_ack;
  logic [7:0] ucore_version_major;
  logic [7:0] ucore_version_minor;
begin
  do begin
     repeat(500) @(posedge clk);
     `WORKQ_DRV_IF .read_trans(`WORKQ_REG_PKG ::WORKACK_ACKQ_OFS, opcode_ack);
  end while (opcode_ack == ACKQ_RD_ERR);

  // Check that received value match or is a version response
  if (work_q[0] == UCORE_VERSION_IOP) begin
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
    assert(opcode_ack == work_q[0])
      else begin
        #5 $fatal(1, "%t > ERROR: opcode ack mismatch [exp %x != %x dut]", $time, work_q[0], opcode_ack);
      end
  end

  // Remove opcode from work_q
  work_q.pop_front();
end
endtask

// ---------------------------------------------------------------------------------------------- --
// write_blwe
// ---------------------------------------------------------------------------------------------- --
task automatic write_blwe;
  output [PEM_PC_MAX_L-1:0][AXI4_PEM_ADD_W-1: 0] ct_ofs_addr;
  bit [AXI4_PEM_ADD_W-1: 0] rand_addr_0;
  logic [AXI4_PEM_DATA_W-1: 0] blwe_q[$];
  logic [AXI4_PEM_DATA_W-1: 0] d;
begin

  // random addresses
  for (int j=0; j<PEM_PC_MAX_L; j=j+1) begin
    rand_addr_0 = $urandom_range(0, 1<< (AXI4_PEM_ADD_W-1)) & {1'b0,{(AXI4_PEM_ADD_W-(12+1)){1'b1}}, {(12){1'b0}} };
    ct_ofs_addr[j] = rand_addr_0;
  end

  $display("%t > INFO: Write BLWE  BLWE_NB=%0d BLWE_LIST[0]=%0d",$time,BLWE_NB, BLWE_LIST[0]);
  for (int i=0; i<BLWE_NB; i=i+1) begin
    bit[15:0] slot;

    slot = BLWE_LIST[i];
    $display("%t > INFO: Write BLWE  i=%0d slot=%0d",$time,i, slot);

    for (int p=0; p<PEM_PC; p=p+1) begin
    // Read from file
      string blwe_filename = $sformatf("%s_%04x_%01x.hex", BLWE_FILE_PREFIX, slot, p);
      read_data #(.DATA_W(AXI4_PEM_DATA_W)) blwe_rd    = new(.filename(blwe_filename), .data_type(FILE_DATA_TYPE));
      if (!blwe_rd.open()) begin
        $display("%t > ERROR: opening file %0s failed\n", $time, blwe_filename);
        $finish;
      end

      // Read file and flush in a queue
      blwe_q.delete();
      d = blwe_rd.get_next_data();
      while (! blwe_rd.is_st_eof()) begin
        blwe_q.push_back(d);
        d = blwe_rd.get_next_data();
      end

      $display("%t > INFO: Write BLWE %s @0x%08x (%0d words/PC%0d)",$time,blwe_filename,ct_ofs_addr[p] + slot * CT_MEM_BYTES, blwe_q.size(),p);
      // Write queue content in memory
      // /!\ Workaround, since p is considered a non-constant
      if (p==0)
        $readmemh(blwe_filename,gen_ct_mem_loop[0].axi4_mem_ct.axi4_mem_inner.axi4_ram_ct_wr.mem, (ct_ofs_addr[p] + slot * CT_MEM_BYTES)/AXI4_PEM_DATA_BYTES, (ct_ofs_addr[p] + slot * CT_MEM_BYTES)/AXI4_PEM_DATA_BYTES + blwe_q.size());
      else if (p==1)
        $readmemh(blwe_filename,gen_ct_mem_loop[1].axi4_mem_ct.axi4_mem_inner.axi4_ram_ct_wr.mem, (ct_ofs_addr[p] + slot * CT_MEM_BYTES)/AXI4_PEM_DATA_BYTES, (ct_ofs_addr[p] + slot * CT_MEM_BYTES)/AXI4_PEM_DATA_BYTES + blwe_q.size());
      else
        $fatal(1,"%t > ERROR: Workaround to fill ct RAM is not enough.", $time);
    end // for p
  end // for i
end
endtask

// ---------------------------------------------------------------------------------------------- --
// write_blwe_add
// ---------------------------------------------------------------------------------------------- --
task automatic write_blwe_add;
  input [PEM_PC_MAX_L-1:0][AXI4_PEM_ADD_W-1: 0] blwe_addr;
begin
  // Init ct fields
  for (int j=0; j<PEM_PC_MAX_L; j=j+1) begin
      gen_cfg_axil_loop[P1_OFS].maxil_drv_if.write_trans(HBM_AXI4_ADDR_1IN3_CT_PC0_LSB_OFS + 2*j*REG_DATA_BYTES, blwe_addr[j] & 'hffffffff);
      gen_cfg_axil_loop[P1_OFS].maxil_drv_if.write_trans(HBM_AXI4_ADDR_1IN3_CT_PC0_MSB_OFS + 2*j*REG_DATA_BYTES, (blwe_addr[j]>> 32) & 'hffffffff);
  end
end
endtask

// ---------------------------------------------------------------------------------------------- --
// read_and_check_blwe
// ---------------------------------------------------------------------------------------------- --
task automatic read_and_check_blwe;
  input int index;
  input bit do_check;
  input [PEM_PC_MAX_L-1:0][AXI4_PEM_ADD_W-1: 0] ct_ofs_addr;
  logic [AXI4_PEM_DATA_W-1: 0] ref_blwe_q[PEM_PC-1:0][$];
  logic [AXI4_PEM_DATA_W-1: 0] rd_blwe_q[PEM_PC-1:0][$];
begin
  bit[15:0] slot;

  slot = OUT_BLWE_LIST[index];

  fork
    begin : isolation_process
      for(int j=0; j <PEM_PC; ++j) begin : for_pc_loop
        fork
          automatic int p = j;
          begin
            int word_nb;
            word_nb = (p==0) ? pem_common_param_pkg::AXI4_WORD_PER_PC0 : pem_common_param_pkg::AXI4_WORD_PER_PC;

            rd_blwe_q[p].delete();
            // Read queue content in memory
            // /!\ Workaround, since p is considered a non-constant
            $display("%t > INFO: Read OUT_BLWE #%0d @0x%0x (%0d words / PC%0d)", $time, index, ct_ofs_addr[p] + slot * CT_MEM_BYTES, word_nb, p);
            if (p==0) begin
              int cnt;
              cnt = 0;
              while (cnt < word_nb) begin
                rd_blwe_q[p].push_back(gen_ct_mem_loop[0].axi4_mem_ct.axi4_mem_inner.axi4_ram_ct_wr.mem[(ct_ofs_addr[p] + slot * CT_MEM_BYTES)/AXI4_PEM_DATA_BYTES +cnt]);
                cnt = cnt + 1;
              end
            end
            else if (p==1) begin
              int cnt;
              cnt = 0;
              while (cnt < word_nb) begin
                rd_blwe_q[p].push_back(gen_ct_mem_loop[1].axi4_mem_ct.axi4_mem_inner.axi4_ram_ct_wr.mem[(ct_ofs_addr[p] + slot * CT_MEM_BYTES)/AXI4_PEM_DATA_BYTES +cnt]);
                cnt = cnt + 1;
              end
            end
            else
              $fatal(1,"%t > ERROR: Workaround to read ct RAM is not enough.", $time);

            if (do_check) begin
              logic [AXI4_PEM_DATA_W-1: 0] d;
              string ref_blwe_filename = $sformatf("%s_%04x_%01x.hex", OUT_BLWE_FILE_PREFIX, slot, p);
              read_data #(.DATA_W(AXI4_PEM_DATA_W)) ref_blwe_rd    = new(.filename(ref_blwe_filename), .data_type(FILE_DATA_TYPE));
              if (!ref_blwe_rd.open()) begin
                $display("%t > ERROR: opening file %0s failed\n", $time, ref_blwe_filename);
                $finish;
              end

              // Read file and flush in a queue
              ref_blwe_q[p].delete();
              d = ref_blwe_rd.get_next_data();
              while (! ref_blwe_rd.is_st_eof()) begin
                ref_blwe_q[p].push_back(d);
                d = ref_blwe_rd.get_next_data();
              end

              for (int i=0; i<pem_common_param_pkg::AXI4_WORD_PER_PC; i=i+1) begin
                logic [AXI4_PEM_DATA_W-1:0] rd_data;
                logic [AXI4_PEM_DATA_W-1:0] ref_data;
                rd_data = rd_blwe_q[p].pop_front();
                ref_data = ref_blwe_q[p].pop_front();
                assert(ref_data == rd_data)
                else begin
                  $display("%t > ERROR: BLWE mismatch #%0d pc=%0d slot=0x%04x data#%0d", $time, index, p, slot,i);
                  $display("%t >        exp=0x%0x", $time,ref_data);
                  $display("%t >        seen=0x%0x",$time,rd_data);
                  #5 $fatal(1, "%t > FAILURE",$time);
                end
              end // for i
              if (p == 0) begin // check body
                logic [AXI4_PEM_DATA_W-1:0] rd_data;
                logic [AXI4_PEM_DATA_W-1:0] ref_data;
                rd_data  = rd_blwe_q[p].pop_front();
                ref_data = ref_blwe_q[p].pop_front();

                for (int b=0; b <AXI4_PEM_DATA_W/8; b=b+1) begin
                  if (ref_data[b*8+:8] !== 'x) begin
                    assert(rd_data[b*8+:8] == ref_data[b*8+:8])
                    else begin
                      $display("%t > ERROR: BLWE body mismatch #%0d pc=%0d slot=0x%04x", $time, index, p, slot);
                      $display("%t >        exp=0x%0x",  $time,ref_data);
                      $display("%t >        seen=0x%0x", $time,rd_data);
                      #5 $fatal(1, "%t > FAILURE",$time);
                    end
                  end
                end

              end // if pc == 0, check body
            end // do check

           end // fork
        join_none
      end : for_pc_loop
    wait fork; // will not wait for some other process
   end : isolation_process
   join

end
endtask

// ---------------------------------------------------------------------------------------------- --
// write_bsk
// ---------------------------------------------------------------------------------------------- --
task automatic write_bsk;
  output [BSK_PC_MAX_L-1:0][AXI4_BSK_ADD_W-1: 0] bsk_addr;
  bit [BSK_PC_MAX_L-1:0][AXI4_BSK_ADD_W-1: 0] rand_addr;
  logic [AXI4_BSK_DATA_W-1: 0] bsk_q[$];
  logic [AXI4_BSK_DATA_W-1: 0] d;
begin

  // random addresses
  for (int i=0; i<BSK_PC_MAX_L; i=i+1) begin
    rand_addr[i] = $urandom_range(0, 1<< (AXI4_BSK_ADD_W-1)) & {{(AXI4_BSK_ADD_W-12){1'b1}}, {(12){1'b0}} };
  end

  // Write bsk in DDR
  for (int i=0; i<BSK_PC; i=i+1) begin
    // Open file associated with current PC
    string bsk_f = $sformatf("%s_%01x.hex", BSK_FILE_PREFIX, i);
    read_data #(.DATA_W(AXI4_BSK_DATA_W)) rdata_bsk    = new(.filename(bsk_f), .data_type(FILE_DATA_TYPE));
    if (!rdata_bsk.open()) begin
      $display("%t > ERROR: opening file %0s failed\n", $time, bsk_f);
      $finish;
    end

    // Read file and flush in a queue
    bsk_q.delete();
    d = rdata_bsk.get_next_data();
    while (! rdata_bsk.is_st_eof()) begin
      bsk_q.push_back(d);
      d = rdata_bsk.get_next_data();
    end

    // Write queue content in ddr
    // /!\ Workaround, since i is considered not a constant
    $display("%t > INFO: Load BSK in PC%0d from @0x%0x to @0x%0x",$time, i,  rand_addr[i], rand_addr[i] + bsk_q.size()*AXI4_BSK_DATA_BYTES);
    if (i==0)
      $readmemh(bsk_f,gen_bsk_mem_loop[0].axi4_mem_bsk.axi4_ram_ct_wr.mem, rand_addr[i] / AXI4_BSK_DATA_BYTES, rand_addr[i]/AXI4_BSK_DATA_BYTES + bsk_q.size());
    else if (i==1)
      $readmemh(bsk_f,gen_bsk_mem_loop[1].axi4_mem_bsk.axi4_ram_ct_wr.mem, rand_addr[i] / AXI4_BSK_DATA_BYTES, rand_addr[i] / AXI4_BSK_DATA_BYTES + bsk_q.size());
    else if (i==2)
      $readmemh(bsk_f,gen_bsk_mem_loop[2].axi4_mem_bsk.axi4_ram_ct_wr.mem, rand_addr[i] / AXI4_BSK_DATA_BYTES, rand_addr[i] / AXI4_BSK_DATA_BYTES + bsk_q.size());
    else if (i==3)
      $readmemh(bsk_f,gen_bsk_mem_loop[3].axi4_mem_bsk.axi4_ram_ct_wr.mem, rand_addr[i] / AXI4_BSK_DATA_BYTES, rand_addr[i] / AXI4_BSK_DATA_BYTES + bsk_q.size());
    else if (i==4)
      $readmemh(bsk_f,gen_bsk_mem_loop[4].axi4_mem_bsk.axi4_ram_ct_wr.mem, rand_addr[i] / AXI4_BSK_DATA_BYTES, rand_addr[i] / AXI4_BSK_DATA_BYTES + bsk_q.size());
    else if (i==5)
      $readmemh(bsk_f,gen_bsk_mem_loop[5].axi4_mem_bsk.axi4_ram_ct_wr.mem, rand_addr[i] / AXI4_BSK_DATA_BYTES, rand_addr[i] / AXI4_BSK_DATA_BYTES + bsk_q.size());
    else if (i==6)
      $readmemh(bsk_f,gen_bsk_mem_loop[6].axi4_mem_bsk.axi4_ram_ct_wr.mem, rand_addr[i] / AXI4_BSK_DATA_BYTES, rand_addr[i] / AXI4_BSK_DATA_BYTES + bsk_q.size());
    else if (i==7)
      $readmemh(bsk_f,gen_bsk_mem_loop[7].axi4_mem_bsk.axi4_ram_ct_wr.mem, rand_addr[i] / AXI4_BSK_DATA_BYTES, rand_addr[i] / AXI4_BSK_DATA_BYTES + bsk_q.size());
    else if (i==8)
      $readmemh(bsk_f,gen_bsk_mem_loop[8].axi4_mem_bsk.axi4_ram_ct_wr.mem, rand_addr[i] / AXI4_BSK_DATA_BYTES, rand_addr[i]/AXI4_BSK_DATA_BYTES + bsk_q.size());
    else if (i==9)
      $readmemh(bsk_f,gen_bsk_mem_loop[9].axi4_mem_bsk.axi4_ram_ct_wr.mem, rand_addr[i] / AXI4_BSK_DATA_BYTES, rand_addr[i] / AXI4_BSK_DATA_BYTES + bsk_q.size());
    else if (i==10)
      $readmemh(bsk_f,gen_bsk_mem_loop[10].axi4_mem_bsk.axi4_ram_ct_wr.mem, rand_addr[i] / AXI4_BSK_DATA_BYTES, rand_addr[i] / AXI4_BSK_DATA_BYTES + bsk_q.size());
    else if (i==11)
      $readmemh(bsk_f,gen_bsk_mem_loop[11].axi4_mem_bsk.axi4_ram_ct_wr.mem, rand_addr[i] / AXI4_BSK_DATA_BYTES, rand_addr[i] / AXI4_BSK_DATA_BYTES + bsk_q.size());
    else if (i==12)
      $readmemh(bsk_f,gen_bsk_mem_loop[12].axi4_mem_bsk.axi4_ram_ct_wr.mem, rand_addr[i] / AXI4_BSK_DATA_BYTES, rand_addr[i] / AXI4_BSK_DATA_BYTES + bsk_q.size());
    else if (i==13)
      $readmemh(bsk_f,gen_bsk_mem_loop[13].axi4_mem_bsk.axi4_ram_ct_wr.mem, rand_addr[i] / AXI4_BSK_DATA_BYTES, rand_addr[i] / AXI4_BSK_DATA_BYTES + bsk_q.size());
    else if (i==14)
      $readmemh(bsk_f,gen_bsk_mem_loop[14].axi4_mem_bsk.axi4_ram_ct_wr.mem, rand_addr[i] / AXI4_BSK_DATA_BYTES, rand_addr[i] / AXI4_BSK_DATA_BYTES + bsk_q.size());
    else if (i==15)
      $readmemh(bsk_f,gen_bsk_mem_loop[15].axi4_mem_bsk.axi4_ram_ct_wr.mem, rand_addr[i] / AXI4_BSK_DATA_BYTES, rand_addr[i] / AXI4_BSK_DATA_BYTES + bsk_q.size());
    else
      $fatal(1,"%t > ERROR: Workaround to fill BSK RAM is not enough.", $time);

  end
  // output the associated addr in ddr
  bsk_addr = rand_addr;
end
endtask

// ---------------------------------------------------------------------------------------------- --
// write_unset_bsk_add
// ---------------------------------------------------------------------------------------------- --
task automatic write_unset_bsk_add;
begin
  gen_prc_axil_loop[P3_OFS].maxil_drv_if.write_trans(BSK_AVAIL_AVAIL_OFS, 0);
end
endtask

// ---------------------------------------------------------------------------------------------- --
// write_bsk_add
// ---------------------------------------------------------------------------------------------- --
task automatic write_bsk_add;
  input [BSK_PC_MAX_L-1:0][AXI4_BSK_ADD_W-1: 0] bsk_addr;
begin
  // Init bsk fields
  for (int i=0; i<BSK_PC; i=i+1) begin
    gen_cfg_axil_loop[P3_OFS].maxil_drv_if.write_trans(HBM_AXI4_ADDR_3IN3_BSK_PC0_LSB_OFS + 2*i*REG_DATA_BYTES, bsk_addr[i] & 'hffffffff);
    gen_cfg_axil_loop[P3_OFS].maxil_drv_if.write_trans(HBM_AXI4_ADDR_3IN3_BSK_PC0_MSB_OFS + 2*i*REG_DATA_BYTES, (bsk_addr[i]>> 32) & 'hffffffff);
  end
  gen_prc_axil_loop[P3_OFS].maxil_drv_if.write_trans(BSK_AVAIL_AVAIL_OFS, 1);
end
endtask

// }}}

// ---------------------------------------------------------------------------------------------- --
// write_ksk
// ---------------------------------------------------------------------------------------------- --
task automatic write_ksk;
  output [KSK_PC_MAX_L-1:0][AXI4_KSK_ADD_W-1: 0] ksk_addr;
  bit [KSK_PC_MAX_L-1:0][AXI4_KSK_ADD_W-1: 0] rand_addr;
  logic [AXI4_KSK_DATA_W-1: 0] ksk_q[$];
  logic [AXI4_KSK_DATA_W-1: 0] d;
begin

  // random addresses
  for (int i=0; i<KSK_PC_MAX_L; i=i+1) begin
    rand_addr[i] = $urandom_range(0, 1<< (AXI4_KSK_ADD_W-1)) & {{(AXI4_KSK_ADD_W-12){1'b1}}, {(12){1'b0}} };
  end

  // Write ksk in DDR
  for (int i=0; i<KSK_PC; i=i+1) begin
    // Open file associated with current batch
    string ksk_f = $sformatf("%s_%01x.hex", KSK_FILE_PREFIX, i);
    read_data #(.DATA_W(AXI4_KSK_DATA_W)) rdata_ksk    = new(.filename(ksk_f), .data_type(FILE_DATA_TYPE));
    if (!rdata_ksk.open()) begin
      $display("%t > ERROR: opening file %0s failed\n", $time, ksk_f);
      $finish;
    end

    // Read file and flush in a queue
    ksk_q.delete();
    d = rdata_ksk.get_next_data();
    while (! rdata_ksk.is_st_eof()) begin
      ksk_q.push_back(d);
      d = rdata_ksk.get_next_data();
    end

  // Write queue content in ddr
    // /!\ Workaround, since i is considered not a constant
    $display("%t > INFO: Load KSK in PC%0d from @0x%0x to @0x%0x",$time, i,  rand_addr[i], rand_addr[i] + ksk_q.size()*AXI4_KSK_DATA_BYTES);
    if (i==0)
      $readmemh(ksk_f,gen_ksk_mem_loop[0].axi4_mem_ksk.axi4_ram_ct_wr.mem, rand_addr[i] / AXI4_KSK_DATA_BYTES, rand_addr[i] / AXI4_KSK_DATA_BYTES + ksk_q.size());
    else if (i==1)
      $readmemh(ksk_f,gen_ksk_mem_loop[1].axi4_mem_ksk.axi4_ram_ct_wr.mem, rand_addr[i] / AXI4_KSK_DATA_BYTES, rand_addr[i] / AXI4_KSK_DATA_BYTES + ksk_q.size());
    else if (i==2)
      $readmemh(ksk_f,gen_ksk_mem_loop[2].axi4_mem_ksk.axi4_ram_ct_wr.mem, rand_addr[i] / AXI4_KSK_DATA_BYTES, rand_addr[i] / AXI4_KSK_DATA_BYTES + ksk_q.size());
    else if (i==3)
      $readmemh(ksk_f,gen_ksk_mem_loop[3].axi4_mem_ksk.axi4_ram_ct_wr.mem, rand_addr[i] / AXI4_KSK_DATA_BYTES, rand_addr[i] / AXI4_KSK_DATA_BYTES + ksk_q.size());
    else if (i==4)
      $readmemh(ksk_f,gen_ksk_mem_loop[4].axi4_mem_ksk.axi4_ram_ct_wr.mem, rand_addr[i] / AXI4_KSK_DATA_BYTES, rand_addr[i] / AXI4_KSK_DATA_BYTES + ksk_q.size());
    else if (i==5)
      $readmemh(ksk_f,gen_ksk_mem_loop[5].axi4_mem_ksk.axi4_ram_ct_wr.mem, rand_addr[i] / AXI4_KSK_DATA_BYTES, rand_addr[i] / AXI4_KSK_DATA_BYTES + ksk_q.size());
    else if (i==6)
      $readmemh(ksk_f,gen_ksk_mem_loop[6].axi4_mem_ksk.axi4_ram_ct_wr.mem, rand_addr[i] / AXI4_KSK_DATA_BYTES, rand_addr[i] / AXI4_KSK_DATA_BYTES + ksk_q.size());
    else if (i==7)
      $readmemh(ksk_f,gen_ksk_mem_loop[7].axi4_mem_ksk.axi4_ram_ct_wr.mem, rand_addr[i] / AXI4_KSK_DATA_BYTES, rand_addr[i] / AXI4_KSK_DATA_BYTES + ksk_q.size());
    else if (i==8)
      $readmemh(ksk_f,gen_ksk_mem_loop[8].axi4_mem_ksk.axi4_ram_ct_wr.mem, rand_addr[i] / AXI4_KSK_DATA_BYTES, rand_addr[i] / AXI4_KSK_DATA_BYTES + ksk_q.size());
    else if (i==9)
      $readmemh(ksk_f,gen_ksk_mem_loop[9].axi4_mem_ksk.axi4_ram_ct_wr.mem, rand_addr[i] / AXI4_KSK_DATA_BYTES, rand_addr[i] / AXI4_KSK_DATA_BYTES + ksk_q.size());
    else if (i==10)
      $readmemh(ksk_f,gen_ksk_mem_loop[10].axi4_mem_ksk.axi4_ram_ct_wr.mem, rand_addr[i] / AXI4_KSK_DATA_BYTES, rand_addr[i] / AXI4_KSK_DATA_BYTES + ksk_q.size());
    else if (i==11)
      $readmemh(ksk_f,gen_ksk_mem_loop[11].axi4_mem_ksk.axi4_ram_ct_wr.mem, rand_addr[i] / AXI4_KSK_DATA_BYTES, rand_addr[i] / AXI4_KSK_DATA_BYTES + ksk_q.size());
    else if (i==12)
      $readmemh(ksk_f,gen_ksk_mem_loop[12].axi4_mem_ksk.axi4_ram_ct_wr.mem, rand_addr[i] / AXI4_KSK_DATA_BYTES, rand_addr[i] / AXI4_KSK_DATA_BYTES + ksk_q.size());
    else if (i==13)
      $readmemh(ksk_f,gen_ksk_mem_loop[13].axi4_mem_ksk.axi4_ram_ct_wr.mem, rand_addr[i] / AXI4_KSK_DATA_BYTES, rand_addr[i] / AXI4_KSK_DATA_BYTES + ksk_q.size());
    else if (i==14)
      $readmemh(ksk_f,gen_ksk_mem_loop[14].axi4_mem_ksk.axi4_ram_ct_wr.mem, rand_addr[i] / AXI4_KSK_DATA_BYTES, rand_addr[i] / AXI4_KSK_DATA_BYTES + ksk_q.size());
    else if (i==15)
      $readmemh(ksk_f,gen_ksk_mem_loop[15].axi4_mem_ksk.axi4_ram_ct_wr.mem, rand_addr[i] / AXI4_KSK_DATA_BYTES, rand_addr[i] / AXI4_KSK_DATA_BYTES + ksk_q.size());
    else
      $fatal(1,"%t > ERROR: Workaround to fill ksk ram is not enough.", $time);

  end
  // output the associated addr in ddr
  ksk_addr = rand_addr;

end
endtask

// ---------------------------------------------------------------------------------------------- --
// write_unset_ksk_add
// ---------------------------------------------------------------------------------------------- --
task automatic write_unset_ksk_add;
begin
  gen_prc_axil_loop[P1_OFS].maxil_drv_if.write_trans(KSK_AVAIL_AVAIL_OFS, 0);
end
endtask

// ---------------------------------------------------------------------------------------------- --
// write_ksk_add
// ---------------------------------------------------------------------------------------------- --
task automatic write_ksk_add;
  input [KSK_PC_MAX_L-1:0][AXI4_KSK_ADD_W-1: 0] ksk_addr;
begin
  // Init ksk fields
  for (int i=0; i<KSK_PC; i=i+1) begin
    gen_cfg_axil_loop[P1_OFS].maxil_drv_if.write_trans(HBM_AXI4_ADDR_1IN3_KSK_PC0_LSB_OFS + 2*i*REG_DATA_BYTES, ksk_addr[i] & 'hffffffff);
    gen_cfg_axil_loop[P1_OFS].maxil_drv_if.write_trans(HBM_AXI4_ADDR_1IN3_KSK_PC0_MSB_OFS + 2*i*REG_DATA_BYTES, (ksk_addr[i]>> 32) & 'hffffffff);
  end
  gen_prc_axil_loop[P1_OFS].maxil_drv_if.write_trans(KSK_AVAIL_AVAIL_OFS, 1);
end
endtask


// ---------------------------------------------------------------------------------------------- --
// reset_key_caches
// ---------------------------------------------------------------------------------------------- --
task automatic reset_key_caches;
begin
  logic [REG_DATA_W-1:0] bsk_reset_rd;
  logic [REG_DATA_W-1:0] ksk_reset_rd;

  $display("%t > INFO: Reset key caches...",$time);
  // First reset KSK, then BSK
  gen_prc_axil_loop[P1_OFS].maxil_drv_if.write_trans(KSK_AVAIL_RESET_OFS, 1);
  gen_prc_axil_loop[P3_OFS].maxil_drv_if.write_trans(BSK_AVAIL_RESET_OFS, 1);

  bsk_reset_rd = 1;
  ksk_reset_rd = 1;

  write_unset_bsk_add();
  write_unset_ksk_add();

  while ((bsk_reset_rd & ksk_reset_rd) == 1) begin
    repeat(100) @(posedge clk);
    gen_prc_axil_loop[P1_OFS].maxil_drv_if.read_trans(KSK_AVAIL_RESET_OFS, ksk_reset_rd);
    gen_prc_axil_loop[P3_OFS].maxil_drv_if.read_trans(BSK_AVAIL_RESET_OFS, bsk_reset_rd);
  end

  // Unreset BSK first, then KSK
  gen_prc_axil_loop[P3_OFS].maxil_drv_if.write_trans(BSK_AVAIL_RESET_OFS, 0);
  gen_prc_axil_loop[P1_OFS].maxil_drv_if.write_trans(KSK_AVAIL_RESET_OFS, 0);
  $display("%t > INFO: Key caches reset done.",$time);
end
endtask

// ---------------------------------------------------------------------------------------------- --
// write_glwe
// ---------------------------------------------------------------------------------------------- --
task automatic write_glwe;
  output logic [GLWE_PC_MAX_L-1:0][AXI4_GLWE_ADD_W-1:0]   add; // offset address
  logic [AXI4_GLWE_DATA_W-1: 0] glwe_q[$];
  logic [AXI4_GLWE_DATA_W-1: 0] d;
begin
  // Keep Add lsb = 0 to guarantee enough slots to store all the GLWE
  for (int i=0; i<GLWE_PC_MAX_L; i=i+1) begin
    add[i] = $urandom_range(0, 1<< (AXI4_GLWE_ADD_W-1)) & {1'b0,{(AXI4_GLWE_ADD_W-13){1'b1}}, {(12){1'b0}} };
  end

  // Note : Support only GLWE_PC = 1 for now.

  // Write queue content in memory
  for (int i=0; i<GLWE_NB; i=i+1) begin
    integer                       idx;
    logic [AXI4_GLWE_ADD_W-1:0]   cur_add;
    string                        glwe_filename;
    automatic read_data #(.DATA_W(AXI4_GLWE_DATA_W)) glwe_rd;

    idx     = GLWE_LIST[i];
    cur_add = add[0] + idx * GLWE_BODY_BYTES;
    glwe_filename = $sformatf("%s_%02x.hex", GLWE_FILE_PREFIX, idx);

    // Open file associated with current iop
    //automatic read_data #(.DATA_W(AXI4_GLWE_DATA_W)) glwe_rd = new(.filename(glwe_filename), .data_type(FILE_DATA_TYPE));
    glwe_rd = new(.filename(glwe_filename), .data_type(FILE_DATA_TYPE));
    if (!glwe_rd.open()) begin
      $display("%t > ERROR: opening file %0s failed\n", $time, glwe_filename);
      $finish;
    end

    // Read file and flush in a queue
    glwe_q.delete();
    d = glwe_rd.get_next_data();
    while (! glwe_rd.is_st_eof()) begin
      glwe_q.push_back(d);
      d = glwe_rd.get_next_data();
    end

    // \gen_glwe_mem_loop[0].maxi4_glwe_if .write_trans(cur_add, glwe_q);
    $readmemh(glwe_filename,gen_glwe_mem_loop[0].axi4_mem_glwe.axi4_ram_ct_wr.mem, cur_add / AXI4_GLWE_DATA_BYTES, cur_add / AXI4_GLWE_DATA_BYTES + glwe_q.size());
    $display("%t > INFO: Write GLWE[0x%02x], at @0x%0x", $time, idx, cur_add);
  end

end
endtask

// ---------------------------------------------------------------------------------------------- --
// write_glwe_add
// ---------------------------------------------------------------------------------------------- --
task automatic write_glwe_add;
  input [GLWE_PC_MAX_L-1:0][AXI4_GLWE_ADD_W-1: 0] glwe_addr;
begin
  // Init glwe fields
  for (int j=0; j<GLWE_PC_MAX_L; j=j+1) begin
    gen_cfg_axil_loop[P1_OFS].maxil_drv_if.write_trans(HBM_AXI4_ADDR_1IN3_GLWE_PC0_LSB_OFS + 2*j*REG_DATA_BYTES, glwe_addr[j] & 'hffffffff);
    gen_cfg_axil_loop[P1_OFS].maxil_drv_if.write_trans(HBM_AXI4_ADDR_1IN3_GLWE_PC0_MSB_OFS + 2*j*REG_DATA_BYTES, (glwe_addr[j]>> 32) & 'hffffffff);
  end
end
endtask

// ---------------------------------------------------------------------------------------------- --
// read_op
// ---------------------------------------------------------------------------------------------- --
// Fill queue with DOp/IOp read from a file
task automatic read_op;
  input string op_filename;
  inout logic [AXI4_UCORE_DATA_W-1:0] op_q[$];
  logic [AXI4_UCORE_DATA_W-1:0] op;
begin
  // assert (AXI4_UCORE_DATA_W == IOP_BASE_W)
  // else $fatal(1,"%t > ERROR: To merge read_op code we made the assumption that IOP_BASE_W and AXI4_UCORE_DATA_W are equal.", $time);

  // Open file associated with current op
  automatic read_data #(.DATA_W(AXI4_UCORE_DATA_W)) op_rd = new(.filename(op_filename), .data_type(FILE_DATA_TYPE));
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

// ============================================================================================== --
// Scenario
// ============================================================================================== --
  bit [BSK_PC_MAX_L-1:0][AXI4_BSK_ADD_W-1: 0]   bsk_addr;
  bit [KSK_PC_MAX_L-1:0][AXI4_KSK_ADD_W-1: 0]   ksk_addr;
  bit [GLWE_PC_MAX_L-1:0][AXI4_GLWE_ADD_W-1: 0] glwe_addr;
  bit [PEM_PC_MAX_L-1:0][AXI4_PEM_ADD_W-1: 0]   blwe_addr;

  initial begin
    int                    work_q[$];
    logic [AXI4_UCORE_DATA_W-1:0]  iop_q[IOP_NB-1:0][$];
    logic [AXI4_UCORE_DATA_W-1:0]  dop_q[DOP_NB-1:0][$];
    int                    iop_ack;
    logic [AXI4_UCORE_DATA_W-1:0]  iop_tmp_q[$];

    $display("%t > INFO: maxil_drv_if.init",$time);
    gen_prc_axil_loop[P1_OFS].maxil_drv_if.init();
    gen_prc_axil_loop[P3_OFS].maxil_drv_if.init();
    gen_cfg_axil_loop[P1_OFS].maxil_drv_if.init();
    gen_cfg_axil_loop[P3_OFS].maxil_drv_if.init();
    $display("%t > INFO: maxi4_ucore_if.init",$time);
    maxi4_ucore_if.init();
    $display("%t > INFO: maxi4_trc_if.init",$time);
    maxi4_trc_if.init();
    $display("%t > INFO: maxi4_bsk_if.init",$time);
    for (int pc=0; pc<BSK_PC_MAX_L; pc=pc+1) begin
      case (pc)
        0: gen_bsk_mem_loop[0].maxi4_bsk_if.init();
        1: gen_bsk_mem_loop[1].maxi4_bsk_if.init();
        2: gen_bsk_mem_loop[2].maxi4_bsk_if.init();
        3: gen_bsk_mem_loop[3].maxi4_bsk_if.init();
        4: gen_bsk_mem_loop[4].maxi4_bsk_if.init();
        5: gen_bsk_mem_loop[5].maxi4_bsk_if.init();
        6: gen_bsk_mem_loop[6].maxi4_bsk_if.init();
        7: gen_bsk_mem_loop[7].maxi4_bsk_if.init();
        8: gen_bsk_mem_loop[8].maxi4_bsk_if.init();
        9: gen_bsk_mem_loop[9].maxi4_bsk_if.init();
        10: gen_bsk_mem_loop[10].maxi4_bsk_if.init();
        11: gen_bsk_mem_loop[11].maxi4_bsk_if.init();
        12: gen_bsk_mem_loop[12].maxi4_bsk_if.init();
        13: gen_bsk_mem_loop[13].maxi4_bsk_if.init();
        14: gen_bsk_mem_loop[14].maxi4_bsk_if.init();
        15: gen_bsk_mem_loop[15].maxi4_bsk_if.init();
        default: $display("%t > WARNING: init of maxi4_bsk_if for pc %0d could not be done", $time, pc);
      endcase
    end
    $display("%t > INFO: maxi4_ksk_if.init",$time);
    for (int pc=0; pc<KSK_PC_MAX_L; pc=pc+1) begin
      case (pc)
        0: gen_ksk_mem_loop[0].maxi4_ksk_if.init();
        1: gen_ksk_mem_loop[1].maxi4_ksk_if.init();
        2: gen_ksk_mem_loop[2].maxi4_ksk_if.init();
        3: gen_ksk_mem_loop[3].maxi4_ksk_if.init();
        4: gen_ksk_mem_loop[4].maxi4_ksk_if.init();
        5: gen_ksk_mem_loop[5].maxi4_ksk_if.init();
        6: gen_ksk_mem_loop[6].maxi4_ksk_if.init();
        7: gen_ksk_mem_loop[7].maxi4_ksk_if.init();
        8: gen_ksk_mem_loop[8].maxi4_ksk_if.init();
        9: gen_ksk_mem_loop[9].maxi4_ksk_if.init();
        10: gen_ksk_mem_loop[10].maxi4_ksk_if.init();
        11: gen_ksk_mem_loop[11].maxi4_ksk_if.init();
        12: gen_ksk_mem_loop[12].maxi4_ksk_if.init();
        13: gen_ksk_mem_loop[13].maxi4_ksk_if.init();
        14: gen_ksk_mem_loop[14].maxi4_ksk_if.init();
        15: gen_ksk_mem_loop[15].maxi4_ksk_if.init();
        default: $display("%t > WARNING: init of maxi4_ksk_if for pc %0d could not be done", $time, pc);
      endcase
    end
    $display("%t > INFO: maxi4_pem_if.init",$time);
    for (int pc=0; pc<PEM_PC_MAX_L; pc=pc+1) begin
      case (pc)
        0: gen_ct_mem_loop[0].maxi4_pem_if.init();
        1: gen_ct_mem_loop[1].maxi4_pem_if.init();
        default: $display("%t > WARNING: init of maxi4_pem_if for pc %0d could not be done", $time, pc);
      endcase
    end
    $display("%t > INFO: maxi4_glwe_if.init",$time);
    for (int pc=0; pc<GLWE_PC_MAX_L; pc=pc+1) begin
      case (pc)
        0: gen_glwe_mem_loop[0].maxi4_glwe_if.init();
        default: $display("%t > WARNING: init of maxi4_glwe_if for pc %0d could not be done", $time, pc);
      endcase
    end
    $display("%t > INFO: Init done",$time);
    axi4_pem_select = TB_DRIVE_HBM;
    axi4_ucore_select = TB_DRIVE_HBM;

    //===============================
    // Wait reset
    //===============================
    // Configure
    while (!s_rst_n) @(posedge clk);
    while (!cfg_srst_n) @(posedge cfg_clk);
    repeat(10) @(posedge clk);

    //===============================
    // Soft Reset
    //===============================
    soft_reset();

    //===============================
    // Check dummy registers
    //===============================
    check_dummy_reg();

    //===============================
    // Check ucore version
    //===============================
    // push IOP to read UCORE Version
    // works only with ublaze in simulation
    iop_tmp_q.push_back(UCORE_VERSION_IOP);
    iop_tmp_q.push_back(EMPTY_DST_IOP);
    iop_tmp_q.push_back(EMPTY_SRC_IOP);
    push_work(iop_tmp_q, work_q);
    $display("%t > INFO: Pushed IOp to read ucore version", $time);
    repeat(100) @(posedge clk);
    pop_ack(work_q, iop_ack);

    //===============================
    // Init phase
    //===============================
    // Configure
    configure_hpu();

    //===============================
    // Init load phase
    //===============================
    // Upload bsk and init bsk registers
    // Upload ksk and init ksk registers
    write_unset_bsk_add();
    write_unset_ksk_add();
    fork
      begin
        $display("%t > INFO: Load BSK...", $time);
        write_bsk(bsk_addr);
        $display("%t > INFO: Load BSK...Done", $time);
        for (int b=0; b<BSK_PC; b=b+1)
          $display("%t > INFO: BSK @[PC%0d] = 0x%08x", $time,b,bsk_addr[b]);
      end
      begin
        $display("%t > INFO: Load KSK...", $time);
        write_ksk(ksk_addr);
        $display("%t > INFO: Load KSK...Done", $time);
        for (int k=0; k<KSK_PC; k=k+1)
          $display("%t > INFO: KSK @[PC%0d] = 0x%08x", $time,k,ksk_addr[k]);
      end
      begin
        $display("%t > INFO: Load GLWE body polynomial...", $time);
        write_glwe(glwe_addr);
        $display("%t > INFO: Load GLWE body polynomial...Done", $time);
        for (int k=0; k<GLWE_PC; k=k+1)
          $display("%t > INFO: GLWE @[PC%0d] address offset = 0x%08x", $time,k,glwe_addr[k]);
      end
    join

    repeat(10) @(posedge clk); // end preload mode. Avoid access conflict

    // Tb take control of the hbm pem and preload some ciphertext
    axi4_pem_select = TB_DRIVE_HBM;

    write_ksk_add(ksk_addr);
    write_bsk_add(bsk_addr);
    write_glwe_add(glwe_addr);

    //===============================
    // Simu iteration
    //===============================
    for (int iter=0; iter < SIMU_ITERATION_NB; iter=iter+1) begin
      // Read Iop in a queue
      for (int i=0; i<IOP_NB; i=i+1) begin
        iop_q[i].delete();
      end
      for (int i=0; i<DOP_NB; i=i+1) begin
        dop_q[i].delete();
      end

      for (int i=0; i<IOP_NB; i=i+1) begin
        string fn;
        fn =  $sformatf("%s_%0d.hex", IOP_FILE_PREFIX, i);
        read_op(fn, iop_q[i]);
      end

      // Load Dops in queues
      for (int i=0; i<DOP_NB; i=i+1) begin
        string fn;
        fn =  $sformatf("%s_%02x.hex", DOP_FILE_PREFIX, DOP_LIST[i]);
        read_op(fn, dop_q[i]);
      end

      fork
        begin
          // Preload translation table
          $display("%t > INFO: Load IOP to DOP tables...", $time);
          init_iop2dop_table(dop_q);
          $display("%t > INFO: Load IOP to DOP tables...Done", $time);
        end
        begin
          $display("%t > INFO: Load BLWE...", $time);
          write_blwe(blwe_addr);
          $display("%t > INFO: Load BLWE...Done", $time);
          for (int c=0; c<PEM_PC_MAX_L; c=c+1)
            $display("%t > INFO: BLWE @[PC%0d] = 0x%08x", $time,c,blwe_addr[c]);
        end
      join

      repeat(10) @(posedge clk); // end preload mode. Avoid access conflict

      // Tb take control of the hbm pem and preload some ciphertext
      axi4_pem_select = TB_DRIVE_HBM;

      write_blwe_add(blwe_addr);
      write_ksk_add(ksk_addr); // avail the key
      write_bsk_add(bsk_addr); // "


      //===============================
      // Run phase
      //===============================
      $display("%t > INFO: Start Run phase",$time);

      // Tb release control of the HBM and issue IOps command to the dut
      // Then it waits for completion of the command batch
      axi4_pem_select = DUT_DRIVE_HBM;
      axi4_ucore_select = DUT_DRIVE_HBM;

      // Iterate over IOp
      // NB: Push 1 IOP at a time.
      for (int i=0; i<IOP_NB; i=i+1) begin
        push_work(iop_q[i], work_q);

        if (i >= TEST_PS) begin
          pop_ack(work_q, iop_ack);
          $display("%t > INFO: Received ack for Iop %x", $time, iop_ack);
        end
      end

      for (int i=0; i< TEST_PS; i++) begin
          pop_ack(work_q, iop_ack);
          $display("%t > INFO: Received ack for Iop %x", $time, iop_ack);
      end

      //===============================
      // Check phase
      //===============================
      axi4_pem_select = TB_DRIVE_HBM;
      // Tb takes control of the HBM and unloads results ciphertext
      // Then it compares received Ct against expected one
      for (int ct_idx=0; ct_idx<OUT_BLWE_NB; ct_idx=ct_idx+1) begin
        $display("%t > INFO: Read output BLWE #%0d...", $time, ct_idx);
        read_and_check_blwe(ct_idx, DO_CHECK, blwe_addr);
        if (DO_CHECK)
          $display("%t > INFO: Read output BLWE #%0d and checked", $time, ct_idx);
        else
          $display("%t > INFO: Read output BLWE #%0d ... done", $time, ct_idx);
      end

      //===============================
      // Reset
      //===============================
      reset_key_caches();

    end // for iter

    //===============================
    // Drain simulation
    //===============================
    repeat(200) @(posedge clk);
    end_of_test = 1'b1;
  end // initial

endmodule
