# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
# Contains procedure to generate block designs that handle
# the shell, which includes :
# * cips
# * clock_reset
# * base_logic
# * AXI stream FIFO : communication from RPU in
# * interrupt
# ==============================================================================================

################################################################
# create_hier_cell_shell_wrapper
################################################################
# Hierarchical cell: shell_wrapper
proc create_hier_cell_shell_wrapper { parentCell nameHier } {
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
  set LP_AXI_FREQ   $_nsp_hpu::LP_AXI_FREQ
  set FREE_RUN_FREQ $_nsp_hpu::FREE_RUN_FREQ
  set PCIE_EXT_CFG_FREQ $_nsp_hpu::PCIE_EXT_CFG_FREQ
  set PCIE_REF_FREQ $_nsp_hpu::PCIE_REF_FREQ

  set IRQ_START_ID  $_nsp_hpu::IRQ_START_ID
  set IRQ_NB        $_nsp_hpu::IRQ_NB

  set AXIL_DATA_W   $_nsp_hpu::AXIL_DATA_W
  set AXIL_ADD_W    $_nsp_hpu::AXIL_ADD_W
  set AXIS_DATA_W   $_nsp_hpu::AXIS_DATA_W

  ####################################
  # Create pins
  ####################################
  # Pin associated to ports
  set gt_pcie_refclk_pin [ create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 gt_pcie_refclk ]

  set gt_pciea1_pin [ create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:gt_rtl:1.0 gt_pciea1 ]

  set axis_m_lpd_pin [ create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:axis_rtl:1.0 axis_m_lpd ]

  set axis_s_lpd_pin [ create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:axis_rtl:1.0 axis_s_lpd ]

  set axi_lpd_pin [ create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 axi_lpd ]

  set rtl_interrupt_pin [ create_bd_pin -dir I -from [expr $IRQ_NB - 1] -to 0 -type intr rtl_interrupt ]
  set clk_usr_1_0_pin [ create_bd_pin -dir O -type clk clk_usr_1_0 ]
  set clk_usr_0_0_pin [ create_bd_pin -dir O -type clk clk_usr_0_0 ]
  set resetn_usr_0_ic_0_pin [ create_bd_pin -dir O -from 0 -to 0 -type rst resetn_usr_0_ic_0 ]
  set resetn_usr_1_ic_0_pin [ create_bd_pin -dir O -from 0 -to 0 -type rst resetn_usr_1_ic_0 ]
  set pl0_ref_clk_0_pin [ create_bd_pin -dir O -type clk pl0_ref_clk_0 ]
  set pl0_resetn_0_pin [ create_bd_pin -dir O -type rst pl0_resetn_0 ]

  # Internal use pins
  set cpm_pcie_noc_0 [ create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 cpm_pcie_noc_0 ]
  set cpm_pcie_noc_1 [ create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 cpm_pcie_noc_1 ]
  set cpm_pcie_noc_axi0_clk [create_bd_pin -dir O -type clk cpm_pcie_noc_axi0_clk]
  set cpm_pcie_noc_axi1_clk [create_bd_pin -dir O -type clk cpm_pcie_noc_axi1_clk]

  set pmc_noc_axi_0 [ create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 pmc_noc_axi_0 ]
  set pmc_axi_noc_axi0_clk [create_bd_pin -dir O -type clk pmc_axi_noc_axi0_clk]

  set lpd_axi_noc_0 [ create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 lpd_axi_noc_0 ]
  set lpd_axi_noc_clk [create_bd_pin -dir O -type clk lpd_axi_noc_clk]

  set s_axi_pcie_mgmt_slr0 [ create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 s_axi_pcie_mgmt_slr0 ]

  ####################################
  # Create CIPS
  ####################################
  set cips [ create_bd_cell -type ip -vlnv xilinx.com:ip:versal_cips:3.4 cips ]

  set cips_cpm_config [list \
      CPM_PCIE0_MODES {None} \
      CPM_PCIE1_ACS_CAP_ON {0} \
      CPM_PCIE1_ARI_CAP_ENABLED {1} \
      CPM_PCIE1_CFG_EXT_IF {1} \
      CPM_PCIE1_CFG_VEND_ID {10ee} \
      CPM_PCIE1_COPY_PF0_QDMA_ENABLED {0} \
      CPM_PCIE1_EXT_PCIE_CFG_SPACE_ENABLED {Extended_Large} \
      CPM_PCIE1_FUNCTIONAL_MODE {QDMA} \
      CPM_PCIE1_MAX_LINK_SPEED {32.0_GT/s} \
      CPM_PCIE1_MODES {DMA} \
      CPM_PCIE1_MODE_SELECTION {Advanced} \
      CPM_PCIE1_MSI_X_OPTIONS {MSI-X_Internal} \
      CPM_PCIE1_PF0_AXIBAR2PCIE_BASEADDR_0 {0x0000008000000000} \
      CPM_PCIE1_PF0_AXIBAR2PCIE_BASEADDR_1 {0x0000008040000000} \
      CPM_PCIE1_PF0_AXIBAR2PCIE_BASEADDR_2 {0x0000008080000000} \
      CPM_PCIE1_PF0_AXIBAR2PCIE_BASEADDR_3 {0x00000080C0000000} \
      CPM_PCIE1_PF0_AXIBAR2PCIE_BASEADDR_4 {0x0000008100000000} \
      CPM_PCIE1_PF0_AXIBAR2PCIE_BASEADDR_5 {0x0000008140000000} \
      CPM_PCIE1_PF0_AXIBAR2PCIE_HIGHADDR_0 {0x000000803FFFFFFFF} \
      CPM_PCIE1_PF0_AXIBAR2PCIE_HIGHADDR_1 {0x000000807FFFFFFFF} \
      CPM_PCIE1_PF0_AXIBAR2PCIE_HIGHADDR_2 {0x00000080BFFFFFFFF} \
      CPM_PCIE1_PF0_AXIBAR2PCIE_HIGHADDR_3 {0x00000080FFFFFFFFF} \
      CPM_PCIE1_PF0_AXIBAR2PCIE_HIGHADDR_4 {0x000000813FFFFFFFF} \
      CPM_PCIE1_PF0_AXIBAR2PCIE_HIGHADDR_5 {0x000000817FFFFFFFF} \
      CPM_PCIE1_PF0_BAR0_QDMA_64BIT {1} \
      CPM_PCIE1_PF0_BAR0_QDMA_ENABLED {1} \
      CPM_PCIE1_PF0_BAR0_QDMA_PREFETCHABLE {1} \
      CPM_PCIE1_PF0_BAR0_QDMA_SCALE {Megabytes} \
      CPM_PCIE1_PF0_BAR0_QDMA_SIZE {256} \
      CPM_PCIE1_PF0_BAR0_QDMA_TYPE {AXI_Bridge_Master} \
      CPM_PCIE1_PF0_BAR2_QDMA_64BIT {0} \
      CPM_PCIE1_PF0_BAR2_QDMA_ENABLED {0} \
      CPM_PCIE1_PF0_BAR2_QDMA_PREFETCHABLE {0} \
      CPM_PCIE1_PF0_BAR2_QDMA_SCALE {Kilobytes} \
      CPM_PCIE1_PF0_BAR2_QDMA_SIZE {4} \
      CPM_PCIE1_PF0_BAR2_QDMA_TYPE {AXI_Bridge_Master} \
      CPM_PCIE1_PF0_BASE_CLASS_VALUE {12} \
      CPM_PCIE1_PF0_CFG_DEV_ID {50b4} \
      CPM_PCIE1_PF0_CFG_SUBSYS_ID {000e} \
      CPM_PCIE1_PF0_DEV_CAP_FUNCTION_LEVEL_RESET_CAPABLE {0} \
      CPM_PCIE1_PF0_MSIX_CAP_TABLE_OFFSET {40} \
      CPM_PCIE1_PF0_MSIX_CAP_TABLE_SIZE {1} \
      CPM_PCIE1_PF0_MSIX_ENABLED {0} \
      CPM_PCIE1_PF0_PCIEBAR2AXIBAR_QDMA_0 {0x0000020100000000} \
      CPM_PCIE1_PF0_SUB_CLASS_VALUE {00} \
      CPM_PCIE1_PF1_BAR0_QDMA_64BIT {1} \
      CPM_PCIE1_PF1_BAR0_QDMA_ENABLED {1} \
      CPM_PCIE1_PF1_BAR0_QDMA_PREFETCHABLE {1} \
      CPM_PCIE1_PF1_BAR0_QDMA_SCALE {Kilobytes} \
      CPM_PCIE1_PF1_BAR0_QDMA_SIZE {512} \
      CPM_PCIE1_PF1_BAR0_QDMA_TYPE {DMA} \
      CPM_PCIE1_PF1_BAR2_QDMA_64BIT {0} \
      CPM_PCIE1_PF1_BAR2_QDMA_ENABLED {0} \
      CPM_PCIE1_PF1_BAR2_QDMA_PREFETCHABLE {0} \
      CPM_PCIE1_PF1_BAR2_QDMA_SCALE {Kilobytes} \
      CPM_PCIE1_PF1_BAR2_QDMA_SIZE {4} \
      CPM_PCIE1_PF1_BAR2_QDMA_TYPE {AXI_Bridge_Master} \
      CPM_PCIE1_PF1_BASE_CLASS_VALUE {12} \
      CPM_PCIE1_PF1_CFG_DEV_ID {50b5} \
      CPM_PCIE1_PF1_CFG_SUBSYS_ID {000e} \
      CPM_PCIE1_PF1_CFG_SUBSYS_VEND_ID {10EE} \
      CPM_PCIE1_PF1_MSIX_CAP_TABLE_OFFSET {50000} \
      CPM_PCIE1_PF1_MSIX_CAP_TABLE_SIZE {8} \
      CPM_PCIE1_PF1_MSIX_ENABLED {1} \
      CPM_PCIE1_PF1_PCIEBAR2AXIBAR_QDMA_2 {0x0000020200000000} \
      CPM_PCIE1_PF1_SUB_CLASS_VALUE {00} \
      CPM_PCIE1_PL_LINK_CAP_MAX_LINK_WIDTH {X8} \
      CPM_PCIE1_TL_PF_ENABLE_REG {2} \
    ]

  set ps_irq_usage [list [list CH0 1] [list CH1 1]]
  for { set i $IRQ_START_ID}  {$i < [expr $IRQ_START_ID + $IRQ_NB]} {incr i} {
    lappend ps_irq_usage [list CH${i} 1]
  }
  for { set i [expr $IRQ_START_ID + $IRQ_NB]}  {$i < 16} {incr i} {
    lappend ps_irq_usage [list CH${i} 0]
  }
  set cips_ps_pmc_config [list \
      BOOT_MODE {Custom} \
      CLOCK_MODE {Custom} \
      DDR_MEMORY_MODE {Custom} \
      DESIGN_MODE {1} \
      DEVICE_INTEGRITY_MODE {Custom} \
      IO_CONFIG_MODE {Custom} \
      PCIE_APERTURES_DUAL_ENABLE {0} \
      PCIE_APERTURES_SINGLE_ENABLE {1} \
      PMC_BANK_1_IO_STANDARD {LVCMOS3.3} \
      PMC_CRP_OSPI_REF_CTRL_FREQMHZ {200} \
      PMC_CRP_PL0_REF_CTRL_FREQMHZ [expr int($LP_AXI_FREQ)] \
      PMC_CRP_PL1_REF_CTRL_FREQMHZ $FREE_RUN_FREQ \
      PMC_CRP_PL2_REF_CTRL_FREQMHZ [expr int($PCIE_EXT_CFG_FREQ)] \
      PMC_GLITCH_CONFIG {{DEPTH_SENSITIVITY 1} {MIN_PULSE_WIDTH 0.5} {TYPE CUSTOM} {VCC_PMC_VALUE 0.88}} \
      PMC_GLITCH_CONFIG_1 {{DEPTH_SENSITIVITY 1} {MIN_PULSE_WIDTH 0.5} {TYPE CUSTOM} {VCC_PMC_VALUE 0.88}} \
      PMC_GLITCH_CONFIG_2 {{DEPTH_SENSITIVITY 1} {MIN_PULSE_WIDTH 0.5} {TYPE CUSTOM} {VCC_PMC_VALUE 0.88}} \
      PMC_GPIO_EMIO_PERIPHERAL_ENABLE {0} \
      PMC_MIO11 {{AUX_IO 0} {DIRECTION in} {DRIVE_STRENGTH 8mA} {OUTPUT_DATA default} {PULL pullup} {SCHMITT 0} {SLEW slow} {USAGE GPIO}} \
      PMC_MIO12 {{AUX_IO 0} {DIRECTION out} {DRIVE_STRENGTH 8mA} {OUTPUT_DATA default} {PULL pullup} {SCHMITT 0} {SLEW slow} {USAGE GPIO}} \
      PMC_MIO13 {{AUX_IO 0} {DIRECTION inout} {DRIVE_STRENGTH 8mA} {OUTPUT_DATA default} {PULL pullup} {SCHMITT 0} {SLEW slow} {USAGE Reserved}} \
      PMC_MIO17 {{AUX_IO 0} {DIRECTION out} {DRIVE_STRENGTH 8mA} {OUTPUT_DATA default} {PULL pullup} {SCHMITT 0} {SLEW slow} {USAGE GPIO}} \
      PMC_MIO26 {{AUX_IO 0} {DIRECTION out} {DRIVE_STRENGTH 8mA} {OUTPUT_DATA default} {PULL pullup} {SCHMITT 0} {SLEW slow} {USAGE GPIO}} \
      PMC_MIO27 {{AUX_IO 0} {DIRECTION out} {DRIVE_STRENGTH 8mA} {OUTPUT_DATA default} {PULL pullup} {SCHMITT 0} {SLEW slow} {USAGE GPIO}} \
      PMC_MIO28 {{AUX_IO 0} {DIRECTION out} {DRIVE_STRENGTH 8mA} {OUTPUT_DATA default} {PULL pullup} {SCHMITT 0} {SLEW slow} {USAGE GPIO}} \
      PMC_MIO29 {{AUX_IO 0} {DIRECTION out} {DRIVE_STRENGTH 8mA} {OUTPUT_DATA default} {PULL pullup} {SCHMITT 0} {SLEW slow} {USAGE GPIO}} \
      PMC_MIO30 {{AUX_IO 0} {DIRECTION out} {DRIVE_STRENGTH 8mA} {OUTPUT_DATA default} {PULL pullup} {SCHMITT 0} {SLEW slow} {USAGE GPIO}} \
      PMC_MIO31 {{AUX_IO 0} {DIRECTION out} {DRIVE_STRENGTH 8mA} {OUTPUT_DATA default} {PULL pullup} {SCHMITT 0} {SLEW slow} {USAGE GPIO}} \
      PMC_MIO32 {{AUX_IO 0} {DIRECTION out} {DRIVE_STRENGTH 8mA} {OUTPUT_DATA default} {PULL pullup} {SCHMITT 0} {SLEW slow} {USAGE GPIO}} \
      PMC_MIO33 {{AUX_IO 0} {DIRECTION in} {DRIVE_STRENGTH 8mA} {OUTPUT_DATA default} {PULL pullup} {SCHMITT 0} {SLEW slow} {USAGE GPIO}} \
      PMC_MIO34 {{AUX_IO 0} {DIRECTION out} {DRIVE_STRENGTH 8mA} {OUTPUT_DATA default} {PULL pullup} {SCHMITT 0} {SLEW slow} {USAGE GPIO}} \
      PMC_MIO35 {{AUX_IO 0} {DIRECTION out} {DRIVE_STRENGTH 8mA} {OUTPUT_DATA default} {PULL pullup} {SCHMITT 0} {SLEW slow} {USAGE GPIO}} \
      PMC_MIO36 {{AUX_IO 0} {DIRECTION out} {DRIVE_STRENGTH 8mA} {OUTPUT_DATA default} {PULL pullup} {SCHMITT 0} {SLEW slow} {USAGE GPIO}} \
      PMC_MIO37 {{AUX_IO 0} {DIRECTION in} {DRIVE_STRENGTH 8mA} {OUTPUT_DATA default} {PULL pullup} {SCHMITT 0} {SLEW slow} {USAGE GPIO}} \
      PMC_MIO38 {{AUX_IO 0} {DIRECTION out} {DRIVE_STRENGTH 8mA} {OUTPUT_DATA default} {PULL pullup} {SCHMITT 0} {SLEW slow} {USAGE GPIO}} \
      PMC_MIO39 {{AUX_IO 0} {DIRECTION out} {DRIVE_STRENGTH 8mA} {OUTPUT_DATA default} {PULL pullup} {SCHMITT 0} {SLEW slow} {USAGE GPIO}} \
      PMC_MIO40 {{AUX_IO 0} {DIRECTION out} {DRIVE_STRENGTH 8mA} {OUTPUT_DATA default} {PULL pullup} {SCHMITT 0} {SLEW slow} {USAGE GPIO}} \
      PMC_MIO41 {{AUX_IO 0} {DIRECTION in} {DRIVE_STRENGTH 8mA} {OUTPUT_DATA default} {PULL pullup} {SCHMITT 0} {SLEW slow} {USAGE GPIO}} \
      PMC_MIO42 {{AUX_IO 0} {DIRECTION out} {DRIVE_STRENGTH 8mA} {OUTPUT_DATA default} {PULL pullup} {SCHMITT 0} {SLEW slow} {USAGE GPIO}} \
      PMC_MIO43 {{AUX_IO 0} {DIRECTION out} {DRIVE_STRENGTH 8mA} {OUTPUT_DATA default} {PULL pullup} {SCHMITT 0} {SLEW slow} {USAGE GPIO}} \
      PMC_MIO44 {{AUX_IO 0} {DIRECTION out} {DRIVE_STRENGTH 8mA} {OUTPUT_DATA default} {PULL pullup} {SCHMITT 0} {SLEW slow} {USAGE GPIO}} \
      PMC_MIO48 {{AUX_IO 0} {DIRECTION in} {DRIVE_STRENGTH 8mA} {OUTPUT_DATA default} {PULL pullup} {SCHMITT 0} {SLEW slow} {USAGE GPIO}} \
      PMC_MIO49 {{AUX_IO 0} {DIRECTION in} {DRIVE_STRENGTH 8mA} {OUTPUT_DATA default} {PULL pullup} {SCHMITT 0} {SLEW slow} {USAGE GPIO}} \
      PMC_MIO50 {{AUX_IO 0} {DIRECTION in} {DRIVE_STRENGTH 8mA} {OUTPUT_DATA default} {PULL pullup} {SCHMITT 0} {SLEW slow} {USAGE GPIO}} \
      PMC_MIO51 {{AUX_IO 0} {DIRECTION out} {DRIVE_STRENGTH 8mA} {OUTPUT_DATA default} {PULL pullup} {SCHMITT 0} {SLEW slow} {USAGE GPIO}} \
      PMC_MIO_EN_FOR_PL_PCIE {0} \
      PMC_OSPI_PERIPHERAL {{ENABLE 1} {IO {PMC_MIO 0 .. 11}} {MODE Single}} \
      PMC_REF_CLK_FREQMHZ {33.333333} \
      PMC_SD0_DATA_TRANSFER_MODE {8Bit} \
      PMC_SD0_PERIPHERAL {{CLK_100_SDR_OTAP_DLY 0x00} {CLK_200_SDR_OTAP_DLY 0x2} {CLK_50_DDR_ITAP_DLY 0x1E} {CLK_50_DDR_OTAP_DLY 0x5} {CLK_50_SDR_ITAP_DLY 0x2C} {CLK_50_SDR_OTAP_DLY 0x5} {ENABLE 1} {IO\
{PMC_MIO 13 .. 25}}} \
      PMC_SD0_SLOT_TYPE {eMMC} \
      PMC_USE_PMC_NOC_AXI0 {1} \
      PS_BANK_2_IO_STANDARD {LVCMOS3.3} \
      PS_BOARD_INTERFACE {Custom} \
      PS_CRL_CPM_TOPSW_REF_CTRL_FREQMHZ {1000} \
      PS_GEN_IPI0_ENABLE {0} \
      PS_GEN_IPI1_ENABLE {0} \
      PS_GEN_IPI2_ENABLE {0} \
      PS_GEN_IPI3_ENABLE {1} \
      PS_GEN_IPI3_MASTER {R5_0} \
      PS_GEN_IPI4_ENABLE {1} \
      PS_GEN_IPI4_MASTER {R5_0} \
      PS_GEN_IPI5_ENABLE {1} \
      PS_GEN_IPI5_MASTER {R5_1} \
      PS_GEN_IPI6_ENABLE {1} \
      PS_GEN_IPI6_MASTER {R5_1} \
      PS_GPIO_EMIO_PERIPHERAL_ENABLE {0} \
      PS_I2C0_PERIPHERAL {{ENABLE 1} {IO {PS_MIO 2 .. 3}}} \
      PS_I2C1_PERIPHERAL {{ENABLE 1} {IO {PS_MIO 0 .. 1}}} \
      PS_IRQ_USAGE $ps_irq_usage \
      PS_KAT_ENABLE {0} \
      PS_KAT_ENABLE_1 {0} \
      PS_KAT_ENABLE_2 {0} \
      PS_MIO10 {{AUX_IO 0} {DIRECTION in} {DRIVE_STRENGTH 8mA} {OUTPUT_DATA default} {PULL pullup} {SCHMITT 0} {SLEW slow} {USAGE GPIO}} \
      PS_MIO11 {{AUX_IO 0} {DIRECTION in} {DRIVE_STRENGTH 8mA} {OUTPUT_DATA default} {PULL pullup} {SCHMITT 0} {SLEW slow} {USAGE GPIO}} \
      PS_MIO12 {{AUX_IO 0} {DIRECTION inout} {DRIVE_STRENGTH 8mA} {OUTPUT_DATA default} {PULL pullup} {SCHMITT 0} {SLEW slow} {USAGE Reserved}} \
      PS_MIO13 {{AUX_IO 0} {DIRECTION out} {DRIVE_STRENGTH 8mA} {OUTPUT_DATA default} {PULL pullup} {SCHMITT 0} {SLEW slow} {USAGE GPIO}} \
      PS_MIO14 {{AUX_IO 0} {DIRECTION in} {DRIVE_STRENGTH 8mA} {OUTPUT_DATA default} {PULL pullup} {SCHMITT 0} {SLEW slow} {USAGE GPIO}} \
      PS_MIO18 {{AUX_IO 0} {DIRECTION out} {DRIVE_STRENGTH 8mA} {OUTPUT_DATA default} {PULL pullup} {SCHMITT 0} {SLEW slow} {USAGE GPIO}} \
      PS_MIO19 {{AUX_IO 0} {DIRECTION out} {DRIVE_STRENGTH 8mA} {OUTPUT_DATA default} {PULL pullup} {SCHMITT 0} {SLEW slow} {USAGE GPIO}} \
      PS_MIO22 {{AUX_IO 0} {DIRECTION out} {DRIVE_STRENGTH 8mA} {OUTPUT_DATA default} {PULL pullup} {SCHMITT 0} {SLEW slow} {USAGE GPIO}} \
      PS_MIO23 {{AUX_IO 0} {DIRECTION out} {DRIVE_STRENGTH 8mA} {OUTPUT_DATA default} {PULL pullup} {SCHMITT 0} {SLEW slow} {USAGE GPIO}} \
      PS_MIO24 {{AUX_IO 0} {DIRECTION out} {DRIVE_STRENGTH 8mA} {OUTPUT_DATA default} {PULL pullup} {SCHMITT 0} {SLEW slow} {USAGE GPIO}} \
      PS_MIO25 {{AUX_IO 0} {DIRECTION in} {DRIVE_STRENGTH 8mA} {OUTPUT_DATA default} {PULL pullup} {SCHMITT 0} {SLEW slow} {USAGE GPIO}} \
      PS_MIO4 {{AUX_IO 0} {DIRECTION out} {DRIVE_STRENGTH 8mA} {OUTPUT_DATA default} {PULL pullup} {SCHMITT 0} {SLEW slow} {USAGE GPIO}} \
      PS_MIO5 {{AUX_IO 0} {DIRECTION in} {DRIVE_STRENGTH 8mA} {OUTPUT_DATA default} {PULL pullup} {SCHMITT 0} {SLEW slow} {USAGE GPIO}} \
      PS_MIO6 {{AUX_IO 0} {DIRECTION out} {DRIVE_STRENGTH 8mA} {OUTPUT_DATA default} {PULL pullup} {SCHMITT 0} {SLEW slow} {USAGE GPIO}} \
      PS_MIO7 {{AUX_IO 0} {DIRECTION out} {DRIVE_STRENGTH 8mA} {OUTPUT_DATA default} {PULL pullup} {SCHMITT 0} {SLEW slow} {USAGE GPIO}} \
      PS_MIO8 {{AUX_IO 0} {DIRECTION in} {DRIVE_STRENGTH 8mA} {OUTPUT_DATA default} {PULL pullup} {SCHMITT 0} {SLEW slow} {USAGE Reserved}} \
      PS_MIO9 {{AUX_IO 0} {DIRECTION out} {DRIVE_STRENGTH 8mA} {OUTPUT_DATA default} {PULL pullup} {SCHMITT 1} {SLEW slow} {USAGE Reserved}} \
      PS_M_AXI_LPD_DATA_WIDTH $AXIL_ADD_W \
      PS_NUM_FABRIC_RESETS {1} \
      PS_PCIE1_PERIPHERAL_ENABLE {0} \
      PS_PCIE2_PERIPHERAL_ENABLE {1} \
      PS_PCIE_EP_RESET1_IO {PMC_MIO 24} \
      PS_PCIE_EP_RESET2_IO {PMC_MIO 25} \
      PS_PCIE_RESET {ENABLE 1} \
      PS_PL_CONNECTIVITY_MODE {Custom} \
      PS_SPI0 {{GRP_SS0_ENABLE 1} {GRP_SS0_IO {PS_MIO 15}} {GRP_SS1_ENABLE 0} {GRP_SS1_IO {PMC_MIO 14}} {GRP_SS2_ENABLE 0} {GRP_SS2_IO {PMC_MIO 13}} {PERIPHERAL_ENABLE 1} {PERIPHERAL_IO {PS_MIO 12 .. 17}}}\
\
      PS_SPI1 {{GRP_SS0_ENABLE 0} {GRP_SS0_IO {PS_MIO 9}} {GRP_SS1_ENABLE 0} {GRP_SS1_IO {PS_MIO 8}} {GRP_SS2_ENABLE 0} {GRP_SS2_IO {PS_MIO 7}} {PERIPHERAL_ENABLE 0} {PERIPHERAL_IO {PS_MIO 6 .. 11}}} \
      PS_TTC0_PERIPHERAL_ENABLE {1} \
      PS_TTC1_PERIPHERAL_ENABLE {1} \
      PS_TTC2_PERIPHERAL_ENABLE {1} \
      PS_TTC3_PERIPHERAL_ENABLE {1} \
      PS_UART0_PERIPHERAL {{ENABLE 1} {IO {PS_MIO 8 .. 9}}} \
      PS_UART1_PERIPHERAL {{ENABLE 1} {IO {PS_MIO 20 .. 21}}} \
      PS_USE_FPD_CCI_NOC {0} \
      PS_USE_M_AXI_FPD {0} \
      PS_USE_M_AXI_LPD {1} \
      PS_USE_NOC_LPD_AXI0 {1} \
      PS_USE_PMCPL_CLK0 {1} \
      PS_USE_PMCPL_CLK1 {1} \
      PS_USE_PMCPL_CLK2 {1} \
      PS_USE_S_AXI_LPD {0} \
      SMON_ALARMS {Set_Alarms_On} \
      SMON_ENABLE_TEMP_AVERAGING {0} \
      SMON_MEAS100 {{ALARM_ENABLE 1} {ALARM_LOWER 0.00} {ALARM_UPPER 4.00} {AVERAGE_EN 0} {ENABLE 1} {MODE {4 V unipolar}} {NAME VCCO_500} {SUPPLY_NUM 9}} \
      SMON_MEAS101 {{ALARM_ENABLE 1} {ALARM_LOWER 0.00} {ALARM_UPPER 4.00} {AVERAGE_EN 0} {ENABLE 1} {MODE {4 V unipolar}} {NAME VCCO_501} {SUPPLY_NUM 10}} \
      SMON_MEAS102 {{ALARM_ENABLE 1} {ALARM_LOWER 0.00} {ALARM_UPPER 4.00} {AVERAGE_EN 0} {ENABLE 1} {MODE {4 V unipolar}} {NAME VCCO_502} {SUPPLY_NUM 11}} \
      SMON_MEAS103 {{ALARM_ENABLE 1} {ALARM_LOWER 0.00} {ALARM_UPPER 4.00} {AVERAGE_EN 0} {ENABLE 1} {MODE {4 V unipolar}} {NAME VCCO_503} {SUPPLY_NUM 12}} \
      SMON_MEAS104 {{ALARM_ENABLE 1} {ALARM_LOWER 0.00} {ALARM_UPPER 2.00} {AVERAGE_EN 0} {ENABLE 1} {MODE {2 V unipolar}} {NAME VCCO_700} {SUPPLY_NUM 13}} \
      SMON_MEAS105 {{ALARM_ENABLE 1} {ALARM_LOWER 0.00} {ALARM_UPPER 2.00} {AVERAGE_EN 0} {ENABLE 1} {MODE {2 V unipolar}} {NAME VCCO_701} {SUPPLY_NUM 14}} \
      SMON_MEAS106 {{ALARM_ENABLE 1} {ALARM_LOWER 0.00} {ALARM_UPPER 2.00} {AVERAGE_EN 0} {ENABLE 1} {MODE {2 V unipolar}} {NAME VCCO_702} {SUPPLY_NUM 15}} \
      SMON_MEAS118 {{ALARM_ENABLE 1} {ALARM_LOWER 0.00} {ALARM_UPPER 2.00} {AVERAGE_EN 0} {ENABLE 1} {MODE {2 V unipolar}} {NAME VCC_PMC} {SUPPLY_NUM 0}} \
      SMON_MEAS119 {{ALARM_ENABLE 1} {ALARM_LOWER 0.00} {ALARM_UPPER 2.00} {AVERAGE_EN 0} {ENABLE 1} {MODE {2 V unipolar}} {NAME VCC_PSFP} {SUPPLY_NUM 1}} \
      SMON_MEAS120 {{ALARM_ENABLE 1} {ALARM_LOWER 0.00} {ALARM_UPPER 2.00} {AVERAGE_EN 0} {ENABLE 1} {MODE {2 V unipolar}} {NAME VCC_PSLP} {SUPPLY_NUM 2}} \
      SMON_MEAS121 {{ALARM_ENABLE 1} {ALARM_LOWER 0.00} {ALARM_UPPER 2.00} {AVERAGE_EN 0} {ENABLE 1} {MODE {2 V unipolar}} {NAME VCC_RAM} {SUPPLY_NUM 3}} \
      SMON_MEAS122 {{ALARM_ENABLE 1} {ALARM_LOWER 0.00} {ALARM_UPPER 2.00} {AVERAGE_EN 0} {ENABLE 1} {MODE {2 V unipolar}} {NAME VCC_SOC} {SUPPLY_NUM 4}} \
      SMON_MEAS47 {{ALARM_ENABLE 1} {ALARM_LOWER 0.00} {ALARM_UPPER 2.00} {AVERAGE_EN 0} {ENABLE 1} {MODE {2 V unipolar}} {NAME GTYP_AVCCAUX_104} {SUPPLY_NUM 20}} \
      SMON_MEAS48 {{ALARM_ENABLE 1} {ALARM_LOWER 0.00} {ALARM_UPPER 2.00} {AVERAGE_EN 0} {ENABLE 1} {MODE {2 V unipolar}} {NAME GTYP_AVCCAUX_105} {SUPPLY_NUM 21}} \
      SMON_MEAS64 {{ALARM_ENABLE 1} {ALARM_LOWER 0.00} {ALARM_UPPER 2.00} {AVERAGE_EN 0} {ENABLE 1} {MODE {2 V unipolar}} {NAME GTYP_AVCC_104} {SUPPLY_NUM 18}} \
      SMON_MEAS65 {{ALARM_ENABLE 1} {ALARM_LOWER 0.00} {ALARM_UPPER 2.00} {AVERAGE_EN 0} {ENABLE 1} {MODE {2 V unipolar}} {NAME GTYP_AVCC_105} {SUPPLY_NUM 19}} \
      SMON_MEAS81 {{ALARM_ENABLE 1} {ALARM_LOWER 0.00} {ALARM_UPPER 2.00} {AVERAGE_EN 0} {ENABLE 1} {MODE {2 V unipolar}} {NAME GTYP_AVTT_104} {SUPPLY_NUM 22}} \
      SMON_MEAS82 {{ALARM_ENABLE 1} {ALARM_LOWER 0.00} {ALARM_UPPER 2.00} {AVERAGE_EN 0} {ENABLE 1} {MODE {2 V unipolar}} {NAME GTYP_AVTT_105} {SUPPLY_NUM 23}} \
      SMON_MEAS96 {{ALARM_ENABLE 1} {ALARM_LOWER 0.00} {ALARM_UPPER 2.00} {AVERAGE_EN 0} {ENABLE 1} {MODE {2 V unipolar}} {NAME VCCAUX} {SUPPLY_NUM 6}} \
      SMON_MEAS97 {{ALARM_ENABLE 1} {ALARM_LOWER 0.00} {ALARM_UPPER 2.00} {AVERAGE_EN 0} {ENABLE 1} {MODE {2 V unipolar}} {NAME VCCAUX_PMC} {SUPPLY_NUM 7}} \
      SMON_MEAS98 {{ALARM_ENABLE 1} {ALARM_LOWER 0.00} {ALARM_UPPER 2.00} {AVERAGE_EN 0} {ENABLE 1} {MODE {2 V unipolar}} {NAME VCCAUX_SMON} {SUPPLY_NUM 8}} \
      SMON_MEAS99 {{ALARM_ENABLE 1} {ALARM_LOWER 0.00} {ALARM_UPPER 2.00} {AVERAGE_EN 0} {ENABLE 1} {MODE {2 V unipolar}} {NAME VCCINT} {SUPPLY_NUM 5}} \
      SMON_TEMP_AVERAGING_SAMPLES {0} \
      SMON_VOLTAGE_AVERAGING_SAMPLES {8} \
    ]

  set_property -dict [list \
    CONFIG.CPM_CONFIG $cips_cpm_config \
    CONFIG.PS_PMC_CONFIG $cips_ps_pmc_config \
    CONFIG.PS_PMC_CONFIG_APPLIED {1} \
  ] $cips

  ####################################
  # Create Base Logic
  ####################################
  create_hier_cell_base_logic [current_bd_instance .] base_logic

  ####################################
  # Create Clock reset
  ####################################
  create_hier_cell_clock_reset [current_bd_instance .] clock_reset

  ####################################
  # Create AXI4 to AXI stream (RPU)
  ####################################
  set axi_to_axis [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_fifo_mm_s:4.3 axi_to_axis ]
  set_property -dict [list \
    CONFIG.C_AXIS_TUSER_WIDTH {4} \
    CONFIG.C_DATA_INTERFACE_TYPE {0} \
    CONFIG.C_S_AXI4_DATA_WIDTH $AXIS_DATA_W \
    CONFIG.C_USE_RX_DATA {1} \
    CONFIG.C_USE_TX_CTRL {0} \
    CONFIG.C_USE_TX_CUT_THROUGH {0} \
    CONFIG.C_USE_TX_DATA {1} \
  ] $axi_to_axis

  ####################################
  # Interrrupts
  ####################################
  for { set i 0}  {$i < $IRQ_NB} {incr i} {
    set irq_id [expr $IRQ_START_ID + $i]
    set xlslice_tmp [create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 xlslice_${irq_id}]
    set_property -dict [list \
      CONFIG.DIN_FROM $i \
      CONFIG.DIN_TO $i \
      CONFIG.DIN_WIDTH $IRQ_NB \
    ] $xlslice_tmp
  }

  ####################################
  # Connection
  ####################################
  # Connect internal pins
  connect_bd_intf_net -intf_net axi_to_axis_AXI_STR_TXD [get_bd_intf_pins axis_m_lpd] [get_bd_intf_pins axi_to_axis/AXI_STR_TXD]
  connect_bd_intf_net -intf_net axis_s_lpd_1 [get_bd_intf_pins axis_s_lpd] [get_bd_intf_pins axi_to_axis/AXI_STR_RXD]
  connect_bd_intf_net -intf_net base_logic_M01_AXI_0 [get_bd_intf_pins axi_lpd] [get_bd_intf_pins base_logic/M01_AXI_0]
  connect_bd_intf_net -intf_net base_logic_M02_AXI [get_bd_intf_pins axi_to_axis/S_AXI] [get_bd_intf_pins base_logic/M02_AXI]
  connect_bd_intf_net -intf_net base_logic_m_axi_pcie_mgmt_pdi_reset [get_bd_intf_pins base_logic/m_axi_pcie_mgmt_pdi_reset] [get_bd_intf_pins clock_reset/s_axi_pcie_mgmt_pdi_reset]
  connect_bd_intf_net -intf_net cips_M_AXI_LPD [get_bd_intf_pins cips/M_AXI_LPD] [get_bd_intf_pins base_logic/s_axi_rpu]
  connect_bd_intf_net -intf_net cips_PCIE1_GT [get_bd_intf_pins cips/PCIE1_GT] [get_bd_intf_pins gt_pciea1]
  connect_bd_intf_net -intf_net cips_pcie1_cfg_ext [get_bd_intf_pins cips/pcie1_cfg_ext] [get_bd_intf_pins base_logic/pcie_cfg_ext]
  connect_bd_intf_net -intf_net gt_pcie_refclk_1 [get_bd_intf_pins gt_pcie_refclk] [get_bd_intf_pins cips/gt_refclk1]

  connect_bd_net -net clock_reset_clk_usr_0 [get_bd_pins clock_reset/clk_usr_0] [get_bd_pins clk_usr_0_0]
  connect_bd_net -net clock_reset_clk_usr_1 [get_bd_pins clock_reset/clk_usr_1] [get_bd_pins clk_usr_1_0]
  connect_bd_net -net clock_reset_resetn_usr_0_ic [get_bd_pins clock_reset/resetn_usr_0_ic] [get_bd_pins resetn_usr_0_ic_0]
  connect_bd_net -net clock_reset_resetn_usr_1_ic [get_bd_pins clock_reset/resetn_usr_1_ic] [get_bd_pins resetn_usr_1_ic_0]

  connect_bd_net -net base_logic_irq_gcq_m2r [get_bd_pins base_logic/irq_gcq_m2r] [get_bd_pins cips/pl_ps_irq0]
  connect_bd_net -net cips_dma1_axi_aresetn [get_bd_pins cips/dma1_axi_aresetn] [get_bd_pins clock_reset/dma_axi_aresetn]
  connect_bd_net -net cips_pl0_ref_clk [get_bd_pins cips/pl0_ref_clk] [get_bd_pins pl0_ref_clk_0] [get_bd_pins cips/m_axi_lpd_aclk] [get_bd_pins base_logic/clk_pl] [get_bd_pins clock_reset/clk_pl]
  connect_bd_net -net cips_pl0_resetn  [get_bd_pins cips/pl0_resetn] [get_bd_pins pl0_resetn_0] [get_bd_pins clock_reset/resetn_pl_axi]
  connect_bd_net -net cips_pl1_ref_clk [get_bd_pins cips/pl1_ref_clk] [get_bd_pins clock_reset/clk_freerun]
  connect_bd_net -net cips_pl2_ref_clk [get_bd_pins cips/pl2_ref_clk] [get_bd_pins cips/dma1_intrfc_clk] [get_bd_pins base_logic/clk_pcie] [get_bd_pins clock_reset/clk_pcie]

  connect_bd_net -net clock_reset_clk_usr_0 [get_bd_pins clock_reset/clk_usr_0] [get_bd_pins axi_to_axis/s_axi_aclk] [get_bd_pins base_logic/hpu_clk]
  connect_bd_net -net clock_reset_resetn_usr_0_ic [get_bd_pins clock_reset/resetn_usr_0_ic] [get_bd_pins axi_to_axis/s_axi_aresetn]

  connect_bd_net -net clock_reset_resetn_pcie_ic [get_bd_pins clock_reset/resetn_pcie_ic] [get_bd_pins cips/dma1_intrfc_resetn]
  connect_bd_net -net clock_reset_resetn_pcie_periph [get_bd_pins clock_reset/resetn_pcie_periph] [get_bd_pins base_logic/resetn_pcie_periph]
  connect_bd_net -net clock_reset_resetn_pl_ic [get_bd_pins clock_reset/resetn_pl_ic] [get_bd_pins base_logic/resetn_pl_ic]
  connect_bd_net -net clock_reset_resetn_pl_periph [get_bd_pins clock_reset/resetn_pl_periph] [get_bd_pins base_logic/resetn_pl_periph]

  for { set i $IRQ_START_ID}  {$i < [expr $IRQ_START_ID + $IRQ_NB]} {incr i} {
    connect_bd_net [get_bd_pins rtl_interrupt] [get_bd_pins xlslice_${i}/Din]
    connect_bd_net -net xlslice_${i}_Dout [get_bd_pins xlslice_${i}/Dout] [get_bd_pins cips/pl_ps_irq${i}]
  }

  connect_bd_intf_net -intf_net cpm_pcie_noc_0 [get_bd_intf_pins cpm_pcie_noc_0] [get_bd_intf_pins cips/CPM_PCIE_NOC_0]
  connect_bd_intf_net -intf_net cpm_pcie_noc_1 [get_bd_intf_pins cpm_pcie_noc_1] [get_bd_intf_pins cips/CPM_PCIE_NOC_1]
  connect_bd_intf_net -intf_net pmc_noc_axi_0  [get_bd_intf_pins pmc_noc_axi_0]  [get_bd_intf_pins cips/PMC_NOC_AXI_0]
  connect_bd_intf_net -intf_net lpd_axi_noc_0  [get_bd_intf_pins lpd_axi_noc_0]  [get_bd_intf_pins cips/LPD_AXI_NOC_0]

  connect_bd_net -net cpm_pcie_noc_axi0_clk [get_bd_pins cpm_pcie_noc_axi0_clk] [get_bd_pins cips/cpm_pcie_noc_axi0_clk]
  connect_bd_net -net cpm_pcie_noc_axi1_clk [get_bd_pins cpm_pcie_noc_axi1_clk] [get_bd_pins cips/cpm_pcie_noc_axi1_clk]
  connect_bd_net -net pmc_axi_noc_axi0_clk  [get_bd_pins pmc_axi_noc_axi0_clk]  [get_bd_pins cips/pmc_axi_noc_axi0_clk]
  connect_bd_net -net lpd_axi_noc_clk       [get_bd_pins lpd_axi_noc_clk]       [get_bd_pins cips/lpd_axi_noc_clk]

  connect_bd_intf_net -intf_net s_axi_pcie_mgmt_slr0 [get_bd_intf_pins s_axi_pcie_mgmt_slr0] [get_bd_intf_pins base_logic/s_axi_pcie_mgmt_slr0]

  ####################################
  # Restore instance
  ####################################
  # Restore current instance
  current_bd_instance $oldCurInst
}
