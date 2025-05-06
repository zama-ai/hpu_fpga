// ============================================================================================== --
// Description  : Performs a full parametric decomposition
// ---------------------------------------------------------------------------------------------- --
//
// Decomposes a OP_W-bit input into L number (called number of levels) of (B_W+1)-bit
// signed subwords.
// The subwords are in the range [-2**B_W, 2**B_W] and are stored in
// the "out_data" output array. out_data[L-1] holds the MSBs of the decomposition,
// out_data[0] holds the LSBs.
//
// /!\ This version is the old version containing the bug: no rounding after the closest rep.
//
// ============================================================================================== --

module decomp_parallel #(
  parameter int OP_W        = 64,  // Modulo width
  parameter int L           = 10,   // Number of levels
  parameter int B_W         = 2,    // Decomposition base width
  parameter int SIDE_W      = 0,   // Set to 0 if unused
  parameter bit OUT_2SCOMPL = 1'b1 // (1) Output in 2s complement format
                                   // (0) Output sign + absolute value
) (
  input  logic                clk,
  input  logic                s_rst_n,
  input  logic [OP_W-1:0]     in_data,
  input  logic                in_avail,
  input  logic [SIDE_W-1:0]   in_side,
  output logic [L-1:0][B_W:0] out_data,
  output logic                out_avail,
  output logic [SIDE_W-1:0]   out_side
);

  // ============================================================================================== --
  // Localparam
  // ============================================================================================== --
  localparam int CLOSEST_REP_W   = L * B_W;
  localparam int CLOSEST_REP_OFS = OP_W - CLOSEST_REP_W;

  // ============================================================================================== --
  // Input register
  // ============================================================================================== --
  logic [OP_W-1:0]   s0_data;
  logic              s0_avail;
  logic [SIDE_W-1:0] s0_side;

  always_ff @(posedge clk) begin
    s0_data <= in_data;
    s0_side <= in_side;
  end

  always_ff @(posedge clk)
    if (!s_rst_n) s0_avail <= 1'b0;
    else          s0_avail <= in_avail;


  // ============================================================================================== --
  // s0: Compute the closest representable value
  // ============================================================================================== --
  // Keep the CLOSEST_REP_W MSB-bits of the input.
  // Add 1<<CLOSEST_REP_W if the LSB part is greater than a half, i.e. bit [CLOSEST_REP_OFS-1] not
  // null.
  logic [OP_W-1:0] s0_closest_rep;
  logic            s0_closest_rep_sign;

  generate
    if (CLOSEST_REP_W >= OP_W) begin : gen_entire
      assign s0_closest_rep = s0_data;
      assign s0_closest_rep_sign = 1'b0;
    end
    else begin : gen_no_entire
      assign s0_closest_rep[CLOSEST_REP_OFS-1:0]    = {CLOSEST_REP_OFS{1'b0}};
      assign s0_closest_rep[OP_W-1:CLOSEST_REP_OFS] = s0_data[OP_W-1:CLOSEST_REP_OFS] + s0_data[CLOSEST_REP_OFS-1];
      // Is negative if: closest_rep > base**level/2 or (closest_rep == base**level/2 and fraction == 1)
      //assign s0_closest_rep_sign = (s0_data[OP_W-1] & ((s0_data[CLOSEST_REP_OFS+:CLOSEST_REP_W-1] != '0) | s0_data[CLOSEST_REP_OFS-1]))
      //                            |(~s0_data[OP_W-1] & (s0_data[CLOSEST_REP_OFS+:CLOSEST_REP_W-1] == '1) & s0_data[CLOSEST_REP_OFS-1]);
      assign s0_closest_rep_sign = 1'b0; // BUG: To stay compatible with previous bugged version.
    end
  endgenerate

  logic [OP_W-1:0]   s1_closest_rep;
  logic              s1_closest_rep_sign;
  logic [SIDE_W-1:0] s1_side;
  logic              s1_avail;

  always_ff @(posedge clk) begin
    s1_closest_rep <= s0_closest_rep;
    s1_closest_rep_sign <= s0_closest_rep_sign;
    s1_side        <= s0_side;
  end

  always_ff @(posedge clk)
    if (!s_rst_n) s1_avail <= 1'b0;
    else          s1_avail <= s0_avail;

  // ============================================================================================== --
  // s1: Apply the decomposition
  // ============================================================================================== --
  logic [L:0][B_W:0]   s1_subw_in_a;
  logic [L-1:0][B_W:0] s1_subw_out_a;
  logic [L:0]          s1_carry;

  // split into subws
  always_comb begin
    for (int i = 0; i < L; i = i + 1) begin
      s1_subw_in_a[i] = {1'b0, s1_closest_rep[CLOSEST_REP_OFS+i*B_W+:B_W]};
    end
    s1_subw_in_a[L] = {1'b0,{B_W{s1_closest_rep_sign}}};
  end

  assign s1_carry[0] = 1'b0;

  generate
    for (genvar gen_i = 0; gen_i < L; gen_i = gen_i + 1) begin : gen_loop
      logic [B_W:0] s1_subw_w_c;
      logic [B_W:0] s1_subw_result_tmp;
      logic         s1_propagate_carry;
      logic         s1_ge_half;
      logic         s1_overflow;
      logic         s1_gt_half;

      assign s1_subw_w_c = s1_subw_in_a[gen_i] + s1_carry[gen_i];

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
          s1_subw_in_a[gen_i][B_W-1] & |{s1_subw_in_a[gen_i][B_W-2:0], s1_carry[gen_i]};
      assign s1_ge_half =
          s1_subw_in_a[gen_i][B_W-1] | &{s1_subw_in_a[gen_i][B_W-2:0], s1_carry[gen_i]};
      assign s1_overflow = &{s1_subw_in_a[gen_i][B_W-1:0], s1_carry[gen_i]};

      // Propagate a carry if current subw is already a negative or if the subw is > b/2.
      // In the case = b/2, propagate only if a propagation analysis is necessary on
      // the next subw.
      assign s1_propagate_carry = s1_overflow | s1_gt_half |
          (s1_ge_half & s1_subw_in_a[gen_i+1][B_W-1]);

      assign s1_carry[gen_i+1] = s1_propagate_carry;

      // s1_propagate_carry=1 : inverse the sign
      // s1_propagate_carry=0 : set the sign to 0
      assign s1_subw_result_tmp = s1_propagate_carry ?
          {~(s1_subw_w_c[B_W]), s1_subw_w_c[B_W-1:0]} : {1'b0, s1_subw_w_c[B_W-1:0]};

      if (OUT_2SCOMPL) begin
        assign s1_subw_out_a[gen_i] = s1_subw_result_tmp;
      end
      else begin
        assign s1_subw_out_a[gen_i][B_W]     = s1_subw_result_tmp[B_W];
        assign s1_subw_out_a[gen_i][B_W-1:0] = s1_subw_result_tmp[B_W] ? ~s1_subw_w_c[B_W-1:0]+1: s1_subw_w_c[B_W-1:0];
      end

    end
  endgenerate

  // ============================================================================================== --
  // Output register
  // ============================================================================================== --
  logic [L-1:0][B_W:0] s2_subw_out_a;
  logic [SIDE_W-1:0]   s2_side;
  logic                s2_avail;

  always_ff @(posedge clk) begin
    s2_subw_out_a <= s1_subw_out_a;
    s2_side       <= s1_side;
  end

  always_ff @(posedge clk)
    if (!s_rst_n) s2_avail <= 1'b0;
    else          s2_avail <= s1_avail;

  assign out_data  = s2_subw_out_a;
  assign out_side  = s2_side;
  assign out_avail = s2_avail;
endmodule

