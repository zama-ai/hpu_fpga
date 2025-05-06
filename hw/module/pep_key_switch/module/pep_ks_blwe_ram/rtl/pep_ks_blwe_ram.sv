// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the RAM used to store the BLWE data for a batch.
// This RAM is initialized by eternal write access.
// To save some RAM, data are stored already decomposed.
// During the process:
// - it is read to get the BLWE coef for the key switching
//
// /!\ Temporary module. While waiting for HPU architecture
// ==============================================================================================

module pep_ks_blwe_ram
  import common_definition_pkg::*;
  import param_tfhe_pkg::*;
  import pep_common_param_pkg::*;
  import pep_ks_common_param_pkg::*;
#(
  parameter  int OP_W             = 64, // KSK_W ? TOREVIEW
  parameter  int SUBW_COEF_NB     = 8,
  parameter  int SUBW_NB          = 2,
  parameter  int RAM_LATENCY      = 2,
  parameter  int BLWE_RAM_DEPTH   = (BLWE_K+LBY-1)/LBY * BATCH_PBS_NB * TOTAL_BATCH_NB,
  localparam int BLWE_RAM_ADD_W   = $clog2(BLWE_RAM_DEPTH)
)
(
  input  logic                                                  clk,        // clock
  input  logic                                                  s_rst_n,    // synchronous reset

  // External Write
  input  logic [SUBW_NB-1:0]                                    blwe_ram_wr_en,
  input  logic [SUBW_NB-1:0][TOTAL_BATCH_NB_W-1:0]              blwe_ram_wr_batch_id, // Used in BPIP
  input  logic [SUBW_NB-1:0][SUBW_COEF_NB-1:0][MOD_Q_W-1:0]     blwe_ram_wr_data,
  input  logic [SUBW_NB-1:0][PID_W-1:0]                         blwe_ram_wr_pid,      // Used in IPIP
  input  logic [SUBW_NB-1:0]                                    blwe_ram_wr_pbs_last, // last element of the LWE [0] = body
  input  logic [SUBW_NB-1:0]                                    blwe_ram_wr_batch_last, // last element of the batch

  // Process read
  input  logic [LBY-1:0]                                        ctrl_blram_rd_en,
  input  logic [LBY-1:0][BLWE_RAM_ADD_W-1:0]                    ctrl_blram_rd_add,
  output logic [LBY-1:0][KS_DECOMP_W-1:0]                       blram_ctrl_rd_data,
  output logic [LBY-1:0]                                        blram_ctrl_rd_data_avail,

  // Body fifo
  output logic [TOTAL_BATCH_NB-1:0]                             blram_bfifo_wr_en,
  output logic [PID_W-1:0]                                      blram_bfifo_wr_pid,
  output logic [OP_W-1:0]                                       blram_bfifo_wr_data
);

//======================================================
// signal
//======================================================
  logic [LBY-1:0]                     ext_blram_wr_en;
  logic [LBY-1:0][BLWE_RAM_ADD_W-1:0] ext_blram_wr_add;
  logic [LBY-1:0][KS_DECOMP_W-1:0]    ext_blram_wr_data;

//======================================================
// Format
//======================================================
  pep_ks_blram_format
  #(
    .OP_W                      (OP_W),
    .BLWE_RAM_DEPTH            (BLWE_RAM_DEPTH),
    .SUBW_COEF_NB              (SUBW_COEF_NB),
    .SUBW_NB                   (SUBW_NB)
  ) pep_ks_blram_format (
    .clk                    (clk),
    .s_rst_n                (s_rst_n),

    .blwe_ram_wr_en         (blwe_ram_wr_en),
    .blwe_ram_wr_batch_id   (blwe_ram_wr_batch_id),
    .blwe_ram_wr_data       (blwe_ram_wr_data),
    .blwe_ram_wr_pid        (blwe_ram_wr_pid),
    .blwe_ram_wr_pbs_last   (blwe_ram_wr_pbs_last),
    .blwe_ram_wr_batch_last (blwe_ram_wr_batch_last),

    .ext_blram_wr_en        (ext_blram_wr_en),
    .ext_blram_wr_add       (ext_blram_wr_add),
    .ext_blram_wr_data      (ext_blram_wr_data),

    .ext_bfifo_wr_en        (blram_bfifo_wr_en),
    .ext_bfifo_wr_pid       (blram_bfifo_wr_pid),
    .ext_bfifo_wr_data      (blram_bfifo_wr_data)
  );

//======================================================
// BLRAM instance
//======================================================
  generate
    for (genvar gen_b=0; gen_b < LBY; gen_b=gen_b+1) begin : gen_b_loop
      pep_ks_blram_core
      #(
        .OP_W           (KS_DECOMP_W),
        .RAM_LATENCY    (RAM_LATENCY),
        .RAM_DEPTH      (BLWE_RAM_DEPTH),
        .IN_PIPE        (1'b1),
        .OUT_PIPE       (1'b1)
      ) pep_ks_blram_core (
        .clk          (clk),
        .s_rst_n      (s_rst_n),

        .wr_en        (ext_blram_wr_en[gen_b]),
        .wr_add       (ext_blram_wr_add[gen_b]),
        .wr_data      (ext_blram_wr_data[gen_b]),

        .rd_en        (ctrl_blram_rd_en[gen_b]),
        .rd_add       (ctrl_blram_rd_add[gen_b]),
        .rd_data      (blram_ctrl_rd_data[gen_b]),
        .rd_data_avail(blram_ctrl_rd_data_avail[gen_b])
      );
    end
  endgenerate

endmodule
