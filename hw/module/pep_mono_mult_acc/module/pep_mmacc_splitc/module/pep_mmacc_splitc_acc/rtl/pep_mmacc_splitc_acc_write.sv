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

module pep_mmacc_splitc_acc_write
  import common_definition_pkg::*;
  import param_tfhe_pkg::*;
  import ntt_core_common_param_pkg::*;
  import top_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import pep_mmacc_common_param_pkg::*;
#(
  parameter bit IN_PIPE = 1'b0 // Set to 1 for 2nd QPSI
)
(
  input  logic                                                     clk,        // clock
  input  logic                                                     s_rst_n,    // synchronous reset

  // GRAM arbiter
  input  logic [GRAM_NB-1:0]                                       garb_acc_wr_avail_1h,

  // Prepare GRAM access
  input  logic                                                     in_a0_do_read,
  input  logic [GLWE_RAM_ADD_W-1:0]                                in_a0_rd_add,
  input  logic [GRAM_ID_W-1:0]                                     in_a0_rd_grid,

  input  logic                                                     in_s0_mask_null,
  input  logic [PSI/4-1:0][R-1:0][MOD_Q_W-1:0]                     in_s1_ntt_acc_data,
  input  logic                                                     in_s1_avail,
  input  logic [GLWE_RAM_ADD_W-1:0]                                in_s1_add,
  input  logic [GRAM_ID_W-1:0]                                     in_s1_grid,

  // GRAM access
  output logic [GRAM_NB-1:0][PSI/4-1:0][R-1:0]                     acc_gram_rd_en,
  output logic [GRAM_NB-1:0][PSI/4-1:0][R-1:0][GLWE_RAM_ADD_W-1:0] acc_gram_rd_add,
  input  logic [GRAM_NB-1:0][PSI/4-1:0][R-1:0][MOD_Q_W-1:0]        gram_acc_rd_data,
  input  logic [GRAM_NB-1:0][PSI/4-1:0][R-1:0]                     gram_acc_rd_data_avail,

  output logic [GRAM_NB-1:0][PSI/4-1:0][R-1:0]                     acc_gram_wr_en,
  output logic [GRAM_NB-1:0][PSI/4-1:0][R-1:0][GLWE_RAM_ADD_W-1:0] acc_gram_wr_add,
  output logic [GRAM_NB-1:0][PSI/4-1:0][R-1:0][MOD_Q_W-1:0]        acc_gram_wr_data,

  // error
  output logic                                                     error // GRAM write access error

);

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int QPSI = PSI/4;

// ============================================================================================== --
// Input Pipe
// ============================================================================================== --
  logic [GRAM_NB-1:0] in_garb_acc_wr_avail_1h;

  always_ff @(posedge clk)
    if (!s_rst_n) in_garb_acc_wr_avail_1h <= '0;
    else          in_garb_acc_wr_avail_1h <= garb_acc_wr_avail_1h;

  logic [GRAM_NB-1:0]                   garb_wr_avail_1h;

  logic                                 a0_do_read;
  logic [GLWE_RAM_ADD_W-1:0]            a0_rd_add;
  logic [GRAM_ID_W-1:0]                 a0_rd_grid;

  logic                                 s0_mask_null;
  logic [QPSI-1:0][R-1:0][MOD_Q_W-1:0]  s1_ntt_acc_data;
  logic                                 s1_avail;
  logic [GLWE_RAM_ADD_W-1:0]            s1_add;
  logic [GRAM_ID_W-1:0]                 s1_grid;

  generate
    if (IN_PIPE) begin : gen_in_pipe
      always_ff @(posedge clk)
        if (!s_rst_n) begin
          garb_wr_avail_1h <= '0;
          a0_do_read       <= 1'b0;
          s1_avail         <= 1'b0;
        end
        else begin
          garb_wr_avail_1h <= in_garb_acc_wr_avail_1h;
          a0_do_read       <= in_a0_do_read;
          s1_avail         <= in_s1_avail;
        end

      always_ff @(posedge clk) begin
        a0_rd_add       <= in_a0_rd_add      ;
        a0_rd_grid      <= in_a0_rd_grid      ;
        s1_ntt_acc_data <= in_s1_ntt_acc_data;
        s1_add          <= in_s1_add         ;
        s1_grid         <= in_s1_grid         ;
        s0_mask_null    <= in_s0_mask_null   ;
      end
    end
    else begin : gen_no_in_pipe
      assign garb_wr_avail_1h= in_garb_acc_wr_avail_1h;
      assign a0_do_read      = in_a0_do_read;
      assign s1_avail        = in_s1_avail;

      assign a0_rd_add       = in_a0_rd_add      ;
      assign a0_rd_grid      = in_a0_rd_grid     ;
      assign s1_ntt_acc_data = in_s1_ntt_acc_data;
      assign s1_add          = in_s1_add         ;
      assign s1_grid         = in_s1_grid        ;
      assign s0_mask_null    = in_s0_mask_null   ;
    end
  endgenerate

// ============================================================================================== --
// A0
// ============================================================================================== --
//== Format to GRAM read request : -> R*PSI/4
  logic [QPSI-1:0][R-1:0]                     a1_rd_en;
  logic [QPSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0] a1_rd_add;
  logic [QPSI-1:0][R-1:0][GRAM_NB-1:0]        a1_rd_grid_1h;

  always_ff @(posedge clk)
    if (!s_rst_n)  a1_rd_en <= '0;
    else           a1_rd_en <= {QPSI*R{a0_do_read}};

  always_ff @(posedge clk) begin
    for (int p=0; p<QPSI; p=p+1) begin
      for (int r=0; r<R; r=r+1) begin
        a1_rd_add[p][r]     <= a0_rd_add;
        a1_rd_grid_1h[p][r] <= 1 << a0_rd_grid;
      end
    end
  end

//=================================================================================================
// A1
//=================================================================================================
// R*QPSI -> GRAM_NB
  logic [GRAM_NB-1:0][QPSI-1:0][R-1:0]                     a1_gram_rd_en;
  logic [GRAM_NB-1:0][QPSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0] a1_gram_rd_add;

  logic [GRAM_NB-1:0][QPSI-1:0][R-1:0]                     a2_gram_rd_en;
  logic [GRAM_NB-1:0][QPSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0] a2_gram_rd_add;

  always_comb
    for (int t=0; t<GRAM_NB; t=t+1) begin
      for (int p=0; p<QPSI; p=p+1) begin
        for (int r=0; r<R; r=r+1) begin
          a1_gram_rd_en[t][p][r] = a1_rd_en[p][r] & a1_rd_grid_1h[p][r][t];
        end
      end
    end

  assign a1_gram_rd_add = {GRAM_NB{a1_rd_add}};

  always_ff @(posedge clk)
    if (!s_rst_n) a2_gram_rd_en <= '0;
    else          a2_gram_rd_en <= a1_gram_rd_en;

  always_ff @(posedge clk)
    a2_gram_rd_add <= a1_gram_rd_add;

//=================================================================================================
// acc_gram
//=================================================================================================
  assign acc_gram_rd_en  = a2_gram_rd_en;
  assign acc_gram_rd_add = a2_gram_rd_add;

//=================================================================================================
// gram_acc pipe
//=================================================================================================
  logic [GRAM_NB-1:0][QPSI-1:0][R-1:0][MOD_Q_W-1:0] s0_gram_acc_rd_data;
  logic [GRAM_NB-1:0][QPSI-1:0][R-1:0]              s0_gram_acc_rd_data_avail;

  always_ff @(posedge clk)
    if (!s_rst_n) s0_gram_acc_rd_data_avail <= '0;
    else          s0_gram_acc_rd_data_avail <= gram_acc_rd_data_avail;

  always_ff @(posedge clk)
    s0_gram_acc_rd_data <= gram_acc_rd_data;

//=================================================================================================
// S0
//=================================================================================================
//== GRAM_NBxQPSIxR -> QPSIxR
  logic [QPSI-1:0][R-1:0][MOD_Q_W-1:0] s0_gram_rd_data;
  logic [QPSI-1:0][R-1:0][MOD_Q_W-1:0] s0_gram_rd_data_tmp;
  logic [QPSI-1:0][R-1:0]              s0_gram_rd_data_avail;

  logic [QPSI-1:0][R-1:0][MOD_Q_W-1:0] s1_gram_rd_data;

  logic [GRAM_NB-1:0][QPSI-1:0][R-1:0][MOD_Q_W-1:0] s0_gram_acc_rd_data_masked;

  always_comb
    for (int t=0; t<GRAM_NB; t=t+1)
      for (int p=0; p<QPSI; p=p+1)
        for (int r=0; r<R; r=r+1)
          s0_gram_acc_rd_data_masked[t][p][r] = s0_gram_acc_rd_data[t][p][r] & {MOD_Q_W{s0_gram_acc_rd_data_avail[t][p][r]}};

  always_comb begin
    s0_gram_rd_data_tmp   = '0;
    s0_gram_rd_data_avail = '0;
    for (int t=0; t<GRAM_NB; t=t+1) begin
      s0_gram_rd_data_tmp   = s0_gram_rd_data_tmp   | s0_gram_acc_rd_data_masked[t];
      s0_gram_rd_data_avail = s0_gram_rd_data_avail | s0_gram_acc_rd_data_avail[t];
    end
  end

  always_comb
    for (int p=0; p<QPSI; p=p+1)
      for (int r=0; r<R; r=r+1)
        s0_gram_rd_data[p][r] = s0_mask_null ? '0 : s0_gram_rd_data_tmp[p][r];

  always_ff @(posedge clk)
    s1_gram_rd_data <= s0_gram_rd_data;

// pragma translate_off
  logic [QPSI-1:0][R-1:0]              s1_gram_rd_data_avail;
  always_ff @(posedge clk)
    if (!s_rst_n) s1_gram_rd_data_avail <= '0;
    else          s1_gram_rd_data_avail <= s0_gram_rd_data_avail;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      if (s1_avail) begin
        assert(s1_gram_rd_data_avail == '1)
        else begin
          $fatal(1,"%t > ERROR: GRAM rdata not available when needed!", $time);
        end
      end
    end
// pragma translate_on

 //== data accumulation
  logic [QPSI-1:0][R-1:0][MOD_Q_W-1:0] s1_sum_data;
  always_comb
    for (int p=0; p<QPSI; p=p+1)
      for (int r=0; r<R; r=r+1)
        s1_sum_data[p][r] = s1_ntt_acc_data[p][r] + s1_gram_rd_data[p][r];

// GRAM write access error
  logic s1_gram_access_error;
  assign s1_gram_access_error = s1_avail & ~garb_wr_avail_1h[s1_grid];

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
    end
    else begin
      assert(!s1_gram_access_error)
      else begin
        $fatal(1,"%t > ERROR: GRAM write access error : access not granted when needed!",$time);
      end
    end
// pragma translate_on

  // To s2 pipe
  logic [GRAM_NB-1:0]  s1_grid_1h;
  assign s1_grid_1h = 1 << s1_grid;

//=================================================================================================
// s2
//=================================================================================================
// Write back to GRAM
// QPSIxR format
  /*(* dont_touch = "yes" *)*/logic [QPSI-1:0][R-1:0]                     s2_wr_en;
  /*(* dont_touch = "yes" *)*/logic [QPSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0] s2_wr_add;
  /*(* dont_touch = "yes" *)*/logic [QPSI-1:0][R-1:0][GRAM_NB-1:0]        s2_wr_grid_1h;
  logic [QPSI-1:0][R-1:0][MOD_Q_W-1:0]         s2_wr_data;

  always_ff @(posedge clk)
    if (!s_rst_n) s2_wr_en <= '0;
    else          s2_wr_en <= {QPSI*R{s1_avail}};

  always_ff @(posedge clk) begin
    s2_wr_data    <= s1_sum_data;
    s2_wr_add     <= {QPSI*R{s1_add}};
    s2_wr_grid_1h <= {QPSI*R{s1_grid_1h}};
  end

//=================================================================================================
// s3
//=================================================================================================
// GRAM_NB format
  logic [GRAM_NB-1:0][QPSI-1:0][R-1:0]                     s2_gram_wr_en;
  logic [GRAM_NB-1:0][QPSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0] s2_gram_wr_add;
  logic [GRAM_NB-1:0][QPSI-1:0][R-1:0][MOD_Q_W-1:0]         s2_gram_wr_data;

  /*(* dont_touch = "yes" *)*/logic [GRAM_NB-1:0][QPSI-1:0][R-1:0]                     s3_gram_wr_en;
  /*(* dont_touch = "yes" *)*/logic [GRAM_NB-1:0][QPSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0] s3_gram_wr_add;
  logic [GRAM_NB-1:0][QPSI-1:0][R-1:0][MOD_Q_W-1:0]         s3_gram_wr_data;

  always_comb
    for (int t=0; t<GRAM_NB; t=t+1)
      for (int p=0; p<QPSI; p=p+1)
        for (int r=0; r<R; r=r+1)
          s2_gram_wr_en[t][p][r] = s2_wr_en[p][r] & s2_wr_grid_1h[p][r][t];

  assign s2_gram_wr_add  = {GRAM_NB{s2_wr_add}};
  assign s2_gram_wr_data = {GRAM_NB{s2_wr_data}};

  always_ff @(posedge clk)
    if (!s_rst_n) s3_gram_wr_en <= '0;
    else          s3_gram_wr_en <= s2_gram_wr_en;

  always_ff @(posedge clk) begin
    s3_gram_wr_add  <= s2_gram_wr_add;
    s3_gram_wr_data <= s2_gram_wr_data;
  end

//=================================================================================================
// GRAM write output
//=================================================================================================
  assign acc_gram_wr_en   = s3_gram_wr_en;
  assign acc_gram_wr_add  = s3_gram_wr_add;
  assign acc_gram_wr_data = s3_gram_wr_data;

//=================================================================================================
// error
//=================================================================================================
  logic errorD;

  assign errorD = s1_gram_access_error;

  always_ff @(posedge clk)
    if (!s_rst_n) error <= '0;
    else          error <= errorD;

endmodule
