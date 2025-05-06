// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the counters, that are exposed on the register interface.
// ==============================================================================================

module hpu_regfile_counter_manager
#(
  parameter int SINGLE_NB      = 1, // counter over REG_DATA_W
  parameter int DOUBLE_NB      = 1, // counter over 2*REG_DATA_W
  parameter int DURATION_NB    = 1, // counter of a duration : number of cycle the signal is 1
  parameter int POSEDGE_NB     = 1, // posedge counter
  parameter int REG_DATA_W     = 32
) (
  input  logic                                      clk,
  input  logic                                      s_rst_n,

  // reg_if
  output logic [SINGLE_NB-1:0][REG_DATA_W-1:0]      r_sg_counter_upd,
  input  logic [SINGLE_NB-1:0]                      r_sg_counter_wr_en,

  output logic [DOUBLE_NB-1:0][1:0][REG_DATA_W-1:0] r_db_counter_upd,
  input  logic [DOUBLE_NB-1:0][1:0]                 r_db_counter_wr_en,

  output logic [DURATION_NB-1:0][REG_DATA_W-1:0]    r_dr_counter_upd,
  input  logic [DURATION_NB-1:0]                    r_dr_counter_wr_en,

  output logic [POSEDGE_NB-1:0][REG_DATA_W-1:0]     r_ps_counter_upd,
  input  logic [POSEDGE_NB-1:0]                     r_ps_counter_wr_en,

  input  logic [REG_DATA_W-1:0]                     r_wr_data,

  // from modules
  input  logic [SINGLE_NB-1:0]                      sg_inc, // pulse
  input  logic [DOUBLE_NB-1:0]                      db_inc, // pulse
  input  logic [DURATION_NB-1:0]                    dr_inc, // counts from posedge to negedge. keep max value.
  input  logic [POSEDGE_NB-1:0]                     ps_inc
);

  generate
// ============================================================================================== //
// Single counter
// ============================================================================================== //
    for (genvar gen_i=0; gen_i<SINGLE_NB; gen_i=gen_i+1) begin : gen_sg_loop
      logic [REG_DATA_W-1:0] counter;
      logic [REG_DATA_W-1:0] counterD;

      logic counter_overflow;

      assign counter_overflow = counter == '1;
      assign counterD = r_sg_counter_wr_en[gen_i] ? r_wr_data :
                        sg_inc[gen_i]             ? counter_overflow ? '1 : counter + 1 : counter;

      always_ff @(posedge clk)
        if (!s_rst_n) counter <= '0;
        else          counter <= counterD;

      assign r_sg_counter_upd[gen_i] = counter;
    end

// ============================================================================================== //
// Double counter
// ============================================================================================== //
    for (genvar gen_i=0; gen_i<DOUBLE_NB; gen_i=gen_i+1) begin : gen_db_loop
      logic [1:0][REG_DATA_W-1:0] counter;
      logic [1:0][REG_DATA_W-1:0] counterD;

      logic [1:0] counter_overflow;

      assign counter_overflow[0] = counter[0] == '1;
      assign counter_overflow[1] = counter[1] == '1;
      assign counterD[0] = r_db_counter_wr_en[gen_i][0] ? r_wr_data :
                           db_inc[gen_i]                ? |counter_overflow ? '1 : counter[0] + 1 : counter[0];
      assign counterD[1] = r_db_counter_wr_en[gen_i][1] ? r_wr_data :
                           db_inc[gen_i] && counter_overflow[0] ? counter_overflow[1] ? '1 : counter[1] + 1 : counter[1];

      always_ff @(posedge clk)
        if (!s_rst_n) counter <= '0;
        else          counter <= counterD;

      assign r_db_counter_upd[gen_i] = counter;
    end

// ============================================================================================== //
// Duration counter
// ============================================================================================== //
    for (genvar gen_i=0; gen_i<DURATION_NB; gen_i=gen_i+1) begin : gen_dr_loop
      logic [REG_DATA_W-1:0] counter;
      logic [REG_DATA_W-1:0] counterD;
      logic [REG_DATA_W-1:0] counter_max;
      logic [REG_DATA_W-1:0] counter_maxD;

      logic counter_overflow;

      assign counter_overflow = counter == '1;
      assign counterD         = dr_inc[gen_i]             ? counter_overflow ? '1 : counter + 1 : '0;
      assign counter_maxD     = r_dr_counter_wr_en[gen_i] ? r_wr_data :
                                counter > counter_max     ? counter : counter_max;

      always_ff @(posedge clk)
        if (!s_rst_n) begin
          counter     <= '0;
          counter_max <= '0;
        end
        else begin
          counter     <= counterD;
          counter_max <= counter_maxD;
        end

      assign r_dr_counter_upd[gen_i] = counter_max;
    end

// ============================================================================================== //
// Posedge counter
// ============================================================================================== //
    for (genvar gen_i=0; gen_i<POSEDGE_NB; gen_i=gen_i+1) begin : gen_ps_loop
      logic [REG_DATA_W-1:0] counter;
      logic [REG_DATA_W-1:0] counterD;

      logic counter_overflow;

      logic inc_dly;
      logic inc_posedge;

      assign inc_posedge = ps_inc[gen_i] & ~inc_dly;
      assign counter_overflow = counter == '1;
      assign counterD = r_ps_counter_wr_en[gen_i] ? r_wr_data :
                        inc_posedge               ? counter_overflow ? '1 : counter + 1 : counter;

      always_ff @(posedge clk)
        if (!s_rst_n) begin
          counter <= '0;
          inc_dly <= 1'b0;
        end
        else begin
          counter <= counterD;
          inc_dly <= ps_inc[gen_i];
        end

      assign r_ps_counter_upd[gen_i] = counter;
    end

  endgenerate

endmodule

