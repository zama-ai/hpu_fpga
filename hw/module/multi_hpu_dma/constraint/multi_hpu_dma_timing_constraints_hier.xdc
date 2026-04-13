# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
# Description  : Hierarchical constraints for multi_hpu_dma
# ----------------------------------------------------------------------------------------------
#
# This file contains:
#    - false_path for quasi-static CDC signals (CFG <-> ETH)
#    - ram_style constraints for FIFO instances (distributed / block / ultra)
#
# Clock domains:
#    - clk_mhdma_cfg : configuration (AXI4-Lite, regfile)
#    - clk_mhdma     : axi stream clock from MRMAC if (same as QSFP, HBM AXI4)
# both are synchronous, from the same MMCM
#
# ==============================================================================================

# Quasi static signals
set_false_path -to [get_cells -hierarchical -filter {NAME =~ *mhdma_bridge/*hpu_ids_cdc_reg*}]

set_false_path -from    [get_cells -hierarchical -regexp -filter { NAME =~ ".*/r_mhdma_lane_debug_reg.*"}]
set_false_path -from    [get_cells -hierarchical -regexp -filter { NAME =~ ".*/r_mhdma_system_timeout_notify_reg.*"}]
set_false_path -from    [get_cells -hierarchical -regexp -filter { NAME =~ ".*/r_mhdma_system_timeout_read_req_reg.*"}]

set_false_path -through [get_cells -hierarchical -regexp -filter { NAME =~ ".*/r_mhdma_system_lane_reg.*"}]

set_false_path -to [get_cells -hierarchical -filter {NAME =~ *mhdma_slave/*phy_addr_reg*}] -from [get_cells -hierarchical -filter {NAME =~ *hpu_regif_core_mhdma_2in3/*addr_2in3_ct_*_reg*}]
set_false_path -to [get_cells -hierarchical -filter {NAME =~ *mhdma_master/*phy_addr_reg*}] -from [get_cells -hierarchical -filter {NAME =~ *hpu_regif_core_mhdma_2in3/*addr_2in3_ct_*_reg*}]

# ==============================================================================================
# RAM style constraints for FIFO instances
# ==============================================================================================

# ------------------------------------------------------------------------------
# Distributed RAM (LUTRAM) - small control & command FIFOs
# ------------------------------------------------------------------------------

# Master: notify retry buffer (depth=REQ_FIFO_DEPTH=128, ~60b)
set_property ram_style "distributed" [get_cells -hier -filter {NAME =~ *mhdma_master/*nrqq_fifo_retries/ram/ram_1R1W/ram_1R1W_core/a_reg*}]

# Slave: notify RX command queue (depth=NRX_DEPTH=4, $bits(command_t)=96b)
set_property ram_style "distributed" [get_cells -hier -filter {NAME =~ *mhdma_slave/*fifo_nrx_commands/ram/ram_1R1W/ram_1R1W_core/a_reg*}]

# Slave: read request command queue (depth=RREQ_CMD_DEPTH=128, $bits(command_t)=96b)
set_property ram_style "distributed" [get_cells -hier -filter {NAME =~ *mhdma_slave/*rreq_command_queue/ram/ram_1R1W/ram_1R1W_core/a_reg*}]

# ------------------------------------------------------------------------------
# Block RAM (BRAM) : data-path FIFOs
# ------------------------------------------------------------------------------

# Decoder: RX command queue (depth=RX_FIFO_DEPTH=256, $bits(command_t)=96b, ~24Kb)
set_property ram_style "block" [get_cells -hier -filter {NAME =~ *mhdma_decoder/*fifo_rx_cmd/ram/ram_1R1W/ram_1R1W_core/a_reg*}]

# # Master: ciphertext RX FIFO (depth=CT_NB_COEF=2049, MRMAC_AXIS_W=64b, ~131Kb)
# set_property ram_style "block" [get_cells -hier -filter {NAME =~ *mhdma_master/*fifo_ce_rx/ram/ram_1R1W/ram_1R1W_core/a_reg*}]

# Slave: per-PC read data buffer (depth=FIFO_PC_DEPTH=CT_NB_WORDS_AXI4/2, width=AXI4_DATA_W; total ~CT_SIZE/2 = ~64Kb regardless of AXI4_DATA_W)
set_property ram_style "block" [get_cells -hier -filter {NAME =~ *mhdma_slave/*fifo_pc_read/ram/ram_1R1W/ram_1R1W_core/a_reg*}]

# Slave: ciphertext emission FIFO (depth=CT_NB_COEF=2049, MRMAC_AXIS_W=64b, ~131Kb)
set_property ram_style "block" [get_cells -hier -filter {NAME =~ *mhdma_slave/*fifo_ce/ram/ram_1R1W/ram_1R1W_core/a_reg*}]

# Formatter: ciphertext store-and-forward FIFO (depth=NB_WORDS_PAYLOAD=184, MRMAC_AXIS_W=64b, ~11.5Kb)
set_property ram_style "block" [get_cells -hier -filter {NAME =~ *mhdma_formatter/*fifo_ce/ram/ram_1R1W/ram_1R1W_core/a_reg*}]

# ------------------------------------------------------------------------------
# URAM : data-path FIFOs
# ------------------------------------------------------------------------------

# Master: ciphertext RX FIFO (depth=CT_NB_COEF=2049, MRMAC_AXIS_W=64b, ~131Kb)
set_property ram_style "ultra" [get_cells -hier -filter {NAME =~ *mhdma_master/*fifo_ce_rx/ram/ram_1R1W/ram_1R1W_core/a_reg*}]

# Slave: per-PC read data buffer (depth=FIFO_PC_DEPTH=CT_NB_WORDS_AXI4/2=256, AXI4_DATA_W=256b, ~64Kb)
# set_property ram_style "ultra" [get_cells -hier -filter {NAME =~ *mhdma_slave/*fifo_pc_read/ram/ram_1R1W/ram_1R1W_core/a_reg*}]
