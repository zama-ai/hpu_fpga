// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// class that handles random.
//
// Data members
// ==============================================================================================

package random_handler_pkg;

// ============================================================================================== --
// class rand_data
// ============================================================================================== --
// Basic class to handle random data.
// User should redefine it to add contraints on the randomization.
  class random_data #(parameter int DATA_W = 8);
    //--------------------------------------------
    // Data members
    //--------------------------------------------
    rand logic [DATA_W-1:0] data;

    //--------------------------------------------
    // Constructor
    //--------------------------------------------
    function new (input [DATA_W-1:0] init_val = 'x);
      this.data    = init_val;
    endfunction : new

    //--------------------------------------------
    // Functions
    //--------------------------------------------
    //----------------------
    // get_data
    //----------------------
    function [DATA_W-1:0] get_data;
      return data;
    endfunction
    
    //----------------------
    // get_next_data
    //----------------------
    function [DATA_W-1:0] get_next_data;
      void'(std::randomize(data));
      return data;
    endfunction

  endclass

endpackage
