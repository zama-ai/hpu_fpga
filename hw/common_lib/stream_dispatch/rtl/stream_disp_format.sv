// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This sub_module of stream_dispatch does the data formatting between input and output
// that does not have the same data size.
// ==============================================================================================

module stream_disp_format
#(
  parameter int OP_W      = 32,
  parameter int IN_COEF   = 8,
  parameter int OUT_COEF  = 8,
  parameter bit IN_PIPE   = 1'b1
)
(
  input  logic                          clk,        // clock
  input  logic                          s_rst_n,    // synchronous reset

  input  logic [IN_COEF-1:0][OP_W-1:0]  in_data,
  input  logic                          in_vld,
  output logic                          in_rdy,

  output logic [OUT_COEF-1:0][OP_W-1:0] out_data,
  output logic                          out_vld,
  input  logic                          out_rdy
);

// ============================================================================================== //
// localparam
// ============================================================================================== //
  localparam bit USE_OUT_PIPE = IN_COEF == OUT_COEF ? 1'b0 : 1'b1;

// ============================================================================================== //
// Input Pipe
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
// Format
// ============================================================================================== //
  logic [OUT_COEF-1:0][OP_W-1:0] s1_data;
  logic                          s1_vld;
  logic                          s1_rdy;

  generate
    if (IN_COEF < OUT_COEF) begin : gen_acc
      localparam int ACC_NB = OUT_COEF / IN_COEF;
      localparam int ACC_W  = $clog2(ACC_NB)==0 ? 1 : $clog2(ACC_NB);

      // Accumulate ACC_NB words
      logic [ACC_W-1:0] acc_in_cnt;
      logic [ACC_W-1:0] acc_in_cntD;
      logic             acc_last_in_cnt;

      logic             s0_avail;

      assign s0_avail = s0_vld & s0_rdy;

      assign acc_last_in_cnt = acc_in_cnt == (ACC_NB-1);
      assign acc_in_cntD     = s0_avail ? acc_last_in_cnt ? '0 : acc_in_cnt + 1 : acc_in_cnt;

      always_ff @(posedge clk)
        if (!s_rst_n) acc_in_cnt <= '0;
        else          acc_in_cnt <= acc_in_cntD;

      logic [ACC_NB-1:1][IN_COEF-1:0][OP_W-1:0] acc_data;
      logic [ACC_NB-1:1][IN_COEF-1:0][OP_W-1:0] acc_dataD;

      if (ACC_NB > 2) begin
        assign acc_dataD = s0_avail ? {s0_data, acc_data[ACC_NB-1:2]} : acc_data;
      end
      else begin
        assign acc_dataD = s0_avail ? s0_data : acc_data;
      end

      assign s1_data = {s0_data, acc_data};
      assign s1_vld  = acc_last_in_cnt & s0_vld;

      always_ff @(posedge clk)
        acc_data <= acc_dataD;

      assign s0_rdy = ~acc_last_in_cnt | s1_rdy;

    end
    else if (IN_COEF > OUT_COEF) begin : gen_sr
      localparam int SR_DEPTH = IN_COEF / OUT_COEF;
      localparam int SR_DEPTH_W = $clog2(SR_DEPTH) == 0 ? 1 : $clog2(SR_DEPTH);

      logic [SR_DEPTH-1:0][OUT_COEF-1:0][OP_W-1:0] sr_data;
      logic [SR_DEPTH-1:0][OUT_COEF-1:0][OP_W-1:0] sr_data_tmp;
      logic [SR_DEPTH-1:0][OUT_COEF-1:0][OP_W-1:0] sr_dataD;

      logic [SR_DEPTH_W-1:0]                       sr_out_cnt;
      logic [SR_DEPTH_W-1:0]                       sr_out_cntD;
      logic                                        sr_last_out_cnt;

      logic                                        sr_avail;
      logic                                        sr_availD;

      logic                                        s0_avail;

      assign s0_avail = s0_vld & s0_rdy;

      assign sr_last_out_cnt = sr_out_cnt == SR_DEPTH-1;
      assign sr_out_cntD     = (s1_vld && s1_rdy) ? sr_last_out_cnt ? '0 : sr_out_cnt + 1 : sr_out_cnt;
      assign sr_availD       = s0_vld ? 1'b1 :
                               s1_vld && s1_rdy && sr_last_out_cnt ? 1'b0 : sr_avail;

      // Data shifter
      assign sr_data_tmp = sr_data >> (OP_W*OUT_COEF); // Use this way of writing to avoid compilation warning due to parameter for the other branch.
      assign sr_dataD    = s0_avail         ? s0_data :
                           s1_vld && s1_rdy ? sr_data_tmp : sr_data;

      always_ff @(posedge clk)
        if (!s_rst_n) begin
          sr_avail   <= 1'b0;
          sr_out_cnt <= '0;
        end
        else begin
          sr_avail   <= sr_availD;
          sr_out_cnt <= sr_out_cntD;
        end

      always_ff @(posedge clk)
        sr_data    <= sr_dataD;

      assign s1_data    = sr_data[0];
      assign s1_vld     = sr_avail;
      assign s0_rdy     = (sr_last_out_cnt & s1_rdy) | ~sr_avail;

    end
    else begin : gen_eq
      assign s1_data = s0_data;
      assign s1_vld  = s0_vld;
      assign s0_rdy  = s1_rdy;
    end
  endgenerate

// ============================================================================================== //
// Output
// ============================================================================================== //
  generate
    if (USE_OUT_PIPE) begin : gen_out_pipe
      fifo_element #(
        .WIDTH          (OUT_COEF * OP_W),
        .DEPTH          (2),
        .TYPE_ARRAY     (8'h12),
        .DO_RESET_DATA  (0),
        .RESET_DATA_VAL (0)
      ) out_fifo_element (
        .clk     (clk),
        .s_rst_n (s_rst_n),

        .in_data (s1_data),
        .in_vld  (s1_vld),
        .in_rdy  (s1_rdy),

        .out_data(out_data),
        .out_vld (out_vld),
        .out_rdy (out_rdy)
      );
    end
    else begin : gen_no_out_pipe
      assign out_data = s1_data;
      assign out_vld  = s1_vld;
      assign s1_rdy   = out_rdy;
    end
  endgenerate
endmodule
