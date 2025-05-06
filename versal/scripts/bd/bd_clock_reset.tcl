# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
# Contains procedure to generate block designs that handle
# the clocks and the resets
# ==============================================================================================

################################################################
# create_hier_cell_pcie_mgmt_pdi_reset
################################################################
# Hierarchical cell: pcie_mgmt_pdi_reset
proc create_hier_cell_pcie_mgmt_pdi_reset { parentCell nameHier } {
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
  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 s_axi

  # Create pins
  create_bd_pin -dir I -type clk clk
  create_bd_pin -dir I -type rst resetn
  create_bd_pin -dir I -type rst resetn_in

  # Create instance: pcie_mgmt_pdi_reset_gpio, and set properties
  set pcie_mgmt_pdi_reset_gpio [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 pcie_mgmt_pdi_reset_gpio ]
  set_property -dict [list \
    CONFIG.C_ALL_INPUTS_2 {1} \
    CONFIG.C_ALL_OUTPUTS {1} \
    CONFIG.C_DOUT_DEFAULT {0x00000000} \
    CONFIG.C_GPIO2_WIDTH {1} \
    CONFIG.C_GPIO_WIDTH {1} \
    CONFIG.C_IS_DUAL {1} \
  ] $pcie_mgmt_pdi_reset_gpio

  # Create instance: inv, and set properties
  set inv [ create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:2.0 inv ]
  set_property -dict [list \
    CONFIG.C_OPERATION {not} \
    CONFIG.C_SIZE {1} \
  ] $inv

  # Create instance: ccat, and set properties
  set ccat [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 ccat ]

  # Create instance: and_0, and set properties
  set and_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:util_reduced_logic:2.0 and_0 ]
  set_property CONFIG.C_SIZE {2} $and_0

  # Create interface connections
  connect_bd_intf_net -intf_net s_axi_1 [get_bd_intf_pins s_axi] [get_bd_intf_pins pcie_mgmt_pdi_reset_gpio/S_AXI]

  # Create port connections
  connect_bd_net -net and_0_Res [get_bd_pins and_0/Res] [get_bd_pins pcie_mgmt_pdi_reset_gpio/gpio2_io_i]
  connect_bd_net -net ccat_dout [get_bd_pins ccat/dout] [get_bd_pins and_0/Op1]
  connect_bd_net -net clk_1 [get_bd_pins clk] [get_bd_pins pcie_mgmt_pdi_reset_gpio/s_axi_aclk]
  connect_bd_net -net inv_Res [get_bd_pins inv/Res] [get_bd_pins ccat/In1]
  connect_bd_net -net pcie_mgmt_pdi_reset_gpio_gpio_io_o [get_bd_pins pcie_mgmt_pdi_reset_gpio/gpio_io_o] [get_bd_pins ccat/In0]
  connect_bd_net -net resetn_1 [get_bd_pins resetn] [get_bd_pins pcie_mgmt_pdi_reset_gpio/s_axi_aresetn]
  connect_bd_net -net resetn_in_1 [get_bd_pins resetn_in] [get_bd_pins inv/Op1]

  # Restore current instance
  current_bd_instance $oldCurInst
}

################################################################
# create_hier_cell_clock_reset
################################################################
# Hierarchical cell: clock_reset
proc create_hier_cell_clock_reset { parentCell nameHier } {

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
  set USER_0_FREQ $_nsp_hpu::USER_0_FREQ
  set USER_1_FREQ $_nsp_hpu::USER_1_FREQ

  ####################################
  # Create pins
  ####################################
  # Create interface pins
  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 s_axi_pcie_mgmt_pdi_reset

  # Create pins
  create_bd_pin -dir I -type clk clk_pl
  create_bd_pin -dir I -type clk clk_freerun
  create_bd_pin -dir I -type clk clk_pcie
  create_bd_pin -dir I -type rst dma_axi_aresetn
  create_bd_pin -dir I -type rst resetn_pl_axi
  create_bd_pin -dir O -from 0 -to 0 -type rst resetn_pcie_ic
  create_bd_pin -dir O -from 0 -to 0 -type rst resetn_pcie_periph
  create_bd_pin -dir O -from 0 -to 0 -type rst resetn_pl_ic
  create_bd_pin -dir O -from 0 -to 0 -type rst resetn_pl_periph
  create_bd_pin -dir O -type clk clk_usr_0
  create_bd_pin -dir O -from 0 -to 0 -type rst resetn_usr_0_ic
  create_bd_pin -dir O -from 0 -to 0 -type rst resetn_usr_0_periph
  create_bd_pin -dir O -type clk clk_usr_1
  create_bd_pin -dir O -from 0 -to 0 -type rst resetn_usr_1_ic
  create_bd_pin -dir O -from 0 -to 0 -type rst resetn_usr_1_periph

  ####################################
  # Create instances
  ####################################
  # Create instance: pcie_psr, and set properties
  set pcie_psr [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 pcie_psr ]
  set_property CONFIG.C_EXT_RST_WIDTH {1} $pcie_psr

  # Create instance: pl_psr, and set properties
  set pl_psr [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 pl_psr ]
  set_property CONFIG.C_EXT_RST_WIDTH {1} $pl_psr

  # Create instance: usr_clk_wiz, and set properties
  set usr_clk_wiz [ create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wizard:1.0 usr_clk_wiz ]

  # Note that the clock frequencies are not round : this avoid us some warnings
  #  > " requested frequency cannot be achived for value [...]"
  set user_freq "${USER_0_FREQ},${USER_1_FREQ}"
  set_property -dict [list \
    CONFIG.CLKOUT_DRIVES {No_buffer,No_buffer} \
    CONFIG.CLKOUT_REQUESTED_OUT_FREQUENCY $user_freq \
    CONFIG.CLKOUT_USED {true,true} \
    CONFIG.PRIM_SOURCE {No_buffer} \
    CONFIG.USE_DYN_RECONFIG {false} \
    CONFIG.USE_LOCKED {true} \
    CONFIG.USE_POWER_DOWN {false} \
    CONFIG.USE_RESET {false} \
  ] $usr_clk_wiz

  # Create instance: usr_0_psr, and set properties
  set usr_0_psr [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 usr_0_psr ]
  set_property CONFIG.C_EXT_RST_WIDTH {1} $usr_0_psr

  # Create instance: usr_1_psr, and set properties
  set usr_1_psr [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 usr_1_psr ]
  set_property CONFIG.C_EXT_RST_WIDTH {1} $usr_1_psr

  # Create instance: pcie_mgmt_pdi_reset
  create_hier_cell_pcie_mgmt_pdi_reset $hier_obj pcie_mgmt_pdi_reset

  ####################################
  # Connections
  ####################################
  # Create interface connections
  connect_bd_intf_net -intf_net s_axi_pcie_mgmt_pdi_reset_1 [get_bd_intf_pins s_axi_pcie_mgmt_pdi_reset] [get_bd_intf_pins pcie_mgmt_pdi_reset/s_axi]

  # Create port connections
  connect_bd_net -net clk_freerun_1 [get_bd_pins clk_freerun] [get_bd_pins usr_clk_wiz/clk_in1]
  connect_bd_net -net clk_pcie_1 [get_bd_pins clk_pcie] [get_bd_pins pcie_psr/slowest_sync_clk]
  connect_bd_net -net clk_pl_1 [get_bd_pins clk_pl] [get_bd_pins pl_psr/slowest_sync_clk] [get_bd_pins pcie_mgmt_pdi_reset/clk]
  connect_bd_net -net dma_axi_aresetn_1 [get_bd_pins dma_axi_aresetn] [get_bd_pins pcie_mgmt_pdi_reset/resetn_in]
  connect_bd_net -net pcie_psr_interconnect_aresetn [get_bd_pins pcie_psr/interconnect_aresetn] [get_bd_pins resetn_pcie_ic]
  connect_bd_net -net pcie_psr_peripheral_aresetn [get_bd_pins pcie_psr/peripheral_aresetn] [get_bd_pins resetn_pcie_periph]
  connect_bd_net -net pl_psr_interconnect_aresetn [get_bd_pins pl_psr/interconnect_aresetn] [get_bd_pins resetn_pl_ic] [get_bd_pins pcie_psr/ext_reset_in] [get_bd_pins usr_0_psr/ext_reset_in] [get_bd_pins usr_1_psr/ext_reset_in]
  connect_bd_net -net pl_psr_peripheral_aresetn [get_bd_pins pl_psr/peripheral_aresetn] [get_bd_pins resetn_pl_periph] [get_bd_pins pcie_mgmt_pdi_reset/resetn]
  connect_bd_net -net resetn_pl_axi_1 [get_bd_pins resetn_pl_axi] [get_bd_pins pl_psr/ext_reset_in]
  connect_bd_net -net usr_0_psr_interconnect_aresetn [get_bd_pins usr_0_psr/interconnect_aresetn] [get_bd_pins resetn_usr_0_ic]
  connect_bd_net -net usr_0_psr_peripheral_aresetn [get_bd_pins usr_0_psr/peripheral_aresetn] [get_bd_pins resetn_usr_0_periph]
  connect_bd_net -net usr_1_psr_interconnect_aresetn [get_bd_pins usr_1_psr/interconnect_aresetn] [get_bd_pins resetn_usr_1_ic]
  connect_bd_net -net usr_1_psr_peripheral_aresetn [get_bd_pins usr_1_psr/peripheral_aresetn] [get_bd_pins resetn_usr_1_periph]
  connect_bd_net -net usr_clk_wiz_clk_out1 [get_bd_pins usr_clk_wiz/clk_out1] [get_bd_pins clk_usr_0] [get_bd_pins usr_0_psr/slowest_sync_clk]
  connect_bd_net -net usr_clk_wiz_clk_out2 [get_bd_pins usr_clk_wiz/clk_out2] [get_bd_pins clk_usr_1] [get_bd_pins usr_1_psr/slowest_sync_clk]
  connect_bd_net -net usr_clk_wiz_locked [get_bd_pins usr_clk_wiz/locked] [get_bd_pins usr_0_psr/dcm_locked] [get_bd_pins usr_1_psr/dcm_locked]

  ####################################
  # Restore instance
  ####################################
  # Restore current instance
  current_bd_instance $oldCurInst
}

