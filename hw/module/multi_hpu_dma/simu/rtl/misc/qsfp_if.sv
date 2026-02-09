// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : QSFP RX Interface Definition for multi_hpu_dma testbenches
// This module only exists becaude of the VCS Error-[NYINM] Unsupported SystemVerilog feature
// when this is compiled first we can avoid duplicating it everywhere
// ==============================================================================================

import mhdma_pkg::*;

interface qsfp_if (input bit clk);
  logic [MRMAC_AXIS_W-1:0]  tdata;
  logic [MRMAC_TKEEP_W-1:0] tkeep_user;
  logic                     tlast;
  logic                     tvalid;
  logic                     tready;

  modport master (
    input  clk,
    output tdata, tkeep_user, tlast, tvalid,
    input  tready
  );

  modport slave (
    input  clk,
    input  tdata, tkeep_user, tlast, tvalid,
    output tready
  );
endinterface
