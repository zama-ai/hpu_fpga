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
// NB: Trace is build to be parsed by a CPU, thus we force byte align fields
  localparam int TIMESTAMP_W = 32;

  // TraceInfo structure
  typedef struct packed {
    logic [TIMESTAMP_W-1: 0] timestamp;
    logic [31: 0] insn;
    logic [7: 0] sync_id;
    logic [7: 0] issue_lock;
    logic [7: 0] rd_lock;
    logic [7: 0] wr_lock;
    logic [7: 0] cmd;
    logic [7: 0] vld_rdpdg_pdg;
    logic [15: 0] pe_reserved;
  } isc_trace_t;
localparam int TRACE_W = $bits(isc_trace_t);

endpackage
