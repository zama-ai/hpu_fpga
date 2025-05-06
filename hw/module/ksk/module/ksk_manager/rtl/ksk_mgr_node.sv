// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the management of the key switching key (ksk).
// It delivers the keys at the pace given by the core.
// The host fills the values. They should be valid before running the key_switch.
// Note that the keys should be given in reverse order in the BLWE_K dimension, on N basis.
// Also note that a unique ksk is used for the process.
// Xilinx UltraRAM are used (72x4096) RAMs.
//
// This module is 1 node inside the systolic array. It deals with 1 [LBZ-1:0] coef.
// ==============================================================================================

module ksk_mgr_node
  import param_tfhe_pkg::*;
  import top_common_param_pkg::*;
  import pep_ks_common_param_pkg::*;
  import ksk_mgr_common_param_pkg::*;
#(
  parameter  int X_ID          = 1, // X Position in the systolic array. Should be > 0
  parameter  int Y_ID          = 1, // Y Position in the systolic array. Should be > 0
  parameter  int RAM_LATENCY   = 1+2 // URAM
)
(
  input  logic                          clk,        // clock
  input  logic                          s_rst_n,    // synchronous reset

  output logic [LBZ-1:0][MOD_KSK_W-1:0] ksk,
  output logic                          ksk_vld,
  input  logic                          ksk_rdy,

  // Command from / to neighbour
  input  logic [NODE_CMD_W-1:0]         prev_node_cmd,
  output logic [NODE_CMD_W-1:0]         next_x_node_cmd,
  output logic [NODE_CMD_W-1:0]         next_y_node_cmd,

  // Write interface
  input  logic                          prev_wr_en, // Write coefficients for 1 (stage iter,GLWE) at a time.
  input  logic [LBZ-1:0][MOD_KSK_W-1:0] prev_wr_data,
  input  logic [KSK_RAM_ADD_W-1:0]      prev_wr_add, // take the slot_id into account
  input  logic [LBX_W-1:0]              prev_wr_x_idx,

  output logic                          next_x_wr_en, // Write coefficients for 1 (stage iter,GLWE) at a time.
  output logic [LBZ-1:0][MOD_KSK_W-1:0] next_x_wr_data,
  output logic [KSK_RAM_ADD_W-1:0]      next_x_wr_add, // take the slot_id into account
  output logic [LBX_W-1:0]              next_x_wr_x_idx
);

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int RAM_LATENCY_L  = RAM_LATENCY + 1; // +1 to register read command
  localparam int BUF_DEPTH      = RAM_LATENCY_L + 2;
  localparam int RAM_W          = MOD_KSK_W * LBZ;

// ============================================================================================== --
// To next node
// ============================================================================================== --
  // Duplicate node_cmd to ease P&R
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      next_x_node_cmd <= '0;
      next_y_node_cmd <= '0;
      next_x_wr_en    <= 1'b0;
    end
    else begin
      next_x_node_cmd <= prev_node_cmd;
      next_y_node_cmd <= prev_node_cmd;
      next_x_wr_en    <= prev_wr_en;
    end

  // Write command
  always_ff @(posedge clk) begin
    next_x_wr_data  <= prev_wr_data ;
    next_x_wr_add   <= prev_wr_add  ;
    next_x_wr_x_idx <= prev_wr_x_idx;
  end

// ============================================================================================== --
// bsk_node_mgr
// ============================================================================================== --
  node_cmd_t node_cmd;
  logic                          wr_en; // Write coefficients for 1 (stage iter,GLWE) at a time.
  logic [LBZ-1:0][MOD_KSK_W-1:0] wr_data;
  logic [KSK_RAM_ADD_W-1:0]      wr_add; // take the slot_id into account
  logic [LBX_W-1:0]              wr_x_idx;

  assign node_cmd = prev_node_cmd;
  assign wr_en    = prev_wr_en   ;
  assign wr_data  = prev_wr_data ;
  assign wr_add   = prev_wr_add  ;
  assign wr_x_idx = prev_wr_x_idx;

  // ----------------------------------------------------------------------------------- --
  // Output buffer
  // ----------------------------------------------------------------------------------- --
  // To ease the P&R, the out_data comes from a register.
  // We need additional RAM_LATENCY_L registers to absorb the RAM read latency.
  // Note we don't need short latency here. We have some cycles to fill the output pipe.
  logic [BUF_DEPTH-1:0][RAM_W-1:0] buf_data;
  logic [BUF_DEPTH:0]  [RAM_W-1:0] buf_data_ext;
  logic [BUF_DEPTH-1:0][RAM_W-1:0] buf_dataD;
  logic [BUF_DEPTH-1:0]            buf_en;
  logic [BUF_DEPTH-1:0]            buf_enD;
  logic [BUF_DEPTH:0]              buf_en_ext;
  logic                            buf_in_avail;
  logic [RAM_W-1:0]                buf_in_data;
  logic [BUF_DEPTH-1:0]            buf_in_wren_1h;
  logic [BUF_DEPTH-1:0]            buf_in_wren_1h_tmp;
  logic [BUF_DEPTH-1:0]            buf_in_wren_1h_tmp2;
  logic                            buf_shift;

  assign buf_in_avail = node_cmd.buf_in_avail;
  assign buf_shift    = node_cmd.buf_shift;

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
  logic [KSK_RAM_ADD_W-1:0] ram_rd_add;
  logic [KSK_RAM_ADD_W-1:0] ram_rd_addD;
  logic [KSK_RAM_ADD_W-1:0] ram_wr_add;
  logic [RAM_W-1:0]         ram_wr_data;

  assign ram_rd_addD = node_cmd.ram_rd_addD;
  assign ram_rd_enD  = node_cmd.ram_rd_enD;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      ram_wr_en <= 1'b0;
      ram_rd_en <= 1'b0;
    end
    else begin
      ram_wr_en <= wr_en & (wr_x_idx == X_ID);
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
    .DEPTH             (KSK_RAM_DEPTH),
    .RD_WR_ACCESS_TYPE (1),
    .KEEP_RD_DATA      (0),
    .RAM_LATENCY       (RAM_LATENCY)
  ) ksk_ram (
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
  assign ksk     = buf_data[0];
  assign ksk_vld = buf_en[0];

// pragma translate_off
  logic _buf_shift;
  assign _buf_shift = ksk_rdy & ksk_vld;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      assert(_buf_shift == buf_shift)
      else begin
        $fatal(1,"%t > ERROR: buf_shift signal does not match between local and node_cmd!", $time);
      end
    end
// pragma translate_on

endmodule
