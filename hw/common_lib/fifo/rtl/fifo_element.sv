// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// FIFO composed by elementary FIFO with depth = 1.
//
// Parameters:
//   WIDTH : data width
//   DEPTH : Number of fifo element
//   TYPE_ARRAY  : fifo element types, each fifo elt type is defined by a 4b digit
//   TYPE_ARRAY[0]: type of 1st fifo_element equal to 1,2 or 3 on 4 lsb bits of TYPE_ARRAY
//           1 : out_data and out_vld paths are register output
//           2 : in_rdy path is register output
//           3 : out_data, out_vld and in_rdy  are register output. Can process 1 data every 2
//               cycles.
//   DO_RESET_DATA : (1) reset data width RESET_DATA_VAL
//                   (0) do not reset data
//   RESET_DATA_VAL : value used to reset the data. Used when DO_RESET_DATA = 1
// ==============================================================================================

module fifo_element #(
  parameter int                  WIDTH          = 1,
  parameter int                  DEPTH          = 1,
  parameter     [DEPTH-1:0][3:0] TYPE_ARRAY     = 4'h1,
  parameter bit                  DO_RESET_DATA  = 0,
  parameter     [WIDTH-1:0]      RESET_DATA_VAL = 0
) (
  input              clk,     // clock
  input              s_rst_n, // synchronous reset

  input  [WIDTH-1:0] in_data,
  input              in_vld,
  output             in_rdy,

  output [WIDTH-1:0] out_data,
  output             out_vld,
  input              out_rdy
);

  // ============================================================================================== --
  // fifo_element
  // ============================================================================================== --
  logic [DEPTH:0][WIDTH-1:0] data;
  logic [DEPTH:0]            vld;
  logic [DEPTH:0]            rdy;

  assign data[0]    = in_data;
  assign vld[0]     = in_vld;
  assign in_rdy     = rdy[0];
  assign rdy[DEPTH] = out_rdy;
  assign out_data   = data[DEPTH];
  assign out_vld    = vld[DEPTH];
  genvar gen_i;
  generate
    for (gen_i = 0; gen_i < DEPTH; gen_i = gen_i + 1) begin : loop_gen
      if (TYPE_ARRAY[gen_i] == 4'h1) begin : type1_gen
        fifo_element_type1 #(
          .WIDTH         (WIDTH),
          .DO_RESET_DATA (DO_RESET_DATA),
          .RESET_DATA_VAL(RESET_DATA_VAL)
        ) fifo_element (
          .clk     (clk),
          .s_rst_n (s_rst_n),

          .in_data (data[gen_i]),
          .in_vld  (vld[gen_i]),
          .in_rdy  (rdy[gen_i]),

          .out_data(data[gen_i+1]),
          .out_vld (vld[gen_i+1]),
          .out_rdy (rdy[gen_i+1])
        );
      end else if (TYPE_ARRAY[gen_i] == 4'h2) begin : type2_gen
        fifo_element_type2 #(
          .WIDTH         (WIDTH),
          .DO_RESET_DATA (DO_RESET_DATA),
          .RESET_DATA_VAL(RESET_DATA_VAL)
        ) fifo_element (
          .clk     (clk),
          .s_rst_n (s_rst_n),

          .in_data (data[gen_i]),
          .in_vld  (vld[gen_i]),
          .in_rdy  (rdy[gen_i]),

          .out_data(data[gen_i+1]),
          .out_vld (vld[gen_i+1]),
          .out_rdy (rdy[gen_i+1])
        );
      end else if (TYPE_ARRAY[gen_i] == 4'h3) begin : type3_gen
        fifo_element_type3 #(
          .WIDTH         (WIDTH),
          .DO_RESET_DATA (DO_RESET_DATA),
          .RESET_DATA_VAL(RESET_DATA_VAL)
        ) fifo_element (
          .clk     (clk),
          .s_rst_n (s_rst_n),

          .in_data (data[gen_i]),
          .in_vld  (vld[gen_i]),
          .in_rdy  (rdy[gen_i]),

          .out_data(data[gen_i+1]),
          .out_vld (vld[gen_i+1]),
          .out_rdy (rdy[gen_i+1])
        );
      end else begin
        $fatal(1,"> ERROR:  Unsupported type: %0d. Should be 1,2 or 3", TYPE_ARRAY[gen_i]);
      end
    end
  endgenerate
endmodule

