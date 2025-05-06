// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// NTT core with goldilocks 64 prime (gf64) localparam package.
// This package defines the localparams of ntt_core_gf64.
// ==============================================================================================

package ntt_core_gf64_common_param_pkg;
  import param_tfhe_pkg::*;
  import ntt_core_common_param_pkg::*;

  localparam [S-1:0]       NTT_STG_IS_NGC      = get_stg_is_ngc();
  localparam [S-1:0][31:0] NTT_STG_RDX_ID      = get_stg_rdx_id();
  localparam [S-1:0][31:0] NTT_RDX_CUT_ID_LIST = get_rdx_cut_id_list();

  localparam int W64_2POWER = 3; // W64 = 2**3

  // [radix][pair position]
  localparam [5:1][15:0][31:0] NTT_GF64_NGC_OMG_2POW = {
  /*5*/ {32'd93,32'd87,32'd81,32'd75,32'd69,32'd63,32'd57,32'd51,32'd45,32'd39,32'd33,32'd27,32'd21,32'd15,32'd9,32'd3},
  /*4*/ {2{32'd90,32'd78,32'd66,32'd54,32'd42,32'd30,32'd18,32'd6}},
  /*3*/ {4{32'd84,32'd60,32'd36,32'd12}},
  /*2*/ {8{32'd72,32'd24}},
  /*1*/ {16{32'd48}}
  };

  localparam [6:1][31:0][31:0] NTT_GF64_CYC_OMG_2POW = {
  /*6*/ {32'd93,32'd90,32'd87,32'd84,32'd81,32'd78,32'd75,32'd72,32'd69,32'd66,32'd63,32'd60,32'd57,32'd54,32'd51,32'd48,
         32'd45,32'd42,32'd39,32'd36,32'd33,32'd30,32'd27,32'd24,32'd21,32'd18,32'd15,32'd12,32'd9,32'd6,32'd3,32'd0},
  /*5*/ {2{32'd90,32'd84,32'd78,32'd72,32'd66,32'd60,32'd54,32'd48,32'd42,32'd36,32'd30,32'd24,32'd18,32'd12,32'd6,32'd0}},
  /*4*/ {4{32'd84,32'd72,32'd60,32'd48,32'd36,32'd24,32'd12,32'd0}},
  /*3*/ {8{32'd72,32'd48,32'd24,32'd0}},
  /*2*/ {16{32'd48,32'd0}},
  /*1*/ {32{32'd0}}
  };

  localparam [5:1][15:0][31:0] INTT_GF64_NGC_OMG_2POW = {
  /*5*/ {32'd3,32'd9,32'd15,32'd21,32'd27,32'd33,32'd39,32'd45,32'd51,32'd57,32'd63,32'd69,32'd75,32'd81,32'd87,32'd93},
  /*4*/ {2{32'd6,32'd18,32'd30,32'd42,32'd54,32'd66,32'd78,32'd90}},
  /*3*/ {4{32'd12,32'd36,32'd60,32'd84}},
  /*2*/ {8{32'd24,32'd72}},
  /*1*/ {16{32'd48}}
  };

  localparam [6:1][31:0][31:0] INTT_GF64_CYC_OMG_2POW = {
  /*6*/ {32'd3,32'd6,32'd9,32'd12,32'd15,32'd18,32'd21,32'd24,32'd27,32'd30,32'd33,32'd36,32'd39,32'd42,32'd45,32'd48,
        32'd51,32'd54,32'd57,32'd60,32'd63,32'd66,32'd69,32'd72,32'd75,32'd78,32'd81,32'd84,32'd87,32'd90,32'd93,32'd0},
  /*5*/ {2{32'd6,32'd12,32'd18,32'd24,32'd30,32'd36,32'd42,32'd48,32'd54,32'd60,32'd66,32'd72,32'd78,32'd84,32'd90,32'd0}},
  /*4*/ {4{32'd12,32'd24,32'd36,32'd48,32'd60,32'd72,32'd84,32'd0}},
  /*3*/ {8{32'd24,32'd48,32'd72,32'd0}},
  /*2*/ {16{32'd48,32'd0}},
  /*1*/ {32{32'd0}}
  };

// ============================================================================================== --
// functions
// ============================================================================================== --
  // /!\ Warning: here the stages are numbered from 0 to S-1, in this increasing order.
  // For each stage
  function [S-1:0] get_stg_is_ngc();
    var [S-1:0] is_ngc;
    is_ngc = '0;
    for (int i=0; i<NTT_RDX_CUT_S[0]; i=i+1)
      is_ngc[i] = 1;
    return is_ngc;
  endfunction

  function [S-1:0][31:0] get_stg_rdx_id();
    integer i;
    i = 0;
    for (int c=0; c<NTT_RDX_CUT_NB; c=c+1)
      for (int s=0; s<NTT_RDX_CUT_S[c]; s=s+1) begin
        get_stg_rdx_id[i] = s+1; // +1 since this represents the exponent of the power of 2.
        i = i+1;
      end
  endfunction

  function [S-1:0][31:0] get_rdx_cut_id_list();
    integer i;
    i = 0;
    for (int c=0; c<NTT_RDX_CUT_NB; c=c+1)
      for (int s=0; s<NTT_RDX_CUT_S[c]; s=s+1) begin
        get_rdx_cut_id_list[i] = c;
        i = i+1;
      end
  endfunction


  // Give the ngc nature of the phi multiplication of the current radix column
  // according to RDX_CUT_ID and BWD.
  function bit is_ngc(int rdx_col_id, bit bwd);
    is_ngc = bwd ? rdx_col_id == 0 : rdx_col_id == 1; // Since the numbering order is inversed.
  endfunction


  // Give the size of the working block for RDX_CUT_ID and BWD.
  // Note that RDX_CUT_ID is numbered increasingly in FWD and decreasingly in BWD.
  // The result is actually the log2 of the size.
  // RDX_CUT_ID is the ID of the first column of the 2nd part of the working block.
  function integer get_s_l(int rdx_col_id, bit bwd);
    integer s_l;
    s_l = 0;
    if (bwd) begin
      for (int i=NTT_RDX_CUT_NB-1; i>=0; i=i-1)
        if (i>=rdx_col_id)
          s_l = s_l + NTT_RDX_CUT_S[i];
    end
    else begin
      for (int i=0; i<NTT_RDX_CUT_NB; i=i+1)
        if (i>=rdx_col_id-1)
          s_l = s_l + NTT_RDX_CUT_S[i];
    end
    return s_l;
  endfunction

  // Get the number of radix block in the left column of the working block
  // RDX_CUT_ID is the ID of the first column of the 2nd part of the working block.
  function integer get_a_nb(int rdx_col_id, bit bwd);
    integer s_l;
    integer n_l;
    s_l = get_s_l(rdx_col_id, bwd);
    n_l = 2**s_l;
    get_a_nb = bwd ? n_l / 2**(s_l-NTT_RDX_CUT_S[rdx_col_id]) : n_l / 2**NTT_RDX_CUT_S[rdx_col_id-1];
  endfunction

  // Get the number of radix block in the right column of the working block
  // RDX_CUT_ID is the ID of the first column of the 2nd part of the working block.
  function integer get_l_nb(int rdx_col_id, bit bwd);
    integer s_l;
    integer n_l;
    s_l = get_s_l(rdx_col_id, bwd);
    n_l = 2**s_l;
    get_l_nb = bwd ? n_l / 2**NTT_RDX_CUT_S[rdx_col_id] : n_l / 2**(s_l-NTT_RDX_CUT_S[rdx_col_id-1]);
  endfunction

  // Get the number of iteration within a working block
  // RDX_CUT_ID is the ID of the first column of the 2nd part of the working block.
  function integer get_iter_nb(int rdx_col_id, bit bwd);
    integer s_l;
    integer n_l;
    s_l = get_s_l(rdx_col_id, bwd);
    n_l = 2**s_l;
    get_iter_nb = n_l / (R*PSI);
  endfunction

  // Get the size of the A column radix
  // RDX_CUT_ID is the ID of the first column of the 2nd part of the working block.
  function integer get_rdx_a(int rdx_col_id, bit bwd);
    integer s_l;
    integer s_a;
    if (bwd) begin
      s_l = get_s_l(rdx_col_id, bwd);
      s_a = s_l - NTT_RDX_CUT_S[rdx_col_id];
    end
    else
      s_a = NTT_RDX_CUT_S[rdx_col_id-1];

    return 2**s_a;
  endfunction

  // Get the size of the L column radix
  // RDX_CUT_ID is the ID of the first column of the 2nd part of the working block.
  function integer get_rdx_l(int rdx_col_id, bit bwd);
    integer s_l;
    integer s_ll;
    if (bwd)
      s_ll = NTT_RDX_CUT_S[rdx_col_id];
    else begin
      s_l = get_s_l(rdx_col_id, bwd);
      s_ll = s_l - NTT_RDX_CUT_S[rdx_col_id-1];
    end

    return 2**s_ll;
  endfunction

endpackage
