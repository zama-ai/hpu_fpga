// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Master AXI4 interface with associated driver function
// ----------------------------------------------------------------------------------------------
//
// Define Master AXI4 interface with a set of function to issues read/write.
// Should only be used for test purpose
//
// ==============================================================================================

interface maxi4_if
  #(
    parameter integer  AXI4_DATA_W  = 32,
    parameter integer  AXI4_ADD_W  = 10,
    parameter integer  AXI4_ID_W = 8,
    localparam integer AXI4_DATA_BYTES = AXI4_DATA_W/8,
    localparam integer AXI4_LEN_MAX_TMP = 4096/ AXI4_DATA_BYTES,
    localparam integer AXI4_LEN_MAX = (AXI4_LEN_MAX_TMP < 256)? (AXI4_LEN_MAX_TMP-1): 255,
    localparam int AXI4_DATA_BYTES_W = $clog2(AXI4_DATA_BYTES)
    )(input rst_n, input clk);
    // Interface signals {{{
    // Write channel
    logic [AXI4_ID_W-1:0]       awid    ;
    logic [AXI4_ADD_W-1:0]      awaddr  ;
    logic [7:0]                 awlen   ;
    logic [2:0]                 awsize  ;
    logic [1:0]                 awburst ;
    logic                       awvalid ;
    logic                       awready ;
    logic [AXI4_DATA_W-1:0]     wdata   ;
    logic [(AXI4_DATA_W/8)-1:0] wstrb   ;
    logic                       wlast   ;
    logic                       wvalid  ;
    logic                       wready  ;
    logic [AXI4_ID_W-1:0]       bid     ;
    logic [1:0]                 bresp   ;
    logic                       bvalid  ;
    logic                       bready  ;
    // Read channel
    logic [AXI4_ID_W-1:0]   arid    ;
    logic [AXI4_ADD_W-1:0]  araddr  ;
    logic [7:0]             arlen   ;
    logic [2:0]             arsize  ;
    logic [1:0]             arburst ;
    logic                   arvalid ;
    logic                   arready ;
    logic [AXI4_ID_W-1:0]   rid     ;
    logic [AXI4_DATA_W-1:0] rdata   ;
    logic [1:0]             rresp   ;
    logic                   rlast   ;
    logic                   rvalid  ;
    logic                   rready  ;
    // }}}
  // }}}

  // Driver clocking block and modport {{{
  clocking drv_cb@(posedge clk);
    default input #0 output #1;
      // Write channel {{{
      output awid;
      output awaddr;
      output awlen;
      output awsize;
      output awburst;
      output awvalid;
      input  awready;
      output wdata;
      output wstrb;
      output wlast;
      output wvalid;
      input  wready;
      input  bid;
      input  bresp;
      input  bvalid;
      output bready; // }}}
      // Read channel {{{
      output arid;
      output araddr;
      output arlen;
      output arsize;
      output arburst;
      output arvalid;
      input  arready;
      input  rid;
      input  rdata;
      input  rresp;
      input  rlast;
      input  rvalid;
      output rready;// }}}
  endclocking
  modport drv_mp( clocking drv_cb, input rst_n, input clk,
                  import read_burst, write_burst, read_trans, write_trans);
  // }}}

  // Monitor clocking block and modport {{{
  clocking mon_cb@(posedge clk);
    default input #1 output #0;
      // Write channel {{{
      input  awid;
      input  awaddr;
      input  awlen;
      input  awsize;
      input  awburst;
      input  awvalid;
      input  awready;
      input  wdata;
      input  wstrb;
      input  wlast;
      input  wvalid;
      input  wready;
      input  bid;
      input  bresp;
      input  bvalid;
      input  bready; // }}}
      // Read channel {{{
      input  arid;
      input  araddr;
      input  arlen;
      input  arsize;
      input  arburst;
      input  arvalid;
      input  arready;
      input  rid;
      input  rdata;
      input  rresp;
      input  rlast;
      input  rvalid;
      input  rready;// }}}
  endclocking
  modport mon_mp( clocking mon_cb, input rst_n, input clk);
  // }}}

task init;
begin
  arvalid <= '0; 
  rready  <= '0;
  awvalid <= '0;
  wvalid  <= '0;
  bready  <= '0;
end
endtask

task read_burst; /// {{{
  input logic [AXI4_ADD_W-1: 0] addr;
  input integer len;
  output logic [AXI4_DATA_W-1: 0] data[$:AXI4_LEN_MAX+1];
begin
    data = {};

    if ((0 == len) || (AXI4_LEN_MAX+1 < len)) begin
      $display("WARN: Invalid read request length %d -> ]%d, %d]", len, 0, AXI4_LEN_MAX+1);
      return;
    end

    // Static configuration
    // NB: only support one outstanding request with incr burst and fixed
    // arsize tight to bus width
    arid    <= 'h1;
    arsize  <= AXI4_DATA_BYTES_W;
    arburst <= 2'b01;

    fork
    begin // Drive addr read request {{{
      @(posedge clk);
      // Addr
      araddr  <= addr;
      arlen   <= len-1;
      arvalid <= 1'b1;
      // Wait slave arready
      // TODO: add a timeout to prevent simulation hanging
      do  @(posedge clk); while (!arready);
      araddr  <= '0;
      arlen   <= '0;
      arvalid <= 1'b0;
    end // }}}
    begin // wait response {{{
      do begin
        rready <= 1'b1;
        do  @(posedge clk); while (!rvalid);
        data[$+1] = rdata;
      end while (!rlast);
      rready <= 1'b0;

      // Check read status
      if (rvalid == 1'b1 && rlast && rresp != 2'h0)
      begin
        $display("WARN: AXI4 -> Received ERROR Read Response");
      end
    end // }}}
    join
end
endtask // }}}

task read_trans; /// {{{
  // Read transaction with no len restriction
  input logic [AXI4_ADD_W-1: 0] addr;
  input integer len;
  output logic [AXI4_DATA_W-1: 0] data[$];
begin
  automatic integer rmn_word = len;
  automatic integer cur_addr = addr;
  automatic logic [AXI4_DATA_W-1: 0] data_tmp[$];
  automatic integer burst_len;

  // Clean data content
  data = {};

  while (rmn_word > 0) begin
    burst_len = ((AXI4_LEN_MAX+1) < rmn_word)? (AXI4_LEN_MAX+1): rmn_word;
    data_tmp = {};
    read_burst(cur_addr, burst_len, data_tmp);
    data = {data, data_tmp};

    rmn_word -= burst_len;
    cur_addr += burst_len * (1 << AXI4_DATA_BYTES_W);
  end

  return;
end
endtask // }}}


task write_burst; /// {{{
  input logic [AXI4_ADD_W-1: 0] addr;
  input logic [AXI4_DATA_W-1: 0] data[$:AXI4_LEN_MAX+1];
begin
    // Early exit in case of invalid request len
    if ((0 == data.size()) || (AXI4_LEN_MAX+1 < data.size())) begin
      $display("WARN: Invalid write request length %d -> ]%d, %d]", data.size(), 0, AXI4_LEN_MAX+1);
      return;
    end

    // Static configuration
    // NB: only support one outstanding request with incr burst and fixed
    // arsize tight to bus width
    awid    <= 'h1;
    awsize  <= AXI4_DATA_BYTES_W;
    awburst <= 2'b01;

    fork
    begin // Drive addr write request {{{
      @(posedge clk);
      // Addr
      awaddr  <= addr;
      awlen   <= data.size() -1;
      awvalid <= 1'b1;
      // Wait addr handshake
      // TODO add timeout to prevent simulation hanging
      do @(posedge clk); while (!awready);
      awvalid <= 1'b0;
      awlen   <= '0;
      awaddr  <= '0;
    end // }}}
    begin // Drive data write request {{{
      @(posedge clk);
      foreach (data[i]) begin
        wdata  <= data[i];
        wstrb  <= '1;
        wvalid <= 1'b1;
        if (i == data.size()-1) begin
          wlast = 1'b1;
        end else begin
          wlast = 1'b0;
        end
        do @(posedge clk); while (!wready);
      end
      wdata   <= '0;
      wstrb   <= '0;
      wvalid  <= 1'b0;
      wlast   <= 1'b0;
    end // }}}
    begin // Drive response {{{
      bready <= 1'b1;

      //wait for response
      // TODO add timeout to prevent simulation hanging
      do @(posedge clk); while (!bvalid);
      if (bvalid == 1'b1 && bresp != 2'h0)
        $display("WARN: AXI4 -> Received ERROR Write Response");
      bready <= 1'b0;
      @(posedge clk);
    end // }}}
    join
end
endtask // }}}

// TODO check burst length and semantic of queue slicing (inclusive with last
// bound ?)
task write_trans; /// {{{
  // Write transaction with no len restriction
  input logic [AXI4_ADD_W-1: 0] addr;
  input logic [AXI4_DATA_W-1: 0] data[$];
begin
  automatic logic [AXI4_DATA_W-1: 0] rmn_data[$] = data;
  automatic integer cur_addr = addr;

  while (rmn_data.size() > 0) begin
    integer burst_len;
    burst_len = ((AXI4_LEN_MAX+1) < rmn_data.size())? (AXI4_LEN_MAX+1): rmn_data.size();
    write_burst(cur_addr, rmn_data[0:burst_len-1]);

    rmn_data = rmn_data[burst_len: $];
    cur_addr += burst_len * (1 << AXI4_DATA_BYTES_W);
  end
  return;
end
endtask // }}}
endinterface : maxi4_if
