// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module should be used in simulation only.
// It modelizes a memory, with an AXI interface.
// A command buffer is implemented.
// Data read are delayed.
// ==============================================================================================

module axi4_mem
#(
  // Width of data bus in bits
  parameter int DATA_WIDTH = 32,
  // Width of address bus in bits
  parameter int ADDR_WIDTH = 16,
  // Width of wstrb (width of data bus in words)
  parameter int STRB_WIDTH = (DATA_WIDTH/8),
  // Width of ID signal
  parameter int ID_WIDTH = 8,
  // Command buffer depth
  parameter int WR_CMD_BUF_DEPTH = 8, // Should be >= 1
  parameter int RD_CMD_BUF_DEPTH = 8, // Should be >= 1
  // Data latency
  parameter int WR_DATA_LATENCY = 4, // Should be >= 1
  parameter int RD_DATA_LATENCY = 4, // Should be >= 1
  // Set random on ready valid, on write path
  parameter bit USE_WR_RANDOM = 1,
  // Set random on ready valid, on read path
  parameter bit USE_RD_RANDOM = 1
)
(
    input  logic                   clk,
    input  logic                   rst,

    input  logic [ID_WIDTH-1:0]    s_axi4_awid,
    input  logic [ADDR_WIDTH-1:0]  s_axi4_awaddr,
    input  logic [7:0]             s_axi4_awlen,
    input  logic [2:0]             s_axi4_awsize,
    input  logic [1:0]             s_axi4_awburst,
    input  logic                   s_axi4_awlock,
    input  logic [3:0]             s_axi4_awcache,
    input  logic [2:0]             s_axi4_awprot,
    input  logic [3:0]             s_axi4_awqos,   /*UNUSED*/
    input  logic [3:0]             s_axi4_awregion,/*UNUSED*/
    input  logic                   s_axi4_awvalid,
    output logic                   s_axi4_awready,
    input  logic [DATA_WIDTH-1:0]  s_axi4_wdata,
    input  logic [STRB_WIDTH-1:0]  s_axi4_wstrb,
    input  logic                   s_axi4_wlast,
    input  logic                   s_axi4_wvalid,
    output logic                   s_axi4_wready,
    output logic [ID_WIDTH-1:0]    s_axi4_bid,
    output logic [1:0]             s_axi4_bresp,
    output logic                   s_axi4_bvalid,
    input  logic                   s_axi4_bready,

    input  logic [ID_WIDTH-1:0]    s_axi4_arid,
    input  logic [ADDR_WIDTH-1:0]  s_axi4_araddr,
    input  logic [7:0]             s_axi4_arlen,
    input  logic [2:0]             s_axi4_arsize,
    input  logic [1:0]             s_axi4_arburst,
    input  logic                   s_axi4_arlock,
    input  logic [3:0]             s_axi4_arcache,
    input  logic [2:0]             s_axi4_arprot,
    input  logic [3:0]             s_axi4_arqos,   /*UNUSED*/
    input  logic [3:0]             s_axi4_arregion,/*UNUSED*/
    input  logic                   s_axi4_arvalid,
    output logic                   s_axi4_arready,
    output logic [ID_WIDTH-1:0]    s_axi4_rid,
    output logic [DATA_WIDTH-1:0]  s_axi4_rdata,
    output logic [1:0]             s_axi4_rresp,
    output logic                   s_axi4_rlast,
    output logic                   s_axi4_rvalid,
    input  logic                   s_axi4_rready
);
// ============================================================================================== //
// Types
// ============================================================================================== //
  typedef struct packed {
    logic [ID_WIDTH-1:0]  arid;
    logic [ADDR_WIDTH-1:0] araddr;
    logic [7:0]            arlen;
    logic [2:0]            arsize;
    logic [1:0]            arburst;
  } axi4_ar_if_t;


  typedef struct packed {
    logic [ID_WIDTH-1:0]   rid;
    logic [DATA_WIDTH-1:0] rdata;
    logic [1:0]             rresp;
    logic                   rlast;
  } axi4_r_if_t;


  typedef struct packed {
    logic [ID_WIDTH-1:0]   awid;
    logic [ADDR_WIDTH-1:0]  awaddr;
    logic [7:0]             awlen;
    logic [2:0]             awsize;
    logic [1:0]             awburst;
  } axi4_aw_if_t;


  typedef struct packed {
    logic [DATA_WIDTH-1:0]     wdata;
    logic [(DATA_WIDTH/8)-1:0] wstrb;
    logic                       wlast;
  } axi4_w_if_t;


  typedef struct packed {
    logic [ID_WIDTH-1:0] bid;
    logic [1:0]           bresp;
  } axi4_b_if_t;

// ============================================================================================== //
// Signals
// ============================================================================================== //
  axi4_aw_if_t s_axi4_aw;
  axi4_w_if_t  s_axi4_w;
  axi4_b_if_t  s_axi4_b;

  axi4_ar_if_t s_axi4_ar;
  axi4_r_if_t  s_axi4_r;

  axi4_aw_if_t axi4_aw;
  logic        axi4_awvalid;
  logic        axi4_awready;
  axi4_w_if_t  axi4_w;
  logic        axi4_wvalid;
  logic        axi4_wready;
  axi4_b_if_t  axi4_b;
  logic        axi4_bvalid;
  logic        axi4_bready;

  axi4_ar_if_t axi4_ar;
  logic        axi4_arvalid;
  logic        axi4_arready;
  axi4_r_if_t  axi4_r;
  logic        axi4_rvalid;
  logic        axi4_rready;

// ============================================================================================== //
// Rename
// ============================================================================================== //
  assign s_axi4_aw.awid    = s_axi4_awid;
  assign s_axi4_aw.awaddr  = s_axi4_awaddr;
  assign s_axi4_aw.awlen   = s_axi4_awlen;
  assign s_axi4_aw.awsize  = s_axi4_awsize;
  assign s_axi4_aw.awburst = s_axi4_awburst;

  assign s_axi4_w.wdata    = s_axi4_wdata;
  assign s_axi4_w.wstrb    = s_axi4_wstrb;
  assign s_axi4_w.wlast    = s_axi4_wlast;

  assign s_axi4_bid        = s_axi4_b.bid;
  assign s_axi4_bresp      = s_axi4_b.bresp;

  assign s_axi4_ar.arid    = s_axi4_arid;
  assign s_axi4_ar.araddr  = s_axi4_araddr;
  assign s_axi4_ar.arlen   = s_axi4_arlen;
  assign s_axi4_ar.arsize  = s_axi4_arsize;
  assign s_axi4_ar.arburst = s_axi4_arburst;

  assign s_axi4_rid        = s_axi4_r.rid;
  assign s_axi4_rdata      = s_axi4_r.rdata;
  assign s_axi4_rresp      = s_axi4_r.rresp;
  assign s_axi4_rlast      = s_axi4_r.rlast;

// ============================================================================================== //
// RAM instance
// ============================================================================================== //
  axi4_ram #(
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH),
    .ID_WIDTH  (ID_WIDTH),
    .STRB_WIDTH(STRB_WIDTH)
  ) axi4_ram_ct_wr
  (
    .clk(clk),
    .rst(rst),

    .s_axi4_awid(axi4_aw.awid),
    .s_axi4_awaddr(axi4_aw.awaddr),
    .s_axi4_awlen(axi4_aw.awlen),
    .s_axi4_awsize(axi4_aw.awsize),
    .s_axi4_awburst(axi4_aw.awburst),
    .s_axi4_awlock(s_axi4_awlock),  // disable
    .s_axi4_awcache(s_axi4_awcache), // disable
    .s_axi4_awprot(s_axi4_awprot),  // disable
    .s_axi4_awvalid(axi4_awvalid),
    .s_axi4_awready(axi4_awready),
    .s_axi4_wdata(axi4_w.wdata),
    .s_axi4_wstrb(axi4_w.wstrb),
    .s_axi4_wlast(axi4_w.wlast),
    .s_axi4_wvalid(axi4_wvalid),
    .s_axi4_wready(axi4_wready),
    .s_axi4_bid(axi4_b.bid),
    .s_axi4_bresp(axi4_b.bresp),
    .s_axi4_bvalid(axi4_bvalid),
    .s_axi4_bready(axi4_bready),

    .s_axi4_arid(axi4_ar.arid),
    .s_axi4_araddr(axi4_ar.araddr),
    .s_axi4_arlen(axi4_ar.arlen),
    .s_axi4_arsize(axi4_ar.arsize),
    .s_axi4_arburst(axi4_ar.arburst),
    .s_axi4_arlock(s_axi4_arlock), // disable
    .s_axi4_arcache(s_axi4_arcache), // disable
    .s_axi4_arprot(s_axi4_arprot), // disable
    .s_axi4_arvalid(axi4_arvalid),
    .s_axi4_arready(axi4_arready),
    .s_axi4_rid(axi4_r.rid),
    .s_axi4_rdata(axi4_r.rdata),
    .s_axi4_rresp(axi4_r.rresp),
    .s_axi4_rlast(axi4_r.rlast),
    .s_axi4_rvalid(axi4_rvalid),
    .s_axi4_rready(axi4_rready)
  );

// ============================================================================================== //
// Input command buffer
// ============================================================================================== //
  logic axi4_awvalid_tmp;
  logic axi4_awready_tmp;

  fifo_element #(
    .WIDTH          ($bits(axi4_aw_if_t)),
    .DEPTH          (WR_CMD_BUF_DEPTH),
    .TYPE_ARRAY     ({WR_CMD_BUF_DEPTH{4'h1}}),
    .DO_RESET_DATA  (1'b1),
    .RESET_DATA_VAL (0)
  ) aw_fifo_element (
    .clk     (clk),
    .s_rst_n (!rst),

    .in_data (s_axi4_aw),
    .in_vld  (s_axi4_awvalid),
    .in_rdy  (s_axi4_awready),

    .out_data(axi4_aw),
    .out_vld (axi4_awvalid_tmp),
    .out_rdy (axi4_awready_tmp)
  );

  logic axi4_arvalid_tmp;
  logic axi4_arready_tmp;

  fifo_element #(
    .WIDTH          ($bits(axi4_ar_if_t)),
    .DEPTH          (RD_CMD_BUF_DEPTH),
    .TYPE_ARRAY     ({RD_CMD_BUF_DEPTH{4'h1}}),
    .DO_RESET_DATA  (1'b1),
    .RESET_DATA_VAL (0)
  ) ar_fifo_element (
    .clk     (clk),
    .s_rst_n (!rst),

    .in_data (s_axi4_ar),
    .in_vld  (s_axi4_arvalid),
    .in_rdy  (s_axi4_arready),

    .out_data(axi4_ar),
    .out_vld (axi4_arvalid_tmp),
    .out_rdy (axi4_arready_tmp)
  );

// ============================================================================================== //
// Data delay
// ============================================================================================== //
  logic s_axi4_rvalid_tmp;
  logic s_axi4_rready_tmp;

  fifo_element #(
    .WIDTH          ($bits(axi4_r_if_t)),
    .DEPTH          (RD_DATA_LATENCY),
    .TYPE_ARRAY     ({RD_DATA_LATENCY{4'h1}}),
    .DO_RESET_DATA  (1'b0),
    .RESET_DATA_VAL (0)
  ) r_fifo_element (
    .clk     (clk),
    .s_rst_n (!rst),

    .in_data (axi4_r),
    .in_vld  (axi4_rvalid),
    .in_rdy  (axi4_rready),

    .out_data(s_axi4_r),
    .out_vld (s_axi4_rvalid_tmp),
    .out_rdy (s_axi4_rready_tmp)
  );

  logic s_axi4_bvalid_tmp;
  logic s_axi4_bready_tmp;

  fifo_element #(
    .WIDTH          ($bits(axi4_b_if_t)),
    .DEPTH          (WR_DATA_LATENCY),
    .TYPE_ARRAY     ({WR_DATA_LATENCY{4'h1}}),
    .DO_RESET_DATA  (1'b0),
    .RESET_DATA_VAL (0)
  ) b_fifo_element (
    .clk     (clk),
    .s_rst_n (!rst),

    .in_data (axi4_b),
    .in_vld  (axi4_bvalid),
    .in_rdy  (axi4_bready),

    .out_data(s_axi4_b),
    .out_vld (s_axi4_bvalid_tmp),
    .out_rdy (s_axi4_bready_tmp)
  );

  assign axi4_w = s_axi4_w;

// ============================================================================================== //
// Random
// ============================================================================================== //
  generate
    if (USE_WR_RANDOM) begin : gen_rand_wr
      // Set some randomness on the data rdy vld path
      // Valid is maintained until ready is seen => avoid SVA assertion
      // [2] wdata
      // [1] bresp
      // [0] wcmd
      localparam [2:0][31:0] RAND_RANGE = {32'd8,32'd8,32'd16};
      logic [2:0] rand_val;
      logic [2:0] rand_mask;
      logic [2:0] rand_maskD;
      logic [2:0] sampling;

      always_ff @(posedge clk)
        rand_val <= $urandom();

      assign sampling[0] = axi4_awvalid & axi4_awready;
      assign sampling[1] = s_axi4_bvalid & s_axi4_bready;
      assign sampling[2] = s_axi4_wvalid & s_axi4_wready;

      for (genvar gen_i=0; gen_i<3; gen_i=gen_i+1) begin : gen_rand_wr_loop
        integer cnt_0;
        integer cnt_0D;
        integer cnt_1;
        integer cnt_1D;

        integer delayed_event_cnt;
        integer delayed_event_cntD;

        integer rand_cnt;

        logic delayed_event_cnt_reached;
        logic consecutiv_event_cnt_reached;
        logic mask_upd;

        assign delayed_event_cnt_reached    = delayed_event_cnt > 2;
        assign consecutiv_event_cnt_reached = cnt_1 > 16;
        assign mask_upd = (sampling[gen_i] & consecutiv_event_cnt_reached) | (~rand_mask[gen_i] & (cnt_0 == 0));

        always_ff @(posedge clk)
          rand_cnt <= $urandom_range(1,RAND_RANGE[gen_i]);

        assign cnt_1D = !rand_mask[gen_i] ? 0 :
                        cnt_1 != '1 ? cnt_1 + 1 : cnt_1;

        assign cnt_0D = cnt_0 > 0 ? cnt_0 - 1 :
                        !rand_mask[gen_i] ? rand_cnt : cnt_0;
        // delayed_event_cnt counts the number of times the rand_mask has delayed an event on a valid or ready
        // we want to limit the number of times an event can be delayed to prevent extremely large delays
        assign rand_maskD[gen_i] = mask_upd ?
                                    ( rand_val[gen_i] || delayed_event_cnt_reached)
                                    : rand_mask[gen_i] ;

        assign delayed_event_cntD = mask_upd ?
                                      ( (rand_val[gen_i] || delayed_event_cnt_reached) ? 0 : delayed_event_cnt + 1 )
                                      : delayed_event_cnt;

        always_ff @(posedge clk)
          if (rst)  begin
            cnt_0 <= '0;
            cnt_1 <= '0;
          end
          else begin
            cnt_0 <= cnt_0D;
            cnt_1 <= cnt_1D;
          end

        always_ff @(posedge clk)
          if (rst)  delayed_event_cnt <= '0;
          else      delayed_event_cnt <= delayed_event_cntD;
      end

      always_ff @(posedge clk)
        if (rst) rand_mask <= '0;
        else     rand_mask <= rand_maskD;

      assign axi4_awvalid      = axi4_awvalid_tmp & rand_mask[0];
      assign axi4_awready_tmp  = axi4_awready & rand_mask[0];

      assign s_axi4_bvalid     = s_axi4_bvalid_tmp & rand_mask[1];
      assign s_axi4_bready_tmp = s_axi4_bready & rand_mask[1];

      assign axi4_wvalid       = s_axi4_wvalid & rand_mask[2];
      assign s_axi4_wready     = axi4_wready & rand_mask[2];

    end
    else begin : gen_no_rand_wr

      assign axi4_awvalid      = axi4_awvalid_tmp;
      assign axi4_awready_tmp  = axi4_awready;

      assign s_axi4_bvalid     = s_axi4_bvalid_tmp;
      assign s_axi4_bready_tmp = s_axi4_bready;

      assign axi4_wvalid       = s_axi4_wvalid;
      assign s_axi4_wready     = axi4_wready;

    end

    if (USE_RD_RANDOM) begin : gen_rand_rd
      // Set some randomness on the data rdy vld path
      // Valid is maintained until ready is seen => avoid SVA assertion
      logic [1:0] rand_val;
      logic [1:0] rand_mask;
      logic [1:0] rand_maskD;
      logic [1:0] sampling;

      always_ff @(posedge clk)
        rand_val <= $urandom();

      assign sampling[0] = axi4_arvalid & axi4_arready;
      assign sampling[1] = s_axi4_rvalid & s_axi4_rready;

      for (genvar gen_i=0; gen_i<2; gen_i=gen_i+1) begin : gen_rand_rd_loop
        integer cnt_0;
        integer cnt_0D;
        integer cnt_1;
        integer cnt_1D;

        integer delayed_event_cnt;
        integer delayed_event_cntD;

        integer rand_cnt;

        logic delayed_event_cnt_reached;
        logic consecutiv_event_cnt_reached;
        logic mask_upd;

        assign delayed_event_cnt_reached = delayed_event_cnt > 2;
        assign consecutiv_event_cnt_reached = cnt_1 > 16;
        assign mask_upd = (sampling[gen_i] & consecutiv_event_cnt_reached) | (~rand_mask[gen_i] & (cnt_0 == 0));

        always_ff @(posedge clk)
          rand_cnt <= $urandom_range(1,8);

        assign cnt_1D = !rand_mask[gen_i] ? 0 :
                        cnt_1 != '1 ? cnt_1 + 1 : cnt_1;

        assign cnt_0D = cnt_0 > 0 ? cnt_0 - 1 :
                        !rand_mask[gen_i] ? rand_cnt : cnt_0;
        // delayed_event_cnt counts the number of times the rand_mask has delayed an event on a valid or ready
        // we want to limit the number of times an event can be delayed to prevent extremely large delays
        assign rand_maskD[gen_i] = mask_upd ?
                                    (rand_val[gen_i] || delayed_event_cnt_reached)
                                    : rand_mask[gen_i] ;

        assign delayed_event_cntD = mask_upd ?
                                      ( (rand_val[gen_i] || delayed_event_cnt_reached) ? 0 : delayed_event_cnt + 1 )
                                      : delayed_event_cnt;

        always_ff @(posedge clk)
          if (rst)  begin
            cnt_0 <= '0;
            cnt_1 <= '0;
          end
          else begin
            cnt_0 <= cnt_0D;
            cnt_1 <= cnt_1D;
          end

        always_ff @(posedge clk)
          if (rst)  delayed_event_cnt <= '0;
          else      delayed_event_cnt <= delayed_event_cntD;
      end

      always_ff @(posedge clk)
        if (rst) rand_mask <= '0;
        else     rand_mask <= rand_maskD;

      assign axi4_arvalid      = axi4_arvalid_tmp & rand_mask[0];
      assign axi4_arready_tmp  = axi4_arready & rand_mask[0];

      assign s_axi4_rvalid     = s_axi4_rvalid_tmp & rand_mask[1];
      assign s_axi4_rready_tmp = s_axi4_rready & rand_mask[1];

    end
    else begin : gen_no_rand_rd

      assign axi4_arvalid      = axi4_arvalid_tmp;
      assign axi4_arready_tmp  = axi4_arready;

      assign s_axi4_rvalid     = s_axi4_rvalid_tmp;
      assign s_axi4_rready_tmp = s_axi4_rready;

    end

  endgenerate

endmodule
