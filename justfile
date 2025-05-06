# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.

relicense:
  hw/script/relicense/relicense.py \
    -t 'hw/script/relicense/templates' \
    -d 'hw' \
       'fw' \
       'sw' \
       'versal' \
    --owner ZAMA \
    justfile \
    versal/justfile

