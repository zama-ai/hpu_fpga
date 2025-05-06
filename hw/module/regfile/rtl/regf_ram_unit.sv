// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals the regfile RAM used to store the BLWE-"registers"
// It handles a single RAM word.
// ==============================================================================================

module regf_ram_unit
#(
  parameter  int OP_W        = 64,
  parameter  int DEPTH       = 2048,
  parameter  int PE_NB       = 3,
  parameter  int RAM_LATENCY = 4,
  parameter  int SIDE_W      = 10,
  parameter  int IN_PIPE     = 1'b0,
  localparam int ADD_W       = $clog2(DEPTH) == 0 ? 1 : $clog2(DEPTH)
)
(
  input  logic                         clk,        // clock
  input  logic                         s_rst_n,    // synchronous reset

  input  logic                         wr_en,
  input  logic [ADD_W-1:0]             wr_add,
  input  logic [OP_W-1:0]              wr_data,

  input  logic                         rd_en,
  input  logic [ADD_W-1:0]             rd_add,
  input  logic [PE_NB-1:0]             rd_pe_id_1h,
  input  logic [SIDE_W-1:0]            rd_side,

  output logic [PE_NB-1:0][OP_W-1:0]   datar,
  output logic [PE_NB-1:0]             datar_avail,
  output logic [PE_NB-1:0][SIDE_W-1:0] datar_side
);

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int SR_DEPTH         = RAM_LATENCY;

// ============================================================================================== --
// Input pipe
// ============================================================================================== --
  logic              s0_wr_en;
  logic [ADD_W-1:0]  s0_wr_add;
  logic [OP_W-1:0]   s0_wr_data;

  logic              s0_rd_en;
  logic [ADD_W-1:0]  s0_rd_add;
  logic [PE_NB-1:0]  s0_rd_pe_id_1h;
  logic [SIDE_W-1:0] s0_rd_side;

  generate
    if (IN_PIPE) begin : gen_in_pipe
      always_ff @(posedge clk)
        if (!s_rst_n) begin
          s0_wr_en <= 1'b0;
          s0_rd_en <= 1'b0;
        end
        else begin
          s0_wr_en <= wr_en;
          s0_rd_en <= rd_en;
        end

      always_ff @(posedge clk) begin
        s0_wr_add      <= wr_add;
        s0_wr_data     <= wr_data;
        s0_rd_add      <= rd_add;
        s0_rd_pe_id_1h <= rd_pe_id_1h;
        s0_rd_side     <= rd_side;
      end
    end
    else begin : gen_no_in_pipe
      assign s0_wr_en       = wr_en;
      assign s0_rd_en       = rd_en;
      assign s0_wr_add      = wr_add;
      assign s0_wr_data     = wr_data;
      assign s0_rd_add      = rd_add;
      assign s0_rd_pe_id_1h = rd_pe_id_1h;
      assign s0_rd_side     = rd_side;
    end
  endgenerate

// ============================================================================================== --
// RAM
// ============================================================================================== --
  logic [OP_W-1:0] s1_rd_data;

  ram_wrapper_1R1W #(
    .WIDTH             (OP_W),
    .DEPTH             (DEPTH),
    .RD_WR_ACCESS_TYPE (0), // Output 'X' when access conflict
    .KEEP_RD_DATA      (0), // TOREVIEW
    .RAM_LATENCY       (RAM_LATENCY)
  ) regf_ram (
    .clk      (clk),
    .s_rst_n  (s_rst_n),

    .rd_en    (s0_rd_en),
    .rd_add   (s0_rd_add),
    .rd_data  (s1_rd_data),

    .wr_en    (s0_wr_en),
    .wr_add   (s0_wr_add),
    .wr_data  (s0_wr_data)
  );

  logic [SR_DEPTH-1:0]             s1_rd_en_sr;
  logic [SR_DEPTH-1:0][PE_NB-1:0]  s1_rd_pe_id_1h_sr;
  logic [SR_DEPTH-1:0][SIDE_W-1:0] s1_rd_side_sr;

  logic [SR_DEPTH-1:0]             s1_rd_en_srD;
  logic [SR_DEPTH-1:0][PE_NB-1:0]  s1_rd_pe_id_1h_srD;
  logic [SR_DEPTH-1:0][SIDE_W-1:0] s1_rd_side_srD;

  assign s1_rd_en_srD[0]       = s0_rd_en;
  assign s1_rd_pe_id_1h_srD[0] = s0_rd_pe_id_1h;
  assign s1_rd_side_srD[0]     = s0_rd_side;

  assign s1_rd_en_srD[SR_DEPTH-1:1]       = s1_rd_en_sr[SR_DEPTH-2:0];
  assign s1_rd_pe_id_1h_srD[SR_DEPTH-1:1] = s1_rd_pe_id_1h_sr[SR_DEPTH-2:0];
  assign s1_rd_side_srD[SR_DEPTH-1:1]     = s1_rd_side_sr[SR_DEPTH-2:0];

  always_ff @(posedge clk)
    if (!s_rst_n) s1_rd_en_sr <= '0;
    else          s1_rd_en_sr <= s1_rd_en_srD;

  always_ff @(posedge clk) begin
    s1_rd_pe_id_1h_sr <= s1_rd_pe_id_1h_srD;
    s1_rd_side_sr     <= s1_rd_side_srD;
  end

// ============================================================================================== --
// RAM output
// ============================================================================================== --
  logic              s2_rd_en;
  logic [PE_NB-1:0]  s2_rd_pe_id_1h;
  logic [SIDE_W-1:0] s2_rd_side;
  logic [OP_W-1:0]   s2_rd_data;
  logic [PE_NB-1:0]  s2_rd_avail;

  assign s2_rd_en       = s1_rd_en_sr[SR_DEPTH-1];
  assign s2_rd_data     = s1_rd_data;
  assign s2_rd_pe_id_1h = s1_rd_pe_id_1h_sr[SR_DEPTH-1];
  assign s2_rd_side     = s1_rd_side_sr[SR_DEPTH-1];
  assign s2_rd_avail    = s2_rd_pe_id_1h & {PE_NB{s2_rd_en}};

// ============================================================================================== --
// Output pipe
// ============================================================================================== --
  logic [PE_NB-1:0][SIDE_W-1:0] datar_sideD;
  logic [PE_NB-1:0][OP_W-1:0]   datarD;

  always_comb
    for (int p=0; p<PE_NB; p=p+1) begin // clockgate for power
      datar_sideD[p] = s2_rd_avail[p] ? s2_rd_side : datar_side[p];
      datarD[p]      = s2_rd_avail[p] ? s2_rd_data : datar[p];
    end

  always_ff @(posedge clk)
    if (!s_rst_n) datar_avail <= '0;
    else          datar_avail <= s2_rd_avail;

  always_ff @(posedge clk) begin
    datar_side <= datar_sideD;
    datar      <= datarD;
  end

// ============================================================================================== --
// Initialization
// ============================================================================================== --
// Initialize with dummy values for simulation
// pragma translate_off
//  initial begin
//    $display("> INFO: Initialize regfile with 'hABBAC001DEADC0FFEE");
//    for (int i=0; i<DEPTH; i=i+1)
//      regf_ram.ram_1R1W.ram_1R1W_core.a[i] = 'hABBAC001DEADC0FFEE;
//  end
// pragma translate_on

endmodule
