// ============================================================================================== //
// Description  : Axi4-lite register bank
// This file was generated with rust regmap generator:
//  * Date:  2025-07-17
//  * Tool_version: bb0db737792da6b81e69a039028c971af1627fe2
// ---------------------------------------------------------------------------------------------- //
// xR[n]W[na]
// |-> who is in charge of the register update logic : u -> User
//                                                   : k -> Kernel (with an *_upd signal)
//                                                   : p -> Parameters (i.e. constant register)
//  | Read options
//  | [n] optional generate read notification (have a _rd_en)
//  | Write options
//  | [n] optional generate wr notification (have a _wr_en)
//
// Thus type of registers are:
// uRW  : Read-write
//      : Value provided by the host. The host can read it and write it.
// uW   : Write-only
//      : Value provided by the host. The host can only write it.
// uWn  : Write-only with notification
//      : Value provided by the host. The host can only write it.
// kR   : Read-only register
//      : Value provided by the RTL.
// kRn  : Read-only register with notification  (rd)
//      : Value provided by the RTL.
// kRWn : Read-only register with notification (wr)
//      : Value provided by the RTL. The host can read it. The write data is processed by the RTL.
// kRnWn: Read-only register with notification (rd/wr)
//      : Value provided by the RTL. The host can read it with notify. The write data is processed by the RTL.
// ============================================================================================== //
module hpu_regif_core_prc_1in3
import axi_if_common_param_pkg::*;
import axi_if_shell_axil_pkg::*;
import hpu_regif_core_prc_1in3_pkg::*;
#()(
  input  logic                           clk,
  input  logic                           s_rst_n,
  // Axi4 lite Slave Interface sAxi4
  input  logic [AXIL_ADD_W-1:0]         s_axil_awaddr,
  input  logic                          s_axil_awvalid,
  output logic                          s_axil_awready,
  input  logic [AXIL_DATA_W-1:0]        s_axil_wdata,
  input  logic                          s_axil_wvalid,
  output logic                          s_axil_wready,
  output logic [AXI4_RESP_W-1:0]        s_axil_bresp,
  output logic                          s_axil_bvalid,
  input  logic                          s_axil_bready,
  input  logic [AXIL_ADD_W-1:0]         s_axil_araddr,
  input  logic                          s_axil_arvalid,
  output logic                          s_axil_arready,
  output logic [AXIL_DATA_W-1:0]        s_axil_rdata,
  output logic [AXI4_RESP_W-1:0]        s_axil_rresp,
  output logic                          s_axil_rvalid,
  input  logic                          s_axil_rready,
  // Registered version of wdata
  output logic [AXIL_DATA_W-1:0]        r_axil_wdata
  // Register IO: status_1in3_error
    , output status_1in3_error_t r_status_1in3_error
        , input status_1in3_error_t r_status_1in3_error_upd
    , output logic r_status_1in3_error_wr_en
  // Register IO: ksk_avail_avail
    , output ksk_avail_avail_t r_ksk_avail_avail
  // Register IO: ksk_avail_reset
    , output ksk_avail_reset_t r_ksk_avail_reset
        , input ksk_avail_reset_t r_ksk_avail_reset_upd
    , output logic r_ksk_avail_reset_wr_en
  // Register IO: runtime_1in3_pep_cmux_loop
    , output runtime_1in3_pep_cmux_loop_t r_runtime_1in3_pep_cmux_loop
        , input runtime_1in3_pep_cmux_loop_t r_runtime_1in3_pep_cmux_loop_upd
  // Register IO: runtime_1in3_pep_pointer_0
    , output runtime_1in3_pep_pointer_0_t r_runtime_1in3_pep_pointer_0
        , input runtime_1in3_pep_pointer_0_t r_runtime_1in3_pep_pointer_0_upd
  // Register IO: runtime_1in3_pep_pointer_1
    , output runtime_1in3_pep_pointer_1_t r_runtime_1in3_pep_pointer_1
        , input runtime_1in3_pep_pointer_1_t r_runtime_1in3_pep_pointer_1_upd
  // Register IO: runtime_1in3_pep_pointer_2
    , output runtime_1in3_pep_pointer_2_t r_runtime_1in3_pep_pointer_2
        , input runtime_1in3_pep_pointer_2_t r_runtime_1in3_pep_pointer_2_upd
  // Register IO: runtime_1in3_isc_latest_instruction_0
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_isc_latest_instruction_0
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_isc_latest_instruction_0_upd
  // Register IO: runtime_1in3_isc_latest_instruction_1
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_isc_latest_instruction_1
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_isc_latest_instruction_1_upd
  // Register IO: runtime_1in3_isc_latest_instruction_2
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_isc_latest_instruction_2
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_isc_latest_instruction_2_upd
  // Register IO: runtime_1in3_isc_latest_instruction_3
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_isc_latest_instruction_3
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_isc_latest_instruction_3_upd
  // Register IO: runtime_1in3_pep_seq_bpip_batch_cnt
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_seq_bpip_batch_cnt
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_seq_bpip_batch_cnt_upd
    , output logic r_runtime_1in3_pep_seq_bpip_batch_cnt_wr_en
  // Register IO: runtime_1in3_pep_seq_bpip_batch_flush_cnt
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_seq_bpip_batch_flush_cnt
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_seq_bpip_batch_flush_cnt_upd
    , output logic r_runtime_1in3_pep_seq_bpip_batch_flush_cnt_wr_en
  // Register IO: runtime_1in3_pep_seq_bpip_batch_timeout_cnt
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_seq_bpip_batch_timeout_cnt
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_seq_bpip_batch_timeout_cnt_upd
    , output logic r_runtime_1in3_pep_seq_bpip_batch_timeout_cnt_wr_en
  // Register IO: runtime_1in3_pep_seq_bpip_waiting_batch_cnt
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_seq_bpip_waiting_batch_cnt
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_seq_bpip_waiting_batch_cnt_upd
    , output logic r_runtime_1in3_pep_seq_bpip_waiting_batch_cnt_wr_en
  // Register IO: runtime_1in3_pep_seq_bpip_batch_filling_cnt_1
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_1
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_1_upd
    , output logic r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_1_wr_en
  // Register IO: runtime_1in3_pep_seq_bpip_batch_filling_cnt_2
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_2
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_2_upd
    , output logic r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_2_wr_en
  // Register IO: runtime_1in3_pep_seq_bpip_batch_filling_cnt_3
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_3
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_3_upd
    , output logic r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_3_wr_en
  // Register IO: runtime_1in3_pep_seq_bpip_batch_filling_cnt_4
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_4
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_4_upd
    , output logic r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_4_wr_en
  // Register IO: runtime_1in3_pep_seq_bpip_batch_filling_cnt_5
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_5
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_5_upd
    , output logic r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_5_wr_en
  // Register IO: runtime_1in3_pep_seq_bpip_batch_filling_cnt_6
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_6
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_6_upd
    , output logic r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_6_wr_en
  // Register IO: runtime_1in3_pep_seq_bpip_batch_filling_cnt_7
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_7
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_7_upd
    , output logic r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_7_wr_en
  // Register IO: runtime_1in3_pep_seq_bpip_batch_filling_cnt_8
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_8
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_8_upd
    , output logic r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_8_wr_en
  // Register IO: runtime_1in3_pep_seq_bpip_batch_filling_cnt_9
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_9
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_9_upd
    , output logic r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_9_wr_en
  // Register IO: runtime_1in3_pep_seq_bpip_batch_filling_cnt_10
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_10
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_10_upd
    , output logic r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_10_wr_en
  // Register IO: runtime_1in3_pep_seq_bpip_batch_filling_cnt_11
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_11
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_11_upd
    , output logic r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_11_wr_en
  // Register IO: runtime_1in3_pep_seq_bpip_batch_filling_cnt_12
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_12
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_12_upd
    , output logic r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_12_wr_en
  // Register IO: runtime_1in3_pep_seq_bpip_batch_filling_cnt_13
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_13
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_13_upd
    , output logic r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_13_wr_en
  // Register IO: runtime_1in3_pep_seq_bpip_batch_filling_cnt_14
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_14
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_14_upd
    , output logic r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_14_wr_en
  // Register IO: runtime_1in3_pep_seq_bpip_batch_filling_cnt_15
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_15
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_15_upd
    , output logic r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_15_wr_en
  // Register IO: runtime_1in3_pep_seq_bpip_batch_filling_cnt_16
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_16
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_16_upd
    , output logic r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_16_wr_en
  // Register IO: runtime_1in3_pep_seq_ld_ack_cnt
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_seq_ld_ack_cnt
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_seq_ld_ack_cnt_upd
    , output logic r_runtime_1in3_pep_seq_ld_ack_cnt_wr_en
  // Register IO: runtime_1in3_pep_seq_cmux_not_full_batch_cnt
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_seq_cmux_not_full_batch_cnt
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_seq_cmux_not_full_batch_cnt_upd
    , output logic r_runtime_1in3_pep_seq_cmux_not_full_batch_cnt_wr_en
  // Register IO: runtime_1in3_pep_seq_ipip_flush_cnt
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_seq_ipip_flush_cnt
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_seq_ipip_flush_cnt_upd
    , output logic r_runtime_1in3_pep_seq_ipip_flush_cnt_wr_en
  // Register IO: runtime_1in3_pep_ldb_rcp_dur
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_ldb_rcp_dur
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_ldb_rcp_dur_upd
    , output logic r_runtime_1in3_pep_ldb_rcp_dur_wr_en
  // Register IO: runtime_1in3_pep_ldg_req_dur
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_ldg_req_dur
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_ldg_req_dur_upd
    , output logic r_runtime_1in3_pep_ldg_req_dur_wr_en
  // Register IO: runtime_1in3_pep_ldg_rcp_dur
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_ldg_rcp_dur
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_ldg_rcp_dur_upd
    , output logic r_runtime_1in3_pep_ldg_rcp_dur_wr_en
  // Register IO: runtime_1in3_pep_load_ksk_rcp_dur_pc0
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_load_ksk_rcp_dur_pc0
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_load_ksk_rcp_dur_pc0_upd
    , output logic r_runtime_1in3_pep_load_ksk_rcp_dur_pc0_wr_en
  // Register IO: runtime_1in3_pep_load_ksk_rcp_dur_pc1
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_load_ksk_rcp_dur_pc1
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_load_ksk_rcp_dur_pc1_upd
    , output logic r_runtime_1in3_pep_load_ksk_rcp_dur_pc1_wr_en
  // Register IO: runtime_1in3_pep_load_ksk_rcp_dur_pc2
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_load_ksk_rcp_dur_pc2
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_load_ksk_rcp_dur_pc2_upd
    , output logic r_runtime_1in3_pep_load_ksk_rcp_dur_pc2_wr_en
  // Register IO: runtime_1in3_pep_load_ksk_rcp_dur_pc3
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_load_ksk_rcp_dur_pc3
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_load_ksk_rcp_dur_pc3_upd
    , output logic r_runtime_1in3_pep_load_ksk_rcp_dur_pc3_wr_en
  // Register IO: runtime_1in3_pep_load_ksk_rcp_dur_pc4
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_load_ksk_rcp_dur_pc4
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_load_ksk_rcp_dur_pc4_upd
    , output logic r_runtime_1in3_pep_load_ksk_rcp_dur_pc4_wr_en
  // Register IO: runtime_1in3_pep_load_ksk_rcp_dur_pc5
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_load_ksk_rcp_dur_pc5
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_load_ksk_rcp_dur_pc5_upd
    , output logic r_runtime_1in3_pep_load_ksk_rcp_dur_pc5_wr_en
  // Register IO: runtime_1in3_pep_load_ksk_rcp_dur_pc6
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_load_ksk_rcp_dur_pc6
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_load_ksk_rcp_dur_pc6_upd
    , output logic r_runtime_1in3_pep_load_ksk_rcp_dur_pc6_wr_en
  // Register IO: runtime_1in3_pep_load_ksk_rcp_dur_pc7
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_load_ksk_rcp_dur_pc7
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_load_ksk_rcp_dur_pc7_upd
    , output logic r_runtime_1in3_pep_load_ksk_rcp_dur_pc7_wr_en
  // Register IO: runtime_1in3_pep_load_ksk_rcp_dur_pc8
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_load_ksk_rcp_dur_pc8
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_load_ksk_rcp_dur_pc8_upd
    , output logic r_runtime_1in3_pep_load_ksk_rcp_dur_pc8_wr_en
  // Register IO: runtime_1in3_pep_load_ksk_rcp_dur_pc9
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_load_ksk_rcp_dur_pc9
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_load_ksk_rcp_dur_pc9_upd
    , output logic r_runtime_1in3_pep_load_ksk_rcp_dur_pc9_wr_en
  // Register IO: runtime_1in3_pep_load_ksk_rcp_dur_pc10
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_load_ksk_rcp_dur_pc10
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_load_ksk_rcp_dur_pc10_upd
    , output logic r_runtime_1in3_pep_load_ksk_rcp_dur_pc10_wr_en
  // Register IO: runtime_1in3_pep_load_ksk_rcp_dur_pc11
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_load_ksk_rcp_dur_pc11
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_load_ksk_rcp_dur_pc11_upd
    , output logic r_runtime_1in3_pep_load_ksk_rcp_dur_pc11_wr_en
  // Register IO: runtime_1in3_pep_load_ksk_rcp_dur_pc12
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_load_ksk_rcp_dur_pc12
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_load_ksk_rcp_dur_pc12_upd
    , output logic r_runtime_1in3_pep_load_ksk_rcp_dur_pc12_wr_en
  // Register IO: runtime_1in3_pep_load_ksk_rcp_dur_pc13
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_load_ksk_rcp_dur_pc13
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_load_ksk_rcp_dur_pc13_upd
    , output logic r_runtime_1in3_pep_load_ksk_rcp_dur_pc13_wr_en
  // Register IO: runtime_1in3_pep_load_ksk_rcp_dur_pc14
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_load_ksk_rcp_dur_pc14
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_load_ksk_rcp_dur_pc14_upd
    , output logic r_runtime_1in3_pep_load_ksk_rcp_dur_pc14_wr_en
  // Register IO: runtime_1in3_pep_load_ksk_rcp_dur_pc15
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_load_ksk_rcp_dur_pc15
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_load_ksk_rcp_dur_pc15_upd
    , output logic r_runtime_1in3_pep_load_ksk_rcp_dur_pc15_wr_en
  // Register IO: runtime_1in3_pep_mmacc_sxt_rcp_dur
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_mmacc_sxt_rcp_dur
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_mmacc_sxt_rcp_dur_upd
    , output logic r_runtime_1in3_pep_mmacc_sxt_rcp_dur_wr_en
  // Register IO: runtime_1in3_pep_mmacc_sxt_req_dur
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_mmacc_sxt_req_dur
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_mmacc_sxt_req_dur_upd
    , output logic r_runtime_1in3_pep_mmacc_sxt_req_dur_wr_en
  // Register IO: runtime_1in3_pep_mmacc_sxt_cmd_wait_b_dur
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_mmacc_sxt_cmd_wait_b_dur
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_mmacc_sxt_cmd_wait_b_dur_upd
    , output logic r_runtime_1in3_pep_mmacc_sxt_cmd_wait_b_dur_wr_en
  // Register IO: runtime_1in3_pep_inst_cnt
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_inst_cnt
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_inst_cnt_upd
    , output logic r_runtime_1in3_pep_inst_cnt_wr_en
  // Register IO: runtime_1in3_pep_ack_cnt
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_ack_cnt
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pep_ack_cnt_upd
    , output logic r_runtime_1in3_pep_ack_cnt_wr_en
  // Register IO: runtime_1in3_pem_load_inst_cnt
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pem_load_inst_cnt
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pem_load_inst_cnt_upd
    , output logic r_runtime_1in3_pem_load_inst_cnt_wr_en
  // Register IO: runtime_1in3_pem_load_ack_cnt
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pem_load_ack_cnt
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pem_load_ack_cnt_upd
    , output logic r_runtime_1in3_pem_load_ack_cnt_wr_en
  // Register IO: runtime_1in3_pem_store_inst_cnt
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pem_store_inst_cnt
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pem_store_inst_cnt_upd
    , output logic r_runtime_1in3_pem_store_inst_cnt_wr_en
  // Register IO: runtime_1in3_pem_store_ack_cnt
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pem_store_ack_cnt
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pem_store_ack_cnt_upd
    , output logic r_runtime_1in3_pem_store_ack_cnt_wr_en
  // Register IO: runtime_1in3_pea_inst_cnt
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pea_inst_cnt
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pea_inst_cnt_upd
    , output logic r_runtime_1in3_pea_inst_cnt_wr_en
  // Register IO: runtime_1in3_pea_ack_cnt
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pea_ack_cnt
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pea_ack_cnt_upd
    , output logic r_runtime_1in3_pea_ack_cnt_wr_en
  // Register IO: runtime_1in3_isc_inst_cnt
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_isc_inst_cnt
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_isc_inst_cnt_upd
    , output logic r_runtime_1in3_isc_inst_cnt_wr_en
  // Register IO: runtime_1in3_isc_ack_cnt
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_isc_ack_cnt
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_isc_ack_cnt_upd
    , output logic r_runtime_1in3_isc_ack_cnt_wr_en
  // Register IO: runtime_1in3_pem_load_info_0_pc0_0
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pem_load_info_0_pc0_0
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pem_load_info_0_pc0_0_upd
  // Register IO: runtime_1in3_pem_load_info_0_pc0_1
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pem_load_info_0_pc0_1
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pem_load_info_0_pc0_1_upd
  // Register IO: runtime_1in3_pem_load_info_0_pc0_2
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pem_load_info_0_pc0_2
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pem_load_info_0_pc0_2_upd
  // Register IO: runtime_1in3_pem_load_info_0_pc0_3
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pem_load_info_0_pc0_3
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pem_load_info_0_pc0_3_upd
  // Register IO: runtime_1in3_pem_load_info_0_pc1_0
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pem_load_info_0_pc1_0
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pem_load_info_0_pc1_0_upd
  // Register IO: runtime_1in3_pem_load_info_0_pc1_1
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pem_load_info_0_pc1_1
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pem_load_info_0_pc1_1_upd
  // Register IO: runtime_1in3_pem_load_info_0_pc1_2
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pem_load_info_0_pc1_2
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pem_load_info_0_pc1_2_upd
  // Register IO: runtime_1in3_pem_load_info_0_pc1_3
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pem_load_info_0_pc1_3
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pem_load_info_0_pc1_3_upd
  // Register IO: runtime_1in3_pem_load_info_1_pc0_lsb
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pem_load_info_1_pc0_lsb
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pem_load_info_1_pc0_lsb_upd
  // Register IO: runtime_1in3_pem_load_info_1_pc0_msb
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pem_load_info_1_pc0_msb
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pem_load_info_1_pc0_msb_upd
  // Register IO: runtime_1in3_pem_load_info_1_pc1_lsb
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pem_load_info_1_pc1_lsb
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pem_load_info_1_pc1_lsb_upd
  // Register IO: runtime_1in3_pem_load_info_1_pc1_msb
    , output logic [REG_DATA_W-1: 0] r_runtime_1in3_pem_load_info_1_pc1_msb
        , input  logic [REG_DATA_W-1: 0] r_runtime_1in3_pem_load_info_1_pc1_msb_upd
  // Register IO: runtime_1in3_pem_store_info_0
    , output runtime_1in3_pem_store_info_0_t r_runtime_1in3_pem_store_info_0
        , input runtime_1in3_pem_store_info_0_t r_runtime_1in3_pem_store_info_0_upd
  // Register IO: runtime_1in3_pem_store_info_1
    , output runtime_1in3_pem_store_info_1_t r_runtime_1in3_pem_store_info_1
        , input runtime_1in3_pem_store_info_1_t r_runtime_1in3_pem_store_info_1_upd
  // Register IO: runtime_1in3_pem_store_info_2
    , output runtime_1in3_pem_store_info_2_t r_runtime_1in3_pem_store_info_2
        , input runtime_1in3_pem_store_info_2_t r_runtime_1in3_pem_store_info_2_upd
  // Register IO: runtime_1in3_pem_store_info_3
    , output runtime_1in3_pem_store_info_3_t r_runtime_1in3_pem_store_info_3
        , input runtime_1in3_pem_store_info_3_t r_runtime_1in3_pem_store_info_3_upd
);
// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int AXIL_ADD_OFS = 'h10000;
  localparam int AXIL_ADD_RANGE= 'h10000; // Should be a power of 2
  localparam int AXIL_ADD_RANGE_W = $clog2(AXIL_ADD_RANGE);
  localparam [AXIL_ADD_W-1:0] AXIL_ADD_RANGE_MASK = AXIL_ADD_W'(AXIL_ADD_RANGE - 1);
  localparam [AXIL_ADD_W-1:0] AXIL_ADD_OFS_MASK   = ~(AXIL_ADD_W'(AXIL_ADD_RANGE - 1));
// ============================================================================================== --
// axil management
// ============================================================================================== --
  logic                    axil_awready;
  logic                    axil_wready;
  logic [AXI4_RESP_W-1:0]  axil_bresp;
  logic                    axil_bvalid;
  logic                    axil_arready;
  logic [AXI4_RESP_W-1:0]  axil_rresp;
  logic [AXIL_DATA_W-1:0]  axil_rdata;
  logic                    axil_rvalid;
  logic                    axil_awreadyD;
  logic                    axil_wreadyD;
  logic [AXI4_RESP_W-1:0]  axil_brespD;
  logic                    axil_bvalidD;
  logic                    axil_arreadyD;
  logic [AXI4_RESP_W-1:0]  axil_rrespD;
  logic [AXIL_DATA_W-1:0]  axil_rdataD;
  logic                    axil_rvalidD;
  logic                    wr_en;
  logic [AXIL_ADD_W-1:0]   wr_add;
  logic [AXIL_DATA_W-1:0]  wr_data;
  logic                    rd_en;
  logic [AXIL_ADD_W-1:0]   rd_add;
  logic                    wr_enD;
  logic [AXIL_ADD_W-1:0]   wr_addD;
  logic [AXIL_DATA_W-1:0]  wr_dataD;
  logic                    rd_enD;
  logic [AXIL_ADD_W-1:0]   rd_addD;
  logic                    wr_en_okD;
  logic                    rd_en_okD;
  logic                    wr_en_ok;
  logic                    rd_en_ok;
  //== Check address
  // Answer all requests within [ADD_OFS -> ADD_OFS + RANGE[
  // Since RANGE is a power of 2, this could be done with masks.
  logic s_axil_wr_add_ok;
  logic s_axil_rd_add_ok;
  assign s_axil_wr_add_ok = (s_axil_awaddr & AXIL_ADD_OFS_MASK) == AXIL_ADD_OFS;
  assign s_axil_rd_add_ok = (s_axil_araddr & AXIL_ADD_OFS_MASK) == AXIL_ADD_OFS;
  //== Local read/write signals
  // Write when address and data are available.
  // Do not accept a new write request when the response
  // of previous request is still pending.
  // Since the ready is sent 1 cycle after the valid,
  // mask the cycle when the ready is r
  assign wr_enD   = (s_axil_awvalid & s_axil_wvalid
                     & ~(s_axil_awready | s_axil_wready)
                     & ~(s_axil_bvalid & ~s_axil_bready));
  assign wr_en_okD = wr_enD & s_axil_wr_add_ok;
  assign wr_addD  = s_axil_awaddr;
  assign wr_dataD = s_axil_wdata;
  // Answer to read request 1 cycle after, when there is no pending read data.
  // Therefore, mask the rd_en during the 2nd cycle.
  assign rd_enD   = (s_axil_arvalid
                    & ~s_axil_arready
                    & ~(s_axil_rvalid & ~s_axil_rready));
  assign rd_en_okD = rd_enD & s_axil_rd_add_ok;
  assign rd_addD   = s_axil_araddr;
  //== AXIL write ready
  assign axil_awreadyD = wr_enD;
  assign axil_wreadyD  = wr_enD;
  //== AXIL read address ready
  assign axil_arreadyD = rd_enD;
  //== AXIL write resp
  assign axil_bvalidD    = wr_en         ? 1'b1:
                           s_axil_bready ? 1'b0 : axil_bvalid;
  assign axil_brespD     = wr_en         ? wr_en_ok ? AXI4_OKAY : AXI4_SLVERR:
                           s_axil_bready ? 1'b0 : axil_bresp;
  //== AXIL read resp
  assign axil_rvalidD    = rd_en         ? 1'b1 :
                           s_axil_rready ? 1'b0 : axil_rvalid;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      axil_awready <= 1'b0;
      axil_wready  <= 1'b0;
      axil_bresp   <= '0;
      axil_bvalid  <= 1'b0;
      axil_arready <= 1'b0;
      axil_rdata   <= '0;
      axil_rresp   <= '0;
      axil_rvalid  <= 1'b0;
      wr_en        <= 1'b0;
      rd_en        <= 1'b0;
      wr_en_ok     <= 1'b0;
      rd_en_ok     <= 1'b0;
    end
    else begin
      axil_awready <= axil_awreadyD;
      axil_wready  <= axil_wreadyD;
      axil_bresp   <= axil_brespD;
      axil_bvalid  <= axil_bvalidD;
      axil_arready <= axil_arreadyD;
      axil_rdata   <= axil_rdataD;
      axil_rresp   <= axil_rrespD;
      axil_rvalid  <= axil_rvalidD;
      wr_en         <= wr_enD;
      rd_en         <= rd_enD;
      wr_en_ok      <= wr_en_okD;
      rd_en_ok      <= rd_en_okD;
    end
  end
  always_ff @(posedge clk) begin
    wr_add  <= wr_addD;
    rd_add  <= rd_addD;
    wr_data <= wr_dataD;
  end
  //= Assignment
  assign s_axil_awready = axil_awready;
  assign s_axil_wready  = axil_wready;
  assign s_axil_bresp   = axil_bresp;
  assign s_axil_bvalid  = axil_bvalid;
  assign s_axil_arready = axil_arready;
  assign s_axil_rresp   = axil_rresp;
  assign s_axil_rdata   = axil_rdata;
  assign s_axil_rvalid  = axil_rvalid;
  assign r_axil_wdata   = wr_data;
// ============================================================================================== --
// Default value signals
// ============================================================================================== --
//-- Default entry_prc_1in3_dummy_val0
  logic [REG_DATA_W-1:0]entry_prc_1in3_dummy_val0_default;
  assign entry_prc_1in3_dummy_val0_default = 'h2020202;
//-- Default entry_prc_1in3_dummy_val1
  logic [REG_DATA_W-1:0]entry_prc_1in3_dummy_val1_default;
  assign entry_prc_1in3_dummy_val1_default = 'h12121212;
//-- Default entry_prc_1in3_dummy_val2
  logic [REG_DATA_W-1:0]entry_prc_1in3_dummy_val2_default;
  assign entry_prc_1in3_dummy_val2_default = 'h22222222;
//-- Default entry_prc_1in3_dummy_val3
  logic [REG_DATA_W-1:0]entry_prc_1in3_dummy_val3_default;
  assign entry_prc_1in3_dummy_val3_default = 'h32323232;
//-- Default status_1in3_error
  status_1in3_error_t status_1in3_error_default;
  always_comb begin
    status_1in3_error_default = 'h0;
    status_1in3_error_default.pbs = 'h0;
  end
//-- Default ksk_avail_avail
  ksk_avail_avail_t ksk_avail_avail_default;
  always_comb begin
    ksk_avail_avail_default = 'h0;
    ksk_avail_avail_default.avail = 'h0;
  end
//-- Default ksk_avail_reset
  ksk_avail_reset_t ksk_avail_reset_default;
  always_comb begin
    ksk_avail_reset_default = 'h0;
    ksk_avail_reset_default.request = 'h0;
    ksk_avail_reset_default.done = 'h0;
  end
//-- Default runtime_1in3_pep_cmux_loop
  runtime_1in3_pep_cmux_loop_t runtime_1in3_pep_cmux_loop_default;
  always_comb begin
    runtime_1in3_pep_cmux_loop_default = 'h0;
    runtime_1in3_pep_cmux_loop_default.br_loop = 'h0;
    runtime_1in3_pep_cmux_loop_default.br_loop_c = 'h0;
    runtime_1in3_pep_cmux_loop_default.ks_loop = 'h0;
    runtime_1in3_pep_cmux_loop_default.ks_loop_c = 'h0;
  end
//-- Default runtime_1in3_pep_pointer_0
  runtime_1in3_pep_pointer_0_t runtime_1in3_pep_pointer_0_default;
  always_comb begin
    runtime_1in3_pep_pointer_0_default = 'h0;
    runtime_1in3_pep_pointer_0_default.pool_rp = 'h0;
    runtime_1in3_pep_pointer_0_default.pool_wp = 'h0;
    runtime_1in3_pep_pointer_0_default.ldg_pt = 'h0;
    runtime_1in3_pep_pointer_0_default.ldb_pt = 'h0;
  end
//-- Default runtime_1in3_pep_pointer_1
  runtime_1in3_pep_pointer_1_t runtime_1in3_pep_pointer_1_default;
  always_comb begin
    runtime_1in3_pep_pointer_1_default = 'h0;
    runtime_1in3_pep_pointer_1_default.ks_in_rp = 'h0;
    runtime_1in3_pep_pointer_1_default.ks_in_wp = 'h0;
    runtime_1in3_pep_pointer_1_default.ks_out_rp = 'h0;
    runtime_1in3_pep_pointer_1_default.ks_out_wp = 'h0;
  end
//-- Default runtime_1in3_pep_pointer_2
  runtime_1in3_pep_pointer_2_t runtime_1in3_pep_pointer_2_default;
  always_comb begin
    runtime_1in3_pep_pointer_2_default = 'h0;
    runtime_1in3_pep_pointer_2_default.pbs_in_rp = 'h0;
    runtime_1in3_pep_pointer_2_default.pbs_in_wp = 'h0;
    runtime_1in3_pep_pointer_2_default.ipip_flush_last_pbs_in_loop = 'h0;
  end
//-- Default runtime_1in3_isc_latest_instruction_0
  logic [REG_DATA_W-1:0]runtime_1in3_isc_latest_instruction_0_default;
  assign runtime_1in3_isc_latest_instruction_0_default = 'h0;
//-- Default runtime_1in3_isc_latest_instruction_1
  logic [REG_DATA_W-1:0]runtime_1in3_isc_latest_instruction_1_default;
  assign runtime_1in3_isc_latest_instruction_1_default = 'h0;
//-- Default runtime_1in3_isc_latest_instruction_2
  logic [REG_DATA_W-1:0]runtime_1in3_isc_latest_instruction_2_default;
  assign runtime_1in3_isc_latest_instruction_2_default = 'h0;
//-- Default runtime_1in3_isc_latest_instruction_3
  logic [REG_DATA_W-1:0]runtime_1in3_isc_latest_instruction_3_default;
  assign runtime_1in3_isc_latest_instruction_3_default = 'h0;
//-- Default runtime_1in3_pep_seq_bpip_batch_cnt
  logic [REG_DATA_W-1:0]runtime_1in3_pep_seq_bpip_batch_cnt_default;
  assign runtime_1in3_pep_seq_bpip_batch_cnt_default = 'h0;
//-- Default runtime_1in3_pep_seq_bpip_batch_flush_cnt
  logic [REG_DATA_W-1:0]runtime_1in3_pep_seq_bpip_batch_flush_cnt_default;
  assign runtime_1in3_pep_seq_bpip_batch_flush_cnt_default = 'h0;
//-- Default runtime_1in3_pep_seq_bpip_batch_timeout_cnt
  logic [REG_DATA_W-1:0]runtime_1in3_pep_seq_bpip_batch_timeout_cnt_default;
  assign runtime_1in3_pep_seq_bpip_batch_timeout_cnt_default = 'h0;
//-- Default runtime_1in3_pep_seq_bpip_waiting_batch_cnt
  logic [REG_DATA_W-1:0]runtime_1in3_pep_seq_bpip_waiting_batch_cnt_default;
  assign runtime_1in3_pep_seq_bpip_waiting_batch_cnt_default = 'h0;
//-- Default runtime_1in3_pep_seq_bpip_batch_filling_cnt_1
  logic [REG_DATA_W-1:0]runtime_1in3_pep_seq_bpip_batch_filling_cnt_1_default;
  assign runtime_1in3_pep_seq_bpip_batch_filling_cnt_1_default = 'h0;
//-- Default runtime_1in3_pep_seq_bpip_batch_filling_cnt_2
  logic [REG_DATA_W-1:0]runtime_1in3_pep_seq_bpip_batch_filling_cnt_2_default;
  assign runtime_1in3_pep_seq_bpip_batch_filling_cnt_2_default = 'h0;
//-- Default runtime_1in3_pep_seq_bpip_batch_filling_cnt_3
  logic [REG_DATA_W-1:0]runtime_1in3_pep_seq_bpip_batch_filling_cnt_3_default;
  assign runtime_1in3_pep_seq_bpip_batch_filling_cnt_3_default = 'h0;
//-- Default runtime_1in3_pep_seq_bpip_batch_filling_cnt_4
  logic [REG_DATA_W-1:0]runtime_1in3_pep_seq_bpip_batch_filling_cnt_4_default;
  assign runtime_1in3_pep_seq_bpip_batch_filling_cnt_4_default = 'h0;
//-- Default runtime_1in3_pep_seq_bpip_batch_filling_cnt_5
  logic [REG_DATA_W-1:0]runtime_1in3_pep_seq_bpip_batch_filling_cnt_5_default;
  assign runtime_1in3_pep_seq_bpip_batch_filling_cnt_5_default = 'h0;
//-- Default runtime_1in3_pep_seq_bpip_batch_filling_cnt_6
  logic [REG_DATA_W-1:0]runtime_1in3_pep_seq_bpip_batch_filling_cnt_6_default;
  assign runtime_1in3_pep_seq_bpip_batch_filling_cnt_6_default = 'h0;
//-- Default runtime_1in3_pep_seq_bpip_batch_filling_cnt_7
  logic [REG_DATA_W-1:0]runtime_1in3_pep_seq_bpip_batch_filling_cnt_7_default;
  assign runtime_1in3_pep_seq_bpip_batch_filling_cnt_7_default = 'h0;
//-- Default runtime_1in3_pep_seq_bpip_batch_filling_cnt_8
  logic [REG_DATA_W-1:0]runtime_1in3_pep_seq_bpip_batch_filling_cnt_8_default;
  assign runtime_1in3_pep_seq_bpip_batch_filling_cnt_8_default = 'h0;
//-- Default runtime_1in3_pep_seq_bpip_batch_filling_cnt_9
  logic [REG_DATA_W-1:0]runtime_1in3_pep_seq_bpip_batch_filling_cnt_9_default;
  assign runtime_1in3_pep_seq_bpip_batch_filling_cnt_9_default = 'h0;
//-- Default runtime_1in3_pep_seq_bpip_batch_filling_cnt_10
  logic [REG_DATA_W-1:0]runtime_1in3_pep_seq_bpip_batch_filling_cnt_10_default;
  assign runtime_1in3_pep_seq_bpip_batch_filling_cnt_10_default = 'h0;
//-- Default runtime_1in3_pep_seq_bpip_batch_filling_cnt_11
  logic [REG_DATA_W-1:0]runtime_1in3_pep_seq_bpip_batch_filling_cnt_11_default;
  assign runtime_1in3_pep_seq_bpip_batch_filling_cnt_11_default = 'h0;
//-- Default runtime_1in3_pep_seq_bpip_batch_filling_cnt_12
  logic [REG_DATA_W-1:0]runtime_1in3_pep_seq_bpip_batch_filling_cnt_12_default;
  assign runtime_1in3_pep_seq_bpip_batch_filling_cnt_12_default = 'h0;
//-- Default runtime_1in3_pep_seq_bpip_batch_filling_cnt_13
  logic [REG_DATA_W-1:0]runtime_1in3_pep_seq_bpip_batch_filling_cnt_13_default;
  assign runtime_1in3_pep_seq_bpip_batch_filling_cnt_13_default = 'h0;
//-- Default runtime_1in3_pep_seq_bpip_batch_filling_cnt_14
  logic [REG_DATA_W-1:0]runtime_1in3_pep_seq_bpip_batch_filling_cnt_14_default;
  assign runtime_1in3_pep_seq_bpip_batch_filling_cnt_14_default = 'h0;
//-- Default runtime_1in3_pep_seq_bpip_batch_filling_cnt_15
  logic [REG_DATA_W-1:0]runtime_1in3_pep_seq_bpip_batch_filling_cnt_15_default;
  assign runtime_1in3_pep_seq_bpip_batch_filling_cnt_15_default = 'h0;
//-- Default runtime_1in3_pep_seq_bpip_batch_filling_cnt_16
  logic [REG_DATA_W-1:0]runtime_1in3_pep_seq_bpip_batch_filling_cnt_16_default;
  assign runtime_1in3_pep_seq_bpip_batch_filling_cnt_16_default = 'h0;
//-- Default runtime_1in3_pep_seq_ld_ack_cnt
  logic [REG_DATA_W-1:0]runtime_1in3_pep_seq_ld_ack_cnt_default;
  assign runtime_1in3_pep_seq_ld_ack_cnt_default = 'h0;
//-- Default runtime_1in3_pep_seq_cmux_not_full_batch_cnt
  logic [REG_DATA_W-1:0]runtime_1in3_pep_seq_cmux_not_full_batch_cnt_default;
  assign runtime_1in3_pep_seq_cmux_not_full_batch_cnt_default = 'h0;
//-- Default runtime_1in3_pep_seq_ipip_flush_cnt
  logic [REG_DATA_W-1:0]runtime_1in3_pep_seq_ipip_flush_cnt_default;
  assign runtime_1in3_pep_seq_ipip_flush_cnt_default = 'h0;
//-- Default runtime_1in3_pep_ldb_rcp_dur
  logic [REG_DATA_W-1:0]runtime_1in3_pep_ldb_rcp_dur_default;
  assign runtime_1in3_pep_ldb_rcp_dur_default = 'h0;
//-- Default runtime_1in3_pep_ldg_req_dur
  logic [REG_DATA_W-1:0]runtime_1in3_pep_ldg_req_dur_default;
  assign runtime_1in3_pep_ldg_req_dur_default = 'h0;
//-- Default runtime_1in3_pep_ldg_rcp_dur
  logic [REG_DATA_W-1:0]runtime_1in3_pep_ldg_rcp_dur_default;
  assign runtime_1in3_pep_ldg_rcp_dur_default = 'h0;
//-- Default runtime_1in3_pep_load_ksk_rcp_dur_pc0
  logic [REG_DATA_W-1:0]runtime_1in3_pep_load_ksk_rcp_dur_pc0_default;
  assign runtime_1in3_pep_load_ksk_rcp_dur_pc0_default = 'h0;
//-- Default runtime_1in3_pep_load_ksk_rcp_dur_pc1
  logic [REG_DATA_W-1:0]runtime_1in3_pep_load_ksk_rcp_dur_pc1_default;
  assign runtime_1in3_pep_load_ksk_rcp_dur_pc1_default = 'h0;
//-- Default runtime_1in3_pep_load_ksk_rcp_dur_pc2
  logic [REG_DATA_W-1:0]runtime_1in3_pep_load_ksk_rcp_dur_pc2_default;
  assign runtime_1in3_pep_load_ksk_rcp_dur_pc2_default = 'h0;
//-- Default runtime_1in3_pep_load_ksk_rcp_dur_pc3
  logic [REG_DATA_W-1:0]runtime_1in3_pep_load_ksk_rcp_dur_pc3_default;
  assign runtime_1in3_pep_load_ksk_rcp_dur_pc3_default = 'h0;
//-- Default runtime_1in3_pep_load_ksk_rcp_dur_pc4
  logic [REG_DATA_W-1:0]runtime_1in3_pep_load_ksk_rcp_dur_pc4_default;
  assign runtime_1in3_pep_load_ksk_rcp_dur_pc4_default = 'h0;
//-- Default runtime_1in3_pep_load_ksk_rcp_dur_pc5
  logic [REG_DATA_W-1:0]runtime_1in3_pep_load_ksk_rcp_dur_pc5_default;
  assign runtime_1in3_pep_load_ksk_rcp_dur_pc5_default = 'h0;
//-- Default runtime_1in3_pep_load_ksk_rcp_dur_pc6
  logic [REG_DATA_W-1:0]runtime_1in3_pep_load_ksk_rcp_dur_pc6_default;
  assign runtime_1in3_pep_load_ksk_rcp_dur_pc6_default = 'h0;
//-- Default runtime_1in3_pep_load_ksk_rcp_dur_pc7
  logic [REG_DATA_W-1:0]runtime_1in3_pep_load_ksk_rcp_dur_pc7_default;
  assign runtime_1in3_pep_load_ksk_rcp_dur_pc7_default = 'h0;
//-- Default runtime_1in3_pep_load_ksk_rcp_dur_pc8
  logic [REG_DATA_W-1:0]runtime_1in3_pep_load_ksk_rcp_dur_pc8_default;
  assign runtime_1in3_pep_load_ksk_rcp_dur_pc8_default = 'h0;
//-- Default runtime_1in3_pep_load_ksk_rcp_dur_pc9
  logic [REG_DATA_W-1:0]runtime_1in3_pep_load_ksk_rcp_dur_pc9_default;
  assign runtime_1in3_pep_load_ksk_rcp_dur_pc9_default = 'h0;
//-- Default runtime_1in3_pep_load_ksk_rcp_dur_pc10
  logic [REG_DATA_W-1:0]runtime_1in3_pep_load_ksk_rcp_dur_pc10_default;
  assign runtime_1in3_pep_load_ksk_rcp_dur_pc10_default = 'h0;
//-- Default runtime_1in3_pep_load_ksk_rcp_dur_pc11
  logic [REG_DATA_W-1:0]runtime_1in3_pep_load_ksk_rcp_dur_pc11_default;
  assign runtime_1in3_pep_load_ksk_rcp_dur_pc11_default = 'h0;
//-- Default runtime_1in3_pep_load_ksk_rcp_dur_pc12
  logic [REG_DATA_W-1:0]runtime_1in3_pep_load_ksk_rcp_dur_pc12_default;
  assign runtime_1in3_pep_load_ksk_rcp_dur_pc12_default = 'h0;
//-- Default runtime_1in3_pep_load_ksk_rcp_dur_pc13
  logic [REG_DATA_W-1:0]runtime_1in3_pep_load_ksk_rcp_dur_pc13_default;
  assign runtime_1in3_pep_load_ksk_rcp_dur_pc13_default = 'h0;
//-- Default runtime_1in3_pep_load_ksk_rcp_dur_pc14
  logic [REG_DATA_W-1:0]runtime_1in3_pep_load_ksk_rcp_dur_pc14_default;
  assign runtime_1in3_pep_load_ksk_rcp_dur_pc14_default = 'h0;
//-- Default runtime_1in3_pep_load_ksk_rcp_dur_pc15
  logic [REG_DATA_W-1:0]runtime_1in3_pep_load_ksk_rcp_dur_pc15_default;
  assign runtime_1in3_pep_load_ksk_rcp_dur_pc15_default = 'h0;
//-- Default runtime_1in3_pep_mmacc_sxt_rcp_dur
  logic [REG_DATA_W-1:0]runtime_1in3_pep_mmacc_sxt_rcp_dur_default;
  assign runtime_1in3_pep_mmacc_sxt_rcp_dur_default = 'h0;
//-- Default runtime_1in3_pep_mmacc_sxt_req_dur
  logic [REG_DATA_W-1:0]runtime_1in3_pep_mmacc_sxt_req_dur_default;
  assign runtime_1in3_pep_mmacc_sxt_req_dur_default = 'h0;
//-- Default runtime_1in3_pep_mmacc_sxt_cmd_wait_b_dur
  logic [REG_DATA_W-1:0]runtime_1in3_pep_mmacc_sxt_cmd_wait_b_dur_default;
  assign runtime_1in3_pep_mmacc_sxt_cmd_wait_b_dur_default = 'h0;
//-- Default runtime_1in3_pep_inst_cnt
  logic [REG_DATA_W-1:0]runtime_1in3_pep_inst_cnt_default;
  assign runtime_1in3_pep_inst_cnt_default = 'h0;
//-- Default runtime_1in3_pep_ack_cnt
  logic [REG_DATA_W-1:0]runtime_1in3_pep_ack_cnt_default;
  assign runtime_1in3_pep_ack_cnt_default = 'h0;
//-- Default runtime_1in3_pem_load_inst_cnt
  logic [REG_DATA_W-1:0]runtime_1in3_pem_load_inst_cnt_default;
  assign runtime_1in3_pem_load_inst_cnt_default = 'h0;
//-- Default runtime_1in3_pem_load_ack_cnt
  logic [REG_DATA_W-1:0]runtime_1in3_pem_load_ack_cnt_default;
  assign runtime_1in3_pem_load_ack_cnt_default = 'h0;
//-- Default runtime_1in3_pem_store_inst_cnt
  logic [REG_DATA_W-1:0]runtime_1in3_pem_store_inst_cnt_default;
  assign runtime_1in3_pem_store_inst_cnt_default = 'h0;
//-- Default runtime_1in3_pem_store_ack_cnt
  logic [REG_DATA_W-1:0]runtime_1in3_pem_store_ack_cnt_default;
  assign runtime_1in3_pem_store_ack_cnt_default = 'h0;
//-- Default runtime_1in3_pea_inst_cnt
  logic [REG_DATA_W-1:0]runtime_1in3_pea_inst_cnt_default;
  assign runtime_1in3_pea_inst_cnt_default = 'h0;
//-- Default runtime_1in3_pea_ack_cnt
  logic [REG_DATA_W-1:0]runtime_1in3_pea_ack_cnt_default;
  assign runtime_1in3_pea_ack_cnt_default = 'h0;
//-- Default runtime_1in3_isc_inst_cnt
  logic [REG_DATA_W-1:0]runtime_1in3_isc_inst_cnt_default;
  assign runtime_1in3_isc_inst_cnt_default = 'h0;
//-- Default runtime_1in3_isc_ack_cnt
  logic [REG_DATA_W-1:0]runtime_1in3_isc_ack_cnt_default;
  assign runtime_1in3_isc_ack_cnt_default = 'h0;
//-- Default runtime_1in3_pem_load_info_0_pc0_0
  logic [REG_DATA_W-1:0]runtime_1in3_pem_load_info_0_pc0_0_default;
  assign runtime_1in3_pem_load_info_0_pc0_0_default = 'h0;
//-- Default runtime_1in3_pem_load_info_0_pc0_1
  logic [REG_DATA_W-1:0]runtime_1in3_pem_load_info_0_pc0_1_default;
  assign runtime_1in3_pem_load_info_0_pc0_1_default = 'h0;
//-- Default runtime_1in3_pem_load_info_0_pc0_2
  logic [REG_DATA_W-1:0]runtime_1in3_pem_load_info_0_pc0_2_default;
  assign runtime_1in3_pem_load_info_0_pc0_2_default = 'h0;
//-- Default runtime_1in3_pem_load_info_0_pc0_3
  logic [REG_DATA_W-1:0]runtime_1in3_pem_load_info_0_pc0_3_default;
  assign runtime_1in3_pem_load_info_0_pc0_3_default = 'h0;
//-- Default runtime_1in3_pem_load_info_0_pc1_0
  logic [REG_DATA_W-1:0]runtime_1in3_pem_load_info_0_pc1_0_default;
  assign runtime_1in3_pem_load_info_0_pc1_0_default = 'h0;
//-- Default runtime_1in3_pem_load_info_0_pc1_1
  logic [REG_DATA_W-1:0]runtime_1in3_pem_load_info_0_pc1_1_default;
  assign runtime_1in3_pem_load_info_0_pc1_1_default = 'h0;
//-- Default runtime_1in3_pem_load_info_0_pc1_2
  logic [REG_DATA_W-1:0]runtime_1in3_pem_load_info_0_pc1_2_default;
  assign runtime_1in3_pem_load_info_0_pc1_2_default = 'h0;
//-- Default runtime_1in3_pem_load_info_0_pc1_3
  logic [REG_DATA_W-1:0]runtime_1in3_pem_load_info_0_pc1_3_default;
  assign runtime_1in3_pem_load_info_0_pc1_3_default = 'h0;
//-- Default runtime_1in3_pem_load_info_1_pc0_lsb
  logic [REG_DATA_W-1:0]runtime_1in3_pem_load_info_1_pc0_lsb_default;
  assign runtime_1in3_pem_load_info_1_pc0_lsb_default = 'h0;
//-- Default runtime_1in3_pem_load_info_1_pc0_msb
  logic [REG_DATA_W-1:0]runtime_1in3_pem_load_info_1_pc0_msb_default;
  assign runtime_1in3_pem_load_info_1_pc0_msb_default = 'h0;
//-- Default runtime_1in3_pem_load_info_1_pc1_lsb
  logic [REG_DATA_W-1:0]runtime_1in3_pem_load_info_1_pc1_lsb_default;
  assign runtime_1in3_pem_load_info_1_pc1_lsb_default = 'h0;
//-- Default runtime_1in3_pem_load_info_1_pc1_msb
  logic [REG_DATA_W-1:0]runtime_1in3_pem_load_info_1_pc1_msb_default;
  assign runtime_1in3_pem_load_info_1_pc1_msb_default = 'h0;
//-- Default runtime_1in3_pem_store_info_0
  runtime_1in3_pem_store_info_0_t runtime_1in3_pem_store_info_0_default;
  always_comb begin
    runtime_1in3_pem_store_info_0_default = 'h0;
    runtime_1in3_pem_store_info_0_default.cmd_vld = 'h0;
    runtime_1in3_pem_store_info_0_default.cmd_rdy = 'h0;
    runtime_1in3_pem_store_info_0_default.pem_regf_rd_req_vld = 'h0;
    runtime_1in3_pem_store_info_0_default.pem_regf_rd_req_rdy = 'h0;
    runtime_1in3_pem_store_info_0_default.brsp_fifo_in_vld = 'h0;
    runtime_1in3_pem_store_info_0_default.brsp_fifo_in_rdy = 'h0;
    runtime_1in3_pem_store_info_0_default.rcp_fifo_in_vld = 'h0;
    runtime_1in3_pem_store_info_0_default.rcp_fifo_in_rdy = 'h0;
    runtime_1in3_pem_store_info_0_default.r2_axi_vld = 'h0;
    runtime_1in3_pem_store_info_0_default.r2_axi_rdy = 'h0;
    runtime_1in3_pem_store_info_0_default.c0_enough_location = 'h0;
  end
//-- Default runtime_1in3_pem_store_info_1
  runtime_1in3_pem_store_info_1_t runtime_1in3_pem_store_info_1_default;
  always_comb begin
    runtime_1in3_pem_store_info_1_default = 'h0;
    runtime_1in3_pem_store_info_1_default.s0_cmd_vld = 'h0;
    runtime_1in3_pem_store_info_1_default.s0_cmd_rdy = 'h0;
    runtime_1in3_pem_store_info_1_default.m_axi_bvalid = 'h0;
    runtime_1in3_pem_store_info_1_default.m_axi_bready = 'h0;
    runtime_1in3_pem_store_info_1_default.m_axi_wvalid = 'h0;
    runtime_1in3_pem_store_info_1_default.m_axi_wready = 'h0;
    runtime_1in3_pem_store_info_1_default.m_axi_awvalid = 'h0;
    runtime_1in3_pem_store_info_1_default.m_axi_awready = 'h0;
  end
//-- Default runtime_1in3_pem_store_info_2
  runtime_1in3_pem_store_info_2_t runtime_1in3_pem_store_info_2_default;
  always_comb begin
    runtime_1in3_pem_store_info_2_default = 'h0;
    runtime_1in3_pem_store_info_2_default.c0_free_loc_cnt = 'h0;
    runtime_1in3_pem_store_info_2_default.brsp_bresp_cnt = 'h0;
  end
//-- Default runtime_1in3_pem_store_info_3
  runtime_1in3_pem_store_info_3_t runtime_1in3_pem_store_info_3_default;
  always_comb begin
    runtime_1in3_pem_store_info_3_default = 'h0;
    runtime_1in3_pem_store_info_3_default.brsp_ack_seen = 'h0;
    runtime_1in3_pem_store_info_3_default.c0_cmd_cnt = 'h0;
  end
// ============================================================================================== --
// Write reg
// ============================================================================================== --
  // To ease the code, use REG_DATA_W as register size.
  // Unused bits will be simplified by the synthesizer
// Register FF: status_1in3_error
  logic [REG_DATA_W-1:0] r_status_1in3_errorD;
  assign r_status_1in3_errorD       = r_status_1in3_error_upd;
  logic r_status_1in3_error_wr_enD;
  assign r_status_1in3_error_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == STATUS_1IN3_ERROR_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_status_1in3_error_wr_en <= 1'b0;
    end
    else begin
      r_status_1in3_error_wr_en <= r_status_1in3_error_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_status_1in3_error       <= status_1in3_error_default;
    end
    else begin
      r_status_1in3_error       <= r_status_1in3_errorD;
    end
  end
// Register FF: ksk_avail_avail
  logic [REG_DATA_W-1:0] r_ksk_avail_availD;
  assign r_ksk_avail_availD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == KSK_AVAIL_AVAIL_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_ksk_avail_avail;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_ksk_avail_avail       <= ksk_avail_avail_default;
    end
    else begin
      r_ksk_avail_avail       <= r_ksk_avail_availD;
    end
  end
// Register FF: ksk_avail_reset
  logic [REG_DATA_W-1:0] r_ksk_avail_resetD;
  assign r_ksk_avail_resetD       = r_ksk_avail_reset_upd;
  logic r_ksk_avail_reset_wr_enD;
  assign r_ksk_avail_reset_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == KSK_AVAIL_RESET_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_ksk_avail_reset_wr_en <= 1'b0;
    end
    else begin
      r_ksk_avail_reset_wr_en <= r_ksk_avail_reset_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_ksk_avail_reset       <= ksk_avail_reset_default;
    end
    else begin
      r_ksk_avail_reset       <= r_ksk_avail_resetD;
    end
  end
// Register FF: runtime_1in3_pep_cmux_loop
  logic [REG_DATA_W-1:0] r_runtime_1in3_pep_cmux_loopD;
  assign r_runtime_1in3_pep_cmux_loopD       = r_runtime_1in3_pep_cmux_loop_upd;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_cmux_loop       <= runtime_1in3_pep_cmux_loop_default;
    end
    else begin
      r_runtime_1in3_pep_cmux_loop       <= r_runtime_1in3_pep_cmux_loopD;
    end
  end
// Register FF: runtime_1in3_pep_pointer_0
  logic [REG_DATA_W-1:0] r_runtime_1in3_pep_pointer_0D;
  assign r_runtime_1in3_pep_pointer_0D       = r_runtime_1in3_pep_pointer_0_upd;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_pointer_0       <= runtime_1in3_pep_pointer_0_default;
    end
    else begin
      r_runtime_1in3_pep_pointer_0       <= r_runtime_1in3_pep_pointer_0D;
    end
  end
// Register FF: runtime_1in3_pep_pointer_1
  logic [REG_DATA_W-1:0] r_runtime_1in3_pep_pointer_1D;
  assign r_runtime_1in3_pep_pointer_1D       = r_runtime_1in3_pep_pointer_1_upd;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_pointer_1       <= runtime_1in3_pep_pointer_1_default;
    end
    else begin
      r_runtime_1in3_pep_pointer_1       <= r_runtime_1in3_pep_pointer_1D;
    end
  end
// Register FF: runtime_1in3_pep_pointer_2
  logic [REG_DATA_W-1:0] r_runtime_1in3_pep_pointer_2D;
  assign r_runtime_1in3_pep_pointer_2D       = r_runtime_1in3_pep_pointer_2_upd;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_pointer_2       <= runtime_1in3_pep_pointer_2_default;
    end
    else begin
      r_runtime_1in3_pep_pointer_2       <= r_runtime_1in3_pep_pointer_2D;
    end
  end
// Register FF: runtime_1in3_isc_latest_instruction_0
  logic [REG_DATA_W-1:0] r_runtime_1in3_isc_latest_instruction_0D;
  assign r_runtime_1in3_isc_latest_instruction_0D       = r_runtime_1in3_isc_latest_instruction_0_upd;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_isc_latest_instruction_0       <= runtime_1in3_isc_latest_instruction_0_default;
    end
    else begin
      r_runtime_1in3_isc_latest_instruction_0       <= r_runtime_1in3_isc_latest_instruction_0D;
    end
  end
// Register FF: runtime_1in3_isc_latest_instruction_1
  logic [REG_DATA_W-1:0] r_runtime_1in3_isc_latest_instruction_1D;
  assign r_runtime_1in3_isc_latest_instruction_1D       = r_runtime_1in3_isc_latest_instruction_1_upd;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_isc_latest_instruction_1       <= runtime_1in3_isc_latest_instruction_1_default;
    end
    else begin
      r_runtime_1in3_isc_latest_instruction_1       <= r_runtime_1in3_isc_latest_instruction_1D;
    end
  end
// Register FF: runtime_1in3_isc_latest_instruction_2
  logic [REG_DATA_W-1:0] r_runtime_1in3_isc_latest_instruction_2D;
  assign r_runtime_1in3_isc_latest_instruction_2D       = r_runtime_1in3_isc_latest_instruction_2_upd;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_isc_latest_instruction_2       <= runtime_1in3_isc_latest_instruction_2_default;
    end
    else begin
      r_runtime_1in3_isc_latest_instruction_2       <= r_runtime_1in3_isc_latest_instruction_2D;
    end
  end
// Register FF: runtime_1in3_isc_latest_instruction_3
  logic [REG_DATA_W-1:0] r_runtime_1in3_isc_latest_instruction_3D;
  assign r_runtime_1in3_isc_latest_instruction_3D       = r_runtime_1in3_isc_latest_instruction_3_upd;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_isc_latest_instruction_3       <= runtime_1in3_isc_latest_instruction_3_default;
    end
    else begin
      r_runtime_1in3_isc_latest_instruction_3       <= r_runtime_1in3_isc_latest_instruction_3D;
    end
  end
// Register FF: runtime_1in3_pep_seq_bpip_batch_cnt
  logic [REG_DATA_W-1:0] r_runtime_1in3_pep_seq_bpip_batch_cntD;
  assign r_runtime_1in3_pep_seq_bpip_batch_cntD       = r_runtime_1in3_pep_seq_bpip_batch_cnt_upd;
  logic r_runtime_1in3_pep_seq_bpip_batch_cnt_wr_enD;
  assign r_runtime_1in3_pep_seq_bpip_batch_cnt_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_CNT_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_seq_bpip_batch_cnt_wr_en <= 1'b0;
    end
    else begin
      r_runtime_1in3_pep_seq_bpip_batch_cnt_wr_en <= r_runtime_1in3_pep_seq_bpip_batch_cnt_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_seq_bpip_batch_cnt       <= runtime_1in3_pep_seq_bpip_batch_cnt_default;
    end
    else begin
      r_runtime_1in3_pep_seq_bpip_batch_cnt       <= r_runtime_1in3_pep_seq_bpip_batch_cntD;
    end
  end
// Register FF: runtime_1in3_pep_seq_bpip_batch_flush_cnt
  logic [REG_DATA_W-1:0] r_runtime_1in3_pep_seq_bpip_batch_flush_cntD;
  assign r_runtime_1in3_pep_seq_bpip_batch_flush_cntD       = r_runtime_1in3_pep_seq_bpip_batch_flush_cnt_upd;
  logic r_runtime_1in3_pep_seq_bpip_batch_flush_cnt_wr_enD;
  assign r_runtime_1in3_pep_seq_bpip_batch_flush_cnt_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FLUSH_CNT_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_seq_bpip_batch_flush_cnt_wr_en <= 1'b0;
    end
    else begin
      r_runtime_1in3_pep_seq_bpip_batch_flush_cnt_wr_en <= r_runtime_1in3_pep_seq_bpip_batch_flush_cnt_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_seq_bpip_batch_flush_cnt       <= runtime_1in3_pep_seq_bpip_batch_flush_cnt_default;
    end
    else begin
      r_runtime_1in3_pep_seq_bpip_batch_flush_cnt       <= r_runtime_1in3_pep_seq_bpip_batch_flush_cntD;
    end
  end
// Register FF: runtime_1in3_pep_seq_bpip_batch_timeout_cnt
  logic [REG_DATA_W-1:0] r_runtime_1in3_pep_seq_bpip_batch_timeout_cntD;
  assign r_runtime_1in3_pep_seq_bpip_batch_timeout_cntD       = r_runtime_1in3_pep_seq_bpip_batch_timeout_cnt_upd;
  logic r_runtime_1in3_pep_seq_bpip_batch_timeout_cnt_wr_enD;
  assign r_runtime_1in3_pep_seq_bpip_batch_timeout_cnt_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_TIMEOUT_CNT_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_seq_bpip_batch_timeout_cnt_wr_en <= 1'b0;
    end
    else begin
      r_runtime_1in3_pep_seq_bpip_batch_timeout_cnt_wr_en <= r_runtime_1in3_pep_seq_bpip_batch_timeout_cnt_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_seq_bpip_batch_timeout_cnt       <= runtime_1in3_pep_seq_bpip_batch_timeout_cnt_default;
    end
    else begin
      r_runtime_1in3_pep_seq_bpip_batch_timeout_cnt       <= r_runtime_1in3_pep_seq_bpip_batch_timeout_cntD;
    end
  end
// Register FF: runtime_1in3_pep_seq_bpip_waiting_batch_cnt
  logic [REG_DATA_W-1:0] r_runtime_1in3_pep_seq_bpip_waiting_batch_cntD;
  assign r_runtime_1in3_pep_seq_bpip_waiting_batch_cntD       = r_runtime_1in3_pep_seq_bpip_waiting_batch_cnt_upd;
  logic r_runtime_1in3_pep_seq_bpip_waiting_batch_cnt_wr_enD;
  assign r_runtime_1in3_pep_seq_bpip_waiting_batch_cnt_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RUNTIME_1IN3_PEP_SEQ_BPIP_WAITING_BATCH_CNT_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_seq_bpip_waiting_batch_cnt_wr_en <= 1'b0;
    end
    else begin
      r_runtime_1in3_pep_seq_bpip_waiting_batch_cnt_wr_en <= r_runtime_1in3_pep_seq_bpip_waiting_batch_cnt_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_seq_bpip_waiting_batch_cnt       <= runtime_1in3_pep_seq_bpip_waiting_batch_cnt_default;
    end
    else begin
      r_runtime_1in3_pep_seq_bpip_waiting_batch_cnt       <= r_runtime_1in3_pep_seq_bpip_waiting_batch_cntD;
    end
  end
// Register FF: runtime_1in3_pep_seq_bpip_batch_filling_cnt_1
  logic [REG_DATA_W-1:0] r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_1D;
  assign r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_1D       = r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_1_upd;
  logic r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_1_wr_enD;
  assign r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_1_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_1_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_1_wr_en <= 1'b0;
    end
    else begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_1_wr_en <= r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_1_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_1       <= runtime_1in3_pep_seq_bpip_batch_filling_cnt_1_default;
    end
    else begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_1       <= r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_1D;
    end
  end
// Register FF: runtime_1in3_pep_seq_bpip_batch_filling_cnt_2
  logic [REG_DATA_W-1:0] r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_2D;
  assign r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_2D       = r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_2_upd;
  logic r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_2_wr_enD;
  assign r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_2_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_2_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_2_wr_en <= 1'b0;
    end
    else begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_2_wr_en <= r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_2_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_2       <= runtime_1in3_pep_seq_bpip_batch_filling_cnt_2_default;
    end
    else begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_2       <= r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_2D;
    end
  end
// Register FF: runtime_1in3_pep_seq_bpip_batch_filling_cnt_3
  logic [REG_DATA_W-1:0] r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_3D;
  assign r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_3D       = r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_3_upd;
  logic r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_3_wr_enD;
  assign r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_3_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_3_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_3_wr_en <= 1'b0;
    end
    else begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_3_wr_en <= r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_3_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_3       <= runtime_1in3_pep_seq_bpip_batch_filling_cnt_3_default;
    end
    else begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_3       <= r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_3D;
    end
  end
// Register FF: runtime_1in3_pep_seq_bpip_batch_filling_cnt_4
  logic [REG_DATA_W-1:0] r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_4D;
  assign r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_4D       = r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_4_upd;
  logic r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_4_wr_enD;
  assign r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_4_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_4_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_4_wr_en <= 1'b0;
    end
    else begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_4_wr_en <= r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_4_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_4       <= runtime_1in3_pep_seq_bpip_batch_filling_cnt_4_default;
    end
    else begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_4       <= r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_4D;
    end
  end
// Register FF: runtime_1in3_pep_seq_bpip_batch_filling_cnt_5
  logic [REG_DATA_W-1:0] r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_5D;
  assign r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_5D       = r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_5_upd;
  logic r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_5_wr_enD;
  assign r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_5_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_5_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_5_wr_en <= 1'b0;
    end
    else begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_5_wr_en <= r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_5_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_5       <= runtime_1in3_pep_seq_bpip_batch_filling_cnt_5_default;
    end
    else begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_5       <= r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_5D;
    end
  end
// Register FF: runtime_1in3_pep_seq_bpip_batch_filling_cnt_6
  logic [REG_DATA_W-1:0] r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_6D;
  assign r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_6D       = r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_6_upd;
  logic r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_6_wr_enD;
  assign r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_6_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_6_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_6_wr_en <= 1'b0;
    end
    else begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_6_wr_en <= r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_6_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_6       <= runtime_1in3_pep_seq_bpip_batch_filling_cnt_6_default;
    end
    else begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_6       <= r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_6D;
    end
  end
// Register FF: runtime_1in3_pep_seq_bpip_batch_filling_cnt_7
  logic [REG_DATA_W-1:0] r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_7D;
  assign r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_7D       = r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_7_upd;
  logic r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_7_wr_enD;
  assign r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_7_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_7_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_7_wr_en <= 1'b0;
    end
    else begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_7_wr_en <= r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_7_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_7       <= runtime_1in3_pep_seq_bpip_batch_filling_cnt_7_default;
    end
    else begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_7       <= r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_7D;
    end
  end
// Register FF: runtime_1in3_pep_seq_bpip_batch_filling_cnt_8
  logic [REG_DATA_W-1:0] r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_8D;
  assign r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_8D       = r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_8_upd;
  logic r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_8_wr_enD;
  assign r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_8_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_8_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_8_wr_en <= 1'b0;
    end
    else begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_8_wr_en <= r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_8_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_8       <= runtime_1in3_pep_seq_bpip_batch_filling_cnt_8_default;
    end
    else begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_8       <= r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_8D;
    end
  end
// Register FF: runtime_1in3_pep_seq_bpip_batch_filling_cnt_9
  logic [REG_DATA_W-1:0] r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_9D;
  assign r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_9D       = r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_9_upd;
  logic r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_9_wr_enD;
  assign r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_9_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_9_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_9_wr_en <= 1'b0;
    end
    else begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_9_wr_en <= r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_9_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_9       <= runtime_1in3_pep_seq_bpip_batch_filling_cnt_9_default;
    end
    else begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_9       <= r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_9D;
    end
  end
// Register FF: runtime_1in3_pep_seq_bpip_batch_filling_cnt_10
  logic [REG_DATA_W-1:0] r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_10D;
  assign r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_10D       = r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_10_upd;
  logic r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_10_wr_enD;
  assign r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_10_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_10_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_10_wr_en <= 1'b0;
    end
    else begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_10_wr_en <= r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_10_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_10       <= runtime_1in3_pep_seq_bpip_batch_filling_cnt_10_default;
    end
    else begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_10       <= r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_10D;
    end
  end
// Register FF: runtime_1in3_pep_seq_bpip_batch_filling_cnt_11
  logic [REG_DATA_W-1:0] r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_11D;
  assign r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_11D       = r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_11_upd;
  logic r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_11_wr_enD;
  assign r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_11_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_11_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_11_wr_en <= 1'b0;
    end
    else begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_11_wr_en <= r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_11_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_11       <= runtime_1in3_pep_seq_bpip_batch_filling_cnt_11_default;
    end
    else begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_11       <= r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_11D;
    end
  end
// Register FF: runtime_1in3_pep_seq_bpip_batch_filling_cnt_12
  logic [REG_DATA_W-1:0] r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_12D;
  assign r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_12D       = r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_12_upd;
  logic r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_12_wr_enD;
  assign r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_12_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_12_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_12_wr_en <= 1'b0;
    end
    else begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_12_wr_en <= r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_12_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_12       <= runtime_1in3_pep_seq_bpip_batch_filling_cnt_12_default;
    end
    else begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_12       <= r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_12D;
    end
  end
// Register FF: runtime_1in3_pep_seq_bpip_batch_filling_cnt_13
  logic [REG_DATA_W-1:0] r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_13D;
  assign r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_13D       = r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_13_upd;
  logic r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_13_wr_enD;
  assign r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_13_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_13_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_13_wr_en <= 1'b0;
    end
    else begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_13_wr_en <= r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_13_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_13       <= runtime_1in3_pep_seq_bpip_batch_filling_cnt_13_default;
    end
    else begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_13       <= r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_13D;
    end
  end
// Register FF: runtime_1in3_pep_seq_bpip_batch_filling_cnt_14
  logic [REG_DATA_W-1:0] r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_14D;
  assign r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_14D       = r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_14_upd;
  logic r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_14_wr_enD;
  assign r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_14_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_14_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_14_wr_en <= 1'b0;
    end
    else begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_14_wr_en <= r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_14_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_14       <= runtime_1in3_pep_seq_bpip_batch_filling_cnt_14_default;
    end
    else begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_14       <= r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_14D;
    end
  end
// Register FF: runtime_1in3_pep_seq_bpip_batch_filling_cnt_15
  logic [REG_DATA_W-1:0] r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_15D;
  assign r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_15D       = r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_15_upd;
  logic r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_15_wr_enD;
  assign r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_15_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_15_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_15_wr_en <= 1'b0;
    end
    else begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_15_wr_en <= r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_15_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_15       <= runtime_1in3_pep_seq_bpip_batch_filling_cnt_15_default;
    end
    else begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_15       <= r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_15D;
    end
  end
// Register FF: runtime_1in3_pep_seq_bpip_batch_filling_cnt_16
  logic [REG_DATA_W-1:0] r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_16D;
  assign r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_16D       = r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_16_upd;
  logic r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_16_wr_enD;
  assign r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_16_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_16_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_16_wr_en <= 1'b0;
    end
    else begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_16_wr_en <= r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_16_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_16       <= runtime_1in3_pep_seq_bpip_batch_filling_cnt_16_default;
    end
    else begin
      r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_16       <= r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_16D;
    end
  end
// Register FF: runtime_1in3_pep_seq_ld_ack_cnt
  logic [REG_DATA_W-1:0] r_runtime_1in3_pep_seq_ld_ack_cntD;
  assign r_runtime_1in3_pep_seq_ld_ack_cntD       = r_runtime_1in3_pep_seq_ld_ack_cnt_upd;
  logic r_runtime_1in3_pep_seq_ld_ack_cnt_wr_enD;
  assign r_runtime_1in3_pep_seq_ld_ack_cnt_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RUNTIME_1IN3_PEP_SEQ_LD_ACK_CNT_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_seq_ld_ack_cnt_wr_en <= 1'b0;
    end
    else begin
      r_runtime_1in3_pep_seq_ld_ack_cnt_wr_en <= r_runtime_1in3_pep_seq_ld_ack_cnt_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_seq_ld_ack_cnt       <= runtime_1in3_pep_seq_ld_ack_cnt_default;
    end
    else begin
      r_runtime_1in3_pep_seq_ld_ack_cnt       <= r_runtime_1in3_pep_seq_ld_ack_cntD;
    end
  end
// Register FF: runtime_1in3_pep_seq_cmux_not_full_batch_cnt
  logic [REG_DATA_W-1:0] r_runtime_1in3_pep_seq_cmux_not_full_batch_cntD;
  assign r_runtime_1in3_pep_seq_cmux_not_full_batch_cntD       = r_runtime_1in3_pep_seq_cmux_not_full_batch_cnt_upd;
  logic r_runtime_1in3_pep_seq_cmux_not_full_batch_cnt_wr_enD;
  assign r_runtime_1in3_pep_seq_cmux_not_full_batch_cnt_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RUNTIME_1IN3_PEP_SEQ_CMUX_NOT_FULL_BATCH_CNT_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_seq_cmux_not_full_batch_cnt_wr_en <= 1'b0;
    end
    else begin
      r_runtime_1in3_pep_seq_cmux_not_full_batch_cnt_wr_en <= r_runtime_1in3_pep_seq_cmux_not_full_batch_cnt_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_seq_cmux_not_full_batch_cnt       <= runtime_1in3_pep_seq_cmux_not_full_batch_cnt_default;
    end
    else begin
      r_runtime_1in3_pep_seq_cmux_not_full_batch_cnt       <= r_runtime_1in3_pep_seq_cmux_not_full_batch_cntD;
    end
  end
// Register FF: runtime_1in3_pep_seq_ipip_flush_cnt
  logic [REG_DATA_W-1:0] r_runtime_1in3_pep_seq_ipip_flush_cntD;
  assign r_runtime_1in3_pep_seq_ipip_flush_cntD       = r_runtime_1in3_pep_seq_ipip_flush_cnt_upd;
  logic r_runtime_1in3_pep_seq_ipip_flush_cnt_wr_enD;
  assign r_runtime_1in3_pep_seq_ipip_flush_cnt_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RUNTIME_1IN3_PEP_SEQ_IPIP_FLUSH_CNT_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_seq_ipip_flush_cnt_wr_en <= 1'b0;
    end
    else begin
      r_runtime_1in3_pep_seq_ipip_flush_cnt_wr_en <= r_runtime_1in3_pep_seq_ipip_flush_cnt_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_seq_ipip_flush_cnt       <= runtime_1in3_pep_seq_ipip_flush_cnt_default;
    end
    else begin
      r_runtime_1in3_pep_seq_ipip_flush_cnt       <= r_runtime_1in3_pep_seq_ipip_flush_cntD;
    end
  end
// Register FF: runtime_1in3_pep_ldb_rcp_dur
  logic [REG_DATA_W-1:0] r_runtime_1in3_pep_ldb_rcp_durD;
  assign r_runtime_1in3_pep_ldb_rcp_durD       = r_runtime_1in3_pep_ldb_rcp_dur_upd;
  logic r_runtime_1in3_pep_ldb_rcp_dur_wr_enD;
  assign r_runtime_1in3_pep_ldb_rcp_dur_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RUNTIME_1IN3_PEP_LDB_RCP_DUR_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_ldb_rcp_dur_wr_en <= 1'b0;
    end
    else begin
      r_runtime_1in3_pep_ldb_rcp_dur_wr_en <= r_runtime_1in3_pep_ldb_rcp_dur_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_ldb_rcp_dur       <= runtime_1in3_pep_ldb_rcp_dur_default;
    end
    else begin
      r_runtime_1in3_pep_ldb_rcp_dur       <= r_runtime_1in3_pep_ldb_rcp_durD;
    end
  end
// Register FF: runtime_1in3_pep_ldg_req_dur
  logic [REG_DATA_W-1:0] r_runtime_1in3_pep_ldg_req_durD;
  assign r_runtime_1in3_pep_ldg_req_durD       = r_runtime_1in3_pep_ldg_req_dur_upd;
  logic r_runtime_1in3_pep_ldg_req_dur_wr_enD;
  assign r_runtime_1in3_pep_ldg_req_dur_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RUNTIME_1IN3_PEP_LDG_REQ_DUR_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_ldg_req_dur_wr_en <= 1'b0;
    end
    else begin
      r_runtime_1in3_pep_ldg_req_dur_wr_en <= r_runtime_1in3_pep_ldg_req_dur_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_ldg_req_dur       <= runtime_1in3_pep_ldg_req_dur_default;
    end
    else begin
      r_runtime_1in3_pep_ldg_req_dur       <= r_runtime_1in3_pep_ldg_req_durD;
    end
  end
// Register FF: runtime_1in3_pep_ldg_rcp_dur
  logic [REG_DATA_W-1:0] r_runtime_1in3_pep_ldg_rcp_durD;
  assign r_runtime_1in3_pep_ldg_rcp_durD       = r_runtime_1in3_pep_ldg_rcp_dur_upd;
  logic r_runtime_1in3_pep_ldg_rcp_dur_wr_enD;
  assign r_runtime_1in3_pep_ldg_rcp_dur_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RUNTIME_1IN3_PEP_LDG_RCP_DUR_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_ldg_rcp_dur_wr_en <= 1'b0;
    end
    else begin
      r_runtime_1in3_pep_ldg_rcp_dur_wr_en <= r_runtime_1in3_pep_ldg_rcp_dur_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_ldg_rcp_dur       <= runtime_1in3_pep_ldg_rcp_dur_default;
    end
    else begin
      r_runtime_1in3_pep_ldg_rcp_dur       <= r_runtime_1in3_pep_ldg_rcp_durD;
    end
  end
// Register FF: runtime_1in3_pep_load_ksk_rcp_dur_pc0
  logic [REG_DATA_W-1:0] r_runtime_1in3_pep_load_ksk_rcp_dur_pc0D;
  assign r_runtime_1in3_pep_load_ksk_rcp_dur_pc0D       = r_runtime_1in3_pep_load_ksk_rcp_dur_pc0_upd;
  logic r_runtime_1in3_pep_load_ksk_rcp_dur_pc0_wr_enD;
  assign r_runtime_1in3_pep_load_ksk_rcp_dur_pc0_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC0_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc0_wr_en <= 1'b0;
    end
    else begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc0_wr_en <= r_runtime_1in3_pep_load_ksk_rcp_dur_pc0_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc0       <= runtime_1in3_pep_load_ksk_rcp_dur_pc0_default;
    end
    else begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc0       <= r_runtime_1in3_pep_load_ksk_rcp_dur_pc0D;
    end
  end
// Register FF: runtime_1in3_pep_load_ksk_rcp_dur_pc1
  logic [REG_DATA_W-1:0] r_runtime_1in3_pep_load_ksk_rcp_dur_pc1D;
  assign r_runtime_1in3_pep_load_ksk_rcp_dur_pc1D       = r_runtime_1in3_pep_load_ksk_rcp_dur_pc1_upd;
  logic r_runtime_1in3_pep_load_ksk_rcp_dur_pc1_wr_enD;
  assign r_runtime_1in3_pep_load_ksk_rcp_dur_pc1_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC1_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc1_wr_en <= 1'b0;
    end
    else begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc1_wr_en <= r_runtime_1in3_pep_load_ksk_rcp_dur_pc1_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc1       <= runtime_1in3_pep_load_ksk_rcp_dur_pc1_default;
    end
    else begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc1       <= r_runtime_1in3_pep_load_ksk_rcp_dur_pc1D;
    end
  end
// Register FF: runtime_1in3_pep_load_ksk_rcp_dur_pc2
  logic [REG_DATA_W-1:0] r_runtime_1in3_pep_load_ksk_rcp_dur_pc2D;
  assign r_runtime_1in3_pep_load_ksk_rcp_dur_pc2D       = r_runtime_1in3_pep_load_ksk_rcp_dur_pc2_upd;
  logic r_runtime_1in3_pep_load_ksk_rcp_dur_pc2_wr_enD;
  assign r_runtime_1in3_pep_load_ksk_rcp_dur_pc2_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC2_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc2_wr_en <= 1'b0;
    end
    else begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc2_wr_en <= r_runtime_1in3_pep_load_ksk_rcp_dur_pc2_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc2       <= runtime_1in3_pep_load_ksk_rcp_dur_pc2_default;
    end
    else begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc2       <= r_runtime_1in3_pep_load_ksk_rcp_dur_pc2D;
    end
  end
// Register FF: runtime_1in3_pep_load_ksk_rcp_dur_pc3
  logic [REG_DATA_W-1:0] r_runtime_1in3_pep_load_ksk_rcp_dur_pc3D;
  assign r_runtime_1in3_pep_load_ksk_rcp_dur_pc3D       = r_runtime_1in3_pep_load_ksk_rcp_dur_pc3_upd;
  logic r_runtime_1in3_pep_load_ksk_rcp_dur_pc3_wr_enD;
  assign r_runtime_1in3_pep_load_ksk_rcp_dur_pc3_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC3_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc3_wr_en <= 1'b0;
    end
    else begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc3_wr_en <= r_runtime_1in3_pep_load_ksk_rcp_dur_pc3_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc3       <= runtime_1in3_pep_load_ksk_rcp_dur_pc3_default;
    end
    else begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc3       <= r_runtime_1in3_pep_load_ksk_rcp_dur_pc3D;
    end
  end
// Register FF: runtime_1in3_pep_load_ksk_rcp_dur_pc4
  logic [REG_DATA_W-1:0] r_runtime_1in3_pep_load_ksk_rcp_dur_pc4D;
  assign r_runtime_1in3_pep_load_ksk_rcp_dur_pc4D       = r_runtime_1in3_pep_load_ksk_rcp_dur_pc4_upd;
  logic r_runtime_1in3_pep_load_ksk_rcp_dur_pc4_wr_enD;
  assign r_runtime_1in3_pep_load_ksk_rcp_dur_pc4_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC4_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc4_wr_en <= 1'b0;
    end
    else begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc4_wr_en <= r_runtime_1in3_pep_load_ksk_rcp_dur_pc4_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc4       <= runtime_1in3_pep_load_ksk_rcp_dur_pc4_default;
    end
    else begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc4       <= r_runtime_1in3_pep_load_ksk_rcp_dur_pc4D;
    end
  end
// Register FF: runtime_1in3_pep_load_ksk_rcp_dur_pc5
  logic [REG_DATA_W-1:0] r_runtime_1in3_pep_load_ksk_rcp_dur_pc5D;
  assign r_runtime_1in3_pep_load_ksk_rcp_dur_pc5D       = r_runtime_1in3_pep_load_ksk_rcp_dur_pc5_upd;
  logic r_runtime_1in3_pep_load_ksk_rcp_dur_pc5_wr_enD;
  assign r_runtime_1in3_pep_load_ksk_rcp_dur_pc5_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC5_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc5_wr_en <= 1'b0;
    end
    else begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc5_wr_en <= r_runtime_1in3_pep_load_ksk_rcp_dur_pc5_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc5       <= runtime_1in3_pep_load_ksk_rcp_dur_pc5_default;
    end
    else begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc5       <= r_runtime_1in3_pep_load_ksk_rcp_dur_pc5D;
    end
  end
// Register FF: runtime_1in3_pep_load_ksk_rcp_dur_pc6
  logic [REG_DATA_W-1:0] r_runtime_1in3_pep_load_ksk_rcp_dur_pc6D;
  assign r_runtime_1in3_pep_load_ksk_rcp_dur_pc6D       = r_runtime_1in3_pep_load_ksk_rcp_dur_pc6_upd;
  logic r_runtime_1in3_pep_load_ksk_rcp_dur_pc6_wr_enD;
  assign r_runtime_1in3_pep_load_ksk_rcp_dur_pc6_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC6_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc6_wr_en <= 1'b0;
    end
    else begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc6_wr_en <= r_runtime_1in3_pep_load_ksk_rcp_dur_pc6_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc6       <= runtime_1in3_pep_load_ksk_rcp_dur_pc6_default;
    end
    else begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc6       <= r_runtime_1in3_pep_load_ksk_rcp_dur_pc6D;
    end
  end
// Register FF: runtime_1in3_pep_load_ksk_rcp_dur_pc7
  logic [REG_DATA_W-1:0] r_runtime_1in3_pep_load_ksk_rcp_dur_pc7D;
  assign r_runtime_1in3_pep_load_ksk_rcp_dur_pc7D       = r_runtime_1in3_pep_load_ksk_rcp_dur_pc7_upd;
  logic r_runtime_1in3_pep_load_ksk_rcp_dur_pc7_wr_enD;
  assign r_runtime_1in3_pep_load_ksk_rcp_dur_pc7_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC7_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc7_wr_en <= 1'b0;
    end
    else begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc7_wr_en <= r_runtime_1in3_pep_load_ksk_rcp_dur_pc7_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc7       <= runtime_1in3_pep_load_ksk_rcp_dur_pc7_default;
    end
    else begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc7       <= r_runtime_1in3_pep_load_ksk_rcp_dur_pc7D;
    end
  end
// Register FF: runtime_1in3_pep_load_ksk_rcp_dur_pc8
  logic [REG_DATA_W-1:0] r_runtime_1in3_pep_load_ksk_rcp_dur_pc8D;
  assign r_runtime_1in3_pep_load_ksk_rcp_dur_pc8D       = r_runtime_1in3_pep_load_ksk_rcp_dur_pc8_upd;
  logic r_runtime_1in3_pep_load_ksk_rcp_dur_pc8_wr_enD;
  assign r_runtime_1in3_pep_load_ksk_rcp_dur_pc8_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC8_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc8_wr_en <= 1'b0;
    end
    else begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc8_wr_en <= r_runtime_1in3_pep_load_ksk_rcp_dur_pc8_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc8       <= runtime_1in3_pep_load_ksk_rcp_dur_pc8_default;
    end
    else begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc8       <= r_runtime_1in3_pep_load_ksk_rcp_dur_pc8D;
    end
  end
// Register FF: runtime_1in3_pep_load_ksk_rcp_dur_pc9
  logic [REG_DATA_W-1:0] r_runtime_1in3_pep_load_ksk_rcp_dur_pc9D;
  assign r_runtime_1in3_pep_load_ksk_rcp_dur_pc9D       = r_runtime_1in3_pep_load_ksk_rcp_dur_pc9_upd;
  logic r_runtime_1in3_pep_load_ksk_rcp_dur_pc9_wr_enD;
  assign r_runtime_1in3_pep_load_ksk_rcp_dur_pc9_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC9_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc9_wr_en <= 1'b0;
    end
    else begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc9_wr_en <= r_runtime_1in3_pep_load_ksk_rcp_dur_pc9_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc9       <= runtime_1in3_pep_load_ksk_rcp_dur_pc9_default;
    end
    else begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc9       <= r_runtime_1in3_pep_load_ksk_rcp_dur_pc9D;
    end
  end
// Register FF: runtime_1in3_pep_load_ksk_rcp_dur_pc10
  logic [REG_DATA_W-1:0] r_runtime_1in3_pep_load_ksk_rcp_dur_pc10D;
  assign r_runtime_1in3_pep_load_ksk_rcp_dur_pc10D       = r_runtime_1in3_pep_load_ksk_rcp_dur_pc10_upd;
  logic r_runtime_1in3_pep_load_ksk_rcp_dur_pc10_wr_enD;
  assign r_runtime_1in3_pep_load_ksk_rcp_dur_pc10_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC10_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc10_wr_en <= 1'b0;
    end
    else begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc10_wr_en <= r_runtime_1in3_pep_load_ksk_rcp_dur_pc10_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc10       <= runtime_1in3_pep_load_ksk_rcp_dur_pc10_default;
    end
    else begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc10       <= r_runtime_1in3_pep_load_ksk_rcp_dur_pc10D;
    end
  end
// Register FF: runtime_1in3_pep_load_ksk_rcp_dur_pc11
  logic [REG_DATA_W-1:0] r_runtime_1in3_pep_load_ksk_rcp_dur_pc11D;
  assign r_runtime_1in3_pep_load_ksk_rcp_dur_pc11D       = r_runtime_1in3_pep_load_ksk_rcp_dur_pc11_upd;
  logic r_runtime_1in3_pep_load_ksk_rcp_dur_pc11_wr_enD;
  assign r_runtime_1in3_pep_load_ksk_rcp_dur_pc11_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC11_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc11_wr_en <= 1'b0;
    end
    else begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc11_wr_en <= r_runtime_1in3_pep_load_ksk_rcp_dur_pc11_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc11       <= runtime_1in3_pep_load_ksk_rcp_dur_pc11_default;
    end
    else begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc11       <= r_runtime_1in3_pep_load_ksk_rcp_dur_pc11D;
    end
  end
// Register FF: runtime_1in3_pep_load_ksk_rcp_dur_pc12
  logic [REG_DATA_W-1:0] r_runtime_1in3_pep_load_ksk_rcp_dur_pc12D;
  assign r_runtime_1in3_pep_load_ksk_rcp_dur_pc12D       = r_runtime_1in3_pep_load_ksk_rcp_dur_pc12_upd;
  logic r_runtime_1in3_pep_load_ksk_rcp_dur_pc12_wr_enD;
  assign r_runtime_1in3_pep_load_ksk_rcp_dur_pc12_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC12_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc12_wr_en <= 1'b0;
    end
    else begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc12_wr_en <= r_runtime_1in3_pep_load_ksk_rcp_dur_pc12_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc12       <= runtime_1in3_pep_load_ksk_rcp_dur_pc12_default;
    end
    else begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc12       <= r_runtime_1in3_pep_load_ksk_rcp_dur_pc12D;
    end
  end
// Register FF: runtime_1in3_pep_load_ksk_rcp_dur_pc13
  logic [REG_DATA_W-1:0] r_runtime_1in3_pep_load_ksk_rcp_dur_pc13D;
  assign r_runtime_1in3_pep_load_ksk_rcp_dur_pc13D       = r_runtime_1in3_pep_load_ksk_rcp_dur_pc13_upd;
  logic r_runtime_1in3_pep_load_ksk_rcp_dur_pc13_wr_enD;
  assign r_runtime_1in3_pep_load_ksk_rcp_dur_pc13_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC13_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc13_wr_en <= 1'b0;
    end
    else begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc13_wr_en <= r_runtime_1in3_pep_load_ksk_rcp_dur_pc13_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc13       <= runtime_1in3_pep_load_ksk_rcp_dur_pc13_default;
    end
    else begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc13       <= r_runtime_1in3_pep_load_ksk_rcp_dur_pc13D;
    end
  end
// Register FF: runtime_1in3_pep_load_ksk_rcp_dur_pc14
  logic [REG_DATA_W-1:0] r_runtime_1in3_pep_load_ksk_rcp_dur_pc14D;
  assign r_runtime_1in3_pep_load_ksk_rcp_dur_pc14D       = r_runtime_1in3_pep_load_ksk_rcp_dur_pc14_upd;
  logic r_runtime_1in3_pep_load_ksk_rcp_dur_pc14_wr_enD;
  assign r_runtime_1in3_pep_load_ksk_rcp_dur_pc14_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC14_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc14_wr_en <= 1'b0;
    end
    else begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc14_wr_en <= r_runtime_1in3_pep_load_ksk_rcp_dur_pc14_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc14       <= runtime_1in3_pep_load_ksk_rcp_dur_pc14_default;
    end
    else begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc14       <= r_runtime_1in3_pep_load_ksk_rcp_dur_pc14D;
    end
  end
// Register FF: runtime_1in3_pep_load_ksk_rcp_dur_pc15
  logic [REG_DATA_W-1:0] r_runtime_1in3_pep_load_ksk_rcp_dur_pc15D;
  assign r_runtime_1in3_pep_load_ksk_rcp_dur_pc15D       = r_runtime_1in3_pep_load_ksk_rcp_dur_pc15_upd;
  logic r_runtime_1in3_pep_load_ksk_rcp_dur_pc15_wr_enD;
  assign r_runtime_1in3_pep_load_ksk_rcp_dur_pc15_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC15_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc15_wr_en <= 1'b0;
    end
    else begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc15_wr_en <= r_runtime_1in3_pep_load_ksk_rcp_dur_pc15_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc15       <= runtime_1in3_pep_load_ksk_rcp_dur_pc15_default;
    end
    else begin
      r_runtime_1in3_pep_load_ksk_rcp_dur_pc15       <= r_runtime_1in3_pep_load_ksk_rcp_dur_pc15D;
    end
  end
// Register FF: runtime_1in3_pep_mmacc_sxt_rcp_dur
  logic [REG_DATA_W-1:0] r_runtime_1in3_pep_mmacc_sxt_rcp_durD;
  assign r_runtime_1in3_pep_mmacc_sxt_rcp_durD       = r_runtime_1in3_pep_mmacc_sxt_rcp_dur_upd;
  logic r_runtime_1in3_pep_mmacc_sxt_rcp_dur_wr_enD;
  assign r_runtime_1in3_pep_mmacc_sxt_rcp_dur_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RUNTIME_1IN3_PEP_MMACC_SXT_RCP_DUR_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_mmacc_sxt_rcp_dur_wr_en <= 1'b0;
    end
    else begin
      r_runtime_1in3_pep_mmacc_sxt_rcp_dur_wr_en <= r_runtime_1in3_pep_mmacc_sxt_rcp_dur_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_mmacc_sxt_rcp_dur       <= runtime_1in3_pep_mmacc_sxt_rcp_dur_default;
    end
    else begin
      r_runtime_1in3_pep_mmacc_sxt_rcp_dur       <= r_runtime_1in3_pep_mmacc_sxt_rcp_durD;
    end
  end
// Register FF: runtime_1in3_pep_mmacc_sxt_req_dur
  logic [REG_DATA_W-1:0] r_runtime_1in3_pep_mmacc_sxt_req_durD;
  assign r_runtime_1in3_pep_mmacc_sxt_req_durD       = r_runtime_1in3_pep_mmacc_sxt_req_dur_upd;
  logic r_runtime_1in3_pep_mmacc_sxt_req_dur_wr_enD;
  assign r_runtime_1in3_pep_mmacc_sxt_req_dur_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RUNTIME_1IN3_PEP_MMACC_SXT_REQ_DUR_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_mmacc_sxt_req_dur_wr_en <= 1'b0;
    end
    else begin
      r_runtime_1in3_pep_mmacc_sxt_req_dur_wr_en <= r_runtime_1in3_pep_mmacc_sxt_req_dur_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_mmacc_sxt_req_dur       <= runtime_1in3_pep_mmacc_sxt_req_dur_default;
    end
    else begin
      r_runtime_1in3_pep_mmacc_sxt_req_dur       <= r_runtime_1in3_pep_mmacc_sxt_req_durD;
    end
  end
// Register FF: runtime_1in3_pep_mmacc_sxt_cmd_wait_b_dur
  logic [REG_DATA_W-1:0] r_runtime_1in3_pep_mmacc_sxt_cmd_wait_b_durD;
  assign r_runtime_1in3_pep_mmacc_sxt_cmd_wait_b_durD       = r_runtime_1in3_pep_mmacc_sxt_cmd_wait_b_dur_upd;
  logic r_runtime_1in3_pep_mmacc_sxt_cmd_wait_b_dur_wr_enD;
  assign r_runtime_1in3_pep_mmacc_sxt_cmd_wait_b_dur_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RUNTIME_1IN3_PEP_MMACC_SXT_CMD_WAIT_B_DUR_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_mmacc_sxt_cmd_wait_b_dur_wr_en <= 1'b0;
    end
    else begin
      r_runtime_1in3_pep_mmacc_sxt_cmd_wait_b_dur_wr_en <= r_runtime_1in3_pep_mmacc_sxt_cmd_wait_b_dur_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_mmacc_sxt_cmd_wait_b_dur       <= runtime_1in3_pep_mmacc_sxt_cmd_wait_b_dur_default;
    end
    else begin
      r_runtime_1in3_pep_mmacc_sxt_cmd_wait_b_dur       <= r_runtime_1in3_pep_mmacc_sxt_cmd_wait_b_durD;
    end
  end
// Register FF: runtime_1in3_pep_inst_cnt
  logic [REG_DATA_W-1:0] r_runtime_1in3_pep_inst_cntD;
  assign r_runtime_1in3_pep_inst_cntD       = r_runtime_1in3_pep_inst_cnt_upd;
  logic r_runtime_1in3_pep_inst_cnt_wr_enD;
  assign r_runtime_1in3_pep_inst_cnt_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RUNTIME_1IN3_PEP_INST_CNT_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_inst_cnt_wr_en <= 1'b0;
    end
    else begin
      r_runtime_1in3_pep_inst_cnt_wr_en <= r_runtime_1in3_pep_inst_cnt_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_inst_cnt       <= runtime_1in3_pep_inst_cnt_default;
    end
    else begin
      r_runtime_1in3_pep_inst_cnt       <= r_runtime_1in3_pep_inst_cntD;
    end
  end
// Register FF: runtime_1in3_pep_ack_cnt
  logic [REG_DATA_W-1:0] r_runtime_1in3_pep_ack_cntD;
  assign r_runtime_1in3_pep_ack_cntD       = r_runtime_1in3_pep_ack_cnt_upd;
  logic r_runtime_1in3_pep_ack_cnt_wr_enD;
  assign r_runtime_1in3_pep_ack_cnt_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RUNTIME_1IN3_PEP_ACK_CNT_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_ack_cnt_wr_en <= 1'b0;
    end
    else begin
      r_runtime_1in3_pep_ack_cnt_wr_en <= r_runtime_1in3_pep_ack_cnt_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pep_ack_cnt       <= runtime_1in3_pep_ack_cnt_default;
    end
    else begin
      r_runtime_1in3_pep_ack_cnt       <= r_runtime_1in3_pep_ack_cntD;
    end
  end
// Register FF: runtime_1in3_pem_load_inst_cnt
  logic [REG_DATA_W-1:0] r_runtime_1in3_pem_load_inst_cntD;
  assign r_runtime_1in3_pem_load_inst_cntD       = r_runtime_1in3_pem_load_inst_cnt_upd;
  logic r_runtime_1in3_pem_load_inst_cnt_wr_enD;
  assign r_runtime_1in3_pem_load_inst_cnt_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RUNTIME_1IN3_PEM_LOAD_INST_CNT_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pem_load_inst_cnt_wr_en <= 1'b0;
    end
    else begin
      r_runtime_1in3_pem_load_inst_cnt_wr_en <= r_runtime_1in3_pem_load_inst_cnt_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pem_load_inst_cnt       <= runtime_1in3_pem_load_inst_cnt_default;
    end
    else begin
      r_runtime_1in3_pem_load_inst_cnt       <= r_runtime_1in3_pem_load_inst_cntD;
    end
  end
// Register FF: runtime_1in3_pem_load_ack_cnt
  logic [REG_DATA_W-1:0] r_runtime_1in3_pem_load_ack_cntD;
  assign r_runtime_1in3_pem_load_ack_cntD       = r_runtime_1in3_pem_load_ack_cnt_upd;
  logic r_runtime_1in3_pem_load_ack_cnt_wr_enD;
  assign r_runtime_1in3_pem_load_ack_cnt_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RUNTIME_1IN3_PEM_LOAD_ACK_CNT_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pem_load_ack_cnt_wr_en <= 1'b0;
    end
    else begin
      r_runtime_1in3_pem_load_ack_cnt_wr_en <= r_runtime_1in3_pem_load_ack_cnt_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pem_load_ack_cnt       <= runtime_1in3_pem_load_ack_cnt_default;
    end
    else begin
      r_runtime_1in3_pem_load_ack_cnt       <= r_runtime_1in3_pem_load_ack_cntD;
    end
  end
// Register FF: runtime_1in3_pem_store_inst_cnt
  logic [REG_DATA_W-1:0] r_runtime_1in3_pem_store_inst_cntD;
  assign r_runtime_1in3_pem_store_inst_cntD       = r_runtime_1in3_pem_store_inst_cnt_upd;
  logic r_runtime_1in3_pem_store_inst_cnt_wr_enD;
  assign r_runtime_1in3_pem_store_inst_cnt_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RUNTIME_1IN3_PEM_STORE_INST_CNT_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pem_store_inst_cnt_wr_en <= 1'b0;
    end
    else begin
      r_runtime_1in3_pem_store_inst_cnt_wr_en <= r_runtime_1in3_pem_store_inst_cnt_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pem_store_inst_cnt       <= runtime_1in3_pem_store_inst_cnt_default;
    end
    else begin
      r_runtime_1in3_pem_store_inst_cnt       <= r_runtime_1in3_pem_store_inst_cntD;
    end
  end
// Register FF: runtime_1in3_pem_store_ack_cnt
  logic [REG_DATA_W-1:0] r_runtime_1in3_pem_store_ack_cntD;
  assign r_runtime_1in3_pem_store_ack_cntD       = r_runtime_1in3_pem_store_ack_cnt_upd;
  logic r_runtime_1in3_pem_store_ack_cnt_wr_enD;
  assign r_runtime_1in3_pem_store_ack_cnt_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RUNTIME_1IN3_PEM_STORE_ACK_CNT_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pem_store_ack_cnt_wr_en <= 1'b0;
    end
    else begin
      r_runtime_1in3_pem_store_ack_cnt_wr_en <= r_runtime_1in3_pem_store_ack_cnt_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pem_store_ack_cnt       <= runtime_1in3_pem_store_ack_cnt_default;
    end
    else begin
      r_runtime_1in3_pem_store_ack_cnt       <= r_runtime_1in3_pem_store_ack_cntD;
    end
  end
// Register FF: runtime_1in3_pea_inst_cnt
  logic [REG_DATA_W-1:0] r_runtime_1in3_pea_inst_cntD;
  assign r_runtime_1in3_pea_inst_cntD       = r_runtime_1in3_pea_inst_cnt_upd;
  logic r_runtime_1in3_pea_inst_cnt_wr_enD;
  assign r_runtime_1in3_pea_inst_cnt_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RUNTIME_1IN3_PEA_INST_CNT_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pea_inst_cnt_wr_en <= 1'b0;
    end
    else begin
      r_runtime_1in3_pea_inst_cnt_wr_en <= r_runtime_1in3_pea_inst_cnt_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pea_inst_cnt       <= runtime_1in3_pea_inst_cnt_default;
    end
    else begin
      r_runtime_1in3_pea_inst_cnt       <= r_runtime_1in3_pea_inst_cntD;
    end
  end
// Register FF: runtime_1in3_pea_ack_cnt
  logic [REG_DATA_W-1:0] r_runtime_1in3_pea_ack_cntD;
  assign r_runtime_1in3_pea_ack_cntD       = r_runtime_1in3_pea_ack_cnt_upd;
  logic r_runtime_1in3_pea_ack_cnt_wr_enD;
  assign r_runtime_1in3_pea_ack_cnt_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RUNTIME_1IN3_PEA_ACK_CNT_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pea_ack_cnt_wr_en <= 1'b0;
    end
    else begin
      r_runtime_1in3_pea_ack_cnt_wr_en <= r_runtime_1in3_pea_ack_cnt_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pea_ack_cnt       <= runtime_1in3_pea_ack_cnt_default;
    end
    else begin
      r_runtime_1in3_pea_ack_cnt       <= r_runtime_1in3_pea_ack_cntD;
    end
  end
// Register FF: runtime_1in3_isc_inst_cnt
  logic [REG_DATA_W-1:0] r_runtime_1in3_isc_inst_cntD;
  assign r_runtime_1in3_isc_inst_cntD       = r_runtime_1in3_isc_inst_cnt_upd;
  logic r_runtime_1in3_isc_inst_cnt_wr_enD;
  assign r_runtime_1in3_isc_inst_cnt_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RUNTIME_1IN3_ISC_INST_CNT_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_isc_inst_cnt_wr_en <= 1'b0;
    end
    else begin
      r_runtime_1in3_isc_inst_cnt_wr_en <= r_runtime_1in3_isc_inst_cnt_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_isc_inst_cnt       <= runtime_1in3_isc_inst_cnt_default;
    end
    else begin
      r_runtime_1in3_isc_inst_cnt       <= r_runtime_1in3_isc_inst_cntD;
    end
  end
// Register FF: runtime_1in3_isc_ack_cnt
  logic [REG_DATA_W-1:0] r_runtime_1in3_isc_ack_cntD;
  assign r_runtime_1in3_isc_ack_cntD       = r_runtime_1in3_isc_ack_cnt_upd;
  logic r_runtime_1in3_isc_ack_cnt_wr_enD;
  assign r_runtime_1in3_isc_ack_cnt_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RUNTIME_1IN3_ISC_ACK_CNT_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_isc_ack_cnt_wr_en <= 1'b0;
    end
    else begin
      r_runtime_1in3_isc_ack_cnt_wr_en <= r_runtime_1in3_isc_ack_cnt_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_isc_ack_cnt       <= runtime_1in3_isc_ack_cnt_default;
    end
    else begin
      r_runtime_1in3_isc_ack_cnt       <= r_runtime_1in3_isc_ack_cntD;
    end
  end
// Register FF: runtime_1in3_pem_load_info_0_pc0_0
  logic [REG_DATA_W-1:0] r_runtime_1in3_pem_load_info_0_pc0_0D;
  assign r_runtime_1in3_pem_load_info_0_pc0_0D       = r_runtime_1in3_pem_load_info_0_pc0_0_upd;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pem_load_info_0_pc0_0       <= runtime_1in3_pem_load_info_0_pc0_0_default;
    end
    else begin
      r_runtime_1in3_pem_load_info_0_pc0_0       <= r_runtime_1in3_pem_load_info_0_pc0_0D;
    end
  end
// Register FF: runtime_1in3_pem_load_info_0_pc0_1
  logic [REG_DATA_W-1:0] r_runtime_1in3_pem_load_info_0_pc0_1D;
  assign r_runtime_1in3_pem_load_info_0_pc0_1D       = r_runtime_1in3_pem_load_info_0_pc0_1_upd;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pem_load_info_0_pc0_1       <= runtime_1in3_pem_load_info_0_pc0_1_default;
    end
    else begin
      r_runtime_1in3_pem_load_info_0_pc0_1       <= r_runtime_1in3_pem_load_info_0_pc0_1D;
    end
  end
// Register FF: runtime_1in3_pem_load_info_0_pc0_2
  logic [REG_DATA_W-1:0] r_runtime_1in3_pem_load_info_0_pc0_2D;
  assign r_runtime_1in3_pem_load_info_0_pc0_2D       = r_runtime_1in3_pem_load_info_0_pc0_2_upd;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pem_load_info_0_pc0_2       <= runtime_1in3_pem_load_info_0_pc0_2_default;
    end
    else begin
      r_runtime_1in3_pem_load_info_0_pc0_2       <= r_runtime_1in3_pem_load_info_0_pc0_2D;
    end
  end
// Register FF: runtime_1in3_pem_load_info_0_pc0_3
  logic [REG_DATA_W-1:0] r_runtime_1in3_pem_load_info_0_pc0_3D;
  assign r_runtime_1in3_pem_load_info_0_pc0_3D       = r_runtime_1in3_pem_load_info_0_pc0_3_upd;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pem_load_info_0_pc0_3       <= runtime_1in3_pem_load_info_0_pc0_3_default;
    end
    else begin
      r_runtime_1in3_pem_load_info_0_pc0_3       <= r_runtime_1in3_pem_load_info_0_pc0_3D;
    end
  end
// Register FF: runtime_1in3_pem_load_info_0_pc1_0
  logic [REG_DATA_W-1:0] r_runtime_1in3_pem_load_info_0_pc1_0D;
  assign r_runtime_1in3_pem_load_info_0_pc1_0D       = r_runtime_1in3_pem_load_info_0_pc1_0_upd;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pem_load_info_0_pc1_0       <= runtime_1in3_pem_load_info_0_pc1_0_default;
    end
    else begin
      r_runtime_1in3_pem_load_info_0_pc1_0       <= r_runtime_1in3_pem_load_info_0_pc1_0D;
    end
  end
// Register FF: runtime_1in3_pem_load_info_0_pc1_1
  logic [REG_DATA_W-1:0] r_runtime_1in3_pem_load_info_0_pc1_1D;
  assign r_runtime_1in3_pem_load_info_0_pc1_1D       = r_runtime_1in3_pem_load_info_0_pc1_1_upd;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pem_load_info_0_pc1_1       <= runtime_1in3_pem_load_info_0_pc1_1_default;
    end
    else begin
      r_runtime_1in3_pem_load_info_0_pc1_1       <= r_runtime_1in3_pem_load_info_0_pc1_1D;
    end
  end
// Register FF: runtime_1in3_pem_load_info_0_pc1_2
  logic [REG_DATA_W-1:0] r_runtime_1in3_pem_load_info_0_pc1_2D;
  assign r_runtime_1in3_pem_load_info_0_pc1_2D       = r_runtime_1in3_pem_load_info_0_pc1_2_upd;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pem_load_info_0_pc1_2       <= runtime_1in3_pem_load_info_0_pc1_2_default;
    end
    else begin
      r_runtime_1in3_pem_load_info_0_pc1_2       <= r_runtime_1in3_pem_load_info_0_pc1_2D;
    end
  end
// Register FF: runtime_1in3_pem_load_info_0_pc1_3
  logic [REG_DATA_W-1:0] r_runtime_1in3_pem_load_info_0_pc1_3D;
  assign r_runtime_1in3_pem_load_info_0_pc1_3D       = r_runtime_1in3_pem_load_info_0_pc1_3_upd;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pem_load_info_0_pc1_3       <= runtime_1in3_pem_load_info_0_pc1_3_default;
    end
    else begin
      r_runtime_1in3_pem_load_info_0_pc1_3       <= r_runtime_1in3_pem_load_info_0_pc1_3D;
    end
  end
// Register FF: runtime_1in3_pem_load_info_1_pc0_lsb
  logic [REG_DATA_W-1:0] r_runtime_1in3_pem_load_info_1_pc0_lsbD;
  assign r_runtime_1in3_pem_load_info_1_pc0_lsbD       = r_runtime_1in3_pem_load_info_1_pc0_lsb_upd;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pem_load_info_1_pc0_lsb       <= runtime_1in3_pem_load_info_1_pc0_lsb_default;
    end
    else begin
      r_runtime_1in3_pem_load_info_1_pc0_lsb       <= r_runtime_1in3_pem_load_info_1_pc0_lsbD;
    end
  end
// Register FF: runtime_1in3_pem_load_info_1_pc0_msb
  logic [REG_DATA_W-1:0] r_runtime_1in3_pem_load_info_1_pc0_msbD;
  assign r_runtime_1in3_pem_load_info_1_pc0_msbD       = r_runtime_1in3_pem_load_info_1_pc0_msb_upd;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pem_load_info_1_pc0_msb       <= runtime_1in3_pem_load_info_1_pc0_msb_default;
    end
    else begin
      r_runtime_1in3_pem_load_info_1_pc0_msb       <= r_runtime_1in3_pem_load_info_1_pc0_msbD;
    end
  end
// Register FF: runtime_1in3_pem_load_info_1_pc1_lsb
  logic [REG_DATA_W-1:0] r_runtime_1in3_pem_load_info_1_pc1_lsbD;
  assign r_runtime_1in3_pem_load_info_1_pc1_lsbD       = r_runtime_1in3_pem_load_info_1_pc1_lsb_upd;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pem_load_info_1_pc1_lsb       <= runtime_1in3_pem_load_info_1_pc1_lsb_default;
    end
    else begin
      r_runtime_1in3_pem_load_info_1_pc1_lsb       <= r_runtime_1in3_pem_load_info_1_pc1_lsbD;
    end
  end
// Register FF: runtime_1in3_pem_load_info_1_pc1_msb
  logic [REG_DATA_W-1:0] r_runtime_1in3_pem_load_info_1_pc1_msbD;
  assign r_runtime_1in3_pem_load_info_1_pc1_msbD       = r_runtime_1in3_pem_load_info_1_pc1_msb_upd;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pem_load_info_1_pc1_msb       <= runtime_1in3_pem_load_info_1_pc1_msb_default;
    end
    else begin
      r_runtime_1in3_pem_load_info_1_pc1_msb       <= r_runtime_1in3_pem_load_info_1_pc1_msbD;
    end
  end
// Register FF: runtime_1in3_pem_store_info_0
  logic [REG_DATA_W-1:0] r_runtime_1in3_pem_store_info_0D;
  assign r_runtime_1in3_pem_store_info_0D       = r_runtime_1in3_pem_store_info_0_upd;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pem_store_info_0       <= runtime_1in3_pem_store_info_0_default;
    end
    else begin
      r_runtime_1in3_pem_store_info_0       <= r_runtime_1in3_pem_store_info_0D;
    end
  end
// Register FF: runtime_1in3_pem_store_info_1
  logic [REG_DATA_W-1:0] r_runtime_1in3_pem_store_info_1D;
  assign r_runtime_1in3_pem_store_info_1D       = r_runtime_1in3_pem_store_info_1_upd;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pem_store_info_1       <= runtime_1in3_pem_store_info_1_default;
    end
    else begin
      r_runtime_1in3_pem_store_info_1       <= r_runtime_1in3_pem_store_info_1D;
    end
  end
// Register FF: runtime_1in3_pem_store_info_2
  logic [REG_DATA_W-1:0] r_runtime_1in3_pem_store_info_2D;
  assign r_runtime_1in3_pem_store_info_2D       = r_runtime_1in3_pem_store_info_2_upd;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pem_store_info_2       <= runtime_1in3_pem_store_info_2_default;
    end
    else begin
      r_runtime_1in3_pem_store_info_2       <= r_runtime_1in3_pem_store_info_2D;
    end
  end
// Register FF: runtime_1in3_pem_store_info_3
  logic [REG_DATA_W-1:0] r_runtime_1in3_pem_store_info_3D;
  assign r_runtime_1in3_pem_store_info_3D       = r_runtime_1in3_pem_store_info_3_upd;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_runtime_1in3_pem_store_info_3       <= runtime_1in3_pem_store_info_3_default;
    end
    else begin
      r_runtime_1in3_pem_store_info_3       <= r_runtime_1in3_pem_store_info_3D;
    end
  end
// ============================================================================================== --
// Read reg
// ============================================================================================== --
  always_comb begin
    if (axil_rvalid) begin
      axil_rdataD = s_axil_rready ? '0 : axil_rdata;
      axil_rrespD = s_axil_rready ? '0 : axil_rresp;
    end
    else begin
      axil_rdataD = axil_rdata;
      axil_rrespD = axil_rresp;
      if (rd_en) begin
        if (!rd_en_ok) begin
          axil_rdataD = REG_DATA_W'('hDEAD_ADD2);
          axil_rrespD = AXI4_SLVERR;
        end
        else begin
          axil_rrespD = AXI4_OKAY;
          case(rd_add[AXIL_ADD_RANGE_W-1:0])
          ENTRY_PRC_1IN3_DUMMY_VAL0_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register entry_prc_1in3_dummy_val0
            axil_rdataD = entry_prc_1in3_dummy_val0_default;
          end
          ENTRY_PRC_1IN3_DUMMY_VAL1_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register entry_prc_1in3_dummy_val1
            axil_rdataD = entry_prc_1in3_dummy_val1_default;
          end
          ENTRY_PRC_1IN3_DUMMY_VAL2_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register entry_prc_1in3_dummy_val2
            axil_rdataD = entry_prc_1in3_dummy_val2_default;
          end
          ENTRY_PRC_1IN3_DUMMY_VAL3_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register entry_prc_1in3_dummy_val3
            axil_rdataD = entry_prc_1in3_dummy_val3_default;
          end
          STATUS_1IN3_ERROR_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register status_1in3_error
            axil_rdataD = r_status_1in3_error;
          end
          KSK_AVAIL_AVAIL_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register ksk_avail_avail
            axil_rdataD = r_ksk_avail_avail;
          end
          KSK_AVAIL_RESET_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register ksk_avail_reset
            axil_rdataD = r_ksk_avail_reset;
          end
          RUNTIME_1IN3_PEP_CMUX_LOOP_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pep_cmux_loop
            axil_rdataD = r_runtime_1in3_pep_cmux_loop;
          end
          RUNTIME_1IN3_PEP_POINTER_0_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pep_pointer_0
            axil_rdataD = r_runtime_1in3_pep_pointer_0;
          end
          RUNTIME_1IN3_PEP_POINTER_1_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pep_pointer_1
            axil_rdataD = r_runtime_1in3_pep_pointer_1;
          end
          RUNTIME_1IN3_PEP_POINTER_2_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pep_pointer_2
            axil_rdataD = r_runtime_1in3_pep_pointer_2;
          end
          RUNTIME_1IN3_ISC_LATEST_INSTRUCTION_0_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_isc_latest_instruction_0
            axil_rdataD = r_runtime_1in3_isc_latest_instruction_0;
          end
          RUNTIME_1IN3_ISC_LATEST_INSTRUCTION_1_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_isc_latest_instruction_1
            axil_rdataD = r_runtime_1in3_isc_latest_instruction_1;
          end
          RUNTIME_1IN3_ISC_LATEST_INSTRUCTION_2_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_isc_latest_instruction_2
            axil_rdataD = r_runtime_1in3_isc_latest_instruction_2;
          end
          RUNTIME_1IN3_ISC_LATEST_INSTRUCTION_3_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_isc_latest_instruction_3
            axil_rdataD = r_runtime_1in3_isc_latest_instruction_3;
          end
          RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_CNT_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pep_seq_bpip_batch_cnt
            axil_rdataD = r_runtime_1in3_pep_seq_bpip_batch_cnt;
          end
          RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FLUSH_CNT_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pep_seq_bpip_batch_flush_cnt
            axil_rdataD = r_runtime_1in3_pep_seq_bpip_batch_flush_cnt;
          end
          RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_TIMEOUT_CNT_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pep_seq_bpip_batch_timeout_cnt
            axil_rdataD = r_runtime_1in3_pep_seq_bpip_batch_timeout_cnt;
          end
          RUNTIME_1IN3_PEP_SEQ_BPIP_WAITING_BATCH_CNT_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pep_seq_bpip_waiting_batch_cnt
            axil_rdataD = r_runtime_1in3_pep_seq_bpip_waiting_batch_cnt;
          end
          RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_1_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pep_seq_bpip_batch_filling_cnt_1
            axil_rdataD = r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_1;
          end
          RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_2_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pep_seq_bpip_batch_filling_cnt_2
            axil_rdataD = r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_2;
          end
          RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_3_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pep_seq_bpip_batch_filling_cnt_3
            axil_rdataD = r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_3;
          end
          RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_4_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pep_seq_bpip_batch_filling_cnt_4
            axil_rdataD = r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_4;
          end
          RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_5_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pep_seq_bpip_batch_filling_cnt_5
            axil_rdataD = r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_5;
          end
          RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_6_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pep_seq_bpip_batch_filling_cnt_6
            axil_rdataD = r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_6;
          end
          RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_7_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pep_seq_bpip_batch_filling_cnt_7
            axil_rdataD = r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_7;
          end
          RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_8_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pep_seq_bpip_batch_filling_cnt_8
            axil_rdataD = r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_8;
          end
          RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_9_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pep_seq_bpip_batch_filling_cnt_9
            axil_rdataD = r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_9;
          end
          RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_10_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pep_seq_bpip_batch_filling_cnt_10
            axil_rdataD = r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_10;
          end
          RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_11_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pep_seq_bpip_batch_filling_cnt_11
            axil_rdataD = r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_11;
          end
          RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_12_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pep_seq_bpip_batch_filling_cnt_12
            axil_rdataD = r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_12;
          end
          RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_13_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pep_seq_bpip_batch_filling_cnt_13
            axil_rdataD = r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_13;
          end
          RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_14_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pep_seq_bpip_batch_filling_cnt_14
            axil_rdataD = r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_14;
          end
          RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_15_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pep_seq_bpip_batch_filling_cnt_15
            axil_rdataD = r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_15;
          end
          RUNTIME_1IN3_PEP_SEQ_BPIP_BATCH_FILLING_CNT_16_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pep_seq_bpip_batch_filling_cnt_16
            axil_rdataD = r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_16;
          end
          RUNTIME_1IN3_PEP_SEQ_LD_ACK_CNT_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pep_seq_ld_ack_cnt
            axil_rdataD = r_runtime_1in3_pep_seq_ld_ack_cnt;
          end
          RUNTIME_1IN3_PEP_SEQ_CMUX_NOT_FULL_BATCH_CNT_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pep_seq_cmux_not_full_batch_cnt
            axil_rdataD = r_runtime_1in3_pep_seq_cmux_not_full_batch_cnt;
          end
          RUNTIME_1IN3_PEP_SEQ_IPIP_FLUSH_CNT_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pep_seq_ipip_flush_cnt
            axil_rdataD = r_runtime_1in3_pep_seq_ipip_flush_cnt;
          end
          RUNTIME_1IN3_PEP_LDB_RCP_DUR_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pep_ldb_rcp_dur
            axil_rdataD = r_runtime_1in3_pep_ldb_rcp_dur;
          end
          RUNTIME_1IN3_PEP_LDG_REQ_DUR_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pep_ldg_req_dur
            axil_rdataD = r_runtime_1in3_pep_ldg_req_dur;
          end
          RUNTIME_1IN3_PEP_LDG_RCP_DUR_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pep_ldg_rcp_dur
            axil_rdataD = r_runtime_1in3_pep_ldg_rcp_dur;
          end
          RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC0_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pep_load_ksk_rcp_dur_pc0
            axil_rdataD = r_runtime_1in3_pep_load_ksk_rcp_dur_pc0;
          end
          RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC1_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pep_load_ksk_rcp_dur_pc1
            axil_rdataD = r_runtime_1in3_pep_load_ksk_rcp_dur_pc1;
          end
          RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC2_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pep_load_ksk_rcp_dur_pc2
            axil_rdataD = r_runtime_1in3_pep_load_ksk_rcp_dur_pc2;
          end
          RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC3_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pep_load_ksk_rcp_dur_pc3
            axil_rdataD = r_runtime_1in3_pep_load_ksk_rcp_dur_pc3;
          end
          RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC4_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pep_load_ksk_rcp_dur_pc4
            axil_rdataD = r_runtime_1in3_pep_load_ksk_rcp_dur_pc4;
          end
          RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC5_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pep_load_ksk_rcp_dur_pc5
            axil_rdataD = r_runtime_1in3_pep_load_ksk_rcp_dur_pc5;
          end
          RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC6_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pep_load_ksk_rcp_dur_pc6
            axil_rdataD = r_runtime_1in3_pep_load_ksk_rcp_dur_pc6;
          end
          RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC7_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pep_load_ksk_rcp_dur_pc7
            axil_rdataD = r_runtime_1in3_pep_load_ksk_rcp_dur_pc7;
          end
          RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC8_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pep_load_ksk_rcp_dur_pc8
            axil_rdataD = r_runtime_1in3_pep_load_ksk_rcp_dur_pc8;
          end
          RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC9_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pep_load_ksk_rcp_dur_pc9
            axil_rdataD = r_runtime_1in3_pep_load_ksk_rcp_dur_pc9;
          end
          RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC10_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pep_load_ksk_rcp_dur_pc10
            axil_rdataD = r_runtime_1in3_pep_load_ksk_rcp_dur_pc10;
          end
          RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC11_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pep_load_ksk_rcp_dur_pc11
            axil_rdataD = r_runtime_1in3_pep_load_ksk_rcp_dur_pc11;
          end
          RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC12_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pep_load_ksk_rcp_dur_pc12
            axil_rdataD = r_runtime_1in3_pep_load_ksk_rcp_dur_pc12;
          end
          RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC13_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pep_load_ksk_rcp_dur_pc13
            axil_rdataD = r_runtime_1in3_pep_load_ksk_rcp_dur_pc13;
          end
          RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC14_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pep_load_ksk_rcp_dur_pc14
            axil_rdataD = r_runtime_1in3_pep_load_ksk_rcp_dur_pc14;
          end
          RUNTIME_1IN3_PEP_LOAD_KSK_RCP_DUR_PC15_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pep_load_ksk_rcp_dur_pc15
            axil_rdataD = r_runtime_1in3_pep_load_ksk_rcp_dur_pc15;
          end
          RUNTIME_1IN3_PEP_MMACC_SXT_RCP_DUR_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pep_mmacc_sxt_rcp_dur
            axil_rdataD = r_runtime_1in3_pep_mmacc_sxt_rcp_dur;
          end
          RUNTIME_1IN3_PEP_MMACC_SXT_REQ_DUR_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pep_mmacc_sxt_req_dur
            axil_rdataD = r_runtime_1in3_pep_mmacc_sxt_req_dur;
          end
          RUNTIME_1IN3_PEP_MMACC_SXT_CMD_WAIT_B_DUR_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pep_mmacc_sxt_cmd_wait_b_dur
            axil_rdataD = r_runtime_1in3_pep_mmacc_sxt_cmd_wait_b_dur;
          end
          RUNTIME_1IN3_PEP_INST_CNT_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pep_inst_cnt
            axil_rdataD = r_runtime_1in3_pep_inst_cnt;
          end
          RUNTIME_1IN3_PEP_ACK_CNT_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pep_ack_cnt
            axil_rdataD = r_runtime_1in3_pep_ack_cnt;
          end
          RUNTIME_1IN3_PEM_LOAD_INST_CNT_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pem_load_inst_cnt
            axil_rdataD = r_runtime_1in3_pem_load_inst_cnt;
          end
          RUNTIME_1IN3_PEM_LOAD_ACK_CNT_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pem_load_ack_cnt
            axil_rdataD = r_runtime_1in3_pem_load_ack_cnt;
          end
          RUNTIME_1IN3_PEM_STORE_INST_CNT_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pem_store_inst_cnt
            axil_rdataD = r_runtime_1in3_pem_store_inst_cnt;
          end
          RUNTIME_1IN3_PEM_STORE_ACK_CNT_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pem_store_ack_cnt
            axil_rdataD = r_runtime_1in3_pem_store_ack_cnt;
          end
          RUNTIME_1IN3_PEA_INST_CNT_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pea_inst_cnt
            axil_rdataD = r_runtime_1in3_pea_inst_cnt;
          end
          RUNTIME_1IN3_PEA_ACK_CNT_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pea_ack_cnt
            axil_rdataD = r_runtime_1in3_pea_ack_cnt;
          end
          RUNTIME_1IN3_ISC_INST_CNT_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_isc_inst_cnt
            axil_rdataD = r_runtime_1in3_isc_inst_cnt;
          end
          RUNTIME_1IN3_ISC_ACK_CNT_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_isc_ack_cnt
            axil_rdataD = r_runtime_1in3_isc_ack_cnt;
          end
          RUNTIME_1IN3_PEM_LOAD_INFO_0_PC0_0_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pem_load_info_0_pc0_0
            axil_rdataD = r_runtime_1in3_pem_load_info_0_pc0_0;
          end
          RUNTIME_1IN3_PEM_LOAD_INFO_0_PC0_1_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pem_load_info_0_pc0_1
            axil_rdataD = r_runtime_1in3_pem_load_info_0_pc0_1;
          end
          RUNTIME_1IN3_PEM_LOAD_INFO_0_PC0_2_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pem_load_info_0_pc0_2
            axil_rdataD = r_runtime_1in3_pem_load_info_0_pc0_2;
          end
          RUNTIME_1IN3_PEM_LOAD_INFO_0_PC0_3_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pem_load_info_0_pc0_3
            axil_rdataD = r_runtime_1in3_pem_load_info_0_pc0_3;
          end
          RUNTIME_1IN3_PEM_LOAD_INFO_0_PC1_0_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pem_load_info_0_pc1_0
            axil_rdataD = r_runtime_1in3_pem_load_info_0_pc1_0;
          end
          RUNTIME_1IN3_PEM_LOAD_INFO_0_PC1_1_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pem_load_info_0_pc1_1
            axil_rdataD = r_runtime_1in3_pem_load_info_0_pc1_1;
          end
          RUNTIME_1IN3_PEM_LOAD_INFO_0_PC1_2_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pem_load_info_0_pc1_2
            axil_rdataD = r_runtime_1in3_pem_load_info_0_pc1_2;
          end
          RUNTIME_1IN3_PEM_LOAD_INFO_0_PC1_3_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pem_load_info_0_pc1_3
            axil_rdataD = r_runtime_1in3_pem_load_info_0_pc1_3;
          end
          RUNTIME_1IN3_PEM_LOAD_INFO_1_PC0_LSB_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pem_load_info_1_pc0_lsb
            axil_rdataD = r_runtime_1in3_pem_load_info_1_pc0_lsb;
          end
          RUNTIME_1IN3_PEM_LOAD_INFO_1_PC0_MSB_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pem_load_info_1_pc0_msb
            axil_rdataD = r_runtime_1in3_pem_load_info_1_pc0_msb;
          end
          RUNTIME_1IN3_PEM_LOAD_INFO_1_PC1_LSB_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pem_load_info_1_pc1_lsb
            axil_rdataD = r_runtime_1in3_pem_load_info_1_pc1_lsb;
          end
          RUNTIME_1IN3_PEM_LOAD_INFO_1_PC1_MSB_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pem_load_info_1_pc1_msb
            axil_rdataD = r_runtime_1in3_pem_load_info_1_pc1_msb;
          end
          RUNTIME_1IN3_PEM_STORE_INFO_0_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pem_store_info_0
            axil_rdataD = r_runtime_1in3_pem_store_info_0;
          end
          RUNTIME_1IN3_PEM_STORE_INFO_1_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pem_store_info_1
            axil_rdataD = r_runtime_1in3_pem_store_info_1;
          end
          RUNTIME_1IN3_PEM_STORE_INFO_2_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pem_store_info_2
            axil_rdataD = r_runtime_1in3_pem_store_info_2;
          end
          RUNTIME_1IN3_PEM_STORE_INFO_3_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register runtime_1in3_pem_store_info_3
            axil_rdataD = r_runtime_1in3_pem_store_info_3;
          end
          default:
            axil_rdataD = REG_DATA_W'('h0BAD_ADD1); // Default value
          endcase // rd_add
        end
      end // if rd_end
    end
  end // always_comb - read
endmodule
