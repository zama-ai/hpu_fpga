#!/bin/bash

# Copyright (c) 2024 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-License-Identifier: MIT

################################################################################
###                                 Variables                                ###
################################################################################

### store xsa path ###
XSA=0
### store os param ###
OS=0
### store profile param ###
PROFILE=0
### AMC build only
AMC_ONLY=0
### stores additional params for CMake ###
CMAKE_PARAMS=""
### stores freertos debug params ###
FREERTOS_DEBUG=0
### stores static analysis debug flag ###
STATIC_ANALYSIS_DEBUG=0

ROOT_DIR=$(pwd)
BSP_DIR=$ROOT_DIR/amc_bsp
BUILD_DIR=$ROOT_DIR/build
SCRIPTS_DIR=$ROOT_DIR/scripts
OUTPUT_BIN="amc.elf"

BUILD_LOG=$BUILD_DIR/build.log

SCRIPT_START_TIME=$SECONDS

chmod +x $SCRIPTS_DIR/*

### Array of required git filenames ###
GIT_FILES=(".uncrustify_rtos.cfg" "function_header.txt" "pre-commit" "commit-msg")

################################################################################
###                                 Functions                                ###
################################################################################

function clean() {
    SECTION_START=$SECONDS
    echo "=== Removing BSP, build, and CMake files ==="
    rm -r $ROOT_DIR/.Xil/
    rm -r $ROOT_DIR/.metadata/
    rm -r $BSP_DIR/
    rm -r $ROOT_DIR/.analytics
    rm -r $ROOT_DIR/IDE.log

    rm -r $BUILD_DIR
    echo "*** Cleaning took $((SECONDS - $SECTION_START)) S ***"
}

function clean_static_analysis() {
    SECTION_START=$SECONDS
    echo "=== Static analysis clean ==="
    cd $BUILD_DIR
    make clean
    rm -r coverity/

    echo "*** Cleaning took $((SECONDS - $SECTION_START)) S ***"
}

function print_help() {
    echo "=================================== AMC Build script ===================================="
    echo
    echo "-clean                  : remove all build files"
    echo "-clean_amc              : remove all AMC application build files (BSP untouched)"
    echo "-amc                    : only builds the AMC application (BSP untouched)"
    echo "-profile <profile_name> : set the profile to build AMC for (v70/v80/Linux, etc)"
    echo "-os <os_name>           : set the OS (freertos10_xilinx, standalone, Linux, etc)"
    echo "-xsa <path_to_xsa>      : XSA to generate BSP from"
    echo "-freertos_debug         : sets FreeRTOSConfig.h stat debug flags"
    echo "-analysis               : triggers a static analysis check on AMC files"
    echo
    echo "Any additional arguments are passed directly into CMAKE"
    echo
    echo "E.g.: To build from scratch:"
    echo " ./scripts/build.sh -xsa /direct/path/to/example.xsa -os freertos10_xilinx -profile v80"
    echo
    echo "E.g.: To build the application only:"
    echo " ./scripts/build.sh -os freertos10_xilinx -profile v80 -amc"
    echo
    echo "E.g.: To build application for Linux (profile will default to Linux):"
    echo " ./scripts/build.sh -os Linux -amc"
    echo
    echo "========================================================================================="
}

function check_workspace_setup() {
    for file in "${GIT_FILES[@]}"
    do
        if [ -f ".git/hooks/$file" ]; then
            echo "Checking ==> $file"
	    else
            echo "Checking ==> $file"
            echo "Error: file does not exist."
            echo "Please run ./scripts/setupWorkspace.sh"
            exit 1
        fi
    done

    echo "Checking ==> uncrustify is installed"
    check=$(command -v uncrustify)

    if [ $? -ne 0 ]; then
        echo "Error: uncrustify is not installed."
        echo "Please run ./scripts/setupWorkspace.sh"
        exit 1
    fi
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
        print_help
        exit 0;;
    -clean)
        ### clean BSP, build and CMake files ###
            clean
            exit 0;;
    -clean_amc)
        ### clean AMC application files ###
        if [ -d "$BUILD_DIR" ]; then
            echo "=== Removing $BUILD_DIR ==="
            rm -r $BUILD_DIR
        fi
        exit 0;;
    -amc)
        ### Build AMC application only, no BSP changes
        echo "Building $OUTPUT_BIN only"
        AMC_ONLY=1
        ;;
        -xsa)
            shift  ### shift to next passed variable (-xsa *) ###
            XSA=$1 ### store option into xsa variable ###

        ### handle empty string ###
            if [ "$1" = "" ]; then
            echo "Error: Invalid xsa"
            exit 1
        fi
            ;;
    -profile)
        shift
        PROFILE=$1

            if [ "$1" = "" ]; then
            echo "Error: Invalid profile"
            exit 1
        fi
            ;;
        -os)
            shift
            OS=$1

            if [ "$1" = "" ]; then
            echo "Error: Invalid OS"
            exit 1
        fi
            ;;
    -freertos_debug)
        FREERTOS_DEBUG=1
        CMAKE_PARAMS+="-DFREERTOS_DEBUG=true "
            ;;
    -analysis)
        STATIC_ANALYSIS_DEBUG=1
        ;;
    *)
        ### Stores any additional args to pass to CMake ###
        CMAKE_PARAMS+="$1 "
        ;;
    esac
    shift ### shift to next passed option ###
done

# Check setupWorkspace.sh script has run, and that uncrustify is installed.
# check_workspace_setup

# Remake build direcory
if [ -d "$BUILD_DIR" ]; then
    rm -r $BUILD_DIR/
fi
mkdir $BUILD_DIR

### start initial build ###
echo "$(date)" |& tee $BUILD_LOG

### handle os ###
if [ $OS == 0 ]; then
    ### if os not specified ###
    echo "Error: Please specify target OS"
    exit 1
else
    ### print out os path ###
    echo "OS path set ==> $OS" |& tee -a $BUILD_LOG
fi

### handle os set to Linux ###
if [ "$OS" == "Linux" ]; then
    ### default profile to Linux ###
    PROFILE="Linux"
    echo "overwriting profile ==> $PROFILE" |& tee -a $BUILD_LOG
fi

### handle profile ###
if [ $PROFILE == 0 ]; then
    ### if profile not specified ###
    echo "Error: Please specify profile"
    exit 1
else
    ### print out profile name ###
    echo "profile set ==> $PROFILE" |& tee -a $BUILD_LOG
fi

### handle xsa file path ###
if [ "$OS" == "Linux" ]; then
    ### xsa not required on Linux ###
    echo "Building on Linux - skipping BSP step" |& tee -a $BUILD_LOG
    clean
elif [ "$AMC_ONLY" == 1 ]; then
    ### xsa not required when building the firmware along ###
    echo "Only building $OUTPUT_BIN - skipping BSP step" |& tee -a $BUILD_LOG
else
    if [ $XSA == 0 ]; then
         ### if xsa not specified ###
        echo "Error: Please specify .xsa file path"
        exit 1
    else
        ### print out xsa path ###
        echo ".xsa path set ==> $XSA" |& tee -a $BUILD_LOG

        ### Removes and regenerates BSP ###
        clean
        if [ ! -d $BUILD_DIR ]; then
            mkdir -p $BUILD_DIR;
        fi
        echo "=== Building BSP ===" |& tee -a $BUILD_LOG
        SECTION_START=$SECONDS
        cd $SCRIPTS_DIR
        if [ "$FREERTOS_DEBUG" == 1 ]; then
            ./build_bsp.sh -xsa "$XSA" -os "$OS" -freertos_debug |& tee -a $BUILD_LOG
        else
            ./build_bsp.sh -xsa "$XSA" -os "$OS" |& tee -a $BUILD_LOG

        if [ "${PIPESTATUS[0]}" == 1 ]; then
            echo "Error: Building BSP failed!"
            exit 1
        fi

        cd $ROOT_DIR
        echo "*** Building BSP took $((SECONDS - $SECTION_START)) S ***" |& tee -a $BUILD_LOG
        fi
    fi
fi

if [ ! -d $BUILD_DIR ]; then
  mkdir -p $BUILD_DIR;
fi
cd $BUILD_DIR

# Running CMake
echo "=== Executing CMake build process ===" |& tee -a $BUILD_LOG
SECTION_START=$SECONDS
cmake -DOS="$OS" -DPROFILE="$PROFILE" "$CMAKE_PARAMS" .. |& tee -a $BUILD_LOG
echo "*** CMake took $((SECONDS - $SECTION_START)) S ***" |& tee -a $BUILD_LOG

#Running Make
echo "=== Compiling $OUTPUT_BIN ===" |& tee -a $BUILD_LOG
SECTION_START=$SECONDS
make |& tee -a $BUILD_LOG
echo "*** Compiling took $((SECONDS - $SECTION_START)) S ***" |& tee -a $BUILD_LOG

if  [ "$STATIC_ANALYSIS_DEBUG" == 1 ]; then
    # Static analysis Clean
    SECTION_START=$SECONDS
    clean_static_analysis
    echo "*** Cleaning took $((SECONDS - $SECTION_START)) S ***" |& tee -a $BUILD_LOG

    # Static Analysis
    echo "=== Static Analysis ===" |& tee -a $BUILD_LOG
    SECTION_START=$SECONDS
    if [ $PROFILE = "v80" ] || [ $PROFILE = "v70" ]; then
        $SCRIPTS_DIR/cov_analysis.sh -b make amc
    elif [ $PROFILE = "Linux" ] || [ $OS = "Linux" ]; then
        $SCRIPTS_DIR/cov_analysis.sh -c gcc -b make amc
    else
        ### if unexpected profile for static analysis build ###
        echo "Error: Please specify a valid profile"
    fi
    echo "*** Static analysis took $((SECONDS - $SECTION_START)) S ***" |& tee -a $BUILD_LOG
fi

# Complete
OUTPUT_DIR=$(realpath .)
echo "Done - AMC build in $OUTPUT_DIR" |& tee -a $BUILD_LOG
cd $ROOT_DIR
echo "*** Complete build time: $((SECONDS - $SCRIPT_START_TIME)) S ***" |& tee -a $BUILD_LOG
exit 0
