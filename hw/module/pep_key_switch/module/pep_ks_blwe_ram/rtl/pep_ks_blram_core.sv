// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the RAM used to store the LWE data for a batch.
// This RAM is initialized by eternal write access.
// During the process:
// - it is read to get the LWE coef.
// There are at most BATCH_PBS_NB PBS per batch.
// ==============================================================================================

module pep_ks_blram_core
#(
  parameter  int OP_W         = 64,
  parameter  int RAM_DEPTH    = 54*8,
  localparam int RAM_ADD_W    = $clog2(RAM_DEPTH),
  parameter  int RAM_LATENCY  = 1,
  parameter  bit IN_PIPE      = 1'b1,
  parameter  bit OUT_PIPE     = 1'b1 // recommended to be 1
)
(
  input                             clk,        // clock
  input                             s_rst_n,    // synchronous reset

  // Wr access to BLWE RAM
  input  logic                      wr_en,
  input  logic [RAM_ADD_W-1:0]      wr_add,
  input  logic [OP_W-1:0]           wr_data,

  // Rd access to BLWE RAM
  input  logic                      rd_en,
  input  logic [RAM_ADD_W-1:0]      rd_add,
  output logic [OP_W-1:0]           rd_data,
  output logic                      rd_data_avail
);

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int DATA_LATENCY = RAM_LATENCY;
  localparam int BUF_DEPTH    = RAM_LATENCY + 4;

// ============================================================================================== --
// Input Pipe
// ============================================================================================== --
  logic                  s0_wr_en;
  logic [RAM_ADD_W-1:0]  s0_wr_add;
  logic [OP_W-1:0]       s0_wr_data;

  generate
    if (IN_PIPE) begin : gen_in_pipe
      always_ff @(posedge clk)
        if (!s_rst_n) s0_wr_en <= 1'b0;
        else          s0_wr_en <= wr_en;

      always_ff @(posedge clk) begin
        s0_wr_add  <= wr_add ;
        s0_wr_data <= wr_data;
      end
    end
    else begin
      assign s0_wr_en   = wr_en;
      assign s0_wr_add  = wr_add ;
      assign s0_wr_data = wr_data;
    end
  endgenerate

// ============================================================================================== --
// RAM read interface
// ============================================================================================== --
  logic                 s0_rd_vld;
  logic                 s0_rd_rdy;
  logic [RAM_ADD_W-1:0] s0_rd_add;

  logic                 s1_rd_data_vld;
  logic                 s1_rd_data_rdy;
  logic [OP_W-1:0]      s1_rd_data;

  logic                 ram_ren;
  logic[RAM_ADD_W-1:0]  ram_add;

  logic [OP_W-1:0]      ram_data;
  logic                 ram_data_en;

  assign s0_rd_vld      = rd_en;
  assign s0_rd_add      = rd_add;
  assign rd_data        = s1_rd_data;
  assign rd_data_avail  = s1_rd_data_vld;
  assign s1_rd_data_rdy = 1'b1;

  ram_rd_rdy_vld #(
    .IN_PIPE     (1'b0),
    .OUT_PIPE    (OUT_PIPE),
    .RAM_IN_PIPE (1'b1),
    .RAM_OUT_PIPE(1'b1),
    .DATA_LATENCY(DATA_LATENCY),
    .BUF_DEPTH   (BUF_DEPTH),
    .ADD_W       (RAM_ADD_W),
    .DATA_W      (OP_W),
    .SIDE_W      (0) // UNUSED
  ) ram_rd_rdy_vld (
     .clk          (clk),
     .s_rst_n      (s_rst_n),

     .rd_vld       (s0_rd_vld),
     .rd_rdy       (s0_rd_rdy),
     .rd_add       (s0_rd_add),
     .rd_side      ('x), // UNUSED

     .rd_data_vld  (s1_rd_data_vld),
     .rd_data_rdy  (s1_rd_data_rdy),
     .rd_data      (s1_rd_data),
     .rd_data_side (/*UNUSED*/),

     .ram_ren      (ram_ren),
     .ram_add      (ram_add),
     .ram_side     (/*UNUSED*/),

     .ram_data     (ram_data),
     .ram_data_en  (ram_data_en),
     .ram_data_side(/*UNUSED*/)
  );

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      assert(!s0_rd_vld || s0_rd_rdy)
      else begin
        $fatal(1,"%t > ERROR: BLRAM read overflow!", $time);
      end
    end
// pragma translate_on

// ============================================================================================== --
// LRAM
// ============================================================================================== --
  // Use 1R1W RAM
  ram_wrapper_1R1W #(
    .WIDTH             (OP_W),
    .DEPTH             (RAM_DEPTH),
    .RD_WR_ACCESS_TYPE (0),
    .KEEP_RD_DATA      (0),
    .RAM_LATENCY       (RAM_LATENCY)
  )
  blwe_ram
  (
    .clk     (clk),
    .s_rst_n (s_rst_n),

    .rd_en   (ram_ren),
    .rd_add  (ram_add),
    .rd_data (ram_data),

    .wr_en   (s0_wr_en),
    .wr_add  (s0_wr_add),
    .wr_data (s0_wr_data)
  );

endmodule

