// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Parameters that defines the NTT core (ntt_core).
// This package is exported by ntt_core_common_param_pkg.
// This package contains the localparams that are architecture dependent.
// Do not use it directly, use ntt_core_common_param_pkg.
// ==============================================================================================

package ntt_core_common_arch_definition_pkg;
  import common_definition_pkg::*;

  // Current architecture
  localparam ntt_core_arch_e NTT_CORE_ARCH = NTT_CORE_ARCH_GF64;

endpackage
