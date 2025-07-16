# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
# Contains procedure to generate block designs that handle
# the ethernet wrappers includes :
# * XXV ethernet IP(MAC+PCS/PMA 64bit)
# ==============================================================================================

################################################################
# create_hier_cell_eth_wrapper
################################################################
# Hierarchical cell: eth_wrapper
proc create_hier_cell_eth_wrapper { parentCell nameHier } {
  set parentObj [check_parent_hier $parentCell $nameHier]
  if { $parentObj == "" } { return }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj
  set parent_is_root [expr [string match "/" $parentObj] ? 1 : 0]

  # Create cell and set as current instance
  set hier_obj [create_bd_cell -type hier $nameHier]
  current_bd_instance $hier_obj

  ####################################
  # get global var
  ####################################

  ####################################
  # Create pins
  ####################################
  # eth axi-lite
  set axil_eth       [ create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 axil_eth ]
  set axil_eth_clk   [ create_bd_pin -dir I -type CLK axil_eth_clk ]
  set axil_eth_arstn [ create_bd_pin -dir I -type rst axil_eth_arstn ]

  # eth axi-stream
  set axis_m_eth [ create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:axis_rtl:1.0 axis_m_eth ]
  set axis_s_eth [ create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:axis_rtl:1.0 axis_s_eth ]

  # reference clock for GTM
  set qsfp0_clk_p [ create_bd_pin -dir I -type CLK qsfp0_clk_p ]

  set tx_ref_clk [ create_bd_pin -dir O -type CLK tx_ref_clk ]
  set rx_ref_clk [ create_bd_pin -dir O -type CLK rx_ref_clk ]

  set pl_ref_clk [ create_bd_pin -dir I -type CLK pl_ref_clk ]
  set pl0_resetn [ create_bd_pin -dir I -type rst pl0_resetn ]

  # qsfp0_4x_grx_p
  # qsfp0_4x_gtx_p

  ####################################
  # Clocking
  ####################################
  # set_property -dict [ list \
  #  CONFIG.FREQ_HZ {156250000} \
  #  ] $qsfp0_clk_p

  ####################################
  # Create XXV IP
  ####################################
  set xxv_ethernet [ create_bd_cell -type ip -vlnv xilinx.com:ip:xxv_ethernet:5.0 xxv_ethernet ]

  # we want an interface with a MAC and PCS/PMA in 64bit
  # wanted rate is 10Gbps. this implies that refclock freq is 156250000
  # our trancievers are GTM

  set_property -dict [list \
    CONFIG.CORE {Ethernet MAC+PCS/PMA 64-bit} \
    CONFIG.LINE_RATE {10} \
    CONFIG.GT_TYPE {GTM} \
    CONFIG.BASE_R_KR {BASE-R} \
  ] $xxv_ethernet

  create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 xlconstant_0
  set_property CONFIG.CONST_VAL {0} [get_bd_cells xlconstant_0]

  ####################################
  # Create GT
  ####################################
  set gt_0 [create_bd_cell -type ip -vlnv xilinx.com:ip:gtwiz_versal:1.0 gt_0]

  set_property -dict [list \
    CONFIG.GT_TYPE {GTM} \
    CONFIG.INTF0_NO_OF_LANES {1} \
    CONFIG.QUAD0_PROT0_LANES {1} \
    CONFIG.QUAD0_PROT0_RX1_EN {false} \
    CONFIG.QUAD0_PROT0_RX2_EN {false} \
    CONFIG.QUAD0_PROT0_RX3_EN {false} \
    CONFIG.QUAD0_PROT0_TX1_EN {false} \
    CONFIG.QUAD0_PROT0_TX2_EN {false} \
    CONFIG.QUAD0_PROT0_TX3_EN {false} \
    CONFIG.QUAD0_HSCLK0_LCPLL_LOCK_EN {true} \
  ] $gt_0

  # we could use rcpll and lcpll: this is not clear what to be prefered

  create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:2.0 not_pl_rst
  # create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:2.0 not_tx_rst

  set_property -dict [list \
    CONFIG.C_OPERATION {not} \
    CONFIG.C_SIZE {1} \
  ] [get_bd_cells not_pl_rst]

  # set_property -dict [list \
  #   CONFIG.C_OPERATION {not} \
  #   CONFIG.C_SIZE {1} \
  # ] [get_bd_cells not_tx_rst]


  ####################################
  # Connection
  ####################################
  # AXI-lite interface
  connect_bd_intf_net -boundary_type upper [get_bd_intf_pins axil_eth] [get_bd_intf_pins xxv_ethernet/s_axi_0]
  connect_bd_net [get_bd_pins axil_eth_clk] [get_bd_pins xxv_ethernet/s_axi_aclk_0]
  connect_bd_net [get_bd_pins axil_eth_arstn] [get_bd_pins xxv_ethernet/s_axi_aresetn_0]

  # AXI-stream interface
  connect_bd_intf_net -intf_net axis_txd [get_bd_intf_pins axis_s_eth] [get_bd_intf_pins xxv_ethernet/axis_tx_0]
  connect_bd_intf_net -intf_net axis_rxd [get_bd_intf_pins axis_m_eth] [get_bd_intf_pins xxv_ethernet/axis_rx_0]

  # MAC TX control interface: tied to 0 for basic usage
  connect_bd_net [get_bd_pins xlconstant_0/dout] [get_bd_pins xxv_ethernet/ctl_tx_send_idle_0]
  connect_bd_net [get_bd_pins xlconstant_0/dout] [get_bd_pins xxv_ethernet/ctl_tx_send_lfi_0]
  connect_bd_net [get_bd_pins xlconstant_0/dout] [get_bd_pins xxv_ethernet/ctl_tx_send_rfi_0]

  # Receive core clock for the XXV Ethernet subsystem - in xxv we use internal FIFO
  #  we need to connect this pin to clock out path
  connect_bd_net [get_bd_pins xxv_ethernet/rx_core_clk_0] [get_bd_pins xxv_ethernet/rx_clk_out_0]

  # GT user clock signals
  connect_bd_net [get_bd_pins qsfp0_clk_p] [get_bd_pins xxv_ethernet/gtm_txusrclk2_0]
  connect_bd_net [get_bd_pins qsfp0_clk_p] [get_bd_pins xxv_ethernet/gtm_rxusrclk2_0]

  connect_bd_net [get_bd_pins qsfp0_clk_p] [get_bd_pins xxv_ethernet/rxoutclk_out_0]
  connect_bd_net [get_bd_pins qsfp0_clk_p] [get_bd_pins xxv_ethernet/txoutclk_out_0]

  # reset
  # lcpll is shared between transmitter and reciever datapath: this can be used for both rx and tx
  connect_bd_net [get_bd_pins gt_0/QUAD0_hsclk0_lcplllock] [get_bd_pins xxv_ethernet/tx_locked_0]
  connect_bd_net [get_bd_pins gt_0/QUAD0_hsclk0_lcplllock] [get_bd_pins xxv_ethernet/rx_locked_0]
  # due to inverse polarity we need to connect
  connect_bd_net [get_bd_pins pl0_resetn] [get_bd_pins not_pl_rst/Op1]
  connect_bd_net [get_bd_pins not_pl_rst/Res] [get_bd_pins xxv_ethernet/tx_reset_0]
  connect_bd_net [get_bd_pins not_pl_rst/Res] [get_bd_pins xxv_ethernet/rx_reset_0]
  connect_bd_net [get_bd_pins pl_ref_clk] [get_bd_pins xxv_ethernet/gtwiz_reset_clk_freerun_in_0]

  # control
  connect_bd_net [get_bd_pins gt_0/gtpowergood] [get_bd_pins xxv_ethernet/gtpowergood_in_0]

  # Data
  connect_bd_intf_net [get_bd_intf_pins gt_0/INTF0_TX0_GT_IP_Interface] [get_bd_intf_pins xxv_ethernet/gtm_tx_serdes_interface_0]
  connect_bd_intf_net [get_bd_intf_pins gt_0/INTF0_RX0_GT_IP_Interface] [get_bd_intf_pins xxv_ethernet/gtm_rx_serdes_interface_0]

  # clocks
  connect_bd_net [get_bd_pins tx_ref_clk] [get_bd_pins xxv_ethernet/tx_clk_out_0]
  connect_bd_net [get_bd_pins rx_ref_clk] [get_bd_pins xxv_ethernet/rx_clk_out_0]

  # Unconnected
  #  * rx_serdes_reset_0 : TODO, not clear if it needs to be tied to something yet
  #  * txoutclk_out_0: TODO is it needed ?  depends on reset sequence from trancievers, tbd with gtwiz
  #  * tx_unfout_0: TODO is it needed ?
  #  * user_reg0_0: TODO is it needed ?
  #  * gtwiz_txprecursor_0 * gtwiz_txpostcursor_0 * gtwiz_txmaincursor_0: Optional, signal integrity
  #  * gtwiz_loopback_0: TODO is it needed ?
  #  * pm_tick_0: Optional performance monitoring tick
  #  * tx_preamblein_0: Optional for custom preamble
  #  * rx_preambleout_0: Optional for custom preamble
  #  * stat_tx_0: no statistics for now
  #  * stat_rx_0: no statistics for now
  #  * stat_rx_status_0: no statistics for now
  #  * rx_resetdone_out_0: Optional
  #

  ####################################
  # Restore instance
  ####################################
  # Restore current instance
  current_bd_instance $oldCurInst
}
