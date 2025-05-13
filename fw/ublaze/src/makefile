###
# Embedded software development
# -------------------------------------------------------------------------------------------------
#
# This makefile generates needed outputs for Micorblaze compilation
#
# Usage :
#		>  make target={TargetName} srcf={FileName}
#
###################################################################################################
SHELL = /bin/sh

# Directory definition
compiled = ${PROJECT_DIR}/hw/output/micro_code
srcdir = ${PROJECT_DIR}/fw/ublaze/src
shelldir = ${PROJECT_DIR}/fw/gen/${MICROBLAZE_CONF}/ip_${MICROBLAZE_CONF}/shell
libdir = ${PROJECT_DIR}/fw/gen//${MICROBLAZE_CONF}/ip_${MICROBLAZE_CONF}/bsp/lib

# Layout
bold := $(shell tput bold)
sgr0 := $(shell tput sgr0)

# ----------------------------------------------------------------------------------------------- #
# > Targets
#
# TargetCompile builds the c code and generates output products '.o' .'d'
#
# TargetLink links compiled code with the address map '.ld' and generates ".elf"
# 
# TargetMemory transforms elf into memory file for standalone simulation
# ----------------------------------------------------------------------------------------------- #

TargetMemory: TargetLink
	@echo 'Building memory file'
	@if test -f $(compiled)/ublaze_lmb_bram_0.mem; then echo "Memoryfile already exists : deleting previous ... " && rm $(compiled)/ublaze_lmb_bram_0.mem; fi
	@echo ''
	cd $(compiled); \
		updatemem -data $(srcf).elf -meminfo $(shelldir)/project_microblaze.smi -proc /ublaze_0

TargetLink: TargetCompile
	@echo "linking to target ..."
	@echo ' '
	mb-gcc -Wl,-T -Wl,$(shelldir)/fw_platform.ld -L$(libdir) -mlittle-endian -mxl-barrel-shift -mxl-pattern-compare -mcpu=v11.0 -mno-xl-soft-mul -Wl,--no-relax -Wl,--gc-sections -o "$(compiled)/$(srcf).elf" $(compiled)/$(srcf).o   -Wl,--start-group,-lxil,-lgcc,-lc,--end-group
	@echo ' '

TargetCompile: $(compiled)
	@echo ' '
	@echo "Building target: $(srcf)"
	@echo "Invoking: MicroBlaze gcc linker"
	@echo ' '
	mb-gcc -Wall -O3 -g3 -c -fmessage-length=0 -MT"$(compiled)/$(srcf).o" -I/include -mno-xl-reorder -mlittle-endian -mxl-barrel-shift -mxl-pattern-compare -mcpu=v11.0 -mno-xl-soft-mul -Wl,--no-relax -ffunction-sections -fdata-sections -MMD -MP -MF"$(compiled)/$(srcf).d" -MT"$(compiled)/$(srcf).o" -o "$(compiled)/$(srcf).o" "$(srcdir)/$(srcf).c"
	@echo ' '
	@echo 'Finished building target: $(bold)$(srcf)$(sgr0)'
	@echo ' '

$(compiled):
	@echo "Folder $(compiled) does not exist"
	mkdir -p $@
