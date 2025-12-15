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
  // slave interface ----------------------------------------------------------
  input  logic                 [     NRX_WIDTH-1:0] nrx_cmd_payload,
  input  logic                                      nrx_valid,
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
  // general control
  // =========================================================================================== //
  // simplify notations
  logic master_request;
  logic small_frame;
  // there is only one slave request: ciphertext emission

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      master_request <= 1'b0;
    end else begin
      if((notify_request_allowed & qsfp_tx_tlast) | (ct_emission_all_packets_received & read_request_allowed)) begin
        master_request <= 1'b0;
      end else if (read_request_allowed | notify_request_allowed) begin
        master_request <= 1'b1;
      end
    end
  end

  // this register is needed to ease timing
  logic [NB_MAX_HPU-1:0][MAC_ADDR_W-1:0] hpu_mac_table_tmp;
  always_ff @(posedge clk_mrmac)
    hpu_mac_table_tmp <= hpu_mac_table;

  // =========================================================================================== //
  // Ciphertext emission specific
  // =========================================================================================== //
  // During CE we need to increment seq_num for each packet sent
  // For the arbiter we need the information to release the fsm that all have been sent
  logic [SEQ_NUM_W-1:0] ce_seq_num;
  logic                 ct_emission_all_packets_transmitted;

  // =========================================================================================== //
  // Building headers
  // =========================================================================================== //
  logic [$clog2(NB_WORDS_MAX)+1:0]   tx_cnt;
  logic [      MRMAC_AXIS_W/8-1:0]   tx_byte_enable;
  logic [      MRMAC_AXIS_W/8-1:0]   tx_byte_enable_d;
  logic [$clog2(MRMAC_AXIS_W/8)-1:0] last_word_bytes;
  logic                              sending_request;

  // Header cycle by cycle construction ---------------------------------------
  logic [  MAC_ADDR_W-1:0] header_target_hpu_mac_addr;
  logic [ETHERNET_LEN-1:0] header_eth_len;
  logic [   SEQ_NUM_W-1:0] header_seq_num;
  logic [  DST_ADDR_W-1:0] header_dst_addr;
  logic [  SRC_ADDR_W-1:0] header_src_addr;
  logic [    SIZE_B_W-1:0] header_size_b;
  logic [    REQ_ID_W-1:0] header_req_id;
  logic [    IOP_ID_W-1:0] header_iop_id;
  logic                    tx_last;

  assign last_word_bytes = (ETH_NB_BYTES_HEADER + header_eth_len) & {$clog2(MRMAC_AXIS_W/8){1'b1}};

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
      if (sending_request & qsfp_tx_tready) begin
        if ((tx_cnt == 0) | ~small_frame)
          tx_byte_enable <= 8'hFF;
        else if (small_frame && (tx_cnt == (NB_WORDS_MIN-1)) )
          tx_byte_enable <= tx_byte_enable_d;
        else if (tx_last)
          tx_byte_enable <= 8'h00;
      end
    end
  end

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      small_frame <= 1'b0;
    end else begin
      if (qsfp_tx_tlast) begin
        small_frame <= 1'b0;
      end else if (master_request | notify_ack_allowed) begin
        small_frame <= 1'b1;
      end
    end
  end

  // =========================================================================================== //
  // Building headers
  // =========================================================================================== //
  // TX signals
  logic                            tx_valid;
  logic [        MRMAC_AXIS_W-1:0] tx_data;
  logic [        MRMAC_AXIS_W-1:0] tx_header;
  logic                            tx_header_last;  // last header word
  logic                            tx_small_last;   // last word of a small packet
  logic                            tx_last_word;

  // ciphertext emission --------------------------------------------------------------------------
  // we need to build header and stall ciphertext arrial until we are ready
  logic ce_first_header;      // level: up for first packet header (used for tx & backpressure)
  logic ce_first_header_sent; // level: up when first packet header has been sent
  logic ce_end_of_packet;     // pulse: last word of last packet

  always_ff @(posedge clk_mrmac) begin
    if(~resetn_mrmac) begin
      ce_first_header <= 1'b0;
    end else begin
      if (tx_header_last) begin
        ce_first_header <= 1'b0;
      end else if (((ce_seq_num == 0) & (ce_valid & ~ce_ready)) & ~ce_first_header_sent) begin
        ce_first_header <= 1'b1;
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

  assign ce_end_of_packet = qsfp_tx_tlast & (ce_seq_num == NB_PACKETS_FULL);

  // let's build CE start-of-header pulse
  logic ce_start_of_header; // pulse: header transmission for all packets
  logic ce_start_emission;  // pulse: start of first header transmission
  logic ce_sop_header;      // pulse: start-of headers between packets
  logic ce_first_header_tmp;

  always_ff @(posedge clk_mrmac)
    ce_first_header_tmp <= ce_first_header;

  assign ce_start_emission = ce_first_header & ~ce_first_header_tmp;

  assign ce_start_of_header = ce_start_emission | ce_sop_header;

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

  // Decoding NACK header paylaod -----------------------------------------------------------------
  logic [SRC_ADDR_W-1:0] nack_src_addr;
  logic [  HPU_ID_W-1:0] nack_hpu_id;
  logic [  IOP_ID_W-1:0] nack_iop_id;

  // TODO: test several notify
  always_ff @(posedge clk_mrmac) begin
    if (nrx_valid) begin
      nack_src_addr <= nrx_cmd_payload[NRX_SRC_ADDR_OFS-1:NRX_HPU_ID_OFS];
      nack_hpu_id   <= nrx_cmd_payload[NRX_HPU_ID_OFS-1:NRX_IOP_ID_OFS];
      nack_iop_id   <= nrx_cmd_payload[NRX_IOP_ID_OFS-1:0];
    end
  end

  // header transmission -------------------------------------------------------------------------
  // we are sending a request on qsfp lane when we have a pulse on header start-of-packet
  // deasserting this request when we hit enough words on the counter
  logic header_sop;
  // to simplify notations we define each cases as :
  logic stop_sending_small_frame;      // notify / notify-ack / read-request
  logic stop_sending_ce_full_frame;    // ciphertext-emission: when we send ETH_NB_BYTES_PAYLOAD
  logic stop_sending_ce_partial_frame; // ciphertext-emission: when we send LAST_PACKET_BYTE_SIZE
  logic ce_last_packet;

  assign ce_last_packet = ct_emission_allowed & (ce_seq_num == NB_PACKETS_FULL);

  // we have to trigger signal one cycle earlier to have sending_request on time
  assign stop_sending_small_frame      = small_frame && (tx_cnt == NB_WORDS_SMALL_PACKETS-1);
  assign stop_sending_ce_full_frame    = ct_emission_allowed && (tx_cnt == NB_WORDS_CUST_HEADER_SIZE+NB_WORDS_PAYLOAD-1);
  assign stop_sending_ce_partial_frame = ce_last_packet && (tx_cnt == (NB_WORDS_LAST_PACKET+NB_WORDS_CUST_HEADER_SIZE-1));

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      sending_request <= 1'b0;
    end else begin
      if (header_sop) begin
        sending_request <= 1'b1;
      end else if (stop_sending_small_frame | stop_sending_ce_full_frame | stop_sending_ce_partial_frame) begin
        sending_request <= 1'b0;
      end
    end
  end

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      tx_cnt <= 'h0;
    end else begin
      if (sending_request & qsfp_tx_tready) begin
        tx_cnt <= tx_cnt+1;
      end else begin
        tx_cnt <= 'h0;
      end
    end
  end

  // header assignation depending on request
  assign header_target_hpu_mac_addr = master_request ? hpu_mac_table_tmp[format_header.hpu_id] : notify_ack_allowed ? hpu_mac_table_tmp[nack_hpu_id] : ct_emission_allowed ? ce_dst_mac_addr : 'h0;
  assign header_req_id              = master_request ? format_header.req_id                : notify_ack_allowed ? REQ_ID_ACK_NOTIFY_TX       : ct_emission_allowed ? REQ_ID_EMISSION : 'h0;
  assign header_src_addr            = master_request ? format_header.src_addr              : notify_ack_allowed ? nack_src_addr              : ct_emission_allowed ? ce_src_addr : 'h0;
  assign header_dst_addr            = master_request ? format_header.dst_addr              : notify_ack_allowed ? 'h0                        : ct_emission_allowed ? ce_dst_addr : 'h0;
  assign header_iop_id              = master_request ? format_header.iop_id                : notify_ack_allowed ? nack_iop_id                : ct_emission_allowed ? ce_iop_id : 'h0;

  assign header_eth_len = small_frame ? ETH_LEN_MIN : ce_last_packet ? ETH_LEN_LAST_PKT : ETH_LEN_MAX;
  assign header_seq_num = small_frame ? 'h0         : ct_emission_allowed ? ce_seq_num : 'h0;
  assign header_size_b  = small_frame ? 'h0         : ct_emission_allowed ? ce_size_b  : 'h0;

  always_comb begin
    case (tx_cnt)
      'h1 :
        tx_header = {MAC_OUI, header_target_hpu_mac_addr, MAC_OUI[MAC_OUI_W-1:8]};
      'h2 :
        tx_header = {MAC_OUI[7:0], current_hpu_mac, header_eth_len, 8'hF8, 8'hF8};
      'h3 :
        tx_header = {8'h03, header_req_id, current_hpu_id, header_seq_num, header_src_addr, header_dst_addr, header_iop_id};
      'h4 :
        tx_header = {header_size_b, 56'h0};
      default:
        tx_header = 'h0;
    endcase
  end

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
    ce_word_cnt_reset <= ct_emission_all_packets_transmitted;

  logic ce_stalling;             // level: up when we need to send header between packets
  logic ce_stalling_last_packet; // level: up when we need to fill last packet by zeros
  logic ce_stalling_tmp;

  // we should stall the emission of coefficents after we have to correct number of words
  // we should unstall when header has left
  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      ce_stalling <= 1'b0;
    end else begin
      if (tx_cnt == NB_WORDS_CUST_HEADER_SIZE+NB_WORDS_PAYLOAD) begin
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
  // to define if we have a new header to send we can just do a positive edge detection
  always_ff @(posedge clk_mrmac)
    ce_stalling_tmp <= ce_stalling;

  assign ce_sop_header = ce_stalling & ~ce_stalling_tmp;

  // level active when we have headers on ciphertext emission
  logic ce_header;
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
      ct_emission_all_packets_transmitted <= 1'b0;
    end else begin
      ct_emission_all_packets_transmitted <= stop_sending_ce_partial_frame;
    end
  end

  // we must be able to do zero padding if we receive not enough words from slave module

  // ----------------------------------------------------------------------------------------------
  assign tx_small_last  = (tx_cnt == NB_WORDS_MIN);
  assign tx_header_last = (tx_cnt == NB_WORDS_CUST_HEADER_SIZE);
  assign tx_last_word   = (ct_emission_allowed & ~ce_last_packet) ? (tx_cnt == NB_WORDS_CUST_HEADER_SIZE+NB_WORDS_PAYLOAD) : (tx_cnt == (NB_WORDS_LAST_PACKET+NB_WORDS_CUST_HEADER_SIZE));

  assign tx_data  = small_frame ? tx_header : (ct_emission_allowed & ce_header) ? tx_header : (ct_emission_allowed & ce_valid & ce_ready) ? ce_payload :'h0;
  assign tx_last  = small_frame ? tx_small_last : ct_emission_allowed ? tx_last_word : 1'b0;
  assign tx_valid = ~(tx_cnt == 'h0);

  // =========================================================================================== //
  // Small arbiter
  // =========================================================================================== //
  // simple FSM that changes state from IDLE when a new request is pensing
  // desasserts from the state allowed when the full frame has been sent

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
          end else if (new_notify_request_pending) begin
            tx_next_state = ST_NOTIFY;
          end else begin
            tx_next_state = ST_IDLE;
          end
        end
      ST_CT_EMISSION:
        tx_next_state = ct_emission_all_packets_transmitted ? ST_IDLE : ST_CT_EMISSION;
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

  assign header_sop = master_request ? format_header.valid : notify_ack_allowed ? nrx_valid : ct_emission_allowed ? ce_start_of_header : 1'b0;

  assign notify_ack_sent = tx_small_last && (tx_state == ST_NACK);

  // =========================================================================================== //
  // AXI4-stream
  // =========================================================================================== //
  assign qsfp_tx_tdata      = mhdma_pkg::byte_swap(tx_data);
  assign qsfp_tx_tvalid     = tx_valid;
  assign qsfp_tx_tkeep_user = {3'b000, tx_byte_enable};
  assign qsfp_tx_tlast      = small_frame  ? tx_small_last: tx_last;

endmodule
