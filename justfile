# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.

#------------------------------------------------
### Default command
#------------------------------------------------
# List recipes
default:
  just --list


#------------------------------------------------
### Handle license header
#------------------------------------------------
# Reapply license header
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

#------------------------------------------------
### Check typos
#------------------------------------------------
# Install typos-cli with rust cargo
install_typos_checker:
	@typos --version > /dev/null 2>&1 || \
	cargo install typos-cli || \
	( echo "Unable to install typos-cli, unknown error." && exit 1 )

# Check typos
check_typos: install_typos_checker
  typos --sort |tee typos_error.out
