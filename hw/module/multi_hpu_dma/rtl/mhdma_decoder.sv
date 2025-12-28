// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Multi-HPU DMA reception and decoder module
// ==============================================================================================

module mhdma_decoder
  import mhdma_pkg::*;             // multi-hpu-dma
  import axi_if_shell_axil_pkg::*; // REG_DATA_W
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
  output header_t                  rx_header,
  // RX payload ---------------------------------------------------------------
  output logic [MRMAC_AXIS_W-1:0]  rx_tdata,
  output logic                     rx_tvalid,
  output logic                     rx_tlast,
  //  Statistics --------------------------------------------------------------
  output logic [REG_DATA_W-1:0]    stat_t_ce_first_to_last_pkt,
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
  logic [ETHERNET_LEN-1:0] eth_len;
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
  logic qsfp_rx_tvalid_tmp;

  always_ff @(posedge clk_mrmac)
    qsfp_rx_tvalid_tmp <= qsfp_rx_tvalid;

  assign qsfp_rx_tsop = qsfp_rx_tvalid & ~qsfp_rx_tvalid_tmp;

  logic [$clog2(ETH_LEN_MAX):0] rx_counter;
  always_ff @(posedge clk_mrmac) begin
    if (qsfp_rx_tvalid) begin
      rx_counter <= rx_counter+1;
    end else begin
      rx_counter <= 0;
    end
  end

  // FRAME 0 ------------------------------------------------------------------
  // dst_mac_addr
  //    destination mac address is not needed from the first clock cycle
  //    this register will help define if next words in receptions are valid
  logic rx_valid;
  always_ff @(posedge clk_mrmac)
    if (~resetn_mrmac) begin
      // it is relevant to reset dst_mac_addr here because we build rx_valid from it
      dst_mac_addr <= 'h0;
    end else begin
      if (qsfp_rx_tvalid & qsfp_rx_tsop)
        dst_mac_addr <= qsfp_rx_tdata_bs[H0_DST_MAC_ADDR_OFS-1:H0_SRC_OUI_OFS];
    end

  assign rx_valid = (current_hpu_mac == dst_mac_addr) ? 1'b1 : 1'b0;

  // FRAME 1 ------------------------------------------------------------------
  // src_mac_address and eth len
  always_ff @(posedge clk_mrmac) begin
    if ((qsfp_rx_tvalid) & (rx_counter == 1)) begin
        eth_len      <= qsfp_rx_tdata_bs[H1_SRC_ETH_LEN_OFS-1:16];
        src_mac_addr <= qsfp_rx_tdata_bs[H1_SRC_MAC_ADDR_OFS-1:H1_SRC_ETH_LEN_OFS];
      end
  end

  // FRAME 2 ------------------------------------------------------------------
  // req_id, hpu_id, sec_num, src_addr, dst_addr and iop_id
  always_ff @(posedge clk_mrmac) begin
    if ((qsfp_rx_tvalid) & (rx_counter == 2)) begin
      hpu_id      <= qsfp_rx_tdata_bs[H2_HPU_ID_OFS-1:H2_SEQ_NUM_OFS];
      sec_num     <= qsfp_rx_tdata_bs[H2_SEQ_NUM_OFS-1:H2_CT_SRC_ADDR_OFS];
      ct_src_addr <= qsfp_rx_tdata_bs[H2_CT_SRC_ADDR_OFS-1:H2_CT_DST_ADDR_OFS];
      ct_dst_addr <= qsfp_rx_tdata_bs[H2_CT_DST_ADDR_OFS-1:H2_IOP_ID_OFS];
      iop_id      <= qsfp_rx_tdata_bs[H2_IOP_ID_OFS-1:0];
    end
  end

  // it is mandatory to reset req_id when invalid: we build pulses around it
  always_ff @(posedge clk_mrmac) begin
    if (qsfp_rx_tvalid) begin
      if (rx_counter == 2) begin
        req_id <= qsfp_rx_tdata_bs[H2_REQ_ID_OFS-1:H2_HPU_ID_OFS];
      end
    end else begin
      req_id <= 'h0;
    end
  end

  // FRAME 3 ------------------------------------------------------------------
  // size_b
  assign size_b = ((rx_counter == 3) & rx_valid) ? qsfp_rx_tdata_bs[H3_SIZE_B_OFS-1:H3_EMPTY_OFS] : 'h0;

  // assigning output -----------------------------------------------------------------------------

  // decoding commands
  logic nack_receivedD;
  logic nr_receivedD;
  logic rr_receivedD;
  logic ce_receivedD;

  logic nack_received;
  logic nr_received;
  logic rr_received;
  logic ce_received;

  assign nack_receivedD = (rx_valid & (req_id == REQ_ID_ACK_NOTIFY_TX)) ? 1'b1 : 1'b0;
  assign nr_receivedD   = (rx_valid & (req_id == REQ_ID_NOTIFY_TX))     ? 1'b1 : 1'b0;
  assign rr_receivedD   = (rx_valid & (req_id == REQ_ID_READ))          ? 1'b1 : 1'b0;
  assign ce_receivedD   = (rx_valid & (req_id == REQ_ID_EMISSION))      ? 1'b1 : 1'b0;

  always_ff @(posedge clk_mrmac) begin
    nack_received <= nack_receivedD;
    nr_received   <= nr_receivedD;
    rr_received   <= rr_receivedD;
    ce_received   <= ce_receivedD;
  end

  assign notify_ack_received          = nack_receivedD & ~nack_received;
  assign notify_request_received      = nr_receivedD   & ~nr_received;
  assign read_request_received        = rr_receivedD   & ~rr_received;
  assign ciphertext_emission_received = ce_receivedD   & ~ce_received;

  // header information
  assign rx_header.valid        = (rx_counter == NB_WORDS_CUST_HEADER_SIZE) ? 1'b1 : 1'b0;
  assign rx_header.src_mac_addr = src_mac_addr;
  assign rx_header.seq_num      = sec_num;
  assign rx_header.hpu_id       = hpu_id;
  assign rx_header.size_b       = size_b;
  assign rx_header.iop_id       = iop_id;
  assign rx_header.src_addr     = ct_src_addr;
  assign rx_header.dst_addr     = ct_dst_addr;
  assign rx_header.req_id       = req_id;

  // payload interface to master module -----------------------------------------------------------
  always_ff @(posedge clk_mrmac)
    if (ce_received & qsfp_rx_tvalid & (qsfp_rx_tkeep_user == 'hFF) & (rx_counter>NB_WORDS_CUST_HEADER_SIZE-1))
      rx_tdata <= qsfp_rx_tdata_bs;

  always_ff @(posedge clk_mrmac) begin
    if (ce_received & qsfp_rx_tvalid & (qsfp_rx_tkeep_user == 'hFF) & (rx_counter>NB_WORDS_CUST_HEADER_SIZE-1)) begin
      rx_tvalid <= 1'b1;
    end else begin
      rx_tvalid <= 1'b0;
    end
  end

  always_ff @(posedge clk_mrmac)
    rx_tlast <= ce_received & qsfp_rx_tvalid & qsfp_rx_tlast;


  // =========================================================================================== //
  // statistics
  // =========================================================================================== //
  logic [REG_DATA_W-1:0] t_first_last_pkt;
  logic                  count_time_first_to_last;

  always_ff @(posedge clk_mrmac)begin
    if (~resetn_mrmac)begin
      count_time_first_to_last <= 1'b0;
    end else begin
      if (ce_received & (sec_num == 0) & qsfp_rx_tlast) begin
        count_time_first_to_last <= 1'b1;
      end else if (ce_received & (sec_num == NB_PACKETS_FULL) & qsfp_rx_tlast)  begin
        count_time_first_to_last <= 1'b0;
      end
    end
  end

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      t_first_last_pkt <= 'h0;
    end else begin
      if (count_time_first_to_last) begin
        t_first_last_pkt <= t_first_last_pkt + 1;
      end else begin
        t_first_last_pkt <= 'h0;
      end
    end
  end

  always_ff@(posedge clk_mrmac) begin
    if (~resetn_mrmac)begin
      stat_t_ce_first_to_last_pkt <= 'h0;
    end else begin
      if (ce_received & (sec_num == NB_PACKETS_FULL) & qsfp_rx_tlast) begin
        stat_t_ce_first_to_last_pkt <= t_first_last_pkt;
      end
    end
  end


endmodule
