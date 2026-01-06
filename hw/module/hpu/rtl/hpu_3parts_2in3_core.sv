// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
// HPU top level.
// HPU is split into 3 parts.
// This module is the second part.
// Mainly used to ease P&R constraints.
// ==============================================================================================

`include "hpu_io_macro_inc.sv"

(* keep_hierarchy = "yes" *)
module hpu_3parts_2in3_core
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
  import axi_if_eth_axi_pkg::*;
  import axi_if_trc_axi_pkg::*;
  import regf_common_param_pkg::*;
  import pem_common_param_pkg::*;
  import pea_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import ntt_core_common_param_pkg::*;
  import pep_ks_common_param_pkg::*;
  import pep_if_pkg::*;
  import mhdma_pkg::*;
#(
  // AXI4 ADD_W could be redefined by the simulation.
  parameter int    AXI4_TRC_ADD_W   = 64,
  parameter int    AXI4_PEM_ADD_W   = 64,
  parameter int    AXI4_GLWE_ADD_W  = 64,
  parameter int    AXI4_BSK_ADD_W   = 64,
  parameter int    AXI4_KSK_ADD_W   = 64,
  parameter int    AXI4_ETH_HBM_ADD_W = 64,

  // HPU version
  parameter int    VERSION_MAJOR    = 2,
  parameter int    VERSION_MINOR    = 0
)
(
  input  logic                               prc_clk,     // process clock
  input  logic                               prc_srst_n, // synchronous reset

  input  logic                               cfg_clk,     // config clock
  input  logic                               cfg_srst_n, // synchronous reset

  input logic                                cfg_eth_clk,     // ethernet configuration slow clock

  input logic                                prc_mrmac_clk,    // mrmac clock at axis speed

  output interrupt_t                         interrupt,

  input  logic [AXIL_ADD_W-1:0]              s_axil_dma_awaddr,
  input  logic                               s_axil_dma_awvalid,
  output logic                               s_axil_dma_awready,
  input  logic [AXIL_DATA_W-1:0]             s_axil_dma_wdata,
  input  logic [AXIL_DATA_BYTES-1:0]         s_axil_dma_wstrb, /* UNUSED */
  input  logic                               s_axil_dma_wvalid,
  output logic                               s_axil_dma_wready,
  output logic [1:0]                         s_axil_dma_bresp,
  output logic                               s_axil_dma_bvalid,
  input  logic                               s_axil_dma_bready,
  input  logic [AXIL_ADD_W-1:0]              s_axil_dma_araddr,
  input  logic                               s_axil_dma_arvalid,
  output logic                               s_axil_dma_arready,
  output logic [AXIL_DATA_W-1:0]             s_axil_dma_rdata,
  output logic [1:0]                         s_axil_dma_rresp,
  output logic                               s_axil_dma_rvalid,
  input  logic                               s_axil_dma_rready,

  // Decomposer -> NTT
  input  logic [PSI-1:0][R-1:0]              decomp_ntt_data_avail,
  input  logic [PSI-1:0][R-1:0][PBS_B_W:0]   decomp_ntt_data, // 2s complement
  input  logic                               decomp_ntt_sob,
  input  logic                               decomp_ntt_eob,
  input  logic                               decomp_ntt_sog,
  input  logic                               decomp_ntt_eog,
  input  logic                               decomp_ntt_sol,
  input  logic                               decomp_ntt_eol,
  input  logic [BPBS_ID_W-1:0]               decomp_ntt_pbs_id,
  input  logic                               decomp_ntt_last_pbs,
  input  logic                               decomp_ntt_full_throughput,
  input  logic                               decomp_ntt_ctrl_avail,

  // Mod switch output
  output logic [PSI-1:0][R-1:0]              ntt_acc_modsw_data_avail,
  output logic                               ntt_acc_modsw_ctrl_avail,
  output logic [PSI-1:0][R-1:0][MOD_Q_W-1:0] ntt_acc_modsw_data,
  output logic                               ntt_acc_modsw_sob,
  output logic                               ntt_acc_modsw_eob,
  output logic                               ntt_acc_modsw_sol,
  output logic                               ntt_acc_modsw_eol,
  output logic                               ntt_acc_modsw_sog,
  output logic                               ntt_acc_modsw_eog,
  output logic [BPBS_ID_W-1:0]               ntt_acc_modsw_pbs_id,

  //-- Data path
  output ntt_proc_data_t                     p2_p3_ntt_proc_data,
  output logic [PSI-1:0][R-1:0]              p2_p3_ntt_proc_avail,
  output logic                               p2_p3_ntt_proc_ctrl_avail,

  input  ntt_proc_data_t                     p3_p2_ntt_proc_data,
  input  logic [PSI-1:0][R-1:0]              p3_p2_ntt_proc_avail,
  input  logic                               p3_p2_ntt_proc_ctrl_avail,

  //-- Cmd path
  input ntt_proc_cmd_t                       ntt_proc_cmd,
  input logic                                ntt_proc_cmd_avail,

  //-- For regif
  output pep_rif_elt_t                       pep_rif_elt,

  // Multi-HPU-DMA
  `HPU_AXI4_IO(eth_hbm, ETH_HBM, axi_if_eth_axi_pkg, [ETH_PC-1:0])
  // QSFP system interface
  // == TX
  output logic [QSFP_LANE_NB-1:0][MRMAC_AXIS_W-1:0]  qsfp_tx_tdata,
  output logic [QSFP_LANE_NB-1:0][MRMAC_TKEEP_W-1:0] qsfp_tx_tkeep_user,
  output logic [QSFP_LANE_NB-1:0]                    qsfp_tx_tlast,
  output logic [QSFP_LANE_NB-1:0]                    qsfp_tx_tvalid,
  input  logic [QSFP_LANE_NB-1:0]                    qsfp_tx_tready,
  // == RX
  input  logic [QSFP_LANE_NB-1:0][MRMAC_AXIS_W-1:0]  qsfp_rx_tdata,
  input  logic [QSFP_LANE_NB-1:0][MRMAC_TKEEP_W-1:0] qsfp_rx_tkeep_user,
  input  logic [QSFP_LANE_NB-1:0]                    qsfp_rx_tlast,
  input  logic [QSFP_LANE_NB-1:0]                    qsfp_rx_tvalid,
  // transceiver control
  output logic [2:0]                                 gt_loopback,
  output logic [7:0]                                 gt_line_rate,
  output logic [QSFP_LANE_NB-1:0]                    gt_reset_rx_datapath,
  output logic [QSFP_LANE_NB-1:0]                    gt_reset_tx_datapath,
  output logic [QSFP_LANE_NB-1:0]                    gt_reset_all,
  input  logic [QSFP_LANE_NB-1:0]                    gt_rx_reset_done,
  input  logic [QSFP_LANE_NB-1:0]                    gt_tx_reset_done
);

// ============================================================================================== --
// localparam
// ============================================================================================== --

// ============================================================================================== --
// Signals
// ============================================================================================== --
  logic                                   interrupt_notify;
  logic                                   interrupt_read_request;
  // -------------------------------------------------------------------------------------------- --
  // Control
  // -------------------------------------------------------------------------------------------- --
  logic [BR_BATCH_CMD_W-1:0]              br_batch_cmd;
  logic                                   br_batch_cmd_avail;

  // -------------------------------------------------------------------------------------------- --
  // NTT
  // -------------------------------------------------------------------------------------------- --
  // Output data to next ntt
  ntt_proc_data_t                         next_otw_data;
  logic [PSI-1:0][R-1:0]                  next_otw_data_avail;
  logic                                   next_otw_ctrl_avail;

  // Input from previous ntt
  ntt_proc_data_t                         prev_ret_data;
  logic [PSI-1:0][R-1:0]                  prev_ret_data_avail;
  logic                                   prev_ret_ctrl_avail;

  // NTT/INTT output
  logic [PSI-1:0][R-1:0]                  ntt_acc_data_avail;
  logic                                   ntt_acc_ctrl_avail;
  logic [PSI-1:0][R-1:0][MOD_Q_W-1:0]     ntt_acc_data;
  logic                                   ntt_acc_sob;
  logic                                   ntt_acc_eob;
  logic                                   ntt_acc_sol;
  logic                                   ntt_acc_eol;
  logic                                   ntt_acc_sog;
  logic                                   ntt_acc_eog;
  logic [BPBS_ID_W-1:0]                   ntt_acc_pbs_id;

  // Errors and counters
  pep_error_t                             pep_error;
  pep_info_t                              pep_rif_info;
  pep_counter_inc_t                       pep_rif_counter_inc;

  pep_error_t                             pep_otw_error;
  pep_error_t                             pep_ret_error;
  pep_error_t                             pep_modsw_error;

  pep_info_t                              pep_otw_rif_info;
  pep_info_t                              pep_ret_rif_info;
  pep_info_t                              pep_modsw_rif_info;

  pep_counter_inc_t                       pep_otw_rif_counter_inc;
  pep_counter_inc_t                       pep_ret_rif_counter_inc;
  pep_counter_inc_t                       pep_modsw_rif_counter_inc;

// ============================================================================================== --
// Side
// ============================================================================================== --
  pep_error_t                             pep_errorD;
  pep_info_t                              pep_rif_infoD;
  pep_counter_inc_t                       pep_rif_counter_incD;

  assign pep_errorD           = pep_otw_error
                                | pep_ret_error
                                | pep_modsw_error;
  assign pep_rif_infoD        = pep_otw_rif_info
                                | pep_ret_rif_info
                                | pep_modsw_rif_info;
  assign pep_rif_counter_incD = pep_otw_rif_counter_inc
                                | pep_ret_rif_counter_inc
                                | pep_modsw_rif_counter_inc;

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
  assign prev_ret_data       = p3_p2_ntt_proc_data;
  assign prev_ret_data_avail = p3_p2_ntt_proc_avail;
  assign prev_ret_ctrl_avail = p3_p2_ntt_proc_ctrl_avail;

// ============================================================================================== --
// Output
// ============================================================================================== --
  assign p2_p3_ntt_proc_data       = next_otw_data;
  assign p2_p3_ntt_proc_avail      = next_otw_data_avail;
  assign p2_p3_ntt_proc_ctrl_avail = next_otw_ctrl_avail;

  assign pep_rif_elt.error           = pep_error;
  assign pep_rif_elt.rif_info        = pep_rif_info;
  assign pep_rif_elt.rif_counter_inc = pep_rif_counter_inc;

// ============================================================================================== --
// pe_pbs_with_ntt_core_middle : outward
// contains:
// * ntt_core_middle
// ============================================================================================== --
  pe_pbs_with_ntt_core_head
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
    .S_NB                  (MID0_S_NB),
    .USE_PP                (MID0_USE_PP)
  ) pe_pbs_with_ntt_core_head (
    .clk                        (prc_clk),
    .s_rst_n                    (prc_srst_n),

    .twd_omg_ru_r_pow           ('x), /*UNUSED*/

    .br_batch_cmd               (ntt_proc_cmd.batch_cmd),
    .br_batch_cmd_avail         (ntt_proc_cmd_avail),

    .bsk                        ('x), /*UNUSED*/
    .bsk_vld                    ('x), /*UNUSED*/
    .bsk_rdy                    (),   /*UNUSED*/

    .decomp_ntt_data_avail      (decomp_ntt_data_avail),
    .decomp_ntt_data            (decomp_ntt_data),
    .decomp_ntt_sob             (decomp_ntt_sob),
    .decomp_ntt_eob             (decomp_ntt_eob),
    .decomp_ntt_sog             (decomp_ntt_sog),
    .decomp_ntt_eog             (decomp_ntt_eog),
    .decomp_ntt_sol             (decomp_ntt_sol),
    .decomp_ntt_eol             (decomp_ntt_eol),
    .decomp_ntt_pbs_id          (decomp_ntt_pbs_id),
    .decomp_ntt_last_pbs        (decomp_ntt_last_pbs),
    .decomp_ntt_full_throughput (decomp_ntt_full_throughput),
    .decomp_ntt_ctrl_avail      (decomp_ntt_ctrl_avail),
    .decomp_ntt_data_rdy        (/*UNUSED*/),
    .decomp_ntt_ctrl_rdy        (/*UNUSED*/),

    .next_data                  (next_otw_data.data),
    .next_data_avail            (next_otw_data_avail),
    .next_sob                   (next_otw_data.sob),
    .next_eob                   (next_otw_data.eob),
    .next_sol                   (next_otw_data.sol),
    .next_eol                   (next_otw_data.eol),
    .next_sos                   (next_otw_data.sos),
    .next_eos                   (next_otw_data.eos),
    .next_pbs_id                (next_otw_data.pbs_id),
    .next_ctrl_avail            (next_otw_ctrl_avail),

    .pep_error                  (pep_otw_error),
    .pep_rif_info               (pep_otw_rif_info),
    .pep_rif_counter_inc        (pep_otw_rif_counter_inc)
  );

// ============================================================================================== --
// pe_pbs_with_ntt_core_tail : return
// contains:
// * ntt_core_tail
// ============================================================================================== --
  pe_pbs_with_ntt_core_tail
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
    .S_NB                  (MID2_S_NB),
    .USE_PP                (MID2_USE_PP),
    .S_INIT                (MID2_S_INIT)
  ) pe_pbs_with_ntt_core_tail (
    .clk                   (prc_clk),
    .s_rst_n               (prc_srst_n),

    .twd_omg_ru_r_pow      ('x), /*UNUSED*/


    .br_batch_cmd          (ntt_proc_cmd.batch_cmd),
    .br_batch_cmd_avail    (ntt_proc_cmd_avail),

    .bsk                   ('x), /*UNUSED*/
    .bsk_vld               ('x), /*UNUSED*/
    .bsk_rdy               (),   /*UNUSED*/

    .prev_data             (prev_ret_data.data),
    .prev_data_avail       (prev_ret_data_avail),
    .prev_sob              (prev_ret_data.sob),
    .prev_eob              (prev_ret_data.eob),
    .prev_sol              (prev_ret_data.sol),
    .prev_eol              (prev_ret_data.eol),
    .prev_sos              (prev_ret_data.sos),
    .prev_eos              (prev_ret_data.eos),
    .prev_pbs_id           (prev_ret_data.pbs_id),
    .prev_ctrl_avail       (prev_ret_ctrl_avail),

    .ntt_acc_data          (ntt_acc_data),
    .ntt_acc_data_avail    (ntt_acc_data_avail),
    .ntt_acc_sob           (ntt_acc_sob),
    .ntt_acc_eob           (ntt_acc_eob),
    .ntt_acc_sol           (ntt_acc_sol),
    .ntt_acc_eol           (ntt_acc_eol),
    .ntt_acc_sog           (ntt_acc_sog),
    .ntt_acc_eog           (ntt_acc_eog),
    .ntt_acc_pbs_id        (ntt_acc_pbs_id),
    .ntt_acc_ctrl_avail    (ntt_acc_ctrl_avail),

    .pep_error             (pep_ret_error),
    .pep_rif_info          (pep_ret_rif_info),
    .pep_rif_counter_inc   (pep_ret_rif_counter_inc)
  );

// ---------------------------------------------------------------------------------------------- --
// pe_pbs_with_modsw
// contains:
// * mod switch
// ---------------------------------------------------------------------------------------------- --
  pe_pbs_with_modsw
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
  ) pe_pbs_with_modsw (
    .clk                      (prc_clk),
    .s_rst_n                  (prc_srst_n),

    .ntt_acc_data_avail       (ntt_acc_data_avail),
    .ntt_acc_ctrl_avail       (ntt_acc_ctrl_avail),
    .ntt_acc_data             (ntt_acc_data),
    .ntt_acc_sob              (ntt_acc_sob),
    .ntt_acc_eob              (ntt_acc_eob),
    .ntt_acc_sol              (ntt_acc_sol),
    .ntt_acc_eol              (ntt_acc_eol),
    .ntt_acc_sog              (ntt_acc_sog),
    .ntt_acc_eog              (ntt_acc_eog),
    .ntt_acc_pbs_id           (ntt_acc_pbs_id),

    .ntt_acc_modsw_data_avail (ntt_acc_modsw_data_avail),
    .ntt_acc_modsw_ctrl_avail (ntt_acc_modsw_ctrl_avail),
    .ntt_acc_modsw_data       (ntt_acc_modsw_data),
    .ntt_acc_modsw_sob        (ntt_acc_modsw_sob),
    .ntt_acc_modsw_eob        (ntt_acc_modsw_eob),
    .ntt_acc_modsw_sol        (ntt_acc_modsw_sol),
    .ntt_acc_modsw_eol        (ntt_acc_modsw_eol),
    .ntt_acc_modsw_sog        (ntt_acc_modsw_sog),
    .ntt_acc_modsw_eog        (ntt_acc_modsw_eog),
    .ntt_acc_modsw_pbs_id     (ntt_acc_modsw_pbs_id),

    .pep_error                (pep_modsw_error),
    .pep_rif_info             (pep_modsw_rif_info),
    .pep_rif_counter_inc      (pep_modsw_rif_counter_inc)
  );


  // ==============================================================================================
  // multi HPU DMA
  // contains:
  // * control register file for MAC+PCS & GT
  // * axi4-stream switch in order to toggle between each line for RPU connection
  // TODO: WIP
  //
  // initialize axi4 signals ----------------------------------------------------------------------
  // Tie-off m_axi4 unused features
  `HPU_AXI4_TIE_GL_UNUSED(eth_hbm, [ETH_PC-1:0], ETH_PC)

  // /!\ Workaround : simulation AXI4_ETH_HBM_ADD_W may be different from
  // the AXI4_ETH_HBM_ADD_W of the package (= the synthesized value).
  // Use intermediate variable.
  logic [ETH_PC-1:0][axi_if_eth_axi_pkg::AXI4_ADD_W-1:0] m_axi4_eth_hbm_araddr_tmp;
  always_comb
    for (int i=0; i<ETH_PC; i=i+1)
      m_axi4_eth_hbm_araddr[i] = m_axi4_eth_hbm_araddr_tmp[i][AXI4_ETH_HBM_ADD_W-1:0];

// pragma translate_off
  always_ff @(posedge prc_mrmac_clk)
    if (!prc_mrmac_srst_n) begin
      // Do nothing
    end
    else begin
      for (int i=0; i<ETH_PC; i=i+1) begin
        if (m_axi4_eth_hbm_arvalid[i]) begin
          assert(m_axi4_eth_hbm_araddr_tmp[i] >> AXI4_ETH_HBM_ADD_W == '0)
          else begin
            $fatal(1,"%t > ERROR: HBM ETHERNET AXI [%d] address overflows. Simulation supports only %d bits: 0x%0x.",$time, i, AXI4_ETH_HBM_ADD_W, m_axi4_eth_hbm_araddr_tmp[i]);
          end
        end
      end
    end
// pragma translate_on

  logic [ETH_PC-1:0][axi_if_eth_axi_pkg::AXI4_ADD_W-1:0] m_axi4_eth_hbm_awaddr_tmp;
  always_comb
    for (int i=0; i<ETH_PC; i=i+1)
      m_axi4_eth_hbm_awaddr[i] = m_axi4_eth_hbm_awaddr_tmp[i][AXI4_ETH_HBM_ADD_W-1:0];

// pragma translate_off
  always_ff @(posedge prc_mrmac_clk)
    if (!prc_mrmac_srst_n) begin
      // Do nothing
    end
    else begin
      for (int i=0; i<ETH_PC; i=i+1) begin
        if (m_axi4_eth_hbm_arvalid[i]) begin
          assert(m_axi4_eth_hbm_awaddr_tmp[i] >> AXI4_ETH_HBM_ADD_W == '0)
          else begin
            $fatal(1,"%t > ERROR: HBM ETHERNET AXI [%d] address overflows. Simulation supports only %d bits: 0x%0x.",$time, i, AXI4_ETH_HBM_ADD_W, m_axi4_eth_hbm_awaddr_tmp[i]);
          end
        end
      end
    end
// pragma translate_on
  // ==============================================================================================

  // reset for mrmac resyncronized for the two clock frequencies
  logic cfg_eth_srst_n;   // ethernet configuration slow clock
  logic prc_mrmac_srst_n; // mrmac clock at axis speed

  xpm_cdc_single_wrapper #(
    // The frequency of the input signal is extremely low, this should be enough
    .CDC_SYNC_STAGES ( 2 ) ,
    .SRC_INPUT_REG   ( 0 )
  ) sync_cfg_prc_mrmac_slow (
    .src_clk  ( prc_clk           ) ,
    .src_in   ( prc_srst_n        ) ,
    .dest_clk ( mrmac_free_clk    ) ,
    .dest_out ( cfg_eth_srst_n    )
  );

  xpm_cdc_single_wrapper #(
    // The frequency of the input signal is extremely low, this should be enough
    .CDC_SYNC_STAGES ( 2 ) ,
    .SRC_INPUT_REG   ( 0 )
  ) sync_cfg_prc_mrmac_fast (
    .src_clk  ( prc_clk           ) ,
    .src_in   ( prc_srst_n        ) ,
    .dest_clk ( mrmac_free_clk    ) ,
    .dest_out ( prc_mrmac_clk     )
  );

  multi_hpu_dma #(
  ) multi_hpu_dma (
    // System interface
    .clk_eth_cfg            (cfg_eth_clk),
    .resetn_eth_cfg         (cfg_eth_srst_n),
    .clk_eth_mrmac          (prc_mrmac_clk),
    .resetn_eth_mrmac       (prc_mrmac_srst_n),
    // register interface
    .s_axil_dma_awaddr      (s_axil_dma_awaddr),
    .s_axil_dma_awvalid     (s_axil_dma_awvalid),
    .s_axil_dma_awready     (s_axil_dma_awready),
    .s_axil_dma_wdata       (s_axil_dma_wdata),
    .s_axil_dma_wstrb       (s_axil_dma_wstrb),
    .s_axil_dma_wvalid      (s_axil_dma_wvalid),
    .s_axil_dma_wready      (s_axil_dma_wready),
    .s_axil_dma_bresp       (s_axil_dma_bresp),
    .s_axil_dma_bvalid      (s_axil_dma_bvalid),
    .s_axil_dma_bready      (s_axil_dma_bready),
    .s_axil_dma_araddr      (s_axil_dma_araddr),
    .s_axil_dma_arvalid     (s_axil_dma_arvalid),
    .s_axil_dma_arready     (s_axil_dma_arready),
    .s_axil_dma_rdata       (s_axil_dma_rdata),
    .s_axil_dma_rresp       (s_axil_dma_rresp),
    .s_axil_dma_rvalid      (s_axil_dma_rvalid),
    .s_axil_dma_rready      (s_axil_dma_rready),
    // HBM axi4
    `HPU_AXI4_SHORT_INSTANCE(eth_hbm, eth_hbm, _tmp, [ETH_PC-1:0])
    // interrupts
    .interrupt_notify       (interrupt_notify),
    .interrupt_read_request (interrupt_read_request),
    // directly from QSFP axi4-stream
    .qsfp_tx_tdata          (qsfp_tx_tdata),
    .qsfp_tx_tkeep_user     (qsfp_tx_tkeep_user),
    .qsfp_tx_tlast          (qsfp_tx_tlast),
    .qsfp_tx_tvalid         (qsfp_tx_tvalid),
    .qsfp_tx_tready         (qsfp_tx_tready),

    .qsfp_rx_tdata          (qsfp_rx_tdata),
    .qsfp_rx_tkeep_user     (qsfp_rx_tkeep_user),
    .qsfp_rx_tlast          (qsfp_rx_tlast),
    .qsfp_rx_tvalid         (qsfp_rx_tvalid),

    // gt control signals
    .gt_loopback            (gt_loopback),
    .gt_line_rate           (gt_line_rate),
    .gt_reset_rx_datapath   (gt_reset_rx_datapath),
    .gt_reset_tx_datapath   (gt_reset_tx_datapath),
    .gt_reset_all           (gt_reset_all),
    .gt_rx_reset_done       (gt_rx_reset_done),
    .gt_tx_reset_done       (gt_tx_reset_done)
  );

  always_comb begin
    interrupt                          = '0;
    interrupt.mhdma_notify_interrupt   = interrupt_notify;
    interrupt.mhdma_readdone_interrupt = interrupt_read_request;
  end

endmodule
