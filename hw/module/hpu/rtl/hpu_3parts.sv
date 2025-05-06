// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
// HPU top level.
// HPU is split into 3 parts.
// This module is the assembly of all parts.
// Mainly used to ease P&R constraints.
// ==============================================================================================

`include "hpu_io_macro_inc.sv"

module hpu_3parts
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
  parameter int    VERSION_MINOR    = 0,

  // Add pipe on signals between parts.
  parameter int    INTER_PART_PIPE  = 2 // Indicates the number of pipes on signals crossing the SLRs.
                                        // Note that 0 means not used.
)
(
  input  logic                 prc_clk,    // process clock
  input  logic                 prc_srst_n, // synchronous reset

  input  logic                 cfg_clk,    // config clock
  input  logic                 cfg_srst_n, // synchronous reset

  output logic [3:0]           interrupt,

  //== Axi4-lite slave @prc_clk and @cfg_clk
  `HPU_AXIL_IO(prc_1in3,axi_if_shell_axil_pkg)
  `HPU_AXIL_IO(cfg_1in3,axi_if_shell_axil_pkg)
  `HPU_AXIL_IO(prc_3in3,axi_if_shell_axil_pkg)
  `HPU_AXIL_IO(cfg_3in3,axi_if_shell_axil_pkg)

  //== Axi4 trace interface
  `HPU_AXI4_IO(trc, TRC, axi_if_trc_axi_pkg,)

  //== Axi4 PEM interface
  `HPU_AXI4_IO(pem, PEM, axi_if_ct_axi_pkg, [PEM_PC_MAX-1:0])

  //== Axi4 GLWE interface
  `HPU_AXI4_IO(glwe, GLWE, axi_if_glwe_axi_pkg, [GLWE_PC_MAX-1:0])

  //== Axi4 KSK interface
  `HPU_AXI4_IO(ksk, KSK, axi_if_ksk_axi_pkg, [KSK_PC_MAX-1:0])

  //== Axi4 BSK interface
  `HPU_AXI4_IO(bsk, BSK, axi_if_bsk_axi_pkg, [BSK_PC_MAX-1:0])

  //== AXI stream for ISC
  input  logic [PE_INST_W-1:0] isc_dop,
  output logic                 isc_dop_rdy,
  input  logic                 isc_dop_vld,

  output logic [PE_INST_W-1:0] isc_ack,
  input  logic                 isc_ack_rdy,
  output logic                 isc_ack_vld
);

// ============================================================================================== --
// Signals
// ============================================================================================== --
  // -------------------------------------------------------------------------------------------- --
  //-- MMACC : main <-> subs
  // -------------------------------------------------------------------------------------------- --
  // Feed
  mainsubs_feed_cmd_t   in_main_subs_feed_cmd;
  logic                 in_main_subs_feed_cmd_vld;
  logic                 in_main_subs_feed_cmd_rdy;

  mainsubs_feed_data_t  in_main_subs_feed_data;
  logic                 in_main_subs_feed_data_avail;

  mainsubs_feed_part_t  in_main_subs_feed_part;
  logic                 in_main_subs_feed_part_avail;

  mainsubs_feed_cmd_t   out_main_subs_feed_cmd;
  logic                 out_main_subs_feed_cmd_vld;
  logic                 out_main_subs_feed_cmd_rdy;

  mainsubs_feed_data_t  out_main_subs_feed_data;
  logic                 out_main_subs_feed_data_avail;

  mainsubs_feed_part_t  out_main_subs_feed_part;
  logic                 out_main_subs_feed_part_avail;

  // Acc
  subsmain_acc_data_t   in_subs_main_acc_data;
  logic                 in_subs_main_acc_data_avail;

  subsmain_acc_data_t   out_subs_main_acc_data;
  logic                 out_subs_main_acc_data_avail;

  // Sxt
  mainsubs_sxt_cmd_t    in_main_subs_sxt_cmd;
  logic                 in_main_subs_sxt_cmd_vld;
  logic                 in_main_subs_sxt_cmd_rdy;

  subsmain_sxt_data_t   in_subs_main_sxt_data;
  logic                 in_subs_main_sxt_data_vld;
  logic                 in_subs_main_sxt_data_rdy;

  subsmain_sxt_part_t   in_subs_main_sxt_part;
  logic                 in_subs_main_sxt_part_vld;
  logic                 in_subs_main_sxt_part_rdy;

  mainsubs_sxt_cmd_t    out_main_subs_sxt_cmd;
  logic                 out_main_subs_sxt_cmd_vld;
  logic                 out_main_subs_sxt_cmd_rdy;

  subsmain_sxt_data_t   out_subs_main_sxt_data;
  logic                 out_subs_main_sxt_data_vld;
  logic                 out_subs_main_sxt_data_rdy;

  subsmain_sxt_part_t   out_subs_main_sxt_part;
  logic                 out_subs_main_sxt_part_vld;
  logic                 out_subs_main_sxt_part_rdy;

  //-- LDG
  mainsubs_ldg_cmd_t    in_main_subs_ldg_cmd;
  logic                 in_main_subs_ldg_cmd_vld;
  logic                 in_main_subs_ldg_cmd_rdy;

  mainsubs_ldg_data_t   in_main_subs_ldg_data;
  logic                 in_main_subs_ldg_data_vld;
  logic                 in_main_subs_ldg_data_rdy;

  mainsubs_ldg_cmd_t    out_main_subs_ldg_cmd;
  logic                 out_main_subs_ldg_cmd_vld;
  logic                 out_main_subs_ldg_cmd_rdy;

  mainsubs_ldg_data_t   out_main_subs_ldg_data;
  logic                 out_main_subs_ldg_data_vld;
  logic                 out_main_subs_ldg_data_rdy;
  //-- MMACC Misc
  mainsubs_side_t       in_main_subs_side;
  subsmain_side_t       in_subs_main_side;

  mainsubs_side_t       out_main_subs_side;
  subsmain_side_t       out_subs_main_side;
  // -------------------------------------------------------------------------------------------- --
  //-- BSK : entry <-> bsk
  // -------------------------------------------------------------------------------------------- --
  entrybsk_proc_t       in_entry_bsk_proc;
  bskentry_proc_t       in_bsk_entry_proc;

  entrybsk_proc_t       out_entry_bsk_proc;
  bskentry_proc_t       out_bsk_entry_proc;
  // -------------------------------------------------------------------------------------------- --
  //-- NTT processing path
  // -------------------------------------------------------------------------------------------- --
  //== Cmd path
  ntt_proc_cmd_t         in_ntt_proc_cmd;
  logic                  in_ntt_proc_cmd_avail;

  ntt_proc_cmd_t         out_ntt_proc_cmd;
  logic                  out_ntt_proc_cmd_avail;

  //== Data path
  ntt_proc_data_t        in_p2_p3_ntt_proc_data;
  logic [PSI-1:0][R-1:0] in_p2_p3_ntt_proc_avail;
  logic                  in_p2_p3_ntt_proc_ctrl_avail;

  ntt_proc_data_t        in_p3_p2_ntt_proc_data;
  logic [PSI-1:0][R-1:0] in_p3_p2_ntt_proc_avail;
  logic                  in_p3_p2_ntt_proc_ctrl_avail;

  ntt_proc_data_t        out_p2_p3_ntt_proc_data;
  logic [PSI-1:0][R-1:0] out_p2_p3_ntt_proc_avail;
  logic                  out_p2_p3_ntt_proc_ctrl_avail;

  ntt_proc_data_t        out_p3_p2_ntt_proc_data;
  logic [PSI-1:0][R-1:0] out_p3_p2_ntt_proc_avail;
  logic                  out_p3_p2_ntt_proc_ctrl_avail;

  // -------------------------------------------------------------------------------------------- --
  //-- To regif
  // -------------------------------------------------------------------------------------------- --
  pep_rif_elt_t          in_p2_p3_pep_rif_elt;

  pep_rif_elt_t          out_p2_p3_pep_rif_elt;

  // -------------------------------------------------------------------------------------------- --
  //-- Interrupt
  // -------------------------------------------------------------------------------------------- --
  logic                  in_p1_prc_interrupt;
  logic                  in_p1_cfg_interrupt;
  logic                  in_p3_prc_interrupt;
  logic                  in_p3_cfg_interrupt;

  logic                  out_p1_prc_interrupt;
  logic                  out_p1_cfg_interrupt;
  logic                  out_p3_prc_interrupt;
  logic                  out_p3_cfg_interrupt;

// ============================================================================================== --
// Interrupts // TOREVIEW
// ============================================================================================== --
  assign interrupt = {out_p3_cfg_interrupt,
                      out_p3_prc_interrupt,
                      out_p1_cfg_interrupt,
                      out_p1_prc_interrupt};

// ============================================================================================== --
// Inter part pipes
// ============================================================================================== --
  assign out_main_subs_feed_cmd         = in_main_subs_feed_cmd;
  assign out_main_subs_feed_cmd_vld     = in_main_subs_feed_cmd_vld;
  assign in_main_subs_feed_cmd_rdy      = out_main_subs_feed_cmd_rdy;

  assign out_main_subs_feed_data        = in_main_subs_feed_data;
  assign out_main_subs_feed_data_avail  = in_main_subs_feed_data_avail;

  assign out_main_subs_feed_part        = in_main_subs_feed_part;
  assign out_main_subs_feed_part_avail  = in_main_subs_feed_part_avail;

  assign out_subs_main_acc_data         = in_subs_main_acc_data;
  assign out_subs_main_acc_data_avail   = in_subs_main_acc_data_avail;

  assign out_main_subs_sxt_cmd          = in_main_subs_sxt_cmd;
  assign out_main_subs_sxt_cmd_vld      = in_main_subs_sxt_cmd_vld;
  assign in_main_subs_sxt_cmd_rdy       = out_main_subs_sxt_cmd_rdy;

  assign out_subs_main_sxt_data         = in_subs_main_sxt_data;
  assign out_subs_main_sxt_data_vld     = in_subs_main_sxt_data_vld;
  assign in_subs_main_sxt_data_rdy      = out_subs_main_sxt_data_rdy;

  assign out_subs_main_sxt_part         = in_subs_main_sxt_part;
  assign out_subs_main_sxt_part_vld     = in_subs_main_sxt_part_vld;
  assign in_subs_main_sxt_part_rdy      = out_subs_main_sxt_part_rdy;

  assign out_main_subs_ldg_cmd          = in_main_subs_ldg_cmd;
  assign out_main_subs_ldg_cmd_vld      = in_main_subs_ldg_cmd_vld;
  assign in_main_subs_ldg_cmd_rdy       = out_main_subs_ldg_cmd_rdy;

  assign out_main_subs_ldg_data         = in_main_subs_ldg_data;
  assign out_main_subs_ldg_data_vld     = in_main_subs_ldg_data_vld;
  assign in_main_subs_ldg_data_rdy      = out_main_subs_ldg_data_rdy;

  assign out_main_subs_side             = in_main_subs_side;
  assign out_subs_main_side             = in_subs_main_side;


  generate
    if (INTER_PART_PIPE > 0) begin : gen_inter_part_pipe
      //-- BSK : entry <-> bsk
      entrybsk_proc_t        out_entry_bsk_procD;
      bskentry_proc_t        out_bsk_entry_procD;

      //-- NTT processing path
      //== Cmd path
      ntt_proc_cmd_t         out_ntt_proc_cmdD;
      logic                  out_ntt_proc_cmd_availD;

      //== Data path
      ntt_proc_data_t        out_p2_p3_ntt_proc_dataD;
      logic [PSI-1:0][R-1:0] out_p2_p3_ntt_proc_availD;
      logic                  out_p2_p3_ntt_proc_ctrl_availD;

      ntt_proc_data_t        out_p3_p2_ntt_proc_dataD;
      logic [PSI-1:0][R-1:0] out_p3_p2_ntt_proc_availD;
      logic                  out_p3_p2_ntt_proc_ctrl_availD;

      //-- To regif
      pep_rif_elt_t          out_p2_p3_pep_rif_eltD;

      // No backpressure
      always_ff @(posedge prc_clk)
        if (!prc_srst_n) begin
          out_entry_bsk_proc               <= '0;
          out_bsk_entry_proc               <= '0;
          out_ntt_proc_cmd_avail           <= '0;
          out_p2_p3_ntt_proc_avail         <= '0;
          out_p2_p3_ntt_proc_ctrl_avail    <= '0;
          out_p3_p2_ntt_proc_avail         <= '0;
          out_p3_p2_ntt_proc_ctrl_avail    <= '0;
          out_p2_p3_pep_rif_elt            <= '0;
          out_p1_prc_interrupt             <= '0;
          out_p3_prc_interrupt             <= '0;
        end
        else begin
          out_entry_bsk_proc               <= out_entry_bsk_procD;
          out_bsk_entry_proc               <= out_bsk_entry_procD;
          out_ntt_proc_cmd_avail           <= out_ntt_proc_cmd_availD;
          out_p2_p3_ntt_proc_avail         <= out_p2_p3_ntt_proc_availD;
          out_p2_p3_ntt_proc_ctrl_avail    <= out_p2_p3_ntt_proc_ctrl_availD;
          out_p3_p2_ntt_proc_avail         <= out_p3_p2_ntt_proc_availD;
          out_p3_p2_ntt_proc_ctrl_avail    <= out_p3_p2_ntt_proc_ctrl_availD;
          out_p2_p3_pep_rif_elt            <= out_p2_p3_pep_rif_eltD;
          out_p1_prc_interrupt             <= out_p1_prc_interrupt;
          out_p3_prc_interrupt             <= out_p3_prc_interrupt;
        end

      always_ff @(posedge prc_clk) begin
        out_ntt_proc_cmd           <= out_ntt_proc_cmdD;
        out_p2_p3_ntt_proc_data    <= out_p2_p3_ntt_proc_dataD;
        out_p3_p2_ntt_proc_data    <= out_p3_p2_ntt_proc_dataD;
      end

      always_ff @(posedge cfg_clk)
        if (!cfg_srst_n) begin
          out_p1_cfg_interrupt <= '0;
          out_p3_cfg_interrupt <= '0;
        end
        else begin
          out_p1_cfg_interrupt <= in_p1_cfg_interrupt;
          out_p3_cfg_interrupt <= in_p3_cfg_interrupt;
        end


      if (INTER_PART_PIPE == 1) begin
        assign out_entry_bsk_procD            = in_entry_bsk_proc;
        assign out_bsk_entry_procD            = in_bsk_entry_proc;

        assign out_ntt_proc_cmdD              = in_ntt_proc_cmd;
        assign out_ntt_proc_cmd_availD        = in_ntt_proc_cmd_avail;

        assign out_p2_p3_ntt_proc_dataD       = in_p2_p3_ntt_proc_data;
        assign out_p2_p3_ntt_proc_availD      = in_p2_p3_ntt_proc_avail;
        assign out_p2_p3_ntt_proc_ctrl_availD = in_p2_p3_ntt_proc_ctrl_avail;

        assign out_p3_p2_ntt_proc_dataD       = in_p3_p2_ntt_proc_data;
        assign out_p3_p2_ntt_proc_availD      = in_p3_p2_ntt_proc_avail;
        assign out_p3_p2_ntt_proc_ctrl_availD = in_p3_p2_ntt_proc_ctrl_avail;

        assign out_p2_p3_pep_rif_eltD         = in_p2_p3_pep_rif_elt;

      end
      else if (INTER_PART_PIPE == 2) begin
        //-- BSK : entry <-> bsk
        entrybsk_proc_t        in_entry_bsk_proc_dly;
        bskentry_proc_t        in_bsk_entry_proc_dly;

        //-- NTT processing path
        //== Cmd path
        ntt_proc_cmd_t         in_ntt_proc_cmd_dly;
        logic                  in_ntt_proc_cmd_avail_dly;

        //== Data path
        ntt_proc_data_t        in_p2_p3_ntt_proc_data_dly;
        logic [PSI-1:0][R-1:0] in_p2_p3_ntt_proc_avail_dly;
        logic                  in_p2_p3_ntt_proc_ctrl_avail_dly;

        ntt_proc_data_t        in_p3_p2_ntt_proc_data_dly;
        logic [PSI-1:0][R-1:0] in_p3_p2_ntt_proc_avail_dly;
        logic                  in_p3_p2_ntt_proc_ctrl_avail_dly;

        //-- To regif
        pep_rif_elt_t          in_p2_p3_pep_rif_elt_dly;

        assign out_entry_bsk_procD            = in_entry_bsk_proc_dly;
        assign out_bsk_entry_procD            = in_bsk_entry_proc_dly;

        assign out_ntt_proc_cmdD              = in_ntt_proc_cmd_dly;
        assign out_ntt_proc_cmd_availD        = in_ntt_proc_cmd_avail_dly;

        assign out_p2_p3_ntt_proc_dataD       = in_p2_p3_ntt_proc_data_dly;
        assign out_p2_p3_ntt_proc_availD      = in_p2_p3_ntt_proc_avail_dly;
        assign out_p2_p3_ntt_proc_ctrl_availD = in_p2_p3_ntt_proc_ctrl_avail_dly;

        assign out_p3_p2_ntt_proc_dataD       = in_p3_p2_ntt_proc_data_dly;
        assign out_p3_p2_ntt_proc_availD      = in_p3_p2_ntt_proc_avail_dly;
        assign out_p3_p2_ntt_proc_ctrl_availD = in_p3_p2_ntt_proc_ctrl_avail_dly;

        always_ff @(posedge prc_clk)
          if (!prc_srst_n) begin
            in_p2_p3_ntt_proc_avail_dly      <= '0;
            in_p2_p3_ntt_proc_ctrl_avail_dly <= '0;
            in_p3_p2_ntt_proc_avail_dly      <= '0;
            in_p3_p2_ntt_proc_ctrl_avail_dly <= '0;
            in_ntt_proc_cmd_avail_dly        <= '0;
            in_entry_bsk_proc_dly            <= '0;
            in_bsk_entry_proc_dly            <= '0;
            in_p2_p3_pep_rif_elt_dly         <= '0;
          end
          else begin
            in_p2_p3_ntt_proc_avail_dly      <= in_p2_p3_ntt_proc_avail     ;
            in_p2_p3_ntt_proc_ctrl_avail_dly <= in_p2_p3_ntt_proc_ctrl_avail;
            in_p3_p2_ntt_proc_avail_dly      <= in_p3_p2_ntt_proc_avail     ;
            in_p3_p2_ntt_proc_ctrl_avail_dly <= in_p3_p2_ntt_proc_ctrl_avail;
            in_ntt_proc_cmd_avail_dly        <= in_ntt_proc_cmd_avail;
            in_entry_bsk_proc_dly            <= in_entry_bsk_proc;
            in_bsk_entry_proc_dly            <= in_bsk_entry_proc;
            in_p2_p3_pep_rif_elt_dly         <= in_p2_p3_pep_rif_elt;
          end

        always_ff @(posedge prc_clk) begin
          in_p2_p3_ntt_proc_data_dly <= in_p2_p3_ntt_proc_data;
          in_p3_p2_ntt_proc_data_dly <= in_p3_p2_ntt_proc_data;
          in_ntt_proc_cmd_dly        <= in_ntt_proc_cmd;
        end
      end
      else begin
        $fatal(1,"> ERROR: Unsupported INTER_PART_PIPE (%0d) > 2", INTER_PART_PIPE);
      end

    end
    else begin : gen_no_inter_part_pipe
      assign out_entry_bsk_proc             = in_entry_bsk_proc;
      assign out_bsk_entry_proc             = in_bsk_entry_proc;

      assign out_ntt_proc_cmd               = in_ntt_proc_cmd;
      assign out_ntt_proc_cmd_avail         = in_ntt_proc_cmd_avail;

      assign out_p2_p3_ntt_proc_data        = in_p2_p3_ntt_proc_data;
      assign out_p2_p3_ntt_proc_avail       = in_p2_p3_ntt_proc_avail;
      assign out_p2_p3_ntt_proc_ctrl_avail  = in_p2_p3_ntt_proc_ctrl_avail;

      assign out_p3_p2_ntt_proc_data        = in_p3_p2_ntt_proc_data;
      assign out_p3_p2_ntt_proc_avail       = in_p3_p2_ntt_proc_avail;
      assign out_p3_p2_ntt_proc_ctrl_avail  = in_p3_p2_ntt_proc_ctrl_avail;

      assign out_p2_p3_pep_rif_elt          = in_p2_p3_pep_rif_elt;

      assign out_p1_prc_interrupt           = in_p1_prc_interrupt;
      assign out_p1_cfg_interrupt           = in_p1_cfg_interrupt;
      assign out_p3_prc_interrupt           = in_p3_prc_interrupt;
      assign out_p3_cfg_interrupt           = in_p3_cfg_interrupt;
    end
  endgenerate

// ============================================================================================== --
// Tie unused AXI channels
// ============================================================================================== --
  generate
    if (PEM_PC < PEM_PC_MAX) begin : gen_tie_unused_pem_pc
      `HPU_AXI4_TIE_WR_UNUSED(pem, [PEM_PC_MAX-1:PEM_PC])
      `HPU_AXI4_TIE_RD_UNUSED(pem, [PEM_PC_MAX-1:PEM_PC])
    end
    if (GLWE_PC < GLWE_PC_MAX) begin : gen_tie_unused_glwe_pc
      `HPU_AXI4_TIE_WR_UNUSED(glwe, [GLWE_PC_MAX-1:GLWE_PC])
      `HPU_AXI4_TIE_RD_UNUSED(glwe, [GLWE_PC_MAX-1:GLWE_PC])
    end
    if (BSK_PC < BSK_PC_MAX) begin : gen_tie_unused_bsk_pc
      `HPU_AXI4_TIE_WR_UNUSED(bsk, [BSK_PC_MAX-1:BSK_PC])
      `HPU_AXI4_TIE_RD_UNUSED(bsk, [BSK_PC_MAX-1:BSK_PC])
    end
    if (KSK_PC < KSK_PC_MAX) begin : gen_tie_unused_ksk_pc
      `HPU_AXI4_TIE_WR_UNUSED(ksk, [KSK_PC_MAX-1:KSK_PC])
      `HPU_AXI4_TIE_RD_UNUSED(ksk, [KSK_PC_MAX-1:KSK_PC])
    end
  endgenerate

// ============================================================================================== --
// hpu_3parts_1in3
// ============================================================================================== --
  hpu_3parts_1in3_core
  #(
    .AXI4_TRC_ADD_W    (AXI4_TRC_ADD_W),
    .AXI4_PEM_ADD_W    (AXI4_PEM_ADD_W),
    .AXI4_GLWE_ADD_W   (AXI4_GLWE_ADD_W),
    .AXI4_KSK_ADD_W    (AXI4_KSK_ADD_W),
    .VERSION_MAJOR     (VERSION_MAJOR),
    .VERSION_MINOR     (VERSION_MINOR)
  ) hpu_3parts_1in3_core (
    .prc_clk                 (prc_clk),
    .prc_srst_n              (prc_srst_n),

    .cfg_clk                 (cfg_clk),
    .cfg_srst_n              (cfg_srst_n),

    .interrupt                ({in_p1_cfg_interrupt,in_p1_prc_interrupt}),

    //== Axi4-lite slave @prc_clk and @cfg_clk
    `HPU_AXIL_INSTANCE(prc,prc_1in3)
    `HPU_AXIL_INSTANCE(cfg,cfg_1in3)

    //== Axi4 trace interface
    `HPU_AXI4_FULL_INSTANCE(trc, trc,,)

    //== Axi4 PEM interface
    `HPU_AXI4_FULL_INSTANCE(pem, pem,,[PEM_PC-1:0])

    //== Axi4 GLWE interface
    `HPU_AXI4_FULL_INSTANCE(glwe, glwe,,[GLWE_PC-1:0])

    //== Axi4 KSK interface
    `HPU_AXI4_FULL_INSTANCE(ksk, ksk,,[KSK_PC-1:0])

    .isc_dop                   (isc_dop),
    .isc_dop_rdy               (isc_dop_rdy),
    .isc_dop_vld               (isc_dop_vld),

    .isc_ack                   (isc_ack),
    .isc_ack_rdy               (isc_ack_rdy),
    .isc_ack_vld               (isc_ack_vld),

    .main_subs_feed_cmd        (in_main_subs_feed_cmd),
    .main_subs_feed_cmd_vld    (in_main_subs_feed_cmd_vld),
    .main_subs_feed_cmd_rdy    (in_main_subs_feed_cmd_rdy),

    .main_subs_feed_data       (in_main_subs_feed_data),
    .main_subs_feed_data_avail (in_main_subs_feed_data_avail),

    .main_subs_feed_part       (in_main_subs_feed_part),
    .main_subs_feed_part_avail (in_main_subs_feed_part_avail),

    .subs_main_acc_data        (out_subs_main_acc_data),
    .subs_main_acc_data_avail  (out_subs_main_acc_data_avail),

    .main_subs_sxt_cmd         (in_main_subs_sxt_cmd),
    .main_subs_sxt_cmd_vld     (in_main_subs_sxt_cmd_vld),
    .main_subs_sxt_cmd_rdy     (in_main_subs_sxt_cmd_rdy),

    .subs_main_sxt_data        (out_subs_main_sxt_data),
    .subs_main_sxt_data_vld    (out_subs_main_sxt_data_vld),
    .subs_main_sxt_data_rdy    (out_subs_main_sxt_data_rdy),

    .subs_main_sxt_part        (out_subs_main_sxt_part),
    .subs_main_sxt_part_vld    (out_subs_main_sxt_part_vld),
    .subs_main_sxt_part_rdy    (out_subs_main_sxt_part_rdy),

    .main_subs_ldg_cmd         (in_main_subs_ldg_cmd),
    .main_subs_ldg_cmd_vld     (in_main_subs_ldg_cmd_vld),
    .main_subs_ldg_cmd_rdy     (in_main_subs_ldg_cmd_rdy),

    .main_subs_ldg_data        (in_main_subs_ldg_data),
    .main_subs_ldg_data_vld    (in_main_subs_ldg_data_vld),
    .main_subs_ldg_data_rdy    (in_main_subs_ldg_data_rdy),

    .main_subs_side            (in_main_subs_side),
    .subs_main_side            (out_subs_main_side),

    .entry_bsk_proc            (in_entry_bsk_proc),
    .bsk_entry_proc            (out_bsk_entry_proc),

    .ntt_proc_cmd              (in_ntt_proc_cmd),
    .ntt_proc_cmd_avail        (in_ntt_proc_cmd_avail)
  );

// ============================================================================================== --
// hpu_3parts_2in3
// ============================================================================================== --
  hpu_3parts_2in3_core
  #(
    .AXI4_TRC_ADD_W    (AXI4_TRC_ADD_W),
    .AXI4_PEM_ADD_W    (AXI4_PEM_ADD_W),
    .AXI4_GLWE_ADD_W   (AXI4_GLWE_ADD_W),
    .AXI4_BSK_ADD_W    (AXI4_BSK_ADD_W),
    .AXI4_KSK_ADD_W    (AXI4_KSK_ADD_W),

    .VERSION_MAJOR     (VERSION_MAJOR),
    .VERSION_MINOR     (VERSION_MINOR)
  ) hpu_3parts_2in3_core (
    .prc_clk                    (prc_clk),
    .prc_srst_n                 (prc_srst_n),

    .cfg_clk                    (cfg_clk),
    .cfg_srst_n                 (cfg_srst_n),

    .main_subs_feed_cmd         (out_main_subs_feed_cmd),
    .main_subs_feed_cmd_vld     (out_main_subs_feed_cmd_vld),
    .main_subs_feed_cmd_rdy     (out_main_subs_feed_cmd_rdy),

    .main_subs_feed_data        (out_main_subs_feed_data),
    .main_subs_feed_data_avail  (out_main_subs_feed_data_avail),

    .main_subs_feed_part        (out_main_subs_feed_part),
    .main_subs_feed_part_avail  (out_main_subs_feed_part_avail),

    .subs_main_acc_data         (in_subs_main_acc_data),
    .subs_main_acc_data_avail   (in_subs_main_acc_data_avail),

    .main_subs_sxt_cmd          (out_main_subs_sxt_cmd),
    .main_subs_sxt_cmd_vld      (out_main_subs_sxt_cmd_vld),
    .main_subs_sxt_cmd_rdy      (out_main_subs_sxt_cmd_rdy),

    .subs_main_sxt_data         (in_subs_main_sxt_data),
    .subs_main_sxt_data_vld     (in_subs_main_sxt_data_vld),
    .subs_main_sxt_data_rdy     (in_subs_main_sxt_data_rdy),

    .subs_main_sxt_part         (in_subs_main_sxt_part),
    .subs_main_sxt_part_vld     (in_subs_main_sxt_part_vld),
    .subs_main_sxt_part_rdy     (in_subs_main_sxt_part_rdy),

    .main_subs_ldg_cmd          (out_main_subs_ldg_cmd),
    .main_subs_ldg_cmd_vld      (out_main_subs_ldg_cmd_vld),
    .main_subs_ldg_cmd_rdy      (out_main_subs_ldg_cmd_rdy),

    .main_subs_ldg_data         (out_main_subs_ldg_data),
    .main_subs_ldg_data_vld     (out_main_subs_ldg_data_vld),
    .main_subs_ldg_data_rdy     (out_main_subs_ldg_data_rdy),

    .subs_main_side             (in_subs_main_side),
    .main_subs_side             (out_main_subs_side),

    .p2_p3_ntt_proc_data        (in_p2_p3_ntt_proc_data),
    .p2_p3_ntt_proc_avail       (in_p2_p3_ntt_proc_avail),
    .p2_p3_ntt_proc_ctrl_avail  (in_p2_p3_ntt_proc_ctrl_avail),

    .p3_p2_ntt_proc_data        (out_p3_p2_ntt_proc_data),
    .p3_p2_ntt_proc_avail       (out_p3_p2_ntt_proc_avail),
    .p3_p2_ntt_proc_ctrl_avail  (out_p3_p2_ntt_proc_ctrl_avail),

    .ntt_proc_cmd               (out_ntt_proc_cmd),
    .ntt_proc_cmd_avail         (out_ntt_proc_cmd_avail),

    .pep_rif_elt                (in_p2_p3_pep_rif_elt)
  );

// ============================================================================================== --
// hpu_3parts_3in3
// ============================================================================================== --
  hpu_3parts_3in3_core
  #(
    .AXI4_TRC_ADD_W    (AXI4_TRC_ADD_W),
    .AXI4_PEM_ADD_W    (AXI4_PEM_ADD_W),
    .AXI4_GLWE_ADD_W   (AXI4_GLWE_ADD_W),
    .AXI4_BSK_ADD_W    (AXI4_BSK_ADD_W),
    .AXI4_KSK_ADD_W    (AXI4_KSK_ADD_W),

    .VERSION_MAJOR     (VERSION_MAJOR),
    .VERSION_MINOR     (VERSION_MINOR)
  ) hpu_3parts_3in3_core (
    .prc_clk                  (prc_clk),
    .prc_srst_n               (prc_srst_n),

    .cfg_clk                  (cfg_clk),
    .cfg_srst_n               (cfg_srst_n),

    .interrupt                ({in_p3_cfg_interrupt,in_p3_prc_interrupt}),

    //== Axi4-lite slave @prc_clk and @cfg_clk
    `HPU_AXIL_INSTANCE(prc,prc_3in3)
    `HPU_AXIL_INSTANCE(cfg,cfg_3in3)

    //== Axi4 BSK interface
    `HPU_AXI4_FULL_INSTANCE(bsk, bsk,,[BSK_PC-1:0])

    .p2_p3_ntt_proc_data       (out_p2_p3_ntt_proc_data),
    .p2_p3_ntt_proc_avail      (out_p2_p3_ntt_proc_avail),
    .p2_p3_ntt_proc_ctrl_avail (out_p2_p3_ntt_proc_ctrl_avail),

    .p3_p2_ntt_proc_data       (in_p3_p2_ntt_proc_data),
    .p3_p2_ntt_proc_avail      (in_p3_p2_ntt_proc_avail),
    .p3_p2_ntt_proc_ctrl_avail (in_p3_p2_ntt_proc_ctrl_avail),

    .ntt_proc_cmd              (out_ntt_proc_cmd),
    .ntt_proc_cmd_avail        (out_ntt_proc_cmd_avail),

    .entry_bsk_proc            (out_entry_bsk_proc),
    .bsk_entry_proc            (in_bsk_entry_proc),

    .p2_p3_pep_rif_elt         (out_p2_p3_pep_rif_elt)
  );

endmodule
