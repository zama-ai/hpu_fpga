// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module multiplies the input with a constant. Here the constant is a inverse
// of goldilocks constant (2**a + 2**b -2)
// TODO TODO => only valid for goldilocks with precision = 64+32
// ==============================================================================================

module arith_mult_cst_goldilocks_inv
  import arith_mult_cst_goldilocks_inv_pkg::*;
#(
  parameter int         IN_W           = 64,
  parameter int         CST_W          = 97,
  parameter [CST_W-1:0] CST            = 2**96+2**64-2, // Should be a the inverse of a goldilocks
  parameter             IN_PIPE        = 1'b1,
  parameter int         SIDE_W         = 0,// Side data size. Set to 0 if not used
  parameter [1:0]       RST_SIDE       = 0 // If side data is used,
                                       // [0] (1) reset them to 0.
                                       // [1] (1) reset them to 1.
)
(
  input  logic                  clk,        // clock
  input  logic                  s_rst_n,    // synchronous reset

  input  logic [IN_W-1:0]       a,
  output logic [IN_W+CST_W-1:0] z,
  input  logic                  in_avail,
  output logic                  out_avail,
  input  logic [SIDE_W-1:0]     in_side,
  output logic [SIDE_W-1:0]     out_side

);

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int                     INT_POW_NB  = 1;
  localparam [INT_POW_NB-1:0][31:0]  INT_POW     = get_int_pow();

// ============================================================================================== --
// Check parameters
// ============================================================================================== --
  generate
//    if (CST != 2**(CST_W-1)+2**INT_POW[0]-2) begin: __ERROR_NOT_A_GOLDILOCKS_INV__
//      initial begin
//        $fatal(1,"> ERROR: CST 0x%0x is not a goldilocks inverse number with size %0d.", CST, CST_W);
//      end
//    end
    localparam [96:0] TMP = 2**96+2**64-2;
    if ((CST != TMP) || (CST_W != 97)) begin : __ERROR_NOT_A_GOLDILOCKS_INV__
      $fatal(1,"> ERROR: CST 0x%0x is not a goldilocks inverse number with size %0d.", CST, CST_W);
    end
  endgenerate

// ============================================================================================== --
// functions
// ============================================================================================== --
  // Since CST has the following form:
  // CST = 2**CST_W - 2**INT_POW0 + 2
  // We can retreive INT_POW0
  function automatic [INT_POW_NB-1:0][31:0] get_int_pow();
    bit [INT_POW_NB-1:0][31:0] pow;
    logic [CST_W:0]            tmp;
    tmp = $clog2(CST+2-(2**(CST_W-1)));
    pow[0] = tmp;
    return pow;
  endfunction

// ============================================================================================== --
// arith_mult_cst_goldilocks
// ============================================================================================== --
  // -------------------------------------------------------------------------------------------- //
  // Input pipe
  // -------------------------------------------------------------------------------------------- //
  logic [IN_W-1:0]   s0_data;
  logic              s0_avail;
  logic [SIDE_W-1:0] s0_side;
  generate
    if (IN_PIPE) begin
      always_ff @(posedge clk) begin
        s0_data <= a;
      end
    end else begin
      assign s0_data = a;
    end
  endgenerate

  common_lib_delay_side #(
    .LATENCY    (IN_PIPE),
    .SIDE_W     (SIDE_W),
    .RST_SIDE   (RST_SIDE)
  ) s0_delay_side (
    .clk      (clk      ),
    .s_rst_n  (s_rst_n  ),
                        
    .in_avail (in_avail ),
    .out_avail(s0_avail ),
                        
    .in_side  (in_side  ),
    .out_side (s0_side  )
  );

  // -------------------------------------------------------------------------------------------- //
  // S0 : Compute
  // -------------------------------------------------------------------------------------------- //
  logic [IN_W+CST_W-1:0] s0_result;

  assign s0_result = {s0_data, {CST_W-1{1'b0}}}
                     - {s0_data, 1'b0}
                     + {s0_data, {INT_POW[0]{1'b0}}};


  logic [IN_W+CST_W-1:0] s1_result;
  logic                  s1_avail;
  logic [SIDE_W-1:0]     s1_side;

  always_ff @(posedge clk) begin
    s1_result <= s0_result;
  end

  common_lib_delay_side #(
    .LATENCY    (1),
    .SIDE_W     (SIDE_W),
    .RST_SIDE   (RST_SIDE)
  ) s1_delay_side (
    .clk      (clk          ),
    .s_rst_n  (s_rst_n      ),
    .in_avail (s0_avail     ),
    .out_avail(s1_avail     ),           
    .in_side  (s0_side      ),
    .out_side (s1_side      )
  );

  assign z         = s1_result;
  assign out_avail = s1_avail;
  assign out_side  = s1_side;

endmodule
