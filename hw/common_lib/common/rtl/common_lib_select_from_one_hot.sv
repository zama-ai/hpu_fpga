// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module selects part of a vector according to a 1-hot selector.
//
// ==============================================================================================

module common_lib_select_from_one_hot #(
  parameter ONE_HOT_W = 4,
  parameter WIDTH     = 8
)
(
  input  logic [ONE_HOT_W-1:0]            sel_1h,
  input  logic [ONE_HOT_W-1:0][WIDTH-1:0] in_data,
  output logic [WIDTH-1:0]                out_data
);

  always_comb begin
    logic [WIDTH-1:0] d;
    d = '0;
    for (int i = 0; i < ONE_HOT_W; i=i+1) begin
      d = d | (in_data[i] & {WIDTH{sel_1h[i]}});
    end
    out_data = d;
  end

endmodule
