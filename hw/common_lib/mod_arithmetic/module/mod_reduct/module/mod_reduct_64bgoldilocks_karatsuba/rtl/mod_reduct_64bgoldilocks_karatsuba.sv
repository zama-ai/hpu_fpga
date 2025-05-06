// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : mod_reduct_64bgoldilocks_karatsuba
// ----------------------------------------------------------------------------------------------
//
// Modular reduction with specific optimisations for the Goldilocks Prime 2^64-2^32+1.
//
// Optimisations:
//  - OP_W, width of input a, is reduced from 128 bits to 98 bits
//
// Can deal with inputs of the form: sums of the 2 results of multiplication of 2 values % MOD_M.
//
// The latency of the module is IN_PIPE + $countone(LAT_PIPE_MH)
//
// ==============================================================================================

module mod_reduct_64bgoldilocks_karatsuba #(
  parameter int          OP_W       = 98, // Uses Multiplier with Goldilocks specific optimisations
                                          // is compatible with reducing sum of 2 64-bit products 
                                          // from the Goldilocks-specific multiplier
  parameter bit          IN_PIPE    = 1,
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
  output logic [63:0]        z,
  // Control + side interface - optional
  input  logic               in_avail,
  output logic               out_avail,

  input  logic [SIDE_W-1:0]  in_side,
  output logic [SIDE_W-1:0]  out_side

);

  import mod_reduct_64bgoldilocks_karatsuba_pkg::*;

  // ============================================================================================ //
  // Localparam
  // ============================================================================================ //

  localparam int          MOD_W      = 64;
  localparam [MOD_W-1:0]  MOD_M      = 2**MOD_W - 2**(MOD_W/2) + 1;

  // Since MOD_M has the following form: 
  // MOD_M = 2**MOD_W - 2**INT_POW + 1
  // We can retreive INT_POW
  localparam int         INT_POW   = $clog2(2**MOD_W+1 - MOD_M);
  localparam int         PROC_W    = 2*MOD_W+1;
  localparam int         INT_W     = MOD_W - INT_POW; // INT stands for intermediate
  localparam int         C_PART_NB = (MOD_W+INT_W-1) / INT_W;
  localparam int         C_ADD_BIT = $clog2(C_PART_NB);

  localparam int         A_DATA_W  = SIDE_W + OP_W;

  localparam [MOD_W:0]   MINUS_MOD_M = ~{1'b0, MOD_M} + 1; // signed

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
      assign s0_side   = 'x;
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
  // s0 : Partial additions
  // ============================================================================================ //
  logic [MOD_W/2:0] s0_msb;     // Sum of two MOD_W/2-bit words
  logic [MOD_W/2:0] s0_lsb_int; // Intermediate sum for calculating the LSBs of result. 
                                // Sum of MOD_W/2-bit word and 2-bit word
  logic [MOD_W/2+1:0] s0_lsb;   // Sub of two (MOD_W/2+1)-bit words

  assign s0_msb = s0_a[63:32] + s0_a[95:64];
  assign s0_lsb_int = s0_a[95:64] + s0_a[OP_W-1:96];
  assign s0_lsb = s0_a[31:0] - s0_lsb_int;


  // ============================================================================================ //
  // s1 : final addition
  // ============================================================================================ //
  logic [MOD_W/2  :0]  s1_msb;
  logic [MOD_W/2+1:0]  s1_lsb;
  logic                s1_avail;
  logic [ SIDE_W-1:0]  s1_side;

  generate
    if (LAT_PIPE_MH[0]) begin : gen_pipe_0
      always_ff @(posedge clk) begin
        s1_msb <= s0_msb;
        s1_lsb <= s0_lsb;
      end
    end
    else begin : no_gen_pipe_0
      assign  s1_msb = s0_msb;
      assign  s1_lsb = s0_lsb;
    end
  endgenerate

  common_lib_delay_side #(
    .LATENCY    (LAT_PIPE_MH[0]),
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

  logic [MOD_W:0] s1_sum;
  assign s1_sum = s1_lsb[MOD_W/2+1] ? (s1_msb << 32) - ({1'b0, ~s1_lsb} + 1)
                                    : (s1_msb << 32) + s1_lsb;

  // ============================================================================================ //
  // s2 : Modulo correction
  // ============================================================================================ //
  logic [MOD_W:0]    s2_sum;
  logic              s2_avail;
  logic [SIDE_W-1:0] s2_side;

  generate
    if (LAT_PIPE_MH[1]) begin : gen_pipe_1
      always_ff @(posedge clk) begin
        s2_sum <= s1_sum[MOD_W:0];
      end
    end
    else begin : no_gen_pipe_1
      assign s2_sum = s1_sum[MOD_W:0];
    end
  endgenerate

  common_lib_delay_side #(
    .LATENCY    (LAT_PIPE_MH[1]),
    .SIDE_W     (SIDE_W  ),
    .RST_SIDE   (RST_SIDE)
  ) s1_delay_side (
    .clk      (clk      ),
    .s_rst_n  (s_rst_n  ),
                        
    .in_avail (s1_avail ),
    .out_avail(s2_avail ),
                        
    .in_side  (s1_side  ),
    .out_side (s2_side  )
  );

  
  logic [MOD_W:0] s2_sum_minus_mod;

  assign s2_sum_minus_mod = s2_sum - MOD_M;

  logic [MOD_W-1:0]  s2_result;

  assign s2_result = s2_sum_minus_mod[MOD_W] ? s2_sum[MOD_W-1:0]
                                             : s2_sum_minus_mod[MOD_W-1:0];

  // ============================================================================================ //
  // s3 : output
  // ============================================================================================ //
  logic [MOD_W-1:0]  s3_result;
  logic              s3_avail;
  logic [SIDE_W-1:0] s3_side;

  generate
    if (LAT_PIPE_MH[2]) begin : gen_pipe_2
      always_ff @(posedge clk) begin
        s3_result <= s2_result;
      end
    end
    else begin : no_gen_pipe_2
      assign s3_result = s2_result;
    end
  endgenerate

  common_lib_delay_side #(
    .LATENCY    (LAT_PIPE_MH[2]),
    .SIDE_W     (SIDE_W  ),
    .RST_SIDE   (RST_SIDE)
  ) s2_delay_side (
    .clk      (clk      ),
    .s_rst_n  (s_rst_n  ),
                        
    .in_avail (s2_avail ),
    .out_avail(s3_avail ),
                        
    .in_side  (s2_side  ),
    .out_side (s3_side  )
  );

  assign z         = s3_result;
  assign out_avail = s3_avail;
  assign out_side  = s3_side;
endmodule

