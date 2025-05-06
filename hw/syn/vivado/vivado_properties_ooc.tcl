# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
#  Define here the properties used by vivado for out-of-context synthesis
# ----------------------------------------------------------------------------------------------
#  Current run is OOC
# ==============================================================================================

set_property -name {STEPS.SYNTH_DESIGN.ARGS.NO_SRLEXTRACT} -value true                  -objects [get_runs synth_1]
set_property -name {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} -value {-mode out_of_context} -objects [get_runs synth_1]
