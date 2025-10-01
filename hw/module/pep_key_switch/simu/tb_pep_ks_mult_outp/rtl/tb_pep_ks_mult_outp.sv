// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module tests pep_ks_mult + pep_ks_out_process.
// ==============================================================================================

module tb_pep_ks_mult_outp;
  import param_tfhe_pkg::*;
  import pep_common_param_pkg::*;
  import pep_ks_common_param_pkg::*;

  `timescale 1ns/10ps
// ============================================================================================== --
// localparam / parameter
// ============================================================================================== --
  parameter  int OP_W             = MOD_KSK_W;
  parameter  int BLWE_RAM_DEPTH   = (BLWE_K+LBY-1)/LBY * BATCH_PBS_NB * TOTAL_BATCH_NB;
  localparam int BLWE_RAM_ADD_W   = $clog2(BLWE_RAM_DEPTH);
  parameter  int DATA_LATENCY     = 6; // BLRAM access read latency
  parameter  int RAM_LATENCY      = 2;

  localparam int CLK_HALF_PERIOD = 1;
  localparam int ARST_ACTIVATION = 17;

  parameter  int PROC_BATCH_NB     = 100;

  parameter  int BATCH_IN_PARALLEL = TOTAL_BATCH_NB;

  localparam int OUT_FIFO_DEPTH = 4;
  localparam int DROP_COL_NB    = LBX == 1 ? 0 : (LBX - (LWE_K_P1 % LBX)) % LBX;
  initial begin
    $display("DROP_COL_NB=%0d",DROP_COL_NB);
  end

// ============================================================================================== --
// structure
// ============================================================================================== --
  typedef struct packed {
    logic [KS_BLOCK_COL_W-1:0]   bcol;
    logic [BPBS_ID_W-1:0]        pbs_id;
    logic                        eol;
    logic                        eoy;
    logic                        last_iter;
    logic [TOTAL_BATCH_NB_W-1:0] batch_id;
  } info_t;


// ============================================================================================== --
// function
// ============================================================================================== --

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
  bit [LBX-1:0] error_mult_node;
  bit [LBX-1:0] error_mult_out;
  bit           error_mult;
  bit [TOTAL_BATCH_NB-1:0] error_out_process;
  bit [TOTAL_BATCH_NB-1:0] error_out_body;

  assign error = |error_mult_node | |error_mult_out | error_mult | |error_out_process | |error_out_body;

  always_ff @(posedge clk)
    if (error) begin
      $display("%t > error_mult=%1d",$time, error_mult);
      $display("%t > error_mult_out=b%0b",$time, error_mult_out);
      $display("%t > error_mult_node=b%0b",$time, error_mult_node);
      $display("%t > error_out_process=b%04b",$time, error_out_process);
      $display("%t > error_out_body=b%04b",$time, error_out_body);
      $display("%t > FAILURE !", $time);
      $finish;
    end

// ============================================================================================== --
// input / output signals
// ============================================================================================== --
  logic [LBY-1:0][LBZ-1:0][KS_B_W-1:0]        ctrl_mult_data;
  logic [LBY-1:0][LBZ-1:0]                    ctrl_mult_sign;
  logic [LBY-1:0]                             ctrl_mult_avail;

  // Information of the last coefficient. Sent at the same time of
  // this coefficient.
  logic                                       ctrl_mult_last_eol;
  logic                                       ctrl_mult_last_eoy;
  logic                                       ctrl_mult_last_last_iter; // last iteration within the column
  logic [TOTAL_BATCH_NB_W-1:0]                ctrl_mult_last_batch_id;

  logic [LBX-1:0][LBY-1:0][LBZ-1:0][OP_W-1:0] ksk;
  logic [LBX-1:0][LBY-1:0]                    ksk_vld;
  logic [LBX-1:0][LBY-1:0]                    ksk_rdy;

  logic [LBX-1:0][OP_W-1:0]                   mult_outp_data;
  logic [LBX-1:0]                             mult_outp_avail;
  logic [LBX-1:0]                             mult_outp_last_pbs;
  logic [LBX-1:0][TOTAL_BATCH_NB_W-1:0]       mult_outp_batch_id;

  // body
  logic [TOTAL_BATCH_NB-1:0][OP_W-1:0]        bfifo_outp_data;
  logic [TOTAL_BATCH_NB-1:0][PID_W-1:0]       bfifo_outp_pid;
  logic [TOTAL_BATCH_NB-1:0]                  bfifo_outp_vld;
  logic [TOTAL_BATCH_NB-1:0]                  bfifo_outp_rdy;

  // LWE coeff
  logic [TOTAL_BATCH_NB-1:0][LWE_COEF_W-1:0]  br_proc_lwe;
  logic [TOTAL_BATCH_NB-1:0][KS_CORR_W-1:0]   br_proc_corr; // mean compensation correction
  logic [TOTAL_BATCH_NB-1:0]                  br_proc_vld;
  logic [TOTAL_BATCH_NB-1:0]                  br_proc_rdy;

  // Wr access to body RAM
  logic [TOTAL_BATCH_NB-1:0]                  br_bfifo_wr_en;
  logic [TOTAL_BATCH_NB-1:0][OP_W-1:0]        br_bfifo_data;

  // BCOL done
  logic [TOTAL_BATCH_NB-1:0]                  outp_ks_loop_done_mh;
  logic [TOTAL_BATCH_NB-1:0]                  inc_ksk_rd_ptr;


  logic                                       reset_cache;

  assign reset_cache = 1'b0; // TODO : not tested here.

// ============================================================================================== --
// Design under test instance
// ============================================================================================== --
  pep_ks_mult
  #(
    .OP_W (OP_W)
  ) pep_ks_mult (
    .clk                        (clk),
    .s_rst_n                    (s_rst_n),

    .ctrl_mult_data             (ctrl_mult_data),
    .ctrl_mult_sign             (ctrl_mult_sign),
    .ctrl_mult_avail            (ctrl_mult_avail),


    .ctrl_mult_last_eol         (ctrl_mult_last_eol),
    .ctrl_mult_last_eoy         (ctrl_mult_last_eoy),
    .ctrl_mult_last_last_iter   (ctrl_mult_last_last_iter),
    .ctrl_mult_last_batch_id    (ctrl_mult_last_batch_id),

    .ksk                        (ksk),
    .ksk_vld                    (ksk_vld),
    .ksk_rdy                    (ksk_rdy),

    .mult_outp_data             (mult_outp_data),
    .mult_outp_avail            (mult_outp_avail),
    .mult_outp_last_pbs         (mult_outp_last_pbs),
    .mult_outp_batch_id         (mult_outp_batch_id),

    .error                      (error_mult)
  );

  pep_ks_out_process
  #(
    .OP_W           (OP_W)
  ) pep_ks_out_process (
    .clk                   (clk),
    .s_rst_n               (s_rst_n),

    .mult_outp_data        (mult_outp_data),
    .mult_outp_avail       (mult_outp_avail),
    .mult_outp_last_pbs    (mult_outp_last_pbs),
    .mult_outp_batch_id    (mult_outp_batch_id),

    .bfifo_outp_data       (bfifo_outp_data),
    .bfifo_outp_pid        (bfifo_outp_pid),
    .bfifo_outp_vld        (bfifo_outp_vld),
    .bfifo_outp_rdy        (bfifo_outp_rdy),

    .br_proc_lwe           (br_proc_lwe),
    .br_proc_corr          (br_proc_corr),
    .br_proc_vld           (br_proc_vld),
    .br_proc_rdy           (br_proc_rdy),

    .br_bfifo_wr_en        (br_bfifo_wr_en),
    .br_bfifo_data         (br_bfifo_data),
    .br_bfifo_pid          (/*UNUSED*/), // Not tested here
    .br_bfifo_parity       (/*UNUSED*/), // Not tested here

    .reset_cache           (reset_cache),
    .outp_ks_loop_done_mh  (outp_ks_loop_done_mh),
    .inc_ksk_rd_ptr        (inc_ksk_rd_ptr      )
  );

// ============================================================================================== --
// Scenario
// ============================================================================================== --
//---------------------------------------------------
// Mult data input
//---------------------------------------------------
  logic [LBZ-1:0][KS_B_W-1:0] in_data_0;
  logic [LBZ-1:0]             in_sign_0;
  logic                       in_avail_0;
  logic                       in_eol_0;
  logic                       in_eoy_0;
  logic                       in_last_iter_0;

  integer                     in_bline_cnt;
  integer                     in_bcol_cnt;
  integer                     in_lvl_cnt;
  integer                     in_pbs_id;
  integer                     in_bline_cntD;
  integer                     in_lvl_cntD;
  integer                     in_pbs_idD;
  logic                       in_last_pbs_cnt;
  logic                       in_last_lvl_cnt;
  logic                       in_last_bline_cnt;
  logic                       in_last_bcol_cnt;

  bit                         in_run_column;
  bit                         in_run_column_rand;
  bit                         in_run_columnD;
  bit                         in_run_columnD_tmp;
  integer                     in_run_pbs_nb;
  integer                     in_run_pbs_nb_rand;
  integer                     in_run_batch_id;
  integer                     in_run_batch_id_rand;
  integer                     in_slot_rand;

  logic                       start;

  integer                     in_slot;
  integer                     in_slot_batch_id [BATCH_NB-1:0];
  integer                     in_slot_pbs_nb [BATCH_NB-1:0];
  integer                     in_slot_bcol [BATCH_NB-1:0];

  integer                     in_slotD;
  integer                     in_slot_batch_idD [BATCH_NB-1:0];
  integer                     in_slot_pbs_nbD [BATCH_NB-1:0];
  integer                     in_slot_bcolD [BATCH_NB-1:0];

  logic                       in_run_col_done;
  logic                       in_run_sample;

  // Random
  always_ff @(posedge clk) begin
    in_run_column_rand   <= $urandom_range(0,1);
    in_run_pbs_nb_rand   <= $urandom_range(1,BATCH_PBS_NB);
    in_run_batch_id_rand <= $urandom_range(0,TOTAL_BATCH_NB-1);
    in_slot_rand         <= $urandom_range(0,BATCH_NB-1);
    in_data_0            <= $urandom;
    in_sign_0            <= $urandom;
  end

  // Slot
  assign in_run_col_done = (in_run_column & in_last_lvl_cnt & in_last_pbs_cnt & in_last_bline_cnt);
  assign in_run_sample   = ~in_run_column | in_run_col_done;
  assign in_slotD        = in_run_sample ? in_slot_rand : in_slot;

  always_comb begin
    for (int i=0; i<BATCH_NB; i=i+1) begin
      integer j;
      j = (i+1) % BATCH_NB;
      if (in_run_col_done && in_slot == i && in_last_bcol_cnt) begin
        // simplification done for BATCH_NB == 2

        in_slot_batch_idD[i] = (in_run_batch_id_rand == in_slot_batch_id[j]) ? (in_run_batch_id_rand + 1) % TOTAL_BATCH_NB : in_run_batch_id_rand;
        in_slot_pbs_nbD[i]   = in_run_pbs_nb_rand;
      end
      else begin
        in_slot_batch_idD[i] = in_slot_batch_id[i];
        in_slot_pbs_nbD[i]   = in_slot_pbs_nb[i];
      end
    end
  end

  always_comb
    for (int i=0; i<BATCH_NB; i=i+1)
      if (in_run_col_done && in_slot == i)
        in_slot_bcolD[i] = in_last_bcol_cnt ? '0 : in_slot_bcol[i] + 1;
      else
        in_slot_bcolD[i] = in_slot_bcol[i];

  // Count the number of input batches
  integer in_batch_cnt;
  always_ff @(posedge clk)
    if (!s_rst_n) in_batch_cnt <= '0;
    else          in_batch_cnt <= (in_run_col_done && in_last_bcol_cnt) ? in_batch_cnt + 1 : in_batch_cnt;

  // Block column counters
  assign in_run_pbs_nb   = in_slot_pbs_nb[in_slot];
  assign in_run_batch_id = in_slot_batch_id[in_slot];
  assign in_bcol_cnt     = in_slot_bcol[in_slot];

  assign in_last_pbs_cnt   = in_pbs_id == (in_run_pbs_nb-1);
  assign in_last_lvl_cnt   = in_lvl_cnt == KS_LG_NB-1;
  assign in_last_bline_cnt = in_bline_cnt == KS_BLOCK_LINE_NB-1;
  assign in_last_bcol_cnt  = in_bcol_cnt == KS_BLOCK_COL_NB-1;

  assign in_run_columnD_tmp = in_run_sample ? in_run_column_rand : in_run_column;
  assign in_run_columnD     = start & in_run_columnD_tmp;
  assign in_lvl_cntD        = in_run_column ? in_last_lvl_cnt ? '0 : in_lvl_cnt + 1 : in_lvl_cnt;
  assign in_pbs_idD         = in_run_column && in_last_lvl_cnt ? in_last_pbs_cnt ? '0 : in_pbs_id + 1 : in_pbs_id;
  assign in_bline_cntD      = in_run_column && in_last_lvl_cnt && in_last_pbs_cnt ? in_last_bline_cnt ? '0 : in_bline_cnt + 1 : in_bline_cnt;

  assign in_avail_0     = in_run_column;
  assign in_eol_0       = in_last_lvl_cnt;
  assign in_eoy_0       = in_last_pbs_cnt;
  assign in_last_iter_0 = in_last_bline_cnt;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      in_run_column <= 1'b0;
      in_lvl_cnt    <= '0;
      in_pbs_id     <= '0;
      in_bline_cnt  <= '0;
      in_slot       <= '0;
      for (int i=0; i<BATCH_NB; i=i+1) begin
        in_slot_batch_id[i] <= i;
        in_slot_bcol[i]     <= 0;
        in_slot_pbs_nb[i]   <= 1;
      end
    end
    else begin
      in_run_column    <= in_run_columnD;
      in_lvl_cnt       <= in_lvl_cntD  ;
      in_pbs_id        <= in_pbs_idD  ;
      in_bline_cnt     <= in_bline_cntD;
      in_slot          <= in_slotD;
      in_slot_batch_id <= in_slot_batch_idD;
      in_slot_bcol     <= in_slot_bcolD    ;
      in_slot_pbs_nb   <= in_slot_pbs_nbD  ;
    end

  // Design input assignment
  logic [LBY-1:0][LBZ-1:0][KS_B_W-1:0] sr_ctrl_mult_data;
  logic [LBY-1:0][LBZ-1:0]             sr_ctrl_mult_sign;
  logic [LBY-1:0]                      sr_ctrl_mult_avail;

  logic [LBY-1:0]                      sr_ctrl_mult_eol;
  logic [LBY-1:0]                      sr_ctrl_mult_eoy;
  logic [LBY-1:0]                      sr_ctrl_mult_last_iter;
  logic [LBY-1:0][TOTAL_BATCH_NB_W-1:0]sr_ctrl_mult_batch_id;

  logic [LBY-1:0][LBZ-1:0][KS_B_W-1:0] sr_ctrl_mult_dataD;
  logic [LBY-1:0][LBZ-1:0]             sr_ctrl_mult_signD;
  logic [LBY-1:0]                      sr_ctrl_mult_availD;

  logic [LBY-1:0]                      sr_ctrl_mult_eolD;
  logic [LBY-1:0]                      sr_ctrl_mult_eoyD;
  logic [LBY-1:0]                      sr_ctrl_mult_last_iterD;
  logic [LBY-1:0][TOTAL_BATCH_NB_W-1:0]sr_ctrl_mult_batch_idD;

  assign sr_ctrl_mult_dataD      = {sr_ctrl_mult_data[LBY-2:0],in_data_0};
  assign sr_ctrl_mult_signD      = {sr_ctrl_mult_sign[LBY-2:0],in_sign_0};
  assign sr_ctrl_mult_availD     = {sr_ctrl_mult_avail[LBY-2:0],in_avail_0};
  assign sr_ctrl_mult_eolD       = {sr_ctrl_mult_eol[LBY-2:0],in_eol_0};
  assign sr_ctrl_mult_eoyD       = {sr_ctrl_mult_eoy[LBY-2:0],in_eoy_0};
  assign sr_ctrl_mult_last_iterD = {sr_ctrl_mult_last_iter[LBY-2:0],in_last_iter_0};
  assign sr_ctrl_mult_batch_idD  = {sr_ctrl_mult_batch_id[LBY-2:0],in_run_batch_id[TOTAL_BATCH_NB_W-1:0]};

  always_ff @(posedge clk)
    if (!s_rst_n) sr_ctrl_mult_avail <= '0;
    else          sr_ctrl_mult_avail <= sr_ctrl_mult_availD;

  always_ff @(posedge clk) begin
    sr_ctrl_mult_data      <= sr_ctrl_mult_dataD;
    sr_ctrl_mult_sign      <= sr_ctrl_mult_signD;
    sr_ctrl_mult_eol       <= sr_ctrl_mult_eolD;
    sr_ctrl_mult_eoy       <= sr_ctrl_mult_eoyD;
    sr_ctrl_mult_last_iter <= sr_ctrl_mult_last_iterD;
    sr_ctrl_mult_batch_id  <= sr_ctrl_mult_batch_idD;
  end

  assign ctrl_mult_data           = sr_ctrl_mult_data;
  assign ctrl_mult_sign           = sr_ctrl_mult_sign;
  assign ctrl_mult_avail          = sr_ctrl_mult_avail;
  assign ctrl_mult_last_eol       = sr_ctrl_mult_eol[LBY-1];
  assign ctrl_mult_last_eoy       = sr_ctrl_mult_eoy[LBY-1];
  assign ctrl_mult_last_last_iter = sr_ctrl_mult_last_iter[LBY-1];
  assign ctrl_mult_last_batch_id  = sr_ctrl_mult_batch_id[LBY-1];

//---------------------------------------------------
// Ksk
//---------------------------------------------------
  generate
    for (genvar gen_x=0; gen_x<LBX; gen_x=gen_x+1) begin : gen_ksk_x
      for (genvar gen_y=0; gen_y<LBY; gen_y=gen_y+1)  begin : gen_ksk_y

        stream_source
        #(
          .FILENAME   ("random"),
          .DATA_TYPE  ("ascii_hex"),
          .DATA_W     (LBZ*OP_W),
          .RAND_RANGE (1),
          .KEEP_VLD   (1),
          .MASK_DATA  ("x")
        )
        source_ksk
        (
          .clk        (clk),
          .s_rst_n    (s_rst_n),

          .data       (ksk[gen_x][gen_y]),
          .vld        (ksk_vld[gen_x][gen_y]),
          .rdy        (ksk_rdy[gen_x][gen_y]),

          .throughput (1'b1)
        );

        initial begin
          if (!source_ksk.open()) begin
            $fatal(1, "%t > ERROR: Opening source_ksk stream source", $time);
          end
          source_ksk.start(0);
        end

      end
    end
  endgenerate

//---------------------------------------------------
// bfifo
//---------------------------------------------------
  generate
    for (genvar gen_i=0; gen_i<TOTAL_BATCH_NB; gen_i=gen_i+1) begin : gen_bfifo
      logic [OP_W-1:0]  body_data;
      logic             body_vld;
      logic             body_rdy;

      logic             body_fifo_rdy;
      logic             body_fifo_vld;

      stream_source
      #(
        .FILENAME   ("random"),
        .DATA_TYPE  ("ascii_hex"),
        .DATA_W     (OP_W),
        .RAND_RANGE (1),
        .KEEP_VLD   (1),
        .MASK_DATA  ("x")
      )
      source_bfifo_outp
      (
        .clk        (clk),
        .s_rst_n    (s_rst_n),

        .data       (body_data),
        .vld        (body_vld),
        .rdy        (body_rdy),

        .throughput (1'b1)
      );

      initial begin
        if (!source_bfifo_outp.open()) begin
          $fatal(1, "%t > ERROR: Opening source_bfifo_outp stream source", $time);
        end
        source_bfifo_outp.start(0);
      end

      assign body_fifo_vld = body_vld
                           & in_avail_0
                           & in_eol_0
                           & in_last_bline_cnt
                           & in_last_bcol_cnt;

      fifo_reg #(
        .WIDTH(OP_W + PID_W)
      ) body_fifo (
        .clk      ( clk                                      ) ,
        .s_rst_n  ( s_rst_n                                  ) ,
        .in_data  ( {body_data, PID_W'(in_run_pbs_nb)}       ) ,
        .in_vld   ( body_fifo_vld                            ) ,
        .in_rdy   ( body_fifo_rdy                            ) ,
        .out_data ( {bfifo_outp_data[gen_i], bfifo_outp_pid} ) ,
        .out_vld  ( bfifo_outp_vld[gen_i]                    ) ,
        .out_rdy  ( bfifo_outp_rdy[gen_i]                    )
      );

      always @(posedge clk) if(s_rst_n) begin
        assert_body_fifo_stall:
        assert(body_fifo_rdy && body_fifo_vld || !body_fifo_vld)
        else $fatal(1, "Error> The body fifo [%0d] stalled at %0t",
                       gen_i, $realtime);
      end
    end
  endgenerate


//---------------------------------------------------
// br proc
//---------------------------------------------------
  assign br_proc_rdy = '1; // TODO

// ============================================================================================== --
// Check
// ============================================================================================== --
  logic [LBZ-1:0][KS_B_W-1:0] ctrl_mult_data_q     [LBX-1:0][LBY-1:0][$];
  logic [LBZ-1:0]             ctrl_mult_sign_q     [LBX-1:0][LBY-1:0][$];
  logic [TOTAL_BATCH_NB_W-1:0]ctrl_mult_batch_id_q [$];
  integer                     in_pbs_id_q            [LBX-1:0][$];
  info_t                      in_info_q              [LBX-1:0][$];

  logic [LBZ-1:0][OP_W-1:0]   ksk_q                  [LBX-1:0][LBY-1:0][$];
  logic [OP_W-1:0]            node_res_q             [LBX-1:0][BATCH_PBS_NB-1:0][$];
  info_t                      mult_info_q            [LBX-1:0][$];
  logic [OP_W-1:0]            mult_res_q             [LBX-1:0][TOTAL_BATCH_NB-1:0][$];


  always_ff @(posedge clk)
    if (in_avail_0)
      for (int x=0; x<LBX; x=x+1) begin
        info_t info;
        info.eol       = in_eol_0;
        info.eoy       = in_eoy_0;
        info.last_iter = in_last_iter_0;
        info.batch_id  = in_run_batch_id;
        info.pbs_id    = in_pbs_id;
        info.bcol      = in_bcol_cnt;

        in_info_q[x].push_back(info);
        in_pbs_id_q[x].push_back(in_pbs_id);
      end

  always_ff @(posedge clk)
    for (int y=0; y<LBY; y=y+1) begin
      if (ctrl_mult_avail[y]) begin
        for (int x=0; x<LBX; x=x+1) begin
          ctrl_mult_data_q[x][y].push_back(ctrl_mult_data[y]);
          ctrl_mult_sign_q[x][y].push_back(ctrl_mult_sign[y]);
        end
      end
      for (int x=0; x<LBX; x=x+1)
        if (ksk_vld[x][y] && ksk_rdy[x][y])
          ksk_q[x][y].push_back(ksk[x][y]);
    end // for y


  generate
    for (genvar gen_x=0; gen_x < LBX; gen_x=gen_x+1) begin : gen_check_mult_node_loop
      //------------------------------
      // Check Mult Node
      //------------------------------
      bit error_mult_node_local;
      assign error_mult_node[gen_x] = error_mult_node_local;

      always_ff @(posedge clk)
        if (!s_rst_n) begin
          error_mult_node_local <= '0;
        end
        else begin
          if (pep_ks_mult.gen_node_x_loop[gen_x].s0_node_res_avail) begin
            logic [LBZ-1:0][KS_B_W-1:0] data_a;
            logic [LBZ-1:0]             sign_a;
            logic [LBZ-1:0][OP_W-1:0]   ksk_a;
            logic [OP_W-1:0]            ref_node_res;
            info_t                      ref_node_info;

            ref_node_info = in_info_q[gen_x].pop_front();
            ref_node_res = '0;
            for (int y=0; y<LBY; y=y+1) begin
              data_a = ctrl_mult_data_q[gen_x][y].pop_front();
              sign_a = ctrl_mult_sign_q[gen_x][y].pop_front();
              ksk_a  = ksk_q[gen_x][y].pop_front();
              for (int z=0; z<LBZ; z=z+1) begin
                //$display("[%0d,%0d,%0d] pbs_id=%0d sign=%1b data=0x%0x ksk=0x%0x",gen_x, y, z, ref_node_info.pbs_id,sign_a[z], data_a[z], ksk_a[z]);
                ref_node_res = ref_node_res + (-1)**sign_a[z] * data_a[z] * ksk_a[z];
              end
            end

            // Prepare ref for mult output
            node_res_q[gen_x][ref_node_info.pbs_id].push_back(ref_node_res);
            if (ref_node_info.eol && ref_node_info.last_iter) begin
              mult_info_q[gen_x].push_back(ref_node_info);
            end

            // check node result
            assert(pep_ks_mult.gen_node_x_loop[gen_x].s0_node_result == ref_node_res)
            else begin
              $display("%t > ERROR: Mult_node[x=%0d] output mismatches. exp=0x%0x seen=0x%0x.",$time, gen_x,ref_node_res,pep_ks_mult.gen_node_x_loop[gen_x].s0_node_result);
              error_mult_node_local <= 1'b1;
            end

            // check node eol
            assert(pep_ks_mult.gen_node_x_loop[gen_x].s0_node_res_info.eol == ref_node_info.eol)
            else begin
              $display("%t > ERROR: Mult_node[x=%0d] eol mismatches. exp=0x%0x seen=0x%0x.",$time, gen_x,ref_node_info.eol,pep_ks_mult.gen_node_x_loop[gen_x].s0_node_res_info.eol);
              error_mult_node_local <= 1'b1;
            end

            // check node eoy
            assert(pep_ks_mult.gen_node_x_loop[gen_x].s0_node_res_info.eoy == ref_node_info.eoy)
            else begin
              $display("%t > ERROR: Mult_node[x=%0d] eoy mismatches. exp=0x%0x seen=0x%0x.",$time, gen_x,ref_node_info.eoy,pep_ks_mult.gen_node_x_loop[gen_x].s0_node_res_info.eoy);
              error_mult_node_local <= 1'b1;
            end

            // check node last_iter
            assert(pep_ks_mult.gen_node_x_loop[gen_x].s0_node_res_info.last_iter == ref_node_info.last_iter)
            else begin
              $display("%t > ERROR: Mult_node[x=%0d] last_iter mismatches. exp=0x%0x seen=0x%0x.",$time, gen_x,ref_node_info.last_iter,pep_ks_mult.gen_node_x_loop[gen_x].s0_node_res_info.last_iter);
              error_mult_node_local <= 1'b1;
            end

            // check node batch_id
            assert(pep_ks_mult.gen_node_x_loop[gen_x].s0_node_res_info.batch_id == ref_node_info.batch_id)
            else begin
              $display("%t > ERROR: Mult_node[x=%0d] batch_id mismatches. exp=0x%0x seen=0x%0x.",$time, gen_x,ref_node_info.batch_id,pep_ks_mult.gen_node_x_loop[gen_x].s0_node_res_info.batch_id);
              error_mult_node_local <= 1'b1;
            end

          end
        end

      //------------------------------
      // Check Mult
      //------------------------------
      logic [OP_W-1:0] in_bfifo_q [TOTAL_BATCH_NB-1:0][$];

      always_ff @(posedge clk)
        for (int b=0; b<TOTAL_BATCH_NB; b=b+1)
          if (bfifo_outp_vld[b] && bfifo_outp_rdy[b])
            in_bfifo_q[b].push_back(bfifo_outp_data[b]);

      bit error_mult_local;
      assign error_mult_out[gen_x] = error_mult_local;

      always_ff @(posedge clk)
        if (!s_rst_n)
          error_mult_local <= 1'b0;
        else begin
          if (mult_outp_avail[gen_x]) begin
            logic [OP_W-1:0] ref_mult_res;
            integer          pbs_id;
            integer          batch_id;
            info_t           ref_mult_info;
            logic [OP_W-1:0] node_res;

            ref_mult_info = mult_info_q[gen_x].pop_front();
            ref_mult_res = '0;
            for (int l=0; l<KS_LG_NB; l=l+1) begin
              for (int y=0; y<KS_BLOCK_LINE_NB; y=y+1) begin
                //$display("[%0d] l=%0d y=%0d pbs_id=%0d node_res=0x%0x", gen_x, l,y,ref_mult_info.pbs_id, node_res_q[gen_x][ref_mult_info.pbs_id][0]);
                // /!\ WORKAROUND for xsim bug. The pop_front does not give the correct value, but [0] does.
                // This occurs when OP_W is > 32bits
                node_res = node_res_q[gen_x][ref_mult_info.pbs_id][0];
                node_res_q[gen_x][ref_mult_info.pbs_id].pop_front();
                //$display(" >> 0x%0x",node_res);
                ref_mult_res = ref_mult_res + node_res;
              end
            end

            mult_res_q[gen_x][ref_mult_info.batch_id].push_back(ref_mult_res);
            //$display("batch_id=%0d x=%0d pbs_id=%0d node_res=0x%0x",mult_outp_batch_id[gen_x], gen_x, ref_mult_info.pbs_id,ref_mult_res);

            // Check mult result
            assert(mult_outp_data[gen_x] == ref_mult_res)
            else begin
              $display("%t > ERROR: Mult[x=%0d] data mismatches. exp=0x%0x seen=0x%0x.",$time, gen_x,ref_mult_res,mult_outp_data[gen_x]);
              error_mult_local <= 1'b1;
            end

            // check node batch_id
            assert(mult_outp_batch_id[gen_x] == ref_mult_info.batch_id)
            else begin
              $display("%t > ERROR: Mult[x=%0d] batch_id mismatches. exp=0x%0x seen=0x%0x.",$time, gen_x,ref_mult_info.batch_id,mult_outp_batch_id[gen_x]);
              error_mult_local <= 1'b1;
            end

            // check node last_pbs
            assert(mult_outp_last_pbs[gen_x] == ref_mult_info.eoy)
            else begin
              $display("%t > ERROR: Mult[x=%0d] last_pbs mismatches. exp=0x%0x seen=0x%0x.",$time, gen_x,ref_mult_info.eoy,mult_outp_last_pbs[gen_x]);
              error_mult_local <= 1'b1;
            end

          end
        end

    end // for gen_x
  endgenerate

  //------------------------------
  // Check out process
  //------------------------------
  integer out_pbs_nb_q [TOTAL_BATCH_NB-1:0][$];
  //integer out_pbs_nb2_q [TOTAL_BATCH_NB-1:0][$];

  logic [OP_W-1:0] bfifo_outp_q   [TOTAL_BATCH_NB-1:0][$];
  logic [OP_W-1:0] out_body_q     [TOTAL_BATCH_NB-1:0][$];
  logic [OP_W-1:0] br_bfifo_data_q[TOTAL_BATCH_NB-1:0][$];
  logic [LWE_COEF_W-1:0] br_proc_lwe_q  [TOTAL_BATCH_NB-1:0][$];
  logic [KS_CORR_W-1:0]  br_proc_corr_q [TOTAL_BATCH_NB-1:0][$];

  always_ff @(posedge clk)
    if (in_run_column && in_bline_cnt==0 && in_bcol_cnt==0 && in_lvl_cnt==0) begin
      for (int i=0; i<LWE_K; i=i+1)
        out_pbs_nb_q[in_run_batch_id].push_back(in_run_pbs_nb);
      //out_pbs_nb2_q[in_run_batch_id].push_back(in_run_pbs_nb);
    end

  always_ff @(posedge clk)
    for (int b=0; b<TOTAL_BATCH_NB; b=b+1) begin
      if (bfifo_outp_vld[b] && bfifo_outp_rdy[b])
        bfifo_outp_q[b].push_back(bfifo_outp_data[b]);
      if (br_bfifo_wr_en[b])
        br_bfifo_data_q[b].push_back(br_bfifo_data[b]);
      if (br_proc_vld[b] && br_proc_rdy[b]) begin
        br_proc_lwe_q[b].push_back(br_proc_lwe[b]);
        br_proc_corr_q[b].push_back(br_proc_corr[b]);
      end
    end


  // Wait for data to be discarded to be available before proceeding the check.
  always_ff @(posedge clk) begin
    int out_x_cnt [TOTAL_BATCH_NB-1:0];
    int out_pbs_cnt [TOTAL_BATCH_NB-1:0];
    if (!s_rst_n) begin
      out_x_cnt   <= '{TOTAL_BATCH_NB{32'd0}};
      out_pbs_cnt <= '{TOTAL_BATCH_NB{32'd0}};
      error_out_process <= '0;
    end
    else
      for (int b=0; b<TOTAL_BATCH_NB; b=b+1) begin
        integer x_col;
        integer pbs_nb;
        x_col = out_x_cnt[b] % LBX;

        pbs_nb = out_pbs_nb_q[b][0];

        if (br_proc_lwe_q[b].size() >= pbs_nb &&
            (((out_x_cnt[b] < LWE_K-1) && mult_res_q[x_col][b].size() >= pbs_nb)
            || ((out_x_cnt[b] == LWE_K-1) && mult_res_q[x_col][b].size() > pbs_nb*(1 + DROP_COL_NB)))) begin
          logic [OP_W-1:0]       mult_res_org;
          logic [OP_W-1:0]       mult_res;
          logic [KS_CORR_W-1:0]  corr_res;
          logic [KS_CORR_W-1:0]  br_proc_corr_res;
          logic [LWE_COEF_W-1:0] br_proc_res;

          mult_res_org = mult_res_q[x_col][b].pop_front();
          br_proc_res = br_proc_lwe_q[b].pop_front();
          br_proc_corr_res = br_proc_corr_q[b].pop_front();

          //$display("batch=%0d pbs_id=%0d x=%0d x_col=%0d mult_res=0x%0x",b, out_pbs_cnt[b], out_x_cnt[b], x_col, mult_res);
          mult_res_org = 0 - mult_res_org;
          mult_res = (mult_res_org >> (OP_W-LWE_COEF_W)) + mult_res_org[OP_W-LWE_COEF_W-1]; // mod switch

          if (USE_MEAN_COMP)
            corr_res = mult_res_org - (mult_res << (OP_W-LWE_COEF_W));
          else
            corr_res = '0;

          assert(mult_res[LWE_COEF_W-1:0] == br_proc_res)
          else begin
            $display("%t > ERROR: Out Proc [%0d] data mismatches exp=0x%0x seen=0x%0x.",$time, b, mult_res[LWE_COEF_W-1:0],br_proc_res);
            error_out_process[b] <= 1'b1;
          end

          assert(corr_res == br_proc_corr_res)
          else begin
            $display("%t > ERROR: Out Proc [%0d] corr mismatches exp=0x%0x seen=0x%0x.",$time, b, corr_res,br_proc_corr_res);
            error_out_process[b] <= 1'b1;
          end

          pbs_nb = out_pbs_nb_q[b].pop_front();

          // If last mask, store the body of all the pbs, and discard the other columns if any
          if (out_x_cnt[b] == LWE_K-1 && out_pbs_cnt[b] == pbs_nb-1) begin
            for (int p=0; p<BATCH_PBS_NB; p=p+1) begin // extract body and coef to be discarded for every pbs of the batch
              if (p < pbs_nb) begin
                mult_res = mult_res_q[(x_col+1)%LBX][b].pop_front();
                out_body_q[b].push_back(mult_res);
                //$display("batch=%0d pbs_id=%0d x=%0d x_col=%0d body=0x%0x",b, out_pbs_cnt[b], out_x_cnt[b], (x_col+1)%LBX, mult_res);
                for (int i=0; i<DROP_COL_NB; i=i+1) begin// discard
                  mult_res = mult_res_q[(x_col+2+i)%LBX][b].pop_front();
                  //$display("batch=%0d pbs_id=%0d x=%0d x_col=%0d Discard=0x%0x",b, out_pbs_cnt[b], out_x_cnt[b],(x_col+2+i)%LBX , mult_res);
                end
              end
            end

          end

          // Update counter
          //$display("pbs_nb=%0d",pbs_nb);
          out_pbs_cnt[b] <= out_pbs_cnt[b] == pbs_nb-1 ? 0 : out_pbs_cnt[b] + 1;
          out_x_cnt[b]   <= out_pbs_cnt[b] == pbs_nb-1 ? out_x_cnt[b] == LWE_K-1 ? 0 : out_x_cnt[b] + 1 : out_x_cnt[b];

        end // if
      end // for b
  end

  // check body
  always_ff @(posedge clk)
    if (!s_rst_n)
      error_out_body <= '0;
    else begin
      for (int b=0; b<TOTAL_BATCH_NB; b=b+1) begin
        if (bfifo_outp_q[b].size() > 0 && out_body_q[b].size() > 0 && br_bfifo_data_q[b].size() > 0) begin
          logic [OP_W-1:0] in_body;
          logic [OP_W-1:0] coef_body;
          logic [OP_W-1:0] out_body;
          logic [OP_W-1:0] ref_body;
          in_body   = bfifo_outp_q[b].pop_front();
          coef_body = out_body_q[b].pop_front();
          out_body  = br_bfifo_data_q[b].pop_front();
          ref_body  = in_body - coef_body;

          //$display("batch=%0d bfifo_outp=0x%0x",b, in_body);
          assert(out_body == ref_body)
          else begin
            $display("%t > ERROR: Out body [%0d] proc data mismatches exp=0x%x seen=0x%x.",$time, b, ref_body, out_body);
            error_out_body[b] <= 1'b1;
          end
        end
      end
    end

// ============================================================================================== --
// Control
// ============================================================================================== --
  initial begin
    start = 1'b0;
    wait(s_rst_n);
    repeat (10) @(posedge clk);
    start = 1'b1;
  end

  // Count the output batches
  integer                    out_pbs_cnt;
  integer                    out_coef_cnt [TOTAL_BATCH_NB];
  logic [TOTAL_BATCH_NB-1:0] out_last_coef_cnt ;
  always_ff @(posedge clk)
    if (!s_rst_n)
      out_coef_cnt <= '{TOTAL_BATCH_NB{32'd0}};
    else
      for (int i = 0; i<TOTAL_BATCH_NB; i=i+1)
        out_coef_cnt[i] <= br_proc_vld[i] && br_proc_rdy[i] ? out_last_coef_cnt[i] ? 0 : out_coef_cnt[i] + 1 : out_coef_cnt[i];

  always_comb
    for (int i = 0; i<TOTAL_BATCH_NB; i=i+1)
      out_last_coef_cnt[i] = out_coef_cnt[i] == LWE_K-1;

  always_ff @(posedge clk)
    if (!s_rst_n) out_pbs_cnt <= 0;
    else          out_pbs_cnt <= |(br_proc_vld && br_proc_rdy && out_last_coef_cnt) ? out_pbs_cnt + 1 : out_pbs_cnt;

  initial begin
    end_of_test = 1'b0;
    wait(s_rst_n);
    wait(in_batch_cnt > PROC_BATCH_NB);
    wait(out_pbs_cnt > PROC_BATCH_NB * BATCH_PBS_NB);
    @(posedge clk);
    end_of_test = 1'b1;
  end

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      if ((in_run_col_done && in_last_bcol_cnt) && (in_batch_cnt % 10 == 0))
        $display("%t > INFO: In_batch # %0d",$time,in_batch_cnt);
      if (|(br_proc_vld && br_proc_rdy && out_last_coef_cnt) && (out_pbs_cnt % 50 == 0))
        $display("%t > INFO: Out_pbs # %0d",$time,out_pbs_cnt);
    end

endmodule
