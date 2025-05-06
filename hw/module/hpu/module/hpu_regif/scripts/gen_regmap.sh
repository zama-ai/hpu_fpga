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
 REGMAP_OUT=${REGMAP_DIR}/gen
 REGMAP_TOOL=${REGMAP_DIR}/target/release/hw_regmap

 # User options
 MODULE_NAME=hpu_regif_core


 # NB: regmap tool must be started from it's own folder to properly found
 #  the associated template files
 cd ${REGMAP_DIR}

 source setup.sh
 cargo build --release

 # Generate files in tmp gen folder
 ${REGMAP_TOOL} \
   --toml-file ${ORIG_DIR}/${MODULE_NAME}_cfg_1in3.toml \
   --toml-file ${ORIG_DIR}/${MODULE_NAME}_cfg_3in3.toml \
   --toml-file ${ORIG_DIR}/${MODULE_NAME}_prc_1in3.toml \
   --toml-file ${ORIG_DIR}/${MODULE_NAME}_prc_3in3.toml \
   --output-path ${REGMAP_OUT} \
   --basename ${MODULE_NAME}

 # Move rtl in rtl subfolder
 mv ${REGMAP_OUT}/*.sv ${ORIG_DIR}/../rtl
 mv ${REGMAP_OUT}/*_doc.* ${ORIG_DIR}/../docs

 cd ${ORIG_DIR}


