// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
// HPU top level.
// HPU is split into 3 parts.
// This module is the third part.
// Mainly used to ease P&R constraints.
// ==============================================================================================

`include "hpu_io_macro_inc.sv"

(* keep_hierarchy = "yes" *)
module hpu_3parts_3in3_core
  import common_definition_pkg::*;
  import param_tfhe_pkg::*;
  import param_ntt_pkg::*;
  import top_common_param_pkg::*;
  import hpu_common_param_pkg::*;
  import hpu_common_instruction_pkg::*;
  import axi_if_common_param_pkg::*;
  import axi_if_shell_axil_pkg::*;
  import axi_if_bsk_axi_pkg::*;
  import axi_if_ksk_axi_pkg::*;
  import axi_if_glwe_axi_pkg::*;
  import axi_if_ct_axi_pkg::*;
  import axi_if_trc_axi_pkg::*;
  import regf_common_param_pkg::*;
  import pem_common_param_pkg::*;
  import pea_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import ntt_core_common_param_pkg::*;
  import pep_ks_common_param_pkg::*;
  import pep_if_pkg::*;
#(
  // AXI4 ADD_W could be redefined by the simulation.
  parameter int    AXI4_TRC_ADD_W   = 64,
  parameter int    AXI4_PEM_ADD_W   = 64,
  parameter int    AXI4_GLWE_ADD_W  = 64,
  parameter int    AXI4_BSK_ADD_W   = 64,
  parameter int    AXI4_KSK_ADD_W   = 64,

  // HPU version
  parameter int    VERSION_MAJOR    = 2,
  parameter int    VERSION_MINOR    = 0
)
(
  input  logic                 prc_clk,     // process clock
  input  logic                 prc_srst_n, // synchronous reset

  input  logic                 cfg_clk,     // config clock
  input  logic                 cfg_srst_n, // synchronous reset

  output logic [1:0]           interrupt, // [0] prc_clk, [1] cfg_clk

  //== Axi4-lite slave @prc_clk and @cfg_clk
  `HPU_AXIL_IO(prc,axi_if_shell_axil_pkg)
  `HPU_AXIL_IO(cfg,axi_if_shell_axil_pkg)

  //== Axi4 BSK interface
  `HPU_AXI4_IO(bsk, BSK, axi_if_bsk_axi_pkg, [BSK_PC-1:0])

  //== HPU internal signals
  //-- Data path
  input  ntt_proc_data_t      p2_p3_ntt_proc_data,
  input  [PSI-1:0][R-1:0]     p2_p3_ntt_proc_avail,
  input                       p2_p3_ntt_proc_ctrl_avail,

  output ntt_proc_data_t      p3_p2_ntt_proc_data,
  output [PSI-1:0][R-1:0]     p3_p2_ntt_proc_avail,
  output                      p3_p2_ntt_proc_ctrl_avail,

  //-- Cmd path
  input ntt_proc_cmd_t        ntt_proc_cmd,
  input                       ntt_proc_cmd_avail,

  //-- BSK
  input  entrybsk_proc_t      entry_bsk_proc,
  output bskentry_proc_t      bsk_entry_proc,

  //-- For regif
  input pep_rif_elt_t         p2_p3_pep_rif_elt,

  // Reset three way handshake
  output logic                hpu_reset,
  input  logic                hpu_reset_done
);

// ============================================================================================== --
// localparam
// ============================================================================================== --
// ---------------------------------------------------------------------------------------------- --
// Error
// ---------------------------------------------------------------------------------------------- --
  // error bus width - TODO : complete here the other modules' error.
  localparam int ERROR_NB  = PEP_ERROR_W;

// ============================================================================================== --
// Signals
// ============================================================================================== --
  // Control
  logic [BR_BATCH_CMD_W-1:0]              br_batch_cmd;
  logic                                   br_batch_cmd_avail;

  logic                                   reset_bsk_cache;
  logic                                   reset_bsk_cache_done;

  logic                                   bsk_if_batch_start_1h;
  logic                                   inc_bsk_wr_ptr;
  logic                                   inc_bsk_rd_ptr;

  logic                                                        bsk_mem_avail;
  logic [BSK_PC_MAX-1:0][axi_if_bsk_axi_pkg::AXI4_ADD_W-1:0]   bsk_mem_addr;

  // BSK
  logic [PSI-1:0][R-1:0][GLWE_K_P1-1:0][MOD_NTT_W-1:0]         bsk;
  logic [PSI-1:0][R-1:0][GLWE_K_P1-1:0]                        bsk_vld;
  logic [PSI-1:0][R-1:0][GLWE_K_P1-1:0]                        bsk_rdy;

  // Output data to next ntt
  ntt_proc_data_t                         next_data;
  logic [PSI-1:0][R-1:0]                  next_data_avail;
  logic                                   next_ctrl_avail;

  // Input from previous ntt
  ntt_proc_data_t                         prev_data;
  logic [PSI-1:0][R-1:0]                  prev_data_avail;
  logic                                   prev_ctrl_avail;

  pep_error_t                             pep_error;
  pep_info_t                              pep_rif_info;
  pep_counter_inc_t                       pep_rif_counter_inc;

  pep_error_t                             pep_ntt_error;
  pep_error_t                             pep_bsk_error;

  pep_info_t                              pep_ntt_rif_info;
  pep_info_t                              pep_bsk_rif_info;

  pep_counter_inc_t                       pep_ntt_rif_counter_inc;
  pep_counter_inc_t                       pep_bsk_rif_counter_inc;

// ============================================================================================== --
// Side
// ============================================================================================== --
  pep_error_t                             pep_errorD;
  pep_info_t                              pep_rif_infoD;
  pep_counter_inc_t                       pep_rif_counter_incD;

  assign pep_errorD           = pep_ntt_error           | pep_bsk_error            | p2_p3_pep_rif_elt.error;
  assign pep_rif_infoD        = pep_ntt_rif_info        | pep_bsk_rif_info         | p2_p3_pep_rif_elt.rif_info;
  assign pep_rif_counter_incD = pep_ntt_rif_counter_inc | pep_bsk_rif_counter_inc  | p2_p3_pep_rif_elt.rif_counter_inc;

  always_ff @(posedge prc_clk)
    if (!prc_srst_n) begin
      pep_error           <= '0;
      pep_rif_info        <= '0;
      pep_rif_counter_inc <= '0;
    end
    else begin
      pep_error           <= pep_errorD          ;
      pep_rif_info        <= pep_rif_infoD       ;
      pep_rif_counter_inc <= pep_rif_counter_incD;
    end

// ============================================================================================== --
// Input
// ============================================================================================== --
  assign br_batch_cmd          = ntt_proc_cmd.batch_cmd;
  assign br_batch_cmd_avail    = ntt_proc_cmd_avail;

  assign inc_bsk_rd_ptr        = entry_bsk_proc.inc_rd_ptr;
  assign bsk_if_batch_start_1h = entry_bsk_proc.batch_start_1h;

  assign prev_data       = p2_p3_ntt_proc_data       ;
  assign prev_data_avail = p2_p3_ntt_proc_avail      ;
  assign prev_ctrl_avail = p2_p3_ntt_proc_ctrl_avail ;

// ============================================================================================== --
// Output
// ============================================================================================== --
  assign bsk_entry_proc.inc_wr_ptr       = inc_bsk_wr_ptr;

  assign p3_p2_ntt_proc_data       = next_data;
  assign p3_p2_ntt_proc_avail      = next_data_avail;
  assign p3_p2_ntt_proc_ctrl_avail = next_ctrl_avail;

// ============================================================================================== --
// HPU entry
// ============================================================================================== --
  hpu_with_entry_3in3
  #(
    .ERROR_NB (ERROR_NB)
  ) hpu_with_entry_3in3 (
    .prc_clk                   (prc_clk),
    .prc_srst_n                (prc_srst_n),

    .cfg_clk                   (cfg_clk),
    .cfg_srst_n                (cfg_srst_n),

    // Axi lite interface
    `HPU_AXIL_INSTANCE(prc,prc)
    `HPU_AXIL_INSTANCE(cfg,cfg)

    // Registers IO
    .bsk_mem_addr              (bsk_mem_addr),
    .bsk_mem_avail             (bsk_mem_avail),
    .reset_bsk_cache           (reset_bsk_cache),
    .reset_bsk_cache_done      (reset_bsk_cache_done),

    .reset_cache               (/*UNUSED*/),

    // Instrumentation
    .error                     (pep_error),
    .pep_rif_info              (pep_rif_info),
    .pep_rif_counter_inc       (pep_rif_counter_inc),

    .interrupt                 (interrupt),

    .hpu_reset                 (hpu_reset),
    .hpu_reset_done            (hpu_reset_done)
  );

// ============================================================================================== --
// pe_pbs_with_ntt_core_middle
// contains:
// * ntt_core_middle
// =============================================================================================
  pe_pbs_with_ntt_core_middle
  #(
    .MOD_MULT_TYPE         (MOD_MULT_TYPE),
    .REDUCT_TYPE           (REDUCT_TYPE),
    .PHI_MULT_TYPE         (PHI_MULT_TYPE),
    .PP_MOD_MULT_TYPE      (PP_MOD_MULT_TYPE),
    .PP_MULT_TYPE          (PP_MULT_TYPE),
    .MODSW_2_PRECISION_W   (MODSW_2_PRECISION_W),
    .MODSW_2_MULT_TYPE     (MODSW_2_MULT_TYPE),
    .MODSW_MULT_TYPE       (MODSW_MULT_TYPE),
    .RAM_LATENCY           (RAM_LATENCY),
    .URAM_LATENCY          (URAM_LATENCY),
    .ROM_LATENCY           (ROM_LATENCY),
    .TWD_IFNL_FILE_PREFIX  (TWD_IFNL_FILE_PREFIX),
    .TWD_PHRU_FILE_PREFIX  (TWD_PHRU_FILE_PREFIX),
    .TWD_GF64_FILE_PREFIX  (TWD_GF64_FILE_PREFIX),
    .INST_FIFO_DEPTH       (PEP_INST_FIFO_DEPTH),
    .REGF_RD_LATENCY       (REGF_RD_LATENCY),
    .KS_IF_COEF_NB         (KS_IF_COEF_NB),
    .KS_IF_SUBW_NB         (KS_IF_SUBW_NB),
    .PHYS_RAM_DEPTH        (PHYS_RAM_DEPTH),
    .S_NB                  (MID1_S_NB),
    .USE_PP                (MID1_USE_PP),
    .S_INIT                (MID1_S_INIT)
  ) pe_pbs_with_ntt_core_middle (
    .clk                  (prc_clk),
    .s_rst_n              (prc_srst_n),

    .twd_omg_ru_r_pow     ('x), /*UNUSED*/


    .br_batch_cmd         (br_batch_cmd),
    .br_batch_cmd_avail   (br_batch_cmd_avail),

    .bsk                  (bsk    ),
    .bsk_vld              (bsk_vld),
    .bsk_rdy              (bsk_rdy),

    .prev_data            (prev_data.data),
    .prev_data_avail      (prev_data_avail),
    .prev_sob             (prev_data.sob),
    .prev_eob             (prev_data.eob),
    .prev_sol             (prev_data.sol),
    .prev_eol             (prev_data.eol),
    .prev_sos             (prev_data.sos),
    .prev_eos             (prev_data.eos),
    .prev_pbs_id          (prev_data.pbs_id),
    .prev_ctrl_avail      (prev_ctrl_avail),

    .next_data            (next_data.data),
    .next_data_avail      (next_data_avail),
    .next_sob             (next_data.sob),
    .next_eob             (next_data.eob),
    .next_sol             (next_data.sol),
    .next_eol             (next_data.eol),
    .next_sos             (next_data.sos),
    .next_eos             (next_data.eos),
    .next_pbs_id          (next_data.pbs_id),
    .next_ctrl_avail      (next_ctrl_avail),

    .pep_error            (pep_ntt_error),
    .pep_rif_info         (pep_ntt_rif_info),
    .pep_rif_counter_inc  (pep_ntt_rif_counter_inc)
  );


// ============================================================================================== --
// pe_pbs_with_bsk
// contains:
// * bsk_if
// * bsk_manager
  // ============================================================================================== --  // Tie-off m_axi4 unused features
  `HPU_AXI4_TIE_GL_UNUSED(bsk, [BSK_PC-1:0],BSK_PC)
  `HPU_AXI4_TIE_WR_UNUSED(bsk, [BSK_PC-1:0])

  // /!\ Workaround : simulation AXI4_BSK_ADD_W may be different from
  // the AXI4_BSK_ADD_W of the package (= the synthesized value).
  // Use intermediate variable.
  logic [BSK_PC-1:0][axi_if_bsk_axi_pkg::AXI4_ADD_W-1:0] m_axi4_bsk_araddr_tmp;
  always_comb
    for (int i=0; i<BSK_PC; i=i+1)
      m_axi4_bsk_araddr[i] = m_axi4_bsk_araddr_tmp[i][AXI4_BSK_ADD_W-1:0];

// pragma translate_off
  always_ff @(posedge prc_clk)
    if (!prc_srst_n) begin
      // Do nothing
    end
    else begin
      for (int i=0; i<BSK_PC; i=i+1) begin
        if (m_axi4_bsk_arvalid[i]) begin
          assert(m_axi4_bsk_araddr_tmp[i]>>AXI4_BSK_ADD_W == '0)
          else begin
            $fatal(1,"%t > ERROR: BSK AXI [%d] address overflows. Simulation supports only %d bits: 0x%0x.",$time, i, AXI4_BSK_ADD_W,m_axi4_bsk_araddr_tmp[i]);
          end
        end
      end
    end
// pragma translate_on

  pe_pbs_with_bsk
  #(
    .MOD_MULT_TYPE         (MOD_MULT_TYPE),
    .REDUCT_TYPE           (REDUCT_TYPE),
    .MULT_TYPE             (MULT_TYPE),
    .PP_MOD_MULT_TYPE      (PP_MOD_MULT_TYPE),
    .PP_MULT_TYPE          (PP_MULT_TYPE),
    .MODSW_2_PRECISION_W   (MODSW_2_PRECISION_W),
    .MODSW_2_MULT_TYPE     (MODSW_2_MULT_TYPE),
    .MODSW_MULT_TYPE       (MODSW_MULT_TYPE),
    .RAM_LATENCY           (RAM_LATENCY),
    .URAM_LATENCY          (URAM_LATENCY),
    .ROM_LATENCY           (ROM_LATENCY),
    .TWD_IFNL_FILE_PREFIX  (TWD_IFNL_FILE_PREFIX),
    .TWD_PHRU_FILE_PREFIX  (TWD_PHRU_FILE_PREFIX),
    .INST_FIFO_DEPTH       (PEP_INST_FIFO_DEPTH),
    .REGF_RD_LATENCY       (REGF_RD_LATENCY),
    .KS_IF_COEF_NB         (KS_IF_COEF_NB),
    .KS_IF_SUBW_NB         (KS_IF_SUBW_NB),
    .PHYS_RAM_DEPTH        (PHYS_RAM_DEPTH)
  ) pe_pbs_with_bsk (
  .clk                       (prc_clk),
  .s_rst_n                   (prc_srst_n),

  .reset_bsk_cache           (reset_bsk_cache),
  .reset_bsk_cache_done      (reset_bsk_cache_done),
  .bsk_mem_avail             (bsk_mem_avail),
  .bsk_mem_addr              (bsk_mem_addr),

  `HPU_AXI4_SHORT_RD_INSTANCE(bsk, bsk, _tmp, [BSK_PC-1:0])

  .br_batch_cmd              (br_batch_cmd),
  .br_batch_cmd_avail        (br_batch_cmd_avail),

  .bsk_if_batch_start_1h     (bsk_if_batch_start_1h),

  .inc_bsk_wr_ptr            (inc_bsk_wr_ptr),
  .inc_bsk_rd_ptr            (inc_bsk_rd_ptr),

  .bsk                       (bsk),
  .bsk_vld                   (bsk_vld),
  .bsk_rdy                   (bsk_rdy),

  .pep_error                 (pep_bsk_error),
  .pep_rif_info              (pep_bsk_rif_info),
  .pep_rif_counter_inc       (pep_bsk_rif_counter_inc)
  );

endmodule
