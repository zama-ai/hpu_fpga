# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
#  Define here the properties used by vivado
# ==============================================================================================

set local_constraint_files [get_files *_local.xdc -quiet]

if {[llength $local_constraint_files]} {
    # Local constraints are only used in OOC
    set_property USED_IN {synthesis implementation out_of_context} $local_constraint_files
    # Process *_local.xdc file first
    set non_local_constraint_files [get_files -regexp .*(!_local)\.xdc -quiet]
    if {[llength $non_local_constraint_files]} {
        set_property PROCESSING_ORDER LATE $non_local_constraint_files 
    }
}

# ROM synthesis
# Upgrade warning message into error, when the file containing the ROM data is not found.
set_msg_config -id {Synth 8-2898} -new_severity {ERROR}

 #set_property my_property "my_value" [current_project]
