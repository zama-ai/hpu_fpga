// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Axi4-lite register bank
// ----------------------------------------------------------------------------------------------
// For cfg_clk part 1in3
// ==============================================================================================

module hpu_regif_cfg_1in3
  import axi_if_common_param_pkg::*;
  import axi_if_shell_axil_pkg::*;
  import axi_if_ct_axi_pkg::*;
  import axi_if_bsk_axi_pkg::*;
  import axi_if_ksk_axi_pkg::*;
  import axi_if_glwe_axi_pkg::*;
  import axi_if_trc_axi_pkg::*;
  import top_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import hpu_regif_core_cfg_1in3_pkg::*;
  import hpu_common_param_pkg::*;
  // For param exposition
  import param_tfhe_pkg::*;
  import param_ntt_pkg::*;
  import pep_ks_common_param_pkg::*;
  import bsk_mgr_common_param_pkg::*;
  import ksk_mgr_common_param_pkg::*;
  import ntt_core_common_param_pkg::*;
  import regf_common_param_pkg::*;
  import instruction_scheduler_pkg::*;
#(
  parameter int VERSION_MAJOR      = 2,
  parameter int VERSION_MINOR      = 0
)
(
  input  logic                           cfg_clk,
  input  logic                           cfg_srst_n,
  // Axi4 lite Slave Interface sAxi4
  input  logic [AXIL_ADD_W-1:0]          s_axil_awaddr,
  input  logic                           s_axil_awvalid,
  output logic                           s_axil_awready,
  input  logic [AXIL_DATA_W-1:0]         s_axil_wdata,
  input  logic                           s_axil_wvalid,
  output logic                           s_axil_wready,
  output logic [1:0]                     s_axil_bresp,
  output logic                           s_axil_bvalid,
  input  logic                           s_axil_bready,
  input  logic [AXIL_ADD_W-1:0]          s_axil_araddr,
  input  logic                           s_axil_arvalid,
  output logic                           s_axil_arready,
  output logic [AXIL_DATA_W-1:0]         s_axil_rdata,
  output logic [1:0]                     s_axil_rresp,
  output logic                           s_axil_rvalid,
  input  logic                           s_axil_rready,

  output logic [PEM_PC_MAX-1:0][axi_if_ct_axi_pkg::AXI4_ADD_W-1:0]    ct_mem_addr,
  output logic [GLWE_PC_MAX-1:0][axi_if_glwe_axi_pkg::AXI4_ADD_W-1:0] glwe_mem_addr,
  output logic [KSK_PC_MAX-1:0][axi_if_ksk_axi_pkg::AXI4_ADD_W-1:0]   ksk_mem_addr,
  output logic [axi_if_trc_axi_pkg::AXI4_ADD_W-1:0]                   trc_mem_addr,
  output logic                                                        use_bpip,
  output logic                                                        use_bpip_opportunism,
  output logic [TIMEOUT_CNT_W-1: 0]                                   bpip_timeout
);
// ============================================================================================== --
// localparam
// ============================================================================================== --
  // Current design supports KSK_PC_MAX up to 16.
  localparam int KSK_PC_MAX_L    = 16;
  localparam int PEM_PC_MAX_L    = 2;
  localparam int GLWE_PC_MAX_L   = 1;

  generate
    if (KSK_PC_MAX > KSK_PC_MAX_L) begin : __UNSUPPORTED_KSK_PC_MAX
      $fatal(1, "> ERROR Unsupported KSK_PC_MAX (%0d). Should be less or equal to %0d.", KSK_PC_MAX, KSK_PC_MAX_L);
    end
    if (PEM_PC_MAX > PEM_PC_MAX_L) begin : __UNSUPPORTED_PEM_PC_MAX
      $fatal(1, "> ERROR Unsupported PEM_PC_MAX (%0d). Should be less or equal to %0d.", PEM_PC_MAX, PEM_PC_MAX_L);
    end
    if (GLWE_PC_MAX > GLWE_PC_MAX_L) begin : __UNSUPPORTED_GLWE_PC_MAX
      $fatal(1, "> ERROR Unsupported GLWE_PC_MAX (%0d). Should be less or equal to %0d.", GLWE_PC_MAX, GLWE_PC_MAX_L);
    end
  endgenerate

// ============================================================================================== --
// signals
// ============================================================================================== --
  logic [PEM_PC_MAX_L-1:0][2*REG_DATA_W-1:0]         r_ct_mem_addr;
  logic [KSK_PC_MAX_L-1:0][2*REG_DATA_W-1:0]         r_ksk_mem_addr;
  logic [GLWE_PC_MAX_L-1:0][2*REG_DATA_W-1:0]        r_glwe_mem_addr;
  logic [2*REG_DATA_W-1:0]                           r_trc_mem_addr;

  logic [REG_DATA_W-1:0]                             r_bpip_timeout;
  bpip_use_t                                         r_bpip_use;

// ============================================================================================== --
// hpu_regif_core
// ============================================================================================== --
  // Extract fields
  assign use_bpip             = r_bpip_use.use_bpip;
  assign use_bpip_opportunism = r_bpip_use.use_opportunism;
  assign bpip_timeout         = r_bpip_timeout[TIMEOUT_CNT_W-1:0];

  always_comb
    for (int j=0; j<PEM_PC_MAX; j=j+1)
      ct_mem_addr[j] = r_ct_mem_addr[j][axi_if_ct_axi_pkg::AXI4_ADD_W-1:0];

  always_comb
    for (int i=0; i<KSK_PC_MAX; i=i+1)
      ksk_mem_addr[i] = r_ksk_mem_addr[i][axi_if_ksk_axi_pkg::AXI4_ADD_W-1:0];

  always_comb
    for (int i=0; i<GLWE_PC_MAX; i=i+1)
      glwe_mem_addr[i]  = r_glwe_mem_addr[i][axi_if_glwe_axi_pkg::AXI4_ADD_W-1:0];

  assign trc_mem_addr = r_trc_mem_addr[axi_if_trc_axi_pkg::AXI4_ADD_W-1:0];

  hpu_regif_core_cfg_1in3
  #(
    .VERSION_MAJOR (VERSION_MAJOR),
    .VERSION_MINOR (VERSION_MINOR),
    .R             (R),
    .PSI           (PSI),
    .BWD_PSI_DIV   (BWD_PSI_DIV),
    .DELTA         (DELTA),
    .NTT_RDX_CUT_S_0 (NTT_RDX_CUT_S[0]),
    .NTT_RDX_CUT_S_1 ((NTT_RDX_CUT_NB > 1) ? (NTT_RDX_CUT_S >> 1*32) & 'hFFFFFFFF : '0),
    .NTT_RDX_CUT_S_2 ((NTT_RDX_CUT_NB > 2) ? (NTT_RDX_CUT_S >> 2*32) & 'hFFFFFFFF : '0),
    .NTT_RDX_CUT_S_3 ((NTT_RDX_CUT_NB > 3) ? (NTT_RDX_CUT_S >> 3*32) & 'hFFFFFFFF : '0),
    .NTT_RDX_CUT_S_4 ((NTT_RDX_CUT_NB > 4) ? (NTT_RDX_CUT_S >> 4*32) & 'hFFFFFFFF : '0),
    .NTT_RDX_CUT_S_5 ((NTT_RDX_CUT_NB > 5) ? (NTT_RDX_CUT_S >> 5*32) & 'hFFFFFFFF : '0),
    .NTT_RDX_CUT_S_6 ((NTT_RDX_CUT_NB > 6) ? (NTT_RDX_CUT_S >> 6*32) & 'hFFFFFFFF : '0),
    .NTT_RDX_CUT_S_7 ((NTT_RDX_CUT_NB > 7) ? (NTT_RDX_CUT_S >> 7*32) & 'hFFFFFFFF : '0),
    .NTT_CORE_ARCH (NTT_CORE_ARCH),
    .BATCH_PBS_NB  (BATCH_PBS_NB),
    .TOTAL_PBS_NB  (TOTAL_PBS_NB),
    .MOD_NTT_NAME  (MOD_NTT_NAME),
    .APPLICATION_NAME (APPLICATION_NAME),
    .LBX           (LBX),
    .LBY           (LBY),
    .LBZ           (LBZ),
    .MOD_KSK_W     (MOD_KSK_W),
    .KS_L          (KS_L),
    .KS_B_W        (KS_B_W),
    .REGF_REG_NB   (REGF_REG_NB),
    .REGF_COEF_NB  (REGF_COEF_NB),
    .ISC_DEPTH     (POOL_SLOT_NB),
    .MIN_IOP_SIZE  (MIN_IOP_SIZE),
    .PEA_REGF_PERIOD(PEA_REGF_PERIOD),
    .PEM_REGF_PERIOD(PEM_REGF_PERIOD),
    .PEP_REGF_PERIOD(PEP_REGF_PERIOD),
    .PEA_ALU_NB    (PEA_ALU_NB),
    .BSK_PC        (BSK_PC),
    .BSK_CUT_NB    (BSK_CUT_NB),
    .KSK_PC        (KSK_PC),
    .KSK_CUT_NB    (KSK_CUT_NB),
    .PEM_PC        (PEM_PC),
    .AXI4_PEM_DATA_W (axi_if_ct_axi_pkg::AXI4_DATA_W),
    .AXI4_GLWE_DATA_W(axi_if_glwe_axi_pkg::AXI4_DATA_W),
    .AXI4_BSK_DATA_W (axi_if_bsk_axi_pkg::AXI4_DATA_W),
    .AXI4_KSK_DATA_W (axi_if_ksk_axi_pkg::AXI4_DATA_W)
    ) hpu_regif_core_cfg_1in3 (
      .clk                       (cfg_clk),
      .s_rst_n                   (cfg_srst_n),

      // Axi lite interface
      .s_axil_awaddr             (s_axil_awaddr),
      .s_axil_awvalid            (s_axil_awvalid),
      .s_axil_awready            (s_axil_awready),
      .s_axil_wdata              (s_axil_wdata),
      .s_axil_wvalid             (s_axil_wvalid),
      .s_axil_wready             (s_axil_wready),
      .s_axil_bresp              (s_axil_bresp),
      .s_axil_bvalid             (s_axil_bvalid),
      .s_axil_bready             (s_axil_bready),
      .s_axil_araddr             (s_axil_araddr),
      .s_axil_arvalid            (s_axil_arvalid),
      .s_axil_arready            (s_axil_arready),
      .s_axil_rdata              (s_axil_rdata),
      .s_axil_rresp              (s_axil_rresp),
      .s_axil_rvalid             (s_axil_rvalid),
      .s_axil_rready             (s_axil_rready),

      // Registered version of wdata
      .r_axil_wdata              (/*UNUSED*/),

      // Registers IO
      .r_hbm_axi4_addr_1in3_ct_pc0_lsb    (r_ct_mem_addr[0][0*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_1in3_ct_pc0_msb    (r_ct_mem_addr[0][1*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_1in3_ct_pc1_lsb    (r_ct_mem_addr[1][0*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_1in3_ct_pc1_msb    (r_ct_mem_addr[1][1*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_1in3_glwe_pc0_lsb  (r_glwe_mem_addr[0][0*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_1in3_glwe_pc0_msb  (r_glwe_mem_addr[0][1*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_1in3_ksk_pc0_lsb   (r_ksk_mem_addr[0][0*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_1in3_ksk_pc0_msb   (r_ksk_mem_addr[0][1*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_1in3_ksk_pc1_lsb   (r_ksk_mem_addr[1][0*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_1in3_ksk_pc1_msb   (r_ksk_mem_addr[1][1*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_1in3_ksk_pc2_lsb   (r_ksk_mem_addr[2][0*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_1in3_ksk_pc2_msb   (r_ksk_mem_addr[2][1*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_1in3_ksk_pc3_lsb   (r_ksk_mem_addr[3][0*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_1in3_ksk_pc3_msb   (r_ksk_mem_addr[3][1*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_1in3_ksk_pc4_lsb   (r_ksk_mem_addr[4][0*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_1in3_ksk_pc4_msb   (r_ksk_mem_addr[4][1*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_1in3_ksk_pc5_lsb   (r_ksk_mem_addr[5][0*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_1in3_ksk_pc5_msb   (r_ksk_mem_addr[5][1*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_1in3_ksk_pc6_lsb   (r_ksk_mem_addr[6][0*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_1in3_ksk_pc6_msb   (r_ksk_mem_addr[6][1*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_1in3_ksk_pc7_lsb   (r_ksk_mem_addr[7][0*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_1in3_ksk_pc7_msb   (r_ksk_mem_addr[7][1*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_1in3_ksk_pc8_lsb   (r_ksk_mem_addr[8][0*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_1in3_ksk_pc8_msb   (r_ksk_mem_addr[8][1*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_1in3_ksk_pc9_lsb   (r_ksk_mem_addr[9][0*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_1in3_ksk_pc9_msb   (r_ksk_mem_addr[9][1*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_1in3_ksk_pc10_lsb  (r_ksk_mem_addr[10][0*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_1in3_ksk_pc10_msb  (r_ksk_mem_addr[10][1*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_1in3_ksk_pc11_lsb  (r_ksk_mem_addr[11][0*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_1in3_ksk_pc11_msb  (r_ksk_mem_addr[11][1*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_1in3_ksk_pc12_lsb  (r_ksk_mem_addr[12][0*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_1in3_ksk_pc12_msb  (r_ksk_mem_addr[12][1*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_1in3_ksk_pc13_lsb  (r_ksk_mem_addr[13][0*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_1in3_ksk_pc13_msb  (r_ksk_mem_addr[13][1*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_1in3_ksk_pc14_lsb  (r_ksk_mem_addr[14][0*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_1in3_ksk_pc14_msb  (r_ksk_mem_addr[14][1*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_1in3_ksk_pc15_lsb  (r_ksk_mem_addr[15][0*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_1in3_ksk_pc15_msb  (r_ksk_mem_addr[15][1*REG_DATA_W+:REG_DATA_W]),
      .r_bpip_use                         (r_bpip_use),
      .r_bpip_timeout                     (r_bpip_timeout),
      .r_hbm_axi4_addr_1in3_trc_pc0_lsb   (r_trc_mem_addr[0*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_1in3_trc_pc0_msb   (r_trc_mem_addr[1*REG_DATA_W+:REG_DATA_W])
  );

endmodule
