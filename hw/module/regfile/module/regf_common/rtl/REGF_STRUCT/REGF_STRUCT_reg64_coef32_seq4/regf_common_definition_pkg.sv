// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Package containing localparams used in regfile.
// ==============================================================================================

package regf_common_definition_pkg;
  // Number of registers in the regfile
  localparam int REGF_REG_NB  = 64; // Number of registers in the regfile
  localparam int REGF_COEF_NB = 32; // Number of coefficients processed in //
  localparam int REGF_SEQ     = 4;  // Data are output in REGF_SEQ cycles.
endpackage
