// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module modelizes the generation of batch_cmd.
//
// ==============================================================================================

module tb_batch_cmd_gen_model
  import pep_common_param_pkg::*;
#(
  parameter int    SIMU_BATCH_NB  = 10, // Total number of processed batches.
  parameter int    BATCH_NB        = 2,  // Number of batches that are alive simultaneously
  parameter string FILE_BATCH_CMD  = "",
  parameter string FILE_DATA_TYPE  = "",
  parameter int    DATA_RAND_RANGE = 1024,
  parameter int    BATCH_DLY       = 32 // Number of cycles between batch_cmd and the data
) (
  input logic                    clk,
  input logic                    s_rst_n,

  input logic                    run, // (1) Send batch command.

  input logic                    in_sample_batch_last,
  input logic                    out_sample_batch_last,

  output logic [BR_BATCH_CMD_W-1:0] batch_cmd,
  output logic                   batch_cmd_avail,
  output integer                 batch_cmd_cnt,
  output logic                   do_send_data, // signal that data of the next batch can be sent
  output logic                   cl_all_idle,  // all batches have been processed.

  output logic                   error_source_batch_open
);

// --------------------------------------------------------------------------------------------- --
// Each NTT core can process up to BATCH_NB pending commands.
// Each command has 3 steps in its life :
// - send the command
// - send corresponding data
// - wait for the response.
// To make several commands live simultaneously, 3 FSM are used, each representing a step.
// Note that several commands can live simultaneously, but only 1 can be in the "send cmd" step,
// and only one in the "send data" step.
  integer cl_batch_cmd_cnt;
  integer cl_batch_data_cnt;
  integer cl_batch_rsp_cnt;
  integer cl_batch_cmd_cntD;
  integer cl_batch_data_cntD;
  integer cl_batch_rsp_cntD;
  integer batch_data_cnt;
  integer batch_data_cntD;

  typedef enum { CL_ST_WAIT_CMD,
                 CL_ST_SEND_CMD} client_state_cmd_e;
  typedef enum { CL_ST_WAIT_DATA,
                 CL_ST_SEND_DATA} client_state_data_e;
  typedef enum { CL_ST_WAIT_RSP,
                 CL_ST_RECEIVE_RSP} client_state_rsp_e;

  client_state_cmd_e   client_state_cmd;
  client_state_cmd_e   next_client_state_cmd;
  client_state_data_e  client_state_data;
  client_state_data_e  next_client_state_data;
  client_state_rsp_e   client_state_rsp;
  client_state_rsp_e   next_client_state_rsp;

  br_batch_cmd_t       cl_batch_cmd;
  logic                cl_batch_cmd_avail;

  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      client_state_cmd  <= CL_ST_WAIT_CMD;
      client_state_data <= CL_ST_WAIT_DATA;
      client_state_rsp  <= CL_ST_WAIT_RSP;
    end
    else begin
      client_state_cmd  <= next_client_state_cmd ;
      client_state_data <= next_client_state_data;
      client_state_rsp  <= next_client_state_rsp ;
    end
  end

  always_comb begin
    case(client_state_cmd)
      CL_ST_WAIT_CMD:
        next_client_state_cmd =  (run && cl_batch_cmd_cnt > 0 && (batch_cmd_cnt < SIMU_BATCH_NB))?
                                 CL_ST_SEND_CMD : client_state_cmd;
      CL_ST_SEND_CMD:
        next_client_state_cmd = cl_batch_cmd_avail ? CL_ST_WAIT_CMD : client_state_cmd;
    endcase
  end

  always_comb begin
    case(client_state_data)
      CL_ST_WAIT_DATA:
        next_client_state_data = cl_batch_data_cnt > 0 ?
                                 CL_ST_SEND_DATA : client_state_data;
      CL_ST_SEND_DATA:
        next_client_state_data = in_sample_batch_last ? CL_ST_WAIT_DATA : client_state_data;
    endcase
  end

  always_comb begin
    case(client_state_rsp)
      CL_ST_WAIT_RSP:
        next_client_state_rsp = cl_batch_rsp_cnt > 0 ?
                                 CL_ST_RECEIVE_RSP : client_state_rsp;
      CL_ST_RECEIVE_RSP:
        next_client_state_rsp = out_sample_batch_last ? CL_ST_WAIT_RSP : client_state_rsp;
    endcase
  end

  logic batch_cmd_avail_dly; // Delay the number of cycles necessary for the twiddle and bsk to load.
                             // => simulate the monomial mult and decomp latency

  assign cl_batch_cmd_cntD  = batch_cmd_avail ?
                                out_sample_batch_last ? cl_batch_cmd_cnt : cl_batch_cmd_cnt - 1 :
                                out_sample_batch_last ? cl_batch_cmd_cnt + 1 : cl_batch_cmd_cnt;
  assign cl_batch_data_cntD = in_sample_batch_last ?
                                batch_cmd_avail_dly ? cl_batch_data_cnt : cl_batch_data_cnt - 1:
                                batch_cmd_avail_dly ? cl_batch_data_cnt+1 : cl_batch_data_cnt;
  assign cl_batch_rsp_cntD  = out_sample_batch_last ?
                                 in_sample_batch_last ? cl_batch_rsp_cnt : cl_batch_rsp_cnt - 1:
                                 in_sample_batch_last ? cl_batch_rsp_cnt+1 : cl_batch_rsp_cnt;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      cl_batch_cmd_cnt  <= BATCH_NB;
      cl_batch_data_cnt <= 0;
      cl_batch_rsp_cnt  <= 0;
    end
    else begin
      cl_batch_cmd_cnt  <= cl_batch_cmd_cntD ;
      cl_batch_data_cnt <= cl_batch_data_cntD;
      cl_batch_rsp_cnt  <= cl_batch_rsp_cntD ;
    end

  logic cl_st_wait_cmd;
  logic cl_st_send_cmd;
  logic cl_st_wait_data;
  logic cl_st_send_data;
  logic cl_st_wait_rsp;
  logic cl_st_receive_rsp;

  assign cl_st_wait_cmd    = client_state_cmd == CL_ST_WAIT_CMD   ;
  assign cl_st_send_cmd    = client_state_cmd == CL_ST_SEND_CMD   ;
  assign cl_st_wait_data   = client_state_data == CL_ST_WAIT_DATA  ;
  assign cl_st_send_data   = client_state_data == CL_ST_SEND_DATA  ;
  assign cl_st_wait_rsp    = client_state_rsp == CL_ST_WAIT_RSP   ;
  assign cl_st_receive_rsp = client_state_rsp == CL_ST_RECEIVE_RSP;

  assign cl_all_idle = cl_st_wait_cmd & cl_st_wait_data & cl_st_wait_rsp & (cl_batch_cmd_cnt == BATCH_NB);
  assign do_send_data = cl_st_send_data;

// --------------------------------------------------------------------------------------------- --
// batch counter
// --------------------------------------------------------------------------------------------- --
  integer batch_cmd_cntD;

  assign batch_cmd_cntD  = batch_cmd_cnt + batch_cmd_avail;
  assign batch_data_cntD = batch_data_cnt + in_sample_batch_last;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      batch_cmd_cnt  <= 0;
      batch_data_cnt <= 0;
    end
    else begin
      batch_cmd_cnt  <= batch_cmd_cntD;
      batch_data_cnt <= batch_data_cntD;
      if (batch_cmd_avail && (batch_cmd_cnt % 5) == 0)
        $display("%t > INFO: Processing batch #%0d / %0d",$time, batch_cmd_cnt, SIMU_BATCH_NB);
    end

  logic [BATCH_DLY-1:0] batch_cmd_avail_sr;
  logic [BATCH_DLY-1:0] batch_cmd_avail_srD;
  assign batch_cmd_avail_srD[0] = batch_cmd_avail;
  assign batch_cmd_avail_srD[BATCH_DLY-1:1] = batch_cmd_avail_sr[BATCH_DLY-2:0];
  always_ff @(posedge clk)
    if (!s_rst_n) batch_cmd_avail_sr <= '0;
    else          batch_cmd_avail_sr <= batch_cmd_avail_srD;
  assign batch_cmd_avail_dly = batch_cmd_avail_sr[BATCH_DLY-1];

// ============================================================================================ //
// Batch command
// ============================================================================================ //
  logic [2*32-1:0] batch_cmd_tmp;
  logic            batch_cmd_vld_tmp;
  logic            batch_cmd_rdy_tmp;
  stream_source
  #(
    .FILENAME   (FILE_BATCH_CMD),
    .DATA_TYPE  (FILE_DATA_TYPE),
    .DATA_W     (2*32),
    .RAND_RANGE (DATA_RAND_RANGE),
    .KEEP_VLD   (1),
    .MASK_DATA  ("x")
  )
  source_batch_cmd
  (
      .clk        (clk),
      .s_rst_n    (s_rst_n),

      .data       (batch_cmd_tmp),
      .vld        (batch_cmd_vld_tmp),
      .rdy        (batch_cmd_rdy_tmp),

      .throughput (DATA_RAND_RANGE)
  );

  assign cl_batch_cmd_avail   = batch_cmd_vld_tmp & (cl_st_send_cmd != 0);
  assign cl_batch_cmd.br_loop = batch_cmd_tmp[1*32+:32];
  assign cl_batch_cmd.pbs_nb  = batch_cmd_tmp[0*32+:32];
  assign batch_cmd_rdy_tmp    = cl_batch_cmd_avail;

  assign batch_cmd            = cl_batch_cmd;
  assign batch_cmd_avail      = cl_batch_cmd_avail;

  initial begin
    error_source_batch_open = 1'b0;
    if (!source_batch_cmd.open()) begin
      $display("%t > ERROR: Opening batch_cmd stream source", $time);
      error_source_batch_open = 1'b1;
    end
    source_batch_cmd.start(0);
  end

endmodule
