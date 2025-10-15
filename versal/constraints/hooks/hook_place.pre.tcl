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
    # Vivado 2025.1 has a don't touch on cips. Theses commands are derived from XILINX
    set_property dont_touch 0 [get_nets -of [get_pins -hierarchical -regexp {.*/clock_reset/pcie_mgmt_pdi_reset/pcie_mgmt_pdi_reset_gpio/gpio2_io_i}]]
    set_property dont_touch 0 [get_cells -hierarchical -regexp -filter { NAME =~ ".*/cips/inst/pspmc_0/inst"}]
    set_property dont_touch 0 [get_cells -hierarchical -regexp -filter { NAME =~ ".*/cips"}]

    disconnect_net -objects ${PS9_IRQ_pin}
    connect_net -hierarchical -net [get_nets -of [get_pins -hierarchical -regexp {.*/clock_reset/pcie_mgmt_pdi_reset/pcie_mgmt_pdi_reset_gpio/gpio2_io_i}]] -objects ${PS9_IRQ_pin}
} else {
    puts "Unable to get PMCPLIRQ pin for Force Reset rewiring."
}

# Enable GCLK Deskew
set_property GCLK_DESKEW CALIBRATED [get_nets hpu_plug_wrapper/hpu_plug_i/shell_wrapper/clock_reset/usr_clk_wiz/inst/clock_primitive_inst/clk_out1]

### pblocks

# Constraining the clock source and reset roots to minimize skew
add_cells_to_pblock [get_pblocks pblock_CLKROOT] \
    [get_cells -hier -regexp \
      -filter { \
        NAME =~ .*/clock_primitive_inst/BUFGCE.* \
     }]

# Make sure that the reset root is at SLR0
add_cells_to_pblock [get_pblocks pblock_SLR0] \
    [get_cells -hier -regexp -filter {NAME =~ .*/clock_reset/usr_._psr \
                                   || NAME =~ .*/hpu_soft_reset}]

# And pin each reset distribution logic to the right SLR
add_cells_to_pblock [get_pblocks pblock_SLR2] \
    [get_cells -hier -regexp -filter {NAME =~ .*/prc1_clk_rst}]
add_cells_to_pblock [get_pblocks pblock_SLR1] \
    [get_cells -hier -regexp -filter {NAME =~ .*/prc2_clk_rst}]
add_cells_to_pblock [get_pblocks pblock_SLR0] \
    [get_cells -hier -regexp -filter {NAME =~ .*/prc3_clk_rst}]

add_cells_to_pblock [get_pblocks pblock_SLR0] [get_cells -hier -regexp .*/hpu_3parts_3in3_core] -clear_locs
add_cells_to_pblock [get_pblocks pblock_SLR1] [get_cells -hier -regexp .*/hpu_3parts_2in3_core] -clear_locs
add_cells_to_pblock [get_pblocks pblock_SLR2] [get_cells -hier -regexp .*/hpu_3parts_1in3_core] -clear_locs
add_cells_to_pblock [get_pblocks pblock_SLR2] [get_cells -hier -regexp .*/fifo_element_isc_dop] -clear_locs
add_cells_to_pblock [get_pblocks pblock_SLR2] [get_cells -hier -regexp .*/fifo_element_isc_ack] -clear_locs

# Constrain SLR crossing flops
add_cells_to_pblock -quiet [get_pblocks pblock_SLL2BOT] [get_cells -hier -regexp -filter {NAME =~ ".*/p1_p2_sll.*/in_pipe"}]
add_cells_to_pblock -quiet [get_pblocks pblock_SLL2BOT] [get_cells -hier -regexp -filter {NAME =~ ".*/p2_p1_sll.*/out_pipe"}]

add_cells_to_pblock -quiet [get_pblocks pblock_SLL1TOP] [get_cells -hier -regexp -filter {NAME =~ ".*/p1_p2_sll.*/out_pipe"}]
add_cells_to_pblock -quiet [get_pblocks pblock_SLL1TOP] [get_cells -hier -regexp -filter {NAME =~ ".*/p2_p1_sll.*/in_pipe"}]

add_cells_to_pblock -quiet [get_pblocks pblock_SLL1BOT] [get_cells -hier -regexp -filter {NAME =~ ".*/p2_p3_sll.*/in_pipe"}]
add_cells_to_pblock -quiet [get_pblocks pblock_SLL1BOT] [get_cells -hier -regexp -filter {NAME =~ ".*/p3_p2_sll.*/out_pipe"}]

add_cells_to_pblock -quiet [get_pblocks pblock_SLL0TOP] [get_cells -hier -regexp -filter {NAME =~ ".*/p3_p2_sll.*/in_pipe"}]
add_cells_to_pblock -quiet [get_pblocks pblock_SLL0TOP] [get_cells -hier -regexp -filter {NAME =~ ".*/p2_p3_sll.*/out_pipe"}]

# This is an alternate way of constraining the SLL flops and it supposedly uses IMUX registers,
# sparing registers for other uses. However, generates DRC errors.
#set sll_regs [ \
#    get_cells -hier -regexp -filter { \
#           NAME =~ ".*gen_inter_part_pipe\..*_ntt_proc_.*_dly.*" \
#        || NAME =~ ".*/.*_sll.*/in_pipe/.*reg.*" \
#        || NAME =~ ".*/.*_sll.*/out_pipe/.*reg.*" \
#        || NAME =~ ".*/hpu_3parts_1in3_core/pe_pbs_with_entry_subsidiary/decomp_balanced_sequential/gen_loop\[.*\].gen_no_first_coef.decomp_balseq_core/s1_subw_result_reg\[.*\]" \
#        || NAME =~ ".*/hpu_3parts_2in3_core/pe_pbs_with_ntt_core_head/gen_head_ntt.gen_ntt_core_gf64.ntt_core_gf64_head/ntt_core_gf64_middle/gen_fwd_ntt.gen_fwd_loop\[.*\].ntt_core_gf64_bu_stage_column_fwd/gen_bu_loop\[.*\].gen_not_0.ntt_core_gf64_bu_cooley_tukey/gen_do_shift.ntt_core_gf64_pmr_shift_cst/in_delay_side/gen_latency.side_dly_reg\[.*\]\[.*\]" \
#        || NAME =~ ".*/hpu_3parts_2in3_core/pe_pbs_with_modsw/pep_br_mod_switch_to_2powerN/gen_modw_p_loop\[.*\].gen_modw_r_loop\[.*\].gen_modsw_inst_gt_0.mod_switch_to_2powerN/gen_out_reg.s2_result_reg\[.*\]" \
#    }
#]
#set_property USER_SLL_REG TRUE $sll_regs
