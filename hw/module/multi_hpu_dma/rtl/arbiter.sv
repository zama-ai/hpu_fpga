// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Simple arbiter
// ----------------------------------------------------------------------------------------------
// TODO: delete
// ==============================================================================================

module arbiter
  import axi_if_common_param_pkg::*;
  import axi_if_shell_axil_pkg::*;
  import hpu_regif_core_eth_2in3_pkg::*;
#(
  parameter int N = 3
) (
  input logic clk,
  input logic resetn,

  input  logic [N-1:0] request,
  output logic [N-1:0] grant
);


  // goal is to have a simple round robin arbiter
  // when a request on one of the lane is up, the module must chose only one
  // pointers are rotated arbitrarily when one request has been granted
  logic         sel;
  logic [N-1:0] pointer;

  assign sel = |grant;

  always_ff @(posedge clk) begin
    if (~resetn) begin
      pointer <= 'h1;
    end else begin
      if (sel) begin
        pointer <= {grant[0], grant[N-1:1]};
      end
    end
  end

  // because we have several request we have a N cascaded structure
  logic [N-1:0] pass;

  assign grant[0] =  request[0] & (pointer[0] | pass[N-1]);
  assign pass[0]  = ~request[0] & (pointer[0] | pass[N-1]);

  generate
    for (genvar gen_i = 1; gen_i<N; gen_i++) begin
      logic var_intermediate;
      always_comb begin
        var_intermediate = pointer[gen_i] | pass[gen_i-1];
        pass[gen_i]      = ~request[gen_i] & var_intermediate;
        grant[gen_i]     = var_intermediate & request[gen_i];
      end
    end
  endgenerate

endmodule
