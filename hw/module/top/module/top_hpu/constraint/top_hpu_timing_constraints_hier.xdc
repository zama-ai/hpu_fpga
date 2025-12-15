# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
# Description  : Timing constraints for hierarchical synthesis
# ----------------------------------------------------------------------------------------------
#
# ==============================================================================================

# == Ethernet ip
# quasi-static signals
set_false_path -through [get_nets -hierarchical -regexp -filter { NAME =~ ".*multi_hpu_dma/gt_line_rate.*"}]
set_false_path -through [get_nets -hierarchical -regexp -filter { NAME =~ ".*multi_hpu_dma/gt_loopback.*"}]

# asynchronous reset signals
set_false_path -through [get_nets  -hierarchical -regexp -filter { NAME =~ ".*gt_reset_rx_datapath.*"}]
set_false_path -through [get_nets  -hierarchical -regexp -filter { NAME =~ ".*gt_reset_tx_datapath.*"}]
set_false_path -through [get_nets  -hierarchical -regexp -filter { NAME =~ ".*gt_reset_all.*"}]

# note that gt_rx_reset_done and gt_tx_reset_done are clocked with axi_clk. same clock as the regfile that reads them.



