// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : AXI4-stream interface with associated driver function
// ----------------------------------------------------------------------------------------------
//
// Define AXI4-stream interface with a set of function to push/pop value in the stream
// Should only be used for test purpose
// NB: Simplified version that doesn't handles STRB/KEEP and Routing signals
//
// Parameters : AXIS_DATA_W size of data bus (default 32)
//
// Prerequisites : None
//
// ----------------------------------------------------------------------------------------------
// NB: Modport isn't used in assignment analysis.
// Duplicate the interface to have drv/ep implementation.
// In a real verification env, interface must be define only once and the logic must go in the driver and the monitory
// (Not in the interface itself)
// ==============================================================================================

interface axis_drv_if
#(
  parameter integer AXIS_DATA_W  = 32
  )(input rst_n, input clk);
// Interface signals {{{
  logic [(AXIS_DATA_W-1):0] tdata;
  logic                     tlast;
  logic                     tready;
  logic                     tvalid;
// }}}

// Driver clocking block and modport {{{
clocking drv_cb@(posedge clk);
  default input #0 output #1;
    output tdata;
    output tlast;
    input  tready;
    output tvalid;
endclocking
modport drv_mp( clocking drv_cb, input rst_n, input clk,
                import push, push_trans);
// }}}

task init; // {{{
begin
  tdata = '0;
  tlast = '0;
  tvalid = '0;
end
endtask // }}}

task push; // {{{
// Push a single word in the stream
input bit [(AXIS_DATA_W-1):0]   data;
input bit is_last;

begin
  tdata = data;
  tlast = is_last;
  tvalid = 1'b1;

  do @(posedge clk); while (!tready);
  tdata = 'h0;
  tlast = 1'b0;
  tvalid = 1'b0;
end
endtask // }}}

task push_trans; // {{{
// push full content of the queue
input bit [(AXIS_DATA_W-1):0]   data_q[$];

begin
  for (int i=0; i< (data_q.size()-1); i++) begin
    push(data_q[i], 1'b0);
  end
  push(data_q[$], 1'b1);
end
endtask // }}}
endinterface : axis_drv_if

interface axis_ep_if
#(
  parameter integer AXIS_DATA_W  = 32
  )(input rst_n, input clk);
// Interface signals {{{
  logic [(AXIS_DATA_W-1):0] tdata;
  logic                     tlast;
  logic                     tready;
  logic                     tvalid;
// }}}

// Endpoint clocking block and modport {{{
clocking ep_cb@(posedge clk);
  default input #1 output #0;
    input tdata;
    input tlast;
    output tready;
    input tvalid;
endclocking
modport ep_mp( clocking ep_cb, input rst_n, input clk,
                import pop, pop_trans);
// }}}

task init; // {{{
begin
  tready = '0;
end
endtask // }}}

task pop; // {{{
// Pop a single word from the stream
output bit [(AXIS_DATA_W-1):0]   data;
output bit is_last;

begin
  tready = 1'b1;
  do @(posedge clk); while (!tvalid);
  data = tdata;
  is_last = tlast;
  tready = 1'b0;
end
endtask // }}}

task pop_trans; // {{{
// pop a full trans content in a queue
output bit [(AXIS_DATA_W-1):0]   data_q[$];
bit is_last;
bit [(AXIS_DATA_W-1):0]   data;
begin
  do begin
    pop(data, is_last);
    data_q[$+1] = tdata;
    end
    while(!is_last);
end
endtask // }}}
endinterface : axis_ep_if
