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
  import param_tfhe_pkg::*;           // TFHE parameterset
  import axi_if_common_param_pkg::*;  // HBM pages
  import axi_if_eth_axi_pkg::*;       // AXI4
  import axi_if_shell_axil_pkg::*;    // REG_DATA_W

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

  // ETH_NB_BYTES_PAYLOAD must be divisible by AXI4_DATA_BYTES
  localparam int ETH_NB_BYTES_PAYLOAD = 1024;
  localparam int ETH_NB_BYTES_MIN = 64;
  localparam int ETH_HEADER_SIZE = 3;

  localparam int NB_WORDS_PAYLOAD = (ETH_NB_BYTES_PAYLOAD * 8) / MRMAC_AXIS_W;
  localparam int NB_WORDS_HEADER  = (ETH_NB_BYTES_MIN * 8) / MRMAC_AXIS_W;

  localparam [15:0] ETH_LEN_MIN = NB_WORDS_HEADER  - ETH_HEADER_SIZE ;
  localparam [15:0] ETH_LEN_MAX = NB_WORDS_PAYLOAD + ETH_HEADER_SIZE;

  // generic sizes on ethernet
  localparam int NB_WORDS_MIN = 7; // without fcs

  //----------------------
  // Parameters
  //----------------------
  // BLWE_K = N * GLWE_K
  localparam int CT_NB_COEF        = BLWE_K + 1;
  localparam int CT_SIZE           = CT_NB_COEF * 64;
  localparam int CT_SIZE_BYTE      = CT_SIZE / 8;

  localparam int CT_NB_WORDS_MRMAC = CT_SIZE; // because coef size is MRMAC size
  localparam int CT_NB_WORDS_AXI4  = CT_SIZE/AXI4_DATA_W;

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
  localparam [ SIZE_B_W-1:0] SIZE_B  = 'h4000; // fixed for now to 16.384

  // fifo specific parameters -------------------------------------------------
  // minimal depth for 64 using XPM fifo is 16
  localparam int XPM_MIN_FIFO_DEPTH   = 16;

  // = Commands
  // read request command: XPM
  localparam int RQQ_MEMORY_TYPE      = "distributed";
  localparam int RQQ_WIDTH            = 2*REG_DATA_W;
  localparam int RQQ_DATA_COUNT_W     =  $clog2(XPM_MIN_FIFO_DEPTH)+1;

  // Notify request command queue: XPM
  localparam int NRQQ_MEMORY_TYPE     = "distributed";
  localparam int NRQQ_WIDTH           = 2*REG_DATA_W;
  localparam int NRQQ_DATA_COUNT_W    =  $clog2(XPM_MIN_FIFO_DEPTH)+1;

  // Notify RX payload: XPM
  localparam int NRX_MEMORY_TYPE      = "distributed";
  localparam int NRX_WIDTH            = REG_DATA_W;
  localparam int NRX_DATA_COUNT_W     =  $clog2(XPM_MIN_FIFO_DEPTH)+1;

  // read request command queue: URAM fifo
  localparam int RREQ_CMD_DATA_W      = HPU_ID_W+IOP_ID_W+SRC_ADDR_W+DST_ADDR_W;
  localparam int RREQ_CMD_DEPTH       = 16;
  localparam int RREQ_CMD_RAM_LATENCY = 1;
  localparam int RQQ_CMD_DATA_COUNT_W =  $clog2(RREQ_CMD_DEPTH)+1;

  // = Ciphertext Emission: URAMs
  // reading each PC
  localparam int READ_PC_DATA_W       = AXI4_DATA_W;
  localparam int READ_PC_DEPTH        = CT_NB_WORDS_AXI4;
  localparam int READ_PC_RAM_LATENCY  = 1;
  localparam int READ_PC_DATA_COUNT_W =  $clog2(CT_NB_WORDS_AXI4)+1;

  // QSFP TX fifo
  localparam int CE_DATA_W       = MRMAC_AXIS_W;
  localparam int CE_DEPTH        = NB_WORDS_PAYLOAD;
  localparam int CE_RAM_LATENCY  = 1;
  localparam int CE_DATA_COUNT_W =  $clog2(NB_WORDS_PAYLOAD)+1;

  // identification opcode --------------------------------------------------
  localparam [REQ_ID_W-1:0] REQ_ID_NOTIFY_TX     = 'h2;
  localparam [REQ_ID_W-1:0] REQ_ID_ACK_NOTIFY_TX = 'h3;
  localparam [REQ_ID_W-1:0] REQ_ID_NOTIFY_RX     = 'h4;
  localparam [REQ_ID_W-1:0] REQ_ID_ACK_NOTIFY_RX = 'h5;
  localparam [REQ_ID_W-1:0] REQ_ID_READ          = 'h6;
  localparam [REQ_ID_W-1:0] REQ_ID_EMISSION      = 'h7;

endpackage
