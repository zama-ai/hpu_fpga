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
set_false_path -to [get_cells -hierarchical -filter {NAME =~ *fifo_handle/nb_word_mrmac_reg[0]*}]

set_false_path -to [get_cells -hierarchical -filter {NAME =~ *fifo_handle/cdc_tx_empty_reg[0]*}]
set_false_path -to [get_cells -hierarchical -filter {NAME =~ *fifo_handle/cdc_tx_rd_rst_busy_reg[0]*}]
set_false_path -to [get_cells -hierarchical -filter {NAME =~ *fifo_handle/cdc_tx_data_valid_reg[0]*}]
set_false_path -to [get_cells -hierarchical -filter {NAME =~ *fifo_handle/cdc_rd_data_count_reg[0]*}]

set_false_path -to [get_cells -hierarchical -filter {NAME =~ *fifo_handle/cdc_clk_cnt_reg[0]*}]
set_false_path -to [get_cells -hierarchical -filter {NAME =~ *fifo_handle/cdc_trigger_rd_cnt_reg[0]*}]
