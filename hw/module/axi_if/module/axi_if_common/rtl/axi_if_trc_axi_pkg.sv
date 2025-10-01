// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
// Parameters for axi interface that addresses the TRACE area
// ==============================================================================================

package axi_if_trc_axi_pkg;
  import axi_if_common_param_pkg::*;

  //----------------------
  // AXI4
  //----------------------
  localparam int AXI4_ADD_W      = 64;
  localparam int AXI4_ID_W       = 1;
  localparam int AXI4_DATA_W     = 128; // AXI data bus width. Should not exceed 512.
                                        // No need performance here.

  localparam int AXI4_DATA_BYTES = AXI4_DATA_W/8;
  localparam int AXI4_STRB_W     = AXI4_DATA_BYTES;
  // Derived value used to define the number of bytes on axi4 transaction
  // -> Mandatory for addr increment in burst
  localparam int AXI4_DATA_BYTES_W = $clog2(AXI4_DATA_BYTES);

  // AXI4 Burst should not cross DDR page boundaries
  // AXI4 transaction length is encoded as AXI4_DATA_BYTES*(AxLen+1)
  localparam int PAGE_AXI4_DATA   = PAGE_BYTES / AXI4_DATA_BYTES;
  localparam int AXI4_LEN_MAX     = (PAGE_AXI4_DATA < 256)? (PAGE_AXI4_DATA-1): 255;
  localparam int AXI4_WORD_MAX    = AXI4_LEN_MAX + 1;

  //----------------------
  // Typedef
  //----------------------
  typedef struct packed {
    logic [AXI4_ID_W-1:0]    arid;
    logic [AXI4_ADD_W-1:0]   araddr;
    logic [AXI4_LEN_W-1:0]   arlen;
    logic [AXI4_SIZE_W-1:0]  arsize;
    logic [AXI4_BURST_W-1:0] arburst;
  } axi4_ar_if_t;

  localparam int AXI4_AR_IF_W = $bits(axi4_ar_if_t);

  typedef struct packed {
    logic [AXI4_ID_W-1:0]   rid;
    logic [AXI4_DATA_W-1:0] rdata;
    logic [AXI4_RESP_W-1:0] rresp;
    logic                   rlast;
  } axi4_r_if_t;

  localparam int AXI4_R_IF_W = $bits(axi4_r_if_t);

  typedef struct packed {
    logic [AXI4_ID_W-1:0]    awid;
    logic [AXI4_ADD_W-1:0]   awaddr;
    logic [AXI4_LEN_W-1:0]   awlen;
    logic [AXI4_SIZE_W-1:0]  awsize;
    logic [AXI4_BURST_W-1:0] awburst;
  } axi4_aw_if_t;

  localparam int AXI4_AW_IF_W = $bits(axi4_aw_if_t);

  typedef struct packed {
    logic [AXI4_DATA_W-1:0]     wdata;
    logic [(AXI4_DATA_W/8)-1:0] wstrb;
    logic                       wlast;
  } axi4_w_if_t;

  localparam int AXI4_W_IF_W = $bits(axi4_w_if_t);

  typedef struct packed {
    logic [AXI4_ID_W-1:0]   bid;
    logic [AXI4_RESP_W-1:0] bresp;
  } axi4_b_if_t;

  localparam int AXI4_B_IF_W = $bits(axi4_b_if_t);

endpackage
