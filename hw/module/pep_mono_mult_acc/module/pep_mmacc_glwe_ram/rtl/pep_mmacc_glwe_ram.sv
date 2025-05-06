// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the RAM used to store the GLWE data.
// The access to this RAM is controlled by the arbiter.
// There should never be any access conflict.
//
// The actors that need access to this RAM are :
// MMACC_FEED
// MMACC_ACC
// MMACC_SXT
// LD : load from memory
//
// There are R*PSI functional RAMs.
// Each functional RAM is composed of 4 physical RAMs.
// ==============================================================================================

module pep_mmacc_glwe_ram
#(
  parameter  int OP_W            = 32,
  parameter  int PSI             = 32,
  parameter  int R               = 2,
  parameter  int RAM_LATENCY     = 1,
  parameter  int GRAM_NB         = 4,
  parameter  int GLWE_RAM_DEPTH  = 1024,// PHYS_RAM_DEPTH / (STG_ITER_NB * GLWE_K_P1) * (STG_ITER_NB * GLWE_K_P1)
  localparam int GLWE_RAM_ADD_W  = $clog2(GLWE_RAM_DEPTH),
  parameter  bit IN_PIPE         = 1'b1,
  parameter  bit OUT_PIPE        = 1'b1
)
(
  input  logic                                                        clk,        // clock
  input  logic                                                        s_rst_n,    // synchronous reset

  // External Write (port a)
  input  logic [GRAM_NB-1:0][PSI-1:0][R-1:0]                          ext_gram_wr_en,
  input  logic [GRAM_NB-1:0][PSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0]      ext_gram_wr_add,
  input  logic [GRAM_NB-1:0][PSI-1:0][R-1:0][OP_W-1:0]                ext_gram_wr_data,

  // Sxt Read (port b)
  input  logic [GRAM_NB-1:0][PSI-1:0][R-1:0]                          sxt_gram_rd_en,
  input  logic [GRAM_NB-1:0][PSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0]      sxt_gram_rd_add,
  output logic [GRAM_NB-1:0][PSI-1:0][R-1:0][OP_W-1:0]                gram_sxt_rd_data,
  output logic [GRAM_NB-1:0][PSI-1:0][R-1:0]                          gram_sxt_rd_data_avail,

  // Feed Read (port a and b)
  input  logic [GRAM_NB-1:0][PSI-1:0][R-1:0][1:0]                     feed_gram_rd_en,
  input  logic [GRAM_NB-1:0][PSI-1:0][R-1:0][1:0][GLWE_RAM_ADD_W-1:0] feed_gram_rd_add,
  output logic [GRAM_NB-1:0][PSI-1:0][R-1:0][1:0][OP_W-1:0]           gram_feed_rd_data,
  output logic [GRAM_NB-1:0][PSI-1:0][R-1:0][1:0]                     gram_feed_rd_data_avail,

  // Acc Read (port a)
  input  logic [GRAM_NB-1:0][PSI-1:0][R-1:0]                          acc_gram_rd_en,
  input  logic [GRAM_NB-1:0][PSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0]      acc_gram_rd_add,
  output logic [GRAM_NB-1:0][PSI-1:0][R-1:0][OP_W-1:0]                gram_acc_rd_data,
  output logic [GRAM_NB-1:0][PSI-1:0][R-1:0]                          gram_acc_rd_data_avail,

  // Acc Write (port b)
  input  logic [GRAM_NB-1:0][PSI-1:0][R-1:0]                          acc_gram_wr_en,
  input  logic [GRAM_NB-1:0][PSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0]      acc_gram_wr_add,
  input  logic [GRAM_NB-1:0][PSI-1:0][R-1:0][OP_W-1:0]                acc_gram_wr_data,

  output logic                                                        error // access conflict
);

  logic [GRAM_NB-1:0][PSI-1:0][R-1:0] access_conflict;
  generate
    for (genvar gen_t=0; gen_t < GRAM_NB; gen_t=gen_t+1) begin : gen_t_loop
      for (genvar gen_p=0; gen_p < PSI; gen_p=gen_p+1) begin : gen_p_loop
        for (genvar gen_r=0; gen_r < R; gen_r=gen_r+1) begin : gen_r_loop
          pep_mmacc_gram_core
          #(
            .OP_W           (OP_W),
            .RAM_LATENCY    (RAM_LATENCY),
            .GLWE_RAM_DEPTH (GLWE_RAM_DEPTH),
            .IN_PIPE        (IN_PIPE),
            .OUT_PIPE       (OUT_PIPE)
          ) pep_mmacc_gram_core (
            .clk                    (clk),
            .s_rst_n                (s_rst_n),

            .ext_gram_wr_en         (ext_gram_wr_en[gen_t][gen_p][gen_r]),
            .ext_gram_wr_add        (ext_gram_wr_add[gen_t][gen_p][gen_r]),
            .ext_gram_wr_data       (ext_gram_wr_data[gen_t][gen_p][gen_r]),

            .sxt_gram_rd_en         (sxt_gram_rd_en[gen_t][gen_p][gen_r]),
            .sxt_gram_rd_add        (sxt_gram_rd_add[gen_t][gen_p][gen_r]),
            .gram_sxt_rd_data       (gram_sxt_rd_data[gen_t][gen_p][gen_r]),
            .gram_sxt_rd_data_avail (gram_sxt_rd_data_avail[gen_t][gen_p][gen_r]),

            .feed_gram_rd_en        (feed_gram_rd_en[gen_t][gen_p][gen_r]),
            .feed_gram_rd_add       (feed_gram_rd_add[gen_t][gen_p][gen_r]),
            .gram_feed_rd_data      (gram_feed_rd_data[gen_t][gen_p][gen_r]),
            .gram_feed_rd_data_avail(gram_feed_rd_data_avail[gen_t][gen_p][gen_r]),

            .acc_gram_rd_en         (acc_gram_rd_en[gen_t][gen_p][gen_r]),
            .acc_gram_rd_add        (acc_gram_rd_add[gen_t][gen_p][gen_r]),
            .gram_acc_rd_data       (gram_acc_rd_data[gen_t][gen_p][gen_r]),
            .gram_acc_rd_data_avail (gram_acc_rd_data_avail[gen_t][gen_p][gen_r]),

            .acc_gram_wr_en         (acc_gram_wr_en[gen_t][gen_p][gen_r]),
            .acc_gram_wr_add        (acc_gram_wr_add[gen_t][gen_p][gen_r]),
            .acc_gram_wr_data       (acc_gram_wr_data[gen_t][gen_p][gen_r]),

            .error                  (access_conflict[gen_t][gen_p][gen_r])
          );
        end
      end
    end
  endgenerate

  always_ff @(posedge clk)
    if (!s_rst_n) error <= 1'b0;
    else          error <= |access_conflict;

endmodule
