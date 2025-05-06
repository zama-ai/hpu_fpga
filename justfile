# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.

relicense:
  hw/scripts/relicense/relicense.py \
    -t 'hw/scripts/relicense/templates' \
    -d 'hw' \
       'fw' \
       'sw' \
       'versal' \
    --owner ZAMA \
    justfile \
    versal/justfile

