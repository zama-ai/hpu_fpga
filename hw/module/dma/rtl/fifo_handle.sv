// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Handler for XPM FIFO ASYNC on rx and TX sides
// ----------------------------------------------------------------------------------------------
//
// ==============================================================================================

module fifo_handle #(
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
  input  logic                    read_ack

);
  // =========================================================================================== //
  // localparam
  // =========================================================================================== //
  localparam int CDC_SYNC_STAGES = 2;

  // word number is rather stable, changed only once in a while a false path must be set to first reg
  // set_false_path -to [get_cells -hierarchical -filter {NAME =~ *fifo_handle/nb_word_mrmac[0]*}]
  logic [CDC_SYNC_STAGES-1:0] [NB_WORD_W-1:0] nb_word_mrmac;

  always_ff @(posedge clk_mrmac) begin
    nb_word_mrmac[0] <= r_nb_word;
  end

  generate
    for (genvar gen_i = 1; gen_i < CDC_SYNC_STAGES ; gen_i = gen_i + 1)
      always_ff @(posedge clk_mrmac)
        nb_word_mrmac[gen_i] <= nb_word_mrmac[gen_i-1];
  endgenerate

  // =========================================================================================== //
  // FIFO TX
  // =========================================================================================== //
  // FIFO tx write control ------------------------------------------------------------------------
  logic tx_full;
  logic tx_wr_en;
  logic tx_wr_rst_busy;

  // First Thing to know is when a word has been written to regif
  logic [AXIS_TDATA_W-1:0] r_wr_word_d;

  // note that no reset value: r_wr_word is assumed correctly reset, from register file
  always_ff @(posedge clk_control) begin
    r_wr_word_d <= r_wr_word;
  end

  // Then we need to know when a word has been changed in the regfile
  logic word_has_changed;

  always_ff @(posedge clk_control) begin
    if(!s_rstn_control) begin
      word_has_changed <= 1'b0;
    end else begin
      if (r_wr_word_d != r_wr_word) begin
        word_has_changed <= 1'b1;
      end else begin
        word_has_changed <= 1'b0;
      end
    end
  end

  // with this information we can trigger writes in the fifo
  assign tx_wr_en = qsfp_tx_tready && word_has_changed && !tx_full && !tx_wr_rst_busy;

  // FIFO tx read control -------------------------------------------------------------------------
  logic [AXIS_TDATA_W-1:0] tx_rd_data;
  logic [NB_WORD_W-1:0]    rd_data_count;
  logic                    tx_rd_en;
  logic tx_data_valid;

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
  assign tx_rd_en = trigger_rd && !tx_empty && !tx_rd_rst_busy;

  xpm_fifo_async_wrapper # (
    .CDC_SYNC_STAGES(CDC_SYNC_STAGES),
    .DATA_W(AXIS_TDATA_W),
    .FIFO_DEPTH(FIFO_DEPTH),
    .DATA_COUNT_WIDTH(NB_WORD_W),
    .SIM_ASSERT_CHK(SIM_ASSERT_CHK)
  ) xpm_fifo_tx (
    .sleep        (1'b0),            // to simplify let's not use power saving mode
    .rst          (~s_rstn_control), // must be syncronous to wr reset
    // Write Domain ports
    .wr_clk       (clk_control),
    .wr_en        (tx_wr_en),
    .wr_data      (r_wr_word_d),
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
  assign qsfp_tx_tdata = tx_rd_data;
  assign qsfp_tx_tvalid = tx_data_valid;
  assign qsfp_tx_tlast = ((rd_data_count ==  1) && tx_data_valid) ? 1'b1 : 1'b0;
  assign qsfp_tx_tkeep_user = qsfp_tx_tvalid ? 'hF : 0; // first 4 bytes are valid

  // =========================================================================================== //
  // FIFO RX
  // =========================================================================================== //
  logic rx_full;
  logic rx_wr_en;
  logic rx_wr_rst_busy;

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
    .rst          (~s_rstn_mrmac), // must be syncronous to wr reset
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

endmodule
