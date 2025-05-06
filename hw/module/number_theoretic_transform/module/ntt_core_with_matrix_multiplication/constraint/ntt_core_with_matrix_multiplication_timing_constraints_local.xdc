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

set CLK_PERIOD 3.700
create_clock -period $CLK_PERIOD -name CLK  [get_ports clk]
set_clock_uncertainty -setup 0.100 [get_clocks CLK]
set_clock_uncertainty -hold 0.100 [get_clocks CLK]
set_system_jitter 0.200
set_clock_latency -source -min 0.100 CLK
set_clock_latency -source -max 0.200 CLK
# If the clock buffer location is known, define it for more accuracy in timing analysis
#set_property HD.CLK_SRC BUFGCTRL_X0Y39 [get_ports clk]

# Set delay on input and output ports
set_input_delay [expr [get_property PERIOD [get_clocks CLK]] / 2] -clock CLK -max [get_ports * -filter {DIRECTION == IN && NAME !~ "clk"}]
set_input_delay [expr [get_property PERIOD [get_clocks CLK]] / 2] -clock CLK -min [get_ports * -filter {DIRECTION == IN && NAME !~ "clk"}]
set_output_delay [expr [get_property PERIOD [get_clocks CLK]] / 2] -clock CLK -max [all_outputs]
set_output_delay [expr [get_property PERIOD [get_clocks CLK]] / 2] -clock CLK -min [all_outputs]

# False path
set_false_path -from [get_ports twd_omg_ru_r_pow*]

# pblock
create_pblock pblock_SLR0
resize_pblock pblock_SLR0 -add SLR0
add_cells_to_pblock pblock_SLR0 -top -clear_locs

