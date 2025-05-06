// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
// /!\ Combinatorial module
// Workaround for parameterized function.
// Compute the permutation vector for a given permutation level.
// When all the permutation levels are applied on data in reverse order, the obtained
// function is a rotation.
//
// /!\ Assumption : R=2
// ==============================================================================================

module pep_mmacc_common_permutation_vector
#(
  parameter  int PERM_LVL_NB  = 5, // Total number of permutation levels
  parameter  int PERM_LVL     = 0, // from 0 to PERM_LVL_NB-1
  parameter  int N_SZ         = 10,
  localparam int LWE_COEF_W   = N_SZ + 1, // Should be N_SZ+1
  localparam int PERM_NB      = 2**PERM_LVL // Number of permutations in this level
)
(
  input  logic [LWE_COEF_W-1:0] rot_factor,
  output logic [PERM_NB-1:0]    perm_select
);


//=================================================================================================
// localparam
//=================================================================================================
  localparam int           MASK_BIT = PERM_LVL + 1;
  localparam [PERM_NB-1:0] MASK     = (1 << MASK_BIT)-1;

//=================================================================================================
// Compute
//=================================================================================================
  logic [MASK_BIT-1:0] factor;
  //factor = ((rot_factor % (N)) >> (N_SZ - (PSI_W+R_W))) & mask
  assign factor  = rot_factor[N_SZ-1-:PERM_LVL_NB] & MASK;

  generate
    if (PERM_LVL == 0) begin : gen_first_lvl
      assign perm_select = factor[0];
    end
    else begin : gen_no_first_lvl
      logic [PERM_NB-1:0]  factor2;
      logic                negateB;
      logic [PERM_NB-1:0]  vectorB;
      logic [PERM_NB-1:0]  rev_vectorB;

      assign factor2 = factor[PERM_LVL-1:0];
      assign negateB = factor[MASK_BIT-1:PERM_LVL] == 0;

      assign vectorB = {PERM_NB{1'b1}} << factor2;
      // place each bit in reverse order position.
      always_comb
        for (int i=0; i<PERM_NB; i=i+1) begin
          var [PERM_LVL-1:0] ii;
          var [PERM_LVL-1:0] rev_ii;

          ii = i;
          for (int j=0; j<PERM_LVL; j=j+1)
            rev_ii[j] = ii[PERM_LVL-j-1];

          rev_vectorB[i] = vectorB[rev_ii];
        end


      assign perm_select = {PERM_NB{negateB}} ^ rev_vectorB;
    end
  endgenerate

endmodule
