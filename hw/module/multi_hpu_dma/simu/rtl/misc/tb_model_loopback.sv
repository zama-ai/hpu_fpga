// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : small model to mimic qsfp lines in simulation.
// ----------------------------------------------------------------------------------------------
//
//  Must take into account the loopback at first and then will complexify later
//
// ==============================================================================================

module tb_model_loopback
  import mhdma_pkg::*;
#() (
  // Ethernet fast clock interface --------------------------------------------
  input logic clk_eth_mrmac,
  input logic resetn_eth_mrmac,
  // QSFP system interface ----------------------------------------------------
  // == TX
  input  [QSFP_LANE_NB-1:0][MRMAC_AXIS_W-1:0  ] qsfp_tx_tdata,
  input  [QSFP_LANE_NB-1:0][MRMAC_TKEEP_W-1:0 ]  qsfp_tx_tkeep_user,
  input  [QSFP_LANE_NB-1:0]                     qsfp_tx_tlast,
  input  [QSFP_LANE_NB-1:0]                     qsfp_tx_tvalid,
  // == RX
  output reg [QSFP_LANE_NB-1:0][MRMAC_AXIS_W-1:0  ] qsfp_rx_tdata,
  output reg [QSFP_LANE_NB-1:0][MRMAC_TKEEP_W-1:0 ] qsfp_rx_tkeep_user,
  output reg [QSFP_LANE_NB-1:0]                     qsfp_rx_tlast,
  output reg [QSFP_LANE_NB-1:0]                     qsfp_rx_tvalid,
  // control interface --------------------------------------------------------
  // loopback mode, will be applied to all channels
  //  * 000: disabled
  //  * 010: near end pma
  //  * 100: near end pcs
  input [2:0] loopback
);

  // =========================================================================================== --
  // Localparam
  // =========================================================================================== --
  localparam int TOTAL_LAT = 10;

  // =========================================================================================== --
  // lanes
  // =========================================================================================== --
  logic [QSFP_LANE_NB-1:0][TOTAL_LAT-1:0][MRMAC_AXIS_W-1:0  ] rx_tdata_d;
  logic [QSFP_LANE_NB-1:0][TOTAL_LAT-1:0][MRMAC_TKEEP_W-1:0 ] rx_tkeep_user_d;
  logic [QSFP_LANE_NB-1:0][TOTAL_LAT-1:0]                     rx_tlast_d;
  logic [QSFP_LANE_NB-1:0][TOTAL_LAT-1:0]                     rx_tvalid_d;

  generate
    for (genvar gen_l = 0; gen_l < QSFP_LANE_NB ; gen_l = gen_l + 1) begin
      always_ff @(posedge clk_eth_mrmac) begin
        if ((loopback == 3'b000) || (loopback == 3'b010)) begin
          rx_tdata_d[gen_l][0]      <= qsfp_tx_tdata[gen_l];
          rx_tkeep_user_d[gen_l][0] <= qsfp_tx_tkeep_user[gen_l];
          rx_tlast_d[gen_l][0]      <= qsfp_tx_tlast[gen_l];
          rx_tvalid_d[gen_l][0]     <= qsfp_tx_tvalid[gen_l];
        end else begin
          rx_tdata_d[gen_l][0]      <= 'h0;
          rx_tkeep_user_d[gen_l][0] <= 'h0;
          rx_tlast_d[gen_l][0]      <= 'h0;
          rx_tvalid_d[gen_l][0]     <= 'h0;
        end
      end
    end
  endgenerate

  generate
    for (genvar gen_l = 0; gen_l < QSFP_LANE_NB ; gen_l = gen_l + 1) begin
      for (genvar gen_i = 1; gen_i < TOTAL_LAT ; gen_i = gen_i + 1) begin
        always_ff @(posedge clk_eth_mrmac) begin
          rx_tdata_d[gen_l][gen_i]      <= rx_tdata_d[gen_l][gen_i-1];
          rx_tkeep_user_d[gen_l][gen_i] <= rx_tkeep_user_d[gen_l][gen_i-1];
          rx_tlast_d[gen_l][gen_i]      <= rx_tlast_d[gen_l][gen_i-1];
          rx_tvalid_d[gen_l][gen_i]     <= rx_tvalid_d[gen_l][gen_i-1];
        end
      end
    end
  endgenerate


  generate
    for (genvar gen_l = 0; gen_l < QSFP_LANE_NB ; gen_l = gen_l + 1) begin
      always_ff @(posedge clk_eth_mrmac) begin
        qsfp_rx_tdata[gen_l]      <= rx_tdata_d[gen_l][TOTAL_LAT-1];
        qsfp_rx_tkeep_user[gen_l] <= rx_tkeep_user_d[gen_l][TOTAL_LAT-1];
        qsfp_rx_tlast[gen_l]      <= rx_tlast_d[gen_l][TOTAL_LAT-1];
        qsfp_rx_tvalid[gen_l]     <= rx_tvalid_d[gen_l][TOTAL_LAT-1];
      end
    end
  endgenerate


endmodule
