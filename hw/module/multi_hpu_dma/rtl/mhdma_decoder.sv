// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Multi-HPU DMA reception and decoder module
// ==============================================================================================

module mhdma_decoder
  import mhdma_pkg::*;
#() (
  // Ethernet fast clock interface --------------------------------------------
  input  logic                     clk_mrmac,
  input  logic                     resetn_mrmac,
  // Command interface --------------------------------------------------------
  output logic                     notify_ack_received,
  output logic                     notify_request_received,
  output logic                     read_request_received,
  output logic                     ciphertext_emission_received,
  // Header information -------------------------------------------------------
  input  logic [MAC_ADDR_W-1:0]    current_hpu_mac,
  output logic [MAC_ADDR_W-1:0]    rx_dst_mac_addr,
  output logic [SEQ_NUM_W-1:0]     rx_sec_num,
  output logic [HPU_ID_W-1:0]      rx_hpu_id,
  output logic [REQ_ID_W-1:0]      rx_req_id,
  output logic [MAC_ADDR_W-1:0]    rx_src_mac_addr,
  output logic [SIZE_B_W-1:0]      rx_size_b,
  output logic [IOP_ID_W-1:0]      rx_iop_id,
  output logic [SRC_ADDR_W-1:0]    rx_ct_src_addr,
  output logic [DST_ADDR_W-1:0]    rx_ct_dst_addr,
  output logic                     rx_header_valid,
  // RX payload ---------------------------------------------------------------
  output logic [MRMAC_AXIS_W-1:0]  rx_tdata,
  output logic                     rx_tsop,
  output logic                     rx_tlast,
  output logic                     rx_tvalid,
  // QSFP system interface ----------------------------------------------------
  // == RX
  input  logic [MRMAC_AXIS_W-1:0]  qsfp_rx_tdata,
  input  logic [MRMAC_TKEEP_W-1:0] qsfp_rx_tkeep_user,
  input  logic                     qsfp_rx_tlast,
  input  logic                     qsfp_rx_tvalid
);

  // ==============================================================================================
  // packet decoder
  // ==============================================================================================
  // On RX lanes, should know as soon as possible what type of packets I should see
  // First frame I can check that the destination address is me
  logic [MAC_ADDR_W-1:0] dst_mac_addr;
  // Second frame I will know who is the sender, request ID, seq num
  logic [SEQ_NUM_W-1:0]  sec_num;
  logic [HPU_ID_W-1:0]   hpu_id;
  logic [REQ_ID_W-1:0]   req_id;
  logic [MAC_ADDR_W-1:0] src_mac_addr;
  // third frame, ct src/dst address, iop id, size_byte
  logic [SIZE_B_W-1:0]   size_b;
  logic [IOP_ID_W-1:0]   iop_id;
  logic [SRC_ADDR_W-1:0] ct_src_addr;
  logic [DST_ADDR_W-1:0] ct_dst_addr;

  // We need to byte swap tdata in
  logic [MRMAC_AXIS_W-1:0] qsfp_rx_tdata_bs;
  assign qsfp_rx_tdata_bs = byte_swap(qsfp_rx_tdata);

  // =========================================================================================== //
  // QSFP RX
  // =========================================================================================== //
  // We must gather RX data as soon as possible and redirect commands into their respective
  // command queue or signal.
  // - ACK Notify TX is only a reception signal     : ntx_ack
  // - Notify RX goes to respective queue           : NRXQ
  // - Read request goes to write fifo to go to HBM : RRFIFO
  // - Ciphertext Emission goes to queue            : CEQ
  logic qsfp_rx_tsop;
  logic qsfp_rx_tvalidD;

  always_ff @(posedge clk_mrmac)
    qsfp_rx_tvalidD <= qsfp_rx_tvalid;

  assign qsfp_rx_tsop = qsfp_rx_tvalid & ~qsfp_rx_tvalidD;

  logic [$clog2(ETH_LEN_MAX):0] rx_counter;
  always_ff @(posedge clk_mrmac) begin
    if (qsfp_rx_tvalid) begin
      rx_counter <= rx_counter+1;
    end else begin
      rx_counter <= 0;
    end
  end

  /* FRAME 0:
   * dst_mac_addr
   *    destination mac address is not needed from the first clock cycle
   *    this register will help define if next words in receptions are valid
   */
  logic rx_valid;
  always_ff @(posedge clk_mrmac)
    if (qsfp_rx_tvalid &qsfp_rx_tsop)
      dst_mac_addr <=  qsfp_rx_tdata_bs[H0_DST_MAC_ADDR_OFS-1:H0_SRC_OUI_OFS];

  assign rx_valid = (current_hpu_mac == dst_mac_addr) ? 1'b1 : 1'b0;

  /* FRAME 1 :
   * sec_num, request_id, hpu_id, src_mac_address
   * ethernet len is skipped: not used for now
   */
  always_ff @(posedge clk_mrmac) begin
    if ( (qsfp_rx_tvalid) & (rx_counter == 1)) begin
      sec_num      <= qsfp_rx_tdata_bs[H1_SEQ_NUM_OFS-1:0];
      hpu_id       <= qsfp_rx_tdata_bs[H1_HPU_ID_OFS-1:H1_SEQ_NUM_OFS];
      req_id       <= qsfp_rx_tdata_bs[H1_REQ_ID_OFS-1:H1_HPU_ID_OFS];
      // Ethernet len is ignored
      src_mac_addr <= qsfp_rx_tdata_bs[H1_SRC_MAC_ADDR_OFS-1:H1_SRC_ETH_LEN_OFS];
    end
  end

  /* FRAME 2:
   * iop_id, src/dst addresses
   * size_b for triggering error
   */
  always_ff @(posedge clk_mrmac) begin
    if ((qsfp_rx_tvalid) & (rx_counter == 2)) begin
      iop_id      <= qsfp_rx_tdata_bs[H2_IOP_ID_OFS-1:H2_SIZE_B_OFS];
      ct_dst_addr <= qsfp_rx_tdata_bs[H2_CT_DST_ADDR_OFS-1:H2_IOP_ID_OFS];
      ct_src_addr <= qsfp_rx_tdata_bs[H2_CT_SRC_ADDR_OFS-1:H2_CT_DST_ADDR_OFS];
    end
  end

  assign size_b = ((rx_counter == 2) & rx_valid) ? qsfp_rx_tdata_bs[H2_SIZE_B_OFS-1:H2_EMPTY_OFS] : 'h0;

  // assigning output -----------------------------------------------------------------------------

  // decoding commands
  assign notify_ack_received          = (rx_valid & (rx_req_id == REQ_ID_ACK_NOTIFY_TX)) ? 1'b1 : 1'b0;
  assign notify_request_received      = (rx_valid & (rx_req_id == REQ_ID_NOTIFY_TX))     ? 1'b1 : 1'b0;
  assign read_request_received        = (rx_valid & (rx_req_id == REQ_ID_READ))          ? 1'b1 : 1'b0;
  assign ciphertext_emission_received = (rx_valid & (rx_req_id == REQ_ID_EMISSION))      ? 1'b1 : 1'b0;

  // header information
  assign rx_dst_mac_addr = dst_mac_addr;
  assign rx_sec_num      = sec_num;
  assign rx_hpu_id       = hpu_id;
  assign rx_req_id       = req_id;
  assign rx_src_mac_addr = src_mac_addr;
  assign rx_size_b       = size_b;
  assign rx_iop_id       = iop_id;
  assign rx_ct_src_addr  = ct_src_addr;
  assign rx_ct_dst_addr  = ct_dst_addr;
  assign rx_header_valid = (rx_counter == 3) ? 1'b1 : 1'b0;

endmodule
