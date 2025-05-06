# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
#
# #
# This script calls hw_regmap tool to convert  TOML description into RTL files
# It handles the tool setup and export the files at the right place
# #

set -e 

 ORIG_DIR=$(pwd)
 REGMAP_DIR=${PROJECT_DIR}/sw/regmap
 REGMAP_TOOL=${REGMAP_DIR}/target/release/hw_regmap

 # User options
 MODULE_NAME=tb_hpu_ucore_regif


 # NB: regmap tool must be started from it's own folder to properly found
 #  the associated template files
 cd ${REGMAP_DIR}

 source setup.sh
 cargo build --release

 ${REGMAP_TOOL} \
   --toml-file ${ORIG_DIR}/${MODULE_NAME}.toml \
   --output-path ${ORIG_DIR}/../rtl \
   --basename ${MODULE_NAME}

 cd ${ORIG_DIR}


