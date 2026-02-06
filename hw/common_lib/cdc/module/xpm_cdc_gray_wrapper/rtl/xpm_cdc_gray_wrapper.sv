// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ==============================================================================================
// Description  : Gray Code Synchronizer using XPM module
// ----------------------------------------------------------------------------------------------
//
// Wrapper around the XPM gray code synchronizer cell for multi-bit CDC.
// Uses gray encoding to safely transfer counter/pointer values across clock domains.
//
// Because of [XPM_CDC 2-3] WIDTH (XXX) is outside of valid range of 2-32 we complexify a bit this
// wrapper to support WIDTH > 32 by internally splitting the data into chunks.
//
// Documentation about XPM module can be found here :
// https://docs.amd.com/r/en-US/ug974-vivado-ultrascale-libraries/XPM_CDC_GRAY
//
// ==============================================================================================

module xpm_cdc_gray_wrapper #(
  // Data width ---------------------------------------------------------------------------------
  // Specifies the width of the binary value to be transferred.
  // This wrapper supports any width >= 2 (internally splits if > 32)
  parameter int WIDTH            = 2,

  // Chunk width for splitting large buses ------------------------------------------------------
  // XPM_CDC_GRAY supports 2-32, so we use 32 as default chunk size
  parameter int CHUNK_WIDTH      = 32,

  // Synchronization stages ---------------------------------------------------------------------
  // Specifies the number of synchronization stages on the CDC path.
  // Valid range: 2-10
  parameter int CDC_SYNC_STAGES  = 4,

  // Registered output --------------------------------------------------------------------------
  // 0 = combinatorial output
  // 1 = registered output (adds one cycle latency but improves timing)
  parameter int REG_OUTPUT       = 0,

  // Behavioral simulation ----------------------------------------------------------------------
  // 0 = disable simulation init values
  // 1 = enable simulation init values
  parameter int INIT_SYNC_FF     = 0,

  // Simulation asserts flag --------------------------------------------------------------------
  // 0 = disable simulation messages
  // 1 = enable simulation messages
  parameter int SIM_ASSERT_CHK   = 0,

  // Lossless check -----------------------------------------------------------------------------
  // 0 = disable lossless check
  // 1 = enable lossless check (simulation only)
  parameter int SIM_LOSSLESS_GRAY_CHK = 0
)(
  // Source clock domain
  input  logic             src_clk,
  input  logic [WIDTH-1:0] src_in,

  // Destination clock domain
  input  logic             dest_clk,
  output logic [WIDTH-1:0] dest_out
);

  // Number of full chunks and remaining bits
  localparam int NB_CHUNKS      = WIDTH / CHUNK_WIDTH;
  localparam int REMAINING_BITS = WIDTH % CHUNK_WIDTH;
  localparam int NB_INSTANCES   = NB_CHUNKS + (REMAINING_BITS > 1 ? 1 : 0);

  // Handle single-bit remainder separately (xpm_cdc_gray requires WIDTH >= 2)
  localparam int HAS_SINGLE_BIT = (REMAINING_BITS == 1) ? 1 : 0;

  generate
    if (WIDTH <= CHUNK_WIDTH) begin : gen_single
      // Simple case: width fits in one xpm_cdc_gray instance
      xpm_cdc_gray #(
        .DEST_SYNC_FF          (CDC_SYNC_STAGES      ),
        .INIT_SYNC_FF          (INIT_SYNC_FF         ),
        .REG_OUTPUT            (REG_OUTPUT           ),
        .SIM_ASSERT_CHK        (SIM_ASSERT_CHK       ),
        .SIM_LOSSLESS_GRAY_CHK (SIM_LOSSLESS_GRAY_CHK),
        .WIDTH                 (WIDTH                )
      ) xpm_cdc_gray_inst (
        .src_clk      (src_clk ),
        .src_in_bin   (src_in  ),
        .dest_clk     (dest_clk),
        .dest_out_bin (dest_out)
      );
    end else begin : gen_split
      // Split into multiple chunks

      // Full chunks
      for (genvar i = 0; i < NB_CHUNKS; i++) begin : gen_chunk
        xpm_cdc_gray #(
          .DEST_SYNC_FF          (CDC_SYNC_STAGES      ),
          .INIT_SYNC_FF          (INIT_SYNC_FF         ),
          .REG_OUTPUT            (REG_OUTPUT           ),
          .SIM_ASSERT_CHK        (SIM_ASSERT_CHK       ),
          .SIM_LOSSLESS_GRAY_CHK (SIM_LOSSLESS_GRAY_CHK),
          .WIDTH                 (CHUNK_WIDTH          )
        ) xpm_cdc_gray_inst (
          .src_clk      (src_clk),
          .src_in_bin   (src_in[i*CHUNK_WIDTH +: CHUNK_WIDTH]),
          .dest_clk     (dest_clk),
          .dest_out_bin (dest_out[i*CHUNK_WIDTH +: CHUNK_WIDTH])
        );
      end

      // Remaining bits (if > 1)
      if (REMAINING_BITS > 1) begin : gen_remainder
        xpm_cdc_gray #(
          .DEST_SYNC_FF          (CDC_SYNC_STAGES      ),
          .INIT_SYNC_FF          (INIT_SYNC_FF         ),
          .REG_OUTPUT            (REG_OUTPUT           ),
          .SIM_ASSERT_CHK        (SIM_ASSERT_CHK       ),
          .SIM_LOSSLESS_GRAY_CHK (SIM_LOSSLESS_GRAY_CHK),
          .WIDTH                 (REMAINING_BITS       )
        ) xpm_cdc_gray_inst (
          .src_clk      (src_clk),
          .src_in_bin   (src_in[NB_CHUNKS*CHUNK_WIDTH +: REMAINING_BITS]),
          .dest_clk     (dest_clk),
          .dest_out_bin (dest_out[NB_CHUNKS*CHUNK_WIDTH +: REMAINING_BITS])
        );
      end

      // Single remaining bit (use xpm_cdc_single since xpm_cdc_gray requires WIDTH >= 2)
      if (REMAINING_BITS == 1) begin : gen_single_bit
        xpm_cdc_single #(
          .DEST_SYNC_FF   (CDC_SYNC_STAGES),
          .INIT_SYNC_FF   (INIT_SYNC_FF   ),
          .SIM_ASSERT_CHK (SIM_ASSERT_CHK ),
          .SRC_INPUT_REG  (0              )
        ) xpm_cdc_single_inst (
          .src_clk  (src_clk),
          .src_in   (src_in[NB_CHUNKS*CHUNK_WIDTH]),
          .dest_clk (dest_clk),
          .dest_out (dest_out[NB_CHUNKS*CHUNK_WIDTH])
        );
      end
    end
  endgenerate

endmodule
