// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
// This module generates a global reset controlled by a config register.
// ==============================================================================================

module hpu_soft_reset (
  input  logic cfg_clk,
  input  logic cfg_srst_n,
  input  logic prc_free_clk,
  input  logic prc_free_srst_n,

  input  logic prc_clk,
  input  logic prc_srst_n,

  input  logic hpu_reset,      // Active high
  output logic hpu_reset_done, // pulse

  // The soft reset output, active low
  output logic soft_prc_srst_n
);

  typedef enum logic [1:0] {
    XXXX = 2'bxx,
    IDLE = 0,
    ASSERT,
    DEASSERT,
    WAIT
  } state_t;

  state_t stateD;
  state_t state;

  logic   soft_reset_tx_nD;
  logic   hpu_reset_doneD;
  logic   soft_reset_tx_n;
  logic   check_bit_rx;

  always_comb begin
    hpu_reset_doneD  = 1'b0;
    soft_reset_tx_nD = 1'b1;
    stateD           = XXXX;
    case(state)
      IDLE: begin
        stateD         = hpu_reset ? ASSERT : IDLE;
      end
      ASSERT: begin
        stateD           = check_bit_rx ? ASSERT : DEASSERT;
        soft_reset_tx_nD = ~check_bit_rx;
      end
      DEASSERT: begin
        stateD          = check_bit_rx ? WAIT : DEASSERT;
        hpu_reset_doneD = check_bit_rx;
      end
      WAIT: begin
        stateD          = hpu_reset ? WAIT : IDLE;
      end
    endcase
  end

  always_ff @(posedge cfg_clk) begin
    if(!cfg_srst_n) begin
      state           <= IDLE;
      soft_reset_tx_n <= 1'b1;
      hpu_reset_done  <= 1'b0;
    end else begin
      state           <= stateD;
      soft_reset_tx_n <= soft_reset_tx_nD;
      hpu_reset_done  <= hpu_reset_doneD;
    end
  end

  xpm_cdc_single_wrapper #(
    // The frequency of the input signal is extremely low, this should be enough
    .CDC_SYNC_STAGES ( 2 ) ,
    .SRC_INPUT_REG   ( 0 )
  ) sync_cfg_prc_free (
    .src_clk  ( cfg_clk         ) ,
    .dest_clk ( prc_free_clk    ) ,
    .src_in   ( soft_reset_tx_n ) ,
    .dest_out ( soft_prc_srst_n )
  );

  // A reset check flag
  logic check_bit_tx;

  always_ff @(posedge prc_clk) begin
    if(!prc_srst_n) begin
      check_bit_tx <= 1'b0;
    end else begin
      check_bit_tx <= 1'b1;
    end
  end

  xpm_cdc_single_wrapper #(
    // The frequency of the input signal is extremely low, this should be enough
    .CDC_SYNC_STAGES ( 2 ) ,
    .SRC_INPUT_REG   ( 0 )
  ) sync_prc_cfg (
    .src_clk  ( prc_clk      ) ,
    .dest_clk ( cfg_clk      ) ,
    .src_in   ( check_bit_tx ) ,
    .dest_out ( check_bit_rx )
  );

endmodule
