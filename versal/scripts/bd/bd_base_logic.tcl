# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
# Contains procedure to generate block designs that handle
# the base logic in the PL
# ==============================================================================================

################################################################
# create_hier_cell_base_logic
################################################################
# Hierarchical cell: base_logic
proc create_hier_cell_base_logic { parentCell nameHier } {
  set parentObj [check_parent_hier $parentCell $nameHier]
  if { $parentObj == "" } { return }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj

  # Create cell and set as current instance
  set hier_obj [create_bd_cell -type hier $nameHier]
  current_bd_instance $hier_obj

  # Create interface pins
  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 s_axi_pcie_mgmt_slr0

  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 s_axi_rpu

  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:pcie3_cfg_ext_rtl:1.0 pcie_cfg_ext

  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 m_axi_pcie_mgmt_pdi_reset

  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 M01_AXI_0

  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 M02_AXI


  # Create pins
  create_bd_pin -dir I -type clk clk_pcie
  create_bd_pin -dir I -type clk clk_pl
  create_bd_pin -dir I -type clk hpu_clk
  create_bd_pin -dir I -type rst resetn_pcie_periph
  create_bd_pin -dir I -type rst resetn_pl_periph
  create_bd_pin -dir I -type rst resetn_pl_ic
  create_bd_pin -dir O -type intr irq_gcq_m2r

  # Create instance: pcie_slr0_mgmt_sc, and set properties
  set pcie_slr0_mgmt_sc [ create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 pcie_slr0_mgmt_sc ]
  set_property -dict [list \
    CONFIG.NUM_CLKS {1} \
    CONFIG.NUM_MI {4} \
    CONFIG.NUM_SI {1} \
  ] $pcie_slr0_mgmt_sc


  # Create instance: rpu_sc, and set properties
  # S00_AXI:M00_AXI:M01_AXI are on aclk
  # M02_AXI is on aclk1
  set rpu_sc [ create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 rpu_sc ]
  set_property -dict [list \
    CONFIG.NUM_CLKS {2} \
    CONFIG.NUM_MI {3} \
    CONFIG.NUM_SI {1} \
  ] $rpu_sc

  # Create instance: hw_discovery, and set properties
  set hw_discovery [ create_bd_cell -type ip -vlnv xilinx.com:ip:hw_discovery:1.0 hw_discovery ]
  set_property -dict [list \
    CONFIG.C_CAP_BASE_ADDR {0x600} \
    CONFIG.C_INJECT_ENDPOINTS {0} \
    CONFIG.C_MANUAL {1} \
    CONFIG.C_NEXT_CAP_ADDR {0x000} \
    CONFIG.C_NUM_PFS {1} \
    CONFIG.C_PF0_BAR_INDEX {0} \
    CONFIG.C_PF0_ENDPOINT_NAMES {0} \
    CONFIG.C_PF0_ENTRY_ADDR_0 {0x000001001000} \
    CONFIG.C_PF0_ENTRY_ADDR_1 {0x000001010000} \
    CONFIG.C_PF0_ENTRY_ADDR_2 {0x000008000000} \
    CONFIG.C_PF0_ENTRY_BAR_0 {0} \
    CONFIG.C_PF0_ENTRY_BAR_1 {0} \
    CONFIG.C_PF0_ENTRY_BAR_2 {0} \
    CONFIG.C_PF0_ENTRY_MAJOR_VERSION_0 {1} \
    CONFIG.C_PF0_ENTRY_MAJOR_VERSION_1 {1} \
    CONFIG.C_PF0_ENTRY_MAJOR_VERSION_2 {1} \
    CONFIG.C_PF0_ENTRY_MINOR_VERSION_0 {0} \
    CONFIG.C_PF0_ENTRY_MINOR_VERSION_1 {2} \
    CONFIG.C_PF0_ENTRY_MINOR_VERSION_2 {0} \
    CONFIG.C_PF0_ENTRY_RSVD0_0 {0x0} \
    CONFIG.C_PF0_ENTRY_RSVD0_1 {0x0} \
    CONFIG.C_PF0_ENTRY_RSVD0_2 {0x0} \
    CONFIG.C_PF0_ENTRY_TYPE_0 {0x50} \
    CONFIG.C_PF0_ENTRY_TYPE_1 {0x54} \
    CONFIG.C_PF0_ENTRY_TYPE_2 {0x55} \
    CONFIG.C_PF0_ENTRY_VERSION_TYPE_0 {0x01} \
    CONFIG.C_PF0_ENTRY_VERSION_TYPE_1 {0x01} \
    CONFIG.C_PF0_ENTRY_VERSION_TYPE_2 {0x01} \
    CONFIG.C_PF0_HIGH_OFFSET {0x00000000} \
    CONFIG.C_PF0_LOW_OFFSET {0x0100000} \
    CONFIG.C_PF0_NUM_SLOTS_BAR_LAYOUT_TABLE {3} \
    CONFIG.C_PF0_S_AXI_ADDR_WIDTH {32} \
  ] $hw_discovery


  # Create instance: uuid_rom, and set properties
  set uuid_rom [ create_bd_cell -type ip -vlnv xilinx.com:ip:shell_utils_uuid_rom:2.0 uuid_rom ]
  set_property CONFIG.C_INITIAL_UUID {00000000000000000000000000000000} $uuid_rom

  # Create instance: gcq_m2r, and set properties
  set gcq_m2r [ create_bd_cell -type ip -vlnv xilinx.com:ip:cmd_queue:2.0 gcq_m2r ]

  # Create interface connections
  connect_bd_intf_net -intf_net Conn1 [get_bd_intf_pins rpu_sc/M01_AXI] [get_bd_intf_pins M01_AXI_0]
  connect_bd_intf_net -intf_net Conn2 [get_bd_intf_pins rpu_sc/M02_AXI] [get_bd_intf_pins M02_AXI]
  connect_bd_intf_net -intf_net pcie_cfg_ext_1 [get_bd_intf_pins pcie_cfg_ext] [get_bd_intf_pins hw_discovery/s_pcie4_cfg_ext]
  connect_bd_intf_net -intf_net pcie_slr0_mgmt_sc_M00_AXI [get_bd_intf_pins pcie_slr0_mgmt_sc/M00_AXI] [get_bd_intf_pins hw_discovery/s_axi_ctrl_pf0]
  connect_bd_intf_net -intf_net pcie_slr0_mgmt_sc_M01_AXI [get_bd_intf_pins pcie_slr0_mgmt_sc/M01_AXI] [get_bd_intf_pins uuid_rom/S_AXI]
  connect_bd_intf_net -intf_net pcie_slr0_mgmt_sc_M02_AXI [get_bd_intf_pins pcie_slr0_mgmt_sc/M02_AXI] [get_bd_intf_pins gcq_m2r/S00_AXI]
  connect_bd_intf_net -intf_net pcie_slr0_mgmt_sc_M03_AXI [get_bd_intf_pins pcie_slr0_mgmt_sc/M03_AXI] [get_bd_intf_pins m_axi_pcie_mgmt_pdi_reset]
  connect_bd_intf_net -intf_net rpu_sc_M00_AXI [get_bd_intf_pins rpu_sc/M00_AXI] [get_bd_intf_pins gcq_m2r/S01_AXI]
  connect_bd_intf_net -intf_net s_axi_pcie_mgmt_slr0_1 [get_bd_intf_pins s_axi_pcie_mgmt_slr0] [get_bd_intf_pins pcie_slr0_mgmt_sc/S00_AXI]
  connect_bd_intf_net -intf_net s_axi_rpu_1 [get_bd_intf_pins s_axi_rpu] [get_bd_intf_pins rpu_sc/S00_AXI]

  # Create port connections
  connect_bd_net -net clk_pcie_1 [get_bd_pins clk_pcie] [get_bd_pins hw_discovery/aclk_pcie]
  connect_bd_net -net clk_pl_1 [get_bd_pins clk_pl] [get_bd_pins pcie_slr0_mgmt_sc/aclk] [get_bd_pins rpu_sc/aclk] [get_bd_pins hw_discovery/aclk_ctrl] [get_bd_pins uuid_rom/S_AXI_ACLK] [get_bd_pins gcq_m2r/aclk]
  connect_bd_net -net hpu_clk [get_bd_pins hpu_clk] [get_bd_pins rpu_sc/aclk1]
  connect_bd_net -net gcq_m2r_irq_sq [get_bd_pins gcq_m2r/irq_sq] [get_bd_pins irq_gcq_m2r]
  connect_bd_net -net resetn_pcie_periph_1 [get_bd_pins resetn_pcie_periph] [get_bd_pins hw_discovery/aresetn_pcie]
  connect_bd_net -net resetn_pl_ic_1 [get_bd_pins resetn_pl_ic] [get_bd_pins pcie_slr0_mgmt_sc/aresetn] [get_bd_pins rpu_sc/aresetn]
  connect_bd_net -net resetn_pl_periph_1 [get_bd_pins resetn_pl_periph] [get_bd_pins hw_discovery/aresetn_ctrl] [get_bd_pins uuid_rom/S_AXI_ARESETN] [get_bd_pins gcq_m2r/aresetn]

  # Restore current instance
  current_bd_instance $oldCurInst
}

