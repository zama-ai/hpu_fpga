// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the sample extraction, and the rotation with b.
// It reads the coefficients from GRAM, and orders them according to b and, does the negation
// when necessary.
// Data in GRAM are assumed to be in reverse order.
//
// This module deals with the access to GRAM, and the coefficient rotation.
// ==============================================================================================

`include "pep_mmacc_splitc_sxt_macro_inc.sv"

module pep_mmacc_splitc_sxt_read
  import param_tfhe_pkg::*;
  import top_common_param_pkg::*;
  import ntt_core_common_param_pkg::*;
  import regf_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import pep_mmacc_common_param_pkg::*;
  import pep_mmacc_splitc_sxt_pkg::*;
  import hpu_common_instruction_pkg::*;
#(
  parameter  int DATA_LATENCY       = 6,    // Latency for read data to come back
  parameter  bit WAIT_FOR_ACK       = 1'b0 // Wait for subs cmd ack before starting the process
)
(
  input  logic                            clk,        // clock
  input  logic                            s_rst_n,    // synchronous reset

  // input command
  input  logic                            in_cmd_vld,
  output logic                            in_cmd_rdy,
  input  logic [LWE_COEF_W-1:0]           in_cmd_body,
  input  logic [MMACC_INTERN_CMD_W-1:0]   in_cmd_icmd,

  input  logic                            icmd_ack, // Used if WAIT_FOR_ACK > 0

  // From GRAM arbiter
  input  logic [GRAM_NB-1:0]              garb_sxt_avail_1h,

  // To prepare GRAM access
  output logic                           out_s1_rd_en,
  output logic [GLWE_RAM_ADD_W-1:0]      out_s1_rd_add,
  output logic [GRAM_ID_W-1:0]           out_s1_rd_grid,

  output logic                           out_x0_avail,
  output logic [CMD_SS2_W-1:0]           out_x0_cmd,

  input  logic                           buf_cnt_do_dec, // output join_buffer is being read.

  // For register if
  output logic                           sxt_rif_req_dur

);
// ============================================================================================= --
// localparam
// ============================================================================================= --
  localparam int GLWE_RAM_DEPTH_PBS = STG_ITER_NB * GLWE_K_P1;
  localparam int QPSI               = PSI/4;
  localparam int ICMD_DEPTH         = 4; // To store the mcmd during the icmd_loopback path.
  localparam int LUT_ID_W           = $clog2(MAX_LUT_NB) == 0 ? 1 : $clog2(MAX_LUT_NB);

  `PEP_MMACC_SPLITC_SXT_LOCALPARAM(R,PSI,DATA_LATENCY,REGF_COEF_NB,REGF_COEF_PER_URAM_WORD,REGF_BLWE_WORD_PER_RAM,DATA_THRESHOLD)

  localparam int SR_DEPTH   = DATA_LATENCY + 2 /* s2 + s3 : for formatting */
                                           + 1; /* gram rdata pipe */

  localparam int ACK_DEPTH  = 2;
// pragma translate_off
  generate
    if (RD_DEPTH_MIN < SR_DEPTH) begin : __UNSUPPORTED_OUT_FIFO_DEPTH_
      $fatal(1,"> ERROR: RD_DEPTH_MIN is not enough to stand the throughput of posted readings. Should be at least : %0d instead of %0d",SR_DEPTH,RD_DEPTH_MIN);
    end
    if (REGF_COEF_NB > N) begin : __UNSUPPORTED__REGF_COEF_NB__LT__N_
      $fatal(1,"> ERROR: REGF_COEF_NB (%0d) should be less than N (%0d).", REGF_COEF_NB, N);
    end
    if (R != 2) begin: __UNSUPPORTED__R_
      $fatal(1,"> ERROR: Support only R=2");
    end
    if ((DATA_THRESHOLD % REGF_COEF_PER_URAM_WORD) != 0) begin : __UNSUPPORTED_DATA_THRESHOLD_
      $fatal(1,"> ERROR: DATA_THRESHOLD (%0d) should be a multiple of REGF_COEF_PER_URAM_WORD (%0d)", DATA_THRESHOLD, REGF_COEF_PER_URAM_WORD);
    end
    if (STG_ITER_NB < 2) begin : __UNSUPPORTED_STG_ITER_NB_
      $fatal(1, "> ERROR: Unsupported STG_ITER_NB (%0d) : should be >= 2", STG_ITER_NB);
    end
    if (PSI < 4) begin : __UNSUPPORTED_PSI_
      $fatal(1, "> ERROR: Unsupported PSI (%0d): should be >= 4", PSI);
    end
  endgenerate
// pragma translate_on


// ============================================================================================= --
// typedef
// ============================================================================================= --
  typedef struct packed {
    logic [PID_W-1:0]            pid;
    logic [REGF_REGID_W-1:0]     dst_rid;
    logic [GLWE_RAM_ADD_W-1:0]   add_ofs;
    logic [GLWE_K_P1_W-1:0]      poly_id;
    logic [STG_ITER_W:0]         stg_iter;
    logic [GRAM_ID_W-1:0]        grid;
    logic [LWE_COEF_W-1:0]       rot_factor;
    logic                        is_body;
    logic                        is_last;
  } cmd_s1_t;

  localparam int CMD_S1_W = $bits(cmd_s1_t);

// ============================================================================================= --
// Input pipe
// ============================================================================================= --
//== GRAM arbiter access enable
  logic [GRAM_NB-1:0]     garb_avail_1h;
  logic                   s0_buf_cnt_do_dec;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      garb_avail_1h     <= '0;
      s0_buf_cnt_do_dec <= 1'b0;
    end
    else begin
      garb_avail_1h     <= garb_sxt_avail_1h;
      s0_buf_cnt_do_dec <= buf_cnt_do_dec;
    end

// ============================================================================================= --
// Keep ack
// ============================================================================================= --
  logic s0_ack_vld;
  logic s0_ack_rdy;

  logic ack_error;

  generate
    if (WAIT_FOR_ACK) begin : gen_ack_fifo
      common_lib_pulse_to_rdy_vld
      #(
        .FIFO_DEPTH (ACK_DEPTH)
      ) common_lib_pulse_to_rdy_vld (
        .clk (clk),
        .s_rst_n  (s_rst_n),

        .in_pulse (icmd_ack),

        .out_vld  (s0_ack_vld),
        .out_rdy  (s0_ack_rdy),

        .error    (ack_error)
      );

// pragma translate_off
      always_ff @(posedge clk)
        if (!s_rst_n) begin
          // Do nothing
        end
        else begin
          assert(ack_error == 1'b0)
          else begin
            //$fatal(1,"%t > ERROR: ack input fifo overflows!", $time);
            $display("%t > ERROR: ack input fifo overflows!", $time);
          end
        end
// pragma translate_on
    end
  endgenerate
// ============================================================================================= --
// Input Shift register
// ============================================================================================= --
  // In the main module, add a shift register to compensate the delay introduced SLR crossing.logic s0_vld;
  logic                  s0_vld;
  logic                  s0_rdy;
  logic [LWE_COEF_W-1:0] s0_body;
  mmacc_intern_cmd_t     s0_icmd;

  generate
    if (WAIT_FOR_ACK == 1'b0) begin : gen_no_wait_for_ack
      // Need a fifo element to generate the ack signal.
      // Also compensate the pipe on the ack path.
      fifo_element #(
        .WIDTH          (LWE_COEF_W + MMACC_INTERN_CMD_W),
        .DEPTH          (1),
        .TYPE_ARRAY     (4'h1),
        .DO_RESET_DATA  (0),
        .RESET_DATA_VAL (0)
      ) cmd_fifo_element (
        .clk     (clk),
        .s_rst_n (s_rst_n),

        .in_data ({in_cmd_body, in_cmd_icmd}),
        .in_vld  (in_cmd_vld),
        .in_rdy  (in_cmd_rdy),

        .out_data({s0_body, s0_icmd}),
        .out_vld (s0_vld),
        .out_rdy (s0_rdy)
      );

    end
    else begin : gen_wait_for_ack
      logic s0_vld_tmp;
      logic s0_rdy_tmp;

      assign s0_vld     = s0_vld_tmp & s0_ack_vld;
      assign s0_rdy_tmp = s0_rdy & s0_ack_vld;
      assign s0_ack_rdy = s0_rdy & s0_vld_tmp;

      fifo_element #(
        .WIDTH          (LWE_COEF_W + MMACC_INTERN_CMD_W),
        .DEPTH          (ICMD_DEPTH),
        .TYPE_ARRAY     ({4'h1,{ICMD_DEPTH-2{4'h2}},4'h3}),
        .DO_RESET_DATA  (0),
        .RESET_DATA_VAL (0)
      ) delay_fifo_reg (
        .clk     (clk),
        .s_rst_n (s_rst_n),

        .in_data ({in_cmd_body, in_cmd_icmd}),
        .in_vld  (in_cmd_vld),
        .in_rdy  (in_cmd_rdy),

        .out_data({s0_body, s0_icmd}),
        .out_vld (s0_vld_tmp),
        .out_rdy (s0_rdy_tmp)
      );

// pragma translate_off
      always_ff @(posedge clk)
        if (!s_rst_n) begin
          // do nothing
        end
        else begin
          if (s0_ack_vld) begin
            assert(s0_vld_tmp)
            else begin
              $fatal(1,"%t > ERROR: Not available icmd at the output of delay_fifo_reg when s0_icmd_ack arrives.", $time);
            end
          end
        end
// pragma translate_on
    end
  endgenerate

// ============================================================================================= --
// S0
// ============================================================================================= --

// ----------------------------------------------------------------------------
// Extract the LUT amount
// ----------------------------------------------------------------------------
  logic [LUT_ID_W-1:0] s0_last_lut_id;
  assign s0_last_lut_id = ~({LUT_ID_W{1'b1}} << s0_icmd.map_elt.log_lut_nb);

// --------------------------------------------------------------------------------------------- --
// Counters
// --------------------------------------------------------------------------------------------- --
  logic                       s0_do_read;
  logic                       s0_is_mask;
  logic                       s0_is_body;
  logic                       s0_last_lut;

  logic [GLWE_K_P1_W-1:0]     s0_poly_id;
  logic [STG_ITER_W-1:0]      s0_stg_iter;
  logic [LUT_ID_W-1:0]        s0_lut_id;
  logic [GLWE_K_P1_W-1:0]     s0_poly_idD;
  logic [STG_ITER_W-1:0]      s0_stg_iterD;
  logic [LUT_ID_W-1:0]        s0_lut_idD;

  logic                       s0_last_stg_iter;
  logic                       s0_last_poly_id;

  assign s0_is_mask        = s0_poly_id < GLWE_K;
  assign s0_is_body        = s0_poly_id == (GLWE_K_P1-1);
  assign s0_last_stg_iter  = s0_is_body | (s0_stg_iter == STG_ITER_NB-1);
  assign s0_last_poly_id   = s0_is_body;
  assign s0_last_lut       = s0_lut_id == s0_last_lut_id;
  assign s0_stg_iterD = s0_do_read ? s0_last_stg_iter ? '0 : s0_stg_iter + 1 :
                        s0_stg_iter;
  assign s0_poly_idD  = s0_do_read && s0_last_stg_iter ? s0_last_poly_id ? '0 : s0_poly_id + 1 :
                        s0_poly_id;
  assign s0_lut_idD   = s0_do_read && s0_last_stg_iter && s0_last_poly_id ?
                        s0_last_lut ? '0 : s0_lut_id + 1 : s0_lut_id;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      s0_poly_id  <= '0;
      s0_stg_iter <= '0;
      s0_lut_id   <= '0;
    end
    else begin
      s0_poly_id  <= s0_poly_idD ;
      s0_stg_iter <= s0_stg_iterD;
      s0_lut_id   <= s0_lut_idD;
    end

  //== Control
  logic s0_s1_vld;
  logic s0_s1_rdy;
  logic s0_free_loc; // free locations in join_fifo

  assign s0_s1_vld   = s0_vld & s0_free_loc;
  assign s0_do_read  = s0_s1_vld & s0_s1_rdy;
  assign s0_rdy      = s0_s1_rdy & s0_free_loc & s0_last_stg_iter
                     & s0_last_poly_id & s0_last_lut;

// --------------------------------------------------------------------------------------------- --
// Sample rot_b
// --------------------------------------------------------------------------------------------- --
  logic [LWE_COEF_W-1:0] s0_rot_factor;
  logic [LWE_COEF_W-1:0] s0_lut_ofs;

  assign s0_lut_ofs = s0_lut_id << (N_SZ - s0_icmd.map_elt.log_lut_nb);
  assign s0_rot_factor = s0_body + s0_lut_ofs;

// --------------------------------------------------------------------------------------------- --
// Address offset
// --------------------------------------------------------------------------------------------- --
  logic [GLWE_RAM_ADD_W-1:0] s0_add_ofs;

  assign s0_add_ofs = s0_icmd.map_elt.pid.grof * GLWE_RAM_DEPTH_PBS;

// --------------------------------------------------------------------------------------------- --
// Regfile ID
// --------------------------------------------------------------------------------------------- --
  logic [REGF_REGID_W-1:0] s0_dst_rid;

  // Each LUT extraction will write to a consecutive register ID
  // The output register index should always start aligned to a power of
  // two.
  assign s0_dst_rid = REGF_REGID_W'(s0_icmd.map_elt.dst_rid) | REGF_REGID_W'(s0_lut_id);

// pragma translate_off
  always @(posedge clk) begin
    if (s_rst_n & s0_rdy & s0_vld) begin
      logic [REGF_REGID_W-1:0] _dst_masked;
      assign _dst_masked = s0_icmd.map_elt.dst_rid & s0_last_lut_id;

      many_assert: assert(~|_dst_masked) else begin
        $fatal(1, {"%t > ERROR: ManyLUT destination RID doesn't align to the ",
                  "number of PBS outputs. Destination RID: 0x%0x, ",
                  "Number of PBS outputs: %0d"},
                   $realtime, s0_icmd.map_elt.dst_rid, s0_last_lut_id+1);
      end
    end
  end
// pragma translate_on

// ============================================================================================= --
// S0-S1 pipe
// ============================================================================================= --
  cmd_s1_t s0_s1_cmd;

  cmd_s1_t s1_cmd;
  logic    s1_vld;
  logic    s1_rdy;

  assign s0_s1_cmd.pid        = s0_icmd.map_elt.pid.pid;
  assign s0_s1_cmd.dst_rid    = s0_dst_rid;
  assign s0_s1_cmd.is_body    = s0_is_body;
  assign s0_s1_cmd.is_last    = s0_last_lut;
  assign s0_s1_cmd.add_ofs    = s0_add_ofs;
  assign s0_s1_cmd.poly_id    = s0_poly_id;
  assign s0_s1_cmd.stg_iter   = s0_stg_iter;
  assign s0_s1_cmd.rot_factor = s0_rot_factor;
  assign s0_s1_cmd.grid       = s0_icmd.map_elt.pid.grid;

  fifo_element #(
    .WIDTH          (CMD_S1_W),
    .DEPTH          (1),
    .TYPE_ARRAY     (4'h1),
    .DO_RESET_DATA  (0),
    .RESET_DATA_VAL (0)
  ) s0_fifo_element (
    .clk     (clk),
    .s_rst_n(s_rst_n),

    .in_data (s0_s1_cmd),
    .in_vld  (s0_s1_vld),
    .in_rdy  (s0_s1_rdy),

    .out_data(s1_cmd),
    .out_vld (s1_vld),
    .out_rdy (s1_rdy)
  );

// ============================================================================================= --
// S1 : Address
// ============================================================================================= --
  logic [GLWE_RAM_ADD_W-1:0] s1_rd_add;
  logic [STG_ITER_W-1:0]     s1_rd_add_local;
  logic [N_W-1:0]            s1_rd_dec;
  logic [N_W-1:0]            s1_rd_id_0;
  logic [N_W-1:0]            s1_rd_idx_0;

  assign s1_rd_dec       = rev_order_n(s1_cmd.stg_iter << RD_COEF_W);
  assign s1_rd_id_0      = s1_cmd.rot_factor[N_W-1:0] - s1_rd_dec;
  assign s1_rd_idx_0     = rev_order_n(s1_rd_id_0);
  assign s1_rd_add_local = s1_rd_idx_0 >> RD_COEF_W;
  assign s1_rd_add       = {s1_cmd.poly_id,s1_rd_add_local} + s1_cmd.add_ofs;


  //== Control
  // NOTE : arbiter access authorization used here. Command must be sent in 2 cycles exactly.
  // This is done in all the GRAM masters.
  logic s1_rd_en;
  assign s1_rdy   = garb_avail_1h[s1_cmd.grid];
  assign s1_rd_en = s1_vld & s1_rdy;

// ============================================================================================= --
// S1 : Output
// ============================================================================================= --
  assign out_s1_rd_en   = s1_rd_en;
  assign out_s1_rd_add  = s1_rd_add;
  assign out_s1_rd_grid = s1_cmd.grid;

// ============================================================================================= --
// SS2 : Shift register: wait for the datar
// ============================================================================================= --
  cmd_ss2_t            ss2_cmd_sr [SR_DEPTH-1:0];
  logic [SR_DEPTH-1:0] ss2_avail_sr;
  cmd_ss2_t            ss2_cmd_srD [SR_DEPTH-1:0];
  logic [SR_DEPTH-1:0] ss2_avail_srD;

  assign ss2_cmd_srD[0].pid        = s1_cmd.pid;
  assign ss2_cmd_srD[0].dst_rid    = s1_cmd.dst_rid;
  assign ss2_cmd_srD[0].id_0       = s1_rd_id_0;
  assign ss2_cmd_srD[0].add_local  = s1_rd_add_local;
  assign ss2_cmd_srD[0].rot_factor = s1_cmd.rot_factor;
  assign ss2_cmd_srD[0].is_body    = s1_cmd.is_body;
  assign ss2_cmd_srD[0].is_last    = s1_cmd.is_last;

  assign ss2_avail_srD[0]          = s1_rd_en;
  generate
    if (SR_DEPTH>1) begin
      assign ss2_cmd_srD[SR_DEPTH-1:1]   = ss2_cmd_sr[SR_DEPTH-2:0];
      assign ss2_avail_srD[SR_DEPTH-1:1] = ss2_avail_sr[SR_DEPTH-2:0];
    end
  endgenerate

  always_ff @(posedge clk)
    if (!s_rst_n) ss2_avail_sr <= '0;
    else          ss2_avail_sr <= ss2_avail_srD;

  always_ff @(posedge clk)
    ss2_cmd_sr <= ss2_cmd_srD;

  assign out_x0_avail = ss2_avail_sr[SR_DEPTH-1];
  assign out_x0_cmd   = ss2_cmd_sr[SR_DEPTH-1];

// ============================================================================================= --
// Track buffer filling for the input
// ============================================================================================= --
// Count elements that are present in the join_fifo.
// These elements are GRAM words.
  logic [JOIN_FIFO_DEPTH_WW-1:0] s0_buf_cnt;
  logic [JOIN_FIFO_DEPTH_WW-1:0] s0_buf_cntD;
  logic                               s0_buf_cnt_do_inc;

  assign s0_buf_cnt_do_inc = s0_do_read;
  assign s0_buf_cntD       = s0_buf_cnt + s0_buf_cnt_do_inc - s0_buf_cnt_do_dec;

  always_ff @(posedge clk)
    if (!s_rst_n) s0_buf_cnt <= '0;
    else          s0_buf_cnt <= s0_buf_cntD;

  assign s0_free_loc = s0_buf_cnt < JOIN_FIFO_DEPTH;

// ============================================================================================= --
// Info for register if
// ============================================================================================= --
  logic sxt_rif_req_durD;

  assign sxt_rif_req_durD        = (s0_vld && s0_rdy) ? 1'b0 : s0_vld;

  always_ff @(posedge clk)
    if (!s_rst_n) sxt_rif_req_dur <= 1'b0;
    else          sxt_rif_req_dur <= sxt_rif_req_durD;

endmodule
