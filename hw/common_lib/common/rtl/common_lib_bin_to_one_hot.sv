// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module transforms a binary value into the corresponding 1-hot vector.
//
// ==============================================================================================

module common_lib_bin_to_one_hot #(
  parameter  ONE_HOT_W = 8,
  localparam CLOG2_ONE_HOT_W = $clog2(ONE_HOT_W)
)
(
  input  logic [CLOG2_ONE_HOT_W-1:0] in_value,
  output logic [ONE_HOT_W-1:0]       out_1h
);

  always_comb begin
    for (int i = 0; i < ONE_HOT_W; i=i+1) begin
      out_1h[i] = (in_value == CLOG2_ONE_HOT_W'(i));
    end
  end

endmodule
