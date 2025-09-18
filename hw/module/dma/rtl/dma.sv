// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Top of DMA
// ----------------------------------------------------------------------------------------------
//
// ==============================================================================================

module dma
  import axi_if_common_param_pkg::*;
  import axi_if_shell_axil_pkg::*;
  import hpu_regif_core_eth_2in3_pkg::*;
#(
  parameter int LINE_NB       = 4,  // number of QSFP lines
  parameter int AXIS_TDATA_W  = 64, // must match MAC+PCS configuration from bd
  parameter int AXIS_TKEEP_W  = 11,

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
  output[LINE_NB-1:0][AXIS_TDATA_W-1:0  ] qsfp_tx_tdata,
  output[LINE_NB-1:0][AXIS_TKEEP_W-1:0 ]  qsfp_tx_tkeep_user,
  output[LINE_NB-1:0]                     qsfp_tx_tlast,
  output[LINE_NB-1:0]                     qsfp_tx_tvalid,
  input [LINE_NB-1:0]                     qsfp_tx_tready,
  // == RX
  input [LINE_NB-1:0][AXIS_TDATA_W-1:0  ] qsfp_rx_tdata,
  input [LINE_NB-1:0][AXIS_TKEEP_W-1:0 ]  qsfp_rx_tkeep_user,
  input [LINE_NB-1:0]                     qsfp_rx_tlast,
  input [LINE_NB-1:0]                     qsfp_rx_tvalid,
  // control interface --------------------------------------------------------
  // loopback mode, will be applied to all channels
  //  * 000: disabled
  //  * 010: near end pma
  //  * 100: near end pcs
  output [2:0] gt_loopback,
  // Line rate TBD
  output [7:0] gt_line_rate,
  // resets
  output [LINE_NB-1:0] gt_reset_rx_datapath,
  output [LINE_NB-1:0] gt_reset_tx_datapath,
  output [LINE_NB-1:0] gt_reset_all,
  input  [LINE_NB-1:0] gt_rx_reset_done,
  input  [LINE_NB-1:0] gt_tx_reset_done
);

  // ============================================================================================ --
  // Signal
  // ============================================================================================ --
  logic [$clog2(LINE_NB):0] line_sel;

  // ============================================================================================ //
  // Register file
  // =============
  // What needs to be controlled through axi4-lite
  //  = MRMAC =================================================================
  //  * line selection            : 3b : rw : line_select
  //  * rx datapath reset         : 4b : rw : gt_reset_rx_datapath
  //  * tx datapath reset         : 4b : rw : gt_reset_tx_datapath
  //  * GT PLL and datapath reset : 4b : rw : gt_reset_all
  //  * reset done monitoring     : 8b : r  : gt_{rx;tx}_reset_done
  //  = GTM ===================================================================
  //  * channel line rate         : 8b : rw : gt_line_rate
  //  * loopback                  : 3b : rw : gt_loopback
  // ============================================================================================ //
  // Registers
  logic [31:0] r_line_parameter;
  logic [31:0] r_reset_datapath;
  logic [31:0] r_reset_monitor;
  // for fifo handler
  logic [NB_WORD_W-1:0]    r_nb_word;
  logic [AXIS_TDATA_W-1:0] r_wr_word;
  logic [NB_WORD_W-1:0]    r_wr_data_count;
  logic [NB_WORD_W-1:0]    r_rd_data_count;
  logic [AXIS_TDATA_W-1:0] r_rd_word;
  // -------------------------------------------------------------------------------------------- //
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

    // control signals
    .r_line_parameter(r_line_parameter),
    .r_reset_datapath(r_reset_datapath),
    .r_reset_monitor_upd(r_reset_monitor),

    .r_fifo_write_number_of_words(r_nb_word),
    .r_fifo_write_words_to_write(r_wr_word),
    .r_fifo_write_fifo_write_data_count_upd(r_wr_data_count),
    .r_fifo_read_words_to_read_upd(r_rd_word),
    .r_fifo_read_fifo_read_data_count_upd(r_rd_data_count)
  );

  // read acknowledge must be built here in case hpu_regif_core_eth_2in3 changes
  // read_ack is a pulse that partly controls the rx_fifo read, must be in configuration clock freq
  logic read_ack;

  always_ff @(posedge clk_eth_cfg) begin
    if (~resetn_eth_cfg) begin
      read_ack <= 1'b0;
    end else begin
      if ((s_axil_dma_araddr == FIFO_READ_WORDS_TO_READ_OFS) && s_axil_dma_arready) begin
        read_ack <= 1'b1;
      end else begin
        read_ack <= 1'b0;
      end
    end
  end

  logic [AXIS_TDATA_W-1:0  ] axis_rx_tdata;
  logic [AXIS_TKEEP_W-1:0 ]  axis_rx_tkeep_user;
  logic                      axis_rx_tlast;
  logic                      axis_rx_tvalid;

  logic [AXIS_TDATA_W-1:0] axis_tx_tdata;
  logic [AXIS_TKEEP_W-1:0] axis_tx_tkeep_user;
  logic                    axis_tx_tlast;
  logic                    axis_tx_tvalid;
  logic                    axis_tx_tready;

  fifo_handle # (
    .AXIS_TDATA_W(AXIS_TDATA_W),
    .AXIS_TKEEP_W(AXIS_TKEEP_W),
    .FIFO_DEPTH(FIFO_DEPTH),
    .SIM_ASSERT_CHK(0)
  ) fifo_handle (
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
    .read_ack           (read_ack)
  );

  // ============================================================================================ //
  // AXI4-stream switch
  // ==================
  // depending on line_sel signal, selects and outputs the correct line
  // this module is fully combinatory
  // ============================================================================================ //
  axis_switch # (
    .LINE_NB            (LINE_NB),
    .AXIS_TDATA_W       (AXIS_TDATA_W),
    .AXIS_TKEEP_W       (AXIS_TKEEP_W)
  ) axis_switch (
    .qsfp_rx_tdata      (qsfp_rx_tdata),
    .qsfp_rx_tkeep_user (qsfp_rx_tkeep_user),
    .qsfp_rx_tlast      (qsfp_rx_tlast),
    .qsfp_rx_tvalid     (qsfp_rx_tvalid),

    .qsfp_tx_tdata      (qsfp_tx_tdata),
    .qsfp_tx_tkeep_user (qsfp_tx_tkeep_user),
    .qsfp_tx_tlast      (qsfp_tx_tlast),
    .qsfp_tx_tvalid     (qsfp_tx_tvalid),
    .qsfp_tx_tready     (qsfp_tx_tready),

    .axis_rx_tdata      (axis_rx_tdata),
    .axis_rx_tkeep_user (axis_rx_tkeep_user),
    .axis_rx_tlast      (axis_rx_tlast),
    .axis_rx_tvalid     (axis_rx_tvalid),

    .axis_tx_tdata      (axis_tx_tdata),
    .axis_tx_tkeep_user (axis_tx_tkeep_user),
    .axis_tx_tlast      (axis_tx_tlast),
    .axis_tx_tvalid     (axis_tx_tvalid),
    .axis_tx_tready     (axis_tx_tready),

    .line_sel(line_sel)
  );

  // assigning outputs
  assign line_sel      = r_line_parameter[1:0];
  assign gt_loopback   = r_line_parameter[4:2];
  assign gt_line_rate  = r_line_parameter[14:5];

  assign gt_reset_all         = r_reset_datapath[3:0];
  assign gt_reset_tx_datapath = r_reset_datapath[7:4];
  assign gt_reset_rx_datapath = r_reset_datapath[11:8];

  assign r_reset_monitor[3:0] = gt_tx_reset_done;
  assign r_reset_monitor[7:4] = gt_rx_reset_done;
  assign r_reset_monitor[31:8] = 'h0;

endmodule
