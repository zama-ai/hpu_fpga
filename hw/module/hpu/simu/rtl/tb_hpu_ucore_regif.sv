// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Axi4-lite register bank
// This file was generated with rust regmap generator:
//  * Date:  2025-01-22
//  * Tool_version: c0ba18d05e0ad364ef72741dd908ad38f42b8f15
// ----------------------------------------------------------------------------------------------
// xR[n]W[na]
// |-> who is in charge of the register update logic : u -> User
//                                                   : k -> Kernel (have a _upd signal)
//                                                   : p -> Parameters (i.e. constant register)
//  | Read options
//  | [n] optional generate read notification (have a _rd_en)
//  | Write options
//  | [n] optional generate wr notification (have a _wr_en)
//
// Thus following type of registers:
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
// ==============================================================================================

module tb_hpu_ucore_regif
import axi_if_common_param_pkg::*;
import axi_if_shell_axil_pkg::*;
import tb_hpu_ucore_regif_pkg::*;
#()(
  input  logic                           clk,
  input  logic                           s_rst_n,
  // Axi4 lite Slave Interface sAxi4
  input  logic [AXIL_ADD_W-1:0]          s_axi4l_awaddr,
  input  logic                           s_axi4l_awvalid,
  output logic                           s_axi4l_awready,
  input  logic [AXIL_DATA_W-1:0]         s_axi4l_wdata,
  input  logic                           s_axi4l_wvalid,
  output logic                           s_axi4l_wready,
  output logic [1:0]                     s_axi4l_bresp,
  output logic                           s_axi4l_bvalid,
  input  logic                           s_axi4l_bready,
  input  logic [AXIL_ADD_W-1:0]          s_axi4l_araddr,
  input  logic                           s_axi4l_arvalid,
  output logic                           s_axi4l_arready,
  output logic [AXIL_DATA_W-1:0]         s_axi4l_rdata,
  output logic [1:0]                     s_axi4l_rresp,
  output logic                           s_axi4l_rvalid,
  input  logic                           s_axi4l_rready,
  // Registered version of wdata
  output logic [AXIL_DATA_W-1:0]         r_axi4l_wdata
  // Register IO: WorkAck_workq
    , output logic [REG_DATA_W-1: 0] r_WorkAck_workq
        , input  logic [REG_DATA_W-1: 0] r_WorkAck_workq_upd
    , output logic r_WorkAck_workq_wr_en
  // Register IO: WorkAck_ackq
    , output WorkAck_ackq_t r_WorkAck_ackq
        , input WorkAck_ackq_t r_WorkAck_ackq_upd 
        , output logic r_WorkAck_ackq_rd_en
);
// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int AXI4L_ADD_OFS = 0;
  localparam int AXI4L_ADD_RANGE= 16;
// ============================================================================================== --
// Axi4l management
// ============================================================================================== --
  logic                    axi4l_awready;
  logic                    axi4l_wready;
  logic [1:0]              axi4l_bresp;
  logic                    axi4l_bvalid;
  logic                    axi4l_arready;
  logic [1:0]              axi4l_rresp;
  logic [AXIL_DATA_W-1:0]  axi4l_rdata;
  logic                    axi4l_rvalid;
  logic                    axi4l_awreadyD;
  logic                    axi4l_wreadyD;
  logic [1:0]              axi4l_brespD;
  logic                    axi4l_bvalidD;
  logic                    axi4l_arreadyD;
  logic [1:0]              axi4l_rrespD;
  logic [AXIL_DATA_W-1:0]  axi4l_rdataD;
  logic                    axi4l_rvalidD;
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
  //== Local read/write signals
  // Write when address and data are available.
  // Do not accept a new write request when the response
  // of previous request is still pending.
  // Since the ready is sent 1 cycle after the valid,
  // mask the cycle when the ready is r
  assign wr_enD   = (s_axi4l_awvalid & s_axi4l_wvalid
                     & ~(s_axi4l_awready | s_axi4l_wready)
                     & ~(s_axi4l_bvalid & ~s_axi4l_bready));
  assign wr_addD  = s_axi4l_awaddr;
  assign wr_dataD = s_axi4l_wdata;
  // Answer to read request 1 cycle after, when there is no pending read data.
  // Therefore, mask the rd_en during the 2nd cycle.
  assign rd_enD   = (s_axi4l_arvalid
                    & ~s_axi4l_arready
                    & ~(s_axi4l_rvalid & ~s_axi4l_rready));
  assign rd_addD  = s_axi4l_araddr;
  //== AXI4L write ready
  assign axi4l_awreadyD = wr_enD;
  assign axi4l_wreadyD  = wr_enD;
  //== AXI4L read address ready
  assign axi4l_arreadyD = rd_enD;
  //== AXI4L write resp
  logic [1:0]              axi4l_brespD_tmp;
  assign axi4l_bvalidD    = wr_en          ? 1'b1:
                            s_axi4l_bready ? 1'b0 : axi4l_bvalid;
  assign axi4l_brespD     = axi4l_bvalidD ? axi4l_brespD_tmp : '0;
  assign axi4l_brespD_tmp = (wr_add - AXI4L_ADD_OFS) < AXI4L_ADD_RANGE ? AXI4_OKAY : AXI4_SLVERR;
  //== AXI4L read resp
  assign axi4l_rvalidD    = rd_en          ? 1'b1 :
                            s_axi4l_rready ? 1'b0 : axi4l_rvalid;
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      axi4l_awready <= 1'b0;
      axi4l_wready  <= 1'b0;
      axi4l_bresp   <= 2'h0;
      axi4l_bvalid  <= 1'b0;
      axi4l_arready <= 1'b0;
      axi4l_rdata   <= 'h0;
      axi4l_rresp   <= 'h0;
      axi4l_rvalid  <= 1'b0;
      wr_en         <= 1'b0;
      rd_en         <= 1'b0;
    end
    else begin
      axi4l_awready <= axi4l_awreadyD;
      axi4l_wready  <= axi4l_wreadyD;
      axi4l_bresp   <= axi4l_brespD;
      axi4l_bvalid  <= axi4l_bvalidD;
      axi4l_arready <= axi4l_arreadyD;
      axi4l_rdata   <= axi4l_rdataD;
      axi4l_rresp   <= axi4l_rrespD;
      axi4l_rvalid  <= axi4l_rvalidD;
      wr_en         <= wr_enD;
      rd_en         <= rd_enD;
    end
  end
  always_ff @(posedge clk) begin
    wr_add  <= wr_addD;
    rd_add  <= rd_addD;
    wr_data <= wr_dataD;
  end
  //= Assignment
  assign s_axi4l_awready = axi4l_awready;
  assign s_axi4l_wready  = axi4l_wready;
  assign s_axi4l_bresp   = axi4l_bresp;
  assign s_axi4l_bvalid  = axi4l_bvalid;
  assign s_axi4l_arready = axi4l_arready;
  assign s_axi4l_rresp   = axi4l_rresp;
  assign s_axi4l_rdata   = axi4l_rdata;
  assign s_axi4l_rvalid  = axi4l_rvalid;
  assign r_axi4l_wdata    = wr_data;
// ============================================================================================== --
// Write reg
// ============================================================================================== --
  // To ease the code, use REG_DATA_W as register size.
  // Unused bits will be simplified by the synthesizer
// Register FF: WorkAck_workq
  logic [REG_DATA_W-1:0] r_WorkAck_workqD;
  assign r_WorkAck_workqD       = r_WorkAck_workq_upd;
  logic r_WorkAck_workq_wr_enD;
  assign r_WorkAck_workq_wr_enD = wr_en && (wr_add == WORKACK_WORKQ_OFS);
  always_ff @(posedge clk) begin
    if (!s_rst_n) begin
      r_WorkAck_workq       <= 'h0;
      r_WorkAck_workq_wr_en <= 1'b0;
    end
    else begin
      r_WorkAck_workq       <= r_WorkAck_workqD;
      r_WorkAck_workq_wr_en <= r_WorkAck_workq_wr_enD;
    end
  end
// Register FF: WorkAck_ackq
  logic [REG_DATA_W-1:0] r_WorkAck_ackqD;
  assign r_WorkAck_ackqD       = r_WorkAck_ackq_upd;
  assign r_WorkAck_ackq_rd_en = rd_en && (rd_add == WORKACK_ACKQ_OFS);
  assign r_WorkAck_ackq = r_WorkAck_ackq_upd;
// ============================================================================================== --
// Read reg
// ============================================================================================== --
  always_comb begin
    if (axi4l_rvalid) begin
      axi4l_rdataD = s_axi4l_rready ? '0 : axi4l_rdata;
      axi4l_rrespD = s_axi4l_rready ? '0 : axi4l_rresp;
    end
    else begin
      axi4l_rdataD = axi4l_rdata;
      axi4l_rrespD = axi4l_rresp;
      if (rd_en) begin
        axi4l_rrespD = AXI4_SLVERR;
        case(rd_add)
          WORKACK_WORKQ_OFS: begin // register WorkAck_workq
            axi4l_rrespD = AXI4_OKAY;
            axi4l_rdataD = r_WorkAck_workq;
          end
          WORKACK_ACKQ_OFS: begin // register WorkAck_ackq
            axi4l_rrespD = AXI4_OKAY;
            axi4l_rdataD = r_WorkAck_ackq;
          end
        endcase // rd_add
      end // if rd_end
    end
  end // always_comb - read
endmodule
