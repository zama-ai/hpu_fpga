// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Top level monolithic integration of HPU aimed to be integrated through Vitis
// ----------------------------------------------------------------------------------------------
//
// Wrap together register interface, IOP->DOp translation (ucore), instruction scheduler (instruction_schedurer),
// register file (regfile), and the three processing units (pe_mem, pe_alu, pe_pbs)
//
// This module is a subpart of hpu, to ease the P&R.
// It contains :
//  * pe_mem
//  * pe_alu
//  * regfile
// ==============================================================================================

module hpu_with_pe
  import common_definition_pkg::*;
  import param_tfhe_pkg::*;
  import top_common_param_pkg::*;
  import hpu_common_param_pkg::*;
  import hpu_common_instruction_pkg::*;
  import axi_if_bsk_axi_pkg::*;
  import axi_if_ksk_axi_pkg::*;
  import axi_if_glwe_axi_pkg::*;
  import axi_if_ct_axi_pkg::*;
  import axi_if_ucore_axi_pkg::*;
  import axi_if_common_param_pkg::*;
  import axi_if_shell_axil_pkg::*;
  import regf_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import pem_common_param_pkg::*;
  import pea_common_param_pkg::*;
(
  input  logic                                                      clk,   // clock
  input  logic                                                      s_rst_n, // synchronous reset

  //== Axi4 PEM interface
  // Write channel
  output logic [PEM_PC-1:0][axi_if_ct_axi_pkg::AXI4_ID_W-1:0]       m_axi4_pem_awid,
  output logic [PEM_PC-1:0][axi_if_ct_axi_pkg::AXI4_ADD_W-1:0]      m_axi4_pem_awaddr,
  output logic [PEM_PC-1:0][AXI4_LEN_W-1:0]                         m_axi4_pem_awlen,
  output logic [PEM_PC-1:0][AXI4_SIZE_W-1:0]                        m_axi4_pem_awsize,
  output logic [PEM_PC-1:0][AXI4_BURST_W-1:0]                       m_axi4_pem_awburst,
  output logic [PEM_PC-1:0]                                         m_axi4_pem_awvalid,
  input  logic [PEM_PC-1:0]                                         m_axi4_pem_awready,
  output logic [PEM_PC-1:0][axi_if_ct_axi_pkg::AXI4_DATA_W-1:0]     m_axi4_pem_wdata,
  output logic [PEM_PC-1:0][axi_if_ct_axi_pkg::AXI4_STRB_W-1:0]     m_axi4_pem_wstrb,
  output logic [PEM_PC-1:0]                                         m_axi4_pem_wlast,
  output logic [PEM_PC-1:0]                                         m_axi4_pem_wvalid,
  input  logic [PEM_PC-1:0]                                         m_axi4_pem_wready,
  input  logic [PEM_PC-1:0][axi_if_ct_axi_pkg::AXI4_ID_W-1:0]       m_axi4_pem_bid,
  input  logic [PEM_PC-1:0][AXI4_RESP_W-1:0]                        m_axi4_pem_bresp,
  input  logic [PEM_PC-1:0]                                         m_axi4_pem_bvalid,
  output logic [PEM_PC-1:0]                                         m_axi4_pem_bready,
  // Read channel
  output logic [PEM_PC-1:0][axi_if_ct_axi_pkg::AXI4_ID_W-1:0]       m_axi4_pem_arid,
  output logic [PEM_PC-1:0][axi_if_ct_axi_pkg::AXI4_ADD_W-1:0]      m_axi4_pem_araddr,
  output logic [PEM_PC-1:0][AXI4_LEN_W-1:0]                         m_axi4_pem_arlen,
  output logic [PEM_PC-1:0][AXI4_SIZE_W-1:0]                        m_axi4_pem_arsize,
  output logic [PEM_PC-1:0][AXI4_BURST_W-1:0]                       m_axi4_pem_arburst,
  output logic [PEM_PC-1:0]                                         m_axi4_pem_arvalid,
  input  logic [PEM_PC-1:0]                                         m_axi4_pem_arready,
  input  logic [PEM_PC-1:0][axi_if_ct_axi_pkg::AXI4_ID_W-1:0]       m_axi4_pem_rid,
  input  logic [PEM_PC-1:0][axi_if_ct_axi_pkg::AXI4_DATA_W-1:0]     m_axi4_pem_rdata,
  input  logic [PEM_PC-1:0][AXI4_RESP_W-1:0]                        m_axi4_pem_rresp,
  input  logic [PEM_PC-1:0]                                         m_axi4_pem_rlast,
  input  logic [PEM_PC-1:0]                                         m_axi4_pem_rvalid,
  output logic [PEM_PC-1:0]                                         m_axi4_pem_rready,

  //== PE MEM
  input  logic [PE_INST_W-1:0]                                      isc_pem_insn,
  input  logic                                                      isc_pem_vld,
  output logic                                                      isc_pem_rdy,
  output logic                                                      pem_isc_load_ack,
  output logic                                                      pem_isc_store_ack,

  //== PE ALU
  input  logic [PE_INST_W-1:0]                                      isc_pea_insn,
  input  logic                                                      isc_pea_vld,
  output logic                                                      isc_pea_rdy,
  output logic                                                      pea_isc_ack,

  //== PE PBS <-> regfile
  input  logic                                                      pep_regf_wr_req_vld,
  output logic                                                      pep_regf_wr_req_rdy,
  input  regf_wr_req_t                                              pep_regf_wr_req,

  input  logic [REGF_COEF_NB-1:0]                                   pep_regf_wr_data_vld,
  output logic [REGF_COEF_NB-1:0]                                   pep_regf_wr_data_rdy,
  input  logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0]                      pep_regf_wr_data,

  output logic                                                      regf_pep_wr_ack,

  input  logic                                                      pep_regf_rd_req_vld,
  output logic                                                      pep_regf_rd_req_rdy,
  input  regf_rd_req_t                                              pep_regf_rd_req,

  output logic [REGF_COEF_NB-1:0]                                   regf_pep_rd_data_avail,
  output logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0]                      regf_pep_rd_data,
  output logic                                                      regf_pep_rd_last_word, // valid with avail[0]
  output logic                                                      regf_pep_rd_is_body,
  output logic                                                      regf_pep_rd_last_mask,

  //== to regif
  output pem_counter_inc_t                                          pem_rif_counter_inc,
  output pea_counter_inc_t                                          pea_rif_counter_inc,
  output pem_info_t                                                 pem_rif_info,

  //== Configuration
  input  logic [PEM_PC_MAX-1:0][axi_if_ct_axi_pkg::AXI4_ADD_W-1:0]  ct_mem_addr

);

// ============================================================================================== --
// localparam
// ============================================================================================== --

// ============================================================================================== --
// Signals
// ============================================================================================== --
// Pe MEM -----------------------------------------------------------------------------------------
logic                                   pem_regf_wr_req_vld;
logic                                   pem_regf_wr_req_rdy;
regf_wr_req_t                           pem_regf_wr_req;
logic [REGF_COEF_NB-1:0]                pem_regf_wr_data_vld;
logic [REGF_COEF_NB-1:0]                pem_regf_wr_data_rdy;
logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0]   pem_regf_wr_data;
logic                                   regf_pem_wr_ack;

logic                                   pem_regf_rd_req_vld;
logic                                   pem_regf_rd_req_rdy;
regf_rd_req_t                           pem_regf_rd_req;
logic [REGF_COEF_NB-1:0]                regf_pem_rd_data_avail;
logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0]   regf_pem_rd_data;
logic                                   regf_pem_rd_last_word; // valid with avail[0]
logic                                   regf_pem_rd_is_body;
logic                                   regf_pem_rd_last_mask;

// Pe ALU -----------------------------------------------------------------------------------------
logic                                   pea_regf_wr_req_vld;
logic                                   pea_regf_wr_req_rdy;
regf_wr_req_t                           pea_regf_wr_req;
logic [REGF_COEF_NB-1:0]                pea_regf_wr_data_vld;
logic [REGF_COEF_NB-1:0]                pea_regf_wr_data_rdy;
logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0]   pea_regf_wr_data;
logic                                   regf_pea_wr_ack;

logic                                   pea_regf_rd_req_vld;
logic                                   pea_regf_rd_req_rdy;
regf_rd_req_t                           pea_regf_rd_req;
logic [REGF_COEF_NB-1:0]                regf_pea_rd_data_avail;
logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0]   regf_pea_rd_data;
logic                                   regf_pea_rd_last_word; // valid with avail[0]
logic                                   regf_pea_rd_is_body;
logic                                   regf_pea_rd_last_mask;

/// ============================================================================================== --
// Register file
// ============================================================================================== --
  regfile #(
    .PEA_PERIOD   (PEA_REGF_PERIOD  ),
    .PEM_PERIOD   (PEM_REGF_PERIOD  ),
    .PEP_PERIOD   (PEP_REGF_PERIOD  ),
    .URAM_LATENCY (URAM_LATENCY)
  ) regfile (
    .clk                    (clk    ),
    .s_rst_n                (s_rst_n),

    // PEM port
    .pem_regf_wr_req_vld    (pem_regf_wr_req_vld),
    .pem_regf_wr_req_rdy    (pem_regf_wr_req_rdy),
    .pem_regf_wr_req        (pem_regf_wr_req),
    .pem_regf_wr_data_vld   (pem_regf_wr_data_vld),
    .pem_regf_wr_data_rdy   (pem_regf_wr_data_rdy),
    .pem_regf_wr_data       (pem_regf_wr_data),
    .pem_wr_ack             (regf_pem_wr_ack),

    .pem_regf_rd_req_vld    (pem_regf_rd_req_vld),
    .pem_regf_rd_req_rdy    (pem_regf_rd_req_rdy),
    .pem_regf_rd_req        (pem_regf_rd_req),
    .regf_pem_rd_data_avail (regf_pem_rd_data_avail),
    .regf_pem_rd_data       (regf_pem_rd_data),
    .regf_pem_rd_last_word  (regf_pem_rd_last_word),
    .regf_pem_rd_is_body    (regf_pem_rd_is_body),
    .regf_pem_rd_last_mask  (regf_pem_rd_last_mask),

    // PEA port
    .pea_regf_wr_req_vld    (pea_regf_wr_req_vld),
    .pea_regf_wr_req_rdy    (pea_regf_wr_req_rdy),
    .pea_regf_wr_req        (pea_regf_wr_req),
    .pea_regf_wr_data_vld   (pea_regf_wr_data_vld),
    .pea_regf_wr_data_rdy   (pea_regf_wr_data_rdy),
    .pea_regf_wr_data       (pea_regf_wr_data),
    .pea_wr_ack             (regf_pea_wr_ack),

    .pea_regf_rd_req_vld    (pea_regf_rd_req_vld),
    .pea_regf_rd_req_rdy    (pea_regf_rd_req_rdy),
    .pea_regf_rd_req        (pea_regf_rd_req),
    .regf_pea_rd_data_avail (regf_pea_rd_data_avail),
    .regf_pea_rd_data       (regf_pea_rd_data),
    .regf_pea_rd_last_word  (regf_pea_rd_last_word),
    .regf_pea_rd_is_body    (regf_pea_rd_is_body),
    .regf_pea_rd_last_mask  (regf_pea_rd_last_mask),

    // PEP port
    .pep_regf_wr_req_vld    (pep_regf_wr_req_vld),
    .pep_regf_wr_req_rdy    (pep_regf_wr_req_rdy),
    .pep_regf_wr_req        (pep_regf_wr_req),
    .pep_regf_wr_data_vld   (pep_regf_wr_data_vld),
    .pep_regf_wr_data_rdy   (pep_regf_wr_data_rdy),
    .pep_regf_wr_data       (pep_regf_wr_data),
    .pep_wr_ack             (regf_pep_wr_ack),

    .pep_regf_rd_req_vld    (pep_regf_rd_req_vld),
    .pep_regf_rd_req_rdy    (pep_regf_rd_req_rdy),
    .pep_regf_rd_req        (pep_regf_rd_req),
    .regf_pep_rd_data_avail (regf_pep_rd_data_avail),
    .regf_pep_rd_data       (regf_pep_rd_data),
    .regf_pep_rd_last_word  (regf_pep_rd_last_word),
    .regf_pep_rd_is_body    (regf_pep_rd_is_body),
    .regf_pep_rd_last_mask  (regf_pep_rd_last_mask)
  );

/// ============================================================================================== --
// Processing elements
// ============================================================================================== --
// ---------------------------------------------------------------------------------------------- --
// PE_MEM
// ---------------------------------------------------------------------------------------------- --
pe_mem #(
    .INST_FIFO_DEPTH(PEM_INST_FIFO_DEPTH)
  ) pe_mem (
    .clk                   (clk    ),
    .s_rst_n               (s_rst_n),

    .ct_mem_addr           (ct_mem_addr),

    .inst                  (isc_pem_insn),
    .inst_vld              (isc_pem_vld),
    .inst_rdy              (isc_pem_rdy),

    .inst_load_ack         (pem_isc_load_ack),
    .inst_store_ack        (pem_isc_store_ack),

    // pem <-> regfile
    // write
    .pem_regf_wr_req_vld   (pem_regf_wr_req_vld),
    .pem_regf_wr_req_rdy   (pem_regf_wr_req_rdy),
    .pem_regf_wr_req       (pem_regf_wr_req),
    .pem_regf_wr_data_vld  (pem_regf_wr_data_vld),
    .pem_regf_wr_data_rdy  (pem_regf_wr_data_rdy),
    .pem_regf_wr_data      (pem_regf_wr_data),
    .regf_pem_wr_ack       (regf_pem_wr_ack),

    // read
    .pem_regf_rd_req_vld   (pem_regf_rd_req_vld),
    .pem_regf_rd_req_rdy   (pem_regf_rd_req_rdy),
    .pem_regf_rd_req       (pem_regf_rd_req),
    .regf_pem_rd_data_avail(regf_pem_rd_data_avail),
    .regf_pem_rd_data      (regf_pem_rd_data),
    .regf_pem_rd_last_word (regf_pem_rd_last_word),
    .regf_pem_rd_is_body   (regf_pem_rd_is_body),
    .regf_pem_rd_last_mask (regf_pem_rd_last_mask),

    // Connect to AXI interface
    .m_axi4_awid            (m_axi4_pem_awid),
    .m_axi4_awaddr          (m_axi4_pem_awaddr),
    .m_axi4_awlen           (m_axi4_pem_awlen),
    .m_axi4_awsize          (m_axi4_pem_awsize),
    .m_axi4_awburst         (m_axi4_pem_awburst),
    .m_axi4_awvalid         (m_axi4_pem_awvalid),
    .m_axi4_awready         (m_axi4_pem_awready),
    .m_axi4_wdata           (m_axi4_pem_wdata),
    .m_axi4_wstrb           (m_axi4_pem_wstrb),
    .m_axi4_wlast           (m_axi4_pem_wlast),
    .m_axi4_wvalid          (m_axi4_pem_wvalid),
    .m_axi4_wready          (m_axi4_pem_wready),
    .m_axi4_bid             (m_axi4_pem_bid),
    .m_axi4_bresp           (m_axi4_pem_bresp),
    .m_axi4_bvalid          (m_axi4_pem_bvalid),
    .m_axi4_bready          (m_axi4_pem_bready),
    .m_axi4_arid            (m_axi4_pem_arid),
    .m_axi4_araddr          (m_axi4_pem_araddr),
    .m_axi4_arlen           (m_axi4_pem_arlen),
    .m_axi4_arsize          (m_axi4_pem_arsize),
    .m_axi4_arburst         (m_axi4_pem_arburst),
    .m_axi4_arvalid         (m_axi4_pem_arvalid),
    .m_axi4_arready         (m_axi4_pem_arready),
    .m_axi4_rid             (m_axi4_pem_rid),
    .m_axi4_rdata           (m_axi4_pem_rdata),
    .m_axi4_rresp           (m_axi4_pem_rresp),
    .m_axi4_rlast           (m_axi4_pem_rlast),
    .m_axi4_rvalid          (m_axi4_pem_rvalid),
    .m_axi4_rready          (m_axi4_pem_rready),

    .pem_rif_counter_inc   (pem_rif_counter_inc),
    .pem_rif_info          (pem_rif_info)
  );

// ---------------------------------------------------------------------------------------------- --
// PE_ALU
// ---------------------------------------------------------------------------------------------- --
    pe_alu #(
    .INST_FIFO_DEPTH (PEA_INST_FIFO_DEPTH),
    .ALU_NB          (PEA_ALU_NB),
    .OUT_FIFO_DEPTH  (PEA_OUT_FIFO_DEPTH)
  ) pe_alu (
    .clk                    (clk    ),
    .s_rst_n                (s_rst_n),

    .inst                   (isc_pea_insn),
    .inst_vld               (isc_pea_vld),
    .inst_rdy               (isc_pea_rdy),

    .inst_ack               (pea_isc_ack),

    // pea <-> regfile
    // write
    .pea_regf_wr_req_vld    (pea_regf_wr_req_vld),
    .pea_regf_wr_req_rdy    (pea_regf_wr_req_rdy),
    .pea_regf_wr_req        (pea_regf_wr_req),
    .pea_regf_wr_data_vld   (pea_regf_wr_data_vld),
    .pea_regf_wr_data_rdy   (pea_regf_wr_data_rdy),
    .pea_regf_wr_data       (pea_regf_wr_data),
    .regf_pea_wr_ack        (regf_pea_wr_ack),

    // read
    .pea_regf_rd_req_vld    (pea_regf_rd_req_vld),
    .pea_regf_rd_req_rdy    (pea_regf_rd_req_rdy),
    .pea_regf_rd_req        (pea_regf_rd_req),
    .regf_pea_rd_data_avail (regf_pea_rd_data_avail),
    .regf_pea_rd_data       (regf_pea_rd_data),
    .regf_pea_rd_last_word  (regf_pea_rd_last_word),
    .regf_pea_rd_is_body    (regf_pea_rd_is_body),
    .regf_pea_rd_last_mask  (regf_pea_rd_last_mask),

    .pea_rif_counter_inc    (pea_rif_counter_inc)
  );

endmodule
