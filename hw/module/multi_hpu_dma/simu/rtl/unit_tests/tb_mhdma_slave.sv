// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Unit testbench for mhdma_slave
// ----------------------------------------------------------------------------------------------
//
// Payload on ciphertext emission is checked in testbench multi_hpu_dma.
//
// Assumptions:
//   - ETH_PC >= 2 in scenario 4/7 (with conditional "if (ETH_PC > 1)")
//   - AXI4_DATA_W is a multiple of MRMAC_AXIS_W
//   - AXI4 responder generates read data with configurable latency (AXI4_MEM_RD_DATA_LATENCY = 256)
//
// Not covered by this testbench:
//   - CE payload data integrity (see tb_multi_hpu_dma)
//
// Scenarios exercised:
//   > Notify RX flow
//   > Notify RX backpressure
//   > Ciphertext Emission flow
//   > CEM backpressure (slave_command_rdy deasserted)
//   > decoded_command_rdy arbitration
//   > Multiple sequential read requests
//   > Statistics counters and reset
//   > Interleaved Notify and Read requests
//   > NOTIFY during CEM_READ_N_SEND
//   > READ during NRX_TRANSMIT_ACK
//   > Back-to-back commands (0-gap stress)
//   > Physical address correctness + page boundary on all PCs
//
// ==============================================================================================

`resetall
`timescale 1ns/10ps
module tb_mhdma_slave;
  import mhdma_pkg::*;
  import axi_if_shell_axil_pkg::*;
  import axi_if_common_param_pkg::*;
  import axi_if_mhdma_axi_pkg::*;
  import pem_common_param_pkg::*;

  `include "tb_mhdma_tasks.sv"

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int CLK_HALF_PERIOD_CFG   = 4;
  localparam int CLK_HALF_PERIOD_MRMAC = 1;
  localparam int ARST_ACTIVATION       = 17;
  localparam int CDC_SYNC_STAGES       = 2;

  localparam int TIMEOUT_CYCLES        = 50_000;

  // axi4_mem parameters for AXI4 read responder
  // RD_CMD_BUF_DEPTH: how many AR commands can be buffered before backpressuring arready
  localparam int AXI4_MEM_RD_CMD_BUF_DEPTH = 1;
  // RD_DATA_LATENCY: number of pipeline stages between RAM read and rvalid (models HBM latency)
  localparam int AXI4_MEM_RD_DATA_LATENCY  = 256;
  // USE_RD_RANDOM: enables random toggling of arready/rvalid for backpressure coverage
  localparam bit AXI4_MEM_USE_RD_RANDOM    = 1;

  // CE drain wait: must account for AXI pipeline latency (per-PC) + serialization + backpressure margin
  // - CT_NB_WORDS_MRMAC: total narrow words to serialize (scales with CT, not AXI width)
  // - ETH_PC * AXI4_MEM_RD_DATA_LATENCY: pipeline fill latency, paid once per PC
  // - CT_NB_WORDS_AXI4: extra margin covering AXI beat count (scales inversely with AXI width)
  localparam int CE_DRAIN_WAIT_CYCLES = CT_NB_WORDS_MRMAC
                                      + ETH_PC * AXI4_MEM_RD_DATA_LATENCY
                                      + CT_NB_WORDS_AXI4;

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
    #CLK_HALF_PERIOD_CFG clk_mhdma_cfg = ~clk_mhdma_cfg;
  end

  always begin
    #CLK_HALF_PERIOD_MRMAC clk_mhdma = ~clk_mhdma;
  end

  bit a_rst_n;
  bit s_rstn_cfg;
  bit s_rstn_mhdma;

  initial begin
    a_rst_n = 1'b0;
    #ARST_ACTIVATION a_rst_n = 1'b1;
  end

  always_ff @(posedge clk_mhdma_cfg)
    s_rstn_cfg <= a_rst_n;

  always_ff @(posedge clk_mhdma)
    s_rstn_mhdma <= a_rst_n;

// ============================================================================================== --
// End of test
// ============================================================================================== --
  bit end_of_test;
  bit error;
  bit error_assert;
  bit error_timeout;

  assign error = error_assert | error_timeout;

  initial begin
    wait (end_of_test);
    @(posedge clk_mhdma_cfg) $display("%t > SUCCEED !", $time);
    $finish;
  end

  always_ff @(posedge clk_mhdma_cfg)
    if (error) begin
      $display("%t > FAILURE !", $time);
      $finish;
    end

// ============================================================================================== --
// DUT signals
// ============================================================================================== --
  // Single AXI4 Read interface (from DUT)
  logic [  AXI4_ADD_W-1:0]                               m_axi4_araddr;
  logic [  AXI4_LEN_W-1:0]                               m_axi4_arlen;
  logic [ AXI4_SIZE_W-1:0]                               m_axi4_arsize;
  logic [AXI4_BURST_W-1:0]                               m_axi4_arburst;
  logic                                                  m_axi4_arvalid;
  logic                                                  m_axi4_arready;
  logic [axi_if_mhdma_axi_pkg::AXI4_ID_W-1:0]            m_axi4_arid;

  logic [AXI4_DATA_W-1:0]                                m_axi4_rdata;
  logic [AXI4_RESP_W-1:0]                                m_axi4_rresp;
  logic [axi_if_mhdma_axi_pkg::AXI4_ID_W-1:0]            m_axi4_rid;
  logic                                                  m_axi4_rlast;
  logic                                                  m_axi4_rvalid;
  logic                                                  m_axi4_rready;

  // PC selectors from DUT
  logic [ETH_PC-1:0] ar_pc_sel;
  logic [ETH_PC-1:0] rd_pc_sel;

  // Per-PC AXI4 signals (for AXI memory models)
  logic [ETH_PC-1:0][  AXI4_ADD_W-1:0]                  nmu_axi4_araddr;
  logic [ETH_PC-1:0][  AXI4_LEN_W-1:0]                  nmu_axi4_arlen;
  logic [ETH_PC-1:0][ AXI4_SIZE_W-1:0]                  nmu_axi4_arsize;
  logic [ETH_PC-1:0][AXI4_BURST_W-1:0]                  nmu_axi4_arburst;
  logic [ETH_PC-1:0]                                    nmu_axi4_arvalid;
  logic [ETH_PC-1:0]                                    nmu_axi4_arready;
  logic [ETH_PC-1:0][axi_if_mhdma_axi_pkg::AXI4_ID_W-1:0] nmu_axi4_arid;

  logic [ETH_PC-1:0][AXI4_DATA_W-1:0]                   nmu_axi4_rdata;
  logic [ETH_PC-1:0][AXI4_RESP_W-1:0]                   nmu_axi4_rresp;
  logic [ETH_PC-1:0][axi_if_mhdma_axi_pkg::AXI4_ID_W-1:0] nmu_axi4_rid;
  logic [ETH_PC-1:0]                                    nmu_axi4_rlast;
  logic [ETH_PC-1:0]                                    nmu_axi4_rvalid;
  logic [ETH_PC-1:0]                                    nmu_axi4_rready;

  // Register file interface
  logic [ETH_PC-1:0][2*REG_DATA_W-1:0] regf_ct_mem_addr;
  logic             [  REG_DATA_W-1:0] regf_notify_req_id;
  logic             [  REG_DATA_W-1:0] regf_notify_req_addr;

  // Interrupt
  logic clear_interrupt_notify;
  logic interrupt_notify;

  // Decoder interface
  command_t decoded_command;
  logic     decoded_command_vld;
  logic     decoded_command_rdy;

  // Formatter interface
  command_t slave_command;
  logic     slave_command_vld;
  logic     slave_command_rdy;

  logic [MRMAC_AXIS_W-1:0] ce_payload;
  logic                     ce_vld;
  logic                     ce_rdy;

  logic ciphertext_sent;
  logic notify_ack_sent;

  // Error
  slave_error_t  slave_error;
  logic          rst_errors;

  // Statistics
  slave_stat_t     stat;
  slave_stat_rst_t stat_rst;

// ============================================================================================== --
// DUT
// ============================================================================================== --
  mhdma_slave #(
    .CDC_SYNC_STAGES(CDC_SYNC_STAGES)
  ) mhdma_slave (
    .clk_mhdma_cfg                (clk_mhdma_cfg               ),
    .resetn_mhdma_cfg             (s_rstn_cfg            ),
    .clk_mhdma              (clk_mhdma             ),
    .resetn_mhdma           (s_rstn_mhdma          ),

    .m_axi4_araddr          (m_axi4_araddr         ),
    .m_axi4_arlen           (m_axi4_arlen          ),
    .m_axi4_arsize          (m_axi4_arsize         ),
    .m_axi4_arburst         (m_axi4_arburst        ),
    .m_axi4_arvalid         (m_axi4_arvalid        ),
    .m_axi4_arready         (m_axi4_arready        ),
    .m_axi4_arid            (m_axi4_arid           ),

    .m_axi4_rdata           (m_axi4_rdata          ),
    .m_axi4_rresp           (m_axi4_rresp          ),
    .m_axi4_rid             (m_axi4_rid            ),
    .m_axi4_rlast           (m_axi4_rlast          ),
    .m_axi4_rvalid          (m_axi4_rvalid         ),
    .m_axi4_rready          (m_axi4_rready         ),
    .ar_pc_sel              (ar_pc_sel             ),
    .rd_pc_sel              (rd_pc_sel             ),

    .regf_ct_mem_addr       (regf_ct_mem_addr      ),
    .regf_notify_req_id     (regf_notify_req_id    ),
    .regf_notify_req_addr   (regf_notify_req_addr  ),

    .clear_interrupt_notify (clear_interrupt_notify),
    .interrupt_notify       (interrupt_notify      ),

    .decoded_command        (decoded_command       ),
    .decoded_command_vld    (decoded_command_vld   ),
    .decoded_command_rdy    (decoded_command_rdy   ),

    .slave_command          (slave_command         ),
    .slave_command_vld      (slave_command_vld     ),
    .slave_command_rdy      (slave_command_rdy     ),

    .ce_payload             (ce_payload            ),
    .ce_vld                 (ce_vld                ),
    .ce_rdy                 (ce_rdy                ),

    .ciphertext_sent        (ciphertext_sent       ),
    .notify_ack_sent        (notify_ack_sent       ),

    .slave_error            (slave_error           ),
    .rst_errors             (rst_errors            ),

    .stat                   (stat                  ),
    .stat_rst               (stat_rst              )
  );

// ============================================================================================== --
// NMU demux: single AXI4 from DUT -> per-PC AXI memory models
// ============================================================================================== --
  mhdma_nmu_demux mhdma_nmu_demux (
    .clk            (clk_mhdma      ),
    .s_rst_n        (s_rstn_mhdma   ),
    .s_axi4_arid    (m_axi4_arid    ),
    .s_axi4_araddr  (m_axi4_araddr  ),
    .s_axi4_arlen   (m_axi4_arlen   ),
    .s_axi4_arsize  (m_axi4_arsize  ),
    .s_axi4_arburst (m_axi4_arburst ),
    .s_axi4_arvalid (m_axi4_arvalid ),
    .s_axi4_arready (m_axi4_arready ),
    .s_axi4_rdata   (m_axi4_rdata   ),
    .s_axi4_rresp   (m_axi4_rresp   ),
    .s_axi4_rid     (m_axi4_rid     ),
    .s_axi4_rlast   (m_axi4_rlast   ),
    .s_axi4_rvalid  (m_axi4_rvalid  ),
    .s_axi4_rready  (m_axi4_rready  ),
    .ar_pc_sel      (ar_pc_sel      ),
    .rd_pc_sel      (rd_pc_sel      ),
    // AW/W unused in slave TB
    .s_axi4_awid    ('0             ),
    .s_axi4_awaddr  ('0             ),
    .s_axi4_awlen   ('0             ),
    .s_axi4_awsize  ('0             ),
    .s_axi4_awburst ('0             ),
    .s_axi4_awvalid (1'b0           ),
    .s_axi4_awready (               ),
    .s_axi4_wdata   ('0             ),
    .s_axi4_wstrb   ('0             ),
    .s_axi4_wlast   (1'b0           ),
    .s_axi4_wvalid  (1'b0           ),
    .s_axi4_wready  (               ),
    .wr_pc_sel      ('0             ),
    // Per-PC NMU ports
    .m_axi4_arid    (nmu_axi4_arid    ),
    .m_axi4_araddr  (nmu_axi4_araddr  ),
    .m_axi4_arlen   (nmu_axi4_arlen   ),
    .m_axi4_arsize  (nmu_axi4_arsize  ),
    .m_axi4_arburst (nmu_axi4_arburst ),
    .m_axi4_arvalid (nmu_axi4_arvalid ),
    .m_axi4_arready (nmu_axi4_arready ),
    .m_axi4_rdata   (nmu_axi4_rdata   ),
    .m_axi4_rresp   (nmu_axi4_rresp   ),
    .m_axi4_rid     (nmu_axi4_rid     ),
    .m_axi4_rlast   (nmu_axi4_rlast   ),
    .m_axi4_rvalid  (nmu_axi4_rvalid  ),
    .m_axi4_rready  (nmu_axi4_rready  ),
    .m_axi4_awid    (                 ),
    .m_axi4_awaddr  (                 ),
    .m_axi4_awlen   (                 ),
    .m_axi4_awsize  (                 ),
    .m_axi4_awburst (                 ),
    .m_axi4_awvalid (                 ),
    .m_axi4_awready ('0               ),
    .m_axi4_wdata   (                 ),
    .m_axi4_wstrb   (                 ),
    .m_axi4_wlast   (                 ),
    .m_axi4_wvalid  (                 ),
    .m_axi4_wready  ('0               )
  );

// ============================================================================================== --
// AXI4 Read Responder (per PC)
// ============================================================================================== --
  int ar_transaction_count [ETH_PC];

  generate
    for (genvar gen_pc = 0; gen_pc < ETH_PC; gen_pc++) begin : gen_axi4_responder
      axi4_mem #(
        .DATA_WIDTH      (AXI4_DATA_W),
        .ADDR_WIDTH      (AXI4_ADD_W),
        .ID_WIDTH        (axi_if_mhdma_axi_pkg::AXI4_ID_W),
        .STRB_WIDTH      (AXI4_DATA_W/8),
        .RD_CMD_BUF_DEPTH(AXI4_MEM_RD_CMD_BUF_DEPTH),
        .RD_DATA_LATENCY (AXI4_MEM_RD_DATA_LATENCY),
        .WR_CMD_BUF_DEPTH(1),  // minimum, write channel unused
        .WR_DATA_LATENCY (1),  // minimum, write channel unused
        .USE_RD_RANDOM   (AXI4_MEM_USE_RD_RANDOM),
        .USE_WR_RANDOM   (0)   // write channel unused
      ) u_axi4_mem (
        .clk              (clk_mhdma),
        .rst              (~s_rstn_mhdma),
        // Write channel - tied off (DUT is read-only, no AW/W/B)
        .s_axi4_awid      ({axi_if_mhdma_axi_pkg::AXI4_ID_W{1'b0}}),
        .s_axi4_awaddr    ({AXI4_ADD_W{1'b0}}),
        .s_axi4_awlen     (8'h0),
        .s_axi4_awsize    (3'h0),
        .s_axi4_awburst   (2'h0),
        .s_axi4_awlock    (1'b0),
        .s_axi4_awcache   (4'h0),
        .s_axi4_awprot    (3'h0),
        .s_axi4_awqos     (4'h0),
        .s_axi4_awregion  (4'h0),
        .s_axi4_awvalid   (1'b0),
        .s_axi4_awready   (/* UNUSED */),
        .s_axi4_wdata     ({AXI4_DATA_W{1'b0}}),
        .s_axi4_wstrb     ({(AXI4_DATA_W/8){1'b0}}),
        .s_axi4_wlast     (1'b0),
        .s_axi4_wvalid    (1'b0),
        .s_axi4_wready    (/* UNUSED */),
        .s_axi4_bid       (/* UNUSED */),
        .s_axi4_bresp     (/* UNUSED */),
        .s_axi4_bvalid    (/* UNUSED */),
        .s_axi4_bready    (1'b0),
        // Read channel - connected to DUT master interface
        .s_axi4_arid      (nmu_axi4_arid[gen_pc]),
        .s_axi4_araddr    (nmu_axi4_araddr[gen_pc]),
        .s_axi4_arlen     (nmu_axi4_arlen[gen_pc]),
        .s_axi4_arsize    (nmu_axi4_arsize[gen_pc]),
        .s_axi4_arburst   (nmu_axi4_arburst[gen_pc]),
        .s_axi4_arlock    (1'b0),
        .s_axi4_arcache   (4'h0),
        .s_axi4_arprot    (3'h0),
        .s_axi4_arqos     (4'h0),
        .s_axi4_arregion  (4'h0),
        .s_axi4_arvalid   (nmu_axi4_arvalid[gen_pc]),
        .s_axi4_arready   (nmu_axi4_arready[gen_pc]),
        .s_axi4_rid       (nmu_axi4_rid[gen_pc]),
        .s_axi4_rdata     (nmu_axi4_rdata[gen_pc]),
        .s_axi4_rresp     (nmu_axi4_rresp[gen_pc]),
        .s_axi4_rlast     (nmu_axi4_rlast[gen_pc]),
        .s_axi4_rvalid    (nmu_axi4_rvalid[gen_pc]),
        .s_axi4_rready    (nmu_axi4_rready[gen_pc])
      );
    end
  endgenerate

  // Track AR transactions per PC
  generate
    for (genvar gen_pc = 0; gen_pc < ETH_PC; gen_pc++) begin : gen_ar_tracker
      always_ff @(posedge clk_mhdma) begin
        if (~s_rstn_mhdma)
          ar_transaction_count[gen_pc] <= 0;
        else if (nmu_axi4_arvalid[gen_pc] && nmu_axi4_arready[gen_pc])
          ar_transaction_count[gen_pc] <= ar_transaction_count[gen_pc] + 1;
      end
    end
  endgenerate

// ============================================================================================== --
// Helper tasks
// ============================================================================================== --

  task automatic tb_init();
    begin
      decoded_command     = '0;
      decoded_command_vld = 1'b0;

      slave_command_rdy   = 1'b0;

      ciphertext_sent     = 1'b0;
      notify_ack_sent     = 1'b0;

      clear_interrupt_notify = 1'b0;

      rst_errors          = 1'b0;
      stat_rst            = '0;

      for (int pc = 0; pc < ETH_PC; pc++) begin
        regf_ct_mem_addr[pc] = 64'h0000_0000_0001_0000 + pc * 64'h0000_0000_0010_0000;
      end

      end_of_test    = 1'b0;
      error_assert   = 1'b0;
      error_timeout  = 1'b0;
    end
  endtask

  always_ff @(posedge clk_mhdma) begin
    ce_rdy <= $urandom();
  end

  task automatic send_decoded_command(
    input logic [REQ_ID_W-1:0]    req_id,
    input logic [HPU_ID_W-1:0]    hpu_id,
    input logic [IOP_ID_W-1:0]    iop_id,
    input logic [SRC_ADDR_W-1:0]  src_addr,
    input logic [DST_ADDR_W-1:0]  dst_addr,
    input logic [FLAG_W-1:0]      flag,
    input logic [MODE_W-1:0]      mode,
    input logic [SEQ_NUM_W-1:0]   seq_num
  );
    begin
      @(posedge clk_mhdma);
      decoded_command.req_id       <= req_id;
      decoded_command.hpu_id       <= hpu_id;
      decoded_command.iop_id       <= iop_id;
      decoded_command.src_addr     <= src_addr;
      decoded_command.dst_addr     <= dst_addr;
      decoded_command.rsvd         <= '0;
      decoded_command.flag         <= flag;
      decoded_command.mode         <= mode;
      decoded_command.src_mac_addr <= 24'hABCDEF;
      decoded_command.seq_num      <= seq_num;
      decoded_command_vld          <= 1'b1;

      do @(posedge clk_mhdma); while (~decoded_command_rdy);
      @(posedge clk_mhdma);
      decoded_command_vld <= 1'b0;
    end
  endtask

  task automatic wait_slave_command_vld(
    input  int   max_cycles,
    output logic timed_out
  );
    int count;
    begin
      timed_out = 1'b0;
      count = 0;
      while (~slave_command_vld & count < max_cycles) begin
        @(posedge clk_mhdma);
        count++;
      end
      if (count >= max_cycles) timed_out = 1'b1;
    end
  endtask

  task automatic wait_ce_vld(
    input  int   max_cycles,
    output logic timed_out
  );
    int count;
    begin
      timed_out = 1'b0;
      count = 0;
      while (!ce_vld & count < max_cycles) begin
        @(posedge clk_mhdma);
        count++;
      end

      if (count >= max_cycles)
        timed_out = 1'b1;

    end
  endtask

  task automatic wait_interrupt_notify(
    input  int   max_cycles,
    output logic timed_out
  );
    int count;
    begin
      timed_out = 1'b0;
      count = 0;
      while (~interrupt_notify & (count < max_cycles)) begin
        @(posedge clk_mhdma_cfg);
        count++;
      end
      if (count >= max_cycles)
        timed_out = 1'b1;
    end
  endtask

  // --------------------------------------------------------------------------------------------- --
  // Consume slave command: pulse slave_command_rdy for one clock cycle (mrmac domain)
  // --------------------------------------------------------------------------------------------- --
  task automatic consume_slave_command();
    begin
      @(posedge clk_mhdma);
      slave_command_rdy <= 1'b1;
      @(posedge clk_mhdma);
      slave_command_rdy <= 1'b0;
    end
  endtask

  // Complete a full CEM read flow: wait for slave_command, consume it, wait for CE data, send ciphertext_sent
  task automatic complete_cem_flow(
    input  int   timeout,
    output logic timed_out
  );
    begin
      wait_slave_command_vld(timeout, timed_out);
      if (timed_out) return;

      consume_slave_command();

      wait_ce_vld(timeout, timed_out);
      if (timed_out) return;

      // Consume all CE words by counting actual handshakes (not cycles)
      begin
        int ce_count;
        int cycle_count;

        ce_count = 0;
        cycle_count = 0;

        while ((ce_count < CT_NB_WORDS_MRMAC) & (cycle_count < timeout)) begin
          @(posedge clk_mhdma);
          if (ce_vld & ce_rdy) ce_count++;
          cycle_count++;
        end

        if (cycle_count >= timeout) begin
          timed_out = 1'b1;
          return;
        end
      end

      simulate_pulse(ciphertext_sent, clk_mhdma);
      repeat (50) @(posedge clk_mhdma);
    end
  endtask

// ============================================================================================== --
// Scenario checker helpers
// ============================================================================================== --

  task automatic check_no_timeout(
    input logic  timed_out,
    input int    sid,
    input string msg
  );
    assert (~timed_out) else begin
      $display("[ERROR:%0d] %s", sid, msg);
      error_assert  = 1'b1;
      error_timeout = 1'b1;
    end
  endtask

  task automatic check_fsm_idle(input int sid);
    assert (stat.fsm_notify_rx == 2'b00) else begin
      $display("[ERROR:%0d] NRX FSM not idle", sid);
      error_assert = 1'b1;
    end
    assert (stat.fsm_cem == 2'b00) else begin
      $display("[ERROR:%0d] CEM FSM not idle", sid);
      error_assert = 1'b1;
    end
  endtask

// ============================================================================================== --
// Scenario tasks
// ============================================================================================== --
  int scenario_id;
  logic timed_out;

  logic [IOP_ID_W-1:0]   iop_id;
  logic [SRC_ADDR_W-1:0] iop_src_addr;
  logic [DST_ADDR_W-1:0] iop_dst_addr;
  logic [FLAG_W-1:0]     req_flag;
  logic [MODE_W-1:0]     req_mode;
  logic [HPU_ID_W-1:0]   hpu_id;

  // -------------------------------------------------------------------------
  // Scenario : Notify RX basic flow
  // -------------------------------------------------------------------------
  task automatic run_scenario_notify_rx_flow();
    scenario_start(scenario_id, "Notify RX basic flow");
    randomize_command_fields($urandom(), hpu_id, iop_id, iop_src_addr, iop_dst_addr, req_flag, req_mode);

    send_decoded_command(REQ_ID_NOTIFY, hpu_id, iop_id, iop_src_addr, iop_dst_addr, req_flag, req_mode, '0);

    wait_slave_command_vld(500, timed_out);

    check_no_timeout(timed_out, scenario_id, "slave_command_vld timeout");
    assert (slave_command.req_id == REQ_ID_NOTIFY_ACK) else begin $display("[ERROR:%0d] req_id mismatch", scenario_id);   error_assert = 1'b1; end
    assert (slave_command.hpu_id == hpu_id)            else begin $display("[ERROR:%0d] hpu_id mismatch", scenario_id);   error_assert = 1'b1; end
    assert (slave_command.iop_id == iop_id)            else begin $display("[ERROR:%0d] iop_id mismatch", scenario_id);   error_assert = 1'b1; end
    assert (slave_command.src_addr == iop_src_addr)    else begin $display("[ERROR:%0d] src_addr mismatch", scenario_id); error_assert = 1'b1; end

    consume_slave_command();
    simulate_pulse(notify_ack_sent, clk_mhdma);

    wait_interrupt_notify(500, timed_out);

    check_no_timeout(timed_out, scenario_id, "interrupt_notify timeout");

    // Upper word = {iop_id, REQ_ID_NOTIFY, hpu_id, mode, flag, rsvd}
    assert (regf_notify_req_id[REG_DATA_W-1:REG_DATA_W-IOP_ID_W]                                     == iop_id)        else begin $display("[ERROR:%0d] regf iop_id mismatch", scenario_id); error_assert = 1'b1; end
    assert (regf_notify_req_id[REG_DATA_W-IOP_ID_W-1:REG_DATA_W-IOP_ID_W-REQ_ID_W]                   == REQ_ID_NOTIFY) else begin $display("[ERROR:%0d] regf req_id mismatch", scenario_id); error_assert = 1'b1; end
    assert (regf_notify_req_id[REG_DATA_W-IOP_ID_W-REQ_ID_W-1:REG_DATA_W-IOP_ID_W-REQ_ID_W-HPU_ID_W] == hpu_id)        else begin $display("[ERROR:%0d] regf hpu_id mismatch", scenario_id); error_assert = 1'b1; end

    // Lower word = {dst_addr, src_addr}
    assert (regf_notify_req_addr == {iop_dst_addr, iop_src_addr}) else begin
      $display("[ERROR:%0d] regf_notify_req_addr mismatch: got %0h", scenario_id, regf_notify_req_addr);
      error_assert = 1'b1;
    end

    clear_signal(clear_interrupt_notify, clk_mhdma_cfg);
    repeat (10) @(posedge clk_mhdma_cfg);
    assert (~interrupt_notify)           else begin $display("[ERROR:%0d] interrupt not cleared", scenario_id); error_assert = 1'b1; end
    assert (stat.fsm_notify_rx == 2'b00) else begin $display("[ERROR:%0d] NRX FSM not idle", scenario_id);     error_assert = 1'b1; end

    scenario_end(scenario_id, clk_mhdma_cfg);
  endtask

  // -------------------------------------------------------------------------
  // Scenario : Notify RX backpressure
  // -------------------------------------------------------------------------
  task automatic run_scenario_notify_rx_backpressure();
    scenario_start(scenario_id, "Notify RX backpressure");
    slave_command_rdy = 1'b0;

    // Fill NRX FIFO: send NRX_DEPTH-1 NOTIFYs, ack each to cycle FSM
    for (int i = 0; i < NRX_DEPTH - 1; i++) begin
      randomize_command_fields($urandom(), hpu_id, iop_id, iop_src_addr, iop_dst_addr, req_flag, req_mode);
      send_decoded_command(REQ_ID_NOTIFY, hpu_id, iop_id, iop_src_addr, iop_dst_addr, req_flag, req_mode, '0);
      simulate_pulse(notify_ack_sent, clk_mhdma);
      repeat (5) @(posedge clk_mhdma);
    end

    // Send one more to fill FIFO completely; keep FSM in TRANSMIT_ACK for drain
    randomize_command_fields($urandom(), hpu_id, iop_id, iop_src_addr, iop_dst_addr, req_flag, req_mode);
    send_decoded_command(REQ_ID_NOTIFY, hpu_id, iop_id, iop_src_addr, iop_dst_addr, req_flag, req_mode, '0);
    repeat (5) @(posedge clk_mhdma);

    // FIFO full + FSM in TRANSMIT_ACK -> decoded_command_rdy must stay 0
    @(posedge clk_mhdma);
    decoded_command.req_id <= REQ_ID_NOTIFY;
    decoded_command_vld    <= 1'b1;

    repeat (20) @(posedge clk_mhdma);

    assert (decoded_command_rdy == 1'b0) else begin
      $display("[ERROR:%0d] rdy should be 0 when FIFO full", scenario_id);
      error_assert = 1'b1;
    end

    decoded_command_vld <= 1'b0;

    // Recovery: enable drain (hold slave_command_rdy=1 for bulk FIFO drain)
    slave_command_rdy = 1'b1;
    repeat (200) @(posedge clk_mhdma);
    simulate_pulse(notify_ack_sent, clk_mhdma);
    repeat (50) @(posedge clk_mhdma);
    slave_command_rdy = 1'b0;

    // Drain pending interrupts
    repeat (NRX_DEPTH + 1) begin
      wait_interrupt_notify(200, timed_out);
      if (~timed_out) begin
        clear_signal(clear_interrupt_notify, clk_mhdma_cfg);
      end
      repeat (5) @(posedge clk_mhdma_cfg);
    end

    // Verify: recovery works - send one more NOTIFY successfully
    randomize_command_fields($urandom(), hpu_id, iop_id, iop_src_addr, iop_dst_addr, req_flag, req_mode);
    send_decoded_command(REQ_ID_NOTIFY, hpu_id, iop_id, iop_src_addr, iop_dst_addr, req_flag, req_mode, '0);

    wait_slave_command_vld(500, timed_out);

    check_no_timeout(timed_out, scenario_id, "recovery slave_command_vld timeout");

    consume_slave_command();

    simulate_pulse(notify_ack_sent, clk_mhdma);

    wait_interrupt_notify(500, timed_out);

    check_no_timeout(timed_out, scenario_id, "recovery NOTIFY interrupt timeout");

    if (~timed_out) begin
      clear_signal(clear_interrupt_notify, clk_mhdma_cfg);
    end

    repeat (10) @(posedge clk_mhdma_cfg);

    scenario_end(scenario_id, clk_mhdma_cfg);
  endtask

  // -------------------------------------------------------------------------
  // Scenario : Ciphertext Emission basic flow
  // -------------------------------------------------------------------------
  task automatic run_scenario_cem_flow();
    scenario_start(scenario_id, "Ciphertext Emission basic flow");
    randomize_command_fields($urandom(), hpu_id, iop_id, iop_src_addr, iop_dst_addr, req_flag, req_mode);

    send_decoded_command(REQ_ID_READ, hpu_id, iop_id, iop_src_addr, iop_dst_addr, req_flag, req_mode, 'h0);

    // slave_command_vld fires shortly after command acceptance (RREQ FIFO pop)
    wait_slave_command_vld(TIMEOUT_CYCLES, timed_out);
    check_no_timeout(timed_out, scenario_id, "slave_command_vld timeout");

    assert (slave_command.req_id   == REQ_ID_EMISSION) else begin $display("[ERROR:%0d] req_id mismatch", scenario_id);       error_assert = 1'b1; end
    assert (slave_command.hpu_id   == hpu_id)          else begin $display("[ERROR:%0d] hpu_id mismatch", scenario_id);       error_assert = 1'b1; end
    assert (slave_command.iop_id   == iop_id)          else begin $display("[ERROR:%0d] iop_id mismatch", scenario_id);       error_assert = 1'b1; end
    assert (slave_command.src_addr == iop_src_addr)    else begin $display("[ERROR:%0d] iop_src_addr mismatch", scenario_id); error_assert = 1'b1; end
    assert (slave_command.dst_addr == iop_dst_addr)    else begin $display("[ERROR:%0d] iop_dst_addr mismatch", scenario_id); error_assert = 1'b1; end
    assert (slave_command.flag     == req_flag)        else begin $display("[ERROR:%0d] req_flag mismatch", scenario_id);     error_assert = 1'b1; end
    assert (slave_command.mode     == req_mode)        else begin $display("[ERROR:%0d] req_mode mismatch", scenario_id);     error_assert = 1'b1; end

    consume_slave_command();

    // Wait for first AXI4 AR transaction on PC0
    begin : wait_ar_block
      int wait_count;
      wait_count = 0;
      while (~nmu_axi4_arvalid[0] & (wait_count < TIMEOUT_CYCLES)) begin
        @(posedge clk_mhdma);
        wait_count++;
      end
      assert (wait_count < TIMEOUT_CYCLES) else begin
        $display("[ERROR:%0d] AR timeout on PC0", scenario_id);
        error_timeout = 1'b1;
      end
    end

    wait_ce_vld(TIMEOUT_CYCLES, timed_out);
    check_no_timeout(timed_out, scenario_id, "ce_vld timeout");

    // Consume CE data by counting actual handshakes (not cycles)
    begin : drain_ce_cem_flow
      int ce_count;
      int cycle_count;
      ce_count = 0;
      cycle_count = 0;
      while ((ce_count < CT_NB_WORDS_MRMAC) & (cycle_count < TIMEOUT_CYCLES)) begin
        @(posedge clk_mhdma);
        if (ce_vld & ce_rdy) ce_count++;
        cycle_count++;
      end
      check_no_timeout(cycle_count >= TIMEOUT_CYCLES, scenario_id, "CE drain timeout");
    end

    simulate_pulse(ciphertext_sent, clk_mhdma);
    repeat (50) @(posedge clk_mhdma);
    assert (stat.fsm_cem == 2'b00) else begin
      $display("[ERROR:%0d] CEM FSM not idle", scenario_id);
      error_assert = 1'b1;
    end

    scenario_end(scenario_id, clk_mhdma_cfg);
  endtask


  // -------------------------------------------------------------------------
  // Scenario : decoded_command_rdy arbitration
  // -------------------------------------------------------------------------
  task automatic run_scenario_decoded_command_rdy_arbitration();
    scenario_start(scenario_id, "decoded_command_rdy arbitration");

    check_fsm_idle(scenario_id);

    // Both FSMs in WAIT, no vld -> registered decoded_command_rdy = 0
    assert (decoded_command_rdy == 1'b0) else begin
      $display("[ERROR:%0d] rdy should be 0 in idle", scenario_id);
      error_assert = 1'b1;
    end

    randomize_command_fields($urandom(), hpu_id, iop_id, iop_src_addr, iop_dst_addr, req_flag, req_mode);

    // Send NOTIFY, check that rdy asserts (registered, 1-cycle latency)
    @(posedge clk_mhdma);
    decoded_command.req_id   <= REQ_ID_NOTIFY;
    decoded_command.hpu_id   <= hpu_id;
    decoded_command.iop_id   <= iop_id;
    decoded_command.src_addr <= iop_src_addr;
    decoded_command.dst_addr <= iop_dst_addr;
    decoded_command.rsvd     <= '0;
    decoded_command.flag     <= req_flag;
    decoded_command.mode     <= req_mode;
    decoded_command_vld      <= 1'b1;

    begin : wait_rdy_block
      int wait_count;
      wait_count = 0;
      while (~decoded_command_rdy &( wait_count < 500)) begin
        @(posedge clk_mhdma);
        wait_count++;
      end
      assert (wait_count < 500) else begin
        $display("[ERROR:%0d] decoded_command_rdy timeout", scenario_id);
        error_assert = 1'b1;
      end
    end

    // rdy asserted -> handshake
    assert (decoded_command_rdy == 1'b1) else begin
      $display("[ERROR:%0d] rdy should be 1 after vld asserted", scenario_id);
      error_assert = 1'b1;
    end

    @(posedge clk_mhdma);
    decoded_command_vld <= 1'b0;

    // Complete notify flow
    wait_slave_command_vld(500, timed_out);
    consume_slave_command();
    simulate_pulse(notify_ack_sent, clk_mhdma);
    wait_interrupt_notify(500, timed_out);
    clear_signal(clear_interrupt_notify, clk_mhdma_cfg);
    repeat (10) @(posedge clk_mhdma_cfg);

    scenario_end(scenario_id, clk_mhdma_cfg);
  endtask

  // -------------------------------------------------------------------------
  // Scenario : Multiple sequential read requests
  // -------------------------------------------------------------------------
  task automatic run_scenario_multiple_sequential_reads();
    logic [REG_DATA_W-1:0] hbm_reads_before;

    scenario_start(scenario_id, "Multiple sequential read requests");
    hbm_reads_before = stat.nb_read_to_hbm;

    for (int request_index = 0; request_index < 2; request_index++) begin
      randomize_command_fields($urandom(), hpu_id, iop_id, iop_src_addr, iop_dst_addr, req_flag, req_mode);

      $display("%t > %0d: starting read request %0d", $time, scenario_id, request_index);
      send_decoded_command(REQ_ID_READ, hpu_id, iop_id, iop_src_addr, iop_dst_addr, req_flag, req_mode, '0);
      complete_cem_flow(TIMEOUT_CYCLES, timed_out);
      check_no_timeout(timed_out, scenario_id, $sformatf("CEM flow timeout on request %0d", request_index));
      assert (stat.fsm_cem == 2'b00) else begin $display("[ERROR:%0d] CEM not idle after request %0d", scenario_id, request_index); error_assert = 1'b1; end
    end

    assert (stat.nb_read_to_hbm > hbm_reads_before) else begin
      $display("[ERROR:%0d] nb_read_to_hbm did not increase", scenario_id);
      error_assert = 1'b1;
    end
    $display("%t > %0d: nb_read_to_hbm: before=%0d, after=%0d", $time, scenario_id, hbm_reads_before, stat.nb_read_to_hbm);

    scenario_end(scenario_id, clk_mhdma_cfg);
  endtask

  // -------------------------------------------------------------------------
  // Scenario : Statistics counters and reset
  // -------------------------------------------------------------------------
  task automatic run_scenario_statistics_counters_and_reset();
    logic [REG_DATA_W-1:0] words_pc1_before;

    scenario_start(scenario_id, "Statistics counters and reset");

    check_fsm_idle(scenario_id);
    assert (stat.nb_read_to_hbm > 0) else begin $display("[ERROR:%0d] nb_read_to_hbm should be non-zero", scenario_id); error_assert = 1'b1; end

    // Reset nb_read_to_hbm
    @(posedge clk_mhdma);
    stat_rst.nb_read_to_hbm <= 1'b1;
    @(posedge clk_mhdma);
    stat_rst.nb_read_to_hbm <= 1'b0;
    @(posedge clk_mhdma);
    assert (stat.nb_read_to_hbm == 0) else begin
      $display("[ERROR:%0d] nb_read_to_hbm not reset", scenario_id);
      error_assert = 1'b1;
    end

    // Check per-PC word counters
    if (ETH_PC > 1) begin
      assert (stat.nb_words_received_pc[0] > 0) else begin $display("[ERROR:%0d] nb_words_received_pc[0] should be non-zero", scenario_id); error_assert = 1'b1; end
      words_pc1_before = stat.nb_words_received_pc[1];
      assert (words_pc1_before > 0) else begin $display("[ERROR:%0d] nb_words_received_pc[1] should be non-zero", scenario_id); error_assert = 1'b1; end

      // Reset only PC0 counter
      @(posedge clk_mhdma);
      stat_rst.nb_words_received_pc[0] <= 1'b1;
      @(posedge clk_mhdma);
      stat_rst.nb_words_received_pc[0] <= 1'b0;
      @(posedge clk_mhdma);
      assert (stat.nb_words_received_pc[0] == 0)                else begin $display("[ERROR:%0d] nb_words_received_pc[0] not reset", scenario_id);               error_assert = 1'b1; end
      assert (stat.nb_words_received_pc[1] == words_pc1_before) else begin $display("[ERROR:%0d] nb_words_received_pc[1] was affected by PC0 reset", scenario_id); error_assert = 1'b1; end
    end else begin
      assert (stat.nb_words_received_pc[0] > 0) else begin
        $display("[ERROR:%0d] nb_words_received_pc[0] should be non-zero", scenario_id);
        error_assert = 1'b1;
      end
      @(posedge clk_mhdma);
      stat_rst.nb_words_received_pc[0] <= 1'b1;
      @(posedge clk_mhdma);
      stat_rst.nb_words_received_pc[0] <= 1'b0;
      @(posedge clk_mhdma);
      assert (stat.nb_words_received_pc[0] == 0) else begin
        $display("[ERROR:%0d] nb_words_received_pc[0] not reset", scenario_id);
        error_assert = 1'b1;
      end
    end

    scenario_end(scenario_id, clk_mhdma_cfg);
  endtask

  // -------------------------------------------------------------------------
  // Scenario : Interleaved Notify and Read requests
  // -------------------------------------------------------------------------
  task automatic run_scenario_interleaved_notify_and_read();
    logic notify_command_done;
    logic read_command_done;
    logic notify_interrupt_received;
    logic read_flow_complete;

    logic [HPU_ID_W-1:0]   hpu_id_notify;
    logic [IOP_ID_W-1:0]   iop_id_notify;
    logic [SRC_ADDR_W-1:0] src_addr_notify;
    logic [DST_ADDR_W-1:0] dst_addr_notify;
    logic [FLAG_W-1:0]     flag_notify;
    logic [MODE_W-1:0]     mode_notify;

    logic [HPU_ID_W-1:0]   hpu_id_read;
    logic [IOP_ID_W-1:0]   iop_id_read;
    logic [SRC_ADDR_W-1:0] src_addr_read;
    logic [DST_ADDR_W-1:0] dst_addr_read;
    logic [FLAG_W-1:0]     flag_read;
    logic [MODE_W-1:0]     mode_read;

    scenario_start(scenario_id, "Interleaved Notify and Read requests");

    notify_command_done = 1'b0;
    read_command_done = 1'b0;
    notify_interrupt_received = 1'b0;
    read_flow_complete = 1'b0;

    hpu_id_notify   = $urandom();
    iop_id_notify   = $urandom();
    src_addr_notify = $urandom();
    dst_addr_notify = $urandom();
    flag_notify     = $urandom();
    mode_notify     = $urandom();

    hpu_id_read   = $urandom();
    iop_id_read   = $urandom();
    src_addr_read = $urandom();
    dst_addr_read = $urandom();
    flag_read     = $urandom();
    mode_read     = $urandom();

    fork
      // Thread 1: Send NOTIFY then READ
      begin
        send_decoded_command(REQ_ID_NOTIFY, hpu_id_notify, iop_id_notify, src_addr_notify, dst_addr_notify, flag_notify, mode_notify, '0);
        notify_command_done = 1'b1;
        send_decoded_command(REQ_ID_READ, hpu_id_read, iop_id_read, src_addr_read, dst_addr_read, flag_read, mode_read, '0);
        read_command_done = 1'b1;
      end
      // Thread 2: Handle NOTIFY_ACK slave_command and ack
      begin
        wait_slave_command_vld(TIMEOUT_CYCLES, timed_out);
        if (~timed_out & slave_command.req_id == REQ_ID_NOTIFY_ACK) begin
          consume_slave_command();
          simulate_pulse(notify_ack_sent, clk_mhdma);
        end
      end
      // Thread 3: Handle interrupt
      begin
        wait_interrupt_notify(TIMEOUT_CYCLES, timed_out);
        if (~timed_out) begin
          notify_interrupt_received = 1'b1;
          clear_signal(clear_interrupt_notify, clk_mhdma_cfg);
        end
      end
      // Thread 4: Complete CEM flow after read is sent
      begin
        wait (read_command_done);
        wait_slave_command_vld(TIMEOUT_CYCLES, timed_out);
        if (~timed_out) begin
          consume_slave_command();
          wait_ce_vld(TIMEOUT_CYCLES, timed_out);
          if (~timed_out) begin
            repeat (CE_DRAIN_WAIT_CYCLES) @(posedge clk_mhdma);
            simulate_pulse(ciphertext_sent, clk_mhdma);
            read_flow_complete = 1'b1;
          end
        end
      end
    join

    assert (notify_command_done)       else begin $display("[ERROR:%0d] NOTIFY command not sent", scenario_id);      error_assert  = 1'b1; end
    assert (notify_interrupt_received) else begin $display("[ERROR:%0d] NOTIFY interrupt not received", scenario_id); error_assert  = 1'b1; end
    assert (read_flow_complete)        else begin $display("[ERROR:%0d] READ flow not complete", scenario_id);        error_timeout = 1'b1; end

    repeat (50) @(posedge clk_mhdma);
    check_fsm_idle(scenario_id);

    scenario_end(scenario_id, clk_mhdma_cfg);
  endtask

  // -------------------------------------------------------------------------
  // Scenario : CEM backpressure (slave_command_rdy deasserted during CEM)
  // -------------------------------------------------------------------------
  task automatic run_scenario_cem_backpressure();
    scenario_start(scenario_id, "CEM backpressure");
    randomize_command_fields($urandom(), hpu_id, iop_id, iop_src_addr, iop_dst_addr, req_flag, req_mode);

    send_decoded_command(REQ_ID_READ, hpu_id, iop_id, iop_src_addr, iop_dst_addr, req_flag, req_mode, '0);

    // slave_command_vld fires from RREQ FIFO output
    wait_slave_command_vld(TIMEOUT_CYCLES, timed_out);
    check_no_timeout(timed_out, scenario_id, "slave_command_vld timeout");
    assert (slave_command.req_id == REQ_ID_EMISSION) else begin
      $display("[ERROR:%0d] req_id mismatch", scenario_id);
      error_assert = 1'b1;
    end

    // Stall: with slave_command_rdy=0, RREQ FIFO not popped : no new AXI4 reads
    begin : stall_check
      int ar_count_before [ETH_PC];
      for (int pc = 0; pc < ETH_PC; pc++)
        ar_count_before[pc] = ar_transaction_count[pc];

      repeat (100) @(posedge clk_mhdma);

      for (int pc = 0; pc < ETH_PC; pc++) begin
        assert (ar_transaction_count[pc] == ar_count_before[pc]) else begin
          $display("[ERROR:%0d] AXI4 AR on PC%0d during backpressure", scenario_id, pc);
          error_assert = 1'b1;
        end
      end
    end
    assert (stat.fsm_cem == 2'b10) else begin
      $display("[ERROR:%0d] CEM FSM not in READ_N_SEND during stall", scenario_id);
      error_assert = 1'b1;
    end

    // Release backpressure -> RREQ pops -> AXI4 reads -> CE data
    consume_slave_command();

    wait_ce_vld(TIMEOUT_CYCLES, timed_out);
    check_no_timeout(timed_out, scenario_id, "ce_vld timeout after consume");

    // Consume CE data by counting actual handshakes (not cycles)
    begin : drain_ce_backpressure
      int ce_count;
      int cycle_count;
      ce_count = 0;
      cycle_count = 0;
      while ((ce_count < CT_NB_WORDS_MRMAC) & (cycle_count < TIMEOUT_CYCLES)) begin
        @(posedge clk_mhdma);
        if (ce_vld & ce_rdy) ce_count++;
        cycle_count++;
      end
      check_no_timeout(cycle_count >= TIMEOUT_CYCLES, scenario_id, "CE drain timeout");
    end

    simulate_pulse(ciphertext_sent, clk_mhdma);
    repeat (50) @(posedge clk_mhdma);
    assert (stat.fsm_cem == 2'b00) else begin
      $display("[ERROR:%0d] CEM FSM not idle", scenario_id);
      error_assert = 1'b1;
    end

    scenario_end(scenario_id, clk_mhdma_cfg);
  endtask

  // -------------------------------------------------------------------------
  // Scenario : NOTIFY arriving during CEM_READ_N_SEND
  // -------------------------------------------------------------------------
  task automatic run_scenario_notify_during_cem();
    logic [HPU_ID_W-1:0]   hpu_id_n;
    logic [IOP_ID_W-1:0]   iop_id_n;
    logic [SRC_ADDR_W-1:0] src_n;
    logic [DST_ADDR_W-1:0] dst_n;
    logic [FLAG_W-1:0]     flag_n;
    logic [MODE_W-1:0]     mode_n;

    scenario_start(scenario_id, "NOTIFY during CEM_READ_N_SEND");
    randomize_command_fields($urandom(), hpu_id, iop_id, iop_src_addr, iop_dst_addr, req_flag, req_mode);
    randomize_command_fields($urandom(), hpu_id_n, iop_id_n, src_n, dst_n, flag_n, mode_n);

    // 1. Start CEM flow
    send_decoded_command(REQ_ID_READ, hpu_id, iop_id, iop_src_addr, iop_dst_addr, req_flag, req_mode, '0);

    // 2. Verify CEM is active
    begin : wait_cem_active
      int cnt;
      cnt = 0;
      while (stat.fsm_cem != 2'b10 & cnt < 500) begin @(posedge clk_mhdma); cnt++; end
      assert (cnt < 500) else begin $display("[ERROR:%0d] CEM FSM not in READ_N_SEND", scenario_id); error_assert = 1'b1; end
    end

    // 3. Send NOTIFY while CEM is busy
    send_decoded_command(REQ_ID_NOTIFY, hpu_id_n, iop_id_n, src_n, dst_n, flag_n, mode_n, '0);

    // 4. NRX has priority in slave_command mux - verify NOTIFY_ACK shows up
    repeat (5) @(posedge clk_mhdma);
    assert (slave_command_vld) else begin
      $display("[ERROR:%0d] slave_command_vld not asserted", scenario_id);
      error_assert = 1'b1;
    end
    assert (slave_command.req_id == REQ_ID_NOTIFY_ACK) else begin
      $display("[ERROR:%0d] expected NOTIFY_ACK, got %0h", scenario_id, slave_command.req_id);
      error_assert = 1'b1;
    end

    // 5. Consume NRX command (RREQ stays in FIFO due to priority guard)
    consume_slave_command();
    simulate_pulse(notify_ack_sent, clk_mhdma);

    // 6. Complete NRX: interrupt
    wait_interrupt_notify(500, timed_out);
    check_no_timeout(timed_out, scenario_id, "interrupt_notify timeout");
    clear_signal(clear_interrupt_notify, clk_mhdma_cfg);

    // 7. Consume RREQ command (now presented on slave_command after NRX drained)
    wait_slave_command_vld(500, timed_out);
    check_no_timeout(timed_out, scenario_id, "EMISSION slave_command_vld timeout");
    assert (slave_command.req_id == REQ_ID_EMISSION) else begin
      $display("[ERROR:%0d] expected EMISSION after NRX drain, got %0h", scenario_id, slave_command.req_id);
      error_assert = 1'b1;
    end
    consume_slave_command();

    // 8. Complete CEM: AXI4 reads -> CE data
    wait_ce_vld(TIMEOUT_CYCLES, timed_out);
    check_no_timeout(timed_out, scenario_id, "ce_vld timeout");
    repeat (CE_DRAIN_WAIT_CYCLES) @(posedge clk_mhdma);
    simulate_pulse(ciphertext_sent, clk_mhdma);
    repeat (50) @(posedge clk_mhdma);

    check_fsm_idle(scenario_id);
    scenario_end(scenario_id, clk_mhdma_cfg);
  endtask

  // -------------------------------------------------------------------------
  // Scenario : READ arriving during NRX_TRANSMIT_ACK
  // -------------------------------------------------------------------------
  task automatic run_scenario_read_during_nrx();
    logic [HPU_ID_W-1:0]   hpu_id_r;
    logic [IOP_ID_W-1:0]   iop_id_r;
    logic [SRC_ADDR_W-1:0] src_r;
    logic [DST_ADDR_W-1:0] dst_r;
    logic [FLAG_W-1:0]     flag_r;
    logic [MODE_W-1:0]     mode_r;

    scenario_start(scenario_id, "READ during NRX_TRANSMIT_ACK");
    randomize_command_fields($urandom(), hpu_id, iop_id, iop_src_addr, iop_dst_addr, req_flag, req_mode);
    randomize_command_fields($urandom(), hpu_id_r, iop_id_r, src_r, dst_r, flag_r, mode_r);

    // 1. Start NRX flow
    send_decoded_command(REQ_ID_NOTIFY, hpu_id, iop_id, iop_src_addr, iop_dst_addr, req_flag, req_mode, '0);
    assert (stat.fsm_notify_rx == 2'b10) else begin
      $display("[ERROR:%0d] NRX FSM not in TRANSMIT_ACK", scenario_id);
      error_assert = 1'b1;
    end

    // 2. NRX slave_command ready
    wait_slave_command_vld(500, timed_out);
    check_no_timeout(timed_out, scenario_id, "NRX slave_command_vld timeout");
    assert (slave_command.req_id == REQ_ID_NOTIFY_ACK) else begin
      $display("[ERROR:%0d] expected NOTIFY_ACK", scenario_id);
      error_assert = 1'b1;
    end

    // 3. Send READ while NRX is busy
    send_decoded_command(REQ_ID_READ, hpu_id_r, iop_id_r, src_r, dst_r, flag_r, mode_r, '0);

    // 4. Consume NRX command (RREQ stays in FIFO due to priority guard)
    consume_slave_command();
    simulate_pulse(notify_ack_sent, clk_mhdma);

    // 5. Complete NRX: interrupt
    wait_interrupt_notify(500, timed_out);
    check_no_timeout(timed_out, scenario_id, "interrupt_notify timeout");
    clear_signal(clear_interrupt_notify, clk_mhdma_cfg);

    // 6. Consume RREQ command (now presented on slave_command after NRX drained)
    wait_slave_command_vld(500, timed_out);
    check_no_timeout(timed_out, scenario_id, "EMISSION slave_command_vld timeout");
    assert (slave_command.req_id == REQ_ID_EMISSION) else begin
      $display("[ERROR:%0d] expected EMISSION after NRX drain, got %0h", scenario_id, slave_command.req_id);
      error_assert = 1'b1;
    end
    consume_slave_command();

    // 7. Complete CEM: AXI4 reads -> CE data
    wait_ce_vld(TIMEOUT_CYCLES, timed_out);
    check_no_timeout(timed_out, scenario_id, "ce_vld timeout");
    repeat (CE_DRAIN_WAIT_CYCLES) @(posedge clk_mhdma);
    simulate_pulse(ciphertext_sent, clk_mhdma);
    repeat (50) @(posedge clk_mhdma);

    check_fsm_idle(scenario_id);
    scenario_end(scenario_id, clk_mhdma_cfg);
  endtask

  // -------------------------------------------------------------------------
  // Scenario : Dual-pop guard (regression for concurrent NRX+RREQ pop)
  // Verifies that when both NRX and RREQ FIFOs have valid output,
  // a single slave_command_rdy pulse only pops the NRX FIFO (priority),
  // and the RREQ command is still presented on the next cycle.
  // -------------------------------------------------------------------------
  task automatic run_scenario_dual_pop_guard();
    scenario_start(scenario_id, "Dual-pop guard (NRX+RREQ concurrent valid)");
    randomize_command_fields($urandom(), hpu_id, iop_id, iop_src_addr, iop_dst_addr, req_flag, req_mode);

    // 1. Send NOTIFY -> NRX enters TRANSMIT_ACK
    send_decoded_command(REQ_ID_NOTIFY, hpu_id, iop_id, iop_src_addr, iop_dst_addr, req_flag, req_mode, '0);
    assert (stat.fsm_notify_rx == 2'b10) else begin
      $display("[ERROR:%0d] NRX FSM not in TRANSMIT_ACK", scenario_id);
      error_assert = 1'b1;
    end

    // 2. Send READ -> CEM enters READ_N_SEND (both FSMs now active)
    randomize_command_fields($urandom(), hpu_id, iop_id, iop_src_addr, iop_dst_addr, req_flag, req_mode);
    send_decoded_command(REQ_ID_READ, hpu_id, iop_id, iop_src_addr, iop_dst_addr, req_flag, req_mode, '0);
    assert (stat.fsm_cem == 2'b10) else begin
      $display("[ERROR:%0d] CEM FSM not in READ_N_SEND", scenario_id);
      error_assert = 1'b1;
    end

    // 3. Wait for slave_command_vld with NOTIFY_ACK (NRX priority)
    wait_slave_command_vld(500, timed_out);
    check_no_timeout(timed_out, scenario_id, "slave_command_vld timeout");
    assert (slave_command.req_id == REQ_ID_NOTIFY_ACK) else begin
      $display("[ERROR:%0d] expected NOTIFY_ACK (NRX priority), got %0h", scenario_id, slave_command.req_id);
      error_assert = 1'b1;
    end

    // 4. Single pulse: consume the NOTIFY_ACK
    consume_slave_command();
    simulate_pulse(notify_ack_sent, clk_mhdma);

    // 5. KEY CHECK: EMISSION command must still appear (RREQ FIFO not drained)
    wait_slave_command_vld(500, timed_out);
    check_no_timeout(timed_out, scenario_id, "EMISSION slave_command_vld never arrived (dual-pop bug)");
    assert (slave_command.req_id == REQ_ID_EMISSION) else begin
      $display("[ERROR:%0d] expected EMISSION after NOTIFY_ACK, got %0h -- RREQ was silently dropped",
               scenario_id, slave_command.req_id);
      error_assert = 1'b1;
    end

    // 6. Complete CEM flow normally
    consume_slave_command();
    wait_ce_vld(TIMEOUT_CYCLES, timed_out);
    check_no_timeout(timed_out, scenario_id, "ce_vld timeout");

    begin
      int ce_count, cycle_count;
      ce_count = 0;
      cycle_count = 0;
      while ((ce_count < CT_NB_WORDS_MRMAC) & (cycle_count < TIMEOUT_CYCLES)) begin
        @(posedge clk_mhdma);
        if (ce_vld & ce_rdy) ce_count++;
        cycle_count++;
      end
      check_no_timeout(cycle_count >= TIMEOUT_CYCLES, scenario_id, "CE drain timeout");
    end

    simulate_pulse(ciphertext_sent, clk_mhdma);
    repeat (50) @(posedge clk_mhdma);

    // 7. Drain interrupt
    wait_interrupt_notify(500, timed_out);
    if (~timed_out) clear_signal(clear_interrupt_notify, clk_mhdma_cfg);
    repeat (10) @(posedge clk_mhdma_cfg);

    check_fsm_idle(scenario_id);
    scenario_end(scenario_id, clk_mhdma_cfg);
  endtask

  // -------------------------------------------------------------------------
  // Scenario : Back-to-back commands (0-gap, vld stays asserted)
  // Stress: NOTIFY then READ with no idle cycle between handshakes
  // -------------------------------------------------------------------------
  task automatic run_scenario_back_to_back();
    logic [HPU_ID_W-1:0]   hpu_id_n;
    logic [IOP_ID_W-1:0]   iop_id_n;
    logic [SRC_ADDR_W-1:0] src_n;
    logic [DST_ADDR_W-1:0] dst_n;
    logic [FLAG_W-1:0]     flag_n;
    logic [MODE_W-1:0]     mode_n;

    logic [HPU_ID_W-1:0]   hpu_id_r;
    logic [IOP_ID_W-1:0]   iop_id_r;
    logic [SRC_ADDR_W-1:0] src_r;
    logic [DST_ADDR_W-1:0] dst_r;
    logic [FLAG_W-1:0]     flag_r;
    logic [MODE_W-1:0]     mode_r;

    scenario_start(scenario_id, "Back-to-back commands (0-gap)");
    randomize_command_fields($urandom(), hpu_id_n, iop_id_n, src_n, dst_n, flag_n, mode_n);
    randomize_command_fields($urandom(), hpu_id_r, iop_id_r, src_r, dst_r, flag_r, mode_r);

    // Drive NOTIFY, keep vld asserted across both handshakes
    @(posedge clk_mhdma);
    decoded_command.req_id       <= REQ_ID_NOTIFY;
    decoded_command.hpu_id       <= hpu_id_n;
    decoded_command.iop_id       <= iop_id_n;
    decoded_command.src_addr     <= src_n;
    decoded_command.dst_addr     <= dst_n;
    decoded_command.rsvd         <= '0;
    decoded_command.flag         <= flag_n;
    decoded_command.mode         <= mode_n;
    decoded_command.src_mac_addr <= 24'hABCDEF;
    decoded_command.seq_num      <= '0;
    decoded_command_vld          <= 1'b1;

    // Wait for first handshake (NOTIFY)
    do @(posedge clk_mhdma); while (~decoded_command_rdy);

    // Immediately switch to READ - vld stays high, no idle cycle
    decoded_command.req_id       <= REQ_ID_READ;
    decoded_command.hpu_id       <= hpu_id_r;
    decoded_command.iop_id       <= iop_id_r;
    decoded_command.src_addr     <= src_r;
    decoded_command.dst_addr     <= dst_r;
    decoded_command.flag         <= flag_r;
    decoded_command.mode         <= mode_r;

    // Wait for second handshake (READ)
    do @(posedge clk_mhdma); while (~decoded_command_rdy);
    @(posedge clk_mhdma);
    decoded_command_vld <= 1'b0;

    // Complete NRX flow
    wait_slave_command_vld(500, timed_out);
    check_no_timeout(timed_out, scenario_id, "NOTIFY slave_command_vld timeout");
    assert (slave_command.req_id == REQ_ID_NOTIFY_ACK) else begin
      $display("[ERROR:%0d] expected NOTIFY_ACK", scenario_id);
      error_assert = 1'b1;
    end

    // Consume NRX command (RREQ stays in FIFO due to priority guard)
    consume_slave_command();
    simulate_pulse(notify_ack_sent, clk_mhdma);

    wait_interrupt_notify(500, timed_out);
    check_no_timeout(timed_out, scenario_id, "interrupt_notify timeout");
    clear_signal(clear_interrupt_notify, clk_mhdma_cfg);

    // Consume RREQ command (now presented on slave_command after NRX drained)
    wait_slave_command_vld(500, timed_out);
    check_no_timeout(timed_out, scenario_id, "EMISSION slave_command_vld timeout");
    assert (slave_command.req_id == REQ_ID_EMISSION) else begin
      $display("[ERROR:%0d] expected EMISSION after NRX drain, got %0h", scenario_id, slave_command.req_id);
      error_assert = 1'b1;
    end
    consume_slave_command();

    // Complete CEM flow
    wait_ce_vld(TIMEOUT_CYCLES, timed_out);
    check_no_timeout(timed_out, scenario_id, "ce_vld timeout");
    repeat (CE_DRAIN_WAIT_CYCLES) @(posedge clk_mhdma);
    simulate_pulse(ciphertext_sent, clk_mhdma);
    repeat (50) @(posedge clk_mhdma);

    check_fsm_idle(scenario_id);
    scenario_end(scenario_id, clk_mhdma_cfg);
  endtask

  // -------------------------------------------------------------------------
  // Scenario : Physical address correctness + page boundary on all PCs
  // Verifies:
  //   - m_axi4_araddr matches expected phy_addr = regf_ct_mem_addr + src_addr * CT_MEM_BYTES
  //   - page boundary splitting produces multiple AR bursts on every PC (not just PC0)
  // Starting near a page boundary forces each PC to split the transfer into multiple AR bursts
  // -------------------------------------------------------------------------
  task automatic run_scenario_phy_addr_and_page_boundary_all_pcs();
    logic [2*REG_DATA_W-1:0] saved_addr [ETH_PC];
    int ar_count_before [ETH_PC];
    int ar_count_after  [ETH_PC];

    logic [AXI4_ADD_W-1:0] expected_phy_addr [ETH_PC];
    logic [AXI4_ADD_W-1:0] captured_first_araddr [ETH_PC];
    logic                  captured [ETH_PC];

    scenario_start(scenario_id, "Phy addr correctness + page boundary all PCs");
    randomize_command_fields($urandom(), hpu_id, iop_id, iop_src_addr, iop_dst_addr, req_flag, req_mode);

    // Place all PCs near a page boundary so each needs multiple AR bursts
    for (int pc = 0; pc < ETH_PC; pc++) begin
      saved_addr[pc] = regf_ct_mem_addr[pc];
      regf_ct_mem_addr[pc] = 64'(PAGE_BYTES - AXI4_DATA_BYTES) + pc * 64'h0000_0000_0010_0000;
    end

    // Compute expected phy_addr per PC
    for (int pc = 0; pc < ETH_PC; pc++) begin
      expected_phy_addr[pc] = regf_ct_mem_addr[pc] + iop_src_addr * CT_MEM_BYTES;
      captured[pc] = 1'b0;
      ar_count_before[pc] = ar_transaction_count[pc];
    end

    // Send the command and consume slave_command (but do NOT send ciphertext_sent yet)
    send_decoded_command(REQ_ID_READ, hpu_id, iop_id, iop_src_addr, iop_dst_addr, req_flag, req_mode, 'h0);

    wait_slave_command_vld(TIMEOUT_CYCLES, timed_out);
    check_no_timeout(timed_out, scenario_id, "slave_command_vld timeout");
    consume_slave_command();

    // Wait for all PCs to have at least one AR transaction, capturing the first address per PC
    begin : monitor_ar_addrs
      int monitor_cnt;
      monitor_cnt = 0;
      while (monitor_cnt < TIMEOUT_CYCLES) begin
        @(posedge clk_mhdma);
        for (int pc = 0; pc < ETH_PC; pc++) begin
          if (~captured[pc] & nmu_axi4_arvalid[pc] & nmu_axi4_arready[pc]) begin
            captured_first_araddr[pc] = nmu_axi4_araddr[pc];
            captured[pc] = 1'b1;
          end
        end
        begin
          logic all_captured;
          all_captured = 1'b1;
          for (int pc = 0; pc < ETH_PC; pc++)
            all_captured = all_captured & captured[pc];
          if (all_captured) break;
        end
        monitor_cnt++;
      end
      timed_out = (monitor_cnt >= TIMEOUT_CYCLES);
    end

    check_no_timeout(timed_out, scenario_id, "AR capture timeout - not all PCs issued AR");

    // Now drain CE data and complete the CEM flow
    wait_ce_vld(TIMEOUT_CYCLES, timed_out);
    check_no_timeout(timed_out, scenario_id, "ce_vld timeout");
    repeat (2 * CE_DRAIN_WAIT_CYCLES) @(posedge clk_mhdma);
    simulate_pulse(ciphertext_sent, clk_mhdma);
    repeat (50) @(posedge clk_mhdma);

    // Check address correctness per PC
    for (int pc = 0; pc < ETH_PC; pc++) begin
      assert (captured[pc]) else begin
        $display("[ERROR:%0d] PC%0d: no AR transaction captured", scenario_id, pc);
        error_assert = 1'b1;
      end
      assert (captured_first_araddr[pc] == expected_phy_addr[pc]) else begin
        $display("[ERROR:%0d] PC%0d: araddr mismatch: got 0x%0h, expected 0x%0h",
                 scenario_id, pc, captured_first_araddr[pc], expected_phy_addr[pc]);
        error_assert = 1'b1;
      end
    end

    // Check page boundary splitting produced multiple bursts per PC
    for (int pc = 0; pc < ETH_PC; pc++) begin
      ar_count_after[pc] = ar_transaction_count[pc];
      $display("%t > %0d: PC%0d AR transactions = %0d",
               $time, scenario_id, pc, ar_count_after[pc] - ar_count_before[pc]);
      assert (ar_count_after[pc] - ar_count_before[pc] > 1) else begin
        $display("[ERROR:%0d] PC%0d: expected multiple AR bursts near page boundary", scenario_id, pc);
        error_assert = 1'b1;
      end
    end

    // Restore original base addresses
    for (int pc = 0; pc < ETH_PC; pc++)
      regf_ct_mem_addr[pc] = saved_addr[pc];

    scenario_end(scenario_id, clk_mhdma_cfg);
  endtask

// ============================================================================================== --
// Main test sequence
// ============================================================================================== --
  initial begin
    tb_init();
    scenario_id = 0;

    wait (s_rstn_cfg == 1'b1);
    wait (s_rstn_mhdma == 1'b1);
    repeat (20) @(posedge clk_mhdma_cfg);

    // Wait for CDC FIFOs to exit reset-busy state
    repeat (50) @(posedge clk_mhdma_cfg);

    run_scenario_notify_rx_flow();
    run_scenario_notify_rx_backpressure();
    run_scenario_cem_flow();
    run_scenario_cem_backpressure();
    run_scenario_decoded_command_rdy_arbitration();
    run_scenario_multiple_sequential_reads();
    run_scenario_statistics_counters_and_reset();
    run_scenario_interleaved_notify_and_read();
    run_scenario_notify_during_cem();
    run_scenario_read_during_nrx();
    run_scenario_dual_pop_guard();
    run_scenario_back_to_back();
    run_scenario_phy_addr_and_page_boundary_all_pcs();

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

  generate
    for (genvar gen_pc = 0; gen_pc < ETH_PC; gen_pc++) begin : gen_sva_axi4

      property axi4_arvalid_stable;
        @(posedge clk_mhdma) disable iff (~s_rstn_mhdma)
        (nmu_axi4_arvalid[gen_pc] && !nmu_axi4_arready[gen_pc]) |=>
          $stable(nmu_axi4_arvalid[gen_pc]) && $stable(nmu_axi4_araddr[gen_pc]) && $stable(nmu_axi4_arlen[gen_pc]);
      endproperty

      property axi4_arburst_incr;
        @(posedge clk_mhdma) disable iff (~s_rstn_mhdma)
        nmu_axi4_arvalid[gen_pc] |-> (nmu_axi4_arburst[gen_pc] == AXI4B_INCR);
      endproperty

      assert_arvalid_stable: assert property(axi4_arvalid_stable)
        else begin
          $display("[ERROR-SVA] PC%0d AR channel: value changed when arready was low", gen_pc);
          error_assert = 1'b1;
        end

      assert_arburst_incr: assert property(axi4_arburst_incr)
        else begin
          $display("[ERROR-SVA] PC%0d AR channel: arburst is not INCR", gen_pc);
          error_assert = 1'b1;
        end

    end
  endgenerate

  // NRX FSM should not be in unknown state
  property nrx_fsm_valid;
    @(posedge clk_mhdma) disable iff (~s_rstn_mhdma)
    (stat.fsm_notify_rx inside {2'b00, 2'b10});
  endproperty

  assert_nrx_fsm_valid: assert property(nrx_fsm_valid)
    else begin
      $display("[ERROR-SVA] NRX FSM in invalid state: %0b", stat.fsm_notify_rx);
      error_assert = 1'b1;
    end

  // CEM FSM should not be in unknown state
  property cem_fsm_valid;
    @(posedge clk_mhdma) disable iff (~s_rstn_mhdma)
    (stat.fsm_cem inside {2'b00, 2'b10});
  endproperty

  assert_cem_fsm_valid: assert property(cem_fsm_valid)
    else begin
      $display("[ERROR-SVA] CEM FSM in invalid state: %0b", stat.fsm_cem);
      error_assert = 1'b1;
    end

  // AR must never be issued (s0_axi_arvalid) to a PC that rd_pc_onehot doesn't serve
  property ar_issued_only_on_active_rd_pc;
    @(posedge clk_mhdma) disable iff (~s_rstn_mhdma)
    (mhdma_slave.s0_axi_arvalid) |-> (mhdma_slave.ar_pc_onehot == mhdma_slave.rd_pc_onehot);
  endproperty

  assert_ar_issued_only_on_active_rd_pc: assert property(ar_issued_only_on_active_rd_pc)
    else begin
      $display("[ERROR-SVA] AR issued while ar_pc_onehot (0x%0h) != rd_pc_onehot (0x%0h)", mhdma_slave.ar_pc_onehot, mhdma_slave.rd_pc_onehot);
      error_assert = 1'b1;
    end

endmodule
