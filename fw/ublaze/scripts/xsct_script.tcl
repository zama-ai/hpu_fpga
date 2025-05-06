# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
#
# Let's Generate files we need with Vitis project mode and quitt

setws .
platform create -name fw_platform -hw $::env(PROJECT_DIR)/fw/gen/$::env(MICROBLAZE_CONF)/ip_$::env(MICROBLAZE_CONF)/shell/ublaze_wrapper.xsa -no-boot-bsp
platform active fw_platform
domain create -name "fw_domain" -os standalone -proc ublaze_0

bsp getdrivers

platform generate

app create -name fw_app -template {Empty Application(C)} -platform fw_platform -domain fw_domain

lscript generate -name fw_platform -path $::env(PROJECT_DIR)/fw/gen/$::env(MICROBLAZE_CONF)/ip_$::env(MICROBLAZE_CONF)/shell
