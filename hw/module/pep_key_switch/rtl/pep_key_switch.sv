// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the key switch for pe_pbs.
// It takes a BLWE as input.
// Change the key into the PBS key domain.
// Each coefficient is finally mod switch to 2N.
// ==============================================================================================

module pep_key_switch
  import common_definition_pkg::*;
  import param_tfhe_pkg::*;
  import pep_common_param_pkg::*;
  import pep_ks_common_param_pkg::*;
#(
  parameter  int RAM_LATENCY   = 2,
  parameter  int ALMOST_DONE_BLINE_ID = 0, // TOREVIEW
  parameter  int KS_IF_SUBW_NB = 1,
  parameter  int KS_IF_COEF_NB = LBY
)
(
  input  logic                                                      clk,        // clock
  input  logic                                                      s_rst_n,    // synchronous reset

  // Sequencer command
  output logic                                                      ks_seq_cmd_enquiry,
  input  logic [KS_CMD_W-1:0]                                       seq_ks_cmd,
  input  logic                                                      seq_ks_cmd_avail,

  // ksk_if
  input  logic                                                      inc_ksk_wr_ptr, // pulse
  output logic                                                      inc_ksk_rd_ptr,

  // To ksk manager
  output logic [KS_BATCH_CMD_W-1:0]                                 batch_cmd,
  output logic                                                      batch_cmd_avail, // pulse

  // load_blwe
  input  logic [KS_IF_SUBW_NB-1:0]                                  ldb_blram_wr_en,
  input  logic [KS_IF_SUBW_NB-1:0][PID_W-1:0]                       ldb_blram_wr_pid,
  input  logic [KS_IF_SUBW_NB-1:0][KS_IF_COEF_NB-1:0][MOD_Q_W-1:0]  ldb_blram_wr_data,
  input  logic [KS_IF_SUBW_NB-1:0]                                  ldb_blram_wr_pbs_last, // associated to wr_en[0]

  // KSK
  input  logic [LBX-1:0][LBY-1:0][LBZ-1:0][MOD_KSK_W-1:0]           ksk,
  input  logic [LBX-1:0][LBY-1:0]                                   ksk_vld,
  output logic [LBX-1:0][LBY-1:0]                                   ksk_rdy,

  // LWE coeff
  output logic [KS_RESULT_W-1:0]                                    ks_seq_result,
  output logic                                                      ks_seq_result_vld,
  input  logic                                                      ks_seq_result_rdy,

  // Wr access to body RAM
  output logic                                                      boram_wr_en,
  output logic [MOD_KSK_W-1:0]                                      boram_data,
  output logic [PID_W-1:0]                                          boram_pid,
  output logic                                                      boram_parity,

  input  logic                                                      reset_cache,

  // Error
  output pep_ks_error_t                                             ks_error
);

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int BLWE_RAM_DEPTH   = KS_BLOCK_LINE_NB * TOTAL_PBS_NB;
  localparam int BLWE_RAM_ADD_W = $clog2(BLWE_RAM_DEPTH);

  localparam int BLRAM_DATA_LATENCY = RAM_LATENCY + 1 + 1 + 1 + 1;// +1 : input pipe
                                                                 // +1 : output pipe
                                                                 // +1 : arbiter pipe
                                                                 // +1 : output demux pipe

  localparam int RES_FIFO_DEPTH = 4*LBX; // TOREVIEW

// ============================================================================================== --
// Internal signals
// ============================================================================================== --
  // BLWE RAM interface
  logic [LBY-1:0]                              ctrl_blram_rd_en;
  logic [LBY-1:0][BLWE_RAM_ADD_W-1:0]          ctrl_blram_rd_add;
  logic [LBY-1:0][KS_DECOMP_W-1:0]             blram_ctrl_rd_data;
  logic [LBY-1:0]                              blram_ctrl_rd_data_avail;

  // ctrl to mult
  logic [LBY-1:0][LBZ-1:0][KS_B_W-1:0]         ctrl_mult_data;
  logic [LBY-1:0][LBZ-1:0]                     ctrl_mult_sign;
  logic [LBY-1:0]                              ctrl_mult_avail;
  // last coef info
  logic                                        ctrl_mult_last_eol;
  logic                                        ctrl_mult_last_eoy;
  logic                                        ctrl_mult_last_last_iter; // last iteration within the column
  logic [TOTAL_BATCH_NB_W-1:0]                 ctrl_mult_last_batch_id;

  logic [LBX-1:0][MOD_KSK_W-1:0]               mult_outp_data;
  logic [LBX-1:0]                              mult_outp_avail;
  logic [LBX-1:0]                              mult_outp_last_pbs;
  logic [LBX-1:0][TOTAL_BATCH_NB_W-1:0]        mult_outp_batch_id;

  // Internal body fifo
  logic [TOTAL_BATCH_NB-1:0]                   blram_bfifo_wr_en;
  logic [PID_W-1:0]                            blram_bfifo_wr_pid;
  logic [MOD_KSK_W-1:0]                        blram_bfifo_wr_data;

  logic [TOTAL_BATCH_NB-1:0][MOD_KSK_W-1:0]    bfifo_outp_data;
  logic [TOTAL_BATCH_NB-1:0][PID_W-1:0]        bfifo_outp_pid;
  logic [TOTAL_BATCH_NB-1:0]                   bfifo_outp_vld;
  logic [TOTAL_BATCH_NB-1:0]                   bfifo_outp_rdy;

  logic [TOTAL_BATCH_NB-1:0]                   outp_batch_done_1h;

  logic [TOTAL_BATCH_NB-1:0]                   outp_ks_loop_done_mh;

  logic [LWE_COEF_W-1:0]                       br_proc_lwe;
  logic [KS_CORR_W-1:0]                        br_proc_corr;
  logic                                        br_proc_vld;
  logic                                        br_proc_rdy;

  logic [KS_CMD_W-1:0]                         ctrl_res_cmd;
  logic                                        ctrl_res_cmd_vld;
  logic                                        ctrl_res_cmd_rdy;

  logic [KS_CMD_W-1:0]                         ctrl_bmap_cmd;
  logic                                        ctrl_bmap_cmd_vld;
  logic                                        ctrl_bmap_cmd_rdy;

// ============================================================================================== --
// Error
// ============================================================================================== --
  pep_ks_error_t ks_errorD;

  logic          error_ksk_udf;

  always_comb begin
    ks_errorD = '0;
    ks_errorD.ksk_udf = error_ksk_udf;
  end

  always_ff @(posedge clk)
    if (!s_rst_n) ks_error <= '0;
    else          ks_error <= ks_errorD;

// ============================================================================================== --
// Instances
// ============================================================================================== --
//------------------------------------------------------
// ks_control
//------------------------------------------------------
  pep_ks_control #(
    .OP_W          (MOD_KSK_W     ),
    .BLWE_RAM_DEPTH(BLWE_RAM_DEPTH),
    .DATA_LATENCY  (BLRAM_DATA_LATENCY),
    .ALMOST_DONE_BLINE_ID (ALMOST_DONE_BLINE_ID)
  ) pep_ks_control (
    .clk                       (clk    ),
    .s_rst_n                   (s_rst_n),

    .ks_seq_cmd_enquiry        (ks_seq_cmd_enquiry),
    .seq_ks_cmd                (seq_ks_cmd        ),
    .seq_ks_cmd_avail          (seq_ks_cmd_avail  ),

    .ctrl_res_cmd              (ctrl_res_cmd),
    .ctrl_res_cmd_vld          (ctrl_res_cmd_vld),
    .ctrl_res_cmd_rdy          (ctrl_res_cmd_rdy),

    .ctrl_bmap_cmd             (ctrl_bmap_cmd),
    .ctrl_bmap_cmd_vld         (ctrl_bmap_cmd_vld),
    .ctrl_bmap_cmd_rdy         (ctrl_bmap_cmd_rdy),

    .batch_cmd                 (batch_cmd),
    .batch_cmd_avail           (batch_cmd_avail),

    .inc_ksk_wr_ptr            (inc_ksk_wr_ptr),
    .outp_ks_loop_done_mh      (outp_ks_loop_done_mh),

    .reset_cache               (reset_cache),

    .ctrl_blram_rd_en          (ctrl_blram_rd_en),
    .ctrl_blram_rd_add         (ctrl_blram_rd_add),
    .blram_ctrl_rd_data        (blram_ctrl_rd_data),
    .blram_ctrl_rd_data_avail  (blram_ctrl_rd_data_avail),

    .ctrl_mult_data            (ctrl_mult_data),
    .ctrl_mult_sign            (ctrl_mult_sign),
    .ctrl_mult_avail           (ctrl_mult_avail),

    .ctrl_mult_last_eol        (ctrl_mult_last_eol),
    .ctrl_mult_last_eoy        (ctrl_mult_last_eoy),
    .ctrl_mult_last_last_iter  (ctrl_mult_last_last_iter),
    .ctrl_mult_last_batch_id   (ctrl_mult_last_batch_id)
  );

//------------------------------------------------------
// ks_blwe_ram
//------------------------------------------------------
  pep_ks_blwe_ram
  #(
    .OP_W             (MOD_KSK_W),
    .SUBW_COEF_NB     (KS_IF_COEF_NB),
    .SUBW_NB          (KS_IF_SUBW_NB),
    .RAM_LATENCY      (RAM_LATENCY),
    .BLWE_RAM_DEPTH   (BLWE_RAM_DEPTH)
  ) pep_ks_blwe_ram (
    .clk                      (clk),
    .s_rst_n                  (s_rst_n),

    .blwe_ram_wr_en           (ldb_blram_wr_en),
    .blwe_ram_wr_batch_id     ('0), // Single batch
    .blwe_ram_wr_data         (ldb_blram_wr_data),
    .blwe_ram_wr_pid          (ldb_blram_wr_pid),
    .blwe_ram_wr_pbs_last     (ldb_blram_wr_pbs_last),
    .blwe_ram_wr_batch_last   (ldb_blram_wr_pbs_last), // Single batch

    .ctrl_blram_rd_en         (ctrl_blram_rd_en),
    .ctrl_blram_rd_add        (ctrl_blram_rd_add),
    .blram_ctrl_rd_data       (blram_ctrl_rd_data),
    .blram_ctrl_rd_data_avail (blram_ctrl_rd_data_avail),

    .blram_bfifo_wr_en        (blram_bfifo_wr_en),
    .blram_bfifo_wr_pid       (blram_bfifo_wr_pid),
    .blram_bfifo_wr_data      (blram_bfifo_wr_data)
  );

//------------------------------------------------------
// ks_mult
//------------------------------------------------------
  pep_ks_mult
  #(
    .OP_W (MOD_KSK_W)
  ) pep_ks_mult (
    .clk                        (clk),
    .s_rst_n                    (s_rst_n),

    .ctrl_mult_data             (ctrl_mult_data),
    .ctrl_mult_sign             (ctrl_mult_sign),
    .ctrl_mult_avail            (ctrl_mult_avail),

    .ctrl_mult_last_eol         (ctrl_mult_last_eol),
    .ctrl_mult_last_eoy         (ctrl_mult_last_eoy),
    .ctrl_mult_last_last_iter   (ctrl_mult_last_last_iter),
    .ctrl_mult_last_batch_id    (ctrl_mult_last_batch_id),

    .ksk                        (ksk),
    .ksk_vld                    (ksk_vld),
    .ksk_rdy                    (ksk_rdy),

    .mult_outp_data             (mult_outp_data),
    .mult_outp_avail            (mult_outp_avail),
    .mult_outp_last_pbs         (mult_outp_last_pbs),
    .mult_outp_batch_id         (mult_outp_batch_id),

    .error                      (error_ksk_udf)
  );

//------------------------------------------------------
// ks_out_process
//------------------------------------------------------
  pep_ks_out_process
  #(
    .OP_W           (MOD_KSK_W)
  ) pep_ks_out_process (
    .clk                   (clk),
    .s_rst_n               (s_rst_n),

    .outp_ks_loop_done_mh  (outp_ks_loop_done_mh),
    .inc_ksk_rd_ptr        (inc_ksk_rd_ptr),

    .mult_outp_data        (mult_outp_data),
    .mult_outp_avail       (mult_outp_avail),
    .mult_outp_last_pbs    (mult_outp_last_pbs),
    .mult_outp_batch_id    (mult_outp_batch_id),

    .bfifo_outp_data       (bfifo_outp_data),
    .bfifo_outp_pid        (bfifo_outp_pid),
    .bfifo_outp_vld        (bfifo_outp_vld),
    .bfifo_outp_rdy        (bfifo_outp_rdy),

    .br_proc_lwe           (br_proc_lwe),
    .br_proc_corr          (br_proc_corr),
    .br_proc_vld           (br_proc_vld),
    .br_proc_rdy           (br_proc_rdy),

    .reset_cache           (reset_cache),

    .br_bfifo_wr_en        (boram_wr_en),
    .br_bfifo_data         (boram_data),
    .br_bfifo_pid          (boram_pid),
    .br_bfifo_parity       (boram_parity)
  );

//------------------------------------------------------
// pep_ks_body_map
//------------------------------------------------------
 pep_ks_body_map
  #(
    .IN_PIPE (1'b0), // TOREVIEW
    .OP_W    (MOD_KSK_W)
  ) pep_ks_body_map (
    .clk                 (clk),
    .s_rst_n             (s_rst_n),

    .ctrl_bmap_cmd       (ctrl_bmap_cmd    ),
    .ctrl_bmap_cmd_vld   (ctrl_bmap_cmd_vld),
    .ctrl_bmap_cmd_rdy   (ctrl_bmap_cmd_rdy),

    .blram_bmap_wr_en    (blram_bfifo_wr_en),
    .blram_bmap_wr_data  (blram_bfifo_wr_data),
    .blram_bmap_wr_pid   (blram_bfifo_wr_pid),

    .bmap_outp_data      (bfifo_outp_data),
    .bmap_outp_pid       (bfifo_outp_pid),
    .bmap_outp_vld       (bfifo_outp_vld),
    .bmap_outp_rdy       (bfifo_outp_rdy)
  );

//------------------------------------------------------
// Result
//------------------------------------------------------
  pep_ks_result_format #(
    .RES_FIFO_DEPTH (RES_FIFO_DEPTH)
  ) pep_ks_result_format (
    .clk               (clk),        // clock
    .s_rst_n           (s_rst_n),    // synchronous reset

    .ctrl_res_cmd      (ctrl_res_cmd    ),
    .ctrl_res_cmd_vld  (ctrl_res_cmd_vld),
    .ctrl_res_cmd_rdy  (ctrl_res_cmd_rdy),

    .br_proc_lwe       (br_proc_lwe),
    .br_proc_corr      (br_proc_corr),
    .br_proc_vld       (br_proc_vld),
    .br_proc_rdy       (br_proc_rdy),

    .reset_cache       (reset_cache),

    .ks_seq_result     (ks_seq_result),
    .ks_seq_result_vld (ks_seq_result_vld),
    .ks_seq_result_rdy (ks_seq_result_rdy)
  );

endmodule
