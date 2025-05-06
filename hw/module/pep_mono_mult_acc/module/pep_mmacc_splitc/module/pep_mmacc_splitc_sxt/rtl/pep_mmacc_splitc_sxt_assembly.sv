// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the sample extraction, and the rotation with b.
// It reads the coefficients from GRAM, and orders them according to b and, does the negation
// when necessary.
// Data in GRAM are assumed to be in reverse order.
//
// This module outputs REGF_COEF_NB coefficients at a time.
// If the number of coefficients of a BLWE is not a multiple of BLWE_COEF_NB, the last word
// is completed with garbage.
// ==============================================================================================

module pep_mmacc_splitc_sxt_assembly
  import common_definition_pkg::*;
  import param_tfhe_pkg::*;
  import top_common_param_pkg::*;
  import ntt_core_common_param_pkg::*;
  import regf_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import pep_mmacc_common_param_pkg::*;
  import pep_mmacc_splitc_sxt_pkg::*;
#(
  parameter  int DATA_LATENCY          = 5,   // RAM_LATENCY + 3 : Latency for read data to come back
  parameter  int SLR_LATENCY           = 2*3  // Number of cycles for the other part to arrive.
)
(
  input  logic                                                   clk,        // clock
  input  logic                                                   s_rst_n,    // synchronous reset

  // From sfifo
  input  logic [MMACC_INTERN_CMD_W-1:0]                          sfifo_sxt_icmd,
  input  logic                                                   sfifo_sxt_vld,
  output logic                                                   sfifo_sxt_rdy,

  // sxt <-> body RAM
  input  logic [LWE_COEF_W-1:0]                                  boram_sxt_data,
  input  logic                                                   boram_sxt_data_vld,
  output logic                                                   boram_sxt_data_rdy,

  // sxt <-> regfile
  // write
  output logic                                                   sxt_regf_wr_req_vld,
  input  logic                                                   sxt_regf_wr_req_rdy,
  output logic [REGF_WR_REQ_W-1:0]                               sxt_regf_wr_req,

  output logic [REGF_COEF_NB-1:0]                                sxt_regf_wr_data_vld,
  input  logic [REGF_COEF_NB-1:0]                                sxt_regf_wr_data_rdy,
  output logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0]                   sxt_regf_wr_data,

  input  logic                                                   regf_sxt_wr_ack,

  // From GRAM arbiter
  input  logic [GRAM_NB-1:0]                                     garb_sxt_avail_1h,

  // GRAM
  output logic [GRAM_NB-1:0][PSI-1:0][R-1:0]                     sxt_gram_rd_en,
  output logic [GRAM_NB-1:0][PSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0] sxt_gram_rd_add,
  input  logic [GRAM_NB-1:0][PSI-1:0][R-1:0][MOD_Q_W-1:0]        gram_sxt_rd_data,
  input  logic [GRAM_NB-1:0][PSI-1:0][R-1:0]                     gram_sxt_rd_data_avail,

  // CT done
  output logic                                                   sxt_seq_done, // pulse
  output logic [PID_W-1:0]                                       sxt_seq_done_pid,

  // For register if
  output logic                                                   sxt_rif_cmd_wait_b_dur,
  output logic                                                   sxt_rif_rcp_dur,
  output logic                                                   sxt_rif_req_dur
);

// ============================================================================================= --
// localparam
// ============================================================================================= --
  generate
    if (SLR_LATENCY!= 0 && SLR_LATENCY < 2) begin : __UNSUPPORTED_SLR_LATENCY_
      $fatal(1,"> ERROR: Unsupported SLR_LATENCY (%0d) value : should be 0 or >= 2", SLR_LATENCY);
    end
  endgenerate

  localparam int OUTWARD_SLR_LATENCY = SLR_LATENCY/2;
  localparam int RETURN_SLR_LATENCY  = SLR_LATENCY - OUTWARD_SLR_LATENCY;
  localparam int SXT_SPLITC_COEF     = set_msplit_sxt_splitc_coef(MSPLIT_TYPE);
  localparam int SUBS_PSI            = PSI * MSPLIT_SUBS_FACTOR / MSPLIT_DIV;
  localparam int MAIN_PSI            = PSI * MSPLIT_MAIN_FACTOR / MSPLIT_DIV;

// ============================================================================================= --
// Signals
// ============================================================================================= --
  // main <-> subs cmd
  logic                                                     in_main_subs_cmd_vld;
  logic                                                     in_main_subs_cmd_rdy;
  logic [LWE_COEF_W-1:0]                                    in_main_subs_cmd_body;
  logic [MMACC_INTERN_CMD_W-1:0]                            in_main_subs_cmd_icmd;

  logic                                                     out_main_subs_cmd_vld;
  logic                                                     out_main_subs_cmd_rdy;
  logic [LWE_COEF_W-1:0]                                    out_main_subs_cmd_body;
  logic [MMACC_INTERN_CMD_W-1:0]                            out_main_subs_cmd_icmd;

  logic                                                     in_subs_main_cmd_ack;
  logic                                                     out_subs_main_cmd_ack;

  // main <-> subs data
  logic [SXT_SPLITC_COEF-1:0][MOD_Q_W-1:0]                  in_subs_main_data_data;
  logic                                                     in_subs_main_data_vld;
  logic                                                     in_subs_main_data_rdy;

  logic [SXT_SPLITC_COEF-1:0][MOD_Q_W-1:0]                  out_subs_main_data_data;
  logic                                                     out_subs_main_data_vld;
  logic                                                     out_subs_main_data_rdy;

  logic [PSI/MSPLIT_DIV-1:0][R-1:0][MOD_Q_W-1:0]            in_subs_main_part_data;
  logic                                                     in_subs_main_part_vld;
  logic                                                     in_subs_main_part_rdy;

  logic [PSI/MSPLIT_DIV-1:0][R-1:0][MOD_Q_W-1:0]            out_subs_main_part_data;
  logic                                                     out_subs_main_part_vld;
  logic                                                     out_subs_main_part_rdy;

  logic [GRAM_NB-1:0]                                       in_subs_main_garb_sxt_avail_1h;
  logic [GRAM_NB-1:0]                                       out_subs_main_garb_sxt_avail_1h;

  logic [GRAM_NB-1:0][MAIN_PSI-1:0][R-1:0]                      main_sxt_gram_rd_en;
  logic [GRAM_NB-1:0][MAIN_PSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0]  main_sxt_gram_rd_add;
  logic [GRAM_NB-1:0][MAIN_PSI-1:0][R-1:0][MOD_Q_W-1:0]         main_gram_sxt_rd_data;
  logic [GRAM_NB-1:0][MAIN_PSI-1:0][R-1:0]                      main_gram_sxt_rd_data_avail;

  logic [GRAM_NB-1:0][SUBS_PSI-1:0][R-1:0]                      subs_sxt_gram_rd_en;
  logic [GRAM_NB-1:0][SUBS_PSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0]  subs_sxt_gram_rd_add;
  logic [GRAM_NB-1:0][SUBS_PSI-1:0][R-1:0][MOD_Q_W-1:0]         subs_gram_sxt_rd_data;
  logic [GRAM_NB-1:0][SUBS_PSI-1:0][R-1:0]                      subs_gram_sxt_rd_data_avail;

  always_comb
    for (int g=0; g<GRAM_NB; g=g+1) begin
        sxt_gram_rd_en[g]      = {main_sxt_gram_rd_en[g],subs_sxt_gram_rd_en[g]};
        sxt_gram_rd_add[g]     = {main_sxt_gram_rd_add[g],subs_sxt_gram_rd_add[g]};
        {main_gram_sxt_rd_data[g],subs_gram_sxt_rd_data[g]} = gram_sxt_rd_data[g];
        {main_gram_sxt_rd_data_avail[g], subs_gram_sxt_rd_data_avail[g]} = gram_sxt_rd_data_avail[g];
      end

// ============================================================================================= --
// SLR crossing
// ============================================================================================= --
  generate
    if (SLR_LATENCY == 0) begin : gen_no_slr_latency
      assign out_main_subs_cmd_vld   = in_main_subs_cmd_vld;
      assign in_main_subs_cmd_rdy    = out_main_subs_cmd_rdy;
      assign out_main_subs_cmd_body  = in_main_subs_cmd_body;
      assign out_main_subs_cmd_icmd  = in_main_subs_cmd_icmd;

      assign out_subs_main_cmd_ack   = in_subs_main_cmd_ack;

      assign out_subs_main_data_data = in_subs_main_data_data;
      assign out_subs_main_data_vld  = in_subs_main_data_vld;
      assign in_subs_main_data_rdy   = out_subs_main_data_rdy;

      assign out_subs_main_part_data = in_subs_main_part_data;
      assign out_subs_main_part_vld  = in_subs_main_part_vld;
      assign in_subs_main_part_rdy   = out_subs_main_part_rdy;

      assign out_subs_main_garb_sxt_avail_1h = in_subs_main_garb_sxt_avail_1h;
    end
    else begin : gen_slr_latency
      fifo_element #(
        .WIDTH          (MMACC_INTERN_CMD_W + LWE_COEF_W),
        .DEPTH          (OUTWARD_SLR_LATENCY),
        .TYPE_ARRAY     ({OUTWARD_SLR_LATENCY{4'h1}}),
        .DO_RESET_DATA  (0),
        .RESET_DATA_VAL (0)
      ) main_subs_fifo_element (
        .clk     (clk),
        .s_rst_n (s_rst_n),

        .in_data ({in_main_subs_cmd_body,in_main_subs_cmd_icmd}),
        .in_vld  (in_main_subs_cmd_vld),
        .in_rdy  (in_main_subs_cmd_rdy),

        .out_data({out_main_subs_cmd_body,out_main_subs_cmd_icmd}),
        .out_vld (out_main_subs_cmd_vld),
        .out_rdy (out_main_subs_cmd_rdy)
      );

      fifo_element #(
        .WIDTH          (SXT_SPLITC_COEF*MOD_Q_W),
        .DEPTH          (RETURN_SLR_LATENCY),
        .TYPE_ARRAY     ({RETURN_SLR_LATENCY{4'h1}}),
        .DO_RESET_DATA  (0),
        .RESET_DATA_VAL (0)
      ) subs_main_fifo_element (
        .clk     (clk),
        .s_rst_n (s_rst_n),

        .in_data (in_subs_main_data_data),
        .in_vld  (in_subs_main_data_vld),
        .in_rdy  (in_subs_main_data_rdy),

        .out_data(out_subs_main_data_data),
        .out_vld (out_subs_main_data_vld),
        .out_rdy (out_subs_main_data_rdy)
      );

      fifo_element #(
        .WIDTH          (PSI/MSPLIT_DIV*R*MOD_Q_W),
        .DEPTH          (RETURN_SLR_LATENCY),
        .TYPE_ARRAY     ({RETURN_SLR_LATENCY{4'h1}}),
        .DO_RESET_DATA  (0),
        .RESET_DATA_VAL (0)
      ) subs_main_part_fifo_element (
        .clk     (clk),
        .s_rst_n (s_rst_n),

        .in_data (in_subs_main_part_data),
        .in_vld  (in_subs_main_part_vld),
        .in_rdy  (in_subs_main_part_rdy),

        .out_data(out_subs_main_part_data),
        .out_vld (out_subs_main_part_vld),
        .out_rdy (out_subs_main_part_rdy)
      );


      logic [RETURN_SLR_LATENCY-1:0][GRAM_NB-1:0] subs_main_garb_sxt_avail_1h_sr;
      logic [RETURN_SLR_LATENCY-1:0][GRAM_NB-1:0] subs_main_garb_sxt_avail_1h_srD;
      logic [RETURN_SLR_LATENCY-1:0]              subs_main_cmd_ack_sr;
      logic [RETURN_SLR_LATENCY-1:0]              subs_main_cmd_ack_srD;

      assign subs_main_garb_sxt_avail_1h_srD[0] = {in_subs_main_garb_sxt_avail_1h};
      assign out_subs_main_garb_sxt_avail_1h    = subs_main_garb_sxt_avail_1h_sr[RETURN_SLR_LATENCY-1];
      assign subs_main_cmd_ack_srD[0]           = in_subs_main_cmd_ack;
      assign out_subs_main_cmd_ack              = subs_main_cmd_ack_sr[RETURN_SLR_LATENCY-1];
      if (RETURN_SLR_LATENCY > 1) begin
        assign subs_main_garb_sxt_avail_1h_srD[RETURN_SLR_LATENCY-1:1] = subs_main_garb_sxt_avail_1h_sr[RETURN_SLR_LATENCY-2:0];
        assign subs_main_cmd_ack_srD[RETURN_SLR_LATENCY-1:1]           = subs_main_cmd_ack_sr[RETURN_SLR_LATENCY-2:0];
      end

      always_ff @(posedge clk)
        if (!s_rst_n) begin
          subs_main_garb_sxt_avail_1h_sr <= '0;
          subs_main_cmd_ack_sr           <= '0;
        end
        else begin
          subs_main_garb_sxt_avail_1h_sr <= subs_main_garb_sxt_avail_1h_srD;
          subs_main_cmd_ack_sr           <= subs_main_cmd_ack_srD;
        end
    end
  endgenerate

// ============================================================================================= --
// main
// ============================================================================================= --
  pep_mmacc_splitc_main_sxt
  #(
    .DATA_LATENCY       (DATA_LATENCY)
  ) pep_mmacc_splitc_main_sxt (
    .clk                    (clk),
    .s_rst_n                (s_rst_n),

    .sfifo_sxt_icmd         (sfifo_sxt_icmd),
    .sfifo_sxt_vld          (sfifo_sxt_vld),
    .sfifo_sxt_rdy          (sfifo_sxt_rdy),

    .boram_sxt_data         (boram_sxt_data),
    .boram_sxt_data_vld     (boram_sxt_data_vld),
    .boram_sxt_data_rdy     (boram_sxt_data_rdy),

    .subs_cmd_vld           (in_main_subs_cmd_vld),
    .subs_cmd_rdy           (in_main_subs_cmd_rdy),
    .subs_cmd_body          (in_main_subs_cmd_body),
    .subs_cmd_icmd          (in_main_subs_cmd_icmd),
    .subs_cmd_ack           (out_subs_main_cmd_ack),

    .subs_data_data         (out_subs_main_data_data),
    .subs_data_vld          (out_subs_main_data_vld),
    .subs_data_rdy          (out_subs_main_data_rdy),

    .subs_part_data         (out_subs_main_part_data),
    .subs_part_vld          (out_subs_main_part_vld ),
    .subs_part_rdy          (out_subs_main_part_rdy ),

    .sxt_regf_wr_req_vld    (sxt_regf_wr_req_vld),
    .sxt_regf_wr_req_rdy    (sxt_regf_wr_req_rdy),
    .sxt_regf_wr_req        (sxt_regf_wr_req),

    .sxt_regf_wr_data_vld   (sxt_regf_wr_data_vld),
    .sxt_regf_wr_data_rdy   (sxt_regf_wr_data_rdy),
    .sxt_regf_wr_data       (sxt_regf_wr_data),

    .regf_sxt_wr_ack        (regf_sxt_wr_ack),

    .garb_sxt_avail_1h      (out_subs_main_garb_sxt_avail_1h),

    .sxt_gram_rd_en         (main_sxt_gram_rd_en),
    .sxt_gram_rd_add        (main_sxt_gram_rd_add),
    .gram_sxt_rd_data       (main_gram_sxt_rd_data),
    .gram_sxt_rd_data_avail (main_gram_sxt_rd_data_avail),

    .sxt_seq_done           (sxt_seq_done),
    .sxt_seq_done_pid       (sxt_seq_done_pid),

    .sxt_rif_cmd_wait_b_dur (sxt_rif_cmd_wait_b_dur),
    .sxt_rif_rcp_dur        (sxt_rif_rcp_dur),
    .sxt_rif_req_dur        (sxt_rif_req_dur)
  );

// ============================================================================================= --
// subs
// ============================================================================================= --
  assign in_subs_main_garb_sxt_avail_1h = garb_sxt_avail_1h;
  pep_mmacc_splitc_subs_sxt
  #(
    .DATA_LATENCY (DATA_LATENCY)
  ) pep_mmacc_splitc_subs_sxt (
    .clk                    (clk),
    .s_rst_n                (s_rst_n),

    .subs_cmd_vld           (out_main_subs_cmd_vld),
    .subs_cmd_rdy           (out_main_subs_cmd_rdy),
    .subs_cmd_body          (out_main_subs_cmd_body),
    .subs_cmd_icmd          (out_main_subs_cmd_icmd),
    .subs_cmd_ack           (in_subs_main_cmd_ack),

    .subs_data_data         (in_subs_main_data_data),
    .subs_data_vld          (in_subs_main_data_vld),
    .subs_data_rdy          (in_subs_main_data_rdy),

    .subs_part_data         (in_subs_main_part_data),
    .subs_part_vld          (in_subs_main_part_vld),
    .subs_part_rdy          (in_subs_main_part_rdy),

    .garb_sxt_avail_1h      (garb_sxt_avail_1h),

    .sxt_gram_rd_en         (subs_sxt_gram_rd_en),
    .sxt_gram_rd_add        (subs_sxt_gram_rd_add),
    .gram_sxt_rd_data       (subs_gram_sxt_rd_data),
    .gram_sxt_rd_data_avail (subs_gram_sxt_rd_data_avail),

    .sxt_rif_req_dur () /*UNUSED*/
  );


endmodule
