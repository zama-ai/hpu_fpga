// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Module for debugging and tracing
// ----------------------------------------------------------------------------------------------
// Enables to read and write from a specific, previously defined lane.
// ==============================================================================================

module debug_lane #(
  parameter int AXIS_TDATA_W  = 64,
  parameter int AXIS_TKEEP_W  = 11,

  parameter int FIFO_DEPTH = 512,
  parameter int NB_WORD_W = $clog2(FIFO_DEPTH)+1,

  parameter int SIM_ASSERT_CHK = 0
) (
  // system interface ---------------------------------------------------------
  input logic clk_control,
  input logic s_rstn_control,
  input logic clk_mrmac,
  input logic s_rstn_mrmac,

  // axi4-stream from RX selected line ----------------------------------------
  input  logic [AXIS_TDATA_W-1:0] qsfp_rx_tdata,
  input  logic [AXIS_TKEEP_W-1:0] qsfp_rx_tkeep_user,
  input  logic                    qsfp_rx_tlast,
  input  logic                    qsfp_rx_tvalid,
  // axi4-stream from TX selected line ----------------------------------------
  output logic [AXIS_TDATA_W-1:0] qsfp_tx_tdata,
  output logic [AXIS_TKEEP_W-1:0] qsfp_tx_tkeep_user,
  output logic                    qsfp_tx_tlast,
  output logic                    qsfp_tx_tvalid,
  input  logic                    qsfp_tx_tready,

  // to/from register interface -----------------------------------------------
  input  logic [NB_WORD_W-1:0]    r_nb_word,
  input  logic [AXIS_TDATA_W-1:0] r_wr_word,
  output logic [NB_WORD_W-1:0]    r_wr_data_count,
  output logic [NB_WORD_W-1:0]    r_rd_data_count,
  output logic [AXIS_TDATA_W-1:0] r_rd_word,
  input  logic                    read_ack,
  input  logic                    write_ack,

  input logic                     tx_loop,
  input logic                     rx_to_tx,

  input logic                     reset_registers,
  // statistics ---------------------------------------------------------------
  output logic [63:0]             clk_cnt_out,
  output logic [63:0]             valid_words_out,
  output logic [31:0]             trigger_rd_cnt_out,
  output logic [31:0]             tx_wr_en_cnt,
  output logic [63:0]             sop_cnt_out,

  output logic                    stat_tx_empty,
  output logic                    stat_tx_rd_rst_busy,
  output logic                    stat_tx_data_valid,
  output logic                    stat_tx_full,
  output logic                    stat_tx_wr_rst_busy,
  output logic                    stat_qsfp_tx_tready,
  output logic [NB_WORD_W-1:0]    stat_rd_data_count
);
  // =========================================================================================== //
  // localparam
  // =========================================================================================== //
  localparam int CDC_SYNC_STAGES = 2;

  // word number is rather stable, changed only once in a while a false path must be set to first reg
  logic [CDC_SYNC_STAGES-1:0] [NB_WORD_W-1:0] nb_word_mrmac;
  logic [CDC_SYNC_STAGES-1:0] reset_registers_cdc;

  always_ff @(posedge clk_mrmac) begin
    nb_word_mrmac[0] <= r_nb_word;
    reset_registers_cdc[0] <= reset_registers;
  end

  generate
    for (genvar gen_i = 1; gen_i < CDC_SYNC_STAGES ; gen_i = gen_i + 1) begin
      always_ff @(posedge clk_mrmac) begin
        nb_word_mrmac[gen_i] <= nb_word_mrmac[gen_i-1];
        reset_registers_cdc[gen_i] <= reset_registers_cdc[gen_i-1];
      end
    end
  endgenerate

  // =========================================================================================== //
  // general control
  // =========================================================================================== //
  // if the two different modes are selected, we choose to apply none
  logic loop;
  logic rx_tx;

  assign loop  = tx_loop & ~rx_to_tx;
  assign rx_tx = ~tx_loop & rx_to_tx;

  // =========================================================================================== //
  // FIFO TX
  // =========================================================================================== //
  // FIFO TX write control ------------------------------------------------------------------------
  logic tx_full;
  logic tx_wr_en;
  logic tx_wr_rst_busy;

  // with this information we can trigger writes in the fifo
  assign tx_wr_en = write_ack && !tx_full && !tx_wr_rst_busy;

  // FIFO TX read control -------------------------------------------------------------------------
  logic [AXIS_TDATA_W-1:0] tx_rd_data;
  logic [NB_WORD_W-1:0]    rd_data_count;
  logic                    tx_rd_en;
  logic tx_data_valid;
  logic tx_empty;
  logic tx_rd_rst_busy;

  // we need to know when to trigger reads, when a full word number is ready in the fifo
  logic trigger_rd;

  always_ff @(posedge clk_mrmac) begin
    if (!s_rstn_mrmac) begin
      trigger_rd <= 1'b0;
    end else begin
      if (rd_data_count == 0) begin
        trigger_rd <= 1'b0;
      end else if (rd_data_count == nb_word_mrmac[CDC_SYNC_STAGES-1]) begin
        trigger_rd <= 1'b1;
      end
    end
  end

  // when we know when to trigger the read, we just need to do it
  assign tx_rd_en = qsfp_tx_tready && trigger_rd && !tx_empty && !tx_rd_rst_busy;

  // FIFO TX
  xpm_fifo_async_wrapper # (
    .CDC_SYNC_STAGES(CDC_SYNC_STAGES),
    .DATA_W(AXIS_TDATA_W),
    .FIFO_DEPTH(FIFO_DEPTH),
    .DATA_COUNT_WIDTH(NB_WORD_W),
    .SIM_ASSERT_CHK(SIM_ASSERT_CHK)
  ) xpm_fifo_tx (
    .sleep        (1'b0),            // to simplify let's not use power saving mode
    .rst          (~s_rstn_control), // must be synchronous to wr reset
    // Write Domain ports
    .wr_clk       (clk_control),
    .wr_en        (tx_wr_en),
    .wr_data      (r_wr_word),
    .full         (tx_full),
    .prog_full    (),
    .wr_data_count(r_wr_data_count),
    .overflow     (),
    .wr_rst_busy  (tx_wr_rst_busy),
    .almost_full  (),
    .wr_ack       (),
    // Read Domain ports
    .rd_clk       (clk_mrmac),
    .rd_en        (tx_rd_en),
    .rd_data      (tx_rd_data),
    .empty        (tx_empty),
    .prog_empty   (),
    .rd_data_count(rd_data_count),
    .underflow    (),
    .rd_rst_busy  (tx_rd_rst_busy),
    .almost_empty (),
    .data_valid   (tx_data_valid),
    // ignoring optional arguments
    .injectsbiterr(1'b0),
    .injectdbiterr(1'b0),
    .sbiterr      (),
    .dbiterr      ()
  );


  // building the axi4-stream tx ------------------------------------------------------------------
  logic [AXIS_TDATA_W-1:0] fifo_tx_tdata;
  logic [AXIS_TKEEP_W-1:0] fifo_tx_tkeep_user;
  logic                    fifo_tx_tlast;
  logic                    fifo_tx_tvalid;

  logic tx_data_valid_d;
  always_ff @(posedge clk_mrmac)
    tx_data_valid_d <= tx_data_valid;

  logic tx_sop;
  logic tx_active_reg;
  logic tx_will_complete_next;

  // pulse on start of transaction: positive edge of tx_data_valid when no words have been consumed
  assign tx_sop = (tx_data_valid & ~tx_data_valid_d) & (rd_data_count==nb_word_mrmac[CDC_SYNC_STAGES-1]);
  assign tx_will_complete_next = fifo_tx_tlast && qsfp_tx_tready && fifo_tx_tvalid;

  // Registered state for memory
  always_ff @(posedge clk_mrmac) begin
      if (~s_rstn_mrmac) begin
          tx_active_reg <= 1'b0;
      end else begin
          tx_active_reg <= fifo_tx_tvalid && !tx_will_complete_next;
      end
  end

  // valid when started and active communication is running
  assign fifo_tx_tvalid    = tx_sop || tx_active_reg;
  assign fifo_tx_tdata     = tx_rd_data;
  assign fifo_tx_tlast     = ((rd_data_count ==  1) && tx_data_valid) ? 1'b1 : 1'b0;
  assign fifo_tx_tkeep_user= fifo_tx_tvalid ? 'hFF : 0; // first 8 bytes are valid

  // ----------------------------------------------------------------------------------------------
  // memory in loopback mode
  // ----------------------------------------------------------------------------------------------
  logic [AXIS_TDATA_W-1:0] mem_tx_tdata;
  logic [AXIS_TKEEP_W-1:0] mem_tx_tkeep_user;
  logic                    mem_tx_tlast;
  logic                    mem_tx_tvalid;
  logic [AXIS_TDATA_W-1:0] memory[63:0];
  logic [5:0]              wr_add;
  logic [5:0]              rd_add;
  logic                    mem_sop;

  always @(posedge clk_mrmac) begin
    if (~s_rstn_mrmac) begin
      wr_add <= 'h0;
    end else begin
      if (loop) begin
        if (fifo_tx_tvalid) begin
          wr_add <= wr_add + 1;
        end
      end else begin
        wr_add <= 'h0;
      end
    end
  end

  always @(posedge clk_mrmac)
      if (loop)
        if (fifo_tx_tvalid)
          memory[wr_add] <= fifo_tx_tdata;

  logic start_mem_pull;
  logic start_mem_pull_d;
  always_ff @(posedge clk_mrmac)
    start_mem_pull_d <= start_mem_pull;

  assign mem_sop = start_mem_pull & ~start_mem_pull_d;

  always_ff @(posedge clk_mrmac) begin
    if (~s_rstn_mrmac) begin
      start_mem_pull <= 1'b0;
    end else begin
      if (loop) begin
        if (fifo_tx_tlast) begin
          start_mem_pull <= 1'b1;
        end
      end else begin
        start_mem_pull <= 1'b0;
      end
    end
  end

  always_ff @(posedge clk_mrmac) begin
    if (~s_rstn_mrmac) begin
      rd_add <= 'h0;
    end else begin
      if (loop) begin
        if (start_mem_pull & qsfp_tx_tready) begin
          rd_add <= rd_add + 1;
        end
      end else begin
        rd_add <= 'h0;
      end
    end
  end

  assign mem_tx_tvalid = start_mem_pull;
  assign mem_tx_tdata = start_mem_pull ? memory[rd_add] : 'h0;
  assign mem_tx_tlast = ((rd_add ==  63) && mem_tx_tvalid) ? 1'b1 : 1'b0;
  assign mem_tx_tkeep_user = mem_tx_tvalid ? 'hFF : 0;

  // ----------------------------------------------------------------------------------------------
  // qsfp tx definition
  // ----------------------------------------------------------------------------------------------
  always_comb begin
    if (~loop & ~rx_to_tx) begin
      qsfp_tx_tvalid     = fifo_tx_tvalid;
      qsfp_tx_tdata      = fifo_tx_tdata;
      qsfp_tx_tlast      = fifo_tx_tlast;
      qsfp_tx_tkeep_user = fifo_tx_tkeep_user;
    end else if (loop) begin
      qsfp_tx_tvalid     = mem_tx_tvalid;
      qsfp_tx_tdata      = mem_tx_tdata;
      qsfp_tx_tlast      = mem_tx_tlast;
      qsfp_tx_tkeep_user = mem_tx_tkeep_user;
    end else if (rx_to_tx) begin
      qsfp_tx_tvalid     = qsfp_rx_tvalid;
      qsfp_tx_tdata      = qsfp_rx_tdata;
      qsfp_tx_tlast      = qsfp_rx_tlast;
      qsfp_tx_tkeep_user = qsfp_rx_tkeep_user;
    end
  end

  // =========================================================================================== //
  // FIFO RX
  // =========================================================================================== //
  logic rx_full;
  logic rx_wr_en;
  logic rx_wr_rst_busy;
  logic rx_empty;
  logic rx_rd_rst_busy;

  // with this information we can trigger writes in the fifo
  assign rx_wr_en = qsfp_rx_tvalid && !rx_full && !rx_wr_rst_busy;

  // RX read word ---------------------------------------------------------------------------------
  logic rx_rd_en;

  assign rx_rd_en = read_ack && !rx_empty && !rx_rd_rst_busy;

  xpm_fifo_async_wrapper # (
    .CDC_SYNC_STAGES(CDC_SYNC_STAGES),
    .DATA_W(AXIS_TDATA_W),
    .FIFO_DEPTH(FIFO_DEPTH),
    .DATA_COUNT_WIDTH(NB_WORD_W),
    .SIM_ASSERT_CHK(SIM_ASSERT_CHK)
  ) xpm_fifo_rx (
    .sleep        (1'b0),         // to simplify let's not use power saving mode
    .rst          (~s_rstn_mrmac), // must be synchronous to wr reset
    // Write Domain ports
    .wr_clk       (clk_mrmac),
    .wr_en        (rx_wr_en),
    .wr_data      (qsfp_rx_tdata),
    .full         (rx_full),
    .prog_full    (),
    .wr_data_count(),
    .overflow     (),
    .wr_rst_busy  (rx_wr_rst_busy),
    .almost_full  (),
    .wr_ack       (),
    // Read Domain ports
    .rd_clk       (clk_control),
    .rd_en        (rx_rd_en),
    .rd_data      (r_rd_word),
    .empty        (rx_empty),
    .prog_empty   (),
    .rd_data_count(r_rd_data_count), // only here to check if the value moves
    .underflow    (),
    .rd_rst_busy  (rx_rd_rst_busy),
    .almost_empty (),
    .data_valid   (),
    // ignoring optional arguments
    .injectsbiterr(1'b0),
    .injectdbiterr(1'b0),
    .sbiterr      (),
    .dbiterr      ()
  );

  // building qsfp rx start of packet
  logic qsfp_rx_sop;
  logic rx_data_valid_d;

  always_ff @(posedge clk_mrmac)
    rx_data_valid_d <= qsfp_rx_tvalid;

  assign qsfp_rx_sop = (qsfp_rx_tvalid & ~rx_data_valid_d);

  // ============================================================================================ //
  // Debug
  // =====
  // counter of
  //    - (@clk_mrmac) mrmac clk
  //    - (@clk_mrmac) trigger_rd
  //    x (@clk_mrmac) sop to sop
  //
  //    - (@clk_control) tx_wr_en
  //    - (@clk_control) word_has_changed
  //
  // Status of
  //    - (@clk_mrmac) tx_empty
  //    - (@clk_mrmac) tx_rd_rst_busy
  //    - (@clk_mrmac) tx_data_valid
  //    - (@clk_mrmac) rd_data_count
  //    - (@clk mrmac) rd_data_count
  //
  //    - (@clk_control) tx_full
  //    - (@clk_control) tx_wr_rst_busy
  //
  // ============================================================================================ //

  // counters -------------------------------------------------------------------------------------
  // from fast clock
  logic [63:0] clk_cnt;
  logic [31:0] trigger_rd_cnt;
  logic [63:0] valid_words;
  logic [63:0] sop_cnt;

  always_ff @(posedge clk_mrmac) begin
    if (~s_rstn_mrmac || reset_registers_cdc) begin
      clk_cnt <='h0;
    end else begin
      if (loop & start_mem_pull) begin
        clk_cnt <= clk_cnt+1;
      end
    end
  end

  always_ff @(posedge clk_mrmac) begin
    if (~s_rstn_mrmac || reset_registers_cdc) begin
      valid_words <='h0;
    end else begin
      if (loop && qsfp_rx_tvalid) begin
        valid_words <= valid_words+1;
      end
    end
  end

  logic tx_sop_d;
  logic qsfp_rx_sop_d;

  always_ff @(posedge clk_mrmac)
    tx_sop_d <= tx_sop;
  always_ff @(posedge clk_mrmac)
    qsfp_rx_sop_d <= qsfp_rx_sop;

  logic sop_tx_rx;
  always_ff @(posedge clk_mrmac) begin
    if (~s_rstn_mrmac) begin
      sop_tx_rx <=1'b0;
    end else begin
      if (tx_sop & ~tx_sop_d) begin
        sop_tx_rx <= 1'b1;
      end else if (qsfp_rx_sop & ~qsfp_rx_sop_d) begin
        sop_tx_rx <= 1'b0;
      end
    end
  end


  always_ff @(posedge clk_mrmac) begin
    if (~s_rstn_mrmac || reset_registers_cdc) begin
      sop_cnt <='h0;
    end else begin
      if (sop_tx_rx) begin
        sop_cnt <= sop_cnt+1;
      end
    end
  end

  always_ff @(posedge clk_mrmac) begin
    if (~s_rstn_mrmac) begin
      trigger_rd_cnt <='h0;
    end else begin
      if (trigger_rd == 1'b1) begin
        trigger_rd_cnt <= trigger_rd_cnt+1;
      end
    end
  end

  // from slow clock
  always_ff @(posedge clk_control) begin
    if (~s_rstn_control) begin
      tx_wr_en_cnt <='h0;
    end begin
      if (tx_wr_en == 1'b1) begin
        tx_wr_en_cnt <= tx_wr_en_cnt+1;
      end
    end
  end

  //  -------------------------------------------
  // clock conversion from fast to slow
  logic [CDC_SYNC_STAGES-1:0][63:0] cdc_clk_cnt;
  logic [CDC_SYNC_STAGES-1:0][63:0] cdc_valid_words;
  logic [CDC_SYNC_STAGES-1:0][31:0] cdc_trigger_rd_cnt;
  logic [CDC_SYNC_STAGES-1:0][31:0] cdc_sop_cnt;

  always_ff @(posedge clk_control) begin
    cdc_clk_cnt[0]        <= clk_cnt;
    cdc_trigger_rd_cnt[0] <= trigger_rd_cnt;
    cdc_valid_words[0]    <= valid_words;
    cdc_sop_cnt[0]        <= sop_cnt;
  end

  generate
    for (genvar gen_i = 1; gen_i < CDC_SYNC_STAGES ; gen_i = gen_i + 1) begin
      always_ff @(posedge clk_control) begin
        cdc_clk_cnt[gen_i] <= cdc_clk_cnt[gen_i-1];
        cdc_trigger_rd_cnt[gen_i] <= cdc_trigger_rd_cnt[gen_i-1];
        cdc_valid_words[gen_i] <= cdc_valid_words[gen_i-1];
        cdc_sop_cnt[gen_i] <= cdc_sop_cnt[gen_i-1];
      end
    end
  endgenerate

  assign clk_cnt_out = cdc_clk_cnt[CDC_SYNC_STAGES-1];
  assign trigger_rd_cnt_out = cdc_trigger_rd_cnt[CDC_SYNC_STAGES-1];
  assign valid_words_out = cdc_valid_words[CDC_SYNC_STAGES-1];
  assign sop_cnt_out = cdc_sop_cnt[CDC_SYNC_STAGES-1];

  // status ---------------------------------------------------------------------------------------
  always_ff @(posedge clk_control) begin
    if (~s_rstn_control) begin
      stat_tx_full <= 'h0;
      stat_tx_wr_rst_busy <= 'h0;
    end else begin
      stat_tx_full <= tx_full;
      stat_tx_wr_rst_busy <= tx_wr_rst_busy;
    end
  end

  logic [CDC_SYNC_STAGES-1:0] cdc_tx_empty;
  logic [CDC_SYNC_STAGES-1:0] cdc_tx_rd_rst_busy;
  logic [CDC_SYNC_STAGES-1:0] cdc_tx_data_valid;
  logic [CDC_SYNC_STAGES-1:0] cdc_qsfp_tx_tready;
  logic [CDC_SYNC_STAGES-1:0] [NB_WORD_W-1:0] cdc_rd_data_count;

  always_ff @(posedge clk_control) begin
    cdc_tx_empty[0]       <= tx_empty;
    cdc_tx_rd_rst_busy[0] <= tx_rd_rst_busy;
    cdc_tx_data_valid[0]  <= tx_data_valid;
    cdc_rd_data_count[0]  <= rd_data_count;
    cdc_qsfp_tx_tready[0] <= qsfp_tx_tready;
  end

  generate
    for (genvar gen_i = 1; gen_i < CDC_SYNC_STAGES ; gen_i = gen_i + 1) begin
      always_ff @(posedge clk_control) begin
        cdc_tx_empty[gen_i]       <= cdc_tx_empty[gen_i-1];
        cdc_tx_rd_rst_busy[gen_i] <= cdc_tx_rd_rst_busy[gen_i-1];
        cdc_tx_data_valid[gen_i]  <= cdc_tx_data_valid[gen_i-1];
        cdc_rd_data_count[gen_i]  <= cdc_rd_data_count[gen_i-1];
        cdc_qsfp_tx_tready[gen_i] <= cdc_qsfp_tx_tready[gen_i-1];
      end
    end
  endgenerate

  assign stat_tx_empty = cdc_tx_empty[CDC_SYNC_STAGES-1];
  assign stat_tx_rd_rst_busy = cdc_tx_rd_rst_busy[CDC_SYNC_STAGES-1];
  assign stat_tx_data_valid = cdc_tx_data_valid[CDC_SYNC_STAGES-1];
  assign stat_rd_data_count = cdc_rd_data_count[CDC_SYNC_STAGES-1];
  assign stat_qsfp_tx_tready = cdc_qsfp_tx_tready[CDC_SYNC_STAGES-1];

endmodule
