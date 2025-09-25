// ============================================================================================== //
// Description  : register  map address definition package
// This file was generated with rust regmap generator:
//  * Date:  2025-09-25
//  * Tool_version: bb0db737792da6b81e69a039028c971af1627fe2
// ---------------------------------------------------------------------------------------------- //
//
// Should only be used in testbench to drive the register interface
// ============================================================================================== //
package hpu_regif_core_eth_2in3_pkg;
  localparam int ENTRY_ETH_2IN3_DUMMY_VAL0_OFS = 'he0000;
  localparam int ENTRY_ETH_2IN3_DUMMY_VAL1_OFS = 'he0004;
  localparam int ENTRY_ETH_2IN3_DUMMY_VAL2_OFS = 'he0008;
  localparam int ENTRY_ETH_2IN3_DUMMY_VAL3_OFS = 'he000c;
  typedef struct packed {
    logic [(1-1):0] reset_registers;
    logic [(1-1):0] tx_loop;
    logic [(1-1):0] rx_to_tx;
    logic [(16-1):0] padding_13;
    logic [(8-1):0] rate;
    logic [(3-1):0] loopback;
    logic [(2-1):0] select;
   } line_parameter_t;
  localparam int LINE_PARAMETER_OFS = 'he0010;
  typedef struct packed {
    logic [(20-1):0] padding_12;
    logic [(4-1):0] rx_rst;
    logic [(4-1):0] tx_rst;
    logic [(4-1):0] gt_all;
   } reset_datapath_t;
  localparam int RESET_DATAPATH_OFS = 'he0014;
  typedef struct packed {
    logic [(24-1):0] padding_8;
    logic [(8-1):0] rst_done;
   } reset_monitor_t;
  localparam int RESET_MONITOR_OFS = 'he0018;
  localparam int FIFO_WRITE_NUMBER_OF_WORDS_OFS = 'he001c;
  localparam int FIFO_WRITE_WORDS_TO_WRITE_A_OFS = 'he0020;
  localparam int FIFO_WRITE_WORDS_TO_WRITE_B_OFS = 'he0024;
  localparam int FIFO_WRITE_FIFO_WRITE_DATA_COUNT_OFS = 'he0028;
  localparam int FIFO_READ_WORDS_TO_READ_A_OFS = 'he002c;
  localparam int FIFO_READ_WORDS_TO_READ_B_OFS = 'he0030;
  localparam int FIFO_READ_FIFO_READ_DATA_COUNT_OFS = 'he0034;
  localparam int CNT_TRIG_RD_OFS = 'he003c;
  localparam int CNT_TX_WR_OFS = 'he0040;
  localparam int CNT_WORDS_OFS = 'he0044;
  localparam int STAT_STATUS_OFS = 'he004c;
  localparam int STAT_CLK_A_OFS = 'he0050;
  localparam int STAT_CLK_B_OFS = 'he0054;
  localparam int STAT_VALID_WORDS_A_OFS = 'he0058;
  localparam int STAT_VALID_WORDS_B_OFS = 'he005c;
  localparam int STAT_SOP_CNT_A_OFS = 'he0060;
  localparam int STAT_SOP_CNT_B_OFS = 'he0064;
endpackage
