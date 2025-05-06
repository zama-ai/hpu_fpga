# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.

# This script is used for programming entirely the flash of v80 FPGA.
# This is mandatory to have JTAG plugged to the board
# It is mandatory as well to have AMD example project in /opt/amd/aved/
# Programming this project is a good fallback when flash is corrupted
open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target
current_hw_device [get_hw_devices xcv80_1]
refresh_hw_device -update_hw_probes false [lindex [get_hw_devices xcv80_1] 0]

create_hw_cfgmem -hw_device [lindex [get_hw_devices xcv80_1] 0] [lindex [get_cfgmem_parts {cfgmem-2048-ospi-x8-single}] 0]
set_property PROGRAM.BLANK_CHECK  0 [ get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices xcv80_1] 0]]
set_property PROGRAM.ERASE  1 [ get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices xcv80_1] 0]]
set_property PROGRAM.CFG_PROGRAM  1 [ get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices xcv80_1] 0]]
set_property PROGRAM.VERIFY  1 [ get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices xcv80_1] 0]]
set_property PROGRAM.CHECKSUM  0 [ get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices xcv80_1] 0]]
refresh_hw_device [lindex [get_hw_devices xcv80_1] 0]

set_property PROGRAM.ADDRESS_RANGE  {entire_device} [ get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices xcv80_1] 0]]
set_property PROGRAM.FILES [list "/opt/amd/aved/amd_v80_gen5x8_23.2_exdes_2_xbtest_stress/flash_setup/fpt_setup_amd_v80_gen5x8_23.2_exdes_2_20240409.pdi" ] [ get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices xcv80_1] 0]]
set_property PROGRAM.FILE {/opt/amd/aved/amd_v80_gen5x8_23.2_exdes_2_xbtest_stress/flash_setup/v80_initialization.pdi} [get_hw_devices xcv80_1]
set_property PROGRAM.BLANK_CHECK  0 [ get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices xcv80_1] 0]]
set_property PROGRAM.ERASE  1 [ get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices xcv80_1] 0]]
set_property PROGRAM.CFG_PROGRAM  1 [ get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices xcv80_1] 0]]
set_property PROGRAM.VERIFY  1 [ get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices xcv80_1] 0]]
set_property PROGRAM.CHECKSUM  0 [ get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices xcv80_1] 0]]

program_hw_devices [lindex [get_hw_devices xcv80_1] 0]; refresh_hw_device [lindex [get_hw_devices xcv80_1] 0];
program_hw_cfgmem [get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices xcv80_1] 0]]
refresh_hw_device [lindex [get_hw_devices xcv80_1] 0]
