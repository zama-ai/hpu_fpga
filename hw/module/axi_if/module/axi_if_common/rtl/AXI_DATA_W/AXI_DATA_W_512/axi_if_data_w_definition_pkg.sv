// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Parameters that defines the DATA width of main axi busses : KSK, BSK, PEM and GLWE
//
// ==============================================================================================

package axi_if_data_w_definition_pkg;

  localparam int AXI4_DATA_W = 512; // Should be a power of 2 <= 512

endpackage
