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

module pep_ks_ctrl_feed
  import common_definition_pkg::*;
  import param_tfhe_pkg::*;
  import pep_common_param_pkg::*;
  import pep_ks_common_param_pkg::*;
#(
  parameter  int DATA_LATENCY   = 6, // Latency for read data to come back
  parameter  int BLWE_RAM_DEPTH = (BLWE_K+LBY-1)/LBY * 8 * 4,
  parameter  int ALMOST_DONE_BLINE_ID = 0, // almost done sent at the end of this bline
  localparam int BLWE_RAM_ADD_W = $clog2(BLWE_RAM_DEPTH)
)
(
  input  logic                               clk,        // clock
  input  logic                               s_rst_n,    // synchronous reset

  input  logic                               reset_cache,

  // KSK status
  input  logic [TOTAL_BATCH_NB-1:0]          ksk_empty,
  output logic [TOTAL_BATCH_NB-1:0]          inc_ksk_rd_ptr,
  input  logic [TOTAL_BATCH_NB-1:0]          ofifo_inc_rp,

  // From ffifo
  input  logic [PROC_CMD_W-1:0]              ffifo_feed_pcmd,
  input  logic                               ffifo_feed_vld,
  output logic                               ffifo_feed_rdy,

  // Rd BLRAM
  output logic [LBY-1:0]                     ctrl_blram_rd_en,
  output logic [LBY-1:0][BLWE_RAM_ADD_W-1:0] ctrl_blram_rd_add,
  input  logic [LBY-1:0][KS_DECOMP_W-1:0]    blram_ctrl_rd_data,
  input  logic [LBY-1:0]                     blram_ctrl_rd_data_avail,

  // To mult
  output logic [LBY-1:0]                     ctrl_mult_avail,
  output logic [LBY-1:0][LBZ-1:0][KS_B_W-1:0]ctrl_mult_data,
  output logic [LBY-1:0][LBZ-1:0]            ctrl_mult_sign,
  output logic                               ctrl_mult_last_eol,
  output logic                               ctrl_mult_last_eoy,
  output logic                               ctrl_mult_last_last_iter,
  output logic [TOTAL_BATCH_NB_W-1:0]        ctrl_mult_last_batch_id,

  // To ksk manager
  output logic [KS_BATCH_CMD_W-1:0]          batch_cmd,
  output logic                               batch_cmd_avail, // pulse

  // To sequencer
  output logic                               proc_almost_done
);

//=================================================================================================
// localparam
//=================================================================================================
  localparam int SR_DEPTH = DATA_LATENCY + 1; // +1 : register data from BLRAM
                                              // /!\ depends highly on pep_ks_ctrl_read architecture

  localparam int BATCH_ADD_NB                = KS_BLOCK_LINE_NB * BATCH_PBS_NB;
  localparam bit SEND_OFIFO_INC_ON_LAST_BCOL = LWE_K % LBX != 0;

  localparam [TOTAL_BATCH_NB-1:0][31:0] BATCH_ADD_OFS = get_batch_add_ofs();

//=================================================================================================
// type
//=================================================================================================
  typedef struct packed{
    logic                        eoy;
    logic                        last_iter;
    logic [TOTAL_BATCH_NB_W-1:0] batch_id;
  } side_t;

  localparam int SIDE_W = $bits(side_t);

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
// Input pipe
// ============================================================================================== --
  logic                  reset_loop;

  always_ff @(posedge clk)
    if (!s_rst_n) reset_loop <= 1'b0;
    else          reset_loop <= reset_cache;

//=================================================================================================
// Output fifo pointers
//=================================================================================================
  logic [TOTAL_BATCH_NB-1:0][OUT_FIFO_DEPTH_W:0] ofifo_rp;
  logic [TOTAL_BATCH_NB-1:0][OUT_FIFO_DEPTH_W:0] ofifo_wp;
  logic [TOTAL_BATCH_NB-1:0][OUT_FIFO_DEPTH_W:0] ofifo_rpD;
  logic [TOTAL_BATCH_NB-1:0][OUT_FIFO_DEPTH_W:0] ofifo_wpD;
  logic [TOTAL_BATCH_NB-1:0]                     ofifo_full;
  logic [TOTAL_BATCH_NB-1:0]                     ofifo_empty;
  logic [TOTAL_BATCH_NB-1:0]                     ofifo_inc_wp;

  always_ff @(posedge clk)
    if (!s_rst_n || reset_loop) begin
      ofifo_rp <= '0;
      ofifo_wp <= '0;
    end
    else begin
      ofifo_rp <= ofifo_rpD;
      ofifo_wp <= ofifo_wpD;
    end

  always_comb
    for (int i=0; i<TOTAL_BATCH_NB; i=i+1) begin
      ofifo_rpD[i]   = ofifo_inc_rp[i] ? ofifo_rp[i][OUT_FIFO_DEPTH_W-1:0] == OUT_FIFO_DEPTH-1 ?
                                        {~ofifo_rp[i][OUT_FIFO_DEPTH_W],{OUT_FIFO_DEPTH_W{1'b0}}} : ofifo_rp[i] + 1 : ofifo_rp[i];
      ofifo_wpD[i]   = ofifo_inc_wp[i] ? ofifo_wp[i][OUT_FIFO_DEPTH_W-1:0] == OUT_FIFO_DEPTH-1 ?
                                        {~ofifo_wp[i][OUT_FIFO_DEPTH_W],{OUT_FIFO_DEPTH_W{1'b0}}} : ofifo_wp[i] + 1 : ofifo_wp[i];
      ofifo_full[i]  = (ofifo_rp[i][OUT_FIFO_DEPTH_W] != ofifo_wp[i][OUT_FIFO_DEPTH_W])
                      & (ofifo_rp[i][OUT_FIFO_DEPTH_W-1:0] == ofifo_wp[i][OUT_FIFO_DEPTH_W-1:0]);
      ofifo_empty[i] = (ofifo_rp[i] == ofifo_wp[i]);
    end

//=================================================================================================
// F0
//=================================================================================================
// Build BLRAM read command
// Note that 1 BLRAM data contains all the decomposition.
// Therefore 1 reading is used during KS_LG_NB cycles
  proc_cmd_t ffifo_feed_pcmd_s;

  assign ffifo_feed_pcmd_s = ffifo_feed_pcmd;

  logic [KS_BLOCK_LINE_W-1:0] f0_bline;
  logic [BPBS_ID_W-1:0]       f0_pbs_cnt;
  logic [KS_LG_W-1:0]         f0_lvl;
  logic [KS_BLOCK_LINE_W-1:0] f0_blineD;
  logic [BPBS_ID_W-1:0]       f0_pbs_cntD;
  logic [KS_LG_W-1:0]         f0_lvlD;
  logic                       f0_last_pbs_cnt;
  logic                       f0_last_bline;
  logic                       f0_last_lvl;
  logic                       f0_almost_bline;
  logic                       f0_use_wrap_pbs;
  logic                       f0_use_wrap_pbsD;
  logic [PID_W-1:0]           f0_wrap_pbs_cnt;

  logic                       f0_do_wrap_pbs;
  logic                       f0_do_read;
  logic                       f0_do_read_exec; // effective one
  logic                       f0_almost_done;

  logic [BLWE_RAM_ADD_W-1:0] f0_add_pbs_ofs;
  logic [BLWE_RAM_ADD_W-1:0] f0_add_ofs;
  logic [BLWE_RAM_ADD_W-1:0] f0_add_pbs_ofsD;
  logic [BLWE_RAM_ADD_W-1:0] f0_add_ofsD;
  logic [BLWE_RAM_ADD_W-1:0] f0_add;

  // pbs_cnt value at which the pbs_id wrap to 0
  assign f0_wrap_pbs_cnt = TOTAL_PBS_NB - ffifo_feed_pcmd_s.first_pid - 1;
  assign f0_do_wrap_pbs  = (f0_pbs_cnt == f0_wrap_pbs_cnt);
  assign f0_almost_bline = f0_bline == ALMOST_DONE_BLINE_ID;
  assign f0_last_pbs_cnt = f0_pbs_cnt == ffifo_feed_pcmd_s.pbs_cnt_max;
  assign f0_last_bline   = f0_bline == KS_BLOCK_LINE_NB-1;
  assign f0_last_lvl     = f0_lvl == KS_LG_NB-1;
  assign f0_lvlD         = f0_do_read ? f0_last_lvl ? '0 : f0_lvl + 1 : f0_lvl;
  assign f0_pbs_cntD     = f0_do_read && f0_last_lvl ? f0_last_pbs_cnt ? '0 : f0_pbs_cnt + 1 : f0_pbs_cnt;
  assign f0_blineD       = f0_do_read && f0_last_lvl && f0_last_pbs_cnt ? f0_last_bline ? '0 : f0_bline + 1 : f0_bline;
  assign f0_use_wrap_pbsD = f0_do_read && f0_last_lvl ? f0_last_pbs_cnt ? 1'b0 : f0_do_wrap_pbs ? 1'b1 : f0_use_wrap_pbs : f0_use_wrap_pbs;

  assign f0_add_ofs       = f0_use_wrap_pbs ? '0 : ffifo_feed_pcmd_s.first_pid * KS_BLOCK_LINE_NB;
  assign f0_add_pbs_ofsD  = f0_do_read && f0_last_lvl ? (f0_do_wrap_pbs || f0_last_pbs_cnt) ? '0 : f0_add_pbs_ofs + KS_BLOCK_LINE_NB : f0_add_pbs_ofs;
  assign f0_add           = f0_bline + f0_add_pbs_ofs + f0_add_ofs;

  assign f0_almost_done = f0_do_read & f0_almost_bline & f0_last_lvl & f0_last_pbs_cnt; // TOREVIEW

  always_ff @(posedge clk)
    if (!s_rst_n || reset_loop) begin
      f0_pbs_cnt       <= '0;
      f0_bline         <= '0;
      f0_add_pbs_ofs   <= '0;
      f0_lvl           <= '0;
      f0_use_wrap_pbs  <= 1'b0;
      proc_almost_done <= 1'b0;
    end
    else begin
      f0_pbs_cnt       <= f0_pbs_cntD;
      f0_bline         <= f0_blineD;
      f0_add_pbs_ofs   <= f0_add_pbs_ofsD;
      f0_lvl           <= f0_lvlD;
      f0_use_wrap_pbs  <= f0_use_wrap_pbsD;
      proc_almost_done <= f0_almost_done;
    end

//-----------------------------------------
// Do read
//-----------------------------------------
  logic f0_ksk_empty;
  logic f0_ofifo_full;
  logic f0_rd_condition;

  assign f0_ksk_empty  = (ksk_empty & ffifo_feed_pcmd_s.batch_id_1h) != 0;
  assign f0_ofifo_full = (ofifo_full & ffifo_feed_pcmd_s.batch_id_1h) != 0;
  assign f0_rd_condition = (~f0_ksk_empty & ~f0_ofifo_full);
  assign f0_do_read    = ffifo_feed_vld & f0_rd_condition & ~reset_loop;
  assign f0_do_read_exec = f0_do_read & (f0_lvl == '0);

//-----------------------------------------
// Control
//-----------------------------------------
  logic                      f0_last_ks_loop;
  logic [TOTAL_BATCH_NB-1:0] f0_inc_ksk_rp;
  logic                      f0_do_read_last;
  logic                      f0_ofifo_inc_wp;

  assign f0_do_read_last = f0_do_read & f0_last_lvl & f0_last_pbs_cnt & f0_last_bline;
  assign f0_last_ks_loop = ffifo_feed_pcmd_s.ks_loop == KS_BLOCK_COL_NB-1;
  assign ffifo_feed_rdy  = (f0_last_lvl & f0_last_pbs_cnt & f0_last_bline & f0_rd_condition) | reset_loop;
  assign f0_inc_ksk_rp   = {TOTAL_BATCH_NB{f0_do_read_last}} & ffifo_feed_pcmd_s.batch_id_1h;
  // If the last Bcol starts with the body, this bcol is not sent into the OFIFO.
  // That's why we do not count it.
  assign f0_ofifo_inc_wp = ffifo_feed_vld & ffifo_feed_rdy & (~f0_last_ks_loop | SEND_OFIFO_INC_ON_LAST_BCOL);
  assign ofifo_inc_wp    = {TOTAL_BATCH_NB{f0_ofifo_inc_wp}} & ffifo_feed_pcmd_s.batch_id_1h;

  // Note cannot register this signal, since it is used to update the ksk_rp, and so the ksk_empty
  // which should be valid next cycle
  assign inc_ksk_rd_ptr = f0_inc_ksk_rp;

//-----------------------------------------
// Send batch cmd
//-----------------------------------------
  logic          f0_batch_cmd_avail;
  ks_batch_cmd_t f0_batch_cmd;

  logic          f0_batch_cmd_sent;
  logic          f0_batch_cmd_sentD;

  assign f0_batch_cmd_sentD = (ffifo_feed_vld && ffifo_feed_rdy) ? 1'b0 : f0_batch_cmd_avail ? 1'b1 : f0_batch_cmd_sent;

  always_ff @(posedge clk)
    if (!s_rst_n) f0_batch_cmd_sent <= 1'b0;
    else          f0_batch_cmd_sent <= f0_batch_cmd_sentD;

  assign f0_batch_cmd_avail   = ~f0_batch_cmd_sent & f0_do_read;
  assign f0_batch_cmd.pbs_nb  = ffifo_feed_pcmd_s.pbs_cnt_max + 1;
  assign f0_batch_cmd.ks_loop = ffifo_feed_pcmd_s.ks_loop;

  always_ff @(posedge clk)
    if (!s_rst_n) batch_cmd_avail <= 1'b0;
    else          batch_cmd_avail <= f0_batch_cmd_avail;

  always_ff @(posedge clk)
    batch_cmd <= f0_batch_cmd;

//-----------------------------------------
// Shift register
//-----------------------------------------
// To mimic the RAM reading latency
// Put it here in common, to save some logic
  side_t  f0_side;

  logic [SR_DEPTH-1:0] f1_avail_sr;
  side_t               f1_side_sr [SR_DEPTH-1:0];
  logic [SR_DEPTH-1:0] f1_avail_srD;
  side_t               f1_side_srD [SR_DEPTH-1:0];

  assign f0_side.eoy       = f0_last_pbs_cnt;
  assign f0_side.last_iter = f0_last_bline;
  assign f0_side.batch_id  = ffifo_feed_pcmd_s.batch_id;

  assign f1_avail_srD[0] = f0_do_read_exec;
  assign f1_side_srD[0]  = f0_side;
  generate
    if (SR_DEPTH>1) begin
      assign f1_side_srD[SR_DEPTH-1:1]  = f1_side_sr[SR_DEPTH-2:0];
      assign f1_avail_srD[SR_DEPTH-1:1] = f1_avail_sr[SR_DEPTH-2:0];
    end
  endgenerate

  always_ff @(posedge clk)
    if (!s_rst_n) f1_avail_sr <= '0;
    else          f1_avail_sr <= f1_avail_srD;

  always_ff @(posedge clk)
    f1_side_sr <= f1_side_srD;

//-----------------------------------------
// Read nodes
//-----------------------------------------
  logic [LBY:0]                     node_avail;
  logic [LBY:0][BLWE_RAM_ADD_W-1:0] node_add;
  logic [LBY:0]                     node_data_avail;
  logic [LBY:0]                     node_data_last_y;
  side_t                            node_data_side [LBY:0];
  logic [LBY-1:0]                   ctrl_mult_eol;


  assign node_avail[0]       = f0_do_read_exec;
  assign node_add[0]         = f0_add;
  assign node_data_avail[0]  = f1_avail_sr[SR_DEPTH-1];
  assign node_data_side[0]   = f1_side_sr[SR_DEPTH-1];
  assign node_data_last_y[0] = f1_side_sr[SR_DEPTH-1].last_iter;

  side_t ctrl_mult_side [LBY-1:0];
  assign ctrl_mult_last_eoy       = ctrl_mult_side[LBY-1].eoy;
  assign ctrl_mult_last_last_iter = ctrl_mult_side[LBY-1].last_iter;
  assign ctrl_mult_last_batch_id  = ctrl_mult_side[LBY-1].batch_id;
  assign ctrl_mult_last_eol       = ctrl_mult_eol[LBY-1];

  generate
    for (genvar gen_i=0; gen_i<LBY; gen_i=gen_i+1) begin : gen_lb_loop
    pep_ks_ctrl_read
    #(
      .ID                (gen_i),
      .BLWE_RAM_DEPTH    (BLWE_RAM_DEPTH),
      .SIDE_W            (SIDE_W)
    ) pep_ks_ctrl_read (
      .clk                      (clk),
      .s_rst_n                  (s_rst_n),

      .ctrl_blram_rd_en         (ctrl_blram_rd_en[gen_i]),
      .ctrl_blram_rd_add        (ctrl_blram_rd_add[gen_i]),
      .blram_ctrl_rd_data       (blram_ctrl_rd_data[gen_i]),
      .blram_ctrl_rd_data_avail (blram_ctrl_rd_data_avail[gen_i]),

      .prev_avail               (node_avail[gen_i]),
      .prev_add                 (node_add[gen_i]),
      .prev_data_avail          (node_data_avail[gen_i]),
      .prev_data_last_y         (node_data_last_y[gen_i]),
      .prev_data_side           (node_data_side[gen_i]),

      .next_avail               (node_avail[gen_i+1]),
      .next_add                 (node_add[gen_i+1]),
      .next_data_avail          (node_data_avail[gen_i+1]),
      .next_data_last_y         (node_data_last_y[gen_i+1]),
      .next_data_side           (node_data_side[gen_i+1]),

      .ctrl_mult_avail          (ctrl_mult_avail[gen_i]),
      .ctrl_mult_data           (ctrl_mult_data[gen_i]),
      .ctrl_mult_sign           (ctrl_mult_sign[gen_i]),
      .ctrl_mult_eol            (ctrl_mult_eol[gen_i]),
      .ctrl_mult_side           (ctrl_mult_side[gen_i])
    );
    end
  endgenerate

endmodule
