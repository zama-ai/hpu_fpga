#!/usr/bin/env python3
# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
# This script runs all the run_simu.sh of the project in parallel.
# Number of thread used depend of the number of available CPUs
#
# Prerequisite : source setup.sh
# ==============================================================================================

import argparse
from collections import namedtuple
import junit_xml as jxml
from threading import Lock
import concurrent.futures
import os
import pandas
from pathlib import Path
import random
import resource
import subprocess

test_t = namedtuple('test', ('name group path seed timeout'))

def add_cli_args(cli_parser):
    # Nreg arguments {{{
    # NB: Currently filtering is done with exact match. This should be enhanced to support regex in
    # the future
    nreg_grp = cli_parser.add_argument_group(title='Non-Regression filtering options')
    nreg_grp.add_argument('-tn', '--test-name', type=str, dest='test_name',
            action='append',
            help='Specify the filtering rules for testname. [%(default)s]\n')
    nreg_grp.add_argument('-tg', '--test-group', type=str, dest='test_group',
            action='append',
            help='Specify the filtering rules for testgroup. [%(default)s]\n')
    nreg_grp.add_argument('-k', '--kind', type=str, dest='kind',
            action='append',
            help='Specify the filtering rules for regression kind. [%(default)s]\n')
    nreg_grp.add_argument('-xtg', '--excl-test-group', type=str, dest='excl_test_group',
            action='append',
            help='Specify the filtering rules for testgroup. [%(default)s]\n')
    nreg_grp.add_argument('-xk', '--excl-kind', type=str, dest='excl_kind',
            action='append',
            help='Specify the filtering rules for regression kind. [%(default)s]\n')

    nreg_grp.add_argument(type=str, dest='csv_file',
                          nargs='?', default='nreg.csv',
            help='Specify the csv file that describes regression content. [%(default)s]\n')
    # }}

    # Execution arguments {{{
    exec_grp = cli_parser.add_argument_group(title='Execution options')
    exec_grp.add_argument('-mc', '--max-cpus', type=int, dest='max_cpus',
            help='Specify the maximum number of cpus to use. [All cpus]\n', default=None)
    exec_grp.add_argument('-out', '--out-path', type=str, dest='out_path',
                          default='hw/output/ci',
            help='Specify the output path folder. [%(default)s]\n')

    exec_grp.add_argument('-r', '--report-junit', type=str, dest='report_junit',
                          default='nreg_rpt.xml',
            help='Specify the junit report filename. [%(default)s]\n')
    # }}}

def get_list_of_test(args):
    """
    Based on cli arguments, return filtered list of testcase to run.
    Filtering is based on pandas frame (a bit overkill for such a task), the outputs is also in a
    pandas frame

    TODO: Based filering on regex instead of exact match
    """
    nreg_list = pandas.read_csv(args.csv_file, comment='#', skip_blank_lines=True)

    # Apply filtering when specified
    if args.kind and not("all" in args.kind):
        nreg_list = nreg_list[nreg_list["Kind"].isin(args.kind)]
    if args.test_group and not("all" in args.test_group):
        nreg_list = nreg_list[nreg_list["Group"].isin(args.test_group)]
    if args.test_name and not("all" in args.test_name):
        nreg_list = nreg_list[nreg_list["Name"].isin(args.test_name)]
    if args.excl_kind:
        nreg_list = nreg_list[~nreg_list["Kind"].isin(args.excl_kind)]
    if args.excl_test_group:
        nreg_list = nreg_list[~nreg_list["Group"].isin(args.excl_test_group)]


    # Also remove all !Enabled test
    return nreg_list[nreg_list["Enabled"] == True]

def expand_tests(nreg_list, args):
    """
    Expand the Seed field to convert a Dataframe into a list of test to execute.
    Seed meaning is as follow:
     * Positive value -> run the test with the given seed
     * Negative value -> run the test multilpe time with a random seed
     """
    test_list = []
    for row in nreg_list.iterrows():
        entry = dict(row[1])
        seed = entry['Seed']
        if seed < 0:
            for i in range(int(abs(seed))):
                rseed = random.randrange(0, 1<<64)
                test_list.append(test_t(
                    name = entry["Name"],
                    group = entry["Group"],
                    path = entry["Path"],
                    seed = rseed,
                    timeout = entry["Timeout"],
                    ))
        else:
            test_list.append(test_t(
                name = entry["Name"],
                group = entry["Group"],
                path = entry["Path"],
                seed = rseed,
                timeout = entry["Timeout"],
            ))
    return test_list

def run_test(test, pdir, out_path, args=None):
    """
    Run a single test defined in a test_t namedtuple
    """
    # Construct path to script run_simu.sh and scripts args
    cmd = [Path(pdir) / test.path / 'scripts/run_simu.sh']
    cmd.extend(['--',
                '-s', f'{test.seed} ',
                '-d', f'{out_path} ',
                ]
               )

    # Timeout is expressed in second
    if test.timeout > 0:
        timeout = test.timeout
    else:
        timeout = None

    # Call simu_run.sh and capture output
    try:
        log = subprocess.run(cmd,
                                timeout=timeout,
                                capture_output=True,
                                )
        rcode = log.returncode
        is_timeout = False

    except subprocess.TimeoutExpired as excpt:
        log = excpt
        rcode = 1 # Error
        is_timeout = True

    info = resource.getrusage(resource.RUSAGE_CHILDREN)
    return(test, log, info, rcode, is_timeout)

def as_junit(exec_log):
    """!@brief: Format execution log as xml junit string
         @return junit.Testcase
    """
    (test, log, info, rcode, is_timeout) = exec_log
    junit_tc = jxml.TestCase(
        name= test.name,
        classname=test.group,
        elapsed_sec=info.ru_utime,
        stdout=log.stdout.decode("UTF-8"),
        stderr=log.stderr.decode("UTF-8"),
        # assertions=None,
        # timestamp=None,
        status='SUCCESS' if 0 == rcode else 'FAILED',
        category=test.group,
        # file=None,
        # line=None,
        # log=None,
        # url=None,
        allow_multiple_subelements=True
    )
    # Add custom messages
    if 0 != rcode:
        msg = "TIMEOUT" if is_timeout else "FAILED"
        junit_tc.add_failure_info(message=msg, output=log.stderr.decode("UTF-8"))
    # junit_tc.add_error_info(message=msg, output=out)
    return junit_tc

def add_testcase(junit_testsuite, exec_log):
    # Extract junit testcase
    junit_tc = as_junit(exec_log)
    # Appent to junit TestSuite
    junit_testsuite.test_cases.append(junit_tc)

def create_junit_testsuite(args):
    # Build junit TestSuite
    junit_rpt = jxml.TestSuite(
                  name= args.csv_file,
                  test_cases=[],
                  hostname=None,
                  id=None,
                  package=None,
                  timestamp=None,
                  properties=None,
                  file=None,
                  log=None,
                  url=None,
                  stdout=None,
                  stderr=None)
    return junit_rpt

if __name__ == '__main__':

    # Define users arguments
    cli_parser = argparse.ArgumentParser()
    add_cli_args(cli_parser)
    cli_args = cli_parser.parse_args()
    print(f"User arguments: {cli_args}");


    # Parse csv file and filtered based on user arguments
    nreg_list = get_list_of_test(cli_args)

    # Expand Seed field and start test execution
    nreg_tests = expand_tests(nreg_list, cli_args)
    print("The following test will be run: ")
    for t in nreg_tests:
        print(f'\t {t}')

    # Handle Environnement variables
    # TODO move this elsewhere
    if 'PROJECT_DIR' in os.environ.keys():
        pdir = os.environ['PROJECT_DIR']
    else:
        print("ERROR: PROJECT_DIR variable must be set. Check sourcing of setup.sh")
        raise FileNotFoundError('Shell variable PROJECT_DIR not found')

    if Path(cli_args.out_path).is_absolute():
        out_path = cli_args.out_path
    else:
        out_path = pdir + "/" + cli_args.out_path
    Path(cli_args.out_path).parent.mkdir(parents=True, exist_ok=True)

    Path(cli_args.report_junit).parent.mkdir(parents=True, exist_ok=True)
    junit_ts = create_junit_testsuite(cli_args)
    junit_ts_lock = Lock()
    # Spawn futures on multiple threads and convert them in concrete results
    with concurrent.futures.ThreadPoolExecutor(max_workers=cli_args.max_cpus) as executor:
        exec_fut = {executor.submit(run_test, test, pdir, out_path, cli_args): test for test in nreg_tests}
        for fut in concurrent.futures.as_completed(exec_fut):
            try:
                test_result = fut.result()
                print('INFO: test {} is done'.format(test_result[0].name))
                with junit_ts_lock:
                    add_testcase(junit_ts, test_result)
                    with open(cli_args.report_junit, 'w') as rf:
                        junit_ts.to_file(rf, [junit_ts])
            except Exception as exc:
                print('ERROR: test {} generated an exception: {}'.format(fut, exc))

