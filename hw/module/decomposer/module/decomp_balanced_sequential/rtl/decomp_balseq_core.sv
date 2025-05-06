// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the decomposition of a coefficient into L levels.
// The levels are output 1 per cycle.
// The algorithm used here corresponds to "Balanced decomposition with unfixed sign and rounding bit"
// ==============================================================================================

module decomp_balseq_core #(
  parameter int B_W    = 13,
  parameter int L      = 3,
  parameter int SIDE_W = 0, // Set to 0 if unused
  parameter bit OUT_2SCOMPL = 1'b1 // (1) Output in 2s complement format
                                   // (0) Output sign + absolute value
) (
    input  logic                  clk,        // clock
    input  logic                  s_rst_n,    // synchronous reset

    input  logic [L-1:0][B_W-1:0] in_data,
    input  logic                  in_sign, // sign of the closest rep
    input  logic                  in_avail,
    input  logic [SIDE_W-1:0]     in_side,

    output logic [B_W:0]          out_data, // signed
    output logic                  out_avail,
    output logic                  out_sol,
    output logic                  out_eol,
    output logic [SIDE_W-1:0]     out_side,

    output logic                  error
);

  // ============================================================================================== --
  // Localparam
  // ============================================================================================== --
  localparam int L_W = $clog2(L) == 0 ? 1 : $clog2(L);

  // ============================================================================================== --
  // Input register
  // ============================================================================================== --
  logic [L-1:0][B_W-1:0] s0_data;
  logic                  s0_sign;
  logic [SIDE_W-1:0]     s0_side;
  logic [L-1:0][B_W-1:0] s0_dataD;
  logic                  s0_signD;
  logic [SIDE_W-1:0]     s0_sideD;
  logic                  s0_run;

  logic [L:0][B_W-1:0] s0_data_ext;
  assign s0_data_ext = {{B_W{s0_sign}},s0_data}; // extend with the sign

  always_comb
    for (int i=0; i<L; i=i+1)
      s0_dataD[i] = in_avail ? in_data[i] :
                    s0_run   ? s0_data_ext[i+1] : s0_data[i];

  assign s0_sideD = in_avail ? in_side : s0_side;
  assign s0_signD = in_avail ? in_sign : s0_sign;

  always_ff @(posedge clk) begin
    s0_data <= s0_dataD;
    s0_sign <= s0_signD;
    s0_side <= s0_sideD;
  end

  // ============================================================================================== --
  // s0 : control
  // ============================================================================================== --
  logic           s0_runD;
  logic [L_W-1:0] s0_lvl_id;
  logic [L_W-1:0] s0_lvl_idD;
  logic           s0_last_lvl;
  logic           s0_first_lvl;

  assign s0_first_lvl = s0_lvl_id == '0;
  assign s0_last_lvl  = s0_lvl_id == L-1;
  assign s0_runD      = in_avail    ? 1'b1:
                        s0_last_lvl ? 1'b0 : s0_run;
  assign s0_lvl_idD   = in_avail ? '0 :
                        s0_run   ? s0_lvl_id + 1 : s0_lvl_id;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      s0_run    <= 1'b0;
      s0_lvl_id <= '0;
    end
    else begin
      s0_run    <= s0_runD;
      s0_lvl_id <= s0_lvl_idD;
    end

  //---------------------------
  // Error
  //---------------------------
  logic s0_error;

  // Input comes too early. The module is still processing the previous data.
  assign s0_error = in_avail & s0_run & ~s0_last_lvl;

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
  // s0: Apply the decomposition
  // ============================================================================================== --
  logic [L:0][B_W-1:0] s0_subw_a;
  logic [B_W:0] s0_subw_w_c;
  logic [B_W:0] s0_subw_result;
  logic         s0_propagate_carry;
  logic         s0_ge_half;
  logic         s0_overflow;
  logic         s0_gt_half;

  logic         s0_carry;
  logic         s0_carry_tmp;
  logic         s0_carry_tmpD;

  assign s0_subw_a = s0_data_ext;

  assign s0_carry    = s0_first_lvl ? 1'b0 : s0_carry_tmp;
  assign s0_subw_w_c = {1'b0,s0_subw_a[0]} + s0_carry;

  always_ff @(posedge clk)
    s0_carry_tmp <= s0_carry_tmpD;

  /*****************************************
   * To save some timing the following code is not used, since the critical
   * path is the adder carry path.
   * For more clarity in the algorithm comprehension, it is kept here:
   ****************************************
  assign s0_gt_half  = s0_subw_w_c[B_W-1] & |s0_subw_w_c[B_W-2:0];
  assign s0_ge_half  = s0_subw_w_c[B_W-1];
  assign s0_overflow = s0_subw_w_c[B_W];
  *****************************************/

  generate
    if (B_W == 1) begin : gen_bw_eq_1
      assign s0_gt_half =
          s0_subw_a[0][B_W-1] & s0_carry;
      assign s0_ge_half =
          s0_subw_a[0][B_W-1] | s0_carry;
    end
    else begin : gen_bw_gt_1
      assign s0_gt_half =
          s0_subw_a[0][B_W-1] & |{s0_subw_a[0][B_W-2:0], s0_carry};
      assign s0_ge_half =
          s0_subw_a[0][B_W-1] | &{s0_subw_a[0][B_W-2:0], s0_carry};
    end
  endgenerate

  assign s0_overflow = &{s0_subw_a[0][B_W-1:0], s0_carry};

  // Propagate a carry if current subw is already a negative or if the subw is > b/2.
  // In the case = b/2, propagate only if a propagation analysis is necessary on
  // the next subw.
  assign s0_propagate_carry = s0_overflow | s0_gt_half |
      (s0_ge_half & s0_subw_a[1][B_W-1]);

  assign s0_carry_tmpD = s0_propagate_carry;

  // s0_propagate_carry=1 : inverse the sign
  // s0_propagate_carry=0 : set the sign to 0
  logic [B_W:0] s0_subw_result_tmp;
  assign s0_subw_result_tmp = s0_propagate_carry ?
      {~(s0_subw_w_c[B_W]), s0_subw_w_c[B_W-1:0]} : {1'b0, s0_subw_w_c[B_W-1:0]};

  generate
    if (OUT_2SCOMPL) begin
      assign s0_subw_result = s0_subw_result_tmp;
    end
    else begin
      assign s0_subw_result[B_W]     = s0_subw_result_tmp[B_W];
      assign s0_subw_result[B_W-1:0] = s0_subw_result_tmp[B_W] ? ~s0_subw_w_c[B_W-1:0]+1: s0_subw_w_c[B_W-1:0];
    end
  endgenerate

  // ============================================================================================== --
  // Output register
  // ============================================================================================== --
  logic [B_W:0]      s1_subw_result;
  logic              s1_first_lvl;
  logic              s1_last_lvl;
  logic [SIDE_W-1:0] s1_side;
  logic              s1_avail;

  always_ff @(posedge clk) begin
    s1_subw_result <= s0_subw_result;
    s1_first_lvl   <= s0_first_lvl;
    s1_last_lvl    <= s0_last_lvl;
    s1_side        <= s0_side;
  end

  always_ff @(posedge clk)
    if (!s_rst_n) s1_avail <= 1'b0;
    else          s1_avail <= s0_run;

  assign out_data  = s1_subw_result;
  assign out_avail = s1_avail;
  assign out_sol   = s1_first_lvl;
  assign out_eol   = s1_last_lvl;
  assign out_side  = s1_side;

endmodule

