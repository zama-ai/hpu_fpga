# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
# Description  : Timing constraints for an out-of-context (OOC) synthesis
# ----------------------------------------------------------------------------------------------
#
# This file contains:
#    - the clock definition
#    - constraints on input and output ports
# ----------------------------------------------------------------------------------------------
# Create clock
# ==============================================================================================

set CLK_PERIOD 2.5
create_clock -period $CLK_PERIOD -name CLK  [get_ports clk_eth_mrmac]

set LPD_CLK_PERIOD 10
create_clock -period $LPD_CLK_PERIOD -name CFG_CLK  [get_ports clk_eth_cfg]

# If the clock buffer location is known, define it for more accuracy in timing analysis
set_property CLOCK_BUFFER_TYPE BUFGCE [get_ports clk_eth_mrmac]
set_property CLOCK_BUFFER_TYPE BUFGCE [get_ports clk_eth_cfg]

