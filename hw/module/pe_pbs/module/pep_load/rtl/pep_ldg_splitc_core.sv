// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the GLWE data read from memory.
//
// ==============================================================================================

module pep_ldg_splitc_core
  import top_common_param_pkg::*;
  import param_tfhe_pkg::*;
  import pep_common_param_pkg::*;
  import ntt_core_common_param_pkg::*;

#(
  parameter  int COEF_NB       = 4,
  parameter  int HPSI_SET_ID   = 0,  // Indicates which of the two coef sets is processed here
  parameter  int MSPLIT_FACTOR = 2,
  localparam int HPSI          = MSPLIT_FACTOR * PSI / MSPLIT_DIV
)
(
  input  logic                                                     clk,        // clock
  input  logic                                                     s_rst_n,    // synchronous reset

  // From GRAM arbiter
  input  logic [GRAM_NB-1:0]                                       garb_ldg_avail_1h,

  // Command
  input  logic [LOAD_GLWE_CMD_W-1:0]                               in_cmd,
  input  logic                                                     in_cmd_vld,
  output logic                                                     in_cmd_rdy,
  output logic                                                     cmd_done,

  input  logic [COEF_NB-1:0][MOD_Q_W-1:0]                          in_data,
  input  logic                                                     in_data_vld,
  output logic                                                     in_data_rdy,

  // Write GLWE RAM
  // This memory is composed of GRAM_NB independent RAMs
  output logic [GRAM_NB-1:0][HPSI-1:0][R-1:0]                      glwe_ram_wr_en,
  output logic [GRAM_NB-1:0][HPSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0]  glwe_ram_wr_add,
  output logic [GRAM_NB-1:0][HPSI-1:0][R-1:0][MOD_Q_W-1:0]         glwe_ram_wr_data,

  output logic [MSPLIT_FACTOR-1:0]                                 ldg_rif_rcp_dur,

  output logic                                                     error
);

// ============================================================================================== //
// localparam
// ============================================================================================== //
  localparam int QPSI   = PSI/MSPLIT_DIV;
  localparam int Q_COEF = COEF_NB > QPSI*R ? QPSI*R : COEF_NB;
  localparam int QPSI_SET_ID_OFS = HPSI_SET_ID*(MSPLIT_DIV-MSPLIT_FACTOR);

  localparam int DONE_FIFO_DEPTH = 8; // TOREVIEW - pbs gap between the different qpsi

// ============================================================================================== //
// Signals
// ============================================================================================== //
  logic [MSPLIT_FACTOR-1:0][Q_COEF-1:0][MOD_Q_W-1:0]                          q_data;
  logic [MSPLIT_FACTOR-1:0]                                                   q_data_vld;
  logic [MSPLIT_FACTOR-1:0]                                                   q_data_rdy;

  logic [MSPLIT_FACTOR-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0]                     glwe_ram_wr_en_l;
  logic [MSPLIT_FACTOR-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0] glwe_ram_wr_add_l;
  logic [MSPLIT_FACTOR-1:0][GRAM_NB-1:0][QPSI-1:0][R-1:0][MOD_Q_W-1:0]        glwe_ram_wr_data_l;

  logic [MSPLIT_FACTOR-1:0][LOAD_GLWE_CMD_W-1:0]                              q_cmd;
  logic [MSPLIT_FACTOR-1:0]                                                   q_cmd_vld;
  logic [MSPLIT_FACTOR-1:0]                                                   q_cmd_rdy;

  logic [MSPLIT_FACTOR-1:0]                                                   q_cmd_done;

  always_comb
    for (int g=0; g<GRAM_NB; g=g+1) begin
      for (int i=0; i<MSPLIT_FACTOR; i=i+1) begin
        glwe_ram_wr_en[g][i*QPSI+:QPSI]   = glwe_ram_wr_en_l[i][g];
        glwe_ram_wr_add[g][i*QPSI+:QPSI]  = glwe_ram_wr_add_l[i][g];
        glwe_ram_wr_data[g][i*QPSI+:QPSI] = glwe_ram_wr_data_l[i][g];
      end
    end

// ============================================================================================== //
// Fork command
// ============================================================================================== //
  assign q_cmd        = {MSPLIT_FACTOR{in_cmd}};
  assign in_cmd_rdy   = &q_cmd_rdy;

  always_comb
    for (int i=0; i<MSPLIT_FACTOR; i=i+1) begin
      var [MSPLIT_FACTOR-1:0] mask;
      mask = 1 << i;
      q_cmd_vld[i] = in_cmd_vld & &(q_cmd_rdy | mask);
    end

// ============================================================================================== //
// Dispatch data
// ============================================================================================== //
  stream_dispatch
  #(
    .OP_W      (MOD_Q_W),
    .IN_COEF   (COEF_NB),
    .OUT_COEF  (Q_COEF),
    .OUT_NB    (MSPLIT_FACTOR),
    .DISP_COEF (R*QPSI),
    .IN_PIPE   (1'b1),
    .OUT_PIPE  (1'b1)
  ) stream_dispatch (
    .clk      (clk),
    .s_rst_n  (s_rst_n),

    .in_data  (in_data),
    .in_vld   (in_data_vld),
    .in_rdy   (in_data_rdy),

    .out_data (q_data),
    .out_vld  (q_data_vld),
    .out_rdy  (q_data_rdy)
  );

// ============================================================================================== //
// Write
// ============================================================================================== //
  logic [MSPLIT_FACTOR-1:0] cmd_done_error;

  logic [MSPLIT_FACTOR-1:0] cmd_done_vld;
  logic [MSPLIT_FACTOR-1:0] cmd_done_rdy;


  generate
    for (genvar gen_i=0; gen_i<MSPLIT_FACTOR; gen_i=gen_i+1) begin : gen_qpsi_loop
      localparam bit IN_DLY = (QPSI_SET_ID_OFS + gen_i)%2;
      pep_ldg_splitc_write
      #(
        .COEF_NB  (Q_COEF),
        .IN_PIPE  (1'b1),
        .IN_DLY   (IN_DLY)
      ) qpsi__pep_ldg_splitc_write (
        .clk               (clk),
        .s_rst_n           (s_rst_n),

        .garb_ldg_avail_1h (garb_ldg_avail_1h),

        .in_cmd            (q_cmd[gen_i]),
        .in_cmd_vld        (q_cmd_vld[gen_i]),
        .in_cmd_rdy        (q_cmd_rdy[gen_i]),
        .cmd_done          (q_cmd_done[gen_i]),

        .in_data           (q_data[gen_i]),
        .in_data_vld       (q_data_vld[gen_i]),
        .in_data_rdy       (q_data_rdy[gen_i]),

        .glwe_ram_wr_en    (glwe_ram_wr_en_l[gen_i]),
        .glwe_ram_wr_add   (glwe_ram_wr_add_l[gen_i]),
        .glwe_ram_wr_data  (glwe_ram_wr_data_l[gen_i]),

        .ldg_rif_rcp_dur   (ldg_rif_rcp_dur[gen_i])
      );

      common_lib_pulse_to_rdy_vld #(
        .FIFO_DEPTH (DONE_FIFO_DEPTH)
      ) common_lib_pulse_to_rdy_vld (
        .clk     (clk),
        .s_rst_n (s_rst_n),

        .in_pulse(q_cmd_done[gen_i]),

        .out_vld (cmd_done_vld[gen_i]),
        .out_rdy (cmd_done_rdy[gen_i]),

        .error   (cmd_done_error[gen_i])
      );

    end
  endgenerate

// ============================================================================================== //
// Command done
// ============================================================================================== //
  // Output
  logic cmd_doneD;

  assign cmd_doneD = &cmd_done_vld;

  always_comb
    for (int i=0; i<MSPLIT_FACTOR; i=i+1) begin
      var [MSPLIT_FACTOR-1:0] mask;
      mask = 1 << i;
      cmd_done_rdy[i] = &(cmd_done_vld | mask);
    end

  always_ff @(posedge clk)
    if (!s_rst_n) cmd_done <= 1'b0;
    else          cmd_done <= cmd_doneD;

// ============================================================================================== //
// Error
// ============================================================================================== //
  logic errorD;

  assign errorD = |cmd_done_error;

  always_ff @(posedge clk)
    if (!s_rst_n) error <= 1'b0;
    else          error <= errorD;

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      assert(error == 1'b0)
      else begin
        $fatal(1,"%t > ERROR: pep_ldg cmd_done fifo overflow!", $time);
      end
    end
// pragma translate_on

endmodule
