// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Multi-HPU DMA formatter or TX module for QSFP lane
// ==============================================================================================

module mhdma_formatter
  import mhdma_pkg::*;
#() (
  // Ethernet fast clock interface --------------------------------------------
  input  logic                                      clk_mrmac,
  input  logic                                      resetn_mrmac,
  // bridge interface ---------------------------------------------------------
  input  logic [NB_MAX_HPU-1:0][    MAC_ADDR_W-1:0] hpu_mac_table,
  input  logic                 [      HPU_ID_W-1:0] current_hpu_id,
  input  logic                 [    MAC_ADDR_W-1:0] current_hpu_mac,
  // Command interface --------------------------------------------------------
  output logic                                      ct_emission_allowed,
  output logic                                      notify_ack_allowed,
  output logic                                      read_request_allowed,
  output logic                                      notify_request_allowed,

  input  logic                                      new_ct_emission_request_pending,
  input  logic                                      new_notify_ack_pending,
  input  logic                                      new_read_request_pending,
  input  logic                                      new_notify_request_pending,

  input  logic                                      ct_emission_all_packets_received,
  input  logic                                      cerx_reception_ready,

  // master interface ---------------------------------------------------------
  input  header_t                                   format_header,
  input  logic                                      retry_notify,
  input  logic                                      retry_read_request,
  // statistics ---------------------------------------------------------------
  // register
  output logic [2:0]                                stat_fsm_formatter,
  // slave interface ----------------------------------------------------------
  input  logic                 [     NRX_WIDTH-1:0] nrx_cmd_payload,
  input  logic                                      nrx_cmd_valid,
  output logic                                      notify_ack_sent,
  input  logic                 [     CEH_WIDTH-1:0] ce_header_payload,
  input  logic                 [  MRMAC_AXIS_W-1:0] ce_payload,
  output logic                                      ce_ready,
  input  logic                                      ce_valid,
  // QSFP TX interface --------------------------------------------------------
  output logic                 [  MRMAC_AXIS_W-1:0] qsfp_tx_tdata,
  output logic                 [ MRMAC_TKEEP_W-1:0] qsfp_tx_tkeep_user,
  output logic                                      qsfp_tx_tlast,
  output logic                                      qsfp_tx_tvalid,
  input  logic                                      qsfp_tx_tready
);

  // =========================================================================================== //
  // Localparam
  // =========================================================================================== //
  localparam int NB_WORDS_FULL    = NB_WORDS_CUST_HEADER_SIZE+NB_WORDS_PAYLOAD;
  localparam int NB_WORDS_PARTIAL = NB_WORDS_LAST_PACKET+NB_WORDS_CUST_HEADER_SIZE;

  // =========================================================================================== //
  // tmp
  // =========================================================================================== //
  // this register is needed to ease timing
  logic [NB_MAX_HPU-1:0][MAC_ADDR_W-1:0] hpu_mac_table_tmp;

  always_ff @(posedge clk_mrmac)
    hpu_mac_table_tmp <= hpu_mac_table;

  header_t prev_format_header;

  always_ff @(posedge clk_mrmac)
    if (format_header.valid)
      prev_format_header <= format_header;

  // =========================================================================================== //
  // Building headers
  // =========================================================================================== //
  // control --------------------------------------------------------------------------------------
  // we are sending a request on qsfp lane when we have a pulse on header start-of-packet
  // deasserting this request when we hit enough words on the counter
  logic header_sop;                    // pulse
  // to simplify notations we define each cases as :
  logic stop_sending_small_packet;      // notify / notify-ack / read-request
  logic stop_sending_ce_full_frame;    // ciphertext-emission: when we send ETH_NB_BYTES_PAYLOAD
  logic stop_sending_ce_partial_frame; // ciphertext-emission: when we send LAST_PACKET_BYTE_SIZE
  logic end_of_packet;                 // pulse of all stops
  logic okay_to_send_request;          // level between start of / end of packet
  logic small_packet;                  // level of a small packet (notify & ack + read request)

  logic tx_header_last; // last header word
  logic tx_small_last;  // last word of a small packet
  logic tx_last_word;   // pulse on last word

  logic [$clog2(NB_WORDS_MAX)+1:0] tx_cnt;
  logic                            tx_last;
  logic                            tx_valid;
  logic [        MRMAC_AXIS_W-1:0] tx_data;
  logic [        MRMAC_AXIS_W-1:0] tx_header;
  // ce -------------------------------------------------------------------------------------------
  // During CE we need to increment seq_num for each packet sent
  // For the arbiter we need the information to release the fsm that all have been sent
  logic [SEQ_NUM_W-1:0] ce_seq_num;
  // we need to build header and stall ciphertext arrial until we are ready
  logic                 ce_first_header;      // level: up for first packet header (used for tx & backpressure)
  logic                 ce_first_header_sent; // level: up when first packet header has been sent
  logic                 ce_last_packet;       // level: up when last packet is transmitting
  logic                 ce_all_packets_transmitted;
  logic                 ce_end_of_packet;   // pulse: last word of last packet
  logic                 ce_start_of_header; // pulse: header transmission for all packets
  logic                 ce_start_emission;  // pulse: start of first header transmission
  logic                 ce_sop_header;      // pulse: start-of headers between packets
  // notify ack -----------------------------------------------------------------------------------
  logic [SRC_ADDR_W-1:0] nack_src_addr;
  logic [  HPU_ID_W-1:0] nack_hpu_id;
  logic [  IOP_ID_W-1:0] nack_iop_id;
  logic                  notify_ack_allowed_reg;
  logic                  notify_ack_pulse;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      small_packet <= 1'b0;
    end else begin
      small_packet <= read_request_allowed | notify_request_allowed | notify_ack_allowed;
    end
  end

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      tx_cnt <= 'h0;
    end else begin
      if (okay_to_send_request & ~end_of_packet & qsfp_tx_tready) begin
        tx_cnt <= tx_cnt+1;
      end else begin
        tx_cnt <= 'h0;
      end
    end
  end

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      okay_to_send_request <= 1'b0;
    end else begin
      if (header_sop) begin
        okay_to_send_request <= 1'b1;
      end else if (end_of_packet) begin
        okay_to_send_request <= 1'b0;
      end
    end
  end

  // we have to trigger signal one cycle earlier to have okay_to_send_request on time
  assign stop_sending_small_packet     = (tx_cnt == NB_WORDS_MIN)      & small_packet;
  assign stop_sending_ce_full_frame    = (tx_cnt == NB_WORDS_FULL)     & ct_emission_allowed;
  assign stop_sending_ce_partial_frame = (tx_cnt == (NB_WORDS_PARTIAL) & ce_last_packet);

  assign end_of_packet = stop_sending_small_packet | stop_sending_ce_full_frame | stop_sending_ce_partial_frame;

  assign tx_small_last  = (tx_cnt == NB_WORDS_MIN);
  assign tx_header_last = (tx_cnt == NB_WORDS_CUST_HEADER_SIZE);
  assign tx_last_word   = (ct_emission_allowed & ~ce_last_packet) ? (tx_cnt == NB_WORDS_FULL) : (tx_cnt == NB_WORDS_PARTIAL);

  assign header_sop = format_header.valid | notify_ack_pulse | ce_start_of_header | retry_notify;

  // =========================================================================================== //
  // Ciphertext Emission (CE)
  // =========================================================================================== //
  assign ce_start_of_header = ce_start_emission | ce_sop_header;
  assign ce_end_of_packet   = (ce_seq_num == NB_PACKETS_FULL) & qsfp_tx_tlast;
  assign ce_last_packet     = (ce_seq_num == NB_PACKETS_FULL) & ct_emission_allowed;

  always_ff @(posedge clk_mrmac) begin
    if(~resetn_mrmac) begin
      ce_first_header <= 1'b0;
    end else begin
      if (tx_header_last) begin
        ce_first_header <= 1'b0;
      end else if (ce_start_emission) begin
        ce_first_header <= 1'b1;
      end
    end
  end

  // decoding header payload --------------------------------------------------
  // header is propagated well before we receive any data on fifo tx
  logic [ CEH_WIDTH-1:0] ce_header_payload_tmp;
  logic [DST_ADDR_W-1:0] ce_dst_addr;
  logic [SRC_ADDR_W-1:0] ce_src_addr;
  logic [  SIZE_B_W-1:0] ce_size_b;
  logic [  HPU_ID_W-1:0] ce_hpu_id;
  logic [  IOP_ID_W-1:0] ce_iop_id;
  logic [MAC_ADDR_W-1:0] ce_dst_mac_addr;

  always_ff @(posedge clk_mrmac)
    ce_header_payload_tmp <= ce_header_payload;

  assign ce_dst_mac_addr = ce_header_payload_tmp[CEH_DST_MAC_ADDR_OFS-1:CEH_IOP_ID_OFS];
  assign ce_iop_id       = ce_header_payload_tmp[CEH_IOP_ID_OFS-1:CEH_HPU_ID_OFS];
  assign ce_hpu_id       = ce_header_payload_tmp[CEH_HPU_ID_OFS-1:CEH_SIZE_B_OFS];
  assign ce_size_b       = ce_header_payload_tmp[CEH_SIZE_B_OFS-1:CEH_DST_ADDR_OFS];
  assign ce_dst_addr     = ce_header_payload_tmp[CEH_DST_ADDR_OFS-1:CEH_SRC_ADDR_OFS];
  assign ce_src_addr     = ce_header_payload_tmp[CEH_SRC_ADDR_OFS-1:0];

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      ce_seq_num <= 'h0;
    end else begin
      if (ce_sop_header) begin
        ce_seq_num <= ce_seq_num+1;
      end else if (ce_end_of_packet) begin
        ce_seq_num <= 'h0;
      end
    end
  end

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      ce_first_header_sent <= 1'b0;
    end else begin
      if (ce_first_header & tx_header_last) begin
        ce_first_header_sent <= 1'b1;
      end else if (ce_end_of_packet) begin
        ce_first_header_sent <= 1'b0;
      end
    end
  end

  assign ce_start_emission = (ce_seq_num == 0) & (ce_valid & ~ce_ready) & ~ce_first_header_sent;

  // =========================================================================================== //
  // Notify ACK (NACK)
  // =========================================================================================== //
  always_ff @(posedge clk_mrmac) begin
    if (nrx_cmd_valid) begin
      nack_src_addr <= nrx_cmd_payload[NRX_SRC_ADDR_OFS-1:NRX_HPU_ID_OFS];
      nack_hpu_id   <= nrx_cmd_payload[NRX_HPU_ID_OFS-1:NRX_IOP_ID_OFS];
      nack_iop_id   <= nrx_cmd_payload[NRX_IOP_ID_OFS-1:0];
    end
  end

  // we need a pulse to latter construct header
  always_ff @(posedge clk_mrmac)
    notify_ack_allowed_reg <= notify_ack_allowed;

  assign notify_ack_pulse = notify_ack_allowed & ~notify_ack_allowed_reg;

  // =========================================================================================== //
  // Cycle by cycle construction
  // =========================================================================================== //
  logic [  MAC_ADDR_W-1:0] header_target_hpu_mac_addr;
  logic [ETHERNET_LEN-1:0] header_eth_len;
  logic [   SEQ_NUM_W-1:0] header_seq_num;
  logic [  DST_ADDR_W-1:0] header_dst_addr;
  logic [  SRC_ADDR_W-1:0] header_src_addr;
  logic [    SIZE_B_W-1:0] header_size_b;
  logic [    REQ_ID_W-1:0] header_req_id;
  logic [    IOP_ID_W-1:0] header_iop_id;

  // header assignation depending on request
  always_ff @(posedge clk_mrmac) begin : prc_header_gen
    if (format_header.valid) begin
      header_target_hpu_mac_addr <= hpu_mac_table_tmp[format_header.hpu_id];
      header_req_id              <= format_header.req_id;
      header_src_addr            <= format_header.src_addr;
      header_dst_addr            <= format_header.dst_addr;
      header_iop_id              <= format_header.iop_id;
    end else if (retry_notify) begin
      header_target_hpu_mac_addr <=  hpu_mac_table_tmp[prev_format_header.hpu_id];
      header_req_id              <=  prev_format_header.req_id;
      header_src_addr            <=  prev_format_header.src_addr;
      header_dst_addr            <=  prev_format_header.dst_addr;
      header_iop_id              <=  prev_format_header.iop_id;
    end else if (notify_ack_pulse) begin
      header_target_hpu_mac_addr <= hpu_mac_table_tmp[nack_hpu_id];
      header_req_id              <= REQ_ID_ACK_NOTIFY_TX;
      header_src_addr            <= nack_src_addr;
      header_dst_addr            <= 'h0;
      header_iop_id              <= nack_iop_id;
    end else if (ce_valid) begin
      header_target_hpu_mac_addr <= ce_dst_mac_addr;
      header_req_id              <= REQ_ID_EMISSION;
      header_src_addr            <= ce_src_addr;
      header_dst_addr            <= ce_dst_addr;
      header_iop_id              <= ce_iop_id;
    end
  end

  always_ff @(posedge clk_mrmac) begin : prc_header_ethernet_len
    if (small_packet) begin
      header_eth_len <= ETH_LEN_MIN;
    end else if (ce_last_packet) begin
      header_eth_len <= ETH_LEN_LAST_PKT;
    end else begin
      header_eth_len <= ETH_LEN_MAX;
    end
  end

  always_ff @(posedge clk_mrmac) begin : prc_header_ce
    if (ct_emission_allowed) begin
      header_seq_num <= ce_seq_num;
      header_size_b  <= ce_size_b;
    end else begin
      header_seq_num <= 'h0;
      header_size_b  <= 'h0;
    end
  end

  always_comb begin
    case (tx_cnt)
      'h1 :
        tx_header = {MAC_OUI, header_target_hpu_mac_addr, MAC_OUI[MAC_OUI_W-1:8]};
      'h2 :
        tx_header = {MAC_OUI[7:0], current_hpu_mac, header_eth_len, LLC_DSAP, LLC_SSAP};
      'h3 :
        tx_header = {LLC_CTRL, header_req_id, current_hpu_id, header_seq_num, header_src_addr, header_dst_addr, header_iop_id};
      'h4 :
        tx_header = {header_size_b, 56'h0};
      default:
        tx_header = 'h0;
    endcase
  end

  // tkeep ----------------------------------------------------------------------------------------
  logic [$clog2(MRMAC_AXIS_W/8)-1:0] last_word_bytes;
  logic [      MRMAC_AXIS_W/8-1:0]   tx_byte_enable;
  logic [      MRMAC_AXIS_W/8-1:0]   tx_byte_enable_d;

  always_comb begin
    case (last_word_bytes)
      'h0 :
        tx_byte_enable_d <= 8'hFF;
      'h1 :
        tx_byte_enable_d <= 8'h01;
      'h2 :
        tx_byte_enable_d <= 8'h03;
      'h3 :
        tx_byte_enable_d <= 8'h07;
      'h4 :
        tx_byte_enable_d <= 8'h0F;
      'h5 :
        tx_byte_enable_d <= 8'h1F;
      'h6 :
        tx_byte_enable_d <= 8'h3F;
      'h7 :
        tx_byte_enable_d <= 8'h7F;
      default :
        tx_byte_enable_d <= 8'h0;
    endcase
  end

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      tx_byte_enable <= 8'h00;
    end else begin
      if (okay_to_send_request & qsfp_tx_tready) begin
        if ((tx_cnt == 0) | ~small_packet)
          tx_byte_enable <= 8'hFF;
        else if (small_packet && (tx_cnt == (NB_WORDS_MIN-1)) )
          tx_byte_enable <= tx_byte_enable_d;
        else if (tx_last)
          tx_byte_enable <= 8'h00;
      end
    end
  end

  assign last_word_bytes = (ETH_NB_BYTES_HEADER + header_eth_len) & {$clog2(MRMAC_AXIS_W/8){1'b1}};

  // =========================================================================================== //
  // Building packets
  // =========================================================================================== //
  // Ciphertext emission --------------------------------------------------------------------------
  // While receiving data, we must stall the coefficients arrival after NB_WORDS_PAYLOAD words
  // We know that we want to send ETH_NB_BYTES_PAYLOAD bytes per payload
  // We should send NB_PACKETS_FULL packets and last one is of size LAST_PACKET_BYTE_SIZE
  // LAST_PACKET_BYTE_SIZE must be greater than minimum (ETH_NB_BYTES_MIN=64)

  // How many words did we receive yet ?
  logic [$clog2(NB_WORDS_PAYLOAD):0] ce_word_counter;
  logic                              ce_word_cnt_reset;

  // we need to stall words comming from ciphertext emission to build headers
  logic ce_stalling;             // level: up when we need to send header between packets
  logic ce_stalling_last_packet; // level: up when we need to fill last packet by zeros
  logic ce_header;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      ce_word_counter <= 'h0;
    end else begin
      if (ce_valid & ce_ready) begin
        if (ce_word_counter == NB_WORDS_PAYLOAD-1) begin
          ce_word_counter <= 'h0;
        end else begin
          ce_word_counter <= ce_word_counter + 1;
        end
      end else if (ce_word_cnt_reset) begin
        ce_word_counter <= 'h0;
      end
    end
  end

  always_ff @(posedge clk_mrmac)
    ce_word_cnt_reset <= ce_all_packets_transmitted;

  // we should stall the emission of coefficents after we have to correct number of words
  // we should unstall when header has left
  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      ce_stalling <= 1'b0;
    end else begin
      if (tx_cnt == NB_WORDS_FULL) begin
        ce_stalling <= 1'b1;
      end else if (tx_header_last) begin
        ce_stalling <= 1'b0;
      end
    end
  end

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      ce_stalling_last_packet <= 1'b0;
    end else begin
      if (ce_last_packet & (ce_word_counter == NB_WORDS_LAST_PACKET_USEFULL)) begin
        ce_stalling_last_packet <= 1'b1;
      end else begin
        ce_stalling_last_packet <= 1'b0;
      end
    end
  end

  // new header pulse
  logic ce_stalling_tmp;
  // to define if we have a new header to send we can just do a positive edge detection
  always_ff @(posedge clk_mrmac)
    ce_stalling_tmp <= ce_stalling;

  assign ce_sop_header = ce_stalling & ~ce_stalling_tmp;

  // level active when we have headers on ciphertext emission
  assign ce_header = tx_valid &  (ce_first_header | ce_stalling);

  // backpressure over ciphertext coefficients
  // active
  //    - when we are in the correct state &
  //    - when the first header is not startin to be propagated &
  //    - qsfp tx is ready &
  //    - we don't need to stall between packets for sending headers
  assign ce_ready = ct_emission_allowed & ce_first_header_sent & qsfp_tx_tready & ~ce_stalling & ~ce_stalling_last_packet;

  // let's take into account when we have full and partially full packets
  generate
    if(LAST_PACKET_BYTE_SIZE==0) begin
      assign ce_end_of_emission = (ce_seq_num == NB_PACKETS_FULL-1) & (ce_word_counter == LAST_PACKET_BYTE_SIZE) ? 1'b1 : 1'b0;
    end else begin
      assign ce_end_of_emission = (ce_seq_num == NB_PACKETS_FULL-1) & (ce_word_counter == LAST_PACKET_BYTE_SIZE) ? 1'b1 : 1'b0;
    end
  endgenerate

  // For the arbiter we need the information to release the fsm that all have been sent
  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      ce_all_packets_transmitted <= 1'b0;
    end else begin
      ce_all_packets_transmitted <= stop_sending_ce_partial_frame;
    end
  end

  // =========================================================================================== //
  // Small arbiter
  // =========================================================================================== //
  // simple FSM that changes state from IDLE when a new request is pending
  // desasserts from the state allowed when the packet has been transmitted
  typedef enum logic [2:0] {
    ST_XXX         = 'x,
    ST_IDLE        = 3'b001,
    ST_CT_EMISSION = 3'b010,
    ST_NACK        = 3'b011,
    ST_READ_REQ    = 3'b100,
    ST_NOTIFY      = 3'b101
  } st_tx;

  st_tx tx_state;
  st_tx tx_next_state;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) tx_state <= ST_IDLE;
    else tx_state <= tx_next_state;
  end

  always_comb begin
    tx_next_state = ST_XXX;
    case (tx_state)
      ST_IDLE:
        begin
          if (new_ct_emission_request_pending) begin
            tx_next_state = ST_CT_EMISSION;
          end else if (new_notify_ack_pending) begin
            tx_next_state = ST_NACK;
          end else if (new_read_request_pending & cerx_reception_ready) begin
            // we must allow launching read-request only if ce-rx is ready and empty
            tx_next_state = ST_READ_REQ;
          end else if (new_notify_request_pending | retry_notify) begin
            tx_next_state = ST_NOTIFY;
          end else begin
            tx_next_state = ST_IDLE;
          end
        end
      ST_CT_EMISSION:
        tx_next_state = ce_all_packets_transmitted ? ST_IDLE : ST_CT_EMISSION;
      ST_NACK:
        tx_next_state =  tx_small_last ? ST_IDLE : ST_NACK;
      ST_READ_REQ:
        tx_next_state =  ct_emission_all_packets_received ? ST_IDLE : ST_READ_REQ;
      ST_NOTIFY:
        tx_next_state =  tx_small_last ? ST_IDLE : ST_NOTIFY;
    endcase
  end

  assign ct_emission_allowed    = (tx_state == ST_CT_EMISSION) ? 1'b1 : 1'b0;
  assign notify_ack_allowed     = (tx_state == ST_NACK)        ? 1'b1 : 1'b0;
  assign read_request_allowed   = (tx_state == ST_READ_REQ)    ? 1'b1 : 1'b0;
  assign notify_request_allowed = (tx_state == ST_NOTIFY)      ? 1'b1 : 1'b0;

  assign notify_ack_sent        = (tx_state == ST_NACK) & tx_small_last;

  // =========================================================================================== //
  // AXI4-stream
  // =========================================================================================== //
  // before sending anything to MRMAC we register it
  logic [  MRMAC_AXIS_W-1:0] tx_tdata_reg;
  logic [ MRMAC_TKEEP_W-1:0] tx_tkeep_user_reg;
  logic                      tx_tlast_reg;
  logic                      tx_tvalid_reg;

  assign tx_last  = small_packet ? tx_small_last : ct_emission_allowed ? tx_last_word : 1'b0;
  assign tx_data  = small_packet ? tx_header : (ct_emission_allowed & ce_header) ? tx_header : (ct_emission_allowed & ce_valid & ce_ready) ? ce_payload :'h0;
  assign tx_valid = ~(tx_cnt == 'h0);

  always_ff @(posedge clk_mrmac) begin
    tx_tdata_reg      <= mhdma_pkg::byte_swap(tx_data);
    tx_tvalid_reg     <= tx_valid;
    tx_tkeep_user_reg <= {3'b000, tx_byte_enable};
    tx_tlast_reg      <= small_packet  ? tx_small_last: tx_last;
  end

  assign qsfp_tx_tdata      = tx_tdata_reg;
  assign qsfp_tx_tvalid     = tx_tvalid_reg;
  assign qsfp_tx_tkeep_user = tx_tkeep_user_reg;
  assign qsfp_tx_tlast      = tx_tlast_reg;

  // =========================================================================================== //
  // Statistics
  // =========================================================================================== //
  assign stat_fsm_formatter = tx_state;

endmodule
