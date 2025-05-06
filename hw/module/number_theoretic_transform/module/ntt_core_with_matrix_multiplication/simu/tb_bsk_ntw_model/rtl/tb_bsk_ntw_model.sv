// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Model for the bsk network.
// This model is a basic instanciation of the BSK network.
// To be used in testbench where the bsk network is needed.
// ==============================================================================================

module tb_bsk_ntw_model
  import param_tfhe_pkg::*;
  import top_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import ntt_core_common_param_pkg::*;
  import bsk_ntw_common_param_pkg::*;
#(
  parameter  int                    OP_W                 = 32,
  parameter  int                    BSK_SRV_NB           = 3,
  parameter  int                    BSK_CLT_NB           = 2,
  parameter  int                    BATCH_NB             = 2,
  parameter  [BSK_SRV_NB-1:0][31:0] BSK_INST_BR_LOOP_NB  = {32'd5, 32'd5, 32'd5},
  parameter  [BSK_SRV_NB-1:0][31:0] BSK_INST_BR_LOOP_OFS = {32'd10, 32'd5, 32'd0},
  parameter  string                 FILE_BSK_PREFIX      = "input/bsk",
  parameter  string                 FILE_DATA_TYPE       = "ascii_hex",
  parameter  int                    RAM_LATENCY          = 1,
  parameter  int                    URAM_LATENCY         = 1+4

)(
  input  logic                                                           clk,
  input  logic                                                           s_rst_n,

  // write in RAM
  input  logic                                                           do_wr_bsk,
  output logic                                                           wr_bsk_done,

  // batch_cmd
  input  logic [BSK_CLT_NB-1:0][BR_BATCH_CMD_W-1:0]                      batch_cmd,
  input  logic [BSK_CLT_NB-1:0]                                          batch_cmd_avail,

  // bsk_cl_ntt_bsk -> ntt
  output logic [BSK_CLT_NB-1:0][PSI-1:0][R-1:0][GLWE_K_P1-1:0][OP_W-1:0] bsk_cl_ntt_bsk,
  output logic [BSK_CLT_NB-1:0][PSI-1:0][R-1:0][GLWE_K_P1-1:0]           bsk_cl_ntt_vld,
  input  logic [BSK_CLT_NB-1:0][PSI-1:0][R-1:0][GLWE_K_P1-1:0]           bsk_cl_ntt_rdy,

  output logic [BSK_SRV_NB-1:0][SRV_ERROR_NB-1:0]                        bsk_error_server,
  output logic [BSK_CLT_NB-1:0][CLT_ERROR_NB-1:0]                        bsk_error_client,
  output logic [BSK_SRV_NB-1:0]                                          error_source_bsk_wr_open
);

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int BSK_RAM_DEPTH = BSK_INST_BR_LOOP_NB[BSK_SRV_NB-1] * BSK_BATCH_COEF_NB / BSK_DIST_COEF_NB;
  localparam int BSK_ADD_W     = $clog2(BSK_RAM_DEPTH);

// ============================================================================================== --
// type
// ============================================================================================== --
  typedef struct packed {
    logic [BSK_ADD_W-1:0]                  wr_add;
    logic [BSK_DIST_COEF_NB-1:0][OP_W-1:0] wr_data;
  } bsk_wr_t;

// ============================================================================================== --
// Internal signals
// ============================================================================================== --
  // bsk_srv_bdc_bsk
  logic [BSK_SRV_NB-1:0][BSK_DIST_COEF_NB-1:0][OP_W-1:0] bsk_srv_bdc_bsk;
  logic [BSK_SRV_NB-1:0][BSK_DIST_COEF_NB-1:0]           bsk_srv_bdc_avail;
  logic [BSK_SRV_NB-1:0][BSK_UNIT_W-1:0]                 bsk_srv_bdc_unit;
  logic [BSK_SRV_NB-1:0][BSK_GROUP_W-1:0]                bsk_srv_bdc_group;
  logic [BSK_SRV_NB-1:0][LWE_K_W-1:0]                    bsk_srv_bdc_br_loop;

  // bsk_arb -> bsk_srv
  logic [BR_BATCH_CMD_W-1:0]                             arb_srv_batch_cmd;
  logic                                                  arb_srv_batch_cmd_avail;

  // wr -> bsk_srv
  logic [BSK_SRV_NB-1:0]                                 bsk_wr_en;
  logic [BSK_SRV_NB-1:0][BSK_DIST_COEF_NB-1:0][OP_W-1:0] bsk_wr_data;
  logic [BSK_SRV_NB-1:0][BSK_ADD_W-1:0]                  bsk_wr_add;

  // Merged signals sent to bsk_cl
  logic [BSK_DIST_COEF_NB-1:0][OP_W-1:0]                 bdc_merged_bsk;
  logic [BSK_DIST_COEF_NB-1:0]                           bdc_merged_avail;
  logic [BSK_UNIT_W-1:0]                                 bdc_merged_unit;
  logic [BSK_GROUP_W-1:0]                                bdc_merged_group;
  logic [LWE_K_W-1:0]                                    bdc_merged_br_loop;

  logic [BSK_SRV_NB-1:0][BSK_SRV_NB-2:0] bsk_neigh_srv_bdc_avail;

// ============================================================================================== --
// Arbiter
// ============================================================================================== --
  bsk_ntw_cmd_arbiter
  #(
    .BATCH_NB   (BATCH_NB  ),
    .BSK_CLT_NB (BSK_CLT_NB)
  )
  bsk_ntw_cmd_arbiter
  (
    .clk                    (clk                    ),
    .s_rst_n                (s_rst_n                ),

    .batch_cmd              (batch_cmd              ),
    .batch_cmd_avail        (batch_cmd_avail        ),

    .arb_srv_batch_cmd      (arb_srv_batch_cmd      ),
    .arb_srv_batch_cmd_avail(arb_srv_batch_cmd_avail),

    .srv_bdc_avail          (bdc_merged_avail[0]    )
  );


// ============================================================================================== --
// Servers
// ============================================================================================== --
  generate
    for (genvar gen_i=0; gen_i<BSK_SRV_NB; gen_i=gen_i+1) begin : srv_inst_loop_gen
      bsk_ntw_server
      #(
        .OP_W             (OP_W),
        .NEIGH_SERVER_NB  (BSK_SRV_NB-1),
        .BR_LOOP_OFS      (BSK_INST_BR_LOOP_OFS[gen_i]),
        .BR_LOOP_NB       (BSK_INST_BR_LOOP_NB[gen_i]),
        .URAM_LATENCY     (URAM_LATENCY)
      )
      bsk_ntw_server
      (
        .clk                      (clk),
        .s_rst_n                  (s_rst_n),

        .srv_bdc_bsk              (bsk_srv_bdc_bsk[gen_i]),
        .srv_bdc_avail            (bsk_srv_bdc_avail[gen_i]),
        .srv_bdc_unit             (bsk_srv_bdc_unit[gen_i]),
        .srv_bdc_group            (bsk_srv_bdc_group[gen_i]),
        .srv_bdc_br_loop          (bsk_srv_bdc_br_loop[gen_i]),

        .neigh_srv_bdc_avail      (bsk_neigh_srv_bdc_avail[gen_i]),

        .arb_srv_batch_cmd        (arb_srv_batch_cmd),
        .arb_srv_batch_cmd_avail  (arb_srv_batch_cmd_avail),

        .wr_en                    (bsk_wr_en[gen_i]),
        .wr_data                  (bsk_wr_data[gen_i]),
        .wr_add                   (bsk_wr_add[gen_i]),

        .error                    (bsk_error_server[gen_i])
      );
    end
  endgenerate

// ============================================================================================== --
// Clients
// ============================================================================================== --
  generate
    for (genvar gen_i=0; gen_i<BSK_CLT_NB; gen_i=gen_i+1) begin : clt_inst_loop_gen
      bsk_ntw_client
      #(
        .OP_W        (OP_W),
        .BATCH_NB    (BATCH_NB),
        .RAM_LATENCY (RAM_LATENCY)
      )
      bsk_ntw_client
      (
        .clk             (clk),
        .s_rst_n         (s_rst_n),

        .srv_cl_bsk      (bdc_merged_bsk),
        .srv_cl_avail    (bdc_merged_avail),
        .srv_cl_unit     (bdc_merged_unit),
        .srv_cl_group    (bdc_merged_group),
        .srv_cl_br_loop  (bdc_merged_br_loop),

        .cl_ntt_bsk      (bsk_cl_ntt_bsk[gen_i]),
        .cl_ntt_vld      (bsk_cl_ntt_vld[gen_i]),
        .cl_ntt_rdy      (bsk_cl_ntt_rdy[gen_i]),

        .batch_cmd       (batch_cmd[gen_i]),
        .batch_cmd_avail (batch_cmd_avail[gen_i]),

        .error           (bsk_error_client[gen_i])
      );
    end
  endgenerate

  // ============================================================================================ //
  // Merge signals for clients
  // ============================================================================================ //
  always_comb begin
    bdc_merged_bsk     = '0;
    bdc_merged_avail   = '0;
    bdc_merged_unit    = '0;
    bdc_merged_group   = '0;
    bdc_merged_br_loop = '0;
    for (int i = 0; i < BSK_SRV_NB; i = i + 1) begin
      bdc_merged_bsk     = bdc_merged_bsk | bsk_srv_bdc_bsk[i];
      bdc_merged_avail   = bdc_merged_avail | bsk_srv_bdc_avail[i];
      bdc_merged_unit    = bdc_merged_unit | bsk_srv_bdc_unit[i];
      bdc_merged_group   = bdc_merged_group | bsk_srv_bdc_group[i];
      bdc_merged_br_loop = bdc_merged_br_loop | bsk_srv_bdc_br_loop[i];
    end
  end

// ============================================================================================= --
// Neighbours
// ============================================================================================= --
  logic [BSK_SRV_NB-1:0] bsk_srv_bdc_avail_0_a;
  always_comb
    for (int i=0; i<BSK_SRV_NB; i=i+1)
      bsk_srv_bdc_avail_0_a[i] = bsk_srv_bdc_avail[i][0];

  generate
    for (genvar gen_i=0; gen_i<BSK_SRV_NB; gen_i=gen_i+1) begin : neigh_loop_gen
      if (gen_i == 0) begin
        assign bsk_neigh_srv_bdc_avail[0]             = bsk_srv_bdc_avail_0_a[BSK_SRV_NB-1:1];
      end
      else if (gen_i == BSK_SRV_NB-1) begin
        assign bsk_neigh_srv_bdc_avail[BSK_SRV_NB-1] = bsk_srv_bdc_avail_0_a[BSK_SRV_NB-2:0];
      end
      else begin
        assign bsk_neigh_srv_bdc_avail[gen_i] = {bsk_srv_bdc_avail_0_a[BSK_SRV_NB-1:gen_i+1],bsk_srv_bdc_avail_0_a[gen_i-1:0]};
      end
    end
  endgenerate

// ============================================================================================= --
// Write in BSK server
// ============================================================================================= --
  logic [BSK_SRV_NB-1:0]            bsk_source_eof;
  logic [BSK_SRV_NB-1:0]            bsk_source_eof_dly;
  logic                             bsk_wr_en_tmp;
  integer                           bsk_wr_inst_id;
  integer                           bsk_wr_inst_idD;

  assign wr_bsk_done = (bsk_source_eof == {BSK_SRV_NB{1'b1}});

  assign bsk_wr_en_tmp   = do_wr_bsk;
  assign bsk_wr_inst_idD = (bsk_source_eof != bsk_source_eof_dly) ? bsk_wr_inst_id + 1 : bsk_wr_inst_id;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      bsk_wr_inst_id     <= 0;
      bsk_source_eof_dly <= '0;
    end
    else begin
      bsk_wr_inst_id     <= bsk_wr_inst_idD;
      bsk_source_eof_dly <= bsk_source_eof;
    end

  generate
    for (genvar gen_i = 0; gen_i < BSK_SRV_NB; gen_i=gen_i+1) begin : gen_loop_source_bsk_wr
      bsk_wr_t c;
      logic vld;
      logic rdy;
      bit error_open;
      logic [BSK_ADD_W-1:0] wr_add;

      assign bsk_wr_data[gen_i] = c;
      assign bsk_wr_en[gen_i]   = vld & bsk_wr_en_tmp & (bsk_wr_inst_id == gen_i);
      assign rdy                = bsk_wr_en_tmp & (bsk_wr_inst_id == gen_i);
      assign bsk_wr_add[gen_i]  = wr_add;

      always_ff @(posedge clk)
        if (!s_rst_n) wr_add <= '0;
        else            wr_add <= bsk_wr_en[gen_i] ? wr_add + 1 : wr_add;

      stream_source
      #(
        .FILENAME   ($sformatf("%s_%0d.dat",FILE_BSK_PREFIX,gen_i)),
        .DATA_TYPE  (FILE_DATA_TYPE),
        .DATA_W     ($size(bsk_wr_t)),
        .RAND_RANGE (1),
        .KEEP_VLD   (1),
        .MASK_DATA  ("none")
      )
      source_bsk_wr
      (
          .clk        (clk),
          .s_rst_n    (s_rst_n),

          .data       (c),
          .vld        (vld),
          .rdy        (rdy),

          .throughput (1)
      );

      assign bsk_source_eof[gen_i] = source_bsk_wr.eof;
      assign error_source_bsk_wr_open[gen_i] = error_open;
      initial begin
        error_open = 1'b0;
        if (!source_bsk_wr.open()) begin
          $display("%t > ERROR: Opening bsk %0d stream source", $time, gen_i);
          error_open = 1'b1;
        end
        source_bsk_wr.start(0);
      end
    end
  endgenerate


endmodule

