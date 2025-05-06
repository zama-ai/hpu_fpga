/*

Copyright (c) 2018 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

// Language: Verilog 2001

// `resetall
// `timescale 1ns / 1ps
// `default_nettype none

/*
 * AXI4 RAM
 */
module axi4_ram #
(
    // Width of data bus in bits
    parameter int DATA_WIDTH = 32,
    // Width of address bus in bits
    parameter int ADDR_WIDTH = 16,
    // Width of wstrb (width of data bus in words)
    parameter int STRB_WIDTH = (DATA_WIDTH/8),
    // Width of ID signal
    parameter int ID_WIDTH = 8,
    // Extra pipeline register on output
    parameter int PIPELINE_OUTPUT = 0
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
    input  logic                   s_axi4_arvalid,
    output logic                   s_axi4_arready,
    output logic [ID_WIDTH-1:0]    s_axi4_rid,
    output logic [DATA_WIDTH-1:0]  s_axi4_rdata,
    output logic [1:0]             s_axi4_rresp,
    output logic                   s_axi4_rlast,
    output logic                   s_axi4_rvalid,
    input  logic                   s_axi4_rready
);

parameter  int VALID_ADDR_WIDTH = ADDR_WIDTH - $clog2(STRB_WIDTH);
parameter  int WORD_WIDTH = STRB_WIDTH;
parameter  int WORD_SIZE = DATA_WIDTH/WORD_WIDTH;
localparam int DEPTH = (2**VALID_ADDR_WIDTH);

// bus width assertions
// pragma translate_off
initial begin
    if (WORD_SIZE * STRB_WIDTH != DATA_WIDTH) begin
        $error("Error: AXI data width not evenly divisble (instance %m)");
        $finish;
    end

    if (2**$clog2(WORD_WIDTH) != WORD_WIDTH) begin
        $error("Error: AXI word width must be even power of two (instance %m)");
        $finish;
    end
end
// pragma translate_on

typedef enum {
    READ_STATE_IDLE,
    READ_STATE_BURST
} rd_state_e;


typedef enum {
    WRITE_STATE_IDLE,
    WRITE_STATE_BURST,
    WRITE_STATE_RESP
} wr_state_e;

rd_state_e read_state_reg, read_state_next;
wr_state_e write_state_reg, write_state_next;

logic mem_wr_en;
logic mem_rd_en;

logic [ID_WIDTH-1:0] read_id_reg, read_id_next;
logic [ADDR_WIDTH-1:0] read_addr_reg, read_addr_next;
logic [7:0] read_count_reg, read_count_next;
logic [2:0] read_size_reg, read_size_next;
logic [1:0] read_burst_reg, read_burst_next;
logic [ID_WIDTH-1:0] write_id_reg, write_id_next;
logic [ADDR_WIDTH-1:0] write_addr_reg, write_addr_next;
logic [7:0] write_count_reg, write_count_next;
logic [2:0] write_size_reg, write_size_next;
logic [1:0] write_burst_reg, write_burst_next;

logic s_axi4_awready_reg, s_axi4_awready_next;
logic s_axi4_wready_reg, s_axi4_wready_next;
logic [ID_WIDTH-1:0] s_axi4_bid_reg, s_axi4_bid_next;
logic s_axi4_bvalid_reg, s_axi4_bvalid_next;
logic s_axi4_arready_reg, s_axi4_arready_next;
logic [ID_WIDTH-1:0] s_axi4_rid_reg, s_axi4_rid_next;
logic [DATA_WIDTH-1:0] s_axi4_rdata_reg, s_axi4_rdata_next;
logic s_axi4_rlast_reg, s_axi4_rlast_next;
logic s_axi4_rvalid_reg, s_axi4_rvalid_next;
logic [ID_WIDTH-1:0] s_axi4_rid_pipe_reg;
logic [DATA_WIDTH-1:0] s_axi4_rdata_pipe_reg;
logic s_axi4_rlast_pipe_reg;
logic s_axi4_rvalid_pipe_reg;

// (* RAM_STYLE="BLOCK" *)
logic /* sparse */ [DATA_WIDTH-1:0] mem [DEPTH-1:0];

logic [VALID_ADDR_WIDTH-1:0] s_axi4_awaddr_valid ;
logic [VALID_ADDR_WIDTH-1:0] s_axi4_araddr_valid ;
logic [VALID_ADDR_WIDTH-1:0] read_addr_valid ;
logic [VALID_ADDR_WIDTH-1:0] write_addr_valid ;

assign s_axi4_awaddr_valid = s_axi4_awaddr >> (ADDR_WIDTH - VALID_ADDR_WIDTH);
assign s_axi4_araddr_valid = s_axi4_araddr >> (ADDR_WIDTH - VALID_ADDR_WIDTH);
assign read_addr_valid = read_addr_reg >> (ADDR_WIDTH - VALID_ADDR_WIDTH);
assign write_addr_valid = write_addr_reg >> (ADDR_WIDTH - VALID_ADDR_WIDTH);

assign s_axi4_awready = s_axi4_awready_reg;
assign s_axi4_wready = s_axi4_wready_reg;
assign s_axi4_bid = s_axi4_bid_reg;
assign s_axi4_bresp = 2'b00;
assign s_axi4_bvalid = s_axi4_bvalid_reg;
assign s_axi4_arready = s_axi4_arready_reg;
assign s_axi4_rid = PIPELINE_OUTPUT ? s_axi4_rid_pipe_reg : s_axi4_rid_reg;
assign s_axi4_rdata = PIPELINE_OUTPUT ? s_axi4_rdata_pipe_reg : s_axi4_rdata_reg;
assign s_axi4_rresp = 2'b00;
assign s_axi4_rlast = PIPELINE_OUTPUT ? s_axi4_rlast_pipe_reg : s_axi4_rlast_reg;
assign s_axi4_rvalid = PIPELINE_OUTPUT ? s_axi4_rvalid_pipe_reg : s_axi4_rvalid_reg;

integer i, j, k;

always_comb begin
    write_state_next = WRITE_STATE_IDLE;

    mem_wr_en = 1'b0;

    write_id_next = write_id_reg;
    write_addr_next = write_addr_reg;
    write_count_next = write_count_reg;
    write_size_next = write_size_reg;
    write_burst_next = write_burst_reg;

    s_axi4_awready_next = 1'b0;
    s_axi4_wready_next = 1'b0;
    s_axi4_bid_next = s_axi4_bid_reg;
    s_axi4_bvalid_next = s_axi4_bvalid_reg && !s_axi4_bready;

    case (write_state_reg)
        WRITE_STATE_IDLE: begin
            s_axi4_awready_next = 1'b1;

            if (s_axi4_awready && s_axi4_awvalid) begin
                write_id_next = s_axi4_awid;
                write_addr_next = s_axi4_awaddr;
                write_count_next = s_axi4_awlen;
                write_size_next = s_axi4_awsize < $clog2(STRB_WIDTH) ? s_axi4_awsize : $clog2(STRB_WIDTH);
                write_burst_next = s_axi4_awburst;

                s_axi4_awready_next = 1'b0;
                s_axi4_wready_next = 1'b1;
                write_state_next = WRITE_STATE_BURST;
            end else begin
                write_state_next = WRITE_STATE_IDLE;
            end
        end
        WRITE_STATE_BURST: begin
            s_axi4_wready_next = 1'b1;

            if (s_axi4_wready && s_axi4_wvalid) begin
                mem_wr_en = 1'b1;
                if (write_burst_reg != 2'b00) begin
                    write_addr_next = write_addr_reg + (1 << write_size_reg);
                end
                write_count_next = write_count_reg - 1;
                if (write_count_reg > 0) begin
                    write_state_next = WRITE_STATE_BURST;
                end else begin
                    s_axi4_wready_next = 1'b0;
                    if (s_axi4_bready || !s_axi4_bvalid) begin
                        s_axi4_bid_next = write_id_reg;
                        s_axi4_bvalid_next = 1'b1;
                        s_axi4_awready_next = 1'b1;
                        write_state_next = WRITE_STATE_IDLE;
                    end else begin
                        write_state_next = WRITE_STATE_RESP;
                    end
                end
            end else begin
                write_state_next = WRITE_STATE_BURST;
            end
        end
        WRITE_STATE_RESP: begin
            if (s_axi4_bready || !s_axi4_bvalid) begin
                s_axi4_bid_next = write_id_reg;
                s_axi4_bvalid_next = 1'b1;
                s_axi4_awready_next = 1'b1;
                write_state_next = WRITE_STATE_IDLE;
            end else begin
                write_state_next = WRITE_STATE_RESP;
            end
        end
    endcase
end

// We are not using always_ff here because some simulators (VCS) do not
// support any other driver (readmemh or initial block...) on signals
// assigned in an always_ff block
always @(posedge clk) begin
    for (i = 0; i < WORD_WIDTH; i = i + 1) begin
        if (mem_wr_en & s_axi4_wstrb[i]) begin
            mem[write_addr_valid][WORD_SIZE*i +: WORD_SIZE] <= s_axi4_wdata[WORD_SIZE*i +: WORD_SIZE];
        end
    end
end

always_ff @(posedge clk) begin
    if (rst) begin
        write_state_reg <= WRITE_STATE_IDLE;

        s_axi4_awready_reg <= 1'b0;
        s_axi4_wready_reg <= 1'b0;
        s_axi4_bvalid_reg <= 1'b0;

        write_id_reg <= {ID_WIDTH{1'b0}};
        write_addr_reg <= {ADDR_WIDTH{1'b0}};
        write_count_reg <= 8'd0;
        write_size_reg <= 3'd0;
        write_burst_reg <= 2'd0;

        s_axi4_awready_reg <= 1'b0;
        s_axi4_wready_reg <= 1'b0;
        s_axi4_bid_reg <= {ID_WIDTH{1'b0}};
        s_axi4_bvalid_reg <= 1'b0;

    end
    else begin
      write_state_reg <= write_state_next;

      write_id_reg <= write_id_next;
      write_addr_reg <= write_addr_next;
      write_count_reg <= write_count_next;
      write_size_reg <= write_size_next;
      write_burst_reg <= write_burst_next;

      s_axi4_awready_reg <= s_axi4_awready_next;
      s_axi4_wready_reg <= s_axi4_wready_next;
      s_axi4_bid_reg <= s_axi4_bid_next;
      s_axi4_bvalid_reg <= s_axi4_bvalid_next;

    end
end

always_comb begin
    read_state_next = READ_STATE_IDLE;

    mem_rd_en = 1'b0;

    s_axi4_rid_next = s_axi4_rid_reg;
    s_axi4_rlast_next = s_axi4_rlast_reg;
    s_axi4_rvalid_next = s_axi4_rvalid_reg && !(s_axi4_rready || (PIPELINE_OUTPUT && !s_axi4_rvalid_pipe_reg));

    read_id_next = read_id_reg;
    read_addr_next = read_addr_reg;
    read_count_next = read_count_reg;
    read_size_next = read_size_reg;
    read_burst_next = read_burst_reg;

    s_axi4_arready_next = 1'b0;

    case (read_state_reg)
        READ_STATE_IDLE: begin
            s_axi4_arready_next = 1'b1;

            if (s_axi4_arready && s_axi4_arvalid) begin
                read_id_next = s_axi4_arid;
                read_addr_next = s_axi4_araddr;
                read_count_next = s_axi4_arlen;
                read_size_next = s_axi4_arsize < $clog2(STRB_WIDTH) ? s_axi4_arsize : $clog2(STRB_WIDTH);
                read_burst_next = s_axi4_arburst;

                s_axi4_arready_next = 1'b0;
                read_state_next = READ_STATE_BURST;
            end else begin
                read_state_next = READ_STATE_IDLE;
            end
        end
        READ_STATE_BURST: begin
            if (s_axi4_rready || (PIPELINE_OUTPUT && !s_axi4_rvalid_pipe_reg) || !s_axi4_rvalid_reg) begin
                mem_rd_en = 1'b1;
                s_axi4_rvalid_next = 1'b1;
                s_axi4_rid_next = read_id_reg;
                s_axi4_rlast_next = read_count_reg == 0;
                if (read_burst_reg != 2'b00) begin
                    read_addr_next = read_addr_reg + (1 << read_size_reg);
                end
                read_count_next = read_count_reg - 1;
                if (read_count_reg > 0) begin
                    read_state_next = READ_STATE_BURST;
                end else begin
                    s_axi4_arready_next = 1'b1;
                    read_state_next = READ_STATE_IDLE;
                end
            end else begin
                read_state_next = READ_STATE_BURST;
            end
        end
    endcase
end

always_ff @(posedge clk) begin
    if (rst) begin
        read_state_reg <= READ_STATE_IDLE;

        s_axi4_arready_reg <= 1'b0;
        s_axi4_rvalid_reg <= 1'b0;
        s_axi4_rvalid_pipe_reg <= 1'b0;

        read_id_reg <= {ID_WIDTH{1'b0}};
        read_addr_reg <= {ADDR_WIDTH{1'b0}};
        read_count_reg <= 8'd0;
        read_size_reg <= 3'd0;
        read_burst_reg <= 2'd0;

        s_axi4_arready_reg <= 1'b0;
        s_axi4_rid_reg <= {ID_WIDTH{1'b0}};
        s_axi4_rdata_reg <= {DATA_WIDTH{1'b0}};
        s_axi4_rlast_reg <= 1'b0;
        s_axi4_rvalid_reg <= 1'b0;

        s_axi4_rid_pipe_reg <= {ID_WIDTH{1'b0}};
        s_axi4_rdata_pipe_reg <= {DATA_WIDTH{1'b0}};
        s_axi4_rlast_pipe_reg <= 1'b0;
    end
    else begin
      read_state_reg <= read_state_next;

      read_id_reg <= read_id_next;
      read_addr_reg <= read_addr_next;
      read_count_reg <= read_count_next;
      read_size_reg <= read_size_next;
      read_burst_reg <= read_burst_next;

      s_axi4_arready_reg <= s_axi4_arready_next;
      s_axi4_rid_reg <= s_axi4_rid_next;
      s_axi4_rlast_reg <= s_axi4_rlast_next;
      s_axi4_rvalid_reg <= s_axi4_rvalid_next;

      if (mem_rd_en) begin
          s_axi4_rdata_reg <= mem[read_addr_valid];
      end

      if (!s_axi4_rvalid_pipe_reg || s_axi4_rready) begin
          s_axi4_rid_pipe_reg <= s_axi4_rid_reg;
          s_axi4_rdata_pipe_reg <= s_axi4_rdata_reg;
          s_axi4_rlast_pipe_reg <= s_axi4_rlast_reg;
          s_axi4_rvalid_pipe_reg <= s_axi4_rvalid_reg;
      end
    end
end

endmodule

`resetall
