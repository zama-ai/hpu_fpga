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


set CLK_PERIOD 2.100
create_clock -period $CLK_PERIOD -name clk_mhdma  [get_ports clk_mhdma]

# If the clock buffer location is known, define it for more accuracy in timing analysis
set_property CLOCK_BUFFER_TYPE BUFGCE [get_ports clk_mhdma]


set CLK_PERIOD_2 10
create_clock -period $CLK_PERIOD_2 -name clk_mhdma_cfg  [get_ports clk_mhdma_cfg]

# If the clock buffer location is known, define it for more accuracy in timing analysis
set_property CLOCK_BUFFER_TYPE BUFGCE [get_ports clk_mhdma_cfg]
