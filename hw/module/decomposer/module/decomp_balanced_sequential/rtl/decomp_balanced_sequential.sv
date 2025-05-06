// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// Bootstrap coefficient decomposition.
//
// Decomposition levels are output sequentially, from LSB to MSB.
// In order to save some logic, if several levels are necessary the input is split into several chunks.
// The chunks are gathered to reconstitute the RxPSI coefficients that are processed in parallel.
// All the RxPSI coefficients are decomposed in parallel.
// The output levels are in 2s complement.
// ==============================================================================================

module decomp_balanced_sequential
  import common_definition_pkg::*;
  import pep_common_param_pkg::*;
  import param_tfhe_pkg::*;
  import param_ntt_pkg::*;
  import ntt_core_common_param_pkg::*;
#(
  parameter  int CHUNK_NB           = PBS_L,   // Only CHUNK_NB = PBS_L is supported for now
  localparam int ACC_DECOMP_COEF_NB = (PSI*R + CHUNK_NB-1)/CHUNK_NB //$ceil(real(PSI)/real(CHUNK_NB))
) (
  input logic                                        clk,
  input logic                                        s_rst_n,

  // ACC <> Decomposer
  input logic                                        acc_decomp_ctrl_avail,
  input logic [ACC_DECOMP_COEF_NB-1:0]               acc_decomp_data_avail,
  input logic [ACC_DECOMP_COEF_NB-1:0][MOD_Q_W-1:0]  acc_decomp_data,
  input logic                                        acc_decomp_sob,
  input logic                                        acc_decomp_eob,
  input logic                                        acc_decomp_sog,
  input logic                                        acc_decomp_eog,
  input logic                                        acc_decomp_sol,
  input logic                                        acc_decomp_eol,
  input logic                                        acc_decomp_soc,
  input logic                                        acc_decomp_eoc,
  input logic [BPBS_ID_W-1:0]                        acc_decomp_pbs_id,
  input logic                                        acc_decomp_last_pbs,
  input logic                                        acc_decomp_full_throughput,

  // Decomposer <> NTT
  output logic                                       decomp_ntt_ctrl_avail,
  output logic [PSI-1:0][R-1:0]                      decomp_ntt_data_avail,
  output logic [PSI-1:0][R-1:0][PBS_B_W:0]           decomp_ntt_data, // 2s complement
  output logic                                       decomp_ntt_sob,
  output logic                                       decomp_ntt_eob,
  output logic                                       decomp_ntt_sog,
  output logic                                       decomp_ntt_eog,
  output logic                                       decomp_ntt_sol,
  output logic                                       decomp_ntt_eol,
  output logic [BPBS_ID_W-1:0]                       decomp_ntt_pbs_id,
  output logic                                       decomp_ntt_last_pbs,
  output logic                                       decomp_ntt_full_throughput,

  output logic                                       error
);
  // ============================================================================================== --
  // localparam
  // ============================================================================================== --
  localparam int CHUNK_W         = $clog2(CHUNK_NB) == 0 ? 1 : $clog2(CHUNK_NB);
  localparam int CLOSEST_REP_W   = PBS_L * PBS_B_W;
  localparam int CLOSEST_REP_OFS = MOD_Q_W - CLOSEST_REP_W;

  generate
    if (MOD_Q_W < (PBS_L*PBS_B_W)) begin
      $fatal(1, "> ERROR: Unsupported parameters: MOD_Q_W (%0d) must be greater or equal to PBS_L*PBS_B_W (%0d).",
             MOD_Q_W,PBS_L*PBS_B_W);
    end
  endgenerate

  // ============================================================================================== --
  // Type
  // ============================================================================================== --
  typedef struct packed {
    logic                 sob;
    logic                 eob;
    logic                 sog;
    logic                 eog;
    logic                 sol;
    logic                 eol;
    logic [BPBS_ID_W-1:0] pbs_id;
    logic                 last_pbs;
    logic                 full_throughput;
  } side_t;

  // ============================================================================================== --
  // Input Pipe
  // ============================================================================================== --
  logic                                        s0_ctrl_avail;
  logic [ACC_DECOMP_COEF_NB-1:0]               s0_data_avail;
  logic [ACC_DECOMP_COEF_NB-1:0][MOD_Q_W-1:0]  s0_data;
  side_t                                       s0_side;
  logic                                        s0_soc;
  logic                                        s0_eoc;

  side_t                                       acc_decomp_side;

  assign acc_decomp_side.sob             = acc_decomp_sob;
  assign acc_decomp_side.eob             = acc_decomp_eob;
  assign acc_decomp_side.sog             = acc_decomp_sog;
  assign acc_decomp_side.eog             = acc_decomp_eog;
  assign acc_decomp_side.sol             = acc_decomp_sol;
  assign acc_decomp_side.eol             = acc_decomp_eol;
  assign acc_decomp_side.pbs_id          = acc_decomp_pbs_id;
  assign acc_decomp_side.last_pbs        = acc_decomp_last_pbs;
  assign acc_decomp_side.full_throughput = acc_decomp_full_throughput;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      s0_ctrl_avail <= 1'b0;
      s0_data_avail <= '0;
    end
    else begin
      s0_ctrl_avail <= acc_decomp_ctrl_avail;
      s0_data_avail <= acc_decomp_data_avail;
    end

  always_ff @(posedge clk) begin
    s0_data <= acc_decomp_data;
    s0_side <= acc_decomp_side;
    s0_soc  <= acc_decomp_soc;
    s0_eoc  <= acc_decomp_eoc;
  end

  // ============================================================================================== --
  // Closest representation
  // ============================================================================================== --
  logic [ACC_DECOMP_COEF_NB-1:0][CLOSEST_REP_W-1:0] s0_closest_rep;
  logic [ACC_DECOMP_COEF_NB-1:0]                    s0_closest_rep_sign;

  generate
    if (CLOSEST_REP_W > 1) begin : gen_closest_rep_w_gt1
      always_comb
        for (int i=0; i<ACC_DECOMP_COEF_NB; i=i+1) begin
          logic frac;
          frac = s0_data[i][CLOSEST_REP_OFS-1];
          s0_closest_rep[i] = s0_data[i][CLOSEST_REP_OFS+:CLOSEST_REP_W] + frac;
          // Is negative if: closest_rep > base**level/2 or (closest_rep == base**level/2 and fraction == 1)
          s0_closest_rep_sign[i] = (s0_data[i][MOD_Q_W-1] & ((s0_data[i][CLOSEST_REP_OFS+:CLOSEST_REP_W-1] != '0) | frac))
                                  |(~s0_data[i][MOD_Q_W-1] & (s0_data[i][CLOSEST_REP_OFS+:CLOSEST_REP_W-1] == '1) & frac);
        end
    end
    else begin : gen_closest_rep_w_eq1
      always_comb
        for (int i=0; i<ACC_DECOMP_COEF_NB; i=i+1) begin
          logic frac;
          frac = s0_data[i][CLOSEST_REP_OFS-1];
          s0_closest_rep[i] = s0_data[i][CLOSEST_REP_OFS+:CLOSEST_REP_W] + frac;
          // Is negative if: closest_rep > base**level/2 or (closest_rep == base**level/2 and fraction == 1)
          s0_closest_rep_sign[i] = s0_closest_rep[i] & frac;
        end
    end
  endgenerate

  // ============================================================================================== --
  // Gather chunks
  // ============================================================================================== --
  logic [PSI*R-1:0][CLOSEST_REP_W-1:0] s1_closest_rep;
  logic [PSI*R-1:0]                    s1_closest_rep_sign;
  side_t                               s1_side;
  logic                                s1_ctrl_avail;
  logic [PSI*R-1:0]                    s1_data_avail;
  generate
    if (CHUNK_NB == 1) begin : gen_chunk_eq_1
      assign s1_closest_rep = s0_closest_rep;
      assign s1_closest_rep_sign = s0_closest_rep_sign;
      assign s1_side        = s0_side;
      assign s1_ctrl_avail  = s0_ctrl_avail;
      assign s1_data_avail  = s0_data_avail;
    end
    else begin : gen_chunk_gt_1
      logic [CHUNK_NB-1:0][ACC_DECOMP_COEF_NB-1:0][CLOSEST_REP_W:0] s0_acc;
      logic [CHUNK_NB-1:0][ACC_DECOMP_COEF_NB-1:0][CLOSEST_REP_W:0] s0_accD;
      side_t                                                        s0_acc_side;
      side_t                                                        s0_acc_sideD;
      logic [CHUNK_NB*ACC_DECOMP_COEF_NB-1:0][CLOSEST_REP_W:0]      s0_acc_a;

      logic                                        s1_ctrl_availD;
      logic [ACC_DECOMP_COEF_NB-1:0]               s1_data_availD_tmp;
      logic [CHUNK_NB-1:0][ACC_DECOMP_COEF_NB-1:0] s1_data_availD_tmp2;
      logic [PSI*R-1:0]                            s1_data_availD;

      always_comb begin
        s0_acc_sideD.sob             = s0_ctrl_avail && s0_soc ? s0_side.sob             : s0_acc_side.sob;
        s0_acc_sideD.eob             = s0_ctrl_avail && s0_eoc ? s0_side.eob             : s0_acc_side.eob;
        s0_acc_sideD.sog             = s0_ctrl_avail && s0_soc ? s0_side.sog             : s0_acc_side.sog;
        s0_acc_sideD.eog             = s0_ctrl_avail && s0_eoc ? s0_side.eog             : s0_acc_side.eog;
        s0_acc_sideD.sol             = s0_ctrl_avail && s0_soc ? s0_side.sol             : s0_acc_side.sol;
        s0_acc_sideD.eol             = s0_ctrl_avail && s0_eoc ? s0_side.eol             : s0_acc_side.eol;
        s0_acc_sideD.pbs_id          = s0_ctrl_avail && s0_eoc ? s0_side.pbs_id          : s0_acc_side.pbs_id;
        s0_acc_sideD.last_pbs        = s0_ctrl_avail && s0_eoc ? s0_side.last_pbs        : s0_acc_side.last_pbs;
        s0_acc_sideD.full_throughput = s0_ctrl_avail && s0_eoc ? s0_side.full_throughput : s0_acc_side.full_throughput;
      end

      always_comb begin
        for (int i=0; i<ACC_DECOMP_COEF_NB; i=i+1) begin
          s0_accD[CHUNK_NB-1][i] = s0_data_avail[i] ? {s0_closest_rep_sign[i], s0_closest_rep[i]} : s0_acc[CHUNK_NB-1][i];
          for (int j=0; j<CHUNK_NB-1; j=j+1)
            s0_accD[j][i] = s0_data_avail[i] ? s0_acc[j+1][i] : s0_acc[j][i];
        end
      end

      assign s0_acc_a = s0_acc;
      always_comb
        for (int i=0; i<PSI*R; i=i+1)
          {s1_closest_rep_sign[i], s1_closest_rep[i]} = s0_acc_a[i];

      assign s1_side = s0_acc_side;

      assign s1_ctrl_availD     = s0_ctrl_avail & s0_eoc;
      assign s1_data_availD_tmp = s0_data_avail & {ACC_DECOMP_COEF_NB{s0_eoc}};

      assign s1_data_availD = s1_data_availD_tmp2; // truncate
      always_comb
        for (int i=0; i<ACC_DECOMP_COEF_NB; i=i+1)
          for (int j=0; j<CHUNK_NB; j=j+1)
            s1_data_availD_tmp2[j][i] = s1_data_availD_tmp[i];

      always_ff @(posedge clk)
        if (!s_rst_n) begin
          s1_ctrl_avail <= 1'b0;
          s1_data_avail <= '0;
        end
        else begin
          s1_ctrl_avail <= s1_ctrl_availD;
          s1_data_avail <= s1_data_availD;
        end

      always_ff @(posedge clk) begin
        s0_acc      <= s0_accD;
        s0_acc_side <= s0_acc_sideD;
      end

    end
  endgenerate

  // ============================================================================================== --
  // Decompose
  // ============================================================================================== --
  logic [PSI*R-1:0][PBS_B_W:0] s2_result;
  side_t                       s2_side;
  logic                        s2_sol;
  logic                        s2_eol;
  logic [PSI*R-1:0]            s2_data_avail;
  logic                        s2_error;

  generate
    for (genvar gen_i=0; gen_i<R*PSI; gen_i=gen_i+1) begin : gen_loop
      if (gen_i==0) begin : gen_first_coef
        decomp_balseq_core #(
          .B_W          (PBS_B_W),
          .L            (PBS_L),
          .SIDE_W       ($bits(side_t)),
          .OUT_2SCOMPL  (1'b1)
        ) decomp_balseq_core (
          .clk       (clk),
          .s_rst_n   (s_rst_n),

          .in_data   (s1_closest_rep[gen_i]),
          .in_sign   (s1_closest_rep_sign[gen_i]),
          .in_avail  (s1_data_avail[gen_i]),
          .in_side   (s1_side),

          .out_data  (s2_result[gen_i]),
          .out_avail (s2_data_avail[gen_i]),
          .out_sol   (s2_sol),
          .out_eol   (s2_eol),
          .out_side  (s2_side),

          .error     (s2_error)
        );
      end
      else begin : gen_no_first_coef
        decomp_balseq_core #(
          .B_W          (PBS_B_W),
          .L            (PBS_L),
          .SIDE_W       (0), /* UNUSED */
          .OUT_2SCOMPL  (1'b1)
        ) decomp_balseq_core (
          .clk       (clk),
          .s_rst_n   (s_rst_n),

          .in_data   (s1_closest_rep[gen_i]),
          .in_sign   (s1_closest_rep_sign[gen_i]),
          .in_avail  (s1_data_avail[gen_i]),
          .in_side   ('x),/* UNUSED */

          .out_data  (s2_result[gen_i]),
          .out_avail (s2_data_avail[gen_i]),
          .out_sol   (),/* UNUSED */
          .out_eol   (),/* UNUSED */
          .out_side  (),/* UNUSED */

          .error     ()/* UNUSED */
        );
      end

    end
  endgenerate

  // ============================================================================================== --
  // Output
  // ============================================================================================== --
  assign decomp_ntt_ctrl_avail      = s2_data_avail[0];
  assign decomp_ntt_data_avail      = s2_data_avail;
  assign decomp_ntt_data            = s2_result; // 2s complement
  assign decomp_ntt_sob             = s2_side.sob & s2_sol;
  assign decomp_ntt_eob             = s2_side.eob & s2_eol;
  assign decomp_ntt_sog             = s2_side.sog & s2_sol;
  assign decomp_ntt_eog             = s2_side.eog & s2_eol;
  assign decomp_ntt_sol             = s2_side.sol & s2_sol;
  assign decomp_ntt_eol             = s2_side.eol & s2_eol;
  assign decomp_ntt_pbs_id          = s2_side.pbs_id;
  assign decomp_ntt_last_pbs        = s2_side.last_pbs;
  assign decomp_ntt_full_throughput = s2_side.full_throughput;

  // ============================================================================================== --
  // Error
  // ============================================================================================== --
  always_ff @(posedge clk)
    if (!s_rst_n) error <= 1'b0;
    else          error <= s2_error;

endmodule

