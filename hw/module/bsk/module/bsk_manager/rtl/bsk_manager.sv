// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the management of the bootstrapping key (BSK).
// It delivers the keys at the pace given by the core.
// The host fills the values. They should be valid before running the blind rotation.
// Note that the keys should be given in reverse order (R,N).
// Also note that a unique BSK is used for the process.
// Xilinx UltraRAM are used (72x4096) RAMs.
// ==============================================================================================

module bsk_manager
  import param_tfhe_pkg::*;
  import top_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import ntt_core_common_param_pkg::*;
  import bsk_mgr_common_param_pkg::*;
#(
  parameter  int OP_W          = 32,
  parameter  int RAM_LATENCY   = 1+2 // URAM
)
(
  input  logic                                            clk,        // clock
  input  logic                                            s_rst_n,    // synchronous reset

  input  logic                                            reset_cache,

  output logic [PSI-1:0][R-1:0][GLWE_K_P1-1:0][OP_W-1:0]  bsk,
  output logic [PSI-1:0][R-1:0][GLWE_K_P1-1:0]            bsk_vld,
  input  logic [PSI-1:0][R-1:0][GLWE_K_P1-1:0]            bsk_rdy,

  // Broadcast from acc
  input  logic [BR_BATCH_CMD_W-1:0]                       batch_cmd,
  input  logic                                            batch_cmd_avail, // pulse

  // Write interface
  input  logic [BSK_CUT_NB-1:0]                           wr_en, // Write coefficients for 1 (stage iter,GLWE) at a time.
  input  logic [BSK_CUT_NB-1:0][BSK_CUT_FCOEF_NB-1:0][OP_W-1:0] wr_data,
  input  logic [BSK_CUT_NB-1:0][BSK_RAM_ADD_W-1:0]        wr_add,
  input  logic [BSK_CUT_NB-1:0][GLWE_K_P1_W-1:0]          wr_g_idx,
  input  logic [BSK_CUT_NB-1:0][BSK_SLOT_W-1:0]           wr_slot,
  input  logic [BSK_CUT_NB-1:0][LWE_K_W-1:0]              wr_br_loop,

  // Error
  output pep_bsk_error_t                                  bsk_mgr_error
);

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int URAM_W         = 72; // ultraRAM width
  localparam int RAM_RD_NB_TMP  = URAM_W / OP_W;
  localparam int RAM_RD_NB      = BSK_CUT_FCOEF_NB == 1 ? 1 :
                                  R / RAM_RD_NB_TMP > 0 ? RAM_RD_NB_TMP : R;

// ============================================================================================== --
// bsk_manager
// ============================================================================================== --
// ---------------------------------------------------------------------------------------------- --
// Input pipe
// ---------------------------------------------------------------------------------------------- --
  br_batch_cmd_t         sm1_batch_cmd;
  logic                  sm1_batch_cmd_avail;
  logic                  sm1_wr_en;
  logic [BSK_SLOT_W-1:0] sm1_wr_slot;
  logic [LWE_K_W-1:0]    sm1_wr_br_loop;

  logic                  do_reset;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      sm1_batch_cmd_avail <= 1'b0;
      sm1_wr_en           <= 1'b0;
      do_reset            <= 1'b0;
    end
    else begin
      sm1_batch_cmd_avail <= batch_cmd_avail;
      sm1_wr_en           <= wr_en[0]; // Use the first cut control to keep track of the slot filling.
      do_reset            <= reset_cache;
    end

  always_ff @(posedge clk) begin
    sm1_batch_cmd  <= batch_cmd;
    sm1_wr_slot    <= wr_slot[0];
    sm1_wr_br_loop <= wr_br_loop[0];
  end

// ---------------------------------------------------------------------------------------------- --
// Sm1 : Search slot
// ---------------------------------------------------------------------------------------------- --
  logic [BSK_SLOT_NB-1:0][LWE_K_W-1:0] slot_br_loop_a;
  logic [BSK_SLOT_NB-1:0][LWE_K_W-1:0] slot_br_loop_aD;

  // Use an avail bit to avoid initial false positive, since the slot_br_loop_a has 'x values after reset.
  logic [BSK_SLOT_NB-1:0] slot_avail_a;
  logic [BSK_SLOT_NB-1:0] slot_avail_aD;

  logic [BSK_SLOT_NB-1:0] sm1_wr_slot_1h;

  always_comb
    for (int i=0; i<BSK_SLOT_NB; i=i+1)
      sm1_wr_slot_1h[i] = (sm1_wr_slot == i) ? 1'b1 : 1'b0;

  always_comb
    for (int i=0; i<BSK_SLOT_NB; i=i+1) begin
        slot_br_loop_aD[i] = (sm1_wr_en && sm1_wr_slot_1h[i]) ? sm1_wr_br_loop : slot_br_loop_a[i];
        slot_avail_aD[i]   = (sm1_wr_en & sm1_wr_slot_1h[i]) | slot_avail_a[i];
    end

  always_ff @(posedge clk)
    if (!s_rst_n || do_reset) slot_avail_a <= '0;
    else                      slot_avail_a <= slot_avail_aD;

  always_ff @(posedge clk)
    slot_br_loop_a <= slot_br_loop_aD;

  logic [BSK_SLOT_NB-1:0] sm1_slot_1h;
  logic [BSK_SLOT_W-1:0]  sm1_slot;

  always_comb
    for (int i=0; i<BSK_SLOT_NB; i=i+1)
      sm1_slot_1h[i] = (sm1_batch_cmd.br_loop == slot_br_loop_a[i]) & slot_avail_a[i];

  common_lib_one_hot_to_bin #(
    .ONE_HOT_W(BSK_SLOT_NB)
  ) common_lib_one_hot_to_bin (
    .in_1h     (sm1_slot_1h),
    .out_value (sm1_slot)
  );

  br_batch_cmd_t          sm2_batch_cmd;
  logic                   sm2_batch_cmd_avail;
  logic [BSK_SLOT_W-1:0]  sm2_slot;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      sm2_batch_cmd_avail <= 1'b0;
    end
    else begin
      sm2_batch_cmd_avail <= sm1_batch_cmd_avail;
    end

  always_ff @(posedge clk) begin
    sm2_batch_cmd  <= sm1_batch_cmd;
    sm2_slot       <= sm1_slot;
  end

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      if (sm1_batch_cmd_avail) begin
        assert($countones(sm1_slot_1h) == 1)
        else begin
          $fatal(1,"%t > ERROR: batch_cmd does not match a unique slot! (sm1_slot_1h=0x%x)", $time, sm1_slot_1h);
        end
      end
    end
// pragma translate_on


// ---------------------------------------------------------------------------------------------- --
// batch_cmd FIFO
// ---------------------------------------------------------------------------------------------- --
// Use a small FIFO to store the commands that have to be processed.
// Note that this FIFO does not need to be very deep, it depends on the number of batches that can
// be processed in parallel.
  br_batch_cmd_t                    s0_batch_cmd;
  logic [BSK_RAM_ADD_W-1:0]         s0_batch_add_ofs;
  logic                             s0_batch_cmd_vld;
  logic                             s0_batch_cmd_rdy;
  logic [BSK_CUT_NB-1:0]            s0_batch_cmd_rdy_a;

  logic                             sm2_batch_cmd_rdy;
  logic [BSK_RAM_ADD_W-1:0]         sm2_batch_add_ofs;

  assign sm2_batch_add_ofs = sm2_slot * BSK_SLOT_DEPTH;

  assign s0_batch_cmd_rdy = s0_batch_cmd_rdy_a[0];
  fifo_reg #(
    .WIDTH       (BR_BATCH_CMD_W + BSK_RAM_ADD_W),
    .DEPTH       (BATCH_CMD_BUFFER_DEPTH-1), // -1 because using output pipe
    .LAT_PIPE_MH ({1'b1, 1'b1})
  ) cmd_fifo(
    .clk     (clk),
    .s_rst_n (s_rst_n),

    .in_data ({sm2_batch_add_ofs, sm2_batch_cmd}),
    .in_vld  (sm2_batch_cmd_avail),
    .in_rdy  (sm2_batch_cmd_rdy),

    .out_data({s0_batch_add_ofs,s0_batch_cmd}),
    .out_vld (s0_batch_cmd_vld),
    .out_rdy (s0_batch_cmd_rdy)
  );

//pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // Do nothing
    end
    else begin
      assert(s0_batch_cmd_rdy_a == '0 || s0_batch_cmd_rdy_a == '1)
      else $fatal(1,"%t > ERROR: All RAMs s0_batch_cmd_rdy are not equal!",$time);
    end
//pragma translate_on
// ---------------------------------------------------------------------------------------------- --
// Duplicate code for each group if PSI*R RAMs to ease P&R
// ---------------------------------------------------------------------------------------------- --
// Cast
  logic [PSI*R-1:0][GLWE_K_P1-1:0][OP_W-1:0]  bsk_tmp;
  logic [PSI*R-1:0][GLWE_K_P1-1:0]            bsk_vld_tmp;
  logic [PSI*R-1:0][GLWE_K_P1-1:0]            bsk_rdy_tmp;

  assign bsk         = bsk_tmp;
  assign bsk_vld     = bsk_vld_tmp;
  assign bsk_rdy_tmp = bsk_rdy;

  generate
    for (genvar gen_c=0; gen_c < BSK_CUT_NB; gen_c=gen_c+1) begin : gen_cut_loop
      bsk_mgr_cut
      #(
        .OP_W        (OP_W),
        .RAM_RD_NB   (RAM_RD_NB),
        .RAM_LATENCY (RAM_LATENCY)
      ) bsk_mgr_cut (
        .clk             (clk),
        .s_rst_n         (s_rst_n),

        .bsk             (bsk_tmp[gen_c*BSK_CUT_FCOEF_NB+:BSK_CUT_FCOEF_NB]),
        .bsk_vld         (bsk_vld_tmp[gen_c*BSK_CUT_FCOEF_NB+:BSK_CUT_FCOEF_NB]),
        .bsk_rdy         (bsk_rdy_tmp[gen_c*BSK_CUT_FCOEF_NB+:BSK_CUT_FCOEF_NB]),

        .wr_en           (wr_en[gen_c]),
        .wr_data         (wr_data[gen_c]),
        .wr_add          (wr_add[gen_c]),
        .wr_g_idx        (wr_g_idx[gen_c]),

        .s0_batch_cmd    (s0_batch_cmd),
        .s0_batch_add_ofs(s0_batch_add_ofs),
        .s0_batch_cmd_vld(s0_batch_cmd_vld),
        .s0_batch_cmd_rdy(s0_batch_cmd_rdy_a[gen_c])
      );
    end
  endgenerate

// ---------------------------------------------------------------------------------------------- --
// Errors
// ---------------------------------------------------------------------------------------------- --
  pep_bsk_error_t bsk_mgr_errorD;

  logic error_cmd_overflow;

  always_comb begin
    bsk_mgr_errorD         = '0;
    bsk_mgr_errorD.cmd_ovf = error_cmd_overflow;
  end

  always_ff @(posedge clk)
    if (!s_rst_n) bsk_mgr_error <= '0;
    else          bsk_mgr_error <= bsk_mgr_errorD;

  // The FIFO should always be ready for an input command.
  logic error_cmd_overflowD;

  assign error_cmd_overflowD  = sm2_batch_cmd_avail & ~sm2_batch_cmd_rdy;
  always_ff @(posedge clk)
    if (!s_rst_n) error_cmd_overflow  <= 1'b0;
    else          error_cmd_overflow  <= error_cmd_overflowD;

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      if (error_cmd_overflow)
        $display("%t > WARNING: BSK_MANAGER error_cmd_overflow", $time);
    end
// pragma translate_on
endmodule
