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

set CLK_PRC_PERIOD 2.500
set CLK_CFG_PERIOD 10.000

create_clock -period PRC_CLK_PERIOD -name PRC_CLK  [get_ports prc_clk]

set_clock_uncertainty -setup 0.100 [get_clocks PRC_CLK]
set_clock_uncertainty -hold 0.010 [get_clocks PRC_CLK]
set_system_jitter 0.200
set_clock_latency -source -min 0.100 PRC_CLK
set_clock_latency -source -max 0.120 PRC_CLK


create_clock -period CLK_CFG_PERIOD -name CFG_CLK  [get_ports cfg_clk]

set_clock_uncertainty -setup 0.100 [get_clocks CFG_CLK]
set_clock_uncertainty -hold 0.010 [get_clocks CFG_CLK]
set_system_jitter 0.200
set_clock_latency -source -min 0.100 CFG_CLK
set_clock_latency -source -max 0.120 CFG_CLK

# If the clock buffer location is known, define it for more accuracy in timing analysis
#set_property HD.CLK_SRC BUFGCTRL_X0Y39 [get_ports PRC_CLK]

# Set delay on input and output ports
set_input_delay [expr [get_property PERIOD [get_clocks PRC_CLK]] / 2] -clock PRC_CLK -max [get_ports * -filter {DIRECTION == IN && NAME !~ "prc_clk" && NAME !~ "cfg_clk"}]
set_input_delay [expr [get_property PERIOD [get_clocks PRC_CLK]] / 2] -clock PRC_CLK -min [get_ports * -filter {DIRECTION == IN && NAME !~ "prc_clk" && NAME !~ "cfg_clk"}]
set_output_delay [expr [get_property PERIOD [get_clocks PRC_CLK]] / 2] -clock PRC_CLK -max [all_outputs]
set_output_delay [expr [get_property PERIOD [get_clocks PRC_CLK]] / 2] -clock PRC_CLK -min [all_outputs]

