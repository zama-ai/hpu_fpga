// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with collecting the design trace signals, stores them in memory,
// via an AXI bus.
// ==============================================================================================

module trace_manager
  import axi_if_common_param_pkg::*;
  import axi_if_trc_axi_pkg::*;
#(
  parameter int INFO_W        = 32,
  parameter int DEPTH         = 1024, // Physical RAM depth for INFO_W size data - Should be a power of 2
  parameter int RAM_LATENCY   = 2,
  parameter int MEM_DEPTH     = 4 // MByte unit. The module will wrap
)
(
  input  logic                       clk,        // clock
  input  logic                       s_rst_n,    // synchronous reset

  input  logic                       wr_en,
  input  logic [INFO_W-1:0]          wr_data,

  // Configuration
  input  logic [AXI4_ADD_W-1:0]      addr_ofs, // should be MEM_DEPTH aligned

  // AXI4 interface
  // Write channel
  output logic [AXI4_ID_W-1:0]       m_axi4_awid,
  output logic [AXI4_ADD_W-1:0]      m_axi4_awaddr,
  output logic [AXI4_LEN_W-1:0]      m_axi4_awlen,
  output logic [AXI4_SIZE_W-1:0]     m_axi4_awsize,
  output logic [AXI4_BURST_W-1:0]    m_axi4_awburst,
  output logic                       m_axi4_awvalid,
  input  logic                       m_axi4_awready,
  output logic [AXI4_DATA_W-1:0]     m_axi4_wdata,
  output logic [AXI4_STRB_W-1:0]     m_axi4_wstrb,
  output logic                       m_axi4_wlast,
  output logic                       m_axi4_wvalid,
  input  logic                       m_axi4_wready,
  input  logic [AXI4_ID_W-1:0]       m_axi4_bid,
  input  logic [AXI4_RESP_W-1:0]     m_axi4_bresp,
  input  logic                       m_axi4_bvalid,
  output logic                       m_axi4_bready,

  output logic                       error // overflow
);

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int ELT_NB_W  = $clog2(DEPTH+1) == 0 ? 1 : $clog2(DEPTH+1);
  localparam int DEPTH_W   = $clog2(DEPTH) == 0 ? 1 : $clog2(DEPTH);
  localparam int PT_W      = DEPTH_W;
  localparam int MEM_ADD_W = $clog2(MEM_DEPTH * 1024 * 1024) == 0 ? 1 : $clog2(MEM_DEPTH * 1024 * 1024);

  // Do a very simple design. The main purpose is to have a very small one.
  // The frequency of the input is not much.
  // At most we could have "burst" of BATCH_PBS wr_en.
  localparam int ACS_W    = INFO_W <= AXI4_DATA_W ? AXI4_DATA_W : ((INFO_W + AXI4_DATA_W - 1) /AXI4_DATA_W) * AXI4_DATA_W;
  localparam int AXI_WORD_PER_INFO = ACS_W / AXI4_DATA_W;

  localparam int MEM_ADD_MAX_TMP = ((MEM_DEPTH * 1024 * 1024) / (AXI_WORD_PER_INFO * AXI4_DATA_BYTES)) * (AXI_WORD_PER_INFO * AXI4_DATA_BYTES);
  localparam int MEM_ADD_MAX     = MEM_ADD_MAX_TMP - (AXI_WORD_PER_INFO * AXI4_DATA_BYTES);

// pragma translate_off
  generate
    if (2**$clog2(DEPTH) != DEPTH) begin : __UNSUPPORTED_DEPTH
      $fatal(1,"> ERROR: Trace RAM DEPTH should be a power of 2!");
    end
  endgenerate
// pragma translate_on

// ============================================================================================== --
// Input Pipe
// ============================================================================================== --
  logic              s0_wr_en;
  logic [INFO_W-1:0] s0_wr_data;

  always_ff @(posedge clk)
    if (!s_rst_n) s0_wr_en <= 1'b0;
    else          s0_wr_en <= wr_en;

  always_ff @(posedge clk)
    s0_wr_data <= wr_data;

// ============================================================================================== --
// Data FIFO
// ============================================================================================== --
  logic              dfifo_in_vld;
  logic              dfifo_in_rdy;
  logic [INFO_W-1:0] dfifo_in_data;
  logic              dfifo_out_vld;
  logic              dfifo_out_rdy;
  logic [INFO_W-1:0] dfifo_out_data;

  logic error_fifo_ovf;

  assign dfifo_in_vld  = s0_wr_en;
  assign dfifo_in_data = s0_wr_data;

  assign error_fifo_ovf = dfifo_in_vld & ~dfifo_in_rdy;

  fifo_ram_rdy_vld #(
    .WIDTH              (INFO_W),
    .DEPTH              (DEPTH),
    .RAM_LATENCY        (RAM_LATENCY),
    .ALMOST_FULL_REMAIN (1)
  ) dfifo (
    .clk      (clk),
    .s_rst_n  (s_rst_n),

    .in_data  (dfifo_in_data),
    .in_vld   (dfifo_in_vld),
    .in_rdy   (dfifo_in_rdy),

    .out_data (dfifo_out_data),
    .out_vld  (dfifo_out_vld),
    .out_rdy  (dfifo_out_rdy),

    .almost_full (/*UNUSED*/)
  );

// ============================================================================================== --
// AXI write
// ============================================================================================== --
// Send a write request per INFO.
// If ACS_W > AXI_DATA_X use a burst.
// No need of performance here.
// Use an FSM to sequentialize the request and the data.

  typedef enum logic [1:0] {
    ST_XXX  = 2'bxx,
    ST_IDLE = 2'b00,
    ST_REQ,
    ST_DATA
  } state_e;

  state_e state;
  state_e next_state;

  logic st_idle;
  logic st_req;
  logic st_data;

  logic send_req_done;
  logic send_data_done;

  always_comb begin
    next_state = ST_XXX;
    case (state)
      ST_IDLE : next_state = dfifo_out_vld  ? ST_REQ : state;
      ST_REQ  : next_state = send_req_done  ? ST_DATA : state;
      ST_DATA : next_state = send_data_done ? ST_IDLE : state;
    endcase
  end

  always_ff @(posedge clk)
    if (!s_rst_n) state <= ST_IDLE;
    else          state <= next_state;

  assign st_idle = state == ST_IDLE;
  assign st_req  = state == ST_REQ;
  assign st_data = state == ST_DATA;


// ---------------------------------------------------------------------------------------------- --
// AXI write request
// ---------------------------------------------------------------------------------------------- --
  logic [MEM_ADD_W-1:0] req_add;
  logic [MEM_ADD_W-1:0] req_addD;
  logic                 req_add_max;

  logic        axi_req_vld;
  logic        axi_req_rdy;
  axi4_aw_if_t axi_req;
  axi4_aw_if_t m_axi4_req;

  assign m_axi4_awid    = m_axi4_req.awid   ;
  assign m_axi4_awaddr  = m_axi4_req.awaddr ;
  assign m_axi4_awlen   = m_axi4_req.awlen  ;
  assign m_axi4_awsize  = m_axi4_req.awsize ;
  assign m_axi4_awburst = m_axi4_req.awburst;

  fifo_element #(
    .WIDTH          (AXI4_AW_IF_W),
    .DEPTH          (1),
    .TYPE_ARRAY     (4'h3),
    .DO_RESET_DATA  (0),
    .RESET_DATA_VAL (0)
  ) req_fifo_element (
    .clk     (clk),
    .s_rst_n (s_rst_n),

    .in_data (axi_req),
    .in_vld  (axi_req_vld),
    .in_rdy  (axi_req_rdy),

    .out_data(m_axi4_req),
    .out_vld (m_axi4_awvalid),
    .out_rdy (m_axi4_awready)
  );

  assign axi_req_vld    = st_req;
  assign axi_req.awid   = '0;
  assign axi_req.awaddr = addr_ofs + req_add;
  assign axi_req.awlen  = AXI_WORD_PER_INFO - 1;
  assign axi_req.awsize = AXI4_DATA_BYTES_W;
  assign axi_req.awburst= AXI4B_INCR;

  assign req_addD    = (axi_req_vld && axi_req_rdy) ? req_add_max ? '0 : req_add + AXI_WORD_PER_INFO*AXI4_DATA_BYTES : req_add;
  assign req_add_max = req_add == MEM_ADD_MAX;

  always_ff @(posedge clk)
    if (!s_rst_n) req_add <= '0;
    else          req_add <= req_addD;

  assign send_req_done = axi_req_rdy;

// pragma translate_off
  always_ff @(posedge clk)
    if (axi_req_vld && axi_req_rdy && req_add_max)
      $display("%t > INFO: Trace has reached MEM_DEPTH (%0dMB), wrapping", $time, MEM_DEPTH);
// pragma translate_on

// ---------------------------------------------------------------------------------------------- --
// AXI write data
// ---------------------------------------------------------------------------------------------- --
  logic        axi_data_vld;
  logic        axi_data_rdy;
  axi4_w_if_t  axi_data;
  axi4_w_if_t  m_axi4_data;

  assign m_axi4_wdata  = m_axi4_data.wdata;
  assign m_axi4_wstrb  = m_axi4_data.wstrb;
  assign m_axi4_wlast  = m_axi4_data.wlast;

  assign dfifo_out_rdy  = send_data_done;

  generate
    if (AXI_WORD_PER_INFO == 1) begin : gen_axi_word_per_info_eq_1
      assign axi_data.wdata = dfifo_out_data; // Complete MSB with 0s, if needed.
      assign axi_data.wstrb = '1;
      assign axi_data.wlast = 1'b1;
      assign axi_data_vld   = st_data;
      assign send_data_done = st_data & axi_data_rdy;
    end
    else begin : gen_axi_word_per_info_gt_1
      localparam int IDX_W = $clog2(AXI_WORD_PER_INFO) == 0 ? 1 : $clog2(AXI_WORD_PER_INFO);

      logic [AXI_WORD_PER_INFO-1:0][AXI4_DATA_W-1:0] dfifo_out_data_a;
      logic [IDX_W-1:0]                        idx;
      logic [IDX_W-1:0]                        idxD;
      logic                                    last_idx;

      assign dfifo_out_data_a = dfifo_out_data; // Complete MSB with 0s, if needed.
      assign last_idx         = idx == AXI_WORD_PER_INFO-1;
      assign idxD             = axi_data_vld && axi_data_rdy ? last_idx ? '0 : idx + 1 : idx;

      assign axi_data.wdata = dfifo_out_data_a[idx];
      assign axi_data.wstrb = '1;
      assign axi_data.wlast = last_idx;
      assign axi_data_vld   = st_data;
      assign send_data_done = axi_data_vld & axi_data_rdy & last_idx;

      always_ff @(posedge clk)
        if (!s_rst_n) idx <= '0;
        else          idx <= idxD;
    end
  endgenerate

  fifo_element #(
    .WIDTH          (AXI4_W_IF_W),
    .DEPTH          (1),
    .TYPE_ARRAY     (4'h3),
    .DO_RESET_DATA  (0),
    .RESET_DATA_VAL (0)
  ) data_fifo_element (
    .clk     (clk),
    .s_rst_n (s_rst_n),

    .in_data (axi_data),
    .in_vld  (axi_data_vld),
    .in_rdy  (axi_data_rdy),

    .out_data(m_axi4_data),
    .out_vld (m_axi4_wvalid),
    .out_rdy (m_axi4_wready)
  );

// ---------------------------------------------------------------------------------------------- --
// AXI Bresp
// ---------------------------------------------------------------------------------------------- --
  // Not used
  assign m_axi4_bready = 1'b1;

// ============================================================================================== --
// Error
// ============================================================================================== --
  logic errorD;

  assign errorD = error_fifo_ovf;

  always_ff @(posedge clk)
    if (!s_rst_n) error <= 1'b0;
    else          error <= errorD;

endmodule
