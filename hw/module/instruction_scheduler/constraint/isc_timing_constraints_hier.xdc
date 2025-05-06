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

# Limit the fanout to ease the P&R
set_property max_fanout 1024 [get_nets -hier -regexp -filter { NAME =~ .*isc_pool/c2_data.*vld.* }]
