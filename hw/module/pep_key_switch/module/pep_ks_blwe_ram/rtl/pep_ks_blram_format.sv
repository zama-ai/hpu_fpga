// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
// This module handles the external interface.
// It transforms the SUBWORD format into BLRAM input format.
// ==============================================================================================

module pep_ks_blram_format
  import common_definition_pkg::*;
  import param_tfhe_pkg::*;
  import pep_common_param_pkg::*;
  import pep_ks_common_param_pkg::*;
#(
  parameter  int OP_W            = 64,
  parameter  int BLWE_RAM_DEPTH  = (BLWE_K+LBY-1) / LBY * BATCH_PBS_NB * TOTAL_BATCH_NB,
  localparam int BLWE_RAM_ADD_W  = $clog2(BLWE_RAM_DEPTH),
  parameter  int SUBW_COEF_NB    = 8,
  parameter  int SUBW_NB         = 2
)
(
  input  logic                                                   clk,        // clock
  input  logic                                                   s_rst_n,    // synchronous reset

  input  logic [SUBW_NB-1:0]                                     blwe_ram_wr_en,
  input  logic [SUBW_NB-1:0][TOTAL_BATCH_NB_W-1:0]               blwe_ram_wr_batch_id, // Used in BPIP - set to 0 if not used
  input  logic [SUBW_NB-1:0][SUBW_COEF_NB-1:0][MOD_Q_W-1:0]      blwe_ram_wr_data,
  input  logic [SUBW_NB-1:0][PID_W-1:0]                          blwe_ram_wr_pid,      // Used in IPIP
  input  logic [SUBW_NB-1:0]                                     blwe_ram_wr_pbs_last, // last element of the LWE [0] = body
  input  logic [SUBW_NB-1:0]                                     blwe_ram_wr_batch_last, // last element of the batch

  // Write
  output logic [LBY-1:0]                                         ext_blram_wr_en,
  output logic [LBY-1:0][BLWE_RAM_ADD_W-1:0]                     ext_blram_wr_add,
  output logic [LBY-1:0][KS_DECOMP_W-1:0]                        ext_blram_wr_data,

  // body
  output logic [TOTAL_BATCH_NB-1:0]                              ext_bfifo_wr_en,
  output logic [PID_W-1:0]                                       ext_bfifo_wr_pid,
  output logic [OP_W-1:0]                                        ext_bfifo_wr_data
);

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int KS_BLOCK_LINE_NB = (BLWE_K+LBY-1) / LBY;
  localparam int KS_BLOCK_LINE_W  = $clog2(KS_BLOCK_LINE_NB);
  localparam int BATCH_ADD_NB     = KS_BLOCK_LINE_NB * BATCH_PBS_NB;

  localparam [TOTAL_BATCH_NB-1:0][31:0] BATCH_ADD_OFS = get_batch_add_ofs();

  localparam int BLWE_SUBW_NB = LBY / (SUBW_COEF_NB * SUBW_NB); // Should divide LBY
  // check parameters
  generate
    if (BLWE_SUBW_NB*SUBW_NB*SUBW_COEF_NB != LBY) begin : __UNSUPPORTED_BLWE_RAM_SUBWORD_NB_
      $fatal(1,"> ERROR: Unsupported BLWE_SUBW_NB value: %0d. Should have: BLWE_SUBW_NB*SUBW_NB(%0d)*SUBW_COEF_NB(%0d) == LBY(%0d)", BLWE_SUBW_NB,SUBW_NB,SUBW_COEF_NB,LBY);
    end
  endgenerate

// ============================================================================================== --
// Function
// ============================================================================================== --
  function [TOTAL_BATCH_NB-1:0][31:0] get_batch_add_ofs();
    var [TOTAL_BATCH_NB-1:0][31:0] ofs;
    ofs[0] = 0;
    for (int i=1; i<TOTAL_BATCH_NB; i=i+1)
      ofs[i] = ofs[i-1] + BATCH_ADD_NB;
    return ofs;
  endfunction

// ============================================================================================== --
// Type
// ============================================================================================== --
  typedef struct packed {
    logic [PID_W-1:0]            pid;
    logic [BLWE_RAM_ADD_W-1:0]   pid_ofs;
    logic [TOTAL_BATCH_NB_W-1:0] batch_id;
    logic                        pbs_last;
    logic                        batch_last;
    logic [MOD_Q_W-1:0]          coef_0; // keep it for the body management
  } side_t;

  localparam int SIDE_W = $bits(side_t);

// ============================================================================================== --
// Write request
// ============================================================================================== --
// ---------------------------------------------------------------------------------------------- --
// Request input pipe
// ---------------------------------------------------------------------------------------------- --
  logic [SUBW_NB-1:0]                                w0_blwe_ram_wr_en;
  logic [SUBW_NB-1:0][TOTAL_BATCH_NB_W-1:0]          w0_blwe_ram_wr_batch_id;
  logic [SUBW_NB-1:0][SUBW_COEF_NB-1:0][MOD_Q_W-1:0] w0_blwe_ram_wr_data;
  logic [SUBW_NB-1:0][PID_W-1:0]                     w0_blwe_ram_wr_pid;
  logic [SUBW_NB-1:0]                                w0_blwe_ram_wr_pbs_last;
  logic [SUBW_NB-1:0]                                w0_blwe_ram_wr_batch_last;

  always_ff @(posedge clk)
    if (!s_rst_n) w0_blwe_ram_wr_en <= '0;
    else          w0_blwe_ram_wr_en <= blwe_ram_wr_en;

  always_ff @(posedge clk) begin
    w0_blwe_ram_wr_batch_id    <= blwe_ram_wr_batch_id;
    w0_blwe_ram_wr_pid         <= blwe_ram_wr_pid;
    w0_blwe_ram_wr_data        <= blwe_ram_wr_data;
    w0_blwe_ram_wr_pbs_last    <= blwe_ram_wr_pbs_last;
    w0_blwe_ram_wr_batch_last  <= blwe_ram_wr_batch_last;
  end

// ---------------------------------------------------------------------------------------------- --
// Process the Subwords in //
// ---------------------------------------------------------------------------------------------- --
  side_t [SUBW_NB-1:0]                    w0_side;

  logic [SUBW_NB-1:0]                     w1_ram_wr_en;
  logic [SUBW_NB-1:0][BLWE_SUBW_NB-1:0]   w1_bsubw_mask;
  logic [SUBW_NB-1:0][BLWE_RAM_ADD_W-1:0] w1_ram_wr_add;
  logic [SUBW_NB-1:0][SUBW_COEF_NB-1:0][KS_DECOMP_W-1:0] w1_blwe_ram_wr_data;

  logic [TOTAL_BATCH_NB-1:0]              w2_bfifo_wr_en;
  logic [OP_W-1:0]                        w2_bfifo_wr_data;
  logic [PID_W-1:0]                       w2_bfifo_wr_pid;

  generate
    for (genvar gen_s=0; gen_s < SUBW_NB; gen_s=gen_s+1) begin : gen_subw_loop
      logic                                     w1_blwe_ram_wr_en;
      logic [TOTAL_BATCH_NB_W-1:0]              w1_blwe_ram_wr_batch_id;
      logic [BLWE_RAM_ADD_W-1:0]                w1_blwe_ram_wr_pid_ofs;
      logic [PID_W-1:0]                         w1_blwe_ram_wr_pid;
      logic                                     w1_blwe_ram_wr_pbs_last;
      logic                                     w1_blwe_ram_wr_batch_last;
      logic  [MOD_Q_W-1:0]                      w1_blwe_ram_wr_coef_0;

      side_t [SUBW_COEF_NB-1:0]                 w1_side;
      logic  [SUBW_COEF_NB-1:0]                 w1_blwe_ram_wr_en_tmp;

      assign w0_side[gen_s].batch_id   = w0_blwe_ram_wr_batch_id[gen_s];
      assign w0_side[gen_s].pid_ofs    = w0_blwe_ram_wr_pid[gen_s] * KS_BLOCK_LINE_NB;
      assign w0_side[gen_s].pid        = w0_blwe_ram_wr_pid[gen_s];
      assign w0_side[gen_s].pbs_last   = w0_blwe_ram_wr_pbs_last[gen_s];
      assign w0_side[gen_s].batch_last = w0_blwe_ram_wr_batch_last[gen_s];
      assign w0_side[gen_s].coef_0     = w0_blwe_ram_wr_data[gen_s][0];

      assign w1_blwe_ram_wr_batch_id   = w1_side[0].batch_id;
      assign w1_blwe_ram_wr_pid_ofs    = w1_side[0].pid_ofs;
      assign w1_blwe_ram_wr_pid        = w1_side[0].pid;
      assign w1_blwe_ram_wr_pbs_last   = w1_side[0].pbs_last;
      assign w1_blwe_ram_wr_batch_last = w1_side[0].batch_last;
      assign w1_blwe_ram_wr_coef_0     = w1_side[0].coef_0;

      assign w1_blwe_ram_wr_en  = w1_blwe_ram_wr_en_tmp[0];

    // ---------------------------------------------------------------------------------------------- --
    // Decompose
    // ---------------------------------------------------------------------------------------------- --
      for (genvar gen_i=0; gen_i < SUBW_COEF_NB; gen_i=gen_i+1) begin : gen_decomp_loop
        decomp_parallel #(
          .OP_W        (MOD_Q_W),
          .L           (KS_L),
          .B_W         (KS_B_W),
          .SIDE_W      (SIDE_W),
          .OUT_2SCOMPL (1'b0)
        ) decomp_parallel (
          .clk       (clk),
          .s_rst_n   (s_rst_n),
          .in_data   (w0_blwe_ram_wr_data[gen_s][gen_i]),
          .in_avail  (w0_blwe_ram_wr_en[gen_s]),
          .in_side   (w0_side[gen_s]),
          .out_data  (w1_blwe_ram_wr_data[gen_s][gen_i]),
          .out_avail (w1_blwe_ram_wr_en_tmp[gen_i]),
          .out_side  (w1_side[gen_i])
        );
      end

    // ---------------------------------------------------------------------------------------------- --
    // Compute address, and fork body
    // ---------------------------------------------------------------------------------------------- --
      logic [BLWE_RAM_ADD_W-1:0]      w1_add_ofs;
      logic [KS_BLOCK_LINE_W-1:0]     w1_add;
      logic [BLWE_SUBW_NB-1:0]        w1_bsubw_mask_l;

      logic [BLWE_RAM_ADD_W-1:0]      w1_add_ofsD;
      logic [KS_BLOCK_LINE_W-1:0]     w1_addD;
      logic [BLWE_SUBW_NB-1:0]        w1_bsubw_mask_lD;
      logic [BLWE_SUBW_NB-1:0]        w1_bsubw_mask_l_rot;

      logic                           w1_last_bsubw;
      logic                           w1_last_add;

      logic [BLWE_RAM_ADD_W-1:0]      w1_add_batch_ofs;

      if (BLWE_SUBW_NB == 1) begin : gen_w1_bsubw_mask_lD_no_rot
        assign w1_bsubw_mask_l_rot = w1_bsubw_mask_l;
      end
      else begin : gen_w1_bsubw_mask_lD_rot
        assign w1_bsubw_mask_l_rot = {w1_bsubw_mask_l[BLWE_SUBW_NB-2:0],w1_bsubw_mask_l[BLWE_SUBW_NB-1]};
      end

      assign w1_add_batch_ofs     = w1_blwe_ram_wr_pid_ofs;
      assign w1_ram_wr_en[gen_s]  = w1_blwe_ram_wr_en & ((gen_s != 0) | ~w1_blwe_ram_wr_pbs_last);
      assign w1_ram_wr_add[gen_s] = w1_add_batch_ofs + w1_add_ofs + w1_add;

      assign w1_last_bsubw    = w1_bsubw_mask_l[BLWE_SUBW_NB-1];
      assign w1_last_add      = w1_add == KS_BLOCK_LINE_NB-1;
      assign w1_bsubw_mask_lD = w1_blwe_ram_wr_en ?
                                (w1_blwe_ram_wr_batch_last || w1_blwe_ram_wr_pbs_last) ? 1 : w1_bsubw_mask_l_rot :
                                w1_bsubw_mask_l;
      assign w1_addD      = w1_blwe_ram_wr_en ? w1_blwe_ram_wr_pbs_last ? '0 : w1_last_bsubw ? w1_add + 1 : w1_add : w1_add;
      assign w1_add_ofsD  = w1_blwe_ram_wr_en && w1_blwe_ram_wr_pbs_last ? w1_blwe_ram_wr_batch_last ? '0 : w1_add_ofs + KS_BLOCK_LINE_NB : w1_add_ofs;

      always_ff @(posedge clk)
        if (!s_rst_n) begin
          w1_bsubw_mask_l <= 1;
          w1_add          <= '0;
          w1_add_ofs      <= '0;
        end
        else begin
          w1_bsubw_mask_l <= w1_bsubw_mask_lD;
          w1_add          <= w1_addD      ;
          w1_add_ofs      <= w1_add_ofsD  ;
        end

      assign w1_bsubw_mask[gen_s] = w1_bsubw_mask_l;

      // ---------------------------------------------------------------------------------------------- --
      // Body
      // ---------------------------------------------------------------------------------------------- --
      if (gen_s == 0) begin : gen_body_proc
        logic [TOTAL_BATCH_NB-1:0] w1_bfifo_wr_en;
        logic [MOD_Q_W-1:0]        w1_bfifo_wr_data_tmp;
        logic [OP_W-1:0]           w1_bfifo_wr_data;
        logic                      w1_body_wr_en;

        assign w1_body_wr_en        = w1_blwe_ram_wr_en & w1_blwe_ram_wr_pbs_last;
        assign w1_bfifo_wr_data_tmp = w1_blwe_ram_wr_coef_0;

        // Do the mod switch from MOD_Q to OP_W if necessary
        if (MOD_Q_W > OP_W) begin : gen_body_mod_switch
          assign w1_bfifo_wr_data = w1_bfifo_wr_data_tmp[MOD_Q_W-1-:OP_W] + w1_bfifo_wr_data_tmp[MOD_Q_W-1-OP_W];
        end
        else if (MOD_Q_W == OP_W) begin : gen_body_no_mod_switch
          assign w1_bfifo_wr_data = w1_bfifo_wr_data_tmp;
        end
        else begin : __UNSUPPORTED_OP_W
          $fatal(1,"> ERROR: Unsupported OP_W. Should be <= MOD_Q_W");
        end

        always_comb
          for (int i=0; i<TOTAL_BATCH_NB; i=i+1)
            w1_bfifo_wr_en[i] = w1_body_wr_en & (w1_blwe_ram_wr_batch_id == i);

        always_ff @(posedge clk)
          if (!s_rst_n) w2_bfifo_wr_en <= '0;
          else          w2_bfifo_wr_en <= w1_bfifo_wr_en;

        always_ff @(posedge clk) begin
          w2_bfifo_wr_data <= w1_bfifo_wr_data;
          w2_bfifo_wr_pid  <= w1_blwe_ram_wr_pid;
        end

      end // gen_body_proc
    end
  endgenerate

// ---------------------------------------------------------------------------------------------- --
// Extend subword format into LBY
// ---------------------------------------------------------------------------------------------- --
  logic [LBY-1:0]                     w1_ext_wr_en;
  logic [LBY-1:0][BLWE_RAM_ADD_W-1:0] w1_ext_wr_add;
  logic [LBY-1:0][KS_DECOMP_W-1:0]    w1_ext_wr_data;

  logic [LBY-1:0]                     w2_ext_wr_en;
  logic [LBY-1:0][BLWE_RAM_ADD_W-1:0] w2_ext_wr_add;
  logic [LBY-1:0][KS_DECOMP_W-1:0]    w2_ext_wr_data;

  always_comb
    for (int i=0; i<BLWE_SUBW_NB; i=i+1)
      for (int k=0; k<SUBW_NB; k=k+1)
        for (int j=0; j<SUBW_COEF_NB; j=j+1) begin
          w1_ext_wr_en[i*(SUBW_NB*SUBW_COEF_NB) + k*SUBW_COEF_NB + j]   = w1_ram_wr_en[k] & w1_bsubw_mask[k][i];
          w1_ext_wr_add[i*(SUBW_NB*SUBW_COEF_NB) + k*SUBW_COEF_NB + j]  = w1_ram_wr_add[k];
          w1_ext_wr_data[i*(SUBW_NB*SUBW_COEF_NB) + k*SUBW_COEF_NB + j] = w1_blwe_ram_wr_data[k][j];
        end

  always_ff @(posedge clk)
    if (!s_rst_n) w2_ext_wr_en <= '0;
    else          w2_ext_wr_en <= w1_ext_wr_en;

  always_ff @(posedge clk) begin
    w2_ext_wr_add         <= w1_ext_wr_add ;
    w2_ext_wr_data        <= w1_ext_wr_data;
  end

// ---------------------------------------------------------------------------------------------- --
// Write output
// ---------------------------------------------------------------------------------------------- --
  assign ext_blram_wr_en   = w2_ext_wr_en;
  assign ext_blram_wr_add  = w2_ext_wr_add;
  assign ext_blram_wr_data = w2_ext_wr_data;

  assign ext_bfifo_wr_en   = w2_bfifo_wr_en  ;
  assign ext_bfifo_wr_data = w2_bfifo_wr_data;
  assign ext_bfifo_wr_pid  = w2_bfifo_wr_pid;
endmodule
