# Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-License-Identifier: MIT

# set workspace to current directory
setws .

# read in passed arguments from command line
set xsa [lindex $argv 0]
puts "config xsa ==> $xsa"

set os [lindex $argv 1]
puts "config os ==> $os"

platform create -name "amc_bsp" -hw $xsa -proc "shell_wrapper_cips_pspmc_0_psv_cortexr5_0" -os $os

bsp config stdin shell_wrapper_cips_pspmc_0_psv_sbsauart_0
bsp config stdout shell_wrapper_cips_pspmc_0_psv_sbsauart_0

bsp setlib xilfpga
bsp setlib xilmailbox
bsp getlibs

platform generate


