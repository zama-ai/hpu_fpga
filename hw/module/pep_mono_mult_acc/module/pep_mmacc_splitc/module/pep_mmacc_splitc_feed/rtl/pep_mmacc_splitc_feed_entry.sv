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
// Here the module checks that the environment (bsk) is ready for the process of
// a new command. A command is sent to the main and the subsidiary parts.
//
// Notation:
// GRAM : stands for GLWE RAM
//
// ==============================================================================================

module pep_mmacc_splitc_feed_entry
  import param_tfhe_pkg::*;
  import param_ntt_pkg::*;
  import ntt_core_common_param_pkg::*;
  import top_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import pep_mmacc_common_param_pkg::*;
(
  input  logic                          clk,        // clock
  input  logic                          s_rst_n,    // synchronous reset

  // From ffifo : command from sequencer
  input  logic [PBS_CMD_W-1:0]          ffifo_feed_pcmd,
  input  logic                          ffifo_feed_vld,
  output logic                          ffifo_feed_rdy,

  // Output command for main
  output logic [MMACC_FEED_CMD_W-1:0]   main_mcmd,
  output logic                          main_vld,
  input  logic                          main_rdy,

  // Output command for subs
  output logic [MMACC_FEED_CMD_W-1:0]   subs_mcmd,
  output logic                          subs_vld,
  input  logic                          subs_rdy,

  // bsk filling status
  input  logic                          inc_bsk_wr_ptr,

  // reset cache
  input  logic                          reset_cache
);

//=================================================================================================
// Input pipe
//=================================================================================================
  logic in_inc_bsk_wr_ptr;
  logic reset_loop;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      in_inc_bsk_wr_ptr <= 1'b0;
      reset_loop        <= 1'b0;
    end
    else begin
      in_inc_bsk_wr_ptr <= inc_bsk_wr_ptr;
      reset_loop        <= reset_cache;
    end

//=================================================================================================
// BSK pointers
//=================================================================================================
// Keep track of the filling of the BSK. Do not start command if the key is not present.
// The count is kept for the feeding part.
  logic [LWE_K_W:0] bsk_wp;
  logic [LWE_K_W:0] bsk_rp;
  logic [LWE_K_W:0] bsk_wpD;
  logic [LWE_K_W:0] bsk_rpD;
  logic             bsk_empty;
  logic             bsk_full;
  logic             bsk_wp_last;
  logic             bsk_rp_last;

  logic             bsk_rd_done;

  always_ff @(posedge clk)
    if (!s_rst_n || reset_loop) begin
      bsk_wp <= '0;
      bsk_rp <= '0;
    end
    else begin
      bsk_rp <= bsk_rpD;
      bsk_wp <= bsk_wpD;
    end

  assign bsk_wp_last = bsk_wp == (LWE_K-1);
  assign bsk_rp_last = bsk_rp == (LWE_K-1);

  assign bsk_empty = bsk_rp == bsk_wp;
  assign bsk_full  = (bsk_rp[LWE_K_W-1:0] == bsk_wp[LWE_K_W-1:0]) & (bsk_rp[LWE_K_W] != bsk_wp[LWE_K_W]);

  assign bsk_wpD = in_inc_bsk_wr_ptr ? bsk_wp_last ? {~bsk_wp[LWE_K_W],{LWE_K_W{1'b0}}} : bsk_wp + 1 : bsk_wp;
  assign bsk_rpD = bsk_rd_done       ? bsk_rp_last ? {~bsk_rp[LWE_K_W],{LWE_K_W{1'b0}}} : bsk_rp + 1 : bsk_rp;

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      if (in_inc_bsk_wr_ptr) begin
        assert(!bsk_full)
        else begin
          $fatal(1,"%t> ERROR: Increase BSK write pointer, while it is already full.",$time);
        end
      end
    end
// pragma translate_on

//=================================================================================================
// fm2
//=================================================================================================
// During this stage
// - extract the pid map info from the command
// - Send command for the accumulate part.

  pbs_cmd_t                    ffifo_feed_pcmd_s;

  logic                        fm2_vld;
  logic                        fm2_rdy;

  logic                        fm2_main_vld;
  logic                        fm2_main_rdy;
  logic                        fm2_subs_vld;
  logic                        fm2_subs_rdy;

  // Counters
  logic [BPBS_ID_W-1:0]        fm2_map_idx;  // ID in map
  logic [BPBS_NB_W-1:0]        fm2_pbs_cnt;  // Count available CT
  logic [BPBS_ID_W-1:0]        fm2_map_idxD;
  logic [BPBS_NB_W-1:0]        fm2_pbs_cntD;
  logic                        fm2_first_pbs_cnt;
  logic                        fm2_last_pbs_cnt;

  map_elt_t                    fm2_map_elt;
  logic                        fm2_ct_avail; //available for the process

  logic                        fm2_do_proc;
  logic                        fm2_do_bypass;
  logic                        fm2_do_flush;
  logic                        fm2_do_flush_tmp;

  map_elt_t [BATCH_PBS_NB-1:0] fm2_map;

  // Cast
  assign ffifo_feed_pcmd_s = ffifo_feed_pcmd; // cast
  assign fm2_map           = ffifo_feed_pcmd_s.map; // cast
  assign fm2_last_pbs_cnt  = fm2_pbs_cnt == ffifo_feed_pcmd_s.ct_nb_m1;
  assign fm2_first_pbs_cnt = fm2_pbs_cnt == '0;

  assign fm2_map_elt       = fm2_map[fm2_map_idx];
  assign fm2_pbs_cntD      = fm2_do_proc ? fm2_last_pbs_cnt ? '0 : fm2_pbs_cnt + 1 : fm2_pbs_cnt;
  assign fm2_map_idxD      = (fm2_do_proc || fm2_do_bypass) ? (fm2_do_proc && fm2_last_pbs_cnt) ? '0 : fm2_map_idx + 1 : fm2_map_idx;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      fm2_map_idx   <= '0;
      fm2_pbs_cnt   <= '0;
    end
    else begin
      fm2_map_idx   <= fm2_map_idxD;
      fm2_pbs_cnt   <= fm2_pbs_cntD;
    end

  //== Control
  logic fm2_do_proc_tmp;
  logic fm2_do_proc_tmp2;
  assign fm2_do_proc_tmp2 = ~bsk_empty & ~ffifo_feed_pcmd_s.is_flush
                            & fm2_map_elt.avail;
  assign fm2_do_proc_tmp  = ffifo_feed_vld & fm2_do_proc_tmp2;
  assign fm2_do_bypass    = ffifo_feed_vld & ~fm2_map_elt.avail & ~ffifo_feed_pcmd_s.is_flush;
  assign fm2_do_flush_tmp = ffifo_feed_pcmd_s.is_flush & (~bsk_empty || reset_loop);
  assign fm2_do_flush     = ffifo_feed_vld & fm2_do_flush_tmp;

  assign fm2_do_proc    = fm2_do_proc_tmp & fm2_rdy;
  assign fm2_vld        = (fm2_do_proc_tmp | fm2_do_flush);
  assign ffifo_feed_rdy = fm2_rdy & ((fm2_do_proc_tmp2 & fm2_last_pbs_cnt) | fm2_do_flush_tmp);

// pragma translate_off
  always_ff @(posedge clk)
    if (ffifo_feed_vld && ffifo_feed_pcmd_s.is_flush)
      assert(fm2_do_proc == 1'b0)
      else begin
        $fatal(1,"%t > ERROR: Processing flush command. Should not trigger the regular processing path!", $time);
      end
// pragma translate_on

  //== Fork
  // Fork between the process paths
  assign fm2_main_vld = fm2_vld & fm2_subs_rdy;
  assign fm2_subs_vld = fm2_vld & fm2_main_rdy;
  assign fm2_rdy      = fm2_main_rdy & fm2_subs_rdy;

  //== To Fm1
  mmacc_feed_cmd_t fm2_mcmd;

  assign fm2_mcmd.is_flush      = ffifo_feed_pcmd_s.is_flush;
  assign fm2_mcmd.batch_first_ct= fm2_first_pbs_cnt;
  assign fm2_mcmd.batch_last_ct = fm2_last_pbs_cnt;
  assign fm2_mcmd.pbs_id        = fm2_pbs_cnt;
  assign fm2_mcmd.br_loop       = ffifo_feed_pcmd_s.br_loop;
  assign fm2_mcmd.map_elt       = fm2_map_elt;
  assign fm2_mcmd.map_idx       = fm2_map_idx;
  assign fm2_mcmd.ct_nb_m1      = ffifo_feed_pcmd_s.ct_nb_m1;

  fifo_element #(
    .WIDTH          (MMACC_FEED_CMD_W),
    .DEPTH          (2),
    .TYPE_ARRAY     (8'h12),
    .DO_RESET_DATA  (1'b0),
    .RESET_DATA_VAL (0)
  ) fm2_main_fifo_element (
    .clk      (clk),
    .s_rst_n  (s_rst_n),

    .in_data  (fm2_mcmd),
    .in_vld   (fm2_main_vld),
    .in_rdy   (fm2_main_rdy),

    .out_data (main_mcmd),
    .out_vld  (main_vld),
    .out_rdy  (main_rdy)
  );

  fifo_element #(
    .WIDTH          (MMACC_FEED_CMD_W),
    .DEPTH          (2),
    .TYPE_ARRAY     (8'h12),
    .DO_RESET_DATA  (1'b0),
    .RESET_DATA_VAL (0)
  ) fm2_subs_fifo_element (
    .clk      (clk),
    .s_rst_n  (s_rst_n),

    .in_data  (fm2_mcmd),
    .in_vld   (fm2_subs_vld),
    .in_rdy   (fm2_subs_rdy),

    .out_data (subs_mcmd),
    .out_vld  (subs_vld),
    .out_rdy  (subs_rdy)
  );

  //== bsk_rd_done
  // Note : do not register the following signal. It is used to update bsk_rp, and so bsk_empty,
  // which should be up to date the next cycle.
  //assign bsk_rd_done = fm1_f0_vld & fm1_f0_rdy & (fm2_mcmd.batch_last_ct | fm2_mcmd.is_flush);
  assign bsk_rd_done = ffifo_feed_rdy & ffifo_feed_vld;

endmodule
