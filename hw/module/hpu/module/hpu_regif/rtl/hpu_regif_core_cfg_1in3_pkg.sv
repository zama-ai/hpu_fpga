// ============================================================================================== //
// Description  : register  map address definition package
// This file was generated with rust regmap generator:
//  * Date:  2025-09-30
//  * Tool_version: bb0db737792da6b81e69a039028c971af1627fe2
// ---------------------------------------------------------------------------------------------- //
//
// Should only be used in testbench to drive the register interface
// ============================================================================================== //
package hpu_regif_core_cfg_1in3_pkg;
  localparam int ENTRY_CFG_1IN3_DUMMY_VAL0_OFS = 'h80000;
  localparam int ENTRY_CFG_1IN3_DUMMY_VAL1_OFS = 'h80004;
  localparam int ENTRY_CFG_1IN3_DUMMY_VAL2_OFS = 'h80008;
  localparam int ENTRY_CFG_1IN3_DUMMY_VAL3_OFS = 'h8000c;
  typedef struct packed {
    logic [(24-1):0] padding_8;
    logic [(4-1):0] minor;
    logic [(4-1):0] major;
   } info_version_t;
  localparam int INFO_VERSION_OFS = 'h80010;
  localparam int INFO_NTT_ARCHITECTURE_OFS = 'h80014;
  typedef struct packed {
    logic [(8-1):0] delta;
    logic [(8-1):0] div;
    logic [(8-1):0] psi;
    logic [(8-1):0] radix;
   } info_ntt_structure_t;
  localparam int INFO_NTT_STRUCTURE_OFS = 'h80018;
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
  localparam int INFO_NTT_RDX_CUT_OFS = 'h8001c;
  typedef struct packed {
    logic [(16-1):0] padding_16;
    logic [(8-1):0] total_pbs_nb;
    logic [(8-1):0] batch_pbs_nb;
   } info_ntt_pbs_t;
  localparam int INFO_NTT_PBS_OFS = 'h80020;
  localparam int INFO_NTT_MODULO_OFS = 'h80024;
  localparam int INFO_APPLICATION_OFS = 'h80028;
  typedef struct packed {
    logic [(8-1):0] padding_24;
    logic [(8-1):0] z;
    logic [(8-1):0] y;
    logic [(8-1):0] x;
   } info_ks_structure_t;
  localparam int INFO_KS_STRUCTURE_OFS = 'h8002c;
  typedef struct packed {
    logic [(8-1):0] padding_24;
    logic [(8-1):0] ks_b;
    logic [(8-1):0] ks_l;
    logic [(8-1):0] mod_ksk_w;
   } info_ks_crypto_param_t;
  localparam int INFO_KS_CRYPTO_PARAM_OFS = 'h80030;
  typedef struct packed {
    logic [(16-1):0] padding_16;
    logic [(8-1):0] coef_nb;
    logic [(8-1):0] reg_nb;
   } info_regf_structure_t;
  localparam int INFO_REGF_STRUCTURE_OFS = 'h80034;
  typedef struct packed {
    logic [(16-1):0] padding_16;
    logic [(8-1):0] min_iop_size;
    logic [(8-1):0] depth;
   } info_isc_structure_t;
  localparam int INFO_ISC_STRUCTURE_OFS = 'h80038;
  typedef struct packed {
    logic [(8-1):0] alu_nb;
    logic [(8-1):0] pep_regf_period;
    logic [(8-1):0] pem_regf_period;
    logic [(8-1):0] pea_regf_period;
   } info_pe_properties_t;
  localparam int INFO_PE_PROPERTIES_OFS = 'h8003c;
  typedef struct packed {
    logic [(16-1):0] padding_16;
    logic [(8-1):0] bsk_cut_nb;
    logic [(8-1):0] padding_0;
   } info_bsk_structure_t;
  localparam int INFO_BSK_STRUCTURE_OFS = 'h80040;
  typedef struct packed {
    logic [(16-1):0] padding_16;
    logic [(8-1):0] ksk_cut_nb;
    logic [(8-1):0] padding_0;
   } info_ksk_structure_t;
  localparam int INFO_KSK_STRUCTURE_OFS = 'h80044;
  typedef struct packed {
    logic [(8-1):0] glwe_pc;
    logic [(8-1):0] pem_pc;
    logic [(8-1):0] ksk_pc;
    logic [(8-1):0] bsk_pc;
   } info_hbm_axi4_nb_t;
  localparam int INFO_HBM_AXI4_NB_OFS = 'h80048;
  localparam int INFO_HBM_AXI4_DATAW_PEM_OFS = 'h8004c;
  localparam int INFO_HBM_AXI4_DATAW_GLWE_OFS = 'h80050;
  localparam int INFO_HBM_AXI4_DATAW_BSK_OFS = 'h80054;
  localparam int INFO_HBM_AXI4_DATAW_KSK_OFS = 'h80058;
  localparam int HBM_AXI4_ADDR_1IN3_CT_PC0_LSB_OFS = 'h81000;
  localparam int HBM_AXI4_ADDR_1IN3_CT_PC0_MSB_OFS = 'h81004;
  localparam int HBM_AXI4_ADDR_1IN3_CT_PC1_LSB_OFS = 'h81008;
  localparam int HBM_AXI4_ADDR_1IN3_CT_PC1_MSB_OFS = 'h8100c;
  localparam int HBM_AXI4_ADDR_1IN3_GLWE_PC0_LSB_OFS = 'h81010;
  localparam int HBM_AXI4_ADDR_1IN3_GLWE_PC0_MSB_OFS = 'h81014;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC0_LSB_OFS = 'h81018;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC0_MSB_OFS = 'h8101c;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC1_LSB_OFS = 'h81020;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC1_MSB_OFS = 'h81024;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC2_LSB_OFS = 'h81028;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC2_MSB_OFS = 'h8102c;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC3_LSB_OFS = 'h81030;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC3_MSB_OFS = 'h81034;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC4_LSB_OFS = 'h81038;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC4_MSB_OFS = 'h8103c;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC5_LSB_OFS = 'h81040;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC5_MSB_OFS = 'h81044;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC6_LSB_OFS = 'h81048;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC6_MSB_OFS = 'h8104c;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC7_LSB_OFS = 'h81050;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC7_MSB_OFS = 'h81054;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC8_LSB_OFS = 'h81058;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC8_MSB_OFS = 'h8105c;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC9_LSB_OFS = 'h81060;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC9_MSB_OFS = 'h81064;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC10_LSB_OFS = 'h81068;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC10_MSB_OFS = 'h8106c;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC11_LSB_OFS = 'h81070;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC11_MSB_OFS = 'h81074;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC12_LSB_OFS = 'h81078;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC12_MSB_OFS = 'h8107c;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC13_LSB_OFS = 'h81080;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC13_MSB_OFS = 'h81084;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC14_LSB_OFS = 'h81088;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC14_MSB_OFS = 'h8108c;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC15_LSB_OFS = 'h81090;
  localparam int HBM_AXI4_ADDR_1IN3_KSK_PC15_MSB_OFS = 'h81094;
  localparam int HBM_AXI4_ADDR_1IN3_TRC_PC0_LSB_OFS = 'h81098;
  localparam int HBM_AXI4_ADDR_1IN3_TRC_PC0_MSB_OFS = 'h8109c;
  typedef struct packed {
    logic [(30-1):0] padding_2;
    logic [(1-1):0] use_opportunism;
    logic [(1-1):0] use_bpip;
   } bpip_use_t;
  localparam int BPIP_USE_OFS = 'h82000;
  localparam int BPIP_TIMEOUT_OFS = 'h82004;
  typedef struct packed {
    logic [(31-1):0] padding_1;
    logic [(1-1):0] mod_switch_mean_comp;
   } keyswitch_config_t;
  localparam int KEYSWITCH_CONFIG_OFS = 'h83000;
endpackage
