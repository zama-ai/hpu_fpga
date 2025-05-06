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
// ==============================================================================================

module pep_ldg_splitc_dispatch
#(
  parameter  int OP_W           = 32,
  parameter  int IN_COEF        = 8,
  parameter  int OUT_COEF       = 8,
  parameter  int UNIT_COEF      = 4, // Dispatch coefficients unit
  parameter  int OUT0_UNIT_NB   = 1,
  parameter  int OUT1_UNIT_NB   = 3,
  parameter  bit IN_PIPE        = 1'b1,
  parameter  bit OUT_PIPE       = 1'b1
)
(
  input  logic                               clk,        // clock
  input  logic                               s_rst_n,    // synchronous reset

  input  logic [IN_COEF-1:0][OP_W-1:0]       in_data,
  input  logic                               in_vld,
  output logic                               in_rdy,

  output logic [1:0][OUT_COEF-1:0][OP_W-1:0] out_data,
  output logic [1:0]                         out_vld,
  input  logic [1:0]                         out_rdy

);

// ============================================================================================== //
// localparam
// ============================================================================================== //
  generate
    if ((IN_COEF > UNIT_COEF) && (IN_COEF%UNIT_COEF) != 0) begin : _UNSUPPORTED_IN_AND_UNIT_COEF
      $fatal(1,"> ERROR: UNIT_COEF (%0d) should divide IN_COEF (%0d).",UNIT_COEF, IN_COEF);
    end
    if ((IN_COEF < UNIT_COEF) && (UNIT_COEF%IN_COEF) != 0) begin : _UNSUPPORTED_IN_AND_UNIT_COEF2
      $fatal(1,"> ERROR: IN_COEF (%0d) should divide UNIT_COEF (%0d).", IN_COEF, UNIT_COEF);
    end
  endgenerate

// ============================================================================================== //
// IN_PIPE
// ============================================================================================== //
  logic [IN_COEF-1:0][OP_W-1:0] s0_data;
  logic                         s0_vld;
  logic                         s0_rdy;

  generate
    if (IN_PIPE) begin : gen_in_pipe
      fifo_element #(
        .WIDTH          (IN_COEF * OP_W),
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
// Accumulate / Shift register
// ============================================================================================== //
  logic [UNIT_COEF-1:0][OP_W-1:0] s1_data;
  logic                           s1_vld;
  logic                           s1_rdy;

  generate
    if (UNIT_COEF > IN_COEF) begin : gen_acc
      localparam int ACC_NB = UNIT_COEF / IN_COEF;
      localparam int ACC_W  = $clog2(ACC_NB) == 0 ? 1 : $clog2(ACC_NB);

      logic [ACC_NB-2:0][IN_COEF-1:0][OP_W-1:0] s0_acc;
      logic [ACC_NB-2:0][IN_COEF-1:0][OP_W-1:0] s0_accD;
      logic [ACC_W-1:0]                         s0_acc_cnt;
      logic [ACC_W-1:0]                         s0_acc_cntD;
      logic                                     s0_last_acc_cnt;

      assign s0_accD[ACC_NB-2] = (s0_vld && s0_rdy) ? s0_data : s0_acc[ACC_NB-2];
      if (ACC_NB > 2) begin : gen_acc_nb_gt_2
        assign s0_accD[ACC_NB-3:0] = (s0_vld && s0_rdy) ? s0_acc[ACC_NB-2:1] : s0_acc[ACC_NB-3:0];
      end

      assign s0_last_acc_cnt = s0_acc_cnt == (ACC_NB-1);
      assign s0_acc_cntD     = (s0_vld && s0_rdy) ? s0_last_acc_cnt ? '0 : s0_acc_cnt + 1 : s0_acc_cnt;

      assign s1_data = {s0_data,s0_acc};
      assign s1_vld  = s0_vld & s0_last_acc_cnt;
      assign s0_rdy  = ~s0_last_acc_cnt | s1_rdy;

      always_ff @(posedge clk)
        s0_acc <= s0_accD;

      always_ff @(posedge clk)
        if (!s_rst_n) s0_acc_cnt <= '0;
        else          s0_acc_cnt <= s0_acc_cntD;

    end // gen_acc
    else if (UNIT_COEF < IN_COEF) begin : gen_sr
      localparam int SR_NB = IN_COEF / UNIT_COEF;
      localparam int SR_W  = $clog2(SR_NB) == 0 ? 1 : $clog2(SR_NB);

      logic [SR_NB-1:0][UNIT_COEF-1:0][OP_W-1:0] s0_sr;
      logic [SR_W-1:0]                           s0_sr_cnt;
      logic [SR_W-1:0]                           s0_sr_cntD;
      logic                                      s0_last_sr_cnt;

      assign s0_last_sr_cnt = s0_sr_cnt == (SR_NB-1);
      assign s0_sr_cntD     = (s0_rdy && s0_vld) ? '0 :
                              (s1_rdy && s1_vld) ? s0_sr_cnt + 1 : s0_sr_cnt;
      assign s0_sr = s0_data;

      assign s1_data = s0_sr[s0_sr_cnt];
      assign s1_vld  = s0_vld;
      assign s0_rdy  = s1_rdy & s0_last_sr_cnt;

      always_ff @(posedge clk)
        if (!s_rst_n) s0_sr_cnt <= '0;
        else          s0_sr_cnt <= s0_sr_cntD;
    end // gen_sr
    else begin : gen_eq
      assign s1_data = s0_data;
      assign s1_vld  = s0_vld;
      assign s0_rdy  = s1_rdy;
    end
  endgenerate

// ============================================================================================== //
// Dispatch
// ============================================================================================== //
  pep_ldg_dispatch_core
  #(
    .OP_W           (OP_W),
    .UNIT_COEF      (UNIT_COEF),
    .OUT_COEF       (OUT_COEF),
    .OUT0_UNIT_NB   (OUT0_UNIT_NB),
    .OUT1_UNIT_NB   (OUT1_UNIT_NB),
    .IN_PIPE        (1'b1),
    .OUT_PIPE       (OUT_PIPE)
  ) pep_ldg_dispatch_core (
    .clk      (clk),
    .s_rst_n  (s_rst_n),

    .in_data  (s1_data),
    .in_vld   (s1_vld),
    .in_rdy   (s1_rdy),

    .out_data (out_data),
    .out_vld  (out_vld),
    .out_rdy  (out_rdy)
  );

endmodule
