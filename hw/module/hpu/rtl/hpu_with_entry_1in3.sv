// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Top level of HPU
// ----------------------------------------------------------------------------------------------
//
// Wrap together register interface, instruction scheduler (instruction_scheduler),
// register file (regfile), and the three processing units (pe_mem, pe_alu, pe_pbs)
//
// This module is a subpart of hpu, to ease the P&R.
// It contains :
//  * isc
//  * regif
// ==============================================================================================

module hpu_with_entry_1in3
  import common_definition_pkg::*;
  import param_tfhe_pkg::*;
  import top_common_param_pkg::*;
  import hpu_common_param_pkg::*;
  import hpu_common_instruction_pkg::*;
  import axi_if_ksk_axi_pkg::*;
  import axi_if_glwe_axi_pkg::*;
  import axi_if_ct_axi_pkg::*;
  import axi_if_ucore_axi_pkg::*;
  import axi_if_trc_axi_pkg::*;
  import axi_if_common_param_pkg::*;
  import axi_if_shell_axil_pkg::*;
  import regf_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import pem_common_param_pkg::*;
  import pea_common_param_pkg::*;
  import isc_common_param_pkg::*;
#(
  parameter int VERSION_MAJOR   = 2,
  parameter int VERSION_MINOR   = 0,
  parameter int ERROR_NB        = 13
) (
  input  logic                                                         prc_clk,   // clock
  input  logic                                                         prc_srst_n, // synchronous reset

  input  logic                                                         cfg_clk,   // clock
  input  logic                                                         cfg_srst_n, // synchronous reset

  //== Axi4 lite Slave Interface sAxi4
  input  logic [AXIL_ADD_W-1:0]                                        s_axil_prc_awaddr,
  input  logic                                                         s_axil_prc_awvalid,
  output logic                                                         s_axil_prc_awready,
  input  logic [AXIL_DATA_W-1:0]                                       s_axil_prc_wdata,
  input  logic [AXIL_DATA_BYTES-1:0]                                   s_axil_prc_wstrb, /* UNUSED */
  input  logic                                                         s_axil_prc_wvalid,
  output logic                                                         s_axil_prc_wready,
  output logic [1:0]                                                   s_axil_prc_bresp,
  output logic                                                         s_axil_prc_bvalid,
  input  logic                                                         s_axil_prc_bready,
  input  logic [AXIL_ADD_W-1:0]                                        s_axil_prc_araddr,
  input  logic                                                         s_axil_prc_arvalid,
  output logic                                                         s_axil_prc_arready,
  output logic [AXIL_DATA_W-1:0]                                       s_axil_prc_rdata,
  output logic [1:0]                                                   s_axil_prc_rresp,
  output logic                                                         s_axil_prc_rvalid,
  input  logic                                                         s_axil_prc_rready,

  input  logic [AXIL_ADD_W-1:0]                                        s_axil_cfg_awaddr,
  input  logic                                                         s_axil_cfg_awvalid,
  output logic                                                         s_axil_cfg_awready,
  input  logic [AXIL_DATA_W-1:0]                                       s_axil_cfg_wdata,
  input  logic [AXIL_DATA_BYTES-1:0]                                   s_axil_cfg_wstrb, /* UNUSED */
  input  logic                                                         s_axil_cfg_wvalid,
  output logic                                                         s_axil_cfg_wready,
  output logic [1:0]                                                   s_axil_cfg_bresp,
  output logic                                                         s_axil_cfg_bvalid,
  input  logic                                                         s_axil_cfg_bready,
  input  logic [AXIL_ADD_W-1:0]                                        s_axil_cfg_araddr,
  input  logic                                                         s_axil_cfg_arvalid,
  output logic                                                         s_axil_cfg_arready,
  output logic [AXIL_DATA_W-1:0]                                       s_axil_cfg_rdata,
  output logic [1:0]                                                   s_axil_cfg_rresp,
  output logic                                                         s_axil_cfg_rvalid,
  input  logic                                                         s_axil_cfg_rready,

  input  logic [PE_INST_W-1:0]                                         isc_dop,
  output logic                                                         isc_dop_rdy,
  input  logic                                                         isc_dop_vld,

  output logic [PE_INST_W-1:0]                                         isc_ack,
  input  logic                                                         isc_ack_rdy,
  output logic                                                         isc_ack_vld,

  //== Axi4 TraceManager interface
  // Write channel
  output logic [axi_if_trc_axi_pkg::AXI4_ID_W-1:0]                     m_axi4_trc_awid,
  output logic [axi_if_trc_axi_pkg::AXI4_ADD_W-1:0]                    m_axi4_trc_awaddr,
  output logic [AXI4_LEN_W-1:0]                                        m_axi4_trc_awlen,
  output logic [AXI4_SIZE_W-1:0]                                       m_axi4_trc_awsize,
  output logic [AXI4_BURST_W-1:0]                                      m_axi4_trc_awburst,
  output logic                                                         m_axi4_trc_awvalid,
  input  logic                                                         m_axi4_trc_awready,
  output logic [axi_if_trc_axi_pkg::AXI4_DATA_W-1:0]                   m_axi4_trc_wdata,
  output logic [(axi_if_trc_axi_pkg::AXI4_DATA_W/8)-1:0]               m_axi4_trc_wstrb,
  output logic                                                         m_axi4_trc_wlast,
  output logic                                                         m_axi4_trc_wvalid,
  input  logic                                                         m_axi4_trc_wready,
  input  logic [axi_if_trc_axi_pkg::AXI4_ID_W-1:0]                     m_axi4_trc_bid,
  input  logic [AXI4_RESP_W-1:0]                                       m_axi4_trc_bresp,
  input  logic                                                         m_axi4_trc_bvalid,
  output logic                                                         m_axi4_trc_bready,

  // Regif -----------------------------------------------------------------------------------------
  // mem addr spread on 2 word (msb/lsb)
  output logic [PEM_PC_MAX-1:0][axi_if_ct_axi_pkg::AXI4_ADD_W-1:0]     ct_mem_addr,

  output logic                                                         reset_ksk_cache,
  input  logic                                                         reset_ksk_cache_done,
  output logic                                                         ksk_mem_avail,
  output logic [KSK_PC_MAX-1:0][axi_if_ksk_axi_pkg::AXI4_ADD_W-1:0]    ksk_mem_addr,

  output logic                                                         reset_cache,

  output logic [GLWE_PC_MAX-1:0][axi_if_glwe_axi_pkg::AXI4_ADD_W-1:0]  glwe_mem_addr,
  output logic                                                         use_bpip,
  output logic                                                         use_bpip_opportunism,
  output logic [TIMEOUT_CNT_W-1: 0]                                    bpip_timeout,

  // Pe MEM -----------------------------------------------------------------------------------------
  output logic [PE_INST_W-1:0]                                         isc_pem_insn,
  output logic                                                         isc_pem_vld,
  input  logic                                                         isc_pem_rdy,
  input  logic                                                         pem_isc_load_ack,
  input  logic                                                         pem_isc_store_ack,

  // Pe ALU -----------------------------------------------------------------------------------------
  output logic [PE_INST_W-1:0]                                         isc_pea_insn,
  output logic                                                         isc_pea_vld,
  input  logic                                                         isc_pea_rdy,
  input  logic                                                         pea_isc_ack,

  // Pe PBS -----------------------------------------------------------------------------------------
  output logic [PE_INST_W-1:0]                                         isc_pep_insn,
  output logic                                                         isc_pep_vld,
  input  logic                                                         isc_pep_rdy,
  input  logic                                                         pep_isc_ack,
  input  logic [LWE_K_W-1:0]                                           pep_isc_ack_br_loop,
  input  logic                                                         pep_isc_load_blwe_ack,

  // Errors ------------------------------------------------------------------------------------------
  input  logic [ERROR_NB-1:0]                                          error,

  // Counters/Infos ----------------------------------------------------------------------------------
  input  pep_info_t                                                    pep_rif_info,
  input  pem_info_t                                                    pem_rif_info,
  input  pep_counter_inc_t                                             pep_rif_counter_inc,
  input  pem_counter_inc_t                                             pem_rif_counter_inc,
  input  pea_counter_inc_t                                             pea_rif_counter_inc,

  output logic [1:0]                                                   interrupt // TODO
);

// ============================================================================================== --
// localparam
// ============================================================================================== --

// ============================================================================================== --
// Signals
// ============================================================================================== --
  // Regif -----------------------------------------------------------------------------------------
  logic [axi_if_trc_axi_pkg::AXI4_ADD_W-1:0] trc_mem_addr;

  // Isc -----------------------------------------------------------------------------------------
  logic               isc_trace_wr_en;
  isc_trace_t         isc_trace_data;
  logic               error_trace;

  // Counters ----------------------------------------------------------------------------------------
  isc_counter_inc_t   isc_rif_counter_inc;
  isc_info_t          isc_rif_info;

// ============================================================================================== --
// regif @ cfg_clk
// ============================================================================================== --
  hpu_regif_cfg_1in3 # (
    .VERSION_MAJOR (VERSION_MAJOR),
    .VERSION_MINOR (VERSION_MINOR)
  ) hpu_regif_cfg_1in3 (
    .cfg_clk                   (cfg_clk),
    .cfg_srst_n                (cfg_srst_n),

    // Axi lite interface
    .s_axil_awaddr             (s_axil_cfg_awaddr),
    .s_axil_awvalid            (s_axil_cfg_awvalid),
    .s_axil_awready            (s_axil_cfg_awready),
    .s_axil_wdata              (s_axil_cfg_wdata),
    .s_axil_wvalid             (s_axil_cfg_wvalid),
    .s_axil_wready             (s_axil_cfg_wready),
    .s_axil_bresp              (s_axil_cfg_bresp),
    .s_axil_bvalid             (s_axil_cfg_bvalid),
    .s_axil_bready             (s_axil_cfg_bready),
    .s_axil_araddr             (s_axil_cfg_araddr),
    .s_axil_arvalid            (s_axil_cfg_arvalid),
    .s_axil_arready            (s_axil_cfg_arready),
    .s_axil_rdata              (s_axil_cfg_rdata),
    .s_axil_rresp              (s_axil_cfg_rresp),
    .s_axil_rvalid             (s_axil_cfg_rvalid),
    .s_axil_rready             (s_axil_cfg_rready),

    // Registers IO
    .ct_mem_addr               (ct_mem_addr),
    .glwe_mem_addr             (glwe_mem_addr),
    .ksk_mem_addr              (ksk_mem_addr),
    .use_bpip                  (use_bpip),
    .use_bpip_opportunism      (use_bpip_opportunism),
    .bpip_timeout              (bpip_timeout),
    .trc_mem_addr              (trc_mem_addr)
  );

// ============================================================================================== --
// regif @ prc_clk
// ============================================================================================== --
  hpu_regif_prc_1in3 # (
  .ERROR_NB      (ERROR_NB+1) //NB: One error is generated internally by trace_manager
  ) hpu_regif_prc_1in3 (
    .prc_clk                   (prc_clk),
    .prc_srst_n                (prc_srst_n),

    // Axi lite interface
    .s_axil_awaddr             (s_axil_prc_awaddr),
    .s_axil_awvalid            (s_axil_prc_awvalid),
    .s_axil_awready            (s_axil_prc_awready),
    .s_axil_wdata              (s_axil_prc_wdata),
    .s_axil_wvalid             (s_axil_prc_wvalid),
    .s_axil_wready             (s_axil_prc_wready),
    .s_axil_bresp              (s_axil_prc_bresp),
    .s_axil_bvalid             (s_axil_prc_bvalid),
    .s_axil_bready             (s_axil_prc_bready),
    .s_axil_araddr             (s_axil_prc_araddr),
    .s_axil_arvalid            (s_axil_prc_arvalid),
    .s_axil_arready            (s_axil_prc_arready),
    .s_axil_rdata              (s_axil_prc_rdata),
    .s_axil_rresp              (s_axil_prc_rresp),
    .s_axil_rvalid             (s_axil_prc_rvalid),
    .s_axil_rready             (s_axil_prc_rready),

    // Registers IO
    .ksk_mem_avail             (ksk_mem_avail),
    .reset_ksk_cache           (reset_ksk_cache),
    .reset_ksk_cache_done      (reset_ksk_cache_done),
    .reset_cache               (reset_cache),
    .pep_info                  (pep_rif_info), // TODO complete with other info
    .pem_info                  (pem_rif_info),
    .isc_info                  (isc_rif_info),
    .error                     ({error_trace, error}), // TODO complete with the other errors
    .pep_counter_inc           (pep_rif_counter_inc), // TODO
    .pem_counter_inc           (pem_rif_counter_inc),
    .pea_counter_inc           (pea_rif_counter_inc),
    .isc_counter_inc           (isc_rif_counter_inc)
  );

/// ============================================================================================== --
//  Instruction scheduler
// ============================================================================================== --
  instruction_scheduler inst_scheduler (
    .clk                (prc_clk    ),
    .s_rst_n            (prc_srst_n),

    .use_bpip           (use_bpip),

    // Insn input stream and ack
    .insn_rdy           (isc_dop_rdy),
    .insn_pld           (isc_dop),
    .insn_vld           (isc_dop_vld),

    // TODO extend to axis or change to directly connect to irq-line
    // Must add a counter with atomic reset on read to enforce that no ack is lost
    // Implement it directly in the scheduler => it's not an axis fifo, custom component
    .insn_ack_rdy       (isc_ack_rdy),
    .insn_ack_cnt       (isc_ack),
    .insn_ack_vld       (isc_ack_vld),

    // PE interfaces
    // PEM
    .pem_rdy            (isc_pem_rdy),
    .pem_insn           (isc_pem_insn),
    .pem_vld            (isc_pem_vld),
    .pem_load_ack       (pem_isc_load_ack),
    .pem_store_ack      (pem_isc_store_ack),
    // PEA
    .pea_rdy            (isc_pea_rdy),
    .pea_insn           (isc_pea_insn),
    .pea_vld            (isc_pea_vld),
    .pea_ack            (pea_isc_ack),
    // PEP
    .pep_rdy            (isc_pep_rdy),
    .pep_insn           (isc_pep_insn),
    .pep_vld            (isc_pep_vld),
    .pep_rd_ack         (pep_isc_load_blwe_ack),
    .pep_wr_ack         (pep_isc_ack),
    .pep_ack_pld        (pep_isc_ack_br_loop),

    .isc_counter_inc    (isc_rif_counter_inc),
    .isc_rif_info       (isc_rif_info),

    .trace_wr_en        (isc_trace_wr_en),
    .trace_data         (isc_trace_data)
  );

/// ============================================================================================== --
//  Trace Manager
// ============================================================================================== --
  trace_manager
  #(
    .INFO_W        (isc_common_param_pkg::TRACE_W),
    .DEPTH         (TRC_DEPTH),
    .RAM_LATENCY   (RAM_LATENCY),
    .MEM_DEPTH     (TRC_MEM_DEPTH)
  ) trace_manager (
    .clk            (prc_clk),
    .s_rst_n        (prc_srst_n),

    .wr_en          (isc_trace_wr_en),
    .wr_data        (isc_trace_data),

    .addr_ofs       (trc_mem_addr),

    .m_axi4_awid    (m_axi4_trc_awid),
    .m_axi4_awaddr  (m_axi4_trc_awaddr),
    .m_axi4_awlen   (m_axi4_trc_awlen),
    .m_axi4_awsize  (m_axi4_trc_awsize),
    .m_axi4_awburst (m_axi4_trc_awburst),
    .m_axi4_awvalid (m_axi4_trc_awvalid),
    .m_axi4_awready (m_axi4_trc_awready),
    .m_axi4_wdata   (m_axi4_trc_wdata),
    .m_axi4_wstrb   (m_axi4_trc_wstrb),
    .m_axi4_wlast   (m_axi4_trc_wlast),
    .m_axi4_wvalid  (m_axi4_trc_wvalid),
    .m_axi4_wready  (m_axi4_trc_wready),
    .m_axi4_bid     (m_axi4_trc_bid),
    .m_axi4_bresp   (m_axi4_trc_bresp),
    .m_axi4_bvalid  (m_axi4_trc_bvalid),
    .m_axi4_bready  (m_axi4_trc_bready),

    .error          (error_trace)
  );

endmodule
