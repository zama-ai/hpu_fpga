// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Definition of localparams used in pe_pbs.
// Should not be used as is.
// Should be imported by pep_common_param_pkg.
// ==============================================================================================

package pep_msplit_definition_pkg;
  import common_definition_pkg::*;
  localparam msplit_name_e MSPLIT_TYPE        = MSPLIT_NAME_M3_S1;
  localparam int           MSPLIT_DIV         = 4;
  localparam int           MSPLIT_MAIN_FACTOR = 3;
  localparam int           MSPLIT_SUBS_FACTOR = 1;
endpackage
