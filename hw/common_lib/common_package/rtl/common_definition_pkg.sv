// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// common_definition package
// Define the constants used to describe the different feature possibilities.
// ==============================================================================================

package common_definition_pkg;
// Value 0 is reserved for UNKNOWN
// Value 1 is reserved for SIMU

  // TOREVIEW
  // Use an offset for each type to avoid conflict in values
  localparam int INT_TYPE_OFS          = 1*2**8; // 256
  localparam int ARITH_MULT_TYPE_OFS   = 2*2**8; // 512
  localparam int MOD_MULT_TYPE_OFS     = 3*2**8; // 768
  localparam int MOD_REDUCT_TYPE_OFS   = 4*2**8; // 1024
  localparam int NTT_CORE_ARCH_OFS     = 5*2**8; // 1280
  localparam int MOD_NTT_NAME_OFS      = 6*2**8; // 1536
  localparam int APPLICATION_NAME_OFS  = 7*2**8; // 1792
  localparam int OPTIMIZATION_NAME_OFS = 8*2**8; // 2048
  localparam int MSPLIT_NAME_OFS       = 9*2**8; // 2304
  localparam int TOP_NAME_OFS          = 10*2**8; // 2560

//=======================================
// Integer type
//=======================================
  typedef enum int{
                    INT_UNKNOWN    = 0,
                    INT_SIMU       = 1,
                    SOLINAS2       = INT_TYPE_OFS + 0,
                    SOLINAS3       = INT_TYPE_OFS + 1,
                    MERSENNE       = INT_TYPE_OFS + 2,
                    GOLDILOCKS     = INT_TYPE_OFS + 3,
                    GOLDILOCKS_INV = INT_TYPE_OFS + 4,
                    SOLINAS2_INV   = INT_TYPE_OFS + 5,
                    SOLINAS3_INV   = INT_TYPE_OFS + 6,
                    MERSENNE_INV   = INT_TYPE_OFS + 7,
                    SOLINAS2_44_14_INV = INT_TYPE_OFS + 8
                  } int_type_e;

//=======================================
// Arithmetic
//=======================================
//==  Multipliers
  typedef enum int {
                    MULT_UNKNOWN              = 0,
                    MULT_SIMU                 = 1,
                    MULT_CORE                 = ARITH_MULT_TYPE_OFS + 0,
                    MULT_KARATSUBA            = ARITH_MULT_TYPE_OFS + 1,
                    MULT_KARATSUBA_CASCADE    = ARITH_MULT_TYPE_OFS + 2,
                    MULT_GOLDILOCKS           = ARITH_MULT_TYPE_OFS + 3,
                    MULT_GOLDILOCKS_CASCADE   = ARITH_MULT_TYPE_OFS + 4
                   } arith_mult_type_e;

//=======================================
// Modular arithmetic
//=======================================
// Modular multipliers
  typedef enum int {
                     MOD_MULT_UNKNOWN    = 0,
                     MOD_MULT_SIMU       = 1,
                     MOD_MULT_SOLINAS2   = MOD_MULT_TYPE_OFS + 0,
                     MOD_MULT_SOLINAS3   = MOD_MULT_TYPE_OFS + 1,
                     MOD_MULT_MERSENNE   = MOD_MULT_TYPE_OFS + 2,
                     MOD_MULT_GOLDILOCKS = MOD_MULT_TYPE_OFS + 3,
                     MOD_MULT_BARRETT    = MOD_MULT_TYPE_OFS + 4
                   } mod_mult_type_e;
// Modular reduction
  typedef enum int { MOD_REDUCT_UNKNOWN    = 0,
                     MOD_REDUCT_SIMU       = 1,
                     MOD_REDUCT_SOLINAS2   = MOD_REDUCT_TYPE_OFS + 0,
                     MOD_REDUCT_SOLINAS3   = MOD_REDUCT_TYPE_OFS + 1,
                     MOD_REDUCT_MERSENNE   = MOD_REDUCT_TYPE_OFS + 2,
                     MOD_REDUCT_GOLDILOCKS = MOD_REDUCT_TYPE_OFS + 3,
                     MOD_REDUCT_BARRETT    = MOD_REDUCT_TYPE_OFS + 4
                   } mod_reduct_type_e;

//=======================================
// NTT core arch
//=======================================
  typedef enum int {
                      NTT_CORE_ARCH_UNKNOWN         = 0,
                      NTT_CORE_ARCH_WMM_COMPACT     = NTT_CORE_ARCH_OFS + 0,
                      NTT_CORE_ARCH_WMM_PIPELINE    = NTT_CORE_ARCH_OFS + 1,
                      NTT_CORE_ARCH_WMM_UNFOLD      = NTT_CORE_ARCH_OFS + 2,
                      NTT_CORE_ARCH_WMM_COMPACT_PCG = NTT_CORE_ARCH_OFS + 3,
                      NTT_CORE_ARCH_WMM_UNFOLD_PCG  = NTT_CORE_ARCH_OFS + 4,
                      NTT_CORE_ARCH_GF64            = NTT_CORE_ARCH_OFS + 5
                   } ntt_core_arch_e;

//=======================================
// NTT modulo names
//=======================================
  typedef enum int {
                      MOD_NTT_NAME_UNKNOWN           = 0,
                      MOD_NTT_NAME_SIMU              = 1,
                      MOD_NTT_NAME_GOLDILOCKS_64     = MOD_NTT_NAME_OFS + 0,
                      MOD_NTT_NAME_SOLINAS3_32_17_13 = MOD_NTT_NAME_OFS + 1,
                      MOD_NTT_NAME_SOLINAS2_44_14    = MOD_NTT_NAME_OFS + 2,
                      MOD_NTT_NAME_SOLINAS2_32_20    = MOD_NTT_NAME_OFS + 3,
                      MOD_NTT_NAME_SOLINAS2_23_13    = MOD_NTT_NAME_OFS + 4,
                      MOD_NTT_NAME_SOLINAS2_16_12    = MOD_NTT_NAME_OFS + 5
                   } mod_ntt_name_e;

//=======================================
// Application names
//=======================================
  typedef enum int {
                      APPLICATION_NAME_UNKNOWN           = 0,
                      APPLICATION_NAME_SIMU              = 1,
                      APPLICATION_NAME_CONCRETE_BOOLEAN  = APPLICATION_NAME_OFS + 0,
                      APPLICATION_NAME_MSG2_CARRY2       = APPLICATION_NAME_OFS + 1,
                      APPLICATION_NAME_IO_MEASURE        = APPLICATION_NAME_OFS + 2,
                      APPLICATION_NAME_MSG2_CARRY2_64_7324CB = APPLICATION_NAME_OFS + 3,
                      APPLICATION_NAME_MSG2_CARRY2_44_7324CB = APPLICATION_NAME_OFS + 4,
                      APPLICATION_NAME_MSG2_CARRY2_32_FAKE   = APPLICATION_NAME_OFS + 5,
                      APPLICATION_NAME_MSG2_CARRY2_23_FAKE   = APPLICATION_NAME_OFS + 6,
                      APPLICATION_NAME_MSG2_CARRY2_16_FAKE   = APPLICATION_NAME_OFS + 7,
                      APPLICATION_NAME_MSG2_CARRY2_44_FAKE   = APPLICATION_NAME_OFS + 8,
                      APPLICATION_NAME_MSG2_CARRY2_64_FAKE   = APPLICATION_NAME_OFS + 9,
                      APPLICATION_NAME_MSG2_CARRY2_GAUSSIAN  = APPLICATION_NAME_OFS + 10,
                      APPLICATION_NAME_MSG2_CARRY2_TUNIFORM  = APPLICATION_NAME_OFS + 11,
                      APPLICATION_NAME_MSG2_CARRY2_PFAIL64_132B_GAUSSIAN_1F72DBA = APPLICATION_NAME_OFS + 12,
                      APPLICATION_NAME_MSG2_CARRY2_PFAIL64_132B_TUNIFORM_7E47D8C = APPLICATION_NAME_OFS + 13
                   } application_name_e;

//=======================================
// Optimization names
//=======================================
  typedef enum int {
                      OPTIMIZATION_NAME_UNKNOWN           = 0,
                      OPTIMIZATION_NAME_SIMU              = 1,
                      OPTIMIZATION_NAME_DSP               = OPTIMIZATION_NAME_OFS + 0,
                      OPTIMIZATION_NAME_CLB               = OPTIMIZATION_NAME_OFS + 1,
                      OPTIMIZATION_NAME_BRAM              = OPTIMIZATION_NAME_OFS + 2
                   } optimization_name_e;

//=======================================
//  Top names
//=======================================
  typedef enum int {
                      TOP_NAME_UNKNOWN           = 0,
                      TOP_NAME_SIMU              = 1,
                      TOP_NAME_HPU               = TOP_NAME_OFS + 1
                   } top_name_e;

//=======================================
//  Msplit names
//=======================================
  typedef enum int {
                      MSPLIT_NAME_UNKNOWN           = 0,
                      MSPLIT_NAME_SIMU              = 1,
                      MSPLIT_NAME_M2_S2             = MSPLIT_NAME_OFS + 0,
                      MSPLIT_NAME_M3_S1             = MSPLIT_NAME_OFS + 1,
                      MSPLIT_NAME_M1_S3             = MSPLIT_NAME_OFS + 2
                   } msplit_name_e;

//=======================================
// functions
//=======================================
  function mod_mult_type_e get_mod_mult(mod_reduct_type_e REDUCT_TYPE, optimization_name_e OPT_TYPE = OPTIMIZATION_NAME_DSP);
    mod_mult_type_e mod_mult;
    case(REDUCT_TYPE)
      MOD_REDUCT_SOLINAS2  :
        mod_mult = MOD_MULT_SOLINAS2;
      MOD_REDUCT_SOLINAS3  :
        mod_mult = MOD_MULT_SOLINAS3;
      MOD_REDUCT_MERSENNE  :
        mod_mult = MOD_MULT_MERSENNE;
      MOD_REDUCT_GOLDILOCKS:
        mod_mult = OPT_TYPE == OPTIMIZATION_NAME_DSP ? MOD_MULT_GOLDILOCKS :
                                                       MOD_MULT_SOLINAS2;
      default:
        mod_mult = MOD_MULT_BARRETT;
    endcase
    return mod_mult;
  endfunction

  function mod_reduct_type_e get_mod_reduct(mod_mult_type_e MULT_TYPE, optimization_name_e OPT_TYPE = OPTIMIZATION_NAME_DSP);
    mod_reduct_type_e mod_reduct;
    case(MULT_TYPE)
      MOD_MULT_SOLINAS2  :
        mod_reduct = MOD_REDUCT_SOLINAS2;
      MOD_MULT_SOLINAS3  :
        mod_reduct = MOD_REDUCT_SOLINAS3;
      MOD_MULT_MERSENNE  :
        mod_reduct = MOD_REDUCT_MERSENNE;
      MOD_MULT_GOLDILOCKS:
        mod_reduct = OPT_TYPE == OPTIMIZATION_NAME_DSP ? MOD_REDUCT_GOLDILOCKS :
                                                         MOD_REDUCT_SOLINAS2;
      default:
        mod_reduct = MOD_REDUCT_BARRETT;
    endcase
    return mod_reduct;
  endfunction

  // Determine the modular multiplier to be used according to the modulo type
  function mod_mult_type_e set_mod_mult_type(int_type_e mod_type, optimization_name_e OPT_TYPE = OPTIMIZATION_NAME_DSP);
    if (mod_type == SOLINAS2)
      return MOD_MULT_SOLINAS2;
    else if (mod_type == SOLINAS3)
      return MOD_MULT_SOLINAS3;
    else if (mod_type == MERSENNE)
      return MOD_MULT_MERSENNE;
    else if (mod_type == GOLDILOCKS)
      return OPT_TYPE == OPTIMIZATION_NAME_DSP ? MOD_MULT_GOLDILOCKS :
                                                 MOD_MULT_SOLINAS2;
    else
      return MOD_MULT_BARRETT;
  endfunction

  // Determine the modular reduction to be used according to the modulo type
  function mod_reduct_type_e set_mod_reduct_type(int_type_e mod_type, optimization_name_e OPT_TYPE = OPTIMIZATION_NAME_DSP);
    if (mod_type == SOLINAS2)
      return MOD_REDUCT_SOLINAS2;
    else if (mod_type == SOLINAS3)
      return MOD_REDUCT_SOLINAS3;
    else if (mod_type == MERSENNE)
      return MOD_REDUCT_MERSENNE;
    else if (mod_type == GOLDILOCKS)
      return OPT_TYPE == OPTIMIZATION_NAME_DSP ? MOD_REDUCT_GOLDILOCKS :
                                                 MOD_REDUCT_SOLINAS2;
    else
      return MOD_REDUCT_BARRETT;
  endfunction

  // Determine the arithmetic multiplier to be used according to the operand width, and NTT type
  function arith_mult_type_e set_ntt_mult_type(int OP_W, int_type_e MOD_NTT_TYPE, optimization_name_e OPT_TYPE = OPTIMIZATION_NAME_DSP);
    case(OP_W)
      32 :
        return OPT_TYPE == OPTIMIZATION_NAME_DSP ? MULT_KARATSUBA : MULT_CORE;
      64 :
        return MOD_NTT_TYPE == GOLDILOCKS ? OPT_TYPE == OPTIMIZATION_NAME_DSP ? MULT_GOLDILOCKS_CASCADE : MULT_CORE :
                                            OPT_TYPE == OPTIMIZATION_NAME_DSP ? MULT_KARATSUBA_CASCADE : MULT_CORE;
      default :
        return  OPT_TYPE == OPTIMIZATION_NAME_DSP ? MULT_KARATSUBA : MULT_CORE;
    endcase
  endfunction

  // Determine the arithmetic multiplier to be used according to the operand width, and NTT type
  function arith_mult_type_e set_mult_type(int OP_W, optimization_name_e OPT_TYPE = OPTIMIZATION_NAME_DSP);
    case(OP_W)
      32 :
        return MULT_CORE; // TOREVIEW
      64 :
        return OPT_TYPE == OPTIMIZATION_NAME_DSP ? MULT_KARATSUBA : MULT_CORE;
      default :
        return MULT_CORE;
    endcase
  endfunction

  // Get msplit coefficient divider, to get the #coef unit
  function int get_msplit_div (msplit_name_e s);
    case (s)
      MSPLIT_NAME_M2_S2: return 4;
      MSPLIT_NAME_M3_S1: return 4;
      MSPLIT_NAME_M1_S3: return 4;
    endcase
  endfunction

  // Get msplit coefficient multiplication factor. Depends on the
  // msplit part.
  function int get_msplit_factor (msplit_name_e s, bit is_main);
    case (s)
      MSPLIT_NAME_M2_S2: return 2;
      MSPLIT_NAME_M3_S1: return is_main ? 3 : 1;
      MSPLIT_NAME_M1_S3: return is_main ? 1 : 3;
    endcase
  endfunction

endpackage
