// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// NTT core with matrix multiplication (ntt_core) localparam package.
// This package defines the localparams of ntt_core.
// ==============================================================================================

`include "ntt_core_common_macro_inc.sv"

package ntt_core_common_param_pkg;
  import common_definition_pkg::*;
  import param_tfhe_pkg::*;
  import param_ntt_pkg::*;
  import ntt_core_common_r_definition_pkg::*;
  import ntt_core_common_psi_definition_pkg::*;
  import ntt_core_common_div_definition_pkg::*;
  import ntt_core_common_arch_definition_pkg::*;
  import ntt_core_common_cut_definition_pkg::*;

  export ntt_core_common_r_definition_pkg::R;
  export ntt_core_common_psi_definition_pkg::PSI;
  export ntt_core_common_div_definition_pkg::BWD_PSI_DIV;
  export ntt_core_common_arch_definition_pkg::NTT_CORE_ARCH;
  export ntt_core_common_cut_definition_pkg::NTT_RDX_CUT_NB;
  export ntt_core_common_cut_definition_pkg::NTT_RDX_CUT_S;

  localparam int DELTA = NTT_RDX_CUT_S[0];
  localparam int S = $clog2(N)/$clog2(R); // Number of stages

  localparam int NTT_OP_W = (NTT_CORE_ARCH == NTT_CORE_ARCH_GF64) ? MOD_NTT_W + 2 : MOD_NTT_W;

  `NTT_CORE_LOCALPARAM(R,S,PSI)
endpackage

