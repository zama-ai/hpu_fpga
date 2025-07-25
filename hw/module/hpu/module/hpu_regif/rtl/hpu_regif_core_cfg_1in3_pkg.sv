// ============================================================================================== //
// Description  : register  map address definition package
// This file was generated with rust regmap generator:
//  * Date:  2025-07-17
//  * Tool_version: bb0db737792da6b81e69a039028c971af1627fe2
// ---------------------------------------------------------------------------------------------- //
//
// Should only be used in testbench to drive the register interface
// ============================================================================================== //
package hpu_regif_core_cfg_1in3_pkg;
  localparam int ENTRY_CFG_1IN3_DUMMY_VAL0_OFS = 'h0;
  localparam int ENTRY_CFG_1IN3_DUMMY_VAL1_OFS = 'h4;
  localparam int ENTRY_CFG_1IN3_DUMMY_VAL2_OFS = 'h8;
  localparam int ENTRY_CFG_1IN3_DUMMY_VAL3_OFS = 'hc;
  typedef struct packed {
    logic [(24-1):0] padding_8;
    logic [(4-1):0] minor;
    logic [(4-1):0] major;
   } info_version_t;
  localparam int INFO_VERSION_OFS = 'h10;
  localparam int INFO_NTT_ARCHITECTURE_OFS = 'h14;
  typedef struct packed {
    logic [(8-1):0] delta;
    logic [(8-1):0] div;
    logic [(8-1):0] psi;
    logic [(8-1):0] radix;
   } info_ntt_structure_t;
  localparam int INFO_NTT_STRUCTURE_OFS = 'h18;
  typedef struct packed {
    logic [(4-1):0] radix_cut7;
    logic [(4-1):0] radix_cut6;
    logic [(4-1):0] radix_cut5;
    logic [(4-1):0] radix_cut4;
    logic [(4-1):0] radix_cut3;
    logic [(4-1):0] radix_cut2;
    logic [(4-1):0] radix_cut1;
    logic [(4-1):0] radix_cut0;
   } info_ntt_rdx_cut_t;
  localparam int INFO_NTT_RDX_CUT_OFS = 'h1c;
  typedef struct packed {
    logic [(16-1):0] padding_16;
    logic [(8-1):0] total_pbs_nb;
    logic [(8-1):0] batch_pbs_nb;
   } info_ntt_pbs_t;
  localparam int INFO_NTT_PBS_OFS = 'h20;
  localparam int INFO_NTT_MODULO_OFS = 'h24;
  localparam int INFO_APPLICATION_OFS = 'h28;
  typedef struct packed {
    logic [(8-1):0] padding_24;
    logic [(8-1):0] z;
    logic [(8-1):0] y;
    logic [(8-1):0] x;
   } info_ks_structure_t;
  localparam int INFO_KS_STRUCTURE_OFS = 'h2c;
  typedef struct packed {
    logic [(8-1):0] padding_24;
    logic [(8-1):0] ks_b;
    logic [(8-1):0] ks_l;
    logic [(8-1):0] mod_ksk_w;
   } info_ks_crypto_param_t;
  localparam int INFO_KS_CRYPTO_PARAM_OFS = 'h30;
  typedef struct packed {
    logic [(16-1):0] padding_16;
    logic [(8-1):0] coef_nb;
    logic [(8-1):0] reg_nb;
   } info_regf_structure_t;
  localparam int INFO_REGF_STRUCTURE_OFS = 'h34;
  typedef struct packed {
    logic [(16-1):0] padding_16;
    logic [(8-1):0] min_iop_size;
    logic [(8-1):0] depth;
   } info_isc_structure_t;
  localparam int INFO_ISC_STRUCTURE_OFS = 'h38;
  typedef struct packed {
    logic [(8-1):0] alu_nb;
    logic [(8-1):0] pep_regf_period;
    logic [(8-1):0] pem_regf_period;
    logic [(8-1):0] pea_regf_period;
   } info_pe_properties_t;
  localparam int INFO_PE_PROPERTIES_OFS = 'h3c;
  typedef struct packed {
    logic [(16-1):0] padding_16;
    logic [(8-1):0] bsk_cut_nb;
    logic [(8-1):0] padding_0;
   } info_bsk_structure_t;
  localparam int INFO_BSK_STRUCTURE_OFS = 'h40;
  typedef struct packed {
    logic [(16-1):0] padding_16;
    logic [(8-1):0] ksk_cut_nb;
    logic [(8-1):0] padding_0;
   } info_ksk_structure_t;
  localparam int INFO_KSK_STRUCTURE_OFS = 'h44;
  typedef struct packed {
    logic [(8-1):0] glwe_pc;
    logic [(8-1):0] pem_pc;
    logic [(8-1):0] ksk_pc;
    logic [(8-1):0] bsk_pc;
   } info_hbm_axi4_nb_t;
  localparam int INFO_HBM_AXI4_NB_OFS = 'h48;
  localparam int INFO_HBM_AXI4_DATAW_PEM_OFS = 'h4c;
  localparam int INFO_HBM_AXI4_DATAW_GLWE_OFS = 'h50;
  localparam int INFO_HBM_AXI4_DATAW_BSK_OFS = 'h54;
  localparam int INFO_HBM_AXI4_DATAW_KSK_OFS = 'h58;
  localparam int HBM_AXI4_ADDR_1IN3_CT_PC0_LSB_OFS = 'h1000;
  localparam int HBM_AXI4_ADDR_1IN3_CT_PC0_MSB_OFS = 'h1004;
  localparam int HBM_AXI4_ADDR_1IN3_CT_PC1_LSB_OFS = 'h1008;
  localparam int HBM_AXI4_ADDR_1IN3_CT_PC1_MSB_OFS = 'h100c;
  localparam int HBM_AXI4_ADDR_1IN3_GLWE_PC0_LSB_OFS = 'h1010;
  localparam int HBM_AXI4_ADDR_1IN3_GLWE_PC0_MSB_OFS = 'h1014;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC0_LSB_OFS = 'h1018;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC0_MSB_OFS = 'h101c;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC1_LSB_OFS = 'h1020;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC1_MSB_OFS = 'h1024;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC2_LSB_OFS = 'h1028;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC2_MSB_OFS = 'h102c;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC3_LSB_OFS = 'h1030;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC3_MSB_OFS = 'h1034;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC4_LSB_OFS = 'h1038;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC4_MSB_OFS = 'h103c;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC5_LSB_OFS = 'h1040;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC5_MSB_OFS = 'h1044;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC6_LSB_OFS = 'h1048;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC6_MSB_OFS = 'h104c;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC7_LSB_OFS = 'h1050;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC7_MSB_OFS = 'h1054;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC8_LSB_OFS = 'h1058;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC8_MSB_OFS = 'h105c;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC9_LSB_OFS = 'h1060;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC9_MSB_OFS = 'h1064;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC10_LSB_OFS = 'h1068;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC10_MSB_OFS = 'h106c;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC11_LSB_OFS = 'h1070;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC11_MSB_OFS = 'h1074;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC12_LSB_OFS = 'h1078;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC12_MSB_OFS = 'h107c;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC13_LSB_OFS = 'h1080;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC13_MSB_OFS = 'h1084;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC14_LSB_OFS = 'h1088;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC14_MSB_OFS = 'h108c;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC15_LSB_OFS = 'h1090;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC15_MSB_OFS = 'h1094;
  localparam int HBM_AXI4_ADDR_1IN3_TRC_PC0_LSB_OFS = 'h1098;
  localparam int HBM_AXI4_ADDR_1IN3_TRC_PC0_MSB_OFS = 'h109c;
  typedef struct packed {
    logic [(30-1):0] padding_2;
    logic [(1-1):0] use_opportunism;
    logic [(1-1):0] use_bpip;
   } bpip_use_t;
  localparam int BPIP_USE_OFS = 'h2000;
  localparam int BPIP_TIMEOUT_OFS = 'h2004;
  typedef struct packed {
    logic [(31-1):0] padding_1;
    logic [(1-1):0] mod_switch_mean_comp;
   } keyswitch_config_t;
  localparam int KEYSWITCH_CONFIG_OFS = 'h3000;
endpackage
