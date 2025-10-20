// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : This testbench only tests debug mode
// Debug mode corresponds to the control of one lane through register file
//
// ==============================================================================================

`resetall
`timescale 1ns/10ps
module tb_multi_hpu_dma;
  import axi_if_common_param_pkg::*;
  import axi_if_shell_axil_pkg::*;
  import hpu_regif_core_eth_2in3_pkg::*;
  import mhdma_pkg::*;

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int CLK_HALF_PERIOD_A = 4;
  localparam int CLK_HALF_PERIOD_B = 1;
  localparam int ARST_ACTIVATION = 17;


  localparam int HPU_NB = 2; // in this test we will try to connect two mhdma (or HPUs)

  localparam int FIFO_DEPTH = 512;

  localparam int DEFAULT_SRC_MAC_ADDR_OFS = 'h0005;
  localparam int DEFAULT_DST_MAC_ADDR_OFS = 'h0006;

// ============================================================================================== --
// clock, reset
// ============================================================================================== --
  bit clk_control;
  bit clk_mrmac;

  initial begin
    clk_control = 1'b0;
    clk_mrmac = 1'b0;
  end

  always begin
    #CLK_HALF_PERIOD_A clk_control = ~clk_control;
  end
  always begin
    #CLK_HALF_PERIOD_B clk_mrmac = ~clk_mrmac;
  end

  bit a_rst_n; // asynchronous reset
  bit s_rstn_control; // synchronous reset
  bit s_rstn_mrmac; // synchronous reset

  initial begin
    a_rst_n = 1'b0;                  // active reset
    #ARST_ACTIVATION a_rst_n = 1'b1; // disable reset
  end

  always_ff @(posedge clk_control) begin
    s_rstn_control <= a_rst_n;
  end
  always_ff @(posedge clk_mrmac) begin
    s_rstn_mrmac <= a_rst_n;
  end

// ============================================================================================== --
// End of test
// ============================================================================================== --
  bit end_of_test;

  initial begin
    wait (end_of_test);
    @(posedge clk_control) $display("%t > SUCCEED !", $time);
    $finish;
  end

// ============================================================================================== --
// Error
// ============================================================================================== --
  bit error;

  always_ff @(posedge clk_control)
    if (error) begin
      $display("%t > FAILURE !", $time);
      $finish;
    end

// ============================================================================================== --
// input / output signals
// ============================================================================================== --
  logic [AXIL_ADD_W-1:0]      s_axil_dma_awaddr_hpu_a;
  logic                       s_axil_dma_awvalid_hpu_a;
  logic                       s_axil_dma_awready_hpu_a;
  logic [AXIL_DATA_W-1:0]     s_axil_dma_wdata_hpu_a;
  logic [AXIL_DATA_BYTES-1:0] s_axil_dma_wstrb_hpu_a; /* UNUSED */
  logic                       s_axil_dma_wvalid_hpu_a;
  logic                       s_axil_dma_wready_hpu_a;
  logic [1:0]                 s_axil_dma_bresp_hpu_a;
  logic                       s_axil_dma_bvalid_hpu_a;
  logic                       s_axil_dma_bready_hpu_a;
  logic [AXIL_ADD_W-1:0]      s_axil_dma_araddr_hpu_a;
  logic                       s_axil_dma_arvalid_hpu_a;
  logic                       s_axil_dma_arready_hpu_a;
  logic [AXIL_DATA_W-1:0]     s_axil_dma_rdata_hpu_a;
  logic [1:0]                 s_axil_dma_rresp_hpu_a;
  logic                       s_axil_dma_rvalid_hpu_a;
  logic                       s_axil_dma_rready_hpu_a;

  logic [AXIL_ADD_W-1:0]      s_axil_dma_awaddr_hpu_b;
  logic                       s_axil_dma_awvalid_hpu_b;
  logic                       s_axil_dma_awready_hpu_b;
  logic [AXIL_DATA_W-1:0]     s_axil_dma_wdata_hpu_b;
  logic [AXIL_DATA_BYTES-1:0] s_axil_dma_wstrb_hpu_b; /* UNUSED */
  logic                       s_axil_dma_wvalid_hpu_b;
  logic                       s_axil_dma_wready_hpu_b;
  logic [1:0]                 s_axil_dma_bresp_hpu_b;
  logic                       s_axil_dma_bvalid_hpu_b;
  logic                       s_axil_dma_bready_hpu_b;
  logic [AXIL_ADD_W-1:0]      s_axil_dma_araddr_hpu_b;
  logic                       s_axil_dma_arvalid_hpu_b;
  logic                       s_axil_dma_arready_hpu_b;
  logic [AXIL_DATA_W-1:0]     s_axil_dma_rdata_hpu_b;
  logic [1:0]                 s_axil_dma_rresp_hpu_b;
  logic                       s_axil_dma_rvalid_hpu_b;
  logic                       s_axil_dma_rready_hpu_b;
  // QSFP system interface ----------------------------------------------------
  // == TX
  logic [HPU_NB-1:0][QSFP_LANE_NB-1:0][MRMAC_AXIS_W-1:0 ] qsfp_tx_tdata;
  logic [HPU_NB-1:0][QSFP_LANE_NB-1:0][MRMAC_TKEEP_W-1:0] qsfp_tx_tkeep_user;
  logic [HPU_NB-1:0][QSFP_LANE_NB-1:0]                    qsfp_tx_tlast;
  logic [HPU_NB-1:0][QSFP_LANE_NB-1:0]                    qsfp_tx_tvalid;
  logic [HPU_NB-1:0][QSFP_LANE_NB-1:0]                    qsfp_tx_tready;
  // == RX
  logic [HPU_NB-1:0][QSFP_LANE_NB-1:0][MRMAC_AXIS_W-1:0 ] qsfp_rx_tdata;
  logic [HPU_NB-1:0][QSFP_LANE_NB-1:0][MRMAC_TKEEP_W-1:0] qsfp_rx_tkeep_user;
  logic [HPU_NB-1:0][QSFP_LANE_NB-1:0]                    qsfp_rx_tlast;
  logic [HPU_NB-1:0][QSFP_LANE_NB-1:0]                    qsfp_rx_tvalid;

  // ============================================================================================== --
  // Design under test instance
  // ============================================================================================== --
  // gt configuration signals
  logic [HPU_NB-1:0][7:0]              gt_line_rate;
  logic [HPU_NB-1:0][2:0]              gt_loopback;
  logic [HPU_NB-1:0][QSFP_LANE_NB-1:0] gt_reset_rx_datapath;
  logic [HPU_NB-1:0][QSFP_LANE_NB-1:0] gt_reset_tx_datapath;
  logic [HPU_NB-1:0][QSFP_LANE_NB-1:0] gt_reset_all;
  logic [HPU_NB-1:0][QSFP_LANE_NB-1:0] gt_rx_reset_done;
  logic [HPU_NB-1:0][QSFP_LANE_NB-1:0] gt_tx_reset_done;

  // [section] line parameter -------------------------------------------------
  logic [31:0] line_parameter;
  logic        debug_flag;
  logic [2:0]  line_loopback;
  logic [7:0]  line_rate;
  logic [1:0]  line_select;

  assign line_parameter[1:0]   = line_select;
  assign line_parameter[4:2]   = line_loopback;
  assign line_parameter[12:5]  = line_rate;
  assign line_parameter[27:13] = 'h0;
  assign line_parameter[31]    = debug_flag;

  // [section] line debug -----------------------------------------------------
  logic [31:0] line_debug;
  logic        reset_registers;
  logic        tx_loop;
  logic        rx_to_tx;

  assign line_debug[28:0] = 'h0;
  assign line_debug[29]   = rx_to_tx;
  assign line_debug[30]   = tx_loop;
  assign line_debug[31]   = reset_registers;

  // [section] reset ----------------------------------------------------------
  logic [31:0] reset_parameter;
  logic [QSFP_LANE_NB-1:0] rst_rx_datapath;
  logic [QSFP_LANE_NB-1:0] rst_tx_datapath;
  logic [QSFP_LANE_NB-1:0] rst_all;

  assign reset_parameter = {20'h0, rst_rx_datapath, rst_tx_datapath, rst_all};

  // monitoring of reset done
  logic [HPU_NB-1:0][31:0] reset_monitor;

  // HPU A ----------------------------------------------------------------------------------------
  multi_hpu_dma #(
    .FIFO_DEPTH(FIFO_DEPTH)
  ) hpu_a (
    .clk_eth_cfg   (clk_control    ),
    .resetn_eth_cfg(s_rstn_control ),

    .clk_eth_mrmac   (clk_mrmac    ),
    .resetn_eth_mrmac(s_rstn_mrmac ),

    .s_axil_dma_awaddr (s_axil_dma_awaddr_hpu_a ),
    .s_axil_dma_awvalid(s_axil_dma_awvalid_hpu_a),
    .s_axil_dma_awready(s_axil_dma_awready_hpu_a),
    .s_axil_dma_wdata  (s_axil_dma_wdata_hpu_a  ),
    .s_axil_dma_wstrb  (s_axil_dma_wstrb_hpu_a  ),
    .s_axil_dma_wvalid (s_axil_dma_wvalid_hpu_a ),
    .s_axil_dma_wready (s_axil_dma_wready_hpu_a ),
    .s_axil_dma_bresp  (s_axil_dma_bresp_hpu_a  ),
    .s_axil_dma_bvalid (s_axil_dma_bvalid_hpu_a ),
    .s_axil_dma_bready (s_axil_dma_bready_hpu_a ),
    .s_axil_dma_araddr (s_axil_dma_araddr_hpu_a ),
    .s_axil_dma_arvalid(s_axil_dma_arvalid_hpu_a),
    .s_axil_dma_arready(s_axil_dma_arready_hpu_a),
    .s_axil_dma_rdata  (s_axil_dma_rdata_hpu_a  ),
    .s_axil_dma_rresp  (s_axil_dma_rresp_hpu_a  ),
    .s_axil_dma_rvalid (s_axil_dma_rvalid_hpu_a ),
    .s_axil_dma_rready (s_axil_dma_rready_hpu_a ),

    .qsfp_tx_tdata     (qsfp_tx_tdata[0]     ),
    .qsfp_tx_tkeep_user(qsfp_tx_tkeep_user[0]),
    .qsfp_tx_tlast     (qsfp_tx_tlast[0]     ),
    .qsfp_tx_tvalid    (qsfp_tx_tvalid[0]    ),
    .qsfp_tx_tready    (qsfp_tx_tready[0]    ),

    .qsfp_rx_tdata     (qsfp_rx_tdata[0]     ),
    .qsfp_rx_tkeep_user(qsfp_rx_tkeep_user[0]),
    .qsfp_rx_tlast     (qsfp_rx_tlast[0]     ),
    .qsfp_rx_tvalid    (qsfp_rx_tvalid[0]    ),

    .gt_line_rate        (gt_line_rate[0]        ),
    .gt_loopback         (gt_loopback[0]         ),
    .gt_reset_rx_datapath(gt_reset_rx_datapath[0]),
    .gt_reset_tx_datapath(gt_reset_tx_datapath[0]),
    .gt_reset_all        (gt_reset_all[0]        ),
    .gt_rx_reset_done    (gt_rx_reset_done[0]    ),
    .gt_tx_reset_done    (gt_tx_reset_done[0]    )
);

  // HPU B ----------------------------------------------------------------------------------------
  multi_hpu_dma #(
    .FIFO_DEPTH(FIFO_DEPTH)
  ) hpu_b (
    .clk_eth_cfg   (clk_control    ),
    .resetn_eth_cfg(s_rstn_control ),

    .clk_eth_mrmac   (clk_mrmac    ),
    .resetn_eth_mrmac(s_rstn_mrmac ),

    .s_axil_dma_awaddr (s_axil_dma_awaddr_hpu_b ),
    .s_axil_dma_awvalid(s_axil_dma_awvalid_hpu_b),
    .s_axil_dma_awready(s_axil_dma_awready_hpu_b),
    .s_axil_dma_wdata  (s_axil_dma_wdata_hpu_b  ),
    .s_axil_dma_wstrb  (s_axil_dma_wstrb_hpu_b  ),
    .s_axil_dma_wvalid (s_axil_dma_wvalid_hpu_b ),
    .s_axil_dma_wready (s_axil_dma_wready_hpu_b ),
    .s_axil_dma_bresp  (s_axil_dma_bresp_hpu_b  ),
    .s_axil_dma_bvalid (s_axil_dma_bvalid_hpu_b ),
    .s_axil_dma_bready (s_axil_dma_bready_hpu_b ),
    .s_axil_dma_araddr (s_axil_dma_araddr_hpu_b ),
    .s_axil_dma_arvalid(s_axil_dma_arvalid_hpu_b),
    .s_axil_dma_arready(s_axil_dma_arready_hpu_b),
    .s_axil_dma_rdata  (s_axil_dma_rdata_hpu_b  ),
    .s_axil_dma_rresp  (s_axil_dma_rresp_hpu_b  ),
    .s_axil_dma_rvalid (s_axil_dma_rvalid_hpu_b ),
    .s_axil_dma_rready (s_axil_dma_rready_hpu_b ),

    .qsfp_tx_tdata     (qsfp_tx_tdata[1]     ),
    .qsfp_tx_tkeep_user(qsfp_tx_tkeep_user[1]),
    .qsfp_tx_tlast     (qsfp_tx_tlast[1]     ),
    .qsfp_tx_tvalid    (qsfp_tx_tvalid[1]    ),
    .qsfp_tx_tready    (qsfp_tx_tready[1]    ),

    .qsfp_rx_tdata     (qsfp_rx_tdata[1]     ),
    .qsfp_rx_tkeep_user(qsfp_rx_tkeep_user[1]),
    .qsfp_rx_tlast     (qsfp_rx_tlast[1]     ),
    .qsfp_rx_tvalid    (qsfp_rx_tvalid[1]    ),

    .gt_line_rate        (gt_line_rate[1]        ),
    .gt_loopback         (gt_loopback[1]         ),
    .gt_reset_rx_datapath(gt_reset_rx_datapath[1]),
    .gt_reset_tx_datapath(gt_reset_tx_datapath[1]),
    .gt_reset_all        (gt_reset_all[1]        ),
    .gt_rx_reset_done    (gt_rx_reset_done[1]    ),
    .gt_tx_reset_done    (gt_tx_reset_done[1]    )
);

// ============================================================================================== --
// Scenario
// ============================================================================================== --
  maxil_if #(
  .AXIL_DATA_W(AXIL_DATA_W),
  .AXIL_ADD_W  (AXIL_ADD_W)
  ) maxil_drv_if_hpu_a ( .clk(clk_control), .rst_n(s_rstn_control));

  // Connect interface on testbench signals
  assign s_axil_dma_awaddr_hpu_a  = maxil_drv_if_hpu_a.awaddr;
  assign s_axil_dma_awvalid_hpu_a = maxil_drv_if_hpu_a.awvalid;
  assign s_axil_dma_wdata_hpu_a   = maxil_drv_if_hpu_a.wdata;
  assign s_axil_dma_wstrb_hpu_a   = maxil_drv_if_hpu_a.wstrb;
  assign s_axil_dma_wvalid_hpu_a  = maxil_drv_if_hpu_a.wvalid;
  assign s_axil_dma_bready_hpu_a  = maxil_drv_if_hpu_a.bready;
  assign s_axil_dma_araddr_hpu_a  = maxil_drv_if_hpu_a.araddr;
  assign s_axil_dma_arvalid_hpu_a = maxil_drv_if_hpu_a.arvalid;
  assign s_axil_dma_rready_hpu_a  = maxil_drv_if_hpu_a.rready;

  assign maxil_drv_if_hpu_a.awready = s_axil_dma_awready_hpu_a;
  assign maxil_drv_if_hpu_a.wready  = s_axil_dma_wready_hpu_a;
  assign maxil_drv_if_hpu_a.bresp   = s_axil_dma_bresp_hpu_a;
  assign maxil_drv_if_hpu_a.bvalid  = s_axil_dma_bvalid_hpu_a;
  assign maxil_drv_if_hpu_a.arready = s_axil_dma_arready_hpu_a;
  assign maxil_drv_if_hpu_a.rdata   = s_axil_dma_rdata_hpu_a;
  assign maxil_drv_if_hpu_a.rresp   = s_axil_dma_rresp_hpu_a;
  assign maxil_drv_if_hpu_a.rvalid  = s_axil_dma_rvalid_hpu_a;


  maxil_if #(
  .AXIL_DATA_W(AXIL_DATA_W),
  .AXIL_ADD_W  (AXIL_ADD_W)
  ) maxil_drv_if_hpu_b ( .clk(clk_control), .rst_n(s_rstn_control));

  // Connect interface on testbench signals
  assign s_axil_dma_awaddr_hpu_b  = maxil_drv_if_hpu_b.awaddr;
  assign s_axil_dma_awvalid_hpu_b = maxil_drv_if_hpu_b.awvalid;
  assign s_axil_dma_wdata_hpu_b   = maxil_drv_if_hpu_b.wdata;
  assign s_axil_dma_wstrb_hpu_b   = maxil_drv_if_hpu_b.wstrb;
  assign s_axil_dma_wvalid_hpu_b  = maxil_drv_if_hpu_b.wvalid;
  assign s_axil_dma_bready_hpu_b  = maxil_drv_if_hpu_b.bready;
  assign s_axil_dma_araddr_hpu_b  = maxil_drv_if_hpu_b.araddr;
  assign s_axil_dma_arvalid_hpu_b = maxil_drv_if_hpu_b.arvalid;
  assign s_axil_dma_rready_hpu_b  = maxil_drv_if_hpu_b.rready;

  assign maxil_drv_if_hpu_b.awready = s_axil_dma_awready_hpu_b;
  assign maxil_drv_if_hpu_b.wready  = s_axil_dma_wready_hpu_b;
  assign maxil_drv_if_hpu_b.bresp   = s_axil_dma_bresp_hpu_b;
  assign maxil_drv_if_hpu_b.bvalid  = s_axil_dma_bvalid_hpu_b;
  assign maxil_drv_if_hpu_b.arready = s_axil_dma_arready_hpu_b;
  assign maxil_drv_if_hpu_b.rdata   = s_axil_dma_rdata_hpu_b;
  assign maxil_drv_if_hpu_b.rresp   = s_axil_dma_rresp_hpu_b;
  assign maxil_drv_if_hpu_b.rvalid  = s_axil_dma_rvalid_hpu_b;

  initial begin
    maxil_drv_if_hpu_a.init();
    maxil_drv_if_hpu_b.init();

    reset_registers = 'h0;
    tx_loop         = 'h0;
    rx_to_tx        = 'h0;
    repeat(20) @(posedge clk_control);

    $display("A - Initial register check and definition");
    init_registers();

    write_mac_addresses();

    $display("%t > INFO: End simulation",$time);
    repeat(20) @(posedge clk_control);
    end_of_test = 1'b1;
  end

// ============================================================================================== --
// Tasks
// ============================================================================================== --
  logic [31:0] rdata;

  task automatic init_registers;
    begin
    // (1) Reading system REGISTERS ---------------------------------------------------------------
      maxil_drv_if_hpu_a.read_trans(SYSTEM_LINE_OFS, rdata);
      assert (rdata == 'h0) else begin
        $display("%t > ERROR:register SYSTEM_LINE_OFS not correctly read %h",$time, rdata);
        error = 1'b1;
      end

      // (2) ASSIGN REGISTERS & CHECK -------------------------------------------------------------
    line_rate     = 8'hAB;  // random, no idea what it should be
    line_loopback = 3'b100; // 3 near end pcs loopback
    line_select   = 2'b10;  // 2nd line selected
    debug_flag    = 1'b0;
    @(posedge clk_control);

    maxil_drv_if_hpu_a.write_trans(SYSTEM_LINE_OFS, line_parameter);
    maxil_drv_if_hpu_b.write_trans(SYSTEM_LINE_OFS, line_parameter);

    rst_rx_datapath = 4'b0100;
    rst_tx_datapath = 4'b1011;
    rst_all         = 4'b0101;
    @(posedge clk_control);

    maxil_drv_if_hpu_a.write_trans(RESET_DATAPATH_OFS, reset_parameter);
    maxil_drv_if_hpu_b.write_trans(RESET_DATAPATH_OFS, reset_parameter);

    assert ((gt_line_rate[0] == line_rate) && (gt_line_rate[1] == line_rate)) else begin
      $display("[ERROR] line_rate has unexpected value %x %x %x",gt_line_rate[0], gt_line_rate[1], line_rate);
      error = 1;
    end
    assert ((gt_loopback[0] ==line_loopback) && (gt_loopback[1] == line_loopback)) else begin
      $display("[ERROR] gt_loopback has unexpected value");
      error = 1;
    end
    assert ((hpu_a.line_sel == line_select) &&  (hpu_b.line_sel == line_select)) else begin
      $display("[ERROR] line_sel has unexpected value");
      error = 1;
    end

    for (int i = 0; i<2; i++) begin
      assert ((gt_reset_rx_datapath[i] == rst_rx_datapath) && (gt_reset_tx_datapath[i] == rst_tx_datapath) && (gt_reset_all[i] == rst_all)) else begin
        $display("%t >    ERROR: reset configuration has not been applied correctly",$time);
        error = 1'b1;
      end
    end

    // read reset register ----------------------------------------------------
    // fake stimulation
    for (int i = 0; i<2; i++) begin
      gt_rx_reset_done[i]= 4'b1111;
      gt_tx_reset_done[i]= 4'b1111;
    end
    @(posedge clk_control);

    maxil_drv_if_hpu_a.read_trans(RESET_MONITOR_OFS, reset_monitor[0]);
    maxil_drv_if_hpu_b.read_trans(RESET_MONITOR_OFS, reset_monitor[1]);

    assert ((reset_monitor[3:0] == gt_tx_reset_done) && (reset_monitor[7:4] == gt_rx_reset_done)) begin
      $display("%t >    ERROR: reset monitor has not been read correctly",$time);
      error = 1'b1;
    end

    // (4) Setting up credible values -------------------------------------------------------------
    // no loopback, no reset, not in debug lane0 selected
    line_rate     = 8'h0;
    line_loopback = 3'b000;
    line_select   = 2'b00;
    debug_flag    = 1'b0;
    rst_rx_datapath = 4'b0000;
    rst_tx_datapath = 4'b0000;
    rst_all         = 4'b0000;
    @(posedge clk_control);

    $display("%t > INFO: Configuration successful\n",$time);
    end
  endtask

  // Effective MAC address without OUI
  logic [23:0] mac_addr;
  logic [3:0]  hpu_id;
  logic        hpu_current;

  logic [3:0] random_hpu_a;
  logic [3:0] random_hpu_b;

  logic [31:0] register_mac_addr_a;
  logic [31:0] register_mac_addr_b;

  task automatic write_mac_addresses();
    begin
      random_hpu_a = $urandom_range(7, 0);

      // let's avoid saying that we are the same HPU
      do begin
        random_hpu_b = $urandom_range(7, 0);
      end while (random_hpu_b == random_hpu_a);

      $display("\n[INFO] For this run....");
      $display("[INFO] HPU_A:id=%0d", random_hpu_a);
      $display("[INFO] HPU_B:id=%0d \n", random_hpu_b);

      for (int i = 0 ; i < 8 ; i++ ) begin
        mac_addr = $urandom();
        hpu_id = i;

        if(i == random_hpu_a) begin
          register_mac_addr_a = {1'b1, 3'b000, hpu_id, mac_addr};
        end else begin
          register_mac_addr_a = {1'b0, 3'b000, hpu_id, mac_addr};
        end

        if(i == random_hpu_b) begin
          register_mac_addr_b = {1'b1, 3'b000, hpu_id, mac_addr};
        end else begin
          register_mac_addr_b = {1'b0, 3'b000, hpu_id, mac_addr};
        end

        $display("[INFO] HPU_ID=%0d :: MAC=%0x", i, mac_addr);
        maxil_drv_if_hpu_a.write_trans(HPU_ID_ZERO_OFS+(4*i), register_mac_addr_a);
        maxil_drv_if_hpu_b.write_trans(HPU_ID_ZERO_OFS+(4*i), register_mac_addr_b);
      end

    end
  endtask

endmodule

