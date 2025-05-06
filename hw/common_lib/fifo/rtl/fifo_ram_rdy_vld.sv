// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// FIFO using a RAM.
// Ready/valid interface is used.
// in_rdy = 0 : the FIFO is full.
// out_vld = 0 : the FIFO is empty.
// FIFO with 1 cycle output latency.
//
// Parameters:
//  WIDTH : data width
//  DEPTH : RAM depth
//  RAM_LATENCY : RAM read latency
//  ALMOST_FULL_REMAIN : If the number of remaining locations in RAM is less or equal to
//                        ALMOST_FULL_REMAIN then the signal almost_full is 1.
//
//  Note that this FIFO total capacity is DEPTH + RAM_LATENCY + 1.
//
// ==============================================================================================

module fifo_ram_rdy_vld #(
  parameter int               WIDTH       = 32,
  parameter int               DEPTH       = 256,
  parameter int               RAM_LATENCY = 1,
  parameter int               ALMOST_FULL_REMAIN = 1
) (
  input              clk,     // clock
  input              s_rst_n, // synchronous reset

  input  [WIDTH-1:0] in_data,
  input              in_vld,
  output             in_rdy,

  output [WIDTH-1:0] out_data,
  output             out_vld,
  input              out_rdy,

  output             almost_full
);

  // ============================================================================================== --
  // localparam
  // ============================================================================================== --
  localparam int DEPTH_W   = $clog2(DEPTH);
  localparam int BUF_DEPTH = RAM_LATENCY + 1;
  localparam int LOC_NB    = RAM_LATENCY + BUF_DEPTH;
  localparam int LOC_W     = $clog2(LOC_NB);

  // ============================================================================================== --
  // fifo_ram_rdy_vld
  // ============================================================================================== --
  // ---------------------------------------------------------------------------------------------- --
  // Pointers
  // ---------------------------------------------------------------------------------------------- --
  // pointers
  logic [  DEPTH_W:0] rp;
  logic [  DEPTH_W:0] wp;

  logic [DEPTH_W-1:0] rp_lsb;
  logic [DEPTH_W-1:0] wp_lsb;
  logic               rp_msb;
  logic               wp_msb;
  logic               is_full;
  logic               is_empty;
  logic               rden;
  logic               wren;

  assign is_empty = rp == wp;
  assign is_full  = (rp_msb != wp_msb) & (rp_lsb == wp_lsb);

  generate
    if (2 ** DEPTH_W == DEPTH) begin : depth_is_power_of_2_gen
      logic [DEPTH_W:0] rpD;
      logic [DEPTH_W:0] wpD;

      assign rpD = rden ? rp + 1 : rp;
      assign wpD = wren  ? wp + 1 : wp;

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

      assign rp_lsbD = rden ? (rp_lsb == DEPTH - 1) ? 0 : rp_lsb + 1 : rp_lsb;
      assign rp_msbD = (rden && (rp_lsb == DEPTH - 1)) ? ~rp_msb : rp_msb;
      assign wp_lsbD = wren ? (wp_lsb == DEPTH - 1) ? 0 : wp_lsb + 1 : wp_lsb;
      assign wp_msbD = (wren && (wp_lsb == DEPTH - 1)) ? ~wp_msb : wp_msb;

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
  endgenerate

  // ---------------------------------------------------------------------------------------------- --
  // RAM instance
  // ---------------------------------------------------------------------------------------------- --
  logic               ram_rd_en;
  logic [DEPTH_W-1:0] ram_rd_add;
  logic [WIDTH-1:0]   ram_rd_data;

  logic               ram_wr_en;
  logic [DEPTH_W-1:0] ram_wr_add;
  logic [WIDTH-1:0]   ram_wr_data;

  assign ram_rd_en   = rden;
  assign ram_rd_add  = rp_lsb;

  assign ram_wr_en   = wren;
  assign ram_wr_add  = wp_lsb;
  assign ram_wr_data = in_data;

  ram_wrapper_1R1W #(
    .WIDTH             (WIDTH),
    .DEPTH             (DEPTH),
    .RD_WR_ACCESS_TYPE (1), // Note that here, there won't be access conflict.
    .KEEP_RD_DATA      (0), // Output buffer is present for that.
    .RAM_LATENCY       (RAM_LATENCY)
  )
  ram
  (
    .clk     (clk),
    .s_rst_n (s_rst_n),

    .rd_en   (ram_rd_en),
    .rd_add  (ram_rd_add),
    .rd_data (ram_rd_data),
    
    .wr_en   (ram_wr_en),
    .wr_add  (ram_wr_add),
    .wr_data (ram_wr_data)
  );

  // ---------------------------------------------------------------------------------------------- --
  // Output buffer
  // ---------------------------------------------------------------------------------------------- --
  // To ease the P&R, the out_data comes from a register.
  // We need additional RAM_LATENCY registers to absorb the RAM read latency.
  // We also want to have the smallest latency as possible. This means, when the FIFO is empty, when
  // an input is valid, it will be available at the output 1 cycle later.
  logic [BUF_DEPTH-1:0][WIDTH-1:0] buf_data;
  logic [BUF_DEPTH:0]  [WIDTH-1:0] buf_data_ext;
  logic [BUF_DEPTH-1:0][WIDTH-1:0] buf_dataD;
  logic [BUF_DEPTH-1:0]            buf_en;
  logic [BUF_DEPTH-1:0]            buf_enD;
  logic [BUF_DEPTH:0]              buf_en_ext;
  logic                            buf_in_avail;
  logic [WIDTH-1:0]                buf_in_data;
  logic [BUF_DEPTH-1:0]            buf_in_wren_1h;
  logic [BUF_DEPTH-1:0]            buf_in_wren_1h_tmp;
  logic [BUF_DEPTH-1:0]            buf_in_wren_1h_tmp2;
  logic                            buf_shift;

  assign buf_data_ext        = {{WIDTH{1'bx}}, buf_data}; // Add 1 element to avoid warning, while
                                                          // selecting out of range.
  assign buf_en_ext          = {1'b0, buf_en};
  assign buf_in_wren_1h_tmp  = buf_shift ? {1'b0, buf_en[BUF_DEPTH-1:1]} : buf_en;
  // Find first bit = 0
  assign buf_in_wren_1h_tmp2 = buf_in_wren_1h_tmp ^ {buf_in_wren_1h_tmp[BUF_DEPTH-2:0], 1'b1};
  assign buf_in_wren_1h      = buf_in_wren_1h_tmp2 & {BUF_DEPTH{buf_in_avail}};

  always_comb begin
    for (int i = 0; i<BUF_DEPTH; i=i+1) begin
      buf_dataD[i] = buf_in_wren_1h[i] ? buf_in_data :
                     buf_shift         ? buf_data_ext[i+1] : buf_data[i];
      buf_enD[i]   = buf_in_wren_1h[i] | (buf_shift ? buf_en_ext[i+1] : buf_en[i]);
    end
  end

  always_ff @(posedge clk)
    if (!s_rst_n) buf_en <= '0;
    else          buf_en <= buf_enD;

  always_ff @(posedge clk) begin
    buf_data <= buf_dataD;
  end

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      if (buf_in_avail) begin
        assert(buf_in_wren_1h != 0)
        else $fatal(1, "> ERROR: FIFO output buffer overflow!");
      end
    end
// pragma translate_on

  // ---------------------------------------------------------------------------------------------- --
  // Read
  // ---------------------------------------------------------------------------------------------- --
  // Read in RAM when it is not empty and when there is a free location in the buffer,
  // or a location currently being freed.
  logic [RAM_LATENCY-1:0] ram_data_avail_dly;
  logic [RAM_LATENCY-1:0] ram_data_avail_dlyD;
  logic [LOC_W-1:0]       data_cnt;
  logic [LOC_NB-1:0]      data_en;

  assign ram_data_avail_dlyD[0] = rden;
  generate
    if (RAM_LATENCY > 1) begin : ram_latency_gt_1_gen
      assign ram_data_avail_dlyD[RAM_LATENCY-1:1] = ram_data_avail_dly[RAM_LATENCY-2:0];
    end
  endgenerate

  always_ff @(posedge clk)
    if (!s_rst_n) ram_data_avail_dly <= '0;
    else          ram_data_avail_dly <= ram_data_avail_dlyD;

  assign data_en =  {buf_en, ram_data_avail_dly};
  always_comb begin
    logic [LOC_W-1:0] cnt;
    cnt = '0;
    for (int i=0; i<LOC_NB; i=i+1) begin
      cnt = cnt + data_en[i];
    end
    data_cnt = cnt;
  end

  assign rden = ~is_empty & (out_rdy | (data_cnt < BUF_DEPTH));

  // ---------------------------------------------------------------------------------------------- --
  // Write
  // ---------------------------------------------------------------------------------------------- --
  // If the RAM is empty, no pending reading, and free location in the output buffer,
  // write directly the input in the buffer.
  logic store_in_buffer;

  assign store_in_buffer = is_empty & (ram_data_avail_dly == '0)
                           & ((buf_en != {BUF_DEPTH{1'b1}}) | buf_shift);

  assign wren = in_vld & ~is_full & ~store_in_buffer;

  assign buf_in_avail = (in_vld & store_in_buffer) | ram_data_avail_dly[RAM_LATENCY-1];
  assign buf_in_data  = ram_data_avail_dly[RAM_LATENCY-1] ? ram_rd_data : in_data;

  // ---------------------------------------------------------------------------------------------- --
  // Ready / Valid
  // ---------------------------------------------------------------------------------------------- --
  assign in_rdy    = ~is_full;
  assign out_vld   = buf_en[0];
  assign out_data  = buf_data[0];
  assign buf_shift = out_rdy & out_vld;

  // ---------------------------------------------------------------------------------------------- --
  // Almost full
  // ---------------------------------------------------------------------------------------------- --
  logic             rp_msb2;
  logic             wp_msb2;
  logic [DEPTH_W:0] free_loc_cnt;

  assign rp_msb2 = ~(rp_msb ^ wp_msb);
  assign wp_msb2 = 1'b0;
  assign free_loc_cnt = {rp_msb2, rp_lsb} - {wp_msb2, wp_lsb};

  assign almost_full = free_loc_cnt <= ALMOST_FULL_REMAIN;

endmodule
