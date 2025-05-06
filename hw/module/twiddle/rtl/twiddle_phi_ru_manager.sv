// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the management of the twiddles PHI root of unity for
// the NTT core with matrix multiplication module.
// It delivers the PHI twiddles at the pace given by the core.
// The host fills the values. They should be valid before running the blind rotation.
//
// Assumptions :
// R >= 4
// ==============================================================================================

`include "ntt_core_common_macro_inc.sv"

module twiddle_phi_ru_manager
  import pep_common_param_pkg::*;
#(
  parameter  string FILE_TWD_PREFIX = "input_gen/data",
  parameter  int    OP_W            = 32,
  parameter  int    ROM_LATENCY     = 1,
  parameter  int    R               = 8, // Butterfly Radix
  parameter  int    PSI             = 8, // Number of butterflies
  parameter  int    S               = 3, // Number of stages
  parameter  int    S_INIT          = S-1,
  parameter  int    S_DEC           = 1,
  parameter  int    LPB_NB          = 1,
  localparam int    ERROR_NB        = 2
)
(
  input                                   clk,        // clock
  input                                   s_rst_n,    // synchronous reset

  // Output to NTT core
  output logic [PSI-1:0][R-1:1][       OP_W-1:0] twd_phi_ru,
  output logic                 [        PSI-1:0] twd_phi_ru_vld,
  input                        [        PSI-1:0] twd_phi_ru_rdy,  // per EOL
  // Broadcast from acc
  input                        [BR_BATCH_CMD_W-1:0] batch_cmd,       // Only need pbs_nb field
  input                                          batch_cmd_avail, // pulse
  // Error
  output [ERROR_NB-1:0]                          error
);

  // ============================================================================================ //
  // localparam
  // ============================================================================================ //
  `NTT_CORE_LOCALPARAM(R,S,PSI)

  localparam int RD_NB       = (R < 4) ? 1 : 2;             // Number of consecutive readings in ROM
  localparam int RD_PER_RAM  = (RD_NB * 2);                 // Total number of readings
  localparam int WR_DEPTH    = S * STG_ITER_NB * 2 * RD_NB; // 2 for NTT/INTT

  localparam int R_L             = R / RD_PER_RAM;
  localparam int RAM_DEPTH_L     = WR_DEPTH * 2;
  localparam int BUF_DEPTH       = ROM_LATENCY + 2;
  localparam int RD_NB_W         = $clog2(RD_NB) == 0 ? 1 : $clog2(RD_NB);
  localparam int LOC_NB          = ROM_LATENCY + BUF_DEPTH;
  localparam int RAM_NB          = PSI * R / RD_PER_RAM; // We use 2RW RAMs, and do 2 readings
  localparam int RAM_ADD_W_L     = $clog2(RAM_DEPTH_L);
  localparam int LOC_W           = $clog2(LOC_NB);

  localparam bit DO_LOOPBACK     = (S_DEC > 0); // if 1 this means that this module is used
                                                // for different stages (fwd-bwd taken into account)
  localparam int S_INIT_L        = S_INIT >= S ? S_INIT - S : S_INIT;
  localparam bit NTT_BWD_INIT    = S_INIT >= S;
  localparam int S_DEC_L         = S_DEC % S;

  localparam int LPB_W           = LPB_NB < 2 ? 1 : $clog2(LPB_NB);
  // ============================================================================================ //
  // twd_phi_ru_manager
  // ============================================================================================ //
  // -------------------------------------------------------------------------------------------- //
  // batch_cmd FIFO
  // -------------------------------------------------------------------------------------------- //
  // Use a small FIFO to store the commands that have to be processed.
  // Note that this FIFO does not need to be very deep, it depends on the number of batches that can
  // be processed in parallel.
  br_batch_cmd_t                      batch_cmd_s;
  logic       [BPBS_NB_WW-1:0]          s0_batch_pbs_nb;
  logic                               s0_batch_cmd_vld;
  logic                               s0_batch_cmd_rdy;
  logic       [     PSI-1:0][R_L-1:0] s0_batch_cmd_rdy_a;
  logic                               batch_cmd_rdy;
  logic       [BPBS_ID_W-1:0]          s0_batch_pbs_id_max;

  assign batch_cmd_s         = batch_cmd;
  assign s0_batch_cmd_rdy    = s0_batch_cmd_rdy_a[0][0];
  assign s0_batch_pbs_id_max = s0_batch_pbs_nb - 1;

  fifo_reg #(
    .WIDTH      (BPBS_NB_WW),
    .DEPTH      (BATCH_CMD_BUFFER_DEPTH-1), // -1 because using output pipe
    .LAT_PIPE_MH({1'b1, 1'b1})
  ) cmd_fifo (
    .clk    (clk),
    .s_rst_n(s_rst_n),

    .in_data(batch_cmd_s.pbs_nb),
    .in_vld (batch_cmd_avail),
    .in_rdy (batch_cmd_rdy),

    .out_data(s0_batch_pbs_nb),
    .out_vld (s0_batch_cmd_vld),
    .out_rdy (s0_batch_cmd_rdy)
  );

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // Do nothing
    end else begin
      assert (s0_batch_cmd_rdy_a == '0 || s0_batch_cmd_rdy_a == '1)
      else $fatal(1, "%t > ERROR: All RAMs s0_batch_cmd_rdy are not equal!", $time);
    end
// pragma translate_on

  // -------------------------------------------------------------------------------------------- //
  // Duplicate code for each RAM to ease P&R
  // -------------------------------------------------------------------------------------------- //
  logic [PSI-1:0][R-1:0][OP_W-1:0] twd_phi_ru_tmp;
  logic [PSI-1:0][R-1:0]           twd_phi_ru_vld_tmp;

  always_comb begin
    for (int p = 0; p < PSI; p = p + 1) begin
      twd_phi_ru_vld[p] = twd_phi_ru_vld_tmp[p][R-1];  // valid when all data have been read.
      for (int r = 1; r < R; r = r + 1) begin
        twd_phi_ru[p][r] = twd_phi_ru_tmp[p][r];
      end
    end
  end

  generate
    for (genvar gen_p = 0; gen_p < PSI; gen_p = gen_p + 1) begin : p_loop_gen
      for (genvar gen_r = 0; gen_r < R_L; gen_r = gen_r + 1) begin : r_loop_gen
        // --------------------------------------------------------------------------------- //
        // batch_cmd FIFO (final)
        // --------------------------------------------------------------------------------- //
        logic [BPBS_ID_W-1:0] s1_batch_pbs_id_max;
        logic                s1_batch_cmd_vld;
        logic                s1_batch_cmd_rdy;

        fifo_element #(
          .WIDTH         (BPBS_ID_W),
          .DEPTH         (1),
          .TYPE_ARRAY    (1),
          .DO_RESET_DATA (0),
          .RESET_DATA_VAL(0)
        ) fifo_element_cmd (
          .clk    (clk),
          .s_rst_n(s_rst_n),

          .in_data(s0_batch_pbs_id_max),
          .in_vld (s0_batch_cmd_vld),
          .in_rdy (s0_batch_cmd_rdy_a[gen_p][gen_r]),

          .out_data(s1_batch_pbs_id_max),
          .out_vld (s1_batch_cmd_vld),
          .out_rdy (s1_batch_cmd_rdy)
        );

        // -------------------------------------------------------------------------------------- //
        // Counters
        // -------------------------------------------------------------------------------------- //
        logic [     STG_W-1:0] s1_stg;
        logic [     STG_W-1:0] s1_stgD;
        logic                  s1_ntt_bwd;
        logic                  s1_ntt_bwdD;
        logic [STG_ITER_W-1:0] s1_stg_iter;
        logic [STG_ITER_W-1:0] s1_stg_iterD;
        logic [  BPBS_ID_W-1:0] s1_pbs_id;
        logic [  BPBS_ID_W-1:0] s1_pbs_idD;
        logic [   RD_NB_W-1:0] s1_rd_cnt;
        logic [   RD_NB_W-1:0] s1_rd_cntD;
        logic [LPB_W-1:0]      s1_lpb_cnt;
        logic [LPB_W-1:0]      s1_lpb_cntD;
        logic                  s1_first_stg_iter;
        logic                  s1_first_pbs_id;
        logic                  s1_first_rd_cnt;
        logic                  s1_last_stg_iter;
        logic                  s1_last_pbs_id;
        logic                  s1_last_rd_cnt;
        logic                  s1_do_read;
        logic                  s1_wrap_stg;
        logic [     STG_W-1:0] s1_start_stg;
        logic                  s1_last_ntt_bwd;
        logic                  s1_last_lpb;

        assign s1_wrap_stg  = ~DO_LOOPBACK | (s1_stg < S_DEC);
        assign s1_start_stg = S_INIT_L;

        assign s1_lpb_cntD  = (s1_do_read && s1_last_rd_cnt && s1_last_stg_iter && s1_last_pbs_id) ? s1_last_lpb ? '0 : s1_lpb_cnt + 1 : s1_lpb_cnt;
        assign s1_rd_cntD   = s1_do_read ? s1_last_rd_cnt ? '0 : s1_rd_cnt + 1 : s1_rd_cnt;
        assign s1_stg_iterD = (s1_do_read && s1_last_rd_cnt) ? s1_last_stg_iter ?
                                  '0 : s1_stg_iter + 1 : s1_stg_iter;
        assign s1_pbs_idD   = (s1_do_read && s1_last_rd_cnt&& s1_last_stg_iter)?
                                  s1_last_pbs_id ? '0 : s1_pbs_id + 1 : s1_pbs_id;
        assign s1_stgD      = (DO_LOOPBACK && s1_do_read && s1_last_rd_cnt&& s1_last_stg_iter && s1_last_pbs_id) ?
                                  s1_last_lpb ? s1_start_stg : s1_stg - S_DEC_L : s1_stg;
        assign s1_ntt_bwdD  = (DO_LOOPBACK && s1_do_read && s1_last_rd_cnt && s1_last_stg_iter && s1_last_pbs_id && s1_wrap_stg) ?
                                  ~s1_ntt_bwd : s1_ntt_bwd;

        assign s1_first_stg_iter = (s1_stg_iter == '0);
        assign s1_first_pbs_id = (s1_pbs_id == '0);
        assign s1_first_rd_cnt = (s1_rd_cnt == '0);
        assign s1_last_stg_iter = (s1_stg_iter == (STG_ITER_NB - 1));
        assign s1_last_pbs_id = (s1_pbs_id == s1_batch_pbs_id_max);
        assign s1_last_rd_cnt = (s1_rd_cnt == (RD_NB - 1));
        assign s1_last_ntt_bwd = ~DO_LOOPBACK | (s1_ntt_bwd != NTT_BWD_INIT);
        assign s1_last_lpb = s1_lpb_cnt == (LPB_NB-1);

        always_ff @(posedge clk) begin
          if (!s_rst_n) begin
            s1_rd_cnt   <= '0;
            s1_stg_iter <= '0;
            s1_pbs_id   <= '0;
            s1_stg      <= S_INIT_L;
            s1_ntt_bwd  <= NTT_BWD_INIT;
            s1_lpb_cnt  <= '0;
          end else begin
            s1_rd_cnt   <= s1_rd_cntD;
            s1_stg_iter <= s1_stg_iterD;
            s1_pbs_id   <= s1_pbs_idD;
            s1_stg      <= s1_stgD;
            s1_ntt_bwd  <= s1_ntt_bwdD;
            s1_lpb_cnt  <= s1_lpb_cntD;
          end
        end

        assign s1_batch_cmd_rdy = s1_do_read & s1_last_stg_iter & s1_last_pbs_id & s1_wrap_stg &
                                  s1_last_ntt_bwd & s1_last_rd_cnt;

        // -------------------------------------------------------------------------------------- //
        // Read pointer
        // -------------------------------------------------------------------------------------- //
        logic [RAM_ADD_W_L-1:0] s1_rp;
        logic [RAM_ADD_W_L-1:0] s1_rpD;
        logic [RAM_ADD_W_L-1:0] s1_rp_restart;
        logic [RAM_ADD_W_L-1:0] s1_rp_restartD;

        assign s1_rpD = s1_do_read ?
                        (s1_last_rd_cnt && s1_last_stg_iter) ? s1_last_pbs_id ?
                                                            (s1_wrap_stg && s1_last_ntt_bwd) ? '0 : s1_rp + 1 :
                                                             s1_rp_restart :
                                                          s1_rp + 1 :
                        s1_rp;

        if (STG_ITER_NB > 1) begin
          assign s1_rp_restartD = (s1_do_read && s1_first_rd_cnt && s1_first_stg_iter &&
                                   s1_first_pbs_id) ? s1_rp : s1_rp_restart;
        end else begin
          assign s1_rp_restartD = (s1_do_read && s1_last_rd_cnt && s1_last_stg_iter &&
                                   s1_last_pbs_id) ? s1_rpD : s1_rp_restart;
        end

        always_ff @(posedge clk)
          if (!s_rst_n) begin
            s1_rp         <= '0;
            s1_rp_restart <= '0;
          end else begin
            s1_rp         <= s1_rpD;
            s1_rp_restart <= s1_rp_restartD;
          end

        // -------------------------------------------------------------------------------------- //
        // Output buffer
        // -------------------------------------------------------------------------------------- //
        // To ease the P&R, the out_data comes from a register.
        // We need additional ROM_LATENCY registers to absorb the RAM read latency.
        // Note we don't need short latency here. We have plenty of time to fill the output pipe.
        logic [      1:0][    RD_NB-1:0][BUF_DEPTH-1:0][OP_W-1:0] buf_data;
        logic [      1:0][    RD_NB-1:0][  BUF_DEPTH:0][OP_W-1:0] buf_data_ext;
        logic [      1:0][    RD_NB-1:0][BUF_DEPTH-1:0][OP_W-1:0] buf_dataD;
        logic [RD_NB-1:0][BUF_DEPTH-1:0]                          buf_en;
        logic [RD_NB-1:0][BUF_DEPTH-1:0]                          buf_enD;
        logic [RD_NB-1:0][  BUF_DEPTH:0]                          buf_en_ext;
        logic [RD_NB-1:0]                                         buf_in_avail;
        logic [      1:0][     OP_W-1:0]                          buf_in_data;
        logic [RD_NB-1:0][BUF_DEPTH-1:0]                          buf_in_wren_1h;
        logic [RD_NB-1:0][BUF_DEPTH-1:0]                          buf_in_wren_1h_tmp;
        logic [RD_NB-1:0][BUF_DEPTH-1:0]                          buf_in_wren_1h_tmp2;
        logic                                                     buf_shift;

        // *_ext : Add 1 element to avoid warning, while selecting out of range.
        always_comb begin
          for (int j = 0; j < RD_NB; j = j + 1) begin
            buf_en_ext[j] = {1'b0, buf_en[j]};
            for (int i = 0; i < 2; i = i + 1) begin
              buf_data_ext[i][j] = {{OP_W{1'bx}}, buf_data[i][j]};
            end
            buf_in_wren_1h_tmp[j] = buf_shift ? {1'b0, buf_en[j][BUF_DEPTH-1:1]} : buf_en[j];
            // Find first bit = 0
            buf_in_wren_1h_tmp2[j] = buf_in_wren_1h_tmp[j] ^
                {buf_in_wren_1h_tmp[j][BUF_DEPTH-2:0], 1'b1};
            buf_in_wren_1h[j] = buf_in_wren_1h_tmp2[j] & {BUF_DEPTH{buf_in_avail[j]}};
          end
        end

        always_comb begin
          for (int k = 0; k < BUF_DEPTH; k = k + 1) begin
            for (int j = 0; j < RD_NB; j = j + 1) begin
              for (int i = 0; i < 2; i = i + 1) begin
                buf_dataD[i][j][k] = buf_in_wren_1h[j][k] ? buf_in_data[i] :
                    buf_shift ? buf_data_ext[i][j][k+1] : buf_data[i][j][k];
              end
              buf_enD[j][k] = buf_in_wren_1h[j][k] |
                  (buf_shift ? buf_en_ext[j][k+1] : buf_en[j][k]);
            end
          end
        end

        always_ff @(posedge clk) begin
          buf_data <= buf_dataD;
        end

        always_ff @(posedge clk)
          if (!s_rst_n) buf_en <= '0;
          else buf_en <= buf_enD;

        // pragma translate_off
        always_ff @(posedge clk)
          if (!s_rst_n) begin
            // do nothing
          end else begin
            for (int j = 0; j < RD_NB; j = j + 1) begin
              if (buf_in_avail[j]) begin
                assert (buf_in_wren_1h[j] != 0)
                else $fatal(1, "> ERROR: FIFO output buffer overflow!");
              end
            end
          end
        // pragma translate_on

        // -------------------------------------------------------------------------------------- //
        // Read
        // -------------------------------------------------------------------------------------- //
        // Read in RAM when there is a free location in the output buffer.
        logic [RD_NB-1:0][ROM_LATENCY-1:0] ram_data_avail_dly;
        logic [RD_NB-1:0][ROM_LATENCY-1:0] ram_data_avail_dlyD;
        logic [      1:0][       OP_W-1:0] ram_rd_data;
        logic [RD_NB-1:0]                  s1_do_read_tmp;

        assign s1_do_read  = |s1_do_read_tmp;
        assign buf_in_data = ram_rd_data;

        always_ff @(posedge clk)
          if (!s_rst_n) ram_data_avail_dly <= '0;
          else ram_data_avail_dly <= ram_data_avail_dlyD;

        for (genvar gen_j = 0; gen_j < RD_NB; gen_j = gen_j + 1) begin : j_loop_gen
          logic [ LOC_W-1:0] s1_data_cnt;
          logic [LOC_NB-1:0] s1_data_en;

          assign ram_data_avail_dlyD[gen_j][0] = s1_do_read & (s1_rd_cnt == gen_j);

          if (ROM_LATENCY > 1) begin : ram_latency_gt_1_gen
            assign ram_data_avail_dlyD[gen_j][ROM_LATENCY-1:1] =
                ram_data_avail_dly[gen_j][ROM_LATENCY-2:0];
          end

          assign s1_data_en = {buf_en[gen_j], ram_data_avail_dly[gen_j]};
          always_comb begin
            logic [LOC_W-1:0] cnt;
            cnt = '0;
            for (int i = 0; i < LOC_NB; i = i + 1) begin
              cnt = cnt + s1_data_en[i];
            end
            s1_data_cnt = cnt;
          end

          assign s1_do_read_tmp[gen_j] = (s1_data_cnt < BUF_DEPTH) & s1_batch_cmd_vld;

          // Buffer input
          assign buf_in_avail[gen_j]   = ram_data_avail_dly[gen_j][ROM_LATENCY-1];
        end  // gen_j

        // -------------------------------------------------------------------------------------- //
        // RAM control
        // -------------------------------------------------------------------------------------- //
        logic [1:0]                  ram_en;
        logic [1:0]                  ram_rd_en;
        logic [1:0][RAM_ADD_W_L-1:0] ram_rd_add;
        logic [1:0][RAM_ADD_W_L-1:0] ram_add;

        assign ram_en                         = ram_rd_en;
        assign ram_rd_add[0][0]               = 1'b0;
        assign ram_rd_add[1][0]               = 1'b1;
        assign ram_rd_add[0][RAM_ADD_W_L-1:1] = s1_rp;
        assign ram_rd_add[1][RAM_ADD_W_L-1:1] = s1_rp;
        assign ram_add[0]                     = ram_rd_add[0];
        assign ram_add[1]                     = ram_rd_add[1];
        assign ram_rd_en                      = {2{s1_do_read}};

        // -------------------------------------------------------------------------------------- //
        // ROMS
        // -------------------------------------------------------------------------------------- //
        rom_wrapper_2R #(
          .FILENAME     ($sformatf("%s_%0d_%0d.mem", FILE_TWD_PREFIX, gen_p, gen_r)),
          .WIDTH        (OP_W),
          .DEPTH        (RAM_DEPTH_L),
          .KEEP_RD_DATA (0),
          .ROM_LATENCY  (ROM_LATENCY)
        ) ram (
          // system interface
          .clk    (clk),
          .s_rst_n(s_rst_n),
          // port a interface
          .a_rd_en     (ram_en[0]),
          .a_rd_add    (ram_add[0]),
          .a_rd_data   (ram_rd_data[0]),
          // port b interface
          .b_rd_en     (ram_en[1]),
          .b_rd_add    (ram_add[1]),
          .b_rd_data   (ram_rd_data[1])
        );

        // -------------------------------------------------------------------------------------- //
        // Output
        // -------------------------------------------------------------------------------------- //
        always_comb begin
          for (int j = 0; j < RD_NB; j = j + 1) begin
            for (int i = 0; i < 2; i = i + 1) begin
              twd_phi_ru_tmp[gen_p][gen_r*RD_PER_RAM+j*RD_NB+i]     = buf_data[i][j][0];
              // output valid only when the last reading has arrived.
              twd_phi_ru_vld_tmp[gen_p][gen_r*RD_PER_RAM+j*RD_NB+i] = buf_en[j][0];
            end
          end
        end
        assign buf_shift = twd_phi_ru_rdy[gen_p] & twd_phi_ru_vld[gen_p];
      end  // gen_r
    end  // gen_p
  endgenerate

  // -------------------------------------------------------------------------------------------- //
  // Errors
  // -------------------------------------------------------------------------------------------- //
  // The FIFO should always be ready for an input command.
  logic error_cmd_overflow;
  logic error_cmd_overflowD;
  logic error_twd_phi_ru_underflow;
  logic error_twd_phi_ru_underflowD;

  assign error_cmd_overflowD         = batch_cmd_avail & ~batch_cmd_rdy;
  assign error_twd_phi_ru_underflowD = twd_phi_ru_rdy[0] & ~twd_phi_ru_vld[0];
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      error_cmd_overflow         <= 1'b0;
      error_twd_phi_ru_underflow <= 1'b0;
    end else begin
      error_cmd_overflow         <= error_cmd_overflowD;
      error_twd_phi_ru_underflow <= error_twd_phi_ru_underflowD;
    end

  assign error = {error_twd_phi_ru_underflow, error_cmd_overflow};
endmodule
