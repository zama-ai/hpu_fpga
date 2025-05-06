// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the arbitration of the batch commands.
// This arbitration needs to be centralized, because, all the servers need to process the commands
// in exactly the same order.
// ==============================================================================================

module bsk_ntw_cmd_arbiter
  import top_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import bsk_ntw_common_param_pkg::*;

#(
  parameter int BATCH_NB           = 2, // Number of batches that are processed simultaneously.
  parameter int BSK_CLT_NB         = 3 // Number of clients in the network
)
(
  input                                     clk,        // clock
  input                                     s_rst_n,    // synchronous reset

  // Broadcast from acc
  input  [BSK_CLT_NB-1:0][BR_BATCH_CMD_W-1:0]  batch_cmd,
  input  [BSK_CLT_NB-1:0]                   batch_cmd_avail, // pulse

  // Broadcast to the servers
  output [BR_BATCH_CMD_W-1:0]               arb_srv_batch_cmd,
  output                                    arb_srv_batch_cmd_avail, // pulse

  input                                     srv_bdc_avail
);

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int PT_W           = $clog2(SRV_CMD_FIFO_DEPTH) == 0 ? 1 : $clog2(SRV_CMD_FIFO_DEPTH);
  localparam int BSK_CLT_NB_EXT = 2**$clog2(BSK_CLT_NB);
  localparam int ARB_STG_NB     = $clog2(BSK_CLT_NB_EXT);
  localparam int ARB_STG_ELT_NB = 2**(ARB_STG_NB-1);
  localparam int CMDP_DEPTH     = BATCH_NB*BSK_CLT_NB;

// ============================================================================================== --
// bsk_ntw_cmd_arbiter
// ============================================================================================== --
// ---------------------------------------------------------------------------------------------- --
// Arbiter
// ---------------------------------------------------------------------------------------------- --
  logic [BSK_CLT_NB_EXT-1:0][BR_BATCH_CMD_W-1:0] batch_cmd_ext;
  logic [BSK_CLT_NB_EXT-1:0]                  batch_ext_vld;
  logic [BSK_CLT_NB_EXT-1:0]                  batch_ext_rdy;

  logic [BSK_CLT_NB_EXT-1:0][BR_BATCH_CMD_W-1:0] s0_batch_cmd;
  logic [BSK_CLT_NB_EXT-1:0]                  s0_batch_vld;
  logic [BSK_CLT_NB_EXT-1:0]                  s0_batch_rdy;

  assign batch_cmd_ext[BSK_CLT_NB-1:0] = batch_cmd;
  assign batch_ext_vld[BSK_CLT_NB-1:0] = batch_cmd_avail;

  // Note : Code written this way for more readability.
  // The synthesizer will remove what is not used.
  generate
    if (BSK_CLT_NB_EXT > BSK_CLT_NB) begin
      assign batch_cmd_ext[BSK_CLT_NB_EXT-1:BSK_CLT_NB] = 'x;
      assign batch_ext_vld[BSK_CLT_NB_EXT-1:BSK_CLT_NB] = '0;
    end
  endgenerate

  genvar gen_i;
  genvar gen_j;
  generate
    for (gen_i=0; gen_i<BSK_CLT_NB_EXT; gen_i=gen_i+1) begin: batch_cmd_pipe_gen
      fifo_element #(
        .WIDTH          (BR_BATCH_CMD_W),
        .DEPTH          (BATCH_NB),
        .TYPE_ARRAY     ({{BATCH_NB-1{4'h1}},4'h2}),
        .DO_RESET_DATA  (0),
        .RESET_DATA_VAL (0)
      ) fifo_element_in (
        .clk     (clk),
        .s_rst_n (s_rst_n),

        .in_data (batch_cmd_ext[gen_i]),
        .in_vld  (batch_ext_vld[gen_i]),
        .in_rdy  (batch_ext_rdy[gen_i]),

        .out_data(s0_batch_cmd[gen_i]),
        .out_vld (s0_batch_vld[gen_i]),
        .out_rdy (s0_batch_rdy[gen_i])
      );

// pragma translate_off
      always_ff @(posedge clk)
        if (!s_rst_n) begin
          // Do nothing
        end
        else begin
          if (batch_ext_vld[gen_i]) begin
            assert(batch_ext_rdy[gen_i])
            else $fatal(1, "%t > ERROR: batch_cmd input fifo_element overflow!",$time);
          end
        end
// pragma translate_on
    end
  endgenerate

  br_batch_cmd_t [ARB_STG_NB:0][BSK_CLT_NB_EXT-1:0] s0_mux_batch_cmd;
  logic       [ARB_STG_NB:0][BSK_CLT_NB_EXT-1:0] s0_mux_batch_vld;
  logic       [ARB_STG_NB:0][BSK_CLT_NB_EXT-1:0] s0_mux_batch_rdy;

  br_batch_cmd_t s1_mux_batch_cmd;
  logic       s1_mux_batch_vld;
  logic       s1_mux_batch_rdy;

  assign s0_mux_batch_cmd[ARB_STG_NB] = s0_batch_cmd;
  assign s0_mux_batch_vld[ARB_STG_NB] = s0_batch_vld;
  assign s0_batch_rdy                 = s0_mux_batch_rdy[ARB_STG_NB];

  assign s1_mux_batch_cmd       = s0_mux_batch_cmd[0][0];
  assign s1_mux_batch_vld       = s0_mux_batch_vld[0][0];
  assign s0_mux_batch_rdy[0][0] = s1_mux_batch_rdy;

  // MUX tree
  // batch_cmd are muxed, 2 by 2. If at a stage 2 cmd have the same br_loop, one of them
  // is discarded.
  generate
    for (gen_i=ARB_STG_NB-1; gen_i >= 0; gen_i=gen_i-1) begin : arbiter_loop_0_gen
      for (gen_j=0; gen_j < 2**gen_i; gen_j=gen_j+1) begin : arbiter_loop_1_gen
        logic s0_same_br_loop;
        br_batch_cmd_t [1:0] s0_batch_cmd_in;
        logic [1:0] s0_batch_cmd_in_vld;
        logic [1:0] s0_batch_cmd_in_rdy;
        logic [1:0] s0_batch_cmd_in_arb_vld;
        logic [1:0] s0_batch_cmd_in_arb_rdy;

        assign s0_batch_cmd_in                       = s0_mux_batch_cmd[gen_i+1][gen_j*2+:2];
        assign s0_batch_cmd_in_vld                   = s0_mux_batch_vld[gen_i+1][gen_j*2+:2];
        assign s0_mux_batch_rdy[gen_i+1][gen_j*2+:2] = s0_batch_cmd_in_rdy;

        assign s0_same_br_loop = &s0_batch_cmd_in_vld
                                 & (s0_batch_cmd_in[0].br_loop == s0_batch_cmd_in[1].br_loop);
        assign s0_batch_cmd_in_arb_vld = s0_batch_cmd_in_vld & {~s0_same_br_loop,1'b1};
        assign s0_batch_cmd_in_rdy     = s0_batch_cmd_in_arb_rdy | {s0_same_br_loop,1'b0};

        // Arbiter
        logic       s0_priority;
        logic       s0_priorityD;
        br_batch_cmd_t s0_sel_batch_cmd;
        logic       s0_sel_batch_vld;
        logic       s0_sel_batch_rdy;

        assign s0_priorityD = s0_batch_cmd_in_arb_vld[0] && s0_batch_cmd_in_arb_rdy[0] ? 1'b1 :
                              s0_batch_cmd_in_arb_vld[1] && s0_batch_cmd_in_arb_rdy[1] ? 1'b0 :
                              s0_priority;

        assign s0_batch_cmd_in_arb_rdy = &s0_batch_cmd_in_arb_vld ? {s0_priority,~s0_priority} & {2{s0_sel_batch_rdy}}:
                                         {2{s0_sel_batch_rdy}};

        assign s0_sel_batch_cmd = (s0_batch_cmd_in_arb_vld[0] && (~s0_priority | ~s0_batch_cmd_in_arb_vld[1])) ?
                                      s0_batch_cmd_in[0] : s0_batch_cmd_in[1];
        assign s0_sel_batch_vld = |s0_batch_cmd_in_arb_vld;

        always_ff @(posedge clk)
          if (!s_rst_n) s0_priority <= 1'b0;
          else          s0_priority <= s0_priorityD;

        fifo_element #(
          .WIDTH          (BR_BATCH_CMD_W),
          .DEPTH          (1),
          .TYPE_ARRAY     (((gen_i%2)+1)),
          .DO_RESET_DATA  (0),
          .RESET_DATA_VAL (0)
        ) fifo_element_arb (
          .clk     (clk),
          .s_rst_n (s_rst_n),

          .in_data (s0_sel_batch_cmd),
          .in_vld  (s0_sel_batch_vld),
          .in_rdy  (s0_sel_batch_rdy),

          .out_data(s0_mux_batch_cmd[gen_i][gen_j]),
          .out_vld (s0_mux_batch_vld[gen_i][gen_j]),
          .out_rdy (s0_mux_batch_rdy[gen_i][gen_j])
        );
      end // gen_j
    end // gen_i
  endgenerate

// ---------------------------------------------------------------------------------------------- --
// batch_cmd command pool
// ---------------------------------------------------------------------------------------------- --
  br_batch_cmd_t [CMDP_DEPTH-1:0] s1_cmdp_batch_cmd;
  logic [CMDP_DEPTH-1:0]       s1_cmdp_avail;
  br_batch_cmd_t [CMDP_DEPTH-1:0] s1_cmdp_batch_cmdD;
  logic [CMDP_DEPTH-1:0]       s1_cmdp_availD;
  logic                        s1_cmdp_in_avail;
  br_batch_cmd_t [CMDP_DEPTH:0]   s1_cmdp_batch_cmd_ext;
  logic [CMDP_DEPTH:0]         s1_cmdp_avail_ext;
  logic [CMDP_DEPTH-1:0]       s1_cmdp_compare_in;
  logic                        s1_same_br_loop;
  logic [CMDP_DEPTH-1:0]       s1_cmdp_free_loc;
  logic [CMDP_DEPTH-1:0]       s1_cmdp_first_avail_1h;
  br_batch_cmd_t [CMDP_DEPTH-1:0] s1_cmdp_batch_cmd_masked;
  logic [CMDP_DEPTH-1:0]       s1_cmdp_avail_next;
  br_batch_cmd_t               s1_cmdp_batch_cmd_out;
  logic                        s1_cmdp_out_vld;
  logic                        s1_cmdp_out_rdy;

  assign s1_cmdp_batch_cmd_ext = {s1_cmdp_batch_cmd,s1_mux_batch_cmd};
  assign s1_cmdp_avail_ext     = {s1_cmdp_avail_next,s1_cmdp_in_avail};

  generate
    for(gen_i = 0; gen_i<CMDP_DEPTH; gen_i=gen_i+1) begin
      assign s1_cmdp_compare_in[gen_i] = (s1_mux_batch_cmd.br_loop == s1_cmdp_batch_cmd[gen_i].br_loop)
                                          & s1_cmdp_avail[gen_i];
      assign s1_cmdp_free_loc[gen_i]   = ~(&s1_cmdp_avail[CMDP_DEPTH-1:gen_i]);
      assign s1_cmdp_batch_cmdD[gen_i] = s1_cmdp_free_loc[gen_i] ? s1_cmdp_batch_cmd_ext[gen_i] : s1_cmdp_batch_cmd[gen_i];
      assign s1_cmdp_availD[gen_i]     = s1_cmdp_free_loc[gen_i] ? s1_cmdp_avail_ext[gen_i] : s1_cmdp_avail_next[gen_i];
    end
  endgenerate

  assign s1_same_br_loop      = |s1_cmdp_compare_in;
  assign s1_cmdp_in_avail     = s1_mux_batch_vld & ~s1_same_br_loop;
  assign s1_mux_batch_rdy = s1_cmdp_free_loc[0];

  always_ff @(posedge clk)
    if (!s_rst_n) s1_cmdp_avail <= '0;
    else          s1_cmdp_avail <= s1_cmdp_availD;

  always_ff @(posedge clk)
    s1_cmdp_batch_cmd <= s1_cmdp_batch_cmdD;

  assign s1_cmdp_out_vld = |s1_cmdp_avail;

  // Find the bit = 1 at the highest position (which means the oldest command).
  common_lib_find_last_bit_equal_to_1
  #(
    .NB_BITS(CMDP_DEPTH)
  )find_last_bit_equal_to_1
  (
    .in_vect_mh         (s1_cmdp_avail),
    .out_vect_1h        (s1_cmdp_first_avail_1h),
    .out_vect_ext_to_lsb(/*UNUSED*/)
  );

  always_comb
    for (int i=0; i<CMDP_DEPTH; i=i+1)
      s1_cmdp_batch_cmd_masked[i] = s1_cmdp_first_avail_1h[i] ? s1_cmdp_batch_cmd[i] : '0;

  always_comb begin
    br_batch_cmd_t tmp;
    tmp = '0;
    for (int i=0; i<CMDP_DEPTH; i=i+1)
      tmp = tmp | s1_cmdp_batch_cmd_masked[i];
    s1_cmdp_batch_cmd_out = tmp;
  end

  assign s1_cmdp_avail_next = s1_cmdp_avail & ~(s1_cmdp_first_avail_1h & {CMDP_DEPTH{s1_cmdp_out_rdy}});

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // Do nothing
    end
    else begin
      if (s1_mux_batch_vld)
        assert(s1_mux_batch_rdy)
        else $fatal(1, "%t > ERROR: Command pool overflow!",$time);
    end
// pragma translate_on

  br_batch_cmd_t               s2_batch_cmd;
  logic                        s2_batch_vld;
  logic                        s2_batch_rdy;

  fifo_element #(
    .WIDTH          (BR_BATCH_CMD_W),
    .DEPTH          (1),
    .TYPE_ARRAY     (3),
    .DO_RESET_DATA  (0),
    .RESET_DATA_VAL (0)
  ) fifo_element_cmdp (
    .clk     (clk),
    .s_rst_n (s_rst_n),

    .in_data (s1_cmdp_batch_cmd_out),
    .in_vld  (s1_cmdp_out_vld),
    .in_rdy  (s1_cmdp_out_rdy),

    .out_data(s2_batch_cmd),
    .out_vld (s2_batch_vld),
    .out_rdy (s2_batch_rdy)
  );

// ---------------------------------------------------------------------------------------------- --
// Counter
// ---------------------------------------------------------------------------------------------- --
  logic [BSK_DIST_ITER_W-1:0] s2_bdc_bsk_cnt;
  logic [BSK_DIST_ITER_W-1:0] s2_bdc_bsk_cntD;
  logic                        s2_last_bdc_bsk_cnt;

  assign s2_last_bdc_bsk_cnt = s2_bdc_bsk_cnt == BSK_DIST_ITER_NB-1;
  assign s2_bdc_bsk_cntD     = srv_bdc_avail ? s2_last_bdc_bsk_cnt ? '0 : s2_bdc_bsk_cnt + 1 : s2_bdc_bsk_cnt;

  always_ff @(posedge clk)
    if (!s_rst_n) s2_bdc_bsk_cnt <= '0;
    else          s2_bdc_bsk_cnt <= s2_bdc_bsk_cntD;

// ---------------------------------------------------------------------------------------------- --
// Pointers
// ---------------------------------------------------------------------------------------------- --
// Broadcast to the servers cmd FIFO.
  logic [PT_W-1:0] s2_rp_lsb;
  logic [PT_W-1:0] s2_wp_lsb;
  logic [PT_W-1:0] s2_wp_lsbD;
  logic [PT_W-1:0] s2_rp_lsbD;
  logic            s2_wp_msb;
  logic            s2_rp_msb;
  logic            s2_wp_msbD;
  logic            s2_rp_msbD;
  logic            s2_fifo_full;

  assign s2_fifo_full = (s2_wp_lsb == s2_rp_lsb) & (s2_wp_msb != s2_rp_msb);

  generate
    if (2**$clog2(SRV_CMD_FIFO_DEPTH) == SRV_CMD_FIFO_DEPTH) begin: batch_pt_power_2_gen// if SRV_CMD_FIFO_DEPTH is a power of 2
      assign {s2_wp_msbD, s2_wp_lsbD} = (s2_batch_vld && s2_batch_rdy) ? {s2_wp_msb, s2_wp_lsb} + 1 :
                                                                         {s2_wp_msb, s2_wp_lsb};
      assign {s2_rp_msbD, s2_rp_lsbD} = (s2_last_bdc_bsk_cnt && srv_bdc_avail) ? {s2_rp_msb, s2_rp_lsb} + 1 :
                                                                                 {s2_rp_msb, s2_rp_lsb};
    end
    else begin : no_batch_pt_power_2_gen
      logic                  last_s2_wp;
      logic                  last_s2_rp;

      assign s2_wp_lsbD = (s2_batch_vld && s2_batch_rdy) ? last_s2_wp ? '0 : s2_wp_lsb + 1 : s2_wp_lsb;
      assign s2_wp_msbD = (s2_batch_vld && s2_batch_rdy) && last_s2_wp ? ~s2_wp_msb : s2_wp_msb;
      assign s2_rp_lsbD = (s2_last_bdc_bsk_cnt && srv_bdc_avail) ? last_s2_rp ? '0 : s2_rp_lsb + 1 : s2_rp_lsb;
      assign s2_rp_msbD = (s2_last_bdc_bsk_cnt && srv_bdc_avail) && last_s2_rp ? ~s2_rp_msb : s2_rp_msb;
      assign last_s2_wp = (s2_wp_lsb == (SRV_CMD_FIFO_DEPTH-1));
      assign last_s2_rp = (s2_rp_lsb == (SRV_CMD_FIFO_DEPTH-1));

    end
  endgenerate

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      s2_wp_msb        <= '0;
      s2_rp_msb        <= '0;
      s2_wp_lsb        <= 1'b0;
      s2_rp_lsb        <= 1'b0;
    end
    else begin
      s2_wp_msb        <= s2_wp_msbD;
      s2_rp_msb        <= s2_rp_msbD;
      s2_wp_lsb        <= s2_wp_lsbD;
      s2_rp_lsb        <= s2_rp_lsbD;
    end

// ---------------------------------------------------------------------------------------------- --
// Pointers
// ---------------------------------------------------------------------------------------------- --
  assign arb_srv_batch_cmd = s2_batch_cmd;
  assign arb_srv_batch_cmd_avail = s2_batch_vld & ~s2_fifo_full;
  assign s2_batch_rdy = ~s2_fifo_full;
endmodule

