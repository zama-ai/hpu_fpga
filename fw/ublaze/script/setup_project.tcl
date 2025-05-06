# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
# Poject script for microblaze.
# ----------------------------------------------------------------------------------------------
# Names are hardcoded here for simplicity.
# We should avoid calling the wrapper with a name including "microblaze"
# ==============================================================================================

set prj_name "project_microblaze"
set bd_name_wrapper "ublaze_wrapper"

set local_xilinx_part [lindex $argv 0]

# Project setup
create_project $prj_name .

#set_property PART $::env(XILINX_PART) [current_project]
set_property PART $local_xilinx_part [current_project]

# We call the microblaze configuation here
source $::env(PROJECT_DIR)/fw/ublaze/core_config/$::env(MICROBLAZE_CONF)/build_microblaze.tcl

# Generation of needed extra files for simulation
set bd_file [exec find . -type f -name *.bd*]

generate_target all [get_files  $bd_file]

export_ip_user_files -of_objects [get_files $bd_file] -no_script -sync -force -quiet
export_simulation -of_objects [get_files $bd_file] -directory ./$prj_name.ip_user_files/sim_scripts -simulator xsim  -ip_user_files_dir ./$prj_name.ip_user_files  -ipstatic_source_dir ./$prj_name.ip_user_files/ipstatic -use_ip_compiled_libs

make_wrapper -files [get_files $bd_file] -top
add_files -norecurse ./$prj_name.gen/sources_1/bd/$bd_name/hdl/$bd_name_wrapper.v

write_hw_platform -fixed -force -file ./$bd_name_wrapper.xsa
