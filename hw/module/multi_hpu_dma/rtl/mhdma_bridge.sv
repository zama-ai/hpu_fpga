// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Ethernet bridge to PL and HBM
// ----------------------------------------------------------------------------------------------
//
// ==============================================================================================

module mhdma_bridge
import mhdma_pkg::*;
  import axi_if_shell_axil_pkg::*;
  import hpu_regif_core_eth_2in3_pkg::*;
  import axi_if_common_param_pkg::*;
#(
  parameter int FIFO_DEPTH    = 512,
  parameter int NB_WORD_W     = $clog2(FIFO_DEPTH)+1,

  parameter int ETH_PC        = 2,
  parameter int MAC_ADDR_W    = 24
) (
  // Ethernet configuration interface -----------------------------------------
  input  logic clk_cfg,
  input  logic resetn_cfg,
  // Ethernet fast clock interface --------------------------------------------
  input  logic clk_mrmac,
  input  logic resetn_mrmac,
  // Axi4 interface for NMU ---------------------------------------------------
  // Read channel
  output logic [ETH_PC-1:0][   AXI4_ID_W-1:0]    m_axi4_arid,
  output logic [ETH_PC-1:0][  AXI4_ADD_W-1:0]    m_axi4_araddr,
  output logic [ETH_PC-1:0][  AXI4_LEN_W-1:0]    m_axi4_arlen,
  output logic [ETH_PC-1:0][ AXI4_SIZE_W-1:0]    m_axi4_arsize,
  output logic [ETH_PC-1:0][AXI4_BURST_W-1:0]    m_axi4_arburst,
  output logic [ETH_PC-1:0]                      m_axi4_arvalid,
  input  logic [ETH_PC-1:0]                      m_axi4_arready,
  input  logic [ETH_PC-1:0][  AXI4_ID_W-1:0]     m_axi4_rid,
  input  logic [ETH_PC-1:0][AXI4_DATA_W-1:0]     m_axi4_rdata,
  input  logic [ETH_PC-1:0][AXI4_RESP_W-1:0]     m_axi4_rresp,
  input  logic [ETH_PC-1:0]                      m_axi4_rlast,
  input  logic [ETH_PC-1:0]                      m_axi4_rvalid,
  output logic [ETH_PC-1:0]                      m_axi4_rready,
  // Write channel
  output logic [ETH_PC-1:0][   AXI4_ID_W-1:0]    m_axi4_awid,
  output logic [ETH_PC-1:0][  AXI4_ADD_W-1:0]    m_axi4_awaddr,
  output logic [ETH_PC-1:0][  AXI4_LEN_W-1:0]    m_axi4_awlen,
  output logic [ETH_PC-1:0][ AXI4_SIZE_W-1:0]    m_axi4_awsize,
  output logic [ETH_PC-1:0][AXI4_BURST_W-1:0]    m_axi4_awburst,
  output logic [ETH_PC-1:0]                      m_axi4_awvalid,
  input  logic [ETH_PC-1:0]                      m_axi4_awready,
  output logic [ETH_PC-1:0][AXI4_DATA_W-1:0]     m_axi4_wdata,
  output logic [ETH_PC-1:0][AXI4_STRB_W-1:0]     m_axi4_wstrb,
  output logic [ETH_PC-1:0]                      m_axi4_wlast,
  output logic [ETH_PC-1:0]                      m_axi4_wvalid,
  input  logic [ETH_PC-1:0]                      m_axi4_wready,
  input  logic [ETH_PC-1:0][  AXI4_ID_W-1:0]     m_axi4_bid,
  input  logic [ETH_PC-1:0][AXI4_RESP_W-1:0]     m_axi4_bresp,
  input  logic [ETH_PC-1:0]                      m_axi4_bvalid,
  output logic [ETH_PC-1:0]                      m_axi4_bready,
  // regf interface -----------------------------------------------------------
  input  logic [   QSFP_LANE_NB-1:0] regf_lane,
  input  logic [MAC_ADDR_W-1:0] regf_src_mac_addr,
  input  logic [MAC_ADDR_W-1:0] regf_dst_mac_addr,
  input  logic                  regf_tx_notify,
  output logic                  regf_rx_notify,
  // QSFP system interface ----------------------------------------------------
  // == TX
  output[QSFP_LANE_NB-1:0][MRMAC_AXIS_W-1:0] qsfp_tx_tdata,
  output[QSFP_LANE_NB-1:0][MRMAC_TKEEP_W-1:0] qsfp_tx_tkeep_user,
  output[QSFP_LANE_NB-1:0]                   qsfp_tx_tlast,
  output[QSFP_LANE_NB-1:0]                   qsfp_tx_tvalid,
  input [QSFP_LANE_NB-1:0]                   qsfp_tx_tready,
  // == RX
  input [QSFP_LANE_NB-1:0][MRMAC_AXIS_W-1:0] qsfp_rx_tdata,
  input [QSFP_LANE_NB-1:0][MRMAC_TKEEP_W-1:0] qsfp_rx_tkeep_user,
  input [QSFP_LANE_NB-1:0]                   qsfp_rx_tlast,
  input [QSFP_LANE_NB-1:0]                   qsfp_rx_tvalid
);

  // =========================================================================================== //
  // localparam
  // =========================================================================================== //
  localparam int CDC_SYNC_STAGES = 2;

  // =========================================================================================== //
  // CDC from regf to mrmac clock
  // =========================================================================================== //
  // theses signals are quasi static: they should move rarely
  logic [CDC_SYNC_STAGES-1:0] [   QSFP_LANE_NB-1:0] lane;
  logic [CDC_SYNC_STAGES-1:0] [MAC_ADDR_W-1:0] src_mac_addr;
  logic [CDC_SYNC_STAGES-1:0] [MAC_ADDR_W-1:0] dst_mac_addr;
  logic [CDC_SYNC_STAGES-1:0]                  tx_notify;
  logic [CDC_SYNC_STAGES-1:0]                  rx_notify;


  always_ff @(posedge clk_mrmac) begin
    lane[0]         <= regf_lane;
    src_mac_addr[0] <= regf_src_mac_addr;
    dst_mac_addr[0] <= regf_dst_mac_addr;
    tx_notify[0]    <= regf_tx_notify;
    rx_notify[0]    <= regf_rx_notify;
  end

  generate
    for (genvar gen_i_cdc = 1; gen_i_cdc < CDC_SYNC_STAGES ; gen_i_cdc = gen_i_cdc + 1) begin
      always_ff @(posedge clk_mrmac) begin
        lane[gen_i_cdc]         <= lane[gen_i_cdc-1];
        src_mac_addr[gen_i_cdc] <= src_mac_addr[gen_i_cdc-1];
        dst_mac_addr[gen_i_cdc] <= dst_mac_addr[gen_i_cdc-1];
        tx_notify[gen_i_cdc]    <= tx_notify[gen_i_cdc-1];
        rx_notify[gen_i_cdc]    <= rx_notify[gen_i_cdc-1];
      end
    end
  endgenerate


  // =========================================================================================== //
  // packet decoder
  // =========================================================================================== //
  // On RX lanes, should know as soon as possible what type of packets I should see

  // =========================================================================================== //
  // TX Notify
  // =========================================================================================== //

  // =========================================================================================== //
  // RX Notify
  // =========================================================================================== //



endmodule
