// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ==============================================================================================

package mhdma_pkg;
  import param_tfhe_pkg::*;           // TFHE parameterset
  import axi_if_common_param_pkg::*;  // HBM pages
  import axi_if_eth_axi_pkg::*;       // AXI4
  import axi_if_shell_axil_pkg::*;    // REG_DATA_W

  // =========================================================================================== //
  // Parameters
  // =========================================================================================== //
  // BLWE_K = N * GLWE_K
  localparam int CT_NB_COEF        = BLWE_K + 1;
  localparam int CT_SIZE           = CT_NB_COEF * 64;
  localparam int CT_SIZE_BYTE      = CT_SIZE / 8;

  localparam int CT_NB_WORDS_MRMAC = CT_SIZE; // because coef size is MRMAC size
  localparam int CT_NB_WORDS_AXI4  = CT_SIZE/AXI4_DATA_W;

  // =========================================================================================== //
  // Ethernet
  // =========================================================================================== //
  // beware of block design if modifying this values
  localparam int MRMAC_AXIS_W   = 64;
  localparam int MRMAC_TKEEP_W  = 11;
  localparam int ETH_PC         = 2;
  // beware of regfile if modifying this value
  localparam int NB_MAX_HPU   = 8;
  localparam int NB_MAX_HPU_W = $clog2(NB_MAX_HPU);

  localparam int QSFP_LANE_NB   = 4;

  // ETH_NB_BYTES_PAYLOAD must be divisible by MRMAC_AXIS_W. 1472 is the closest to 1518.
  localparam int ETH_NB_BYTES_PAYLOAD = 1472;
  localparam int ETH_NB_BYTES_MIN     = 64;
  localparam int ETH_HEADER_SIZE      = 3;

  localparam int NB_WORDS_PAYLOAD = ETH_NB_BYTES_PAYLOAD / (MRMAC_AXIS_W/8);
  localparam int NB_WORDS_SMALL_PACKETS = ETH_NB_BYTES_MIN / (MRMAC_AXIS_W/8);

  localparam int NB_WORDS_MAX = NB_WORDS_PAYLOAD + ETH_HEADER_SIZE;
  localparam int NB_WORDS_MIN = NB_WORDS_SMALL_PACKETS;

  localparam [15:0] ETH_LEN_MIN = NB_WORDS_SMALL_PACKETS - ETH_HEADER_SIZE ;
  localparam [15:0] ETH_LEN_MAX = NB_WORDS_PAYLOAD + ETH_HEADER_SIZE;

  localparam int NB_PACKETS_FULL = $floor(CT_SIZE_BYTE/ETH_NB_BYTES_PAYLOAD);
  localparam int LAST_PACKET_BYTE_SIZE = CT_SIZE_BYTE - (NB_PACKETS_FULL*ETH_NB_BYTES_PAYLOAD);
  localparam int NB_WORDS_LAST_PACKET_USEFULL = LAST_PACKET_BYTE_SIZE/8;
  localparam int NB_WORDS_LAST_PACKET = (NB_WORDS_LAST_PACKET_USEFULL < NB_WORDS_SMALL_PACKETS) ? NB_WORDS_SMALL_PACKETS : NB_WORDS_LAST_PACKET_USEFULL;

  // Ethernet header: sizes ---------------------------------------------------
  localparam int MAC_ADDR_W   = 24;
  localparam int MAC_OUI_W    = 24;

  localparam int SEQ_NUM_W    = 8;
  localparam int HPU_ID_W     = 4;
  localparam int REQ_ID_W     = 4;
  localparam int ETHERNET_LEN = 16;

  localparam int SIZE_B_W     = 16;
  localparam int IOP_ID_W     = 8;
  localparam int SRC_ADDR_W   = 16;
  localparam int DST_ADDR_W   = 16;

  // ce header transmission size to formatter
  localparam int CEH_WIDTH = MAC_ADDR_W+HPU_ID_W+SIZE_B_W+IOP_ID_W+DST_ADDR_W+SRC_ADDR_W;

  // Ethernet header: values --------------------------------------------------
  localparam [MAC_OUI_W-1:0] MAC_OUI = 'h000A35;
  localparam [ SIZE_B_W-1:0] SIZE_B  = 'h4000; // fixed for now to 16.384

  // =========================================================================================== //
  // fifo specific parameters
  // =========================================================================================== //
  // minimal depth for 64 using XPM fifo is 16
  localparam int XPM_MIN_FIFO_DEPTH    = 16;

  // = Commands
  // read request command: XPM
  localparam int RQQ_MEMORY_TYPE       = "distributed";
  localparam int RQQ_WIDTH             = 2*REG_DATA_W;
  localparam int RQQ_DATA_COUNT_W      =  $clog2(XPM_MIN_FIFO_DEPTH)+1;

  // Notify request command queue: XPM
  localparam int NRQQ_MEMORY_TYPE      = "distributed";
  localparam int NRQQ_WIDTH            = 2*REG_DATA_W;
  localparam int NRQQ_DATA_COUNT_W     = $clog2(XPM_MIN_FIFO_DEPTH)+1;

  // Notify RX payload to regif: XPM
  localparam int NRX_REGF_MEMORY_TYPE  = "distributed";
  localparam int NRX_REGF_WIDTH        = REG_DATA_W;
  localparam int NRX_REGF_DATA_COUNT_W =  $clog2(XPM_MIN_FIFO_DEPTH)+1;

  // Notify RX payload: distributed
  localparam int NRX_WIDTH             = SRC_ADDR_W + HPU_ID_W + IOP_ID_W;
  localparam int NRX_DEPTH             = 4; //TOREVIEW
  localparam int NRX_DATA_COUNT_W      =  $clog2(NRX_DEPTH)+1;

  // read request command queue: URAM fifo
  localparam int RREQ_CMD_DATA_W       = HPU_ID_W+IOP_ID_W+SRC_ADDR_W+DST_ADDR_W;
  localparam int RREQ_CMD_DEPTH        = 16;
  localparam int RREQ_CMD_RAM_LATENCY  = 1;
  localparam int RQQ_CMD_DATA_COUNT_W  =  $clog2(RREQ_CMD_DEPTH)+1;

  // = Ciphertext Emission: URAMs
  // reading each PC
  localparam int READ_PC_DATA_W        = AXI4_DATA_W;
  localparam int READ_PC_DEPTH         = CT_NB_WORDS_AXI4;
  localparam int READ_PC_RAM_LATENCY   = 1;
  localparam int READ_PC_DATA_COUNT_W  =  $clog2(READ_PC_DEPTH)+1;

  // QSFP TX fifo: FIFO CE
  localparam int CE_DATA_W             = MRMAC_AXIS_W;
  localparam int CE_DEPTH              = CT_NB_COEF;
  localparam int CE_RAM_LATENCY        = 1;
  localparam int CE_DATA_COUNT_W       =  $clog2(CE_DEPTH)+1;

  // =========================================================================================== //
  // identification opcode
  // =========================================================================================== //
  localparam [REQ_ID_W-1:0] REQ_ID_NOTIFY_TX     = 'h2;
  localparam [REQ_ID_W-1:0] REQ_ID_ACK_NOTIFY_TX = 'h3;
  // localparam [REQ_ID_W-1:0] REQ_ID_NOTIFY_RX     = 'h4;
  // localparam [REQ_ID_W-1:0] REQ_ID_ACK_NOTIFY_RX = 'h5;
  localparam [REQ_ID_W-1:0] REQ_ID_READ          = 'h6;
  localparam [REQ_ID_W-1:0] REQ_ID_EMISSION      = 'h7;

  // =========================================================================================== //
  // Offsets
  // =========================================================================================== //
  // Read ReQuest Queue
  localparam int CMD_IOP_ID_OFS   = SRC_ADDR_W + DST_ADDR_W + SIZE_B_W + HPU_ID_W + REQ_ID_W + IOP_ID_W;
  localparam int CMD_REQ_ID_OFS   = SRC_ADDR_W + DST_ADDR_W + SIZE_B_W + HPU_ID_W + REQ_ID_W;
  localparam int CMD_HPU_ID_OFS   = SRC_ADDR_W + DST_ADDR_W + SIZE_B_W + HPU_ID_W;
  localparam int CMD_SIZE_B_OFS   = SRC_ADDR_W + DST_ADDR_W + SIZE_B_W;
  localparam int CMD_DST_ADDR_OFS = SRC_ADDR_W + DST_ADDR_W;
  localparam int CMD_SRC_ADDR_OFS = SRC_ADDR_W;

  // Slave offset: notify request
  localparam int NRX_SRC_ADDR_OFS = IOP_ID_W + HPU_ID_W + SRC_ADDR_W;
  localparam int NRX_HPU_ID_OFS   = IOP_ID_W + HPU_ID_W;
  localparam int NRX_IOP_ID_OFS   = IOP_ID_W;

  // Slave offset: ciphertext emission offset
  localparam int CEH_DST_MAC_ADDR_OFS = SRC_ADDR_W + DST_ADDR_W + SIZE_B_W + HPU_ID_W + IOP_ID_W + MAC_ADDR_W;
  localparam int CEH_IOP_ID_OFS       = SRC_ADDR_W + DST_ADDR_W + SIZE_B_W + HPU_ID_W + IOP_ID_W;
  localparam int CEH_HPU_ID_OFS       = SRC_ADDR_W + DST_ADDR_W + SIZE_B_W + HPU_ID_W;
  localparam int CEH_SIZE_B_OFS       = SRC_ADDR_W + DST_ADDR_W + SIZE_B_W;
  localparam int CEH_DST_ADDR_OFS     = SRC_ADDR_W + DST_ADDR_W;
  localparam int CEH_SRC_ADDR_OFS     = SRC_ADDR_W;

  // Read-Request
  localparam int RR_HPU_ID_OFS = SRC_ADDR_W + DST_ADDR_W + IOP_ID_W + HPU_ID_W;
  localparam int RR_IOP_ID_OFS = SRC_ADDR_W + DST_ADDR_W + IOP_ID_W;
  localparam int RR_DST_ID_OFS = SRC_ADDR_W + DST_ADDR_W;
  localparam int RR_SRC_ID_OFS = SRC_ADDR_W;

  // Headers (0,1,2,3) for the clock cycle
  localparam int H0_DST_MAC_ADDR_OFS = 16 + MAC_ADDR_W;
  localparam int H0_SRC_OUI_OFS = 16;

  localparam int H1_SRC_MAC_ADDR_OFS = SEQ_NUM_W + HPU_ID_W + REQ_ID_W + ETHERNET_LEN + MAC_ADDR_W;
  localparam int H1_SRC_ETH_LEN_OFS  = SEQ_NUM_W + HPU_ID_W + REQ_ID_W + ETHERNET_LEN;
  localparam int H1_REQ_ID_OFS       = SEQ_NUM_W + HPU_ID_W + REQ_ID_W;
  localparam int H1_HPU_ID_OFS       = SEQ_NUM_W + HPU_ID_W;
  localparam int H1_SEQ_NUM_OFS      = SEQ_NUM_W;

  localparam int H2_CT_SRC_ADDR_OFS = 8 + SIZE_B_W + IOP_ID_W + SRC_ADDR_W + DST_ADDR_W;
  localparam int H2_CT_DST_ADDR_OFS = 8 + SIZE_B_W + IOP_ID_W + SRC_ADDR_W;
  localparam int H2_IOP_ID_OFS      = 8 + SIZE_B_W + IOP_ID_W;
  localparam int H2_SIZE_B_OFS      = 8 + SIZE_B_W;
  localparam int H2_EMPTY_OFS       = 8;

  // =========================================================================================== //
  // Functions
  // =========================================================================================== //
  function automatic logic [MRMAC_AXIS_W-1:0] byte_swap (input logic [MRMAC_AXIS_W-1:0] data_in);
    logic [MRMAC_AXIS_W-1:0] data_out;
    for (int i = 0; i < 8; i++) begin
      data_out[(MRMAC_AXIS_W - ((i + 1) * 8)) +: 8] = data_in[(i*8) +: 8];
    end
    return data_out;
  endfunction

endpackage
