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
  input  logic [MAC_ADDR_W-1:0]    current_hpu_mac,
  // Header information -------------------------------------------------------
  output command_t                 decoded_command,
  output logic                     decoded_command_vld,
  input  logic                     decoded_command_rdy,
  // RX payload ---------------------------------------------------------------
  output logic [MRMAC_AXIS_W-1:0]  rx_tdata_out,
  output logic                     rx_tvalid_out,
  //  Statistics --------------------------------------------------------------
  output logic [REG_DATA_W-1:0]    stat_t_ce_first_to_last_pkt,
  // number of received events
  output logic [REG_DATA_W-1:0]    stat_cnt_nack_received,
  output logic [REG_DATA_W-1:0]    stat_cnt_notify_received,
  output logic [REG_DATA_W-1:0]    stat_cnt_read_req_received,
  output logic [REG_DATA_W-1:0]    stat_cnt_ce_received,
  // rst
  input  logic                     rst_cnt_nack_received,
  input  logic                     rst_cnt_notify_received,
  input  logic                     rst_cnt_read_req_received,
  input  logic                     rst_cnt_ce_received,
  // Error interface ----------------------------------------------------------
  output decoder_error_t          decoder_error,
  input  logic                    rst_errors,
  // QSFP system interface ----------------------------------------------------
  // == RX
  input  logic [MRMAC_AXIS_W-1:0]  qsfp_rx_tdata,
  input  logic [MRMAC_TKEEP_W-1:0] qsfp_rx_tkeep_user,
  input  logic                     qsfp_rx_tlast,
  input  logic                     qsfp_rx_tvalid
);

  // ==============================================================================================
  // Temp axi4-stream inputs
  // ==============================================================================================
  logic [MRMAC_AXIS_W-1:0]  rx_tdata_in;
  logic [MRMAC_TKEEP_W-1:0] rx_tkeep_user_in;
  logic                     rx_tlast_in;
  logic                     rx_tvalid_in;

  always_ff @(posedge clk_mrmac)
    rx_tdata_in <= qsfp_rx_tdata;

  always_ff @(posedge clk_mrmac)
    rx_tkeep_user_in <= qsfp_rx_tkeep_user;

  always_ff @(posedge clk_mrmac)
    rx_tlast_in <= qsfp_rx_tlast;

  always_ff @(posedge clk_mrmac)
    rx_tvalid_in <= qsfp_rx_tvalid;

  // ==============================================================================================
  // packet decoder
  // ==============================================================================================
  // On RX lanes, should know as soon as possible what type of packets I should see
  // First frame I can check that the destination address is me
  logic [MAC_ADDR_W-1:0] dst_mac_addr;
  logic [ETHERNET_LEN-1:0] eth_len;
  // Second frame I will know who is the sender, request ID, seq num
  logic [SEC_NUM_W-1:0]  seq_num;
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
  assign qsfp_rx_tdata_bs = byte_swap(rx_tdata_in);

  // =========================================================================================== //
  // QSFP RX
  // =========================================================================================== //
  // We must gather RX data as soon as possible and redirect commands into their respective
  // command queue or signal.
  // - ACK Notify TX is only a reception signal     : ntx_ack
  // - Notify RX goes to respective queue           : NRXQ
  // - Read request goes to write fifo to go to HBM : RRFIFO
  // - Ciphertext Emission goes to queue            : CEQ
  logic [$clog2(ETH_LEN_MAX):0] rx_counter;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      rx_counter <= 0;
    end else begin
      if (rx_tvalid_in & ~rx_tlast_in) begin
        rx_counter <= rx_counter + 1;
      end else if (rx_tvalid_in & rx_tlast_in) begin
        rx_counter <= 0;
      end
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
      if (rx_tvalid_in & (rx_counter == 0)) begin
        dst_mac_addr <= qsfp_rx_tdata_bs[H0_DST_MAC_ADDR_OFS-1:H0_SRC_OUI_OFS];
      end else if (rx_tvalid_in & rx_tlast_in) begin
        dst_mac_addr <= 'h0;
      end
    end

  assign rx_valid = (current_hpu_mac == dst_mac_addr);

  // FRAME 1 ------------------------------------------------------------------
  // src_mac_address and eth len
  always_ff @(posedge clk_mrmac) begin
    if ((rx_tvalid_in) & (rx_counter == 1)) begin
        eth_len      <= qsfp_rx_tdata_bs[H1_SRC_ETH_LEN_OFS-1:16];
        src_mac_addr <= qsfp_rx_tdata_bs[H1_SRC_MAC_ADDR_OFS-1:H1_SRC_ETH_LEN_OFS];
      end
  end

  // FRAME 2 ------------------------------------------------------------------
  // req_id, hpu_id, seq_num, src_addr, dst_addr and iop_id
  always_ff @(posedge clk_mrmac) begin
    if ((rx_tvalid_in) & (rx_counter == 2)) begin
      hpu_id      <= qsfp_rx_tdata_bs[H2_HPU_ID_OFS-1:H2_SEQ_NUM_OFS];
      seq_num     <= qsfp_rx_tdata_bs[H2_SEQ_NUM_OFS-1:H2_CT_SRC_ADDR_OFS];
      ct_src_addr <= qsfp_rx_tdata_bs[H2_CT_SRC_ADDR_OFS-1:H2_CT_DST_ADDR_OFS];
      ct_dst_addr <= qsfp_rx_tdata_bs[H2_CT_DST_ADDR_OFS-1:H2_IOP_ID_OFS];
      iop_id      <= qsfp_rx_tdata_bs[H2_IOP_ID_OFS-1:0];
    end
  end

  // it is mandatory to reset req_id when invalid: we build pulses around it
  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      req_id <= 'h0;
    end else begin
      if (rx_tvalid_in & (rx_counter == 2)) begin
        req_id <= qsfp_rx_tdata_bs[H2_REQ_ID_OFS-1:H2_HPU_ID_OFS];
      end else if (rx_tvalid_in & rx_tlast_in) begin
        req_id <= 'h0;
      end
    end
  end

  // FRAME 3 ------------------------------------------------------------------
  // size_b
  assign size_b = ((rx_counter == 3) & rx_valid) ? qsfp_rx_tdata_bs[H3_SIZE_B_OFS-1:H3_EMPTY_OFS] : 'h0;

  // assigning output -----------------------------------------------------------------------------
  logic nack_receivedD;
  logic nr_receivedD;
  logic rr_receivedD;
  logic ce_receivedD;

  logic nack_received;
  logic nr_received;
  logic rr_received;
  logic ce_received;

  assign nack_receivedD = rx_valid & (req_id == REQ_ID_NOTIFY_ACK);
  assign nr_receivedD   = rx_valid & (req_id == REQ_ID_NOTIFY);
  assign rr_receivedD   = rx_valid & (req_id == REQ_ID_READ);
  assign ce_receivedD   = rx_valid & (req_id == REQ_ID_EMISSION);

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

  logic fifo_rx_cmd_in_vld;
  logic fifo_rx_cmd_in_rdy;

  assign fifo_rx_cmd_in_vld = notify_ack_received | notify_request_received | read_request_received | ciphertext_emission_received;

  fifo_ram_rdy_vld # (
    .WIDTH(MAC_ADDR_W + SEC_NUM_W + HPU_ID_W + SIZE_B_W + IOP_ID_W + SRC_ADDR_W + DST_ADDR_W + REQ_ID_W),
    .DEPTH(RX_FIFO_DEPTH)
  ) fifo_rx_cmd (
    .clk         (clk_mrmac          ),
    .s_rst_n     (resetn_mrmac       ),

    .in_data     ({src_mac_addr, seq_num, hpu_id, size_b, iop_id, ct_src_addr, ct_dst_addr, req_id}),
    .in_vld      (fifo_rx_cmd_in_vld),
    .in_rdy      (fifo_rx_cmd_in_rdy),

    .out_data    ({decoded_command.src_mac_addr, decoded_command.seq_num, decoded_command.hpu_id, decoded_command.size_b, decoded_command.iop_id, decoded_command.src_addr, decoded_command.dst_addr, decoded_command.req_id}),
    .out_vld     (decoded_command_vld),
    .out_rdy     (decoded_command_rdy),

    .almost_full (/* UNUSED */)
  );

  logic error_fifo_rx_ovf;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      error_fifo_rx_ovf <= 1'b0;
    end else begin
      if (rst_errors) begin
        error_fifo_rx_ovf <= 1'b0;
      end else begin
        if (fifo_rx_cmd_in_vld & ~fifo_rx_cmd_in_rdy) begin
          error_fifo_rx_ovf <= 1'b1;
        end
      end
    end
  end

  // payload interface to master module -----------------------------------------------------------
  always_ff @(posedge clk_mrmac)
    if (ce_received & rx_tvalid_in & (rx_tkeep_user_in != 'h0) & (rx_counter>NB_WORDS_CUST_HEADER_SIZE-1))
      rx_tdata_out <= qsfp_rx_tdata_bs;

  always_ff @(posedge clk_mrmac) begin
    if (ce_received & rx_tvalid_in & (rx_tkeep_user_in != 'h0) & (rx_counter>NB_WORDS_CUST_HEADER_SIZE-1)) begin
      rx_tvalid_out <= 1'b1;
    end else begin
      rx_tvalid_out <= 1'b0;
    end
  end

  // =========================================================================================== //
  // Errors
  // =========================================================================================== //
  assign decoder_error = error_fifo_rx_ovf;

  // =========================================================================================== //
  // statistics
  // =========================================================================================== //
  // computing timing between first and last packet received on ciphertext emission
  logic [REG_DATA_W-1:0] t_first_last_pkt;
  logic                  count_time_first_to_last;

  always_ff @(posedge clk_mrmac)begin
    if (~resetn_mrmac)begin
      count_time_first_to_last <= 1'b0;
    end else begin
      if (ce_received & (seq_num == 0) & rx_tlast_in) begin
        count_time_first_to_last <= 1'b1;
      end else if (ce_received & (seq_num == NB_PACKETS_FULL) & rx_tlast_in)  begin
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
      if (ce_received & (seq_num == NB_PACKETS_FULL) & rx_tlast_in) begin
        stat_t_ce_first_to_last_pkt <= t_first_last_pkt;
      end
    end
  end

  // counters on received commands
  logic [REG_DATA_W-1:0] cnt_notify_received;
  logic [REG_DATA_W-1:0] cnt_read_req_received;
  logic [REG_DATA_W-1:0] cnt_nack_received;
  logic [REG_DATA_W-1:0] cnt_ce_received;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      cnt_notify_received <= 'h0;
    end else begin
      if (rst_cnt_notify_received) begin
        cnt_notify_received <= 'h0;
      end else begin
        if (notify_request_received) begin
          cnt_notify_received <= cnt_notify_received + 1;
        end
      end
    end
  end
  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      cnt_read_req_received <= 'h0;
    end else begin
      if (rst_cnt_read_req_received) begin
        cnt_read_req_received <= 'h0;
      end else begin
        if (read_request_received) begin
          cnt_read_req_received <= cnt_read_req_received + 1;
        end
      end
    end
  end
  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      cnt_nack_received <= 'h0;
    end else begin
      if (rst_cnt_nack_received) begin
      cnt_nack_received <= 'h0;
      end else begin
        if (notify_ack_received) begin
          cnt_nack_received <= cnt_nack_received + 1;
        end
      end
    end
  end
  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      cnt_ce_received <= 'h0;
    end else begin
      if (rst_cnt_ce_received) begin
        cnt_ce_received <= 'h0;
      end else begin
        if (ciphertext_emission_received) begin
          cnt_ce_received <= cnt_ce_received + 1;
        end
      end
    end
  end
  assign stat_cnt_notify_received   = cnt_notify_received;
  assign stat_cnt_read_req_received = cnt_read_req_received;
  assign stat_cnt_nack_received     = cnt_nack_received;
  assign stat_cnt_ce_received       = cnt_ce_received;

endmodule
