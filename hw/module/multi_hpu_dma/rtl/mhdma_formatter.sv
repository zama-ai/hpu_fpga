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
  // master interface ---------------------------------------------------------
  input  logic                 [    DST_ADDR_W-1:0] master_dst_addr,
  input  logic                 [    SRC_ADDR_W-1:0] master_src_addr,
  input  logic                 [      SIZE_B_W-1:0] master_size_b,
  input  logic                 [      REQ_ID_W-1:0] master_req_id,
  input  logic                 [      IOP_ID_W-1:0] master_iop_id,
  input  logic                 [      HPU_ID_W-1:0] master_hpu_id,
  input  logic                                      master_valid,
  // slave interface ----------------------------------------------------------
  input  logic                 [     NRX_WIDTH-1:0] nrx_cmd_payload,
  input  logic                                      nrx_valid,
  output logic                                      notify_ack_sent,
  input  logic                 [     CEH_WIDTH-1:0] ce_header_payload,
  input  logic                                      ce_start_of_batch,
  input  logic                 [  MRMAC_AXIS_W-1:0] ce_payload,
  input  logic                                      ce_valid,
  output logic                                      ce_ready,
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
  logic end_of_header;
  // simplify notations
  logic master_request;
  logic small_frame;

  assign master_request = read_request_allowed | notify_request_allowed;
  assign small_frame = master_request | notify_ack_allowed;

  // =========================================================================================== //
  // Ciphertext emission specific
  // =========================================================================================== //

  // headers --------------------------------------------------------------------------------------
  logic ce_start_of_header;
  logic ce_new_header;
  logic ce_end_of_batch;
  // decoding header payload
  logic [CEH_WIDTH-1:0] ce_header_payloadD;
  logic                 ce_dst_addr;
  logic                 ce_src_addr;
  logic                 ce_size_b;
  logic                 ce_hpu_id;
  logic                 ce_iop_id;
  logic                 ce_dst_mac_addr;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      ce_header_payloadD <= 'h0;
    end else begin
      if (ce_start_of_batch)
        ce_header_payloadD <= ce_header_payload;
    end
  end

  assign ce_dst_mac_addr = ce_header_payloadD[CEH_DST_MAC_ADDR_OFS-1:CEH_IOP_ID_OFS];
  assign ce_iop_id       = ce_header_payloadD[CEH_IOP_ID_OFS-1:CEH_HPU_ID_OFS];
  assign ce_hpu_id       = ce_header_payloadD[CEH_HPU_ID_OFS-1:CEH_SIZE_B_OFS];
  assign ce_size_b       = ce_header_payloadD[CEH_SIZE_B_OFS-1:CEH_DST_ADDR_OFS];
  assign ce_dst_addr     = ce_header_payloadD[CEH_DST_ADDR_OFS-1:CEH_SRC_ADDR_OFS];
  assign ce_src_addr     = ce_header_payloadD[CEH_SRC_ADDR_OFS-1:0];

  assign ce_start_of_header = ce_start_of_batch | ce_new_header;

  // payload --------------------------------------------------------------------------------------
  logic                                  ct_emission_all_packets_transmitted;
  logic [$clog2(ETH_NB_BYTES_PAYLOAD):0] ce_word_counter;
  logic                                  ce_stalling;

  assign ce_ready = ct_emission_allowed & qsfp_tx_tready & ~ce_stalling;

  // For the arbiter we need the information to release the fsm that all have been sent
  assign ct_emission_all_packets_transmitted = 1'b0;

  // we must stall when we have extracted ETH_NB_BYTES_PAYLOAD words
  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      ce_word_counter <= 'h0;
    end else begin
      if (ce_valid & ce_ready) begin
        ce_word_counter <= ce_word_counter + 1;
      end
    end
  end

  logic trigger_stalling;

  // TODO: find better solution?
  // we know that we will not have more than three packets in a batch of ciphertext
  // we should not use % because NB_WORDS_PAYLOAD is not a power of two
  // generate
  //   if ($ceil(CT_NB_COEF/ETH_NB_BYTES_PAYLOAD)>3) begin : __UNSUPPORTED_NB_PACKETS_
  //     $fatal(1,"> ERROR: We do not support more than 3 ethernet packets per CT, add more if needed.");
  //   end
  // endgenerate
  always_comb begin
    trigger_stalling = 1'b0;
    case (ce_word_counter)
      1*NB_WORDS_PAYLOAD-1: trigger_stalling = 1'b1;
      2*NB_WORDS_PAYLOAD-1: trigger_stalling = 1'b1;
      3*NB_WORDS_PAYLOAD-1: trigger_stalling = 1'b1;
      default: trigger_stalling = 1'b0;
    endcase
  end

  // we must continue to stall long enough to allow us to send a new header
  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      ce_stalling <= 1'b0;
    end else begin
      if (trigger_stalling) begin
        ce_stalling <= 1'b1;
      end else if (end_of_header) begin
        ce_stalling <= 1'b0;
      end
    end
  end

  // to define if we have a new header to send we can just do a positive edge detection
  logic ce_stallingD;
  always_ff @(posedge clk_mrmac)
    ce_stallingD <= ce_stalling;

  assign ce_new_header = ce_stalling & ~ce_stallingD;

  // During CE we need to increment seq_num for each packet sent
  logic [SEQ_NUM_W-1:0] ce_seq_num;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      ce_seq_num <= 'h0;
    end else begin
      if (ce_new_header) begin
        ce_seq_num <= ce_seq_num+1;
      end else if (ce_end_of_batch) begin
        ce_seq_num <= 'h0;
      end
    end
  end

  assign ce_end_of_batch = (ce_word_counter >= CT_NB_COEF) ? 1'b1 : 1'b0;

  // we must be able to do zero padding if we receive not enough words from slave module

  // =========================================================================================== //
  // Building headers
  // =========================================================================================== //
  logic                            sending_request;
  logic                            header_sop;
  logic [        MRMAC_AXIS_W-1:0] tx_frame;
  logic [$clog2(NB_WORDS_MIN)+1:0] tx_cnt; //TODO
  logic                            tx_frame_valid;
  logic                            tx_last_header;
  logic                            tx_last;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      tx_cnt <= 'h0;
    end else begin
      if (sending_request & qsfp_tx_tready) begin
        tx_cnt <= tx_cnt +1;
      end else begin
        tx_cnt <= 'h0;
      end
    end
  end

  assign tx_last_header = (tx_cnt == NB_WORDS_MIN+1) ? 1'b1: 1'b0;
  assign tx_last        = (tx_cnt == NB_WORDS_PAYLOAD+1) ? 1'b1: 1'b0;
  assign tx_frame_valid = (tx_cnt == 'h0) ? 1'b0 : 1'b1 ;
  assign end_of_header  = (tx_cnt == ETH_HEADER_SIZE) ? 1'b1 : 1'b0 ;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      sending_request <= 1'b0;
    end else begin
      if (header_sop) begin
        sending_request <= 1'b1;
      end else if(small_frame && (tx_cnt == NB_WORDS_MIN)) begin
        sending_request <= 1'b0;
      end else if(ct_emission_allowed && (tx_cnt == NB_WORDS_PAYLOAD)) begin
        sending_request <= 1'b0;
      end
    end
  end

  // NACK received from slave module ------------------------------------------
  logic [SRC_ADDR_W-1:0] nack_src_addr;
  logic [  HPU_ID_W-1:0] nack_hpu_id;
  logic [  IOP_ID_W-1:0] nack_iop_id;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      nack_src_addr <= 'h0;
      nack_hpu_id   <= 'h0;
      nack_iop_id   <= 'h0;
    end else begin
      if (nrx_valid) begin
        nack_src_addr <= nrx_cmd_payload[NRX_SRC_ADDR_OFS-1:NRX_HPU_ID_OFS];
        nack_hpu_id   <= nrx_cmd_payload[NRX_HPU_ID_OFS-1:NRX_IOP_ID_OFS];
        nack_iop_id   <= nrx_cmd_payload[NRX_IOP_ID_OFS-1:0];
      end
    end
  end

  // Header cycle by cycle construction ---------------------------------------
  logic [  MAC_ADDR_W-1:0] header_target_hpu_mac_addr;
  logic [ETHERNET_LEN-1:0] header_eth_len;
  logic [   SEQ_NUM_W-1:0] header_seq_num;
  logic [  DST_ADDR_W-1:0] header_dst_addr;
  logic [  SRC_ADDR_W-1:0] header_src_addr;
  logic [    SIZE_B_W-1:0] header_size_b;
  logic [    REQ_ID_W-1:0] header_req_id;
  logic [    IOP_ID_W-1:0] header_iop_id;

  // header assignation depending on request
  assign header_target_hpu_mac_addr = master_request ? hpu_mac_table[master_hpu_id] : notify_ack_allowed ? hpu_mac_table[nack_hpu_id] : ct_emission_allowed ? ce_dst_mac_addr : 'h0;
  assign header_req_id              = master_request ? master_req_id                : notify_ack_allowed ? REQ_ID_ACK_NOTIFY_TX       : ct_emission_allowed ? REQ_ID_EMISSION : 'h0;
  assign header_src_addr            = master_request ? master_src_addr              : notify_ack_allowed ? nack_src_addr              : ct_emission_allowed ? ce_src_addr : 'h0;
  assign header_dst_addr            = master_request ? master_dst_addr              : notify_ack_allowed ? 'h0                        : ct_emission_allowed ? ce_dst_addr : 'h0;
  assign header_iop_id              = master_request ? master_iop_id                : notify_ack_allowed ? nack_iop_id                : ct_emission_allowed ? ce_iop_id : 'h0;

  assign header_eth_len = small_frame ? ETH_LEN_MIN : ETH_LEN_MAX;
  assign header_seq_num = small_frame ? 'h0         : ct_emission_allowed ? ce_seq_num : 'h0;
  assign header_size_b  = small_frame ? 'h0         : ct_emission_allowed ? ce_size_b  : 'h0;

  always_comb begin
    case (tx_cnt)
      'h1 :
        tx_frame = {MAC_OUI, header_target_hpu_mac_addr, MAC_OUI[MAC_OUI_W-1:8]};
      'h2 :
        tx_frame = {MAC_OUI[7:0], current_hpu_mac, header_eth_len, header_req_id, current_hpu_id, header_seq_num};
      'h3 :
        tx_frame = {header_src_addr, header_dst_addr, header_iop_id, header_size_b, 8'b0};
      'h0, 'h4 , 'h5 , 'h6, 'h7: begin
        tx_frame = (~ct_emission_allowed) ? 'h0 : 'h0;
      end
      default:
        tx_frame = 'h0;
    endcase
  end

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
          end else if (new_read_request_pending) begin
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
        tx_next_state =  tx_last_header ? ST_IDLE : ST_NACK;
      ST_READ_REQ:
        tx_next_state =  ct_emission_all_packets_transmitted ? ST_IDLE : ST_READ_REQ;
      ST_NOTIFY:
        tx_next_state =  tx_last_header ? ST_IDLE : ST_NOTIFY;
    endcase
  end

  assign ct_emission_allowed    = (tx_state == ST_CT_EMISSION) ? 1'b1 : 1'b0;
  assign notify_ack_allowed     = (tx_state == ST_NACK)        ? 1'b1 : 1'b0;
  assign read_request_allowed   = (tx_state == ST_READ_REQ)    ? 1'b1 : 1'b0;
  assign notify_request_allowed = (tx_state == ST_NOTIFY)      ? 1'b1 : 1'b0;

  assign header_sop = master_request ? master_valid : notify_ack_allowed ? nrx_valid : ct_emission_allowed ? ce_start_of_header : 1'b0;

  assign notify_ack_sent = tx_last_header && (tx_state == ST_NACK);
  // =========================================================================================== //
  // AXI4-stream
  // =========================================================================================== //
  assign qsfp_tx_tdata      = tx_frame;
  assign qsfp_tx_tvalid     = tx_frame_valid;
  assign qsfp_tx_tkeep_user = tx_frame_valid ? 'hFF : 0;
  assign qsfp_tx_tlast      = small_frame    ? tx_last_header: tx_last;

endmodule
