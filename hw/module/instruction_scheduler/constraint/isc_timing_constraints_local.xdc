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
# We'll not define any source delay or system jitter in ooc. Source delay is computed automatically
# by propagating the clock and all IO constraints are within the chip. The system jitter should also
# be computed automatically by the tool.
# SYS_UNCERTAINTY is only an estimate of the total clock uncertainty to tame the IO delay.
# This should be set to the maximum value of the uncertainty in hold and setup analysis, including
# clock skew.
# For hold analysis, this is usually dominated by the clock skew, since both the
# launching and capture clocks have the same edge, so jitter is dominated by very high frequency
# PSIJ and is negligible. The only meaningfull source of error is any path mismatch in the path
# divergence between launching and capturing cells.
# For setup, jitter will be significant and might dominate.
# ----------------------------------------------------------------------------------------------
# Data table
# ==============================================================================================

set CLK_PERIOD            2.86
set CLK_UNCERTAINTY_RATIO 0.02
set SYS_UNCERTAINTY       0.300
set INPUT_MARGIN_RATIO    0.2
set OUTPUT_MARGIN_RATIO   0.8
set MIN_DELAY_RATIO       0.5

# Create clock
create_clock -period $CLK_PERIOD -name CLK  [get_ports clk]

# Clock uncertainty only to give margin
set_clock_uncertainty -setup [expr $CLK_PERIOD * $CLK_UNCERTAINTY_RATIO] [get_clocks CLK]

# In Vivado 2024.2 (or v80, not sure), input and output delays no longer inherit the clock's
# insertion delay in the path calculation. So, build a generated clock from a cell's clock pin to
# inherite the propagation delay and set all io constraints relatively to this new clock.
set insertion_pin {isc_pool/r_pinfo_reg[61][insn][dst_id][isc][id][13]/C}
create_generated_clock -name io_clk -source [get_port clk] -combinational [get_pin $insertion_pin]

# -----------------------------------------------------------------------------
# Set delay on input and output ports
# Assuming here that timing is split by having inputs not registered and outputs registered. Also,
# the minimum delay is set to overcome the clock uncertainty and jitter, otherwise it would be
# impossible to meet.

set USER_UNCERTAINTY [ expr ($CLK_PERIOD * $CLK_UNCERTAINTY_RATIO)                 ]
set MIN_IO_DELAY     [ expr $SYS_UNCERTAINTY * 1.02                                ]
set MAX_IDELAY       [ expr max($CLK_PERIOD * $INPUT_MARGIN_RATIO, $MIN_IO_DELAY)  ]
set MAX_ODELAY       [ expr max($CLK_PERIOD * $OUTPUT_MARGIN_RATIO, $MIN_IO_DELAY) ]
set MIN_IDELAY       [ expr max($MAX_IDELAY * $MIN_DELAY_RATIO, $MIN_IO_DELAY)     ]
set MIN_ODELAY       [ expr max($MAX_ODELAY * $MIN_DELAY_RATIO, $MIN_IO_DELAY)     ]

set all_inputs [get_ports * -filter {DIRECTION == IN && NAME !~ "clk"}]
set_input_delay  $MAX_IDELAY -clock io_clk -max $all_inputs
set_output_delay $MAX_ODELAY -clock io_clk -max [all_outputs]
set_input_delay  $MIN_IDELAY -clock io_clk -min $all_inputs
set_output_delay $MIN_ODELAY -clock io_clk -min [all_outputs]

# -----------------------------------------------------------------------------
# False Paths
set_false_path -from [get_ports use_bpip]
