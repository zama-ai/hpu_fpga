# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
# Description  : Timing & general constraints for FPGA
# ----------------------------------------------------------------------------------------------
#
# ==============================================================================================

# To be reviewed
set_false_path -to [get_cells -hierarchical -filter {NAME =~ *mhdma_trace/nb_word_mrmac_cdc_reg[0]*}]
set_false_path -to [get_cells -hierarchical -filter {NAME =~ *mhdma_trace/reset_registers_cdc_reg[0]*}]

set_false_path -to [get_cells -hierarchical -filter {NAME =~ *mhdma_trace/cdc_clk_cnt_reg[0]*}]
set_false_path -to [get_cells -hierarchical -filter {NAME =~ *mhdma_trace/cdc_trigger_rd_cnt_reg[0]*}]
set_false_path -to [get_cells -hierarchical -filter {NAME =~ *mhdma_trace/cdc_tx_rd_rst_busy_reg[0]*}]
set_false_path -to [get_cells -hierarchical -filter {NAME =~ *mhdma_trace/cdc_valid_words_reg[0]*}]
set_false_path -to [get_cells -hierarchical -filter {NAME =~ *mhdma_trace/cdc_sop_cnt_reg[0]*}]

set_false_path -to [get_cells -hierarchical -filter {NAME =~ *mhdma_trace/cdc_tx_empty_reg[0]*}]
set_false_path -to [get_cells -hierarchical -filter {NAME =~ *mhdma_trace/cdc_tx_rd_rst_busy_reg[0]*}]
set_false_path -to [get_cells -hierarchical -filter {NAME =~ *mhdma_trace/cdc_tx_data_valid_reg[0]*}]
set_false_path -to [get_cells -hierarchical -filter {NAME =~ *mhdma_trace/cdc_rd_data_count_reg[0]*}]

# Quasi static signals
set_false_path -to [get_cells -hierarchical -filter {NAME =~ *mhdma_bridge/*hpu_ids_cdc_reg*}]

set_false_path -from    [get_cells -hierarchical -regexp -filter { NAME =~ ".*/r_mhdma_lane_debug_reg.*"}]
set_false_path -from    [get_cells -hierarchical -regexp -filter { NAME =~ ".*/r_mhdma_system_timeout_notify_reg.*"}]
set_false_path -from    [get_cells -hierarchical -regexp -filter { NAME =~ ".*/r_mhdma_system_timeout_read_req_reg.*"}]

set_false_path -through [get_cells -hierarchical -regexp -filter { NAME =~ ".*/r_mhdma_system_lane_reg.*"}]

# raises concerning warnings:
set_false_path -to [get_cells -hierarchical -filter {NAME =~ *mhdma_slave/*phy_addr_reg*}] -from [get_cells -hierarchical -filter {NAME =~ *hpu_regif_core_eth_2in3/*addr_2in3_ct_*}]
set_false_path -to [get_cells -hierarchical -filter {NAME =~ *mhdma_master/*phy_addr_reg*}] -from [get_cells -hierarchical -filter {NAME =~ *hpu_regif_core_eth_2in3/*addr_2in3_ct_*}]

# Use URAM for ciphertext buffering
# set_property ram_style "ultra" [get_cells -hier -regexp .*fifo_read_pc[*]/ram/ram_1R1W/ram_1R1W_core/a_reg.*]
# set_property cascade_height 8 [get_cells -hier -regexp .*fifo_read_pc[*]/ram/ram_1R1W/ram_1R1W_core/a_reg.*]

# set_property ram_style "ultra" [get_cells -hier -regexp .*fifo_ce[*]/ram/ram_1R1W/ram_1R1W_core/a_reg.*]
# set_property cascade_height 8 [get_cells -hier -regexp .*fifo_ce[*]/ram/ram_1R1W/ram_1R1W_core/a_reg.*]
