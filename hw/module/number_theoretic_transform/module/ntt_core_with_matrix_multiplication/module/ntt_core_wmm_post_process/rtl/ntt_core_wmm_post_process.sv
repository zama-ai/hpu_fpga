// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : post-processing
// ----------------------------------------------------------------------------------------------
//
// Post-processing module has three objectives :
//  - Compute final point-wise multiplication in INTT phase
//  - Compute modular multiplier and accumulator for BSK matrix multiplication
//  - Re-direct input, twiddle muliplication or point-wise multiplication depending on control
//
// ==============================================================================================

module ntt_core_wmm_post_process
  import common_definition_pkg::*;
  import param_tfhe_pkg::*;
  import pep_common_param_pkg::*;
#(
  parameter int    OP_W            = 32,
  parameter [OP_W-1:0] MOD_NTT     = 2**32-2**17-2**13+1,
  parameter mod_mult_type_e   MOD_MULT_TYPE   = MOD_MULT_SOLINAS3,
  parameter arith_mult_type_e MULT_TYPE       = MULT_KARATSUBA,
  parameter bit    IN_PIPE         = 1'b1, // Recommended
  parameter bit    OUT_PIPE        = 1'b1  // Recommended
) (
  // System interface
  input                                       clk,
  input                                       s_rst_n,
  // Data from CLBU
  input  logic                [     OP_W-1:0] clbu_pp_data,
  input  logic                                clbu_pp_data_avail,
  input  logic                                clbu_pp_sob,
  input  logic                                clbu_pp_eob,
  input  logic                                clbu_pp_sol,
  input  logic                                clbu_pp_eol,
  input  logic                                clbu_pp_sos,
  input  logic                                clbu_pp_eos,
  input  logic                                clbu_pp_ntt_bwd,
  input  logic                [ BPBS_ID_W-1:0] clbu_pp_pbs_id,
  input  logic                                clbu_pp_ctrl_avail,
  input                                       clbu_pp_last_stg,
  // Output logic data to network regular stage
  output logic                [     OP_W-1:0] pp_rsntw_data,
  output logic                                pp_rsntw_sob,
  output logic                                pp_rsntw_eob,
  output logic                                pp_rsntw_sol,
  output logic                                pp_rsntw_eol,
  output logic                                pp_rsntw_sos,
  output logic                                pp_rsntw_eos,
  output logic                [ BPBS_ID_W-1:0] pp_rsntw_pbs_id,
  output logic                                pp_rsntw_avail,
  // Output logic data forward network last stage
  output logic                [     OP_W-1:0] pp_lsntw_fwd_data,
  output logic                                pp_lsntw_fwd_sob,
  output logic                                pp_lsntw_fwd_eob,
  output logic                                pp_lsntw_fwd_sol,
  output logic                                pp_lsntw_fwd_eol,
  output logic                                pp_lsntw_fwd_sos,
  output logic                                pp_lsntw_fwd_eos,
  output logic                [ BPBS_ID_W-1:0] pp_lsntw_fwd_pbs_id,
  output logic                                pp_lsntw_fwd_avail,
  // Output logic data backward network last stage
  output logic                [     OP_W-1:0] pp_lsntw_bwd_data,
  output logic                                pp_lsntw_bwd_sob,
  output logic                                pp_lsntw_bwd_eob,
  output logic                                pp_lsntw_bwd_sol,
  output logic                                pp_lsntw_bwd_eol,
  output logic                                pp_lsntw_bwd_sos,
  output logic                                pp_lsntw_bwd_eos,
  output logic                [ BPBS_ID_W-1:0] pp_lsntw_bwd_pbs_id,
  output logic                                pp_lsntw_bwd_avail,
  // Output logic data network last stage
  output logic                [     OP_W-1:0] pp_lsntw_data,
  output logic                                pp_lsntw_sob,
  output logic                                pp_lsntw_eob,
  output logic                                pp_lsntw_sol,
  output logic                                pp_lsntw_eol,
  output logic                                pp_lsntw_sos,
  output logic                                pp_lsntw_eos,
  output logic                [ BPBS_ID_W-1:0] pp_lsntw_pbs_id,
  output logic                                pp_lsntw_avail,
  // Error trigger
  output logic                                pp_error,
  // Twiddles for final multiplication
  input  logic                [     OP_W-1:0] twd_intt_final,
  input  logic                                twd_intt_final_vld,
  output logic                                twd_intt_final_rdy,
  // Matrix factors : BSK
  input  logic [GLWE_K_P1-1:0][     OP_W-1:0] bsk,
  input  logic                [GLWE_K_P1-1:0] bsk_vld,
  output logic                [GLWE_K_P1-1:0] bsk_rdy
);

  // ============================================================================================ //
  // Structure
  // ============================================================================================ //
  typedef struct packed {
    logic                ntt_bwd;
    logic                sol;
    logic                eol;
    logic                sob;
    logic                eob;
    logic                sos;
    logic                eos;
    logic [BPBS_ID_W-1:0] pbs_id;
  } control_t;

  typedef struct packed {
    logic                sob;
    logic                eob;
    logic                sos;
    logic                eos;
    logic [BPBS_ID_W-1:0] pbs_id;
  } short_control_t;

  // ============================================================================================ //
  // Input pipe
  // ============================================================================================ //
  logic [OP_W-1:0]      s0_data;
  logic                 s0_data_avail;
  logic                 s0_sob;
  logic                 s0_eob;
  logic                 s0_sol;
  logic                 s0_eol;
  logic                 s0_sos;
  logic                 s0_eos;
  logic                 s0_ntt_bwd;
  logic [BPBS_ID_W-1:0]  s0_pbs_id;
  logic                 s0_ctrl_avail;
  logic                 s0_last_stg;

  generate
    if (IN_PIPE) begin : gen_input_pipe
      always_ff @(posedge clk)
        if (!s_rst_n) begin
          s0_data_avail <= 1'b0;
          s0_ctrl_avail <= 1'b0;
        end
        else begin
          s0_data_avail <= clbu_pp_data_avail;
          s0_ctrl_avail <= clbu_pp_ctrl_avail;
        end

      always_ff @(posedge clk) begin
        s0_data       <= clbu_pp_data;
        s0_sob        <= clbu_pp_sob;
        s0_eob        <= clbu_pp_eob;
        s0_sol        <= clbu_pp_sol;
        s0_eol        <= clbu_pp_eol;
        s0_sos        <= clbu_pp_sos;
        s0_eos        <= clbu_pp_eos;
        s0_ntt_bwd    <= clbu_pp_ntt_bwd;
        s0_pbs_id     <= clbu_pp_pbs_id;
        s0_last_stg   <= clbu_pp_last_stg;
      end
    end
    else begin : no_gen_input_pipe
      assign s0_data       = clbu_pp_data;
      assign s0_data_avail = clbu_pp_data_avail;
      assign s0_sob        = clbu_pp_sob;
      assign s0_eob        = clbu_pp_eob;
      assign s0_sol        = clbu_pp_sol;
      assign s0_eol        = clbu_pp_eol;
      assign s0_sos        = clbu_pp_sos;
      assign s0_eos        = clbu_pp_eos;
      assign s0_ntt_bwd    = clbu_pp_ntt_bwd;
      assign s0_pbs_id     = clbu_pp_pbs_id;
      assign s0_ctrl_avail = clbu_pp_ctrl_avail;
      assign s0_last_stg   = clbu_pp_last_stg;
    end
  endgenerate

  // ============================================================================================ //
  // s0
  // ============================================================================================ //
  // ============================================================================================ //
  // Stage 0 :
  //  - Regular stage network redirection
  //  - Modular multiplier
  //  - Control delay
  // ============================================================================================ //
  // Available -------------------------------------------------------------------------------------
  logic s0_ls_bwd_avail;
  logic s0_ls_fwd_avail;
  logic s0_ls_avail;
  logic s0_rs_avail;

  assign s0_rs_avail     = s0_data_avail & ~s0_last_stg;
  assign s0_ls_avail     = s0_data_avail & s0_last_stg;
  assign s0_ls_bwd_avail = s0_ls_avail & s0_ntt_bwd ;
  assign s0_ls_fwd_avail = s0_ls_avail & ~s0_ntt_bwd;

  // Error management -------------------------------------------------------------------------------
  // BSK and twiddle INTT final must be valid when the data are available
  logic s0_error;
  logic s0_errorD;

  assign s0_errorD = (s0_ls_bwd_avail & ~twd_intt_final_vld)
                    |(s0_ls_fwd_avail & ~bsk_vld[0]);

  always_ff @(posedge clk)
    if (~s_rst_n) s0_error <= 1'b0;
    else          s0_error <= s0_errorD;

  assign pp_error = s0_error;

  // Inverse twiddles factor -----------------------------------------------------------------------
  // The twiddle INTT factors are independent from the level.
  assign twd_intt_final_rdy = s0_ls_bwd_avail & s0_eol;

  // Bootstrapping key ------------------------------------------------------------------------------
  // GLWE_K_P1 keys are consumed per input, 1 per cycle.
  logic [GLWE_K_P1-1:0] s0_ls_fwd_avail_sr;
  assign bsk_rdy = s0_ls_fwd_avail_sr;

  // regular stage network -------------------------------------------------------------------------

  generate
    if (OUT_PIPE) begin : gen_rs_output_pipe

      always_ff @(posedge clk)
        if (~s_rst_n) pp_rsntw_avail <= 0;
        else          pp_rsntw_avail <= s0_rs_avail;

      always_ff @(posedge clk) begin
        pp_rsntw_data    <= s0_data;
        pp_rsntw_sob     <= s0_sob;
        pp_rsntw_eob     <= s0_eob;
        pp_rsntw_sos     <= s0_sos;
        pp_rsntw_eos     <= s0_eos;
        pp_rsntw_sol     <= s0_sol;
        pp_rsntw_eol     <= s0_eol;
        pp_rsntw_pbs_id  <= s0_pbs_id;
      end
    end
    else begin : no_gen_rs_output_pipe
      assign pp_rsntw_avail   = s0_rs_avail;
      assign pp_rsntw_data    = s0_data;
      assign pp_rsntw_sob     = s0_sob;
      assign pp_rsntw_eob     = s0_eob;
      assign pp_rsntw_sos     = s0_sos;
      assign pp_rsntw_eos     = s0_eos;
      assign pp_rsntw_sol     = s0_sol;
      assign pp_rsntw_eol     = s0_eol;
      assign pp_rsntw_pbs_id  = s0_pbs_id;
    end
  endgenerate

  // Modular multiplier ---------------- -----------------------------------------------------------
  logic [GLWE_K_P1-1:0][OP_W-1:0] s0_mult_factor;
  logic [GLWE_K_P1-1:0][OP_W-1:0] s1_multiplier;
  logic [GLWE_K_P1-1:0]           s1_avail_mult;
  control_t                       s0_mult_ctrl;
  control_t [GLWE_K_P1-1:0]       s1_mult_ctrl;

  always_comb begin
    s0_mult_factor[0] = s0_ntt_bwd ? twd_intt_final : bsk[0];
    for (int i = 1; i<GLWE_K_P1; i=i+1)
      s0_mult_factor[i] = bsk[i];
  end

  assign s0_mult_ctrl.ntt_bwd = s0_ntt_bwd;
  assign s0_mult_ctrl.sol     = s0_sol    ;
  assign s0_mult_ctrl.eol     = s0_eol    ;
  assign s0_mult_ctrl.sob     = s0_sob    ;
  assign s0_mult_ctrl.eob     = s0_eob    ;
  assign s0_mult_ctrl.sos     = s0_sos    ;
  assign s0_mult_ctrl.eos     = s0_eos    ;
  assign s0_mult_ctrl.pbs_id  = s0_pbs_id ;

  logic [GLWE_K_P1-1:0][OP_W-1:0] s0_data_sr;
  logic [GLWE_K_P1-1:0][OP_W-1:0] s0_data_sr_tmp;
  logic [GLWE_K_P1-1:0][OP_W-1:0] s0_data_sr_tmpD;
  logic [GLWE_K_P1-1:0]           s0_ls_fwd_avail_sr_tmp;
  logic [GLWE_K_P1-1:0]           s0_ls_fwd_avail_sr_tmpD;
  control_t [GLWE_K_P1-1:0]       s0_mult_ctrl_sr;
  control_t [GLWE_K_P1-1:0]       s0_mult_ctrl_sr_tmp;
  control_t [GLWE_K_P1-1:0]       s0_mult_ctrl_sr_tmpD;

  assign s0_data_sr         = s0_data_sr_tmpD;
  assign s0_ls_fwd_avail_sr = s0_ls_fwd_avail_sr_tmpD;
  assign s0_mult_ctrl_sr    = s0_mult_ctrl_sr_tmpD;

  assign s0_data_sr_tmpD         = {s0_data_sr_tmp[GLWE_K_P1-2:0],s0_data};
  assign s0_ls_fwd_avail_sr_tmpD = {s0_ls_fwd_avail_sr_tmp[GLWE_K_P1-2:0],s0_ls_fwd_avail};
  assign s0_mult_ctrl_sr_tmpD    = {s0_mult_ctrl_sr_tmp[GLWE_K_P1-2:0],s0_mult_ctrl};

  always_ff @(posedge clk) begin
    s0_data_sr_tmp      <= s0_data_sr_tmpD;
    s0_mult_ctrl_sr_tmp <= s0_mult_ctrl_sr_tmpD;
  end

  always_ff @(posedge clk)
    if (!s_rst_n) s0_ls_fwd_avail_sr_tmp <= '0;
    else          s0_ls_fwd_avail_sr_tmp <= s0_ls_fwd_avail_sr_tmpD;

  mod_mult #(
    .MOD_MULT_TYPE (MOD_MULT_TYPE),
    .MOD_W         (OP_W         ),
    .MOD_M         (MOD_NTT      ),
    .MULT_TYPE     (MULT_TYPE    ),
    .IN_PIPE       (0            ), // TODO - review this value
    .SIDE_W        ($size(control_t)),
    .RST_SIDE      (2'b00        )

  ) mod_mult_0 (
    .clk      (clk),
    .s_rst_n  (s_rst_n),
    .a        (s0_mult_factor[0]),
    .b        (s0_data),
    .z        (s1_multiplier[0]),
    .in_avail (s0_ls_avail),
    .out_avail(s1_avail_mult[0]),
    .in_side  (s0_mult_ctrl),
    .out_side (s1_mult_ctrl[0])
  );

  generate
    for (genvar i_gen = 1; i_gen < GLWE_K_P1; i_gen++) begin : gen_glwe_mod_multiplier
      mod_mult #(
        .MOD_MULT_TYPE (MOD_MULT_TYPE),
        .MOD_W         (OP_W         ),
        .MOD_M         (MOD_NTT      ),
        .MULT_TYPE     (MULT_TYPE    ),
        .IN_PIPE       (0            ), // TODO - review this value
        .SIDE_W        ($size(control_t)),
        .RST_SIDE      (2'b00        )

      ) mod_mult_i (
        .clk      (clk),
        .s_rst_n  (s_rst_n),
        .a        (s0_mult_factor[i_gen]),
        .b        (s0_data_sr[i_gen]),
        .z        (s1_multiplier[i_gen]),
        .in_avail (s0_ls_fwd_avail_sr[i_gen]),
        .out_avail(s1_avail_mult[i_gen]),
        .in_side  (s0_mult_ctrl_sr[i_gen]),
        .out_side (s1_mult_ctrl[i_gen])
      );
    end
  endgenerate

  // ============================================================================================ //
  // s1
  // ============================================================================================ //
  // ============================================================================================ //
  // Stage 1 :
  //  - Last stage backward redirection
  //  - Modular accumulator
  // ============================================================================================ //
  logic s1_ls_bwd_avail;
  logic s1_ls_fwd_avail;

  assign s1_ls_bwd_avail = s1_avail_mult[0] & s1_mult_ctrl[0].ntt_bwd;
  assign s1_ls_fwd_avail = s1_avail_mult[0] & ~s1_mult_ctrl[0].ntt_bwd;

  // Last stage backward redirection ---------------------------------------------------------------
  logic [     OP_W-1:0] s1_ls_bwd_data;
  logic                 s1_ls_bwd_sob;
  logic                 s1_ls_bwd_eob;
  logic                 s1_ls_bwd_sol;
  logic                 s1_ls_bwd_eol;
  logic                 s1_ls_bwd_sos;
  logic                 s1_ls_bwd_eos;
  logic                 s1_ls_bwd_ntt_bwd;
  logic [ BPBS_ID_W-1:0] s1_ls_bwd_pbs_id;

  assign s1_ls_bwd_data       = s1_multiplier[0];
  assign s1_ls_bwd_sob        = s1_mult_ctrl[0].sob    ;
  assign s1_ls_bwd_eob        = s1_mult_ctrl[0].eob    ;
  assign s1_ls_bwd_sol        = s1_mult_ctrl[0].sol    ;
  assign s1_ls_bwd_eol        = s1_mult_ctrl[0].eol    ;
  assign s1_ls_bwd_sos        = s1_mult_ctrl[0].sos    ;
  assign s1_ls_bwd_eos        = s1_mult_ctrl[0].eos    ;
  assign s1_ls_bwd_ntt_bwd    = s1_mult_ctrl[0].ntt_bwd;
  assign s1_ls_bwd_pbs_id     = s1_mult_ctrl[0].pbs_id ;

  generate
    if (OUT_PIPE) begin: gen_ls_bwd_output_pipe
      always_ff @(posedge clk)
        if (!s_rst_n) pp_lsntw_bwd_avail <= 1'b0;
        else          pp_lsntw_bwd_avail <= s1_ls_bwd_avail;
      always_ff @(posedge clk) begin
        pp_lsntw_bwd_data    <= s1_ls_bwd_data   ;
        pp_lsntw_bwd_pbs_id  <= s1_ls_bwd_pbs_id ;
        pp_lsntw_bwd_sob     <= s1_ls_bwd_sob    ;
        pp_lsntw_bwd_eob     <= s1_ls_bwd_eob    ;
        pp_lsntw_bwd_sol     <= s1_ls_bwd_sol    ;
        pp_lsntw_bwd_eol     <= s1_ls_bwd_eol    ;
        pp_lsntw_bwd_eos     <= s1_ls_bwd_eos    ;
        pp_lsntw_bwd_sos     <= s1_ls_bwd_sos    ;
      end
    end
    else begin : no_gen_ls_bwd_output_pipe
      assign pp_lsntw_bwd_avail   = s1_ls_bwd_avail  ;
      assign pp_lsntw_bwd_data    = s1_ls_bwd_data   ;
      assign pp_lsntw_bwd_pbs_id  = s1_ls_bwd_pbs_id ;
      assign pp_lsntw_bwd_sob     = s1_ls_bwd_sob    ;
      assign pp_lsntw_bwd_eob     = s1_ls_bwd_eob    ;
      assign pp_lsntw_bwd_sol     = s1_ls_bwd_sol    ;
      assign pp_lsntw_bwd_eol     = s1_ls_bwd_eol    ;
      assign pp_lsntw_bwd_eos     = s1_ls_bwd_eos    ;
      assign pp_lsntw_bwd_sos     = s1_ls_bwd_sos    ;
    end
  endgenerate

  // Accumulation ----------------------------------------------------------------------------------
  logic [GLWE_K_P1-1:0]           s2_avail_acc;
  logic [GLWE_K_P1-1:0][OP_W-1:0] s2_accumulator;

  // The first mod_acc takes care of the delaying of the control signals.
  short_control_t s1_acc_ctrl;
  short_control_t s2_acc_ctrl;
  logic s1_sob_kept;
  logic s1_sos_kept;

  // /!\ Assumption : We assume that a batch and a stage last more than 1 cycle.
  always_ff @(posedge clk)
    if (s1_ls_fwd_avail && s1_mult_ctrl[0].sol) begin
      s1_sob_kept <= s1_mult_ctrl[0].sob;
      s1_sos_kept <= s1_mult_ctrl[0].sos;
    end

  // The control is only taken into account with eol.
  assign s1_acc_ctrl.sob     = s1_sob_kept;
  assign s1_acc_ctrl.sos     = s1_sos_kept;
  assign s1_acc_ctrl.eob     = s1_mult_ctrl[0].eob;
  assign s1_acc_ctrl.eos     = s1_mult_ctrl[0].eos;
  assign s1_acc_ctrl.pbs_id  = s1_mult_ctrl[0].pbs_id;

  mod_acc #(
    .OP_W    (OP_W                  ),
    .MOD_M   (MOD_NTT               ),
    .IN_PIPE (1                     ),
    .OUT_PIPE(0                     ), // TODO - review value
    .SIDE_W  ($size(short_control_t)),
    .RST_SIDE(2'b00                 )
  ) mod_acc_0 (
    // system interface
    .clk      (clk),
    .s_rst_n  (s_rst_n),
    // data interface
    .in_op    (s1_multiplier[0]),
    .out_op   (s2_accumulator[0]),
    // control interface
    .in_eol   (s1_mult_ctrl[0].eol),
    .in_sol   (s1_mult_ctrl[0].sol),
    .in_avail (s1_ls_fwd_avail),
    .out_avail(s2_avail_acc[0]),
    .in_side  (s1_acc_ctrl),
    .out_side (s2_acc_ctrl)
  );

  generate
    for (genvar i_gen = 1; i_gen < GLWE_K_P1; i_gen++) begin : gen_glwe_accumulator
      mod_acc #(
        .OP_W    (OP_W   ),
        .MOD_M   (MOD_NTT),
        .IN_PIPE (1      ),
        .OUT_PIPE(0      ), // TODO - review value
        .SIDE_W  (0      ),
        .RST_SIDE(2'b00  )
      ) mod_acc_i (
        // system interface
        .clk      (clk),
        .s_rst_n  (s_rst_n),
        // data interface
        .in_op    (s1_multiplier[i_gen]),
        .out_op   (s2_accumulator[i_gen]),
        // control interface
        .in_eol   (s1_mult_ctrl[i_gen].eol),
        .in_sol   (s1_mult_ctrl[i_gen].sol),
        .in_avail (s1_avail_mult[i_gen]), // already contains the "fwd" information
        .out_avail(s2_avail_acc[i_gen]),
        .in_side  ('x),
        .out_side (/*UNUSED*/)
      );
    end
  endgenerate

  // ============================================================================================ //
  // s2
  // ============================================================================================ //
  // ============================================================================================ //
  // Stage 2 :
  //  - Last stage forward output management
  // ============================================================================================ //
  // Bufferize output
  short_control_t                     s2_fwd_buffer_ctrl;
  short_control_t                     s2_fwd_out_ctrl;
  logic     [GLWE_K_P1-1:0][OP_W-1:0] s2_fwd_out_data_a;

  assign s2_fwd_out_ctrl                  = s2_avail_acc[0] ? s2_acc_ctrl : s2_fwd_buffer_ctrl;
  assign s2_fwd_out_data_a                = s2_accumulator;

  always_ff @(posedge clk)
    s2_fwd_buffer_ctrl <= s2_avail_acc[0] ? s2_acc_ctrl : s2_fwd_buffer_ctrl;

  // Count the output
  logic [GLWE_K_P1_W-1:0] s2_fwd_out_cnt;
  logic [GLWE_K_P1_W-1:0] s2_fwd_out_cntD;

  assign s2_fwd_out_cntD = (s2_avail_acc[0] || s2_fwd_out_cnt > 0) ?
                          (s2_fwd_out_cnt == GLWE_K_P1-1) ? '0 : s2_fwd_out_cnt + 1 : s2_fwd_out_cnt;

  always_ff @(posedge clk)
    if (!s_rst_n) s2_fwd_out_cnt <= '0;
    else          s2_fwd_out_cnt <= s2_fwd_out_cntD;

  // Last stage FWD output
  logic [     OP_W-1:0] s2_ls_fwd_data;
  logic                 s2_ls_fwd_sob;
  logic                 s2_ls_fwd_eob;
  logic                 s2_ls_fwd_sol;
  logic                 s2_ls_fwd_eol;
  logic                 s2_ls_fwd_sos;
  logic                 s2_ls_fwd_eos;
  logic                 s2_ls_fwd_ntt_bwd;
  logic [BPBS_ID_W-1:0] s2_ls_fwd_pbs_id;
  logic                 s2_ls_fwd_avail;

  assign s2_ls_fwd_avail   = (s2_avail_acc[0] | s2_fwd_out_cnt > 0);
  assign s2_ls_fwd_pbs_id  = s2_fwd_out_ctrl.pbs_id;
  assign s2_ls_fwd_ntt_bwd = 1'b0; // since we are processing fwd path
  assign s2_ls_fwd_sob     = (s2_fwd_out_cnt == 0)           ? s2_acc_ctrl.sob : 1'b0;
  assign s2_ls_fwd_eob     = (s2_fwd_out_cnt == GLWE_K_P1-1) ? s2_fwd_buffer_ctrl.eob : 1'b0;
  assign s2_ls_fwd_sos     = (s2_fwd_out_cnt == 0)           ? s2_acc_ctrl.sos : 1'b0;
  assign s2_ls_fwd_eos     = (s2_fwd_out_cnt == GLWE_K_P1-1) ? s2_fwd_buffer_ctrl.eos : 1'b0;
  assign s2_ls_fwd_sol     = s2_fwd_out_cnt == '0;
  assign s2_ls_fwd_eol     = s2_fwd_out_cnt == GLWE_K_P1-1;
  assign s2_ls_fwd_data    = s2_fwd_out_data_a[s2_fwd_out_cnt];

  generate
    if (OUT_PIPE) begin : gen_ls_fwd_output_pipe
      always_ff @(posedge clk)
        if (!s_rst_n) pp_lsntw_fwd_avail <= 1'b0;
        else          pp_lsntw_fwd_avail <= s2_ls_fwd_avail;
      always_ff @(posedge clk) begin
        pp_lsntw_fwd_pbs_id  <= s2_ls_fwd_pbs_id ;
        pp_lsntw_fwd_sob     <= s2_ls_fwd_sob    ;
        pp_lsntw_fwd_eob     <= s2_ls_fwd_eob    ;
        pp_lsntw_fwd_sos     <= s2_ls_fwd_sos    ;
        pp_lsntw_fwd_eos     <= s2_ls_fwd_eos    ;
        pp_lsntw_fwd_sol     <= s2_ls_fwd_sol    ;
        pp_lsntw_fwd_eol     <= s2_ls_fwd_eol    ;
        pp_lsntw_fwd_data    <= s2_ls_fwd_data   ;
      end
    end
    else begin : no_gen_ls_fwd_output_pipe
      assign pp_lsntw_fwd_pbs_id  = s2_ls_fwd_pbs_id ;
      assign pp_lsntw_fwd_sob     = s2_ls_fwd_sob    ;
      assign pp_lsntw_fwd_eob     = s2_ls_fwd_eob    ;
      assign pp_lsntw_fwd_sos     = s2_ls_fwd_sos    ;
      assign pp_lsntw_fwd_eos     = s2_ls_fwd_eos    ;
      assign pp_lsntw_fwd_sol     = s2_ls_fwd_sol    ;
      assign pp_lsntw_fwd_eol     = s2_ls_fwd_eol    ;
      assign pp_lsntw_fwd_data    = s2_ls_fwd_data   ;
      assign pp_lsntw_fwd_avail   = s2_ls_fwd_avail  ;
    end
  endgenerate

  // Last stage output configuration for compact architecture --------------------------------------
  // In compact architecture, a last stage is never followed by another last stage.
  // Therefore, in this architecture, the 2 last stages should not conflict.
  logic [     OP_W-1:0] s2_ls_data;
  logic                 s2_ls_sob;
  logic                 s2_ls_eob;
  logic                 s2_ls_sol;
  logic                 s2_ls_eol;
  logic                 s2_ls_sos;
  logic                 s2_ls_eos;
  logic [ BPBS_ID_W-1:0] s2_ls_pbs_id;
  logic                 s2_ls_avail;

  assign s2_ls_data     = s1_ls_bwd_avail ? s1_ls_bwd_data    : s2_ls_fwd_data   ;
  assign s2_ls_sob      = s1_ls_bwd_avail ? s1_ls_bwd_sob     : s2_ls_fwd_sob    ;
  assign s2_ls_eob      = s1_ls_bwd_avail ? s1_ls_bwd_eob     : s2_ls_fwd_eob    ;
  assign s2_ls_sol      = s1_ls_bwd_avail ? s1_ls_bwd_sol     : s2_ls_fwd_sol    ;
  assign s2_ls_eol      = s1_ls_bwd_avail ? s1_ls_bwd_eol     : s2_ls_fwd_eol    ;
  assign s2_ls_sos      = s1_ls_bwd_avail ? s1_ls_bwd_sos     : s2_ls_fwd_sos    ;
  assign s2_ls_eos      = s1_ls_bwd_avail ? s1_ls_bwd_eos     : s2_ls_fwd_eos    ;
  assign s2_ls_pbs_id   = s1_ls_bwd_avail ? s1_ls_bwd_pbs_id  : s2_ls_fwd_pbs_id ;
  assign s2_ls_avail    = s2_ls_fwd_avail | s1_ls_bwd_avail;

  generate
    if (OUT_PIPE) begin : gen_ls_output_pipe
      always_ff @(posedge clk)
        if (!s_rst_n) pp_lsntw_avail <= 1'b0;
        else          pp_lsntw_avail <= s2_ls_avail;
      always_ff @(posedge clk) begin
        pp_lsntw_pbs_id  <= s2_ls_pbs_id ;
        pp_lsntw_sob     <= s2_ls_sob    ;
        pp_lsntw_eob     <= s2_ls_eob    ;
        pp_lsntw_sos     <= s2_ls_sos    ;
        pp_lsntw_eos     <= s2_ls_eos    ;
        pp_lsntw_sol     <= s2_ls_sol    ;
        pp_lsntw_eol     <= s2_ls_eol    ;
        pp_lsntw_data    <= s2_ls_data   ;
      end
    end
    else begin : no_gen_ls_output_pipe
      assign pp_lsntw_pbs_id  = s2_ls_pbs_id ;
      assign pp_lsntw_sob     = s2_ls_sob    ;
      assign pp_lsntw_eob     = s2_ls_eob    ;
      assign pp_lsntw_sos     = s2_ls_sos    ;
      assign pp_lsntw_eos     = s2_ls_eos    ;
      assign pp_lsntw_sol     = s2_ls_sol    ;
      assign pp_lsntw_eol     = s2_ls_eol    ;
      assign pp_lsntw_data    = s2_ls_data   ;
      assign pp_lsntw_avail   = s2_ls_avail  ;
    end
  endgenerate

endmodule
