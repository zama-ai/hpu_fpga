// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the management of the blind rotation key (bsk).
// It delivers the keys at the pace given by the core.
// The host fills the values. They should be valid before running the blind rotation.
// Note that the keys should be given in reverse order on N basis.
// Also note that a unique bsk is used for the process.
// Xilinx UltraRAM are used : (72x4096) RAMs.
//
// This module is 1 node inside the systolic array. It deals with 1 coef.
// ==============================================================================================

module bsk_mgr_node
  import param_tfhe_pkg::*;
  import top_common_param_pkg::*;
  import bsk_mgr_common_param_pkg::*;
#(
  parameter  int OP_W          = 64,
  parameter  int RAM_RD_NB     = 1,
  parameter  int G_ID          = 1, // G Position in the systolic array.
  parameter  int RAM_LATENCY   = 1+2,
  parameter  int BUF_DEPTH     = RAM_LATENCY + 1 + 2
)
(
  input  logic                           clk,        // clock
  input  logic                           s_rst_n,    // synchronous reset

  output logic [RAM_RD_NB-1:0][OP_W-1:0] bsk,
  output logic [RAM_RD_NB-1:0]           bsk_vld,
  input  logic [RAM_RD_NB-1:0]           bsk_rdy,

  // Command from / to neighbour
  input  logic [NODE_CMD_W-1:0]          prev_node_cmd,
  output logic [NODE_CMD_W-1:0]          next_x_node_cmd,

  // Write interface
  input  logic                           prev_wr_en, // Write coefficients for 1 (stage iter,GLWE) at a time.
  input  logic [RAM_RD_NB-1:0][OP_W-1:0] prev_wr_data,
  input  logic [BSK_RAM_ADD_W-1:0]       prev_wr_add, // take the slot_id into account
  input  logic [GLWE_K_P1_W-1:0]         prev_wr_g_idx,

  output logic                           next_x_wr_en, // Write coefficients for 1 (stage iter,GLWE) at a time.
  output logic [RAM_RD_NB-1:0][OP_W-1:0] next_x_wr_data,
  output logic [BSK_RAM_ADD_W-1:0]       next_x_wr_add, // take the slot_id into account
  output logic [GLWE_K_P1_W-1:0]         next_x_wr_g_idx,

  output logic [BUF_DEPTH-1:0]           buf_en // for the control
);

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int RAM_W          = RAM_RD_NB*OP_W;

// ============================================================================================== --
// To next node
// ============================================================================================== --
  // Duplicate node_cmd to ease P&R
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      next_x_node_cmd <= '0;
      next_x_wr_en    <= 1'b0;
    end
    else begin
      next_x_node_cmd <= prev_node_cmd;
      next_x_wr_en    <= prev_wr_en;
    end

  // Write command
  always_ff @(posedge clk) begin
    next_x_wr_data  <= prev_wr_data ;
    next_x_wr_add   <= prev_wr_add  ;
    next_x_wr_g_idx <= prev_wr_g_idx;
  end

// ============================================================================================== --
// bsk_node_mgr
// ============================================================================================== --
  node_cmd_t node_cmd;
  logic                           wr_en; // Write coefficients for 1 (stage iter,GLWE) at a time.
  logic [RAM_RD_NB-1:0][OP_W-1:0] wr_data;
  logic [BSK_RAM_ADD_W-1:0]       wr_add; // take the slot_id into account
  logic [GLWE_K_P1_W-1:0]         wr_g_idx;

  assign node_cmd = prev_node_cmd;
  assign wr_en    = prev_wr_en   ;
  assign wr_data  = prev_wr_data ;
  assign wr_add   = prev_wr_add  ;
  assign wr_g_idx = prev_wr_g_idx;

  // ----------------------------------------------------------------------------------- --
  // Output buffer
  // ----------------------------------------------------------------------------------- --
  // To ease the P&R, the out_data comes from a register.
  // We need additional RAM_LATENCY_L registers to absorb the RAM read latency.
  // Note we don't need short latency here. We have some cycles to fill the output pipe.
  logic [BUF_DEPTH-1:0][RAM_W-1:0] buf_data;
  logic [BUF_DEPTH:0]  [RAM_W-1:0] buf_data_ext;
  logic [BUF_DEPTH-1:0][RAM_W-1:0] buf_dataD;
  logic [BUF_DEPTH-1:0]            buf_enD;
  logic [BUF_DEPTH:0]              buf_en_ext;
  logic                            buf_in_avail;
  logic [RAM_W-1:0]                buf_in_data;
  logic [BUF_DEPTH-1:0]            buf_in_wren_1h;
  logic [BUF_DEPTH-1:0]            buf_in_wren_1h_tmp;
  logic [BUF_DEPTH-1:0]            buf_in_wren_1h_tmp2;
  logic                            buf_shift;

  assign buf_in_avail = node_cmd.buf_in_avail;
  assign buf_shift    = bsk_rdy[0] & bsk_vld[0];

  // Add 1 element to avoid warning, while selecting out of range.
  always_comb begin
    buf_data_ext = {{RAM_W{1'bx}}, buf_data};
  end
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
        else $fatal(1, "> ERROR: FIFO output buffer overflow!");
      end
    end
// pragma translate_on

  // ---------------------------------------------------------------------------------------------- --
  // Read
  // ---------------------------------------------------------------------------------------------- --
  logic [RAM_W-1:0] ram_rd_data;
  assign buf_in_data  = ram_rd_data;

  // ---------------------------------------------------------------------------------------------- --
  // RAM control
  // ---------------------------------------------------------------------------------------------- --
  logic                     ram_rd_en;
  logic                     ram_rd_enD;
  logic                     ram_wr_en;
  logic [BSK_RAM_ADD_W-1:0] ram_rd_add;
  logic [BSK_RAM_ADD_W-1:0] ram_rd_addD;
  logic [BSK_RAM_ADD_W-1:0] ram_wr_add;
  logic [RAM_W-1:0]         ram_wr_data;

  assign ram_rd_addD = node_cmd.ram_rd_addD;
  assign ram_rd_enD  = node_cmd.ram_rd_enD;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      ram_wr_en <= 1'b0;
      ram_rd_en <= 1'b0;
    end
    else begin
      ram_wr_en <= wr_en & (wr_g_idx == G_ID);
      ram_rd_en <= ram_rd_enD;
    end

  always_ff @(posedge clk) begin
    ram_wr_data <= wr_data;
    ram_wr_add  <= wr_add;
    ram_rd_add  <= ram_rd_addD;
  end

  // ----------------------------------------------------------------------------------- --
  // RAMs
  // ----------------------------------------------------------------------------------- --
  ram_wrapper_1R1W #(
    .WIDTH             (RAM_W),
    .DEPTH             (BSK_RAM_DEPTH),
    .RD_WR_ACCESS_TYPE (1),
    .KEEP_RD_DATA      (0),
    .RAM_LATENCY       (RAM_LATENCY)
  ) bsk_ram (
    .clk       (clk),
    .s_rst_n   (s_rst_n),

    .rd_en     (ram_rd_en),
    .rd_add    (ram_rd_add),
    .rd_data   (ram_rd_data),

    .wr_en     (ram_wr_en),
    .wr_add    (ram_wr_add),
    .wr_data   (ram_wr_data)
  );

  // ----------------------------------------------------------------------------------- --
  // Output [0][0]
  // ----------------------------------------------------------------------------------- --
  assign bsk     = buf_data[0];
  assign bsk_vld = {RAM_RD_NB{buf_en[0]}};

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      assert(bsk_rdy == '0 || bsk_rdy == '1)
      else begin
        $fatal(1,"%t > ERROR: bsk_rdy signal is not coherent", $time);
      end
    end
// pragma translate_on

endmodule
