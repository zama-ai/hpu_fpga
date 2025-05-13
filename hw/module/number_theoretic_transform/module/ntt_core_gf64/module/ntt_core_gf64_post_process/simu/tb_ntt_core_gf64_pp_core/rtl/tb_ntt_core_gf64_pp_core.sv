// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
// NTT gf64 post process core testbench
//
// Note that the module support any modulo of the form
// solinas 2 : 2**MOD_NTT_W - 2**(MOD_NTT_W/2) + 1
// ==============================================================================================

module tb_ntt_core_gf64_pp_core;
  `timescale 1ns/10ps

  import param_tfhe_pkg::*;
  import pep_common_param_pkg::*;
  import common_definition_pkg::*;

  // ============================================================================================ //
  // parameter
  // ============================================================================================ //
  // system
  localparam int CLK_HALF_PERIOD   = 1;
  localparam int ARST_ACTIVATION   = 17;

  parameter arith_mult_type_e MULT_TYPE  = MULT_CORE;
  parameter bit               IN_PIPE    = 1'b1;

  parameter int               SAMPLE_NB   = GLWE_K_P1*10000;
  parameter int               STG_ITER_NB = 8;
  parameter int               MOD_NTT_W   = 64; // should be even

  localparam [MOD_NTT_W-1:0]  MOD_M       = 2**MOD_NTT_W - 2**(MOD_NTT_W/2) + 1;
  localparam int              OP_W        = MOD_NTT_W+2;
  localparam int              INLV_NB     = GLWE_K_P1*PBS_L;

  // ============================================================================================ //
  // type
  // ============================================================================================ //
  typedef struct packed {
    logic                 sob;
    logic                 eob;
    logic                 sol;
    logic                 eol;
    logic                 sos;
    logic                 eos;
    logic [BPBS_ID_W-1:0] pbs_id;
  } control_t;

  // ============================================================================================ //
  // clock, reset
  // ============================================================================================ //
  bit clk;
  bit a_rst_n;
  bit s_rst_n;

  initial begin
    clk     = 1'b0;
    a_rst_n = 1'b0;
    #ARST_ACTIVATION a_rst_n = 1'b1;
  end

  always begin
    #CLK_HALF_PERIOD clk = ~clk;
  end

  always_ff @(posedge clk) begin
    s_rst_n <= a_rst_n;
  end

  // ============================================================================================ //
  // End of test
  // ============================================================================================ //
  bit end_of_test;

  initial begin
    wait (end_of_test);
    @(posedge clk) $display("%t > SUCCEED !", $time);
    $finish;
  end

  // ============================================================================================ //
  // Error
  // ============================================================================================ //
  bit error;
  bit error_data;
  bit error_ctrl;
  bit error_pp;

  assign error = error_data
               | error_ctrl
               | error_pp;

  always_ff @(posedge clk) begin
    if (error) begin
      $display("%t > FAILURE !", $time);
      $stop;
    end
  end

  // ============================================================================================ //
  // IO
  // ============================================================================================ //
  // Input data
  logic [MOD_NTT_W+1:0]                in_data; // 2s complement
  logic                                in_avail;
  control_t                            in_ctrl;

  // Output data
  logic [MOD_NTT_W+1:0]                out_data; // 2s complement
  logic                                out_avail;
  control_t                            out_ctrl;

  // Matrix factors : BSK
  logic [GLWE_K_P1-1:0][MOD_NTT_W-1:0] bsk;
  logic [GLWE_K_P1-1:0]                bsk_vld;
  logic [GLWE_K_P1-1:0]                bsk_rdy;

  // ============================================================================================ //
  // Design under test
  // ============================================================================================ //
  ntt_core_gf64_pp_core #(
    .MOD_NTT_W      (MOD_NTT_W),
    .MULT_TYPE      (MULT_TYPE),
    .IN_PIPE        (IN_PIPE)
  ) dut (
    .clk                 (clk),
    .s_rst_n             (s_rst_n),
    .in_data             (in_data),
    .in_avail            (in_avail),
    .in_sob              (in_ctrl.sob),
    .in_eob              (in_ctrl.eob),
    .in_sol              (in_ctrl.sol),
    .in_eol              (in_ctrl.eol),
    .in_sos              (in_ctrl.sos),
    .in_eos              (in_ctrl.eos),
    .in_pbs_id           (in_ctrl.pbs_id),

    .out_data            (out_data),
    .out_avail           (out_avail),
    .out_sob             (out_ctrl.sob),
    .out_eob             (out_ctrl.eob),
    .out_sol             (out_ctrl.sol),
    .out_eol             (out_ctrl.eol),
    .out_sos             (out_ctrl.sos),
    .out_eos             (out_ctrl.eos),
    .out_pbs_id          (out_ctrl.pbs_id),

    .bsk                 (bsk),
    .bsk_vld             (bsk_vld),
    .bsk_rdy             (bsk_rdy),

    .error               (error_pp)
  );

  // ============================================================================================ //
  // Stimuli
  // ============================================================================================ //
  integer in_pbs_nb;
  integer in_pbs_id;
  integer in_stg_iter;
  integer in_inlv;

  integer in_pbs_idD;
  integer in_stg_iterD;
  integer in_inlvD;

  logic in_last_inlv;
  logic in_last_stg_iter;
  logic in_last_pbs_id;

  assign in_last_inlv     = in_inlv == INLV_NB-1;
  assign in_last_stg_iter = in_stg_iter == STG_ITER_NB-1;
  assign in_last_pbs_id   = in_pbs_id == in_pbs_nb-1;

  assign in_inlvD     = in_avail ? in_last_inlv ? '0 : in_inlv + 1 : in_inlv;
  assign in_stg_iterD = in_avail && in_last_inlv ? in_last_stg_iter ? '0 : in_stg_iter + 1 : in_stg_iter;
  assign in_pbs_idD   = in_avail && in_last_inlv && in_last_stg_iter ? in_last_pbs_id ? '0 : in_pbs_id + 1 : in_pbs_id;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      in_inlv     <= '0;
      in_stg_iter <= '0;
      in_pbs_id   <= '0;
    end
    else begin
      in_inlv     <= in_inlvD    ;
      in_stg_iter <= in_stg_iterD;
      in_pbs_id   <= in_pbs_idD  ;
    end

  always_ff @(posedge clk)
    if (!s_rst_n) in_pbs_nb <= $urandom_range(1,BATCH_PBS_NB+1);
    else          in_pbs_nb <= (in_avail && in_last_inlv && in_last_stg_iter && in_last_pbs_id) ? $urandom_range(1,BATCH_PBS_NB+1) : in_pbs_nb;

  assign in_ctrl.sol = in_inlv == 0;
  assign in_ctrl.eol = in_last_inlv;
  assign in_ctrl.sos = in_stg_iter == 0 & in_ctrl.sol;
  assign in_ctrl.eos = in_last_stg_iter & in_ctrl.eol;
  assign in_ctrl.sob = in_pbs_id == 0 & in_ctrl.sol & in_ctrl.sos;
  assign in_ctrl.eob = in_last_pbs_id & in_ctrl.eol & in_ctrl.eos;
  assign in_ctrl.pbs_id = in_pbs_id;

  stream_source #(
    .FILENAME   ("random"),
    .DATA_TYPE  ("ascii_hex"), // UNUSED
    .DATA_W     (OP_W),
    .RAND_RANGE (2**32-1),
    .KEEP_VLD   (0),
    .MASK_DATA  ("none")
  ) data_source (
      .clk     (clk),
      .s_rst_n (s_rst_n),

      .data    (in_data),
      .vld     (in_avail),
      .rdy     (1'b1),

      .throughput(0)
  );

  logic [MOD_NTT_W-1:0]                bsk_tmp;
  logic                                bsk_vld_tmp;
  logic                                bsk_rdy_tmp;
  logic [GLWE_K_P1-1:0][MOD_NTT_W-1:0] bsk_sr;
  logic [GLWE_K_P1-1:0]                bsk_vld_sr;
  logic [GLWE_K_P1-1:0][MOD_NTT_W-1:0] bsk_srD;
  logic [GLWE_K_P1-1:0]                bsk_vld_srD;

  assign bsk_srD     = {bsk_sr[GLWE_K_P1-2:0],bsk_tmp};
  assign bsk_vld_srD = {bsk_vld_sr[GLWE_K_P1-2:0],bsk_vld_tmp & bsk_rdy_tmp};

  assign bsk_vld     = {bsk_vld_srD[GLWE_K_P1-1:1],bsk_vld_tmp};
  assign bsk_rdy_tmp = bsk_rdy[0];

  always_comb
    for (int i=0; i< GLWE_K_P1; i=i+1)
      bsk[i] = (bsk_srD[i] + i) % MOD_M; // to set different values

  stream_source #(
    .FILENAME   ("random"),
    .DATA_TYPE  ("ascii_hex"), // UNUSED
    .DATA_W     (MOD_NTT_W),
    .RAND_RANGE (16),
    .KEEP_VLD   (1),
    .MASK_DATA  ("none")
  ) bsk_source (
      .clk     (clk),
      .s_rst_n (s_rst_n),

      .data    (bsk_tmp),
      .vld     (bsk_vld_tmp),
      .rdy     (bsk_rdy_tmp),

      .throughput(16)
  );

  always_ff @(posedge clk)
    if (!s_rst_n) bsk_vld_sr <= '0;
    else          bsk_vld_sr <= bsk_vld_srD;

  always_ff @(posedge clk)
    bsk_sr <= bsk_srD;

  initial begin
    int r0, r1;
    r0 = data_source.open();
    r1 = bsk_source.open();
    wait(s_rst_n);
    data_source.start(SAMPLE_NB * PBS_L);
    bsk_source.start(SAMPLE_NB * PBS_L);
  end

  // ============================================================================================ //
  // Reference
  // ============================================================================================ //
  logic [MOD_NTT_W-1:0] ref_q [$];
  control_t             ref_ctrl_q[$];

  control_t  keep_in_ctrl;
  always_ff @(posedge clk)
    if (in_avail && in_ctrl.sol)
      keep_in_ctrl = in_ctrl;

  always_ff @(posedge clk)
    if (in_avail && in_ctrl.eol) begin
      for (int i=0; i<GLWE_K_P1; i=i+1) begin
        control_t c;

        c.sol = i == 0;
        c.eol = i == GLWE_K_P1-1;
        c.sos = keep_in_ctrl.sos & c.sol;
        c.eos = in_ctrl.eos & c.eol;
        c.sob = keep_in_ctrl.sob & c.sol & c.sos;
        c.eob = in_ctrl.eob & c.eol & c.eos;
        c.pbs_id = in_ctrl.pbs_id;

        ref_ctrl_q.push_back(c);

      end
    end

  logic [OP_W-1:0] in_data_q [$];
  logic [MOD_NTT_W-1:0] in_bsk_q [$]; // Note that we can deduce the GLWE_K_P1 bsk values from the 1rst one.
  always_ff @(posedge clk)
    if (in_avail)
      in_data_q.push_back(in_data);

  always_ff @(posedge clk)
    if (bsk_vld[0] && bsk_rdy[0])
      in_bsk_q.push_back(bsk[0]);

  integer bsk_cnt;
  always_ff @(posedge clk)
    if (!s_rst_n)
      bsk_cnt   <= '0;
    else
      if (bsk_vld[GLWE_K_P1-1] && bsk_rdy[GLWE_K_P1-1])
        bsk_cnt   <= bsk_cnt == INLV_NB-1 ? '0 : bsk_cnt + 1;

  bit build_ref;
  assign build_ref = bsk_vld[GLWE_K_P1-1] && bsk_rdy[GLWE_K_P1-1] && (bsk_cnt == INLV_NB-1);
  always_ff @(posedge clk)
    if (build_ref) begin
      logic [GLWE_K_P1*PBS_L-1:0][OP_W-1:0]      d;
      logic [GLWE_K_P1*PBS_L-1:0][MOD_NTT_W-1:0] b;

      for (int i=0; i<GLWE_K_P1*PBS_L; i=i+1) begin
        d[i] = in_data_q.pop_front();
        b[i] = in_bsk_q.pop_front();

        //$display("d[%0d]=0x%0x bsk[%0d]=0x%0x",i,d[i],i,b[i]);
      end

      for (int i=0; i<GLWE_K_P1; i=i+1) begin
        logic [MOD_NTT_W:0] res;
        res = 0;
        for (int j=0; j<GLWE_K_P1*PBS_L; j=j+1) begin
          logic[OP_W-1:0] a_val;
          logic[OP_W-1:0] a_abs;

          logic[OP_W+MOD_NTT_W-1:0] mult_abs;
          logic[MOD_NTT_W-1:0] mult_abs_reduc;
          logic[MOD_NTT_W-1:0] mult_reduc;
          logic         sign;
          a_val          = d[j];
          sign           = a_val[OP_W-1];
          a_abs          = sign ? (1 << OP_W) - a_val[OP_W-1:0] : a_val[OP_W-1:0];

          mult_abs       = a_abs * ((b[j]+i)%MOD_M); // retrieve the bsk from the 1rst one
          mult_abs_reduc = mult_abs - (mult_abs/MOD_M)*MOD_M;
          mult_reduc     = (sign && (mult_abs_reduc!=0)) ? MOD_M - mult_abs_reduc : mult_abs_reduc;

          res = res + mult_reduc;
          res = res >= MOD_M ? res - MOD_M : res;
          //$display("[%0d] mult_reduc=0x%0x res=0x%0x",j,mult_reduc,res);
        end
        ref_q.push_back(res);
      end
    end

  // ============================================================================================ //
  // Check
  // ============================================================================================ //
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      error_data <= 1'b0;
      error_ctrl <= 1'b0;
    end
    else if (out_avail) begin
      control_t             ref_c;
      logic [MOD_NTT_W-1:0] ref_d;
      logic [MOD_NTT_W-1:0] res_reduct;
      logic                 res_sign;
      logic [MOD_NTT_W:0]   res_abs;
      logic [MOD_NTT_W-1:0] res_abs_reduct;

      ref_c = ref_ctrl_q.pop_front();
      ref_d = ref_q.pop_front();

      assert(ref_c == out_ctrl)
      else begin
        $display("%t > ERROR: Mismatch control", $time);
        $display("%t >  sol exp=%0d seen=%0d", $time, out_ctrl.sol, ref_c.sol);
        $display("%t >  eol exp=%0d seen=%0d", $time, out_ctrl.eol, ref_c.eol);
        $display("%t >  sob exp=%0d seen=%0d", $time, out_ctrl.sob, ref_c.sob);
        $display("%t >  eob exp=%0d seen=%0d", $time, out_ctrl.eob, ref_c.eob);
        $display("%t >  sos exp=%0d seen=%0d", $time, out_ctrl.sos, ref_c.sos);
        $display("%t >  eos exp=%0d seen=%0d", $time, out_ctrl.eos, ref_c.eos);
        $display("%t >  pbs_id exp=%0d seen=%0d", $time, out_ctrl.pbs_id, ref_c.pbs_id);
        error_ctrl <= 1'b1;
      end

      res_sign = out_data[MOD_NTT_W+1];
      res_abs  = res_sign ? (1 << MOD_NTT_W+1)-out_data[MOD_NTT_W:0] : out_data[MOD_NTT_W:0];
      res_abs_reduct = res_abs - (res_abs/MOD_M)*MOD_M;
      res_reduct = (res_sign && (res_abs_reduct!=0)) ? MOD_M - res_abs_reduct : res_abs_reduct;

      assert(ref_d == res_reduct)
      else begin
        $display("%t > ERROR: Mismatche data: reduced exp=0x%0x seen=0x%0x (seen=0x%0x)",$time, ref_d, res_reduct,out_data);
        error_data <= 1;
      end

    end


  // ============================================================================================ //
  // End of test
  // ============================================================================================ //
  integer out_cnt;
  always_ff @(posedge clk)
    if (!s_rst_n) out_cnt <= '0;
    else begin
      if (out_avail) begin
        out_cnt <= out_cnt + 1;
        if (out_cnt % 1000 == 0)
          $display("%t > INFO : Output data #%0d", $time, out_cnt);
      end
    end

  initial begin
    end_of_test <= 1'b0;
    wait (out_cnt == SAMPLE_NB);
    repeat(10) @(posedge clk);
    end_of_test <= 1'b1;
  end

endmodule
