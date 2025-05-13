// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This package contains localparam, localparam, function used by ntt_core_wmm_dispatch_rotate_pcg.
//
// ==============================================================================================

package ntt_core_wmm_dispatch_rotate_pcg_pkg;
  localparam int PARAM_NB = 12;

  localparam int PARAM_OFS_GROUP_SIZE         = 0;
  localparam int PARAM_OFS_GROUP_NB           = 1;
  localparam int PARAM_OFS_TOTAL_GROUP_NB     = 2;
  localparam int PARAM_OFS_GROUP_NB_L         = 3;
  localparam int PARAM_OFS_GROUP_NODE         = 4;
  localparam int PARAM_OFS_GROUP_STG_ITER_NB  = 5;
  localparam int PARAM_OFS_POS_NB             = 6;
  localparam int PARAM_OFS_STG_ITER_THRESHOLD = 7;
  localparam int PARAM_OFS_SET_NB             = 8;
  localparam int PARAM_OFS_CONS_NB            = 9;
  localparam int PARAM_OFS_ITER_CONS_NB       = 10;
  localparam int PARAM_OFS_ITER_SET_NB        = 11;

  function [PARAM_NB-1:0][31:0] get_pcg_param(int R, int PSI, int S, int STG_ITER_NB, int DELTA_IDX);
    int GROUP_SIZE;
    int GROUP_NB;
    int TOTAL_GROUP_NB;
    int GROUP_NB_L;
    int GROUP_NODE;
    int GROUP_STG_ITER_NB;
    int POS_NB;
    int STG_ITER_THRESHOLD;
    int SET_NB;
    int CONS_NB;
    int ITER_CONS_NB;
    int ITER_SET_NB;

    // Intermediate var
    int R_W;
    int PSI_W;
    int STG_ITER_W;
    int POS_NB_TMP;
    int STG_ITER_THRESHOLD_TMP;
    int N;
    int elt_per_iter;
    int node_idx_stg_iter_1_tmp;
    int node_idx_stg_iter_1;
    int node_id_stg_iter_1;
    int next_node_id_stg_iter_1;
    int next_bu_id_stg_iter_1;
    int next_bu_idx_stg_iter_1;
    int NODE_ID_MASK;

    R_W   = $clog2(R);
    PSI_W = $clog2(PSI);
    STG_ITER_W = $clog2(STG_ITER_W);
    N     = R**S;
    NODE_ID_MASK = (1 << S-1) -1;

    //== Group info
    /* Network characteristics according to current DELTA_IDX */
    /* A group is composed of the smallest number of consecutive data */
    /* that are dependent on the next stage */
    GROUP_SIZE     = R**(DELTA_IDX + 2);         /* Number of data of the group */
    GROUP_NB       = (PSI*R) / GROUP_SIZE;   /* Number of groups within the implemented BUs */
    TOTAL_GROUP_NB = N / GROUP_SIZE == 0 ? 1 : N / GROUP_SIZE;
    GROUP_NB_L     = GROUP_NB == 0 ? 1 : GROUP_NB; /* Used in for loop */
    GROUP_NODE     = GROUP_SIZE / R; /* Number of BU within a group. Is also the number of occurrence of a position. */

    //== Step info
    POS_NB_TMP  = (PSI*R) / GROUP_NODE;
    POS_NB      = (GROUP_NB == 0) ? POS_NB_TMP == 0 ? 1 : POS_NB_TMP : R;

    GROUP_STG_ITER_NB = (POS_NB == 1) ? STG_ITER_NB / TOTAL_GROUP_NB : 1; /* Number of stg iteration per group */

    //== stage iteration info
    STG_ITER_THRESHOLD_TMP = (POS_NB > 1) ? TOTAL_GROUP_NB / PSI : N / (PSI*R*PSI*R);
    STG_ITER_THRESHOLD = STG_ITER_THRESHOLD_TMP == 0 ? 1 : STG_ITER_THRESHOLD_TMP;

    elt_per_iter = (POS_NB > 1) ? PSI : PSI*R;

    if (elt_per_iter <= STG_ITER_NB)
      SET_NB = 1;
    else begin
      if (elt_per_iter <= GROUP_NODE)
        SET_NB = elt_per_iter / STG_ITER_NB;
      else begin
        if (GROUP_NODE > STG_ITER_NB)
          SET_NB = GROUP_NODE / STG_ITER_NB;
        else
          SET_NB = 1;
      end
    end


    // Look at ID of the first node of 2nd iteration
    // If associated next_BU is the same as the first one : we have consecutive BUs
    if (PSI*R == (GROUP_SIZE /R)) begin
        if (STG_ITER_NB > 2)
            node_idx_stg_iter_1 = R*PSI; // Do not look at the iteration the produces the other position
        else
            node_idx_stg_iter_1 = 1; // To force a non null result
    end
    else
        node_idx_stg_iter_1 = PSI;
    // node_id_stg_iter_1 = pseudo_reverse_order(node_idx_stg_iter_1, R, S-1, DELTA_IDX)
    node_id_stg_iter_1 = 0;
    for (int i=0; i<DELTA_IDX; i=i+1)
      node_id_stg_iter_1[i] = node_idx_stg_iter_1[i];
    for (int i=DELTA_IDX; i<S-1; i=i+1)
      node_id_stg_iter_1[i] = node_idx_stg_iter_1[S-2-(i-DELTA_IDX)];

    next_node_id_stg_iter_1 = (node_id_stg_iter_1 << R_W) & NODE_ID_MASK;
    next_bu_id_stg_iter_1 = next_node_id_stg_iter_1 >> STG_ITER_W;
    //next_bu_idx_stg_iter_1 = pseudo_reverse_order(next_bu_id_stg_iter_1, R, PSI_W, 0)
    next_bu_idx_stg_iter_1 = 0;
    for (int i=0; i<PSI_W; i=i+1)
      next_bu_idx_stg_iter_1[i] = next_bu_id_stg_iter_1[PSI_W-1-i];

    if (next_bu_idx_stg_iter_1 == 0) begin// 0 is the BU idx of the first next BU of 1rst stg_iter
      ITER_CONS_NB = (STG_ITER_NB * SET_NB)/ (PSI*R);
      // Should be less than the number of stg_iter per group / R
      if (ITER_CONS_NB >= GROUP_STG_ITER_NB)
          ITER_CONS_NB = GROUP_STG_ITER_NB / R;
    end
    else
        ITER_CONS_NB = 1;

    if (ITER_CONS_NB == 0)
      ITER_CONS_NB = 1;

    CONS_NB = GROUP_NB;
    if (CONS_NB == 0)
      CONS_NB = 1;

    ITER_SET_NB = GROUP_STG_ITER_NB / (R * ITER_CONS_NB);
    if (ITER_SET_NB == 0)
      ITER_SET_NB = 1;

    get_pcg_param[PARAM_OFS_GROUP_SIZE]         = GROUP_SIZE;
    get_pcg_param[PARAM_OFS_GROUP_NB]           = GROUP_NB;
    get_pcg_param[PARAM_OFS_TOTAL_GROUP_NB]     = TOTAL_GROUP_NB;
    get_pcg_param[PARAM_OFS_GROUP_NB_L]         = GROUP_NB_L;
    get_pcg_param[PARAM_OFS_GROUP_NODE]         = GROUP_NODE;
    get_pcg_param[PARAM_OFS_GROUP_STG_ITER_NB]  = GROUP_STG_ITER_NB;
    get_pcg_param[PARAM_OFS_POS_NB]             = POS_NB;
    get_pcg_param[PARAM_OFS_STG_ITER_THRESHOLD] = STG_ITER_THRESHOLD;
    get_pcg_param[PARAM_OFS_SET_NB]             = SET_NB;
    get_pcg_param[PARAM_OFS_CONS_NB]            = CONS_NB;
    get_pcg_param[PARAM_OFS_ITER_CONS_NB]       = ITER_CONS_NB;
    get_pcg_param[PARAM_OFS_ITER_SET_NB]        = ITER_SET_NB;
  endfunction

  //=================================
  // Last stage
  //=================================
  localparam int LS_PARAM_NB = 4;

  localparam int LS_PARAM_OFS_CONS_NB      = 0;
  localparam int LS_PARAM_OFS_OCC_NB       = 1;
  localparam int LS_PARAM_OFS_SET_NB       = 2;
  localparam int LS_PARAM_OFS_ITER_CONS_NB = 3;

  function [LS_PARAM_NB-1:0][31:0] get_pcg_ls_param(int R, int PSI, int S, int STG_ITER_NB, int DELTA_IDX);
    int CONS_NB;
    int OCC_NB;
    int SET_NB;
    int ITER_CONS_NB;

    int PSI_W;
    int STG_ITER_W;

    PSI_W = $clog2(PSI);
    STG_ITER_W = $clog2(STG_ITER_NB);

    if (DELTA_IDX <= PSI_W) begin
        CONS_NB = R**DELTA_IDX;
        OCC_NB = R**(PSI_W-DELTA_IDX);
        if ((PSI_W-DELTA_IDX) > STG_ITER_W)
            OCC_NB = R**(STG_ITER_W);
    end
    else begin
        CONS_NB = R**PSI_W;
        OCC_NB = 1;
    end
    if (DELTA_IDX < PSI_W) begin
        if (STG_ITER_W-(PSI_W-DELTA_IDX) > 0)
            ITER_CONS_NB = R**(STG_ITER_W-(PSI_W-DELTA_IDX));
        else
            ITER_CONS_NB = 1;
    end
    else begin
        ITER_CONS_NB = R**STG_ITER_W;
    end

    SET_NB = PSI/(CONS_NB*OCC_NB);
    if (SET_NB == 0)
        SET_NB = 1;

    get_pcg_ls_param[LS_PARAM_OFS_CONS_NB]      = CONS_NB;
    get_pcg_ls_param[LS_PARAM_OFS_OCC_NB]       = OCC_NB;
    get_pcg_ls_param[LS_PARAM_OFS_SET_NB]       = SET_NB;
    get_pcg_ls_param[LS_PARAM_OFS_ITER_CONS_NB] = ITER_CONS_NB;

  endfunction

endpackage
