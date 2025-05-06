// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals the regfile.
// 3 actors need to access the regfile:
// * ALU
// * PBS
// * MEM (for HBM/DDR load/store)
//
// It has 2 access ports
//  1 Read
//  1 Write
//
// The module takes care of the request arbitration.
// Requests are in BLWE unit.
// ==============================================================================================

module regfile
  import param_tfhe_pkg::*;
  import regf_common_param_pkg::*;
#(
  parameter int PEA_PERIOD   = REGF_COEF_NB,
  parameter int PEM_PERIOD   = 4,
  parameter int PEP_PERIOD   = 1,
  parameter int URAM_LATENCY = 1+2
)
(
  input  logic                                 clk,        // clock
  input  logic                                 s_rst_n,    // synchronous reset

  //== PE MEM
  // write
  input  logic                                 pem_regf_wr_req_vld,
  output logic                                 pem_regf_wr_req_rdy,
  input  logic [REGF_WR_REQ_W-1:0]             pem_regf_wr_req,

  input  logic [REGF_COEF_NB-1:0]              pem_regf_wr_data_vld,
  output logic [REGF_COEF_NB-1:0]              pem_regf_wr_data_rdy,
  input  logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0] pem_regf_wr_data,

  // read
  input  logic                                 pem_regf_rd_req_vld,
  output logic                                 pem_regf_rd_req_rdy,
  input  logic [REGF_RD_REQ_W-1:0]             pem_regf_rd_req,

  output logic [REGF_COEF_NB-1:0]              regf_pem_rd_data_avail,
  output logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0] regf_pem_rd_data,
  output logic                                 regf_pem_rd_last_word, // valid with avail[0] - info set for both src
  output logic                                 regf_pem_rd_is_body,   // "
  output logic                                 regf_pem_rd_last_mask, // "

  //== PE ALU
  // write
  input  logic                                 pea_regf_wr_req_vld,
  output logic                                 pea_regf_wr_req_rdy,
  input  logic [REGF_WR_REQ_W-1:0]             pea_regf_wr_req,

  input  logic [REGF_COEF_NB-1:0]              pea_regf_wr_data_vld,
  output logic [REGF_COEF_NB-1:0]              pea_regf_wr_data_rdy,
  input  logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0] pea_regf_wr_data,

  // read
  input  logic                                 pea_regf_rd_req_vld,
  output logic                                 pea_regf_rd_req_rdy,
  input  logic [REGF_RD_REQ_W-1:0]             pea_regf_rd_req,

  output logic [REGF_COEF_NB-1:0]              regf_pea_rd_data_avail,
  output logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0] regf_pea_rd_data,
  output logic                                 regf_pea_rd_last_word, // valid with avail[0]
  output logic                                 regf_pea_rd_is_body,
  output logic                                 regf_pea_rd_last_mask,

  //== PE PBS
  // write
  input  logic                                 pep_regf_wr_req_vld,
  output logic                                 pep_regf_wr_req_rdy,
  input  logic [REGF_WR_REQ_W-1:0]             pep_regf_wr_req,

  input  logic [REGF_COEF_NB-1:0]              pep_regf_wr_data_vld,
  output logic [REGF_COEF_NB-1:0]              pep_regf_wr_data_rdy,
  input  logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0] pep_regf_wr_data,

  // read
  input  logic                                 pep_regf_rd_req_vld,
  output logic                                 pep_regf_rd_req_rdy,
  input  logic [REGF_RD_REQ_W-1:0]             pep_regf_rd_req,

  output logic [REGF_COEF_NB-1:0]              regf_pep_rd_data_avail,
  output logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0] regf_pep_rd_data,
  output logic                                 regf_pep_rd_last_word, // valid with avail[0]
  output logic                                 regf_pep_rd_is_body,
  output logic                                 regf_pep_rd_last_mask,

  // Write acknowledge
  output logic                                 pem_wr_ack,
  output logic                                 pea_wr_ack,
  output logic                                 pep_wr_ack
);

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int RAM_IN_PIPE = 1'b0; // TOREVIEW: No need, since the arbiters already output on a register.

  // Check parameters
  generate
    if (REGF_COEF_NB < 2) begin : __UNSUPPORTED_REGF_COEF_NB
      $fatal(1,"> ERROR: Unsupported REGF_COEF_NB. Should be > 1.");
    end
  endgenerate

// ============================================================================================== --
// Signals
// ============================================================================================== --
  // Write to Regfile RAM
  logic [REGF_SEQ-1:0][REGF_SEQ_WORD_NB-1:0][REGF_WORD_W-1:0]            warb_rram_wr_data;
  logic [REGF_SEQ-1:0]                                                   warb_rram_wr_en;
  logic [REGF_SEQ-1:0][REGF_RAM_WORD_ADD_W-1:0]                          warb_rram_wr_add;

  // Write to Body RAM
  logic [MOD_Q_W-1:0]                                                    warb_boram_wr_data;
  logic                                                                  warb_boram_wr_en;
  logic [REGF_REGID_W-1:0]                                               warb_boram_wr_add;

  // Write acknowledge
  logic [PE_NB-1:0]                                                      warb_wr_ack_1h;

  // Read Regfile RAM
  logic [REGF_SEQ-1:0]                                                   rarb_rram_rd_en;
  logic [REGF_SEQ-1:0][REGF_RAM_WORD_ADD_W-1:0]                          rarb_rram_rd_add;
  logic [REGF_SEQ-1:0][PE_NB-1:0]                                        rarb_rram_pe_id_1h;
  regf_side_t [REGF_SEQ-1:0]                                             rarb_rram_side;

  // Read body RAM
  logic                                                                  rarb_boram_rd_en;
  logic [REGF_REGID_W-1:0]                                               rarb_boram_rd_add;
  logic [PE_NB-1:0]                                                      rarb_boram_pe_id_1h;
  regf_side_t                                                            rarb_boram_side;

  // Read data
  logic [PE_NB-1:0][REGF_SEQ-1:0][REGF_SEQ_WORD_NB-1:0][REGF_WORD_W-1:0] rram_datar;
  logic [PE_NB-1:0][REGF_SEQ-1:0][REGF_SEQ_WORD_NB-1:0]                  rram_datar_avail;
  regf_side_t [PE_NB-1:0][REGF_SEQ-1:0][REGF_SEQ_WORD_NB-1:0]            rram_datar_side;

  logic [PE_NB-1:0][MOD_Q_W-1:0]                                         boram_datar;
  logic [PE_NB-1:0]                                                      boram_datar_avail;
  regf_side_t [PE_NB-1:0]                                                boram_datar_side;

// ============================================================================================== --
// Arbiters
// ============================================================================================== --
  assign pea_wr_ack = warb_wr_ack_1h[PEA_ID];
  assign pem_wr_ack = warb_wr_ack_1h[PEM_ID];
  assign pep_wr_ack = warb_wr_ack_1h[PEP_ID];

  //== Write arbiter
  regf_write_arbiter
  #(
    .PEA_PERIOD (PEA_PERIOD),
    .PEM_PERIOD (PEM_PERIOD),
    .PEP_PERIOD (PEP_PERIOD)
  ) regf_write_arbiter (
    .clk                  (clk),
    .s_rst_n              (s_rst_n),

    .pem_regf_wr_req_vld  (pem_regf_wr_req_vld),
    .pem_regf_wr_req_rdy  (pem_regf_wr_req_rdy),
    .pem_regf_wr_req      (pem_regf_wr_req),

    .pem_regf_wr_data_vld (pem_regf_wr_data_vld),
    .pem_regf_wr_data_rdy (pem_regf_wr_data_rdy),
    .pem_regf_wr_data     (pem_regf_wr_data),

    .pea_regf_wr_req_vld  (pea_regf_wr_req_vld),
    .pea_regf_wr_req_rdy  (pea_regf_wr_req_rdy),
    .pea_regf_wr_req      (pea_regf_wr_req),

    .pea_regf_wr_data_vld (pea_regf_wr_data_vld),
    .pea_regf_wr_data_rdy (pea_regf_wr_data_rdy),
    .pea_regf_wr_data     (pea_regf_wr_data),

    .pep_regf_wr_req_vld  (pep_regf_wr_req_vld),
    .pep_regf_wr_req_rdy  (pep_regf_wr_req_rdy),
    .pep_regf_wr_req      (pep_regf_wr_req),

    .pep_regf_wr_data_vld (pep_regf_wr_data_vld),
    .pep_regf_wr_data_rdy (pep_regf_wr_data_rdy),
    .pep_regf_wr_data     (pep_regf_wr_data),

    .warb_rram_wr_data    (warb_rram_wr_data),
    .warb_rram_wr_en      (warb_rram_wr_en),
    .warb_rram_wr_add     (warb_rram_wr_add),

    .warb_boram_wr_data   (warb_boram_wr_data),
    .warb_boram_wr_en     (warb_boram_wr_en),
    .warb_boram_wr_add    (warb_boram_wr_add),

    .warb_wr_ack_1h       (warb_wr_ack_1h)
  );

  //== Read arbiter
  regf_read_arbiter
  #(
    .PEA_PERIOD (PEA_PERIOD),
    .PEM_PERIOD (PEM_PERIOD),
    .PEP_PERIOD (PEP_PERIOD)
  ) regf_read_arbiter (
    .clk                   (clk),
    .s_rst_n               (s_rst_n),

    .pem_regf_rd_req_vld   (pem_regf_rd_req_vld),
    .pem_regf_rd_req_rdy   (pem_regf_rd_req_rdy),
    .pem_regf_rd_req       (pem_regf_rd_req),

    .pea_regf_rd_req_vld   (pea_regf_rd_req_vld),
    .pea_regf_rd_req_rdy   (pea_regf_rd_req_rdy),
    .pea_regf_rd_req       (pea_regf_rd_req),

    .pep_regf_rd_req_vld   (pep_regf_rd_req_vld),
    .pep_regf_rd_req_rdy   (pep_regf_rd_req_rdy),
    .pep_regf_rd_req       (pep_regf_rd_req),

    .rarb_rram_rd_en       (rarb_rram_rd_en),
    .rarb_rram_rd_add      (rarb_rram_rd_add),
    .rarb_rram_pe_id_1h    (rarb_rram_pe_id_1h),
    .rarb_rram_side        (rarb_rram_side),

    .rarb_boram_rd_en      (rarb_boram_rd_en),
    .rarb_boram_rd_add     (rarb_boram_rd_add),
    .rarb_boram_pe_id_1h   (rarb_boram_pe_id_1h),
    .rarb_boram_side       (rarb_boram_side)
  );

// ============================================================================================== --
// Reg Ram
// ============================================================================================== --
  logic [REGF_SEQ-1:0][REGF_SEQ_WORD_NB-1:0][PE_NB-1:0][REGF_WORD_W-1:0] rram_datar_l;
  logic [REGF_SEQ-1:0][REGF_SEQ_WORD_NB-1:0][PE_NB-1:0]                  rram_datar_avail_l;
  logic [REGF_SEQ-1:0][REGF_SEQ_WORD_NB-1:0][PE_NB-1:0][REGF_SIDE_W-1:0] rram_datar_side_l;

  always_comb
    for (int p=0; p<PE_NB; p=p+1)
      for (int s=0; s<REGF_SEQ; s=s+1)
        for (int i=0; i<REGF_SEQ_WORD_NB; i=i+1) begin
          rram_datar[p][s][i]       = rram_datar_l[s][i][p];
          rram_datar_avail[p][s][i] = rram_datar_avail_l[s][i][p];
          rram_datar_side[p][s][i]  = rram_datar_side_l[s][i][p];
        end

  generate
    for (genvar gen_s=0; gen_s<REGF_SEQ; gen_s=gen_s+1) begin : gen_seq_loop
      for (genvar gen_i=0; gen_i<REGF_SEQ_WORD_NB; gen_i=gen_i+1) begin : gen_word_loop
        regf_ram_unit
        #(
          .OP_W        (REGF_WORD_W),
          .DEPTH       (REGF_RAM_WORD_DEPTH),
          .PE_NB       (PE_NB),
          .RAM_LATENCY (URAM_LATENCY),
          .SIDE_W      (REGF_SIDE_W),
          .IN_PIPE     (RAM_IN_PIPE)
        ) regf_ram_unit (
          .clk         (clk),
          .s_rst_n     (s_rst_n),

          .wr_en       (warb_rram_wr_en[gen_s]),
          .wr_add      (warb_rram_wr_add[gen_s]),
          .wr_data     (warb_rram_wr_data[gen_s][gen_i]),

          .rd_en       (rarb_rram_rd_en[gen_s]),
          .rd_add      (rarb_rram_rd_add[gen_s]),
          .rd_pe_id_1h (rarb_rram_pe_id_1h[gen_s]),
          .rd_side     (rarb_rram_side[gen_s]),

          .datar       (rram_datar_l[gen_s][gen_i]),
          .datar_avail (rram_datar_avail_l[gen_s][gen_i]),
          .datar_side  (rram_datar_side_l[gen_s][gen_i])
        );
      end
    end
  endgenerate


// ============================================================================================== --
// Body Ram
// ============================================================================================== --
    regf_ram_unit
    #(
      .OP_W        (MOD_Q_W),
      .DEPTH       (REGF_REG_NB),
      .PE_NB       (PE_NB),
      .RAM_LATENCY (URAM_LATENCY), // Keep same latency as the rram
      .SIDE_W      (REGF_SIDE_W),
      .IN_PIPE     (RAM_IN_PIPE)
    ) regf_ram_unit_body (
      .clk         (clk),
      .s_rst_n     (s_rst_n),

      .wr_en       (warb_boram_wr_en),
      .wr_add      (warb_boram_wr_add),
      .wr_data     (warb_boram_wr_data),

      .rd_en       (rarb_boram_rd_en),
      .rd_add      (rarb_boram_rd_add),
      .rd_pe_id_1h (rarb_boram_pe_id_1h),
      .rd_side     (rarb_boram_side),

      .datar       (boram_datar),
      .datar_avail (boram_datar_avail),
      .datar_side  (boram_datar_side)
    );

// ============================================================================================== --
// Mux body to the output
// ============================================================================================== --
  logic [PE_NB-1:0][REGF_WORD_NB-1:0]                  rram_datar_avail_tmp;
  logic [PE_NB-1:0][REGF_WORD_NB-1:0][REGF_WORD_W-1:0] rram_datar_tmp;
  logic [PE_NB-1:0][REGF_COEF_NB-1:0]                  rram_datar_avail_tmp2;
  logic [PE_NB-1:0][REGF_COEF_NB-1:0][MOD_Q_W-1:0]     rram_datar_tmp2;

  assign rram_datar_avail_tmp = rram_datar_avail;
  assign rram_datar_tmp       = rram_datar;

  always_comb
    for (int p=0; p<PE_NB; p=p+1)
      for (int w=0; w<REGF_WORD_NB; w=w+1)
        for (int i=0; i<REGF_COEF_PER_URAM_WORD; i=i+1) begin
          rram_datar_avail_tmp2[p][w*REGF_COEF_PER_URAM_WORD+i] = rram_datar_avail_tmp[p][w];
          rram_datar_tmp2[p][w*REGF_COEF_PER_URAM_WORD+i]       = rram_datar_tmp[p][w][i*MOD_Q_W+:MOD_Q_W];
        end

  // Use intermediate var => do the mux, then set the output
  logic [PE_NB-1:0][REGF_COEF_NB-1:0]                  out_datar_avail;
  logic [PE_NB-1:0][REGF_COEF_NB-1:0][MOD_Q_W-1:0]     out_datar;
  logic [PE_NB-1:0]                                    out_datar_last_word;
  logic [PE_NB-1:0]                                    out_datar_is_body;
  logic [PE_NB-1:0]                                    out_datar_last_mask;

  logic [PE_NB-1:0][REGF_SEQ-1:0]                      boram_datar_avail_sr;
  logic [PE_NB-1:0][REGF_SEQ-1:0]                      boram_datar_avail_srD;
  logic [PE_NB-1:0][REGF_COEF_NB-1:0]                  boram_datar_avail_tmp;

  always_comb
    for (int p=0; p<PE_NB; p=p+1) begin
      boram_datar_avail_srD[p][0] = boram_datar_avail[p];
      for (int s=1; s<REGF_SEQ; s=s+1)
        boram_datar_avail_srD[p][s] = boram_datar_avail_sr[p][s-1];
      for (int s=0; s<REGF_SEQ; s=s+1)
        boram_datar_avail_tmp[p][s*REGF_SEQ_COEF_NB+:REGF_SEQ_COEF_NB] = {REGF_SEQ_COEF_NB{boram_datar_avail_srD[p][s]}};
    end

  always_ff @(posedge clk)
    if (!s_rst_n) boram_datar_avail_sr <= '0;
    else          boram_datar_avail_sr <= boram_datar_avail_srD;

  always_comb
    for (int p=0; p<PE_NB; p=p+1) begin
      out_datar_avail[p]             = boram_datar_avail_tmp[p] | rram_datar_avail_tmp2[p];

      out_datar[p][0]                = boram_datar_avail[p] ? boram_datar[p] : rram_datar_tmp2[p][0];
      out_datar[p][REGF_COEF_NB-1:1] = rram_datar_tmp2[p][REGF_COEF_NB-1:1];

      out_datar_last_word[p]         = boram_datar_avail[p] ? boram_datar_side[p].last_word : rram_datar_side[p][0][0].last_word;
      out_datar_last_mask[p]         = boram_datar_avail[p] ? boram_datar_side[p].last_mask : rram_datar_side[p][0][0].last_mask;
      out_datar_is_body[p]           = boram_datar_avail[p];
    end

  //== PEM
  assign regf_pem_rd_data_avail = out_datar_avail[PEM_ID];
  assign regf_pem_rd_data       = out_datar[PEM_ID];
  assign regf_pem_rd_last_word  = out_datar_last_word[PEM_ID];
  assign regf_pem_rd_is_body    = out_datar_is_body[PEM_ID];
  assign regf_pem_rd_last_mask  = out_datar_last_mask[PEM_ID];

  //== PEA
  assign regf_pea_rd_data_avail = out_datar_avail[PEA_ID];
  assign regf_pea_rd_data       = out_datar[PEA_ID];
  assign regf_pea_rd_last_word  = out_datar_last_word[PEA_ID];
  assign regf_pea_rd_is_body    = out_datar_is_body[PEA_ID];
  assign regf_pea_rd_last_mask  = out_datar_last_mask[PEA_ID];

  //== PEP
  assign regf_pep_rd_data_avail = out_datar_avail[PEP_ID];
  assign regf_pep_rd_data       = out_datar[PEP_ID];
  assign regf_pep_rd_last_word  = out_datar_last_word[PEP_ID];
  assign regf_pep_rd_is_body    = out_datar_is_body[PEP_ID];
  assign regf_pep_rd_last_mask  = out_datar_last_mask[PEP_ID];

endmodule
