// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This testbench checks that the assembly of the ntt_core_with_matrix_multiplication with
// the unfold_pcg architecture is working fine with the twiddles, and bsk network.
//
// ==============================================================================================

module tb_ntt_core_with_matrix_multiplication_unfold_pcg_assembly;
  `timescale 1ns/10ps

  import common_definition_pkg::*;
  import param_ntt_pkg::*;
  import param_tfhe_pkg::*;
  import pep_common_param_pkg::*;
  import ntt_core_common_param_pkg::*;
  import bsk_ntw_common_param_pkg::*;
  import file_handler_pkg::*;

  // ============================================================================================ //
  // parameter
  // ============================================================================================ //
  parameter mod_mult_type_e   MOD_MULT_TYPE = set_mod_mult_type(MOD_NTT_TYPE, OPTIMIZATION_NAME_CLB);
  parameter mod_reduct_type_e REDUCT_TYPE   = set_mod_reduct_type(MOD_NTT_TYPE, OPTIMIZATION_NAME_CLB);
  parameter arith_mult_type_e MULT_TYPE     = set_ntt_mult_type(MOD_NTT_W,MOD_NTT_TYPE, OPTIMIZATION_NAME_CLB);
  parameter mod_mult_type_e   PP_MOD_MULT_TYPE = set_mod_mult_type(MOD_NTT_TYPE, OPTIMIZATION_NAME_DSP);
  parameter arith_mult_type_e PP_MULT_TYPE     = set_ntt_mult_type(MOD_NTT_W,MOD_NTT_TYPE, OPTIMIZATION_NAME_DSP);
  parameter int    RAM_LATENCY   = 1;
  parameter int    ROM_LATENCY   = RAM_LATENCY;
  parameter int    URAM_LATENCY  = 1+4;
  // Not too many BSK_INST_BR_LOOP_NB, in order to provoke some collisions.
  parameter int    BR_LOOP_NB     = 10;
  parameter int    SIMU_BATCH_NB = 40;
  parameter int    BATCH_NB       = 2; // Number of batch processed simultaneously
  parameter int    BWD_PSI_DIV    = 2;

  parameter int    DELTA          = (S+1)/2;

  // ============================================================================================ //
  // localparam
  // ============================================================================================ //
  localparam int CLK_HALF_PERIOD     = 1;
  localparam int ARST_ACTIVATION     = 17;

  localparam int NTT_ERROR_W         = 2;
  localparam int TWD_PHRU_ERROR_NB   = 2;

  localparam int BSK_SRV_NB          = 3;
  localparam int BSK_CLT_NB          = 1;
  localparam int SRV_ERROR_NB         = 1;
  localparam int CLT_ERROR_NB         = 2;

  parameter  [BSK_SRV_NB-1:0][31:0] BSK_INST_BR_LOOP_NB  = get_bsk_loop_nb(BR_LOOP_NB);
  localparam [BSK_SRV_NB-1:0][31:0] BSK_INST_BR_LOOP_OFS = get_bsk_loop_ofs(BSK_INST_BR_LOOP_NB);
  localparam int DATA_RAND_RANGE     = 1023;

  localparam int BATCH_DLY           = 32; // Number of cycles between batch_cmd and the data
                                          // Estimation of the latency of the monomial mult and decomp
  localparam int OP_W = MOD_NTT_W;

  localparam int LS_DELTA = S % DELTA == 0 ? DELTA : S % DELTA;
  localparam int RS_DELTA = DELTA;
  localparam int CLBU_NB  = (S + DELTA-1) / DELTA;

  localparam int LPB_NB = 1;
  localparam int BWD_PSI             = PSI / BWD_PSI_DIV;

  // Input Files
  localparam string FILE_DATA_TYPE           = "ascii_hex";
  localparam string FILE_BSK_PREFIX          = "input/bsk";
  localparam string FILE_TWD_OMG_RU_R_POW    = "input/twd_omg_ru_r_pow.dat";
  localparam string FILE_IN_DATA             = "input/decomp_ntt.dat";
  localparam string FILE_OUT_DATA_REF        = "input/ntt_acc.dat";
  localparam string TWD_PHRU_FILE_PREFIX     = "input/twd_phru";
  localparam string TWD_IFNL_FILE_PREFIX     = "input/twd_ifnl";
  localparam string FILE_REF_CLBU_IN_PREFIX  = "input/ntt_clbu_in";
  localparam string FILE_REF_CLBU_OUT_PREFIX = "input/ntt_clbu_out";
  localparam string FILE_BATCH_CMD           = "input/batch_cmd.dat";

/*
initial begin
  $display("BR_LOOP_NB=%d",BR_LOOP_NB);
  $display("BSK_INST_BR_LOOP_NB=[%d,%d, %d]",BSK_INST_BR_LOOP_NB[2],BSK_INST_BR_LOOP_NB[1],BSK_INST_BR_LOOP_NB[0]);
  $display("BSK_INST_BR_LOOP_OFS=[%d,%d, %d]",BSK_INST_BR_LOOP_OFS[2],BSK_INST_BR_LOOP_OFS[1],BSK_INST_BR_LOOP_OFS[0]);
  $display("BSK_RAM_DEPTH=%d", BSK_RAM_DEPTH);
end
*/
  // ============================================================================================ //
  // Function
  // ============================================================================================ //
  function [BSK_SRV_NB-1:0][31:0] get_bsk_loop_nb (int br_loop_nb);
    bit [BSK_SRV_NB-1:0][31:0] result;
    int last_nb;
    last_nb = br_loop_nb;
    for (int i=0; i<BSK_SRV_NB-1; i=i+1) begin
      result[i] = br_loop_nb / BSK_SRV_NB;
      last_nb = last_nb - result[i];
    end
    result[BSK_SRV_NB-1] = last_nb;
    return result;
  endfunction

  function [BSK_SRV_NB-1:0][31:0] get_bsk_loop_ofs ([BSK_SRV_NB-1:0][31:0] bsk_inst_br_loop_nb);
    bit [BSK_SRV_NB-1:0][31:0] result;
    result[0] = 0;
    for (int i=1; i<BSK_SRV_NB; i=i+1)
      result[i] = result[i-1] + bsk_inst_br_loop_nb[i-1];
    return result;
  endfunction

  // ============================================================================================ //
  // Type
  // ============================================================================================ //
  typedef struct packed {
    logic                sob;
    logic                eob;
    logic                sol;
    logic                eol;
    logic                sog;
    logic                eog;
    logic [BPBS_ID_W-1:0] pbs_id;
    logic                last_pbs;
  } control_t;

  typedef struct packed {
    logic [        R/2-1:0][OP_W-1:0]                         wr_data;
  } twd_omg_ru_r_pow_wr_t;

  // ============================================================================================ //
  // clock, reset
  // ============================================================================================ //
  bit clk;
  bit a_rst_n;
  bit s_rst_n;

  initial begin
    clk     = 1'b0;
    a_rst_n = 1'b0;
    #ARST_ACTIVATION a_rst_n = 1'b1;
  end

  always begin
    #CLK_HALF_PERIOD clk = ~clk;
  end

  always_ff @(posedge clk) begin
    s_rst_n <= a_rst_n;
  end

  // ============================================================================================ //
  // Error
  // ============================================================================================ //
  bit error;

  bit                  error_out_ctrl;
  bit                  error_data;
  bit                  error_source_data_open;
  bit                  error_sink_data_open;
  bit [BSK_SRV_NB-1:0] error_source_bsk_wr_open;
  bit [CLBU_NB-1:0][DELTA-1:0] error_spy_clbu_in_fwd;
  bit [CLBU_NB-1:0][DELTA-1:0] error_spy_clbu_in_bwd;
  bit [CLBU_NB-1:0][DELTA-1:0] error_spy_clbu_out_fwd;
  bit [CLBU_NB-1:0][DELTA-1:0] error_spy_clbu_out_bwd;
  bit                  error_source_batch_open;

  assign error = error_out_ctrl
                | error_data
                | error_source_data_open
                | error_sink_data_open
                | |error_source_bsk_wr_open
                | |error_spy_clbu_in_fwd
                | |error_spy_clbu_out_fwd
                | |error_spy_clbu_in_bwd
                | |error_spy_clbu_out_bwd
                | error_source_batch_open;

  always_ff @(posedge clk) begin
    if (error) begin
      $display("%t > FAILURE !", $time);
      $finish;
    end
  end

  // ============================================================================================ //
  // input / output signals
  // ============================================================================================ //
  // Design under test -----------------------------------------------------------------------------
  // decomp -> ntt
  logic [     PSI-1:0][   R-1:0][     OP_W-1:0]                    decomp_ntt_data;
  logic [     PSI-1:0][   R-1:0]                                   decomp_ntt_data_vld;
  logic [     PSI-1:0][   R-1:0]                                   decomp_ntt_data_rdy;
  logic                                                            decomp_ntt_sob;
  logic                                                            decomp_ntt_eob;
  logic                                                            decomp_ntt_sol;
  logic                                                            decomp_ntt_eol;
  logic                                                            decomp_ntt_sog;
  logic                                                            decomp_ntt_eog;
  logic [BPBS_ID_W-1:0]                                             decomp_ntt_pbs_id;
  logic                                                            decomp_ntt_last_pbs;
  logic                                                            decomp_ntt_full_throughput;
  logic                                                            decomp_ntt_ctrl_vld;
  logic                                                            decomp_ntt_ctrl_rdy;
  // ntt -> acc
  logic [     PSI-1:0][   R-1:0][     OP_W-1:0]                    ntt_acc_data;
  logic [     PSI-1:0][   R-1:0]                                   ntt_acc_data_avail;
  logic                                                            ntt_acc_sob;
  logic                                                            ntt_acc_eob;
  logic                                                            ntt_acc_sol;
  logic                                                            ntt_acc_eol;
  logic                                                            ntt_acc_sog;
  logic                                                            ntt_acc_eog;
  logic [BPBS_ID_W-1:0]                                             ntt_acc_pbs_id;
  logic                                                            ntt_acc_ctrl_avail;
  // Twiddles -> ntt
  logic [         1:0][ R/2-1:0][     OP_W-1:0]                    twd_omg_ru_r_pow;  // Quasi-static
  logic [S-1:0][ PSI-1:0][R-1:1][OP_W-1:0]        twd_phi_ru_fwd;
  logic [S-1:0][ PSI-1:0]                         twd_phi_ru_fwd_vld;
  logic [S-1:0][ PSI-1:0]                         twd_phi_ru_fwd_rdy;
  logic [S-1:0][BWD_PSI-1:0][R-1:1][OP_W-1:0]     twd_phi_ru_bwd;
  logic [S-1:0][BWD_PSI-1:0]                      twd_phi_ru_bwd_vld;
  logic [S-1:0][BWD_PSI-1:0]                      twd_phi_ru_bwd_rdy;
  logic [    BWD_PSI-1:0][   R-1:0][     OP_W-1:0]                 twd_intt_final;
  logic [    BWD_PSI-1:0][   R-1:0]                                twd_intt_final_vld;
  logic [    BWD_PSI-1:0][   R-1:0]                                twd_intt_final_rdy;
  // bsk_cl_ntt_bsk -> ntt
  logic [        PSI-1:0][   R-1:0][GLWE_K_P1-1:0][OP_W-1:0]       bsk_cl_ntt_bsk;
  logic [        PSI-1:0][   R-1:0][GLWE_K_P1-1:0]                 bsk_cl_ntt_vld;
  logic [        PSI-1:0][   R-1:0][GLWE_K_P1-1:0]                 bsk_cl_ntt_rdy;
  // Err flag
  logic [NTT_ERROR_W-1:0]                                          ntt_error;

  // acc -> broadcast
  logic [BR_BATCH_CMD_W-1:0]                                       batch_cmd;
  logic                                                            batch_cmd_avail;

  // Error
  logic [1:0][CLBU_NB-1:0][DELTA-1:0][TWD_PHRU_ERROR_NB-1:0]       twd_phru_error;

  logic [BSK_SRV_NB-1:0][SRV_ERROR_NB-1:0]                         bsk_error_server;
  logic [CLT_ERROR_NB-1:0]                                         bsk_error_client;

  // ============================================================================================ //
  // Design under test instance
  // ============================================================================================ //
  // -----------------------------------------------------------------------------------------------
  // ntt_core_with_matrix_multiplication_unfold_pcg
  // -----------------------------------------------------------------------------------------------
  ntt_core_with_matrix_multiplication_unfold_pcg_assembly #(
    .OP_W          (OP_W),
    .MOD_NTT       (MOD_NTT),
    .MOD_NTT_TYPE  (MOD_NTT_TYPE),
    .MOD_MULT_TYPE (MOD_MULT_TYPE),
    .MULT_TYPE     (MULT_TYPE    ),
    .REDUCT_TYPE   (REDUCT_TYPE  ),
    .PP_MOD_MULT_TYPE (PP_MOD_MULT_TYPE),
    .PP_MULT_TYPE     (PP_MULT_TYPE    ),
    .R             (R),
    .PSI           (PSI),
    .S             (S),
    .FWD_DELTA     (DELTA),
    .BWD_DELTA     (DELTA),
    .BWD_PSI_DIV   (BWD_PSI_DIV),
    .RAM_LATENCY   (RAM_LATENCY)
  ) ntt_core_with_matrix_multiplication_unfold_pcg (
    // System
    .clk                       (clk),
    .s_rst_n                   (s_rst_n),
    // decomp -> ntt
    .decomp_ntt_data           (decomp_ntt_data),
    .decomp_ntt_data_vld       (decomp_ntt_data_vld),
    .decomp_ntt_sob            (decomp_ntt_sob),
    .decomp_ntt_eob            (decomp_ntt_eob),
    .decomp_ntt_sol            (decomp_ntt_sol),
    .decomp_ntt_eol            (decomp_ntt_eol),
    .decomp_ntt_sog            (decomp_ntt_sog),
    .decomp_ntt_eog            (decomp_ntt_eog),
    .decomp_ntt_pbs_id         (decomp_ntt_pbs_id),
    .decomp_ntt_last_pbs       (decomp_ntt_last_pbs),
    .decomp_ntt_full_throughput(decomp_ntt_full_throughput),
    .decomp_ntt_ctrl_vld       (decomp_ntt_ctrl_vld),
    .decomp_ntt_ctrl_rdy       (decomp_ntt_ctrl_rdy),
    .decomp_ntt_data_rdy       (decomp_ntt_data_rdy),
    // data -> acc
    .ntt_acc_data              (ntt_acc_data),
    .ntt_acc_data_avail        (ntt_acc_data_avail),
    .ntt_acc_sob               (ntt_acc_sob),
    .ntt_acc_eob               (ntt_acc_eob),
    .ntt_acc_sol               (ntt_acc_sol),
    .ntt_acc_eol               (ntt_acc_eol),
    .ntt_acc_sog               (ntt_acc_sog),
    .ntt_acc_eog               (ntt_acc_eog),
    .ntt_acc_pbs_id            (ntt_acc_pbs_id),
    .ntt_acc_ctrl_avail        (ntt_acc_ctrl_avail),
    // Twiddles
    .twd_omg_ru_r_pow          (twd_omg_ru_r_pow),
    .twd_phi_ru_fwd            (twd_phi_ru_fwd),
    .twd_phi_ru_fwd_vld        (twd_phi_ru_fwd_vld),
    .twd_phi_ru_fwd_rdy        (twd_phi_ru_fwd_rdy),
    .twd_phi_ru_bwd            (twd_phi_ru_bwd),
    .twd_phi_ru_bwd_vld        (twd_phi_ru_bwd_vld),
    .twd_phi_ru_bwd_rdy        (twd_phi_ru_bwd_rdy),
    .twd_intt_final            (twd_intt_final),
    .twd_intt_final_vld        (twd_intt_final_vld),
    .twd_intt_final_rdy        (twd_intt_final_rdy),
    // bootstrapping key
    .bsk                       (bsk_cl_ntt_bsk),
    .bsk_vld                   (bsk_cl_ntt_vld),
    .bsk_rdy                   (bsk_cl_ntt_rdy),
    // Error flags
    .ntt_error                 (ntt_error)
  );

  //-------------------------------------------------------------------------------------------------
  // twiddle_intt_final_manager
  //-------------------------------------------------------------------------------------------------
  twiddle_intt_final_manager
  #(
    .FILE_TWD_PREFIX(TWD_IFNL_FILE_PREFIX),
    .OP_W        (OP_W),
    .R           (R),
    .PSI         (BWD_PSI),
    .S           (S),
    .ROM_LATENCY (ROM_LATENCY)
  )
  twiddle_intt_final_manager
  (
    .clk                (clk),
    .s_rst_n            (s_rst_n),

    .twd_intt_final     (twd_intt_final),
    .twd_intt_final_vld (twd_intt_final_vld),
    .twd_intt_final_rdy (twd_intt_final_rdy)
  );

  //-------------------------------------------------------------------------------------------------
  // twiddle_phi_ru_manager
  //-------------------------------------------------------------------------------------------------
  generate
    for (genvar gen_c=0; gen_c<CLBU_NB-1; gen_c=gen_c+1) begin : gen_twd_phru
      for (genvar gen_d=0; gen_d<RS_DELTA; gen_d=gen_d+1) begin : gen_twd_phru_d_loop
        twiddle_phi_ru_manager
        #(
          .FILE_TWD_PREFIX($sformatf("%s_C%0d_D%0d_fwd",TWD_PHRU_FILE_PREFIX, gen_c, gen_d)),
          .OP_W        (OP_W),
          .R           (R),
          .PSI         (PSI),
          .S           (S),
          .ROM_LATENCY (ROM_LATENCY),
          .S_INIT      (S-1-(gen_c*RS_DELTA+gen_d)),
          .S_DEC       (0),
          .LPB_NB      (LPB_NB)
        )
        twiddle_phi_ru_manager_fwd
        (
          .clk             (clk),
          .s_rst_n         (s_rst_n),

          .twd_phi_ru      (twd_phi_ru_fwd[(gen_c*RS_DELTA + gen_d)]),
          .twd_phi_ru_vld  (twd_phi_ru_fwd_vld[(gen_c*RS_DELTA + gen_d)]),
          .twd_phi_ru_rdy  (twd_phi_ru_fwd_rdy[(gen_c*RS_DELTA + gen_d)]),

          .batch_cmd       (batch_cmd),
          .batch_cmd_avail (batch_cmd_avail),

          .error           (twd_phru_error[0][gen_c][gen_d])
        );

        twiddle_phi_ru_manager
        #(
          .FILE_TWD_PREFIX($sformatf("%s_C%0d_D%0d_bwd",TWD_PHRU_FILE_PREFIX, gen_c, gen_d)),
          .OP_W        (OP_W),
          .R           (R),
          .PSI         (BWD_PSI),
          .S           (S),
          .ROM_LATENCY (ROM_LATENCY),
          .S_INIT      (2*S-1-(gen_c*RS_DELTA+gen_d)),
          .S_DEC       (0),
          .LPB_NB      (LPB_NB)
        )
        twiddle_phi_ru_manager_bwd
        (
          .clk             (clk),
          .s_rst_n         (s_rst_n),

          .twd_phi_ru      (twd_phi_ru_bwd[(gen_c*RS_DELTA + gen_d)]),
          .twd_phi_ru_vld  (twd_phi_ru_bwd_vld[(gen_c*RS_DELTA + gen_d)]),
          .twd_phi_ru_rdy  (twd_phi_ru_bwd_rdy[(gen_c*RS_DELTA + gen_d)]),

          .batch_cmd       (batch_cmd),
          .batch_cmd_avail (batch_cmd_avail),

          .error           (twd_phru_error[1][gen_c][gen_d])
        );

      end
    end
    for (genvar gen_d=0; gen_d<LS_DELTA; gen_d=gen_d+1) begin : gen_twd_phru_d_loop
      twiddle_phi_ru_manager
      #(
        .FILE_TWD_PREFIX($sformatf("%s_C%0d_D%0d_fwd",TWD_PHRU_FILE_PREFIX, CLBU_NB-1, gen_d)),
        .OP_W        (OP_W),
        .R           (R),
        .PSI         (PSI),
        .S           (S),
        .ROM_LATENCY (ROM_LATENCY),
        .S_INIT      (S-1-((CLBU_NB-1)*RS_DELTA+gen_d)),
        .S_DEC       (0),
        .LPB_NB      (LPB_NB)
      )
      twiddle_phi_ru_manager_fwd_ls
      (
        .clk             (clk),
        .s_rst_n         (s_rst_n),

        .twd_phi_ru      (twd_phi_ru_fwd[((CLBU_NB-1)*RS_DELTA + gen_d)]),
        .twd_phi_ru_vld  (twd_phi_ru_fwd_vld[((CLBU_NB-1)*RS_DELTA + gen_d)]),
        .twd_phi_ru_rdy  (twd_phi_ru_fwd_rdy[((CLBU_NB-1)*RS_DELTA + gen_d)]),

        .batch_cmd       (batch_cmd),
        .batch_cmd_avail (batch_cmd_avail),

        .error           (twd_phru_error[0][CLBU_NB-1][gen_d])
      );

      twiddle_phi_ru_manager
      #(
        .FILE_TWD_PREFIX($sformatf("%s_C%0d_D%0d_bwd",TWD_PHRU_FILE_PREFIX, CLBU_NB-1, gen_d)),
        .OP_W        (OP_W),
        .R           (R),
        .PSI         (BWD_PSI),
        .S           (S),
        .ROM_LATENCY (ROM_LATENCY),
        .S_INIT      (2*S-1-((CLBU_NB-1)*RS_DELTA+gen_d)),
        .S_DEC       (0),
        .LPB_NB      (LPB_NB)
      )
      twiddle_phi_ru_manager_bwd_ls
      (
        .clk             (clk),
        .s_rst_n         (s_rst_n),

        .twd_phi_ru      (twd_phi_ru_bwd[((CLBU_NB-1)*RS_DELTA + gen_d)]),
        .twd_phi_ru_vld  (twd_phi_ru_bwd_vld[((CLBU_NB-1)*RS_DELTA + gen_d)]),
        .twd_phi_ru_rdy  (twd_phi_ru_bwd_rdy[((CLBU_NB-1)*RS_DELTA + gen_d)]),

        .batch_cmd       (batch_cmd),
        .batch_cmd_avail (batch_cmd_avail),

        .error           (twd_phru_error[1][CLBU_NB-1][gen_d])
      );
    end
  endgenerate

  //-------------------------------------------------------------------------------------------------
  // bsk_network
  //-------------------------------------------------------------------------------------------------
  logic                                   do_wr_bsk;
  logic                                   wr_bsk_done;
  tb_bsk_ntw_model
  #(
    .OP_W                (OP_W),
    .BSK_SRV_NB          (BSK_SRV_NB),
    .BSK_CLT_NB          (1),
    .BATCH_NB            (BATCH_NB),
    .BSK_INST_BR_LOOP_NB (BSK_INST_BR_LOOP_NB),
    .BSK_INST_BR_LOOP_OFS(BSK_INST_BR_LOOP_OFS),
    .FILE_BSK_PREFIX     (FILE_BSK_PREFIX),
    .FILE_DATA_TYPE      (FILE_DATA_TYPE),
    .RAM_LATENCY         (RAM_LATENCY),
    .URAM_LATENCY        (URAM_LATENCY)
  ) tb_bsk_ntw_model (
    .clk              (clk),
    .s_rst_n          (s_rst_n),

    .do_wr_bsk        (do_wr_bsk),
    .wr_bsk_done      (wr_bsk_done),

    .batch_cmd        (batch_cmd),
    .batch_cmd_avail  (batch_cmd_avail),

    .bsk_cl_ntt_bsk   (bsk_cl_ntt_bsk),
    .bsk_cl_ntt_vld   (bsk_cl_ntt_vld),
    .bsk_cl_ntt_rdy   (bsk_cl_ntt_rdy),

    .bsk_error_server (bsk_error_server),
    .bsk_error_client (bsk_error_client),
    .error_source_bsk_wr_open(error_source_bsk_wr_open)
  );

// ============================================================================================= --
// Scenario
// ============================================================================================= --
// --------------------------------------------------------------------------------------------- --
// Bench top sequence
// --------------------------------------------------------------------------------------------- --
// The scenario is the following :
// - Fill the BSK_RAM
// - Fill the twid intt final RAM
// - Fill the twid phi ru RAM
// - Process
  typedef enum { TOP_ST_IDLE,
                 TOP_ST_WR_BSK,
                 TOP_ST_PROCESS,
                 TOP_ST_WAIT_FLUSH,
                 TOP_ST_DONE,
                 XXX} top_state_e;

  top_state_e top_state;
  top_state_e next_top_state;
  logic   start; // equals 1 during 1 cycle after the reset
  integer batch_cmd_cnt;
  logic   cl_all_idle;

  always_ff @(posedge clk) begin
    if (!s_rst_n) top_state <= TOP_ST_IDLE;
    else          top_state <= next_top_state;
  end

  always_comb begin
    case(top_state)
      TOP_ST_IDLE:
        next_top_state = start ? TOP_ST_WR_BSK : top_state;
      TOP_ST_WR_BSK:
        next_top_state = wr_bsk_done ? TOP_ST_PROCESS : top_state;
      TOP_ST_PROCESS:
        next_top_state = (batch_cmd_cnt >= SIMU_BATCH_NB) ? TOP_ST_WAIT_FLUSH : top_state;
      TOP_ST_WAIT_FLUSH:
        next_top_state = cl_all_idle ? TOP_ST_DONE : top_state;
      TOP_ST_DONE:
        next_top_state = top_state;
      default:
        next_top_state = XXX;
   endcase
  end

  logic top_st_idle;
  logic top_st_wr_bsk;
  logic top_st_process;
  logic top_st_wait_flush;
  logic top_st_done;

  assign top_st_idle        = top_state == TOP_ST_IDLE;
  assign top_st_wr_bsk      = top_state == TOP_ST_WR_BSK;
  assign top_st_process     = top_state == TOP_ST_PROCESS;
  assign top_st_wait_flush  = top_state == TOP_ST_WAIT_FLUSH;
  assign top_st_done        = top_state == TOP_ST_DONE;

  logic top_do_process;
  assign top_do_process = top_st_process | top_st_wait_flush;

  always_ff @(posedge clk) begin
    if (top_st_wr_bsk && wr_bsk_done)           $display("%t > INFO: WR BSK done.", $time);
  end

  assign do_wr_bsk = top_st_wr_bsk;
// --------------------------------------------------------------------------------------------- --
// Bench client
// --------------------------------------------------------------------------------------------- --
// Here the clients are the command generators
// Each NTT core can process up to BATCH_NB pending commands.
  logic in_sample_batch_last; // DUT input sampling last element of the batch
  logic out_sample_batch_last; // DUT output sampling last element of the batch
  logic do_send_data;

  assign out_sample_batch_last = ntt_acc_ctrl_avail & ntt_acc_eob;
  assign in_sample_batch_last  = decomp_ntt_ctrl_vld & decomp_ntt_ctrl_rdy & decomp_ntt_eob;

  tb_batch_cmd_gen_model
  #(
    .SIMU_BATCH_NB  (SIMU_BATCH_NB),
    .BATCH_NB        (BATCH_NB),
    .FILE_BATCH_CMD  (FILE_BATCH_CMD),
    .FILE_DATA_TYPE  (FILE_DATA_TYPE),
    .DATA_RAND_RANGE (DATA_RAND_RANGE),
    .BATCH_DLY       (BATCH_DLY)
  ) tb_batch_cmd_gen_model (
    .clk                     (clk),
    .s_rst_n                 (s_rst_n),

    .run                     (top_st_process), // (1) Send batch command.

    .in_sample_batch_last    (in_sample_batch_last),
    .out_sample_batch_last   (out_sample_batch_last),

    .batch_cmd               (batch_cmd  ),
    .batch_cmd_avail         (batch_cmd_avail),
    .batch_cmd_cnt           (batch_cmd_cnt),
    .do_send_data            (do_send_data),
    .cl_all_idle             (cl_all_idle),

    .error_source_batch_open (error_source_batch_open)
  );

//-------------------------------------------------------------------------------------------------
// twd_omg_ru_r_pow
//-------------------------------------------------------------------------------------------------
  generate
    if (R > 2) begin : gen_omg_ru_r_pow_R_gt_2
      read_data #(.DATA_W($size(twd_omg_ru_r_pow_wr_t))) rdata_twd_omg_ru    = new(.filename(FILE_TWD_OMG_RU_R_POW), .data_type(FILE_DATA_TYPE));

      initial begin
        // read_data
        if (!rdata_twd_omg_ru.open()) begin
          $display("%t > ERROR: opening file %0s failed\n", $time, FILE_TWD_OMG_RU_R_POW);
          $finish;
        end
        rdata_twd_omg_ru.start;
        twd_omg_ru_r_pow[0] = rdata_twd_omg_ru.get_cur_data;
        twd_omg_ru_r_pow[1] = rdata_twd_omg_ru.get_next_data;
      end

    end
    else begin // R == 2
      assign twd_omg_ru_r_pow     = 'x;// should not be used
    end
  endgenerate

// --------------------------------------------------------------------------------------------- --
// Control input and reference
// --------------------------------------------------------------------------------------------- --
// Build the stimuli.
  control_t         control_in_q[$];
  control_t         control_ref_q[$];
  int pbs_nb_a [SIMU_BATCH_NB];

  read_data #(.DATA_W(32)) rdata_batch_cmd = new(.filename(FILE_BATCH_CMD), .data_type(FILE_DATA_TYPE));

  initial begin
    int pbs_nb;
    if (!rdata_batch_cmd.open()) begin
      $display("%t > ERROR: opening file %0s failed\n", $time, FILE_BATCH_CMD);
      $finish;
    end
    rdata_batch_cmd.start;
    pbs_nb = rdata_batch_cmd.get_cur_data;
    for (int batch_id=0; batch_id<SIMU_BATCH_NB; batch_id=batch_id+1) begin
      pbs_nb_a[batch_id] = pbs_nb;
      pbs_nb = rdata_batch_cmd.get_next_data;
      for (int pbs_id=0; pbs_id < pbs_nb_a[batch_id]; pbs_id=pbs_id+1) begin
        for (int stg_iter=0; stg_iter<STG_ITER_NB; stg_iter=stg_iter+1) begin
          for (int intl_idx=0; intl_idx<INTL_L; intl_idx=intl_idx+1) begin
            control_t c;
            logic last_pbs;
            logic first_pbs;
            logic last_stg_iter;
            logic first_stg_iter;
            logic last_intl_idx;
            logic first_intl_idx;

            // control
            last_pbs       = pbs_id == pbs_nb_a[batch_id] - 1;
            first_pbs      = pbs_id == 0;
            last_stg_iter  = stg_iter == STG_ITER_NB-1;
            first_stg_iter = stg_iter == 0;
            last_intl_idx  = intl_idx == INTL_L-1;
            first_intl_idx = intl_idx == 0;

            c.sob = (first_pbs & first_stg_iter & first_intl_idx);
            c.eob = (last_pbs  & last_stg_iter  & last_intl_idx);
            c.sol = first_intl_idx;
            c.eol = last_intl_idx;
            c.sog = first_stg_iter & first_intl_idx;
            c.eog = last_stg_iter  & last_intl_idx;
            c.pbs_id  = pbs_id;
            c.last_pbs  = last_pbs;
            control_in_q.push_back(c);
            if (intl_idx < GLWE_K_P1) begin
              last_intl_idx  = intl_idx == GLWE_K_P1-1;
              c.sob = (first_pbs & first_stg_iter & first_intl_idx);
              c.eob = (last_pbs  & last_stg_iter  & last_intl_idx);
              c.sol = first_intl_idx;
              c.eol = last_intl_idx;
              c.sog = first_stg_iter & first_intl_idx;
              c.eog = last_stg_iter  & last_intl_idx;
              c.pbs_id  = pbs_id;
              c.last_pbs  = last_pbs;
              control_ref_q.push_back(c);
            end
          end
        end
      end
    end
  end // initial

// ============================================================================================== --
// Input
// ============================================================================================== --
  logic full_throughput;
  logic full_throughputD;
  logic data_vld;
  logic data_rdy;
  logic [$clog2(DATA_RAND_RANGE)-1:0] data_throughput;

  logic rand_full_throughput;
  logic data_vld_tmp;
  int rand_val;

  always_ff @(posedge clk) begin
    rand_val             <= $urandom;
    rand_full_throughput <= (rand_val & 'h3FF) == 0;
  end

  assign full_throughputD = ((decomp_ntt_ctrl_vld && decomp_ntt_ctrl_rdy && decomp_ntt_eob)
                              || !decomp_ntt_full_throughput) ?
                                  rand_full_throughput : full_throughput;

  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      full_throughput <= 1;
    end
    else begin
      full_throughput <= full_throughputD;
    end
  end

  assign data_vld_tmp = top_do_process & do_send_data;

  assign decomp_ntt_ctrl_vld        = data_vld & data_vld_tmp;
  assign data_rdy                   = decomp_ntt_ctrl_rdy & data_vld_tmp;
  assign decomp_ntt_data_vld        = {PSI*R{decomp_ntt_ctrl_vld}};
  assign decomp_ntt_full_throughput = full_throughput;

  assign data_throughput = full_throughput ? DATA_RAND_RANGE : DATA_RAND_RANGE / 4;

  stream_source
  #(
    .FILENAME   (FILE_IN_DATA),
    .DATA_TYPE  (FILE_DATA_TYPE),
    .DATA_W     (PSI*R*OP_W),
    .RAND_RANGE (DATA_RAND_RANGE),
    .KEEP_VLD   (1),
    .MASK_DATA  ("x")
  )
  source_data
  (
      .clk        (clk),
      .s_rst_n    (s_rst_n),

      .data       (decomp_ntt_data),
      .vld        (data_vld),
      .rdy        (data_rdy),

      .throughput (data_throughput)
  );

  // control
  always_ff @(posedge clk)
    if (!s_rst_n)
      start <= 1;
    else
      start <= 0;

  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      decomp_ntt_sob      <= 'x;
      decomp_ntt_eob      <= 'x;
      decomp_ntt_sol      <= 'x;
      decomp_ntt_eol      <= 'x;
      decomp_ntt_sog      <= 'x;
      decomp_ntt_eog      <= 'x;
      decomp_ntt_last_pbs <= 'x;
      decomp_ntt_pbs_id   <= 'x;
    end
    else if (start || (decomp_ntt_ctrl_vld && decomp_ntt_ctrl_rdy)) begin
      control_t c;
      c = control_in_q.pop_front();
      decomp_ntt_sob      <= c.sob    ;
      decomp_ntt_eob      <= c.eob    ;
      decomp_ntt_sol      <= c.sol    ;
      decomp_ntt_eol      <= c.eol    ;
      decomp_ntt_sog      <= c.sog    ;
      decomp_ntt_eog      <= c.eog    ;
      decomp_ntt_last_pbs <= c.last_pbs;
      decomp_ntt_pbs_id   <= c.pbs_id ;
    end
  end

  initial begin
    error_source_data_open = 1'b0;
    if (!source_data.open()) begin
      $display("%t > ERROR: Opening data stream source", $time);
      error_source_data_open = 1'b1;
    end
    source_data.start(0);
  end

// ============================================================================================ //
// Check output data
// ============================================================================================ //
  stream_sink
  #(
    .FILENAME_REF   (FILE_OUT_DATA_REF),
    .DATA_TYPE_REF  (FILE_DATA_TYPE),
    .FILENAME       (""),
    .DATA_TYPE      (FILE_DATA_TYPE),
    .DATA_W         (PSI*R*OP_W),
    .RAND_RANGE     (1),
    .KEEP_RDY       (1)
  )
  sink_data
  (
      .clk        (clk),
      .s_rst_n    (s_rst_n),

      .data       (ntt_acc_data),
      .vld        (ntt_acc_ctrl_avail),
      .rdy        (/*UNUSED*/),

      .error      (error_data),
      .throughput (1) // 100%
  );

initial begin
  error_sink_data_open = 1'b0;
  // active spy and write
  sink_data.set_do_ref(1);
  if (!sink_data.open()) begin
      $display("%t > ERROR: Opening data stream sink", $time);
      error_sink_data_open = 1'b1;
  end
  sink_data.start(0);
end

logic[PSI-1:0][R-1:0][OP_W-1:0] sink_ref;
assign sink_ref = sink_data.stream_spy.data_ref;

// ============================================================================================ //
// Check output control signals
// ============================================================================================ //
  always_ff @(posedge clk) begin
    if (!s_rst_n)
      error_out_ctrl <= 0;
    else begin
      if (ntt_acc_ctrl_avail) begin
        control_t                        c;
        c = control_ref_q.pop_front();
        assert(ntt_acc_sob    == c.sob
               && ntt_acc_eob    == c.eob
               && ntt_acc_sol    == c.sol
               && ntt_acc_eol    == c.eol
               && ntt_acc_sog    == c.sog
               && ntt_acc_eog    == c.eog
               && ntt_acc_pbs_id == c.pbs_id)
        else begin
          $display("%t > ERROR: acc output mismatches.", $time);
          $display("  sob : exp=%1d seen=%1d",c.sob,ntt_acc_sob);
          $display("  eob : exp=%1d seen=%1d",c.eob,ntt_acc_eob);
          $display("  sol : exp=%1d seen=%1d",c.sol,ntt_acc_sol);
          $display("  eol : exp=%1d seen=%1d",c.eol,ntt_acc_eol);
          $display("  sog : exp=%1d seen=%1d",c.sog,ntt_acc_sog);
          $display("  eog : exp=%1d seen=%1d",c.eog,ntt_acc_eog);
          $display("  pbs_id : exp=%1d seen=%1d",c.pbs_id,ntt_acc_pbs_id);
          error_out_ctrl <= 1;
        end
      end
    end
  end
/***************************
// ============================================================================================ //
// Check internal data
// ============================================================================================ //
generate
  for (genvar gen_c=0; gen_c < CLBU_NB-1; gen_c=gen_c+1) begin : gen_spy_loop
    for (genvar gen_d=0; gen_d < RS_DELTA; gen_d=gen_d+1) begin : gen_spy_loop_delta
      stream_spy
      #(
        .FILENAME       (""),
        .DATA_TYPE      (FILE_DATA_TYPE),
        .FILENAME_REF   ($sformatf("%s_C%0d_D%0d_fwd.dat",FILE_REF_CLBU_IN_PREFIX,gen_c, gen_d)),
        .DATA_TYPE_REF  (FILE_DATA_TYPE),
        .DATA_W         (PSI*R*OP_W)
      ) stream_spy_clbu_in_fwd
      (
          .clk     (clk),
          .s_rst_n (s_rst_n),    // synchronous reset

          .data    (ntt_core_with_matrix_multiplication_unfold_pcg.gen_fwd_rs_stage[gen_c].ntt_core_wmm_clbu_pcg_fwd_rs.rdx_in_data[gen_d]),
          .vld     (ntt_core_with_matrix_multiplication_unfold_pcg.gen_fwd_rs_stage[gen_c].ntt_core_wmm_clbu_pcg_fwd_rs.rdx_in_avail[gen_d][0]),
          .rdy     (1'b1),

          .error   (error_spy_clbu_in_fwd[gen_c][gen_d])
      );

      stream_spy
      #(
        .FILENAME       (""),
        .DATA_TYPE      (FILE_DATA_TYPE),
        .FILENAME_REF   ($sformatf("%s_C%0d_D%0d_fwd.dat",FILE_REF_CLBU_OUT_PREFIX,gen_c, gen_d)),
        .DATA_TYPE_REF  (FILE_DATA_TYPE),
        .DATA_W         (PSI*R*OP_W)
      ) stream_spy_clbu_out_fwd
      (
          .clk     (clk),
          .s_rst_n (s_rst_n),    // synchronous reset

          .data    (ntt_core_with_matrix_multiplication_unfold_pcg.gen_fwd_rs_stage[gen_c].ntt_core_wmm_clbu_pcg_fwd_rs.rdx_out_data[gen_d]),
          .vld     (ntt_core_with_matrix_multiplication_unfold_pcg.gen_fwd_rs_stage[gen_c].ntt_core_wmm_clbu_pcg_fwd_rs.rdx_out_avail[gen_d][0]),
          .rdy     (1'b1),

          .error   (error_spy_clbu_out_fwd[gen_c][gen_d])
      );

      stream_spy
      #(
        .FILENAME       (""),
        .DATA_TYPE      (FILE_DATA_TYPE),
        .FILENAME_REF   ($sformatf("%s_C%0d_D%0d_bwd.dat",FILE_REF_CLBU_IN_PREFIX,gen_c, gen_d)),
        .DATA_TYPE_REF  (FILE_DATA_TYPE),
        .DATA_W         (BWD_PSI*R*OP_W)
      ) stream_spy_clbu_in_bwd
      (
          .clk     (clk),
          .s_rst_n (s_rst_n),    // synchronous reset

          .data    (ntt_core_with_matrix_multiplication_unfold_pcg.gen_bwd_rs_stage[gen_c].ntt_core_wmm_clbu_pcg_bwd_rs.rdx_in_data[gen_d]),
          .vld     (ntt_core_with_matrix_multiplication_unfold_pcg.gen_bwd_rs_stage[gen_c].ntt_core_wmm_clbu_pcg_bwd_rs.rdx_in_avail[gen_d][0]),
          .rdy     (1'b1),

          .error   (error_spy_clbu_in_bwd[gen_c][gen_d])
      );

      stream_spy
      #(
        .FILENAME       (""),
        .DATA_TYPE      (FILE_DATA_TYPE),
        .FILENAME_REF   ($sformatf("%s_C%0d_D%0d_bwd.dat",FILE_REF_CLBU_OUT_PREFIX,gen_c, gen_d)),
        .DATA_TYPE_REF  (FILE_DATA_TYPE),
        .DATA_W         (BWD_PSI*R*OP_W)
      ) stream_spy_clbu_out_bwd
      (
          .clk     (clk),
          .s_rst_n (s_rst_n),    // synchronous reset

          .data    (ntt_core_with_matrix_multiplication_unfold_pcg.gen_bwd_rs_stage[gen_c].ntt_core_wmm_clbu_pcg_bwd_rs.rdx_out_data[gen_d]),
          .vld     (ntt_core_with_matrix_multiplication_unfold_pcg.gen_bwd_rs_stage[gen_c].ntt_core_wmm_clbu_pcg_bwd_rs.rdx_out_avail[gen_d][0]),
          .rdy     (1'b1),

          .error   (error_spy_clbu_out_bwd[gen_c][gen_d])
      );

      logic[PSI-1:0][R-1:0][OP_W-1:0] spy_clbu_in_fwd_ref;
      logic[PSI-1:0][R-1:0][OP_W-1:0] spy_clbu_out_fwd_ref;
      logic[BWD_PSI-1:0][R-1:0][OP_W-1:0] spy_clbu_in_bwd_ref;
      logic[BWD_PSI-1:0][R-1:0][OP_W-1:0] spy_clbu_out_bwd_ref;
      assign spy_clbu_in_fwd_ref  = stream_spy_clbu_in_fwd.data_ref;
      assign spy_clbu_out_fwd_ref = stream_spy_clbu_out_fwd.data_ref;
      assign spy_clbu_in_bwd_ref  = stream_spy_clbu_in_bwd.data_ref;
      assign spy_clbu_out_bwd_ref = stream_spy_clbu_out_bwd.data_ref;

      initial begin
        int r;
        // active spy and do not write
        stream_spy_clbu_in_fwd.set_do_ref(1);
        stream_spy_clbu_in_fwd.set_do_write(0);
        r = stream_spy_clbu_in_fwd.open();

        stream_spy_clbu_out_fwd.set_do_ref(1);
        stream_spy_clbu_out_fwd.set_do_write(0);
        r = stream_spy_clbu_out_fwd.open();

        stream_spy_clbu_in_bwd.set_do_ref(1);
        stream_spy_clbu_in_bwd.set_do_write(0);
        r = stream_spy_clbu_in_bwd.open();

        stream_spy_clbu_out_bwd.set_do_ref(1);
        stream_spy_clbu_out_bwd.set_do_write(0);
        r = stream_spy_clbu_out_bwd.open();

        stream_spy_clbu_in_fwd.start;
        stream_spy_clbu_out_fwd.start;
        stream_spy_clbu_in_bwd.start;
        stream_spy_clbu_out_bwd.start;
      end
    end
  end // for clbu_nb
  for (genvar gen_d=0; gen_d < LS_DELTA; gen_d=gen_d+1) begin : gen_spy_loop_delta_ls
      stream_spy
      #(
        .FILENAME       (""),
        .DATA_TYPE      (FILE_DATA_TYPE),
        .FILENAME_REF   ($sformatf("%s_C%0d_D%0d_fwd.dat",FILE_REF_CLBU_IN_PREFIX,CLBU_NB-1, gen_d)),
        .DATA_TYPE_REF  (FILE_DATA_TYPE),
        .DATA_W         (PSI*R*OP_W)
      ) stream_spy_clbu_in_fwd
      (
          .clk     (clk),
          .s_rst_n (s_rst_n),    // synchronous reset

          .data    (ntt_core_with_matrix_multiplication_unfold_pcg.ntt_core_wmm_clbu_pcg_fwd_ls.rdx_in_data[gen_d]),
          .vld     (ntt_core_with_matrix_multiplication_unfold_pcg.ntt_core_wmm_clbu_pcg_fwd_ls.rdx_in_avail[gen_d][0]),
          .rdy     (1'b1),

          .error   (error_spy_clbu_in_fwd[CLBU_NB-1][gen_d])
      );

      stream_spy
      #(
        .FILENAME       (""),
        .DATA_TYPE      (FILE_DATA_TYPE),
        .FILENAME_REF   ($sformatf("%s_C%0d_D%0d_fwd.dat",FILE_REF_CLBU_OUT_PREFIX,CLBU_NB-1, gen_d)),
        .DATA_TYPE_REF  (FILE_DATA_TYPE),
        .DATA_W         (PSI*R*OP_W)
      ) stream_spy_clbu_out_fwd
      (
          .clk     (clk),
          .s_rst_n (s_rst_n),    // synchronous reset

          .data    (ntt_core_with_matrix_multiplication_unfold_pcg.ntt_core_wmm_clbu_pcg_fwd_ls.rdx_out_data[gen_d]),
          .vld     (ntt_core_with_matrix_multiplication_unfold_pcg.ntt_core_wmm_clbu_pcg_fwd_ls.rdx_out_avail[gen_d][0]),
          .rdy     (1'b1),

          .error   (error_spy_clbu_out_fwd[CLBU_NB-1][gen_d])
      );

      stream_spy
      #(
        .FILENAME       (""),
        .DATA_TYPE      (FILE_DATA_TYPE),
        .FILENAME_REF   ($sformatf("%s_C%0d_D%0d_bwd.dat",FILE_REF_CLBU_IN_PREFIX,CLBU_NB-1, gen_d)),
        .DATA_TYPE_REF  (FILE_DATA_TYPE),
        .DATA_W         (BWD_PSI*R*OP_W)
      ) stream_spy_clbu_in_bwd
      (
          .clk     (clk),
          .s_rst_n (s_rst_n),    // synchronous reset

          .data    (ntt_core_with_matrix_multiplication_unfold_pcg.ntt_core_wmm_clbu_pcg_bwd_ls.rdx_in_data[gen_d]),
          .vld     (ntt_core_with_matrix_multiplication_unfold_pcg.ntt_core_wmm_clbu_pcg_bwd_ls.rdx_in_avail[gen_d][0]),
          .rdy     (1'b1),

          .error   (error_spy_clbu_in_bwd[CLBU_NB-1][gen_d])
      );

      stream_spy
      #(
        .FILENAME       (""),
        .DATA_TYPE      (FILE_DATA_TYPE),
        .FILENAME_REF   ($sformatf("%s_C%0d_D%0d_bwd.dat",FILE_REF_CLBU_OUT_PREFIX,CLBU_NB-1, gen_d)),
        .DATA_TYPE_REF  (FILE_DATA_TYPE),
        .DATA_W         (BWD_PSI*R*OP_W)
      ) stream_spy_clbu_out_bwd
      (
          .clk     (clk),
          .s_rst_n (s_rst_n),    // synchronous reset

          .data    (ntt_core_with_matrix_multiplication_unfold_pcg.ntt_core_wmm_clbu_pcg_bwd_ls.rdx_out_data[gen_d]),
          .vld     (ntt_core_with_matrix_multiplication_unfold_pcg.ntt_core_wmm_clbu_pcg_bwd_ls.rdx_out_avail[gen_d][0]),
          .rdy     (1'b1),

          .error   (error_spy_clbu_out_bwd[CLBU_NB-1][gen_d])
      );

      logic[PSI-1:0][R-1:0][OP_W-1:0] spy_clbu_in_fwd_ref;
      logic[PSI-1:0][R-1:0][OP_W-1:0] spy_clbu_out_fwd_ref;
      logic[BWD_PSI-1:0][R-1:0][OP_W-1:0] spy_clbu_in_bwd_ref;
      logic[BWD_PSI-1:0][R-1:0][OP_W-1:0] spy_clbu_out_bwd_ref;
      assign spy_clbu_in_fwd_ref  = stream_spy_clbu_in_fwd.data_ref;
      assign spy_clbu_out_fwd_ref = stream_spy_clbu_out_fwd.data_ref;
      assign spy_clbu_in_bwd_ref  = stream_spy_clbu_in_bwd.data_ref;
      assign spy_clbu_out_bwd_ref = stream_spy_clbu_out_bwd.data_ref;

      initial begin
        int r;
        // active spy and do not write
        stream_spy_clbu_in_fwd.set_do_ref(1);
        stream_spy_clbu_in_fwd.set_do_write(0);
        r = stream_spy_clbu_in_fwd.open();

        stream_spy_clbu_out_fwd.set_do_ref(1);
        stream_spy_clbu_out_fwd.set_do_write(0);
        r = stream_spy_clbu_out_fwd.open();

        stream_spy_clbu_in_bwd.set_do_ref(1);
        stream_spy_clbu_in_bwd.set_do_write(0);
        r = stream_spy_clbu_in_bwd.open();

        stream_spy_clbu_out_bwd.set_do_ref(1);
        stream_spy_clbu_out_bwd.set_do_write(0);
        r = stream_spy_clbu_out_bwd.open();

        stream_spy_clbu_in_fwd.start;
        stream_spy_clbu_out_fwd.start;
        stream_spy_clbu_in_bwd.start;
        stream_spy_clbu_out_bwd.start;
      end
  end
endgenerate
********************/
// ============================================================================================ //
// End of test
// ============================================================================================ //
  bit end_of_test;

  initial begin
    wait (end_of_test);
    @(posedge clk);
    $display("%t > SUCCEED !", $time);
    $finish;
  end


  integer out_batch_cnt;
  always_ff @(posedge clk)
    if (!s_rst_n) out_batch_cnt <= 0;
    else if (ntt_acc_ctrl_avail && ntt_acc_eob) out_batch_cnt <= out_batch_cnt + 1;

  initial begin
    end_of_test = 0;
    wait (source_data.eof);
    $display("%t > INFO: No more input", $time);
    @(posedge clk);
    wait (out_batch_cnt == SIMU_BATCH_NB);
    $display("%t > INFO: No more output", $time);
    @(posedge clk);
    end_of_test = 1'b1;
  end

endmodule
