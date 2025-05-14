// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Two path Read-only memory behavioral model
// ----------------------------------------------------------------------------------------------
//
// Behavioral double port ROM.
// Infers a dual port ROM without write connections.
//
// Parameters :
// FILENAME          : Path for initialization of the memory, values are in bits
// WIDTH             : Data width
// DEPTH             : ROM depth (number of words in ROM)
// KEEP_RD_DATA      : Read data is kept until the next read request.
// ROM_LATENCY       : ROM read latency. Should be at least 1
//
// ==============================================================================================

module rom_2R_behav #(
  parameter     FILENAME     = "",
  parameter int WIDTH        = 8,
  parameter int DEPTH        = 512,
  parameter     KEEP_RD_DATA = 0,
  parameter int ROM_LATENCY  = 1
) (
  // system interface
  input                            clk,
  input                            s_rst_n,
  // data interface a
  input                            a_rd_en,
  input  logic [$clog2(DEPTH)-1:0] a_rd_add,
  output logic [        WIDTH-1:0] a_rd_data,
  // data interface b
  input                            b_rd_en,
  input  logic [$clog2(DEPTH)-1:0] b_rd_add,
  output logic [        WIDTH-1:0] b_rd_data

);

  // ============================================================================================ //
  // Parameters
  // ============================================================================================ //
  localparam int ROM_LAT_LOCAL = ROM_LATENCY - 1;

  // ============================================================================================ //
  // RAM_1R behav
  // ============================================================================================ //
  logic [1:0][WIDTH-1:0] datar_tmp;

  rom_2R_behav_core #(
    .FILENAME (FILENAME),
    .WIDTH    (WIDTH),
    .DEPTH    (DEPTH)
  ) rom_2R_behav_core (
    .clk      (clk),
    // data interface a
    .a_rd_en  (a_rd_en),
    .a_rd_add (a_rd_add),
    .a_rd_data(datar_tmp[0]),
    // data interface b
    .b_rd_en  (b_rd_en),
    .b_rd_add (b_rd_add),
    .b_rd_data(datar_tmp[1])
  );

  // -------------------------------------------------------------------------------------------- //
  // Read mode
  // -------------------------------------------------------------------------------------------- //
  logic [1:0][WIDTH-1:0] datar;
  logic [1:0]            rd_en_dly;

  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      rd_en_dly <= 0;
    end
    else begin
      rd_en_dly <= {b_rd_en, a_rd_en};
    end
  end

  generate
    if (KEEP_RD_DATA != 0) begin : keep_rd_data_gen
      logic [1:0][WIDTH-1:0] datar_kept;

      always_ff @(posedge clk) begin
        for (int i = 0; i < 2; i = i + 1) begin
          if (rd_en_dly[i]) begin
            datar_kept[i] <= datar_tmp[i];
          end
        end
      end

      always_comb begin
        for (int i = 0; i < 2; i = i + 1) begin
          datar[i] = rd_en_dly[i] ? datar_tmp[i] : datar_kept[i];
        end
      end
    end else begin : no_keep_rd_data_gen
      assign datar[0] = datar_tmp[0];
      assign datar[1] = datar_tmp[1];
    end
  endgenerate

  generate
    if (ROM_LAT_LOCAL != 0) begin : add_ram_latency_gen

      logic [ROM_LAT_LOCAL-1:0][1:0][WIDTH-1:0] datar_sr;
      logic [ROM_LAT_LOCAL-1:0][1:0][WIDTH-1:0] datar_srD;

      assign datar_srD[0] = datar;

      if (ROM_LAT_LOCAL > 1) begin : ram_lat_local_gt_1
        assign datar_srD[ROM_LAT_LOCAL-1:1] = datar_sr[ROM_LAT_LOCAL-2:0];
      end

      always_ff @(posedge clk) begin
        datar_sr <= datar_srD;
      end

      assign a_rd_data = datar_sr[ROM_LAT_LOCAL-1][0];
      assign b_rd_data = datar_sr[ROM_LAT_LOCAL-1][1];
    end else begin : no_add_ram_latency_gen
      assign a_rd_data = datar[0];
      assign b_rd_data = datar[1];
    end
  endgenerate

endmodule
