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
// LRAM : stands for LWE RAM
//
// ==============================================================================================

module pep_mmacc_splitc_feed_rot
  import param_tfhe_pkg::*;
  import ntt_core_common_param_pkg::*;
  import top_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import pep_mmacc_common_param_pkg::*;
  import pep_mmacc_splitc_feed_pkg::*;
#(
  parameter bit INPUT_DLY   = 1'b0, // Delay to be applied when 2nd set of coef
  parameter int QPSI_SET_ID = 0     // Indicates which of the four R*PSI/4 coef sets is processed here
)
(
  input  logic                                                           clk,        // clock
  input  logic                                                           s_rst_n,    // synchronous reset

  // Gram access
  input  logic                                                           in_f1_rd_en,
  input  logic [GLWE_RAM_ADD_W-1:0]                                      in_f1_rd_add,
  input  logic [GRAM_ID_W-1:0]                                           in_f1_rd_grid,

  input  logic                                                           in_ff3_rd_en,
  input  logic [GLWE_RAM_ADD_W-1:0]                                      in_ff3_rd_add,
  input  logic [GRAM_ID_W-1:0]                                           in_ff3_rd_grid,

  input  logic                                                           in_s0_avail,
  input  logic [REQ_CMD_W-1:0]                                           in_s0_rcmd,

  input  logic                                                           in_ss1_avail,
  input  logic [REQ_CMD_W-1:0]                                           in_ss1_rcmd,

  // Gram access
  output logic [GRAM_NB-1:0][PSI/4-1:0][R-1:0][1:0]                      feed_gram_rd_en,
  output logic [GRAM_NB-1:0][PSI/4-1:0][R-1:0][1:0][GLWE_RAM_ADD_W-1:0]  feed_gram_rd_add,
  input  logic [GRAM_NB-1:0][PSI/4-1:0][R-1:0][1:0][MOD_Q_W-1:0]         gram_feed_rd_data,
  input  logic [GRAM_NB-1:0][PSI/4-1:0][R-1:0][1:0]                      gram_feed_rd_data_avail,

  // Output data
  output logic [PSI/4-1:0][R-1:0][MOD_Q_W-1:0]                           out_data,
  output logic [PSI/4-1:0][R-1:0][MOD_Q_W-1:0]                           out_rot_data,
  output logic [1:0][PERM_W-1:0]                                         out_perm_select, // last 2 levels of permutation
  output logic [LWE_COEF_W:0]                                            out_coef_rot_id0,
  output logic [REQ_CMD_W-1:0]                                           out_rcmd,
  output logic [PSI/4-1:0][R-1:0]                                        out_data_avail
);

// ============================================================================================= --
// localparam
// ============================================================================================= --
  localparam int QPSI = PSI / 4;
  localparam int PERM_SEL_OFS = (R*QPSI*QPSI_SET_ID);
  localparam int PERM_LVL_NB_L = PERM_LVL_NB - 2; // 2 levels are done outside this module


  generate
    if (PSI < 4) begin : __UNSUPPORTED_PSI
      $fatal(1,"> ERROR: For MMACC PSI must be greater or equal to 4.");
    end
  endgenerate


// ============================================================================================= --
// Input pipe
// ============================================================================================= --
  logic                      f1_rd_en;
  logic [GLWE_RAM_ADD_W-1:0] f1_rd_add;
  logic [GRAM_ID_W-1:0]      f1_rd_grid;

  logic                      ff3_rd_en;
  logic [GLWE_RAM_ADD_W-1:0] ff3_rd_add;
  logic [GRAM_ID_W-1:0]      ff3_rd_grid;

  logic                      s0_avail;
  req_cmd_t                  s0_rcmd;

  logic                      ss1_avail;
  req_cmd_t                  ss1_rcmd;

  generate
    if (INPUT_DLY) begin : gen_dly_input
      always_ff @(posedge clk)
        if (!s_rst_n) begin
          f1_rd_en  <= 1'b0;
          ff3_rd_en <= 1'b0;
          s0_avail  <= 1'b0;
          ss1_avail <= 1'b0;
        end
        else begin
          f1_rd_en  <= in_f1_rd_en ;
          ff3_rd_en <= in_ff3_rd_en;
          s0_avail  <= in_s0_avail ;
          ss1_avail <= in_ss1_avail;
        end

      always_ff @(posedge clk) begin
        f1_rd_add   <= in_f1_rd_add;
        f1_rd_grid  <= in_f1_rd_grid;
        ff3_rd_add  <= in_ff3_rd_add;
        ff3_rd_grid <= in_ff3_rd_grid;
        s0_rcmd     <= in_s0_rcmd;
        ss1_rcmd    <= in_ss1_rcmd;
      end

    end
    else begin : gen_no_dly_input
      assign f1_rd_en    = in_f1_rd_en;
      assign f1_rd_add   = in_f1_rd_add;
      assign f1_rd_grid  = in_f1_rd_grid;

      assign ff3_rd_en   = in_ff3_rd_en;
      assign ff3_rd_add  = in_ff3_rd_add;
      assign ff3_rd_grid = in_ff3_rd_grid;

      assign s0_avail    = in_s0_avail;
      assign s0_rcmd     = in_s0_rcmd;

      assign ss1_avail   = in_ss1_avail;
      assign ss1_rcmd    = in_ss1_rcmd;
    end
  endgenerate

//=================================================================================================
// F2
//=================================================================================================
// Format to GRAM read request : -> R*QPSI
  /*(* dont_touch = "yes" *)*/logic [QPSI-1:0][R-1:0]                     f2_rd_en;
  /*(* dont_touch = "yes" *)*/logic [QPSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0] f2_rd_add;
  /*(* dont_touch = "yes" *)*/logic [QPSI-1:0][R-1:0][GRAM_NB-1:0]        f2_rd_grid_1h;

  always_ff @(posedge clk)
    if (!s_rst_n)  f2_rd_en <= '0;
    else           f2_rd_en <= {R*QPSI{f1_rd_en}};

  always_ff @(posedge clk)
    for (int p=0; p<QPSI; p=p+1)
      for (int r=0; r<R; r=r+1) begin
        f2_rd_add[p][r]     <= f1_rd_add;
        f2_rd_grid_1h[p][r] <= 1 << f1_rd_grid;
      end

//=================================================================================================
// F3
//=================================================================================================
// R*QPSI -> GRAM_NB
  logic [GRAM_NB-1:0][QPSI-1:0][R-1:0]                     f2_gram_rd_en;
  logic [GRAM_NB-1:0][QPSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0] f2_gram_rd_add;

  /*(* dont_touch = "yes" *)*/logic [GRAM_NB-1:0][QPSI-1:0][R-1:0]                     f3_gram_rd_en;
  /*(* dont_touch = "yes" *)*/logic [GRAM_NB-1:0][QPSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0] f3_gram_rd_add;

  always_comb
    for (int t=0; t<GRAM_NB; t=t+1)
      for (int p=0; p<QPSI; p=p+1)
        for (int r=0; r<R; r=r+1)
          f2_gram_rd_en[t][p][r] = f2_rd_en[p][r] & f2_rd_grid_1h[p][r][t];

  assign f2_gram_rd_add = {GRAM_NB{f2_rd_add}};

  always_ff @(posedge clk)
    if (!s_rst_n) f3_gram_rd_en <= '0;
    else          f3_gram_rd_en <= f2_gram_rd_en;

  always_ff @(posedge clk)
    f3_gram_rd_add <= f2_gram_rd_add;

//=================================================================================================
// FF4
//=================================================================================================
// Format to GRAM read request : -> R*QPSI
  /*(* dont_touch = "yes" *)*/logic [QPSI-1:0][R-1:0]                     ff4_rd_en;
  /*(* dont_touch = "yes" *)*/logic [QPSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0] ff4_rd_add;
  /*(* dont_touch = "yes" *)*/logic [QPSI-1:0][R-1:0][GRAM_NB-1:0]        ff4_rd_grid_1h;

  always_ff @(posedge clk)
    if (!s_rst_n)  ff4_rd_en <= '0;
    else           ff4_rd_en <= {R*QPSI{ff3_rd_en}};

  always_ff @(posedge clk)
    for (int p=0; p<QPSI; p=p+1)
      for (int r=0; r<R; r=r+1) begin
        ff4_rd_add[p][r]     <= ff3_rd_add;
        ff4_rd_grid_1h[p][r] <= 1 << ff3_rd_grid;
      end

//=================================================================================================
// FF5
//=================================================================================================
// R*QPSI -> GRAM_NB
  logic [GRAM_NB-1:0][QPSI-1:0][R-1:0]                     ff4_gram_rd_en;
  logic [GRAM_NB-1:0][QPSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0] ff4_gram_rd_add;

  /*(* dont_touch = "yes" *)*/logic [GRAM_NB-1:0][QPSI-1:0][R-1:0]                     ff5_gram_rd_en;
  /*(* dont_touch = "yes" *)*/logic [GRAM_NB-1:0][QPSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0] ff5_gram_rd_add;

  always_comb
    for (int t=0; t<GRAM_NB; t=t+1)
      for (int p=0; p<QPSI; p=p+1)
        for (int r=0; r<R; r=r+1)
          ff4_gram_rd_en[t][p][r] = ff4_rd_en[p][r] & ff4_rd_grid_1h[p][r][t];

  assign ff4_gram_rd_add = {GRAM_NB{ff4_rd_add}};

  always_ff @(posedge clk)
    if (!s_rst_n) ff5_gram_rd_en <= '0;
    else          ff5_gram_rd_en <= ff4_gram_rd_en;

  always_ff @(posedge clk)
    ff5_gram_rd_add <= ff4_gram_rd_add;

//=================================================================================================
// feed_gram
//=================================================================================================
  always_comb
    for (int g=0; g<GRAM_NB; g=g+1)
      for (int p=0; p<QPSI; p=p+1)
        for (int r=0; r<R; r=r+1) begin
          feed_gram_rd_en[g][p][r][1]  = ff5_gram_rd_en[g][p][r];
          feed_gram_rd_add[g][p][r][1] = ff5_gram_rd_add[g][p][r];
          feed_gram_rd_en[g][p][r][0]  = f3_gram_rd_en[g][p][r];
          feed_gram_rd_add[g][p][r][0] = f3_gram_rd_add[g][p][r];
        end

//=================================================================================================
// gram_feed pipe
//=================================================================================================
  logic [GRAM_NB-1:0][QPSI-1:0][R-1:0][1:0][MOD_Q_W-1:0] s0_gram_feed_rd_data;
  logic [GRAM_NB-1:0][QPSI-1:0][R-1:0][1:0]              s0_gram_feed_rd_data_avail;

  always_ff @(posedge clk)
    if (!s_rst_n) s0_gram_feed_rd_data_avail <= '0;
    else          s0_gram_feed_rd_data_avail <= gram_feed_rd_data_avail;

  always_ff @(posedge clk)
    s0_gram_feed_rd_data <= gram_feed_rd_data;


//=================================================================================================
// S0
//=================================================================================================
// /!\ Process all the data here : rot and non rot, ease writing.
// Note that they are not available at the same cycle.
// non rot data are available later.
//== GRAM_NBxQPSIxRx2 -> QPSIxRx2
  logic [QPSI-1:0][R-1:0][1:0][MOD_Q_W-1:0] s0_gram_rd_data;
  logic [QPSI-1:0][R-1:0][1:0]              s0_gram_rd_data_avail;

  logic [QPSI-1:0][R-1:0][1:0][MOD_Q_W-1:0] s1_gram_rd_data;
  logic [QPSI-1:0][R-1:0][1:0]              s1_gram_rd_data_avail;

  logic [GRAM_NB-1:0][QPSI-1:0][R-1:0][1:0][MOD_Q_W-1:0] s0_gram_feed_rd_data_masked;

  always_comb
    for (int t=0; t<GRAM_NB; t=t+1)
      for (int p=0; p<QPSI; p=p+1)
        for (int r=0; r<R; r=r+1)
          for (int i=0; i<2; i=i+1)
            s0_gram_feed_rd_data_masked[t][p][r][i] = s0_gram_feed_rd_data[t][p][r][i] & {MOD_Q_W{s0_gram_feed_rd_data_avail[t][p][r][i]}};

  always_comb begin
    s0_gram_rd_data       = '0;
    s0_gram_rd_data_avail = '0;
    for (int t=0; t<GRAM_NB; t=t+1) begin
      s0_gram_rd_data       = s0_gram_rd_data       | s0_gram_feed_rd_data_masked[t];
      s0_gram_rd_data_avail = s0_gram_rd_data_avail | s0_gram_feed_rd_data_avail[t];
    end
  end

  always_ff @(posedge clk)
    if (!s_rst_n) s1_gram_rd_data_avail <= '0;
    else          s1_gram_rd_data_avail <= s0_gram_rd_data_avail;

  // Keep data stable for the chunk process
  always_ff @(posedge clk)
      for (int p=0; p<QPSI; p=p+1)
        for (int r=0; r<R; r=r+1)
          for (int i=0; i<2; i=i+1)
            s1_gram_rd_data[p][r][i] <= s0_gram_rd_data_avail[p][r][i] ? s0_gram_rd_data[p][r][i] : s1_gram_rd_data[p][r][i];

  //== Permutation lvl0 : Compute permutation mask
  logic [N_W-1:0]            s0_coef_idx0; // index in natural order
  logic [N_W-1:0]            s0_coef_id0; // reverse order
  logic [LWE_COEF_W:0]       s0_coef_rot_id0; // reverse order
  logic                      s0_mask_null;

  assign s0_coef_idx0    = {s0_rcmd.stg_iter,{R_SZ+PSI_SZ{1'b0}}};
  assign s0_coef_id0     = rev_order_n(s0_coef_idx0);
  assign s0_coef_rot_id0 = s0_coef_id0 + s0_rcmd.rot_factor;

  // Permutation vector
  logic [PERM_W-1:0] s0_perm_select;
  pep_mmacc_common_permutation_vector
  #(
    .PERM_LVL_NB  (PERM_LVL_NB), // Total number of permutation levels
    .PERM_LVL     (PERM_LVL_NB-1), // Value from 0 to PERM_LVL_NB-1
    .N_SZ         (N_SZ)
  ) s0_pep_mmacc_common_permutation_vector (
    .rot_factor (s0_coef_rot_id0[LWE_COEF_W-1:0]),
    .perm_select(s0_perm_select)
  );

  // Only the body part of the GLWE was loaded. Set the mask part to 0
  // when processing the first iteration of the CT.
  assign s0_mask_null = s0_rcmd.map_elt.first & (s0_rcmd.poly_id < GLWE_K);

// pragma translate_off
  logic [1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0] _gram_feed_rd_data_avail;
  logic [1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0] _s0_gram_feed_rd_data_avail;

  always_comb
    for (int g=0; g<GRAM_NB; g=g+1)
      for (int p=0; p<QPSI; p=p+1)
          for (int r=0; r<R; r=r+1)
            for (int i=0; i<2; i=i+1) begin
              _gram_feed_rd_data_avail[i][g][p][r]    = gram_feed_rd_data_avail[g][p][r][i];
              _s0_gram_feed_rd_data_avail[i][g][p][r] = s0_gram_feed_rd_data_avail[g][p][r][i];
            end

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // Do nothing
    end
    else begin
      for (int i=0; i<2; i=i+1) begin
        assert(($countones(_gram_feed_rd_data_avail[i]) == QPSI*R) || (_gram_feed_rd_data_avail[i]=='0))
        else begin
          $fatal(1,"%t > ERROR: _gram_feed_rd_data_avail[%0d] is incoherent!", $time,i);
        end
        for (int t=0; t<GRAM_NB; t=t+1) begin
          assert(_gram_feed_rd_data_avail[i][t] == '0 || _gram_feed_rd_data_avail[i][t] == '1)
          else begin
            $fatal(1,"%t > ERROR: _gram_feed_rd_data_avail[%0d][%0d] is incoherent!", $time,i,t);
          end
        end
      end // for
      if (s0_avail) begin
        assert(_s0_gram_feed_rd_data_avail[0] != '0)
        else begin
          $fatal(1,"%t > ERROR: gram_feed_rd_data and feed shift-register are not synchronized at s0!", $time);
        end
      end
    end
// pragma translate_on

//=================================================================================================
// S1
//=================================================================================================
  //== Perm lvl PERM_LVL_NB-1
  logic                      s1_avail;
  req_cmd_t                  s1_rcmd;
  logic [PERM_W-1:0]         s1_perm_select;
  logic [LWE_COEF_W:0]       s1_coef_rot_id0;
  /*(* dont_touch = "yes" *)*/ logic [QPSI-1:0][R-1:0]     s1_mask_null_ext;

  always_ff @(posedge clk)
    if (!s_rst_n) s1_avail <= 1'b0;
    else          s1_avail <= s0_avail;

  // Keep these signals stable for the chunk process
  always_ff @(posedge clk) begin
    s1_rcmd          <= s0_avail ? s0_rcmd         : s1_rcmd       ;
    s1_perm_select   <= s0_avail ? s0_perm_select  : s1_perm_select;
    s1_coef_rot_id0  <= s0_avail ? s0_coef_rot_id0 : s1_coef_rot_id0;
    s1_mask_null_ext <= s0_avail ? {QPSI*R{s0_mask_null}} : s1_mask_null_ext;
  end

  logic [QPSI*R-1:0][MOD_Q_W-1:0] s1_perm_data;
  logic [QPSI*R-1:0][MOD_Q_W-1:0] s1_mask_data_0;
  logic [QPSI-1:0][R-1:0]         s1_data_avail;

  // Only the body part of the GLWE was loaded. Set the mask part to 0
  // when processing the first iteration of the CT.
  always_comb
    for (int p=0; p<QPSI; p=p+1)
      for (int r=0; r<R; r=r+1) begin
        s1_mask_data_0[p*R+r] =  s1_mask_null_ext[p][r] ? '0 : s1_gram_rd_data[p][r][0];
      end

  // Permutation level PERM_LVL_NB-1.
  // Permute coefficients that are at position 2i <-> 2i+1 according to perm_select[i]
  always_comb
    for (int i=0; i<R*QPSI; i=i+2) begin
      s1_perm_data[i]   = s1_perm_select[(PERM_SEL_OFS + i)/2] ? s1_mask_data_0[i+1] : s1_mask_data_0[i];
      s1_perm_data[i+1] = s1_perm_select[(PERM_SEL_OFS + i)/2] ? s1_mask_data_0[i]   : s1_mask_data_0[i+1];
    end

  always_comb
    for (int p=0; p<QPSI; p=p+1)
      for (int r=0; r<R; r=r+1) begin
        s1_data_avail[p][r] = s1_gram_rd_data_avail[p][r][0];
      end

  // Permutation vector for next level
  logic [PERM_W/2-1:0] s1_perm_select_next;
  pep_mmacc_common_permutation_vector
  #(
    .PERM_LVL_NB  (PERM_LVL_NB), // Total number of permutation levels
    .PERM_LVL     (PERM_LVL_NB-2), // from 0 to PERM_LVL_NB-1
    .N_SZ         (N_SZ)
  ) s1_pep_mmacc_common_permutation_vector (
    .rot_factor (s1_coef_rot_id0[LWE_COEF_W-1:0]),
    .perm_select(s1_perm_select_next)
  );

//=================================================================================================
// S2
//=================================================================================================
  // Permutation
  //
  // Note : to ease the writing, a regular structure is used.
  // Some stages of the bus are not used.
  // All this will be removed by the synthesizer.
  //
  // Here it remains PERM_LVL_NB-1 levels of permutations.
  // If PERM_LVL_NB-1 is odd, we start with a single permutation.
  // Then permutations are done 2 levels at a time.
  //
  logic [PERM_LVL_NB-1:2][QPSI*R-1:0][MOD_Q_W-1:0] s2_perm_data;
  logic [QPSI-1:0][R-1:0]                          s2_data_avail;
  req_cmd_t                                        s2_rcmd;
  logic [PERM_W/2-1:0]                             s2_perm_select;
  logic [LWE_COEF_W:0]                             s2_coef_rot_id0;

  logic [PERM_LVL_NB-1:2][QPSI*R-1:0][MOD_Q_W-1:0] s2_l_perm_data;
  logic [PERM_LVL_NB-1:2][QPSI-1:0][R-1:0]         s2_l_data_avail;
  req_cmd_t [PERM_LVL_NB-1:2]                      s2_l_rcmd;
  logic [PERM_LVL_NB-1:1][PERM_W-1:0]              s2_l_perm_select;
  logic [PERM_LVL_NB-1:2][LWE_COEF_W:0]            s2_l_coef_rot_id0;

  always_ff @(posedge clk)
    if (!s_rst_n) s2_data_avail <= '0;
    else          s2_data_avail <= s1_data_avail;

  always_ff @(posedge clk) begin
    s2_perm_data    <= s1_perm_data;
    s2_rcmd         <= s1_rcmd;
    s2_perm_select  <= s1_perm_select_next;
    s2_coef_rot_id0 <= s1_coef_rot_id0;
  end

  // Each level input/output
  assign s2_l_perm_data[PERM_LVL_NB-1]      = s2_perm_data;
  assign s2_l_perm_select[PERM_LVL_NB-1]    = s2_perm_select;
  assign s2_l_data_avail[PERM_LVL_NB-1]     = s2_data_avail;
  assign s2_l_rcmd[PERM_LVL_NB-1]           = s2_rcmd;
  assign s2_l_coef_rot_id0[PERM_LVL_NB-1]   = s2_coef_rot_id0;

  generate
    if (PERM_LVL_NB_L % 2 == 0) begin : gen_perm_lvl_penult
      // Once the first level is processed, it remains an odd number of permutation levels.
      // Do 1 level here.
      localparam int PERM_LVL     = PERM_LVL_NB - 2;
      localparam int PERM_NB      = 2**PERM_LVL;
      localparam int PERM_NB_NEXT = PERM_NB/2;
      localparam int ELT_NB       = 2**(PERM_LVL_NB-1 - PERM_LVL); // Number of elements to be permuted together

      // Do permutation on 2*ELT_NB <-> 2*ELT_NB + ELT_NB
      logic [QPSI*R-1:0][MOD_Q_W-1:0] s2_perm_data_tmp;
      logic [QPSI*R-1:0][MOD_Q_W-1:0] s2_perm_data_tmpD;
      always_comb
        for (int i=0; i<R*QPSI; i=i+2*ELT_NB) begin
          s2_perm_data_tmpD[i+:ELT_NB]        = s2_l_perm_select[PERM_LVL+1][(PERM_SEL_OFS+i)/(2*ELT_NB)] ? s2_l_perm_data[PERM_LVL+1][i+ELT_NB+:ELT_NB]
                                                                                           : s2_l_perm_data[PERM_LVL+1][i+:ELT_NB];
          s2_perm_data_tmpD[i+ELT_NB+:ELT_NB] = s2_l_perm_select[PERM_LVL+1][(PERM_SEL_OFS+i)/(2*ELT_NB)] ? s2_l_perm_data[PERM_LVL+1][i+:ELT_NB]
                                                                                           : s2_l_perm_data[PERM_LVL+1][i+ELT_NB+:ELT_NB];
        end

      // Register for next level
      logic     [QPSI-1:0][R-1:0]       s2_data_avail_tmp;
      req_cmd_t                         s2_rcmd_tmp;
      logic     [LWE_COEF_W:0]          s2_coef_rot_id0_tmp;

      always_ff @(posedge clk) begin
        s2_perm_data_tmp     <= s2_perm_data_tmpD;
        s2_rcmd_tmp          <= s2_l_rcmd[PERM_LVL+1];
        s2_coef_rot_id0_tmp  <= s2_l_coef_rot_id0[PERM_LVL+1];
      end

      always_ff @(posedge clk)
        if (!s_rst_n) s2_data_avail_tmp <= '0;
        else          s2_data_avail_tmp <= s2_l_data_avail[PERM_LVL+1];


      assign s2_l_perm_data[PERM_LVL]    = s2_perm_data_tmp;
      assign s2_l_rcmd[PERM_LVL]         = s2_rcmd_tmp;
      assign s2_l_coef_rot_id0[PERM_LVL] = s2_coef_rot_id0_tmp;
      assign s2_l_data_avail[PERM_LVL]   = s2_data_avail_tmp;

      // Permutation vector for next level
      // During next steps, 2 levels are processed at the same time.
      logic [PERM_NB_NEXT-1:0]   s2_perm_select_next;
      logic [PERM_NB_NEXT-1:0]   s2_perm_select_nextD;
      logic [PERM_NB_NEXT/2-1:0] s2_perm_select_next2;
      logic [PERM_NB_NEXT/2-1:0] s2_perm_select_next2D;

      assign s2_l_perm_select[PERM_LVL]   = s2_perm_select_next; // extend with 0s
      assign s2_l_perm_select[PERM_LVL-1] = s2_perm_select_next2; // extend with 0s

      always_ff @(posedge clk) begin
        s2_perm_select_next  <= s2_perm_select_nextD;
        s2_perm_select_next2 <= s2_perm_select_next2D;
      end

      pep_mmacc_common_permutation_vector
      #(
        .PERM_LVL_NB  (PERM_LVL_NB), // Total number of permutation levels
        .PERM_LVL     (PERM_LVL-1), // from 0 to PERM_LVL_NB-1
        .N_SZ         (N_SZ)
      ) s2_pep_mmacc_common_permutation_vector (
        .rot_factor (s2_l_coef_rot_id0[PERM_LVL+1][LWE_COEF_W-1:0]),
        .perm_select(s2_perm_select_nextD)
      );

      pep_mmacc_common_permutation_vector
      #(
        .PERM_LVL_NB  (PERM_LVL_NB), // Total number of permutation levels
        .PERM_LVL     (PERM_LVL-2), // from 0 to PERM_LVL_NB-1
        .N_SZ         (N_SZ)
      ) s2_pep_mmacc_common_permutation_vector2 (
        .rot_factor (s2_l_coef_rot_id0[PERM_LVL+1][LWE_COEF_W-1:0]),
        .perm_select(s2_perm_select_next2D)
      );
    end // if gen_perm_lvl_penult
    else begin : gen_no_perm_lvl_penult
      // Prepare the 2nd selection for the next stages
      localparam int PERM_LVL     = PERM_LVL_NB - 2;
      localparam int PERM_NB      = 2**PERM_LVL;
      localparam int PERM_NB_NEXT = PERM_NB/2;

      logic [PERM_NB_NEXT-1:0] s2_perm_select_next2;
      logic [PERM_NB_NEXT-1:0] s2_perm_select_next2D;

      assign s2_l_perm_select[PERM_LVL] = s2_perm_select_next2; // extend with 0s

      always_ff @(posedge clk)
        s2_perm_select_next2 <= s2_perm_select_next2D;

      pep_mmacc_common_permutation_vector
      #(
        .PERM_LVL_NB  (PERM_LVL_NB), // Total number of permutation levels
        .PERM_LVL     (PERM_LVL-1), // from 0 to PERM_LVL_NB-1
        .N_SZ         (N_SZ)
      ) s2_pep_mmacc_common_permutation_vector2 (
        .rot_factor (s1_coef_rot_id0[LWE_COEF_W-1:0]), // Take this, since it is for the 1rst round
        .perm_select(s2_perm_select_next2D)
      );
    end

    // Remaining levels : there is an even number of levels. Do them 2 at a time.
    // Do not process the last 2, since they are done elsewhere.
    for (genvar gen_l=((PERM_LVL_NB+1)/2)*2 - 3; gen_l>2; gen_l=gen_l-2) begin : gen_perm_loop
      localparam int PERM_NB      = 2**gen_l;
      localparam int PERM_NB_NEXT = PERM_NB/4;
      localparam int ELT_NB  = 2**(PERM_LVL_NB-1 - gen_l); // Number of elements to be permuted together

      // Do permutation on 2*ELT_NB <-> 2*ELT_NB + ELT_NB
      logic [QPSI*R-1:0][MOD_Q_W-1:0] s2_perm_data_tmp;
      logic [QPSI*R-1:0][MOD_Q_W-1:0] s2_perm_data_tmpD_0;
      logic [QPSI*R-1:0][MOD_Q_W-1:0] s2_perm_data_tmpD;
      always_comb
        for (int i=0; i<R*QPSI; i=i+2*ELT_NB) begin
          s2_perm_data_tmpD_0[i+:ELT_NB]        = s2_l_perm_select[gen_l+1][(PERM_SEL_OFS+i)/(2*ELT_NB)] ? s2_l_perm_data[gen_l+1][i+ELT_NB+:ELT_NB]
                                                                                          : s2_l_perm_data[gen_l+1][i+:ELT_NB];
          s2_perm_data_tmpD_0[i+ELT_NB+:ELT_NB] = s2_l_perm_select[gen_l+1][(PERM_SEL_OFS+i)/(2*ELT_NB)] ? s2_l_perm_data[gen_l+1][i+:ELT_NB]
                                                                                          : s2_l_perm_data[gen_l+1][i+ELT_NB+:ELT_NB];
        end

      // Do permutation on 2*2*ELT_NB <-> 2*2*ELT_NB + 2*ELT_NB
      always_comb
        for (int i=0; i<R*QPSI; i=i+2*2*ELT_NB) begin
          s2_perm_data_tmpD[i+:2*ELT_NB]          = s2_l_perm_select[gen_l][(PERM_SEL_OFS+i)/(2*2*ELT_NB)] ? s2_perm_data_tmpD_0[i+2*ELT_NB+:2*ELT_NB]
                                                                                            : s2_perm_data_tmpD_0[i+:2*ELT_NB];
          s2_perm_data_tmpD[i+2*ELT_NB+:2*ELT_NB] = s2_l_perm_select[gen_l][(PERM_SEL_OFS+i)/(2*2*ELT_NB)] ? s2_perm_data_tmpD_0[i+:2*ELT_NB]
                                                                                            : s2_perm_data_tmpD_0[i+2*ELT_NB+:2*ELT_NB];
        end

      // Register for next level
      logic     [QPSI-1:0][R-1:0]       s2_data_avail_tmp;
      req_cmd_t                         s2_rcmd_tmp;
      logic     [LWE_COEF_W:0]          s2_coef_rot_id0_tmp;

      always_ff @(posedge clk) begin
        s2_perm_data_tmp     <= s2_perm_data_tmpD;
        s2_rcmd_tmp          <= s2_l_rcmd[gen_l+1];
        s2_coef_rot_id0_tmp  <= s2_l_coef_rot_id0[gen_l+1];
      end

      always_ff @(posedge clk)
        if (!s_rst_n) s2_data_avail_tmp <= '0;
        else          s2_data_avail_tmp <= s2_l_data_avail[gen_l+1];


      assign s2_l_perm_data[gen_l-1]    = s2_perm_data_tmp;
      assign s2_l_rcmd[gen_l-1]         = s2_rcmd_tmp;
      assign s2_l_coef_rot_id0[gen_l-1] = s2_coef_rot_id0_tmp;
      assign s2_l_data_avail[gen_l-1]   = s2_data_avail_tmp;

      // Permutation vector for next level
      logic [PERM_NB_NEXT-1:0]   s2_perm_select_next;
      logic [PERM_NB_NEXT-1:0]   s2_perm_select_nextD;
      logic [PERM_NB_NEXT/2-1:0] s2_perm_select_next2;
      logic [PERM_NB_NEXT/2-1:0] s2_perm_select_next2D;

      assign s2_l_perm_select[gen_l-1] = s2_perm_select_next; // extend with 0s
      assign s2_l_perm_select[gen_l-2] = s2_perm_select_next2; // extend with 0s

      always_ff @(posedge clk) begin
        s2_perm_select_next  <= s2_perm_select_nextD;
        s2_perm_select_next2 <= s2_perm_select_next2D;
      end

      pep_mmacc_common_permutation_vector
      #(
        .PERM_LVL_NB  (PERM_LVL_NB), // Total number of permutation levels
        .PERM_LVL     (gen_l-2), // from 0 to PERM_LVL_NB-1
        .N_SZ         (N_SZ)
      ) s2_pep_mmacc_common_permutation_vector (
        .rot_factor (s2_l_coef_rot_id0[gen_l+1][LWE_COEF_W-1:0]),
        .perm_select(s2_perm_select_nextD)
      );
      pep_mmacc_common_permutation_vector
      #(
        .PERM_LVL_NB  (PERM_LVL_NB), // Total number of permutation levels
        .PERM_LVL     (gen_l-3), // from 0 to PERM_LVL_NB-1
        .N_SZ         (N_SZ)
      ) s2_pep_mmacc_common_permutation_vector2 (
        .rot_factor (s2_l_coef_rot_id0[gen_l+1][LWE_COEF_W-1:0]),
        .perm_select(s2_perm_select_next2D)
      );

    end // for gen_l : gen_perm_loop
  endgenerate

//=================================================================================================
// ss1
//=================================================================================================
// Compute mask_null
  logic ss1_mask_null;

  // Only the body part of the GLWE was loaded. Set the mask part to 0
  // when processing the first iteration of the CT.
  assign ss1_mask_null = ss1_rcmd.map_elt.first & (ss1_rcmd.poly_id < GLWE_K);

//=================================================================================================
// ss2
//=================================================================================================
// Not rotated data are available.
// Apply the null mask
  logic                      ss2_avail;
  /*(* dont_touch = "yes" *)*/ logic [PSI-1:0][R-1:0]     ss2_mask_null_ext;

  always_ff @(posedge clk)
    if (!s_rst_n) ss2_avail <= 1'b0;
    else          ss2_avail <= ss1_avail;

  always_ff @(posedge clk)
    ss2_mask_null_ext <= ss1_avail ? {PSI*R{ss1_mask_null}} : ss2_mask_null_ext;

  // Only the body part of the GLWE was loaded. Set the mask part to 0
  // when processing the first iteration of the CT.
  logic [QPSI*R-1:0][MOD_Q_W-1:0] ss2_mask_data_1;
  always_comb
    for (int p=0; p<QPSI; p=p+1)
      for (int r=0; r<R; r=r+1)
        ss2_mask_data_1[p*R+r] =  ss2_mask_null_ext[p][r] ? '0 : s1_gram_rd_data[p][r][1];

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // Do nothing
    end
    else begin
      if (ss1_avail) begin
        assert(_s0_gram_feed_rd_data_avail[1] != '0)
        else begin
          $fatal(1,"%t > ERROR: gram_feed_rd_data and feed shift-register are not synchronized at ss1_avail!", $time);
        end
      end

      assert(ss2_avail == s2_l_data_avail[2][0][0])
      else begin
        $fatal(1,"%t > ERROR: dat and rot paths are not synchronized!", $time);
      end
    end
// pragma translate_on

// ============================================================================================= --
// Output
// ============================================================================================= --
  assign out_data         = ss2_mask_data_1;
  assign out_rot_data     = s2_l_perm_data[2];
  assign out_perm_select  = s2_l_perm_select[2:1];
  assign out_coef_rot_id0 = s2_l_coef_rot_id0[2];
  assign out_data_avail   = s2_l_data_avail[2];
  assign out_rcmd         = s2_l_rcmd[2];

// pragma translate_off
  logic [QPSI-1:0][R-1:0] _s1_gram_rd_data_avail_1;

  always_comb
    for (int p=0; p<QPSI; p=p+1)
      for (int r=0; r<R; r=r+1)
        _s1_gram_rd_data_avail_1[p][r] = s1_gram_rd_data_avail[p][r][1];

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      assert (out_data_avail == _s1_gram_rd_data_avail_1)
      else begin
        $fatal(1,"%t > ERROR: rot path and data path are not synchronized.",$time);
      end
    end
// pragma translate_on

endmodule

