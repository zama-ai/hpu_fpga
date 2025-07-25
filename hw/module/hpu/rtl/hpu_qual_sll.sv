// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
// A simple qualified sll crossing
// ==============================================================================================

(* keep_hierarchy = "yes" *)
module hpu_qual_sll #(
  parameter int unsigned IN_DEPTH   = 1,
  parameter int unsigned OUT_DEPTH  = 1,
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned CTRL_WIDTH = 32,
  parameter              CTRL_RST   = 32'd0
) (
  input  logic                  in_clk,
  input  logic                  in_s_rst_n,
  input  logic                  out_clk,
  input  logic                  out_s_rst_n,
  input  logic [DATA_WIDTH-1:0] in_data,
  input  logic [CTRL_WIDTH-1:0] in_ctrl,
  output logic [DATA_WIDTH-1:0] out_data,
  output logic [CTRL_WIDTH-1:0] out_ctrl
);

  logic [DATA_WIDTH-1:0] sll_data;
  logic [CTRL_WIDTH-1:0] sll_ctrl;

  hpu_qualified_pipe #(
    .DEPTH      ( IN_DEPTH   ) ,
    .DATA_WIDTH ( DATA_WIDTH ) ,
    .CTRL_WIDTH ( CTRL_WIDTH ) ,
    .CTRL_RST   ( CTRL_RST   )
  ) in_pipe (
    .clk      ( in_clk     ) ,
    .s_rst_n  ( in_s_rst_n ) ,
    .in_data  ( in_data    ) ,
    .in_ctrl  ( in_ctrl    ) ,
    .out_data ( sll_data   ) ,
    .out_ctrl ( sll_ctrl   )
  );

  hpu_qualified_pipe #(
    .DEPTH      ( OUT_DEPTH  ) ,
    .DATA_WIDTH ( DATA_WIDTH ) ,
    .CTRL_WIDTH ( CTRL_WIDTH ) ,
    .CTRL_RST   ( CTRL_RST   )
  ) out_pipe (
    .clk      ( out_clk     ) ,
    .s_rst_n  ( out_s_rst_n ) ,
    .in_data  ( sll_data    ) ,
    .in_ctrl  ( sll_ctrl    ) ,
    .out_data ( out_data    ) ,
    .out_ctrl ( out_ctrl    )
  );

endmodule
