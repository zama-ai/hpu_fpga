set SITE   [lindex $::argv 0]
set VERSAL [file normalize [file dirname [info script]]/..]
set OUTPUT [lindex $::argv 1]
set IMPL   $OUTPUT/top_hpu/prj.runs/impl_1

cd $IMPL

open_checkpoint top_hpu_routed_error.dcp
set_property IP_REPO_PATHS $VERSAL/iprepo/ [current_project] 

route_design -unroute -nets [get_nets -of_objects [get_sites $SITE]]
update_clock_routing
route_design

source $VERSAL/constraints/hooks/hook_route.post.tcl
report_timing_summary -rpx route_timing_summary.rpx -max_paths 1000 \
                      -file route_timing_summary.rpt

write_checkpoint -force top_hpu_routed.dcp
source $VERSAL/constraints/hooks/hook_write_device_image.pre.tcl
write_device_image -force $OUTPUT/top_hpu.pdi
