// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the register pipe at the butterfly input.
//
// Let's name : IN_NB = R**STEP, the number of successive R-data inputs.
// Then the data order is the following :
// during LVL*IN_NB cycles : POS_0
// during LVL*IN_NB cycles : POS_1
// during LVL*IN_NB cycles : POS_2
// ...
// during LVL*IN_NB cycles : POS_(R-1)
// Data are processed when the POS_(R-1) coefficients are received (in_inc = 1).
// So the current module does not receive data at every cycle.
//
// WARNING : checked with R=2 only
// ==============================================================================================

module ntt_core_wmm_clbu_pcg_pipe
#(
  parameter int OP_W     = 64,
  parameter int R        = 8,
  parameter int STEP     = 1,// R**STEP : number of R-inputs received
  parameter int POS      = 0, // from 0 to R-1
  parameter int LVL_NB   = 3, // Maximum number of interleaved level.
  parameter int MIN_LVL_NB = 3,
  parameter int BPBS_ID_W = 2,
  parameter bit IN_PIPE  = 1'b0,
  parameter bit OUT_PIPE = 1'b1
) (
  input  logic                   clk,
  input  logic                   s_rst_n,
  input  logic [R-1:0][OP_W-1:0] in_data,
  input  logic                   in_avail,
  input  logic                   in_eol, // Current input is last level.
  input  logic                   in_inc,
  output logic [OP_W-1:0]        out_data,
  output logic                   out_avail,

  // For POS = R-1, the module outputs the control signals.
  input  logic                   in_ctrl_sol,
  input  logic                   in_ctrl_eol,
  input  logic                   in_ctrl_sob,
  input  logic                   in_ctrl_eob,
  input  logic                   in_ctrl_sos,
  input  logic                   in_ctrl_eos,
  input  logic                   in_ctrl_ntt_bwd,
  input  logic [BPBS_ID_W-1:0]    in_ctrl_pbs_id,
  input  logic                   in_ctrl_last_lpb,
  output logic                   out_ctrl_sol,
  output logic                   out_ctrl_eol,
  output logic                   out_ctrl_sob,
  output logic                   out_ctrl_eob,
  output logic                   out_ctrl_sos,
  output logic                   out_ctrl_eos,
  output logic                   out_ctrl_ntt_bwd,
  output logic [BPBS_ID_W-1:0]    out_ctrl_pbs_id,
  output logic                   out_ctrl_last_lpb

);

  // ============================================================================================== --
  // localparam
  // ============================================================================================== --
  localparam int IN_NB       = R**STEP;
  localparam int IDEAL_DEPTH = 2*R*IN_NB-(POS+1)*IN_NB-(IN_NB-1);
  localparam int DEPTH_TMP   = (IDEAL_DEPTH + (R-1)) / R;
  localparam int DEPTH_TMP2  = DEPTH_TMP - 1;
  localparam int LVL_BUF     = LVL_NB / MIN_LVL_NB;
  //TODO : Keep at least 1 buffer to absorb the change in lvl numbers between NTT and INTT
  localparam int DEPTH       = DEPTH_TMP2 * LVL_BUF; // TODO : find a correct way
  localparam int DEPTH_W     = DEPTH > 1 ? $clog2(DEPTH) : 1;
  localparam int I_DEPTH     = 2;
  localparam int I_DEPTH_W   = $clog2(I_DEPTH) > 0 ? 1 : $clog2(I_DEPTH);

  localparam int R_W       = $clog2(R) > 0 ? $clog2(R) : 1;
  //localparam int FIRST_LOC = DEPTH - (IN_NB*R - (POS+1)*IN_NB)-R;
  localparam int LVL_W     = $clog2(LVL_NB) > 0 ? $clog2(LVL_NB) : 1;
  localparam int IN_NB_W   = $clog2(IN_NB) > 0 ? $clog2(IN_NB) : 1;
  localparam int OUT_NB    = IN_NB * R;
  localparam int OUT_NB_W  = $clog2(OUT_NB) > 0 ? $clog2(OUT_NB) : 1;

  // ============================================================================================== --
  // Type
  // ============================================================================================== --
  typedef struct packed {
    logic                sob;
    logic                eob;
    logic                sol;
    logic                eol;
    logic                sos;
    logic                eos;
  } startend_t;

  typedef struct packed {
    logic                last_lpb;
    logic                ntt_bwd;
    logic [BPBS_ID_W-1:0] pbs_id;
  } info_t;

  typedef struct packed {
    logic                last_lpb;
    logic                sob;
    logic                eob;
    logic                sol;
    logic                eol;
    logic                sos;
    logic                eos;
    logic                ntt_bwd;
    logic [BPBS_ID_W-1:0] pbs_id;
  } control_t;

  localparam int STARTEND_W = $bits(startend_t);
  localparam int INFO_W     = $bits(info_t);
  localparam int CTRL_W     = $bits(control_t);

  // ============================================================================================== --
  // Input pipe
  // ============================================================================================== --
  logic [R-1:0][OP_W-1:0] s0_data;
  logic                   s0_avail;
  logic                   s0_eol;

  logic                   s0_ctrl_sol;
  logic                   s0_ctrl_eol;
  logic                   s0_ctrl_sob;
  logic                   s0_ctrl_eob;
  logic                   s0_ctrl_sos;
  logic                   s0_ctrl_eos;
  logic                   s0_ctrl_ntt_bwd;
  logic [BPBS_ID_W-1:0]    s0_ctrl_pbs_id;
  logic                   s0_ctrl_last_lpb;

  generate
    if (IN_PIPE) begin : gen_in_pipe
      always_ff @(posedge clk)
        if (!s_rst_n) s0_avail <= 1'b0;
        else          s0_avail <= in_avail;

      always_ff @(posedge clk) begin
        s0_data         <= in_data;
        s0_eol          <= in_eol;
        s0_ctrl_sol     <= in_ctrl_sol;
        s0_ctrl_eol     <= in_ctrl_eol;
        s0_ctrl_sob     <= in_ctrl_sob;
        s0_ctrl_eob     <= in_ctrl_eob;
        s0_ctrl_sos     <= in_ctrl_sos;
        s0_ctrl_eos     <= in_ctrl_eos;
        s0_ctrl_ntt_bwd <= in_ctrl_ntt_bwd;
        s0_ctrl_pbs_id  <= in_ctrl_pbs_id;
        s0_ctrl_last_lpb<= in_ctrl_last_lpb;
      end
    end
    else begin : gen_no_in_pipe
      assign s0_avail        = in_avail;
      assign s0_eol          = in_eol;
      assign s0_data         = in_data;
      assign s0_ctrl_sol     = in_ctrl_sol;
      assign s0_ctrl_eol     = in_ctrl_eol;
      assign s0_ctrl_sob     = in_ctrl_sob;
      assign s0_ctrl_eob     = in_ctrl_eob;
      assign s0_ctrl_sos     = in_ctrl_sos;
      assign s0_ctrl_eos     = in_ctrl_eos;
      assign s0_ctrl_ntt_bwd = in_ctrl_ntt_bwd;
      assign s0_ctrl_pbs_id  = in_ctrl_pbs_id;
      assign s0_ctrl_last_lpb= in_ctrl_last_lpb;
    end
  endgenerate

  // ============================================================================================== --
  // Shift register
  // ============================================================================================== --
  // The shift register is split into 2 parts
  // The first part is meant to accumulate the input, and the second part is meant to distribute
  // the coefficients.
  // Indeed, the unit of each is different. We receive input as R-coef words. The output read
  // a coef at a time.

  //== s0 : write
  logic [LVL_NB-1:0]             s0_lvl_1h;
  logic [LVL_NB-1:0]             s0_lvl_1hD;
  startend_t                     s0_seof;
  info_t                         s0_info;

  assign s0_seof.sob     = s0_ctrl_sob;
  assign s0_seof.eob     = s0_ctrl_eob;
  assign s0_seof.sol     = s0_ctrl_sol;
  assign s0_seof.eol     = s0_eol; //s0_ctrl_eol;
  assign s0_seof.sos     = s0_ctrl_sos;
  assign s0_seof.eos     = s0_ctrl_eos;
  assign s0_info.ntt_bwd = s0_ctrl_ntt_bwd;
  assign s0_info.pbs_id  = s0_ctrl_pbs_id;
  assign s0_info.last_lpb= s0_ctrl_last_lpb;

  assign s0_lvl_1hD = s0_avail? s0_eol ? 1 : {s0_lvl_1h[LVL_NB-2:0],s0_lvl_1h[LVL_NB-1]}
                              : s0_lvl_1h;

  always_ff @(posedge clk)
    if (!s_rst_n) s0_lvl_1h <= 1;
    else          s0_lvl_1h <= s0_lvl_1hD;

  //== s1 :read
  logic [LVL_NB-1:0][OP_W-1:0]   s1_data_a;
  logic [LVL_NB-1:0][CTRL_W-1:0] s1_ctrl_a;
  logic [LVL_NB-1:0]             s1_avail_a;

  logic [LVL_NB-1:0]             s1_lvl_1h;
  logic [LVL_W-1:0]              s1_lvl;
  logic [LVL_NB-1:0]             s1_lvl_1hD;
  logic [LVL_W-1:0]              s1_lvlD;

  logic [OP_W-1:0]               s1_sel_data;
  control_t                      s1_sel_ctrl;
  logic                          s1_sel_avail;

  assign s1_lvl_1hD = in_inc ? s1_sel_ctrl.eol ? 1 : {s1_lvl_1h[LVL_NB-2:0],s1_lvl_1h[LVL_NB-1]} : s1_lvl_1h;
  assign s1_lvlD    = in_inc ? s1_sel_ctrl.eol ? 0 : s1_lvl + 1 : s1_lvl;

  assign s1_sel_data  = s1_data_a[s1_lvl];
  assign s1_sel_ctrl  = s1_ctrl_a[s1_lvl];
  assign s1_sel_avail = s1_avail_a[s1_lvl];

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      s1_lvl_1h <= 1;
      s1_lvl    <= 0;
    end
    else begin
      s1_lvl_1h <= s1_lvl_1hD;
      s1_lvl    <= s1_lvlD;
    end

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      if (in_inc) begin
        assert(s1_sel_avail)
        else begin
          $fatal(1,"%t > ERROR: Data is not available while in_inc.", $time);
        end
      end
    end
// pragma translate_on

  logic [LVL_NB-1:0] sr_do_transfer;
  startend_t         sra_sel_seof[LVL_NB-1:0];
  info_t             sra_sel_info;
  logic              sra_i_sos_seen;
  logic              sra_i_sos_seenD;
  info_t             srd_info[LVL_NB-1:0];
  info_t             srd_infoD[LVL_NB-1:0];

  generate
    for (genvar gen_l=0; gen_l<LVL_NB; gen_l=gen_l+1) begin : gen_l_loop
      logic                   sra_empty;
      logic [R-1:0][OP_W-1:0] sra_sel_data;
      control_t               sra_sel_ctrl;

      if (DEPTH > 0) begin : gen_sra
        //-------------------------------------
        // Shift register for accumulation
        //-------------------------------------

        logic [DEPTH_W:0]                  sra_rp; // from -1 to DEPTH-1
        logic [DEPTH_W:0]                  sra_rpD;

        logic [DEPTH-1:0][R-1:0][OP_W-1:0] sra_data;
        logic [DEPTH-1:0][STARTEND_W-1:0]  sra_seof;
        logic [DEPTH-1:0][R-1:0][OP_W-1:0] sra_dataD;
        logic [DEPTH-1:0][STARTEND_W-1:0]  sra_seofD;
        logic                              sra_full;
        logic                              sra_wr;
        logic                              sra_rd;
        always_ff @(posedge clk)
          if (!s_rst_n) begin
            sra_rp    <= '1; // empty
          end
          else begin
            sra_rp    <= sra_rpD;
          end

        always_ff @(posedge clk) begin
          sra_data <= sra_dataD;
          sra_seof <= sra_seofD;
        end

        assign sra_full    = sra_rp == DEPTH-1;
        assign sra_empty   = sra_rp == '1; // -1
        assign sra_sel_data  = sra_data[sra_rp];
        assign sra_sel_seof[gen_l]  = sra_seof[sra_rp];

        assign sra_wr   = s0_avail & s0_lvl_1h[gen_l];
        assign sra_rd   = sr_do_transfer[gen_l];

        assign sra_rpD = (sra_wr && !sra_rd) ? sra_rp + 1:
                         (!sra_wr && sra_rd) ? sra_rp - 1: sra_rp;

        if (DEPTH > 1) begin
          assign sra_dataD  = sra_wr ? {sra_data[DEPTH-2:0],s0_data} : sra_data;
          assign sra_seofD  = sra_wr ? {sra_seof[DEPTH-2:0],s0_seof} : sra_seof;
        end
        else begin
          assign sra_dataD  = sra_wr ? s0_data : sra_data;
          assign sra_seofD  = sra_wr ? s0_seof : sra_seof;
        end

  // pragma translate_off
        always_ff @(posedge clk)
          if (!s_rst_n) begin
            // do nothing
          end
          else begin
            if (sra_rd) begin
              assert(!sra_empty)
              else begin
                $fatal(1,"%t > ERROR: Do data transfer from SRA to SRD, whereas the accumulation is not over.", $time);
              end
            end

            if (sra_wr) begin
              assert(!sra_full)
              else begin
                $fatal(1,"%t > ERROR: Write in SRA whereas it is full!", $time);
              end
            end
          end
  // pragma translate_on
      end // gen_sra
      else begin : gen_no_sra
        assign sra_sel_data  = s0_data;
        assign sra_sel_seof[gen_l]  = s0_seof;
        assign sra_empty     = ~(s0_avail & s0_lvl_1h[gen_l]);

 // pragma translate_off
        always_ff @(posedge clk)
          if (!s_rst_n) begin
            // do nothing
          end
          else begin
            if (!sra_empty) begin
              assert(sr_do_transfer[gen_l])
              else begin
                $fatal(1,"%t > ERROR: Data is not stored in SRD (DEPTH = 0).", $time);
              end
            end
          end

 // pragma translate_on
      end //gen_no_sra

      //-------------------------------------
      // Shift register for distribution
      //-------------------------------------
      logic [R-1:0][OP_W-1:0]       srd_data;
      logic [R-1:0]                 srd_avail;
      control_t                     srd_ctrl;

      logic [R-1:0][OP_W-1:0]       srd_dataD;
      logic [R-1:0]                 srd_availD;
      control_t                     srd_ctrlD;

      logic                         srd_wr;
      logic                         srd_rd;

      logic                         srd_empty;
      logic                         srd_out_first;
      logic                         srd_out_last;
      control_t                     srd_ctrl_out;

      assign sr_do_transfer[gen_l]= srd_empty & ~sra_empty;

      assign sra_sel_ctrl.sol     = sra_sel_seof[gen_l].sol;
      assign sra_sel_ctrl.eol     = sra_sel_seof[gen_l].eol;
      assign sra_sel_ctrl.sos     = sra_sel_seof[gen_l].sos;
      assign sra_sel_ctrl.eos     = sra_sel_seof[gen_l].eos;
      assign sra_sel_ctrl.sob     = sra_sel_seof[gen_l].sob;
      assign sra_sel_ctrl.eob     = sra_sel_seof[gen_l].eob;
//      assign sra_sel_ctrl.pbs_id  = (sra_sel_seof[gen_l].sos || sra_i_sos_seen) ? sra_sel_info.pbs_id : srd_ctrl.pbs_id ;
//      assign sra_sel_ctrl.ntt_bwd = (sra_sel_seof[gen_l].sos || sra_i_sos_seen) ? sra_sel_info.ntt_bwd: srd_ctrl.ntt_bwd;
//      assign sra_sel_ctrl.last_lpb= (sra_sel_seof[gen_l].sos || sra_i_sos_seen) ? sra_sel_info.last_lpb : srd_ctrl.last_lpb ;

      // Note that there are at least 2 levels (LVL_NB > 1).
      // Therefore, there is always (at least) 1 idle cycle, after the reading of the last data,
      // during which we can reload the SRD.
      assign srd_wr = sr_do_transfer[gen_l];
      assign srd_rd = in_inc & s1_lvl_1h[gen_l];

      assign srd_dataD  = srd_wr ? sra_sel_data:
                          srd_rd ? {srd_data[R-1],srd_data[R-1:1]} : srd_data;
      assign srd_ctrlD  = srd_wr ? sra_sel_ctrl : srd_ctrl;
      assign srd_availD = srd_wr ? {R{~sra_empty}} :
                          srd_rd ? {1'b0,srd_avail[R-1:1]} : srd_avail;
      assign srd_empty  = srd_avail[0] == 0;

      always_ff @(posedge clk)
        if (!s_rst_n) srd_avail <= '0;
        else          srd_avail <= srd_availD;

      always_ff @(posedge clk) begin
        srd_data <= srd_dataD;
        srd_ctrl <= srd_ctrlD;
      end

      assign srd_out_first = srd_avail == '1;
      assign srd_out_last  = srd_avail[1] == 0;
      assign srd_ctrl_out.ntt_bwd = srd_info[gen_l].ntt_bwd;
      assign srd_ctrl_out.pbs_id  = srd_info[gen_l].pbs_id;
      assign srd_ctrl_out.last_lpb= srd_info[gen_l].last_lpb;
      assign srd_ctrl_out.sol     = srd_ctrl.sol;
      assign srd_ctrl_out.eol     = srd_ctrl.eol;
      assign srd_ctrl_out.sos     = srd_ctrl.sos & srd_out_first;
      assign srd_ctrl_out.eos     = srd_ctrl.eos & srd_out_last;
      assign srd_ctrl_out.sob     = srd_ctrl.sob & srd_out_first;
      assign srd_ctrl_out.eob     = srd_ctrl.eob & srd_out_last;

      assign s1_data_a[gen_l]  = srd_data[0];
      assign s1_ctrl_a[gen_l]  = srd_ctrl_out;
      assign s1_avail_a[gen_l] = srd_avail[0];

// pragma translate_off
      always_ff @(posedge clk)
        if (!s_rst_n) begin
          // do nothing
        end
        else begin
          if (POS != (R-1)) begin
            assert(!(srd_wr && srd_rd))
            else begin
              $fatal(1, "%t > ERROR: Read and write in SRD at the same time!", $time);
            end
          end
        end
// pragma translate_on

    end // gen_l_loop
  endgenerate

  // ============================================================================================== --
  // Info
  // ============================================================================================== --
  // To save some registers, store 1 version of the info for all the levels.
  logic [I_DEPTH_W:0]             sra_i_rp;
  logic [I_DEPTH_W:0]             sra_i_rpD;

  logic [I_DEPTH-1:0][INFO_W-1:0] sra_info;
  logic [I_DEPTH-1:0][INFO_W-1:0] sra_infoD;

  logic                           sra_i_full;
  logic                           sra_i_empty;
  logic                           sra_i_wr;
  logic                           sra_i_rd;

  logic [LVL_NB-1:0]              sra_sel_eol;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      sra_i_rp       <= '1;
      sra_i_sos_seen <= 1'b0;
    end
    else begin
      sra_i_rp       <= sra_i_rpD;
      sra_i_sos_seen <= sra_i_sos_seenD;
    end

  always_ff @(posedge clk)
    sra_info <= sra_infoD;

  always_comb
    for (int i=0; i<LVL_NB; i=i+1)
      sra_sel_eol[i] = sra_sel_seof[i].eol;

  assign sra_i_full  = sra_i_rp == I_DEPTH-1;
  assign sra_i_empty = sra_i_rp == '1; // -1

  assign sra_i_sos_seenD = sr_do_transfer[0] && sra_sel_seof[0].sos ? 1'b1 :
                           (in_inc && out_ctrl_eol) == 1'b1 ? 1'b0 : sra_i_sos_seen;
  assign sra_i_wr  = s0_avail & s0_seof.sos;
  assign sra_i_rd  = sr_do_transfer[0] & sra_sel_seof[0].sos; // keep the pointer until the last level is read.
  assign sra_i_rpD = (sra_i_wr && !sra_i_rd) ? sra_i_rp + 1:
                     (!sra_i_wr && sra_i_rd) ? sra_i_rp - 1: sra_i_rp;
  assign sra_sel_info = sra_info[sra_i_rp[I_DEPTH_W-1:0]];

  if (I_DEPTH > 1) begin
    assign sra_infoD  = sra_i_wr ? {sra_info[I_DEPTH-2:0],s0_info} : sra_info;
  end
  else begin
    assign sra_infoD  = sra_i_wr ? s0_info : sra_info;
  end

  always_comb begin
    srd_infoD[0] = sra_i_rd ? sra_sel_info : srd_info[0];
    for (int i=1; i<LVL_NB; i=i+1)
      srd_infoD[i] = (in_inc && s1_lvl_1h[i-1]) ? srd_info[i-1] : srd_info[i];
  end

  always_ff @(posedge clk)
    srd_info <= srd_infoD;

//pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      if (sra_i_wr) begin
        assert(!sra_i_full)
        else begin
          $fatal(1,"%t > ERROR: Write in sra_info, while it is full", $time);
        end
      end
      if (sra_i_rd) begin
        assert(!sra_i_empty)
        else begin
          $fatal(1,"%t > ERROR: Read in sra_info, while it is empty", $time);
        end
      end
    end
//pragma translate_on

  // ============================================================================================== --
  // Output pipe
  // ============================================================================================== --
  generate
    if (OUT_PIPE) begin: gen_out_pipe
      always_ff @(posedge clk)
        if (!s_rst_n) out_avail <= 1'b0;
        else          out_avail <= s1_sel_avail;

      always_ff @(posedge clk) begin
        out_data         <= s1_sel_data;
        out_ctrl_sol     <= s1_sel_ctrl.sol    ;
        out_ctrl_eol     <= s1_sel_ctrl.eol    ;
        out_ctrl_sos     <= s1_sel_ctrl.sos    ;
        out_ctrl_eos     <= s1_sel_ctrl.eos    ;
        out_ctrl_sob     <= s1_sel_ctrl.sob    ;
        out_ctrl_eob     <= s1_sel_ctrl.eob    ;
        out_ctrl_ntt_bwd <= s1_sel_ctrl.ntt_bwd;
        out_ctrl_pbs_id  <= s1_sel_ctrl.pbs_id ;
        out_ctrl_last_lpb<= s1_sel_ctrl.last_lpb ;
      end
    end
    else begin
      assign out_data         = s1_sel_data;
      assign out_avail        = s1_sel_avail;
      assign out_ctrl_sol     = s1_sel_ctrl.sol    ;
      assign out_ctrl_eol     = s1_sel_ctrl.eol    ;
      assign out_ctrl_sos     = s1_sel_ctrl.sos    ;
      assign out_ctrl_eos     = s1_sel_ctrl.eos    ;
      assign out_ctrl_sob     = s1_sel_ctrl.sob    ;
      assign out_ctrl_eob     = s1_sel_ctrl.eob    ;
      assign out_ctrl_ntt_bwd = s1_sel_ctrl.ntt_bwd;
      assign out_ctrl_pbs_id  = s1_sel_ctrl.pbs_id ;
      assign out_ctrl_last_lpb= s1_sel_ctrl.last_lpb ;
    end
  endgenerate

endmodule
