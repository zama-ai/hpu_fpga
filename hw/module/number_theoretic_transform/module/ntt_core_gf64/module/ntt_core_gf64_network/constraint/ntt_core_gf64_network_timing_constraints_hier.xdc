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

# forcing usage of BRAM for NTT network RAM
set_property RAM_STYLE BLOCK [get_cells -hierarchical -regexp " .*ntt_ntw_ram/ram_1R1W/ram_1R1W_core/a_reg.*"]
