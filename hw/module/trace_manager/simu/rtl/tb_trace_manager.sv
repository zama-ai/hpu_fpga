// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Testbench to verify trace_manager.
// ==============================================================================================

module tb_trace_manager;
`timescale 1ns/10ps

  import axi_if_common_param_pkg::*;
  import axi_if_trc_axi_pkg::*;

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int CLK_HALF_PERIOD = 1;
  localparam int ARST_ACTIVATION = 17;

  parameter int INFO_W        = 10;
  parameter int DEPTH         = 64; // Physical RAM depth for INFO_W size data - Should be a power of 2
  parameter int RAM_LATENCY   = 2;
  parameter int MEM_DEPTH     = 1; // MByte unit. The module will wrap

  parameter int SAMPLE_NB = 200_000;

  localparam int MEM_DEPTH_SZ = $clog2(MEM_DEPTH * 1024*1024);

  localparam int ACS_W    = INFO_W <= AXI4_DATA_W ? AXI4_DATA_W : ((INFO_W + AXI4_DATA_W - 1) /AXI4_DATA_W) * AXI4_DATA_W;
  localparam int AXI_WORD_PER_INFO = ACS_W / AXI4_DATA_W;
  localparam int MEM_BYTES = MEM_DEPTH * 1024 * 1024;

  localparam int RAND_RANGE = 1023;
  localparam [$clog2(RAND_RANGE)-1:0] DATA_SINK_THROUGHPUT = RAND_RANGE * 3 / 4;
  localparam [$clog2(RAND_RANGE)-1:0] CMD_SINK_THROUGHPUT  = RAND_RANGE * 3 / 4;
  localparam [$clog2(RAND_RANGE)-1:0] SRC_THROUGHPUT  = (DATA_SINK_THROUGHPUT / 2) / (AXI_WORD_PER_INFO + 1); // */2 to get some margin, +1 : for the command

// ============================================================================================== --
// clock, reset
// ============================================================================================== --
  bit clk;
  bit a_rst_n; // asynchronous reset
  bit s_rst_n; // synchronous reset

  initial begin
    clk     = 1'b0;
    a_rst_n = 1'b0;                   // active reset
    #ARST_ACTIVATION a_rst_n = 1'b1; // disable reset
  end

  always begin
    #CLK_HALF_PERIOD clk = ~clk;
  end

  always_ff @(posedge clk) begin
    s_rst_n <= a_rst_n;
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

// ============================================================================================== --
// Error
// ============================================================================================== --
  bit   error;
  logic error_trace;
  bit   error_data;
  bit   error_add;

  assign error = error_trace | error_data | error_add;

  always_ff @(posedge clk)
    if (error) begin
      $display("%t > INFO: error_trace = %0d", $time, error_trace);
      $display("%t > FAILURE !", $time);
      $finish;
    end

// ============================================================================================== --
// input / output signals
// ============================================================================================== --
  logic                       wr_en;
  logic [INFO_W-1:0]          wr_data;

  logic [AXI4_ADD_W-1:0]      addr_ofs; // should be MEM_DEPTH aligned

  logic [AXI4_ID_W-1:0]       m_axi4_awid;
  logic [AXI4_ADD_W-1:0]      m_axi4_awaddr;
  logic [AXI4_LEN_W-1:0]      m_axi4_awlen;
  logic [AXI4_SIZE_W-1:0]     m_axi4_awsize;
  logic [AXI4_BURST_W-1:0]    m_axi4_awburst;
  logic                       m_axi4_awvalid;
  logic                       m_axi4_awready;
  logic [AXI4_DATA_W-1:0]     m_axi4_wdata;
  logic [AXI4_STRB_W-1:0]     m_axi4_wstrb;
  logic                       m_axi4_wlast;
  logic                       m_axi4_wvalid;
  logic                       m_axi4_wready;
  logic [AXI4_ID_W-1:0]       m_axi4_bid;
  logic [AXI4_RESP_W-1:0]     m_axi4_bresp;
  logic                       m_axi4_bvalid;
  logic                       m_axi4_bready;

// ============================================================================================== --
// Design under test instance
// ============================================================================================== --
  trace_manager
  #(
    .INFO_W        (INFO_W),
    .DEPTH         (DEPTH),
    .RAM_LATENCY   (RAM_LATENCY),
    .MEM_DEPTH     (MEM_DEPTH)
  ) dut (
    .clk           (clk),
    .s_rst_n       (s_rst_n),

    .wr_en         (wr_en),
    .wr_data       (wr_data),

    .addr_ofs      (addr_ofs),  
    
    .m_axi4_awid    (m_axi4_awid),
    .m_axi4_awaddr  (m_axi4_awaddr),
    .m_axi4_awlen   (m_axi4_awlen),
    .m_axi4_awsize  (m_axi4_awsize),
    .m_axi4_awburst (m_axi4_awburst),
    .m_axi4_awvalid (m_axi4_awvalid),
    .m_axi4_awready (m_axi4_awready),
    .m_axi4_wdata   (m_axi4_wdata),
    .m_axi4_wstrb   (m_axi4_wstrb),
    .m_axi4_wlast   (m_axi4_wlast),
    .m_axi4_wvalid  (m_axi4_wvalid),
    .m_axi4_wready  (m_axi4_wready),
    .m_axi4_bid     (m_axi4_bid),
    .m_axi4_bresp   (m_axi4_bresp),
    .m_axi4_bvalid  (m_axi4_bvalid),
    .m_axi4_bready  (m_axi4_bready),

    .error         (error_trace)
  );

// ============================================================================================== --
// Scenario
// ============================================================================================== --
  initial begin
    addr_ofs = $urandom_range(0, 1<< AXI4_ADD_W) & {{(AXI4_ADD_W-MEM_DEPTH_SZ){1'b1}}, {(MEM_DEPTH_SZ){1'b0}} };
  end

  stream_source
  #(
    .FILENAME   ("random"),
    .DATA_TYPE  ("ascii_hex"),
    .DATA_W     (INFO_W),
    .RAND_RANGE (RAND_RANGE),
    .KEEP_VLD   (1),
    .MASK_DATA  ("x")
  )
  source_wr
  (
    .clk        (clk),
    .s_rst_n    (s_rst_n),

    .data       (wr_data),
    .vld        (wr_en),
    .rdy        (1'b1),

    .throughput (SRC_THROUGHPUT)
  );

  stream_sink #(
    .FILENAME      (""),
    .DATA_TYPE     ("ascii_hex"),
    .FILENAME_REF  (""),
    .DATA_TYPE_REF ("ascii_hex"),
    .DATA_W        (1),
    .RAND_RANGE    (RAND_RANGE),
    .KEEP_RDY      (0)
  ) stream_sink_add (
    .clk     (clk    ),
    .s_rst_n (s_rst_n),

    .data    (1'bx),
    .vld     (m_axi4_awvalid ),
    .rdy     (m_axi4_awready ),

    .error   (/*UNUSED*/),
    .throughput (CMD_SINK_THROUGHPUT)
  );

  stream_sink #(
    .FILENAME      (""),
    .DATA_TYPE     ("ascii_hex"),
    .FILENAME_REF  (""),
    .DATA_TYPE_REF ("ascii_hex"),
    .DATA_W        (1),
    .RAND_RANGE    (RAND_RANGE),
    .KEEP_RDY      (0)
  ) stream_sink_data (
    .clk     (clk    ),
    .s_rst_n (s_rst_n),

    .data    (1'bx),
    .vld     (m_axi4_wvalid ),
    .rdy     (m_axi4_wready ),

    .error   (/*UNUSED*/),
    .throughput (DATA_SINK_THROUGHPUT)
  );

  initial begin
    stream_sink_add.set_do_ref(0);
    stream_sink_add.set_do_write(0);

    stream_sink_data.set_do_ref(0);
    stream_sink_data.set_do_write(0);

    if (!source_wr.open()) begin
      $fatal(1, "%t > ERROR: Opening source_wr stream source", $time);
    end
    if (!stream_sink_add.open())
      $error("%t > ERROR: Something went wrong when opening stream_sink",$time);

    if (!stream_sink_data.open())
      $error("%t > ERROR: Something went wrong when opening stream_sink",$time);

    stream_sink_add.start(SAMPLE_NB);
    stream_sink_data.start(0);
    source_wr.start(SAMPLE_NB);
  end

// ============================================================================================== --
// Check
// ============================================================================================== --
  logic [INFO_W-1:0] data_ref_q[$];

  always_ff @(posedge clk)
    if (wr_en)
      data_ref_q.push_back(wr_data);

  //== Data
  int idx;
  int idxD;
  logic last_idx;

  assign last_idx = idx == AXI_WORD_PER_INFO-1;
  assign idxD = (m_axi4_wvalid && m_axi4_wready) ? last_idx ? 0 : idx + 1 : idx;

  always_ff @(posedge clk)
    if (!s_rst_n) idx <= '0;
    else          idx <= idxD;

  always_ff @(posedge clk)
    if (!s_rst_n)
      error_data <= 1'b0;
    else
      if (m_axi4_wvalid && m_axi4_wready) begin
        logic [AXI_WORD_PER_INFO-1:0][AXI4_DATA_W-1:0] d;

        d = data_ref_q[0];

        assert(m_axi4_wdata == d[idx])
        else begin
          $display("%t > ERROR: Mismatch data idx=%0d exp=0x%0x seen=0x%0x",$time, idx, d[idx], m_axi4_wdata);
          error_data <= 1'b1;
        end

        assert(m_axi4_wlast == last_idx)
        else begin
          $display("%t > ERROR: Mismatch wlast idx=%0d exp=%0d seen=%0d",$time, idx, last_idx, m_axi4_wlast);
          error_data <= 1'b1;
        end

        if (last_idx)
          data_ref_q.pop_front();
      end
  
  logic [AXI4_ADD_W-1:0] ref_add;
  logic [AXI4_ADD_W-1:0] ref_addD;
  logic [AXI4_ADD_W-1:0] ref_addD_tmp;

  assign ref_addD_tmp = ref_add + ACS_W/8;
  assign ref_addD = (m_axi4_awvalid && m_axi4_awready) ? ref_addD_tmp + ACS_W/8 > MEM_BYTES ? '0 : ref_addD_tmp : ref_add;

  always_ff @(posedge clk)
    if (!s_rst_n) ref_add <= '0;
    else          ref_add <= ref_addD;

  always_ff @(posedge clk)
    if (!s_rst_n)
      error_add <= 1'b0;
    else
      if (m_axi4_awvalid && m_axi4_awready) begin
        assert(m_axi4_awaddr == ref_add + addr_ofs)
        else begin
          $display("%t > ERROR: Mismatch add exp=0x%0x seen=0x%0x",$time, ref_add + addr_ofs, m_axi4_awaddr);
          error_add <= 1'b1;
        end

        assert(m_axi4_awlen == AXI_WORD_PER_INFO-1)
        else begin
          $display("%t > ERROR: Mismatch len exp=%0d seen=%0d",$time, idx, AXI_WORD_PER_INFO-1, m_axi4_awlen);
          error_add <= 1'b1;
        end
      end


// ============================================================================================== --
// End of test
// ============================================================================================== --
  initial begin
    end_of_test = 1'b0;
    wait (source_wr.running);
    @(posedge clk);
    wait (!source_wr.running);
    @(posedge clk);
    wait (!stream_sink_add.running);
    @(posedge clk);

    end_of_test = 1'b1;

  end

endmodule
