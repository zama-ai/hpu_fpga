// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module stores the body "b" of the small LWE.
// They are used by the sample extract module to do the rotation with b.
// ==============================================================================================

module pep_mmacc_body_ram
  import param_tfhe_pkg::*;
  import pep_common_param_pkg::*;
(
  input                         clk,        // clock
  input                         s_rst_n,    // synchronous reset
  input                         reset_cache,

  input  logic                  ks_boram_wr_en,
  input  logic [LWE_COEF_W-1:0] ks_boram_wr_data,
  input  logic [PID_W-1:0]      ks_boram_wr_pid,
  input  logic                  ks_boram_wr_parity,

  input  logic [PID_W-1:0]      boram_rd_pid,
  input  logic                  boram_rd_parity,
  input  logic                  boram_rd_vld,
  output logic                  boram_rd_rdy,

  output logic [LWE_COEF_W-1:0] boram_sxt_data,
  output logic                  boram_sxt_data_vld,
  input  logic                  boram_sxt_data_rdy
);

// ============================================================================================= --
// Input pipe
// ============================================================================================= --
  logic                  ram_wr_en;
  logic [LWE_COEF_W-1:0] ram_wr_data;
  logic [PID_W-1:0]      ram_wr_pid;
  logic                  ram_wr_parity;

  always_ff @(posedge clk)
    if (!s_rst_n) ram_wr_en <= 1'b0;
    else          ram_wr_en <= ks_boram_wr_en;

  always_ff @(posedge clk) begin
    ram_wr_data   <= ks_boram_wr_data;
    ram_wr_parity <= ks_boram_wr_parity;
    ram_wr_pid    <= ks_boram_wr_pid;
  end

  logic [PID_W-1:0] s0_rd_pid;
  logic             s0_rd_parity;
  logic             s0_rd_vld;
  logic             s0_rd_rdy;

  fifo_element #(
    .WIDTH          (PID_W+1),
    .DEPTH          (2),
    .TYPE_ARRAY     (8'h12),
    .DO_RESET_DATA  (0),
    .RESET_DATA_VAL (0)
  ) in_fifo_element (
    .clk     (clk),
    .s_rst_n (s_rst_n),

    .in_data ({boram_rd_parity,boram_rd_pid}),
    .in_vld  (boram_rd_vld),
    .in_rdy  (boram_rd_rdy),

    .out_data({s0_rd_parity,s0_rd_pid}),
    .out_vld (s0_rd_vld),
    .out_rdy (s0_rd_rdy)
  );

// ============================================================================================= --
// Output pipe
// ============================================================================================= --
  logic [LWE_COEF_W-1:0] s0_out_data;
  logic                  s0_out_vld;
  logic                  s0_out_rdy;

  fifo_element #(
    .WIDTH          (LWE_COEF_W),
    .DEPTH          (2),
    .TYPE_ARRAY     (8'h12),
    .DO_RESET_DATA  (0),
    .RESET_DATA_VAL (0)
  ) out_fifo_element (
    .clk     (clk),
    .s_rst_n (s_rst_n),

    .in_data (s0_out_data),
    .in_vld  (s0_out_vld),
    .in_rdy  (s0_out_rdy),

    .out_data(boram_sxt_data),
    .out_vld (boram_sxt_data_vld),
    .out_rdy (boram_sxt_data_rdy)
  );

// ============================================================================================= --
// RAM
// ============================================================================================= --
  // Read port
  logic                                    ram_rd_en;
  logic [PID_W-1:0]                        ram_rd_pid;
  logic [LWE_COEF_W-1:0]                   ram_rd_data;
  logic                                    ram_rd_present;
  logic                                    ram_rd_parity;

  logic [TOTAL_PBS_NB-1:0][LWE_COEF_W-1:0] ram;
  logic [TOTAL_PBS_NB-1:0]                 ram_present;
  logic [TOTAL_PBS_NB-1:0]                 ram_parity;

  logic [TOTAL_PBS_NB-1:0][LWE_COEF_W-1:0] ramD;
  logic [TOTAL_PBS_NB-1:0]                 ram_presentD;
  logic [TOTAL_PBS_NB-1:0]                 ram_parityD;

  always_comb
    for (int i=0; i<TOTAL_PBS_NB; i=i+1) begin
      ramD[i]         = (ram_wr_en && ram_wr_pid==i) ? ram_wr_data : ram[i];
      ram_parityD[i]  = (ram_wr_en && ram_wr_pid==i) ? ram_wr_parity : ram_parity[i];
      ram_presentD[i] = (ram_rd_en && ram_rd_pid==i) ? 1'b0 : // Read has priority
                        (ram_wr_en && ram_wr_pid==i) ? 1'b1 : ram_present[i];
    end

  always_ff @(posedge clk)
    if (!s_rst_n || reset_cache) ram_present <= '0;
    else                         ram_present <= ram_presentD;

  always_ff @(posedge clk) begin
    ram        <= ramD;
    ram_parity <= ram_parityD;
  end

  // Fits timing because TOTAL_PBS_NB order of magnitude is 32/64
  assign ram_rd_data    = ram[ram_rd_pid];
  assign ram_rd_parity  = ram_parity[ram_rd_pid];
  assign ram_rd_present = ram_present[ram_rd_pid];

// pragma translate_off
  // Remove parity check, because, it could occur in IPIP, the data is written twice,
  // because the KS process starts during the last KS col. The 2 times with different parities.
  // Therefore the request could be done with the first write parity, but data stored with
  // the last parity.
  // If this occurs, check that the data has the same value.
  //
  // parity signals are here for the debug.
  always_ff @(posedge clk)
    if (ram_wr_en && ram_present[ram_wr_pid]) begin
      assert(ram[ram_wr_pid] == ram_wr_data)
      else begin
        $display("%t > WARNING: Rewrite data in body_ram at pid=%0d, whereas data already present with another value.",$time,ram_wr_pid);
      end

      assert(ram_parity[ram_wr_pid] != ram_wr_parity)
      else begin
        $display("%t > WARNING: Rewrite data in body_ram at pid=%0d, whereas data already present with same parity.",$time,ram_wr_pid);
      end

      assert(!ram_rd_en || ram_present[ram_rd_pid])
      else begin
        $fatal(1,"%t > ERROR: Read data in body_ram at pid=%0d, whereas data not present.",$time,ram_rd_pid);
      end
    end
// pragma translate_on

// ============================================================================================= --
// READ access
// ============================================================================================= --
  assign ram_rd_en  = s0_rd_vld & s0_rd_rdy;
  assign ram_rd_pid = s0_rd_pid;

  assign s0_out_vld = s0_rd_vld  & ram_rd_present;
  assign s0_rd_rdy  = s0_out_rdy & ram_rd_present;

  assign s0_out_data = ram_rd_data;
endmodule
