// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the reading of GLWE in regfile for the blind rotation.
// Note that we only read the "body" polynomial. Indeed, the mask part is 0.
// The GLWE is then written in the GRAM.
//
// For P&R reasons, the module is split into 2.
// This module assembles the parts, and is used for the verification.
//
// ==============================================================================================

module pep_load_glwe_splitc_assembly
  import common_definition_pkg::*;
  import axi_if_common_param_pkg::*;
  import axi_if_glwe_axi_pkg::*;
  import param_tfhe_pkg::*;
  import top_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import ntt_core_common_param_pkg::*;
#(
  parameter  int           SLR_LATENCY = 2*3
)
(
  input  logic                                                     clk,        // clock
  input  logic                                                     s_rst_n,    // synchronous reset

  input  logic [AXI4_ADD_W-1:0]                                    gid_offset, // quasi static

  // From GRAM arbiter
  input  logic [GRAM_NB-1:0]                                       garb_ldg_avail_1h,

  // pep_seq : command
  input  logic [LOAD_GLWE_CMD_W-1:0]                               seq_ldg_cmd,
  input  logic                                                     seq_ldg_vld,
  output logic                                                     seq_ldg_rdy,
  output logic                                                     ldg_seq_done,

  // AXI4 Master interface
  // NB: Only AXI Read channel exposed here
  output logic [AXI4_ID_W-1:0]                                     m_axi4_arid,
  output logic [AXI4_ADD_W-1:0]                                    m_axi4_araddr,
  output logic [7:0]                                               m_axi4_arlen,
  output logic [2:0]                                               m_axi4_arsize,
  output logic [1:0]                                               m_axi4_arburst,
  output logic                                                     m_axi4_arvalid,
  input  logic                                                     m_axi4_arready,
  input  logic [AXI4_ID_W-1:0]                                     m_axi4_rid,
  input  logic [AXI4_DATA_W-1:0]                                   m_axi4_rdata,
  input  logic [1:0]                                               m_axi4_rresp,
  input  logic                                                     m_axi4_rlast,
  input  logic                                                     m_axi4_rvalid,
  output logic                                                     m_axi4_rready,

  // Write GLWE RAM
  // This memory is composed of GRAM_NB independent RAMs
  output logic [GRAM_NB-1:0][PSI-1:0][R-1:0]                       glwe_ram_wr_en,
  output logic [GRAM_NB-1:0][PSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0]   glwe_ram_wr_add,
  output logic [GRAM_NB-1:0][PSI-1:0][R-1:0][MOD_Q_W-1:0]          glwe_ram_wr_data,

  output pep_ldg_counter_inc_t                                     pep_ldg_counter_inc,
  output pep_ldg_error_t                                           error
);

// ============================================================================================== //
// localparam
// ============================================================================================== //
  generate
    if (SLR_LATENCY!=0 && SLR_LATENCY < 2) begin : __UNSUPPORTED_SLR_LATENCY_
      $fatal(1,"> ERROR: Unsupported SLR_LATENCY (%0d) value : should be 0 or >= 2", SLR_LATENCY);
    end
  endgenerate

  localparam int OUTWARD_SLR_LATENCY = SLR_LATENCY/2;
  localparam int RETURN_SLR_LATENCY  = SLR_LATENCY - OUTWARD_SLR_LATENCY;

  localparam int QPSI = PSI / MSPLIT_DIV;
  localparam int MAIN_PSI = MSPLIT_MAIN_FACTOR * QPSI;
  localparam int SUBS_PSI = MSPLIT_SUBS_FACTOR * QPSI;

// ============================================================================================== //
// Signals
// ============================================================================================== //
  // Command
  logic [LOAD_GLWE_CMD_W-1:0]                                      in_main_subs_cmd;
  logic                                                            in_main_subs_cmd_vld;
  logic                                                            in_main_subs_cmd_rdy;
  logic                                                            in_subs_main_cmd_done;

  logic [LOAD_GLWE_CMD_W-1:0]                                      out_main_subs_cmd;
  logic                                                            out_main_subs_cmd_vld;
  logic                                                            out_main_subs_cmd_rdy;
  logic                                                            out_subs_main_cmd_done;

  // Data
  logic [GLWE_SPLITC_COEF-1:0][MOD_Q_W-1:0]                        in_main_subs_data;
  logic                                                            in_main_subs_data_vld;
  logic                                                            in_main_subs_data_rdy;

  logic [GLWE_SPLITC_COEF-1:0][MOD_Q_W-1:0]                        out_main_subs_data;
  logic                                                            out_main_subs_data_vld;
  logic                                                            out_main_subs_data_rdy;

  logic [GRAM_NB-1:0][MAIN_PSI-1:0][R-1:0]                         main_glwe_ram_wr_en;
  logic [GRAM_NB-1:0][MAIN_PSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0]     main_glwe_ram_wr_add;
  logic [GRAM_NB-1:0][MAIN_PSI-1:0][R-1:0][MOD_Q_W-1:0]            main_glwe_ram_wr_data;

  logic [GRAM_NB-1:0][SUBS_PSI-1:0][R-1:0]                         subs_glwe_ram_wr_en;
  logic [GRAM_NB-1:0][SUBS_PSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0]     subs_glwe_ram_wr_add;
  logic [GRAM_NB-1:0][SUBS_PSI-1:0][R-1:0][MOD_Q_W-1:0]            subs_glwe_ram_wr_data;

  pep_ldg_error_t                                                  main_error;
  pep_ldg_error_t                                                  subs_error;

  pep_ldg_counter_inc_t                                            main_ldg_counter_inc;
  pep_ldg_counter_inc_t                                            subs_ldg_counter_inc;

  logic [GRAM_NB-1:0]                                              in_subs_main_garb_ldg_avail_1h;
  logic [GRAM_NB-1:0]                                              out_subs_main_garb_ldg_avail_1h;

  always_comb
    for (int i=0; i<GRAM_NB; i=i+1) begin
        glwe_ram_wr_en[i]   = {main_glwe_ram_wr_en[i], subs_glwe_ram_wr_en[i]};
        glwe_ram_wr_add[i]  = {main_glwe_ram_wr_add[i], subs_glwe_ram_wr_add[i]};
        glwe_ram_wr_data[i] = {main_glwe_ram_wr_data[i], subs_glwe_ram_wr_data[i]};
    end

  assign in_subs_main_garb_ldg_avail_1h = garb_ldg_avail_1h;

// ============================================================================================= --
// Error / Inc
// ============================================================================================= --
  pep_ldg_counter_inc_t pep_ldg_counter_incD;
  pep_ldg_error_t       errorD;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      error               <= '0;
      pep_ldg_counter_inc <= '0;
    end
    else begin
      error               <= errorD;
      pep_ldg_counter_inc <= pep_ldg_counter_incD;
    end

// ============================================================================================= --
// SLR crossing
// ============================================================================================= --
  generate
    if (SLR_LATENCY == 0) begin : gen_no_slr_latency
      assign out_main_subs_cmd               = in_main_subs_cmd;
      assign out_main_subs_cmd_vld           = in_main_subs_cmd_vld;
      assign in_main_subs_cmd_rdy            = out_main_subs_cmd_rdy;
      assign out_subs_main_cmd_done          = in_subs_main_cmd_done;

      assign out_main_subs_data              = in_main_subs_data;
      assign out_main_subs_data_vld          = in_main_subs_data_vld;
      assign in_main_subs_data_rdy           = out_main_subs_data_rdy;

      assign out_subs_main_garb_ldg_avail_1h = in_subs_main_garb_ldg_avail_1h;
    end
    else begin : gen_slr_latency
      //== Command
      fifo_element #(
        .WIDTH          (LOAD_GLWE_CMD_W),
        .DEPTH          (OUTWARD_SLR_LATENCY),
        .TYPE_ARRAY     ({OUTWARD_SLR_LATENCY{4'h1}}),
        .DO_RESET_DATA  (0),
        .RESET_DATA_VAL (0)
      ) main_subs_cmd_fifo_element (
        .clk     (clk),
        .s_rst_n (s_rst_n),

        .in_data (in_main_subs_cmd),
        .in_vld  (in_main_subs_cmd_vld),
        .in_rdy  (in_main_subs_cmd_rdy),

        .out_data(out_main_subs_cmd),
        .out_vld (out_main_subs_cmd_vld),
        .out_rdy (out_main_subs_cmd_rdy)
      );

      //== Data
      fifo_element #(
        .WIDTH          (GLWE_SPLITC_COEF*MOD_Q_W),
        .DEPTH          (OUTWARD_SLR_LATENCY),
        .TYPE_ARRAY     ({OUTWARD_SLR_LATENCY{4'h1}}),
        .DO_RESET_DATA  (0),
        .RESET_DATA_VAL (0)
      ) main_subs_data_fifo_element (
        .clk     (clk),
        .s_rst_n (s_rst_n),

        .in_data (in_main_subs_data),
        .in_vld  (in_main_subs_data_vld),
        .in_rdy  (in_main_subs_data_rdy),

        .out_data(out_main_subs_data),
        .out_vld (out_main_subs_data_vld),
        .out_rdy (out_main_subs_data_rdy)
      );

      //== garb avail
      logic [RETURN_SLR_LATENCY-1:0][GRAM_NB-1:0] subs_main_garb_ldg_avail_1h_sr;
      logic [RETURN_SLR_LATENCY-1:0][GRAM_NB-1:0] subs_main_garb_ldg_avail_1h_srD;

      assign subs_main_garb_ldg_avail_1h_srD[0] = in_subs_main_garb_ldg_avail_1h;
      assign out_subs_main_garb_ldg_avail_1h    = subs_main_garb_ldg_avail_1h_sr[RETURN_SLR_LATENCY-1];
      if (RETURN_SLR_LATENCY > 1) begin
        assign subs_main_garb_ldg_avail_1h_srD[RETURN_SLR_LATENCY-1:1] = subs_main_garb_ldg_avail_1h_sr[RETURN_SLR_LATENCY-2:0];
      end

      always_ff @(posedge clk)
        if (!s_rst_n) subs_main_garb_ldg_avail_1h_sr <= '0;
        else          subs_main_garb_ldg_avail_1h_sr <= subs_main_garb_ldg_avail_1h_srD;

      //== cmd_done
      logic [RETURN_SLR_LATENCY-1:0] subs_main_cmd_done_sr;
      logic [RETURN_SLR_LATENCY-1:0] subs_main_cmd_done_srD;

      assign subs_main_cmd_done_srD[0] = in_subs_main_cmd_done;
      assign out_subs_main_cmd_done    = subs_main_cmd_done_sr[RETURN_SLR_LATENCY-1];
      if (RETURN_SLR_LATENCY > 1) begin
        assign subs_main_cmd_done_srD[RETURN_SLR_LATENCY-1:1] = subs_main_cmd_done_sr[RETURN_SLR_LATENCY-2:0];
      end

      always_ff @(posedge clk)
        if (!s_rst_n) subs_main_cmd_done_sr <= '0;
        else          subs_main_cmd_done_sr <= subs_main_cmd_done_srD;
    end
  endgenerate


// ============================================================================================= --
// Main
// ============================================================================================= --
  pep_load_glwe_splitc_main
  pep_load_glwe_splitc_main (
    .clk                  (clk),
    .s_rst_n              (s_rst_n),

    .gid_offset           (gid_offset),

    .garb_ldg_avail_1h    (out_subs_main_garb_ldg_avail_1h),

    .seq_ldg_cmd          (seq_ldg_cmd),
    .seq_ldg_vld          (seq_ldg_vld),
    .seq_ldg_rdy          (seq_ldg_rdy),
    .ldg_seq_done         (ldg_seq_done),

    .m_axi4_arid          (m_axi4_arid),
    .m_axi4_araddr        (m_axi4_araddr),
    .m_axi4_arlen         (m_axi4_arlen),
    .m_axi4_arsize        (m_axi4_arsize),
    .m_axi4_arburst       (m_axi4_arburst),
    .m_axi4_arvalid       (m_axi4_arvalid),
    .m_axi4_arready       (m_axi4_arready),
    .m_axi4_rid           (m_axi4_rid),
    .m_axi4_rdata         (m_axi4_rdata),
    .m_axi4_rresp         (m_axi4_rresp),
    .m_axi4_rlast         (m_axi4_rlast),
    .m_axi4_rvalid        (m_axi4_rvalid),
    .m_axi4_rready        (m_axi4_rready),

    .subs_cmd             (in_main_subs_cmd),
    .subs_cmd_vld         (in_main_subs_cmd_vld),
    .subs_cmd_rdy         (in_main_subs_cmd_rdy),
    .subs_cmd_done        (out_subs_main_cmd_done),

    .subs_data            (in_main_subs_data),
    .subs_data_vld        (in_main_subs_data_vld),
    .subs_data_rdy        (in_main_subs_data_rdy),

    .glwe_ram_wr_en       (main_glwe_ram_wr_en),
    .glwe_ram_wr_add      (main_glwe_ram_wr_add),
    .glwe_ram_wr_data     (main_glwe_ram_wr_data),

    .pep_ldg_counter_inc  (main_ldg_counter_inc),
    .ldg_error            (main_error)
  );

// ============================================================================================= --
// Subsidiary
// ============================================================================================= --
  pep_load_glwe_splitc_subs
  pep_load_glwe_splitc_subs (
    .clk                   (clk),
    .s_rst_n               (s_rst_n),

    .garb_ldg_avail_1h     (garb_ldg_avail_1h),

    .subs_cmd              (out_main_subs_cmd),
    .subs_cmd_vld          (out_main_subs_cmd_vld),
    .subs_cmd_rdy          (out_main_subs_cmd_rdy),
    .subs_cmd_done         (in_subs_main_cmd_done),

    .subs_data             (out_main_subs_data),
    .subs_data_vld         (out_main_subs_data_vld),
    .subs_data_rdy         (out_main_subs_data_rdy),

    .glwe_ram_wr_en        (subs_glwe_ram_wr_en),
    .glwe_ram_wr_add       (subs_glwe_ram_wr_add),
    .glwe_ram_wr_data      (subs_glwe_ram_wr_data),

    .pep_ldg_counter_inc   (subs_ldg_counter_inc),
    .ldg_error             (subs_error)
  );

endmodule
