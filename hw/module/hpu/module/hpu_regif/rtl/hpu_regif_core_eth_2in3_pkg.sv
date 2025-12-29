// ============================================================================================== //
// Description  : register  map address definition package
// This file was generated with rust regmap generator:
//  * Date:  2025-12-29
//  * Tool_version: bd49564daf1a99d615cb6dbb121b54bfbeef8b22
// ---------------------------------------------------------------------------------------------- //
//
// Should only be used in testbench to drive the register interface
// ============================================================================================== //
package hpu_regif_core_eth_2in3_pkg;
  typedef struct packed {
    logic [(1-1):0] debug;
    logic [(18-1):0] padding_13;
    logic [(8-1):0] rate;
    logic [(3-1):0] loopback;
    logic [(2-1):0] select;
   } mhdma_system_lane_t;
  localparam int MHDMA_SYSTEM_LANE_OFS = 'h50000;
  typedef struct packed {
    logic [(32-1):0] notify_timeout_dur;
   } mhdma_system_timeout_notify_t;
  localparam int MHDMA_SYSTEM_TIMEOUT_NOTIFY_OFS = 'h50004;
  typedef struct packed {
    logic [(32-1):0] read_req_timeout_dur;
   } mhdma_system_timeout_read_req_t;
  localparam int MHDMA_SYSTEM_TIMEOUT_READ_REQ_OFS = 'h50008;
  localparam int MHDMA_SYSTEM_FSM_VALUE_OFS = 'h5000c;
  typedef struct packed {
    logic [(20-1):0] padding_12;
    logic [(4-1):0] rx_rst;
    logic [(4-1):0] tx_rst;
    logic [(4-1):0] gt_all;
   } mhdma_reset_datapath_t;
  localparam int MHDMA_RESET_DATAPATH_OFS = 'h50014;
  typedef struct packed {
    logic [(24-1):0] padding_8;
    logic [(8-1):0] rst_done;
   } mhdma_reset_monitor_t;
  localparam int MHDMA_RESET_MONITOR_OFS = 'h50018;
  localparam int MHDMA_HPU_ID_ZERO_OFS = 'h50050;
  localparam int MHDMA_HPU_ID_ONE_OFS = 'h50054;
  localparam int MHDMA_HPU_ID_TWO_OFS = 'h50058;
  localparam int MHDMA_HPU_ID_THREE_OFS = 'h5005c;
  localparam int MHDMA_HPU_ID_FOUR_OFS = 'h50060;
  localparam int MHDMA_HPU_ID_FIVE_OFS = 'h50064;
  localparam int MHDMA_HPU_ID_SIX_OFS = 'h50068;
  localparam int MHDMA_HPU_ID_SEVEN_OFS = 'h5006c;
  typedef struct packed {
    logic [(8-1):0] iop_id;
    logic [(4-1):0] req_id;
    logic [(4-1):0] node_id;
    logic [(16-1):0] size_b;
   } mhdma_request_req_id_t;
  localparam int MHDMA_REQUEST_REQ_ID_OFS = 'h50100;
  typedef struct packed {
    logic [(16-1):0] dst;
    logic [(16-1):0] src;
   } mhdma_request_req_addr_t;
  localparam int MHDMA_REQUEST_REQ_ADDR_OFS = 'h50104;
  typedef struct packed {
    logic [(16-1):0] src_addr;
    logic [(8-1):0] padding_8;
    logic [(4-1):0] node_id;
    logic [(4-1):0] iop_id;
   } mhdma_request_notify_t;
  localparam int MHDMA_REQUEST_NOTIFY_OFS = 'h50108;
  typedef struct packed {
    logic [(16-1):0] dst_addr;
    logic [(8-1):0] padding_8;
    logic [(4-1):0] node_id;
    logic [(4-1):0] iop_id;
   } mhdma_request_read_request_t;
  localparam int MHDMA_REQUEST_READ_REQUEST_OFS = 'h5010c;
  localparam int MHDMA_REQUEST_STAT_NOTIFY_OFS = 'h50110;
  localparam int MHDMA_REQUEST_STAT_NOTIFY_ACK_OFS = 'h50114;
  localparam int MHDMA_REQUEST_STAT_NOTIFY_TIMEOUT_RETRY_OFS = 'h50118;
  localparam int MHDMA_REQUEST_STAT_NB_NACK_RECEIVED_OFS = 'h5011c;
  localparam int MHDMA_REQUEST_STAT_NB_NOTIFY_RECEIVED_OFS = 'h50120;
  localparam int MHDMA_REQUEST_STAT_NB_READ_REQ_RECEIVED_OFS = 'h50124;
  localparam int MHDMA_REQUEST_STAT_NB_CE_RECEIVED_OFS = 'h50128;
  localparam int MHDMA_REQUEST_STAT_NB_READ_TO_HBM_OFS = 'h5012c;
  localparam int MHDMA_REQUEST_STAT_NB_WORDS_RECEIVED_PC_PC0_OFS = 'h50130;
  localparam int MHDMA_REQUEST_STAT_NB_WORDS_RECEIVED_PC_PC1_OFS = 'h50134;
  localparam int MHDMA_REQUEST_STAT_T_NOTIFY_TO_ACK_OFS = 'h50138;
  localparam int MHDMA_REQUEST_STAT_T_RR_TO_CE_RECEIVED_OFS = 'h5013c;
  localparam int MHDMA_REQUEST_STAT_T_CE_FIRST_TO_LAST_PKT_OFS = 'h50140;
  localparam int MHDMA_REQUEST_STAT_T_RR_WAIT_WORDS_PC_PC0_OFS = 'h50144;
  localparam int MHDMA_REQUEST_STAT_T_RR_WAIT_WORDS_PC_PC1_OFS = 'h50148;
  localparam int MHDMA_REQUEST_STAT_NOTIFY_TIMEOUT_OFS = 'h5014c;
  localparam int MHDMA_REQUEST_STAT_PHYSICAL_ADDR_PC0_LSB_OFS = 'h50150;
  localparam int MHDMA_REQUEST_STAT_PHYSICAL_ADDR_PC0_MSB_OFS = 'h50154;
  localparam int MHDMA_REQUEST_STAT_PHYSICAL_ADDR_PC1_LSB_OFS = 'h50158;
  localparam int MHDMA_REQUEST_STAT_PHYSICAL_ADDR_PC1_MSB_OFS = 'h5015c;
  typedef struct packed {
    logic [(1-1):0] reset_registers;
    logic [(1-1):0] tx_loop;
    logic [(1-1):0] rx_to_tx;
    logic [(29-1):0] padding_0;
   } mhdma_lane_debug_t;
  localparam int MHDMA_LANE_DEBUG_OFS = 'h50200;
  localparam int MHDMA_HBM_AXI4_ADDR_2IN3_CT_PC0_LSB_OFS = 'h51000;
  localparam int MHDMA_HBM_AXI4_ADDR_2IN3_CT_PC0_MSB_OFS = 'h51004;
  localparam int MHDMA_HBM_AXI4_ADDR_2IN3_CT_PC1_LSB_OFS = 'h51008;
  localparam int MHDMA_HBM_AXI4_ADDR_2IN3_CT_PC1_MSB_OFS = 'h5100c;
  localparam int FIFO_WRITE_NUMBER_OF_WORDS_OFS = 'h5101c;
  localparam int FIFO_WRITE_WORDS_TO_WRITE_A_OFS = 'h51020;
  localparam int FIFO_WRITE_WORDS_TO_WRITE_B_OFS = 'h51024;
  localparam int FIFO_WRITE_FIFO_WRITE_DATA_COUNT_OFS = 'h51028;
  localparam int FIFO_READ_WORDS_TO_READ_A_OFS = 'h5102c;
  localparam int FIFO_READ_WORDS_TO_READ_B_OFS = 'h51030;
  localparam int FIFO_READ_FIFO_READ_DATA_COUNT_OFS = 'h51034;
  localparam int CNT_TRIG_RD_OFS = 'h5103c;
  localparam int CNT_TX_WR_OFS = 'h51040;
  localparam int CNT_WORDS_OFS = 'h51044;
  localparam int MHDMA_STAT_STATUS_OFS = 'h5104c;
  localparam int MHDMA_STAT_CLK_A_OFS = 'h51050;
  localparam int MHDMA_STAT_CLK_B_OFS = 'h51054;
  localparam int MHDMA_STAT_VALID_WORDS_A_OFS = 'h51058;
  localparam int MHDMA_STAT_VALID_WORDS_B_OFS = 'h5105c;
  localparam int MHDMA_STAT_SOP_CNT_A_OFS = 'h51060;
  localparam int MHDMA_STAT_SOP_CNT_B_OFS = 'h51064;
endpackage
