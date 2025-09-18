// ============================================================================================== //
// Description  : Axi4-lite register bank
// This file was generated with rust regmap generator:
//  * Date:  2025-09-18
//  * Tool_version: bb0db737792da6b81e69a039028c971af1627fe2
// ---------------------------------------------------------------------------------------------- //
// xR[n]W[na]
// |-> who is in charge of the register update logic : u -> User
//                                                   : k -> Kernel (with an *_upd signal)
//                                                   : p -> Parameters (i.e. constant register)
//  | Read options
//  | [n] optional generate read notification (have a _rd_en)
//  | Write options
//  | [n] optional generate wr notification (have a _wr_en)
//
// Thus type of registers are:
// uRW  : Read-write
//      : Value provided by the host. The host can read it and write it.
// uW   : Write-only
//      : Value provided by the host. The host can only write it.
// uWn  : Write-only with notification
//      : Value provided by the host. The host can only write it.
// kR   : Read-only register
//      : Value provided by the RTL.
// kRn  : Read-only register with notification  (rd)
//      : Value provided by the RTL.
// kRWn : Read-only register with notification (wr)
//      : Value provided by the RTL. The host can read it. The write data is processed by the RTL.
// kRnWn: Read-only register with notification (rd/wr)
//      : Value provided by the RTL. The host can read it with notify. The write data is processed by the RTL.
// ============================================================================================== //
module hpu_regif_core_eth_2in3
import axi_if_common_param_pkg::*;
import axi_if_shell_axil_pkg::*;
import hpu_regif_core_eth_2in3_pkg::*;
#()(
  input  logic                           clk,
  input  logic                           s_rst_n,
  // Axi4 lite Slave Interface sAxi4
  input  logic [AXIL_ADD_W-1:0]         s_axil_awaddr,
  input  logic                          s_axil_awvalid,
  output logic                          s_axil_awready,
  input  logic [AXIL_DATA_W-1:0]        s_axil_wdata,
  input  logic                          s_axil_wvalid,
  output logic                          s_axil_wready,
  output logic [AXI4_RESP_W-1:0]        s_axil_bresp,
  output logic                          s_axil_bvalid,
  input  logic                          s_axil_bready,
  input  logic [AXIL_ADD_W-1:0]         s_axil_araddr,
  input  logic                          s_axil_arvalid,
  output logic                          s_axil_arready,
  output logic [AXIL_DATA_W-1:0]        s_axil_rdata,
  output logic [AXI4_RESP_W-1:0]        s_axil_rresp,
  output logic                          s_axil_rvalid,
  input  logic                          s_axil_rready,
  // Registered version of wdata
  output logic [AXIL_DATA_W-1:0]        r_axil_wdata
  // Register IO: line_parameter
    , output line_parameter_t r_line_parameter
  // Register IO: reset_datapath
    , output reset_datapath_t r_reset_datapath
  // Register IO: reset_monitor
    , output reset_monitor_t r_reset_monitor
        , input reset_monitor_t r_reset_monitor_upd
  // Register IO: fifo_write_number_of_words
    , output logic [REG_DATA_W-1: 0] r_fifo_write_number_of_words
  // Register IO: fifo_write_words_to_write_a
    , output logic [REG_DATA_W-1: 0] r_fifo_write_words_to_write_a
  // Register IO: fifo_write_words_to_write_b
    , output logic [REG_DATA_W-1: 0] r_fifo_write_words_to_write_b
  // Register IO: fifo_write_fifo_write_data_count
    , output logic [REG_DATA_W-1: 0] r_fifo_write_fifo_write_data_count
        , input  logic [REG_DATA_W-1: 0] r_fifo_write_fifo_write_data_count_upd
  // Register IO: fifo_read_words_to_read_a
    , output logic [REG_DATA_W-1: 0] r_fifo_read_words_to_read_a
        , input  logic [REG_DATA_W-1: 0] r_fifo_read_words_to_read_a_upd
  // Register IO: fifo_read_words_to_read_b
    , output logic [REG_DATA_W-1: 0] r_fifo_read_words_to_read_b
        , input  logic [REG_DATA_W-1: 0] r_fifo_read_words_to_read_b_upd
  // Register IO: fifo_read_fifo_read_data_count
    , output logic [REG_DATA_W-1: 0] r_fifo_read_fifo_read_data_count
        , input  logic [REG_DATA_W-1: 0] r_fifo_read_fifo_read_data_count_upd
);
// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int AXIL_ADD_OFS = 'he0000;
  localparam int AXIL_ADD_RANGE= 'h10000; // Should be a power of 2
  localparam int AXIL_ADD_RANGE_W = $clog2(AXIL_ADD_RANGE);
  localparam [AXIL_ADD_W-1:0] AXIL_ADD_RANGE_MASK = AXIL_ADD_W'(AXIL_ADD_RANGE - 1);
  localparam [AXIL_ADD_W-1:0] AXIL_ADD_OFS_MASK   = ~(AXIL_ADD_W'(AXIL_ADD_RANGE - 1));
// ============================================================================================== --
// axil management
// ============================================================================================== --
  logic                    axil_awready;
  logic                    axil_wready;
  logic [AXI4_RESP_W-1:0]  axil_bresp;
  logic                    axil_bvalid;
  logic                    axil_arready;
  logic [AXI4_RESP_W-1:0]  axil_rresp;
  logic [AXIL_DATA_W-1:0]  axil_rdata;
  logic                    axil_rvalid;
  logic                    axil_awreadyD;
  logic                    axil_wreadyD;
  logic [AXI4_RESP_W-1:0]  axil_brespD;
  logic                    axil_bvalidD;
  logic                    axil_arreadyD;
  logic [AXI4_RESP_W-1:0]  axil_rrespD;
  logic [AXIL_DATA_W-1:0]  axil_rdataD;
  logic                    axil_rvalidD;
  logic                    wr_en;
  logic [AXIL_ADD_W-1:0]   wr_add;
  logic [AXIL_DATA_W-1:0]  wr_data;
  logic                    rd_en;
  logic [AXIL_ADD_W-1:0]   rd_add;
  logic                    wr_enD;
  logic [AXIL_ADD_W-1:0]   wr_addD;
  logic [AXIL_DATA_W-1:0]  wr_dataD;
  logic                    rd_enD;
  logic [AXIL_ADD_W-1:0]   rd_addD;
  logic                    wr_en_okD;
  logic                    rd_en_okD;
  logic                    wr_en_ok;
  logic                    rd_en_ok;
  //== Check address
  // Answer all requests within [ADD_OFS -> ADD_OFS + RANGE[
  // Since RANGE is a power of 2, this could be done with masks.
  logic s_axil_wr_add_ok;
  logic s_axil_rd_add_ok;
  assign s_axil_wr_add_ok = (s_axil_awaddr & AXIL_ADD_OFS_MASK) == AXIL_ADD_OFS;
  assign s_axil_rd_add_ok = (s_axil_araddr & AXIL_ADD_OFS_MASK) == AXIL_ADD_OFS;
  //== Local read/write signals
  // Write when address and data are available.
  // Do not accept a new write request when the response
  // of previous request is still pending.
  // Since the ready is sent 1 cycle after the valid,
  // mask the cycle when the ready is r
  assign wr_enD   = (s_axil_awvalid & s_axil_wvalid
                     & ~(s_axil_awready | s_axil_wready)
                     & ~(s_axil_bvalid & ~s_axil_bready));
  assign wr_en_okD = wr_enD & s_axil_wr_add_ok;
  assign wr_addD  = s_axil_awaddr;
  assign wr_dataD = s_axil_wdata;
  // Answer to read request 1 cycle after, when there is no pending read data.
  // Therefore, mask the rd_en during the 2nd cycle.
  assign rd_enD   = (s_axil_arvalid
                    & ~s_axil_arready
                    & ~(s_axil_rvalid & ~s_axil_rready));
  assign rd_en_okD = rd_enD & s_axil_rd_add_ok;
  assign rd_addD   = s_axil_araddr;
  //== AXIL write ready
  assign axil_awreadyD = wr_enD;
  assign axil_wreadyD  = wr_enD;
  //== AXIL read address ready
  assign axil_arreadyD = rd_enD;
  //== AXIL write resp
  assign axil_bvalidD    = wr_en         ? 1'b1:
                           s_axil_bready ? 1'b0 : axil_bvalid;
  assign axil_brespD     = wr_en         ? wr_en_ok ? AXI4_OKAY : AXI4_SLVERR:
                           s_axil_bready ? 1'b0 : axil_bresp;
  //== AXIL read resp
  assign axil_rvalidD    = rd_en         ? 1'b1 :
                           s_axil_rready ? 1'b0 : axil_rvalid;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      axil_awready <= 1'b0;
      axil_wready  <= 1'b0;
      axil_bresp   <= '0;
      axil_bvalid  <= 1'b0;
      axil_arready <= 1'b0;
      axil_rdata   <= '0;
      axil_rresp   <= '0;
      axil_rvalid  <= 1'b0;
      wr_en        <= 1'b0;
      rd_en        <= 1'b0;
      wr_en_ok     <= 1'b0;
      rd_en_ok     <= 1'b0;
    end
    else begin
      axil_awready <= axil_awreadyD;
      axil_wready  <= axil_wreadyD;
      axil_bresp   <= axil_brespD;
      axil_bvalid  <= axil_bvalidD;
      axil_arready <= axil_arreadyD;
      axil_rdata   <= axil_rdataD;
      axil_rresp   <= axil_rrespD;
      axil_rvalid  <= axil_rvalidD;
      wr_en         <= wr_enD;
      rd_en         <= rd_enD;
      wr_en_ok      <= wr_en_okD;
      rd_en_ok      <= rd_en_okD;
    end
  end
  always_ff @(posedge clk) begin
    wr_add  <= wr_addD;
    rd_add  <= rd_addD;
    wr_data <= wr_dataD;
  end
  //= Assignment
  assign s_axil_awready = axil_awready;
  assign s_axil_wready  = axil_wready;
  assign s_axil_bresp   = axil_bresp;
  assign s_axil_bvalid  = axil_bvalid;
  assign s_axil_arready = axil_arready;
  assign s_axil_rresp   = axil_rresp;
  assign s_axil_rdata   = axil_rdata;
  assign s_axil_rvalid  = axil_rvalid;
  assign r_axil_wdata   = wr_data;
// ============================================================================================== --
// Default value signals
// ============================================================================================== --
//-- Default entry_eth_2in3_dummy_val0
  logic [REG_DATA_W-1:0]entry_eth_2in3_dummy_val0_default;
  assign entry_eth_2in3_dummy_val0_default = 'h5050504;
//-- Default entry_eth_2in3_dummy_val1
  logic [REG_DATA_W-1:0]entry_eth_2in3_dummy_val1_default;
  assign entry_eth_2in3_dummy_val1_default = 'h15151515;
//-- Default entry_eth_2in3_dummy_val2
  logic [REG_DATA_W-1:0]entry_eth_2in3_dummy_val2_default;
  assign entry_eth_2in3_dummy_val2_default = 'h25252525;
//-- Default entry_eth_2in3_dummy_val3
  logic [REG_DATA_W-1:0]entry_eth_2in3_dummy_val3_default;
  assign entry_eth_2in3_dummy_val3_default = 'h35353535;
//-- Default line_parameter
  line_parameter_t line_parameter_default;
  always_comb begin
    line_parameter_default = 'h0;
    line_parameter_default.select = 'h0;
    line_parameter_default.loopback = 'h0;
    line_parameter_default.rate = 'h0;
  end
//-- Default reset_datapath
  reset_datapath_t reset_datapath_default;
  always_comb begin
    reset_datapath_default = 'h0;
    reset_datapath_default.gt_all = 'h0;
    reset_datapath_default.tx_rst = 'h0;
    reset_datapath_default.rx_rst = 'h0;
  end
//-- Default reset_monitor
  reset_monitor_t reset_monitor_default;
  always_comb begin
    reset_monitor_default = 'h0;
    reset_monitor_default.rst_done = 'h0;
  end
//-- Default fifo_write_number_of_words
  logic [REG_DATA_W-1:0]fifo_write_number_of_words_default;
  assign fifo_write_number_of_words_default = 'h0;
//-- Default fifo_write_words_to_write_a
  logic [REG_DATA_W-1:0]fifo_write_words_to_write_a_default;
  assign fifo_write_words_to_write_a_default = 'h0;
//-- Default fifo_write_words_to_write_b
  logic [REG_DATA_W-1:0]fifo_write_words_to_write_b_default;
  assign fifo_write_words_to_write_b_default = 'h0;
//-- Default fifo_write_fifo_write_data_count
  logic [REG_DATA_W-1:0]fifo_write_fifo_write_data_count_default;
  assign fifo_write_fifo_write_data_count_default = 'h0;
//-- Default fifo_read_words_to_read_a
  logic [REG_DATA_W-1:0]fifo_read_words_to_read_a_default;
  assign fifo_read_words_to_read_a_default = 'h0;
//-- Default fifo_read_words_to_read_b
  logic [REG_DATA_W-1:0]fifo_read_words_to_read_b_default;
  assign fifo_read_words_to_read_b_default = 'h0;
//-- Default fifo_read_fifo_read_data_count
  logic [REG_DATA_W-1:0]fifo_read_fifo_read_data_count_default;
  assign fifo_read_fifo_read_data_count_default = 'h0;
// ============================================================================================== --
// Write reg
// ============================================================================================== --
  // To ease the code, use REG_DATA_W as register size.
  // Unused bits will be simplified by the synthesizer
// Register FF: line_parameter
  logic [REG_DATA_W-1:0] r_line_parameterD;
  assign r_line_parameterD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == LINE_PARAMETER_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_line_parameter;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_line_parameter       <= line_parameter_default;
    end
    else begin
      r_line_parameter       <= r_line_parameterD;
    end
  end
// Register FF: reset_datapath
  logic [REG_DATA_W-1:0] r_reset_datapathD;
  assign r_reset_datapathD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == RESET_DATAPATH_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_reset_datapath;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_reset_datapath       <= reset_datapath_default;
    end
    else begin
      r_reset_datapath       <= r_reset_datapathD;
    end
  end
// Register FF: reset_monitor
  logic [REG_DATA_W-1:0] r_reset_monitorD;
  assign r_reset_monitorD       = r_reset_monitor_upd;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_reset_monitor       <= reset_monitor_default;
    end
    else begin
      r_reset_monitor       <= r_reset_monitorD;
    end
  end
// Register FF: fifo_write_number_of_words
  logic [REG_DATA_W-1:0] r_fifo_write_number_of_wordsD;
  assign r_fifo_write_number_of_wordsD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == FIFO_WRITE_NUMBER_OF_WORDS_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_fifo_write_number_of_words;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_fifo_write_number_of_words       <= fifo_write_number_of_words_default;
    end
    else begin
      r_fifo_write_number_of_words       <= r_fifo_write_number_of_wordsD;
    end
  end
// Register FF: fifo_write_words_to_write_a
  logic [REG_DATA_W-1:0] r_fifo_write_words_to_write_aD;
  assign r_fifo_write_words_to_write_aD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == FIFO_WRITE_WORDS_TO_WRITE_A_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_fifo_write_words_to_write_a;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_fifo_write_words_to_write_a       <= fifo_write_words_to_write_a_default;
    end
    else begin
      r_fifo_write_words_to_write_a       <= r_fifo_write_words_to_write_aD;
    end
  end
// Register FF: fifo_write_words_to_write_b
  logic [REG_DATA_W-1:0] r_fifo_write_words_to_write_bD;
  assign r_fifo_write_words_to_write_bD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == FIFO_WRITE_WORDS_TO_WRITE_B_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_fifo_write_words_to_write_b;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_fifo_write_words_to_write_b       <= fifo_write_words_to_write_b_default;
    end
    else begin
      r_fifo_write_words_to_write_b       <= r_fifo_write_words_to_write_bD;
    end
  end
// Register FF: fifo_write_fifo_write_data_count
  logic [REG_DATA_W-1:0] r_fifo_write_fifo_write_data_countD;
  assign r_fifo_write_fifo_write_data_countD       = r_fifo_write_fifo_write_data_count_upd;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_fifo_write_fifo_write_data_count       <= fifo_write_fifo_write_data_count_default;
    end
    else begin
      r_fifo_write_fifo_write_data_count       <= r_fifo_write_fifo_write_data_countD;
    end
  end
// Register FF: fifo_read_words_to_read_a
  logic [REG_DATA_W-1:0] r_fifo_read_words_to_read_aD;
  assign r_fifo_read_words_to_read_aD       = r_fifo_read_words_to_read_a_upd;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_fifo_read_words_to_read_a       <= fifo_read_words_to_read_a_default;
    end
    else begin
      r_fifo_read_words_to_read_a       <= r_fifo_read_words_to_read_aD;
    end
  end
// Register FF: fifo_read_words_to_read_b
  logic [REG_DATA_W-1:0] r_fifo_read_words_to_read_bD;
  assign r_fifo_read_words_to_read_bD       = r_fifo_read_words_to_read_b_upd;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_fifo_read_words_to_read_b       <= fifo_read_words_to_read_b_default;
    end
    else begin
      r_fifo_read_words_to_read_b       <= r_fifo_read_words_to_read_bD;
    end
  end
// Register FF: fifo_read_fifo_read_data_count
  logic [REG_DATA_W-1:0] r_fifo_read_fifo_read_data_countD;
  assign r_fifo_read_fifo_read_data_countD       = r_fifo_read_fifo_read_data_count_upd;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_fifo_read_fifo_read_data_count       <= fifo_read_fifo_read_data_count_default;
    end
    else begin
      r_fifo_read_fifo_read_data_count       <= r_fifo_read_fifo_read_data_countD;
    end
  end
// ============================================================================================== --
// Read reg
// ============================================================================================== --
  always_comb begin
    if (axil_rvalid) begin
      axil_rdataD = s_axil_rready ? '0 : axil_rdata;
      axil_rrespD = s_axil_rready ? '0 : axil_rresp;
    end
    else begin
      axil_rdataD = axil_rdata;
      axil_rrespD = axil_rresp;
      if (rd_en) begin
        if (!rd_en_ok) begin
          axil_rdataD = REG_DATA_W'('hDEAD_ADD2);
          axil_rrespD = AXI4_SLVERR;
        end
        else begin
          axil_rrespD = AXI4_OKAY;
          case(rd_add[AXIL_ADD_RANGE_W-1:0])
          ENTRY_ETH_2IN3_DUMMY_VAL0_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register entry_eth_2in3_dummy_val0
            axil_rdataD = entry_eth_2in3_dummy_val0_default;
          end
          ENTRY_ETH_2IN3_DUMMY_VAL1_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register entry_eth_2in3_dummy_val1
            axil_rdataD = entry_eth_2in3_dummy_val1_default;
          end
          ENTRY_ETH_2IN3_DUMMY_VAL2_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register entry_eth_2in3_dummy_val2
            axil_rdataD = entry_eth_2in3_dummy_val2_default;
          end
          ENTRY_ETH_2IN3_DUMMY_VAL3_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register entry_eth_2in3_dummy_val3
            axil_rdataD = entry_eth_2in3_dummy_val3_default;
          end
          LINE_PARAMETER_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register line_parameter
            axil_rdataD = r_line_parameter;
          end
          RESET_DATAPATH_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register reset_datapath
            axil_rdataD = r_reset_datapath;
          end
          RESET_MONITOR_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register reset_monitor
            axil_rdataD = r_reset_monitor;
          end
          FIFO_WRITE_NUMBER_OF_WORDS_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register fifo_write_number_of_words
            axil_rdataD = r_fifo_write_number_of_words;
          end
          FIFO_WRITE_WORDS_TO_WRITE_A_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register fifo_write_words_to_write_a
            axil_rdataD = r_fifo_write_words_to_write_a;
          end
          FIFO_WRITE_WORDS_TO_WRITE_B_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register fifo_write_words_to_write_b
            axil_rdataD = r_fifo_write_words_to_write_b;
          end
          FIFO_WRITE_FIFO_WRITE_DATA_COUNT_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register fifo_write_fifo_write_data_count
            axil_rdataD = r_fifo_write_fifo_write_data_count;
          end
          FIFO_READ_WORDS_TO_READ_A_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register fifo_read_words_to_read_a
            axil_rdataD = r_fifo_read_words_to_read_a;
          end
          FIFO_READ_WORDS_TO_READ_B_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register fifo_read_words_to_read_b
            axil_rdataD = r_fifo_read_words_to_read_b;
          end
          FIFO_READ_FIFO_READ_DATA_COUNT_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register fifo_read_fifo_read_data_count
            axil_rdataD = r_fifo_read_fifo_read_data_count;
          end
          default:
            axil_rdataD = REG_DATA_W'('h0BAD_ADD1); // Default value
          endcase // rd_add
        end
      end // if rd_end
    end
  end // always_comb - read
endmodule
