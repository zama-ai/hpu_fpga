// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Compute the external multiplication with BSK in GF64 domain.
// The modular reduction is done partially.
//
// The input data are received interleaved.Therefore, once they are multiplied by the corresponding
// BSK, they are accumulated, until eol is seen.
//
// ==============================================================================================

module ntt_core_gf64_pp_core
  import common_definition_pkg::*;
  import param_tfhe_pkg::*;
  import pep_common_param_pkg::*;
#(
  parameter int        MOD_NTT_W        = 64, // For simulation
  parameter arith_mult_type_e MULT_TYPE = MULT_CORE,
  parameter bit        IN_PIPE          = 1'b1 // Recommended
) (
  // System interface
  input                                       clk,
  input                                       s_rst_n,
  // Input data
  input  logic [MOD_NTT_W+1:0]                in_data, // 2s complement
  input  logic                                in_avail,
  input  logic                                in_sob,
  input  logic                                in_eob,
  input  logic                                in_sol,
  input  logic                                in_eol,
  input  logic                                in_sos,
  input  logic                                in_eos,
  input  logic [BPBS_ID_W-1:0]                in_pbs_id,
  // Output data
  output logic [MOD_NTT_W+1:0]                out_data, // 2s complement
  output logic                                out_avail,
  output logic                                out_sob,
  output logic                                out_eob,
  output logic                                out_sol,
  output logic                                out_eol,
  output logic                                out_sos,
  output logic                                out_eos,
  output logic [BPBS_ID_W-1:0]                out_pbs_id,

  // Matrix factors : BSK
  input  logic [GLWE_K_P1-1:0][MOD_NTT_W-1:0] bsk,
  input  logic [GLWE_K_P1-1:0]                bsk_vld,
  output logic [GLWE_K_P1-1:0]                bsk_rdy,

  output logic                                error
);

  // ============================================================================================ //
  // localparam
  // ============================================================================================ //
  localparam int OP_W = MOD_NTT_W + 2;

  // ============================================================================================ //
  // Structure
  // ============================================================================================ //
  typedef struct packed {
    logic                 sol;
    logic                 eol;
    logic                 sob;
    logic                 eob;
    logic                 sos;
    logic                 eos;
    logic [BPBS_ID_W-1:0] pbs_id;
  } control_t;

  typedef struct packed {
    logic                 sob;
    logic                 eob;
    logic                 sos;
    logic                 eos;
    logic [BPBS_ID_W-1:0] pbs_id;
  } short_control_t;

  // ============================================================================================ //
  // Signals
  // ============================================================================================ //
  control_t in_ctrl;

  assign in_ctrl.sol    = in_sol   ;
  assign in_ctrl.eol    = in_eol   ;
  assign in_ctrl.sob    = in_sob   ;
  assign in_ctrl.eob    = in_eob   ;
  assign in_ctrl.sos    = in_sos   ;
  assign in_ctrl.eos    = in_eos   ;
  assign in_ctrl.pbs_id = in_pbs_id;

  // ============================================================================================ //
  // Multiplication
  // ============================================================================================ //
  // Multiply with all the GLWE_K_P1 BSK coefficients
  // The GLWE_K_P1 coef of the same BSK element are sent one at the same time : one after the other.
  // Therefore, we need to shift register the input.
  logic [GLWE_K_P1-1:0][OP_W-1:0] in_data_sr;
  logic [GLWE_K_P1-1:0][OP_W-1:0] in_data_sr_tmp;
  logic [GLWE_K_P1-1:0][OP_W-1:0] in_data_sr_tmpD;
  control_t [GLWE_K_P1-1:0]       in_ctrl_sr;
  control_t [GLWE_K_P1-1:0]       in_ctrl_sr_tmp;
  control_t [GLWE_K_P1-1:0]       in_ctrl_sr_tmpD;
  logic [GLWE_K_P1-1:0]           in_avail_sr;
  logic [GLWE_K_P1-1:0]           in_avail_sr_tmp;
  logic [GLWE_K_P1-1:0]           in_avail_sr_tmpD;

  assign in_data_sr       = in_data_sr_tmpD;
  assign in_ctrl_sr       = in_ctrl_sr_tmpD;
  assign in_avail_sr      = in_avail_sr_tmpD;

  assign in_data_sr_tmpD  = {in_data_sr_tmp[GLWE_K_P1-2:0],in_data};
  assign in_ctrl_sr_tmpD  = {in_ctrl_sr_tmp[GLWE_K_P1-2:0],in_ctrl};
  assign in_avail_sr_tmpD = {in_avail_sr_tmp[GLWE_K_P1-2:0],in_avail};

  always_ff @(posedge clk) begin
    in_data_sr_tmp <= in_data_sr_tmpD;
    in_ctrl_sr_tmp <= in_ctrl_sr_tmpD;
  end

  always_ff @(posedge clk)
    if (!s_rst_n) in_avail_sr_tmp <= '0;
    else          in_avail_sr_tmp <= in_avail_sr_tmpD;

  logic [GLWE_K_P1-1:0][OP_W-1:0] s0_mult;
  control_t [GLWE_K_P1-1:0]       s0_ctrl;
  logic [GLWE_K_P1-1:0]           s0_avail;

  generate
    for (genvar gen_i=0; gen_i<GLWE_K_P1; gen_i=gen_i+1) begin : gen_mult_loop
      ntt_core_gf64_pmr_mult
      #(
        .MOD_NTT_W (MOD_NTT_W),
        .OP_W      (OP_W),
        .MULT_TYPE (MULT_TYPE),
        .IN_PIPE   (IN_PIPE),
        .SIDE_W    ($bits(control_t)),
        .RST_SIDE  (2'b00)
      ) ntt_core_gf64_pmr_mult (
        .clk       (clk),
        .s_rst_n   (s_rst_n),

        .a         (in_data_sr[gen_i]),
        .z         (s0_mult[gen_i]),

        .m         (bsk[gen_i]),
        .m_vld     (bsk_vld[gen_i]),
        .m_rdy     (bsk_rdy[gen_i]),

        .in_avail  (in_avail_sr[gen_i]),
        .out_avail (s0_avail[gen_i]),
        .in_side   (in_ctrl_sr[gen_i]),
        .out_side  (s0_ctrl[gen_i])
      );
    end
  endgenerate

  // ============================================================================================ //
  // Accumulation
  // ============================================================================================ //
  short_control_t                 s0_short_ctrl;

  logic [GLWE_K_P1-1:0][OP_W-1:0] s1_acc;
  short_control_t                 s1_short_ctrl;
  logic [GLWE_K_P1-1:0]           s1_avail;

  // The first mod_acc takes care of the delaying of the control signals.
  logic s0_sob_kept;
  logic s0_sos_kept;

  // /!\ Assumption : We assume that a batch and a stage last more than 1 cycle.
  // The control is only taken into account with eol. Therefore keep the start-of
  // information.
  always_ff @(posedge clk)
    if (s0_avail[0] && s0_ctrl[0].sol) begin
      s0_sob_kept <= s0_ctrl[0].sob;
      s0_sos_kept <= s0_ctrl[0].sos;
    end

  assign s0_short_ctrl.sob    = s0_sob_kept;
  assign s0_short_ctrl.eob    = s0_ctrl[0].eob;
  assign s0_short_ctrl.sos    = s0_sos_kept;
  assign s0_short_ctrl.eos    = s0_ctrl[0].eos;
  assign s0_short_ctrl.pbs_id = s0_ctrl[0].pbs_id;

  generate
    for (genvar gen_i=0; gen_i<GLWE_K_P1; gen_i=gen_i+1) begin : gen_acc_loop
      if (gen_i==0) begin : gen_0
        // contains the side part
        ntt_core_gf64_pmr_acc #(
          .MOD_NTT_W (MOD_NTT_W),
          .OP_W      (OP_W),
          .ELT_NB    (GLWE_K_P1*PBS_L),
          .IN_PIPE   (1'b0),
          .SIDE_W    ($bits(short_control_t)),
          .RST_SIDE  (2'b00)
        ) ntt_core_gf64_pmr_acc (
          .clk       (clk),
          .s_rst_n   (s_rst_n),

          .a         (s0_mult[gen_i]),
          .z         (s1_acc[gen_i]),

          .in_sol    (s0_ctrl[gen_i].sol),
          .in_eol    (s0_ctrl[gen_i].eol),
          .in_avail  (s0_avail[gen_i]),
          .out_avail (s1_avail[gen_i]),

          .in_side   (s0_short_ctrl),
          .out_side  (s1_short_ctrl)
        );
      end
      else begin : gen_no_0
        // contains the side part
        ntt_core_gf64_pmr_acc #(
          .MOD_NTT_W (MOD_NTT_W),
          .OP_W      (OP_W),
          .ELT_NB    (GLWE_K_P1*PBS_L),
          .IN_PIPE   (1'b0),
          .SIDE_W    ('0), /*UNUSED*/
          .RST_SIDE  (2'b00)/*UNUSED*/
        ) ntt_core_gf64_pmr_acc (
          .clk       (clk),
          .s_rst_n   (s_rst_n),

          .a         (s0_mult[gen_i]),
          .z         (s1_acc[gen_i]),

          .in_sol    (s0_ctrl[gen_i].sol),
          .in_eol    (s0_ctrl[gen_i].eol),
          .in_avail  (s0_avail[gen_i]),
          .out_avail (s1_avail[gen_i]),

          .in_side   ('x),/*UNUSED*/
          .out_side  ()   /*UNUSED*/
        );
      end
    end
  endgenerate

  // ============================================================================================ //
  // Control
  // ============================================================================================ //
  short_control_t  s1_out_short_ctrl;
  short_control_t  s1_out_short_ctrl_kept;
  short_control_t  s1_out_short_ctrl_keptD;

  assign s1_out_short_ctrl       = s1_out_short_ctrl_keptD;
  assign s1_out_short_ctrl_keptD = s1_avail[0] ? s1_short_ctrl : s1_out_short_ctrl_kept;

  always_ff @(posedge clk)
    s1_out_short_ctrl_kept <= s1_out_short_ctrl_keptD;

  // Control
  logic            s1_out_avail;
  logic            s1_out_eol;
  logic            s1_out_sol;
  logic [OP_W-1:0] s1_out_data;

  // Count the output
  logic [GLWE_K_P1_W-1:0] s1_out_cnt;
  logic [GLWE_K_P1_W-1:0] s1_out_cntD;

  assign s1_out_cntD = s1_out_avail ?
                          (s1_out_cnt == GLWE_K_P1-1) ? '0 : s1_out_cnt + 1 : s1_out_cnt;

  always_ff @(posedge clk)
    if (!s_rst_n) s1_out_cnt <= '0;
    else          s1_out_cnt <= s1_out_cntD;

  assign s1_out_avail = |s1_avail;
  assign s1_out_eol   = s1_avail[GLWE_K_P1-1];
  assign s1_out_sol   = s1_avail[0];
  assign s1_out_data  = s1_acc[s1_out_cnt];

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      if (s1_out_avail) begin
        assert(s1_avail[s1_out_cnt])
        else begin
          $fatal(1,"%t > ERROR: Desynchronization of PP data!", $time);
        end
      end

      assert($countones(s1_avail) <= 1)
      else begin
        $fatal(1,"%t > ERROR: Concurrent data in PP!", $time);
      end
    end
// pragma translate_on


  // ============================================================================================ //
  // Output
  // ============================================================================================ //
  always_ff @(posedge clk) begin
    out_data   <= s1_out_data;
    out_sol    <= s1_out_sol;
    out_eol    <= s1_out_eol;
    out_sos    <= s1_out_short_ctrl.sos & s1_out_sol;
    out_eos    <= s1_out_short_ctrl.eos & s1_out_eol;
    out_sob    <= s1_out_short_ctrl.sob & s1_out_sol & s1_out_short_ctrl.sos;
    out_eob    <= s1_out_short_ctrl.eob & s1_out_eol & s1_out_short_ctrl.eos;
    out_pbs_id <= s1_out_short_ctrl.pbs_id;
  end

  always_ff @(posedge clk)
    if (!s_rst_n) out_avail <= 1'b0;
    else          out_avail <= s1_out_avail;

  // ============================================================================================ //
  // Error
  // ============================================================================================ //
  logic errorD;

  assign errorD = |(!bsk_vld & bsk_rdy);

  always_ff @(posedge clk)
    if (!s_rst_n) error <= 1'b0;
    else          error <= errorD;


endmodule
