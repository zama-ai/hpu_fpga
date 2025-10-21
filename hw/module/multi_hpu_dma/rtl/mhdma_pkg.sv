// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Package for multi-HPU DMA
// ==============================================================================================

package mhdma_pkg;
  import param_tfhe_pkg::*;
  import axi_if_common_param_pkg::*;
  import axi_if_ct_axi_pkg::*;
  //----------------------
  // AXI4
  //----------------------
  localparam int AXI4_ADD_W      = 64;
  localparam int AXI4_ID_W       = 1;
  localparam int AXI4_DATA_W     = axi_if_data_w_definition_pkg::AXI4_DATA_W; // AXI data bus width. Should not exceed 512.

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
  // Ethernet
  //----------------------
  localparam int MRMAC_AXIS_W   = 64;
  localparam int MRMAC_TKEEP_W  = 11;

  localparam int QSFP_LANE_NB   = 4;

  localparam int MAC_ADDR_W = 24;
  localparam int MAC_OUI_W  = 24;

  localparam [MAC_OUI_W-1:0] MAC_OUI = 'h000A35;

  //----------------------
  // Parameters
  //----------------------
  localparam int CT_BYTE_SIZE      = N * GLWE_K + 1;
  localparam int CT_NB_WORDS_MRMAC = (CT_BYTE_SIZE * 8) / MRMAC_AXIS_W;
  localparam int CT_NB_WORDS_HBM   = (CT_BYTE_SIZE * 8) / AXI4_DATA_W;

endpackage
