// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Parameters that defines the NTT prime.
// Do not use this package directly in modules. Use param_ntt_pkg instead.
// This purpose of this package is to ease the tests/synthesis with various localparam sets.
//
// Ring generator : 7
// ==============================================================================================

package param_ntt_definition_pkg;
  import common_definition_pkg::*;

  localparam mod_ntt_name_e MOD_NTT_NAME = MOD_NTT_NAME_GOLDILOCKS_64;
  localparam string MOD_NTT_NAME_S = "GOLDILOCKS";

  // Operand and modulo width
  localparam int             MOD_NTT_W    = 64;
  localparam [MOD_NTT_W-1:0] MOD_NTT      = 2**64 - 2**32 + 1;
  // Declare the type of the modulo to ease the selection for the best operators.
  // Recognized values are SOLINAS2, SOLINAS3, MERSENNE.
  // Any other type won't be recognized, and generic operators will be used.
  localparam int_type_e      MOD_NTT_TYPE = GOLDILOCKS;
  localparam int_type_e      MOD_NTT_INV_TYPE = GOLDILOCKS_INV;
endpackage
