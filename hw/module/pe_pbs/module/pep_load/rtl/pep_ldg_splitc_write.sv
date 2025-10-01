// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the GLWE data read from memory.
// This module formats them to fit the GRAM, and write them in GRAM.
//
// ==============================================================================================

module pep_ldg_splitc_write
  import top_common_param_pkg::*;
  import param_tfhe_pkg::*;
  import pep_common_param_pkg::*;
  import ntt_core_common_param_pkg::*;
#(
  parameter int COEF_NB = 4,
  parameter bit IN_PIPE = 1'b0,
  parameter bit IN_DLY  = 1'b0 // Dealy for arbiter signal
)
(
  input  logic                                                     clk,        // clock
  input  logic                                                     s_rst_n,    // synchronous reset

  // From GRAM arbiter
  input  logic [GRAM_NB-1:0]                                       garb_ldg_avail_1h,

  // Command
  input  logic [LOAD_GLWE_CMD_W-1:0]                               in_cmd,
  input  logic                                                     in_cmd_vld,
  output logic                                                     in_cmd_rdy,
  output logic                                                     cmd_done,

  input  logic [COEF_NB-1:0][MOD_Q_W-1:0]                          in_data,
  input  logic                                                     in_data_vld,
  output logic                                                     in_data_rdy,

  // Write GLWE RAM
  // This memory is composed of GRAM_NB independent RAMs
  output logic [GRAM_NB-1:0][PSI/4-1:0][R-1:0]                     glwe_ram_wr_en,
  output logic [GRAM_NB-1:0][PSI/4-1:0][R-1:0][GLWE_RAM_ADD_W-1:0] glwe_ram_wr_add,
  output logic [GRAM_NB-1:0][PSI/4-1:0][R-1:0][MOD_Q_W-1:0]        glwe_ram_wr_data,

  output logic                                                     ldg_rif_rcp_dur

);

// ============================================================================================== //
// localparam
// ============================================================================================== //
  localparam int QPSI      = PSI / 4;
  localparam int SUBW_NB   = QPSI*R > COEF_NB ? (QPSI*R) / COEF_NB : 1;
  localparam int SUBW_W    = $clog2(SUBW_NB)==0 ? 1 : $clog2(SUBW_NB);
  localparam int SUBW_COEF = QPSI*R > COEF_NB ? COEF_NB : QPSI*R;

  localparam int RAM_PBS_ADD_OFS      = STG_ITER_NB * GLWE_K_P1;
  localparam int RAM_PBS_BODY_ADD_OFS = STG_ITER_NB * GLWE_K;

  generate
    if (COEF_NB > QPSI*R) begin : _UNSUPPORTED_COEF_NB
      $fatal(1,"> ERROR: pep_ldg splitc only supports COEF_NB(%0d) <= R*PSI/4(%0d)",COEF_NB,R*QPSI);
    end
  endgenerate

// ============================================================================================== //
// Input pipe
// ============================================================================================== //
  //== access avail
  logic [GRAM_NB-1:0] gram_avail_1h;

  always_ff @(posedge clk)
    if (!s_rst_n) gram_avail_1h <= '0;
    else          gram_avail_1h <= garb_ldg_avail_1h;

  //== Reception command
  load_glwe_cmd_t        rcp_cmd;
  logic                  rcp_vld;
  logic                  rcp_rdy;

  load_glwe_cmd_t        rcp_cmd_tmp;
  logic                  rcp_vld_tmp;
  logic                  rcp_rdy_tmp;

  logic [GLWE_RAM_ADD_W-1:0] rcp_pid_add_ofs;
  logic [GLWE_RAM_ADD_W-1:0] rcp_pid_add_ofs_tmp;
  // Address in the GRAM : precompute to ease timing
  assign rcp_pid_add_ofs_tmp = rcp_cmd_tmp.pid.grof * RAM_PBS_ADD_OFS + RAM_PBS_BODY_ADD_OFS; // We only write the body part.

  fifo_element #(
    .WIDTH          (LOAD_GLWE_CMD_W),
    .DEPTH          (1),
    .TYPE_ARRAY     (4'h3),
    .DO_RESET_DATA  (1'b0),
    .RESET_DATA_VAL (0)
  ) rcp_fifo_element_0 (
    .clk      (clk),
    .s_rst_n  (s_rst_n),

    .in_data  (in_cmd),
    .in_vld   (in_cmd_vld),
    .in_rdy   (in_cmd_rdy),

    .out_data (rcp_cmd_tmp),
    .out_vld  (rcp_vld_tmp),
    .out_rdy  (rcp_rdy_tmp)
  );

  fifo_element #(
    .WIDTH          (GLWE_RAM_ADD_W + LOAD_GLWE_CMD_W),
    .DEPTH          (2),
    .TYPE_ARRAY     ({4'h1,4'h2}),
    .DO_RESET_DATA  (1'b0),
    .RESET_DATA_VAL (0)
  ) rcp_fifo_element_1 (
    .clk     (clk),
    .s_rst_n (s_rst_n),

    .in_data ({rcp_pid_add_ofs_tmp,rcp_cmd_tmp}),
    .in_vld  (rcp_vld_tmp),
    .in_rdy  (rcp_rdy_tmp),

    .out_data({rcp_pid_add_ofs,rcp_cmd}),
    .out_vld (rcp_vld),
    .out_rdy (rcp_rdy)
  );

  //== Data
  logic [COEF_NB-1:0][MOD_Q_W-1:0] r0_data;
  logic                            r0_vld;
  logic                            r0_rdy;

  generate
    if (IN_PIPE) begin : gen_in_pipe
      fifo_element #(
        .WIDTH          (COEF_NB * MOD_Q_W),
        .DEPTH          (2),
        .TYPE_ARRAY     ({4'h1,4'h2}),
        .DO_RESET_DATA  (1'b0),
        .RESET_DATA_VAL (0)
      ) in_data_fifo_element (
        .clk     (clk),
        .s_rst_n (s_rst_n),

        .in_data (in_data),
        .in_vld  (in_data_vld),
        .in_rdy  (in_data_rdy),

        .out_data(r0_data),
        .out_vld (r0_vld),
        .out_rdy (r0_rdy)
      );
    end
    else begin
      assign r0_data     = in_data;
      assign r0_vld      = in_data_vld;
      assign in_data_rdy = r0_rdy;
    end
  endgenerate

// ============================================================================================== //
// Input delay
// ============================================================================================== //
  // Delay between 2 write modules.
  logic [GRAM_NB-1:0] r0_gram_avail_1h;
  generate
    if (IN_DLY) begin : gen_in_dly
      always_ff @(posedge clk)
        if (!s_rst_n) r0_gram_avail_1h <= '0;
        else          r0_gram_avail_1h <= gram_avail_1h;

    end
    else begin : gen_no_in_dly
      assign r0_gram_avail_1h = gram_avail_1h;
    end
  endgenerate

// ============================================================================================== //
// Counters
// ============================================================================================== //
  // Write COEF_NB coefficients at a time.
  logic [QPSI*R-1:0]   r0_wr_mask;
  logic [QPSI*R-1:0]   r0_wr_maskD;
  logic [2*QPSI*R-1:0] r0_wr_maskD_tmp;

  logic [SUBW_W-1:0]   r0_subw_cnt;
  logic [SUBW_W-1:0]   r0_subw_cntD;
  logic                r0_last_subw_cnt;

  logic [STG_ITER_W-1:0] r0_stg_iter;
  logic [STG_ITER_W-1:0] r0_stg_iterD;
  logic                  r0_last_stg_iter;

  logic [GLWE_RAM_ADD_W-1:0] r0_add;

  logic                  r0_pbs_last;

  assign r0_last_subw_cnt = r0_subw_cnt == (SUBW_NB-1);
  assign r0_last_stg_iter = r0_stg_iter == (STG_ITER_NB-1);
  assign r0_pbs_last      = r0_last_subw_cnt & r0_last_stg_iter;
  assign r0_subw_cntD     = (r0_vld && r0_rdy) ? r0_last_subw_cnt ? '0 : r0_subw_cnt + 1 : r0_subw_cnt;
  assign r0_stg_iterD     = (r0_vld && r0_rdy && r0_last_subw_cnt)? r0_last_stg_iter ? '0 : r0_stg_iter + 1: r0_stg_iter;

  assign r0_wr_maskD_tmp = {2{r0_wr_mask}} << SUBW_COEF;
  assign r0_wr_maskD     = r0_vld && r0_rdy ? r0_wr_maskD_tmp[2*QPSI*R-1:QPSI*R] : r0_wr_mask;

  assign r0_add          = rcp_pid_add_ofs + r0_stg_iter;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      r0_wr_mask  <= 2**SUBW_COEF - 1;
      r0_subw_cnt <= '0;
      r0_stg_iter <= '0;
    end
    else begin
      r0_wr_mask  <= r0_wr_maskD;
      r0_subw_cnt <= r0_subw_cntD;
      r0_stg_iter <= r0_stg_iterD;
    end

  assign r0_rdy  = r0_gram_avail_1h[rcp_cmd.pid.grid] & rcp_vld;
  assign rcp_rdy = r0_gram_avail_1h[rcp_cmd.pid.grid] & r0_vld & r0_pbs_last;
                   // We might have lint errors here because "grid" can index more than the width
                   // of the indexed vector. Still, this won't happen by construction.

  //== Output
  // NOTE : arbiter access authorization used here. Command must be sent in 2 cycles exactly.
  // This is done in all the GRAM masters.
  logic                            r0_ram_wr_en;
  logic [GRAM_ID_W-1:0]            r0_ram_wr_grid;
  logic [COEF_NB-1:0][MOD_Q_W-1:0] r0_ram_wr_data;
  logic [GLWE_RAM_ADD_W-1:0]       r0_ram_wr_add;


  assign r0_ram_wr_en   = r0_vld & r0_rdy;
  assign r0_ram_wr_grid = rcp_cmd.pid.grid;
  assign r0_ram_wr_data = r0_data;
  assign r0_ram_wr_add  = r0_add;

// ============================================================================================== //
// Done
// ============================================================================================== //
  logic cmd_doneD;

  assign cmd_doneD = r0_ram_wr_en & r0_pbs_last;

  always_ff @(posedge clk)
    if (!s_rst_n) cmd_done <= 1'b0;
    else          cmd_done <= cmd_doneD;

// ============================================================================================== //
// Format the output
// ============================================================================================== //
// ---------------------------------------------------------------------------------------------- //
// Extend to RxPSI
// ---------------------------------------------------------------------------------------------- //
  /*(* dont_touch = "yes" *)*/logic [QPSI-1:0][R-1:0]                     r1_ram_wr_en;
  /*(* dont_touch = "yes" *)*/logic [QPSI-1:0][R-1:0][MOD_Q_W-1:0]        r1_ram_wr_data;
  /*(* dont_touch = "yes" *)*/logic [QPSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0] r1_ram_wr_add;
  logic [GRAM_NB-1:0]                                                     r1_ram_wr_grid_1h;

  logic [QPSI-1:0][R-1:0]                     r1_ram_wr_enD;
  logic [QPSI-1:0][R-1:0][MOD_Q_W-1:0]        r1_ram_wr_dataD;
  logic [QPSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0] r1_ram_wr_addD;
  logic [GRAM_NB-1:0]                         r1_ram_wr_grid_1hD;

  assign r1_ram_wr_grid_1hD = 1 << r0_ram_wr_grid;

  assign r1_ram_wr_enD   = {QPSI*R{r0_ram_wr_en}} & r0_wr_mask ;
  assign r1_ram_wr_dataD = {SUBW_NB{r0_ram_wr_data}};
  assign r1_ram_wr_addD  = {QPSI*R{r0_ram_wr_add}};

  always_ff @(posedge clk)
    if (!s_rst_n) r1_ram_wr_en <= '0;
    else          r1_ram_wr_en <= r1_ram_wr_enD;

  always_ff @(posedge clk) begin
    r1_ram_wr_grid_1h <= r1_ram_wr_grid_1hD;
    r1_ram_wr_data    <= r1_ram_wr_dataD;
    r1_ram_wr_add     <= r1_ram_wr_addD;
  end

// ---------------------------------------------------------------------------------------------- //
// Extend to GRAM_NB
// ---------------------------------------------------------------------------------------------- //
  /*(* dont_touch = "yes" *)*/logic [GRAM_NB-1:0][QPSI-1:0][R-1:0]                     r2_ram_wr_en;
  /*(* dont_touch = "yes" *)*/logic [GRAM_NB-1:0][QPSI-1:0][R-1:0][MOD_Q_W-1:0]         r2_ram_wr_data;
  /*(* dont_touch = "yes" *)*/logic [GRAM_NB-1:0][QPSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0] r2_ram_wr_add;

  logic [GRAM_NB-1:0][QPSI-1:0][R-1:0]                     r2_ram_wr_enD;
  logic [GRAM_NB-1:0][QPSI-1:0][R-1:0][MOD_Q_W-1:0]        r2_ram_wr_dataD;
  logic [GRAM_NB-1:0][QPSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0] r2_ram_wr_addD;

  assign r2_ram_wr_dataD = {GRAM_NB{r1_ram_wr_data}};
  assign r2_ram_wr_addD  = {GRAM_NB{r1_ram_wr_add}};

  always_comb
    for (int i=0; i<GRAM_NB; i=i+1)
      r2_ram_wr_enD[i] = {R*QPSI{r1_ram_wr_grid_1h[i]}} & r1_ram_wr_en;

  always_ff @(posedge clk)
    if (!s_rst_n) r2_ram_wr_en <= '0;
    else          r2_ram_wr_en <= r2_ram_wr_enD;

  always_ff @(posedge clk) begin
    r2_ram_wr_data <= r2_ram_wr_dataD;
    r2_ram_wr_add  <= r2_ram_wr_addD;
  end

// ---------------------------------------------------------------------------------------------- //
// Send
// ---------------------------------------------------------------------------------------------- //
  assign glwe_ram_wr_en   = r2_ram_wr_en;
  assign glwe_ram_wr_add  = r2_ram_wr_add;
  assign glwe_ram_wr_data = r2_ram_wr_data;

// ============================================================================================== //
// Duration signals for register if
// ============================================================================================== //
  logic ldg_rif_rcp_durD;

  assign ldg_rif_rcp_durD = (rcp_vld && rcp_rdy) ? 1'b0 : rcp_vld;

  always_ff @(posedge clk)
    if (!s_rst_n) ldg_rif_rcp_dur <= 1'b0;
    else          ldg_rif_rcp_dur <= ldg_rif_rcp_durD;

endmodule
