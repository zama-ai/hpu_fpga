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

set CLK_PERIOD 3.700
create_clock -period $CLK_PERIOD -name CLK  [get_ports clk]

# If the clock buffer location is known, define it for more accuracy in timing analysis
set_property CLOCK_BUFFER_TYPE BUFGCE [get_ports clk]

# False path
set_false_path -from [get_ports twd_omg_ru_r_pow*]

# pblock
create_pblock pblock_SLR0
resize_pblock pblock_SLR0 -add SLR0
add_cells_to_pblock pblock_SLR0 -top -clear_locs

