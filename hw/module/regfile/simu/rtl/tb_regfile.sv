// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// regfile testbench.
// ==============================================================================================

module tb_regfile;
`timescale 1ns/10ps

  import param_tfhe_pkg::*;
  import regf_common_param_pkg::*;

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int CLK_HALF_PERIOD = 1;
  localparam int ARST_ACTIVATION = 17;

  parameter  int URAM_LATENCY      = 2 + 1;
  parameter  int RD_WR_ACCESS_TYPE = 1;
  parameter  bit KEEP_RD_DATA      = 0;

  parameter  int PEA_PERIOD   = REGF_COEF_NB;
  parameter  int PEM_PERIOD   = 4;
  parameter  int PEP_PERIOD   = 1;

  parameter  int MAX_ACCESS  = 500;

  localparam [PE_NB-1:0][31:0] PE_PERIOD = {PEP_PERIOD, PEM_PERIOD, PEA_PERIOD};

  initial begin
    $display("%t > INFO : REGF_REG_NB=%0d",$time,REGF_REG_NB);
    $display("%t > INFO : REGF_COEF_NB=%0d",$time,REGF_COEF_NB);
    $display("%t > INFO : REGF_SEQ=%0d",$time,REGF_SEQ);
    $display("%t > INFO : MOD_Q_W=%0d",$time,MOD_Q_W);
    $display("%t > INFO : REGF_COEF_PER_URAM_WORD=%0d",$time,REGF_COEF_PER_URAM_WORD);
    $display("%t > INFO : REGF_RAM_NB=%0d",$time,REGF_RAM_NB);
    $display("%t > INFO : REGF_BLWE_COEF_PER_RAM=%0d",$time,REGF_BLWE_COEF_PER_RAM);
    $display("%t > INFO : REGF_RAM_WORD_DEPTH=%0d",$time,REGF_RAM_WORD_DEPTH);
    $display("%t > INFO : REGF_SEQ_WORD_NB=%0d",$time,REGF_SEQ_WORD_NB);
  end

// ============================================================================================== --
// type
// ============================================================================================== --
  typedef struct packed {
    logic [PE_ID_W-1:0]              pe_id;
    logic [REGF_REGID_W-1:0]         reg_id;
    logic [REGF_BLWE_WORD_CNT_W-1:0] blwe_word;
    logic [REGF_COEF_ID_W-1:0]       coef;
  } data_t;

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
  bit [PE_NB-1:0] error_wr_data;
  bit [PE_NB-1:0] error_rd_data;
  bit [PE_NB-1:0] error_rd_val;

  assign error = |error_wr_data
                | |error_rd_data
                | |error_rd_val;

  always_ff @(posedge clk)
    if (error) begin
      $display("%t > FAILURE !", $time);
      $finish;
    end

// ============================================================================================== --
// input / output signals
// ============================================================================================== --
  // To ease simulation writing
  logic [PE_NB-1:0]                                wr_req_vld;
  logic [PE_NB-1:0]                                wr_req_rdy;
  regf_wr_req_t [PE_NB-1:0]                        wr_req;

  logic [PE_NB-1:0][REGF_COEF_NB-1:0]              wr_data_vld;
  logic [PE_NB-1:0][REGF_COEF_NB-1:0]              wr_data_rdy;
  logic [PE_NB-1:0][REGF_COEF_NB-1:0][MOD_Q_W-1:0] wr_data;

  // read
  logic [PE_NB-1:0]                                rd_req_vld;
  logic [PE_NB-1:0]                                rd_req_rdy;
  regf_rd_req_t [PE_NB-1:0]                        rd_req;

  logic [PE_NB-1:0][REGF_COEF_NB-1:0]              rd_data_avail;
  logic [PE_NB-1:0][REGF_COEF_NB-1:0][MOD_Q_W-1:0] rd_data;
  logic [PE_NB-1:0]                                rd_last_word;
  logic [PE_NB-1:0]                                rd_is_body;
  logic [PE_NB-1:0]                                rd_last_mask;

  logic [PE_NB-1:0]                                wr_ack;

// ============================================================================================== --
// Design under test instance
// ============================================================================================== --
  regfile #(
    .PEA_PERIOD   (PEA_PERIOD  ),
    .PEM_PERIOD   (PEM_PERIOD  ),
    .PEP_PERIOD   (PEP_PERIOD  ),
    .URAM_LATENCY (URAM_LATENCY)
  ) dut (
    .clk                    (clk    ),
    .s_rst_n                (s_rst_n),

    .pem_regf_wr_req_vld    (wr_req_vld[PEM_ID]),
    .pem_regf_wr_req_rdy    (wr_req_rdy[PEM_ID]),
    .pem_regf_wr_req        (wr_req[PEM_ID]),

    .pem_regf_wr_data_vld   (wr_data_vld[PEM_ID]),
    .pem_regf_wr_data_rdy   (wr_data_rdy[PEM_ID]),
    .pem_regf_wr_data       (wr_data[PEM_ID]),

    .pem_regf_rd_req_vld    (rd_req_vld[PEM_ID]),
    .pem_regf_rd_req_rdy    (rd_req_rdy[PEM_ID]),
    .pem_regf_rd_req        (rd_req[PEM_ID]),

    .regf_pem_rd_data_avail (rd_data_avail[PEM_ID]),
    .regf_pem_rd_data       (rd_data[PEM_ID]),
    .regf_pem_rd_last_word  (rd_last_word[PEM_ID]),
    .regf_pem_rd_is_body    (rd_is_body[PEM_ID]),
    .regf_pem_rd_last_mask  (rd_last_mask[PEM_ID]),

    .pea_regf_wr_req_vld    (wr_req_vld[PEA_ID]),
    .pea_regf_wr_req_rdy    (wr_req_rdy[PEA_ID]),
    .pea_regf_wr_req        (wr_req[PEA_ID]),

    .pea_regf_wr_data_vld   (wr_data_vld[PEA_ID]),
    .pea_regf_wr_data_rdy   (wr_data_rdy[PEA_ID]),
    .pea_regf_wr_data       (wr_data[PEA_ID]),

    .pea_regf_rd_req_vld    (rd_req_vld[PEA_ID]),
    .pea_regf_rd_req_rdy    (rd_req_rdy[PEA_ID]),
    .pea_regf_rd_req        (rd_req[PEA_ID]),

    .regf_pea_rd_data_avail (rd_data_avail[PEA_ID]),
    .regf_pea_rd_data       (rd_data[PEA_ID]),
    .regf_pea_rd_last_word  (rd_last_word[PEA_ID]),
    .regf_pea_rd_is_body    (rd_is_body[PEA_ID]),
    .regf_pea_rd_last_mask  (rd_last_mask[PEA_ID]),

    .pep_regf_wr_req_vld    (wr_req_vld[PEP_ID]),
    .pep_regf_wr_req_rdy    (wr_req_rdy[PEP_ID]),
    .pep_regf_wr_req        (wr_req[PEP_ID]),

    .pep_regf_wr_data_vld   (wr_data_vld[PEP_ID]),
    .pep_regf_wr_data_rdy   (wr_data_rdy[PEP_ID]),
    .pep_regf_wr_data       (wr_data[PEP_ID]),

    .pep_regf_rd_req_vld    (rd_req_vld[PEP_ID]),
    .pep_regf_rd_req_rdy    (rd_req_rdy[PEP_ID]),
    .pep_regf_rd_req        (rd_req[PEP_ID]),

    .regf_pep_rd_data_avail (rd_data_avail[PEP_ID]),
    .regf_pep_rd_data       (rd_data[PEP_ID]),
    .regf_pep_rd_last_word  (rd_last_word[PEP_ID]),
    .regf_pep_rd_is_body    (rd_is_body[PEP_ID]),
    .regf_pep_rd_last_mask  (rd_last_mask[PEP_ID]),

    .pem_wr_ack             (wr_ack[PEM_ID]),
    .pea_wr_ack             (wr_ack[PEA_ID]),
    .pep_wr_ack             (wr_ack[PEP_ID])
  );

// ============================================================================================== --
// Scenario
// ============================================================================================== --
// ---------------------------------------------------------------------------------------------- --
// FSM
// ---------------------------------------------------------------------------------------------- --
// First phase :
//  * Write at "full" speed. Check that there is no bubble introduced, and data are accepted
//    at the correct frequency.
//  * Read at "full speed". Check that there is no bubble introduced in data read, and that they
//    are sent in the correct order.
//  * Read and write : Same scenario with both read and write. Check write acknowledge.
// Second phase :
//  * Random access : check data coherency.
//
  typedef enum {ST_IDLE,
                ST_WRITE,
                ST_READ,
                ST_READ_AND_WRITE,
                ST_RANDOM_ACCESS,
                ST_DONE,
                ST_XXX} state_e;
  state_e state;
  state_e next_state;

  logic start;
  logic req_done;

  always_ff @(posedge clk) begin
    if (!s_rst_n) state <= ST_IDLE;
    else          state <= next_state;
  end

  always_comb begin
    next_state = ST_XXX;
    case (state)
      ST_IDLE:
        next_state = start ? ST_WRITE : ST_IDLE;
      ST_WRITE:
        next_state = req_done ? ST_READ : state;
      ST_READ:
        next_state = req_done ? ST_READ_AND_WRITE : state;
      ST_READ_AND_WRITE:
        next_state = req_done ? ST_RANDOM_ACCESS : state;
      ST_RANDOM_ACCESS:
        next_state = req_done ? ST_DONE : state;
      ST_DONE:
        next_state = state;
      ST_XXX:
        $fatal(1, "%t > ERROR: Unknown state.", $time);
    endcase
  end

  always_comb begin
    case (state)
      ST_IDLE:
        if (start)
          $display("%t > INFO : ST_WRITE", $time);
      ST_WRITE:
        if (req_done)
          $display("%t > INFO : ST_READ", $time);
      ST_READ:
        if (req_done)
          $display("%t > INFO : ST_READ_AND_WRITE", $time);
      ST_READ_AND_WRITE:
        if (req_done)
          $display("%t > INFO : ST_RANDOM_ACCESS", $time);
      ST_RANDOM_ACCESS:
        if (req_done)
          $display("%t > INFO : ST_DONE", $time);
      default: begin
          // do nothing
        end
    endcase
  end

  logic st_idle;
  logic st_write;
  logic st_read;
  logic st_read_and_write;
  logic st_random_access;

  assign st_idle           = (state == ST_IDLE);
  assign st_write          = (state == ST_WRITE);
  assign st_read           = (state == ST_READ);
  assign st_read_and_write = (state == ST_READ_AND_WRITE);
  assign st_random_access  = (state == ST_RANDOM_ACCESS);
  assign st_done           = (state == ST_DONE);

// ---------------------------------------------------------------------------------------------- --
// Random
// ---------------------------------------------------------------------------------------------- --
  logic [REGF_BLWE_WORD_PER_RAM:0][31:0] rand_word_cnt;
  logic                                  rand_do_2_read;
  integer                                rand_wr_pe;
  integer                                rand_rd_pe;

  always_ff @(posedge clk) begin
    rand_wr_pe     = $urandom_range(0,PE_NB-1);
    rand_rd_pe     = $urandom_range(0,PE_NB-1);
    rand_do_2_read = $urandom_range(0,1);
    for (int i=0; i<REGF_BLWE_WORD_PER_RAM+1; i=i+1)
      rand_word_cnt[i] = $urandom_range(1, REGF_BLWE_WORD_PER_RAM+1); // body included
  end

// ---------------------------------------------------------------------------------------------- --
// Request
// ---------------------------------------------------------------------------------------------- --
// ---------------------
// Write
// ---------------------
  logic [REGF_REGID_W-1:0] wr_reg_id_pool_q[$];
  logic [REGF_REGID_W-1:0] rd_reg_id_pool_q[$];

  logic [REGF_REGID_W-1:0] wr_reg_id_pending_q[PE_NB-1:0][$];
  logic [REGF_REGID_W-1:0] rd_reg_id_pending_q[PE_NB-1:0][$];
  logic [REGF_REGID_W-1:0] rd_reg_id_pending_2_q[PE_NB-1:0][$];

  logic rd_do_2_read_pending_q[PE_NB-1:0][$];

  regf_wr_req_t       wr_req_q  [PE_NB-1:0][$];
  regf_rd_req_t       rd_req_q  [PE_NB-1:0][$];
  logic [MOD_Q_W-1:0] wr_data_q [PE_NB-1:0][REGF_COEF_NB-1:0][$];
  logic [MOD_Q_W-1:0] rd_data_q [PE_NB-1:0][REGF_COEF_NB-1:0][$];

  int wr_req_cnt_q[PE_NB-1:0][$];
  int wr_ack_cnt[PE_NB-1:0];

  initial begin
    for (int i=0; i<REGF_REG_NB; i=i+1)
      wr_reg_id_pool_q.push_back(i);
  end

  // Build WR requests
  always_ff @(posedge clk)
    if (st_write || st_read_and_write || st_random_access) begin
      for (int p=0; p<PE_NB; p=p+1) begin
        logic [REGF_REGID_W-1:0] rid;
        integer pe_id;
        regf_wr_req_t req;

        pe_id = (rand_wr_pe + p) % PE_NB;
        if (wr_reg_id_pool_q.size() > 0) begin
          int start_word;
          int req_cnt;
          rid = wr_reg_id_pool_q[0];
          wr_reg_id_pending_q[pe_id].push_back(rid);
          wr_reg_id_pool_q.pop_front();

          //$display("%t > DEBUG: generating WR req for PE %0d; with reg_id=%0d",$time, pe_id,rid);
          start_word = 0;
          req_cnt = 0;
          while(start_word < (REGF_BLWE_WORD_PER_RAM+1)) begin
            int word_nb;

            word_nb = rand_word_cnt[start_word];
            word_nb = (word_nb + start_word) > (REGF_BLWE_WORD_PER_RAM+1) ? (REGF_BLWE_WORD_PER_RAM+1) - start_word : word_nb;

            req.reg_id     = rid;
            req.start_word = start_word;
            req.word_nb_m1 = word_nb - 1;

            wr_req_q[pe_id].push_back(req);

            start_word = start_word + word_nb;
            req_cnt = req_cnt + 1;
          end // while

          wr_req_cnt_q[pe_id].push_back(req_cnt);

          for (int w=0; w<(REGF_BLWE_WORD_PER_RAM+1); w=w+1) begin
            data_t d;
            logic [MOD_Q_W-1:0] dd;
            for (int i=0; i<REGF_COEF_NB; i=i+1) begin
              d.coef      = i;
              d.blwe_word = w;
              d.reg_id    = rid;
              d.pe_id     = pe_id;
              dd = d;
              wr_data_q[pe_id][i].push_back(dd);
            end // for i
          end // for w
        end // if wr_reg_id_pool_q.size() > 0)
      end // for p
    end // if st_write

// ---------------------
// Read
// ---------------------
  // Build RD requests
  logic [PE_NB-1:0][REGF_SEQ-1:0] rd_first;
  logic [PE_NB-1:0][REGF_SEQ-1:0] rd_firstD;

  always_ff @(posedge clk)
    if (!s_rst_n) rd_first <= '1;
    else          rd_first <= rd_firstD;

  always_comb
    for (int p=0; p<PE_NB; p=p+1) begin
      rd_firstD[p][0] = rd_data_avail[p][0] ? !rd_first[p][0] ? 1'b1 :
                                              (rd_do_2_read_pending_q[p][0]) ? 1'b0 : 1'b1 : rd_first[p][0];
      for (int s=1; s<REGF_SEQ; s=s+1)
        rd_firstD[p][s] = rd_firstD[p][s-1];
    end

  // Keep track of the last write
  integer reg_tag [REGF_REG_NB-1:0];

  always_ff @(posedge clk)
    if (!s_rst_n)
      for (int i=0; i<REGF_REG_NB; i=i+1)
        reg_tag[i] = -1;
    else begin
      for (int i=0; i<REGF_REG_NB; i=i+1)
        for (int p=0; p<PE_NB; p=p+1) begin
          if (wr_req_vld[p] && wr_req_rdy[p] && wr_req[p].reg_id == i)
            reg_tag[i] = p;
        end
    end

  always_ff @(posedge clk) begin
    for (int p=0; p<PE_NB; p=p+1) begin
      logic [REGF_REGID_W-1:0] rid;
      logic [REGF_REGID_W-1:0] rid_2;
      bit                      do_2_read;
      integer                  pe_id;
      regf_rd_req_t            req;

      pe_id = (rand_rd_pe + p) % PE_NB;
      // If rand_do_2_read == 1, need 2 available registers.
      if ((st_done && (rd_reg_id_pool_q.size() > 0)) || rd_reg_id_pool_q.size() > 1) begin
        int start_word;

        do_2_read =  (PE_PERIOD[pe_id] > 1) & (rd_reg_id_pool_q.size() > 1) & rand_do_2_read;

        rid = rd_reg_id_pool_q[0];
        rd_reg_id_pending_q[pe_id].push_back(rid);
        rd_reg_id_pool_q.pop_front();

        //$display("%t > DEBUG: generating RD req for PE %0d; with reg_id=%0d",$time, pe_id,rid);
        if (do_2_read) begin
          rid_2 = rd_reg_id_pool_q[0];
          rd_reg_id_pending_2_q[pe_id].push_back(rid_2);
          rd_reg_id_pool_q.pop_front();
          //$display("%t > DEBUG:                             with reg_id_1=%0d",$time, rid_2);
        end
        else
          rid_2 = '0; // Avoid 'X in simulation

        start_word = 0;
        while(start_word < (REGF_BLWE_WORD_PER_RAM+1)) begin
          int word_nb;

          word_nb = rand_word_cnt[start_word];
          word_nb = (word_nb + start_word) > (REGF_BLWE_WORD_PER_RAM+1) ? (REGF_BLWE_WORD_PER_RAM+1) - start_word : word_nb;

          req.do_2_read  = do_2_read;
          req.reg_id     = rid;
          req.reg_id_1   = rid_2;
          req.start_word = start_word;
          req.word_nb_m1 = word_nb - 1;

          rd_req_q[pe_id].push_back(req);

          start_word = start_word + word_nb;
        end // while

        for (int w=0; w<(REGF_BLWE_WORD_PER_RAM+1); w=w+1) begin // Includes body
          data_t d;
          logic [MOD_Q_W-1:0] dd;

          rd_do_2_read_pending_q[pe_id].push_back(do_2_read);
          if (do_2_read)
            rd_do_2_read_pending_q[pe_id].push_back(do_2_read);

          for (int i=0; i<REGF_COEF_NB; i=i+1) begin
            d.coef      = i;
            d.blwe_word = w;
            d.reg_id    = rid;
            d.pe_id     = reg_tag[rid];
            dd = d;
            rd_data_q[pe_id][i].push_back(dd);

            if (do_2_read) begin
              d.reg_id    = rid_2;
              d.pe_id     = reg_tag[rid_2];
              dd = d;
              rd_data_q[pe_id][i].push_back(dd);
            end
          end // for i
        end // for w
      end // if rd_reg_id_pool_q.size() > 0)

    end // for p
  end // always

// ---------------------
// Reuse reg_id
// ---------------------
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      wr_ack_cnt <= '{PE_NB{32'd0}};
    end
    else
      for (int p=0; p<PE_NB; p=p+1) begin
        logic [REGF_REGID_W-1:0] rid;
        logic [REGF_REGID_W-1:0] rid_2;
        bit                      do_2_read;
        if (wr_ack[p]) begin
          int req_cnt;
          req_cnt = wr_req_cnt_q[p][0];

          if (req_cnt == wr_ack_cnt[p] + 1) begin // All requests for the same BLWE have been acknowledged
            wr_ack_cnt[p] <= '0;

            rid = wr_reg_id_pending_q[p][0];

            //$display("%t > DEBUG: Wr ack for PE %0d; with reg_id=%0d",$time, p,rid);
            if (st_write) begin
              wr_reg_id_pool_q.push_back(rid);
              //$display("%t > DEBUG:                 push in wr_reg_id_pool",$time);
            end
            else begin
              //$display("%t > DEBUG:                 push in rd_reg_id_pool",$time);
              rd_reg_id_pool_q.push_back(rid);
            end
            wr_reg_id_pending_q[p].pop_front();
            wr_req_cnt_q[p].pop_front();
          end
          else begin
            wr_ack_cnt[p] <= wr_ack_cnt[p] + 1;
          end
        end // if wr_ack

        if (rd_data_avail[p][0] && rd_last_word[p] && rd_is_body[p]) begin
            if (rd_first[p][0]) begin
              rid = rd_reg_id_pending_q[p][0];
              rd_reg_id_pending_q[p].pop_front();
            end
            else begin
              rid = rd_reg_id_pending_2_q[p][0];
              rd_reg_id_pending_2_q[p].pop_front();
            end

            //$display("%t > DEBUG: RD ack for PE %0d; with reg_id=%0d",$time, p,rid);
            if (st_read) begin
              rd_reg_id_pool_q.push_back(rid);
              //$display("%t > DEBUG:                 push in rd_reg_id_pool",$time);
            end
            else begin
              wr_reg_id_pool_q.push_back(rid);
              //$display("%t > DEBUG:                 push in wr_reg_id_pool",$time);
            end
        end // if rd done
      end // for p

// ---------------------------------------------------------------------------------------------- --
// Interface
// ---------------------------------------------------------------------------------------------- --
  generate
    for (genvar gen_p=0; gen_p<PE_NB; gen_p=gen_p+1) begin : gen_pe_loop
    // ---------------------
    // Write
    // ---------------------
      logic wr_req_vld_tmp;
      logic wr_req_rdy_tmp;
      logic wr_req_vld_tmp2;
      logic wr_req_rdy_tmp2;

      stream_source
      #(
        .FILENAME   ("random"),
        .DATA_TYPE  ("ascii_hex"),
        .DATA_W     (1),
        .RAND_RANGE (1),
        .KEEP_VLD   (1),
        .MASK_DATA  ("x")
      )
      source_wr_req
      (
        .clk        (clk),
        .s_rst_n    (s_rst_n),

        .data       (/*UNUSED*/),
        .vld        (wr_req_vld_tmp),
        .rdy        (wr_req_rdy_tmp),

        .throughput (st_random_access ? 0 : 1)
      );

      initial begin
        if (!source_wr_req.open()) begin
          $fatal(1, "%t > ERROR: Opening source_wr_req stream source", $time);
        end
        source_wr_req.start(0);
      end

      for (genvar gen_c=0; gen_c<REGF_COEF_NB; gen_c=gen_c+1) begin
        int dataw_word_cnt;
        int dataw_word_cntD;
        int dataw_word_cnt_inc;
        int dataw_word_cnt_dec;

        always_ff @(posedge clk)
          if (!s_rst_n) dataw_word_cnt <= '0;
          else          dataw_word_cnt <= dataw_word_cntD;

        assign dataw_word_cnt_inc = wr_req_vld[gen_p] && wr_req_rdy[gen_p] ? wr_req[gen_p].word_nb_m1 + 1 : '0;
        assign dataw_word_cnt_dec = wr_data_vld[gen_p][gen_c] && wr_data_rdy[gen_p][gen_c] ? 1 : '0;
        assign dataw_word_cntD    = dataw_word_cnt - dataw_word_cnt_dec + dataw_word_cnt_inc;

        logic               wr_data_avail;
        logic [MOD_Q_W-1:0] wr_data_tmp;
        logic               wr_data_vld_tmp;
        always_ff @(posedge clk)
          if (!s_rst_n) begin
            wr_data_avail <= 1'b0;
            wr_data_tmp   <= '0;
          end
          else
            if (wr_data_avail == 1'b0 || (wr_data_vld[gen_p][gen_c] && wr_data_rdy[gen_p][gen_c])) begin
              wr_data_avail <= wr_data_q[gen_p][gen_c].size() > 0;
              if (wr_data_q[gen_p][gen_c].size() > 0) begin
                wr_data_tmp <= wr_data_q[gen_p][gen_c][0];
                wr_data_q[gen_p][gen_c].pop_front();
              end
            end

        assign wr_data_vld[gen_p][gen_c] = wr_data_vld_tmp           & wr_data_avail & (dataw_word_cnt > 0);
        assign wr_data_rdy_tmp           = wr_data_rdy[gen_p][gen_c] & wr_data_avail & (dataw_word_cnt > 0);
        assign wr_data[gen_p][gen_c]     = wr_data_tmp;

        stream_source
        #(
          .FILENAME   ("random"),
          .DATA_TYPE  ("ascii_hex"),
          .DATA_W     (1),
          .RAND_RANGE (1),
          .KEEP_VLD   (1),
          .MASK_DATA  ("x")
        )
        source_wr_data
        (
          .clk        (clk),
          .s_rst_n    (s_rst_n),

          .data       (/*UNUSED*/),
          .vld        (wr_data_vld_tmp),
          .rdy        (wr_data_rdy_tmp),

          .throughput (1)
        );

        initial begin
          if (!source_wr_data.open()) begin
            $fatal(1, "%t > ERROR: Opening source_wr_data[%0d] stream source", $time, gen_c);
          end
          source_wr_data.start(0);
        end

      end // for gen_c

      logic         wr_req_avail;
      regf_wr_req_t wr_req_tmp;
      always_ff @(posedge clk)
        if (!s_rst_n) begin
          wr_req_avail <= 1'b0;
          wr_req_tmp   <= '0;
        end
        else
          if (wr_req_avail == 1'b0 || (wr_req_vld[gen_p] && wr_req_rdy[gen_p])) begin
            wr_req_avail <= wr_req_q[gen_p].size() > 0;
            if (wr_req_q[gen_p].size() > 0) begin
              wr_req_tmp <= wr_req_q[gen_p][0];
              wr_req_q[gen_p].pop_front();
            end
          end

      always_comb begin
        wr_req_vld_tmp2 = wr_req_vld_tmp & wr_req_avail & ~(st_idle);
        wr_req_rdy_tmp  = wr_req_rdy_tmp2 & wr_req_avail & ~(st_idle);
      end

      assign wr_req_vld[gen_p] = wr_req_vld_tmp2;
      assign wr_req_rdy_tmp2   = wr_req_rdy[gen_p];
      assign wr_req[gen_p]     = wr_req_tmp;

    // ---------------------
    // Read
    // ---------------------
      logic rd_req_vld_tmp;
      logic rd_req_rdy_tmp;
      logic rd_req_vld_tmp2;
      logic rd_req_rdy_tmp2;

      stream_source
      #(
        .FILENAME   ("random"),
        .DATA_TYPE  ("ascii_hex"),
        .DATA_W     (1),
        .RAND_RANGE (1),
        .KEEP_VLD   (1),
        .MASK_DATA  ("x")
      )
      source_rd_req
      (
        .clk        (clk),
        .s_rst_n    (s_rst_n),

        .data       (/*UNUSED*/),
        .vld        (rd_req_vld_tmp),
        .rdy        (rd_req_rdy_tmp),

        .throughput (st_random_access ? 0 : 1)
      );

      initial begin
        if (!source_rd_req.open()) begin
          $fatal(1, "%t > ERROR: Opening source_rd_req stream source", $time);
        end
        source_rd_req.start(0);
      end

      logic         rd_req_avail;
      regf_rd_req_t rd_req_tmp;
      always_ff @(posedge clk)
        if (!s_rst_n) begin
          rd_req_avail <= 1'b0;
          rd_req_tmp   <= '0;
        end
        else
          if (rd_req_avail == 1'b0 || (rd_req_vld[gen_p] && rd_req_rdy[gen_p])) begin
            rd_req_avail <= rd_req_q[gen_p].size() > 0;
            if (rd_req_q[gen_p].size() > 0) begin
              rd_req_tmp = rd_req_q[gen_p][0];
              rd_req_q[gen_p].pop_front();
            end
          end

      always_comb begin
        rd_req_vld_tmp2 = rd_req_vld_tmp & rd_req_avail;
        rd_req_rdy_tmp  = rd_req_rdy_tmp2 & rd_req_avail;
      end

      assign rd_req_vld[gen_p] = rd_req_vld_tmp2;
      assign rd_req_rdy_tmp2   = rd_req_rdy[gen_p];
      assign rd_req[gen_p]     = rd_req_tmp;

    end
  endgenerate

// ============================================================================================== --
// Check
// ============================================================================================== --
// /!\ Cannot be done on the interface signals because of internal pipes
// ---------------------------------------------------------------------------------------------- --
// Check dataw consumption periodicity
// ---------------------------------------------------------------------------------------------- --
  integer signed wr_period [PE_NB-1:0];
  integer signed  wr_periodD [PE_NB-1:0];

  logic [PE_NB-1:0][REGF_WORD_NB-1:0] warb_in_data_vld;
  logic [PE_NB-1:0][REGF_WORD_NB-1:0] warb_in_data_rdy;

  assign warb_in_data_vld = dut.regf_write_arbiter.in0_data_vld;
  assign warb_in_data_rdy = dut.regf_write_arbiter.in0_data_rdy;

  always_ff @(posedge clk)
    if (!s_rst_n) wr_period <= '{PE_NB{32'd0}};
    else          wr_period <= wr_periodD;

  always_comb
    for (int p=0; p<PE_NB; p=p+1)
      wr_periodD[p]      = warb_in_data_vld[p][0] && warb_in_data_rdy[p][0] ? PE_PERIOD[p] - 1 : wr_period[p] < 0 ?  wr_period[p] : wr_period[p] - 1;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      error_wr_data <= '0;
    end
    else begin
      for (int p=0; p<PE_NB; p=p+1) begin
        if (PE_PERIOD[p] > 1 && warb_in_data_vld[p][0] && warb_in_data_rdy[p][0]) begin
          assert(wr_period[p] <= 0)
          else begin
            $display("%t > ERROR: Write data sampled while period is not over. PE=%0d", $time, p);
            error_wr_data[p] <= 1'b1;
          end

          if (st_write || st_read_and_write)
            assert(wr_period[p] == 0)
            else begin
              $display("%t > WARNING: Write data not sampled at period exactly. PE=%0d", $time, p);
              // Should only occur for the 1rst data
              //error_wr_data[p] <= 1'b1;
            end
        end // if rdy & vld
      end
    end

// ---------------------------------------------------------------------------------------------- --
// Check datar production periodicity
// ---------------------------------------------------------------------------------------------- --
  int rd_period [PE_NB-1:0];
  int rd_periodD [PE_NB-1:0];

  always_ff @(posedge clk)
    if (!s_rst_n) rd_period <= '{PE_NB{32'd0}};
    else          rd_period <= rd_periodD;

  always_comb
    for (int p=0; p<PE_NB; p=p+1) begin
      rd_periodD[p]   = rd_data_avail[p][0] && rd_first[p][0] ? PE_PERIOD[p] - 1 : rd_period[p] < 0 ? rd_period[p] : rd_period[p] - 1;
    end

  always_ff @(posedge clk)
    for (int p=0; p<PE_NB; p=p+1) begin
      if (rd_data_avail[p][0])
        rd_do_2_read_pending_q[p].pop_front();
    end

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      error_rd_data <= '0;
    end
    else begin
      for (int p=0; p<PE_NB; p=p+1) begin
        if (PE_PERIOD[p] > 1 && rd_data_avail[p][0] && rd_first[p][0]) begin
          assert(rd_period[p] <= 0)
          else begin
            $display("%t > ERROR: Read data produced while period is not over. PE=%0d", $time, p);
            error_rd_data[p] <= 1'b1;
          end

          if (st_read || st_read_and_write)
            assert(rd_period[p] == 0)
            else begin
              $display("%t > WARNING: Read data not produced at period exactly. PE=%0d", $time, p);
              // Should only occur for the 1rst data
              //error_rd_data[p] <= 1'b1;
            end
        end // if
        if (rd_data_avail[p][0] && !rd_first[p][0]) begin
          assert(rd_period[p] == PE_PERIOD[p] - 1)
          else begin
            $display("%t > ERROR: Second read data does not follow the first one. PE=%0d",$time,p);
            error_rd_data[p] <= 1'b1;
          end
        end
      end
    end

// ---------------------------------------------------------------------------------------------- --
// Check datar value
// ---------------------------------------------------------------------------------------------- --
  logic [PE_NB-1:0][REGF_COEF_NB-1:0] rd_is_body_sr;
  logic [PE_NB-1:0][REGF_COEF_NB-1:0] rd_is_body_sr_tmp;
  logic [PE_NB-1:0][REGF_COEF_NB-1:0] rd_is_body_sr_tmpD;

  assign rd_is_body_sr = rd_is_body_sr_tmpD;

  always_comb
    for (int p=0; p<PE_NB; p=p+1) begin
      rd_is_body_sr_tmpD[p][REGF_SEQ_COEF_NB-1:0] = {REGF_SEQ_COEF_NB{rd_is_body[p]}};
      for (int s=1; s<REGF_SEQ; s=s+1)
        rd_is_body_sr_tmpD[p][s*REGF_SEQ_COEF_NB+:REGF_SEQ_COEF_NB] = rd_is_body_sr_tmp[p][(s-1)*REGF_SEQ_COEF_NB+:REGF_SEQ_COEF_NB];
    end

  always_ff @(posedge clk)
    if (!s_rst_n) rd_is_body_sr_tmp <= '0;
    else          rd_is_body_sr_tmp <= rd_is_body_sr_tmpD;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      error_rd_val <= '0;
    end
    else begin
      for (int p=0; p<PE_NB; p=p+1) begin
        for (int i=0; i<REGF_COEF_NB; i=i+1) begin
          data_t d_ref;
          if (rd_data_avail[p][i]) begin
            d_ref = rd_data_q[p][i][0];
            rd_data_q[p][i].pop_front();
            if (i == 0 || !rd_is_body_sr[p][i]) // Do not check the dummy values that go with the body coef
              assert(d_ref == rd_data[p][i])
              else begin
                $display("%t > ERROR: Datar mismatch [PE=%0d][Coef=%0d] exp=0x%0x seen=0x%0x",$time, p, i, d_ref, rd_data[p][i]);
                error_rd_val[p] <= 1'b1;
              end

            if (i==0 && rd_is_body_sr[p][i]) begin
              assert(d_ref.blwe_word == REGF_BLWE_WORD_PER_RAM)
              else begin
                $display("%t > ERROR: Mismatch rd_is_body [PE=%0d]", $time, p);
                error_rd_val[p] <= 1'b1;
              end
            end
          end
        end // for i
      end // for p
    end

// ============================================================================================== --
// End of test
// ============================================================================================== --
// ---------------------------------------------------------------------------------------------- --
// Control
// ---------------------------------------------------------------------------------------------- --
  integer access_cnt_inc;
  integer access_cnt;

  always_comb begin
    access_cnt_inc = 0;
    for (int p=0; p<PE_NB; p=p+1) begin
      access_cnt_inc = access_cnt_inc + (wr_req_vld[p] & wr_req_rdy[p]) + (rd_req_vld[p] & rd_req_rdy[p]);
    end
  end

  always_ff @(posedge clk) begin
    if (!s_rst_n) access_cnt <= 0;
    else          access_cnt <= req_done ? '0 : access_cnt + access_cnt_inc;
  end

  assign req_done = access_cnt > MAX_ACCESS;

// ---------------------------------------------------------------------------------------------- --
// end
// ---------------------------------------------------------------------------------------------- --
  initial begin
    end_of_test = 1'b0;
    start = 1'b0;
    wait (s_rst_n);
    repeat(10) @(posedge clk);
    start = 1'b1;
    wait (st_done);
    $display("%t > INFO: All requests sent.",$time);
    $display("%t > INFO: Wait flush.", $time);
    wait (wr_reg_id_pool_q.size() == REGF_REG_NB);
    @(posedge clk);
    $display("%t > INFO: Done.", $time);
    end_of_test = 1'b1;
  end

endmodule
