// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the distribution of the bootstrapping key (BSK).
// This module contains part of the key.
// It delivers the keys to bsk_ntw_clients that are closer to the processing path.
// The host fills the values. They should be valid before running the blind rotation.
// Note that the keys should be given in reverse order (R,N).
// Also note that a unique BSK is used for the process.
// Xilinx UltraRAM are used (72x4096) RAMs.
//
// RAM_W is chosen according to the throughput we need.
// A batch command is received before the NTT starts on this batch. The bsk_ntw_server has the
// time of the S-1 forward stages to send all the keys for this batch.
//
// Note : When this server is not sollicited, its output should be 0, to let the other servers
//   drive the bus.
// ==============================================================================================

module bsk_ntw_server
  import param_tfhe_pkg::*;
  import top_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import bsk_ntw_common_param_pkg::*;
#(
  parameter  int OP_W               = 32,
  parameter  int NEIGH_SERVER_NB    = 2, // Use 1 if no neighbour.
  parameter  int BR_LOOP_OFS        = 0,
  parameter  int BR_LOOP_NB         = 98, // LWE_K / nb of srv
  parameter  int URAM_LATENCY       = 1+2,
  localparam int RAM_DEPTH          = BR_LOOP_NB * BSK_BATCH_COEF_NB / BSK_DIST_COEF_NB,
  localparam int RAM_ADD_W          = $clog2(RAM_DEPTH)
)
(
  input  logic                                  clk,        // clock
  input  logic                                  s_rst_n,    // synchronous reset

  output logic [BSK_DIST_COEF_NB-1:0][OP_W-1:0] srv_bdc_bsk,       // broadcast
  output logic [BSK_DIST_COEF_NB-1:0]           srv_bdc_avail,
  output logic [BSK_UNIT_W-1:0]                 srv_bdc_unit,
  output logic [BSK_GROUP_W-1:0]                srv_bdc_group,
  output logic [LWE_K_W-1:0]                    srv_bdc_br_loop,

  // From neighbour servers
  input  logic [NEIGH_SERVER_NB-1:0]            neigh_srv_bdc_avail,

  // Broadcast from acc
  input  logic [BR_BATCH_CMD_W-1:0]             arb_srv_batch_cmd,
  input  logic                                  arb_srv_batch_cmd_avail, // pulse

  // Write interface
  input  logic                                  wr_en,
  input  logic [BSK_DIST_COEF_NB-1:0][OP_W-1:0] wr_data,
  input  logic [RAM_ADD_W-1:0]                  wr_add,

  // Error
  output logic [SRV_ERROR_NB-1:0]               error

);

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int URAM_W         = 72;
  localparam int RAM_RD_NB      = URAM_W / OP_W; // number of coef read per RAM, per cycle.
  localparam int RAM_NB         = BSK_DIST_COEF_NB / RAM_RD_NB;
  localparam int RAM_W          = RAM_RD_NB * OP_W;
  localparam int EXTRA_W        = LWE_K_W; // extra data to be delayed

// ============================================================================================== --
// Type
// ============================================================================================== --
  typedef struct packed {
    logic [LWE_K_W-1:0]          br_loop;
  } extra_t;

// ============================================================================================== --
// bsk_ntw_server
// ============================================================================================== --
// ---------------------------------------------------------------------------------------------- --
// Input register
// ---------------------------------------------------------------------------------------------- --
  br_batch_cmd_t        s2_batch_cmd;
  logic                 s2_batch_avail;

  always_ff @(posedge clk)
    s2_batch_cmd <= arb_srv_batch_cmd_avail ? arb_srv_batch_cmd : s2_batch_cmd;

  always_ff @(posedge clk)
    if (!s_rst_n) s2_batch_avail <= 1'b0;
    else          s2_batch_avail <= arb_srv_batch_cmd_avail;

// ---------------------------------------------------------------------------------------------- --
// batch_cmd pre process
// ---------------------------------------------------------------------------------------------- --
  logic                 s2_batch_rdy;
  logic [RAM_ADD_W-1:0] s2_batch_add_ofs;
  logic                 s2_do_read;

  assign s2_batch_add_ofs = (s2_batch_cmd.br_loop - BR_LOOP_OFS)  * BSK_DIST_ITER_NB;
  assign s2_do_read       = (s2_batch_cmd.br_loop >= BR_LOOP_OFS)
                            & (s2_batch_cmd.br_loop < (BR_LOOP_OFS+BR_LOOP_NB));

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      if (s2_batch_avail) begin
        assert(s2_batch_rdy)
        else begin
          $fatal(1, "%t > ERROR: Server cmd_fifo overflow!",$time);
        end
      end
    end
// pragma translate_on

  // precompute the address offset.
  logic [RAM_ADD_W-1:0]   s3_batch_add_ofs;
  logic                   s3_do_read;
  logic [LWE_K_W-1:0]     s3_br_loop;
  logic                   s3_batch_vld;
  logic                   s3_batch_rdy;
  fifo_reg #(
    .WIDTH          (1 + RAM_ADD_W + LWE_K_W),
    .DEPTH          (SRV_CMD_FIFO_DEPTH-1),
    .LAT_PIPE_MH ({1'b1, 1'b1})
  ) cmd_fifo (
    .clk     (clk),
    .s_rst_n (s_rst_n),

    .in_data ({s2_batch_cmd.br_loop,s2_batch_add_ofs,s2_do_read}),
    .in_vld  (s2_batch_avail),
    .in_rdy  (s2_batch_rdy),

    .out_data({s3_br_loop, s3_batch_add_ofs,s3_do_read}),
    .out_vld (s3_batch_vld),
    .out_rdy (s3_batch_rdy)
  );

// ---------------------------------------------------------------------------------------------- --
// Global pointers
// ---------------------------------------------------------------------------------------------- --
// The following pointers keep track of the current reading by all the servers.
// This will help with the command "consumption".
// Count the readings to be done for a batch : N*GLWE_K_P1*INTL_L / BSK_DIST_COEF_NB
  logic [BSK_DIST_ITER_W-1:0] s3_gl_rp;
  logic [BSK_DIST_ITER_W-1:0] s3_gl_rpD;
  logic                  s3_last_gl_rp;
  logic                  s3_first_gl_rp;
  logic                  s3_gl_rp_inc;

  assign s3_gl_rpD      = s3_gl_rp_inc ? s3_last_gl_rp ? '0 : s3_gl_rp + 1 : s3_gl_rp;
  assign s3_last_gl_rp  = (s3_gl_rp == BSK_DIST_ITER_NB-1);
  assign s3_first_gl_rp = (s3_gl_rp == 0);

  always_ff @(posedge clk)
    if (!s_rst_n) s3_gl_rp <= '0;
    else          s3_gl_rp <= s3_gl_rpD;

// ---------------------------------------------------------------------------------------------- --
// RAM logic
// ---------------------------------------------------------------------------------------------- --
  logic [RAM_NB-1:0][RAM_RD_NB-1:0][OP_W-1:0] ram_rd_data_dly_a;
  logic [RAM_NB-1:0][RAM_RD_NB-1:0]           ram_rd_data_avail_dly_a;
  logic [RAM_NB-1:0][RAM_RD_NB-1:0]           ram_rd_data_avail_dly_aD;
  extra_t [URAM_LATENCY:0]                    ram_rd_extra_dly;
  extra_t [URAM_LATENCY:0]                    ram_rd_extra_dlyD;

  assign ram_rd_extra_dlyD[0].br_loop      = s3_br_loop;
  assign ram_rd_extra_dlyD[URAM_LATENCY:1] = ram_rd_extra_dly[URAM_LATENCY-1:0];

  always_ff @(posedge clk)
    ram_rd_extra_dly <= ram_rd_extra_dlyD;

  genvar gen_i;
  generate
    for (gen_i=0; gen_i<RAM_NB; gen_i=gen_i+1) begin : bsk_server_loop
      // ----------------------------------------------------------------------- --
      // RAM control
      // ----------------------------------------------------------------------- --
      (* keep = "true" *) logic                   ram_wr_en;
      (* keep = "true" *) logic                   ram_rd_en;
      (* keep = "true" *) logic [RAM_ADD_W-1:0]   ram_rd_add;
      (* keep = "true" *) logic [RAM_ADD_W-1:0]   ram_wr_add;
      (* keep = "true" *) logic [RAM_W-1:0]       ram_wr_data;
      (* keep = "true" *) logic [URAM_LATENCY:0]  ram_rd_en_dly;
      (* keep = "true" *) logic [RAM_RD_NB-1:0]   ram_rd_data_avail_dly;
      logic [RAM_W-1:0]                  ram_rd_data;
      logic [RAM_RD_NB-1:0][OP_W-1:0]    ram_rd_data_dly;
      logic [URAM_LATENCY:0]             ram_rd_en_dlyD;
      logic                              ram_rd_enD;
      logic                              ram_wr_enD;
      logic [RAM_ADD_W-1:0]              ram_rd_addD;
      logic [RAM_ADD_W-1:0]              ram_wr_addD;
      logic [RAM_RD_NB-1:0][OP_W-1:0]    ram_rd_data_dlyD;
      logic [RAM_W-1:0]                  ram_wr_dataD;
      logic [RAM_RD_NB-1:0]              ram_rd_data_avail_dlyD;

      assign ram_wr_enD                       = wr_en;
      assign ram_rd_enD                       = s3_do_read & s3_batch_vld;
      assign ram_wr_addD                      = wr_add;
      assign ram_rd_addD                      = s3_gl_rp + s3_batch_add_ofs;
      assign ram_rd_en_dlyD[0]                = ram_rd_enD;
      assign ram_rd_en_dlyD[URAM_LATENCY:1]   = ram_rd_en_dly[URAM_LATENCY-1:0];

      assign ram_rd_data_avail_dlyD = {2{ram_rd_en_dly[URAM_LATENCY]}};

      always_comb
        for (int i=0; i<RAM_RD_NB; i=i+1)
          ram_rd_data_dlyD[i] = ram_rd_data_avail_dlyD[i] ? ram_rd_data[i*OP_W+:OP_W] : '0;

      assign ram_wr_dataD = wr_en ? wr_data[gen_i*RAM_RD_NB+:RAM_RD_NB] : ram_wr_data;

      always_ff @(posedge clk) begin
        if (!s_rst_n) begin
          ram_wr_en             <= 1'b0;
          ram_rd_en             <= 1'b0;
          ram_rd_en_dly         <= '0;
          ram_rd_data_avail_dly <= '0;
        end
        else begin
          ram_wr_en             <= ram_wr_enD;
          ram_rd_en             <= ram_rd_enD   ;
          ram_rd_en_dly         <= ram_rd_en_dlyD;
          ram_rd_data_avail_dly <= ram_rd_data_avail_dlyD;
        end
      end
      always_ff @(posedge clk) begin
        ram_rd_add      <= ram_rd_addD;
        ram_wr_add      <= ram_wr_addD;
        ram_wr_data     <= ram_wr_dataD;
        ram_rd_data_dly <= ram_rd_data_dlyD;
      end

      assign ram_rd_data_dly_a[gen_i]        = ram_rd_data_dly;
      assign ram_rd_data_avail_dly_a[gen_i]  = ram_rd_data_avail_dly;
      assign ram_rd_data_avail_dly_aD[gen_i] = ram_rd_data_avail_dlyD;

      // ----------------------------------------------------------------------- --
      // RAM
      // ----------------------------------------------------------------------- --
      ram_wrapper_1R1W #(
        .WIDTH             (RAM_W),
        .DEPTH             (RAM_DEPTH),
        .RD_WR_ACCESS_TYPE (1),
        .KEEP_RD_DATA      (0),
        .RAM_LATENCY       (URAM_LATENCY)
      ) bsk_ram
      (
        .clk       (clk),
        .s_rst_n   (s_rst_n),

        .rd_en     (ram_rd_en),
        .rd_add    (ram_rd_add),
        .rd_data   (ram_rd_data),

        .wr_en     (ram_wr_en),
        .wr_add    (ram_wr_add),
        .wr_data   (ram_wr_data)
      );

    end
  endgenerate

// ---------------------------------------------------------------------------------------------- --
// Control
// ---------------------------------------------------------------------------------------------- --
  logic s3_neigh_do_read;
  logic s3_neigh_do_readD;

  assign s3_neigh_do_readD = |neigh_srv_bdc_avail;
  assign s3_gl_rp_inc      = s3_neigh_do_read | (s3_batch_vld & s3_do_read);

  assign s3_batch_rdy  =  s3_gl_rp_inc & s3_last_gl_rp;

  always_ff @(posedge clk)
    if (!s_rst_n) s3_neigh_do_read <= 1'b0;
    else          s3_neigh_do_read <= s3_neigh_do_readD;

// ---------------------------------------------------------------------------------------------- --
// Output
// ---------------------------------------------------------------------------------------------- --
  logic [BSK_UNIT_W-1:0]  s4_rd_unit;
  logic [BSK_UNIT_W-1:0]  s4_rd_unitD;
  logic [BSK_GROUP_W-1:0] s4_rd_group;
  logic [BSK_GROUP_W-1:0] s4_rd_groupD;
  logic [LWE_K_W-1:0]     s4_br_loop;
  logic [LWE_K_W-1:0]     s4_br_loopD;
  logic                   s4_last_rd_unit;
  logic                   s4_last_rd_group;

  assign s4_last_rd_unit  = s4_rd_unit == BSK_UNIT_NB-1;
  assign s4_last_rd_group = s4_rd_group == BSK_GROUP_NB-1;

  assign s4_rd_unitD     = ram_rd_data_avail_dly_a[0][0] ? s4_last_rd_unit ? '0 : s4_rd_unit+1 : s4_rd_unit;
  assign s4_rd_groupD    = ram_rd_data_avail_dly_a[0][0] && s4_last_rd_unit ? s4_last_rd_group ? '0 : s4_rd_group+1 : s4_rd_group;
  assign s4_br_loopD     = ram_rd_extra_dly[URAM_LATENCY].br_loop;

  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      s4_rd_unit  <= '0;
      s4_rd_group <= '0;
    end
    else begin
      s4_rd_unit  <= s4_rd_unitD;
      s4_rd_group <= s4_rd_groupD;
    end
  end

  always_ff @(posedge clk) begin
    s4_br_loop  <= s4_br_loopD;
  end

  assign srv_bdc_avail   = ram_rd_data_avail_dly_a;
  assign srv_bdc_bsk     = ram_rd_data_dly_a; // already masked //srv_bdc_avail ? ram_rd_data_dly_a : '0;
  assign srv_bdc_unit    = srv_bdc_avail ? s4_rd_unit  : '0;
  assign srv_bdc_group   = srv_bdc_avail ? s4_rd_group : '0;
  assign srv_bdc_br_loop = srv_bdc_avail ? s4_br_loop  : '0;

// ---------------------------------------------------------------------------------------------- --
// Errors
// ---------------------------------------------------------------------------------------------- --
  // The FIFO should always be ready for an input command.
  logic error_cmd_overflow;
  logic error_cmd_overflowD;

  assign error_cmd_overflowD = s2_batch_avail & ~s2_batch_rdy;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      error_cmd_overflow  <= 1'b0;
    end
    else begin
      error_cmd_overflow  <= error_cmd_overflowD;
    end

  assign error = {error_cmd_overflow};

endmodule
