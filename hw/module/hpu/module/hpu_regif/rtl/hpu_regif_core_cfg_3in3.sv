// ============================================================================================== //
// Description  : Axi4-lite register bank
// This file was generated with rust regmap generator:
//  * Date:  2025-07-17
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
module hpu_regif_core_cfg_3in3
import axi_if_shell_axil_pkg::*;
import axi_if_common_param_pkg::*;
import hpu_regif_core_cfg_3in3_pkg::*;
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
  // Register IO: hbm_axi4_addr_3in3_bsk_pc0_lsb
    , output logic [REG_DATA_W-1: 0] r_hbm_axi4_addr_3in3_bsk_pc0_lsb
  // Register IO: hbm_axi4_addr_3in3_bsk_pc0_msb
    , output logic [REG_DATA_W-1: 0] r_hbm_axi4_addr_3in3_bsk_pc0_msb
  // Register IO: hbm_axi4_addr_3in3_bsk_pc1_lsb
    , output logic [REG_DATA_W-1: 0] r_hbm_axi4_addr_3in3_bsk_pc1_lsb
  // Register IO: hbm_axi4_addr_3in3_bsk_pc1_msb
    , output logic [REG_DATA_W-1: 0] r_hbm_axi4_addr_3in3_bsk_pc1_msb
  // Register IO: hbm_axi4_addr_3in3_bsk_pc2_lsb
    , output logic [REG_DATA_W-1: 0] r_hbm_axi4_addr_3in3_bsk_pc2_lsb
  // Register IO: hbm_axi4_addr_3in3_bsk_pc2_msb
    , output logic [REG_DATA_W-1: 0] r_hbm_axi4_addr_3in3_bsk_pc2_msb
  // Register IO: hbm_axi4_addr_3in3_bsk_pc3_lsb
    , output logic [REG_DATA_W-1: 0] r_hbm_axi4_addr_3in3_bsk_pc3_lsb
  // Register IO: hbm_axi4_addr_3in3_bsk_pc3_msb
    , output logic [REG_DATA_W-1: 0] r_hbm_axi4_addr_3in3_bsk_pc3_msb
  // Register IO: hbm_axi4_addr_3in3_bsk_pc4_lsb
    , output logic [REG_DATA_W-1: 0] r_hbm_axi4_addr_3in3_bsk_pc4_lsb
  // Register IO: hbm_axi4_addr_3in3_bsk_pc4_msb
    , output logic [REG_DATA_W-1: 0] r_hbm_axi4_addr_3in3_bsk_pc4_msb
  // Register IO: hbm_axi4_addr_3in3_bsk_pc5_lsb
    , output logic [REG_DATA_W-1: 0] r_hbm_axi4_addr_3in3_bsk_pc5_lsb
  // Register IO: hbm_axi4_addr_3in3_bsk_pc5_msb
    , output logic [REG_DATA_W-1: 0] r_hbm_axi4_addr_3in3_bsk_pc5_msb
  // Register IO: hbm_axi4_addr_3in3_bsk_pc6_lsb
    , output logic [REG_DATA_W-1: 0] r_hbm_axi4_addr_3in3_bsk_pc6_lsb
  // Register IO: hbm_axi4_addr_3in3_bsk_pc6_msb
    , output logic [REG_DATA_W-1: 0] r_hbm_axi4_addr_3in3_bsk_pc6_msb
  // Register IO: hbm_axi4_addr_3in3_bsk_pc7_lsb
    , output logic [REG_DATA_W-1: 0] r_hbm_axi4_addr_3in3_bsk_pc7_lsb
  // Register IO: hbm_axi4_addr_3in3_bsk_pc7_msb
    , output logic [REG_DATA_W-1: 0] r_hbm_axi4_addr_3in3_bsk_pc7_msb
  // Register IO: hbm_axi4_addr_3in3_bsk_pc8_lsb
    , output logic [REG_DATA_W-1: 0] r_hbm_axi4_addr_3in3_bsk_pc8_lsb
  // Register IO: hbm_axi4_addr_3in3_bsk_pc8_msb
    , output logic [REG_DATA_W-1: 0] r_hbm_axi4_addr_3in3_bsk_pc8_msb
  // Register IO: hbm_axi4_addr_3in3_bsk_pc9_lsb
    , output logic [REG_DATA_W-1: 0] r_hbm_axi4_addr_3in3_bsk_pc9_lsb
  // Register IO: hbm_axi4_addr_3in3_bsk_pc9_msb
    , output logic [REG_DATA_W-1: 0] r_hbm_axi4_addr_3in3_bsk_pc9_msb
  // Register IO: hbm_axi4_addr_3in3_bsk_pc10_lsb
    , output logic [REG_DATA_W-1: 0] r_hbm_axi4_addr_3in3_bsk_pc10_lsb
  // Register IO: hbm_axi4_addr_3in3_bsk_pc10_msb
    , output logic [REG_DATA_W-1: 0] r_hbm_axi4_addr_3in3_bsk_pc10_msb
  // Register IO: hbm_axi4_addr_3in3_bsk_pc11_lsb
    , output logic [REG_DATA_W-1: 0] r_hbm_axi4_addr_3in3_bsk_pc11_lsb
  // Register IO: hbm_axi4_addr_3in3_bsk_pc11_msb
    , output logic [REG_DATA_W-1: 0] r_hbm_axi4_addr_3in3_bsk_pc11_msb
  // Register IO: hbm_axi4_addr_3in3_bsk_pc12_lsb
    , output logic [REG_DATA_W-1: 0] r_hbm_axi4_addr_3in3_bsk_pc12_lsb
  // Register IO: hbm_axi4_addr_3in3_bsk_pc12_msb
    , output logic [REG_DATA_W-1: 0] r_hbm_axi4_addr_3in3_bsk_pc12_msb
  // Register IO: hbm_axi4_addr_3in3_bsk_pc13_lsb
    , output logic [REG_DATA_W-1: 0] r_hbm_axi4_addr_3in3_bsk_pc13_lsb
  // Register IO: hbm_axi4_addr_3in3_bsk_pc13_msb
    , output logic [REG_DATA_W-1: 0] r_hbm_axi4_addr_3in3_bsk_pc13_msb
  // Register IO: hbm_axi4_addr_3in3_bsk_pc14_lsb
    , output logic [REG_DATA_W-1: 0] r_hbm_axi4_addr_3in3_bsk_pc14_lsb
  // Register IO: hbm_axi4_addr_3in3_bsk_pc14_msb
    , output logic [REG_DATA_W-1: 0] r_hbm_axi4_addr_3in3_bsk_pc14_msb
  // Register IO: hbm_axi4_addr_3in3_bsk_pc15_lsb
    , output logic [REG_DATA_W-1: 0] r_hbm_axi4_addr_3in3_bsk_pc15_lsb
  // Register IO: hbm_axi4_addr_3in3_bsk_pc15_msb
    , output logic [REG_DATA_W-1: 0] r_hbm_axi4_addr_3in3_bsk_pc15_msb
  // Register IO: hpu_reset_trigger
    , output hpu_reset_trigger_t r_hpu_reset_trigger
        , input hpu_reset_trigger_t r_hpu_reset_trigger_upd
        , output logic r_hpu_reset_trigger_rd_en
    , output logic r_hpu_reset_trigger_wr_en
);
// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int AXIL_ADD_OFS = 'h20000;
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
//-- Default entry_cfg_3in3_dummy_val0
  logic [REG_DATA_W-1:0]entry_cfg_3in3_dummy_val0_default;
  assign entry_cfg_3in3_dummy_val0_default = 'h3030303;
//-- Default entry_cfg_3in3_dummy_val1
  logic [REG_DATA_W-1:0]entry_cfg_3in3_dummy_val1_default;
  assign entry_cfg_3in3_dummy_val1_default = 'h13131313;
//-- Default entry_cfg_3in3_dummy_val2
  logic [REG_DATA_W-1:0]entry_cfg_3in3_dummy_val2_default;
  assign entry_cfg_3in3_dummy_val2_default = 'h23232323;
//-- Default entry_cfg_3in3_dummy_val3
  logic [REG_DATA_W-1:0]entry_cfg_3in3_dummy_val3_default;
  assign entry_cfg_3in3_dummy_val3_default = 'h33333333;
//-- Default hbm_axi4_addr_3in3_bsk_pc0_lsb
  logic [REG_DATA_W-1:0]hbm_axi4_addr_3in3_bsk_pc0_lsb_default;
  assign hbm_axi4_addr_3in3_bsk_pc0_lsb_default = 'h0;
//-- Default hbm_axi4_addr_3in3_bsk_pc0_msb
  logic [REG_DATA_W-1:0]hbm_axi4_addr_3in3_bsk_pc0_msb_default;
  assign hbm_axi4_addr_3in3_bsk_pc0_msb_default = 'h0;
//-- Default hbm_axi4_addr_3in3_bsk_pc1_lsb
  logic [REG_DATA_W-1:0]hbm_axi4_addr_3in3_bsk_pc1_lsb_default;
  assign hbm_axi4_addr_3in3_bsk_pc1_lsb_default = 'h0;
//-- Default hbm_axi4_addr_3in3_bsk_pc1_msb
  logic [REG_DATA_W-1:0]hbm_axi4_addr_3in3_bsk_pc1_msb_default;
  assign hbm_axi4_addr_3in3_bsk_pc1_msb_default = 'h0;
//-- Default hbm_axi4_addr_3in3_bsk_pc2_lsb
  logic [REG_DATA_W-1:0]hbm_axi4_addr_3in3_bsk_pc2_lsb_default;
  assign hbm_axi4_addr_3in3_bsk_pc2_lsb_default = 'h0;
//-- Default hbm_axi4_addr_3in3_bsk_pc2_msb
  logic [REG_DATA_W-1:0]hbm_axi4_addr_3in3_bsk_pc2_msb_default;
  assign hbm_axi4_addr_3in3_bsk_pc2_msb_default = 'h0;
//-- Default hbm_axi4_addr_3in3_bsk_pc3_lsb
  logic [REG_DATA_W-1:0]hbm_axi4_addr_3in3_bsk_pc3_lsb_default;
  assign hbm_axi4_addr_3in3_bsk_pc3_lsb_default = 'h0;
//-- Default hbm_axi4_addr_3in3_bsk_pc3_msb
  logic [REG_DATA_W-1:0]hbm_axi4_addr_3in3_bsk_pc3_msb_default;
  assign hbm_axi4_addr_3in3_bsk_pc3_msb_default = 'h0;
//-- Default hbm_axi4_addr_3in3_bsk_pc4_lsb
  logic [REG_DATA_W-1:0]hbm_axi4_addr_3in3_bsk_pc4_lsb_default;
  assign hbm_axi4_addr_3in3_bsk_pc4_lsb_default = 'h0;
//-- Default hbm_axi4_addr_3in3_bsk_pc4_msb
  logic [REG_DATA_W-1:0]hbm_axi4_addr_3in3_bsk_pc4_msb_default;
  assign hbm_axi4_addr_3in3_bsk_pc4_msb_default = 'h0;
//-- Default hbm_axi4_addr_3in3_bsk_pc5_lsb
  logic [REG_DATA_W-1:0]hbm_axi4_addr_3in3_bsk_pc5_lsb_default;
  assign hbm_axi4_addr_3in3_bsk_pc5_lsb_default = 'h0;
//-- Default hbm_axi4_addr_3in3_bsk_pc5_msb
  logic [REG_DATA_W-1:0]hbm_axi4_addr_3in3_bsk_pc5_msb_default;
  assign hbm_axi4_addr_3in3_bsk_pc5_msb_default = 'h0;
//-- Default hbm_axi4_addr_3in3_bsk_pc6_lsb
  logic [REG_DATA_W-1:0]hbm_axi4_addr_3in3_bsk_pc6_lsb_default;
  assign hbm_axi4_addr_3in3_bsk_pc6_lsb_default = 'h0;
//-- Default hbm_axi4_addr_3in3_bsk_pc6_msb
  logic [REG_DATA_W-1:0]hbm_axi4_addr_3in3_bsk_pc6_msb_default;
  assign hbm_axi4_addr_3in3_bsk_pc6_msb_default = 'h0;
//-- Default hbm_axi4_addr_3in3_bsk_pc7_lsb
  logic [REG_DATA_W-1:0]hbm_axi4_addr_3in3_bsk_pc7_lsb_default;
  assign hbm_axi4_addr_3in3_bsk_pc7_lsb_default = 'h0;
//-- Default hbm_axi4_addr_3in3_bsk_pc7_msb
  logic [REG_DATA_W-1:0]hbm_axi4_addr_3in3_bsk_pc7_msb_default;
  assign hbm_axi4_addr_3in3_bsk_pc7_msb_default = 'h0;
//-- Default hbm_axi4_addr_3in3_bsk_pc8_lsb
  logic [REG_DATA_W-1:0]hbm_axi4_addr_3in3_bsk_pc8_lsb_default;
  assign hbm_axi4_addr_3in3_bsk_pc8_lsb_default = 'h0;
//-- Default hbm_axi4_addr_3in3_bsk_pc8_msb
  logic [REG_DATA_W-1:0]hbm_axi4_addr_3in3_bsk_pc8_msb_default;
  assign hbm_axi4_addr_3in3_bsk_pc8_msb_default = 'h0;
//-- Default hbm_axi4_addr_3in3_bsk_pc9_lsb
  logic [REG_DATA_W-1:0]hbm_axi4_addr_3in3_bsk_pc9_lsb_default;
  assign hbm_axi4_addr_3in3_bsk_pc9_lsb_default = 'h0;
//-- Default hbm_axi4_addr_3in3_bsk_pc9_msb
  logic [REG_DATA_W-1:0]hbm_axi4_addr_3in3_bsk_pc9_msb_default;
  assign hbm_axi4_addr_3in3_bsk_pc9_msb_default = 'h0;
//-- Default hbm_axi4_addr_3in3_bsk_pc10_lsb
  logic [REG_DATA_W-1:0]hbm_axi4_addr_3in3_bsk_pc10_lsb_default;
  assign hbm_axi4_addr_3in3_bsk_pc10_lsb_default = 'h0;
//-- Default hbm_axi4_addr_3in3_bsk_pc10_msb
  logic [REG_DATA_W-1:0]hbm_axi4_addr_3in3_bsk_pc10_msb_default;
  assign hbm_axi4_addr_3in3_bsk_pc10_msb_default = 'h0;
//-- Default hbm_axi4_addr_3in3_bsk_pc11_lsb
  logic [REG_DATA_W-1:0]hbm_axi4_addr_3in3_bsk_pc11_lsb_default;
  assign hbm_axi4_addr_3in3_bsk_pc11_lsb_default = 'h0;
//-- Default hbm_axi4_addr_3in3_bsk_pc11_msb
  logic [REG_DATA_W-1:0]hbm_axi4_addr_3in3_bsk_pc11_msb_default;
  assign hbm_axi4_addr_3in3_bsk_pc11_msb_default = 'h0;
//-- Default hbm_axi4_addr_3in3_bsk_pc12_lsb
  logic [REG_DATA_W-1:0]hbm_axi4_addr_3in3_bsk_pc12_lsb_default;
  assign hbm_axi4_addr_3in3_bsk_pc12_lsb_default = 'h0;
//-- Default hbm_axi4_addr_3in3_bsk_pc12_msb
  logic [REG_DATA_W-1:0]hbm_axi4_addr_3in3_bsk_pc12_msb_default;
  assign hbm_axi4_addr_3in3_bsk_pc12_msb_default = 'h0;
//-- Default hbm_axi4_addr_3in3_bsk_pc13_lsb
  logic [REG_DATA_W-1:0]hbm_axi4_addr_3in3_bsk_pc13_lsb_default;
  assign hbm_axi4_addr_3in3_bsk_pc13_lsb_default = 'h0;
//-- Default hbm_axi4_addr_3in3_bsk_pc13_msb
  logic [REG_DATA_W-1:0]hbm_axi4_addr_3in3_bsk_pc13_msb_default;
  assign hbm_axi4_addr_3in3_bsk_pc13_msb_default = 'h0;
//-- Default hbm_axi4_addr_3in3_bsk_pc14_lsb
  logic [REG_DATA_W-1:0]hbm_axi4_addr_3in3_bsk_pc14_lsb_default;
  assign hbm_axi4_addr_3in3_bsk_pc14_lsb_default = 'h0;
//-- Default hbm_axi4_addr_3in3_bsk_pc14_msb
  logic [REG_DATA_W-1:0]hbm_axi4_addr_3in3_bsk_pc14_msb_default;
  assign hbm_axi4_addr_3in3_bsk_pc14_msb_default = 'h0;
//-- Default hbm_axi4_addr_3in3_bsk_pc15_lsb
  logic [REG_DATA_W-1:0]hbm_axi4_addr_3in3_bsk_pc15_lsb_default;
  assign hbm_axi4_addr_3in3_bsk_pc15_lsb_default = 'h0;
//-- Default hbm_axi4_addr_3in3_bsk_pc15_msb
  logic [REG_DATA_W-1:0]hbm_axi4_addr_3in3_bsk_pc15_msb_default;
  assign hbm_axi4_addr_3in3_bsk_pc15_msb_default = 'h0;
//-- Default hpu_reset_trigger
  hpu_reset_trigger_t hpu_reset_trigger_default;
  always_comb begin
    hpu_reset_trigger_default = 'h0;
    hpu_reset_trigger_default.request = 'h0;
    hpu_reset_trigger_default.done = 'h0;
  end
// ============================================================================================== --
// Write reg
// ============================================================================================== --
  // To ease the code, use REG_DATA_W as register size.
  // Unused bits will be simplified by the synthesizer
// Register FF: hbm_axi4_addr_3in3_bsk_pc0_lsb
  logic [REG_DATA_W-1:0] r_hbm_axi4_addr_3in3_bsk_pc0_lsbD;
  assign r_hbm_axi4_addr_3in3_bsk_pc0_lsbD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == HBM_AXI4_ADDR_3IN3_BSK_PC0_LSB_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_hbm_axi4_addr_3in3_bsk_pc0_lsb;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_hbm_axi4_addr_3in3_bsk_pc0_lsb       <= hbm_axi4_addr_3in3_bsk_pc0_lsb_default;
    end
    else begin
      r_hbm_axi4_addr_3in3_bsk_pc0_lsb       <= r_hbm_axi4_addr_3in3_bsk_pc0_lsbD;
    end
  end
// Register FF: hbm_axi4_addr_3in3_bsk_pc0_msb
  logic [REG_DATA_W-1:0] r_hbm_axi4_addr_3in3_bsk_pc0_msbD;
  assign r_hbm_axi4_addr_3in3_bsk_pc0_msbD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == HBM_AXI4_ADDR_3IN3_BSK_PC0_MSB_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_hbm_axi4_addr_3in3_bsk_pc0_msb;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_hbm_axi4_addr_3in3_bsk_pc0_msb       <= hbm_axi4_addr_3in3_bsk_pc0_msb_default;
    end
    else begin
      r_hbm_axi4_addr_3in3_bsk_pc0_msb       <= r_hbm_axi4_addr_3in3_bsk_pc0_msbD;
    end
  end
// Register FF: hbm_axi4_addr_3in3_bsk_pc1_lsb
  logic [REG_DATA_W-1:0] r_hbm_axi4_addr_3in3_bsk_pc1_lsbD;
  assign r_hbm_axi4_addr_3in3_bsk_pc1_lsbD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == HBM_AXI4_ADDR_3IN3_BSK_PC1_LSB_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_hbm_axi4_addr_3in3_bsk_pc1_lsb;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_hbm_axi4_addr_3in3_bsk_pc1_lsb       <= hbm_axi4_addr_3in3_bsk_pc1_lsb_default;
    end
    else begin
      r_hbm_axi4_addr_3in3_bsk_pc1_lsb       <= r_hbm_axi4_addr_3in3_bsk_pc1_lsbD;
    end
  end
// Register FF: hbm_axi4_addr_3in3_bsk_pc1_msb
  logic [REG_DATA_W-1:0] r_hbm_axi4_addr_3in3_bsk_pc1_msbD;
  assign r_hbm_axi4_addr_3in3_bsk_pc1_msbD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == HBM_AXI4_ADDR_3IN3_BSK_PC1_MSB_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_hbm_axi4_addr_3in3_bsk_pc1_msb;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_hbm_axi4_addr_3in3_bsk_pc1_msb       <= hbm_axi4_addr_3in3_bsk_pc1_msb_default;
    end
    else begin
      r_hbm_axi4_addr_3in3_bsk_pc1_msb       <= r_hbm_axi4_addr_3in3_bsk_pc1_msbD;
    end
  end
// Register FF: hbm_axi4_addr_3in3_bsk_pc2_lsb
  logic [REG_DATA_W-1:0] r_hbm_axi4_addr_3in3_bsk_pc2_lsbD;
  assign r_hbm_axi4_addr_3in3_bsk_pc2_lsbD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == HBM_AXI4_ADDR_3IN3_BSK_PC2_LSB_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_hbm_axi4_addr_3in3_bsk_pc2_lsb;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_hbm_axi4_addr_3in3_bsk_pc2_lsb       <= hbm_axi4_addr_3in3_bsk_pc2_lsb_default;
    end
    else begin
      r_hbm_axi4_addr_3in3_bsk_pc2_lsb       <= r_hbm_axi4_addr_3in3_bsk_pc2_lsbD;
    end
  end
// Register FF: hbm_axi4_addr_3in3_bsk_pc2_msb
  logic [REG_DATA_W-1:0] r_hbm_axi4_addr_3in3_bsk_pc2_msbD;
  assign r_hbm_axi4_addr_3in3_bsk_pc2_msbD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == HBM_AXI4_ADDR_3IN3_BSK_PC2_MSB_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_hbm_axi4_addr_3in3_bsk_pc2_msb;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_hbm_axi4_addr_3in3_bsk_pc2_msb       <= hbm_axi4_addr_3in3_bsk_pc2_msb_default;
    end
    else begin
      r_hbm_axi4_addr_3in3_bsk_pc2_msb       <= r_hbm_axi4_addr_3in3_bsk_pc2_msbD;
    end
  end
// Register FF: hbm_axi4_addr_3in3_bsk_pc3_lsb
  logic [REG_DATA_W-1:0] r_hbm_axi4_addr_3in3_bsk_pc3_lsbD;
  assign r_hbm_axi4_addr_3in3_bsk_pc3_lsbD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == HBM_AXI4_ADDR_3IN3_BSK_PC3_LSB_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_hbm_axi4_addr_3in3_bsk_pc3_lsb;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_hbm_axi4_addr_3in3_bsk_pc3_lsb       <= hbm_axi4_addr_3in3_bsk_pc3_lsb_default;
    end
    else begin
      r_hbm_axi4_addr_3in3_bsk_pc3_lsb       <= r_hbm_axi4_addr_3in3_bsk_pc3_lsbD;
    end
  end
// Register FF: hbm_axi4_addr_3in3_bsk_pc3_msb
  logic [REG_DATA_W-1:0] r_hbm_axi4_addr_3in3_bsk_pc3_msbD;
  assign r_hbm_axi4_addr_3in3_bsk_pc3_msbD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == HBM_AXI4_ADDR_3IN3_BSK_PC3_MSB_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_hbm_axi4_addr_3in3_bsk_pc3_msb;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_hbm_axi4_addr_3in3_bsk_pc3_msb       <= hbm_axi4_addr_3in3_bsk_pc3_msb_default;
    end
    else begin
      r_hbm_axi4_addr_3in3_bsk_pc3_msb       <= r_hbm_axi4_addr_3in3_bsk_pc3_msbD;
    end
  end
// Register FF: hbm_axi4_addr_3in3_bsk_pc4_lsb
  logic [REG_DATA_W-1:0] r_hbm_axi4_addr_3in3_bsk_pc4_lsbD;
  assign r_hbm_axi4_addr_3in3_bsk_pc4_lsbD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == HBM_AXI4_ADDR_3IN3_BSK_PC4_LSB_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_hbm_axi4_addr_3in3_bsk_pc4_lsb;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_hbm_axi4_addr_3in3_bsk_pc4_lsb       <= hbm_axi4_addr_3in3_bsk_pc4_lsb_default;
    end
    else begin
      r_hbm_axi4_addr_3in3_bsk_pc4_lsb       <= r_hbm_axi4_addr_3in3_bsk_pc4_lsbD;
    end
  end
// Register FF: hbm_axi4_addr_3in3_bsk_pc4_msb
  logic [REG_DATA_W-1:0] r_hbm_axi4_addr_3in3_bsk_pc4_msbD;
  assign r_hbm_axi4_addr_3in3_bsk_pc4_msbD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == HBM_AXI4_ADDR_3IN3_BSK_PC4_MSB_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_hbm_axi4_addr_3in3_bsk_pc4_msb;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_hbm_axi4_addr_3in3_bsk_pc4_msb       <= hbm_axi4_addr_3in3_bsk_pc4_msb_default;
    end
    else begin
      r_hbm_axi4_addr_3in3_bsk_pc4_msb       <= r_hbm_axi4_addr_3in3_bsk_pc4_msbD;
    end
  end
// Register FF: hbm_axi4_addr_3in3_bsk_pc5_lsb
  logic [REG_DATA_W-1:0] r_hbm_axi4_addr_3in3_bsk_pc5_lsbD;
  assign r_hbm_axi4_addr_3in3_bsk_pc5_lsbD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == HBM_AXI4_ADDR_3IN3_BSK_PC5_LSB_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_hbm_axi4_addr_3in3_bsk_pc5_lsb;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_hbm_axi4_addr_3in3_bsk_pc5_lsb       <= hbm_axi4_addr_3in3_bsk_pc5_lsb_default;
    end
    else begin
      r_hbm_axi4_addr_3in3_bsk_pc5_lsb       <= r_hbm_axi4_addr_3in3_bsk_pc5_lsbD;
    end
  end
// Register FF: hbm_axi4_addr_3in3_bsk_pc5_msb
  logic [REG_DATA_W-1:0] r_hbm_axi4_addr_3in3_bsk_pc5_msbD;
  assign r_hbm_axi4_addr_3in3_bsk_pc5_msbD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == HBM_AXI4_ADDR_3IN3_BSK_PC5_MSB_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_hbm_axi4_addr_3in3_bsk_pc5_msb;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_hbm_axi4_addr_3in3_bsk_pc5_msb       <= hbm_axi4_addr_3in3_bsk_pc5_msb_default;
    end
    else begin
      r_hbm_axi4_addr_3in3_bsk_pc5_msb       <= r_hbm_axi4_addr_3in3_bsk_pc5_msbD;
    end
  end
// Register FF: hbm_axi4_addr_3in3_bsk_pc6_lsb
  logic [REG_DATA_W-1:0] r_hbm_axi4_addr_3in3_bsk_pc6_lsbD;
  assign r_hbm_axi4_addr_3in3_bsk_pc6_lsbD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == HBM_AXI4_ADDR_3IN3_BSK_PC6_LSB_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_hbm_axi4_addr_3in3_bsk_pc6_lsb;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_hbm_axi4_addr_3in3_bsk_pc6_lsb       <= hbm_axi4_addr_3in3_bsk_pc6_lsb_default;
    end
    else begin
      r_hbm_axi4_addr_3in3_bsk_pc6_lsb       <= r_hbm_axi4_addr_3in3_bsk_pc6_lsbD;
    end
  end
// Register FF: hbm_axi4_addr_3in3_bsk_pc6_msb
  logic [REG_DATA_W-1:0] r_hbm_axi4_addr_3in3_bsk_pc6_msbD;
  assign r_hbm_axi4_addr_3in3_bsk_pc6_msbD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == HBM_AXI4_ADDR_3IN3_BSK_PC6_MSB_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_hbm_axi4_addr_3in3_bsk_pc6_msb;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_hbm_axi4_addr_3in3_bsk_pc6_msb       <= hbm_axi4_addr_3in3_bsk_pc6_msb_default;
    end
    else begin
      r_hbm_axi4_addr_3in3_bsk_pc6_msb       <= r_hbm_axi4_addr_3in3_bsk_pc6_msbD;
    end
  end
// Register FF: hbm_axi4_addr_3in3_bsk_pc7_lsb
  logic [REG_DATA_W-1:0] r_hbm_axi4_addr_3in3_bsk_pc7_lsbD;
  assign r_hbm_axi4_addr_3in3_bsk_pc7_lsbD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == HBM_AXI4_ADDR_3IN3_BSK_PC7_LSB_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_hbm_axi4_addr_3in3_bsk_pc7_lsb;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_hbm_axi4_addr_3in3_bsk_pc7_lsb       <= hbm_axi4_addr_3in3_bsk_pc7_lsb_default;
    end
    else begin
      r_hbm_axi4_addr_3in3_bsk_pc7_lsb       <= r_hbm_axi4_addr_3in3_bsk_pc7_lsbD;
    end
  end
// Register FF: hbm_axi4_addr_3in3_bsk_pc7_msb
  logic [REG_DATA_W-1:0] r_hbm_axi4_addr_3in3_bsk_pc7_msbD;
  assign r_hbm_axi4_addr_3in3_bsk_pc7_msbD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == HBM_AXI4_ADDR_3IN3_BSK_PC7_MSB_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_hbm_axi4_addr_3in3_bsk_pc7_msb;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_hbm_axi4_addr_3in3_bsk_pc7_msb       <= hbm_axi4_addr_3in3_bsk_pc7_msb_default;
    end
    else begin
      r_hbm_axi4_addr_3in3_bsk_pc7_msb       <= r_hbm_axi4_addr_3in3_bsk_pc7_msbD;
    end
  end
// Register FF: hbm_axi4_addr_3in3_bsk_pc8_lsb
  logic [REG_DATA_W-1:0] r_hbm_axi4_addr_3in3_bsk_pc8_lsbD;
  assign r_hbm_axi4_addr_3in3_bsk_pc8_lsbD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == HBM_AXI4_ADDR_3IN3_BSK_PC8_LSB_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_hbm_axi4_addr_3in3_bsk_pc8_lsb;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_hbm_axi4_addr_3in3_bsk_pc8_lsb       <= hbm_axi4_addr_3in3_bsk_pc8_lsb_default;
    end
    else begin
      r_hbm_axi4_addr_3in3_bsk_pc8_lsb       <= r_hbm_axi4_addr_3in3_bsk_pc8_lsbD;
    end
  end
// Register FF: hbm_axi4_addr_3in3_bsk_pc8_msb
  logic [REG_DATA_W-1:0] r_hbm_axi4_addr_3in3_bsk_pc8_msbD;
  assign r_hbm_axi4_addr_3in3_bsk_pc8_msbD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == HBM_AXI4_ADDR_3IN3_BSK_PC8_MSB_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_hbm_axi4_addr_3in3_bsk_pc8_msb;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_hbm_axi4_addr_3in3_bsk_pc8_msb       <= hbm_axi4_addr_3in3_bsk_pc8_msb_default;
    end
    else begin
      r_hbm_axi4_addr_3in3_bsk_pc8_msb       <= r_hbm_axi4_addr_3in3_bsk_pc8_msbD;
    end
  end
// Register FF: hbm_axi4_addr_3in3_bsk_pc9_lsb
  logic [REG_DATA_W-1:0] r_hbm_axi4_addr_3in3_bsk_pc9_lsbD;
  assign r_hbm_axi4_addr_3in3_bsk_pc9_lsbD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == HBM_AXI4_ADDR_3IN3_BSK_PC9_LSB_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_hbm_axi4_addr_3in3_bsk_pc9_lsb;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_hbm_axi4_addr_3in3_bsk_pc9_lsb       <= hbm_axi4_addr_3in3_bsk_pc9_lsb_default;
    end
    else begin
      r_hbm_axi4_addr_3in3_bsk_pc9_lsb       <= r_hbm_axi4_addr_3in3_bsk_pc9_lsbD;
    end
  end
// Register FF: hbm_axi4_addr_3in3_bsk_pc9_msb
  logic [REG_DATA_W-1:0] r_hbm_axi4_addr_3in3_bsk_pc9_msbD;
  assign r_hbm_axi4_addr_3in3_bsk_pc9_msbD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == HBM_AXI4_ADDR_3IN3_BSK_PC9_MSB_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_hbm_axi4_addr_3in3_bsk_pc9_msb;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_hbm_axi4_addr_3in3_bsk_pc9_msb       <= hbm_axi4_addr_3in3_bsk_pc9_msb_default;
    end
    else begin
      r_hbm_axi4_addr_3in3_bsk_pc9_msb       <= r_hbm_axi4_addr_3in3_bsk_pc9_msbD;
    end
  end
// Register FF: hbm_axi4_addr_3in3_bsk_pc10_lsb
  logic [REG_DATA_W-1:0] r_hbm_axi4_addr_3in3_bsk_pc10_lsbD;
  assign r_hbm_axi4_addr_3in3_bsk_pc10_lsbD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == HBM_AXI4_ADDR_3IN3_BSK_PC10_LSB_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_hbm_axi4_addr_3in3_bsk_pc10_lsb;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_hbm_axi4_addr_3in3_bsk_pc10_lsb       <= hbm_axi4_addr_3in3_bsk_pc10_lsb_default;
    end
    else begin
      r_hbm_axi4_addr_3in3_bsk_pc10_lsb       <= r_hbm_axi4_addr_3in3_bsk_pc10_lsbD;
    end
  end
// Register FF: hbm_axi4_addr_3in3_bsk_pc10_msb
  logic [REG_DATA_W-1:0] r_hbm_axi4_addr_3in3_bsk_pc10_msbD;
  assign r_hbm_axi4_addr_3in3_bsk_pc10_msbD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == HBM_AXI4_ADDR_3IN3_BSK_PC10_MSB_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_hbm_axi4_addr_3in3_bsk_pc10_msb;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_hbm_axi4_addr_3in3_bsk_pc10_msb       <= hbm_axi4_addr_3in3_bsk_pc10_msb_default;
    end
    else begin
      r_hbm_axi4_addr_3in3_bsk_pc10_msb       <= r_hbm_axi4_addr_3in3_bsk_pc10_msbD;
    end
  end
// Register FF: hbm_axi4_addr_3in3_bsk_pc11_lsb
  logic [REG_DATA_W-1:0] r_hbm_axi4_addr_3in3_bsk_pc11_lsbD;
  assign r_hbm_axi4_addr_3in3_bsk_pc11_lsbD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == HBM_AXI4_ADDR_3IN3_BSK_PC11_LSB_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_hbm_axi4_addr_3in3_bsk_pc11_lsb;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_hbm_axi4_addr_3in3_bsk_pc11_lsb       <= hbm_axi4_addr_3in3_bsk_pc11_lsb_default;
    end
    else begin
      r_hbm_axi4_addr_3in3_bsk_pc11_lsb       <= r_hbm_axi4_addr_3in3_bsk_pc11_lsbD;
    end
  end
// Register FF: hbm_axi4_addr_3in3_bsk_pc11_msb
  logic [REG_DATA_W-1:0] r_hbm_axi4_addr_3in3_bsk_pc11_msbD;
  assign r_hbm_axi4_addr_3in3_bsk_pc11_msbD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == HBM_AXI4_ADDR_3IN3_BSK_PC11_MSB_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_hbm_axi4_addr_3in3_bsk_pc11_msb;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_hbm_axi4_addr_3in3_bsk_pc11_msb       <= hbm_axi4_addr_3in3_bsk_pc11_msb_default;
    end
    else begin
      r_hbm_axi4_addr_3in3_bsk_pc11_msb       <= r_hbm_axi4_addr_3in3_bsk_pc11_msbD;
    end
  end
// Register FF: hbm_axi4_addr_3in3_bsk_pc12_lsb
  logic [REG_DATA_W-1:0] r_hbm_axi4_addr_3in3_bsk_pc12_lsbD;
  assign r_hbm_axi4_addr_3in3_bsk_pc12_lsbD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == HBM_AXI4_ADDR_3IN3_BSK_PC12_LSB_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_hbm_axi4_addr_3in3_bsk_pc12_lsb;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_hbm_axi4_addr_3in3_bsk_pc12_lsb       <= hbm_axi4_addr_3in3_bsk_pc12_lsb_default;
    end
    else begin
      r_hbm_axi4_addr_3in3_bsk_pc12_lsb       <= r_hbm_axi4_addr_3in3_bsk_pc12_lsbD;
    end
  end
// Register FF: hbm_axi4_addr_3in3_bsk_pc12_msb
  logic [REG_DATA_W-1:0] r_hbm_axi4_addr_3in3_bsk_pc12_msbD;
  assign r_hbm_axi4_addr_3in3_bsk_pc12_msbD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == HBM_AXI4_ADDR_3IN3_BSK_PC12_MSB_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_hbm_axi4_addr_3in3_bsk_pc12_msb;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_hbm_axi4_addr_3in3_bsk_pc12_msb       <= hbm_axi4_addr_3in3_bsk_pc12_msb_default;
    end
    else begin
      r_hbm_axi4_addr_3in3_bsk_pc12_msb       <= r_hbm_axi4_addr_3in3_bsk_pc12_msbD;
    end
  end
// Register FF: hbm_axi4_addr_3in3_bsk_pc13_lsb
  logic [REG_DATA_W-1:0] r_hbm_axi4_addr_3in3_bsk_pc13_lsbD;
  assign r_hbm_axi4_addr_3in3_bsk_pc13_lsbD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == HBM_AXI4_ADDR_3IN3_BSK_PC13_LSB_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_hbm_axi4_addr_3in3_bsk_pc13_lsb;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_hbm_axi4_addr_3in3_bsk_pc13_lsb       <= hbm_axi4_addr_3in3_bsk_pc13_lsb_default;
    end
    else begin
      r_hbm_axi4_addr_3in3_bsk_pc13_lsb       <= r_hbm_axi4_addr_3in3_bsk_pc13_lsbD;
    end
  end
// Register FF: hbm_axi4_addr_3in3_bsk_pc13_msb
  logic [REG_DATA_W-1:0] r_hbm_axi4_addr_3in3_bsk_pc13_msbD;
  assign r_hbm_axi4_addr_3in3_bsk_pc13_msbD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == HBM_AXI4_ADDR_3IN3_BSK_PC13_MSB_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_hbm_axi4_addr_3in3_bsk_pc13_msb;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_hbm_axi4_addr_3in3_bsk_pc13_msb       <= hbm_axi4_addr_3in3_bsk_pc13_msb_default;
    end
    else begin
      r_hbm_axi4_addr_3in3_bsk_pc13_msb       <= r_hbm_axi4_addr_3in3_bsk_pc13_msbD;
    end
  end
// Register FF: hbm_axi4_addr_3in3_bsk_pc14_lsb
  logic [REG_DATA_W-1:0] r_hbm_axi4_addr_3in3_bsk_pc14_lsbD;
  assign r_hbm_axi4_addr_3in3_bsk_pc14_lsbD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == HBM_AXI4_ADDR_3IN3_BSK_PC14_LSB_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_hbm_axi4_addr_3in3_bsk_pc14_lsb;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_hbm_axi4_addr_3in3_bsk_pc14_lsb       <= hbm_axi4_addr_3in3_bsk_pc14_lsb_default;
    end
    else begin
      r_hbm_axi4_addr_3in3_bsk_pc14_lsb       <= r_hbm_axi4_addr_3in3_bsk_pc14_lsbD;
    end
  end
// Register FF: hbm_axi4_addr_3in3_bsk_pc14_msb
  logic [REG_DATA_W-1:0] r_hbm_axi4_addr_3in3_bsk_pc14_msbD;
  assign r_hbm_axi4_addr_3in3_bsk_pc14_msbD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == HBM_AXI4_ADDR_3IN3_BSK_PC14_MSB_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_hbm_axi4_addr_3in3_bsk_pc14_msb;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_hbm_axi4_addr_3in3_bsk_pc14_msb       <= hbm_axi4_addr_3in3_bsk_pc14_msb_default;
    end
    else begin
      r_hbm_axi4_addr_3in3_bsk_pc14_msb       <= r_hbm_axi4_addr_3in3_bsk_pc14_msbD;
    end
  end
// Register FF: hbm_axi4_addr_3in3_bsk_pc15_lsb
  logic [REG_DATA_W-1:0] r_hbm_axi4_addr_3in3_bsk_pc15_lsbD;
  assign r_hbm_axi4_addr_3in3_bsk_pc15_lsbD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == HBM_AXI4_ADDR_3IN3_BSK_PC15_LSB_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_hbm_axi4_addr_3in3_bsk_pc15_lsb;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_hbm_axi4_addr_3in3_bsk_pc15_lsb       <= hbm_axi4_addr_3in3_bsk_pc15_lsb_default;
    end
    else begin
      r_hbm_axi4_addr_3in3_bsk_pc15_lsb       <= r_hbm_axi4_addr_3in3_bsk_pc15_lsbD;
    end
  end
// Register FF: hbm_axi4_addr_3in3_bsk_pc15_msb
  logic [REG_DATA_W-1:0] r_hbm_axi4_addr_3in3_bsk_pc15_msbD;
  assign r_hbm_axi4_addr_3in3_bsk_pc15_msbD = (wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == HBM_AXI4_ADDR_3IN3_BSK_PC15_MSB_OFS[AXIL_ADD_RANGE_W-1:0]))? wr_data: r_hbm_axi4_addr_3in3_bsk_pc15_msb;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_hbm_axi4_addr_3in3_bsk_pc15_msb       <= hbm_axi4_addr_3in3_bsk_pc15_msb_default;
    end
    else begin
      r_hbm_axi4_addr_3in3_bsk_pc15_msb       <= r_hbm_axi4_addr_3in3_bsk_pc15_msbD;
    end
  end
// Register FF: hpu_reset_trigger
  logic [REG_DATA_W-1:0] r_hpu_reset_triggerD;
  assign r_hpu_reset_triggerD       = r_hpu_reset_trigger_upd;
  logic r_hpu_reset_trigger_wr_enD;
  assign r_hpu_reset_trigger_wr_enD = wr_en_ok && (wr_add[AXIL_ADD_RANGE_W-1:0] == HPU_RESET_TRIGGER_OFS[AXIL_ADD_RANGE_W-1:0]);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_hpu_reset_trigger_wr_en <= 1'b0;
    end
    else begin
      r_hpu_reset_trigger_wr_en <= r_hpu_reset_trigger_wr_enD;
    end
  end
  assign r_hpu_reset_trigger_rd_en = rd_en_ok && (rd_add[AXIL_ADD_RANGE_W-1:0] == HPU_RESET_TRIGGER_OFS[AXIL_ADD_RANGE_W-1:0]);
  assign r_hpu_reset_trigger = r_hpu_reset_trigger_upd;
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
          ENTRY_CFG_3IN3_DUMMY_VAL0_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register entry_cfg_3in3_dummy_val0
            axil_rdataD = entry_cfg_3in3_dummy_val0_default;
          end
          ENTRY_CFG_3IN3_DUMMY_VAL1_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register entry_cfg_3in3_dummy_val1
            axil_rdataD = entry_cfg_3in3_dummy_val1_default;
          end
          ENTRY_CFG_3IN3_DUMMY_VAL2_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register entry_cfg_3in3_dummy_val2
            axil_rdataD = entry_cfg_3in3_dummy_val2_default;
          end
          ENTRY_CFG_3IN3_DUMMY_VAL3_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register entry_cfg_3in3_dummy_val3
            axil_rdataD = entry_cfg_3in3_dummy_val3_default;
          end
          HBM_AXI4_ADDR_3IN3_BSK_PC0_LSB_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register hbm_axi4_addr_3in3_bsk_pc0_lsb
            axil_rdataD = r_hbm_axi4_addr_3in3_bsk_pc0_lsb;
          end
          HBM_AXI4_ADDR_3IN3_BSK_PC0_MSB_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register hbm_axi4_addr_3in3_bsk_pc0_msb
            axil_rdataD = r_hbm_axi4_addr_3in3_bsk_pc0_msb;
          end
          HBM_AXI4_ADDR_3IN3_BSK_PC1_LSB_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register hbm_axi4_addr_3in3_bsk_pc1_lsb
            axil_rdataD = r_hbm_axi4_addr_3in3_bsk_pc1_lsb;
          end
          HBM_AXI4_ADDR_3IN3_BSK_PC1_MSB_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register hbm_axi4_addr_3in3_bsk_pc1_msb
            axil_rdataD = r_hbm_axi4_addr_3in3_bsk_pc1_msb;
          end
          HBM_AXI4_ADDR_3IN3_BSK_PC2_LSB_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register hbm_axi4_addr_3in3_bsk_pc2_lsb
            axil_rdataD = r_hbm_axi4_addr_3in3_bsk_pc2_lsb;
          end
          HBM_AXI4_ADDR_3IN3_BSK_PC2_MSB_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register hbm_axi4_addr_3in3_bsk_pc2_msb
            axil_rdataD = r_hbm_axi4_addr_3in3_bsk_pc2_msb;
          end
          HBM_AXI4_ADDR_3IN3_BSK_PC3_LSB_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register hbm_axi4_addr_3in3_bsk_pc3_lsb
            axil_rdataD = r_hbm_axi4_addr_3in3_bsk_pc3_lsb;
          end
          HBM_AXI4_ADDR_3IN3_BSK_PC3_MSB_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register hbm_axi4_addr_3in3_bsk_pc3_msb
            axil_rdataD = r_hbm_axi4_addr_3in3_bsk_pc3_msb;
          end
          HBM_AXI4_ADDR_3IN3_BSK_PC4_LSB_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register hbm_axi4_addr_3in3_bsk_pc4_lsb
            axil_rdataD = r_hbm_axi4_addr_3in3_bsk_pc4_lsb;
          end
          HBM_AXI4_ADDR_3IN3_BSK_PC4_MSB_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register hbm_axi4_addr_3in3_bsk_pc4_msb
            axil_rdataD = r_hbm_axi4_addr_3in3_bsk_pc4_msb;
          end
          HBM_AXI4_ADDR_3IN3_BSK_PC5_LSB_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register hbm_axi4_addr_3in3_bsk_pc5_lsb
            axil_rdataD = r_hbm_axi4_addr_3in3_bsk_pc5_lsb;
          end
          HBM_AXI4_ADDR_3IN3_BSK_PC5_MSB_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register hbm_axi4_addr_3in3_bsk_pc5_msb
            axil_rdataD = r_hbm_axi4_addr_3in3_bsk_pc5_msb;
          end
          HBM_AXI4_ADDR_3IN3_BSK_PC6_LSB_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register hbm_axi4_addr_3in3_bsk_pc6_lsb
            axil_rdataD = r_hbm_axi4_addr_3in3_bsk_pc6_lsb;
          end
          HBM_AXI4_ADDR_3IN3_BSK_PC6_MSB_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register hbm_axi4_addr_3in3_bsk_pc6_msb
            axil_rdataD = r_hbm_axi4_addr_3in3_bsk_pc6_msb;
          end
          HBM_AXI4_ADDR_3IN3_BSK_PC7_LSB_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register hbm_axi4_addr_3in3_bsk_pc7_lsb
            axil_rdataD = r_hbm_axi4_addr_3in3_bsk_pc7_lsb;
          end
          HBM_AXI4_ADDR_3IN3_BSK_PC7_MSB_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register hbm_axi4_addr_3in3_bsk_pc7_msb
            axil_rdataD = r_hbm_axi4_addr_3in3_bsk_pc7_msb;
          end
          HBM_AXI4_ADDR_3IN3_BSK_PC8_LSB_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register hbm_axi4_addr_3in3_bsk_pc8_lsb
            axil_rdataD = r_hbm_axi4_addr_3in3_bsk_pc8_lsb;
          end
          HBM_AXI4_ADDR_3IN3_BSK_PC8_MSB_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register hbm_axi4_addr_3in3_bsk_pc8_msb
            axil_rdataD = r_hbm_axi4_addr_3in3_bsk_pc8_msb;
          end
          HBM_AXI4_ADDR_3IN3_BSK_PC9_LSB_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register hbm_axi4_addr_3in3_bsk_pc9_lsb
            axil_rdataD = r_hbm_axi4_addr_3in3_bsk_pc9_lsb;
          end
          HBM_AXI4_ADDR_3IN3_BSK_PC9_MSB_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register hbm_axi4_addr_3in3_bsk_pc9_msb
            axil_rdataD = r_hbm_axi4_addr_3in3_bsk_pc9_msb;
          end
          HBM_AXI4_ADDR_3IN3_BSK_PC10_LSB_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register hbm_axi4_addr_3in3_bsk_pc10_lsb
            axil_rdataD = r_hbm_axi4_addr_3in3_bsk_pc10_lsb;
          end
          HBM_AXI4_ADDR_3IN3_BSK_PC10_MSB_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register hbm_axi4_addr_3in3_bsk_pc10_msb
            axil_rdataD = r_hbm_axi4_addr_3in3_bsk_pc10_msb;
          end
          HBM_AXI4_ADDR_3IN3_BSK_PC11_LSB_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register hbm_axi4_addr_3in3_bsk_pc11_lsb
            axil_rdataD = r_hbm_axi4_addr_3in3_bsk_pc11_lsb;
          end
          HBM_AXI4_ADDR_3IN3_BSK_PC11_MSB_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register hbm_axi4_addr_3in3_bsk_pc11_msb
            axil_rdataD = r_hbm_axi4_addr_3in3_bsk_pc11_msb;
          end
          HBM_AXI4_ADDR_3IN3_BSK_PC12_LSB_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register hbm_axi4_addr_3in3_bsk_pc12_lsb
            axil_rdataD = r_hbm_axi4_addr_3in3_bsk_pc12_lsb;
          end
          HBM_AXI4_ADDR_3IN3_BSK_PC12_MSB_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register hbm_axi4_addr_3in3_bsk_pc12_msb
            axil_rdataD = r_hbm_axi4_addr_3in3_bsk_pc12_msb;
          end
          HBM_AXI4_ADDR_3IN3_BSK_PC13_LSB_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register hbm_axi4_addr_3in3_bsk_pc13_lsb
            axil_rdataD = r_hbm_axi4_addr_3in3_bsk_pc13_lsb;
          end
          HBM_AXI4_ADDR_3IN3_BSK_PC13_MSB_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register hbm_axi4_addr_3in3_bsk_pc13_msb
            axil_rdataD = r_hbm_axi4_addr_3in3_bsk_pc13_msb;
          end
          HBM_AXI4_ADDR_3IN3_BSK_PC14_LSB_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register hbm_axi4_addr_3in3_bsk_pc14_lsb
            axil_rdataD = r_hbm_axi4_addr_3in3_bsk_pc14_lsb;
          end
          HBM_AXI4_ADDR_3IN3_BSK_PC14_MSB_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register hbm_axi4_addr_3in3_bsk_pc14_msb
            axil_rdataD = r_hbm_axi4_addr_3in3_bsk_pc14_msb;
          end
          HBM_AXI4_ADDR_3IN3_BSK_PC15_LSB_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register hbm_axi4_addr_3in3_bsk_pc15_lsb
            axil_rdataD = r_hbm_axi4_addr_3in3_bsk_pc15_lsb;
          end
          HBM_AXI4_ADDR_3IN3_BSK_PC15_MSB_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register hbm_axi4_addr_3in3_bsk_pc15_msb
            axil_rdataD = r_hbm_axi4_addr_3in3_bsk_pc15_msb;
          end
          HPU_RESET_TRIGGER_OFS[AXIL_ADD_RANGE_W-1:0]: begin // register hpu_reset_trigger
            axil_rdataD = r_hpu_reset_trigger;
          end
          default:
            axil_rdataD = REG_DATA_W'('h0BAD_ADD1); // Default value
          endcase // rd_add
        end
      end // if rd_end
    end
  end // always_comb - read
endmodule
