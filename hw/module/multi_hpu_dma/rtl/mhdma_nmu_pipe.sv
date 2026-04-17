// ================================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ------------------------------------------------------------------------------------------------
// Description  : NMU pipeline for MHDMA AXI4 channels
//
// Placed near the single NMU port to break long wires from the bridge core.
// Pipeline stages (fifo_element, depth = NMU_PLACEMENT_FIFO_DEPTH) on each channel.
//
// Channels:
//   AR (read address)  : pipeline
//   R  (read data)     : pipeline
//   AW (write address) : pipeline
//   W  (write data)    : pipeline
//   B  (write response): not handled here, goes directly NMU <-> bridge
//
// ================================================================================================

module mhdma_nmu_pipe
  import mhdma_pkg::*;               // for all mhdma modules
  import axi_if_mhdma_axi_pkg::*;    // AXI4
  import axi_if_common_param_pkg::*; // general axi4
#(
  parameter int FIFO_DEPTH = NMU_PLACEMENT_FIFO_DEPTH
) (
  input  logic                                clk,
  input  logic                                s_rst_n,
  // Single AXI4 read address channel (from slave via bridge) ----------------------------------
  input  logic [   AXI4_ID_W-1:0]             s_axi4_arid,
  input  logic [  AXI4_ADD_W-1:0]             s_axi4_araddr,
  input  logic [  AXI4_LEN_W-1:0]             s_axi4_arlen,
  input  logic [ AXI4_SIZE_W-1:0]             s_axi4_arsize,
  input  logic [AXI4_BURST_W-1:0]             s_axi4_arburst,
  input  logic                                s_axi4_arvalid,
  output logic                                s_axi4_arready,
  // Single AXI4 read data channel (to slave via bridge) ---------------------------------------
  output logic [AXI4_DATA_W-1:0]              s_axi4_rdata,
  output logic [AXI4_RESP_W-1:0]              s_axi4_rresp,
  output logic [  AXI4_ID_W-1:0]              s_axi4_rid,
  output logic                                s_axi4_rlast,
  output logic                                s_axi4_rvalid,
  input  logic                                s_axi4_rready,
  // Single AXI4 write address channel (from master via bridge) --------------------------------
  input  logic [   AXI4_ID_W-1:0]             s_axi4_awid,
  input  logic [  AXI4_ADD_W-1:0]             s_axi4_awaddr,
  input  logic [  AXI4_LEN_W-1:0]             s_axi4_awlen,
  input  logic [ AXI4_SIZE_W-1:0]             s_axi4_awsize,
  input  logic [AXI4_BURST_W-1:0]             s_axi4_awburst,
  input  logic                                s_axi4_awvalid,
  output logic                                s_axi4_awready,
  // Single AXI4 write data channel (from master via bridge) -----------------------------------
  input  logic [AXI4_DATA_W-1:0]              s_axi4_wdata,
  input  logic [AXI4_STRB_W-1:0]              s_axi4_wstrb,
  input  logic                                s_axi4_wlast,
  input  logic                                s_axi4_wvalid,
  output logic                                s_axi4_wready,
  // Single AXI4 NMU port (active NMU connection) ----------------------------------------------
  // Read address
  output logic [   AXI4_ID_W-1:0]             m_axi4_arid,
  output logic [  AXI4_ADD_W-1:0]             m_axi4_araddr,
  output logic [  AXI4_LEN_W-1:0]             m_axi4_arlen,
  output logic [ AXI4_SIZE_W-1:0]             m_axi4_arsize,
  output logic [AXI4_BURST_W-1:0]             m_axi4_arburst,
  output logic                                m_axi4_arvalid,
  input  logic                                m_axi4_arready,
  // Read data
  input  logic [AXI4_DATA_W-1:0]              m_axi4_rdata,
  input  logic [AXI4_RESP_W-1:0]              m_axi4_rresp,
  input  logic [  AXI4_ID_W-1:0]              m_axi4_rid,
  input  logic                                m_axi4_rlast,
  input  logic                                m_axi4_rvalid,
  output logic                                m_axi4_rready,
  // Write address
  output logic [   AXI4_ID_W-1:0]             m_axi4_awid,
  output logic [  AXI4_ADD_W-1:0]             m_axi4_awaddr,
  output logic [  AXI4_LEN_W-1:0]             m_axi4_awlen,
  output logic [ AXI4_SIZE_W-1:0]             m_axi4_awsize,
  output logic [AXI4_BURST_W-1:0]             m_axi4_awburst,
  output logic                                m_axi4_awvalid,
  input  logic                                m_axi4_awready,
  // Write data
  output logic [AXI4_DATA_W-1:0]              m_axi4_wdata,
  output logic [AXI4_STRB_W-1:0]              m_axi4_wstrb,
  output logic                                m_axi4_wlast,
  output logic                                m_axi4_wvalid,
  input  logic                                m_axi4_wready
  // Note: B channel (write response) is NOT handled here.
);

  // =========================================================================================== //
  // AR channel pipeline
  // =========================================================================================== //
  axi4_ar_if_t ar_pipe_out;
  logic        ar_pipe_out_vld;

  fifo_element #(
    .WIDTH         (AXI4_AR_IF_W),
    .DEPTH         (1'b1),
    .TYPE_ARRAY    (4'h3),
    .DO_RESET_DATA (0),
    .RESET_DATA_VAL(0)
  ) fifo_ar_placement (
    .clk     (clk),
    .s_rst_n (s_rst_n),
    .in_data ({s_axi4_arid, s_axi4_araddr, s_axi4_arlen, s_axi4_arsize, s_axi4_arburst}),
    .in_vld  (s_axi4_arvalid),
    .in_rdy  (s_axi4_arready),
    .out_data(ar_pipe_out),
    .out_vld (ar_pipe_out_vld),
    .out_rdy (m_axi4_arready)
  );

  assign m_axi4_arid    = ar_pipe_out.arid;
  assign m_axi4_araddr  = ar_pipe_out.araddr;
  assign m_axi4_arlen   = ar_pipe_out.arlen;
  assign m_axi4_arsize  = ar_pipe_out.arsize;
  assign m_axi4_arburst = ar_pipe_out.arburst;
  assign m_axi4_arvalid = ar_pipe_out_vld;

  // =========================================================================================== //
  // R channel pipeline
  // =========================================================================================== //
  axi4_r_if_t r_pipe_out;
  logic       r_pipe_out_vld;

  fifo_element #(
    .WIDTH         (AXI4_R_IF_W),
    .DEPTH         (FIFO_DEPTH),
    .TYPE_ARRAY    ({{FIFO_DEPTH-1{4'h1}}, 4'h2}),
    .DO_RESET_DATA (0),
    .RESET_DATA_VAL(0)
  ) fifo_r_placement (
    .clk     (clk),
    .s_rst_n (s_rst_n),
    .in_data ({m_axi4_rid, m_axi4_rdata, m_axi4_rresp, m_axi4_rlast}),
    .in_vld  (m_axi4_rvalid),
    .in_rdy  (m_axi4_rready),
    .out_data(r_pipe_out),
    .out_vld (r_pipe_out_vld),
    .out_rdy (s_axi4_rready)
  );

  assign s_axi4_rid    = r_pipe_out.rid;
  assign s_axi4_rdata  = r_pipe_out.rdata;
  assign s_axi4_rresp  = r_pipe_out.rresp;
  assign s_axi4_rlast  = r_pipe_out.rlast;
  assign s_axi4_rvalid = r_pipe_out_vld;

  // =========================================================================================== //
  // AW channel pipeline
  // =========================================================================================== //
  axi4_aw_if_t aw_pipe_out;
  logic        aw_pipe_out_vld;

  fifo_element #(
    .WIDTH         (AXI4_AW_IF_W),
    .DEPTH         (1'b1),
    .TYPE_ARRAY    (4'h3),
    .DO_RESET_DATA (0),
    .RESET_DATA_VAL(0)
  ) fifo_aw_placement (
    .clk     (clk),
    .s_rst_n (s_rst_n),
    .in_data ({s_axi4_awid, s_axi4_awaddr, s_axi4_awlen, s_axi4_awsize, s_axi4_awburst}),
    .in_vld  (s_axi4_awvalid),
    .in_rdy  (s_axi4_awready),
    .out_data(aw_pipe_out),
    .out_vld (aw_pipe_out_vld),
    .out_rdy (m_axi4_awready)
  );

  assign m_axi4_awid    = aw_pipe_out.awid;
  assign m_axi4_awaddr  = aw_pipe_out.awaddr;
  assign m_axi4_awlen   = aw_pipe_out.awlen;
  assign m_axi4_awsize  = aw_pipe_out.awsize;
  assign m_axi4_awburst = aw_pipe_out.awburst;
  assign m_axi4_awvalid = aw_pipe_out_vld;

  // =========================================================================================== //
  // W channel pipeline
  // =========================================================================================== //
  axi4_w_if_t w_pipe_out;
  logic       w_pipe_out_vld;

  fifo_element #(
    .WIDTH         (AXI4_W_IF_W),
    .DEPTH         (FIFO_DEPTH),
    .TYPE_ARRAY    ({{FIFO_DEPTH-1{4'h1}}, 4'h2}),
    .DO_RESET_DATA (0),
    .RESET_DATA_VAL(0)
  ) fifo_w_placement (
    .clk     (clk),
    .s_rst_n (s_rst_n),
    .in_data ({s_axi4_wdata, s_axi4_wstrb, s_axi4_wlast}),
    .in_vld  (s_axi4_wvalid),
    .in_rdy  (s_axi4_wready),
    .out_data(w_pipe_out),
    .out_vld (w_pipe_out_vld),
    .out_rdy (m_axi4_wready)
  );

  assign m_axi4_wdata  = w_pipe_out.wdata;
  assign m_axi4_wstrb  = w_pipe_out.wstrb;
  assign m_axi4_wlast  = w_pipe_out.wlast;
  assign m_axi4_wvalid = w_pipe_out_vld;

endmodule
