// ============================================================================================== //
// Description  : register  map address definition package
// This file was generated with rust regmap generator:
//  * Date:  2025-09-17
//  * Tool_version: bb0db737792da6b81e69a039028c971af1627fe2
// ---------------------------------------------------------------------------------------------- //
//
// Should only be used in testbench to drive the register interface
// ============================================================================================== //
package hpu_regif_core_prc_3in3_pkg;
  localparam int ENTRY_PRC_3IN3_DUMMY_VAL0_OFS = 'hb0000;
  localparam int ENTRY_PRC_3IN3_DUMMY_VAL1_OFS = 'hb0004;
  localparam int ENTRY_PRC_3IN3_DUMMY_VAL2_OFS = 'hb0008;
  localparam int ENTRY_PRC_3IN3_DUMMY_VAL3_OFS = 'hb000c;
  typedef struct packed {
    logic [(32-1):0] pbs;
   } status_3in3_error_t;
  localparam int STATUS_3IN3_ERROR_OFS = 'hb0010;
  typedef struct packed {
    logic [(31-1):0] padding_1;
    logic [(1-1):0] avail;
   } bsk_avail_avail_t;
  localparam int BSK_AVAIL_AVAIL_OFS = 'hb1000;
  typedef struct packed {
    logic [(1-1):0] done;
    logic [(30-1):0] padding_1;
    logic [(1-1):0] request;
   } bsk_avail_reset_t;
  localparam int BSK_AVAIL_RESET_OFS = 'hb1004;
  localparam int RUNTIME_3IN3_PEP_LOAD_BSK_RCP_DUR_PC0_OFS = 'hb2000;
  localparam int RUNTIME_3IN3_PEP_LOAD_BSK_RCP_DUR_PC1_OFS = 'hb2004;
  localparam int RUNTIME_3IN3_PEP_LOAD_BSK_RCP_DUR_PC2_OFS = 'hb2008;
  localparam int RUNTIME_3IN3_PEP_LOAD_BSK_RCP_DUR_PC3_OFS = 'hb200c;
  localparam int RUNTIME_3IN3_PEP_LOAD_BSK_RCP_DUR_PC4_OFS = 'hb2010;
  localparam int RUNTIME_3IN3_PEP_LOAD_BSK_RCP_DUR_PC5_OFS = 'hb2014;
  localparam int RUNTIME_3IN3_PEP_LOAD_BSK_RCP_DUR_PC6_OFS = 'hb2018;
  localparam int RUNTIME_3IN3_PEP_LOAD_BSK_RCP_DUR_PC7_OFS = 'hb201c;
  localparam int RUNTIME_3IN3_PEP_LOAD_BSK_RCP_DUR_PC8_OFS = 'hb2020;
  localparam int RUNTIME_3IN3_PEP_LOAD_BSK_RCP_DUR_PC9_OFS = 'hb2024;
  localparam int RUNTIME_3IN3_PEP_LOAD_BSK_RCP_DUR_PC10_OFS = 'hb2028;
  localparam int RUNTIME_3IN3_PEP_LOAD_BSK_RCP_DUR_PC11_OFS = 'hb202c;
  localparam int RUNTIME_3IN3_PEP_LOAD_BSK_RCP_DUR_PC12_OFS = 'hb2030;
  localparam int RUNTIME_3IN3_PEP_LOAD_BSK_RCP_DUR_PC13_OFS = 'hb2034;
  localparam int RUNTIME_3IN3_PEP_LOAD_BSK_RCP_DUR_PC14_OFS = 'hb2038;
  localparam int RUNTIME_3IN3_PEP_LOAD_BSK_RCP_DUR_PC15_OFS = 'hb203c;
  typedef struct packed {
    logic [(16-1):0] req_br_loop_wp;
    logic [(16-1):0] req_br_loop_rp;
   } runtime_3in3_pep_bskif_req_info_0_t;
  localparam int RUNTIME_3IN3_PEP_BSKIF_REQ_INFO_0_OFS = 'hb2040;
  typedef struct packed {
    logic [(1-1):0] req_assigned;
    logic [(14-1):0] padding_17;
    logic [(1-1):0] req_parity;
    logic [(16-1):0] req_prf_br_loop;
   } runtime_3in3_pep_bskif_req_info_1_t;
  localparam int RUNTIME_3IN3_PEP_BSKIF_REQ_INFO_1_OFS = 'hb2044;
endpackage
