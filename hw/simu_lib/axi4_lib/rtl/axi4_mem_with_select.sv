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
//
// Naively it's a axi4_mem with muxed interface to enable connection with multiple master.
// Only one master could be enabled at a time (based on the select entry)
// ==============================================================================================

module axi4_mem_with_select
#(
  // Number of slave interface
  parameter int SLAVE_IF = 2, // Should be >= 1
  localparam int SLAVE_IF_W = ($clog2(SLAVE_IF)>0)? $clog2(SLAVE_IF): 1,
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

    input  logic [SLAVE_IF-1: 0]                  s_axi4_select_1h,
    input  logic [SLAVE_IF-1: 0][ID_WIDTH-1:0]    s_axi4_awid,
    input  logic [SLAVE_IF-1: 0][ADDR_WIDTH-1:0]  s_axi4_awaddr,
    input  logic [SLAVE_IF-1: 0][7:0]             s_axi4_awlen,
    input  logic [SLAVE_IF-1: 0][2:0]             s_axi4_awsize,
    input  logic [SLAVE_IF-1: 0][1:0]             s_axi4_awburst,
    input  logic [SLAVE_IF-1: 0]                  s_axi4_awlock,
    input  logic [SLAVE_IF-1: 0][3:0]             s_axi4_awcache,
    input  logic [SLAVE_IF-1: 0][2:0]             s_axi4_awprot,
    input  logic [SLAVE_IF-1: 0][3:0]             s_axi4_awqos,
    input  logic [SLAVE_IF-1: 0][3:0]             s_axi4_awregion,
    input  logic [SLAVE_IF-1: 0]                  s_axi4_awvalid,
    output logic [SLAVE_IF-1: 0]                  s_axi4_awready,
    input  logic [SLAVE_IF-1: 0][DATA_WIDTH-1:0]  s_axi4_wdata,
    input  logic [SLAVE_IF-1: 0][STRB_WIDTH-1:0]  s_axi4_wstrb,
    input  logic [SLAVE_IF-1: 0]                  s_axi4_wlast,
    input  logic [SLAVE_IF-1: 0]                  s_axi4_wvalid,
    output logic [SLAVE_IF-1: 0]                  s_axi4_wready,
    output logic [SLAVE_IF-1: 0][ID_WIDTH-1:0]    s_axi4_bid,
    output logic [SLAVE_IF-1: 0][1:0]             s_axi4_bresp,
    output logic [SLAVE_IF-1: 0]                  s_axi4_bvalid,
    input  logic [SLAVE_IF-1: 0]                  s_axi4_bready,

    input  logic [SLAVE_IF-1: 0][ID_WIDTH-1:0]    s_axi4_arid,
    input  logic [SLAVE_IF-1: 0][ADDR_WIDTH-1:0]  s_axi4_araddr,
    input  logic [SLAVE_IF-1: 0][7:0]             s_axi4_arlen,
    input  logic [SLAVE_IF-1: 0][2:0]             s_axi4_arsize,
    input  logic [SLAVE_IF-1: 0][1:0]             s_axi4_arburst,
    input  logic [SLAVE_IF-1: 0]                  s_axi4_arlock,
    input  logic [SLAVE_IF-1: 0][3:0]             s_axi4_arcache,
    input  logic [SLAVE_IF-1: 0][2:0]             s_axi4_arprot,
    input  logic [SLAVE_IF-1: 0][3:0]             s_axi4_arqos,
    input  logic [SLAVE_IF-1: 0][3:0]             s_axi4_arregion,
    input  logic [SLAVE_IF-1: 0]                  s_axi4_arvalid,
    output logic [SLAVE_IF-1: 0]                  s_axi4_arready,
    output logic [SLAVE_IF-1: 0][ID_WIDTH-1:0]    s_axi4_rid,
    output logic [SLAVE_IF-1: 0][DATA_WIDTH-1:0]  s_axi4_rdata,
    output logic [SLAVE_IF-1: 0][1:0]             s_axi4_rresp,
    output logic [SLAVE_IF-1: 0]                  s_axi4_rlast,
    output logic [SLAVE_IF-1: 0]                  s_axi4_rvalid,
    input  logic [SLAVE_IF-1: 0]                  s_axi4_rready
);

// ============================================================================================== --
// Internal signal for muxing
// ============================================================================================== --
logic [ID_WIDTH-1:0]        axi4_awid;
logic [ADDR_WIDTH-1:0]      axi4_awaddr;
logic [7:0]                 axi4_awlen;
logic [2:0]                 axi4_awsize;
logic [1:0]                 axi4_awburst;
logic                       axi4_awlock;
logic [3:0]                 axi4_awcache;
logic [2:0]                 axi4_awprot;
logic [3:0]                 axi4_awqos;
logic [3:0]                 axi4_awregion;
logic                       axi4_awvalid;
logic                       axi4_awready;
logic [DATA_WIDTH-1:0]      axi4_wdata;
logic [STRB_WIDTH-1:0]      axi4_wstrb;
logic                       axi4_wlast;
logic                       axi4_wvalid;
logic                       axi4_wready;
logic [ID_WIDTH-1:0]        axi4_bid;
logic [1:0]                 axi4_bresp;
logic                       axi4_bvalid;
logic                       axi4_bready;

logic [ID_WIDTH-1:0]        axi4_arid;
logic [ADDR_WIDTH-1:0]      axi4_araddr;
logic [7:0]                 axi4_arlen;
logic [2:0]                 axi4_arsize;
logic [1:0]                 axi4_arburst;
logic                       axi4_arlock;
logic [3:0]                 axi4_arcache;
logic [2:0]                 axi4_arprot;
logic [3:0]                 axi4_arqos;
logic [3:0]                 axi4_arregion;
logic                       axi4_arvalid;
logic                       axi4_arready;
logic [ID_WIDTH-1:0]        axi4_rid;
logic [DATA_WIDTH-1:0]      axi4_rdata;
logic [1:0]                 axi4_rresp;
logic                       axi4_rlast;
logic                       axi4_rvalid;
logic                       axi4_rready;


// Axi memory inner component

axi4_mem #(
  .DATA_WIDTH(DATA_WIDTH),
  .ADDR_WIDTH(ADDR_WIDTH),
  .ID_WIDTH  (ID_WIDTH),
  .WR_CMD_BUF_DEPTH (WR_CMD_BUF_DEPTH),
  .RD_CMD_BUF_DEPTH (RD_CMD_BUF_DEPTH),
  .WR_DATA_LATENCY  (WR_DATA_LATENCY),
  .RD_DATA_LATENCY  (RD_DATA_LATENCY),
  .USE_WR_RANDOM    (USE_WR_RANDOM),
  .USE_RD_RANDOM    (USE_RD_RANDOM)
) axi4_mem_inner (
  .clk          (clk),
  .rst          (rst),

  .s_axi4_awid   (axi4_awid   ),
  .s_axi4_awaddr (axi4_awaddr ),
  .s_axi4_awlen  (axi4_awlen  ),
  .s_axi4_awsize (axi4_awsize ),
  .s_axi4_awburst(axi4_awburst),
  .s_axi4_awlock (axi4_awlock ),
  .s_axi4_awcache(axi4_awcache),
  .s_axi4_awprot (axi4_awprot ),
  .s_axi4_awqos  (axi4_awqos  ),
  .s_axi4_awregion (axi4_awregion),
  .s_axi4_awvalid(axi4_awvalid),
  .s_axi4_awready(axi4_awready),
  .s_axi4_wdata  (axi4_wdata  ),
  .s_axi4_wstrb  (axi4_wstrb  ),
  .s_axi4_wlast  (axi4_wlast  ),
  .s_axi4_wvalid (axi4_wvalid ),
  .s_axi4_wready (axi4_wready ),
  .s_axi4_bid    (axi4_bid    ),
  .s_axi4_bresp  (axi4_bresp  ),
  .s_axi4_bvalid (axi4_bvalid ),
  .s_axi4_bready (axi4_bready ),
  .s_axi4_arid   (axi4_arid   ),
  .s_axi4_araddr (axi4_araddr ),
  .s_axi4_arlen  (axi4_arlen  ),
  .s_axi4_arsize (axi4_arsize ),
  .s_axi4_arburst(axi4_arburst),
  .s_axi4_arlock (axi4_arlock ),
  .s_axi4_arcache(axi4_arcache),
  .s_axi4_arprot (axi4_arprot ),
  .s_axi4_arqos  (axi4_arqos  ),
  .s_axi4_arregion (axi4_arregion),
  .s_axi4_arvalid(axi4_arvalid),
  .s_axi4_arready(axi4_arready),
  .s_axi4_rid    (axi4_rid    ),
  .s_axi4_rdata  (axi4_rdata  ),
  .s_axi4_rresp  (axi4_rresp  ),
  .s_axi4_rlast  (axi4_rlast  ),
  .s_axi4_rvalid (axi4_rvalid ),
  .s_axi4_rready (axi4_rready )
);

// Select is one-hot encoded
logic [SLAVE_IF_W-1:0] axi4_select;
  common_lib_one_hot_to_bin #(
    .ONE_HOT_W (SLAVE_IF)
  ) axi4_select_htb (
    .in_1h     (s_axi4_select_1h),
    .out_value (axi4_select)
  );

// Muxing based on s_axi4_select
assign axi4_awid    = s_axi4_awid   [axi4_select];
assign axi4_awaddr  = s_axi4_awaddr [axi4_select];
assign axi4_awlen   = s_axi4_awlen  [axi4_select];
assign axi4_awsize  = s_axi4_awsize [axi4_select];
assign axi4_awburst = s_axi4_awburst[axi4_select];
assign axi4_awvalid = s_axi4_awvalid[axi4_select];
assign axi4_wdata   = s_axi4_wdata  [axi4_select];
assign axi4_wstrb   = s_axi4_wstrb  [axi4_select];
assign axi4_wlast   = s_axi4_wlast  [axi4_select];
assign axi4_wvalid  = s_axi4_wvalid [axi4_select];
assign axi4_bready  = s_axi4_bready [axi4_select];

assign axi4_awlock  = s_axi4_awlock [axi4_select];
assign axi4_awcache = s_axi4_awcache[axi4_select];
assign axi4_awprot  = s_axi4_awprot [axi4_select];
assign axi4_awqos   = s_axi4_awqos  [axi4_select];
assign axi4_awregion= s_axi4_awregion [axi4_select];

assign axi4_arid    = s_axi4_arid    [axi4_select];
assign axi4_araddr  = s_axi4_araddr  [axi4_select];
assign axi4_arlen   = s_axi4_arlen   [axi4_select];
assign axi4_arsize  = s_axi4_arsize  [axi4_select];
assign axi4_arburst = s_axi4_arburst [axi4_select];
assign axi4_arvalid = s_axi4_arvalid [axi4_select];
assign axi4_rready  = s_axi4_rready  [axi4_select];

assign axi4_arlock  = s_axi4_arlock [axi4_select];
assign axi4_arcache = s_axi4_arcache[axi4_select];
assign axi4_arprot  = s_axi4_arprot [axi4_select];
assign axi4_arqos   = s_axi4_arqos  [axi4_select];
assign axi4_arregion= s_axi4_arregion [axi4_select];

// Tie unselect interface to 0
generate
  for (genvar gen_p=0; gen_p<SLAVE_IF; gen_p=gen_p+1) begin

  assign s_axi4_awready [gen_p] = (axi4_select == gen_p)? axi4_awready :'0;
  assign s_axi4_wready  [gen_p] = (axi4_select == gen_p)? axi4_wready  :'0;
  assign s_axi4_bid     [gen_p] = (axi4_select == gen_p)? axi4_bid     :'0;
  assign s_axi4_bresp   [gen_p] = (axi4_select == gen_p)? axi4_bresp   :'0;
  assign s_axi4_bvalid  [gen_p] = (axi4_select == gen_p)? axi4_bvalid  :'0;

  assign s_axi4_arready [gen_p] = (axi4_select == gen_p)? axi4_arready :'0;
  assign s_axi4_rid     [gen_p] = (axi4_select == gen_p)? axi4_rid     :'0;
  assign s_axi4_rdata   [gen_p] = (axi4_select == gen_p)? axi4_rdata   :'0;
  assign s_axi4_rresp   [gen_p] = (axi4_select == gen_p)? axi4_rresp   :'0;
  assign s_axi4_rlast   [gen_p] = (axi4_select == gen_p)? axi4_rlast   :'0;
  assign s_axi4_rvalid  [gen_p] = (axi4_select == gen_p)? axi4_rvalid  :'0;
  end
endgenerate

endmodule
