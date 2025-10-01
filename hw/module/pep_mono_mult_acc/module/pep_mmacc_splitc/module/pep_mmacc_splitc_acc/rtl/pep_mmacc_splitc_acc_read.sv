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

module pep_mmacc_splitc_acc_read
  import common_definition_pkg::*;
  import param_tfhe_pkg::*;
  import ntt_core_common_param_pkg::*;
  import top_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import pep_mmacc_common_param_pkg::*;
#(
  parameter  int DATA_LATENCY        = 5, // Latency for read data to come back
  parameter  int RAM_LATENCY         = 2,
  parameter  int MSPLIT_FACTOR       = 2,
  parameter  int FIFO_NTT_ACC_DEPTH  = 1024, // Physical RAM depth. Should be a power of 2
  localparam int HPSI                = MSPLIT_FACTOR*PSI / MSPLIT_DIV
)
(
  input  logic                                                   clk,        // clock
  input  logic                                                   s_rst_n,    // synchronous reset

  // NTT core -> ACC
  input  logic                                                   ntt_acc_avail,
  input  logic [HPSI-1:0][R-1:0][MOD_Q_W-1:0]                    ntt_acc_data,
  input  logic                                                   ntt_acc_sob,
  input  logic                                                   ntt_acc_eob,
  input  logic                                                   ntt_acc_sol,
  input  logic                                                   ntt_acc_eol,
  input  logic                                                   ntt_acc_sog,
  input  logic                                                   ntt_acc_eog,
  input  logic [BPBS_ID_W-1:0]                                   ntt_acc_pbs_id,

  // GRAM arbiter
  output logic [GARB_CMD_W-1:0]                                  acc_garb_req,
  output logic                                                   acc_garb_req_vld,
  input  logic                                                   acc_garb_req_rdy,

  input  logic [GRAM_NB-1:0]                                     garb_acc_rd_avail_1h,

  // Prepare GRAM access
  output logic                                                   out_a0_do_read,
  output logic [GLWE_RAM_ADD_W-1:0]                              out_a0_rd_add,
  output logic [GRAM_ID_W-1:0]                                   out_a0_rd_grid,

  output logic                                                   out_s0_mask_null,
  output logic [HPSI-1:0][R-1:0][MOD_Q_W-1:0]                    out_s1_ntt_acc_data,
  output logic                                                   out_s1_avail,
  output logic [GLWE_RAM_ADD_W-1:0]                              out_s1_add,
  output logic [GRAM_ID_W-1:0]                                   out_s1_grid,

  // From afifo
  input  logic [MMACC_INTERN_CMD_W-1:0]                          afifo_acc_icmd,
  input  logic                                                   afifo_acc_vld,
  output logic                                                   afifo_acc_rdy,

  // To sfifo
  output logic [MMACC_INTERN_CMD_W-1:0]                          acc_sfifo_icmd,
  output logic                                                   acc_sfifo_avail,

  // Status
  output logic                                                   acc_feed_done,
  output logic [BPBS_ID_W-1:0]                                   acc_feed_done_map_idx,
  output logic                                                   br_loop_proc_done,

  // error
  output logic                                                   error // infifo overflow

);

//=================================================================================================
// localparam
//=================================================================================================
  localparam int SR_DEPTH     = DATA_LATENCY + 2 // a1 + a2 : for address computation
                                             + 2; // gram rdata pipe + format s0
  localparam int SR_DATA_DEPTH = SR_DEPTH - 1 // Pipe on dec signal
                                          - 2; // -2 infifo latency on sample signal

  localparam int GLWE_RAM_DEPTH_PBS = STG_ITER_NB * GLWE_K_P1;

  localparam int GRAM_ACCESS_ERROR_OFS = 0;
  localparam int INFIFO_OVF_ERROR_OFS  = 1;

  // Number of ciphertext that can be stored entirely in INFIFO
  localparam int INFIFO_CT_NB    = FIFO_NTT_ACC_DEPTH / GLWE_RAM_DEPTH_PBS;
  localparam int INFIFO_CT_THRES = INFIFO_CT_NB / 2; // TOREVIEW

  localparam int INFIFO_DEPTH_W  = $clog2(FIFO_NTT_ACC_DEPTH) == 0 ? 1 : $clog2(FIFO_NTT_ACC_DEPTH) + 1; // add 1 bit for extra pipes within infifo

  generate
    if (INFIFO_CT_NB < 3) begin : __UNSUPPORTED_FIFO_NTT_ACC_DEPTH
      $fatal(1,"> ERROR: FIFO_NTT_ACC_DEPTH (%0d) is not big enough. It should be able to store at least 3 whole ciphertext. Now it stores only %0d.",FIFO_NTT_ACC_DEPTH,INFIFO_CT_NB);
    end
  endgenerate

//=================================================================================================
// ntt_acc input FIFO
//=================================================================================================
  logic [HPSI-1:0][R-1:0][MOD_Q_W-1:0] a0_ntt_acc_data;
  logic                                a0_ntt_acc_sob;
  logic                                a0_ntt_acc_eob;
  logic                                a0_ntt_acc_sol;
  logic                                a0_ntt_acc_eol;
  logic                                a0_ntt_acc_sog;
  logic                                a0_ntt_acc_eog;
  logic [BPBS_ID_W-1:0]                a0_ntt_acc_pbs_id;
  logic                                a0_ntt_acc_avail;

  logic                                infifo_acc_data_inc;
  logic                                infifo_acc_data_sample;

  logic                                infifo_error; // FIFO overflow error

  logic                                ntt_acc_new_ct;

  assign ntt_acc_new_ct = ntt_acc_avail & ntt_acc_sog;

  pep_mmacc_infifo
  #(
    .OP_W        (MOD_Q_W),
    .R           (R),
    .PSI         (HPSI),
    .RAM_LATENCY (RAM_LATENCY),
    .DEPTH       (FIFO_NTT_ACC_DEPTH),
    .BYPASS      (1'b0) // This FIFO is mandatory in PEP
  ) pep_mmacc_infifo (
    .clk                 (clk),
    .s_rst_n             (s_rst_n),

    .ntt_acc_data        (ntt_acc_data),

    .ntt_acc_sob         (ntt_acc_sob),
    .ntt_acc_eob         (ntt_acc_eob),
    .ntt_acc_sol         (ntt_acc_sol),
    .ntt_acc_eol         (ntt_acc_eol),
    .ntt_acc_sog         (ntt_acc_sog),
    .ntt_acc_eog         (ntt_acc_eog),
    .ntt_acc_pbs_id      (ntt_acc_pbs_id),
    .ntt_acc_avail       (ntt_acc_avail),

    .infifo_acc_data     (a0_ntt_acc_data),
    .infifo_acc_sob      (a0_ntt_acc_sob),
    .infifo_acc_eob      (a0_ntt_acc_eob),
    .infifo_acc_sol      (a0_ntt_acc_sol),
    .infifo_acc_eol      (a0_ntt_acc_eol),
    .infifo_acc_sog      (a0_ntt_acc_sog),
    .infifo_acc_eog      (a0_ntt_acc_eog),
    .infifo_acc_pbs_id   (a0_ntt_acc_pbs_id),
    .infifo_acc_avail    (a0_ntt_acc_avail),

    .infifo_acc_data_inc (infifo_acc_data_inc),
    .infifo_acc_data_sample(infifo_acc_data_sample),

    .error               (infifo_error)
  );

//=================================================================================================
// Input pipe
//=================================================================================================
  logic               am2_new_ct;
  logic               am1_new_ct; // Give time
  logic [GRAM_NB-1:0] garb_rd_avail_1h;
  logic               a0_ntt_data_inc;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      am2_new_ct       <= 1'b0;
      am1_new_ct       <= 1'b0;
      garb_rd_avail_1h <= '0;
      a0_ntt_data_inc  <= 1'b0;
    end
    else begin
      am2_new_ct       <= ntt_acc_new_ct;
      am1_new_ct       <= am2_new_ct;
      garb_rd_avail_1h <= garb_acc_rd_avail_1h;
      a0_ntt_data_inc  <= infifo_acc_data_inc;
    end

//=================================================================================================
// Am1
//=================================================================================================
// When ntt_acc data available. Request access to the GRAM.

  mmacc_intern_cmd_t afifo_acc_icmd_s;

  assign afifo_acc_icmd_s = afifo_acc_icmd; // cast

  //== Counter
  // Counts the number of available ct for which no arb request has been sent.
  logic [BPBS_NB_WW-1:0] am1_ct_pending_cnt;
  logic [BPBS_NB_WW-1:0] am1_ct_pending_cntD;
  logic                  am1_ct_avail;

  assign am1_ct_avail = am1_ct_pending_cnt > 0;

  //== Fork
  logic am1_vld;
  logic am1_rdy;

  logic am1_garb_vld;
  logic am1_garb_rdy;

  logic am1_a0_vld;
  logic am1_a0_rdy;

  assign am1_vld       = afifo_acc_vld & am1_ct_avail;
  assign am1_garb_vld  = am1_vld & am1_a0_rdy;
  assign am1_a0_vld    = am1_vld & am1_garb_rdy;
  assign am1_rdy       = am1_ct_avail & am1_a0_rdy & am1_garb_rdy;
  assign afifo_acc_rdy = am1_rdy;

  assign am1_ct_pending_cntD = am1_new_ct && !(am1_vld && am1_rdy) ? am1_ct_pending_cnt + 1 :
                               !am1_new_ct && (am1_vld && am1_rdy) ? am1_ct_pending_cnt - 1 : am1_ct_pending_cnt;

  always_ff @(posedge clk)
    if (!s_rst_n) am1_ct_pending_cnt <= '0;
    else          am1_ct_pending_cnt <= am1_ct_pending_cntD;

  //= GRAM arbiter
  garb_cmd_t am1_garb_req;

  assign am1_garb_req.grid     = afifo_acc_icmd_s.map_elt.pid.grid;
  assign am1_garb_req.critical = am1_ct_pending_cnt > INFIFO_CT_THRES;


  fifo_element #(
    .WIDTH          (GARB_CMD_W),
    .DEPTH          (2),
    .TYPE_ARRAY     (8'h12),
    .DO_RESET_DATA  (1'b0),
    .RESET_DATA_VAL (0)
  ) garb_fifo_element (
    .clk      (clk),
    .s_rst_n  (s_rst_n),

    .in_data  (am1_garb_req),
    .in_vld   (am1_garb_vld),
    .in_rdy   (am1_garb_rdy),

    .out_data (acc_garb_req),
    .out_vld  (acc_garb_req_vld),
    .out_rdy  (acc_garb_req_rdy)
  );

  //= To A0
  mmacc_intern_cmd_t a0_icmd;
  logic              a0_vld;
  logic              a0_rdy;

  logic [GLWE_RAM_ADD_W-1:0] am1_add_ofs;
  logic [GLWE_RAM_ADD_W-1:0] a0_add_ofs;

  assign am1_add_ofs = afifo_acc_icmd_s.map_elt.pid.grof * GLWE_RAM_DEPTH_PBS;

  fifo_element #(
    .WIDTH          (GLWE_RAM_ADD_W+MMACC_INTERN_CMD_W),
    .DEPTH          (2),
    .TYPE_ARRAY     (8'h12),
    .DO_RESET_DATA  (1'b0),
    .RESET_DATA_VAL (0)
  ) am1_fifo_element (
    .clk      (clk),
    .s_rst_n  (s_rst_n),

    .in_data  ({am1_add_ofs,afifo_acc_icmd_s}),
    .in_vld   (am1_a0_vld),
    .in_rdy   (am1_a0_rdy),

    .out_data ({a0_add_ofs,a0_icmd}),
    .out_vld  (a0_vld),
    .out_rdy  (a0_rdy)
  );

//=================================================================================================
// A0
//=================================================================================================
// The ntt_acc is available : do the corresponding read request in GRAM
  //== Counter
  // Count the number of elements in infifo
  // Do this way to ease P&R.
  logic [INFIFO_DEPTH_W-1:0] a0_ntt_data_cnt;
  logic [INFIFO_DEPTH_W-1:0] a0_ntt_data_cntD;
  logic                      a0_ntt_data_dec;
  logic                      a0_ntt_data_empty;

  assign a0_ntt_data_cntD = a0_ntt_data_inc && !a0_ntt_data_dec ? a0_ntt_data_cnt + 1:
                            !a0_ntt_data_inc && a0_ntt_data_dec ? a0_ntt_data_cnt - 1:
                            a0_ntt_data_cnt;
  always_ff @(posedge clk)
    if (!s_rst_n) a0_ntt_data_cnt <= '0;
    else          a0_ntt_data_cnt <= a0_ntt_data_cntD;

  assign a0_ntt_data_empty = a0_ntt_data_cnt == '0;

  //== Arbitration mask
  // To avoid using the arbitration of a previous request, use a mask.
  // This could accur when PBS_L > 1. The arbitration duration is set to the longest case
  // when the data arrive on the flight, i.e. one every PBS_L cycles.
  // The arbitration always starts with a posedge.
  logic [GRAM_NB-1:0] a0_garb_rd_avail_mask;
  logic [GRAM_NB-1:0] a0_garb_rd_avail_mask_keep;
  logic [GRAM_NB-1:0] a0_garb_rd_avail_mask_keepD;

  logic [GRAM_NB-1:0] garb_rd_avail_1h_dly;
  logic [GRAM_NB-1:0] garb_rd_avail_1h_posedge;

  assign garb_rd_avail_1h_posedge = ~garb_rd_avail_1h_dly & garb_rd_avail_1h;

  always_comb
    for (int g=0; g<GRAM_NB; g=g+1)
      a0_garb_rd_avail_mask_keepD[g] = a0_vld && a0_rdy            ? 1'b0:
                                       garb_rd_avail_1h_posedge[g] ? 1'b1 : a0_garb_rd_avail_mask_keep[g];

  assign a0_garb_rd_avail_mask = garb_rd_avail_1h_posedge | a0_garb_rd_avail_mask_keep;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      a0_garb_rd_avail_mask_keep <= '0;
      garb_rd_avail_1h_dly       <= '0;
    end
    else begin
      a0_garb_rd_avail_mask_keep <= a0_garb_rd_avail_mask_keepD;
      garb_rd_avail_1h_dly       <= garb_rd_avail_1h;
    end

  //== Counters
  logic [GLWE_K_P1_W-1:0]    a0_poly_id;
  logic [STG_ITER_W-1:0]     a0_stg_iter;

  logic [GLWE_K_P1_W-1:0]    a0_poly_idD;
  logic [STG_ITER_W-1:0]     a0_stg_iterD;

  logic                      a0_last_poly_id;
  logic                      a0_last_stg_iter;

  logic [GLWE_RAM_ADD_W-1:0] a0_rd_add;
  logic                      a0_do_read; // do the reading in GRAM
  logic [GRAM_ID_W-1:0]      a0_gram_id;

  assign a0_last_poly_id  = a0_poly_id == (GLWE_K_P1-1);
  assign a0_last_stg_iter = a0_stg_iter == (STG_ITER_NB-1);

  assign a0_poly_idD   = a0_do_read  ? a0_last_poly_id ? '0 : a0_poly_id + 1 : a0_poly_id;
  assign a0_stg_iterD  = (a0_do_read  && a0_last_poly_id) ? a0_last_stg_iter ? '0 : a0_stg_iter + 1 : a0_stg_iter;

  assign a0_rd_add     = {a0_poly_id,a0_stg_iter} + a0_add_ofs;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      a0_poly_id   <= '0;
      a0_stg_iter  <= '0;
    end
    else begin
      a0_poly_id   <= a0_poly_idD ;
      a0_stg_iter  <= a0_stg_iterD;
    end

  logic a0_garb_en;
  logic a0_mask_null;

  assign a0_gram_id          = a0_icmd.map_elt.pid.grid;
  assign a0_garb_en          = garb_rd_avail_1h[a0_gram_id] & a0_garb_rd_avail_mask[a0_gram_id];
  assign a0_do_read          = a0_vld & ~a0_ntt_data_empty & a0_garb_en;
  assign a0_rdy              = ~a0_ntt_data_empty & a0_garb_en & a0_last_poly_id & a0_last_stg_iter;
  assign a0_ntt_data_dec     = a0_vld & a0_garb_en & ~a0_ntt_data_empty;

  // Only the body part of the GLWE was loaded. Set the mask part to 0
  // when processing the first iteration of the CT.
  assign a0_mask_null = a0_icmd.map_elt.first & (a0_poly_id < GLWE_K);

  always_ff @(posedge clk)
    if (!s_rst_n) infifo_acc_data_sample <= 1'b0;
    else          infifo_acc_data_sample <= a0_ntt_data_dec;

// pragma translate_off
  always_ff @(posedge clk)
    if (|(garb_rd_avail_1h & ~garb_rd_avail_1h_dly)) begin // posedge
      assert(a0_vld && !a0_ntt_data_empty)
      else begin
        $fatal(1,"%t > ERROR: Arbitration enabled for acc reading, but no command or data valid!",$time);
      end

      assert(garb_rd_avail_1h[a0_gram_id])
      else begin
        $fatal(1,"%t > ERROR: Arbitration GRAM id is not the one needed by the command!",$time);
      end
    end
// pragma translate_on

//=================================================================================================
// AA1
//=================================================================================================
// Shift register : wait for the datar.
  mmacc_intern_cmd_t                                 aa1_icmd_sr [SR_DEPTH-1:0];
  logic [SR_DEPTH-1:0][GLWE_RAM_ADD_W-1:0]           aa1_add_sr;
  logic [SR_DEPTH-1:0]                               aa1_avail_sr;
  logic [SR_DEPTH-1:0]                               aa1_mask_null_sr;
  logic [SR_DATA_DEPTH-1:0][HPSI-1:0][R-1:0][MOD_Q_W-1:0] aa1_ntt_acc_data_sr;
  logic [SR_DATA_DEPTH-1:0]                               aa1_eog_sr;

  mmacc_intern_cmd_t                                 aa1_icmd_srD [SR_DEPTH-1:0];
  logic [SR_DEPTH-1:0][GLWE_RAM_ADD_W-1:0]           aa1_add_srD;
  logic [SR_DEPTH-1:0]                               aa1_avail_srD;
  logic [SR_DEPTH-1:0]                               aa1_mask_null_srD;
  logic [SR_DATA_DEPTH-1:0][HPSI-1:0][R-1:0][MOD_Q_W-1:0] aa1_ntt_acc_data_srD;
  logic [SR_DATA_DEPTH-1:0]                               aa1_eog_srD;

  assign aa1_icmd_srD[0]         = a0_icmd;
  assign aa1_add_srD[0]          = a0_rd_add;
  assign aa1_avail_srD[0]        = a0_do_read;
  assign aa1_mask_null_srD[0]    = a0_mask_null;
  assign aa1_ntt_acc_data_srD[0] = a0_ntt_acc_data;
  assign aa1_eog_srD[0]          = a0_ntt_acc_eog;
  generate
    if (SR_DEPTH>1) begin
      assign aa1_icmd_srD[SR_DEPTH-1:1]         = aa1_icmd_sr[SR_DEPTH-2:0];
      assign aa1_add_srD[SR_DEPTH-1:1]          = aa1_add_sr[SR_DEPTH-2:0];
      assign aa1_avail_srD[SR_DEPTH-1:1]        = aa1_avail_sr[SR_DEPTH-2:0];
      assign aa1_mask_null_srD[SR_DEPTH-1:1]    = aa1_mask_null_sr[SR_DEPTH-2:0];
      assign aa1_ntt_acc_data_srD[SR_DATA_DEPTH-1:1] = aa1_ntt_acc_data_sr[SR_DATA_DEPTH-2:0];
      assign aa1_eog_srD[SR_DATA_DEPTH-1:1]          = aa1_eog_sr[SR_DATA_DEPTH-2:0];
    end
  endgenerate

  always_ff @(posedge clk)
    if (!s_rst_n) aa1_avail_sr <= '0;
    else          aa1_avail_sr <= aa1_avail_srD;

  always_ff @(posedge clk) begin
    aa1_icmd_sr         <= aa1_icmd_srD;
    aa1_add_sr          <= aa1_add_srD;
    aa1_ntt_acc_data_sr <= aa1_ntt_acc_data_srD;
    aa1_eog_sr          <= aa1_eog_srD;
    aa1_mask_null_sr    <= aa1_mask_null_srD;
  end

//=================================================================================================
// S1
//=================================================================================================
// At this cycle datar are available.
  mmacc_intern_cmd_t                   s1_icmd;
  logic [GLWE_RAM_ADD_W-1:0]           s1_add;
  logic [HPSI-1:0][R-1:0][MOD_Q_W-1:0] s1_ntt_acc_data;
  logic                                s1_avail;
  logic                                s1_eog;

  assign s1_icmd         = aa1_icmd_sr[SR_DEPTH-1];
  assign s1_add          = aa1_add_sr[SR_DEPTH-1];
  assign s1_avail        = aa1_avail_sr[SR_DEPTH-1];
  assign s1_ntt_acc_data = aa1_ntt_acc_data_sr[SR_DATA_DEPTH-1];
  assign s1_eog          = aa1_eog_sr[SR_DATA_DEPTH-1];

  //== Send done to feed, and bsk
  logic                 s1_acc_feed_done;
  logic [BPBS_ID_W-1:0] s1_acc_feed_done_map_idx;
  logic                 s1_br_loop_proc_done;

  assign s1_acc_feed_done         = s1_avail & s1_eog & ~s1_icmd.map_elt.last;
  assign s1_acc_feed_done_map_idx = s1_icmd.map_idx;
  assign s1_br_loop_proc_done     = s1_avail & s1_eog & s1_icmd.batch_last_ct;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      acc_feed_done     <= 1'b0;
      br_loop_proc_done <= 1'b0;
    end
    else begin
      acc_feed_done     <= s1_acc_feed_done;
      br_loop_proc_done <= s1_br_loop_proc_done;
    end

  always_ff @(posedge clk)
    acc_feed_done_map_idx <= s1_acc_feed_done_map_idx;

  //== Send done to SXT
  // When the whole BR process of the ct is over.
  logic s1_sxt_avail;

  assign s1_sxt_avail = s1_avail & s1_eog & s1_icmd.map_elt.last;

  always_ff @(posedge clk)
    if (!s_rst_n) acc_sfifo_avail <= 1'b0;
    else          acc_sfifo_avail <= s1_sxt_avail;

  always_ff @(posedge clk)
    acc_sfifo_icmd <= s1_icmd;

//=================================================================================================
// Output
//=================================================================================================
  assign out_a0_do_read = a0_do_read;
  assign out_a0_rd_add  = a0_rd_add;
  assign out_a0_rd_grid = a0_gram_id;

  assign out_s0_mask_null = aa1_mask_null_sr[SR_DEPTH-2];

  assign out_s1_ntt_acc_data = s1_ntt_acc_data;
  assign out_s1_avail        = s1_avail       ;
  assign out_s1_add          = s1_add         ;
  assign out_s1_grid         = s1_icmd.map_elt.pid.grid;

//=================================================================================================
// error
//=================================================================================================
  logic errorD;

  assign errorD = infifo_error;

  always_ff @(posedge clk)
    if (!s_rst_n) error <= '0;
    else          error <= errorD;

endmodule
