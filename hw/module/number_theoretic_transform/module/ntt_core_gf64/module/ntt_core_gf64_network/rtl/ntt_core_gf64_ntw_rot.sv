// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the rotation of a vector in several clock cycles.
// Here 2 cycles are used.
// ==============================================================================================

module ntt_core_gf64_ntw_rot
#(
  parameter bit    IN_PIPE         = 1'b1, // Recommended
  parameter int    OP_W            = 66,
  parameter int    C               = 128, // Number of coefficients. Should be a power of 2
  parameter int    ROT_C           = C <= 32 ? C/2 :
                                     C <= 256 ? 16 :
                                     C <= 1024 ? 32  : 64, // Rotation subword size in nb of coef unit
  parameter bit    DIR             = 1'b0, // Rotation direction
                                           // (0) : [0] = [-rot_factor]
                                           // (1) : [0] = [+rot_factor]
  parameter int    SIDE_W          = 0, // Side data size. Set to 0 if not used
  parameter [1:0]  RST_SIDE        = 0,  // If side data is used,
                                        // [0] (1) reset them to 0.
                                        // [1] (1) reset them to 1.
  localparam int   C_W             = $clog2(C) == 0 ? 1 : $clog2(C)

)
(
  input  logic                         clk,        // clock
  input  logic                         s_rst_n,    // synchronous reset

  input  logic [C-1:0][OP_W-1:0]       in_data,
  input  logic [C-1:0]                 in_avail,
  input  logic [SIDE_W-1:0]            in_side,
  input  logic [C_W-1:0]               in_rot_factor,

  output logic [C-1:0][OP_W-1:0]       out_data,
  output logic [C-1:0]                 out_avail,
  output logic [SIDE_W-1:0]            out_side,

  // signals 1 cycle before the output
  output logic [C-1:0]                 penult_avail,
  output logic [SIDE_W-1:0]            penult_side

);

  // =========================================================================================== --
  // localparam
  // =========================================================================================== --
  localparam int ROT_SUBW_NB = C / ROT_C;
  localparam int ROT_C_Z     = $clog2(ROT_C);
  localparam int ROT_C_W     = $clog2(ROT_C) == 0 ? 1 : $clog2(ROT_C);
  localparam int ROT_SUBW_W  = $clog2(ROT_SUBW_NB) == 0 ? 1 : $clog2(ROT_SUBW_NB);

  generate
    if (2**$clog2(C) != C) begin : __UNSUPPORTED_C
      $fatal(1,"> ERROR: C (%0d) should be a power of 2.", C);
    end
    if (ROT_C < 2) begin : __UNSUPPORTED_ROT_C_0
      $fatal(1,"> ERROR: Support only ROT_C (%0d) >= 2", ROT_C);
    end
    if ((C % ROT_C) != 0) begin : __UNSUPPORTED_ROT_C_1
      $fatal(1,"> ERROR: ROT_C (%0d) should divide C (%0d)", ROT_C,C);
    end
    if (ROT_SUBW_NB > 32) begin : __WARNING_ROT_SIZE
      initial begin
        $display("> WARNING: NTT GF64 network rotation 2nd part is done with %0d sub-words, which may be not optimal.",ROT_SUBW_NB);
      end
    end
  endgenerate

  // =========================================================================================== --
  // Input pipe
  // =========================================================================================== --
  logic [C-1:0][OP_W-1:0] s0_data;
  logic [SIDE_W-1:0]      s0_side;
  logic [C_W-1:0]         s0_rot_factor;
  logic [C-1:0]           s0_avail;

  generate
    if (IN_PIPE) begin : gen_in_pipe
      always_ff @(posedge clk)
        if (!s_rst_n) s0_avail <= '0;
        else          s0_avail <= in_avail;

      // NOTE : if the synthesis enables it, we can use pp_drw_avail as enable
      // to save some power.
      always_ff @(posedge clk) begin
        s0_data         <= in_data;
        s0_rot_factor   <= in_rot_factor;
      end
    end else begin : gen_no_in_pipe
      assign s0_data       = in_data;
      assign s0_rot_factor = in_rot_factor;
      assign s0_avail      = in_avail;
    end
  endgenerate

  common_lib_delay_side #(
    .LATENCY    (IN_PIPE ),
    .SIDE_W     (SIDE_W  ),
    .RST_SIDE   (RST_SIDE)
  ) in_delay_side (
    .clk      (clk      ),
    .s_rst_n  (s_rst_n  ),

    .in_avail (in_avail[0] ),
    .out_avail(/*UNUSED*/),

    .in_side  (in_side  ),
    .out_side (s0_side  )
  );

  // =========================================================================================== --
  // s0
  // =========================================================================================== --
  // ------------------------------------------------------------------------------------------- --
  // Rotation - part1
  // ------------------------------------------------------------------------------------------- --
  // Does the rotation in 2 cycles, since C could be quite big.
  // First do "local rotation" on ROT_C coefficients.
  // Then rotate the subwords, during the 2nd clock cycle.

  logic [ROT_SUBW_NB-1:0][ROT_C-1:0][OP_W-1:0]     s0_rot_part1_data;
  logic [ROT_SUBW_NB*2-1:0][ROT_C/2-1:0][OP_W-1:0] s0_data_a;

  assign s0_data_a = s0_data;

  // Compute rotation factors
  logic                  s0_rot_part1_carry;
  logic [ROT_C_W-1:0]    s0_rot_part1_factor;
  logic [ROT_SUBW_W-1:0] s0_rot_part2_factor;

  assign s0_rot_part1_carry    = s0_rot_factor[ROT_C_Z-1];
  generate
    if (ROT_C_Z<2) begin : gen_rot_z_lt_2
      assign s0_rot_part1_factor = '0;
    end
    else begin : gen_no_rot_z_lt_2
      assign s0_rot_part1_factor = s0_rot_factor[ROT_C_Z-2:0];
    end
  endgenerate
  assign s0_rot_part2_factor = (s0_rot_factor >> ROT_C_Z) + s0_rot_part1_carry;

  // Rotation part1
  generate
    for (genvar gen_i=0; gen_i<ROT_SUBW_NB; gen_i=gen_i+1) begin : gen_rot_part_1_loop
      localparam int PREV_IDX = (2*gen_i-1) < 0 ? 2*ROT_SUBW_NB-1: (2*gen_i-1);
      localparam int NEXT_IDX = (2*gen_i+2) % (2*ROT_SUBW_NB);

      logic [2:0][ROT_C/2-1:0][OP_W-1:0] s0_rot_part1_in;
      logic [3*ROT_C/2-1:0][OP_W-1:0]    s0_rot_part1_in_a;
      logic [ROT_C-1:0][OP_W-1:0]        s0_rot_part1_l;

      assign s0_rot_part1_in_a = s0_rot_part1_in;

      // Rotate max range is ROT_C/2 instead of ROT_C, to lower the quantity of muxes. Help the tool.
      // Gather 3*ROT_C/2 consecutive elements.
      // According to carry and DIR:
      // DIR = 0 (rotation direction =>)
      //   carry = 0
      //     [prev.1] , [cur.0], [cur.1]
      //   carry = 1
      //     [cur.0] , [cur.1], [next.0]
      // DIR = 1 (rotation direction <=)
      //   carry = 0
      //     [cur.0] , [cur.1], [next.0]
      //   carry = 1
      //     [prev.1] , [cur.0], [cur.1]
      assign s0_rot_part1_in[0] = (s0_rot_part1_carry ^ DIR) ? s0_data_a[2*gen_i]   : s0_data_a[PREV_IDX];
      assign s0_rot_part1_in[1] = (s0_rot_part1_carry ^ DIR) ? s0_data_a[2*gen_i+1] : s0_data_a[2*gen_i];
      assign s0_rot_part1_in[2] = (s0_rot_part1_carry ^ DIR) ? s0_data_a[NEXT_IDX]  : s0_data_a[2*gen_i+1];

      // Local rotation
      always_comb
        for (int i=0; i<ROT_C; i=i+1) begin
          if (DIR)
            s0_rot_part1_l[i] = s0_rot_part1_in_a[i + s0_rot_part1_factor];
          else
            s0_rot_part1_l[i] = s0_rot_part1_in_a[ROT_C/2 + i - s0_rot_part1_factor];
        end

      assign s0_rot_part1_data[gen_i] = s0_rot_part1_l;

    end // gen_rot_part_1_loop
  endgenerate

  // =========================================================================================== --
  // s1
  // =========================================================================================== --
  logic [C-1:0]           s1_avail;
  logic [C-1:0][OP_W-1:0] s1_rot_part1_data;
  logic [ROT_SUBW_W-1:0]  s1_rot_part2_factor;
  logic [SIDE_W-1:0]      s1_side;

  always_ff @(posedge clk)
    if (!s_rst_n) s1_avail <= '0;
    else          s1_avail <= s0_avail;

  always_ff @(posedge clk) begin
    s1_rot_part1_data   <= s0_rot_part1_data;
    s1_rot_part2_factor <= s0_rot_part2_factor;
  end

  common_lib_delay_side #(
    .LATENCY    (1'b1    ),
    .SIDE_W     (SIDE_W  ),
    .RST_SIDE   (RST_SIDE)
  ) s0_delay_side (
    .clk      (clk      ),
    .s_rst_n  (s_rst_n  ),

    .in_avail (s0_avail[0] ),
    .out_avail(/*UNUSED*/),

    .in_side  (s0_side  ),
    .out_side (s1_side  )
  );

  // ------------------------------------------------------------------------------------------- --
  // Rotation - part2
  // ------------------------------------------------------------------------------------------- --
  logic [ROT_SUBW_NB-1:0][ROT_C-1:0][OP_W-1:0] s1_rot_part1_data_a;
  logic [ROT_SUBW_NB-1:0][ROT_C-1:0][OP_W-1:0] s1_rot_part2_data;

  assign s1_rot_part1_data_a = s1_rot_part1_data;

  always_comb
    for (int i=0; i<ROT_SUBW_NB; i=i+1) begin
      var [ROT_SUBW_W-1:0] rot_factor;
      rot_factor = DIR ? i+s1_rot_part2_factor : i-s1_rot_part2_factor;
      s1_rot_part2_data[i] = s1_rot_part1_data_a[rot_factor];
    end

  // ------------------------------------------------------------------------------------------- --
  // Penult output
  // ------------------------------------------------------------------------------------------- --
  assign penult_avail = s1_avail;
  assign penult_side  = s1_side;

  // =========================================================================================== --
  // s2
  // =========================================================================================== --
  logic [C-1:0][OP_W-1:0]       s2_rot_part2_data;
  logic [C-1:0]                 s2_avail;
  logic [SIDE_W-1:0]            s2_side;

  always_ff @(posedge clk)
    if (!s_rst_n) s2_avail <= '0;
    else          s2_avail <= s1_avail;

  always_ff @(posedge clk)
    s2_rot_part2_data   <= s1_rot_part2_data;

  common_lib_delay_side #(
    .LATENCY    (1'b1    ),
    .SIDE_W     (SIDE_W  ),
    .RST_SIDE   (RST_SIDE)
  ) s1_delay_side (
    .clk      (clk      ),
    .s_rst_n  (s_rst_n  ),

    .in_avail (s1_avail[0] ),
    .out_avail(/*UNUSED*/),

    .in_side  (s1_side  ),
    .out_side (s2_side  )
  );

  assign out_data   = s2_rot_part2_data;
  assign out_avail  = s2_avail;
  assign out_side   = s2_side;

endmodule
