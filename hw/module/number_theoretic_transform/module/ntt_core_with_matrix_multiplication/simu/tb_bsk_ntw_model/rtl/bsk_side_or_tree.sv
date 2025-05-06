// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
//
// ==============================================================================================

module bsk_side_or_tree
  import param_tfhe_pkg::*;
  import bsk_ntw_common_param_pkg::*;
  #(
    // Server number
    parameter int SRV_NB        = 6,
    // Coefficient width
    parameter int OP_W          = 32
  )(
    // System interface
    input                                               clk,
    // Servers interface 
    input  [     SRV_NB-1:0][BSK_DIST_COEF_NB-1:0][OP_W-1:0] bsk_srv_bdc_bsk_in,
    input  [     SRV_NB-1:0][BSK_DIST_COEF_NB-1:0]           bsk_srv_bdc_avail_in,
    input  [     SRV_NB-1:0][ BSK_UNIT_W-1:0]                bsk_srv_bdc_unit_in,
    input  [     SRV_NB-1:0][BSK_GROUP_W-1:0]                bsk_srv_bdc_group_in,
    input  [     SRV_NB-1:0][    LWE_K_W-1:0]                bsk_srv_bdc_br_loop_in,

    output [BSK_DIST_COEF_NB-1:0][       OP_W-1:0]           bsk_srv_bdc_bsk_1_out,
    output [BSK_DIST_COEF_NB-1:0]                            bsk_srv_bdc_avail_1_out,
    output [ BSK_UNIT_W-1:0]                                 bsk_srv_bdc_unit_1_out,
    output [BSK_GROUP_W-1:0]                                 bsk_srv_bdc_group_1_out,
    output [    LWE_K_W-1:0]                                 bsk_srv_bdc_br_loop_1_out,

    input  [BSK_DIST_COEF_NB-1:0][       OP_W-1:0]           bsk_srv_bdc_bsk_2_in,
    input  [BSK_DIST_COEF_NB-1:0]                            bsk_srv_bdc_avail_2_in,
    input  [ BSK_UNIT_W-1:0]                                 bsk_srv_bdc_unit_2_in,
    input  [BSK_GROUP_W-1:0]                                 bsk_srv_bdc_group_2_in,
    input  [    LWE_K_W-1:0]                                 bsk_srv_bdc_br_loop_2_in,

    output [BSK_DIST_COEF_NB-1:0][       OP_W-1:0]           bsk_srv_bdc_bsk_2_out,
    output [BSK_DIST_COEF_NB-1:0]                            bsk_srv_bdc_avail_2_out,
    output [ BSK_UNIT_W-1:0]                                 bsk_srv_bdc_unit_2_out,
    output [BSK_GROUP_W-1:0]                                 bsk_srv_bdc_group_2_out,
    output [    LWE_K_W-1:0]                                 bsk_srv_bdc_br_loop_2_out
  );

  // Input Register barrier ------------------------------------------------------------------------
  logic [     SRV_NB-1:0][BSK_DIST_COEF_NB-1:0][OP_W-1:0]  bsk_srv_bdc_bsk;
  logic [     SRV_NB-1:0][BSK_DIST_COEF_NB-1:0]            bsk_srv_bdc_avail;
  logic [     SRV_NB-1:0][ BSK_UNIT_W-1:0]                 bsk_srv_bdc_unit;
  logic [     SRV_NB-1:0][BSK_GROUP_W-1:0]                 bsk_srv_bdc_group;
  logic [     SRV_NB-1:0][    LWE_K_W-1:0]                 bsk_srv_bdc_br_loop;
  
  logic [BSK_DIST_COEF_NB-1:0][       OP_W-1:0]            bsk_srv_bdc_bsk_2;
  logic [BSK_DIST_COEF_NB-1:0]                             bsk_srv_bdc_avail_2;
  logic [ BSK_UNIT_W-1:0]                                  bsk_srv_bdc_unit_2;
  logic [BSK_GROUP_W-1:0]                                  bsk_srv_bdc_group_2;
  logic [    LWE_K_W-1:0]                                  bsk_srv_bdc_br_loop_2;

  // from servers
  generate
    for (genvar gen_i = 0; gen_i < SRV_NB ; gen_i = gen_i + 1) begin : srv_inst_loop
      always_ff @(posedge clk) begin
        bsk_srv_bdc_bsk[gen_i]     <= bsk_srv_bdc_bsk_in[gen_i];
        bsk_srv_bdc_avail[gen_i]   <= bsk_srv_bdc_avail_in[gen_i];
        bsk_srv_bdc_unit[gen_i]    <= bsk_srv_bdc_unit_in[gen_i];
        bsk_srv_bdc_group[gen_i]   <= bsk_srv_bdc_group_in[gen_i];
        bsk_srv_bdc_br_loop[gen_i] <= bsk_srv_bdc_br_loop_in[gen_i];
      end
    end
  endgenerate

  // from side SLR 
  always_ff @(posedge clk) begin
    bsk_srv_bdc_bsk_2     <= bsk_srv_bdc_bsk_2_in;
    bsk_srv_bdc_avail_2   <= bsk_srv_bdc_avail_2_in;
    bsk_srv_bdc_unit_2    <= bsk_srv_bdc_unit_2_in;
    bsk_srv_bdc_group_2   <= bsk_srv_bdc_group_2_in;
    bsk_srv_bdc_br_loop_2 <= bsk_srv_bdc_br_loop_2_in;
  end

  // Merging signals for clients - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  logic [BSK_DIST_COEF_NB-1:0][OP_W-1:0] slr0_or_1_bsk;
  logic [BSK_DIST_COEF_NB-1:0]           slr0_or_1_avail;
  logic [ BSK_UNIT_W-1:0]                slr0_or_1_unit;
  logic [BSK_GROUP_W-1:0]                slr0_or_1_group;
  logic [    LWE_K_W-1:0]                slr0_or_1_br_loop;

  always_comb begin
    slr0_or_1_bsk     = bsk_srv_bdc_bsk[0]     | bsk_srv_bdc_bsk[1];
    slr0_or_1_avail   = bsk_srv_bdc_avail[0]   | bsk_srv_bdc_avail[1];
    slr0_or_1_unit    = bsk_srv_bdc_unit[0]    | bsk_srv_bdc_unit[1];
    slr0_or_1_group   = bsk_srv_bdc_group[0]   | bsk_srv_bdc_group[1];
    slr0_or_1_br_loop = bsk_srv_bdc_br_loop[0] | bsk_srv_bdc_br_loop[1];
  end

  // Output Register barrier -----------------------------------------------------------------------
  logic [BSK_DIST_COEF_NB-1:0][OP_W-1:0] bsk_srv_bdc_bsk_1_D;
  logic [BSK_DIST_COEF_NB-1:0]           bsk_srv_bdc_avail_1_D;
  logic [ BSK_UNIT_W-1:0]                bsk_srv_bdc_unit_1_D;
  logic [BSK_GROUP_W-1:0]                bsk_srv_bdc_group_1_D;
  logic [    LWE_K_W-1:0]                bsk_srv_bdc_br_loop_1_D;

  logic [BSK_DIST_COEF_NB-1:0][OP_W-1:0] bsk_srv_bdc_bsk_2_D;
  logic [BSK_DIST_COEF_NB-1:0]           bsk_srv_bdc_avail_2_D;
  logic [ BSK_UNIT_W-1:0]                bsk_srv_bdc_unit_2_D;
  logic [BSK_GROUP_W-1:0]                bsk_srv_bdc_group_2_D;
  logic [    LWE_K_W-1:0]                bsk_srv_bdc_br_loop_2_D;

  always_ff @(posedge clk) begin
    bsk_srv_bdc_bsk_1_D      <= slr0_or_1_bsk;
    bsk_srv_bdc_avail_1_D    <= slr0_or_1_avail;
    bsk_srv_bdc_unit_1_D     <= slr0_or_1_unit;
    bsk_srv_bdc_group_1_D    <= slr0_or_1_group;
    bsk_srv_bdc_br_loop_1_D  <= slr0_or_1_br_loop;
  end

  always_ff @(posedge clk) begin
    bsk_srv_bdc_bsk_2_D     = slr0_or_1_bsk     | bsk_srv_bdc_bsk_2;
    bsk_srv_bdc_avail_2_D   = slr0_or_1_avail   | bsk_srv_bdc_avail_2;
    bsk_srv_bdc_unit_2_D    = slr0_or_1_unit    | bsk_srv_bdc_unit_2;
    bsk_srv_bdc_group_2_D   = slr0_or_1_group   | bsk_srv_bdc_group_2;
    bsk_srv_bdc_br_loop_2_D = slr0_or_1_br_loop | bsk_srv_bdc_br_loop_2;
  end

  // Output assignations ---------------------------------------------------------------------------
  assign bsk_srv_bdc_bsk_1_out      = bsk_srv_bdc_bsk_1_D;
  assign bsk_srv_bdc_avail_1_out    = bsk_srv_bdc_avail_1_D;
  assign bsk_srv_bdc_unit_1_out     = bsk_srv_bdc_unit_1_D;
  assign bsk_srv_bdc_group_1_out    = bsk_srv_bdc_group_1_D;
  assign bsk_srv_bdc_br_loop_1_out  = bsk_srv_bdc_br_loop_1_D;

  assign bsk_srv_bdc_bsk_2_out      = bsk_srv_bdc_bsk_2_D;
  assign bsk_srv_bdc_avail_2_out    = bsk_srv_bdc_avail_2_D;
  assign bsk_srv_bdc_unit_2_out     = bsk_srv_bdc_unit_2_D;
  assign bsk_srv_bdc_br_loop_2_out  = bsk_srv_bdc_group_2_D;
  assign bsk_srv_bdc_group_2_out    = bsk_srv_bdc_br_loop_2_D;

endmodule
