// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Behavioral RAM : 1R1W RAM.
//
// Parameters :
// WIDTH             : Data width
// DEPTH             : RAM depth (number of words in RAM)
// RD_WR_ACCESS_TYPE : Behavior when there is a read and write access conflict.
//                     0 : output 'X'
//                     1 : Read old value - BRAM default bahaviour
//                     2 : Read new value
// KEEP_RD_DATA      : Read data is kept until the next read request.
// RAM_LATENCY       : RAM read latency. Should be at least 1
//
// ==============================================================================================

module ram_1R1W_behav #(
  parameter int WIDTH             = 8,
  parameter int DEPTH             = 512,
  parameter int RD_WR_ACCESS_TYPE = 0,
  parameter bit KEEP_RD_DATA      = 0,
  parameter int RAM_LATENCY       = 1
)
(
  input                     clk,        // clock
  input                     s_rst_n,    // synchronous reset

  // Read port
  input                     rd_en,
  input [$clog2(DEPTH)-1:0] rd_add,
  output [WIDTH-1:0]        rd_data, // available RAM_LATENCY cycles after rd_en

  // Write port
  input                     wr_en,
  input [$clog2(DEPTH)-1:0] wr_add,
  input [WIDTH-1:0]         wr_data
);

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int RD_WR_ACCESS_TYPE_CONFLICT = 0;
  localparam int RD_WR_ACCESS_TYPE_READ_OLD = 1;
  localparam int RD_WR_ACCESS_TYPE_READ_NEW = 2;

  localparam int RAM_LAT_LOCAL = RAM_LATENCY - 1;
  localparam int RAM_LAT_IN  = RAM_LAT_LOCAL / 2;
  localparam int RAM_LAT_OUT = (RAM_LAT_LOCAL+1)/2;

// ============================================================================================== --
// Check parameter
// ============================================================================================== --
// pragma translate_off
  initial begin
    assert (RD_WR_ACCESS_TYPE == RD_WR_ACCESS_TYPE_CONFLICT
        || RD_WR_ACCESS_TYPE == RD_WR_ACCESS_TYPE_READ_OLD
        || RD_WR_ACCESS_TYPE == RD_WR_ACCESS_TYPE_READ_NEW)
    else $error("> ERROR: Unsupported RAM access type : %d", RD_WR_ACCESS_TYPE);
  end
// pragma translate_on

// ============================================================================================== --
// Input pipe
// ============================================================================================== --
  logic                     in_rd_en;
  logic [$clog2(DEPTH)-1:0] in_rd_add;

  logic                     in_wr_en;
  logic [$clog2(DEPTH)-1:0] in_wr_add;
  logic [WIDTH-1:0]         in_wr_data;

  generate
    if (RAM_LAT_IN > 0) begin : gen_in_pip
      logic [RAM_LAT_IN-1:0]                    in_rd_en_sr;
      logic [RAM_LAT_IN-1:0][$clog2(DEPTH)-1:0] in_rd_add_sr;
      logic [RAM_LAT_IN-1:0]                    in_wr_en_sr;
      logic [RAM_LAT_IN-1:0][$clog2(DEPTH)-1:0] in_wr_add_sr;
      logic [RAM_LAT_IN-1:0][WIDTH-1:0]         in_wr_data_sr;

      logic [RAM_LAT_IN-1:0]                    in_rd_en_srD;
      logic [RAM_LAT_IN-1:0][$clog2(DEPTH)-1:0] in_rd_add_srD;
      logic [RAM_LAT_IN-1:0]                    in_wr_en_srD;
      logic [RAM_LAT_IN-1:0][$clog2(DEPTH)-1:0] in_wr_add_srD;
      logic [RAM_LAT_IN-1:0][WIDTH-1:0]         in_wr_data_srD;

      assign in_rd_en   = in_rd_en_sr[RAM_LAT_IN-1];
      assign in_rd_add  = in_rd_add_sr[RAM_LAT_IN-1];
      assign in_wr_en   = in_wr_en_sr[RAM_LAT_IN-1];
      assign in_wr_add  = in_wr_add_sr[RAM_LAT_IN-1];
      assign in_wr_data = in_wr_data_sr[RAM_LAT_IN-1];

      assign in_rd_en_srD[0]   = rd_en;
      assign in_rd_add_srD[0]  = rd_add;
      assign in_wr_en_srD[0]   = wr_en;
      assign in_wr_add_srD[0]  = wr_add;
      assign in_wr_data_srD[0] = wr_data;

      if (RAM_LAT_IN > 1) begin : gen_ram_lat_in_gt_1
        assign in_rd_en_srD[RAM_LAT_IN-1:1]   = in_rd_en_sr[RAM_LAT_IN-2:0];
        assign in_rd_add_srD[RAM_LAT_IN-1:1]  = in_rd_add_sr[RAM_LAT_IN-2:0];
        assign in_wr_en_srD[RAM_LAT_IN-1:1]   = in_wr_en_sr[RAM_LAT_IN-2:0];
        assign in_wr_add_srD[RAM_LAT_IN-1:1]  = in_wr_add_sr[RAM_LAT_IN-2:0];
        assign in_wr_data_srD[RAM_LAT_IN-1:1] = in_wr_data_sr[RAM_LAT_IN-2:0];
      end

      always_ff @(posedge clk)
        if (!s_rst_n) begin
          in_rd_en_sr <= '0;
          in_wr_en_sr <= '0;
        end
        else begin
          in_rd_en_sr <= in_rd_en_srD;
          in_wr_en_sr <= in_wr_en_srD;
        end

      always_ff @(posedge clk) begin
        in_rd_add_sr   <= in_rd_add_srD;
        in_wr_add_sr   <= in_wr_add_srD;
        in_wr_data_sr  <= in_wr_data_srD;
      end
    end
    else begin : gen_no_in_pipe
      assign in_rd_en   = rd_en;
      assign in_rd_add  = rd_add;
      assign in_wr_en   = wr_en;
      assign in_wr_add  = wr_add;
      assign in_wr_data = wr_data;
    end
  endgenerate
// ============================================================================================== --
// ram_1R1W_behav
// ============================================================================================== --
// ---------------------------------------------------------------------------------------------- --
// RAM 1R1W core
// ---------------------------------------------------------------------------------------------- --
  // Note :
  //  - If access conflict will read the old value.
  //  - Has 1 cycle of latency
  logic [WIDTH-1:0] datar_tmp;
  ram_1R1W_behav_core #(
    .WIDTH (WIDTH),
    .DEPTH (DEPTH)
  )
  ram_1R1W_core
  (
    .clk    (clk),

    .rd_en  (in_rd_en),
    .rd_add (in_rd_add),
    .rd_data(datar_tmp),

    .wr_en  (in_wr_en),
    .wr_add (in_wr_add),
    .wr_data(in_wr_data)
  );

// ---------------------------------------------------------------------------------------------- --
// Data management
// ---------------------------------------------------------------------------------------------- --
  logic [WIDTH-1:0] datar_tmp2;

  generate
    if (RD_WR_ACCESS_TYPE == RD_WR_ACCESS_TYPE_READ_OLD) begin : rd_wr_access_type_read_old_gen
      assign datar_tmp2 = datar_tmp;
    end
    else begin : no_rd_wr_access_type_read_old_gen
      logic             access_conflict;
      logic             access_conflictD;

      assign access_conflictD = in_wr_en & in_rd_en & (in_wr_add == in_rd_add);

      always_ff @(posedge clk)
        if (!s_rst_n) begin
          access_conflict <= 1'b0;
        end
        else begin
          access_conflict <= access_conflictD;
        end

      if (RD_WR_ACCESS_TYPE == RD_WR_ACCESS_TYPE_CONFLICT) begin : rd_wr_access_type_conflict_gen
        assign datar_tmp2 = access_conflict ? {WIDTH{1'bx}} : datar_tmp;
      end
      else if (RD_WR_ACCESS_TYPE == RD_WR_ACCESS_TYPE_READ_NEW) begin : rd_wr_access_type_read_new_gen
        logic[WIDTH-1:0]  wr_data_dly;
        always_ff @(posedge clk)
          wr_data_dly <= in_wr_data;
        assign datar_tmp2 = access_conflict ? wr_data_dly : datar_tmp;
      end
    end
  endgenerate

// ---------------------------------------------------------------------------------------------- --
// datar
// ---------------------------------------------------------------------------------------------- --
  logic [WIDTH-1:0] datar;
  generate
    if (KEEP_RD_DATA != 0) begin : keep_rd_data_gen
      logic [WIDTH-1:0] datar_kept;
      logic             rd_en_dly;

      always_ff @(posedge clk)
        if (!s_rst_n) begin
          rd_en_dly       <= 1'b0;
        end
        else begin
          rd_en_dly       <= in_rd_en;
        end

      always_ff @(posedge clk) begin
        if (rd_en_dly)
          datar_kept <= datar_tmp2;
      end

      assign datar = rd_en_dly ? datar_tmp2 : datar_kept;
    end
    else begin : no_keep_rd_data_gen
      assign datar = datar_tmp2;
    end
  endgenerate

  genvar gen_i;
  generate
    if (RAM_LAT_OUT != 0) begin : add_ram_latency_gen

      logic [RAM_LAT_OUT-1:0][WIDTH-1:0] datar_sr;
      logic [RAM_LAT_OUT-1:0][WIDTH-1:0] datar_srD;
      logic [RAM_LAT_OUT-1:0]            datar_en_sr;
      logic [RAM_LAT_OUT-1:0]            datar_en_srD;

      assign datar_srD[0]    = datar_en_sr[0] ? datar : datar_sr[0];
      assign datar_en_srD[0] = in_rd_en;

      if (RAM_LAT_OUT > 1) begin : ram_lat_out_gt_1
        assign datar_en_srD[RAM_LAT_OUT-1:1] = datar_en_sr[RAM_LAT_OUT-2:0];
        for (gen_i=1; gen_i<RAM_LAT_OUT; gen_i=gen_i+1)
          assign datar_srD[gen_i] = datar_en_sr[gen_i] ? datar_sr[gen_i-1] : datar_sr[gen_i];
      end

      always_ff @(posedge clk)
        if (!s_rst_n) datar_en_sr <= '0;
        else          datar_en_sr <= datar_en_srD;

      always_ff @(posedge clk)
        datar_sr <= datar_srD;

      assign rd_data = datar_sr[RAM_LAT_OUT-1];
    end
    else begin : no_add_ram_latency_gen
      assign rd_data = datar;
    end
  endgenerate
endmodule

