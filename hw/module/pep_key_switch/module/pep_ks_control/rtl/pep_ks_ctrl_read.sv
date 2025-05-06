// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the reading in BLRAM.
// According to its position, during the last reading of the current iteration,
// the data read is replaced with 0.
// ==============================================================================================

module pep_ks_ctrl_read
  import param_tfhe_pkg::*;
  import pep_ks_common_param_pkg::*;
#(
  parameter  int ID               = 0,
  parameter  int BLWE_RAM_DEPTH   = (BLWE_K+LBY-1)/LBY * 8 * 4,
  localparam int BLWE_RAM_ADD_W   = $clog2(BLWE_RAM_DEPTH),
  parameter  int SIDE_W            = 1
)
(
  input  logic                      clk,        // clock
  input  logic                      s_rst_n,    // synchronous reset

  output logic                      ctrl_blram_rd_en,
  output logic [BLWE_RAM_ADD_W-1:0] ctrl_blram_rd_add,
  input  logic [KS_DECOMP_W-1:0]    blram_ctrl_rd_data,
  input  logic                      blram_ctrl_rd_data_avail,

  input  logic                      prev_avail,
  input  logic [BLWE_RAM_ADD_W-1:0] prev_add,
  input  logic                      prev_data_avail,
  input  logic                      prev_data_last_y,
  input  logic [SIDE_W-1:0]         prev_data_side,

  output logic                      next_avail,
  output logic [BLWE_RAM_ADD_W-1:0] next_add,
  output logic                      next_data_avail,
  output logic                      next_data_last_y,
  output logic [SIDE_W-1:0]         next_data_side,

  output logic                      ctrl_mult_avail,
  output logic [LBZ-1:0][KS_B_W-1:0]ctrl_mult_data,
  output logic [LBZ-1:0]            ctrl_mult_sign,
  output logic                      ctrl_mult_eol,
  output logic [SIDE_W-1:0]         ctrl_mult_side
);

//=================================================================================================
// localparam
//=================================================================================================
  localparam int ID_OFS_TMP = (BLWE_K % LBY);
  localparam int ID_OFS     = ID_OFS_TMP == 0 ? LBY : ID_OFS_TMP;
  localparam bit DO_LAST_0  = ID >= ID_OFS;

//=================================================================================================
// pipe to next read node
//=================================================================================================
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      next_avail      <= 1'b0;
      next_data_avail <= 1'b0;
    end
    else begin
      next_avail      <= prev_avail;
      next_data_avail <= prev_data_avail;
    end

  always_ff @(posedge clk) begin
    next_add         <= prev_add;
    next_data_side   <= prev_data_side;
    next_data_last_y <= prev_data_last_y;
  end

//=================================================================================================
// Input pipe
//=================================================================================================
  logic                       s0_avail;
  logic [BLWE_RAM_ADD_W-1:0]  s0_add;
  logic                       r0_avail;
  logic [SIDE_W-1:0]          r0_side;
  logic                       r0_last_y;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      s0_avail <= 1'b0;
      r0_avail <= 1'b0;
    end
    else begin
      s0_avail <= prev_avail;
      r0_avail <= prev_data_avail;
    end

  always_ff @(posedge clk) begin
    s0_add    <= prev_add;
    r0_side   <= prev_data_side;
    r0_last_y <= prev_data_last_y;
  end

//=================================================================================================
// s0 : read
//=================================================================================================
  assign ctrl_blram_rd_en  = s0_avail;
  assign ctrl_blram_rd_add = s0_add;

//=================================================================================================
// blram_ctrl pipe
//=================================================================================================
  logic [KS_DECOMP_W-1:0] r0_data;
  logic                   r0_data_avail;

  always_ff @(posedge clk)
    if (!s_rst_n) r0_data_avail <= '0;
    else          r0_data_avail <= blram_ctrl_rd_data_avail;

  always_ff @(posedge clk)
    r0_data <= blram_ctrl_rd_data;

//=================================================================================================
// r0
//=================================================================================================
  logic [KS_DECOMP_W-1:0] r0_out_data;

  assign r0_out_data = (r0_last_y && DO_LAST_0) ? '0 : r0_data;

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      assert(r0_avail == r0_data_avail)
      else begin
        $fatal(1,"%t > ERROR: Incoherence : read data and shift register are not aligned.",$time);
      end
    end
// pragma translate_on

//=================================================================================================
// Output shift register
//=================================================================================================
  logic                                   r1_avail;
  logic [KS_LG_NB-1:0][LBZ-1:0][KS_B_W:0] r1_out_data;
  logic [KS_LG_NB-1:0][LBZ-1:0][KS_B_W:0] r1_out_dataD;
  logic [KS_LG_NB-1:0][LBZ-1:0][KS_B_W:0] r1_out_dataD_tmp;
  logic [SIDE_W-1:0]                      r1_side;
  logic [SIDE_W-1:0]                      r1_sideD;
  logic [KS_LG_NB-1:0][LBZ-1:0][KS_B_W:0] r0_data_ext;

  // counter
  logic [KS_LG_W-1:0] r1_lvl;
  logic [KS_LG_W-1:0] r1_lvlD;
  logic               r1_last_lvl;

  assign r1_last_lvl = r1_lvl == KS_LG_NB-1;
  assign r1_lvlD     = (r1_avail || (r1_lvl > 0)) ? r1_last_lvl ? '0 : r1_lvl + 1 : r1_lvl;

  generate
    if (KS_LG_NB > 1) begin
      assign r1_out_dataD_tmp = {r1_out_data[KS_LG_NB-1],r1_out_data[KS_LG_NB-1:1]};
    end
    else begin
      assign r1_out_dataD_tmp = r1_out_data;
    end
  endgenerate

  assign r0_data_ext  = r0_out_data; // MSB are extended with 0s if needed
  assign r1_out_dataD = r0_avail ? r0_data_ext : r1_out_dataD_tmp;
  assign r1_sideD     = r0_avail ? r0_side     : r1_side;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      r1_avail <= 1'b0;
      r1_lvl   <= '0;
    end
    else begin
      r1_avail <= r0_avail;
      r1_lvl   <= r1_lvlD;
    end

  always_ff @(posedge clk) begin
    r1_out_data <= r1_out_dataD;
    r1_side     <= r1_sideD;
  end

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
    end
    else begin
      assert(!r1_avail || (r1_last_lvl || (r1_lvl==0)))
      else begin
        $fatal(1,"%t > ERROR: Output shift register is still full when data arrives.", $time);
      end
    end
// pragma translate_on

  // output
  logic                       ctrl_mult_availD;
  logic [LBZ-1:0][KS_B_W-1:0] ctrl_mult_dataD;
  logic [LBZ-1:0]             ctrl_mult_signD;
  logic                       ctrl_mult_eolD;
  logic [SIDE_W-1:0]          ctrl_mult_sideD;

  assign ctrl_mult_availD = r1_avail | (r1_lvl > 0);
  assign ctrl_mult_sideD  = r1_side;
  assign ctrl_mult_eolD   = r1_last_lvl;

  always_comb
    for (int z=0; z<LBZ; z=z+1) begin
      ctrl_mult_dataD[z]  = r1_out_data[0][z][KS_B_W-1:0];
      ctrl_mult_signD[z]  = r1_out_data[0][z][KS_B_W];
    end

  always_ff @(posedge clk)
    if (!s_rst_n) ctrl_mult_avail <= '0;
    else          ctrl_mult_avail <= ctrl_mult_availD;

  always_ff @(posedge clk) begin
    ctrl_mult_data <= ctrl_mult_dataD;
    ctrl_mult_sign <= ctrl_mult_signD;
    ctrl_mult_side <= ctrl_mult_sideD;
    ctrl_mult_eol  <= ctrl_mult_eolD;
  end
endmodule
