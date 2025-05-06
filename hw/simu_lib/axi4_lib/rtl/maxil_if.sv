// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Master AXI4-lite interface with associated driver function
// ----------------------------------------------------------------------------------------------
//
// Define Master AXI4-lite interface with a set of function to issues
// read/write.
// Should only be used for test purpose
//
// ==============================================================================================

interface maxil_if
#(
  parameter integer AXIL_DATA_W  = 32,
  parameter integer AXIL_ADD_W  = 10
  )(input rst_n, input clk);
// Interface signals {{{
logic [(AXIL_ADD_W-1): 0]      awaddr  ;
logic [2: 0]                   awprot  ;
logic                          awvalid ;
logic                          awready ;
logic [(AXIL_DATA_W-1): 0]     wdata   ;
logic [((AXIL_DATA_W/8)-1): 0] wstrb   ;
logic                          wvalid  ;
logic                          wready  ;
logic [1: 0]                   bresp   ;
logic                          bvalid  ;
logic                          bready  ;
logic [AXIL_ADD_W-1 : 0]       araddr  ;
logic [2: 0]                   arprot  ;
logic                          arvalid ;
logic                          arready ;
logic [AXIL_DATA_W-1 : 0]      rdata   ;
logic [1: 0]                   rresp   ;
logic                          rvalid  ;
logic                          rready  ;
// }}}

// Driver clocking block and modport {{{
clocking drv_cb@(posedge clk);
  default input #0 output #1;
    output awaddr;
    output awprot;
    output awvalid;
    input  awready;
    output wdata;
    output wstrb;
    output wvalid;
    input  wready;
    input  bresp;
    input  bvalid;
    output bready;
    output araddr;
    output arprot;
    output arvalid;
    input  arready;
    input  rdata;
    input  rresp;
    input  rvalid;
    output  rready;
endclocking
modport drv_mp( clocking drv_cb, input rst_n, input clk,
                import read_trans, write_trans);
// }}}

// Monitor clocking block and modport {{{
clocking mon_cb@(posedge clk);
  default input #1 output #0;
    input awaddr;
    input awprot;
    input awvalid;
    input awready;
    input wdata;
    input wstrb;
    input wvalid;
    input wready;
    input bresp;
    input bvalid;
    input bready;
    input araddr;
    input arprot;
    input arvalid;
    input arready;
    input rdata;
    input rresp;
    input rvalid;
    input rready;
endclocking
modport mon_mp( clocking mon_cb, input rst_n, input clk);
// }}}

task init;
begin
  arvalid <= '0; 
  rready  <= '0;
  awvalid <= '0;
  awaddr  <= '0;
  wstrb   <= '0;
  awprot  <= '0;
  wvalid  <= '0;
  bready  <= '0;
end
endtask

task read_trans; // {{{
// Execute a full read transaction
// NB: Currently this implementation doesn't support wrapped transaction
input bit [(AXIL_ADD_W-1):0]   addr;
output bit [(AXIL_DATA_W-1):0] data;

begin
  data = 'h0;
  fork
    begin // Drive addr read request {{{
      @(posedge clk);
      // Addr
      araddr  <= addr;
      arprot  <= 3'h0;
      arvalid <= 1'b1;
      // Wait slave arready
      // TODO: add a timeout to prevent simulation hanging
      do  @(posedge clk); while (!arready);
      araddr  <= 'h0;
      arprot  <= 3'h0;
      arvalid <= 1'b0;
    end // }}}

    begin // Drive response {{{
      @(posedge clk);
      rready <= 1'b1;
      do  @(posedge clk); while (!rvalid);
      data = rdata;
      if (rvalid == 1'b1 && rresp != 2'h0)
        begin
          $display("WARN: AXIL -> Received ERROR Read Response");
        end
      rready <= 1'b0;
    end // }}}
  join
end
endtask // }}}


task write_trans; // {{{
// Execute a full write transaction
// NB: Currently this implementation doesn't support wrapped transaction
input bit [(AXIL_ADD_W-1):0]  addr;
input bit [(AXIL_DATA_W-1):0] data;
begin
  fork
  begin // Drive addr write request {{{
    @(posedge clk);
    // Addr
    awaddr  <= addr;
    awprot  <= 3'h0;
    awvalid <= 1'b1;
    // Check slave awready
    // TODO add timeout to prevent simulation hanging
    do  @(posedge clk); while (!awready);
    awvalid <= 1'b0;
    awaddr  <= 'h0;
  end // }}}
  begin // Drive data write request {{{
    @(posedge clk);
    // Data
    wdata  <= data;
    wstrb  <= 4'hf;
    wvalid <= 1'b1;

    // TODO add timeout to prevent simulation hanging
    do  @(posedge clk); while (!wready);
    wdata   <= 32'h0;
    wstrb   <= 4'h0;
    wvalid  <= 1'b0;
  end // }}}
  begin // Drive response {{{
    bready <= 'b1;

    //wait for response
    // TODO add timeout to prevent simulation hanging
    do  @(posedge clk); while (!bvalid);
    if (bvalid == 1'b1 && bresp != 2'h0)
      $display("WARN: AXIL -> Received ERROR Write Response");
    bready <= 'b0;
    @(posedge clk);
  end // }}}
  join
end
endtask // }}}

endinterface : maxil_if
