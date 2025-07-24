# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.

# Put here commands to be applied post synthesis.

# post-synthesis CDC waivers
create_waiver -quiet -type CDC -id {CDC-13} -user "mrmac" -desc "The CDC-13 warning is waived, this is a level signal and this is safe to ignore" -tags "1101959"\
-from [get_pins -of [get_cells -hier -filter { name =~ *_cips_wrapper/*_cips_i/axi_gpio_gt_prbs_comm_ctl/*/gpio_core_*/Dual.gpio_Data_Out_reg*}] -filter { name =~ *C } ]\
-to [get_pins -hier -filter {name =~ */*_gt_wrapper/gt_quad_base/inst/quad_inst/CH*_RXRATE*}]

create_waiver -quiet -type CDC -id {CDC-13} -user "mrmac" -desc "The CDC-13 warning is waived, this is a level signal and this is safe to ignore" -tags "1101959"\
-from [get_pins -of [get_cells -hier -filter { name =~ *_cips_wrapper/*_cips_i/axi_gpio_gt_prbs_comm_ctl/*/gpio_core_*/Dual.gpio_Data_Out_reg*}] -filter { name =~ *C } ]\
-to [get_pins -hier -filter {name =~ */*_gt_wrapper/gt_quad_base/inst/quad_inst/CH*_TXRATE*}]

create_waiver -quiet -type CDC -id {CDC-1} -user "mrmac" -desc "This register drives multiple destination path and all are registered on the destination clocks " -tags "1101959"\
-from [get_pins -hier -filter { name =~ */*_exdes_support_i/*_core/inst/*_top/*/TX_CORE_CLK*}]\
-to [list [get_pins -of [get_cells -hier -filter {name =~ *_exdes/*_axis_stream_mux/axis_2stg_buff*.tdata_buff*_reg*}] -filter { name =~ *CE } ]\
[get_pins -of [get_cells -hier -filter {name =~ *_exdes/*_axis_stream_mux/axis_2stg_buff*.tkeep_buff*_reg*}] -filter { name =~ *CE } ]\
[get_pins -of [get_cells -hier -filter {name =~ *_exdes/*_axis_stream_mux/axis_2stg_buff*.tlast_buff*_reg*}] -filter { name =~ *CE } ]\
[get_pins -of [get_cells -hier -filter {name =~ *_exdes/*_axis_stream_mux/axis_2stg_buff*.tlast_buff*_reg*}] -filter { name =~ *D } ]\
[get_pins -of [get_cells -hier -filter {name =~ *_exdes/*_axis_stream_mux/axis_2stg_buff*.tvalid_buff*_reg*}] -filter { name =~ *D } ]]

create_waiver -quiet -type CDC -id {CDC-1} -user "mrmac" -desc "This register drives multiple destination path and all are registered on the destination clocks " -tags "1101959"\
-from [get_pins -of [get_cells -hier -filter { name =~ *_cips_wrapper/*_cips_i/*/gpio_core_*/*_Data_Out_reg*}] -filter { name =~ *C } ]\
-to [list [get_pins -of [get_cells -hier -filter {name =~ *_exdes/*_axis_stream_mux/axis_2stg_buff*.tdata_buff*_reg*}] -filter { name =~ *CE } ]\
[get_pins -of [get_cells -hier -filter {name =~ *_exdes/*_axis_stream_mux/axis_2stg_buff*.tdata_buff*_reg*}] -filter { name =~ *D } ]\
[get_pins -of [get_cells -hier -filter {name =~ *_exdes/*_axis_stream_mux/axis_2stg_buff*.tkeep_buff*_reg*}] -filter { name =~ *CE } ]\
[get_pins -of [get_cells -hier -filter {name =~ *_exdes/*_axis_stream_mux/axis_2stg_buff*.tkeep_buff*_reg*}] -filter { name =~ *D } ]\
[get_pins -of [get_cells -hier -filter {name =~ *_exdes/*_axis_stream_mux/axis_2stg_buff*.tlast_buff*_reg*}] -filter { name =~ *CE } ]\
[get_pins -of [get_cells -hier -filter {name =~ *_exdes/*_axis_stream_mux/axis_2stg_buff*.tlast_buff*_reg*}] -filter { name =~ *R } ]\
[get_pins -of [get_cells -hier -filter {name =~ *_exdes/*_axis_stream_mux/axis_2stg_buff*.tlast_buff*_reg*}] -filter { name =~ *D } ]\
[get_pins -of [get_cells -hier -filter {name =~ *_exdes/*_axis_stream_mux/axis_2stg_buff*.tvalid_buff*_reg*}] -filter { name =~ *D } ]]

create_waiver -quiet -type CDC -id {CDC-1} -user "mrmac" -desc "This register drives multiple destination path and all are registered on the destination clocks" -tags "1101959"\
-from [get_pins -of [get_cells -hier -filter { name =~ *_cips_wrapper/*_cips_i/proc_sys_reset_*/*/ACTIVE_LOW_PR_OUT_DFF*.FDRE_PER_*}] -filter { name =~ *C } ]\
-to [list [get_pins -of [get_cells -hier -filter {name =~ *_exdes/CLIENT*_FSM_r_reg*}] -filter { name =~ *S } ]\
[get_pins -of [get_cells -hier -filter {name =~ *_exdes/CLIENT*_FSM_r_reg*}] -filter { name =~ *R }]\
[get_pins -of [get_cells -hier -filter {name =~ *_exdes/client*_prbs_reg*}] -filter { name =~ *R }]\
[get_pins -of [get_cells -hier -filter {name =~ *_exdes/*_axis_stream_mux/axis_2stg_buff*.*_buff*_reg*}] -filter {name =~ *R}]\
[get_pins -of [get_cells -hier -filter {name =~ *_exdes/*_axis_stream_mux/axis_2stg_buff*.*_buff*_reg*}] -filter {name =~ *D}]]

create_waiver  -quiet -type CDC -id {CDC-10} -user "mrmac" -desc "This is a level signal and safe to ignore " -tags "1101959"\
-from [get_pins -of [get_cells -hier -filter {name =~ *_cips_wrapper/*_cips_i/axi_gpio_prbs_ctl/*/gpio_core_*/Dual.gpio*_Data_Out_reg*}] -filter { name =~ *C } ]\
-to [get_pins -hier -filter {name =~ */*_pkt_gen_mon_*/*_pkt_gen_*/DUPLEX_PKT_SIZE_*_reg*/CLR}]

create_waiver -quiet -type CDC -id {CDC-13} -user "mrmac" -desc "The CDC-13 is safe to ignore " -tags "1101959"\
-from [get_pins -of [get_cells -hier -filter {name =~ *_exdes/*_axis_stream_mux/axis_2stg_buff*.tlast_buff_reg*}] -filter { name =~ *C } ]\
-to [get_pins -hier -filter { name =~ */*_support_wrapper/*_exdes_support_i/*_core/*/*_core_0_top/*/TX_AXIS_TLAST_*}]

create_waiver -quiet -type CDC -id {CDC-13} -user "mrmac" -desc "The CDC-13 is safe to ignore " -tags "1101959"\
-from [get_pins -of [get_cells -hier -filter {name =~ *_exdes/*_axis_stream_mux/axis_2stg_buff*.tvalid_buff_reg*}] -filter { name =~ *C } ]\
-to [get_pins -hier -filter { name =~ */*_support_wrapper/*_exdes_support_i/*_core/*/*_core_0_top/*/TX_AXIS_TVALID_*}]

create_waiver -quiet -type CDC -id {CDC-11} -user "mrmac" -desc "This is a level signal and safe to ignore " -tags "1101959"\
-from [get_pins -of [get_cells -hier -filter {name =~ *_cips_wrapper/*_cips_i/*/gpio_core_*/Dual.gpio*_Data_Out_reg*}]  -filter { name =~ *C } ]\
-to [get_pins -hier -filter { name =~ *_exdes/*_pkt_gen_mon_*/*_pkt_gen_*/DUPLEX_PKT_SIZE_*_reg*/CLR}]

create_waiver -quiet -type CDC -id {CDC-7} -user "mrmac" -desc "This is a level signal and safe to ignore " -tags "1101959"\
-from [get_pins -of [get_cells -hier -filter {name =~ *_cips_wrapper/*_cips_i/*/gpio_core_*/Dual.gpio*_Data_Out_reg*}]  -filter { name =~ *C } ]\
-to [get_pins  -hier -filter { name =~ *_exdes/*_pkt_gen_mon_*/*_pkt_gen_*/*_reg*/CLR}]

 create_waiver -quiet -type CDC -id {CDC-7} -user "mrmac" -desc "This is a level signal and safe to ignore " -tags "1101959"\
-from [get_pins -of [get_cells -hier -filter  {name =~ *_cips_wrapper/*_cips_i/proc_sys_reset_*/*/ACTIVE_LOW_PR_OUT_DFF*.FDRE_PER_*}]  -filter { name =~ *C } ]\
-to [get_pins  -hier -filter { name =~ *_exdes/*_trig_in_edge_detect_reg/CLR}]

 create_waiver -quiet -type CDC -id {CDC-10} -user "mrmac" -desc "This is a level signal and safe to ignore " -tags "1101959"\
-from [get_pins -of [get_cells -hier -filter  {name =~ *_cips_wrapper/*_cips_i/proc_sys_reset_*/*/ACTIVE_LOW_PR_OUT_DFF*.FDRE_PER_*}]  -filter { name =~ *C } ]\
-to [get_pins  -hier -filter { name =~ *_exdes/*_pkt_gen_mon_*/*_pkt_gen_*/DUPLEX_PKT_SIZE_*_reg*/CLR}]

create_waiver -quiet -type CDC -id {CDC-14} -user "mrmac" -desc "The CDC-14 is safe to ignore" -tags "1101959"\
-from [get_pins -of [get_cells -hier -filter  {name =~ *_exdes/*_axis_stream_mux/axis_2stg_buff*_buff*_reg* }]  -filter { name =~ *C } ]\
-to [get_pins -hier -filter {name =~ *_exdes/*_exdes_support_wrapper/*/*_core/*/*_top/*/TX_AXIS_*}]

create_waiver -quiet -type CDC -id {CDC-7} -user "mrmac" -desc "This is a level signal and safe to ignore " -tags "1101959"\
-from [get_pins -of [get_cells -hier -filter  {name =~ *_cips_wrapper/*_cips_i/*/gpio_core_*/Dual.gpio*_Data_Out_reg*}]  -filter { name =~ *C } ]\
-to [get_pins  -hier -filter { name =~ *_exdes/*_pkt_gen_mon_*/*_pkt_gen_*/*_reg*/PRE}]

create_waiver -quiet -type DRC -id {REQP-2057} -user "mrmac" -desc "REQP-2057 is waived as the MBUFG_GT CLR and CLRBLEAF pins are connected with the GT Reset IP" -tags "1138767" -objects [get_cells -hier -filter {REF_NAME==MBUFG_GT && NAME=~ */*_exdes_support*/*gt_wrapper*/*}]

create_waiver -quiet -type CDC -id {CDC-11} -user "mrmac" -desc "This is a level signal and safe to ignore " -tags "1101959"\
-from [get_pins -of [get_cells -hier -filter {name =~ *_cips_wrapper/*_cips_i/proc_sys_reset_0/U0/ACTIVE_LOW_PR_OUT_DFF[0].FDRE_PER_N}]  -filter { name =~ *C } ]\
-to [get_pins -hier -filter { name =~ *_exdes/*_pkt_gen_mon_*/*_pkt_gen_*/DUPLEX_PKT_SIZE_*_reg*/CLR}]

create_waiver -quiet -type CDC -id {CDC-7} -user "mrmac" -desc "This is a level signal and safe to ignore " -tags "1101959"\
-from [get_pins -of [get_cells -hier -filter {name =~ *_cips_wrapper/*_cips_i/proc_sys_reset_0/U0/ACTIVE_LOW_PR_OUT_DFF[0].FDRE_PER_N}]  -filter { name =~ *C } ]\
-to [get_pins  -hier -filter { name =~ *_exdes/*_pkt_gen_mon_*/*_pkt_gen_*/*_reg*/CLR}]

create_waiver -quiet -type CDC -id {CDC-7} -user "mrmac" -desc "This is a level signal and safe to ignore " -tags "1101959"\
-from [get_pins -of [get_cells -hier -filter {name =~ *_cips_wrapper/*_cips_i/proc_sys_reset_0/U0/ACTIVE_LOW_PR_OUT_DFF[0].FDRE_PER_N}]  -filter { name =~ *C } ]\
-to [get_pins  -hier -filter { name =~ *_exdes/*_pkt_gen_mon_*/*_pkt_gen_*/*_reg*/PRE}]
