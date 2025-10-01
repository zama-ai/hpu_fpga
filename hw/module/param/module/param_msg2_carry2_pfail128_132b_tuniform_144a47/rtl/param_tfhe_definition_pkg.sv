// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Parameter set to use with mean compensation reaching pfail = 1e-128
//
// pub const V1_2_HPU_PARAM_MESSAGE_2_CARRY_2_KS32_PBS_TUNIFORM_2M128: KeySwitch32PBSParameters =
//       KeySwitch32PBSParameters {
//           lwe_dimension: LweDimension(879),
//           glwe_dimension: GlweDimension(1),
//           polynomial_size: PolynomialSize(2048),
//           lwe_noise_distribution: DynamicDistribution::new_t_uniform(3),
//           glwe_noise_distribution: DynamicDistribution::new_t_uniform(17),
//           pbs_base_log: DecompositionBaseLog(23),
//           pbs_level: DecompositionLevelCount(1),
//           ks_base_log: DecompositionBaseLog(2),
//           ks_level: DecompositionLevelCount(8),
//           message_modulus: MessageModulus(4),
//           carry_modulus: CarryModulus(4),
//           max_noise_level: MaxNoiseLevel::new(5),
//           log2_p_fail: -128.0,
//           post_keyswitch_ciphertext_modulus: CiphertextModulus32::new(1 << 21),
//           ciphertext_modulus: CiphertextModulus::new_native(),
//           modulus_switch_noise_reduction_params: None,
//     };
//
// ==============================================================================================

package param_tfhe_definition_pkg;
  import common_definition_pkg::*;

  localparam application_name_e APPLICATION_NAME = APPLICATION_NAME_MSG2_CARRY2_PFAIL128_132B_TUNIFORM_144A47;

  // Number of coefficient in the polynomial
  localparam int           N       = 2048;
  // The dimension of GLWE.
  localparam int           GLWE_K  = 1;
  // Number of decomposition levels.
  localparam int           PBS_L   = 1;
  // Decomposition base, in number of bits
  localparam int           PBS_B_W = 23;
  // Ciphertext size
  localparam int           LWE_K   = 879;
  // GLWE coefficient size
  localparam int           MOD_Q_W = 64;
  // GLWE coefficient modulo
  localparam [MOD_Q_W-1:0] MOD_Q   = 2**MOD_Q_W;
  // Number of decomposition levels.
  localparam int           KS_L    = 8;
  // Decomposition base, in number of bits
  localparam int           KS_B_W  = 2;
  // KSK coefficient size
  localparam int           MOD_KSK_W = 21;
  // KSK coefficient modulo
  localparam [MOD_KSK_W:0] MOD_KSK = 2**MOD_KSK_W;
  // Useful message bit (padding + payload)
  localparam int           PAYLOAD_BIT   = 4;
  localparam int           PADDING_BIT   = 1;
  // Use mean compensation
  localparam bit           USE_MEAN_COMP = 1'b1;
endpackage
