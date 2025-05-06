// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the management of the twiddles for the final point-wise multiplication,
// necessary when processing INTT with DIT architecture.
// It delivers the twiddles at the pace given by the core.
// The host fills the values. They should be valid before running the blind rotation.
// Note that the twiddles should be given in reverse order (R,N).
//
// Assumptions :
// GLWE_K_P1 >= ROM_LATENCY+1 : which means that there are enough clock cycles
//                      to read the next twiddle sets while the current one is being processed.
// ==============================================================================================

`include "ntt_core_common_macro_inc.sv"

module twiddle_intt_final_manager
#(
  parameter  string  FILE_TWD_PREFIX = "input_gen/data", // generated from scripts
  parameter  int     OP_W            = 32,
  parameter  int     ROM_LATENCY     = 1,
  parameter  int     R               = 8,
  parameter  int     PSI             = 8,
  parameter  int     S               = 3
)
(
  input  logic                               clk,        // clock
  input  logic                               s_rst_n,    // synchronous reset

  // Output to NTT core
  // 1 set of twiddles per stage iteration
  output logic [PSI-1:0][  R-1:0][OP_W-1:0] twd_intt_final,
  output logic          [PSI-1:0][   R-1:0] twd_intt_final_vld,
  input  logic          [PSI-1:0][   R-1:0] twd_intt_final_rdy
);

  // ============================================================================================ //
  // localparam
  // ============================================================================================ //
  `NTT_CORE_LOCALPARAM(R,S,PSI)

  // Number of RAMs
  localparam int ROM_DEPTH        = STG_ITER_NB;     // Should be at least STG_ITER_NB
  localparam int ROM_NB           = PSI * R / 2;  // We use 2RW RAMs
  localparam int ROM_DEPTH_L      = ROM_DEPTH * 2;
  localparam int ROM_ADD_W_L      = $clog2(ROM_DEPTH_L);
  localparam int ROM_DEPTH_W_REAL = 2 * STG_ITER_NB;
  localparam int ROM_ADD_W_REAL   = $clog2(ROM_DEPTH_W_REAL);
  localparam int ROM_ADD_W        = $clog2(ROM_DEPTH);

  localparam int BUF_DEPTH        = 1 + ROM_LATENCY;
  localparam int BUF_W            = $clog2(BUF_DEPTH+1); // For counter from 0 to BUF_DEPTH included

  // ============================================================================================ //
  // Check parameters
  // ============================================================================================ //
// pragma translate_off
  initial begin
    assert (ROM_DEPTH >= STG_ITER_NB)
    else $fatal(1, "%t > ERROR: ROM_DEPTH should be at least STG_ITER_NB", $time);
  end
// pragma translate_on

  // ============================================================================================ //
  // twiddle_intt_final_manager
  // ============================================================================================ //
  // -------------------------------------------------------------------------------------------- //
  // Counters
  // -------------------------------------------------------------------------------------------- //
  logic [STG_ITER_W-1:0] s0_stg_iter;
  logic [STG_ITER_W-1:0] s0_stg_iterD;
  logic                  s0_last_stg_iter;
  logic                  s0_do_read;

  assign s0_stg_iterD     = s0_do_read ? s0_last_stg_iter ? '0 : s0_stg_iter + 1 : s0_stg_iter;

  assign s0_last_stg_iter = (s0_stg_iter == (STG_ITER_NB - 1));

  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      s0_stg_iter <= '0;
    end else begin
      s0_stg_iter <= s0_stg_iterD;
    end
  end

  // -------------------------------------------------------------------------------------------- //
  // RAM control
  // -------------------------------------------------------------------------------------------- //
  logic [        PSI-1:0]                            ram_rd_en;
  logic [        PSI-1:0][          R-1:0]           ram_rd_en_ext;
  logic [            1:0][ROM_ADD_W_L-1:0]           ram_rd_add;
  logic [        PSI-1:0][          R-1:0][OP_W-1:0] ram_rd_data;
  logic [ROM_LATENCY-1:0][        PSI-1:0][   R-1:0] ram_rd_en_dly;
  logic [ROM_LATENCY-1:0][        PSI-1:0][   R-1:0] ram_rd_en_dlyD;

  always_comb
    for (int p = 0; p < PSI; p = p + 1) begin
      ram_rd_en_ext[p] = {R{ram_rd_en[p]}};
    end

  assign ram_rd_en_dlyD[0] = ram_rd_en_ext;
  generate
    if (ROM_LATENCY > 1) assign ram_rd_en_dlyD[ROM_LATENCY-1:1] = ram_rd_en_dly[ROM_LATENCY-2:0];
  endgenerate

  always_ff @(posedge clk)
    if (!s_rst_n) ram_rd_en_dly <= '0;
    else ram_rd_en_dly <= ram_rd_en_dlyD;

  // Read once at the beginning, to prepare the very first data.
  // Read at each sol
  always_comb for (int p = 0; p < PSI; p = p + 1) ram_rd_en[p] = s0_do_read;

  assign ram_rd_add[0][0] = 1'b0;
  assign ram_rd_add[1][0] = 1'b1;

  generate
    if (STG_ITER_NB > 1) begin : ram_rd_add_stg_iter_nb_gt_1_gen
      assign ram_rd_add[0][1+:STG_ITER_W] = s0_stg_iter;
      assign ram_rd_add[1][1+:STG_ITER_W] = s0_stg_iter;
    end
  endgenerate

  // Complete with 0
  generate
    if (ROM_ADD_W_L > ROM_ADD_W_REAL) begin : rd_ROM_ADD_W_gt_add_w_p1_gen
      assign ram_rd_add[0][ROM_ADD_W_L-1:ROM_ADD_W_REAL] = '0;
      assign ram_rd_add[1][ROM_ADD_W_L-1:ROM_ADD_W_REAL] = '0;
    end
  endgenerate

  // -------------------------------------------------------------------------------------------- //
  // RAM instance
  // -------------------------------------------------------------------------------------------- //
  logic [PSI-1:0][R-1:0]                  ram_en;
  logic [PSI-1:0][R-1:0][ROM_ADD_W_L-1:0] ram_add;

  assign ram_en = ram_rd_en_ext;

  always_comb begin
    for (int p = 0; p < PSI; p = p + 1) begin
      for (int r = 0; r < R / 2; r = r + 1) begin
        ram_add[p][2*r]   = ram_rd_add[0];
        ram_add[p][2*r+1] = ram_rd_add[1];
      end
    end
  end

  generate
    for (genvar gen_p = 0; gen_p < PSI; gen_p = gen_p + 1) begin : ram_psi_loop_gen
      for (genvar gen_r = 0; gen_r < R / 2; gen_r = gen_r + 1) begin : ram_r_loop_gen
        rom_wrapper_2R #(
          .FILENAME    ($sformatf("%s_%0d_%0d.mem", FILE_TWD_PREFIX, gen_p, gen_r)),
          .WIDTH       (OP_W),
          .DEPTH       (ROM_DEPTH_L),
          .KEEP_RD_DATA(0),
          .ROM_LATENCY (ROM_LATENCY)
        ) rom (
          // system interface
          .clk      (clk),
          .s_rst_n  (s_rst_n),
          // port a interface
          .a_rd_en  (ram_en[gen_p][2*gen_r]),
          .a_rd_add (ram_add[gen_p][2*gen_r]),
          .a_rd_data(ram_rd_data[gen_p][2*gen_r]),
          // port b interface
          .b_rd_en  (ram_en[gen_p][2*gen_r+1]),
          .b_rd_add (ram_add[gen_p][2*gen_r+1]),
          .b_rd_data(ram_rd_data[gen_p][2*gen_r+1])
        );
      end
    end
  endgenerate

  // -------------------------------------------------------------------------------------------- //
  // Output pipe
  // -------------------------------------------------------------------------------------------- //
  logic [PSI-1:0][R-1:0]           s1_vld;
  logic [PSI-1:0][R-1:0]           s1_rdy;
  logic [PSI-1:0][R-1:0][OP_W-1:0] s2_data;
  logic [PSI-1:0][R-1:0]           s2_vld;
  logic [PSI-1:0][R-1:0]           s2_rdy;

  assign s1_vld = ram_rd_en_dly[ROM_LATENCY-1];

  generate
    for (genvar gen_p = 0; gen_p < PSI; gen_p = gen_p + 1) begin : psi_loop_gen
      for (genvar gen_r = 0; gen_r < R; gen_r = gen_r + 1) begin : r_loop_gen

        logic [PSI-1:0][R-1:0][OP_W-1:0] s2_data_tmp;
        logic [PSI-1:0][R-1:0]           s2_vld_tmp;
        logic [PSI-1:0][R-1:0]           s2_rdy_tmp;

        fifo_element #(
          .WIDTH         (OP_W),
          .DEPTH         (BUF_DEPTH-1),
          .TYPE_ARRAY    ({BUF_DEPTH-1{4'h2}}),
          .DO_RESET_DATA (0),
          .RESET_DATA_VAL(0)
        ) fifo_element_start (
          .clk    (clk),
          .s_rst_n(s_rst_n),

          .in_data(ram_rd_data[gen_p][gen_r]),
          .in_vld (s1_vld[gen_p][gen_r]),
          .in_rdy (s1_rdy[gen_p][gen_r]),

          .out_data(s2_data_tmp[gen_p][gen_r]),
          .out_vld (s2_vld_tmp[gen_p][gen_r]),
          .out_rdy (s2_rdy_tmp[gen_p][gen_r])
        );

        fifo_element #(
          .WIDTH         (OP_W),
          .DEPTH         (1),
          .TYPE_ARRAY    (1),
          .DO_RESET_DATA (0),
          .RESET_DATA_VAL(0)
        ) fifo_element_end (
          .clk    (clk),
          .s_rst_n(s_rst_n),

          .in_data(s2_data_tmp[gen_p][gen_r]),
          .in_vld (s2_vld_tmp[gen_p][gen_r]),
          .in_rdy (s2_rdy_tmp[gen_p][gen_r]),

          .out_data(s2_data[gen_p][gen_r]),
          .out_vld (s2_vld[gen_p][gen_r]),
          .out_rdy (s2_rdy[gen_p][gen_r])
        );

// pragma translate_off
        always_ff @(posedge clk) begin
          if (!s_rst_n) begin
            // Do nothing
          end else begin
            if (ram_rd_en_dly[ROM_LATENCY-1][gen_p][gen_r]) begin
              assert (s1_rdy[gen_p][gen_r])
              else $fatal(1, "%t > ERROR: output FIFO not ready to receive RAM read data!", $time);
            end
          end
        end
// pragma translate_on
      end
    end
  endgenerate

  always_comb begin
    for (int p = 0; p < PSI; p = p + 1) begin
      for (int r = 0; r < R; r = r + 1) begin
        twd_intt_final[p][r] = s2_data[p][r];
      end
    end
  end

  always_comb begin
    for (int p = 0; p < PSI; p = p + 1) begin
      for (int r = 0; r < R; r = r + 1) begin
        twd_intt_final_vld[p][r] = s2_vld[p][r];
        s2_rdy[p][r]             = twd_intt_final_rdy[p][r];
      end
    end
  end

  // -------------------------------------------------------------------------------------------- //
  // Do read
  // -------------------------------------------------------------------------------------------- //
  // Output buffer has a depth of 2.
  // Counts the number of available read data.
  // When it is less than 2, read a new data.
  logic [BUF_W-1:0] s0_avail_data_cnt;
  logic [BUF_W-1:0] s0_avail_data_cntD;

  assign s0_avail_data_cntD = s0_do_read ?
      (s2_vld[0][0] && s2_rdy[0][0]) ? s0_avail_data_cnt : s0_avail_data_cnt + 1 :
      (s2_vld[0][0] && s2_rdy[0][0]) ? s0_avail_data_cnt - 1 : s0_avail_data_cnt;
  always_ff @(posedge clk)
    if (!s_rst_n) s0_avail_data_cnt <= '0;
    else s0_avail_data_cnt <= s0_avail_data_cntD;

  assign s0_do_read = (s0_avail_data_cnt < BUF_DEPTH);
endmodule
