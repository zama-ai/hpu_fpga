// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the reading of BLWE coefficients
// for the KS operation.
// ==============================================================================================

module pep_ks_control
  import common_definition_pkg::*;
  import param_tfhe_pkg::*;
  import pep_common_param_pkg::*;
  import pep_ks_common_param_pkg::*;
#(
  parameter  int OP_W             = 64,
  parameter  int BLWE_RAM_DEPTH   = (BLWE_K+LBY-1)/LBY * TOTAL_PBS_NB,
  localparam int BLWE_RAM_ADD_W   = $clog2(BLWE_RAM_DEPTH),
  parameter  int DATA_LATENCY     = 6, // RAM access read latency
  parameter  int ALMOST_DONE_BLINE_ID = 0
)
(
  input  logic                                clk,        // clock
  input  logic                                s_rst_n,    // synchronous reset

  // Sequencer command
  output logic                                ks_seq_cmd_enquiry,
  input  logic [KS_CMD_W-1:0]                 seq_ks_cmd,
  input  logic                                seq_ks_cmd_avail,

  // Command for result_format
  output logic [KS_CMD_W-1:0]                 ctrl_res_cmd,
  output logic                                ctrl_res_cmd_vld,
  input  logic                                ctrl_res_cmd_rdy,

  // Command for body map
  output logic [KS_CMD_W-1:0]                 ctrl_bmap_cmd,
  output logic                                ctrl_bmap_cmd_vld,
  input  logic                                ctrl_bmap_cmd_rdy,

  // ksk_if
  input  logic                                inc_ksk_wr_ptr,
  // Output FIFO
  input  logic                                outp_ks_loop_done_mh,

  // reset cache
  input  logic                                reset_cache,

  // To ksk manager
  output logic [KS_BATCH_CMD_W-1:0]           batch_cmd,
  output logic                                batch_cmd_avail, // pulse

  // BLWE RAM interface
  output logic [LBY-1:0]                      ctrl_blram_rd_en,
  output logic [LBY-1:0][BLWE_RAM_ADD_W-1:0]  ctrl_blram_rd_add,
  input  logic [LBY-1:0][KS_DECOMP_W-1:0]     blram_ctrl_rd_data,
  input  logic [LBY-1:0]                      blram_ctrl_rd_data_avail,

  // Output to mult
  output logic [LBY-1:0][LBZ-1:0][KS_B_W-1:0] ctrl_mult_data,
  output logic [LBY-1:0][LBZ-1:0]             ctrl_mult_sign,
  output logic [LBY-1:0]                      ctrl_mult_avail,
  // last coef info
  output logic                                ctrl_mult_last_eol,
  output logic                                ctrl_mult_last_eoy,
  output logic                                ctrl_mult_last_last_iter, // last iteration within the column
  output logic [TOTAL_BATCH_NB_W-1:0]         ctrl_mult_last_batch_id // Unused. Is a constant.

);

// ============================================================================================== --
// Parameter
// ============================================================================================== --
// Check
  generate
    if (KS_BLOCK_COL_NB < 2) begin : __UNSUPPORTED_KS_BLOCK_COL_NB
      $fatal(1,"> ERROR: Unsupported KS_BLOCK_COL_NB (%0d), should be greater or equal to 2.", KS_BLOCK_COL_NB);
    end
  endgenerate

// ============================================================================================== --
// Input pipe
// ============================================================================================== --
  logic                  reset_loop;

  always_ff @(posedge clk)
    if (!s_rst_n) reset_loop <= 1'b0;
    else          reset_loop <= reset_cache;

// The sequencer command, contains the command for 1 BCOL process.
  //== cmd
  logic                  seq_ks_cmd_vld;
  logic                  seq_ks_cmd_rdy;

  ks_cmd_t               s0_cmd;
  logic                  s0_cmd_in_vld;
  logic                  s0_cmd_in_rdy;
  logic [BPBS_NB_WW-1:0] s0_cmd_ct_nb_m1;

  assign s0_cmd_ct_nb_m1 = pt_elt_nb(s0_cmd.wp, s0_cmd.rp) - 1;

  assign seq_ks_cmd_vld = seq_ks_cmd_avail;

  fifo_element #(
    .WIDTH          (KS_CMD_W),
    .DEPTH          (1),
    .TYPE_ARRAY     (4'h3),
    .DO_RESET_DATA  (1'b0),
    .RESET_DATA_VAL (0)
  ) s0_cmd_fifo_element (
    .clk      (clk),
    .s_rst_n  (s_rst_n),

    .in_data  (seq_ks_cmd),
    .in_vld   (seq_ks_cmd_vld),
    .in_rdy   (seq_ks_cmd_rdy),

    .out_data (s0_cmd),
    .out_vld  (s0_cmd_in_vld),
    .out_rdy  (s0_cmd_in_rdy)
  );

// pragma translate_off
  always_ff @(posedge clk)
    if (seq_ks_cmd_vld) begin
      assert(seq_ks_cmd_rdy)
      else begin
        $fatal(1, "%t > ERROR: s0_cmd_fifo_element is not ready for KS command!", $time);
      end
    end
// pragma translate_on

  //== Fork the command between the main path and the other paths
  logic s0_cmd_vld;
  logic s0_cmd_rdy;

  assign s0_cmd_vld        = s0_cmd_in_vld & ctrl_res_cmd_rdy & ctrl_bmap_cmd_rdy;
  assign ctrl_res_cmd_vld  = s0_cmd_in_vld & s0_cmd_rdy       & ctrl_bmap_cmd_rdy;
  assign ctrl_bmap_cmd_vld = s0_cmd_in_vld & ctrl_res_cmd_rdy & s0_cmd_rdy;
  assign s0_cmd_in_rdy     = s0_cmd_rdy    & ctrl_res_cmd_rdy & ctrl_bmap_cmd_rdy;

  assign ctrl_res_cmd      = s0_cmd;
  assign ctrl_bmap_cmd     = s0_cmd;

  // pointers
  logic s0_inc_ksk_wr_ptr;
  logic s0_inc_ksk_rd_ptr;

  always_ff @(posedge clk)
    if (!s_rst_n) s0_inc_ksk_wr_ptr <= '0;
    else          s0_inc_ksk_wr_ptr <= inc_ksk_wr_ptr;

// ============================================================================================== --
// KSK pointer
// ============================================================================================== --
  // Keep track of the filling of the KSK. Do not start command if the key is not present.
  logic [KS_BLOCK_COL_W:0] ksk_wp;
  logic [KS_BLOCK_COL_W:0] ksk_rp;
  logic [KS_BLOCK_COL_W:0] ksk_wpD;
  logic [KS_BLOCK_COL_W:0] ksk_rpD;
  logic                ksk_empty;
  logic                ksk_full;
  logic                ksk_wp_last;
  logic                ksk_rp_last;

  always_ff @(posedge clk)
    if (!s_rst_n || reset_loop) begin
      ksk_wp <= '0;
      ksk_rp <= '0;
    end
    else begin
      ksk_rp <= ksk_rpD;
      ksk_wp <= ksk_wpD;
    end

  assign ksk_wp_last = ksk_wp == (KS_BLOCK_COL_NB-1);
  assign ksk_rp_last = ksk_rp == (KS_BLOCK_COL_NB-1);

  assign ksk_empty = ksk_rp == ksk_wp;
  assign ksk_full  = (ksk_rp[KS_BLOCK_COL_W-1:0] == ksk_wp[KS_BLOCK_COL_W-1:0]) & (ksk_rp[KS_BLOCK_COL_W] != ksk_wp[KS_BLOCK_COL_W]);

  assign ksk_wpD = s0_inc_ksk_wr_ptr ? ksk_wp_last ? {~ksk_wp[KS_BLOCK_COL_W],{KS_BLOCK_COL_W{1'b0}}} : ksk_wp + 1 : ksk_wp;
  assign ksk_rpD = s0_inc_ksk_rd_ptr ? ksk_rp_last ? {~ksk_rp[KS_BLOCK_COL_W],{KS_BLOCK_COL_W{1'b0}}} : ksk_rp + 1 : ksk_rp;

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      if (s0_inc_ksk_wr_ptr) begin
        assert(!ksk_full)
        else begin
          $fatal(1,"%t> ERROR: Increase ksk write pointer, while it is already full.",$time);
        end
      end
      if (s0_inc_ksk_rd_ptr) begin
        assert(!ksk_empty)
        else begin
          $fatal(1,"%t> ERROR: Increase ksk read pointer, while it is empty.",$time);
        end
      end
    end
// pragma translate_on

// ============================================================================================== --
// Process
// ============================================================================================== --
  proc_cmd_t ffifo_in_pcmd;
  logic      ffifo_in_vld;
  logic      ffifo_in_rdy;

  proc_cmd_t ffifo_out_pcmd;
  logic      ffifo_out_vld;
  logic      ffifo_out_rdy;

//-------------------------------------------------------------------------------------------------
// Feed FIFO
//-------------------------------------------------------------------------------------------------
  logic [KS_BLOCK_COL_W-1:0] s0_ks_loop;
  logic [KS_BLOCK_COL_W-1:0] s0_ks_loopD;
  logic                      s0_last_ks_loop;

  assign s0_last_ks_loop = s0_ks_loop == KS_BLOCK_COL_NB-1;
  assign s0_ks_loopD = (ffifo_in_vld && ffifo_in_rdy) ? s0_last_ks_loop ? '0 : s0_ks_loop + 1 : s0_ks_loop;

  always_ff @(posedge clk)
    if (!s_rst_n || reset_loop) s0_ks_loop <= '0;
    else                        s0_ks_loop <= s0_ks_loopD;

  fifo_element #(
    .WIDTH          (PROC_CMD_W),
    .DEPTH          (1),
    .TYPE_ARRAY     (4'h1),
    .DO_RESET_DATA  (1'b0),
    .RESET_DATA_VAL (0)
  ) feed_fifo (
    .clk      (clk),
    .s_rst_n  (s_rst_n),

    .in_data  (ffifo_in_pcmd),
    .in_vld   (ffifo_in_vld),
    .in_rdy   (ffifo_in_rdy),

    .out_data (ffifo_out_pcmd),
    .out_vld  (ffifo_out_vld),
    .out_rdy  (ffifo_out_rdy)
  );

  // Loopback path has priority over input new command
  assign ffifo_in_vld              = s0_cmd_vld;
  assign s0_cmd_rdy                = ffifo_in_rdy;
  assign ffifo_in_pcmd.first_pid   = s0_cmd.rp[PID_W-1:0];
  assign ffifo_in_pcmd.batch_id    = '0;
  assign ffifo_in_pcmd.batch_id_1h = 1;
  assign ffifo_in_pcmd.pbs_cnt_max = s0_cmd_ct_nb_m1;
  assign ffifo_in_pcmd.ks_loop     = s0_ks_loop;

// pragma translate_off
  always_ff @(posedge clk)
    if (s0_cmd_vld && s0_cmd_rdy)
      // In the command, ks_loop indicates the LWE_K_P1 column.
      assert(s0_ks_loop == s0_cmd.ks_loop / LBX)
      else begin
        $fatal(1,"%t > ERROR: ks_loop mismatch: internal_counter=%0d, command=%0d", $time,s0_ks_loop, s0_cmd.ks_loop / LBX);
      end
// pragma translate_on

//-------------------------------------------------------------------------------------------------
// Feed process
//-------------------------------------------------------------------------------------------------
  logic proc_almost_done;
  pep_ks_ctrl_feed
  #(
    .DATA_LATENCY   (DATA_LATENCY),
    .BLWE_RAM_DEPTH (BLWE_RAM_DEPTH),
    .ALMOST_DONE_BLINE_ID (ALMOST_DONE_BLINE_ID)
  ) pep_ks_ctrl_feed (
    .clk                        (clk),
    .s_rst_n                    (s_rst_n),

    .reset_cache                (reset_cache),

    .ksk_empty                  (ksk_empty),
    .inc_ksk_rd_ptr             (s0_inc_ksk_rd_ptr),
    .ofifo_inc_rp               (outp_ks_loop_done_mh),

    .ffifo_feed_pcmd            (ffifo_out_pcmd),
    .ffifo_feed_vld             (ffifo_out_vld),
    .ffifo_feed_rdy             (ffifo_out_rdy),

    .ctrl_blram_rd_en           (ctrl_blram_rd_en),
    .ctrl_blram_rd_add          (ctrl_blram_rd_add),
    .blram_ctrl_rd_data         (blram_ctrl_rd_data),
    .blram_ctrl_rd_data_avail   (blram_ctrl_rd_data_avail),

    .ctrl_mult_avail            (ctrl_mult_avail),
    .ctrl_mult_data             (ctrl_mult_data),
    .ctrl_mult_sign             (ctrl_mult_sign),
    .ctrl_mult_last_eol         (ctrl_mult_last_eol),
    .ctrl_mult_last_eoy         (ctrl_mult_last_eoy),
    .ctrl_mult_last_last_iter   (ctrl_mult_last_last_iter),
    .ctrl_mult_last_batch_id    (ctrl_mult_last_batch_id),

    .batch_cmd                  (batch_cmd),
    .batch_cmd_avail            (batch_cmd_avail),

    .proc_almost_done           (proc_almost_done)
  );

//-------------------------------------------------------------------------------------------------
// Enquiry
//-------------------------------------------------------------------------------------------------
// Build the very first enquiry after the reset
// Set it some cycle after the reset. TOREVIEW
  localparam int ENQ_DEPTH = 8;
  logic [ENQ_DEPTH-1:0] enq_init;
  logic [ENQ_DEPTH-1:0] enq_initD;

  logic pending_cmd;
  logic pending_cmdD;

  logic ks_seq_cmd_enquiryD;

  assign pending_cmdD = seq_ks_cmd_avail   ? 1'b1 :
                        ks_seq_cmd_enquiry ? 1'b0 : pending_cmd;
  assign enq_initD = enq_init << 1;
  assign ks_seq_cmd_enquiryD = (enq_init[ENQ_DEPTH-1] & pending_cmd) | proc_almost_done;

  always_ff @(posedge clk)
    if (!s_rst_n || reset_loop) begin
      enq_init <= 1;
    end
    else begin
      enq_init <= enq_initD;
    end

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      ks_seq_cmd_enquiry <= 1'b0;
      pending_cmd        <= 1'b1;
    end
    else begin
      ks_seq_cmd_enquiry <= ks_seq_cmd_enquiryD;
      pending_cmd        <= pending_cmdD;
    end

endmodule
