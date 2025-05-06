// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module performs the multiplication with between the BLWE coefficient and the
// KSK.
// It also takes care of the addition with the result of the previous pep_ks_mult_node,
// which is also processing a coefficient of the same BLWE, on the same ks_loop.
//
// ==============================================================================================

module pep_ks_mult_node #(
  parameter int KS_B_W = 3,
  parameter int LBZ    = 1,
  parameter int OP_W   = 64,
  parameter int SIDE_W = 0 // Set to 0 if not used.
)
(
  input  logic                       clk,        // clock
  input  logic                       s_rst_n,    // synchronous reset

  input  logic [LBZ-1:0][KS_B_W-1:0] prevx_data,
  input  logic [LBZ-1:0]             prevx_sign,
  input  logic                       prevx_avail,
  input  logic [SIDE_W-1:0]          prevx_side,
  output logic [LBZ-1:0][KS_B_W-1:0] nextx_data,
  output logic [LBZ-1:0]             nextx_sign,
  output logic                       nextx_avail,
  output logic [SIDE_W-1:0]          nextx_side,

  input  logic [LBZ-1:0][OP_W-1:0]   ksk,
  input  logic                       ksk_vld,
  output logic                       ksk_rdy,

  input  logic [OP_W-1:0]            prevy_result,
  input  logic                       prevy_avail,
  output logic [OP_W-1:0]            nexty_result,
  output logic                       nexty_avail,
  output logic [SIDE_W-1:0]          nexty_side,

  output logic                       error // KSK not available when needed
);

//===============================================
// Input Pipe
//===============================================
  logic [LBZ-1:0][KS_B_W-1:0] s0_data;
  logic [LBZ-1:0]             s0_sign;
  logic                       s0_avail;
  logic [SIDE_W-1:0]          s0_side;

  logic [LBZ-1:0][OP_W-1:0]   s0_ksk;
  logic                       s0_ksk_vld;
  logic                       s0_ksk_rdy;

  always_ff @(posedge clk)
    if (!s_rst_n) s0_avail <= 1'b0;
    else          s0_avail <= prevx_avail;

  always_ff @(posedge clk) begin
    s0_data <= prevx_data;
    s0_sign <= prevx_sign;
    s0_side <= prevx_side;
  end

  fifo_element #(
    .WIDTH          (LBZ*OP_W),
    .DEPTH          (1), // TOREVIEW
    .TYPE_ARRAY     (1),
    .DO_RESET_DATA  (0),
    .RESET_DATA_VAL (0)
  ) s0_fifo_element(
    .clk     (clk),
    .s_rst_n (s_rst_n),

    .in_data (ksk),
    .in_vld  (ksk_vld),
    .in_rdy  (ksk_rdy),

    .out_data(s0_ksk),
    .out_vld (s0_ksk_vld),
    .out_rdy (s0_ksk_rdy)
  );

//===============================================
// s0 : Multiplication
//===============================================
  logic [LBZ-1:0][OP_W-1:0] s0_mult;

  // TOREVIEW in case KS_B_W is too large
  // Is OK at 500MHz, up to KS_B_W=4 bits, OP_W=64 included.
  always_comb
    for (int z=0; z<LBZ; z=z+1) begin
      //s0_mult[z] = s0_ksk[z] * s0_data[z];
      //write it this way to improve timing. Indeed, s0_data is only a few bits.
      s0_mult[z] = '0;
      for (int i=0; i<KS_B_W; i=i+1) begin
        var [OP_W-1:0] ksk_masked;
        ksk_masked = s0_ksk[z] & {OP_W{s0_data[z][i]}};
        s0_mult[z] = s0_mult[z] + (ksk_masked << i);
      end
    end

  assign s0_ksk_rdy = s0_avail;
  // Error
  logic s0_error;

  assign s0_error = s0_avail & ~s0_ksk_vld;
  always_ff @(posedge clk)
    if (!s_rst_n) error <= 1'b0;
    else          error <= s0_error;

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      assert(!s0_error)
      else begin
        $fatal("%t > ERROR: KSK not valid when needed!",$time);
      end
    end
// pragma translate_on

//===============================================
// s1 : Addition
//===============================================
  logic [LBZ-1:0][OP_W-1:0] s1_mult;
  logic [LBZ-1:0]           s1_sign;
  logic [OP_W-1:0]          s1_add;
  logic [SIDE_W-1:0]        s1_side;
  logic                     s1_avail;

  always_ff @(posedge clk)
    if (!s_rst_n) s1_avail <= 1'b0;
    else          s1_avail <= s0_avail;

  always_ff @(posedge clk) begin
    s1_mult <= s0_mult;
    s1_side <= s0_side;
    s1_sign <= s0_sign;
  end

  // TOREVIEW if LBZ is too big
  always_comb begin
    s1_add = prevy_result;
    for (int z=0; z<LBZ; z=z+1)
      s1_add = s1_add + (s1_mult[z] ^ {OP_W{s1_sign[z]}}) + s1_sign[z];
  end

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      assert(!s1_avail || prevy_avail)
      else begin
        $fatal(1,"%t > ERROR: prevyious data is not available while needed!", $time);
      end
    end
// pragma translate_on

//===============================================
// Output Pipe
//===============================================
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      nexty_avail <= 1'b0;
      nextx_avail <= 1'b0;
    end
    else begin
      nexty_avail <= s1_avail;
      nextx_avail <= prevx_avail;
    end

  always_ff @(posedge clk) begin
    nexty_result <= s1_add;
    nexty_side   <= s1_side;
    nextx_data   <= prevx_data;
    nextx_sign   <= prevx_sign;
    nextx_side   <= prevx_side;
  end

endmodule
