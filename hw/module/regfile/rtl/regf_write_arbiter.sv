// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals the regfile write path arbitration.
// 3 actors need to access the regfile:
// * ALU
// * PBS
// * MEM (for HBM/DDR load/store)
//
// Once the requests sampled, the module decides which input to arbiter.
// Arbitration configuration.
// PE*_PERIOD : number of cycles between 2 arbitrations of the PE* input.
//
// 1 : means that the input can be chosen every cycle.
//
// PE : stands for processing element
//
// ==============================================================================================

module regf_write_arbiter
  import param_tfhe_pkg::*;
  import regf_common_param_pkg::*;
#(
  parameter int PEA_PERIOD = REGF_WORD_NB,
  parameter int PEM_PERIOD = 4,
  parameter int PEP_PERIOD = 1
)
(
  input  logic                                                       clk,        // clock
  input  logic                                                       s_rst_n,    // synchronous reset

  // PE MEM write
  input  logic                                                       pem_regf_wr_req_vld,
  output logic                                                       pem_regf_wr_req_rdy,
  input  logic [REGF_WR_REQ_W-1:0]                                   pem_regf_wr_req,

  input  logic [REGF_COEF_NB-1:0]                                    pem_regf_wr_data_vld,
  output logic [REGF_COEF_NB-1:0]                                    pem_regf_wr_data_rdy,
  input  logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0]                       pem_regf_wr_data,

  // PE ALU write
  input  logic                                                       pea_regf_wr_req_vld,
  output logic                                                       pea_regf_wr_req_rdy,
  input  logic [REGF_WR_REQ_W-1:0]                                   pea_regf_wr_req,

  input  logic [REGF_COEF_NB-1:0]                                    pea_regf_wr_data_vld,
  output logic [REGF_COEF_NB-1:0]                                    pea_regf_wr_data_rdy,
  input  logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0]                       pea_regf_wr_data,

  // PE PBS write
  input  logic                                                       pep_regf_wr_req_vld,
  output logic                                                       pep_regf_wr_req_rdy,
  input  logic [REGF_WR_REQ_W-1:0]                                   pep_regf_wr_req,

  input  logic [REGF_COEF_NB-1:0]                                    pep_regf_wr_data_vld,
  output logic [REGF_COEF_NB-1:0]                                    pep_regf_wr_data_rdy,
  input  logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0]                       pep_regf_wr_data,

  // Output to Regfile RAM
  output logic [REGF_SEQ-1:0][REGF_SEQ_WORD_NB-1:0][REGF_WORD_W-1:0] warb_rram_wr_data,
  output logic [REGF_SEQ-1:0]                                        warb_rram_wr_en,
  output logic [REGF_SEQ-1:0][REGF_RAM_WORD_ADD_W-1:0]               warb_rram_wr_add,

  // Output to Regfile RAM
  output logic [MOD_Q_W-1:0]                                         warb_boram_wr_data,
  output logic                                                       warb_boram_wr_en,
  output logic [REGF_REGID_W-1:0]                                    warb_boram_wr_add,

  // Write ack
  output logic [PE_NB-1:0]                                           warb_wr_ack_1h
);
// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int PEA_PERIOD_CNT_W = $clog2(PEA_PERIOD+1) == 0 ? 1 : $clog2(PEA_PERIOD+1);
  localparam int PEM_PERIOD_CNT_W = $clog2(PEM_PERIOD+1) == 0 ? 1 : $clog2(PEM_PERIOD+1);
  localparam int PEP_PERIOD_CNT_W = $clog2(PEP_PERIOD+1) == 0 ? 1 : $clog2(PEP_PERIOD+1);

  localparam int PE_PERIOD_CNT_W = PEA_PERIOD_CNT_W > PEM_PERIOD_CNT_W ? PEA_PERIOD_CNT_W > PEP_PERIOD_CNT_W ? PEA_PERIOD_CNT_W : PEP_PERIOD_CNT_W:
                                                                         PEM_PERIOD_CNT_W > PEP_PERIOD_CNT_W ? PEM_PERIOD_CNT_W : PEP_PERIOD_CNT_W;

  localparam [PE_NB-1:0][31:0] PE_PERIOD   = {PEP_PERIOD,
                                              PEM_PERIOD,
                                              PEA_PERIOD};

// ============================================================================================== --
// Input pipe
// ============================================================================================== --
  // Request
  logic [PE_NB-1:0]                                    in_req_vld;
  logic [PE_NB-1:0]                                    in_req_rdy;
  regf_wr_req_t [PE_NB-1:0]                            in_req;

  logic [PE_NB-1:0]                                    s0_req_vld;
  logic [PE_NB-1:0]                                    s0_req_rdy;
  regf_wr_req_t [PE_NB-1:0]                            s0_req;

  // Data
  logic [PE_NB-1:0][REGF_WORD_NB-1:0]                  in_wr_data_vld;
  logic [PE_NB-1:0][REGF_WORD_NB-1:0]                  in_wr_data_rdy;
  logic [PE_NB-1:0][REGF_WORD_NB-1:0][REGF_WORD_W-1:0] in_wr_data;

  logic [PE_NB-1:0][REGF_WORD_NB-1:0]                  in0_data_vld;
  logic [PE_NB-1:0][REGF_WORD_NB-1:0]                  in0_data_rdy;
  logic [PE_NB-1:0][REGF_WORD_NB-1:0][REGF_WORD_W-1:0] in0_data;

  assign in_req_vld[PEA_ID]  = pea_regf_wr_req_vld;
  assign pea_regf_wr_req_rdy = in_req_rdy[PEA_ID];
  assign in_req[PEA_ID]      = pea_regf_wr_req;

  assign in_req_vld[PEM_ID]  = pem_regf_wr_req_vld;
  assign pem_regf_wr_req_rdy = in_req_rdy[PEM_ID];
  assign in_req[PEM_ID]      = pem_regf_wr_req;

  assign in_req_vld[PEP_ID]  = pep_regf_wr_req_vld;
  assign pep_regf_wr_req_rdy = in_req_rdy[PEP_ID];
  assign in_req[PEP_ID]      = pep_regf_wr_req;

  always_comb
    for (int w=0; w<REGF_WORD_NB; w=w+1) begin
      in_wr_data_vld[PEA_ID][w]                                                = pea_regf_wr_data_vld[w*REGF_COEF_PER_URAM_WORD];
      pea_regf_wr_data_rdy[w*REGF_COEF_PER_URAM_WORD+:REGF_COEF_PER_URAM_WORD] = {REGF_COEF_PER_URAM_WORD{in_wr_data_rdy[PEA_ID][w]}};
      in_wr_data[PEA_ID][w]                                                    = pea_regf_wr_data[w*REGF_COEF_PER_URAM_WORD+:REGF_COEF_PER_URAM_WORD];

      in_wr_data_vld[PEM_ID][w]                                                = pem_regf_wr_data_vld[w*REGF_COEF_PER_URAM_WORD];
      pem_regf_wr_data_rdy[w*REGF_COEF_PER_URAM_WORD+:REGF_COEF_PER_URAM_WORD] = {REGF_COEF_PER_URAM_WORD{in_wr_data_rdy[PEM_ID][w]}};
      in_wr_data[PEM_ID][w]                                                    = pem_regf_wr_data[w*REGF_COEF_PER_URAM_WORD+:REGF_COEF_PER_URAM_WORD];

      in_wr_data_vld[PEP_ID][w]                                                = pep_regf_wr_data_vld[w*REGF_COEF_PER_URAM_WORD];
      pep_regf_wr_data_rdy[w*REGF_COEF_PER_URAM_WORD+:REGF_COEF_PER_URAM_WORD] = {REGF_COEF_PER_URAM_WORD{in_wr_data_rdy[PEP_ID][w]}};
      in_wr_data[PEP_ID][w]                                                    = pep_regf_wr_data[w*REGF_COEF_PER_URAM_WORD+:REGF_COEF_PER_URAM_WORD];
    end

  generate
    for (genvar gen_p = 0; gen_p < PE_NB; gen_p = gen_p + 1) begin : gen_req_input_pipe
      fifo_element #(
        .WIDTH          (REGF_WR_REQ_W),
        .DEPTH          (2),
        .TYPE_ARRAY     (8'h12),
        .DO_RESET_DATA  (1'b0),
        .RESET_DATA_VAL (0)
      ) in_req_fifo_element (
        .clk     (clk),
        .s_rst_n (s_rst_n),

        .in_data (in_req[gen_p]),
        .in_vld  (in_req_vld[gen_p]),
        .in_rdy  (in_req_rdy[gen_p]),

        .out_data(s0_req[gen_p]),
        .out_vld (s0_req_vld[gen_p]),
        .out_rdy (s0_req_rdy[gen_p])
      );

      for (genvar gen_i = 0; gen_i < REGF_WORD_NB; gen_i = gen_i + 1) begin : gen_data_loop
        fifo_element #(
          .WIDTH          (REGF_WORD_W),
          .DEPTH          (2),
          .TYPE_ARRAY     (8'h12),
          .DO_RESET_DATA  (1'b0),
          .RESET_DATA_VAL (0)
        ) in_data_fifo_element (
          .clk     (clk),
          .s_rst_n (s_rst_n),

          .in_data (in_wr_data[gen_p][gen_i]),
          .in_vld  (in_wr_data_vld[gen_p][gen_i]),
          .in_rdy  (in_wr_data_rdy[gen_p][gen_i]),

          .out_data(in0_data[gen_p][gen_i]),
          .out_vld (in0_data_vld[gen_p][gen_i]),
          .out_rdy (in0_data_rdy[gen_p][gen_i])
        );
      end
    end
  endgenerate

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
    end
    else begin
      for (int w=0; w<REGF_WORD_NB; w=w+1) begin
        assert(pea_regf_wr_data_vld[w*REGF_COEF_PER_URAM_WORD+:REGF_COEF_PER_URAM_WORD] == '0 || pea_regf_wr_data_vld[w*REGF_COEF_PER_URAM_WORD+:REGF_COEF_PER_URAM_WORD] == '1)
        else begin
          $fatal(1,"%t > ERROR: PEA to REGF valid are not coherent per WORD.", $time);
        end
        assert(pem_regf_wr_data_vld[w*REGF_COEF_PER_URAM_WORD+:REGF_COEF_PER_URAM_WORD] == '0 || pem_regf_wr_data_vld[w*REGF_COEF_PER_URAM_WORD+:REGF_COEF_PER_URAM_WORD] == '1)
        else begin
          $fatal(1,"%t > ERROR: PEM to REGF valid are not coherent per WORD.", $time);
        end
        assert(pep_regf_wr_data_vld[w*REGF_COEF_PER_URAM_WORD+:REGF_COEF_PER_URAM_WORD] == '0 || pep_regf_wr_data_vld[w*REGF_COEF_PER_URAM_WORD+:REGF_COEF_PER_URAM_WORD] == '1)
        else begin
          $fatal(1,"%t > ERROR: PEP to REGF valid are not coherent per WORD.", $time);
        end
      end
    end
// pragma translate_on

// ============================================================================================== --
// s0 : Arbiter
// ============================================================================================== --
  //== Selection
  logic [PE_NB-1:0]                           s0_pe_arbitrable; // (1) means that the corresponding PE can be selected.
  logic [PE_NB-1:0]                           s0_sel_1h;  // request selection
  regf_wr_req_t                               s0_sel_req; // selected request
  logic [PE_NB-1:0]                           s0_sel_1h_tmp;

  //== Counters
  // Keep track of last arbitration for each input
  logic [PE_NB-1:0][PE_PERIOD_CNT_W-1:0]      s0_period_cnt;
  logic [PE_NB-1:0][PE_PERIOD_CNT_W-1:0]      s0_period_cntD;
  logic [PE_NB-1:0][REGF_BLWE_WORD_CNT_W-1:0] s0_word_cnt; // counts number of words read
  logic [PE_NB-1:0][REGF_BLWE_WORD_CNT_W-1:0] s0_word_cntD;
  logic [PE_NB-1:0]                           s0_last_word;


  always_ff @(posedge clk)
    if (!s_rst_n) begin
      s0_period_cnt <= '0; // every PE is arbitrable
      s0_word_cnt   <= '0;
    end
    else begin
      s0_period_cnt <= s0_period_cntD;
      s0_word_cnt   <= s0_word_cntD;
    end

  // Once selected, start to count the number of cycles before next selection of this PE is possible.
  always_comb
    for (int p=0; p<PE_NB; p=p+1) begin
      s0_period_cntD[p] = s0_sel_1h[p] ? PE_PERIOD[p]-1 :
                              s0_period_cnt[p] == '0 ? s0_period_cnt[p] : s0_period_cnt[p] - 1;

      s0_last_word[p] = s0_word_cnt[p] == s0_req[p].word_nb_m1;
      s0_word_cntD[p] = s0_sel_1h[p] ?
                            s0_last_word[p] ? '0 : s0_word_cnt[p] + 1 : s0_word_cnt[p];
    end

  //== Arbitration
  always_comb
    for (int p=0; p<PE_NB; p=p+1)
      s0_pe_arbitrable[p] = (s0_period_cnt[p] == 0);

  assign s0_sel_1h = s0_sel_1h_tmp & s0_req_vld;
  generate
    for (genvar gen_p=0; gen_p<PE_NB; gen_p=gen_p+1) begin : gen_pe_nb_loop
      if (gen_p == 0) begin : gen_0
        assign s0_sel_1h_tmp[gen_p] = s0_pe_arbitrable[gen_p]; // most priority
      end
      else begin : gen_no_0
        assign s0_sel_1h_tmp[gen_p] = s0_pe_arbitrable[gen_p] & (s0_sel_1h[gen_p-1:0] == 0);
      end
    end
  endgenerate

  always_comb begin
    s0_sel_req = '0;
    for (int p=0; p<PE_NB; p=p+1)
      s0_sel_req = s0_sel_1h[p] ? s0_req[p] : s0_sel_req;
  end

  always_comb
    for (int p=0; p<PE_NB; p=p+1)
      s0_req_rdy[p] = s0_sel_1h_tmp[p] & s0_last_word[p];

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      assert($countones(s0_sel_1h) < 2)
      else begin
        $fatal(1,"%t > ERROR: s0_sel_1h contains several 1s!", $time);
      end

      for (int p=0; p<PE_NB; p=p+1)
        if (s0_sel_1h[p]) begin
          assert(s0_pe_arbitrable[p])
          else begin
            $fatal(1,"%t > ERROR: Request selected while not arbitrable!",$time);
          end
        end
    end
// pragma translate_on

  //== For next step
  logic [REGF_BLWE_WORD_CNT_W-1:0] s0_sel_word_cnt;

  always_comb begin
    s0_sel_word_cnt = '0;
    for (int p=0; p<PE_NB; p=p+1)
      s0_sel_word_cnt = s0_sel_1h[p] ? s0_word_cnt[p] : s0_sel_word_cnt;
  end

// ============================================================================================== --
// s1 : Build write command / Select input
// ============================================================================================== --
  //== Write command
  regf_wr_req_t                    s1_sel_req;
  logic [REGF_BLWE_WORD_CNT_W-1:0] s1_sel_word_cnt; // current word number to be written
  logic                            s1_avail;
  logic [PE_NB-1:0]                s1_sel_1h;
  logic [PE_NB-1:0]                s1_last_word;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      s1_avail  <= 1'b0;
      s1_sel_1h <= '0;
    end
    else begin
      s1_avail  <= |s0_sel_1h;
      s1_sel_1h <= s0_sel_1h;
    end
  always_ff @(posedge clk) begin
    s1_sel_req      <= s0_sel_req;
    s1_sel_word_cnt <= s0_sel_word_cnt;
    s1_last_word    <= s0_last_word;
  end

  logic                            s1_is_body;
  logic [REGF_RAM_WORD_ADD_W-1:0]  s1_add;
  logic [REGF_REGID_W-1:0]         s1_reg_id;
  logic [REGF_BLWE_WORD_CNT_W-1:0] s1_word_ofs;
  logic [PE_ID_W-1:0]              s1_pe_id;
  regf_side_t                      s1_side;
  logic                            s1_write_last_word;

  assign s1_write_last_word = |(s1_sel_1h & s1_last_word);
  assign s1_reg_id          = s1_sel_req.reg_id;
  assign s1_word_ofs        = s1_sel_req.start_word + s1_sel_word_cnt;
  assign s1_add             = s1_reg_id * REGF_BLWE_WORD_PER_RAM + s1_word_ofs;
  assign s1_is_body         = s1_word_ofs == REGF_BLWE_WORD_PER_RAM;

  assign s1_side.last_word = s1_write_last_word;
  assign s1_side.pe_id     = s1_pe_id;

  always_comb begin
    s1_pe_id = PE_NB-1;
    for (int p=0; p<PE_NB-1; p=p+1)
      s1_pe_id = s1_sel_1h[p] ? p : s1_pe_id;
  end

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      if (s1_avail)
        assert(s1_sel_req.reg_id < REGF_REG_NB)
        else begin
          $fatal(1,"%t > ERROR: Regfile write address overflow! REGF_REG_NB=%0d reg_id=%0d.",$time,REGF_REG_NB,s1_sel_req.reg_id);
        end
    end
// pragma translate_on

  //== Select data
  logic [REGF_SEQ-1:0][REGF_SEQ_WORD_NB-1:0][REGF_WORD_W-1:0] s1_sr_sel_data;
  logic [REGF_SEQ-1:0][PE_NB-1:0]                         s1_sr_sel_1h;
  logic [REGF_SEQ-1:0][PE_ID_W-1:0]                       s1_sr_pe_id;

  logic [REGF_SEQ-1:0][PE_NB-1:0]                         s1_sr_sel_1h_tmp;
  logic [REGF_SEQ-1:0][PE_ID_W-1:0]                       s1_sr_pe_id_tmp;
  logic [REGF_SEQ-1:0][PE_NB-1:0]                         s1_sr_sel_1h_tmpD;
  logic [REGF_SEQ-1:0][PE_ID_W-1:0]                       s1_sr_pe_id_tmpD;

  assign s1_sr_sel_1h_tmpD[0] = s1_sel_1h;
  assign s1_sr_pe_id_tmpD[0]  = s1_pe_id;

  generate
     if (REGF_SEQ > 1) begin : gen_s1_seq
      assign s1_sr_sel_1h_tmpD[REGF_SEQ-1:1] = s1_sr_sel_1h_tmp[REGF_SEQ-2:0];
      assign s1_sr_pe_id_tmpD[REGF_SEQ-1:1]  = s1_sr_pe_id_tmp[REGF_SEQ-2:0];
     end
  endgenerate

  always_ff @(posedge clk)
    if (!s_rst_n) s1_sr_sel_1h_tmp <= '0;
    else          s1_sr_sel_1h_tmp <= s1_sr_sel_1h_tmpD;

  always_ff @(posedge clk)
    s1_sr_pe_id_tmp <= s1_sr_pe_id_tmpD;

  assign s1_sr_sel_1h = s1_sr_sel_1h_tmpD;
  assign s1_sr_pe_id  = s1_sr_pe_id_tmpD;

  generate
    for (genvar gen_s=0; gen_s < REGF_SEQ;  gen_s=gen_s+1) begin : gen_s1_seq_loop
      assign s1_sr_sel_data[gen_s] = in0_data[s1_sr_pe_id[gen_s]][gen_s*REGF_SEQ_WORD_NB+:REGF_SEQ_WORD_NB];
      for (genvar gen_p=0; gen_p<PE_NB; gen_p=gen_p+1) begin : gen_s1_pe_loop
        assign in0_data_rdy[gen_p][gen_s*REGF_SEQ_WORD_NB+:REGF_SEQ_WORD_NB] = {REGF_SEQ_WORD_NB{s1_sr_sel_1h[gen_s][gen_p]}};
      end
    end
  endgenerate

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      for (int p=0; p<PE_NB; p=p+1)
        for (int i=0; i<REGF_WORD_NB; i=i+1)
          if (in0_data_rdy[p][i]) begin
            assert(in0_data_vld[p][i])
            else begin
              $fatal(1,"%t > ERROR: dataw not valid when needed.", $time);
            end
          end
    end
// pragma translate_on

//== Write acknowledge
  logic [PE_NB-1:0] warb_wr_ack_1hD;
  assign warb_wr_ack_1hD = s1_sel_1h & s1_last_word;

  always_ff @(posedge clk)
    if (!s_rst_n) warb_wr_ack_1h <= '0;
    else          warb_wr_ack_1h <= warb_wr_ack_1hD;

// ============================================================================================== --
// s2 : Sequentialize write commands and dataw
// ============================================================================================== --
  logic [REGF_SEQ-1:0]                                    s2_rram_wr_en;
  logic [REGF_SEQ-1:0][REGF_RAM_WORD_ADD_W-1:0]           s2_rram_wr_add;

  logic [REGF_SEQ-1:0][REGF_SEQ_WORD_NB-1:0][REGF_WORD_W-1:0] s2_wr_data;

  logic                                                   s2_boram_wr_en;
  logic [REGF_REGID_W-1:0]                                s2_boram_wr_add;
  regf_side_t                                             s2_boram_side;

  logic [REGF_SEQ-1:0]                                    s2_rram_wr_enD;
  logic [REGF_SEQ-1:0][REGF_RAM_WORD_ADD_W-1:0]           s2_rram_wr_addD;
  regf_side_t [REGF_SEQ-1:0]                              s2_rram_sideD;

  logic [REGF_SEQ-1:0][REGF_SEQ_WORD_NB-1:0][REGF_WORD_W-1:0] s2_wr_dataD;

  logic                                                   s2_boram_wr_enD;
  logic [REGF_REGID_W-1:0]                                s2_boram_wr_addD;
  regf_side_t                                             s2_boram_sideD;


  always_ff @(posedge clk)
    if (!s_rst_n) begin
      s2_rram_wr_en  <= '0;
      s2_boram_wr_en <= 1'b0;
    end
    else begin
      s2_rram_wr_en  <= s2_rram_wr_enD ;
      s2_boram_wr_en <= s2_boram_wr_enD;
    end

  always_ff @(posedge clk) begin
    s2_rram_wr_add  <= s2_rram_wr_addD;
    s2_boram_wr_add <= s2_boram_wr_addD;
    s2_boram_side   <= s2_boram_sideD;
    s2_wr_data      <= s2_wr_dataD;
  end

  assign s2_rram_wr_enD[0]  = s1_avail & ~s1_is_body;
  assign s2_rram_wr_addD[0] = s1_add;
  assign s2_rram_sideD[0]   = s1_side;
  assign s2_boram_wr_enD    = s1_avail & s1_is_body;
  assign s2_boram_wr_addD   = s1_reg_id;

  assign s2_wr_dataD = s1_sr_sel_data; // The "sequentialization" is already taken into account in s1_sr_sel_data

  generate
    if (REGF_SEQ > 1) begin : gen_seq
      assign s2_rram_wr_enD[REGF_SEQ-1:1]  = s2_rram_wr_en[REGF_SEQ-2:0];
      assign s2_rram_wr_addD[REGF_SEQ-1:1] = s2_rram_wr_add[REGF_SEQ-2:0];
    end
  endgenerate

// ============================================================================================== --
// Output
// ============================================================================================== --//
  // Output to Regfile RAM
  assign warb_rram_wr_en   = s2_rram_wr_en ;
  assign warb_rram_wr_add  = s2_rram_wr_add;
  assign warb_rram_wr_data = s2_wr_data;

  // Output to body RAM
  assign warb_boram_wr_en   = s2_boram_wr_en ;
  assign warb_boram_wr_add  = s2_boram_wr_add;
  assign warb_boram_wr_data = s2_wr_data[0][0][MOD_Q_W-1:0];

endmodule
