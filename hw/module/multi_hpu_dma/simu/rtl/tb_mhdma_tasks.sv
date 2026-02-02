// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Shared tasks and functions for multi_hpu_dma testbenches
//
// ==============================================================================================

import mhdma_pkg::*;                    // multi-hpu-dma
import axi_if_shell_axil_pkg::*;        // axi4-lite + REG_DATA_W
import axi_if_common_param_pkg::*;      // general axi4
import hpu_regif_core_eth_2in3_pkg::*;  // ethernet regif
import axi_if_eth_axi_pkg::*;           // AXI ethernet

// Note: qsfp_if interface is defined in qsfp_if.sv (compiled separately)

// ==============================================================================================
// Error Display Function
// ==============================================================================================

// Display error register contents using struct (call only after reading the register)
function automatic void display_errors(
  input logic [REG_DATA_W-1:0] stat_errors
);
  mhdma_error_t errors_struct;
  errors_struct = mhdma_error_t'(stat_errors);

  $display("\n --------------------- Errors --------------------------------");
  $display(" Raw error register                      : 0x%08b", stat_errors);
  $display(" format_error.formatter_error            : %b", errors_struct.format_error.formatter_error);
  $display(" decoder_error.error_fifo_rx_ovf         : %b", errors_struct.decoder_error.error_fifo_rx_ovf);
  $display(" slave_error.error_fifo_nrx_commands_ovf : %b", errors_struct.slave_error.error_fifo_nrx_commands_ovf);
  $display(" master_error.seq_num_mismatch           : %b", errors_struct.master_error.seq_num_mismatch);
  $display(" master_error.write_error                : %b", errors_struct.master_error.write_error);
  $display(" error_id                                : %b", errors_struct.error_id);
  $display(" -------------------------------------------------------------\n");
endfunction

// ==============================================================================================
// QSFP Packet Injection Tasks (using virtual interface)
// ==============================================================================================

// Send a Notify packet via QSFP RX interface
task automatic send_notify_packet(
  virtual qsfp_if.master          vif,
  input logic [MAC_ADDR_W-1:0]    dst_mac_addr,
  input logic [MAC_ADDR_W-1:0]    src_mac_addr,
  input logic [HPU_ID_W-1:0]      dst_hpu_id,
  input logic [IOP_ID_W-1:0]      iop_id,
  input logic [SRC_ADDR_W-1:0]    src_addr
);
  logic [MRMAC_AXIS_W-1:0] pkt_data [8];
  begin
    // Build notify packet header
    pkt_data[0] = {MAC_OUI, dst_mac_addr, MAC_OUI[MAC_OUI_W-1:8]};
    pkt_data[1] = {MAC_OUI[7:0], src_mac_addr, ETH_LEN_MIN, LLC_DSAP, LLC_SSAP};
    pkt_data[2] = {LLC_CTRL, REQ_ID_NOTIFY, dst_hpu_id, 8'h00, src_addr, 16'h0000, iop_id};
    pkt_data[3] = {16'h4000, 48'h0};
    for (int i = 4; i < 8; i++) pkt_data[i] = 64'h0;

    // Send packet
    for (int i = 0; i < 8; i++) begin
      @(posedge vif.clk);
      vif.tdata      = byte_swap(pkt_data[i]);
      vif.tkeep_user = (i < 7) ? 11'h0FF : 11'h00F;
      vif.tlast      = (i == 7);
      vif.tvalid     = 1'b1;
    end

    @(posedge vif.clk);
    vif.tvalid     = 1'b0;
    vif.tlast      = 1'b0;
    vif.tkeep_user = 'h0;
  end
endtask

// Send a Notify ACK packet via QSFP RX interface
task automatic send_notify_ack_packet(
  virtual qsfp_if.master          vif,
  input logic [MAC_ADDR_W-1:0]    dst_mac_addr,
  input logic [MAC_ADDR_W-1:0]    src_mac_addr,
  input logic [HPU_ID_W-1:0]      dst_hpu_id,
  input logic [IOP_ID_W-1:0]      iop_id,
  input logic [SRC_ADDR_W-1:0]    src_addr,
  input logic [DST_ADDR_W-1:0]    dst_addr
);
  logic [MRMAC_AXIS_W-1:0] pkt_data [8];
  begin
    // Build notify ack packet header
    pkt_data[0] = {MAC_OUI, dst_mac_addr, MAC_OUI[MAC_OUI_W-1:8]};
    pkt_data[1] = {MAC_OUI[7:0], src_mac_addr, ETH_LEN_MIN, LLC_DSAP, LLC_SSAP};
    pkt_data[2] = {LLC_CTRL, REQ_ID_NOTIFY_ACK, dst_hpu_id, 8'b0, src_addr, dst_addr, iop_id};
    pkt_data[3] = {SIZE_B, 24'b0};
    for (int i = 4; i < 8; i++) pkt_data[i] = 64'h0;

    // Send packet
    for (int i = 0; i < 8; i++) begin
      @(posedge vif.clk);
      vif.tdata      = byte_swap(pkt_data[i]);
      vif.tkeep_user = 11'h0FF;
      vif.tlast      = (i == 7);
      vif.tvalid     = 1'b1;
    end

    @(posedge vif.clk);
    vif.tvalid     = 1'b0;
    vif.tlast      = 1'b0;
    vif.tkeep_user = 'h0;
  end
endtask

// Send a Read Request packet via QSFP RX interface
task automatic send_read_request_packet(
  virtual qsfp_if.master       vif,
  input logic [MAC_ADDR_W-1:0]    dst_mac_addr,
  input logic [MAC_ADDR_W-1:0]    src_mac_addr,
  input logic [HPU_ID_W-1:0]      dst_hpu_id,
  input logic [IOP_ID_W-1:0]      iop_id,
  input logic [SRC_ADDR_W-1:0]    src_addr,
  input logic [DST_ADDR_W-1:0]    dst_addr
);
  logic [MRMAC_AXIS_W-1:0] pkt_data [8];
  begin
    // Build read request packet header
    pkt_data[0] = {MAC_OUI, dst_mac_addr, MAC_OUI[MAC_OUI_W-1:8]};
    pkt_data[1] = {MAC_OUI[7:0], src_mac_addr, ETH_LEN_MIN, LLC_DSAP, LLC_SSAP};
    pkt_data[2] = {LLC_CTRL, REQ_ID_READ, dst_hpu_id, 8'h00, src_addr, dst_addr, iop_id};
    pkt_data[3] = {16'h4000, 48'h0};
    for (int i = 4; i < 8; i++) pkt_data[i] = 64'h0;

    // Send packet
    for (int i = 0; i < 8; i++) begin
      @(posedge vif.clk);
      vif.tdata      = byte_swap(pkt_data[i]);
      vif.tkeep_user = (i < 7) ? 11'h0FF : 11'h00F;
      vif.tlast      = (i == 7);
      vif.tvalid     = 1'b1;
    end

    @(posedge vif.clk);
    vif.tvalid     = 1'b0;
    vif.tlast      = 1'b0;
    vif.tkeep_user = 'h0;
  end
endtask

// Send a Ciphertext Emission packet via QSFP RX interface
task automatic send_ciphertext_emission_packet(
  virtual qsfp_if.master          vif,
  input logic [MAC_ADDR_W-1:0]    dst_mac_addr,
  input logic [MAC_ADDR_W-1:0]    src_mac_addr,
  input logic [HPU_ID_W-1:0]      dst_hpu_id,
  input logic [IOP_ID_W-1:0]      iop_id,
  input logic [SRC_ADDR_W-1:0]    src_addr,
  input logic [DST_ADDR_W-1:0]    dst_addr,
  input logic [SEQ_NUM_W-1:0]     seq_num
);
  int num_payload_words;
  logic [MRMAC_AXIS_W-1:0] pkt_data;
  begin
    if (seq_num == NB_PACKETS_FULL) begin
      num_payload_words = NB_WORDS_LAST_PACKET;
    end else begin
      num_payload_words = NB_WORDS_PAYLOAD;
    end

    @(posedge vif.clk);
    pkt_data       = {MAC_OUI, dst_mac_addr, MAC_OUI[MAC_OUI_W-1:8]};
    vif.tdata      = byte_swap(pkt_data);
    vif.tkeep_user = 11'h0FF;
    vif.tlast      = 1'b0;
    vif.tvalid     = 1'b1;

    @(posedge vif.clk);
    pkt_data       = {MAC_OUI[7:0], src_mac_addr, ETH_LEN_MIN, LLC_DSAP, LLC_SSAP};
    vif.tdata      = byte_swap(pkt_data);
    vif.tkeep_user = 11'h0FF;
    vif.tlast      = 1'b0;
    vif.tvalid     = 1'b1;

    @(posedge vif.clk);
    pkt_data       = {LLC_CTRL, REQ_ID_EMISSION, dst_hpu_id, seq_num, src_addr, dst_addr, iop_id};
    vif.tdata      = byte_swap(pkt_data);
    vif.tkeep_user = 11'h0FF;
    vif.tlast      = 1'b0;
    vif.tvalid     = 1'b1;

    @(posedge vif.clk);
    pkt_data       = {16'h4000, 48'h0};
    vif.tdata      = byte_swap(pkt_data);
    vif.tkeep_user = 11'h0FF;
    vif.tlast      = 1'b0;
    vif.tvalid     = 1'b1;

    // Payload words
    for (int i = 0; i < num_payload_words - 1; i++) begin
      @(posedge vif.clk);
      vif.tdata      = {$urandom(), $urandom()};
      vif.tkeep_user = 11'h0FF;
      vif.tlast      = 1'b0;
      vif.tvalid     = 1'b1;
    end

    // Last payload word
    @(posedge vif.clk);
    vif.tdata      = {$urandom(), $urandom()};
    vif.tkeep_user = 11'h00F;
    vif.tlast      = 1'b1;
    vif.tvalid     = 1'b1;

    // Deassert valid
    @(posedge vif.clk);
    vif.tvalid     = 1'b0;
    vif.tlast      = 1'b0;
    vif.tkeep_user = 'h0;
  end
endtask
