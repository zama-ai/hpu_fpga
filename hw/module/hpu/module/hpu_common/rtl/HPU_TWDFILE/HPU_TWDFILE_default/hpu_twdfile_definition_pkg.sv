// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Parameters that define the twiddle files used in HPU NTT.
//
// ==============================================================================================

`include "top_defines_inc.sv"

package hpu_twdfile_definition_pkg;
  import param_ntt_pkg::*;
  import ntt_core_common_param_pkg::*;

  // Twiddle files //TOREVIEW mod_ntt_name
  // WORKAROUND : Write it exactly this way, for the macro to work. If not => not interpretated correctly in vivado

  // ntt_core_wmm
  localparam string TWD_IFNL_FILE_PREFIX = $sformatf("%smemory_file/twiddle/NTT_CORE_ARCH_WMM/R%0d_PSI%0d_S%0d_D%0d/%s/twd_ifnl_bwd",`MEMORY_FILE_PATH ,R,PSI,S,DELTA,MOD_NTT_NAME_S);
  localparam string TWD_PHRU_FILE_PREFIX = $sformatf("%smemory_file/twiddle/NTT_CORE_ARCH_WMM/R%0d_PSI%0d_S%0d_D%0d/%s/twd_phru", `MEMORY_FILE_PATH ,R,PSI,S,DELTA,MOD_NTT_NAME_S);
  // ntt_core_gf64
  localparam string TWD_GF64_FILE_PREFIX = $sformatf("%smemory_file/twiddle/NTT_CORE_ARCH_GF64/R%0d_PSI%0d/twd_phi",`MEMORY_FILE_PATH,R,PSI);

endpackage
