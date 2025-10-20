# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
# Description  : Timing constraints for an out-of-context (OOC) synthesis
# ----------------------------------------------------------------------------------------------
#
# This file contains:
#    - the clock definition
#    - constraints on input and output ports
# ----------------------------------------------------------------------------------------------
# Create clock
# ==============================================================================================
set_false_path -to [get_cells -hierarchical -filter {NAME =~ *debug_lane/nb_word_mrmac_cdc_reg[0]*}]
set_false_path -to [get_cells -hierarchical -filter {NAME =~ *debug_lane/reset_registers_cdc_reg[0]*}]

set_false_path -to [get_cells -hierarchical -filter {NAME =~ *debug_lane/cdc_clk_cnt_reg[0]*}]
set_false_path -to [get_cells -hierarchical -filter {NAME =~ *debug_lane/cdc_trigger_rd_cnt_reg[0]*}]
set_false_path -to [get_cells -hierarchical -filter {NAME =~ *debug_lane/cdc_tx_rd_rst_busy_reg[0]*}]
set_false_path -to [get_cells -hierarchical -filter {NAME =~ *debug_lane/cdc_valid_words_reg[0]*}]
set_false_path -to [get_cells -hierarchical -filter {NAME =~ *debug_lane/cdc_sop_cnt_reg[0]*}]

set_false_path -to [get_cells -hierarchical -filter {NAME =~ *debug_lane/cdc_tx_empty_reg[0]*}]
set_false_path -to [get_cells -hierarchical -filter {NAME =~ *debug_lane/cdc_tx_rd_rst_busy_reg[0]*}]
set_false_path -to [get_cells -hierarchical -filter {NAME =~ *debug_lane/cdc_tx_data_valid_reg[0]*}]
set_false_path -to [get_cells -hierarchical -filter {NAME =~ *debug_lane/cdc_rd_data_count_reg[0]*}]
set_false_path -to [get_cells -hierarchical -filter {NAME =~ *debug_lane/cdc_qsfp_tx_tready_reg[0]*}]
