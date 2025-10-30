# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
# Description  : Timing constraints for an out-of-context (OOC) synthesis
# ----------------------------------------------------------------------------------------------
#
# This file contains:
#    - the clock definition
#
# ----------------------------------------------------------------------------------------------
# Create clock
# ==============================================================================================

set CLK_PERIOD 2.500
create_clock -period $CLK_PERIOD -name CLK  [get_ports clk]

# If the clock buffer location is known, define it for more accuracy in timing analysis
set_property CLOCK_BUFFER_TYPE BUFGCE [get_ports clk]

# pblock
create_pblock user_pblock_SLR0
resize_pblock user_pblock_SLR0 -add SLR0
create_pblock user_pblock_SLR1
resize_pblock user_pblock_SLR1 -add SLR1
create_pblock user_pblock_SLR2
resize_pblock user_pblock_SLR2 -add SLR2

create_pblock user_pblock_SLR0_left
resize_pblock user_pblock_SLR0_left -add CLOCKREGION_X0Y0:CLOCKREGION_X3Y3
create_pblock user_pblock_SLR0_right
resize_pblock user_pblock_SLR0_right -add CLOCKREGION_X4Y0:CLOCKREGION_X6Y3
set_property PARENT user_pblock_SLR0 [get_pblocks user_pblock_SLR0_left]
set_property PARENT user_pblock_SLR0 [get_pblocks user_pblock_SLR0_right]

create_pblock user_pblock_SLR1_left
resize_pblock user_pblock_SLR1_left -add CLOCKREGION_X0Y4:CLOCKREGION_X3Y7
create_pblock user_pblock_SLR1_right
resize_pblock user_pblock_SLR1_right -add CLOCKREGION_X4Y4:CLOCKREGION_X6Y7
set_property PARENT user_pblock_SLR1 [get_pblocks user_pblock_SLR1_left]
set_property PARENT user_pblock_SLR1 [get_pblocks user_pblock_SLR1_right]

create_pblock user_pblock_SLR2_left
resize_pblock user_pblock_SLR2_left -add CLOCKREGION_X0Y8:CLOCKREGION_X3Y11
create_pblock user_pblock_SLR2_right
resize_pblock user_pblock_SLR2_right -add CLOCKREGION_X4Y8:CLOCKREGION_X6Y11
set_property PARENT user_pblock_SLR2 [get_pblocks user_pblock_SLR2_left]
set_property PARENT user_pblock_SLR2 [get_pblocks user_pblock_SLR2_right]

add_cells_to_pblock user_pblock_SLR0 [get_cells -hierarchical -regexp .*pep_mmacc_splitc_main_sxt] -clear_locs
add_cells_to_pblock user_pblock_SLR1 [get_cells -hierarchical -regexp .*pep_mmacc_splitc_subs_sxt] -clear_locs

#add_cells_to_pblock user_pblock_SLR0_left [get_cells -hierarchical -regexp .*pep_mmacc_splitc_main_sxt/pep_mmacc_splitc_sxt_core/qpsi0_.*] -clear_locs
#add_cells_to_pblock user_pblock_SLR0_right [get_cells -hierarchical -regexp .*pep_mmacc_splitc_main_sxt/pep_mmacc_splitc_sxt_core/qpsi1_.*] -clear_locs
#add_cells_to_pblock user_pblock_SLR1_left [get_cells -hierarchical -regexp .*pep_mmacc_splitc_subs_sxt/pep_mmacc_splitc_sxt_core/qpsi0_.*] -clear_locs
#add_cells_to_pblock user_pblock_SLR1_right [get_cells -hierarchical -regexp .*pep_mmacc_splitc_subs_sxt/pep_mmacc_splitc_sxt_core/qpsi1_.*] -clear_locs

