// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Behavioral RAM : 2RW RAM.
//
// Parameters :
// WIDTH             : Data width
// DEPTH             : RAM depth (number of words in RAM)
// RD_WR_ACCESS_TYPE : Behavior when there is a read and write access conflict.
//                     0 : output 'X'
//                     1 : Read old value - BRAM default behaviour
//                     2 : Read new value
// KEEP_RD_DATA      : Read data is kept until the next read request.
// RAM_LATENCY       : RAM read latency. Should be at least 1
//
// ==============================================================================================

module ram_2RW_behav #(
  parameter int WIDTH             = 8,
  parameter int DEPTH             = 512,
  parameter int RD_WR_ACCESS_TYPE = 0,
  parameter bit KEEP_RD_DATA      = 0,
  parameter int RAM_LATENCY       = 1
)
(
  input                            clk,        // clock
  input                            s_rst_n,    // synchronous reset

  // Port a
  input  logic                     a_en,
  input  logic                     a_wen,
  input  logic [$clog2(DEPTH)-1:0] a_add,
  input  logic [WIDTH-1:0]         a_wr_data,
  output logic [WIDTH-1:0]         a_rd_data,

  // Port b
  input  logic                     b_en,
  input  logic                     b_wen,
  input  logic [$clog2(DEPTH)-1:0] b_add,
  input  logic [WIDTH-1:0]         b_wr_data,
  output logic [WIDTH-1:0]         b_rd_data
);

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int RD_WR_ACCESS_TYPE_CONFLICT = 0;
  localparam int RD_WR_ACCESS_TYPE_READ_OLD = 1;
  localparam int RD_WR_ACCESS_TYPE_READ_NEW = 2;

  localparam int RAM_LAT_LOCAL = RAM_LATENCY - 1;
  localparam int RAM_LAT_IN    = RAM_LAT_LOCAL / 2;
  localparam int RAM_LAT_OUT   = (RAM_LAT_LOCAL + 1)/2;

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
// Input Pipe
// ============================================================================================== --
  logic                     in_a_en;
  logic                     in_a_wen;
  logic [$clog2(DEPTH)-1:0] in_a_add;
  logic [WIDTH-1:0]         in_a_wr_data;
  logic                     in_b_en;
  logic                     in_b_wen;
  logic [$clog2(DEPTH)-1:0] in_b_add;
  logic [WIDTH-1:0]         in_b_wr_data;

  generate
    if (RAM_LAT_IN > 0) begin : gen_in_pipe
      logic [RAM_LAT_IN-1:0]                    in_a_en_sr;
      logic [RAM_LAT_IN-1:0]                    in_a_wen_sr;
      logic [RAM_LAT_IN-1:0][$clog2(DEPTH)-1:0] in_a_add_sr;
      logic [RAM_LAT_IN-1:0][WIDTH-1:0]         in_a_wr_data_sr;
      logic [RAM_LAT_IN-1:0]                    in_b_en_sr;
      logic [RAM_LAT_IN-1:0]                    in_b_wen_sr;
      logic [RAM_LAT_IN-1:0][$clog2(DEPTH)-1:0] in_b_add_sr;
      logic [RAM_LAT_IN-1:0][WIDTH-1:0]         in_b_wr_data_sr;

      logic [RAM_LAT_IN-1:0]                    in_a_en_srD;
      logic [RAM_LAT_IN-1:0]                    in_a_wen_srD;
      logic [RAM_LAT_IN-1:0][$clog2(DEPTH)-1:0] in_a_add_srD;
      logic [RAM_LAT_IN-1:0][WIDTH-1:0]         in_a_wr_data_srD;
      logic [RAM_LAT_IN-1:0]                    in_b_en_srD;
      logic [RAM_LAT_IN-1:0]                    in_b_wen_srD;
      logic [RAM_LAT_IN-1:0][$clog2(DEPTH)-1:0] in_b_add_srD;
      logic [RAM_LAT_IN-1:0][WIDTH-1:0]         in_b_wr_data_srD;

     assign in_a_en      = in_a_en_sr[RAM_LAT_IN-1];
     assign in_a_wen     = in_a_wen_sr[RAM_LAT_IN-1];
     assign in_a_add     = in_a_add_sr[RAM_LAT_IN-1];
     assign in_a_wr_data = in_a_wr_data_sr[RAM_LAT_IN-1];
     assign in_b_en      = in_b_en_sr[RAM_LAT_IN-1];
     assign in_b_wen     = in_b_wen_sr[RAM_LAT_IN-1];
     assign in_b_add     = in_b_add_sr[RAM_LAT_IN-1];
     assign in_b_wr_data = in_b_wr_data_sr[RAM_LAT_IN-1];

     assign in_a_en_srD[0]      = a_en;
     assign in_a_wen_srD[0]     = a_wen;
     assign in_a_add_srD[0]     = a_add;
     assign in_a_wr_data_srD[0] = a_wr_data;
     assign in_b_en_srD[0]      = b_en;
     assign in_b_wen_srD[0]     = b_wen;
     assign in_b_add_srD[0]     = b_add;
     assign in_b_wr_data_srD[0] = b_wr_data;

    if (RAM_LAT_IN > 1) begin : gen_rma_lat_in_gt_1
      assign in_a_en_srD[RAM_LAT_IN-1:1]      = in_a_en_sr[RAM_LAT_IN-2:0];
      assign in_a_wen_srD[RAM_LAT_IN-1:1]     = in_a_wen_sr[RAM_LAT_IN-2:0];
      assign in_a_add_srD[RAM_LAT_IN-1:1]     = in_a_add_sr[RAM_LAT_IN-2:0];
      assign in_a_wr_data_srD[RAM_LAT_IN-1:1] = in_a_wr_data_sr[RAM_LAT_IN-2:0];
      assign in_b_en_srD[RAM_LAT_IN-1:1]      = in_b_en_sr[RAM_LAT_IN-2:0];
      assign in_b_wen_srD[RAM_LAT_IN-1:1]     = in_b_wen_sr[RAM_LAT_IN-2:0];
      assign in_b_add_srD[RAM_LAT_IN-1:1]     = in_b_add_sr[RAM_LAT_IN-2:0];
      assign in_b_wr_data_srD[RAM_LAT_IN-1:1] = in_b_wr_data_sr[RAM_LAT_IN-2:0];
    end

    always_ff @(posedge clk)
      if (!s_rst_n) begin
        in_a_en_sr  <= '0;
        in_a_wen_sr <= '0;
        in_b_en_sr  <= '0;
        in_b_wen_sr <= '0;
      end
      else begin
        in_a_en_sr  <= in_a_en_srD ;
        in_a_wen_sr <= in_a_wen_srD;
        in_b_en_sr  <= in_b_en_srD ;
        in_b_wen_sr <= in_b_wen_srD;
      end

      always_ff @(posedge clk) begin
        in_a_add_sr     <= in_a_add_srD;
        in_a_wr_data_sr <= in_a_wr_data_srD;
        in_b_add_sr     <= in_b_add_srD;
        in_b_wr_data_sr <= in_b_wr_data_srD;
      end
   end
    else begin : gen_no_in_pipe
      assign in_a_en      = a_en;
      assign in_a_wen     = a_wen;
      assign in_a_add     = a_add;
      assign in_a_wr_data = a_wr_data;
      assign in_b_en      = b_en;
      assign in_b_wen     = b_wen;
      assign in_b_add     = b_add;
      assign in_b_wr_data = b_wr_data;
    end
  endgenerate

// ============================================================================================== --
// ram_2RW_behav
// ============================================================================================== --
// ---------------------------------------------------------------------------------------------- --
// RAM 2RW core
// ---------------------------------------------------------------------------------------------- --
  // Note :
  //  - If access conflict will read the old value.
  //  - Has 1 cycle of latency
  logic [1:0][WIDTH-1:0] datar_tmp;
  ram_2RW_behav_core #(
    .WIDTH (WIDTH),
    .DEPTH (DEPTH)
  )
  ram_2RW_core
  (
    .clk         (clk),

    .a_en        (in_a_en     ),
    .a_wen       (in_a_wen    ),
    .a_add       (in_a_add    ),
    .a_wr_data   (in_a_wr_data),
    .a_rd_data   (datar_tmp[0]),

    .b_en        (in_b_en     ),
    .b_wen       (in_b_wen    ),
    .b_add       (in_b_add    ),
    .b_wr_data   (in_b_wr_data),
    .b_rd_data   (datar_tmp[1])
  );

// ---------------------------------------------------------------------------------------------- --
// Data management
// ---------------------------------------------------------------------------------------------- --
  logic [1:0] rd_access_conflict;
  logic [1:0] rd_access_conflictD;
  logic [1:0][WIDTH-1:0]  wr_data_dly;
  logic [1:0] rd_en_dly;
  logic [1:0][WIDTH-1:0] datar_tmp2;

  assign rd_access_conflictD[0] = in_a_en & in_b_en & ~in_a_wen & in_b_wen & (in_a_add == in_b_add);
  assign rd_access_conflictD[1] = in_a_en & in_b_en & in_a_wen & ~in_b_wen & (in_a_add == in_b_add);

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      rd_access_conflict <= '0;
      rd_en_dly          <= '0;
    end
    else begin
      rd_access_conflict <= rd_access_conflictD;
      rd_en_dly          <= {in_b_en & ~in_b_wen, in_a_en & ~in_a_wen};
    end

  always_ff @(posedge clk)
    wr_data_dly <= {in_b_wr_data, in_a_wr_data};

  generate
    if (RD_WR_ACCESS_TYPE == RD_WR_ACCESS_TYPE_CONFLICT) begin
      always_comb begin
        for (int i=0; i<2; i=i+1) begin
          datar_tmp2[i] = rd_access_conflict[i] ? {WIDTH{1'bx}} : datar_tmp[i];
        end
      end
    end
    else if (RD_WR_ACCESS_TYPE == RD_WR_ACCESS_TYPE_READ_OLD) begin
      assign datar_tmp2 = datar_tmp;
    end
    else if (RD_WR_ACCESS_TYPE == RD_WR_ACCESS_TYPE_READ_NEW) begin
      always_comb begin
        for (int i=0; i<2; i=i+1) begin
          int j;
          j = (i==0) ? 1 : 0; // the other port
          datar_tmp2[i] = rd_access_conflict[i] ? wr_data_dly[j] : datar_tmp[i];
        end
      end
    end
  endgenerate

// pragma translate_off
  logic       wr_access_conflict;
  assign wr_access_conflict = in_a_en & in_b_en & in_a_wen & in_b_wen & (in_a_add == in_b_add);
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      if (wr_access_conflict) begin
        $warning("> WARNING: RAM write access conflict at address 0x%x.", in_a_add);
      end
    end
// pragma translate_on

// ---------------------------------------------------------------------------------------------- --
// datar
// ---------------------------------------------------------------------------------------------- --
  logic [1:0][WIDTH-1:0] datar;
  generate
    if (KEEP_RD_DATA != 0) begin : keep_rd_data_gen
      logic [1:0][WIDTH-1:0] datar_kept;
      always_ff @(posedge clk) begin
        for (int i=0; i<2; i=i+1) begin
          if (rd_en_dly[i])
            datar_kept[i] <= datar_tmp2[i];
        end
      end

      always_comb begin
        for (int i = 0; i<2; i=i+1) begin
          datar[i] = rd_en_dly[i] ? datar_tmp2[i] : datar_kept[i];
        end
      end
    end
    else begin : no_keep_rd_data_gen
      assign datar = datar_tmp2;
    end
  endgenerate

  generate
    if (RAM_LAT_OUT != 0) begin : add_ram_latency_gen

      logic [RAM_LAT_OUT-1:0][1:0][WIDTH-1:0] datar_sr;
      logic [RAM_LAT_OUT-1:0][1:0][WIDTH-1:0] datar_srD;

      assign datar_srD[0] = datar;

      if (RAM_LAT_OUT > 1) begin : ram_lat_out_gt_1
        assign datar_srD[RAM_LAT_OUT-1:1] = datar_sr[RAM_LAT_OUT-2:0];
      end

      always_ff @(posedge clk) begin
        datar_sr <= datar_srD;
      end

      assign a_rd_data = datar_sr[RAM_LAT_OUT-1][0];
      assign b_rd_data = datar_sr[RAM_LAT_OUT-1][1];
    end
    else begin : no_add_ram_latency_gen
      assign a_rd_data = datar[0];
      assign b_rd_data = datar[1];
    end
  endgenerate

endmodule
