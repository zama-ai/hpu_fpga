// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Axi4-lite register bank
// ----------------------------------------------------------------------------------------------
// For prc_clk part 1in3
// ==============================================================================================

module hpu_regif_prc_1in3
  import axi_if_common_param_pkg::*;
  import axi_if_shell_axil_pkg::*;
  import top_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import pem_common_param_pkg::*;
  import pea_common_param_pkg::*;
  import hpu_regif_core_prc_1in3_pkg::*;
  import isc_common_param_pkg::*;
#(
  parameter int ERROR_NB = 10
)
(
  input  logic                           prc_clk,
  input  logic                           prc_srst_n,
  // Axi4 lite Slave Interface sAxi4
  input  logic [AXIL_ADD_W-1:0]          s_axil_awaddr,
  input  logic                           s_axil_awvalid,
  output logic                           s_axil_awready,
  input  logic [AXIL_DATA_W-1:0]         s_axil_wdata,
  input  logic                           s_axil_wvalid,
  output logic                           s_axil_wready,
  output logic [AXI4_RESP_W-1:0]         s_axil_bresp,
  output logic                           s_axil_bvalid,
  input  logic                           s_axil_bready,
  input  logic [AXIL_ADD_W-1:0]          s_axil_araddr,
  input  logic                           s_axil_arvalid,
  output logic                           s_axil_arready,
  output logic [AXIL_DATA_W-1:0]         s_axil_rdata,
  output logic [AXI4_RESP_W-1:0]         s_axil_rresp,
  output logic                           s_axil_rvalid,
  input  logic                           s_axil_rready,

  // KSK
  output logic                                                      ksk_mem_avail,

  output logic                                                      reset_ksk_cache,
  input  logic                                                      reset_ksk_cache_done,
  output logic                                                      reset_cache,

  // Register IO: runtime_1in3
  // -> info
  input  pep_info_t                                                 pep_info,
  input  isc_info_t                                                 isc_info,
  input  pem_info_t                                                 pem_info,
  // -> error
  input  logic [ERROR_NB-1:0]                                       error, // TOREVIEW : to complete if needed
  // Register IO: Counter
  input  pep_counter_inc_t                                          pep_counter_inc,
  input  pem_counter_inc_t                                          pem_counter_inc,
  input  pea_counter_inc_t                                          pea_counter_inc,
  input  isc_counter_inc_t                                          isc_counter_inc

);
// ============================================================================================== --
// localparam
// ============================================================================================== --
  // Current design supports KSK_PC_MAX up to 16.
  localparam int KSK_PC_MAX_L    = 16;

  localparam int REQ_ACK_NB      = 1; // reset_cache for KSK
  localparam int REQ_ACK_KSK_OFS = 0;

  // counter over REG_DATA_W
  localparam int SINGLE_COUNTER_NB      = SEQ_COUNTER_INC_W // PEP sequencer
                                          + 5 * 2; // PEP, PEM_ST, PEM_LD, PEA, ISC (inst + ack)
  // counter over 2*REG_DATA_W
  localparam int DOUBLE_COUNTER_NB      = 0;
  // counter of a duration : number of cycle the signal is 1
  localparam int DURATION_COUNTER_NB    =   LD_COUNTER_INC_W
                                          + KEY_COUNTER_INC_W
                                          + MMACC_COUNTER_INC_W
                                          + KSK_PC_MAX_L;
  localparam int POSEDGE_COUNTER_NB     = 0; // posedge counter

  // TODO define here the offset of each input
  localparam int SGCNT_PEP_SEQ_BPIP_BATCH_OFS          = 0;
  localparam int SGCNT_PEP_SEQ_BPIP_BATCH_FLUSH_OFS    = SGCNT_PEP_SEQ_BPIP_BATCH_OFS         +1;
  localparam int SGCNT_PEP_SEQ_BPIP_BATCH_TIMEOUT_OFS  = SGCNT_PEP_SEQ_BPIP_BATCH_FLUSH_OFS   +1;
  localparam int SGCNT_PEP_SEQ_BPIP_WAITING_BATCH_OFS  = SGCNT_PEP_SEQ_BPIP_BATCH_TIMEOUT_OFS +1;
  localparam int SGCNT_PEP_SEQ_BPIP_BATCH_FILLING_OFS  = SGCNT_PEP_SEQ_BPIP_WAITING_BATCH_OFS +1;
  localparam int SGCNT_PEP_SEQ_LD_ACK_OFS              = SGCNT_PEP_SEQ_BPIP_BATCH_FILLING_OFS +BATCH_PBS_NB;
  localparam int SGCNT_PEP_SEQ_CMUX_NOT_FULL_BATCH_OFS = SGCNT_PEP_SEQ_LD_ACK_OFS             +1;
  localparam int SGCNT_PEP_SEQ_IPIP_FLUSH_OFS          = SGCNT_PEP_SEQ_CMUX_NOT_FULL_BATCH_OFS+1;
  localparam int SGCNT_PEP_INST_OFS                    = SGCNT_PEP_SEQ_IPIP_FLUSH_OFS         +1;
  localparam int SGCNT_PEP_ACK_OFS                     = SGCNT_PEP_INST_OFS                   +1;
  localparam int SGCNT_PEM_LD_INST_OFS                 = SGCNT_PEP_ACK_OFS                    +1;
  localparam int SGCNT_PEM_LD_ACK_OFS                  = SGCNT_PEM_LD_INST_OFS                +1;
  localparam int SGCNT_PEM_ST_INST_OFS                 = SGCNT_PEM_LD_ACK_OFS                 +1;
  localparam int SGCNT_PEM_ST_ACK_OFS                  = SGCNT_PEM_ST_INST_OFS                +1;
  localparam int SGCNT_PEA_INST_OFS                    = SGCNT_PEM_ST_ACK_OFS                 +1;
  localparam int SGCNT_PEA_ACK_OFS                     = SGCNT_PEA_INST_OFS                   +1;
  localparam int SGCNT_ISC_INST_OFS                    = SGCNT_PEA_ACK_OFS                    +1;
  localparam int SGCNT_ISC_ACK_OFS                     = SGCNT_ISC_INST_OFS                   +1;

  localparam int DRCNT_PEP_LD_LDB_RCP_OFS           = 0;
  localparam int DRCNT_PEP_LD_LDG_REQ_OFS           = DRCNT_PEP_LD_LDB_RCP_OFS          +1;
  localparam int DRCNT_PEP_LD_LDG_RCP_OFS           = DRCNT_PEP_LD_LDG_REQ_OFS          +1;
  localparam int DRCNT_PEP_MMACC_SXT_REQ_OFS        = DRCNT_PEP_LD_LDG_RCP_OFS          +1;
  localparam int DRCNT_PEP_MMACC_SXT_RCP_OFS        = DRCNT_PEP_MMACC_SXT_REQ_OFS       +1;
  localparam int DRCNT_PEP_MMACC_SXT_CMD_WAIT_B_OFS = DRCNT_PEP_MMACC_SXT_RCP_OFS       +1;
  localparam int DRCNT_PEP_LOAD_KSK_RCP_OFS         = DRCNT_PEP_MMACC_SXT_CMD_WAIT_B_OFS+1;
  // Next offset will be at DRCNT_PEP_LOAD_KSK_RCP_OFS DRCNT_PEP_LOAD_KSK_RCP_OFS       + KSK_PC_MAX_L

// ============================================================================================== --
// signals
// ============================================================================================== --
  logic [REG_DATA_W-1:0]                             r_wr_data;

  logic [REQ_ACK_NB-1:0][REG_DATA_W-1:0]             r_req_ack_upd;
  logic [REQ_ACK_NB-1:0]                             r_req_ack_wr_en;

  logic [REQ_ACK_NB-1:0]                             req_cmd;
  logic [REQ_ACK_NB-1:0]                             ack_rsp;

  logic [REG_DATA_W-1:0]                             r_error_upd;
  logic                                              r_error_wr_en;

  logic [SINGLE_COUNTER_NB-1:0][REG_DATA_W-1:0]      r_sg_counter_upd;
  logic [SINGLE_COUNTER_NB-1:0]                      r_sg_counter_wr_en;

  logic [DOUBLE_COUNTER_NB-1:0][1:0][REG_DATA_W-1:0] r_db_counter_upd;
  logic [DOUBLE_COUNTER_NB-1:0][1:0]                 r_db_counter_wr_en;

  logic [DURATION_COUNTER_NB-1:0][REG_DATA_W-1:0]    r_dr_counter_upd;
  logic [DURATION_COUNTER_NB-1:0]                    r_dr_counter_wr_en;

  logic [POSEDGE_COUNTER_NB-1:0][REG_DATA_W-1:0]     r_ps_counter_upd;
  logic [POSEDGE_COUNTER_NB-1:0]                     r_ps_counter_wr_en;

  logic [SINGLE_COUNTER_NB-1:0]                      sg_inc;
  logic [DOUBLE_COUNTER_NB-1:0]                      db_inc;
  logic [DURATION_COUNTER_NB-1:0]                    dr_inc;
  logic [POSEDGE_COUNTER_NB-1:0]                     ps_inc;

  logic [16-1:0][REG_DATA_W-1:0]                     r_sg_counter_bpip_batch_filling_upd;
  logic [16-1:0]                                     r_sg_counter_bpip_batch_filling_wr_en;

// ============================================================================================== --
// Input pipe
// ============================================================================================== --
  pep_info_t            in_pep_info;
  isc_info_t            in_isc_info;
  pem_info_t            in_pem_info;
  pep_counter_inc_t     in_pep_counter_inc;
  pem_counter_inc_t     in_pem_counter_inc;
  pea_counter_inc_t     in_pea_counter_inc;
  isc_counter_inc_t     in_isc_counter_inc;
  logic [ERROR_NB-1: 0] in_error;

  always_ff @(posedge prc_clk)
    if (!prc_srst_n) begin
      in_error           <= '0;
      in_pep_counter_inc <= '0;
      in_pem_counter_inc <= '0;
      in_pea_counter_inc <= '0;
      in_isc_counter_inc <= '0;
    end
    else begin
      in_error           <= error          ;
      in_pep_counter_inc <= pep_counter_inc;
      in_pem_counter_inc <= pem_counter_inc;
      in_pea_counter_inc <= pea_counter_inc;
      in_isc_counter_inc <= isc_counter_inc;
    end

  always_ff @(posedge prc_clk) begin
    in_pep_info <= pep_info;
    in_isc_info <= isc_info;
    in_pem_info <= pem_info;
  end

// ============================================================================================== --
// hpu_regif_req_ack
// ============================================================================================== --
  assign reset_ksk_cache = req_cmd[REQ_ACK_KSK_OFS];
  assign ack_rsp[REQ_ACK_KSK_OFS] = reset_ksk_cache_done;
  hpu_regif_req_ack
  #(
     .IN_NB       (REQ_ACK_NB),
     .REG_DATA_W  (REG_DATA_W)
  ) hpu_regif_req_ack (
    .clk             (prc_clk),
    .s_rst_n         (prc_srst_n),

    .r_req_ack_upd   (r_req_ack_upd),
    .r_req_ack_wr_en (r_req_ack_wr_en),
    .r_wr_data       (r_wr_data),

    .req_cmd         (req_cmd),
    .ack_rsp         (ack_rsp)
  );

// ============================================================================================== --
// hpu_regif_error_manager
// ============================================================================================== --
  hpu_regif_error_manager
  #(
     .IN_NB       (ERROR_NB),
     .REG_DATA_W  (REG_DATA_W)
  ) pbs_hpu_regif_error_manager (
    .clk           (prc_clk),
    .s_rst_n       (prc_srst_n),

    .r_error_upd   (r_error_upd),
    .r_error_wr_en (r_error_wr_en),
    .r_wr_data     (r_wr_data),

    .error         (in_error)
  );

// TODO : complete here with other errors

// ============================================================================================== --
// hpu_reg_if_counter_manager
// ============================================================================================== --
  assign sg_inc[SGCNT_PEP_SEQ_BPIP_BATCH_OFS]          = in_pep_counter_inc.seq.bpip_batch_inc;
  assign sg_inc[SGCNT_PEP_SEQ_BPIP_BATCH_FLUSH_OFS]    = in_pep_counter_inc.seq.bpip_batch_flush_inc;
  assign sg_inc[SGCNT_PEP_SEQ_BPIP_BATCH_TIMEOUT_OFS]  = in_pep_counter_inc.seq.bpip_batch_timeout_inc;
  assign sg_inc[SGCNT_PEP_SEQ_BPIP_WAITING_BATCH_OFS]  = in_pep_counter_inc.seq.bpip_waiting_batch_inc;
  assign sg_inc[SGCNT_PEP_SEQ_BPIP_BATCH_FILLING_OFS+:BATCH_PBS_NB] = in_pep_counter_inc.seq.bpip_batch_filling_inc;
  assign sg_inc[SGCNT_PEP_SEQ_LD_ACK_OFS]              = in_pep_counter_inc.seq.load_ack_inc;
  assign sg_inc[SGCNT_PEP_SEQ_CMUX_NOT_FULL_BATCH_OFS] = in_pep_counter_inc.seq.cmux_not_full_batch_inc;
  assign sg_inc[SGCNT_PEP_SEQ_IPIP_FLUSH_OFS]          = in_pep_counter_inc.seq.ipip_flush_inc;
  assign sg_inc[SGCNT_PEP_INST_OFS]                    = in_pep_counter_inc.common.inst_inc;
  assign sg_inc[SGCNT_PEP_ACK_OFS]                     = in_pep_counter_inc.common.ack_inc;
  assign sg_inc[SGCNT_PEM_LD_INST_OFS]                 = in_pem_counter_inc.load.inst_inc;
  assign sg_inc[SGCNT_PEM_LD_ACK_OFS]                  = in_pem_counter_inc.load.ack_inc;
  assign sg_inc[SGCNT_PEM_ST_INST_OFS]                 = in_pem_counter_inc.store.inst_inc;
  assign sg_inc[SGCNT_PEM_ST_ACK_OFS]                  = in_pem_counter_inc.store.ack_inc;
  assign sg_inc[SGCNT_PEA_INST_OFS]                    = in_pea_counter_inc.inst_inc;
  assign sg_inc[SGCNT_PEA_ACK_OFS]                     = in_pea_counter_inc.ack_inc;
  assign sg_inc[SGCNT_ISC_INST_OFS]                    = in_isc_counter_inc.inst_inc;
  assign sg_inc[SGCNT_ISC_ACK_OFS]                     = in_isc_counter_inc.ack_inc;

  assign dr_inc[DRCNT_PEP_LD_LDG_RCP_OFS]              = in_pep_counter_inc.ld.ldg.rcp_dur;
  assign dr_inc[DRCNT_PEP_LD_LDG_REQ_OFS]              = in_pep_counter_inc.ld.ldg.req_dur;
  assign dr_inc[DRCNT_PEP_LD_LDB_RCP_OFS]              = in_pep_counter_inc.ld.ldb.rcp_dur;
  assign dr_inc[DRCNT_PEP_MMACC_SXT_CMD_WAIT_B_OFS]    = in_pep_counter_inc.mmacc.sxt_cmd_wait_b_dur;
  assign dr_inc[DRCNT_PEP_MMACC_SXT_RCP_OFS]           = in_pep_counter_inc.mmacc.sxt_rcp_dur;
  assign dr_inc[DRCNT_PEP_MMACC_SXT_REQ_OFS]           = in_pep_counter_inc.mmacc.sxt_req_dur;

  always_comb begin
    for (int i=0; i<KSK_PC_MAX; i=i+1)
      dr_inc[DRCNT_PEP_LOAD_KSK_RCP_OFS+i]        = in_pep_counter_inc.key.load_ksk_dur[i];
    for (int i=KSK_PC_MAX; i<KSK_PC_MAX_L; i=i+1)
      dr_inc[DRCNT_PEP_LOAD_KSK_RCP_OFS+i]        = 1'b0;
  end

  // TODO : add counters here

  hpu_regfile_counter_manager
  #(
     .SINGLE_NB       (SINGLE_COUNTER_NB),
     .DOUBLE_NB       (DOUBLE_COUNTER_NB),
     .DURATION_NB     (DURATION_COUNTER_NB),
     .POSEDGE_NB      (POSEDGE_COUNTER_NB),
     .REG_DATA_W      (REG_DATA_W)
  ) hpu_regfile_counter_manager (
    .clk                (prc_clk),
    .s_rst_n            (prc_srst_n),

    .r_sg_counter_upd   (r_sg_counter_upd),
    .r_sg_counter_wr_en (r_sg_counter_wr_en),

    .r_db_counter_upd   (r_db_counter_upd),
    .r_db_counter_wr_en (r_db_counter_wr_en),

    .r_dr_counter_upd   (r_dr_counter_upd),
    .r_dr_counter_wr_en (r_dr_counter_wr_en),

    .r_ps_counter_upd   (r_ps_counter_upd),
    .r_ps_counter_wr_en (r_ps_counter_wr_en),

    .r_wr_data          (r_wr_data),

    .sg_inc             (sg_inc),
    .db_inc             (db_inc),
    .dr_inc             (dr_inc),
    .ps_inc             (ps_inc)
  );

// ============================================================================================== --
// hpu_regif_core
// ============================================================================================== --
  ksk_avail_avail_t         r_ksk_avail_avail;

  // For register update
  runtime_1in3_pep_cmux_loop_t r_runtime_1in3_pep_cmux_loop_upd;
  runtime_1in3_pep_pointer_0_t r_runtime_1in3_pep_pointer_0_upd;
  runtime_1in3_pep_pointer_1_t r_runtime_1in3_pep_pointer_1_upd;
  runtime_1in3_pep_pointer_2_t r_runtime_1in3_pep_pointer_2_upd;

  runtime_1in3_pem_store_info_0_t r_runtime_1in3_pem_store_info_0_upd;
  runtime_1in3_pem_store_info_1_t r_runtime_1in3_pem_store_info_1_upd;
  runtime_1in3_pem_store_info_2_t r_runtime_1in3_pem_store_info_2_upd;
  runtime_1in3_pem_store_info_3_t r_runtime_1in3_pem_store_info_3_upd;

  // Extract fields
  assign ksk_mem_avail = r_ksk_avail_avail.avail;

  // Set fields
  assign r_runtime_1in3_pep_cmux_loop_upd.br_loop       = in_pep_info.seq.br_loop   ;
  assign r_runtime_1in3_pep_cmux_loop_upd.br_loop_c     = in_pep_info.seq.br_loop_c ;
  assign r_runtime_1in3_pep_cmux_loop_upd.ks_loop       = in_pep_info.seq.ks_loop   ;
  assign r_runtime_1in3_pep_cmux_loop_upd.ks_loop_c     = in_pep_info.seq.ks_loop_c ;
  assign r_runtime_1in3_pep_pointer_0_upd.pool_rp   = in_pep_info.seq.pool_rp   ;
  assign r_runtime_1in3_pep_pointer_0_upd.pool_wp   = in_pep_info.seq.pool_wp   ;
  assign r_runtime_1in3_pep_pointer_0_upd.ldg_pt    = in_pep_info.seq.ldg_pt    ;
  assign r_runtime_1in3_pep_pointer_0_upd.ldb_pt    = in_pep_info.seq.ldb_pt    ;
  assign r_runtime_1in3_pep_pointer_1_upd.ks_in_rp  = in_pep_info.seq.ks_in_rp  ;
  assign r_runtime_1in3_pep_pointer_1_upd.ks_in_wp  = in_pep_info.seq.ks_in_wp  ;
  assign r_runtime_1in3_pep_pointer_1_upd.ks_out_rp = in_pep_info.seq.ks_out_rp ;
  assign r_runtime_1in3_pep_pointer_1_upd.ks_out_wp = in_pep_info.seq.ks_out_wp ;
  assign r_runtime_1in3_pep_pointer_2_upd.pbs_in_rp = in_pep_info.seq.pbs_in_rp ;
  assign r_runtime_1in3_pep_pointer_2_upd.pbs_in_wp = in_pep_info.seq.pbs_in_wp ;
  assign r_runtime_1in3_pep_pointer_2_upd.ipip_flush_last_pbs_in_loop = in_pep_info.seq.ipip_flush_last_pbs_in_loop;

  assign r_runtime_1in3_pem_store_info_0_upd.cmd_vld             = in_pem_info.store.cmd_vld            ;
  assign r_runtime_1in3_pem_store_info_0_upd.cmd_rdy             = in_pem_info.store.cmd_rdy            ;
  assign r_runtime_1in3_pem_store_info_0_upd.pem_regf_rd_req_vld = in_pem_info.store.pem_regf_rd_req_vld;
  assign r_runtime_1in3_pem_store_info_0_upd.pem_regf_rd_req_rdy = in_pem_info.store.pem_regf_rd_req_rdy;
  assign r_runtime_1in3_pem_store_info_0_upd.brsp_fifo_in_vld    = in_pem_info.store.brsp_fifo_in_vld   ;
  assign r_runtime_1in3_pem_store_info_0_upd.brsp_fifo_in_rdy    = in_pem_info.store.brsp_fifo_in_rdy   ;
  assign r_runtime_1in3_pem_store_info_0_upd.rcp_fifo_in_vld     = in_pem_info.store.rcp_fifo_in_vld    ;
  assign r_runtime_1in3_pem_store_info_0_upd.rcp_fifo_in_rdy     = in_pem_info.store.rcp_fifo_in_rdy    ;
  assign r_runtime_1in3_pem_store_info_0_upd.r2_axi_vld          = in_pem_info.store.r2_axi_vld         ;
  assign r_runtime_1in3_pem_store_info_0_upd.r2_axi_rdy          = in_pem_info.store.r2_axi_rdy         ;
  assign r_runtime_1in3_pem_store_info_0_upd.c0_enough_location  = in_pem_info.store.c0_enough_location ;

  assign r_runtime_1in3_pem_store_info_1_upd.s0_cmd_vld    = in_pem_info.store.s0_cmd_vld   ;
  assign r_runtime_1in3_pem_store_info_1_upd.s0_cmd_rdy    = in_pem_info.store.s0_cmd_rdy   ;
  assign r_runtime_1in3_pem_store_info_1_upd.m_axi_bvalid  = in_pem_info.store.m_axi4_bvalid ;
  assign r_runtime_1in3_pem_store_info_1_upd.m_axi_bready  = in_pem_info.store.m_axi4_bready ;
  assign r_runtime_1in3_pem_store_info_1_upd.m_axi_wvalid  = in_pem_info.store.m_axi4_wvalid ;
  assign r_runtime_1in3_pem_store_info_1_upd.m_axi_wready  = in_pem_info.store.m_axi4_wready ;
  assign r_runtime_1in3_pem_store_info_1_upd.m_axi_awvalid = in_pem_info.store.m_axi4_awvalid;
  assign r_runtime_1in3_pem_store_info_1_upd.m_axi_awready = in_pem_info.store.m_axi4_awready;

  assign r_runtime_1in3_pem_store_info_2_upd.c0_free_loc_cnt = in_pem_info.store.c0_free_loc_cnt;
  assign r_runtime_1in3_pem_store_info_2_upd.brsp_bresp_cnt  = in_pem_info.store.brsp_bresp_cnt ;

  assign r_runtime_1in3_pem_store_info_3_upd.brsp_ack_seen = in_pem_info.store.brsp_ack_seen;
  assign r_runtime_1in3_pem_store_info_3_upd.c0_cmd_cnt    = in_pem_info.store.c0_cmd_cnt   ;

  // Extend
  always_comb begin
    r_sg_counter_bpip_batch_filling_upd   = '0;
    for (int i=0; i<BATCH_PBS_NB; i=i+1) begin
      r_sg_counter_bpip_batch_filling_upd[i]                     = r_sg_counter_upd[SGCNT_PEP_SEQ_BPIP_BATCH_FILLING_OFS+i];
      r_sg_counter_wr_en[SGCNT_PEP_SEQ_BPIP_BATCH_FILLING_OFS+i] = r_sg_counter_bpip_batch_filling_wr_en[i];
    end
  end

  hpu_regif_core_prc_1in3
  hpu_regif_core_prc_1in3 (
      .clk                       (prc_clk),
      .s_rst_n                   (prc_srst_n),

      // Axi lite interface
      .s_axil_awaddr             (s_axil_awaddr),
      .s_axil_awvalid            (s_axil_awvalid),
      .s_axil_awready            (s_axil_awready),
      .s_axil_wdata              (s_axil_wdata),
      .s_axil_wvalid             (s_axil_wvalid),
      .s_axil_wready             (s_axil_wready),
      .s_axil_bresp              (s_axil_bresp),
      .s_axil_bvalid             (s_axil_bvalid),
      .s_axil_bready             (s_axil_bready),
      .s_axil_araddr             (s_axil_araddr),
      .s_axil_arvalid            (s_axil_arvalid),
      .s_axil_arready            (s_axil_arready),
      .s_axil_rdata              (s_axil_rdata),
      .s_axil_rresp              (s_axil_rresp),
      .s_axil_rvalid             (s_axil_rvalid),
      .s_axil_rready             (s_axil_rready),

      // Registered version of wdata
      .r_axil_wdata              (r_wr_data),

      // Error
      .r_status_1in3_error                                 (/*UNUSED*/),
      .r_status_1in3_error_upd                             (r_error_upd),
      .r_status_1in3_error_wr_en                           (r_error_wr_en),

      // Registers IO
      .r_ksk_avail_avail                                   (r_ksk_avail_avail),
      .r_ksk_avail_reset                                   (/*UNUSED*/),
      .r_ksk_avail_reset_upd                               (r_req_ack_upd[REQ_ACK_KSK_OFS]),
      .r_ksk_avail_reset_wr_en                             (r_req_ack_wr_en[REQ_ACK_KSK_OFS]),
      .r_runtime_1in3_pep_cmux_loop                        (/*UNUSED*/),
      .r_runtime_1in3_pep_cmux_loop_upd                    (r_runtime_1in3_pep_cmux_loop_upd),
      .r_runtime_1in3_pep_pointer_0                        (/*UNUSED*/),
      .r_runtime_1in3_pep_pointer_0_upd                    (r_runtime_1in3_pep_pointer_0_upd),
      .r_runtime_1in3_pep_pointer_1                        (/*UNUSED*/),
      .r_runtime_1in3_pep_pointer_1_upd                    (r_runtime_1in3_pep_pointer_1_upd),
      .r_runtime_1in3_pep_pointer_2                        (/*UNUSED*/),
      .r_runtime_1in3_pep_pointer_2_upd                    (r_runtime_1in3_pep_pointer_2_upd),
      .r_runtime_1in3_isc_latest_instruction_0             (/*UNUSED*/),
      .r_runtime_1in3_isc_latest_instruction_0_upd         (in_isc_info.insn_pld[0]),
      .r_runtime_1in3_isc_latest_instruction_1             (/*UNUSED*/),
      .r_runtime_1in3_isc_latest_instruction_1_upd         (in_isc_info.insn_pld[1]),
      .r_runtime_1in3_isc_latest_instruction_2             (/*UNUSED*/),
      .r_runtime_1in3_isc_latest_instruction_2_upd         (in_isc_info.insn_pld[2]),
      .r_runtime_1in3_isc_latest_instruction_3             (/*UNUSED*/),
      .r_runtime_1in3_isc_latest_instruction_3_upd         (in_isc_info.insn_pld[3]),
      .r_runtime_1in3_pep_seq_bpip_batch_cnt               (/*UNUSED*/),
      .r_runtime_1in3_pep_seq_bpip_batch_cnt_upd           (r_sg_counter_upd[SGCNT_PEP_SEQ_BPIP_BATCH_OFS]),
      .r_runtime_1in3_pep_seq_bpip_batch_cnt_wr_en         (r_sg_counter_wr_en[SGCNT_PEP_SEQ_BPIP_BATCH_OFS]),
      .r_runtime_1in3_pep_seq_bpip_batch_flush_cnt         (/*UNUSED*/),
      .r_runtime_1in3_pep_seq_bpip_batch_flush_cnt_upd     (r_sg_counter_upd[SGCNT_PEP_SEQ_BPIP_BATCH_FLUSH_OFS]),
      .r_runtime_1in3_pep_seq_bpip_batch_flush_cnt_wr_en   (r_sg_counter_wr_en[SGCNT_PEP_SEQ_BPIP_BATCH_FLUSH_OFS]),
      .r_runtime_1in3_pep_seq_bpip_batch_timeout_cnt       (/*UNUSED*/),
      .r_runtime_1in3_pep_seq_bpip_batch_timeout_cnt_upd   (r_sg_counter_upd[SGCNT_PEP_SEQ_BPIP_BATCH_TIMEOUT_OFS]),
      .r_runtime_1in3_pep_seq_bpip_batch_timeout_cnt_wr_en (r_sg_counter_wr_en[SGCNT_PEP_SEQ_BPIP_BATCH_TIMEOUT_OFS]),
      .r_runtime_1in3_pep_seq_bpip_waiting_batch_cnt         (/*UNUSED*/),
      .r_runtime_1in3_pep_seq_bpip_waiting_batch_cnt_upd     (r_sg_counter_upd[SGCNT_PEP_SEQ_BPIP_WAITING_BATCH_OFS]),
      .r_runtime_1in3_pep_seq_bpip_waiting_batch_cnt_wr_en   (r_sg_counter_wr_en[SGCNT_PEP_SEQ_BPIP_WAITING_BATCH_OFS]),
      .r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_1       (/*UNUSED*/),
      .r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_1_upd   (r_sg_counter_bpip_batch_filling_upd[0]),
      .r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_1_wr_en (r_sg_counter_bpip_batch_filling_wr_en[0]),
      .r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_2       (/*UNUSED*/),
      .r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_2_upd   (r_sg_counter_bpip_batch_filling_upd[1]),
      .r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_2_wr_en (r_sg_counter_bpip_batch_filling_wr_en[1]),
      .r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_3       (/*UNUSED*/),
      .r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_3_upd   (r_sg_counter_bpip_batch_filling_upd[2]),
      .r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_3_wr_en (r_sg_counter_bpip_batch_filling_wr_en[2]),
      .r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_4       (/*UNUSED*/),
      .r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_4_upd   (r_sg_counter_bpip_batch_filling_upd[3]),
      .r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_4_wr_en (r_sg_counter_bpip_batch_filling_wr_en[3]),
      .r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_5       (/*UNUSED*/),
      .r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_5_upd   (r_sg_counter_bpip_batch_filling_upd[4]),
      .r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_5_wr_en (r_sg_counter_bpip_batch_filling_wr_en[4]),
      .r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_6       (/*UNUSED*/),
      .r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_6_upd   (r_sg_counter_bpip_batch_filling_upd[5]),
      .r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_6_wr_en (r_sg_counter_bpip_batch_filling_wr_en[5]),
      .r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_7       (/*UNUSED*/),
      .r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_7_upd   (r_sg_counter_bpip_batch_filling_upd[6]),
      .r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_7_wr_en (r_sg_counter_bpip_batch_filling_wr_en[6]),
      .r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_8       (/*UNUSED*/),
      .r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_8_upd   (r_sg_counter_bpip_batch_filling_upd[7]),
      .r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_8_wr_en (r_sg_counter_bpip_batch_filling_wr_en[7]),
      .r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_9       (/*UNUSED*/),
      .r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_9_upd   (r_sg_counter_bpip_batch_filling_upd[8]),
      .r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_9_wr_en (r_sg_counter_bpip_batch_filling_wr_en[8]),
      .r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_10      (/*UNUSED*/),
      .r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_10_upd  (r_sg_counter_bpip_batch_filling_upd[9]),
      .r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_10_wr_en(r_sg_counter_bpip_batch_filling_wr_en[9]),
      .r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_11      (/*UNUSED*/),
      .r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_11_upd  (r_sg_counter_bpip_batch_filling_upd[10]),
      .r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_11_wr_en(r_sg_counter_bpip_batch_filling_wr_en[10]),
      .r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_12      (/*UNUSED*/),
      .r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_12_upd  (r_sg_counter_bpip_batch_filling_upd[11]),
      .r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_12_wr_en(r_sg_counter_bpip_batch_filling_wr_en[11]),
      .r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_13      (/*UNUSED*/),
      .r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_13_upd  (r_sg_counter_bpip_batch_filling_upd[12]),
      .r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_13_wr_en(r_sg_counter_bpip_batch_filling_wr_en[12]),
      .r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_14      (/*UNUSED*/),
      .r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_14_upd  (r_sg_counter_bpip_batch_filling_upd[13]),
      .r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_14_wr_en(r_sg_counter_bpip_batch_filling_wr_en[13]),
      .r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_15      (/*UNUSED*/),
      .r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_15_upd  (r_sg_counter_bpip_batch_filling_upd[14]),
      .r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_15_wr_en(r_sg_counter_bpip_batch_filling_wr_en[14]),
      .r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_16      (/*UNUSED*/),
      .r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_16_upd  (r_sg_counter_bpip_batch_filling_upd[15]),
      .r_runtime_1in3_pep_seq_bpip_batch_filling_cnt_16_wr_en(r_sg_counter_bpip_batch_filling_wr_en[15]),
      .r_runtime_1in3_pep_seq_ld_ack_cnt                   (/*UNUSED*/),
      .r_runtime_1in3_pep_seq_ld_ack_cnt_upd               (r_sg_counter_upd[SGCNT_PEP_SEQ_LD_ACK_OFS]),
      .r_runtime_1in3_pep_seq_ld_ack_cnt_wr_en             (r_sg_counter_wr_en[SGCNT_PEP_SEQ_LD_ACK_OFS]),
      .r_runtime_1in3_pep_seq_cmux_not_full_batch_cnt      (/*UNUSED*/),
      .r_runtime_1in3_pep_seq_cmux_not_full_batch_cnt_upd  (r_sg_counter_upd[SGCNT_PEP_SEQ_CMUX_NOT_FULL_BATCH_OFS]),
      .r_runtime_1in3_pep_seq_cmux_not_full_batch_cnt_wr_en(r_sg_counter_wr_en[SGCNT_PEP_SEQ_CMUX_NOT_FULL_BATCH_OFS]),
      .r_runtime_1in3_pep_seq_ipip_flush_cnt               (/*UNUSED*/),
      .r_runtime_1in3_pep_seq_ipip_flush_cnt_upd           (r_sg_counter_upd[SGCNT_PEP_SEQ_IPIP_FLUSH_OFS]),
      .r_runtime_1in3_pep_seq_ipip_flush_cnt_wr_en         (r_sg_counter_wr_en[SGCNT_PEP_SEQ_IPIP_FLUSH_OFS]),
      .r_runtime_1in3_pep_ldg_rcp_dur                      (/*UNUSED*/),
      .r_runtime_1in3_pep_ldg_rcp_dur_upd                  (r_dr_counter_upd[DRCNT_PEP_LD_LDG_RCP_OFS]),
      .r_runtime_1in3_pep_ldg_rcp_dur_wr_en                (r_dr_counter_wr_en[DRCNT_PEP_LD_LDG_RCP_OFS]),
      .r_runtime_1in3_pep_ldg_req_dur                      (/*UNUSED*/),
      .r_runtime_1in3_pep_ldg_req_dur_upd                  (r_dr_counter_upd[DRCNT_PEP_LD_LDG_REQ_OFS]),
      .r_runtime_1in3_pep_ldg_req_dur_wr_en                (r_dr_counter_wr_en[DRCNT_PEP_LD_LDG_REQ_OFS]),
      .r_runtime_1in3_pep_ldb_rcp_dur                      (/*UNUSED*/),
      .r_runtime_1in3_pep_ldb_rcp_dur_upd                  (r_dr_counter_upd[DRCNT_PEP_LD_LDB_RCP_OFS]),
      .r_runtime_1in3_pep_ldb_rcp_dur_wr_en                (r_dr_counter_wr_en[DRCNT_PEP_LD_LDB_RCP_OFS]),
      .r_runtime_1in3_pep_mmacc_sxt_cmd_wait_b_dur         (/*UNUSED*/),
      .r_runtime_1in3_pep_mmacc_sxt_cmd_wait_b_dur_upd     (r_dr_counter_upd[DRCNT_PEP_MMACC_SXT_CMD_WAIT_B_OFS]),
      .r_runtime_1in3_pep_mmacc_sxt_cmd_wait_b_dur_wr_en   (r_dr_counter_wr_en[DRCNT_PEP_MMACC_SXT_CMD_WAIT_B_OFS]),
      .r_runtime_1in3_pep_mmacc_sxt_rcp_dur                (/*UNUSED*/),
      .r_runtime_1in3_pep_mmacc_sxt_rcp_dur_upd            (r_dr_counter_upd[DRCNT_PEP_MMACC_SXT_RCP_OFS]),
      .r_runtime_1in3_pep_mmacc_sxt_rcp_dur_wr_en          (r_dr_counter_wr_en[DRCNT_PEP_MMACC_SXT_RCP_OFS]),
      .r_runtime_1in3_pep_mmacc_sxt_req_dur                (/*UNUSED*/),
      .r_runtime_1in3_pep_mmacc_sxt_req_dur_upd            (r_dr_counter_upd[DRCNT_PEP_MMACC_SXT_REQ_OFS]),
      .r_runtime_1in3_pep_mmacc_sxt_req_dur_wr_en          (r_dr_counter_wr_en[DRCNT_PEP_MMACC_SXT_REQ_OFS]),
      .r_runtime_1in3_pep_load_ksk_rcp_dur_pc0             (/*UNUSED*/),
      .r_runtime_1in3_pep_load_ksk_rcp_dur_pc0_upd         (r_dr_counter_upd[DRCNT_PEP_LOAD_KSK_RCP_OFS + 0]),
      .r_runtime_1in3_pep_load_ksk_rcp_dur_pc0_wr_en       (r_dr_counter_wr_en[DRCNT_PEP_LOAD_KSK_RCP_OFS + 0]),
      .r_runtime_1in3_pep_load_ksk_rcp_dur_pc1             (/*UNUSED*/),
      .r_runtime_1in3_pep_load_ksk_rcp_dur_pc1_upd         (r_dr_counter_upd[DRCNT_PEP_LOAD_KSK_RCP_OFS + 1]),
      .r_runtime_1in3_pep_load_ksk_rcp_dur_pc1_wr_en       (r_dr_counter_wr_en[DRCNT_PEP_LOAD_KSK_RCP_OFS + 1]),
      .r_runtime_1in3_pep_load_ksk_rcp_dur_pc2             (/*UNUSED*/),
      .r_runtime_1in3_pep_load_ksk_rcp_dur_pc2_upd         (r_dr_counter_upd[DRCNT_PEP_LOAD_KSK_RCP_OFS + 2]),
      .r_runtime_1in3_pep_load_ksk_rcp_dur_pc2_wr_en       (r_dr_counter_wr_en[DRCNT_PEP_LOAD_KSK_RCP_OFS + 2]),
      .r_runtime_1in3_pep_load_ksk_rcp_dur_pc3             (/*UNUSED*/),
      .r_runtime_1in3_pep_load_ksk_rcp_dur_pc3_upd         (r_dr_counter_upd[DRCNT_PEP_LOAD_KSK_RCP_OFS + 3]),
      .r_runtime_1in3_pep_load_ksk_rcp_dur_pc3_wr_en       (r_dr_counter_wr_en[DRCNT_PEP_LOAD_KSK_RCP_OFS + 3]),
      .r_runtime_1in3_pep_load_ksk_rcp_dur_pc4             (/*UNUSED*/),
      .r_runtime_1in3_pep_load_ksk_rcp_dur_pc4_upd         (r_dr_counter_upd[DRCNT_PEP_LOAD_KSK_RCP_OFS + 4]),
      .r_runtime_1in3_pep_load_ksk_rcp_dur_pc4_wr_en       (r_dr_counter_wr_en[DRCNT_PEP_LOAD_KSK_RCP_OFS + 4]),
      .r_runtime_1in3_pep_load_ksk_rcp_dur_pc5             (/*UNUSED*/),
      .r_runtime_1in3_pep_load_ksk_rcp_dur_pc5_upd         (r_dr_counter_upd[DRCNT_PEP_LOAD_KSK_RCP_OFS + 5]),
      .r_runtime_1in3_pep_load_ksk_rcp_dur_pc5_wr_en       (r_dr_counter_wr_en[DRCNT_PEP_LOAD_KSK_RCP_OFS + 5]),
      .r_runtime_1in3_pep_load_ksk_rcp_dur_pc6             (/*UNUSED*/),
      .r_runtime_1in3_pep_load_ksk_rcp_dur_pc6_upd         (r_dr_counter_upd[DRCNT_PEP_LOAD_KSK_RCP_OFS + 6]),
      .r_runtime_1in3_pep_load_ksk_rcp_dur_pc6_wr_en       (r_dr_counter_wr_en[DRCNT_PEP_LOAD_KSK_RCP_OFS + 6]),
      .r_runtime_1in3_pep_load_ksk_rcp_dur_pc7             (/*UNUSED*/),
      .r_runtime_1in3_pep_load_ksk_rcp_dur_pc7_upd         (r_dr_counter_upd[DRCNT_PEP_LOAD_KSK_RCP_OFS + 7]),
      .r_runtime_1in3_pep_load_ksk_rcp_dur_pc7_wr_en       (r_dr_counter_wr_en[DRCNT_PEP_LOAD_KSK_RCP_OFS + 7]),
      .r_runtime_1in3_pep_load_ksk_rcp_dur_pc8             (/*UNUSED*/),
      .r_runtime_1in3_pep_load_ksk_rcp_dur_pc8_upd         (r_dr_counter_upd[DRCNT_PEP_LOAD_KSK_RCP_OFS + 8]),
      .r_runtime_1in3_pep_load_ksk_rcp_dur_pc8_wr_en       (r_dr_counter_wr_en[DRCNT_PEP_LOAD_KSK_RCP_OFS + 8]),
      .r_runtime_1in3_pep_load_ksk_rcp_dur_pc9             (/*UNUSED*/),
      .r_runtime_1in3_pep_load_ksk_rcp_dur_pc9_upd         (r_dr_counter_upd[DRCNT_PEP_LOAD_KSK_RCP_OFS + 9]),
      .r_runtime_1in3_pep_load_ksk_rcp_dur_pc9_wr_en       (r_dr_counter_wr_en[DRCNT_PEP_LOAD_KSK_RCP_OFS + 9]),
      .r_runtime_1in3_pep_load_ksk_rcp_dur_pc10            (/*UNUSED*/),
      .r_runtime_1in3_pep_load_ksk_rcp_dur_pc10_upd        (r_dr_counter_upd[DRCNT_PEP_LOAD_KSK_RCP_OFS + 10]),
      .r_runtime_1in3_pep_load_ksk_rcp_dur_pc10_wr_en      (r_dr_counter_wr_en[DRCNT_PEP_LOAD_KSK_RCP_OFS + 10]),
      .r_runtime_1in3_pep_load_ksk_rcp_dur_pc11            (/*UNUSED*/),
      .r_runtime_1in3_pep_load_ksk_rcp_dur_pc11_upd        (r_dr_counter_upd[DRCNT_PEP_LOAD_KSK_RCP_OFS + 11]),
      .r_runtime_1in3_pep_load_ksk_rcp_dur_pc11_wr_en      (r_dr_counter_wr_en[DRCNT_PEP_LOAD_KSK_RCP_OFS + 11]),
      .r_runtime_1in3_pep_load_ksk_rcp_dur_pc12            (/*UNUSED*/),
      .r_runtime_1in3_pep_load_ksk_rcp_dur_pc12_upd        (r_dr_counter_upd[DRCNT_PEP_LOAD_KSK_RCP_OFS + 12]),
      .r_runtime_1in3_pep_load_ksk_rcp_dur_pc12_wr_en      (r_dr_counter_wr_en[DRCNT_PEP_LOAD_KSK_RCP_OFS + 12]),
      .r_runtime_1in3_pep_load_ksk_rcp_dur_pc13            (/*UNUSED*/),
      .r_runtime_1in3_pep_load_ksk_rcp_dur_pc13_upd        (r_dr_counter_upd[DRCNT_PEP_LOAD_KSK_RCP_OFS + 13]),
      .r_runtime_1in3_pep_load_ksk_rcp_dur_pc13_wr_en      (r_dr_counter_wr_en[DRCNT_PEP_LOAD_KSK_RCP_OFS + 13]),
      .r_runtime_1in3_pep_load_ksk_rcp_dur_pc14            (/*UNUSED*/),
      .r_runtime_1in3_pep_load_ksk_rcp_dur_pc14_upd        (r_dr_counter_upd[DRCNT_PEP_LOAD_KSK_RCP_OFS + 14]),
      .r_runtime_1in3_pep_load_ksk_rcp_dur_pc14_wr_en      (r_dr_counter_wr_en[DRCNT_PEP_LOAD_KSK_RCP_OFS + 14]),
      .r_runtime_1in3_pep_load_ksk_rcp_dur_pc15            (/*UNUSED*/),
      .r_runtime_1in3_pep_load_ksk_rcp_dur_pc15_upd        (r_dr_counter_upd[DRCNT_PEP_LOAD_KSK_RCP_OFS + 15]),
      .r_runtime_1in3_pep_load_ksk_rcp_dur_pc15_wr_en      (r_dr_counter_wr_en[DRCNT_PEP_LOAD_KSK_RCP_OFS + 15]),
      .r_runtime_1in3_pep_inst_cnt                         (/*UNUSED*/),
      .r_runtime_1in3_pep_inst_cnt_upd                     (r_sg_counter_upd  [SGCNT_PEP_INST_OFS]),
      .r_runtime_1in3_pep_inst_cnt_wr_en                   (r_sg_counter_wr_en[SGCNT_PEP_INST_OFS]),
      .r_runtime_1in3_pep_ack_cnt                          (/*UNUSED*/),
      .r_runtime_1in3_pep_ack_cnt_upd                      (r_sg_counter_upd  [SGCNT_PEP_ACK_OFS]),
      .r_runtime_1in3_pep_ack_cnt_wr_en                    (r_sg_counter_wr_en[SGCNT_PEP_ACK_OFS]),
      .r_runtime_1in3_pem_load_inst_cnt                    (/*UNUSED*/),
      .r_runtime_1in3_pem_load_inst_cnt_upd                (r_sg_counter_upd  [SGCNT_PEM_LD_INST_OFS]),
      .r_runtime_1in3_pem_load_inst_cnt_wr_en              (r_sg_counter_wr_en[SGCNT_PEM_LD_INST_OFS]),
      .r_runtime_1in3_pem_load_ack_cnt                     (/*UNUSED*/),
      .r_runtime_1in3_pem_load_ack_cnt_upd                 (r_sg_counter_upd  [SGCNT_PEM_LD_ACK_OFS]),
      .r_runtime_1in3_pem_load_ack_cnt_wr_en               (r_sg_counter_wr_en[SGCNT_PEM_LD_ACK_OFS]),
      .r_runtime_1in3_pem_store_inst_cnt                   (/*UNUSED*/),
      .r_runtime_1in3_pem_store_inst_cnt_upd               (r_sg_counter_upd  [SGCNT_PEM_ST_INST_OFS]),
      .r_runtime_1in3_pem_store_inst_cnt_wr_en             (r_sg_counter_wr_en[SGCNT_PEM_ST_INST_OFS]),
      .r_runtime_1in3_pem_store_ack_cnt                    (/*UNUSED*/),
      .r_runtime_1in3_pem_store_ack_cnt_upd                (r_sg_counter_upd  [SGCNT_PEM_ST_ACK_OFS]),
      .r_runtime_1in3_pem_store_ack_cnt_wr_en              (r_sg_counter_wr_en[SGCNT_PEM_ST_ACK_OFS]),
      .r_runtime_1in3_pea_inst_cnt                         (/*UNUSED*/),
      .r_runtime_1in3_pea_inst_cnt_upd                     (r_sg_counter_upd  [SGCNT_PEA_INST_OFS]),
      .r_runtime_1in3_pea_inst_cnt_wr_en                   (r_sg_counter_wr_en[SGCNT_PEA_INST_OFS]),
      .r_runtime_1in3_pea_ack_cnt                          (/*UNUSED*/),
      .r_runtime_1in3_pea_ack_cnt_upd                      (r_sg_counter_upd  [SGCNT_PEA_ACK_OFS]),
      .r_runtime_1in3_pea_ack_cnt_wr_en                    (r_sg_counter_wr_en[SGCNT_PEA_ACK_OFS]),
      .r_runtime_1in3_isc_inst_cnt                         (/*UNUSED*/),
      .r_runtime_1in3_isc_inst_cnt_upd                     (r_sg_counter_upd  [SGCNT_ISC_INST_OFS]),
      .r_runtime_1in3_isc_inst_cnt_wr_en                   (r_sg_counter_wr_en[SGCNT_ISC_INST_OFS]),
      .r_runtime_1in3_isc_ack_cnt                          (/*UNUSED*/),
      .r_runtime_1in3_isc_ack_cnt_upd                      (r_sg_counter_upd  [SGCNT_ISC_ACK_OFS]),
      .r_runtime_1in3_isc_ack_cnt_wr_en                    (r_sg_counter_wr_en[SGCNT_ISC_ACK_OFS]),
      .r_runtime_1in3_pem_load_info_0_pc0_0                (/*UNUSED*/),
      .r_runtime_1in3_pem_load_info_0_pc0_0_upd            (in_pem_info.load.data[0][0]),
      .r_runtime_1in3_pem_load_info_0_pc0_1                (/*UNUSED*/),
      .r_runtime_1in3_pem_load_info_0_pc0_1_upd            (in_pem_info.load.data[0][1]),
      .r_runtime_1in3_pem_load_info_0_pc0_2                (/*UNUSED*/),
      .r_runtime_1in3_pem_load_info_0_pc0_2_upd            (in_pem_info.load.data[0][2]),
      .r_runtime_1in3_pem_load_info_0_pc0_3                (/*UNUSED*/),
      .r_runtime_1in3_pem_load_info_0_pc0_3_upd            (in_pem_info.load.data[0][3]),
      .r_runtime_1in3_pem_load_info_0_pc1_0                (/*UNUSED*/),
      .r_runtime_1in3_pem_load_info_0_pc1_0_upd            (in_pem_info.load.data[1][0]),
      .r_runtime_1in3_pem_load_info_0_pc1_1                (/*UNUSED*/),
      .r_runtime_1in3_pem_load_info_0_pc1_1_upd            (in_pem_info.load.data[1][1]),
      .r_runtime_1in3_pem_load_info_0_pc1_2                (/*UNUSED*/),
      .r_runtime_1in3_pem_load_info_0_pc1_2_upd            (in_pem_info.load.data[1][2]),
      .r_runtime_1in3_pem_load_info_0_pc1_3                (/*UNUSED*/),
      .r_runtime_1in3_pem_load_info_0_pc1_3_upd            (in_pem_info.load.data[1][3]),
      .r_runtime_1in3_pem_load_info_1_pc0_lsb              (/*UNUSED*/),
      .r_runtime_1in3_pem_load_info_1_pc0_lsb_upd          (in_pem_info.load.add[0][0*REG_DATA_W+:REG_DATA_W]),
      .r_runtime_1in3_pem_load_info_1_pc0_msb              (/*UNUSED*/),
      .r_runtime_1in3_pem_load_info_1_pc0_msb_upd          (in_pem_info.load.add[0][1*REG_DATA_W+:REG_DATA_W]),
      .r_runtime_1in3_pem_load_info_1_pc1_lsb              (/*UNUSED*/),
      .r_runtime_1in3_pem_load_info_1_pc1_lsb_upd          (in_pem_info.load.add[1][0*REG_DATA_W+:REG_DATA_W]),
      .r_runtime_1in3_pem_load_info_1_pc1_msb              (/*UNUSED*/),
      .r_runtime_1in3_pem_load_info_1_pc1_msb_upd          (in_pem_info.load.add[1][1*REG_DATA_W+:REG_DATA_W]),
      .r_runtime_1in3_pem_store_info_0                     (/*UNUSED*/),
      .r_runtime_1in3_pem_store_info_0_upd                 (r_runtime_1in3_pem_store_info_0_upd),
      .r_runtime_1in3_pem_store_info_1                     (/*UNUSED*/),
      .r_runtime_1in3_pem_store_info_1_upd                 (r_runtime_1in3_pem_store_info_1_upd),
      .r_runtime_1in3_pem_store_info_2                     (/*UNUSED*/),
      .r_runtime_1in3_pem_store_info_2_upd                 (r_runtime_1in3_pem_store_info_2_upd),
      .r_runtime_1in3_pem_store_info_3                     (/*UNUSED*/),
      .r_runtime_1in3_pem_store_info_3_upd                 (r_runtime_1in3_pem_store_info_3_upd)
    );

// ============================================================================================== --
// Output pipe
// ============================================================================================== --
  always_ff @(posedge prc_clk)
    if (!prc_srst_n) reset_cache <= 1'b0;
    else             reset_cache <= reset_ksk_cache;

endmodule
