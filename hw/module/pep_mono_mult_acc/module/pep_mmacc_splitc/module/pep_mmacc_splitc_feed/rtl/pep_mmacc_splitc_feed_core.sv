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

module pep_mmacc_splitc_feed_core
  import param_tfhe_pkg::*;
  import ntt_core_common_param_pkg::*;
  import top_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import pep_mmacc_common_param_pkg::*;
  import pep_mmacc_splitc_feed_pkg::*;
#(
  parameter  int DATA_LATENCY       = 5, // RAM_LATENCY + 3 : Latency for read data to come back
  parameter  int WAIT_FOR_ACK       = 0, // (0) : do not wait
                                         // (1) : wait for ack signal before starting processing
                                         // (2) : wait for ack_ack signal before starting processing
  parameter  int MSPLIT_FACTOR      = 2, // Indicates how many pieces are present here.
  parameter  int HPSI_SET_ID        = 0,  // Indicates which of the two coef sets is processed here
  localparam int HPSI               = MSPLIT_FACTOR * PSI / MSPLIT_DIV,
  localparam int CORE_FACTOR        = (HPSI_SET_ID == 0) ? ((MSPLIT_FACTOR + 1) / 2) * 2: (MSPLIT_FACTOR / 2) * 2,
  localparam int CORE_PSI           = PSI * CORE_FACTOR / MSPLIT_DIV

)
(
  input  logic                                                               clk,        // clock
  input  logic                                                               s_rst_n,    // synchronous reset

  input  logic [MMACC_FEED_CMD_W-1:0]                                        in_mcmd,
  input  logic                                                               in_mcmd_vld,
  output logic                                                               in_mcmd_rdy,
  input  logic                                                               mcmd_ack,
  input  logic                                                               mcmd_ack_ack,
  output logic                                                               mcmd_loopback,
  output logic                                                               mcmd_loopback_ack,

  // GRAM arbiter
  output logic [GARB_CMD_W-1:0]                                              feed_garb_req,
  output logic                                                               feed_garb_req_vld,
  input  logic                                                               feed_garb_req_rdy,

  input  logic [GRAM_NB-1:0]                                                 garb_feed_rot_avail_1h,
  input  logic [GRAM_NB-1:0]                                                 garb_feed_dat_avail_1h,

  // To afifo
  output logic [MMACC_INTERN_CMD_W-1:0]                                      feed_afifo_icmd,
  output logic                                                               feed_afifo_vld,
  input  logic                                                               feed_afifo_rdy,

  // From acc
  input  logic                                                               acc_feed_done,
  input  logic [BPBS_ID_W-1:0]                                               acc_feed_done_map_idx,

  // GRAM
  output logic [GRAM_NB-1:0][HPSI-1:0][R-1:0][1:0]                           feed_gram_rd_en,
  output logic [GRAM_NB-1:0][HPSI-1:0][R-1:0][1:0][GLWE_RAM_ADD_W-1:0]       feed_gram_rd_add,
  input  logic [GRAM_NB-1:0][HPSI-1:0][R-1:0][1:0][MOD_Q_W-1:0]              gram_feed_rd_data,
  input  logic [GRAM_NB-1:0][HPSI-1:0][R-1:0][1:0]                           gram_feed_rd_data_avail,

  // Output data
  output logic [CORE_PSI-1:0][R-1:0][MOD_Q_W-1:0]                            out_data,
  output logic [CORE_PSI-1:0][R-1:0][MOD_Q_W-1:0]                            out_rot_data,
  output logic [PERM_W-1:0]                                                  out_perm_select, // last 2 levels of permutation
  output logic [LWE_COEF_W:0]                                                out_coef_rot_id0,
  output logic [REQ_CMD_W-1:0]                                               out_rcmd,
  output logic                                                               out_data_avail,

  output logic [PSI/MSPLIT_DIV-1:0][R-1:0][MOD_Q_W-1:0]                      out_part,
  output logic [PSI/MSPLIT_DIV-1:0][R-1:0][MOD_Q_W-1:0]                      out_rot_part,
  output logic                                                               out_part_avail,

  // Input data for the join. Used when MSPLIT_FACTOR is odd and HPSI_SET_ID == 0
  input  logic [PSI/MSPLIT_DIV-1:0][R-1:0][MOD_Q_W-1:0]                      in_data,
  input  logic [PSI/MSPLIT_DIV-1:0][R-1:0][MOD_Q_W-1:0]                      in_rot_data,
  input  logic                                                               in_data_avail,

  // Control
  output logic                                                               br_loop_flush_done,

  output logic [BR_BATCH_CMD_W-1:0]                                          batch_cmd,
  output logic                                                               batch_cmd_avail

);

//=================================================================================================
// Localparam
//=================================================================================================
  localparam bit WAIT_FOR_ACK_L  = WAIT_FOR_ACK > 0 ? 1'b1 : 1'b0;
  localparam int QPSI_SET_ID_OFS = HPSI_SET_ID*(MSPLIT_DIV-MSPLIT_FACTOR);
  localparam int QPSI_SET_ID_END = QPSI_SET_ID_OFS + MSPLIT_FACTOR-1;
  localparam int JOIN_NB         = ((MSPLIT_FACTOR + 1) / 2) * 2;
  localparam bit JOIN_IS_BALANCED= (JOIN_NB == MSPLIT_FACTOR);
  localparam int QPSI            = PSI / MSPLIT_DIV;
  localparam int JOIN_QPSI_SET_ID_OFS = QPSI_SET_ID_OFS - (QPSI_SET_ID_OFS%2);

  // If the number of coef part is not even, in HPSI_SET_ID=0, the part is completed with the "join". Therefore
  // there are more data at the output.
  localparam bit OUTPUT_PART     = (HPSI_SET_ID == 1) && (MSPLIT_FACTOR%(MSPLIT_DIV/2) != 0);
  localparam bit OUTPUT_DATA     = (HPSI_SET_ID == 0) || (MSPLIT_FACTOR >= MSPLIT_DIV/2);

  generate
    if (MSPLIT_DIV != 4) begin : __UNSUPPORTED_MSPLIT_DIV
      $fatal(1,"> ERROR: Unsupported MSPLIT_DIV (%0d) value. Should be equal to 4.",MSPLIT_DIV);
    end
    if (MSPLIT_FACTOR < 1 || MSPLIT_FACTOR > 3) begin : __UNSUPPORTED_MSPLIT_FACTOR
      $fatal(1,"> ERROR: Unsupported MSPLIT_FACTOR (%0d) value. With MSPLIT_DIV equals 4, we support only 1,2 and 3 for the factor.",MSPLIT_DIV);
    end
  endgenerate

//=================================================================================================
// Signals
//=================================================================================================
  logic                      f1_rd_en;
  logic [GLWE_RAM_ADD_W-1:0] f1_rd_add;
  logic [GRAM_ID_W-1:0]      f1_rd_grid;

  logic                      ff3_rd_en;
  logic [GLWE_RAM_ADD_W-1:0] ff3_rd_add;
  logic [GRAM_ID_W-1:0]      ff3_rd_grid;

  logic                      s0_avail;
  logic [REQ_CMD_W-1:0]      s0_rcmd;

  logic                      ss1_avail;
  logic [REQ_CMD_W-1:0]      ss1_rcmd;


  logic [MSPLIT_FACTOR-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0][1:0]                     feed_gram_rd_en_l;
  logic [MSPLIT_FACTOR-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0][1:0][GLWE_RAM_ADD_W-1:0] feed_gram_rd_add_l;
  logic [MSPLIT_FACTOR-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0][1:0][MOD_Q_W-1:0]        gram_feed_rd_data_l;
  logic [MSPLIT_FACTOR-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0][1:0]                     gram_feed_rd_data_avail_l;

  logic [MSPLIT_FACTOR-1:0][QPSI-1:0][R-1:0][MOD_Q_W-1:0]                          q_data;
  logic [MSPLIT_FACTOR-1:0][QPSI-1:0][R-1:0][MOD_Q_W-1:0]                          q_rot_data;
  logic [MSPLIT_FACTOR-1:0][1:0][PERM_W-1:0]                                       q_perm_select; // last 2 levels of permutation
  logic [MSPLIT_FACTOR-1:0][LWE_COEF_W:0]                                          q_coef_rot_id0;
  logic [MSPLIT_FACTOR-1:0][REQ_CMD_W-1:0]                                         q_rcmd;
  logic [MSPLIT_FACTOR-1:0]                                                        q_data_avail;

//=================================================================================================
// Loopback
//=================================================================================================
  assign mcmd_loopback     = in_mcmd_vld & in_mcmd_rdy;
  assign mcmd_loopback_ack = mcmd_ack;

//=================================================================================================
// feed read
//=================================================================================================
  logic mcmd_ack_trigger;
  assign mcmd_ack_trigger = WAIT_FOR_ACK > 1 ? mcmd_ack_ack : mcmd_ack;

  pep_mmacc_splitc_feed_read
  #(
    .DATA_LATENCY (DATA_LATENCY),
    .WAIT_FOR_ACK (WAIT_FOR_ACK_L)
  ) pep_mmacc_splitc_feed_read (
    .clk                    (clk),
    .s_rst_n                (s_rst_n),
    .in_mcmd                (in_mcmd),
    .in_mcmd_vld            (in_mcmd_vld),
    .in_mcmd_rdy            (in_mcmd_rdy),
    .mcmd_ack               (mcmd_ack_trigger),

    .feed_garb_req          (feed_garb_req),
    .feed_garb_req_vld      (feed_garb_req_vld),
    .feed_garb_req_rdy      (feed_garb_req_rdy),

    .garb_feed_rot_avail_1h (garb_feed_rot_avail_1h),
    .garb_feed_dat_avail_1h (garb_feed_dat_avail_1h),

    .feed_afifo_icmd        (feed_afifo_icmd),
    .feed_afifo_vld         (feed_afifo_vld),
    .feed_afifo_rdy         (feed_afifo_rdy),

    .acc_feed_done          (acc_feed_done),
    .acc_feed_done_map_idx  (acc_feed_done_map_idx),

    .out_f1_rd_en           (f1_rd_en),
    .out_f1_rd_add          (f1_rd_add),
    .out_f1_rd_grid         (f1_rd_grid),

    .out_ff3_rd_en          (ff3_rd_en),
    .out_ff3_rd_add         (ff3_rd_add),
    .out_ff3_rd_grid        (ff3_rd_grid),

    .out_s0_avail           (s0_avail),
    .out_s0_rcmd            (s0_rcmd),

    .out_ss1_avail          (ss1_avail),
    .out_ss1_rcmd           (ss1_rcmd),

    .br_loop_flush_done     (br_loop_flush_done),

    .batch_cmd              (batch_cmd),
    .batch_cmd_avail        (batch_cmd_avail)
  );

//=================================================================================================
// feed rot
//=================================================================================================
// feed_rot goes by pair. If 2 feed_rot are present, their data are rotated one more time in
// "join" module.
// The second feed_rot of a pair starts working with 1 cycle delay : to ease the P&R.

  generate
    for (genvar gen_i=0; gen_i<MSPLIT_FACTOR; gen_i=gen_i+1) begin : gen_qpsi_loop
      logic [QPSI-1:0][R-1:0] q_data_avail_l;
      assign q_data_avail[gen_i] = q_data_avail_l[0][0];

      pep_mmacc_splitc_feed_rot
      #(
        .INPUT_DLY   ((QPSI_SET_ID_OFS + gen_i) % 2),
        .QPSI_SET_ID (QPSI_SET_ID_OFS + gen_i)
      ) qpsi__pep_mmacc_splitc_feed_rot (
        .clk                     (clk),
        .s_rst_n                 (s_rst_n),

        .in_f1_rd_en             (f1_rd_en),
        .in_f1_rd_add            (f1_rd_add),
        .in_f1_rd_grid           (f1_rd_grid),

        .in_ff3_rd_en            (ff3_rd_en),
        .in_ff3_rd_add           (ff3_rd_add),
        .in_ff3_rd_grid          (ff3_rd_grid),

        .in_s0_avail             (s0_avail),
        .in_s0_rcmd              (s0_rcmd),

        .in_ss1_avail            (ss1_avail),
        .in_ss1_rcmd             (ss1_rcmd),

        .feed_gram_rd_en         (feed_gram_rd_en_l[gen_i]),
        .feed_gram_rd_add        (feed_gram_rd_add_l[gen_i]),
        .gram_feed_rd_data       (gram_feed_rd_data_l[gen_i]),
        .gram_feed_rd_data_avail (gram_feed_rd_data_avail_l[gen_i]),

        .out_data                (q_data[gen_i]),
        .out_rot_data            (q_rot_data[gen_i]),
        .out_perm_select         (q_perm_select[gen_i]),
        .out_coef_rot_id0        (q_coef_rot_id0[gen_i]),
        .out_rcmd                (q_rcmd[gen_i]),
        .out_data_avail          (q_data_avail_l)
      );
    end // gen_qpsi_loop
  endgenerate

//=================================================================================================
// feed join
//=================================================================================================
  logic [JOIN_NB-1:0][QPSI-1:0][R-1:0][MOD_Q_W-1:0]     jin_data;
  logic [JOIN_NB-1:0][QPSI-1:0][R-1:0][MOD_Q_W-1:0]     jin_rot_data;
  logic [JOIN_NB-1:0][1:0][PERM_W-1:0]                  jin_perm_select;
  logic [JOIN_NB-1:0][LWE_COEF_W:0]                     jin_coef_rot_id0;
  logic [JOIN_NB-1:0][REQ_CMD_W-1:0]                    jin_rcmd;
  logic [JOIN_NB-1:0]                                   jin_data_avail;

  logic [JOIN_NB/2-1:0][2*QPSI-1:0][R-1:0][MOD_Q_W-1:0] jout_data;
  logic [JOIN_NB/2-1:0][2*QPSI-1:0][R-1:0][MOD_Q_W-1:0] jout_rot_data;
  logic [JOIN_NB/2-1:0][PERM_W-1:0]                     jout_perm_select;
  logic [JOIN_NB/2-1:0][LWE_COEF_W:0]                   jout_coef_rot_id0;
  logic [JOIN_NB/2-1:0][REQ_CMD_W-1:0]                  jout_rcmd;
  logic [JOIN_NB/2-1:0]                                 jout_data_avail;

  // Associate some control to the input.
  // Choose the one that will be its pair in the join process
  logic [1:0][PERM_W-1:0]                               in_perm_select;
  logic [LWE_COEF_W:0]                                  in_coef_rot_id0;
  logic [REQ_CMD_W-1:0]                                 in_rcmd;

  assign in_perm_select  = (QPSI_SET_ID_OFS%2)==0 ? q_perm_select[MSPLIT_FACTOR-1]  : q_perm_select[0];
  assign in_coef_rot_id0 = (QPSI_SET_ID_OFS%2)==0 ? q_coef_rot_id0[MSPLIT_FACTOR-1] : q_coef_rot_id0[0];
  assign in_rcmd         = (QPSI_SET_ID_OFS%2)==0 ? q_rcmd[MSPLIT_FACTOR-1]         : q_rcmd[0];

  generate
    if (!JOIN_IS_BALANCED) begin : gen_unbalanced_join
      assign jin_data         = (QPSI_SET_ID_OFS%2)==0 ? {in_data,q_data}                 : {q_data, in_data};
      assign jin_rot_data     = (QPSI_SET_ID_OFS%2)==0 ? {in_rot_data,q_rot_data}         : {q_rot_data, in_rot_data};
      assign jin_data_avail   = (QPSI_SET_ID_OFS%2)==0 ? {in_data_avail,q_data_avail}     : {q_data_avail, in_data_avail};
      assign jin_perm_select  = (QPSI_SET_ID_OFS%2)==0 ? {in_perm_select,q_perm_select}   : {q_perm_select,in_perm_select};
      assign jin_coef_rot_id0 = (QPSI_SET_ID_OFS%2)==0 ? {in_coef_rot_id0,q_coef_rot_id0} : {q_coef_rot_id0,in_coef_rot_id0};
      assign jin_rcmd         = (QPSI_SET_ID_OFS%2)==0 ? {in_rcmd,q_rcmd}                 : {q_rcmd,in_rcmd};
    end
    else begin : gen_balanced_join
      assign jin_data         = q_data;
      assign jin_rot_data     = q_rot_data;
      assign jin_data_avail   = q_data_avail;
      assign jin_perm_select  = q_perm_select;
      assign jin_coef_rot_id0 = q_coef_rot_id0;
      assign jin_rcmd         = q_rcmd;
    end

    // With MSPLIT_DIV=4, we have 4 parts. They can be gathered into 3 ways :
    // 1. main 2 (#2, #3)     : subs 2 (#0, #1)
    // 2. main 1 (#3)         : subs 3 (#0, #1, #2)
    // 3. main 3 (#1, #2, #3) : subs 1 (#0)
    // All the coef are, at the end, sent to "subs" which will deal with the final step of the rotation.
    // Therefore "main" does all the rotations it can, including the "join" with the coef that are available.
    // In case 1 and 3, main is able to do the "join" of #2 and #3.
    // In case 2 and 3, the number of coefficients is not balanced, so there are some
    // coef that cannot be "joined" here. They will be in the "subs" part. These coef are
    // #3 and #1 respectively.
    // In "subs" coef are always balanced for the join.
    // Note: "main" <=> HPSI_SET_ID=1
    // Note: "subs" <=> HPSI_SET_ID=0
    for (genvar gen_i=0; gen_i<JOIN_NB/2; gen_i=gen_i+1) begin : gen_join_loop
      if (JOIN_IS_BALANCED
          || (JOIN_QPSI_SET_ID_OFS+2*gen_i) >= QPSI_SET_ID_OFS) begin : gen_join // There is a pair available for the join.
        pep_mmacc_splitc_feed_join
        #(
          .HPSI_SET_ID (JOIN_QPSI_SET_ID_OFS/2+gen_i),
          .CMD_ID      (JOIN_QPSI_SET_ID_OFS+2*gen_i+1 <= QPSI_SET_ID_END ? 1 : 0) // The ctrl comes from the "copy" in_* => delay
        ) qpsi__pep_mmacc_splitc_feed_join ( // Use this particular prefix for scripts
          .clk              (clk),
          .s_rst_n          (s_rst_n),

          .in0_data         (jin_data[2*gen_i]),
          .in0_rot_data     (jin_rot_data[2*gen_i]),
          .in0_data_avail   (jin_data_avail[2*gen_i]),

          .in1_data         (jin_data[2*gen_i+1]),
          .in1_rot_data     (jin_rot_data[2*gen_i+1]),
          .in1_data_avail   (jin_data_avail[2*gen_i+1]),

          .in_coef_rot_id0  (jin_coef_rot_id0[2*gen_i+1]),
          .in_rcmd          (jin_rcmd[2*gen_i+1]),
          .in_perm_select   (jin_perm_select[2*gen_i+1]),

          .out_data         (jout_data[gen_i]),
          .out_rot_data     (jout_rot_data[gen_i]),
          .out_perm_select  (jout_perm_select[gen_i]),
          .out_coef_rot_id0 (jout_coef_rot_id0[gen_i]),
          .out_rcmd         (jout_rcmd[gen_i]),
          .out_data_avail   (jout_data_avail[gen_i])
        );

      end
      else begin : gen_no_join // No pair available
        assign jout_data[gen_i]       = {2{jin_data[2*gen_i+1]}};
        assign jout_rot_data[gen_i]   = {2{jin_rot_data[2*gen_i+1]}};
        assign jout_data_avail[gen_i] = jin_data_avail[2*gen_i+1];
        if (gen_i!=0) begin: __ERROR_SPLIT_SPREAD
          $fatal(1,"> ERROR: Wrong data repartition in the join modules.");
        end
      end
    end // gen_join_loop
  endgenerate

  logic [JOIN_NB*QPSI-1:0][R-1:0][MOD_Q_W-1:0] jout_data_tmp;
  logic [JOIN_NB*QPSI-1:0][R-1:0][MOD_Q_W-1:0] jout_rot_data_tmp;
  logic [JOIN_NB/2-1:0]                        jout_data_avail_tmp;

  // Only used when the associated join exists
  assign out_perm_select  = jout_perm_select[0];
  assign out_coef_rot_id0 = jout_coef_rot_id0[0];
  assign out_rcmd         = jout_rcmd[0];

  assign jout_data_tmp       = jout_data;
  assign jout_rot_data_tmp   = jout_rot_data;
  assign jout_data_avail_tmp = jout_data_avail;

  generate
    if (OUTPUT_PART) begin : gen_part
      assign out_part       = jout_data_tmp[0+:QPSI];
      assign out_rot_part   = jout_rot_data_tmp[0+:QPSI];
      assign out_part_avail = jout_data_avail_tmp[0];
    end
    else begin : gen_no_part
      assign out_part       = 'x;
      assign out_rot_part   = 'x;
      assign out_part_avail = 1'b0;
    end
    if (OUTPUT_DATA) begin : gen_data
      assign out_data       = jout_data_tmp[JOIN_NB*QPSI-1-:CORE_PSI];
      assign out_rot_data   = jout_rot_data_tmp[JOIN_NB*QPSI-1-:CORE_PSI];
      assign out_data_avail = jout_data_avail_tmp[JOIN_NB/2-1-:CORE_FACTOR/2];
    end
    else begin : gen_no_data
      assign out_data       = 'x;
      assign out_rot_data   = 'x;
      assign out_data_avail = 1'b0;
    end

  endgenerate
//=================================================================================================
// To/from GRAM
//=================================================================================================
  always_comb
    for (int g=0; g<GRAM_NB; g=g+1) begin
      for (int i=0; i<MSPLIT_FACTOR; i=i+1) begin
        feed_gram_rd_en[g][i*QPSI+:QPSI]  = feed_gram_rd_en_l[i][g];
        feed_gram_rd_add[g][i*QPSI+:QPSI] = feed_gram_rd_add_l[i][g];
        gram_feed_rd_data_l[i][g]         = gram_feed_rd_data[g][i*QPSI+:QPSI];
        gram_feed_rd_data_avail_l[i][g]   = gram_feed_rd_data_avail[g][i*QPSI+:QPSI];
      end
    end

endmodule
