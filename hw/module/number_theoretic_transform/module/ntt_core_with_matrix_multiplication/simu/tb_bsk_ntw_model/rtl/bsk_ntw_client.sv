// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the distribution of the cl_ntt_bsk to the NTT core.
// ==============================================================================================

module bsk_ntw_client
  import param_tfhe_pkg::*;
  import ntt_core_common_param_pkg::*;
  import top_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import bsk_ntw_common_param_pkg::*;
#(
  parameter  int OP_W            = 32,
  parameter  int BATCH_NB        = 2,
  parameter  int RAM_LATENCY     = 2
)
(
  input  logic                                           clk,        // clock
  input  logic                                           s_rst_n,    // synchronous reset

  input  logic [BSK_DIST_COEF_NB-1:0][OP_W-1:0]          srv_cl_bsk,
  input  logic [BSK_DIST_COEF_NB-1:0]                    srv_cl_avail,
  input  logic [BSK_UNIT_W-1:0]                          srv_cl_unit,
  input  logic [BSK_GROUP_W-1:0]                         srv_cl_group,
  input  logic [LWE_K_W-1:0]                             srv_cl_br_loop,

  output logic [PSI-1:0][R-1:0][GLWE_K_P1-1:0][OP_W-1:0] cl_ntt_bsk,
  output logic [PSI-1:0][R-1:0][GLWE_K_P1-1:0]           cl_ntt_vld,
  input  logic [PSI-1:0][R-1:0][GLWE_K_P1-1:0]           cl_ntt_rdy,

  // Broadcast from acc
  input  logic [BR_BATCH_CMD_W-1:0]                      batch_cmd,
  input  logic                                           batch_cmd_avail, // pulse

  // Error
  output logic [CLT_ERROR_NB-1:0]                        error

);

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int CORE_ERROR_NB = 2;

// ============================================================================================== --
// bsk_ntw_client
// ============================================================================================== --
// ---------------------------------------------------------------------------------------------- --
// Duplication
// ---------------------------------------------------------------------------------------------- --
// To ease the P&R duplicate some signals
  logic [BSK_ITER_COEF_NB-1:0]                  srv_cl_avail_dly_a;
  logic [BSK_ITER_COEF_NB-1:0][OP_W-1:0]        srv_cl_bsk_dly_a;
  logic [BSK_ITER_COEF_NB-1:0][LWE_K_W-1:0]     srv_cl_br_loop_dly_a;
  logic [BSK_ITER_COEF_NB-1:0][BSK_GROUP_W-1:0] srv_cl_group_dly_a;
  logic [BSK_ITER_COEF_NB-1:0][BR_BATCH_CMD_W-1:0] batch_cmd_dly_a;
  logic [BSK_ITER_COEF_NB-1:0]                  batch_cmd_avail_dly_a;
  logic [BSK_ITER_COEF_NB-1:0]                  srv_cl_avail_dly_aD;
  logic [BSK_ITER_COEF_NB-1:0][OP_W-1:0]        srv_cl_bsk_dly_aD;
  logic [BSK_ITER_COEF_NB-1:0][LWE_K_W-1:0]     srv_cl_br_loop_dly_aD;
  logic [BSK_ITER_COEF_NB-1:0][BSK_GROUP_W-1:0] srv_cl_group_dly_aD;
  logic [BSK_ITER_COEF_NB-1:0][BR_BATCH_CMD_W-1:0] batch_cmd_dly_aD;
  logic [BSK_ITER_COEF_NB-1:0]                  batch_cmd_avail_dly_aD;


  always_comb begin
    for (int i=0; i<BSK_ITER_COEF_NB/BSK_DIST_COEF_NB; i=i+1) begin
      for (int j=0; j<BSK_DIST_COEF_NB; j=j+1) begin
        srv_cl_avail_dly_aD[i*BSK_DIST_COEF_NB+j]   = srv_cl_avail[j] & (srv_cl_unit == i);
      end
    end
  end

  always_comb begin
    for (int i=0; i<BSK_ITER_COEF_NB/BSK_DIST_COEF_NB; i=i+1) begin
      for (int j=0; j<BSK_DIST_COEF_NB; j=j+1) begin
        srv_cl_bsk_dly_aD[i*BSK_DIST_COEF_NB+j]     = srv_cl_avail_dly_aD[i*BSK_DIST_COEF_NB+j] ? srv_cl_bsk[j]  : srv_cl_bsk_dly_a[i*BSK_DIST_COEF_NB+j];
        srv_cl_br_loop_dly_aD[i*BSK_DIST_COEF_NB+j] = srv_cl_avail_dly_aD[i*BSK_DIST_COEF_NB+j] ? srv_cl_br_loop : srv_cl_br_loop_dly_a[i*BSK_DIST_COEF_NB+j];
        srv_cl_group_dly_aD[i*BSK_DIST_COEF_NB+j]   = srv_cl_avail_dly_aD[i*BSK_DIST_COEF_NB+j] ? srv_cl_group   : srv_cl_group_dly_a[i*BSK_DIST_COEF_NB+j];
      end
    end
  end

  always_comb begin
    for (int i=0; i<BSK_ITER_COEF_NB; i=i+1) begin
      batch_cmd_dly_aD[i]       = batch_cmd_avail ? batch_cmd : batch_cmd_dly_a[i];
      batch_cmd_avail_dly_aD[i] = batch_cmd_avail;
    end
  end

  always_ff @(posedge clk) begin
    srv_cl_bsk_dly_a     <= srv_cl_bsk_dly_aD;
    srv_cl_br_loop_dly_a <= srv_cl_br_loop_dly_aD;
    srv_cl_group_dly_a   <= srv_cl_group_dly_aD;
    batch_cmd_dly_a      <= batch_cmd_dly_aD;
  end

  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      srv_cl_avail_dly_a   <= '0;
      batch_cmd_avail_dly_a <= '0;
    end
    else begin
      srv_cl_avail_dly_a    <= srv_cl_avail_dly_aD;
      batch_cmd_avail_dly_a <= batch_cmd_avail_dly_aD;
    end
  end

// ---------------------------------------------------------------------------------------------- --
// Client core instances
// ---------------------------------------------------------------------------------------------- --
  logic [BSK_ITER_COEF_NB-1:0][CORE_ERROR_NB-1:0] error_a;

  genvar gen_p;
  genvar gen_r;
  genvar gen_g;
  generate
    for (gen_p=0; gen_p<PSI; gen_p=gen_p+1) begin : p_loop_gen
      for (gen_r=0; gen_r<R; gen_r=gen_r+1) begin : r_loop_gen
        for (gen_g=0; gen_g<GLWE_K_P1; gen_g=gen_g+1) begin : g_loop_gen
          bsk_ntw_client_core
          #(
            .OP_W       (OP_W),
            .BATCH_NB   (BATCH_NB),
            .RAM_LATENCY(RAM_LATENCY)
          )
          bsk_ntw_client_core
          (
            .clk            (clk),
            .s_rst_n        (s_rst_n),

            .srv_cl_bsk     (srv_cl_bsk_dly_a[gen_p*(R*GLWE_K_P1)+gen_r*GLWE_K_P1+gen_g]),
            .srv_cl_avail   (srv_cl_avail_dly_a[gen_p*(R*GLWE_K_P1)+gen_r*GLWE_K_P1+gen_g]),
            .srv_cl_br_loop (srv_cl_br_loop_dly_a[gen_p*(R*GLWE_K_P1)+gen_r*GLWE_K_P1+gen_g]),
            .srv_cl_group   (srv_cl_group_dly_a[gen_p*(R*GLWE_K_P1)+gen_r*GLWE_K_P1+gen_g]),

            .cl_ntt_bsk     (cl_ntt_bsk[gen_p][gen_r][gen_g]),
            .cl_ntt_vld     (cl_ntt_vld[gen_p][gen_r][gen_g]),
            .cl_ntt_rdy     (cl_ntt_rdy[gen_p][gen_r][gen_g]),

            .batch_cmd      (batch_cmd_dly_a[(gen_p*(R*GLWE_K_P1)+gen_r*GLWE_K_P1+gen_g)]),
            .batch_cmd_avail(batch_cmd_avail_dly_a[(gen_p*(R*GLWE_K_P1)+gen_r*GLWE_K_P1+gen_g)]),

            .error          (error_a[(gen_p*(R*GLWE_K_P1)+gen_r*GLWE_K_P1+gen_g)])
          );

        end
      end
    end
  endgenerate

  always_comb begin
    logic [CLT_ERROR_NB-1:0] error_tmp;
    error_tmp = '0;
    for (int i=0; i<BSK_ITER_COEF_NB; i=i+1)
      error_tmp = error_tmp | error_a[i];
    error = error_tmp;
  end

endmodule
