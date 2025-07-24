
# == Ethernet ip
# clock creation
create_clock -period 3.103 -name gt_ref_clk_p -waveform {0.000 1.552} [get_ports gt_ref_clk_p]
# timing constraints
set_max_delay -datapath_only -from [get_clocks -of_objects [get_pins -hierarchical -filter {NAME =~ */gt_quad_base*/inst/quad_inst/CH0_TXOUTCLK}]] -to [get_clocks -of_objects [get_pins -hierarchical -filter {NAME =~ */i_*_axis_clk_wiz_*/inst/clock_primitive_inst/MMCME5_inst/CLKOUT0}]] 2.8
set_max_delay -datapath_only -from [get_clocks -of_objects [get_pins -hierarchical -filter {NAME =~ */i_*_axis_clk_wiz_*/inst/clock_primitive_inst/MMCME5_inst/CLKOUT0}]] -to [get_clocks -of_objects [get_pins -hierarchical -filter {NAME =~ */gt_quad_base*/inst/quad_inst/CH0_TXOUTCLK}]] 2.8
set_max_delay -datapath_only -from [get_clocks clk_pl_0] -to [get_clocks -of_objects [get_pins -hierarchical -filter {NAME =~ *_axis_clk_wiz_*/inst/clock_primitive_inst/MMCME5_inst/CLKOUT0}]] 2.8

set_clock_groups -quiet -name pl0_ref_clk_0 -asynchronous -group [get_clocks -of_objects [get_pins i_mrmac_0_cips_wrapper/mrmac_0_cips_i/pl0_ref_clk_0]]
