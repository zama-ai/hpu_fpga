// ============================================================================================== //
// Description  : register  map address definition package
// This file was generated with rust regmap generator:
//  * Date:  2025-10-17
//  * Tool_version: bd49564daf1a99d615cb6dbb121b54bfbeef8b22
// ---------------------------------------------------------------------------------------------- //
//
// Should only be used in testbench to drive the register interface
// ============================================================================================== //
package hpu_regif_core_eth_2in3_pkg;
  localparam int SYSTEM_SRC_MAC_ADDR_OFS = 'h50000;
  localparam int SYSTEM_DST_MAC_ADDR_OFS = 'h50004;
  typedef struct packed {
    logic [(1-1):0] debug;
    logic [(18-1):0] padding_13;
    logic [(8-1):0] rate;
    logic [(3-1):0] loopback;
    logic [(2-1):0] select;
   } system_line_t;
  localparam int SYSTEM_LINE_OFS = 'h50008;
  localparam int SYSTEM_DUMMY_VAL3_OFS = 'h5000c;
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
  typedef struct packed {
    logic [(1-1):0] reset_registers;
    logic [(1-1):0] tx_loop;
    logic [(1-1):0] rx_to_tx;
    logic [(29-1):0] padding_0;
   } line_debug_t;
  localparam int LINE_DEBUG_OFS = 'h51000;
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
