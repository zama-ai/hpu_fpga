// ============================================================================================== //
// Description  : register  map address definition package
// This file was generated with rust regmap generator:
//  * Date:  2025-11-19
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
   } system_line_t;
  localparam int SYSTEM_LINE_OFS = 'h50000;
  localparam int SYSTEM_TIMEOUT_OFS = 'h50004;
  typedef struct packed {
    logic [(20-1):0] padding_12;
    logic [(4-1):0] rx_rst;
    logic [(4-1):0] tx_rst;
    logic [(4-1):0] gt_all;
   } reset_datapath_t;
  localparam int RESET_DATAPATH_OFS = 'h50014;
  typedef struct packed {
    logic [(24-1):0] padding_8;
    logic [(8-1):0] rst_done;
   } reset_monitor_t;
  localparam int RESET_MONITOR_OFS = 'h50018;
  localparam int HPU_ID_ZERO_OFS = 'h50050;
  localparam int HPU_ID_ONE_OFS = 'h50054;
  localparam int HPU_ID_TWO_OFS = 'h50058;
  localparam int HPU_ID_THREE_OFS = 'h5005c;
  localparam int HPU_ID_FOUR_OFS = 'h50060;
  localparam int HPU_ID_FIVE_OFS = 'h50064;
  localparam int HPU_ID_SIX_OFS = 'h50068;
  localparam int HPU_ID_SEVEN_OFS = 'h5006c;
  typedef struct packed {
    logic [(8-1):0] iop_id;
    logic [(4-1):0] req_id;
    logic [(4-1):0] node_id;
    logic [(16-1):0] size_b;
   } request_req_id_t;
  localparam int REQUEST_REQ_ID_OFS = 'h50100;
  typedef struct packed {
    logic [(16-1):0] dst;
    logic [(16-1):0] src;
   } request_req_addr_t;
  localparam int REQUEST_REQ_ADDR_OFS = 'h50104;
  typedef struct packed {
    logic [(16-1):0] src_addr;
    logic [(8-1):0] padding_8;
    logic [(4-1):0] node_id;
    logic [(4-1):0] iop_id;
   } request_notify_t;
  localparam int REQUEST_NOTIFY_OFS = 'h50108;
  typedef struct packed {
    logic [(16-1):0] cnt_notify_read;
    logic [(16-1):0] cnt_notify_ack;
   } request_stat_notify_t;
  localparam int REQUEST_STAT_NOTIFY_OFS = 'h5010c;
  typedef struct packed {
    logic [(1-1):0] reset_registers;
    logic [(1-1):0] tx_loop;
    logic [(1-1):0] rx_to_tx;
    logic [(29-1):0] padding_0;
   } line_debug_t;
  localparam int LINE_DEBUG_OFS = 'h50200;
  localparam int HBM_AXI4_ADDR_2IN3_CT_PC0_LSB_OFS = 'h51000;
  localparam int HBM_AXI4_ADDR_2IN3_CT_PC0_MSB_OFS = 'h51004;
  localparam int HBM_AXI4_ADDR_2IN3_CT_PC1_LSB_OFS = 'h51008;
  localparam int HBM_AXI4_ADDR_2IN3_CT_PC1_MSB_OFS = 'h5100c;
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
  localparam int STAT_STATUS_OFS = 'h5104c;
  localparam int STAT_CLK_A_OFS = 'h51050;
  localparam int STAT_CLK_B_OFS = 'h51054;
  localparam int STAT_VALID_WORDS_A_OFS = 'h51058;
  localparam int STAT_VALID_WORDS_B_OFS = 'h5105c;
  localparam int STAT_SOP_CNT_A_OFS = 'h51060;
  localparam int STAT_SOP_CNT_B_OFS = 'h51064;
endpackage
