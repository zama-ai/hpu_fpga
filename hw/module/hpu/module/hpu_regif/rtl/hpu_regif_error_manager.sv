// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the error signals, that are exposed on the register
// interface.
// ==============================================================================================

module hpu_regif_error_manager
#(
  parameter int IN_NB      = 1, // Should be <= REG_DATA_W
  parameter int REG_DATA_W = 32
) (
  input  logic                                clk,
  input  logic                                s_rst_n,

  // reg_if
  output logic [REG_DATA_W-1:0]               r_error_upd,
  input  logic                                r_error_wr_en,
  input  logic [REG_DATA_W-1:0]               r_wr_data,

  // from modules
  input  logic [IN_NB-1:0]                    error
);

  logic [IN_NB-1:0] sticky;
  logic [IN_NB-1:0] stickyD;

  always_comb
    for (int i=0; i<IN_NB; i=i+1)
      stickyD[i] = r_error_wr_en ? r_wr_data[i] : error[i] | sticky[i];

  always_ff @(posedge clk)
    if (!s_rst_n) sticky <= '0;
    else          sticky <= stickyD;


  always_comb begin
    r_error_upd = '0;
    r_error_upd[IN_NB-1:0] = sticky;
  end


endmodule
