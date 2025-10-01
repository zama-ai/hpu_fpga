// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
// Parameters for axi bus
// ==============================================================================================

package axi_if_common_param_pkg;
  //----------------------
  // DDR PAGE
  //----------------------
  localparam int PAGE_BYTES    = 4096; // byte unit
  localparam int PAGE_BYTES_W  = $clog2(PAGE_BYTES);
  localparam int PAGE_BYTES_WW = $clog2(PAGE_BYTES + 1);

  //----------------------
  // AXI constant
  //----------------------
  localparam int AXI4_LEN_W   = 8;
  localparam int AXI4_BURST_W = 2;
  localparam int AXI4_RESP_W  = 2;
  localparam int AXI4_SIZE_W  = 3;

  localparam int AXI4_ARLOCK_W   = 1;
  localparam int AXI4_ARCACHE_W  = 4;
  localparam int AXI4_ARPROT_W   = 3;
  localparam int AXI4_ARQOS_W    = 4;
  localparam int AXI4_ARREGION_W = 4;

  localparam int AXI4_AWLOCK_W   = 1;
  localparam int AXI4_AWCACHE_W  = 4;
  localparam int AXI4_AWPROT_W   = 3;
  localparam int AXI4_AWQOS_W    = 4;
  localparam int AXI4_AWREGION_W = 4;

  localparam logic [3:0] AXI4_ARCACHE_DEFAULT = 4'b0011;
  localparam logic [3:0] AXI4_AWCACHE_DEFAULT = 4'b0011;

  //----------------------
  // Type
  //----------------------
  typedef enum logic [AXI4_RESP_W-1:0] {
    AXI4_OKAY   = 2'b00,
    AXI4_EXOKAY = 2'b01,
    AXI4_SLVERR = 2'b10,
    AXI4_DECERR = 2'b11
  } axi4_resp_e;

  typedef enum logic [AXI4_BURST_W-1:0] {
    AXI4B_FIXED ='b00,
    AXI4B_INCR  ='b01,
    AXI4B_WRAP  ='b10
  } axi4_burst_mode_e;

endpackage
