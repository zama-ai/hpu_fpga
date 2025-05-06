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

set CLK_PERIOD 2.3
#3.700
create_clock -period $CLK_PERIOD -name CLK  [get_ports clk]
set_clock_uncertainty -setup [expr $CLK_PERIOD * 0.05] [get_clocks CLK]
set_clock_uncertainty -hold [expr $CLK_PERIOD * 0.05] [get_clocks CLK]
set_system_jitter [expr $CLK_PERIOD * 0.10]
set_clock_latency -source -min [expr $CLK_PERIOD * 0.01] CLK
set_clock_latency -source -max [expr $CLK_PERIOD * 0.02] CLK

# If the clock buffer location is known, define it for more accuracy in timing analysis
#set_property HD.CLK_SRC BUFGCTRL_X0Y39 [get_ports clk]

# Set delay on input and output ports
set_input_delay  [expr [get_property PERIOD [get_clocks CLK]] / 4] -clock CLK -max [get_ports * -filter {DIRECTION == IN && NAME !~ "clk"}]
set_input_delay  [expr [get_property PERIOD [get_clocks CLK]] / 4] -clock CLK -min [get_ports * -filter {DIRECTION == IN && NAME !~ "clk"}]
set_output_delay [expr [get_property PERIOD [get_clocks CLK]] / 4] -clock CLK -max [all_outputs]
set_output_delay [expr [get_property PERIOD [get_clocks CLK]] / 4] -clock CLK -min [all_outputs]
