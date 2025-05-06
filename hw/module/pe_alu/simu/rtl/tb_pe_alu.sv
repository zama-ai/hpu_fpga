// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// pe_alu testbench.
// ==============================================================================================

module tb_pe_alu;
`timescale 1ns/10ps

  import param_tfhe_pkg::*;
  import regf_common_param_pkg::*;
  import hpu_common_instruction_pkg::*;

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int CLK_HALF_PERIOD = 1;
  localparam int ARST_ACTIVATION = 17;

  parameter  int INST_FIFO_DEPTH = 8;
  parameter  int ALU_NB          = 1;
  parameter  int OUT_FIFO_DEPTH  = 2;

  parameter  int PEA_PERIOD   = REGF_COEF_NB / ALU_NB == 1 ? 2 : REGF_COEF_NB / ALU_NB;
  parameter  int PEM_PERIOD   = 2;
  parameter  int PEP_PERIOD   = 1;

  parameter  int SAMPLE_NB    = 100;

  localparam int DOP_ALU_NB   = 7;
  localparam [DOP_ALU_NB-1:0][DOP_W-1:0] DOP_ALU_L = {DOP_MAC,DOP_SUB,DOP_ADD,DOP_MULS,DOP_SSUB,DOP_SUBS,DOP_ADDS};

  localparam int RAND_RANGE = 1024-1;
  localparam int URAM_LATENCY = 5;


  initial begin
    $display("> INFO : REGF_REG_NB=%0d",REGF_REG_NB);
    $display("> INFO : REGF_COEF_NB=%0d",REGF_COEF_NB);
    $display("> INFO : REGF_SEQ=%0d",REGF_SEQ);
    $display("> INFO : REGF_BLWE_WORD_PER_RAM=%0d",REGF_BLWE_WORD_PER_RAM);
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
  bit error_ack;
  bit error_data;
  bit error_req;

  assign error = error_ack | error_data | error_req;

  always_ff @(posedge clk)
    if (error) begin
      $display("%t > FAILURE !", $time);
      $finish;
    end

// ============================================================================================== --
// input / output signals
// ============================================================================================== --
  logic [PE_INST_W-1:0]                   inst;
  logic                                   inst_vld;
  logic                                   inst_rdy;

  logic                                   inst_ack;

  logic                                   pea_regf_wr_req_vld;
  logic                                   pea_regf_wr_req_rdy;
  regf_wr_req_t                           pea_regf_wr_req;

  logic [REGF_COEF_NB-1:0]                pea_regf_wr_data_vld;
  logic [REGF_COEF_NB-1:0]                pea_regf_wr_data_rdy;
  logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0]   pea_regf_wr_data;

  logic                                   regf_pea_wr_ack;


  logic                                   pea_regf_rd_req_vld;
  logic                                   pea_regf_rd_req_rdy;
  regf_rd_req_t                           pea_regf_rd_req;

  logic [REGF_COEF_NB-1:0]                regf_pea_rd_data_avail;
  logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0]   regf_pea_rd_data;
  logic                                   regf_pea_rd_last_word; // valid with avail[0]
  logic                                   regf_pea_rd_is_body;
  logic                                   regf_pea_rd_last_mask;

// ============================================================================================== --
// Design under test instance
// ============================================================================================== --
  pe_alu #(
    .INST_FIFO_DEPTH (INST_FIFO_DEPTH),
    .ALU_NB          (ALU_NB),
    .OUT_FIFO_DEPTH  (OUT_FIFO_DEPTH)
  ) dut (
    .clk                    (clk    ),
    .s_rst_n                (s_rst_n),

    .inst                   (inst),
    .inst_vld               (inst_vld),
    .inst_rdy               (inst_rdy),

    .inst_ack               (inst_ack),

    .pea_regf_wr_req_vld    (pea_regf_wr_req_vld),
    .pea_regf_wr_req_rdy    (pea_regf_wr_req_rdy),
    .pea_regf_wr_req        (pea_regf_wr_req),

    .pea_regf_wr_data_vld   (pea_regf_wr_data_vld),
    .pea_regf_wr_data_rdy   (pea_regf_wr_data_rdy),
    .pea_regf_wr_data       (pea_regf_wr_data),

    .regf_pea_wr_ack        (regf_pea_wr_ack),

    .pea_regf_rd_req_vld    (pea_regf_rd_req_vld),
    .pea_regf_rd_req_rdy    (pea_regf_rd_req_rdy),
    .pea_regf_rd_req        (pea_regf_rd_req),

    .regf_pea_rd_data_avail (regf_pea_rd_data_avail),
    .regf_pea_rd_data       (regf_pea_rd_data),
    .regf_pea_rd_last_word  (regf_pea_rd_last_word),
    .regf_pea_rd_is_body    (regf_pea_rd_is_body),
    .regf_pea_rd_last_mask  (regf_pea_rd_last_mask)
  );

// ============================================================================================== --
// Regfile
// ============================================================================================== --
  // write
  logic                                 regf_wr_req_vld;
  logic                                 regf_wr_req_rdy;
  regf_wr_req_t                         regf_wr_req;

  logic [REGF_COEF_NB-1:0]              regf_wr_data_vld;
  logic [REGF_COEF_NB-1:0]              regf_wr_data_rdy;
  logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0] regf_wr_data;

  logic                                 regf_wr_ack;

  // read
  logic                                 regf_rd_req_vld = 1'b0;
  logic                                 regf_rd_req_rdy;
  regf_rd_req_t                         regf_rd_req;

  logic [REGF_COEF_NB-1:0]              regf_rd_data_avail;
  logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0] regf_rd_data;
  logic                                 regf_rd_last_word;
  logic                                 regf_rd_is_body;
  logic                                 regf_rd_last_mask;

  regfile
  #(
    .PEA_PERIOD (PEA_PERIOD),
    .PEM_PERIOD (PEM_PERIOD),
    .PEP_PERIOD (PEP_PERIOD),
    .URAM_LATENCY (URAM_LATENCY)
  ) regfile (
    .clk                    (clk),        // clock
    .s_rst_n                (s_rst_n),    // synchronous reset

    .pem_regf_wr_req_vld    ('0), /*UNUSED*/
    .pem_regf_wr_req_rdy    (/*UNUSED*/),
    .pem_regf_wr_req        (/*UNUSED*/),

    .pem_regf_wr_data_vld   ('0), /*UNUSED*/
    .pem_regf_wr_data_rdy   (/*UNUSED*/),
    .pem_regf_wr_data       (/*UNUSED*/),

    .pem_regf_rd_req_vld    ('0),/*UNUSED*/
    .pem_regf_rd_req_rdy    (/*UNUSED*/),
    .pem_regf_rd_req        (/*UNUSED*/),

    .regf_pem_rd_data_avail (/*UNUSED*/),
    .regf_pem_rd_data       (/*UNUSED*/),
    .regf_pem_rd_last_word  (/*UNUSED*/),
    .regf_pem_rd_last_mask  (/*UNUSED*/),
    .regf_pem_rd_is_body    (/*UNUSED*/),

    .pea_regf_wr_req_vld    (pea_regf_wr_req_vld ),
    .pea_regf_wr_req_rdy    (pea_regf_wr_req_rdy ),
    .pea_regf_wr_req        (pea_regf_wr_req     ),

    .pea_regf_wr_data_vld   (pea_regf_wr_data_vld),
    .pea_regf_wr_data_rdy   (pea_regf_wr_data_rdy),
    .pea_regf_wr_data       (pea_regf_wr_data    ),


    .pea_regf_rd_req_vld    (pea_regf_rd_req_vld   ),
    .pea_regf_rd_req_rdy    (pea_regf_rd_req_rdy   ),
    .pea_regf_rd_req        (pea_regf_rd_req       ),

    .regf_pea_rd_data_avail (regf_pea_rd_data_avail),
    .regf_pea_rd_data       (regf_pea_rd_data      ),
    .regf_pea_rd_last_word  (regf_pea_rd_last_word ),
    .regf_pea_rd_last_mask  (regf_pea_rd_last_mask ),
    .regf_pea_rd_is_body    (regf_pea_rd_is_body   ),

    .pep_regf_wr_req_vld    (regf_wr_req_vld   ),
    .pep_regf_wr_req_rdy    (regf_wr_req_rdy   ),
    .pep_regf_wr_req        (regf_wr_req       ),

    .pep_regf_wr_data_vld   (regf_wr_data_vld),
    .pep_regf_wr_data_rdy   (regf_wr_data_rdy),
    .pep_regf_wr_data       (regf_wr_data    ),

    .pep_regf_rd_req_vld    (regf_rd_req_vld ),
    .pep_regf_rd_req_rdy    (regf_rd_req_rdy ),
    .pep_regf_rd_req        (regf_rd_req     ),

    .regf_pep_rd_data_avail (regf_rd_data_avail),
    .regf_pep_rd_data       (regf_rd_data      ),
    .regf_pep_rd_last_word  (regf_rd_last_word ),
    .regf_pep_rd_last_mask  (regf_rd_last_mask ),
    .regf_pep_rd_is_body    (regf_rd_is_body   ),


    .pem_wr_ack             (/*UNUSED*/),
    .pea_wr_ack             (regf_pea_wr_ack),
    .pep_wr_ack             (regf_wr_ack)
  );


// ============================================================================================== --
// Scenario
// ============================================================================================== --
// ---------------------------------------------------------------------------------------------- --
// FSM
// ---------------------------------------------------------------------------------------------- --
// First phase :
//  * Fill the registers of the regfile.
//  * Process ALU operation on these registers.
//
  typedef enum {ST_IDLE,
                ST_WRITE,
                ST_PROC,
                ST_DONE,
                ST_XXX} state_e;
  state_e state;
  state_e next_state;

  logic start;
  logic wr_done;
  logic proc_done;

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
        next_state = wr_done ? ST_PROC : state;
      ST_PROC:
        next_state = proc_done ? ST_DONE : state;
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
        if (wr_done)
          $display("%t > INFO : ST_PROC", $time);
      ST_PROC:
        if (proc_done)
          $display("%t > INFO : ST_DONE", $time);
      default: begin
          // do nothing
        end
    endcase
  end

  logic st_idle;
  logic st_write;
  logic st_proc;
  logic st_done;

  assign st_idle  = (state == ST_IDLE);
  assign st_write = (state == ST_WRITE);
  assign st_proc  = (state == ST_PROC);
  assign st_done  = (state == ST_DONE);

// ---------------------------------------------------------------------------------------------- --
// Fill the regfile
// ---------------------------------------------------------------------------------------------- --
  logic [REGF_REGID_W-1:0] regf_wr_req_rid;
  stream_source
  #(
    .FILENAME   ("counter"),
    .DATA_TYPE  ("ascii_hex"),
    .DATA_W     (REGF_REGID_W),
    .RAND_RANGE (RAND_RANGE),
    .KEEP_VLD   (1),
    .MASK_DATA  ("x")
  )
  source_wr_req
  (
    .clk        (clk),
    .s_rst_n    (s_rst_n),

    .data       (regf_wr_req_rid),
    .vld        (regf_wr_req_vld),
    .rdy        (regf_wr_req_rdy),

    .throughput (RAND_RANGE)
  );

  initial begin
    wr_done <= 1'b0;
    if (!source_wr_req.open()) begin
      $fatal(1, "%t > ERROR: Opening source_wr_req stream source", $time);
    end
    wait(st_write);
    @(posedge clk);
    source_wr_req.start(REGF_REG_NB);

    wait(source_wr_req.running);
    wait(!source_wr_req.running);

    @(posedge clk) wr_done <= 1'b1;
  end

  assign regf_wr_req.reg_id     = regf_wr_req_rid;
  assign regf_wr_req.start_word = '0;
  assign regf_wr_req.word_nb_m1 = REGF_BLWE_WORD_PER_RAM;

  generate
    for (genvar gen_c=0; gen_c<REGF_COEF_NB; gen_c=gen_c+1) begin : gen_source_data
      int dataw_word_cnt;
      int dataw_word_cntD;
      int dataw_word_cnt_inc;
      int dataw_word_cnt_dec;

      logic wr_data_vld_tmp;
      logic wr_data_rdy_tmp;

      always_ff @(posedge clk)
        if (!s_rst_n) dataw_word_cnt <= '0;
        else          dataw_word_cnt <= dataw_word_cntD;

      assign dataw_word_cnt_inc = regf_wr_req_vld && regf_wr_req_rdy ? REGF_BLWE_WORD_PER_RAM+1 : '0;
      assign dataw_word_cnt_dec = wr_data_vld_tmp && wr_data_rdy_tmp ? 1 : '0;
      assign dataw_word_cntD    = dataw_word_cnt - dataw_word_cnt_dec + dataw_word_cnt_inc;

      assign regf_wr_data_vld[gen_c] = wr_data_vld_tmp         & (dataw_word_cnt > 0);
      assign wr_data_rdy_tmp         = regf_wr_data_rdy[gen_c] & (dataw_word_cnt > 0);

      stream_source
      #(
        .FILENAME   ("random"),
        .DATA_TYPE  ("ascii_hex"),
        .DATA_W     (MOD_Q_W),
        .RAND_RANGE (RAND_RANGE),
        .KEEP_VLD   (1),
        .MASK_DATA  ("x")
      )
      source_wr_data
      (
        .clk        (clk),
        .s_rst_n    (s_rst_n),

        .data       (regf_wr_data[gen_c]),
        .vld        (wr_data_vld_tmp),
        .rdy        (wr_data_rdy_tmp),

        .throughput (RAND_RANGE)
      );

      initial begin
        if (!source_wr_data.open()) begin
          $fatal(1, "%t > ERROR: Opening source_wr_data[%0d] stream source", $time, gen_c);
        end
        source_wr_data.start(0);
      end
    end // for gen_c
  endgenerate

// ---------------------------------------------------------------------------------------------- --
// Process
// ---------------------------------------------------------------------------------------------- --
  pea_mac_inst_t inst_mac;
  pea_msg_inst_t inst_msg;

  logic [REGF_REGID_W-1:0] inst_src0_rid;
  integer                  inst_dop_rand;
  logic [DOP_W-1:0]        inst_dop;
  logic [MUL_FACTOR_W-1:0] inst_mul_factor;
  logic [MSG_CST_W-1:0]    inst_msg_cst;

  assign inst_dop = DOP_ALU_L[inst_dop_rand];

  // Random values
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      inst_mul_factor <= $urandom();
      inst_msg_cst    <= $urandom();
      inst_dop_rand   <= $urandom_range(0,DOP_ALU_NB-1);
    end
    else begin
      if (inst_vld && inst_rdy) begin
        inst_mul_factor <= $urandom();
        inst_msg_cst    <= $urandom();
        inst_dop_rand   <= $urandom_range(0,DOP_ALU_NB-1);
      end
    end

  assign inst_mac.dop        = inst_dop;
  assign inst_mac.mul_factor = inst_mul_factor;
  assign inst_mac.src1_rid   = (inst_src0_rid + 1) % REGF_REG_NB;
  assign inst_mac.src0_rid   = inst_src0_rid % REGF_REG_NB;
  assign inst_mac.dst_rid    = (inst_src0_rid - 1) % REGF_REG_NB;

  assign inst_msg.dop        = inst_dop;
  assign inst_msg.msg_cst    = inst_msg_cst;
  assign inst_msg.src0_rid   = inst_src0_rid % REGF_REG_NB;
  assign inst_msg.dst_rid    = (inst_src0_rid - 1) % REGF_REG_NB;

  assign inst = (inst_dop == DOP_ADDS) || (inst_dop == DOP_SUBS) || (inst_dop == DOP_SSUB) || (inst_dop == DOP_MULS) ? inst_msg : inst_mac;

  stream_source
  #(
    .FILENAME   ("counter"),
    .DATA_TYPE  ("ascii_hex"),
    .DATA_W     (REGF_REGID_W),
    .RAND_RANGE (RAND_RANGE),
    .KEEP_VLD   (1'b0),
    .MASK_DATA  ("x")
  ) inst_stream_source (
      .clk       (clk),
      .s_rst_n   (s_rst_n),

      .data      (inst_src0_rid),
      .vld       (inst_vld),
      .rdy       (inst_rdy),

      .throughput(1)
  );

  logic in_cmd_done;
  assign proc_done = in_cmd_done;
  initial begin
    integer dummy;
    in_cmd_done = 1'b0;
    dummy = inst_stream_source.open();
    wait(st_proc);
    @(posedge clk);
    inst_stream_source.start(SAMPLE_NB);
    wait (inst_stream_source.running);
    wait (!inst_stream_source.running);

    in_cmd_done = 1'b1;
  end


  pea_mac_inst_t proc_inst_q[REGF_COEF_NB-1:0][$];
  pea_mac_inst_t rd_inst_q[$];
  pea_mac_inst_t wr_inst_q[$];

  always_ff @(posedge clk)
    if (inst_vld && inst_rdy) begin
      for (int i=0; i<REGF_COEF_NB; i=i+1)
        proc_inst_q[i].push_back(inst);
      rd_inst_q.push_back(inst);
      wr_inst_q.push_back(inst);
    end

// ---------------------------------------------------------------------------------------------- --
// Build ref
// ---------------------------------------------------------------------------------------------- --
  logic [MOD_Q_W-1:0] ref_result_q[REGF_COEF_NB-1:0][$];

  generate
    for (genvar gen_c=0; gen_c<REGF_COEF_NB; gen_c=gen_c+1) begin: gen_data_ref_loop
      logic               word_cnt_inc;
      integer             regf_word_cnt;
      integer             regf_word_cntD;
      logic               regf_last_word_cnt;
      logic [MOD_Q_W-1:0] regf_pea_rd_data_dly;
      logic               regf_pea_rd_data_avail_dly;
      logic               regf_pea_rd_data_parity;
      logic               regf_pea_rd_data_parity_dly;
      logic               regf_pea_rd_data_parityD;

      // Update this info once the data have been processed.
      // To ease the implementation, update the cycle after the last data is seen.
      assign regf_last_word_cnt  = regf_word_cnt == REGF_BLWE_WORD_PER_RAM;

      assign regf_pea_rd_data_parityD = regf_pea_rd_data_avail[gen_c] ? ~regf_pea_rd_data_parity : 1'b0;
      always_ff @(posedge clk)
        if (!s_rst_n) begin
          regf_pea_rd_data_avail_dly  <= '0;
          regf_pea_rd_data_parity     <= '0;
          regf_pea_rd_data_parity_dly <= '0;
        end
        else begin
          regf_pea_rd_data_avail_dly  <= regf_pea_rd_data_avail[gen_c];
          regf_pea_rd_data_parity     <= regf_pea_rd_data_parityD    ;
          regf_pea_rd_data_parity_dly <= regf_pea_rd_data_parity;
        end

      always_ff @(posedge clk)
        regf_pea_rd_data_dly <= regf_pea_rd_data[gen_c];

      always_ff @(posedge clk) begin
        if (!s_rst_n) begin
          regf_word_cnt <= '0;
        end
        else begin
          logic inc;
          logic [MOD_Q_W-1:0] res;
          pea_mac_inst_t i_mac;
          pea_msg_inst_t i_msg;

          if (proc_inst_q[gen_c].size() > 0) begin

            i_mac = proc_inst_q[gen_c][0];
            i_msg = proc_inst_q[gen_c][0];

            inc = 1'b0;
            if (regf_pea_rd_data_avail_dly && regf_pea_rd_data_parity_dly == 1'b0) begin
              if (i_mac.dop == DOP_MAC || i_mac.dop == DOP_ADD || i_mac.dop == DOP_SUB) begin // need 2 sources
                if (regf_pea_rd_data_avail[gen_c]) begin
                  case (i_mac.dop)
                    DOP_MAC :
                      res = (i_mac.mul_factor * regf_pea_rd_data_dly + regf_pea_rd_data[gen_c]);
                    DOP_ADD :
                      res = (regf_pea_rd_data_dly + regf_pea_rd_data[gen_c]);
                    DOP_SUB :
                      res = (regf_pea_rd_data_dly - regf_pea_rd_data[gen_c]);
                    default :
                      $fatal(1,"%t > ERROR: Unknown DOP %0d",$time,i_mac.dop);
                  endcase
                  ref_result_q[gen_c].push_back(res);
                  inc = 1'b1;

                  if (regf_last_word_cnt)
                    proc_inst_q[gen_c].pop_front();

                  //$display("%t > INFO: DOP=%0d > Push2 [%0d] 0x%0x (a0=0x%0x a1=0x%0x).",$time, i_mac.dop, gen_c, res,regf_pea_rd_data_dly, regf_pea_rd_data[gen_c]);
                end
              end
              else begin // single source
                case (i_mac.dop)
                  DOP_MULS :
                    res = (i_msg.msg_cst[MUL_FACTOR_W-1:0] * regf_pea_rd_data_dly);
                  DOP_SSUB :
                    // Apply on the body only
                    res = (gen_c == 0 && regf_last_word_cnt) ? ((i_msg.msg_cst[USEFUL_BIT-1:0] << (MOD_Q_W-USEFUL_BIT)) - regf_pea_rd_data_dly):
                                                                ({MOD_Q_W{1'b0}} - regf_pea_rd_data_dly);
                  DOP_SUBS :
                    // Apply on the body only
                    res = (gen_c == 0 && regf_last_word_cnt) ? (regf_pea_rd_data_dly - (i_msg.msg_cst[USEFUL_BIT-1:0] << (MOD_Q_W-USEFUL_BIT))):
                                                               regf_pea_rd_data_dly;
                  DOP_ADDS :
                    // Apply on the body only
                    res = (gen_c == 0 && regf_last_word_cnt) ? (regf_pea_rd_data_dly + (i_msg.msg_cst[USEFUL_BIT-1:0] << (MOD_Q_W-USEFUL_BIT))):
                                                                regf_pea_rd_data_dly;
                  default :
                    $fatal(1,"%t > ERROR: Unknown DOP S %0d",$time,i_mac.dop);
                endcase
                ref_result_q[gen_c].push_back(res);
                inc = 1'b1;

                if (regf_last_word_cnt)
                  proc_inst_q[gen_c].pop_front();

                //$display("%t > INFO: DOP=%0d > Push [%0d] 0x%0x (a0=0x%0x msg_cst=0x%0x mul_factor=%0d).",$time, i_mac.dop, gen_c, res, regf_pea_rd_data_dly,i_msg.msg_cst,i_mac.mul_factor);
              end
            end

            regf_word_cnt <= inc ? regf_last_word_cnt ? '0 : regf_word_cnt + 1 : regf_word_cnt;
          end // inst exists
        end // else
      end



    end // for gen_c
  endgenerate

// ---------------------------------------------------------------------------------------------- --
// Check
// ---------------------------------------------------------------------------------------------- --
  pea_mac_inst_t ref_wr_inst;
  pea_mac_inst_t ref_rd_inst;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      error_req  <= 1'b0;
      error_data <= 1'b0;
    end
    else begin
      // - check write request
      if (pea_regf_wr_req_vld && pea_regf_wr_req_rdy) begin
        ref_wr_inst = wr_inst_q.pop_front();
        assert(pea_regf_wr_req.reg_id == ref_wr_inst.dst_rid
              && pea_regf_wr_req.start_word == '0
              && pea_regf_wr_req.word_nb_m1 == REGF_BLWE_WORD_PER_RAM)
        else begin
          $display("%t > ERROR: Wr req mismatch. reg_id exp=%0d seen=%0d", $time, ref_wr_inst.dst_rid, pea_regf_wr_req.reg_id);
          error_req <= 1'b1;
        end
      end

      // - check read request
      if (pea_regf_rd_req_vld && pea_regf_rd_req_rdy) begin
        ref_rd_inst = rd_inst_q.pop_front();
        assert(pea_regf_rd_req.reg_id == ref_rd_inst.src0_rid
              && pea_regf_rd_req.start_word == '0
              && pea_regf_rd_req.word_nb_m1 == REGF_BLWE_WORD_PER_RAM)
        else begin
          $display("%t > ERROR: rd req mismatch. reg_id exp=%0d seen=%0d", $time, ref_rd_inst.src0_rid, pea_regf_rd_req.reg_id);
          error_req <= 1'b1;
        end
        if (ref_rd_inst.dop == DOP_ADD || ref_rd_inst.dop == DOP_SUB || ref_rd_inst.dop == DOP_MAC) begin
          assert(pea_regf_rd_req.reg_id_1 == ref_rd_inst.src1_rid)
          else begin
            $display("%t > ERROR: rd req mismatch. reg_id_1 exp=%0d seen=%0d", $time, ref_rd_inst.src1_rid, pea_regf_rd_req.reg_id_1);
            error_req <= 1'b1;
          end
        end
      end

      // - check wr data
      for (int i=0; i<REGF_COEF_NB; i=i+1) begin
        logic [MOD_Q_W-1:0] ref_d;
        if (pea_regf_wr_data_vld[i] && pea_regf_wr_data_rdy[i]) begin
          ref_d = ref_result_q[i].pop_front();
          //$display("%t > INFO: Pop [%0d] 0x%0x",$time,i,ref_d);
          assert(pea_regf_wr_data[i] == ref_d)
          else begin
            $display("%t > ERROR: Data Mismatch [%0d] exp=0x%0x seen=0x%0x",$time,i,ref_d,pea_regf_wr_data[i]);
            error_data <= 1'b1;
          end
        end
      end // for i
    end // else
  end // always

// ---------------------------------------------------------------------------------------------- --
// Ack
// ---------------------------------------------------------------------------------------------- --
  integer ack_cnt;
  integer ack_cntD;

  assign ack_cntD = regf_pea_wr_ack ? ack_cnt + 1 : ack_cnt;

  always_ff @(posedge clk)
    if (!s_rst_n) ack_cnt <= '0;
    else          ack_cnt <= ack_cntD;

// ---------------------------------------------------------------------------------------------- --
// Control
// ---------------------------------------------------------------------------------------------- --
  initial begin
    error_ack <= 1'b0;
    end_of_test = 1'b0;
    start = 1'b0;
    wait (s_rst_n);
    repeat(10) @(posedge clk);
    start = 1'b1;
    wait (st_done);
    $display("%t > INFO: All instructions sent.",$time);
    $display("%t > INFO: Wait flush.", $time);
    wait (rd_inst_q.size() == 0);
    @(posedge clk);
    wait (wr_inst_q.size() == 0);
    @(posedge clk);
    for (int i=0; i<REGF_COEF_NB; i=i+1)
      wait (ref_result_q[i].size() == 0);
    @(posedge clk);
    $display("%t > INFO: Done.", $time);
    repeat(200) @(posedge clk);
    assert(ack_cnt == SAMPLE_NB)
    else begin
      $display("%t > ERROR: Wrong number of ack at the end of the test. exp=%0d seen=%0d.",$time, SAMPLE_NB, ack_cnt);
      error_ack <= 1'b1;
    end

    end_of_test = 1'b1;
  end

endmodule
