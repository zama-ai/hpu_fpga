// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Parameters that defines the PBS.
// ==============================================================================================

package param_tfhe_pkg;
  import param_tfhe_definition_pkg::*;

  export param_tfhe_definition_pkg::N;
  export param_tfhe_definition_pkg::GLWE_K;
  export param_tfhe_definition_pkg::PBS_L;
  export param_tfhe_definition_pkg::PBS_B_W;
  export param_tfhe_definition_pkg::LWE_K;
  export param_tfhe_definition_pkg::MOD_Q_W;
  export param_tfhe_definition_pkg::MOD_Q ;
  export param_tfhe_definition_pkg::KS_L;
  export param_tfhe_definition_pkg::KS_B_W;
  export param_tfhe_definition_pkg::MOD_KSK_W;
  export param_tfhe_definition_pkg::MOD_KSK;
  export param_tfhe_definition_pkg::PAYLOAD_BIT;
  export param_tfhe_definition_pkg::PADDING_BIT;
  export param_tfhe_definition_pkg::APPLICATION_NAME;
  export param_tfhe_definition_pkg::USE_MEAN_COMP;

  // ------------------------------------------------------------------------------------------- --
  // Create localparam for constants that are often used.
  // ------------------------------------------------------------------------------------------- --
  localparam int USEFUL_BIT  = PAYLOAD_BIT + PADDING_BIT;
  // Total number of polynomials
  localparam int GLWE_K_P1   = GLWE_K + 1;
  localparam int LWE_K_P1    = LWE_K + 1;
  localparam int BLWE_K      = GLWE_K * N;
  localparam int BLWE_K_P1   = BLWE_K + 1;
  // Number of interleaved levels at the input. (Number of rows of the matrix)
  localparam int INTL_L      = GLWE_K_P1 * PBS_L;
  // LWE coefficient width: value in [0 2*N[
  localparam int LWE_COEF_W  = $clog2(2*N);

  // ------------------------------------------------------------------------------------------- --
  // Counter size
  // ------------------------------------------------------------------------------------------- --
  // Note that if the value is 1, the counter size is 1 (and not 0)
  // intl_idx counter size
  localparam int INTL_L_W    = ($clog2(INTL_L) == 0) ? 1 : $clog2(INTL_L);
  // Counter from 0 to LWE_K-1
  localparam int LWE_K_W     = $clog2(LWE_K) == 0 ? 1 : $clog2(LWE_K);
  // Counter from 0 to LWE_K included
  localparam int LWE_K_WW     = $clog2(LWE_K+1) == 0 ? 1 : $clog2(LWE_K+1);
  // Counter from 0 to GLWE_K_P1-1
  localparam int GLWE_K_P1_W = $clog2(GLWE_K_P1) == 0 ? 1 : $clog2(GLWE_K_P1);
  // Counter from 0 to LWE_K_P1-1
  localparam int LWE_K_P1_W  = $clog2(LWE_K_P1) == 0 ? 1 : $clog2(LWE_K_P1);
  // Counter from 0 to PBS_L-1
  localparam int PBS_L_W     = $clog2(PBS_L) == 0 ? 1 : $clog2(PBS_L);
  // Decomposition base value
  localparam int PBS_B       = 2**PBS_B_W;
  // Number of bits of KS_L
  localparam int KS_L_W       = $clog2(KS_L);
  // Decomposition base value
  localparam int KS_B         = 2**KS_B_W;
  // Counter from 0 to LWE_K-1
  localparam int BLWE_K_W     = $clog2(BLWE_K) == 0 ? 1 : $clog2(BLWE_K);
  // Counter from 0 to LWE_K_P1-1
  localparam int BLWE_K_P1_W  = $clog2(BLWE_K_P1) == 0 ? 1 : $clog2(BLWE_K_P1);
  // Counter from 0 to N-1
  localparam int N_W          = $clog2(N) == 0 ? 1 : $clog2(N);
  // Size
  localparam int N_SZ         = $clog2(N);

endpackage
