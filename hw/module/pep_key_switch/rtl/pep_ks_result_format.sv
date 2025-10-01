// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the key switch for pe_pbs.
// It takes a BLWE as input.
// Change the key into the PBS key domain.
// Each coefficient is finally mod switch to 2N.
// ==============================================================================================

module pep_ks_result_format
  import param_tfhe_pkg::*;
  import pep_common_param_pkg::*;
  import pep_ks_common_param_pkg::*;
#(
  parameter int RES_FIFO_DEPTH = 4*LBZ // Should be >=2
)
(
  input  logic                    clk,        // clock
  input  logic                    s_rst_n,    // synchronous reset

  input  logic [KS_CMD_W-1:0]     ctrl_res_cmd,
  input  logic                    ctrl_res_cmd_vld,
  output logic                    ctrl_res_cmd_rdy,

  input  logic [LWE_COEF_W-1:0]   br_proc_lwe,
  input  logic [KS_CORR_W-1:0]    br_proc_corr,
  input  logic                    br_proc_vld,
  output logic                    br_proc_rdy,

  // reset cache
  input  logic                    reset_cache,


  // LWE coeff
  output logic [KS_RESULT_W-1:0]  ks_seq_result,
  output logic                    ks_seq_result_vld,
  input  logic                    ks_seq_result_rdy
);

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int CMD_FIFO_DEPTH    = 4; // 2 = ks_control + 2
  localparam int RESULT_FIFO_DEPTH = 4;
  localparam int LAST_X            = (LWE_K_P1 % LBX) == 0 ? LBX - 1 : (LWE_K_P1 % LBX) - 1;

  typedef struct packed {
    logic [KS_CORR_W-1:0]      corr; // mean compensation correction.
    logic [LWE_COEF_W-1:0]     lwe;
  } coef_t;

  localparam int COEF_W = $bits(coef_t);

// ============================================================================================== --
// Input pipe
// ============================================================================================== --
  ks_cmd_t               s0_cmd;
  logic                  s0_cmd_vld;
  logic                  s0_cmd_rdy;

  fifo_reg #(
    .WIDTH       (KS_CMD_W),
    .DEPTH       (CMD_FIFO_DEPTH),
    .LAT_PIPE_MH (2'b11)
  ) s0_cmd_fifo (
    .clk      (clk),
    .s_rst_n  (s_rst_n),

    .in_data  (ctrl_res_cmd),
    .in_vld   (ctrl_res_cmd_vld),
    .in_rdy   (ctrl_res_cmd_rdy),

    .out_data (s0_cmd),
    .out_vld  (s0_cmd_vld),
    .out_rdy  (s0_cmd_rdy)
  );

  coef_t                    br_proc_coef;
  coef_t                    s0_proc_coef;
  logic                     s0_proc_vld;
  logic                     s0_proc_rdy;

  assign br_proc_coef.lwe  = br_proc_lwe;
  assign br_proc_coef.corr = br_proc_corr;

  fifo_element #(
    .WIDTH          (COEF_W),
    .DEPTH          (2),
    .TYPE_ARRAY     (8'h12),
    .DO_RESET_DATA  (1'b0),
    .RESET_DATA_VAL (0)
  ) s0_lwe_fifo_element (
    .clk      (clk),
    .s_rst_n  (s_rst_n),

    .in_data  (br_proc_coef),
    .in_vld   (br_proc_vld),
    .in_rdy   (br_proc_rdy),

    .out_data (s0_proc_coef),
    .out_vld  (s0_proc_vld),
    .out_rdy  (s0_proc_rdy)
  );

  logic reset_loop;
  always_ff @(posedge clk)
    if (!s_rst_n) reset_loop <= 1'b0;
    else          reset_loop <= reset_cache;

// ============================================================================================== --
// Format the result
// ============================================================================================== --
  ks_result_t                              s0_result;
  logic                                    s0_result_vld;
  logic                                    s0_result_rdy;

  coef_t [BATCH_PBS_NB-1:0]                lwe_a;
  coef_t [BATCH_PBS_NB-1:0]                lwe_aD;

  //== keep track of the ks_loop
  logic [KS_BLOCK_COL_W-1:0]               s0_ks_loop;
  logic [KS_BLOCK_COL_W-1:0]               s0_ks_loopD;
  logic                                    s0_last_ks_loop;

  logic [LBX_W-1:0]                        s0_x;
  logic [LBX_W-1:0]                        s0_xD;
  logic                                    s0_last_x;
  logic                                    s0_is_body;

  logic                                    s0_do_inc;

  assign s0_is_body      = s0_last_ks_loop & s0_last_x;
  assign s0_last_ks_loop = s0_ks_loop == KS_BLOCK_COL_NB-1;
  assign s0_last_x       = s0_last_ks_loop ? s0_x == LAST_X : s0_x == LBX-1;
  assign s0_xD           = s0_do_inc ? s0_last_x ? '0 : s0_x + 1 : s0_x;
  assign s0_ks_loopD     = (s0_do_inc && s0_last_x) ? s0_last_ks_loop ? '0 : s0_ks_loop + 1 : s0_ks_loop;

  assign s0_do_inc = (s0_is_body & s0_cmd_vld) | (s0_result_vld & s0_result_rdy);

  always_ff @(posedge clk)
    if (!s_rst_n || reset_loop) begin
      s0_ks_loop <= '0;
      s0_x       <= '0;
    end
    else begin
      s0_ks_loop <= s0_ks_loopD;
      s0_x       <= s0_xD;
    end

  //== Fill the LWE array
  logic [BPBS_NB_W-1:0]  s0_lwe_cnt;
  logic [BPBS_NB_W-1:0]  s0_lwe_cntD;
  logic                  s0_last_lwe_cnt;
  logic [BPBS_NB_WW-1:0] s0_lwe_cnt_max;

  assign s0_lwe_cnt_max   = pt_elt_nb(s0_cmd.wp,s0_cmd.rp) - 1;
  assign s0_last_lwe_cnt  = s0_lwe_cnt == s0_lwe_cnt_max;
  assign s0_lwe_cntD      = (s0_proc_vld && s0_proc_rdy) ? s0_last_lwe_cnt ? '0 : s0_lwe_cnt + 1 : s0_lwe_cnt;

  assign s0_proc_rdy      = (s0_cmd_vld & ~s0_is_body & (~s0_last_lwe_cnt | s0_result_rdy)) | reset_loop;
  assign s0_result_vld    = s0_cmd_vld & ~s0_is_body & s0_proc_vld & s0_last_lwe_cnt & ~reset_loop;
  assign s0_cmd_rdy       = s0_is_body | (s0_result_rdy & s0_proc_vld & (s0_last_lwe_cnt & s0_last_x)) | reset_loop;

  always_comb
    for (int i=0; i<BATCH_PBS_NB; i=i+1)
      lwe_aD[i] = s0_proc_vld && s0_proc_rdy && (s0_lwe_cnt == i) ? s0_proc_coef : lwe_a[i];

  always_ff @(posedge clk)
    if (!s_rst_n || reset_loop) s0_lwe_cnt <= '0;
    else                        s0_lwe_cnt <= s0_lwe_cntD;

  always_ff @(posedge clk)
    lwe_a <= lwe_aD;

  always_comb begin
    s0_result.ks_loop = s0_ks_loop * LBX + s0_x;
    s0_result.wp      = s0_cmd.wp;
    s0_result.rp      = s0_cmd.rp;
    for (int i=0; i<BATCH_PBS_NB; i=i+1) begin
      s0_result.lwe_a[i]   = lwe_aD[i].lwe;
      s0_result.corr_a[i]  = lwe_aD[i].corr;
    end
  end

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n || reset_loop) begin
      // do nothing
    end
    else begin
      if (s0_cmd_vld)
        assert((s0_cmd.ks_loop / LBX) == s0_ks_loop)
        else begin
          $fatal(1,"%t > ERROR: local and command ks_loop mismatch. cmd=%0d local=%0d", $time, (s0_cmd.ks_loop / LBX), s0_ks_loop);
        end
    end
// pragma translate_on

// ============================================================================================== --
// Output FIFO
// ============================================================================================== --
  fifo_reg #(
    .WIDTH       (KS_RESULT_W),
    .DEPTH       (RESULT_FIFO_DEPTH),
    .LAT_PIPE_MH (2'b11)
  ) out_fifo_reg (
    .clk      (clk),
    .s_rst_n  (s_rst_n),

    .in_data  (s0_result),
    .in_vld   (s0_result_vld),
    .in_rdy   (s0_result_rdy),

    .out_data (ks_seq_result),
    .out_vld  (ks_seq_result_vld),
    .out_rdy  (ks_seq_result_rdy)
  );

endmodule
