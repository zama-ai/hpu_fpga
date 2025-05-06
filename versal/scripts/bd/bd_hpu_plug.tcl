# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
# Block design of V80 Shell
# ==============================================================================================

set PROJECT_DIR $::env(PROJECT_DIR)
set BD_SCRIPTS_DIR ${PROJECT_DIR}/versal/scripts/bd

source ${BD_SCRIPTS_DIR}/bd_lib.tcl
source ${BD_SCRIPTS_DIR}/bd_clock_reset.tcl
source ${BD_SCRIPTS_DIR}/bd_base_logic.tcl
source ${BD_SCRIPTS_DIR}/bd_ddr_noc.tcl
source ${BD_SCRIPTS_DIR}/bd_shell_wrapper.tcl
source ${BD_SCRIPTS_DIR}/bd_noc_wrapper.tcl
source ${BD_SCRIPTS_DIR}/bd_main.tcl

################################################################
# Check if script is running in correct Vivado version.
################################################################
check_version 2024.1

################################################################
# Global variables
################################################################
namespace eval _nsp_hpu {
    #========================
    # Addresses
    #========================
    # Do not modify : HBM
    variable HBM_ADD_OFS 0x0000004000000000
    variable HBM_PC_RANGE 0x40000000

    #========================
    # Clock frequencies (MHZ)
    #========================
    # Do not modify : PMC_CRP_PL<i>_REF_CTRL_FREQ
    variable LP_AXI_FREQ 100.000
    variable FREE_RUN_FREQ 33.3333333
    variable PCIE_EXT_CFG_FREQ 250.000

    # HBM
    variable HBM_REF_FREQ 200.000
    variable HBM_FREQ 1600.000

    # DDR
    variable SYS_FREQ 200.000
    variable PCIE_REF_FREQ 100.000

    # User
    variable USER_0_FREQ 300.000
    variable USER_1_FREQ 100.000

    #========================
    # AXI
    #========================
    variable AXIL_DATA_W 32
    variable AXIL_ADD_W  32

    variable AXIS_DATA_W 32

    variable AXI4_ADD_W 64

    # NOC support multiple of 16bytes
    set AXIS_DATA_BYTES [expr $AXIS_DATA_W / 8]
    set AXIS_NOC_DATA_BYTE [expr (($AXIS_DATA_BYTES + 15) / 16) * 16]
    set AXIS_NOC_DATA_W [expr $AXIS_NOC_DATA_BYTE * 8]

    #========================
    # QOS
    #========================
    # RPU <-> DDR
    variable RPU_DDR_RD_BW 800
    variable RPU_DDR_WR_BW 800
    variable RPU_DDR_RD_BURST_AVG 64
    variable RPU_DDR_WR_BURST_AVG 64

    # RPU <-> AXIL
    variable RPU_AXIL_RD_BW 100
    variable RPU_AXIL_WR_BW 100
    variable RPU_AXIL_RD_BURST_AVG 1
    variable RPU_AXIL_WR_BURST_AVG 1

    # RPU <-> ISC
    variable RPU_ISC_WR_BW 500
    variable RPU_ISC_WR_BURST_AVG 8

    # PCIE <-> HBM DMA
    variable PCIE_HBM_DMA_RD_BW 340
    variable PCIE_HBM_DMA_WR_BW 340
    variable PCIE_HBM_DMA_RD_BURST_AVG 256
    variable PCIE_HBM_DMA_WR_BURST_AVG 256
    variable PCIE_HBM_DMA_DATA_W 128

    # PCIE <-> AXIL
    variable PCIE_AXIL_RD_BW 100
    variable PCIE_AXIL_WR_BW 100
    variable PCIE_AXIL_RD_BURST_AVG 1
    variable PCIE_AXIL_WR_BURST_AVG 1

    # PCIE <-> DDR DMA
    variable PCIE_DDR_DMA_RD_BW 500
    variable PCIE_DDR_DMA_WR_BW 500
    variable PCIE_DDR_DMA_RD_BURST_AVG 256
    variable PCIE_DDR_DMA_WR_BURST_AVG 256

    # PMC <-> DDR
    variable PMC_DDR_RD_BW 800
    variable PMC_DDR_WR_BW 800
    variable PMC_DDR_RD_BURST_AVG 256
    variable PMC_DDR_WR_BURST_AVG 256

    # Key <-> HBM
    variable HPU_BSK_HBM_RD_BW 11000
    variable HPU_BSK_HBM_WR_BW 0
    variable HPU_BSK_HBM_RD_BURST_AVG 128
    variable HPU_BSK_HBM_WR_BURST_AVG 128
    variable HPU_BSK_HBM_BURST_MAX 128
    variable HPU_BSK_HBM_DATA_W 256

    variable HPU_KSK_HBM_RD_BW 12000
    variable HPU_KSK_HBM_WR_BW 0
    variable HPU_KSK_HBM_RD_BURST_AVG 128
    variable HPU_KSK_HBM_WR_BURST_AVG 128
    variable HPU_KSK_HBM_BURST_MAX 128
    variable HPU_KSK_HBM_DATA_W 256

    # CT <-> HBM
    variable HPU_CT_HBM_RD_BW 12000
    variable HPU_CT_HBM_WR_BW 12000
    variable HPU_CT_HBM_RD_BURST_AVG 16
    variable HPU_CT_HBM_WR_BURST_AVG 16
    variable HPU_CT_HBM_BURST_MAX 16
    variable HPU_CT_HBM_DATA_W 256

    # GLWE <-> HBM
    variable HPU_GLWE_HBM_RD_BW 12000
    variable HPU_GLWE_HBM_WR_BW 0
    variable HPU_GLWE_HBM_RD_BURST_AVG 128
    variable HPU_GLWE_HBM_WR_BURST_AVG 128
    variable HPU_GLWE_HBM_BURST_MAX 128
    variable HPU_GLWE_HBM_DATA_W 256

    # TRC <-> HBM
    variable HPU_TRC_HBM_RD_BW 0
    variable HPU_TRC_HBM_WR_BW 12000
    variable HPU_TRC_HBM_RD_BURST_AVG 8
    variable HPU_TRC_HBM_WR_BURST_AVG 8
    variable HPU_TRC_HBM_BURST_MAX 32
    variable HPU_TRC_HBM_DATA_W 32

    #========================
    # HPU NOC ports
    #========================
    # NOC PORT NB
    variable KSK_AXI_NB 16
    variable BSK_AXI_NB 8
    variable CT_AXI_NB 2
    variable GLWE_AXI_NB 1
    variable TRC_AXI_NB 1
    # DOP and ACK
    variable AXIS_NB 2

    #========================
    # IRQ
    #========================
    # IRQ
    variable IRQ_START_ID 1
    variable IRQ_NB 6

    #========================
    # Variables
    #========================
    # NOC pin mapping - will be completed by noc_wrapper
    variable CPM_NOC_PINS_L [list]
    variable KSK_NOC_PINS_L [list]
    variable BSK_NOC_PINS_L [list]
    variable TRC_NOC_PINS_L [list]
    variable CT_NOC_PINS_L [list]
    variable GLWE_NOC_PINS_L [list]

    # HBM port mapping
    variable KSK_HBM_PORTS_L [list]
    variable BSK_HBM_PORTS_L [list]
    variable TRC_HBM_PORTS_L [list]
    variable CT_HBM_PORTS_L [list]
    variable GLWE_HBM_PORTS_L [list]

    # do not touch
    variable AXI_PCIE_NB 1

    # Regfile
    variable LPD_AXI_NB 1
    variable REGIF_NB 2

    # For each regif we have REGIF_CLK_NB
    variable REGIF_CLK_NB 2
}

################################################################
# Create root design
################################################################
create_root_design "" $ntt_psi

set_param noc.enableEnhancedExclusiveRouting true
# Another option to increase bd compiler effort.
#set_param noc.enableCompilerHiEffort true
