// ============================================================================================== //
// Description  : register  map address definition package
// This file was generated with rust regmap generator:
//  * Date:  2025-07-17
//  * Tool_version: bb0db737792da6b81e69a039028c971af1627fe2
// ---------------------------------------------------------------------------------------------- //
//
// Should only be used in testbench to drive the register interface
// ============================================================================================== //
package hpu_regif_core_prc_1in3_pkg;
  localparam int ENTRY_PRC_1IN3_DUMMY_VAL0_OFS = 'h10000;
  localparam int ENTRY_PRC_1IN3_DUMMY_VAL1_OFS = 'h10004;
  localparam int ENTRY_PRC_1IN3_DUMMY_VAL2_OFS = 'h10008;
  localparam int ENTRY_PRC_1IN3_DUMMY_VAL3_OFS = 'h1000c;
  typedef struct packed {
    logic [(32-1):0] pbs;
   } status_1in3_error_t;
  localparam int STATUS_1IN3_ERROR_OFS = 'h10010;
  typedef struct packed {
    logic [(31-1):0] padding_1;
    logic [(1-1):0] avail;
   } ksk_avail_avail_t;
  localparam int KSK_AVAIL_AVAIL_OFS = 'h11000;
  typedef struct packed {
    logic [(1-1):0] done;
    logic [(30-1):0] padding_1;
    logic [(1-1):0] request;
   } ksk_avail_reset_t;
  localparam int KSK_AVAIL_RESET_OFS = 'h11004;
  typedef struct packed {
    logic [(1-1):0] ks_loop_c;
    logic [(15-1):0] ks_loop;
    logic [(1-1):0] br_loop_c;
    logic [(15-1):0] br_loop;
   } runtime_1in3_pep_cmux_loop_t;
  localparam int RUNTIME_1IN3_PEP_CMUX_LOOP_OFS = 'h12000;
  typedef struct packed {
    logic [(8-1):0] ldb_pt;
    logic [(8-1):0] ldg_pt;
    logic [(8-1):0] pool_wp;
    logic [(8-1):0] pool_rp;
   } runtime_1in3_pep_pointer_0_t;
  localparam int RUNTIME_1IN3_PEP_POINTER_0_OFS = 'h12004;
  typedef struct packed {
    logic [(8-1):0] ks_out_wp;
    logic [(8-1):0] ks_out_rp;
    logic [(8-1):0] ks_in_wp;
    logic [(8-1):0] ks_in_rp;
   } runtime_1in3_pep_pointer_1_t;
  localparam int RUNTIME_1IN3_PEP_POINTER_1_OFS = 'h12008;
  typedef struct packed {
    logic [(16-1):0] ipip_flush_last_pbs_in_loop;
    logic [(8-1):0] pbs_in_wp;
    logic [(8-1):0] pbs_in_rp;
   } runtime_1in3_pep_pointer_2_t;
  localparam int RUNTIME_1IN3_PEP_POINTER_2_OFS = 'h1200c;
  localparam int RUNTIME_1IN3_ISC_LATEST_INSTRUCTION_0_OFS = 'h12010;
  localparam int RUNTIME_1IN3_ISC_LATEST_INSTRUCTION_1_OFS = 'h12014;
  localparam int RUNTIME_1IN3_ISC_LATEST_INSTRUCTION_2_OFS = 'h12018;
  localparam int RUNTIME_1IN3_ISC_LATEST_INSTRUCTION_3_OFS = 'h1201c;
  localparam int RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_CNT_OFS = 'h12020;
  localparam int RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FLUSH_CNT_OFS = 'h12024;
  localparam int RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_TIMEOUT_CNT_OFS = 'h12028;
  localparam int RUNTIME_1IN3_PEP_SEQ_BPIP_WAITING_BATCH_CNT_OFS = 'h1202c;
  localparam int RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_1_OFS = 'h12030;
  localparam int RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_2_OFS = 'h12034;
  localparam int RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_3_OFS = 'h12038;
  localparam int RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_4_OFS = 'h1203c;
  localparam int RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_5_OFS = 'h12040;
  localparam int RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_6_OFS = 'h12044;
  localparam int RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_7_OFS = 'h12048;
  localparam int RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_8_OFS = 'h1204c;
  localparam int RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_9_OFS = 'h12050;
  localparam int RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_10_OFS = 'h12054;
  localparam int RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_11_OFS = 'h12058;
  localparam int RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_12_OFS = 'h1205c;
  localparam int RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_13_OFS = 'h12060;
  localparam int RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_14_OFS = 'h12064;
  localparam int RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_15_OFS = 'h12068;
  localparam int RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_16_OFS = 'h1206c;
  localparam int RUNTIME_1IN3_PEP_SEQ_LD_ACK_CNT_OFS = 'h12070;
  localparam int RUNTIME_1IN3_PEP_SEQ_CMUX_NOT_FULL_BATCH_CNT_OFS = 'h12074;
  localparam int RUNTIME_1IN3_PEP_SEQ_IPIP_FLUSH_CNT_OFS = 'h12078;
  localparam int RUNTIME_1IN3_PEP_LDB_RCP_DUR_OFS = 'h1207c;
  localparam int RUNTIME_1IN3_PEP_LDG_REQ_DUR_OFS = 'h12080;
  localparam int RUNTIME_1IN3_PEP_LDG_RCP_DUR_OFS = 'h12084;
  localparam int RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC0_OFS = 'h12088;
  localparam int RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC1_OFS = 'h1208c;
  localparam int RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC2_OFS = 'h12090;
  localparam int RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC3_OFS = 'h12094;
  localparam int RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC4_OFS = 'h12098;
  localparam int RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC5_OFS = 'h1209c;
  localparam int RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC6_OFS = 'h120a0;
  localparam int RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC7_OFS = 'h120a4;
  localparam int RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC8_OFS = 'h120a8;
  localparam int RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC9_OFS = 'h120ac;
  localparam int RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC10_OFS = 'h120b0;
  localparam int RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC11_OFS = 'h120b4;
  localparam int RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC12_OFS = 'h120b8;
  localparam int RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC13_OFS = 'h120bc;
  localparam int RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC14_OFS = 'h120c0;
  localparam int RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC15_OFS = 'h120c4;
  localparam int RUNTIME_1IN3_PEP_MMACC_SXT_RCP_DUR_OFS = 'h120c8;
  localparam int RUNTIME_1IN3_PEP_MMACC_SXT_REQ_DUR_OFS = 'h120cc;
  localparam int RUNTIME_1IN3_PEP_MMACC_SXT_CMD_WAIT_B_DUR_OFS = 'h120d0;
  localparam int RUNTIME_1IN3_PEP_INST_CNT_OFS = 'h120d4;
  localparam int RUNTIME_1IN3_PEP_ACK_CNT_OFS = 'h120d8;
  localparam int RUNTIME_1IN3_PEM_LOAD_INST_CNT_OFS = 'h120dc;
  localparam int RUNTIME_1IN3_PEM_LOAD_ACK_CNT_OFS = 'h120e0;
  localparam int RUNTIME_1IN3_PEM_STORE_INST_CNT_OFS = 'h120e4;
  localparam int RUNTIME_1IN3_PEM_STORE_ACK_CNT_OFS = 'h120e8;
  localparam int RUNTIME_1IN3_PEA_INST_CNT_OFS = 'h120ec;
  localparam int RUNTIME_1IN3_PEA_ACK_CNT_OFS = 'h120f0;
  localparam int RUNTIME_1IN3_ISC_INST_CNT_OFS = 'h120f4;
  localparam int RUNTIME_1IN3_ISC_ACK_CNT_OFS = 'h120f8;
  localparam int RUNTIME_1IN3_PEM_LOAD_INFO_0_PC0_0_OFS = 'h120fc;
  localparam int RUNTIME_1IN3_PEM_LOAD_INFO_0_PC0_1_OFS = 'h12100;
  localparam int RUNTIME_1IN3_PEM_LOAD_INFO_0_PC0_2_OFS = 'h12104;
  localparam int RUNTIME_1IN3_PEM_LOAD_INFO_0_PC0_3_OFS = 'h12108;
  localparam int RUNTIME_1IN3_PEM_LOAD_INFO_0_PC1_0_OFS = 'h1210c;
  localparam int RUNTIME_1IN3_PEM_LOAD_INFO_0_PC1_1_OFS = 'h12110;
  localparam int RUNTIME_1IN3_PEM_LOAD_INFO_0_PC1_2_OFS = 'h12114;
  localparam int RUNTIME_1IN3_PEM_LOAD_INFO_0_PC1_3_OFS = 'h12118;
  localparam int RUNTIME_1IN3_PEM_LOAD_INFO_1_PC0_LSB_OFS = 'h1211c;
  localparam int RUNTIME_1IN3_PEM_LOAD_INFO_1_PC0_MSB_OFS = 'h12120;
  localparam int RUNTIME_1IN3_PEM_LOAD_INFO_1_PC1_LSB_OFS = 'h12124;
  localparam int RUNTIME_1IN3_PEM_LOAD_INFO_1_PC1_MSB_OFS = 'h12128;
  typedef struct packed {
    logic [(4-1):0] c0_enough_location;
    logic [(4-1):0] r2_axi_rdy;
    logic [(4-1):0] r2_axi_vld;
    logic [(4-1):0] rcp_fifo_in_rdy;
    logic [(4-1):0] rcp_fifo_in_vld;
    logic [(4-1):0] brsp_fifo_in_rdy;
    logic [(4-1):0] brsp_fifo_in_vld;
    logic [(1-1):0] pem_regf_rd_req_rdy;
    logic [(1-1):0] pem_regf_rd_req_vld;
    logic [(1-1):0] cmd_rdy;
    logic [(1-1):0] cmd_vld;
   } runtime_1in3_pem_store_info_0_t;
  localparam int RUNTIME_1IN3_PEM_STORE_INFO_0_OFS = 'h1212c;
  typedef struct packed {
    logic [(4-1):0] m_axi_awready;
    logic [(4-1):0] m_axi_awvalid;
    logic [(4-1):0] m_axi_wready;
    logic [(4-1):0] m_axi_wvalid;
    logic [(4-1):0] m_axi_bready;
    logic [(4-1):0] m_axi_bvalid;
    logic [(4-1):0] s0_cmd_rdy;
    logic [(4-1):0] s0_cmd_vld;
   } runtime_1in3_pem_store_info_1_t;
  localparam int RUNTIME_1IN3_PEM_STORE_INFO_1_OFS = 'h12130;
  typedef struct packed {
    logic [(16-1):0] brsp_bresp_cnt;
    logic [(16-1):0] c0_free_loc_cnt;
   } runtime_1in3_pem_store_info_2_t;
  localparam int RUNTIME_1IN3_PEM_STORE_INFO_2_OFS = 'h12134;
  typedef struct packed {
    logic [(8-1):0] padding_24;
    logic [(8-1):0] c0_cmd_cnt;
    logic [(16-1):0] brsp_ack_seen;
   } runtime_1in3_pem_store_info_3_t;
  localparam int RUNTIME_1IN3_PEM_STORE_INFO_3_OFS = 'h12138;
endpackage
