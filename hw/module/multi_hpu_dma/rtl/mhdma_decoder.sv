// ================================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ------------------------------------------------------------------------------------------------
// Description  : Multi-HPU DMA reception and decoder module
//
// Receives raw QSFP RX AXI-Stream data, parses the custom Ethernet header word by word (h0..h3),
// pushes decoded commands into a FIFO for downstream consumption.
// For Ciphertext Emission packets, payload data is forwarded on a separate AXI-Stream like bus
//
// Latency: QSFP input to decoded command =
//  > input stage (1) + frame parsing (4) + fifo_rx_cmd (1) = 6 cycles
//  > streaming interface has two clock cycles latency
//
// Assumptions / Limitations:
// - No backpressure on QSFP RX input (no tready output with our MRMAC configuration).
//   This implies that Ciphertext Emission words have no backpressure and go to master with a
//    streaming interface
// - If the command FIFO overflows, incoming commands are silently dropped and error_fifo_rx_ovf is
//    raised, sticky until read (rst_errors).
// - ETH LEN is only used for packet handling outside FPGA, we ignore it here
// - A packet with an unrecognized req_id (or mismatched MAC) registers dst_mac_addr and
//    req_id but generates no command; it increments the cnt_dropped counter.
// - Stat counters (cnt_*) are REG_DATA_W wide and wrap on overflow.
//
// ================================================================================================

module mhdma_decoder
  import mhdma_pkg::*;             // multi-hpu-dma
  import axi_if_shell_axil_pkg::*; // REG_DATA_W
(
  // Ethernet fast clock interface ----------------------------------------------------------------
  input  logic                     clk_mhdma,
  input  logic                     resetn_mhdma,
  // Command interface ----------------------------------------------------------------------------
  output logic                     notify_ack_received,
  input  logic [MAC_ADDR_W-1:0]    current_hpu_mac,
  // Header information ---------------------------------------------------------------------------
  output command_t                 decoded_command,
  output logic                     decoded_command_vld,
  input  logic                     decoded_command_rdy,
  // Streaming Ciphertext payload -----------------------------------------------------------------
  output logic [MRMAC_AXIS_W-1:0]  rx_tdata_out,
  output logic                     rx_tvalid_out,
  //  Statistics ----------------------------------------------------------------------------------
  output decoder_stat_t            stat,
  input  decoder_stat_rst_t        stat_rst,
  // Error interface ------------------------------------------------------------------------------
  output decoder_error_t           decoder_error,
  input  logic                     rst_errors,
  // QSFP system interface ------------------------------------------------------------------------
  // == RX
  input  logic [MRMAC_AXIS_W-1:0]  qsfp_rx_tdata,
  input  logic [MRMAC_TKEEP_W-1:0] qsfp_rx_tkeep_user,
  input  logic                     qsfp_rx_tlast,
  input  logic                     qsfp_rx_tvalid
);

  // =========================================================================================== //
  // Localparam
  // =========================================================================================== //
  localparam int NUM_STAT_CNTS = 5;

  // =========================================================================================== //
  // Input pipeline stage
  // =========================================================================================== //
  logic [MRMAC_AXIS_W-1:0]  rx_tdata_in;
  logic                     rx_tlast_in;
  logic                     rx_tvalid_in;

  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      rx_tvalid_in <= 1'b0;
    end else begin
      rx_tvalid_in <= qsfp_rx_tvalid;
      rx_tlast_in  <= qsfp_rx_tlast;
      rx_tdata_in  <= qsfp_rx_tdata;
    end
  end

  // We need to byte swap tdata in
  logic [MRMAC_AXIS_W-1:0] qsfp_rx_tdata_bs;

  assign qsfp_rx_tdata_bs = byte_swap(rx_tdata_in);

  // =========================================================================================== //
  // Packet decoder
  // Frame-by-frame field extraction from byte-swapped AXI-Stream data.
  // =========================================================================================== //
  // Frame 0 (counter==0, h0): dst_mac_addr -> used to build rx_valid
  logic [MAC_ADDR_W-1:0]   dst_mac_addr;
  // Frame 1 (counter==1, h1): src_mac_addr, (eth_len not used)
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
  logic [$clog2(NB_WORDS_MAX)-1:0] rx_counter;

  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
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
  //    destination mac address is not needed on first clock cycle
  //    this register will help define if next words in receptions are valid
  logic rx_valid;
  always_ff @(posedge clk_mhdma)
    if (~resetn_mhdma) begin
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
  // src_mac_address
  // h1.eth_len is not used today
  always_ff @(posedge clk_mhdma) begin
    if ((rx_tvalid_in) & (rx_counter == 1)) begin
        src_mac_addr <= h1.src_mac_addr;
      end
  end

  // FRAME 2 --------------------------------------------------------------------------------------
  // Gathering req_id, hpu_id, seq_num, src_addr, dst_addr and iop_id + building *_received signals
  logic notify_request_received;
  logic read_request_received;
  logic ciphertext_emission_received;
  // notify_ack_received is an output

  always_ff @(posedge clk_mhdma) begin
    if ((rx_tvalid_in) & (rx_counter == 2)) begin
      hpu_id      <= h2.hpu_id;
      seq_num     <= h2.seq_num;
      ct_src_addr <= h2.ct_src_addr;
      ct_dst_addr <= h2.ct_dst_addr;
      iop_id      <= h2.iop_id;
    end
  end

  // it is mandatory to reset req_id when invalid: we build pulses around it
  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
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

  always_ff @(posedge clk_mhdma) begin
    nack_received <= nack_receivedD;
    nr_received   <= nr_receivedD;
    rr_received   <= rr_receivedD;
    ce_received   <= ce_receivedD;
  end

  always_ff @(posedge clk_mhdma) begin
    notify_ack_received          <= nack_receivedD & ~nack_received;
    notify_request_received      <= nr_receivedD   & ~nr_received;
    read_request_received        <= rr_receivedD   & ~rr_received;
    ciphertext_emission_received <= ce_receivedD   & ~ce_received;
  end


  // FRAME 3 --------------------------------------------------------------------------------------
  // Gathering rsvd, flag, mode.
  always_ff @(posedge clk_mhdma) begin
    if ((rx_tvalid_in) & (rx_counter == 3)) begin
      rsvd <= h3.h3_rsvd;
      flag <= h3.flag;
      mode <= h3.mode;
    end
  end

  command_t fifo_rx_cmd_in_data;
  logic     fifo_rx_cmd_in_vld;
  logic     fifo_rx_cmd_in_rdy;

  // Push into FIFO one cycle after frame 3 data is captured.
  // Gate with *_receivedD to only push for known command types with matching MAC address.
  always_ff @(posedge clk_mhdma)
    fifo_rx_cmd_in_vld <= (rx_tvalid_in & (rx_counter == 3)) & (nack_receivedD | nr_receivedD | rr_receivedD | ce_receivedD);

  assign fifo_rx_cmd_in_data = {src_mac_addr, seq_num, hpu_id, rsvd, flag, mode, req_id, iop_id, ct_src_addr, ct_dst_addr};

  fifo_ram_rdy_vld # (
    .WIDTH       ($bits(command_t)    ),
    .DEPTH       (RX_FIFO_DEPTH       )
  ) fifo_rx_cmd (
    .clk         (clk_mhdma           ),
    .s_rst_n     (resetn_mhdma        ),

    .in_data     (fifo_rx_cmd_in_data ),
    .in_vld      (fifo_rx_cmd_in_vld  ),
    .in_rdy      (fifo_rx_cmd_in_rdy  ),

    .out_data    (decoded_command     ),
    .out_vld     (decoded_command_vld ),
    .out_rdy     (decoded_command_rdy ),

    .almost_full (/*     UNUSED     */)
  );

  // Building sticky error bit on fifo_rx_cmd overflow
  logic error_fifo_rx_ovf;

  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
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
  // Ciphertext Emission forwarding: two pipe stages before output.
  // First stage captures data when ce_received is active and counter is past the custom header.
  // Second stage adds one more register for timing.
  logic [MRMAC_AXIS_W-1:0] rx_tdata_pipe;
  logic                    rx_tvalid_pipe;

  always_ff @(posedge clk_mhdma)
    if (ce_received & rx_tvalid_in & (rx_counter>NB_WORDS_CUST_HEADER_SIZE-1))
      rx_tdata_pipe <= qsfp_rx_tdata_bs;

  always_ff @(posedge clk_mhdma) begin
    if (ce_received & rx_tvalid_in & (rx_counter>NB_WORDS_CUST_HEADER_SIZE-1)) begin
      rx_tvalid_pipe <= 1'b1;
    end else begin
      rx_tvalid_pipe <= 1'b0;
    end
  end

  always_ff @(posedge clk_mhdma) begin
    rx_tdata_out  <= rx_tdata_pipe;
    rx_tvalid_out <= rx_tvalid_pipe;
  end

  // =========================================================================================== //
  // Errors
  // =========================================================================================== //
  assign decoder_error = error_fifo_rx_ovf;

  // =========================================================================================== //
  // Statistics
  // Note that cnt_*_received have no overflow system: only here for debugging
  // =========================================================================================== //
  // computing timing between first and last packet received on ciphertext emission
  logic [REG_DATA_W-1:0] t_first_last_pkt;
  logic                  count_time_first_to_last;

  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      count_time_first_to_last <= 1'b0;
    end else begin
      if (ce_received & (seq_num == 0) & rx_tlast_in) begin
        count_time_first_to_last <= 1'b1;
      end else if (ce_received & (seq_num == NB_PACKETS_FULL) & rx_tlast_in)  begin
        count_time_first_to_last <= 1'b0;
      end
    end
  end

  always_ff @(posedge clk_mhdma) begin
    if (count_time_first_to_last) begin
      t_first_last_pkt <= t_first_last_pkt + 1;
    end else begin
      t_first_last_pkt <= 'h0;
    end
  end

  logic [REG_DATA_W-1:0] stat_t_ce_first_to_last_pkt_r;

  always_ff @(posedge clk_mhdma) begin
    if (~resetn_mhdma) begin
      stat_t_ce_first_to_last_pkt_r <= 'h0;
    end else begin
      if (ce_received & (seq_num == NB_PACKETS_FULL) & rx_tlast_in) begin
        stat_t_ce_first_to_last_pkt_r <= t_first_last_pkt;
      end
    end
  end

  // Dropped packet detection: packet not recognized (wrong MAC or unknown opcode)
  // req_id is captured at counter==2 (always_ff), so *_receivedD is first valid at counter==3
  // Check exactly at counter==3: after that *_receivedD are stable levels, not pulses
  logic pkt_dropped;
  assign pkt_dropped = rx_tvalid_in & (rx_counter == 3)
                     & ~(nack_receivedD | nr_receivedD | rr_receivedD | ce_receivedD);

  // counters on received commands
  logic [NUM_STAT_CNTS-1:0][REG_DATA_W-1:0] stat_cnt;
  logic [NUM_STAT_CNTS-1:0]                 stat_cnt_inc;
  logic [NUM_STAT_CNTS-1:0]                 stat_cnt_rst;

  assign stat_cnt_inc = {
    pkt_dropped,
    ciphertext_emission_received,
    notify_ack_received,
    read_request_received,
    notify_request_received
  };

  assign stat_cnt_rst = {
    stat_rst.cnt_dropped,
    stat_rst.cnt_ce_received,
    stat_rst.cnt_nack_received,
    stat_rst.cnt_read_req_received,
    stat_rst.cnt_notify_received
  };

  for (genvar gen_i = 0; gen_i < NUM_STAT_CNTS; gen_i++) begin : gen_stat_cnt
    always_ff @(posedge clk_mhdma) begin
      if (~resetn_mhdma) begin
        stat_cnt[gen_i] <= 'h0;
      end else begin
        if (stat_cnt_rst[gen_i]) begin
          stat_cnt[gen_i] <= 'h0;
        end else if (stat_cnt_inc[gen_i]) begin
          stat_cnt[gen_i] <= stat_cnt[gen_i] + 1;
        end
      end
    end
  end

  assign stat.t_ce_first_to_last_pkt = stat_t_ce_first_to_last_pkt_r;
  assign stat.cnt_notify_received    = stat_cnt[0];
  assign stat.cnt_read_req_received  = stat_cnt[1];
  assign stat.cnt_nack_received      = stat_cnt[2];
  assign stat.cnt_ce_received        = stat_cnt[3];
  assign stat.cnt_dropped            = stat_cnt[4];

endmodule
