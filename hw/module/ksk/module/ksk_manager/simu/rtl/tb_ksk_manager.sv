// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// ksk_manager testbench.
// ==============================================================================================

module tb_ksk_manager;
`timescale 1ns/10ps

  import param_tfhe_pkg::*;
  import pep_common_param_pkg::*;
  import pep_ks_common_param_pkg::*;
  import ksk_mgr_common_param_pkg::*;

// ============================================================================================== --
// localparam
// ============================================================================================== --
  parameter int RAM_LATENCY     = 1;

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int CLK_HALF_PERIOD = 1;
  localparam int ARST_ACTIVATION = 17;

  localparam int PROC_BATCH_NB  = 100;
  localparam int KSK_ERROR_NB   = 1;
  localparam int CMD_FIFO_DEPTH = BATCH_NB*2; // Same value as the one inside the ksk_manager

  localparam int RD_DELAY       = (2+1) + (1 + RAM_LATENCY + 1) + 1; // cmd FIFO  + read in RAM + input pipe

  localparam int RUN_BATCH_NB   = CMD_FIFO_DEPTH;

// ============================================================================================== --
// Type
// ============================================================================================== --
  typedef struct packed {
    logic [KS_BLOCK_LINE_W-1:0] bline;
    logic [KS_BLOCK_COL_W-1:0]  bcol;
    logic [KS_LG_W-1:0]         lg;
    logic [LBX_W-1:0]           x;
    logic [LBY_W-1:0]           y;
    logic [LBZ_W-1:0]           z;
  } data_t;

  typedef struct packed {
    logic [KSK_RAM_ADD_W-1:0]  wr_add;
    logic [LBX_W-1:0]          x_idx;
    logic [KSK_SLOT_W-1:0]     slot;
    logic [KS_BLOCK_COL_W-1:0] ks_loop;
  } wr_ctrl_t;

  typedef struct packed {
    integer batch_id;
    integer slot_id;
    integer ks_loop;
    integer pbs_nb;
  } cmd_t;


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
  bit error_data;
  bit error_vld_avail;

  assign error = error_data | error_vld_avail;

  always_ff @(posedge clk)
    if (error) begin
      $display("%t > FAILURE !", $time);
      $finish;
    end

// ============================================================================================== --
// input / output signals
// ============================================================================================== --

  logic [LBX-1:0][LBY-1:0][LBZ-1:0][MOD_KSK_W-1:0] ksk;
  logic [LBX-1:0][LBY-1:0]                         ksk_vld;
  logic [LBX-1:0][LBY-1:0]                         ksk_rdy;
  // Broadcast from acc
  ks_batch_cmd_t                                   batch_cmd;
  logic                                            batch_cmd_avail;

  // Write interface
  logic [KSK_CUT_NB-1:0]                                               wr_en;
  logic [KSK_CUT_NB-1:0][KSK_CUT_FCOEF_NB-1:0][LBZ-1:0][MOD_KSK_W-1:0] wr_data;
  logic [KSK_CUT_NB-1:0][KSK_RAM_ADD_W-1:0]                            wr_add;
  logic [KSK_CUT_NB-1:0][LBX_W-1:0]                                    wr_x_idx;
  logic [KSK_CUT_NB-1:0][KSK_SLOT_W-1:0]                               wr_slot;
  logic [KSK_CUT_NB-1:0][KS_BLOCK_COL_W-1:0]                           wr_ks_loop;

  // Error
  logic [KSK_ERROR_NB-1:0]                         ksk_error;

// ============================================================================================== --
// Design under test instance
// ============================================================================================== --
  ksk_manager #(
    .RAM_LATENCY(RAM_LATENCY)
  ) dut (
    .clk            (clk            ),
    .s_rst_n        (s_rst_n        ),

    .ksk            (ksk            ),
    .ksk_vld        (ksk_vld        ),
    .ksk_rdy        (ksk_rdy        ),

    .batch_cmd      (batch_cmd      ),
    .batch_cmd_avail(batch_cmd_avail),

    .wr_en          (wr_en          ),
    .wr_data        (wr_data        ),
    .wr_add         (wr_add         ),
    .wr_x_idx       (wr_x_idx       ),
    .wr_slot        (wr_slot        ),
    .wr_ks_loop     (wr_ks_loop     ),

    .error          (ksk_error      )

  );

// ============================================================================================== --
// Launch cmd
// ============================================================================================== --
// To simplify the test, each command will trigger the filling of a slot then the reading
// of this slot.
// The hit/miss aspect is not handled by the ksk_manager
  logic                      start;
  logic [TOTAL_BATCH_NB-1:0] batch_running_mh;
  cmd_t                      batch_running_cmd_a [TOTAL_BATCH_NB-1:0];
  logic [TOTAL_BATCH_NB-1:0] batch_running_mhD;
  cmd_t                      batch_running_cmd_aD [TOTAL_BATCH_NB-1:0];

  logic [TOTAL_BATCH_NB-1:0] batch_done_1h;
  logic                      do_batch_run;

  // random
  integer                    batch_run_rand;
  logic                      batch_do_run_rand;
  logic [TOTAL_BATCH_NB-1:0] batch_run_1h_rand;
  integer                    batch_run_pbs_nb_rand;

  assign batch_run_1h_rand = 1 << batch_run_rand;

  always_ff @(posedge clk) begin
    batch_run_rand        <= $urandom_range(0,TOTAL_BATCH_NB-1);
    batch_do_run_rand     <= $urandom_range(0,1);
    batch_run_pbs_nb_rand <= $urandom_range(1,BATCH_PBS_NB);
  end

  // Run batch
  integer batch_run_slot;
  integer batch_run_ks_loop;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      batch_run_slot    <= '0;
      batch_run_ks_loop <= '0;
    end
    else begin
      if (do_batch_run) begin
        batch_run_slot    <= batch_run_slot == KSK_SLOT_NB-1 ? '0 : batch_run_slot + 1;
        batch_run_ks_loop <= batch_run_ks_loop == KS_BLOCK_COL_NB-1 ? '0 : batch_run_ks_loop + 1;
      end
    end

  assign do_batch_run = start & batch_do_run_rand & ($countones(batch_running_mh) < RUN_BATCH_NB) & |(batch_run_1h_rand & ~batch_running_mh);

  cmd_t slot_fill_q[$];
  cmd_t batch_run_cmd;

  assign batch_run_cmd.batch_id = batch_run_rand;
  assign batch_run_cmd.slot_id  = batch_run_slot;
  assign batch_run_cmd.ks_loop  = batch_run_ks_loop;
  assign batch_run_cmd.pbs_nb   = batch_run_pbs_nb_rand;

  always_ff @(posedge clk)
    if (do_batch_run) begin
      slot_fill_q.push_back(batch_run_cmd);
    end

  assign batch_running_mhD = (batch_running_mh | ({TOTAL_BATCH_NB{do_batch_run}} & batch_run_1h_rand)) ^ batch_done_1h;

  always_comb
    for (int t=0; t<TOTAL_BATCH_NB; t=t+1)
      batch_running_cmd_aD[t] = do_batch_run && batch_run_1h_rand[t] ? batch_run_cmd : batch_running_cmd_a[t];

  always_ff @(posedge clk)
    if (!s_rst_n) batch_running_mh <= '0;
    else          batch_running_mh <= batch_running_mhD;

  always_ff @(posedge clk)
    batch_running_cmd_a <= batch_running_cmd_aD;

// ============================================================================================== --
// Fill the slot
// ============================================================================================== --
  logic slot_filling;
  cmd_t slot_fill_cmd;
  logic slot_filling_done;

  always_ff @(posedge clk)
    if (!s_rst_n)
      slot_filling <= 1'b0;
    else begin
      logic do_slot_filling;
      do_slot_filling = (~slot_filling & slot_fill_q.size() > 0);
      slot_filling  <= slot_filling_done ? 1'b0 :
                      do_slot_filling   ? 1'b1 : slot_filling;
      slot_fill_cmd <= do_slot_filling ? slot_fill_q.pop_front() : slot_fill_cmd;
    end

  // Counters
  integer slot_fill_bline;
  integer slot_fill_lg;
  integer slot_fill_x;
  integer slot_fill_cut;

  integer slot_fill_blineD;
  integer slot_fill_lgD;
  integer slot_fill_xD;
  integer slot_fill_cutD;

  logic slot_fill_last_bline;
  logic slot_fill_last_lg;
  logic slot_fill_last_x;
  logic slot_fill_last_cut;

  assign slot_fill_last_bline = slot_fill_bline == KS_BLOCK_LINE_NB-1;
  assign slot_fill_last_lg    = slot_fill_lg == KS_LG_NB-1;
  assign slot_fill_last_x     = slot_fill_x == LBX-1;
  assign slot_fill_last_cut   = slot_fill_cut == KSK_CUT_NB-1;

  assign slot_fill_lgD    = slot_filling ? slot_fill_last_lg ? '0 : slot_fill_lg + 1 : slot_fill_lg;
  assign slot_fill_cutD   = (slot_filling && slot_fill_last_lg) ? slot_fill_last_cut ? '0 : slot_fill_cut + 1 : slot_fill_cut;
  assign slot_fill_blineD = (slot_filling && slot_fill_last_lg && slot_fill_last_cut) ? slot_fill_last_bline ? '0 : slot_fill_bline + 1 : slot_fill_bline;
  assign slot_fill_xD     = (slot_filling && slot_fill_last_lg && slot_fill_last_cut && slot_fill_last_bline) ? slot_fill_last_x ? '0 : slot_fill_x + 1 : slot_fill_x;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      slot_fill_lg    <= '0;
      slot_fill_bline <= '0;
      slot_fill_x     <= '0;
      slot_fill_cut   <= '0;
    end
    else begin
      slot_fill_lg    <= slot_fill_lgD   ;
      slot_fill_bline <= slot_fill_blineD;
      slot_fill_x     <= slot_fill_xD    ;
      slot_fill_cut   <= slot_fill_cutD  ;
    end

  logic [LBY-1:0][LBZ-1:0][MOD_KSK_W-1:0] wr_data_tmp;
  logic [KSK_RAM_ADD_W-1:0]               wr_add_tmp;

  assign wr_en      = slot_filling << slot_fill_cut;
  assign wr_x_idx   = {KSK_CUT_NB{slot_fill_x[LBX_W-1:0]}};
  assign wr_slot    = {KSK_CUT_NB{slot_fill_cmd.slot_id}};
  assign wr_ks_loop = {KSK_CUT_NB{slot_fill_cmd.ks_loop}};
  assign wr_add_tmp = slot_fill_bline * KS_LG_NB + slot_fill_lg + slot_fill_cmd.slot_id* (KS_LG_NB*KS_BLOCK_LINE_NB);
  assign wr_add     = {KSK_CUT_NB{wr_add_tmp}};
  assign wr_data    = wr_data_tmp;

  always_comb
    for (int y=0; y<LBY; y=y+1) begin
      bit valid;
      valid = (y >= (slot_fill_cut * KSK_CUT_FCOEF_NB)) & (y < ((slot_fill_cut+1) * KSK_CUT_FCOEF_NB));
      for (int z=0; z<LBZ; z=z+1) begin
        data_t d;
        if (valid) begin
          d.bline = slot_fill_bline;
          d.bcol  = slot_fill_cmd.ks_loop;
          d.x     = slot_fill_x;
          d.y     = y;
          d.z     = z;
          d.lg    = slot_fill_lg;
        end
        else
          d = 'x;
        wr_data_tmp[y][z] = d;
      end
    end

  cmd_t read_cmd_q [$];

  always_ff @(posedge clk)
    if (slot_filling && slot_fill_last_cut && slot_fill_last_bline && slot_fill_last_lg && slot_fill_last_x)
      read_cmd_q.push_back(slot_fill_cmd);

  assign slot_filling_done = (slot_filling & slot_fill_last_cut & slot_fill_last_bline & slot_fill_last_lg & slot_fill_last_x);

// ============================================================================================== --
// Read the slot
// ============================================================================================== --
  cmd_t sample_cmd_q[$];
  cmd_t check_cmd_q[$];
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      batch_cmd_avail <= 1'b0;
      batch_cmd       <= 'x;
    end
    else begin
      if (read_cmd_q.size() > 0) begin
        cmd_t c;
        c = read_cmd_q.pop_front();
        batch_cmd_avail   <= 1'b1;
        batch_cmd.pbs_nb  <= c.pbs_nb;
        batch_cmd.ks_loop <= c.ks_loop;
        sample_cmd_q.push_back(c);
        check_cmd_q.push_back(c);
      end
      else begin
        batch_cmd_avail <= 1'b0;
        batch_cmd       <= 'x;
      end
    end

  // Do not read right away. Let the ksk_manager fill its pipe.
  logic [RD_DELAY-1:0] batch_cmd_avail_dly;
  logic [RD_DELAY-1:0] batch_cmd_avail_dlyD;

  assign batch_cmd_avail_dlyD = {batch_cmd_avail_dly[RD_DELAY-2:0],batch_cmd_avail};
  always_ff @(posedge clk)
    if (!s_rst_n) batch_cmd_avail_dly <= '0;
    else          batch_cmd_avail_dly <= batch_cmd_avail_dlyD;

// ============================================================================================== --
// Sample the KSK
// ============================================================================================== --
  logic do_sample_0; // Data are ready to be sampled
  assign do_sample_0 = batch_cmd_avail_dly[RD_DELAY-1];

  logic do_sample_q[$];
  always_ff @(posedge clk)
    if (do_sample_0)
      do_sample_q.push_back(1);

  // Random
  logic ksk_rdy_00_rand;
  always_ff @(posedge clk)
    ksk_rdy_00_rand <= $urandom_range(0,1);

  // Counters
  integer sample_pbs_id;
  integer sample_lg;
  integer sample_bline;

  logic ksk_rdy_00;

  // Define the counters along with the control to avoid race condition on the queues.
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      sample_pbs_id <= '0;
      sample_lg     <= '0;
      sample_bline  <= '0;
      ksk_rdy_00    <= 1'b0;
    end
    else begin
      logic sample_last_lg;
      logic sample_last_pbs_id;
      logic sample_last_bline;

      sample_last_lg     = sample_lg == KS_LG_NB-1;
      sample_last_pbs_id = (sample_pbs_id == sample_cmd_q[0].pbs_nb-1);
      sample_last_bline  = sample_bline == KS_BLOCK_LINE_NB - 1;
      if (ksk_vld[0][0] && ksk_rdy[0][0]) begin
        sample_lg     <= sample_last_lg ? '0 : sample_lg + 1;
        sample_pbs_id <= sample_last_lg ? sample_last_pbs_id ? '0 : sample_pbs_id + 1 : sample_pbs_id;
        sample_bline  <= sample_last_lg && sample_last_pbs_id ? sample_last_bline ?  '0 : sample_bline + 1 : sample_bline;

        //$display("%t > batch_id=%0d pbs_nb=%0d sample_lg=%0d sample_pbs_id=%0d sample_bline=%0d sample_last_lg=%0b sample_last_pbs_id=%0b sample_last_bline=%0b size=%0d",
        //          $time,sample_cmd_q[0].batch_id,sample_cmd_q[0].pbs_nb,sample_lg,sample_pbs_id,sample_bline,
        //          sample_last_lg, sample_last_pbs_id, sample_last_bline,do_sample_q.size());
      end

      // ksk_rdy_00
      ksk_rdy_00 <= (do_sample_q.size() > 0) & ksk_rdy_00_rand & ~(sample_last_lg & sample_last_pbs_id & sample_last_bline & ksk_rdy_00);

      // Last element
      if (ksk_rdy_00 && sample_last_lg && sample_last_pbs_id && sample_last_bline) begin
        sample_cmd_q.pop_front();
        do_sample_q.pop_front();
      end
    end


  logic [LBY-1:1] ksk_rdy_tmp_y;
  always_ff @(posedge clk)
    if (!s_rst_n) ksk_rdy_tmp_y <= '0;
    else          ksk_rdy_tmp_y <= {ksk_rdy_tmp_y[LBY-2:1],ksk_rdy_00};

  generate
    if (LBX == 1) begin
      assign ksk_rdy[0] = {ksk_rdy_tmp_y,ksk_rdy_00};
    end
    else if (LBX == 2) begin
      logic [LBX-1:1][LBY-1:0] ksk_rdy_tmp_x;
      always_ff @(posedge clk)
        if (!s_rst_n) ksk_rdy_tmp_x <= '0;
        else          ksk_rdy_tmp_x <= {ksk_rdy_tmp_y,ksk_rdy_00};
      assign ksk_rdy = {ksk_rdy_tmp_x,ksk_rdy_tmp_y,ksk_rdy_00};
    end
    else begin // LBX > 2
      logic [LBX-1:1][LBY-1:0] ksk_rdy_tmp_x;
      always_ff @(posedge clk)
        if (!s_rst_n) ksk_rdy_tmp_x <= '0;
        else          ksk_rdy_tmp_x <= {ksk_rdy_tmp_x[LBX-2:1],ksk_rdy_tmp_y,ksk_rdy_00};
      assign ksk_rdy = {ksk_rdy_tmp_x,ksk_rdy_tmp_y,ksk_rdy_00};
    end
  endgenerate

// ============================================================================================== --
// Check
// ============================================================================================== --
// Check the presence of the valid
  always_ff @(posedge clk)
    if (!s_rst_n) error_vld_avail <= 1'b0;
    else begin
      for (int x=0; x<LBX; x=x+1)
        for (int y=0; y<LBY; y=y+1)
          if (ksk_rdy[x][y] && !ksk_vld[x][y]) begin
            $display("%t > ERROR: ksk_vld[%0d][%0d] null when needed.",$time, x,y);
            error_vld_avail <= 1'b1;
          end
    end // else

// Check the ksk values
  // Check the value when the last Y arrives
  // data queue
  logic [LBZ-1:0][MOD_KSK_W-1:0] ksk_q[LBX-1:0][LBY-1:0][$];
  always_ff @(posedge clk)
    for (int x=0; x<LBX; x=x+1)
      for (int y=0; y<LBY; y=y+1)
        if (ksk_vld[x][y] && ksk_rdy[x][y])
          ksk_q[x][y].push_back(ksk[x][y]);


  // Counters
  integer check_pbs_id;
  integer check_lg;
  integer check_bline;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      check_pbs_id <= '0;
      check_lg     <= '0;
      check_bline  <= '0;
      error_data   <= '0;
      batch_done_1h <= '0;
    end
    else begin
      batch_done_1h <= '0;
      if (ksk_q[LBX-1][LBY-1].size() > 0) begin
        logic check_last_lg;
        logic check_last_pbs_id;
        logic check_last_bline;

        logic [LBX-1:0][LBY-1:0][LBZ-1:0][MOD_KSK_W-1:0] proc_ksk;

        // Counters
        check_last_lg     = check_lg     == KS_LG_NB-1;
        check_last_pbs_id = check_pbs_id == check_cmd_q[0].pbs_nb -1;
        check_last_bline  = check_bline  == KS_BLOCK_LINE_NB-1;
        check_lg     <= check_last_lg ? '0 : check_lg + 1;
        check_pbs_id <= check_last_lg ? check_last_pbs_id ? '0 : check_pbs_id + 1 : check_pbs_id;
        check_bline  <= check_last_lg && check_last_pbs_id ? check_last_bline ? '0 : check_bline + 1 : check_bline;

        for (int x=0; x<LBX; x=x+1)
          for (int y=0; y<LBY; y=y+1) begin
            data_t ref_d;
            ref_d.bline = check_bline;
            ref_d.bcol  = check_cmd_q[0].ks_loop;
            ref_d.lg    = check_lg;
            ref_d.x     = x;
            ref_d.y     = y;

            proc_ksk[x][y] = ksk_q[x][y].pop_front();

            for (int z=0; z<LBZ; z=z+1) begin
              ref_d.z     = z;
              assert(ref_d == proc_ksk[x][y][z])
              else begin
                $display("%t > ERROR: batch_id=%0d bline=%0d bcol=%0d lg=%0d Data [%0d][%0d][%0d] mismatch exp=0x%0x seen=0x%0x",
                        $time,check_cmd_q[0].batch_id,check_bline, check_cmd_q[0].ks_loop, check_lg, x,y,z,ref_d, proc_ksk[x][y][z]);
                error_data <= 1'b1;
              end // else
            end // z
          end // y


        if (check_last_lg && check_last_pbs_id && check_last_bline) begin
          batch_done_1h <= (1 << check_cmd_q[0].batch_id);
          check_cmd_q.pop_front();
        end
      end
    end

// ============================================================================================== --
// End of test
// ============================================================================================== --
  integer out_batch_cnt;

  always_ff @(posedge clk)
    if (!s_rst_n) out_batch_cnt <= '0;
    else          out_batch_cnt <= |batch_done_1h ? out_batch_cnt + 1 : out_batch_cnt;

  initial begin
    start = 1'b0;
    wait(s_rst_n);
    repeat (10) @(posedge clk);
    start = 1'b1;
  end


  initial begin
    end_of_test = 1'b0;
    wait(s_rst_n);
    wait(out_batch_cnt == PROC_BATCH_NB);
    @(posedge clk);
    end_of_test = 1'b1;
  end
endmodule
