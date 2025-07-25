// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Axi4-lite register bank
// ----------------------------------------------------------------------------------------------
// For cfg_clk part 3in3
// ==============================================================================================

module hpu_regif_cfg_3in3
  import axi_if_common_param_pkg::*;
  import axi_if_shell_axil_pkg::*;
  import axi_if_bsk_axi_pkg::*;
  import top_common_param_pkg::*;
  import hpu_regif_core_cfg_3in3_pkg::*;
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

  output logic [BSK_PC_MAX-1:0][axi_if_bsk_axi_pkg::AXI4_ADD_W-1:0] bsk_mem_addr,

  // Reset three way handshake
  output logic                           hpu_reset,
  input  logic                           hpu_reset_done
);

// ============================================================================================== --
// localparam
// ============================================================================================== --
  // Current design supports BSK_PC_MAX up to 16.
  localparam int BSK_PC_MAX_L        = 16;
  localparam int REQ_ACK_NB          = 1; // hpu_reset
  localparam int REQ_ACK_HPU_RST_OFS = 0;

  generate
    if (BSK_PC_MAX > BSK_PC_MAX_L) begin : __UNSUPPORTED_BSK_PC_MAX
      $fatal(1, "> ERROR Unsupported BSK_PC_MAX (%0d). Should be less or equal to %0d.", BSK_PC_MAX, BSK_PC_MAX_L);
    end
  endgenerate

// ============================================================================================== --
// signals
// ============================================================================================== --
  logic [BSK_PC_MAX_L-1:0][2*REG_DATA_W-1:0]         r_bsk_mem_addr;
  logic [REQ_ACK_NB-1:0][REG_DATA_W-1:0]             r_req_ack_upd;
  logic [REQ_ACK_NB-1:0]                             r_req_ack_wr_en;
  logic [REQ_ACK_NB-1:0]                             r_req_ack_rd_en;
  logic [REG_DATA_W-1:0]                             r_wr_data;
  logic [REQ_ACK_NB-1:0]                             req_cmd;
  logic [REQ_ACK_NB-1:0]                             ack_rsp;

// Reset interface
  assign hpu_reset = req_cmd[REQ_ACK_HPU_RST_OFS];
  assign ack_rsp[REQ_ACK_HPU_RST_OFS] = hpu_reset_done;
  hpu_regif_req_ack_rd
  #(
     .IN_NB       (REQ_ACK_NB),
     .REG_DATA_W  (REG_DATA_W)
  ) hpu_regif_req_ack_rd (
    .clk             (cfg_clk),
    .s_rst_n         (cfg_srst_n),

    .r_req_ack_upd   (r_req_ack_upd),
    .r_req_ack_wr_en (r_req_ack_wr_en),
    .r_req_ack_rd_en (r_req_ack_rd_en),
    .r_wr_data       (r_wr_data),

    .req_cmd         (req_cmd),
    .ack_rsp         (ack_rsp)
  );

// ============================================================================================== --
// hpu_regif_core
// ============================================================================================== --
  // Extract fields
  always_comb
    for (int i=0; i<BSK_PC_MAX; i=i+1)
      bsk_mem_addr[i] = r_bsk_mem_addr[i][axi_if_bsk_axi_pkg::AXI4_ADD_W-1:0];

  hpu_regif_core_cfg_3in3
  hpu_regif_core_cfg_3in3 (
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

      .r_axil_wdata              (r_wr_data),

      // Registers IO
      .r_hbm_axi4_addr_3in3_bsk_pc0_lsb   (r_bsk_mem_addr[0][0*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_3in3_bsk_pc0_msb   (r_bsk_mem_addr[0][1*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_3in3_bsk_pc1_lsb   (r_bsk_mem_addr[1][0*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_3in3_bsk_pc1_msb   (r_bsk_mem_addr[1][1*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_3in3_bsk_pc2_lsb   (r_bsk_mem_addr[2][0*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_3in3_bsk_pc2_msb   (r_bsk_mem_addr[2][1*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_3in3_bsk_pc3_lsb   (r_bsk_mem_addr[3][0*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_3in3_bsk_pc3_msb   (r_bsk_mem_addr[3][1*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_3in3_bsk_pc4_lsb   (r_bsk_mem_addr[4][0*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_3in3_bsk_pc4_msb   (r_bsk_mem_addr[4][1*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_3in3_bsk_pc5_lsb   (r_bsk_mem_addr[5][0*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_3in3_bsk_pc5_msb   (r_bsk_mem_addr[5][1*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_3in3_bsk_pc6_lsb   (r_bsk_mem_addr[6][0*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_3in3_bsk_pc6_msb   (r_bsk_mem_addr[6][1*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_3in3_bsk_pc7_lsb   (r_bsk_mem_addr[7][0*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_3in3_bsk_pc7_msb   (r_bsk_mem_addr[7][1*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_3in3_bsk_pc8_lsb   (r_bsk_mem_addr[8][0*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_3in3_bsk_pc8_msb   (r_bsk_mem_addr[8][1*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_3in3_bsk_pc9_lsb   (r_bsk_mem_addr[9][0*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_3in3_bsk_pc9_msb   (r_bsk_mem_addr[9][1*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_3in3_bsk_pc10_lsb  (r_bsk_mem_addr[10][0*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_3in3_bsk_pc10_msb  (r_bsk_mem_addr[10][1*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_3in3_bsk_pc11_lsb  (r_bsk_mem_addr[11][0*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_3in3_bsk_pc11_msb  (r_bsk_mem_addr[11][1*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_3in3_bsk_pc12_lsb  (r_bsk_mem_addr[12][0*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_3in3_bsk_pc12_msb  (r_bsk_mem_addr[12][1*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_3in3_bsk_pc13_lsb  (r_bsk_mem_addr[13][0*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_3in3_bsk_pc13_msb  (r_bsk_mem_addr[13][1*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_3in3_bsk_pc14_lsb  (r_bsk_mem_addr[14][0*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_3in3_bsk_pc14_msb  (r_bsk_mem_addr[14][1*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_3in3_bsk_pc15_lsb  (r_bsk_mem_addr[15][0*REG_DATA_W+:REG_DATA_W]),
      .r_hbm_axi4_addr_3in3_bsk_pc15_msb  (r_bsk_mem_addr[15][1*REG_DATA_W+:REG_DATA_W]),
      .r_hpu_reset_trigger_upd            (r_req_ack_upd[REQ_ACK_HPU_RST_OFS]),
      .r_hpu_reset_trigger_wr_en          (r_req_ack_wr_en[REQ_ACK_HPU_RST_OFS]),
      .r_hpu_reset_trigger_rd_en          (r_req_ack_rd_en[REQ_ACK_HPU_RST_OFS]),
      .r_hpu_reset_trigger                (/*UNUSED*/)
  );

endmodule
