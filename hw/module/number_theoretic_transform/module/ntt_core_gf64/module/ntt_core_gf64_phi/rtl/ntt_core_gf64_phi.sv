// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the multiplication with phis.
// According to the number of stage iterations different architectures of phi reader are used.
// ==============================================================================================

module ntt_core_gf64_phi
  import common_definition_pkg::*;
  import param_ntt_pkg::*;
  import ntt_core_common_param_pkg::*;
  import ntt_core_gf64_common_param_pkg::*;
#(
  parameter int    RDX_CUT_ID      = 1, // increasing numbering for FWD, decreasing for BWD
                                        // FWD : 1 means ngc
                                        // BWD : 0 means ngc
                                        // Column that follows the phi multiplication
  parameter bit    BWD             = 1'b0,
  parameter bit    IN_PIPE         = 1'b1, // Recommended
  parameter int    ROM_LATENCY     = 2,
  parameter int    LVL_NB          = 2, // Number of interleaved levels
  parameter string TWD_GF64_FILE_PREFIX = $sformatf("memory_file/twiddle/NTT_CORE_ARCH_G64/R%0d_PSI%0d/twd_phi",R,PSI), // For ROM if they are used.
  parameter arith_mult_type_e MULT_TYPE = MULT_CORE, // Multiplication type to use
  parameter int    SIDE_W          = 0, // Side data size. Set to 0 if not used
  parameter [1:0]  RST_SIDE        = 0  // If side data is used,
                                        // [0] (1) reset them to 0.
                                        // [1] (1) reset them to 1.

)
(
    input  logic                            clk,        // clock
    input  logic                            s_rst_n,    // synchronous reset

    input  logic [PSI*R-1:0][MOD_NTT_W+1:0] in_data,
    output logic [PSI*R-1:0][MOD_NTT_W+1:0] out_data,

    input  logic [PSI*R-1:0]                in_avail,
    output logic [PSI*R-1:0]                out_avail,
    input  logic [SIDE_W-1:0]               in_side,
    output logic [SIDE_W-1:0]               out_side

);

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int S_L     = get_s_l(RDX_CUT_ID,BWD);
  localparam int N_L     = 2**S_L; // current working block size
  localparam bit IS_NGC  = is_ngc(RDX_CUT_ID, BWD);
  localparam int ITER_NB = get_iter_nb(RDX_CUT_ID,BWD);

  // Number of iterations from which ROM is used to store the Phis
  localparam int ROM_ITER_THRESHOLD = 128;

  // Shifts are used for friendly twiddles. This occurs when we are processing PHI
  // for cyclic, and if the working block is not greater than 64 (i.e we need powers of
  // w_64)
  localparam bit USE_SHIFT = (ITER_NB < ROM_ITER_THRESHOLD) && !IS_NGC && (N_L <= 64);

// ============================================================================================== --
// Instances
// ============================================================================================== --
  generate
    if (USE_SHIFT) begin : gen_shift
// ---------------------------------------------------------------------------------------------- --
// ntt_core_gf64_phi_shift
// ---------------------------------------------------------------------------------------------- --
      ntt_core_gf64_phi_shift
      #(
        .RDX_CUT_ID (RDX_CUT_ID),
        .BWD        (BWD),
        .LVL_NB     (LVL_NB),
        .IN_PIPE    (IN_PIPE),
        .SIDE_W     (SIDE_W),
        .RST_SIDE   (RST_SIDE)
      ) ntt_core_gf64_phi_shift (
        .clk       (clk),
        .s_rst_n   (s_rst_n),

        .in_data   (in_data),
        .out_data  (out_data),

        .in_avail  (in_avail),
        .out_avail (out_avail),
        .in_side   (in_side),
        .out_side  (out_side)
      );
    end
// ---------------------------------------------------------------------------------------------- --
// ntt_core_gf64_phi_mult
// ---------------------------------------------------------------------------------------------- --
    else begin : gen_mult
      ntt_core_gf64_phi_mult
      #(
        .RDX_CUT_ID         (RDX_CUT_ID),
        .BWD                (BWD),
        .MULT_TYPE          (MULT_TYPE),
        .ROM_ITER_THRESHOLD (ROM_ITER_THRESHOLD),
        .ROM_LATENCY        (ROM_LATENCY),
        .LVL_NB             (LVL_NB),
        .IN_PIPE            (IN_PIPE),
        .TWD_GF64_FILE_PREFIX (TWD_GF64_FILE_PREFIX),
        .SIDE_W             (SIDE_W),
        .RST_SIDE           (RST_SIDE)
      ) ntt_core_gf64_phi_mult  (
        .clk       (clk),
        .s_rst_n   (s_rst_n),

        .in_data   (in_data),
        .out_data  (out_data),

        .in_avail  (in_avail),
        .out_avail (out_avail),
        .in_side   (in_side),
        .out_side  (out_side)
      );

    end
  endgenerate
endmodule
