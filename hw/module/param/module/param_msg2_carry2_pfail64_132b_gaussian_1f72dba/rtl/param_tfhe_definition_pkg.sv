// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Parameters produced by optimizer from wip/fpga_poc branch commit 1f72dba
// requirements: pfail 2^-64, 132b security, gaussian distribution, correct HW BR & KS formulas
// matching noise measurements done in tfhe-rs-internal lwe_hpu_noise test
//
// ----------------------------------------------------------------------------------------------
// Var bounds: {'n': (512, 2048), 'log2_N': (8, 17), 'k': (1, 6), 'l_ks': (1, 64), 'b_ks': (2, 64), 'l_br': (1, 64), 'b_br': (2, 64), 'log2_psi': (1, 5), 'ntt_pbs_max': (6, 8), 'lambda_factor': (4, 32), 'mod_q_w': (64, 64), 'mod_ntt_w': (64, 64), 'ksk_w': (21, 21), 'bsk_slot': (8, 16), 'ksk_slot': (8, 16), 'hbm_ch_ksk': (1, 8), 'hbm_ch_bsk': (1, 8)}
// ----------------------------------------------------------------------------------------------
// Costs (51456.0, 51520.0) [br_cycles, ks_cycles]
// Params {'n': 804.0, 'log2_N': 11.0, 'k': 1.0, 'l_ks': 8.0, 'b_ks': 2.0, 'l_br': 1.0, 'b_br': 23.0, 'log2_psi': 5.0, 'ntt_pbs_max': None, 'lambda_factor': 32.0, 'mod_q_w': 64.0, 'mod_ntt_w': 64.0, 'ksk_w': 21.0, 'bsk_slot': None, 'ksk_slot': None, 'hbm_ch_ksk': None, 'hbm_ch_bsk': None}
// std_devs {'standard_deviations': [(2048.0, 2.8452674713391114e-15), (804.0, 5.963599673924788e-06)], 'log2_modulus': 64.0}
// ----------------------------------------------------------------------------------------------
//
// lambda= 133.30638057835066
// lambda= 132.03955349880871
//
// ==============================================================================================

package param_tfhe_definition_pkg;
  import common_definition_pkg::*;

  localparam application_name_e APPLICATION_NAME = APPLICATION_NAME_MSG2_CARRY2_PFAIL64_132B_GAUSSIAN_1F72DBA;

  // Number of coefficient in the polynomial
  localparam int           N       = 2048;
  // The dimension of GLWE.
  localparam int           GLWE_K  = 1;
  // Number of decomposition levels.
  localparam int           PBS_L   = 1;
  // Decomposition base, in number of bits
  localparam int           PBS_B_W = 23;
  // Ciphertext size
  localparam int           LWE_K   = 804;
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
  localparam bit           USE_MEAN_COMP = 1'b0;
endpackage
