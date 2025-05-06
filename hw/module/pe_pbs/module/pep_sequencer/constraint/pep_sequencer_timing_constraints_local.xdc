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

set CLK_PERIOD 2.500
create_clock -period $CLK_PERIOD -name CLK  [get_ports clk]
set_clock_uncertainty -setup 0.100 [get_clocks CLK]
set_clock_uncertainty -hold 0.010 [get_clocks CLK]
set_system_jitter 0.200
set_clock_latency -source -min 0.100 CLK
set_clock_latency -source -max 0.120 CLK

set insertion_pin {pep_sequencer/inst_ack/C}
create_generated_clock -name IO_CLK -source [get_port clk] -combinational [get_pin $insertion_pin]

# Set delay on input and output ports
set_input_delay [expr [get_property PERIOD [get_clocks CLK]] / 2] -clock IO_CLK -max [get_ports * -filter {DIRECTION == IN && NAME !~ "clk"}]
set_input_delay [expr [get_property PERIOD [get_clocks CLK]] / 2] -clock IO_CLK -min [get_ports * -filter {DIRECTION == IN && NAME !~ "clk"}]
set_output_delay [expr [get_property PERIOD [get_clocks CLK]] / 2] -clock IO_CLK -max [all_outputs]
set_output_delay [expr [get_property PERIOD [get_clocks CLK]] / 2] -clock IO_CLK -min [all_outputs]
