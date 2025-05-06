// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : mod_reduct_solinas3
// ----------------------------------------------------------------------------------------------
//
// Modular reduction with specific modulo value:
//  MOD_M = 2**MOD_W - 2**INT_POW0 -2**INT_POW1 + 1
//
// Some simplifications are made in the RTL that makes the support for all values
// with the form described above not possible.
// Indeed the wrap done to get the factors for the final sum is only done once in the code.
// For some value of INT_POW, repetition of this wrapping is necessary. Particularly when
// (MOD_W-INT_POW) is small.
//
// Can deal with input up to 2*MOD_W+1 bits.
// This is the size of the sum of the 2 results of multiplication of 2
// values % MOD_M.
//
// LATENCY = IN_PIPE + $countone(LAT_PIPE_MH)
// ==============================================================================================

module mod_reduct_solinas3 #(
  parameter int          MOD_W      = 32,
  parameter [MOD_W-1:0]  MOD_M      = 2**MOD_W - 2**(2*MOD_W/3) - 2**(MOD_W/3) + 1,
  parameter int          OP_W       = 2*MOD_W+1, // Should be in [MOD_W:2*MOD_W+1]
  parameter bit          IN_PIPE    = 1,
  parameter int          SIDE_W     = 0, // Side data size. Set to 0 if not used
  parameter [1:0]        RST_SIDE   = 0  // If side data is used,
                                         // [0] (1) reset them to 0.
                                         // [1] (1) reset them to 1.
)
(
  // System interface
  input  logic               clk,
  input  logic               s_rst_n,
  // Data interface
  input  logic [OP_W-1:0]    a,
  output logic [MOD_W-1:0]   z,
  // Control + side interface - optional
  input  logic               in_avail,
  output logic               out_avail,

  input  logic [SIDE_W-1:0]  in_side,
  output logic [SIDE_W-1:0]  out_side

);

  import mod_reduct_solinas3_pkg::*;

// ============================================================================================== --
// localparam
// ============================================================================================== --
  // INT stands for intermediate
  // Use 32 bit to express integer, and have packed structure.

  // In the computation, we condider the different internal powers INT_POW.
  // For the calculation we also consider the term "+1", which is translated as an internal
  // power equals to 0.
  // This additional power is added as the INT_POW_NB+1th power in the calculation.

  localparam int                     INT_POW_NB  = 2;
  localparam int                     PROC_W      = MOD_W*2+1;
  localparam [INT_POW_NB:0][31:0]    INT_POW     = {32'd0,get_int_pow()}; // 32?

  // STRIDE distance between the power and MOD_W.
  localparam [INT_POW_NB:0][31:0]    STRIDE      = get_stride(INT_POW);
  // Number of sub-parts of the input that have to be added for an internal power.
  localparam int                     POS_NB      = get_pos_nb(MOD_W);
  // Sub-lsb lsb bit position
  localparam [POS_NB-1:0][31:0]      POS         = get_pos(MOD_W);
  localparam [INT_POW_NB:0][31:0]    ADD_BIT     = get_additional_bit_nb();
  localparam [31:0]                  MAX_ADD_BIT = get_max(ADD_BIT, INT_POW_NB+1);
  localparam [31:0]                  MAX_STRIDE  = get_max(STRIDE, INT_POW_NB);  // do not take power 0 into account
  localparam [31:0]                  WRAP_W      = get_wrap_size(); // wrap size for all int_power except power 0.

  localparam int                     A_DATA_W     = SIDE_W + OP_W;
  localparam [MOD_W:0]               MINUS_MOD_M  = ~{1'b0, MOD_M} + 1; // signed
  localparam [MOD_W+1:0]             MINUS_2MOD_M = ~{1'b0, MOD_M, 1'b0} + 1; // signed

  // change stride order - to ease compute
  localparam [INT_POW_NB:0][31:0]              RSTRIDE     = get_rstride();
  localparam [INT_POW_NB:0][POS_NB-1:0][31:0]  RPOS        = get_rpos();

  // Check parameters
  generate
    for (genvar gen_i=0; gen_i<INT_POW_NB; gen_i=gen_i+1) begin
      if (ADD_BIT[gen_i] > STRIDE[gen_i]) begin : __UNSUPPORTED_MODULO__
        $fatal(1, "> ERROR: Modulo 0x%0x is not supported for stride %0d, because the intermediate compute is too large (+%0d bits).",
                MOD_M, STRIDE[gen_i], ADD_BIT[gen_i]);
      end
    end

    if (ADD_BIT[INT_POW_NB] > 1) begin : __UNSUPPORTED_MODULO__
        $fatal(1, "> ERROR: Modulo 0x%0x is not supported, because the intermediate compute is too large (+%0d bits). The correction only supports down to -2*MOD_M+1",
                MOD_M, ADD_BIT[INT_POW_NB]);
    end

    if (MOD_M != 2**MOD_W-2**INT_POW[0]-2**INT_POW[1] + 1) begin : __NOT_SOLINAS_3_MODULO__
      $fatal(1, "> ERROR: The modulo is not a Solinas 3 modulo 0x%0x", MOD_M);
    end

    if (MOD_M[MOD_W-1] == 0) begin : __ERROR_MODULO_MSB__
      $fatal(1, "> ERROR: The modulo [MOD_W-1]=[%0d] bit should be 1 : 0x%0x", MOD_W-1,MOD_M);
    end

  endgenerate

// ============================================================================================== --
// Constant function
// ============================================================================================== --
  // Since MOD_M has the following form:
  // MOD_M = 2**MOD_W - 2**INT_POW0 - 2**INT_POW1 + 1
  // We can retreive INT_POW0 and INT_POW1
  function automatic [INT_POW_NB-1:0][31:0] get_int_pow();
    bit   [INT_POW_NB-1:0][  31:0] pow;
    logic [INT_POW_NB-1:0][MOD_W:0] temp;

    temp[0] = $clog2((((2**MOD_W)+1)- MOD_M) >> 1); //>>1 : To avoid to take into account the 2nd term.
    temp[1] = $clog2(((2**MOD_W)+1-2**temp[0])- MOD_M);

    pow[0] = temp[0];
    pow[1] = temp[1];

    return pow;
  endfunction

  function [INT_POW_NB:0][31:0] get_stride(bit[INT_POW_NB:0][31:0] pow);
    bit [INT_POW_NB:0][31:0] stride;
    for (int i=0; i<INT_POW_NB+1; i=i+1) begin
      stride[i] = MOD_W - pow[i];
    end
    return stride;
  endfunction

  // Recursive function to get the total number of positions to consider.
  function automatic int get_pos_nb(int start);
    int nb;
    nb = 0; // includes initial position start
    for (int i=0; i<INT_POW_NB+1; i=i+1) begin // Takes power 0 into account.
      int p;
      p = start + STRIDE[i];
      if (p < PROC_W) begin
        nb = nb + 1;
        nb = nb + get_pos_nb(p);
      end
    end
    return nb;
  endfunction

  // Recursive function to get the different position to consider in the computation
  function automatic [POS_NB*INT_POW_NB-1:0][31:0] get_pos_core(int start, bit [POS_NB*INT_POW_NB-1:0][31:0] prev_pos);
    bit [INT_POW_NB*POS_NB-1:0][31:0] pos;
    bit [INT_POW_NB*POS_NB-1:0][31:0] rec_pos;

    pos = prev_pos;
    for (int i=0; i<INT_POW_NB; i=i+1) begin
      int p;
      p = start + STRIDE[i];
      if (p < PROC_W) begin
        rec_pos = get_pos_core(p, pos);
        pos = rec_pos << 32 | p;
//        $display("pos=0x%0x STRIDE=%0d start=%0d p=%0d",pos,STRIDE[i],start, p);
      end
    end
    return pos;
  endfunction

  function [POS_NB-1:0][31:0] get_pos(int start);
    bit [POS_NB*INT_POW_NB-1:0][31:0] pos_tmp;
    bit [POS_NB-1:0][31:0] pos;
    int k;
    pos_tmp = get_pos_core(start, 0); // Set prev_pos to 0
    pos_tmp = pos_tmp << 32 | start;
    k=0;
    for (int i=0; i<POS_NB; i=i+1) begin
      for (int j=0; j<INT_POW_NB; j=j+1) begin
        if (pos_tmp[i*INT_POW_NB+j]!=0) begin
// pragma translate_off
          assert(k < POS_NB)
          else begin
            $fatal(1, "> ERROR: in position generation!");
          end
// pragma translate_on
          pos[k] = pos_tmp[i*INT_POW_NB+j];
          k=k+1;
        end
      end
    end
    return pos;
  endfunction

  // Compute additional bits for each stride.
  // This bits are the additional ones resulting from the intermediate compute.
  function [INT_POW_NB:0][31:0] get_additional_bit_nb();
    bit [INT_POW_NB:0][MOD_W+POS_NB:0] tmp;
    bit [INT_POW_NB:0][31:0] add_bit_nb;

    for (int i=0; i<INT_POW_NB+1; i=i+1) begin
      bit [MOD_W+POS_NB-1:0] total;
      total = 0;
      for (int p=0; p<POS_NB; p=p+1) begin
        int size;
        size = STRIDE[i] + POS[p];
        size = (size > PROC_W) ? PROC_W-POS[p] : STRIDE[i];
        total = total + 2**size-1;
        $display("STRIDE[%0d]=%0d POS[%0d]=%0d size=%0d total=0x%0x", i, STRIDE[i], p, POS[p], size, total);
      end
      tmp[i] = $clog2(total+1) - STRIDE[i];
      add_bit_nb[i] = tmp[i];
    end
    return add_bit_nb;
  endfunction

  function [31:0] get_max([INT_POW_NB:0][31:0] list, int nb_elt = 0);
    bit [31:0] max;
    max = list[0];
    for (int i = 1; i<nb_elt; i=i+1)
      max = list[i] > max ? list[i] : max;
    return max;
  endfunction

  function [31:0] get_wrap_size();
    bit [MOD_W+INT_POW_NB-1:0] total;
    bit [31:0] tmp;

    total = 0;
    for (int i=0; i<INT_POW_NB; i=i+1) begin
      total = total + 2**ADD_BIT[i]-1;
    end
    tmp = $clog2(total+1);
    return tmp[31:0]; // Count from 0 to total included
  endfunction

  // compute the remaining stride for a given INT_POW (express in the order "bis")
  function [INT_POW_NB:0][31:0] get_rstride();
    bit [INT_POW_NB:0][31:0] rstride;
    rstride[0] = STRIDE[0];
    for (int i=1; i<INT_POW_NB+1; i=i+1) begin
      rstride[i] = STRIDE[i] - STRIDE[i-1];
    end
    return rstride;
  endfunction

  function [INT_POW_NB:0][POS_NB-1:0][31:0] get_rpos();
    bit [INT_POW_NB:0][POS_NB-1:0][31:0] rpos;
    for (int i=0; i<INT_POW_NB+1; i=i+1) begin
      for (int p=0; p<POS_NB; p=p+1) begin
        rpos[i][p] = (i==0) ? POS[p] :
                     ((POS[p] + STRIDE[i-1]) > PROC_W) ? PROC_W : POS[p] + STRIDE[i-1];
      end
    end
    return rpos;
  endfunction

  // ============================================================================================ //
  // Input registers
  // ============================================================================================ //
  logic [OP_W-1:0]       s0_a;
  logic                  s0_avail;
  logic [SIDE_W-1:0]     s0_side;

  logic [A_DATA_W-1:0]   in_a_data;
  logic [A_DATA_W-1:0]   s0_a_data;

  generate
    if (SIDE_W > 0) begin
      assign in_a_data       = {in_side, a};
      assign {s0_side, s0_a} = s0_a_data;
    end
    else begin
      assign in_a_data = a;
      assign s0_a      = s0_a_data;
      assign s0_side   = 'x;
    end
  endgenerate

  common_lib_delay_side #(
    .LATENCY    (IN_PIPE ),
    .SIDE_W     (A_DATA_W),
    .RST_SIDE   (RST_SIDE)
  ) in_delay_side (
    .clk      (clk      ),
    .s_rst_n  (s_rst_n  ),

    .in_avail (in_avail ),
    .out_avail(s0_avail ),

    .in_side  (in_a_data),
    .out_side (s0_a_data)
  );

  // ============================================================================================ //
  // s0 : Partial additions
  // ============================================================================================ //
  // In the stage, partial additions are done.
  // Sub-words of the input are added. The size of the subwords depend on STRIDE.
  //
  // A the end of the computation of the partial sums, the bit a[2*MOD_W] is substracted.
  //
  // For example, with MOD_W=32, and INT_POW=[17, 13, 0], the partial addition is:
  // POS = [32, 47, 51, 62]
  // STRIDE = [15, 19, 32]
  // c[0]  = a[46:32] + a[61:47] + a[64:51] + a[64:62] - a[64] // stride = 15
  // c[1]  = a[50:32] + a[64:47] + a[64:51] + a[64:62] - a[64] // stride = 19
  // c[2]  = a[63:32] + a[64:47] + a[64:51] + a[64:62] - a[64] // stride = MOD_W
  //
  // c[i] have ADD_BIT additional bits. Wrap them :
  // wrap  = SUM(c[i][STRIDE[i]+:ADD_BIT[i]])  for INT_POW != 0 (i<INT_POW_NB)
  // e[i]  = c[i][STRIDE[i]-1:0] + wrap        for INT_POW != 0 (i<INT_POW_NB)
  // f     = c[2] + wrap
  //
  // To save some logic, the processed calulation is the following one:
  // c_part[0]  = a[46:32] + a[61:47] + a[64:51] + a[64:62] - a[64] // stride = 15
  // c_part[1]  = a[50:47] + a[64:62]                               // stride = 19
  // c_part[2]  = a[63:51]                                          // stride = MOD_W
  //
  // c[0] = c_part[0]
  // c[1] = c_part[0]
  //         + c_part[1] << STRIDE[0]
  //      = c[0] + c_part[1] << STRIDE[0]
  // c[2] = c_part[0]
  //         + c_part[1] << STRIDE[0]
  //         + c_part[2] << STRIDE[1]
  //      = c[1] + c_part[2] << STRIDE[1]

  logic [PROC_W+MOD_W-1:0]                       s0_a_ext; // Extend a with 0
  logic [INT_POW_NB:0][MOD_W+MAX_ADD_BIT-1:0]    s0_c;
  logic [WRAP_W-1:0]                             s0_wrap;
  logic [INT_POW_NB:0][MOD_W+MAX_ADD_BIT-1:0]    s0_c_part;

  assign s0_a_ext = s0_a; // MSB are extended with 0

  // Workaround to avoid warning [VRFC 10-8871] "constant expression is required here"
  // STRIKE[i] and POS[p] are not recognized as constant, when i and p are indices
  // of "for loop".
  logic [INT_POW_NB-1:0][MAX_ADD_BIT-1:0]       s0_c_msb;
  logic [INT_POW_NB-1:0][MOD_W+MAX_ADD_BIT-1:0] s0_c_lsb;
  logic [INT_POW_NB:0][POS_NB-1:0][MOD_W-1:0]   s0_a_part;
  generate
    for (genvar gen_i=0; gen_i<INT_POW_NB; gen_i=gen_i+1) begin
      assign s0_c_msb[gen_i] = s0_c[gen_i][STRIDE[gen_i]+:ADD_BIT[gen_i]]; // extend with 0
      assign s0_c_lsb[gen_i] = s0_c[gen_i][STRIDE[gen_i]-1:0];             // "
    end
    for (genvar gen_i=0; gen_i<INT_POW_NB+1; gen_i=gen_i+1) begin
      for (genvar gen_p=0; gen_p<POS_NB; gen_p=gen_p+1) begin
        assign s0_a_part[gen_i][gen_p] = s0_a_ext[RPOS[gen_i][gen_p]+:RSTRIDE[gen_i]]; // extend with 0
      end
    end
  endgenerate

  // Partial sums
  always_comb begin
    for (int i=0; i<INT_POW_NB+1; i=i+1) begin
      logic [MOD_W+MAX_ADD_BIT-1:0] tmp;
      tmp = 0;
      for (int p=0; p<POS_NB; p=p+1) begin
        tmp = tmp + s0_a_part[i][p];
      end
      s0_c_part[i] = tmp;
    end
  end

/*
// The following process is the computation to be done.
// Due to a need of acceleration, the final part of the computation
// is done in the next cycle.
// Therefore the expression of this computation has been explicited for
// our particular case of INT_POW_NB=2
  always_comb begin
    s0_c[0] = s0_c_part[0] - s0_a_ext[PROC_W-1];
    for (int i=1; i<INT_POW_NB+1; i=i+1) begin
      logic [MOD_W+MAX_ADD_BIT-1:0] tmp;
      tmp = s0_c_part[i] << STRIDE[i-1];
      s0_c[i] = tmp + s0_c[i-1];
    end
  end
*/
  logic [INT_POW_NB:0][MOD_W+MAX_ADD_BIT-1:0]    s0_c_tmp;
  assign s0_c_tmp[1] = s0_c_part[1] << STRIDE[0];
  assign s0_c_tmp[2] = s0_c_part[2] << STRIDE[1];

  assign s0_c[0] = s0_c_part[0] - s0_a_ext[PROC_W-1];
  assign s0_c[1] = s0_c[0] + s0_c_tmp[1];
  // The following calculation is done in the next cycle.
  //assign s0_c[2] = s0_c[1] + s0_c_tmp[2];
  //
  //Note that s0_c[2] is s0_f.

  // wrap
  always_comb begin
    s0_wrap = '0;
    for (int i=0; i<INT_POW_NB; i=i+1) begin
      s0_wrap = s0_wrap + s0_c_msb[i];
    end
  end

  /* Computation to be done.
   * Split it into 2 parts for timing optimization.
   * Second part of the calculation is done in the next cycle.
  logic [MOD_W+1:0] s0_a_plus_c;
  assign s0_a_plus_c = {2'b00,s0_a[MOD_W-1:0]}
                     + {2'b00,s0_c_lsb[0],{INT_POW[0]{1'b0}}}
                     + {2'b00,s0_c_lsb[1],{INT_POW[1]{1'b0}}};
  */

  logic [MOD_W+1:0] s0_a_plus_c_part0;
  assign s0_a_plus_c_part0 = {2'b00,s0_a[MOD_W-1:0]}
                           + {2'b00,s0_c_lsb[0],{INT_POW[0]{1'b0}}};
  // ============================================================================================ //
  // s1 : final addition
  // ============================================================================================ //
  logic [MOD_W+ADD_BIT[INT_POW_NB]:0] s1_f;
  logic [MOD_W+ADD_BIT[INT_POW_NB]:0] s1_f_part0;
  logic [MOD_W+ADD_BIT[INT_POW_NB]:0] s1_f_part1;
  logic [MOD_W+1:0]                   s1_a_plus_c_part0;
  logic [MOD_W+1:0]                   s1_a_plus_c;
  logic [WRAP_W-1:0]                  s1_wrap;
  logic                               s1_avail;
  logic [SIDE_W-1:0]                  s1_side;

  generate
    if (LAT_PIPE_MH[0]) begin : gen_pipe_0
      always_ff @(posedge clk) begin
        s1_a_plus_c_part0 <= s0_a_plus_c_part0;
        s1_wrap           <= s0_wrap;
        s1_f_part0        <= s0_c[1];
        s1_f_part1        <= s0_c_tmp[2]; // Note that the LSB "0" will be simplified by the synthesizer
      end
    end
    else begin : no_gen_pipe_0
      assign  s1_a_plus_c_part0 = s0_a_plus_c_part0;
      assign  s1_wrap           = s0_wrap;
      assign  s1_f_part0        = s0_c[1];
      assign  s1_f_part1        = s0_c_tmp[2];
    end
  endgenerate

  common_lib_delay_side #(
    .LATENCY    (LAT_PIPE_MH[0]),
    .SIDE_W     (SIDE_W  ),
    .RST_SIDE   (RST_SIDE)
  ) s0_delay_side (
    .clk      (clk      ),
    .s_rst_n  (s_rst_n  ),

    .in_avail (s0_avail ),
    .out_avail(s1_avail ),

    .in_side  (s0_side  ),
    .out_side (s1_side  )
  );

  assign s1_f = s1_f_part0 + s1_f_part1;
  assign s1_a_plus_c = s1_a_plus_c_part0
                  + {2'b00, s1_f_part0[STRIDE[1]-1:0],{INT_POW[1]{1'b0}}};

  logic [MOD_W+2:0] s1_sum; // signed
  assign s1_sum = {1'b0,s1_a_plus_c}
                  + {{MOD_W{1'b0}},s1_wrap,{INT_POW[0]{1'b0}}}
                  + {{MOD_W{1'b0}},s1_wrap,{INT_POW[1]{1'b0}}}
                  - {2'b00,s1_f}
                  - {{MOD_W+2{1'b0}},s1_wrap};


  // ============================================================================================ //
  // s2 : Modulo correction - part 1
  // ============================================================================================ //
  logic [MOD_W+2:0]  s2_sum; // signed
  logic              s2_avail;
  logic [SIDE_W-1:0] s2_side;

  generate
    if (LAT_PIPE_MH[1]) begin : gen_pipe_11
      always_ff @(posedge clk) begin
        s2_sum     <= s1_sum;
      end
    end
    else begin : no_gen_pipe_11
      assign  s2_sum     = s1_sum;
    end
  endgenerate

  common_lib_delay_side #(
    .LATENCY    (LAT_PIPE_MH[1]),
    .SIDE_W     (SIDE_W  ),
    .RST_SIDE   (RST_SIDE)
  ) s1_delay_side (
    .clk      (clk      ),
    .s_rst_n  (s_rst_n  ),

    .in_avail (s1_avail ),
    .out_avail(s2_avail ),

    .in_side  (s1_side  ),
    .out_side (s2_side  )
  );

  // Comparisons
  logic [MOD_W+1:0] s2_mod_inc; // signed
  logic [MOD_W+2:0] s2_sum_op_2mod;

  assign s2_mod_inc    = s2_sum[MOD_W+2]       ? {1'b0,MOD_M, 1'b0} : // negative sum
                         s2_sum[MOD_W+:2] != 0 ? MINUS_2MOD_M :       // greater or equal to 2**MOD_W
                         0;
  assign s2_sum_op_2mod = s2_sum +{s2_mod_inc[MOD_W+1],s2_mod_inc};

// pragma translate_off
  always_ff @(posedge clk) begin
    if (s2_sum !== 'x) begin
      if (s2_sum[MOD_W+2]) begin
        logic [MOD_W+2:0] _s2_sum_abs;
        _s2_sum_abs = ~s2_sum + 1;
        assert(_s2_sum_abs < 2*MOD_M)
        else $fatal(1,"> ERROR: Reduction underflow : sum is less than -2*MOD_M 0x%x (abs=0x%0x)",s2_sum, _s2_sum_abs);
      end
      else begin
        assert(s2_sum < 4*MOD_M)
        else $fatal(1,"> ERROR: Reduction overflow : sum is greater than 3*MOD_M 0x%x",s2_sum);
      end
    end
  end
// pragma translate_on

  // ============================================================================================ //
  // s3 : Modulo correction - part 2
  // ============================================================================================ //
  logic [MOD_W+2:0]  s3_sum_op_2mod;
  logic              s3_avail;
  logic [SIDE_W-1:0] s3_side;

  generate
    if (LAT_PIPE_MH[2]) begin : gen_pipe_1
      always_ff @(posedge clk) begin
        s3_sum_op_2mod <= s2_sum_op_2mod;
      end
    end
    else begin : no_gen_pipe_1
      assign s3_sum_op_2mod = s2_sum_op_2mod;
    end
  endgenerate

  common_lib_delay_side #(
    .LATENCY    (LAT_PIPE_MH[2]),
    .SIDE_W     (SIDE_W  ),
    .RST_SIDE   (RST_SIDE)
  ) s2_delay_side (
    .clk      (clk      ),
    .s_rst_n  (s_rst_n  ),

    .in_avail (s2_avail ),
    .out_avail(s3_avail ),

    .in_side  (s2_side  ),
    .out_side (s3_side  )
  );


  logic [MOD_W:0]   s3_mod_inc; // signed
  logic [MOD_W+2:0] s3_sum_op_mod;

  assign s3_mod_inc        = s3_sum_op_2mod[MOD_W+2] ? {1'b0,MOD_M} : MINUS_MOD_M;
  assign s3_sum_op_mod     = s3_sum_op_2mod + {{2{s3_mod_inc[MOD_W]}},s3_mod_inc};

  logic [MOD_W-1:0]  s3_result;

  assign s3_result = s3_sum_op_2mod[MOD_W+2] ? // negative value
                        s3_sum_op_mod[MOD_W-1:0] :
                        s3_sum_op_mod[MOD_W+2] ? s3_sum_op_2mod[MOD_W-1:0] : s3_sum_op_mod[MOD_W-1:0];


// pragma translate_off
  always_ff @(posedge clk) begin
    if (s3_sum_op_2mod !== 'x) begin
      if (s3_sum_op_2mod[MOD_W+2]) begin
        logic [MOD_W+2:0] _s3_sum_op_2mod_abs;
        _s3_sum_op_2mod_abs = ~s3_sum_op_2mod + 1;
        assert(_s3_sum_op_2mod_abs < MOD_M)
        else $fatal(1,"> ERROR: Reduction underflow : s3_sum_op_2mod is less than -MOD_M 0x%x (abs=0x%0x)",s3_sum_op_2mod, _s3_sum_op_2mod_abs);
      end
      else begin
        assert(s3_sum_op_2mod < 2*MOD_M)
        else $fatal(1,"> ERROR: Reduction overflow : sum is greater than 2*MOD_M 0x%x",s3_sum_op_2mod);
      end
    end
  end
// pragma translate_on

  // ============================================================================================ //
  // s4 : output
  // ============================================================================================ //
  logic [MOD_W-1:0]  s4_result;
  logic              s4_avail;
  logic [SIDE_W-1:0] s4_side;

  generate
    if (LAT_PIPE_MH[3]) begin : gen_pipe_2
      always_ff @(posedge clk) begin
        s4_result <= s3_result;
      end
    end
    else begin : no_gen_pipe_2
      assign s4_result = s3_result;
    end
  endgenerate

  common_lib_delay_side #(
    .LATENCY    (LAT_PIPE_MH[3]),
    .SIDE_W     (SIDE_W  ),
    .RST_SIDE   (RST_SIDE)
  ) s3_delay_side (
    .clk      (clk      ),
    .s_rst_n  (s_rst_n  ),

    .in_avail (s3_avail ),
    .out_avail(s4_avail ),

    .in_side  (s3_side  ),
    .out_side (s4_side  )
  );

  assign z         = s4_result;
  assign out_avail = s4_avail;
  assign out_side  = s4_side;

endmodule
