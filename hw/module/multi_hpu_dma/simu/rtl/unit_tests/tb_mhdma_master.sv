// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Unit testbench for mhdma_master
// ----------------------------------------------------------------------------------------------
// This testbench directly instantiates and exercises the mhdma_master module.
// It verifies:
//   - Notify TX FSM (NTX): basic flow, timeout/retry
//   - Read Request FSM (RR): basic flow, timeout/retry
//   - CDC FIFOs: requests cross from clk_mhdma_cfg to clk_mhdma
//   - Ciphertext reception: decoder payload, seq_num validation, zero-padding
//   - AXI4 HBM write: deserialization, page-boundary splitting, burst management
//   - Write response tracking: per-PC B response counting
//   - Interrupt generation: interrupt_read_request after ciphertext written to HBM
//   - Statistics counters and error flags
//
// Scenarios:
//   > Notify TX basic flow
//   > Notify TX timeout and retry
//   > Read Request basic flow
//   > Read Request timeout and retry
//   > Seq num mismatch handling
//   > AXI4 page boundary splitting
//   > AXI4 write error handling
//   > ce_reception_ready signaling
//   > Multiple sequential notify requests
//   > Multiple sequential read requests
//   > Statistics counters
//   > Error reset
//
//
// TODO  clear_axi4_captures
// ==============================================================================================

`resetall
`timescale 1ns/10ps

module tb_mhdma_master;
  import mhdma_pkg::*;
  import axi_if_shell_axil_pkg::*;
  import axi_if_common_param_pkg::*;
  import axi_if_mhdma_axi_pkg::*;
  import pem_common_param_pkg::*;

  `include "tb_mhdma_tasks.sv"

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int CLK_HALF_PERIOD_A   = 4;   // cfg clock: slower
  localparam int CLK_HALF_PERIOD_B   = 1;   // mrmac clock: faster
  localparam int ARST_ACTIVATION     = 17;
  localparam int CDC_SYNC_STAGES     = 2;

  // Timeout durations for the test (keep them short for simulation speed)
  // NOTE: TIMEOUT_READ_REQ must exceed the full ciphertext transfer time !
  //   (NB_PACKETS_FULL+1) packets of data + AXI4 pipeline drain + B responses
  localparam int TIMEOUT_NOTIFY      = 200;
  localparam int TIMEOUT_READ_REQ    = 10_000;

  // Derived constants from the DUT

// ============================================================================================== --
// clock, reset
// ============================================================================================== --
  bit clk_mhdma_cfg;
  bit clk_mhdma;

  initial begin
    clk_mhdma_cfg   = 1'b0;
    clk_mhdma = 1'b0;
  end

  always begin
    #CLK_HALF_PERIOD_A clk_mhdma_cfg = ~clk_mhdma_cfg;
  end
  always begin
    #CLK_HALF_PERIOD_B clk_mhdma = ~clk_mhdma;
  end

  bit a_rst_n;         // asynchronous reset
  bit s_rstn_cfg;      // synchronous reset in cfg domain
  bit s_rstn_mhdma;    // synchronous reset in mrmac domain

  initial begin
    a_rst_n = 1'b0;
    #ARST_ACTIVATION a_rst_n = 1'b1;
  end

  always_ff @(posedge clk_mhdma_cfg)   s_rstn_cfg   <= a_rst_n;
  always_ff @(posedge clk_mhdma) s_rstn_mhdma <= a_rst_n;

// ============================================================================================== --
// End of test
// ============================================================================================== --
  bit end_of_test;

  initial begin
    wait (end_of_test);
    @(posedge clk_mhdma_cfg) $display("%t > SUCCEED !", $time);
    $finish;
  end

// ============================================================================================== --
// Error
// ============================================================================================== --
  bit error;
  bit error_scenario;
  bit error_assert;
  bit error_timeout_watchdog;

  assign error = error_scenario | error_assert | error_timeout_watchdog;

  always_ff @(posedge clk_mhdma_cfg)
    if (error) begin
      $display("%t > FAILURE !", $time);
      $finish;
    end

  // Global watchdog: prevent simulation from hanging, some tests here are waiting on failure
  initial begin
    #5_000_000;
    $display("%t > FAILURE: Global watchdog timeout!", $time);
    error_timeout_watchdog = 1'b1;
  end

// ============================================================================================== --
// DUT signals
// ============================================================================================== --
  // AXI4 write channel (per PC)
  logic [ETH_PC-1:0][AXI4_ID_W-1:0]    m_axi4_awid;
  logic [ETH_PC-1:0][AXI4_ADD_W-1:0]   m_axi4_awaddr;
  logic [ETH_PC-1:0][AXI4_LEN_W-1:0]   m_axi4_awlen;
  logic [ETH_PC-1:0][AXI4_SIZE_W-1:0]  m_axi4_awsize;
  logic [ETH_PC-1:0][AXI4_BURST_W-1:0] m_axi4_awburst;
  logic [ETH_PC-1:0]                   m_axi4_awvalid;
  logic [ETH_PC-1:0]                   m_axi4_awready;

  logic [ETH_PC-1:0][AXI4_DATA_W-1:0]  m_axi4_wdata;
  logic [ETH_PC-1:0][AXI4_STRB_W-1:0]  m_axi4_wstrb;
  logic [ETH_PC-1:0]                   m_axi4_wlast;
  logic [ETH_PC-1:0]                   m_axi4_wvalid;
  logic [ETH_PC-1:0]                   m_axi4_wready;

  logic [ETH_PC-1:0][AXI4_ID_W-1:0]    m_axi4_bid;
  logic [ETH_PC-1:0][AXI4_RESP_W-1:0]  m_axi4_bresp;
  logic [ETH_PC-1:0]                   m_axi4_bvalid;
  logic [ETH_PC-1:0]                   m_axi4_bready;

  // regf interface
  logic [ETH_PC-1:0][2*REG_DATA_W-1:0] regf_ct_mem_addr;
  logic               [REG_DATA_W-1:0] regf_req_id;
  logic               [REG_DATA_W-1:0] regf_req_addr;
  logic               [REG_DATA_W-1:0] regf_read_req_id;
  logic               [REG_DATA_W-1:0] regf_read_addr;
  logic               [REG_DATA_W-1:0] regf_timeout_duration_notify;
  logic               [REG_DATA_W-1:0] regf_timeout_duration_read_req;

  // register control
  logic                                received_req;
  logic                                request_consumed;

  // interrupt
  logic                                clear_interrupt_rr;
  logic                                interrupt_read_request;

  // decoder interface
  command_t                            decoded_command;
  logic                                decoded_command_vld;
  logic                                decoded_command_rdy;
  logic             [MRMAC_AXIS_W-1:0] decoder_rx_tdata;
  logic                                decoder_rx_tvalid;
  logic                                notify_ack_received;

  // formatter interface
  command_t                            master_command;
  logic                                master_command_vld;
  logic                                master_command_rdy;
  logic                                read_request_sent;
  logic                                notify_sent;
  logic                                ce_reception_ready;

  // errors / stats
  master_error_t                       master_error;
  logic                                rst_errors;
  master_stat_t                        stat;
  master_stat_rst_t                    stat_rst;

// ============================================================================================== --
// DUT instantiation
// ============================================================================================== --
  mhdma_master #(
    .CDC_SYNC_STAGES (CDC_SYNC_STAGES)
  ) mhdma_master (
    .clk_mhdma_cfg                       (clk_mhdma_cfg                       ),
    .resetn_mhdma_cfg                    (s_rstn_cfg                    ),
    .clk_mhdma                     (clk_mhdma                     ),
    .resetn_mhdma                  (s_rstn_mhdma                  ),
    // AXI4 write
    .m_axi4_awid                   (m_axi4_awid                   ),
    .m_axi4_awaddr                 (m_axi4_awaddr                 ),
    .m_axi4_awlen                  (m_axi4_awlen                  ),
    .m_axi4_awsize                 (m_axi4_awsize                 ),
    .m_axi4_awburst                (m_axi4_awburst                ),
    .m_axi4_awvalid                (m_axi4_awvalid                ),
    .m_axi4_awready                (m_axi4_awready                ),
    .m_axi4_wdata                  (m_axi4_wdata                  ),
    .m_axi4_wstrb                  (m_axi4_wstrb                  ),
    .m_axi4_wlast                  (m_axi4_wlast                  ),
    .m_axi4_wvalid                 (m_axi4_wvalid                 ),
    .m_axi4_wready                 (m_axi4_wready                 ),
    .m_axi4_bid                    (m_axi4_bid                    ),
    .m_axi4_bresp                  (m_axi4_bresp                  ),
    .m_axi4_bvalid                 (m_axi4_bvalid                 ),
    .m_axi4_bready                 (m_axi4_bready                 ),
    // regf
    .regf_ct_mem_addr              (regf_ct_mem_addr              ),
    .regf_req_id                   (regf_req_id                   ),
    .regf_req_addr                 (regf_req_addr                 ),
    .regf_read_req_id              (regf_read_req_id              ),
    .regf_read_addr                (regf_read_addr                ),
    .regf_timeout_duration_notify  (regf_timeout_duration_notify  ),
    .regf_timeout_duration_read_req(regf_timeout_duration_read_req),
    // register control
    .received_req                  (received_req                  ),
    .request_consumed              (request_consumed              ),
    // interrupt
    .clear_interrupt_rr            (clear_interrupt_rr            ),
    .interrupt_read_request        (interrupt_read_request        ),
    // decoder
    .decoded_command               (decoded_command               ),
    .decoded_command_vld           (decoded_command_vld           ),
    .decoded_command_rdy           (decoded_command_rdy           ),
    .decoder_rx_tdata              (decoder_rx_tdata              ),
    .decoder_rx_tvalid             (decoder_rx_tvalid             ),
    .notify_ack_received           (notify_ack_received           ),
    // formatter
    .master_command                (master_command                ),
    .master_command_vld            (master_command_vld            ),
    .master_command_rdy            (master_command_rdy            ),
    .read_request_sent             (read_request_sent             ),
    .notify_sent                   (notify_sent                   ),
    .ce_reception_ready            (ce_reception_ready            ),
    // errors
    .master_error                  (master_error                  ),
    .rst_errors                    (rst_errors                    ),
    // stats
    .stat                          (stat                          ),
    .stat_rst                      (stat_rst                      )
  );

// ============================================================================================== --
// Simple AXI4 write responder
// ============================================================================================== --
// Accepts AW and W channels, returns B responses with configurable delay and response type.
// Tracks per-PC write addresses and data for verification.

  // Configurable B response delay (in mrmac clock cycles) and response type
  int unsigned axi4_bresp_delay [ETH_PC];
  logic [AXI4_RESP_W-1:0] axi4_bresp_type [ETH_PC];

  // Write data capture (per PC): queue of addresses and data words written
  logic [AXI4_ADD_W-1:0]  axi4_aw_captured_addr [ETH_PC][$];
  logic [AXI4_LEN_W-1:0]  axi4_aw_captured_len  [ETH_PC][$];
  logic [AXI4_DATA_W-1:0] axi4_w_captured_data  [ETH_PC][$];
  int unsigned            axi4_b_pending_count  [ETH_PC];

  generate
    for (genvar gen_pc = 0; gen_pc < ETH_PC; gen_pc++) begin : gen_axi4_responder

      // AW channel: always ready
      assign m_axi4_awready[gen_pc] = 1'b1;

      // W channel: always ready
      assign m_axi4_wready[gen_pc] = 1'b1;

      // Capture AW transactions
      always @(posedge clk_mhdma) begin
        if (m_axi4_awvalid[gen_pc] && m_axi4_awready[gen_pc]) begin
          axi4_aw_captured_addr[gen_pc].push_back(m_axi4_awaddr[gen_pc]);
          axi4_aw_captured_len[gen_pc].push_back(m_axi4_awlen[gen_pc]);
        end
      end

      // Capture W transactions
      always @(posedge clk_mhdma) begin
        if (m_axi4_wvalid[gen_pc] && m_axi4_wready[gen_pc]) begin
          axi4_w_captured_data[gen_pc].push_back(m_axi4_wdata[gen_pc]);
        end
      end

      // B response generation: when we see wlast, schedule a B response
      // Simple: respond after configurable delay
      initial begin
        m_axi4_bvalid[gen_pc]    = 1'b0;
        m_axi4_bresp[gen_pc]     = AXI4_OKAY;
        m_axi4_bid[gen_pc]       = '0;
        axi4_bresp_delay[gen_pc] = 2;
        axi4_bresp_type[gen_pc]  = AXI4_OKAY;

        forever begin
          @(posedge clk_mhdma);
          if (m_axi4_wvalid[gen_pc] && m_axi4_wready[gen_pc] && m_axi4_wlast[gen_pc]) begin
            // Schedule B response after delay
            repeat (axi4_bresp_delay[gen_pc]) @(posedge clk_mhdma);
            m_axi4_bvalid[gen_pc] = 1'b1;
            m_axi4_bresp[gen_pc]  = axi4_bresp_type[gen_pc];
            m_axi4_bid[gen_pc]    = MHDMA_AXI_ARID;
            @(posedge clk_mhdma);
            while (!m_axi4_bready[gen_pc]) @(posedge clk_mhdma);
            m_axi4_bvalid[gen_pc] = 1'b0;
          end
        end
      end

    end
  endgenerate

// ============================================================================================== --
// Helper tasks
// ============================================================================================== --

  // --------------------------------------------------------------------------------------------- --
  // Initialize all testbench signals to idle state
  // --------------------------------------------------------------------------------------------- --
  task automatic tb_init();
    begin
      regf_req_id                   = '0;
      regf_req_addr                 = '0;
      regf_timeout_duration_notify  = TIMEOUT_NOTIFY;
      regf_timeout_duration_read_req= TIMEOUT_READ_REQ;
      received_req                  = 1'b0;
      clear_interrupt_rr            = 1'b0;

      decoded_command               = '0;
      decoded_command_vld           = 1'b0;
      decoder_rx_tdata              = '0;
      decoder_rx_tvalid             = 1'b0;
      notify_ack_received           = 1'b0;

      master_command_rdy            = 1'b0;
      read_request_sent             = 1'b0;
      notify_sent                   = 1'b0;

      rst_errors                    = 1'b0;
      stat_rst                      = '0;

      // Set HBM base addresses: page-aligned per PC
      for (int pc = 0; pc < ETH_PC; pc++) begin
        regf_ct_mem_addr[pc] = 64'h0000_0000_0001_0000 + pc * 64'h0000_0000_0010_0000;
      end

      // Reset AXI4 responder config
      for (int pc = 0; pc < ETH_PC; pc++) begin
        axi4_bresp_delay[pc] = 2;
        axi4_bresp_type[pc]  = AXI4_OKAY;
      end
    end
  endtask

  // --------------------------------------------------------------------------------------------- --
  // Inject a register request in the cfg clock domain
  // req_type: REQ_ID_NOTIFY or REQ_ID_READ
  // --------------------------------------------------------------------------------------------- --
  task automatic inject_regf_request(
    input logic [IOP_ID_W-1:0]   iop_id,
    input logic [REQ_ID_W-1:0]   req_type,
    input logic [HPU_ID_W-1:0]   hpu_id,
    input logic [MODE_W-1:0]     mode,
    input logic [FLAG_W-1:0]     flag,
    input logic [SRC_ADDR_W-1:0] src_addr,
    input logic [DST_ADDR_W-1:0] dst_addr
  );
    begin
      @(posedge clk_mhdma_cfg);
      regf_req_id   = {iop_id, req_type, hpu_id, mode, flag, 8'h0};
      regf_req_addr = {dst_addr, src_addr};
      received_req  = 1'b1;
      @(posedge clk_mhdma_cfg);
      received_req  = 1'b0;
    end
  endtask

  // wait tasks are using directly an output of the DUT, easier to not be merged
  task automatic wait_master_command_vld(
    input  int   max_cycles,
    output logic timed_out
  );
    int cnt;
    begin
      timed_out = 1'b0;
      cnt = 0;
      while (!master_command_vld && cnt < max_cycles) begin
        @(posedge clk_mhdma);
        cnt++;
      end
      if (cnt >= max_cycles) timed_out = 1'b1;
    end
  endtask

  // wait tasks are using directly an output of the DUT, easier to not be merged
  task automatic wait_interrupt_rr(
    input  int   max_cycles,
    output logic timed_out
  );
    int cnt;
    begin
      timed_out = 1'b0;
      cnt = 0;
      while (!interrupt_read_request && cnt < max_cycles) begin
        @(posedge clk_mhdma);
        cnt++;
      end
      if (cnt >= max_cycles) timed_out = 1'b1;
    end
  endtask

  // --------------------------------------------------------------------------------------------- --
  // Feed decoded CE emission command + payload data through decoder interface (mrmac domain)
  // Payload size is auto-computed from seq_num (like send_ciphertext_emission_packet):
  //   seq_num == NB_PACKETS_FULL  -> NB_WORDS_LAST_PACKET (last, smaller packet)
  //   otherwise                   -> NB_WORDS_PAYLOAD     (full-size packet)
  // --------------------------------------------------------------------------------------------- --
  task automatic feed_ce_packet(
    input logic [SEQ_NUM_W-1:0]  seq_num,
    input logic [IOP_ID_W-1:0]   iop_id,
    input logic [HPU_ID_W-1:0]   hpu_id,
    input logic [MODE_W-1:0]     mode,
    input logic [FLAG_W-1:0]     flag,
    input logic [SRC_ADDR_W-1:0] src_addr,
    input logic [DST_ADDR_W-1:0] dst_addr
  );
    int nwords;
    begin
      nwords = (seq_num == NB_PACKETS_FULL) ? NB_WORDS_LAST_PACKET : NB_WORDS_PAYLOAD;

      // Present decoded command
      @(posedge clk_mhdma);
      decoded_command.req_id   = REQ_ID_EMISSION;
      decoded_command.seq_num  = seq_num;
      decoded_command.iop_id   = iop_id;
      decoded_command.hpu_id   = hpu_id;
      decoded_command.src_addr = src_addr;
      decoded_command.dst_addr = dst_addr;
      decoded_command.mode     = mode;
      decoded_command.flag     = flag;
      decoded_command.rsvd     = '0;
      decoded_command.src_mac_addr = '0;
      decoded_command_vld      = 1'b1;

      // Wait for decoded_command_rdy (registered, 1-cycle latency).
      // Hold vld one cycle after the handshake so DUT FFs reliably sample it.
      @(posedge clk_mhdma);
      while (!decoded_command_rdy) @(posedge clk_mhdma);
      @(posedge clk_mhdma);
      decoded_command_vld = 1'b0;

      // Feed payload data words
      for (int w = 0; w < nwords; w++) begin
        @(posedge clk_mhdma);
        decoder_rx_tdata  = {$urandom(), $urandom()};
        decoder_rx_tvalid = 1'b1;
      end
      @(posedge clk_mhdma);
      decoder_rx_tvalid = 1'b0;
    end
  endtask

  // --------------------------------------------------------------------------------------------- --
  // Feed all CE packets for a full ciphertext (split across Ethernet packets)
  // NB_PACKETS_FULL full-size packets + 1 last smaller packet
  // --------------------------------------------------------------------------------------------- --
  task automatic feed_full_ciphertext(
    input logic [IOP_ID_W-1:0]   iop_id,
    input logic [HPU_ID_W-1:0]   hpu_id,
    input logic [MODE_W-1:0]     mode,
    input logic [FLAG_W-1:0]     flag,
    input logic [SRC_ADDR_W-1:0] src_addr,
    input logic [DST_ADDR_W-1:0] dst_addr
  );
    begin
      for (int pkt = 0; pkt < NB_PACKETS_FULL + 1; pkt++) begin
        feed_ce_packet(pkt[SEQ_NUM_W-1:0], iop_id, hpu_id, mode, flag, src_addr, dst_addr);
      end
    end
  endtask

  // --------------------------------------------------------------------------------------------- --
  // Clear captured AXI4 data for all PCs
  // --------------------------------------------------------------------------------------------- --
  task automatic clear_axi4_captures();
    begin
      for (int pc = 0; pc < ETH_PC; pc++) begin
        axi4_aw_captured_addr[pc].delete();
        axi4_aw_captured_len[pc].delete();
        axi4_w_captured_data[pc].delete();
      end
    end
  endtask

  // --------------------------------------------------------------------------------------------- --
  // Consume master command: pulse master_command_rdy for one clock cycle (mrmac domain)
  // --------------------------------------------------------------------------------------------- --
  task automatic consume_master_command();
    begin
      @(posedge clk_mhdma);
      master_command_rdy = 1'b1;
      @(posedge clk_mhdma);
      master_command_rdy = 1'b0;
    end
  endtask

// ============================================================================================== --
// Scenario helpers
// ============================================================================================== --

  int scenario_id;

  logic [IOP_ID_W-1:0]   iop_id;
  logic [SRC_ADDR_W-1:0] iop_src_addr;
  logic [DST_ADDR_W-1:0] iop_dst_addr;
  logic [FLAG_W-1:0]     req_flag;
  logic [MODE_W-1:0]     req_mode;
  logic [HPU_ID_W-1:0]   hpu_id;

  // --------------------------------------------------------------------------------------------- --
  // Randomize all test command fields
  // --------------------------------------------------------------------------------------------- --
  task automatic randomize_fields();
    begin
      hpu_id       = $urandom();
      iop_id       = $urandom();
      iop_src_addr = $urandom();
      iop_dst_addr = $urandom();
      req_mode     = $urandom();
      req_flag     = $urandom();
    end
  endtask

  // --------------------------------------------------------------------------------------------- --
  // Pulse the rst_errors signal (mrmac domain)
  // --------------------------------------------------------------------------------------------- --
  task automatic pulse_rst_errors();
    begin
      @(posedge clk_mhdma);
      rst_errors = 1'b1;
      @(posedge clk_mhdma);
      rst_errors = 1'b0;
      repeat (5) @(posedge clk_mhdma);
    end
  endtask

  // --------------------------------------------------------------------------------------------- --
  // Inject a notify request, wait for command, check fields, complete handshake
  // Returns 1 on failure
  // --------------------------------------------------------------------------------------------- --
  task automatic do_notify_handshake(
    output bit failed
  );
    logic cmd_timed_out;
    begin
      failed = 1'b0;

      inject_regf_request(
        .iop_id   (iop_id      ),
        .req_type (REQ_ID_NOTIFY),
        .hpu_id   (hpu_id      ),
        .mode     (req_mode    ),
        .flag     (req_flag    ),
        .src_addr (iop_src_addr),
        .dst_addr (iop_dst_addr)
      );

      wait_master_command_vld(500, cmd_timed_out);
      assert (!cmd_timed_out) else begin
        $display("[ERROR:%0d] Timed out waiting for master_command_vld", scenario_id);
        failed = 1'b1;
      end
      assert (master_command.req_id == REQ_ID_NOTIFY) else begin
        $display("[ERROR:%0d] req_id mismatch: expected %0h, got %0h", scenario_id, REQ_ID_NOTIFY, master_command.req_id);
        failed = 1'b1;
      end
      assert (master_command.iop_id == iop_id) else begin
        $display("[ERROR:%0d] iop_id mismatch: expected %0h, got %0h", scenario_id, iop_id, master_command.iop_id);
        failed = 1'b1;
      end
      assert (master_command.dst_addr == iop_dst_addr) else begin
        $display("[ERROR:%0d] dst_addr mismatch: expected %0h, got %0h", scenario_id, iop_dst_addr, master_command.dst_addr);
        failed = 1'b1;
      end

      consume_master_command();
      simulate_pulse(notify_sent, clk_mhdma);
      simulate_pulse(notify_ack_received, clk_mhdma);
      repeat (20) @(posedge clk_mhdma);
    end
  endtask

  // --------------------------------------------------------------------------------------------- --
  // Inject a read request, wait for command, send CE, wait for interrupt, clear interrupt
  // Returns 1 on failure
  // --------------------------------------------------------------------------------------------- --
  task automatic do_read_request_flow(
    output bit failed
  );
    logic cmd_timed_out;
    logic irq_timed_out;
    begin
      failed = 1'b0;

      inject_regf_request(
        .iop_id   (iop_id      ),
        .req_type (REQ_ID_READ ),
        .hpu_id   (hpu_id      ),
        .mode     (req_mode    ),
        .flag     (req_flag    ),
        .src_addr (iop_src_addr),
        .dst_addr (iop_dst_addr)
      );

      wait_master_command_vld(500, cmd_timed_out);
      assert (!cmd_timed_out) else begin
        $display("[ERROR:%0d] Timed out waiting for master_command_vld", scenario_id);
        failed = 1'b1;
      end
      assert (master_command.req_id == REQ_ID_READ) else begin
        $display("[ERROR:%0d] req_id mismatch: expected %0h, got %0h", scenario_id, REQ_ID_READ, master_command.req_id);
        failed = 1'b1;
      end

      consume_master_command();
      simulate_pulse(read_request_sent, clk_mhdma);
      feed_full_ciphertext(iop_id, hpu_id, req_mode, req_flag, iop_src_addr, iop_dst_addr);

      wait_interrupt_rr(5000, irq_timed_out);
      assert (!irq_timed_out) else begin
        $display("[ERROR:%0d] Timed out waiting for interrupt_read_request", scenario_id);
        failed = 1'b1;
      end

      clear_signal(clear_interrupt_rr, clk_mhdma_cfg);
    end
  endtask

// ============================================================================================== --
// Scenario tasks
// ============================================================================================== --

  // --------------------------------------------------------------------------------------------- --
  // Scenario : Triggering a Notify
  // --------------------------------------------------------------------------------------------- --
  task automatic run_scenario_notify_tx();
    logic cmd_timed_out;
    begin
      scenario_start(scenario_id, "Notify TX basic flow");
      randomize_fields();

      inject_regf_request(
        .iop_id   (iop_id       ),
        .req_type (REQ_ID_NOTIFY),
        .hpu_id   (hpu_id       ),
        .mode     (req_mode     ),
        .flag     (req_flag     ),
        .src_addr (iop_src_addr ),
        .dst_addr (iop_dst_addr )
      );

      wait_master_command_vld(500, cmd_timed_out);
      assert (!cmd_timed_out) else begin
        $display("[ERROR:%0d] Timed out waiting for master_command_vld", scenario_id);
        error_scenario = 1'b1;
      end

      assert (master_command.req_id   == REQ_ID_NOTIFY) else begin $display("[ERROR:%0d] req_id mismatch: expected %0h, got %0h", scenario_id, REQ_ID_NOTIFY, master_command.req_id); error_scenario = 1'b1; end
      assert (master_command.hpu_id   == hpu_id       ) else begin $display("[ERROR:%0d] hpu_id mismatch",   scenario_id); error_scenario = 1'b1; end
      assert (master_command.iop_id   == iop_id       ) else begin $display("[ERROR:%0d] iop_id mismatch",   scenario_id); error_scenario = 1'b1; end
      assert (master_command.src_addr == iop_src_addr ) else begin $display("[ERROR:%0d] src_addr mismatch", scenario_id); error_scenario = 1'b1; end
      assert (master_command.dst_addr == iop_dst_addr ) else begin $display("[ERROR:%0d] dst_addr mismatch", scenario_id); error_scenario = 1'b1; end

      consume_master_command();
      simulate_pulse(notify_sent, clk_mhdma);
      simulate_pulse(notify_ack_received, clk_mhdma);

      repeat (50) @(posedge clk_mhdma);
      assert (stat.fsm_notify == 2'b00) else begin
        $display("[ERROR:%0d] NTX FSM not in WAIT_REQUEST: %0b", scenario_id, stat.fsm_notify);
        error_scenario = 1'b1;
      end

      assert (stat.cnt_notify     >= 1) else begin $display("[ERROR:%0d] cnt_notify not incremented",     scenario_id); error_scenario = 1'b1; end
      assert (stat.cnt_notify_ack >= 1) else begin $display("[ERROR:%0d] cnt_notify_ack not incremented", scenario_id); error_scenario = 1'b1; end

      scenario_end(scenario_id, clk_mhdma_cfg);
    end
  endtask

  // --------------------------------------------------------------------------------------------- --
  // Scenario : Notify TX timeout and retry
  // --------------------------------------------------------------------------------------------- --
  task automatic run_scenario_notify_tx_timeout_retry();
    logic [REG_DATA_W-1:0] saved_notify_retries;
    logic cmd_timed_out;
    begin
      scenario_start(scenario_id, "Notify TX timeout and retry");
      saved_notify_retries = stat.cnt_notify_retries;
      randomize_fields();

      inject_regf_request(
        .iop_id   (iop_id      ),
        .req_type (REQ_ID_NOTIFY),
        .hpu_id   (hpu_id      ),
        .mode     (req_mode    ),
        .flag     (req_flag    ),
        .src_addr (iop_src_addr),
        .dst_addr (iop_dst_addr)
      );

      wait_master_command_vld(500, cmd_timed_out);
      assert (!cmd_timed_out) else begin
        $display("[ERROR:%0d] Timed out waiting for initial master_command_vld", scenario_id);
        error_scenario = 1'b1;
      end

      consume_master_command();
      simulate_pulse(notify_sent, clk_mhdma);
      // Do NOT send notify_ack

      repeat (TIMEOUT_NOTIFY + 20) @(posedge clk_mhdma);
      assert (stat.cnt_notify_retries >= saved_notify_retries + 1) else begin
        $display("[ERROR:%0d] cnt_notify_retries not incremented after timeout", scenario_id);
        error_scenario = 1'b1;
      end

      wait_master_command_vld(500, cmd_timed_out);
      assert (!cmd_timed_out) else begin
        $display("[ERROR:%0d] Timed out waiting for retry master_command_vld", scenario_id);
        error_scenario = 1'b1;
      end
      assert (master_command.req_id == REQ_ID_NOTIFY) else begin
        $display("[ERROR:%0d] Retry req_id mismatch", scenario_id);
        error_scenario = 1'b1;
      end
      assert (master_command.dst_addr == iop_dst_addr) else begin
        $display("[ERROR:%0d] Retry dst_addr mismatch: expected %0h, got %0h", scenario_id, iop_dst_addr, master_command.dst_addr);
        error_scenario = 1'b1;
      end

      consume_master_command();
      simulate_pulse(notify_sent, clk_mhdma);
      simulate_pulse(notify_ack_received, clk_mhdma);

      repeat (20) @(posedge clk_mhdma);
      assert (stat.fsm_notify == 2'b00) else begin
        $display("[ERROR:%0d] NTX FSM not back to WAIT_REQUEST after retry", scenario_id);
        error_scenario = 1'b1;
      end

      scenario_end(scenario_id, clk_mhdma_cfg);
    end
  endtask

  // --------------------------------------------------------------------------------------------- --
  // Scenario : Read Request basic flow
  // --------------------------------------------------------------------------------------------- --
  task automatic run_scenario_read_request();
    logic cmd_timed_out;
    logic irq_timed_out;
    logic [REG_DATA_W-1:0] exp_read_req_id;
    logic [REG_DATA_W-1:0] exp_read_addr;
    begin
      scenario_start(scenario_id, "Read Request basic flow");
      clear_axi4_captures();
      randomize_fields();

      inject_regf_request(
        .iop_id   (iop_id      ),
        .req_type (REQ_ID_READ ),
        .hpu_id   (hpu_id      ),
        .mode     (req_mode    ),
        .flag     (req_flag    ),
        .src_addr (iop_src_addr),
        .dst_addr (iop_dst_addr)
      );

      wait_master_command_vld(500, cmd_timed_out);
      assert (!cmd_timed_out) else begin
        $display("[ERROR:%0d] Timed out waiting for master_command_vld", scenario_id);
        error_scenario = 1'b1;
      end
      assert (master_command.req_id == REQ_ID_READ) else begin
        $display("[ERROR:%0d] req_id mismatch: expected %0h, got %0h", scenario_id, REQ_ID_READ, master_command.req_id);
        error_scenario = 1'b1;
      end

      consume_master_command();
      simulate_pulse(read_request_sent, clk_mhdma);

      feed_full_ciphertext(
        .iop_id   (iop_id      ),
        .hpu_id   (hpu_id      ),
        .mode     (req_mode    ),
        .flag     (req_flag    ),
        .src_addr (iop_src_addr),
        .dst_addr (iop_dst_addr)
      );

      wait_interrupt_rr(5000, irq_timed_out);
      assert (!irq_timed_out) else begin
        $display("[ERROR:%0d] Timed out waiting for interrupt_read_request", scenario_id);
        error_scenario = 1'b1;
      end

      // Build expected values: received_* fields come from decoded_command (CE emission)
      exp_read_req_id = {iop_id, REQ_ID_EMISSION, hpu_id, req_mode, req_flag, 8'h0};
      exp_read_addr   = {iop_dst_addr, iop_src_addr};

      assert (regf_read_req_id == exp_read_req_id) else begin $display("[ERROR:%0d] regf_read_req_id | exp %0h got %0h", scenario_id, exp_read_req_id, regf_read_req_id); error_scenario = 1'b1; end
      assert (regf_read_addr   == exp_read_addr  ) else begin $display("[ERROR:%0d] regf_read_addr   | exp %0h got %0h", scenario_id, exp_read_addr,   regf_read_addr  ); error_scenario = 1'b1; end

      clear_signal(clear_interrupt_rr, clk_mhdma_cfg);

      repeat (10) @(posedge clk_mhdma_cfg);
      assert (!interrupt_read_request) else begin
        $display("[ERROR:%0d] interrupt_read_request did not deassert after clear", scenario_id);
        error_scenario = 1'b1;
      end

      repeat (20) @(posedge clk_mhdma);
      assert (stat.fsm_read_req == 2'b00) else begin
        $display("[ERROR:%0d] RR FSM not in WAIT_REQUEST: %0b", scenario_id, stat.fsm_read_req);
        error_scenario = 1'b1;
      end

      scenario_end(scenario_id, clk_mhdma_cfg);
    end
  endtask

  // --------------------------------------------------------------------------------------------- --
  // Scenario : Read Request timeout and retry
  // --------------------------------------------------------------------------------------------- --
  task automatic run_scenario_read_request_timeout_retry();
    logic [REG_DATA_W-1:0] saved_read_retries;
    logic cmd_timed_out;
    logic irq_timed_out;
    begin
      scenario_start(scenario_id, "Read Request timeout and retry");
      saved_read_retries = stat.cnt_read_req_retries;
      randomize_fields();

      inject_regf_request(
        .iop_id   (iop_id      ),
        .req_type (REQ_ID_READ ),
        .hpu_id   (hpu_id      ),
        .mode     (req_mode    ),
        .flag     (req_flag    ),
        .src_addr (iop_src_addr),
        .dst_addr (iop_dst_addr)
      );

      wait_master_command_vld(500, cmd_timed_out);
      assert (!cmd_timed_out) else begin
        $display("[ERROR:%0d] Timed out waiting for initial master_command_vld", scenario_id);
        error_scenario = 1'b1;
      end
      assert (master_command.req_id == REQ_ID_READ) else begin
        $display("[ERROR:%0d] req_id mismatch", scenario_id);
        error_scenario = 1'b1;
      end

      consume_master_command();
      simulate_pulse(read_request_sent, clk_mhdma);
      // Do NOT send CE data

      repeat (TIMEOUT_READ_REQ + 20) @(posedge clk_mhdma);
      assert (stat.cnt_read_req_retries >= saved_read_retries + 1) else begin
        $display("[ERROR:%0d] cnt_read_req_retries not incremented after timeout", scenario_id);
        error_scenario = 1'b1;
      end

      wait_master_command_vld(500, cmd_timed_out);
      assert (!cmd_timed_out) else begin
        $display("[ERROR:%0d] Timed out waiting for retry master_command_vld", scenario_id);
        error_scenario = 1'b1;
      end
      assert (master_command.req_id == REQ_ID_READ) else begin
        $display("[ERROR:%0d] Retry req_id mismatch", scenario_id);
        error_scenario = 1'b1;
      end

      consume_master_command();
      simulate_pulse(read_request_sent, clk_mhdma);
      feed_full_ciphertext(
        .iop_id   (iop_id      ),
        .hpu_id   (hpu_id      ),
        .mode     (req_mode    ),
        .flag     (req_flag    ),
        .src_addr (iop_src_addr),
        .dst_addr (iop_dst_addr)
      );

      wait_interrupt_rr(5000, irq_timed_out);
      assert (!irq_timed_out) else begin
        $display("[ERROR:%0d] Timed out waiting for interrupt after retry", scenario_id);
        error_scenario = 1'b1;
      end
      clear_signal(clear_interrupt_rr, clk_mhdma_cfg);

      repeat (20) @(posedge clk_mhdma);
      assert (stat.fsm_read_req == 2'b00) else begin
        $display("[ERROR:%0d] RR FSM not back to WAIT_REQUEST", scenario_id);
        error_scenario = 1'b1;
      end

      scenario_end(scenario_id, clk_mhdma_cfg);
    end
  endtask

  // --------------------------------------------------------------------------------------------- --
  // Scenario : Seq num mismatch handling
  // --------------------------------------------------------------------------------------------- --
  task automatic run_scenario_seq_num_mismatch();
    logic [REG_DATA_W-1:0] saved_read_retries;
    logic cmd_timed_out;
    logic irq_timed_out;
    begin
      scenario_start(scenario_id, "Seq num mismatch handling");
      saved_read_retries = stat.cnt_read_req_retries;
      randomize_fields();

      inject_regf_request(
        .iop_id   (iop_id      ),
        .req_type (REQ_ID_READ ),
        .hpu_id   (hpu_id      ),
        .mode     (req_mode    ),
        .flag     (req_flag    ),
        .src_addr (iop_src_addr),
        .dst_addr (iop_dst_addr)
      );

      wait_master_command_vld(500, cmd_timed_out);
      assert (!cmd_timed_out) else begin
        $display("[ERROR:%0d] Timed out waiting for master_command_vld", scenario_id);
        error_scenario = 1'b1;
      end
      consume_master_command();
      simulate_pulse(read_request_sent, clk_mhdma);

      // Feed first CE packet with seq_num=0 (correct)
      feed_ce_packet(8'h0, iop_id, hpu_id, req_mode, req_flag, iop_src_addr, iop_dst_addr);

      // Feed second CE packet with seq_num=2 (skip 1 = mismatch)
      feed_ce_packet(8'h2, iop_id, hpu_id, req_mode, req_flag, iop_src_addr, iop_dst_addr);

      repeat (50) @(posedge clk_mhdma);
      assert (master_error.seq_num_error == 1'b1) else begin
        $display("[ERROR:%0d] seq_num_error not set after mismatch", scenario_id);
        error_scenario = 1'b1;
      end

      // Wait for zero-padded write to complete and retry
      wait_master_command_vld(5000, cmd_timed_out);
      assert (!cmd_timed_out) else begin
        $display("[ERROR:%0d] Timed out waiting for retry master_command_vld after mismatch", scenario_id);
        error_scenario = 1'b1;
      end

      assert (stat.cnt_read_req_retries >= saved_read_retries + 1) else begin
        $display("[ERROR:%0d] cnt_read_req_retries not incremented after mismatch", scenario_id);
        error_scenario = 1'b1;
      end

      consume_master_command();
      simulate_pulse(read_request_sent, clk_mhdma);
      feed_full_ciphertext(
        .iop_id   (iop_id      ),
        .hpu_id   (hpu_id      ),
        .mode     (req_mode    ),
        .flag     (req_flag    ),
        .src_addr (iop_src_addr),
        .dst_addr (iop_dst_addr)
      );

      wait_interrupt_rr(5000, irq_timed_out);
      assert (!irq_timed_out) else begin
        $display("[ERROR:%0d] Timed out waiting for interrupt after retry", scenario_id);
        error_scenario = 1'b1;
      end
      clear_signal(clear_interrupt_rr, clk_mhdma_cfg);

      // Clear error for subsequent scenarios
      pulse_rst_errors();

      scenario_end(scenario_id, clk_mhdma_cfg);
    end
  endtask

  // --------------------------------------------------------------------------------------------- --
  // Scenario : AXI4 page boundary splitting
  // TODO
  //  1. Single hardcoded offset - The test only exercises 0xF00 (8 words before boundary). It misses important edge cases:
  // - Page-aligned address (offset 0x000): should produce no unnecessary split
  // - 1 word before boundary (e.g. offset 0xFE0): first burst is just 1 word - minimal split
  // - Offset that doesn't divide evenly: different remainder patterns
  // 2. No burst contiguity check - The test checks first burst offset, second burst alignment, and total word count, but never verifies that bursts are actually contiguous.
  //  A gap or overlap between bursts would go undetected. Should check: burst[i+1].addr == burst[i].addr + (burst[i].len+1) * AXI4_DATA_BYTES
  // 3. Middle bursts not validated - When the transfer spans 3+ pages, all middle bursts should be exactly PAGE_AXI4_DATA words (full page). The test doesn't check this.
  // 4. Only PC0 is tested - If ETH_PC > 1, the other PCs are completely ignored. They have a different word count (AXI4_WORD_PER_PC vs AXI4_WORD_PER_PC0) and could have different splitting behavior.
  // 5. Redundant variable - saved_ct_mem_addr_pc0 / save-restore pattern would become cleaner if the test iterated over addresses, and expected_words_pc0 is used only once (could inline it).
  // --------------------------------------------------------------------------------------------- --
  task automatic run_scenario_axi4_page_boundary();
    logic [2*REG_DATA_W-1:0] saved_ct_mem_addr_pc0;
    int                      total_awlen_sum;
    int                      expected_words_pc0;
    int                      words_before_boundary;
    logic [AXI4_ADD_W-1:0]   burst_addr;
    logic                    cmd_timed_out;
    logic                    irq_timed_out;
    begin
      scenario_start(scenario_id, "AXI4 page boundary splitting");
      clear_axi4_captures();
      saved_ct_mem_addr_pc0 = regf_ct_mem_addr[0];

      // Place PC0 base address near end of a 4KB page to force page split
      // PAGE_BYTES=4096, AXI4_DATA_BYTES=32 (256/8), so PAGE_AXI4_DATA=128
      // Set address so only a few AXI4 words fit before page boundary
      regf_ct_mem_addr[0] = 64'h0000_0000_0000_0F00;

      randomize_fields();

      inject_regf_request(
        .iop_id   (iop_id      ),
        .req_type (REQ_ID_READ ),
        .hpu_id   (hpu_id      ),
        .mode     (req_mode    ),
        .flag     (req_flag    ),
        .src_addr (iop_src_addr),
        .dst_addr (iop_dst_addr)
      );

      wait_master_command_vld(500, cmd_timed_out);
      assert (!cmd_timed_out) else begin
        $display("[ERROR:%0d] Timed out waiting for master_command_vld", scenario_id);
        error_scenario = 1'b1;
      end

      consume_master_command();
      simulate_pulse(read_request_sent, clk_mhdma);
      feed_full_ciphertext(
        .iop_id   (iop_id      ),
        .hpu_id   (hpu_id      ),
        .mode     (req_mode    ),
        .flag     (req_flag    ),
        .src_addr (iop_src_addr),
        .dst_addr (iop_dst_addr)
      );

      wait_interrupt_rr(5000, irq_timed_out);
      assert (!irq_timed_out) else begin
        $display("[ERROR:%0d] Timed out waiting for interrupt", scenario_id);
        error_scenario = 1'b1;
      end
      clear_signal(clear_interrupt_rr, clk_mhdma_cfg);

      repeat (20) @(posedge clk_mhdma);

      // Verify PC0 got multiple AW transactions (page split)
      assert (axi4_aw_captured_addr[0].size() > 1) else begin
        $display("[ERROR:%0d] Expected multiple AW transactions for PC0 due to page split, got %0d", scenario_id, axi4_aw_captured_addr[0].size());
        error_scenario = 1'b1;
      end

      // Verify first burst page offset matches the configured base address
      assert (axi4_aw_captured_addr[0][0][PAGE_BYTES_W-1:0] == regf_ct_mem_addr[0][PAGE_BYTES_W-1:0]) else begin
        $display("[ERROR:%0d] First burst page offset: expected 0x%0h, got 0x%0h",
                 scenario_id, regf_ct_mem_addr[0][PAGE_BYTES_W-1:0], axi4_aw_captured_addr[0][0][PAGE_BYTES_W-1:0]);
        error_scenario = 1'b1;
      end

      // Verify first burst length matches words remaining before page boundary
      words_before_boundary = PAGE_AXI4_DATA - axi4_aw_captured_addr[0][0][PAGE_BYTES_W-1:AXI4_DATA_BYTES_W];
      assert (axi4_aw_captured_len[0][0] + 1 == words_before_boundary) else begin
        $display("[ERROR:%0d] First burst length: expected %0d words, got %0d",
                 scenario_id, words_before_boundary, axi4_aw_captured_len[0][0] + 1);
        error_scenario = 1'b1;
      end

      // Verify second burst starts at the next page boundary
      assert (axi4_aw_captured_addr[0][1][PAGE_BYTES_W-1:0] == '0) else begin
        $display("[ERROR:%0d] Second burst addr not page-aligned: 0x%0h", scenario_id, axi4_aw_captured_addr[0][1]);
        error_scenario = 1'b1;
      end

      // Verify no burst crosses a page boundary
      // Use page-local word offsets to avoid XSIM 64-bit arithmetic issues
      for (int burst_index = 0; burst_index < axi4_aw_captured_addr[0].size(); burst_index++) begin
        burst_addr = axi4_aw_captured_addr[0][burst_index];
        assert (burst_addr[PAGE_BYTES_W-1:AXI4_DATA_BYTES_W] + axi4_aw_captured_len[0][burst_index] < PAGE_AXI4_DATA) else begin
          $display("[ERROR:%0d] Burst %0d crosses page boundary: addr=0x%0h, word_offset=%0d, awlen=%0d",
                   scenario_id, burst_index, burst_addr,
                   burst_addr[PAGE_BYTES_W-1:AXI4_DATA_BYTES_W],
                   axi4_aw_captured_len[0][burst_index]);
          error_scenario = 1'b1;
        end
      end

      // Verify sum of (awlen+1) matches AXI4_WORD_PER_PC0
      expected_words_pc0 = AXI4_WORD_PER_PC0;
      total_awlen_sum = 0;
      for (int burst_index = 0; burst_index < axi4_aw_captured_len[0].size(); burst_index++) begin
        total_awlen_sum += axi4_aw_captured_len[0][burst_index] + 1;
      end
      assert (total_awlen_sum == expected_words_pc0) else begin
        $display("[ERROR:%0d] PC0 awlen sum mismatch: expected %0d, got %0d", scenario_id, expected_words_pc0, total_awlen_sum);
        error_scenario = 1'b1;
      end

      // Restore
      regf_ct_mem_addr[0] = saved_ct_mem_addr_pc0;
      clear_axi4_captures();

      scenario_end(scenario_id, clk_mhdma_cfg);
    end
  endtask

  // --------------------------------------------------------------------------------------------- --
  // Scenario : AXI4 write error handling
  // --------------------------------------------------------------------------------------------- --
  task automatic run_scenario_axi4_write_error();
    logic cmd_timed_out;
    logic irq_timed_out;
    begin
      scenario_start(scenario_id, "AXI4 write error handling");
      axi4_bresp_type[0] = AXI4_SLVERR;
      randomize_fields();

      inject_regf_request(
        .iop_id   (iop_id      ),
        .req_type (REQ_ID_READ ),
        .hpu_id   (hpu_id      ),
        .mode     (req_mode    ),
        .flag     (req_flag    ),
        .src_addr (iop_src_addr),
        .dst_addr (iop_dst_addr)
      );

      wait_master_command_vld(500, cmd_timed_out);
      assert (!cmd_timed_out) else begin
        $display("[ERROR:%0d] Timed out waiting for master_command_vld", scenario_id);
        error_scenario = 1'b1;
      end

      consume_master_command();
      simulate_pulse(read_request_sent, clk_mhdma);
      feed_full_ciphertext(
        .iop_id   (iop_id      ),
        .hpu_id   (hpu_id      ),
        .mode     (req_mode    ),
        .flag     (req_flag    ),
        .src_addr (iop_src_addr),
        .dst_addr (iop_dst_addr)
      );

      wait_interrupt_rr(5000, irq_timed_out);
      assert (!irq_timed_out) else begin
        $display("[ERROR:%0d] Timed out waiting for interrupt", scenario_id);
        error_scenario = 1'b1;
      end
      clear_signal(clear_interrupt_rr, clk_mhdma_cfg);

      repeat (20) @(posedge clk_mhdma);
      assert (master_error.write_error[0] == 1'b1) else begin
        $display("[ERROR:%0d] write_error[0] not set for SLVERR", scenario_id);
        error_scenario = 1'b1;
      end

      if (ETH_PC > 1) begin
        assert (master_error.write_error[1] == 1'b0) else begin
          $display("[ERROR:%0d] write_error[1] unexpectedly set", scenario_id);
          error_scenario = 1'b1;
        end
      end

      // Restore and clear errors
      axi4_bresp_type[0] = AXI4_OKAY;
      pulse_rst_errors();

      assert (master_error.write_error[0] == 1'b0) else begin
        $display("[ERROR:%0d] write_error[0] not cleared after rst_errors", scenario_id);
        error_scenario = 1'b1;
      end

      scenario_end(scenario_id, clk_mhdma_cfg);
    end
  endtask

  // --------------------------------------------------------------------------------------------- --
  // Scenario : ce_reception_ready signaling
  // --------------------------------------------------------------------------------------------- --
  task automatic run_scenario_ce_reception_ready();
    logic cmd_timed_out;
    logic irq_timed_out;
    begin
      scenario_start(scenario_id, "ce_reception_ready signaling");

      repeat (10) @(posedge clk_mhdma);
      assert (ce_reception_ready == 1'b1) else begin
        $display("[ERROR:%0d] ce_reception_ready not high before transfer", scenario_id);
        error_scenario = 1'b1;
      end

      randomize_fields();

      inject_regf_request(
        .iop_id   (iop_id      ),
        .req_type (REQ_ID_READ ),
        .hpu_id   (hpu_id      ),
        .mode     (req_mode    ),
        .flag     (req_flag    ),
        .src_addr (iop_src_addr),
        .dst_addr (iop_dst_addr)
      );

      wait_master_command_vld(500, cmd_timed_out);
      assert (!cmd_timed_out) else begin
        $display("[ERROR:%0d] Timed out waiting for master_command_vld", scenario_id);
        error_scenario = 1'b1;
      end

      consume_master_command();
      simulate_pulse(read_request_sent, clk_mhdma);

      // Feed first CE packet and check ce_reception_ready goes low
      feed_ce_packet(8'h0, iop_id, hpu_id, req_mode, req_flag, iop_src_addr, iop_dst_addr);

      // While pipeline has data, ce_reception_ready may be low
      begin
        logic seen_low;
        seen_low = 1'b0;
        repeat (20) begin
          @(posedge clk_mhdma);
          if (!ce_reception_ready) seen_low = 1'b1;
        end
        assert (seen_low) else begin
          $display("[ERROR:%0d] ce_reception_ready never went low during CE feeding", scenario_id);
          error_scenario = 1'b1;
        end
      end

      // Feed remaining CE packets
      for (int pkt = 1; pkt < NB_PACKETS_FULL + 1; pkt++) begin
        feed_ce_packet(pkt[SEQ_NUM_W-1:0], iop_id, hpu_id, req_mode, req_flag, iop_src_addr, iop_dst_addr);
      end

      wait_interrupt_rr(5000, irq_timed_out);
      assert (!irq_timed_out) else begin
        $display("[ERROR:%0d] Timed out waiting for interrupt", scenario_id);
        error_scenario = 1'b1;
      end
      clear_signal(clear_interrupt_rr, clk_mhdma_cfg);

      // Wait for pipeline to drain
      repeat (100) @(posedge clk_mhdma);
      assert (ce_reception_ready == 1'b1) else begin
        $display("[ERROR:%0d] ce_reception_ready not high after transfer completed", scenario_id);
        error_scenario = 1'b1;
      end

      scenario_end(scenario_id, clk_mhdma_cfg);
    end
  endtask

  // --------------------------------------------------------------------------------------------- --
  // Scenario : Multiple sequential notify requests
  // --------------------------------------------------------------------------------------------- --
  task automatic run_scenario_multiple_notifies();
    logic [REG_DATA_W-1:0] saved_cnt_notify;
    logic [REG_DATA_W-1:0] saved_cnt_notify_ack;
    int notify_count;
    bit handshake_failed;
    begin
      scenario_start(scenario_id, "Multiple sequential notify requests");

      notify_count = 4;
      saved_cnt_notify     = stat.cnt_notify;
      saved_cnt_notify_ack = stat.cnt_notify_ack;

      for (int notify_index = 0; notify_index < notify_count; notify_index++) begin
        randomize_fields();
        do_notify_handshake(handshake_failed);
        if (handshake_failed) error_scenario = 1'b1;
      end

      assert (stat.cnt_notify == saved_cnt_notify + notify_count) else begin
        $display("[ERROR:%0d] cnt_notify mismatch: expected %0d, got %0d", scenario_id, saved_cnt_notify + notify_count, stat.cnt_notify);
        error_scenario = 1'b1;
      end
      assert (stat.cnt_notify_ack == saved_cnt_notify_ack + notify_count) else begin
        $display("[ERROR:%0d] cnt_notify_ack mismatch: expected %0d, got %0d", scenario_id, saved_cnt_notify_ack + notify_count, stat.cnt_notify_ack);
        error_scenario = 1'b1;
      end

      scenario_end(scenario_id, clk_mhdma_cfg);
    end
  endtask

  // --------------------------------------------------------------------------------------------- --
  // Scenario : Multiple sequential read requests
  // --------------------------------------------------------------------------------------------- --
  task automatic run_scenario_multiple_reads();
    int read_count;
    bit read_failed;
    begin
      scenario_start(scenario_id, "Multiple sequential read requests");
      read_count = 3;

      for (int read_index = 0; read_index < read_count; read_index++) begin
        randomize_fields();
        do_read_request_flow(read_failed);
        if (read_failed) error_scenario = 1'b1;

        assert (regf_read_req_id[31:24] == iop_id      ) else begin $display("[ERROR:%0d] regf_read_req_id iop_id mismatch on read %0d",   scenario_id, read_index); error_scenario = 1'b1; end
        assert (regf_read_addr[15:0]    == iop_src_addr ) else begin $display("[ERROR:%0d] regf_read_addr src_addr mismatch on read %0d",   scenario_id, read_index); error_scenario = 1'b1; end

        repeat (20) @(posedge clk_mhdma);
      end

      assert (stat.fsm_read_req == 2'b00) else begin
        $display("[ERROR:%0d] RR FSM not in WAIT_REQUEST after all reads", scenario_id);
        error_scenario = 1'b1;
      end

      scenario_end(scenario_id, clk_mhdma_cfg);
    end
  endtask

  // --------------------------------------------------------------------------------------------- --
  // Scenario : Statistics counters
  // --------------------------------------------------------------------------------------------- --
  task automatic run_scenario_statistics();
    logic [REG_DATA_W-1:0] baseline_cnt_notify;
    logic [REG_DATA_W-1:0] baseline_cnt_notify_ack;
    logic cmd_timed_out;
    logic irq_timed_out;
    bit handshake_failed;
    begin
      scenario_start(scenario_id, "Statistics counters");

      baseline_cnt_notify     = stat.cnt_notify;
      baseline_cnt_notify_ack = stat.cnt_notify_ack;

      // Perform 2 notifies
      for (int notify_index = 0; notify_index < 2; notify_index++) begin
        randomize_fields();
        do_notify_handshake(handshake_failed);
        if (handshake_failed) error_scenario = 1'b1;
      end

      assert (stat.cnt_notify == baseline_cnt_notify + 2) else begin
        $display("[ERROR:%0d] cnt_notify not incremented by 2", scenario_id);
        error_scenario = 1'b1;
      end
      assert (stat.cnt_notify_ack == baseline_cnt_notify_ack + 2) else begin
        $display("[ERROR:%0d] cnt_notify_ack not incremented by 2", scenario_id);
        error_scenario = 1'b1;
      end
      assert (stat.t_notify_to_ack != 0) else begin
        $display("[ERROR:%0d] t_notify_to_ack is zero", scenario_id);
        error_scenario = 1'b1;
      end
      assert (stat.t_notify_to_ack_max != 0) else begin
        $display("[ERROR:%0d] t_notify_to_ack_max is zero", scenario_id);
        error_scenario = 1'b1;
      end

      // Perform a read request for t_rr_to_ce_received
      randomize_fields();

      inject_regf_request(
        .iop_id   (iop_id      ),
        .req_type (REQ_ID_READ ),
        .hpu_id   (hpu_id      ),
        .mode     (req_mode    ),
        .flag     (req_flag    ),
        .src_addr (iop_src_addr),
        .dst_addr (iop_dst_addr)
      );
      wait_master_command_vld(500, cmd_timed_out);
      consume_master_command();
      simulate_pulse(read_request_sent, clk_mhdma);
      feed_full_ciphertext(iop_id, hpu_id, req_mode, req_flag, iop_src_addr, iop_dst_addr);
      wait_interrupt_rr(5000, irq_timed_out);
      clear_signal(clear_interrupt_rr, clk_mhdma_cfg);

      repeat (20) @(posedge clk_mhdma);
      assert (stat.t_rr_to_ce_received != 0) else begin
        $display("[ERROR:%0d] t_rr_to_ce_received is zero", scenario_id);
        error_scenario = 1'b1;
      end
      assert (stat.t_rr_to_ce_received_max != 0) else begin
        $display("[ERROR:%0d] t_rr_to_ce_received_max is zero", scenario_id);
        error_scenario = 1'b1;
      end
      assert (stat.nb_ce_words_received != 0) else begin
        $display("[ERROR:%0d] nb_ce_words_received is zero", scenario_id);
        error_scenario = 1'b1;
      end

      // Test selective stat reset: pulse stat_rst.cnt_notify
      begin
        logic [REG_DATA_W-1:0] saved_cnt_notify_ack_before_reset;
        saved_cnt_notify_ack_before_reset = stat.cnt_notify_ack;

        @(posedge clk_mhdma);
        stat_rst.cnt_notify = 1'b1;
        @(posedge clk_mhdma);
        stat_rst.cnt_notify = 1'b0;
        repeat (5) @(posedge clk_mhdma);

        assert (stat.cnt_notify == 0) else begin
          $display("[ERROR:%0d] cnt_notify not reset to 0", scenario_id);
          error_scenario = 1'b1;
        end
        assert (stat.cnt_notify_ack == saved_cnt_notify_ack_before_reset) else begin
          $display("[ERROR:%0d] cnt_notify_ack affected by cnt_notify reset", scenario_id);
          error_scenario = 1'b1;
        end
      end

      assert (stat.fsm_notify   == 2'b00) else begin $display("[ERROR:%0d] fsm_notify not WAIT_REQUEST",   scenario_id); error_scenario = 1'b1; end
      assert (stat.fsm_read_req == 2'b00) else begin $display("[ERROR:%0d] fsm_read_req not WAIT_REQUEST", scenario_id); error_scenario = 1'b1; end

      scenario_end(scenario_id, clk_mhdma_cfg);
    end
  endtask

  // --------------------------------------------------------------------------------------------- --
  // Scenario : Error reset
  // --------------------------------------------------------------------------------------------- --
  task automatic run_scenario_error_reset();
    logic cmd_timed_out;
    logic irq_timed_out;
    begin
      scenario_start(scenario_id, "Error reset");

      // Trigger seq_num_error via mismatch
      randomize_fields();

      inject_regf_request(
        .iop_id   (iop_id      ),
        .req_type (REQ_ID_READ ),
        .hpu_id   (hpu_id      ),
        .mode     (req_mode    ),
        .flag     (req_flag    ),
        .src_addr (iop_src_addr),
        .dst_addr (iop_dst_addr)
      );

      wait_master_command_vld(500, cmd_timed_out);
      assert (!cmd_timed_out) else begin
        $display("[ERROR:%0d] Timed out waiting for master_command_vld", scenario_id);
        error_scenario = 1'b1;
      end
      consume_master_command();
      simulate_pulse(read_request_sent, clk_mhdma);

      // Feed seq_num=0 then seq_num=2 (skip 1 = mismatch)
      feed_ce_packet(8'h0, iop_id, hpu_id, req_mode, req_flag, iop_src_addr, iop_dst_addr);
      feed_ce_packet(8'h2, iop_id, hpu_id, req_mode, req_flag, iop_src_addr, iop_dst_addr);

      repeat (50) @(posedge clk_mhdma);
      assert (master_error.seq_num_error == 1'b1) else begin
        $display("[ERROR:%0d] seq_num_error not set", scenario_id);
        error_scenario = 1'b1;
      end

      // Verify it stays set
      repeat (10) @(posedge clk_mhdma);
      assert (master_error.seq_num_error == 1'b1) else begin
        $display("[ERROR:%0d] seq_num_error did not stay set", scenario_id);
        error_scenario = 1'b1;
      end

      // Pulse rst_errors
      pulse_rst_errors();

      assert (master_error.seq_num_error == 1'b0) else begin $display("[ERROR:%0d] seq_num_error not cleared after rst_errors", scenario_id); error_scenario = 1'b1; end
      assert (master_error.write_error   == '0  ) else begin $display("[ERROR:%0d] write_error not cleared after rst_errors",   scenario_id); error_scenario = 1'b1; end

      // Complete the pending read request to clean up state
      wait_master_command_vld(5000, cmd_timed_out);
      assert (!cmd_timed_out) else begin
        $display("[ERROR:%0d] Timed out waiting for retry command", scenario_id);
        error_scenario = 1'b1;
      end
      consume_master_command();
      simulate_pulse(read_request_sent, clk_mhdma);
      feed_full_ciphertext(iop_id, hpu_id, req_mode, req_flag, iop_src_addr, iop_dst_addr);
      wait_interrupt_rr(5000, irq_timed_out);
      clear_signal(clear_interrupt_rr, clk_mhdma_cfg);
      repeat (20) @(posedge clk_mhdma);

      scenario_end(scenario_id, clk_mhdma_cfg);
    end
  endtask

// ============================================================================================== --
// Main test sequence
// ============================================================================================== --
  initial begin
    tb_init();
    scenario_id = 0;

    // Wait for resets to deassert
    wait (s_rstn_cfg == 1'b1);
    wait (s_rstn_mhdma == 1'b1);
    repeat (20) @(posedge clk_mhdma_cfg);

    // waiting a bit more time that CDC fifo are not reset busy..
    repeat (50) @(posedge clk_mhdma_cfg);

    run_scenario_notify_tx();
    run_scenario_notify_tx_timeout_retry();
    run_scenario_read_request();
    run_scenario_read_request_timeout_retry();
    run_scenario_seq_num_mismatch();
    run_scenario_axi4_page_boundary();
    run_scenario_axi4_write_error();
    run_scenario_ce_reception_ready();
    run_scenario_multiple_notifies();
    run_scenario_multiple_reads();
    run_scenario_statistics();
    run_scenario_error_reset();

    $display("\n==================================================================================================");
    $display("  All scenarios completed");
    $display("==================================================================================================");
    repeat (50) @(posedge clk_mhdma_cfg);
    end_of_test = 1'b1;
  end

// ============================================================================================== --
// SVA
// XSIM is fast enough for SVA in this test
// ============================================================================================== --

  // AXI4 protocol: awvalid must remain stable until awready
  generate
    for (genvar gen_pc = 0; gen_pc < ETH_PC; gen_pc++) begin : gen_sva_axi4

      // awvalid must not deassert without awready handshake
      property axi4_awvalid_stable;
        @(posedge clk_mhdma) disable iff (!s_rstn_mhdma)
        (m_axi4_awvalid[gen_pc] && !m_axi4_awready[gen_pc]) |=>
          $stable(m_axi4_awvalid[gen_pc]) && $stable(m_axi4_awaddr[gen_pc]) && $stable(m_axi4_awlen[gen_pc]);
      endproperty

      // wvalid must not deassert without wready handshake
      property axi4_wvalid_stable;
        @(posedge clk_mhdma) disable iff (!s_rstn_mhdma)
        (m_axi4_wvalid[gen_pc] && !m_axi4_wready[gen_pc]) |=>
          $stable(m_axi4_wvalid[gen_pc]) && $stable(m_axi4_wdata[gen_pc]) && $stable(m_axi4_wlast[gen_pc]);
      endproperty

      // awburst must always be INCR
      property axi4_awburst_incr;
        @(posedge clk_mhdma) disable iff (!s_rstn_mhdma)
        m_axi4_awvalid[gen_pc] |-> (m_axi4_awburst[gen_pc] == AXI4B_INCR);
      endproperty

      // awsize must be correct for AXI4_DATA_W
      property axi4_awsize_correct;
        @(posedge clk_mhdma) disable iff (!s_rstn_mhdma)
        m_axi4_awvalid[gen_pc] |-> (m_axi4_awsize[gen_pc] == MHDMA_ARSIZE);
      endproperty

      assert_awvalid_stable: assert property(axi4_awvalid_stable)
        else begin
          $display("[ERROR-SVA] PC%0d AW channel: value changed when awready was low", gen_pc);
          error_assert = 1'b1;
        end

      assert_wvalid_stable: assert property(axi4_wvalid_stable)
        else begin
          $display("[ERROR-SVA] PC%0d W channel: value changed when wready was low", gen_pc);
          error_assert = 1'b1;
        end

      assert_awburst_incr: assert property(axi4_awburst_incr)
        else begin
          $display("[ERROR-SVA] PC%0d AW channel: awburst is not INCR", gen_pc);
          error_assert = 1'b1;
        end

      assert_awsize_correct: assert property(axi4_awsize_correct)
        else begin
          $display("[ERROR-SVA] PC%0d AW channel: awsize is incorrect", gen_pc);
          error_assert = 1'b1;
        end

    end
  endgenerate

  // master_command_vld should deassert within 2 cycles after handshake
  // (1-cycle lag is expected: registered FSM state + fifo_element pipeline)
  property master_cmd_vld_deassert_after_handshake;
    @(posedge clk_mhdma) disable iff (!s_rstn_mhdma)
    (master_command_vld && master_command_rdy) |-> ##[1:2] !master_command_vld;
  endproperty

  assert_master_cmd_handshake: assert property(master_cmd_vld_deassert_after_handshake)
    else begin
      $display("[ERROR-SVA] master_command_vld did not deassert after handshake");
      error_assert = 1'b1;
    end

endmodule
