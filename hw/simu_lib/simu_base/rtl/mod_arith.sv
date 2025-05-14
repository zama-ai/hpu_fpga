// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Package for modular arithmetic functions
// ==============================================================================================

package mod_arith;

  function logic [63:0] mod_div_by_2(logic [63:0] a, logic [63:0] m);
    /*
    . Returns [(1/2) * a] modulo m
    . using the shift trick
    */

    if ((a & 1) == 0) begin
      return (a >> 1);
    end else begin
      return ((a >> 1) + ((m + 1) >> 1));
    end

  endfunction

  function logic [63:0] mod_add(logic [63:0] a, logic [63:0] b, logic [63:0] m);
    /*
    . Returns (a + b) modulo m
    . using the naive method for addition with one reduction step
    */

    logic [64:0] addition;
    logic [64:0] subtraction;

    addition = a + b;
    subtraction = addition - m;

    if ($signed(subtraction) >= 0) begin
      return subtraction[63:0];
    end else begin
      return addition[63:0];
    end

  endfunction

  function logic [63:0] mod_sub(logic [63:0] a, logic [63:0] b, logic [63:0] m);
    /*
    . Returns (a - b) modulo m
    . using the naive method for subtraction with one reduction step
    */

    logic [64:0] sub;
    logic [64:0] add;

    sub = a - b;
    add = m + sub;

    if ($signed(sub) < 0) begin
      return add[63:0];
    end else begin
      return sub[63:0];
    end

  endfunction

  function logic [127:0] mod_red(logic [127:0] a, logic [127:0] m);
    /*
    . Returns a modulo m
    . using the naive method by division
    */

    return a - ((a / m) * m);

  endfunction

endpackage : mod_arith
