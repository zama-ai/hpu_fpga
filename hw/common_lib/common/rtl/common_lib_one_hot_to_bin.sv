// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module transforms a one-hot vector into the corresponding binary value.
//
// ==============================================================================================

module common_lib_one_hot_to_bin #(
  parameter  int ONE_HOT_W = 8,
  localparam int WIDTH     = $clog2(ONE_HOT_W) == 0 ? 1 : $clog2(ONE_HOT_W)
)
(
  input  logic [ONE_HOT_W-1:0] in_1h,
  output logic [WIDTH-1:0]     out_value
);

  logic [WIDTH:0] i;
  always_comb begin
    out_value = {WIDTH {1'b0}};
    for (i = '0; int'(i) < ONE_HOT_W; i = i + WIDTH'(1))
      out_value = out_value |  (in_1h[i] ? i[WIDTH-1:0] : {WIDTH {1'b0}});
  end

endmodule // common_lib_one_hot_to_bin
