
# == Ethernet ip
# timing constraints
set_max_delay -datapath_only -from [get_clocks -of_objects [get_pins -hierarchical -filter {NAME =~ */gt_quad_base*/inst/quad_inst/CH0_TXOUTCLK}]] -to [get_clocks -of_objects [get_pins -hierarchical -filter {NAME =~ */i_*_axis_clk_wiz_*/inst/clock_primitive_inst/MMCME5_inst/CLKOUT0}]] 2.8
set_max_delay -datapath_only -from [get_clocks -of_objects [get_pins -hierarchical -filter {NAME =~ */i_*_axis_clk_wiz_*/inst/clock_primitive_inst/MMCME5_inst/CLKOUT0}]] -to [get_clocks -of_objects [get_pins -hierarchical -filter {NAME =~ */gt_quad_base*/inst/quad_inst/CH0_TXOUTCLK}]] 2.8
set_max_delay -datapath_only -from [get_clocks clk_pl_0] -to [get_clocks -of_objects [get_pins -hierarchical -filter {NAME =~ *_axis_clk_wiz_*/inst/clock_primitive_inst/MMCME5_inst/CLKOUT0}]] 2.8

set_clock_groups -quiet -name pl0_ref_clk_0 -asynchronous -group [get_clocks -of_objects [get_pins i_mrmac_0_cips_wrapper/mrmac_0_cips_i/pl0_ref_clk_0]]

# quasi-static signals
set_false_path -through [get_nets -hierarchical -regexp -filter { NAME =~ ".*multi_hpu_dma/gt_line_rate.*"}]
set_false_path -through [get_nets -hierarchical -regexp -filter { NAME =~ ".*multi_hpu_dma/gt_loopback.*"}]
set_false_path -from [get_cells -hierarchical -regexp -filter { NAME =~ ".*/r_line_parameter_reg.*"}]

# asynchronous reset signals
set_false_path -through [get_nets  -hierarchical -regexp -filter { NAME =~ ".*gt_reset_rx_datapath.*"}]
set_false_path -through [get_nets  -hierarchical -regexp -filter { NAME =~ ".*gt_reset_tx_datapath.*"}]
set_false_path -through [get_nets  -hierarchical -regexp -filter { NAME =~ ".*gt_reset_all.*"}]

# note that gt_rx_reset_done and gt_tx_reset_done are clocked with axi_clk. same clock as the regfile that reads them.



