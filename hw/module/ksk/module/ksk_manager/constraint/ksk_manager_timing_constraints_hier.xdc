# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
# Description  : Timing constraints for hierarchical synthesis
# ----------------------------------------------------------------------------------------------
#
# This file contains:
#   Module specific constraints, to be kept when doing hierarchical synthesis.
# ==============================================================================================

# Use Ultra RAM
set_property ram_style "ultra" [get_cells -hier -regexp .*ksk_ram/ram_1R1W/ram_1R1W_core/a_reg.*]
set_property cascade_height 8 [get_cells -hier -regexp .*ksk_ram/ram_1R1W/ram_1R1W_core/a_reg.*]
