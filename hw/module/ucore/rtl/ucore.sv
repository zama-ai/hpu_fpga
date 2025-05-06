// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : ucore infrastructure
// ----------------------------------------------------------------------------------------------
//
// Thin-wrapper around ublaze.
// Integrate generic regif<->Queue logic with and fifo buffering on in/out axis_stream
// ==============================================================================================

module ucore
import ucore_pkg::*;
import axi_if_common_param_pkg::*;
import axi_if_ucore_axi_pkg::*;
import hpu_common_instruction_pkg::*;
 #(
  parameter int VERSION          = 1,
  parameter int AXI4_ADD_W       = 32
)(
  // System interface ---------------------------------------------------------
  input                              clk,   // clock
  input                              s_rst_n, // synchronous reset

  //== Axi4 Interface
  // Write channel
  output logic [AXI4_ID_W-1:0]       m_axi_awid, 
  output logic [AXI4_ADD_W-1:0]      m_axi_awaddr, 
  output logic [AXI4_LEN_W-1:0]      m_axi_awlen, 
  output logic [AXI4_SIZE_W-1:0]     m_axi_awsize, 
  output logic [AXI4_BURST_W-1:0]    m_axi_awburst, 
  output logic                       m_axi_awvalid, 
  input  logic                       m_axi_awready, 
  output logic [AXI4_DATA_W-1:0]     m_axi_wdata, 
  output logic [(AXI4_DATA_W/8)-1:0] m_axi_wstrb, 
  output logic                       m_axi_wlast, 
  output logic                       m_axi_wvalid, 
  input  logic                       m_axi_wready, 
  input  logic [AXI4_ID_W-1:0]       m_axi_bid, 
  input  logic [AXI4_RESP_W-1:0]     m_axi_bresp, 
  input  logic                       m_axi_bvalid, 
  output logic                       m_axi_bready, 
  // Read channel 
  output logic [AXI4_ID_W-1:0]       m_axi_arid, 
  output logic [AXI4_ADD_W-1:0]      m_axi_araddr, 
  output logic [AXI4_LEN_W-1:0]      m_axi_arlen, 
  output logic [AXI4_SIZE_W-1:0]     m_axi_arsize, 
  output logic [AXI4_BURST_W-1:0]    m_axi_arburst, 
  output logic                       m_axi_arvalid, 
  input  logic                       m_axi_arready, 
  input  logic [AXI4_ID_W-1:0]       m_axi_rid, 
  input  logic [AXI4_DATA_W-1:0]     m_axi_rdata, 
  input  logic [AXI4_RESP_W-1:0]     m_axi_rresp, 
  input  logic                       m_axi_rlast, 
  input  logic                       m_axi_rvalid, 
  output logic                       m_axi_rready, 

  //== Work_queue
  // Interface with a eR.Wa register
  input  logic [PE_INST_W-1:0]      r_workq,
  output logic [PE_INST_W-1:0]      r_workq_upd,
  input  logic                      r_workq_wr_en,
  input  logic [PE_INST_W-1:0]      r_workq_wdata,

  //== Ack_queue
  // Interface with a eRn__ register
  output logic [PE_INST_W-1:0]      r_ackq_upd,
  input  logic                      r_ackq_rd_en,

  // Dop stream: issue sequence of DOps
  output logic [(PE_INST_W-1):0]     dop_data,
  input  logic                       dop_rdy,
  output logic                       dop_vld,

  // Ack stream: received acknowledgment of DOp sync.
  input  logic [(PE_INST_W-1):0]     ack_data,
  output logic                       ack_rdy,
  input  logic                       ack_vld,

  // Ucore irq line
  output logic                       irq
);

// Internal signals
// ----------------------------------------------------------------------------------------------
  // Workq fifo
  logic [(PE_INST_W-1):0] workq_tdata_in, workq_tdata_out;
  logic                   workq_tlast_out;
  logic                   workq_tready_in, workq_tready_out;
  logic                   workq_tvalid_in, workq_tvalid_out;

  // Ackq fifo
  logic [(PE_INST_W-1):0] ackq_tdata_in, ackq_tdata_out;
  logic                   ackq_tlast_in;
  logic                   ackq_tready_in, ackq_tready_out;
  logic                   ackq_tvalid_in, ackq_tvalid_out;

  // DOp fifo
  logic [(PE_INST_W-1):0] dop_tdata_in;
  logic                   dop_tlast_in;
  logic                   dop_tready_in;
  logic                   dop_tvalid_in;

  // Work queue register and logic
  // ----------------------------------------------------------------------------------------------
  // Convert the eR.Wa register interface in axis
  // Custom interface translate write in axis pus event. Update value is the number of push in a full queue
  logic r_workq_updD;

  always_ff @(posedge clk)
  begin
    if (!s_rst_n) begin
      r_workq_upd <= 'h0;
    end
    else begin
      r_workq_upd <= r_workq_updD;
    end
  end

  assign r_workq_updD = (r_workq_wr_en && !workq_tready_in) ? r_workq_upd+ 1: r_workq_upd;
  assign workq_tdata_in = r_workq_wdata;
  assign workq_tvalid_in = r_workq_wr_en;

  fifo_reg # (
    .WIDTH        (PE_INST_W),
    .DEPTH        (UCORE_FIFO_DEPTH)
) fifo_workq (
    .clk     (clk          ),
    .s_rst_n (s_rst_n      ),

    .in_data (workq_tdata_in ),
    .in_vld  (workq_tvalid_in),
    .in_rdy  (workq_tready_in),

    .out_data(workq_tdata_out ),
    .out_vld (workq_tvalid_out),
    .out_rdy (workq_tready_out)
  );
  // TODO: enhance handling of tlast
  assign workq_tlast_out = 1'b0;

  // Ack queue register and logic
  // ----------------------------------------------------------------------------------------------
  // Convert the eRn__ register interface in axis
  // Custom interface translate write in axis pus event. Update value is the number of push in a full queue
  logic [PE_INST_W-1:0]      r_ackq_updD;
  logic                      r_ackq_upd_avail;
  logic                      r_ackq_upd_availD;

  always_ff @(posedge clk)
  begin
    if (!s_rst_n) begin
      r_ackq_upd       <= ACKQ_RD_ERR;
      r_ackq_upd_avail <= 1'b0;
    end
    else begin
      r_ackq_upd       <= r_ackq_updD;
      r_ackq_upd_avail <= r_ackq_upd_availD;
    end
  end

  assign r_ackq_updD       = (r_ackq_upd_avail && r_ackq_rd_en)   ? ACKQ_RD_ERR:
                             (ackq_tvalid_out && ackq_tready_out) ? ackq_tdata_out : r_ackq_upd;
  assign ackq_tready_out   = ~r_ackq_upd_avail;
  assign r_ackq_upd_availD = (r_ackq_upd_avail && r_ackq_rd_en)  ? 1'b0 :
                            (ackq_tvalid_out && ackq_tready_out) ? 1'b1 : r_ackq_upd_avail;

  // TODO add a register for timing purpose TBC
  assign irq = ackq_tvalid_out;

  fifo_reg # (
    .WIDTH        (PE_INST_W),
    .DEPTH        (UCORE_FIFO_DEPTH)
) fifo_ackq (
    .clk     (clk          ),
    .s_rst_n (s_rst_n      ),

    .in_data (ackq_tdata_in ),
    .in_vld  (ackq_tvalid_in),
    .in_rdy  (ackq_tready_in),

    .out_data(ackq_tdata_out ),
    .out_vld (ackq_tvalid_out),
    .out_rdy (ackq_tready_out)
  );
  // TODO: enhance handling of tlast
  logic ackq_tlast_out;
  assign ackq_tlast_out = 1'b0;

  // simulation AXI4_ADD_W can be different from synthesis
  // value axi_if_ucore_axi_pkg::AXI4_ADD_W
  logic [axi_if_ucore_axi_pkg::AXI4_ADD_W-1:0] m_axi_awaddr_tmp;
  logic [axi_if_ucore_axi_pkg::AXI4_ADD_W-1:0] m_axi_araddr_tmp;

  assign m_axi_awaddr = m_axi_awaddr_tmp[AXI4_ADD_W-1:0];
  assign m_axi_araddr = m_axi_araddr_tmp[AXI4_ADD_W-1:0];

  // ublaze
  // ----------------------------------------------------------------------------------------------
  ublaze_wrapper ublaze_wrapper (
    // System interface
    .ublaze_clk    (clk                ),
    .ublaze_rst    (s_rst_n            ),
   
    // axis workq
    .axis_sp0_tdata   (workq_tdata_out),
    .axis_sp0_tlast   (workq_tlast_out),
    .axis_sp0_tready  (workq_tready_out),
    .axis_sp0_tvalid  (workq_tvalid_out),

    // axis ackq
    .axis_mp0_tdata   (ackq_tdata_in),
    .axis_mp0_tlast   (ackq_tlast_in),
    .axis_mp0_tready  (ackq_tready_in),
    .axis_mp0_tvalid  (ackq_tvalid_in),

    // Master Axi -> lookup/translation memory [ucore_reg]
    // NB: internally ublaze only support axi4-lite thus the lookup/translation 
    // memory use axi4-lite
    // write path
    .axi_mp_awaddr  (m_axi_awaddr_tmp),
    .axi_mp_awvalid (m_axi_awvalid ),
    .axi_mp_awready (m_axi_awready ),
    .axi_mp_wdata   (m_axi_wdata   ),
    .axi_mp_wvalid  (m_axi_wvalid  ),
    .axi_mp_wready  (m_axi_wready  ),
    .axi_mp_awprot  (/* UNUSED */  ),
    .axi_mp_wstrb   (m_axi_wstrb   ),
    .axi_mp_wlast   (m_axi_wlast   ),
    .axi_mp_awburst (m_axi_awburst ),
    .axi_mp_awcache (/* UNUSED */  ),
    .axi_mp_awlen   (m_axi_awlen   ),
    .axi_mp_awlock  (/* UNUSED */  ),
    .axi_mp_awqos   (/* UNUSED */  ),
    .axi_mp_awsize  (m_axi_awsize  ),
    .axi_mp_bresp   (m_axi_bresp   ),
    .axi_mp_bready  (m_axi_bready  ),
    .axi_mp_bvalid  (m_axi_bvalid  ),
    .axi_mp_awregion(/*UNUSED*/    ),

    // read path
    .axi_mp_araddr  (m_axi_araddr_tmp),
    .axi_mp_arvalid (m_axi_arvalid ),
    .axi_mp_arready (m_axi_arready ),
    .axi_mp_arprot  (/* UNUSED */  ),
    .axi_mp_arburst (m_axi_arburst ),
    .axi_mp_arcache (/* UNUSED */  ),
    .axi_mp_arlen   (m_axi_arlen   ),
    .axi_mp_arlock  (/* UNUSED */  ),
    .axi_mp_arqos   (/* UNUSED */  ),
    .axi_mp_arsize  (m_axi_arsize  ),
    .axi_mp_rdata   (m_axi_rdata   ),
    .axi_mp_rresp   (m_axi_rresp   ),
    .axi_mp_rvalid  (m_axi_rvalid  ),
    .axi_mp_rready  (m_axi_rready  ),
    .axi_mp_rlast   (m_axi_rlast   ),
    .axi_mp_arregion(/*UNUSED*/    ),
  
    // axis dop
    .axis_mp1_tdata   (dop_tdata_in),
    .axis_mp1_tlast   (dop_tlast_in),
    .axis_mp1_tready  (dop_tready_in),
    .axis_mp1_tvalid  (dop_tvalid_in),

    // axis ackq
    .axis_sp1_tdata   (ack_data),
    .axis_sp1_tlast   ('0),
    .axis_sp1_tready  (ack_rdy),
    .axis_sp1_tvalid  (ack_vld),
    
    // Interrupt
    .irq_0(ack_vld)
  );

  // NB: ublaze use kind of axi4-lite over axi4 bridge (beauty of microblaze ^-^)
  //     -> No awid/arid generated mu
  // tie interface to 0
  assign m_axi_awid = '0;
  assign m_axi_arid = '0;


  // Dops fifo
  // ----------------------------------------------------------------------------------------------
  fifo_reg # (
    .WIDTH        (PE_INST_W),
    .DEPTH        (UCORE_FIFO_DEPTH)
) fifo_dop (
    .clk     (clk          ),
    .s_rst_n (s_rst_n      ),

    .in_data (dop_tdata_in ),
    .in_vld  (dop_tvalid_in),
    .in_rdy  (dop_tready_in),

    .out_data(dop_data),
    .out_vld (dop_vld),
    .out_rdy (dop_rdy)
  );

endmodule
