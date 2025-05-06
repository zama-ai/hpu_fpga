// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the decomposition of a coefficient into L levels.
// The levels are output 1 per cycle.
// ==============================================================================================

module decomp_sequential #(
  parameter int OP_W   = 64,
  parameter int B_W    = 13,
  parameter int L      = 3,
  parameter int SIDE_W = 0, // Set to 0 if unused
  parameter bit OUT_2SCOMPL = 1'b1 // (1) Output in 2s complement format
                                   // (0) Output sign + absolute value
)
(
    input  logic              clk,        // clock
    input  logic              s_rst_n,    // synchronous reset

    input  logic [OP_W-1:0]   in_data,
    input  logic              in_avail,
    input  logic [SIDE_W-1:0] in_side,

    output logic [B_W:0]      out_data, // signed
    output logic              out_avail,
    output logic              out_sol,
    output logic              out_eol,
    output logic [SIDE_W-1:0] out_side,

    output logic              error
);


  // ============================================================================================== --
  // Localparam
  // ============================================================================================== --
  localparam int CLOSEST_REP_W   = L * B_W;
  localparam int CLOSEST_REP_OFS = OP_W - CLOSEST_REP_W;

  localparam int L_W = $clog2(L) == 0 ? 1 : $clog2(L);

  // ============================================================================================== --
  // Input register
  // ============================================================================================== --
  logic [OP_W-1:0]   s0_data;
  logic [SIDE_W-1:0] s0_side;
  logic              s0_avail;
  logic [OP_W-1:0]   s0_dataD;
  logic [SIDE_W-1:0] s0_sideD;

  assign s0_dataD = in_avail ? in_data : s0_data;
  assign s0_sideD = in_avail ? in_side : s0_side;

  always_ff @(posedge clk) begin
    s0_data <= s0_dataD;
    s0_side <= s0_sideD;
  end

  always_ff @(posedge clk)
    if (!s_rst_n) s0_avail <= 1'b0;
    else          s0_avail <= in_avail;

  // ============================================================================================== --
  // s0 : control
  // ============================================================================================== --
  logic           s0_run;
  logic           s0_run_tmp;
  logic           s0_run_tmpD;
  logic [L_W-1:0] s0_lvl_id;
  logic [L_W-1:0] s0_lvl_idD;
  logic           s0_last_lvl;
  logic           s0_first_lvl;

  assign s0_first_lvl = s0_lvl_id == '0;
  assign s0_last_lvl  = s0_lvl_id == L-1;
  assign s0_run_tmpD  = s0_last_lvl ? 1'b0 :
                        s0_avail    ? 1'b1 : s0_run_tmp;
  assign s0_lvl_idD   = s0_run ? s0_last_lvl ? '0 : s0_lvl_id + 1 : s0_lvl_id;

  assign s0_run = s0_avail | s0_run_tmp;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      s0_run_tmp <= 1'b0;
      s0_lvl_id  <= '0;
    end
    else begin
      s0_run_tmp <= s0_run_tmpD;
      s0_lvl_id  <= s0_lvl_idD;
    end

  //---------------------------
  // Error
  //---------------------------
  logic s0_error;

  // Input comes too early. The module is still processing the previous data.
  assign s0_error = s0_run_tmp & s0_avail;

  always_ff @(posedge clk)
    if (!s_rst_n) error <= 1'b0;
    else          error <= s0_error;

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
    end
    else begin
      assert(!s0_error)
      else begin
        $fatal(1,"%t > ERROR: Input received, while the module is still busy!", $time);
      end
    end
// pragma translate_on

  // ============================================================================================== --
  // s0: Compute the closest representable value
  // ============================================================================================== --
  // Keep the CLOSEST_REP_W MSB-bits of the input.
  // Add 1<<CLOSEST_REP_W if the LSB part is greater than a half, i.e. bit [CLOSEST_REP_OFS-1] not
  // null.
  logic [OP_W-1:0]     s0_closest_rep;
  logic [L:0][B_W-1:0] s1_subw_a;
  logic [L:0][B_W-1:0] s1_subw_aD;

  assign s0_closest_rep[CLOSEST_REP_OFS-1:0]    = {CLOSEST_REP_OFS{1'b0}};
  assign s0_closest_rep[OP_W-1:CLOSEST_REP_OFS] = s0_data[OP_W-1:CLOSEST_REP_OFS] + s0_data[CLOSEST_REP_OFS-1];
  assign s1_subw_aD                             = s0_first_lvl ? {{B_W{1'b0}},s0_closest_rep[OP_W-1:CLOSEST_REP_OFS]} :
                                                  {s1_subw_a[L],s1_subw_a[L:1]}; // shift

  logic              s1_avail;
  logic [SIDE_W-1:0] s1_side;
  logic              s1_first_lvl;
  logic              s1_last_lvl;

  always_ff @(posedge clk) begin
    s1_subw_a    <= s1_subw_aD;
    s1_side      <= s0_side;
    s1_first_lvl <= s0_first_lvl;
    s1_last_lvl  <= s0_last_lvl;
  end

  always_ff @(posedge clk)
    if (!s_rst_n) s1_avail <= 1'b0;
    else          s1_avail <= s0_run;

  // ============================================================================================== --
  // s1: Apply the decomposition
  // ============================================================================================== --
  logic [B_W:0] s1_subw_w_c;
  logic [B_W:0] s1_subw_result;
  logic         s1_propagate_carry;
  logic         s1_ge_half;
  logic         s1_overflow;
  logic         s1_gt_half;

  logic         s1_carry;
  logic         s1_carry_tmp;
  logic         s1_carry_tmpD;

  assign s1_carry    = s1_first_lvl ? 1'b0 : s1_carry_tmp;
  assign s1_subw_w_c = {1'b0,s1_subw_a[0]} + s1_carry;

  always_ff @(posedge clk)
    s1_carry_tmp <= s1_carry_tmpD;

  /*****************************************
   * To save some timing the following code is not used, since the critical
   * path is the adder carry path.
   * For more clarity in the algorithm comprehension, it is kept here:
   ****************************************
  assign s1_gt_half  = s1_subw_w_c[B_W-1] & |s1_subw_w_c[B_W-2:0];
  assign s1_ge_half  = s1_subw_w_c[B_W-1];
  assign s1_overflow = s1_subw_w_c[B_W];
  *****************************************/

  assign s1_gt_half =
      s1_subw_a[0][B_W-1] & |{s1_subw_a[0][B_W-2:0], s1_carry};
  assign s1_ge_half =
      s1_subw_a[0][B_W-1] | &{s1_subw_a[0][B_W-2:0], s1_carry};
  assign s1_overflow = &{s1_subw_a[0][B_W-1:0], s1_carry};

  // Propagate a carry if current subw is already a negative or if the subw is > b/2.
  // In the case = b/2, propagate only if a propagation analysis is necessary on
  // the next subw.
  assign s1_propagate_carry = s1_overflow | s1_gt_half |
      (s1_ge_half & s1_subw_a[1][B_W-1]);

  assign s1_carry_tmpD = s1_propagate_carry;

  // s1_propagate_carry=1 : inverse the sign
  // s1_propagate_carry=0 : set the sign to 0
  logic [B_W:0] s1_subw_result_tmp;
  assign s1_subw_result_tmp = s1_propagate_carry ?
      {~(s1_subw_w_c[B_W]), s1_subw_w_c[B_W-1:0]} : {1'b0, s1_subw_w_c[B_W-1:0]};

  generate
    if (OUT_2SCOMPL) begin
      assign s1_subw_result = s1_subw_result_tmp;
    end
    else begin
      assign s1_subw_result[B_W]     = s1_subw_result_tmp[B_W];
      assign s1_subw_result[B_W-1:0] = s1_subw_result_tmp[B_W] ? ~s1_subw_w_c[B_W-1:0]+1: s1_subw_w_c[B_W-1:0];
    end
  endgenerate

  // ============================================================================================== --
  // Output register
  // ============================================================================================== --
  logic [B_W:0]      s2_subw_result;
  logic              s2_first_lvl;
  logic              s2_last_lvl;
  logic [SIDE_W-1:0] s2_side;
  logic              s2_avail;

  always_ff @(posedge clk) begin
    s2_subw_result <= s1_subw_result;
    s2_first_lvl   <= s1_first_lvl;
    s2_last_lvl    <= s1_last_lvl;
    s2_side        <= s1_side;
  end

  always_ff @(posedge clk)
    if (!s_rst_n) s2_avail <= 1'b0;
    else          s2_avail <= s1_avail;

  assign out_data  = s2_subw_result;
  assign out_avail = s2_avail;
  assign out_sol   = s2_first_lvl;
  assign out_eol   = s2_last_lvl;
  assign out_side  = s2_side;

endmodule
