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
# Set clock period to 270MHz
# ==============================================================================================

set CLK_PERIOD 2.000

# Set clock period to 450MHz
# Passes timing with one register retiming register
#set CLK_PERIOD 2.222

create_clock -period $CLK_PERIOD -name CLK  [get_ports clk]

# If the clock buffer location is known, define it for more accuracy in timing analysis
set_property CLOCK_BUFFER_TYPE BUFGCE [get_ports clk]

