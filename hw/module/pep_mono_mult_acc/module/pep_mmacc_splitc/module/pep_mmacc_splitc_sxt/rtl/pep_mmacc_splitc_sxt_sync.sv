// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals synchonizes input pulses. It proposes an output when all pulses from
// the inputs have been received.
// ==============================================================================================

module pep_mmacc_splitc_sxt_sync
#(
  parameter int IN_NB    = 2,
  parameter int DIFF_MAX = 258, // Maximum difference between the input pulses.
                               // Used to size the counters
  parameter bit OUT_PIPE = 1'b0
)
(
  input logic              clk,
  input logic              s_rst_n,

  input  logic [IN_NB-1:0] in_pulse,
  output logic             out_pulse
);


// ============================================================================================== //
// localparam
// ============================================================================================== //
  localparam int CNT_W = $clog2(DIFF_MAX) == 0 ? 1 : $clog2(DIFF_MAX);

// ============================================================================================== //
// Counters
// ============================================================================================== //
  logic out_pulseD;

  generate
    if (IN_NB == 1) begin : gen_input_nb_eq_1
      assign out_pulseD = in_pulse[0];
    end
    else begin : gen_input_nb_gt_1
      logic [IN_NB-1:0][CNT_W-1:0] pulse_cnt;
      logic [IN_NB-1:0][CNT_W-1:0] pulse_cntD;
      logic [IN_NB-1:0]            pulse_cnt_seen;

      assign out_pulseD = &pulse_cnt_seen;

      always_comb
        for (int i=0; i<IN_NB; i=i+1) begin
          pulse_cntD[i] = in_pulse[i] && !out_pulseD ? pulse_cnt[i] + 1 :
                          !in_pulse[i] && out_pulseD ? pulse_cnt[i] - 1 : pulse_cnt[i];
          pulse_cnt_seen[i] = pulse_cnt[i] > 0;
        end
      
      always_ff @(posedge clk)
        if (!s_rst_n) pulse_cnt <= '0;
        else          pulse_cnt <= pulse_cntD;

// pragma translate_off
      always_ff @(posedge clk)
        if (!s_rst_n) begin
          // do nothing
        end
        else begin
          for (int i=0; i<IN_NB; i=i+1) begin
            assert(!in_pulse[i] || (pulse_cnt[i] < DIFF_MAX-1))
            else begin
              $fatal(1,"%t >ERROR: pulse_sync overflows. Set correct DIFF_MAX value (%0d).", $time, DIFF_MAX);
            end
          end
        end
// pragma translate_on
    end
  endgenerate

// ============================================================================================== //
// Output
// ============================================================================================== //
  generate
    if (OUT_PIPE) begin : gen_out_pipe
      always_ff @(posedge clk)
        if (!s_rst_n) out_pulse <= 1'b0;
        else          out_pulse <= out_pulseD;

    end
    else begin : gen_no_out_pipe
      assign out_pulse = out_pulseD;
    end
  endgenerate

endmodule

