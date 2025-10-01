// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the feeding of the processing path, in pe_pbs
// The command is given by the pep_sequencer.
// It reads the data from the GRAM.
// It processes the rotation of the monomial multiplication, and the subtraction
// of the CMUX.
//
// For P&R reason, GRAM is split into several parts.
//
// Notation:
// GRAM : stands for GLWE RAM
//
// ==============================================================================================

module pep_mmacc_splitc_feed_read
  import param_tfhe_pkg::*;
  import ntt_core_common_param_pkg::*;
  import top_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import pep_mmacc_common_param_pkg::*;
  import pep_mmacc_splitc_feed_pkg::*;
#(
  parameter  int DATA_LATENCY       = 5, // RAM_LATENCY + 3 : Latency for read data to come back
  parameter  bit WAIT_FOR_ACK       = 1'b1    // Used in main, wait for cmd subs acknowledgement before processing.
)
(
  input  logic                           clk,        // clock
  input  logic                           s_rst_n,    // synchronous reset

  // Input command from main
  input  logic [MMACC_FEED_CMD_W-1:0]    in_mcmd,
  input  logic                           in_mcmd_vld,
  output logic                           in_mcmd_rdy,

  input  logic                           mcmd_ack, // Used if WAIT_FOR_ACK > 0

  // GRAM arbiter
  output logic [GARB_CMD_W-1:0]          feed_garb_req,
  output logic                           feed_garb_req_vld,
  input  logic                           feed_garb_req_rdy,

  input  logic [GRAM_NB-1:0]             garb_feed_rot_avail_1h,
  input  logic [GRAM_NB-1:0]             garb_feed_dat_avail_1h,

  // To afifo
  output logic [MMACC_INTERN_CMD_W-1:0]  feed_afifo_icmd,
  output logic                           feed_afifo_vld,
  input  logic                           feed_afifo_rdy,

  // From acc
  input  logic                           acc_feed_done,
  input  logic [BPBS_ID_W-1:0]           acc_feed_done_map_idx,

  // To prepare GRAM access
  output logic                           out_f1_rd_en,
  output logic [GLWE_RAM_ADD_W-1:0]      out_f1_rd_add,
  output logic [GRAM_ID_W-1:0]           out_f1_rd_grid,

  output logic                           out_ff3_rd_en,
  output logic [GLWE_RAM_ADD_W-1:0]      out_ff3_rd_add,
  output logic [GRAM_ID_W-1:0]           out_ff3_rd_grid,

  output logic                           out_s0_avail,
  output logic [REQ_CMD_W-1:0]           out_s0_rcmd,

  output logic                           out_ss1_avail,
  output logic [REQ_CMD_W-1:0]           out_ss1_rcmd,

  output logic                           br_loop_flush_done,

  output logic [BR_BATCH_CMD_W-1:0]      batch_cmd,
  output logic                           batch_cmd_avail

);

//=================================================================================================
// localparam
//=================================================================================================
  localparam int PSI_R_W      = $clog2(PSI*R);
  localparam int MCMD_DEPTH   = 4; // To store the mcmd during the mcmd_loopback path.

  localparam int ACK_DEPTH  = MCMD_DEPTH + 2; // +2 pipe of the delay_fifo_reg

  // There are PERM_CYCLE_NB cycles during which the permutation of the coefficients
  // is done for the rotation.
  // During these cycles the "not rotated" data are not used. Therefore, there is no
  // need to read these latter at the same time as the rotated ones.
  // Thus registers are saved.
  // t0                                    : rotated data read
  // t0 + GRAM_AVAIL_CYCLE                 : rotated data available
  // t0 + GRAM_AVAIL_CYCLE + PERM_CYCLE_NB : data are rotated
  //
  // t0 + PERM_CYCLE_NB                    : read "not rotated" data
  // t0 + PERM_CYCLE_NB + GRAM_AVAIL_CYCLE : "not rotated" data are available
  //

  localparam int GRAM_AVAIL_CYCLE = DATA_LATENCY + 2 // f2 + f3 : for address computation
                                                 + 1; // gram rdata pipe
  localparam int RD_DATA_CYCLE    = PERM_CYCLE_NB+1; // +1 rot stage pipe
  localparam int SR_DEPTH         = RD_DATA_CYCLE + GRAM_AVAIL_CYCLE;

  localparam int SS          = STG_ITER_SZ / R_SZ;

  localparam int GLWE_RAM_DEPTH_PBS = STG_ITER_NB * GLWE_K_P1;

  localparam int FEED_OFIFO_DEPTH = 1 + 2; // 2 due to subs input fifo element latency + 2 real buffer location

  generate
    if (STG_ITER_NB < 2) begin : __UNSUPPORTED_STG_ITER_NB_
      $fatal(1, "> ERROR: Unsupported STG_ITER_NB (%0d) : should be >= 2", STG_ITER_NB);
    end
    if (R != 2) begin : __UNSUPPORTED_R_
      $fatal(1, "> ERROR: Unsupported R (%0d): should be 2", R);
    end
    if (PSI < 2) begin : __UNSUPPORTED_PSI_
      $fatal(1, "> ERROR: Unsupported PSI (%0d): should be >= 2", PSI);
    end
  endgenerate

// ============================================================================================= --
// Input pipe
// ============================================================================================= --
  logic [GRAM_NB-1:0]   garb_rot_avail_1h;
  logic [GRAM_NB-1:0]   garb_dat_avail_1h;
  logic                 acc_done;
  logic [BPBS_ID_W-1:0] acc_done_map_idx;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      garb_rot_avail_1h <= '0;
      garb_dat_avail_1h <= '0;
      acc_done          <= 1'b0;
    end
    else begin
      garb_rot_avail_1h <= garb_feed_rot_avail_1h;
      garb_dat_avail_1h <= garb_feed_dat_avail_1h;
      acc_done          <= acc_feed_done;
    end

  always_ff @(posedge clk)
    acc_done_map_idx <= acc_feed_done_map_idx;

// ============================================================================================= --
// Keep ack
// ============================================================================================= --
  logic fm1_ack_vld;
  logic fm1_ack_rdy;

  logic ack_error;

  generate
    if (WAIT_FOR_ACK) begin : gen_ack_fifo
      logic fm2_mcmd_ack;
      always_ff @(posedge clk)
        if (!s_rst_n) fm2_mcmd_ack <= 1'b0;
        else          fm2_mcmd_ack <= mcmd_ack;
      common_lib_pulse_to_rdy_vld
      #(
        .FIFO_DEPTH (ACK_DEPTH)
      ) common_lib_pulse_to_rdy_vld (
        .clk (clk),
        .s_rst_n  (s_rst_n),

        .in_pulse (fm2_mcmd_ack),

        .out_vld  (fm1_ack_vld),
        .out_rdy  (fm1_ack_rdy),

        .error    (ack_error)
      );

// pragma translate_off
      always_ff @(posedge clk)
        if (!s_rst_n) begin
          // Do nothing
        end
        else begin
          assert(ack_error == 1'b0)
          else begin
            $fatal(1,"%t > ERROR: ack input fifo overflows!", $time);
          end
        end
// pragma translate_on
    end
  endgenerate

// ============================================================================================= --
// Input Shift register
// ============================================================================================= --
  mmacc_feed_cmd_t  fm1_mcmd;
  logic             fm1_mcmd_vld;
  logic             fm1_mcmd_rdy;

  generate
    if (WAIT_FOR_ACK == 0) begin : gen_no_wait_for_ack
      // Need a fifo element to generate the ack signal.
      // Also compensate the pipe on the ack path.
      fifo_element #(
        .WIDTH          (MMACC_FEED_CMD_W),
        .DEPTH          (1),
        .TYPE_ARRAY     (4'h1),
        .DO_RESET_DATA  (0),
        .RESET_DATA_VAL (0)
      ) cmd_fifo_element (
        .clk     (clk),
        .s_rst_n (s_rst_n),

        .in_data (in_mcmd),
        .in_vld  (in_mcmd_vld),
        .in_rdy  (in_mcmd_rdy),

        .out_data(fm1_mcmd),
        .out_vld (fm1_mcmd_vld),
        .out_rdy (fm1_mcmd_rdy)
      );
    end
    else begin : gen_wait_for_ack
      logic fm1_mcmd_vld_tmp;
      logic fm1_mcmd_rdy_tmp;

      assign fm1_mcmd_vld     = fm1_mcmd_vld_tmp & fm1_ack_vld;
      assign fm1_mcmd_rdy_tmp = fm1_mcmd_rdy & fm1_ack_vld;
      assign fm1_ack_rdy      = fm1_mcmd_rdy & fm1_mcmd_vld_tmp;
      fifo_reg #(
        .WIDTH         (MMACC_FEED_CMD_W),
        .DEPTH         (MCMD_DEPTH),
        .LAT_PIPE_MH   ({1'b1, 1'b1})
      ) delay_fifo_reg (
        .clk    (clk),
        .s_rst_n(s_rst_n),

        .in_data(in_mcmd),
        .in_vld (in_mcmd_vld),
        .in_rdy (in_mcmd_rdy),

        .out_data(fm1_mcmd),
        .out_vld (fm1_mcmd_vld_tmp),
        .out_rdy (fm1_mcmd_rdy_tmp)
      );

// pragma translate_off
      always_ff @(posedge clk)
        if (!s_rst_n) begin
          // do nothing
        end
        else begin
          if (fm1_ack_vld)
            assert(fm1_mcmd_vld_tmp)
            else begin
              $fatal(1,"%t > ERROR: Not available mcmd at the output of delay_fifo_reg when mcmd_ack arrives.", $time);
            end
        end
// pragma translate_on
    end
  endgenerate

//=================================================================================================
// Track loopback
//=================================================================================================
  // To be able to process a CMUX iteration, the previous iteration of the ciphertext must be over.
  // No need to set, when it is the last iteration.
  logic [BATCH_PBS_NB-1:0] loopback_pending;
  logic [BATCH_PBS_NB-1:0] loopback_pendingD;

  logic                    loopback_pending_set;
  logic [BPBS_ID_W-1:0]    loopback_pending_set_map_idx;

  logic                    loopback_pending_unset;
  logic [BPBS_ID_W-1:0]    loopback_pending_unset_map_idx;

  assign loopback_pending_unset         = acc_done;
  assign loopback_pending_unset_map_idx = acc_done_map_idx;

  always_comb
    for (int i=0; i<BATCH_PBS_NB; i=i+1)
      loopback_pendingD[i] = loopback_pending_set   && (loopback_pending_set_map_idx == i)   ? 1'b1 :
                         loopback_pending_unset && (loopback_pending_unset_map_idx == i) ? 1'b0 :
                         loopback_pending[i];

  always_ff @(posedge clk)
    if (!s_rst_n) loopback_pending <= '0;
    else          loopback_pending <= loopback_pendingD;

// pragma translate_off
    always_ff @(posedge clk)
      if (!s_rst_n) begin
        // do nothing
      end
      else begin
        for (int i=0; i<BATCH_PBS_NB; i=i+1)
          assert(!( loopback_pending_set   && (loopback_pending_set_map_idx == i) && loopback_pending_unset && (loopback_pending_unset_map_idx == i)))
          else begin
            $fatal(1,"%t > ERROR: loopback_pending set/unset conflict for map_idx=%0d!",$time,i);
          end
      end
// pragma translate_on

// ============================================================================================= --
// fm1
// ============================================================================================= --
  // Check that there is no pending loopback
  // Fork between the processing path, the gram arbiter, and the accumulator.
  // Update loopback_pending
  logic fm1_vld;
  logic fm1_rdy;

  logic fm1_f0_vld;
  logic fm1_f0_rdy;

  logic fm1_garb_vld;
  logic fm1_garb_rdy;

  logic fm1_acc_vld;
  logic fm1_acc_rdy;

  logic fm1_do_proc;
  logic fm1_do_flush;

  assign fm1_do_proc  = (fm1_mcmd.map_elt.first | ~loopback_pending[fm1_mcmd.map_idx]);
  assign fm1_do_flush = fm1_mcmd.is_flush;
  assign fm1_vld      = fm1_mcmd_vld & (fm1_do_proc | fm1_do_flush);
  assign fm1_mcmd_rdy = fm1_rdy      & (fm1_do_proc | fm1_do_flush);

  //== Fork
  // Fork between the process path and the arbiter request path.
  assign fm1_f0_vld   = fm1_vld & fm1_garb_rdy & fm1_acc_rdy;
  assign fm1_garb_vld = fm1_vld & fm1_f0_rdy   & fm1_acc_rdy & ~fm1_do_flush;
  assign fm1_acc_vld  = fm1_vld & fm1_f0_rdy   & fm1_garb_rdy & ~fm1_do_flush;
  assign fm1_rdy      = fm1_garb_rdy & fm1_f0_rdy & fm1_acc_rdy;

  //== Update loopback pending
  assign loopback_pending_set         = fm1_vld & fm1_rdy & ~fm1_do_flush & ~fm1_mcmd.map_elt.last;
  assign loopback_pending_set_map_idx = fm1_mcmd.map_idx;

  //== To GRAM arbiter
  garb_cmd_t fm1_garb_req;

  assign fm1_garb_req.grid     = fm1_mcmd.map_elt.pid.grid;
  assign fm1_garb_req.critical = 1'b0;

  fifo_element #(
    .WIDTH          (GARB_CMD_W),
    .DEPTH          (2),
    .TYPE_ARRAY     (8'h12),
    .DO_RESET_DATA  (1'b0),
    .RESET_DATA_VAL (0)
  ) garb_fifo_element (
    .clk      (clk),
    .s_rst_n  (s_rst_n),

    .in_data  (fm1_garb_req),
    .in_vld   (fm1_garb_vld),
    .in_rdy   (fm1_garb_rdy),

    .out_data (feed_garb_req),
    .out_vld  (feed_garb_req_vld),
    .out_rdy  (feed_garb_req_rdy)
  );

  //== To F0
  mmacc_feed_cmd_t fm1_f0_mcmd;
  mmacc_feed_cmd_t f0_mcmd;
  logic            f0_vld;
  logic            f0_rdy;

  assign fm1_f0_mcmd = fm1_mcmd;

  fifo_element #(
    .WIDTH          (MMACC_FEED_CMD_W),
    .DEPTH          (2),
    .TYPE_ARRAY     (8'h12),
    .DO_RESET_DATA  (1'b0),
    .RESET_DATA_VAL (0)
  ) fm1_fifo_element (
    .clk      (clk),
    .s_rst_n  (s_rst_n),

    .in_data  (fm1_f0_mcmd),
    .in_vld   (fm1_f0_vld),
    .in_rdy   (fm1_f0_rdy),

    .out_data (f0_mcmd),
    .out_vld  (f0_vld),
    .out_rdy  (f0_rdy)
  );

  //== To acc via afifo
  mmacc_intern_cmd_t fm1_acc_icmd;

  assign fm1_acc_icmd.br_loop_parity = fm1_mcmd.br_loop[0];
  assign fm1_acc_icmd.batch_first_ct = fm1_mcmd.batch_first_ct;
  assign fm1_acc_icmd.batch_last_ct  = fm1_mcmd.batch_last_ct;
  assign fm1_acc_icmd.map_idx        = fm1_mcmd.map_idx;
  assign fm1_acc_icmd.map_elt        = fm1_mcmd.map_elt;

  assign feed_afifo_icmd = fm1_acc_icmd;
  assign feed_afifo_vld  = fm1_acc_vld;
  assign fm1_acc_rdy     = feed_afifo_rdy;

  //== Send batch_cmd
  logic          fm1_batch_cmd_avail;
  br_batch_cmd_t fm1_batch_cmd;

  logic          fm1_batch_cmd_sent;
  logic          fm1_batch_cmd_sentD;

  assign fm1_batch_cmd_sentD = (fm1_mcmd_vld && fm1_mcmd_rdy && fm1_mcmd.batch_last_ct) ? 1'b0 : fm1_batch_cmd_avail ? 1'b1 : fm1_batch_cmd_sent;

  always_ff @(posedge clk)
    if (!s_rst_n) fm1_batch_cmd_sent <= 1'b0;
    else          fm1_batch_cmd_sent <= fm1_batch_cmd_sentD;

  assign fm1_batch_cmd_avail   = ~fm1_batch_cmd_sent & fm1_mcmd_vld & ~fm1_do_flush;
  assign fm1_batch_cmd.pbs_nb  = fm1_mcmd.ct_nb_m1 + 1;
  assign fm1_batch_cmd.br_loop = fm1_mcmd.br_loop;

  always_ff @(posedge clk)
    if (!s_rst_n) batch_cmd_avail <= 1'b0;
    else          batch_cmd_avail <= fm1_batch_cmd_avail;

  always_ff @(posedge clk)
    batch_cmd <= fm1_batch_cmd;

// pragma translate_off
  always_ff @(posedge clk)
    if (fm1_f0_vld && fm1_f0_rdy) begin
      $display("%t > INFO: PEP_MMACC_FEED: map_idx=%0d br_loop=%0d is_flush=%0d",$time,fm1_mcmd.map_idx, fm1_mcmd.br_loop,fm1_mcmd.is_flush);
    end
// pragma translate_on

//=================================================================================================
// F0
//=================================================================================================
// From this stage:
// - Prepare GRAM read commands

  logic                    f0_f1_vld;
  logic                    f0_f1_rdy;

  //== Counters
  logic [GLWE_K_P1_W-1:0] f0_poly_id;
  logic [STG_ITER_W-1:0]  f0_stg_iter;

  logic [GLWE_K_P1_W-1:0] f0_poly_idD;
  logic [STG_ITER_W-1:0]  f0_stg_iterD;

  logic                   f0_last_poly_id;
  logic                   f0_last_stg_iter;

  logic                   f0_do_inc; // increase counters

  assign f0_last_poly_id  = f0_poly_id == (GLWE_K_P1-1);
  assign f0_last_stg_iter = f0_stg_iter == (STG_ITER_NB-1);

  assign f0_poly_idD  = f0_do_inc ? f0_last_poly_id ? '0 : f0_poly_id + 1 : f0_poly_id;
  assign f0_stg_iterD = (f0_do_inc && f0_last_poly_id) ? f0_last_stg_iter ? '0 : f0_stg_iter + 1 : f0_stg_iter;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      f0_poly_id  <= '0;
      f0_stg_iter <= '0;
    end
    else begin
      f0_poly_id  <= f0_poly_idD;
      f0_stg_iter <= f0_stg_iterD;
    end

  // Read all the GLWE data, in order to do the rotation.
  assign f0_f1_vld = f0_vld & ~f0_mcmd.is_flush;
  assign f0_rdy    = f0_f1_rdy & ((f0_last_poly_id & f0_last_stg_iter) | f0_mcmd.is_flush);

  assign f0_do_inc   = f0_f1_vld & f0_f1_rdy;

  assign br_loop_flush_done = f0_vld & f0_rdy & f0_mcmd.is_flush;

  //== LWE
  // Compute the factor used for the rotation.
  logic [LWE_COEF_W-1:0] f0_rot_factor;
  logic [LWE_COEF_W-1:0] f0_lwe;

  assign f0_lwe         = f0_mcmd.map_elt.lwe;
  assign f0_rot_factor = (f0_lwe == 0) ? 0 : 2*N - f0_lwe;


  //== to next stage
  req_cmd_t f0_f1_rcmd;
  req_cmd_t f1_rcmd;
  logic f1_vld;
  logic f1_rdy;

  // Add offset
  logic [GLWE_RAM_ADD_W-1:0] f0_add_ofs;

  assign f0_add_ofs = f0_mcmd.map_elt.pid.grof * GLWE_RAM_DEPTH_PBS;

  assign f0_f1_rcmd.batch_first_ct = f0_mcmd.batch_first_ct;
  assign f0_f1_rcmd.batch_last_ct  = f0_mcmd.batch_last_ct;
  assign f0_f1_rcmd.pbs_id         = f0_mcmd.pbs_id; // ID for processing path
  assign f0_f1_rcmd.poly_id        = f0_poly_id;
  assign f0_f1_rcmd.stg_iter       = f0_stg_iter;
  assign f0_f1_rcmd.rot_factor     = f0_rot_factor;
  assign f0_f1_rcmd.br_loop        = f0_mcmd.br_loop;
  assign f0_f1_rcmd.map_elt        = f0_mcmd.map_elt;
  assign f0_f1_rcmd.add_ofs        = f0_add_ofs;

  fifo_element #(
    .WIDTH          (REQ_CMD_W),
    .DEPTH          (2),
    .TYPE_ARRAY     (8'h12),
    .DO_RESET_DATA  (1'b0),
    .RESET_DATA_VAL (0)
  ) f0_fifo_element (
    .clk      (clk),
    .s_rst_n  (s_rst_n),

    .in_data  (f0_f1_rcmd),
    .in_vld   (f0_f1_vld),
    .in_rdy   (f0_f1_rdy),

    .out_data (f1_rcmd),
    .out_vld  (f1_vld),
    .out_rdy  (f1_rdy)
  );

// pragma translate_off
  always_ff @(posedge clk)
    if (f0_vld) begin
      assert(f0_mcmd.is_flush | f0_mcmd.map_elt.avail)
      else begin
        $fatal(1,"%t > ERROR: Processing not valid ciphertext!",$time);
      end
    end
// pragma translate_on

//=================================================================================================
// F1
//=================================================================================================
// During this stage : compute the GRAM address
//
// Note: STG_ITER_NB is a power of 2.
// In GRAM portB [1], read current position
// In GRAM portA [0], read the rotated position

// To compute the rotated address to be read, with data in reverse order:
// * Find the ID of the first element of the current :
// id_0 = stg_iter * PSI * R
// rev_id_0 = reverse_order(id_0, R, S)
// * Find the ID of the rotated element to be read that corresponds to rev_id_0
// rot_rev_id_0 = rev_id_0 + rot
// * Find the stg_iter in which it belongs to
// rot_add = reverse_order(rot_rev_id_0,R,S-PSI_W-R_W) // keep the S-PSI_W-R_W LSBs.

// Since we need to wait for the arbiter green light, we
// also regulate the chunk command frequency here, to ensure
// a regular rhythm for the decomposer.

  logic                               f1_avail;

  logic [CHUNK_NB_W-1:0]              f1_chk;
  logic [CHUNK_NB_W-1:0]              f1_chkD;
  logic                               f1_first_chk;
  logic                               f1_last_chk;

  //logic [GLWE_RAM_ADD_W-1:0]          f1_rd_add_1;
  logic [GLWE_RAM_ADD_W-1:0]          f1_rd_add_0;
  logic [PSI-1:0][GLWE_RAM_ADD_W-1:0] f1_rd_add_0_rot;
  logic [N_W-1:0]                     f1_coef_idx0; // index in natural order
  logic [STG_ITER_W-1:0]              f1_rot_add;

  assign f1_first_chk  = f1_chk == 0;
  assign f1_last_chk   = f1_chk == (CHUNK_NB-1);

  assign f1_chkD       = (f1_avail || !f1_first_chk) ? f1_last_chk ? '0 : f1_chk + 1 : f1_chk;

  assign f1_rot_add = get_rot_add(.pos         (f1_coef_idx0),
                                  .rot_factor  (f1_rcmd.rot_factor));

  assign f1_coef_idx0  = {f1_rcmd.stg_iter,{PSI_R_W{1'b0}}};
  //assign f1_rd_add_1   = {f1_rcmd.poly_id,f1_rcmd.stg_iter} + f1_rcmd.add_ofs;
  assign f1_rd_add_0   = {f1_rcmd.poly_id,f1_rot_add}       + f1_rcmd.add_ofs;

  always_ff @(posedge clk)
    if (!s_rst_n) f1_chk <= '0;
    else          f1_chk <= f1_chkD;

  assign f1_rd_add_0_rot = {PSI{f1_rd_add_0}};

  //== Control
  // NOTE : arbiter access authorization used here. Command must be sent in 2 cycles exactly.
  // This is done in all the GRAM masters.
  logic f1_rdy_tmp;

  assign f1_rdy_tmp = garb_rot_avail_1h[f1_rcmd.map_elt.pid.grid];
  assign f1_rdy     = f1_rdy_tmp & f1_last_chk;
  assign f1_avail   = f1_vld & f1_rdy_tmp & f1_first_chk;

// pragma translate_off
// Check that at a start of a new arbitration, f1_vld should be 1.
  logic [GRAM_NB-1:0]   _garb_rot_avail_1h_dly;

  always_ff @(posedge clk)
    if (!s_rst_n) _garb_rot_avail_1h_dly <= '0;
    else          _garb_rot_avail_1h_dly <= garb_rot_avail_1h;

  always_ff @(posedge clk)
    if (|(garb_rot_avail_1h & ~_garb_rot_avail_1h_dly)) begin // posedge
      assert(f1_vld)
      else begin
        $fatal(1,"%t > ERROR: Arbitration enabled, but no command valid!",$time);
      end

      assert(garb_rot_avail_1h[f1_rcmd.map_elt.pid.grid])
      else begin
        $fatal(1,"%t > ERROR: Arbitration GRAM id is not the one needed by the command!",$time);
      end
    end
// pragma translate_on

  // Output
  assign out_f1_rd_en   = f1_avail;
  assign out_f1_rd_add  = f1_rd_add_0;
  assign out_f1_rd_grid = f1_rcmd.map_elt.pid.grid;

//=================================================================================================
// FF2
//=================================================================================================
// Note that unused fields in rcmd will be removed by the synthesizer.
// Shift register : wait for the datar.
  req_cmd_t            ff2_rcmd_sr [SR_DEPTH-1:0];
  logic [SR_DEPTH-1:0] ff2_avail_sr;
  req_cmd_t            ff2_rcmd_srD [SR_DEPTH-1:0];
  logic [SR_DEPTH-1:0] ff2_avail_srD;

  assign ff2_rcmd_srD[0]  = f1_rcmd;
  assign ff2_avail_srD[0] = f1_avail;
  generate
    if (SR_DEPTH>1) begin
      assign ff2_rcmd_srD[SR_DEPTH-1:1]  = ff2_rcmd_sr[SR_DEPTH-2:0];
      assign ff2_avail_srD[SR_DEPTH-1:1] = ff2_avail_sr[SR_DEPTH-2:0];
    end
  endgenerate

  always_ff @(posedge clk)
    if (!s_rst_n) ff2_avail_sr <= '0;
    else          ff2_avail_sr <= ff2_avail_srD;

  always_ff @(posedge clk)
    ff2_rcmd_sr <= ff2_rcmd_srD;

//=================================================================================================
// FF3
//=================================================================================================
// Read "not rotated data"
  logic [GLWE_RAM_ADD_W-1:0] ff3_rd_add_1;
  req_cmd_t                  ff3_rcmd;
  logic                      ff3_avail;
  logic                      ff3_rd_en;

  assign ff3_avail = ff2_avail_sr[RD_DATA_CYCLE-1];
  assign ff3_rcmd  = ff2_rcmd_sr[RD_DATA_CYCLE-1];

  assign ff3_rd_en = ff3_avail & garb_dat_avail_1h[ff3_rcmd.map_elt.pid.grid];

  assign ff3_rd_add_1 = {ff3_rcmd.poly_id,ff3_rcmd.stg_iter} + ff3_rcmd.add_ofs;

// pragma translate_off
// check that the arbitration is available when needed.
  always_ff @(posedge clk)
    if (ff3_avail)
      assert(garb_dat_avail_1h[ff3_rcmd.map_elt.pid.grid])
      else begin
        $fatal(1,"%t > ERROR: garb_dat_avail_1h not valid when needed for the read of non rotated data!",$time);
      end
// pragma translate_on

  // Output
  assign out_ff3_rd_en   = ff3_rd_en;
  assign out_ff3_rd_add  = ff3_rd_add_1;
  assign out_ff3_rd_grid = ff3_rcmd.map_elt.pid.grid;

//=================================================================================================
// Output
//=================================================================================================
  // Instant when rotated data is avail
  assign out_s0_avail = ff2_avail_sr[GRAM_AVAIL_CYCLE-1];
  assign out_s0_rcmd  = ff2_rcmd_sr[GRAM_AVAIL_CYCLE-1];

  // instant when non rotated data is avail
  assign out_ss1_avail = ff2_avail_sr[SR_DEPTH-1];
  assign out_ss1_rcmd  = ff2_rcmd_sr[SR_DEPTH-1];

endmodule
