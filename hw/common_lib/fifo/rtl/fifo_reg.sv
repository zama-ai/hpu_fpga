// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// FIFO using registers.
// Ready/valid interface is used.
// in_rdy = 0 : the FIFO is full.
// out_vld = 0 : the FIFO is empty.
//
// Parameters:
//  WIDTH : data width
//  DEPTH : FIFO depth
//
// ==============================================================================================

module fifo_reg #(
  parameter int               WIDTH       = 8,
  parameter int               DEPTH       = 32,
  localparam int              LAT_MAX     = 2,
  parameter     [LAT_MAX-1:0] LAT_PIPE_MH = {1'b1, 1'b1} // NOTE [0] should always be 1 by
                                                         // construction.
) (
  input              clk,     // clock
  input              s_rst_n, // synchronous reset

  input  [WIDTH-1:0] in_data,
  input              in_vld,
  output             in_rdy,

  output [WIDTH-1:0] out_data,
  output             out_vld,
  input              out_rdy
);

  // ============================================================================================== --
  // localparam
  // ============================================================================================== --
  localparam int DEPTH_W = $clog2(DEPTH);

  // ============================================================================================== --
  // fifo_reg
  // ============================================================================================== --
  logic [WIDTH-1:0] datar;
  logic             datar_vld;
  logic             datar_rdy;

  generate
    if (DEPTH <= 2) begin : gen_depth_le_2
      logic [WIDTH-1:0] d;
      logic             d_vld;
      logic             d_rdy;

      fifo_element #(
        .WIDTH         (WIDTH),
        .DEPTH         (1),
        .TYPE_ARRAY    (4'h2),
        .DO_RESET_DATA (0),
        .RESET_DATA_VAL(0) // UNUSED
      ) fifo_element (
        .clk    (clk),
        .s_rst_n(s_rst_n),

        .in_data (in_data),
        .in_vld  (in_vld),
        .in_rdy  (in_rdy),

        .out_data(d),
        .out_vld (d_vld),
        .out_rdy (d_rdy)
      );

      if (DEPTH == 2) begin : gen_depth_eq_2
        fifo_element #(
          .WIDTH         (WIDTH),
          .DEPTH         (1),
          .TYPE_ARRAY    (4'h1),
          .DO_RESET_DATA (0),
          .RESET_DATA_VAL(0) // UNUSED
        ) fifo_element (
          .clk    (clk),
          .s_rst_n(s_rst_n),

          .in_data (d),
          .in_vld  (d_vld),
          .in_rdy  (d_rdy),

          .out_data(datar),
          .out_vld (datar_vld),
          .out_rdy (datar_rdy)
        );
      end
      else begin
        assign datar     = d;
        assign datar_vld = d_vld;
        assign d_rdy     = datar_rdy;
      end
    end
    else begin : gen_depth_gt_2
      // ---------------------------------------------------------------------------------------------- --
      // Pointers
      // ---------------------------------------------------------------------------------------------- --
      // pointers
      logic [DEPTH_W:0]   rp;
      logic [DEPTH_W:0]   wp;

      logic [DEPTH_W-1:0] rp_lsb;
      logic [DEPTH_W-1:0] wp_lsb;
      logic               rp_msb;
      logic               wp_msb;
      logic               is_full;
      logic               is_empty;

      assign is_empty = rp == wp;
      assign is_full  = (rp_msb != wp_msb) & (rp_lsb == wp_lsb);

      if (2 ** DEPTH_W == DEPTH) begin : depth_is_power_of_2_gen
        logic [DEPTH_W:0] rpD;
        logic [DEPTH_W:0] wpD;

        assign rpD = (datar_vld && datar_rdy) ? rp + 1 : rp;
        assign wpD = (in_vld && in_rdy) ? wp + 1 : wp;

        always_ff @(posedge clk)
          if (!s_rst_n) begin
            rp <= '0;
            wp <= '0;
          end else begin
            rp <= rpD;
            wp <= wpD;
          end

        assign rp_msb = rp[DEPTH_W];
        assign wp_msb = wp[DEPTH_W];
        assign rp_lsb = rp[DEPTH_W-1:0];
        assign wp_lsb = wp[DEPTH_W-1:0];

      end else begin : no_depth_is_power_of_2_gen
        logic [DEPTH_W-1:0] rp_lsbD;
        logic [DEPTH_W-1:0] wp_lsbD;
        logic               rp_msbD;
        logic               wp_msbD;
        assign rp      = {rp_msb, rp_lsb};
        assign wp      = {wp_msb, wp_lsb};

        assign rp_lsbD = (datar_vld && datar_rdy) ? (rp_lsb == DEPTH - 1) ? 0 : rp_lsb + 1 : rp_lsb;
        assign rp_msbD = (datar_vld && datar_rdy && (rp_lsb == DEPTH - 1)) ? ~rp_msb : rp_msb;
        assign wp_lsbD = (in_vld && in_rdy) ? (wp_lsb == DEPTH - 1) ? 0 : wp_lsb + 1 : wp_lsb;
        assign wp_msbD = (in_vld && in_rdy && (wp_lsb == DEPTH - 1)) ? ~wp_msb : wp_msb;

        always_ff @(posedge clk)
          if (!s_rst_n) begin
            rp_lsb <= '0;
            rp_msb <= '0;
            wp_lsb <= '0;
            wp_msb <= '0;
          end else begin
            rp_lsb <= rp_lsbD;
            rp_msb <= rp_msbD;
            wp_lsb <= wp_lsbD;
            wp_msb <= wp_msbD;
          end
      end

      // ---------------------------------------------------------------------------------------------- --
      // Data array
      // ---------------------------------------------------------------------------------------------- --
      logic [WIDTH-1:0] a[DEPTH-1:0];  // data array

      always_ff @(posedge clk) begin
        if (in_vld && in_rdy)
          a[wp_lsb] <= in_data;
      end

      assign datar = a[rp_lsb];

      // ---------------------------------------------------------------------------------------------- --
      // Control
      // ---------------------------------------------------------------------------------------------- --
      assign in_rdy    = ~is_full;
      assign datar_vld = ~is_empty;
    end  // DEPTH > 2

    if (LAT_PIPE_MH[LAT_MAX-1]) begin : output_pipe_gen
      fifo_element #(
        .WIDTH         (WIDTH),
        .DEPTH         (1),
        .TYPE_ARRAY    (1), // Use type 1 to put a register on the data path.
        .DO_RESET_DATA (0),
        .RESET_DATA_VAL(0) // UNUSED
      ) out_fifo_element (
        .clk    (clk),
        .s_rst_n(s_rst_n),

        .in_data(datar),
        .in_vld (datar_vld),
        .in_rdy (datar_rdy),

        .out_data(out_data),
        .out_vld (out_vld),
        .out_rdy (out_rdy)
      );
    end
    else begin : output_pipe_gen
      assign out_vld   = datar_vld;
      assign datar_rdy = out_rdy;
      assign out_data  = datar;
    end

  endgenerate
endmodule

