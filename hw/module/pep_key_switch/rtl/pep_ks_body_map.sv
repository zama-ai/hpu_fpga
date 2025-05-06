// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module stores the body "b" of the BLWE, in a RAM.
// They are used by the ks_out_process module to do the LWE body computation.
// The input command is used to deliver the body in the correct order, since in
// IPIP, the pid are not processed in order.
// ==============================================================================================

module pep_ks_body_map
  import param_tfhe_pkg::*;
  import pep_common_param_pkg::*;
  import pep_ks_common_param_pkg::*;
#(
  parameter bit IN_PIPE = 1'b0,
  parameter int OP_W    = 64
)
(
  input                        clk,        // clock
  input                        s_rst_n,    // synchronous reset

  input  logic [KS_CMD_W-1:0]  ctrl_bmap_cmd,
  input  logic                 ctrl_bmap_cmd_vld,
  output logic                 ctrl_bmap_cmd_rdy,

  input  logic                 blram_bmap_wr_en,
  input  logic [OP_W-1:0]      blram_bmap_wr_data,
  input  logic [PID_W-1:0]     blram_bmap_wr_pid,

  output logic [OP_W-1:0]      bmap_outp_data,
  output logic [PID_W-1:0]     bmap_outp_pid,
  output logic                 bmap_outp_vld,
  input  logic                 bmap_outp_rdy
);

// ============================================================================================= --
// localparam
// ============================================================================================= --
  localparam int OUT_FIFO_DEPTH = BATCH_PBS_NB < 2 ? 2 : BATCH_PBS_NB;
  localparam int CMD_FIFO_DEPTH = 3;

// ============================================================================================= --
// Input pipe
// ============================================================================================= --
  //== Write body pipe
  logic             s0_map_wr_en;
  logic [OP_W-1:0]  s0_map_wr_data;
  logic [PID_W-1:0] s0_map_wr_pid;

  generate
    if (IN_PIPE) begin : gen_in_pipe
      always_ff @(posedge clk)
        if (!s_rst_n) s0_map_wr_en <= '0;
        else          s0_map_wr_en <= blram_bmap_wr_en;

      always_ff @(posedge clk) begin
        s0_map_wr_data <= blram_bmap_wr_data;
        s0_map_wr_pid  <= blram_bmap_wr_pid;
      end
    end
    else begin
      assign s0_map_wr_data = blram_bmap_wr_data;
      assign s0_map_wr_en   = blram_bmap_wr_en;
      assign s0_map_wr_pid  = blram_bmap_wr_pid;
    end
  endgenerate

  // Input command pipe
  ks_cmd_t  ctrl_bmap_cmd_s;
  logic     ctrl_bmap_cmd_body_vld;
  logic     ctrl_bmap_cmd_body_rdy;
  logic     ctrl_bmap_cmd_is_body;

  ks_cmd_t  p0_cmd;
  logic     p0_cmd_vld;
  logic     p0_cmd_rdy;

  assign ctrl_bmap_cmd_s       = ctrl_bmap_cmd;
  assign ctrl_bmap_cmd_is_body = (ctrl_bmap_cmd_s.ks_loop + LBX) > (LWE_K_P1-1);

  assign ctrl_bmap_cmd_body_vld = ctrl_bmap_cmd_vld & ctrl_bmap_cmd_is_body;
  assign ctrl_bmap_cmd_rdy      = ~ctrl_bmap_cmd_is_body | ctrl_bmap_cmd_body_rdy;

  fifo_reg #(
    .WIDTH       (KS_CMD_W),
    .DEPTH       (CMD_FIFO_DEPTH),
    .LAT_PIPE_MH ({1'b1, 1'b1})
  ) cmd_fifo (
    .clk      (clk),
    .s_rst_n  (s_rst_n),

    .in_data  (ctrl_bmap_cmd),
    .in_vld   (ctrl_bmap_cmd_body_vld),
    .in_rdy   (ctrl_bmap_cmd_body_rdy),

    .out_data (p0_cmd),
    .out_vld  (p0_cmd_vld),
    .out_rdy  (p0_cmd_rdy)
  );

// ============================================================================================= --
// Map
// ============================================================================================= --
  logic [TOTAL_PBS_NB-1:0][OP_W-1:0] body_map;
  logic [TOTAL_PBS_NB-1:0][OP_W-1:0] body_mapD;

  always_comb
    for (int i=0; i<TOTAL_PBS_NB; i=i+1)
      body_mapD[i] = s0_map_wr_en && (s0_map_wr_pid == i) ? blram_bmap_wr_data : body_map[i];

  always_ff @(posedge clk)
    body_map <= body_mapD;

// ============================================================================================= --
// Output order
// ============================================================================================= --
  typedef enum logic [0:0] {
    ST_INIT,
    ST_PROC
  } state_e;

  state_e state;
  state_e next_state;

  logic cmd_done;

  always_comb
    case (state)
      ST_INIT:
        next_state = p0_cmd_vld ? ST_PROC : state;
      ST_PROC:
        next_state = cmd_done ? ST_INIT : state;
    endcase

  logic st_init;
  logic st_proc;

  assign st_init = state == ST_INIT;
  assign st_proc = state == ST_PROC;

  always_ff @(posedge clk)
    if (!s_rst_n) state <= ST_INIT;
    else state          <= next_state;

  // == Process
  logic [PID_W-1:0] p0_pbs_id;
  logic [PID_W-1:0] p0_pbs_idD;
  logic             p0_last_pbs_id;
  logic [PID_W-1:0] p0_pbs_id_max;
  logic [PID_W-1:0] p0_pbs_id_maxD;
  logic [OP_W-1:0]  p0_datar;

  logic p0_do_read;

  assign p0_pbs_id_maxD = st_init ? p0_cmd.wp[PID_W-1:0] == '0 ? TOTAL_PBS_NB-1 : p0_cmd.wp[PID_W-1:0]-1 :
                                    p0_pbs_id_max;
  assign p0_pbs_idD     = st_init    ? p0_cmd.rp[PID_W-1:0] :
                          p0_do_read ? p0_pbs_id == TOTAL_PBS_NB-1 ? 0 : p0_pbs_id + 1 : p0_pbs_id;
  assign p0_last_pbs_id = p0_pbs_id == p0_pbs_id_max;

  assign p0_datar       = body_map[p0_pbs_id];

  always_ff @(posedge clk) begin
    p0_pbs_id_max <= p0_pbs_id_maxD;
    p0_pbs_id     <= p0_pbs_idD;
  end

// ============================================================================================= --
// Output FIFO
// ============================================================================================= --
  logic [OP_W-1:0]  bfifo_in_data;
  logic [PID_W-1:0] bfifo_in_pid;
  logic             bfifo_in_vld;
  logic             bfifo_in_rdy;

  logic [OP_W-1:0]  bfifo_out_data;
  logic [PID_W-1:0] bfifo_out_pid;
  logic             bfifo_out_vld;
  logic             bfifo_out_rdy;

  assign bfifo_in_data = p0_datar;
  assign bfifo_in_pid  = p0_pbs_id;
  assign bfifo_in_vld  = st_proc;

  fifo_reg #(
    .WIDTH       (OP_W+PID_W),
    .DEPTH       (OUT_FIFO_DEPTH),
    .LAT_PIPE_MH ({1'b1, 1'b1})
  ) body_fifo (
    .clk      (clk),
    .s_rst_n  (s_rst_n),

    .in_data  ({bfifo_in_pid, bfifo_in_data}),
    .in_vld   (bfifo_in_vld),
    .in_rdy   (bfifo_in_rdy),

    .out_data ({bfifo_out_pid, bfifo_out_data}),
    .out_vld  (bfifo_out_vld),
    .out_rdy  (bfifo_out_rdy)
  );

  assign bmap_outp_data = bfifo_out_data;
  assign bmap_outp_pid  = bfifo_out_pid;
  assign bmap_outp_vld  = bfifo_out_vld;
  assign bfifo_out_rdy  = bmap_outp_rdy;

// ============================================================================================= --
// Control
// ============================================================================================= --
  assign p0_do_read = st_proc & bfifo_in_rdy;
  assign cmd_done   = p0_do_read & p0_last_pbs_id;
  assign p0_cmd_rdy = p0_do_read & p0_last_pbs_id;

endmodule
