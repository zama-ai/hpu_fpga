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
  import axi_if_eth_axi_pkg::*;

  //----------------------
  // Ethernet
  //----------------------
  // beware of block design if modifying this values
  localparam int MRMAC_AXIS_W   = 64;
  localparam int MRMAC_TKEEP_W  = 11;
  localparam int ETH_PC         = 2;
  // beware of regfile if modifying this value
  localparam int NB_MAX_HPU   = 8;
  localparam int NB_MAX_HPU_W = $clog2(NB_MAX_HPU);

  localparam int QSFP_LANE_NB   = 4;

  localparam int ETH_NB_BYTES_PAYLOAD = 1000;
  localparam int ETH_NB_BYTES_MIN = 64;
  localparam int ETH_HEADER_SIZE = 3;  // number of 64bit frames to send

  localparam [15:0] ETH_LEN_MIN = (ETH_NB_BYTES_MIN*8)/64 - ETH_HEADER_SIZE ;
  localparam [15:0] ETH_LEN_MAX = (ETH_NB_BYTES_PAYLOAD*8)/MRMAC_AXIS_W + ETH_HEADER_SIZE;

  // generic sizes on ethernet
  localparam int NB_WORDS_MIN = 7; // without fcs

  // Ethernet header: sizes ---------------------------------------------------
  localparam int MAC_ADDR_W   = 24;
  localparam int MAC_OUI_W    = 24;

  localparam int SEQ_NUM_W    = 8;
  localparam int HPU_ID_W     = 4;
  localparam int REQ_ID_W     = 4;
  localparam int ETHERNET_LEN = 16;

  localparam int SIZE_B_W     = 16;
  localparam int IOP_ID_W     = 4;
  localparam int SRC_ADDR_W   = 16;
  localparam int DST_ADDR_W   = 16;

  // Ethernet header: values --------------------------------------------------
  localparam [MAC_OUI_W-1:0] MAC_OUI = 'h000A35;
  localparam [SIZE_B_W-1:0]  SIZE_B  = 'h4000; // fixed for now to 16.384

  // fifo specific parameters -------------------------------------------------
  // minimal depth for 64 using XPM fifo is 16
  localparam int RQQ_MEMORY_TYPE  = "distributed";
  localparam int RQQ_DEPTH        = 16;
  localparam int RQQ_WIDTH        = 64;
  localparam int RQQ_DATA_COUNT_W =  $clog2(RQQ_DEPTH)+1;

  // identification opcode --------------------------------------------------
  localparam [REQ_ID_W-1:0] REQ_ID_NOTIFY_TX     = 'h2;
  localparam [REQ_ID_W-1:0] REQ_ID_ACK_NOTIFY_TX = 'h3;
  localparam [REQ_ID_W-1:0] REQ_ID_NOTIFY_RX     = 'h4;
  localparam [REQ_ID_W-1:0] REQ_ID_ACK_NOTIFY_RX = 'h5;
  localparam [REQ_ID_W-1:0] REQ_ID_READ          = 'h6;
  localparam [REQ_ID_W-1:0] REQ_ID_EMISSION      = 'h7;

  //----------------------
  // Parameters
  //----------------------
  localparam int CT_BYTE_SIZE      = N * GLWE_K + 1;
  localparam int CT_NB_WORDS_MRMAC = (CT_BYTE_SIZE * 8) / MRMAC_AXIS_W;
  localparam int CT_NB_WORDS_HBM   = (CT_BYTE_SIZE * 8) / AXI4_DATA_W;

endpackage
