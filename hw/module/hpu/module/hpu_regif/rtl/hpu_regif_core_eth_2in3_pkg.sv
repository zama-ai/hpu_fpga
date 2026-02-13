// ============================================================================================== //
// Description  : register  map address definition package
// This file was generated with rust regmap generator:
//  * Date:  2026-02-13
//  * Tool_version: 27d9e880d531030160fd8749c606142942d5558d
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
  localparam int MHDMA_SYSTEM_ERRORS_OFS = 'h50010;
  localparam int MHDMA_SYSTEM_HPU_ID_0_OFS = 'h50014;
  localparam int MHDMA_SYSTEM_HPU_ID_1_OFS = 'h50018;
  localparam int MHDMA_SYSTEM_HPU_ID_2_OFS = 'h5001c;
  localparam int MHDMA_SYSTEM_HPU_ID_3_OFS = 'h50020;
  localparam int MHDMA_SYSTEM_HPU_ID_4_OFS = 'h50024;
  localparam int MHDMA_SYSTEM_HPU_ID_5_OFS = 'h50028;
  localparam int MHDMA_SYSTEM_HPU_ID_6_OFS = 'h5002c;
  localparam int MHDMA_SYSTEM_HPU_ID_7_OFS = 'h50030;
  typedef struct packed {
    logic [(20-1):0] padding_12;
    logic [(4-1):0] rx_rst;
    logic [(4-1):0] tx_rst;
    logic [(4-1):0] gt_all;
   } mhdma_reset_datapath_t;
  localparam int MHDMA_RESET_DATAPATH_OFS = 'h50090;
  typedef struct packed {
    logic [(24-1):0] padding_8;
    logic [(8-1):0] rst_done;
   } mhdma_reset_monitor_t;
  localparam int MHDMA_RESET_MONITOR_OFS = 'h50094;
  typedef struct packed {
    logic [(8-1):0] iop_id;
    logic [(4-1):0] req_id;
    logic [(4-1):0] node_id;
    logic [(2-1):0] mode;
    logic [(6-1):0] flag;
    logic [(8-1):0] rsvd;
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
  localparam int MHDMA_REQUEST_STAT_READ_REQ_TIMEOUT_RETRY_OFS = 'h5011c;
  localparam int MHDMA_REQUEST_STAT_NB_NACK_RECEIVED_OFS = 'h50120;
  localparam int MHDMA_REQUEST_STAT_NB_NOTIFY_RECEIVED_OFS = 'h50124;
  localparam int MHDMA_REQUEST_STAT_NB_READ_REQ_RECEIVED_OFS = 'h50128;
  localparam int MHDMA_REQUEST_STAT_NB_CE_RECEIVED_OFS = 'h5012c;
  localparam int MHDMA_REQUEST_STAT_NB_READ_TO_HBM_OFS = 'h50130;
  localparam int MHDMA_REQUEST_STAT_NB_WORDS_RECEIVED_PC_PC0_OFS = 'h50134;
  localparam int MHDMA_REQUEST_STAT_NB_WORDS_RECEIVED_PC_PC1_OFS = 'h50138;
  localparam int MHDMA_REQUEST_STAT_NB_CE_WORDS_RECEIVED_OFS = 'h5013c;
  localparam int MHDMA_REQUEST_STAT_T_NOTIFY_TO_ACK_OFS = 'h50140;
  localparam int MHDMA_REQUEST_STAT_T_RR_TO_CE_RECEIVED_OFS = 'h50144;
  localparam int MHDMA_REQUEST_STAT_T_CE_FIRST_TO_LAST_PKT_OFS = 'h50148;
  localparam int MHDMA_REQUEST_STAT_T_RR_WAIT_WORDS_PC_PC0_OFS = 'h5014c;
  localparam int MHDMA_REQUEST_STAT_T_RR_WAIT_WORDS_PC_PC1_OFS = 'h50150;
  localparam int MHDMA_REQUEST_STAT_NOTIFY_TIMEOUT_OFS = 'h50154;
  localparam int MHDMA_REQUEST_STAT_PHYSICAL_ADDR_PC0_LSB_OFS = 'h50158;
  localparam int MHDMA_REQUEST_STAT_PHYSICAL_ADDR_PC0_MSB_OFS = 'h5015c;
  localparam int MHDMA_REQUEST_STAT_PHYSICAL_ADDR_PC1_LSB_OFS = 'h50160;
  localparam int MHDMA_REQUEST_STAT_PHYSICAL_ADDR_PC1_MSB_OFS = 'h50164;
  localparam int MHDMA_REQUEST_STAT_CNT_NB_WRITE_COMPLETE_OFS = 'h50168;
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
endpackage
