// ============================================================================================== //
// Description  : register  map address definition package
// This file was generated with rust regmap generator:
//  * Date:  2025-07-17
//  * Tool_version: bb0db737792da6b81e69a039028c971af1627fe2
// ---------------------------------------------------------------------------------------------- //
//
// Should only be used in testbench to drive the register interface
// ============================================================================================== //
package hpu_regif_core_prc_3in3_pkg;
  localparam int ENTRY_PRC_3IN3_DUMMY_VAL0_OFS = 'h30000;
  localparam int ENTRY_PRC_3IN3_DUMMY_VAL1_OFS = 'h30004;
  localparam int ENTRY_PRC_3IN3_DUMMY_VAL2_OFS = 'h30008;
  localparam int ENTRY_PRC_3IN3_DUMMY_VAL3_OFS = 'h3000c;
  typedef struct packed {
    logic [(32-1):0] pbs;
   } status_3in3_error_t;
  localparam int STATUS_3IN3_ERROR_OFS = 'h30010;
  typedef struct packed {
    logic [(31-1):0] padding_1;
    logic [(1-1):0] avail;
   } bsk_avail_avail_t;
  localparam int BSK_AVAIL_AVAIL_OFS = 'h31000;
  typedef struct packed {
    logic [(1-1):0] done;
    logic [(30-1):0] padding_1;
    logic [(1-1):0] request;
   } bsk_avail_reset_t;
  localparam int BSK_AVAIL_RESET_OFS = 'h31004;
  localparam int RUNTIME_3IN3_PEP_LOAD_BSK_RCP_DUR_PC0_OFS = 'h32000;
  localparam int RUNTIME_3IN3_PEP_LOAD_BSK_RCP_DUR_PC1_OFS = 'h32004;
  localparam int RUNTIME_3IN3_PEP_LOAD_BSK_RCP_DUR_PC2_OFS = 'h32008;
  localparam int RUNTIME_3IN3_PEP_LOAD_BSK_RCP_DUR_PC3_OFS = 'h3200c;
  localparam int RUNTIME_3IN3_PEP_LOAD_BSK_RCP_DUR_PC4_OFS = 'h32010;
  localparam int RUNTIME_3IN3_PEP_LOAD_BSK_RCP_DUR_PC5_OFS = 'h32014;
  localparam int RUNTIME_3IN3_PEP_LOAD_BSK_RCP_DUR_PC6_OFS = 'h32018;
  localparam int RUNTIME_3IN3_PEP_LOAD_BSK_RCP_DUR_PC7_OFS = 'h3201c;
  localparam int RUNTIME_3IN3_PEP_LOAD_BSK_RCP_DUR_PC8_OFS = 'h32020;
  localparam int RUNTIME_3IN3_PEP_LOAD_BSK_RCP_DUR_PC9_OFS = 'h32024;
  localparam int RUNTIME_3IN3_PEP_LOAD_BSK_RCP_DUR_PC10_OFS = 'h32028;
  localparam int RUNTIME_3IN3_PEP_LOAD_BSK_RCP_DUR_PC11_OFS = 'h3202c;
  localparam int RUNTIME_3IN3_PEP_LOAD_BSK_RCP_DUR_PC12_OFS = 'h32030;
  localparam int RUNTIME_3IN3_PEP_LOAD_BSK_RCP_DUR_PC13_OFS = 'h32034;
  localparam int RUNTIME_3IN3_PEP_LOAD_BSK_RCP_DUR_PC14_OFS = 'h32038;
  localparam int RUNTIME_3IN3_PEP_LOAD_BSK_RCP_DUR_PC15_OFS = 'h3203c;
  typedef struct packed {
    logic [(16-1):0] req_br_loop_wp;
    logic [(16-1):0] req_br_loop_rp;
   } runtime_3in3_pep_bskif_req_info_0_t;
  localparam int RUNTIME_3IN3_PEP_BSKIF_REQ_INFO_0_OFS = 'h32040;
  typedef struct packed {
    logic [(1-1):0] req_assigned;
    logic [(14-1):0] padding_17;
    logic [(1-1):0] req_parity;
    logic [(16-1):0] req_prf_br_loop;
   } runtime_3in3_pep_bskif_req_info_1_t;
  localparam int RUNTIME_3IN3_PEP_BSKIF_REQ_INFO_1_OFS = 'h32044;
endpackage
