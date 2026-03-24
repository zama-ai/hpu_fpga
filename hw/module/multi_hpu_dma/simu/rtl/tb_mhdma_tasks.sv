// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Shared tasks and functions for multi_hpu_dma testbenches
//
// This file is to be included into testbenches
// Note: qsfp_if interface is defined in qsfp_if.sv (compiled separately)
//
// ==============================================================================================

// ==============================================================================================
// Common types
// ==============================================================================================

// AXI-Stream captured word (used by TX frame capture and header verification)
typedef struct {
  logic [MRMAC_AXIS_W-1:0]  tdata;
  logic [MRMAC_TKEEP_W-1:0] tkeep_user;
  logic                     tlast;
} tx_word_t;

// ==============================================================================================
// Header helpers
// ==============================================================================================

// Build expected header words (before byte_swap) for a given command
function automatic void build_expected_header(
  input  logic [MAC_ADDR_W-1:0]   target_mac,
  input  logic [MAC_ADDR_W-1:0]   self_mac,
  input  logic [ETHERNET_LEN-1:0] eth_len,
  input  logic [REQ_ID_W-1:0]     req_id,
  input  logic [HPU_ID_W-1:0]     hpu_id,
  input  logic [SEQ_NUM_W-1:0]    seq_num,
  input  logic [SRC_ADDR_W-1:0]   src_addr,
  input  logic [DST_ADDR_W-1:0]   dst_addr,
  input  logic [IOP_ID_W-1:0]     iop_id,
  input  logic [FLAG_W-1:0]       flag,
  input  logic [MODE_W-1:0]       mode,
  output logic [MRMAC_AXIS_W-1:0] expected_header [4]
);
  expected_header[0] = {MAC_OUI, target_mac, MAC_OUI[MAC_OUI_W-1:8]};
  expected_header[1] = {MAC_OUI[7:0], self_mac, eth_len, LLC_DSAP, LLC_SSAP};
  expected_header[2] = {LLC_CTRL, req_id, hpu_id, seq_num, src_addr, dst_addr, iop_id};
  expected_header[3] = {{RSVD_W{1'b0}}, flag, mode, 48'h0};
endfunction

// Verify header words of a captured frame against expected values
task automatic check_header(
  input tx_word_t frame_words[$],
  input logic [MRMAC_AXIS_W-1:0] expected_header [4],
  input string scenario_name,
  ref bit error_flag
);
  logic [MRMAC_AXIS_W-1:0] expected_swapped;
  begin
    for (int i = 0; i < 4; i++) begin
      expected_swapped = byte_swap(expected_header[i]);
      if (frame_words[i].tdata !== expected_swapped) begin
        $display("%t > [ERROR] %s: header word %0d mismatch: got 0x%016h, expected 0x%016h", $time, scenario_name, i, frame_words[i].tdata, expected_swapped);
        error_flag = 1'b1;
      end
    end
  end
endtask

// ==============================================================================================
// Generic signal helpers
// ==============================================================================================

// Pulse a signal high for one clock cycle
task automatic simulate_pulse(
  ref logic signal,
  ref bit   clk
);
  begin
    @(posedge clk);
    signal = 1'b1;
    @(posedge clk);
    signal = 1'b0;
  end
endtask

// Clear a signal by pulsing it high for one clock cycle
task automatic clear_signal(
  ref logic signal,
  ref bit   clk
);
  begin
    @(posedge clk);
    signal = 1'b1;
    @(posedge clk);
    signal = 1'b0;
  end
endtask

// ==============================================================================================
// Scenario helpers
// ==============================================================================================

// ---------------------------------------------------------------------------
// Randomize command fields with a given target HPU
// ---------------------------------------------------------------------------
task automatic randomize_command_fields(
  input  logic [HPU_ID_W-1:0]   target_hpu,
  ref    logic [HPU_ID_W-1:0]   hpu_id,
  ref    logic [IOP_ID_W-1:0]   iop_id,
  ref    logic [SRC_ADDR_W-1:0] iop_src_addr,
  ref    logic [DST_ADDR_W-1:0] iop_dst_addr,
  ref    logic [FLAG_W-1:0]     req_flag,
  ref    logic [MODE_W-1:0]     req_mode
);
  hpu_id       = target_hpu;
  iop_id       = $urandom();
  iop_src_addr = $urandom();
  iop_dst_addr = $urandom();
  req_flag     = $urandom();
  req_mode     = $urandom();
endtask

// ---------------------------------------------------------------------------
// Print scenario banner
// ---------------------------------------------------------------------------
task automatic scenario_start(
  input int    scenario_id,
  input string name
);
  $display("\n==================================================================================================");
  $display("  SCENARIO %0d: %s", scenario_id, name);
  $display("==================================================================================================");
endtask

// ---------------------------------------------------------------------------
// Print scenario result and increment ID
// ---------------------------------------------------------------------------
task automatic scenario_end(
  ref int scenario_id,
  ref bit clk
);
  $display("%t > SCENARIO %0d: PASSED", $time, scenario_id);
  scenario_id++;
  repeat (20) @(posedge clk);
endtask


// ==============================================================================================
// Error Display Function
// ==============================================================================================

// Display error register contents using struct (call only after reading the register)
function automatic void display_errors(
  input logic [REG_DATA_W-1:0] stat_errors
);
  mhdma_error_all_t errors_struct;
  errors_struct = mhdma_error_all_t'(stat_errors);

  $display("\n --------------------- Errors --------------------------------");
  $display(" Raw error register                      : 0x%08b", stat_errors);
  $display(" format_error.formatter_error            : %b", errors_struct.mhdma_error.format_error.formatter_error);
  $display(" decoder_error.error_fifo_rx_ovf         : %b", errors_struct.mhdma_error.decoder_error.error_fifo_rx_ovf);
  $display(" slave_error.rreq_cmd_ovf_error          : %b", errors_struct.mhdma_error.slave_error.rreq_cmd_ovf_error);
  $display(" slave_error.read_rresp_error            : %b", errors_struct.mhdma_error.slave_error.read_rresp_error);
  $display(" master_error_cfg.rrqq_cmd_ovf_error     : %b", errors_struct.master_error_cfg.rrqq_cmd_ovf_error);
  $display(" master_error_cfg.nrqq_cmd_ovf_error     : %b", errors_struct.master_error_cfg.nrqq_cmd_ovf_error);
  $display(" master_error.seq_num_error              : %b", errors_struct.mhdma_error.master_error.seq_num_error);
  $display(" master_error.write_error                : %b", errors_struct.mhdma_error.master_error.write_error);
  $display(" error_id                                : %b", errors_struct.mhdma_error.error_id);
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
  input logic [SRC_ADDR_W-1:0]    src_addr,
  input logic [FLAG_W-1:0]        flag = 6'h0,
  input logic [MODE_W-1:0]        mode = 2'b0
);
  logic [MRMAC_AXIS_W-1:0] pkt_data [8];
  begin
    // Build notify packet header
    pkt_data[0] = {MAC_OUI, dst_mac_addr, MAC_OUI[MAC_OUI_W-1:8]};
    pkt_data[1] = {MAC_OUI[7:0], src_mac_addr, ETH_LEN_MIN, LLC_DSAP, LLC_SSAP};
    pkt_data[2] = {LLC_CTRL, REQ_ID_NOTIFY, dst_hpu_id, 8'h00, src_addr, 16'h0000, iop_id};
    pkt_data[3] = {8'h0, flag, mode, 48'h0};
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
  input logic [DST_ADDR_W-1:0]    dst_addr,
  input logic [FLAG_W-1:0]        flag = 6'h0,
  input logic [MODE_W-1:0]        mode = 2'b0
);
  logic [MRMAC_AXIS_W-1:0] pkt_data [8];
  begin
    // Build notify ack packet header
    pkt_data[0] = {MAC_OUI, dst_mac_addr, MAC_OUI[MAC_OUI_W-1:8]};
    pkt_data[1] = {MAC_OUI[7:0], src_mac_addr, ETH_LEN_MIN, LLC_DSAP, LLC_SSAP};
    pkt_data[2] = {LLC_CTRL, REQ_ID_NOTIFY_ACK, dst_hpu_id, 8'b0, src_addr, dst_addr, iop_id};
    pkt_data[3] = {8'h0, flag, mode, 48'h0};
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
  virtual qsfp_if.master          vif,
  input logic [MAC_ADDR_W-1:0]    dst_mac_addr,
  input logic [MAC_ADDR_W-1:0]    src_mac_addr,
  input logic [HPU_ID_W-1:0]      dst_hpu_id,
  input logic [IOP_ID_W-1:0]      iop_id,
  input logic [SRC_ADDR_W-1:0]    src_addr,
  input logic [DST_ADDR_W-1:0]    dst_addr,
  input logic [FLAG_W-1:0]        flag = 6'h0,
  input logic [MODE_W-1:0]        mode = 2'b0
);
  logic [MRMAC_AXIS_W-1:0] pkt_data [8];
  begin
    // Build read request packet header
    pkt_data[0] = {MAC_OUI, dst_mac_addr, MAC_OUI[MAC_OUI_W-1:8]};
    pkt_data[1] = {MAC_OUI[7:0], src_mac_addr, ETH_LEN_MIN, LLC_DSAP, LLC_SSAP};
    pkt_data[2] = {LLC_CTRL, REQ_ID_READ, dst_hpu_id, 8'h00, src_addr, dst_addr, iop_id};
    pkt_data[3] = {8'h0, flag, mode, 48'h0};
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
// payload_data_out returns the raw payload words for verification.
// num_payload_words: when 0 (default), computed from seq_num.
task automatic send_ciphertext_emission_packet(
  virtual qsfp_if.master                vif,
  input  logic [MAC_ADDR_W-1:0]         dst_mac_addr,
  input  logic [MAC_ADDR_W-1:0]         src_mac_addr,
  input  logic [HPU_ID_W-1:0]           dst_hpu_id,
  input  logic [IOP_ID_W-1:0]           iop_id,
  input  logic [SRC_ADDR_W-1:0]         src_addr,
  input  logic [DST_ADDR_W-1:0]         dst_addr,
  input  logic [SEQ_NUM_W-1:0]          seq_num,
  output logic [MRMAC_AXIS_W-1:0]       payload_data_out [$],
  input  logic [FLAG_W-1:0]             flag = 6'h0,
  input  logic [MODE_W-1:0]             mode = 2'b0,
  input  int                            num_payload_words = 0
);
  int nwords;
  logic [MRMAC_AXIS_W-1:0] pkt_data;
  logic [MRMAC_AXIS_W-1:0] word;
  begin
    payload_data_out = {};

    // Compute payload size from seq_num when not explicitly provided
    if (num_payload_words == 0) begin
      if (seq_num == NB_PACKETS_FULL) begin
        nwords = NB_WORDS_LAST_PACKET;
      end else begin
        nwords = NB_WORDS_PAYLOAD;
      end
    end else begin
      nwords = num_payload_words;
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
    pkt_data       = {8'h0, flag, mode, 48'h0};
    vif.tdata      = byte_swap(pkt_data);
    vif.tkeep_user = 11'h0FF;
    vif.tlast      = 1'b0;
    vif.tvalid     = 1'b1;

    for (int i = 0; i < nwords - 1; i++) begin
      @(posedge vif.clk);
      word = {$urandom(), $urandom()};
      payload_data_out.push_back(word);
      vif.tdata      = byte_swap(word);
      vif.tkeep_user = 11'h0FF;
      vif.tlast      = 1'b0;
      vif.tvalid     = 1'b1;
    end

    // Last payload word
    @(posedge vif.clk);
    word           = {$urandom(), $urandom()};
    payload_data_out.push_back(word);
    vif.tdata      = byte_swap(word);
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
