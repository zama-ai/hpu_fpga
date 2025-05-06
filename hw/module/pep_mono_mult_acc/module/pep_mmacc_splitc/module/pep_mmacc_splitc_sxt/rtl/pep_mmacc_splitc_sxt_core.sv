// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the sample extraction, and the rotation with b.
// It reads the coefficients from GRAM, and orders them according to b and, does the negation
// when necessary.
// Data in GRAM are assumed to be in reverse order.
//
// This module outputs REGF_COEF_NB coefficients at a time.
// If the number of coefficients of a BLWE is not a multiple of BLWE_COEF_NB, the last word
// is completed with garbage.
// ==============================================================================================

`include "pep_mmacc_splitc_sxt_macro_inc.sv"

module pep_mmacc_splitc_sxt_core
  import param_tfhe_pkg::*;
  import top_common_param_pkg::*;
  import ntt_core_common_param_pkg::*;
  import regf_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import pep_mmacc_common_param_pkg::*;
  import pep_mmacc_splitc_sxt_pkg::*;
#(
  parameter  int DATA_LATENCY       = 5, // RAM_LATENCY + 3 : Latency for read data to come back
  parameter  bit WAIT_FOR_ACK       = 1'b1, // Wait for the subs cmd ack signal before starting to process
  parameter  int MSPLIT_FACTOR      = 2,
  parameter  int HPSI_SET_ID        = 0,    // Indicates which sets is processed here
  parameter  bit JOIN_LIMIT         = 1'b0, // Indicates if on join path a format is used. In which case, this path
                                            // is the most constrained.
  localparam int HPSI               = MSPLIT_FACTOR * PSI / MSPLIT_DIV,
  // If the number of coef part is not even, in HPSI_SET_ID=1, the part is completed with the "join". Therefore
  // there are more data at the output.
  localparam int O_FACTOR           = ((HPSI_SET_ID == 1) && (MSPLIT_FACTOR%2 != 0)) ? MSPLIT_FACTOR + 1 : MSPLIT_FACTOR,
  localparam int OPSI               = O_FACTOR * PSI / MSPLIT_DIV,
  localparam int OCTRL_NB           = (HPSI_SET_ID == 1) ? O_FACTOR / 2 : (O_FACTOR+1) / 2

)
(
  input  logic                                                      clk,        // clock
  input  logic                                                      s_rst_n,    // synchronous reset

  // Input cmd
  input  logic                                                      in_cmd_vld,
  output logic                                                      in_cmd_rdy,
  input  logic [LWE_COEF_W-1:0]                                     in_cmd_body,
  input  logic [MMACC_INTERN_CMD_W-1:0]                             in_cmd_icmd,

  input  logic                                                      icmd_ack, // Used if WAIT_FOR_ACK > 0
  output logic                                                      icmd_loopback,

  // From GRAM arbiter
  input  logic [GRAM_NB-1:0]                                        garb_sxt_avail_1h,

  // GRAM
  output logic [GRAM_NB-1:0][HPSI-1:0][R-1:0]                       sxt_gram_rd_en,
  output logic [GRAM_NB-1:0][HPSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0]   sxt_gram_rd_add,
  input  logic [GRAM_NB-1:0][HPSI-1:0][R-1:0][MOD_Q_W-1:0]          gram_sxt_rd_data,
  input  logic [GRAM_NB-1:0][HPSI-1:0][R-1:0]                       gram_sxt_rd_data_avail,

  // Output data
  output logic [OPSI-1:0][R-1:0][MOD_Q_W-1:0]                       out_rot_data,
  output logic [OCTRL_NB-1:0]                                       out_vld, // For each QPSI pair contained in OPSI
  input  logic [OCTRL_NB-1:0]                                       out_rdy,
  // The command is synchronized with OPSI-1
  output logic [PERM_W-1:0]                                         out_perm_select, // last 2 levels of permutation.
  output logic [CMD_X_W-1:0]                                        out_cmd,

  // Input data for the join. Used when MSPLIT_FACTOR is odd and HPSI_SET_ID == 1
  // To be joined with the first QPSI of the set.
  input  logic [PSI/MSPLIT_DIV-1:0][R-1:0][MOD_Q_W-1:0]             in_rot_data,
  input  logic                                                      in_vld,
  output logic                                                      in_rdy,

  // For register if
  output logic                                                      sxt_rif_req_dur

);

//=================================================================================================
// localparam
//=================================================================================================
  localparam int QPSI_SET_ID_OFS = HPSI_SET_ID*(MSPLIT_DIV-MSPLIT_FACTOR);
  localparam int QPSI_SET_ID_END = QPSI_SET_ID_OFS + MSPLIT_FACTOR-1;
  localparam int JOIN_NB         = ((MSPLIT_FACTOR + 1) / 2) * 2;
  localparam bit JOIN_IS_BALANCED= (JOIN_NB == MSPLIT_FACTOR);
  localparam int QPSI            = PSI / MSPLIT_DIV;
  localparam int JOIN_QPSI_SET_ID_OFS = QPSI_SET_ID_OFS - (QPSI_SET_ID_OFS%2);

  `PEP_MMACC_SPLITC_SXT_LOCALPARAM(R,PSI,DATA_LATENCY,REGF_COEF_NB,REGF_COEF_PER_URAM_WORD,REGF_BLWE_WORD_PER_RAM,DATA_THRESHOLD)

  generate
    if (MSPLIT_DIV != 4) begin : __UNSUPPORTED_MSPLIT_DIV
      $fatal(1,"> ERROR: Unsupported MSPLIT_DIV (%0d) value. Should be equal to 4.",MSPLIT_DIV);
    end
    if (MSPLIT_FACTOR < 1 || MSPLIT_FACTOR > 3) begin : __UNSUPPORTED_MSPLIT_FACTOR
      $fatal(1,"> ERROR: Unsupported MSPLIT_FACTOR (%0d) value. With MSPLIT_DIV equals 4, we support only 1,2 and 3 for the factor.",MSPLIT_DIV);
    end
  endgenerate

//=================================================================================================
// Loopback
//=================================================================================================
  assign icmd_loopback = in_cmd_vld & in_cmd_rdy;

// ================================================================================================
// Signals
// ================================================================================================
  logic                                                          buf_cnt_do_dec;

  logic                                                          s1_rd_en;
  logic [GLWE_RAM_ADD_W-1:0]                                     s1_rd_add;
  logic [GRAM_ID_W-1:0]                                          s1_rd_grid;

  logic                                                          x0_avail;
  logic [CMD_SS2_W-1:0]                                          x0_cmd;

  logic [MSPLIT_FACTOR-1:0][QPSI-1:0][R-1:0][MOD_Q_W-1:0]        q_rot_data;
  logic [MSPLIT_FACTOR-1:0][1:0][PERM_W-1:0]                     q_perm_select; // last 2 levels of permutation
  logic [MSPLIT_FACTOR-1:0][CMD_X_W-1:0]                         q_cmd;
  logic [MSPLIT_FACTOR-1:0]                                      q_avail;

  logic [MSPLIT_FACTOR-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0]                      sxt_gram_rd_en_l;
  logic [MSPLIT_FACTOR-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0]  sxt_gram_rd_add_l;
  logic [MSPLIT_FACTOR-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0][MOD_Q_W-1:0]         gram_sxt_rd_data_l;
  logic [MSPLIT_FACTOR-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0]                      gram_sxt_rd_data_avail_l;

//=================================================================================================
// sxt read
//=================================================================================================
  pep_mmacc_splitc_sxt_read
  #(
    .DATA_LATENCY       (DATA_LATENCY),
    .WAIT_FOR_ACK       (WAIT_FOR_ACK)
  ) pep_mmacc_splitc_sxt_read (
     .clk               (clk),
     .s_rst_n           (s_rst_n),

     .in_cmd_vld        (in_cmd_vld),
     .in_cmd_rdy        (in_cmd_rdy),
     .in_cmd_body       (in_cmd_body),
     .in_cmd_icmd       (in_cmd_icmd),

     .icmd_ack          (icmd_ack),

     .garb_sxt_avail_1h (garb_sxt_avail_1h),

    .out_s1_rd_en       (s1_rd_en),
    .out_s1_rd_add      (s1_rd_add),
    .out_s1_rd_grid     (s1_rd_grid),

    .out_x0_avail       (x0_avail),
    .out_x0_cmd         (x0_cmd),

    .buf_cnt_do_dec     (buf_cnt_do_dec),

    .sxt_rif_req_dur    (sxt_rif_req_dur)
  );

//=================================================================================================
// sxt rot
//=================================================================================================
// sxt_rot goes by pair. If 2 sxt_rot are present, their data are rotated one more time in
// "join" module.
// The second sxt_rot of a pair starts working with 1 cycle delay : to ease the P&R.

  generate
    for (genvar gen_i=0; gen_i<MSPLIT_FACTOR; gen_i=gen_i+1) begin : gen_qpsi_loop
      pep_mmacc_splitc_sxt_rot
      #(
        .INPUT_DLY     ((QPSI_SET_ID_OFS + gen_i) % 2),
        .QPSI_SET_ID   (QPSI_SET_ID_OFS + gen_i),
        .DATA_LATENCY  (DATA_LATENCY)
      ) qpsi__pep_mmacc_splitc_sxt_rot (
        .clk                    (clk),
        .s_rst_n                (s_rst_n),

        .in_s1_rd_en            (s1_rd_en),
        .in_s1_rd_add           (s1_rd_add),
        .in_s1_rd_grid          (s1_rd_grid),

        .in_x0_avail            (x0_avail),
        .in_x0_cmd              (x0_cmd),

        .sxt_gram_rd_en         (sxt_gram_rd_en_l[gen_i]),
        .sxt_gram_rd_add        (sxt_gram_rd_add_l[gen_i]),
        .gram_sxt_rd_data       (gram_sxt_rd_data_l[gen_i]),
        .gram_sxt_rd_data_avail (gram_sxt_rd_data_avail_l[gen_i]),


        .out_rot_data           (q_rot_data[gen_i]),
        .out_perm_select        (q_perm_select[gen_i]),
        .out_cmd                (q_cmd[gen_i]),
        .out_avail              (q_avail[gen_i])
      );
    end // gen_qpsi_loop
  endgenerate

//=================================================================================================
// sxt join
//=================================================================================================
  // With MSPLIT_DIV=4, we have 4 parts. There are 3 ways to gather them :
  // 1. main 2 (#2, #3)     : subs 2 (#0, #1)
  // 2. main 1 (#3)         : subs 3 (#0, #1, #2)
  // 3. main 3 (#1, #2, #3) : subs 1 (#0)
  // All the coef are, at the end, sent to "main" which will deal with the final step of the rotation.
  // Therefore "subs" does all the rotations it can, including the "join" with the coef that are available.
  // In case 1 and 2, subs is able to do the "join" of #0 and #1.
  // In case 2 and 3, the number of coefficients is not balanced, so there are some
  // coef that cannot be "joined" here. They will be in the "main" part. These coef are
  // #2 and #0 respectively.
  // In "main" coef are always balanced for the join.
  // Note: "main" <=> HPSI_SET_ID=1
  // Note: "subs" <=> HPSI_SET_ID=0

  // Put a FIFO after the rot, when the associated QPSI pair is not present in this module.
  logic [MSPLIT_FACTOR-1:0][QPSI-1:0][R-1:0][MOD_Q_W-1:0] j0_rot_data;
  logic [MSPLIT_FACTOR-1:0]                               j0_vld;
  logic [MSPLIT_FACTOR-1:0]                               j0_rdy;
  logic [MSPLIT_FACTOR-1:0][1:0][PERM_W-1:0]              j0_perm_select; // last 2 levels of permutation
  logic [MSPLIT_FACTOR-1:0][CMD_X_W-1:0]                  j0_cmd;

  logic [MSPLIT_FACTOR-1:0]                               q_vld;
  logic [MSPLIT_FACTOR-1:0]                               q_rdy;

  assign q_vld = q_avail;

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      for (int i=0; i<MSPLIT_FACTOR; i=i+1) begin
        assert(!q_vld[i] || q_rdy[i])
        else begin
          $fatal(1,"%t > ERROR: SXT rot [%0d] output overflows!",$time,i);
        end
      end
    end
// pragma translate_on

  generate
    for (genvar gen_i=0; gen_i<MSPLIT_FACTOR; gen_i=gen_i+1) begin : gen_unbalanced_fifo_loop
      localparam int QPSI_SET_ID_OFS_L = ((QPSI_SET_ID_OFS + gen_i) / 2) * 2;
      if ((QPSI_SET_ID_OFS_L >= QPSI_SET_ID_OFS) && (QPSI_SET_ID_OFS_L + 1 <= QPSI_SET_ID_END)) begin : gen_no_fifo
        // Both QPSI are present in the set.
        // FIFO is not needed.
        assign j0_rot_data[gen_i]    = q_rot_data[gen_i];
        assign j0_perm_select[gen_i] = q_perm_select[gen_i];
        assign j0_cmd[gen_i]         = q_cmd[gen_i];
        assign j0_vld[gen_i]         = q_vld[gen_i];
        assign q_rdy[gen_i]          = j0_rdy[gen_i];
      end
      else begin : gen_fifo
        // Only 1 QPSI is present.
        // FIFO is needed.
        fifo_reg #(
          .WIDTH       (CMD_X_W+2*PERM_W+QPSI*R*MOD_Q_W),
          .DEPTH       (JOIN_FIFO_DEPTH), // TOREVIEW : same FIFO depth as in join
                                              // + 1 pipe equivalent to join internal pipe
                                              // 2 pipes in the format
          .LAT_PIPE_MH ({1'b1, 1'b1})
        ) join_fifo (
          .clk     (clk),
          .s_rst_n (s_rst_n),

          .in_data ({q_cmd[gen_i],q_perm_select[gen_i],q_rot_data[gen_i]}),
          .in_vld  (q_vld[gen_i]),
          .in_rdy  (q_rdy[gen_i]),

          .out_data({j0_cmd[gen_i],j0_perm_select[gen_i],j0_rot_data[gen_i]}),
          .out_vld (j0_vld[gen_i]),
          .out_rdy (j0_rdy[gen_i])

        );

      end
    end
  endgenerate

  logic [JOIN_NB-1:0][QPSI-1:0][R-1:0][MOD_Q_W-1:0]     jin_rot_data;
  logic [JOIN_NB-1:0][1:0][PERM_W-1:0]                  jin_perm_select;
  logic [JOIN_NB-1:0][CMD_X_W-1:0]                      jin_cmd;
  logic [JOIN_NB-1:0]                                   jin_vld;
  logic [JOIN_NB-1:0]                                   jin_rdy;

  logic [JOIN_NB/2-1:0][2*QPSI-1:0][R-1:0][MOD_Q_W-1:0] jout_rot_data;
  logic [JOIN_NB/2-1:0][PERM_W-1:0]                     jout_perm_select;
  logic [JOIN_NB/2-1:0][CMD_X_W-1:0]                    jout_cmd;
  logic [JOIN_NB/2-1:0]                                 jout_vld;
  logic [JOIN_NB/2-1:0]                                 jout_rdy;

  logic [JOIN_NB/2-1:0]                                 jout_buf_cnt_do_dec;

  // Associate some control to the input.
  // Choose the one that will be its pair in the join process
  logic [1:0][PERM_W-1:0]                               in_perm_select;
  logic [CMD_X_W-1:0]                                   in_cmd;

  assign in_perm_select = (QPSI_SET_ID_OFS%2)==0 ? j0_perm_select[MSPLIT_FACTOR-1] : j0_perm_select[0];
  assign in_cmd         = (QPSI_SET_ID_OFS%2)==0 ? j0_cmd[MSPLIT_FACTOR-1]         : j0_cmd[0];

  generate
    if (!JOIN_IS_BALANCED) begin : gen_unbalanced_join
      // When unbalanced, complete with data coming from the other part.
      assign jin_rot_data    = (QPSI_SET_ID_OFS%2)==0 ? {in_rot_data,j0_rot_data}       : {j0_rot_data, in_rot_data};
      assign jin_vld         = (QPSI_SET_ID_OFS%2)==0 ? {in_vld,j0_vld}                 : {j0_vld, in_vld};
      assign jin_perm_select = (QPSI_SET_ID_OFS%2)==0 ? {in_perm_select,j0_perm_select} : {j0_perm_select,in_perm_select};
      assign jin_cmd         = (QPSI_SET_ID_OFS%2)==0 ? {in_cmd,j0_cmd}                 : {j0_cmd,in_cmd};
      assign in_rdy          = (QPSI_SET_ID_OFS%2)==0 ? jin_rdy[JOIN_NB-1]              : jin_rdy[0];
      assign j0_rdy          = (QPSI_SET_ID_OFS%2)==0 ? jin_rdy[JOIN_NB-2:0]            : jin_rdy[JOIN_NB-1:1];
    end
    else begin : gen_balanced_join
      assign jin_rot_data    = j0_rot_data;
      assign jin_perm_select = j0_perm_select;
      assign jin_cmd         = j0_cmd;
      assign jin_vld         = j0_vld;
      assign j0_rdy          = jin_rdy;
    end


    for (genvar gen_i=0; gen_i<JOIN_NB/2; gen_i=gen_i+1) begin : gen_join_loop
      if (JOIN_IS_BALANCED
          || (JOIN_QPSI_SET_ID_OFS+2*gen_i+1) <= QPSI_SET_ID_END) begin : gen_join // There is a pair available for the join.
        pep_mmacc_splitc_sxt_join
        #(
          .HPSI_SET_ID  (JOIN_QPSI_SET_ID_OFS/2+gen_i),
          .DATA_LATENCY (DATA_LATENCY),
          .CHECK_SYNCHRONIZATION((JOIN_QPSI_SET_ID_OFS+2*gen_i) >= QPSI_SET_ID_OFS) // Check synchro when both QPSI sets are present.
        ) pep_mmacc_splitc_sxt_join (
          .clk             (clk),
          .s_rst_n         (s_rst_n),

          .in0_rot_data    (jin_rot_data[2*gen_i]),
          .in0_vld         (jin_vld[2*gen_i]),
          .in0_rdy         (jin_rdy[2*gen_i]),

          .in1_rot_data    (jin_rot_data[2*gen_i+1]),
          .in1_vld         (jin_vld[2*gen_i+1]),
          .in1_rdy         (jin_rdy[2*gen_i+1]),

          .in1_perm_select (jin_perm_select[2*gen_i+1]),
          .in1_cmd         (jin_cmd[2*gen_i+1]),

          .out_rot_data    (jout_rot_data[gen_i]),
          .out_perm_select (jout_perm_select[gen_i]),
          .out_cmd         (jout_cmd[gen_i]),
          .out_vld         (jout_vld[gen_i]),
          .out_rdy         (jout_rdy[gen_i]),

          .buf_cnt_do_dec  (jout_buf_cnt_do_dec[gen_i])
        );

      end
      else begin : gen_no_join // No pair available
        assign jout_rot_data[gen_i] = {2{jin_rot_data[2*gen_i]}};
        assign jout_vld[gen_i]      = jin_vld[2*gen_i];
        assign jin_rdy[2*gen_i]     = jout_rdy[gen_i];
        assign jin_rdy[2*gen_i+1]   = 1'b0; // UNUSED

        assign jout_buf_cnt_do_dec[gen_i] = jout_vld[gen_i] & jout_rdy[gen_i];
      end
    end // gen_join_loop
  endgenerate

  // The most constrained path decides the limit
  // Synchronize the dec pulses.
  pep_mmacc_splitc_sxt_sync
  #(
    .IN_NB    (JOIN_NB/2),
    .DIFF_MAX (2*JOIN_FIFO_DEPTH),
    .OUT_PIPE (1'b0)
  ) pep_mmacc_splitc_sxt_sync (
    .clk      (clk),
    .s_rst_n  (s_rst_n),

    .in_pulse (jout_buf_cnt_do_dec),
    .out_pulse(buf_cnt_do_dec)
  );

  logic [JOIN_NB*QPSI-1:0][R-1:0][MOD_Q_W-1:0] jout_rot_data_tmp;

  // Only used when the associated join exists
  assign out_perm_select  = jout_perm_select[0];
  assign out_cmd          = jout_cmd[0];

  assign jout_rot_data_tmp = jout_rot_data;

  assign out_rot_data = jout_rot_data_tmp[0+:OPSI];
  assign out_vld      = jout_vld;
  assign jout_rdy     = out_rdy;

//=================================================================================================
// To/from GRAM
//=================================================================================================
  always_comb
    for (int g=0; g<GRAM_NB; g=g+1) begin
      for (int i=0; i<MSPLIT_FACTOR; i=i+1) begin
        sxt_gram_rd_en[g][i*QPSI+:QPSI]  = sxt_gram_rd_en_l[i][g];
        sxt_gram_rd_add[g][i*QPSI+:QPSI] = sxt_gram_rd_add_l[i][g];
        gram_sxt_rd_data_l[i][g]         = gram_sxt_rd_data[g][i*QPSI+:QPSI];
        gram_sxt_rd_data_avail_l[i][g]   = gram_sxt_rd_data_avail[g][i*QPSI+:QPSI];
      end
    end

  integer q_cnt [MSPLIT_FACTOR-1:0];
  always_ff @(posedge clk)
    for (int i=0; i<MSPLIT_FACTOR; i=i+1) begin
      if (!s_rst_n)
        q_cnt[i] <= '0;
      else
        q_cnt[i] <= q_avail[i] ? q_cnt[i] + 1 : q_cnt[i];
    end


endmodule
