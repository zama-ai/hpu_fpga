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
source ${BD_SCRIPTS_DIR}/bd_mrmac_wrapper.tcl
source ${BD_SCRIPTS_DIR}/bd_main.tcl

################################################################
# Check if script is running in correct Vivado version.
################################################################
check_version 2025.1

################################################################
# Global variables
################################################################
set ::ntt_psi $ntt_psi
namespace eval _nsp_hpu {
    #========================
    # Addresses
    #========================
    # Do not modify : HBM
    variable HBM_ADD_OFS 0x0000004000000000
    variable HBM_PC_RANGE 0x40000000
    variable HBM_PORT_RANGE [expr $HBM_PC_RANGE/2]

    #========================
    # Clock frequencies (MHZ)
    #========================
    # Do not modify : PMC_CRP_PL<i>_REF_CTRL_FREQ
    variable LP_AXI_FREQ 100.000
    variable FREE_RUN_FREQ 33.3333333
    variable PCIE_EXT_CFG_FREQ 250.000

    # HBM
    variable HBM_REF_FREQ 100.000
    variable HBM_FREQ 1600.000

    # DDR
    variable SYS_FREQ 200.000
    variable PCIE_REF_FREQ 100.000

    # User
    set freq 400.000
    variable USER_0_FREQ $freq
    variable USER_1_FREQ 100.000

    # MHDMA
    variable MHDMA_FREERUN_FREQ 100
    # APB3 freerunning mandatory clock for MRMAC
    variable MRMAC_APB3_FREQ 200
    # MHDMA RTL module frequency is the same as GT's today.
    # We are in 4x25GE Narrow mode 64bits, frequency is fixed by this configuration
    variable MHDMA_FREQ 390.625

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

    # MHDMA configuration
    # 64 depends on the line configurations, beware
    # current configuration is: 4x Independent 64b Non-Segmented
    set AXIS_DATA_MHDMA_W 64
    set AXIS_DATA_MHDMA_BYTES [expr $AXIS_DATA_MHDMA_W / 8]

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
    variable PCIE_HBM_DMA_RD_BW 256
    variable PCIE_HBM_DMA_WR_BW 256
    variable PCIE_HBM_DMA_RD_BURST_AVG 256
    variable PCIE_HBM_DMA_WR_BURST_AVG 256
    variable PCIE_HBM_DMA_DATA_W 128

    # PCIE <-> AXIL
    variable PCIE_AXIL_RD_BW 100
    variable PCIE_AXIL_WR_BW 100
    variable PCIE_AXIL_RD_BURST_AVG 1
    variable PCIE_AXIL_WR_BURST_AVG 1

    # PCIE <-> DDR DMA
    variable PCIE_DDR_DMA_RD_BW 100
    variable PCIE_DDR_DMA_WR_BW 100
    variable PCIE_DDR_DMA_RD_BURST_AVG 256
    variable PCIE_DDR_DMA_WR_BURST_AVG 256

    # PMC <-> DDR
    variable PMC_DDR_RD_BW 800
    variable PMC_DDR_WR_BW 800
    variable PMC_DDR_RD_BURST_AVG 256
    variable PMC_DDR_WR_BURST_AVG 256

    # MHDMA <-> HBM
    variable MHDMA_HBM_RD_BW 100
    variable MHDMA_HBM_WR_BW 100
    variable MHDMA_HBM_RD_BURST_AVG 256
    variable MHDMA_HBM_WR_BURST_AVG 256
    variable MHDMA_HBM_BURST_MAX 256
    variable MHDMA_HBM_DATA_W 256

    # Key <-> HBM
    # WARNING:
    # The current BW requirements assume a 400MHz clock, the
    # APPLICATION_NAME_MSG2_CARRY2_PFAIL128_132B_TUNIFORM_144A47 parameter set and 16 NMUs for KSK
    # and BSK. If any of those assumptions change this needs to be revised.
    #
    # NOTE: The BSK needs a minimum of 5000Mbps. The NOC bandwidth across all SLRs is roughly half
    # of the normal physical lane bandwidth because of a limit in the number of outstanding
    # transactions in the NMU. So, we would only get roughly 5960Mbps per NMU, which is good enough.
    # However, the HBM access pattern is now adapted to having two NMUs connected directly to a single
    # pseudo-channel, so to avoid more "creative" solutions from the NOC router, we're forcing
    # exactly two NMUs to use the same NOC lane by setting them to the NOC lane bandwidth divided by
    # two.
    variable HPU_BSK_HBM_RD_BW 6000
    variable HPU_BSK_HBM_WR_BW 0
    variable HPU_BSK_HBM_RD_BURST_AVG 128
    variable HPU_BSK_HBM_WR_BURST_AVG 128
    variable HPU_BSK_HBM_BURST_MAX 128
    variable HPU_BSK_HBM_DATA_W 256

    # The KSK needs a minimum of 4000Mbps. But, similarly to the BSK, the HBM access pattern is
    # important. To avoid the NOC router from getting creative, we're asking for the maximum
    # bandwidth to force the router to use separate lanes for each connection.
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
    variable HPU_TRC_HBM_DATA_W 128

    #========================
    # HPU NOC ports
    #========================
    # NOC PORT NB
    variable KSK_AXI_NB 16
    variable BSK_AXI_NB 16
    variable CT_AXI_NB 2
    variable GLWE_AXI_NB 1
    variable TRC_AXI_NB 1
    variable MHDMA_PC_AXI_NB 2
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
    variable MHDMA_NOC_PINS_L [list]

    # HBM port mapping
    variable KSK_HBM_PORTS_L [list]
    variable BSK_HBM_PORTS_L [list]
    variable TRC_HBM_PORTS_L [list]
    variable CT_HBM_PORTS_L [list]
    variable GLWE_HBM_PORTS_L [list]
    variable MHDMA_HBM_PORTS_L [list]

    # /!\ do not touch
    # - one is for communication to gcq, uuid and reset
    # - other one is for the tandem loopback in order to reprogram FPGA
    variable AXI_PCIE_NB 2

    # Regfile
    variable LPD_AXI_NB 1
    variable REGIF_NB 2

    # MHDMA
    variable MHDMA_AXI_NB 2

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
