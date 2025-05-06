// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the accumulation part of the CMUX process.
// It reads the data from the GRAM, and wait for the external multiplication results.
// It does the addition, and writes the result back in GRAM.
//
// This module is the core of the module.
//
// Notation:
// GRAM : stands for GLWE RAM
// ==============================================================================================

module pep_mmacc_splitc_acc_core
  import param_tfhe_pkg::*;
  import ntt_core_common_param_pkg::*;
  import top_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import pep_mmacc_common_param_pkg::*;
#(
  parameter  int DATA_LATENCY        = 5, // Latency for read data to come back
  parameter  int RAM_LATENCY         = 2,
  parameter  int HPSI_SET_ID         = 0,  // Indicates which of the two coef sets is processed here
  parameter  int MSPLIT_FACTOR       = 2,
  parameter  int FIFO_NTT_ACC_DEPTH  = 1024, // Physical RAM depth. Should be a power of 2
  localparam int HPSI                = MSPLIT_FACTOR * PSI / MSPLIT_DIV
)
(
  input  logic                                                     clk,        // clock
  input  logic                                                     s_rst_n,    // synchronous reset

  // NTT core -> ACC
  input  logic                                                     ntt_acc_avail,
  input  logic [HPSI-1:0][R-1:0][MOD_Q_W-1:0]                      ntt_acc_data,
  input  logic                                                     ntt_acc_sob,
  input  logic                                                     ntt_acc_eob,
  input  logic                                                     ntt_acc_sol,
  input  logic                                                     ntt_acc_eol,
  input  logic                                                     ntt_acc_sog,
  input  logic                                                     ntt_acc_eog,
  input  logic [BPBS_ID_W-1:0]                                     ntt_acc_pbs_id,

  // GRAM arbiter
  output logic [GARB_CMD_W-1:0]                                    acc_garb_req,
  output logic                                                     acc_garb_req_vld,
  input  logic                                                     acc_garb_req_rdy,

  input  logic [GRAM_NB-1:0]                                       garb_acc_rd_avail_1h,
  input  logic [GRAM_NB-1:0]                                       garb_acc_wr_avail_1h,

  // GRAM access
  output logic [GRAM_NB-1:0][HPSI-1:0][R-1:0]                      acc_gram_rd_en,
  output logic [GRAM_NB-1:0][HPSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0]  acc_gram_rd_add,
  input  logic [GRAM_NB-1:0][HPSI-1:0][R-1:0][MOD_Q_W-1:0]         gram_acc_rd_data,
  input  logic [GRAM_NB-1:0][HPSI-1:0][R-1:0]                      gram_acc_rd_data_avail,

  output logic [GRAM_NB-1:0][HPSI-1:0][R-1:0]                      acc_gram_wr_en,
  output logic [GRAM_NB-1:0][HPSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0]  acc_gram_wr_add,
  output logic [GRAM_NB-1:0][HPSI-1:0][R-1:0][MOD_Q_W-1:0]         acc_gram_wr_data,

  // From afifo
  input  logic [MMACC_INTERN_CMD_W-1:0]                            afifo_acc_icmd,
  input  logic                                                     afifo_acc_vld,
  output logic                                                     afifo_acc_rdy,

  // To sfifo
  output logic [MMACC_INTERN_CMD_W-1:0]                            acc_sfifo_icmd,
  output logic                                                     acc_sfifo_avail,

  // Status
  output logic                                                     acc_feed_done,
  output logic [BPBS_ID_W-1:0]                                     acc_feed_done_map_idx,
  output logic                                                     br_loop_proc_done,

  output logic [ACC_CORE_ERROR_W-1:0]                              error // [0] gram write access error
                                                                       // [1] infifo overflow
);

//=================================================================================================
// localparam
//=================================================================================================
  localparam int GRAM_ACCESS_ERROR_OFS = 0;
  localparam int INFIFO_OVF_ERROR_OFS  = 1;

  localparam int QPSI                  = PSI/MSPLIT_DIV;
  localparam int QPSI_SET_ID_OFS       = HPSI_SET_ID*(MSPLIT_DIV-MSPLIT_FACTOR);

  generate
    if (MSPLIT_DIV != 4) begin : __UNSUPPORTED_MSPLIT_DIV
      $fatal(1,"> ERROR: Unsupported MSPLIT_DIV (%0d) value. Should be equal to 4.",MSPLIT_DIV);
    end
  endgenerate


//=================================================================================================
// signals
//=================================================================================================
  logic [MSPLIT_FACTOR-1:0]             gram_acs_error;

  // Prepare GRAM access
  logic                                 a0_do_read;
  logic [GLWE_RAM_ADD_W-1:0]            a0_rd_add;
  logic [GRAM_ID_W-1:0]                 a0_rd_grid;

  logic                                 s0_mask_null;
  logic [HPSI-1:0][R-1:0][MOD_Q_W-1:0]  s1_ntt_acc_data;
  logic                                 s1_avail;
  logic [GLWE_RAM_ADD_W-1:0]            s1_add;
  logic [GRAM_ID_W-1:0]                 s1_grid;

  // GRAM access
  logic [MSPLIT_FACTOR-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0]                     acc_gram_rd_en_l;
  logic [MSPLIT_FACTOR-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0] acc_gram_rd_add_l;
  logic [MSPLIT_FACTOR-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0][MOD_Q_W-1:0]        gram_acc_rd_data_l;
  logic [MSPLIT_FACTOR-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0]                     gram_acc_rd_data_avail_l;

  logic [MSPLIT_FACTOR-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0]                     acc_gram_wr_en_l;
  logic [MSPLIT_FACTOR-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0] acc_gram_wr_add_l;
  logic [MSPLIT_FACTOR-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0][MOD_Q_W-1:0]        acc_gram_wr_data_l;

  always_comb
    for (int i=0; i<MSPLIT_FACTOR; i=i+1)
      for (int g=0; g<GRAM_NB; g=g+1)
        for (int p=0; p<QPSI; p=p+1) begin
          acc_gram_rd_en[g][i*QPSI+p]       = acc_gram_rd_en_l[i][g][p];
          acc_gram_rd_add[g][i*QPSI+p]      = acc_gram_rd_add_l[i][g][p];
          gram_acc_rd_data_l[i][g][p]       = gram_acc_rd_data[g][i*QPSI+p];
          gram_acc_rd_data_avail_l[i][g][p] = gram_acc_rd_data_avail[g][i*QPSI+p];
          acc_gram_wr_en[g][i*QPSI+p]       = acc_gram_wr_en_l[i][g][p];
          acc_gram_wr_add[g][i*QPSI+p]      = acc_gram_wr_add_l[i][g][p];
          acc_gram_wr_data[g][i*QPSI+p]     = acc_gram_wr_data_l[i][g][p];
        end

//=================================================================================================
// read
//=================================================================================================
  pep_mmacc_splitc_acc_read
  #(
    .DATA_LATENCY         (DATA_LATENCY),
    .RAM_LATENCY          (RAM_LATENCY),
    .MSPLIT_FACTOR        (MSPLIT_FACTOR),
    .FIFO_NTT_ACC_DEPTH   (FIFO_NTT_ACC_DEPTH)
  ) pep_mmacc_splitc_acc_read (
    .clk                  (clk),
    .s_rst_n              (s_rst_n),

    .ntt_acc_avail        (ntt_acc_avail),
    .ntt_acc_data         (ntt_acc_data),
    .ntt_acc_sob          (ntt_acc_sob),
    .ntt_acc_eob          (ntt_acc_eob),
    .ntt_acc_sol          (ntt_acc_sol),
    .ntt_acc_eol          (ntt_acc_eol),
    .ntt_acc_sog          (ntt_acc_sog),
    .ntt_acc_eog          (ntt_acc_eog),
    .ntt_acc_pbs_id       (ntt_acc_pbs_id),

    .acc_garb_req         (acc_garb_req),
    .acc_garb_req_vld     (acc_garb_req_vld),
    .acc_garb_req_rdy     (acc_garb_req_rdy),

    .garb_acc_rd_avail_1h (garb_acc_rd_avail_1h),

    .out_a0_do_read       (a0_do_read),
    .out_a0_rd_add        (a0_rd_add),
    .out_a0_rd_grid       (a0_rd_grid),

    .out_s0_mask_null     (s0_mask_null),
    .out_s1_ntt_acc_data  (s1_ntt_acc_data),
    .out_s1_avail         (s1_avail),
    .out_s1_add           (s1_add),
    .out_s1_grid          (s1_grid),

    .afifo_acc_icmd       (afifo_acc_icmd),
    .afifo_acc_vld        (afifo_acc_vld),
    .afifo_acc_rdy        (afifo_acc_rdy),

    .acc_sfifo_icmd       (acc_sfifo_icmd),
    .acc_sfifo_avail      (acc_sfifo_avail),

    .acc_feed_done       (acc_feed_done),
    .acc_feed_done_map_idx (acc_feed_done_map_idx),
    .br_loop_proc_done   (br_loop_proc_done),

    .error               (error[INFIFO_OVF_ERROR_OFS])
  );

//=================================================================================================
// write
//=================================================================================================
  generate
    for (genvar gen_i=0; gen_i<MSPLIT_FACTOR; gen_i=gen_i+1) begin : gen_qpsi_loop
      localparam bit USE_IN_PIPE = (QPSI_SET_ID_OFS + gen_i) % 2;
      pep_mmacc_splitc_acc_write
      #(
        .IN_PIPE (USE_IN_PIPE)
      ) qpsi__pep_mmacc_splitc_acc_write
      (
        .clk                    (clk),
        .s_rst_n                (s_rst_n),

        .garb_acc_wr_avail_1h   (garb_acc_wr_avail_1h),

        .in_a0_do_read          (a0_do_read),
        .in_a0_rd_add           (a0_rd_add),
        .in_a0_rd_grid          (a0_rd_grid),

        .in_s0_mask_null        (s0_mask_null),
        .in_s1_ntt_acc_data     (s1_ntt_acc_data[gen_i*QPSI+:QPSI]),
        .in_s1_avail            (s1_avail),
        .in_s1_add              (s1_add),
        .in_s1_grid             (s1_grid),

        .acc_gram_rd_en         (acc_gram_rd_en_l[gen_i]),
        .acc_gram_rd_add        (acc_gram_rd_add_l[gen_i]),
        .gram_acc_rd_data       (gram_acc_rd_data_l[gen_i]),
        .gram_acc_rd_data_avail (gram_acc_rd_data_avail_l[gen_i]),

        .acc_gram_wr_en         (acc_gram_wr_en_l[gen_i]),
        .acc_gram_wr_add        (acc_gram_wr_add_l[gen_i]),
        .acc_gram_wr_data       (acc_gram_wr_data_l[gen_i]),

        .error                  (gram_acs_error[gen_i])
      );
    end // gen_qpsi_loop
  endgenerate

//=================================================================================================
// Error
//=================================================================================================
  logic gram_error;
  logic gram_errorD;

  assign gram_errorD = |gram_acs_error;

  always_ff @(posedge clk)
    if (!s_rst_n) gram_error <= 1'b0;
    else          gram_error <= gram_errorD;

  assign error[GRAM_ACCESS_ERROR_OFS] = gram_error;
endmodule
