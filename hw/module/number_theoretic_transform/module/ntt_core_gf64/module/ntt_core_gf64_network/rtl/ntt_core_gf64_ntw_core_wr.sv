// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the network between the radix columns.
// This sub-module deals with the write part.
// ==============================================================================================

`include "ntt_core_gf64_ntw_macro_inc.sv"

module ntt_core_gf64_ntw_core_wr
  import pep_common_param_pkg::*;
  import param_tfhe_pkg::*;
  import ntt_core_common_param_pkg::*;
  import ntt_core_gf64_common_param_pkg::*;
#(
  parameter int    RDX_CUT_ID      = 1, // increasing numbering for FWD, decreasing for BWD
                                        // FWD : 1 means ngc
                                        // BWD : 0 means ngc
                                        // Column that precedes the network.
  parameter bit    BWD             = 1'b0,
  parameter bit    IN_PIPE         = 1'b1, // Recommended
  parameter int    OP_W            = 66,
  parameter int    TOKEN_W         = 2 // Store up to 2**TOKEN_W working block
)
(
  input  logic                             clk,        // clock
  input  logic                             s_rst_n,    // synchronous reset


  input  logic [PSI*R-1:0][OP_W-1:0]       in_data,
  input  logic [PSI*R-1:0]                 in_avail,
  input  logic                             in_sob,
  input  logic                             in_eob,
  input  logic                             in_sol,
  input  logic                             in_eol,
  input  logic                             in_sos,
  input  logic                             in_eos,
  input  logic [BPBS_ID_W-1:0]             in_pbs_id,

  // RAM
  output logic [PSI*R-1:0][OP_W-1:0]       ram_wr_data,
  output logic [PSI*R-1:0]                 ram_wr_avail,
  output logic [PSI*R-1:0][STG_ITER_W-1:0] ram_wr_add, // only ITER_W bits are used.
  output logic [INTL_L_W-1:0]              ram_wr_intl_idx,
  output logic [TOKEN_W-1:0]               ram_wr_token,

  // Token
  input  logic                             token_release,

  // Command FIFO
  output logic                             cmd_fifo_avail,
  output logic [BPBS_ID_W-1:0]             cmd_fifo_pbs_id,
  output logic [INTL_L_W-1:0]              cmd_fifo_intl_idx,
  output logic                             cmd_fifo_eob
);

// ============================================================================================== --
// localparam
// ============================================================================================== --
  `NTT_CORE_GF64_NTW_LOCALPARAM(RDX_CUT_ID,BWD,R,PSI)

  localparam int TOKEN_NB    = 2**TOKEN_W;

      // Should be a power of 2
  localparam int ROT_C       = C <= 32 ? C/2 :
                               C <= 256 ? 16 :
                               C <= 1024 ? 32  : 64;
  localparam int ROT_SUBW_NB = C / ROT_C; // Should be a power of 2

  generate
    if (N_L <= C) begin : __UNSUPPORTED_N_L
      $fatal(1,"> ERROR: ntt_core_gf64_ntw_core should be used with N_L (%0d) greater than R*PSI (%0d).", N_L, C);
    end
    if (ROT_C < 2) begin : __UNSUPPORTED_C
      $fatal(1,"> ERROR: Support only C (%0d) > 2, for the ntt gf64 network rotation", C);
    end
    if (ROT_SUBW_NB > 32) begin : __WARNING_ROT_SIZE
      initial begin
        $display("> WARNING: NTT GF64 network rotation 2nd part is done with %0d sub-words, which may be not optimal.",ROT_SUBW_NB);
      end
    end
  endgenerate

  // =========================================================================================== --
  // type
  // =========================================================================================== --
  typedef struct packed {
    logic                 sob;
    logic                 eob;
    logic                 sol;
    logic                 eol;
    logic                 sos;
    logic                 eos;
    logic [BPBS_ID_W-1:0] pbs_id;
    logic [INTL_L_W-1:0]  intl_idx;
    logic                 end_of_wb;
    logic                 last_iter;
  } ctrl_t;

  localparam CTRL_W = $bits(ctrl_t);

  typedef struct packed {
    logic [ITER_W-1:0] add;
    logic [OP_W-1:0]   data;
  } elt_t;

  localparam ELT_W = $bits(elt_t);

  // =========================================================================================== --
  // Input pipe
  // =========================================================================================== --
  logic [C-1:0][OP_W-1:0] s0_data;
  ctrl_t                  s0_ctrl;
  logic [C-1:0]           s0_avail;

  generate
    if (IN_PIPE) begin : gen_in_pipe
      always_ff @(posedge clk)
        if (!s_rst_n) s0_avail <= '0;
        else          s0_avail <= in_avail;

      always_ff @(posedge clk) begin
        s0_data        <= in_data;
        s0_ctrl.sob    <= in_sob;
        s0_ctrl.eob    <= in_eob;
        s0_ctrl.sol    <= in_sol;
        s0_ctrl.eol    <= in_eol;
        s0_ctrl.sos    <= in_sos;
        s0_ctrl.eos    <= in_eos;
        s0_ctrl.pbs_id <= in_pbs_id;
      end
    end else begin : gen_no_in_pipe
      assign s0_data        = in_data;
      assign s0_ctrl.sob    = in_sob;
      assign s0_ctrl.eob    = in_eob;
      assign s0_ctrl.sol    = in_sol;
      assign s0_ctrl.eol    = in_eol;
      assign s0_ctrl.sos    = in_sos;
      assign s0_ctrl.eos    = in_eos;
      assign s0_ctrl.pbs_id = in_pbs_id;
      assign s0_avail       = in_avail;
    end
  endgenerate

  // =========================================================================================== --
  // s0
  // =========================================================================================== --
  // ------------------------------------------------------------------------------------------- --
  // Counters
  // ------------------------------------------------------------------------------------------- --
  // Keep track of :
  //   wb       : current working block
  //   iter     : current iteration inside the working block
  //   intl_idx : current level index

  logic [INTL_L_W-1:0]   s0_intl_idx;
  logic [WB_W-1:0]       s0_wb; // working block
  logic [ITER_W-1:0]     s0_iter;

  logic [INTL_L_W-1:0]   s0_intl_idxD;
  logic [WB_W-1:0]       s0_wbD; // working block
  logic [ITER_W-1:0]     s0_iterD;

  logic                  s0_last_intl_idx;
  logic                  s0_last_wb;
  logic                  s0_last_iter;

  logic                  s0_end_of_wb;

  assign s0_last_intl_idx = s0_ctrl.eol;
  assign s0_last_iter     = s0_iter == ITER_NB-1;
  assign s0_last_wb       = s0_wb == WB_NB-1;

  assign s0_intl_idxD     = s0_avail[0] ? s0_last_intl_idx ? '0 : s0_intl_idx + 1 : s0_intl_idx;
  assign s0_iterD         = (s0_avail[0] && s0_last_intl_idx) ? s0_last_iter ? '0 : s0_iter + 1 : s0_iter;
  assign s0_wbD           = (s0_avail[0] && s0_last_intl_idx && s0_last_iter) ? s0_last_wb ? '0 : s0_wb + 1 : s0_wb;

  assign s0_end_of_wb     = s0_last_intl_idx & s0_last_iter;

  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      s0_wb       <= '0;
      s0_iter     <= '0;
      s0_intl_idx <= '0;
    end else begin
      s0_wb       <= s0_wbD;
      s0_iter     <= s0_iterD;
      s0_intl_idx <= s0_intl_idxD;
    end
  end

  // ------------------------------------------------------------------------------------------- --
  // Interleave / dispatch
  // ------------------------------------------------------------------------------------------- --
  // Note that the following is hardwired.
  logic [C-1:0][OP_W-1:0] s0_intl_data;
  logic [C-1:0][OP_W-1:0] s0_disp_data;
  generate
    if (DO_INTERLEAVE) begin : gen_do_intl
      logic [C/L_NB-1:0][L_NB-1:0][OP_W-1:0] s0_data_a;
      logic [L_NB-1:0][C/L_NB-1:0][OP_W-1:0] s0_intl_data_a;

      assign s0_data_a    = s0_data;
      assign s0_intl_data = s0_intl_data_a;
      always_comb begin
        for (int j=0; j < L_NB; j = j+1)
          for (int i=0; i<C/L_NB; i=i+1)
            s0_intl_data_a[j][i] = s0_data_a[i][j];
      end
    end
    else begin : gen_no_do_intl
      assign s0_intl_data = s0_data;
    end
    if (DO_DISPATCH) begin : gen_do_disp
      logic [C/(DSP_STRIDE*CONS_NB)-1:0][DSP_STRIDE-1:0][CONS_NB-1:0][OP_W-1:0] s0_intl_data_a;
      logic [DSP_STRIDE-1:0][C/(DSP_STRIDE*CONS_NB)-1:0][CONS_NB-1:0][OP_W-1:0] s0_disp_data_a;

      assign s0_intl_data_a = s0_intl_data;
      assign s0_disp_data   = s0_disp_data_a;
      always_comb begin
        for (int i=0; i<C/(DSP_STRIDE*CONS_NB); i=i+1)
          for (int j=0; j < DSP_STRIDE; j = j+1)
            for (int k=0; k<CONS_NB; k=k+1)
              s0_disp_data_a[j][i][k] = s0_intl_data_a[i][j][k];
      end
    end
    else begin : gen_no_do_disp
      assign s0_disp_data = s0_intl_data;
    end
  endgenerate

  // ------------------------------------------------------------------------------------------- --
  // rotation factor
  // ------------------------------------------------------------------------------------------- --
  // The rotation is the coefficient position at the input a L radix module.
  logic [POS_W-1:0] s0_pos;
  logic [POS_W-1:0] s0_posD;

  always_ff @(posedge clk)
    if (!s_rst_n)  s0_pos <= '0;
    else           s0_pos <= s0_posD;

  generate
    if (C > L_NB) begin : gen_pos_c_gt_rl
      localparam int POS_INC = C / L_NB;

      assign s0_posD = (s0_avail && s0_last_intl_idx) ? s0_pos + POS_INC : s0_pos; // power of 2 numbers. Should wrap nicely.
    end
    else begin : gen_pos_no_c_gt_rl
      localparam int ITER_PER_POS   = L_NB / C;
      localparam int ITER_PER_POS_W = $clog2(ITER_PER_POS) == 0 ? 1 : $clog2(ITER_PER_POS);

      logic [ITER_PER_POS_W-1:0] s0_pos_iter;
      logic [ITER_PER_POS_W-1:0] s0_pos_iterD;
      logic                      s0_last_pos_iter;

      assign s0_last_pos_iter = s0_pos_iter == ITER_PER_POS-1;
      assign s0_pos_iterD     = (s0_avail && s0_last_intl_idx) ? s0_last_pos_iter ? '0 : s0_pos_iter + 1 : s0_pos_iter;

      assign s0_posD          = (s0_avail && s0_last_intl_idx && s0_last_pos_iter) ? s0_pos + 1 : s0_pos; // power of 2. Should wrap nicely

      always_ff @(posedge clk)
        if (!s_rst_n) s0_pos_iter <= '0;
        else          s0_pos_iter <= s0_pos_iterD;
    end
  endgenerate

  // ------------------------------------------------------------------------------------------- --
  // Addresses
  // ------------------------------------------------------------------------------------------- --
  logic [C-1:0][ITER_W-1:0] s0_add;
  logic [ITER_W-1:0]        s0_add_ofs_0;
  logic [ITER_W-1:0]        s0_add_ofs_1;

  generate
    if (POS_ITER_Z == 0) begin : gen_pos_iter_nb_eq_1
      assign s0_add_ofs_0 = '0;
    end
    else begin : gen_no_pos_iter_nb_eq_1
      assign s0_add_ofs_0 = s0_iter[POS_ITER_Z-1:0] * (TRG_RD_ITER_NB * RD_ITER_NB); // multiply with a power of 2
    end
  endgenerate

  assign s0_add_ofs_1 = s0_iter >> (POS_ITER_Z + COMPLETE_RD_ITER_Z);

  always_comb
    for (int x=0; x<SET_NB; x=x+1)
      for (int y=0; y<TRG_RDX_NB/SET_NB; y=y+1)
        for (int z=0; z<CONS_NB; z=z+1) begin
          s0_add[x*TRG_RDX_NB/SET_NB*CONS_NB+y*CONS_NB+z] = y*RD_ITER_NB + s0_add_ofs_0 + s0_add_ofs_1;// Truncate to stay in [0,ITER_NB[ (this latter is a power of 2)
        end

  // =========================================================================================== --
  // s1
  // =========================================================================================== --
  logic [C-1:0][OP_W-1:0]   s1_disp_data;
  logic [C-1:0]             s1_avail;
  logic [POS_W-1:0]         s1_pos;
  ctrl_t                    s1_ctrl;
  logic [C-1:0][ITER_W-1:0] s1_add;

  ctrl_t                        s0_ctrl_tmp;
  always_comb begin
    s0_ctrl_tmp           = s0_ctrl;
    s0_ctrl_tmp.intl_idx  = s0_intl_idx;
    s0_ctrl_tmp.end_of_wb = s0_end_of_wb;
    s0_ctrl_tmp.last_iter = s0_last_iter;
  end

  always_ff @(posedge clk)
    if (!s_rst_n) s1_avail <= '0;
    else          s1_avail <= s0_avail;

  always_ff @(posedge clk) begin
    s1_disp_data <= s0_disp_data;
    s1_pos       <= s0_pos;
    s1_ctrl      <= s0_ctrl_tmp;
    s1_add       <= s0_add;
  end

  // ------------------------------------------------------------------------------------------- --
  // Rotation - part1
  // ------------------------------------------------------------------------------------------- --
  // Does the rotation in 2 cycles, since C could be quite big.
  // First do "local rotation" on ROT_C coefficients.
  // Then rotate the subwords, during the 2nd clock cycle.

  // Rotation is applied on the data and the addresses
  elt_t [C-1:0]                          s1_disp_elt;

  always_comb
    for (int i=0; i<C; i=i+1) begin
      s1_disp_elt[i].data = s1_disp_data[i];
      s1_disp_elt[i].add  = s1_add[i];
    end

  // ------------------------------------------------------------------------------------------- --
  // Command FIFO
  // ------------------------------------------------------------------------------------------- --
  // Prepare command FIFO during this cycle (2 cycles before RAM write), to loose as less cycles as possible.
  assign cmd_fifo_avail    = s1_avail[0] & s1_ctrl.last_iter; // write a command for each interleaved level
  assign cmd_fifo_pbs_id   = s1_ctrl.pbs_id;
  assign cmd_fifo_intl_idx = s1_ctrl.intl_idx;
  assign cmd_fifo_eob      = s1_ctrl.eob;

  // =========================================================================================== --
  // s2
  // =========================================================================================== --
  logic [C-1:0] s2_avail;
  ctrl_t        s2_ctrl;

  // ------------------------------------------------------------------------------------------- --
  // Token management
  // ------------------------------------------------------------------------------------------- --
  // Start with all the token available.
  logic [TOKEN_W:0]   s2_token_rp;
  logic [TOKEN_W:0]   s2_token_wp;
  logic [TOKEN_W:0]   s2_token_rpD;
  logic [TOKEN_W:0]   s2_token_wpD;
  logic [TOKEN_W-1:0] s2_token;
  logic               s2_token_full;
  logic               s2_token_empty;

  assign s2_token_rpD = (s2_avail[0] && s2_ctrl.end_of_wb) ? s2_token_rp + 1 : s2_token_rp;
  assign s2_token_wpD = token_release ? s2_token_wp + 1: s2_token_wp;

  assign s2_token      = s2_token_rp[TOKEN_W-1:0];
  assign s2_token_full = (s2_token_wp[TOKEN_W-1:0] == s2_token_rp[TOKEN_W-1:0])
                        & (s2_token_wp[TOKEN_W] != s2_token_rp[TOKEN_W]);
  assign s2_token_empty = s2_token_rp == s2_token_wp;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      s2_token_rp <= '0;
      s2_token_wp <= TOKEN_NB; // full token. Note : this value is a power of 2
    end
    else begin
      s2_token_rp <= s2_token_rpD;
      s2_token_wp <= s2_token_wpD;
    end

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // Do nothing
    end
    else begin
      if (s2_avail[0]) begin
        assert(!s2_token_empty)
        else $fatal(1,"%t > ERROR: No more available token!", $time);
      end
      if (token_release) begin
        assert(!s2_token_full)
        else  $fatal(1,"%t > ERROR: Token stack overflow!", $time);
      end
    end

    logic [C-1:0] _s1_avail_dly;
    always_ff @(posedge clk)
      if (!s_rst_n) _s1_avail_dly <= '0;
      else          _s1_avail_dly <= s1_avail;

    // Note : if the rotation does not last 2 cycles, adjust the moment the command for cmd_fifo is sent.
    always_ff @(posedge clk)
      if (!s_rst_n) begin
        // do nothing
      end
      else begin
        assert(_s1_avail_dly == s2_avail)
        else begin
          $fatal(1,"%t > ERROR: rotation does not last 2 cycles as expected!", $time);
        end
      end
// pragma translate_on

  // =========================================================================================== --
  // Rotation instance
  // =========================================================================================== --
  elt_t [ROT_SUBW_NB-1:0][ROT_C-1:0] s3_rot_elt;
  logic [C-1:0]                      s3_avail;
  ctrl_t                             s3_ctrl;

  logic [C_W-1:0] s1_rot_factor;

  assign s1_rot_factor = s1_pos; // truncate or expand with 0s

  // Takes 2 cycles
  ntt_core_gf64_ntw_rot
  #(
    .IN_PIPE         (1'b0),
    .OP_W            (ELT_W),
    .C               (C),
    .ROT_C           (ROT_C),
    .DIR             (1'b0),
    .SIDE_W          (CTRL_W),
    .RST_SIDE        (2'b00)
  ) ntt_core_gf64_ntw_rot (
    .clk           (clk),
    .s_rst_n       (s_rst_n),

    .in_data       (s1_disp_elt),
    .in_avail      (s1_avail),
    .in_side       (s1_ctrl),
    .in_rot_factor (s1_rot_factor),

    .out_data      (s3_rot_elt),
    .out_avail     (s3_avail),
    .out_side      (s3_ctrl),

    .penult_avail  (s2_avail),
    .penult_side   (s2_ctrl)
  );

  // =========================================================================================== --
  // s3
  // =========================================================================================== --
  logic [TOKEN_W-1:0] s3_token;

  always_ff @(posedge clk)
    s3_token             <= s2_token;

  // ------------------------------------------------------------------------------------------- --
  // Write in RAM
  // ------------------------------------------------------------------------------------------- --
  always_comb
    for (int i=0; i<ROT_SUBW_NB; i=i+1)
      for (int j=0; j<ROT_C; j=j+1) begin
        ram_wr_data[i*ROT_C+j] = s3_rot_elt[i][j].data;
        ram_wr_add[i*ROT_C+j]  = s3_rot_elt[i][j].add; // extend with 0s if necessary
      end

  assign ram_wr_avail    = s3_avail;
  assign ram_wr_intl_idx = s3_ctrl.intl_idx;
  assign ram_wr_token    = s3_token;
endmodule
