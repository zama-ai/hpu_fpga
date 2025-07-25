// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ==============================================================================================
// Description  : Simple Synchronizer using XPM module
// ----------------------------------------------------------------------------------------------
//
// Wrapper around the XPM synchronizer cell.
//
// Documentation about XPM module can be found here :
// https://docs.amd.com/r/en-US/ug1353-versal-architecture-ai-libraries/XPM_CDC_SINGLE
//
// ==============================================================================================

module xpm_cdc_single_wrapper #(
  // Synchronization stages ---------------------------------------------------------------------
  // Specifies the number of synchronization stages on the CDC path.
  // For proper operation, the input data must be sampled two or more times by destination clock.
  parameter int CDC_SYNC_STAGES  = 2,
  // Input stage
  parameter int SRC_INPUT_REG    = 0,

  // Behavioral simulation ----------------------------------------------------------------------
  // 0 = disable simulation init values
  // 1 = enable simulation init values
  parameter int INIT_SYNC_FF      = 0,

  // Simulation asserts flag --------------------------------------------------------------------
  parameter int SIM_ASSERT_CHK    = 0
  )(
  // Clock
  input  logic src_clk,
  input  logic dest_clk,
  // data
  input  logic src_in,
  output logic dest_out
);
  // Xilinx Parameterized Macro
  xpm_cdc_single #(
    .DEST_SYNC_FF   (CDC_SYNC_STAGES),
    .INIT_SYNC_FF   (INIT_SYNC_FF   ),
    .SIM_ASSERT_CHK (SIM_ASSERT_CHK ),
    .SRC_INPUT_REG  (SRC_INPUT_REG  )
  ) xpm_cdc_single (
    .src_in   ( src_in   ) ,
    .dest_out ( dest_out ) ,
    .src_clk  ( src_clk  ) ,
    .dest_clk ( dest_clk )
  );

endmodule
