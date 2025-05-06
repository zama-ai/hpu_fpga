// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Modular accumulation
// ==============================================================================================

module mod_acc #(
  parameter int            OP_W     = 33,
  parameter [OP_W-1:0]     MOD_M    = 2 ** 33 - 2 ** 20 + 1,
  parameter bit            IN_PIPE  = 1'b1, // Recommended
  parameter bit            OUT_PIPE = 1'b1, // Recommended
  parameter int            SIDE_W   = 0, // Side data size. Set to 0 if not used
  parameter [1:0]          RST_SIDE = 0  // If side data is used,
                                         // [0] (1) reset them to 0.
                                         // [1] (1) reset them to 1.


) (
  // System interface
  input               clk,
  input               s_rst_n,
  // Data interface
  input  [OP_W-1:0]   in_op,
  output [OP_W-1:0]   out_op,
  // Control interface - mandatory
  input               in_sol,    // First coefficient
  input               in_eol,    // Last coefficient
  input               in_avail,
  output              out_avail,
  // Side signal - Only the last one (eol=1) is output along the result.
  input  [SIDE_W-1:0] in_side,
  output [SIDE_W-1:0] out_side
);

  // ============================================================================================== --
  // localparam
  // ============================================================================================== --
  // None 
  // ============================================================================================== --
  // mod_acc
  // ============================================================================================== --
  // ---------------------------------------------------------------------------------------------- --
  // s0 : compute the remaining : distance between the result and the modulo
  // ---------------------------------------------------------------------------------------------- --
  //== Input pipe
  logic [OP_W-1:0]   s0_op;
  logic              s0_sol;
  logic              s0_eol;
  logic              s0_avail;
  logic [SIDE_W-1:0] s0_side;

  generate
    if (IN_PIPE) begin : gen_input_pipe
      always_ff @(posedge clk) begin
        s0_op  <= in_op;
        s0_sol <= in_sol;
        s0_eol <= in_eol;
      end
    end
    else begin : no_gen_input_pipe
      assign s0_op    = in_op;
      assign s0_sol   = in_sol;
      assign s0_eol   = in_eol;
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

  //== Compute
  logic [OP_W-1:0] s0_r;
  logic [OP_W-1:0] s0_remain;
  logic [OP_W-1:0] s0_remainD;
  logic [  OP_W:0] s0_diff;
  logic [OP_W-1:0] s0_diffB;
  logic [OP_W-1:0] s0_result;
  logic            s0_out_avail;
  logic            s0_out_availD;

  assign s0_r          = s0_sol ? MOD_M : s0_remain;
  assign s0_diff       = {1'b0, s0_r} - {1'b0, s0_op};
  assign s0_diffB      = s0_r + MOD_M - s0_op;
  assign s0_remainD    = s0_avail ? (s0_diff[OP_W] || (s0_diff==0)) ? s0_diffB : s0_diff[OP_W-1:0] : s0_remain;
  assign s0_result     = MOD_M - s0_remain;
  // The result in s0 is available 1 cycle after receiving eol.
  assign s0_out_availD = s0_avail & s0_eol;

  always_ff @(posedge clk) s0_remain <= s0_remainD;

  logic [SIDE_W-1:0] s0_out_side;
  common_lib_delay_side #(
    .LATENCY    (1       ),
    .SIDE_W     (SIDE_W  ),
    .RST_SIDE   (RST_SIDE)
  ) s0_delay_side (
    .clk      (clk      ),
    .s_rst_n  (s_rst_n  ),
                        
    .in_avail (s0_out_availD ),
    .out_avail(s0_out_avail  ),
                        
    .in_side  (s0_side  ),
    .out_side (s0_out_side)
  );

  // ---------------------------------------------------------------------------------------------- --
  // s1 store the result
  // ---------------------------------------------------------------------------------------------- --
  logic [OP_W-1:0]   s1_result;
  logic              s1_avail;
  logic [SIDE_W-1:0] s1_side;

  generate
    if (OUT_PIPE) begin : gen_output_pipe
      always_ff @(posedge clk) s1_result <= s0_result;
    end
    else begin
      assign s1_result = s0_result;
    end
  endgenerate

  common_lib_delay_side #(
    .LATENCY    (OUT_PIPE),
    .SIDE_W     (SIDE_W  ),
    .RST_SIDE   (RST_SIDE)
  ) s0_out_delay_side (
    .clk      (clk         ),
    .s_rst_n  (s_rst_n     ),
                        
    .in_avail (s0_out_avail),
    .out_avail(s1_avail    ),
                        
    .in_side  (s0_out_side ),
    .out_side (s1_side     )
  );

  assign out_op    = s1_result;
  assign out_avail = s1_avail;
  assign out_side  = s1_side;

endmodule
