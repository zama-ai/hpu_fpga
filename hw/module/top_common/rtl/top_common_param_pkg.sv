// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Template
// ----------------------------------------------------------------------------------------------
//
// Definition of localparams used in any top.
// ==============================================================================================

package top_common_param_pkg;
  import top_common_top_definition_pkg::*;
  import top_common_pcmax_definition_pkg::*;
  import top_common_pc_definition_pkg::*;

  export top_common_top_definition_pkg::TOP;

  // Max number of memory PCs (for top interface definition)
  export top_common_pcmax_definition_pkg::PEM_PC_MAX;
  export top_common_pcmax_definition_pkg::GLWE_PC_MAX;
  export top_common_pcmax_definition_pkg::BSK_PC_MAX;
  export top_common_pcmax_definition_pkg::KSK_PC_MAX;

  // Number of memory PCs
  export top_common_pc_definition_pkg::PEM_PC;
  export top_common_pc_definition_pkg::GLWE_PC;
  export top_common_pc_definition_pkg::BSK_PC;
  export top_common_pc_definition_pkg::KSK_PC;

endpackage
