// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright (c) 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Unit testbench for mhdma_decoder
//
// The mhdma_decoder receives raw QSFP RX AXI-Stream data and:
//   1. Byte-swaps incoming data
//   2. Parses Ethernet frames word by word (h0..h3)
//   3. Validates destination MAC against current_hpu_mac
//   4. Detects packet type from req_id: NOTIFY, NOTIFY_ACK, READ, EMISSION
//   5. Generates rising-edge pulses for each packet type
//   6. Pushes decoded commands into a FIFO (fifo_rx_cmd) with ready/valid handshake
//   7. For CE packets, forwards payload data via rx_tdata_out/rx_tvalid_out
//   8. Tracks statistics: counters for each packet type, timing between first and last CE packet
//   9. Reports error if FIFO overflows (error_fifo_rx_ovf)
//
// Scenarios tested:
//   > Basic Notify packet decode
//   > Notify ACK packet decode
//   > Read Request packet decode
//   > Ciphertext Emission packet decode
//   > MAC address filtering
//   > Mid-packet bubble (tvalid drop between frames)
//   > Unknown/invalid req_id
//   > Consecutive same-type packets (pulse detection)
//   > Dynamic MAC address change
//   > Back-to-back packets
//   > FIFO backpressure & error overflow
//   > Statistics reset
//   > Error reset
//   > CE timing statistics
//   > Mixed packet types
//
// Simulation timeout: SIM_TIMEOUT (100_000 ns).
//
// ==============================================================================================

`resetall
`timescale 1ns/10ps
module tb_mhdma_decoder;
  import mhdma_pkg::*;
  import axi_if_shell_axil_pkg::*;
  import axi_if_common_param_pkg::*;
  import axi_if_mhdma_axi_pkg::*;
  import pem_common_param_pkg::*;

  `include "tb_mhdma_tasks.sv"

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int CLK_HALF_PERIOD = 1;
  localparam int ARST_ACTIVATION = 17;
  localparam int SIM_TIMEOUT  = 100_000;

  // Test MAC address for this HPU (only lower MAC_ADDR_W bits matter for matching)
  localparam [MAC_ADDR_W-1:0] TB_DUT_MAC_ADDR   = 24'hA1B2C3;
  localparam [MAC_ADDR_W-1:0] TB_WRONG_MAC_ADDR = 24'hFFFFFF;
  localparam [MAC_ADDR_W-1:0] TB_SRC_MAC_ADDR   = 24'hD4E5F6;
  localparam [MAC_ADDR_W-1:0] TB_NEW_MAC_ADDR   = 24'h112233;

  // FIFO total capacity = DEPTH + RAM_LATENCY + 1.
  localparam int TOTAL_RX_FIFO_DEPTH = RX_FIFO_DEPTH + 1 + 1;


// ============================================================================================== --
// clock, reset
// ============================================================================================== --
  bit clk;

  initial begin
    clk = 1'b0;
  end

  always begin
    #CLK_HALF_PERIOD clk = ~clk;
  end

  bit a_rst_n;       // asynchronous reset
  bit s_rstn;        // synchronous reset

  initial begin
    a_rst_n = 1'b0;                  // active reset
    #ARST_ACTIVATION a_rst_n = 1'b1; // disable reset
  end

  always_ff @(posedge clk) begin
    s_rstn <= a_rst_n;
  end

// ============================================================================================== --
// End of test
// ============================================================================================== --
  bit end_of_test;

  initial begin
    wait (end_of_test);
    @(posedge clk) $display("%t > SUCCEED !", $time);
    $finish;
  end

  // Global simulation timeout -- prevents indefinite hangs
  initial begin
    #SIM_TIMEOUT;
    $display("%t > TIMEOUT: simulation did not complete in time!", $time);
    $finish;
  end

// ============================================================================================== --
// Error
// ============================================================================================== --
  bit error;
  bit error_decoded_cmd;
  bit error_notify_pulse;
  bit error_nack_pulse;
  bit error_read_req_pulse;
  bit error_payload;
  bit error_stat;
  bit error_mac_filter;
  bit error_fifo_overflow;
  bit error_assert;

  assign error = error_decoded_cmd
               | error_notify_pulse
               | error_nack_pulse
               | error_read_req_pulse
               | error_payload
               | error_stat
               | error_mac_filter
               | error_fifo_overflow
               | error_assert;

  always_ff @(posedge clk)
    if (error) begin
      $display("%t > FAILURE !", $time);
      $finish;
    end

// ============================================================================================== --
// Decoder instance
// ============================================================================================== --
  // QSFP RX interface
  qsfp_if qsfp_rx_vif (clk);
  assign qsfp_rx_vif.tready = 1'b1;

  // Configuration input
  logic [MAC_ADDR_W-1:0]    current_hpu_mac;

  // Command output
  // Decoder now exposes two role-split command streams (master-role: NOTIFY_ACK/EMISSION ;
  // slave-role: NOTIFY/READ). Merge them back into a single decoded_command view so the existing
  // single-stream consume task/checks work. NOTE: cross-role ordering is no longer guaranteed by a
  // single FIFO; scenarios that assert ordering BETWEEN a master-role and a slave-role command
  // must be reviewed. Ordering WITHIN a role is preserved.
  logic     notify_ack_received;
  command_t decoded_command_master;
  logic     decoded_command_master_vld;
  logic     decoded_command_master_rdy;

  command_t decoded_command_slave;
  logic     decoded_command_slave_vld;
  logic     decoded_command_slave_rdy;

  command_t decoded_command;
  logic     decoded_command_vld;
  logic     decoded_command_rdy;

  assign decoded_command          = decoded_command_slave_vld ? decoded_command_slave : decoded_command_master;
  assign decoded_command_vld      = decoded_command_slave_vld | decoded_command_master_vld;
  assign decoded_command_slave_rdy  = decoded_command_rdy &  decoded_command_slave_vld;
  assign decoded_command_master_rdy = decoded_command_rdy & ~decoded_command_slave_vld;

  // RX payload output
  logic [MRMAC_AXIS_W-1:0]  rx_tdata_out;
  logic                     rx_tvalid_out;

  // Statistics
  decoder_stat_t            stat;
  decoder_stat_rst_t        stat_rst;

  // Errors
  decoder_error_t           decoder_error;
  logic                     rst_errors;

  mhdma_decoder decoder (
    // Ethernet fast clock interface
    .clk_mhdma                 (clk                       ),
    .resetn_mhdma              (s_rstn                    ),
    // Command interface
    .notify_ack_received       (notify_ack_received       ),
    .current_hpu_mac           (current_hpu_mac           ),
    // Header information
    .decoded_command_master    (decoded_command_master    ),
    .decoded_command_master_vld(decoded_command_master_vld),
    .decoded_command_master_rdy(decoded_command_master_rdy),
    .decoded_command_slave     (decoded_command_slave     ),
    .decoded_command_slave_vld (decoded_command_slave_vld ),
    .decoded_command_slave_rdy (decoded_command_slave_rdy ),
    // RX payload
    .rx_tdata_out              (rx_tdata_out              ),
    .rx_tvalid_out             (rx_tvalid_out             ),
    //  Statistics
    .stat                      (stat                      ),
    .stat_rst                  (stat_rst                  ),
    // Error interface
    .decoder_error             (decoder_error             ),
    .rst_errors                (rst_errors                ),
    // QSFP system interface
    .qsfp_rx_tdata             (qsfp_rx_vif.tdata         ),
    .qsfp_rx_tkeep_user        (qsfp_rx_vif.tkeep_user    ),
    .qsfp_rx_tlast             (qsfp_rx_vif.tlast         ),
    .qsfp_rx_tvalid            (qsfp_rx_vif.tvalid        )
  );

// ============================================================================================== --
// Helper tasks
// ============================================================================================== --

  // -------------------------------------------------------------------------
  // consume_decoded_command
  // Waits for decoded_command_vld and captures the decoded command, then
  // deasserts rdy after one cycle.
  // -------------------------------------------------------------------------
  task automatic consume_decoded_command(
    output command_t cmd
  );
    begin
      wait (decoded_command_vld);
      @(posedge clk);
      decoded_command_rdy = 1'b1;
      cmd = decoded_command;
      @(posedge clk);
      decoded_command_rdy = 1'b0;
    end
  endtask

  // -------------------------------------------------------------------------
  // assert_no_command_produced
  // Waits 30 cycles then checks decoded_command_vld never asserted for 10
  // cycles. Used to verify MAC filtering, unknown req_id, etc.
  // -------------------------------------------------------------------------
  task automatic assert_no_command_produced(
    input int scenario_id,
    ref   bit err_flag
  );
    begin
      logic seen_command_valid;
      seen_command_valid = 1'b0;
      repeat (30) @(posedge clk);
      for (int i = 0; i < 10; i++) begin
        @(posedge clk);
        if (decoded_command_vld) seen_command_valid = 1'b1;
      end
      assert (!seen_command_valid) else begin
        $display("[ERROR:%0d]: command unexpectedly produced", scenario_id);
        err_flag = 1'b1;
      end
    end
  endtask

  // -------------------------------------------------------------------------
  // send_raw_packet
  // Drives qsfp_rx_vif with 8 pre-built words (byte-swapped internally).
  // this task will be used to stimulate dut with random data
  // -------------------------------------------------------------------------
  task automatic send_raw_packet(
    input logic [MRMAC_AXIS_W-1:0] pkt_data [8]
  );
    begin
      for (int i = 0; i < 8; i++) begin
        @(posedge clk);
        qsfp_rx_vif.tdata      = byte_swap(pkt_data[i]);
        qsfp_rx_vif.tkeep_user = (i < 7) ? 11'h0FF : 11'h00F;
        qsfp_rx_vif.tlast      = (i == 7);
        qsfp_rx_vif.tvalid     = 1'b1;
      end
      @(posedge clk);
      qsfp_rx_vif.tvalid     = 1'b0;
      qsfp_rx_vif.tlast      = 1'b0;
      qsfp_rx_vif.tkeep_user = 'h0;
    end
  endtask

  // -------------------------------------------------------------------------
  // check_command_fields
  // Asserts the 8 common decoded command fields against expected values.
  // Don't check dst_addr depends on scenarios, some of them don't use it.
  // -------------------------------------------------------------------------
  task automatic check_command_fields(
    input command_t              cmd,
    input logic [REQ_ID_W-1:0]   exp_req_id,
    input logic [HPU_ID_W-1:0]   exp_hpu_id,
    input logic [IOP_ID_W-1:0]   exp_iop_id,
    input logic [SRC_ADDR_W-1:0] exp_src_addr,
    input logic [FLAG_W-1:0]     exp_flag,
    input logic [MODE_W-1:0]     exp_mode,
    input logic [MAC_ADDR_W-1:0] exp_src_mac_addr,
    input int                    scen_id,
    ref   bit                    err_flag
  );
    begin
      assert (cmd.req_id       == exp_req_id)       else begin $display("[ERROR:%0d]: req_id mismatch", scen_id);       err_flag = 1'b1; end
      assert (cmd.hpu_id       == exp_hpu_id)       else begin $display("[ERROR:%0d]: hpu_id mismatch", scen_id);       err_flag = 1'b1; end
      assert (cmd.iop_id       == exp_iop_id)       else begin $display("[ERROR:%0d]: iop_id mismatch", scen_id);       err_flag = 1'b1; end
      assert (cmd.src_addr     == exp_src_addr)     else begin $display("[ERROR:%0d]: src_addr mismatch", scen_id);     err_flag = 1'b1; end
      assert (cmd.flag         == exp_flag)         else begin $display("[ERROR:%0d]: flag mismatch", scen_id);         err_flag = 1'b1; end
      assert (cmd.mode         == exp_mode)         else begin $display("[ERROR:%0d]: mode mismatch", scen_id);         err_flag = 1'b1; end
      assert (cmd.rsvd         == 8'h00)            else begin $display("[ERROR:%0d]: rsvd mismatch", scen_id);         err_flag = 1'b1; end
      assert (cmd.src_mac_addr == exp_src_mac_addr) else begin $display("[ERROR:%0d]: src_mac_addr mismatch", scen_id); err_flag = 1'b1; end
    end
  endtask

// ============================================================================================== --
// Scenario tasks
// ============================================================================================== --
  int scenario_id;
  logic [MRMAC_AXIS_W-1:0] unused_payload [$];

  // -------------------------------------------------------------------------
  // Scenario : Basic Notify packet decode
  // -------------------------------------------------------------------------
  task automatic run_scenario_basic_notify();
    command_t captured_command;
    logic [HPU_ID_W-1:0]   dst_hpu_id;
    logic [IOP_ID_W-1:0]   iop_id;
    logic [SRC_ADDR_W-1:0] src_addr;
    logic [FLAG_W-1:0]     flag;
    logic [MODE_W-1:0]     mode;

    scenario_start(scenario_id, "Basic Notify packet decode");

    dst_hpu_id = $urandom_range(1, 7);
    iop_id     = $urandom();
    src_addr   = $urandom();
    flag       = $urandom();
    mode       = $urandom();
    @(posedge clk);

    send_notify_packet(
      .vif          (qsfp_rx_vif    ),
      .dst_mac_addr (TB_DUT_MAC_ADDR),
      .src_mac_addr (TB_SRC_MAC_ADDR),
      .dst_hpu_id   (dst_hpu_id     ),
      .iop_id       (iop_id         ),
      .src_addr     (src_addr       ),
      .flag         (flag           ),
      .mode         (mode           )
    );

    consume_decoded_command(captured_command);

    check_command_fields(
      captured_command, REQ_ID_NOTIFY, dst_hpu_id, iop_id, src_addr, flag, mode, TB_SRC_MAC_ADDR, scenario_id, error_decoded_cmd
    );

    assert (stat.cnt_notify_received   == 1) else begin $display("[ERROR:%0d]: cnt_notify_received != 1", scenario_id);   error_stat = 1'b1; end
    assert (stat.cnt_nack_received     == 0) else begin $display("[ERROR:%0d]: cnt_nack_received != 0", scenario_id);     error_stat = 1'b1; end
    assert (stat.cnt_read_req_received == 0) else begin $display("[ERROR:%0d]: cnt_read_req_received != 0", scenario_id); error_stat = 1'b1; end
    assert (stat.cnt_ce_received       == 0) else begin $display("[ERROR:%0d]: cnt_ce_received != 0", scenario_id);       error_stat = 1'b1; end

    scenario_end(scenario_id, clk);
  endtask

  // -------------------------------------------------------------------------
  // Scenario : Basic Notify ACK packet decode
  // -------------------------------------------------------------------------
  task automatic run_scenario_basic_nack();
    command_t captured_command;
    logic seen_nack_pulse;
    logic [HPU_ID_W-1:0]   dst_hpu_id;
    logic [IOP_ID_W-1:0]   iop_id;
    logic [SRC_ADDR_W-1:0] src_addr;
    logic [DST_ADDR_W-1:0] dst_addr;

    scenario_start(scenario_id, "Basic Notify ACK packet decode");

    seen_nack_pulse = 1'b0;

    dst_hpu_id = $urandom_range(1, 7);
    iop_id     = $urandom();
    src_addr   = $urandom();
    dst_addr   = $urandom();

    fork

      send_notify_ack_packet(
        .vif          (qsfp_rx_vif    ),
        .dst_mac_addr (TB_DUT_MAC_ADDR),
        .src_mac_addr (TB_SRC_MAC_ADDR),
        .dst_hpu_id   (dst_hpu_id     ),
        .iop_id       (iop_id         ),
        .src_addr     (src_addr       ),
        .dst_addr     (dst_addr       )
      );

      begin : monitor_nack_pulse
        int wait_count;
        wait_count = 0;
        while (wait_count < 100) begin
          @(posedge clk);
          if (notify_ack_received) begin
            seen_nack_pulse = 1'b1;
            break;
          end
          wait_count++;
        end
      end

    join

    assert (seen_nack_pulse) else begin
      $display("[ERROR:%0d]: notify_ack_received pulse not seen", scenario_id);
      error_nack_pulse = 1'b1;
    end

    consume_decoded_command(captured_command);

    assert (captured_command.req_id       == REQ_ID_NOTIFY_ACK) else begin $display("[ERROR:%0d]: req_id mismatch", scenario_id);        error_decoded_cmd = 1'b1; end
    assert (captured_command.hpu_id       == dst_hpu_id)        else begin $display("[ERROR:%0d]: hpu_id mismatch", scenario_id);        error_decoded_cmd = 1'b1; end
    assert (captured_command.src_mac_addr == TB_SRC_MAC_ADDR)   else begin $display("[ERROR:%0d]: src_mac_addr mismatch", scenario_id);  error_decoded_cmd = 1'b1; end
    assert (stat.cnt_nack_received == 1)                        else begin $display("[ERROR:%0d]: cnt_nack_received != 1", scenario_id); error_stat = 1'b1; end

    scenario_end(scenario_id, clk);
  endtask

  // -------------------------------------------------------------------------
  // Scenario : Basic Read Request packet decode
  // -------------------------------------------------------------------------
  task automatic run_scenario_basic_read_request();
    command_t captured_command;
    logic [HPU_ID_W-1:0]   dst_hpu_id;
    logic [IOP_ID_W-1:0]   iop_id;
    logic [SRC_ADDR_W-1:0] src_addr;
    logic [DST_ADDR_W-1:0] dst_addr;
    logic [FLAG_W-1:0]     flag;
    logic [MODE_W-1:0]     mode;

    scenario_start(scenario_id, "Basic Read Request packet decode");

    dst_hpu_id = $urandom_range(1, 7);
    iop_id     = $urandom();
    src_addr   = $urandom();
    dst_addr   = $urandom();
    flag       = $urandom();
    mode       = $urandom();

    send_read_request_packet(
      .vif          (qsfp_rx_vif    ),
      .dst_mac_addr (TB_DUT_MAC_ADDR),
      .src_mac_addr (TB_SRC_MAC_ADDR),
      .dst_hpu_id   (dst_hpu_id     ),
      .iop_id       (iop_id         ),
      .src_addr     (src_addr       ),
      .dst_addr     (dst_addr       ),
      .flag         (flag           ),
      .mode         (mode           )
    );

    consume_decoded_command(captured_command);

    check_command_fields(
      captured_command, REQ_ID_READ, dst_hpu_id, iop_id, src_addr, flag, mode, TB_SRC_MAC_ADDR, scenario_id, error_decoded_cmd
    );
    assert (captured_command.dst_addr == dst_addr) else begin $display("[ERROR:%0d]: dst_addr mismatch", scenario_id); error_decoded_cmd = 1'b1; end

    assert (stat.cnt_read_req_received == 1) else begin
      $display("[ERROR:%0d]: cnt_read_req_received != 1", scenario_id);
      error_stat = 1'b1;
    end

    scenario_end(scenario_id, clk);
  endtask

  // -------------------------------------------------------------------------
  // Scenario : Basic Ciphertext Emission packet decode
  // -------------------------------------------------------------------------
  task automatic run_scenario_basic_ce();
    command_t captured_command;
    logic [MRMAC_AXIS_W-1:0] expected_payload [$];
    logic [MRMAC_AXIS_W-1:0] received_payload [$];
    int num_payload_words;
    logic [HPU_ID_W-1:0]   dst_hpu_id;
    logic [SEQ_NUM_W-1:0]  seq_num;
    logic [IOP_ID_W-1:0]   iop_id;
    logic [SRC_ADDR_W-1:0] src_addr;
    logic [DST_ADDR_W-1:0] dst_addr;
    logic [FLAG_W-1:0]     flag;
    logic [MODE_W-1:0]     mode;

    scenario_start(scenario_id, "Basic Ciphertext Emission packet decode");

    num_payload_words = 10;

    dst_hpu_id = $urandom_range(1, 7);
    seq_num    = $urandom();
    iop_id     = $urandom();
    src_addr   = $urandom();
    dst_addr   = $urandom();
    flag       = $urandom();
    mode       = $urandom();

    fork

      send_ciphertext_emission_packet(
        .vif                (qsfp_rx_vif      ),
        .dst_mac_addr       (TB_DUT_MAC_ADDR  ),
        .src_mac_addr       (TB_SRC_MAC_ADDR  ),
        .dst_hpu_id         (dst_hpu_id       ),
        .iop_id             (iop_id           ),
        .src_addr           (src_addr         ),
        .dst_addr           (dst_addr         ),
        .seq_num            (seq_num          ),
        .payload_data_out   (expected_payload ),
        .flag               (flag             ),
        .mode               (mode             ),
        .num_payload_words  (num_payload_words)
      );

      begin : capture_payload
        int capture_count;
        capture_count = 0;
        while (capture_count < num_payload_words + 20) begin
          @(posedge clk);
          if (rx_tvalid_out) begin
            received_payload.push_back(rx_tdata_out);
          end
          capture_count++;
        end
      end

    join

    consume_decoded_command(captured_command);

    assert (captured_command.req_id == REQ_ID_EMISSION) else begin        $display("[ERROR:%0d]: req_id mismatch", scenario_id);  error_decoded_cmd = 1'b1; end
    assert (captured_command.src_mac_addr == TB_SRC_MAC_ADDR) else begin  $display("[ERROR:%0d]: src_mac_addr mismatch", scenario_id);  error_decoded_cmd = 1'b1; end

    assert (received_payload.size() == num_payload_words) else begin
      $display("[ERROR:%0d]: payload word count mismatch: got %0d, expected %0d", scenario_id, received_payload.size(), num_payload_words);
      error_payload = 1'b1;
    end

    for (int i = 0; i < received_payload.size() && i < expected_payload.size(); i++) begin
      assert (received_payload[i] == expected_payload[i]) else begin
        $display("[ERROR:%0d]: payload word %0d mismatch: got 0x%016h, expected 0x%016h", scenario_id,  i, received_payload[i], expected_payload[i]);
        error_payload = 1'b1;
      end
    end

    assert (stat.cnt_ce_received == 1) else begin
      $display("[ERROR:%0d]: cnt_ce_received != 1", scenario_id);
      error_stat = 1'b1;
    end

    $display("%t > SCENARIO %0d: PASSED (received payload %0d)", $time, scenario_id, received_payload.size());

    scenario_end(scenario_id, clk);
  endtask

  // -------------------------------------------------------------------------
  // Scenario : MAC address filtering (wrong dst MAC)
  // -------------------------------------------------------------------------
  task automatic run_scenario_mac_filtering();
    logic [REG_DATA_W-1:0] saved_cnt_notify;
    logic [REG_DATA_W-1:0] saved_cnt_nack;
    logic [REG_DATA_W-1:0] saved_cnt_read_req;
    logic [REG_DATA_W-1:0] saved_cnt_ce;
    logic [HPU_ID_W-1:0]   dst_hpu_id;
    logic [IOP_ID_W-1:0]   iop_id;
    logic [SRC_ADDR_W-1:0] src_addr;

    scenario_start(scenario_id, "MAC address filtering (wrong dst MAC)");

    saved_cnt_notify   = stat.cnt_notify_received;
    saved_cnt_nack     = stat.cnt_nack_received;
    saved_cnt_read_req = stat.cnt_read_req_received;
    saved_cnt_ce       = stat.cnt_ce_received;

    dst_hpu_id = $urandom_range(1, 7);
    iop_id     = $urandom();
    src_addr   = $urandom();

    send_notify_packet(
      .vif          (qsfp_rx_vif      ),
      .dst_mac_addr (TB_WRONG_MAC_ADDR),
      .src_mac_addr (TB_SRC_MAC_ADDR  ),
      .dst_hpu_id   (dst_hpu_id       ),
      .iop_id       (iop_id           ),
      .src_addr     (src_addr         )
    );

    assert_no_command_produced(scenario_id, error_mac_filter);

    assert (stat.cnt_notify_received   == saved_cnt_notify)   else begin $display("[ERROR:%0d]: cnt_notify changed", scenario_id);   error_mac_filter = 1'b1; end
    assert (stat.cnt_nack_received     == saved_cnt_nack)     else begin $display("[ERROR:%0d]: cnt_nack changed", scenario_id);     error_mac_filter = 1'b1; end
    assert (stat.cnt_read_req_received == saved_cnt_read_req) else begin $display("[ERROR:%0d]: cnt_read_req changed", scenario_id); error_mac_filter = 1'b1; end
    assert (stat.cnt_ce_received       == saved_cnt_ce)       else begin $display("[ERROR:%0d]: cnt_ce changed", scenario_id);       error_mac_filter = 1'b1; end

    scenario_end(scenario_id, clk);
  endtask

  // -------------------------------------------------------------------------
  // Scenario : Mid-packet bubble (tvalid drop between frame 2 and frame 3)
  // Verifies that rsvd/flag/mode (frame 3) are captured from valid data
  // only, not from garbage present on the bus during a tvalid bubble.
  // -------------------------------------------------------------------------
  task automatic run_scenario_mid_packet_bubble();
    command_t captured_command;
    logic [MRMAC_AXIS_W-1:0] pkt_data [8];
    logic [HPU_ID_W-1:0]     bubble_hpu_id;
    logic [IOP_ID_W-1:0]     bubble_iop_id;
    logic [SRC_ADDR_W-1:0]   bubble_src_addr;
    logic [DST_ADDR_W-1:0]   bubble_dst_addr;
    logic [FLAG_W-1:0]       bubble_flag;
    logic [MODE_W-1:0]       bubble_mode;

    scenario_start(scenario_id, "Mid-packet bubble (tvalid drop between frame 2 and frame 3)");

    bubble_hpu_id   = $urandom_range(1, 7);
    bubble_iop_id   = $urandom();
    bubble_src_addr = $urandom();
    bubble_dst_addr = $urandom();
    bubble_flag     = $urandom();
    bubble_mode     = $urandom();

    // Build a Read Request packet (exercises all decoded fields)
    pkt_data[0] = {MAC_OUI, TB_DUT_MAC_ADDR, MAC_OUI[MAC_OUI_W-1:8]};
    pkt_data[1] = {MAC_OUI[7:0], TB_SRC_MAC_ADDR, ETH_LEN_MIN, LLC_DSAP, LLC_SSAP};
    pkt_data[2] = {LLC_CTRL, REQ_ID_READ, bubble_hpu_id, 8'h00, bubble_src_addr, bubble_dst_addr, bubble_iop_id};
    pkt_data[3] = {8'h0, bubble_flag, bubble_mode, 48'h0};
    for (int i = 4; i < 8; i++) pkt_data[i] = 64'h0;

    // Send frame words 0-2 normally
    for (int i = 0; i < 3; i++) begin
      @(posedge clk);
      qsfp_rx_vif.tdata      = byte_swap(pkt_data[i]);
      qsfp_rx_vif.tkeep_user = 11'h0FF;
      qsfp_rx_vif.tlast      = 1'b0;
      qsfp_rx_vif.tvalid     = 1'b1;
    end

    // Insert 2-cycle bubble between frame 2 and frame 3
    // Put deliberate garbage on the bus to detect if it gets latched
    @(posedge clk);
    qsfp_rx_vif.tvalid = 1'b0;
    qsfp_rx_vif.tdata  = {$urandom(), $urandom()};
    @(posedge clk);
    qsfp_rx_vif.tdata  = {$urandom(), $urandom()};

    // Resume with frame 3 onwards
    for (int i = 3; i < 8; i++) begin
      @(posedge clk);
      qsfp_rx_vif.tdata      = byte_swap(pkt_data[i]);
      qsfp_rx_vif.tkeep_user = (i < 7) ? 11'h0FF : 11'h00F;
      qsfp_rx_vif.tlast      = (i == 7);
      qsfp_rx_vif.tvalid     = 1'b1;
    end

    @(posedge clk);
    qsfp_rx_vif.tvalid     = 1'b0;
    qsfp_rx_vif.tlast      = 1'b0;
    qsfp_rx_vif.tkeep_user = 'h0;

    consume_decoded_command(captured_command);

    check_command_fields(
      captured_command, REQ_ID_READ, bubble_hpu_id, bubble_iop_id, bubble_src_addr, bubble_flag, bubble_mode, TB_SRC_MAC_ADDR, scenario_id, error_decoded_cmd
    );

    assert (captured_command.dst_addr == bubble_dst_addr) else begin $display("[ERROR:%0d]: dst_addr mismatch", scenario_id); error_decoded_cmd = 1'b1; end

    scenario_end(scenario_id, clk);
  endtask

  // -------------------------------------------------------------------------
  // Scenario : Unknown/invalid req_id
  // A packet with a req_id that does not match any known type should not
  // push any command into the FIFO and should not increment any counter.
  // -------------------------------------------------------------------------
  task automatic run_scenario_unknown_req_id();
    logic [MRMAC_AXIS_W-1:0] pkt_data [8];
    logic [REG_DATA_W-1:0]   saved_cnt_notify;
    logic [REG_DATA_W-1:0]   saved_cnt_nack;
    logic [REG_DATA_W-1:0]   saved_cnt_read_req;
    logic [REG_DATA_W-1:0]   saved_cnt_ce;

    scenario_start(scenario_id, "Unknown/invalid req_id");

    saved_cnt_notify   = stat.cnt_notify_received;
    saved_cnt_nack     = stat.cnt_nack_received;
    saved_cnt_read_req = stat.cnt_read_req_received;
    saved_cnt_ce       = stat.cnt_ce_received;

    // Build packet with invalid req_id = 4'hF (not NOTIFY/NACK/READ/EMISSION)
    pkt_data[0] = {MAC_OUI, TB_DUT_MAC_ADDR, MAC_OUI[MAC_OUI_W-1:8]};
    pkt_data[1] = {MAC_OUI[7:0], TB_SRC_MAC_ADDR, ETH_LEN_MIN, LLC_DSAP, LLC_SSAP};
    pkt_data[2] = {LLC_CTRL, 4'hF, 4'h1, 8'h00, 16'hAAAA, 16'hBBBB, 8'hCC};
    pkt_data[3] = {8'h0, 6'h3F, 2'b11, 48'h0};
    for (int i = 4; i < 8; i++) pkt_data[i] = 64'h0;

    send_raw_packet(pkt_data);

    assert_no_command_produced(scenario_id, error_decoded_cmd);

    assert (stat.cnt_notify_received   == saved_cnt_notify)   else begin $display("[ERROR:%0d]: cnt_notify changed", scenario_id);   error_stat = 1'b1; end
    assert (stat.cnt_nack_received     == saved_cnt_nack)     else begin $display("[ERROR:%0d]: cnt_nack changed", scenario_id);     error_stat = 1'b1; end
    assert (stat.cnt_read_req_received == saved_cnt_read_req) else begin $display("[ERROR:%0d]: cnt_read_req changed", scenario_id); error_stat = 1'b1; end
    assert (stat.cnt_ce_received       == saved_cnt_ce)       else begin $display("[ERROR:%0d]: cnt_ce changed", scenario_id);       error_stat = 1'b1; end

    scenario_end(scenario_id, clk);
  endtask

  // -------------------------------------------------------------------------
  // Scenario : Consecutive same-type packets (pulse detection)
  // Verify that the rising-edge pulse detection generates two separate
  // notify_request_received pulses for two back-to-back NOTIFY packets.
  // -------------------------------------------------------------------------
  task automatic run_scenario_consecutive_same_type();
    int pulse_count;
    logic [REG_DATA_W-1:0] saved_cnt_notify;
    command_t cmd1;
    command_t cmd2;

    scenario_start(scenario_id, "Consecutive same-type packets (pulse detection)");

    saved_cnt_notify = stat.cnt_notify_received;
    pulse_count = 0;

    fork
      // Send two identical NOTIFY packets back-to-back (no inter-packet gap)
      begin
        send_notify_packet(
          .vif(qsfp_rx_vif),
          .dst_mac_addr(TB_DUT_MAC_ADDR),
          .src_mac_addr(TB_SRC_MAC_ADDR),
          .dst_hpu_id(4'h5),
          .iop_id(8'hAA),
          .src_addr(16'hF000)
        );
        send_notify_packet(
          .vif(qsfp_rx_vif),
          .dst_mac_addr(TB_DUT_MAC_ADDR),
          .src_mac_addr(TB_SRC_MAC_ADDR),
          .dst_hpu_id(4'h6),
          .iop_id(8'hBB),
          .src_addr(16'hF001)
        );
      end

      // Monitor notify_request_received pulses (internal DUT signal via hierarchy)
      begin : monitor_notify_pulses
        int wait_count;
        wait_count = 0;
        while (wait_count < 200) begin
          @(posedge clk);
          if (decoder.notify_request_received) pulse_count++;
          wait_count++;
        end
      end
    join

    assert (pulse_count == 2) else begin
      $display("[ERROR:%0d]: expected 2 notify pulses, got %0d", scenario_id, pulse_count);
      error_notify_pulse = 1'b1;
    end

    // Consume both commands and verify ordering
    consume_decoded_command(cmd1);
    consume_decoded_command(cmd2);

    assert (cmd1.req_id == REQ_ID_NOTIFY && cmd1.hpu_id == 4'h5) else begin
      $display("[ERROR:%0d]: first NOTIFY mismatch", scenario_id);
      error_decoded_cmd = 1'b1;
    end

    assert (cmd2.req_id == REQ_ID_NOTIFY && cmd2.hpu_id == 4'h6) else begin
      $display("[ERROR:%0d]: second NOTIFY mismatch", scenario_id);
      error_decoded_cmd = 1'b1;
    end

    assert (stat.cnt_notify_received == saved_cnt_notify + 2) else begin
      $display("[ERROR:%0d]: cnt_notify mismatch: expected +2", scenario_id);
      error_stat = 1'b1;
    end

    scenario_end(scenario_id, clk);
  endtask

  // -------------------------------------------------------------------------
  // Scenario : Dynamic MAC address change
  // Verify that changing current_hpu_mac at runtime correctly updates filtering:
  // a packet to the old MAC is rejected, a packet to the new MAC is accepted.
  // -------------------------------------------------------------------------
  task automatic run_scenario_dynamic_mac_change();
    command_t captured_command;
    logic [REG_DATA_W-1:0] saved_cnt_notify;

    scenario_start(scenario_id, "Dynamic MAC address change");

    saved_cnt_notify = stat.cnt_notify_received;

    // Switch MAC address
    @(posedge clk);
    current_hpu_mac = TB_NEW_MAC_ADDR;
    repeat (5) @(posedge clk);

    // Send packet addressed to OLD MAC (should be rejected)
    send_notify_packet(
      .vif(qsfp_rx_vif),
      .dst_mac_addr(TB_DUT_MAC_ADDR),
      .src_mac_addr(TB_SRC_MAC_ADDR),
      .dst_hpu_id(4'h1),
      .iop_id(8'h01),
      .src_addr(16'hD000)
    );

    assert_no_command_produced(scenario_id, error_mac_filter);

    assert (stat.cnt_notify_received == saved_cnt_notify) else begin
      $display("[ERROR:%0d]: cnt_notify changed for old MAC", scenario_id);
      error_mac_filter = 1'b1;
    end

    // Send packet addressed to NEW MAC (should be accepted)
    send_notify_packet(
      .vif(qsfp_rx_vif),
      .dst_mac_addr(TB_NEW_MAC_ADDR),
      .src_mac_addr(TB_SRC_MAC_ADDR),
      .dst_hpu_id(4'h2),
      .iop_id(8'h02),
      .src_addr(16'hD001)
    );

    consume_decoded_command(captured_command);

    assert (captured_command.req_id == REQ_ID_NOTIFY) else begin $display("[ERROR:%0d]: req_id mismatch for new MAC", scenario_id); error_decoded_cmd = 1'b1; end
    assert (captured_command.hpu_id == 4'h2)          else begin $display("[ERROR:%0d]: hpu_id mismatch for new MAC", scenario_id); error_decoded_cmd = 1'b1; end

    assert (stat.cnt_notify_received == saved_cnt_notify + 1) else begin
      $display("[ERROR:%0d]: cnt_notify not incremented for new MAC", scenario_id);
      error_stat = 1'b1;
    end

    // Restore original MAC for subsequent scenarios
    @(posedge clk);
    current_hpu_mac = TB_DUT_MAC_ADDR;
    repeat (5) @(posedge clk);

    scenario_end(scenario_id, clk);
  endtask

  // -------------------------------------------------------------------------
  // Scenario : Back-to-back packets of different types
  // -------------------------------------------------------------------------
  task automatic run_scenario_back_to_back();
    command_t captured_command;
    logic [REG_DATA_W-1:0] saved_cnt_notify;
    logic [REG_DATA_W-1:0] saved_cnt_read_req;
    logic [REG_DATA_W-1:0] saved_cnt_nack;

    scenario_start(scenario_id, "Back-to-back packets of different types");

    saved_cnt_notify   = stat.cnt_notify_received;
    saved_cnt_read_req = stat.cnt_read_req_received;
    saved_cnt_nack     = stat.cnt_nack_received;

    send_notify_packet(
      .vif(qsfp_rx_vif),
      .dst_mac_addr(TB_DUT_MAC_ADDR),
      .src_mac_addr(TB_SRC_MAC_ADDR),
      .dst_hpu_id(4'h1),
      .iop_id(8'h10),
      .src_addr(16'h1000)
    );

    send_read_request_packet(
      .vif(qsfp_rx_vif),
      .dst_mac_addr(TB_DUT_MAC_ADDR),
      .src_mac_addr(TB_SRC_MAC_ADDR),
      .dst_hpu_id(4'h2),
      .iop_id(8'h20),
      .src_addr(16'h2000),
      .dst_addr(16'h2001)
    );

    send_notify_ack_packet(
      .vif(qsfp_rx_vif),
      .dst_mac_addr(TB_DUT_MAC_ADDR),
      .src_mac_addr(TB_SRC_MAC_ADDR),
      .dst_hpu_id(4'h3),
      .iop_id(8'h30),
      .src_addr(16'h3000),
      .dst_addr(16'h3001)
    );

    // Consume and verify each command in order
    consume_decoded_command(captured_command);
    assert (captured_command.req_id == REQ_ID_NOTIFY) else begin $display("[ERROR:%0d]: first cmd not NOTIFY", scenario_id);   error_decoded_cmd = 1'b1; end
    assert (captured_command.hpu_id == 4'h1) else begin          $display("[ERROR:%0d]: NOTIFY hpu_id mismatch", scenario_id); error_decoded_cmd = 1'b1; end

    consume_decoded_command(captured_command);
    assert (captured_command.req_id == REQ_ID_READ) else begin $display("[ERROR:%0d]: second cmd not READ", scenario_id);  error_decoded_cmd = 1'b1; end
    assert (captured_command.hpu_id == 4'h2) else begin        $display("[ERROR:%0d]: READ hpu_id mismatch", scenario_id); error_decoded_cmd = 1'b1; end

    consume_decoded_command(captured_command);
    assert (captured_command.req_id == REQ_ID_NOTIFY_ACK) else begin $display("[ERROR:%0d]: third cmd not NACK", scenario_id);   error_decoded_cmd = 1'b1; end
    assert (captured_command.hpu_id == 4'h3) else begin              $display("[ERROR:%0d]: NACK hpu_id mismatch", scenario_id); error_decoded_cmd = 1'b1; end

    assert (stat.cnt_notify_received   == saved_cnt_notify + 1)   else begin $display("[ERROR:%0d]: cnt_notify mismatch", scenario_id);   error_stat = 1'b1; end
    assert (stat.cnt_read_req_received == saved_cnt_read_req + 1) else begin $display("[ERROR:%0d]: cnt_read_req mismatch", scenario_id); error_stat = 1'b1; end
    assert (stat.cnt_nack_received     == saved_cnt_nack + 1)     else begin $display("[ERROR:%0d]: cnt_nack mismatch", scenario_id);     error_stat = 1'b1; end

    scenario_end(scenario_id, clk);
  endtask

  // -------------------------------------------------------------------------
  // Scenario : FIFO backpressure and overflow
  // -------------------------------------------------------------------------
  task automatic run_scenario_fifo_backpressure();
    int drained_count;

    scenario_start(scenario_id, $sformatf("FIFO backpressure and overflow (RX_FIFO_DEPTH=%0d)", RX_FIFO_DEPTH));

    // Block FIFO output
    decoded_command_rdy = 1'b0;

    // Send TOTAL_RX_FIFO_DEPTH + 1 packets to overflow
    for (int packet_index = 0; packet_index < TOTAL_RX_FIFO_DEPTH + 1; packet_index++) begin
      send_notify_packet(
        .vif         (qsfp_rx_vif),
        .dst_mac_addr(TB_DUT_MAC_ADDR),
        .src_mac_addr(TB_SRC_MAC_ADDR),
        .dst_hpu_id  (packet_index[HPU_ID_W-1:0]),
        .iop_id      (packet_index[IOP_ID_W-1:0]),
        .src_addr    (16'h6000 + packet_index[15:0])
      );
    end

    // Wait for pipeline to settle
    repeat (20) @(posedge clk);

    assert (decoder_error == 1'b1) else begin
      $display("[ERROR:%0d]: FIFO overflow error not set", scenario_id);
      error_fifo_overflow = 1'b1;
    end

    // Drain FIFO
    decoded_command_rdy = 1'b1;
    drained_count = 0;
    repeat (TOTAL_RX_FIFO_DEPTH + 1 ) begin
      @(posedge clk);
      if (decoded_command_vld) begin
        drained_count++;
      end
    end

    $display("%t > %0d: drained %0d commands from FIFO", $time, scenario_id, drained_count);

    assert (drained_count <= TOTAL_RX_FIFO_DEPTH) else begin
      $display("[ERROR:%0d]: drained more than FIFO depth", scenario_id);
      error_fifo_overflow = 1'b1;
    end

    decoded_command_rdy = 1'b0;

    scenario_end(scenario_id, clk);
  endtask

  // -------------------------------------------------------------------------
  // Scenario : Statistics reset
  // -------------------------------------------------------------------------
  task automatic run_scenario_stat_reset();
    scenario_start(scenario_id, "Statistics reset");

    // Verify counters are non-zero from previous scenarios
    assert (stat.cnt_notify_received > 0) else begin
      $display("[ERROR:%0d]: cnt_notify already zero", scenario_id);
      error_stat = 1'b1;
    end

    assert (stat.cnt_nack_received > 0) else begin
      $display("[ERROR:%0d]: cnt_nack already zero", scenario_id);
      error_stat = 1'b1;
    end

    // Reset cnt_notify_received
    @(posedge clk);
    stat_rst.cnt_notify_received = 1'b1;

    @(posedge clk);
    stat_rst.cnt_notify_received = 1'b0;

    repeat (3) @(posedge clk);
    assert (stat.cnt_notify_received == 0) else begin
      $display("[ERROR:%0d]: cnt_notify not reset", scenario_id);
      error_stat = 1'b1;
    end

    assert (stat.cnt_nack_received > 0) else begin
      $display("[ERROR:%0d]: cnt_nack affected by notify reset", scenario_id);
      error_stat = 1'b1;
    end

    // Reset cnt_nack_received
    @(posedge clk);
    stat_rst.cnt_nack_received = 1'b1;

    @(posedge clk);
    stat_rst.cnt_nack_received = 1'b0;

    repeat (3) @(posedge clk);
    assert (stat.cnt_nack_received == 0) else begin
      $display("[ERROR:%0d]: cnt_nack not reset", scenario_id);
      error_stat = 1'b1;
    end

    // Reset cnt_read_req_received
    @(posedge clk);
    stat_rst.cnt_read_req_received = 1'b1;

    @(posedge clk);
    stat_rst.cnt_read_req_received = 1'b0;

    repeat (3) @(posedge clk);
    assert (stat.cnt_read_req_received == 0) else begin
      $display("[ERROR:%0d]: cnt_read_req not reset", scenario_id);
      error_stat = 1'b1;
    end

    // Reset cnt_ce_received
    @(posedge clk);
    stat_rst.cnt_ce_received = 1'b1;

    @(posedge clk);
    stat_rst.cnt_ce_received = 1'b0;

    repeat (3) @(posedge clk);
    assert (stat.cnt_ce_received == 0) else begin
     $display("[ERROR:%0d]: cnt_ce not reset",scenario_id);
     error_stat = 1'b1;
    end

    scenario_end(scenario_id, clk);
  endtask

  // -------------------------------------------------------------------------
  // Scenario : Error reset (rst_errors)
  // -------------------------------------------------------------------------
  task automatic run_scenario_error_reset();
    scenario_start(scenario_id, "Error reset (rst_errors)");

    // Error should still be sticky from FIFO backpressure scenario
    assert (decoder_error == 1'b1) else begin
      $display("[ERROR:%0d]: error not sticky from previous scenario", scenario_id);
      error_fifo_overflow = 1'b1;
    end

    // Pulse rst_errors
    @(posedge clk);
    rst_errors = 1'b1;
    @(posedge clk);
    rst_errors = 1'b0;
    repeat (3) @(posedge clk);

    assert (decoder_error == 1'b0) else begin
      $display("[ERROR:%0d]: error not cleared after rst_errors", scenario_id);
      error_fifo_overflow = 1'b1;
    end

    scenario_end(scenario_id, clk);
  endtask

  // -------------------------------------------------------------------------
  // Scenario : CE timing statistics (first-to-last packet)
  // (just checking that the counter counts)
  // -------------------------------------------------------------------------
  task automatic run_scenario_ce_timing();
    scenario_start(scenario_id, "CE timing statistics (first-to-last packet)");

    // Send CE packets with seq_num 0 to NB_PACKETS_FULL
    for (int seq = 0; seq <= NB_PACKETS_FULL + 1; seq++) begin

      send_ciphertext_emission_packet(
        .vif              (qsfp_rx_vif),
        .dst_mac_addr     (TB_DUT_MAC_ADDR),
        .src_mac_addr     (TB_SRC_MAC_ADDR),
        .dst_hpu_id       (4'h0),
        .iop_id           (8'hA0),
        .src_addr         (16'h5000),
        .dst_addr         (16'h6000),
        .seq_num          (seq[SEQ_NUM_W-1:0]),
        .payload_data_out (unused_payload)
      );
      unused_payload.delete();

      // Consume the decoded command
      begin
        command_t discard_command;
        consume_decoded_command(discard_command);
      end

      repeat (5) @(posedge clk);
    end

    repeat (20) @(posedge clk);

    assert (stat.t_ce_first_to_last_pkt > 0) else begin
      $display("[ERROR:%0d]: t_ce_first_to_last_pkt is zero", scenario_id);
      error_stat = 1'b1;
    end

    $display("%t > %0d: t_ce_first_to_last_pkt = %0d", $time, scenario_id, stat.t_ce_first_to_last_pkt);

    scenario_end(scenario_id, clk);
  endtask

  // -------------------------------------------------------------------------
  // Scenario : Mixed packet types (interleaved, randomized)
  // -------------------------------------------------------------------------
  task automatic run_scenario_mixed_packets();
    int num_mixed_packets;
    int packet_type;
    int expected_notify_count;
    int expected_nack_count;
    int expected_read_req_count;
    int expected_ce_count;

    logic [REQ_ID_W-1:0] expected_req_ids [$];
    logic [HPU_ID_W-1:0] expected_hpu_ids [$];

    scenario_start(scenario_id, "Mixed packet types (interleaved, randomized)");

    num_mixed_packets       = 16;
    expected_notify_count   = 0;
    expected_nack_count     = 0;
    expected_read_req_count = 0;
    expected_ce_count       = 0;

    // Reset all stat counters
    @(posedge clk);
    stat_rst.cnt_notify_received   = 1'b1;
    stat_rst.cnt_nack_received     = 1'b1;
    stat_rst.cnt_read_req_received = 1'b1;
    stat_rst.cnt_ce_received       = 1'b1;

    @(posedge clk);
    stat_rst = '0;

    repeat (5) @(posedge clk);

    for (int packet_index = 0; packet_index < num_mixed_packets; packet_index++) begin
      logic [HPU_ID_W-1:0]   random_hpu_id;
      logic [IOP_ID_W-1:0]   random_iop_id;
      logic [SRC_ADDR_W-1:0] random_src_addr;

      random_hpu_id   = $urandom_range(0, 15);
      random_iop_id   = $urandom();
      random_src_addr = $urandom();
      packet_type     = $urandom_range(0, 3);

      expected_hpu_ids.push_back(random_hpu_id);

      case (packet_type)
        0: begin // NOTIFY
          expected_req_ids.push_back(REQ_ID_NOTIFY);
          expected_notify_count++;
          send_notify_packet(
            .vif(qsfp_rx_vif),
            .dst_mac_addr(TB_DUT_MAC_ADDR), .src_mac_addr(TB_SRC_MAC_ADDR),
            .dst_hpu_id(random_hpu_id), .iop_id(random_iop_id),
            .src_addr(random_src_addr)
          );
        end
        1: begin // NOTIFY ACK
          expected_req_ids.push_back(REQ_ID_NOTIFY_ACK);
          expected_nack_count++;
          send_notify_ack_packet(
            .vif(qsfp_rx_vif),
            .dst_mac_addr(TB_DUT_MAC_ADDR), .src_mac_addr(TB_SRC_MAC_ADDR),
            .dst_hpu_id(random_hpu_id), .iop_id(random_iop_id),
            .src_addr(random_src_addr), .dst_addr(16'h0)
          );
        end
        2: begin // READ
          expected_req_ids.push_back(REQ_ID_READ);
          expected_read_req_count++;
          send_read_request_packet(
            .vif(qsfp_rx_vif),
            .dst_mac_addr(TB_DUT_MAC_ADDR), .src_mac_addr(TB_SRC_MAC_ADDR),
            .dst_hpu_id(random_hpu_id), .iop_id(random_iop_id),
            .src_addr(random_src_addr), .dst_addr(16'h0)
          );
        end
        3: begin // EMISSION
          expected_req_ids.push_back(REQ_ID_EMISSION);
          expected_ce_count++;
          send_ciphertext_emission_packet(
            .vif(qsfp_rx_vif),
            .dst_mac_addr(TB_DUT_MAC_ADDR), .src_mac_addr(TB_SRC_MAC_ADDR),
            .dst_hpu_id(random_hpu_id), .iop_id(random_iop_id),
            .src_addr(random_src_addr), .dst_addr(16'h0),
            .seq_num(8'h0), .payload_data_out(unused_payload)
          );
          unused_payload.delete();
        end
      endcase
    end

    // Consume and verify all commands
    for (int cmd_index = 0; cmd_index < num_mixed_packets; cmd_index++) begin
      command_t captured_command;
      consume_decoded_command(captured_command);

      assert (captured_command.req_id == expected_req_ids[cmd_index]) else begin
        $display("[ERROR:%0d]: packet %0d req_id mismatch: got %0h, expected %0h", scenario_id,
               cmd_index, captured_command.req_id, expected_req_ids[cmd_index]);
        error_decoded_cmd = 1'b1;
      end

      assert (captured_command.hpu_id == expected_hpu_ids[cmd_index]) else begin
        $display("[ERROR:%0d]: packet %0d hpu_id mismatch", scenario_id, cmd_index);
        error_decoded_cmd = 1'b1;
      end
    end

    repeat (10) @(posedge clk);
    assert (stat.cnt_notify_received   == expected_notify_count)   else begin $display("[ERROR:%0d]: cnt_notify mismatch", scenario_id);   error_stat = 1'b1; end
    assert (stat.cnt_nack_received     == expected_nack_count)     else begin $display("[ERROR:%0d]: cnt_nack mismatch", scenario_id);     error_stat = 1'b1; end
    assert (stat.cnt_read_req_received == expected_read_req_count) else begin $display("[ERROR:%0d]: cnt_read_req mismatch", scenario_id); error_stat = 1'b1; end
    assert (stat.cnt_ce_received       == expected_ce_count)       else begin $display("[ERROR:%0d]: cnt_ce mismatch", scenario_id);       error_stat = 1'b1; end

    scenario_end(scenario_id, clk);
  endtask

// ============================================================================================== --
// Main test sequence
// ============================================================================================== --
  initial begin
    // Initialisation -----------------------------------------------------------------------
    qsfp_rx_vif.tdata      = '0;
    qsfp_rx_vif.tkeep_user = '0;
    qsfp_rx_vif.tlast      = 1'b0;
    qsfp_rx_vif.tvalid     = 1'b0;

    current_hpu_mac    = TB_DUT_MAC_ADDR;
    decoded_command_rdy = 1'b0;

    stat_rst   = '0;
    rst_errors = 1'b0;

    scenario_id = 0;

    // Wait for reset deassertion
    wait (s_rstn);
    repeat (10) @(posedge clk);

    run_scenario_basic_notify();
    run_scenario_basic_nack();
    run_scenario_basic_read_request();
    run_scenario_basic_ce();
    run_scenario_mac_filtering();
    run_scenario_mid_packet_bubble();
    run_scenario_unknown_req_id();
    run_scenario_consecutive_same_type();
    run_scenario_dynamic_mac_change();
    run_scenario_back_to_back();
    run_scenario_fifo_backpressure();
    run_scenario_stat_reset();
    run_scenario_error_reset();
    run_scenario_ce_timing();
    run_scenario_mixed_packets();

    $display("\n==================================================================================================");
    $display("  All scenarios complete");
    $display("==================================================================================================");
    repeat (20) @(posedge clk);
    end_of_test = 1'b1;
  end

// ============================================================================================== --
// SVA - SystemVerilog Assertions
// XSIM is fast enough for SVA in this test
// ============================================================================================== --

  property rx_tvalid_only_during_ce;
    @(posedge clk) disable iff (~s_rstn)
    (rx_tvalid_out) |-> (decoder.ce_received || $past(decoder.ce_received) || $past(decoder.ce_received, 2));
  endproperty

  assert_rx_tvalid_only_during_ce: assert property(rx_tvalid_only_during_ce)
    else begin
      $error("[ERROR-SVA]: rx_tvalid_out asserted outside of CE reception");
      error_assert = 1'b1;
    end

  // FIFO overflow should only be flagged when valid is asserted and ready is deasserted
  property fifo_ovf_requires_backpressure;
    @(posedge clk) disable iff (~s_rstn)
    ($rose(decoder.error_fifo_rx_ovf)) |-> ($past(decoder.fifo_rx_cmd_in_vld) && $past(~decoder.fifo_rx_cmd_in_rdy));
  endproperty

  assert_fifo_ovf_requires_backpressure: assert property(fifo_ovf_requires_backpressure)
    else begin
      $error("[ERROR-SVA]: FIFO overflow flagged without valid && !ready condition");
      error_assert = 1'b1;
    end

endmodule
