# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
# Main script to build the block design used in HPU.
# ==============================================================================================

################################################################
# create_hier_cell_core
################################################################
# Procedure to create entire design; Provide argument to make
# procedure reusable. If parentCell is "", will use root.
proc create_root_design { parentCell ntt_psi } {
  set parentObj [check_parent_root $parentCell]
  if { $parentObj == "" } { return }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj

  ####################################
  # get global var
  ####################################
  set SYS_FREQ $_nsp_hpu::SYS_FREQ
  set HBM_REF_FREQ $_nsp_hpu::HBM_REF_FREQ
  set PCIE_REF_FREQ $_nsp_hpu::PCIE_REF_FREQ

  set IRQ_NB   $_nsp_hpu::IRQ_NB
  set REGIF_NB $_nsp_hpu::REGIF_NB
  set REGIF_CLK_NB $_nsp_hpu::REGIF_CLK_NB

  set AXIL_DATA_W $_nsp_hpu::AXIL_DATA_W
  set AXIL_ADD_W  $_nsp_hpu::AXIL_ADD_W
  set AXI4_ADD_W  $_nsp_hpu::AXI4_ADD_W
  set AXIS_DATA_W $_nsp_hpu::AXIS_DATA_W

  set AXIS_DATA_BYTES $_nsp_hpu::AXIS_DATA_BYTES
  set AXIS_NOC_DATA_BYTE $_nsp_hpu::AXIS_NOC_DATA_BYTE

  set KSK_AXI_NB $_nsp_hpu::KSK_AXI_NB
  set BSK_AXI_NB $_nsp_hpu::BSK_AXI_NB
  set CT_AXI_NB $_nsp_hpu::CT_AXI_NB
  set GLWE_AXI_NB $_nsp_hpu::GLWE_AXI_NB
  set TRC_AXI_NB $_nsp_hpu::TRC_AXI_NB

  set HPU_KSK_HBM_BURST_MAX $_nsp_hpu::HPU_KSK_HBM_BURST_MAX
  set HPU_BSK_HBM_BURST_MAX $_nsp_hpu::HPU_BSK_HBM_BURST_MAX
  set HPU_CT_HBM_BURST_MAX $_nsp_hpu::HPU_CT_HBM_BURST_MAX
  set HPU_GLWE_HBM_BURST_MAX $_nsp_hpu::HPU_GLWE_HBM_BURST_MAX
  set HPU_TRC_HBM_BURST_MAX $_nsp_hpu::HPU_TRC_HBM_BURST_MAX

  set HPU_BSK_HBM_DATA_W $_nsp_hpu::HPU_BSK_HBM_DATA_W
  set HPU_KSK_HBM_DATA_W $_nsp_hpu::HPU_KSK_HBM_DATA_W
  set HPU_CT_HBM_DATA_W $_nsp_hpu::HPU_CT_HBM_DATA_W
  set HPU_GLWE_HBM_DATA_W $_nsp_hpu::HPU_GLWE_HBM_DATA_W
  set HPU_TRC_HBM_DATA_W $_nsp_hpu::HPU_TRC_HBM_DATA_W

  set ETH_AXI_NB $_nsp_hpu::ETH_AXI_NB
  set DMA_AXI_NB $_nsp_hpu::DMA_AXI_NB
  set ETH_QSFP_FREQ $_nsp_hpu::ETH_QSFP_FREQ

  ####################################
  # Create Ports
  ####################################
  # Design block ports created here, since the properties are known here.
  # == Clocks
  # Differential clocks
  set gt_pcie_refclk [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 gt_pcie_refclk ]
  set_property -dict [ list \
   CONFIG.FREQ_HZ [expr int($PCIE_REF_FREQ * 10**6)] \
   ] $gt_pcie_refclk

  set sys_clk0_0 [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 sys_clk0_0 ]
  set_property -dict [ list \
   CONFIG.FREQ_HZ [expr int($SYS_FREQ * 10**6)] \
   ] $sys_clk0_0

  set sys_clk0_1 [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 sys_clk0_1 ]
  set_property -dict [ list \
   CONFIG.FREQ_HZ [expr int($SYS_FREQ * 10**6)] \
   ] $sys_clk0_1

  set hbm_ref_clk_0 [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 hbm_ref_clk_0 ]
  set_property -dict [ list \
   CONFIG.FREQ_HZ [expr int($HBM_REF_FREQ * 10**6)] \
   ] $hbm_ref_clk_0

  set hbm_ref_clk_1 [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 hbm_ref_clk_1 ]
  set_property -dict [ list \
   CONFIG.FREQ_HZ [expr int($HBM_REF_FREQ * 10**6)] \
   ] $hbm_ref_clk_1

  # System clocks
  set clk_usr_0_0 [ create_bd_port -dir O -type clk clk_usr_0_0 ]
  set clk_usr_0_0_fr [ create_bd_port -dir O -type clk clk_usr_0_0_fr ]
  set clk_usr_1_0 [ create_bd_port -dir O -type clk clk_usr_1_0 ]
  set pl0_ref_clk_0 [ create_bd_port -dir O -type clk pl0_ref_clk_0 ]
  set clk_usr_0_0_ce [ create_bd_port -dir I clk_usr_0_0_ce]
  set clk_eth_cfg_0 [ create_bd_port -dir O -type clk clk_eth_cfg_0 ]

  # Association properties
  set prop_clk(clk_usr_0_0) ""
  set prop_clk(clk_usr_1_0) ""
  set prop_clk(pl0_ref_clk_0) ""

  # == Resets
  set resetn_usr_0_ic_0 [ create_bd_port -dir O -type rst resetn_usr_0_ic_0 ]
  set resetn_usr_0_ic_0_gated [ create_bd_port -dir I -type rst resetn_usr_0_ic_0_gated ]
  set resetn_usr_1_ic_0 [ create_bd_port -dir O -type rst resetn_usr_1_ic_0 ]
  set pl0_resetn_0 [ create_bd_port -dir O -type rst pl0_resetn_0 ]
  set resetn_eth_cfg_ic_0 [ create_bd_port -dir O -from 0 -to 0 -type rst resetn_eth_cfg_ic_0 ]

  # == PCIe
  set gt_pciea1 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:gt_rtl:1.0 gt_pciea1 ]

  # == DDR
  set CH0_DDR4_0_0 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:ddr4_rtl:1.0 CH0_DDR4_0_0 ]
  set CH0_DDR4_0_1 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:ddr4_rtl:1.0 CH0_DDR4_0_1 ]

  # == Interruptions
  set rtl_interrupt [ create_bd_port -dir I -from [expr $IRQ_NB - 1] -to 0 -type intr rtl_interrupt ]
  set_property -dict [ list \
   CONFIG.PortWidth $IRQ_NB \
 ] $rtl_interrupt

  # == HPU AXI stream
  # RPU interface
  set axis_m_lpd [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:axis_rtl:1.0 axis_m_lpd ]

  set axis_s_lpd [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:axis_rtl:1.0 axis_s_lpd ]
  set_property -dict [ list \
   CONFIG.HAS_TKEEP {0} \
   CONFIG.HAS_TLAST {0} \
   CONFIG.HAS_TREADY {1} \
   CONFIG.HAS_TSTRB {0} \
   CONFIG.LAYERED_METADATA {undef} \
   CONFIG.TDATA_NUM_BYTES $AXIS_DATA_BYTES \
   CONFIG.TDEST_WIDTH {0} \
   CONFIG.TID_WIDTH {0} \
   CONFIG.TUSER_WIDTH {0} \
   ] $axis_s_lpd

  # NOC interface
  set axis_s_tx [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:axis_rtl:1.0 axis_s_tx ]
  set axis_s_rx [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:axis_rtl:1.0 axis_s_rx ]
  set_property -dict [ list \
   CONFIG.HAS_TKEEP {0} \
   CONFIG.HAS_TLAST {0} \
   CONFIG.HAS_TREADY {1} \
   CONFIG.HAS_TSTRB {0} \
   CONFIG.LAYERED_METADATA {undef} \
   CONFIG.TDATA_NUM_BYTES $AXIS_NOC_DATA_BYTE \
   CONFIG.TDEST_WIDTH {0} \
   CONFIG.TID_WIDTH {0} \
   CONFIG.TUSER_WIDTH {0} \
   ] $axis_s_rx

  set axis_m_tx [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:axis_rtl:1.0 axis_m_tx ]
  set axis_m_rx [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:axis_rtl:1.0 axis_m_rx ]
  set_property -dict [ list \
   CONFIG.HAS_TKEEP {0} \
   CONFIG.HAS_TLAST {0} \
   CONFIG.HAS_TREADY {1} \
   CONFIG.HAS_TSTRB {0} \
   CONFIG.LAYERED_METADATA {undef} \
   CONFIG.TDATA_NUM_BYTES $AXIS_NOC_DATA_BYTE \
   CONFIG.TDEST_WIDTH {0} \
   CONFIG.TID_WIDTH {0} \
   CONFIG.TUSER_WIDTH {0} \
   ] $axis_m_rx

  if {$prop_clk(clk_usr_0_0) eq ""} {
    set prop_clk(clk_usr_0_0) "axis_s_lpd:axis_m_lpd:axis_s_tx:axis_s_rx:axis_m_tx:axis_m_rx"
  } else {
    set prop_clk(clk_usr_0_0) "$prop_clk(clk_usr_0_0):axis_s_lpd:axis_m_lpd:axis_s_tx:axis_s_rx:axis_m_tx:axis_m_rx"
  }

  # == HPU AXI-lite
  set axi_lpd [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 axi_lpd ]
  # we use some axi lite parameters : this net will be converted into axi4-lite after NOC
  set_property -dict [ list \
   CONFIG.ADDR_WIDTH $AXIL_ADD_W \
   CONFIG.DATA_WIDTH $AXIL_DATA_W \
   CONFIG.HAS_BURST {0} \
   CONFIG.HAS_CACHE {0} \
   CONFIG.HAS_LOCK {0} \
   CONFIG.PROTOCOL {AXI4} \
   ] $axi_lpd

  if {$prop_clk(pl0_ref_clk_0) eq ""} {
    set prop_clk(pl0_ref_clk_0) "axi_lpd"
  } else {
    set prop_clk(pl0_ref_clk_0) "$prop_clk(pl0_ref_clk_0):axi_lpd"
  }

  # == HPU to HBM
  set hpu_hbm_acs_l [list TRC \
                          CT \
                          GLWE \
                          BSK \
                          KSK]
  set axi_nb_l [list $TRC_AXI_NB \
                     $CT_AXI_NB \
                     $GLWE_AXI_NB \
                     $BSK_AXI_NB \
                     $KSK_AXI_NB]
  set data_w_l [list $HPU_TRC_HBM_DATA_W \
                     $HPU_CT_HBM_DATA_W \
                     $HPU_GLWE_HBM_DATA_W \
                     $HPU_BSK_HBM_DATA_W \
                     $HPU_KSK_HBM_DATA_W]
  set burst_length_l [list $HPU_TRC_HBM_BURST_MAX \
                           $HPU_CT_HBM_BURST_MAX \
                           $HPU_GLWE_HBM_BURST_MAX \
                           $HPU_BSK_HBM_BURST_MAX \
                           $HPU_KSK_HBM_BURST_MAX]
  set has_bresp_l [list 0 1 0 0 0]
  set read_outstanding_l [list 1 32 32 32 32]
  set write_outstanding_l [list 32 32 1 1 1]
  set read_write_mode_l [list WRITE_ONLY \
                              READ_WRITE \
                              READ_ONLY \
                              READ_ONLY \
                              READ_ONLY]

  for { set a 0}  {$a < [llength $hpu_hbm_acs_l]} {incr a} {
    set axi_nb [lindex $axi_nb_l $a]
    set data_w [lindex $data_w_l $a]
    set burst_length [lindex $burst_length_l $a]
    set prefix [lindex $hpu_hbm_acs_l $a]
    set has_bresp [lindex $has_bresp_l $a]
    set read_outstanding [lindex $read_outstanding_l $a]
    set write_outstanding [lindex $write_outstanding_l $a]
    set read_write_mode [lindex $read_write_mode_l $a]

    for { set i 0}  {$i < $axi_nb} {incr i} {
      set port [create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 ${prefix}_AXI_${i}]
      set_property -dict [ list \
       CONFIG.ADDR_WIDTH $AXI4_ADD_W \
       CONFIG.ARUSER_WIDTH {0} \
       CONFIG.AWUSER_WIDTH {0} \
       CONFIG.BUSER_WIDTH {0} \
       CONFIG.DATA_WIDTH $data_w \
       CONFIG.HAS_BRESP $has_bresp \
       CONFIG.HAS_BURST {1} \
       CONFIG.HAS_CACHE {0} \
       CONFIG.HAS_LOCK {0} \
       CONFIG.HAS_PROT {0} \
       CONFIG.HAS_QOS {1} \
       CONFIG.HAS_REGION {1} \
       CONFIG.HAS_RRESP {0} \
       CONFIG.HAS_WSTRB {1} \
       CONFIG.ID_WIDTH {0} \
       CONFIG.MAX_BURST_LENGTH $burst_length \
       CONFIG.NUM_READ_OUTSTANDING $read_outstanding \
       CONFIG.NUM_READ_THREADS {1} \
       CONFIG.NUM_WRITE_OUTSTANDING $write_outstanding \
       CONFIG.NUM_WRITE_THREADS {1} \
       CONFIG.PROTOCOL {AXI4} \
       CONFIG.READ_WRITE_MODE $read_write_mode \
       CONFIG.RUSER_BITS_PER_BYTE {0} \
       CONFIG.RUSER_WIDTH {0} \
       CONFIG.SUPPORTS_NARROW_BURST {0} \
       CONFIG.WUSER_BITS_PER_BYTE {0} \
       CONFIG.WUSER_WIDTH {0} \
      ] $port

      if {$prop_clk(clk_usr_0_0) eq ""} {
        set prop_clk(clk_usr_0_0) "${prefix}_AXI_${i}"
      } else {
        set prop_clk(clk_usr_0_0) "$prop_clk(clk_usr_0_0):${prefix}_AXI_${i}"
      }
    } ; # for i
  } ; # for a

  # == HPU AXI-lite NOC
  # this is an axi4-full configuration but connected to an axi-lite:
  # we use only the axi4-full address, not other features
  set port_s_regif [create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 S_REGIF_AXI_0]
  set_property -dict [ list \
   CONFIG.ADDR_WIDTH $AXI4_ADD_W \
   CONFIG.ARUSER_WIDTH {0} \
   CONFIG.AWUSER_WIDTH {0} \
   CONFIG.BUSER_WIDTH {0} \
   CONFIG.DATA_WIDTH $AXIL_DATA_W \
   CONFIG.HAS_BRESP {1} \
   CONFIG.HAS_BURST {0} \
   CONFIG.HAS_CACHE {0} \
   CONFIG.HAS_LOCK {0} \
   CONFIG.HAS_PROT {0} \
   CONFIG.HAS_QOS {0} \
   CONFIG.HAS_REGION {0} \
   CONFIG.HAS_RRESP {1} \
   CONFIG.HAS_WSTRB {1} \
   CONFIG.ID_WIDTH {0} \
   CONFIG.MAX_BURST_LENGTH {1} \
   CONFIG.NUM_READ_OUTSTANDING {1} \
   CONFIG.NUM_READ_THREADS {1} \
   CONFIG.NUM_WRITE_OUTSTANDING {1} \
   CONFIG.NUM_WRITE_THREADS {1} \
   CONFIG.PROTOCOL {AXI4} \
   CONFIG.READ_WRITE_MODE {READ_WRITE} \
   CONFIG.RUSER_BITS_PER_BYTE {0} \
   CONFIG.RUSER_WIDTH {0} \
   CONFIG.SUPPORTS_NARROW_BURST {0} \
   CONFIG.WUSER_BITS_PER_BYTE {0} \
   CONFIG.WUSER_WIDTH {0} \
  ] $port_s_regif

  if {$prop_clk(pl0_ref_clk_0) eq ""} {
    set prop_clk(pl0_ref_clk_0) "S_REGIF_AXI_0"
  } else {
    set prop_clk(pl0_ref_clk_0) "$prop_clk(pl0_ref_clk_0):S_REGIF_AXI_0"
  }

  for { set i 0}  {$i < $REGIF_NB} {incr i} {
    for { set j 0}  {$j < $REGIF_CLK_NB} {incr j} {
      set port [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 REGIF_AXI_${i}_${j} ]

      set_property -dict [ list \
       CONFIG.ADDR_WIDTH $AXI4_ADD_W \
       CONFIG.DATA_WIDTH $AXIL_DATA_W \
       CONFIG.PROTOCOL {AXI4LITE} \
       CONFIG.READ_WRITE_MODE {READ_WRITE} \
     ] $port

     if {$prop_clk(clk_usr_${j}_0) eq ""} {
       set prop_clk(clk_usr_${j}_0) "REGIF_AXI_${i}_${j}"
     } else {
       set prop_clk(clk_usr_${j}_0) "$prop_clk(clk_usr_${j}_0):REGIF_AXI_${i}_${j}"
     }
   }
  }

  # == Ethernet control via RPU

  # Axi lite loopback
  set port_s_eth_axi [create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 S_ETH_AXI_0]
  set_property -dict [ list \
   CONFIG.ADDR_WIDTH $AXI4_ADD_W \
   CONFIG.ARUSER_WIDTH {0} \
   CONFIG.AWUSER_WIDTH {0} \
   CONFIG.BUSER_WIDTH {0} \
   CONFIG.DATA_WIDTH $AXIL_DATA_W \
   CONFIG.HAS_BRESP {1} \
   CONFIG.HAS_BURST {0} \
   CONFIG.HAS_CACHE {0} \
   CONFIG.HAS_LOCK {0} \
   CONFIG.HAS_PROT {0} \
   CONFIG.HAS_QOS {0} \
   CONFIG.HAS_REGION {0} \
   CONFIG.HAS_RRESP {1} \
   CONFIG.HAS_WSTRB {1} \
   CONFIG.ID_WIDTH {0} \
   CONFIG.MAX_BURST_LENGTH {1} \
   CONFIG.NUM_READ_OUTSTANDING {1} \
   CONFIG.NUM_READ_THREADS {1} \
   CONFIG.NUM_WRITE_OUTSTANDING {1} \
   CONFIG.NUM_WRITE_THREADS {1} \
   CONFIG.PROTOCOL {AXI4} \
   CONFIG.READ_WRITE_MODE {READ_WRITE} \
   CONFIG.RUSER_BITS_PER_BYTE {0} \
   CONFIG.RUSER_WIDTH {0} \
   CONFIG.SUPPORTS_NARROW_BURST {0} \
   CONFIG.WUSER_BITS_PER_BYTE {0} \
   CONFIG.WUSER_WIDTH {0} \
  ] $port_s_eth_axi

  if {$prop_clk(pl0_ref_clk_0) eq ""} {
    set prop_clk(pl0_ref_clk_0) "S_ETH_AXI_0"
  } else {
    set prop_clk(pl0_ref_clk_0) "$prop_clk(pl0_ref_clk_0):S_ETH_AXI_0"
  }

  # == Clock port connections
  # Bus clock must be defined with a port clock
  set_property -dict [ list \
   CONFIG.ASSOCIATED_BUSIF $prop_clk(clk_usr_0_0) \
  ] [get_bd_port /clk_usr_0_0]

  set_property -dict [ list \
   CONFIG.ASSOCIATED_BUSIF $prop_clk(clk_usr_1_0) \
  ] [get_bd_port /clk_usr_1_0]

  set_property -dict [ list \
   CONFIG.ASSOCIATED_BUSIF $prop_clk(pl0_ref_clk_0) \
  ] [get_bd_ports /pl0_ref_clk_0]

  # == Ethernet via QSFP
  set GT_Serial [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:gt_rtl:1.0 GT_Serial ]

  set CLK_IN_D [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 CLK_IN_D ]
  set_property -dict [ list \
   CONFIG.FREQ_HZ [expr int($ETH_QSFP_FREQ * 10**6)] \
  ] $CLK_IN_D

  set ctl_tx_port0 [ create_bd_intf_port -mode Slave -vlnv xilinx.com:display_mrmac:mrmac_ctrl_ports:2.0 ctl_tx_port0 ]
  set ctl_tx_port1 [ create_bd_intf_port -mode Slave -vlnv xilinx.com:display_mrmac:mrmac_ctrl_ports:2.0 ctl_tx_port1 ]
  set ctl_tx_port2 [ create_bd_intf_port -mode Slave -vlnv xilinx.com:display_mrmac:mrmac_ctrl_ports:2.0 ctl_tx_port2 ]
  set ctl_tx_port3 [ create_bd_intf_port -mode Slave -vlnv xilinx.com:display_mrmac:mrmac_ctrl_ports:2.0 ctl_tx_port3 ]
  set stat_tx_port0 [ create_bd_intf_port -mode Master -vlnv xilinx.com:display_mrmac:mrmac_statistics_ports:2.0 stat_tx_port0 ]
  set stat_tx_port1 [ create_bd_intf_port -mode Master -vlnv xilinx.com:display_mrmac:mrmac_statistics_ports:2.0 stat_tx_port1 ]
  set stat_tx_port2 [ create_bd_intf_port -mode Master -vlnv xilinx.com:display_mrmac:mrmac_statistics_ports:2.0 stat_tx_port2 ]
  set stat_tx_port3 [ create_bd_intf_port -mode Master -vlnv xilinx.com:display_mrmac:mrmac_statistics_ports:2.0 stat_tx_port3 ]
  set stat_rx_port0 [ create_bd_intf_port -mode Master -vlnv xilinx.com:display_mrmac:mrmac_statistics_ports:2.0 stat_rx_port0 ]
  set stat_rx_port1 [ create_bd_intf_port -mode Master -vlnv xilinx.com:display_mrmac:mrmac_statistics_ports:2.0 stat_rx_port1 ]
  set stat_rx_port2 [ create_bd_intf_port -mode Master -vlnv xilinx.com:display_mrmac:mrmac_statistics_ports:2.0 stat_rx_port2 ]
  set stat_rx_port3 [ create_bd_intf_port -mode Master -vlnv xilinx.com:display_mrmac:mrmac_statistics_ports:2.0 stat_rx_port3 ]
  set tx_preamblein [ create_bd_intf_port -mode Slave -vlnv xilinx.com:display_mrmac:mrmac_statistics_ports:2.0 tx_preamblein ]
  set rx_preambleout [ create_bd_intf_port -mode Master -vlnv xilinx.com:display_mrmac:mrmac_statistics_ports:2.0 rx_preambleout ]
  set APB3_INTF [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:apb_rtl:1.0 APB3_INTF ]
  set apb3clk_quad [ create_bd_port -dir I -type clk -freq_hz 200000000 apb3clk_quad ]

  set tx_axi_clk   [ create_bd_port -dir I -from 3 -to 0 -type clk -freq_hz [expr int($ETH_QSFP_FREQ * 10**6)] tx_axi_clk ]
  set rx_axi_clk   [ create_bd_port -dir I -from 3 -to 0 -type clk -freq_hz [expr int($ETH_QSFP_FREQ * 10**6)] rx_axi_clk ]
  # theorical frequency cannot be reached
  set clk_axi_qsfp [ create_bd_port -dir O -type clk  clk_axi_qsfp ]

  set resetn_qsfp      [ create_bd_port -dir O -type rst resetn_qsfp ]
  set tx_core_reset [ create_bd_port -dir I -from 3 -to 0 -type rst tx_core_reset ]

  set_property -dict [ list \
   CONFIG.POLARITY {ACTIVE_HIGH} \
 ] $tx_core_reset

  set rx_core_reset [ create_bd_port -dir I -from 3 -to 0 -type rst rx_core_reset ]
  set_property -dict [ list \
   CONFIG.POLARITY {ACTIVE_HIGH} \
 ] $rx_core_reset

  set tx_serdes_reset [ create_bd_port -dir I -from 3 -to 0 -type rst tx_serdes_reset ]
  set_property -dict [ list \
   CONFIG.POLARITY {ACTIVE_HIGH} \
 ] $tx_serdes_reset

  set rx_serdes_reset [ create_bd_port -dir I -from 3 -to 0 -type rst rx_serdes_reset ]
  set_property -dict [ list \
   CONFIG.POLARITY {ACTIVE_HIGH} \
 ] $rx_serdes_reset

  set rx_flexif_reset [ create_bd_port -dir I -from 3 -to 0 -type rst rx_flexif_reset ]
  set_property -dict [ list \
   CONFIG.POLARITY {ACTIVE_HIGH} \
 ] $rx_flexif_reset

  set tx_core_clk [ create_bd_port -dir I -from 3 -to 0 -type gt_usrclk tx_core_clk ]
  set_property -dict [ list \
   CONFIG.FREQ_HZ {644531000} \
 ] $tx_core_clk

  set rx_core_clk [ create_bd_port -dir I -from 3 -to 0 -type gt_usrclk rx_core_clk ]
  set_property -dict [ list \
   CONFIG.FREQ_HZ {644531000} \
 ] $rx_core_clk

  set rx_serdes_clk [ create_bd_port -dir I -from 3 -to 0 -type gt_usrclk rx_serdes_clk ]
  set_property -dict [ list \
   CONFIG.FREQ_HZ {644531000} \
 ] $rx_serdes_clk

  set tx_alt_serdes_clk [ create_bd_port -dir I -from 3 -to 0 -type gt_usrclk tx_alt_serdes_clk ]
  set_property -dict [ list \
   CONFIG.FREQ_HZ {322266000} \
 ] $tx_alt_serdes_clk

  set rx_alt_serdes_clk [ create_bd_port -dir I -from 3 -to 0 -type gt_usrclk rx_alt_serdes_clk ]
  set_property -dict [ list \
   CONFIG.FREQ_HZ {322266000} \
 ] $rx_alt_serdes_clk

  set tx_flexif_clk [ create_bd_port -dir I -from 3 -to 0 -type clk -freq_hz 250000000 tx_flexif_clk ]
  set rx_flexif_clk [ create_bd_port -dir I -from 3 -to 0 -type clk -freq_hz 250000000 rx_flexif_clk ]
  set tx_ts_clk [ create_bd_port -dir I -from 3 -to 0 -type clk -freq_hz 250000000 tx_ts_clk ]
  set rx_ts_clk [ create_bd_port -dir I -from 3 -to 0 -type clk -freq_hz 250000000 rx_ts_clk ]
  set pm_tick [ create_bd_port -dir I -from 3 -to 0 pm_tick ]
  set gt_tx_reset_done_out [ create_bd_port -dir O -from 3 -to 0 gt_tx_reset_done_out ]
  set gt_rx_reset_done_out [ create_bd_port -dir O -from 3 -to 0 gt_rx_reset_done_out ]
  set gt_reset_all_in [ create_bd_port -dir I -from 3 -to 0 gt_reset_all_in ]
  set gtpowergood_in [ create_bd_port -dir I gtpowergood_in ]
  set ch0_tx_usr_clk [ create_bd_port -dir O -from 0 -to 0 -type gt_usrclk ch0_tx_usr_clk ]
  set ch0_rx_usr_clk [ create_bd_port -dir O -from 0 -to 0 -type gt_usrclk ch0_rx_usr_clk ]
  set ch1_rx_usr_clk [ create_bd_port -dir O -from 0 -to 0 -type gt_usrclk ch1_rx_usr_clk ]
  set ch2_rx_usr_clk [ create_bd_port -dir O -from 0 -to 0 -type gt_usrclk ch2_rx_usr_clk ]
  set ch3_rx_usr_clk [ create_bd_port -dir O -from 0 -to 0 -type gt_usrclk ch3_rx_usr_clk ]
  set ch0_tx_usr_clk2 [ create_bd_port -dir O -from 0 -to 0 -type gt_usrclk ch0_tx_usr_clk2 ]
  set ch0_rx_usr_clk2 [ create_bd_port -dir O -from 0 -to 0 -type gt_usrclk ch0_rx_usr_clk2 ]
  set ch2_rx_usr_clk2 [ create_bd_port -dir O -from 0 -to 0 -type gt_usrclk ch2_rx_usr_clk2 ]
  set ch1_rx_usr_clk2 [ create_bd_port -dir O -from 0 -to 0 -type gt_usrclk ch1_rx_usr_clk2 ]
  set ch3_rx_usr_clk2 [ create_bd_port -dir O -from 0 -to 0 -type gt_usrclk ch3_rx_usr_clk2 ]
  set tx_axis_tdata0 [ create_bd_port -dir I -from 63 -to 0 tx_axis_tdata0 ]
  set tx_axis_tdata2 [ create_bd_port -dir I -from 63 -to 0 tx_axis_tdata2 ]
  set tx_axis_tdata4 [ create_bd_port -dir I -from 63 -to 0 tx_axis_tdata4 ]
  set tx_axis_tdata6 [ create_bd_port -dir I -from 63 -to 0 tx_axis_tdata6 ]
  set tx_axis_tkeep_user0 [ create_bd_port -dir I -from 10 -to 0 tx_axis_tkeep_user0 ]
  set tx_axis_tkeep_user2 [ create_bd_port -dir I -from 10 -to 0 tx_axis_tkeep_user2 ]
  set tx_axis_tkeep_user4 [ create_bd_port -dir I -from 10 -to 0 tx_axis_tkeep_user4 ]
  set tx_axis_tkeep_user6 [ create_bd_port -dir I -from 10 -to 0 tx_axis_tkeep_user6 ]
  set tx_axis_tready_0 [ create_bd_port -dir O tx_axis_tready_0 ]
  set tx_axis_tlast_0 [ create_bd_port -dir I tx_axis_tlast_0 ]
  set tx_axis_tvalid_0 [ create_bd_port -dir I tx_axis_tvalid_0 ]
  set rx_axis_tdata0 [ create_bd_port -dir O -from 63 -to 0 rx_axis_tdata0 ]
  set rx_axis_tdata2 [ create_bd_port -dir O -from 63 -to 0 rx_axis_tdata2 ]
  set rx_axis_tdata4 [ create_bd_port -dir O -from 63 -to 0 rx_axis_tdata4 ]
  set rx_axis_tdata6 [ create_bd_port -dir O -from 63 -to 0 rx_axis_tdata6 ]
  set rx_axis_tkeep_user0 [ create_bd_port -dir O -from 10 -to 0 rx_axis_tkeep_user0 ]
  set rx_axis_tkeep_user2 [ create_bd_port -dir O -from 10 -to 0 rx_axis_tkeep_user2 ]
  set rx_axis_tkeep_user4 [ create_bd_port -dir O -from 10 -to 0 rx_axis_tkeep_user4 ]
  set rx_axis_tkeep_user6 [ create_bd_port -dir O -from 10 -to 0 rx_axis_tkeep_user6 ]
  set rx_axis_tlast_0 [ create_bd_port -dir O rx_axis_tlast_0 ]
  set rx_axis_tvalid_0 [ create_bd_port -dir O rx_axis_tvalid_0 ]
  set gt_reset_tx_datapath_in [ create_bd_port -dir I -from 3 -to 0 gt_reset_tx_datapath_in ]
  set gt_reset_rx_datapath_in [ create_bd_port -dir I -from 3 -to 0 gt_reset_rx_datapath_in ]
  set pm_rdy [ create_bd_port -dir O -from 3 -to 0 pm_rdy ]
  set gtpowergood [ create_bd_port -dir O gtpowergood ]
  set ch0_rxusrclk [ create_bd_port -dir I -from 0 -to 0 -type gt_usrclk ch0_rxusrclk ]
  set_property -dict [ list \
   CONFIG.FREQ_HZ {322266000} \
 ] $ch0_rxusrclk
  set ch0_txusrclk [ create_bd_port -dir I -from 0 -to 0 -type gt_usrclk ch0_txusrclk ]
  set_property -dict [ list \
   CONFIG.FREQ_HZ {322266000} \
 ] $ch0_txusrclk
  set ch1_rxusrclk [ create_bd_port -dir I -from 0 -to 0 -type gt_usrclk ch1_rxusrclk ]
  set_property -dict [ list \
   CONFIG.FREQ_HZ {322266000} \
 ] $ch1_rxusrclk
  set ch1_txusrclk [ create_bd_port -dir I -from 0 -to 0 -type gt_usrclk ch1_txusrclk ]
  set_property -dict [ list \
   CONFIG.FREQ_HZ {322266000} \
 ] $ch1_txusrclk
  set ch2_rxusrclk [ create_bd_port -dir I -from 0 -to 0 -type gt_usrclk ch2_rxusrclk ]
  set_property -dict [ list \
   CONFIG.FREQ_HZ {322266000} \
 ] $ch2_rxusrclk
  set ch2_txusrclk [ create_bd_port -dir I -from 0 -to 0 -type gt_usrclk ch2_txusrclk ]
  set_property -dict [ list \
   CONFIG.FREQ_HZ {322266000} \
 ] $ch2_txusrclk
  set ch3_rxusrclk [ create_bd_port -dir I -from 0 -to 0 -type gt_usrclk ch3_rxusrclk ]
  set_property -dict [ list \
   CONFIG.FREQ_HZ {322266000} \
 ] $ch3_rxusrclk
  set ch3_txusrclk [ create_bd_port -dir I -from 0 -to 0 -type gt_usrclk ch3_txusrclk ]
  set_property -dict [ list \
   CONFIG.FREQ_HZ {322266000} \
 ] $ch3_txusrclk

  set ch0_loopback [ create_bd_port -dir I -from 2 -to 0 ch0_loopback ]
  set ch0_txrate   [ create_bd_port -dir I -from 7 -to 0 ch0_txrate ]
  set ch0_rxrate   [ create_bd_port -dir I -from 7 -to 0 ch0_rxrate ]

  set ch1_loopback [ create_bd_port -dir I -from 2 -to 0 ch1_loopback ]
  set ch1_txrate   [ create_bd_port -dir I -from 7 -to 0 ch1_txrate ]
  set ch1_rxrate   [ create_bd_port -dir I -from 7 -to 0 ch1_rxrate ]

  set ch2_loopback [ create_bd_port -dir I -from 2 -to 0 ch2_loopback ]
  set ch2_txrate   [ create_bd_port -dir I -from 7 -to 0 ch2_txrate ]
  set ch2_rxrate   [ create_bd_port -dir I -from 7 -to 0 ch2_rxrate ]

  set ch3_loopback [ create_bd_port -dir I -from 2 -to 0 ch3_loopback ]
  set ch3_txrate   [ create_bd_port -dir I -from 7 -to 0 ch3_txrate ]
  set ch3_rxrate   [ create_bd_port -dir I -from 7 -to 0 ch3_rxrate ]

  set gt_rxn_in_0  [ create_bd_port -dir I -from 3 -to 0 gt_rxn_in_0 ]
  set gt_rxp_in_0  [ create_bd_port -dir I -from 3 -to 0 gt_rxp_in_0 ]
  set gt_txn_out_0 [ create_bd_port -dir O -from 3 -to 0 gt_txn_out_0 ]
  set gt_txp_out_0 [ create_bd_port -dir O -from 3 -to 0 gt_txp_out_0 ]

  ####################################
  # Create Shell
  ####################################
  create_hier_cell_shell_wrapper [current_bd_instance .] shell_wrapper

  ####################################
  # Create NOC
  ####################################
  create_hier_cell_noc_wrapper [current_bd_instance .] noc_wrapper $ntt_psi

  ####################################
  # Create ethernet
  ####################################
  create_hier_cell_eth_wrapper [current_bd_instance .] eth_wrapper
  save_bd_design

  ####################################
  # Port Connections
  ####################################
  # == Clocks
  connect_bd_intf_net -intf_net sys_clk0_0     [get_bd_intf_ports /sys_clk0_0]     [get_bd_intf_pins noc_wrapper/sys_clk0_0]
  connect_bd_intf_net -intf_net sys_clk0_1     [get_bd_intf_ports /sys_clk0_1]     [get_bd_intf_pins noc_wrapper/sys_clk0_1]
  connect_bd_intf_net -intf_net hbm_ref_clk_0  [get_bd_intf_ports /hbm_ref_clk_0]  [get_bd_intf_pins noc_wrapper/hbm_ref_clk_0]
  connect_bd_intf_net -intf_net hbm_ref_clk_1  [get_bd_intf_ports /hbm_ref_clk_1]  [get_bd_intf_pins noc_wrapper/hbm_ref_clk_1]
  connect_bd_intf_net -intf_net gt_pcie_refclk [get_bd_intf_ports /gt_pcie_refclk] [get_bd_intf_pins shell_wrapper/gt_pcie_refclk]

  connect_bd_net -net pl0_ref_clk  [get_bd_ports /pl0_ref_clk_0]  [get_bd_pins shell_wrapper/pl0_ref_clk_0]
  connect_bd_net -net clk_usr_0    [get_bd_ports /clk_usr_0_0]    [get_bd_pins shell_wrapper/clk_usr_0_0]
  connect_bd_net -net clk_usr_0_fr [get_bd_ports /clk_usr_0_0_fr] [get_bd_pins shell_wrapper/clk_usr_0_0_fr]
  connect_bd_net -net clk_usr_1    [get_bd_ports /clk_usr_1_0]    [get_bd_pins shell_wrapper/clk_usr_1_0]
  connect_bd_net -net clk_usr_0_ce [get_bd_ports /clk_usr_0_0_ce] [get_bd_pins shell_wrapper/clk_usr_0_0_ce]

  # == Resets
  connect_bd_net -net pl0_resetn      [get_bd_ports /pl0_resetn_0]      [get_bd_pins shell_wrapper/pl0_resetn_0]
  connect_bd_net -net resetn_usr_0_ic [get_bd_ports /resetn_usr_0_ic_0] [get_bd_pins shell_wrapper/resetn_usr_0_ic_0]
  connect_bd_net -net resetn_usr_0_ic_gated $resetn_usr_0_ic_0_gated    [get_bd_pins shell_wrapper/resetn_usr_0_ic_0_gated]
  connect_bd_net -net resetn_usr_1_ic [get_bd_ports /resetn_usr_1_ic_0] [get_bd_pins shell_wrapper/resetn_usr_1_ic_0]

  # == PCIe
  connect_bd_intf_net -intf_net gt_pciea1 [get_bd_intf_ports /gt_pciea1] [get_bd_intf_pins shell_wrapper/gt_pciea1]

  # == DDR
  connect_bd_intf_net -intf_net CH0_DDR4_0_0 [get_bd_intf_ports /CH0_DDR4_0_0] [get_bd_intf_pins noc_wrapper/CH0_DDR4_0_0]
  connect_bd_intf_net -intf_net CH0_DDR4_0_1 [get_bd_intf_ports /CH0_DDR4_0_1] [get_bd_intf_pins noc_wrapper/CH0_DDR4_0_1]

  # == Interruptions
  connect_bd_net -net rtl_interrupt [get_bd_ports /rtl_interrupt] [get_bd_pins shell_wrapper/rtl_interrupt]

  # == HPU AXI stream
  connect_bd_intf_net -intf_net axis_m_lpd [get_bd_intf_ports /axis_m_lpd] [get_bd_intf_pins shell_wrapper/axis_m_lpd]
  connect_bd_intf_net -intf_net axis_m_rx  [get_bd_intf_ports /axis_m_rx]  [get_bd_intf_pins noc_wrapper/axis_m_rx]
  connect_bd_intf_net -intf_net axis_m_tx  [get_bd_intf_ports /axis_m_tx]  [get_bd_intf_pins noc_wrapper/axis_m_tx]

  connect_bd_intf_net -intf_net axis_s_lpd [get_bd_intf_ports /axis_s_lpd] [get_bd_intf_pins shell_wrapper/axis_s_lpd]
  connect_bd_intf_net -intf_net axis_s_rx  [get_bd_intf_ports /axis_s_rx]  [get_bd_intf_pins noc_wrapper/axis_s_rx]
  connect_bd_intf_net -intf_net axis_s_tx  [get_bd_intf_ports /axis_s_tx]  [get_bd_intf_pins noc_wrapper/axis_s_tx]

  # == HPU AXI-lite
  connect_bd_intf_net -intf_net axi_lpd [get_bd_intf_ports /axi_lpd] [get_bd_intf_pins shell_wrapper/axi_lpd]

  # == HPU to HBM
  for { set a 0}  {$a < [llength $hpu_hbm_acs_l]} {incr a} {
    set prefix [lindex $hpu_hbm_acs_l $a]
    set axi_nb [lindex $axi_nb_l $a]
    for { set i 0}  {$i < $axi_nb} {incr i} {
      set name "${prefix}_AXI_${i}"
      connect_bd_intf_net -intf_net $name [get_bd_intf_ports /${name}] [get_bd_intf_pins noc_wrapper/${name}]
    }
  }

  # == HPU AXI-lite NOC
  for {set i 0}  {$i < $REGIF_NB} {incr i} {
    for {set j 0}  {$j < $REGIF_CLK_NB} {incr j} {
      set name "REGIF_AXI_${i}_${j}"
      connect_bd_intf_net -intf_net $name [get_bd_intf_ports /$name] [get_bd_intf_pins noc_wrapper/${name}]
    }
  }

  connect_bd_intf_net -intf_net S_REGIF_AXI_0 [get_bd_intf_ports /S_REGIF_AXI_0] [get_bd_intf_pins noc_wrapper/S_REGIF_AXI_0]

  # RPU to Ethernet
  connect_bd_intf_net  -intf_net s_eth_axi_loopback  [get_bd_intf_ports S_ETH_AXI_0] [get_bd_intf_pins noc_wrapper/S_ETH_AXI_0]

  # == Ethernet
  connect_bd_intf_net -intf_net APB3_INTF                  [get_bd_intf_ports APB3_INTF] [get_bd_intf_pins eth_wrapper/APB3_INTF]
  connect_bd_intf_net -intf_net CLK_IN_D                   [get_bd_intf_ports CLK_IN_D] [get_bd_intf_pins eth_wrapper/CLK_IN_D]
  connect_bd_intf_net -intf_net ctl_tx_port0               [get_bd_intf_ports ctl_tx_port0] [get_bd_intf_pins eth_wrapper/ctl_tx_port0]
  connect_bd_intf_net -intf_net ctl_tx_port1               [get_bd_intf_ports ctl_tx_port1] [get_bd_intf_pins eth_wrapper/ctl_tx_port1]
  connect_bd_intf_net -intf_net ctl_tx_port2               [get_bd_intf_ports ctl_tx_port2] [get_bd_intf_pins eth_wrapper/ctl_tx_port2]
  connect_bd_intf_net -intf_net ctl_tx_port3               [get_bd_intf_ports ctl_tx_port3] [get_bd_intf_pins eth_wrapper/ctl_tx_port3]
  connect_bd_intf_net -intf_net gt_quad_base_GT_Serial     [get_bd_intf_ports GT_Serial] [get_bd_intf_pins eth_wrapper/GT_Serial]
  connect_bd_intf_net -intf_net eth_wrapper_rx_preambleout [get_bd_intf_ports rx_preambleout] [get_bd_intf_pins eth_wrapper/rx_preambleout]
  connect_bd_intf_net -intf_net eth_wrapper_stat_rx_port0  [get_bd_intf_ports stat_rx_port0] [get_bd_intf_pins eth_wrapper/stat_rx_port0]
  connect_bd_intf_net -intf_net eth_wrapper_stat_rx_port1  [get_bd_intf_ports stat_rx_port1] [get_bd_intf_pins eth_wrapper/stat_rx_port1]
  connect_bd_intf_net -intf_net eth_wrapper_stat_rx_port2  [get_bd_intf_ports stat_rx_port2] [get_bd_intf_pins eth_wrapper/stat_rx_port2]
  connect_bd_intf_net -intf_net eth_wrapper_stat_rx_port3  [get_bd_intf_ports stat_rx_port3] [get_bd_intf_pins eth_wrapper/stat_rx_port3]
  connect_bd_intf_net -intf_net eth_wrapper_stat_tx_port0  [get_bd_intf_ports stat_tx_port0] [get_bd_intf_pins eth_wrapper/stat_tx_port0]
  connect_bd_intf_net -intf_net eth_wrapper_stat_tx_port1  [get_bd_intf_ports stat_tx_port1] [get_bd_intf_pins eth_wrapper/stat_tx_port1]
  connect_bd_intf_net -intf_net eth_wrapper_stat_tx_port2  [get_bd_intf_ports stat_tx_port2] [get_bd_intf_pins eth_wrapper/stat_tx_port2]
  connect_bd_intf_net -intf_net eth_wrapper_stat_tx_port3  [get_bd_intf_ports stat_tx_port3] [get_bd_intf_pins eth_wrapper/stat_tx_port3]
  connect_bd_intf_net -intf_net tx_preamblein              [get_bd_intf_ports tx_preamblein] [get_bd_intf_pins eth_wrapper/tx_preamblein]

  connect_bd_net -net apb3clk_quad                     [get_bd_ports apb3clk_quad] [get_bd_pins eth_wrapper/apb3clk_quad]
  connect_bd_net -net ch0_loopback                     [get_bd_ports ch0_loopback] [get_bd_pins eth_wrapper/ch0_loopback]
  connect_bd_net -net ch0_rxrate                       [get_bd_ports ch0_rxrate] [get_bd_pins eth_wrapper/ch0_rxrate]
  connect_bd_net -net ch0_rxusrclk                     [get_bd_ports ch0_rxusrclk] [get_bd_pins eth_wrapper/ch0_rxusrclk]
  connect_bd_net -net ch0_txrate                       [get_bd_ports ch0_txrate] [get_bd_pins eth_wrapper/ch0_txrate]
  connect_bd_net -net ch0_txusrclk                     [get_bd_ports ch0_txusrclk] [get_bd_pins eth_wrapper/ch0_txusrclk]
  connect_bd_net -net ch1_loopback                     [get_bd_ports ch1_loopback] [get_bd_pins eth_wrapper/ch1_loopback]
  connect_bd_net -net ch1_rxrate                       [get_bd_ports ch1_rxrate] [get_bd_pins eth_wrapper/ch1_rxrate]
  connect_bd_net -net ch1_rxusrclk                     [get_bd_ports ch1_rxusrclk] [get_bd_pins eth_wrapper/ch1_rxusrclk]
  connect_bd_net -net ch1_txrate                       [get_bd_ports ch1_txrate] [get_bd_pins eth_wrapper/ch1_txrate]
  connect_bd_net -net ch1_txusrclk                     [get_bd_ports ch1_txusrclk] [get_bd_pins eth_wrapper/ch1_txusrclk]
  connect_bd_net -net ch2_loopback                     [get_bd_ports ch2_loopback] [get_bd_pins eth_wrapper/ch2_loopback]
  connect_bd_net -net ch2_rxrate                       [get_bd_ports ch2_rxrate] [get_bd_pins eth_wrapper/ch2_rxrate]
  connect_bd_net -net ch2_rxusrclk                     [get_bd_ports ch2_rxusrclk] [get_bd_pins eth_wrapper/ch2_rxusrclk]
  connect_bd_net -net ch2_txrate                       [get_bd_ports ch2_txrate] [get_bd_pins eth_wrapper/ch2_txrate]
  connect_bd_net -net ch2_txusrclk                     [get_bd_ports ch2_txusrclk] [get_bd_pins eth_wrapper/ch2_txusrclk]
  connect_bd_net -net ch3_loopback                     [get_bd_ports ch3_loopback] [get_bd_pins eth_wrapper/ch3_loopback]
  connect_bd_net -net ch3_rxrate                       [get_bd_ports ch3_rxrate] [get_bd_pins eth_wrapper/ch3_rxrate]
  connect_bd_net -net ch3_rxusrclk                     [get_bd_ports ch3_rxusrclk] [get_bd_pins eth_wrapper/ch3_rxusrclk]
  connect_bd_net -net ch3_txrate                       [get_bd_ports ch3_txrate] [get_bd_pins eth_wrapper/ch3_txrate]
  connect_bd_net -net ch3_txusrclk                     [get_bd_ports ch3_txusrclk] [get_bd_pins eth_wrapper/ch3_txusrclk]
  connect_bd_net -net gt_quad_base_gtpowergood         [get_bd_ports gtpowergood] [get_bd_pins eth_wrapper/gtpowergood]
  connect_bd_net -net gt_quad_base_txn                 [get_bd_ports gt_txn_out_0] [get_bd_pins eth_wrapper/gt_txn_out_0]
  connect_bd_net -net gt_quad_base_txp                 [get_bd_ports gt_txp_out_0] [get_bd_pins eth_wrapper/gt_txp_out_0]
  connect_bd_net -net gt_reset_all_in                  [get_bd_ports gt_reset_all_in] [get_bd_pins eth_wrapper/gt_reset_all_in]
  connect_bd_net -net gt_reset_rx_datapath_in          [get_bd_ports gt_reset_rx_datapath_in] [get_bd_pins eth_wrapper/gt_reset_rx_datapath_in]
  connect_bd_net -net gt_reset_tx_datapath_in          [get_bd_ports gt_reset_tx_datapath_in] [get_bd_pins eth_wrapper/gt_reset_tx_datapath_in]
  connect_bd_net -net gt_rxn_in_0                      [get_bd_ports gt_rxn_in_0] [get_bd_pins eth_wrapper/gt_rxn_in_0]
  connect_bd_net -net gt_rxp_in_0                      [get_bd_ports gt_rxp_in_0] [get_bd_pins eth_wrapper/gt_rxp_in_0]
  connect_bd_net -net gtpowergood_in                   [get_bd_ports gtpowergood_in] [get_bd_pins eth_wrapper/gtpowergood_in]
  connect_bd_net -net mbufg_gt_0_MBUFG_GT_O1           [get_bd_ports ch0_tx_usr_clk] [get_bd_pins eth_wrapper/ch0_tx_usr_clk]
  connect_bd_net -net mbufg_gt_0_MBUFG_GT_O2           [get_bd_ports ch0_tx_usr_clk2] [get_bd_pins eth_wrapper/ch0_tx_usr_clk2]
  connect_bd_net -net mbufg_gt_MBUFG_GT_O1             [get_bd_ports ch1_rx_usr_clk] [get_bd_pins eth_wrapper/ch1_rx_usr_clk]
  connect_bd_net -net mbufg_gt_MBUFG_GT_O2             [get_bd_ports ch1_rx_usr_clk2] [get_bd_pins eth_wrapper/ch1_rx_usr_clk2]
  connect_bd_net -net mbufg_gt_2_MBUFG_GT_O1           [get_bd_ports ch2_rx_usr_clk] [get_bd_pins eth_wrapper/ch2_rx_usr_clk]
  connect_bd_net -net mbufg_gt_2_MBUFG_GT_O2           [get_bd_ports ch2_rx_usr_clk2] [get_bd_pins eth_wrapper/ch2_rx_usr_clk2]
  connect_bd_net -net mbufg_gt_3_MBUFG_GT_O1           [get_bd_ports ch3_rx_usr_clk] [get_bd_pins eth_wrapper/ch3_rx_usr_clk]
  connect_bd_net -net mbufg_gt_3_MBUFG_GT_O2           [get_bd_ports ch3_rx_usr_clk2] [get_bd_pins eth_wrapper/ch3_rx_usr_clk2]
  connect_bd_net -net mbufg_gt_MBUFG_GT_O1_1           [get_bd_ports ch0_rx_usr_clk] [get_bd_pins eth_wrapper/ch0_rx_usr_clk]
  connect_bd_net -net mbufg_gt_MBUFG_GT_O2_1           [get_bd_ports ch0_rx_usr_clk2] [get_bd_pins eth_wrapper/ch0_rx_usr_clk2]
  connect_bd_net -net eth_wrapper_gt_rx_reset_done_out [get_bd_ports gt_rx_reset_done_out] [get_bd_pins eth_wrapper/gt_rx_reset_done_out]
  connect_bd_net -net eth_wrapper_gt_tx_reset_done_out [get_bd_ports gt_tx_reset_done_out] [get_bd_pins eth_wrapper/gt_tx_reset_done_out]
  connect_bd_net -net eth_wrapper_pm_rdy               [get_bd_ports pm_rdy] [get_bd_pins eth_wrapper/pm_rdy]
  connect_bd_net -net eth_wrapper_rx_axis_tdata0       [get_bd_ports rx_axis_tdata0] [get_bd_pins eth_wrapper/rx_axis_tdata0]
  connect_bd_net -net eth_wrapper_rx_axis_tdata2       [get_bd_ports rx_axis_tdata2] [get_bd_pins eth_wrapper/rx_axis_tdata2]
  connect_bd_net -net eth_wrapper_rx_axis_tdata4       [get_bd_ports rx_axis_tdata4] [get_bd_pins eth_wrapper/rx_axis_tdata4]
  connect_bd_net -net eth_wrapper_rx_axis_tdata6       [get_bd_ports rx_axis_tdata6] [get_bd_pins eth_wrapper/rx_axis_tdata6]
  connect_bd_net -net eth_wrapper_rx_axis_tkeep_user0  [get_bd_ports rx_axis_tkeep_user0] [get_bd_pins eth_wrapper/rx_axis_tkeep_user0]
  connect_bd_net -net eth_wrapper_rx_axis_tkeep_user2  [get_bd_ports rx_axis_tkeep_user2] [get_bd_pins eth_wrapper/rx_axis_tkeep_user2]
  connect_bd_net -net eth_wrapper_rx_axis_tkeep_user4  [get_bd_ports rx_axis_tkeep_user4] [get_bd_pins eth_wrapper/rx_axis_tkeep_user4]
  connect_bd_net -net eth_wrapper_rx_axis_tkeep_user6  [get_bd_ports rx_axis_tkeep_user6] [get_bd_pins eth_wrapper/rx_axis_tkeep_user6]
  connect_bd_net -net eth_wrapper_rx_axis_tlast_0      [get_bd_ports rx_axis_tlast_0] [get_bd_pins eth_wrapper/rx_axis_tlast_0]
  connect_bd_net -net eth_wrapper_rx_axis_tvalid_0     [get_bd_ports rx_axis_tvalid_0] [get_bd_pins eth_wrapper/rx_axis_tvalid_0]
  connect_bd_net -net eth_wrapper_tx_axis_tready_0     [get_bd_ports tx_axis_tready_0] [get_bd_pins eth_wrapper/tx_axis_tready_0]
  connect_bd_net -net pm_tick                          [get_bd_ports pm_tick] [get_bd_pins eth_wrapper/pm_tick]
  connect_bd_net -net rx_alt_serdes_clk                [get_bd_ports rx_alt_serdes_clk] [get_bd_pins eth_wrapper/rx_alt_serdes_clk]
  connect_bd_net -net rx_axi_clk                       [get_bd_ports rx_axi_clk] [get_bd_pins eth_wrapper/rx_axi_clk]
  connect_bd_net -net rx_core_clk                      [get_bd_ports rx_core_clk] [get_bd_pins eth_wrapper/rx_core_clk]
  connect_bd_net -net rx_core_reset                    [get_bd_ports rx_core_reset] [get_bd_pins eth_wrapper/rx_core_reset]
  connect_bd_net -net rx_flexif_clk                    [get_bd_ports rx_flexif_clk] [get_bd_pins eth_wrapper/rx_flexif_clk]
  connect_bd_net -net rx_flexif_reset                  [get_bd_ports rx_flexif_reset] [get_bd_pins eth_wrapper/rx_flexif_reset]
  connect_bd_net -net rx_serdes_clk                    [get_bd_ports rx_serdes_clk] [get_bd_pins eth_wrapper/rx_serdes_clk]
  connect_bd_net -net rx_serdes_reset                  [get_bd_ports rx_serdes_reset] [get_bd_pins eth_wrapper/rx_serdes_reset]
  connect_bd_net -net rx_ts_clk                        [get_bd_ports rx_ts_clk] [get_bd_pins eth_wrapper/rx_ts_clk]
  connect_bd_net -net tx_alt_serdes_clk                [get_bd_ports tx_alt_serdes_clk] [get_bd_pins eth_wrapper/tx_alt_serdes_clk]
  connect_bd_net -net tx_axi_clk                       [get_bd_ports tx_axi_clk] [get_bd_pins eth_wrapper/tx_axi_clk]
  connect_bd_net -net tx_axis_tdata0                   [get_bd_ports tx_axis_tdata0] [get_bd_pins eth_wrapper/tx_axis_tdata0]
  connect_bd_net -net tx_axis_tdata2                   [get_bd_ports tx_axis_tdata2] [get_bd_pins eth_wrapper/tx_axis_tdata2]
  connect_bd_net -net tx_axis_tdata4                   [get_bd_ports tx_axis_tdata4] [get_bd_pins eth_wrapper/tx_axis_tdata4]
  connect_bd_net -net tx_axis_tdata6                   [get_bd_ports tx_axis_tdata6] [get_bd_pins eth_wrapper/tx_axis_tdata6]
  connect_bd_net -net tx_axis_tkeep_user0              [get_bd_ports tx_axis_tkeep_user0] [get_bd_pins eth_wrapper/tx_axis_tkeep_user0]
  connect_bd_net -net tx_axis_tkeep_user2              [get_bd_ports tx_axis_tkeep_user2] [get_bd_pins eth_wrapper/tx_axis_tkeep_user2]
  connect_bd_net -net tx_axis_tkeep_user4              [get_bd_ports tx_axis_tkeep_user4] [get_bd_pins eth_wrapper/tx_axis_tkeep_user4]
  connect_bd_net -net tx_axis_tkeep_user6              [get_bd_ports tx_axis_tkeep_user6] [get_bd_pins eth_wrapper/tx_axis_tkeep_user6]
  connect_bd_net -net tx_axis_tlast_0                  [get_bd_ports tx_axis_tlast_0] [get_bd_pins eth_wrapper/tx_axis_tlast_0]
  connect_bd_net -net tx_axis_tvalid_0                 [get_bd_ports tx_axis_tvalid_0] [get_bd_pins eth_wrapper/tx_axis_tvalid_0]
  connect_bd_net -net tx_core_clk                      [get_bd_ports tx_core_clk] [get_bd_pins eth_wrapper/tx_core_clk]
  connect_bd_net -net tx_core_reset                    [get_bd_ports tx_core_reset] [get_bd_pins eth_wrapper/tx_core_reset]
  connect_bd_net -net tx_flexif_clk                    [get_bd_ports tx_flexif_clk] [get_bd_pins eth_wrapper/tx_flexif_clk]
  connect_bd_net -net tx_serdes_reset                  [get_bd_ports tx_serdes_reset] [get_bd_pins eth_wrapper/tx_serdes_reset]
  connect_bd_net -net tx_ts_clk                        [get_bd_ports tx_ts_clk] [get_bd_pins eth_wrapper/tx_ts_clk]

  connect_bd_net [get_bd_ports clk_axi_qsfp]           [get_bd_pins shell_wrapper/clk_eth_qsfp_0]
  connect_bd_net [get_bd_ports resetn_qsfp]               [get_bd_pins shell_wrapper/resetn_eth_qsfp_ic_0]

  ####################################
  # Internal Connections
  ####################################
  connect_bd_net -net pl0_ref_clk [get_bd_pins shell_wrapper/pl0_ref_clk_0] \
                                        [get_bd_pins noc_wrapper/mgmt_clk] \
                                        [get_bd_pins noc_wrapper/sregif_clk] -boundary_type upper
  connect_bd_net -net clk_usr_0   [get_bd_pins shell_wrapper/clk_usr_0_0] \
                                        [get_bd_pins noc_wrapper/hpu_noc_clk] \
                                        [get_bd_pins noc_wrapper/mregif_0_clk] -boundary_type upper
  connect_bd_net -net clk_usr_1   [get_bd_pins shell_wrapper/clk_usr_1_0] \
                                        [get_bd_pins noc_wrapper/mregif_1_clk] -boundary_type upper
  connect_bd_net [get_bd_pins noc_wrapper/mregif_0_rst_n] \
                                        $resetn_usr_0_ic_0_gated -boundary_type upper
  connect_bd_net [get_bd_pins noc_wrapper/mregif_1_rst_n] \
                                        [get_bd_pins shell_wrapper/resetn_usr_1_ic_0] -boundary_type upper

  connect_bd_net [get_bd_pins noc_wrapper/eth_clk]   [get_bd_pins shell_wrapper/clk_eth_cfg_0] [get_bd_ports clk_eth_cfg_0] -boundary_type upper
  connect_bd_net [get_bd_pins noc_wrapper/eth_rst_n] [get_bd_pins shell_wrapper/resetn_eth_cfg_ic_0] [get_bd_ports resetn_eth_cfg_ic_0] -boundary_type upper

  # MGMT
  connect_bd_intf_net -intf_net s_axi_pcie_mgmt_slr0 [get_bd_intf_pins shell_wrapper/s_axi_pcie_mgmt_slr0] [get_bd_intf_pins noc_wrapper/s_axi_pcie_mgmt_slr0]
  connect_bd_intf_net -intf_net s_noc_pcm_tandem [get_bd_intf_pins shell_wrapper/s_noc_pcm_tandem] [get_bd_intf_pins noc_wrapper/s_axi_tandem_loopback]

  # CPM NOC
  connect_bd_intf_net -intf_net cpm_pcie_noc_0 [get_bd_intf_pins shell_wrapper/cpm_pcie_noc_0] [get_bd_intf_pins noc_wrapper/cpm_pcie_noc_0]
  connect_bd_intf_net -intf_net cpm_pcie_noc_1 [get_bd_intf_pins shell_wrapper/cpm_pcie_noc_1] [get_bd_intf_pins noc_wrapper/cpm_pcie_noc_1]
  connect_bd_net -net cpm_pcie_noc_axi0_clk [get_bd_pins shell_wrapper/cpm_pcie_noc_axi0_clk] [get_bd_pins noc_wrapper/cpm_pcie_noc_axi0_clk]
  connect_bd_net -net cpm_pcie_noc_axi1_clk [get_bd_pins shell_wrapper/cpm_pcie_noc_axi1_clk] [get_bd_pins noc_wrapper/cpm_pcie_noc_axi1_clk]

  # PMC NOC
  connect_bd_intf_net -intf_net pmc_noc_axi_0 [get_bd_intf_pins shell_wrapper/pmc_noc_axi_0] [get_bd_intf_pins noc_wrapper/pmc_noc_axi_0]
  connect_bd_net -net pmc_axi_noc_axi0_clk [get_bd_pins shell_wrapper/pmc_axi_noc_axi0_clk] [get_bd_pins noc_wrapper/pmc_axi_noc_axi0_clk]
  connect_bd_net -net pmc_tandem_clk [get_bd_pins noc_wrapper/pmc_tandem_clk] [get_bd_pins shell_wrapper/pmc_tandem_clk]

  # LPD AXI NOC
  connect_bd_intf_net -intf_net lpd_axi_noc_0 [get_bd_intf_pins shell_wrapper/lpd_axi_noc_0] [get_bd_intf_pins noc_wrapper/lpd_axi_noc_0]
  connect_bd_net -net lpd_axi_noc_clk [get_bd_pins noc_wrapper/lpd_axi_noc_clk] [get_bd_pins shell_wrapper/lpd_axi_noc_clk]

  # Ethernet
  connect_bd_net      [get_bd_pins eth_wrapper/s_axi_aclk]    [get_bd_pins shell_wrapper/clk_eth_cfg_0]
  connect_bd_net      [get_bd_pins eth_wrapper/s_axi_aresetn] [get_bd_pins shell_wrapper/resetn_eth_cfg_ic_0]
  connect_bd_intf_net [get_bd_intf_pins eth_wrapper/s_axi]    [get_bd_intf_pins noc_wrapper/ETH_AXI_0]

  ####################################
  # Address
  ####################################

  # CPM
  # For each HBM PC
  for { set j 0}  {$j < 2} {incr j} {
    # CPM<i> use all the HBM
    for { set hbm_pc_idx 0}  {$hbm_pc_idx < 32} {incr hbm_pc_idx} {
      set hbm_pc_name [format "HBM%0d_PC%0d" [expr int($hbm_pc_idx/2)] [expr $hbm_pc_idx%2]]
      set add_ofs [expr $_nsp_hpu::HBM_ADD_OFS + $hbm_pc_idx * $_nsp_hpu::HBM_PC_RANGE]
      set noc_pin [lindex $_nsp_hpu::CPM_NOC_PINS_L $j]
      assign_bd_address -offset $add_ofs -range $_nsp_hpu::HBM_PC_RANGE -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_$j] [get_bd_addr_segs noc_wrapper/axi_noc_cips/$noc_pin/$hbm_pc_name] -force
    }
  }

  # CPM 0
  assign_bd_address -offset 0x020108000000 -range 0x08000000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs noc_wrapper/ddr_noc/axi_noc_mc_ddr4_0/S00_INI/C0_DDR_LOW0] -force
  assign_bd_address -offset 0x060000000000 -range 0x000800000000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs noc_wrapper/ddr_noc/axi_noc_mc_ddr4_1/S00_INI/C0_DDR_CH2] -force
  assign_bd_address -offset 0x020101010000 -range 0x00001000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/base_logic/gcq_m2r/S00_AXI/S00_AXI_Reg] -force
  assign_bd_address -offset 0x020101040000 -range 0x00001000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/clock_reset/pcie_mgmt_pdi_reset/pcie_mgmt_pdi_reset_gpio/S_AXI/Reg] -force
  assign_bd_address -offset 0x020101001000 -range 0x00001000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/base_logic/uuid_rom/S_AXI/reg0] -force

  # CPM 1
  assign_bd_address -offset 0x050080000000 -range 0x80000000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs noc_wrapper/ddr_noc/axi_noc_mc_ddr4_0/S01_INI/C1_DDR_CH1] -force
  assign_bd_address -offset 0x00000000     -range 0x80000000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs noc_wrapper/ddr_noc/axi_noc_mc_ddr4_0/S01_INI/C1_DDR_LOW0] -force
  assign_bd_address -offset 0x060000000000 -range 0x000800000000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs noc_wrapper/ddr_noc/axi_noc_mc_ddr4_1/S01_INI/C1_DDR_CH2] -force
  assign_bd_address -offset 0x020101010000 -range 0x00001000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/base_logic/gcq_m2r/S00_AXI/S00_AXI_Reg] -force
  assign_bd_address -offset 0x020101040000 -range 0x00001000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/clock_reset/pcie_mgmt_pdi_reset/pcie_mgmt_pdi_reset_gpio/S_AXI/Reg] -force
  assign_bd_address -offset 0x020101001000 -range 0x00001000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/base_logic/uuid_rom/S_AXI/reg0] -force

  # LPD
  assign_bd_address -offset 0x00000000 -range 0x80000000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/LPD_AXI_NOC_0] [get_bd_addr_segs noc_wrapper/ddr_noc/axi_noc_mc_ddr4_0/S00_INI/C0_DDR_LOW0] -force
  assign_bd_address -offset 0x80800000 -range 0x00001000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/M_AXI_LPD] [get_bd_addr_segs shell_wrapper/axi_to_axis/S_AXI/Mem0] -force
  assign_bd_address -offset 0x80010000 -range 0x00001000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/M_AXI_LPD] [get_bd_addr_segs shell_wrapper/base_logic/gcq_m2r/S01_AXI/S01_AXI_Reg] -force

  # NOC to PL
  set regif_add 0x80080000
  set regif_add_noc [expr 0x20100000000 + $regif_add]
  set regif_range 0x00010000
  assign_bd_address -offset $regif_add -range  [expr $ETH_AXI_NB + $DMA_AXI_NB * $REGIF_NB * $REGIF_CLK_NB * $regif_range] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/M_AXI_LPD] [get_bd_addr_segs /axi_lpd/Reg] -force
  for { set i 0}  {$i < $REGIF_NB} {incr i} {
    for { set j 0}  {$j < $REGIF_CLK_NB} {incr j} {
      # Address order : first 2nd clock, then second clock
      set n [expr $i * $REGIF_CLK_NB + ($REGIF_CLK_NB - 1 - $j)]
      assign_bd_address -offset [expr $regif_add_noc + $n * $regif_range] -range $regif_range -target_address_space [get_bd_addr_spaces /S_REGIF_AXI_0 ] [get_bd_addr_segs /REGIF_AXI_${i}_${j}/Reg] -force
    }
  }

  # Ethernet
  assign_bd_address -offset 0x201800C0000 -range 0x00010000 -target_address_space [get_bd_addr_spaces s_axi] [get_bd_addr_segs eth_wrapper/mrmac_0_core/s_axi/Reg] -force
  # APB3 not meant to be used
  assign_bd_address -offset 0xA4080000 -range 0x00010000 -target_address_space [get_bd_addr_spaces APB3_INTF] [get_bd_addr_segs eth_wrapper/mrmac_0_gt_wrapper/gt_quad_base/APB3_INTF/Reg] -force

  # PMC
  assign_bd_address -offset 0x050080000000 -range 0x80000000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/PMC_NOC_AXI_0] [get_bd_addr_segs noc_wrapper/ddr_noc/axi_noc_mc_ddr4_0/S00_INI/C0_DDR_CH1] -force
  assign_bd_address -offset 0x00000000 -range 0x80000000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/PMC_NOC_AXI_0] [get_bd_addr_segs noc_wrapper/ddr_noc/axi_noc_mc_ddr4_0/S00_INI/C0_DDR_LOW0] -force
  assign_bd_address -offset 0x060000000000 -range 0x000800000000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/PMC_NOC_AXI_0] [get_bd_addr_segs noc_wrapper/ddr_noc/axi_noc_mc_ddr4_1/S00_INI/C0_DDR_CH2] -force

  # HPU-HBM
  # BSK
  for { set i 0}  {$i < $_nsp_hpu::BSK_AXI_NB} {incr i} {
    set hbm_port_idx [lindex $_nsp_hpu::BSK_HBM_PORTS_L $i]
    set hbm_pc_idx [expr int($hbm_port_idx/2)]
    set hbm_pc_name [format "HBM%0d_PC%0d" [expr int($hbm_pc_idx/2)] [expr $hbm_pc_idx%2]]

    set add_ofs [expr $_nsp_hpu::HBM_ADD_OFS + $hbm_pc_idx * $_nsp_hpu::HBM_PC_RANGE]
    set noc_pin [lindex $_nsp_hpu::BSK_NOC_PINS_L $i]

    assign_bd_address -offset $add_ofs -range $_nsp_hpu::HBM_PC_RANGE -target_address_space [get_bd_addr_spaces BSK_AXI_${i}] [get_bd_addr_segs noc_wrapper/axi_noc_cips/$noc_pin/$hbm_pc_name] -force
  }
  # KSK
  for { set i 0}  {$i < $_nsp_hpu::KSK_AXI_NB} {incr i} {
    set hbm_port_idx [lindex $_nsp_hpu::KSK_HBM_PORTS_L $i]
    set hbm_pc_idx [expr int($hbm_port_idx/2)]
    set hbm_pc_name [format "HBM%0d_PC%0d" [expr int($hbm_pc_idx/2)] [expr $hbm_pc_idx%2]]

    set add_ofs [expr $_nsp_hpu::HBM_ADD_OFS + $hbm_pc_idx * $_nsp_hpu::HBM_PC_RANGE]
    set noc_pin [lindex $_nsp_hpu::KSK_NOC_PINS_L $i]

    assign_bd_address -offset $add_ofs -range $_nsp_hpu::HBM_PC_RANGE -target_address_space [get_bd_addr_spaces KSK_AXI_${i}] [get_bd_addr_segs noc_wrapper/axi_noc_cips/$noc_pin/$hbm_pc_name] -force
  }
  # CT
  for { set i 0}  {$i < $_nsp_hpu::CT_AXI_NB} {incr i} {
    set hbm_port_idx [lindex $_nsp_hpu::CT_HBM_PORTS_L $i]
    set hbm_pc_idx [expr int($hbm_port_idx/2)]
    set hbm_pc_name [format "HBM%0d_PC%0d" [expr int($hbm_pc_idx/2)] [expr $hbm_pc_idx%2]]

    set add_ofs [expr $_nsp_hpu::HBM_ADD_OFS + $hbm_pc_idx * $_nsp_hpu::HBM_PC_RANGE]
    set noc_pin [lindex $_nsp_hpu::CT_NOC_PINS_L $i]

    assign_bd_address -offset $add_ofs -range $_nsp_hpu::HBM_PC_RANGE -target_address_space [get_bd_addr_spaces CT_AXI_${i}] [get_bd_addr_segs noc_wrapper/axi_noc_cips/$noc_pin/$hbm_pc_name] -force
  }
  # TRC
  for { set i 0}  {$i < $_nsp_hpu::TRC_AXI_NB} {incr i} {
    set hbm_port_idx [lindex $_nsp_hpu::TRC_HBM_PORTS_L $i]
    set hbm_pc_idx [expr int($hbm_port_idx/2)]
    set hbm_pc_name [format "HBM%0d_PC%0d" [expr int($hbm_pc_idx/2)] [expr $hbm_pc_idx%2]]

    set add_ofs [expr $_nsp_hpu::HBM_ADD_OFS + $hbm_pc_idx * $_nsp_hpu::HBM_PC_RANGE]
    set noc_pin [lindex $_nsp_hpu::TRC_NOC_PINS_L $i]

    assign_bd_address -offset $add_ofs -range $_nsp_hpu::HBM_PC_RANGE -target_address_space [get_bd_addr_spaces TRC_AXI_${i}] [get_bd_addr_segs noc_wrapper/axi_noc_cips/$noc_pin/$hbm_pc_name] -force
  }
  # GLWE
  for { set i 0}  {$i < $_nsp_hpu::GLWE_AXI_NB} {incr i} {
    set hbm_port_idx [lindex $_nsp_hpu::GLWE_HBM_PORTS_L $i]
    set hbm_pc_idx [expr int($hbm_port_idx/2)]
    set hbm_pc_name [format "HBM%0d_PC%0d" [expr int($hbm_pc_idx/2)] [expr $hbm_pc_idx%2]]

    set add_ofs [expr $_nsp_hpu::HBM_ADD_OFS + $hbm_pc_idx * $_nsp_hpu::HBM_PC_RANGE]
    set noc_pin [lindex $_nsp_hpu::GLWE_NOC_PINS_L $i]

    assign_bd_address -offset $add_ofs -range $_nsp_hpu::HBM_PC_RANGE -target_address_space [get_bd_addr_spaces GLWE_AXI_${i}] [get_bd_addr_segs noc_wrapper/axi_noc_cips/$noc_pin/$hbm_pc_name] -force
  }

  # tandem mode
  assign_bd_address -offset 0x000102100000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_slave_boot_stream] -force
  assign_bd_address -offset 0x000101220000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_slave_boot] -force
  assign_bd_address -offset 0x000101220000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_slave_boot] -force
  assign_bd_address -offset 0x000102100000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_slave_boot_stream] -force

  ####################################
  # Address exclusion
  ####################################
  puts ">>>>>>>> Exclusion"
  # Exclude Address Segments
  exclude_bd_addr_seg -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs noc_wrapper/ddr_noc/axi_noc_mc_ddr4_0/S00_INI/C0_DDR_CH1]
  exclude_bd_addr_seg -offset 0x050080000000 -range 0x80000000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/LPD_AXI_NOC_0] [get_bd_addr_segs noc_wrapper/ddr_noc/axi_noc_mc_ddr4_0/S00_INI/C0_DDR_CH1]

  # PMC exclusions due to tandem mode
  exclude_bd_addr_seg -offset 0xFFA80000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_adma_0]
  exclude_bd_addr_seg -offset 0xFFA90000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_adma_1]
  exclude_bd_addr_seg -offset 0xFFAA0000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_adma_2]
  exclude_bd_addr_seg -offset 0xFFAB0000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_adma_3]
  exclude_bd_addr_seg -offset 0xFFAC0000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_adma_4]
  exclude_bd_addr_seg -offset 0xFFAD0000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_adma_5]
  exclude_bd_addr_seg -offset 0xFFAE0000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_adma_6]
  exclude_bd_addr_seg -offset 0xFFAF0000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_adma_7]
  exclude_bd_addr_seg -offset 0xFD5C0000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_apu_0]
  exclude_bd_addr_seg -offset 0x000100800000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_coresight_0]
  exclude_bd_addr_seg -offset 0x000100B80000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_coresight_fpd_atm]
  exclude_bd_addr_seg -offset 0x000100B70000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_coresight_fpd_stm]
  exclude_bd_addr_seg -offset 0x000100980000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_coresight_lpd_atm]
  exclude_bd_addr_seg -offset 0xFC000000 -range 0x01000000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_cpm]
  exclude_bd_addr_seg -offset 0xFD1A0000 -range 0x00140000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_crf_0]
  exclude_bd_addr_seg -offset 0xFF5E0000 -range 0x00300000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_crl_0]
  exclude_bd_addr_seg -offset 0x000101260000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_crp_0]
  exclude_bd_addr_seg -offset 0xFD360000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_fpd_afi_0]
  exclude_bd_addr_seg -offset 0xFD380000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_fpd_afi_2]
  exclude_bd_addr_seg -offset 0xFD5E0000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_fpd_cci_0]
  exclude_bd_addr_seg -offset 0xFD700000 -range 0x00100000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_fpd_gpv_0]
  exclude_bd_addr_seg -offset 0xFD000000 -range 0x00100000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_fpd_maincci_0]
  exclude_bd_addr_seg -offset 0xFD390000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_fpd_slave_xmpu_0]
  exclude_bd_addr_seg -offset 0xFD610000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_fpd_slcr_0]
  exclude_bd_addr_seg -offset 0xFD690000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_fpd_slcr_secure_0]
  exclude_bd_addr_seg -offset 0xFD5F0000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_fpd_smmu_0]
  exclude_bd_addr_seg -offset 0xFD800000 -range 0x00800000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_fpd_smmutcu_0]
  exclude_bd_addr_seg -offset 0xFF320000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_ipi_pmc]
  exclude_bd_addr_seg -offset 0xFF390000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_ipi_pmc_nobuf]
  exclude_bd_addr_seg -offset 0xFF310000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_ipi_psm]
  exclude_bd_addr_seg -offset 0xFF9B0000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_lpd_afi_0]
  exclude_bd_addr_seg -offset 0xFF0A0000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_lpd_iou_secure_slcr_0]
  exclude_bd_addr_seg -offset 0xFF080000 -range 0x00020000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_lpd_iou_slcr_0]
  exclude_bd_addr_seg -offset 0xFF410000 -range 0x00100000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_lpd_slcr_0]
  exclude_bd_addr_seg -offset 0xFF510000 -range 0x00040000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_lpd_slcr_secure_0]
  exclude_bd_addr_seg -offset 0xFF990000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_lpd_xppu_0]
  exclude_bd_addr_seg -offset 0xFF960000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_ocm_ctrl]
  exclude_bd_addr_seg -offset 0xFFFC0000 -range 0x00040000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_ocm_ram_0]
  exclude_bd_addr_seg -offset 0xFF980000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_ocm_xmpu_0]
  exclude_bd_addr_seg -offset 0x0001011E0000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_aes]
  exclude_bd_addr_seg -offset 0x0001011F0000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_bbram_ctrl]
  exclude_bd_addr_seg -offset 0x0001012D0000 -range 0x00001000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_cfi_cframe_0]
  exclude_bd_addr_seg -offset 0x0001012B0000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_cfu_apb_0]
  exclude_bd_addr_seg -offset 0x0001011C0000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_dma_0]
  exclude_bd_addr_seg -offset 0x0001011D0000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_dma_1]
  exclude_bd_addr_seg -offset 0x000101250000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_efuse_cache]
  exclude_bd_addr_seg -offset 0x000101240000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_efuse_ctrl]
  exclude_bd_addr_seg -offset 0x000101110000 -range 0x00050000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_global_0]
  exclude_bd_addr_seg -offset 0x000100280000 -range 0x00001000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_iomodule_0]
  exclude_bd_addr_seg -offset 0x000100310000 -range 0x00008000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_ppu1_mdm_0]
  exclude_bd_addr_seg -offset 0x000101030000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_qspi_0]
  exclude_bd_addr_seg -offset 0x000102000000 -range 0x00020000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_ram]
  exclude_bd_addr_seg -offset 0x000100240000 -range 0x00020000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_ram_data_cntlr]
  exclude_bd_addr_seg -offset 0x000100200000 -range 0x00040000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_ram_instr_cntlr]
  exclude_bd_addr_seg -offset 0x000106000000 -range 0x02000000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_ram_npi]
  exclude_bd_addr_seg -offset 0x000101200000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_rsa]
  exclude_bd_addr_seg -offset 0x0001012A0000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_rtc_0]
  exclude_bd_addr_seg -offset 0x000101210000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_sha]
  exclude_bd_addr_seg -offset 0x000101270000 -range 0x00030000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_sysmon_0]
  exclude_bd_addr_seg -offset 0x000100083000 -range 0x00001000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_tmr_inject_0]
  exclude_bd_addr_seg -offset 0x000100283000 -range 0x00001000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_tmr_manager_0]
  exclude_bd_addr_seg -offset 0x000101230000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_trng]
  exclude_bd_addr_seg -offset 0x0001012F0000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_xmpu_0]
  exclude_bd_addr_seg -offset 0x000101310000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_xppu_0]
  exclude_bd_addr_seg -offset 0x000101300000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_xppu_npi_0]
  exclude_bd_addr_seg -offset 0xFFC90000 -range 0x0000F000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_psm_global_reg]
  exclude_bd_addr_seg -offset 0xFFE90000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_r5_1_atcm_global]
  exclude_bd_addr_seg -offset 0xFFEB0000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_r5_1_btcm_global]
  exclude_bd_addr_seg -offset 0xFFE00000 -range 0x00040000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_r5_tcm_ram_global]
  exclude_bd_addr_seg -offset 0xFF9A0000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_rpu_0]
  exclude_bd_addr_seg -offset 0xFF130000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_scntr_0]
  exclude_bd_addr_seg -offset 0xFF140000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_scntrs_0]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_qspi_ospi_flash_0] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_coresight_apu_fun] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_coresight_apu_etf] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_coresight_apu_ela] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_coresight_apu_cti] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_coresight_a720_dbg] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_coresight_a720_cti] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_coresight_a720_pmu] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_coresight_a720_etm] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_coresight_a721_dbg] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_coresight_a721_cti] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_coresight_a721_pmu] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_coresight_a721_etm] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_coresight_cpm_rom] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_coresight_cpm_fun] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_coresight_cpm_ela2a] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_coresight_cpm_ela2b] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_coresight_cpm_ela2c] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_coresight_cpm_ela2d] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_coresight_cpm_atm] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_coresight_cpm_cti2a] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_coresight_cpm_cti2d] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0]
  exclude_bd_addr_seg -offset 0xFFA80000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_adma_0]
  exclude_bd_addr_seg -offset 0xFFA90000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_adma_1]
  exclude_bd_addr_seg -offset 0xFFAA0000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_adma_2]
  exclude_bd_addr_seg -offset 0xFFAB0000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_adma_3]
  exclude_bd_addr_seg -offset 0xFFAC0000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_adma_4]
  exclude_bd_addr_seg -offset 0xFFAD0000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_adma_5]
  exclude_bd_addr_seg -offset 0xFFAE0000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_adma_6]
  exclude_bd_addr_seg -offset 0xFFAF0000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_adma_7]
  exclude_bd_addr_seg -offset 0xFD5C0000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_apu_0]
  exclude_bd_addr_seg -offset 0x000100800000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_coresight_0]
  exclude_bd_addr_seg -offset 0x000100B80000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_coresight_fpd_atm]
  exclude_bd_addr_seg -offset 0x000100B70000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_coresight_fpd_stm]
  exclude_bd_addr_seg -offset 0x000100980000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_coresight_lpd_atm]
  exclude_bd_addr_seg -offset 0xFC000000 -range 0x01000000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_cpm]
  exclude_bd_addr_seg -offset 0xFD1A0000 -range 0x00140000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_crf_0]
  exclude_bd_addr_seg -offset 0xFF5E0000 -range 0x00300000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_crl_0]
  exclude_bd_addr_seg -offset 0x000101260000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_crp_0]
  exclude_bd_addr_seg -offset 0xFD360000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_fpd_afi_0]
  exclude_bd_addr_seg -offset 0xFD380000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_fpd_afi_2]
  exclude_bd_addr_seg -offset 0xFD5E0000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_fpd_cci_0]
  exclude_bd_addr_seg -offset 0xFD700000 -range 0x00100000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_fpd_gpv_0]
  exclude_bd_addr_seg -offset 0xFD000000 -range 0x00100000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_fpd_maincci_0]
  exclude_bd_addr_seg -offset 0xFD390000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_fpd_slave_xmpu_0]
  exclude_bd_addr_seg -offset 0xFD610000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_fpd_slcr_0]
  exclude_bd_addr_seg -offset 0xFD690000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_fpd_slcr_secure_0]
  exclude_bd_addr_seg -offset 0xFD5F0000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_fpd_smmu_0]
  exclude_bd_addr_seg -offset 0xFD800000 -range 0x00800000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_fpd_smmutcu_0]
  exclude_bd_addr_seg -offset 0xFF320000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_ipi_pmc]
  exclude_bd_addr_seg -offset 0xFF390000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_ipi_pmc_nobuf]
  exclude_bd_addr_seg -offset 0xFF310000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_ipi_psm]
  exclude_bd_addr_seg -offset 0xFF9B0000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_lpd_afi_0]
  exclude_bd_addr_seg -offset 0xFF0A0000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_lpd_iou_secure_slcr_0]
  exclude_bd_addr_seg -offset 0xFF080000 -range 0x00020000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_lpd_iou_slcr_0]
  exclude_bd_addr_seg -offset 0xFF410000 -range 0x00100000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_lpd_slcr_0]
  exclude_bd_addr_seg -offset 0xFF510000 -range 0x00040000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_lpd_slcr_secure_0]
  exclude_bd_addr_seg -offset 0xFF990000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_lpd_xppu_0]
  exclude_bd_addr_seg -offset 0xFF960000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_ocm_ctrl]
  exclude_bd_addr_seg -offset 0xFFFC0000 -range 0x00040000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_ocm_ram_0]
  exclude_bd_addr_seg -offset 0xFF980000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_ocm_xmpu_0]
  exclude_bd_addr_seg -offset 0x0001011E0000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_aes]
  exclude_bd_addr_seg -offset 0x0001011F0000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_bbram_ctrl]
  exclude_bd_addr_seg -offset 0x0001012D0000 -range 0x00001000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_cfi_cframe_0]
  exclude_bd_addr_seg -offset 0x0001012B0000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_cfu_apb_0]
  exclude_bd_addr_seg -offset 0x0001011C0000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_dma_0]
  exclude_bd_addr_seg -offset 0x0001011D0000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_dma_1]
  exclude_bd_addr_seg -offset 0x000101250000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_efuse_cache]
  exclude_bd_addr_seg -offset 0x000101240000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_efuse_ctrl]
  exclude_bd_addr_seg -offset 0x000101110000 -range 0x00050000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_global_0]
  exclude_bd_addr_seg -offset 0x000100280000 -range 0x00001000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_iomodule_0]
  exclude_bd_addr_seg -offset 0x000100310000 -range 0x00008000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_ppu1_mdm_0]
  exclude_bd_addr_seg -offset 0x000101030000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_qspi_0]
  exclude_bd_addr_seg -offset 0x000102000000 -range 0x00020000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_ram]
  exclude_bd_addr_seg -offset 0x000100240000 -range 0x00020000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_ram_data_cntlr]
  exclude_bd_addr_seg -offset 0x000100200000 -range 0x00040000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_ram_instr_cntlr]
  exclude_bd_addr_seg -offset 0x000106000000 -range 0x02000000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_ram_npi]
  exclude_bd_addr_seg -offset 0x000101200000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_rsa]
  exclude_bd_addr_seg -offset 0x0001012A0000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_rtc_0]
  exclude_bd_addr_seg -offset 0x000101210000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_sha]
  exclude_bd_addr_seg -offset 0x000101270000 -range 0x00030000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_sysmon_0]
  exclude_bd_addr_seg -offset 0x000100083000 -range 0x00001000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_tmr_inject_0]
  exclude_bd_addr_seg -offset 0x000100283000 -range 0x00001000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_tmr_manager_0]
  exclude_bd_addr_seg -offset 0x000101230000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_trng]
  exclude_bd_addr_seg -offset 0x0001012F0000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_xmpu_0]
  exclude_bd_addr_seg -offset 0x000101310000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_xppu_0]
  exclude_bd_addr_seg -offset 0x000101300000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_xppu_npi_0]
  exclude_bd_addr_seg -offset 0xFFC90000 -range 0x0000F000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_psm_global_reg]
  exclude_bd_addr_seg -offset 0xFFE90000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_r5_1_atcm_global]
  exclude_bd_addr_seg -offset 0xFFEB0000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_r5_1_btcm_global]
  exclude_bd_addr_seg -offset 0xFFE00000 -range 0x00040000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_r5_tcm_ram_global]
  exclude_bd_addr_seg -offset 0xFF9A0000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_rpu_0]
  exclude_bd_addr_seg -offset 0xFF130000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_scntr_0]
  exclude_bd_addr_seg -offset 0xFF140000 -range 0x00010000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_scntrs_0]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_qspi_ospi_flash_0] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_coresight_apu_fun] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_coresight_apu_etf] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_coresight_apu_ela] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_coresight_apu_cti] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_coresight_a720_dbg] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_coresight_a720_cti] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_coresight_a720_pmu] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_coresight_a720_etm] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_coresight_a721_dbg] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_coresight_a721_cti] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_coresight_a721_pmu] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_coresight_a721_etm] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_coresight_cpm_rom] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_coresight_cpm_fun] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_coresight_cpm_ela2a] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_coresight_cpm_ela2b] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_coresight_cpm_ela2c] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_coresight_cpm_ela2d] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_coresight_cpm_atm] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_coresight_cpm_cti2a] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_coresight_cpm_cti2d] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_spi_0] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_i2c_1] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_i2c_0] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_sbsauart_1] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_sbsauart_0] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_ttc_1] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_ttc_0] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_gpio_2] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_ipi_5] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_ipi_6] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_ipi_4] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_ipi_3] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_ttc_3] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_ospi_0] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_ttc_2] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_sd_0] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_gpio_0] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_spi_0] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_i2c_1] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_i2c_0] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_sbsauart_1] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_sbsauart_0] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_ttc_1] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_ttc_0] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_gpio_2] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_ipi_5] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_ipi_6] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_ipi_4] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_ipi_3] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_ttc_3] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_ospi_0] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_ttc_2] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_sd_0] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0]
  exclude_bd_addr_seg [get_bd_addr_segs shell_wrapper/cips/NOC_PMC_AXI_0/pspmc_0_psv_pmc_gpio_0] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0]
  save_bd_design

  ####################################
  # Restore instance
  ####################################
  current_bd_instance $oldCurInst

}
