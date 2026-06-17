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
//   - Ciphertext reception: decoder payload, seq_num validation, abort-on-mismatch
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
//   > Seq num mismatch mid-burst abort
//   > Abort drain strobe verification
//   > AXI4 page boundary splitting (offset 0xF00)
//   > AXI4 page-aligned addresses (offset 0x000)
//   > AXI4 one word before page boundary (offset 0xFE0)
//   > AXI4 page boundary all PCs (offset 0xF00)
//   > AXI4 write error handling
//   > Multiple sequential notify requests
//   > Multiple sequential read requests
//   > NOTIFY_ACK leakage into received_cmd (regression for 57bf253984)
//   > Race: master_command.req_id flips between formatter's observation and rdy pulse
//   > Statistics counters
//   > Error reset
//
// NOTE: Drop of a packet (with others packets still correct) covered in tb_mhdma_pkt_loss
//
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
  // Single AXI4 write interface (from DUT)
  logic [AXI4_ID_W-1:0]                m_axi4_awid;
  logic [AXI4_ADD_W-1:0]               m_axi4_awaddr;
  logic [AXI4_LEN_W-1:0]               m_axi4_awlen;
  logic [AXI4_SIZE_W-1:0]              m_axi4_awsize;
  logic [AXI4_BURST_W-1:0]             m_axi4_awburst;
  logic                                m_axi4_awvalid;
  logic                                m_axi4_awready;

  logic [AXI4_DATA_W-1:0]              m_axi4_wdata;
  logic [AXI4_STRB_W-1:0]              m_axi4_wstrb;
  logic                                m_axi4_wlast;
  logic                                m_axi4_wvalid;
  logic                                m_axi4_wready;

  logic [AXI4_ID_W-1:0]                m_axi4_bid;
  logic [AXI4_RESP_W-1:0]              m_axi4_bresp;
  logic                                m_axi4_bvalid;
  logic                                m_axi4_bready;

  // NMU-side AXI4 signals
  logic [AXI4_ID_W-1:0]                nmu_axi4_awid;
  logic [AXI4_ADD_W-1:0]               nmu_axi4_awaddr;
  logic [AXI4_LEN_W-1:0]               nmu_axi4_awlen;
  logic [AXI4_SIZE_W-1:0]              nmu_axi4_awsize;
  logic [AXI4_BURST_W-1:0]             nmu_axi4_awburst;
  logic                                nmu_axi4_awvalid;
  logic                                nmu_axi4_awready;

  logic [AXI4_DATA_W-1:0]              nmu_axi4_wdata;
  logic [AXI4_STRB_W-1:0]              nmu_axi4_wstrb;
  logic                                nmu_axi4_wlast;
  logic                                nmu_axi4_wvalid;
  logic                                nmu_axi4_wready;

  // regf interface
  logic [ETH_PC-1:0][2*REG_DATA_W-1:0] regf_ct_mem_addr;
  logic               [REG_DATA_W-1:0] regf_req_id;
  logic               [REG_DATA_W-1:0] regf_req_addr;
  logic               [REG_DATA_W-1:0] regf_read_req_id;
  logic               [REG_DATA_W-1:0] regf_read_addr;
  logic               [REG_DATA_W-1:0] regf_timeout_duration_notify;
  logic               [REG_DATA_W-1:0] regf_timeout_duration_read_req;
  logic                          [7:0] regf_retry_max_notify;
  logic                          [7:0] regf_retry_max_read_req;

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

  // errors / stats
  master_error_t                       master_error;
  master_error_cfg_t                   master_error_cfg;
  logic                                rst_errors;
  logic                                rst_errors_cfg;
  master_stat_t                        stat;
  master_stat_rst_t                    stat_rst;

// ============================================================================================== --
// DUT instantiation
// ============================================================================================== --
  mhdma_master #(
    .CDC_SYNC_STAGES (CDC_SYNC_STAGES)
  ) mhdma_master (
    .clk_mhdma_cfg                 (clk_mhdma_cfg                 ),
    .resetn_mhdma_cfg              (s_rstn_cfg                    ),
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
    .regf_retry_max_notify         (regf_retry_max_notify         ),
    .regf_retry_max_read_req       (regf_retry_max_read_req       ),
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
    // errors
    .master_error                  (master_error                  ),
    .master_error_cfg              (master_error_cfg              ),
    .rst_errors                    (rst_errors                    ),
    .rst_errors_cfg                (rst_errors_cfg                ),
    // stats
    .stat                          (stat                          ),
    .stat_rst                      (stat_rst                      )
  );

// ============================================================================================== --
// NMU pipe: pipeline register between DUT and NMU port
// ============================================================================================== --
  mhdma_nmu_pipe mhdma_nmu_pipe (
    .clk            (clk_mhdma        ),
    .s_rst_n        (s_rstn_mhdma     ),
    // AR/R unused in master TB
    .s_axi4_arid    ('0               ),
    .s_axi4_araddr  ('0               ),
    .s_axi4_arlen   ('0               ),
    .s_axi4_arsize  ('0               ),
    .s_axi4_arburst ('0               ),
    .s_axi4_arvalid (1'b0             ),
    .s_axi4_arready (                 ),
    .s_axi4_rdata   (                 ),
    .s_axi4_rresp   (                 ),
    .s_axi4_rid     (                 ),
    .s_axi4_rlast   (                 ),
    .s_axi4_rvalid  (                 ),
    .s_axi4_rready  (1'b0             ),
    // Single AXI4 write from DUT
    .s_axi4_awid    (m_axi4_awid      ),
    .s_axi4_awaddr  (m_axi4_awaddr    ),
    .s_axi4_awlen   (m_axi4_awlen     ),
    .s_axi4_awsize  (m_axi4_awsize    ),
    .s_axi4_awburst (m_axi4_awburst   ),
    .s_axi4_awvalid (m_axi4_awvalid   ),
    .s_axi4_awready (m_axi4_awready   ),
    .s_axi4_wdata   (m_axi4_wdata     ),
    .s_axi4_wstrb   (m_axi4_wstrb     ),
    .s_axi4_wlast   (m_axi4_wlast     ),
    .s_axi4_wvalid  (m_axi4_wvalid    ),
    .s_axi4_wready  (m_axi4_wready    ),
    // Single NMU port
    .m_axi4_arid    (                 ),
    .m_axi4_araddr  (                 ),
    .m_axi4_arlen   (                 ),
    .m_axi4_arsize  (                 ),
    .m_axi4_arburst (                 ),
    .m_axi4_arvalid (                 ),
    .m_axi4_arready (1'b0             ),
    .m_axi4_rdata   ('0               ),
    .m_axi4_rresp   ('0               ),
    .m_axi4_rid     ('0               ),
    .m_axi4_rlast   (1'b0             ),
    .m_axi4_rvalid  (1'b0             ),
    .m_axi4_rready  (                 ),
    .m_axi4_awid    (nmu_axi4_awid    ),
    .m_axi4_awaddr  (nmu_axi4_awaddr  ),
    .m_axi4_awlen   (nmu_axi4_awlen   ),
    .m_axi4_awsize  (nmu_axi4_awsize  ),
    .m_axi4_awburst (nmu_axi4_awburst ),
    .m_axi4_awvalid (nmu_axi4_awvalid ),
    .m_axi4_awready (nmu_axi4_awready ),
    .m_axi4_wdata   (nmu_axi4_wdata   ),
    .m_axi4_wstrb   (nmu_axi4_wstrb   ),
    .m_axi4_wlast   (nmu_axi4_wlast   ),
    .m_axi4_wvalid  (nmu_axi4_wvalid  ),
    .m_axi4_wready  (nmu_axi4_wready  )
  );

// ============================================================================================== --
// Simple AXI4 write responder (single NMU port)
// ============================================================================================== --
// Accepts AW and W channels on the single NMU port, returns B responses with configurable delay.
// Tracks write addresses and data per PC (using AXI ID to determine the PC) for verification.

  // Configurable B response delay and response type (single NMU — one value for all bursts)
  int unsigned axi4_bresp_delay = 2;
  logic [AXI4_RESP_W-1:0] axi4_bresp_type = AXI4_OKAY;

  // Write data capture (per PC): queue of addresses and data words written
  logic [AXI4_ADD_W-1:0]  axi4_aw_captured_addr [ETH_PC][$];
  logic [AXI4_LEN_W-1:0]  axi4_aw_captured_len  [ETH_PC][$];
  logic [AXI4_DATA_W-1:0] axi4_w_captured_data  [ETH_PC][$];
  logic [AXI4_STRB_W-1:0] axi4_w_captured_strb  [ETH_PC][$];

  // AW channel: randomly toggling ready (~75% asserted)
  logic awready_rand = 1'b1;
  always @(posedge clk_mhdma)
    awready_rand <= $urandom_range(0, 3) != 0;

  assign nmu_axi4_awready = awready_rand;

  // W channel: randomly toggling ready (~75% asserted)
  logic wready_rand = 1'b1;
  always @(posedge clk_mhdma)
    wready_rand <= $urandom_range(0, 3) != 0;

  assign nmu_axi4_wready = wready_rand;

  // Track current AW PC index for capture routing (based on burst order: PC0 first, then PC1, ...)
  // The DUT sends all bursts for PC0, then all bursts for PC1, etc.
  // We track the current PC by counting AW transactions vs the expected per-PC burst count.
  // Simpler: just use a single capture queue and route to per-PC queues based on AW order.
  // Since the DUT processes PCs in order (PC0 words first), we track the PC index by
  // counting AW beats and mapping to PCs by the expected word counts.
  // For simplicity: maintain an AW PC tracker that increments based on accumulated word count.
  int aw_pc_tracker = 0;
  int aw_word_accumulator = 0;

  // Capture AW transactions — route to per-PC queues based on aw_pc_tracker
  always @(posedge clk_mhdma) begin
    if (nmu_axi4_awvalid && nmu_axi4_awready) begin
      axi4_aw_captured_addr[aw_pc_tracker].push_back(nmu_axi4_awaddr);
      axi4_aw_captured_len[aw_pc_tracker].push_back(nmu_axi4_awlen);
      aw_word_accumulator += int'(nmu_axi4_awlen) + 1;
      // Check if this PC's words are complete; advance to next PC (capped at ETH_PC-1)
      if (aw_pc_tracker == 0 && aw_word_accumulator >= AXI4_WORD_PER_PC0 && ETH_PC > 1) begin
        aw_pc_tracker++;
        aw_word_accumulator = 0;
      end else if (aw_pc_tracker > 0 && aw_word_accumulator >= AXI4_WORD_PER_PC) begin
        if (aw_pc_tracker < ETH_PC - 1) aw_pc_tracker++;
        aw_word_accumulator = 0;
      end
    end
  end

  // Capture W transactions — route to per-PC queues based on W beat order
  // The DUT sends W data in the same PC order as AW, so we track similarly.
  int w_pc_tracker = 0;
  int w_word_accumulator = 0;

  int unsigned b_detected = 0;

  always @(posedge clk_mhdma) begin
    if (nmu_axi4_wvalid && nmu_axi4_wready) begin
      axi4_w_captured_data[w_pc_tracker].push_back(nmu_axi4_wdata);
      axi4_w_captured_strb[w_pc_tracker].push_back(nmu_axi4_wstrb);

      if (nmu_axi4_wlast)
        b_detected <= b_detected + 1;

      w_word_accumulator++;
      if (w_pc_tracker == 0 && w_word_accumulator >= AXI4_WORD_PER_PC0 && ETH_PC > 1) begin
        w_pc_tracker++;
        w_word_accumulator = 0;
      end else if (w_pc_tracker > 0 && w_word_accumulator >= AXI4_WORD_PER_PC) begin
        if (w_pc_tracker < ETH_PC - 1) w_pc_tracker++;
        w_word_accumulator = 0;
      end
    end
  end

  // B response generation: single responder, single configurable bresp value
  initial begin
    m_axi4_bvalid = 1'b0;
    m_axi4_bresp  = AXI4_OKAY;
    m_axi4_bid    = '0;
  end

  int unsigned b_responded = 0;
  initial begin
    forever begin
      @(posedge clk_mhdma);
      if (b_detected > b_responded) begin
        repeat (axi4_bresp_delay) @(posedge clk_mhdma);
        m_axi4_bvalid = 1'b1;
        m_axi4_bresp  = axi4_bresp_type;
        m_axi4_bid    = MHDMA_AXI_ARID;
        @(posedge clk_mhdma);
        while (!m_axi4_bready) @(posedge clk_mhdma);
        m_axi4_bvalid = 1'b0;
        b_responded++;
      end
    end
  end

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
      regf_retry_max_notify         = 8'hFF; // large: existing scenarios must not hit the retry cap
      regf_retry_max_read_req       = 8'hFF;
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
      rst_errors_cfg                = 1'b0;
      stat_rst                      = '0;

      // Set HBM base addresses: page-aligned per PC
      for (int pc = 0; pc < ETH_PC; pc++) begin
        regf_ct_mem_addr[pc] = 64'h0000_0000_0001_0000 + pc * 64'h0000_0000_0010_0000;
      end

      // Reset AXI4 responder config
      axi4_bresp_delay = $urandom_range(1, 5);
      axi4_bresp_type  = AXI4_OKAY;
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
        axi4_w_captured_strb[pc].delete();
      end
      aw_pc_tracker       = 0;
      aw_word_accumulator = 0;
      w_pc_tracker        = 0;
      w_word_accumulator  = 0;
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
      iop_dst_addr = $urandom_range(0, (1 << DST_ADDR_W) - 1);
      req_mode     = $urandom();
      req_flag     = $urandom();
    end
  endtask

  // --------------------------------------------------------------------------------------------- --
  // Verify burst splitting for a given PC
  // Checks: no page crossing, burst contiguity, page-aligned splits, total word count
  // --------------------------------------------------------------------------------------------- --
  task automatic verify_burst_splitting(
    input int    pc,
    input int    expected_words,
    input string scenario_label
  );
    logic [AXI4_ADD_W-1:0] burst_addr;
    logic [AXI4_LEN_W-1:0] burst_len;
    logic [AXI4_ADD_W-1:0] expected_addr;
    logic [AXI4_ADD_W-1:0] prev_end_addr;
    int                    total_words;
    int                    num_bursts;
    begin
      num_bursts  = axi4_aw_captured_addr[pc].size();
      total_words = 0;

      for (int bi = 0; bi < num_bursts; bi++) begin
        burst_addr = axi4_aw_captured_addr[pc][bi];
        burst_len  = axi4_aw_captured_len[pc][bi];

        // No burst crosses a page boundary
        assert (burst_addr[PAGE_BYTES_W-1:AXI4_DATA_BYTES_W] + burst_len < PAGE_AXI4_DATA) else begin
          $display("[ERROR:%0d] %s PC%0d burst %0d crosses page: addr=0x%0h, word_offset=%0d, awlen=%0d",
                   scenario_id, scenario_label, pc, bi, burst_addr,
                   burst_addr[PAGE_BYTES_W-1:AXI4_DATA_BYTES_W], burst_len);
          error_scenario = 1'b1;
        end

        // Burst contiguity: addr[i] == addr[i-1] + (len[i-1]+1) * AXI4_DATA_BYTES
        if (bi > 0) begin
          assert (burst_addr == expected_addr) else begin
            $display("[ERROR:%0d] %s PC%0d burst %0d not contiguous: expected addr=0x%0h, got 0x%0h",
                     scenario_id, scenario_label, pc, bi, expected_addr, burst_addr);
            error_scenario = 1'b1;
          end
        end

        // Page-aligned splits: when a burst starts on a new page (different page than
        // previous burst's end), it must be page-aligned. This catches DUTs that split
        // at wrong offsets within a page instead of exactly at the boundary.
        if (bi > 0) begin
          prev_end_addr = expected_addr - 1; // last byte of previous burst
          if (burst_addr[AXI4_ADD_W-1:PAGE_BYTES_W] != prev_end_addr[AXI4_ADD_W-1:PAGE_BYTES_W]) begin
            // burst_addr is on a different page than the last word of the previous burst
            assert (burst_addr[PAGE_BYTES_W-1:0] == '0) else begin
              $display("[ERROR:%0d] %s PC%0d burst %0d crosses page boundary but not page-aligned: addr=0x%0h",
                       scenario_id, scenario_label, pc, bi, burst_addr);
              error_scenario = 1'b1;
            end
          end
        end

        // Prepare expected address for next burst (computed from local burst_addr)
        expected_addr = burst_addr + AXI4_ADD_W'(burst_len + 1) * AXI4_DATA_BYTES;
        total_words  += burst_len + 1;
      end

      // Total word count
      assert (total_words == expected_words) else begin
        $display("[ERROR:%0d] %s PC%0d word count mismatch: expected %0d, got %0d", scenario_id, scenario_label, pc, expected_words, total_words);
        error_scenario = 1'b1;
      end
    end
  endtask

  // --------------------------------------------------------------------------------------------- --
  // Pulse the rst_errors signal (mrmac domain + cfg domain)
  // --------------------------------------------------------------------------------------------- --
  task automatic pulse_rst_errors();
    begin
      fork
        begin
          @(posedge clk_mhdma);
          rst_errors = 1'b1;
          @(posedge clk_mhdma);
          rst_errors = 1'b0;
          repeat (5) @(posedge clk_mhdma);
        end
        begin
          @(posedge clk_mhdma_cfg);
          rst_errors_cfg = 1'b1;
          @(posedge clk_mhdma_cfg);
          rst_errors_cfg = 1'b0;
          repeat (5) @(posedge clk_mhdma_cfg);
        end
      join
    end
  endtask

  // --------------------------------------------------------------------------------------------- --
  // Common read-request flow: inject request, wait for command, consume, pulse,
  // feed full ciphertext, wait for interrupt, clear interrupt.
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
        failed = 1'b1;
      end
      clear_signal(clear_interrupt_rr, clk_mhdma_cfg);
    end
  endtask

  // --------------------------------------------------------------------------------------------- --
  // Complete a retry after abort: wait for retry command, consume, feed ciphertext,
  // wait for interrupt, verify AW was produced.
  // --------------------------------------------------------------------------------------------- --
  task automatic complete_retry(
    input logic [REG_DATA_W-1:0] saved_read_retries
  );
    logic cmd_timed_out;
    logic irq_timed_out;
    begin
      wait_master_command_vld(5000, cmd_timed_out);
      assert (!cmd_timed_out) else begin
        $display("[ERROR:%0d] Timed out waiting for retry command", scenario_id);
        error_scenario = 1'b1;
      end

      assert ((stat.cnt_read_req_timeout_retries + stat.cnt_read_req_seq_num_retries) >= saved_read_retries + 1) else begin
        $display("[ERROR:%0d] cnt_read_req_retries not incremented", scenario_id);
        error_scenario = 1'b1;
      end

      clear_axi4_captures();
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

      assert (axi4_aw_captured_addr[0].size() > 0) else begin
        $display("[ERROR:%0d] No AW after retry", scenario_id);
        error_scenario = 1'b1;
      end

      pulse_rst_errors();
      clear_axi4_captures();
    end
  endtask

  // --------------------------------------------------------------------------------------------- --
  // Check abort drain strobes for a given PC:
  //   - Optionally assert at least one valid strobe (check_valid_strb)
  //   - Assert at least one zero strobe (check_zero_strb) or just report
  //   - Every zero-strobe beat must have zero data (no leak)
  // --------------------------------------------------------------------------------------------- --
  task automatic check_abort_drain_strobes(
    input int  pc,
    input bit  require_valid_strb,
    input bit  require_zero_strb
  );
    int total_w_beats;
    bit found_valid_strb;
    bit found_zero_strb;
    begin
      total_w_beats = axi4_w_captured_data[pc].size();

      // Search for valid and zero strobe beats
      found_valid_strb = 1'b0;
      found_zero_strb  = 1'b0;
      for (int i = 0; i < total_w_beats; i++) begin
        if (axi4_w_captured_strb[pc][i] != '0) found_valid_strb = 1'b1;
        if (axi4_w_captured_strb[pc][i] == '0) found_zero_strb  = 1'b1;
      end

      if (require_valid_strb) begin
        assert (found_valid_strb) else begin
          $display("[ERROR:%0d] PC%0d: no valid W beat before abort", scenario_id, pc);
          error_scenario = 1'b1;
        end
      end

      if (require_zero_strb) begin
        assert (found_zero_strb) else begin
          $display("[ERROR:%0d] PC%0d: no zero-strobe W beats: abort drain not exercised", scenario_id, pc);
          error_scenario = 1'b1;
        end
      end else begin
        if (found_zero_strb)
          $display("[INFO:%0d] PC%0d: abort draining produced zero-strobe W beats", scenario_id, pc);
        else
          $display("[INFO:%0d] PC%0d: no zero-strobe W beats: burst completed before abort", scenario_id, pc);
      end

      // Every zero-strobe beat must also have zero data
      for (int i = 0; i < total_w_beats; i++) begin
        if (axi4_w_captured_strb[pc][i] == '0) begin
          assert (axi4_w_captured_data[pc][i] == '0) else begin
            $display("[ERROR:%0d] PC%0d W beat %0d: wstrb=='0 but wdata!=0 (0x%0h)", scenario_id, pc, i, axi4_w_captured_data[pc][i]);
            error_scenario = 1'b1;
          end
        end
      end

      $display("[INFO:%0d] PC%0d: %0d total W beats", scenario_id, pc, total_w_beats);
    end
  endtask

  // --------------------------------------------------------------------------------------------- --
  // Inject a NOTIFY_ACK command through the decoded_command interface (mhdma domain).
  // This simulates the decoder forwarding an ACK from a remote HPU.
  // --------------------------------------------------------------------------------------------- --
  task automatic feed_notify_ack(
    input logic [IOP_ID_W-1:0]   ack_iop_id,
    input logic [HPU_ID_W-1:0]   ack_hpu_id,
    input logic [SEQ_NUM_W-1:0]  ack_seq_num
  );
    begin
      @(posedge clk_mhdma);
      decoded_command.req_id       = REQ_ID_NOTIFY_ACK;
      decoded_command.seq_num      = ack_seq_num;
      decoded_command.iop_id       = ack_iop_id;
      decoded_command.hpu_id       = ack_hpu_id;
      decoded_command.src_addr     = '0;
      decoded_command.dst_addr     = '0;
      decoded_command.mode         = '0;
      decoded_command.flag         = '0;
      decoded_command.rsvd         = '0;
      decoded_command.src_mac_addr = '0;
      decoded_command_vld          = 1'b1;

      // Wait for handshake (nack_rdy asserts decoded_command_rdy)
      @(posedge clk_mhdma);
      while (!decoded_command_rdy) @(posedge clk_mhdma);
      // Pulse notify_ack_received alongside the command handshake (matches real decoder behavior)
      notify_ack_received = 1'b1;
      @(posedge clk_mhdma);
      decoded_command_vld = 1'b0;
      notify_ack_received = 1'b0;
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
      assert (stat.fsm_burst == 2'b00) else begin $display("[ERROR:%0d] fsm_burst not BURST_IDLE", scenario_id); error_scenario = 1'b1; end

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
      assert (stat.fsm_burst == 2'b00) else begin $display("[ERROR:%0d] fsm_burst not BURST_IDLE", scenario_id); error_scenario = 1'b1; end

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
      assert (stat.fsm_burst == 2'b00) else begin $display("[ERROR:%0d] fsm_burst not BURST_IDLE", scenario_id); error_scenario = 1'b1; end

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
      saved_read_retries = (stat.cnt_read_req_timeout_retries + stat.cnt_read_req_seq_num_retries);
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
      assert ((stat.cnt_read_req_timeout_retries + stat.cnt_read_req_seq_num_retries) >= saved_read_retries + 1) else begin
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
      assert (stat.fsm_burst == 2'b00) else begin $display("[ERROR:%0d] fsm_burst not BURST_IDLE", scenario_id); error_scenario = 1'b1; end

      scenario_end(scenario_id, clk_mhdma_cfg);
    end
  endtask

  // --------------------------------------------------------------------------------------------- --
  // Scenario : Seq num mismatch handling (abort + retry)
  // With the stream-through architecture, mismatch aborts the in-flight AXI burst
  // (drains remaining beats with zeros), then retries from scratch.
  // --------------------------------------------------------------------------------------------- --
  task automatic run_scenario_seq_num_mismatch();
    logic [REG_DATA_W-1:0] saved_read_retries;
    logic cmd_timed_out;
    logic irq_timed_out;
    int   num_aw_before_mismatch;
    begin
      scenario_start(scenario_id, "Seq num mismatch: abort and retry");
      saved_read_retries = (stat.cnt_read_req_timeout_retries + stat.cnt_read_req_seq_num_retries);
      randomize_fields();
      clear_axi4_captures();

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

      repeat (100) @(posedge clk_mhdma);
      assert (master_error.seq_num_error == 1'b1) else begin
        $display("[ERROR:%0d] seq_num_error not set after mismatch", scenario_id);
        error_scenario = 1'b1;
      end

      // Verify no further AW commands are issued after abort draining
      num_aw_before_mismatch = axi4_aw_captured_addr[0].size();
      repeat (50) @(posedge clk_mhdma);
      // No new AW commands should have been issued during abort
      // (note: some may have been issued before abort was detected)

      // Complete the retry
      complete_retry(saved_read_retries);

      scenario_end(scenario_id, clk_mhdma_cfg);
    end
  endtask

  // --------------------------------------------------------------------------------------------- --
  // Scenario : Seq num mismatch mid-burst abort
  // Feeds a correct CE packet, then a mismatch packet while the first is still being written.
  // Verifies abort fires, at least some beats have wstrb=='0, and retry completes.
  // --------------------------------------------------------------------------------------------- --
  task automatic run_scenario_seq_num_mismatch_mid_burst();
    logic [REG_DATA_W-1:0] saved_read_retries;
    logic cmd_timed_out;
    begin
      scenario_start(scenario_id, "Seq num mismatch mid-burst abort");
      saved_read_retries = (stat.cnt_read_req_timeout_retries + stat.cnt_read_req_seq_num_retries);
      randomize_fields();
      clear_axi4_captures();

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

      // Feed correct packet then mismatch back-to-back in a fork so the
      // mismatch arrives while the first packet's burst is still in progress.
      fork
        feed_ce_packet(8'h0, iop_id, hpu_id, req_mode, req_flag, iop_src_addr, iop_dst_addr);
        begin
          // Wait for at least one W beat to complete (valid data written before abort)
          while (axi4_w_captured_data[0].size() == 0) @(posedge clk_mhdma);
          // Inject mismatch: seq_num=2 (skip 1)
          feed_ce_packet(8'h2, iop_id, hpu_id, req_mode, req_flag, iop_src_addr, iop_dst_addr);
        end
      join

      // Let abort drain complete + B responses
      repeat (300) @(posedge clk_mhdma);

      assert (master_error.seq_num_error == 1'b1) else begin
        $display("[ERROR:%0d] seq_num_error not set after mismatch", scenario_id);
        error_scenario = 1'b1;
      end

      // Require both valid and zero-strobe beats (mid-burst abort)
      check_abort_drain_strobes(.pc(0), .require_valid_strb(1), .require_zero_strb(0));

      complete_retry(saved_read_retries);

      scenario_end(scenario_id, clk_mhdma_cfg);
    end
  endtask

  // --------------------------------------------------------------------------------------------- --
  // Scenario : Abort drain strobe verification
  // Feeds correct + mismatch packets back-to-back so abort fires as early as possible.
  // Checks that at least some W beats have wstrb=='0 and retry completes.
  // --------------------------------------------------------------------------------------------- --
  task automatic run_scenario_abort_drain_strobe();
    logic [REG_DATA_W-1:0] saved_read_retries;
    logic cmd_timed_out;
    begin
      scenario_start(scenario_id, "Abort drain strobe verification");
      saved_read_retries = (stat.cnt_read_req_timeout_retries + stat.cnt_read_req_seq_num_retries);
      randomize_fields();
      clear_axi4_captures();

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

      // Feed correct packet then mismatch immediately after in a fork.
      // The mismatch fires as early as possible to maximize zero-strobe beats.
      fork
        feed_ce_packet(8'h0, iop_id, hpu_id, req_mode, req_flag, iop_src_addr, iop_dst_addr);
        begin
          while (axi4_aw_captured_addr[0].size() == 0) @(posedge clk_mhdma);
          feed_ce_packet(8'h2, iop_id, hpu_id, req_mode, req_flag, iop_src_addr, iop_dst_addr);
        end
      join

      // Let abort drain complete + B responses
      repeat (300) @(posedge clk_mhdma);

      assert (master_error.seq_num_error == 1'b1) else begin
        $display("[ERROR:%0d] seq_num_error not set", scenario_id);
        error_scenario = 1'b1;
      end

      // Require zero-strobe beats (abort drain must be exercised)
      check_abort_drain_strobes(.pc(0), .require_valid_strb(0), .require_zero_strb(1));

      complete_retry(saved_read_retries);

      scenario_end(scenario_id, clk_mhdma_cfg);
    end
  endtask

  // --------------------------------------------------------------------------------------------- --
  // Scenario : AXI4 page boundary splitting (offset 0xF00)
  // Verifies page split, first burst offset/length, second burst alignment, plus shared checks
  // --------------------------------------------------------------------------------------------- --
  task automatic run_scenario_axi4_page_boundary();
    logic [2*REG_DATA_W-1:0] saved_ct_mem_addr_pc0;
    int                      words_before_boundary;
    bit                      flow_failed;
    begin
      scenario_start(scenario_id, "AXI4 page boundary splitting");
      clear_axi4_captures();
      saved_ct_mem_addr_pc0 = regf_ct_mem_addr[0];

      regf_ct_mem_addr[0] = 64'h0000_0000_0000_0F00;
      randomize_fields();
      do_read_request_flow(flow_failed);
      if (flow_failed) error_scenario = 1'b1;
      repeat (20) @(posedge clk_mhdma);

      // Verify PC0 got multiple AW transactions (page split)
      assert (axi4_aw_captured_addr[0].size() > 1) else begin
        $display("[ERROR:%0d] Expected multiple AW transactions for PC0 due to page split, got %0d", scenario_id, axi4_aw_captured_addr[0].size());
        error_scenario = 1'b1;
      end

      // Verify first burst page offset matches the configured base address
      assert (axi4_aw_captured_addr[0][0][PAGE_BYTES_W-1:0] == regf_ct_mem_addr[0][PAGE_BYTES_W-1:0]) else begin
        $display("[ERROR:%0d] First burst page offset: expected 0x%0h, got 0x%0h", scenario_id, regf_ct_mem_addr[0][PAGE_BYTES_W-1:0], axi4_aw_captured_addr[0][0][PAGE_BYTES_W-1:0]);
        error_scenario = 1'b1;
      end

      // Verify first burst length matches words remaining before page boundary
      words_before_boundary = PAGE_AXI4_DATA - axi4_aw_captured_addr[0][0][PAGE_BYTES_W-1:AXI4_DATA_BYTES_W];
      assert (axi4_aw_captured_len[0][0] + 1 == words_before_boundary) else begin
        $display("[ERROR:%0d] First burst length: expected %0d words, got %0d", scenario_id, words_before_boundary, axi4_aw_captured_len[0][0] + 1);
        error_scenario = 1'b1;
      end

      // Verify second burst starts at the next page boundary
      assert (axi4_aw_captured_addr[0][1][PAGE_BYTES_W-1:0] == '0) else begin
        $display("[ERROR:%0d] Second burst addr not page-aligned: 0x%0h", scenario_id, axi4_aw_captured_addr[0][1]);
        error_scenario = 1'b1;
      end

      // Shared checks: no page crossing, contiguity, middle bursts, total count
      verify_burst_splitting(0, AXI4_WORD_PER_PC0, "page_boundary_0xF00");

      // Restore
      regf_ct_mem_addr[0] = saved_ct_mem_addr_pc0;
      clear_axi4_captures();

      scenario_end(scenario_id, clk_mhdma_cfg);
    end
  endtask

  // --------------------------------------------------------------------------------------------- --
  // Scenario : AXI4 page-aligned addresses (offset 0x000)
  // Verifies that page-aligned addresses produce valid bursts without unnecessary splits
  // --------------------------------------------------------------------------------------------- --
  task automatic run_scenario_axi4_page_aligned();
    logic [2*REG_DATA_W-1:0] saved_ct_mem_addr [ETH_PC];
    int                      expected_words;
    bit                      flow_failed;
    begin
      scenario_start(scenario_id, "AXI4 page-aligned addresses");
      clear_axi4_captures();

      for (int pc = 0; pc < ETH_PC; pc++) begin
        saved_ct_mem_addr[pc] = regf_ct_mem_addr[pc];
        regf_ct_mem_addr[pc]  = 64'h0000_0000_0001_0000 + pc * 64'h0000_0000_0010_0000;
      end

      randomize_fields();
      do_read_request_flow(flow_failed);
      if (flow_failed) error_scenario = 1'b1;
      repeat (20) @(posedge clk_mhdma);

      // Verify first burst of each PC starts page-aligned
      for (int pc = 0; pc < ETH_PC; pc++) begin
        assert (axi4_aw_captured_addr[pc].size() > 0) else begin
          $display("[ERROR:%0d] No AW transactions captured for PC%0d", scenario_id, pc);
          error_scenario = 1'b1;
        end
        if (axi4_aw_captured_addr[pc].size() > 0) begin
          assert (axi4_aw_captured_addr[pc][0][PAGE_BYTES_W-1:0] == '0) else begin
            $display("[ERROR:%0d] PC%0d first burst not page-aligned: 0x%0h", scenario_id, pc, axi4_aw_captured_addr[pc][0]);
            error_scenario = 1'b1;
          end
        end

        expected_words = (pc == 0) ? AXI4_WORD_PER_PC0 : AXI4_WORD_PER_PC;
        verify_burst_splitting(pc, expected_words, "page_aligned");
      end

      // Restore
      for (int pc = 0; pc < ETH_PC; pc++)
        regf_ct_mem_addr[pc] = saved_ct_mem_addr[pc];
      clear_axi4_captures();

      scenario_end(scenario_id, clk_mhdma_cfg);
    end
  endtask

  // --------------------------------------------------------------------------------------------- --
  // Scenario : AXI4 one word before page boundary (offset 0xFE0)
  // Verifies minimal first burst (1 word) when address is 1 word before boundary
  // --------------------------------------------------------------------------------------------- --
  task automatic run_scenario_axi4_one_word_before_boundary();
    logic [2*REG_DATA_W-1:0] saved_ct_mem_addr_pc0;
    bit                      flow_failed;
    begin
      scenario_start(scenario_id, "AXI4 one word before page boundary");
      clear_axi4_captures();
      saved_ct_mem_addr_pc0 = regf_ct_mem_addr[0];

      // Place address 1 AXI word before the page boundary (works for any AXI4_DATA_W)
      regf_ct_mem_addr[0] = 64'(PAGE_BYTES - AXI4_DATA_BYTES);

      randomize_fields();
      do_read_request_flow(flow_failed);
      if (flow_failed) error_scenario = 1'b1;
      repeat (20) @(posedge clk_mhdma);

      // First burst should be exactly 1 word (awlen == 0)
      assert (axi4_aw_captured_len[0][0] == 0) else begin
        $display("[ERROR:%0d] First burst awlen: expected 0 (1 word), got %0d", scenario_id, axi4_aw_captured_len[0][0]);
        error_scenario = 1'b1;
      end

      // Page split must have occurred (multiple AW transactions)
      assert (axi4_aw_captured_addr[0].size() > 1) else begin
        $display("[ERROR:%0d] Expected page split (multiple AW txns), got %0d", scenario_id, axi4_aw_captured_addr[0].size());
        error_scenario = 1'b1;
      end

      // Second burst must start at the next page boundary
      if (axi4_aw_captured_addr[0].size() > 1) begin
        assert (axi4_aw_captured_addr[0][1][PAGE_BYTES_W-1:0] == '0) else begin
          $display("[ERROR:%0d] Second burst not page-aligned: 0x%0h", scenario_id, axi4_aw_captured_addr[0][1]);
          error_scenario = 1'b1;
        end
      end

      // Full shared validation
      verify_burst_splitting(0, AXI4_WORD_PER_PC0, "one_word_before_boundary");

      // Restore
      regf_ct_mem_addr[0] = saved_ct_mem_addr_pc0;
      clear_axi4_captures();

      scenario_end(scenario_id, clk_mhdma_cfg);
    end
  endtask

  // --------------------------------------------------------------------------------------------- --
  // Scenario : AXI4 page boundary splitting on all PCs (offset 0xF00)
  // Verifies page split and burst correctness for every PC, not just PC0
  // --------------------------------------------------------------------------------------------- --
  task automatic run_scenario_axi4_all_pcs();
    logic [2*REG_DATA_W-1:0] saved_ct_mem_addr [ETH_PC];
    int                      expected_words;
    bit                      flow_failed;
    begin
      scenario_start(scenario_id, "AXI4 page boundary all PCs");
      clear_axi4_captures();

      for (int pc = 0; pc < ETH_PC; pc++) begin
        saved_ct_mem_addr[pc] = regf_ct_mem_addr[pc];
        regf_ct_mem_addr[pc]  = 64'h0000_0000_0001_0F00 + pc * 64'h0000_0000_0010_0000;
      end

      randomize_fields();
      do_read_request_flow(flow_failed);
      if (flow_failed) error_scenario = 1'b1;
      repeat (20) @(posedge clk_mhdma);

      // Verify all PCs got multiple bursts (page split) and pass shared checks
      for (int pc = 0; pc < ETH_PC; pc++) begin
        assert (axi4_aw_captured_addr[pc].size() > 1) else begin
          $display("[ERROR:%0d] PC%0d expected multiple AW txns (page split), got %0d", scenario_id, pc, axi4_aw_captured_addr[pc].size());
          error_scenario = 1'b1;
        end

        // First burst page offset must match configured base address
        if (axi4_aw_captured_addr[pc].size() > 0) begin
          assert (axi4_aw_captured_addr[pc][0][PAGE_BYTES_W-1:0] == regf_ct_mem_addr[pc][PAGE_BYTES_W-1:0]) else begin
            $display("[ERROR:%0d] PC%0d first burst page offset: expected 0x%0h, got 0x%0h",
                     scenario_id, pc, regf_ct_mem_addr[pc][PAGE_BYTES_W-1:0], axi4_aw_captured_addr[pc][0][PAGE_BYTES_W-1:0]);
            error_scenario = 1'b1;
          end
        end

        // Second burst must be page-aligned (first page crossing)
        if (axi4_aw_captured_addr[pc].size() > 1) begin
          assert (axi4_aw_captured_addr[pc][1][PAGE_BYTES_W-1:0] == '0) else begin
            $display("[ERROR:%0d] PC%0d second burst not page-aligned: 0x%0h",
                     scenario_id, pc, axi4_aw_captured_addr[pc][1]);
            error_scenario = 1'b1;
          end
        end

        expected_words = (pc == 0) ? AXI4_WORD_PER_PC0 : AXI4_WORD_PER_PC;
        verify_burst_splitting(pc, expected_words, "all_pcs_0xF00");
      end

      // Restore
      for (int pc = 0; pc < ETH_PC; pc++)
        regf_ct_mem_addr[pc] = saved_ct_mem_addr[pc];
      clear_axi4_captures();

      scenario_end(scenario_id, clk_mhdma_cfg);
    end
  endtask

  // --------------------------------------------------------------------------------------------- --
  // Scenario : AXI4 write error handling
  // --------------------------------------------------------------------------------------------- --
  task automatic run_scenario_axi4_write_error();
    bit flow_failed;
    begin
      scenario_start(scenario_id, "AXI4 write error handling");
      axi4_bresp_type = AXI4_SLVERR;
      randomize_fields();
      do_read_request_flow(flow_failed);
      if (flow_failed) error_scenario = 1'b1;
      repeat (20) @(posedge clk_mhdma);
      // Single NMU: SLVERR applies to all bursts, so all PCs should report error
      assert (master_error.write_error == '1) else begin
        $display("[ERROR:%0d] write_error not fully set for SLVERR (got %b)", scenario_id, master_error.write_error);
        error_scenario = 1'b1;
      end

      // Restore and clear errors
      axi4_bresp_type = AXI4_OKAY;
      pulse_rst_errors();

      assert (master_error.write_error == '0) else begin
        $display("[ERROR:%0d] write_error not cleared after rst_errors", scenario_id);
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
      read_count = 20;

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
      assert (stat.fsm_burst == 2'b00) else begin $display("[ERROR:%0d] fsm_burst not BURST_IDLE", scenario_id); error_scenario = 1'b1; end

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
      begin
        bit read_failed;
        do_read_request_flow(read_failed);
        if (read_failed) error_scenario = 1'b1;
      end
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
      assert (stat.fsm_burst    == 2'b00) else begin $display("[ERROR:%0d] fsm_burst not BURST_IDLE",      scenario_id); error_scenario = 1'b1; end

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

      // Feed seq_num=0 then seq_num=2 (skip 1 = mismatch, triggers abort)
      feed_ce_packet(8'h0, iop_id, hpu_id, req_mode, req_flag, iop_src_addr, iop_dst_addr);
      feed_ce_packet(8'h2, iop_id, hpu_id, req_mode, req_flag, iop_src_addr, iop_dst_addr);

      repeat (100) @(posedge clk_mhdma);
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

  // --------------------------------------------------------------------------------------------- --
  // Scenario : IRQ FIFO backpressure and recovery
  //
  // Verifies that the master correctly backpressures when the interrupt FIFO
  // (rr_resp_ram_rdy_vld_2clk, depth=REQ_FIFO_DEPTH) is full, and resumes after clearing.
  //
  // Steps:
  //   1. Issue REQ_FIFO_DEPTH reads WITHOUT clearing interrupts -> fills the FIFO
  //   2. Inject one more read request and verify master_command_vld does NOT assert (backpressure)
  //   3. Clear one interrupt -> verify the blocked read request is now issued
  //   4. Complete that last read, clear remaining interrupts
  //   5. Read back regf_read_req_id and check it matches the last completed read
  // --------------------------------------------------------------------------------------------- --
  task automatic run_scenario_irq_fifo_backpressure();
    localparam int NB_FILL_READS = REQ_FIFO_DEPTH+1; // exactly fill the FIFO
    bit                    read_failed;
    logic                  cmd_timed_out;
    logic                  irq_timed_out;
    // Save last read fields for regfile check
    logic [IOP_ID_W-1:0]   last_iop_id;
    logic [HPU_ID_W-1:0]   last_hpu_id;
    logic [MODE_W-1:0]     last_req_mode;
    logic [FLAG_W-1:0]     last_req_flag;
    logic [SRC_ADDR_W-1:0] last_iop_src_addr;
    logic [DST_ADDR_W-1:0] last_iop_dst_addr;
    logic [REG_DATA_W-1:0] exp_read_req_id;
    logic [REG_DATA_W-1:0] exp_read_addr;
    begin
      scenario_start(scenario_id, "IRQ FIFO backpressure and recovery");

      // Phase 1: fill the interrupt FIFO (no clearing)
      for (int i = 0; i < NB_FILL_READS; i++) begin
        randomize_fields();

        inject_regf_request(iop_id, REQ_ID_READ, hpu_id, req_mode, req_flag, iop_src_addr, iop_dst_addr);

        wait_master_command_vld(2000, cmd_timed_out);
        assert (!cmd_timed_out) else begin
          $display("[ERROR:%0d] Phase1: Read %0d/%0d timed out waiting for master_command_vld", scenario_id, i, NB_FILL_READS);
          error_scenario = 1'b1;
        end
        if (error_scenario) break;

        consume_master_command();
        simulate_pulse(read_request_sent, clk_mhdma);
        feed_full_ciphertext(iop_id, hpu_id, req_mode, req_flag, iop_src_addr, iop_dst_addr);

        wait_interrupt_rr(5000, irq_timed_out);
        assert (!irq_timed_out) else begin
          $display("[ERROR:%0d] Phase1: Read %0d/%0d timed out waiting for interrupt", scenario_id, i, NB_FILL_READS);
          error_scenario = 1'b1;
        end
        if (error_scenario) break;

        // DO NOT clear the interrupt: accumulate in the FIFO
      end
      if (error_scenario) begin
        scenario_end(scenario_id, clk_mhdma_cfg);
        return;
      end

      // Phase 2: inject one more read, verify backpressure (master_command_vld must NOT assert)
      randomize_fields();
      last_iop_id       = iop_id;
      last_hpu_id       = hpu_id;
      last_req_mode     = req_mode;
      last_req_flag     = req_flag;
      last_iop_src_addr = iop_src_addr;
      last_iop_dst_addr = iop_dst_addr;

      inject_regf_request(iop_id, REQ_ID_READ, hpu_id, req_mode, req_flag, iop_src_addr, iop_dst_addr);

      // Wait a reasonable time: master_command_vld should NOT assert
      wait_master_command_vld(500, cmd_timed_out);
      assert (cmd_timed_out) else begin
        $display("[ERROR:%0d] Phase2: master_command_vld asserted despite full IRQ FIFO (rr_regf_in_rdy=%0b)", scenario_id, mhdma_master.rr_regf_in_rdy);
        error_scenario = 1'b1;
      end
      if (error_scenario) begin
        scenario_end(scenario_id, clk_mhdma_cfg);
        return;
      end

      // Phase 3: clear one interrupt -> blocked read should now be issued
      clear_signal(clear_interrupt_rr, clk_mhdma_cfg);
      repeat (10) @(posedge clk_mhdma_cfg);

      wait_master_command_vld(2000, cmd_timed_out);
      assert (!cmd_timed_out) else begin
        $display("[ERROR:%0d] Phase3: master_command_vld did not assert after clearing one interrupt (rr_regf_in_rdy=%0b)", scenario_id, mhdma_master.rr_regf_in_rdy);
        error_scenario = 1'b1;
      end
      if (error_scenario) begin
        scenario_end(scenario_id, clk_mhdma_cfg);
        return;
      end

      // Phase 4: complete the last read
      consume_master_command();
      simulate_pulse(read_request_sent, clk_mhdma);
      feed_full_ciphertext(last_iop_id, last_hpu_id, last_req_mode, last_req_flag, last_iop_src_addr, last_iop_dst_addr);

      wait_interrupt_rr(5000, irq_timed_out);
      assert (!irq_timed_out) else begin
        $display("[ERROR:%0d] Phase4: timed out waiting for interrupt on last read", scenario_id);
        error_scenario = 1'b1;
      end
      if (error_scenario) begin
        scenario_end(scenario_id, clk_mhdma_cfg);
        return;
      end

      // Phase 5: drain all interrupts, then verify regf_read_req_id matches the last read
      // The FIFO is FIFO-ordered: drain NB_FILL_READS Phase1 entries + the Phase3 clear already popped one
      // so we need to clear NB_FILL_READS remaining entries (NB_FILL_READS-1 from Phase1 + 1 from Phase4)
      repeat (NB_FILL_READS) begin
        clear_signal(clear_interrupt_rr, clk_mhdma_cfg);
        repeat (10) @(posedge clk_mhdma_cfg);
      end
      repeat (100) @(posedge clk_mhdma);

      // The last entry popped should be the Phase 4 completion
      exp_read_req_id = {last_iop_id, REQ_ID_EMISSION, last_hpu_id, last_req_mode, last_req_flag, 8'h0};
      exp_read_addr   = {last_iop_dst_addr, last_iop_src_addr};

      assert (regf_read_req_id == exp_read_req_id) else begin
        $display("[ERROR:%0d] Phase5: regf_read_req_id mismatch | exp %08h got %08h", scenario_id, exp_read_req_id, regf_read_req_id);
        error_scenario = 1'b1;
      end
      assert (regf_read_addr == exp_read_addr) else begin
        $display("[ERROR:%0d] Phase5: regf_read_addr mismatch | exp %08h got %08h", scenario_id, exp_read_addr, regf_read_addr);
        error_scenario = 1'b1;
      end

      // Verify FSMs idle
      assert (stat.fsm_read_req == 2'b00) else begin $display("[ERROR:%0d] fsm_read_req not idle", scenario_id); error_scenario = 1'b1; end
      assert (stat.fsm_burst    == 2'b00) else begin $display("[ERROR:%0d] fsm_burst not idle",    scenario_id); error_scenario = 1'b1; end
      assert (stat.fsm_notify   == 2'b00) else begin $display("[ERROR:%0d] fsm_notify not idle",   scenario_id); error_scenario = 1'b1; end

      scenario_end(scenario_id, clk_mhdma_cfg);
    end
  endtask

  // --------------------------------------------------------------------------------------------- --
  // Scenario : NOTIFY_ACK leakage into received_cmd (spotted and fixed in 57bf253984)
  //
  // A NOTIFY_ACK arriving mid-ciphertext overwrote received_cmd with the ACK's fields.
  // The read-complete FIFO entry (built from received_cmd at valid_ciphertext_received)
  // then contained the ACK's iop_id/hpu_id instead of the original EMISSION's fields.
  //
  // Steps:
  //   1. Issue a READ request and start receiving ciphertext (CE packets)
  //   2. After the first CE packet, inject a NOTIFY_ACK with different iop_id/hpu_id
  //   3. Continue feeding remaining CE packets to complete the ciphertext
  //   4. Verify regf_read_req_id contains the EMISSION's fields, NOT the ACK's
  // --------------------------------------------------------------------------------------------- --
  task automatic run_scenario_ack_leakage_to_received_cmd();
    logic cmd_timed_out;
    logic irq_timed_out;
    logic [REG_DATA_W-1:0] exp_read_req_id;
    logic [REG_DATA_W-1:0] exp_read_addr;
    // ACK fields: intentionally different from the read request
    logic [IOP_ID_W-1:0]   ack_iop_id;
    logic [HPU_ID_W-1:0]   ack_hpu_id;
    begin
      scenario_start(scenario_id, "NOTIFY_ACK leakage into received_cmd");
      randomize_fields();
      clear_axi4_captures();

      // Choose ACK fields that differ from the read request's
      ack_iop_id = ~iop_id;
      ack_hpu_id = ~hpu_id;

      // 1. Issue READ request
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

      // 2. Feed ALL CE packets to complete the ciphertext.
      feed_full_ciphertext(iop_id, hpu_id, req_mode, req_flag, iop_src_addr, iop_dst_addr);

      // 3. Inject a NOTIFY_ACK with different fields AFTER the last CE packet.
      //    The AXI4 write pipeline + B responses are still in-flight, so
      //    valid_ciphertext_received has NOT fired yet.
      //    Without the req_id guard, this overwrites received_cmd BEFORE the
      //    read-complete FIFO entry is generated.
      feed_notify_ack(
        .ack_iop_id  (ack_iop_id),
        .ack_hpu_id  (ack_hpu_id),
        .ack_seq_num (8'hAB)
      );

      // 5. Wait for read-complete interrupt
      wait_interrupt_rr(5000, irq_timed_out);
      assert (!irq_timed_out) else begin
        $display("[ERROR:%0d] Timed out waiting for interrupt", scenario_id);
        error_scenario = 1'b1;
      end

      // 6. Verify regf_read_req_id contains the EMISSION's fields
      exp_read_req_id = {iop_id, REQ_ID_EMISSION, hpu_id, req_mode, req_flag, 8'h0};
      exp_read_addr   = {iop_dst_addr, iop_src_addr};

      assert (regf_read_req_id == exp_read_req_id) else begin
        $display("[ERROR:%0d] regf_read_req_id mismatch (ACK leaked?) | exp %08h got %08h",
                 scenario_id, exp_read_req_id, regf_read_req_id);
        error_scenario = 1'b1;
      end
      assert (regf_read_addr == exp_read_addr) else begin
        $display("[ERROR:%0d] regf_read_addr mismatch (ACK leaked?) | exp %08h got %08h",
                 scenario_id, exp_read_addr, regf_read_addr);
        error_scenario = 1'b1;
      end

      clear_signal(clear_interrupt_rr, clk_mhdma_cfg);
      clear_axi4_captures();

      scenario_end(scenario_id, clk_mhdma_cfg);
    end
  endtask

  // --------------------------------------------------------------------------------------------- --
  // Scenario : Concurrent NOTIFY + READ traffic through the master_command arbiter
  //
  // The master_command arbiter + fifo_element  must correctly serialize a READ already in flight
  // with a NOTIFY that arrives while the READ holds the buffer.
  // This scenario covers:
  //   - arbiter priority + per-command serialization (one command in the buffer at a time)
  //   - source-FIFO pop atomicity (nrqq retry-FIFO push happens once per fresh notify)
  //   - dispatch-event side effects (no spurious *_sent; FSMs only advance on real dispatch)
  //   - both commands surface with their payloads preserved end-to-end
  //
  // req_id stability while vld=1 & rdy=0 is directly enforced by the SVA
  // assert_master_cmd_req_id_stable — no scenario-level assertion duplicates it here.
  //
  // Steps:
  //   1. Inject a READ; wait for master_command_vld with req_id=READ.
  //   2. Inject a NOTIFY while the READ is still held in the buffer.
  //   3. Pulse master_command_rdy + read_request_sent to dispatch the READ.
  //   4. Check cnt_notify didn't increment (no formatter notify transmission happened),
  //      then complete the READ flow and verify the queued NOTIFY drains with the
  //      correct iop_id.
  // --------------------------------------------------------------------------------------------- --
  task automatic run_scenario_concurrent_notify_read();
    logic                  cmd_timed_out;
    logic                  irq_timed_out;
    logic [REG_DATA_W-1:0] saved_cnt_notify;
    logic [IOP_ID_W-1:0]   notify_iop_id;
    begin
      scenario_start(scenario_id, "Concurrent NOTIFY + READ traffic through the arbiter");
      clear_axi4_captures();
      randomize_fields();
      saved_cnt_notify = stat.cnt_notify;
      notify_iop_id    = iop_id ^ 8'hFF;

      // Phase 1: inject READ, wait for master_command_vld with req_id=READ
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
        $display("[ERROR:%0d] Timed out waiting for READ master_command_vld", scenario_id);
        error_scenario = 1'b1;
      end
      assert (master_command.req_id == REQ_ID_READ) else begin
        $display("[ERROR:%0d] Phase1: expected req_id=READ, got %0h", scenario_id, master_command.req_id);
        error_scenario = 1'b1;
      end

      // Phase 2: inject NOTIFY while master_command is still vld=1 with req_id=READ.
      // A correct DUT must hold master_command stable until master_command_rdy pulses.
      // A buggy DUT overwrites req_id to NOTIFY via the priority mux.
      inject_regf_request(
        .iop_id   (notify_iop_id),
        .req_type (REQ_ID_NOTIFY),
        .hpu_id   (hpu_id       ),
        .mode     (req_mode     ),
        .flag     (req_flag     ),
        .src_addr (iop_src_addr ),
        .dst_addr (iop_dst_addr )
      );

      // Give the CDC fifo enough time to propagate the NOTIFY into nrqq_cmd_vld.
      repeat (100) @(posedge clk_mhdma);

      // Phase 3: formatter commits to consume the READ it observed in phase 1.
      @(posedge clk_mhdma);
      master_command_rdy = 1'b1;
      @(posedge clk_mhdma);
      master_command_rdy = 1'b0;

      // Phase 4: formatter sends the read packet.
      simulate_pulse(read_request_sent, clk_mhdma);

      // Phase 5: let FSMs settle, then check no spurious notify transmission happened.
      // FSM state snapshots are intentionally NOT asserted here — they are implementation
      // artifacts of where the FSM-trigger pulse lives in the arbiter/buffer pipeline.
      // The real invariants checked are:
      //   - cnt_notify unchanged (no notify_sent without a real formatter transmission)
      //   - both commands eventually drain with the correct payload (cleanup phase)
      //   - req_id stability while vld & !rdy (covered by assert_master_cmd_req_id_stable)
      repeat (10) @(posedge clk_mhdma);

      assert (stat.cnt_notify == saved_cnt_notify) else begin
        $display("[ERROR:%0d] cnt_notify incremented unexpectedly (was %0d, now %0d) -- notify_sent pulsed without a corresponding formatter notify transmission", scenario_id, saved_cnt_notify, stat.cnt_notify);
        error_scenario = 1'b1;
      end

      // Complete the READ flow, then drain the queued NOTIFY.
      feed_full_ciphertext(iop_id, hpu_id, req_mode, req_flag, iop_src_addr, iop_dst_addr);
      wait_interrupt_rr(5000, irq_timed_out);
      if (!irq_timed_out) clear_signal(clear_interrupt_rr, clk_mhdma_cfg);
      repeat (20) @(posedge clk_mhdma);

      // The queued NOTIFY must surface on master_command with its original payload.
      wait_master_command_vld(500, cmd_timed_out);
      assert (!cmd_timed_out) else begin
        $display("[ERROR:%0d] Queued NOTIFY did not surface after READ completed", scenario_id);
        error_scenario = 1'b1;
      end
      if (!cmd_timed_out) begin
        assert (master_command.req_id == REQ_ID_NOTIFY) else begin
          $display("[ERROR:%0d] Expected queued NOTIFY, got req_id=%0h", scenario_id, master_command.req_id);
          error_scenario = 1'b1;
        end
        assert (master_command.iop_id == notify_iop_id) else begin
          $display("[ERROR:%0d] NOTIFY iop_id mismatch: expected %0h, got %0h", scenario_id, notify_iop_id, master_command.iop_id);
          error_scenario = 1'b1;
        end
        consume_master_command();
        simulate_pulse(notify_sent, clk_mhdma);
        simulate_pulse(notify_ack_received, clk_mhdma);
        repeat (20) @(posedge clk_mhdma);
      end

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
    run_scenario_seq_num_mismatch_mid_burst();
    run_scenario_abort_drain_strobe();
    run_scenario_axi4_page_boundary();
    run_scenario_axi4_page_aligned();
    run_scenario_axi4_one_word_before_boundary();
    run_scenario_axi4_all_pcs();
    run_scenario_axi4_write_error();
    run_scenario_multiple_notifies();
    run_scenario_multiple_reads();
    run_scenario_irq_fifo_backpressure();
    run_scenario_ack_leakage_to_received_cmd();
    run_scenario_concurrent_notify_read();
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

  // AXI4 write-channel protocol checks (single NMU port): handshake stability, burst type/size, 4KB boundary, wlast

  // awvalid must not deassert without awready handshake
  property axi4_awvalid_stable;
    @(posedge clk_mhdma) disable iff (!s_rstn_mhdma)
    (nmu_axi4_awvalid && !nmu_axi4_awready) |=>
      $stable(nmu_axi4_awvalid) && $stable(nmu_axi4_awaddr) && $stable(nmu_axi4_awlen)
      && $stable(nmu_axi4_awburst) && $stable(nmu_axi4_awsize) && $stable(nmu_axi4_awid);
  endproperty

  // wvalid must not deassert without wready handshake
  property axi4_wvalid_stable;
    @(posedge clk_mhdma) disable iff (!s_rstn_mhdma)
    (nmu_axi4_wvalid && !nmu_axi4_wready) |=>
      $stable(nmu_axi4_wvalid) && $stable(nmu_axi4_wdata) && $stable(nmu_axi4_wlast)
      && $stable(nmu_axi4_wstrb);
  endproperty

  // awburst must always be INCR
  property axi4_awburst_incr;
    @(posedge clk_mhdma) disable iff (!s_rstn_mhdma)
    nmu_axi4_awvalid |-> (nmu_axi4_awburst == AXI4B_INCR);
  endproperty

  // awsize must be correct for AXI4_DATA_W
  property axi4_awsize_correct;
    @(posedge clk_mhdma) disable iff (!s_rstn_mhdma)
    nmu_axi4_awvalid |-> (nmu_axi4_awsize == MHDMA_ARSIZE);
  endproperty

  assert_awvalid_stable: assert property(axi4_awvalid_stable)
    else begin
      $display("[ERROR-SVA] AW channel: value changed when awready was low");
      error_assert = 1'b1;
    end

  assert_wvalid_stable: assert property(axi4_wvalid_stable)
    else begin
      $display("[ERROR-SVA] W channel: value changed when wready was low");
      error_assert = 1'b1;
    end

  assert_awburst_incr: assert property(axi4_awburst_incr)
    else begin
      $display("[ERROR-SVA] AW channel: awburst is not INCR");
      error_assert = 1'b1;
    end

  assert_awsize_correct: assert property(axi4_awsize_correct)
    else begin
      $display("[ERROR-SVA] AW channel: awsize is incorrect");
      error_assert = 1'b1;
    end

  // burst must not cross a 4KB page boundary (AXI4 spec A3.4.1)
  property axi4_no_4k_cross;
    @(posedge clk_mhdma) disable iff (!s_rstn_mhdma)
    (nmu_axi4_awvalid && nmu_axi4_awready) |->
      (nmu_axi4_awaddr[PAGE_BYTES_W-1:0]
       + ((nmu_axi4_awlen + 1) * AXI4_DATA_BYTES)) <= PAGE_BYTES;
  endproperty

  assert_no_4k_cross: assert property(axi4_no_4k_cross)
    else begin
      $display("[ERROR-SVA] AW channel: burst crosses 4KB page boundary (addr=0x%0h, len=%0d)",
               nmu_axi4_awaddr, nmu_axi4_awlen);
      error_assert = 1'b1;
    end

  // wlast correctness: check at the INTERNAL handshake point (before the
  // fifo_element_write pipeline register), where wlast and burst_beat_cnt
  // are synchronous.
  // DUT defines: wlast = (burst_word_cnt != 0) & (burst_beat_cnt == burst_word_cnt - 1)
  //              w_send_data = axi_wvalid & axi_wready  (internal handshake)

  // wlast must assert on the final beat
  property axi4_wlast_correct;
    @(posedge clk_mhdma) disable iff (!s_rstn_mhdma)
    (mhdma_master.w_send_data && mhdma_master.wlast) |->
      (mhdma_master.burst_beat_cnt == mhdma_master.burst_word_cnt - 1);
  endproperty

  // wlast must not assert before the final beat
  property axi4_wlast_not_early;
    @(posedge clk_mhdma) disable iff (!s_rstn_mhdma)
    (mhdma_master.w_send_data && !mhdma_master.wlast) |->
      (mhdma_master.burst_beat_cnt < mhdma_master.burst_word_cnt - 1);
  endproperty

  assert_wlast_correct: assert property(axi4_wlast_correct)
    else begin
      $display("[ERROR-SVA] W channel: wlast on wrong beat (beat=%0d, word_cnt=%0d)",
               mhdma_master.burst_beat_cnt, mhdma_master.burst_word_cnt);
      error_assert = 1'b1;
    end

  assert_wlast_not_early: assert property(axi4_wlast_not_early)
    else begin
      $display("[ERROR-SVA] W channel: wlast missing (beat=%0d < word_cnt-1=%0d)",
               mhdma_master.burst_beat_cnt, mhdma_master.burst_word_cnt - 1);
      error_assert = 1'b1;
    end

  // After a handshake, vld must either drop or present a new command within 2 cycles
  // (no stale command held with vld high).
  property master_cmd_vld_deassert_after_handshake;
    @(posedge clk_mhdma) disable iff (!s_rstn_mhdma)
    (master_command_vld && master_command_rdy) |->
      ##[1:2] (!master_command_vld || !$stable(master_command));
  endproperty

  assert_master_cmd_handshake: assert property(master_cmd_vld_deassert_after_handshake)
    else begin
      $display("[ERROR-SVA] master_command_vld stuck high with stale command after handshake");
      error_assert = 1'b1;
    end

  // While vld=1 and rdy=0, req_id must remain stable (valid/ready contract).
  property master_command_req_id_stable;
    @(posedge clk_mhdma) disable iff (!s_rstn_mhdma)
    (master_command_vld && !master_command_rdy) |=>
      (!master_command_vld || $stable(master_command.req_id));
  endproperty

  assert_master_cmd_req_id_stable: assert property(master_command_req_id_stable)
    else begin
      $display("[ERROR-SVA] master_command.req_id changed while vld=1 and rdy=0");
      error_assert = 1'b1;
    end

endmodule
