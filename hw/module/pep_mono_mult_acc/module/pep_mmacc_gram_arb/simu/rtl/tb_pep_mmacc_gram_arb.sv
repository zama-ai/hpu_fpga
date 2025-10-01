// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Testbench for the GRAM arbiter.
// ==============================================================================================

module tb_pep_mmacc_gram_arb;
  `timescale 1ns/10ps

  import pep_common_param_pkg::*;
  import pep_mmacc_common_param_pkg::*;

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int CLK_HALF_PERIOD = 1;
  localparam int ARST_ACTIVATION = 17;

  localparam int RAND_RANGE = 1024-1;
  localparam int SRC_NB     = 4;
  localparam int REQ_NB     = 2;

  parameter  int SAMPLE_NB = 1000;

  initial begin
    $display("INFO > GARB_SLOT_CYCLE=%0d",GARB_SLOT_CYCLE);
    $display("INFO > GLWE_SLOT_NB=%0d",GLWE_SLOT_NB);
  end

// ============================================================================================== --
// clock, reset
// ============================================================================================== --
  bit clk;
  bit a_rst_n; // asynchronous reset
  bit s_rst_n; // synchronous reset

  initial begin
    clk     = 1'b0;
    a_rst_n = 1'b0;                   // active reset
    #ARST_ACTIVATION a_rst_n = 1'b1; // disable reset
  end

  always begin
    #CLK_HALF_PERIOD clk = ~clk;
  end

  always_ff @(posedge clk) begin
    s_rst_n <= a_rst_n;
  end

// ============================================================================================== --
// End of test
// ============================================================================================== --
  bit end_of_test;

  initial begin
    wait (end_of_test);
    @(posedge clk) $display("%t > SUCCEED !", $time);
    $finish;
  end

// ============================================================================================== --
// Error
// ============================================================================================== --
  bit error;
  bit error_attribution;
  bit error_grant;
  bit error_cycle;

  assign error = error_attribution | error_grant | error_cycle;

  always_ff @(posedge clk)
    if (error) begin
      $display("%t > FAILURE !", $time);
      $finish;
    end

// ============================================================================================== --
// input / output signals
// ============================================================================================== --
  logic [GARB_CMD_W-1:0] mmfeed_garb_req;
  logic                  mmfeed_garb_req_vld;
  logic                  mmfeed_garb_req_rdy;

  logic [GARB_CMD_W-1:0] mmacc_garb_req;
  logic                  mmacc_garb_req_vld;
  logic                  mmacc_garb_req_rdy;

  logic                  garb_mmfeed_grant;
  logic                  garb_mmacc_grant;

  logic [GRAM_NB-1:0]    garb_mmfeed_rot_avail_1h;
  logic [GRAM_NB-1:0]    garb_mmfeed_dat_avail_1h;
  logic [GRAM_NB-1:0]    garb_mmacc_rd_avail_1h;
  logic [GRAM_NB-1:0]    garb_mmacc_wr_avail_1h;
  logic [GRAM_NB-1:0]    garb_mmsxt_avail_1h;
  logic [GRAM_NB-1:0]    garb_ldg_avail_1h;

// ============================================================================================== --
// Design under test instance
// ============================================================================================== --
  pep_mmacc_gram_arb
  dut (
    .clk                     (clk    ),
    .s_rst_n                 (s_rst_n),
    .mmfeed_garb_req         (mmfeed_garb_req),
    .mmfeed_garb_req_vld     (mmfeed_garb_req_vld),
    .mmfeed_garb_req_rdy     (mmfeed_garb_req_rdy),

    .mmacc_garb_req          (mmacc_garb_req),
    .mmacc_garb_req_vld      (mmacc_garb_req_vld),
    .mmacc_garb_req_rdy      (mmacc_garb_req_rdy),

    .garb_mmfeed_grant       (garb_mmfeed_grant),
    .garb_mmacc_grant        (garb_mmacc_grant),

    .garb_mmfeed_rot_avail_1h(garb_mmfeed_rot_avail_1h),
    .garb_mmfeed_dat_avail_1h(garb_mmfeed_dat_avail_1h),
    .garb_mmacc_rd_avail_1h  (garb_mmacc_rd_avail_1h),
    .garb_mmacc_wr_avail_1h  (garb_mmacc_wr_avail_1h),
    .garb_mmsxt_avail_1h     (garb_mmsxt_avail_1h),
    .garb_ldg_avail_1h       (garb_ldg_avail_1h)
  );

// ============================================================================================== --
// Scenario
// ============================================================================================== --
  garb_cmd_t [REQ_NB-1:0] garb_req;
  logic      [REQ_NB-1:0] garb_req_vld;
  logic      [REQ_NB-1:0] garb_req_rdy;

  logic      [REQ_NB-1:0] garb_mm_grant;

  assign garb_mm_grant[0] = garb_mmfeed_grant;
  assign garb_mm_grant[1] = garb_mmacc_grant;

  assign mmfeed_garb_req = garb_req[0];
  assign mmacc_garb_req  = garb_req[1];

  assign mmfeed_garb_req_vld = garb_req_vld[0];
  assign mmacc_garb_req_vld  = garb_req_vld[1];

  assign garb_req_rdy[0] = mmfeed_garb_req_rdy;
  assign garb_req_rdy[1] = mmacc_garb_req_rdy ;

  generate
    for (genvar gen_i=0; gen_i<REQ_NB; gen_i=gen_i+1) begin : gen_req_loop
      integer      after_grant_cnt;
      logic        do_req;
      logic [15:0] req_cnt;
      logic        req_vld;
      logic        req_rdy;

      always_ff @(posedge clk)
        if (!s_rst_n) after_grant_cnt <= 'hFFFF;
        else          after_grant_cnt <= req_vld && req_rdy   ? '0 :
                                         garb_mm_grant[gen_i] ? 1 :
                                         after_grant_cnt > 0  && after_grant_cnt < 'hFFFF ? after_grant_cnt +1 : after_grant_cnt;

      assign do_req = after_grant_cnt >= (GLWE_SLOT_NB-1)*GARB_SLOT_CYCLE;
      assign garb_req_vld[gen_i]     = req_vld & do_req;
      assign req_rdy                 = garb_req_rdy[gen_i] & do_req;
      assign garb_req[gen_i].grid    = req_cnt % GRAM_NB;
      assign garb_req[gen_i].critical = ^req_cnt; // random value

      stream_source
      #(
        .FILENAME   ("counter"),
        .DATA_TYPE  ("ascii_hex"),
        .DATA_W     (16),
        .RAND_RANGE (RAND_RANGE),
        .KEEP_VLD   (1),
        .MASK_DATA  ("x")
      )
      source_req
      (
        .clk        (clk),
        .s_rst_n    (s_rst_n),

        .data       (req_cnt),
        .vld        (req_vld),
        .rdy        (req_rdy),

        .throughput (0) // Random
      );

      initial begin
        if (!source_req.open()) begin
          $fatal(1, "%t > ERROR: Opening source_req stream source", $time);
        end
        wait(s_rst_n);
        @(posedge clk);
        source_req.start(SAMPLE_NB);
      end
    end // for gen_i

  endgenerate


// ============================================================================================== --
// End of test
// ============================================================================================== --
  integer req_cnt [REQ_NB-1:0];
  integer grant_cnt [REQ_NB-1:0];

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      req_cnt   <= '{default:'0};
      grant_cnt <= '{default:'0};
    end
    else begin
      req_cnt[0]   <= (mmfeed_garb_req_vld && mmfeed_garb_req_rdy) ? req_cnt[0] + 1 : req_cnt[0];
      req_cnt[1]   <= (mmacc_garb_req_vld && mmacc_garb_req_rdy)   ? req_cnt[1] + 1 : req_cnt[1];
      grant_cnt[0] <= garb_mmfeed_grant ? grant_cnt[0] + 1 : grant_cnt[0];
      grant_cnt[1] <= garb_mmacc_grant  ? grant_cnt[1] + 1 : grant_cnt[1];
    end

  initial begin
    end_of_test <= 1'b0;
    error_grant <= 1'b0;

    wait (req_cnt[0] == SAMPLE_NB);
    wait (req_cnt[1] == SAMPLE_NB);

    repeat(100) @(posedge clk);

    assert(grant_cnt[0] == SAMPLE_NB)
    else begin
      $display("%t > ERROR: Mismatch feed grant_nb exp=%0d seen=%0d",$time, SAMPLE_NB, grant_cnt[0]);
      error_grant <= 1'b1;
    end

    assert(grant_cnt[1] == SAMPLE_NB)
    else begin
      $display("%t > ERROR: Mismatch acc grant_nb exp=%0d seen=%0d",$time, SAMPLE_NB, grant_cnt[1]);
      error_grant <= 1'b1;
    end

    @(posedge clk) end_of_test <= 1'b1;
  end

// ============================================================================================== --
// Check
// ============================================================================================== --
  integer cycle_cnt;
  integer feed_rot_cycle [GRAM_NB-1:0];
  integer feed_dat_cycle [GRAM_NB-1:0];
  integer acc_rd_cycle[GRAM_NB-1:0];
  integer acc_wr_cycle[GRAM_NB-1:0];

  bit feed_rot_change [GRAM_NB-1:0];
  bit feed_dat_change [GRAM_NB-1:0];
  bit acc_rd_change [GRAM_NB-1:0];
  bit acc_wr_change [GRAM_NB-1:0];

  logic [GRAM_NB-1:0]    garb_mmfeed_rot_avail_1h_dly;
  logic [GRAM_NB-1:0]    garb_mmfeed_dat_avail_1h_dly;
  logic [GRAM_NB-1:0]    garb_mmacc_rd_avail_1h_dly;
  logic [GRAM_NB-1:0]    garb_mmacc_wr_avail_1h_dly;

  always_comb
    for (int i=0; i<GRAM_NB; i=i+1) begin
      feed_rot_change[i] = ~garb_mmfeed_rot_avail_1h[i] & garb_mmfeed_rot_avail_1h_dly[i];
      feed_dat_change[i] = ~garb_mmfeed_dat_avail_1h[i] & garb_mmfeed_dat_avail_1h_dly[i];
      acc_rd_change[i]   = ~garb_mmacc_rd_avail_1h[i]   & garb_mmacc_rd_avail_1h_dly[i];
      acc_wr_change[i]   = ~garb_mmacc_wr_avail_1h[i]   & garb_mmacc_wr_avail_1h_dly[i];
  end


  always_ff @(posedge clk)
    if (!s_rst_n) begin
      garb_mmfeed_rot_avail_1h_dly <= '0;
      garb_mmfeed_dat_avail_1h_dly <= '0;
      garb_mmacc_rd_avail_1h_dly   <= '0;
      garb_mmacc_wr_avail_1h_dly   <= '0;
      cycle_cnt                    <= '0;
      for (int i=0; i<GRAM_NB; i=i+1) begin
        feed_rot_cycle[i] <= '0;
        feed_dat_cycle[i] <= '0;
        acc_rd_cycle[i]   <= '0;
        acc_wr_cycle[i]   <= '0;
      end
    end
    else begin
      garb_mmfeed_rot_avail_1h_dly <= garb_mmfeed_rot_avail_1h;
      garb_mmfeed_dat_avail_1h_dly <= garb_mmfeed_dat_avail_1h;
      garb_mmacc_rd_avail_1h_dly   <= garb_mmacc_rd_avail_1h;
      garb_mmacc_wr_avail_1h_dly   <= garb_mmacc_wr_avail_1h;
      cycle_cnt                    <= cycle_cnt + 1;
      for (int i=0; i<GRAM_NB; i=i+1) begin
        feed_rot_cycle[i] <= garb_mmfeed_rot_avail_1h[i] ? feed_rot_cycle[i] + 1 : '0;
        feed_dat_cycle[i] <= garb_mmfeed_dat_avail_1h[i] ? feed_dat_cycle[i] + 1 : '0;
        acc_rd_cycle[i]   <= garb_mmacc_rd_avail_1h[i]   ? acc_rd_cycle[i] + 1 : '0;
        acc_wr_cycle[i]   <= garb_mmacc_wr_avail_1h[i]   ? acc_wr_cycle[i] + 1 : '0;
      end
    end

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      error_cycle <= '0;
    end
    else begin
      for (int i=0; i<GRAM_NB; i=i+1) begin
        if (feed_rot_change[i])
          assert(feed_rot_cycle[i] == GLWE_SLOT_NB*GARB_SLOT_CYCLE)
          else begin
            $display("%t > ERROR: Feed_rot has not been arbitrated GLWE_SLOT_NB(%0d)*GARB_SLOT_CYCLE(%0d) consecutive cycles (%0d) for gram %0d.",
                    $time,GLWE_SLOT_NB,GARB_SLOT_CYCLE,feed_rot_cycle[i],i);
            error_cycle <= 1'b1;
          end

        if (feed_dat_change[i])
          assert(feed_dat_cycle[i] == (GLWE_SLOT_NB+FEED_ADD_SLOT)*GARB_SLOT_CYCLE)
          else begin
            $display("%t > ERROR: Feed_dat has not been arbitrated (GLWE_SLOT_NB(%0d)+FEED_ADD_SLOT(%0d))*GARB_SLOT_CYCLE(%0d) consecutive cycles (%0d) for gram %0d.",
                    $time,GLWE_SLOT_NB,FEED_ADD_SLOT,GARB_SLOT_CYCLE,feed_dat_cycle[i],i);
            error_cycle <= 1'b1;
          end

        if (acc_rd_change[i])
          assert(acc_rd_cycle[i] == GLWE_SLOT_NB*GARB_SLOT_CYCLE)
          else begin
            $display("%t > ERROR: acc_rd has not been arbitrated GLWE_SLOT_NB(%0d)*GARB_SLOT_CYCLE(%0d) consecutive cycles (%0d) for gram %0d.",
                    $time,GLWE_SLOT_NB,GARB_SLOT_CYCLE,acc_rd_cycle[i],i);
            error_cycle <= 1'b1;
          end

        if (acc_wr_change[i])
          assert(acc_wr_cycle[i] == (GLWE_SLOT_NB+ACC_ADD_SLOT)*GARB_SLOT_CYCLE)
          else begin
            $display("%t > ERROR: acc_wr has not been arbitrated (GLWE_SLOT_NB(%0d)+ACC_ADD_SLOT(%0d))*GARB_SLOT_CYCLE(%0d) consecutive cycles (%0d) for gram %0d.",
                    $time,GLWE_SLOT_NB,ACC_ADD_SLOT,GARB_SLOT_CYCLE,acc_wr_cycle[i],i);
            error_cycle <= 1'b1;
          end

      end // for
    end // else

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      error_attribution <= 1'b0;
    end
    else begin
      assert($countones(garb_mmfeed_rot_avail_1h) <= 1)
      else begin
        $display("%t > ERROR: garb_mmfeed_rot_avail_1h is not a 1-hot", $time);
        error_attribution <= 1'b1;
      end
      assert($countones(garb_mmacc_rd_avail_1h) <= 1)
      else begin
        $display("%t > ERROR: garb_mmacc_rd_avail_1h is not a 1-hot", $time);
        error_attribution <= 1'b1;
      end

      for (int i=0; i<GRAM_NB; i=i+1) begin
        int cnt [1:0];
        cnt[0] = garb_mmfeed_rot_avail_1h[i]
              + garb_ldg_avail_1h[i]
              + garb_mmacc_rd_avail_1h[i];
        cnt[1] = garb_mmfeed_dat_avail_1h[i]
              + garb_mmsxt_avail_1h[i]
              + garb_mmacc_wr_avail_1h[i];
        assert(cnt[0] <= 1)
        else begin
          $display("%t > ERROR: More than 1 source was granted for PORT A", $time);
          error_attribution <= 1'b1;
        end
        assert(cnt[1] <= 1)
        else begin
          $display("%t > ERROR: More than 1 source was granted for PORT B", $time);
          error_attribution <= 1'b1;
        end

        // Opportunism
        if (cycle_cnt > 2*GARB_SLOT_CYCLE) begin
          assert(cnt[0] == 1 && cnt[1] == 1)
          else begin
            $display("%t > ERROR: Sxt and Ldg were not granted when possible", $time);
            error_attribution <= 1'b1;
          end
        end
      end
    end
endmodule
