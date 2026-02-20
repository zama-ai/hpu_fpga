// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Multi-HPU DMA reception and decoder module
//
// Receives raw QSFP RX AXI-Stream data, parses the custom Ethernet header word by word (h0..h3),
// pushes decoded commands into a FIFO for downstream consumption.
// For Ciphertext Emission packets, payload data is forwarded on a separate AXI-Stream like bus
//
// Latency: QSFP input to decoded command =
//  > input stage (1) + frame parsing (4) + fifo_rx_cmd (1) = 6 cycles
//
// Assumptions / Limitations:
// - No backpressure on QSFP RX input (no tready output with MRMAC configuration).
//   If the command FIFO overflows, incoming commands are silently dropped and error_fifo_rx_ovf is
//    raised (sticky until rst_errors).
// - A packet with an unrecognized req_id, registers dst_mac_addr and req_id but generates
//    no command & increments no counter.
// - Stat counters (cnt_*) are REG_DATA_W wide with no saturation. They wrap on overflow.
//
// ==============================================================================================

module mhdma_decoder
  import mhdma_pkg::*;             // multi-hpu-dma
  import axi_if_shell_axil_pkg::*; // REG_DATA_W
(
  // Ethernet fast clock interface --------------------------------------------
  input  logic                     clk_mrmac,
  input  logic                     resetn_mrmac,
  // Command interface --------------------------------------------------------
  output logic                     notify_ack_received,
  input  logic [MAC_ADDR_W-1:0]    current_hpu_mac,
  // Header information -------------------------------------------------------
  output command_t                 decoded_command,
  output logic                     decoded_command_vld,
  input  logic                     decoded_command_rdy,
  // RX payload ---------------------------------------------------------------
  output logic [MRMAC_AXIS_W-1:0]  rx_tdata_out,
  output logic                     rx_tvalid_out,
  //  Statistics --------------------------------------------------------------
  output decoder_stat_t            stat,
  input  decoder_stat_rst_t        stat_rst,
  // Error interface ----------------------------------------------------------
  output decoder_error_t           decoder_error,
  input  logic                     rst_errors,
  // QSFP system interface ----------------------------------------------------
  // == RX
  input  logic [MRMAC_AXIS_W-1:0]  qsfp_rx_tdata,
  input  logic [MRMAC_TKEEP_W-1:0] qsfp_rx_tkeep_user,
  input  logic                     qsfp_rx_tlast,
  input  logic                     qsfp_rx_tvalid
);

  // =========================================================================================== //
  // Input pipeline stage
  // =========================================================================================== //
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

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      rx_tvalid_in <= ('h0);
    end else begin
      rx_tvalid_in <= qsfp_rx_tvalid;
    end
  end

  // =========================================================================================== //
  // Packet decoder
  // =========================================================================================== //
  // Frame-by-frame field extraction from byte-swapped AXI-Stream data.
  // Frame 0 (counter==0, h0): dst_mac_addr  → used to build rx_valid
  logic [MAC_ADDR_W-1:0]   dst_mac_addr;
  // Frame 1 (counter==1, h1): src_mac_addr, eth_len
  logic [ETHERNET_LEN-1:0] eth_len;
  logic [MAC_ADDR_W-1:0]   src_mac_addr;
  // Frame 2 (counter==2, h2): req_id, hpu_id, seq_num, ct_src/dst_addr, iop_id
  logic [SEQ_NUM_W-1:0]    seq_num;
  logic [HPU_ID_W-1:0]     hpu_id;
  logic [REQ_ID_W-1:0]     req_id;
  logic [IOP_ID_W-1:0]     iop_id;
  logic [SRC_ADDR_W-1:0]   ct_src_addr;
  logic [DST_ADDR_W-1:0]   ct_dst_addr;
  // Frame 3 (counter==3, h3): rsvd, flag, mode
  logic [RSVD_W-1:0]       rsvd;
  logic [FLAG_W-1:0]       flag;
  logic [MODE_W-1:0]       mode;

  // We need to byte swap tdata in
  logic [MRMAC_AXIS_W-1:0] qsfp_rx_tdata_bs;

  assign qsfp_rx_tdata_bs = byte_swap(rx_tdata_in);

  // Overlay frame structures on byte-swapped data
  h0_frame_t h0;
  h1_frame_t h1;
  h2_frame_t h2;
  h3_frame_t h3;

  assign h0 = qsfp_rx_tdata_bs;
  assign h1 = qsfp_rx_tdata_bs;
  assign h2 = qsfp_rx_tdata_bs;
  assign h3 = qsfp_rx_tdata_bs;

  // =========================================================================================== //
  // QSFP RX
  // =========================================================================================== //
  // Word counter: tracks current frame position within a packet.
  // Increments on each valid beat, resets on tlast.
  logic [$clog2(NB_WORDS_MAX):0] rx_counter;

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

  // FRAME 0 --------------------------------------------------------------------------------------
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
        dst_mac_addr <= h0.dst_mac_addr;
      end else if (rx_tvalid_in & rx_tlast_in) begin
        dst_mac_addr <= 'h0;
      end
    end

  assign rx_valid = (current_hpu_mac == dst_mac_addr);

  // FRAME 1 --------------------------------------------------------------------------------------
  // src_mac_address and eth len
  always_ff @(posedge clk_mrmac) begin
    if ((rx_tvalid_in) & (rx_counter == 1)) begin
        eth_len      <= h1.eth_len;
        src_mac_addr <= h1.src_mac_addr;
      end
  end

  // FRAME 2 --------------------------------------------------------------------------------------
  logic notify_request_received;
  logic read_request_received;
  logic ciphertext_emission_received;
  // notify_ack_received is an output

  // req_id, hpu_id, seq_num, src_addr, dst_addr and iop_id
  always_ff @(posedge clk_mrmac) begin
    if ((rx_tvalid_in) & (rx_counter == 2)) begin
      hpu_id      <= h2.hpu_id;
      seq_num     <= h2.seq_num;
      ct_src_addr <= h2.ct_src_addr;
      ct_dst_addr <= h2.ct_dst_addr;
      iop_id      <= h2.iop_id;
    end
  end

  // it is mandatory to reset req_id when invalid: we build pulses around it
  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      req_id <= 'h0;
    end else begin
      if (rx_tvalid_in & (rx_counter == 2)) begin
        req_id <= h2.req_id;
      end else if (rx_tvalid_in & rx_tlast_in) begin
        req_id <= 'h0;
      end
    end
  end

  logic nack_receivedD;
  logic nr_receivedD;
  logic rr_receivedD;
  logic ce_receivedD;

  assign nack_receivedD = rx_valid & (req_id == REQ_ID_NOTIFY_ACK);
  assign nr_receivedD   = rx_valid & (req_id == REQ_ID_NOTIFY);
  assign rr_receivedD   = rx_valid & (req_id == REQ_ID_READ);
  assign ce_receivedD   = rx_valid & (req_id == REQ_ID_EMISSION);

  logic nack_received;
  logic nr_received;
  logic rr_received;
  logic ce_received;

  always_ff @(posedge clk_mrmac) begin
    nack_received <= nack_receivedD;
    nr_received   <= nr_receivedD;
    rr_received   <= rr_receivedD;
    ce_received   <= ce_receivedD;
  end

  always_ff @(posedge clk_mrmac) begin
    notify_ack_received          <= nack_receivedD & ~nack_received;
    notify_request_received      <= nr_receivedD   & ~nr_received;
    read_request_received        <= rr_receivedD   & ~rr_received;
    ciphertext_emission_received <= ce_receivedD   & ~ce_received;
  end


  // FRAME 3 --------------------------------------------------------------------------------------
  // There are four frames in total to account for
  // We are decoding received command at Frame 2
  // Fields (rsvd, flag, mode) are registered
  always_ff @(posedge clk_mrmac) begin
    if ((rx_tvalid_in) & (rx_counter == 3)) begin
      rsvd <= h3.h3_rsvd;
      flag <= h3.flag;
      mode <= h3.mode;
    end
  end

  logic fifo_rx_cmd_in_vld;
  logic fifo_rx_cmd_in_rdy;

  // Push into FIFO one cycle after frame 3 data is captured (NBA makes rsvd/flag/mode stable).
  // Gate with *_receivedD to only push for known command types with matching MAC.
  // (rx_counter == 3) & rx_tvalid_in is a single-cycle pulse (counter advances to 4 on the same beat).
  always_ff @(posedge clk_mrmac)
    fifo_rx_cmd_in_vld <= (rx_tvalid_in & (rx_counter == 3))
                        & (nack_receivedD | nr_receivedD | rr_receivedD | ce_receivedD);

  fifo_ram_rdy_vld # (
    .WIDTH(MAC_ADDR_W + SEQ_NUM_W + HPU_ID_W + RSVD_W + FLAG_W + MODE_W + IOP_ID_W + SRC_ADDR_W + DST_ADDR_W + REQ_ID_W),
    .DEPTH(RX_FIFO_DEPTH)
  ) fifo_rx_cmd (
    .clk         (clk_mrmac),
    .s_rst_n     (resetn_mrmac),

    .in_data     ({src_mac_addr, seq_num, hpu_id, rsvd, flag, mode, iop_id, ct_src_addr, ct_dst_addr, req_id}),
    .in_vld      (fifo_rx_cmd_in_vld),
    .in_rdy      (fifo_rx_cmd_in_rdy),

    .out_data    ({decoded_command.src_mac_addr, decoded_command.seq_num, decoded_command.hpu_id, decoded_command.rsvd, decoded_command.flag, decoded_command.mode, decoded_command.iop_id, decoded_command.src_addr, decoded_command.dst_addr, decoded_command.req_id}),
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

  // =========================================================================================== //
  // Payload interface to master module
  // =========================================================================================== //
  // CE payload forwarding: two pipe stages before output.
  // First stage captures data when ce_received is active and counter is past the custom header.
  // Second stage adds one more register for timing.
  logic [MRMAC_AXIS_W-1:0] rx_tdata_pipe;
  logic                    rx_tvalid_pipe;

  always_ff @(posedge clk_mrmac)
    if (ce_received & rx_tvalid_in & (rx_tkeep_user_in != 'h0) & (rx_counter>NB_WORDS_CUST_HEADER_SIZE-1))
      rx_tdata_pipe <= qsfp_rx_tdata_bs;

  always_ff @(posedge clk_mrmac) begin
    if (ce_received & rx_tvalid_in & (rx_tkeep_user_in != 'h0) & (rx_counter>NB_WORDS_CUST_HEADER_SIZE-1)) begin
      rx_tvalid_pipe <= 1'b1;
    end else begin
      rx_tvalid_pipe <= 1'b0;
    end
  end

  always_ff @(posedge clk_mrmac) begin
    rx_tdata_out  <= rx_tdata_pipe;
    rx_tvalid_out <= rx_tvalid_pipe;
  end

  // =========================================================================================== //
  // Errors
  // =========================================================================================== //
  assign decoder_error = error_fifo_rx_ovf;

  // =========================================================================================== //
  // Statistics
  // Note that cnt_*_received have no overflow system, only here for debugging
  // =========================================================================================== //
  // computing timing between first and last packet received on ciphertext emission
  logic [REG_DATA_W-1:0] t_first_last_pkt;
  logic                  count_time_first_to_last;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
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
    if (count_time_first_to_last) begin
      t_first_last_pkt <= t_first_last_pkt + 1;
    end else begin
      t_first_last_pkt <= 'h0;
    end
  end

  logic [REG_DATA_W-1:0] stat_t_ce_first_to_last_pkt_r;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      stat_t_ce_first_to_last_pkt_r <= 'h0;
    end else begin
      if (ce_received & (seq_num == NB_PACKETS_FULL) & rx_tlast_in) begin
        stat_t_ce_first_to_last_pkt_r <= t_first_last_pkt;
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
      if (stat_rst.cnt_notify_received) begin
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
      if (stat_rst.cnt_read_req_received) begin
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
      if (stat_rst.cnt_nack_received) begin
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
      if (stat_rst.cnt_ce_received) begin
        cnt_ce_received <= 'h0;
      end else begin
        if (ciphertext_emission_received) begin
          cnt_ce_received <= cnt_ce_received + 1;
        end
      end
    end
  end
  assign stat.t_ce_first_to_last_pkt = stat_t_ce_first_to_last_pkt_r;
  assign stat.cnt_notify_received    = cnt_notify_received;
  assign stat.cnt_read_req_received  = cnt_read_req_received;
  assign stat.cnt_nack_received      = cnt_nack_received;
  assign stat.cnt_ce_received        = cnt_ce_received;

endmodule
