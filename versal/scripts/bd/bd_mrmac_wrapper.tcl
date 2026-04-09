# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
# Contains procedure to generate block designs that handle MRMAC wrapper.
# Part of it is derived from the example design and adapted to our needs.
#
# We needed an MRMAC MAC + PCS driving GTM for QSFPs.
#
# ==============================================================================================

###############################################################################
# The majority of this code has been generated using example design.
# some parts have been modified to fit our needs and naming convention.
###############################################################################

# Hierarchical cell: mrmac_0_gt_wrapper
proc create_hier_cell_mrmac_0_gt_wrapper { parentCell nameHier } {
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
  # Create pins
  ####################################
  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:gt_tx_interface_rtl:1.0 TX0_GT_IP_Interface
  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:gt_tx_interface_rtl:1.0 TX1_GT_IP_Interface
  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:gt_tx_interface_rtl:1.0 TX2_GT_IP_Interface
  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:gt_tx_interface_rtl:1.0 TX3_GT_IP_Interface
  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:gt_rx_interface_rtl:1.0 RX0_GT_IP_Interface
  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:gt_rx_interface_rtl:1.0 RX1_GT_IP_Interface
  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:gt_rx_interface_rtl:1.0 RX2_GT_IP_Interface
  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:gt_rx_interface_rtl:1.0 RX3_GT_IP_Interface
  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:apb_rtl:1.0 APB3_INTF
  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:gt_rtl:1.0 GT_Serial
  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 CLK_IN_D

  create_bd_pin -dir I -from 7 -to 0 ch0_txrate
  create_bd_pin -dir I -type gt_usrclk ch0_txusrclk
  create_bd_pin -dir I -from 7 -to 0 ch1_txrate
  create_bd_pin -dir I -type gt_usrclk ch1_txusrclk
  create_bd_pin -dir I -from 7 -to 0 ch2_txrate
  create_bd_pin -dir I -type gt_usrclk ch2_txusrclk
  create_bd_pin -dir I -from 7 -to 0 ch3_txrate
  create_bd_pin -dir I -type gt_usrclk ch3_txusrclk
  create_bd_pin -dir I -from 7 -to 0 ch0_rxrate
  create_bd_pin -dir I -type gt_usrclk ch0_rxusrclk
  create_bd_pin -dir I -from 7 -to 0 ch1_rxrate
  create_bd_pin -dir I -type gt_usrclk ch1_rxusrclk
  create_bd_pin -dir I -from 7 -to 0 ch2_rxrate
  create_bd_pin -dir I -type gt_usrclk ch2_rxusrclk
  create_bd_pin -dir I -from 7 -to 0 ch3_rxrate
  create_bd_pin -dir I -type gt_usrclk ch3_rxusrclk
  create_bd_pin -dir I -from 2 -to 0 ch0_loopback
  create_bd_pin -dir I -from 2 -to 0 ch1_loopback
  create_bd_pin -dir I -from 2 -to 0 ch2_loopback
  create_bd_pin -dir I -from 2 -to 0 ch3_loopback
  create_bd_pin -dir I -type clk apb3clk_quad
  create_bd_pin -dir I -type rst apb3presetn
  create_bd_pin -dir O gtpowergood
  create_bd_pin -dir I -from 3 -to 0 gt_rxp_in_0
  create_bd_pin -dir I -from 3 -to 0 gt_rxn_in_0
  create_bd_pin -dir O -from 3 -to 0 gt_txp_out_0
  create_bd_pin -dir O -from 3 -to 0 gt_txn_out_0
  create_bd_pin -dir I -from 0 -to 0 MBUFG_GT_CLR
  create_bd_pin -dir I -from 0 -to 0 MBUFG_GT_CLRB_LEAF
  create_bd_pin -dir O -from 0 -to 0 -type gt_usrclk ch0_tx_usr_clk
  create_bd_pin -dir O -from 0 -to 0 -type gt_usrclk ch0_tx_usr_clk2
  create_bd_pin -dir I -from 0 -to 0 MBUFG_GT_CLR1
  create_bd_pin -dir I -from 0 -to 0 MBUFG_GT_CLRB_LEAF1
  create_bd_pin -dir O -from 0 -to 0 -type gt_usrclk ch0_rx_usr_clk
  create_bd_pin -dir O -from 0 -to 0 -type gt_usrclk ch0_rx_usr_clk2
  create_bd_pin -dir I -from 0 -to 0 MBUFG_GT_CLR2
  create_bd_pin -dir I -from 0 -to 0 MBUFG_GT_CLRB_LEAF2
  create_bd_pin -dir O -from 0 -to 0 -type gt_usrclk ch1_rx_usr_clk
  create_bd_pin -dir O -from 0 -to 0 -type gt_usrclk ch1_rx_usr_clk2
  create_bd_pin -dir I -from 0 -to 0 MBUFG_GT_CLR3
  create_bd_pin -dir I -from 0 -to 0 MBUFG_GT_CLRB_LEAF3
  create_bd_pin -dir O -from 0 -to 0 -type gt_usrclk ch2_rx_usr_clk
  create_bd_pin -dir O -from 0 -to 0 -type gt_usrclk ch2_rx_usr_clk2
  create_bd_pin -dir I -from 0 -to 0 MBUFG_GT_CLR4
  create_bd_pin -dir I -from 0 -to 0 MBUFG_GT_CLRB_LEAF4
  create_bd_pin -dir O -from 0 -to 0 -type gt_usrclk ch3_rx_usr_clk
  create_bd_pin -dir O -from 0 -to 0 -type gt_usrclk ch3_rx_usr_clk2

  ####################################
  # Create instances
  ####################################

  # Create instance: gt_quad_base, and set properties
  set gt_quad_base [ create_bd_cell -type ip -vlnv xilinx.com:ip:gt_quad_base:1.1 gt_quad_base ]

  set_property -dict [list CONFIG.GT_TYPE.VALUE_MODE MANUAL] $gt_quad_base
  set_property CONFIG.GT_TYPE {GTM} $gt_quad_base

  # forces all lanes (and both HSCLK of GT Quad) to use same GT_REFCLK0
  set_property -dict [list \
      CONFIG.PROT0_NO_OF_LANES.VALUE_MODE MANUAL \
      CONFIG.PROT1_ENABLE.VALUE_MODE MANUAL \
      CONFIG.RX3_LANE_SEL.VALUE_MODE MANUAL \
      CONFIG.TX3_LANE_SEL.VALUE_MODE MANUAL \
      CONFIG.RX2_LANE_SEL.VALUE_MODE MANUAL \
      CONFIG.TX2_LANE_SEL.VALUE_MODE MANUAL] $gt_quad_base
  set_property -dict [list \
      CONFIG.PROT0_NO_OF_LANES {4} \
      CONFIG.PROT1_ENABLE {false} \
      CONFIG.RX3_LANE_SEL {PROT0} \
      CONFIG.TX3_LANE_SEL {PROT0} \
      CONFIG.RX2_LANE_SEL {PROT0} \
      CONFIG.TX2_LANE_SEL {PROT0} \
  ] $gt_quad_base

  # This property forces the frequency to be updated from the clock wizard defined earlier
  # The clock is not exactly what is expected (200Mhz) and without this argument mismatch will be found and an error will be triggered
  set_property -dict [list \
    CONFIG.APB3_CLK_FREQUENCY.VALUE_MODE {auto} \
  ] $gt_quad_base

  # Create instance: mbufg_gt_0, and set properties
  set mbufg_gt_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:util_ds_buf:2.2 mbufg_gt_0 ]
  set_property -dict [list \
    CONFIG.C_BUFG_GT_SYNC {true} \
    CONFIG.C_BUF_TYPE {MBUFG_GT} \
  ] $mbufg_gt_0

  # Create instance: mbufg_gt_1, and set properties
  set mbufg_gt_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:util_ds_buf:2.2 mbufg_gt_1 ]
  set_property -dict [list \
    CONFIG.C_BUFG_GT_SYNC {true} \
    CONFIG.C_BUF_TYPE {MBUFG_GT} \
  ] $mbufg_gt_1

  # Create instance: mbufg_gt_1_1, and set properties
  set mbufg_gt_1_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:util_ds_buf:2.2 mbufg_gt_1_1 ]
  set_property -dict [list \
    CONFIG.C_BUFG_GT_SYNC {true} \
    CONFIG.C_BUF_TYPE {MBUFG_GT} \
  ] $mbufg_gt_1_1

  # Create instance: mbufg_gt_1_2, and set properties
  set mbufg_gt_1_2 [ create_bd_cell -type ip -vlnv xilinx.com:ip:util_ds_buf:2.2 mbufg_gt_1_2 ]
  set_property -dict [list \
    CONFIG.C_BUFG_GT_SYNC {true} \
    CONFIG.C_BUF_TYPE {MBUFG_GT} \
  ] $mbufg_gt_1_2

  # Create instance: mbufg_gt_1_3, and set properties
  set mbufg_gt_1_3 [ create_bd_cell -type ip -vlnv xilinx.com:ip:util_ds_buf:2.2 mbufg_gt_1_3 ]
  set_property -dict [list \
    CONFIG.C_BUFG_GT_SYNC {true} \
    CONFIG.C_BUF_TYPE {MBUFG_GT} \
  ] $mbufg_gt_1_3

  # Create instance: util_ds_buf_0, and set properties
  set util_ds_buf_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:util_ds_buf:2.2 util_ds_buf_0 ]
  set_property CONFIG.C_BUF_TYPE {IBUFDS_GTME5} $util_ds_buf_0

  # Create instance: xlconst_mbufg_0, and set properties
  set xlconst_mbufg_0 [ create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilconstant:1.0 xlconst_mbufg_0 ]
  set_property -dict [list \
    CONFIG.CONST_VAL {1} \
    CONFIG.CONST_WIDTH {1} \
  ] $xlconst_mbufg_0

  # Create interface connections
  connect_bd_intf_net -intf_net APB3_INTF_1 [get_bd_intf_pins APB3_INTF] [get_bd_intf_pins gt_quad_base/APB3_INTF]
  connect_bd_intf_net -intf_net gt_quad_base_GT_Serial [get_bd_intf_pins GT_Serial] [get_bd_intf_pins gt_quad_base/GT_Serial]
  connect_bd_intf_net -intf_net mrmac_0_core_gt_rx_serdes_interface_0 [get_bd_intf_pins RX0_GT_IP_Interface] [get_bd_intf_pins gt_quad_base/RX0_GT_IP_Interface]
  connect_bd_intf_net -intf_net mrmac_0_core_gt_rx_serdes_interface_1 [get_bd_intf_pins RX1_GT_IP_Interface] [get_bd_intf_pins gt_quad_base/RX1_GT_IP_Interface]
  connect_bd_intf_net -intf_net mrmac_0_core_gt_rx_serdes_interface_2 [get_bd_intf_pins RX2_GT_IP_Interface] [get_bd_intf_pins gt_quad_base/RX2_GT_IP_Interface]
  connect_bd_intf_net -intf_net mrmac_0_core_gt_rx_serdes_interface_3 [get_bd_intf_pins RX3_GT_IP_Interface] [get_bd_intf_pins gt_quad_base/RX3_GT_IP_Interface]
  connect_bd_intf_net -intf_net mrmac_0_core_gt_tx_serdes_interface_0 [get_bd_intf_pins TX0_GT_IP_Interface] [get_bd_intf_pins gt_quad_base/TX0_GT_IP_Interface]
  connect_bd_intf_net -intf_net mrmac_0_core_gt_tx_serdes_interface_1 [get_bd_intf_pins TX1_GT_IP_Interface] [get_bd_intf_pins gt_quad_base/TX1_GT_IP_Interface]
  connect_bd_intf_net -intf_net mrmac_0_core_gt_tx_serdes_interface_2 [get_bd_intf_pins TX2_GT_IP_Interface] [get_bd_intf_pins gt_quad_base/TX2_GT_IP_Interface]
  connect_bd_intf_net -intf_net mrmac_0_core_gt_tx_serdes_interface_3 [get_bd_intf_pins TX3_GT_IP_Interface] [get_bd_intf_pins gt_quad_base/TX3_GT_IP_Interface]

  # Create pin connections
  connect_bd_net -net apb3clk_quad_1  [get_bd_pins apb3clk_quad] [get_bd_pins gt_quad_base/apb3clk]
  connect_bd_net -net ch0_loopback_1  [get_bd_pins ch0_loopback] [get_bd_pins gt_quad_base/ch0_loopback]
  connect_bd_net -net ch0_rxrate_1  [get_bd_pins ch0_rxrate] [get_bd_pins gt_quad_base/ch0_rxrate]
  connect_bd_net -net ch0_rxusrclk_1  [get_bd_pins ch0_rxusrclk] [get_bd_pins gt_quad_base/ch0_rxusrclk]
  connect_bd_net -net ch0_txrate_1  [get_bd_pins ch0_txrate] [get_bd_pins gt_quad_base/ch0_txrate]
  connect_bd_net -net ch0_txusrclk_1  [get_bd_pins ch0_txusrclk] [get_bd_pins gt_quad_base/ch0_txusrclk]
  connect_bd_net -net ch1_loopback_1  [get_bd_pins ch1_loopback] [get_bd_pins gt_quad_base/ch1_loopback]
  connect_bd_net -net ch1_rxrate_1  [get_bd_pins ch1_rxrate] [get_bd_pins gt_quad_base/ch1_rxrate]
  connect_bd_net -net ch1_rxusrclk_1  [get_bd_pins ch1_rxusrclk] [get_bd_pins gt_quad_base/ch1_rxusrclk]
  connect_bd_net -net ch1_txrate_1  [get_bd_pins ch1_txrate] [get_bd_pins gt_quad_base/ch1_txrate]
  connect_bd_net -net ch1_txusrclk_1  [get_bd_pins ch1_txusrclk] [get_bd_pins gt_quad_base/ch1_txusrclk]
  connect_bd_net -net ch2_loopback_1  [get_bd_pins ch2_loopback] [get_bd_pins gt_quad_base/ch2_loopback]
  connect_bd_net -net ch2_rxrate_1  [get_bd_pins ch2_rxrate] [get_bd_pins gt_quad_base/ch2_rxrate]
  connect_bd_net -net ch2_rxusrclk_1  [get_bd_pins ch2_rxusrclk] [get_bd_pins gt_quad_base/ch2_rxusrclk]
  connect_bd_net -net ch2_txrate_1  [get_bd_pins ch2_txrate] [get_bd_pins gt_quad_base/ch2_txrate]
  connect_bd_net -net ch2_txusrclk_1  [get_bd_pins ch2_txusrclk] [get_bd_pins gt_quad_base/ch2_txusrclk]
  connect_bd_net -net ch3_loopback_1  [get_bd_pins ch3_loopback] [get_bd_pins gt_quad_base/ch3_loopback]
  connect_bd_net -net ch3_rxrate_1  [get_bd_pins ch3_rxrate] [get_bd_pins gt_quad_base/ch3_rxrate]
  connect_bd_net -net ch3_rxusrclk_1  [get_bd_pins ch3_rxusrclk] [get_bd_pins gt_quad_base/ch3_rxusrclk]
  connect_bd_net -net ch3_txrate_1  [get_bd_pins ch3_txrate] [get_bd_pins gt_quad_base/ch3_txrate]
  connect_bd_net -net ch3_txusrclk_1  [get_bd_pins ch3_txusrclk] [get_bd_pins gt_quad_base/ch3_txusrclk]
  connect_bd_net -net gt_quad_base_ch0_rxoutclk  [get_bd_pins gt_quad_base/ch0_rxoutclk] [get_bd_pins mbufg_gt_1/MBUFG_GT_I]
  connect_bd_net -net gt_quad_base_ch0_txoutclk  [get_bd_pins gt_quad_base/ch0_txoutclk] [get_bd_pins mbufg_gt_0/MBUFG_GT_I]
  connect_bd_net -net gt_quad_base_ch1_rxoutclk  [get_bd_pins gt_quad_base/ch1_rxoutclk] [get_bd_pins mbufg_gt_1_1/MBUFG_GT_I]
  connect_bd_net -net gt_quad_base_ch2_rxoutclk  [get_bd_pins gt_quad_base/ch2_rxoutclk] [get_bd_pins mbufg_gt_1_2/MBUFG_GT_I]
  connect_bd_net -net gt_quad_base_ch3_rxoutclk  [get_bd_pins gt_quad_base/ch3_rxoutclk] [get_bd_pins mbufg_gt_1_3/MBUFG_GT_I]
  connect_bd_net -net gt_quad_base_gtpowergood  [get_bd_pins gt_quad_base/gtpowergood] [get_bd_pins gtpowergood]
  connect_bd_net -net gt_quad_base_txn  [get_bd_pins gt_quad_base/txn] [get_bd_pins gt_txn_out_0]
  connect_bd_net -net gt_quad_base_txp  [get_bd_pins gt_quad_base/txp] [get_bd_pins gt_txp_out_0]
  connect_bd_net -net gt_rxn_in_0_1  [get_bd_pins gt_rxn_in_0] [get_bd_pins gt_quad_base/rxn]
  connect_bd_net -net gt_rxp_in_0_1  [get_bd_pins gt_rxp_in_0] [get_bd_pins gt_quad_base/rxp]
  connect_bd_net -net mbufg_gt_0_MBUFG_GT_O1  [get_bd_pins mbufg_gt_0/MBUFG_GT_O1] [get_bd_pins ch0_tx_usr_clk]
  connect_bd_net -net mbufg_gt_0_MBUFG_GT_O2  [get_bd_pins mbufg_gt_0/MBUFG_GT_O2] [get_bd_pins ch0_tx_usr_clk2]
  connect_bd_net -net mbufg_gt_1_1_MBUFG_GT_O1  [get_bd_pins mbufg_gt_1_1/MBUFG_GT_O1] [get_bd_pins ch1_rx_usr_clk]
  connect_bd_net -net mbufg_gt_1_1_MBUFG_GT_O2  [get_bd_pins mbufg_gt_1_1/MBUFG_GT_O2] [get_bd_pins ch1_rx_usr_clk2]
  connect_bd_net -net mbufg_gt_1_2_MBUFG_GT_O1  [get_bd_pins mbufg_gt_1_2/MBUFG_GT_O1] [get_bd_pins ch2_rx_usr_clk]
  connect_bd_net -net mbufg_gt_1_2_MBUFG_GT_O2  [get_bd_pins mbufg_gt_1_2/MBUFG_GT_O2] [get_bd_pins ch2_rx_usr_clk2]
  connect_bd_net -net mbufg_gt_1_3_MBUFG_GT_O1  [get_bd_pins mbufg_gt_1_3/MBUFG_GT_O1] [get_bd_pins ch3_rx_usr_clk]
  connect_bd_net -net mbufg_gt_1_3_MBUFG_GT_O2  [get_bd_pins mbufg_gt_1_3/MBUFG_GT_O2] [get_bd_pins ch3_rx_usr_clk2]
  connect_bd_net -net mbufg_gt_1_MBUFG_GT_O1  [get_bd_pins mbufg_gt_1/MBUFG_GT_O1] [get_bd_pins ch0_rx_usr_clk]
  connect_bd_net -net mbufg_gt_1_MBUFG_GT_O2  [get_bd_pins mbufg_gt_1/MBUFG_GT_O2] [get_bd_pins ch0_rx_usr_clk2]
  connect_bd_net -net mrmac_0_core_rx_clr_out_0  [get_bd_pins MBUFG_GT_CLR1] [get_bd_pins mbufg_gt_1/MBUFG_GT_CLR]
  connect_bd_net -net mrmac_0_core_rx_clr_out_1  [get_bd_pins MBUFG_GT_CLR2] [get_bd_pins mbufg_gt_1_1/MBUFG_GT_CLR]
  connect_bd_net -net mrmac_0_core_rx_clr_out_2  [get_bd_pins MBUFG_GT_CLR3] [get_bd_pins mbufg_gt_1_2/MBUFG_GT_CLR]
  connect_bd_net -net mrmac_0_core_rx_clr_out_3  [get_bd_pins MBUFG_GT_CLR4] [get_bd_pins mbufg_gt_1_3/MBUFG_GT_CLR]
  connect_bd_net -net mrmac_0_core_rx_clrb_leaf_out_0  [get_bd_pins MBUFG_GT_CLRB_LEAF1] [get_bd_pins mbufg_gt_1/MBUFG_GT_CLRB_LEAF]
  connect_bd_net -net mrmac_0_core_rx_clrb_leaf_out_1  [get_bd_pins MBUFG_GT_CLRB_LEAF2] [get_bd_pins mbufg_gt_1_1/MBUFG_GT_CLRB_LEAF]
  connect_bd_net -net mrmac_0_core_rx_clrb_leaf_out_2  [get_bd_pins MBUFG_GT_CLRB_LEAF3] [get_bd_pins mbufg_gt_1_2/MBUFG_GT_CLRB_LEAF]
  connect_bd_net -net mrmac_0_core_rx_clrb_leaf_out_3  [get_bd_pins MBUFG_GT_CLRB_LEAF4] [get_bd_pins mbufg_gt_1_3/MBUFG_GT_CLRB_LEAF]
  connect_bd_net -net mrmac_0_core_tx_clr_out_0  [get_bd_pins MBUFG_GT_CLR] [get_bd_pins mbufg_gt_0/MBUFG_GT_CLR]
  connect_bd_net -net mrmac_0_core_tx_clrb_leaf_out_0  [get_bd_pins MBUFG_GT_CLRB_LEAF] [get_bd_pins mbufg_gt_0/MBUFG_GT_CLRB_LEAF]
  connect_bd_net -net apb3presetn_1  [get_bd_pins apb3presetn] [get_bd_pins gt_quad_base/apb3presetn]

  # This important to note that we use GT_REFCLK0 and not GT_REFCLK1
  connect_bd_net -net util_ds_buf_0_IBUFDS_GTME5_O  [get_bd_pins util_ds_buf_0/IBUFDS_GTME5_O]   [get_bd_pins gt_quad_base/GT_REFCLK0]
  # GT_REFCLK1 will therefore be unconnected even if this triggers a critical warning [BD 41-759]

  connect_bd_net -net xlconst_mbufg_0_dout  [get_bd_pins xlconst_mbufg_0/dout] \
  [get_bd_pins mbufg_gt_0/MBUFG_GT_CE] \
  [get_bd_pins mbufg_gt_1/MBUFG_GT_CE] \
  [get_bd_pins mbufg_gt_1_1/MBUFG_GT_CE] \
  [get_bd_pins mbufg_gt_1_2/MBUFG_GT_CE] \
  [get_bd_pins mbufg_gt_1_3/MBUFG_GT_CE]

  # Restore current instance
  current_bd_instance $oldCurInst
}

proc create_hier_cell_mrmac_wrapper  { parentCell nameHier } {

  set parentObj [check_parent_hier $parentCell $nameHier]
  if { $parentObj == "" } { return }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj

  # Create cell and set as current instance
  set hier_obj [create_bd_cell -type hier $nameHier]
  current_bd_instance $hier_obj

  ####################################
  # get global var
  ####################################
  set AXIL_DATA_W $_nsp_hpu::AXIL_DATA_W
  set AXIS_DATA_W   $_nsp_hpu::AXIS_DATA_W
  set AXIS_DATA_MHDMA_W $_nsp_hpu::AXIS_DATA_MHDMA_W
  set AXIS_DATA_MHDMA_BYTES $_nsp_hpu::AXIS_DATA_MHDMA_BYTES

  ####################################
  # Create pins
  ####################################
  # Create interface pins
  set GT_Serial [ create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:gt_rtl:1.0 GT_Serial ]

  set CLK_IN_D [ create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 CLK_IN_D ]

  set s_axil_mrmac [ create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 s_axil_mrmac ]

  create_bd_intf_pin -mode Slave -vlnv xilinx.com:display_mrmac:mrmac_ctrl_ports:2.0 ctl_tx_port0
  create_bd_intf_pin -mode Slave -vlnv xilinx.com:display_mrmac:mrmac_ctrl_ports:2.0 ctl_tx_port1
  create_bd_intf_pin -mode Slave -vlnv xilinx.com:display_mrmac:mrmac_ctrl_ports:2.0 ctl_tx_port2
  create_bd_intf_pin -mode Slave -vlnv xilinx.com:display_mrmac:mrmac_ctrl_ports:2.0 ctl_tx_port3
  create_bd_intf_pin -mode Slave -vlnv xilinx.com:display_mrmac:mrmac_statistics_ports:2.0 tx_preamblein
  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:apb_rtl:1.0 APB3_INTF

  # Create pins
  set apb3clk_quad [ create_bd_pin -dir I -type clk apb3clk_quad ]
  set apb3presetn [ create_bd_pin -dir I -type rst apb3presetn ]

  set s_axi_aclk [ create_bd_pin -dir I -type clk s_axi_aclk ]
  set s_axi_aresetn [ create_bd_pin -dir I -type rst s_axi_aresetn ]

  set s_axis_mrmac_aclk [ create_bd_pin -dir I -type clk s_axis_mrmac_aclk ]

  set gt_tx_reset_done_out [ create_bd_pin -dir O -from 3 -to 0 gt_tx_reset_done_out ]
  set gt_rx_reset_done_out [ create_bd_pin -dir O -from 3 -to 0 gt_rx_reset_done_out ]
  set gt_reset_all_in [ create_bd_pin -dir I -from 3 -to 0 gt_reset_all_in ]

  # == TX axi-stream interface
  set tx_axis_tdata_0   [ create_bd_pin -dir I -from [expr $AXIS_DATA_MHDMA_W - 1] -to 0 tx_axis_tdata_0 ]
  set tx_axis_tready_0  [ create_bd_pin -dir O tx_axis_tready_0 ]
  set tx_axis_tlast_0   [ create_bd_pin -dir I tx_axis_tlast_0 ]
  set tx_axis_tvalid_0  [ create_bd_pin -dir I tx_axis_tvalid_0 ]

  set tx_axis_tdata_2   [ create_bd_pin -dir I -from [expr $AXIS_DATA_MHDMA_W - 1] -to 0 tx_axis_tdata_2 ]
  set tx_axis_tready_2  [ create_bd_pin -dir O tx_axis_tready_2 ]
  set tx_axis_tlast_2   [ create_bd_pin -dir I tx_axis_tlast_2 ]
  set tx_axis_tvalid_2  [ create_bd_pin -dir I tx_axis_tvalid_2 ]

  set tx_axis_tdata_4   [ create_bd_pin -dir I -from [expr $AXIS_DATA_MHDMA_W - 1] -to 0 tx_axis_tdata_4 ]
  set tx_axis_tready_4  [ create_bd_pin -dir O tx_axis_tready_4 ]
  set tx_axis_tlast_4   [ create_bd_pin -dir I tx_axis_tlast_4 ]
  set tx_axis_tvalid_4  [ create_bd_pin -dir I tx_axis_tvalid_4 ]

  set tx_axis_tdata_6   [ create_bd_pin -dir I -from [expr $AXIS_DATA_MHDMA_W - 1] -to 0 tx_axis_tdata_6 ]
  set tx_axis_tready_6  [ create_bd_pin -dir O tx_axis_tready_6 ]
  set tx_axis_tlast_6   [ create_bd_pin -dir I tx_axis_tlast_6 ]
  set tx_axis_tvalid_6  [ create_bd_pin -dir I tx_axis_tvalid_6 ]

  set tx_axis_tkeep_user_0 [ create_bd_pin -dir I -from 10 -to 0 tx_axis_tkeep_user_0 ]
  set tx_axis_tkeep_user_2 [ create_bd_pin -dir I -from 10 -to 0 tx_axis_tkeep_user_2 ]
  set tx_axis_tkeep_user_4 [ create_bd_pin -dir I -from 10 -to 0 tx_axis_tkeep_user_4 ]
  set tx_axis_tkeep_user_6 [ create_bd_pin -dir I -from 10 -to 0 tx_axis_tkeep_user_6 ]

  # == RX axi-stream interface
  set rx_axis_tdata_0      [ create_bd_pin -dir O -from [expr $AXIS_DATA_MHDMA_W - 1] -to 0 rx_axis_tdata_0 ]
  set rx_axis_tkeep_user_0 [ create_bd_pin -dir O -from 10 -to 0 rx_axis_tkeep_user_0 ]
  set rx_axis_tlast_0     [ create_bd_pin -dir O rx_axis_tlast_0 ]
  set rx_axis_tvalid_0    [ create_bd_pin -dir O rx_axis_tvalid_0 ]

  set rx_axis_tdata_2      [ create_bd_pin -dir O -from [expr $AXIS_DATA_MHDMA_W - 1] -to 0 rx_axis_tdata_2 ]
  set rx_axis_tkeep_user_2 [ create_bd_pin -dir O -from 10 -to 0 rx_axis_tkeep_user_2 ]
  set rx_axis_tlast_2     [ create_bd_pin -dir O rx_axis_tlast_2 ]
  set rx_axis_tvalid_2    [ create_bd_pin -dir O rx_axis_tvalid_2 ]

  set rx_axis_tdata_4      [ create_bd_pin -dir O -from [expr $AXIS_DATA_MHDMA_W - 1] -to 0 rx_axis_tdata_4 ]
  set rx_axis_tkeep_user_4 [ create_bd_pin -dir O -from 10 -to 0 rx_axis_tkeep_user_4 ]
  set rx_axis_tlast_4     [ create_bd_pin -dir O rx_axis_tlast_4 ]
  set rx_axis_tvalid_4    [ create_bd_pin -dir O rx_axis_tvalid_4 ]

  set rx_axis_tdata_6      [ create_bd_pin -dir O -from [expr $AXIS_DATA_MHDMA_W - 1] -to 0 rx_axis_tdata_6 ]
  set rx_axis_tkeep_user_6 [ create_bd_pin -dir O -from 10 -to 0 rx_axis_tkeep_user_6 ]
  set rx_axis_tlast_6     [ create_bd_pin -dir O rx_axis_tlast_6 ]
  set rx_axis_tvalid_6    [ create_bd_pin -dir O rx_axis_tvalid_6 ]

  set gt_reset_tx_datapath_in [ create_bd_pin -dir I -from 3 -to 0 gt_reset_tx_datapath_in ]
  set gt_reset_rx_datapath_in [ create_bd_pin -dir I -from 3 -to 0 gt_reset_rx_datapath_in ]
  set pm_rdy [ create_bd_pin -dir O -from 3 -to 0 pm_rdy ]


  set ch0_loopback [ create_bd_pin -dir I -from 2 -to 0 ch0_loopback ]
  set ch0_txrate [ create_bd_pin -dir I -from 7 -to 0 ch0_txrate ]
  set ch0_rxrate [ create_bd_pin -dir I -from 7 -to 0 ch0_rxrate ]
  set ch1_loopback [ create_bd_pin -dir I -from 2 -to 0 ch1_loopback ]
  set ch1_txrate [ create_bd_pin -dir I -from 7 -to 0 ch1_txrate ]
  set ch1_rxrate [ create_bd_pin -dir I -from 7 -to 0 ch1_rxrate ]
  set ch2_loopback [ create_bd_pin -dir I -from 2 -to 0 ch2_loopback ]
  set ch2_txrate [ create_bd_pin -dir I -from 7 -to 0 ch2_txrate ]
  set ch2_rxrate [ create_bd_pin -dir I -from 7 -to 0 ch2_rxrate ]
  set ch3_loopback [ create_bd_pin -dir I -from 2 -to 0 ch3_loopback ]
  set ch3_txrate [ create_bd_pin -dir I -from 7 -to 0 ch3_txrate ]
  set ch3_rxrate [ create_bd_pin -dir I -from 7 -to 0 ch3_rxrate ]
  set gt_rxn_in_0 [ create_bd_pin -dir I -from 3 -to 0 gt_rxn_in_0 ]
  set gt_rxp_in_0 [ create_bd_pin -dir I -from 3 -to 0 gt_rxp_in_0 ]
  set gt_txn_out_0 [ create_bd_pin -dir O -from 3 -to 0 gt_txn_out_0 ]
  set gt_txp_out_0 [ create_bd_pin -dir O -from 3 -to 0 gt_txp_out_0 ]

  # Create instance: mrmac_0_core, and set properties
  # Static 4 x 25GE Narrow
  # No FEC
  # Must use GTM
  # Placement near bank 111
  set mrmac_0_core [ create_bd_cell -type ip -vlnv xilinx.com:ip:mrmac:3.1 mrmac_0_core ]
  set_property -dict [list \
    CONFIG.FAST_SIM_MODE {0} \
    CONFIG.FEC_SLICE0_CFG_C0 {FEC Disabled (Bypass)} \
    CONFIG.FEC_SLICE1_CFG_C0 {FEC Disabled (Bypass)} \
    CONFIG.FEC_SLICE2_CFG_C0 {FEC Disabled (Bypass)} \
    CONFIG.FEC_SLICE3_CFG_C0 {FEC Disabled (Bypass)} \
    CONFIG.FLEX_PORT0_DATA_RATE_C0 {25GE} \
    CONFIG.FLEX_PORT1_DATA_RATE_C0 {N/A} \
    CONFIG.FLEX_PORT2_DATA_RATE_C0 {N/A} \
    CONFIG.FLEX_PORT3_DATA_RATE_C0 {N/A} \
    CONFIG.GT_PIPELINE_STAGES {0} \
    CONFIG.GT_TYPE_C0 {GTM} \
    CONFIG.MAC_PORT0_ENABLE_TIME_STAMPING_C0 {0} \
    CONFIG.MAC_PORT0_PREEMPTION_C0 {0} \
    CONFIG.MAC_PORT0_RX_FLOW_C0 {0} \
    CONFIG.MAC_PORT0_TX_FLOW_C0 {0} \
    CONFIG.MAC_PORT0_RATE_C0 {25GE} \
    CONFIG.MAC_PORT1_RATE_C0 {25GE} \
    CONFIG.MAC_PORT2_RATE_C0 {25GE} \
    CONFIG.MAC_PORT3_RATE_C0 {25GE} \
    CONFIG.MRMAC_CLIENTS_C0 {4} \
    CONFIG.MRMAC_CONFIGURATION_TYPE {Static Configuration} \
    CONFIG.MRMAC_LOCATION_C0 {MRMAC_X0Y3} \
    CONFIG.MRMAC_MODE_C0 {MAC+PCS} \
    CONFIG.MRMAC_PRESET_C0 {4x25GE Narrow} \
    CONFIG.MRMAC_SPEED_C0 {4x25GE} \
    CONFIG.NUM_GT_CHANNELS {4} \
    CONFIG.PORT0_1588v2_Clocking_C0 {Ordinary/Boundary Clock} \
    CONFIG.PORT1_1588v2_Clocking_C0 {Ordinary/Boundary Clock} \
    CONFIG.PORT2_1588v2_Clocking_C0 {Ordinary/Boundary Clock} \
    CONFIG.PORT3_1588v2_Clocking_C0 {Ordinary/Boundary Clock} \
    CONFIG.PORT0_1588v2_Operation_MODE_C0 {No operation} \
    CONFIG.PORT1_1588v2_Operation_MODE_C0 {No operation} \
    CONFIG.PORT2_1588v2_Operation_MODE_C0 {No operation} \
    CONFIG.PORT3_1588v2_Operation_MODE_C0 {No operation} \
    CONFIG.TIMESTAMP_CLK_PERIOD_NS {4.0000} \
  ] $mrmac_0_core

  # Create instance within hier object: mrmac_0_gt_wrapper
  create_hier_cell_mrmac_0_gt_wrapper $hier_obj mrmac_0_gt_wrapper

  # modules for transceiver <-> MRMAC connections
  # resets
  set concat_4_flexif_reset    [create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilconcat:1.0 concat_4_flexif_reset]

  set ilvector_not_flexif_reset [create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilvector_logic:1.0 ilvector_not_flexif_reset]

  set_property -dict [list \
    CONFIG.C_OPERATION {not} \
    CONFIG.C_SIZE {1} \
  ] $ilvector_not_flexif_reset

  set ilvector_not_4_tx_reset_done [create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilvector_logic:1.0 ilvector_not_4_tx_reset_done]
  set ilvector_not_4_rx_reset_done [create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilvector_logic:1.0 ilvector_not_4_rx_reset_done]

  set_property -dict [list \
    CONFIG.C_OPERATION {not} \
    CONFIG.C_SIZE {4} \
  ]  [get_bd_cells -filter {NAME=~"*ilvector_not_4*"}]

  # clocks
  set concat_4_clk_axis_mrmac  [create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilconcat:1.0 concat_4_clk_axis_mrmac]
  set concat_4_clk_ts          [create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilconcat:1.0 concat_4_clk_ts]
  set concat_4_clk_mhdma_control [create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilconcat:1.0 concat_4_clk_mhdma_control]

  set concat_4_rx_usr_clock  [create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilconcat:1.0 concat_4_rx_usr_clock]
  set concat_4_rx_usr_clock2 [create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilconcat:1.0 concat_4_rx_usr_clock2]
  set concat_4_tx_usr_clock  [create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilconcat:1.0 concat_4_tx_usr_clock]
  set concat_4_tx_usr_clock2 [create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilconcat:1.0 concat_4_tx_usr_clock2]

  # signals
  set concat_4_pm_tick [create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilconcat:1.0 concat_4_pm_tick]
  set ilconst_tick [create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilconstant:1.0 ilconst_tick]

  set_property CONFIG.NUM_PORTS {4} [get_bd_cells -filter {NAME=~"*concat_4*"}]
  ####################################
  # Connection
  ####################################
  # clocks and resets
  connect_bd_net -net config_aresetn [get_bd_pins s_axi_aresetn] [get_bd_pins mrmac_0_core/s_axi_aresetn]

  connect_bd_net -net config_aclk [get_bd_pins s_axi_aclk] [get_bd_pins mrmac_0_core/s_axi_aclk]

  # GT <-> MRMAC connections ----------------------------------------------------------------------
  # ~mhdma_cfg_srst_n to rx_flexif_reset
  connect_bd_net [get_bd_pins s_axi_aresetn] [get_bd_pins ilvector_not_flexif_reset/Op1]

  for {set i 0} {$i < 4} {incr i} {
    connect_bd_net [get_bd_pins ilvector_not_flexif_reset/Res] [get_bd_pins concat_4_flexif_reset/In${i}]
  }

  connect_bd_net [get_bd_pins concat_4_flexif_reset/Dout] [get_bd_pins mrmac_0_core/rx_flexif_reset]

  # ~ gt_rx_reset_done -> (rx_core_reset & rx_serdes_reset)
  connect_bd_net [get_bd_pins mrmac_0_core/gt_rx_reset_done_out] [get_bd_pins ilvector_not_4_rx_reset_done/Op1]
  connect_bd_net [get_bd_pins ilvector_not_4_rx_reset_done/Res]  [get_bd_pins mrmac_0_core/rx_core_reset]
  connect_bd_net [get_bd_pins ilvector_not_4_rx_reset_done/Res]  [get_bd_pins mrmac_0_core/rx_serdes_reset]

  # ~ gt_tx_reset_done -> (tx_core_reset & tx_serdes_reset)
  connect_bd_net [get_bd_pins mrmac_0_core/gt_tx_reset_done_out] [get_bd_pins ilvector_not_4_tx_reset_done/Op1]
  connect_bd_net [get_bd_pins ilvector_not_4_tx_reset_done/Res]  [get_bd_pins mrmac_0_core/tx_core_reset]
  connect_bd_net [get_bd_pins ilvector_not_4_tx_reset_done/Res]  [get_bd_pins mrmac_0_core/tx_serdes_reset]

  # pm_tick associated to 4'b1
  for {set i 0} {$i < 4} {incr i} {
    connect_bd_net [get_bd_pins ilconst_tick/dout] [get_bd_pins concat_4_pm_tick/In${i}]
  }
  connect_bd_net [get_bd_pins concat_4_pm_tick/Dout] [get_bd_pins mrmac_0_core/pm_tick]


  # s_axis_mrmac_aclk to (tx_axi_clk & rx_axi_clk)
  for {set i 0} {$i < 4} {incr i} {
    connect_bd_net [get_bd_pins s_axis_mrmac_aclk] [get_bd_pins concat_4_clk_axis_mrmac/In${i}]
  }

  connect_bd_net [get_bd_pins concat_4_clk_axis_mrmac/Dout] \
                  [get_bd_pins mrmac_0_core/tx_axi_clk] \
                  [get_bd_pins mrmac_0_core/rx_axi_clk]

  # ts_clk: PTP unused, use apb3clk_quad (200 MHz) to satisfy MRMAC min period
  for {set i 0} {$i < 4} {incr i} {
    connect_bd_net [get_bd_pins apb3clk_quad] [get_bd_pins concat_4_clk_ts/In${i}]
  }
  connect_bd_net [get_bd_pins concat_4_clk_ts/Dout] \
                  [get_bd_pins mrmac_0_core/tx_ts_clk] \
                  [get_bd_pins mrmac_0_core/rx_ts_clk]

  # s_axi_aclk to (rx_flexif_clk & tx_flexif_clk)
  for {set i 0} {$i < 4} {incr i} {
    connect_bd_net [get_bd_pins s_axi_aclk] [get_bd_pins concat_4_clk_mhdma_control/In${i}]
  }

  connect_bd_net [get_bd_pins concat_4_clk_mhdma_control/Dout] \
                  [get_bd_pins mrmac_0_core/rx_flexif_clk] \
                  [get_bd_pins mrmac_0_core/tx_flexif_clk]

  connect_bd_net [get_bd_pins concat_4_rx_usr_clock/In0] [get_bd_pins mrmac_0_gt_wrapper/ch0_rx_usr_clk]
  connect_bd_net [get_bd_pins concat_4_rx_usr_clock/In1] [get_bd_pins mrmac_0_gt_wrapper/ch1_rx_usr_clk]
  connect_bd_net [get_bd_pins concat_4_rx_usr_clock/In2] [get_bd_pins mrmac_0_gt_wrapper/ch2_rx_usr_clk]
  connect_bd_net [get_bd_pins concat_4_rx_usr_clock/In3] [get_bd_pins mrmac_0_gt_wrapper/ch3_rx_usr_clk]

  connect_bd_net [get_bd_pins concat_4_rx_usr_clock/Dout] [get_bd_pins mrmac_0_core/rx_core_clk]
  connect_bd_net [get_bd_pins concat_4_rx_usr_clock/Dout] [get_bd_pins mrmac_0_core/rx_serdes_clk]

  # rx_alt_serdes_clk = {ch3_rx_usr_clk2, ch2_rx_usr_clk2, ch1_rx_usr_clk2, ch0_rx_usr_clk2};
  connect_bd_net [get_bd_pins concat_4_rx_usr_clock2/In0] [get_bd_pins mrmac_0_gt_wrapper/ch0_rx_usr_clk2]
  connect_bd_net [get_bd_pins concat_4_rx_usr_clock2/In1] [get_bd_pins mrmac_0_gt_wrapper/ch1_rx_usr_clk2]
  connect_bd_net [get_bd_pins concat_4_rx_usr_clock2/In2] [get_bd_pins mrmac_0_gt_wrapper/ch2_rx_usr_clk2]
  connect_bd_net [get_bd_pins concat_4_rx_usr_clock2/In3] [get_bd_pins mrmac_0_gt_wrapper/ch3_rx_usr_clk2]

  connect_bd_net [get_bd_pins concat_4_rx_usr_clock2/Dout] [get_bd_pins mrmac_0_core/rx_alt_serdes_clk]

  for {set i 0} {$i < 4} {incr i} {
    connect_bd_net [get_bd_pins mrmac_0_gt_wrapper/ch0_tx_usr_clk] [get_bd_pins concat_4_tx_usr_clock/In${i}]
    connect_bd_net [get_bd_pins mrmac_0_gt_wrapper/ch0_tx_usr_clk2] [get_bd_pins concat_4_tx_usr_clock2/In${i}]
  }
  connect_bd_net [get_bd_pins concat_4_tx_usr_clock/Dout] [get_bd_pins mrmac_0_core/tx_core_clk]
  connect_bd_net [get_bd_pins concat_4_tx_usr_clock2/Dout] [get_bd_pins mrmac_0_core/tx_alt_serdes_clk]


  connect_bd_net -net gtpowergood_net [get_bd_pins mrmac_0_gt_wrapper/gtpowergood] [get_bd_pins mrmac_0_core/gtpowergood_in]


  connect_bd_net [get_bd_pins mrmac_0_gt_wrapper/ch0_tx_usr_clk] \
                    [get_bd_pins mrmac_0_gt_wrapper/ch0_txusrclk] \
                    [get_bd_pins mrmac_0_gt_wrapper/ch1_txusrclk] \
                    [get_bd_pins mrmac_0_gt_wrapper/ch2_txusrclk] \
                    [get_bd_pins mrmac_0_gt_wrapper/ch3_txusrclk] \

  connect_bd_net [get_bd_pins mrmac_0_gt_wrapper/ch0_rx_usr_clk]  [get_bd_pins mrmac_0_gt_wrapper/ch0_rxusrclk]
  connect_bd_net [get_bd_pins mrmac_0_gt_wrapper/ch1_rx_usr_clk]  [get_bd_pins mrmac_0_gt_wrapper/ch1_rxusrclk]
  connect_bd_net [get_bd_pins mrmac_0_gt_wrapper/ch2_rx_usr_clk]  [get_bd_pins mrmac_0_gt_wrapper/ch2_rxusrclk]
  connect_bd_net [get_bd_pins mrmac_0_gt_wrapper/ch3_rx_usr_clk]  [get_bd_pins mrmac_0_gt_wrapper/ch3_rxusrclk]


  # GT wrapper ------------------------------------------------------------------------------------
  connect_bd_intf_net -intf_net APB3_INTF_1            [get_bd_intf_pins mrmac_0_gt_wrapper/APB3_INTF]  [get_bd_intf_pins APB3_INTF]
  connect_bd_intf_net -intf_net CLK_IN_D_1             [get_bd_intf_pins mrmac_0_gt_wrapper/CLK_IN_D]   [get_bd_intf_pins CLK_IN_D]
  connect_bd_intf_net -intf_net gt_quad_base_GT_Serial [get_bd_intf_pins mrmac_0_gt_wrapper/GT_Serial]  [get_bd_intf_pins GT_Serial]
  connect_bd_intf_net -boundary_type upper             [get_bd_intf_pins mrmac_0_gt_wrapper/CLK_IN_D]   [get_bd_intf_pins mrmac_0_gt_wrapper/util_ds_buf_0/CLK_IN_D1]

  connect_bd_net -net cfg_apb3presetn                  [get_bd_pins mrmac_0_gt_wrapper/apb3presetn]     [get_bd_pins apb3presetn]
  connect_bd_net -net apb3clk_quad_1                   [get_bd_pins mrmac_0_gt_wrapper/apb3clk_quad]    [get_bd_pins apb3clk_quad]
  connect_bd_net -net ch0_loopback_1                   [get_bd_pins mrmac_0_gt_wrapper/ch0_loopback]    [get_bd_pins ch0_loopback]
  connect_bd_net -net ch0_rxrate_1                     [get_bd_pins mrmac_0_gt_wrapper/ch0_rxrate]      [get_bd_pins ch0_rxrate]
  connect_bd_net -net ch0_txrate_1                     [get_bd_pins mrmac_0_gt_wrapper/ch0_txrate]      [get_bd_pins ch0_txrate]
  connect_bd_net -net ch1_loopback_1                   [get_bd_pins mrmac_0_gt_wrapper/ch1_loopback]    [get_bd_pins ch1_loopback]
  connect_bd_net -net ch1_rxrate_1                     [get_bd_pins mrmac_0_gt_wrapper/ch1_rxrate]      [get_bd_pins ch1_rxrate]
  connect_bd_net -net ch1_txrate_1                     [get_bd_pins mrmac_0_gt_wrapper/ch1_txrate]      [get_bd_pins ch1_txrate]
  connect_bd_net -net ch2_loopback_1                   [get_bd_pins mrmac_0_gt_wrapper/ch2_loopback]    [get_bd_pins ch2_loopback]
  connect_bd_net -net ch2_rxrate_1                     [get_bd_pins mrmac_0_gt_wrapper/ch2_rxrate]      [get_bd_pins ch2_rxrate]
  connect_bd_net -net ch2_txrate_1                     [get_bd_pins mrmac_0_gt_wrapper/ch2_txrate]      [get_bd_pins ch2_txrate]
  connect_bd_net -net ch3_loopback_1                   [get_bd_pins mrmac_0_gt_wrapper/ch3_loopback]    [get_bd_pins ch3_loopback]
  connect_bd_net -net ch3_rxrate_1                     [get_bd_pins mrmac_0_gt_wrapper/ch3_rxrate]      [get_bd_pins ch3_rxrate]
  connect_bd_net -net ch3_txrate_1                     [get_bd_pins mrmac_0_gt_wrapper/ch3_txrate]      [get_bd_pins ch3_txrate]
  connect_bd_net -net gt_rxn_in_0_1                    [get_bd_pins mrmac_0_gt_wrapper/gt_rxn_in_0]     [get_bd_pins gt_rxn_in_0]
  connect_bd_net -net gt_rxp_in_0_1                    [get_bd_pins mrmac_0_gt_wrapper/gt_rxp_in_0]     [get_bd_pins gt_rxp_in_0]
  connect_bd_net -net gt_quad_base_txn                 [get_bd_pins mrmac_0_gt_wrapper/gt_txn_out_0]    [get_bd_pins gt_txn_out_0]
  connect_bd_net -net gt_quad_base_txp                 [get_bd_pins mrmac_0_gt_wrapper/gt_txp_out_0]    [get_bd_pins gt_txp_out_0]

  # MRMAC core
  connect_bd_net -net mrmac_0_core_gt_reset_all_in          [get_bd_pins mrmac_0_core/gt_reset_all_in]         [get_bd_pins gt_reset_all_in]
  connect_bd_net -net mrmac_0_core_gt_reset_rx_datapath_in  [get_bd_pins mrmac_0_core/gt_reset_rx_datapath_in] [get_bd_pins gt_reset_rx_datapath_in]
  connect_bd_net -net mrmac_0_core_gt_reset_tx_datapath_in  [get_bd_pins mrmac_0_core/gt_reset_tx_datapath_in] [get_bd_pins gt_reset_tx_datapath_in]
  connect_bd_net -net mrmac_0_core_rx_clr_out_0             [get_bd_pins mrmac_0_core/rx_clr_out_0]            [get_bd_pins mrmac_0_gt_wrapper/MBUFG_GT_CLR1]
  connect_bd_net -net mrmac_0_core_rx_clr_out_1             [get_bd_pins mrmac_0_core/rx_clr_out_1]            [get_bd_pins mrmac_0_gt_wrapper/MBUFG_GT_CLR2]
  connect_bd_net -net mrmac_0_core_rx_clr_out_2             [get_bd_pins mrmac_0_core/rx_clr_out_2]            [get_bd_pins mrmac_0_gt_wrapper/MBUFG_GT_CLR3]
  connect_bd_net -net mrmac_0_core_rx_clr_out_3             [get_bd_pins mrmac_0_core/rx_clr_out_3]            [get_bd_pins mrmac_0_gt_wrapper/MBUFG_GT_CLR4]
  connect_bd_net -net mrmac_0_core_rx_clrb_leaf_out_0       [get_bd_pins mrmac_0_core/rx_clrb_leaf_out_0]      [get_bd_pins mrmac_0_gt_wrapper/MBUFG_GT_CLRB_LEAF1]
  connect_bd_net -net mrmac_0_core_rx_clrb_leaf_out_1       [get_bd_pins mrmac_0_core/rx_clrb_leaf_out_1]      [get_bd_pins mrmac_0_gt_wrapper/MBUFG_GT_CLRB_LEAF2]
  connect_bd_net -net mrmac_0_core_rx_clrb_leaf_out_2       [get_bd_pins mrmac_0_core/rx_clrb_leaf_out_2]      [get_bd_pins mrmac_0_gt_wrapper/MBUFG_GT_CLRB_LEAF3]
  connect_bd_net -net mrmac_0_core_rx_clrb_leaf_out_3       [get_bd_pins mrmac_0_core/rx_clrb_leaf_out_3]      [get_bd_pins mrmac_0_gt_wrapper/MBUFG_GT_CLRB_LEAF4]
  connect_bd_net -net mrmac_0_core_tx_clr_out_0             [get_bd_pins mrmac_0_core/tx_clr_out_0]            [get_bd_pins mrmac_0_gt_wrapper/MBUFG_GT_CLR]
  connect_bd_net -net mrmac_0_core_tx_clrb_leaf_out_0       [get_bd_pins mrmac_0_core/tx_clrb_leaf_out_0]      [get_bd_pins mrmac_0_gt_wrapper/MBUFG_GT_CLRB_LEAF]
  connect_bd_net -net mrmac_0_core_gt_rx_reset_done_out     [get_bd_pins mrmac_0_core/gt_rx_reset_done_out]    [get_bd_pins gt_rx_reset_done_out]
  connect_bd_net -net mrmac_0_core_gt_tx_reset_done_out     [get_bd_pins mrmac_0_core/gt_tx_reset_done_out]    [get_bd_pins gt_tx_reset_done_out]
  connect_bd_net -net mrmac_0_core_pm_rdy                   [get_bd_pins mrmac_0_core/pm_rdy]                  [get_bd_pins pm_rdy]

  connect_bd_intf_net -intf_net ctl_tx_pin0_1               [get_bd_intf_pins mrmac_0_core/ctl_tx_port0]              [get_bd_intf_pins ctl_tx_port0]
  connect_bd_intf_net -intf_net ctl_tx_pin1_1               [get_bd_intf_pins mrmac_0_core/ctl_tx_port1]              [get_bd_intf_pins ctl_tx_port1]
  connect_bd_intf_net -intf_net ctl_tx_pin2_1               [get_bd_intf_pins mrmac_0_core/ctl_tx_port2]              [get_bd_intf_pins ctl_tx_port2]
  connect_bd_intf_net -intf_net ctl_tx_pin3_1               [get_bd_intf_pins mrmac_0_core/ctl_tx_port3]              [get_bd_intf_pins ctl_tx_port3]
  connect_bd_intf_net -intf_net s_axi_1                     [get_bd_intf_pins mrmac_0_core/s_axi]                     [get_bd_intf_pins s_axil_mrmac]
  connect_bd_intf_net -intf_net tx_preamblein_1             [get_bd_intf_pins mrmac_0_core/tx_preamblein]             [get_bd_intf_pins tx_preamblein]
  connect_bd_intf_net                                       [get_bd_intf_pins mrmac_0_core/gtm_tx_serdes_interface_0] [get_bd_intf_pins mrmac_0_gt_wrapper/TX0_GT_IP_Interface]
  connect_bd_intf_net                                       [get_bd_intf_pins mrmac_0_core/gtm_tx_serdes_interface_1] [get_bd_intf_pins mrmac_0_gt_wrapper/TX1_GT_IP_Interface]
  connect_bd_intf_net                                       [get_bd_intf_pins mrmac_0_core/gtm_tx_serdes_interface_2] [get_bd_intf_pins mrmac_0_gt_wrapper/TX2_GT_IP_Interface]
  connect_bd_intf_net                                       [get_bd_intf_pins mrmac_0_core/gtm_tx_serdes_interface_3] [get_bd_intf_pins mrmac_0_gt_wrapper/TX3_GT_IP_Interface]
  connect_bd_intf_net                                       [get_bd_intf_pins mrmac_0_core/gtm_rx_serdes_interface_0] [get_bd_intf_pins mrmac_0_gt_wrapper/RX0_GT_IP_Interface]
  connect_bd_intf_net                                       [get_bd_intf_pins mrmac_0_core/gtm_rx_serdes_interface_1] [get_bd_intf_pins mrmac_0_gt_wrapper/RX1_GT_IP_Interface]
  connect_bd_intf_net                                       [get_bd_intf_pins mrmac_0_core/gtm_rx_serdes_interface_2] [get_bd_intf_pins mrmac_0_gt_wrapper/RX2_GT_IP_Interface]
  connect_bd_intf_net                                       [get_bd_intf_pins mrmac_0_core/gtm_rx_serdes_interface_3] [get_bd_intf_pins mrmac_0_gt_wrapper/RX3_GT_IP_Interface]

  # on the IP side, axi stream suffix is a mix and match of different things.
  # Trying to keep something homogeous on the top of this block: lanes 0, 2, 4, 6 (from mrmac configuration) + underscore before suffix
  # == RX Lanes
  # 0
  connect_bd_net -net mrmac_0_core_rx_axis_tdata_0      [get_bd_pins mrmac_0_core/rx_axis_tdata0]       [get_bd_pins rx_axis_tdata_0]
  connect_bd_net -net mrmac_0_core_rx_axis_tkeep_user_0 [get_bd_pins mrmac_0_core/rx_axis_tkeep_user0]  [get_bd_pins rx_axis_tkeep_user_0]
  connect_bd_net -net mrmac_0_core_rx_axis_tlast_0      [get_bd_pins mrmac_0_core/rx_axis_tlast_0]      [get_bd_pins rx_axis_tlast_0]
  connect_bd_net -net mrmac_0_core_rx_axis_tvalid_0     [get_bd_pins mrmac_0_core/rx_axis_tvalid_0]     [get_bd_pins rx_axis_tvalid_0]
  # 1
  connect_bd_net -net mrmac_0_core_rx_axis_tdata_2      [get_bd_pins mrmac_0_core/rx_axis_tdata2]       [get_bd_pins rx_axis_tdata_2]
  connect_bd_net -net mrmac_0_core_rx_axis_tkeep_user_2 [get_bd_pins mrmac_0_core/rx_axis_tkeep_user2]  [get_bd_pins rx_axis_tkeep_user_2]
  connect_bd_net -net mrmac_0_core_rx_axis_tlast_2      [get_bd_pins mrmac_0_core/rx_axis_tlast_1]      [get_bd_pins rx_axis_tlast_2]
  connect_bd_net -net mrmac_0_core_rx_axis_tvalid_2     [get_bd_pins mrmac_0_core/rx_axis_tvalid_1]     [get_bd_pins rx_axis_tvalid_2]
  # 2
  connect_bd_net -net mrmac_0_core_rx_axis_tdata_4      [get_bd_pins mrmac_0_core/rx_axis_tdata4]       [get_bd_pins rx_axis_tdata_4]
  connect_bd_net -net mrmac_0_core_rx_axis_tkeep_user_4 [get_bd_pins mrmac_0_core/rx_axis_tkeep_user4]  [get_bd_pins rx_axis_tkeep_user_4]
  connect_bd_net -net mrmac_0_core_rx_axis_tlast_4      [get_bd_pins mrmac_0_core/rx_axis_tlast_2]      [get_bd_pins rx_axis_tlast_4]
  connect_bd_net -net mrmac_0_core_rx_axis_tvalid_4     [get_bd_pins mrmac_0_core/rx_axis_tvalid_2]     [get_bd_pins rx_axis_tvalid_4]
  # 3
  connect_bd_net -net mrmac_0_core_rx_axis_tdata_6      [get_bd_pins mrmac_0_core/rx_axis_tdata6]       [get_bd_pins rx_axis_tdata_6]
  connect_bd_net -net mrmac_0_core_rx_axis_tkeep_user_6 [get_bd_pins mrmac_0_core/rx_axis_tkeep_user6]  [get_bd_pins rx_axis_tkeep_user_6]
  connect_bd_net -net mrmac_0_core_rx_axis_tlast_6      [get_bd_pins mrmac_0_core/rx_axis_tlast_3]      [get_bd_pins rx_axis_tlast_6]
  connect_bd_net -net mrmac_0_core_rx_axis_tvalid_6     [get_bd_pins mrmac_0_core/rx_axis_tvalid_3]     [get_bd_pins rx_axis_tvalid_6]
  # == TX Lanes
  # 0
  connect_bd_net -net mrmac_0_core_tx_axis_tdata_0      [get_bd_pins tx_axis_tdata_0]      [get_bd_pins mrmac_0_core/tx_axis_tdata0]
  connect_bd_net -net mrmac_0_core_tx_axis_tkeep_user_0 [get_bd_pins tx_axis_tkeep_user_0] [get_bd_pins mrmac_0_core/tx_axis_tkeep_user0]
  connect_bd_net -net mrmac_0_core_tx_axis_tlast_0      [get_bd_pins tx_axis_tlast_0]      [get_bd_pins mrmac_0_core/tx_axis_tlast_0]
  connect_bd_net -net mrmac_0_core_tx_axis_tvalid_0     [get_bd_pins tx_axis_tvalid_0]     [get_bd_pins mrmac_0_core/tx_axis_tvalid_0]
  connect_bd_net -net mrmac_0_core_tx_axis_tready_0     [get_bd_pins tx_axis_tready_0]     [get_bd_pins mrmac_0_core/tx_axis_tready_0]
  # 1
  connect_bd_net -net mrmac_0_core_tx_axis_tdata_2      [get_bd_pins tx_axis_tdata_2]      [get_bd_pins mrmac_0_core/tx_axis_tdata2]
  connect_bd_net -net mrmac_0_core_tx_axis_tkeep_user_2 [get_bd_pins tx_axis_tkeep_user_2] [get_bd_pins mrmac_0_core/tx_axis_tkeep_user2]
  connect_bd_net -net mrmac_0_core_tx_axis_tlast_2      [get_bd_pins tx_axis_tlast_2]      [get_bd_pins mrmac_0_core/tx_axis_tlast_1]
  connect_bd_net -net mrmac_0_core_tx_axis_tvalid_2     [get_bd_pins tx_axis_tvalid_2]     [get_bd_pins mrmac_0_core/tx_axis_tvalid_1]
  connect_bd_net -net mrmac_0_core_tx_axis_tready_2     [get_bd_pins tx_axis_tready_2]     [get_bd_pins mrmac_0_core/tx_axis_tready_1]
  # 2
  connect_bd_net -net mrmac_0_core_tx_axis_tdata_4      [get_bd_pins tx_axis_tdata_4]      [get_bd_pins mrmac_0_core/tx_axis_tdata4]
  connect_bd_net -net mrmac_0_core_tx_axis_tkeep_user_4 [get_bd_pins tx_axis_tkeep_user_4] [get_bd_pins mrmac_0_core/tx_axis_tkeep_user4]
  connect_bd_net -net mrmac_0_core_tx_axis_tlast_4      [get_bd_pins tx_axis_tlast_4]      [get_bd_pins mrmac_0_core/tx_axis_tlast_2]
  connect_bd_net -net mrmac_0_core_tx_axis_tvalid_4     [get_bd_pins tx_axis_tvalid_4]     [get_bd_pins mrmac_0_core/tx_axis_tvalid_2]
  connect_bd_net -net mrmac_0_core_tx_axis_tready_4     [get_bd_pins tx_axis_tready_4]     [get_bd_pins mrmac_0_core/tx_axis_tready_2]
  # 3
  connect_bd_net -net mrmac_0_core_tx_axis_tdata_6      [get_bd_pins tx_axis_tdata_6]      [get_bd_pins mrmac_0_core/tx_axis_tdata6]
  connect_bd_net -net mrmac_0_core_tx_axis_tkeep_user_6 [get_bd_pins tx_axis_tkeep_user_6] [get_bd_pins mrmac_0_core/tx_axis_tkeep_user6]
  connect_bd_net -net mrmac_0_core_tx_axis_tlast_6      [get_bd_pins tx_axis_tlast_6]      [get_bd_pins mrmac_0_core/tx_axis_tlast_3]
  connect_bd_net -net mrmac_0_core_tx_axis_tvalid_6     [get_bd_pins tx_axis_tvalid_6]     [get_bd_pins mrmac_0_core/tx_axis_tvalid_3]
  connect_bd_net -net mrmac_0_core_tx_axis_tready_6     [get_bd_pins tx_axis_tready_6]     [get_bd_pins mrmac_0_core/tx_axis_tready_3]

  # Restore current instance
  current_bd_instance $oldCurInst
}
