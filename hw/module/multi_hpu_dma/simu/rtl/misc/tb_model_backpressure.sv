// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Per-lane ready/valid backpressure module for testbenches.
//
// When ENABLE=1, buffers one word and forwards it with 50% random valid probability.
// When ENABLE=0, passthrough (no backpressure, no delay).
//
// ==============================================================================================

`resetall
`timescale 1ns/10ps

module tb_model_backpressure
  import mhdma_pkg::*;
#(
  parameter bit ENABLE = 1
)(
  input  logic                      clk,
  input  logic                      rstn,
  // Slave side (from DUT TX)
  input  logic [MRMAC_AXIS_W-1:0]   s_tdata,
  input  logic [MRMAC_TKEEP_W-1:0]  s_tkeep_user,
  input  logic                      s_tlast,
  input  logic                      s_tvalid,
  output logic                      s_tready,
  // Master side (to DUT RX or delay)
  output logic [MRMAC_AXIS_W-1:0]   m_tdata,
  output logic [MRMAC_TKEEP_W-1:0]  m_tkeep_user,
  output logic                      m_tlast,
  output logic                      m_tvalid
);

  logic [MRMAC_AXIS_W-1:0]   tmp_tdata;
  logic [MRMAC_TKEEP_W-1:0]  tmp_tkeep_user;
  logic                      tmp_tlast;
  logic                      tmp_tvalid;

  generate
    if (ENABLE) begin : gen_enabled
      logic [MRMAC_AXIS_W-1:0]  data_buf;
      logic [MRMAC_TKEEP_W-1:0] tkeep_buf;
      logic                      last_buf;
      logic                      has_data;
      logic                      random_valid_en;

      always_ff @(posedge clk) begin
        if (~rstn) begin
          data_buf        <= '0;
          tkeep_buf       <= '0;
          last_buf        <= '0;
          has_data        <= '0;
          random_valid_en <= '0;
        end else begin
          random_valid_en <= ($urandom() % 100 < 50);

          if (~has_data && s_tvalid) begin
            data_buf  <= s_tdata;
            tkeep_buf <= s_tkeep_user;
            last_buf  <= s_tlast;
            has_data  <= 1'b1;
          end

          if (has_data && random_valid_en) begin
            has_data <= 1'b0;
          end
        end
      end

      assign s_tready     = ~has_data;
      assign tmp_tdata      = data_buf;
      assign tmp_tkeep_user = tkeep_buf;
      assign tmp_tlast      = last_buf;
      assign tmp_tvalid     = has_data && random_valid_en;

    end else begin : gen_passthrough
      assign s_tready     = 1'b1;
      assign tmp_tdata      = s_tdata;
      assign tmp_tkeep_user = s_tkeep_user;
      assign tmp_tlast      = s_tlast;
      assign tmp_tvalid     = s_tvalid;
    end
  endgenerate

  always @(*) begin
    m_tdata      <= #100ns tmp_tdata;
    m_tkeep_user <= #100ns tmp_tkeep_user;
    m_tlast      <= #100ns tmp_tlast;
    m_tvalid     <= #100ns tmp_tvalid;
  end

endmodule
