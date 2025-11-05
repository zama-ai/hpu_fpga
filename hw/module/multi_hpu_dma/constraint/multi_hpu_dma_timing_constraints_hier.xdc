# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
# Description  : Timing & general constraints for FPGA
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

# Use URAM for ciphertext buffering
set_property ram_style "ultra" [get_cells -hier -regexp .*ce_read_fifo_ping/ram/ram_1R1W/ram_1R1W_core/a_reg.*]
set_property cascade_height 8 [get_cells -hier -regexp .*ce_read_fifo_ping/ram/ram_1R1W/ram_1R1W_core/a_reg.*]
set_property ram_style "ultra" [get_cells -hier -regexp .*ce_read_fifo_pong/ram/ram_1R1W/ram_1R1W_core/a_reg.*]
set_property cascade_height 8 [get_cells -hier -regexp .*ce_read_fifo_pong/ram/ram_1R1W/ram_1R1W_core/a_reg.*]

set_property ram_style "ultra" [get_cells -hier -regexp .*rrq_write_fifo_ping/ram/ram_1R1W/ram_1R1W_core/a_reg.*]
set_property cascade_height 8 [get_cells -hier -regexp .*rrq_write_fifo_ping/ram/ram_1R1W/ram_1R1W_core/a_reg.*]
set_property ram_style "ultra" [get_cells -hier -regexp .*rrq_write_fifo_pong/ram/ram_1R1W/ram_1R1W_core/a_reg.*]
set_property cascade_height 8 [get_cells -hier -regexp .*rrq_write_fifo_pong/ram/ram_1R1W/ram_1R1W_core/a_reg.*]
