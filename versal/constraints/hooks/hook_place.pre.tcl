# (c) Copyright 2024, Advanced Micro Devices, Inc.
# 
# Permission is hereby granted, free of charge, to any person obtaining a 
# copy of this software and associated documentation files (the "Software"), 
# to deal in the Software without restriction, including without limitation 
# the rights to use, copy, modify, merge, publish, distribute, sublicense, 
# and/or sell copies of the Software, and to permit persons to whom the 
# Software is furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in 
# all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR 
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, 
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL 
# THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER 
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING 
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER 
# DEALINGS IN THE SOFTWARE.
############################################################
set cdir [pwd]
puts "current directory: $cdir"
source ${cdir}/../../uservars.tcl
puts "current PSI is: $::ntt_psi"

# Connect the DMA reset detection signal to the PMC Interrupt input to allow a full PDI reload to be triggered on PCIe hot reset
set PS9_IRQ_pin [get_pins -of [get_cells -hierarchical PS9_inst -filter { PARENT =~ "*cips*"}] -filter { REF_PIN_NAME =~ "PMCPLIRQ[4]"}]

set SHELL_VER $::env(SHELL_VER)

if {[llength ${PS9_IRQ_pin}] == 1} {
    disconnect_net -objects ${PS9_IRQ_pin}
    connect_net -hierarchical -net [get_nets -of [get_pins -hierarchical -regexp -filter { NAME =~ ".*/clock_reset/pcie_mgmt_pdi_reset/and_0/Res" }]] -objects ${PS9_IRQ_pin}
} else {
    puts "Unable to get PMCPLIRQ pin for Force Reset rewiring."
    error
}

### pblocks
if {$::ntt_psi == 64} {
    add_cells_to_pblock [get_pblocks pblock_SLR2] [get_cells -hier -regexp .*/hpu_3parts_1in3_core/.*]
    add_cells_to_pblock [get_pblocks pblock_SLR0] [get_cells -hier -regexp .*/hpu_3parts_3in3_core/.*]

    add_cells_to_pblock [get_pblocks pblock_SLR2] [get_cells -hier -regexp .*/hpu_3parts_2in3_core/pe_pbs_with_entry_subsidiary/.*]

    add_cells_to_pblock [get_pblocks pblock_SLR1] [get_cells -hier -regexp .*/hpu_3parts_2in3_core/pe_pbs_with_ntt_core_head/.*]
    add_cells_to_pblock [get_pblocks pblock_SLR1] [get_cells -hier -regexp .*/hpu_3parts_2in3_core/pe_pbs_with_ntt_core_tail/.*]
    add_cells_to_pblock [get_pblocks pblock_SLR1] [get_cells -hier -regexp .*/hpu_3parts_2in3_core/pe_pbs_with_modsw/.*]

    remove_cells_from_pblock [get_pblocks pblock_SLR2] [get_cells -hier -regexp -filter {NAME =~ .*/pep_mmacc_infifo/.*}]
    add_cells_to_pblock      [get_pblocks pblock_SLR1] [get_cells -hier -regexp -filter {NAME =~ .*/pep_mmacc_infifo/.*}]
} elseif {$::ntt_psi == 32} {
    add_cells_to_pblock [get_pblocks pblock_SLR2] [get_cells -hier -regexp .*/hpu_3parts_1in3_core/pe_pbs_with_entry_main/.*]
    add_cells_to_pblock [get_pblocks pblock_SLR2] [get_cells -hier -regexp .*/hpu_3parts_2in3_core/.*]
    add_cells_to_pblock [get_pblocks pblock_SLR1] [get_cells -hier -regexp .*/hpu_3parts_3in3_core/.*]
} else {
    # Do nothing. Let the tool place.
}

set generics [get_property generic [current_fileset]]

if { [expr $::ntt_psi == 64] && [expr [string first "INTER_PART_PIPE=2" $generics] >= 0] } {
  add_cells_to_pblock -quiet [get_pblocks pblock_SLR0] [get_cells -hier -regexp -filter {NAME =~ ".*gen_inter_part_pipe.out_p2_p3_ntt_proc_.*"}]
  add_cells_to_pblock -quiet [get_pblocks pblock_SLR1] [get_cells -hier -regexp -filter {NAME =~ ".*gen_inter_part_pipe.out_p3_p2_ntt_proc_.*"}]

  add_cells_to_pblock -quiet [get_pblocks pblock_SLR0] [get_cells -hier -regexp -filter {NAME =~ ".*gen_inter_part_pipe.in_p3_p2_ntt_proc_.*_dly.*"}]
  add_cells_to_pblock -quiet [get_pblocks pblock_SLR1] [get_cells -hier -regexp -filter {NAME =~ ".*gen_inter_part_pipe.in_p2_p3_ntt_proc_.*_dly.*"}]
}
