# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ==============================================================================================

# == timing constraints
create_clock -period 3.103 -name gt_ref_clk_p -waveform {0.000 1.552} [get_ports gt_ref_clk_p]

set qsfp_mmcm_pin     [get_pins -hierarchical -filter {NAME =~ *hpu_plug_wrapper/hpu_plug_i/shell_wrapper/clock_reset/mhdma_clk_wiz/clk_out2*}]
set mhdma_cfg_mmcm_pin [get_pins -hierarchical -filter {NAME =~ *hpu_plug_wrapper/hpu_plug_i/shell_wrapper/clock_reset/mhdma_clk_wiz/clk_out1*}]

# CDC between mhdma_cfg_clk (100MHz, clk_out1) and clk_mhdma (390MHz, clk_out2) from same MMCM
# These paths cross clock domains through the MRMAC AXI-APB bridge and regif without proper synchronizers. set_max_delay tells Vivado to constrain only the datapath delay.
# IMPORTANT: only target the unsynchronized AXI bus paths, NOT the XPM CDC primitives which have their own internal constraints.
set_max_delay -datapath_only -from \
    [get_clocks -of_objects $mhdma_cfg_mmcm_pin] -to \
    [get_clocks -of_objects $qsfp_mmcm_pin \
] 2.558

set_max_delay -datapath_only -from \
    [get_clocks -of_objects $qsfp_mmcm_pin] -to \
    [get_clocks -of_objects $mhdma_cfg_mmcm_pin \
] 2.558

# we are using clk_pl_1 - freerun 33Mhz - to generate qsfp_mmcm
set_max_delay -datapath_only -from \
    [get_clocks clk_pl_1] -to \
    [get_clocks -of_objects $qsfp_mmcm_pin \
] 2.8

# Setting max delay for all TX channels
# MMCM clock and QSFP tx clock will be asynchronous
set_max_delay -datapath_only -from \
    [get_clocks -of_objects [get_pins -hierarchical -filter {NAME =~ */gt_quad_base*/inst/quad_inst/CH*_TXOUTCLK}]] -to \
    [get_clocks -of_objects $qsfp_mmcm_pin \
] 2.8

set_max_delay -datapath_only -from \
  [get_clocks -of_objects $qsfp_mmcm_pin] -to \
  [get_clocks -of_objects [get_pins -hierarchical -filter {NAME =~ */gt_quad_base*/inst/quad_inst/CH*_TXOUTCLK}] \
] 2.8

# == Ethernet placement
# top right SL1, bank 111 - port 4. Meant for MRMAC_X0Y3, one clock region away from this transceiver.
set_property LOC GTM_QUAD_X0Y9    [get_cells -hier -filter {name =~ */gt_quad_base*/inst/quad_inst}]
set_property LOC GTM_REFCLK_X0Y18 [get_cells -hier -filter {name =~ */util_ds_buf*/U0/USE_IBUFDS_GTME5.GEN_IBUFDS_GTME5[0].IBUFDS_GTME5_U}]
