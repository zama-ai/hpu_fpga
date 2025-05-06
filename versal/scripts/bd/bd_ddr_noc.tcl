# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ==============================================================================================

################################################################
# create_hier_cell_shell_wrapper
################################################################
# Hierarchical cell: shell_wrapper
proc create_hier_cell_ddr_noc { parentCell nameHier } {
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
  set SYS_FREQ $_nsp_hpu::SYS_FREQ

  set PCIE_DDR_DMA_RD_BW $_nsp_hpu::PCIE_DDR_DMA_RD_BW
  set PCIE_DDR_DMA_WR_BW $_nsp_hpu::PCIE_DDR_DMA_WR_BW
  set PCIE_DDR_DMA_RD_BURST_AVG $_nsp_hpu::PCIE_DDR_DMA_RD_BURST_AVG
  set PCIE_DDR_DMA_WR_BURST_AVG $_nsp_hpu::PCIE_DDR_DMA_WR_BURST_AVG

  set SYS_PERIOD [expr int((10**6)/$SYS_FREQ)]

  ####################################
  # Create pins
  ####################################
  # Create pins that will be connected to the ports
  set CH0_DDR4_0_0 [ create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:ddr4_rtl:1.0 CH0_DDR4_0_0 ]
  set sys_clk0_0   [ create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 sys_clk0_0 ]
  set CH0_DDR4_0_1 [ create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:ddr4_rtl:1.0 CH0_DDR4_0_1 ]
  set sys_clk0_1   [ create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 sys_clk0_1 ]

  # Pin for internal use
  set S00_INI_0 [ create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:inimm_rtl:1.0 S00_INI_0 ]
  set S00_INI_1 [ create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:inimm_rtl:1.0 S00_INI_1 ]
  set S01_INI_0 [ create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:inimm_rtl:1.0 S01_INI_0 ]
  set S01_INI_1 [ create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:inimm_rtl:1.0 S01_INI_1 ]

  ####################################
  # Create ddr_noc 0
  ####################################
  set axi_noc_mc_ddr4_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_noc:1.1 axi_noc_mc_ddr4_0 ]
  set_property -dict [list \
    CONFIG.CONTROLLERTYPE {DDR4_SDRAM} \
    CONFIG.MC_CHAN_REGION1 {DDR_CH1} \
    CONFIG.MC_COMPONENT_WIDTH {x16} \
    CONFIG.MC_DATAWIDTH {72} \
    CONFIG.MC_DM_WIDTH {9} \
    CONFIG.MC_DQS_WIDTH {9} \
    CONFIG.MC_DQ_WIDTH {72} \
    CONFIG.MC_INIT_MEM_USING_ECC_SCRUB {true} \
    CONFIG.MC_INPUTCLK0_PERIOD $SYS_PERIOD \
    CONFIG.MC_MEMORY_DEVICETYPE {Components} \
    CONFIG.MC_MEMORY_SPEEDGRADE {DDR4-3200AA(22-22-22)} \
    CONFIG.MC_NO_CHANNELS {Single} \
    CONFIG.MC_RANK {1} \
    CONFIG.MC_ROWADDRESSWIDTH {16} \
    CONFIG.MC_STACKHEIGHT {1} \
    CONFIG.MC_SYSTEM_CLOCK {Differential} \
    CONFIG.NUM_CLKS {0} \
    CONFIG.NUM_MC {1} \
    CONFIG.NUM_MCP {4} \
    CONFIG.NUM_MI {0} \
    CONFIG.NUM_NMI {0} \
    CONFIG.NUM_NSI {2} \
    CONFIG.NUM_SI {0} \
  ] $axi_noc_mc_ddr4_0

  set pcie_ddr_dma_qos [set_qos $PCIE_DDR_DMA_RD_BW $PCIE_DDR_DMA_WR_BW $PCIE_DDR_DMA_RD_BURST_AVG $PCIE_DDR_DMA_WR_BURST_AVG]
  set s00_ini_cnx [list MC_0 $pcie_ddr_dma_qos ]
  set_property -dict [ list \
   CONFIG.CONNECTIONS $s00_ini_cnx \
  ] [get_bd_intf_pins axi_noc_mc_ddr4_0/S00_INI]

  set s01_ini_cnx [list MC_1 $pcie_ddr_dma_qos ]
  set_property -dict [ list \
   CONFIG.CONNECTIONS $s01_ini_cnx \
  ] [get_bd_intf_pins axi_noc_mc_ddr4_0/S01_INI]

  ####################################
  # Create ddr_noc 1
  ####################################
  set axi_noc_mc_ddr4_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_noc:1.1 axi_noc_mc_ddr4_1 ]
  set_property -dict [list \
    CONFIG.CONTROLLERTYPE {DDR4_SDRAM} \
    CONFIG.MC0_CONFIG_NUM {config21} \
    CONFIG.MC0_FLIPPED_PINOUT {false} \
    CONFIG.MC_CHAN_REGION0 {DDR_CH2} \
    CONFIG.MC_COMPONENT_WIDTH {x4} \
    CONFIG.MC_DATAWIDTH {72} \
    CONFIG.MC_INIT_MEM_USING_ECC_SCRUB {true} \
    CONFIG.MC_INPUTCLK0_PERIOD $SYS_PERIOD \
    CONFIG.MC_MEMORY_DEVICETYPE {RDIMMs} \
    CONFIG.MC_MEMORY_SPEEDGRADE {DDR4-3200AA(22-22-22)} \
    CONFIG.MC_NO_CHANNELS {Single} \
    CONFIG.MC_PARITY {true} \
    CONFIG.MC_RANK {1} \
    CONFIG.MC_ROWADDRESSWIDTH {18} \
    CONFIG.MC_STACKHEIGHT {1} \
    CONFIG.MC_SYSTEM_CLOCK {Differential} \
    CONFIG.NUM_CLKS {0} \
    CONFIG.NUM_MC {1} \
    CONFIG.NUM_MCP {4} \
    CONFIG.NUM_MI {0} \
    CONFIG.NUM_NMI {0} \
    CONFIG.NUM_NSI {2} \
    CONFIG.NUM_SI {0} \
  ] $axi_noc_mc_ddr4_1


  set_property -dict [ list \
   CONFIG.CONNECTIONS $s00_ini_cnx \
 ] [get_bd_intf_pins axi_noc_mc_ddr4_1/S00_INI]

  set_property -dict [ list \
   CONFIG.CONNECTIONS $s01_ini_cnx \
 ] [get_bd_intf_pins axi_noc_mc_ddr4_1/S01_INI]

  ####################################
  # Connection
  ####################################
  # Connect internal pins
  connect_bd_intf_net -intf_net CH0_DDR4_0_0 [get_bd_intf_pins axi_noc_mc_ddr4_0/CH0_DDR4_0] [get_bd_intf_pins CH0_DDR4_0_0]
  connect_bd_intf_net -intf_net CH0_DDR4_0_1 [get_bd_intf_pins axi_noc_mc_ddr4_1/CH0_DDR4_0] [get_bd_intf_pins CH0_DDR4_0_1]
  connect_bd_intf_net -intf_net sys_clk0_0   [get_bd_intf_pins axi_noc_mc_ddr4_0/sys_clk0]   [get_bd_intf_pins sys_clk0_0]
  connect_bd_intf_net -intf_net sys_clk0_1   [get_bd_intf_pins axi_noc_mc_ddr4_1/sys_clk0]   [get_bd_intf_pins sys_clk0_1]

  connect_bd_intf_net -intf_net axi_noc_mc_ddr4_0_S00_INI [get_bd_intf_pins axi_noc_mc_ddr4_0/S00_INI] [get_bd_intf_pins S00_INI_0]
  connect_bd_intf_net -intf_net axi_noc_mc_ddr4_0_S01_INI [get_bd_intf_pins axi_noc_mc_ddr4_0/S01_INI] [get_bd_intf_pins S01_INI_0]
  connect_bd_intf_net -intf_net axi_noc_mc_ddr4_1_S00_INI [get_bd_intf_pins axi_noc_mc_ddr4_1/S00_INI] [get_bd_intf_pins S00_INI_1]
  connect_bd_intf_net -intf_net axi_noc_mc_ddr4_1_S01_INI [get_bd_intf_pins axi_noc_mc_ddr4_1/S01_INI] [get_bd_intf_pins S01_INI_1]

  ####################################
  # Restore instance
  ####################################
  # Restore current instance
  current_bd_instance $oldCurInst
}

