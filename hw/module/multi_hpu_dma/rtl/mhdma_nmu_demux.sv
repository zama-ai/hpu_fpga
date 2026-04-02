// ================================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ------------------------------------------------------------------------------------------------
// Description  : NMU demultiplexer for MHDMA AXI4 channels
//
// Placed near NMU ports to avoid stretching the mhdma_bridge logic across the SLR.
// Takes single-port AXI4 interfaces from the bridge and demuxes/muxes them to/from
// per-PC NMU ports using one-hot PC selectors.
//
// Pipeline stages (fifo_element, depth = NMU_PLACEMENT_FIFO_DEPTH) are placed on each
// channel input to break long wires from the bridge core.
//
// Channels:
//   AR (read address)  : pipeline -> broadcast address, gate arvalid with ar_pc_sel
//   R  (read data)     : mux rdata/rvalid back -> pipeline -> bridge
//   AW (write address) : pipeline -> broadcast address, gate awvalid with wr_pc_sel
//   W  (write data)    : pipeline -> broadcast data, gate wvalid with wr_pc_sel
//   B  (write response): not handled here, goes directly NMU <-> bridge (per-PC)
//
// ================================================================================================

module mhdma_nmu_demux
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
  // PC selectors for read path ----------------------------------------------------------------
  input  logic [ETH_PC-1:0]                   ar_pc_sel,
  input  logic [ETH_PC-1:0]                   rd_pc_sel,
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
  // PC selector for write path ----------------------------------------------------------------
  input  logic [ETH_PC-1:0]                   wr_pc_sel,
  // Per-PC AXI4 NMU ports (active NMU connections) --------------------------------------------
  // Read address
  output logic [ETH_PC-1:0][   AXI4_ID_W-1:0] m_axi4_arid,
  output logic [ETH_PC-1:0][  AXI4_ADD_W-1:0] m_axi4_araddr,
  output logic [ETH_PC-1:0][  AXI4_LEN_W-1:0] m_axi4_arlen,
  output logic [ETH_PC-1:0][ AXI4_SIZE_W-1:0] m_axi4_arsize,
  output logic [ETH_PC-1:0][AXI4_BURST_W-1:0] m_axi4_arburst,
  output logic [ETH_PC-1:0]                   m_axi4_arvalid,
  input  logic [ETH_PC-1:0]                   m_axi4_arready,
  // Read data
  input  logic [ETH_PC-1:0][AXI4_DATA_W-1:0]  m_axi4_rdata,
  input  logic [ETH_PC-1:0][AXI4_RESP_W-1:0]  m_axi4_rresp,
  input  logic [ETH_PC-1:0][  AXI4_ID_W-1:0]  m_axi4_rid,
  input  logic [ETH_PC-1:0]                   m_axi4_rlast,
  input  logic [ETH_PC-1:0]                   m_axi4_rvalid,
  output logic [ETH_PC-1:0]                   m_axi4_rready,
  // Write address
  output logic [ETH_PC-1:0][   AXI4_ID_W-1:0] m_axi4_awid,
  output logic [ETH_PC-1:0][  AXI4_ADD_W-1:0] m_axi4_awaddr,
  output logic [ETH_PC-1:0][  AXI4_LEN_W-1:0] m_axi4_awlen,
  output logic [ETH_PC-1:0][ AXI4_SIZE_W-1:0] m_axi4_awsize,
  output logic [ETH_PC-1:0][AXI4_BURST_W-1:0] m_axi4_awburst,
  output logic [ETH_PC-1:0]                   m_axi4_awvalid,
  input  logic [ETH_PC-1:0]                   m_axi4_awready,
  // Write data
  output logic [ETH_PC-1:0][AXI4_DATA_W-1:0]  m_axi4_wdata,
  output logic [ETH_PC-1:0][AXI4_STRB_W-1:0]  m_axi4_wstrb,
  output logic [ETH_PC-1:0]                   m_axi4_wlast,
  output logic [ETH_PC-1:0]                   m_axi4_wvalid,
  input  logic [ETH_PC-1:0]                   m_axi4_wready
  // Note: B channel (write response) is NOT handled here.
  // It goes directly from NMU to bridge (per-PC) because master needs per-PC B tracking.
);

  // =========================================================================================== //
  // One-hot to index conversion for R channel (used before pipeline, on NMU side)
  // AR/AW/W pc_sel are piped with data, converted to index after pipeline output
  // =========================================================================================== //
  logic [ETH_PC_W-1:0] rd_pc_idx;
  logic [ETH_PC:0][ETH_PC_W-1:0] rd_pc_idx_chain;

  assign rd_pc_idx_chain[0] = 'h0;

  generate
    for (genvar i = 0; i < ETH_PC; i++) begin : gen_rd_pc_idx
      assign rd_pc_idx_chain[i+1] = rd_pc_sel[i] ? ETH_PC_W'(i) : rd_pc_idx_chain[i];
    end
  endgenerate

  assign rd_pc_idx = rd_pc_idx_chain[ETH_PC];

  // =========================================================================================== //
  // AR channel: pipeline (with pc_sel) -> broadcast address, gate valid per-PC
  // =========================================================================================== //
  localparam int AR_PIPE_W = AXI4_AR_IF_W + ETH_PC;

  logic [AR_PIPE_W-1:0]  ar_pipe_out_packed;
  axi4_ar_if_t           ar_pipe_out;
  logic [ETH_PC-1:0]     ar_pc_sel_pipe;
  logic                  ar_pipe_out_vld;
  logic                  ar_pipe_out_rdy;
  logic [ETH_PC_W-1:0]  ar_pc_idx_pipe;
  logic [ETH_PC:0][ETH_PC_W-1:0] ar_pc_idx_pipe_chain;

  fifo_element #(
    .WIDTH         (AR_PIPE_W),
    .DEPTH         (FIFO_DEPTH),
    .TYPE_ARRAY    ({4'h2, 4'h1}),
    .DO_RESET_DATA (0),
    .RESET_DATA_VAL(0)
  ) fifo_ar_placement (
    .clk     (clk),
    .s_rst_n (s_rst_n),
    .in_data ({ar_pc_sel, s_axi4_arid, s_axi4_araddr, s_axi4_arlen, s_axi4_arsize, s_axi4_arburst}),
    .in_vld  (s_axi4_arvalid),
    .in_rdy  (s_axi4_arready),
    .out_data(ar_pipe_out_packed),
    .out_vld (ar_pipe_out_vld),
    .out_rdy (ar_pipe_out_rdy)
  );

  assign {ar_pc_sel_pipe, ar_pipe_out} = ar_pipe_out_packed;

  assign ar_pc_idx_pipe_chain[0] = 'h0;
  generate
    for (genvar i = 0; i < ETH_PC; i++) begin : gen_ar_pc_idx
      assign ar_pc_idx_pipe_chain[i+1] = ar_pc_sel_pipe[i] ? ETH_PC_W'(i) : ar_pc_idx_pipe_chain[i];
    end
  endgenerate
  assign ar_pc_idx_pipe = ar_pc_idx_pipe_chain[ETH_PC];

  assign ar_pipe_out_rdy = m_axi4_arready[ar_pc_idx_pipe];

  generate
    for (genvar i = 0; i < ETH_PC; i++) begin : gen_ar_demux
      assign m_axi4_arid[i]    = ar_pipe_out.arid;
      assign m_axi4_araddr[i]  = ar_pipe_out.araddr;
      assign m_axi4_arlen[i]   = ar_pipe_out.arlen;
      assign m_axi4_arsize[i]  = ar_pipe_out.arsize;
      assign m_axi4_arburst[i] = ar_pipe_out.arburst;
      assign m_axi4_arvalid[i] = ar_pipe_out_vld & ar_pc_sel_pipe[i];
    end
  endgenerate

  // =========================================================================================== //
  // R channel: mux data back -> pipeline -> bridge
  // =========================================================================================== //
  logic [AXI4_R_IF_W-1:0] r_mux_data;
  logic                   r_mux_vld;
  logic                   r_mux_rdy;

  assign r_mux_data = {m_axi4_rid[rd_pc_idx], m_axi4_rdata[rd_pc_idx],
                        m_axi4_rresp[rd_pc_idx], m_axi4_rlast[rd_pc_idx]};
  assign r_mux_vld  = m_axi4_rvalid[rd_pc_idx];

  axi4_r_if_t r_pipe_out;
  logic       r_pipe_out_vld;

  fifo_element #(
    .WIDTH         (AXI4_R_IF_W),
    .DEPTH         (FIFO_DEPTH),
    .TYPE_ARRAY    ({4'h2, 4'h1}),
    .DO_RESET_DATA (0),
    .RESET_DATA_VAL(0)
  ) fifo_r_placement (
    .clk     (clk),
    .s_rst_n (s_rst_n),
    .in_data (r_mux_data),
    .in_vld  (r_mux_vld),
    .in_rdy  (r_mux_rdy),
    .out_data(r_pipe_out),
    .out_vld (r_pipe_out_vld),
    .out_rdy (s_axi4_rready)
  );

  assign s_axi4_rid    = r_pipe_out.rid;
  assign s_axi4_rdata  = r_pipe_out.rdata;
  assign s_axi4_rresp  = r_pipe_out.rresp;
  assign s_axi4_rlast  = r_pipe_out.rlast;
  assign s_axi4_rvalid = r_pipe_out_vld;

  generate
    for (genvar i = 0; i < ETH_PC; i++) begin : gen_rready_demux
      assign m_axi4_rready[i] = rd_pc_sel[i] ? r_mux_rdy : 1'b0;
    end
  endgenerate

  // =========================================================================================== //
  // AW channel: pipeline (with pc_sel) -> broadcast address, gate valid per-PC
  // =========================================================================================== //
  localparam int AW_PIPE_W = AXI4_AW_IF_W + ETH_PC;

  logic [AW_PIPE_W-1:0]  aw_pipe_out_packed;
  axi4_aw_if_t           aw_pipe_out;
  logic [ETH_PC-1:0]     aw_pc_sel_pipe;
  logic                  aw_pipe_out_vld;
  logic                  aw_pipe_out_rdy;
  logic [ETH_PC_W-1:0]  aw_pc_idx_pipe;
  logic [ETH_PC:0][ETH_PC_W-1:0] aw_pc_idx_pipe_chain;

  fifo_element #(
    .WIDTH         (AW_PIPE_W),
    .DEPTH         (FIFO_DEPTH),
    .TYPE_ARRAY    ({4'h2, 4'h1}),
    .DO_RESET_DATA (0),
    .RESET_DATA_VAL(0)
  ) fifo_aw_placement (
    .clk     (clk),
    .s_rst_n (s_rst_n),
    .in_data ({wr_pc_sel, s_axi4_awid, s_axi4_awaddr, s_axi4_awlen, s_axi4_awsize, s_axi4_awburst}),
    .in_vld  (s_axi4_awvalid),
    .in_rdy  (s_axi4_awready),
    .out_data(aw_pipe_out_packed),
    .out_vld (aw_pipe_out_vld),
    .out_rdy (aw_pipe_out_rdy)
  );

  assign {aw_pc_sel_pipe, aw_pipe_out} = aw_pipe_out_packed;

  assign aw_pc_idx_pipe_chain[0] = 'h0;
  generate
    for (genvar i = 0; i < ETH_PC; i++) begin : gen_aw_pc_idx
      assign aw_pc_idx_pipe_chain[i+1] = aw_pc_sel_pipe[i] ? ETH_PC_W'(i) : aw_pc_idx_pipe_chain[i];
    end
  endgenerate
  assign aw_pc_idx_pipe = aw_pc_idx_pipe_chain[ETH_PC];

  assign aw_pipe_out_rdy = m_axi4_awready[aw_pc_idx_pipe];

  generate
    for (genvar i = 0; i < ETH_PC; i++) begin : gen_aw_demux
      assign m_axi4_awid[i]    = aw_pipe_out.awid;
      assign m_axi4_awaddr[i]  = aw_pipe_out.awaddr;
      assign m_axi4_awlen[i]   = aw_pipe_out.awlen;
      assign m_axi4_awsize[i]  = aw_pipe_out.awsize;
      assign m_axi4_awburst[i] = aw_pipe_out.awburst;
      assign m_axi4_awvalid[i] = aw_pipe_out_vld & aw_pc_sel_pipe[i];
    end
  endgenerate

  // =========================================================================================== //
  // W channel: pipeline (with pc_sel) -> broadcast data, gate valid per-PC
  // =========================================================================================== //
  localparam int W_PIPE_W = AXI4_W_IF_W + ETH_PC;

  logic [W_PIPE_W-1:0]  w_pipe_out_packed;
  axi4_w_if_t           w_pipe_out;
  logic [ETH_PC-1:0]    w_pc_sel_pipe;
  logic                 w_pipe_out_vld;
  logic                 w_pipe_out_rdy;
  logic [ETH_PC_W-1:0]  w_pc_idx_pipe;
  logic [ETH_PC:0][ETH_PC_W-1:0] w_pc_idx_pipe_chain;

  fifo_element #(
    .WIDTH         (W_PIPE_W),
    .DEPTH         (FIFO_DEPTH),
    .TYPE_ARRAY    ({4'h2, 4'h1}),
    .DO_RESET_DATA (0),
    .RESET_DATA_VAL(0)
  ) fifo_w_placement (
    .clk     (clk),
    .s_rst_n (s_rst_n),
    .in_data ({wr_pc_sel, s_axi4_wdata, s_axi4_wstrb, s_axi4_wlast}),
    .in_vld  (s_axi4_wvalid),
    .in_rdy  (s_axi4_wready),
    .out_data(w_pipe_out_packed),
    .out_vld (w_pipe_out_vld),
    .out_rdy (w_pipe_out_rdy)
  );

  assign {w_pc_sel_pipe, w_pipe_out} = w_pipe_out_packed;

  assign w_pc_idx_pipe_chain[0] = 'h0;

  generate
    for (genvar i = 0; i < ETH_PC; i++) begin : gen_w_pc_idx
      assign w_pc_idx_pipe_chain[i+1] = w_pc_sel_pipe[i] ? ETH_PC_W'(i) : w_pc_idx_pipe_chain[i];
    end
  endgenerate

  assign w_pc_idx_pipe = w_pc_idx_pipe_chain[ETH_PC];

  assign w_pipe_out_rdy = m_axi4_wready[w_pc_idx_pipe];

  generate
    for (genvar i = 0; i < ETH_PC; i++) begin : gen_w_demux
      assign m_axi4_wdata[i]  = w_pipe_out.wdata;
      assign m_axi4_wstrb[i]  = w_pipe_out.wstrb;
      assign m_axi4_wlast[i]  = w_pipe_out.wlast;
      assign m_axi4_wvalid[i] = w_pipe_out_vld & w_pc_sel_pipe[i];
    end
  endgenerate

endmodule
