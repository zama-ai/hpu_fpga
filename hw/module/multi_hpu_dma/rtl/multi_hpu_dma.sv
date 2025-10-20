// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : multi-HPU DMA
// ----------------------------------------------------------------------------------------------
//
// ==============================================================================================

module multi_hpu_dma
  import mhdma_pkg::*;
  import axi_if_common_param_pkg::*;
  import axi_if_shell_axil_pkg::*;
  import hpu_regif_core_eth_2in3_pkg::*;
#(
  parameter int FIFO_DEPTH = 512,
  parameter int NB_WORD_W = $clog2(FIFO_DEPTH)+1
) (
  // Ethernet configuration interface -----------------------------------------
  input logic clk_eth_cfg,
  input logic resetn_eth_cfg,
  // Ethernet fast clock interface --------------------------------------------
  input logic clk_eth_mrmac,
  input logic resetn_eth_mrmac,
  // Axi4-lite slave interface for regfile ------------------------------------
  input  logic [AXIL_ADD_W-1:0]      s_axil_dma_awaddr,
  input  logic                       s_axil_dma_awvalid,
  output logic                       s_axil_dma_awready,
  input  logic [AXIL_DATA_W-1:0]     s_axil_dma_wdata,
  input  logic [AXIL_DATA_BYTES-1:0] s_axil_dma_wstrb, /* UNUSED */
  input  logic                       s_axil_dma_wvalid,
  output logic                       s_axil_dma_wready,
  output logic [1:0]                 s_axil_dma_bresp,
  output logic                       s_axil_dma_bvalid,
  input  logic                       s_axil_dma_bready,
  input  logic [AXIL_ADD_W-1:0]      s_axil_dma_araddr,
  input  logic                       s_axil_dma_arvalid,
  output logic                       s_axil_dma_arready,
  output logic [AXIL_DATA_W-1:0]     s_axil_dma_rdata,
  output logic [1:0]                 s_axil_dma_rresp,
  output logic                       s_axil_dma_rvalid,
  input  logic                       s_axil_dma_rready,
  // QSFP system interface ----------------------------------------------------
  // == TX
  output[QSFP_LANE_NB-1:0][MRMAC_AXIS_W-1:0  ] qsfp_tx_tdata,
  output[QSFP_LANE_NB-1:0][MRMAC_TKEEP_W-1:0 ] qsfp_tx_tkeep_user,
  output[QSFP_LANE_NB-1:0]                     qsfp_tx_tlast,
  output[QSFP_LANE_NB-1:0]                     qsfp_tx_tvalid,
  input [QSFP_LANE_NB-1:0]                     qsfp_tx_tready,
  // == RX
  input [QSFP_LANE_NB-1:0][MRMAC_AXIS_W-1:0  ] qsfp_rx_tdata,
  input [QSFP_LANE_NB-1:0][MRMAC_TKEEP_W-1:0 ]  qsfp_rx_tkeep_user,
  input [QSFP_LANE_NB-1:0]                     qsfp_rx_tlast,
  input [QSFP_LANE_NB-1:0]                     qsfp_rx_tvalid,
  // irq interface ------------------------------------------------------------
  logic irq_read_done,
  logic irq_rx_notify,
  // Giga traceivers interface ------------------------------------------------
  output [QSFP_LANE_NB-1:0] gt_reset_rx_datapath,
  output [QSFP_LANE_NB-1:0] gt_reset_tx_datapath,
  output [QSFP_LANE_NB-1:0] gt_reset_all,
  input  [QSFP_LANE_NB-1:0] gt_rx_reset_done,
  input  [QSFP_LANE_NB-1:0] gt_tx_reset_done,
  // line rate, should be set to zero
  output [7:0]         gt_line_rate,
  // loopback mode, will be applied to all channels
  //  * 000: disabled
  //  * 010: near end pma
  //  * 100: near end pcs
  output [2:0]         gt_loopback
);

  // ============================================================================================ --
  // Signal
  // ============================================================================================ --
  logic [$clog2(QSFP_LANE_NB):0] line_sel;

  // ============================================================================================ //
  // Register file
  // =============
  // What needs to be controlled through axi4-lite
  //  = SYSTEM ================================================================
  //  * Source MAC address        : 24b : rw : MAC address of this HPU, without OUI
  //  * Target MAC address        : 24b : rw : MAC address of target HPU, without OUI
  //  * Line parametrization      : 14b : rw : general parameters for line communication
  //  = RESET =================================================================
  //  * rx datapath reset         : 4b : rw : gt_reset_rx_datapath
  //  * tx datapath reset         : 4b : rw : gt_reset_tx_datapath
  //  * GT PLL and datapath reset : 4b : rw : gt_reset_all
  //  * reset done monitoring     : 8b : r  : gt_{rx;tx}_reset_done
  // ============================================================================================ //
  // Registers
  logic [31:0] r_system_src_mac_addr;
  logic [31:0] r_system_dst_mac_addr;
  logic [31:0] r_system_line;
  logic [31:0] r_reset_datapath;
  logic [31:0] r_reset_monitor;
  logic [31:0] r_line_debug;
  logic [31:0] r_status_debug;
  // signals derived from registers
  logic                 tx_loop;
  logic                 rx_to_tx;
  logic                 reset_registers;
  logic                 debug;

  logic                 stat_tx_empty;
  logic                 stat_tx_rd_rst_busy;
  logic                 stat_tx_data_valid;
  logic [NB_WORD_W-1:0] stat_rd_data_count;
  logic                 stat_tx_full;
  logic                 stat_tx_wr_rst_busy;
  logic                 stat_qsfp_tx_tready;

  assign line_sel      = r_system_line[1:0];
  assign gt_loopback   = r_system_line[4:2];
  assign gt_line_rate  = r_system_line[13:5];
  assign debug         = r_system_line[31];

  assign gt_reset_all         = r_reset_datapath[3:0];
  assign gt_reset_tx_datapath = r_reset_datapath[7:4];
  assign gt_reset_rx_datapath = r_reset_datapath[11:8];

  assign r_reset_monitor[3:0] = gt_tx_reset_done;
  assign r_reset_monitor[7:4] = gt_rx_reset_done;
  assign r_reset_monitor[31:8] = 'h0;

  assign rx_to_tx        = r_line_debug[29];
  assign tx_loop         = r_line_debug[30];
  assign reset_registers = r_line_debug[31];

  assign r_status_debug = {stat_tx_empty, stat_tx_rd_rst_busy, stat_tx_data_valid,
                          stat_tx_full, stat_tx_wr_rst_busy, stat_qsfp_tx_tready,
                          {(AXIL_DATA_W-NB_WORD_W-6){1'b0}},
                          stat_rd_data_count};

  // status directly from fifo
  logic [NB_WORD_W-1:0]    r_nb_word;
  logic [MRMAC_AXIS_W-1:0] r_wr_word;
  logic [AXIL_DATA_W-1:0]  r_wr_word_a;
  logic [AXIL_DATA_W-1:0]  r_wr_word_b;
  logic [NB_WORD_W-1:0]    r_wr_data_count;
  logic [NB_WORD_W-1:0]    r_rd_data_count;
  logic [MRMAC_AXIS_W-1:0] r_rd_word;

  logic [63:0]             clk_cnt_out;
  logic [63:0]             valid_words_out;
  logic [63:0]             sop_cnt_out;
  logic [31:0]             trigger_rd_cnt_out;
  logic [31:0]             tx_wr_en_cnt;

  hpu_regif_core_eth_2in3  hpu_regif_core_eth_2in3 (
    // configuration interface
    .clk    (clk_eth_cfg),
    .s_rst_n(resetn_eth_cfg),
    // axi4-lite
    .s_axil_awaddr (s_axil_dma_awaddr),
    .s_axil_awvalid(s_axil_dma_awvalid),
    .s_axil_awready(s_axil_dma_awready),
    .s_axil_wdata  (s_axil_dma_wdata),
    .s_axil_wvalid (s_axil_dma_wvalid),
    .s_axil_wready (s_axil_dma_wready),
    .s_axil_bresp  (s_axil_dma_bresp),
    .s_axil_bvalid (s_axil_dma_bvalid),
    .s_axil_bready (s_axil_dma_bready),
    .s_axil_araddr (s_axil_dma_araddr),
    .s_axil_arvalid(s_axil_dma_arvalid),
    .s_axil_arready(s_axil_dma_arready),
    .s_axil_rdata  (s_axil_dma_rdata),
    .s_axil_rresp  (s_axil_dma_rresp),
    .s_axil_rvalid (s_axil_dma_rvalid),
    .s_axil_rready (s_axil_dma_rready),
    .r_axil_wdata  (/* */),
    // registers
    .r_system_src_mac_addr                 (r_system_src_mac_addr),
    .r_system_dst_mac_addr                 (r_system_dst_mac_addr),
    .r_system_line                         (r_system_line),
    .r_reset_datapath                      (r_reset_datapath),
    .r_reset_monitor_upd                   (r_reset_monitor),
    .r_line_debug                          (r_line_debug),
    .r_fifo_write_number_of_words          (r_nb_word),
    .r_fifo_write_words_to_write_a         (r_wr_word_a),
    .r_fifo_write_words_to_write_b         (r_wr_word_b),
    .r_fifo_write_fifo_write_data_count_upd({ {(AXIL_DATA_W-NB_WORD_W){1'b0}}, r_wr_data_count}),
    .r_fifo_read_words_to_read_a_upd       (r_rd_word[AXIL_DATA_W-1:0]),
    .r_fifo_read_words_to_read_b_upd       (r_rd_word[2*AXIL_DATA_W-1:AXIL_DATA_W]),
    .r_fifo_read_fifo_read_data_count_upd  ({ {(AXIL_DATA_W-NB_WORD_W){1'b0}}, r_rd_data_count}),
    .r_cnt_trig_rd_upd                     (trigger_rd_cnt_out),
    .r_cnt_tx_wr_upd                       (tx_wr_en_cnt),
    .r_stat_clk_a_upd                      (clk_cnt_out[31:0] ),
    .r_stat_clk_b_upd                      (clk_cnt_out[63:32]),
    .r_stat_valid_words_a_upd              (valid_words_out[31:0] ),
    .r_stat_valid_words_b_upd              (valid_words_out[63:32]),
    .r_stat_sop_cnt_a_upd                  (sop_cnt_out[31:0]),
    .r_stat_sop_cnt_b_upd                  (sop_cnt_out[63:32]),
    .r_stat_status_upd                     (r_status_debug)
  );

  // Logic around regfile -------------------------------------------------------------------------
  // read_ack is a pulse that partly controls the rx_fifo read, must be in configuration clock freq
  // because axi4-lite is limited in word number, the ack is triggered only when the second word is read
  logic read_ack;

  always_ff @(posedge clk_eth_cfg) begin
    if (~resetn_eth_cfg) begin
      read_ack <= 1'b0;
    end else begin
      if ((s_axil_dma_araddr == FIFO_READ_WORDS_TO_READ_B_OFS) && s_axil_dma_arready) begin
        read_ack <= 1'b1;
      end else begin
        read_ack <= 1'b0;
      end
    end
  end

  // write ack: same fashion as read_ack, a pulse is generated
  logic write_ack;
  always_ff @(posedge clk_eth_cfg) begin
    if (~resetn_eth_cfg) begin
      write_ack <= 1'b0;
    end else begin
      if ((s_axil_dma_awaddr == FIFO_WRITE_WORDS_TO_WRITE_B_OFS) && s_axil_dma_awready) begin
        write_ack <= 1'b1;
      end else begin
        write_ack <= 1'b0;
      end
    end
  end

  // merging half words into a single one
  assign r_wr_word = write_ack ? {r_wr_word_a, r_wr_word_b} :0;

  // ============================================================================================ //
  // Fifo Handle
  // ==================
  // Handles two FIFOs for RX and TX that are meant to be back to back to MRMAC axi4-stream
  // Basically sends axi4-stream data frames to MRMAC
  //
  // ----------------------------------------------------------------------------------------------
  // There are different modes
  // ----------------------------------------------------------------------------------------------
  //  - 0: DEBUG     : regfile must be able to read and write directly to the two FIFOs
  // ----------------------------------------------------------------------------------------------
  //  - 1: FIFO_LOOP : after initialisation, we are sending continuously what is in the fifo
  //                   stop sending data in TX when this mode changes
  // ----------------------------------------------------------------------------------------------
  //  - 2: RX_TO_TX  : sends what is received in rx to tx link
  // ----------------------------------------------------------------------------------------------
  //
  // ----------------------------------------------------------------------------------------------
  // Control of the logic
  //
  // reset_registers  : resets the value of the statistic counters
  //
  // ----------------------------------------------------------------------------------------------

  // ============================================================================================ //
  logic [MRMAC_AXIS_W-1:0  ] axis_rx_tdata;
  logic [MRMAC_TKEEP_W-1:0 ]  axis_rx_tkeep_user;
  logic                      axis_rx_tlast;
  logic                      axis_rx_tvalid;

  logic [MRMAC_AXIS_W-1:0] axis_tx_tdata;
  logic [MRMAC_TKEEP_W-1:0] axis_tx_tkeep_user;
  logic                    axis_tx_tlast;
  logic                    axis_tx_tvalid;
  logic                    axis_tx_tready;

  mhdma_trace # (
    .FIFO_DEPTH(FIFO_DEPTH),
    .SIM_ASSERT_CHK(0)
  ) mhdma_trace (
    // system interface
    .clk_control        (clk_eth_cfg),
    .s_rstn_control     (resetn_eth_cfg),
    .clk_mrmac          (clk_eth_mrmac),
    .s_rstn_mrmac       (resetn_eth_mrmac),
    // MRMAC RX interface
    .qsfp_rx_tdata      (axis_rx_tdata),
    .qsfp_rx_tkeep_user (axis_rx_tkeep_user),
    .qsfp_rx_tlast      (axis_rx_tlast),
    .qsfp_rx_tvalid     (axis_rx_tvalid),
    // MRMAC TX interface
    .qsfp_tx_tdata      (axis_tx_tdata),
    .qsfp_tx_tkeep_user (axis_tx_tkeep_user),
    .qsfp_tx_tlast      (axis_tx_tlast),
    .qsfp_tx_tvalid     (axis_tx_tvalid),
    .qsfp_tx_tready     (axis_tx_tready),
    // register interface
    .r_nb_word          (r_nb_word),
    .r_wr_word          (r_wr_word),
    .r_wr_data_count    (r_wr_data_count),
    .r_rd_data_count    (r_rd_data_count),
    .r_rd_word          (r_rd_word),
    .read_ack           (read_ack),
    .write_ack          (write_ack),
    .tx_loop            (tx_loop),
    .rx_to_tx           (rx_to_tx),
    .reset_registers    (reset_registers),
    // debug interface
    .clk_cnt_out         (clk_cnt_out),
    .valid_words_out     (valid_words_out),
    .sop_cnt_out         (sop_cnt_out),
    .trigger_rd_cnt_out  (trigger_rd_cnt_out),
    .tx_wr_en_cnt        (tx_wr_en_cnt),
    .stat_tx_empty       (stat_tx_empty),
    .stat_tx_rd_rst_busy (stat_tx_rd_rst_busy),
    .stat_tx_data_valid  (stat_tx_data_valid),
    .stat_tx_full        (stat_tx_full),
    .stat_tx_wr_rst_busy (stat_tx_wr_rst_busy),
    .stat_qsfp_tx_tready (stat_qsfp_tx_tready),
    .stat_rd_data_count  (stat_rd_data_count)
  );

  // ============================================================================================ //
  // AXI4-stream switch
  // ==================
  // depending on line_sel signal, selects and outputs the correct line
  // this module is fully combinatory
  // ============================================================================================ //
  // Rx Link
  assign axis_rx_tdata      = qsfp_rx_tdata[line_sel];
  assign axis_rx_tkeep_user = qsfp_rx_tkeep_user[line_sel];
  assign axis_rx_tlast      = qsfp_rx_tlast[line_sel];
  assign axis_rx_tvalid     = qsfp_rx_tvalid[line_sel];

  // TX link
  assign axis_tx_tready = qsfp_tx_tready[line_sel];

  generate
    for (genvar i = 0; i < QSFP_LANE_NB; i++) begin
      assign qsfp_tx_tdata[i]       = (line_sel == i) ? axis_tx_tdata      : 'h0;
      assign qsfp_tx_tkeep_user[i]  = (line_sel == i) ? axis_tx_tkeep_user : 'h0;
      assign qsfp_tx_tlast[i]       = (line_sel == i) ? axis_tx_tlast      : 'h0;
      assign qsfp_tx_tvalid[i]      = (line_sel == i) ? axis_tx_tvalid     : 'h0;
    end
  endgenerate

endmodule
