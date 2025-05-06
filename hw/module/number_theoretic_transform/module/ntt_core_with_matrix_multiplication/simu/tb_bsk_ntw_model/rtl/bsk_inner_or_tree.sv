// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
//
// ==============================================================================================

module bsk_inner_or_tree
  import param_tfhe_pkg::*;
  import bsk_ntw_common_param_pkg::*;
  #(
    // Number of servers
    parameter int SRV_NB        = 2,
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

    input  [BSK_DIST_COEF_NB-1:0][       OP_W-1:0]           bsk_srv_bdc_bsk_2_in,
    input  [BSK_DIST_COEF_NB-1:0]                            bsk_srv_bdc_avail_2_in,
    input  [ BSK_UNIT_W-1:0]                                 bsk_srv_bdc_unit_2_in,
    input  [BSK_GROUP_W-1:0]                                 bsk_srv_bdc_group_2_in,
    input  [    LWE_K_W-1:0]                                 bsk_srv_bdc_br_loop_2_in,

    output [BSK_DIST_COEF_NB-1:0][       OP_W-1:0]           bsk_srv_bdc_bsk_2_out,
    output [BSK_DIST_COEF_NB-1:0]                            bsk_srv_bdc_avail_2_out,
    output [ BSK_UNIT_W-1:0]                                 bsk_srv_bdc_unit_2_out,
    output [BSK_GROUP_W-1:0]                                 bsk_srv_bdc_group_2_out,
    output [    LWE_K_W-1:0]                                 bsk_srv_bdc_br_loop_2_out,

    input  [BSK_DIST_COEF_NB-1:0][       OP_W-1:0]           bsk_srv_bdc_bsk_3_in,
    input  [BSK_DIST_COEF_NB-1:0]                            bsk_srv_bdc_avail_3_in,
    input  [ BSK_UNIT_W-1:0]                                 bsk_srv_bdc_unit_3_in,
    input  [BSK_GROUP_W-1:0]                                 bsk_srv_bdc_group_3_in,
    input  [    LWE_K_W-1:0]                                 bsk_srv_bdc_br_loop_3_in,

    output [BSK_DIST_COEF_NB-1:0][       OP_W-1:0]           bsk_srv_bdc_bsk_3_out,
    output [BSK_DIST_COEF_NB-1:0]                            bsk_srv_bdc_avail_3_out,
    output [ BSK_UNIT_W-1:0]                                 bsk_srv_bdc_unit_3_out,
    output [BSK_GROUP_W-1:0]                                 bsk_srv_bdc_group_3_out,
    output [    LWE_K_W-1:0]                                 bsk_srv_bdc_br_loop_3_out,

    output [BSK_DIST_COEF_NB-1:0][       OP_W-1:0]           bsk_srv_bdc_bsk_4_out,
    output [BSK_DIST_COEF_NB-1:0]                            bsk_srv_bdc_avail_4_out,
    output [ BSK_UNIT_W-1:0]                                 bsk_srv_bdc_unit_4_out,
    output [BSK_GROUP_W-1:0]                                 bsk_srv_bdc_group_4_out,
    output [    LWE_K_W-1:0]                                 bsk_srv_bdc_br_loop_4_out
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

  logic [BSK_DIST_COEF_NB-1:0][       OP_W-1:0]            bsk_srv_bdc_bsk_3;
  logic [BSK_DIST_COEF_NB-1:0]                             bsk_srv_bdc_avail_3;
  logic [ BSK_UNIT_W-1:0]                                  bsk_srv_bdc_unit_3;
  logic [BSK_GROUP_W-1:0]                                  bsk_srv_bdc_group_3;
  logic [    LWE_K_W-1:0]                                  bsk_srv_bdc_br_loop_3;

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

  always_ff @(posedge clk) begin
    bsk_srv_bdc_bsk_3     <= bsk_srv_bdc_bsk_3_in;
    bsk_srv_bdc_avail_3   <= bsk_srv_bdc_avail_3_in;
    bsk_srv_bdc_unit_3    <= bsk_srv_bdc_unit_3_in;
    bsk_srv_bdc_group_3   <= bsk_srv_bdc_group_3_in;
    bsk_srv_bdc_br_loop_3 <= bsk_srv_bdc_br_loop_3_in;
  end

  // Merging signals for clients - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  logic [BSK_DIST_COEF_NB-1:0][OP_W-1:0] slr0_or_1_bsk;
  logic [BSK_DIST_COEF_NB-1:0]           slr0_or_1_avail;
  logic [ BSK_UNIT_W-1:0]                slr0_or_1_unit;
  logic [BSK_GROUP_W-1:0]                slr0_or_1_group;
  logic [    LWE_K_W-1:0]                slr0_or_1_br_loop;

  logic [BSK_DIST_COEF_NB-1:0][OP_W-1:0] slr0_or_2_bsk;
  logic [BSK_DIST_COEF_NB-1:0]           slr0_or_2_avail;
  logic [ BSK_UNIT_W-1:0]                slr0_or_2_unit;
  logic [BSK_GROUP_W-1:0]                slr0_or_2_group;
  logic [    LWE_K_W-1:0]                slr0_or_2_br_loop;

  logic [BSK_DIST_COEF_NB-1:0][OP_W-1:0] slr0_or_3_bsk;
  logic [BSK_DIST_COEF_NB-1:0]           slr0_or_3_avail;
  logic [ BSK_UNIT_W-1:0]                slr0_or_3_unit;
  logic [BSK_GROUP_W-1:0]                slr0_or_3_group;
  logic [    LWE_K_W-1:0]                slr0_or_3_br_loop;

  always_comb begin : first_or
    slr0_or_1_bsk     = bsk_srv_bdc_bsk[0]      | bsk_srv_bdc_bsk[1];
    slr0_or_1_avail   = bsk_srv_bdc_avail[0]    | bsk_srv_bdc_avail[1];
    slr0_or_1_unit    = bsk_srv_bdc_unit[0]     | bsk_srv_bdc_unit[1];
    slr0_or_1_group   = bsk_srv_bdc_group[0]    | bsk_srv_bdc_group[1];
    slr0_or_1_br_loop = bsk_srv_bdc_br_loop[0]  | bsk_srv_bdc_br_loop[1];
  end

  always_comb begin : second_or
    slr0_or_2_bsk     = slr0_or_1_bsk     | bsk_srv_bdc_bsk_2;
    slr0_or_2_avail   = slr0_or_1_avail   | bsk_srv_bdc_avail_2;
    slr0_or_2_unit    = slr0_or_1_unit    | bsk_srv_bdc_unit_2;
    slr0_or_2_group   = slr0_or_1_group   | bsk_srv_bdc_group_2;
    slr0_or_2_br_loop = slr0_or_1_br_loop | bsk_srv_bdc_br_loop_2;
  end

  always_comb begin : third_or
    slr0_or_3_bsk     = slr0_or_1_bsk     | bsk_srv_bdc_bsk_3;
    slr0_or_3_avail   = slr0_or_1_avail   | bsk_srv_bdc_avail_3;
    slr0_or_3_unit    = slr0_or_1_unit    | bsk_srv_bdc_unit_3;
    slr0_or_3_group   = slr0_or_1_group   | bsk_srv_bdc_group_3;
    slr0_or_3_br_loop = slr0_or_1_br_loop | bsk_srv_bdc_br_loop_3;
  end


  // Output Register barrier -----------------------------------------------------------------------

  logic [BSK_DIST_COEF_NB-1:0][       OP_W-1:0]       bsk_srv_bdc_bsk_2_D;
  logic [BSK_DIST_COEF_NB-1:0]                        bsk_srv_bdc_avail_2_D;
  logic [ BSK_UNIT_W-1:0]                             bsk_srv_bdc_unit_2_D;
  logic [BSK_GROUP_W-1:0]                             bsk_srv_bdc_group_2_D;
  logic [    LWE_K_W-1:0]                             bsk_srv_bdc_br_loop_2_D;

  logic [BSK_DIST_COEF_NB-1:0][       OP_W-1:0]       bsk_srv_bdc_bsk_3_D;
  logic [BSK_DIST_COEF_NB-1:0]                        bsk_srv_bdc_avail_3_D;
  logic [ BSK_UNIT_W-1:0]                             bsk_srv_bdc_unit_3_D;
  logic [BSK_GROUP_W-1:0]                             bsk_srv_bdc_group_3_D;
  logic [    LWE_K_W-1:0]                             bsk_srv_bdc_br_loop_3_D;

  logic [BSK_DIST_COEF_NB-1:0][       OP_W-1:0]       bsk_srv_bdc_bsk_4_D;
  logic [BSK_DIST_COEF_NB-1:0]                        bsk_srv_bdc_avail_4_D;
  logic [ BSK_UNIT_W-1:0]                             bsk_srv_bdc_unit_4_D;
  logic [BSK_GROUP_W-1:0]                             bsk_srv_bdc_group_4_D;
  logic [    LWE_K_W-1:0]                             bsk_srv_bdc_br_loop_4_D;

  // to side slr
  always_ff @(posedge clk) begin
    bsk_srv_bdc_bsk_2_D      <= slr0_or_2_bsk;
    bsk_srv_bdc_avail_2_D    <= slr0_or_2_avail;
    bsk_srv_bdc_unit_2_D     <= slr0_or_2_unit;
    bsk_srv_bdc_group_2_D    <= slr0_or_2_group;
    bsk_srv_bdc_br_loop_2_D  <= slr0_or_2_br_loop;
  end

  always_ff @(posedge clk) begin
    bsk_srv_bdc_bsk_3_D     <= slr0_or_3_bsk;
    bsk_srv_bdc_avail_3_D   <= slr0_or_3_avail;
    bsk_srv_bdc_unit_3_D    <= slr0_or_3_unit;
    bsk_srv_bdc_group_3_D   <= slr0_or_3_group;
    bsk_srv_bdc_br_loop_3_D <= slr0_or_3_br_loop;
  end

  // to clients
  always_ff @(posedge clk) begin : fourth_or
    bsk_srv_bdc_bsk_4_D     = bsk_srv_bdc_bsk_2_D     | bsk_srv_bdc_bsk_3_D;
    bsk_srv_bdc_avail_4_D   = bsk_srv_bdc_avail_2_D   | bsk_srv_bdc_avail_3_D;
    bsk_srv_bdc_unit_4_D    = bsk_srv_bdc_unit_2_D    | bsk_srv_bdc_unit_3_D;
    bsk_srv_bdc_group_4_D   = bsk_srv_bdc_group_2_D   | bsk_srv_bdc_group_3_D;
    bsk_srv_bdc_br_loop_4_D = bsk_srv_bdc_br_loop_2_D | bsk_srv_bdc_br_loop_3_D;
  end

  // Output assignations ---------------------------------------------------------------------------
  assign  bsk_srv_bdc_bsk_2_out     = bsk_srv_bdc_bsk_2_D;
  assign  bsk_srv_bdc_avail_2_out   = bsk_srv_bdc_avail_2_D;
  assign  bsk_srv_bdc_unit_2_out    = bsk_srv_bdc_unit_2_D;
  assign  bsk_srv_bdc_group_2_out   = bsk_srv_bdc_group_2_D;
  assign  bsk_srv_bdc_br_loop_2_out = bsk_srv_bdc_br_loop_2_D;

  assign bsk_srv_bdc_bsk_3_out      = bsk_srv_bdc_bsk_3_D;
  assign bsk_srv_bdc_avail_3_out    = bsk_srv_bdc_avail_3_D;
  assign bsk_srv_bdc_unit_3_out     = bsk_srv_bdc_unit_3_D;
  assign bsk_srv_bdc_group_3_out    = bsk_srv_bdc_group_3_D;
  assign bsk_srv_bdc_br_loop_3_out  = bsk_srv_bdc_br_loop_3_D;
  
  assign  bsk_srv_bdc_bsk_4_out     = bsk_srv_bdc_bsk_4_D;
  assign  bsk_srv_bdc_avail_4_out   = bsk_srv_bdc_avail_4_D;
  assign  bsk_srv_bdc_unit_4_out    = bsk_srv_bdc_unit_4_D;
  assign  bsk_srv_bdc_group_4_out   = bsk_srv_bdc_group_4_D;
  assign  bsk_srv_bdc_br_loop_4_out = bsk_srv_bdc_br_loop_4_D;

endmodule
