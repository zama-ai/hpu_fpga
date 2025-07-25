# ==============================================================================================
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
# ----------------------------------------------------------------------------------------------
# Contains procedure to generate block designs that handle ethernet connexion.
# Part of it is derived from the example design and adapted to our needs.
#
# We needed an MRMAC MAC + PCS driving GTM for QSFPs.
#
# ==============================================================================================

###############################################################################
# The majority of this code has been generated using example design.
# some parts have been modified to fit our needs and naming convention.
###############################################################################

# Hierarchical cell: mrmac_0_gt_wrapper
proc create_hier_cell_mrmac_0_gt_wrapper { parentCell nameHier } {
  set parentObj [check_parent_hier $parentCell $nameHier]
  if { $parentObj == "" } { return }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj
  set parent_is_root [expr [string match "/" $parentObj] ? 1 : 0]

  # Create cell and set as current instance
  set hier_obj [create_bd_cell -type hier $nameHier]
  current_bd_instance $hier_obj

  ####################################
  # Create pins
  ####################################
  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:gt_tx_interface_rtl:1.0 TX0_GT_IP_Interface
  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:gt_tx_interface_rtl:1.0 TX1_GT_IP_Interface
  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:gt_tx_interface_rtl:1.0 TX2_GT_IP_Interface
  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:gt_tx_interface_rtl:1.0 TX3_GT_IP_Interface
  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:gt_rx_interface_rtl:1.0 RX0_GT_IP_Interface
  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:gt_rx_interface_rtl:1.0 RX1_GT_IP_Interface
  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:gt_rx_interface_rtl:1.0 RX2_GT_IP_Interface
  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:gt_rx_interface_rtl:1.0 RX3_GT_IP_Interface
  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:apb_rtl:1.0 APB3_INTF
  create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:gt_rtl:1.0 GT_Serial
  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 CLK_IN_D

  create_bd_pin -dir I -from 7 -to 0 ch0_txrate
  create_bd_pin -dir I -type gt_usrclk ch0_txusrclk
  create_bd_pin -dir I -from 7 -to 0 ch1_txrate
  create_bd_pin -dir I -type gt_usrclk ch1_txusrclk
  create_bd_pin -dir I -from 7 -to 0 ch2_txrate
  create_bd_pin -dir I -type gt_usrclk ch2_txusrclk
  create_bd_pin -dir I -from 7 -to 0 ch3_txrate
  create_bd_pin -dir I -type gt_usrclk ch3_txusrclk
  create_bd_pin -dir I -from 7 -to 0 ch0_rxrate
  create_bd_pin -dir I -type gt_usrclk ch0_rxusrclk
  create_bd_pin -dir I -from 7 -to 0 ch1_rxrate
  create_bd_pin -dir I -type gt_usrclk ch1_rxusrclk
  create_bd_pin -dir I -from 7 -to 0 ch2_rxrate
  create_bd_pin -dir I -type gt_usrclk ch2_rxusrclk
  create_bd_pin -dir I -from 7 -to 0 ch3_rxrate
  create_bd_pin -dir I -type gt_usrclk ch3_rxusrclk
  create_bd_pin -dir I -from 2 -to 0 ch0_loopback
  create_bd_pin -dir I -from 2 -to 0 ch1_loopback
  create_bd_pin -dir I -from 2 -to 0 ch2_loopback
  create_bd_pin -dir I -from 2 -to 0 ch3_loopback
  create_bd_pin -dir I -type clk apb3clk_quad
  create_bd_pin -dir I -type rst s_axi_aresetn
  create_bd_pin -dir O gtpowergood
  create_bd_pin -dir I -from 3 -to 0 gt_rxp_in_0
  create_bd_pin -dir I -from 3 -to 0 gt_rxn_in_0
  create_bd_pin -dir O -from 3 -to 0 gt_txp_out_0
  create_bd_pin -dir O -from 3 -to 0 gt_txn_out_0
  create_bd_pin -dir I -from 0 -to 0 MBUFG_GT_CLR
  create_bd_pin -dir I -from 0 -to 0 MBUFG_GT_CLRB_LEAF
  create_bd_pin -dir O -from 0 -to 0 -type gt_usrclk ch0_tx_usr_clk
  create_bd_pin -dir O -from 0 -to 0 -type gt_usrclk ch0_tx_usr_clk2
  create_bd_pin -dir I -from 0 -to 0 MBUFG_GT_CLR1
  create_bd_pin -dir I -from 0 -to 0 MBUFG_GT_CLRB_LEAF1
  create_bd_pin -dir O -from 0 -to 0 -type gt_usrclk ch0_rx_usr_clk
  create_bd_pin -dir O -from 0 -to 0 -type gt_usrclk ch0_rx_usr_clk2
  create_bd_pin -dir I -from 0 -to 0 MBUFG_GT_CLR2
  create_bd_pin -dir I -from 0 -to 0 MBUFG_GT_CLRB_LEAF2
  create_bd_pin -dir O -from 0 -to 0 -type gt_usrclk ch1_rx_usr_clk
  create_bd_pin -dir O -from 0 -to 0 -type gt_usrclk ch1_rx_usr_clk2
  create_bd_pin -dir I -from 0 -to 0 MBUFG_GT_CLR3
  create_bd_pin -dir I -from 0 -to 0 MBUFG_GT_CLRB_LEAF3
  create_bd_pin -dir O -from 0 -to 0 -type gt_usrclk ch2_rx_usr_clk
  create_bd_pin -dir O -from 0 -to 0 -type gt_usrclk ch2_rx_usr_clk2
  create_bd_pin -dir I -from 0 -to 0 MBUFG_GT_CLR4
  create_bd_pin -dir I -from 0 -to 0 MBUFG_GT_CLRB_LEAF4
  create_bd_pin -dir O -from 0 -to 0 -type gt_usrclk ch3_rx_usr_clk
  create_bd_pin -dir O -from 0 -to 0 -type gt_usrclk ch3_rx_usr_clk2

  ####################################
  # Create instances
  ####################################

  # Create instance: gt_quad_base, and set properties
  set gt_quad_base [ create_bd_cell -type ip -vlnv xilinx.com:ip:gt_quad_base:1.1 gt_quad_base ]

  set_property -dict [list \
    CONFIG.APB3_CLK_FREQUENCY {200.0} \
    CONFIG.CHANNEL_ORDERING {/mrmac_0_gt_wrapper/gt_quad_base/TX0_GT_IP_Interface mrmac_0_exdes_support_mrmac_0_core_0_0./mrmac_0_core/gtm_tx_serdes_interface_0.0 /mrmac_0_gt_wrapper/gt_quad_base/TX1_GT_IP_Interface\
mrmac_0_exdes_support_mrmac_0_core_0_0./mrmac_0_core/gtm_tx_serdes_interface_1.1 /mrmac_0_gt_wrapper/gt_quad_base/TX2_GT_IP_Interface mrmac_0_exdes_support_mrmac_0_core_0_0./mrmac_0_core/gtm_tx_serdes_interface_2.2\
/mrmac_0_gt_wrapper/gt_quad_base/TX3_GT_IP_Interface mrmac_0_exdes_support_mrmac_0_core_0_0./mrmac_0_core/gtm_tx_serdes_interface_3.3 /mrmac_0_gt_wrapper/gt_quad_base/RX0_GT_IP_Interface mrmac_0_exdes_support_mrmac_0_core_0_0./mrmac_0_core/gtm_rx_serdes_interface_0.0\
/mrmac_0_gt_wrapper/gt_quad_base/RX1_GT_IP_Interface mrmac_0_exdes_support_mrmac_0_core_0_0./mrmac_0_core/gtm_rx_serdes_interface_1.1 /mrmac_0_gt_wrapper/gt_quad_base/RX2_GT_IP_Interface mrmac_0_exdes_support_mrmac_0_core_0_0./mrmac_0_core/gtm_rx_serdes_interface_2.2\
/mrmac_0_gt_wrapper/gt_quad_base/RX3_GT_IP_Interface mrmac_0_exdes_support_mrmac_0_core_0_0./mrmac_0_core/gtm_rx_serdes_interface_3.3} \
    CONFIG.GT_TYPE {GTM} \
    CONFIG.PORTS_INFO_DICT {LANE_SEL_DICT {PROT0 {RX0 RX1 RX2 RX3 TX0 TX1 TX2 TX3}} GT_TYPE GTM REG_CONF_INTF APB3_INTF BOARD_PARAMETER { }} \
    CONFIG.PROT0_ENABLE {true} \
    CONFIG.PROT0_GT_DIRECTION {DUPLEX} \
    CONFIG.PROT0_LR0_SETTINGS {GT_DIRECTION DUPLEX TX_PAM_SEL NRZ TX_HD_EN 0 TX_GRAY_BYP true TX_GRAY_LITTLEENDIAN true TX_PRECODE_BYP true TX_PRECODE_LITTLEENDIAN false TX_LINE_RATE 25.78125 TX_PLL_TYPE\
LCPLL TX_REFCLK_FREQUENCY 322.265625 TX_ACTUAL_REFCLK_FREQUENCY 322.265625000000 TX_FRACN_ENABLED false TX_FRACN_OVRD false TX_FRACN_NUMERATOR 0 TX_REFCLK_SOURCE R0 TX_DATA_ENCODING RAW TX_USER_DATA_WIDTH\
80 TX_INT_DATA_WIDTH 64 TX_BUFFER_MODE 1 TX_BUFFER_BYPASS_MODE Fast_Sync TX_PIPM_ENABLE false TX_OUTCLK_SOURCE TXPROGDIVCLK TXPROGDIV_FREQ_ENABLE true TXPROGDIV_FREQ_SOURCE LCPLL TXPROGDIV_FREQ_VAL 644.531\
TX_DIFF_SWING_EMPH_MODE CUSTOM TX_64B66B_SCRAMBLER false TX_64B66B_ENCODER false TX_64B66B_CRC false TX_RATE_GROUP A TX_LANE_DESKEW_HDMI_ENABLE false TX_BUFFER_RESET_ON_RATE_CHANGE ENABLE PRESET GTM-NRZ_Ethernet_25G\
RX_PAM_SEL NRZ RX_HD_EN 0 RX_GRAY_BYP true RX_GRAY_LITTLEENDIAN true RX_PRECODE_BYP true RX_PRECODE_LITTLEENDIAN false INTERNAL_PRESET GTM-NRZ_Ethernet_25G RX_LINE_RATE 25.78125 RX_PLL_TYPE LCPLL RX_REFCLK_FREQUENCY\
322.265625 RX_ACTUAL_REFCLK_FREQUENCY 322.265625000000 RX_FRACN_ENABLED false RX_FRACN_OVRD false RX_FRACN_NUMERATOR 0 RX_REFCLK_SOURCE R0 RX_DATA_DECODING RAW RX_USER_DATA_WIDTH 80 RX_INT_DATA_WIDTH 64\
RX_BUFFER_MODE 1 RX_OUTCLK_SOURCE RXPROGDIVCLK RXPROGDIV_FREQ_ENABLE true RXPROGDIV_FREQ_SOURCE LCPLL RXPROGDIV_FREQ_VAL 644.531 RXRECCLK_FREQ_ENABLE false RXRECCLK_FREQ_VAL 0 INS_LOSS_NYQ 14 RX_EQ_MODE\
AUTO RX_COUPLING AC RX_TERMINATION VCOM_VREF RX_RATE_GROUP A RX_TERMINATION_PROG_VALUE 800 RX_PPM_OFFSET 200 RX_64B66B_DESCRAMBLER false RX_64B66B_DECODER false RX_64B66B_CRC false OOB_ENABLE false RX_COMMA_ALIGN_WORD\
1 RX_COMMA_SHOW_REALIGN_ENABLE true PCIE_ENABLE false RX_COMMA_P_ENABLE false RX_COMMA_M_ENABLE false RX_COMMA_DOUBLE_ENABLE false RX_COMMA_P_VAL 0101111100 RX_COMMA_M_VAL 1010000011 RX_COMMA_MASK 0000000000\
RX_SLIDE_MODE OFF RX_SSC_PPM 0 RX_CB_NUM_SEQ 0 RX_CB_LEN_SEQ 1 RX_CB_MAX_SKEW 1 RX_CB_MAX_LEVEL 1 RX_CB_MASK 00000000 RX_CB_VAL 00000000000000000000000000000000000000000000000000000000000000000000000000000000\
RX_CB_K 00000000 RX_CB_DISP 00000000 RX_CB_MASK_0_0 false RX_CB_VAL_0_0 0000000000 RX_CB_K_0_0 false RX_CB_DISP_0_0 false RX_CB_MASK_0_1 false RX_CB_VAL_0_1 0000000000 RX_CB_K_0_1 false RX_CB_DISP_0_1\
false RX_CB_MASK_0_2 false RX_CB_VAL_0_2 0000000000 RX_CB_K_0_2 false RX_CB_DISP_0_2 false RX_CB_MASK_0_3 false RX_CB_VAL_0_3 0000000000 RX_CB_K_0_3 false RX_CB_DISP_0_3 false RX_CB_MASK_1_0 false RX_CB_VAL_1_0\
0000000000 RX_CB_K_1_0 false RX_CB_DISP_1_0 false RX_CB_MASK_1_1 false RX_CB_VAL_1_1 0000000000 RX_CB_K_1_1 false RX_CB_DISP_1_1 false RX_CB_MASK_1_2 false RX_CB_VAL_1_2 0000000000 RX_CB_K_1_2 false RX_CB_DISP_1_2\
false RX_CB_MASK_1_3 false RX_CB_VAL_1_3 0000000000 RX_CB_K_1_3 false RX_CB_DISP_1_3 false RX_CC_NUM_SEQ 0 RX_CC_LEN_SEQ 1 RX_CC_PERIODICITY 5000 RX_CC_KEEP_IDLE DISABLE RX_CC_PRECEDENCE ENABLE RX_CC_REPEAT_WAIT\
0 RX_CC_MASK 00000000 RX_CC_VAL 00000000000000000000000000000000000000000000000000000000000000000000000000000000 RX_CC_K 00000000 RX_CC_DISP 00000000 RX_CC_MASK_0_0 false RX_CC_VAL_0_0 0000000000 RX_CC_K_0_0\
false RX_CC_DISP_0_0 false RX_CC_MASK_0_1 false RX_CC_VAL_0_1 0000000000 RX_CC_K_0_1 false RX_CC_DISP_0_1 false RX_CC_MASK_0_2 false RX_CC_VAL_0_2 0000000000 RX_CC_K_0_2 false RX_CC_DISP_0_2 false RX_CC_MASK_0_3\
false RX_CC_VAL_0_3 0000000000 RX_CC_K_0_3 false RX_CC_DISP_0_3 false RX_CC_MASK_1_0 false RX_CC_VAL_1_0 0000000000 RX_CC_K_1_0 false RX_CC_DISP_1_0 false RX_CC_MASK_1_1 false RX_CC_VAL_1_1 0000000000\
RX_CC_K_1_1 false RX_CC_DISP_1_1 false RX_CC_MASK_1_2 false RX_CC_VAL_1_2 0000000000 RX_CC_K_1_2 false RX_CC_DISP_1_2 false RX_CC_MASK_1_3 false RX_CC_VAL_1_3 0000000000 RX_CC_K_1_3 false RX_CC_DISP_1_3\
false PCIE_USERCLK2_FREQ 250 PCIE_USERCLK_FREQ 250 RX_JTOL_FC 10 RX_JTOL_LF_SLOPE -20 RX_BUFFER_BYPASS_MODE Fast_Sync RX_BUFFER_BYPASS_MODE_LANE MULTI RX_BUFFER_RESET_ON_CB_CHANGE ENABLE RX_BUFFER_RESET_ON_COMMAALIGN\
DISABLE RX_BUFFER_RESET_ON_RATE_CHANGE ENABLE RESET_SEQUENCE_INTERVAL 0 RX_COMMA_PRESET NONE RX_COMMA_VALID_ONLY 0 GT_TYPE GTM} \
    CONFIG.PROT0_LR10_SETTINGS {NA NA} \
    CONFIG.PROT0_LR11_SETTINGS {NA NA} \
    CONFIG.PROT0_LR12_SETTINGS {NA NA} \
    CONFIG.PROT0_LR13_SETTINGS {NA NA} \
    CONFIG.PROT0_LR14_SETTINGS {NA NA} \
    CONFIG.PROT0_LR15_SETTINGS {NA NA} \
    CONFIG.PROT0_LR1_SETTINGS {GT_DIRECTION DUPLEX TX_PAM_SEL NRZ TX_HD_EN 0 TX_GRAY_BYP true TX_GRAY_LITTLEENDIAN true TX_PRECODE_BYP true TX_PRECODE_LITTLEENDIAN false TX_LINE_RATE 25.78125 TX_PLL_TYPE\
LCPLL TX_REFCLK_FREQUENCY 322.265625 TX_ACTUAL_REFCLK_FREQUENCY 322.265625000000 TX_FRACN_ENABLED false TX_FRACN_OVRD false TX_FRACN_NUMERATOR 0 TX_REFCLK_SOURCE R0 TX_DATA_ENCODING RAW TX_USER_DATA_WIDTH\
80 TX_INT_DATA_WIDTH 64 TX_BUFFER_MODE 1 TX_BUFFER_BYPASS_MODE Fast_Sync TX_PIPM_ENABLE false TX_OUTCLK_SOURCE TXPROGDIVCLK TXPROGDIV_FREQ_ENABLE true TXPROGDIV_FREQ_SOURCE LCPLL TXPROGDIV_FREQ_VAL 644.531\
TX_DIFF_SWING_EMPH_MODE CUSTOM TX_64B66B_SCRAMBLER false TX_64B66B_ENCODER false TX_64B66B_CRC false TX_RATE_GROUP A TX_LANE_DESKEW_HDMI_ENABLE false TX_BUFFER_RESET_ON_RATE_CHANGE ENABLE PRESET GTM-NRZ_Ethernet_25G\
RX_PAM_SEL NRZ RX_HD_EN 0 RX_GRAY_BYP true RX_GRAY_LITTLEENDIAN true RX_PRECODE_BYP true RX_PRECODE_LITTLEENDIAN false INTERNAL_PRESET GTM-NRZ_Ethernet_25G RX_LINE_RATE 25.78125 RX_PLL_TYPE LCPLL RX_REFCLK_FREQUENCY\
322.265625 RX_ACTUAL_REFCLK_FREQUENCY 322.265625000000 RX_FRACN_ENABLED false RX_FRACN_OVRD false RX_FRACN_NUMERATOR 0 RX_REFCLK_SOURCE R0 RX_DATA_DECODING RAW RX_USER_DATA_WIDTH 80 RX_INT_DATA_WIDTH 64\
RX_BUFFER_MODE 1 RX_OUTCLK_SOURCE RXPROGDIVCLK RXPROGDIV_FREQ_ENABLE true RXPROGDIV_FREQ_SOURCE LCPLL RXPROGDIV_FREQ_VAL 644.531 RXRECCLK_FREQ_ENABLE false RXRECCLK_FREQ_VAL 0 INS_LOSS_NYQ 14 RX_EQ_MODE\
AUTO RX_COUPLING AC RX_TERMINATION VCOM_VREF RX_RATE_GROUP A RX_TERMINATION_PROG_VALUE 800 RX_PPM_OFFSET 200 RX_64B66B_DESCRAMBLER false RX_64B66B_DECODER false RX_64B66B_CRC false OOB_ENABLE false RX_COMMA_ALIGN_WORD\
1 RX_COMMA_SHOW_REALIGN_ENABLE true PCIE_ENABLE false RX_COMMA_P_ENABLE false RX_COMMA_M_ENABLE false RX_COMMA_DOUBLE_ENABLE false RX_COMMA_P_VAL 0101111100 RX_COMMA_M_VAL 1010000011 RX_COMMA_MASK 0000000000\
RX_SLIDE_MODE OFF RX_SSC_PPM 0 RX_CB_NUM_SEQ 0 RX_CB_LEN_SEQ 1 RX_CB_MAX_SKEW 1 RX_CB_MAX_LEVEL 1 RX_CB_MASK 00000000 RX_CB_VAL 00000000000000000000000000000000000000000000000000000000000000000000000000000000\
RX_CB_K 00000000 RX_CB_DISP 00000000 RX_CB_MASK_0_0 false RX_CB_VAL_0_0 0000000000 RX_CB_K_0_0 false RX_CB_DISP_0_0 false RX_CB_MASK_0_1 false RX_CB_VAL_0_1 0000000000 RX_CB_K_0_1 false RX_CB_DISP_0_1\
false RX_CB_MASK_0_2 false RX_CB_VAL_0_2 0000000000 RX_CB_K_0_2 false RX_CB_DISP_0_2 false RX_CB_MASK_0_3 false RX_CB_VAL_0_3 0000000000 RX_CB_K_0_3 false RX_CB_DISP_0_3 false RX_CB_MASK_1_0 false RX_CB_VAL_1_0\
0000000000 RX_CB_K_1_0 false RX_CB_DISP_1_0 false RX_CB_MASK_1_1 false RX_CB_VAL_1_1 0000000000 RX_CB_K_1_1 false RX_CB_DISP_1_1 false RX_CB_MASK_1_2 false RX_CB_VAL_1_2 0000000000 RX_CB_K_1_2 false RX_CB_DISP_1_2\
false RX_CB_MASK_1_3 false RX_CB_VAL_1_3 0000000000 RX_CB_K_1_3 false RX_CB_DISP_1_3 false RX_CC_NUM_SEQ 0 RX_CC_LEN_SEQ 1 RX_CC_PERIODICITY 5000 RX_CC_KEEP_IDLE DISABLE RX_CC_PRECEDENCE ENABLE RX_CC_REPEAT_WAIT\
0 RX_CC_MASK 00000000 RX_CC_VAL 00000000000000000000000000000000000000000000000000000000000000000000000000000000 RX_CC_K 00000000 RX_CC_DISP 00000000 RX_CC_MASK_0_0 false RX_CC_VAL_0_0 0000000000 RX_CC_K_0_0\
false RX_CC_DISP_0_0 false RX_CC_MASK_0_1 false RX_CC_VAL_0_1 0000000000 RX_CC_K_0_1 false RX_CC_DISP_0_1 false RX_CC_MASK_0_2 false RX_CC_VAL_0_2 0000000000 RX_CC_K_0_2 false RX_CC_DISP_0_2 false RX_CC_MASK_0_3\
false RX_CC_VAL_0_3 0000000000 RX_CC_K_0_3 false RX_CC_DISP_0_3 false RX_CC_MASK_1_0 false RX_CC_VAL_1_0 0000000000 RX_CC_K_1_0 false RX_CC_DISP_1_0 false RX_CC_MASK_1_1 false RX_CC_VAL_1_1 0000000000\
RX_CC_K_1_1 false RX_CC_DISP_1_1 false RX_CC_MASK_1_2 false RX_CC_VAL_1_2 0000000000 RX_CC_K_1_2 false RX_CC_DISP_1_2 false RX_CC_MASK_1_3 false RX_CC_VAL_1_3 0000000000 RX_CC_K_1_3 false RX_CC_DISP_1_3\
false PCIE_USERCLK2_FREQ 250 PCIE_USERCLK_FREQ 250 RX_JTOL_FC 10 RX_JTOL_LF_SLOPE -20 RX_BUFFER_BYPASS_MODE Fast_Sync RX_BUFFER_BYPASS_MODE_LANE MULTI RX_BUFFER_RESET_ON_CB_CHANGE ENABLE RX_BUFFER_RESET_ON_COMMAALIGN\
DISABLE RX_BUFFER_RESET_ON_RATE_CHANGE ENABLE RESET_SEQUENCE_INTERVAL 0 RX_COMMA_PRESET NONE RX_COMMA_VALID_ONLY 0 GT_TYPE GTM} \
    CONFIG.PROT0_LR2_SETTINGS {GT_DIRECTION DUPLEX TX_PAM_SEL NRZ TX_HD_EN 0 TX_GRAY_BYP true TX_GRAY_LITTLEENDIAN true TX_PRECODE_BYP true TX_PRECODE_LITTLEENDIAN false TX_LINE_RATE 25.78125 TX_PLL_TYPE\
LCPLL TX_REFCLK_FREQUENCY 322.265625 TX_ACTUAL_REFCLK_FREQUENCY 322.265625000000 TX_FRACN_ENABLED false TX_FRACN_OVRD false TX_FRACN_NUMERATOR 0 TX_REFCLK_SOURCE R0 TX_DATA_ENCODING RAW TX_USER_DATA_WIDTH\
80 TX_INT_DATA_WIDTH 64 TX_BUFFER_MODE 1 TX_BUFFER_BYPASS_MODE Fast_Sync TX_PIPM_ENABLE false TX_OUTCLK_SOURCE TXPROGDIVCLK TXPROGDIV_FREQ_ENABLE true TXPROGDIV_FREQ_SOURCE LCPLL TXPROGDIV_FREQ_VAL 644.531\
TX_DIFF_SWING_EMPH_MODE CUSTOM TX_64B66B_SCRAMBLER false TX_64B66B_ENCODER false TX_64B66B_CRC false TX_RATE_GROUP A TX_LANE_DESKEW_HDMI_ENABLE false TX_BUFFER_RESET_ON_RATE_CHANGE ENABLE PRESET GTM-NRZ_Ethernet_25G\
RX_PAM_SEL NRZ RX_HD_EN 0 RX_GRAY_BYP true RX_GRAY_LITTLEENDIAN true RX_PRECODE_BYP true RX_PRECODE_LITTLEENDIAN false INTERNAL_PRESET GTM-NRZ_Ethernet_25G RX_LINE_RATE 25.78125 RX_PLL_TYPE LCPLL RX_REFCLK_FREQUENCY\
322.265625 RX_ACTUAL_REFCLK_FREQUENCY 322.265625000000 RX_FRACN_ENABLED false RX_FRACN_OVRD false RX_FRACN_NUMERATOR 0 RX_REFCLK_SOURCE R0 RX_DATA_DECODING RAW RX_USER_DATA_WIDTH 80 RX_INT_DATA_WIDTH 64\
RX_BUFFER_MODE 1 RX_OUTCLK_SOURCE RXPROGDIVCLK RXPROGDIV_FREQ_ENABLE true RXPROGDIV_FREQ_SOURCE LCPLL RXPROGDIV_FREQ_VAL 644.531 RXRECCLK_FREQ_ENABLE false RXRECCLK_FREQ_VAL 0 INS_LOSS_NYQ 14 RX_EQ_MODE\
AUTO RX_COUPLING AC RX_TERMINATION VCOM_VREF RX_RATE_GROUP A RX_TERMINATION_PROG_VALUE 800 RX_PPM_OFFSET 200 RX_64B66B_DESCRAMBLER false RX_64B66B_DECODER false RX_64B66B_CRC false OOB_ENABLE false RX_COMMA_ALIGN_WORD\
1 RX_COMMA_SHOW_REALIGN_ENABLE true PCIE_ENABLE false RX_COMMA_P_ENABLE false RX_COMMA_M_ENABLE false RX_COMMA_DOUBLE_ENABLE false RX_COMMA_P_VAL 0101111100 RX_COMMA_M_VAL 1010000011 RX_COMMA_MASK 0000000000\
RX_SLIDE_MODE OFF RX_SSC_PPM 0 RX_CB_NUM_SEQ 0 RX_CB_LEN_SEQ 1 RX_CB_MAX_SKEW 1 RX_CB_MAX_LEVEL 1 RX_CB_MASK 00000000 RX_CB_VAL 00000000000000000000000000000000000000000000000000000000000000000000000000000000\
RX_CB_K 00000000 RX_CB_DISP 00000000 RX_CB_MASK_0_0 false RX_CB_VAL_0_0 0000000000 RX_CB_K_0_0 false RX_CB_DISP_0_0 false RX_CB_MASK_0_1 false RX_CB_VAL_0_1 0000000000 RX_CB_K_0_1 false RX_CB_DISP_0_1\
false RX_CB_MASK_0_2 false RX_CB_VAL_0_2 0000000000 RX_CB_K_0_2 false RX_CB_DISP_0_2 false RX_CB_MASK_0_3 false RX_CB_VAL_0_3 0000000000 RX_CB_K_0_3 false RX_CB_DISP_0_3 false RX_CB_MASK_1_0 false RX_CB_VAL_1_0\
0000000000 RX_CB_K_1_0 false RX_CB_DISP_1_0 false RX_CB_MASK_1_1 false RX_CB_VAL_1_1 0000000000 RX_CB_K_1_1 false RX_CB_DISP_1_1 false RX_CB_MASK_1_2 false RX_CB_VAL_1_2 0000000000 RX_CB_K_1_2 false RX_CB_DISP_1_2\
false RX_CB_MASK_1_3 false RX_CB_VAL_1_3 0000000000 RX_CB_K_1_3 false RX_CB_DISP_1_3 false RX_CC_NUM_SEQ 0 RX_CC_LEN_SEQ 1 RX_CC_PERIODICITY 5000 RX_CC_KEEP_IDLE DISABLE RX_CC_PRECEDENCE ENABLE RX_CC_REPEAT_WAIT\
0 RX_CC_MASK 00000000 RX_CC_VAL 00000000000000000000000000000000000000000000000000000000000000000000000000000000 RX_CC_K 00000000 RX_CC_DISP 00000000 RX_CC_MASK_0_0 false RX_CC_VAL_0_0 0000000000 RX_CC_K_0_0\
false RX_CC_DISP_0_0 false RX_CC_MASK_0_1 false RX_CC_VAL_0_1 0000000000 RX_CC_K_0_1 false RX_CC_DISP_0_1 false RX_CC_MASK_0_2 false RX_CC_VAL_0_2 0000000000 RX_CC_K_0_2 false RX_CC_DISP_0_2 false RX_CC_MASK_0_3\
false RX_CC_VAL_0_3 0000000000 RX_CC_K_0_3 false RX_CC_DISP_0_3 false RX_CC_MASK_1_0 false RX_CC_VAL_1_0 0000000000 RX_CC_K_1_0 false RX_CC_DISP_1_0 false RX_CC_MASK_1_1 false RX_CC_VAL_1_1 0000000000\
RX_CC_K_1_1 false RX_CC_DISP_1_1 false RX_CC_MASK_1_2 false RX_CC_VAL_1_2 0000000000 RX_CC_K_1_2 false RX_CC_DISP_1_2 false RX_CC_MASK_1_3 false RX_CC_VAL_1_3 0000000000 RX_CC_K_1_3 false RX_CC_DISP_1_3\
false PCIE_USERCLK2_FREQ 250 PCIE_USERCLK_FREQ 250 RX_JTOL_FC 10 RX_JTOL_LF_SLOPE -20 RX_BUFFER_BYPASS_MODE Fast_Sync RX_BUFFER_BYPASS_MODE_LANE MULTI RX_BUFFER_RESET_ON_CB_CHANGE ENABLE RX_BUFFER_RESET_ON_COMMAALIGN\
DISABLE RX_BUFFER_RESET_ON_RATE_CHANGE ENABLE RESET_SEQUENCE_INTERVAL 0 RX_COMMA_PRESET NONE RX_COMMA_VALID_ONLY 0 GT_TYPE GTM} \
    CONFIG.PROT0_LR3_SETTINGS {NA NA} \
    CONFIG.PROT0_LR4_SETTINGS {NA NA} \
    CONFIG.PROT0_LR5_SETTINGS {NA NA} \
    CONFIG.PROT0_LR6_SETTINGS {NA NA} \
    CONFIG.PROT0_LR7_SETTINGS {NA NA} \
    CONFIG.PROT0_LR8_SETTINGS {NA NA} \
    CONFIG.PROT0_LR9_SETTINGS {NA NA} \
    CONFIG.PROT0_NO_OF_LANES {4} \
    CONFIG.PROT0_RX_MASTERCLK_SRC {RX0} \
    CONFIG.PROT0_TX_MASTERCLK_SRC {TX0} \
    CONFIG.QUAD_USAGE {TX_QUAD_CH {TXQuad_0_/mrmac_0_gt_wrapper/gt_quad_base {/mrmac_0_gt_wrapper/gt_quad_base mrmac_0_exdes_support_mrmac_0_core_0_0.IP_CH0,mrmac_0_exdes_support_mrmac_0_core_0_0.IP_CH1,mrmac_0_exdes_support_mrmac_0_core_0_0.IP_CH2,mrmac_0_exdes_support_mrmac_0_core_0_0.IP_CH3\
MSTRCLK 1,0,0,0 IS_CURRENT_QUAD 1}} RX_QUAD_CH {RXQuad_0_/mrmac_0_gt_wrapper/gt_quad_base {/mrmac_0_gt_wrapper/gt_quad_base mrmac_0_exdes_support_mrmac_0_core_0_0.IP_CH0,mrmac_0_exdes_support_mrmac_0_core_0_0.IP_CH1,mrmac_0_exdes_support_mrmac_0_core_0_0.IP_CH2,mrmac_0_exdes_support_mrmac_0_core_0_0.IP_CH3\
MSTRCLK 1,0,0,0 IS_CURRENT_QUAD 1}}} \
    CONFIG.REFCLK_LIST {/ref_clk_p_0} \
    CONFIG.REFCLK_STRING {HSCLK0_LCPLLGTREFCLK0 refclk_PROT0_R0_322.265625_MHz_unique1} \
    CONFIG.RX0_LANE_SEL {PROT0} \
    CONFIG.RX1_LANE_SEL {PROT0} \
    CONFIG.RX2_LANE_SEL {PROT0} \
    CONFIG.RX3_LANE_SEL {PROT0} \
    CONFIG.TX0_LANE_SEL {PROT0} \
    CONFIG.TX1_LANE_SEL {PROT0} \
    CONFIG.TX2_LANE_SEL {PROT0} \
    CONFIG.TX3_LANE_SEL {PROT0} \
  ] $gt_quad_base

  set_property -dict [list \
    CONFIG.APB3_CLK_FREQUENCY.VALUE_MODE {auto} \
    CONFIG.CHANNEL_ORDERING.VALUE_MODE {auto} \
    CONFIG.GT_TYPE.VALUE_MODE {auto} \
    CONFIG.PROT0_ENABLE.VALUE_MODE {auto} \
    CONFIG.PROT0_GT_DIRECTION.VALUE_MODE {auto} \
    CONFIG.PROT0_LR0_SETTINGS.VALUE_MODE {auto} \
    CONFIG.PROT0_LR10_SETTINGS.VALUE_MODE {auto} \
    CONFIG.PROT0_LR11_SETTINGS.VALUE_MODE {auto} \
    CONFIG.PROT0_LR12_SETTINGS.VALUE_MODE {auto} \
    CONFIG.PROT0_LR13_SETTINGS.VALUE_MODE {auto} \
    CONFIG.PROT0_LR14_SETTINGS.VALUE_MODE {auto} \
    CONFIG.PROT0_LR15_SETTINGS.VALUE_MODE {auto} \
    CONFIG.PROT0_LR1_SETTINGS.VALUE_MODE {auto} \
    CONFIG.PROT0_LR2_SETTINGS.VALUE_MODE {auto} \
    CONFIG.PROT0_LR3_SETTINGS.VALUE_MODE {auto} \
    CONFIG.PROT0_LR4_SETTINGS.VALUE_MODE {auto} \
    CONFIG.PROT0_LR5_SETTINGS.VALUE_MODE {auto} \
    CONFIG.PROT0_LR6_SETTINGS.VALUE_MODE {auto} \
    CONFIG.PROT0_LR7_SETTINGS.VALUE_MODE {auto} \
    CONFIG.PROT0_LR8_SETTINGS.VALUE_MODE {auto} \
    CONFIG.PROT0_LR9_SETTINGS.VALUE_MODE {auto} \
    CONFIG.PROT0_NO_OF_LANES.VALUE_MODE {auto} \
    CONFIG.PROT0_RX_MASTERCLK_SRC.VALUE_MODE {auto} \
    CONFIG.PROT0_TX_MASTERCLK_SRC.VALUE_MODE {auto} \
    CONFIG.QUAD_USAGE.VALUE_MODE {auto} \
    CONFIG.REFCLK_LIST.VALUE_MODE {auto} \
    CONFIG.RX0_LANE_SEL.VALUE_MODE {auto} \
    CONFIG.RX1_LANE_SEL.VALUE_MODE {auto} \
    CONFIG.RX2_LANE_SEL.VALUE_MODE {auto} \
    CONFIG.RX3_LANE_SEL.VALUE_MODE {auto} \
    CONFIG.TX0_LANE_SEL.VALUE_MODE {auto} \
    CONFIG.TX1_LANE_SEL.VALUE_MODE {auto} \
    CONFIG.TX2_LANE_SEL.VALUE_MODE {auto} \
    CONFIG.TX3_LANE_SEL.VALUE_MODE {auto} \
  ] $gt_quad_base

  # Create instance: mbufg_gt_0, and set properties
  set mbufg_gt_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:util_ds_buf:2.2 mbufg_gt_0 ]
  set_property -dict [list \
    CONFIG.C_BUFG_GT_SYNC {true} \
    CONFIG.C_BUF_TYPE {MBUFG_GT} \
  ] $mbufg_gt_0

  # Create instance: mbufg_gt_1, and set properties
  set mbufg_gt_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:util_ds_buf:2.2 mbufg_gt_1 ]
  set_property -dict [list \
    CONFIG.C_BUFG_GT_SYNC {true} \
    CONFIG.C_BUF_TYPE {MBUFG_GT} \
  ] $mbufg_gt_1

  # Create instance: mbufg_gt_1_1, and set properties
  set mbufg_gt_1_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:util_ds_buf:2.2 mbufg_gt_1_1 ]
  set_property -dict [list \
    CONFIG.C_BUFG_GT_SYNC {true} \
    CONFIG.C_BUF_TYPE {MBUFG_GT} \
  ] $mbufg_gt_1_1

  # Create instance: mbufg_gt_1_2, and set properties
  set mbufg_gt_1_2 [ create_bd_cell -type ip -vlnv xilinx.com:ip:util_ds_buf:2.2 mbufg_gt_1_2 ]
  set_property -dict [list \
    CONFIG.C_BUFG_GT_SYNC {true} \
    CONFIG.C_BUF_TYPE {MBUFG_GT} \
  ] $mbufg_gt_1_2

  # Create instance: mbufg_gt_1_3, and set properties
  set mbufg_gt_1_3 [ create_bd_cell -type ip -vlnv xilinx.com:ip:util_ds_buf:2.2 mbufg_gt_1_3 ]
  set_property -dict [list \
    CONFIG.C_BUFG_GT_SYNC {true} \
    CONFIG.C_BUF_TYPE {MBUFG_GT} \
  ] $mbufg_gt_1_3

  # Create instance: util_ds_buf_0, and set properties
  set util_ds_buf_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:util_ds_buf:2.2 util_ds_buf_0 ]
  set_property CONFIG.C_BUF_TYPE {IBUFDSGTE} $util_ds_buf_0

  # Create instance: xlconst_mbufg_0, and set properties
  set xlconst_mbufg_0 [ create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilconstant:1.0 xlconst_mbufg_0 ]
  set_property -dict [list \
    CONFIG.CONST_VAL {1} \
    CONFIG.CONST_WIDTH {1} \
  ] $xlconst_mbufg_0

  # Create interface connections
  connect_bd_intf_net -intf_net APB3_INTF_1 [get_bd_intf_pins APB3_INTF] [get_bd_intf_pins gt_quad_base/APB3_INTF]
  connect_bd_intf_net -intf_net CLK_IN_D_1 [get_bd_intf_pins CLK_IN_D] [get_bd_intf_pins util_ds_buf_0/CLK_IN_D]
  connect_bd_intf_net -intf_net gt_quad_base_GT_Serial [get_bd_intf_pins GT_Serial] [get_bd_intf_pins gt_quad_base/GT_Serial]
  connect_bd_intf_net -intf_net mrmac_0_core_gt_rx_serdes_interface_0 [get_bd_intf_pins RX0_GT_IP_Interface] [get_bd_intf_pins gt_quad_base/RX0_GT_IP_Interface]
  connect_bd_intf_net -intf_net mrmac_0_core_gt_rx_serdes_interface_1 [get_bd_intf_pins RX1_GT_IP_Interface] [get_bd_intf_pins gt_quad_base/RX1_GT_IP_Interface]
  connect_bd_intf_net -intf_net mrmac_0_core_gt_rx_serdes_interface_2 [get_bd_intf_pins RX2_GT_IP_Interface] [get_bd_intf_pins gt_quad_base/RX2_GT_IP_Interface]
  connect_bd_intf_net -intf_net mrmac_0_core_gt_rx_serdes_interface_3 [get_bd_intf_pins RX3_GT_IP_Interface] [get_bd_intf_pins gt_quad_base/RX3_GT_IP_Interface]
  connect_bd_intf_net -intf_net mrmac_0_core_gt_tx_serdes_interface_0 [get_bd_intf_pins TX0_GT_IP_Interface] [get_bd_intf_pins gt_quad_base/TX0_GT_IP_Interface]
  connect_bd_intf_net -intf_net mrmac_0_core_gt_tx_serdes_interface_1 [get_bd_intf_pins TX1_GT_IP_Interface] [get_bd_intf_pins gt_quad_base/TX1_GT_IP_Interface]
  connect_bd_intf_net -intf_net mrmac_0_core_gt_tx_serdes_interface_2 [get_bd_intf_pins TX2_GT_IP_Interface] [get_bd_intf_pins gt_quad_base/TX2_GT_IP_Interface]
  connect_bd_intf_net -intf_net mrmac_0_core_gt_tx_serdes_interface_3 [get_bd_intf_pins TX3_GT_IP_Interface] [get_bd_intf_pins gt_quad_base/TX3_GT_IP_Interface]

  # Create pin connections
  connect_bd_net -net apb3clk_quad_1  [get_bd_pins apb3clk_quad] [get_bd_pins gt_quad_base/apb3clk]
  connect_bd_net -net ch0_loopback_1  [get_bd_pins ch0_loopback] [get_bd_pins gt_quad_base/ch0_loopback]
  connect_bd_net -net ch0_rxrate_1  [get_bd_pins ch0_rxrate] [get_bd_pins gt_quad_base/ch0_rxrate]
  connect_bd_net -net ch0_rxusrclk_1  [get_bd_pins ch0_rxusrclk] [get_bd_pins gt_quad_base/ch0_rxusrclk]
  connect_bd_net -net ch0_txrate_1  [get_bd_pins ch0_txrate] [get_bd_pins gt_quad_base/ch0_txrate]
  connect_bd_net -net ch0_txusrclk_1  [get_bd_pins ch0_txusrclk] [get_bd_pins gt_quad_base/ch0_txusrclk]
  connect_bd_net -net ch1_loopback_1  [get_bd_pins ch1_loopback] [get_bd_pins gt_quad_base/ch1_loopback]
  connect_bd_net -net ch1_rxrate_1  [get_bd_pins ch1_rxrate] [get_bd_pins gt_quad_base/ch1_rxrate]
  connect_bd_net -net ch1_rxusrclk_1  [get_bd_pins ch1_rxusrclk] [get_bd_pins gt_quad_base/ch1_rxusrclk]
  connect_bd_net -net ch1_txrate_1  [get_bd_pins ch1_txrate] [get_bd_pins gt_quad_base/ch1_txrate]
  connect_bd_net -net ch1_txusrclk_1  [get_bd_pins ch1_txusrclk] [get_bd_pins gt_quad_base/ch1_txusrclk]
  connect_bd_net -net ch2_loopback_1  [get_bd_pins ch2_loopback] [get_bd_pins gt_quad_base/ch2_loopback]
  connect_bd_net -net ch2_rxrate_1  [get_bd_pins ch2_rxrate] [get_bd_pins gt_quad_base/ch2_rxrate]
  connect_bd_net -net ch2_rxusrclk_1  [get_bd_pins ch2_rxusrclk] [get_bd_pins gt_quad_base/ch2_rxusrclk]
  connect_bd_net -net ch2_txrate_1  [get_bd_pins ch2_txrate] [get_bd_pins gt_quad_base/ch2_txrate]
  connect_bd_net -net ch2_txusrclk_1  [get_bd_pins ch2_txusrclk] [get_bd_pins gt_quad_base/ch2_txusrclk]
  connect_bd_net -net ch3_loopback_1  [get_bd_pins ch3_loopback] [get_bd_pins gt_quad_base/ch3_loopback]
  connect_bd_net -net ch3_rxrate_1  [get_bd_pins ch3_rxrate] [get_bd_pins gt_quad_base/ch3_rxrate]
  connect_bd_net -net ch3_rxusrclk_1  [get_bd_pins ch3_rxusrclk] [get_bd_pins gt_quad_base/ch3_rxusrclk]
  connect_bd_net -net ch3_txrate_1  [get_bd_pins ch3_txrate] [get_bd_pins gt_quad_base/ch3_txrate]
  connect_bd_net -net ch3_txusrclk_1  [get_bd_pins ch3_txusrclk] [get_bd_pins gt_quad_base/ch3_txusrclk]
  connect_bd_net -net gt_quad_base_ch0_rxoutclk  [get_bd_pins gt_quad_base/ch0_rxoutclk] [get_bd_pins mbufg_gt_1/MBUFG_GT_I]
  connect_bd_net -net gt_quad_base_ch0_txoutclk  [get_bd_pins gt_quad_base/ch0_txoutclk] [get_bd_pins mbufg_gt_0/MBUFG_GT_I]
  connect_bd_net -net gt_quad_base_ch1_rxoutclk  [get_bd_pins gt_quad_base/ch1_rxoutclk] [get_bd_pins mbufg_gt_1_1/MBUFG_GT_I]
  connect_bd_net -net gt_quad_base_ch2_rxoutclk  [get_bd_pins gt_quad_base/ch2_rxoutclk] [get_bd_pins mbufg_gt_1_2/MBUFG_GT_I]
  connect_bd_net -net gt_quad_base_ch3_rxoutclk  [get_bd_pins gt_quad_base/ch3_rxoutclk] [get_bd_pins mbufg_gt_1_3/MBUFG_GT_I]
  connect_bd_net -net gt_quad_base_gtpowergood  [get_bd_pins gt_quad_base/gtpowergood] [get_bd_pins gtpowergood]
  connect_bd_net -net gt_quad_base_txn  [get_bd_pins gt_quad_base/txn] [get_bd_pins gt_txn_out_0]
  connect_bd_net -net gt_quad_base_txp  [get_bd_pins gt_quad_base/txp] [get_bd_pins gt_txp_out_0]
  connect_bd_net -net gt_rxn_in_0_1  [get_bd_pins gt_rxn_in_0] [get_bd_pins gt_quad_base/rxn]
  connect_bd_net -net gt_rxp_in_0_1  [get_bd_pins gt_rxp_in_0] [get_bd_pins gt_quad_base/rxp]
  connect_bd_net -net mbufg_gt_0_MBUFG_GT_O1  [get_bd_pins mbufg_gt_0/MBUFG_GT_O1] [get_bd_pins ch0_tx_usr_clk]
  connect_bd_net -net mbufg_gt_0_MBUFG_GT_O2  [get_bd_pins mbufg_gt_0/MBUFG_GT_O2] [get_bd_pins ch0_tx_usr_clk2]
  connect_bd_net -net mbufg_gt_1_1_MBUFG_GT_O1  [get_bd_pins mbufg_gt_1_1/MBUFG_GT_O1] [get_bd_pins ch1_rx_usr_clk]
  connect_bd_net -net mbufg_gt_1_1_MBUFG_GT_O2  [get_bd_pins mbufg_gt_1_1/MBUFG_GT_O2] [get_bd_pins ch1_rx_usr_clk2]
  connect_bd_net -net mbufg_gt_1_2_MBUFG_GT_O1  [get_bd_pins mbufg_gt_1_2/MBUFG_GT_O1] [get_bd_pins ch2_rx_usr_clk]
  connect_bd_net -net mbufg_gt_1_2_MBUFG_GT_O2  [get_bd_pins mbufg_gt_1_2/MBUFG_GT_O2] [get_bd_pins ch2_rx_usr_clk2]
  connect_bd_net -net mbufg_gt_1_3_MBUFG_GT_O1  [get_bd_pins mbufg_gt_1_3/MBUFG_GT_O1] [get_bd_pins ch3_rx_usr_clk]
  connect_bd_net -net mbufg_gt_1_3_MBUFG_GT_O2  [get_bd_pins mbufg_gt_1_3/MBUFG_GT_O2] [get_bd_pins ch3_rx_usr_clk2]
  connect_bd_net -net mbufg_gt_1_MBUFG_GT_O1  [get_bd_pins mbufg_gt_1/MBUFG_GT_O1] [get_bd_pins ch0_rx_usr_clk]
  connect_bd_net -net mbufg_gt_1_MBUFG_GT_O2  [get_bd_pins mbufg_gt_1/MBUFG_GT_O2] [get_bd_pins ch0_rx_usr_clk2]
  connect_bd_net -net mrmac_0_core_rx_clr_out_0  [get_bd_pins MBUFG_GT_CLR1] [get_bd_pins mbufg_gt_1/MBUFG_GT_CLR]
  connect_bd_net -net mrmac_0_core_rx_clr_out_1  [get_bd_pins MBUFG_GT_CLR2] [get_bd_pins mbufg_gt_1_1/MBUFG_GT_CLR]
  connect_bd_net -net mrmac_0_core_rx_clr_out_2  [get_bd_pins MBUFG_GT_CLR3] [get_bd_pins mbufg_gt_1_2/MBUFG_GT_CLR]
  connect_bd_net -net mrmac_0_core_rx_clr_out_3  [get_bd_pins MBUFG_GT_CLR4] [get_bd_pins mbufg_gt_1_3/MBUFG_GT_CLR]
  connect_bd_net -net mrmac_0_core_rx_clrb_leaf_out_0  [get_bd_pins MBUFG_GT_CLRB_LEAF1] [get_bd_pins mbufg_gt_1/MBUFG_GT_CLRB_LEAF]
  connect_bd_net -net mrmac_0_core_rx_clrb_leaf_out_1  [get_bd_pins MBUFG_GT_CLRB_LEAF2] [get_bd_pins mbufg_gt_1_1/MBUFG_GT_CLRB_LEAF]
  connect_bd_net -net mrmac_0_core_rx_clrb_leaf_out_2  [get_bd_pins MBUFG_GT_CLRB_LEAF3] [get_bd_pins mbufg_gt_1_2/MBUFG_GT_CLRB_LEAF]
  connect_bd_net -net mrmac_0_core_rx_clrb_leaf_out_3  [get_bd_pins MBUFG_GT_CLRB_LEAF4] [get_bd_pins mbufg_gt_1_3/MBUFG_GT_CLRB_LEAF]
  connect_bd_net -net mrmac_0_core_tx_clr_out_0  [get_bd_pins MBUFG_GT_CLR] [get_bd_pins mbufg_gt_0/MBUFG_GT_CLR]
  connect_bd_net -net mrmac_0_core_tx_clrb_leaf_out_0  [get_bd_pins MBUFG_GT_CLRB_LEAF] [get_bd_pins mbufg_gt_0/MBUFG_GT_CLRB_LEAF]
  connect_bd_net -net s_axi_aresetn_1  [get_bd_pins s_axi_aresetn] [get_bd_pins gt_quad_base/apb3presetn]
  connect_bd_net -net util_ds_buf_0_IBUF_OUT  [get_bd_pins util_ds_buf_0/IBUF_OUT] [get_bd_pins gt_quad_base/GT_REFCLK0]

  connect_bd_net -net xlconst_mbufg_0_dout  [get_bd_pins xlconst_mbufg_0/dout] \
  [get_bd_pins mbufg_gt_0/MBUFG_GT_CE] \
  [get_bd_pins mbufg_gt_1/MBUFG_GT_CE] \
  [get_bd_pins mbufg_gt_1_1/MBUFG_GT_CE] \
  [get_bd_pins mbufg_gt_1_2/MBUFG_GT_CE] \
  [get_bd_pins mbufg_gt_1_3/MBUFG_GT_CE]

  # Restore current instance
  current_bd_instance $oldCurInst
}

proc create_hier_cell_eth_wrapper  { parentCell nameHier } {

  set parentObj [check_parent_hier $parentCell $nameHier]
  if { $parentObj == "" } { return }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj

  # Create cell and set as current instance
  set hier_obj [create_bd_cell -type hier $nameHier]
  current_bd_instance $hier_obj

  ####################################
  # Create pins
  ####################################
  # Create interface pins
  set GT_Serial [ create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:gt_rtl:1.0 GT_Serial ]

  set CLK_IN_D [ create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 CLK_IN_D ]

  set s_axi [ create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 s_axi ]

  create_bd_intf_pin -mode Slave -vlnv xilinx.com:display_mrmac:mrmac_ctrl_ports:2.0 ctl_tx_port0
  create_bd_intf_pin -mode Slave -vlnv xilinx.com:display_mrmac:mrmac_ctrl_ports:2.0 ctl_tx_port1
  create_bd_intf_pin -mode Slave -vlnv xilinx.com:display_mrmac:mrmac_ctrl_ports:2.0 ctl_tx_port2
  create_bd_intf_pin -mode Slave -vlnv xilinx.com:display_mrmac:mrmac_ctrl_ports:2.0 ctl_tx_port3
  create_bd_intf_pin -mode Master -vlnv xilinx.com:display_mrmac:mrmac_statistics_ports:2.0 stat_tx_port0
  create_bd_intf_pin -mode Master -vlnv xilinx.com:display_mrmac:mrmac_statistics_ports:2.0 stat_tx_port1
  create_bd_intf_pin -mode Master -vlnv xilinx.com:display_mrmac:mrmac_statistics_ports:2.0 stat_tx_port2
  create_bd_intf_pin -mode Master -vlnv xilinx.com:display_mrmac:mrmac_statistics_ports:2.0 stat_tx_port3
  create_bd_intf_pin -mode Master -vlnv xilinx.com:display_mrmac:mrmac_statistics_ports:2.0 stat_rx_port0
  create_bd_intf_pin -mode Master -vlnv xilinx.com:display_mrmac:mrmac_statistics_ports:2.0 stat_rx_port1
  create_bd_intf_pin -mode Master -vlnv xilinx.com:display_mrmac:mrmac_statistics_ports:2.0 stat_rx_port2
  create_bd_intf_pin -mode Master -vlnv xilinx.com:display_mrmac:mrmac_statistics_ports:2.0 stat_rx_port3
  create_bd_intf_pin -mode Slave -vlnv xilinx.com:display_mrmac:mrmac_statistics_ports:2.0 tx_preamblein
  create_bd_intf_pin -mode Master -vlnv xilinx.com:display_mrmac:mrmac_statistics_ports:2.0 rx_preambleout
  create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:apb_rtl:1.0 APB3_INTF

  # Create pins
  set apb3clk_quad [ create_bd_pin -dir I -type clk apb3clk_quad ]
  set tx_axi_clk [ create_bd_pin -dir I -from 3 -to 0 -type clk tx_axi_clk ]
  set rx_axi_clk [ create_bd_pin -dir I -from 3 -to 0 -type clk rx_axi_clk ]

  set tx_core_reset [ create_bd_pin -dir I -from 3 -to 0 -type rst tx_core_reset ]
  set rx_core_reset [ create_bd_pin -dir I -from 3 -to 0 -type rst rx_core_reset ]
  set tx_serdes_reset [ create_bd_pin -dir I -from 3 -to 0 -type rst tx_serdes_reset ]
  set rx_serdes_reset [ create_bd_pin -dir I -from 3 -to 0 -type rst rx_serdes_reset ]
  set rx_flexif_reset [ create_bd_pin -dir I -from 3 -to 0 -type rst rx_flexif_reset ]

  set s_axi_aclk [ create_bd_pin -dir I -type clk s_axi_aclk ]
  set s_axi_aresetn [ create_bd_pin -dir I -type rst s_axi_aresetn ]

  set tx_core_clk [ create_bd_pin -dir I -from 3 -to 0 -type gt_usrclk tx_core_clk ]
  set rx_core_clk [ create_bd_pin -dir I -from 3 -to 0 -type gt_usrclk rx_core_clk ]
  set rx_serdes_clk [ create_bd_pin -dir I -from 3 -to 0 -type gt_usrclk rx_serdes_clk ]
  set tx_alt_serdes_clk [ create_bd_pin -dir I -from 3 -to 0 -type gt_usrclk tx_alt_serdes_clk ]
  set rx_alt_serdes_clk [ create_bd_pin -dir I -from 3 -to 0 -type gt_usrclk rx_alt_serdes_clk ]

  set tx_flexif_clk [ create_bd_pin -dir I -from 3 -to 0 -type clk tx_flexif_clk ]
  set rx_flexif_clk [ create_bd_pin -dir I -from 3 -to 0 -type clk rx_flexif_clk ]
  set tx_ts_clk [ create_bd_pin -dir I -from 3 -to 0 -type clk tx_ts_clk ]
  set rx_ts_clk [ create_bd_pin -dir I -from 3 -to 0 -type clk rx_ts_clk ]

  set pm_tick [ create_bd_pin -dir I -from 3 -to 0 pm_tick ]
  set gt_tx_reset_done_out [ create_bd_pin -dir O -from 3 -to 0 gt_tx_reset_done_out ]
  set gt_rx_reset_done_out [ create_bd_pin -dir O -from 3 -to 0 gt_rx_reset_done_out ]
  set gt_reset_all_in [ create_bd_pin -dir I -from 3 -to 0 gt_reset_all_in ]
  set gtpowergood_in [ create_bd_pin -dir I gtpowergood_in ]
  set ch0_tx_usr_clk [ create_bd_pin -dir O -from 0 -to 0 -type gt_usrclk ch0_tx_usr_clk ]
  set ch0_rx_usr_clk [ create_bd_pin -dir O -from 0 -to 0 -type gt_usrclk ch0_rx_usr_clk ]
  set ch1_rx_usr_clk [ create_bd_pin -dir O -from 0 -to 0 -type gt_usrclk ch1_rx_usr_clk ]
  set ch2_rx_usr_clk [ create_bd_pin -dir O -from 0 -to 0 -type gt_usrclk ch2_rx_usr_clk ]
  set ch3_rx_usr_clk [ create_bd_pin -dir O -from 0 -to 0 -type gt_usrclk ch3_rx_usr_clk ]
  set ch0_tx_usr_clk2 [ create_bd_pin -dir O -from 0 -to 0 -type gt_usrclk ch0_tx_usr_clk2 ]
  set ch0_rx_usr_clk2 [ create_bd_pin -dir O -from 0 -to 0 -type gt_usrclk ch0_rx_usr_clk2 ]
  set ch2_rx_usr_clk2 [ create_bd_pin -dir O -from 0 -to 0 -type gt_usrclk ch2_rx_usr_clk2 ]
  set ch1_rx_usr_clk2 [ create_bd_pin -dir O -from 0 -to 0 -type gt_usrclk ch1_rx_usr_clk2 ]
  set ch3_rx_usr_clk2 [ create_bd_pin -dir O -from 0 -to 0 -type gt_usrclk ch3_rx_usr_clk2 ]
  set tx_axis_tdata0 [ create_bd_pin -dir I -from 63 -to 0 tx_axis_tdata0 ]
  set tx_axis_tdata1 [ create_bd_pin -dir I -from 63 -to 0 tx_axis_tdata1 ]
  set tx_axis_tdata2 [ create_bd_pin -dir I -from 63 -to 0 tx_axis_tdata2 ]
  set tx_axis_tdata3 [ create_bd_pin -dir I -from 63 -to 0 tx_axis_tdata3 ]
  set tx_axis_tdata4 [ create_bd_pin -dir I -from 63 -to 0 tx_axis_tdata4 ]
  set tx_axis_tdata5 [ create_bd_pin -dir I -from 63 -to 0 tx_axis_tdata5 ]
  set tx_axis_tkeep_user0 [ create_bd_pin -dir I -from 10 -to 0 tx_axis_tkeep_user0 ]
  set tx_axis_tkeep_user1 [ create_bd_pin -dir I -from 10 -to 0 tx_axis_tkeep_user1 ]
  set tx_axis_tkeep_user2 [ create_bd_pin -dir I -from 10 -to 0 tx_axis_tkeep_user2 ]
  set tx_axis_tkeep_user3 [ create_bd_pin -dir I -from 10 -to 0 tx_axis_tkeep_user3 ]
  set tx_axis_tkeep_user4 [ create_bd_pin -dir I -from 10 -to 0 tx_axis_tkeep_user4 ]
  set tx_axis_tkeep_user5 [ create_bd_pin -dir I -from 10 -to 0 tx_axis_tkeep_user5 ]
  set tx_axis_tready_0 [ create_bd_pin -dir O tx_axis_tready_0 ]
  set tx_axis_tlast_0 [ create_bd_pin -dir I tx_axis_tlast_0 ]
  set tx_axis_tvalid_0 [ create_bd_pin -dir I tx_axis_tvalid_0 ]
  set rx_axis_tdata0 [ create_bd_pin -dir O -from 63 -to 0 rx_axis_tdata0 ]
  set rx_axis_tdata1 [ create_bd_pin -dir O -from 63 -to 0 rx_axis_tdata1 ]
  set rx_axis_tdata2 [ create_bd_pin -dir O -from 63 -to 0 rx_axis_tdata2 ]
  set rx_axis_tdata3 [ create_bd_pin -dir O -from 63 -to 0 rx_axis_tdata3 ]
  set rx_axis_tdata4 [ create_bd_pin -dir O -from 63 -to 0 rx_axis_tdata4 ]
  set rx_axis_tdata5 [ create_bd_pin -dir O -from 63 -to 0 rx_axis_tdata5 ]
  set rx_axis_tkeep_user0 [ create_bd_pin -dir O -from 10 -to 0 rx_axis_tkeep_user0 ]
  set rx_axis_tkeep_user1 [ create_bd_pin -dir O -from 10 -to 0 rx_axis_tkeep_user1 ]
  set rx_axis_tkeep_user2 [ create_bd_pin -dir O -from 10 -to 0 rx_axis_tkeep_user2 ]
  set rx_axis_tkeep_user3 [ create_bd_pin -dir O -from 10 -to 0 rx_axis_tkeep_user3 ]
  set rx_axis_tkeep_user4 [ create_bd_pin -dir O -from 10 -to 0 rx_axis_tkeep_user4 ]
  set rx_axis_tkeep_user5 [ create_bd_pin -dir O -from 10 -to 0 rx_axis_tkeep_user5 ]
  set rx_axis_tlast_0 [ create_bd_pin -dir O rx_axis_tlast_0 ]
  set rx_axis_tvalid_0 [ create_bd_pin -dir O rx_axis_tvalid_0 ]
  set gt_reset_tx_datapath_in [ create_bd_pin -dir I -from 3 -to 0 gt_reset_tx_datapath_in ]
  set gt_reset_rx_datapath_in [ create_bd_pin -dir I -from 3 -to 0 gt_reset_rx_datapath_in ]
  set pm_rdy [ create_bd_pin -dir O -from 3 -to 0 pm_rdy ]
  set gtpowergood [ create_bd_pin -dir O gtpowergood ]

  set ch0_rxusrclk [ create_bd_pin -dir I -from 0 -to 0 -type gt_usrclk ch0_rxusrclk ]
  set ch0_txusrclk [ create_bd_pin -dir I -from 0 -to 0 -type gt_usrclk ch0_txusrclk ]
  set ch1_rxusrclk [ create_bd_pin -dir I -from 0 -to 0 -type gt_usrclk ch1_rxusrclk ]
  set ch1_txusrclk [ create_bd_pin -dir I -from 0 -to 0 -type gt_usrclk ch1_txusrclk ]
  set ch2_rxusrclk [ create_bd_pin -dir I -from 0 -to 0 -type gt_usrclk ch2_rxusrclk ]
  set ch2_txusrclk [ create_bd_pin -dir I -from 0 -to 0 -type gt_usrclk ch2_txusrclk ]
  set ch3_rxusrclk [ create_bd_pin -dir I -from 0 -to 0 -type gt_usrclk ch3_rxusrclk ]
  set ch3_txusrclk [ create_bd_pin -dir I -from 0 -to 0 -type gt_usrclk ch3_txusrclk ]

  set ch0_loopback [ create_bd_pin -dir I -from 2 -to 0 ch0_loopback ]
  set ch0_txrate [ create_bd_pin -dir I -from 7 -to 0 ch0_txrate ]
  set ch0_rxrate [ create_bd_pin -dir I -from 7 -to 0 ch0_rxrate ]
  set ch1_loopback [ create_bd_pin -dir I -from 2 -to 0 ch1_loopback ]
  set ch1_txrate [ create_bd_pin -dir I -from 7 -to 0 ch1_txrate ]
  set ch1_rxrate [ create_bd_pin -dir I -from 7 -to 0 ch1_rxrate ]
  set ch2_loopback [ create_bd_pin -dir I -from 2 -to 0 ch2_loopback ]
  set ch2_txrate [ create_bd_pin -dir I -from 7 -to 0 ch2_txrate ]
  set ch2_rxrate [ create_bd_pin -dir I -from 7 -to 0 ch2_rxrate ]
  set ch3_loopback [ create_bd_pin -dir I -from 2 -to 0 ch3_loopback ]
  set ch3_txrate [ create_bd_pin -dir I -from 7 -to 0 ch3_txrate ]
  set ch3_rxrate [ create_bd_pin -dir I -from 7 -to 0 ch3_rxrate ]
  set gt_rxn_in_0 [ create_bd_pin -dir I -from 3 -to 0 gt_rxn_in_0 ]
  set gt_rxp_in_0 [ create_bd_pin -dir I -from 3 -to 0 gt_rxp_in_0 ]
  set gt_txn_out_0 [ create_bd_pin -dir O -from 3 -to 0 gt_txn_out_0 ]
  set gt_txp_out_0 [ create_bd_pin -dir O -from 3 -to 0 gt_txp_out_0 ]

  # Create instance: mrmac_0_core, and set properties
  set mrmac_0_core [ create_bd_cell -type ip -vlnv xilinx.com:ip:mrmac:3.1 mrmac_0_core ]
  set_property -dict [list \
    CONFIG.FAST_SIM_MODE {0} \
    CONFIG.FEC_SLICE0_CFG_C0 {FEC Disabled (Bypass)} \
    CONFIG.FEC_SLICE1_CFG_C0 {FEC Disabled (Bypass)} \
    CONFIG.FEC_SLICE2_CFG_C0 {FEC Disabled (Bypass)} \
    CONFIG.FEC_SLICE3_CFG_C0 {FEC Disabled (Bypass)} \
    CONFIG.FLEX_PORT0_DATA_RATE_C0 {100GE} \
    CONFIG.FLEX_PORT1_DATA_RATE_C0 {N/A} \
    CONFIG.FLEX_PORT2_DATA_RATE_C0 {N/A} \
    CONFIG.FLEX_PORT3_DATA_RATE_C0 {N/A} \
    CONFIG.GT_PIPELINE_STAGES {0} \
    CONFIG.GT_REF_CLK_FREQ_C0 {322.265625} \
    CONFIG.GT_TYPE_C0 {GTM} \
    CONFIG.MAC_PORT0_ENABLE_TIME_STAMPING_C0 {0} \
    CONFIG.MAC_PORT0_PREEMPTION_C0 {0} \
    CONFIG.MAC_PORT0_RATE_C0 {100GE} \
    CONFIG.MAC_PORT0_RX_FLOW_C0 {0} \
    CONFIG.MAC_PORT0_TX_FLOW_C0 {0} \
    CONFIG.MAC_PORT1_RATE_C0 {N/A} \
    CONFIG.MAC_PORT2_RATE_C0 {N/A} \
    CONFIG.MAC_PORT3_RATE_C0 {N/A} \
    CONFIG.MRMAC_CLIENTS_C0 {1} \
    CONFIG.MRMAC_CONFIGURATION_TYPE {Static Configuration} \
    CONFIG.MRMAC_DATA_PATH_INTERFACE_PORT0_C0 {Independent 384b Non-Segmented} \
    CONFIG.MRMAC_DATA_PATH_INTERFACE_PORT1_C0 {N/A} \
    CONFIG.MRMAC_DATA_PATH_INTERFACE_PORT2_C0 {N/A} \
    CONFIG.MRMAC_DATA_PATH_INTERFACE_PORT3_C0 {N/A} \
    CONFIG.MRMAC_LOCATION_C0 {MRMAC_X0Y3} \
    CONFIG.MRMAC_MODE_C0 {MAC+PCS} \
    CONFIG.MRMAC_PRESET_C0 {1x100GE CAUI-4 Wide} \
    CONFIG.MRMAC_SPEED_C0 {1x100GE} \
    CONFIG.NUM_GT_CHANNELS {4} \
    CONFIG.PORT0_1588v2_Clocking_C0 {Ordinary/Boundary Clock} \
    CONFIG.PORT0_1588v2_Operation_MODE_C0 {No operation} \
    CONFIG.PORT1_1588v2_Clocking_C0 {Ordinary/Boundary Clock} \
    CONFIG.PORT1_1588v2_Operation_MODE_C0 {No operation} \
    CONFIG.PORT2_1588v2_Clocking_C0 {Ordinary/Boundary Clock} \
    CONFIG.PORT2_1588v2_Operation_MODE_C0 {No operation} \
    CONFIG.PORT3_1588v2_Clocking_C0 {Ordinary/Boundary Clock} \
    CONFIG.PORT3_1588v2_Operation_MODE_C0 {No operation} \
    CONFIG.TIMESTAMP_CLK_PERIOD_NS {4.0000} \
  ] $mrmac_0_core

  # Create instance within hier object: mrmac_0_gt_wrapper
  create_hier_cell_mrmac_0_gt_wrapper $hier_obj mrmac_0_gt_wrapper

  # Create interface connections
  connect_bd_intf_net -intf_net APB3_INTF_1 [get_bd_intf_pins APB3_INTF] [get_bd_intf_pins mrmac_0_gt_wrapper/APB3_INTF]
  connect_bd_intf_net -intf_net CLK_IN_D_1 [get_bd_intf_pins CLK_IN_D] [get_bd_intf_pins mrmac_0_gt_wrapper/CLK_IN_D]
  connect_bd_intf_net -intf_net ctl_tx_pin0_1 [get_bd_intf_pins ctl_tx_port0] [get_bd_intf_pins mrmac_0_core/ctl_tx_port0]
  connect_bd_intf_net -intf_net ctl_tx_pin1_1 [get_bd_intf_pins ctl_tx_port1] [get_bd_intf_pins mrmac_0_core/ctl_tx_port1]
  connect_bd_intf_net -intf_net ctl_tx_pin2_1 [get_bd_intf_pins ctl_tx_port2] [get_bd_intf_pins mrmac_0_core/ctl_tx_port2]
  connect_bd_intf_net -intf_net ctl_tx_pin3_1 [get_bd_intf_pins ctl_tx_port3] [get_bd_intf_pins mrmac_0_core/ctl_tx_port3]
  connect_bd_intf_net -intf_net gt_quad_base_GT_Serial [get_bd_intf_pins mrmac_0_gt_wrapper/GT_Serial] [get_bd_intf_pins GT_Serial]
  connect_bd_intf_net -intf_net mrmac_0_core_gt_rx_serdes_interface_0 [get_bd_intf_pins mrmac_0_core/gtm_rx_serdes_interface_0] [get_bd_intf_pins mrmac_0_gt_wrapper/RX0_GT_IP_Interface]
  connect_bd_intf_net -intf_net mrmac_0_core_gt_rx_serdes_interface_1 [get_bd_intf_pins mrmac_0_core/gtm_rx_serdes_interface_1] [get_bd_intf_pins mrmac_0_gt_wrapper/RX1_GT_IP_Interface]
  connect_bd_intf_net -intf_net mrmac_0_core_gt_rx_serdes_interface_2 [get_bd_intf_pins mrmac_0_core/gtm_rx_serdes_interface_2] [get_bd_intf_pins mrmac_0_gt_wrapper/RX2_GT_IP_Interface]
  connect_bd_intf_net -intf_net mrmac_0_core_gt_rx_serdes_interface_3 [get_bd_intf_pins mrmac_0_core/gtm_rx_serdes_interface_3] [get_bd_intf_pins mrmac_0_gt_wrapper/RX3_GT_IP_Interface]
  connect_bd_intf_net -intf_net mrmac_0_core_gt_tx_serdes_interface_0 [get_bd_intf_pins mrmac_0_core/gtm_tx_serdes_interface_0] [get_bd_intf_pins mrmac_0_gt_wrapper/TX0_GT_IP_Interface]
  connect_bd_intf_net -intf_net mrmac_0_core_gt_tx_serdes_interface_1 [get_bd_intf_pins mrmac_0_core/gtm_tx_serdes_interface_1] [get_bd_intf_pins mrmac_0_gt_wrapper/TX1_GT_IP_Interface]
  connect_bd_intf_net -intf_net mrmac_0_core_gt_tx_serdes_interface_2 [get_bd_intf_pins mrmac_0_core/gtm_tx_serdes_interface_2] [get_bd_intf_pins mrmac_0_gt_wrapper/TX2_GT_IP_Interface]
  connect_bd_intf_net -intf_net mrmac_0_core_gt_tx_serdes_interface_3 [get_bd_intf_pins mrmac_0_core/gtm_tx_serdes_interface_3] [get_bd_intf_pins mrmac_0_gt_wrapper/TX3_GT_IP_Interface]
  connect_bd_intf_net -intf_net mrmac_0_core_rx_preambleout [get_bd_intf_pins rx_preambleout] [get_bd_intf_pins mrmac_0_core/rx_preambleout]
  connect_bd_intf_net -intf_net mrmac_0_core_stat_rx_pin0 [get_bd_intf_pins stat_rx_port0] [get_bd_intf_pins mrmac_0_core/stat_rx_port0]
  connect_bd_intf_net -intf_net mrmac_0_core_stat_rx_pin1 [get_bd_intf_pins stat_rx_port1] [get_bd_intf_pins mrmac_0_core/stat_rx_port1]
  connect_bd_intf_net -intf_net mrmac_0_core_stat_rx_pin2 [get_bd_intf_pins stat_rx_port2] [get_bd_intf_pins mrmac_0_core/stat_rx_port2]
  connect_bd_intf_net -intf_net mrmac_0_core_stat_rx_pin3 [get_bd_intf_pins stat_rx_port3] [get_bd_intf_pins mrmac_0_core/stat_rx_port3]
  connect_bd_intf_net -intf_net mrmac_0_core_stat_tx_pin0 [get_bd_intf_pins stat_tx_port0] [get_bd_intf_pins mrmac_0_core/stat_tx_port0]
  connect_bd_intf_net -intf_net mrmac_0_core_stat_tx_pin1 [get_bd_intf_pins stat_tx_port1] [get_bd_intf_pins mrmac_0_core/stat_tx_port1]
  connect_bd_intf_net -intf_net mrmac_0_core_stat_tx_pin2 [get_bd_intf_pins stat_tx_port2] [get_bd_intf_pins mrmac_0_core/stat_tx_port2]
  connect_bd_intf_net -intf_net mrmac_0_core_stat_tx_pin3 [get_bd_intf_pins stat_tx_port3] [get_bd_intf_pins mrmac_0_core/stat_tx_port3]
  connect_bd_intf_net -intf_net s_axi_1 [get_bd_intf_pins s_axi] [get_bd_intf_pins mrmac_0_core/s_axi]
  connect_bd_intf_net -intf_net tx_preamblein_1 [get_bd_intf_pins tx_preamblein] [get_bd_intf_pins mrmac_0_core/tx_preamblein]

  # Create pin connections
  connect_bd_net -net apb3clk_quad_1  [get_bd_pins apb3clk_quad] [get_bd_pins mrmac_0_gt_wrapper/apb3clk_quad]
  connect_bd_net -net ch0_loopback_1  [get_bd_pins ch0_loopback] [get_bd_pins mrmac_0_gt_wrapper/ch0_loopback]
  connect_bd_net -net ch0_rxrate_1  [get_bd_pins ch0_rxrate] [get_bd_pins mrmac_0_gt_wrapper/ch0_rxrate]
  connect_bd_net -net ch0_rxusrclk_1  [get_bd_pins ch0_rxusrclk] [get_bd_pins mrmac_0_gt_wrapper/ch0_rxusrclk]
  connect_bd_net -net ch0_txrate_1  [get_bd_pins ch0_txrate] [get_bd_pins mrmac_0_gt_wrapper/ch0_txrate]
  connect_bd_net -net ch0_txusrclk_1  [get_bd_pins ch0_txusrclk] [get_bd_pins mrmac_0_gt_wrapper/ch0_txusrclk]
  connect_bd_net -net ch1_loopback_1  [get_bd_pins ch1_loopback] [get_bd_pins mrmac_0_gt_wrapper/ch1_loopback]
  connect_bd_net -net ch1_rxrate_1  [get_bd_pins ch1_rxrate] [get_bd_pins mrmac_0_gt_wrapper/ch1_rxrate]
  connect_bd_net -net ch1_rxusrclk_1  [get_bd_pins ch1_rxusrclk] [get_bd_pins mrmac_0_gt_wrapper/ch1_rxusrclk]
  connect_bd_net -net ch1_txrate_1  [get_bd_pins ch1_txrate] [get_bd_pins mrmac_0_gt_wrapper/ch1_txrate]
  connect_bd_net -net ch1_txusrclk_1  [get_bd_pins ch1_txusrclk] [get_bd_pins mrmac_0_gt_wrapper/ch1_txusrclk]
  connect_bd_net -net ch2_loopback_1  [get_bd_pins ch2_loopback] [get_bd_pins mrmac_0_gt_wrapper/ch2_loopback]
  connect_bd_net -net ch2_rxrate_1  [get_bd_pins ch2_rxrate] [get_bd_pins mrmac_0_gt_wrapper/ch2_rxrate]
  connect_bd_net -net ch2_rxusrclk_1  [get_bd_pins ch2_rxusrclk] [get_bd_pins mrmac_0_gt_wrapper/ch2_rxusrclk]
  connect_bd_net -net ch2_txrate_1  [get_bd_pins ch2_txrate] [get_bd_pins mrmac_0_gt_wrapper/ch2_txrate]
  connect_bd_net -net ch2_txusrclk_1  [get_bd_pins ch2_txusrclk] [get_bd_pins mrmac_0_gt_wrapper/ch2_txusrclk]
  connect_bd_net -net ch3_loopback_1  [get_bd_pins ch3_loopback] [get_bd_pins mrmac_0_gt_wrapper/ch3_loopback]
  connect_bd_net -net ch3_rxrate_1  [get_bd_pins ch3_rxrate] [get_bd_pins mrmac_0_gt_wrapper/ch3_rxrate]
  connect_bd_net -net ch3_rxusrclk_1  [get_bd_pins ch3_rxusrclk] [get_bd_pins mrmac_0_gt_wrapper/ch3_rxusrclk]
  connect_bd_net -net ch3_txrate_1  [get_bd_pins ch3_txrate] [get_bd_pins mrmac_0_gt_wrapper/ch3_txrate]
  connect_bd_net -net ch3_txusrclk_1  [get_bd_pins ch3_txusrclk] [get_bd_pins mrmac_0_gt_wrapper/ch3_txusrclk]
  connect_bd_net -net gt_quad_base_gtpowergood  [get_bd_pins mrmac_0_gt_wrapper/gtpowergood] [get_bd_pins gtpowergood]
  connect_bd_net -net gt_quad_base_txn  [get_bd_pins mrmac_0_gt_wrapper/gt_txn_out_0] [get_bd_pins gt_txn_out_0]
  connect_bd_net -net gt_quad_base_txp  [get_bd_pins mrmac_0_gt_wrapper/gt_txp_out_0] [get_bd_pins gt_txp_out_0]
  connect_bd_net -net gt_reset_all_in_1  [get_bd_pins gt_reset_all_in] [get_bd_pins mrmac_0_core/gt_reset_all_in]
  connect_bd_net -net gt_reset_rx_datapath_in_1  [get_bd_pins gt_reset_rx_datapath_in] [get_bd_pins mrmac_0_core/gt_reset_rx_datapath_in]
  connect_bd_net -net gt_reset_tx_datapath_in_1  [get_bd_pins gt_reset_tx_datapath_in] [get_bd_pins mrmac_0_core/gt_reset_tx_datapath_in]
  connect_bd_net -net gt_rxn_in_0_1  [get_bd_pins gt_rxn_in_0] [get_bd_pins mrmac_0_gt_wrapper/gt_rxn_in_0]
  connect_bd_net -net gt_rxp_in_0_1  [get_bd_pins gt_rxp_in_0] [get_bd_pins mrmac_0_gt_wrapper/gt_rxp_in_0]
  connect_bd_net -net gtpowergood_in_1  [get_bd_pins gtpowergood_in] [get_bd_pins mrmac_0_core/gtpowergood_in]
  connect_bd_net -net mbufg_gt_0_MBUFG_GT_O1  [get_bd_pins mrmac_0_gt_wrapper/ch0_tx_usr_clk] [get_bd_pins ch0_tx_usr_clk]
  connect_bd_net -net mbufg_gt_0_MBUFG_GT_O2  [get_bd_pins mrmac_0_gt_wrapper/ch0_tx_usr_clk2] [get_bd_pins ch0_tx_usr_clk2]
  connect_bd_net -net mbufg_gt_1_1_MBUFG_GT_O1  [get_bd_pins mrmac_0_gt_wrapper/ch1_rx_usr_clk] [get_bd_pins ch1_rx_usr_clk]
  connect_bd_net -net mbufg_gt_1_1_MBUFG_GT_O2  [get_bd_pins mrmac_0_gt_wrapper/ch1_rx_usr_clk2] [get_bd_pins ch1_rx_usr_clk2]
  connect_bd_net -net mbufg_gt_1_2_MBUFG_GT_O1  [get_bd_pins mrmac_0_gt_wrapper/ch2_rx_usr_clk] [get_bd_pins ch2_rx_usr_clk]
  connect_bd_net -net mbufg_gt_1_2_MBUFG_GT_O2  [get_bd_pins mrmac_0_gt_wrapper/ch2_rx_usr_clk2] [get_bd_pins ch2_rx_usr_clk2]
  connect_bd_net -net mbufg_gt_1_3_MBUFG_GT_O1  [get_bd_pins mrmac_0_gt_wrapper/ch3_rx_usr_clk] [get_bd_pins ch3_rx_usr_clk]
  connect_bd_net -net mbufg_gt_1_3_MBUFG_GT_O2  [get_bd_pins mrmac_0_gt_wrapper/ch3_rx_usr_clk2] [get_bd_pins ch3_rx_usr_clk2]
  connect_bd_net -net mbufg_gt_1_MBUFG_GT_O1  [get_bd_pins mrmac_0_gt_wrapper/ch0_rx_usr_clk] [get_bd_pins ch0_rx_usr_clk]
  connect_bd_net -net mbufg_gt_1_MBUFG_GT_O2  [get_bd_pins mrmac_0_gt_wrapper/ch0_rx_usr_clk2] [get_bd_pins ch0_rx_usr_clk2]
  connect_bd_net -net mrmac_0_core_gt_rx_reset_done_out  [get_bd_pins mrmac_0_core/gt_rx_reset_done_out] [get_bd_pins gt_rx_reset_done_out]
  connect_bd_net -net mrmac_0_core_gt_tx_reset_done_out  [get_bd_pins mrmac_0_core/gt_tx_reset_done_out] [get_bd_pins gt_tx_reset_done_out]
  connect_bd_net -net mrmac_0_core_pm_rdy  [get_bd_pins mrmac_0_core/pm_rdy] [get_bd_pins pm_rdy]
  connect_bd_net -net mrmac_0_core_rx_axis_tdata0  [get_bd_pins mrmac_0_core/rx_axis_tdata0] [get_bd_pins rx_axis_tdata0]
  connect_bd_net -net mrmac_0_core_rx_axis_tdata1  [get_bd_pins mrmac_0_core/rx_axis_tdata1] [get_bd_pins rx_axis_tdata1]
  connect_bd_net -net mrmac_0_core_rx_axis_tdata2  [get_bd_pins mrmac_0_core/rx_axis_tdata2] [get_bd_pins rx_axis_tdata2]
  connect_bd_net -net mrmac_0_core_rx_axis_tdata3  [get_bd_pins mrmac_0_core/rx_axis_tdata3] [get_bd_pins rx_axis_tdata3]
  connect_bd_net -net mrmac_0_core_rx_axis_tdata4  [get_bd_pins mrmac_0_core/rx_axis_tdata4] [get_bd_pins rx_axis_tdata4]
  connect_bd_net -net mrmac_0_core_rx_axis_tdata5  [get_bd_pins mrmac_0_core/rx_axis_tdata5] [get_bd_pins rx_axis_tdata5]
  connect_bd_net -net mrmac_0_core_rx_axis_tkeep_user0  [get_bd_pins mrmac_0_core/rx_axis_tkeep_user0] [get_bd_pins rx_axis_tkeep_user0]
  connect_bd_net -net mrmac_0_core_rx_axis_tkeep_user1  [get_bd_pins mrmac_0_core/rx_axis_tkeep_user1] [get_bd_pins rx_axis_tkeep_user1]
  connect_bd_net -net mrmac_0_core_rx_axis_tkeep_user2  [get_bd_pins mrmac_0_core/rx_axis_tkeep_user2] [get_bd_pins rx_axis_tkeep_user2]
  connect_bd_net -net mrmac_0_core_rx_axis_tkeep_user3  [get_bd_pins mrmac_0_core/rx_axis_tkeep_user3] [get_bd_pins rx_axis_tkeep_user3]
  connect_bd_net -net mrmac_0_core_rx_axis_tkeep_user4  [get_bd_pins mrmac_0_core/rx_axis_tkeep_user4] [get_bd_pins rx_axis_tkeep_user4]
  connect_bd_net -net mrmac_0_core_rx_axis_tkeep_user5  [get_bd_pins mrmac_0_core/rx_axis_tkeep_user5] [get_bd_pins rx_axis_tkeep_user5]
  connect_bd_net -net mrmac_0_core_rx_axis_tlast_0  [get_bd_pins mrmac_0_core/rx_axis_tlast_0] [get_bd_pins rx_axis_tlast_0]
  connect_bd_net -net mrmac_0_core_rx_axis_tvalid_0  [get_bd_pins mrmac_0_core/rx_axis_tvalid_0] [get_bd_pins rx_axis_tvalid_0]
  connect_bd_net -net mrmac_0_core_rx_clr_out_0  [get_bd_pins mrmac_0_core/rx_clr_out_0] [get_bd_pins mrmac_0_gt_wrapper/MBUFG_GT_CLR1]
  connect_bd_net -net mrmac_0_core_rx_clr_out_1  [get_bd_pins mrmac_0_core/rx_clr_out_1] [get_bd_pins mrmac_0_gt_wrapper/MBUFG_GT_CLR2]
  connect_bd_net -net mrmac_0_core_rx_clr_out_2  [get_bd_pins mrmac_0_core/rx_clr_out_2] [get_bd_pins mrmac_0_gt_wrapper/MBUFG_GT_CLR3]
  connect_bd_net -net mrmac_0_core_rx_clr_out_3  [get_bd_pins mrmac_0_core/rx_clr_out_3] [get_bd_pins mrmac_0_gt_wrapper/MBUFG_GT_CLR4]
  connect_bd_net -net mrmac_0_core_rx_clrb_leaf_out_0  [get_bd_pins mrmac_0_core/rx_clrb_leaf_out_0] [get_bd_pins mrmac_0_gt_wrapper/MBUFG_GT_CLRB_LEAF1]
  connect_bd_net -net mrmac_0_core_rx_clrb_leaf_out_1  [get_bd_pins mrmac_0_core/rx_clrb_leaf_out_1] [get_bd_pins mrmac_0_gt_wrapper/MBUFG_GT_CLRB_LEAF2]
  connect_bd_net -net mrmac_0_core_rx_clrb_leaf_out_2  [get_bd_pins mrmac_0_core/rx_clrb_leaf_out_2] [get_bd_pins mrmac_0_gt_wrapper/MBUFG_GT_CLRB_LEAF3]
  connect_bd_net -net mrmac_0_core_rx_clrb_leaf_out_3  [get_bd_pins mrmac_0_core/rx_clrb_leaf_out_3] [get_bd_pins mrmac_0_gt_wrapper/MBUFG_GT_CLRB_LEAF4]
  connect_bd_net -net mrmac_0_core_tx_axis_tready_0  [get_bd_pins mrmac_0_core/tx_axis_tready_0] [get_bd_pins tx_axis_tready_0]
  connect_bd_net -net mrmac_0_core_tx_clr_out_0  [get_bd_pins mrmac_0_core/tx_clr_out_0] [get_bd_pins mrmac_0_gt_wrapper/MBUFG_GT_CLR]
  connect_bd_net -net mrmac_0_core_tx_clrb_leaf_out_0  [get_bd_pins mrmac_0_core/tx_clrb_leaf_out_0] [get_bd_pins mrmac_0_gt_wrapper/MBUFG_GT_CLRB_LEAF]
  connect_bd_net -net pm_tick_1  [get_bd_pins pm_tick] [get_bd_pins mrmac_0_core/pm_tick]
  connect_bd_net -net rx_alt_serdes_clk_1  [get_bd_pins rx_alt_serdes_clk] [get_bd_pins mrmac_0_core/rx_alt_serdes_clk]
  connect_bd_net -net rx_axi_clk_1  [get_bd_pins rx_axi_clk] [get_bd_pins mrmac_0_core/rx_axi_clk]
  connect_bd_net -net rx_core_clk_1  [get_bd_pins rx_core_clk] [get_bd_pins mrmac_0_core/rx_core_clk]
  connect_bd_net -net rx_core_reset_1  [get_bd_pins rx_core_reset] [get_bd_pins mrmac_0_core/rx_core_reset]
  connect_bd_net -net rx_flexif_clk_1  [get_bd_pins rx_flexif_clk] [get_bd_pins mrmac_0_core/rx_flexif_clk]
  connect_bd_net -net rx_flexif_reset_1  [get_bd_pins rx_flexif_reset] [get_bd_pins mrmac_0_core/rx_flexif_reset]
  connect_bd_net -net rx_serdes_clk_1  [get_bd_pins rx_serdes_clk] [get_bd_pins mrmac_0_core/rx_serdes_clk]
  connect_bd_net -net rx_serdes_reset_1  [get_bd_pins rx_serdes_reset] [get_bd_pins mrmac_0_core/rx_serdes_reset]
  connect_bd_net -net rx_ts_clk_1  [get_bd_pins rx_ts_clk] [get_bd_pins mrmac_0_core/rx_ts_clk]
  connect_bd_net -net s_axi_aclk_1  [get_bd_pins s_axi_aclk] [get_bd_pins mrmac_0_core/s_axi_aclk]
  connect_bd_net -net s_axi_aresetn_1  [get_bd_pins s_axi_aresetn] [get_bd_pins mrmac_0_core/s_axi_aresetn] [get_bd_pins mrmac_0_gt_wrapper/s_axi_aresetn]
  connect_bd_net -net tx_alt_serdes_clk_1  [get_bd_pins tx_alt_serdes_clk] [get_bd_pins mrmac_0_core/tx_alt_serdes_clk]
  connect_bd_net -net tx_axi_clk_1  [get_bd_pins tx_axi_clk] [get_bd_pins mrmac_0_core/tx_axi_clk]
  connect_bd_net -net tx_axis_tdata0_1  [get_bd_pins tx_axis_tdata0] [get_bd_pins mrmac_0_core/tx_axis_tdata0]
  connect_bd_net -net tx_axis_tdata1_1  [get_bd_pins tx_axis_tdata1] [get_bd_pins mrmac_0_core/tx_axis_tdata1]
  connect_bd_net -net tx_axis_tdata2_1  [get_bd_pins tx_axis_tdata2] [get_bd_pins mrmac_0_core/tx_axis_tdata2]
  connect_bd_net -net tx_axis_tdata3_1  [get_bd_pins tx_axis_tdata3] [get_bd_pins mrmac_0_core/tx_axis_tdata3]
  connect_bd_net -net tx_axis_tdata4_1  [get_bd_pins tx_axis_tdata4] [get_bd_pins mrmac_0_core/tx_axis_tdata4]
  connect_bd_net -net tx_axis_tdata5_1  [get_bd_pins tx_axis_tdata5] [get_bd_pins mrmac_0_core/tx_axis_tdata5]
  connect_bd_net -net tx_axis_tkeep_user0_1  [get_bd_pins tx_axis_tkeep_user0] [get_bd_pins mrmac_0_core/tx_axis_tkeep_user0]
  connect_bd_net -net tx_axis_tkeep_user1_1  [get_bd_pins tx_axis_tkeep_user1] [get_bd_pins mrmac_0_core/tx_axis_tkeep_user1]
  connect_bd_net -net tx_axis_tkeep_user2_1  [get_bd_pins tx_axis_tkeep_user2] [get_bd_pins mrmac_0_core/tx_axis_tkeep_user2]
  connect_bd_net -net tx_axis_tkeep_user3_1  [get_bd_pins tx_axis_tkeep_user3] [get_bd_pins mrmac_0_core/tx_axis_tkeep_user3]
  connect_bd_net -net tx_axis_tkeep_user4_1  [get_bd_pins tx_axis_tkeep_user4] [get_bd_pins mrmac_0_core/tx_axis_tkeep_user4]
  connect_bd_net -net tx_axis_tkeep_user5_1  [get_bd_pins tx_axis_tkeep_user5] [get_bd_pins mrmac_0_core/tx_axis_tkeep_user5]
  connect_bd_net -net tx_axis_tlast_0_1  [get_bd_pins tx_axis_tlast_0] [get_bd_pins mrmac_0_core/tx_axis_tlast_0]
  connect_bd_net -net tx_axis_tvalid_0_1  [get_bd_pins tx_axis_tvalid_0] [get_bd_pins mrmac_0_core/tx_axis_tvalid_0]
  connect_bd_net -net tx_core_clk_1  [get_bd_pins tx_core_clk] [get_bd_pins mrmac_0_core/tx_core_clk]
  connect_bd_net -net tx_core_reset_1  [get_bd_pins tx_core_reset] [get_bd_pins mrmac_0_core/tx_core_reset]
  connect_bd_net -net tx_flexif_clk_1  [get_bd_pins tx_flexif_clk] [get_bd_pins mrmac_0_core/tx_flexif_clk]
  connect_bd_net -net tx_serdes_reset_1  [get_bd_pins tx_serdes_reset] [get_bd_pins mrmac_0_core/tx_serdes_reset]
  connect_bd_net -net tx_ts_clk_1  [get_bd_pins tx_ts_clk] [get_bd_pins mrmac_0_core/tx_ts_clk]

  # Restore current instance
  current_bd_instance $oldCurInst
}
