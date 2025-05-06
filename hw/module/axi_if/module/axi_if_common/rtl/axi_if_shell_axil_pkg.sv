// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
// Parameters for axi-lite interface exposed by Vitis builtin shell
// ==============================================================================================

package axi_if_shell_axil_pkg;

  //----------------------
  // AXI4-Lite
  //----------------------
  localparam int AXIL_ADD_W      = 18;
  localparam int AXIL_DATA_W     = 32;

  localparam int AXIL_DATA_BYTES = AXIL_DATA_W/8;

  localparam int REG_DATA_W      = AXIL_DATA_W;
  localparam int REG_DATA_BYTES  = REG_DATA_W / 8;
endpackage
