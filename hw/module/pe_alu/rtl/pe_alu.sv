// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Arithmmmetic logic unit processing element (PE).
// This module deals with reading in the regfile, et doing the ALU operation on the BLWE, before
// writing it back into the regfile.
//
//
//
// ==============================================================================================

module pe_alu
  import param_tfhe_pkg::*;
  import regf_common_param_pkg::*;
  import hpu_common_instruction_pkg::*;
  import pea_common_param_pkg::*;
#(
  parameter int INST_FIFO_DEPTH = 8, // Should be >= 5
  parameter int ALU_NB          = 1, // Number of ALU that worked in parallel. Should devide REGF_SEQ_COEF_NB
  // /!\ Review the following parameters whenever regfile architecture is updated.
  //     OUT_FIFO_DEPTH : The depth depends on the regfile maximum latency, between the sampling of the write command
  //                    and the actual writing of the first data.
  parameter int OUT_FIFO_DEPTH  = 2 // /!\
)
(
  input  logic                                   clk,        // clock
  input  logic                                   s_rst_n,    // synchronous reset

  input  logic [PE_INST_W-1:0]                   inst,
  input  logic                                   inst_vld,
  output logic                                   inst_rdy,

  output logic                                   inst_ack,

  // pea <-> regfile
  // write
  output logic                                   pea_regf_wr_req_vld,
  input  logic                                   pea_regf_wr_req_rdy,
  output logic [REGF_WR_REQ_W-1:0]               pea_regf_wr_req,

  output logic [REGF_COEF_NB-1:0]                pea_regf_wr_data_vld,
  input  logic [REGF_COEF_NB-1:0]                pea_regf_wr_data_rdy,
  output logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0]   pea_regf_wr_data,

  input  logic                                   regf_pea_wr_ack,

  // read
  output logic                                   pea_regf_rd_req_vld,
  input  logic                                   pea_regf_rd_req_rdy,
  output logic [REGF_RD_REQ_W-1:0]               pea_regf_rd_req,

  input  logic [REGF_COEF_NB-1:0]                regf_pea_rd_data_avail,
  input  logic [REGF_COEF_NB-1:0][MOD_Q_W-1:0]   regf_pea_rd_data,
  input  logic                                   regf_pea_rd_last_word, // valid with avail[0]
  input  logic                                   regf_pea_rd_is_body,
  input  logic                                   regf_pea_rd_last_mask,

  output logic [PEA_COUNTER_INC_W-1:0]           pea_rif_counter_inc
);

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int ACC_DEPTH = REGF_SEQ;
  localparam int ACC_PTR_W = $clog2(ACC_DEPTH+1) == 0 ? 1 : $clog2(ACC_DEPTH+1); // counts to ACC_DEPTH included

  localparam int SR_DEPTH   = REGF_SEQ_COEF_NB/ALU_NB;
  localparam int SR_DEPTH_W = $clog2(SR_DEPTH) == 0 ? 1 : $clog2(SR_DEPTH);

  localparam int SEC_NB   = REGF_SEQ_COEF_NB/ALU_NB;
  localparam int SEC_NB_W = $clog2(SEC_NB) == 0 ? 1 : $clog2(SEC_NB);

  localparam int OUT_FIFO_DEPTH_PART1_TMP = (OUT_FIFO_DEPTH-1) * REGF_SEQ;
  localparam int OUT_FIFO_DEPTH_PART1 = OUT_FIFO_DEPTH_PART1_TMP < 2 ? 2 : OUT_FIFO_DEPTH_PART1_TMP;
  localparam int OUT_FIFO_DEPTH_PART2 = 1;

  generate
    if (REGF_SEQ_COEF_NB%ALU_NB != 0) begin : __UNSUPPORTED_ALU_NB_
      $fatal(1,"> ERROR: Unsupported ALU_NB and REGF_SEQ_COEF_NB. ALU_NB (%0d) should divide REGF_SEQ_COEF_NB (%0d).",ALU_NB, REGF_SEQ_COEF_NB);
    end
  endgenerate

// ============================================================================================== --
// typedef
// ============================================================================================== --
  typedef struct packed {
    logic                    do_2_read;
    logic                    is_body;
    logic [DOP_W-1:0]        dop;
    logic [MUL_FACTOR_W-1:0] mul_factor;
    logic [MSG_CST_W-1:0]    msg_cst;
    logic                    last;
  } acc_info_t;

  localparam int ACC_INFO_W = $bits(acc_info_t);

  typedef struct packed {
    logic last;
  } side_t;

  localparam int SIDE_W = $bits(side_t);

// ============================================================================================== --
// Instruction FIFO
// ============================================================================================== --
  pea_mac_inst_t s0_inst;
  logic          s0_inst_vld;
  logic          s0_inst_rdy;

  fifo_reg #(
    .WIDTH       (PE_INST_W),
    .DEPTH       (INST_FIFO_DEPTH),
    .LAT_PIPE_MH ({1'b1, 1'b1})
  ) inst_fifo_reg (
    .clk      (clk),
    .s_rst_n  (s_rst_n),

    .in_data  (inst),
    .in_vld   (inst_vld),
    .in_rdy   (inst_rdy),

    .out_data (s0_inst),
    .out_vld  (s0_inst_vld),
    .out_rdy  (s0_inst_rdy)
  );

// ============================================================================================== --
// Regfile read request
// ============================================================================================== --
  // Fork command with processing part
  pea_mac_inst_t proc_fifo_in_inst;
  logic          proc_fifo_in_vld;
  logic          proc_fifo_in_rdy;

  regf_rd_req_t  s0_regf_req;
  logic          s0_regf_req_vld;
  logic          s0_regf_req_rdy;

  assign s0_regf_req.do_2_read  = (s0_inst.dop == DOP_ADD) |
                                  (s0_inst.dop == DOP_SUB) |
                                  (s0_inst.dop == DOP_MAC);
  assign s0_regf_req.reg_id_1   = s0_inst.src1_rid[REGF_REGID_W-1:0];
  assign s0_regf_req.reg_id     = s0_inst.src0_rid[REGF_REGID_W-1:0];
  assign s0_regf_req.start_word = '0;
  assign s0_regf_req.word_nb_m1 = REGF_BLWE_WORD_PER_RAM;

  assign proc_fifo_in_inst = s0_inst;

  assign s0_regf_req_vld  = s0_inst_vld & proc_fifo_in_rdy;
  assign proc_fifo_in_vld = s0_inst_vld & s0_regf_req_rdy;
  assign s0_inst_rdy      = proc_fifo_in_rdy & s0_regf_req_rdy;

  //----------------------------------
  // Regfile request FIFO
  //----------------------------------
  fifo_element #(
    .WIDTH          (REGF_RD_REQ_W),
    .DEPTH          (1),
    .TYPE_ARRAY     (4'h3),
    .DO_RESET_DATA  (1'b0),
    .RESET_DATA_VAL (0)
  ) regf_rd_req_fifo_element (
    .clk     (clk),
    .s_rst_n (s_rst_n),

    .in_data (s0_regf_req),
    .in_vld  (s0_regf_req_vld),
    .in_rdy  (s0_regf_req_rdy),

    .out_data(pea_regf_rd_req),
    .out_vld (pea_regf_rd_req_vld),
    .out_rdy (pea_regf_rd_req_rdy)
  );

// ============================================================================================== --
// Regfile data format
// ============================================================================================== --
  //----------------------------------
  // Process command FIFO
  //----------------------------------
  pea_mac_inst_t proc_fifo_out_inst;
  logic          proc_fifo_out_vld;
  logic          proc_fifo_out_rdy;

  fifo_element #(
    .WIDTH          (PE_INST_W),
    .DEPTH          (2),
    .TYPE_ARRAY     ({4'h1,4'h2}),
    .DO_RESET_DATA  (1'b0),
    .RESET_DATA_VAL (0)
  ) proc_cmd_fifo_element (
    .clk     (clk),
    .s_rst_n (s_rst_n),

    .in_data (proc_fifo_in_inst),
    .in_vld  (proc_fifo_in_vld),
    .in_rdy  (proc_fifo_in_rdy),
    .out_data(proc_fifo_out_inst),
    .out_vld (proc_fifo_out_vld),
    .out_rdy (proc_fifo_out_rdy)
  );

  // Send command to the write back part.
  logic          proc_send_to_wback;
  logic          proc_send_to_wbackD;

  pea_mac_inst_t wback_fifo_in_inst;
  logic          wback_fifo_in_vld;
  logic          wback_fifo_in_rdy;

  assign proc_send_to_wbackD = proc_fifo_out_vld && proc_fifo_out_rdy ? 1'b1 :
                               wback_fifo_in_vld && wback_fifo_in_rdy ? 1'b0 : proc_send_to_wback;

  assign wback_fifo_in_vld  = proc_fifo_out_vld & proc_send_to_wback;
  assign wback_fifo_in_inst = proc_fifo_out_inst;

  always_ff @(posedge clk)
    if (!s_rst_n) proc_send_to_wback <= 1'b1;
    else          proc_send_to_wback <= proc_send_to_wbackD;

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      if (proc_fifo_out_vld && proc_fifo_out_rdy) begin
        assert(!proc_send_to_wback)
        else begin
          $fatal(1,"%t > ERROR: Command not sent to wback part, at the end of the process in read part.", $time);
        end
      end
    end
// pragma translate_on

  // Format data from the regfile, to fit the accumulator.
  // Data are received partially sequentially.
  logic [1:0][REGF_SEQ_W-1:0]                             proc_regf_seq_id;
  logic [1:0][REGF_SEQ_W-1:0]                             proc_regf_seq_idD;
  logic [1:0]                                             proc_regf_last_seq_id;
  logic [REGF_SEQ-1:0][0:0]                               proc_src_id_s;
  logic [REGF_SEQ-1:0][0:0]                               proc_src_id_sD;

  logic [1:0][REGF_SEQ_COEF_NB-1:0][MOD_Q_W-1:0]          acc_in;
  logic [1:0][REGF_SEQ_COEF_NB-1:0][MOD_Q_W-1:0]          acc_inD;
  logic [1:0]                                             acc_in_avail;
  logic [1:0]                                             acc_in_availD;
  acc_info_t                                              acc_in_info;
  acc_info_t                                              acc_in_infoD;

  logic [REGF_SEQ-1:0][REGF_SEQ_COEF_NB-1:0][MOD_Q_W-1:0] regf_pea_rd_data_s;
  logic [REGF_SEQ-1:0][REGF_SEQ_COEF_NB-1:0]              regf_pea_rd_avail_s;

  logic [REGF_SEQ-1:0]                                    regf_pea_rd_is_body_word_s;
  logic [REGF_SEQ-1:0]                                    regf_pea_rd_is_body_word_s_tmp;
  logic [REGF_SEQ-1:0]                                    regf_pea_rd_is_body_word_s_tmpD;

  pea_mac_inst_t [REGF_SEQ-1:0]                           proc_fifo_out_inst_s;
  pea_mac_inst_t [REGF_SEQ-1:0]                           proc_fifo_out_inst_s_tmp;
  pea_mac_inst_t [REGF_SEQ-1:0]                           proc_fifo_out_inst_s_tmpD;
  logic [REGF_SEQ-1:0]                                    proc_do_2_read_s;
  logic [REGF_SEQ-1:0]                                    proc_do_2_read_s_tmp;
  logic [REGF_SEQ-1:0]                                    proc_do_2_read_s_tmpD;
  pea_msg_inst_t [REGF_SEQ-1:0]                           proc_fifo_out_inst_s_c;

  assign regf_pea_rd_data_s  = regf_pea_rd_data; // Cast
  assign regf_pea_rd_avail_s = regf_pea_rd_data_avail;

  assign proc_fifo_out_inst_s_c = proc_fifo_out_inst_s; // cast

  assign proc_fifo_out_inst_s = proc_fifo_out_inst_s_tmpD;
  assign proc_do_2_read_s     = proc_do_2_read_s_tmpD;
  always_comb begin
    proc_fifo_out_inst_s_tmpD[0] = proc_fifo_out_inst;
    proc_do_2_read_s_tmpD[0] = (proc_fifo_out_inst.dop == DOP_ADD) |
                               (proc_fifo_out_inst.dop == DOP_SUB) |
                               (proc_fifo_out_inst.dop == DOP_MAC);
    for (int i=1; i<REGF_SEQ; i=i+1) begin
      proc_fifo_out_inst_s_tmpD[i] = proc_fifo_out_inst_s_tmp[i-1];
      proc_do_2_read_s_tmpD[i] = proc_do_2_read_s_tmp[i-1];
    end
  end

  always_comb begin
    proc_src_id_sD[0] = regf_pea_rd_data_avail[0] && proc_do_2_read_s[0] ? ~proc_src_id_s[0] : proc_src_id_s[0];
    for (int i=1; i<REGF_SEQ; i=i+1)
      proc_src_id_sD[i] = proc_src_id_s[i-1];
  end

  always_comb
    for (int i=0; i<2; i=i+1)
      proc_regf_last_seq_id[i] = proc_regf_seq_id[i] == REGF_SEQ-1;

  assign proc_regf_seq_idD[0] = ((proc_regf_seq_id[0] != 0) || (regf_pea_rd_data_avail[0] && (proc_src_id_s[0] == '0))) ?
                                    proc_regf_last_seq_id[0] ? '0 : proc_regf_seq_id[0] + 1 : proc_regf_seq_id[0];
  assign proc_regf_seq_idD[1] = proc_regf_seq_id[0];

  assign regf_pea_rd_is_body_word_s_tmpD[0] = regf_pea_rd_is_body & regf_pea_rd_data_avail[0];
  assign regf_pea_rd_is_body_word_s         = regf_pea_rd_is_body_word_s_tmpD;
  generate
    if (REGF_SEQ > 1) begin : gen_regf_seq_gt_1
      assign regf_pea_rd_is_body_word_s_tmpD[REGF_SEQ-1:1] = regf_pea_rd_is_body_word_s_tmp[REGF_SEQ-2:0];
    end
  endgenerate

  // Select the sequence
  always_comb
    for (int i=0; i<2; i=i+1) begin
      acc_inD[i]       = regf_pea_rd_data_s[proc_regf_seq_id[i]];
      acc_in_availD[i] = 1'b0;
      for (int j=0; j<REGF_SEQ; j=j+1)
        acc_in_availD[i] = acc_in_availD[i] | (regf_pea_rd_avail_s[j][0] & (proc_src_id_s[j] == i));
    end

  // acc_info is build for src0
  assign acc_in_infoD.do_2_read  = proc_do_2_read_s[proc_regf_seq_id[0]];
  assign acc_in_infoD.is_body    = regf_pea_rd_avail_s[0][0] & (proc_src_id_s[0] == 0) & regf_pea_rd_is_body; // tag the body coef of src0
  assign acc_in_infoD.dop        = proc_fifo_out_inst_s[proc_regf_seq_id[0]].dop;
  assign acc_in_infoD.mul_factor = (proc_fifo_out_inst_s[proc_regf_seq_id[0]].dop == DOP_MAC) ?
                                      proc_fifo_out_inst_s[proc_regf_seq_id[0]].mul_factor :
                                      proc_fifo_out_inst_s_c[proc_regf_seq_id[0]].msg_cst; // truncated
  assign acc_in_infoD.msg_cst    = proc_fifo_out_inst_s_c[proc_regf_seq_id[0]].msg_cst;
  assign acc_in_infoD.last       = regf_pea_rd_is_body_word_s[REGF_SEQ-1];

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      proc_src_id_s    <= '0;
      proc_regf_seq_id <= '0;
      acc_in_avail     <= '0;
    end
    else begin
      proc_src_id_s    <= proc_src_id_sD;
      proc_regf_seq_id <= proc_regf_seq_idD;
      acc_in_avail     <= acc_in_availD;
    end

  always_ff @(posedge clk) begin
    acc_in                         <= acc_inD;
    acc_in_info                    <= acc_in_infoD;
    regf_pea_rd_is_body_word_s_tmp <= regf_pea_rd_is_body_word_s_tmpD;
    proc_fifo_out_inst_s_tmp       <= proc_fifo_out_inst_s_tmpD;
    proc_do_2_read_s_tmp           <= proc_do_2_read_s_tmpD;
  end

  // Keep the instruction until the last sequence is received, to build the acc_in_info
  assign proc_fifo_out_rdy = regf_pea_rd_data_avail[0] & regf_pea_rd_is_body_word_s[0] & (~proc_do_2_read_s[0] | proc_src_id_s[0] == 1);

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      if (regf_pea_rd_data_avail[0]) begin
        assert(proc_fifo_out_vld)
        else begin
          $fatal(1,"%t > ERROR: proc_fifo_out cmd is not available while datar is.", $time);
        end
      end
    end
// pragma translate_on

  //----------------------------------
  // Accumulate data
  //----------------------------------
  // Accumulate input, and unpile at the same time
  // Data from the regfile are received sequence per sequence.
  logic [1:0][ACC_DEPTH-1:0][REGF_SEQ_COEF_NB-1:0][MOD_Q_W-1:0] acc;
  logic [1:0][ACC_DEPTH:0][REGF_SEQ_COEF_NB-1:0][MOD_Q_W-1:0]   acc_ext;
  logic [1:0][ACC_PTR_W-1:0]                                    acc_wp;
  logic [1:0]                                                   acc_empty;
  acc_info_t [ACC_DEPTH-1:0]                                    acc_info;
  acc_info_t [ACC_DEPTH:0]                                      acc_info_ext;
  logic [1:0][ACC_DEPTH:0][REGF_SEQ_COEF_NB-1:0][MOD_Q_W-1:0]   accD_tmp;
  logic [1:0][ACC_DEPTH-1:0][REGF_SEQ_COEF_NB-1:0][MOD_Q_W-1:0] accD;
  logic [1:0][ACC_PTR_W-1:0]                                    acc_wpD;
  acc_info_t [ACC_DEPTH-1:0]                                    acc_infoD;
  acc_info_t [ACC_DEPTH:0]                                      acc_infoD_tmp;

  logic                                                         acc_rd_en;
  logic [1:0]                                                   acc_shift;
  logic                                                         acc_avail;

  assign acc_avail    = ~acc_empty[0] & (~acc_info[0].do_2_read | ~acc_empty[1]);
  assign acc_shift[0] = acc_rd_en & acc_avail;
  assign acc_shift[1] = acc_shift[0] & acc_info[0].do_2_read;
  // To avoid warning
  assign acc_ext[0]   = acc[0]; // extend with '0
  assign acc_ext[1]   = acc[1]; // extend with '0
  assign acc_info_ext = acc_info;

  always_comb
    for (int i=0; i<2; i=i+1) begin
      acc_empty[i] = acc_wp[i] == '0;
      acc_wpD[i]   = acc_shift[i] && !acc_in_avail[i] ? acc_wp[i] - 1 :
                     !acc_shift[i] && acc_in_avail[i] ? acc_wp[i] + 1 : acc_wp[i];

      for (int j=0; j<ACC_DEPTH+1; j=j+1)
        accD_tmp[i][j] = acc_in_avail[i] && (acc_wp[i] == j) ? acc_in[i] : acc_ext[i][j];
    end

  always_comb
    for (int i=0; i<ACC_DEPTH+1; i=i+1)
      acc_infoD_tmp[i] = acc_in_avail[0] && (acc_wp[0] == i) ? acc_in_info : acc_info_ext[i];

  assign acc_infoD = acc_shift[0] ? acc_infoD_tmp[ACC_DEPTH:1] : acc_infoD_tmp[ACC_DEPTH-1:0];
  
  always_comb
    for (int i=0; i<2; i=i+1)
      accD[i] = acc_shift[i] ? accD_tmp[i][ACC_DEPTH:1] : accD_tmp[i][ACC_DEPTH-1:0];

  always_ff @(posedge clk)
    if (!s_rst_n) acc_wp <= '0;
    else          acc_wp <= acc_wpD;

  always_ff @(posedge clk) begin
    acc      <= accD;
    acc_info <= acc_infoD;
  end

  //----------------------------------
  // ALU input
  //----------------------------------
  logic [ALU_NB-1:0][MOD_Q_W-1:0]                    p0_a0;
  logic [ALU_NB-1:0][MOD_Q_W-1:0]                    p0_a1;
  logic [ALU_NB-1:0][MSG_CST_W-1:0]                  p0_msg_cst;
  logic [MUL_FACTOR_W-1:0]                           p0_mul_factor;
  side_t                                             p0_side;
  logic                                              p0_avail;
  acc_info_t                                         p0_info;
  acc_info_t                                         p0_infoD;

  logic [1:0][SR_DEPTH-1:0][ALU_NB-1:0][MOD_Q_W-1:0] p0_sr;
  logic [1:0][SR_DEPTH-1:0][ALU_NB-1:0][MOD_Q_W-1:0] p0_srD;
  logic [SR_DEPTH_W-1:0]                             p0_sr_cnt;
  logic [SR_DEPTH_W-1:0]                             p0_sr_cntD;
  logic                                              p0_sr_avail;
  logic                                              p0_sr_availD;
  logic                                              p0_last_sr_cnt;

  assign p0_last_sr_cnt = p0_sr_cnt == 0;
  assign p0_sr_availD   = acc_rd_en && acc_avail ? 1'b1 : p0_last_sr_cnt ? 1'b0 : p0_sr_avail;
  assign p0_sr_cntD     = acc_rd_en ? SR_DEPTH-1 : !p0_last_sr_cnt ? p0_sr_cnt - 1: p0_sr_cnt;

  assign acc_rd_en = p0_last_sr_cnt | ~p0_sr_avail;

  generate
    if (SR_DEPTH > 1) begin : gen_sr_depth_gt_1
      always_comb
        for (int i=0; i<2; i=i+1)
          p0_srD[i] = acc_rd_en ? acc[i][0] : {{ALU_NB*MOD_Q_W{1'bx}},p0_sr[i][SR_DEPTH-1:1]};
    end
    else begin
      assign p0_srD = acc_rd_en ? {acc[1][0],acc[0][0]} : p0_sr;
    end
  endgenerate

  assign p0_infoD = acc_rd_en ? acc_info[0] : p0_info;

  // ALU input
  assign p0_avail      = p0_sr_avail;
  assign p0_a0         = p0_sr[0][0];
  assign p0_a1         = p0_sr[1][0];
  assign p0_side.last  = p0_info.last;
  assign p0_mul_factor = p0_info.mul_factor;
  always_comb begin
    p0_msg_cst[0] = (p0_info.is_body && (p0_sr_cnt == SR_DEPTH-1)) ? p0_info.msg_cst : '0;
    for (int i=1; i<ALU_NB; i=i+1)
      p0_msg_cst[i] = '0;
  end

  always_ff @(posedge clk) begin
    p0_sr   <= p0_srD;
    p0_info <= p0_infoD;
  end

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      p0_sr_avail <= 1'b0;
      p0_sr_cnt   <= SR_DEPTH-1;
    end
    else begin
      p0_sr_avail <= p0_sr_availD;
      p0_sr_cnt   <= p0_sr_cntD;
    end

// ============================================================================================== --
// ALU core
// ============================================================================================== --
  //----------------------------------
  // ALU instance
  //----------------------------------
  logic  [ALU_NB-1:0][MOD_Q_W-1:0] p1_z;
  logic  [ALU_NB-1:0]              p1_avail;
  side_t [ALU_NB-1:0]              p1_side;

  generate
    for (genvar gen_i=0; gen_i<ALU_NB; gen_i=gen_i+1) begin : gen_core
      pea_alu_core #(
        .SIDE_W (SIDE_W)
      ) pea_alu_core (
        .clk       (clk),
        .s_rst_n   (s_rst_n),

        .in_a0        (p0_a0[gen_i]),
        .in_a1        (p0_a1[gen_i]),
        .in_dop       (p0_info.dop),
        .in_msg_cst   (p0_msg_cst[gen_i]),
        .in_mul_factor(p0_info.mul_factor),
        .in_side      (p0_side),
        .in_avail     (p0_avail),

        .out_z        (p1_z[gen_i]),
        .out_side     (p1_side[gen_i]),
        .out_avail    (p1_avail[gen_i])
      );
    end
  endgenerate

// ============================================================================================== --
// Regfile write request
// ============================================================================================== --
  //----------------------------------
  // Data out FIFO - part 1
  //----------------------------------
  // Output data are formatted in 2 steps. First data from the same sequence are gathered.
  // Then the sequences are dispatched
  //== Part 1
  logic [SEC_NB_W-1:0]                        p1_section_id;
  logic [SEC_NB_W-1:0]                        p1_section_idD;
  logic                                       p1_last_section_id;

  logic [SEC_NB-1:0][ALU_NB-1:0]              p1_vld;
  logic [SEC_NB-1:0][ALU_NB-1:0]              p1_rdy;

  logic [SEC_NB-1:0][ALU_NB-1:0][MOD_Q_W-1:0] p2_data;
  logic [SEC_NB-1:0][ALU_NB-1:0]              p2_vld;
  logic [SEC_NB-1:0][ALU_NB-1:0]              p2_rdy;

  assign p1_last_section_id = p1_section_id == (SEC_NB-1);
  assign p1_section_idD     = p1_avail[0] ? p1_last_section_id ? '0 : p1_section_id + 1 : p1_section_id;

  always_comb
    for (int i=0; i<SEC_NB; i=i+1)
      p1_vld[i] = p1_avail & {ALU_NB{p1_section_id == i}};

  always_ff @(posedge clk)
    if (!s_rst_n) p1_section_id <= '0;
    else          p1_section_id <= p1_section_idD;

  generate
    for (genvar gen_i=0; gen_i<SEC_NB; gen_i=gen_i+1) begin : gen_section_loop_i
      for (genvar gen_j=0; gen_j<ALU_NB; gen_j=gen_j+1) begin : gen_section_loop_j
        fifo_reg #(
          .WIDTH       (MOD_Q_W),
          .DEPTH       (OUT_FIFO_DEPTH_PART1),
          .LAT_PIPE_MH ({1'b1, 1'b1})
        ) section_fifo_reg (
          .clk      (clk),
          .s_rst_n  (s_rst_n),

          .in_data  (p1_z[gen_j]),
          .in_vld   (p1_vld[gen_i][gen_j]),
          .in_rdy   (p1_rdy[gen_i][gen_j]),

          .out_data (p2_data[gen_i][gen_j]),
          .out_vld  (p2_vld[gen_i][gen_j]),
          .out_rdy  (p2_rdy[gen_i][gen_j])
        );

// pragma translate_off
        always_ff @(posedge clk)
          if (!s_rst_n) begin
            // do nothing
          end
          else begin
            if (p1_vld[gen_i][gen_j]) begin
              assert(p1_rdy[gen_i][gen_j])
              else begin
                $fatal(1,"%t > ERROR: Section FIFO [%0d][%0d] is full. Overflow", $time, gen_i, gen_j);
              end
            end
          end
// pragma translate_on
      end
    end
  endgenerate

  //----------------------------------
  // Data out FIFO - part 2
  //----------------------------------
  logic                                                   p2_vld_tmp;
  logic                                                   p2_rdy_tmp;
  logic [REGF_SEQ_COEF_NB-1:0][MOD_Q_W-1:0]               p2_data_a;
  logic [REGF_SEQ_COEF_NB-1:0]                            p2_vld_a;
  logic [REGF_SEQ_COEF_NB-1:0]                            p2_rdy_a;
  logic [REGF_SEQ-1:0][REGF_SEQ_COEF_NB-1:0]              p2_out_vld;
  logic [REGF_SEQ-1:0][REGF_SEQ_COEF_NB-1:0]              p2_out_rdy;

  logic [REGF_SEQ-1:0][REGF_SEQ_COEF_NB-1:0][MOD_Q_W-1:0] p3_out_data;
  logic [REGF_SEQ-1:0][REGF_SEQ_COEF_NB-1:0]              p3_out_vld;
  logic [REGF_SEQ-1:0][REGF_SEQ_COEF_NB-1:0]              p3_out_rdy;

  logic [REGF_SEQ_W-1:0]                                  p2_seq_id;
  logic [REGF_SEQ_W-1:0]                                  p2_seq_idD;
  logic                                                   p2_last_seq_id;
  logic [REGF_SEQ-1:0]                                    p2_mask;
  logic [REGF_SEQ-1:0][REGF_SEQ_COEF_NB-1:0]              p2_out_rdy_masked_tmp;
  logic [REGF_SEQ_COEF_NB-1:0]                            p2_out_rdy_masked;

  assign p2_data_a = p2_data;  // Cast
  assign p2_vld_a  = p2_vld;   // "
  assign p2_rdy    = p2_rdy_a; // "

  // wait for all data of the section to be available before sending them in the final FIFO.
  assign p2_vld_tmp = &p2_vld;
  assign p2_rdy_tmp = &p2_rdy;

  assign p2_last_seq_id = p2_seq_id == REGF_SEQ -1;
  assign p2_seq_idD     = (p2_vld_tmp && p2_rdy_tmp) ? p2_last_seq_id ? '0 : p2_seq_id + 1 : p2_seq_id;

  always_ff @(posedge clk)
    if (!s_rst_n) p2_seq_id <= '0;
    else          p2_seq_id <= p2_seq_idD;

  always_comb
    for (int i=0; i<REGF_SEQ; i=i+1)
      p2_mask[i] = (p2_seq_id == i);

  always_comb begin
    p2_out_rdy_masked = '0;
    for (int i=0; i<REGF_SEQ; i=i+1) begin
      for (int j=0; j<REGF_SEQ_COEF_NB; j=j+1) begin
        p2_out_vld[i][j]        = p2_vld_tmp & p2_mask[i];
        p2_out_rdy_masked_tmp[i][j] = p2_out_rdy[i][j] & p2_mask[i];
      end
      p2_out_rdy_masked = p2_out_rdy_masked | p2_out_rdy_masked_tmp[i];
    end
  end

  always_comb begin
    for (int j=0; j<REGF_SEQ_COEF_NB; j=j+1) begin
      logic [REGF_SEQ_COEF_NB-1:0] mask;
      mask = 1 << j;
      p2_rdy_a[j] = p2_out_rdy_masked[j] & (&(p2_vld_a | mask));
    end
  end

  generate
    for (genvar gen_i=0; gen_i<REGF_SEQ; gen_i=gen_i+1) begin : gen_out_loop_i
      for (genvar gen_j=0; gen_j<REGF_SEQ_COEF_NB; gen_j=gen_j+1) begin : gen_out_loop_j
        fifo_element #(
          .WIDTH          (MOD_Q_W),
          .DEPTH          (1),
          .TYPE_ARRAY     (4'h1),
          .DO_RESET_DATA  (1'b0),
          .RESET_DATA_VAL (0)
        ) out_fifo_element (
          .clk     (clk),
          .s_rst_n (s_rst_n),

          .in_data (p2_data_a[gen_j]),
          .in_vld  (p2_out_vld[gen_i][gen_j]),
          .in_rdy  (p2_out_rdy[gen_i][gen_j]),

          .out_data(p3_out_data[gen_i][gen_j]),
          .out_vld (p3_out_vld[gen_i][gen_j]),
          .out_rdy (p3_out_rdy[gen_i][gen_j])
        );
      end
    end
  endgenerate

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      for (int i=0; i<REGF_SEQ; i=i+1)
        assert(p2_out_rdy[i] == '0 || p2_out_rdy[i] == '1)
        else begin
          $fatal(1,"%t > ERROR: Output data fifo_element ready are not coherent!",$time);
        end
    end
// pragma translate_on

  //----------------------------------
  // Data out
  //----------------------------------
  assign pea_regf_wr_data     = p3_out_data;
  assign pea_regf_wr_data_vld = p3_out_vld;
  assign p3_out_rdy           = pea_regf_wr_data_rdy;

  //----------------------------------
  // Write back command FIFO
  //----------------------------------
  pea_mac_inst_t wback_fifo_out_inst;
  logic          wback_fifo_out_vld;
  logic          wback_fifo_out_rdy;

  fifo_element #(
    .WIDTH          (PE_INST_W),
    .DEPTH          (2),
    .TYPE_ARRAY     ({4'h1,4'h2}),
    .DO_RESET_DATA  (1'b0),
    .RESET_DATA_VAL (0)
  ) wback_cmd_fifo_element (
    .clk     (clk),
    .s_rst_n (s_rst_n),

    .in_data (wback_fifo_in_inst),
    .in_vld  (wback_fifo_in_vld),
    .in_rdy  (wback_fifo_in_rdy),

    .out_data(wback_fifo_out_inst),
    .out_vld (wback_fifo_out_vld),
    .out_rdy (wback_fifo_out_rdy)
  );

  //----------------------------------
  // Regfile write request
  //----------------------------------
  regf_wr_req_t                    wback_regf_req;
  logic                            wback_regf_vld;
  logic                            wback_regf_rdy;

  logic [REGF_BLWE_WORD_CNT_W-1:0] p2_data_cnt;
  logic [REGF_BLWE_WORD_CNT_W-1:0] p2_data_cntD;
  logic                            p2_last_data_cnt;
  logic                            p2_first_data_cnt;

  logic                            wback_send_regf_req;
  logic                            wback_send_regf_reqD;

  assign p2_last_data_cnt  = p2_data_cnt == REGF_BLWE_WORD_PER_RAM; // takes the body into account
  assign p2_first_data_cnt = p2_data_cnt == '0;
  assign p2_data_cntD      = p2_out_vld[REGF_SEQ-1][0] && p2_out_rdy[REGF_SEQ-1][0] ? p2_last_data_cnt ? '0 : p2_data_cnt + 1 : p2_data_cnt;

  assign wback_send_regf_reqD = wback_regf_vld && wback_regf_rdy                                                         ? 1'b0 :
                                p2_out_vld[REGF_SEQ-1][0] && p2_out_rdy[REGF_SEQ-1][0] && p2_first_data_cnt ? 1'b1 : // First regf word is entirely available
                                wback_send_regf_req;

  assign wback_regf_vld            = wback_send_regf_req & wback_fifo_out_vld;
  assign wback_fifo_out_rdy        = wback_send_regf_req & wback_regf_rdy;
  assign wback_regf_req.reg_id     = wback_fifo_out_inst.dst_rid;
  assign wback_regf_req.start_word = '0;
  assign wback_regf_req.word_nb_m1 = REGF_BLWE_WORD_PER_RAM;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      p2_data_cnt         <= '0;
      wback_send_regf_req <= 1'b0;
    end
    else begin
      p2_data_cnt         <= p2_data_cntD;
      wback_send_regf_req <= wback_send_regf_reqD;
    end

  //== Write request fifo
  fifo_element #(
    .WIDTH          (REGF_WR_REQ_W),
    .DEPTH          (1),
    .TYPE_ARRAY     (4'h3),
    .DO_RESET_DATA  (1'b0),
    .RESET_DATA_VAL (0)
  ) regf_wr_req_fifo_element (
    .clk     (clk),
    .s_rst_n (s_rst_n),

    .in_data (wback_regf_req),
    .in_vld  (wback_regf_vld),
    .in_rdy  (wback_regf_rdy),

    .out_data(pea_regf_wr_req),
    .out_vld (pea_regf_wr_req_vld),
    .out_rdy (pea_regf_wr_req_rdy)
  );

// ============================================================================================== --
// Write ack
// ============================================================================================== --
  always_ff @(posedge clk)
    if (!s_rst_n) inst_ack <= 1'b0;
    else          inst_ack <= regf_pea_wr_ack;


// ============================================================================================== --
// Counters
// ============================================================================================== --
  pea_counter_inc_t pea_rif_counter_inc_s;
  pea_counter_inc_t pea_rif_counter_inc_sD;

  assign pea_rif_counter_inc_sD.inst_inc  = inst_vld & inst_rdy;
  assign pea_rif_counter_inc_sD.ack_inc   = inst_ack;

  always_ff @(posedge clk)
    if (!s_rst_n) pea_rif_counter_inc_s <= '0;
    else          pea_rif_counter_inc_s <= pea_rif_counter_inc_sD;

  assign pea_rif_counter_inc = pea_rif_counter_inc_s;

endmodule
