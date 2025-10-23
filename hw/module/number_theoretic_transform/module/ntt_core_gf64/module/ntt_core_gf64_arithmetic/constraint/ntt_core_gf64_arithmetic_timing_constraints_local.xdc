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

set CLK_PERIOD 2.000
create_clock -period $CLK_PERIOD -name CLK  [get_ports clk]

# If the clock buffer location is known, define it for more accuracy in timing analysis
set_property CLOCK_BUFFER_TYPE BUFGCE [get_ports clk]

set insertion_pin [get_pin -hierarchical -regexp -filter {NAME =~ .*s._z.*/C}]
create_generated_clock -name IO_CLK -source [get_port clk] -combinational $insertion_pin

