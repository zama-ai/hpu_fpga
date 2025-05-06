#!/bin/bash

################################################################################
#                                                                              #
# Copyright (C) 2023, Advanced Micro Devices, Inc. All rights reserved.        #
# SPDX-License-Identifier: X11                                                 #
#                                                                              #
################################################################################

################################################################################
#                                                                              #
# E.g. To get the version info of a module named "amc":                        #
#           ./getVersion amc                                                   #
#                                                                              #
# This must be run from the top level of the repo for amc                      #
# & from /src/device_drivers/gcq_driver for gcq                                #
#                                                                              #
# This cats the output file "<ID>_version.h"                                   #
# amc_version.h in the src/common/include directory                            #
# gcq_version.h in the src/device_drivers/gcq_driver/src directory             #
#                                                                              #
# This file will not be tracked by git                                         #
#                                                                              #
################################################################################

################################################################################
###                                 Variables                                ###
################################################################################

if [ "$#" -eq 1 ]; then
    MODULE_NAME=$1
else
    MODULE_NAME=${PWD##*/}
fi

VERSION_AMC_FILE="./src/common/include/amc_version.h"
AMC_STR="amc"
VERSION_GCQ_FILE="./src/gcq_version.h"
GCQ_STR="gcq"

################################################################################
###                                 Functions                                ###
################################################################################

################################################################################
#
# This function creates the version.h file
#
################################################################################
function catVersionHeaderFile {

    if [ "$MODULE_NAME" = "$AMC_STR" ]; then
        cat $VERSION_AMC_FILE
        elif [ "$MODULE_NAME" = "$GCQ_STR" ]; then
            cat $VERSION_GCQ_FILE
        else
            echo "No version file found..."
    fi
}
################################################################################

function getVersionMain {
    echo -e "\r\nRunning $0"
    catVersionHeaderFile
    echo -e "Done\r\n"
}
################################################################################

################################################################################
###                           Script Starting Point                          ###
################################################################################

getVersionMain

exit 0
