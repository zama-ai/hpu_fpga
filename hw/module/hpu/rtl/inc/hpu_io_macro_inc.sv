// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
//  This file contains macros used in hpu.
//
//  Used to define some IOs
// ==============================================================================================

`ifndef HPU_IO_MACRO
`define HPU_IO_MACRO 1

//==================================================================================
// AXIL
//==================================================================================
// We use different AXIL.

  `define HPU_AXIL_IO(name, axi_package=axi_if_shell_axil_pkg) \
  input  logic [axi_package::AXIL_ADD_W-1:0]      s_axil_``name``_awaddr, \
  input  logic                                    s_axil_``name``_awvalid, \
  output logic                                    s_axil_``name``_awready, \
  input  logic [axi_package::AXIL_DATA_W-1:0]     s_axil_``name``_wdata, \
  input  logic [axi_package::AXIL_DATA_BYTES-1:0] s_axil_``name``_wstrb, /* dropped */ \
  input  logic                                    s_axil_``name``_wvalid, \
  output logic                                    s_axil_``name``_wready, \
  output logic [AXI4_RESP_W-1:0]                  s_axil_``name``_bresp, \
  output logic                                    s_axil_``name``_bvalid, \
  input  logic                                    s_axil_``name``_bready, \
  input  logic [axi_package::AXIL_ADD_W-1:0]      s_axil_``name``_araddr, \
  input  logic                                    s_axil_``name``_arvalid, \
  output logic                                    s_axil_``name``_arready, \
  output logic [axi_package::AXIL_DATA_W-1:0]     s_axil_``name``_rdata, \
  output logic [AXI4_RESP_W-1:0]                  s_axil_``name``_rresp, \
  output logic                                    s_axil_``name``_rvalid, \
  input  logic                                    s_axil_``name``_rready,

  `define HPU_AXIL_INSTANCE(port_name,sig_name) \
  .s_axil_``port_name``_awaddr (s_axil_``sig_name``_awaddr), \
  .s_axil_``port_name``_awvalid(s_axil_``sig_name``_awvalid), \
  .s_axil_``port_name``_awready(s_axil_``sig_name``_awready), \
  .s_axil_``port_name``_wdata  (s_axil_``sig_name``_wdata), \
  .s_axil_``port_name``_wstrb  (s_axil_``sig_name``_wstrb), \
  .s_axil_``port_name``_wvalid (s_axil_``sig_name``_wvalid), \
  .s_axil_``port_name``_wready (s_axil_``sig_name``_wready), \
  .s_axil_``port_name``_bresp  (s_axil_``sig_name``_bresp), \
  .s_axil_``port_name``_bvalid (s_axil_``sig_name``_bvalid), \
  .s_axil_``port_name``_bready (s_axil_``sig_name``_bready), \
  .s_axil_``port_name``_araddr (s_axil_``sig_name``_araddr), \
  .s_axil_``port_name``_arvalid(s_axil_``sig_name``_arvalid), \
  .s_axil_``port_name``_arready(s_axil_``sig_name``_arready), \
  .s_axil_``port_name``_rdata  (s_axil_``sig_name``_rdata), \
  .s_axil_``port_name``_rresp  (s_axil_``sig_name``_rresp), \
  .s_axil_``port_name``_rvalid (s_axil_``sig_name``_rvalid), \
  .s_axil_``port_name``_rready (s_axil_``sig_name``_rready),

//==================================================================================
// AXI4
//==================================================================================
`define HPU_AXI4_IO(name, NAME, axi_package,BUS_WIDTH) \
  /*Write channel*/ \
  output logic ``BUS_WIDTH``[axi_package::AXI4_ID_W-1:0]       m_axi4_``name``_awid, \
  output logic ``BUS_WIDTH``[AXI4_``NAME``_ADD_W-1:0]          m_axi4_``name``_awaddr, \
  output logic ``BUS_WIDTH``[AXI4_LEN_W-1:0]                   m_axi4_``name``_awlen, \
  output logic ``BUS_WIDTH``[AXI4_SIZE_W-1:0]                  m_axi4_``name``_awsize, \
  output logic ``BUS_WIDTH``[AXI4_BURST_W-1:0]                 m_axi4_``name``_awburst, \
  output logic ``BUS_WIDTH``                                   m_axi4_``name``_awvalid, \
  input  logic ``BUS_WIDTH``                                   m_axi4_``name``_awready, \
  output logic ``BUS_WIDTH``[axi_package::AXI4_DATA_W-1:0]     m_axi4_``name``_wdata, \
  output logic ``BUS_WIDTH``[axi_package::AXI4_DATA_BYTES-1:0] m_axi4_``name``_wstrb, \
  output logic ``BUS_WIDTH``                                   m_axi4_``name``_wlast, \
  output logic ``BUS_WIDTH``                                   m_axi4_``name``_wvalid, \
  input  logic ``BUS_WIDTH``                                   m_axi4_``name``_wready, \
  input  logic ``BUS_WIDTH``[axi_package::AXI4_ID_W-1:0]       m_axi4_``name``_bid, \
  input  logic ``BUS_WIDTH``[AXI4_RESP_W-1:0]                  m_axi4_``name``_bresp, \
  input  logic ``BUS_WIDTH``                                   m_axi4_``name``_bvalid, \
  output logic ``BUS_WIDTH``                                   m_axi4_``name``_bready, \
  /*Unused signal tight to constant in the top*/ \
  output logic ``BUS_WIDTH``[AXI4_AWLOCK_W-1:0]                m_axi4_``name``_awlock,  /*UNUSED*/ \
  output logic ``BUS_WIDTH``[AXI4_AWCACHE_W-1:0]               m_axi4_``name``_awcache, /*UNUSED*/ \
  output logic ``BUS_WIDTH``[AXI4_AWPROT_W-1:0]                m_axi4_``name``_awprot,  /*UNUSED*/ \
  output logic ``BUS_WIDTH``[AXI4_AWQOS_W-1:0]                 m_axi4_``name``_awqos,   /*UNUSED*/ \
  output logic ``BUS_WIDTH``[AXI4_AWREGION_W-1:0]              m_axi4_``name``_awregion,/*UNUSED*/ \
  /*Read channel*/ \
  output logic ``BUS_WIDTH``[axi_package::AXI4_ID_W-1:0]       m_axi4_``name``_arid, \
  output logic ``BUS_WIDTH``[AXI4_PEM_ADD_W-1:0]               m_axi4_``name``_araddr, \
  output logic ``BUS_WIDTH``[AXI4_LEN_W-1:0]                   m_axi4_``name``_arlen, \
  output logic ``BUS_WIDTH``[AXI4_SIZE_W-1:0]                  m_axi4_``name``_arsize, \
  output logic ``BUS_WIDTH``[AXI4_BURST_W-1:0]                 m_axi4_``name``_arburst, \
  output logic ``BUS_WIDTH``                                   m_axi4_``name``_arvalid, \
  input  logic ``BUS_WIDTH``                                   m_axi4_``name``_arready, \
  input  logic ``BUS_WIDTH``[axi_package::AXI4_ID_W-1:0]       m_axi4_``name``_rid, \
  input  logic ``BUS_WIDTH``[axi_package::AXI4_DATA_W-1:0]     m_axi4_``name``_rdata, \
  input  logic ``BUS_WIDTH``[AXI4_RESP_W-1:0]                  m_axi4_``name``_rresp, \
  input  logic ``BUS_WIDTH``                                   m_axi4_``name``_rlast, \
  input  logic ``BUS_WIDTH``                                   m_axi4_``name``_rvalid, \
  output logic ``BUS_WIDTH``                                   m_axi4_``name``_rready, \
  /*Unused signal tight to constant in the top*/ \
  output logic ``BUS_WIDTH``[AXI4_ARLOCK_W-1:0]                m_axi4_``name``_arlock,  /*UNUSED*/ \
  output logic ``BUS_WIDTH``[AXI4_ARCACHE_W-1:0]               m_axi4_``name``_arcache, /*UNUSED*/ \
  output logic ``BUS_WIDTH``[AXI4_ARPROT_W-1:0]                m_axi4_``name``_arprot,  /*UNUSED*/ \
  output logic ``BUS_WIDTH``[AXI4_ARQOS_W-1:0]                 m_axi4_``name``_arqos,   /*UNUSED*/ \
  output logic ``BUS_WIDTH``[AXI4_ARREGION_W-1:0]              m_axi4_``name``_arregion,/*UNUSED*/ \

  `define HPU_AXI4_TIE_GL_UNUSED(name, BUS_WIDTH, SIZE = 1) \
  assign m_axi4_``name``_awlock   BUS_WIDTH = {SIZE{AXI4_AWLOCK_W'(0)}}; \
  assign m_axi4_``name``_awcache  BUS_WIDTH = {SIZE{AXI4_AWCACHE_DEFAULT}}; \
  assign m_axi4_``name``_awprot   BUS_WIDTH = {SIZE{AXI4_AWPROT_W'(0)}}  ; \
  assign m_axi4_``name``_awqos    BUS_WIDTH = {SIZE{AXI4_AWQOS_W'(0)}}   ; \
  assign m_axi4_``name``_awregion BUS_WIDTH = {SIZE{AXI4_AWREGION_W'(0)}}; \
  assign m_axi4_``name``_arlock   BUS_WIDTH = {SIZE{AXI4_ARLOCK_W'(0)}}; \
  assign m_axi4_``name``_arcache  BUS_WIDTH = {SIZE{AXI4_ARCACHE_DEFAULT}}; \
  assign m_axi4_``name``_arprot   BUS_WIDTH = {SIZE{AXI4_ARPROT_W'(0)}}  ; \
  assign m_axi4_``name``_arqos    BUS_WIDTH = {SIZE{AXI4_ARQOS_W'(0)}}   ; \
  assign m_axi4_``name``_arregion BUS_WIDTH = {SIZE{AXI4_ARREGION_W'(0)}}; \

  `define HPU_AXI4_TIE_WR_UNUSED(name, BUS_WIDTH) \
  assign m_axi4_``name``_awid   ``BUS_WIDTH`` = '0; \
  assign m_axi4_``name``_awaddr ``BUS_WIDTH`` = '0; \
  assign m_axi4_``name``_awlen  ``BUS_WIDTH`` = '0; \
  assign m_axi4_``name``_awsize ``BUS_WIDTH`` = '0; \
  assign m_axi4_``name``_awburst``BUS_WIDTH`` = '0; \
  assign m_axi4_``name``_awvalid``BUS_WIDTH`` = '0; \
  assign m_axi4_``name``_wdata  ``BUS_WIDTH`` = '0; \
  assign m_axi4_``name``_wstrb  ``BUS_WIDTH`` = '0; \
  assign m_axi4_``name``_wlast  ``BUS_WIDTH`` = '0; \
  assign m_axi4_``name``_wvalid ``BUS_WIDTH`` = '0; \
  assign m_axi4_``name``_bready ``BUS_WIDTH`` = '0; \

  `define HPU_AXI4_TIE_RD_UNUSED(name,BUS_WIDTH) \
  assign m_axi4_``name``_arid   ``BUS_WIDTH`` = '0; \
  assign m_axi4_``name``_araddr ``BUS_WIDTH`` = '0; \
  assign m_axi4_``name``_arlen  ``BUS_WIDTH`` = '0; \
  assign m_axi4_``name``_arsize ``BUS_WIDTH`` = '0; \
  assign m_axi4_``name``_arburst``BUS_WIDTH`` = '0; \
  assign m_axi4_``name``_arvalid``BUS_WIDTH`` = '0; \
  assign m_axi4_``name``_rready ``BUS_WIDTH`` = '0; \

  `define HPU_AXI4_SHORT_WR_INSTANCE(port_name, sig_name, add_suffix, BUS_WIDTH) \
  .m_axi4_``port_name``_awid     (m_axi4_``sig_name``_awid``BUS_WIDTH``),\
  .m_axi4_``port_name``_awaddr   (m_axi4_``sig_name``_awaddr``add_suffix````BUS_WIDTH``),\
  .m_axi4_``port_name``_awlen    (m_axi4_``sig_name``_awlen``BUS_WIDTH``),\
  .m_axi4_``port_name``_awsize   (m_axi4_``sig_name``_awsize``BUS_WIDTH``),\
  .m_axi4_``port_name``_awburst  (m_axi4_``sig_name``_awburst``BUS_WIDTH``),\
  .m_axi4_``port_name``_awvalid  (m_axi4_``sig_name``_awvalid``BUS_WIDTH``),\
  .m_axi4_``port_name``_awready  (m_axi4_``sig_name``_awready``BUS_WIDTH``),\
  .m_axi4_``port_name``_wdata    (m_axi4_``sig_name``_wdata``BUS_WIDTH``),\
  .m_axi4_``port_name``_wstrb    (m_axi4_``sig_name``_wstrb``BUS_WIDTH``),\
  .m_axi4_``port_name``_wlast    (m_axi4_``sig_name``_wlast``BUS_WIDTH``),\
  .m_axi4_``port_name``_wvalid   (m_axi4_``sig_name``_wvalid``BUS_WIDTH``),\
  .m_axi4_``port_name``_wready   (m_axi4_``sig_name``_wready``BUS_WIDTH``),\
  .m_axi4_``port_name``_bid      (m_axi4_``sig_name``_bid``BUS_WIDTH``),\
  .m_axi4_``port_name``_bresp    (m_axi4_``sig_name``_bresp``BUS_WIDTH``),\
  .m_axi4_``port_name``_bvalid   (m_axi4_``sig_name``_bvalid``BUS_WIDTH``),\
  .m_axi4_``port_name``_bready   (m_axi4_``sig_name``_bready``BUS_WIDTH``),\

  `define HPU_AXI4_FULL_WR_INSTANCE(port_name, sig_name, add_suffix, BUS_WIDTH) \
   `HPU_AXI4_SHORT_WR_INSTANCE(port_name, sig_name, add_suffix, BUS_WIDTH) \
  .m_axi4_``port_name``_awlock   (m_axi4_``sig_name``_awlock``BUS_WIDTH``),\
  .m_axi4_``port_name``_awcache  (m_axi4_``sig_name``_awcache``BUS_WIDTH``),\
  .m_axi4_``port_name``_awprot   (m_axi4_``sig_name``_awprot``BUS_WIDTH``),\
  .m_axi4_``port_name``_awqos    (m_axi4_``sig_name``_awqos``BUS_WIDTH``),\
  .m_axi4_``port_name``_awregion (m_axi4_``sig_name``_awregion``BUS_WIDTH``),\


  `define HPU_AXI4_SHORT_RD_INSTANCE(port_name, sig_name, add_suffix, BUS_WIDTH) \
  .m_axi4_``port_name``_arid     (m_axi4_``sig_name``_arid``BUS_WIDTH``),\
  .m_axi4_``port_name``_araddr   (m_axi4_``sig_name``_araddr``add_suffix````BUS_WIDTH``),\
  .m_axi4_``port_name``_arlen    (m_axi4_``sig_name``_arlen``BUS_WIDTH``),\
  .m_axi4_``port_name``_arsize   (m_axi4_``sig_name``_arsize``BUS_WIDTH``),\
  .m_axi4_``port_name``_arburst  (m_axi4_``sig_name``_arburst``BUS_WIDTH``),\
  .m_axi4_``port_name``_arvalid  (m_axi4_``sig_name``_arvalid``BUS_WIDTH``),\
  .m_axi4_``port_name``_arready  (m_axi4_``sig_name``_arready``BUS_WIDTH``),\
  .m_axi4_``port_name``_rid      (m_axi4_``sig_name``_rid``BUS_WIDTH``),\
  .m_axi4_``port_name``_rdata    (m_axi4_``sig_name``_rdata``BUS_WIDTH``),\
  .m_axi4_``port_name``_rresp    (m_axi4_``sig_name``_rresp``BUS_WIDTH``),\
  .m_axi4_``port_name``_rlast    (m_axi4_``sig_name``_rlast``BUS_WIDTH``),\
  .m_axi4_``port_name``_rvalid   (m_axi4_``sig_name``_rvalid``BUS_WIDTH``),\
  .m_axi4_``port_name``_rready   (m_axi4_``sig_name``_rready``BUS_WIDTH``),\

  `define HPU_AXI4_FULL_RD_INSTANCE(port_name, sig_name, add_suffix, BUS_WIDTH) \
  `HPU_AXI4_SHORT_RD_INSTANCE(port_name, sig_name, add_suffix, BUS_WIDTH) \
  .m_axi4_``port_name``_arlock   (m_axi4_``sig_name``_arlock``BUS_WIDTH``),\
  .m_axi4_``port_name``_arcache  (m_axi4_``sig_name``_arcache``BUS_WIDTH``),\
  .m_axi4_``port_name``_arprot   (m_axi4_``sig_name``_arprot``BUS_WIDTH``),\
  .m_axi4_``port_name``_arqos    (m_axi4_``sig_name``_arqos``BUS_WIDTH``),\
  .m_axi4_``port_name``_arregion (m_axi4_``sig_name``_arregion``BUS_WIDTH``),\

  `define HPU_AXI4_SHORT_INSTANCE(port_name, sig_name, add_suffix, BUS_WIDTH) \
  `HPU_AXI4_SHORT_WR_INSTANCE(port_name, sig_name, add_suffix, BUS_WIDTH) \
  `HPU_AXI4_SHORT_RD_INSTANCE(port_name, sig_name, add_suffix, BUS_WIDTH) \

  `define HPU_AXI4_FULL_INSTANCE(port_name, sig_name, add_suffix, BUS_WIDTH) \
  `HPU_AXI4_FULL_WR_INSTANCE(port_name, sig_name, add_suffix, BUS_WIDTH) \
  `HPU_AXI4_FULL_RD_INSTANCE(port_name, sig_name, add_suffix, BUS_WIDTH) \

`endif
