// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Axi4-lite register bank
// ----------------------------------------------------------------------------------------------
// For prc_clk part 3in3
// ==============================================================================================

module hpu_regif_prc_3in3
  import axi_if_common_param_pkg::*;
  import axi_if_shell_axil_pkg::*;
  import top_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import hpu_common_instruction_pkg::*;
  import hpu_regif_core_prc_3in3_pkg::*;
  import hpu_common_param_pkg::*;
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

  // bsk
  output logic                                                      bsk_mem_avail,

  output logic                                                      reset_bsk_cache,
  input  logic                                                      reset_bsk_cache_done,
  output logic                                                      reset_cache,

  // Register IO: runtime_3in3
  // -> error
  input  logic [ERROR_NB-1:0]                                       error, // TOREVIEW : to complete if needed
  // -> info
  input  pep_info_t                                                 pep_info,
  // Register IO: Counter
  input  pep_counter_inc_t                                          pep_counter_inc

);
// ============================================================================================== --
// localparam
// ============================================================================================== --
  // Current design supports BSK_PC_MAX up to 16.
  localparam int BSK_PC_MAX_L    = 16;

  localparam int REQ_ACK_NB      = 1; // reset_cache for bsk
  localparam int REQ_ACK_BSK_OFS = 0;

  // counter over REG_DATA_W
  localparam int SINGLE_COUNTER_NB      = 0;
  // counter over 2*REG_DATA_W
  localparam int DOUBLE_COUNTER_NB      = 0;
  // counter of a duration : number of cycle the signal is 1
  localparam int DURATION_COUNTER_NB    =   BSK_PC_MAX_L;
  localparam int POSEDGE_COUNTER_NB     = 0; // posedge counter

  // TODO define here the offset of each input
  localparam int DRCNT_PEP_LOAD_BSK_RCP_OFS         = 0;
  // Next offset will be at DRCNT_PEP_LOAD_BSK_RCP_OFS + BSK_PC_MAX_L

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

// ============================================================================================== --
// Input pipe
// ============================================================================================== --
  pep_info_t            in_pep_info;
  pep_counter_inc_t     in_pep_counter_inc;
  logic [ERROR_NB-1: 0] in_error;

  always_ff @(posedge prc_clk)
    if (!prc_srst_n) begin
      in_error           <= '0;
      in_pep_counter_inc <= '0;
    end
    else begin
      in_error           <= error          ;
      in_pep_counter_inc <= pep_counter_inc;
    end

  always_ff @(posedge prc_clk) begin
    in_pep_info <= pep_info;
  end

// ============================================================================================== --
// hpu_regif_req_ack
// ============================================================================================== --
  assign reset_bsk_cache = req_cmd[REQ_ACK_BSK_OFS];
  assign ack_rsp[REQ_ACK_BSK_OFS] = reset_bsk_cache_done;
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
  always_comb begin
    for (int i=0; i<BSK_PC_MAX; i=i+1)
      dr_inc[DRCNT_PEP_LOAD_BSK_RCP_OFS+i]        = in_pep_counter_inc.key.load_bsk_dur[i];
    for (int i=BSK_PC_MAX; i<BSK_PC_MAX_L; i=i+1)
      dr_inc[DRCNT_PEP_LOAD_BSK_RCP_OFS+i]        = 1'b0;
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
  bsk_avail_avail_t         r_bsk_avail_avail;

  // Extract fields
  assign bsk_mem_avail = r_bsk_avail_avail.avail;

  runtime_3in3_pep_bskif_req_info_0_t runtime_3in3_pep_bskif_req_info_0_upd;
  runtime_3in3_pep_bskif_req_info_1_t runtime_3in3_pep_bskif_req_info_1_upd;

  // Set fields
  assign runtime_3in3_pep_bskif_req_info_0_upd.req_br_loop_rp = in_pep_info.bskif.req_br_loop_rp;
  assign runtime_3in3_pep_bskif_req_info_0_upd.req_br_loop_wp = in_pep_info.bskif.req_br_loop_wp;

  assign runtime_3in3_pep_bskif_req_info_1_upd.req_prf_br_loop = in_pep_info.bskif.req_prf_br_loop;
  assign runtime_3in3_pep_bskif_req_info_1_upd.req_parity      = in_pep_info.bskif.req_parity;
  assign runtime_3in3_pep_bskif_req_info_1_upd.req_assigned    = in_pep_info.bskif.req_assigned;


  hpu_regif_core_prc_3in3
  hpu_regif_core_prc_3in3 (
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
      .r_status_3in3_error                                 (/*UNUSED*/),
      .r_status_3in3_error_upd                             (r_error_upd),
      .r_status_3in3_error_wr_en                           (r_error_wr_en),

      // Registers IO
      .r_bsk_avail_avail                                   (r_bsk_avail_avail),
      .r_bsk_avail_reset                                   (/*UNUSED*/),
      .r_bsk_avail_reset_upd                               (r_req_ack_upd[REQ_ACK_BSK_OFS]),
      .r_bsk_avail_reset_wr_en                             (r_req_ack_wr_en[REQ_ACK_BSK_OFS]),
      .r_runtime_3in3_pep_load_bsk_rcp_dur_pc0             (/*UNUSED*/),
      .r_runtime_3in3_pep_load_bsk_rcp_dur_pc0_upd         (r_dr_counter_upd[DRCNT_PEP_LOAD_BSK_RCP_OFS + 0]),
      .r_runtime_3in3_pep_load_bsk_rcp_dur_pc0_wr_en       (r_dr_counter_wr_en[DRCNT_PEP_LOAD_BSK_RCP_OFS + 0]),
      .r_runtime_3in3_pep_load_bsk_rcp_dur_pc1             (/*UNUSED*/),
      .r_runtime_3in3_pep_load_bsk_rcp_dur_pc1_upd         (r_dr_counter_upd[DRCNT_PEP_LOAD_BSK_RCP_OFS + 1]),
      .r_runtime_3in3_pep_load_bsk_rcp_dur_pc1_wr_en       (r_dr_counter_wr_en[DRCNT_PEP_LOAD_BSK_RCP_OFS + 1]),
      .r_runtime_3in3_pep_load_bsk_rcp_dur_pc2             (/*UNUSED*/),
      .r_runtime_3in3_pep_load_bsk_rcp_dur_pc2_upd         (r_dr_counter_upd[DRCNT_PEP_LOAD_BSK_RCP_OFS + 2]),
      .r_runtime_3in3_pep_load_bsk_rcp_dur_pc2_wr_en       (r_dr_counter_wr_en[DRCNT_PEP_LOAD_BSK_RCP_OFS + 2]),
      .r_runtime_3in3_pep_load_bsk_rcp_dur_pc3             (/*UNUSED*/),
      .r_runtime_3in3_pep_load_bsk_rcp_dur_pc3_upd         (r_dr_counter_upd[DRCNT_PEP_LOAD_BSK_RCP_OFS + 3]),
      .r_runtime_3in3_pep_load_bsk_rcp_dur_pc3_wr_en       (r_dr_counter_wr_en[DRCNT_PEP_LOAD_BSK_RCP_OFS + 3]),
      .r_runtime_3in3_pep_load_bsk_rcp_dur_pc4             (/*UNUSED*/),
      .r_runtime_3in3_pep_load_bsk_rcp_dur_pc4_upd         (r_dr_counter_upd[DRCNT_PEP_LOAD_BSK_RCP_OFS + 4]),
      .r_runtime_3in3_pep_load_bsk_rcp_dur_pc4_wr_en       (r_dr_counter_wr_en[DRCNT_PEP_LOAD_BSK_RCP_OFS + 4]),
      .r_runtime_3in3_pep_load_bsk_rcp_dur_pc5             (/*UNUSED*/),
      .r_runtime_3in3_pep_load_bsk_rcp_dur_pc5_upd         (r_dr_counter_upd[DRCNT_PEP_LOAD_BSK_RCP_OFS + 5]),
      .r_runtime_3in3_pep_load_bsk_rcp_dur_pc5_wr_en       (r_dr_counter_wr_en[DRCNT_PEP_LOAD_BSK_RCP_OFS + 5]),
      .r_runtime_3in3_pep_load_bsk_rcp_dur_pc6             (/*UNUSED*/),
      .r_runtime_3in3_pep_load_bsk_rcp_dur_pc6_upd         (r_dr_counter_upd[DRCNT_PEP_LOAD_BSK_RCP_OFS + 6]),
      .r_runtime_3in3_pep_load_bsk_rcp_dur_pc6_wr_en       (r_dr_counter_wr_en[DRCNT_PEP_LOAD_BSK_RCP_OFS + 6]),
      .r_runtime_3in3_pep_load_bsk_rcp_dur_pc7             (/*UNUSED*/),
      .r_runtime_3in3_pep_load_bsk_rcp_dur_pc7_upd         (r_dr_counter_upd[DRCNT_PEP_LOAD_BSK_RCP_OFS + 7]),
      .r_runtime_3in3_pep_load_bsk_rcp_dur_pc7_wr_en       (r_dr_counter_wr_en[DRCNT_PEP_LOAD_BSK_RCP_OFS + 7]),
      .r_runtime_3in3_pep_load_bsk_rcp_dur_pc8             (/*UNUSED*/),
      .r_runtime_3in3_pep_load_bsk_rcp_dur_pc8_upd         (r_dr_counter_upd[DRCNT_PEP_LOAD_BSK_RCP_OFS + 8]),
      .r_runtime_3in3_pep_load_bsk_rcp_dur_pc8_wr_en       (r_dr_counter_wr_en[DRCNT_PEP_LOAD_BSK_RCP_OFS + 8]),
      .r_runtime_3in3_pep_load_bsk_rcp_dur_pc9             (/*UNUSED*/),
      .r_runtime_3in3_pep_load_bsk_rcp_dur_pc9_upd         (r_dr_counter_upd[DRCNT_PEP_LOAD_BSK_RCP_OFS + 9]),
      .r_runtime_3in3_pep_load_bsk_rcp_dur_pc9_wr_en       (r_dr_counter_wr_en[DRCNT_PEP_LOAD_BSK_RCP_OFS + 9]),
      .r_runtime_3in3_pep_load_bsk_rcp_dur_pc10            (/*UNUSED*/),
      .r_runtime_3in3_pep_load_bsk_rcp_dur_pc10_upd        (r_dr_counter_upd[DRCNT_PEP_LOAD_BSK_RCP_OFS + 10]),
      .r_runtime_3in3_pep_load_bsk_rcp_dur_pc10_wr_en      (r_dr_counter_wr_en[DRCNT_PEP_LOAD_BSK_RCP_OFS + 10]),
      .r_runtime_3in3_pep_load_bsk_rcp_dur_pc11            (/*UNUSED*/),
      .r_runtime_3in3_pep_load_bsk_rcp_dur_pc11_upd        (r_dr_counter_upd[DRCNT_PEP_LOAD_BSK_RCP_OFS + 11]),
      .r_runtime_3in3_pep_load_bsk_rcp_dur_pc11_wr_en      (r_dr_counter_wr_en[DRCNT_PEP_LOAD_BSK_RCP_OFS + 11]),
      .r_runtime_3in3_pep_load_bsk_rcp_dur_pc12            (/*UNUSED*/),
      .r_runtime_3in3_pep_load_bsk_rcp_dur_pc12_upd        (r_dr_counter_upd[DRCNT_PEP_LOAD_BSK_RCP_OFS + 12]),
      .r_runtime_3in3_pep_load_bsk_rcp_dur_pc12_wr_en      (r_dr_counter_wr_en[DRCNT_PEP_LOAD_BSK_RCP_OFS + 12]),
      .r_runtime_3in3_pep_load_bsk_rcp_dur_pc13            (/*UNUSED*/),
      .r_runtime_3in3_pep_load_bsk_rcp_dur_pc13_upd        (r_dr_counter_upd[DRCNT_PEP_LOAD_BSK_RCP_OFS + 13]),
      .r_runtime_3in3_pep_load_bsk_rcp_dur_pc13_wr_en      (r_dr_counter_wr_en[DRCNT_PEP_LOAD_BSK_RCP_OFS + 13]),
      .r_runtime_3in3_pep_load_bsk_rcp_dur_pc14            (/*UNUSED*/),
      .r_runtime_3in3_pep_load_bsk_rcp_dur_pc14_upd        (r_dr_counter_upd[DRCNT_PEP_LOAD_BSK_RCP_OFS + 14]),
      .r_runtime_3in3_pep_load_bsk_rcp_dur_pc14_wr_en      (r_dr_counter_wr_en[DRCNT_PEP_LOAD_BSK_RCP_OFS + 14]),
      .r_runtime_3in3_pep_load_bsk_rcp_dur_pc15            (/*UNUSED*/),
      .r_runtime_3in3_pep_load_bsk_rcp_dur_pc15_upd        (r_dr_counter_upd[DRCNT_PEP_LOAD_BSK_RCP_OFS + 15]),
      .r_runtime_3in3_pep_load_bsk_rcp_dur_pc15_wr_en      (r_dr_counter_wr_en[DRCNT_PEP_LOAD_BSK_RCP_OFS + 15]),
      .r_runtime_3in3_pep_bskif_req_info_0                 (/*UNUSED*/),
      .r_runtime_3in3_pep_bskif_req_info_0_upd             (runtime_3in3_pep_bskif_req_info_0_upd),
      .r_runtime_3in3_pep_bskif_req_info_1                 (/*UNUSED*/),
      .r_runtime_3in3_pep_bskif_req_info_1_upd             (runtime_3in3_pep_bskif_req_info_1_upd)
    );

// ============================================================================================== --
// Output pipe
// ============================================================================================== --
  always_ff @(posedge prc_clk)
    if (!prc_srst_n) reset_cache <= 1'b0;
    else             reset_cache <= reset_bsk_cache;

endmodule
