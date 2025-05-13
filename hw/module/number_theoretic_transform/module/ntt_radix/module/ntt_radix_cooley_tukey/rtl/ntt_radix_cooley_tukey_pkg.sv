// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// ntt_radix_cooley_tukey package
// Contains functions related to ntt_radix_cooley_tukey:
//   get_latency : output ntt_radix_cooley_tukey latency value (does not take into account IN_PIPE)
// ==============================================================================================

package ntt_radix_cooley_tukey_pkg;
  import common_definition_pkg::*;
  import arith_mult_pkg::*;
  import mod_reduct_pkg::*;
  import mod_add_sub_pkg::*;
  import mod_mult_pkg::*;

  localparam bit BUTTERFLY_IN_PIPE      = 1;
  localparam bit BUTTERFLY_OUT_PIPE     = 1;
  localparam bit MULT_BUTTERFLY_IN_PIPE = 1;

  // LATENCY of ntt_radix_cooley_tukey.
  // This function enables parent module to have access to the default LATENCY value.
  function int get_latency_butterfly();
    return  BUTTERFLY_IN_PIPE
          + BUTTERFLY_OUT_PIPE
          + mod_add_sub_pkg::get_latency();
  endfunction

  function int get_latency_mult_butterfly(arith_mult_type_e MULT_TYPE,
                                          mod_reduct_type_e REDUCT_TYPE,
                                          mod_mult_type_e MOD_MULT_TYPE = get_mod_mult(REDUCT_TYPE), bit USE_MOD_MULT = 0);
    int mult_reduct_lat;
    int mod_mult_lat;
    int additional_input_pipe;

    // When inferring goldilock cascade, every clock cycle is already accounted for and hardcoded
    additional_input_pipe = (MULT_TYPE == MULT_GOLDILOCKS_CASCADE) ? 0 : 1; // TODO

    mult_reduct_lat = MULT_BUTTERFLY_IN_PIPE
          + arith_mult_pkg::get_latency(MULT_TYPE)
          + mod_reduct_pkg::get_latency(REDUCT_TYPE, MULT_TYPE) + additional_input_pipe; // internal pipe
    mod_mult_lat = MULT_BUTTERFLY_IN_PIPE
                  + mod_mult_pkg::get_latency(MOD_MULT_TYPE, MULT_TYPE)
                  + mod_add_sub_pkg::get_latency()
                  +1; // Output pipe
    return USE_MOD_MULT ? mod_mult_lat : mult_reduct_lat;
  endfunction

  function int get_latency(int R, arith_mult_type_e MULT_TYPE,
                           mod_reduct_type_e REDUCT_TYPE,
                           mod_mult_type_e MOD_MULT_TYPE = get_mod_mult(REDUCT_TYPE), bit USE_MOD_MULT = 0);
    int s_nb;
    s_nb = $clog2(R);
    return s_nb * get_latency_mult_butterfly(MULT_TYPE, REDUCT_TYPE, MOD_MULT_TYPE, USE_MOD_MULT);
  endfunction

endpackage
