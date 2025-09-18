// ============================================================================================== //
// Description  : register  map address definition package
// This file was generated with rust regmap generator:
//  * Date:  2025-09-18
//  * Tool_version: bb0db737792da6b81e69a039028c971af1627fe2
// ---------------------------------------------------------------------------------------------- //
//
// Should only be used in testbench to drive the register interface
// ============================================================================================== //
package hpu_regif_core_prc_1in3_pkg;
  localparam int ENTRY_PRC_1IN3_DUMMY_VAL0_OFS = 'h90000;
  localparam int ENTRY_PRC_1IN3_DUMMY_VAL1_OFS = 'h90004;
  localparam int ENTRY_PRC_1IN3_DUMMY_VAL2_OFS = 'h90008;
  localparam int ENTRY_PRC_1IN3_DUMMY_VAL3_OFS = 'h9000c;
  typedef struct packed {
    logic [(32-1):0] pbs;
   } status_1in3_error_t;
  localparam int STATUS_1IN3_ERROR_OFS = 'h90010;
  typedef struct packed {
    logic [(31-1):0] padding_1;
    logic [(1-1):0] avail;
   } ksk_avail_avail_t;
  localparam int KSK_AVAIL_AVAIL_OFS = 'h91000;
  typedef struct packed {
    logic [(1-1):0] done;
    logic [(30-1):0] padding_1;
    logic [(1-1):0] request;
   } ksk_avail_reset_t;
  localparam int KSK_AVAIL_RESET_OFS = 'h91004;
  typedef struct packed {
    logic [(1-1):0] ks_loop_c;
    logic [(15-1):0] ks_loop;
    logic [(1-1):0] br_loop_c;
    logic [(15-1):0] br_loop;
   } runtime_1in3_pep_cmux_loop_t;
  localparam int RUNTIME_1IN3_PEP_CMUX_LOOP_OFS = 'h92000;
  typedef struct packed {
    logic [(8-1):0] ldb_pt;
    logic [(8-1):0] ldg_pt;
    logic [(8-1):0] pool_wp;
    logic [(8-1):0] pool_rp;
   } runtime_1in3_pep_pointer_0_t;
  localparam int RUNTIME_1IN3_PEP_POINTER_0_OFS = 'h92004;
  typedef struct packed {
    logic [(8-1):0] ks_out_wp;
    logic [(8-1):0] ks_out_rp;
    logic [(8-1):0] ks_in_wp;
    logic [(8-1):0] ks_in_rp;
   } runtime_1in3_pep_pointer_1_t;
  localparam int RUNTIME_1IN3_PEP_POINTER_1_OFS = 'h92008;
  typedef struct packed {
    logic [(16-1):0] ipip_flush_last_pbs_in_loop;
    logic [(8-1):0] pbs_in_wp;
    logic [(8-1):0] pbs_in_rp;
   } runtime_1in3_pep_pointer_2_t;
  localparam int RUNTIME_1IN3_PEP_POINTER_2_OFS = 'h9200c;
  localparam int RUNTIME_1IN3_ISC_LATEST_INSTRUCTION_0_OFS = 'h92010;
  localparam int RUNTIME_1IN3_ISC_LATEST_INSTRUCTION_1_OFS = 'h92014;
  localparam int RUNTIME_1IN3_ISC_LATEST_INSTRUCTION_2_OFS = 'h92018;
  localparam int RUNTIME_1IN3_ISC_LATEST_INSTRUCTION_3_OFS = 'h9201c;
  localparam int RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_CNT_OFS = 'h92020;
  localparam int RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FLUSH_CNT_OFS = 'h92024;
  localparam int RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_TIMEOUT_CNT_OFS = 'h92028;
  localparam int RUNTIME_1IN3_PEP_SEQ_BPIP_WAITING_BATCH_CNT_OFS = 'h9202c;
  localparam int RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_1_OFS = 'h92030;
  localparam int RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_2_OFS = 'h92034;
  localparam int RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_3_OFS = 'h92038;
  localparam int RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_4_OFS = 'h9203c;
  localparam int RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_5_OFS = 'h92040;
  localparam int RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_6_OFS = 'h92044;
  localparam int RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_7_OFS = 'h92048;
  localparam int RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_8_OFS = 'h9204c;
  localparam int RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_9_OFS = 'h92050;
  localparam int RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_10_OFS = 'h92054;
  localparam int RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_11_OFS = 'h92058;
  localparam int RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_12_OFS = 'h9205c;
  localparam int RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_13_OFS = 'h92060;
  localparam int RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_14_OFS = 'h92064;
  localparam int RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_15_OFS = 'h92068;
  localparam int RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_16_OFS = 'h9206c;
  localparam int RUNTIME_1IN3_PEP_SEQ_LD_ACK_CNT_OFS = 'h92070;
  localparam int RUNTIME_1IN3_PEP_SEQ_CMUX_NOT_FULL_BATCH_CNT_OFS = 'h92074;
  localparam int RUNTIME_1IN3_PEP_SEQ_IPIP_FLUSH_CNT_OFS = 'h92078;
  localparam int RUNTIME_1IN3_PEP_LDB_RCP_DUR_OFS = 'h9207c;
  localparam int RUNTIME_1IN3_PEP_LDG_REQ_DUR_OFS = 'h92080;
  localparam int RUNTIME_1IN3_PEP_LDG_RCP_DUR_OFS = 'h92084;
  localparam int RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC0_OFS = 'h92088;
  localparam int RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC1_OFS = 'h9208c;
  localparam int RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC2_OFS = 'h92090;
  localparam int RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC3_OFS = 'h92094;
  localparam int RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC4_OFS = 'h92098;
  localparam int RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC5_OFS = 'h9209c;
  localparam int RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC6_OFS = 'h920a0;
  localparam int RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC7_OFS = 'h920a4;
  localparam int RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC8_OFS = 'h920a8;
  localparam int RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC9_OFS = 'h920ac;
  localparam int RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC10_OFS = 'h920b0;
  localparam int RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC11_OFS = 'h920b4;
  localparam int RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC12_OFS = 'h920b8;
  localparam int RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC13_OFS = 'h920bc;
  localparam int RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC14_OFS = 'h920c0;
  localparam int RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC15_OFS = 'h920c4;
  localparam int RUNTIME_1IN3_PEP_MMACC_SXT_RCP_DUR_OFS = 'h920c8;
  localparam int RUNTIME_1IN3_PEP_MMACC_SXT_REQ_DUR_OFS = 'h920cc;
  localparam int RUNTIME_1IN3_PEP_MMACC_SXT_CMD_WAIT_B_DUR_OFS = 'h920d0;
  localparam int RUNTIME_1IN3_PEP_INST_CNT_OFS = 'h920d4;
  localparam int RUNTIME_1IN3_PEP_ACK_CNT_OFS = 'h920d8;
  localparam int RUNTIME_1IN3_PEM_LOAD_INST_CNT_OFS = 'h920dc;
  localparam int RUNTIME_1IN3_PEM_LOAD_ACK_CNT_OFS = 'h920e0;
  localparam int RUNTIME_1IN3_PEM_STORE_INST_CNT_OFS = 'h920e4;
  localparam int RUNTIME_1IN3_PEM_STORE_ACK_CNT_OFS = 'h920e8;
  localparam int RUNTIME_1IN3_PEA_INST_CNT_OFS = 'h920ec;
  localparam int RUNTIME_1IN3_PEA_ACK_CNT_OFS = 'h920f0;
  localparam int RUNTIME_1IN3_ISC_INST_CNT_OFS = 'h920f4;
  localparam int RUNTIME_1IN3_ISC_ACK_CNT_OFS = 'h920f8;
  localparam int RUNTIME_1IN3_PEM_LOAD_INFO_0_PC0_0_OFS = 'h920fc;
  localparam int RUNTIME_1IN3_PEM_LOAD_INFO_0_PC0_1_OFS = 'h92100;
  localparam int RUNTIME_1IN3_PEM_LOAD_INFO_0_PC0_2_OFS = 'h92104;
  localparam int RUNTIME_1IN3_PEM_LOAD_INFO_0_PC0_3_OFS = 'h92108;
  localparam int RUNTIME_1IN3_PEM_LOAD_INFO_0_PC1_0_OFS = 'h9210c;
  localparam int RUNTIME_1IN3_PEM_LOAD_INFO_0_PC1_1_OFS = 'h92110;
  localparam int RUNTIME_1IN3_PEM_LOAD_INFO_0_PC1_2_OFS = 'h92114;
  localparam int RUNTIME_1IN3_PEM_LOAD_INFO_0_PC1_3_OFS = 'h92118;
  localparam int RUNTIME_1IN3_PEM_LOAD_INFO_1_PC0_LSB_OFS = 'h9211c;
  localparam int RUNTIME_1IN3_PEM_LOAD_INFO_1_PC0_MSB_OFS = 'h92120;
  localparam int RUNTIME_1IN3_PEM_LOAD_INFO_1_PC1_LSB_OFS = 'h92124;
  localparam int RUNTIME_1IN3_PEM_LOAD_INFO_1_PC1_MSB_OFS = 'h92128;
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
  localparam int RUNTIME_1IN3_PEM_STORE_INFO_0_OFS = 'h9212c;
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
  localparam int RUNTIME_1IN3_PEM_STORE_INFO_1_OFS = 'h92130;
  typedef struct packed {
    logic [(16-1):0] brsp_bresp_cnt;
    logic [(16-1):0] c0_free_loc_cnt;
   } runtime_1in3_pem_store_info_2_t;
  localparam int RUNTIME_1IN3_PEM_STORE_INFO_2_OFS = 'h92134;
  typedef struct packed {
    logic [(8-1):0] padding_24;
    logic [(8-1):0] c0_cmd_cnt;
    logic [(16-1):0] brsp_ack_seen;
   } runtime_1in3_pem_store_info_3_t;
  localparam int RUNTIME_1IN3_PEM_STORE_INFO_3_OFS = 'h92138;
endpackage
