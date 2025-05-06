// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the convertion of a stream rdy/vld type bus into a sequential type bus.
//
//
//
// This module can be used for example at the input of the regfile.
// ==============================================================================================

module stream_to_seq #(
  parameter int WIDTH = 8,
  parameter int IN_NB = 8,
  parameter int SEQ   = 2 // Must divide IN_NB
)
(
  input  logic                        clk,        // clock
  input  logic                        s_rst_n,    // synchronous reset

  input  logic [IN_NB-1:0][WIDTH-1:0] in_data,
  input  logic                        in_vld,
  output logic                        in_rdy,

  output logic [IN_NB-1:0][WIDTH-1:0] out_data,
  output logic [IN_NB-1:0]            out_vld,
  input  logic [IN_NB-1:0]            out_rdy
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
// Sequence
// ============================================================================================== --
  logic [SEQ-1:0][SEQ_COEF_NB-1:0][WIDTH-1:0] in_data_a;
  logic [SEQ-1:0][SEQ_COEF_NB-1:0][WIDTH-1:0] out_data_a;
  logic [SEQ-1:0][SEQ_COEF_NB-1:0]            out_vld_a;

  assign in_data_a = in_data;
  assign out_data  = out_data_a;
  assign out_vld   = out_vld_a;

  assign in_rdy    = out_rdy[0];
  assign out_data_a[0] = in_data_a[0];
  assign out_vld_a[0]  = {SEQ_COEF_NB{in_vld}};


  generate
    for (genvar gen_i=1; gen_i<SEQ; gen_i=gen_i+1) begin : gen_seq_loop
      localparam int SR_DEPTH = gen_i;

      logic [SR_DEPTH-1:0][SEQ_COEF_NB-1:0][WIDTH-1:0] sr;
      logic [SR_DEPTH-1:0][SEQ_COEF_NB-1:0][WIDTH-1:0] srD;
      logic [SR_DEPTH-1:0]                             sr_vld;
      logic [SR_DEPTH-1:0]                             sr_vldD;

      assign srD[0]     = in_data_a[gen_i];
      assign sr_vldD[0] = in_vld & in_rdy;

      if (SR_DEPTH > 1) begin
        assign srD[SR_DEPTH-1:1]     = sr[SR_DEPTH-2:0];
        assign sr_vldD[SR_DEPTH-1:1] = sr_vld[SR_DEPTH-2:0];
      end

      always_ff @(posedge clk)
        sr <= srD;

      always_ff @(posedge clk)
        if (!s_rst_n) sr_vld <= '0;
        else          sr_vld <= sr_vldD;

      assign out_data_a[gen_i] = sr[SR_DEPTH-1];
      assign out_vld_a[gen_i]  = {SEQ_COEF_NB{sr_vld[SR_DEPTH-1]}};
    
// pragma translate_off
      always_ff @(posedge clk)
        if (!s_rst_n) begin
          // do nothing
        end
        else begin
          if (out_vld_a[gen_i]) begin
            assert(out_rdy[gen_i*SEQ_COEF_NB+:SEQ_COEF_NB] == '1)
            else begin
              $fatal(1,"%t > ERROR: Output is not ready on sequential parts.", $time);
            end
          end
        end
// pragma translate_on

    end
  endgenerate

endmodule
