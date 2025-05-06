#!/bin/bash

# Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-License-Identifier: MIT

################################################################################
#                                                                              #
# E.g. Build amc bsp:                                                          #
# ./build_bsp.sh -xsa <file path>                                              #
#                       -os freertos10_xilinx                                  #
#                                                                              #
#                                                                              #
# This will create a bsp (amc_bsp) in the top level directory                  #
#                                                                              #
#                                                                              #
#                                                                              #
################################################################################

################################################################################
###                                 Variables                                ###
################################################################################

ARCH_DIR=archive
### store xsa path ###
xsa=0
### store os param ###
os=0
### store FREERTOS_DEBUG param ###
FREERTOS_DEBUG=0
### FreeRTOS number of ticks per second ###
TICK_RATE_HZ=10000

### Heap size ###
HEAP_SIZE=131072

################################################################################
###                                 Functions                                ###
################################################################################

################################################################################
#
# This function will display syntax diagram, with description of each option
#
################################################################################
function help() {
    echo
    echo
    echo "Usage: ./create_bsp.sh [options]"
    echo "./create_bsp.sh will generate a BSP based on specified xsa and os"
    echo "All below options must be specified!"
    echo
    echo "Options:"
    echo "-xsa       [file path]    Specify .xsa file path"
    echo "-os        [name]         Specify target os (eg standalone)"
    echo "-clean                    Remove all vitis source directories"
    echo "-help                     Print this help"
    echo
    echo
}
################################################################################

################################################################################
#
# This function will remove all vitis source directories
#
################################################################################
function clean() {
    echo "Removing all vitis source files"
    rm -r .Xil
    rm -r .metadata
    rm -r .analytics
    rm -r IDE.log
}

################################################################################
#
# This function sets additinal debug parameters in the FreeRTOSConfig.h file
#
################################################################################
function set_freertos_config() {

    FREERTOS_CONFIG_DIR=$(find ./amc_bsp/psv_cortexr5_0/freertos10_xilinx_domain/bsp/psv_cortexr5_0/libsrc/ -type d -name "freertos10_xilinx_v*")

    if [ ! -d "${FREERTOS_CONFIG_DIR[0]}" ]; then
        echo "Error: FreeRTOS Config not found!"
        exit 1
    fi

    FREERTOS_CONFIG_FILE="$FREERTOS_CONFIG_DIR/src/FreeRTOSConfig.h"
    # Use awk to process and replace/add configurations
    awk '
    BEGIN {
        configs["configGENERATE_RUN_TIME_STATS"];
        configs["configUSE_STATS_FORMATTING_FUNCTIONS"];
        configs["configUSE_TRACE_FACILITY"];
    }
    {
        for (config in configs) {
            if ($0 ~ config) {
                sub(config ".*", config " 1");
                found[config]++;
            }
        }
        # Replacement for the sed commands
        if ($0 ~ "portCONFIGURE_TIMER_FOR_RUN_TIME_STATS()") {
            sub("portCONFIGURE_TIMER_FOR_RUN_TIME_STATS().*", "portCONFIGURE_TIMER_FOR_RUN_TIME_STATS() vConfigureTimerForRunTimeStats()");
        }
        if ($0 ~ "portGET_RUN_TIME_COUNTER_VALUE()") {
            sub("portGET_RUN_TIME_COUNTER_VALUE().*", "portGET_RUN_TIME_COUNTER_VALUE() vGetRunTimeCounterValue()");
        }
        print $0;
    }
    END {
        for (config in configs) {
            if (!found[config]) {
                print "#define " config " 1";
            }
        }
    }' $FREERTOS_CONFIG_FILE > $FREERTOS_CONFIG_FILE.tmp
    mv $FREERTOS_CONFIG_FILE.tmp $FREERTOS_CONFIG_FILE

    # Re-run the makefile to regenerate libraries with new config
    make -C ./amc_bsp/psv_cortexr5_0/freertos10_xilinx_domain/bsp/ clean all
}

################################################################################
#
# This function sets configTICK_RATE_HZ in the FreeRTOSConfig.h file
#
################################################################################
function set_config_tick_rate() {

    FREERTOS_CONFIG_DIR=$(find ./amc_bsp/psv_cortexr5_0/freertos10_xilinx_domain/bsp/psv_cortexr5_0/libsrc/ -type d -name "freertos10_xilinx_v*")

    if [ ! -d "${FREERTOS_CONFIG_DIR[0]}" ]; then
        echo "Error: FreeRTOS Config not found!"
        exit 1
    fi

    FREERTOS_CONFIG_FILE="$FREERTOS_CONFIG_DIR/src/FreeRTOSConfig.h"

    stringreplacement="#define configTICK_RATE_HZ ("
    stringreplacement+=$TICK_RATE_HZ
    stringreplacement+=")"
    echo "Replacing configTICK_RATE_HZ value in FreeRTOSConfig.h"
    sed -i "s/#define configTICK_RATE_HZ (100)/$stringreplacement/g" $FREERTOS_CONFIG_FILE

    # Re-run the makefile to regenerate libraries with new config
    make -C ./amc_bsp/psv_cortexr5_0/freertos10_xilinx_domain/bsp/ clean all
}

################################################################################
#
# This function sets configSUPPORT_STATIC_ALLOCATION in the FreeRTOSConfig.h file
#
################################################################################
function set_config_static_allocation() {

    FREERTOS_CONFIG_DIR=$(find ./amc_bsp/psv_cortexr5_0/freertos10_xilinx_domain/bsp/psv_cortexr5_0/libsrc/ -type d -name "freertos10_xilinx_v*")

    if [ ! -d "${FREERTOS_CONFIG_DIR[0]}" ]; then
        echo "Error: FreeRTOS Config not found!"
        exit 1
    fi

    FREERTOS_CONFIG_FILE="$FREERTOS_CONFIG_DIR/src/FreeRTOSConfig.h"

    stringreplacement="#define configSUPPORT_STATIC_ALLOCATION 1"

    echo "Replacing configSUPPORT_STATIC_ALLOCATION value in FreeRTOSConfig.h"
    sed -i "s/#define configSUPPORT_STATIC_ALLOCATION 0/$stringreplacement/g" $FREERTOS_CONFIG_FILE

    # Re-run the makefile to regenerate libraries with new config
    make -C ./amc_bsp/psv_cortexr5_0/freertos10_xilinx_domain/bsp/ clean all
}

################################################################################
#
# This function sets config configTOTAL_HEAP_SIZE in the FreeRTOSConfig.h file
#
################################################################################
function set_config_heap_size() {

    FREERTOS_CONFIG_DIR=$(find ./amc_bsp/psv_cortexr5_0/freertos10_xilinx_domain/bsp/psv_cortexr5_0/libsrc/ -type d -name "freertos10_xilinx_v*")

    if [ ! -d "${FREERTOS_CONFIG_DIR[0]}" ]; then
        echo "Error: FreeRTOS Config not found!"
        exit 1
    fi

    FREERTOS_CONFIG_FILE="$FREERTOS_CONFIG_DIR/src/FreeRTOSConfig.h"

    stringreplacement="#define configTOTAL_HEAP_SIZE ( ( size_t ) ( "
    stringreplacement+=$HEAP_SIZE
    stringreplacement+=" ) )"
    echo "Replacing configTOTAL_HEAP_SIZE value in FreeRTOSConfig.h"
    sed -i "s/#define configTOTAL_HEAP_SIZE ( ( size_t ) ( 65536 ) )/$stringreplacement/g" $FREERTOS_CONFIG_FILE

    # Re-run the makefile to regenerate libraries with new config
    make -C ./amc_bsp/psv_cortexr5_0/freertos10_xilinx_domain/bsp/ clean all
}

################################################################################

################################################################################
###                           Script Starting Point                          ###
################################################################################

### handle options ###

### while-done structure defines a loop ###
### that executes once for each passed option ###
while [ $# -gt 0 ]; do
    ### case-esac structure evaluates each option ###
    case "$1" in
    -help)
        ### display Help ###
	    help
	    exit;;
    -clean)
        ### clean vitis source directories ###
	    clean
	    exit;;
	-xsa)
	    shift  ### shift to next passed variable (-xsa *) ###
	    xsa=$1 ### store option into xsa variable ###

        ### handle empty string ###
	    if [ "x$1" = x ]
            then
                    echo "Error: Invalid option"
                    help
                    exit
            else
                ### print out xsa path ###
                echo "xsa path set==>$xsa"
            fi
	    ;;

	-os)
	    shift
	    os=$1

	    if [ "x$1" = x  ]
            then
		    echo "Error: Invaild option"
	    	    help
		    exit
	    else
		echo "target os set ==> $os"
	    fi
	    ;;
    -freertos_debug)
	    FREERTOS_DEBUG=1
	    ;;
        *|--*|-*)
            ### Invalid option ###
            echo "Error: Invalid option"
	        help ### display help ###
            exit;;
    esac
    shift ### shift to next passed option ###
done

### start initial build ###

### handle xsa file path ###
if [ $xsa == 0 ] ### if xsa not specified ###
    then
        echo "Error: Please specify .xsa file path"
        help
        exit
fi

### handle os ###
if [ $os == 0 ] ### if os not specified ###
    then
	echo "Error: Please specify target os"
	help
	exit
fi

echo "=== Creating BSP in vitis ==="
cd ..
xsct ./scripts/create_bsp.tcl $xsa $os
set_config_tick_rate
set_config_static_allocation
set_config_heap_size
if [ "$FREERTOS_DEBUG" == 1 ]; then
    set_freertos_config
fi
