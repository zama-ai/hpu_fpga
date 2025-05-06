#! /usr/bin/bash
# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
# This script generate the coverage reports (functional and code)
# for the post run phase.
#
# Takes as input the coverage databases, and the testbench name.
# ----------------------------------------------------------------------------------------------
# Parse input
# ==============================================================================================

work_dir=$1
testbench_name=$2
shift
shift

# functional coverage reports
echo "==========================================================="
echo "Functional coverage report"
echo "==========================================================="
echo "xcrg -dir ${work_dir}/xsim.covdb -report_format html -log ${work_dir}/xcrg_fcov.log -report_dir ${work_dir}/xcrg_fcov_report"
xcrg -dir ${work_dir}/xsim.covdb -report_format html -log ${work_dir}/xcrg_fcov.log -report_dir ${work_dir}/xcrg_fcov_report
# code coverage reports
echo "==========================================================="
echo "Code coverage report"
echo "==========================================================="
echo "xcrg -cc_dir $work_dir -cc_db $testbench_name -log ${work_dir}/xcrg_ccov.log -cc_report ${work_dir}/xcrg_ccov_report"
xcrg -cc_dir $work_dir -cc_db $testbench_name -log ${work_dir}/xcrg_ccov.log -cc_report ${work_dir}/xcrg_ccov_report
