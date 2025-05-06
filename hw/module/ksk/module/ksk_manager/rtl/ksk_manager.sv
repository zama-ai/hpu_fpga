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
// ==============================================================================================

module ksk_manager
  import param_tfhe_pkg::*;
  import top_common_param_pkg::*;
  import pep_ks_common_param_pkg::*;
  import ksk_mgr_common_param_pkg::*;
  import pep_common_param_pkg::*;
#(
  parameter  int RAM_LATENCY   = 1+2 // URAM
)
(
  input  logic                                                                clk,        // clock
  input  logic                                                                s_rst_n,    // synchronous reset

  input  logic                                                                reset_cache,

  output logic [LBX-1:0][LBY-1:0][LBZ-1:0][MOD_KSK_W-1:0]                     ksk,
  output logic [LBX-1:0][LBY-1:0]                                             ksk_vld,
  input  logic [LBX-1:0][LBY-1:0]                                             ksk_rdy,

  // Broadcast from key switch
  input  logic [KS_BATCH_CMD_W-1:0]                                           batch_cmd,
  input  logic                                                                batch_cmd_avail, // pulse

  // Write interface
  input  logic [KSK_CUT_NB-1:0]                                               wr_en, // Write coefficients for 1 (stage iter,GLWE) at a time.
  input  logic [KSK_CUT_NB-1:0][KSK_CUT_FCOEF_NB-1:0][LBZ-1:0][MOD_KSK_W-1:0] wr_data,
  input  logic [KSK_CUT_NB-1:0][KSK_RAM_ADD_W-1:0]                            wr_add, // take the slot_id into account
  input  logic [KSK_CUT_NB-1:0][LBX_W-1:0]                                    wr_x_idx,
  input  logic [KSK_CUT_NB-1:0][KSK_SLOT_W-1:0]                               wr_slot,
  input  logic [KSK_CUT_NB-1:0][KS_BLOCK_COL_W-1:0]                           wr_ks_loop,

  // Error
  output pep_ksk_error_t                                                      error

);

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int CMD_FIFO_DEPTH = TOTAL_BATCH_NB;
  localparam int RAM_LATENCY_L  = RAM_LATENCY + 1; // +1 to register read command
  localparam int BUF_DEPTH      = RAM_LATENCY_L + 2;
  localparam int LOC_NB         = RAM_LATENCY_L + BUF_DEPTH;
  localparam int LOC_W          = $clog2(LOC_NB);
  localparam int URAM_W         = 72; // ultraRAM width
  localparam int RAM_W          = MOD_KSK_W * LBZ;
  localparam int RAM_NB         = LBX*LBY;

// ============================================================================================== --
// ksk_manager
// ============================================================================================== --
// ---------------------------------------------------------------------------------------------- --
// Input pipe
// ---------------------------------------------------------------------------------------------- --
  ks_batch_cmd_t                                          sm1_batch_cmd;
  logic                                                   sm1_batch_cmd_avail;
  logic [KSK_CUT_NB-1:0]                                  sm1_wr_en;
  logic [KSK_CUT_NB-1:0][KSK_SLOT_W-1:0]                  sm1_wr_slot;
  logic [KSK_CUT_NB-1:0][KS_BLOCK_COL_W-1:0]              sm1_wr_ks_loop;
  logic [LBY-1:0][LBZ-1:0][MOD_KSK_W-1:0]                 sm1_wr_data;
  logic [KSK_CUT_NB-1:0][KSK_RAM_ADD_W-1:0]               sm1_wr_add;
  logic [KSK_CUT_NB-1:0][LBX_W-1:0]                       sm1_wr_x_idx;

  logic                                                   do_reset;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      sm1_batch_cmd_avail <= 1'b0;
      sm1_wr_en           <= '0;
      do_reset            <= 1'b0;
    end
    else begin
      sm1_batch_cmd_avail <= batch_cmd_avail;
      sm1_wr_en           <= wr_en;
      do_reset            <= reset_cache;
    end

  always_ff @(posedge clk) begin
    sm1_batch_cmd  <= batch_cmd;
    sm1_wr_slot    <= wr_slot;
    sm1_wr_ks_loop <= wr_ks_loop;
    sm1_wr_data    <= wr_data;
    sm1_wr_add     <= wr_add;
    sm1_wr_x_idx   <= wr_x_idx;
  end

// ---------------------------------------------------------------------------------------------- --
// Sm1 : Search slot
// ---------------------------------------------------------------------------------------------- --
  logic [KSK_SLOT_NB-1:0][KS_BLOCK_COL_W-1:0] slot_ks_loop_a;
  logic [KSK_SLOT_NB-1:0][KS_BLOCK_COL_W-1:0] slot_ks_loop_aD;

  // Use an avail bit to avoid initial false positive, since the slot_ks_loop_a has 'x values after reset.
  logic [KSK_SLOT_NB-1:0] slot_avail_a;
  logic [KSK_SLOT_NB-1:0] slot_avail_aD;

  logic [KSK_SLOT_NB-1:0] sm1_wr_slot_1h_0;

  always_comb
    for (int i=0; i<KSK_SLOT_NB; i=i+1)
      sm1_wr_slot_1h_0[i] = (sm1_wr_slot[0] == i) ? 1'b1 : 1'b0;

  always_comb
    for (int i=0; i<KSK_SLOT_NB; i=i+1) begin
        slot_ks_loop_aD[i] = (sm1_wr_en[0] && sm1_wr_slot_1h_0[i]) ? sm1_wr_ks_loop[0] : slot_ks_loop_a[i];
        slot_avail_aD[i]   = (sm1_wr_en[0] & sm1_wr_slot_1h_0[i]) | slot_avail_a[i];
    end

  always_ff @(posedge clk)
    if (!s_rst_n || do_reset) slot_avail_a <= '0;
    else                      slot_avail_a <= slot_avail_aD;

  always_ff @(posedge clk)
    slot_ks_loop_a <= slot_ks_loop_aD;

  logic [KSK_SLOT_NB-1:0] sm1_slot_1h;
  logic [KSK_SLOT_W-1:0]  sm1_slot;

  always_comb
    for (int i=0; i<KSK_SLOT_NB; i=i+1)
      sm1_slot_1h[i] = (sm1_batch_cmd.ks_loop == slot_ks_loop_a[i]) & slot_avail_a[i];

  common_lib_one_hot_to_bin #(
    .ONE_HOT_W(KSK_SLOT_NB)
  ) common_lib_one_hot_to_bin (
    .in_1h     (sm1_slot_1h),
    .out_value (sm1_slot)
  );

  ks_batch_cmd_t      sm2_batch_cmd;
  logic               sm2_batch_cmd_avail;
  logic [KSK_SLOT_W-1:0]  sm2_slot;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      sm2_batch_cmd_avail <= 1'b0;
    end
    else begin
      sm2_batch_cmd_avail <= sm1_batch_cmd_avail;
    end

  always_ff @(posedge clk) begin
    sm2_batch_cmd  <= sm1_batch_cmd;
    sm2_slot       <= sm1_slot;
  end

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      if (sm1_batch_cmd_avail) begin
        assert($countones(sm1_slot_1h) == 1)
        else begin
          $fatal(1,"%t > ERROR: batch_cmd does not match a unique slot! (sm1_slot_1h=0x%x)", $time, sm1_slot_1h);
        end
      end
    end
// pragma translate_on


// ---------------------------------------------------------------------------------------------- --
// batch_cmd FIFO
// ---------------------------------------------------------------------------------------------- --
// Use a small FIFO to store the commands that have to be processed.
// Note that this FIFO does not need to be very deep, it depends on the number of batches that can
// be processed in parallel.
  ks_batch_cmd_t            s0_batch_cmd;
  logic [KSK_RAM_ADD_W-1:0] s0_batch_add_ofs;
  logic                     s0_batch_cmd_vld;
  logic                     s0_batch_cmd_rdy;

  logic                     sm2_batch_cmd_rdy;
  logic [KSK_RAM_ADD_W-1:0] sm2_batch_add_ofs;

  assign sm2_batch_add_ofs = sm2_slot * KSK_SLOT_DEPTH;

  fifo_reg #(
    .WIDTH       (KS_BATCH_CMD_W + KSK_RAM_ADD_W),
    .DEPTH       (CMD_FIFO_DEPTH-1),
    .LAT_PIPE_MH ({1'b1, 1'b1})
  ) cmd_fifo(
    .clk     (clk),
    .s_rst_n (s_rst_n),

    .in_data ({sm2_batch_add_ofs, sm2_batch_cmd}),
    .in_vld  (sm2_batch_cmd_avail),
    .in_rdy  (sm2_batch_cmd_rdy),

    .out_data({s0_batch_add_ofs,s0_batch_cmd}),
    .out_vld (s0_batch_cmd_vld),
    .out_rdy (s0_batch_cmd_rdy)
  );

// ---------------------------------------------------------------------------------------------- --
// Systolic array [0][0]
// ---------------------------------------------------------------------------------------------- --
// Share the same control for all the nodes.
// The control is built for the node [0][0], then it is pipelined to the other nodes.
  // ----------------------------------------------------------------------------------- --
  // batch_cmd FIFO
  // ----------------------------------------------------------------------------------- --
  ks_batch_cmd_t            s1_batch_cmd;
  logic [KSK_RAM_ADD_W-1:0] s1_batch_add_ofs;
  logic                     s1_batch_cmd_vld;
  logic                     s1_batch_cmd_rdy;

  assign s1_batch_cmd     = s0_batch_cmd;;
  assign s1_batch_add_ofs = s0_batch_add_ofs;;
  assign s1_batch_cmd_vld = s0_batch_cmd_vld;;
  assign s0_batch_cmd_rdy = s1_batch_cmd_rdy;;


  // ---------------------------------------------------------------------------------------------- --
  // Counters
  // ---------------------------------------------------------------------------------------------- --
  logic [KS_BLOCK_LINE_W-1:0] s1_bline;
  logic [KS_BLOCK_LINE_W-1:0] s1_blineD;
  logic [BPBS_ID_W-1:0]       s1_pbs_id;
  logic [BPBS_ID_W-1:0]       s1_pbs_idD;
  logic [KS_LG_W-1:0]         s1_lg;
  logic [KS_LG_W-1:0]         s1_lgD;
  logic                       s1_first_bline;
  logic                       s1_first_lg;
  logic                       s1_first_pbs_id;
  logic                       s1_last_bline;
  logic                       s1_last_lg;
  logic                       s1_last_pbs_id;
  logic                       s1_do_read;

  assign s1_lgD     = s1_do_read ? s1_last_lg ? '0 : s1_lg + 1 : s1_lg;
  assign s1_pbs_idD = (s1_do_read && s1_last_lg)?
                            s1_last_pbs_id ? '0 : s1_pbs_id + 1 : s1_pbs_id;
  assign s1_blineD  = (s1_do_read && s1_last_lg && s1_last_pbs_id) ?
                             s1_last_bline ? '0 : s1_bline + 1 : s1_bline;

  assign s1_first_lg     = (s1_lg == '0);
  assign s1_first_bline  = (s1_bline == '0);
  assign s1_first_pbs_id = (s1_pbs_id == '0);
  assign s1_last_lg      = (s1_lg == (KS_LG_NB-1));
  assign s1_last_bline   = (s1_bline == (KS_BLOCK_LINE_NB-1));
  assign s1_last_pbs_id  = (s1_pbs_id == (s1_batch_cmd.pbs_nb -1));

  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      s1_lg     <= '0;
      s1_bline  <= '0;
      s1_pbs_id <= '0;
    end
    else begin
      s1_lg     <= s1_lgD;
      s1_bline  <= s1_blineD;
      s1_pbs_id <= s1_pbs_idD;
    end
  end

  assign s1_batch_cmd_rdy = s1_do_read & s1_last_lg & s1_last_bline & s1_last_pbs_id;

  // ---------------------------------------------------------------------------------------------- --
  // Read pointer within the slot
  // ---------------------------------------------------------------------------------------------- --
  logic [KSK_RAM_ADD_W-1:0] s1_rp;
  logic [KSK_RAM_ADD_W-1:0] s1_rpD;

  assign s1_rpD = !s1_do_read ? s1_rp :
                  (s1_last_lg && s1_last_pbs_id && s1_last_bline) ? '0 : // last read of the slot
                  (!s1_last_lg || s1_last_pbs_id) ? s1_rp + 1 :
                  s1_rp - (KS_LG_NB-1); // wrap for the next pbs

  always_ff @(posedge clk)
    if (!s_rst_n) s1_rp <= '0;
    else          s1_rp <= s1_rpD;

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
  // Read in RAM when there is a free location in the output buffer.
  logic [RAM_LATENCY_L-1:0] ram_data_avail_dly;
  logic [RAM_LATENCY_L-1:0] ram_data_avail_dlyD;
  logic [LOC_W-1:0]         s1_data_cnt;
  logic [LOC_NB-1:0]        s1_data_en;
  logic [RAM_W-1:0]         ram_rd_data;

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
    s1_data_cnt = cnt;
  end

  assign s1_do_read = (s1_data_cnt < BUF_DEPTH) & s1_batch_cmd_vld;

  // Buffer input
  assign buf_in_avail = ram_data_avail_dly[RAM_LATENCY_L-1];
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

  assign ram_rd_addD = s1_rp + s1_batch_add_ofs;
  assign ram_rd_enD  = s1_do_read;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      ram_wr_en <= 1'b0;
      ram_rd_en <= 1'b0;
    end
    else begin
      ram_wr_en <= sm1_wr_en[0] & (sm1_wr_x_idx[0] == 0);
      ram_rd_en <= ram_rd_enD;
    end

  always_ff @(posedge clk) begin
    ram_wr_data <= sm1_wr_data[0];
    ram_wr_add  <= sm1_wr_add[0];
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
  ) ksk_ram
  (
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
  assign ksk[0][0]     = buf_data[0];
  assign ksk_vld[0][0] = buf_en[0];
  assign buf_shift     = ksk_rdy[0][0] & ksk_vld[0][0];

  // ----------------------------------------------------------------------------------- --
  // node command
  // ----------------------------------------------------------------------------------- --
  node_cmd_t [LBX-1:0][LBY-1:0] node_cmd_a;
  node_cmd_t [LBX-1:0][LBY-1:0] next_x_node_cmd_a;
  node_cmd_t [LBX-1:0][LBY-1:0] next_y_node_cmd_a;
  node_cmd_t next_y_node_cmd_a_0_0;
  node_cmd_t next_x_node_cmd_a_0_0;

  assign next_x_node_cmd_a[0][0] = next_x_node_cmd_a_0_0;
  assign next_y_node_cmd_a[0][0] = next_y_node_cmd_a_0_0;

  always_comb begin
    node_cmd_a[0][0].buf_in_avail = buf_in_avail;
    node_cmd_a[0][0].buf_shift    = buf_shift;
    node_cmd_a[0][0].ram_rd_enD   = ram_rd_enD ;
    node_cmd_a[0][0].ram_rd_addD  = ram_rd_addD;

    node_cmd_a[0][LBY-1:1] = next_y_node_cmd_a[0][LBY-2:0];

    for (int x=1; x<LBX; x=x+1)
      node_cmd_a[x] = next_x_node_cmd_a[x-1];
  end

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      next_y_node_cmd_a_0_0 <= '0;
      next_x_node_cmd_a_0_0 <= '0;
    end
    else begin
      next_y_node_cmd_a_0_0 <= node_cmd_a[0][0];
      next_x_node_cmd_a_0_0 <= node_cmd_a[0][0];
    end

// ---------------------------------------------------------------------------------------------- --
// Node array
// ---------------------------------------------------------------------------------------------- --
  logic [LBX:0][LBY-1:0]                         node_wr_en;
  logic [LBX:0][LBY-1:0][LBZ-1:0][MOD_KSK_W-1:0] node_wr_data;
  logic [LBX:0][LBY-1:0][KSK_RAM_ADD_W-1:0]      node_wr_add;
  logic [LBX:0][LBY-1:0][LBX_W-1:0]              node_wr_x_idx;

  logic [LBY-1:0]                                node_wr_en_0;
  logic [LBY-1:0][KSK_RAM_ADD_W-1:0]             node_wr_add_0;
  logic [LBY-1:0][LBX_W-1:0]                     node_wr_x_idx_0;

  logic                                          node_wr_en_1_0;
  logic [LBZ-1:0][MOD_KSK_W-1:0]                 node_wr_data_1_0;
  logic [KSK_RAM_ADD_W-1:0]                      node_wr_add_1_0;
  logic [LBX_W-1:0]                              node_wr_x_idx_1_0;

  always_comb
    for (int i=0; i<KSK_CUT_NB; i=i+1) begin
      node_wr_en_0[i*KSK_CUT_FCOEF_NB+:KSK_CUT_FCOEF_NB]    = {KSK_CUT_FCOEF_NB{sm1_wr_en[i]}};
      node_wr_add_0[i*KSK_CUT_FCOEF_NB+:KSK_CUT_FCOEF_NB]   = {KSK_CUT_FCOEF_NB{sm1_wr_add[i]}};
      node_wr_x_idx_0[i*KSK_CUT_FCOEF_NB+:KSK_CUT_FCOEF_NB] = {KSK_CUT_FCOEF_NB{sm1_wr_x_idx[i]}};
    end

  assign node_wr_en[0]    = node_wr_en_0;
  assign node_wr_data[0]  = sm1_wr_data;
  assign node_wr_add[0]   = node_wr_add_0;
  assign node_wr_x_idx[0] = node_wr_x_idx_0;

  always_ff @(posedge clk)
    if (!s_rst_n) node_wr_en_1_0 <= 1'b0;
    else          node_wr_en_1_0 <= node_wr_en[0][0];

  always_ff @(posedge clk) begin
    node_wr_data_1_0  <= node_wr_data[0][0];
    node_wr_add_1_0   <= node_wr_add[0][0];
    node_wr_x_idx_1_0 <= node_wr_x_idx[0][0];
  end

  assign node_wr_en[1][0]    = node_wr_en_1_0;
  assign node_wr_data[1][0]  = node_wr_data_1_0;
  assign node_wr_add[1][0]   = node_wr_add_1_0;
  assign node_wr_x_idx[1][0] = node_wr_x_idx_1_0;

  generate
    for (genvar gen_r=1; gen_r < RAM_NB; gen_r=gen_r+1) begin : gen_loop_node
      localparam int X_ID = gen_r / LBY;
      localparam int Y_ID = gen_r % LBY;
      ksk_mgr_node
      #(
        .X_ID           (X_ID),
        .Y_ID           (Y_ID),
        .RAM_LATENCY    (RAM_LATENCY)
      ) ksk_mgr_node (
        .clk             (clk),
        .s_rst_n         (s_rst_n),

        .ksk             (ksk[X_ID][Y_ID]),
        .ksk_vld         (ksk_vld[X_ID][Y_ID]),
        .ksk_rdy         (ksk_rdy[X_ID][Y_ID]),

        .prev_node_cmd   (node_cmd_a[X_ID][Y_ID]),
        .next_x_node_cmd (next_x_node_cmd_a[X_ID][Y_ID]),
        .next_y_node_cmd (next_y_node_cmd_a[X_ID][Y_ID]),

        .prev_wr_en      (node_wr_en[X_ID][Y_ID]),
        .prev_wr_data    (node_wr_data[X_ID][Y_ID]),
        .prev_wr_add     (node_wr_add[X_ID][Y_ID]),
        .prev_wr_x_idx   (node_wr_x_idx[X_ID][Y_ID]),

        .next_x_wr_en    (node_wr_en[X_ID+1][Y_ID]),
        .next_x_wr_data  (node_wr_data[X_ID+1][Y_ID]),
        .next_x_wr_add   (node_wr_add[X_ID+1][Y_ID]),
        .next_x_wr_x_idx (node_wr_x_idx[X_ID+1][Y_ID])
      );

    end
  endgenerate

// ---------------------------------------------------------------------------------------------- --
// Errors
// ---------------------------------------------------------------------------------------------- --
  // The FIFO should always be ready for an input command.
  logic error_cmd_overflow;
  logic error_cmd_overflowD;

  assign error_cmd_overflowD  = sm2_batch_cmd_avail & ~sm2_batch_cmd_rdy;
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      error_cmd_overflow  <= 1'b0;
    end
    else begin
      error_cmd_overflow  <= error_cmd_overflowD;
    end

  assign error = {error_cmd_overflow};
endmodule
