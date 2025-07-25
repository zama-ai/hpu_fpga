// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
// A simple qualified pipeline
// ==============================================================================================

(* keep_hierarchy = "yes" *)
module hpu_qualified_pipe #(
  parameter int unsigned DEPTH      = 1,
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned CTRL_WIDTH = 32,
  parameter              CTRL_RST   = 32'd0
) (
  input  logic                  clk,
  input  logic                  s_rst_n,
  input  logic [DATA_WIDTH-1:0] in_data,
  input  logic [CTRL_WIDTH-1:0] in_ctrl,
  output logic [DATA_WIDTH-1:0] out_data,
  output logic [CTRL_WIDTH-1:0] out_ctrl
);

  generate if(DEPTH == 0) begin: depth0

    assign out_data = in_data;
    assign out_ctrl = in_ctrl;

  end else if(DEPTH == 1) begin: depth1

    always_ff @(posedge clk) begin
      if(!s_rst_n) begin
        out_ctrl <= CTRL_RST;
      end else begin
        out_ctrl <= in_ctrl;
      end
    end

    always_ff @(posedge clk) begin
      out_data <= in_data;
    end

  end else begin: depthgt1

    logic [DEPTH-1:0][CTRL_WIDTH-1:0] ctrl_sr;
    logic [DEPTH-1:0][DATA_WIDTH-1:0] data_sr;

    always_ff @(posedge clk) begin
      if(!s_rst_n) begin
        ctrl_sr <= CTRL_RST;
      end else begin
        ctrl_sr <= {ctrl_sr[DEPTH-2:0], in_ctrl};
      end
    end

    always_ff @(posedge clk) begin
      data_sr <= {data_sr[DEPTH-2:0], in_data};
    end

    assign out_data = data_sr[DEPTH-1];
    assign out_ctrl = ctrl_sr[DEPTH-1];

  end endgenerate
endmodule
