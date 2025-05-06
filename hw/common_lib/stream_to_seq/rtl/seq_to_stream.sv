// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the convertion of sequential bus type into a stream rdy/vld type bus.
//
//
//
// This module can be used for example at the output of the regfile.
// ==============================================================================================

module seq_to_stream #(
  parameter int WIDTH = 8,
  parameter int IN_NB = 8,
  parameter int SEQ   = 2 // Must divide IN_NB
)
(
  input  logic                        clk,        // clock
  input  logic                        s_rst_n,    // synchronous reset

  input  logic [IN_NB-1:0][WIDTH-1:0] in_data,
  input  logic [IN_NB-1:0]            in_vld,
  output logic [IN_NB-1:0]            in_rdy,

  output logic [IN_NB-1:0][WIDTH-1:0] out_data,
  output logic                        out_vld,
  input  logic                        out_rdy
);

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int SEQ_COEF_NB = IN_NB / SEQ;

// pragma translate_off
  generate
    if ((IN_NB/SEQ)*SEQ != IN_NB) begin : __UNSUPPORTED_SEQ_
      initial begin
        $fatal(1,"> ERROR: SEQ (%0d)  must divide IN_NB (%0d).", SEQ, IN_NB);
      end
    end
  endgenerate
// pragma translate_on

// ============================================================================================== --
// Delay
// ============================================================================================== --
  logic [SEQ-1:0][SEQ_COEF_NB-1:0][WIDTH-1:0] in_data_a;
  logic [SEQ-1:0][SEQ_COEF_NB-1:0]            in_vld_a;
  logic [SEQ-1:0][SEQ_COEF_NB-1:0]            in_rdy_a;

  logic [SEQ-1:0][SEQ_COEF_NB-1:0][WIDTH-1:0] out_data_a;
  logic [SEQ-1:0][SEQ_COEF_NB-1:0]            out_vld_a;
  logic [SEQ-1:0][SEQ_COEF_NB-1:0]            out_rdy_a;

  logic [SEQ-1:0]                             out_vld_a_tmp;
  assign in_data_a = in_data;
  assign in_vld_a  = in_vld;
  assign in_rdy    = in_rdy_a;

  assign out_data  = out_data_a;
  assign out_vld   = &out_vld_a_tmp;

  always_comb
    for (int i=0; i<SEQ; i=i+1)
      out_vld_a_tmp[i] = out_vld_a[i][0];

  always_comb
    for (int i=0; i<SEQ; i=i+1) begin
      for (int j=0; j<SEQ_COEF_NB; j=j+1) begin
        logic [SEQ-1:0] mask;
        mask = 1 << i;
        out_rdy_a[i][j] = out_rdy & (&(mask | out_vld_a_tmp));
      end
    end

  generate
    for (genvar gen_s=0; gen_s<SEQ; gen_s=gen_s+1) begin : gen_seq_loop
      localparam int DEPTH = SEQ-1-gen_s;
      for (genvar gen_c=0; gen_c<SEQ_COEF_NB; gen_c=gen_c+1) begin : gen_coef_loop

        fifo_element #(
          .WIDTH          (WIDTH),
          .DEPTH          (DEPTH),
          .TYPE_ARRAY     ({DEPTH{4'h1}}),
          .DO_RESET_DATA  (0),
          .RESET_DATA_VAL (0)
        ) regf_req_fifo_element (
          .clk     (clk),
          .s_rst_n (s_rst_n),

          .in_data (in_data_a[gen_s][gen_c]),
          .in_vld  (in_vld_a[gen_s][gen_c]),
          .in_rdy  (in_rdy_a[gen_s][gen_c]),

          .out_data(out_data_a[gen_s][gen_c]),
          .out_vld (out_vld_a[gen_s][gen_c]),
          .out_rdy (out_rdy_a[gen_s][gen_c])
        );
      end
    end
  endgenerate

endmodule
