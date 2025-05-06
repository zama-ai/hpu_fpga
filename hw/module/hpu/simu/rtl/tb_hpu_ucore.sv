// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Ublaze + satellite modules.
// Used in tb_hpu for v80's HPU, where there is no ublaze inside.
// The testbench ublaze is used to simulate the RPU, which translates IOP into DOP code
// and sends it to the HPU.
// ==============================================================================================

module tb_hpu_ucore
  import hpu_common_instruction_pkg::*;
  import axi_if_common_param_pkg::*;
  import axi_if_ucore_axi_pkg::*;
  import axi_if_shell_axil_pkg::*;
  // Package used to modelize the communication between the host and the testbench ublaze
  import tb_hpu_ucore_regif_pkg::*;
#(
  parameter int    AXI4_ADD_W   = 16,
  parameter int    AXI4_DATA_W  = axi_if_ucore_axi_pkg::AXI4_DATA_W,
  parameter int    AXI4_ID_W    = axi_if_ucore_axi_pkg::AXI4_ID_W
)
(
  input  logic                             clk,
  input  logic                             s_rst_n,

  // AXI4 HBM<->DUT interface
  /*Write channel*/
  output logic [AXI4_ID_W-1:0]             m_axi4_awid,
  output logic [AXI4_ADD_W-1:0]            m_axi4_awaddr,
  output logic [AXI4_LEN_W-1:0]            m_axi4_awlen,
  output logic [AXI4_SIZE_W-1:0]           m_axi4_awsize,
  output logic [AXI4_BURST_W-1:0]          m_axi4_awburst,
  output logic                             m_axi4_awvalid,
  input  logic                             m_axi4_awready,
  output logic [AXI4_DATA_W-1:0]           m_axi4_wdata,
  output logic [(AXI4_DATA_W/8)-1:0]       m_axi4_wstrb,
  output logic                             m_axi4_wlast,
  output logic                             m_axi4_wvalid,
  input  logic                             m_axi4_wready,
  input  logic [AXI4_ID_W-1:0]             m_axi4_bid,
  input  logic [AXI4_RESP_W-1:0]           m_axi4_bresp,
  input  logic                             m_axi4_bvalid,
  output logic                             m_axi4_bready,
  output logic [AXI4_AWLOCK_W-1:0]         m_axi4_awlock,
  output logic [AXI4_AWCACHE_W-1:0]        m_axi4_awcache,
  output logic [AXI4_AWPROT_W-1:0]         m_axi4_awprot,
  output logic [AXI4_AWQOS_W-1:0]          m_axi4_awqos,
  output logic [AXI4_AWREGION_W-1:0]       m_axi4_awregion,

  /*Read channel*/
  output logic [AXI4_ID_W-1:0]             m_axi4_arid,
  output logic [AXI4_ADD_W-1:0]            m_axi4_araddr,
  output logic [AXI4_LEN_W-1:0]            m_axi4_arlen,
  output logic [AXI4_SIZE_W-1:0]           m_axi4_arsize,
  output logic [AXI4_BURST_W-1:0]          m_axi4_arburst,
  output logic                             m_axi4_arvalid,
  input  logic                             m_axi4_arready,
  input  logic [AXI4_ID_W-1:0]             m_axi4_rid,
  input  logic [AXI4_DATA_W-1:0]           m_axi4_rdata,
  input  logic [AXI4_RESP_W-1:0]           m_axi4_rresp,
  input  logic                             m_axi4_rlast,
  input  logic                             m_axi4_rvalid,
  output logic                             m_axi4_rready,
  output logic [AXI4_ARLOCK_W-1:0]         m_axi4_arlock,
  output logic [AXI4_ARCACHE_W-1:0]        m_axi4_arcache,
  output logic [AXI4_ARPROT_W-1:0]         m_axi4_arprot,
  output logic [AXI4_ARQOS_W-1:0]          m_axi4_arqos,
  output logic [AXI4_ARREGION_W-1:0]       m_axi4_arregion,

  // Output to ISC
  // Instruction scheduler input
  output logic [PE_INST_W-1:0]             isc_dop,
  input  logic                             isc_dop_rdy,
  output logic                             isc_dop_vld,

  input  logic [PE_INST_W-1:0]             isc_ack,
  output logic                             isc_ack_rdy,
  input  logic                             isc_ack_vld
);

//=============================================================
// Signals
//=============================================================
  // Ucore regif interface
  logic [AXIL_DATA_W-1:0]          r_wr_data;
  logic [PE_INST_W-1:0]            r_workq;
  logic [PE_INST_W-1:0]            r_workq_upd;
  logic                            r_workq_wr_en;
  logic [PE_INST_W-1:0]            r_ackq_upd;
  logic                            r_ackq_rd_en;

  // AxiLite interface
  logic [AXIL_ADD_W-1:0]           axil_awaddr;
  logic                            axil_awvalid;
  logic                            axil_awready;
  logic [AXIL_DATA_W-1:0]          axil_wdata;
  logic [AXIL_DATA_W/8-1:0]        axil_wstrb;
  logic                            axil_wvalid;
  logic                            axil_wready;
  logic [AXI4_RESP_W-1:0]          axil_bresp;
  logic                            axil_bvalid;
  logic                            axil_bready;
  logic [AXIL_ADD_W-1:0]           axil_araddr;
  logic                            axil_arvalid;
  logic                            axil_arready;
  logic [AXIL_DATA_W-1:0]          axil_rdata;
  logic [AXI4_RESP_W-1:0]          axil_rresp;
  logic                            axil_rvalid;
  logic                            axil_rready;

//=============================================================
// AXIL driver
//=============================================================
// AXIL driver
  maxil_if #(
  .AXIL_DATA_W(AXIL_DATA_W),
  .AXIL_ADD_W (AXIL_ADD_W)
  ) maxil_ucore_if ( .clk(clk), .rst_n(s_rst_n));

  // Connect interface on testbench signals
  assign axil_awaddr  = maxil_ucore_if.awaddr;
  assign axil_awvalid = maxil_ucore_if.awvalid;
  assign axil_wdata   = maxil_ucore_if.wdata;
  assign axil_wstrb   = maxil_ucore_if.wstrb;
  assign axil_wvalid  = maxil_ucore_if.wvalid;
  assign axil_bready  = maxil_ucore_if.bready;
  assign axil_araddr  = maxil_ucore_if.araddr;
  assign axil_arvalid = maxil_ucore_if.arvalid;
  assign axil_rready  = maxil_ucore_if.rready;

  assign maxil_ucore_if.awready = axil_awready;
  assign maxil_ucore_if.wready  = axil_wready;
  assign maxil_ucore_if.bresp   = axil_bresp;
  assign maxil_ucore_if.bvalid  = axil_bvalid;
  assign maxil_ucore_if.arready = axil_arready;
  assign maxil_ucore_if.rdata   = axil_rdata;
  assign maxil_ucore_if.rresp   = axil_rresp;
  assign maxil_ucore_if.rvalid  = axil_rvalid;

  initial begin
    $display("%t > INFO: maxil_ucore_if.init",$time);
    maxil_ucore_if.init();
  end

//=============================================================
// Regif
//=============================================================
// For work queues

  tb_hpu_ucore_regif
  tb_hpu_ucore_regif (
    .clk (clk),
    .s_rst_n (s_rst_n),

    .s_axi4l_awaddr            (axil_awaddr),
    .s_axi4l_awvalid           (axil_awvalid),
    .s_axi4l_awready           (axil_awready),
    .s_axi4l_wdata             (axil_wdata),
    .s_axi4l_wvalid            (axil_wvalid),
    .s_axi4l_wready            (axil_wready),
    .s_axi4l_bresp             (axil_bresp),
    .s_axi4l_bvalid            (axil_bvalid),
    .s_axi4l_bready            (axil_bready),
    .s_axi4l_araddr            (axil_araddr),
    .s_axi4l_arvalid           (axil_arvalid),
    .s_axi4l_arready           (axil_arready),
    .s_axi4l_rdata             (axil_rdata),
    .s_axi4l_rresp             (axil_rresp),
    .s_axi4l_rvalid            (axil_rvalid),
    .s_axi4l_rready            (axil_rready),

    .r_axi4l_wdata             (r_wr_data),

    .r_WorkAck_workq           (r_workq      ),
    .r_WorkAck_workq_upd       (r_workq_upd  ),
    .r_WorkAck_workq_wr_en     (r_workq_wr_en),
    .r_WorkAck_ackq            (),
    .r_WorkAck_ackq_upd        (r_ackq_upd),
    .r_WorkAck_ackq_rd_en      (r_ackq_rd_en)
  );

//=============================================================
// Ucore
//=============================================================
  ucore #(
    .AXI4_ADD_W(AXI4_ADD_W)
  ) ucore (
    .clk          (clk        ),
    .s_rst_n      (s_rst_n    ),

    // Master Axi interface
    .m_axi_awid   (m_axi4_awid   ),
    .m_axi_awaddr (m_axi4_awaddr ),
    .m_axi_awlen  (m_axi4_awlen  ),
    .m_axi_awsize (m_axi4_awsize ),
    .m_axi_awburst(m_axi4_awburst),
    .m_axi_awvalid(m_axi4_awvalid),
    .m_axi_awready(m_axi4_awready),
    .m_axi_wdata  (m_axi4_wdata  ),
    .m_axi_wstrb  (m_axi4_wstrb  ),
    .m_axi_wlast  (m_axi4_wlast  ),
    .m_axi_wvalid (m_axi4_wvalid ),
    .m_axi_wready (m_axi4_wready ),
    .m_axi_bid    (m_axi4_bid    ),
    .m_axi_bresp  (m_axi4_bresp  ),
    .m_axi_bvalid (m_axi4_bvalid ),
    .m_axi_bready (m_axi4_bready ),
    .m_axi_arid   (m_axi4_arid   ),
    .m_axi_araddr (m_axi4_araddr ),
    .m_axi_arlen  (m_axi4_arlen  ),
    .m_axi_arsize (m_axi4_arsize ),
    .m_axi_arburst(m_axi4_arburst),
    .m_axi_arvalid(m_axi4_arvalid),
    .m_axi_arready(m_axi4_arready),
    .m_axi_rid    (m_axi4_rid    ),
    .m_axi_rdata  (m_axi4_rdata  ),
    .m_axi_rresp  (m_axi4_rresp  ),
    .m_axi_rlast  (m_axi4_rlast  ),
    .m_axi_rvalid (m_axi4_rvalid ),
    .m_axi_rready (m_axi4_rready ),

    //== Work_queue
    .r_workq      (r_workq      ),
    .r_workq_upd  (r_workq_upd  ),
    .r_workq_wr_en(r_workq_wr_en),
    .r_workq_wdata(r_wr_data),

    //== Ack_queue
    // Interface with a eRn__ register
    .r_ackq_upd   (r_ackq_upd),
    .r_ackq_rd_en (r_ackq_rd_en),

    // Dop stream: issue sequence of DOps
    .dop_data     (isc_dop),
    .dop_rdy      (isc_dop_rdy ),
    .dop_vld      (isc_dop_vld ),

    // Ack stream: received acknowledgment of DOp sync.
    .ack_data     (isc_ack),
    .ack_rdy      (isc_ack_rdy ),
    .ack_vld      (isc_ack_vld ),

    // Ucore irq line
    .irq          (/*UNUSED*/)
    );

endmodule
