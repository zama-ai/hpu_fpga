// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the PHI root of unity for ntt_core_gf64.
// This modules handles cases with numerous unfriendly PHI per port. They are stored in a ROM.
// ==============================================================================================

module ntt_core_gf64_phi_rom #(
  parameter int    N_L             = 2048, // local block size to consider. Should be a power of 2. Should be greater than R*PSI
  parameter int    R               = 2, // Supports only value 2
  parameter int    PSI             = 16,
  parameter int    OP_W            = 64,
  parameter int    LVL_NB          = 2, // Number of times the twd is kept. Should be at least 2
  parameter string TWD_GF64_FILE_PREFIX = "memory_file/twiddle/NTT_CORE_ARCH_GF64/R2_PSI16/twd_phi_fwd_N2048",
  parameter int    ROM_LATENCY     = 2
)
(
  input  logic                            clk,        // clock
  input  logic                            s_rst_n,    // synchronous reset

  output logic [PSI-1:0][R-1:0][OP_W-1:0] twd_phi,
  output logic [PSI-1:0]                  twd_phi_vld,
  input  logic [PSI-1:0]                  twd_phi_rdy

);

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int ITER_NB = N_L / (R*PSI);
  localparam int ITER_W  = $clog2(ITER_NB) == 0 ? 1 : $clog2(ITER_NB);
  localparam int LVL_W   = $clog2(LVL_NB) == 0 ? 1 : $clog2(LVL_NB);

  localparam int BUF_DEPTH = ROM_LATENCY + 1;
  localparam int LOC_W     = $clog2(2*BUF_DEPTH) == 0 ? 1 : $clog2(2*BUF_DEPTH);
  localparam int LOC_WW    = $clog2(2*BUF_DEPTH+1) == 0 ? 1 : $clog2(2*BUF_DEPTH+1);

  generate
    if (ITER_NB < 64) begin : __WARNING
      initial begin
        $display("> WARNING : There are %0d iterations for phi readings. This is small for a ROM. Registers may be better.", ITER_NB);
      end
    end

    if (R != 2) begin : __UNSUPPORTED_R
      $fatal(1,"> ERROR: phi_rom only supports R=2");
    end

    if (LVL_NB < 2) begin : __UNSUPPORTED_LVL_NB
      $fatal(1,"> ERROR: LVL_NB (%0d) should be at least 2. RTL simplifications are made with this assumption.",LVL_NB);
    end
  endgenerate


  logic [PSI-1:0] twd_phi_rdy_masked;

  generate
    for (genvar gen_p = 0; gen_p < PSI; gen_p = gen_p + 1) begin : p_loop_gen
      // Duplicate counters to ease P&R

// ============================================================================================== --
// Keep data
// ============================================================================================== --
      // Output data are kept LVL_NB times
      logic [LVL_W-1:0] out_lvl;
      logic [LVL_W-1:0] out_lvlD;
      logic             last_out_lvl;

      assign last_out_lvl = out_lvl == LVL_NB-1;
      assign out_lvlD = twd_phi_vld[gen_p] && twd_phi_rdy[gen_p] ? last_out_lvl ? '0 : out_lvl + 1 : out_lvl;

      always_ff @(posedge clk)
        if (!s_rst_n) out_lvl <= '0;
        else          out_lvl <= out_lvlD;

      assign twd_phi_rdy_masked[gen_p] = twd_phi_rdy[gen_p] & last_out_lvl;


// ============================================================================================== --
// ROM
// ============================================================================================== --
      //-------------------------------------------------------
      // Counters
      //-------------------------------------------------------
      logic [ITER_W-1:0] iter;
      logic [ITER_W-1:0] iterD;
      logic              rd_parity;
      logic              rd_parityD;

      logic              last_iter;
      logic              last_rd_parity;
      logic              rd_en;

      assign last_iter      = iter == (ITER_NB-1);
      assign last_rd_parity = rd_parity == 1'b1;
      assign rd_parityD     = rd_en ? ~rd_parity : rd_parity;
      assign iterD          = rd_en && last_rd_parity ? last_iter ? '0 : iter + 1 : iter;

      always_ff @(posedge clk)
        if (!s_rst_n) begin
          iter      <= '0;
          rd_parity <= 1'b0;
        end
        else begin
          iter      <= iterD;
          rd_parity <= rd_parityD;
        end

      //-------------------------------------------------------
      // ROM output buffers
      //-------------------------------------------------------
      logic [ROM_LATENCY-1:0] ram_data_avail_sr;
      logic [ROM_LATENCY-1:0] ram_data_avail_srD;

      assign ram_data_avail_srD[0] = rd_en;
      if (ROM_LATENCY > 1) begin
        assign ram_data_avail_srD[ROM_LATENCY-1:1] = ram_data_avail_sr[ROM_LATENCY-2:0];
      end

      always_ff @(posedge clk)
        if (!s_rst_n) ram_data_avail_sr <= '0;
        else          ram_data_avail_sr <= ram_data_avail_srD;

      logic            ram_data_avail;
      logic [OP_W-1:0] ram_data;

      assign ram_data_avail = ram_data_avail_sr[ROM_LATENCY-1];

      //== Count free locations
      logic [LOC_WW-1:0] free_loc;
      logic [LOC_WW-1:0] free_locD;

      assign rd_en = free_loc != 0;

      assign free_locD = (twd_phi_vld[gen_p] && twd_phi_rdy_masked[gen_p]) && rd_en  ? free_loc + 1:
                         (twd_phi_vld[gen_p] && twd_phi_rdy_masked[gen_p]) && !rd_en ? free_loc + 2:
                         !(twd_phi_vld[gen_p] && twd_phi_rdy_masked[gen_p]) && rd_en ? free_loc - 1:
                         free_loc;

      //== buffers
      logic [LOC_W-1:0] loc_wp;
      logic [LOC_W-1:0] loc_wpD;

      assign loc_wpD = (twd_phi_vld[gen_p] && twd_phi_rdy_masked[gen_p]) && !ram_data_avail ? loc_wp - 2:
                       !(twd_phi_vld[gen_p] && twd_phi_rdy_masked[gen_p]) && ram_data_avail ? loc_wp + 1:
                       (twd_phi_vld[gen_p] && twd_phi_rdy_masked[gen_p]) && ram_data_avail ? loc_wp - 1:
                       loc_wp;

      always_ff @(posedge clk)
        if (!s_rst_n) begin
          free_loc <= 2*BUF_DEPTH;
          loc_wp   <= '0;
        end
        else begin
          free_loc <= free_locD;
          loc_wp   <= loc_wpD;
        end

      logic [BUF_DEPTH-1:0][1:0][OP_W-1:0] buffer;
      logic [BUF_DEPTH-1:0][1:0][OP_W-1:0] bufferD;
      logic [BUF_DEPTH-1:0][1:0][OP_W-1:0] buffer_upd;

      assign bufferD[BUF_DEPTH-2:0] = (twd_phi_vld[gen_p] && twd_phi_rdy_masked[gen_p]) ? buffer_upd[BUF_DEPTH-1:1] : buffer_upd[BUF_DEPTH-2:0];
      assign bufferD[BUF_DEPTH-1]   = buffer_upd[BUF_DEPTH-1];

      always_comb
        for (int i=0; i<BUF_DEPTH; i=i+1) begin
          buffer_upd[i][1] = (ram_data_avail && loc_wp[LOC_W-1:1] == i) ? ram_data     : buffer[i][1];
          buffer_upd[i][0] = (ram_data_avail && loc_wp[LOC_W-1:1] == i) ? buffer[i][1] : buffer[i][0];
        end

      always_ff @(posedge clk)
        buffer <= bufferD;

      //-------------------------------------------------------
      // Output
      //-------------------------------------------------------
      assign twd_phi[gen_p]     = buffer[0];
      assign twd_phi_vld[gen_p] = loc_wp[LOC_W-1:1] != 0;

      //-------------------------------------------------------
      // ROM
      //-------------------------------------------------------
      rom_wrapper_1R #(
        .FILENAME     ($sformatf("%s_%0d.mem", TWD_GF64_FILE_PREFIX, gen_p)),
        .WIDTH        (OP_W),
        .DEPTH        (ITER_NB*2),
        .KEEP_RD_DATA (0),
        .ROM_LATENCY  (ROM_LATENCY)
      ) twd_phi_rom (
        // system interface
        .clk       (clk),
        .s_rst_n   (s_rst_n),
        // port a interface
        .rd_en     (rd_en),
        .rd_add    ({iter,rd_parity}),
        .rd_data   (ram_data)
      );

    end // p_loop_gen
  endgenerate
endmodule
