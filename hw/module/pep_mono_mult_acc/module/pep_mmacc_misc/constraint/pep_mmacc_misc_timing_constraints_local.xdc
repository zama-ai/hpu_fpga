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
create_pblock pblock_mmacc_ram
resize_pblock pblock_mmacc_ram -add {RAMB18_X0Y0:RAMB18_X7Y81 RAMB36_X0Y0:RAMB36_X7Y47} -locs keep_all
add_cells_to_pblock pblock_mmacc_ram -clear_locs -add_primitives [get_cells *mmacc_glwe_ram/*]

