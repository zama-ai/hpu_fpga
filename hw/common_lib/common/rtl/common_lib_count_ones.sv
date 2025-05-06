// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module extract the number of one in a vector
//
// ==============================================================================================

module common_lib_count_ones #(
  parameter  int MULTI_HOT_W = 8,
  localparam int WIDTH     = $clog2(MULTI_HOT_W) == 0 ? 1 : $clog2(MULTI_HOT_W)
)
(
  input  logic [MULTI_HOT_W-1:0] in_mh,
  output logic [WIDTH: 0]     out_cnt
);

  logic [WIDTH: 0] count_ones;
  always_comb begin
    count_ones = '0;
    foreach(in_mh[idx]) begin
      count_ones += WIDTH'(in_mh[idx]);
    end
  end

  assign out_cnt = count_ones;

endmodule // common_lib_count_ones
