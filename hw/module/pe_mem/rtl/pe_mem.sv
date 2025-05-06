// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module is a processing element (PE) of the HPU.
// It deals with the loading and storage of BLWE between the memory (DDR or HBM) and
// the register_file.
// ==============================================================================================

module pe_mem
  import param_tfhe_pkg::*;
  import regf_common_param_pkg::*;
  import axi_if_common_param_pkg::*;
  import axi_if_ct_axi_pkg::*;
  import hpu_common_instruction_pkg::*;
  import top_common_param_pkg::*;
  import pem_common_param_pkg::*;
#(
  parameter int INST_FIFO_DEPTH = 8 // Should be >= 5
)
(
  input  logic                                   clk,        // clock
  input  logic                                   s_rst_n,    // synchronous reset

  input  logic [PEM_PC_MAX-1:0][AXI4_ADD_W-1:0]  ct_mem_addr,

  input  logic [PE_INST_W-1:0]                   inst,
  input  logic                                   inst_vld,
  output logic                                   inst_rdy,

  output logic                                   inst_load_ack,
  output logic                                   inst_store_ack,

  // pem <-> regfile
  // write
  output logic                                   pem_regf_wr_req_vld,
  input  logic                                   pem_regf_wr_req_rdy,
  output logic [REGF_WR_REQ_W-1:0]               pem_regf_wr_req,

  output logic [REGF_COEF_NB-1:0]                pem_regf_wr_data_vld,
  input  logic [REGF_COEF_NB-1:0]                pem_regf_wr_data_rdy,
  output logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0]   pem_regf_wr_data,

  input                                          regf_pem_wr_ack,

  // read
  output logic                                   pem_regf_rd_req_vld,
  input  logic                                   pem_regf_rd_req_rdy,
  output logic [REGF_RD_REQ_W-1:0]               pem_regf_rd_req,

  input  logic [REGF_COEF_NB-1:0]                regf_pem_rd_data_avail,
  input  logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0]   regf_pem_rd_data,
  input  logic                                   regf_pem_rd_last_word, // valid with avail[0]
  input  logic                                   regf_pem_rd_is_body,
  input  logic                                   regf_pem_rd_last_mask,

  // AXI4 interface to/from memory
  // Write channel
  output logic [PEM_PC-1:0][AXI4_ID_W-1:0]       m_axi4_awid,
  output logic [PEM_PC-1:0][AXI4_ADD_W-1:0]      m_axi4_awaddr,
  output logic [PEM_PC-1:0][AXI4_LEN_W-1:0]      m_axi4_awlen,
  output logic [PEM_PC-1:0][AXI4_SIZE_W-1:0]     m_axi4_awsize,
  output logic [PEM_PC-1:0][AXI4_BURST_W-1:0]    m_axi4_awburst,
  output logic [PEM_PC-1:0]                      m_axi4_awvalid,
  input  logic [PEM_PC-1:0]                      m_axi4_awready,
  output logic [PEM_PC-1:0][AXI4_DATA_W-1:0]     m_axi4_wdata,
  output logic [PEM_PC-1:0][AXI4_STRB_W-1:0]     m_axi4_wstrb,
  output logic [PEM_PC-1:0]                      m_axi4_wlast,
  output logic [PEM_PC-1:0]                      m_axi4_wvalid,
  input  logic [PEM_PC-1:0]                      m_axi4_wready,
  input  logic [PEM_PC-1:0][AXI4_ID_W-1:0]       m_axi4_bid,
  input  logic [PEM_PC-1:0][AXI4_RESP_W-1:0]     m_axi4_bresp,
  input  logic [PEM_PC-1:0]                      m_axi4_bvalid,
  output logic [PEM_PC-1:0]                      m_axi4_bready,
  // Read channel
  output logic [PEM_PC-1:0][AXI4_ID_W-1:0]       m_axi4_arid,
  output logic [PEM_PC-1:0][AXI4_ADD_W-1:0]      m_axi4_araddr,
  output logic [PEM_PC-1:0][AXI4_LEN_W-1:0]      m_axi4_arlen,
  output logic [PEM_PC-1:0][AXI4_SIZE_W-1:0]     m_axi4_arsize,
  output logic [PEM_PC-1:0][AXI4_BURST_W-1:0]    m_axi4_arburst,
  output logic [PEM_PC-1:0]                      m_axi4_arvalid,
  input  logic [PEM_PC-1:0]                      m_axi4_arready,
  input  logic [PEM_PC-1:0][AXI4_ID_W-1:0]       m_axi4_rid,
  input  logic [PEM_PC-1:0][AXI4_DATA_W-1:0]     m_axi4_rdata,
  input  logic [PEM_PC-1:0][AXI4_RESP_W-1:0]     m_axi4_rresp,
  input  logic [PEM_PC-1:0]                      m_axi4_rlast,
  input  logic [PEM_PC-1:0]                      m_axi4_rvalid,
  output logic [PEM_PC-1:0]                      m_axi4_rready,

  output pem_counter_inc_t                       pem_rif_counter_inc,
  output pem_info_t                              pem_rif_info
);

// ============================================================================================== --
// Check parameters
// ============================================================================================== --
// pragma translate_off
  initial begin
    assert(INST_FIFO_DEPTH >= 5)
    else begin
      $fatal(1,"%t > ERROR: parameter INST_FIFO_DEPTH must be >= 5!", $time);
    end
  end
// pragma translate_on

// ============================================================================================== --
// Input FIFO
// ============================================================================================== --
// Use 2 FIFOs, one for the store commands, one for the load commands.
  logic      in_is_load;
  pem_inst_t in_inst;
  pem_cmd_t  in_cmd;
  logic      in_ld_vld;
  logic      in_ld_rdy;
  logic      in_st_vld;
  logic      in_st_rdy;

  pem_cmd_t  s0_ld_cmd;
  logic      s0_ld_vld;
  logic      s0_ld_rdy;
  pem_cmd_t  s0_st_cmd;
  logic      s0_st_vld;
  logic      s0_st_rdy;

  assign in_inst       = inst;
  assign in_is_load    = in_inst.dop == DOP_LD;
  assign in_ld_vld     = inst_vld & in_is_load;
  assign in_st_vld     = inst_vld & ~in_is_load;
  assign inst_rdy      = in_is_load ? in_ld_rdy : in_st_rdy;
  assign in_cmd.reg_id = in_inst.rid[REGF_REGID_W-1:0]; // Keep bits that are really used.
  assign in_cmd.cid    = in_inst.cid;

  fifo_element #(
    .WIDTH          (PEM_CMD_W),
    .DEPTH          (1),
    .TYPE_ARRAY     (4'h3),// TOREVIEW
    .DO_RESET_DATA  (1'b0),
    .RESET_DATA_VAL (0)
  ) in_ld_fifo_element (
    .clk      (clk),
    .s_rst_n  (s_rst_n),

    .in_data  (in_cmd),
    .in_vld   (in_ld_vld),
    .in_rdy   (in_ld_rdy),

    .out_data (s0_ld_cmd),
    .out_vld  (s0_ld_vld),
    .out_rdy  (s0_ld_rdy)
  );

  fifo_element #(
    .WIDTH          (PEM_CMD_W),
    .DEPTH          (1),
    .TYPE_ARRAY     (4'h3),// TOREVIEW
    .DO_RESET_DATA  (1'b0),
    .RESET_DATA_VAL (0)
  ) in_st_fifo_reg (
    .clk      (clk),
    .s_rst_n  (s_rst_n),

    .in_data  (in_cmd),
    .in_vld   (in_st_vld),
    .in_rdy   (in_st_rdy),

    .out_data (s0_st_cmd),
    .out_vld  (s0_st_vld),
    .out_rdy  (s0_st_rdy)
  );

// pragma translate_off
  always_ff @(posedge clk)
    if (inst_vld && inst_rdy)
      assert(in_inst.rid < REGF_REG_NB)
      else begin
        $fatal(1,"%t > ERROR: DOP with a rid(%0d) >= REGF_REG_NB (%0d)", $time, in_inst.rid, REGF_REG_NB);
      end
// pragma translate_on

// ============================================================================================== --
// pem_load
// ============================================================================================== --
  pem_ld_info_t pem_ld_info;

  pem_load #(
    .INST_FIFO_DEPTH(INST_FIFO_DEPTH-1)
  ) pem_load (
    .clk                  (clk    ),
    .s_rst_n              (s_rst_n),

    .ct_mem_addr          (ct_mem_addr), // Address offset for CT

    .cmd                  (s0_ld_cmd),
    .cmd_vld              (s0_ld_vld),
    .cmd_rdy              (s0_ld_rdy),

    .cmd_ack              (inst_load_ack),

    .pem_regf_wr_req_vld  (pem_regf_wr_req_vld),
    .pem_regf_wr_req_rdy  (pem_regf_wr_req_rdy),
    .pem_regf_wr_req      (pem_regf_wr_req),

    .pem_regf_wr_data_vld (pem_regf_wr_data_vld),
    .pem_regf_wr_data_rdy (pem_regf_wr_data_rdy),
    .pem_regf_wr_data     (pem_regf_wr_data),

    .regf_pem_wr_ack      (regf_pem_wr_ack),

    .m_axi4_arid          (m_axi4_arid),
    .m_axi4_araddr        (m_axi4_araddr),
    .m_axi4_arlen         (m_axi4_arlen),
    .m_axi4_arsize        (m_axi4_arsize),
    .m_axi4_arburst       (m_axi4_arburst),
    .m_axi4_arvalid       (m_axi4_arvalid),
    .m_axi4_arready       (m_axi4_arready),
    .m_axi4_rid           (m_axi4_rid),
    .m_axi4_rdata         (m_axi4_rdata),
    .m_axi4_rresp         (m_axi4_rresp),
    .m_axi4_rlast         (m_axi4_rlast),
    .m_axi4_rvalid        (m_axi4_rvalid),
    .m_axi4_rready        (m_axi4_rready),

    .pem_ld_info          (pem_ld_info)
  );

// ============================================================================================== --
// pem_store
// ============================================================================================== --
  pem_st_info_t pem_st_info;

  pem_store #(
    .INST_FIFO_DEPTH(INST_FIFO_DEPTH-1)
  ) pem_store (
    .clk                    (clk    ),
    .s_rst_n                (s_rst_n),

    .ct_mem_addr            (ct_mem_addr), // Address offset for CT

    .cmd                    (s0_st_cmd),
    .cmd_vld                (s0_st_vld),
    .cmd_rdy                (s0_st_rdy),

    .cmd_ack                (inst_store_ack),

    .pem_regf_rd_req_vld    (pem_regf_rd_req_vld),
    .pem_regf_rd_req_rdy    (pem_regf_rd_req_rdy),
    .pem_regf_rd_req        (pem_regf_rd_req),

    .regf_pem_rd_data_avail (regf_pem_rd_data_avail),
    .regf_pem_rd_data       (regf_pem_rd_data),
    .regf_pem_rd_last_word  (regf_pem_rd_last_word),
    .regf_pem_rd_is_body    (regf_pem_rd_is_body),
    .regf_pem_rd_last_mask  (regf_pem_rd_last_mask),

    .m_axi4_awid            (m_axi4_awid),
    .m_axi4_awaddr          (m_axi4_awaddr),
    .m_axi4_awlen           (m_axi4_awlen),
    .m_axi4_awsize          (m_axi4_awsize),
    .m_axi4_awburst         (m_axi4_awburst),
    .m_axi4_awvalid         (m_axi4_awvalid),
    .m_axi4_awready         (m_axi4_awready),
    .m_axi4_wdata           (m_axi4_wdata),
    .m_axi4_wstrb           (m_axi4_wstrb),
    .m_axi4_wlast           (m_axi4_wlast),
    .m_axi4_wvalid          (m_axi4_wvalid),
    .m_axi4_wready          (m_axi4_wready),
    .m_axi4_bid             (m_axi4_bid),
    .m_axi4_bresp           (m_axi4_bresp),
    .m_axi4_bvalid          (m_axi4_bvalid),
    .m_axi4_bready          (m_axi4_bready),

    .pem_st_info            (pem_st_info)
  );

// ============================================================================================== --
// Counters / Info
// ============================================================================================== --
  pem_counter_inc_t pem_rif_counter_incD;
  pem_info_t        pem_rif_infoD;

  always_comb begin
    pem_rif_counter_incD = '0;
    pem_rif_infoD        = '0;

    pem_rif_infoD.load   = pem_ld_info;
    pem_rif_infoD.store  = pem_st_info;

    pem_rif_counter_incD.load.inst_inc  = inst_vld & inst_rdy & in_is_load;
    pem_rif_counter_incD.load.ack_inc   = inst_load_ack;
    pem_rif_counter_incD.store.inst_inc = inst_vld & inst_rdy & ~in_is_load;
    pem_rif_counter_incD.store.ack_inc  = inst_store_ack;
  end

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      pem_rif_counter_inc <= '0;
      pem_rif_info        <= '0;
    end
    else begin
      pem_rif_counter_inc <= pem_rif_counter_incD;
      pem_rif_info        <= pem_rif_infoD;
    end

endmodule
