// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Performs a modular addition
// ----------------------------------------------------------------------------------------------
//
// Performs an addition z = a + b modulo MOD_M.
// MOD_M is a OP_W word, with bit [OP_W-1] = 1.
//
// LATENCY = IN_PIPE + OUT_PIPE
// ==============================================================================================

module mod_add #(
  parameter  int           OP_W     = 64,
  parameter [OP_W-1:0]     MOD_M    = 2 ** OP_W - 2 ** (OP_W/2) + 1,
  parameter bit            IN_PIPE  = 1'b1, // Recommended
  parameter bit            OUT_PIPE = 1'b1, // Recommended
  parameter int            SIDE_W   = 0, // Side data size. Set to 0 if not used
  parameter [1:0]          RST_SIDE = 0  // If side data is used,
                                         // [0] (1) reset them to 0.
                                         // [1] (1) reset them to 1.

) (
  // System interface
  input  logic              clk,
  input  logic              s_rst_n,
  // Data interface
  input  logic [OP_W-1:0]   a,
  input  logic [OP_W-1:0]   b,
  output logic [OP_W-1:0]   z,
  // Control + side interface - optional
  input  logic              in_avail,
  output logic              out_avail,
  input  logic [SIDE_W-1:0] in_side,
  output logic [SIDE_W-1:0] out_side
);

// ============================================================================================== //
// s0
// ============================================================================================== //
// input pipe
// start the compute :
// c = a + b
// c_minus_m = c - MOD_M
// z = sign(c_minus_m) ? c : c_minus_m

  logic [OP_W-1:0]   s0_a;
  logic [OP_W-1:0]   s0_b;
  logic              s0_avail;
  logic [SIDE_W-1:0] s0_side;
  generate
    if (IN_PIPE) begin : gen_input_pipe
      always_ff @(posedge clk) begin
        s0_a <= a;
        s0_b <= b;
      end
    end else begin : no_gen_input_pipe
      assign s0_a = a;
      assign s0_b = b;
    end
  endgenerate

  common_lib_delay_side #(
    .LATENCY    (IN_PIPE ),
    .SIDE_W     (SIDE_W  ),
    .RST_SIDE   (RST_SIDE)
  ) in_delay_side (
    .clk      (clk      ),
    .s_rst_n  (s_rst_n  ),

    .in_avail (in_avail ),
    .out_avail(s0_avail ),

    .in_side  (in_side  ),
    .out_side (s0_side  )
  );

// Compute
  logic [OP_W:0]   s0_c;
  logic [OP_W+1:0] s0_c_minus_m;
  logic [OP_W-1:0] s0_z;

  assign s0_c         = s0_a + s0_b;
  assign s0_c_minus_m = {1'b0,s0_c} - {2'b00,MOD_M};
  assign s0_z         = s0_c_minus_m[OP_W+1] ? s0_c[OP_W-1:0] : s0_c_minus_m[OP_W-1:0];

// ============================================================================================== //
// s1
// ============================================================================================== //
// Output pipe
  logic [OP_W-1:0]   s1_z;
  logic              s1_avail;
  logic [SIDE_W-1:0] s1_side;
  generate
    if (OUT_PIPE) begin : gen_output_pipe
      always_ff @(posedge clk) begin
        s1_z <= s0_z;
      end
    end else begin : no_gen_output_pipe
      assign s1_z = s0_z;
    end
  endgenerate

  common_lib_delay_side #(
    .LATENCY    (OUT_PIPE),
    .SIDE_W     (SIDE_W  ),
    .RST_SIDE   (RST_SIDE)
  ) s0_delay_side (
    .clk      (clk      ),
    .s_rst_n  (s_rst_n  ),

    .in_avail (s0_avail ),
    .out_avail(s1_avail ),

    .in_side  (s0_side  ),
    .out_side (s1_side  )
  );

  assign z         = s1_z;
  assign out_avail = s1_avail;
  assign out_side  = s1_side;

endmodule
