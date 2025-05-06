// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module enables the reading in a RAM with rdy/vld interface.
// ==============================================================================================

module ram_rd_rdy_vld #(
  parameter bit   IN_PIPE      = 1'b1,
  parameter bit   OUT_PIPE     = 1'b1,
  parameter bit   RAM_IN_PIPE  = 1'b1,
  parameter bit   RAM_OUT_PIPE = 1'b1,
  parameter int   DATA_LATENCY = 1, // RAM_LATENCY + pipes to send the cmd and get the datar outside this module
  parameter int   BUF_DEPTH    = DATA_LATENCY + 2 + RAM_IN_PIPE + RAM_OUT_PIPE, // Output buffer depth > 0
  parameter int   ADD_W        = 8,
  parameter int   DATA_W       = 32,
  parameter int   SIDE_W       = 0 // Side data size. Set to 0 if not used
)
(
    input  logic               clk,        // clock
    input  logic               s_rst_n,    // synchronous reset

    input  logic               rd_vld,
    output logic               rd_rdy,
    input  logic  [ADD_W-1:0]  rd_add,
    input  logic  [SIDE_W-1:0] rd_side,

    output logic               rd_data_vld,
    input logic                rd_data_rdy,
    output logic  [DATA_W-1:0] rd_data,
    output logic  [SIDE_W-1:0] rd_data_side,

    output logic               ram_ren,
    output logic [ADD_W-1:0]   ram_add,
    output logic [SIDE_W-1:0]  ram_side,

    input  logic [DATA_W-1:0]  ram_data,
    output logic               ram_data_en, // mainly informative, for debug
    output logic [SIDE_W-1:0]  ram_data_side
);

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int BUF_DEPTH_W = $clog2(BUF_DEPTH+1); // counts from 0 to BUF_DEPTH included
  localparam int SR_DEPTH    = DATA_LATENCY + RAM_IN_PIPE;
  localparam int BSET_W      = SIDE_W + DATA_W;

// ============================================================================================== --
// Input pipe
// ============================================================================================== --
  logic                s0_rd_vld;
  logic                s0_rd_rdy;
  logic  [ADD_W-1:0]   s0_rd_add;
  logic  [SIDE_W-1:0]  s0_rd_side;

  generate
    if (IN_PIPE) begin : gen_in_pipe
      logic [SIDE_W+ADD_W-1:0] rd_set;
      logic [SIDE_W+ADD_W-1:0] s0_rd_set;

      if (SIDE_W > 0) begin
        assign rd_set                 = {rd_side,rd_add};
        assign {s0_rd_side,s0_rd_add} = s0_rd_set;
      end
      else begin
        assign rd_set     = {rd_add};
        assign s0_rd_add  = s0_rd_set;
        assign s0_rd_side = 'x; // UNUSED
      end

      fifo_element #(
        .WIDTH          (SIDE_W+ADD_W),
        .DEPTH          (2),
        .TYPE_ARRAY     (8'h12),
        .DO_RESET_DATA  (0),
        .RESET_DATA_VAL (0)
      ) in_fifo_element (
        .clk     (clk),
        .s_rst_n (s_rst_n),

        .in_data (rd_set),
        .in_vld  (rd_vld),
        .in_rdy  (rd_rdy),

        .out_data(s0_rd_set),
        .out_vld (s0_rd_vld),
        .out_rdy (s0_rd_rdy)
      );
    end
    else begin : gen_no_in_pipe
      assign s0_rd_vld  = rd_vld;
      assign s0_rd_add  = rd_add;
      assign s0_rd_side = rd_side;
      assign rd_rdy     = s0_rd_rdy;
    end
  endgenerate

// ============================================================================================== --
// RAM read request
// ============================================================================================== --
  // Count remaining location in the buffer.
  // Send a read request only when there are free location.
  logic [BUF_DEPTH_W-1:0] buf_free_cnt;
  logic [BUF_DEPTH_W-1:0] buf_free_cntD;
  logic                   buf_free_exists;

  assign buf_free_exists = buf_free_cnt > 0;

  logic s0_ram_ren;

  assign s0_ram_ren = buf_free_exists & s0_rd_vld;
  assign s0_rd_rdy  = buf_free_exists;

  //--------------------------------
  // RAM_IN_PIPE
  //--------------------------------
  generate
    if (RAM_IN_PIPE) begin : gen_ram_in_pipe
      always_ff @(posedge clk)
        if (!s_rst_n) ram_ren <= 1'b0;
        else          ram_ren <= s0_ram_ren;
      always_ff @(posedge clk) begin
        ram_add  <= s0_rd_add;
        ram_side <= s0_rd_side;
      end
    end
    else begin : gen_no_ram_in_pipe
      assign ram_ren  = s0_ram_ren;
      assign ram_add  = s0_rd_add;
      assign ram_side = s0_rd_side;
    end
  endgenerate

// ============================================================================================== --
// Avail + Side data shift register
// ============================================================================================== --
  logic [SIDE_W-1:0] s2_side;
  logic              s2_ram_data_avail;

  //== avail
  logic [SR_DEPTH-1:0] s1_ram_data_avail_sr;
  logic [SR_DEPTH-1:0] s1_ram_data_avail_srD;

  assign s2_ram_data_avail        = s1_ram_data_avail_sr[SR_DEPTH-1];
  assign s1_ram_data_avail_srD[0] = s0_ram_ren;
  generate
    if (SR_DEPTH>1) begin
      assign s1_ram_data_avail_srD[SR_DEPTH-1:1] = s1_ram_data_avail_sr[SR_DEPTH-2:0];
    end
  endgenerate

  always_ff @(posedge clk)
    if (!s_rst_n) s1_ram_data_avail_sr <= '0;
    else          s1_ram_data_avail_sr <= s1_ram_data_avail_srD;

  //== side
  generate
    if (SIDE_W > 0) begin : gen_side_sr
      logic [SR_DEPTH-1:0][SIDE_W-1:0] s1_side_sr;
      logic [SR_DEPTH-1:0][SIDE_W-1:0] s1_side_srD;

      assign s2_side        = s1_side_sr[SR_DEPTH-1];
      assign s1_side_srD[0] = s0_rd_side;
      if (SR_DEPTH>1) begin
        assign s1_side_srD[SR_DEPTH-1:1] = s1_side_sr[SR_DEPTH-2:0];
      end
      always_ff @(posedge clk)
        s1_side_sr <= s1_side_srD;
    end
    else begin : gen_no_side_sr
      assign s2_side = 'x; // UNUSED
    end
  endgenerate

  assign ram_data_en   = s2_ram_data_avail;
  assign ram_data_side = s2_side;

// ============================================================================================== --
// RAM data : pipe
// ============================================================================================== --
  logic [DATA_W-1:0] s3_ram_data;
  logic [SIDE_W-1:0] s3_side;
  logic              s3_ram_data_avail;

  generate
    if (RAM_OUT_PIPE) begin : gen_ram_out_pipe
      always_ff @(posedge clk) begin
        s3_ram_data <= ram_data;
        s3_side     <= s2_side;
      end
      always_ff @(posedge clk)
        if (!s_rst_n) s3_ram_data_avail <= 1'b0;
        else          s3_ram_data_avail <= s2_ram_data_avail;
    end
    else begin : gen_no_ram_out_pipe
      assign s3_ram_data       = ram_data;
      assign s3_side           = s2_side;
      assign s3_ram_data_avail = s2_ram_data_avail;
    end
  endgenerate

// ============================================================================================== --
// RAM data + Buffer
// ============================================================================================== --
  logic [BSET_W-1:0] buf_in_set;
  logic              buf_in_vld;
  logic              buf_in_rdy;
  logic [BSET_W-1:0] buf_out_set;
  logic              buf_out_vld;
  logic              buf_out_rdy;

  assign buf_in_vld = s3_ram_data_avail;
  generate
    if (SIDE_W>0) begin : gen_buf_in_side
      assign buf_in_set = {s3_side,s3_ram_data};
    end
    else begin : gen_no_buf_in_side
      assign buf_in_set = s3_ram_data;
    end
  endgenerate

  fifo_reg #(
    .WIDTH       (BSET_W),
    .DEPTH       (BUF_DEPTH),
    .LAT_PIPE_MH ({1'b0,1'b1})
  ) buffer_fifo_reg (
    .clk     (clk),
    .s_rst_n (s_rst_n),

    .in_data (buf_in_set),
    .in_vld  (buf_in_vld),
    .in_rdy  (buf_in_rdy),

    .out_data(buf_out_set),
    .out_vld (buf_out_vld),
    .out_rdy (buf_out_rdy)
  );

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      if (buf_in_vld) begin
        assert(buf_in_rdy)
        else begin
          $fatal(1,"%t > ERROR: buffer_fifo_reg is not ready when needed!", $time);
        end
      end
    end
// pragma translate_on

// ============================================================================================== --
// Output pipe
// ============================================================================================== --
  generate
    if (OUT_PIPE) begin : gen_out_pipe
      logic [BSET_W-1:0] rd_data_set;
      fifo_element #(
        .WIDTH          (BSET_W),
        .DEPTH          (2),
        .TYPE_ARRAY     (8'h12),
        .DO_RESET_DATA  (0),
        .RESET_DATA_VAL (0)
      ) in_fifo_element (
        .clk     (clk),
        .s_rst_n (s_rst_n),

        .in_data (buf_out_set),
        .in_vld  (buf_out_vld),
        .in_rdy  (buf_out_rdy),

        .out_data(rd_data_set),
        .out_vld (rd_data_vld),
        .out_rdy (rd_data_rdy)
      );

      if (SIDE_W > 0) begin
        assign {rd_data_side,rd_data} = rd_data_set;
      end
      else begin
        assign rd_data      = rd_data_set;
        assign rd_data_side = 'x; // UNUSED
      end
    end
    else begin : gen_no_out_pipe
      assign rd_data_vld = buf_out_vld;
      assign buf_out_rdy = rd_data_rdy;

      if (SIDE_W > 0) begin
        assign {rd_data_side,rd_data} = buf_out_set;
      end
      else begin
        assign rd_data      = buf_out_set;
        assign rd_data_side = 'x; // UNUSED
      end
    end
  endgenerate

// ============================================================================================== --
// Counter
// ============================================================================================== --
  assign buf_free_cntD = s0_ram_ren && !(buf_out_vld && buf_out_rdy) ? buf_free_cnt - 1:
                         !s0_ram_ren && (buf_out_vld && buf_out_rdy) ? buf_free_cnt + 1: buf_free_cnt;

  always_ff @(posedge clk)
    if (!s_rst_n) buf_free_cnt <= BUF_DEPTH;
    else          buf_free_cnt <= buf_free_cntD;

endmodule
