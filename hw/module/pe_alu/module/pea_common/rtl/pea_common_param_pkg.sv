// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Package containing common localparams for PE memory.
// ==============================================================================================

package pea_common_param_pkg;
//==================================================
// Structure
//==================================================
  //== Counters
  typedef struct packed {
    logic ack_inc;
    logic inst_inc;
  } pea_counter_inc_t;

  localparam int PEA_COUNTER_INC_W = $bits(pea_counter_inc_t);

endpackage
