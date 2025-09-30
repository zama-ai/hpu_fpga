// ============================================================================================== //
// Description  : register  map address definition package
// This file was generated with rust regmap generator:
//  * Date:  2025-09-30
//  * Tool_version: bb0db737792da6b81e69a039028c971af1627fe2
// ---------------------------------------------------------------------------------------------- //
//
// Should only be used in testbench to drive the register interface
// ============================================================================================== //
package hpu_regif_core_cfg_3in3_pkg;
  localparam int ENTRY_CFG_3IN3_DUMMY_VAL0_OFS = 'ha0000;
  localparam int ENTRY_CFG_3IN3_DUMMY_VAL1_OFS = 'ha0004;
  localparam int ENTRY_CFG_3IN3_DUMMY_VAL2_OFS = 'ha0008;
  localparam int ENTRY_CFG_3IN3_DUMMY_VAL3_OFS = 'ha000c;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC0_LSB_OFS = 'ha0010;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC0_MSB_OFS = 'ha0014;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC1_LSB_OFS = 'ha0018;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC1_MSB_OFS = 'ha001c;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC2_LSB_OFS = 'ha0020;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC2_MSB_OFS = 'ha0024;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC3_LSB_OFS = 'ha0028;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC3_MSB_OFS = 'ha002c;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC4_LSB_OFS = 'ha0030;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC4_MSB_OFS = 'ha0034;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC5_LSB_OFS = 'ha0038;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC5_MSB_OFS = 'ha003c;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC6_LSB_OFS = 'ha0040;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC6_MSB_OFS = 'ha0044;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC7_LSB_OFS = 'ha0048;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC7_MSB_OFS = 'ha004c;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC8_LSB_OFS = 'ha0050;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC8_MSB_OFS = 'ha0054;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC9_LSB_OFS = 'ha0058;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC9_MSB_OFS = 'ha005c;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC10_LSB_OFS = 'ha0060;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC10_MSB_OFS = 'ha0064;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC11_LSB_OFS = 'ha0068;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC11_MSB_OFS = 'ha006c;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC12_LSB_OFS = 'ha0070;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC12_MSB_OFS = 'ha0074;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC13_LSB_OFS = 'ha0078;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC13_MSB_OFS = 'ha007c;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC14_LSB_OFS = 'ha0080;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC14_MSB_OFS = 'ha0084;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC15_LSB_OFS = 'ha0088;
  localparam int HBM_AXI4_ADDR_3IN3_BSK_PC15_MSB_OFS = 'ha008c;
  typedef struct packed {
    logic [(1-1):0] done;
    logic [(30-1):0] padding_1;
    logic [(1-1):0] request;
   } hpu_reset_trigger_t;
  localparam int HPU_RESET_TRIGGER_OFS = 'ha0100;
endpackage
