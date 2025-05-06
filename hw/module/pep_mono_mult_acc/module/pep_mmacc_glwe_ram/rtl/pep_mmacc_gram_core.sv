// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the RAM used to store the GLWE data for a batch.
// This RAM is initialized by eternal write access.
// During the process:
// - it is read to get the GLWE coef and its rotated value.
// - the accumulated result is written.
// Once the process is over, an external read access is done to read back the results.
//
// To improve performances, physical cut of the RAMs are taken into account to enable
// concurrent accesses to the same batch, notably, feed and acc accesses.
// ==============================================================================================

module pep_mmacc_gram_core
#(
  parameter  int OP_W            = 64,
  parameter  int RAM_LATENCY     = 1,
  parameter  int GLWE_RAM_DEPTH  = 1024, //BATCH_PBS_NB * STG_ITER_NB * GLWE_K_P1,
  localparam int GLWE_RAM_ADD_W  = $clog2(GLWE_RAM_DEPTH),
  parameter  bit IN_PIPE         = 1'b1,
  parameter  bit OUT_PIPE        = 1'b1 // (1) highly recommended
)
(
  input  logic                           clk,        // clock
  input  logic                           s_rst_n,    // synchronous reset

  // External Write (port a)
  input  logic                           ext_gram_wr_en,
  input  logic [GLWE_RAM_ADD_W-1:0]      ext_gram_wr_add,
  input  logic [OP_W-1:0]                ext_gram_wr_data,

  // External Read (port b)
  input  logic                           sxt_gram_rd_en,
  input  logic [GLWE_RAM_ADD_W-1:0]      sxt_gram_rd_add,
  output logic [OP_W-1:0]                gram_sxt_rd_data,
  output logic                           gram_sxt_rd_data_avail,

  // Feed Read (port a and b)
  input  logic [1:0]                     feed_gram_rd_en,
  input  logic [1:0][GLWE_RAM_ADD_W-1:0] feed_gram_rd_add,
  output logic [1:0][OP_W-1:0]           gram_feed_rd_data,
  output logic [1:0]                     gram_feed_rd_data_avail,

  // Acc Read (port a)
  input  logic                           acc_gram_rd_en,
  input  logic [GLWE_RAM_ADD_W-1:0]      acc_gram_rd_add,
  output logic [OP_W-1:0]                gram_acc_rd_data,
  output logic                           gram_acc_rd_data_avail,

  // Acc Write (port b)
  input  logic                           acc_gram_wr_en,
  input  logic [GLWE_RAM_ADD_W-1:0]      acc_gram_wr_add,
  input  logic [OP_W-1:0]                acc_gram_wr_data,

  output logic                           error // access conflict
);

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int SR_DEPTH         = RAM_LATENCY + 1; // +1 : s0

// ============================================================================================== --
// Input pipe
// ============================================================================================== --
  logic                           s0_ext_gram_wr_en;
  logic [GLWE_RAM_ADD_W-1:0]      s0_ext_gram_wr_add;
  logic [OP_W-1:0]                s0_ext_gram_wr_data;

  logic                           s0_sxt_gram_rd_en;
  logic [GLWE_RAM_ADD_W-1:0]      s0_sxt_gram_rd_add;

  logic [1:0]                     s0_feed_gram_rd_en;
  logic [1:0][GLWE_RAM_ADD_W-1:0] s0_feed_gram_rd_add;

  logic                           s0_acc_gram_rd_en;
  logic [GLWE_RAM_ADD_W-1:0]      s0_acc_gram_rd_add;

  logic                           s0_acc_gram_wr_en;
  logic [GLWE_RAM_ADD_W-1:0]      s0_acc_gram_wr_add;
  logic [OP_W-1:0]                s0_acc_gram_wr_data;

  generate
    if (IN_PIPE) begin : gen_in_pipe
      always_ff @(posedge clk)
        if (!s_rst_n) begin
          s0_ext_gram_wr_en  <= '0;
          s0_sxt_gram_rd_en  <= '0;
          s0_feed_gram_rd_en <= '0;
          s0_acc_gram_rd_en  <= '0;
          s0_acc_gram_wr_en  <= '0;
        end
        else begin
          s0_ext_gram_wr_en  <= ext_gram_wr_en ;
          s0_sxt_gram_rd_en  <= sxt_gram_rd_en ;
          s0_feed_gram_rd_en <= feed_gram_rd_en;
          s0_acc_gram_rd_en  <= acc_gram_rd_en ;
          s0_acc_gram_wr_en  <= acc_gram_wr_en ;
        end

      always_ff @(posedge clk) begin
        s0_ext_gram_wr_add   <= ext_gram_wr_add;
        s0_ext_gram_wr_data  <= ext_gram_wr_data;
        s0_sxt_gram_rd_add   <= sxt_gram_rd_add;
        s0_feed_gram_rd_add  <= feed_gram_rd_add;
        s0_acc_gram_rd_add   <= acc_gram_rd_add;
        s0_acc_gram_wr_add   <= acc_gram_wr_add;
        s0_acc_gram_wr_data  <= acc_gram_wr_data;
      end
    end
    else begin : gen_no_in_pipe
      assign s0_ext_gram_wr_en    = ext_gram_wr_en ;
      assign s0_sxt_gram_rd_en    = sxt_gram_rd_en ;
      assign s0_feed_gram_rd_en   = feed_gram_rd_en;
      assign s0_acc_gram_rd_en    = acc_gram_rd_en ;
      assign s0_acc_gram_wr_en    = acc_gram_wr_en ;
      assign s0_ext_gram_wr_add   = ext_gram_wr_add;
      assign s0_ext_gram_wr_data  = ext_gram_wr_data;
      assign s0_sxt_gram_rd_add   = sxt_gram_rd_add;
      assign s0_feed_gram_rd_add  = feed_gram_rd_add;
      assign s0_acc_gram_rd_add   = acc_gram_rd_add;
      assign s0_acc_gram_wr_add   = acc_gram_wr_add;
      assign s0_acc_gram_wr_data  = acc_gram_wr_data;
    end
  endgenerate

  // ============================================================================================== --
  // s0 : arbiter
  // ============================================================================================== --
  // Port a
  //   read : feed / acc
  //   write : ext
  // Port b
  //   read : feed / ext
  //   write : acc
  // Note that there should never be any conflict. If it is the case an error is triggered
  // An arbitrary priority has been chosen.

  logic [1:0]            s0_access_error; // [0] : port a, [1] : port b

  logic                  s0_a_en;
  logic                  s0_a_wen;
  logic [GLWE_RAM_ADD_W-1:0] s0_a_add;
  logic [OP_W-1:0]       s0_a_wr_data;
  logic                  s0_a_is_feed;
  logic                  s0_b_en;
  logic                  s0_b_wen;
  logic [GLWE_RAM_ADD_W-1:0] s0_b_add;
  logic [OP_W-1:0]       s0_b_wr_data;
  logic                  s0_b_is_feed;

  assign s0_a_en      = s0_feed_gram_rd_en[0]|
                        s0_acc_gram_rd_en    |
                        s0_ext_gram_wr_en;
  assign s0_a_wen     = s0_ext_gram_wr_en;
  assign s0_a_add     = s0_ext_gram_wr_en ? s0_ext_gram_wr_add[GLWE_RAM_ADD_W-1:0] :
                        s0_acc_gram_rd_en ? s0_acc_gram_rd_add[GLWE_RAM_ADD_W-1:0] :
                        s0_feed_gram_rd_add[0][GLWE_RAM_ADD_W-1:0];
  assign s0_a_wr_data = s0_ext_gram_wr_data;
  assign s0_a_is_feed = ~s0_acc_gram_rd_en;

  assign s0_b_en      = s0_feed_gram_rd_en[1] |
                        s0_sxt_gram_rd_en     |
                        s0_acc_gram_wr_en;
  assign s0_b_wen     = s0_acc_gram_wr_en;
  assign s0_b_add     = s0_acc_gram_wr_en ? s0_acc_gram_wr_add[GLWE_RAM_ADD_W-1:0] :
                        s0_sxt_gram_rd_en ? s0_sxt_gram_rd_add[GLWE_RAM_ADD_W-1:0] :
                        s0_feed_gram_rd_add[1][GLWE_RAM_ADD_W-1:0];
  assign s0_b_wr_data = s0_acc_gram_wr_data;
  assign s0_b_is_feed = ~s0_sxt_gram_rd_en;


  // There is an access conflict when more than 1 access is requested
  assign s0_access_error[0] = (s0_ext_gram_wr_en & (s0_feed_gram_rd_en[0] | s0_acc_gram_rd_en)) | (s0_feed_gram_rd_en[0] & s0_acc_gram_rd_en);
  assign s0_access_error[1] = (s0_sxt_gram_rd_en & (s0_feed_gram_rd_en[1] | s0_acc_gram_wr_en)) | (s0_feed_gram_rd_en[1] & s0_acc_gram_wr_en);

// ============================================================================================== --
// s1 : RAM
// ============================================================================================== --
  logic                      s1_a_en;
  logic                      s1_a_wen;
  logic [GLWE_RAM_ADD_W-1:0] s1_a_add;
  logic [OP_W-1:0]           s1_a_wr_data;
  logic [OP_W-1:0]           s1_a_rd_data;
  logic                      s1_b_en;
  logic                      s1_b_wen;
  logic [GLWE_RAM_ADD_W-1:0] s1_b_add;
  logic [OP_W-1:0]           s1_b_wr_data;
  logic [OP_W-1:0]           s1_b_rd_data;

  logic [SR_DEPTH-1:0]       s1_a_ren_sr;
  logic [SR_DEPTH-1:0]       s1_a_is_feed_sr;
  logic [SR_DEPTH-1:0]       s1_b_ren_sr;
  logic [SR_DEPTH-1:0]       s1_b_is_feed_sr;

  logic [SR_DEPTH-1:0]       s1_a_ren_srD;
  logic [SR_DEPTH-1:0]       s1_a_is_feed_srD;
  logic [SR_DEPTH-1:0]       s1_b_ren_srD;
  logic [SR_DEPTH-1:0]       s1_b_is_feed_srD;

  assign s1_a_ren_srD[0]     = s0_a_en & ~s0_a_wen;
  assign s1_a_is_feed_srD[0] = s0_a_is_feed;
  assign s1_b_ren_srD[0]     = s0_b_en & ~s0_b_wen;
  assign s1_b_is_feed_srD[0] = s0_b_is_feed;

  assign s1_a_ren_srD[SR_DEPTH-1:1]     = s1_a_ren_sr[SR_DEPTH-2:0];
  assign s1_a_is_feed_srD[SR_DEPTH-1:1] = s1_a_is_feed_sr[SR_DEPTH-2:0];
  assign s1_b_ren_srD[SR_DEPTH-1:1]     = s1_b_ren_sr[SR_DEPTH-2:0];
  assign s1_b_is_feed_srD[SR_DEPTH-1:1] = s1_b_is_feed_sr[SR_DEPTH-2:0];

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      s1_a_en     <= 1'b0;
      s1_b_en     <= 1'b0;
      s1_a_ren_sr <= '0;
      s1_b_ren_sr <= '0;
    end
    else begin
      s1_a_en     <= s0_a_en;
      s1_b_en     <= s0_b_en;
      s1_a_ren_sr <= s1_a_ren_srD;
      s1_b_ren_sr <= s1_b_ren_srD;
    end

  always_ff @(posedge clk) begin
    s1_a_wen        <= s0_a_wen;
    s1_a_add        <= s0_a_add;
    s1_a_wr_data    <= s0_a_wr_data;
    s1_b_wen        <= s0_b_wen;
    s1_b_add        <= s0_b_add;
    s1_b_wr_data    <= s0_b_wr_data;
    s1_a_is_feed_sr <= s1_a_is_feed_srD;
    s1_b_is_feed_sr <= s1_b_is_feed_srD;
  end

  // -----------------------------------
  // RAM instance
  // -----------------------------------
  ram_wrapper_2RW #(
    .WIDTH             (OP_W),
    .DEPTH             (GLWE_RAM_DEPTH),
    .RD_WR_ACCESS_TYPE (0), // Output 'X' when access conflict
    .KEEP_RD_DATA      (0), // TOREVIEW
    .RAM_LATENCY       (RAM_LATENCY)
  ) glwe_ram
  (
    .clk       (clk),
    .s_rst_n   (s_rst_n),

    .a_en      (s1_a_en),
    .a_wen     (s1_a_wen),
    .a_add     (s1_a_add),
    .a_wr_data (s1_a_wr_data),
    .a_rd_data (s1_a_rd_data),

    .b_en      (s1_b_en),
    .b_wen     (s1_b_wen),
    .b_add     (s1_b_add),
    .b_wr_data (s1_b_wr_data),
    .b_rd_data (s1_b_rd_data)
  );

// ============================================================================================== --
// s2 : RAM datar
// ============================================================================================== --
  logic [OP_W-1:0]       s2_a_rd_data;
  logic                  s2_a_avail;
  logic                  s2_a_is_feed;
  logic [OP_W-1:0]       s2_b_rd_data;
  logic                  s2_b_avail;
  logic                  s2_b_is_feed;

  logic [OP_W-1:0]       s2_sxt_rd_data;
  logic                  s2_sxt_data_avail;

  logic [1:0][OP_W-1:0]  s2_feed_rd_data;
  logic [1:0]            s2_feed_data_avail;

  logic [OP_W-1:0]       s2_acc_rd_data;
  logic                  s2_acc_data_avail;

  assign s2_a_rd_data = s1_a_rd_data;
  assign s2_a_avail   = s1_a_ren_sr[SR_DEPTH-1];
  assign s2_a_is_feed = s1_a_is_feed_sr[SR_DEPTH-1];

  assign s2_b_rd_data = s1_b_rd_data;
  assign s2_b_avail   = s1_b_ren_sr[SR_DEPTH-1];
  assign s2_b_is_feed = s1_b_is_feed_sr[SR_DEPTH-1];

  assign s2_sxt_rd_data        = s2_b_rd_data;
  assign s2_sxt_data_avail     = s2_b_avail & ~s2_b_is_feed;

  assign s2_feed_rd_data[0]    = s2_a_rd_data;
  assign s2_feed_rd_data[1]    = s2_b_rd_data;
  assign s2_feed_data_avail[0] = s2_a_avail & s2_a_is_feed;
  assign s2_feed_data_avail[1] = s2_b_avail & s2_b_is_feed;

  assign s2_acc_rd_data        = s2_a_rd_data;
  assign s2_acc_data_avail     = s2_a_avail & ~s2_a_is_feed;

  // ============================================================================================== --
  // Output pipe
  // ============================================================================================== --
  generate
    if (OUT_PIPE) begin : gen_out_pipe
      always_ff @(posedge clk)
        if (!s_rst_n) begin
          gram_sxt_rd_data_avail  <= 1'b0;
          gram_feed_rd_data_avail <= '0;
          gram_acc_rd_data_avail  <= 1'b0;
        end
        else begin
          gram_sxt_rd_data_avail  <= s2_sxt_data_avail ;
          gram_feed_rd_data_avail <= s2_feed_data_avail;
          gram_acc_rd_data_avail  <= s2_acc_data_avail ;
        end
      always_ff @(posedge clk) begin
        gram_sxt_rd_data  <= s2_sxt_rd_data;
        gram_feed_rd_data <= s2_feed_rd_data;
        gram_acc_rd_data  <= s2_acc_rd_data;
      end
    end
    else begin
      assign gram_sxt_rd_data       = s2_sxt_rd_data   ;
      assign gram_sxt_rd_data_avail = s2_sxt_data_avail;

      assign gram_feed_rd_data       = s2_feed_rd_data   ;
      assign gram_feed_rd_data_avail = s2_feed_data_avail;

      assign gram_acc_rd_data       = s2_acc_rd_data   ;
      assign gram_acc_rd_data_avail = s2_acc_data_avail;
    end
  endgenerate

  // ============================================================================================== --
  // Error
  // ============================================================================================== --
  logic [1:0] access_error;
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      access_error <= '0;
      error        <= 1'b0;
    end
    else begin
      access_error <= s0_access_error;
      error        <= |access_error;
    end

endmodule
