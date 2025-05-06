// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Parameters that defines the NTT core (ntt_core).
// This package is exported by ntt_core_common_param_pkg.
// This package contains the localparams that define the architecture.
// Do not use this package directly : use ntt_core_common_param_pkg.
// ==============================================================================================

package ntt_core_common_cut_definition_pkg;
  // Number of Radix columns
  localparam int                    NTT_RDX_CUT_NB = 3;
  // [0] is the first negacyclic column
  // Note that for ngc, the radix is in [2,32], so its log in [1,5]
  // for cyclic : radix in [2,64], and its log in [1,6]
  localparam [NTT_RDX_CUT_NB-1:0][31:0] NTT_RDX_CUT_S = {32'd3,32'd4,32'd4};

endpackage
