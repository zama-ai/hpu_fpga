# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
# Description  : Timing constraints for an out-of-context (OOC) synthesis
# ----------------------------------------------------------------------------------------------
#
# ==============================================================================================

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
set_false_path -to [get_cells -hierarchical -filter {NAME =~ *mhdma_trace/cdc_qsfp_tx_tready_reg[0]*}]
