#!/bin/bash -e

# Copyright (c) 2023 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-License-Identifier: MIT

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]
then
    echo "ERROR: Sourcing script is not supported - exiting"
else

    # Where the tools needed are to be found
    COVERITY_VERSION="2022.3.0"
    export PATH=/tools/batonroot/coverity/${COVERITY_VERSION}/bin/:$PATH

    Usage()
    {
        echo "Usage: `basename $0` [-h] [-a <level>] [-c <compiler>] -d <directory> -b <build command>"
        echo
        echo "-h    Display usage instructions and exit"
        echo "-a    Analysis agressiveness level <low | medium | high> (default is low)"
        echo "-c    Compiler e.g. gcc (default is armr5-none-eabi-gcc)"
        echo "-d    Analysis output directory (default is ./coverity)"
        echo "-b    Build command to invoke e.g. \"make firmware_libs\""
        echo
        echo "NOTE - switch -b is required!"
        echo "NOTE - If the build command has multiple words, use quotes around the whole command"
        exit 1;
    }

    AGGRESSIVENESS="low"
    DIRECTORY="coverity"
    BUILD_CMD=
    COMPILER="armr5-none-eabi-gcc"

    while getopts ":a:c:b:d:h" opt
    do
        case "${opt}" in
            h)
                Usage >&2
                ;;
            a)
                AGGRESSIVENESS=$OPTARG
                ;;
            b)
                BUILD_CMD=$OPTARG
                ;;
            c)
                COMPILER=$OPTARG
                ;;
            d)
                DIRECTORY=$OPTARG
                ;;
            \?)
                echo "Invalid option: -$OPTARG" >&2
                exit 1
                ;;
            :)
                echo "Option -$OPTARG requires an argument." >&2
                exit 1
                ;;
            *)
                Usage >&2
                exit 1
                ;;
        esac
    done

    # Validate options
    if [[ -z $BUILD_CMD ]]
    then
        echo "The -b option is required"
        exit 1
    fi

    case "$AGGRESSIVENESS" in
        "low") ;;
        "medium") ;;
        "high") ;;
        *)
            echo "Unrecognised aggressiveness level \"$AGGRESSIVENESS\""
            Usage >&2
            ;;
    esac

    # Execute build
    CONFIG=$DIRECTORY/config.xml
    cov-configure --config $CONFIG --compiler $COMPILER --comptype gcc --template
    cov-build --config $CONFIG --dir $DIRECTORY $BUILD_CMD
    cov-analyze --dir $DIRECTORY --all
    # Filtering nanopb generated files to save disk space
    cov-format-errors --exclude-files "\.pb.*" --dir $DIRECTORY --html-output $DIRECTORY/html
    # Removing large log file - if we reach here, we managed to generate a report so the log isn't much value
    rm $DIRECTORY/build-log.txt
fi

