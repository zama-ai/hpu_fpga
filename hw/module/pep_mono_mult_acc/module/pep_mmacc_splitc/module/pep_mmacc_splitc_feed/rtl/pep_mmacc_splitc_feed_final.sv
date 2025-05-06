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

module pep_mmacc_splitc_feed_final
  import param_tfhe_pkg::*;
  import ntt_core_common_param_pkg::*;
  import top_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import pep_mmacc_common_param_pkg::*;
  import pep_mmacc_splitc_feed_pkg::*;
#(
  parameter bit INPUT_PIPE = 1'b0
)
(
  input  logic                                                           clk,        // clock
  input  logic                                                           s_rst_n,    // synchronous reset

  // Input data
  input  logic [PSI/2-1:0][R-1:0][MOD_Q_W-1:0]                           in0_data,
  input  logic [PSI/2-1:0][R-1:0][MOD_Q_W-1:0]                           in0_rot_data,
  input  logic                                                           in0_data_avail,

  input  logic [PSI/2-1:0][R-1:0][MOD_Q_W-1:0]                           in1_data,
  input  logic [PSI/2-1:0][R-1:0][MOD_Q_W-1:0]                           in1_rot_data,
  input  logic                                                           in1_data_avail,

  input  logic [PERM_W-1:0]                                              in_perm_select,
  input  logic [LWE_COEF_W:0]                                            in_coef_rot_id0,
  input  logic [REQ_CMD_W-1:0]                                           in_rcmd,

  // Output data
  output logic [ACC_DECOMP_COEF_NB-1:0]                                  acc_decomp_data_avail,
  output logic                                                           acc_decomp_ctrl_avail,
  output logic [ACC_DECOMP_COEF_NB-1:0][MOD_Q_W-1:0]                     acc_decomp_data,
  output logic                                                           acc_decomp_sob,
  output logic                                                           acc_decomp_eob,
  output logic                                                           acc_decomp_sog,
  output logic                                                           acc_decomp_eog,
  output logic                                                           acc_decomp_sol,
  output logic                                                           acc_decomp_eol,
  output logic                                                           acc_decomp_soc,
  output logic                                                           acc_decomp_eoc,
  output logic [BPBS_ID_W-1:0]                                           acc_decomp_pbs_id,
  output logic                                                           acc_decomp_last_pbs,
  output logic                                                           acc_decomp_full_throughput
);

//=================================================================================================
// localparam
//=================================================================================================
  localparam int HPSI = PSI/2;

//=================================================================================================
// Input pipe
//=================================================================================================
  logic [HPSI-1:0][R-1:0][MOD_Q_W-1:0] s2_0_in0_data;
  logic [HPSI-1:0][R-1:0][MOD_Q_W-1:0] s2_0_in0_rot_data;
  logic                                s2_0_in0_data_avail;

  logic [HPSI-1:0][R-1:0][MOD_Q_W-1:0] s2_0_in1_data;
  logic [HPSI-1:0][R-1:0][MOD_Q_W-1:0] s2_0_in1_rot_data;
  logic [PERM_W-1:0]                   s2_0_in_perm_select;
  logic                                s2_0_in1_data_avail;
  logic [LWE_COEF_W:0]                 s2_0_coef_rot_id0;
  req_cmd_t                            s2_0_rcmd;

  generate
    if (INPUT_PIPE) begin : gen_in_pipe
      always_ff @(posedge clk)
        if (!s_rst_n) begin
          s2_0_in0_data_avail <= '0;
          s2_0_in1_data_avail <= '0;
        end
        else begin
          s2_0_in0_data_avail <= in0_data_avail;
          s2_0_in1_data_avail <= in1_data_avail;
        end

      always_ff @(posedge clk) begin
        s2_0_in0_data         <= in0_data;
        s2_0_in0_rot_data     <= in0_rot_data;
        s2_0_in1_data         <= in1_data;
        s2_0_in1_rot_data     <= in1_rot_data;
        s2_0_in_perm_select   <= in_perm_select;
        s2_0_coef_rot_id0     <= in_coef_rot_id0;
        s2_0_rcmd             <= in_rcmd;
      end
    end
    else begin : gen_no_in_pipe
      assign s2_0_in0_data_avail   = in0_data_avail;
      assign s2_0_in1_data_avail   = in1_data_avail;
      assign s2_0_in0_data         = in0_data;
      assign s2_0_in0_rot_data     = in0_rot_data;
      assign s2_0_in1_data         = in1_data;
      assign s2_0_in1_rot_data     = in1_rot_data;
      assign s2_0_in_perm_select   = in_perm_select;
      assign s2_0_coef_rot_id0     = in_coef_rot_id0;
      assign s2_0_rcmd             = in_rcmd;
    end
  endgenerate

//=================================================================================================
// S2 Permutation
//=================================================================================================
  logic [1:0][HPSI-1:0][R-1:0][MOD_Q_W-1:0] s2_0_rot_data;
  logic [1:0][HPSI-1:0][R-1:0][MOD_Q_W-1:0] s2_0_data;
  logic [1:0]                               s2_0_data_avail;
  logic                                     s2_0_perm_select;

  assign s2_0_rot_data[0] = s2_0_in0_rot_data;
  assign s2_0_rot_data[1] = s2_0_in1_rot_data;

  assign s2_0_data[0] = s2_0_in0_data;
  assign s2_0_data[1] = s2_0_in1_data;

  assign s2_0_data_avail[0] = s2_0_in0_data_avail;
  assign s2_0_data_avail[1] = s2_0_in1_data_avail;

  assign s2_0_perm_select = s2_0_in_perm_select[0];

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      assert(s2_0_data_avail[0] == s2_0_data_avail[1])
      else begin
        $fatal(1,"%t > ERROR: HPSI coef not synchronized!" , $time);
      end
    end
// pragma translate_on

  logic [1:0][HPSI-1:0][R-1:0][MOD_Q_W-1:0] s2_0_perm_data;

  assign s2_0_perm_data[0] = s2_0_perm_select ? s2_0_rot_data[1] : s2_0_rot_data[0];
  assign s2_0_perm_data[1] = s2_0_perm_select ? s2_0_rot_data[0] : s2_0_rot_data[1];

//=================================================================================================
// S2 Chunk management
//=================================================================================================
  logic [CHUNK_NB-1:0][ACC_DECOMP_COEF_NB-1:0][MOD_Q_W-1:0] s2_0_mask_data_1_ext;
  logic [CHUNK_NB-1:0][ACC_DECOMP_COEF_NB-1:0][MOD_Q_W-1:0] s2_0_perm_data_ext;

  logic                                                     s2_0_avail;

  assign s2_0_mask_data_1_ext = s2_0_data;
  assign s2_0_perm_data_ext   = s2_0_perm_data;
  assign s2_0_avail           = s2_0_data_avail[0]; // both bits should be equal

  // Counters
  logic [CHUNK_NB_W-1:0] s2_0_chk;
  logic [CHUNK_NB_W-1:0] s2_0_chkD;
  logic                  s2_0_last_chk;
  logic                  s2_0_first_chk;
  logic                  s2_0_chk_running;

  assign s2_0_first_chk   = s2_0_chk == 0;
  assign s2_0_last_chk    = s2_0_chk == (CHUNK_NB-1);
  assign s2_0_chk_running = (s2_0_chk > 0);
  assign s2_0_chkD        = (s2_0_avail || s2_0_chk_running) ? s2_0_last_chk ? '0 : s2_0_chk + 1 : s2_0_chk;

  always_ff @(posedge clk)
    if (!s_rst_n) s2_0_chk <= '0;
    else          s2_0_chk <= s2_0_chkD;

  logic s2_0_sob;
  logic s2_0_eob;
  logic s2_0_sog;
  logic s2_0_eog;
  logic s2_0_sol;
  logic s2_0_eol;
  logic s2_0_soc;
  logic s2_0_eoc;

  assign s2_0_sob = s2_0_sog & s2_0_rcmd.batch_first_ct;
  assign s2_0_eob = s2_0_eog & s2_0_rcmd.batch_last_ct;
  assign s2_0_sog = s2_0_sol & (s2_0_rcmd.stg_iter == 0);
  assign s2_0_eog = s2_0_eol & (s2_0_rcmd.stg_iter == (STG_ITER_NB-1));
  assign s2_0_sol = s2_0_soc & (s2_0_rcmd.poly_id == 0);
  assign s2_0_eol = s2_0_eoc & (s2_0_rcmd.poly_id == (GLWE_K_P1-1));
  assign s2_0_soc = s2_0_first_chk;
  assign s2_0_eoc = s2_0_last_chk;

  //== Sign
  logic [CHUNK_NB-1:0][ACC_DECOMP_COEF_NB-1:0] s2_0_sign_ext;
  logic [PSI-1:0][R-1:0]                       s2_0_sign;

  assign s2_0_sign_ext = s2_0_sign;

  generate
    for (genvar gen_i=0; gen_i<R*PSI; gen_i=gen_i+1) begin : gen_s2_0_sign_loop
      logic [N_SZ-1:0]     s2_0_local_id; // reverse order
      logic [LWE_COEF_W:0] s2_0_rot_id;

      assign s2_0_local_id = rev_order_n(gen_i); // constant
      assign s2_0_rot_id   = s2_0_coef_rot_id0 + s2_0_local_id;

      //assign s2_0_sign[gen_i/R][gen_i%R] = (s2_0_rot_id >= N) & (s2_0_rot_id < 2*N);
      assign s2_0_sign[gen_i/R][gen_i%R] = s2_0_rot_id[LWE_COEF_W:N_SZ] == 2'b01;

// pragma translate_off
      always_ff @(posedge clk)
        if (s2_0_avail)
          assert(s2_0_rot_id < 3*N)
          else begin
            $fatal(1, "%t > ERROR: rot coord overflow! %0d should be less than 3*N=%0d.",$time, s2_0_rot_id, 3*N);
          end
// pragma translate_on
    end
  endgenerate

  //== avail
  logic                                        s2_0_ctrl_avail;
  logic [PSI-1:0][R-1:0]                       s2_0_data_avail_tmp;
  logic [CHUNK_NB-1:0][ACC_DECOMP_COEF_NB-1:0] s2_0_data_avail_ext;

  assign s2_0_ctrl_avail     = s2_0_avail | s2_0_chk_running;
  assign s2_0_data_avail_tmp = {PSI*R{s2_0_ctrl_avail}}; // duplicate
  assign s2_0_data_avail_ext = s2_0_data_avail_tmp;

  //== Select the chunk
  logic [ACC_DECOMP_COEF_NB-1:0][MOD_Q_W-1:0] s2_0_chk_data;
  logic [ACC_DECOMP_COEF_NB-1:0][MOD_Q_W-1:0] s2_0_chk_rot_data;
  logic [ACC_DECOMP_COEF_NB-1:0]              s2_0_chk_sign;

  always_comb
    for (int i=0; i<ACC_DECOMP_COEF_NB; i=i+1) begin
      s2_0_chk_data[i]     = s2_0_mask_data_1_ext[s2_0_chk][i];
      s2_0_chk_rot_data[i] = s2_0_perm_data_ext[s2_0_chk][i];
      s2_0_chk_sign[i]     = s2_0_sign_ext[s2_0_chk][i];
    end

//=================================================================================================
// S3
//=================================================================================================
// Pipe
  logic [ACC_DECOMP_COEF_NB-1:0][MOD_Q_W-1:0] s2_0_chk_data_opp;

  always_comb
    for (int i=0; i<ACC_DECOMP_COEF_NB; i=i+1)
      s2_0_chk_data_opp[i] = 2**MOD_Q_W - s2_0_chk_data[i];

  logic [ACC_DECOMP_COEF_NB-1:0][MOD_Q_W-1:0] s3_chk_data_opp;
  logic [ACC_DECOMP_COEF_NB-1:0][MOD_Q_W-1:0] s3_chk_rot_data;
  logic [ACC_DECOMP_COEF_NB-1:0]              s3_chk_sign;
  logic                                       s3_sob;
  logic                                       s3_eob;
  logic                                       s3_sog;
  logic                                       s3_eog;
  logic                                       s3_sol;
  logic                                       s3_eol;
  logic                                       s3_soc;
  logic                                       s3_eoc;
  logic                                       s3_last_pbs;
  logic [BPBS_ID_W-1:0]                       s3_pbs_id;
  logic [ACC_DECOMP_COEF_NB-1:0]              s3_data_avail;
  logic                                       s3_ctrl_avail;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      s3_data_avail <= '0;
      s3_ctrl_avail <= 1'b0;
    end
    else begin
      s3_data_avail <= s2_0_data_avail_ext[0];
      s3_ctrl_avail <= s2_0_ctrl_avail;
    end

  always_ff @(posedge clk) begin
    s3_chk_data_opp <= s2_0_chk_data_opp;
    s3_chk_rot_data <= s2_0_chk_rot_data;
    s3_chk_sign     <= s2_0_chk_sign;
    s3_sob          <= s2_0_sob;
    s3_eob          <= s2_0_eob;
    s3_sog          <= s2_0_sog;
    s3_eog          <= s2_0_eog;
    s3_sol          <= s2_0_sol;
    s3_eol          <= s2_0_eol;
    s3_soc          <= s2_0_soc;
    s3_eoc          <= s2_0_eoc;
    s3_last_pbs     <= s2_0_rcmd.batch_last_ct;
    s3_pbs_id       <= s2_0_rcmd.pbs_id;
  end

// Apply subtraction
  logic [ACC_DECOMP_COEF_NB-1:0]              res_data_avail;
  logic                                       res_ctrl_avail;

  logic [ACC_DECOMP_COEF_NB-1:0][MOD_Q_W-1:0] res_data;
  logic                                       res_sob;
  logic                                       res_eob;
  logic                                       res_sog;
  logic                                       res_eog;
  logic                                       res_sol;
  logic                                       res_eol;
  logic                                       res_soc;
  logic                                       res_eoc;
  logic [BPBS_ID_W-1:0]                       res_pbs_id;
  logic                                       res_last_pbs;

  logic [ACC_DECOMP_COEF_NB-1:0][MOD_Q_W-1:0] s3_sub_data;

  always_comb
    for (int i=0; i<ACC_DECOMP_COEF_NB; i=i+1)
      s3_sub_data[i] = s3_chk_sign[i] ? s3_chk_data_opp[i] - s3_chk_rot_data[i] : s3_chk_data_opp[i] + s3_chk_rot_data[i];

  // result
  assign res_data_avail = s3_data_avail;
  assign res_ctrl_avail = s3_ctrl_avail;
  assign res_data       = s3_sub_data;
  assign res_sob        = s3_sob;
  assign res_eob        = s3_eob;
  assign res_sog        = s3_sog;
  assign res_eog        = s3_eog;
  assign res_sol        = s3_sol;
  assign res_eol        = s3_eol;
  assign res_soc        = s3_soc;
  assign res_eoc        = s3_eoc;
  assign res_pbs_id     = s3_pbs_id;
  assign res_last_pbs   = s3_last_pbs;

//=================================================================================================
// Output
//=================================================================================================
// Synchronization + Subtraction
    always_ff @(posedge clk)
    if (!s_rst_n) begin
      acc_decomp_data_avail <= '0;
      acc_decomp_ctrl_avail <= '0;
    end
    else begin
      acc_decomp_data_avail <= res_data_avail;
      acc_decomp_ctrl_avail <= res_ctrl_avail;
    end

  always_ff @(posedge clk) begin
    acc_decomp_data     <= res_data;
    acc_decomp_sob      <= res_sob;
    acc_decomp_eob      <= res_eob;
    acc_decomp_sog      <= res_sog;
    acc_decomp_eog      <= res_eog;
    acc_decomp_sol      <= res_sol;
    acc_decomp_eol      <= res_eol;
    acc_decomp_soc      <= res_soc;
    acc_decomp_eoc      <= res_eoc;
    acc_decomp_pbs_id   <= res_pbs_id;
    acc_decomp_last_pbs <= res_last_pbs;
  end

  assign acc_decomp_full_throughput = 1; //TODO

endmodule
