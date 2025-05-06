// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals the regfile rdite path arbitration.
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

module regf_read_arbiter
  import regf_common_param_pkg::*;
#(
  parameter int PEA_PERIOD = REGF_COEF_NB, // number of cycles between 2 arbitrations
  parameter int PEM_PERIOD = 4,
  parameter int PEP_PERIOD = 1
)
(
  input  logic                                                   clk,        // clock
  input  logic                                                   s_rst_n,    // synchronous reset

  // PE MEM rdite
  input  logic                                                   pem_regf_rd_req_vld,
  output logic                                                   pem_regf_rd_req_rdy,
  input  logic [REGF_RD_REQ_W-1:0]                               pem_regf_rd_req,

  // PE ALU rdite
  input  logic                                                   pea_regf_rd_req_vld,
  output logic                                                   pea_regf_rd_req_rdy,
  input  logic [REGF_RD_REQ_W-1:0]                               pea_regf_rd_req,

  // PE PBS rdite
  input  logic                                                   pep_regf_rd_req_vld,
  output logic                                                   pep_regf_rd_req_rdy,
  input  logic [REGF_RD_REQ_W-1:0]                               pep_regf_rd_req,

  // Output to Regfile RAM
  output logic [REGF_SEQ-1:0]                                    rarb_rram_rd_en,
  output logic [REGF_SEQ-1:0][REGF_RAM_WORD_ADD_W-1:0]           rarb_rram_rd_add,
  output logic [REGF_SEQ-1:0][PE_NB-1:0]                         rarb_rram_pe_id_1h,
  output logic [REGF_SEQ-1:0][REGF_SIDE_W-1:0]                   rarb_rram_side,

  // Output to body RAM
  output logic                                                   rarb_boram_rd_en,
  output logic [REGF_REGID_W-1:0]                                rarb_boram_rd_add,
  output logic [PE_NB-1:0]                                       rarb_boram_pe_id_1h,
  output logic [REGF_SIDE_W-1:0]                                 rarb_boram_side

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
  logic [PE_NB-1:0]         in_req_vld;
  logic [PE_NB-1:0]         in_req_rdy;
  regf_rd_req_t [PE_NB-1:0] in_req;

  logic [PE_NB-1:0]         s0_req_vld;
  logic [PE_NB-1:0]         s0_req_rdy;
  regf_rd_req_t [PE_NB-1:0] s0_req;

  assign in_req_vld[PEA_ID]  = pea_regf_rd_req_vld;
  assign pea_regf_rd_req_rdy = in_req_rdy[PEA_ID];
  assign in_req[PEA_ID]      = pea_regf_rd_req;

  assign in_req_vld[PEM_ID]  = pem_regf_rd_req_vld;
  assign pem_regf_rd_req_rdy = in_req_rdy[PEM_ID];
  assign in_req[PEM_ID]      = pem_regf_rd_req;

  assign in_req_vld[PEP_ID]  = pep_regf_rd_req_vld;
  assign pep_regf_rd_req_rdy = in_req_rdy[PEP_ID];
  assign in_req[PEP_ID]      = pep_regf_rd_req;

  generate
    for (genvar gen_p = 0; gen_p < PE_NB; gen_p = gen_p + 1) begin : gen_req_input_pipe
      fifo_element #(
        .WIDTH          (REGF_RD_REQ_W),
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
    end
  endgenerate

// ============================================================================================== --
// s0 : Arbiter
// ============================================================================================== --
  //== Selection
  logic [PE_NB-1:0]                           s0_pe_arbitrable; // (1) means that the corresponding PE can be selected.
  logic [PE_NB-1:0]                           s0_sel_1rst_1h;
  logic [PE_NB-1:0]                           s0_sel_2nd_1h;
  logic [PE_NB-1:0]                           s0_sel_2nd_1hD;
  logic [PE_NB-1:0]                           s0_sel_1h; // request selection
  regf_rd_req_t                               s0_sel_req;
  logic [PE_NB-1:0]                           s0_sel_1rst_1h_tmp; // Version without the vld in order to build the rdy

  //== Counters
  // Keep track of last arbitration for each input
  logic [PE_NB-1:0][PE_PERIOD_CNT_W-1:0]      s0_period_cnt;
  logic [PE_NB-1:0][PE_PERIOD_CNT_W-1:0]      s0_period_cntD;
  logic [PE_NB-1:0][REGF_BLWE_WORD_CNT_W-1:0] s0_word_cnt; // counts number of words read
  logic [PE_NB-1:0][REGF_BLWE_WORD_CNT_W-1:0] s0_word_cntD;
  logic [PE_NB-1:0]                           s0_last_word;
  logic [PE_NB-1:0]                           s0_inc_word;

  assign s0_sel_1h = s0_sel_1rst_1h | s0_sel_2nd_1h;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      s0_period_cnt <= '0;
      s0_sel_2nd_1h <= '0;
      s0_word_cnt   <= '0;
    end
    else begin
      s0_period_cnt <= s0_period_cntD;
      s0_sel_2nd_1h <= s0_sel_2nd_1hD;
      s0_word_cnt   <= s0_word_cntD;
    end

  // Once selected, start to count the number of cycles before next selection of this PE is possible.
  always_comb
    for (int p=0; p<PE_NB; p=p+1) begin
      s0_period_cntD[p] = s0_sel_1rst_1h[p] ? PE_PERIOD[p]-1 :
                              s0_period_cnt[p] == '0 ? s0_period_cnt[p] : s0_period_cnt[p] - 1;

      s0_last_word[p] = s0_word_cnt[p] == s0_req[p].word_nb_m1;
      s0_inc_word[p]  = (s0_sel_1rst_1h[p] & ~s0_req[p].do_2_read) | s0_sel_2nd_1h[p];
      s0_word_cntD[p] = s0_inc_word[p] ? s0_last_word[p] ? '0 : s0_word_cnt[p] + 1 : s0_word_cnt[p];
    end

  //== Arbitration
  // Is arbitrable when the period number of cycles is reached.
  always_comb
    for (int p=0; p<PE_NB; p=p+1)
      s0_pe_arbitrable[p] = (s0_period_cnt[p] == 0);

  assign s0_sel_1rst_1h = s0_sel_1rst_1h_tmp & s0_req_vld;
  generate
    for (genvar gen_p=0; gen_p<PE_NB; gen_p=gen_p+1) begin : gen_pe_nb_loop
      if (gen_p == 0) begin : gen_0
        assign s0_sel_1rst_1h_tmp[gen_p] = s0_pe_arbitrable[gen_p] & (s0_sel_2nd_1h == 0); // most priority
      end
      else begin : gen_no_0
        assign s0_sel_1rst_1h_tmp[gen_p] = s0_pe_arbitrable[gen_p] & (s0_sel_2nd_1h == 0) & (s0_sel_1rst_1h[gen_p-1:0] == 0);
      end
    end
  endgenerate

  always_comb
    for (int p=0; p<PE_NB; p=p+1)
      s0_sel_2nd_1hD[p] = s0_sel_1rst_1h[p] & s0_req[p].do_2_read;

  always_comb begin
    s0_sel_req = 0;
    for (int p=0; p<PE_NB; p=p+1)
      s0_sel_req = s0_sel_1h[p] ? s0_req[p] : s0_sel_req;
  end

  always_comb
    for (int p=0; p<PE_NB; p=p+1)
      s0_req_rdy[p] = ((s0_sel_1rst_1h_tmp[p] & ~s0_req[p].do_2_read) | s0_sel_2nd_1h[p]) & s0_last_word[p];

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
        if (s0_sel_1rst_1h[p]) begin
          assert(s0_pe_arbitrable[p])
          else begin
            $fatal(1,"%t > ERROR: Request selected while not arbitrable!",$time);
          end
        end
    end
// pragma translate_on

  //== For next step
  logic [REGF_BLWE_WORD_CNT_W-1:0] s0_sel_word_cnt;
  logic                            s0_read_2nd;
  logic                            s0_read_last_word;

  assign s0_read_2nd = |s0_sel_2nd_1h;
  assign s0_read_last_word = |(s0_sel_1h & s0_last_word);

  always_comb begin
    s0_sel_word_cnt = '0;
    for (int p=0; p<PE_NB; p=p+1)
      s0_sel_word_cnt = s0_sel_1h[p] ? s0_word_cnt[p] : s0_sel_word_cnt;
  end

// ============================================================================================== --
// s1 : Build read command
// ============================================================================================== --
  regf_rd_req_t                    s1_sel_req;
  logic [REGF_BLWE_WORD_CNT_W-1:0] s1_sel_word_cnt; // counts number of words read
  logic                            s1_read_2nd;
  logic                            s1_avail;
  logic [PE_NB-1:0]                s1_sel_1h;
  logic                            s1_read_last_word;

  always_ff @(posedge clk)
    if (!s_rst_n) s1_avail <= 1'b0;
    else          s1_avail <= |s0_sel_1h;

  always_ff @(posedge clk) begin
    s1_sel_req        <= s0_sel_req;
    s1_sel_word_cnt   <= s0_sel_word_cnt;
    s1_read_2nd       <= s0_read_2nd;
    s1_sel_1h         <= s0_sel_1h;
    s1_read_last_word <= s0_read_last_word;
  end

  logic                            s1_is_body;
  logic                            s1_last_mask;
  logic [REGF_RAM_WORD_ADD_W-1:0]  s1_add;
  logic [REGF_REGID_W-1:0]         s1_reg_id;
  logic [REGF_BLWE_WORD_CNT_W-1:0] s1_word_ofs;
  logic [PE_ID_W-1:0]              s1_pe_id;
  regf_side_t                      s1_side;

  assign s1_reg_id    = s1_read_2nd ? s1_sel_req.reg_id_1 : s1_sel_req.reg_id;
  assign s1_word_ofs  = s1_sel_req.start_word + s1_sel_word_cnt;
  assign s1_add       = s1_reg_id * REGF_BLWE_WORD_PER_RAM + s1_word_ofs;
  assign s1_is_body   = s1_word_ofs == REGF_BLWE_WORD_PER_RAM;
  assign s1_last_mask = s1_word_ofs == REGF_BLWE_WORD_PER_RAM - 1;

  assign s1_side.last_mask = s1_last_mask;
  assign s1_side.last_word = s1_read_last_word;
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
          $fatal(1,"%t > ERROR: Regfile read address overflow! REGF_REG_NB=%0d reg_id=%0d.",$time,REGF_REG_NB,s1_sel_req.reg_id);
        end
    end
// pragma translate_on
// ============================================================================================== --
// s2 : Sequentialize read commands
// ============================================================================================== --
  logic [REGF_SEQ-1:0]                          s2_rram_rd_en;
  logic [REGF_SEQ-1:0][REGF_RAM_WORD_ADD_W-1:0] s2_rram_rd_add;
  regf_side_t [REGF_SEQ-1:0]                    s2_rram_side;

  logic                                         s2_boram_rd_en;
  logic [REGF_REGID_W-1:0]                      s2_boram_rd_add;
  regf_side_t                                   s2_boram_side;

  logic [REGF_SEQ-1:0]                          s2_rram_rd_enD;
  logic [REGF_SEQ-1:0][REGF_RAM_WORD_ADD_W-1:0] s2_rram_rd_addD;
  regf_side_t [REGF_SEQ-1:0]                    s2_rram_sideD;

  logic                                         s2_boram_rd_enD;
  logic [REGF_REGID_W-1:0]                      s2_boram_rd_addD;
  regf_side_t                                   s2_boram_sideD;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      s2_rram_rd_en  <= '0;
      s2_boram_rd_en <= 1'b0;
    end
    else begin
      s2_rram_rd_en  <= s2_rram_rd_enD ;
      s2_boram_rd_en <= s2_boram_rd_enD;
    end

  always_ff @(posedge clk) begin
    s2_rram_rd_add  <= s2_rram_rd_addD;
    s2_rram_side    <= s2_rram_sideD;
    s2_boram_rd_add <= s2_boram_rd_addD;
    s2_boram_side   <= s2_boram_sideD;
  end

  assign s2_rram_rd_enD[0]  = s1_avail & ~s1_is_body;
  assign s2_rram_rd_addD[0] = s1_add;
  assign s2_rram_sideD[0]   = s1_side;
  assign s2_boram_rd_enD    = s1_avail & s1_is_body;
  assign s2_boram_rd_addD   = s1_reg_id;
  assign s2_boram_sideD     = s1_side;

  generate
    if (REGF_SEQ > 1) begin : gen_seq
      assign s2_rram_rd_enD[REGF_SEQ-1:1]  = s2_rram_rd_en[REGF_SEQ-2:0];
      assign s2_rram_rd_addD[REGF_SEQ-1:1] = s2_rram_rd_add[REGF_SEQ-2:0];
      assign s2_rram_sideD[REGF_SEQ-1:1]   = s2_rram_side[REGF_SEQ-2:0];
    end
  endgenerate

// ============================================================================================== --
// Output
// ============================================================================================== --
  logic [REGF_SEQ-1:0][PE_NB-1:0] s2_rram_pe_id_1h;
  logic [PE_NB-1:0]               s2_boram_pe_id_1h;

  always_comb
    for (int s=0; s<REGF_SEQ; s=s+1)
      s2_rram_pe_id_1h[s] = 1 << s2_rram_side[s].pe_id;

  assign s2_boram_pe_id_1h = 1 << s2_boram_side.pe_id;

  // Output to Regfile RAM
  assign rarb_rram_rd_en    = s2_rram_rd_en ;
  assign rarb_rram_rd_add   = s2_rram_rd_add;
  assign rarb_rram_side     = s2_rram_side  ;
  assign rarb_rram_pe_id_1h = s2_rram_pe_id_1h;

  // Output to body RAM
  assign rarb_boram_rd_en    = s2_boram_rd_en ;
  assign rarb_boram_rd_add   = s2_boram_rd_add;
  assign rarb_boram_side     = s2_boram_side  ;
  assign rarb_boram_pe_id_1h = s2_boram_pe_id_1h;
endmodule





