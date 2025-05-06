# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.

set cdir [pwd]
puts "current directory: $cdir"
source ${cdir}/../../uservars.tcl
puts "current PSI is: $::ntt_psi"

# PBLOCK
create_pblock pblock_pl
resize_pblock pblock_pl -add SLR0
resize_pblock pblock_pl -add SLR1
resize_pblock pblock_pl -add SLR2

create_pblock pblock_SLR0
resize_pblock pblock_SLR0 -add SLR0
create_pblock pblock_SLR1
resize_pblock pblock_SLR1 -add SLR1
create_pblock pblock_SLR2
resize_pblock pblock_SLR2 -add SLR2


# parent
set_property PARENT pblock_pl [get_pblocks pblock_SLR0] [get_pblocks pblock_SLR1] [get_pblocks pblock_SLR2]

set_property IS_SOFT TRUE [get_pblocks pblock_SLR*]


#Set false path
set_false_path -from [get_pins -hierarchical -regexp {.*hpu_regif_cfg_.in3/.*reg.*/C}] -to [get_clocks  -regexp {.*prc_clk.*}]
# TODO : Temporary solution : to be removed, when a correct solution is found
if {$::ntt_psi == 64} {
    set_false_path -from [get_pins -hierarchical -regexp -filter {NAME =~ hpu_plug_wrapper/hpu_plug_i/shell_wrapper/clock_reset/usr_0_psr/U0/ACTIVE_LOW_BSR_OUT_DFF\[0\].FDRE_BSR_N.*/C}]
}
