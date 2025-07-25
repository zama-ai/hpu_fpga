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
  input  logic                 prc_free_clk,    // free running process clock
  input  logic                 prc_free_srst_n, // free running process clock reset

  input  logic                 prc_clk,         // gated process clock
  output logic                 prc_ce,          // gated process clock enable
  output logic                 prc_srst_n,      // gated process clock reset

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
  //-- NTT : ntt <-> mmacc
  // -------------------------------------------------------------------------------------------- --
  p1_p2_sll_data_t     in_p1_p2_sll_data;
  p1_p2_sll_data_t     out_p1_p2_sll_data;
  p1_p2_sll_ctrl_t     in_p1_p2_sll_ctrl;
  p1_p2_sll_ctrl_t     out_p1_p2_sll_ctrl;

  p2_p1_sll_data_t     in_p2_p1_sll_data;
  p2_p1_sll_ctrl_t     in_p2_p1_sll_ctrl;
  p2_p1_sll_data_t     out_p2_p1_sll_data;
  p2_p1_sll_ctrl_t     out_p2_p1_sll_ctrl;

  // -------------------------------------------------------------------------------------------- --
  //-- NTT processing path
  // -------------------------------------------------------------------------------------------- --
  //== Data path
  p2_p3_sll_data_t       in_p2_p3_sll_data;
  p2_p3_sll_data_t       out_p2_p3_sll_data;
  p3_p2_sll_data_t       in_p3_p2_sll_data;
  p3_p2_sll_data_t       out_p3_p2_sll_data;

  //== Control
  p2_p3_sll_ctrl_t       in_p2_p3_sll_ctrl;
  p2_p3_sll_ctrl_t       out_p2_p3_sll_ctrl;
  p3_p2_sll_ctrl_t       in_p3_p2_sll_ctrl;
  p3_p2_sll_ctrl_t       out_p3_p2_sll_ctrl;

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
// Daisy chain the reset signals to be able to pin the reset root to different SLRs
// ============================================================================================== --
  logic [2:0] prc_srst_n_part;
  logic [1:0] prc_rst_sll;
  logic       hpu_reset;
  logic       hpu_reset_done;
  logic       soft_prc_srst_n;
  logic       global_rst;

  hpu_soft_reset
  hpu_soft_reset (
    .cfg_clk         ( cfg_clk            ) ,
    .cfg_srst_n      ( cfg_srst_n         ) ,
    .prc_free_clk    ( prc_free_clk       ) ,
    .prc_free_srst_n ( prc_free_srst_n    ) ,
    .prc_clk         ( prc_clk            ) ,
    .prc_srst_n      ( prc_srst_n_part[2] ) ,
    .hpu_reset       ( hpu_reset          ) ,
    .hpu_reset_done  ( hpu_reset_done     ) ,
    .soft_prc_srst_n ( soft_prc_srst_n    )
  );

  assign global_rst = prc_free_srst_n & soft_prc_srst_n;

  fpga_clock_reset #(
    .RST_POL         ( 1'b0                  ) ,
    .INTER_PART_PIPE ( INTER_PART_PIPE       ) ,
    .INTRA_PART_PIPE ( 2*INTER_PART_PIPE + 1 ) // To match the latency of the other resets
  ) prc3_clk_rst (
    .clk_in  ( prc_free_clk       ) ,
    .rst_in  ( global_rst         ) ,
    .rst_nxt ( prc_rst_sll[0]     ) ,
    .clk_en  ( prc_ce             ) ,
    .rst_out ( prc_srst_n_part[2] )
  );

  fpga_clock_reset #(
    .RST_POL         ( 1'b0                ) ,
    .INTER_PART_PIPE ( INTER_PART_PIPE     ) ,
    .INTRA_PART_PIPE ( INTER_PART_PIPE + 1 ) // To match the latency of the other resets
  ) prc2_clk_rst (
    .clk_in  ( prc_free_clk       ) ,
    .rst_in  ( prc_rst_sll[0]     ) ,
    .rst_nxt ( prc_rst_sll[1]     ) ,
    .clk_en  ( /*UNUSED*/         ) ,
    .rst_out ( prc_srst_n_part[1] )
  );

  fpga_clock_reset #(
    .RST_POL         ( 1'b0  ) ,
    .INTER_PART_PIPE ( 0     ) ,
    .INTRA_PART_PIPE ( 1     ) // To match the latency of the other resets
  ) prc1_clk_rst (
    .clk_in  ( prc_free_clk       ) ,
    .rst_in  ( prc_rst_sll[1]     ) ,
    .rst_nxt ( /*UNUSED*/         ) ,
    .clk_en  ( /*UNUSED*/         ) ,
    .rst_out ( prc_srst_n_part[0] )
  );

  assign prc_srst_n = prc_srst_n_part[2];

//=====================================
// Fifo element
//=====================================
  // These belong to SLR2, where the ISC is placed. The NOC slave is very close to it already

  logic [31:0] s1_isc_dop;
  logic        s1_isc_dop_vld;
  logic        s1_isc_dop_rdy;
  fifo_element #(
  .WIDTH          (32),
  .DEPTH          (1),
  .TYPE_ARRAY     (4'h3),
  .DO_RESET_DATA  (0),
  .RESET_DATA_VAL (0)
  ) fifo_element_isc_dop (
    .clk     (prc_clk),
    .s_rst_n (prc_srst_n_part[0]),

    .in_data (isc_dop),
    .in_vld  (isc_dop_vld),
    .in_rdy  (isc_dop_rdy),

    .out_data(s1_isc_dop),
    .out_vld (s1_isc_dop_vld),
    .out_rdy (s1_isc_dop_rdy)
  );

  logic [31:0] s1_isc_ack;
  logic        s1_isc_ack_vld;
  logic        s1_isc_ack_rdy;
  fifo_element #(
  .WIDTH          (32),
  .DEPTH          (1),
  .TYPE_ARRAY     (4'h3),
  .DO_RESET_DATA  (0),
  .RESET_DATA_VAL (0)
  ) fifo_element_isc_ack (
    .clk     (prc_clk),
    .s_rst_n (prc_srst_n_part[0]),

    .in_data (s1_isc_ack),
    .in_vld  (s1_isc_ack_vld),
    .in_rdy  (s1_isc_ack_rdy),

    .out_data (isc_ack),
    .out_vld  (isc_ack_vld),
    .out_rdy  (isc_ack_rdy)
  );

// ============================================================================================== --
// Inter part pipes
// ============================================================================================== --
// Note: Increasing inter part pipe here will increase the NTT and, consequently, PBS latency
  localparam int unsigned SLL_IN_PIPE  = INTER_PART_PIPE/2 + INTER_PART_PIPE % 2;
  localparam int unsigned SLL_OUT_PIPE = INTER_PART_PIPE/2;

  hpu_qual_sll #(
    .IN_DEPTH    ( SLL_IN_PIPE                 ) ,
    .OUT_DEPTH   ( SLL_OUT_PIPE                ) ,
    .DATA_WIDTH  ( $bits(p1_p2_sll_data_t)     ) ,
    .CTRL_WIDTH  ( $bits(p1_p2_sll_ctrl_t)     ) ,
    .CTRL_RST    ( $bits(p1_p2_sll_ctrl_t)'(0) )
  ) p1_p2_sll (
    .in_clk      ( prc_clk            ) ,
    .in_s_rst_n  ( prc_srst_n_part[0] ) ,
    .in_data     ( in_p1_p2_sll_data  ) ,
    .in_ctrl     ( in_p1_p2_sll_ctrl  ) ,
    .out_clk     ( prc_clk            ) ,
    .out_s_rst_n ( prc_srst_n_part[1] ) ,
    .out_data    ( out_p1_p2_sll_data ) ,
    .out_ctrl    ( out_p1_p2_sll_ctrl )
  );

  hpu_qual_sll #(
    .IN_DEPTH    ( SLL_IN_PIPE                 ) ,
    .OUT_DEPTH   ( SLL_OUT_PIPE                ) ,
    .DATA_WIDTH  ( $bits(p2_p1_sll_data_t)     ) ,
    .CTRL_WIDTH  ( $bits(p2_p1_sll_ctrl_t)     ) ,
    .CTRL_RST    ( $bits(p2_p1_sll_ctrl_t)'(0) )
  ) p2_p1_sll (
    .in_clk      ( prc_clk            ) ,
    .in_s_rst_n  ( prc_srst_n_part[1] ) ,
    .in_data     ( in_p2_p1_sll_data  ) ,
    .in_ctrl     ( in_p2_p1_sll_ctrl  ) ,
    .out_clk     ( prc_clk            ) ,
    .out_s_rst_n ( prc_srst_n_part[0] ) ,
    .out_data    ( out_p2_p1_sll_data ) ,
    .out_ctrl    ( out_p2_p1_sll_ctrl )
  );

  // Cross data between part 1 and part 3 through part 2
  assign in_p2_p3_sll_data.ntt_proc_cmd = out_p1_p2_sll_data.ntt_proc_cmd;
  assign in_p2_p3_sll_ctrl.ntt_proc_cmd_avail = out_p1_p2_sll_ctrl.ntt_proc_cmd_avail;
  assign in_p2_p3_sll_ctrl.bsk_ctrl = out_p1_p2_sll_ctrl.bsk_ctrl;
  assign in_p2_p1_sll_ctrl.bsk_ctrl = out_p3_p2_sll_ctrl.bsk_ctrl;

  hpu_qual_sll #(
    .IN_DEPTH    ( SLL_IN_PIPE                 ) ,
    .OUT_DEPTH   ( SLL_OUT_PIPE                ) ,
    .DATA_WIDTH  ( $bits(p2_p3_sll_data_t)     ) ,
    .CTRL_WIDTH  ( $bits(p2_p3_sll_ctrl_t)     ) ,
    .CTRL_RST    ( $bits(p2_p3_sll_ctrl_t)'(0) )
  ) p2_p3_sll (
    .in_clk      ( prc_clk            ) ,
    .in_s_rst_n  ( prc_srst_n_part[1] ) ,
    .in_data     ( in_p2_p3_sll_data  ) ,
    .in_ctrl     ( in_p2_p3_sll_ctrl  ) ,
    .out_clk     ( prc_clk            ) ,
    .out_s_rst_n ( prc_srst_n_part[2] ) ,
    .out_data    ( out_p2_p3_sll_data ) ,
    .out_ctrl    ( out_p2_p3_sll_ctrl )
  );

  hpu_qual_sll #(
    .IN_DEPTH    ( SLL_IN_PIPE                 ) ,
    .OUT_DEPTH   ( SLL_OUT_PIPE                ) ,
    .DATA_WIDTH  ( $bits(p3_p2_sll_data_t)     ) ,
    .CTRL_WIDTH  ( $bits(p3_p2_sll_ctrl_t)     ) ,
    .CTRL_RST    ( $bits(p3_p2_sll_ctrl_t)'(0) )
  ) p3_p2_sll (
    .in_clk      ( prc_clk            ) ,
    .in_s_rst_n  ( prc_srst_n_part[2] ) ,
    .in_data     ( in_p3_p2_sll_data  ) ,
    .in_ctrl     ( in_p3_p2_sll_ctrl  ) ,
    .out_clk     ( prc_clk            ) ,
    .out_s_rst_n ( prc_srst_n_part[1] ) ,
    .out_data    ( out_p3_p2_sll_data ) ,
    .out_ctrl    ( out_p3_p2_sll_ctrl )
  );

  generate
    if (INTER_PART_PIPE > 0) begin : gen_inter_part_pipe
      // ----------------------------------------------------------------------------------------- //
      // Interpart Resetable output flops
      // ----------------------------------------------------------------------------------------- //
      // Part 1
      always_ff @(posedge prc_clk)
        if (!prc_srst_n_part[0]) begin
          out_p1_prc_interrupt <= '0;
        end
        else begin
          out_p1_prc_interrupt <= in_p1_prc_interrupt;
        end

      // Part 3 TODO: Not clear how are the interrupts going to be used.
      always_ff @(posedge prc_clk)
        if (!prc_srst_n_part[2]) begin
          out_p3_prc_interrupt <= '0;
        end
        else begin
          out_p3_prc_interrupt <= in_p3_prc_interrupt;
        end
      // ----------------------------------------------------------------------------------------- //

      always_ff @(posedge cfg_clk)
        if (!cfg_srst_n) begin
          out_p1_cfg_interrupt <= '0;
        end
        else begin
          out_p1_cfg_interrupt <= in_p1_cfg_interrupt;
        end

      always_ff @(posedge cfg_clk)
        if (!cfg_srst_n) begin
          out_p3_cfg_interrupt <= '0;
        end
        else begin
          out_p3_cfg_interrupt <= in_p3_cfg_interrupt;
        end

    end
    else begin : gen_no_inter_part_pipe
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
    .prc_srst_n              (prc_srst_n_part[0]),

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

    .isc_dop                   (s1_isc_dop),
    .isc_dop_rdy               (s1_isc_dop_rdy),
    .isc_dop_vld               (s1_isc_dop_vld),

    .isc_ack                   (s1_isc_ack),
    .isc_ack_rdy               (s1_isc_ack_rdy),
    .isc_ack_vld               (s1_isc_ack_vld),

    .entry_bsk_proc            (in_p1_p2_sll_ctrl.bsk_ctrl),
    .bsk_entry_proc            (out_p2_p1_sll_ctrl.bsk_ctrl),

    .ntt_proc_cmd              (in_p1_p2_sll_data.ntt_proc_cmd),
    .ntt_proc_cmd_avail        (in_p1_p2_sll_ctrl.ntt_proc_cmd_avail),

    .decomp_ntt_data_avail      (in_p1_p2_sll_ctrl.decomp_ntt_ctrl.data_avail     ),
    .decomp_ntt_data            (in_p1_p2_sll_data.decomp_ntt_data.data           ),
    .decomp_ntt_sob             (in_p1_p2_sll_data.decomp_ntt_data.sob            ),
    .decomp_ntt_eob             (in_p1_p2_sll_data.decomp_ntt_data.eob            ),
    .decomp_ntt_sog             (in_p1_p2_sll_data.decomp_ntt_data.sog            ),
    .decomp_ntt_eog             (in_p1_p2_sll_data.decomp_ntt_data.eog            ),
    .decomp_ntt_sol             (in_p1_p2_sll_data.decomp_ntt_data.sol            ),
    .decomp_ntt_eol             (in_p1_p2_sll_data.decomp_ntt_data.eol            ),
    .decomp_ntt_pbs_id          (in_p1_p2_sll_data.decomp_ntt_data.pbs_id         ),
    .decomp_ntt_last_pbs        (in_p1_p2_sll_data.decomp_ntt_data.last_pbs       ),
    .decomp_ntt_full_throughput (in_p1_p2_sll_data.decomp_ntt_data.full_throughput),
    .decomp_ntt_ctrl_avail      (in_p1_p2_sll_ctrl.decomp_ntt_ctrl.ctrl_avail     ),

    .ntt_acc_modsw_data_avail   (out_p2_p1_sll_ctrl.ntt_acc_modsw_ctrl.data_avail ),
    .ntt_acc_modsw_ctrl_avail   (out_p2_p1_sll_ctrl.ntt_acc_modsw_ctrl.ctrl_avail ),
    .ntt_acc_modsw_data         (out_p2_p1_sll_data.ntt_acc_modsw_data.data       ),
    .ntt_acc_modsw_sob          (out_p2_p1_sll_data.ntt_acc_modsw_data.sob        ),
    .ntt_acc_modsw_eob          (out_p2_p1_sll_data.ntt_acc_modsw_data.eob        ),
    .ntt_acc_modsw_sol          (out_p2_p1_sll_data.ntt_acc_modsw_data.sol        ),
    .ntt_acc_modsw_eol          (out_p2_p1_sll_data.ntt_acc_modsw_data.eol        ),
    .ntt_acc_modsw_sog          (out_p2_p1_sll_data.ntt_acc_modsw_data.sog        ),
    .ntt_acc_modsw_eog          (out_p2_p1_sll_data.ntt_acc_modsw_data.eog        ),
    .ntt_acc_modsw_pbs_id       (out_p2_p1_sll_data.ntt_acc_modsw_data.pbs_id     )
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
    .prc_srst_n                 (prc_srst_n_part[1]),

    .cfg_clk                    (cfg_clk),
    .cfg_srst_n                 (cfg_srst_n),

    .decomp_ntt_data_avail      (out_p1_p2_sll_ctrl.decomp_ntt_ctrl.data_avail),
    .decomp_ntt_data            (out_p1_p2_sll_data.decomp_ntt_data.data),
    .decomp_ntt_sob             (out_p1_p2_sll_data.decomp_ntt_data.sob),
    .decomp_ntt_eob             (out_p1_p2_sll_data.decomp_ntt_data.eob),
    .decomp_ntt_sog             (out_p1_p2_sll_data.decomp_ntt_data.sog),
    .decomp_ntt_eog             (out_p1_p2_sll_data.decomp_ntt_data.eog),
    .decomp_ntt_sol             (out_p1_p2_sll_data.decomp_ntt_data.sol),
    .decomp_ntt_eol             (out_p1_p2_sll_data.decomp_ntt_data.eol),
    .decomp_ntt_pbs_id          (out_p1_p2_sll_data.decomp_ntt_data.pbs_id),
    .decomp_ntt_last_pbs        (out_p1_p2_sll_data.decomp_ntt_data.last_pbs),
    .decomp_ntt_full_throughput (out_p1_p2_sll_data.decomp_ntt_data.full_throughput),
    .decomp_ntt_ctrl_avail      (out_p1_p2_sll_ctrl.decomp_ntt_ctrl.ctrl_avail),

    .ntt_acc_modsw_data_avail   (in_p2_p1_sll_ctrl.ntt_acc_modsw_ctrl.data_avail),
    .ntt_acc_modsw_ctrl_avail   (in_p2_p1_sll_ctrl.ntt_acc_modsw_ctrl.ctrl_avail),
    .ntt_acc_modsw_data         (in_p2_p1_sll_data.ntt_acc_modsw_data.data),
    .ntt_acc_modsw_sob          (in_p2_p1_sll_data.ntt_acc_modsw_data.sob),
    .ntt_acc_modsw_eob          (in_p2_p1_sll_data.ntt_acc_modsw_data.eob),
    .ntt_acc_modsw_sol          (in_p2_p1_sll_data.ntt_acc_modsw_data.sol),
    .ntt_acc_modsw_eol          (in_p2_p1_sll_data.ntt_acc_modsw_data.eol),
    .ntt_acc_modsw_sog          (in_p2_p1_sll_data.ntt_acc_modsw_data.sog),
    .ntt_acc_modsw_eog          (in_p2_p1_sll_data.ntt_acc_modsw_data.eog),
    .ntt_acc_modsw_pbs_id       (in_p2_p1_sll_data.ntt_acc_modsw_data.pbs_id),

    .p2_p3_ntt_proc_data        (in_p2_p3_sll_data.ntt_proc_data),
    .p2_p3_ntt_proc_avail       (in_p2_p3_sll_ctrl.ntt_ctrl.data_avail),
    .p2_p3_ntt_proc_ctrl_avail  (in_p2_p3_sll_ctrl.ntt_ctrl.ctrl_avail),

    .p3_p2_ntt_proc_data        (out_p3_p2_sll_data.ntt_proc_data),
    .p3_p2_ntt_proc_avail       (out_p3_p2_sll_ctrl.ntt_ctrl.data_avail),
    .p3_p2_ntt_proc_ctrl_avail  (out_p3_p2_sll_ctrl.ntt_ctrl.ctrl_avail),

    .ntt_proc_cmd               (out_p1_p2_sll_data.ntt_proc_cmd),
    .ntt_proc_cmd_avail         (out_p1_p2_sll_ctrl.ntt_proc_cmd_avail),

    .pep_rif_elt                (in_p2_p3_sll_ctrl.pep_rif_elt)
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
    .prc_srst_n               (prc_srst_n_part[2]),

    .cfg_clk                  (cfg_clk),
    .cfg_srst_n               (cfg_srst_n),

    .interrupt                ({in_p3_cfg_interrupt,in_p3_prc_interrupt}),

    //== Axi4-lite slave @prc_clk and @cfg_clk
    `HPU_AXIL_INSTANCE(prc,prc_3in3)
    `HPU_AXIL_INSTANCE(cfg,cfg_3in3)

    //== Axi4 BSK interface
    `HPU_AXI4_FULL_INSTANCE(bsk, bsk,,[BSK_PC-1:0])

    .p2_p3_ntt_proc_data       (out_p2_p3_sll_data.ntt_proc_data),
    .p2_p3_ntt_proc_avail      (out_p2_p3_sll_ctrl.ntt_ctrl.data_avail),
    .p2_p3_ntt_proc_ctrl_avail (out_p2_p3_sll_ctrl.ntt_ctrl.ctrl_avail),

    .p3_p2_ntt_proc_data       (in_p3_p2_sll_data.ntt_proc_data),
    .p3_p2_ntt_proc_avail      (in_p3_p2_sll_ctrl.ntt_ctrl.data_avail),
    .p3_p2_ntt_proc_ctrl_avail (in_p3_p2_sll_ctrl.ntt_ctrl.ctrl_avail),

    .ntt_proc_cmd              (out_p2_p3_sll_data.ntt_proc_cmd),
    .ntt_proc_cmd_avail        (out_p2_p3_sll_ctrl.ntt_proc_cmd_avail),

    .entry_bsk_proc            (out_p2_p3_sll_ctrl.bsk_ctrl),
    .bsk_entry_proc            (in_p3_p2_sll_ctrl.bsk_ctrl),

    .p2_p3_pep_rif_elt         (out_p2_p3_sll_ctrl.pep_rif_elt),

    .hpu_reset                 (hpu_reset),
    .hpu_reset_done            (hpu_reset_done)
  );

endmodule
