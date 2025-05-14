// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : One path Read-only memory behavioral model
// ----------------------------------------------------------------------------------------------
//
// Behavioral double port ROM.
// Infers a single port ROM without write connections.
//
// Parameters :
// FILENAME          : File for initialization of the memory, values are in bits
// WIDTH             : Data width
// DEPTH             : ROM depth (number of words in ROM)
// KEEP_RD_DATA      : Read data is kept until the next read request.
// ROM_LATENCY       : ROM read latency. Should be at least 1
//
// ==============================================================================================

module rom_1R_behav #(
  parameter     FILENAME     = "",
  parameter int WIDTH        = 8,
  parameter int DEPTH        = 512,
  parameter     KEEP_RD_DATA = 0,
  parameter int ROM_LATENCY  = 1
) (
  // system interface
  input                            clk,
  input                            s_rst_n,
  // data interface
  input                            rd_en,
  input  logic [$clog2(DEPTH)-1:0] rd_add,
  output logic [        WIDTH-1:0] rd_data

);

  // ============================================================================================ //
  // Parameters
  // ============================================================================================ //
  localparam int ROM_LAT_LOCAL = ROM_LATENCY - 1;

  // ============================================================================================ //
  // RAM_1R behav
  // ============================================================================================ //
  logic [WIDTH-1:0] data_tmp;

  rom_1R_behav_core #(
    .FILENAME(FILENAME),
    .WIDTH   (WIDTH),
    .DEPTH   (DEPTH)
  ) rom_1R_behav_core (
    .clk     (clk),
    .rd_en   (rd_en),
    .rd_add  (rd_add),
    .rd_data (data_tmp)
  );

  // -------------------------------------------------------------------------------------------- //
  // Read mode
  // -------------------------------------------------------------------------------------------- //
  logic [WIDTH-1:0] datar;

  generate
    if (KEEP_RD_DATA != 0) begin : keep_rd_data_gen
      logic [WIDTH-1:0] datar_kept;
      logic             rd_en_dly;

      always_ff @(posedge clk) begin
        if (!s_rst_n) begin
          rd_en_dly <= 1'b0;
        end else begin
          rd_en_dly <= rd_en;
        end
      end

      always_ff @(posedge clk) begin
        if (rd_en_dly) datar_kept <= data_tmp;
      end

      assign datar = rd_en_dly ? data_tmp : datar_kept;

    end else begin : no_keep_rd_data_gen
      assign datar = data_tmp;
    end
  endgenerate

  // -------------------------------------------------------------------------------------------- //
  // LATENCY
  // -------------------------------------------------------------------------------------------- //
  genvar gen_i;
  generate
    if (ROM_LAT_LOCAL != 0) begin : add_ram_latency_gen

      logic [ROM_LAT_LOCAL-1:0][WIDTH-1:0] datar_sr;
      logic [ROM_LAT_LOCAL-1:0][WIDTH-1:0] datar_srD;
      logic [ROM_LAT_LOCAL-1:0]            datar_en_sr;
      logic [ROM_LAT_LOCAL-1:0]            datar_en_srD;

      assign datar_srD[0]    = datar_en_sr[0] ? datar : datar_sr[0];
      assign datar_en_srD[0] = rd_en;

      if (ROM_LAT_LOCAL > 1) begin : ram_lat_local_gt_1
        assign datar_en_srD[ROM_LAT_LOCAL-1:1] = datar_en_sr[ROM_LAT_LOCAL-2:0];
        for (gen_i = 1; gen_i < ROM_LAT_LOCAL; gen_i = gen_i + 1)
          assign datar_srD[gen_i] = datar_en_sr[gen_i] ? datar_sr[gen_i-1] : datar_sr[gen_i];
      end

      always_ff @(posedge clk)
        if (!s_rst_n) datar_en_sr <= '0;
        else datar_en_sr <= datar_en_srD;

      always_ff @(posedge clk) datar_sr <= datar_srD;

      assign rd_data = datar_sr[ROM_LAT_LOCAL-1];
    end else begin : no_add_ram_latency_gen
      assign rd_data = datar;
    end
  endgenerate

endmodule
