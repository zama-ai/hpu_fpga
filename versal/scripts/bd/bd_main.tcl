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
  set clk_usr_1_0 [ create_bd_port -dir O -type clk clk_usr_1_0 ]
  set pl0_ref_clk_0 [ create_bd_port -dir O -type clk pl0_ref_clk_0 ]

  # Association properties
  set prop_clk(clk_usr_0_0) ""
  set prop_clk(clk_usr_1_0) ""
  set prop_clk(pl0_ref_clk_0) ""

  # == Resets
  set resetn_usr_0_ic_0 [ create_bd_port -dir O -type rst resetn_usr_0_ic_0 ]
  set resetn_usr_1_ic_0 [ create_bd_port -dir O -type rst resetn_usr_1_ic_0 ]
  set pl0_resetn_0 [ create_bd_port -dir O -type rst pl0_resetn_0 ]

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

  ####################################
  # Create Shell
  ####################################
  create_hier_cell_shell_wrapper [current_bd_instance .] shell_wrapper

  ####################################
  # Create NOC
  ####################################
  create_hier_cell_noc_wrapper [current_bd_instance .] noc_wrapper $ntt_psi

  ####################################
  # Port Connections
  ####################################
  # == Clocks
  connect_bd_intf_net -intf_net sys_clk0_0     [get_bd_intf_ports /sys_clk0_0]     [get_bd_intf_pins noc_wrapper/sys_clk0_0]
  connect_bd_intf_net -intf_net sys_clk0_1     [get_bd_intf_ports /sys_clk0_1]     [get_bd_intf_pins noc_wrapper/sys_clk0_1]
  connect_bd_intf_net -intf_net hbm_ref_clk_0  [get_bd_intf_ports /hbm_ref_clk_0]  [get_bd_intf_pins noc_wrapper/hbm_ref_clk_0]
  connect_bd_intf_net -intf_net hbm_ref_clk_1  [get_bd_intf_ports /hbm_ref_clk_1]  [get_bd_intf_pins noc_wrapper/hbm_ref_clk_1]
  connect_bd_intf_net -intf_net gt_pcie_refclk [get_bd_intf_ports /gt_pcie_refclk] [get_bd_intf_pins shell_wrapper/gt_pcie_refclk]

  connect_bd_net -net pl0_ref_clk [get_bd_ports /pl0_ref_clk_0] [get_bd_pins shell_wrapper/pl0_ref_clk_0]
  connect_bd_net -net clk_usr_0   [get_bd_ports /clk_usr_0_0]   [get_bd_pins shell_wrapper/clk_usr_0_0]
  connect_bd_net -net clk_usr_1   [get_bd_ports /clk_usr_1_0]   [get_bd_pins shell_wrapper/clk_usr_1_0]

  # == Resets
  connect_bd_net -net pl0_resetn      [get_bd_ports /pl0_resetn_0]      [get_bd_pins shell_wrapper/pl0_resetn_0]
  connect_bd_net -net resetn_usr_0_ic [get_bd_ports /resetn_usr_0_ic_0] [get_bd_pins shell_wrapper/resetn_usr_0_ic_0]
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
                                        [get_bd_pins shell_wrapper/resetn_usr_0_ic_0] -boundary_type upper
  connect_bd_net [get_bd_pins noc_wrapper/mregif_1_rst_n] \
                                        [get_bd_pins shell_wrapper/resetn_usr_1_ic_0] -boundary_type upper

  # MGMT
  connect_bd_intf_net -intf_net s_axi_pcie_mgmt_slr0 [get_bd_intf_pins shell_wrapper/s_axi_pcie_mgmt_slr0] [get_bd_intf_pins noc_wrapper/s_axi_pcie_mgmt_slr0]

  # CPM NOC
  connect_bd_intf_net -intf_net cpm_pcie_noc_0 [get_bd_intf_pins shell_wrapper/cpm_pcie_noc_0] [get_bd_intf_pins noc_wrapper/cpm_pcie_noc_0]
  connect_bd_intf_net -intf_net cpm_pcie_noc_1 [get_bd_intf_pins shell_wrapper/cpm_pcie_noc_1] [get_bd_intf_pins noc_wrapper/cpm_pcie_noc_1]
  connect_bd_net -net cpm_pcie_noc_axi0_clk [get_bd_pins shell_wrapper/cpm_pcie_noc_axi0_clk] [get_bd_pins noc_wrapper/cpm_pcie_noc_axi0_clk]
  connect_bd_net -net cpm_pcie_noc_axi1_clk [get_bd_pins shell_wrapper/cpm_pcie_noc_axi1_clk] [get_bd_pins noc_wrapper/cpm_pcie_noc_axi1_clk]

  # PMC NOC
  connect_bd_intf_net -intf_net pmc_noc_axi_0 [get_bd_intf_pins shell_wrapper/pmc_noc_axi_0] [get_bd_intf_pins noc_wrapper/pmc_noc_axi_0]
  connect_bd_net -net pmc_axi_noc_axi0_clk [get_bd_pins shell_wrapper/pmc_axi_noc_axi0_clk] [get_bd_pins noc_wrapper/pmc_axi_noc_axi0_clk]

  # LPD AXI NOC
  connect_bd_intf_net -intf_net lpd_axi_noc_0 [get_bd_intf_pins shell_wrapper/lpd_axi_noc_0] [get_bd_intf_pins noc_wrapper/lpd_axi_noc_0]
  connect_bd_net -net lpd_axi_noc_clk [get_bd_pins noc_wrapper/lpd_axi_noc_clk] [get_bd_pins shell_wrapper/lpd_axi_noc_clk]

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
  assign_bd_address -offset 0x020101000000 -range 0x00001000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/base_logic/hw_discovery/s_axi_ctrl_pf0/reg0] -force
  assign_bd_address -offset 0x020101040000 -range 0x00001000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/clock_reset/pcie_mgmt_pdi_reset/pcie_mgmt_pdi_reset_gpio/S_AXI/Reg] -force
  assign_bd_address -offset 0x020101001000 -range 0x00001000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs shell_wrapper/base_logic/uuid_rom/S_AXI/reg0] -force

  # CPM 1
  assign_bd_address -offset 0x050080000000 -range 0x80000000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs noc_wrapper/ddr_noc/axi_noc_mc_ddr4_0/S01_INI/C1_DDR_CH1] -force
  assign_bd_address -offset 0x00000000     -range 0x80000000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs noc_wrapper/ddr_noc/axi_noc_mc_ddr4_0/S01_INI/C1_DDR_LOW0] -force
  assign_bd_address -offset 0x060000000000 -range 0x000800000000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs noc_wrapper/ddr_noc/axi_noc_mc_ddr4_1/S01_INI/C1_DDR_CH2] -force
  assign_bd_address -offset 0x020101010000 -range 0x00001000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/base_logic/gcq_m2r/S00_AXI/S00_AXI_Reg] -force
  assign_bd_address -offset 0x020101000000 -range 0x00001000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_1] [get_bd_addr_segs shell_wrapper/base_logic/hw_discovery/s_axi_ctrl_pf0/reg0] -force
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
  assign_bd_address -offset $regif_add -range  [expr $REGIF_NB * $REGIF_CLK_NB * $regif_range] -target_address_space [get_bd_addr_spaces shell_wrapper/cips/M_AXI_LPD] [get_bd_addr_segs /axi_lpd/Reg] -force
  for { set i 0}  {$i < $REGIF_NB} {incr i} {
    for { set j 0}  {$j < $REGIF_CLK_NB} {incr j} {
      # Address order : first 2nd clock, then second clock
      set n [expr $i * $REGIF_CLK_NB + ($REGIF_CLK_NB - 1 - $j)]
      assign_bd_address -offset [expr $regif_add_noc + $n * $regif_range] -range $regif_range -target_address_space [get_bd_addr_spaces /S_REGIF_AXI_0 ] [get_bd_addr_segs /REGIF_AXI_${i}_${j}/Reg] -force
    }
  }

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

  ####################################
  # Address exclusion
  ####################################
  puts ">>>>>>>> Exclusion"
  # Exclude Address Segments
  exclude_bd_addr_seg -target_address_space [get_bd_addr_spaces shell_wrapper/cips/CPM_PCIE_NOC_0] [get_bd_addr_segs noc_wrapper/ddr_noc/axi_noc_mc_ddr4_0/S00_INI/C0_DDR_CH1]
  exclude_bd_addr_seg -offset 0x050080000000 -range 0x80000000 -target_address_space [get_bd_addr_spaces shell_wrapper/cips/LPD_AXI_NOC_0] [get_bd_addr_segs noc_wrapper/ddr_noc/axi_noc_mc_ddr4_0/S00_INI/C0_DDR_CH1]

  save_bd_design

  ####################################
  # Restore instance
  ####################################
  current_bd_instance $oldCurInst

}
