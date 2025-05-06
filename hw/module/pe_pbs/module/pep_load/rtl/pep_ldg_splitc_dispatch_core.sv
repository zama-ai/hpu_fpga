// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module dispatch AXI data for main and subs parts.
// These 2 parts may need different number of coefficients.
// Assumption : the number of coefficients in the AXI divides the number of coefficients
// needed by each part.
// This sub module handles the case when IN_COEF <= DISP_COEF
// ==============================================================================================

module pep_ldg_dispatch_core
#(
  parameter  int OP_W           = 32,
  parameter  int UNIT_COEF      = 8,
  parameter  int OUT_COEF       = 8,
  parameter  int OUT0_UNIT_NB   = 1,
  parameter  int OUT1_UNIT_NB   = 3,
  parameter  bit IN_PIPE        = 1'b1,
  parameter  bit OUT_PIPE       = 1'b1
)
(
  input  logic                               clk,        // clock
  input  logic                               s_rst_n,    // synchronous reset

  input  logic [UNIT_COEF-1:0][OP_W-1:0]     in_data,
  input  logic                               in_vld,
  output logic                               in_rdy,

  output logic [1:0][OUT_COEF-1:0][OP_W-1:0] out_data,
  output logic [1:0]                         out_vld,
  input  logic [1:0]                         out_rdy
);

// ============================================================================================== //
// localparam
// ============================================================================================== //
  localparam int MAX_UNIT_NB = OUT0_UNIT_NB > OUT1_UNIT_NB ? OUT0_UNIT_NB : OUT1_UNIT_NB;
  localparam int UNIT_CNT_W  = $clog2(MAX_UNIT_NB) == 0 ? 1 : $clog2(MAX_UNIT_NB);
  localparam [1:0][UNIT_CNT_W-1:0] UNIT_CNT_MAX = {UNIT_CNT_W'(OUT1_UNIT_NB-1),UNIT_CNT_W'(OUT0_UNIT_NB-1)};

// ============================================================================================== //
// IN_PIPE
// ============================================================================================== //
  logic [UNIT_COEF-1:0][OP_W-1:0] s0_data;
  logic                           s0_vld;
  logic                           s0_rdy;

  generate
    if (IN_PIPE) begin : gen_in_pipe
      fifo_element #(
        .WIDTH          (UNIT_COEF * OP_W),
        .DEPTH          (2),
        .TYPE_ARRAY     (8'h12),
        .DO_RESET_DATA  (0),
        .RESET_DATA_VAL (0)
      ) in_fifo_element (
        .clk     (clk),
        .s_rst_n (s_rst_n),

        .in_data (in_data),
        .in_vld  (in_vld),
        .in_rdy  (in_rdy),

        .out_data(s0_data),
        .out_vld (s0_vld),
        .out_rdy (s0_rdy)
      );
    end
    else begin : gen_no_in_pipe
      assign s0_data = in_data;
      assign s0_vld  = in_vld;
      assign in_rdy  = s0_rdy;
    end
  endgenerate


// ============================================================================================== //
// Dispatch
// ============================================================================================== //
  // Dispatch is done the following way :
  // First OUT0_UNIT_NB elements are sent to out0, then OUT1_UNIT_NB are sent to out1.
  logic s0_disp_id;
  logic s0_disp_idD;

  logic [UNIT_CNT_W-1:0] s0_unit_cnt;
  logic [UNIT_CNT_W-1:0] s0_unit_cntD;
  logic                  s0_last_unit_cnt;
  logic [UNIT_CNT_W-1:0] s0_unit_max;

  assign s0_last_unit_cnt = s0_unit_cnt == UNIT_CNT_MAX[s0_disp_id];
  assign s0_unit_cntD     = (s0_vld && s0_rdy) ? s0_last_unit_cnt ? '0 : s0_unit_cnt + 1 : s0_unit_cnt;
  assign s0_disp_idD      = (s0_vld && s0_rdy && s0_last_unit_cnt) ? ~s0_disp_id : s0_disp_id;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      s0_unit_cnt    <= '0;
      s0_disp_id <= '0;
    end
    else begin
      s0_unit_cnt    <= s0_unit_cntD   ;
      s0_disp_id <= s0_disp_idD;
    end

  // Dispatch
  logic [1:0] s0_fmt_vld;
  logic [1:0] s0_fmt_rdy;
  logic [1:0][UNIT_COEF-1:0][OP_W-1:0] s0_fmt_data;

  assign s0_rdy      = s0_fmt_rdy[s0_disp_id];
  assign s0_fmt_data = {2{s0_data}};
  assign s0_fmt_vld  = {s0_disp_id,~s0_disp_id} & {2{s0_vld}};

// ============================================================================================== //
// Format
// ============================================================================================== //
  logic [1:0]                         s1_fmt_vld;
  logic [1:0]                         s1_fmt_rdy;
  logic [1:0][OUT_COEF-1:0][OP_W-1:0] s1_fmt_data;

  generate
    for (genvar gen_i=0; gen_i<2; gen_i=gen_i+1) begin : gen_loop
      stream_disp_format
      #(
        .OP_W      (OP_W),
        .IN_COEF   (UNIT_COEF),
        .OUT_COEF  (OUT_COEF),
        .IN_PIPE   (1'b1) // TO REVIEW
      ) stream_disp_format (
        .clk      (clk),
        .s_rst_n  (s_rst_n),

        .in_data  (s0_fmt_data[gen_i]),
        .in_vld   (s0_fmt_vld[gen_i]),
        .in_rdy   (s0_fmt_rdy[gen_i]),

        .out_data (s1_fmt_data[gen_i]),
        .out_vld  (s1_fmt_vld[gen_i]),
        .out_rdy  (s1_fmt_rdy[gen_i])
      );
    end
  endgenerate


// ============================================================================================== //
// Output
// ============================================================================================== //
  generate
    if (OUT_PIPE) begin : gen_out_pipe
      for (genvar gen_i=0; gen_i<2; gen_i=gen_i+1) begin : gen_out_loop
        fifo_element #(
          .WIDTH          (OUT_COEF * OP_W),
          .DEPTH          (2),
          .TYPE_ARRAY     (8'h12),
          .DO_RESET_DATA  (0),
          .RESET_DATA_VAL (0)
        ) out_fifo_element (
          .clk     (clk),
          .s_rst_n (s_rst_n),

          .in_data (s1_fmt_data[gen_i]),
          .in_vld  (s1_fmt_vld[gen_i]),
          .in_rdy  (s1_fmt_rdy[gen_i]),

          .out_data(out_data[gen_i]),
          .out_vld (out_vld[gen_i]),
          .out_rdy (out_rdy[gen_i])
        );
      end
    end
    else begin : gen_no_out_pipe
      assign out_data   = s1_fmt_data;
      assign out_vld    = s1_fmt_vld;
      assign s1_fmt_rdy = out_rdy;
    end
  endgenerate


endmodule
