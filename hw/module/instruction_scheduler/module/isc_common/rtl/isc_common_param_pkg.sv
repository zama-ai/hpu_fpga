// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Package containing common localparams for Instruction Scheduler
// ==============================================================================================

package isc_common_param_pkg;
  import instruction_scheduler_pkg::*;
  import hpu_common_instruction_pkg::*;
  import param_tfhe_pkg::*;

//==================================================
// Structure
//==================================================

//== Counters
  typedef struct packed {
    logic ack_inc;
    logic inst_inc;
  } isc_counter_inc_t;

  localparam int ISC_COUNTER_INC_W = $bits(isc_counter_inc_t);

//== Info
  typedef struct packed {
    logic [3:0][PE_INST_W-1:0] insn_pld;
  } isc_info_t;

  localparam int ISC_INFO_W = $bits(isc_info_t);

//= Trace
  localparam int TIMESTAMP_W = 32;
  // Currently only pep is using this field
  localparam int TRACE_RESV_W = LWE_K_W;

  // TraceInfo structure
  typedef struct packed {
    logic[TIMESTAMP_W-1: 0] timestamp;
    logic [PE_INST_W-1: 0]  insn;
    isc_query_cmd_e         cmd;
    isc_pool_state_t        state;
    logic[TRACE_RESV_W-1:0] pe_reserved;
  } isc_trace_t;
localparam int TRACE_W = $bits(isc_trace_t);

endpackage
