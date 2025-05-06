// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module dispatches the data to OUT_NB outputs. Each output needs OUT_COEF consecutive elements.
// ==============================================================================================

module stream_dispatch
#(
  parameter int OP_W      = 32,
  parameter int IN_COEF   = 16,
  parameter int OUT_COEF  = 4,
  parameter int OUT_NB    = 1,
  parameter int DISP_COEF = 8, // consecutive coef for each output
  parameter bit IN_PIPE   = 1'b1,
  parameter bit OUT_PIPE  = 1'b1 // Highly recommended
)
(
  input  logic                                      clk,        // clock
  input  logic                                      s_rst_n,    // synchronous reset

  input  logic [IN_COEF-1:0][OP_W-1:0]              in_data,
  input  logic                                      in_vld,
  output logic                                      in_rdy,

  output logic [OUT_NB-1:0][OUT_COEF-1:0][OP_W-1:0] out_data,
  output logic [OUT_NB-1:0]                         out_vld,
  input  logic [OUT_NB-1:0]                         out_rdy
);

// ============================================================================================== //
// localparam
// ============================================================================================== //
  // Number of destination ports concerned by the input
  localparam int DEST_NB      = IN_COEF > DISP_COEF ? IN_COEF/DISP_COEF : 1;
  localparam int O_ITER_NB    = IN_COEF > DISP_COEF && DEST_NB > OUT_NB ? DEST_NB/OUT_NB : 1;
  localparam int FMT_CORE_NB  = IN_COEF > DISP_COEF ? DEST_NB > OUT_NB ? OUT_NB : DEST_NB : 1;
  localparam int COEF_NB      = IN_COEF > DISP_COEF ? DISP_COEF : IN_COEF;

  localparam int O_ITER_W   = $clog2(O_ITER_NB) == 0 ? 1 : $clog2(O_ITER_NB);

  generate
    if (IN_COEF > OUT_COEF) begin : _check_in_coef_gt_out_coef
      if (IN_COEF % OUT_COEF != 0) begin : _UNSUPPORTED_IN_COEF_OUT_COEF_0
        $fatal(1,"> ERROR: stream_dispatch only supports IN_COEF (%0d) mod OUT_COEF (%0d) == 0", IN_COEF, OUT_COEF);
      end
    end
    else if (IN_COEF < OUT_COEF) begin: _check_in_coef_lt_out_coef
      if (OUT_COEF % IN_COEF != 0) begin: _UNSUPPORTED_IN_COEF_OUT_COEF_1
        $fatal(1,"> ERROR: stream_dispatch only supports OUT_COEF (%0d) mod IN_COEF == 0 (%0d)", OUT_COEF, IN_COEF);
      end
    end
    if (DISP_COEF > OUT_COEF) begin : _check_disp_coef_gt_out_coef
      if (DISP_COEF % OUT_COEF != 0) begin : _UNSUPPORTED_DISP_COEF_OUT_COEF_0
        $fatal(1,"> ERROR: stream_dispatch only supports DISP_COEF (%0d) mod OUT_COEF (%0d) == 0", DISP_COEF, OUT_COEF);
      end
    end
    else if (DISP_COEF < OUT_COEF) begin : _check_disp_coef_lt_out_coef
      if (OUT_COEF % DISP_COEF != 0) begin : _UNSUPPORTED_DISP_COEF_OUT_COEF_1
        $fatal(1,"> ERROR: stream_dispatch only supports OUT_COEF (%0d) mod DISP_COEF (%0d) == 0", OUT_COEF, DISP_COEF);
      end
    end

    if (IN_COEF < DISP_COEF && DISP_COEF < OUT_COEF) begin : _UNSUPPORTED_IN_DISP_OUT_COEF
      $fatal(1,"> ERROR: Unsupported IN_COEF < DISP_COEF < OUT_COEF");
      // The module does not support this case, because only a single format core is instanciated here.
    end

    if (FMT_CORE_NB < OUT_NB) begin : _check_fmt_core_nb_lt_out_nb
      if (OUT_NB % FMT_CORE_NB != 0) begin : _UNSUPPORTED_OUT_NB
        // This case is not supported by current architecture. Indeed, the current architecture assumes that each format core addresses
        // a set of outputs that distinct from the other format cores.
        // So we don't address the issue of data racing to the same output.
        $fatal(1,"> ERROR: Unsupported OUT_NB (%0d) vs FMT_CORE_NB (%0d). The current architecture does not support this.", OUT_NB, FMT_CORE_NB);
      end
    end
  endgenerate

// ============================================================================================== //
// Input Pipe
// ============================================================================================== //
  logic [IN_COEF-1:0][OP_W-1:0] s0_data;
  logic                         s0_vld;
  logic                         s0_rdy;

  generate
    if (IN_PIPE) begin : gen_in_pipe
      fifo_element #(
        .WIDTH          (IN_COEF * OP_W),
        .DEPTH          (2),
        .TYPE_ARRAY     (8'h12),
        .DO_RESET_DATA  (0),
        .RESET_DATA_VAL (0)
      ) in_fifo_element (
        .clk     (clk),
        .s_rst_n (s_rst_n),

        .in_data (in_data),
        .in_vld  (in_vld),
        .in_rdy  (in_rdy),

        .out_data(s0_data),
        .out_vld (s0_vld),
        .out_rdy (s0_rdy)
      );
    end
    else begin : gen_no_in_pipe
      assign s0_data = in_data;
      assign s0_vld  = in_vld;
      assign in_rdy  = s0_rdy;
    end
  endgenerate

// ============================================================================================== //
// Fork
// ============================================================================================== //
  // Build input of the format core
  logic [FMT_CORE_NB-1:0][COEF_NB-1:0][OP_W-1:0] f0_data;
  logic [FMT_CORE_NB-1:0]                     f0_vld;
  logic [FMT_CORE_NB-1:0]                     f0_rdy;

  generate
    if (IN_COEF > DISP_COEF) begin : gen_in_coef_gt_disp_coef
      logic                                          s0_last_o_iter;
      logic [FMT_CORE_NB-1:0][COEF_NB-1:0][OP_W-1:0] f0_data_tmp;
      logic                                          s0_rdy_tmp;

      if (DEST_NB > OUT_NB) begin : gen_dest_nb_gt_out_nb
        // Count the number of output iterations that can be produced with a single input data.
        logic [O_ITER_W-1:0] s0_o_iter;
        logic [O_ITER_W-1:0] s0_o_iterD;
        logic                s0_avail;

        assign s0_last_o_iter = s0_o_iter == O_ITER_NB-1;
        assign s0_o_iterD = s0_avail ? s0_last_o_iter ? '0 : s0_o_iter + 1 : s0_o_iter;

        always_ff @(posedge clk)
          if (!s_rst_n) s0_o_iter <= '0;
          else          s0_o_iter <= s0_o_iterD;

        logic [O_ITER_NB-1:0][OUT_NB-1:0][COEF_NB-1:0][OP_W-1:0] s0_data_a;

        assign s0_data_a   = s0_data;
        assign f0_data_tmp = s0_data_a[s0_o_iter];
        assign s0_avail    = s0_vld & s0_rdy_tmp;
      end
      else begin : gen_dest_nb_le_out_nb
        assign s0_last_o_iter = 1'b1; // Since there is only 1 iteration
        assign f0_data_tmp    = s0_data;
      end

      // fork
      // Use a mask to mark the cores that have already sampled the data.
      logic [FMT_CORE_NB-1:0] s0_fmt_mask;
      logic [FMT_CORE_NB-1:0] s0_fmt_maskD;
      logic                   s0_reset_fmt_mask;

      assign s0_reset_fmt_mask = &((f0_vld & f0_rdy) | s0_fmt_mask);
      always_comb
        for (int i=0; i<FMT_CORE_NB; i=i+1)
          s0_fmt_maskD[i] = s0_reset_fmt_mask ? 1'b0 : f0_vld[i] && f0_rdy[i] ? 1'b1 : s0_fmt_mask[i];


      assign f0_data = f0_data_tmp;
      assign f0_vld  = {FMT_CORE_NB{s0_vld}} & ~s0_fmt_mask;
      assign s0_rdy_tmp = &(f0_rdy | s0_fmt_mask);
      assign s0_rdy     = s0_rdy_tmp & s0_last_o_iter;

      always_ff @(posedge clk)
        if (!s_rst_n) s0_fmt_mask <= '0;
        else          s0_fmt_mask <= s0_fmt_maskD;

    end
    else begin : gen_in_coef_le_disp_coef
      assign f0_data = s0_data;
      assign f0_vld  = s0_vld;
      assign s0_rdy  = f0_rdy;
    end
  endgenerate

// ============================================================================================== //
// Format
// ============================================================================================== //
  logic [FMT_CORE_NB-1:0][OUT_COEF-1:0][OP_W-1:0] f1_data;
  logic [FMT_CORE_NB-1:0]                         f1_vld;
  logic [FMT_CORE_NB-1:0]                         f1_rdy;

  generate
    for (genvar gen_i=0; gen_i<FMT_CORE_NB; gen_i=gen_i+1) begin : gen_format_loop
      stream_disp_format
      #(
        .OP_W      (OP_W),
        .IN_COEF   (COEF_NB),
        .OUT_COEF  (OUT_COEF),
        .IN_PIPE   (1'b1) // TOREVIEW
      ) stream_disp_format (
        .clk      (clk),
        .s_rst_n  (s_rst_n),

        .in_data  (f0_data[gen_i]),
        .in_vld   (f0_vld[gen_i]),
        .in_rdy   (f0_rdy[gen_i]),

        .out_data (f1_data[gen_i]),
        .out_vld  (f1_vld[gen_i]),
        .out_rdy  (f1_rdy[gen_i])
      );
    end
  endgenerate

// ============================================================================================== //
// Dispatch
// ============================================================================================== //
  logic [OUT_NB-1:0][OUT_COEF-1:0][OP_W-1:0] f2_data;
  logic [OUT_NB-1:0]                         f2_vld;
  logic [OUT_NB-1:0]                         f2_rdy;

  generate
    if (FMT_CORE_NB < OUT_NB) begin : gen_dispatch
      localparam int I_ITER_NB       = DISP_COEF > COEF_NB ? DISP_COEF / COEF_NB : 1;
      localparam int D_ITER_NB_TMP_0 = (COEF_NB / OUT_COEF) * I_ITER_NB;
      localparam int D_ITER_NB_TMP_1 = DISP_COEF > OUT_COEF ? DISP_COEF / OUT_COEF : 1;
      localparam int D_ITER_NB       = COEF_NB > OUT_COEF ? D_ITER_NB_TMP_0 : D_ITER_NB_TMP_1;
      localparam int D_ITER_W        = $clog2(D_ITER_NB) == 0 ? 1 : $clog2(D_ITER_NB);

      logic [FMT_CORE_NB-1:0][OUT_NB-1:0][OUT_COEF-1:0][OP_W-1:0] f2_data_a;
      logic [FMT_CORE_NB-1:0][OUT_NB-1:0]                         f2_vld_a;

      // assemble
      always_comb begin
        var [OUT_NB-1:0][OUT_COEF-1:0][OP_W-1:0] f2_data_tmp;
        var [OUT_NB-1:0]                         f2_vld_tmp;
        f2_data_tmp = '0;
        f2_vld_tmp  = '0;
        for (int i=0; i<FMT_CORE_NB; i=i+1) begin
          f2_data_tmp = f2_data_tmp | f2_data_a[i];
          f2_vld_tmp  = f2_vld_tmp | f2_vld_a[i];
        end
        f2_data = f2_data_tmp;
        f2_vld  = f2_vld_tmp;
      end

      for (genvar gen_c=0; gen_c<FMT_CORE_NB; gen_c=gen_c+1) begin : gen_disp_loop
        // Counters
        logic [D_ITER_W-1:0] f1_d_iter;
        logic [D_ITER_W-1:0] f1_d_iterD;
        logic                f1_last_d_iter;

        assign f1_last_d_iter = f1_d_iter == D_ITER_NB-1;
        assign f1_d_iterD     = (f1_vld[gen_c] && f1_rdy[gen_c]) ? f1_last_d_iter ? '0 : f1_d_iter + 1 : f1_d_iter;

        always_ff @(posedge clk)
          if (!s_rst_n) f1_d_iter <= '0;
          else          f1_d_iter <= f1_d_iterD;

        // dispatch
        logic [OUT_NB-1:0]   f1_disp_out_1h;
        logic [OUT_NB-1:0]   f1_disp_out_1hD;
        logic [2*OUT_NB-1:0] f1_disp_out_1hD_tmp;
        logic [1:0][OUT_NB-1:0] f1_disp_out_1hD_tmp2;
        logic [OUT_NB-1:0]      f1_disp_out_1hD_tmp3;

        assign f1_disp_out_1hD_tmp  = f1_disp_out_1h; // extended with 0s
        assign f1_disp_out_1hD_tmp2 = f1_disp_out_1h << FMT_CORE_NB;
        assign f1_disp_out_1hD_tmp3 = f1_disp_out_1hD_tmp2[1] | f1_disp_out_1hD_tmp2[0];
        assign f1_disp_out_1hD      = (f1_vld[gen_c] && f1_rdy[gen_c] && f1_last_d_iter) ? f1_disp_out_1hD_tmp3 : f1_disp_out_1h;

        always_ff @(posedge clk)
          if (!s_rst_n) f1_disp_out_1h <= 1 << gen_c;
          else          f1_disp_out_1h <= f1_disp_out_1hD;

        always_comb
          for (int i=0; i<OUT_NB; i=i+1)
            f2_data_a[gen_c][i] = f1_disp_out_1h[i] ? f1_data[gen_c] : '0;
        assign f2_vld_a[gen_c]  = {OUT_NB{f1_vld[gen_c]}} & f1_disp_out_1h;
        assign f1_rdy[gen_c]    = &(f2_rdy  | ~f1_disp_out_1h);

      end // for gen_disp_loop
    end
    else begin : gen_no_dispatch
      assign f2_data = f1_data;
      assign f2_vld  = f1_vld;
      assign f1_rdy  = f2_rdy;
    end
  endgenerate

// ============================================================================================== //
// Output pipe
// ============================================================================================== //
  generate
    if (OUT_PIPE) begin : gen_out_pipe
      for (genvar gen_i=0; gen_i<OUT_NB; gen_i=gen_i+1) begin : gen_out_loop
        fifo_element #(
          .WIDTH          (OUT_COEF * OP_W),
          .DEPTH          (2),
          .TYPE_ARRAY     (8'h12),
          .DO_RESET_DATA  (0),
          .RESET_DATA_VAL (0)
        ) out_fifo_element (
          .clk     (clk),
          .s_rst_n (s_rst_n),

          .in_data (f2_data[gen_i]),
          .in_vld  (f2_vld[gen_i]),
          .in_rdy  (f2_rdy[gen_i]),

          .out_data(out_data[gen_i]),
          .out_vld (out_vld[gen_i]),
          .out_rdy (out_rdy[gen_i])
        );
      end
    end
    else begin : gen_no_out_pipe
      assign out_vld  = f2_vld;
      assign f2_rdy   = out_rdy;
      assign out_data = f2_data;
    end
  endgenerate

endmodule
