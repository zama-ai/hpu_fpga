// ============================================================================================== //
// Description  : Axi4-lite register bank
// This file was generated with rust regmap generator:
//  * Date:  2026-01-09
//  * Tool_version: bd49564daf1a99d615cb6dbb121b54bfbeef8b22
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
  // Register IO: mhdma_system_lane
    , output mhdma_system_lane_t r_mhdma_system_lane
  // Register IO: mhdma_system_timeout_notify
    , output mhdma_system_timeout_notify_t r_mhdma_system_timeout_notify
  // Register IO: mhdma_system_timeout_read_req
    , output mhdma_system_timeout_read_req_t r_mhdma_system_timeout_read_req
  // Register IO: mhdma_system_fsm_value
    , output logic [REG_DATA_W-1: 0] r_mhdma_system_fsm_value
    , input  logic [REG_DATA_W-1: 0] r_mhdma_system_fsm_value_upd
  // Register IO: mhdma_reset_datapath
    , output mhdma_reset_datapath_t r_mhdma_reset_datapath
  // Register IO: mhdma_reset_monitor
    , output mhdma_reset_monitor_t r_mhdma_reset_monitor
    , input  mhdma_reset_monitor_t r_mhdma_reset_monitor_upd
  // Register IO: mhdma_hpu_id_zero
    , output logic [REG_DATA_W-1: 0] r_mhdma_hpu_id_zero
  // Register IO: mhdma_hpu_id_one
    , output logic [REG_DATA_W-1: 0] r_mhdma_hpu_id_one
  // Register IO: mhdma_hpu_id_two
    , output logic [REG_DATA_W-1: 0] r_mhdma_hpu_id_two
  // Register IO: mhdma_hpu_id_three
    , output logic [REG_DATA_W-1: 0] r_mhdma_hpu_id_three
  // Register IO: mhdma_hpu_id_four
    , output logic [REG_DATA_W-1: 0] r_mhdma_hpu_id_four
  // Register IO: mhdma_hpu_id_five
    , output logic [REG_DATA_W-1: 0] r_mhdma_hpu_id_five
  // Register IO: mhdma_hpu_id_six
    , output logic [REG_DATA_W-1: 0] r_mhdma_hpu_id_six
  // Register IO: mhdma_hpu_id_seven
    , output logic [REG_DATA_W-1: 0] r_mhdma_hpu_id_seven
  // Register IO: mhdma_request_req_id
    , output mhdma_request_req_id_t r_mhdma_request_req_id
    , output logic r_mhdma_request_req_id_wr_en
  // Register IO: mhdma_request_req_addr
    , output mhdma_request_req_addr_t r_mhdma_request_req_addr
    , output logic r_mhdma_request_req_addr_wr_en
  // Register IO: mhdma_request_notify
    , output mhdma_request_notify_t r_mhdma_request_notify
    , input  mhdma_request_notify_t r_mhdma_request_notify_upd
    , output logic r_mhdma_request_notify_rd_en
  // Register IO: mhdma_request_read_request
    , output mhdma_request_read_request_t r_mhdma_request_read_request
    , input  mhdma_request_read_request_t r_mhdma_request_read_request_upd
    , output logic r_mhdma_request_read_request_rd_en
  // Register IO: mhdma_request_stat_notify
    , output logic [REG_DATA_W-1: 0] r_mhdma_request_stat_notify
    , input  logic [REG_DATA_W-1: 0] r_mhdma_request_stat_notify_upd
    , output logic r_mhdma_request_stat_notify_rd_en
  // Register IO: mhdma_request_stat_notify_ack
    , output logic [REG_DATA_W-1: 0] r_mhdma_request_stat_notify_ack
    , input  logic [REG_DATA_W-1: 0] r_mhdma_request_stat_notify_ack_upd
    , output logic r_mhdma_request_stat_notify_ack_rd_en
  // Register IO: mhdma_request_stat_notify_timeout_retry
    , output logic [REG_DATA_W-1: 0] r_mhdma_request_stat_notify_timeout_retry
    , input  logic [REG_DATA_W-1: 0] r_mhdma_request_stat_notify_timeout_retry_upd
    , output logic r_mhdma_request_stat_notify_timeout_retry_rd_en
  // Register IO: mhdma_request_stat_nb_nack_received
    , output logic [REG_DATA_W-1: 0] r_mhdma_request_stat_nb_nack_received
    , input  logic [REG_DATA_W-1: 0] r_mhdma_request_stat_nb_nack_received_upd
    , output logic r_mhdma_request_stat_nb_nack_received_rd_en
  // Register IO: mhdma_request_stat_nb_notify_received
    , output logic [REG_DATA_W-1: 0] r_mhdma_request_stat_nb_notify_received
    , input  logic [REG_DATA_W-1: 0] r_mhdma_request_stat_nb_notify_received_upd
    , output logic r_mhdma_request_stat_nb_notify_received_rd_en
  // Register IO: mhdma_request_stat_nb_read_req_received
    , output logic [REG_DATA_W-1: 0] r_mhdma_request_stat_nb_read_req_received
    , input  logic [REG_DATA_W-1: 0] r_mhdma_request_stat_nb_read_req_received_upd
    , output logic r_mhdma_request_stat_nb_read_req_received_rd_en
  // Register IO: mhdma_request_stat_nb_ce_received
    , output logic [REG_DATA_W-1: 0] r_mhdma_request_stat_nb_ce_received
    , input  logic [REG_DATA_W-1: 0] r_mhdma_request_stat_nb_ce_received_upd
    , output logic r_mhdma_request_stat_nb_ce_received_rd_en
  // Register IO: mhdma_request_stat_nb_read_to_hbm
    , output logic [REG_DATA_W-1: 0] r_mhdma_request_stat_nb_read_to_hbm
    , input  logic [REG_DATA_W-1: 0] r_mhdma_request_stat_nb_read_to_hbm_upd
    , output logic r_mhdma_request_stat_nb_read_to_hbm_rd_en
  // Register IO: mhdma_request_stat_nb_words_received_pc_pc0
    , output logic [REG_DATA_W-1: 0] r_mhdma_request_stat_nb_words_received_pc_pc0
    , input  logic [REG_DATA_W-1: 0] r_mhdma_request_stat_nb_words_received_pc_pc0_upd
    , output logic r_mhdma_request_stat_nb_words_received_pc_pc0_rd_en
  // Register IO: mhdma_request_stat_nb_words_received_pc_pc1
    , output logic [REG_DATA_W-1: 0] r_mhdma_request_stat_nb_words_received_pc_pc1
    , input  logic [REG_DATA_W-1: 0] r_mhdma_request_stat_nb_words_received_pc_pc1_upd
    , output logic r_mhdma_request_stat_nb_words_received_pc_pc1_rd_en
  // Register IO: mhdma_request_stat_nb_ce_words_received
    , output logic [REG_DATA_W-1: 0] r_mhdma_request_stat_nb_ce_words_received
    , input  logic [REG_DATA_W-1: 0] r_mhdma_request_stat_nb_ce_words_received_upd
    , output logic r_mhdma_request_stat_nb_ce_words_received_rd_en
  // Register IO: mhdma_request_stat_t_notify_to_ack
    , output logic [REG_DATA_W-1: 0] r_mhdma_request_stat_t_notify_to_ack
    , input  logic [REG_DATA_W-1: 0] r_mhdma_request_stat_t_notify_to_ack_upd
  // Register IO: mhdma_request_stat_t_rr_to_ce_received
    , output logic [REG_DATA_W-1: 0] r_mhdma_request_stat_t_rr_to_ce_received
    , input  logic [REG_DATA_W-1: 0] r_mhdma_request_stat_t_rr_to_ce_received_upd
  // Register IO: mhdma_request_stat_t_ce_first_to_last_pkt
    , output logic [REG_DATA_W-1: 0] r_mhdma_request_stat_t_ce_first_to_last_pkt
    , input  logic [REG_DATA_W-1: 0] r_mhdma_request_stat_t_ce_first_to_last_pkt_upd
  // Register IO: mhdma_request_stat_t_rr_wait_words_pc_pc0
    , output logic [REG_DATA_W-1: 0] r_mhdma_request_stat_t_rr_wait_words_pc_pc0
    , input  logic [REG_DATA_W-1: 0] r_mhdma_request_stat_t_rr_wait_words_pc_pc0_upd
  // Register IO: mhdma_request_stat_t_rr_wait_words_pc_pc1
    , output logic [REG_DATA_W-1: 0] r_mhdma_request_stat_t_rr_wait_words_pc_pc1
    , input  logic [REG_DATA_W-1: 0] r_mhdma_request_stat_t_rr_wait_words_pc_pc1_upd
  // Register IO: mhdma_request_stat_notify_timeout
    , output logic [REG_DATA_W-1: 0] r_mhdma_request_stat_notify_timeout
    , input  logic [REG_DATA_W-1: 0] r_mhdma_request_stat_notify_timeout_upd
    , output logic r_mhdma_request_stat_notify_timeout_rd_en
  // Register IO: mhdma_request_stat_physical_addr_pc0_lsb
    , output logic [REG_DATA_W-1: 0] r_mhdma_request_stat_physical_addr_pc0_lsb
    , input  logic [REG_DATA_W-1: 0] r_mhdma_request_stat_physical_addr_pc0_lsb_upd
  // Register IO: mhdma_request_stat_physical_addr_pc0_msb
    , output logic [REG_DATA_W-1: 0] r_mhdma_request_stat_physical_addr_pc0_msb
    , input  logic [REG_DATA_W-1: 0] r_mhdma_request_stat_physical_addr_pc0_msb_upd
  // Register IO: mhdma_request_stat_physical_addr_pc1_lsb
    , output logic [REG_DATA_W-1: 0] r_mhdma_request_stat_physical_addr_pc1_lsb
    , input  logic [REG_DATA_W-1: 0] r_mhdma_request_stat_physical_addr_pc1_lsb_upd
  // Register IO: mhdma_request_stat_physical_addr_pc1_msb
    , output logic [REG_DATA_W-1: 0] r_mhdma_request_stat_physical_addr_pc1_msb
    , input  logic [REG_DATA_W-1: 0] r_mhdma_request_stat_physical_addr_pc1_msb_upd
  // Register IO: mhdma_request_stat_cnt_nb_write_complete
    , output logic [REG_DATA_W-1: 0] r_mhdma_request_stat_cnt_nb_write_complete
    , input  logic [REG_DATA_W-1: 0] r_mhdma_request_stat_cnt_nb_write_complete_upd
  // Register IO: mhdma_lane_debug
    , output mhdma_lane_debug_t r_mhdma_lane_debug
  // Register IO: mhdma_hbm_axi4_addr_2in3_ct_pc0_lsb
    , output logic [REG_DATA_W-1: 0] r_mhdma_hbm_axi4_addr_2in3_ct_pc0_lsb
  // Register IO: mhdma_hbm_axi4_addr_2in3_ct_pc0_msb
    , output logic [REG_DATA_W-1: 0] r_mhdma_hbm_axi4_addr_2in3_ct_pc0_msb
  // Register IO: mhdma_hbm_axi4_addr_2in3_ct_pc1_lsb
    , output logic [REG_DATA_W-1: 0] r_mhdma_hbm_axi4_addr_2in3_ct_pc1_lsb
  // Register IO: mhdma_hbm_axi4_addr_2in3_ct_pc1_msb
    , output logic [REG_DATA_W-1: 0] r_mhdma_hbm_axi4_addr_2in3_ct_pc1_msb
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
  // Register IO: cnt_trig_rd
    , output logic [REG_DATA_W-1: 0] r_cnt_trig_rd
    , input  logic [REG_DATA_W-1: 0] r_cnt_trig_rd_upd
  // Register IO: cnt_tx_wr
    , output logic [REG_DATA_W-1: 0] r_cnt_tx_wr
    , input  logic [REG_DATA_W-1: 0] r_cnt_tx_wr_upd
  // Register IO: cnt_words
    , output logic [REG_DATA_W-1: 0] r_cnt_words
    , input  logic [REG_DATA_W-1: 0] r_cnt_words_upd
  // Register IO: mhdma_stat_status
    , output logic [REG_DATA_W-1: 0] r_mhdma_stat_status
    , input  logic [REG_DATA_W-1: 0] r_mhdma_stat_status_upd
  // Register IO: mhdma_stat_clk_a
    , output logic [REG_DATA_W-1: 0] r_mhdma_stat_clk_a
    , input  logic [REG_DATA_W-1: 0] r_mhdma_stat_clk_a_upd
  // Register IO: mhdma_stat_clk_b
    , output logic [REG_DATA_W-1: 0] r_mhdma_stat_clk_b
    , input  logic [REG_DATA_W-1: 0] r_mhdma_stat_clk_b_upd
  // Register IO: mhdma_stat_valid_words_a
    , output logic [REG_DATA_W-1: 0] r_mhdma_stat_valid_words_a
    , input  logic [REG_DATA_W-1: 0] r_mhdma_stat_valid_words_a_upd
  // Register IO: mhdma_stat_valid_words_b
    , output logic [REG_DATA_W-1: 0] r_mhdma_stat_valid_words_b
    , input  logic [REG_DATA_W-1: 0] r_mhdma_stat_valid_words_b_upd
  // Register IO: mhdma_stat_sop_cnt_a
    , output logic [REG_DATA_W-1: 0] r_mhdma_stat_sop_cnt_a
    , input  logic [REG_DATA_W-1: 0] r_mhdma_stat_sop_cnt_a_upd
  // Register IO: mhdma_stat_sop_cnt_b
    , output logic [REG_DATA_W-1: 0] r_mhdma_stat_sop_cnt_b
    , input  logic [REG_DATA_W-1: 0] r_mhdma_stat_sop_cnt_b_upd
);
// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int AXIL_ADD_OFS = 'h50000;
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
//-- Default mhdma_system_lane
  mhdma_system_lane_t mhdma_system_lane_default;
  always_comb begin
    mhdma_system_lane_default = 'h0;
    mhdma_system_lane_default.select = 'h0;
    mhdma_system_lane_default.loopback = 'h0;
    mhdma_system_lane_default.rate = 'h0;
    mhdma_system_lane_default.debug = 'h0;
  end
//-- Default mhdma_system_timeout_notify
  mhdma_system_timeout_notify_t mhdma_system_timeout_notify_default;
  always_comb begin
    mhdma_system_timeout_notify_default = 'h0;
    mhdma_system_timeout_notify_default.notify_timeout_dur = 'h48000000;
  end
//-- Default mhdma_system_timeout_read_req
  mhdma_system_timeout_read_req_t mhdma_system_timeout_read_req_default;
  always_comb begin
    mhdma_system_timeout_read_req_default = 'h0;
    mhdma_system_timeout_read_req_default.read_req_timeout_dur = 'h48000000;
  end
//-- Default mhdma_system_fsm_value
  logic [REG_DATA_W-1:0]mhdma_system_fsm_value_default;
  assign mhdma_system_fsm_value_default = 'h0;
//-- Default mhdma_reset_datapath
  mhdma_reset_datapath_t mhdma_reset_datapath_default;
  always_comb begin
    mhdma_reset_datapath_default = 'h0;
    mhdma_reset_datapath_default.gt_all = 'h0;
    mhdma_reset_datapath_default.tx_rst = 'h0;
    mhdma_reset_datapath_default.rx_rst = 'h0;
  end
//-- Default mhdma_reset_monitor
  mhdma_reset_monitor_t mhdma_reset_monitor_default;
  always_comb begin
    mhdma_reset_monitor_default = 'h0;
    mhdma_reset_monitor_default.rst_done = 'h0;
  end
//-- Default mhdma_hpu_id_zero
  logic [REG_DATA_W-1:0]mhdma_hpu_id_zero_default;
  assign mhdma_hpu_id_zero_default = 'h0;
//-- Default mhdma_hpu_id_one
  logic [REG_DATA_W-1:0]mhdma_hpu_id_one_default;
  assign mhdma_hpu_id_one_default = 'h0;
//-- Default mhdma_hpu_id_two
  logic [REG_DATA_W-1:0]mhdma_hpu_id_two_default;
  assign mhdma_hpu_id_two_default = 'h0;
//-- Default mhdma_hpu_id_three
  logic [REG_DATA_W-1:0]mhdma_hpu_id_three_default;
  assign mhdma_hpu_id_three_default = 'h0;
//-- Default mhdma_hpu_id_four
  logic [REG_DATA_W-1:0]mhdma_hpu_id_four_default;
  assign mhdma_hpu_id_four_default = 'h0;
//-- Default mhdma_hpu_id_five
  logic [REG_DATA_W-1:0]mhdma_hpu_id_five_default;
  assign mhdma_hpu_id_five_default = 'h0;
//-- Default mhdma_hpu_id_six
  logic [REG_DATA_W-1:0]mhdma_hpu_id_six_default;
  assign mhdma_hpu_id_six_default = 'h0;
//-- Default mhdma_hpu_id_seven
  logic [REG_DATA_W-1:0]mhdma_hpu_id_seven_default;
  assign mhdma_hpu_id_seven_default = 'h0;
//-- Default mhdma_request_req_id
  mhdma_request_req_id_t mhdma_request_req_id_default;
  always_comb begin
    mhdma_request_req_id_default = 'h0;
    mhdma_request_req_id_default.size_b = 'h4000;
    mhdma_request_req_id_default.node_id = 'h0;
    mhdma_request_req_id_default.req_id = 'h0;
    mhdma_request_req_id_default.iop_id = 'h0;
  end
//-- Default mhdma_request_req_addr
  mhdma_request_req_addr_t mhdma_request_req_addr_default;
  always_comb begin
    mhdma_request_req_addr_default = 'h0;
    mhdma_request_req_addr_default.src = 'h0;
    mhdma_request_req_addr_default.dst = 'h0;
  end
//-- Default mhdma_request_notify
  mhdma_request_notify_t mhdma_request_notify_default;
  always_comb begin
    mhdma_request_notify_default = 'h0;
    mhdma_request_notify_default.iop_id = 'h0;
    mhdma_request_notify_default.node_id = 'h0;
    mhdma_request_notify_default.src_addr = 'h0;
  end
//-- Default mhdma_request_read_request
  mhdma_request_read_request_t mhdma_request_read_request_default;
  always_comb begin
    mhdma_request_read_request_default = 'h0;
    mhdma_request_read_request_default.iop_id = 'h0;
    mhdma_request_read_request_default.node_id = 'h0;
    mhdma_request_read_request_default.dst_addr = 'h0;
  end
//-- Default mhdma_request_stat_notify
  logic [REG_DATA_W-1:0]mhdma_request_stat_notify_default;
  assign mhdma_request_stat_notify_default = 'h0;
//-- Default mhdma_request_stat_notify_ack
  logic [REG_DATA_W-1:0]mhdma_request_stat_notify_ack_default;
  assign mhdma_request_stat_notify_ack_default = 'h0;
//-- Default mhdma_request_stat_notify_timeout_retry
  logic [REG_DATA_W-1:0]mhdma_request_stat_notify_timeout_retry_default;
  assign mhdma_request_stat_notify_timeout_retry_default = 'h0;
//-- Default mhdma_request_stat_nb_nack_received
  logic [REG_DATA_W-1:0]mhdma_request_stat_nb_nack_received_default;
  assign mhdma_request_stat_nb_nack_received_default = 'h0;
//-- Default mhdma_request_stat_nb_notify_received
  logic [REG_DATA_W-1:0]mhdma_request_stat_nb_notify_received_default;
  assign mhdma_request_stat_nb_notify_received_default = 'h0;
//-- Default mhdma_request_stat_nb_read_req_received
  logic [REG_DATA_W-1:0]mhdma_request_stat_nb_read_req_received_default;
  assign mhdma_request_stat_nb_read_req_received_default = 'h0;
//-- Default mhdma_request_stat_nb_ce_received
  logic [REG_DATA_W-1:0]mhdma_request_stat_nb_ce_received_default;
  assign mhdma_request_stat_nb_ce_received_default = 'h0;
//-- Default mhdma_request_stat_nb_read_to_hbm
  logic [REG_DATA_W-1:0]mhdma_request_stat_nb_read_to_hbm_default;
  assign mhdma_request_stat_nb_read_to_hbm_default = 'h0;
//-- Default mhdma_request_stat_nb_words_received_pc_pc0
  logic [REG_DATA_W-1:0]mhdma_request_stat_nb_words_received_pc_pc0_default;
  assign mhdma_request_stat_nb_words_received_pc_pc0_default = 'h0;
//-- Default mhdma_request_stat_nb_words_received_pc_pc1
  logic [REG_DATA_W-1:0]mhdma_request_stat_nb_words_received_pc_pc1_default;
  assign mhdma_request_stat_nb_words_received_pc_pc1_default = 'h0;
//-- Default mhdma_request_stat_nb_ce_words_received
  logic [REG_DATA_W-1:0]mhdma_request_stat_nb_ce_words_received_default;
  assign mhdma_request_stat_nb_ce_words_received_default = 'h0;
//-- Default mhdma_request_stat_t_notify_to_ack
  logic [REG_DATA_W-1:0]mhdma_request_stat_t_notify_to_ack_default;
  assign mhdma_request_stat_t_notify_to_ack_default = 'h0;
//-- Default mhdma_request_stat_t_rr_to_ce_received
  logic [REG_DATA_W-1:0]mhdma_request_stat_t_rr_to_ce_received_default;
  assign mhdma_request_stat_t_rr_to_ce_received_default = 'h0;
//-- Default mhdma_request_stat_t_ce_first_to_last_pkt
  logic [REG_DATA_W-1:0]mhdma_request_stat_t_ce_first_to_last_pkt_default;
  assign mhdma_request_stat_t_ce_first_to_last_pkt_default = 'h0;
//-- Default mhdma_request_stat_t_rr_wait_words_pc_pc0
  logic [REG_DATA_W-1:0]mhdma_request_stat_t_rr_wait_words_pc_pc0_default;
  assign mhdma_request_stat_t_rr_wait_words_pc_pc0_default = 'h0;
//-- Default mhdma_request_stat_t_rr_wait_words_pc_pc1
  logic [REG_DATA_W-1:0]mhdma_request_stat_t_rr_wait_words_pc_pc1_default;
  assign mhdma_request_stat_t_rr_wait_words_pc_pc1_default = 'h0;
//-- Default mhdma_request_stat_notify_timeout
  logic [REG_DATA_W-1:0]mhdma_request_stat_notify_timeout_default;
  assign mhdma_request_stat_notify_timeout_default = 'h0;
//-- Default mhdma_request_stat_physical_addr_pc0_lsb
  logic [REG_DATA_W-1:0]mhdma_request_stat_physical_addr_pc0_lsb_default;
  assign mhdma_request_stat_physical_addr_pc0_lsb_default = 'h0;
//-- Default mhdma_request_stat_physical_addr_pc0_msb
  logic [REG_DATA_W-1:0]mhdma_request_stat_physical_addr_pc0_msb_default;
  assign mhdma_request_stat_physical_addr_pc0_msb_default = 'h0;
//-- Default mhdma_request_stat_physical_addr_pc1_lsb
  logic [REG_DATA_W-1:0]mhdma_request_stat_physical_addr_pc1_lsb_default;
  assign mhdma_request_stat_physical_addr_pc1_lsb_default = 'h0;
//-- Default mhdma_request_stat_physical_addr_pc1_msb
  logic [REG_DATA_W-1:0]mhdma_request_stat_physical_addr_pc1_msb_default;
  assign mhdma_request_stat_physical_addr_pc1_msb_default = 'h0;
//-- Default mhdma_request_stat_cnt_nb_write_complete
  logic [REG_DATA_W-1:0]mhdma_request_stat_cnt_nb_write_complete_default;
  assign mhdma_request_stat_cnt_nb_write_complete_default = 'h0;
//-- Default mhdma_lane_debug
  mhdma_lane_debug_t mhdma_lane_debug_default;
  always_comb begin
    mhdma_lane_debug_default = 'h0;
    mhdma_lane_debug_default.rx_to_tx = 'h0;
    mhdma_lane_debug_default.tx_loop = 'h0;
    mhdma_lane_debug_default.reset_registers = 'h0;
  end
//-- Default mhdma_hbm_axi4_addr_2in3_ct_pc0_lsb
  logic [REG_DATA_W-1:0]mhdma_hbm_axi4_addr_2in3_ct_pc0_lsb_default;
  assign mhdma_hbm_axi4_addr_2in3_ct_pc0_lsb_default = 'h0;
//-- Default mhdma_hbm_axi4_addr_2in3_ct_pc0_msb
  logic [REG_DATA_W-1:0]mhdma_hbm_axi4_addr_2in3_ct_pc0_msb_default;
  assign mhdma_hbm_axi4_addr_2in3_ct_pc0_msb_default = 'h0;
//-- Default mhdma_hbm_axi4_addr_2in3_ct_pc1_lsb
  logic [REG_DATA_W-1:0]mhdma_hbm_axi4_addr_2in3_ct_pc1_lsb_default;
  assign mhdma_hbm_axi4_addr_2in3_ct_pc1_lsb_default = 'h0;
//-- Default mhdma_hbm_axi4_addr_2in3_ct_pc1_msb
  logic [REG_DATA_W-1:0]mhdma_hbm_axi4_addr_2in3_ct_pc1_msb_default;
  assign mhdma_hbm_axi4_addr_2in3_ct_pc1_msb_default = 'h0;
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
//-- Default cnt_trig_rd
  logic [REG_DATA_W-1:0]cnt_trig_rd_default;
  assign cnt_trig_rd_default = 'h0;
//-- Default cnt_tx_wr
  logic [REG_DATA_W-1:0]cnt_tx_wr_default;
  assign cnt_tx_wr_default = 'h0;
//-- Default cnt_words
  logic [REG_DATA_W-1:0]cnt_words_default;
  assign cnt_words_default = 'h0;
//-- Default mhdma_stat_status
  logic [REG_DATA_W-1:0]mhdma_stat_status_default;
  assign mhdma_stat_status_default = 'h0;
//-- Default mhdma_stat_clk_a
  logic [REG_DATA_W-1:0]mhdma_stat_clk_a_default;
  assign mhdma_stat_clk_a_default = 'h0;
//-- Default mhdma_stat_clk_b
  logic [REG_DATA_W-1:0]mhdma_stat_clk_b_default;
  assign mhdma_stat_clk_b_default = 'h0;
//-- Default mhdma_stat_valid_words_a
  logic [REG_DATA_W-1:0]mhdma_stat_valid_words_a_default;
  assign mhdma_stat_valid_words_a_default = 'h0;
//-- Default mhdma_stat_valid_words_b
  logic [REG_DATA_W-1:0]mhdma_stat_valid_words_b_default;
  assign mhdma_stat_valid_words_b_default = 'h0;
//-- Default mhdma_stat_sop_cnt_a
  logic [REG_DATA_W-1:0]mhdma_stat_sop_cnt_a_default;
  assign mhdma_stat_sop_cnt_a_default = 'h0;
//-- Default mhdma_stat_sop_cnt_b
  logic [REG_DATA_W-1:0]mhdma_stat_sop_cnt_b_default;
  assign mhdma_stat_sop_cnt_b_default = 'h0;
// ============================================================================================== --
// Write reg
// ============================================================================================== --
  // To ease the code, use REG_DATA_W as register size.
  // Unused bits will be simplified by the synthesizer
// Register FF: mhdma_system_lane
  logic [REG_DATA_W-1:0] r_mhdma_system_laneD;
  assign r_mhdma_system_laneD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == MHDMA_SYSTEM_LANE_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_mhdma_system_lane;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_mhdma_system_lane       <= mhdma_system_lane_default;
    end
    else begin
      r_mhdma_system_lane       <= r_mhdma_system_laneD;
    end
  end
// Register FF: mhdma_system_timeout_notify
  logic [REG_DATA_W-1:0] r_mhdma_system_timeout_notifyD;
  assign r_mhdma_system_timeout_notifyD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == MHDMA_SYSTEM_TIMEOUT_NOTIFY_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_mhdma_system_timeout_notify;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_mhdma_system_timeout_notify       <= mhdma_system_timeout_notify_default;
    end
    else begin
      r_mhdma_system_timeout_notify       <= r_mhdma_system_timeout_notifyD;
    end
  end
// Register FF: mhdma_system_timeout_read_req
  logic [REG_DATA_W-1:0] r_mhdma_system_timeout_read_reqD;
  assign r_mhdma_system_timeout_read_reqD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == MHDMA_SYSTEM_TIMEOUT_READ_REQ_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_mhdma_system_timeout_read_req;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_mhdma_system_timeout_read_req       <= mhdma_system_timeout_read_req_default;
    end
    else begin
      r_mhdma_system_timeout_read_req       <= r_mhdma_system_timeout_read_reqD;
    end
  end
// Register FF: mhdma_system_fsm_value
  logic [REG_DATA_W-1:0] r_mhdma_system_fsm_valueD;
  assign r_mhdma_system_fsm_valueD       = r_mhdma_system_fsm_value_upd;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_mhdma_system_fsm_value       <= mhdma_system_fsm_value_default;
    end
    else begin
      r_mhdma_system_fsm_value       <= r_mhdma_system_fsm_valueD;
    end
  end
// Register FF: mhdma_reset_datapath
  logic [REG_DATA_W-1:0] r_mhdma_reset_datapathD;
  assign r_mhdma_reset_datapathD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == MHDMA_RESET_DATAPATH_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_mhdma_reset_datapath;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_mhdma_reset_datapath       <= mhdma_reset_datapath_default;
    end
    else begin
      r_mhdma_reset_datapath       <= r_mhdma_reset_datapathD;
    end
  end
// Register FF: mhdma_reset_monitor
  logic [REG_DATA_W-1:0] r_mhdma_reset_monitorD;
  assign r_mhdma_reset_monitorD       = r_mhdma_reset_monitor_upd;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_mhdma_reset_monitor       <= mhdma_reset_monitor_default;
    end
    else begin
      r_mhdma_reset_monitor       <= r_mhdma_reset_monitorD;
    end
  end
// Register FF: mhdma_hpu_id_zero
  logic [REG_DATA_W-1:0] r_mhdma_hpu_id_zeroD;
  assign r_mhdma_hpu_id_zeroD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == MHDMA_HPU_ID_ZERO_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_mhdma_hpu_id_zero;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_mhdma_hpu_id_zero       <= mhdma_hpu_id_zero_default;
    end
    else begin
      r_mhdma_hpu_id_zero       <= r_mhdma_hpu_id_zeroD;
    end
  end
// Register FF: mhdma_hpu_id_one
  logic [REG_DATA_W-1:0] r_mhdma_hpu_id_oneD;
  assign r_mhdma_hpu_id_oneD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == MHDMA_HPU_ID_ONE_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_mhdma_hpu_id_one;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_mhdma_hpu_id_one       <= mhdma_hpu_id_one_default;
    end
    else begin
      r_mhdma_hpu_id_one       <= r_mhdma_hpu_id_oneD;
    end
  end
// Register FF: mhdma_hpu_id_two
  logic [REG_DATA_W-1:0] r_mhdma_hpu_id_twoD;
  assign r_mhdma_hpu_id_twoD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == MHDMA_HPU_ID_TWO_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_mhdma_hpu_id_two;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_mhdma_hpu_id_two       <= mhdma_hpu_id_two_default;
    end
    else begin
      r_mhdma_hpu_id_two       <= r_mhdma_hpu_id_twoD;
    end
  end
// Register FF: mhdma_hpu_id_three
  logic [REG_DATA_W-1:0] r_mhdma_hpu_id_threeD;
  assign r_mhdma_hpu_id_threeD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == MHDMA_HPU_ID_THREE_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_mhdma_hpu_id_three;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_mhdma_hpu_id_three       <= mhdma_hpu_id_three_default;
    end
    else begin
      r_mhdma_hpu_id_three       <= r_mhdma_hpu_id_threeD;
    end
  end
// Register FF: mhdma_hpu_id_four
  logic [REG_DATA_W-1:0] r_mhdma_hpu_id_fourD;
  assign r_mhdma_hpu_id_fourD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == MHDMA_HPU_ID_FOUR_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_mhdma_hpu_id_four;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_mhdma_hpu_id_four       <= mhdma_hpu_id_four_default;
    end
    else begin
      r_mhdma_hpu_id_four       <= r_mhdma_hpu_id_fourD;
    end
  end
// Register FF: mhdma_hpu_id_five
  logic [REG_DATA_W-1:0] r_mhdma_hpu_id_fiveD;
  assign r_mhdma_hpu_id_fiveD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == MHDMA_HPU_ID_FIVE_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_mhdma_hpu_id_five;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_mhdma_hpu_id_five       <= mhdma_hpu_id_five_default;
    end
    else begin
      r_mhdma_hpu_id_five       <= r_mhdma_hpu_id_fiveD;
    end
  end
// Register FF: mhdma_hpu_id_six
  logic [REG_DATA_W-1:0] r_mhdma_hpu_id_sixD;
  assign r_mhdma_hpu_id_sixD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == MHDMA_HPU_ID_SIX_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_mhdma_hpu_id_six;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_mhdma_hpu_id_six       <= mhdma_hpu_id_six_default;
    end
    else begin
      r_mhdma_hpu_id_six       <= r_mhdma_hpu_id_sixD;
    end
  end
// Register FF: mhdma_hpu_id_seven
  logic [REG_DATA_W-1:0] r_mhdma_hpu_id_sevenD;
  assign r_mhdma_hpu_id_sevenD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == MHDMA_HPU_ID_SEVEN_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_mhdma_hpu_id_seven;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_mhdma_hpu_id_seven       <= mhdma_hpu_id_seven_default;
    end
    else begin
      r_mhdma_hpu_id_seven       <= r_mhdma_hpu_id_sevenD;
    end
  end
// Register FF: mhdma_request_req_id
  logic [REG_DATA_W-1:0] r_mhdma_request_req_idD;
  assign r_mhdma_request_req_idD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == MHDMA_REQUEST_REQ_ID_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_mhdma_request_req_id;
  logic r_mhdma_request_req_id_wr_enD;
  assign r_mhdma_request_req_id_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == MHDMA_REQUEST_REQ_ID_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_mhdma_request_req_id_wr_en <= 1'b0;
    end
    else begin
      r_mhdma_request_req_id_wr_en <= r_mhdma_request_req_id_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_mhdma_request_req_id       <= mhdma_request_req_id_default;
    end
    else begin
      r_mhdma_request_req_id       <= r_mhdma_request_req_idD;
    end
  end
// Register FF: mhdma_request_req_addr
  logic [REG_DATA_W-1:0] r_mhdma_request_req_addrD;
  assign r_mhdma_request_req_addrD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == MHDMA_REQUEST_REQ_ADDR_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_mhdma_request_req_addr;
  logic r_mhdma_request_req_addr_wr_enD;
  assign r_mhdma_request_req_addr_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == MHDMA_REQUEST_REQ_ADDR_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_mhdma_request_req_addr_wr_en <= 1'b0;
    end
    else begin
      r_mhdma_request_req_addr_wr_en <= r_mhdma_request_req_addr_wr_enD;
    end
  end
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_mhdma_request_req_addr       <= mhdma_request_req_addr_default;
    end
    else begin
      r_mhdma_request_req_addr       <= r_mhdma_request_req_addrD;
    end
  end
// Register FF: mhdma_request_notify
  logic [REG_DATA_W-1:0] r_mhdma_request_notifyD;
  assign r_mhdma_request_notifyD       = r_mhdma_request_notify_upd;
  assign r_mhdma_request_notify_rd_en = rd_en_ok && (rd_add[AXIL_ADD_RANGE_W-1:0] == MHDMA_REQUEST_NOTIFY_OFS[AXIL_ADD_RANGE_W-1:0]);
  assign r_mhdma_request_notify = r_mhdma_request_notify_upd;
// Register FF: mhdma_request_read_request
  logic [REG_DATA_W-1:0] r_mhdma_request_read_requestD;
  assign r_mhdma_request_read_requestD       = r_mhdma_request_read_request_upd;
  assign r_mhdma_request_read_request_rd_en = rd_en_ok && (rd_add[AXIL_ADD_RANGE_W-1:0] == MHDMA_REQUEST_READ_REQUEST_OFS[AXIL_ADD_RANGE_W-1:0]);
  assign r_mhdma_request_read_request = r_mhdma_request_read_request_upd;
// Register FF: mhdma_request_stat_notify
  logic [REG_DATA_W-1:0] r_mhdma_request_stat_notifyD;
  assign r_mhdma_request_stat_notifyD       = r_mhdma_request_stat_notify_upd;
  assign r_mhdma_request_stat_notify_rd_en = rd_en_ok && (rd_add[AXIL_ADD_RANGE_W-1:0] == MHDMA_REQUEST_STAT_NOTIFY_OFS[AXIL_ADD_RANGE_W-1:0]);
  assign r_mhdma_request_stat_notify = r_mhdma_request_stat_notify_upd;
// Register FF: mhdma_request_stat_notify_ack
  logic [REG_DATA_W-1:0] r_mhdma_request_stat_notify_ackD;
  assign r_mhdma_request_stat_notify_ackD       = r_mhdma_request_stat_notify_ack_upd;
  assign r_mhdma_request_stat_notify_ack_rd_en = rd_en_ok && (rd_add[AXIL_ADD_RANGE_W-1:0] == MHDMA_REQUEST_STAT_NOTIFY_ACK_OFS[AXIL_ADD_RANGE_W-1:0]);
  assign r_mhdma_request_stat_notify_ack = r_mhdma_request_stat_notify_ack_upd;
// Register FF: mhdma_request_stat_notify_timeout_retry
  logic [REG_DATA_W-1:0] r_mhdma_request_stat_notify_timeout_retryD;
  assign r_mhdma_request_stat_notify_timeout_retryD       = r_mhdma_request_stat_notify_timeout_retry_upd;
  assign r_mhdma_request_stat_notify_timeout_retry_rd_en = rd_en_ok && (rd_add[AXIL_ADD_RANGE_W-1:0] == MHDMA_REQUEST_STAT_NOTIFY_TIMEOUT_RETRY_OFS[AXIL_ADD_RANGE_W-1:0]);
  assign r_mhdma_request_stat_notify_timeout_retry = r_mhdma_request_stat_notify_timeout_retry_upd;
// Register FF: mhdma_request_stat_nb_nack_received
  logic [REG_DATA_W-1:0] r_mhdma_request_stat_nb_nack_receivedD;
  assign r_mhdma_request_stat_nb_nack_receivedD       = r_mhdma_request_stat_nb_nack_received_upd;
  assign r_mhdma_request_stat_nb_nack_received_rd_en = rd_en_ok && (rd_add[AXIL_ADD_RANGE_W-1:0] == MHDMA_REQUEST_STAT_NB_NACK_RECEIVED_OFS[AXIL_ADD_RANGE_W-1:0]);
  assign r_mhdma_request_stat_nb_nack_received = r_mhdma_request_stat_nb_nack_received_upd;
// Register FF: mhdma_request_stat_nb_notify_received
  logic [REG_DATA_W-1:0] r_mhdma_request_stat_nb_notify_receivedD;
  assign r_mhdma_request_stat_nb_notify_receivedD       = r_mhdma_request_stat_nb_notify_received_upd;
  assign r_mhdma_request_stat_nb_notify_received_rd_en = rd_en_ok && (rd_add[AXIL_ADD_RANGE_W-1:0] == MHDMA_REQUEST_STAT_NB_NOTIFY_RECEIVED_OFS[AXIL_ADD_RANGE_W-1:0]);
  assign r_mhdma_request_stat_nb_notify_received = r_mhdma_request_stat_nb_notify_received_upd;
// Register FF: mhdma_request_stat_nb_read_req_received
  logic [REG_DATA_W-1:0] r_mhdma_request_stat_nb_read_req_receivedD;
  assign r_mhdma_request_stat_nb_read_req_receivedD       = r_mhdma_request_stat_nb_read_req_received_upd;
  assign r_mhdma_request_stat_nb_read_req_received_rd_en = rd_en_ok && (rd_add[AXIL_ADD_RANGE_W-1:0] == MHDMA_REQUEST_STAT_NB_READ_REQ_RECEIVED_OFS[AXIL_ADD_RANGE_W-1:0]);
  assign r_mhdma_request_stat_nb_read_req_received = r_mhdma_request_stat_nb_read_req_received_upd;
// Register FF: mhdma_request_stat_nb_ce_received
  logic [REG_DATA_W-1:0] r_mhdma_request_stat_nb_ce_receivedD;
  assign r_mhdma_request_stat_nb_ce_receivedD       = r_mhdma_request_stat_nb_ce_received_upd;
  assign r_mhdma_request_stat_nb_ce_received_rd_en = rd_en_ok && (rd_add[AXIL_ADD_RANGE_W-1:0] == MHDMA_REQUEST_STAT_NB_CE_RECEIVED_OFS[AXIL_ADD_RANGE_W-1:0]);
  assign r_mhdma_request_stat_nb_ce_received = r_mhdma_request_stat_nb_ce_received_upd;
// Register FF: mhdma_request_stat_nb_read_to_hbm
  logic [REG_DATA_W-1:0] r_mhdma_request_stat_nb_read_to_hbmD;
  assign r_mhdma_request_stat_nb_read_to_hbmD       = r_mhdma_request_stat_nb_read_to_hbm_upd;
  assign r_mhdma_request_stat_nb_read_to_hbm_rd_en = rd_en_ok && (rd_add[AXIL_ADD_RANGE_W-1:0] == MHDMA_REQUEST_STAT_NB_READ_TO_HBM_OFS[AXIL_ADD_RANGE_W-1:0]);
  assign r_mhdma_request_stat_nb_read_to_hbm = r_mhdma_request_stat_nb_read_to_hbm_upd;
// Register FF: mhdma_request_stat_nb_words_received_pc_pc0
  logic [REG_DATA_W-1:0] r_mhdma_request_stat_nb_words_received_pc_pc0D;
  assign r_mhdma_request_stat_nb_words_received_pc_pc0D       = r_mhdma_request_stat_nb_words_received_pc_pc0_upd;
  assign r_mhdma_request_stat_nb_words_received_pc_pc0_rd_en = rd_en_ok && (rd_add[AXIL_ADD_RANGE_W-1:0] == MHDMA_REQUEST_STAT_NB_WORDS_RECEIVED_PC_PC0_OFS[AXIL_ADD_RANGE_W-1:0]);
  assign r_mhdma_request_stat_nb_words_received_pc_pc0 = r_mhdma_request_stat_nb_words_received_pc_pc0_upd;
// Register FF: mhdma_request_stat_nb_words_received_pc_pc1
  logic [REG_DATA_W-1:0] r_mhdma_request_stat_nb_words_received_pc_pc1D;
  assign r_mhdma_request_stat_nb_words_received_pc_pc1D       = r_mhdma_request_stat_nb_words_received_pc_pc1_upd;
  assign r_mhdma_request_stat_nb_words_received_pc_pc1_rd_en = rd_en_ok && (rd_add[AXIL_ADD_RANGE_W-1:0] == MHDMA_REQUEST_STAT_NB_WORDS_RECEIVED_PC_PC1_OFS[AXIL_ADD_RANGE_W-1:0]);
  assign r_mhdma_request_stat_nb_words_received_pc_pc1 = r_mhdma_request_stat_nb_words_received_pc_pc1_upd;
// Register FF: mhdma_request_stat_nb_ce_words_received
  logic [REG_DATA_W-1:0] r_mhdma_request_stat_nb_ce_words_receivedD;
  assign r_mhdma_request_stat_nb_ce_words_receivedD       = r_mhdma_request_stat_nb_ce_words_received_upd;
  assign r_mhdma_request_stat_nb_ce_words_received_rd_en = rd_en_ok && (rd_add[AXIL_ADD_RANGE_W-1:0] == MHDMA_REQUEST_STAT_NB_CE_WORDS_RECEIVED_OFS[AXIL_ADD_RANGE_W-1:0]);
  assign r_mhdma_request_stat_nb_ce_words_received = r_mhdma_request_stat_nb_ce_words_received_upd;
// Register FF: mhdma_request_stat_t_notify_to_ack
  logic [REG_DATA_W-1:0] r_mhdma_request_stat_t_notify_to_ackD;
  assign r_mhdma_request_stat_t_notify_to_ackD       = r_mhdma_request_stat_t_notify_to_ack_upd;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_mhdma_request_stat_t_notify_to_ack       <= mhdma_request_stat_t_notify_to_ack_default;
    end
    else begin
      r_mhdma_request_stat_t_notify_to_ack       <= r_mhdma_request_stat_t_notify_to_ackD;
    end
  end
// Register FF: mhdma_request_stat_t_rr_to_ce_received
  logic [REG_DATA_W-1:0] r_mhdma_request_stat_t_rr_to_ce_receivedD;
  assign r_mhdma_request_stat_t_rr_to_ce_receivedD       = r_mhdma_request_stat_t_rr_to_ce_received_upd;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_mhdma_request_stat_t_rr_to_ce_received       <= mhdma_request_stat_t_rr_to_ce_received_default;
    end
    else begin
      r_mhdma_request_stat_t_rr_to_ce_received       <= r_mhdma_request_stat_t_rr_to_ce_receivedD;
    end
  end
// Register FF: mhdma_request_stat_t_ce_first_to_last_pkt
  logic [REG_DATA_W-1:0] r_mhdma_request_stat_t_ce_first_to_last_pktD;
  assign r_mhdma_request_stat_t_ce_first_to_last_pktD       = r_mhdma_request_stat_t_ce_first_to_last_pkt_upd;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_mhdma_request_stat_t_ce_first_to_last_pkt       <= mhdma_request_stat_t_ce_first_to_last_pkt_default;
    end
    else begin
      r_mhdma_request_stat_t_ce_first_to_last_pkt       <= r_mhdma_request_stat_t_ce_first_to_last_pktD;
    end
  end
// Register FF: mhdma_request_stat_t_rr_wait_words_pc_pc0
  logic [REG_DATA_W-1:0] r_mhdma_request_stat_t_rr_wait_words_pc_pc0D;
  assign r_mhdma_request_stat_t_rr_wait_words_pc_pc0D       = r_mhdma_request_stat_t_rr_wait_words_pc_pc0_upd;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_mhdma_request_stat_t_rr_wait_words_pc_pc0       <= mhdma_request_stat_t_rr_wait_words_pc_pc0_default;
    end
    else begin
      r_mhdma_request_stat_t_rr_wait_words_pc_pc0       <= r_mhdma_request_stat_t_rr_wait_words_pc_pc0D;
    end
  end
// Register FF: mhdma_request_stat_t_rr_wait_words_pc_pc1
  logic [REG_DATA_W-1:0] r_mhdma_request_stat_t_rr_wait_words_pc_pc1D;
  assign r_mhdma_request_stat_t_rr_wait_words_pc_pc1D       = r_mhdma_request_stat_t_rr_wait_words_pc_pc1_upd;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_mhdma_request_stat_t_rr_wait_words_pc_pc1       <= mhdma_request_stat_t_rr_wait_words_pc_pc1_default;
    end
    else begin
      r_mhdma_request_stat_t_rr_wait_words_pc_pc1       <= r_mhdma_request_stat_t_rr_wait_words_pc_pc1D;
    end
  end
// Register FF: mhdma_request_stat_notify_timeout
  logic [REG_DATA_W-1:0] r_mhdma_request_stat_notify_timeoutD;
  assign r_mhdma_request_stat_notify_timeoutD       = r_mhdma_request_stat_notify_timeout_upd;
  assign r_mhdma_request_stat_notify_timeout_rd_en = rd_en_ok && (rd_add[AXIL_ADD_RANGE_W-1:0] == MHDMA_REQUEST_STAT_NOTIFY_TIMEOUT_OFS[AXIL_ADD_RANGE_W-1:0]);
  assign r_mhdma_request_stat_notify_timeout = r_mhdma_request_stat_notify_timeout_upd;
// Register FF: mhdma_request_stat_physical_addr_pc0_lsb
  logic [REG_DATA_W-1:0] r_mhdma_request_stat_physical_addr_pc0_lsbD;
  assign r_mhdma_request_stat_physical_addr_pc0_lsbD       = r_mhdma_request_stat_physical_addr_pc0_lsb_upd;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_mhdma_request_stat_physical_addr_pc0_lsb       <= mhdma_request_stat_physical_addr_pc0_lsb_default;
    end
    else begin
      r_mhdma_request_stat_physical_addr_pc0_lsb       <= r_mhdma_request_stat_physical_addr_pc0_lsbD;
    end
  end
// Register FF: mhdma_request_stat_physical_addr_pc0_msb
  logic [REG_DATA_W-1:0] r_mhdma_request_stat_physical_addr_pc0_msbD;
  assign r_mhdma_request_stat_physical_addr_pc0_msbD       = r_mhdma_request_stat_physical_addr_pc0_msb_upd;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_mhdma_request_stat_physical_addr_pc0_msb       <= mhdma_request_stat_physical_addr_pc0_msb_default;
    end
    else begin
      r_mhdma_request_stat_physical_addr_pc0_msb       <= r_mhdma_request_stat_physical_addr_pc0_msbD;
    end
  end
// Register FF: mhdma_request_stat_physical_addr_pc1_lsb
  logic [REG_DATA_W-1:0] r_mhdma_request_stat_physical_addr_pc1_lsbD;
  assign r_mhdma_request_stat_physical_addr_pc1_lsbD       = r_mhdma_request_stat_physical_addr_pc1_lsb_upd;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_mhdma_request_stat_physical_addr_pc1_lsb       <= mhdma_request_stat_physical_addr_pc1_lsb_default;
    end
    else begin
      r_mhdma_request_stat_physical_addr_pc1_lsb       <= r_mhdma_request_stat_physical_addr_pc1_lsbD;
    end
  end
// Register FF: mhdma_request_stat_physical_addr_pc1_msb
  logic [REG_DATA_W-1:0] r_mhdma_request_stat_physical_addr_pc1_msbD;
  assign r_mhdma_request_stat_physical_addr_pc1_msbD       = r_mhdma_request_stat_physical_addr_pc1_msb_upd;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_mhdma_request_stat_physical_addr_pc1_msb       <= mhdma_request_stat_physical_addr_pc1_msb_default;
    end
    else begin
      r_mhdma_request_stat_physical_addr_pc1_msb       <= r_mhdma_request_stat_physical_addr_pc1_msbD;
    end
  end
// Register FF: mhdma_request_stat_cnt_nb_write_complete
  logic [REG_DATA_W-1:0] r_mhdma_request_stat_cnt_nb_write_completeD;
  assign r_mhdma_request_stat_cnt_nb_write_completeD       = r_mhdma_request_stat_cnt_nb_write_complete_upd;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_mhdma_request_stat_cnt_nb_write_complete       <= mhdma_request_stat_cnt_nb_write_complete_default;
    end
    else begin
      r_mhdma_request_stat_cnt_nb_write_complete       <= r_mhdma_request_stat_cnt_nb_write_completeD;
    end
  end
// Register FF: mhdma_lane_debug
  logic [REG_DATA_W-1:0] r_mhdma_lane_debugD;
  assign r_mhdma_lane_debugD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == MHDMA_LANE_DEBUG_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_mhdma_lane_debug;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_mhdma_lane_debug       <= mhdma_lane_debug_default;
    end
    else begin
      r_mhdma_lane_debug       <= r_mhdma_lane_debugD;
    end
  end
// Register FF: mhdma_hbm_axi4_addr_2in3_ct_pc0_lsb
  logic [REG_DATA_W-1:0] r_mhdma_hbm_axi4_addr_2in3_ct_pc0_lsbD;
  assign r_mhdma_hbm_axi4_addr_2in3_ct_pc0_lsbD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == MHDMA_HBM_AXI4_ADDR_2IN3_CT_PC0_LSB_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_mhdma_hbm_axi4_addr_2in3_ct_pc0_lsb;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_mhdma_hbm_axi4_addr_2in3_ct_pc0_lsb       <= mhdma_hbm_axi4_addr_2in3_ct_pc0_lsb_default;
    end
    else begin
      r_mhdma_hbm_axi4_addr_2in3_ct_pc0_lsb       <= r_mhdma_hbm_axi4_addr_2in3_ct_pc0_lsbD;
    end
  end
// Register FF: mhdma_hbm_axi4_addr_2in3_ct_pc0_msb
  logic [REG_DATA_W-1:0] r_mhdma_hbm_axi4_addr_2in3_ct_pc0_msbD;
  assign r_mhdma_hbm_axi4_addr_2in3_ct_pc0_msbD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == MHDMA_HBM_AXI4_ADDR_2IN3_CT_PC0_MSB_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_mhdma_hbm_axi4_addr_2in3_ct_pc0_msb;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_mhdma_hbm_axi4_addr_2in3_ct_pc0_msb       <= mhdma_hbm_axi4_addr_2in3_ct_pc0_msb_default;
    end
    else begin
      r_mhdma_hbm_axi4_addr_2in3_ct_pc0_msb       <= r_mhdma_hbm_axi4_addr_2in3_ct_pc0_msbD;
    end
  end
// Register FF: mhdma_hbm_axi4_addr_2in3_ct_pc1_lsb
  logic [REG_DATA_W-1:0] r_mhdma_hbm_axi4_addr_2in3_ct_pc1_lsbD;
  assign r_mhdma_hbm_axi4_addr_2in3_ct_pc1_lsbD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == MHDMA_HBM_AXI4_ADDR_2IN3_CT_PC1_LSB_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_mhdma_hbm_axi4_addr_2in3_ct_pc1_lsb;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_mhdma_hbm_axi4_addr_2in3_ct_pc1_lsb       <= mhdma_hbm_axi4_addr_2in3_ct_pc1_lsb_default;
    end
    else begin
      r_mhdma_hbm_axi4_addr_2in3_ct_pc1_lsb       <= r_mhdma_hbm_axi4_addr_2in3_ct_pc1_lsbD;
    end
  end
// Register FF: mhdma_hbm_axi4_addr_2in3_ct_pc1_msb
  logic [REG_DATA_W-1:0] r_mhdma_hbm_axi4_addr_2in3_ct_pc1_msbD;
  assign r_mhdma_hbm_axi4_addr_2in3_ct_pc1_msbD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == MHDMA_HBM_AXI4_ADDR_2IN3_CT_PC1_MSB_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_mhdma_hbm_axi4_addr_2in3_ct_pc1_msb;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_mhdma_hbm_axi4_addr_2in3_ct_pc1_msb       <= mhdma_hbm_axi4_addr_2in3_ct_pc1_msb_default;
    end
    else begin
      r_mhdma_hbm_axi4_addr_2in3_ct_pc1_msb       <= r_mhdma_hbm_axi4_addr_2in3_ct_pc1_msbD;
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
// Register FF: cnt_trig_rd
  logic [REG_DATA_W-1:0] r_cnt_trig_rdD;
  assign r_cnt_trig_rdD       = r_cnt_trig_rd_upd;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_cnt_trig_rd       <= cnt_trig_rd_default;
    end
    else begin
      r_cnt_trig_rd       <= r_cnt_trig_rdD;
    end
  end
// Register FF: cnt_tx_wr
  logic [REG_DATA_W-1:0] r_cnt_tx_wrD;
  assign r_cnt_tx_wrD       = r_cnt_tx_wr_upd;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_cnt_tx_wr       <= cnt_tx_wr_default;
    end
    else begin
      r_cnt_tx_wr       <= r_cnt_tx_wrD;
    end
  end
// Register FF: cnt_words
  logic [REG_DATA_W-1:0] r_cnt_wordsD;
  assign r_cnt_wordsD       = r_cnt_words_upd;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_cnt_words       <= cnt_words_default;
    end
    else begin
      r_cnt_words       <= r_cnt_wordsD;
    end
  end
// Register FF: mhdma_stat_status
  logic [REG_DATA_W-1:0] r_mhdma_stat_statusD;
  assign r_mhdma_stat_statusD       = r_mhdma_stat_status_upd;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_mhdma_stat_status       <= mhdma_stat_status_default;
    end
    else begin
      r_mhdma_stat_status       <= r_mhdma_stat_statusD;
    end
  end
// Register FF: mhdma_stat_clk_a
  logic [REG_DATA_W-1:0] r_mhdma_stat_clk_aD;
  assign r_mhdma_stat_clk_aD       = r_mhdma_stat_clk_a_upd;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_mhdma_stat_clk_a       <= mhdma_stat_clk_a_default;
    end
    else begin
      r_mhdma_stat_clk_a       <= r_mhdma_stat_clk_aD;
    end
  end
// Register FF: mhdma_stat_clk_b
  logic [REG_DATA_W-1:0] r_mhdma_stat_clk_bD;
  assign r_mhdma_stat_clk_bD       = r_mhdma_stat_clk_b_upd;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_mhdma_stat_clk_b       <= mhdma_stat_clk_b_default;
    end
    else begin
      r_mhdma_stat_clk_b       <= r_mhdma_stat_clk_bD;
    end
  end
// Register FF: mhdma_stat_valid_words_a
  logic [REG_DATA_W-1:0] r_mhdma_stat_valid_words_aD;
  assign r_mhdma_stat_valid_words_aD       = r_mhdma_stat_valid_words_a_upd;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_mhdma_stat_valid_words_a       <= mhdma_stat_valid_words_a_default;
    end
    else begin
      r_mhdma_stat_valid_words_a       <= r_mhdma_stat_valid_words_aD;
    end
  end
// Register FF: mhdma_stat_valid_words_b
  logic [REG_DATA_W-1:0] r_mhdma_stat_valid_words_bD;
  assign r_mhdma_stat_valid_words_bD       = r_mhdma_stat_valid_words_b_upd;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_mhdma_stat_valid_words_b       <= mhdma_stat_valid_words_b_default;
    end
    else begin
      r_mhdma_stat_valid_words_b       <= r_mhdma_stat_valid_words_bD;
    end
  end
// Register FF: mhdma_stat_sop_cnt_a
  logic [REG_DATA_W-1:0] r_mhdma_stat_sop_cnt_aD;
  assign r_mhdma_stat_sop_cnt_aD       = r_mhdma_stat_sop_cnt_a_upd;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_mhdma_stat_sop_cnt_a       <= mhdma_stat_sop_cnt_a_default;
    end
    else begin
      r_mhdma_stat_sop_cnt_a       <= r_mhdma_stat_sop_cnt_aD;
    end
  end
// Register FF: mhdma_stat_sop_cnt_b
  logic [REG_DATA_W-1:0] r_mhdma_stat_sop_cnt_bD;
  assign r_mhdma_stat_sop_cnt_bD       = r_mhdma_stat_sop_cnt_b_upd;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_mhdma_stat_sop_cnt_b       <= mhdma_stat_sop_cnt_b_default;
    end
    else begin
      r_mhdma_stat_sop_cnt_b       <= r_mhdma_stat_sop_cnt_bD;
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
          MHDMA_SYSTEM_LANE_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register mhdma_system_lane
            axil_rdataD = r_mhdma_system_lane;
          end
          MHDMA_SYSTEM_TIMEOUT_NOTIFY_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register mhdma_system_timeout_notify
            axil_rdataD = r_mhdma_system_timeout_notify;
          end
          MHDMA_SYSTEM_TIMEOUT_READ_REQ_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register mhdma_system_timeout_read_req
            axil_rdataD = r_mhdma_system_timeout_read_req;
          end
          MHDMA_SYSTEM_FSM_VALUE_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register mhdma_system_fsm_value
            axil_rdataD = r_mhdma_system_fsm_value;
          end
          MHDMA_RESET_DATAPATH_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register mhdma_reset_datapath
            axil_rdataD = r_mhdma_reset_datapath;
          end
          MHDMA_RESET_MONITOR_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register mhdma_reset_monitor
            axil_rdataD = r_mhdma_reset_monitor;
          end
          MHDMA_HPU_ID_ZERO_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register mhdma_hpu_id_zero
            axil_rdataD = r_mhdma_hpu_id_zero;
          end
          MHDMA_HPU_ID_ONE_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register mhdma_hpu_id_one
            axil_rdataD = r_mhdma_hpu_id_one;
          end
          MHDMA_HPU_ID_TWO_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register mhdma_hpu_id_two
            axil_rdataD = r_mhdma_hpu_id_two;
          end
          MHDMA_HPU_ID_THREE_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register mhdma_hpu_id_three
            axil_rdataD = r_mhdma_hpu_id_three;
          end
          MHDMA_HPU_ID_FOUR_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register mhdma_hpu_id_four
            axil_rdataD = r_mhdma_hpu_id_four;
          end
          MHDMA_HPU_ID_FIVE_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register mhdma_hpu_id_five
            axil_rdataD = r_mhdma_hpu_id_five;
          end
          MHDMA_HPU_ID_SIX_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register mhdma_hpu_id_six
            axil_rdataD = r_mhdma_hpu_id_six;
          end
          MHDMA_HPU_ID_SEVEN_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register mhdma_hpu_id_seven
            axil_rdataD = r_mhdma_hpu_id_seven;
          end
          MHDMA_REQUEST_REQ_ID_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register mhdma_request_req_id
            axil_rdataD = r_mhdma_request_req_id;
          end
          MHDMA_REQUEST_REQ_ADDR_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register mhdma_request_req_addr
            axil_rdataD = r_mhdma_request_req_addr;
          end
          MHDMA_REQUEST_NOTIFY_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register mhdma_request_notify
            axil_rdataD = r_mhdma_request_notify;
          end
          MHDMA_REQUEST_READ_REQUEST_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register mhdma_request_read_request
            axil_rdataD = r_mhdma_request_read_request;
          end
          MHDMA_REQUEST_STAT_NOTIFY_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register mhdma_request_stat_notify
            axil_rdataD = r_mhdma_request_stat_notify;
          end
          MHDMA_REQUEST_STAT_NOTIFY_ACK_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register mhdma_request_stat_notify_ack
            axil_rdataD = r_mhdma_request_stat_notify_ack;
          end
          MHDMA_REQUEST_STAT_NOTIFY_TIMEOUT_RETRY_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register mhdma_request_stat_notify_timeout_retry
            axil_rdataD = r_mhdma_request_stat_notify_timeout_retry;
          end
          MHDMA_REQUEST_STAT_NB_NACK_RECEIVED_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register mhdma_request_stat_nb_nack_received
            axil_rdataD = r_mhdma_request_stat_nb_nack_received;
          end
          MHDMA_REQUEST_STAT_NB_NOTIFY_RECEIVED_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register mhdma_request_stat_nb_notify_received
            axil_rdataD = r_mhdma_request_stat_nb_notify_received;
          end
          MHDMA_REQUEST_STAT_NB_READ_REQ_RECEIVED_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register mhdma_request_stat_nb_read_req_received
            axil_rdataD = r_mhdma_request_stat_nb_read_req_received;
          end
          MHDMA_REQUEST_STAT_NB_CE_RECEIVED_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register mhdma_request_stat_nb_ce_received
            axil_rdataD = r_mhdma_request_stat_nb_ce_received;
          end
          MHDMA_REQUEST_STAT_NB_READ_TO_HBM_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register mhdma_request_stat_nb_read_to_hbm
            axil_rdataD = r_mhdma_request_stat_nb_read_to_hbm;
          end
          MHDMA_REQUEST_STAT_NB_WORDS_RECEIVED_PC_PC0_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register mhdma_request_stat_nb_words_received_pc_pc0
            axil_rdataD = r_mhdma_request_stat_nb_words_received_pc_pc0;
          end
          MHDMA_REQUEST_STAT_NB_WORDS_RECEIVED_PC_PC1_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register mhdma_request_stat_nb_words_received_pc_pc1
            axil_rdataD = r_mhdma_request_stat_nb_words_received_pc_pc1;
          end
          MHDMA_REQUEST_STAT_NB_CE_WORDS_RECEIVED_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register mhdma_request_stat_nb_ce_words_received
            axil_rdataD = r_mhdma_request_stat_nb_ce_words_received;
          end
          MHDMA_REQUEST_STAT_T_NOTIFY_TO_ACK_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register mhdma_request_stat_t_notify_to_ack
            axil_rdataD = r_mhdma_request_stat_t_notify_to_ack;
          end
          MHDMA_REQUEST_STAT_T_RR_TO_CE_RECEIVED_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register mhdma_request_stat_t_rr_to_ce_received
            axil_rdataD = r_mhdma_request_stat_t_rr_to_ce_received;
          end
          MHDMA_REQUEST_STAT_T_CE_FIRST_TO_LAST_PKT_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register mhdma_request_stat_t_ce_first_to_last_pkt
            axil_rdataD = r_mhdma_request_stat_t_ce_first_to_last_pkt;
          end
          MHDMA_REQUEST_STAT_T_RR_WAIT_WORDS_PC_PC0_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register mhdma_request_stat_t_rr_wait_words_pc_pc0
            axil_rdataD = r_mhdma_request_stat_t_rr_wait_words_pc_pc0;
          end
          MHDMA_REQUEST_STAT_T_RR_WAIT_WORDS_PC_PC1_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register mhdma_request_stat_t_rr_wait_words_pc_pc1
            axil_rdataD = r_mhdma_request_stat_t_rr_wait_words_pc_pc1;
          end
          MHDMA_REQUEST_STAT_NOTIFY_TIMEOUT_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register mhdma_request_stat_notify_timeout
            axil_rdataD = r_mhdma_request_stat_notify_timeout;
          end
          MHDMA_REQUEST_STAT_PHYSICAL_ADDR_PC0_LSB_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register mhdma_request_stat_physical_addr_pc0_lsb
            axil_rdataD = r_mhdma_request_stat_physical_addr_pc0_lsb;
          end
          MHDMA_REQUEST_STAT_PHYSICAL_ADDR_PC0_MSB_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register mhdma_request_stat_physical_addr_pc0_msb
            axil_rdataD = r_mhdma_request_stat_physical_addr_pc0_msb;
          end
          MHDMA_REQUEST_STAT_PHYSICAL_ADDR_PC1_LSB_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register mhdma_request_stat_physical_addr_pc1_lsb
            axil_rdataD = r_mhdma_request_stat_physical_addr_pc1_lsb;
          end
          MHDMA_REQUEST_STAT_PHYSICAL_ADDR_PC1_MSB_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register mhdma_request_stat_physical_addr_pc1_msb
            axil_rdataD = r_mhdma_request_stat_physical_addr_pc1_msb;
          end
          MHDMA_REQUEST_STAT_CNT_NB_WRITE_COMPLETE_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register mhdma_request_stat_cnt_nb_write_complete
            axil_rdataD = r_mhdma_request_stat_cnt_nb_write_complete;
          end
          MHDMA_LANE_DEBUG_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register mhdma_lane_debug
            axil_rdataD = r_mhdma_lane_debug;
          end
          MHDMA_HBM_AXI4_ADDR_2IN3_CT_PC0_LSB_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register mhdma_hbm_axi4_addr_2in3_ct_pc0_lsb
            axil_rdataD = r_mhdma_hbm_axi4_addr_2in3_ct_pc0_lsb;
          end
          MHDMA_HBM_AXI4_ADDR_2IN3_CT_PC0_MSB_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register mhdma_hbm_axi4_addr_2in3_ct_pc0_msb
            axil_rdataD = r_mhdma_hbm_axi4_addr_2in3_ct_pc0_msb;
          end
          MHDMA_HBM_AXI4_ADDR_2IN3_CT_PC1_LSB_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register mhdma_hbm_axi4_addr_2in3_ct_pc1_lsb
            axil_rdataD = r_mhdma_hbm_axi4_addr_2in3_ct_pc1_lsb;
          end
          MHDMA_HBM_AXI4_ADDR_2IN3_CT_PC1_MSB_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register mhdma_hbm_axi4_addr_2in3_ct_pc1_msb
            axil_rdataD = r_mhdma_hbm_axi4_addr_2in3_ct_pc1_msb;
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
          CNT_TRIG_RD_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register cnt_trig_rd
            axil_rdataD = r_cnt_trig_rd;
          end
          CNT_TX_WR_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register cnt_tx_wr
            axil_rdataD = r_cnt_tx_wr;
          end
          CNT_WORDS_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register cnt_words
            axil_rdataD = r_cnt_words;
          end
          MHDMA_STAT_STATUS_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register mhdma_stat_status
            axil_rdataD = r_mhdma_stat_status;
          end
          MHDMA_STAT_CLK_A_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register mhdma_stat_clk_a
            axil_rdataD = r_mhdma_stat_clk_a;
          end
          MHDMA_STAT_CLK_B_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register mhdma_stat_clk_b
            axil_rdataD = r_mhdma_stat_clk_b;
          end
          MHDMA_STAT_VALID_WORDS_A_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register mhdma_stat_valid_words_a
            axil_rdataD = r_mhdma_stat_valid_words_a;
          end
          MHDMA_STAT_VALID_WORDS_B_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register mhdma_stat_valid_words_b
            axil_rdataD = r_mhdma_stat_valid_words_b;
          end
          MHDMA_STAT_SOP_CNT_A_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register mhdma_stat_sop_cnt_a
            axil_rdataD = r_mhdma_stat_sop_cnt_a;
          end
          MHDMA_STAT_SOP_CNT_B_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register mhdma_stat_sop_cnt_b
            axil_rdataD = r_mhdma_stat_sop_cnt_b;
          end
          default:
            axil_rdataD = REG_DATA_W'('h0BAD_ADD1); // Default value
          endcase // rd_add
        end
      end // if rd_end
    end
  end // always_comb - read
endmodule
