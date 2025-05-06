// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Performs a Mersenne modular reduction
// ----------------------------------------------------------------------------------------------
//
// Performs a reduction z = a modulo (2^(MOD_W) - 1).
//
// Can deal with input up to 2*MOD_W+1 bits.
// This is the size of the sum of the 2 results of multiplication of 2
// values % MOD_M.
//
// LATENCY : IN_PIPE + $countones(LAT_PIPE_MH)
// ==============================================================================================

module mod_reduct_mersenne #(
  parameter int          MOD_W      = 33,
  parameter [MOD_W-1:0]  MOD_M      = 2**MOD_W - 1,
  parameter int          OP_W       = 67, // Should be in [MOD_W:2*MOD_W+1]
  parameter bit          IN_PIPE    = 1, // Recommended
  parameter int          SIDE_W     = 0, // Side data size. Set to 0 if not used
  parameter [1:0]        RST_SIDE   = 0  // If side data is used,
                                         // [0] (1) reset them to 0.
                                         // [1] (1) reset them to 1.
)
(
    // System interface
    input  logic               clk,
    input  logic               s_rst_n,
    // Data interface
    input  logic [OP_W-1:0]    a,
    output logic [MOD_W-1:0]   z,
    // Control + side interface - optional
    input  logic               in_avail,
    output logic               out_avail,

    input  logic [SIDE_W-1:0]  in_side,
    output logic [SIDE_W-1:0]  out_side

);

  import mod_reduct_mersenne_pkg::*;

  // ============================================================================================ //
  // localparam
  // ============================================================================================ //
  localparam int           PROC_W      = MOD_W*2+1;

  localparam int          A_DATA_W  = SIDE_W + OP_W;
  localparam int          C_DATA_W  = SIDE_W + MOD_W;

  // parameter check
  generate
    if (MOD_M != 2**MOD_W-1) begin : __NOT_A_MERSENNE_MOD__
      $fatal(1, "> ERROR: The modulo is not a Mersenne modulo 0x%0x",MOD_M);
    end
  endgenerate

  // ============================================================================================ //
  // Input registers
  // ============================================================================================ //
  logic [OP_W-1:0]       s0_a;
  logic                  s0_avail;
  logic [SIDE_W-1:0]     s0_side;

  logic [A_DATA_W-1:0]   in_a_data;
  logic [A_DATA_W-1:0]   s0_a_data;

  generate
    if (SIDE_W > 0) begin
      assign in_a_data       = {in_side, a};
      assign {s0_side, s0_a} = s0_a_data;
    end
    else begin
      assign in_a_data = a;
      assign s0_a      = s0_a_data;
    end
  endgenerate

  common_lib_delay_side #(
    .LATENCY    (IN_PIPE ),
    .SIDE_W     (A_DATA_W),
    .RST_SIDE   (RST_SIDE)
  ) in_delay_side (
    .clk      (clk      ),
    .s_rst_n  (s_rst_n  ),
                        
    .in_avail (in_avail ),
    .out_avail(s0_avail ),
                        
    .in_side  (in_a_data),
    .out_side (s0_a_data)
  );


  // ============================================================================================ //
  // s0 : reduction
  // ============================================================================================ //
  // b =  a[2*MOD_W] + a[2*MOD_W-1:MOD_W] + a[MOD_W-1:0]
  // c = b > 2*MOD ? b-2*MOD :
  //     b > MOD   ? b - MOD : b

  logic [PROC_W+MOD_W-1:0] s0_a_ext; // Extend a with 0
  logic [MOD_W:0]          s0_b;
  logic [MOD_W+1:0]        s0_b_minus_m;
  logic [MOD_W+1:0]        s0_b_minus_2m;
  logic [MOD_W-1:0]        s0_c;

  assign s0_a_ext = s0_a; // MSB are extended with 0

  always_comb begin
    logic [MOD_W:0] tmp;
    tmp = s0_a_ext[0+:MOD_W];
    for (int i = MOD_W; i<PROC_W; i=i+MOD_W) begin
      tmp = tmp + s0_a_ext[i+:MOD_W];
    end
    s0_b = tmp;
  end

  assign s0_b_minus_m  = {1'b0, s0_b} - {2'b00, MOD_M};
  assign s0_b_minus_2m = {1'b0, s0_b} - {1'b0, MOD_M, 1'b0};
  assign s0_c          = s0_b_minus_m[MOD_W+1]  ? s0_b[MOD_W-1:0] :
                         s0_b_minus_2m[MOD_W+1] ? s0_b_minus_m[MOD_W-1:0] : s0_b_minus_2m[MOD_W-1:0];

  // Output pipe
  logic [C_DATA_W-1:0] s0_c_data;
  logic [MOD_W-1:0]    s1_c;
  logic [C_DATA_W-1:0] s1_c_data;
  logic                s1_avail;
  logic [SIDE_W-1:0]   s1_side;
  
  generate
    if (SIDE_W > 0) begin
      assign s0_c_data       = {s0_side, s0_c};
      assign {s1_side, s1_c} = s1_c_data;
    end
    else begin
      assign s0_c_data = s0_c;
      assign s1_c      = s1_c_data;
    end
  endgenerate

  common_lib_delay_side #(
    .LATENCY    (LAT_PIPE_MH[0]),
    .SIDE_W     (C_DATA_W),
    .RST_SIDE   (RST_SIDE)
  ) s0_delay_side (
    .clk      (clk      ),
    .s_rst_n  (s_rst_n  ),
                        
    .in_avail (s0_avail ),
    .out_avail(s1_avail ),
                        
    .in_side  (s0_c_data),
    .out_side (s1_c_data)
  );

  assign z         = s1_c;
  assign out_avail = s1_avail;
  assign out_side  = s1_side;

endmodule
