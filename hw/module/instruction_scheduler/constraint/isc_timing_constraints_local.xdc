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
# ==============================================================================================

set CLK_PERIOD 2.5
create_clock -period $CLK_PERIOD -name CLK  [get_ports clk]

set LPD_CLK_PERIOD 10
create_clock -period $LPD_CLK_PERIOD -name CFG_CLK  [get_ports cfg_clk]

# If the clock buffer location is known, define it for more accuracy in timing analysis
set_property CLOCK_BUFFER_TYPE BUFGCE [get_ports clk]
set_property CLOCK_BUFFER_TYPE BUFGCE [get_ports cfg_clk]

# -----------------------------------------------------------------------------
# False Paths
set_false_path -from [get_ports use_bpip]
