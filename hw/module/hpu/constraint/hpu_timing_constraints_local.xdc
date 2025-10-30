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

set CLK_PRC_PERIOD 2.500
set CLK_CFG_PERIOD 10.000

create_clock -period PRC_CLK_PERIOD -name PRC_CLK  [get_ports prc_clk]

create_clock -period CLK_CFG_PERIOD -name CFG_CLK  [get_ports cfg_clk]

# If the clock buffer location is known, define it for more accuracy in timing analysis
set_property CLOCK_BUFFER_TYPE BUFGCE [get_ports prc_clk]
set_property CLOCK_BUFFER_TYPE BUFGCE [get_ports cfg_clk]

