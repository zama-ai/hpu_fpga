# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.

report_timing_summary -rpx route_pre_timing_summary.rpx -max_paths 1000 -file route_pre_timing_summary.rpt

set_clock_uncertainty -setup 0.2 [get_clocks *]
phys_opt_design -directive AggressiveExplore
phys_opt_design -directive AggressiveExplore
set_clock_uncertainty -setup 0 [get_clocks *]

report_timing_summary -rpx route_pre_timing_summary.rpx -max_paths 1000 -file physopt2_timing_summary.rpt

