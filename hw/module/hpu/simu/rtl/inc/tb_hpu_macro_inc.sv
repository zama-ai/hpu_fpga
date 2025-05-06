// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
//  This file contains macros used in tb_hpu.
//  These macro are mostly used to help support for multiple tops.
// ==============================================================================================

`ifndef TB_HPU_MACRO
`define TB_HPU_MACRO 1

`define FPGA_V80 1

//===============================
// Work Queue register driver
//===============================
`define WORKQ_DRV_IF tb_hpu_ucore.maxil_ucore_if
`define WORKQ_REG_PKG tb_hpu_ucore_regif_pkg


//===============================
// AXI-lite port connection
//===============================
  `define AXIL_INSTANCE(port_prefix,signal_prefix,signal_suffix)\
  .``port_prefix``_awaddr (``signal_prefix``_awaddr``signal_suffix``), \
  .``port_prefix``_awvalid(``signal_prefix``_awvalid``signal_suffix``), \
  .``port_prefix``_awready(``signal_prefix``_awready``signal_suffix``), \
  .``port_prefix``_wdata  (``signal_prefix``_wdata``signal_suffix``), \
  .``port_prefix``_wstrb  (``signal_prefix``_wstrb``signal_suffix``), \
  .``port_prefix``_wvalid (``signal_prefix``_wvalid``signal_suffix``), \
  .``port_prefix``_wready (``signal_prefix``_wready``signal_suffix``), \
  .``port_prefix``_bresp  (``signal_prefix``_bresp``signal_suffix``), \
  .``port_prefix``_bvalid (``signal_prefix``_bvalid``signal_suffix``), \
  .``port_prefix``_bready (``signal_prefix``_bready``signal_suffix``), \
  .``port_prefix``_araddr (``signal_prefix``_araddr``signal_suffix``), \
  .``port_prefix``_arvalid(``signal_prefix``_arvalid``signal_suffix``), \
  .``port_prefix``_arready(``signal_prefix``_arready``signal_suffix``), \
  .``port_prefix``_rdata  (``signal_prefix``_rdata``signal_suffix``), \
  .``port_prefix``_rresp  (``signal_prefix``_rresp``signal_suffix``), \
  .``port_prefix``_rvalid (``signal_prefix``_rvalid``signal_suffix``), \
  .``port_prefix``_rready (``signal_prefix``_rready``signal_suffix``), 

//===============================
// AXI4 WR port connection
//===============================
`define AXI4_WR_INSTANCE(port_prefix,signal_prefix,signal_suffix) \
  .``port_prefix``_awid    (``signal_prefix``_awid``signal_suffix``    ),\
  .``port_prefix``_awaddr  (``signal_prefix``_awaddr``signal_suffix``  ),\
  .``port_prefix``_awlen   (``signal_prefix``_awlen``signal_suffix``   ),\
  .``port_prefix``_awsize  (``signal_prefix``_awsize``signal_suffix``  ),\
  .``port_prefix``_awburst (``signal_prefix``_awburst``signal_suffix`` ),\
  .``port_prefix``_awvalid (``signal_prefix``_awvalid``signal_suffix`` ),\
  .``port_prefix``_awready (``signal_prefix``_awready``signal_suffix`` ),\
  .``port_prefix``_wdata   (``signal_prefix``_wdata``signal_suffix``   ),\
  .``port_prefix``_wstrb   (``signal_prefix``_wstrb``signal_suffix``   ),\
  .``port_prefix``_wlast   (``signal_prefix``_wlast``signal_suffix``   ),\
  .``port_prefix``_wvalid  (``signal_prefix``_wvalid``signal_suffix``  ),\
  .``port_prefix``_wready  (``signal_prefix``_wready``signal_suffix``  ),\
  .``port_prefix``_bid     (``signal_prefix``_bid``signal_suffix``     ),\
  .``port_prefix``_bresp   (``signal_prefix``_bresp``signal_suffix``   ),\
  .``port_prefix``_bvalid  (``signal_prefix``_bvalid``signal_suffix``  ),\
  .``port_prefix``_bready  (``signal_prefix``_bready``signal_suffix``  ),\
  .``port_prefix``_awlock  (), /*UNUSED*/ \
  .``port_prefix``_awcache (), /*UNUSED*/ \
  .``port_prefix``_awprot  (), /*UNUSED*/ \
  .``port_prefix``_awqos   (), /*UNUSED*/ \
  .``port_prefix``_awregion(), /*UNUSED*/ \

`define AXI4_WR_UNUSED_INSTANCE(port_prefix) \
  .``port_prefix``_awid    (),\
  .``port_prefix``_awaddr  (),\
  .``port_prefix``_awlen   (),\
  .``port_prefix``_awsize  (),\
  .``port_prefix``_awburst (),\
  .``port_prefix``_awvalid (),\
  .``port_prefix``_awready ('0),\
  .``port_prefix``_wdata   (),\
  .``port_prefix``_wstrb   (),\
  .``port_prefix``_wlast   (),\
  .``port_prefix``_wvalid  (),\
  .``port_prefix``_wready  ('0),\
  .``port_prefix``_bid     (),\
  .``port_prefix``_bresp   (),\
  .``port_prefix``_bvalid  ('0),\
  .``port_prefix``_bready  (),\
  .``port_prefix``_awlock  (), /*UNUSED*/ \
  .``port_prefix``_awcache (), /*UNUSED*/ \
  .``port_prefix``_awprot  (), /*UNUSED*/ \
  .``port_prefix``_awqos   (), /*UNUSED*/ \
  .``port_prefix``_awregion(), /*UNUSED*/ \

//===============================
// AXI4 RD port connection
//===============================
`define AXI4_RD_INSTANCE(port_prefix,signal_prefix,signal_suffix) \
  .``port_prefix``_arid    (``signal_prefix``_arid``signal_suffix``   ),\
  .``port_prefix``_araddr  (``signal_prefix``_araddr``signal_suffix`` ),\
  .``port_prefix``_arlen   (``signal_prefix``_arlen``signal_suffix``  ),\
  .``port_prefix``_arsize  (``signal_prefix``_arsize``signal_suffix`` ),\
  .``port_prefix``_arburst (``signal_prefix``_arburst``signal_suffix``),\
  .``port_prefix``_arvalid (``signal_prefix``_arvalid``signal_suffix``),\
  .``port_prefix``_arready (``signal_prefix``_arready``signal_suffix``),\
  .``port_prefix``_rid     (``signal_prefix``_rid``signal_suffix``    ),\
  .``port_prefix``_rdata   (``signal_prefix``_rdata``signal_suffix``  ),\
  .``port_prefix``_rresp   (``signal_prefix``_rresp``signal_suffix``  ),\
  .``port_prefix``_rlast   (``signal_prefix``_rlast``signal_suffix``  ),\
  .``port_prefix``_rvalid  (``signal_prefix``_rvalid``signal_suffix`` ),\
  .``port_prefix``_rready  (``signal_prefix``_rready``signal_suffix`` ),\
  .``port_prefix``_arlock  (), /*UNUSED*/ \
  .``port_prefix``_arcache (), /*UNUSED*/ \
  .``port_prefix``_arprot  (), /*UNUSED*/ \
  .``port_prefix``_arqos   (), /*UNUSED*/ \
  .``port_prefix``_arregion(), /*UNUSED*/ \

`define AXI4_RD_UNUSED_INSTANCE(port_prefix) \
  .``port_prefix``_arid    (),\
  .``port_prefix``_araddr  (),\
  .``port_prefix``_arlen   (),\
  .``port_prefix``_arsize  (),\
  .``port_prefix``_arburst (),\
  .``port_prefix``_arvalid (),\
  .``port_prefix``_arready ('0),\
  .``port_prefix``_rid     (),\
  .``port_prefix``_rdata   (),\
  .``port_prefix``_rresp   (),\
  .``port_prefix``_rlast   (),\
  .``port_prefix``_rvalid  ('0),\
  .``port_prefix``_rready  (),\
  .``port_prefix``_arlock  (), /*UNUSED*/ \
  .``port_prefix``_arcache (), /*UNUSED*/ \
  .``port_prefix``_arprot  (), /*UNUSED*/ \
  .``port_prefix``_arqos   (), /*UNUSED*/ \
  .``port_prefix``_arregion(), /*UNUSED*/ \
 
`endif // TB_HPU_MACRO
