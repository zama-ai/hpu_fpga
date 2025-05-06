# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
# Block design description
# ----------------------------------------------------------------------------------------------
# Variables
# Note : avoid using "microblaze" as block design name
# DO NOT CHANGE, otherwise it break the outer script
# ==============================================================================================

set bd_name "ublaze"

# Block design creation ---------------------------------------------------------------------------
create_bd_design $bd_name

# Adding microblaze module
startgroup
  create_bd_cell -type ip -vlnv xilinx.com:ip:microblaze:11.0 ${bd_name}_0
endgroup

set bd_top [get_bd_cells ${bd_name}_0]

# Note : always put debug_module as {None} for integration
apply_bd_automation -rule xilinx.com:bd_rule:microblaze -config {
  axi_intc {1} 
  axi_periph {Enabled} 
  cache {None} 
  clk {New External Port} 
  cores {1} 
  debug_module {None} 
  ecc {None} 
  local_mem {64KB} 
  preset {Microcontroller}
} ${bd_top}

# Here are defined how many communication buses are used in the micro-processor
startgroup
  set_property -dict [list CONFIG.NUM_PORTS {1}] [get_bd_cells ${bd_name}_0_xlconcat]
  set_property -dict [list CONFIG.NUM_MI {2} CONFIG.NUM_SI {1}] [get_bd_cells ${bd_name}_0_axi_periph]
  set_property -dict [list CONFIG.C_I_AXI {0} CONFIG.C_D_AXI {1} CONFIG.C_FSL_LINKS {2}] ${bd_top}
endgroup

# Setup input output Pins
startgroup
  make_bd_intf_pins_external  [get_bd_intf_pins ${bd_name}_0/M0_AXIS]
  make_bd_intf_pins_external  [get_bd_intf_pins ${bd_name}_0/S0_AXIS]
  make_bd_intf_pins_external  [get_bd_intf_pins ${bd_name}_0/M1_AXIS]
  make_bd_intf_pins_external  [get_bd_intf_pins ${bd_name}_0/S1_AXIS]
  make_bd_intf_pins_external  [get_bd_intf_pins ${bd_name}_0_axi_periph/M01_AXI]
  make_bd_pins_external  [get_bd_pins ${bd_name}_0_xlconcat/In0]
endgroup

# By default the clock is defined as 100Mhz, change here when needed.
startgroup
  set_property CONFIG.FREQ_HZ 250000000 [get_bd_ports Clk]
  apply_bd_automation -rule xilinx.com:bd_rule:board -config { Manual_Source {Auto}}  [get_bd_pins rst_Clk_100M/ext_reset_in]
  apply_bd_automation -rule xilinx.com:bd_rule:clkrst -config { Clk {/Clk (250 MHz)} Freq {250} Ref_Clk0 {} Ref_Clk1 {} Ref_Clk2 {}}  [get_bd_pins ${bd_name}_0_axi_periph/M01_ACLK]
endgroup

# Rework Addr-map
# NB: Addr outside of addr-range are filtered out, however addr issued aren't updated:
#  i.e. addr over the bus are within [Offset: Offset + Range] instead of [0: Range]
# Note : the ucore can only read in HBM add from 0 to 4G, which means that
# the associated PC is either one of the following : PC0 -> PC7
# To optimize/homogenize the HBM address area, set the HBM address space first.
# Workaround : it seems that the ublaze has to have some preconfigured add space.
# At each set_property, the address space overlap is checked, therefore we
# may not be able to set the value directly, and so may need a workaround to set
# a high add first..

# The following ublaze_0/Data/SEG_dlmb_bram_if_cntlr_Mem should be at 0x0 (default value)
set_property offset 0x00000000 [get_bd_addr_segs {ublaze_0/Data/SEG_dlmb_bram_if_cntlr_Mem}]
set_property range 64K  [get_bd_addr_segs {ublaze_0/Data/SEG_dlmb_bram_if_cntlr_Mem}]

# Here peripheral AXI data interface is set to PC1 address space
assign_bd_address -target_address_space /ublaze_0/Data [get_bd_addr_segs M01_AXI_0/Reg] -force
set_property offset 0x20000000 [get_bd_addr_segs {ublaze_0/Data/SEG_M01_AXI_0_Reg}]
set_property range 512M [get_bd_addr_segs {ublaze_0/Data/SEG_M01_AXI_0_Reg}]

# This is an internal range to configure interrupt ctrl but we want to be sure it is
# not set over another existing range
set_property offset 0x40000000 [get_bd_addr_segs {ublaze_0/Data/SEG_ublaze_0_axi_intc_Reg}]
set_property range 64K  [get_bd_addr_segs {ublaze_0/Data/SEG_ublaze_0_axi_intc_Reg}]

# The following ublaze_0/Instruction/SEG_ilmb_bram_if_cntlr_Mem should be at 0x0 (default value)
set_property offset 0x00000000 [get_bd_addr_segs {ublaze_0/Instruction/SEG_ilmb_bram_if_cntlr_Mem}]
set_property range 64K [get_bd_addr_segs {ublaze_0/Instruction/SEG_ilmb_bram_if_cntlr_Mem}]

# Renaming some of the IO pins for clarity 
startgroup
  set_property name axis_sp0 [get_bd_intf_ports S0_AXIS_0]
  set_property name axis_mp0 [get_bd_intf_ports M0_AXIS_0]
  set_property name axis_sp1 [get_bd_intf_ports S1_AXIS_0]
  set_property name axis_mp1 [get_bd_intf_ports M1_AXIS_0]
  set_property name axi_mp   [get_bd_intf_ports M01_AXI_0]
  set_property name irq_0 [get_bd_ports In0_0]
  set_property name ublaze_rst [get_bd_ports reset_rtl_0]
  set_property name ublaze_clk [get_bd_ports Clk]
endgroup

# Mandatory
assign_bd_address
validate_bd_design
