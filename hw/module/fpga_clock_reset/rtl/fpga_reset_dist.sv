// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
// Used to accommodate and constrain clocks and resets
// ==============================================================================================

(* keep_hierarchy = "yes" *)
module fpga_reset_dist
#(
  parameter bit          RST_POL         = 1'b0, // Active low = 0 or high = 1
  parameter int unsigned INTER_PART_PIPE = 3,    // Latency to the next part
  parameter int unsigned INTRA_PART_PIPE = 3     // Latency to this part
) (
  input logic  clk,
  input logic  rst_in,
  output logic rst_nxt,
  output logic rst_out
);

  generate if(INTER_PART_PIPE > 1) begin: nxt_pipe
    logic [INTER_PART_PIPE-1:0] nxt_rst_sr;

    // Start with resets active out of GLRST
    initial begin
      nxt_rst_sr = {INTER_PART_PIPE{RST_POL}};
    end

    // Distribute the reset using a pipeline per SLR
    always @(posedge clk) begin
      nxt_rst_sr <= {rst_in, nxt_rst_sr[INTER_PART_PIPE-1:1]};
    end

    assign rst_nxt = nxt_rst_sr[0];
  end else if (INTER_PART_PIPE == 1) begin: nxt_pipe_1
    logic [0:0] nxt_rst_sr;

    // Start with resets active out of GLRST
    initial begin
      nxt_rst_sr = RST_POL;
    end

    // Distribute the reset using a pipeline per SLR
    always @(posedge clk) begin
      nxt_rst_sr <= rst_in;
    end

    assign rst_nxt = nxt_rst_sr[0];
  end else begin: no_nxt_pipe
    assign rst_nxt = rst_in;
  end endgenerate

  generate if(INTRA_PART_PIPE > 1) begin: cur_pipe
    logic [INTRA_PART_PIPE-1:0] cur_rst_sr;

    // Start with resets active out of GLRST
    initial begin
      cur_rst_sr = {INTRA_PART_PIPE{RST_POL}};
    end

    // Distribute the reset using a pipeline per SLR
    always @(posedge clk) begin
      cur_rst_sr <= {rst_in, cur_rst_sr[INTRA_PART_PIPE-1:1]};
    end

    assign rst_out = cur_rst_sr[0];
  end else if (INTRA_PART_PIPE == 1) begin: cur_pipe_1
    logic [0:0] cur_rst_sr;

    // Start with resets active out of GLRST
    initial begin
      cur_rst_sr = RST_POL;
    end

    // Distribute the reset using a pipeline per SLR
    always @(posedge clk) begin
      cur_rst_sr <= rst_in;
    end

    assign rst_out = cur_rst_sr[0];
  end else begin: no_cur_pipe
    assign rst_out = rst_in;
  end endgenerate
endmodule
