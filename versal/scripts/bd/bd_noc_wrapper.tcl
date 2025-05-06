# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ==============================================================================================

################################################################
# create_hier_cell_noc_wrapper
################################################################
# Hierarchical cell: shell_wrapper
proc create_hier_cell_noc_wrapper { parentCell nameHier ntt_psi } {
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
  set USER_0_FREQ $_nsp_hpu::USER_0_FREQ
  set HBM_REF_FREQ $_nsp_hpu::HBM_REF_FREQ

  set AXI_PCIE_NB $_nsp_hpu::AXI_PCIE_NB

  set AXIL_DATA_W $_nsp_hpu::AXIL_DATA_W
  set AXI4_ADD_W $_nsp_hpu::AXI4_ADD_W
  set AXIS_DATA_W $_nsp_hpu::AXIS_DATA_W
  set AXIS_NOC_DATA_W $_nsp_hpu::AXIS_NOC_DATA_W

  set AXIS_NB $_nsp_hpu::AXIS_NB
  set KSK_AXI_NB $_nsp_hpu::KSK_AXI_NB
  set BSK_AXI_NB $_nsp_hpu::BSK_AXI_NB
  set CT_AXI_NB $_nsp_hpu::CT_AXI_NB
  set GLWE_AXI_NB $_nsp_hpu::GLWE_AXI_NB
  set TRC_AXI_NB $_nsp_hpu::TRC_AXI_NB

  # RPU <-> DDR
  set RPU_DDR_RD_BW $_nsp_hpu::RPU_DDR_RD_BW
  set RPU_DDR_WR_BW $_nsp_hpu::RPU_DDR_WR_BW
  set RPU_DDR_RD_BURST_AVG $_nsp_hpu::RPU_DDR_RD_BURST_AVG
  set RPU_DDR_WR_BURST_AVG $_nsp_hpu::RPU_DDR_WR_BURST_AVG

  # RPU <-> AXIL
  set RPU_AXIL_RD_BW $_nsp_hpu::RPU_AXIL_RD_BW
  set RPU_AXIL_WR_BW $_nsp_hpu::RPU_AXIL_WR_BW
  set RPU_AXIL_RD_BURST_AVG $_nsp_hpu::RPU_AXIL_RD_BURST_AVG
  set RPU_AXIL_WR_BURST_AVG $_nsp_hpu::RPU_AXIL_WR_BURST_AVG

  # RPU <-> ISC
  set RPU_ISC_WR_BW $_nsp_hpu::RPU_ISC_WR_BW
  set RPU_ISC_WR_BURST_AVG $_nsp_hpu::RPU_ISC_WR_BURST_AVG

  # PCIE <-> HBM DMA
  set PCIE_HBM_DMA_RD_BW $_nsp_hpu::PCIE_HBM_DMA_RD_BW
  set PCIE_HBM_DMA_WR_BW $_nsp_hpu::PCIE_HBM_DMA_WR_BW
  set PCIE_HBM_DMA_RD_BURST_AVG $_nsp_hpu::PCIE_HBM_DMA_RD_BURST_AVG
  set PCIE_HBM_DMA_WR_BURST_AVG $_nsp_hpu::PCIE_HBM_DMA_WR_BURST_AVG

  # PCIE <-> AXIL
  set PCIE_AXIL_RD_BW $_nsp_hpu::PCIE_AXIL_RD_BW
  set PCIE_AXIL_WR_BW $_nsp_hpu::PCIE_AXIL_WR_BW
  set PCIE_AXIL_RD_BURST_AVG $_nsp_hpu::PCIE_AXIL_RD_BURST_AVG
  set PCIE_AXIL_WR_BURST_AVG $_nsp_hpu::PCIE_AXIL_WR_BURST_AVG

  # PCIE <-> DDR
  set PCIE_DDR_DMA_RD_BW $_nsp_hpu::PCIE_DDR_DMA_RD_BW
  set PCIE_DDR_DMA_WR_BW $_nsp_hpu::PCIE_DDR_DMA_WR_BW
  set PCIE_DDR_DMA_RD_BURST_AVG $_nsp_hpu::PCIE_DDR_DMA_RD_BURST_AVG
  set PCIE_DDR_DMA_WR_BURST_AVG $_nsp_hpu::PCIE_DDR_DMA_WR_BURST_AVG

  # PMC <-> DDR
  set PMC_DDR_RD_BW $_nsp_hpu::PMC_DDR_RD_BW
  set PMC_DDR_WR_BW $_nsp_hpu::PMC_DDR_WR_BW
  set PMC_DDR_RD_BURST_AVG $_nsp_hpu::PMC_DDR_RD_BURST_AVG
  set PMC_DDR_WR_BURST_AVG $_nsp_hpu::PMC_DDR_WR_BURST_AVG

  # Key <-> HBM
  set HPU_BSK_HBM_RD_BW $_nsp_hpu::HPU_BSK_HBM_RD_BW
  set HPU_BSK_HBM_WR_BW $_nsp_hpu::HPU_BSK_HBM_WR_BW
  set HPU_BSK_HBM_RD_BURST_AVG $_nsp_hpu::HPU_BSK_HBM_RD_BURST_AVG
  set HPU_BSK_HBM_WR_BURST_AVG $_nsp_hpu::HPU_BSK_HBM_WR_BURST_AVG
  set HPU_BSK_HBM_BURST_MAX $_nsp_hpu::HPU_BSK_HBM_BURST_MAX
  set HPU_BSK_HBM_DATA_W $_nsp_hpu::HPU_BSK_HBM_DATA_W

  set HPU_KSK_HBM_RD_BW $_nsp_hpu::HPU_KSK_HBM_RD_BW
  set HPU_KSK_HBM_WR_BW $_nsp_hpu::HPU_KSK_HBM_WR_BW
  set HPU_KSK_HBM_RD_BURST_AVG $_nsp_hpu::HPU_KSK_HBM_RD_BURST_AVG
  set HPU_KSK_HBM_WR_BURST_AVG $_nsp_hpu::HPU_KSK_HBM_WR_BURST_AVG
  set HPU_KSK_HBM_BURST_MAX $_nsp_hpu::HPU_KSK_HBM_BURST_MAX
  set HPU_KSK_HBM_DATA_W $_nsp_hpu::HPU_KSK_HBM_DATA_W

  # CT <-> HBM
  set HPU_CT_HBM_RD_BW $_nsp_hpu::HPU_CT_HBM_RD_BW
  set HPU_CT_HBM_WR_BW $_nsp_hpu::HPU_CT_HBM_WR_BW
  set HPU_CT_HBM_RD_BURST_AVG $_nsp_hpu::HPU_CT_HBM_RD_BURST_AVG
  set HPU_CT_HBM_WR_BURST_AVG $_nsp_hpu::HPU_CT_HBM_WR_BURST_AVG
  set HPU_CT_HBM_BURST_MAX $_nsp_hpu::HPU_CT_HBM_BURST_MAX
  set HPU_CT_HBM_DATA_W $_nsp_hpu::HPU_CT_HBM_DATA_W

  # GLWE <-> HBM
  set HPU_GLWE_HBM_RD_BW $_nsp_hpu::HPU_GLWE_HBM_RD_BW
  set HPU_GLWE_HBM_WR_BW $_nsp_hpu::HPU_GLWE_HBM_WR_BW
  set HPU_GLWE_HBM_RD_BURST_AVG $_nsp_hpu::HPU_GLWE_HBM_RD_BURST_AVG
  set HPU_GLWE_HBM_WR_BURST_AVG $_nsp_hpu::HPU_GLWE_HBM_WR_BURST_AVG
  set HPU_GLWE_HBM_BURST_MAX $_nsp_hpu::HPU_GLWE_HBM_BURST_MAX
  set HPU_GLWE_HBM_DATA_W $_nsp_hpu::HPU_GLWE_HBM_DATA_W

  # TRC <-> HBM
  set HPU_TRC_HBM_RD_BW $_nsp_hpu::HPU_TRC_HBM_RD_BW
  set HPU_TRC_HBM_WR_BW $_nsp_hpu::HPU_TRC_HBM_WR_BW
  set HPU_TRC_HBM_RD_BURST_AVG $_nsp_hpu::HPU_TRC_HBM_RD_BURST_AVG
  set HPU_TRC_HBM_WR_BURST_AVG $_nsp_hpu::HPU_TRC_HBM_WR_BURST_AVG
  set HPU_TRC_HBM_BURST_MAX $_nsp_hpu::HPU_TRC_HBM_BURST_MAX
  set HPU_TRC_HBM_DATA_W $_nsp_hpu::HPU_TRC_HBM_DATA_W

  set HNMU_AXI_NB [expr $KSK_AXI_NB + $CT_AXI_NB + $GLWE_AXI_NB + $TRC_AXI_NB]
  # 4 additional inputs for 2xCPM, 1xPMC, 1xRPU_DDR
  set NMU_AXI_NB [expr $BSK_AXI_NB + 4]

  # AXI LPD <-> regfile
  set REGIF_CLK_NB $_nsp_hpu::REGIF_CLK_NB
  set LPD_AXI_NB $_nsp_hpu::LPD_AXI_NB
  set REGIF_NB $_nsp_hpu::REGIF_NB

  # set TOTAL_AXI_NB [expr $HNMU_AXI_NB + $NMU_AXI_NB + $LPD_AXI_NB]

  ####################################
  # Create pins
  ####################################
  puts ">>>>>>>> Create Pin >>>>>>>>>"
  # Create pins connected to ports
  set hbm_ref_clk_0 [ create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 hbm_ref_clk_0 ]
  set hbm_ref_clk_1 [ create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 hbm_ref_clk_1 ]

  for { set i 0}  {$i < $TRC_AXI_NB} {incr i} {
    create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 TRC_AXI_${i}
  }
  for { set i 0}  {$i < $CT_AXI_NB} {incr i} {
    create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 CT_AXI_${i}
  }
  for { set i 0}  {$i < $GLWE_AXI_NB} {incr i} {
    create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 GLWE_AXI_${i}
  }
  for { set i 0}  {$i < $BSK_AXI_NB} {incr i} {
    create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 BSK_AXI_${i}
  }
  for { set i 0}  {$i < $KSK_AXI_NB} {incr i} {
    create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 KSK_AXI_${i}
  }

  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 S_REGIF_AXI_0

  # DDR noc
  set CH0_DDR4_0_0 [ create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:ddr4_rtl:1.0 CH0_DDR4_0_0 ]
  set sys_clk0_0 [ create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 sys_clk0_0 ]
  set CH0_DDR4_0_1 [ create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:ddr4_rtl:1.0 CH0_DDR4_0_1 ]
  set sys_clk0_1 [ create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 sys_clk0_1 ]

  # AXIS noc
  set axis_s_rx [create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:axis_rtl:1.0 axis_s_rx]
  set axis_s_tx [create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:axis_rtl:1.0 axis_s_tx]
  set axis_m_rx [create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:axis_rtl:1.0 axis_m_rx]
  set axis_m_tx [create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:axis_rtl:1.0 axis_m_tx]

  # Pins for internal connections
  set cpm_pcie_noc_axi0_clk  [ create_bd_pin -dir I -type CLK cpm_pcie_noc_axi0_clk ]
  set cpm_pcie_noc_axi1_clk  [ create_bd_pin -dir I -type CLK cpm_pcie_noc_axi1_clk ]
  set pmc_axi_noc_axi0_clk   [ create_bd_pin -dir I -type CLK pmc_axi_noc_axi0_clk ]
  set lpd_axi_noc_clk        [ create_bd_pin -dir I -type CLK lpd_axi_noc_clk ]

  set mgmt_clk               [ create_bd_pin -dir I -type CLK mgmt_clk ]
  set hpu_noc_clk            [ create_bd_pin -dir I -type CLK hpu_noc_clk ]
  set sregif_clk             [ create_bd_pin -dir I -type CLK sregif_clk ]

  # reset_n for smartconnect
  for { set j 0}  {$j < $REGIF_CLK_NB} {incr j} {
    create_bd_pin -dir I -type CLK mregif_${j}_clk
    create_bd_pin -dir I -from 0 -to 0 -type rst mregif_${j}_rst_n
  }

  set s_axi_pcie_mgmt_slr0   [ create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 s_axi_pcie_mgmt_slr0 ]

  set cpm_pcie_noc_0 [ create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 cpm_pcie_noc_0 ]
  set cpm_pcie_noc_1 [ create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 cpm_pcie_noc_1 ]
  set pmc_noc_axi_0 [ create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 pmc_noc_axi_0 ]
  set lpd_axi_noc_0 [ create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 lpd_axi_noc_0 ]

  for { set i 0}  {$i < $REGIF_NB} {incr i} {
    for { set j 0}  {$j < $REGIF_CLK_NB} {incr j} {
      set name "REGIF_AXI_${i}_${j}"
      create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 $name
    }
  }

  puts ">>>>>>>> End Create Pin >>>>>>>>>"
  ####################################
  # Create ddr_noc
  ####################################
  puts ">>>>>>>> Create DDR noc >>>>>>>>>"
  create_hier_cell_ddr_noc [current_bd_instance .] ddr_noc

  ####################################
  # Create output noc smartconnect
  ####################################
  puts ">>>>>>>> Create noc smartconnect >>>>>>>>>"
  # Used to transform AXI4-full into AXI4-lite
  for { set i 0}  {$i < $REGIF_NB} {incr i} {
    for { set j 0}  {$j < $REGIF_CLK_NB} {incr j} {
      set sc_axil [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 regif_sc_${i}_${j}]
      set_property CONFIG.NUM_SI {1} [get_bd_cells regif_sc_${i}_${j}]
    }
  }

  ####################################
  # Create axis_noc
  ####################################
  puts ">>>>>>>> Create AXIS noc >>>>>>>>>"
  set axis_noc [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_noc:1.0 axis_noc ]
  set_property -dict [list \
    CONFIG.TDATA_NUM_BYTES.VALUE_SRC $AXIS_NOC_DATA_W \
    CONFIG.NUM_MI $AXIS_NB \
    CONFIG.NUM_SI $AXIS_NB \
    CONFIG.NUM_CLKS {1} \
  ] $axis_noc

  ####################################
  # Create noc
  ####################################
  puts ">>>>>>>> Create noc >>>>>>>>>"
  # Create instance: axi_noc_cips, and set properties
  set axi_noc_cips [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_noc:1.1 axi_noc_cips ]
  set_property -dict [list \
    CONFIG.HBM_NUM_CHNL {16} \
    CONFIG.HBM_REF_CLK_FREQ0 $HBM_REF_FREQ \
    CONFIG.HBM_REF_CLK_FREQ1 $HBM_REF_FREQ \
    CONFIG.HBM_REF_CLK_SELECTION {External} \
    CONFIG.NUM_CLKS [expr 6 + $LPD_AXI_NB + $REGIF_CLK_NB] \
    CONFIG.NUM_HBM_BLI $HNMU_AXI_NB \
    CONFIG.NUM_MI [expr $AXI_PCIE_NB + $REGIF_NB*$REGIF_CLK_NB] \
    CONFIG.NUM_NMI {4} \
    CONFIG.NUM_NSI {0} \
    CONFIG.NUM_SI [expr $NMU_AXI_NB + $LPD_AXI_NB] \
  ] $axi_noc_cips

  #===================================
  # NOC pin assignment
  #===================================
  #== NOC Inputs
  # HBM_NMU
  # TOREVIEW: offset according to P&R
  set ksk_ofs 0
  set ct_ofs   [expr $ksk_ofs + $KSK_AXI_NB]
  set glwe_ofs [expr $ct_ofs + $CT_AXI_NB]
  set trc_ofs  [expr $glwe_ofs + $GLWE_AXI_NB]

  set ksk_noc_pins_l [list]
  for { set i 0}  {$i < $KSK_AXI_NB} {incr i} {
    lappend ksk_noc_pins_l [format "HBM%02d_AXI" [expr $i + $ksk_ofs]]
  }
  set trc_noc_pins_l [list]
  for { set i 0}  {$i < $TRC_AXI_NB} {incr i} {
    lappend trc_noc_pins_l [format "HBM%02d_AXI" [expr $i + $trc_ofs]]
  }
  set ct_noc_pins_l [list]
  for { set i 0}  {$i < $CT_AXI_NB} {incr i} {
    lappend ct_noc_pins_l [format "HBM%02d_AXI" [expr $i + $ct_ofs]]
  }
  set glwe_noc_pins_l [list]
  for { set i 0}  {$i < $GLWE_AXI_NB} {incr i} {
    lappend glwe_noc_pins_l [format "HBM%02d_AXI" [expr $i + $glwe_ofs]]
  }

  # NMU
  set cpm_ofs 0
  set pmc_ofs [expr $cpm_ofs + 2]
  set lpd_ofs [expr $pmc_ofs + 1]
  set sregif_ofs [expr $lpd_ofs + 1]
  set bsk_ofs [expr $sregif_ofs + 1]
  set other_aclk_ofs [expr $bsk_ofs + 1]

  set cpm_noc_pins_l [list]
  for { set i 0}  {$i < 2} {incr i} {
    lappend cpm_noc_pins_l [format "S%02d_AXI" [expr $i + $cpm_ofs]]
  }
  set pmc_noc_pins_l [list]
  for { set i 0}  {$i < 1} {incr i} {
    lappend pmc_noc_pins_l [format "S%02d_AXI" [expr $i + $pmc_ofs]]
  }
  set lpd_noc_pins_l [list]
  for { set i 0}  {$i < 1} {incr i} {
    lappend lpd_noc_pins_l [format "S%02d_AXI" [expr $i + $lpd_ofs]]
  }
  set bsk_noc_pins_l [list]
  for { set i 0}  {$i < $BSK_AXI_NB} {incr i} {
    lappend bsk_noc_pins_l [format "S%02d_AXI" [expr $i + $bsk_ofs]]
  }

  set sregif_noc_pins_l [format "S%02d_AXI" [expr $sregif_ofs]]

  #== NOC Outputs
  #NSU
  set mgmt_ofs 0
  set mregif_ofs [expr $mgmt_ofs + 1]

  set pcie_mgmt_noc_pins_l [list]
  for { set i 0}  {$i < 1} {incr i} {
    lappend pcie_mgmt_noc_pins_l [format "M%02d_AXI" [expr $i + $mgmt_ofs]]
  }

  set mregif_noc_pins_l [list]
  for { set i 0}  {$i < [expr $REGIF_NB*$REGIF_CLK_NB]} {incr i} {
    lappend mregif_noc_pins_l [format "M%02d_AXI" [expr $i + $mregif_ofs]]
  }

  #INI
  set ddr_noc_pins_l [list]
  for { set i 0}  {$i < 4} {incr i} {
    lappend ddr_noc_pins_l [format "M%02d_INI" $i]
  }

  #== AXIS NOC
  set axis_noc_tx_pins_l [list]
  set axis_noc_rx_pins_l [list]
  for { set i 0}  {$i < $AXIS_NB} {incr i} {
    lappend axis_noc_tx_pins_l [format "M%02d_AXIS" $i]
    lappend axis_noc_rx_pins_l [format "S%02d_AXIS" $i]
  }

  #== Clocks
  set cpm_noc_clock_pins_l [list]
  for { set i 0}  {$i < 2} {incr i} {
    lappend cpm_noc_clock_pins_l [format "aclk%0d" [expr $i + $cpm_ofs]]
  }
  set pmc_noc_clock_pins_l [list]
  for { set i 0}  {$i < 1} {incr i} {
    lappend pmc_noc_clock_pins_l [format "aclk%0d" [expr $i + $pmc_ofs]]
  }
  set lpd_noc_clock_pins_l [list]
  for { set i 0}  {$i < 1} {incr i} {
    lappend lpd_noc_clock_pins_l [format "aclk%0d" [expr $i + $lpd_ofs]]
  }
  set sregif_clock_pins_l [list]
  for { set i 0}  {$i < 1} {incr i} {
    lappend sregif_clock_pins_l [format "aclk%0d" [expr $i + $sregif_ofs]]
  }
  set hpu_noc_clock_pins_l [list]
  for { set i 0}  {$i < 1} {incr i} {
    lappend hpu_noc_clock_pins_l [format "aclk%0d" [expr $i + $bsk_ofs]]
  }
  set mregif_clock_pins_l [list]
  for { set i 0}  {$i < $REGIF_CLK_NB} {incr i} {
    lappend mregif_clock_pins_l [format "aclk%0d" [expr $i + $other_aclk_ofs + $mregif_ofs]]
  }
  set pcie_mgmt_noc_clock_pins_l [list]
  for { set i 0}  {$i < 1} {incr i} {
    lappend pcie_mgmt_noc_clock_pins_l [format "aclk%0d" [expr $i + $other_aclk_ofs + $mgmt_ofs]]
  }
  set axis_noc_clock_pins_l [list]
  for { set i 0}  {$i < 1} {incr i} {
    lappend axis_noc_clock_pins_l [format "aclk%0d" $i]
  }

  #===================================
  # NOC properties
  #===================================
  puts ">>>>>>>> Create noc properties >>>>>>>>>"
  # Note : for simplicity and comprehension, HBM are numbered according to their ports.
  # In V80, there are 2 HBM, with 8 channels each. Each channel has 2 pseudo-channel (PC).
  # Each PC has 2 ports. Therefore there is a total of 32 HBM ports.
  set HBM_PORT_NB 64
  # Note that the HBM ports have been attributed to the different PL usage, so that
  # the highest BW is ensured.
  # KSK : Use HBM_PORT 0-7 and 16-23
  set ksk_hbm_ports_l [list 0 1 2 3 4 5 6 7 16 17 18 19 20 21 22 23]
  # CT : Use HBM_PORT 32 - 33
  set ct_hbm_ports_l [list 32 33]
  # GLWE : Use HBM_PORT 34
  set glwe_hbm_ports_l [list 34]
  # TRC : Use HBM_PORT 35
  set trc_hbm_ports_l [list 35]
  # BSK : Use 8 12 24 28 40 44 56 60
  set bsk_hbm_ports_l [list 8 12 24 28 40 44 56 60]

  # Check NOC config
  if {[llength $ksk_hbm_ports_l] < $KSK_AXI_NB} {
    catch {common::send_gid_msg -ssname BD::TCL -id 3333 -severity "ERROR" " Noc configuration is incoherent for KSK. Expected at least $KSK_AXI_NB HBM port assignment."}
  }
  if {[llength $trc_hbm_ports_l] < $TRC_AXI_NB} {
    catch {common::send_gid_msg -ssname BD::TCL -id 3333 -severity "ERROR" " Noc configuration is incoherent for TRC. Expected at least $TRC_AXI_NB HBM port assignment."}
  }
  if {[llength $ct_hbm_ports_l] < $CT_AXI_NB} {
    catch {common::send_gid_msg -ssname BD::TCL -id 3333 -severity "ERROR" " Noc configuration is incoherent for CT. Expected at least $CT_AXI_NB HBM port assignment."}
  }
  if {[llength $glwe_hbm_ports_l] < $GLWE_AXI_NB} {
    catch {common::send_gid_msg -ssname BD::TCL -id 3333 -severity "ERROR" " Noc configuration is incoherent for GLWE. Expected at least $GLWE_AXI_NB HBM port assignment."}
  }
  if {[llength $bsk_hbm_ports_l] < $BSK_AXI_NB} {
    catch {common::send_gid_msg -ssname BD::TCL -id 3333 -severity "ERROR" " Noc configuration is incoherent for BSK. Expected at least $BSK_AXI_NB HBM port assignment."}
  }

  #== HBM_NMU
  # KSK
  set ksk_hbm_qos [set_qos $HPU_KSK_HBM_RD_BW $HPU_KSK_HBM_WR_BW $HPU_KSK_HBM_RD_BURST_AVG $HPU_KSK_HBM_WR_BURST_AVG]
  for { set i 0}  {$i < $KSK_AXI_NB} {incr i} {
    set idx [lindex $ksk_hbm_ports_l $i]
    set hbm_port_name [format "HBM%0d_PORT%0d" [expr int($idx / 4)] [expr $idx % 4]]
    set cnx [list $hbm_port_name $ksk_hbm_qos]

    set_property -dict [ list \
     CONFIG.DATA_WIDTH $HPU_KSK_HBM_DATA_W \
     CONFIG.CONNECTIONS $cnx \
     CONFIG.NOC_PARAMS {} \
     CONFIG.CATEGORY {pl_hbm} \
   ] [get_bd_intf_pins axi_noc_cips/[lindex $ksk_noc_pins_l $i]]

  }

  # TRC
  set trc_hbm_qos [set_qos $HPU_TRC_HBM_RD_BW $HPU_TRC_HBM_WR_BW $HPU_TRC_HBM_RD_BURST_AVG $HPU_TRC_HBM_WR_BURST_AVG]
  for { set i 0}  {$i < $TRC_AXI_NB} {incr i} {
    set idx [lindex $trc_hbm_ports_l $i]
    set hbm_port_name [format "HBM%0d_PORT%0d" [expr int($idx / 4)] [expr $idx % 4]]
    set cnx [list $hbm_port_name $trc_hbm_qos]

    set_property -dict [ list \
     CONFIG.DATA_WIDTH $HPU_TRC_HBM_DATA_W \
     CONFIG.CONNECTIONS $cnx \
     CONFIG.NOC_PARAMS {} \
     CONFIG.CATEGORY {pl_hbm} \
   ] [get_bd_intf_pins axi_noc_cips/[lindex $trc_noc_pins_l $i]]

  }

  # CT
  set ct_hbm_qos [set_qos $HPU_CT_HBM_RD_BW $HPU_CT_HBM_WR_BW $HPU_CT_HBM_RD_BURST_AVG $HPU_CT_HBM_WR_BURST_AVG]
  for { set i 0}  {$i < $CT_AXI_NB} {incr i} {
    set idx [lindex $ct_hbm_ports_l $i]
    set hbm_port_name [format "HBM%0d_PORT%0d" [expr int($idx / 4)] [expr $idx % 4]]
    set cnx [list $hbm_port_name $ct_hbm_qos]

    set_property -dict [ list \
     CONFIG.DATA_WIDTH $HPU_CT_HBM_DATA_W \
     CONFIG.CONNECTIONS $cnx \
     CONFIG.NOC_PARAMS {} \
     CONFIG.CATEGORY {pl_hbm} \
   ] [get_bd_intf_pins axi_noc_cips/[lindex $ct_noc_pins_l $i]]

  }

  # GLWE
  set glwe_hbm_qos [set_qos $HPU_GLWE_HBM_RD_BW $HPU_GLWE_HBM_WR_BW $HPU_GLWE_HBM_RD_BURST_AVG $HPU_GLWE_HBM_WR_BURST_AVG]
  for { set i 0}  {$i < $GLWE_AXI_NB} {incr i} {
    set idx [lindex $glwe_hbm_ports_l $i]
    set hbm_port_name [format "HBM%0d_PORT%0d" [expr int($idx / 4)] [expr $idx % 4]]
    set cnx [list $hbm_port_name $glwe_hbm_qos]

    set_property -dict [ list \
     CONFIG.DATA_WIDTH $HPU_GLWE_HBM_DATA_W \
     CONFIG.CONNECTIONS $cnx \
     CONFIG.NOC_PARAMS {} \
     CONFIG.CATEGORY {pl_hbm} \
   ] [get_bd_intf_pins axi_noc_cips/[lindex $glwe_noc_pins_l $i]]

  }

  #== NMU
  # CPM 0
  # Connect to DDRs (M00_INI, M02_INI) and mgmt (M00_AXI)
  # Connect to all HBM PC, even ports
  set pcie_ddr_dma_qos  [set_qos $PCIE_DDR_DMA_RD_BW $PCIE_DDR_DMA_WR_BW $PCIE_DDR_DMA_RD_BURST_AVG $PCIE_DDR_DMA_WR_BURST_AVG]
  set pcie_axil_qos [set_qos $PCIE_AXIL_RD_BW $PCIE_AXIL_WR_BW $PCIE_AXIL_RD_BURST_AVG $PCIE_AXIL_WR_BURST_AVG]
  set pcie_hbm_dma_qos [set_qos $PCIE_HBM_DMA_RD_BW $PCIE_HBM_DMA_WR_BW $PCIE_HBM_DMA_RD_BURST_AVG $PCIE_HBM_DMA_WR_BURST_AVG]
  set pcie_cnx_0 [list]
  lappend pcie_cnx_0 [lindex $ddr_noc_pins_l 0] $pcie_ddr_dma_qos
  lappend pcie_cnx_0 [lindex $ddr_noc_pins_l 2] $pcie_ddr_dma_qos
  lappend pcie_cnx_0 [lindex $pcie_mgmt_noc_pins_l 0] $pcie_axil_qos
  # all HBM PCs, even ports
  for { set i 0}  {$i < $HBM_PORT_NB} {incr i 2} {
    set hbm_port_name [format "HBM%01d_PORT%01d" [expr int($i / 4)] [expr ($i%4)]]
    lappend pcie_cnx_0 $hbm_port_name $pcie_hbm_dma_qos
  }
  puts ">> CPM_0 CNX $pcie_cnx_0"
  # Remap for RPU access to DDR
  set_property -dict [ list \
   CONFIG.CONNECTIONS $pcie_cnx_0 \
   CONFIG.DEST_IDS {M00_AXI:0x480} \
   CONFIG.REMAPS {M00_INI {{0x20108000000 0x00038000000 0x08000000}}} \
   CONFIG.NOC_PARAMS {} \
   CONFIG.CATEGORY {ps_pcie} \
 ] [get_bd_intf_pins axi_noc_cips/[lindex $cpm_noc_pins_l 0]]


  # CPM 1
  # Connect to DDRs (M00_INI, M02_INI) and mgmt (M00_AXI)
  # Connect to all HBM PC, odd ports
  set pcie_cnx_1 [list]
  lappend pcie_cnx_1 [lindex $ddr_noc_pins_l 1] $pcie_ddr_dma_qos
  lappend pcie_cnx_1 [lindex $ddr_noc_pins_l 3] $pcie_ddr_dma_qos
  lappend pcie_cnx_1 [lindex $pcie_mgmt_noc_pins_l 0] $pcie_axil_qos
  # all HBM PCs, odd ports
  for { set i 1}  {$i < $HBM_PORT_NB} {incr i 2} {
    set hbm_port_name [format "HBM%01d_PORT%01d" [expr int($i / 4)] [expr ($i%4)]]
    lappend pcie_cnx_1 $hbm_port_name $pcie_hbm_dma_qos
  }
  puts ">> CPM_1 CNX $pcie_cnx_1"
  set_property -dict [ list \
   CONFIG.CONNECTIONS $pcie_cnx_1 \
   CONFIG.DEST_IDS {M00_AXI:0x480} \
   CONFIG.NOC_PARAMS {} \
   CONFIG.CATEGORY {ps_pcie} \
 ] [get_bd_intf_pins axi_noc_cips/[lindex $cpm_noc_pins_l 1]]


  # PMC
  # Connect to DDR
  set pmc_ddr_qos  [set_qos $PMC_DDR_RD_BW $PMC_DDR_WR_BW $PMC_DDR_RD_BURST_AVG $PMC_DDR_WR_BURST_AVG]
  set pmc_cnx [list]
  lappend pmc_cnx [lindex $ddr_noc_pins_l 0] $pmc_ddr_qos
  lappend pmc_cnx [lindex $ddr_noc_pins_l 2] $pmc_ddr_qos
  puts ">> PMC CNX $pmc_cnx"
  set_property -dict [ list \
   CONFIG.CONNECTIONS $pmc_cnx \
   CONFIG.DEST_IDS {} \
   CONFIG.NOC_PARAMS {} \
   CONFIG.CATEGORY {ps_pmc} \
 ] [get_bd_intf_pins axi_noc_cips/[lindex $pmc_noc_pins_l 0]]


  # RPU - LPD
  set rpu_ddr_qos  [set_qos $RPU_DDR_RD_BW $RPU_DDR_WR_BW $RPU_DDR_RD_BURST_AVG $RPU_DDR_WR_BURST_AVG]
  set lpd_cnx [list]
  lappend lpd_cnx [lindex $ddr_noc_pins_l 0] $rpu_ddr_qos
  puts ">> LPD CNX $lpd_cnx"
  set_property -dict [ list \
   CONFIG.CONNECTIONS $lpd_cnx \
   CONFIG.DEST_IDS {} \
   CONFIG.NOC_PARAMS {} \
   CONFIG.CATEGORY {ps_rpu} \
  ] [get_bd_intf_pins axi_noc_cips/[lindex $lpd_noc_pins_l 0]]

  # BSK
  set bsk_hbm_qos [set_qos $HPU_BSK_HBM_RD_BW $HPU_BSK_HBM_WR_BW $HPU_BSK_HBM_RD_BURST_AVG $HPU_BSK_HBM_WR_BURST_AVG]
  for { set i 0}  {$i < $BSK_AXI_NB} {incr i} {
    set idx [lindex $bsk_hbm_ports_l $i]
    set hbm_port_name [format "HBM%01d_PORT%01d" [expr int($idx / 4)] [expr ($idx%4)]]
    set cnx [list $hbm_port_name $bsk_hbm_qos]
    puts ">> BSK CNX [$i] $cnx"
    set_property -dict [ list \
     CONFIG.DATA_WIDTH $HPU_BSK_HBM_DATA_W \
     CONFIG.CONNECTIONS $cnx \
     CONFIG.NOC_PARAMS {} \
     CONFIG.CATEGORY {pl} \
   ] [get_bd_intf_pins axi_noc_cips/[lindex $bsk_noc_pins_l $i]]
  }

  # Regfile : RPU <-> PL through NOC
  set axil_qos [set_qos $RPU_AXIL_RD_BW $RPU_AXIL_WR_BW $RPU_AXIL_RD_BURST_AVG $RPU_AXIL_WR_BURST_AVG]
  set regif_cnx [list]
  for {set i 0}  {$i < $REGIF_NB*$REGIF_CLK_NB} {incr i} {
    lappend regif_cnx [lindex $mregif_noc_pins_l $i] $axil_qos
  }
  set_property -dict [list \
    CONFIG.CONNECTIONS $regif_cnx
  ] [get_bd_intf_pins axi_noc_cips/[lindex $sregif_noc_pins_l 0]]

  # MGMT
  set_property -dict [ list \
   CONFIG.DATA_WIDTH {32} \
   CONFIG.APERTURES {{0x201_0000_0000 0x200_0000}} \
   CONFIG.CATEGORY {pl} \
  ] [get_bd_intf_pins axi_noc_cips/[lindex $pcie_mgmt_noc_pins_l 0]]

  #== AXIS noc
  set axis_qos [set_axis_qos $RPU_ISC_WR_BW $RPU_ISC_WR_BURST_AVG]
  for {set i 0}  {$i < $AXIS_NB} {incr i} {
    set port_name [lindex $axis_noc_tx_pins_l $i]
    set cnx [list $port_name $axis_qos]
    puts ">> AXIS CNX [$i] $cnx"
    set_property -dict [ list \
     CONFIG.CONNECTIONS $cnx \
     CONFIG.CATEGORY {pl} \
   ] [get_bd_intf_pins axis_noc/[lindex $axis_noc_rx_pins_l $i]]
  }

  #== Clocks
  # CPM
  for { set i 0}  {$i < 2} {incr i} {
    set_property -dict [ list \
    CONFIG.ASSOCIATED_BUSIF [lindex $cpm_noc_pins_l $i] \
    ] [get_bd_pins axi_noc_cips/[lindex $cpm_noc_clock_pins_l $i]]
  }

  # PMC
  for { set i 0}  {$i < 1} {incr i} {
    set_property -dict [ list \
    CONFIG.ASSOCIATED_BUSIF [lindex $pmc_noc_pins_l $i] \
    ] [get_bd_pins axi_noc_cips/[lindex $pmc_noc_clock_pins_l $i]]
  }

  # LPD
  for { set i 0}  {$i < 1} {incr i} {
    set_property -dict [ list \
    CONFIG.ASSOCIATED_BUSIF [lindex $lpd_noc_pins_l $i] \
    ] [get_bd_pins axi_noc_cips/[lindex $lpd_noc_clock_pins_l $i]]
  }

  # MGMT
  for { set i 0}  {$i < 1} {incr i} {
    set_property -dict [ list \
    CONFIG.ASSOCIATED_BUSIF [lindex $pcie_mgmt_noc_pins_l $i] \
    ] [get_bd_pins axi_noc_cips/[lindex $pcie_mgmt_noc_clock_pins_l $i]]
  }

  # S_REGIF
  set_property -dict [ list \
    CONFIG.ASSOCIATED_BUSIF [lindex $sregif_noc_pins_l 0] \
  ] [get_bd_pins axi_noc_cips/[lindex $sregif_clock_pins_l 0]]

  # REGIF
  for { set j 0}  {$j < $REGIF_CLK_NB} {incr j} {
    set mregif_noc_pins_format ""
    for { set i 0}  {$i < $REGIF_NB} {incr i} {
      set n [lindex $mregif_noc_pins_l [expr $i*$REGIF_CLK_NB + $j]]
      if {$mregif_noc_pins_format eq ""} {
        set mregif_noc_pins_format "${n}"
      } else {
        set mregif_noc_pins_format "${mregif_noc_pins_format}:${n}"
      }
    }
    set_property -dict [ list \
      CONFIG.ASSOCIATED_BUSIF  ${mregif_noc_pins_format}\
    ] [get_bd_pins axi_noc_cips/[lindex $mregif_clock_pins_l $j]]
  }

  # HPU
  set hpu_noc_pins_l [concat $ksk_noc_pins_l $trc_noc_pins_l $ct_noc_pins_l $glwe_noc_pins_l $bsk_noc_pins_l]
  set hpu_noc_pins_format ""
  foreach n $hpu_noc_pins_l {
    if {$hpu_noc_pins_format eq ""} {
      set hpu_noc_pins_format "${n}"
    } else {
      set hpu_noc_pins_format "${hpu_noc_pins_format}:${n}"
    }
  }

  for { set i 0}  {$i < 1} {incr i} {
    set_property -dict [ list \
    CONFIG.ASSOCIATED_BUSIF ${hpu_noc_pins_format} \
    ] [get_bd_pins axi_noc_cips/[lindex $hpu_noc_clock_pins_l $i]]
  }

  # AXIS NOC
  set axis_noc_pins_l [concat $axis_noc_rx_pins_l $axis_noc_tx_pins_l]
  set axis_noc_pins_format ""
  foreach n $axis_noc_pins_l {
    if {$axis_noc_pins_format eq ""} {
      set axis_noc_pins_format "${n}"
    } else {
      set axis_noc_pins_format "${axis_noc_pins_format}:${n}"
    }
  }

  for { set i 0}  {$i < 1} {incr i} {
    set_property -dict [ list \
    CONFIG.ASSOCIATED_BUSIF ${axis_noc_pins_format} \
    ] [get_bd_pins axis_noc/[lindex $axis_noc_clock_pins_l $i]]
  }

  ####################################
  # Connection
  ####################################
  # Internal connections
  for { set i 0}  {$i < $TRC_AXI_NB} {incr i} {
    set name "TRC_AXI_${i}"
    connect_bd_intf_net -intf_net $name [get_bd_intf_pins $name] [get_bd_intf_pins axi_noc_cips/[lindex $trc_noc_pins_l $i]]
  }
  for { set i 0}  {$i < $CT_AXI_NB} {incr i} {
    set name "CT_AXI_${i}"
    connect_bd_intf_net -intf_net $name [get_bd_intf_pins $name] [get_bd_intf_pins axi_noc_cips/[lindex $ct_noc_pins_l $i]]
  }
  for { set i 0}  {$i < $GLWE_AXI_NB} {incr i} {
    set name "GLWE_AXI_${i}"
    connect_bd_intf_net -intf_net $name [get_bd_intf_pins $name] [get_bd_intf_pins axi_noc_cips/[lindex $glwe_noc_pins_l $i]]
  }
  for { set i 0}  {$i < $KSK_AXI_NB} {incr i} {
    set name "KSK_AXI_${i}"
    connect_bd_intf_net -intf_net $name [get_bd_intf_pins $name] [get_bd_intf_pins axi_noc_cips/[lindex $ksk_noc_pins_l $i]]
  }
  for { set i 0}  {$i < $BSK_AXI_NB} {incr i} {
    set name "BSK_AXI_${i}"
    connect_bd_intf_net -intf_net $name [get_bd_intf_pins $name] [get_bd_intf_pins axi_noc_cips/[lindex $bsk_noc_pins_l $i]]
  }

  connect_bd_intf_net -intf_net cpm_pcie_noc_0 [get_bd_intf_pins cpm_pcie_noc_0] [get_bd_intf_pins axi_noc_cips/[lindex $cpm_noc_pins_l 0]]
  connect_bd_intf_net -intf_net cpm_pcie_noc_1 [get_bd_intf_pins cpm_pcie_noc_1] [get_bd_intf_pins axi_noc_cips/[lindex $cpm_noc_pins_l 1]]

  connect_bd_intf_net -intf_net pmc_noc_axi_0 [get_bd_intf_pins pmc_noc_axi_0] [get_bd_intf_pins axi_noc_cips/[lindex $pmc_noc_pins_l 0]]

  connect_bd_intf_net -intf_net lpd_axi_noc_0 [get_bd_intf_pins lpd_axi_noc_0] [get_bd_intf_pins axi_noc_cips/[lindex $lpd_noc_pins_l 0]]

  connect_bd_intf_net -intf_net axi_noc_cips_M00_INI [get_bd_intf_pins axi_noc_cips/M00_INI] [get_bd_intf_pins ddr_noc/S00_INI_0]
  connect_bd_intf_net -intf_net axi_noc_cips_M01_INI [get_bd_intf_pins axi_noc_cips/M01_INI] [get_bd_intf_pins ddr_noc/S01_INI_0]
  connect_bd_intf_net -intf_net axi_noc_cips_M02_INI [get_bd_intf_pins axi_noc_cips/M02_INI] [get_bd_intf_pins ddr_noc/S00_INI_1]
  connect_bd_intf_net -intf_net axi_noc_cips_M03_INI [get_bd_intf_pins axi_noc_cips/M03_INI] [get_bd_intf_pins ddr_noc/S01_INI_1]

  connect_bd_intf_net -intf_net hbm_ref_clk_0 [get_bd_intf_pins hbm_ref_clk_0] [get_bd_intf_pins axi_noc_cips/hbm_ref_clk0]
  connect_bd_intf_net -intf_net hbm_ref_clk_1 [get_bd_intf_pins hbm_ref_clk_1] [get_bd_intf_pins axi_noc_cips/hbm_ref_clk1]

  connect_bd_intf_net -intf_net CH0_DDR4_0_0 [get_bd_intf_pins ddr_noc/CH0_DDR4_0_0] [get_bd_intf_pins CH0_DDR4_0_0]
  connect_bd_intf_net -intf_net CH0_DDR4_0_1 [get_bd_intf_pins ddr_noc/CH0_DDR4_0_1] [get_bd_intf_pins CH0_DDR4_0_1]
  connect_bd_intf_net -intf_net sys_clk0_0   [get_bd_intf_pins ddr_noc/sys_clk0_0]   [get_bd_intf_pins sys_clk0_0]
  connect_bd_intf_net -intf_net sys_clk0_1   [get_bd_intf_pins ddr_noc/sys_clk0_1]   [get_bd_intf_pins sys_clk0_1]

  connect_bd_net [get_bd_pins cpm_pcie_noc_axi0_clk] [get_bd_pins axi_noc_cips/[lindex $cpm_noc_clock_pins_l 0]]
  connect_bd_net [get_bd_pins cpm_pcie_noc_axi1_clk] [get_bd_pins axi_noc_cips/[lindex $cpm_noc_clock_pins_l 1]]
  connect_bd_net [get_bd_pins pmc_axi_noc_axi0_clk] [get_bd_pins axi_noc_cips/[lindex $pmc_noc_clock_pins_l 0]]
  connect_bd_net [get_bd_pins lpd_axi_noc_clk] [get_bd_pins axi_noc_cips/[lindex $lpd_noc_clock_pins_l 0]]
  connect_bd_net [get_bd_pins mgmt_clk] [get_bd_pins axi_noc_cips/[lindex $pcie_mgmt_noc_clock_pins_l 0]]
  connect_bd_net [get_bd_pins hpu_noc_clk] [get_bd_pins axi_noc_cips/[lindex $hpu_noc_clock_pins_l 0]] [get_bd_pins axis_noc/[lindex $axis_noc_clock_pins_l 0]]

  for {set j 0}  {$j < $REGIF_CLK_NB} {incr j} {
    connect_bd_net [get_bd_pins mregif_${j}_clk] [get_bd_pins axi_noc_cips/[lindex $mregif_clock_pins_l $j]]
  }

  connect_bd_net [get_bd_pins sregif_clk] [get_bd_pins axi_noc_cips/[lindex $sregif_clock_pins_l 0]]

  connect_bd_intf_net -intf_net axi_noc_cips_mgmt [get_bd_intf_pins axi_noc_cips/[lindex $pcie_mgmt_noc_pins_l 0]] [get_bd_intf_pins s_axi_pcie_mgmt_slr0]

  for {set i 0}  {$i < $REGIF_NB} {incr i} {
    for {set j 0}  {$j < $REGIF_CLK_NB} {incr j} {
      set name "REGIF_AXI_${i}_${j}"
      set idx [expr $i * $REGIF_CLK_NB + $j ]
      connect_bd_intf_net  [get_bd_intf_pins axi_noc_cips/[lindex $mregif_noc_pins_l $idx]] [get_bd_intf_pins regif_sc_${i}_${j}/S00_AXI]
      connect_bd_intf_net -intf_net sc_$name [get_bd_intf_pins $name] [get_bd_intf_pins regif_sc_${i}_${j}/M00_AXI]
      connect_bd_net [get_bd_pins mregif_${j}_clk] [get_bd_pins regif_sc_${i}_${j}/aclk]
      connect_bd_net [get_bd_pins mregif_${j}_rst_n] [get_bd_pins regif_sc_${i}_${j}/aresetn]
    }
  }
  connect_bd_intf_net -intf_net S_REGIF_AXI_0 [get_bd_intf_pins S_REGIF_AXI_0] [get_bd_intf_pins axi_noc_cips/[lindex $sregif_noc_pins_l 0]]

  connect_bd_intf_net -intf_net axis_m_rx [get_bd_intf_pins axis_m_rx] [get_bd_intf_pins axis_noc/[lindex $axis_noc_rx_pins_l 0]]
  connect_bd_intf_net -intf_net axis_m_tx [get_bd_intf_pins axis_m_tx] [get_bd_intf_pins axis_noc/[lindex $axis_noc_tx_pins_l 0]]
  connect_bd_intf_net -intf_net axis_s_rx [get_bd_intf_pins axis_s_rx] [get_bd_intf_pins axis_noc/[lindex $axis_noc_rx_pins_l 1]]
  connect_bd_intf_net -intf_net axis_s_tx [get_bd_intf_pins axis_s_tx] [get_bd_intf_pins axis_noc/[lindex $axis_noc_tx_pins_l 1]]

  ##########################
  ### physical placement ###
  ##########################
  puts ">>> Set physical placement"
  puts ">>> NTT PSI: $ntt_psi"

  # BSK
  if { $ntt_psi == 64 } {
  # in this case BSK IF is in SLR0
    set_property CONFIG.PHYSICAL_LOC NOC_NMU512_X0Y2 [get_bd_intf_pins axi_noc_cips/S05_AXI]
    set_property CONFIG.PHYSICAL_LOC NOC_NMU512_X0Y3 [get_bd_intf_pins axi_noc_cips/S06_AXI]

    set_property CONFIG.PHYSICAL_LOC NOC_NMU512_X1Y2 [get_bd_intf_pins axi_noc_cips/S07_AXI]
    set_property CONFIG.PHYSICAL_LOC NOC_NMU512_X1Y3 [get_bd_intf_pins axi_noc_cips/S08_AXI]

    set_property CONFIG.PHYSICAL_LOC NOC_NMU512_X2Y2 [get_bd_intf_pins axi_noc_cips/S09_AXI]
    set_property CONFIG.PHYSICAL_LOC NOC_NMU512_X2Y3 [get_bd_intf_pins axi_noc_cips/S10_AXI]

    set_property CONFIG.PHYSICAL_LOC NOC_NMU512_X3Y2 [get_bd_intf_pins axi_noc_cips/S11_AXI]
    set_property CONFIG.PHYSICAL_LOC NOC_NMU512_X3Y3 [get_bd_intf_pins axi_noc_cips/S12_AXI]

  } elseif { $ntt_psi == 32 } {
  # in this case BSK IF is in SLR1
    set_property CONFIG.PHYSICAL_LOC NOC_NMU512_X0Y8 [get_bd_intf_pins axi_noc_cips/S05_AXI]
    set_property CONFIG.PHYSICAL_LOC NOC_NMU512_X0Y9 [get_bd_intf_pins axi_noc_cips/S06_AXI]

    set_property CONFIG.PHYSICAL_LOC NOC_NMU512_X1Y8 [get_bd_intf_pins axi_noc_cips/S07_AXI]
    set_property CONFIG.PHYSICAL_LOC NOC_NMU512_X1Y9 [get_bd_intf_pins axi_noc_cips/S08_AXI]

    set_property CONFIG.PHYSICAL_LOC NOC_NMU512_X2Y8 [get_bd_intf_pins axi_noc_cips/S09_AXI]
    set_property CONFIG.PHYSICAL_LOC NOC_NMU512_X2Y9 [get_bd_intf_pins axi_noc_cips/S10_AXI]

    set_property CONFIG.PHYSICAL_LOC NOC_NMU512_X3Y8 [get_bd_intf_pins axi_noc_cips/S11_AXI]
    set_property CONFIG.PHYSICAL_LOC NOC_NMU512_X3Y9 [get_bd_intf_pins axi_noc_cips/S12_AXI]
  # means psi = 16 or under
  } else {
  # in this case BSK IF is in SLR1
    set_property CONFIG.PHYSICAL_LOC NOC_NMU512_X0Y8 [get_bd_intf_pins axi_noc_cips/S05_AXI]
    set_property CONFIG.PHYSICAL_LOC NOC_NMU512_X0Y9 [get_bd_intf_pins axi_noc_cips/S06_AXI]

    set_property CONFIG.PHYSICAL_LOC NOC_NMU512_X1Y8 [get_bd_intf_pins axi_noc_cips/S07_AXI]
    set_property CONFIG.PHYSICAL_LOC NOC_NMU512_X1Y9 [get_bd_intf_pins axi_noc_cips/S08_AXI]

    set_property CONFIG.PHYSICAL_LOC NOC_NMU512_X2Y8 [get_bd_intf_pins axi_noc_cips/S09_AXI]
    set_property CONFIG.PHYSICAL_LOC NOC_NMU512_X2Y9 [get_bd_intf_pins axi_noc_cips/S10_AXI]

    set_property CONFIG.PHYSICAL_LOC NOC_NMU512_X3Y8 [get_bd_intf_pins axi_noc_cips/S11_AXI]
    set_property CONFIG.PHYSICAL_LOC NOC_NMU512_X3Y9 [get_bd_intf_pins axi_noc_cips/S12_AXI]
  }

  # REGIF
  # connected to RPU
  set_property CONFIG.PHYSICAL_LOC NOC_NMU512_X2Y1  [get_bd_intf_pins axi_noc_cips/S04_AXI]
  if { $ntt_psi == 64 } {
    # 2 are used in SLR0, and 2 in SLR2
    set_property CONFIG.PHYSICAL_LOC NOC_NSU512_X2Y1 [get_bd_intf_pins axi_noc_cips/M03_AXI]
    set_property CONFIG.PHYSICAL_LOC NOC_NSU512_X2Y2 [get_bd_intf_pins axi_noc_cips/M04_AXI]
    set_property CONFIG.PHYSICAL_LOC NOC_NSU512_X2Y16 [get_bd_intf_pins axi_noc_cips/M01_AXI]
    set_property CONFIG.PHYSICAL_LOC NOC_NSU512_X2Y13 [get_bd_intf_pins axi_noc_cips/M02_AXI]
  } elseif { $ntt_psi == 32 } {
    # 2 are used in SLR1, and 2 in SLR2
    set_property CONFIG.PHYSICAL_LOC NOC_NSU512_X2Y8 [get_bd_intf_pins axi_noc_cips/M03_AXI]
    set_property CONFIG.PHYSICAL_LOC NOC_NSU512_X2Y9 [get_bd_intf_pins axi_noc_cips/M04_AXI]
    set_property CONFIG.PHYSICAL_LOC NOC_NSU512_X2Y16 [get_bd_intf_pins axi_noc_cips/M01_AXI]
    set_property CONFIG.PHYSICAL_LOC NOC_NSU512_X2Y13 [get_bd_intf_pins axi_noc_cips/M02_AXI]
  # means psi = 16 or under
  } else {
    # All 4 are used in SLR1
    # Let the tool place them
  }

  # MGMT (to UUID, GCQ...)
  set_property CONFIG.PHYSICAL_LOC NOC_NSU512_X2Y0 [get_bd_intf_pins axi_noc_cips/M00_AXI]

  #  # AXIS
  if { $ntt_psi == 64 } {
    set_property CONFIG.PHYSICAL_LOC NOC_NMU512_X0Y0  [get_bd_intf_pins axis_noc/S00_AXIS]
    set_property CONFIG.PHYSICAL_LOC NOC_NSU512_X1Y0  [get_bd_intf_pins axis_noc/M01_AXIS]
    set_property CONFIG.PHYSICAL_LOC NOC_NMU512_X1Y14 [get_bd_intf_pins axis_noc/S01_AXIS]
    set_property CONFIG.PHYSICAL_LOC NOC_NSU512_X0Y14 [get_bd_intf_pins axis_noc/M00_AXIS]
  } elseif { $ntt_psi == 32 } {
    set_property CONFIG.PHYSICAL_LOC NOC_NMU512_X0Y0  [get_bd_intf_pins axis_noc/S00_AXIS]
    set_property CONFIG.PHYSICAL_LOC NOC_NSU512_X1Y0  [get_bd_intf_pins axis_noc/M01_AXIS]
    set_property CONFIG.PHYSICAL_LOC NOC_NMU512_X1Y14 [get_bd_intf_pins axis_noc/S01_AXIS]
    set_property CONFIG.PHYSICAL_LOC NOC_NSU512_X0Y14 [get_bd_intf_pins axis_noc/M00_AXIS]
  } else {
    set_property CONFIG.PHYSICAL_LOC NOC_NMU512_X0Y0  [get_bd_intf_pins axis_noc/S00_AXIS]
    set_property CONFIG.PHYSICAL_LOC NOC_NSU512_X1Y0  [get_bd_intf_pins axis_noc/M01_AXIS]
    # Let the tool place axis_noc/S01_AXIS and axis_noc/M00_AXIS
  }

  ####################################
  # Transmit NOC/HBM mapping
  ####################################
  set _nsp_hpu::CPM_NOC_PINS_L   $cpm_noc_pins_l
  set _nsp_hpu::KSK_NOC_PINS_L   $ksk_noc_pins_l
  set _nsp_hpu::BSK_NOC_PINS_L   $bsk_noc_pins_l
  set _nsp_hpu::TRC_NOC_PINS_L   $trc_noc_pins_l
  set _nsp_hpu::CT_NOC_PINS_L    $ct_noc_pins_l
  set _nsp_hpu::GLWE_NOC_PINS_L  $glwe_noc_pins_l

  set _nsp_hpu::KSK_HBM_PORTS_L  $ksk_hbm_ports_l
  set _nsp_hpu::BSK_HBM_PORTS_L  $bsk_hbm_ports_l
  set _nsp_hpu::TRC_HBM_PORTS_L  $trc_hbm_ports_l
  set _nsp_hpu::CT_HBM_PORTS_L   $ct_hbm_ports_l
  set _nsp_hpu::GLWE_HBM_PORTS_L $glwe_hbm_ports_l


  ####################################
  # Restore instance
  ####################################
  # Restore current instance
  current_bd_instance $oldCurInst
}
