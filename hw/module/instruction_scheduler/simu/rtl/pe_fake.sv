// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Simulation component to fake PE interface
// ----------------------------------------------------------------------------------------------
//
// Buffer request in a fifo and randomly consume elems and generate ack
// ==============================================================================================

`ifdef QUESTA
  `timescale 1ns/10ps
`endif


module pe_fake
  import instruction_scheduler_pkg::*;
  import hpu_common_instruction_pkg::*;
  #(
    parameter int FIFO_DEPTH = 32,
    parameter int MAX_CONS_CYCLE = 4,
    parameter int MAX_BATCH_ELEM = 1,
    parameter int MAX_ACK_CYCLE = 4
  )(
    input logic                  clk,        // clock
    input logic                  s_rst_n,    // synchronous reset

    // PE interface
    output logic                 pe_rdy,
    input  logic[PE_INST_W-1: 0] pe_insn,
    input  logic                 pe_vld,
    output logic                 pe_rd_ack,
    output logic                 pe_wr_ack
  );


// Internal signal
// ----------------------------------------------------------------------------------------------
logic cons_vld, cons_rdy;
  
// Insn fifo
// ----------------------------------------------------------------------------------------------
fifo_reg # (
  .WIDTH        (PE_INST_W),
  .DEPTH        (FIFO_DEPTH),
  .LAT_PIPE_MH('{0,1})
) fifo_ack (
  .clk     (clk          ),
  .s_rst_n (s_rst_n      ),

  .in_data (pe_insn),
  .in_vld  (pe_vld),
  .in_rdy  (pe_rdy),

  .out_data(),
  .out_vld (cons_vld),
  .out_rdy (cons_rdy)
);


// Random consumer process
// Draw a random number between 0-MAX_CONS_CYCLE and trigger a dequeue
// Then draw a random number between 0-MAX_ACK_CYCLE and generate a pulse over pe_ack
integer cons_cycles;
integer ack_cycles;
integer batch_elem;
integer batch_slot;
logic rd_ack_gen, wr_ack_gen;

initial begin
  rd_ack_gen = '0;
  wr_ack_gen = '0;
  cons_rdy = '0;

  while (!s_rst_n) @(posedge clk);
  repeat(10) @(posedge clk);

  while (1) begin
    // Draw random number
    cons_cycles = $urandom_range(1, MAX_CONS_CYCLE);
    batch_elem = $urandom_range(1,MAX_BATCH_ELEM);
    ack_cycles = $urandom_range(1, MAX_ACK_CYCLE);
    @(posedge clk);

    batch_slot = 0;
    fork
    begin
      repeat(cons_cycles) @(posedge clk);
    end
    begin
      for (int i = 0; i < batch_elem; i++) begin
        cons_rdy = 1'b1;
        do @(posedge clk); while (!cons_vld);
        batch_slot += 1;
      end

    end
    join_any
    #1 disable fork;
    cons_rdy = 1'b0;

    if (batch_slot != 0) begin
      // generate fake rd_release
      rd_ack_gen = 1'b1;
      repeat(batch_slot) @(posedge clk);
      rd_ack_gen = '0;

      // generate fake wr_release
      repeat(ack_cycles) @(posedge clk);
      wr_ack_gen = 1'b1;
      repeat(batch_slot) @(posedge clk);
      wr_ack_gen = '0;
    end
    @(posedge clk);
  end
end
assign pe_rd_ack = rd_ack_gen;
assign pe_wr_ack = wr_ack_gen;

endmodule
