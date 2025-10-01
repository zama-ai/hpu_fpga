// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module stores the body "b" of the small LWE.
// They are used by the sample extract module to do the rotation with b.
// ==============================================================================================

module pep_mmacc_body_ram
  import param_tfhe_pkg::*;
  import pep_common_param_pkg::*;
(
  input                             clk,        // clock
  input                             s_rst_n,    // synchronous reset
  input                             reset_cache,

  input  logic                      ks_boram_wr_en,
  input  logic [MOD_KSK_W-1:0]      ks_boram_wr_data,
  input  logic [PID_W-1:0]          ks_boram_wr_pid,
  input  logic                      ks_boram_wr_parity,

  input  logic                      seq_boram_corr_wr_en,
  input  logic [KS_CORR_W-1:0]      seq_boram_corr_wr_data,
  input  logic [PID_W-1:0]          seq_boram_corr_wr_pid,

  input  logic [PID_W-1:0]          boram_rd_pid,
  input  logic                      boram_rd_parity,
  input  logic                      boram_rd_vld,
  output logic                      boram_rd_rdy,

  output logic [LWE_COEF_W-1:0]     boram_sxt_data,
  output logic                      boram_sxt_data_vld,
  input  logic                      boram_sxt_data_rdy
);

// ============================================================================================== --
// Local parameters
// ============================================================================================== --
  localparam int unsigned BR_CORR_W      = MOD_KSK_W + KS_KEY_MEAN_F;
  localparam [MOD_KSK_W-1:0] CENTER_CORR = 1 << (MOD_KSK_W - LWE_COEF_W - 1); // MOD_KSK / (2 * 2N)

// ============================================================================================= --
// Input pipe
// ============================================================================================= --
  logic                  sm1_wr_en;
  logic [MOD_KSK_W-1:0]  sm1_wr_data;
  logic [PID_W-1:0]      sm1_wr_pid;
  logic                  sm1_wr_parity;

  always_ff @(posedge clk)
    if (!s_rst_n) sm1_wr_en <= 1'b0;
    else          sm1_wr_en <= ks_boram_wr_en;

  always_ff @(posedge clk) begin
    sm1_wr_data   <= ks_boram_wr_data;
    sm1_wr_parity <= ks_boram_wr_parity;
    sm1_wr_pid    <= ks_boram_wr_pid;
  end

  // Correction signals
  logic                      corr_ram_wr_en;
  logic [KS_CORR_W-1:0]      corr_ram_wr_data;
  logic [PID_W-1:0]          corr_ram_wr_pid;

  always_ff @(posedge clk)
    if (!s_rst_n) corr_ram_wr_en <= 1'b0;
    else          corr_ram_wr_en <= seq_boram_corr_wr_en;

  always_ff @(posedge clk) begin
    corr_ram_wr_data <= seq_boram_corr_wr_data;
    corr_ram_wr_pid  <= seq_boram_corr_wr_pid;
  end

  logic [PID_W-1:0] s0_rd_pid;
  logic             s0_rd_parity;
  logic             s0_rd_vld;
  logic             s0_rd_rdy;

  fifo_element #(
    .WIDTH          (PID_W+1),
    .DEPTH          (2),
    .TYPE_ARRAY     (8'h12),
    .DO_RESET_DATA  (0),
    .RESET_DATA_VAL (0)
  ) in_fifo_element (
    .clk     (clk),
    .s_rst_n (s_rst_n),

    .in_data ({boram_rd_parity,boram_rd_pid}),
    .in_vld  (boram_rd_vld),
    .in_rdy  (boram_rd_rdy),

    .out_data({s0_rd_parity,s0_rd_pid}),
    .out_vld (s0_rd_vld),
    .out_rdy (s0_rd_rdy)
  );

// ============================================================================================= --
// Output pipe
// ============================================================================================= --
  logic [LWE_COEF_W-1:0] s2_out_data;
  logic                  s2_out_vld;
  logic                  s2_out_rdy;

  fifo_element #(
    .WIDTH          (LWE_COEF_W),
    .DEPTH          (2),
    .TYPE_ARRAY     (8'h12),
    .DO_RESET_DATA  (0),
    .RESET_DATA_VAL (0)
  ) out_fifo_element (
    .clk     (clk),
    .s_rst_n (s_rst_n),

    .in_data (s2_out_data),
    .in_vld  (s2_out_vld),
    .in_rdy  (s2_out_rdy),

    .out_data(boram_sxt_data),
    .out_vld (boram_sxt_data_vld),
    .out_rdy (boram_sxt_data_rdy)
  );

// ============================================================================================= --
// Center
// ============================================================================================= --
// Center the body, for the shifted modulo switch.
// Before the mean compensation and modswitch, center the body, by subtracting
// MOD_KSK / (2*2N)
  logic                  ram_wr_en;
  logic [MOD_KSK_W-1:0]  ram_wr_data;
  logic [PID_W-1:0]      ram_wr_pid;
  logic                  ram_wr_parity;

  logic [MOD_KSK_W-1:0]  sm1_wr_data_centered;
  generate
    if (USE_MEAN_COMP) begin : gen_use_mean_comp
      assign sm1_wr_data_centered = sm1_wr_data - CENTER_CORR;
    end
    else begin : gen_no_use_mean_comp
      assign sm1_wr_data_centered = sm1_wr_data;
    end
  endgenerate

  always_ff @(posedge clk)
    if (!s_rst_n) ram_wr_en <= 1'b0;
    else          ram_wr_en <= sm1_wr_en;

  always_ff @(posedge clk) begin
    ram_wr_data   <= sm1_wr_data_centered;
    ram_wr_parity <= sm1_wr_parity;
    ram_wr_pid    <= sm1_wr_pid;
  end

// ============================================================================================= --
// RAM
// ============================================================================================= --
  // Read port
  logic                 ram_rd_en;
  logic [PID_W-1:0]     ram_rd_pid;
  logic [MOD_KSK_W-1:0] ram_data;      // Old value at the write address
  logic [MOD_KSK_W-1:0] ram_rd_data;   // Read value
  logic                 ram_parity;    // Old value at the write address
  logic                 ram_rd_parity; // Read value

  logic                 ram_present_wen;
  logic [PID_W-1:0]     ram_present_wadd;
  logic                 ram_present;     // Old value at the write address
  logic                 ram_presentD;    // New value at the write address
  logic                 ram_rd_present;  // Value read

  assign ram_rd_en  = s0_rd_vld & s0_rd_rdy;
  assign ram_rd_pid = s0_rd_pid;

  ram_wrapper_NR1W #(
    .WIDTH      ( MOD_KSK_W + 1 ) ,
    .DEPTH      ( TOTAL_PBS_NB  ) ,
    .RD_PORT_NB ( 2             )
  ) body_ram (
    .clk     ( clk                                                     ) ,
    .s_rst_n ( s_rst_n                                                 ) ,
    .wr_en   ( ram_wr_en                                               ) ,
    .wr_add  ( ram_wr_pid                                              ) ,
    .wr_data ( {ram_wr_data, ram_wr_parity}                            ) ,
    .rd_en   ( '{1'b1, 1'b1}                                           ) ,
    .rd_add  ( '{ram_rd_pid, ram_wr_pid}                               ) ,
    .rd_data ( '{{ram_rd_data, ram_rd_parity}, {ram_data, ram_parity}} )
  );

  ram_wrapper_NR1W #(
    .WIDTH      ( 1            ) ,
    .DEPTH      ( TOTAL_PBS_NB ) ,
    .RD_PORT_NB ( 2            ) ,
    .HAS_RST    ( 1'b1         ) ,
    .RST_VAL    ( 1'b0         )
  ) present_ram (
    .clk     ( clk                            ) ,
    .s_rst_n ( s_rst_n & ~reset_cache         ) ,
    .wr_en   ( ram_present_wen                ) ,
    .wr_add  ( ram_present_wadd               ) ,
    .wr_data ( ram_presentD                   ) ,
    .rd_en   ( '{1'b1, 1'b1}                  ) ,
    .rd_add  ( '{ram_rd_pid, ram_wr_pid}      ) ,
    .rd_data ( '{ram_rd_present, ram_present} )
  );

  assign ram_present_wadd = ram_wr_en ? ram_wr_pid : ram_rd_pid ; // Write has priority
  assign ram_presentD     = ram_wr_en;
  assign ram_present_wen  = ram_wr_en || ram_rd_en;

// pragma translate_off
  // Remove parity check, because, it could occur in IPIP, that the data is written twice,
  // because the KS process starts during the last KS col. The 2 times with different parities.
  // Therefore the request could be done with the first write parity, but data stored with
  // the last parity.
  // If this occurs, check that the data has the same value.
  //
  // parity signals are here for the debug.
  always_ff @(posedge clk)
    if (ram_wr_en && ram_present) begin
      assert_body_ram_rewrite:
      assert(ram_data == ram_wr_data)
      else begin
        $display("%t > WARNING: Rewrite data in body_ram at pid=%0d, whereas data already present with another value.",$time,ram_wr_pid);
      end

      assert_body_ram_parity:
      assert(ram_parity != ram_wr_parity)
      else begin
        $display("%t > WARNING: Rewrite data in body_ram at pid=%0d, whereas data already present with same parity.",$time,ram_wr_pid);
      end

      assert_body_ram_present:
      assert(!ram_rd_en || ram_rd_present)
      else begin
        $fatal(1,"%t > ERROR: Read data in body_ram at pid=%0d, whereas data not present.",$time,ram_rd_pid);
      end
    end
// pragma translate_on

// ============================================================================================= --
// Correction RAM
// ============================================================================================= --
  logic [KS_MAX_ERROR_W-1:0] corr_data;        // Old value at the write address
  logic [KS_MAX_ERROR_W-1:0] corr_dataD;       // New write address
  logic [KS_MAX_ERROR_W-1:0] corr_ram_rd_data; // Read value
  logic [KS_MAX_ERROR_W-1:0] corr_ram_wr_data_ext;

  logic [LWE_K_WW-1:0] corr_cnt;         // Old value at the write address
  logic [LWE_K_WW-1:0] corr_cntD;        // New value at the write address
  logic [LWE_K_WW-1:0] corr_cnt_rd_data; // Read value

  logic                      corr_present;
  logic                      corr_presentD;
  logic                      corr_present_rd_data;
  logic                      corr_present_wen;
  logic [PID_W-1:0]          corr_present_wadd;

  logic                      corr_rd_avail;

  ram_wrapper_NR1W #(
    .WIDTH      ( LWE_K_WW + KS_MAX_ERROR_W ) ,
    .DEPTH      ( TOTAL_PBS_NB                    ) ,
    .RD_PORT_NB ( 2                               )
  ) corr_ram (
    .clk     ( clk                                                            ) ,
    .s_rst_n ( s_rst_n                                                        ) ,
    .wr_en   ( corr_ram_wr_en                                                 ) ,
    .wr_add  ( corr_ram_wr_pid                                                ) ,
    .wr_data ( {corr_cntD, corr_dataD}                                        ) ,
    .rd_en   ( '{1'b1, 1'b1}                                                  ) ,
    .rd_add  ( '{corr_ram_wr_pid, ram_rd_pid}                                 ) ,
    .rd_data ( '{{corr_cnt, corr_data}, {corr_cnt_rd_data, corr_ram_rd_data}} )
  );

  ram_wrapper_NR1W #(
    .WIDTH      ( 1'b1         ) ,
    .DEPTH      ( TOTAL_PBS_NB ) ,
    .RD_PORT_NB ( 2            ) ,
    .HAS_RST    ( 1'b1         ) ,
    .RST_VAL    ( 1'b0         )
  ) corr_present_ram (
    .clk     ( clk                                   ) ,
    .s_rst_n ( s_rst_n & ~reset_cache                ) ,
    .wr_en   ( corr_present_wen                      ) ,
    .wr_add  ( corr_present_wadd                     ) ,
    .wr_data ( corr_presentD                         ) ,
    .rd_en   ( '{1'b1, 1'b1}                         ) ,
    .rd_add  ( '{corr_ram_wr_pid, ram_rd_pid}        ) ,
    .rd_data ( '{corr_present, corr_present_rd_data} )
  );

  // Sign extension
  assign corr_ram_wr_data_ext = {{KS_MAX_ERROR_W-KS_CORR_W{corr_ram_wr_data[KS_CORR_W-1]}},corr_ram_wr_data};
  assign corr_dataD        = corr_present ? corr_ram_wr_data_ext + corr_data : corr_ram_wr_data_ext;
  // First element is caught by corr_present.
  // The counter starts to count with the 2nd element. Therefore initialized with value 1.
  assign corr_cntD         = corr_present ? LWE_K_WW'(corr_cnt + 1'b1) : LWE_K_WW'(1);
  assign corr_presentD     = corr_ram_wr_en;
  assign corr_present_wadd = corr_ram_wr_en ? corr_ram_wr_pid : ram_rd_pid ; // Write has priority
  assign corr_present_wen  = corr_ram_wr_en || ram_rd_en;

  assign corr_rd_avail     = corr_present_rd_data & (corr_cnt_rd_data == LWE_K);

// pragma translate_off
  always_ff @(posedge clk)
    if (corr_ram_wr_en && corr_present) begin
      assert_corr_ram_rewrite:
      assert(corr_cnt < LWE_K)
      else $fatal(1, "%t > ERROR: Correction RAM re-written at pid=%0d.",$time,corr_ram_wr_pid);

      assert_unfinished_read:
      assert(!ram_rd_en || (corr_cnt_rd_data == LWE_K))
      else $fatal(1,"%t > ERROR: Unfinished data read at pid=%0d.",$time,ram_rd_pid);
    end
// pragma translate_on

// ============================================================================================= --
// RAM output stage
// This is needed to close timing on the mean compensation logic
// ============================================================================================= --
  logic                      s0_vld;
  logic                      s0_rdy;
  logic [MOD_KSK_W-1:0]      s0_ram_rd_data;
  logic [KS_MAX_ERROR_W-1:0] s0_corr_ram_rd_data;

  logic                      s1_vld;
  logic                      s1_rdy;
  logic [MOD_KSK_W-1:0]      s1_ram_rd_data;
  logic [KS_MAX_ERROR_W-1:0] s1_corr_ram_rd_data;

  assign s0_ram_rd_data      = ram_rd_data;
  assign s0_corr_ram_rd_data = corr_ram_rd_data;

  // When a the result is available, we do a reading but also a writing
  // to reset the present information.
  // Using ram_NR1W, there is only a single write port.
  // Therefore, the write that is associated to a read is not
  // priority over a "regular" write. Indeed the read is not urgent.
  // If the read becomes urgent, change the ram_NR1W into ram_NRNW, and
  // solve access conflict with read as priority (since it resets the value).
  // Below the dependency with *wr_en reflects that.
  logic s0_rd_cond;
  assign s0_rd_cond= ram_rd_present & corr_rd_avail
                     & ~ram_wr_en & ~corr_ram_wr_en;
  assign s0_vld    = s0_rd_vld & s0_rd_cond;
  assign s0_rd_rdy = s0_rdy    & s0_rd_cond;

  fifo_element #(
    .WIDTH          (MOD_KSK_W + KS_MAX_ERROR_W),
    .DEPTH          (2),
    .TYPE_ARRAY     (8'h12),
    .DO_RESET_DATA  (0),
    .RESET_DATA_VAL (0)
  ) s1_fifo_element (
    .clk     (clk),
    .s_rst_n (s_rst_n),

    .in_data ({s0_corr_ram_rd_data,s0_ram_rd_data}),
    .in_vld  (s0_vld),
    .in_rdy  (s0_rdy),

    .out_data({s1_corr_ram_rd_data,s1_ram_rd_data}),
    .out_vld (s1_vld),
    .out_rdy (s1_rdy)
  );

// ============================================================================================= --
// Final correction
// ============================================================================================= --
  // The correction here should be: b - mean(s) * sum(mod_switch_err), where s is the binary key
  // switching key and mod_switch_err the vector of mod_switch_error factors of doing modulus
  // switching on mask elements.
  // The key mean value is encoded in fixed point. This part of the code will convert b to the fixed
  // point format before subtraction.

  logic [BR_CORR_W-1:0] s1_br_corrected;
  logic [BR_CORR_W-1:0] s1_corr_xtend;

  generate if (BR_CORR_W > KS_MAX_ERROR_W) begin: with_signed_ext
    assign s1_corr_xtend = {
      {(BR_CORR_W-KS_MAX_ERROR_W){s1_corr_ram_rd_data[KS_MAX_ERROR_W-1]}},
                                  s1_corr_ram_rd_data[KS_MAX_ERROR_W-1:0]
      };
  end else if (BR_CORR_W == KS_MAX_ERROR_W) begin: no_sign_ext
    assign s1_corr_xtend = s1_corr_ram_rd_data;
  end else begin: invalid_sign_ext
    $fatal(1, "The accumulation mod switch error (%0d) cannot be greater than the final compensated B width (%0d)",
              KS_MAX_ERROR_W, BR_CORR_W);
  end endgenerate

  assign s1_br_corrected = (BR_CORR_W'(s1_ram_rd_data) << KS_KEY_MEAN_F)
                         - s1_corr_xtend * BR_CORR_W'(KS_KEY_MEAN);

// ============================================================================================= --
// Final mod switch. br_corrected is in fixed point format, but that is irrelevant in the
// modulus switch if we pick exactly LWE_COEF_W bits starting from the MSB.
// ============================================================================================= --
  assign s2_out_vld = s1_vld;
  assign s1_rdy     = s2_out_rdy;

  assign s2_out_data = s1_br_corrected[BR_CORR_W-1-:LWE_COEF_W] + s1_br_corrected[BR_CORR_W-1-LWE_COEF_W];

endmodule
