// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ==============================================================================================

package mhdma_pkg;
  import param_tfhe_pkg::*;           // TFHE parameterset
  import axi_if_common_param_pkg::*;  // HBM pages
  import axi_if_eth_axi_pkg::*;       // AXI4
  import axi_if_shell_axil_pkg::*;    // REG_DATA_W

  import top_common_param_pkg::*;    // PEM_PC
  import pem_common_param_pkg::*;    // CT_MEM_BYTES, AXI4_WORD_PER_PC_L*

  // =========================================================================================== //
  // Parameters
  // =========================================================================================== //
  // BLWE_K = N * GLWE_K
  localparam int CT_NB_COEF   = BLWE_K + 1;
  localparam int CT_SIZE      = CT_NB_COEF * 64;
  localparam int CT_SIZE_BYTE = CT_SIZE / 8;

  localparam [AXI4_SIZE_W-1:0] MHDMA_ARSIZE = $clog2(AXI4_DATA_BYTES);

  localparam [AXI4_ID_W-1:0] MHDMA_AXI_ARID = '0; // Use the same ID for read/writes

  // =========================================================================================== //
  // Ethernet
  // =========================================================================================== //
  // beware of block design if modifying this values
  localparam int MRMAC_AXIS_W   = 64;
  localparam int MRMAC_TKEEP_W  = 11;
  localparam int NB_MRMRAC_WORDS_PER_READ = AXI4_DATA_W/MRMAC_AXIS_W;

  localparam int ETH_PC       = PEM_PC; // MHDMA is tied to PEM module: mandatory same number of PC
  // beware of regfile if modifying this value
  localparam int NB_MAX_HPU   = 8;
  localparam int NB_MAX_HPU_W = $clog2(NB_MAX_HPU);

  localparam int CT_NB_WORDS_MRMAC = CT_SIZE/MRMAC_AXIS_W; // because coef size is MRMAC size
  localparam int CT_NB_WORDS_AXI4  = CT_SIZE/AXI4_DATA_W;

  localparam int NB_MRMRAC_WORDS_PER_WRITE = AXI4_DATA_W/MRMAC_AXIS_W;

  localparam int COUNTER_W      = 32; // this is arbitrary

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
  localparam int LAST_PACKET_BYTE_SIZE_USEFUL = CT_SIZE_BYTE - (NB_PACKETS_FULL*ETH_NB_BYTES_PAYLOAD);

  // I have LAST_PACKET_BYTE_SIZE useful bytes. To simplify I'll send a multiple of AXI4_DATA_W
  // it is important to have a real concatenation here to be sure to have the ceiling and not be truncated by integer
  localparam int LAST_PACKET_BYTE_SIZE = $ceil(real'(LAST_PACKET_BYTE_SIZE_USEFUL) / AXI4_DATA_BYTES)*AXI4_DATA_BYTES;

  // If ever I need to send less words and what is allowed by ethernet, we need to fill with zeros
  localparam int NB_WORDS_LAST_PACKET_USEFUL = LAST_PACKET_BYTE_SIZE/8;
  localparam int NB_WORDS_LAST_PACKET = (NB_WORDS_LAST_PACKET_USEFUL < NB_WORDS_SMALL_PACKETS) ? NB_WORDS_SMALL_PACKETS : NB_WORDS_LAST_PACKET_USEFUL;

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

  localparam int RSVD_W       = 8;
  localparam int FLAG_W       = 6;
  localparam int MODE_W       = 2;
  localparam int IOP_ID_W     = 8;
  localparam int SRC_ADDR_W   = 16;
  localparam int DST_ADDR_W   = 16;

  localparam int LLC_W        = 8;

  // Ethernet header: values --------------------------------------------------
  localparam [MAC_OUI_W-1:0] MAC_OUI = 'h000A35;

  localparam [LLC_W-1:0] LLC_DSAP = 'hF8;
  localparam [LLC_W-1:0] LLC_SSAP = 'hF8;
  localparam [LLC_W-1:0] LLC_CTRL = 'h03;

  // =========================================================================================== //
  // fifo specific parameters
  // =========================================================================================== //
  // minimal depth for 64 using XPM fifo is 16
  // LIMITATION: XPM_MIN_FIFO_DEPTH is the max number of command that can be sent before processed (RR & Notify)
  localparam int XPM_MIN_FIFO_DEPTH = 16;

  // = Commands
  // Request Fifo sizes
  localparam int REQ_MEMORY_TYPE       = "distributed";
  localparam int REQ_FIFO_DEPTH        = XPM_MIN_FIFO_DEPTH;
  localparam int REQ_DATA_COUNT_W      =  $clog2(REQ_FIFO_DEPTH)+1;

  // RX fifo : decoder reception fifo. Must be greater than Command fifos
  localparam int RX_FIFO_DEPTH = 64;

  // Notify RX payload: distributed
  localparam int NRX_DEPTH             = 4; //TOREVIEW
  localparam int NRX_RAM_LATENCY       = 1;
  localparam int NRX_DATA_COUNT_W      = $clog2(NRX_DEPTH)+1;

  // read request command queue: URAM fifo
  localparam int RREQ_CMD_DEPTH        = XPM_MIN_FIFO_DEPTH;
  localparam int RREQ_CMD_RAM_LATENCY  = 1;
  localparam int RQQ_CMD_DATA_COUNT_W  = $clog2(RREQ_CMD_DEPTH)+1;

  // = Ciphertext Emission: URAMs
  // reading/ writing to each PC
  localparam int FIFO_PC_DEPTH         = CT_NB_WORDS_AXI4/2;
  localparam int FIFO_PC_RAM_LATENCY   = 1;
  localparam int FIFO_PC_DATA_COUNT_W  = $clog2(FIFO_PC_DEPTH)+1;

  // QSFP TX fifo: FIFO CE
  localparam int CE_RAM_LATENCY        = 1;
  localparam int CE_DATA_COUNT_W       = $clog2(CT_NB_COEF)+1;

  // =========================================================================================== //
  // identification opcode
  // =========================================================================================== //
  localparam [REQ_ID_W-1:0] REQ_ID_NOTIFY     = 'h2;
  localparam [REQ_ID_W-1:0] REQ_ID_NOTIFY_ACK = 'h3;
  localparam [REQ_ID_W-1:0] REQ_ID_READ       = 'h6;
  localparam [REQ_ID_W-1:0] REQ_ID_EMISSION   = 'h7;

  // =========================================================================================== //
  // Packed structures
  // =========================================================================================== //
  // Command structure for MHDMA module -----------------------------------------------------------
  typedef struct packed {
    logic [MAC_ADDR_W-1:0] src_mac_addr;
    logic [ SEQ_NUM_W-1:0] seq_num;
    logic [  HPU_ID_W-1:0] hpu_id;
    logic [    RSVD_W-1:0] rsvd;
    logic [    FLAG_W-1:0] flag;
    logic [    MODE_W-1:0] mode;
    logic [  REQ_ID_W-1:0] req_id;
    logic [  IOP_ID_W-1:0] iop_id;
    logic [SRC_ADDR_W-1:0] src_addr;
    logic [DST_ADDR_W-1:0] dst_addr;
  } command_t;

  //  Ethernet frames, one by one -----------------------------------------------------------------
  typedef struct packed {
    logic [MAC_OUI_W-1:0]  dst_mac_oui;
    logic [MAC_ADDR_W-1:0] dst_mac_addr;
    logic [15:0]           src_oui;
  } h0_frame_t;

  typedef struct packed {
    logic [7:0]              src_mac_oui;
    logic [MAC_ADDR_W-1:0]   src_mac_addr;
    logic [ETHERNET_LEN-1:0] eth_len;
    logic [2*LLC_W-1:0]      llc; // DSAP + SSAP
  } h1_frame_t;

  typedef struct packed {
    logic [LLC_W-1:0]      llc_ctrl;
    logic [REQ_ID_W-1:0]   req_id;
    logic [HPU_ID_W-1:0]   hpu_id;
    logic [SEQ_NUM_W-1:0]  seq_num;
    logic [SRC_ADDR_W-1:0] ct_src_addr;
    logic [DST_ADDR_W-1:0] ct_dst_addr;
    logic [IOP_ID_W-1:0]   iop_id;
  } h2_frame_t;

  typedef struct packed {
    logic [RSVD_W-1:0] h3_rsvd;
    logic [FLAG_W-1:0] flag;
    logic [MODE_W-1:0] mode;
    logic      [47:0]  h3_pad;
  } h3_frame_t;

  // Errors ---------------------------------------------------------------------------------------
  typedef struct packed {
    logic formatter_error;
  } format_error_t;

  typedef struct packed {
    logic error_fifo_rx_ovf;
  } decoder_error_t;

  typedef struct packed {
    logic error_fifo_nrx_commands_ovf;
  } slave_error_t;

  typedef struct packed {
    logic              seq_num_error;
    logic [ETH_PC-1:0] write_error;
  } master_error_t;

  typedef struct packed {
    format_error_t  format_error;
    decoder_error_t decoder_error;
    slave_error_t   slave_error;
    master_error_t  master_error;
    logic           error_id;
  } mhdma_error_t;

  // =========================================================================================== //
  // Per-submodule stat/rst structs
  // =========================================================================================== //
  // Master stat output
  typedef struct packed {
    logic [REG_DATA_W-1:0] cnt_notify;
    logic [REG_DATA_W-1:0] cnt_notify_ack;
    logic [REG_DATA_W-1:0] cnt_notify_retries;
    logic [REG_DATA_W-1:0] cnt_read_req_retries;
    logic [REG_DATA_W-1:0] cnt_notify_timeout;
    logic [REG_DATA_W-1:0] nb_ce_words_received;
    logic [REG_DATA_W-1:0] nb_write_complete_cnt;
    logic [REG_DATA_W-1:0] t_notify_to_ack;
    logic [REG_DATA_W-1:0] t_rr_to_ce_received;
    logic [1:0]            fsm_notify;
    logic [1:0]            fsm_read_req;
  } master_stat_t;

  // Master stat reset input
  typedef struct packed {
    logic cnt_notify;
    logic cnt_notify_ack;
    logic cnt_timeout;
    logic cnt_notify_retry;
    logic cnt_read_req_retry;
    logic nb_ce_words_received;
  } master_stat_rst_t;

  // Slave stat output
  typedef struct packed {
    logic             [  REG_DATA_W-1:0] nb_read_to_hbm;
    logic [ETH_PC-1:0][  REG_DATA_W-1:0] nb_words_received_pc;
    logic [ETH_PC-1:0][  REG_DATA_W-1:0] t_rr_wait_words_pc;
    logic [1:0]                          fsm_notify_rx;
    logic [1:0]                          fsm_cem;
    logic [ETH_PC-1:0][2*REG_DATA_W-1:0] rr_phy_addr;
  } slave_stat_t;

  // Slave stat reset input
  typedef struct packed {
    logic              nb_read_to_hbm;
    logic [ETH_PC-1:0] nb_words_received_pc;
  } slave_stat_rst_t;

  // Decoder stat output
  typedef struct packed {
    logic [REG_DATA_W-1:0] t_ce_first_to_last_pkt;
    logic [REG_DATA_W-1:0] cnt_nack_received;
    logic [REG_DATA_W-1:0] cnt_notify_received;
    logic [REG_DATA_W-1:0] cnt_read_req_received;
    logic [REG_DATA_W-1:0] cnt_ce_received;
  } decoder_stat_t;

  // Decoder stat reset input
  typedef struct packed {
    logic cnt_nack_received;
    logic cnt_notify_received;
    logic cnt_read_req_received;
    logic cnt_ce_received;
  } decoder_stat_rst_t;

  // Formatter stat output
  typedef struct packed {
    logic [2:0] fsm_formatter;
  } formatter_stat_t;

  // =========================================================================================== //
  // CDC structs (used in multi_hpu_dma top and mhdma_bridge)
  // =========================================================================================== //
  // Reset signals (single-bit, CFG -> ETH) - nests per-submodule rst structs
  typedef struct packed {
    master_stat_rst_t  master;
    slave_stat_rst_t   slave;
    decoder_stat_rst_t decoder;
    logic              mhdma_errors;
  } mhdma_rst_cnt_t;

  // All stat values (ETH -> CFG) - nests per-submodule stat structs
  typedef struct packed {
    master_stat_t    master;
    slave_stat_t     slave;
    decoder_stat_t   decoder;
    formatter_stat_t formatter;
    logic [REG_DATA_W-1:0] mhdma_errors;
  } mhdma_cnt_t;

  // =========================================================================================== //
  // Functions
  // =========================================================================================== //
  function automatic logic [MRMAC_AXIS_W-1:0] byte_swap(
    input logic [MRMAC_AXIS_W-1:0] data_in
  );
    return {<<8{data_in}};
  endfunction

endpackage
