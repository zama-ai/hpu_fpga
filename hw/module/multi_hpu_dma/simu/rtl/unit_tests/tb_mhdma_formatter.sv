// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright (c) 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Unit testbench for mhdma_formatter (TX module)
//
// The mhdma_formatter builds Ethernet frames from slave/master commands and streams them on QSFP TX.
// This testbench drives the mhdma_formatter's command and CE payload interfaces directly and monitors
// the QSFP TX AXI-Stream output.
//
// Notes:
//  Payload data is not checked here: it is checked in tb_multi_hpu_dma
//
// Scenarios:
// > Send a Notify packet
// > Send a Notify ACK packet
// > Send a Read Request packet
// > Send a Ciphertext Emission (full multi-frame transfer)
// > FSM priority: CT_EMISSION > NOTIFY
// > FSM priority: NACK > READ_REQ > NOTIFY
// > TX backpressure
// > CE multi-frame with backpressure
// > FIFO starvation resilience (frame-level gating)
// > Header field correctness
// > tkeep_user correctness
// > Back-to-back small packets (NOTIFY -> NACK)
// > Back-to-back CE emissions
// > Mid-frame backpressure for CE
// > Max hpu_id (NB_MAX_HPU-1)
// > Invalid req_id discard (slave + master)
// > Reset during active transmission
//
// ==============================================================================================

`resetall
`timescale 1ns/10ps
module tb_mhdma_formatter;
  import mhdma_pkg::*;                    // multi-hpu-dma
  import axi_if_shell_axil_pkg::*;        // axi4-lite + REG_DATA_W
  import axi_if_common_param_pkg::*;      // general axi4
  import axi_if_mhdma_axi_pkg::*;           // AXI ethernet
  import pem_common_param_pkg::*;         // CT_MEM_BYTES, AXI4_WORD_PER_PC*

  `include "tb_mhdma_tasks.sv"

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int CLK_HALF_PERIOD = 1;
  localparam int ARST_ACTIVATION = 17;

  // Known MAC addresses for verification, hardcoded to simplify
  localparam [MAC_ADDR_W-1:0] MAC_ADDR_HPU0 = 24'hAA_BB_CC;
  localparam [MAC_ADDR_W-1:0] MAC_ADDR_HPU1 = 24'hDD_EE_FF;
  localparam [MAC_ADDR_W-1:0] MAC_ADDR_HPU2 = 24'h11_22_33;
  localparam [MAC_ADDR_W-1:0] MAC_ADDR_SELF = MAC_ADDR_HPU0;
  localparam [MAC_ADDR_W-1:0] MAC_ADDR_HPU7 = 24'h77_88_99;

  // DUT HPU identity
  localparam [HPU_ID_W-1:0] SELF_HPU_ID = 4'h0;

  // Total number of CE payload words across all frames
  localparam int CE_TOTAL_PAYLOAD_WORDS = NB_PACKETS_FULL * NB_WORDS_PAYLOAD + NB_WORDS_LAST_PACKET;

  // Timeout guard: maximum cycles before declaring failure
  // otherwise most scenarios here are running continuously
  localparam int TIMEOUT_CYCLES = 500_000;

// ============================================================================================== --
// clock, reset
// ============================================================================================== --
  bit clk;
  bit a_rst_n;
  bit s_rstn;

  initial clk = 1'b0;
  always #CLK_HALF_PERIOD clk = ~clk;

  initial begin
    a_rst_n = 1'b0;
    #ARST_ACTIVATION a_rst_n = 1'b1;
  end

  always_ff @(posedge clk)
    s_rstn <= a_rst_n;

// ============================================================================================== --
// End of test
// ============================================================================================== --
  bit end_of_test;

  initial begin
    wait (end_of_test);
    @(posedge clk) $display("%t > SUCCEED !", $time);
    $finish;
  end

  // Timeout watchdog
  initial begin
    repeat (TIMEOUT_CYCLES) @(posedge clk);
    $display("%t > FAILURE: timeout reached !", $time);
    $finish;
  end

// ============================================================================================== --
// Error
// ============================================================================================== --
  bit error;
  bit error_header_check;
  bit error_done_pulse;
  bit error_fsm_priority;
  bit error_backpressure;
  bit error_ce_multiframe;
  bit error_formatter_err;
  bit error_tkeep;
  bit error_starvation;
  bit error_assert;

  bit error_b2b;
  bit error_mid_bp;
  bit error_reset_mid_tx;
  bit error_discard;

  assign error = error_header_check
               | error_done_pulse
               | error_fsm_priority
               | error_backpressure
               | error_ce_multiframe
               | error_formatter_err
               | error_tkeep
               | error_starvation
               | error_assert

               | error_b2b
               | error_mid_bp
               | error_reset_mid_tx
               | error_discard;

  always_ff @(posedge clk)
    if (error) begin
      $display("%t > FAILURE !", $time);
      $finish;
    end

// ============================================================================================== --
// DUT signals
// ============================================================================================== --
  // Bridge configurationfrst_errors
  logic [NB_MAX_HPU-1:0][MAC_ADDR_W-1:0] hpu_mac_table;
  logic                 [HPU_ID_W-1:0]   current_hpu_id;
  logic                 [MAC_ADDR_W-1:0] current_hpu_mac;

  // Slave interface (CE + NACK)
  command_t                              slave_command;
  logic                                  slave_command_vld;
  logic                                  slave_command_rdy;
  logic [MRMAC_AXIS_W-1:0]               ce_payload;
  logic                                  ce_rdy;
  logic                                  ce_vld;
  logic                                  notify_ack_sent;
  logic                                  ciphertext_sent;

  // Master interface (NOTIFY + READ_REQ)
  command_t                              master_command;
  logic                                  master_command_vld;
  logic                                  master_command_rdy;
  logic                                  notify_sent;
  logic                                  read_request_sent;

  // Error
  format_error_t                         format_error;
  logic                                  rst_errors;

  // QSFP TX
  logic [MRMAC_AXIS_W-1:0]               qsfp_tx_tdata;
  logic [MRMAC_TKEEP_W-1:0]              qsfp_tx_tkeep_user;
  logic                                  qsfp_tx_tlast;
  logic                                  qsfp_tx_tvalid;
  logic                                  qsfp_tx_tready;

  // Statistics
  formatter_stat_t                       stat;

// ============================================================================================== --
// DUT instantiation
// ============================================================================================== --
  mhdma_formatter mhdma_formatter (
    .clk_mhdma          (clk               ),
    .resetn_mhdma       (s_rstn            ),
    .hpu_mac_table      (hpu_mac_table     ),
    .current_hpu_id     (current_hpu_id    ),
    .current_hpu_mac    (current_hpu_mac   ),
    .slave_command      (slave_command     ),
    .slave_command_vld  (slave_command_vld ),
    .slave_command_rdy  (slave_command_rdy ),
    .ce_payload         (ce_payload        ),
    .ce_rdy             (ce_rdy            ),
    .ce_vld             (ce_vld            ),
    .notify_ack_sent    (notify_ack_sent   ),
    .ciphertext_sent    (ciphertext_sent   ),
    .master_command     (master_command    ),
    .master_command_vld (master_command_vld),
    .master_command_rdy (master_command_rdy),
    .notify_sent        (notify_sent       ),
    .read_request_sent  (read_request_sent ),
    .format_error       (format_error      ),
    .rst_errors         (rst_errors        ),
    .qsfp_tx_tdata      (qsfp_tx_tdata     ),
    .qsfp_tx_tkeep_user (qsfp_tx_tkeep_user),
    .qsfp_tx_tlast      (qsfp_tx_tlast     ),
    .qsfp_tx_tvalid     (qsfp_tx_tvalid    ),
    .qsfp_tx_tready     (qsfp_tx_tready    ),
    .stat               (stat              )
  );

// ============================================================================================== --
// TX frame capture: collect all words of each transmitted frame
// ============================================================================================== --
  // (clear_tx_capture is deleting properly queue content)
  tx_word_t tx_frame_q[$];     // queue collecting words of the current frame
  tx_word_t tx_all_words_q[$]; // queue collecting all transmitted words (across frames)
  int       tx_frame_count;    // number of complete frames captured

  initial begin
    tx_frame_count = 0;
    forever begin
      @(posedge clk);
      if (qsfp_tx_tvalid && qsfp_tx_tready) begin
        tx_word_t w;
        w.tdata      = qsfp_tx_tdata;
        w.tkeep_user = qsfp_tx_tkeep_user;
        w.tlast      = qsfp_tx_tlast;
        tx_frame_q.push_back(w);
        tx_all_words_q.push_back(w);
        if (qsfp_tx_tlast) begin
          tx_frame_count++;
        end
      end
    end
  end

// ============================================================================================== --
// Helper tasks
// ============================================================================================== --
  logic [MRMAC_TKEEP_W-1:0] expected_last_tkeep;
  logic force_tready;
  logic force_tready_val;

  // Initialize all TB-driven inputs to safe defaults
  task automatic tb_init();
    begin
      slave_command      = '0;
      slave_command_vld  = 1'b0;
      master_command     = '0;
      master_command_vld = 1'b0;
      ce_payload         = '0;
      ce_vld             = 1'b0;
      rst_errors         = 1'b0;
      force_tready       = 1'b0;
      force_tready_val   = 1'b1;


      // always the same in this testbench, fixed. (Used only for ciphertext emissions)
      expected_last_tkeep = 'h0F;

      // Populate MAC table with known addresses
      hpu_mac_table[0]   = MAC_ADDR_HPU0;
      hpu_mac_table[1]   = MAC_ADDR_HPU1;
      hpu_mac_table[2]   = MAC_ADDR_HPU2;
      hpu_mac_table[7]   = MAC_ADDR_HPU7;

      current_hpu_id     = SELF_HPU_ID;
      current_hpu_mac    = MAC_ADDR_SELF;
    end
  endtask

  always_ff @(posedge clk) begin
    if (force_tready)
      qsfp_tx_tready <= force_tready_val;
    else
      qsfp_tx_tready <= $urandom();
  end

  // Clear the frame capture queues
  task automatic clear_tx_capture();
    begin
      tx_frame_q.delete();
      tx_all_words_q.delete();
      tx_frame_count = 0;
    end
  endtask

  // ---------------------------------------------------------------------------
  // Drain the output fifo_element by forcing tready=1 until all expected
  // frames have been captured. *_sent signals fire at the fifo_element INPUT,
  // so with random tready the output may still be buffered.
  // ---------------------------------------------------------------------------
  task automatic flush_tx_output(input int expected_frames);
    begin
      force_tready     = 1'b1;
      force_tready_val = 1'b1;
      while (tx_frame_count < expected_frames) @(posedge clk);
      repeat (3) @(posedge clk);
      force_tready = 1'b0;
    end
  endtask

  // ---------------------------------------------------------------------------
  // Drive a master command (NOTIFY or READ_REQ) with proper handshake
  // ---------------------------------------------------------------------------
  task automatic drive_master_command(
    input logic [REQ_ID_W-1:0]   req_id,
    input logic [HPU_ID_W-1:0]   hpu_id,
    input logic [IOP_ID_W-1:0]   iop_id,
    input logic [SRC_ADDR_W-1:0] src_addr,
    input logic [DST_ADDR_W-1:0] dst_addr,
    input logic [FLAG_W-1:0]     flag,
    input logic [MODE_W-1:0]     mode
  );
    begin
      @(posedge clk);
      master_command.req_id       <= req_id;
      master_command.hpu_id       <= hpu_id;
      master_command.iop_id       <= iop_id;
      master_command.src_addr     <= src_addr;
      master_command.dst_addr     <= dst_addr;
      master_command.rsvd         <= 'h0;
      master_command.flag         <= flag;
      master_command.mode         <= mode;
      master_command.seq_num      <= '0;
      master_command.src_mac_addr <= '0;
      master_command_vld          <= 1'b1;

      // Wait for the DUT to consume the command
      do @(posedge clk); while (!master_command_rdy);
      master_command_vld <= 1'b0;
    end
  endtask

  // ---------------------------------------------------------------------------
  // Drive a slave command (CE or NACK) with proper handshake
  // ---------------------------------------------------------------------------
  task automatic drive_slave_command(
    input logic [REQ_ID_W-1:0]   req_id,
    input logic [HPU_ID_W-1:0]   hpu_id,
    input logic [IOP_ID_W-1:0]   iop_id,
    input logic [SRC_ADDR_W-1:0] src_addr,
    input logic [DST_ADDR_W-1:0] dst_addr,
    input logic [FLAG_W-1:0]     flag,
    input logic [MODE_W-1:0]     mode
  );
    begin
      @(posedge clk);
      slave_command.req_id       <= req_id;
      slave_command.hpu_id       <= hpu_id;
      slave_command.iop_id       <= iop_id;
      slave_command.src_addr     <= src_addr;
      slave_command.dst_addr     <= dst_addr;
      slave_command.rsvd         <= 'h0;
      slave_command.flag         <= flag;
      slave_command.mode         <= mode;
      slave_command.seq_num      <= '0;
      slave_command.src_mac_addr <= '0;
      slave_command_vld          <= 1'b1;

      // Wait for the DUT to consume the command
      do @(posedge clk); while (!slave_command_rdy);
      slave_command_vld <= 1'b0;
    end
  endtask

  // ---------------------------------------------------------------------------
  // Stream CE payload data with continuous valid (no gaps)
  // for debugging keep writing word counter, not random
  // ---------------------------------------------------------------------------
  task automatic stream_ce_payload_continuous();
    begin
      for (int w = 0; w < CE_TOTAL_PAYLOAD_WORDS; w++) begin
        ce_payload <= MRMAC_AXIS_W'(w);
        ce_vld     <= 1'b1;
        do @(posedge clk); while (!ce_rdy);
      end
      ce_vld <= 1'b0;
    end
  endtask

  // ---------------------------------------------------------------------------
  // Stream CE payload with random gaps (for backpressure / error testing)
  // ---------------------------------------------------------------------------
  task automatic stream_ce_payload_with_gaps(
    input int starve_after_n
  );
    int words_sent;
    begin
      words_sent = 0;
      for (int w = 0; w < CE_TOTAL_PAYLOAD_WORDS; w++) begin
        if (starve_after_n > 0 && words_sent >= starve_after_n) begin
          ce_vld <= 1'b0;
          break;
        end

        ce_payload <= MRMAC_AXIS_W'(w);
        ce_vld     <= 1'b1;
        do @(posedge clk); while (!ce_rdy);
        words_sent++;

        if (starve_after_n == 0 && ($urandom_range(0,3) == 0)) begin
          ce_vld <= 1'b0;
          repeat ($urandom_range(1,3)) @(posedge clk);
        end
      end
      ce_vld <= 1'b0;
    end
  endtask

  // ---------------------------------------------------------------------------
  // Verify that the FSM returned to IDLE
  // ---------------------------------------------------------------------------
  task automatic check_fsm_idle();
    begin
      repeat (5) @(posedge clk);
      assert (stat.fsm_formatter ==  3'b000) else begin
        $display("%t > [ERROR]: FSM did not return to IDLE (state = %0b)", $time, stat.fsm_formatter);
        error_done_pulse = 1'b1;
      end
    end
  endtask

  // ---------------------------------------------------------------------------
  // Apply full synchronous reset to recover DUT state
  // ---------------------------------------------------------------------------
  task automatic apply_full_reset();
    begin
      a_rst_n = 1'b0;
      repeat (5) @(posedge clk);
      a_rst_n = 1'b1;
      repeat (10) @(posedge clk);
      tb_init();
      repeat (5) @(posedge clk);
    end
  endtask

// ============================================================================================== --
// Scenario Helper
// ============================================================================================== --
  int scenario_id;

  logic [MRMAC_AXIS_W-1:0] expected_header [4];

  logic [  IOP_ID_W-1:0] iop_id;
  logic [SRC_ADDR_W-1:0] iop_src_addr;
  logic [DST_ADDR_W-1:0] iop_dst_addr;
  logic [FLAG_W-1:0]     req_flag;
  logic [MODE_W-1:0]     req_mode;
  logic [HPU_ID_W-1:0]   hpu_id;


  // ---------------------------------------------------------------------------
  // Verify a single-frame small packet (NOTIFY, NACK, READ_REQ)
  // Checks: word count, header, tkeep on last word, frame count
  // ---------------------------------------------------------------------------
  task automatic check_small_packet(
    input logic [MAC_ADDR_W-1:0] target_mac,
    input logic [REQ_ID_W-1:0]   req_id,
    input string                 label, // scenario id to see where we are
    ref bit                      err_flag
  );
    // Word count
    assert (tx_frame_q.size() == NB_WORDS_MIN) else begin
      $display("[ERROR:%s] expected %0d words, got %0d", label, NB_WORDS_MIN, tx_frame_q.size());
      err_flag = 1'b1;
    end

    // Header
    build_expected_header(
      .target_mac     (target_mac     ),
      .self_mac       (MAC_ADDR_SELF  ),
      .eth_len        (ETH_LEN_MIN    ),
      .req_id         (req_id         ),
      .hpu_id         (SELF_HPU_ID    ),
      .seq_num        (8'h0           ),
      .src_addr       (iop_src_addr   ),
      .dst_addr       (iop_dst_addr   ),
      .iop_id         (iop_id         ),
      .flag           (req_flag       ),
      .mode           (req_mode       ),
      .expected_header(expected_header)
    );
    check_header(tx_frame_q, expected_header, label, err_flag);

    // tkeep on last word
    assert (tx_frame_q[NB_WORDS_MIN-1].tkeep_user == expected_last_tkeep) else begin
      $display("[ERROR:%s] last tkeep mismatch: got 0x%03h, expected 0x%03h", label, tx_frame_q[NB_WORDS_MIN-1].tkeep_user, expected_last_tkeep);
      err_flag = 1'b1;
    end

    // Frame count
    assert (tx_frame_count == 1) else begin
      $display("[ERROR:%s] expected 1 frame, got %0d", label, tx_frame_count);
      err_flag = 1'b1;
    end
  endtask

  // ---------------------------------------------------------------------------
  // Verify CE multi-frame headers, tlast, and frame count
  // ---------------------------------------------------------------------------
  task automatic check_ce_multiframe_headers(
    input logic [MAC_ADDR_W-1:0] target_mac,
    input string                 label, // scenario id to see where we are
    ref bit                      err_flag
  );
    int word_i;
    int frame_width;
    logic [ETHERNET_LEN-1:0] eth_len;

    // Frame count
    assert (tx_frame_count == NB_PACKETS_FULL + 1) else begin
      $display("[ERROR:%s] expected %0d frames, got %0d", label, NB_PACKETS_FULL + 1, tx_frame_count);
      err_flag = 1'b1;
    end

    // Per-frame header verification
    word_i = 0;
    for (int frame = 0; frame <= NB_PACKETS_FULL; frame++) begin
      if (frame == NB_PACKETS_FULL) begin
        frame_width      = NB_WORDS_LAST_PACKET + NB_WORDS_CUST_HEADER_SIZE;
        eth_len = ETH_LEN_LAST_PKT;
      end else begin
        frame_width      = NB_WORDS_CUST_HEADER_SIZE + NB_WORDS_PAYLOAD;
        eth_len = ETH_LEN_MAX;
      end

      build_expected_header(
        .target_mac     (target_mac          ),
        .self_mac       (MAC_ADDR_SELF       ),
        .eth_len        (eth_len             ),
        .req_id         (REQ_ID_EMISSION     ),
        .hpu_id         (SELF_HPU_ID         ),
        .seq_num        (frame[SEQ_NUM_W-1:0]),
        .src_addr       (iop_src_addr        ),
        .dst_addr       (iop_dst_addr        ),
        .iop_id         (iop_id              ),
        .flag           (req_flag            ),
        .mode           (req_mode            ),
        .expected_header(expected_header      )
      );

      for (int h = 0; h < NB_WORDS_CUST_HEADER_SIZE; h++) begin
        if (word_i + h < tx_all_words_q.size()) begin
          if (tx_all_words_q[word_i + h].tdata !== byte_swap(expected_header[h])) begin
            $display("[ERROR:%s] frame %0d: header word %0d mismatch: got 0x%016h, expected 0x%016h",
                     label, frame, h, tx_all_words_q[word_i + h].tdata, byte_swap(expected_header[h]));
            err_flag = 1'b1;
          end
        end
      end

      // Verify tlast on last word of frame
      if (word_i + frame_width - 1 < tx_all_words_q.size()) begin
        assert (tx_all_words_q[word_i + frame_width - 1].tlast == 1'b1) else begin
          $display("[ERROR:%s] frame %0d: tlast not set on last word (index %0d)", label, frame, word_i + frame_width - 1);
          err_flag = 1'b1;
        end
      end

      word_i += frame_width;
    end
  endtask

// ============================================================================================== --
// Scenario tasks
// ============================================================================================== --

  // ---------------------------------------------------------------------------
  // SCENARIO: Send a Notify packet
  // ---------------------------------------------------------------------------
  task automatic run_scenario_notify();
    clear_tx_capture();
    scenario_start(scenario_id, "Send a Notify packet");
    randomize_command_fields(4'h1, hpu_id, iop_id, iop_src_addr, iop_dst_addr, req_flag, req_mode);

    drive_master_command(
      .req_id  (REQ_ID_NOTIFY),
      .hpu_id  (hpu_id       ),
      .iop_id  (iop_id       ),
      .src_addr(iop_src_addr ),
      .dst_addr(iop_dst_addr ),
      .flag    (req_flag     ),
      .mode    (req_mode     )
    );

    wait(notify_sent);
    flush_tx_output(1);

    check_small_packet(MAC_ADDR_HPU1, REQ_ID_NOTIFY, $sformatf("%0d", scenario_id), error_header_check);

    // Verify padding words are zero
    for (int i = 4; i < NB_WORDS_MIN; i++) begin
      if (tx_frame_q[i].tdata !== 64'h0) begin
        $display("[ERROR:%0d] padding word %0d not zero: 0x%016h", scenario_id, i, tx_frame_q[i].tdata);
        error_header_check = 1'b1;
      end
    end

    // Verify tlast on last word only
    for (int i = 0; i < NB_WORDS_MIN; i++) begin
      if (i == NB_WORDS_MIN-1) begin
        assert (tx_frame_q[i].tlast == 1'b1) else begin
          $display("[ERROR:%0d] tlast not set on last word", scenario_id);
          error_header_check = 1'b1;
        end
      end else begin
        assert (tx_frame_q[i].tlast == 1'b0) else begin
          $display("[ERROR:%0d] unexpected tlast on word %0d", scenario_id, i);
          error_header_check = 1'b1;
        end
      end
    end

    check_fsm_idle();
    scenario_end(scenario_id, clk);
  endtask

  // ---------------------------------------------------------------------------
  // SCENARIO: Send a Notify ACK packet
  // ---------------------------------------------------------------------------
  task automatic run_scenario_notify_ack();
    clear_tx_capture();
    scenario_start(scenario_id, "Send a Notify ACK packet");
    randomize_command_fields(4'h2, hpu_id, iop_id, iop_src_addr, iop_dst_addr, req_flag, req_mode);

    drive_slave_command(
      .req_id  (REQ_ID_NOTIFY_ACK),
      .hpu_id  (hpu_id           ),
      .iop_id  (iop_id           ),
      .src_addr(iop_src_addr     ),
      .dst_addr(iop_dst_addr     ),
      .flag    (req_flag         ),
      .mode    (req_mode         )
    );

    wait(notify_ack_sent);
    flush_tx_output(1);

    check_small_packet(MAC_ADDR_HPU2, REQ_ID_NOTIFY_ACK, $sformatf("%0d", scenario_id), error_header_check);

    check_fsm_idle();
    scenario_end(scenario_id, clk);
  endtask

  // ---------------------------------------------------------------------------
  // SCENARIO: Send a Read Request packet
  // ---------------------------------------------------------------------------
  task automatic run_scenario_read_req();
    clear_tx_capture();
    scenario_start(scenario_id, "Send a Read Request packet");
    randomize_command_fields(4'h1, hpu_id, iop_id, iop_src_addr, iop_dst_addr, req_flag, req_mode);

    drive_master_command(
      .req_id  (REQ_ID_READ ),
      .hpu_id  (hpu_id      ),
      .iop_id  (iop_id      ),
      .src_addr(iop_src_addr),
      .dst_addr(iop_dst_addr),
      .flag    (req_flag    ),
      .mode    (req_mode    )
    );

    wait(read_request_sent);
    flush_tx_output(1);

    check_small_packet(MAC_ADDR_HPU1, REQ_ID_READ, $sformatf("%0d", scenario_id), error_header_check);

    check_fsm_idle();
    scenario_end(scenario_id, clk);
  endtask

  // ---------------------------------------------------------------------------
  // SCENARIO: Send a Ciphertext Emission (full multi-frame transfer)
  // ---------------------------------------------------------------------------
  task automatic run_scenario_ce_emission();
    clear_tx_capture();
    scenario_start(scenario_id, "Send a Ciphertext Emission");
    randomize_command_fields(4'h1, hpu_id, iop_id, iop_src_addr, iop_dst_addr, req_flag, req_mode);

    drive_slave_command(
      .req_id  (REQ_ID_EMISSION),
      .hpu_id  (hpu_id       ),
      .iop_id  (iop_id       ),
      .src_addr(iop_src_addr ),
      .dst_addr(iop_dst_addr ),
      .flag    (req_flag     ),
      .mode    (req_mode     )
    );

    stream_ce_payload_continuous();

    wait(ciphertext_sent);
    flush_tx_output(NB_PACKETS_FULL + 1);

    check_ce_multiframe_headers(MAC_ADDR_HPU1, $sformatf("%0d", scenario_id), error_ce_multiframe);

    // Verify tkeep on last word of each frame
    begin
      int word_i;
      int frame_width;
      word_i = 0;
      for (int frame = 0; frame <= NB_PACKETS_FULL; frame++) begin
        if (frame == NB_PACKETS_FULL)
          frame_width = NB_WORDS_LAST_PACKET + NB_WORDS_CUST_HEADER_SIZE;
        else
          frame_width = NB_WORDS_CUST_HEADER_SIZE + NB_WORDS_PAYLOAD;

        if (word_i + frame_width - 1 < tx_all_words_q.size()) begin
          if (tx_all_words_q[word_i + frame_width - 1].tkeep_user !== 'hFF) begin
            $display("[ERROR:%0d] frame %0d: last tkeep mismatch: got 0x%03h, expected 0xFF",
                     scenario_id, frame, tx_all_words_q[word_i + frame_width - 1].tkeep_user);
            error_tkeep = 1'b1;
          end
        end

        word_i += frame_width;
      end
    end

    check_fsm_idle();
    scenario_end(scenario_id, clk);
  endtask

  // ---------------------------------------------------------------------------
  // SCENARIO: FSM priority CT_EMISSION > NOTIFY
  // ---------------------------------------------------------------------------
  task automatic run_scenario_prio_ce_notify();
    logic ce_done;
    logic notify_done;
    int ce_done_time;
    int notify_done_time;

    clear_tx_capture();
    scenario_start(scenario_id, "FSM priority CT_EMISSION > NOTIFY");

    ce_done = 1'b0;
    notify_done = 1'b0;
    ce_done_time = 0;
    notify_done_time = 0;

    // Present both commands simultaneously
    @(posedge clk);
    slave_command.req_id        <= REQ_ID_EMISSION;
    slave_command.hpu_id        <= 4'h1;
    slave_command.iop_id        <= 8'h55;
    slave_command.src_addr      <= 16'h3000;
    slave_command.dst_addr      <= 16'h4000;
    slave_command.rsvd          <= 8'h0;
    slave_command.flag          <= 6'h0;
    slave_command.mode          <= 2'h0;
    slave_command.seq_num       <= '0;
    slave_command.src_mac_addr  <= '0;
    slave_command_vld           <= 1'b1;

    master_command.req_id       <= REQ_ID_NOTIFY;
    master_command.hpu_id       <= 4'h2;
    master_command.iop_id       <= 8'h66;
    master_command.src_addr     <= 16'h5000;
    master_command.dst_addr     <= 16'h6000;
    master_command.rsvd         <= 8'h0;
    master_command.flag         <= 6'h0;
    master_command.mode         <= 2'h0;
    master_command.seq_num      <= '0;
    master_command.src_mac_addr <= '0;
    master_command_vld          <= 1'b1;

    fork
      stream_ce_payload_continuous();

      // Wait for slave_command_rdy (CE consumed first)
      begin
        do @(posedge clk); while (!slave_command_rdy);
        @(posedge clk);
        slave_command_vld <= 1'b0;
        $display("%t > %0d: CE command consumed (slave_command_rdy)", $time, scenario_id);
      end

      // Monitor ciphertext_sent
      begin
        wait(ciphertext_sent);
        ce_done = 1'b1;
        ce_done_time = $time;
        $display("%t > %0d: ciphertext_sent", $time, scenario_id);
      end

      // Wait for master_command_rdy (NOTIFY consumed after CE)
      begin
        do @(posedge clk); while (!master_command_rdy);
        @(posedge clk);
        master_command_vld <= 1'b0;
        $display("%t > %0d: NOTIFY command consumed (master_command_rdy)", $time, scenario_id);
      end

      // Monitor notify_sent
      begin
        // Wait for CE to complete first
        wait (ce_done);
        wait(notify_sent);
        notify_done = 1'b1;
        notify_done_time = $time;
        $display("%t > %0d: notify_sent", $time, scenario_id);
      end
    join

    // Verify ordering: CE completed before NOTIFY
    assert (ce_done_time <= notify_done_time) else begin
      $display("[ERROR:%0d] CE should complete before NOTIFY", scenario_id);
      error_fsm_priority = 1'b1;
    end

    repeat (10) @(posedge clk);
    check_fsm_idle();
    scenario_end(scenario_id, clk);
  endtask

  // ---------------------------------------------------------------------------
  // SCENARIO: FSM priority NACK > READ_REQ > NOTIFY
  // ---------------------------------------------------------------------------
  task automatic run_scenario_prio_nack_read_notify();
    int nack_done_time;
    int read_done_time;
    int notify_s6_done_time;

    clear_tx_capture();
    scenario_start(scenario_id, "FSM priority NACK > READ_REQ > NOTIFY");

    nack_done_time = 0;
    read_done_time = 0;
    notify_s6_done_time = 0;

    // Present NACK on slave + READ on master simultaneously
    @(posedge clk);
    slave_command.req_id        <= REQ_ID_NOTIFY_ACK;
    slave_command.hpu_id        <= 4'h2;
    slave_command.iop_id        <= 8'hA1;
    slave_command.src_addr      <= 16'h7000;
    slave_command.dst_addr      <= 16'h8000;
    slave_command.rsvd          <= 8'h0;
    slave_command.flag          <= 6'h0;
    slave_command.mode          <= 2'h0;
    slave_command.seq_num       <= '0;
    slave_command.src_mac_addr  <= '0;
    slave_command_vld           <= 1'b1;

    master_command.req_id       <= REQ_ID_READ;
    master_command.hpu_id       <= 4'h1;
    master_command.iop_id       <= 8'hB2;
    master_command.src_addr     <= 16'h9000;
    master_command.dst_addr     <= 16'hA000;
    master_command.rsvd         <= 8'h0;
    master_command.flag         <= 6'h0;
    master_command.mode         <= 2'h0;
    master_command.seq_num      <= '0;
    master_command.src_mac_addr <= '0;
    master_command_vld          <= 1'b1;

    // Wait for NACK to be consumed
    // Deassert one cycle later: rdy is a one-shot pulse so the extra
    // cycle of vld=1 is harmless and avoids an Active-region race.
    do @(posedge clk); while (!slave_command_rdy);
    @(posedge clk);
    slave_command_vld <= 1'b0;
    $display("%t > %0d: NACK command consumed", $time, scenario_id);

    // Wait for nack_sent
    wait(notify_ack_sent);
    nack_done_time = $time;
    $display("%t > %0d: notify_ack_sent", $time, scenario_id);

    // Wait for READ to be consumed
    do @(posedge clk); while (!master_command_rdy);
    $display("%t > %0d: READ command consumed", $time, scenario_id);

    // Wait for read_request_sent
    wait(read_request_sent);
    read_done_time = $time;
    $display("%t > %0d: read_request_sent", $time, scenario_id);

    // Now switch master_command to NOTIFY
    @(posedge clk);
    master_command.req_id   <= REQ_ID_NOTIFY;
    master_command.hpu_id   <= 4'h1;
    master_command.iop_id   <= 8'hC3;
    master_command.src_addr <= 16'hB000;
    master_command.dst_addr <= 16'hC000;
    master_command.rsvd     <= 8'h0;
    master_command.flag     <= 6'h0;
    master_command.mode     <= 2'h0;
    master_command_vld      <= 1'b1;

    // Wait for NOTIFY to be consumed
    do @(posedge clk); while (!master_command_rdy);
    @(posedge clk);
    master_command_vld <= 1'b0;

    // Wait for notify_sent
    wait(notify_sent);
    notify_s6_done_time = $time;
    $display("%t > %0d: notify_sent", $time, scenario_id);

    // Verify ordering
    assert (nack_done_time <= read_done_time) else begin
      $display("[ERROR:%0d] NACK should complete before READ", scenario_id);
      error_fsm_priority = 1'b1;
    end
    assert (read_done_time <= notify_s6_done_time) else begin
      $display("[ERROR:%0d] READ should complete before NOTIFY", scenario_id);
      error_fsm_priority = 1'b1;
    end

    repeat (10) @(posedge clk);
    check_fsm_idle();
    scenario_end(scenario_id, clk);
  endtask

  // ---------------------------------------------------------------------------
  // SCENARIO: TX backpressure
  // ---------------------------------------------------------------------------
  task automatic run_scenario_tx_backpressure();
    clear_tx_capture();
    scenario_start(scenario_id, "TX backpressure");
    randomize_command_fields(4'h1, hpu_id, iop_id, iop_src_addr, iop_dst_addr, req_flag, req_mode);

    fork
      drive_master_command(
        .req_id  (REQ_ID_NOTIFY),
        .hpu_id  (hpu_id       ),
        .iop_id  (iop_id       ),
        .src_addr(iop_src_addr ),
        .dst_addr(iop_dst_addr ),
        .flag    (req_flag     ),
        .mode    (req_mode     )
      );

      // Backpressure controller: deassert tready after 3 words
      begin
        int word_count;
        word_count = 0;
        while (word_count < 3) begin
          @(posedge clk);
          if (qsfp_tx_tvalid && qsfp_tx_tready) word_count++;
        end
        force_tready = 1'b1; force_tready_val = 1'b0;
        repeat (10) @(posedge clk);
        force_tready = 1'b0;
      end
    join

    wait(notify_sent);
    flush_tx_output(1);

    check_small_packet(MAC_ADDR_HPU1, REQ_ID_NOTIFY, $sformatf("%0d", scenario_id), error_backpressure);

    check_fsm_idle();
    scenario_end(scenario_id, clk);
  endtask

  // ---------------------------------------------------------------------------
  // SCENARIO: CE multi-frame with backpressure
  // ---------------------------------------------------------------------------
  task automatic run_scenario_ce_multiframe_bp();
    clear_tx_capture();
    scenario_start(scenario_id, "CE multi-frame with backpressure");
    randomize_command_fields(4'h1, hpu_id, iop_id, iop_src_addr, iop_dst_addr, req_flag, req_mode);

    fork
      drive_slave_command(
        .req_id  (REQ_ID_EMISSION),
        .hpu_id  (hpu_id       ),
        .iop_id  (iop_id       ),
        .src_addr(iop_src_addr ),
        .dst_addr(iop_dst_addr ),
        .flag    (req_flag     ),
        .mode    (req_mode     )
      );

      stream_ce_payload_continuous();

      // Backpressure controller: deassert tready between frames
      begin
        for (int frame = 0; frame < NB_PACKETS_FULL; frame++) begin
          @(posedge clk iff (qsfp_tx_tlast && qsfp_tx_tvalid && qsfp_tx_tready));
          force_tready = 1'b1; force_tready_val = 1'b0;
          repeat ($urandom_range(5,20)) @(posedge clk);
          force_tready = 1'b0;
        end
      end
    join

    wait(ciphertext_sent);
    flush_tx_output(NB_PACKETS_FULL + 1);

    check_ce_multiframe_headers(MAC_ADDR_HPU1, $sformatf("%0d", scenario_id), error_ce_multiframe);

    check_fsm_idle();
    scenario_end(scenario_id, clk);
  endtask

  // ---------------------------------------------------------------------------
  // SCENARIO: FIFO starvation resilience (frame-level gating)
  // ---------------------------------------------------------------------------
  task automatic run_scenario_fifo_starvation();
    // Frame-level gating buffers a full frame before alloword_ing TX, so random gaps
    // in the CE payload stream must NOT cause tvalid drops mid-frame.
    clear_tx_capture();
    scenario_start(scenario_id, "FIFO starvation resilience");
    randomize_command_fields(4'h1, hpu_id, iop_id, iop_src_addr, iop_dst_addr, req_flag, req_mode);
    repeat (20) @(posedge clk);

    fork
      drive_slave_command(
        .req_id  (REQ_ID_EMISSION),
        .hpu_id  (hpu_id       ),
        .iop_id  (iop_id       ),
        .src_addr(iop_src_addr ),
        .dst_addr(iop_dst_addr ),
        .flag    (req_flag     ),
        .mode    (req_mode     )
      );
      stream_ce_payload_with_gaps(.starve_after_n(0)); // random gaps
    join

    wait(ciphertext_sent);
    flush_tx_output(NB_PACKETS_FULL + 1);

    // All frames must have been transmitted despite slow payload arrival
    assert (tx_frame_count == NB_PACKETS_FULL + 1) else begin
      $display("[ERROR:%0d] expected %0d frames, got %0d", scenario_id, NB_PACKETS_FULL + 1, tx_frame_count);
      error_starvation = 1'b1;
    end

    // Frame-level gating should prevent the formatter_error flag
    assert (format_error.formatter_error == 1'b0) else begin
      $display("[ERROR:%0d] formatter_error raised despite frame-level gating", scenario_id);
      error_starvation = 1'b1;
    end

    check_fsm_idle();

    scenario_end(scenario_id, clk);
  endtask

  // ---------------------------------------------------------------------------
  // SCENARIO: Header field correctness
  // ---------------------------------------------------------------------------
  task automatic run_scenario_header_fields();
    scenario_start(scenario_id, "Header field correctness");

    // --- NOTIFY with specific fields ---
    clear_tx_capture();
    randomize_command_fields(4'h2, hpu_id, iop_id, iop_src_addr, iop_dst_addr, req_flag, req_mode);

    drive_master_command(
      .req_id  (REQ_ID_NOTIFY),
      .hpu_id  (hpu_id       ),
      .iop_id  (iop_id       ),
      .src_addr(iop_src_addr ),
      .dst_addr(iop_dst_addr ),
      .flag    (req_flag     ),
      .mode    (req_mode     )
    );
    wait(notify_sent);
    flush_tx_output(1);

    build_expected_header(
      .target_mac     (MAC_ADDR_HPU2  ),
      .self_mac       (MAC_ADDR_SELF  ),
      .eth_len        (ETH_LEN_MIN    ),
      .req_id         (REQ_ID_NOTIFY  ),
      .hpu_id         (SELF_HPU_ID    ),
      .seq_num        (8'h0           ),
      .src_addr       (iop_src_addr   ),
      .dst_addr       (iop_dst_addr   ),
      .iop_id         (iop_id         ),
      .flag           (req_flag       ),
      .mode           (req_mode       ),
      .expected_header(expected_header)
    );
    check_header(tx_frame_q, expected_header, $sformatf("%0d-NOTIFY", scenario_id), error_header_check);
    $display("%t > %0d: NOTIFY header verified", $time, scenario_id);

    // --- NACK with specific fields ---
    clear_tx_capture();
    randomize_command_fields(4'h1, hpu_id, iop_id, iop_src_addr, iop_dst_addr, req_flag, req_mode);

    drive_slave_command(
      .req_id  (REQ_ID_NOTIFY_ACK),
      .hpu_id  (hpu_id       ),
      .iop_id  (iop_id       ),
      .src_addr(iop_src_addr ),
      .dst_addr(iop_dst_addr ),
      .flag    (req_flag     ),
      .mode    (req_mode     )
    );
    wait(notify_ack_sent);
    flush_tx_output(1);

    build_expected_header(
      .target_mac     (MAC_ADDR_HPU1    ),
      .self_mac       (MAC_ADDR_SELF    ),
      .eth_len        (ETH_LEN_MIN      ),
      .req_id         (REQ_ID_NOTIFY_ACK),
      .hpu_id         (SELF_HPU_ID      ),
      .seq_num        (8'h0             ),
      .src_addr       (iop_src_addr     ),
      .dst_addr       (iop_dst_addr     ),
      .iop_id         (iop_id           ),
      .flag           (req_flag         ),
      .mode           (req_mode         ),
      .expected_header(expected_header  )
    );

    check_header(tx_frame_q, expected_header, $sformatf("%0d-NACK", scenario_id), error_header_check);
    $display("%t > %0d: NACK header verified", $time, scenario_id);

    // --- READ_REQ with specific fields ---
    clear_tx_capture();
    randomize_command_fields(4'h2, hpu_id, iop_id, iop_src_addr, iop_dst_addr, req_flag, req_mode);

    drive_master_command(
      .req_id  (REQ_ID_READ),
      .hpu_id  (hpu_id       ),
      .iop_id  (iop_id       ),
      .src_addr(iop_src_addr ),
      .dst_addr(iop_dst_addr ),
      .flag    (req_flag     ),
      .mode    (req_mode     )
    );
    wait(read_request_sent);
    flush_tx_output(1);

    build_expected_header(
      .target_mac     (MAC_ADDR_HPU2  ),
      .self_mac       (MAC_ADDR_SELF  ),
      .eth_len        (ETH_LEN_MIN    ),
      .req_id         (REQ_ID_READ    ),
      .hpu_id         (SELF_HPU_ID    ),
      .seq_num        (8'h0           ),
      .src_addr       (iop_src_addr   ),
      .dst_addr       (iop_dst_addr   ),
      .iop_id         (iop_id         ),
      .flag           (req_flag       ),
      .mode           (req_mode       ),
      .expected_header(expected_header)
    );
    check_header(tx_frame_q, expected_header, $sformatf("%0d-READ", scenario_id), error_header_check);
    $display("%t > %0d: READ_REQ header verified", $time, scenario_id);

    // --- CE first frame header with specific fields ---
    clear_tx_capture();
    randomize_command_fields(4'h2, hpu_id, iop_id, iop_src_addr, iop_dst_addr, req_flag, req_mode);

    fork
      drive_slave_command(
        .req_id  (REQ_ID_EMISSION),
        .hpu_id  (hpu_id       ),
        .iop_id  (iop_id       ),
        .src_addr(iop_src_addr ),
        .dst_addr(iop_dst_addr ),
        .flag    (req_flag     ),
        .mode    (req_mode     )
      );
      stream_ce_payload_continuous();
    join

    wait(ciphertext_sent);
    flush_tx_output(NB_PACKETS_FULL + 1);

    // Verify first frame header
    build_expected_header(
      .target_mac     (MAC_ADDR_HPU2  ),
      .self_mac       (MAC_ADDR_SELF  ),
      .eth_len        (ETH_LEN_MAX    ),
      .req_id         (REQ_ID_EMISSION),
      .hpu_id         (SELF_HPU_ID    ),
      .seq_num        (8'h0           ),
      .src_addr       (iop_src_addr   ),
      .dst_addr       (iop_dst_addr   ),
      .iop_id         (iop_id         ),
      .flag           (req_flag       ),
      .mode           (req_mode       ),
      .expected_header(expected_header)
    );

    for (int h = 0; h < NB_WORDS_CUST_HEADER_SIZE; h++) begin
      if (tx_all_words_q[h].tdata !== byte_swap(expected_header[h])) begin
        $display("%t > [ERROR:%0d-CE] header word %0d mismatch: got 0x%016h, expected 0x%016h",
                 $time, scenario_id, h, tx_all_words_q[h].tdata, byte_swap(expected_header[h]));
        error_header_check = 1'b1;
      end
    end

    $display("%t > %0d: CE header verified", $time, scenario_id);

    check_fsm_idle();
    scenario_end(scenario_id, clk);
  endtask

  // ---------------------------------------------------------------------------
  // SCENARIO: tkeep_user correctness
  // only two types checked here : NOTIFY & CE
  // ---------------------------------------------------------------------------
  task automatic run_scenario_tkeep_correctness();
    int word_index;
    int expected_frame_words;
    logic [ETHERNET_LEN-1:0] expected_eth_len;

    scenario_start(scenario_id, "tkeep_user correctness");

    // --- Small packet tkeep (NOTIFY) ---
    clear_tx_capture();
    randomize_command_fields(4'h1, hpu_id, iop_id, iop_src_addr, iop_dst_addr, req_flag, req_mode);

    drive_master_command(
      .req_id  (REQ_ID_NOTIFY),
      .hpu_id  (hpu_id       ),
      .iop_id  (iop_id       ),
      .src_addr(iop_src_addr ),
      .dst_addr(iop_dst_addr ),
      .flag    (req_flag     ),
      .mode    (req_mode     )
    );
    wait(notify_sent);
    flush_tx_output(1);

    for (int i = 0; i < tx_frame_q.size(); i++) begin
      if (i < NB_WORDS_MIN - 1) begin
        assert (tx_frame_q[i].tkeep_user == {3'b000, 8'hFF}) else begin
          $display("%t > [ERROR:%0d] NOTIFY word %0d tkeep mismatch: got 0x%03h, expected 0x0FF",
                   $time, scenario_id, i, tx_frame_q[i].tkeep_user);
          error_tkeep = 1'b1;
        end
      end else begin
        assert (tx_frame_q[i].tkeep_user == expected_last_tkeep) else begin
          $display("%t > [ERROR:%0d] NOTIFY last word tkeep mismatch: got 0x%03h, expected 0x%03h",
                   $time, scenario_id, tx_frame_q[i].tkeep_user, expected_last_tkeep);
          error_tkeep = 1'b1;
        end
      end
    end
    $display("%t > %0d: NOTIFY tkeep verified (last = 0x%03h)", $time, scenario_id, expected_last_tkeep);

    // --- CE frame tkeep ---
    clear_tx_capture();
    randomize_command_fields(4'h1, hpu_id, iop_id, iop_src_addr, iop_dst_addr, req_flag, req_mode);

    fork
      drive_slave_command(
        .req_id  (REQ_ID_EMISSION),
        .hpu_id  (hpu_id       ),
        .iop_id  (iop_id       ),
        .src_addr(iop_src_addr ),
        .dst_addr(iop_dst_addr ),
        .flag    (req_flag     ),
        .mode    (req_mode     )
      );
      stream_ce_payload_continuous();
    join

    wait(ciphertext_sent);
    flush_tx_output(NB_PACKETS_FULL + 1);

    // Verify tkeep for each frame
    word_index = 0;
    for (int frame = 0; frame <= NB_PACKETS_FULL; frame++) begin
      if (frame == NB_PACKETS_FULL) begin
        expected_frame_words = NB_WORDS_LAST_PACKET + NB_WORDS_CUST_HEADER_SIZE;
        expected_eth_len = ETH_LEN_LAST_PKT;
      end else begin
        expected_frame_words = NB_WORDS_CUST_HEADER_SIZE + NB_WORDS_PAYLOAD;
        expected_eth_len = ETH_LEN_MAX;
      end

      for (int w = 0; w < expected_frame_words; w++) begin
        if (word_index + w < tx_all_words_q.size()) begin
          if (w < expected_frame_words - 1) begin
            if (tx_all_words_q[word_index + w].tkeep_user !== {3'b000, 8'hFF}) begin
              $display("%t > [ERROR:%0d] frame %0d word %0d: tkeep mismatch: got 0x%03h, expected 0x0FF",
                       $time, scenario_id, frame, w, tx_all_words_q[word_index + w].tkeep_user);
              error_tkeep = 1'b1;
            end
          end else begin
            if (tx_all_words_q[word_index + w].tkeep_user !== 'hFF) begin
              $display("%t > [ERROR:%0d] frame %0d last word: tkeep mismatch: got 0x%03h, expected 0x%03h",
                       $time, scenario_id, frame, tx_all_words_q[word_index + w].tkeep_user, expected_last_tkeep);
              error_tkeep = 1'b1;
            end
          end
        end
      end

      word_index += expected_frame_words;
    end

    $display("%t > %0d: CE tkeep verified across all frames", $time, scenario_id);

    check_fsm_idle();
    scenario_end(scenario_id, clk);
  endtask

  // ---------------------------------------------------------------------------
  // SCENARIO: Back-to-back small packets (NOTIFY -> NACK)
  // ---------------------------------------------------------------------------
  task automatic run_scenario_b2b_small();
    logic [  IOP_ID_W-1:0] iop_id_1;
    logic [  IOP_ID_W-1:0] iop_id_2;
    logic [SRC_ADDR_W-1:0] src_addr_1;
    logic [SRC_ADDR_W-1:0] src_addr_2;
    logic [DST_ADDR_W-1:0] dst_addr_1;
    logic [DST_ADDR_W-1:0] dst_addr_2;
    logic [    FLAG_W-1:0] flag_1;
    logic [    FLAG_W-1:0] flag_2;
    logic [    MODE_W-1:0] mode_1;
    logic [    MODE_W-1:0] mode_2;

    clear_tx_capture();
    scenario_start(scenario_id, "Back-to-back small packets (NOTIFY -> NACK)");

    iop_id_1   = $urandom();
    src_addr_1 = $urandom();
    dst_addr_1 = $urandom();
    flag_1     = $urandom();
    mode_1     = $urandom();

    iop_id_2   = $urandom();
    src_addr_2 = $urandom();
    dst_addr_2 = $urandom();
    flag_2     = $urandom();
    mode_2     = $urandom();

    // Drive NOTIFY (master command) - blocks until consumed
    drive_master_command(
      .req_id  (REQ_ID_NOTIFY),
      .hpu_id  (4'h1         ),
      .iop_id  (iop_id_1     ),
      .src_addr(src_addr_1   ),
      .dst_addr(dst_addr_1   ),
      .flag    (flag_1       ),
      .mode    (mode_1       )
    );

    // While NOTIFY is still transmitting, present NACK on slave interface
    // so the FSM picks it up immediately when returning to IDLE
    @(posedge clk);
    slave_command.req_id       <= REQ_ID_NOTIFY_ACK;
    slave_command.hpu_id       <= 4'h2;
    slave_command.iop_id       <= iop_id_2;
    slave_command.src_addr     <= src_addr_2;
    slave_command.dst_addr     <= dst_addr_2;
    slave_command.rsvd         <= 'h0;
    slave_command.flag         <= flag_2;
    slave_command.mode         <= mode_2;
    slave_command.seq_num      <= '0;
    slave_command.src_mac_addr <= '0;
    slave_command_vld          <= 1'b1;

    // Wait for NOTIFY to complete
    wait(notify_sent);
    $display("%t > %0d: NOTIFY sent", $time, scenario_id);

    // NACK should be consumed immediately (FSM: IDLE -> ST_NACK)
    do @(posedge clk); while (!slave_command_rdy);
    @(posedge clk);
    slave_command_vld <= 1'b0;

    wait(notify_ack_sent);
    $display("%t > %0d: NACK sent", $time, scenario_id);

    flush_tx_output(2);

    // Verify 2 frames transmitted back-to-back
    assert (tx_frame_count == 2) else begin
      $display("[ERROR:%0d] expected 2 frames, got %0d", scenario_id, tx_frame_count);
      error_b2b = 1'b1;
    end

    check_fsm_idle();
    scenario_end(scenario_id, clk);
  endtask

  // ---------------------------------------------------------------------------
  // SCENARIO: Back-to-back CE emissions
  // ---------------------------------------------------------------------------
  task automatic run_scenario_b2b_ce();
    scenario_start(scenario_id, "Back-to-back CE emissions");

    // --- First CE ---
    clear_tx_capture();
    randomize_command_fields(4'h1, hpu_id, iop_id, iop_src_addr, iop_dst_addr, req_flag, req_mode);

    drive_slave_command(
      .req_id  (REQ_ID_EMISSION),
      .hpu_id  (hpu_id       ),
      .iop_id  (iop_id       ),
      .src_addr(iop_src_addr ),
      .dst_addr(iop_dst_addr ),
      .flag    (req_flag     ),
      .mode    (req_mode     )
    );

    stream_ce_payload_continuous();
    wait(ciphertext_sent);
    flush_tx_output(NB_PACKETS_FULL + 1);

    assert (tx_frame_count == NB_PACKETS_FULL + 1) else begin
      $display("[ERROR:%0d] first CE: expected %0d frames, got %0d", scenario_id, NB_PACKETS_FULL + 1, tx_frame_count);
      error_b2b = 1'b1;
    end

    $display("%t > %0d: first CE completed (%0d frames)", $time, scenario_id, tx_frame_count);

    // --- Second CE (minimal gap) ---
    clear_tx_capture();
    randomize_command_fields(4'h2, hpu_id, iop_id, iop_src_addr, iop_dst_addr, req_flag, req_mode);

    drive_slave_command(
      .req_id  (REQ_ID_EMISSION),
      .hpu_id  (hpu_id         ),
      .iop_id  (iop_id         ),
      .src_addr(iop_src_addr   ),
      .dst_addr(iop_dst_addr   ),
      .flag    (req_flag       ),
      .mode    (req_mode       )
    );

    stream_ce_payload_continuous();
    wait(ciphertext_sent);
    flush_tx_output(NB_PACKETS_FULL + 1);

    // Verify second CE
    check_ce_multiframe_headers(MAC_ADDR_HPU2, $sformatf("%0d-2nd", scenario_id), error_b2b);

    check_fsm_idle();
    scenario_end(scenario_id, clk);
  endtask

  // ---------------------------------------------------------------------------
  // SCENARIO: Mid-frame backpressure for CE
  // ---------------------------------------------------------------------------
  task automatic run_scenario_mid_frame_backpressure();
    clear_tx_capture();
    scenario_start(scenario_id, "Mid-frame backpressure for CE");
    randomize_command_fields(4'h1, hpu_id, iop_id, iop_src_addr, iop_dst_addr, req_flag, req_mode);

    // Spawn backpressure controller in background
    fork
      begin
        int word_cnt;
        word_cnt = 0;
        while (word_cnt < NB_WORDS_CUST_HEADER_SIZE + 5) begin
          @(posedge clk);
          if (qsfp_tx_tvalid && qsfp_tx_tready) word_cnt++;
        end
        force_tready = 1'b1; force_tready_val = 1'b0;
        repeat (20) @(posedge clk);
        force_tready = 1'b0;
      end
    join_none

    // Sequential flow (same pattern as working CE scenarios)
    drive_slave_command(
      .req_id  (REQ_ID_EMISSION),
      .hpu_id  (hpu_id         ),
      .iop_id  (iop_id         ),
      .src_addr(iop_src_addr   ),
      .dst_addr(iop_dst_addr   ),
      .flag    (req_flag       ),
      .mode    (req_mode       )
    );

    stream_ce_payload_continuous();
    wait(ciphertext_sent);
    flush_tx_output(NB_PACKETS_FULL + 1);

    assert (tx_frame_count == NB_PACKETS_FULL + 1) else begin
      $display("[ERROR:%0d] expected %0d frames, got %0d", scenario_id, NB_PACKETS_FULL + 1, tx_frame_count);
      error_mid_bp = 1'b1;
    end

    assert (format_error.formatter_error == 1'b0) else begin
      $display("%t > [ERROR:%0d] formatter_error raised during mid-frame backpressure", $time, scenario_id);
      error_mid_bp = 1'b1;
    end

    check_fsm_idle();
    scenario_end(scenario_id, clk);
  endtask

  // ---------------------------------------------------------------------------
  // SCENARIO: Max hpu_id (NB_MAX_HPU-1)
  // ---------------------------------------------------------------------------
  task automatic run_scenario_max_hpu_id();
    clear_tx_capture();
    scenario_start(scenario_id, "Max hpu_id (NB_MAX_HPU-1)");
    randomize_command_fields(NB_MAX_HPU - 1, hpu_id, iop_id, iop_src_addr, iop_dst_addr, req_flag, req_mode);

    drive_master_command(
      .req_id  (REQ_ID_NOTIFY),
      .hpu_id  (hpu_id       ),
      .iop_id  (iop_id       ),
      .src_addr(iop_src_addr ),
      .dst_addr(iop_dst_addr ),
      .flag    (req_flag     ),
      .mode    (req_mode     )
    );

    wait(notify_sent);
    flush_tx_output(1);

    check_small_packet(MAC_ADDR_HPU7, REQ_ID_NOTIFY, $sformatf("%0d-MAX_HPU", scenario_id), error_header_check);

    check_fsm_idle();
    scenario_end(scenario_id, clk);
  endtask

  // ---------------------------------------------------------------------------
  // SCENARIO: Reset during active transmission
  // ---------------------------------------------------------------------------
  task automatic run_scenario_reset_mid_tx();
    clear_tx_capture();
    scenario_start(scenario_id, "Reset during active transmission");

    // Drive NOTIFY directly (avoid task to prevent fork issues on reset)
    @(posedge clk);
    master_command.req_id       <= REQ_ID_NOTIFY;
    master_command.hpu_id       <= 4'h1;
    master_command.iop_id       <= $urandom();
    master_command.src_addr     <= $urandom();
    master_command.dst_addr     <= $urandom();
    master_command.rsvd         <= 'h0;
    master_command.flag         <= $urandom();
    master_command.mode         <= $urandom();
    master_command.seq_num      <= '0;
    master_command.src_mac_addr <= '0;
    master_command_vld          <= 1'b1;

    // Wait for command to be consumed
    do @(posedge clk); while (!master_command_rdy);
    master_command_vld <= 1'b0;

    // Wait for a few words to be transmitted
    begin
      int word_cnt;
      word_cnt = 0;
      while (word_cnt < 3) begin
        @(posedge clk);
        if (qsfp_tx_tvalid && qsfp_tx_tready) word_cnt++;
      end
    end

    // Assert reset mid-frame
    a_rst_n = 1'b0;
    repeat (5) @(posedge clk);
    a_rst_n = 1'b1;
    repeat (10) @(posedge clk);
    tb_init();
    repeat (5) @(posedge clk);

    // Verify clean recovery
    assert (stat.fsm_formatter == 3'b000) else begin
      $display("%t > [ERROR:%0d] FSM not in IDLE after reset (state=%0b)", $time, scenario_id, stat.fsm_formatter);
      error_reset_mid_tx = 1'b1;
    end

    assert (!qsfp_tx_tvalid) else begin
      $display("%t > [ERROR:%0d] tvalid still asserted after reset", $time, scenario_id);
      error_reset_mid_tx = 1'b1;
    end

    // Verify DUT can send a normal packet after recovery
    clear_tx_capture();
    drive_master_command(
      .req_id  (REQ_ID_NOTIFY),
      .hpu_id  (4'h1         ),
      .iop_id  ($urandom()   ),
      .src_addr($urandom()   ),
      .dst_addr($urandom()   ),
      .flag    ($urandom()   ),
      .mode    ($urandom()   )
    );

    wait(notify_sent);
    flush_tx_output(1);

    assert (tx_frame_count == 1) else begin
      $display("[ERROR:%0d] expected 1 frame after reset recovery, got %0d", scenario_id, tx_frame_count);
      error_reset_mid_tx = 1'b1;
    end

    check_fsm_idle();
    scenario_end(scenario_id, clk);
  endtask

  // ---------------------------------------------------------------------------
  // SCENARIO: Invalid req_id discard (slave + master)
  // ---------------------------------------------------------------------------
  task automatic run_scenario_invalid_req_id_discard();
    logic [REQ_ID_W-1:0] invalid_req_id;

    clear_tx_capture();
    scenario_start(scenario_id, "Invalid req_id discard");

    // Use a req_id that matches none of the valid opcodes
    invalid_req_id = 4'hF;

    // --- Invalid slave command ---
    @(posedge clk);
    slave_command.req_id       <= invalid_req_id;
    slave_command.hpu_id       <= 4'h1;
    slave_command.iop_id       <= 8'hDE;
    slave_command.src_addr     <= 16'hAAAA;
    slave_command.dst_addr     <= 16'hBBBB;
    slave_command.rsvd         <= 'h0;
    slave_command.flag         <= 'h0;
    slave_command.mode         <= 'h0;
    slave_command.seq_num      <= '0;
    slave_command.src_mac_addr <= '0;
    slave_command_vld          <= 1'b1;

    // slave_discard pulse should consume the command
    do @(posedge clk); while (!slave_command_rdy);
    @(posedge clk);
    slave_command_vld <= 1'b0;
    $display("%t > %0d: invalid slave command discarded", $time, scenario_id);

    repeat (10) @(posedge clk);

    // FSM must stay IDLE, no TX activity
    assert (stat.fsm_formatter == 3'b000) else begin
      $display("[ERROR:%0d] FSM left IDLE after invalid slave command", scenario_id);
      error_discard = 1'b1;
    end
    assert (tx_frame_count == 0) else begin
      $display("[ERROR:%0d] unexpected TX frame after invalid slave command", scenario_id);
      error_discard = 1'b1;
    end

    // --- Invalid master command ---
    @(posedge clk);
    master_command.req_id       <= invalid_req_id;
    master_command.hpu_id       <= 4'h2;
    master_command.iop_id       <= 8'hEF;
    master_command.src_addr     <= 16'hCCCC;
    master_command.dst_addr     <= 16'hDDDD;
    master_command.rsvd         <= 'h0;
    master_command.flag         <= 'h0;
    master_command.mode         <= 'h0;
    master_command.seq_num      <= '0;
    master_command.src_mac_addr <= '0;
    master_command_vld          <= 1'b1;

    do @(posedge clk); while (!master_command_rdy);
    @(posedge clk);
    master_command_vld <= 1'b0;
    $display("%t > %0d: invalid master command discarded", $time, scenario_id);

    repeat (10) @(posedge clk);

    assert (stat.fsm_formatter == 3'b000) else begin
      $display("[ERROR:%0d] FSM left IDLE after invalid master command", scenario_id);
      error_discard = 1'b1;
    end
    assert (tx_frame_count == 0) else begin
      $display("[ERROR:%0d] unexpected TX frame after invalid master command", scenario_id);
      error_discard = 1'b1;
    end

    // --- Valid command after discard: verify recovery ---
    clear_tx_capture();
    randomize_command_fields(4'h1, hpu_id, iop_id, iop_src_addr, iop_dst_addr, req_flag, req_mode);

    drive_master_command(
      .req_id  (REQ_ID_NOTIFY),
      .hpu_id  (hpu_id       ),
      .iop_id  (iop_id       ),
      .src_addr(iop_src_addr ),
      .dst_addr(iop_dst_addr ),
      .flag    (req_flag     ),
      .mode    (req_mode     )
    );

    wait(notify_sent);
    flush_tx_output(1);

    assert (tx_frame_count == 1) else begin
      $display("[ERROR:%0d] expected 1 frame after discard recovery, got %0d", scenario_id, tx_frame_count);
      error_discard = 1'b1;
    end

    check_fsm_idle();
    scenario_end(scenario_id, clk);
  endtask

// ============================================================================================== --
// Main test sequence
// ============================================================================================== --
  initial begin
    tb_init();
    scenario_id = 0;
    repeat (10) @(posedge clk);
    $display("\n\n"); // separating from xpm fifo information

    run_scenario_notify();
    run_scenario_notify_ack();
    run_scenario_read_req();
    run_scenario_ce_emission();
    run_scenario_prio_ce_notify();
    run_scenario_prio_nack_read_notify();
    run_scenario_tx_backpressure();
    run_scenario_ce_multiframe_bp();
    run_scenario_fifo_starvation();
    run_scenario_header_fields();
    run_scenario_tkeep_correctness();
    run_scenario_b2b_small();
    run_scenario_b2b_ce();
    run_scenario_mid_frame_backpressure();
    run_scenario_max_hpu_id();
    run_scenario_invalid_req_id_discard();
    run_scenario_reset_mid_tx();

    $display("\n==================================================================================================");
    $display("  All scenarios executed");
    $display("==================================================================================================");
    repeat (20) @(posedge clk);
    end_of_test = 1'b1;
  end


// ============================================================================================== --
// SVA
// XSIM is fast enough for SVA in this test
// ============================================================================================== --

  // -----------------------------------------------------------------------------------------
  // AXI-Stream: tvalid must remain stable when tready is low
  // -----------------------------------------------------------------------------------------
  property axis_tvalid_stable;
    @(posedge clk) disable iff (~s_rstn)
    (qsfp_tx_tvalid && !qsfp_tx_tready) |=> $stable(qsfp_tx_tvalid);
  endproperty

  // AXI-Stream: tdata must remain stable when tvalid is high and tready is low
  property axis_tdata_stable;
    @(posedge clk) disable iff (~s_rstn)
    (qsfp_tx_tvalid && !qsfp_tx_tready) |=> $stable(qsfp_tx_tdata);
  endproperty

  // AXI-Stream: tkeep_user must remain stable when tvalid is high and tready is low
  property axis_tkeep_stable;
    @(posedge clk) disable iff (~s_rstn)
    (qsfp_tx_tvalid && !qsfp_tx_tready) |=> $stable(qsfp_tx_tkeep_user);
  endproperty

  // AXI-Stream: tlast must remain stable when tvalid is high and tready is low
  property axis_tlast_stable;
    @(posedge clk) disable iff (~s_rstn)
    (qsfp_tx_tvalid && !qsfp_tx_tready) |=> $stable(qsfp_tx_tlast);
  endproperty

  // -----------------------------------------------------------------------------------------
  // tlast implies tvalid
  // -----------------------------------------------------------------------------------------
  property tlast_implies_tvalid;
    @(posedge clk) disable iff (~s_rstn)
    qsfp_tx_tlast |-> qsfp_tx_tvalid;
  endproperty

  // // -----------------------------------------------------------------------------------------
  // // After tlast is accepted (tvalid & tready & tlast), tvalid must drop the next cycle
  // // in our case this is true, there is never back to back frames
  // // -----------------------------------------------------------------------------------------
  // property no_valid_after_last;
  //   @(posedge clk) disable iff (~s_rstn)
  //   (qsfp_tx_tvalid && qsfp_tx_tready && qsfp_tx_tlast) |=> !qsfp_tx_tvalid;
  // endproperty

  // -----------------------------------------------------------------------------------------
  // tvalid must NOT drop mid-frame: after a successful transfer that is not
  // the last word, tvalid must remain high on the next cycle.
  // This catches FIFO starvation / frame-gating failures that would cause
  // MRMAC to drop the frame.
  // -----------------------------------------------------------------------------------------
  property tvalid_no_drop_before_tlast;
    @(posedge clk) disable iff (~s_rstn)
    (qsfp_tx_tvalid && qsfp_tx_tready && !qsfp_tx_tlast) |=> qsfp_tx_tvalid;
  endproperty

  // Assertion instances
  assert_tvalid_stable : assert property (axis_tvalid_stable)
    else begin $error("%t > [ERROR:SVA] tvalid changed while tready=0", $time); error_assert = 1'b1; end

  assert_tdata_stable : assert property (axis_tdata_stable)
    else begin $error("%t > [ERROR:SVA] tdata changed while tvalid=1 & tready=0", $time); error_assert = 1'b1; end

  assert_tkeep_stable : assert property (axis_tkeep_stable)
    else begin $error("%t > [ERROR:SVA] tkeep_user changed while tvalid=1 & tready=0", $time); error_assert = 1'b1; end

  assert_tlast_stable : assert property (axis_tlast_stable)
    else begin $error("%t > [ERROR:SVA] tlast changed while tvalid=1 & tready=0", $time); error_assert = 1'b1; end

  assert_tlast_implies_tvalid : assert property (tlast_implies_tvalid)
    else begin $error("%t > [ERROR:SVA] tlast without tvalid", $time); error_assert = 1'b1; end

  // assert_no_valid_after_last : assert property (no_valid_after_last)
  //   else begin $error("%t > [ERROR:SVA] tvalid still asserted after tlast accepted", $time); error_assert = 1'b1; end

  assert_tvalid_no_drop_before_tlast : assert property (tvalid_no_drop_before_tlast)
    else begin $error("%t > [ERROR:SVA] tvalid dropped before tlast (FIFO starvation)", $time); error_assert = 1'b1; end

endmodule
