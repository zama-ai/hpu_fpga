// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the distribution of the cl_ntt_bsk to the NTT core.
// Handle 1 element of the cl_ntt_bsk.
// ==============================================================================================

module bsk_ntw_client_core
  import param_tfhe_pkg::*;
  import ntt_core_common_param_pkg::*;
  import top_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import bsk_ntw_common_param_pkg::*;
#(
  parameter  int OP_W            = 32,
  parameter  int BATCH_NB        = 2,
  parameter  int RAM_LATENCY     = 2
)
(
  input                         clk,        // clock
  input                         s_rst_n,    // synchronous reset

  input  [OP_W-1:0]             srv_cl_bsk,
  input                         srv_cl_avail,
  input  [LWE_K_W-1:0]          srv_cl_br_loop,
  input  [BSK_GROUP_W-1:0]      srv_cl_group,

  output [OP_W-1:0]             cl_ntt_bsk,
  output                        cl_ntt_vld,
  input                         cl_ntt_rdy,

  // Broadcast from acc
  input  [BR_BATCH_CMD_W-1:0]   batch_cmd,
  input                         batch_cmd_avail, // pulse

  // Error
  output [CLT_ERROR_NB-1:0]     error

);

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int CMD_FIFO_DEPTH = BATCH_NB;
  localparam int BATCH_PT_W     = $clog2(BATCH_NB) == 0 ? 1 : $clog2(BATCH_NB);
  localparam int PT_W           = BSK_GROUP_W;
  localparam int RAM_LATENCY_L  = RAM_LATENCY + 1; // +1 to register read command
  localparam int BUF_DEPTH      = RAM_LATENCY_L + 2; //1 for reading cycle + output reg
  localparam int LOC_NB         = RAM_LATENCY_L + BUF_DEPTH;
  localparam int LOC_W          = $clog2(LOC_NB);
  localparam int RAM_DEPTH      = BATCH_NB * BSK_GROUP_NB;
  localparam int RAM_ADD_W      = $clog2(RAM_DEPTH);

// ============================================================================================== --
// bsk_ntw_client
// ============================================================================================== --
// ---------------------------------------------------------------------------------------------- --
// batch_cmd FIFO
// ---------------------------------------------------------------------------------------------- --
// Use a small FIFO to store the commands that have to be processed.
// Note that this FIFO does not need to be very deep, it depends on the number of batches that can
// be processed in parallel.
  br_batch_cmd_t                    batch_cmd_s;
  logic [BATCH_PT_W-1:0]            batch_cmd_pt;
  br_batch_cmd_t                    s0_batch_cmd;
  logic [BATCH_PT_W-1:0]            s0_batch_cmd_pt;
  logic [RAM_ADD_W-1:0]             s0_batch_add_ofs;
  logic                             s0_batch_cmd_vld;
  logic                             s0_batch_cmd_rdy;
  logic                             batch_cmd_rdy;

  assign batch_cmd_s = batch_cmd;

  fifo_reg #(
    .WIDTH       (BR_BATCH_CMD_W + BATCH_PT_W),
    .DEPTH       (CMD_FIFO_DEPTH),
    .LAT_PIPE_MH ({1'b1, 1'b1})
  ) cmd_fifo (
    .clk     (clk),
    .s_rst_n (s_rst_n),

    .in_data ({batch_cmd_pt, batch_cmd_s}),
    .in_vld  (batch_cmd_avail),
    .in_rdy  (batch_cmd_rdy),

    .out_data({s0_batch_cmd_pt,s0_batch_cmd}),
    .out_vld (s0_batch_cmd_vld),
    .out_rdy (s0_batch_cmd_rdy)
  );

  br_batch_cmd_t          s1_batch_cmd;
  logic [BATCH_PT_W-1:0]  s1_batch_cmd_pt;
  logic [RAM_ADD_W-1:0]   s1_batch_add_ofs;
  logic                   s1_batch_cmd_vld;
  logic                   s1_batch_cmd_rdy;
  assign s0_batch_add_ofs = s0_batch_cmd_pt * BSK_GROUP_NB;
  fifo_element #(
    .WIDTH          (BR_BATCH_CMD_W + RAM_ADD_W + BATCH_PT_W),
    .DEPTH          (1),
    .TYPE_ARRAY     (1),
    .DO_RESET_DATA  (0),
    .RESET_DATA_VAL (0)
  ) fifo_element_cmd (
    .clk     (clk),
    .s_rst_n (s_rst_n),

    .in_data ({s0_batch_cmd_pt,s0_batch_add_ofs,s0_batch_cmd}),
    .in_vld  (s0_batch_cmd_vld),
    .in_rdy  (s0_batch_cmd_rdy),

    .out_data({s1_batch_cmd_pt,s1_batch_add_ofs,s1_batch_cmd}),
    .out_vld (s1_batch_cmd_vld),
    .out_rdy (s1_batch_cmd_rdy)
  );

// ---------------------------------------------------------------------------------------------- --
// Handle batch_cmd input and pointer pt distribution
// ---------------------------------------------------------------------------------------------- --
// According to the br_loop value of the batch_cmd, different pt are attributed.
// If the br_loop is not already present, attribute a free pt.
// If the br_loop is already present, attribute this one.

  // Keep the correspondence between the pt and the associated br_loop.
  logic [BATCH_NB-1:0][LWE_K_W:0]    pt_2_br_loop; // Additional bit to fake an unreachable value for the init.
  logic [BATCH_NB-1:0][LWE_K_W:0]    pt_2_br_loopD;
   // Number of cmd depending on this pt
   // Additional bit to count to BATCH_NB included
  logic [BATCH_NB-1:0][BATCH_PT_W:0] pt_cmd_cnt;
  logic [BATCH_NB-1:0][BATCH_PT_W:0] pt_cmd_cntD;
  logic [BATCH_NB-1:0]               pt_cmd_cnt_inc;
  logic [BATCH_NB-1:0]               pt_cmd_cnt_dec;
  logic [BATCH_NB-1:0]               pt_erase_1h;
  logic [BATCH_NB-1:0]               pt_cmd_cnt_is_0_mh;
  logic [BATCH_NB-1:0]               pt_free_1h;
  logic [BATCH_PT_W-1:0]             free_pt;
  logic [BATCH_NB-1:0]               batch_cmd_match_br_loop_1h;
  logic [BATCH_PT_W-1:0]             batch_cmd_match_pt;

  logic                              batch_cmd_hit;

  always_comb begin
    for (int i=0; i<BATCH_NB; i=i+1) begin
      pt_2_br_loopD[i]              = (batch_cmd_avail && (batch_cmd_pt == i)) ?
                                            batch_cmd_s.br_loop : pt_2_br_loop[i];
      batch_cmd_match_br_loop_1h[i] = (batch_cmd_s.br_loop == pt_2_br_loop[i]);
      pt_cmd_cntD[i]                = pt_cmd_cnt_inc[i] && ~pt_cmd_cnt_dec[i] ? pt_cmd_cnt[i] + 1:
                                        ~pt_cmd_cnt_inc[i] && pt_cmd_cnt_dec[i] ? pt_cmd_cnt[i] - 1: pt_cmd_cnt[i];
      pt_cmd_cnt_is_0_mh[i]         = (pt_cmd_cnt[i] == 0);
    end
  end

  assign batch_cmd_hit = batch_cmd_match_br_loop_1h != 0;
  assign batch_cmd_pt  = batch_cmd_hit ? batch_cmd_match_pt : free_pt;

  assign pt_cmd_cnt_inc = batch_cmd_avail ? batch_cmd_hit ?
                            batch_cmd_match_br_loop_1h : pt_free_1h : '0;
  assign pt_erase_1h    = batch_cmd_avail & ~batch_cmd_hit ? pt_free_1h : '0;

  common_lib_find_first_bit_equal_to_1
  #(
    .NB_BITS(BATCH_NB)
  ) find_first_bit_equal_to_1 (
    .in_vect_mh         (pt_cmd_cnt_is_0_mh),
    .out_vect_1h        (pt_free_1h),
    .out_vect_ext_to_msb(/*UNUSED*/)
  );

  common_lib_one_hot_to_bin #(
    .ONE_HOT_W(BATCH_NB)
  ) one_hot_to_bin_batch_cmd_pt (
    .in_1h     (batch_cmd_match_br_loop_1h),
    .out_value (batch_cmd_match_pt)
  );

  common_lib_one_hot_to_bin #(
    .ONE_HOT_W(BATCH_NB)
  ) one_hot_to_bin_free_pt (
    .in_1h     (pt_free_1h),
    .out_value (free_pt)
  );

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      pt_2_br_loop <= '1; // Unreachable value
      pt_cmd_cnt   <= '0;
    end
    else begin
      pt_2_br_loop <= pt_2_br_loopD;
      pt_cmd_cnt   <= pt_cmd_cntD;
    end

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      if (batch_cmd_avail)
        assert($countones(batch_cmd_match_br_loop_1h) <= 1)
        else $fatal(1, "%t > ERROR: batch_cmd_match_br_loop_1h should be a one hot!", $time);
    end
// pragma translate_on
// ---------------------------------------------------------------------------------------------- --
// Handle srv_cl_bsk input
// ---------------------------------------------------------------------------------------------- --
  logic [BATCH_NB-1:0]              srv_cl_match_br_loop_1h;
  logic                             srv_cl_hit;
  logic [BATCH_PT_W-1:0]            srv_cl_batch_wp;

  always_comb
    for (int i=0; i<BATCH_NB; i=i+1)
      srv_cl_match_br_loop_1h[i]   = (srv_cl_br_loop == pt_2_br_loop[i]);

  assign srv_cl_hit = srv_cl_match_br_loop_1h != 0;

  common_lib_one_hot_to_bin #(
    .ONE_HOT_W(BATCH_NB)
  ) one_hot_to_bin_srv_cl_batch_wp (
    .in_1h     (srv_cl_match_br_loop_1h),
    .out_value (srv_cl_batch_wp)
  );

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      if (srv_cl_avail)
        assert($countones(srv_cl_match_br_loop_1h) <= 1)
        else $fatal(1, "%t > ERROR: srv_cl_match_br_loop_1h should be a one hot!", $time);
    end
// pragma translate_on
// ---------------------------------------------------------------------------------------------- --
// Counters
// ---------------------------------------------------------------------------------------------- --
  logic [STG_ITER_W-1:0] s1_stg_iter;
  logic [STG_ITER_W-1:0] s1_stg_iterD;
  logic [BPBS_ID_W-1:0]   s1_pbs_id;
  logic [BPBS_ID_W-1:0]   s1_pbs_idD;
  logic [INTL_L_W-1:0]   s1_intl_idx;
  logic [INTL_L_W-1:0]   s1_intl_idxD;
  logic                  s1_last_stg_iter;
  logic                  s1_last_pbs_id;
  logic                  s1_last_intl_idx;
  logic                  s1_do_read;

  assign s1_intl_idxD = (s1_do_read) ? s1_last_intl_idx ?
                            '0 : s1_intl_idx + 1 : s1_intl_idx;
  assign s1_stg_iterD = (s1_do_read && s1_last_intl_idx) ? s1_last_stg_iter ?
                            '0 : s1_stg_iter + 1 : s1_stg_iter;
  assign s1_pbs_idD   = (s1_do_read && s1_last_intl_idx && s1_last_stg_iter)?
                            s1_last_pbs_id ? '0 : s1_pbs_id + 1 : s1_pbs_id;

  assign s1_last_intl_idx  = (s1_intl_idx == INTL_L-1);
  assign s1_last_stg_iter  = (s1_stg_iter == (STG_ITER_NB-1));
  assign s1_last_pbs_id    = (s1_pbs_id == s1_batch_cmd.pbs_nb-1);

  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      s1_intl_idx <= '0;
      s1_stg_iter <= '0;
      s1_pbs_id   <= '0;
    end
    else begin
      s1_intl_idx <= s1_intl_idxD;
      s1_stg_iter <= s1_stg_iterD;
      s1_pbs_id   <= s1_pbs_idD;
    end
  end

// ---------------------------------------------------------------------------------------------- --
// cl_ntt_bsk write and read pointers
// ---------------------------------------------------------------------------------------------- --
  logic [PT_W-1:0]                   s1_rp;
  logic [BATCH_NB-1:0][PT_W-1:0]     s1_wp; // count the number of writing
  logic [PT_W-1:0]                   s1_rpD;
  logic [BATCH_NB-1:0][PT_W-1:0]     s1_wpD;
  logic [BATCH_NB-1:0]               pt_complete;
  logic [BATCH_NB-1:0]               pt_completeD;
  logic [BATCH_NB-1:0]               s1_last_wp;
  logic                              s1_last_rp;

  assign s1_last_rp = (s1_rp == BSK_GROUP_NB-1);
  assign s1_rpD     = s1_do_read ? s1_last_rp ? '0 : s1_rp + 1 : s1_rp;

  always_comb begin
    for (int i=0; i<BATCH_NB; i=i+1) begin
      s1_last_wp[i] = (s1_wp[i] == BSK_GROUP_NB-1);
      s1_wpD[i]     = (srv_cl_avail && srv_cl_hit && (srv_cl_batch_wp == i) && ~pt_complete[i]) ?
                         s1_last_wp[i] ? '0 : s1_wp[i] + 1 : s1_wp[i];
    end
  end

  always_comb
    for (int i=0; i<BATCH_NB; i=i+1) begin
      pt_completeD[i] = pt_erase_1h[i] ? 1'b0: // done and no other command on this pt
                        srv_cl_avail & srv_cl_hit && s1_last_wp[i] & (srv_cl_batch_wp == i) ? 1'b1 : pt_complete[i];
      pt_cmd_cnt_dec[i] = s1_batch_cmd_rdy & (s1_batch_cmd_pt == i);
    end

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      s1_rp       <= '0;
      s1_wp       <= '0;
      pt_complete <= '0;
    end
    else begin
      s1_rp       <= s1_rpD;
      s1_wp       <= s1_wpD;
      pt_complete <= pt_completeD;
    end

// ---------------------------------------------------------------------------------------------- --
// Output Buffer
// ---------------------------------------------------------------------------------------------- --
  logic [BUF_DEPTH-1:0][OP_W-1:0] buf_data;
  logic [BUF_DEPTH:0]  [OP_W-1:0] buf_data_ext;
  logic [BUF_DEPTH-1:0][OP_W-1:0] buf_dataD;
  logic [BUF_DEPTH-1:0]           buf_en;
  logic [BUF_DEPTH-1:0]           buf_enD;
  logic [BUF_DEPTH:0]             buf_en_ext;
  logic                           buf_in_avail;
  logic [OP_W-1:0]                buf_in_data;
  logic [BUF_DEPTH-1:0]           buf_in_wren_1h;
  logic [BUF_DEPTH-1:0]           buf_in_wren_1h_tmp;
  logic [BUF_DEPTH-1:0]           buf_in_wren_1h_tmp2;
  logic                           buf_shift;

  // Add 1 element to avoid warning, while selecting out of range.
  assign buf_data_ext        = {{OP_W{1'bx}}, buf_data};
  assign buf_en_ext          = {1'b0, buf_en};
  assign buf_in_wren_1h_tmp  = buf_shift ? {1'b0, buf_en[BUF_DEPTH-1:1]} : buf_en;
  // Find first bit = 0
  assign buf_in_wren_1h_tmp2 = buf_in_wren_1h_tmp ^ {buf_in_wren_1h_tmp[BUF_DEPTH-2:0], 1'b1};
  assign buf_in_wren_1h      = buf_in_wren_1h_tmp2 & {BUF_DEPTH{buf_in_avail}};

  always_comb begin
    for (int i = 0; i<BUF_DEPTH; i=i+1) begin
      buf_dataD[i] = buf_in_wren_1h[i] ? buf_in_data :
                     buf_shift         ? buf_data_ext[i+1] : buf_data[i];
      buf_enD[i] = buf_in_wren_1h[i] | (buf_shift ? buf_en_ext[i+1] : buf_en[i]);
    end
  end

  always_ff @(posedge clk) begin
    buf_data <= buf_dataD;
  end

  always_ff @(posedge clk)
    if (!s_rst_n) buf_en <= '0;
    else          buf_en <= buf_enD;

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      if (buf_in_avail) begin
        assert(buf_in_wren_1h != 0)
        else $fatal(1, "%t > ERROR: FIFO output buffer overflow!", $time);
      end
    end
// pragma translate_on

// ---------------------------------------------------------------------------------------------- --
// Read
// ---------------------------------------------------------------------------------------------- --
  logic                     s1_free_loc_exists;
  logic [LOC_W-1:0]         s1_free_loc_cnt;
  logic [LOC_NB-1:0]        s1_data_en;
  logic [RAM_LATENCY_L-1:0] ram_data_avail_dly;
  logic [RAM_LATENCY_L-1:0] ram_data_avail_dlyD;
  logic [OP_W-1:0]          ram_rd_data;

  assign s1_do_read = s1_batch_cmd_vld & pt_complete[s1_batch_cmd_pt] & s1_free_loc_exists;

  assign ram_data_avail_dlyD[0] = s1_do_read;
  if (RAM_LATENCY_L > 1) begin : ram_latency_gt_1_gen
    assign ram_data_avail_dlyD[RAM_LATENCY_L-1:1] = ram_data_avail_dly[RAM_LATENCY_L-2:0];
  end

  always_ff @(posedge clk)
    if (!s_rst_n) ram_data_avail_dly <= '0;
    else          ram_data_avail_dly <= ram_data_avail_dlyD;

  assign s1_data_en =  {buf_en, ram_data_avail_dly};
  always_comb begin
    logic [LOC_W-1:0] cnt;
    cnt = '0;
    for (int i=0; i<LOC_NB; i=i+1) begin
      cnt = cnt + s1_data_en[i];
    end
    s1_free_loc_cnt = cnt;
  end

  assign s1_free_loc_exists  = s1_free_loc_cnt < BUF_DEPTH;

  // Buffer input
  assign buf_in_avail     = ram_data_avail_dly[RAM_LATENCY_L-1];
  assign buf_in_data      = ram_rd_data;
  assign s1_batch_cmd_rdy = s1_do_read & s1_last_rp & s1_last_pbs_id;

// ---------------------------------------------------------------------------------------------- --
// RAM
// ---------------------------------------------------------------------------------------------- --
  logic                   ram_rd_en;
  logic                   ram_rd_enD;
  logic                   ram_wr_en;
  logic                   ram_wr_enD;
  logic [RAM_ADD_W-1:0]   ram_rd_add;
  logic [RAM_ADD_W-1:0]   ram_rd_addD;
  logic [RAM_ADD_W-1:0]   ram_wr_add;
  logic [RAM_ADD_W-1:0]   ram_wr_addD;
  logic [OP_W-1:0]        ram_wr_data;
  logic [OP_W-1:0]        ram_wr_dataD;

  assign ram_rd_addD  = s1_rp + s1_batch_add_ofs;
  assign ram_rd_enD   = s1_do_read;
  assign ram_wr_addD  = srv_cl_batch_wp * BSK_GROUP_NB + srv_cl_group;
  assign ram_wr_enD   = srv_cl_avail & srv_cl_hit & ~pt_complete[srv_cl_batch_wp];
  assign ram_wr_dataD = srv_cl_bsk;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      ram_wr_en <= 1'b0;
      ram_rd_en <= 1'b0;
    end
    else begin
      ram_wr_en <= ram_wr_enD;
      ram_rd_en <= ram_rd_enD;
    end

  always_ff @(posedge clk) begin
    ram_wr_add  <= ram_wr_addD;
    ram_rd_add  <= ram_rd_addD;
    ram_wr_data <= ram_wr_dataD;
  end

  ram_wrapper_1R1W #(
    .WIDTH             (OP_W),
    .DEPTH             (RAM_DEPTH),
    .RD_WR_ACCESS_TYPE (1),
    .KEEP_RD_DATA      (0),
    .RAM_LATENCY       (RAM_LATENCY)
  ) client_ram (
    .clk       (clk),
    .s_rst_n   (s_rst_n),

    .rd_en     (ram_rd_en),
    .rd_add    (ram_rd_add),
    .rd_data   (ram_rd_data),

    .wr_en     (ram_wr_en),
    .wr_add    (ram_wr_add),
    .wr_data   (ram_wr_data)
  );

// ---------------------------------------------------------------------------------------------- --
// Output
// ---------------------------------------------------------------------------------------------- --
  assign cl_ntt_bsk = buf_data[0];
  assign cl_ntt_vld = buf_en[0];

  assign buf_shift = cl_ntt_rdy & cl_ntt_vld;

// ---------------------------------------------------------------------------------------------- --
// Error
// ---------------------------------------------------------------------------------------------- --
  logic error_batch_cmd;
  logic error_bsk_underflow;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      error_batch_cmd <= 1'b0;
    end
    else begin
      if (batch_cmd_avail) begin
        assert(batch_cmd_rdy)
        else begin
//pragma translate_off
          $fatal(1,"%t > ERROR: batch_cmd_fifo overflow!", $time);
//pragma translate_on
          error_batch_cmd <= 1'b1;
        end
      end
      else
        error_batch_cmd <= 1'b0;
    end

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      error_bsk_underflow <= 1'b0;
    end
    else begin
      if (cl_ntt_rdy) begin
        assert(cl_ntt_vld)
        else begin
//pragma translate_off
          $fatal(1,"%t > ERROR: No valid cl_ntt_bsk when needed!", $time);
//pragma translate_on
          error_bsk_underflow <= 1'b1;
        end
      end
      else
        error_bsk_underflow <= 1'b0;
    end

  assign error = {error_batch_cmd, error_bsk_underflow};
endmodule
