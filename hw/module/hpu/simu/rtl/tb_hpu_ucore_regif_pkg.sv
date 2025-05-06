// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : register  map address definition package
// This file was generated with rust regmap generator:
//  * Date:  2025-01-22
//  * Tool_version: c0ba18d05e0ad364ef72741dd908ad38f42b8f15
// ----------------------------------------------------------------------------------------------
//
// Should only be used in testbench to drive the register interface
// ==============================================================================================

package tb_hpu_ucore_regif_pkg;
  localparam int WORKACK_WORKQ_OFS = 0;
  typedef struct packed {logic [(16-1):0] padding_16;
    logic [(8-1):0] bsk_cut_nb;
    logic [(8-1):0] bsk_pc;
   } WorkAck_ackq_t;
  localparam int WORKACK_ACKQ_OFS = 4;
endpackage
