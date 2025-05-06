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

module pep_mmacc_splitc_sxt_rot
  import param_tfhe_pkg::*;
  import param_ntt_pkg::*;
  import top_common_param_pkg::*;
  import ntt_core_common_param_pkg::*;
  import regf_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import pep_mmacc_common_param_pkg::*;
  import pep_mmacc_splitc_sxt_pkg::*;
#(
  parameter bit INPUT_DLY     = 1'b0, // Delay to be applied when 2nd set of coef
  parameter int QPSI_SET_ID   = 0,    // Indicates which of the four R*PSI/4 coef sets is processed here
  parameter int DATA_LATENCY  = 6     // Latency for read data to come back
)
(
  input  logic                                                     clk,        // clock
  input  logic                                                     s_rst_n,    // synchronous reset

  // GRAM access
  input  logic                                                     in_s1_rd_en,
  input  logic [GLWE_RAM_ADD_W-1:0]                                in_s1_rd_add,
  input  logic [GRAM_ID_W-1:0]                                     in_s1_rd_grid,

  input  logic                                                     in_x0_avail,
  input  logic [CMD_SS2_W-1:0]                                     in_x0_cmd,

  // Read from GRAM
  output logic [GRAM_NB-1:0][PSI/4-1:0][R-1:0]                     sxt_gram_rd_en,
  output logic [GRAM_NB-1:0][PSI/4-1:0][R-1:0][GLWE_RAM_ADD_W-1:0] sxt_gram_rd_add,
  input  logic [GRAM_NB-1:0][PSI/4-1:0][R-1:0][MOD_Q_W-1:0]        gram_sxt_rd_data,
  input  logic [GRAM_NB-1:0][PSI/4-1:0][R-1:0]                     gram_sxt_rd_data_avail,

  // Output data
  output logic [PSI/4-1:0][R-1:0][MOD_Q_W-1:0]                     out_rot_data,
  output logic [1:0][PERM_W-1:0]                                   out_perm_select, // last 2 levels of permutation
  output logic [CMD_X_W-1:0]                                       out_cmd,
  output logic                                                     out_avail
);

// ============================================================================================= --
// localparam
// ============================================================================================= --
  localparam int QPSI          = PSI/4;
  localparam int PERM_SEL_OFS  = (R*QPSI*QPSI_SET_ID);
  localparam int PERM_LVL_NB_L = PERM_LVL_NB - 2; // 2 levels are done outside this module

  `PEP_MMACC_SPLITC_SXT_LOCALPARAM(R,PSI,DATA_LATENCY,REGF_COEF_NB,REGF_COEF_PER_URAM_WORD,REGF_BLWE_WORD_PER_RAM,DATA_THRESHOLD)

  generate
    if (PSI < 4) begin : __UNSUPPORTED_PSI
      $fatal(1,"> ERROR: For MMACC PSI must be greater or equal to 4.");
    end
  endgenerate

// pragma translate_off
  initial begin
    $display("> INFO: PERM_LVL_NB=%0d",PERM_LVL_NB);
    $display("> INFO: PERM_W=%0d",PERM_W);
  end
// pragma translate_on

// ============================================================================================= --
// typedef
// ============================================================================================= --


// ============================================================================================= --
// Input pipe
// ============================================================================================= --
  logic                      s1_rd_en;
  logic [GLWE_RAM_ADD_W-1:0] s1_rd_add;
  logic [GRAM_ID_W-1:0]      s1_rd_grid;

  logic                      x0_avail;
  cmd_ss2_t                  x0_cmd;

  generate
    if (INPUT_DLY) begin : gen_dly_input
      always_ff @(posedge clk)
        if (!s_rst_n) begin
          s1_rd_en  <= 1'b0;
          x0_avail  <= 1'b0;
        end
        else begin
          s1_rd_en  <= in_s1_rd_en ;
          x0_avail  <= in_x0_avail ;
        end

      always_ff @(posedge clk) begin
        s1_rd_add   <= in_s1_rd_add;
        s1_rd_grid  <= in_s1_rd_grid;
        x0_cmd      <= in_x0_cmd;
      end

    end
    else begin : gen_no_dly_input
      assign s1_rd_en    = in_s1_rd_en;
      assign s1_rd_add   = in_s1_rd_add;
      assign s1_rd_grid  = in_s1_rd_grid;

      assign x0_avail    = in_x0_avail;
      assign x0_cmd      = in_x0_cmd;
    end
  endgenerate

// ============================================================================================= --
// S2 : Format to GRAM read request -> R*QPSI
// ============================================================================================= --
  /*(* dont_touch = "yes" *)*/logic [QPSI-1:0][R-1:0]                     s2_rd_en;
  /*(* dont_touch = "yes" *)*/logic [QPSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0] s2_rd_add;
  /*(* dont_touch = "yes" *)*/logic [QPSI-1:0][R-1:0][GRAM_NB-1:0]        s2_rd_grid_1h;

  always_ff @(posedge clk)
    if (!s_rst_n)  s2_rd_en <= '0;
    else           s2_rd_en <= {R*QPSI{s1_rd_en}};

  always_ff @(posedge clk) begin
    s2_rd_add <= {R*QPSI{s1_rd_add}};
    for (int p=0; p<QPSI; p=p+1) begin
      for (int r=0; r<R; r=r+1) begin
        s2_rd_grid_1h[p][r] <= 1 << s1_rd_grid; // duplicate
      end
    end
  end

// ============================================================================================= --
// S3 : R*QPSI -> GRAM_NB
// ============================================================================================= --
  logic [GRAM_NB-1:0][QPSI-1:0][R-1:0]                     s2_gram_rd_en;
  logic [GRAM_NB-1:0][QPSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0] s2_gram_rd_add;

  /*(* dont_touch = "yes" *)*/logic [GRAM_NB-1:0][QPSI-1:0][R-1:0]                     s3_gram_rd_en;
  /*(* dont_touch = "yes" *)*/logic [GRAM_NB-1:0][QPSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0] s3_gram_rd_add;

  always_comb
    for (int t=0; t<GRAM_NB; t=t+1)
      for (int p=0; p<QPSI; p=p+1)
        for (int r=0; r<R; r=r+1)
          s2_gram_rd_en[t][p][r] = s2_rd_en[p][r] & s2_rd_grid_1h[p][r][t];

  assign s2_gram_rd_add = {GRAM_NB{s2_rd_add}};

  always_ff @(posedge clk)
    if (!s_rst_n) s3_gram_rd_en <= '0;
    else          s3_gram_rd_en <= s2_gram_rd_en;

  always_ff @(posedge clk)
    s3_gram_rd_add <= s2_gram_rd_add;

//=================================================================================================
// sxt_gram
//=================================================================================================
  assign sxt_gram_rd_en  = s3_gram_rd_en;
  assign sxt_gram_rd_add = s3_gram_rd_add;

//=================================================================================================
// gram_sxt pipe
//=================================================================================================
  logic [GRAM_NB-1:0][QPSI-1:0][R-1:0][MOD_Q_W-1:0] x0_gram_sxt_rd_data;
  logic [GRAM_NB-1:0][QPSI-1:0][R-1:0]           x0_gram_sxt_rd_data_avail;

  always_ff @(posedge clk)
    if (!s_rst_n) x0_gram_sxt_rd_data_avail <= '0;
    else          x0_gram_sxt_rd_data_avail <= gram_sxt_rd_data_avail;

  always_ff @(posedge clk)
    x0_gram_sxt_rd_data <= gram_sxt_rd_data;

// ============================================================================================= --
// X0 : Extract data
// ============================================================================================= --
//== GRAM_NBxQPSIxR -> QPSIxR
  logic [QPSI-1:0][R-1:0][MOD_Q_W-1:0] x0_gram_rd_data;
  logic [QPSI-1:0][R-1:0]              x0_gram_rd_data_avail;

  logic [QPSI*R-1:0][MOD_Q_W-1:0] x1_gram_rd_data;
  logic [QPSI-1:0][R-1:0]             x1_gram_rd_data_avail;

  logic [GRAM_NB-1:0][QPSI-1:0][R-1:0][MOD_Q_W-1:0] x0_gram_sxt_rd_data_masked;

  always_comb
    for (int t=0; t<GRAM_NB; t=t+1)
      for (int p=0; p<QPSI; p=p+1)
        for (int r=0; r<R; r=r+1)
          x0_gram_sxt_rd_data_masked[t][p][r] = x0_gram_sxt_rd_data[t][p][r] & {MOD_Q_W{x0_gram_sxt_rd_data_avail[t][p][r]}};

  always_comb begin
    x0_gram_rd_data       = '0;
    x0_gram_rd_data_avail = '0;
    for (int t=0; t<GRAM_NB; t=t+1) begin
      x0_gram_rd_data       = x0_gram_rd_data       | x0_gram_sxt_rd_data_masked[t];
      x0_gram_rd_data_avail = x0_gram_rd_data_avail | x0_gram_sxt_rd_data_avail[t];
    end
  end

  always_ff @(posedge clk)
    if (!s_rst_n) x1_gram_rd_data_avail <= '0;
    else          x1_gram_rd_data_avail <= x0_gram_rd_data_avail;

  always_ff @(posedge clk)
    x1_gram_rd_data <= x0_gram_rd_data;

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // Do nothing
    end
    else begin
      assert(($countones(gram_sxt_rd_data_avail) == QPSI*R) || (gram_sxt_rd_data_avail=='0))
      else begin
        $fatal(1,"%t > ERROR: gram_sxt_rd_data_avail is incoherent!", $time);
      end
      for (int t=0; t<GRAM_NB; t=t+1) begin
        assert(gram_sxt_rd_data_avail[t] == '0 || gram_sxt_rd_data_avail[t] == '1)
        else begin
          $fatal(1,"%t > ERROR: gram_sxt_rd_data_avail[%0d] is incoherent!", $time,t);
        end
      end
      if (x0_avail) begin
        assert(x0_gram_sxt_rd_data_avail != '0)
        else begin
          $fatal(1,"%t > ERROR: gram_sxt_rd_data and sxt shift-register are not synchronized!", $time);
        end
      end
    end
// pragma translate_on

// ============================================================================================= --
// X0 : Compute sign mask + permutation vector for 1rst level
// ============================================================================================= --
  logic [QPSI*R-1:0][N_W-1:0] x0_id_a;
  always_comb
    for (int i=0; i<QPSI*R; i=i+1) begin
      logic [N_W-1:0] idx_tmp;
      idx_tmp    = (x0_cmd.add_local << RD_COEF_W) + i + PERM_SEL_OFS;  // no operation here
      x0_id_a[i] = rev_order_n(idx_tmp);                 // no operation here
    end

  // sign_0 = rot_factor in [N,2*N[ ? 1 : 0
  // If the ID is > rot_factor % N, use the opposite of sign_0
  // else use the same sign as sign_0
  logic                  x0_sign_0;
  logic [QPSI*R-1:0] x0_sign_a;

  assign x0_sign_0 = ((x0_cmd.rot_factor) >= N) & (x0_cmd.rot_factor < (2*N));
  always_comb
    for (int i=0; i<QPSI*R; i=i+1)
      x0_sign_a[i] = x0_id_a[i] > x0_cmd.rot_factor[N_W-1:0] ? ~x0_sign_0 : x0_sign_0;

  // Permutation vector for level
  logic [LWE_COEF_W-1:0] x0_perm_rot;
  logic [PERM_W-1:0]     x0_perm_select;

  assign x0_perm_rot = x0_cmd.id_0 + (PERM_W+1)*STG_ITER_NB;
  pep_mmacc_common_permutation_vector
  #(
    .PERM_LVL_NB  (PERM_LVL_NB), // Total number of permutation levels
    .PERM_LVL     (PERM_LVL_NB-1), // from 0 to PERM_LVL_NB-1
    .N_SZ         (N_SZ)
  ) x0_pep_mmacc_common_permutation_vector (
    .rot_factor (x0_perm_rot),
    .perm_select(x0_perm_select)
  );

  cmd_x_t x0_x1_cmd;

  assign x0_x1_cmd.pid     = x0_cmd.pid;
  assign x0_x1_cmd.dst_rid = x0_cmd.dst_rid;
  assign x0_x1_cmd.is_body = x0_cmd.is_body;
  assign x0_x1_cmd.id_0    = x0_cmd.id_0;
  assign x0_x1_cmd.is_last = x0_cmd.is_last;

// ============================================================================================= --
// X1 : permutation 1rst level
// ============================================================================================= --
  logic                  x1_avail;
  cmd_x_t                x1_cmd;
  logic [QPSI*R-1:0] x1_sign_a;
  logic [PERM_W-1:0]     x1_perm_select;

  always_ff @(posedge clk)
    if (!s_rst_n) x1_avail <= 1'b0;
    else          x1_avail <= x0_avail;

  always_ff @(posedge clk) begin
    x1_cmd         <= x0_x1_cmd;
    x1_sign_a      <= x0_sign_a;
    x1_perm_select <= x0_perm_select;
  end

  // Sign mask
  logic [QPSI*R-1:0][MOD_Q_W-1:0] x1_withsign_data;
  always_comb
    for (int i=0; i<QPSI*R; i=i+1)
      x1_withsign_data[i] = x1_sign_a[i] ? (2**MOD_Q_W) - x1_gram_rd_data[i] : x1_gram_rd_data[i];

  // Permutation level PERM_LVL_NB-1
  // Permute coefficients that are at position 2i <-> 2i+1 according to perm_select[i]
  logic [QPSI*R-1:0][MOD_Q_W-1:0] x1_perm_data;
  always_comb
    for (int i=0; i<QPSI*R; i=i+2) begin
      x1_perm_data[i]   = x1_perm_select[(PERM_SEL_OFS+i)/2] ? x1_withsign_data[i+1] : x1_withsign_data[i];
      x1_perm_data[i+1] = x1_perm_select[(PERM_SEL_OFS+i)/2] ? x1_withsign_data[i]   : x1_withsign_data[i+1];
    end

  // Compute permutation level for next steps
  logic [PERM_W/2-1:0]   x1_perm_select_next;
  logic [LWE_COEF_W-1:0] x1_perm_rot;

  assign x1_perm_rot = x1_cmd.id_0 + (PERM_W/2+1)*STG_ITER_NB;
  pep_mmacc_common_permutation_vector
  #(
    .PERM_LVL_NB  (PERM_LVL_NB), // Total number of permutation levels
    .PERM_LVL     (PERM_LVL_NB-2), // from 0 to PERM_LVL_NB-1
    .N_SZ         (N_SZ)
  ) x1_pep_mmacc_common_permutation_vector (
    .rot_factor (x1_perm_rot),
    .perm_select(x1_perm_select_next)
  );

// ============================================================================================= --
// X2 : permutation
// ============================================================================================= --
  // Permutation
  //
  // Note : to ease the writing, a regular structure is used.
  // Some stages of the bus are not used.
  // All this will be removed by the synthesizer.
  //
  // Here it remains PERM_LVL_NB-1 levels of permutations.
  // If PERM_LVL_NB-1 is odd, we start with a single permutation.
  // Then permutations are done 2 levels at a time.
  logic                                            x2_avail;
  cmd_x_t                                          x2_cmd;
  logic [QPSI*R-1:0][MOD_Q_W-1:0]                  x2_perm_data;
  logic [PERM_W-1:0]                               x2_perm_select;

  logic [PERM_LVL_NB-1:0][QPSI*R-1:0][MOD_Q_W-1:0] x2_l_perm_data;
  logic [PERM_LVL_NB-1:0]                          x2_l_avail;
  cmd_x_t [PERM_LVL_NB-1:0]                        x2_l_cmd;
  logic [PERM_LVL_NB-1:0][PERM_W-1:0]              x2_l_perm_select;

  always_ff @(posedge clk)
    if (!s_rst_n) x2_avail <= 1'b0;
    else          x2_avail <= x1_avail;

  always_ff @(posedge clk) begin
    x2_cmd         <= x1_cmd;
    x2_perm_data   <= x1_perm_data;
    x2_perm_select <= x1_perm_select_next;
  end

  assign x2_l_perm_data[PERM_LVL_NB-1]   = x2_perm_data;
  assign x2_l_avail[PERM_LVL_NB-1]       = x2_avail;
  assign x2_l_cmd[PERM_LVL_NB-1]         = x2_cmd;
  assign x2_l_perm_select[PERM_LVL_NB-1] = x2_perm_select;

  generate
    if (PERM_LVL_NB_L % 2 == 0) begin : gen_perm_lvl_penult
      // Once the first level is processed, it remains an odd number of permutation levels.
      // Do 1 level here.
      localparam int PERM_LVL     = PERM_LVL_NB - 2;
      localparam int PERM_NB      = 2**PERM_LVL;
      localparam int PERM_NB_NEXT = PERM_NB/2;
      localparam int ELT_NB       = 2**(PERM_LVL_NB-1 - PERM_LVL); // Number of elements to be permuted together

      // Do permutation on 2*ELT_NB <-> 2*ELT_NB + ELT_NB
      logic [QPSI*R-1:0][MOD_Q_W-1:0] x2_perm_data_tmp;
      logic [QPSI*R-1:0][MOD_Q_W-1:0] x2_perm_data_tmpD;
      always_comb
        for (int i=0; i<R*QPSI; i=i+2*ELT_NB) begin
          x2_perm_data_tmpD[i+:ELT_NB]        = x2_l_perm_select[PERM_LVL+1][(PERM_SEL_OFS+i)/(2*ELT_NB)] ? x2_l_perm_data[PERM_LVL+1][i+ELT_NB+:ELT_NB]
                                                                                           : x2_l_perm_data[PERM_LVL+1][i+:ELT_NB];
          x2_perm_data_tmpD[i+ELT_NB+:ELT_NB] = x2_l_perm_select[PERM_LVL+1][(PERM_SEL_OFS+i)/(2*ELT_NB)] ? x2_l_perm_data[PERM_LVL+1][i+:ELT_NB]
                                                                                           : x2_l_perm_data[PERM_LVL+1][i+ELT_NB+:ELT_NB];
        end

      // Register for next level
      logic    x2_avail_tmp;
      cmd_x_t  x2_cmd_tmp;

      always_ff @(posedge clk) begin
        x2_perm_data_tmp    <= x2_perm_data_tmpD;
        x2_cmd_tmp          <= x2_l_cmd[PERM_LVL+1];
      end

      always_ff @(posedge clk)
        if (!s_rst_n) x2_avail_tmp <= '0;
        else          x2_avail_tmp <= x2_l_avail[PERM_LVL+1];

      assign x2_l_perm_data[PERM_LVL] = x2_perm_data_tmp;
      assign x2_l_cmd[PERM_LVL]       = x2_cmd_tmp;
      assign x2_l_avail[PERM_LVL]     = x2_avail_tmp;

      // Permutation vector for next level
      // During next steps, 2 levels are processed.
      logic [PERM_NB_NEXT-1:0]   x2_perm_select_next;
      logic [PERM_NB_NEXT-1:0]   x2_perm_select_nextD;
      logic [PERM_NB_NEXT/2-1:0] x2_perm_select_next2;
      logic [PERM_NB_NEXT/2-1:0] x2_perm_select_next2D;
      logic [LWE_COEF_W-1:0]     x2_perm_rot;
      logic [LWE_COEF_W-1:0]     x2_perm_rot2;

      assign x2_perm_rot  = x2_l_cmd[PERM_LVL+1].id_0 + (PERM_NB_NEXT+1)*STG_ITER_NB;
      assign x2_perm_rot2 = x2_l_cmd[PERM_LVL+1].id_0 + (PERM_NB_NEXT/2+1)*STG_ITER_NB;

      assign x2_l_perm_select[PERM_LVL]   = x2_perm_select_next; // extend with 0s
      assign x2_l_perm_select[PERM_LVL-1] = x2_perm_select_next2; // extend with 0s

      always_ff @(posedge clk) begin
        x2_perm_select_next  <= x2_perm_select_nextD;
        x2_perm_select_next2 <= x2_perm_select_next2D;
      end

      pep_mmacc_common_permutation_vector
      #(
        .PERM_LVL_NB  (PERM_LVL_NB), // Total number of permutation levels
        .PERM_LVL     (PERM_LVL-1), // from 0 to PERM_LVL_NB-1
        .N_SZ         (N_SZ)
      ) x2_pep_mmacc_common_permutation_vector (
        .rot_factor (x2_perm_rot),
        .perm_select(x2_perm_select_nextD)
      );

      pep_mmacc_common_permutation_vector
      #(
        .PERM_LVL_NB  (PERM_LVL_NB), // Total number of permutation levels
        .PERM_LVL     (PERM_LVL-2), // from 0 to PERM_LVL_NB-1
        .N_SZ         (N_SZ)
      ) x2_pep_mmacc_common_permutation_vector2 (
        .rot_factor (x2_perm_rot2),
        .perm_select(x2_perm_select_next2D)
      );

    end // if gen_perm_lvl_penult
    else begin : gen_no_perm_lvl_penult
      // Prepare the 2nd selection for the next stages
      localparam int PERM_LVL     = PERM_LVL_NB - 2;
      localparam int PERM_NB      = 2**PERM_LVL;
      localparam int PERM_NB_NEXT = PERM_NB/2;

      logic [PERM_NB_NEXT-1:0] x2_perm_select_next2;
      logic [PERM_NB_NEXT-1:0] x2_perm_select_next2D;

      logic [LWE_COEF_W-1:0]   x1_perm_rot2;

      assign x1_perm_rot2 = x1_cmd.id_0 + (PERM_NB_NEXT+1)*STG_ITER_NB;

      assign x2_l_perm_select[PERM_LVL] = x2_perm_select_next2; // extend with 0s

      always_ff @(posedge clk)
        x2_perm_select_next2 <= x2_perm_select_next2D;

      pep_mmacc_common_permutation_vector
      #(
        .PERM_LVL_NB  (PERM_LVL_NB), // Total number of permutation levels
        .PERM_LVL     (PERM_LVL-1), // from 0 to PERM_LVL_NB-1
        .N_SZ         (N_SZ)
      ) x2_pep_mmacc_common_permutation_vector2 (
        .rot_factor (x1_perm_rot2), // Take this, since it is for the 1rst round
        .perm_select(x2_perm_select_next2D)
      );

    end

    // Remaining levels : there is an even number of levels. Do them 2 at a time.
    // Do not process the last 2, since they are done elsewhere.
    for (genvar gen_l=((PERM_LVL_NB+1)/2)*2 - 3; gen_l>2; gen_l=gen_l-2) begin : gen_perm_loop
      localparam int PERM_NB      = 2**gen_l;
      localparam int PERM_NB_NEXT = PERM_NB/4;
      localparam int ELT_NB  = 2**(PERM_LVL_NB-1 - gen_l); // Number of elements to be permuted together

      // Do permutation on 2*ELT_NB <-> 2*ELT_NB + ELT_NB
      logic [QPSI*R-1:0][MOD_Q_W-1:0] x2_perm_data_tmp;
      logic [QPSI*R-1:0][MOD_Q_W-1:0] x2_perm_data_tmpD_0;
      logic [QPSI*R-1:0][MOD_Q_W-1:0] x2_perm_data_tmpD;
      always_comb
        for (int i=0; i<R*QPSI; i=i+2*ELT_NB) begin
          x2_perm_data_tmpD_0[i+:ELT_NB]        = x2_l_perm_select[gen_l+1][(PERM_SEL_OFS+i)/(2*ELT_NB)] ? x2_l_perm_data[gen_l+1][i+ELT_NB+:ELT_NB]
                                                                                          : x2_l_perm_data[gen_l+1][i+:ELT_NB];
          x2_perm_data_tmpD_0[i+ELT_NB+:ELT_NB] = x2_l_perm_select[gen_l+1][(PERM_SEL_OFS+i)/(2*ELT_NB)] ? x2_l_perm_data[gen_l+1][i+:ELT_NB]
                                                                                          : x2_l_perm_data[gen_l+1][i+ELT_NB+:ELT_NB];
        end

      // Do permutation on 2*2*ELT_NB <-> 2*2*ELT_NB + 2*ELT_NB
      always_comb
        for (int i=0; i<R*QPSI; i=i+2*2*ELT_NB) begin
          x2_perm_data_tmpD[i+:2*ELT_NB]          = x2_l_perm_select[gen_l][(PERM_SEL_OFS+i)/(2*2*ELT_NB)] ? x2_perm_data_tmpD_0[i+2*ELT_NB+:2*ELT_NB]
                                                                                            : x2_perm_data_tmpD_0[i+:2*ELT_NB];
          x2_perm_data_tmpD[i+2*ELT_NB+:2*ELT_NB] = x2_l_perm_select[gen_l][(PERM_SEL_OFS+i)/(2*2*ELT_NB)] ? x2_perm_data_tmpD_0[i+:2*ELT_NB]
                                                                                            : x2_perm_data_tmpD_0[i+2*ELT_NB+:2*ELT_NB];
        end

      // Register for next level
      logic    x2_avail_tmp;
      cmd_x_t  x2_cmd_tmp;

      always_ff @(posedge clk) begin
        x2_perm_data_tmp <= x2_perm_data_tmpD;
        x2_cmd_tmp       <= x2_l_cmd[gen_l+1];
      end

      always_ff @(posedge clk)
        if (!s_rst_n) x2_avail_tmp <= 1'b0;
        else          x2_avail_tmp <= x2_l_avail[gen_l+1];


      assign x2_l_perm_data[gen_l-1] = x2_perm_data_tmp;
      assign x2_l_cmd[gen_l-1]       = x2_cmd_tmp;
      assign x2_l_avail[gen_l-1]     = x2_avail_tmp;

      // Permutation vector for next level
      logic [PERM_NB_NEXT-1:0]   x2_perm_select_next;
      logic [PERM_NB_NEXT-1:0]   x2_perm_select_nextD;
      logic [PERM_NB_NEXT/2-1:0] x2_perm_select_next2;
      logic [PERM_NB_NEXT/2-1:0] x2_perm_select_next2D;
      logic [LWE_COEF_W-1:0]     x2_perm_rot;
      logic [LWE_COEF_W-1:0]     x2_perm_rot2;

      assign x2_perm_rot  = x2_l_cmd[gen_l+1].id_0 + (PERM_NB_NEXT+1)*STG_ITER_NB;
      assign x2_perm_rot2 = x2_l_cmd[gen_l+1].id_0 + (PERM_NB_NEXT/2+1)*STG_ITER_NB;

      assign x2_l_perm_select[gen_l-1] = x2_perm_select_next; // extend with 0s
      assign x2_l_perm_select[gen_l-2] = x2_perm_select_next2; // extend with 0s

      always_ff @(posedge clk) begin
        x2_perm_select_next  <= x2_perm_select_nextD;
        x2_perm_select_next2 <= x2_perm_select_next2D;
      end

      pep_mmacc_common_permutation_vector
      #(
        .PERM_LVL_NB  (PERM_LVL_NB), // Total number of permutation levels
        .PERM_LVL     (gen_l-2), // from 0 to PERM_LVL_NB-1
        .N_SZ         (N_SZ)
      ) x2_pep_mmacc_common_permutation_vector (
        .rot_factor (x2_perm_rot),
        .perm_select(x2_perm_select_nextD)
      );
      pep_mmacc_common_permutation_vector
      #(
        .PERM_LVL_NB  (PERM_LVL_NB), // Total number of permutation levels
        .PERM_LVL     (gen_l-3), // from 0 to PERM_LVL_NB-1
        .N_SZ         (N_SZ)
      ) x2_pep_mmacc_common_permutation_vector2 (
        .rot_factor (x2_perm_rot2),
        .perm_select(x2_perm_select_next2D)
      );

    end // for gen_l : gen_perm_loop
  endgenerate

// ============================================================================================= --
// Output
// ============================================================================================= --
  assign out_rot_data     = x2_l_perm_data[2];
  assign out_perm_select  = x2_l_perm_select[2:1];
  assign out_avail        = x2_l_avail[2];
  assign out_cmd          = x2_l_cmd[2];

endmodule
