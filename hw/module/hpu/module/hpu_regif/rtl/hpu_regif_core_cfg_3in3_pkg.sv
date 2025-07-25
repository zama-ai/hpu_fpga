// ============================================================================================== //
// Description  : register  map address definition package
// This file was generated with rust regmap generator:
//  * Date:  2025-07-17
//  * Tool_version: bb0db737792da6b81e69a039028c971af1627fe2
// ---------------------------------------------------------------------------------------------- //
//
// Should only be used in testbench to drive the register interface
// ============================================================================================== //
package hpu_regif_core_cfg_3in3_pkg;
  localparam int ENTRY_CFG_3IN3_DUMMY_VAL0_OFS = 'h20000;
  localparam int ENTRY_CFG_3IN3_DUMMY_VAL1_OFS = 'h20004;
  localparam int ENTRY_CFG_3IN3_DUMMY_VAL2_OFS = 'h20008;
  localparam int ENTRY_CFG_3IN3_DUMMY_VAL3_OFS = 'h2000c;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC0_LSB_OFS = 'h20010;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC0_MSB_OFS = 'h20014;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC1_LSB_OFS = 'h20018;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC1_MSB_OFS = 'h2001c;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC2_LSB_OFS = 'h20020;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC2_MSB_OFS = 'h20024;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC3_LSB_OFS = 'h20028;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC3_MSB_OFS = 'h2002c;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC4_LSB_OFS = 'h20030;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC4_MSB_OFS = 'h20034;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC5_LSB_OFS = 'h20038;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC5_MSB_OFS = 'h2003c;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC6_LSB_OFS = 'h20040;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC6_MSB_OFS = 'h20044;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC7_LSB_OFS = 'h20048;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC7_MSB_OFS = 'h2004c;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC8_LSB_OFS = 'h20050;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC8_MSB_OFS = 'h20054;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC9_LSB_OFS = 'h20058;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC9_MSB_OFS = 'h2005c;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC10_LSB_OFS = 'h20060;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC10_MSB_OFS = 'h20064;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC11_LSB_OFS = 'h20068;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC11_MSB_OFS = 'h2006c;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC12_LSB_OFS = 'h20070;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC12_MSB_OFS = 'h20074;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC13_LSB_OFS = 'h20078;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC13_MSB_OFS = 'h2007c;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC14_LSB_OFS = 'h20080;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC14_MSB_OFS = 'h20084;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC15_LSB_OFS = 'h20088;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC15_MSB_OFS = 'h2008c;
  typedef struct packed {
    logic [(1-1):0] done;
    logic [(30-1):0] padding_1;
    logic [(1-1):0] request;
   } hpu_reset_trigger_t;
  localparam int HPU_RESET_TRIGGER_OFS = 'h20100;
endpackage
