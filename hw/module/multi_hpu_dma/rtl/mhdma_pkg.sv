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
  localparam int CT_NB_COEF   = BLWE_K + 1;
  localparam int CT_SIZE      = CT_NB_COEF * 64;
  localparam int CT_SIZE_BYTE = CT_SIZE / 8;

  localparam [AXI4_SIZE_W-1:0] MHDMA_ARSIZE = $clog2(AXI4_DATA_BYTES);

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

  localparam int CT_NB_WORDS_MRMAC = CT_SIZE/MRMAC_AXIS_W; // because coef size is MRMAC size
  localparam int CT_NB_WORDS_AXI4  = CT_SIZE/AXI4_DATA_W;

  localparam int QSFP_LANE_NB   = 4;

  // ETH_NB_BYTES_PAYLOAD must be divisible by MRMAC_AXIS_W. 1472 is the closest to 1518.
  localparam int ETH_NB_BYTES_PAYLOAD = 1472;
  localparam int ETH_NB_BYTES_MIN     = 64;
  localparam int ETH_NB_BYTES_HEADER  = 14;
  localparam int ETH_NB_BYTES_CRC     = 4;

  localparam int NB_WORDS_CUST_HEADER_SIZE = 4;

  localparam int NB_WORDS_PAYLOAD = ETH_NB_BYTES_PAYLOAD / (MRMAC_AXIS_W/8);
  localparam int NB_WORDS_SMALL_PACKETS = ETH_NB_BYTES_MIN / (MRMAC_AXIS_W/8);
  localparam int NB_WORDS_MAX = NB_WORDS_PAYLOAD + NB_WORDS_CUST_HEADER_SIZE;
  localparam int NB_WORDS_MIN = NB_WORDS_SMALL_PACKETS;

  localparam int NB_PACKETS_FULL = $floor(CT_SIZE_BYTE/ETH_NB_BYTES_PAYLOAD);
  localparam int LAST_PACKET_BYTE_SIZE_USEFULL = CT_SIZE_BYTE - (NB_PACKETS_FULL*ETH_NB_BYTES_PAYLOAD);

  // I have LAST_PACKET_BYTE_SIZE usefull bytes. To simplify i'll send a multiple of AXI4_DATA_W
  // it is important to have a real concatenation here to be sure to have the ceiling and not be truncated by integer
  localparam int LAST_PACKET_BYTE_SIZE =  $ceil(real'(LAST_PACKET_BYTE_SIZE_USEFULL) / AXI4_DATA_BYTES)*AXI4_DATA_BYTES;

  // If ever I need to send less words and what is allowed by ethernet, we need to fill with zeros
  localparam int NB_WORDS_LAST_PACKET_USEFULL = LAST_PACKET_BYTE_SIZE/8;
  localparam int NB_WORDS_LAST_PACKET = (NB_WORDS_LAST_PACKET_USEFULL < NB_WORDS_SMALL_PACKETS) ? NB_WORDS_SMALL_PACKETS : NB_WORDS_LAST_PACKET_USEFULL;

  localparam [15:0] ETH_LEN_MIN      = ETH_NB_BYTES_MIN - ETH_NB_BYTES_HEADER - ETH_NB_BYTES_CRC;
  localparam [15:0] ETH_LEN_MAX      = ETH_NB_BYTES_PAYLOAD;
  localparam [15:0] ETH_LEN_LAST_PKT = LAST_PACKET_BYTE_SIZE;

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

  localparam int LLC_W        = 8;

  // ce header transmission size to formatter
  localparam int CEH_WIDTH = MAC_ADDR_W+HPU_ID_W+SIZE_B_W+IOP_ID_W+DST_ADDR_W+SRC_ADDR_W;

  // Ethernet header: values --------------------------------------------------
  localparam [MAC_OUI_W-1:0] MAC_OUI = 'h000A35;
  localparam [ SIZE_B_W-1:0] SIZE_B  = 'h4000; // fixed for now to 16.384

  localparam [LLC_W-1:0] LLC_DSAP = 'hF8;
  localparam [LLC_W-1:0] LLC_SSAP = 'hF8;
  localparam [LLC_W-1:0] LLC_CTRL = 'h03;

  // =========================================================================================== //
  // fifo specific parameters
  // =========================================================================================== //
  // minimal depth for 64 using XPM fifo is 16
  // LIMITATION: XPM_MIN_FIFO_DEPTH is the max number of command that can be sent before processed (RR & Notify)
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
  localparam int NRX_RAM_LATENCY       = 1;
  localparam int NRX_DATA_COUNT_W      =  $clog2(NRX_DEPTH)+1;

  // read request command queue: URAM fifo
  localparam int RREQ_CMD_DATA_W       = HPU_ID_W+IOP_ID_W+SRC_ADDR_W+DST_ADDR_W;
  localparam int RREQ_CMD_DEPTH        = XPM_MIN_FIFO_DEPTH;
  localparam int RREQ_CMD_RAM_LATENCY  = 1;
  localparam int RQQ_CMD_DATA_COUNT_W  =  $clog2(RREQ_CMD_DEPTH)+1;

  // = Ciphertext Emission: URAMs
  // reading/ writing to each PC
  localparam int FIFO_PC_DATA_W        = AXI4_DATA_W;
  localparam int FIFO_PC_DEPTH         = CT_NB_WORDS_AXI4/2;
  localparam int FIFO_PC_RAM_LATENCY   = 1;
  localparam int FIFO_PC_DATA_COUNT_W  =  $clog2(FIFO_PC_DEPTH)+1;

  // QSFP TX fifo: FIFO CE
  localparam int CE_DATA_W             = MRMAC_AXIS_W;
  localparam int CE_DEPTH              = CT_NB_COEF;
  localparam int CE_RAM_LATENCY        = 1;
  localparam int CE_DATA_COUNT_W       =  $clog2(CE_DEPTH)+1;

  // QSFP RX fifo: FIFO CE
  localparam int CERX_DATA_W           = MRMAC_AXIS_W;
  // localparam int CERX_DEPTH            = CT_NB_COEF;
  localparam int CERX_RAM_LATENCY      = 1;
  localparam int CERX_DATA_COUNT_W     =  $clog2(CE_DEPTH)+1;

  // =========================================================================================== //
  // identification opcode
  // =========================================================================================== //
  localparam [REQ_ID_W-1:0] REQ_ID_NOTIFY_TX     = 'h2;
  localparam [REQ_ID_W-1:0] REQ_ID_ACK_NOTIFY_TX = 'h3;
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

  localparam int H1_SRC_MAC_ADDR_OFS = 16 + ETHERNET_LEN + MAC_ADDR_W;
  localparam int H1_SRC_ETH_LEN_OFS  = 16 + ETHERNET_LEN;

  localparam int H2_REQ_ID_OFS      = IOP_ID_W + DST_ADDR_W + SRC_ADDR_W + SEQ_NUM_W + HPU_ID_W + REQ_ID_W;
  localparam int H2_HPU_ID_OFS      = IOP_ID_W + DST_ADDR_W + SRC_ADDR_W + SEQ_NUM_W + HPU_ID_W;
  localparam int H2_SEQ_NUM_OFS     = IOP_ID_W + DST_ADDR_W + SRC_ADDR_W + SEQ_NUM_W;
  localparam int H2_CT_SRC_ADDR_OFS = IOP_ID_W + DST_ADDR_W + SRC_ADDR_W;
  localparam int H2_CT_DST_ADDR_OFS = IOP_ID_W + DST_ADDR_W;
  localparam int H2_IOP_ID_OFS      = IOP_ID_W;

  localparam int H3_SIZE_B_OFS      = 48 + SIZE_B_W;
  localparam int H3_EMPTY_OFS       = 48;

  typedef struct packed {
    logic                  valid;
    logic [MAC_ADDR_W-1:0] src_mac_addr;
    logic [ SEQ_NUM_W-1:0] seq_num;
    logic [  HPU_ID_W-1:0] hpu_id;
    logic [  SIZE_B_W-1:0] size_b;
    logic [  REQ_ID_W-1:0] req_id;
    logic [  IOP_ID_W-1:0] iop_id;
    logic [SRC_ADDR_W-1:0] src_addr;
    logic [DST_ADDR_W-1:0] dst_addr;
  } header_t;

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


  // parameter generation
  // to be reviewed
  typedef int unpacked_array_t [ETH_PC];

  function automatic unpacked_array_t compute_nb_words (
    input int pc_ct_bytes [ETH_PC]
  );
    int pc_nb_words [ETH_PC];
    for (int i = 0; i < ETH_PC; i++) begin
      pc_nb_words[i] = pc_ct_bytes[i] / AXI4_DATA_BYTES;
    end
    return pc_nb_words;
  endfunction

  function automatic unpacked_array_t compute_nb_bursts(
    input int pc_nb_words[ETH_PC],
    input int                      max_burst_size
  );
    int pc_nb_bursts[ETH_PC];
    for (int i = 0; i < ETH_PC; i++) begin
      pc_nb_bursts[i] = pc_nb_words[i] / max_burst_size;
    end
    return pc_nb_bursts;
  endfunction

  function automatic unpacked_array_t compute_remaining_words(
    input int pc_nb_words[ETH_PC],
    input int                      max_burst_size
  );
    int pc_nb_remaining[ETH_PC];
    for (int i = 0; i < ETH_PC; i++) begin
      pc_nb_remaining[i] = pc_nb_words[i] % max_burst_size;
    end
    return pc_nb_remaining;
  endfunction

  function automatic unpacked_array_t compute_nb_transactions(
    input int pc_nb_remain[ETH_PC],
    input int pc_nb_bursts[ETH_PC]
  );
    int pc_nb_trans [ETH_PC];
    for (int i = 0; i < ETH_PC; i++) begin
      pc_nb_trans[i] = (pc_nb_remain[i] != 0) ? pc_nb_bursts[i] + pc_nb_remain[i] : pc_nb_bursts[i];
    end
    return pc_nb_trans;
  endfunction


endpackage
