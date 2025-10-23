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

set CLK_PERIOD 2.500
create_clock -period $CLK_PERIOD -name CLK  [get_ports clk]

set insertion_pin {pep_sequencer/inst_ack/C}
create_generated_clock -name IO_CLK -source [get_port clk] -combinational [get_pin $insertion_pin]

