// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the reading of BLWE in regfile for the key_switch.
// ==============================================================================================

module pep_load_blwe
  import param_tfhe_pkg::*;
  import top_common_param_pkg::*;
  import pep_ks_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import regf_common_param_pkg::*;
#(
  parameter int REGF_RD_LATENCY = 7, // URAM_LATENCY + 4 - minimum latency to get the data
  parameter int KS_IF_COEF_NB   = (LBY < REGF_COEF_NB) ? LBY : REGF_SEQ_COEF_NB,
  parameter int KS_IF_SUBW_NB   = (LBY < REGF_COEF_NB) ? 1 : REGF_SEQ
)
(
  input  logic                                                      clk,        // clock
  input  logic                                                      s_rst_n,    // synchronous reset

  // pep_seq : command
  input  logic [LOAD_BLWE_CMD_W-1:0]                                seq_ldb_cmd,
  input  logic                                                      seq_ldb_vld,
  output logic                                                      seq_ldb_rdy,
  output logic                                                      ldb_seq_done,

  // pep_ldb <-> Regfile
  // read
  output logic                                                      pep_regf_rd_req_vld,
  input  logic                                                      pep_regf_rd_req_rdy,
  output logic [REGF_RD_REQ_W-1:0]                                  pep_regf_rd_req,

  input  logic [REGF_COEF_NB-1:0]                                   regf_pep_rd_data_avail,
  input  logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0]                      regf_pep_rd_data,
  input  logic                                                      regf_pep_rd_last_word, // valid with avail[0]
  input  logic                                                      regf_pep_rd_is_body,
  input  logic                                                      regf_pep_rd_last_mask,

  // pep_ldb <-> Key switch
  // write
  output logic [KS_IF_SUBW_NB-1:0]                                  pep_blram_wr_en,
  output logic [KS_IF_SUBW_NB-1:0][PID_W-1:0]                       pep_blram_wr_pid,
  output logic [KS_IF_SUBW_NB-1:0][KS_IF_COEF_NB-1:0][MOD_Q_W-1:0]  pep_blram_wr_data,
  output logic [KS_IF_SUBW_NB-1:0]                                  pep_blram_wr_pbs_last, // associated to wr_en[0]

  output logic                                                      ldb_rif_rcp_dur
);

// ============================================================================================== //
// localparam
// ============================================================================================== //
  localparam bit REQ_ALL                  = REGF_COEF_NB <= LBY;
  // The following parameters are used when REGF_COEF_NB > LBY
  localparam int DIV_NB                   = REQ_ALL ? 1 : REGF_COEF_NB / LBY;
  localparam int DIV_SEQ                  = REGF_SEQ / DIV_NB;
  localparam int RD_LATENCY               = REGF_RD_LATENCY + 1 + 1; // + req_pipe c0 + data_pipe r0
  localparam int DATA_THRESHOLD_TMP       = 2**$clog2(RD_LATENCY); // REGF word unit
  localparam int DATA_THRESHOLD           = DATA_THRESHOLD_TMP == RD_LATENCY ? 2*DATA_THRESHOLD_TMP : DATA_THRESHOLD_TMP; // REGF word unit
  localparam int DATA_FIFO_DEPTH_TMP      = DATA_THRESHOLD - (DATA_THRESHOLD / DIV_NB);
  localparam int DATA_FIFO_DEPTH          = DATA_FIFO_DEPTH_TMP < 2 ? 2 : DATA_FIFO_DEPTH_TMP;
  localparam int REGF_REQ_NB              = REQ_ALL ? 1 : (BLWE_K + (REGF_COEF_NB*DATA_THRESHOLD) - 1) / (REGF_COEF_NB*DATA_THRESHOLD); // does not take body into account
  localparam int REGF_REQ_NB_W            = $clog2(REGF_REQ_NB) == 0 ? 1 : $clog2(REGF_REQ_NB);
  localparam int REGF_WORD_THRESHOLD      = DATA_THRESHOLD / REGF_COEF_PER_URAM_WORD;
  localparam int LAST_DATA_THRESHOLD      = (REGF_BLWE_WORD_PER_RAM % DATA_THRESHOLD) == 0 ? DATA_THRESHOLD : (REGF_BLWE_WORD_PER_RAM % DATA_THRESHOLD);
  localparam int DIV_W                    = $clog2(DIV_NB) == 0 ? 1 : $clog2(DIV_NB);
  localparam int DIV_COEF_NB              = REGF_COEF_NB / DIV_NB;
  localparam int BLWE_DIV_NB              = BLWE_K / DIV_COEF_NB; // Does not take the body into account
  localparam int BLWE_DIV_W               = $clog2(BLWE_DIV_NB) == 0 ? 1 : $clog2(BLWE_DIV_NB);
  localparam int DATA_THRESHOLD_WW        = $clog2(DATA_THRESHOLD+1) == 0 ? 1 : $clog2(DATA_THRESHOLD+1);
  localparam int OUT_FIFO_CNT_W           = $clog2(2 * DATA_THRESHOLD * DIV_NB) == 0 ? 1 : $clog2(2 * DATA_THRESHOLD * DIV_NB);
  localparam int OUT_FIFO_CNT_THRES       = RD_LATENCY + REGF_SEQ + (DIV_NB-1);// DIB_NB-1 : data arrives when there is still 1 coef
                                                                               // REGF_SEQ : to compensate the body dummy coef
  // NOTE : when DIV_NB == 2, there is a bubble at the output just after the body is sent.
  // TOREVIEW : See if this optim is necessary.

  localparam int RCP_FIFO_DEPTH           = 2; // Should be >= 2
  localparam int RCP_FIFO_DEPTH_WW        = $clog2(RCP_FIFO_DEPTH+1) == 0 ? 1 : $clog2(RCP_FIFO_DEPTH+1);

  generate
    if (REGF_COEF_NB > LBY && (REGF_COEF_NB%LBY) != 0) begin : _UNSUPPORTED_REGF_COEF_NB_LBY_0_
      $fatal(1,"ERROR> Unsupported REGF_COEF_NB (%0d) and LBY (%0d). LBY must divide REGF_COEF_NB",REGF_COEF_NB,LBY);
    end
    if (REGF_COEF_NB < LBY && (LBY%REGF_COEF_NB) != 0) begin : _UNSUPPORTED_REGF_COEF_NB_LBY_1_
      $fatal(1,"ERROR> Unsupported REGF_COEF_NB (%0d) and LBY (%0d). REGF_COEF_NB must divide LBY",REGF_COEF_NB,LBY);
    end
    if (REGF_COEF_NB > LBY && REGF_SEQ_COEF_NB > LBY) begin : _UNSUPPORTED_REGF_SEQ_COEF_NB_LBY_
      $fatal(1,"ERROR> Unsupported REGF_SEQ_COEF_NB (%0d) and LBY (%0d). REGF_SEQ_COEF_NB must be less or equal to LBY", REGF_SEQ_COEF_NB,LBY);
    end
  endgenerate

// pragma translate_off
  initial begin
    $display("> INFO: RD_LATENCY = %0d", RD_LATENCY);
    $display("> INFO: DATA_THRESHOLD = %0d", DATA_THRESHOLD);
    $display("> INFO: DATA_FIFO_DEPTH = %0d", DATA_FIFO_DEPTH);
    $display("> INFO: DIV_NB = %0d", DIV_NB);
    $display("> INFO: DIV_SEQ = %0d", DIV_SEQ);
    $display("> INFO: OUT_FIFO_CNT_THRES = %0d", OUT_FIFO_CNT_THRES);
  end
// pragma translate_on

// ============================================================================================== //
// typedef
// ============================================================================================== //
  typedef struct packed {
    logic [PID_W-1:0] pid;
  } rcp_cmd_t;

  localparam int RCP_CMD_W = $bits(rcp_cmd_t);

// ============================================================================================== //
// Input pipe
// ============================================================================================== //
  load_blwe_cmd_t c0_cmd;
  logic           c0_cmd_vld;
  logic           c0_cmd_rdy;

  fifo_element #(
    .WIDTH          (LOAD_BLWE_CMD_W),
    .DEPTH          (1), // TOREVIEW
    .TYPE_ARRAY     (4'h1),
    .DO_RESET_DATA  (1'b0),
    .RESET_DATA_VAL (0)
  ) ldb_cmd_fifo_element (
    .clk     (clk),
    .s_rst_n (s_rst_n),

    .in_data (seq_ldb_cmd),
    .in_vld  (seq_ldb_vld),
    .in_rdy  (seq_ldb_rdy),

    .out_data(c0_cmd),
    .out_vld (c0_cmd_vld),
    .out_rdy (c0_cmd_rdy)
  );

  logic [REGF_COEF_NB-1:0]              r0_rd_data_avail;
  logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0] r0_rd_data;
  logic                                 r0_rd_last_word;
  logic                                 r0_rd_is_body;
  logic                                 r0_rd_last_mask;

  always_ff @(posedge clk)
    if (!s_rst_n) r0_rd_data_avail <= '0;
    else          r0_rd_data_avail <= regf_pep_rd_data_avail;

  always_ff @(posedge clk) begin
    r0_rd_data      <= regf_pep_rd_data;
    r0_rd_last_word <= regf_pep_rd_last_word;
    r0_rd_is_body   <= regf_pep_rd_is_body;
    r0_rd_last_mask <= regf_pep_rd_last_mask;
  end

// ============================================================================================== --
// REGF request
// ============================================================================================== --
  //-----------------------
  // Request
  //-----------------------
  logic                             c0_regf_req_vld;
  logic                             c0_regf_req_rdy;
  regf_rd_req_t                     c0_regf_req;

  //== Counters
  logic [REGF_REQ_NB_W-1:0]         c0_req_cnt;
  logic [REGF_BLWE_WORD_CNT_W-1:0]  c0_word_add;

  logic [REGF_REQ_NB_W-1:0]         c0_req_cntD;
  logic [REGF_BLWE_WORD_CNT_W-1:0]  c0_word_addD;

  logic                             c0_rd_body;
  logic                             c0_rd_bodyD;

  logic                             c0_last_req_cnt;
  logic                             c0_first_req_cnt;
  logic                             c0_send_req;

  //== reception FIFO
  rcp_cmd_t                         rcp_fifo_in_cmd;
  logic                             rcp_fifo_in_vld;
  logic                             rcp_fifo_in_rdy;

  assign c0_last_req_cnt  = c0_req_cnt == REGF_REQ_NB - 1;
  assign c0_first_req_cnt = (c0_req_cnt == '0) & ~c0_rd_body;
  assign c0_req_cntD      = c0_send_req ? c0_rd_body ? '0 : c0_req_cnt + 1 : c0_req_cnt;
  assign c0_word_addD     = c0_send_req ? c0_rd_body ? '0 : c0_last_req_cnt ? REGF_BLWE_WORD_PER_RAM :
                                         c0_word_add + DATA_THRESHOLD : c0_word_add;
  assign c0_rd_bodyD      = c0_send_req ? c0_rd_body ? 1'b0 : c0_last_req_cnt ? 1'b1 : c0_rd_body : c0_rd_body;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      c0_req_cnt  <= '0;
      c0_word_add <= '0;
      c0_rd_body  <= 1'b0;
    end
    else begin
      c0_req_cnt  <= c0_req_cntD;
      c0_word_add <= c0_word_addD;
      c0_rd_body  <= c0_rd_bodyD;
    end

  // reception buffer location availability
  logic c0_enough_location;
  logic c0_regf_req_vld_tmp;

  assign c0_regf_req_vld_tmp    = c0_cmd_vld & (c0_rd_body | c0_enough_location);
  assign c0_regf_req_vld        = c0_regf_req_vld_tmp & (~c0_first_req_cnt | rcp_fifo_in_rdy);
  assign c0_send_req            = c0_regf_req_vld & c0_regf_req_rdy;
  assign c0_regf_req.start_word = c0_word_add;
  assign c0_regf_req.word_nb_m1 = c0_rd_body ? '0 :
                                  REQ_ALL ? REGF_BLWE_WORD_PER_RAM-1 :
                                  c0_last_req_cnt ? LAST_DATA_THRESHOLD-1: DATA_THRESHOLD-1;
  assign c0_regf_req.reg_id     = c0_cmd.src_rid;
  assign c0_regf_req.do_2_read  = 1'b0;

  //assign c0_cmd_rdy             = c0_regf_req_rdy & c0_enough_location & c0_rd_body;
  assign c0_cmd_rdy             = c0_regf_req_rdy & c0_rd_body;

  assign rcp_fifo_in_vld        = c0_regf_req_vld_tmp & c0_regf_req_rdy & c0_first_req_cnt;
  assign rcp_fifo_in_cmd.pid    = c0_cmd.pid;

  //-----------------------
  // Output FIFO
  //-----------------------
  fifo_element #(
    .WIDTH          (REGF_RD_REQ_W),
    .DEPTH          (1),
    .TYPE_ARRAY     (4'h3), // TOREVIEW
    .DO_RESET_DATA  (0),
    .RESET_DATA_VAL (0)
  ) regf_req_fifo_element (
    .clk     (clk),
    .s_rst_n (s_rst_n),

    .in_data (c0_regf_req),
    .in_vld  (c0_regf_req_vld),
    .in_rdy  (c0_regf_req_rdy),

    .out_data(pep_regf_rd_req),
    .out_vld (pep_regf_rd_req_vld),
    .out_rdy (pep_regf_rd_req_rdy)
  );

// ============================================================================================== --
// Reception FIFO
// ============================================================================================== --
   rcp_cmd_t rcp_fifo_out_cmd;
   logic     rcp_fifo_out_vld;
   logic     rcp_fifo_out_rdy;

    fifo_reg #(
      .WIDTH       (RCP_CMD_W),
      .DEPTH       (RCP_FIFO_DEPTH),
      .LAT_PIPE_MH ({1'b1, 1'b1})
    ) rcp_fifo_reg (
      .clk      (clk),
      .s_rst_n  (s_rst_n),

      .in_data  (rcp_fifo_in_cmd),
      .in_vld   (rcp_fifo_in_vld),
      .in_rdy   (rcp_fifo_in_rdy),

      .out_data (rcp_fifo_out_cmd),
      .out_vld  (rcp_fifo_out_vld),
      .out_rdy  (rcp_fifo_out_rdy)
    );

// ============================================================================================== --
// REGF Data format
// ============================================================================================== --
  // There is no ready on the BLRAM path.
  // There are 2 cases.
  // REQ_ALL : REGF_COEF_NB <= LBY
  //    Request for the whole BLWE is done.
  //    Since there is no ready back pressure, we are able to send all the received
  //    coefficients directly to the BLRAM.
  //    Therefore, there is always enough locations.
  // !REQ_ALL : REGF_COEF_NB > LBY
  //    It takes DIV_NB cycles to send 1 input from the regfile.
  //    The FIFO is sized so that it is big enough to received all the input while the
  //    sending is on.
  //    There are enough location therefore means that after REGF_RD_LATENCY cycles the FIFO is empty
  //    to receive the new data.

  logic [KS_IF_SUBW_NB-1:0]                                 blram_wr_en;
  logic [KS_IF_SUBW_NB-1:0][PID_W-1:0]                      blram_wr_pid;
  logic [KS_IF_SUBW_NB-1:0][KS_IF_COEF_NB-1:0][MOD_Q_W-1:0] blram_wr_data;
  logic [KS_IF_SUBW_NB-1:0]                                 blram_wr_pbs_last;

  logic [REGF_SEQ-1:0]                                      r0_rd_is_body_sr;
  logic [REGF_SEQ-1:0]                                      r0_rd_is_body_sr_tmp;
  logic [REGF_SEQ-1:0]                                      r0_rd_is_body_sr_tmpD;
  rcp_cmd_t [REGF_SEQ-1:0]                                  r0_rcp_cmd_sr;
  rcp_cmd_t [REGF_SEQ-1:0]                                  r0_rcp_cmd_sr_tmp;
  rcp_cmd_t [REGF_SEQ-1:0]                                  r0_rcp_cmd_sr_tmpD;
  logic [REGF_SEQ-1:0]                                      r0_rd_last_mask_sr;
  logic [REGF_SEQ-1:0]                                      r0_rd_last_mask_sr_tmp;
  logic [REGF_SEQ-1:0]                                      r0_rd_last_mask_sr_tmpD;

  assign r0_rcp_cmd_sr            = r0_rcp_cmd_sr_tmpD;
  assign r0_rd_is_body_sr         = r0_rd_is_body_sr_tmpD;
  assign r0_rd_last_mask_sr       = r0_rd_last_mask_sr_tmpD;

  assign r0_rcp_cmd_sr_tmpD[0]      = rcp_fifo_out_cmd;
  assign r0_rd_is_body_sr_tmpD[0]   = r0_rd_is_body;
  assign r0_rd_last_mask_sr_tmpD[0] = r0_rd_last_mask;
  generate
    if (REGF_SEQ > 1) begin
      assign r0_rcp_cmd_sr_tmpD[REGF_SEQ-1:1]      = r0_rcp_cmd_sr_tmp[REGF_SEQ-2:0];
      assign r0_rd_is_body_sr_tmpD[REGF_SEQ-1:1]   = r0_rd_is_body_sr_tmp[REGF_SEQ-2:0];
      assign r0_rd_last_mask_sr_tmpD[REGF_SEQ-1:1] = r0_rd_last_mask_sr_tmp[REGF_SEQ-2:0];
    end
  endgenerate

  always_ff @(posedge clk) begin
    r0_rcp_cmd_sr_tmp      <= r0_rcp_cmd_sr_tmpD;
    r0_rd_is_body_sr_tmp   <= r0_rd_is_body_sr_tmpD;
    r0_rd_last_mask_sr_tmp <= r0_rd_last_mask_sr_tmpD;
  end

  generate
    if (REQ_ALL) begin : gen_req_all
      // Here:
      // KS_IF_SUBW_NB = REGF_SEQ
      // KS_IF_COEF_NB = REGF_SEQ_COEF_NB
      // Therefore, we can connect directly.

      assign blram_wr_data     = r0_rd_data;

      always_comb
        for (int i=0; i<KS_IF_SUBW_NB; i=i+1) begin
          blram_wr_pid[i] = r0_rcp_cmd_sr[i].pid;
          blram_wr_en[i]  = r0_rd_data_avail[i*KS_IF_COEF_NB] & ( (i==0) | ~r0_rd_is_body_sr[i]);
          blram_wr_pbs_last[i] = (i==0) ? r0_rd_is_body : r0_rd_last_mask_sr[i];
        end

      assign rcp_fifo_out_rdy = blram_wr_en[0] & blram_wr_pbs_last[0];

      assign c0_enough_location = 1'b1;

    end
    else begin : gen_no_req_all
      logic [DIV_NB-1:0][LBY-1:0][MOD_Q_W-1:0]                r1_div_data;
      logic [DIV_NB-1:0]                                      r1_div_vld;
      logic [DIV_NB-1:0]                                      r1_div_rdy;

      logic [REGF_SEQ-1:0][REGF_SEQ_COEF_NB-1:0][MOD_Q_W-1:0] r1_data;
      logic [REGF_SEQ-1:0]                                    r1_vld;
      logic [REGF_SEQ-1:0]                                    r1_rdy;

      logic [DIV_NB-1:0]                                      r1_div_sample;

      logic [REGF_SEQ-1:0]                                    r0_rd_vld;
      logic [REGF_SEQ-1:0]                                    r0_rd_rdy;

      assign r1_div_data = r1_data;

      always_comb
        for (int i=0; i<DIV_NB; i=i+1) begin
          r1_div_vld[i]    = &r1_vld[i*DIV_SEQ+:DIV_SEQ];
          r1_div_sample[i] = r1_div_vld[i] & r1_div_rdy[i];
          for (int j=0; j<DIV_SEQ; j=j+1) begin
            logic [DIV_SEQ-1:0] mask;
            mask = 1 << j;
            r1_rdy[i*DIV_SEQ+j] = r1_div_rdy[i] & (&(mask | r1_vld[i*DIV_SEQ+:DIV_SEQ]));
          end
        end

      for (genvar gen_i=0; gen_i<REGF_SEQ; gen_i=gen_i+1) begin : gen_data_fifo_loop
        assign r0_rd_vld[gen_i] = (gen_i < DIV_SEQ) ? r0_rd_data_avail[gen_i*REGF_SEQ_COEF_NB] :
                                  r0_rd_data_avail[gen_i*REGF_SEQ_COEF_NB] & ~r0_rd_is_body_sr[gen_i] ; // do not store the dummy coef that goes with the body coef

        // Realign the data
        fifo_reg #(
          .WIDTH       (REGF_SEQ_COEF_NB*MOD_Q_W),
          .DEPTH       (DATA_FIFO_DEPTH + (REGF_SEQ-gen_i)),
          .LAT_PIPE_MH ({1'b1, 1'b1})
        ) r1_fifo_reg (
          .clk      (clk),
          .s_rst_n  (s_rst_n),

          .in_data  (r0_rd_data[gen_i*REGF_SEQ_COEF_NB+:REGF_SEQ_COEF_NB]),
          .in_vld   (r0_rd_vld[gen_i]),
          .in_rdy   (r0_rd_rdy[gen_i]),

          .out_data (r1_data[gen_i]),
          .out_vld  (r1_vld[gen_i]),
          .out_rdy  (r1_rdy[gen_i])
        );

// pragma translate_off
        always_ff @(posedge clk)
          if (!s_rst_n) begin
            // do nothing
          end
          else begin
            if (r0_rd_vld[gen_i])
              assert(r0_rd_rdy[gen_i])
              else begin
                $fatal(1,"%t> ERROR: data fifo[%0d] is not ready!", $time, gen_i);
              end
          end
// pragma translate_on
      end // gen_data_fifo_loop

      logic [DIV_W-1:0]      r1_div_sel;
      logic [DIV_W-1:0]      r1_div_selD;
      logic [BLWE_DIV_W-1:0] r1_div_cnt;
      logic [BLWE_DIV_W-1:0] r1_div_cntD;
      logic                  r1_is_body;
      logic                  r1_is_bodyD;
      logic                  r1_last_div_sel;
      logic                  r1_last_div_cnt;

      logic                  r1_out_avail;
      logic                  r1_out_avail_tmp;

      assign r1_last_div_sel = r1_div_sel == DIV_NB-1;
      assign r1_last_div_cnt = r1_div_cnt == BLWE_DIV_NB-1;
      assign r1_div_selD     = r1_out_avail ? (r1_is_body || r1_last_div_sel) ? '0 : r1_div_sel + 1 : r1_div_sel;
      assign r1_div_cntD     = r1_out_avail ? (r1_is_body || r1_last_div_cnt) ? '0 : r1_div_cnt + 1 : r1_div_cnt;
      assign r1_is_bodyD     = r1_out_avail ? r1_is_body ? 1'b0 : r1_last_div_cnt ? 1'b1 : r1_is_body : r1_is_body;

      assign r1_out_avail_tmp = r1_div_vld[r1_div_sel];
      assign r1_out_avail     = rcp_fifo_out_vld & r1_out_avail_tmp;

      always_ff @(posedge clk)
        if (!s_rst_n) begin
          r1_div_sel <= '0;
          r1_div_cnt <= '0;
          r1_is_body <= 1'b0;
        end
        else begin
          r1_div_sel <= r1_div_selD;
          r1_div_cnt <= r1_div_cntD;
          r1_is_body <= r1_is_bodyD;
        end

        //== Ready
        always_comb
          for (int i=0; i<DIV_NB; i=i+1)
            r1_div_rdy[i] = rcp_fifo_out_vld & (r1_div_sel == i);

        assign rcp_fifo_out_rdy = r1_out_avail_tmp & r1_is_body;

        //== Output
        assign blram_wr_en       = r1_out_avail;
        assign blram_wr_pid      = rcp_fifo_out_cmd.pid;
        assign blram_wr_data     = r1_div_data[r1_div_sel];
        assign blram_wr_pbs_last[0] = r1_is_body;

        if (KS_IF_SUBW_NB > 1) begin
          assign blram_wr_pbs_last[KS_IF_SUBW_NB-1:1] = '0;
        end

        //== Output FIFO location count
        // We assume that we have a FIFO which capacity is to receive DATA_THRESHOLD,
        // i.e. all the data that are requested.
        // Since there is no backpressure, once received the data are sent to the output at
        // each DIV_NB cycle.
        // Therefore, it is possible to do a new request when this FIFO is at most filled
        // with RD_LATENCY/DIV_NB elements.
        //
        // Note that we can do this with the first r1_fifo_reg only.
        // Then we count DATA_THRESHOLD elements, and this FIFO's outputs.
        logic [OUT_FIFO_CNT_W-1:0] out_fifo_cnt;
        logic [OUT_FIFO_CNT_W-1:0] out_fifo_cntD;
        logic [OUT_FIFO_CNT_W-1:0] out_fifo_cnt_inc;
        logic                      out_fifo_cnt_dec;

        assign out_fifo_cnt_inc = c0_send_req ? c0_rd_body ? 1 : (c0_regf_req.word_nb_m1 + 1)*DIV_NB : '0;
        assign out_fifo_cnt_dec = |r1_div_sample;
        assign out_fifo_cntD    = out_fifo_cnt + out_fifo_cnt_inc - out_fifo_cnt_dec;

        assign c0_enough_location = out_fifo_cnt < OUT_FIFO_CNT_THRES;

        always_ff @(posedge clk)
          if (!s_rst_n) out_fifo_cnt <= '0;
          else          out_fifo_cnt <= out_fifo_cntD;

    end // else
  endgenerate

// ============================================================================================== --
// Output pipe
// ============================================================================================== --
  logic ldb_seq_doneD;

  assign ldb_seq_doneD = blram_wr_en[0] & blram_wr_pbs_last[0];

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      pep_blram_wr_en <= '0;
      ldb_seq_done    <= 1'b0;
    end
    else begin
      pep_blram_wr_en <= blram_wr_en;
      ldb_seq_done    <= ldb_seq_doneD;
    end

  always_ff @(posedge clk) begin
    pep_blram_wr_pid      <= blram_wr_pid;
    pep_blram_wr_data     <= blram_wr_data;
    pep_blram_wr_pbs_last <= blram_wr_pbs_last;
  end

// ============================================================================================== --
// Load duration for register if
// ============================================================================================== --
  // Signal that remains at 1 during the cycles when a load is pending.
  logic ldb_rif_rcp_durD;

  assign ldb_rif_rcp_durD = (rcp_fifo_out_vld && rcp_fifo_out_rdy) ? 1'b0 : rcp_fifo_out_vld;

  always_ff @(posedge clk)
    if (!s_rst_n) ldb_rif_rcp_dur <= 1'b0;
    else          ldb_rif_rcp_dur <= ldb_rif_rcp_durD;
endmodule
