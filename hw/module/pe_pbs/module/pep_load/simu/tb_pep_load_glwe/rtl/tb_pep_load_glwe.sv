// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Testbench to test pep_load_glwe.
// ==============================================================================================

module tb_pep_load_glwe;
`timescale 1ns/10ps

  import common_definition_pkg::*;
  import axi_if_common_param_pkg::*;
  import axi_if_glwe_axi_pkg::*;
  import param_tfhe_pkg::*;
  import top_common_param_pkg::*;
  import hpu_common_instruction_pkg::*;
  import pep_common_param_pkg::*;
  import ntt_core_common_param_pkg::*;

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int CLK_HALF_PERIOD = 1;
  localparam int ARST_ACTIVATION = 17;

  localparam int START_ADD_RANGE_W = 4;
  localparam int START_ADD_RANGE = 2**START_ADD_RANGE_W;
  localparam int AXI4_ADD_W      = 24; // to ease simulation duration

  parameter  int SAMPLE_NB   = 100;

  localparam int MAX_COEF_NB = N;
  localparam int COEF_ID_W   = $clog2(MAX_COEF_NB) == 0 ? 1 : $clog2(MAX_COEF_NB);

  localparam int TOTAL_GID_NB = int'($ceil(64.0/GRAM_NB) * GRAM_NB);

  localparam int PROC_CYCLE_NB = 100;

  localparam int RAND_RANGE      = 1023;
  parameter  int INST_THROUGHPUT = RAND_RANGE / 10;

  localparam int GLWE_ACS_W               = MOD_Q_W > 32 ? 64 : 32;
  localparam int GLWE_COEF_PER_AXI4_WORD  = AXI4_DATA_W/GLWE_ACS_W;
  localparam int AXI4_WORD_PER_GLWE_BODY  = (N*GLWE_ACS_W + AXI4_DATA_W-1)/AXI4_DATA_W;

  parameter  int SLR_LATENCY     = 2*3;

// ============================================================================================== --
// type
// ============================================================================================== --
  typedef struct packed {
    logic                 part;
    logic [COEF_ID_W-1:0] coef_id;
    logic [GID_W-1:0]     gid;
  } data_t;

  typedef struct packed {
    data_t d1;
    data_t d0;
  } data2_t;

  initial begin
    if (COEF_ID_W+1 > MOD_Q_W/2)
      $fatal(1,"> ERROR: bench only support MOD_Q_W (%0d) > 2*(COEF_ID_W+1) (2*(%0d+1))", MOD_Q_W, COEF_ID_W);
  end

// ============================================================================================== --
// function
// ============================================================================================== --
  function [MOD_Q_W-1:0] get_data (data_t d);
    return {d.part, d.coef_id} ^ d.gid;
  endfunction

// ============================================================================================== --
// clock, reset
// ============================================================================================== --
  bit clk;
  bit a_rst_n; // asynchronous reset
  bit s_rst_n; // synchronous reset

  initial begin
    clk     = 1'b0;
    a_rst_n = 1'b0;                   // active reset
    #ARST_ACTIVATION a_rst_n = 1'b1; // disable reset
  end

  always begin
    #CLK_HALF_PERIOD clk = ~clk;
  end

  always_ff @(posedge clk) begin
    s_rst_n <= a_rst_n;
  end

// ============================================================================================== --
// End of test
// ============================================================================================== --
  bit end_of_test;

  initial begin
    wait (end_of_test);
    @(posedge clk) $display("%t > SUCCEED !", $time);
    $finish;
  end

// ============================================================================================== --
// Error
// ============================================================================================== --
  bit error;
  bit [GRAM_NB-1:0][PSI-1:0][R-1:0] error_data;
  bit [GRAM_NB-1:0][PSI-1:0][R-1:0] error_add;
  logic             pep_ldg_error;

  assign error = |error_data
                 | |error_add
                 | pep_ldg_error;

  always_ff @(posedge clk) begin
    if (pep_ldg_error)
      $display("%t > ERROR : pep_load_glwe_splitc : cmd_done overflow!", $time);
    if (error) begin
      $display("%t > FAILURE !", $time);
      $finish;
    end
  end

// ============================================================================================== --
// input / output signals
// ============================================================================================== --
  logic [axi_if_ct_axi_pkg::AXI4_ADD_W-1:0]        gid_offset; // quasi static

  logic [GRAM_NB-1:0]                              garb_ldg_avail_1h;

  // AXI4 Master interface
  // NB: Only AXI Read channel exposed here
  logic [AXI4_ID_W-1:0]                            m_axi4_arid;
  logic [AXI4_ADD_W-1:0]                           m_axi4_araddr;
  logic [7:0]                                      m_axi4_arlen;
  logic [2:0]                                      m_axi4_arsize;
  logic [1:0]                                      m_axi4_arburst;
  logic                                            m_axi4_arvalid;
  logic                                            m_axi4_arready;
  logic [AXI4_ID_W-1:0]                            m_axi4_rid;
  logic [AXI4_DATA_W-1:0]                          m_axi4_rdata;
  logic [1:0]                                      m_axi4_rresp;
  logic                                            m_axi4_rlast;
  logic                                            m_axi4_rvalid;
  logic                                            m_axi4_rready;

  // pep_seq : command
  logic [LOAD_GLWE_CMD_W-1:0]                      seq_ldg_cmd;
  logic                                            seq_ldg_vld;
  logic                                            seq_ldg_rdy;
  logic                                            ldg_seq_done;

  // Write GLWE RAM
  // This memory is composed of GRAM_NB independent RAMs
  logic [GRAM_NB-1:0][PSI-1:0][R-1:0]                     glwe_ram_wr_en;
  logic [GRAM_NB-1:0][PSI-1:0][R-1:0][GLWE_RAM_ADD_W-1:0] glwe_ram_wr_add;
  logic [GRAM_NB-1:0][PSI-1:0][R-1:0][MOD_Q_W-1:0]        glwe_ram_wr_data;

  pep_ldg_counter_inc_t                            pep_ldg_counter_inc;
  pep_ldg_error_t                                  ldg_error;

// ============================================================================================== --
// Design under test instance
// ============================================================================================== --
  assign pep_ldg_error = |ldg_error;

  pep_load_glwe_splitc_assembly
  #(
    .SLR_LATENCY (SLR_LATENCY)
  ) dut (
    .clk                    (clk),
    .s_rst_n                (s_rst_n),

    .gid_offset             (gid_offset),
    .garb_ldg_avail_1h      (garb_ldg_avail_1h),

    .seq_ldg_cmd            (seq_ldg_cmd ),
    .seq_ldg_vld            (seq_ldg_vld ),
    .seq_ldg_rdy            (seq_ldg_rdy ),
    .ldg_seq_done           (ldg_seq_done),

    .m_axi4_arid            (m_axi4_arid),
    .m_axi4_araddr          (m_axi4_araddr),
    .m_axi4_arlen           (m_axi4_arlen),
    .m_axi4_arsize          (m_axi4_arsize),
    .m_axi4_arburst         (m_axi4_arburst),
    .m_axi4_arvalid         (m_axi4_arvalid),
    .m_axi4_arready         (m_axi4_arready),
    .m_axi4_rid             (m_axi4_rid),
    .m_axi4_rdata           (m_axi4_rdata),
    .m_axi4_rresp           (m_axi4_rresp),
    .m_axi4_rlast           (m_axi4_rlast),
    .m_axi4_rvalid          (m_axi4_rvalid),
    .m_axi4_rready          (m_axi4_rready),

    .glwe_ram_wr_en         (glwe_ram_wr_en),
    .glwe_ram_wr_add        (glwe_ram_wr_add),
    .glwe_ram_wr_data       (glwe_ram_wr_data),

    .pep_ldg_counter_inc    (pep_ldg_counter_inc),
    .error                  (ldg_error)
  );

// ============================================================================================== --
// Memory
// ============================================================================================== --
  logic [AXI4_ID_W-1:0]       axi4_wr_awid;
  logic [AXI4_ADD_W-1:0]      axi4_wr_awaddr;
  logic [7:0]                 axi4_wr_awlen;
  logic [2:0]                 axi4_wr_awsize;
  logic [1:0]                 axi4_wr_awburst;
  logic                       axi4_wr_awvalid;
  logic                       axi4_wr_awready;
  logic [AXI4_DATA_W-1:0]     axi4_wr_wdata;
  logic [(AXI4_DATA_W/8)-1:0] axi4_wr_wstrb;
  logic                       axi4_wr_wlast;
  logic                       axi4_wr_wvalid;
  logic                       axi4_wr_wready;
  logic [AXI4_ID_W-1:0]       axi4_wr_bid;
  logic [1:0]                 axi4_wr_bresp;
  logic                       axi4_wr_bvalid;
  logic                       axi4_wr_bready;

  axi4_mem #(
      .DATA_WIDTH(AXI4_DATA_W),
      .ADDR_WIDTH(AXI4_ADD_W),
      .ID_WIDTH  (AXI4_ID_W),
      .WR_CMD_BUF_DEPTH (1),
      .RD_CMD_BUF_DEPTH (32),
      .WR_DATA_LATENCY  (1),
      .RD_DATA_LATENCY  (40),
      .USE_WR_RANDOM    (0),
      .USE_RD_RANDOM    (1)
  ) axi4_ram_ct // {{{
  (
    .clk          (clk),
    .rst          (!s_rst_n),

    .s_axi4_awid   (axi4_wr_awid   ),
    .s_axi4_awaddr (axi4_wr_awaddr ),
    .s_axi4_awlen  (axi4_wr_awlen  ),
    .s_axi4_awsize (axi4_wr_awsize ),
    .s_axi4_awburst(axi4_wr_awburst),
    .s_axi4_awlock ('0), // disable
    .s_axi4_awcache('0), // disable
    .s_axi4_awprot ('0), // disable
    .s_axi4_awvalid(axi4_wr_awvalid),
    .s_axi4_awready(axi4_wr_awready),
    .s_axi4_wdata  (axi4_wr_wdata  ),
    .s_axi4_wstrb  (axi4_wr_wstrb  ),
    .s_axi4_wlast  (axi4_wr_wlast  ),
    .s_axi4_wvalid (axi4_wr_wvalid ),
    .s_axi4_wready (axi4_wr_wready ),
    .s_axi4_bid    (axi4_wr_bid    ),
    .s_axi4_bresp  (axi4_wr_bresp  ),
    .s_axi4_bvalid (axi4_wr_bvalid ),
    .s_axi4_bready (axi4_wr_bready ),
    .s_axi4_arid   (m_axi4_arid   ),
    .s_axi4_araddr (m_axi4_araddr ),
    .s_axi4_arlen  (m_axi4_arlen  ),
    .s_axi4_arsize (m_axi4_arsize ),
    .s_axi4_arburst(m_axi4_arburst),
    .s_axi4_arlock ('0), // disable
    .s_axi4_arcache('0), // disable
    .s_axi4_arprot ('0), // disable
    .s_axi4_arvalid(m_axi4_arvalid),
    .s_axi4_arready(m_axi4_arready),
    .s_axi4_rid    (m_axi4_rid    ),
    .s_axi4_rdata  (m_axi4_rdata  ),
    .s_axi4_rresp  (m_axi4_rresp  ),
    .s_axi4_rlast  (m_axi4_rlast  ),
    .s_axi4_rvalid (m_axi4_rvalid ),
    .s_axi4_rready (m_axi4_rready )
  );

  // AXI4 ct driver
  maxi4_if #(
    .AXI4_DATA_W(AXI4_DATA_W),
    .AXI4_ADD_W (AXI4_ADD_W),
    .AXI4_ID_W  (AXI4_ID_W)
  ) maxi4_if (
    .clk(clk),
    .rst_n(s_rst_n)
  );

  // Connect interface on testbench signals
  // Write channel
  assign axi4_wr_awid        = maxi4_if.awid   ;
  assign axi4_wr_awaddr      = maxi4_if.awaddr ;
  assign axi4_wr_awlen       = maxi4_if.awlen  ;
  assign axi4_wr_awsize      = maxi4_if.awsize ;
  assign axi4_wr_awburst     = maxi4_if.awburst;
  assign axi4_wr_awvalid     = maxi4_if.awvalid;
  assign axi4_wr_wdata       = maxi4_if.wdata  ;
  assign axi4_wr_wstrb       = maxi4_if.wstrb  ;
  assign axi4_wr_wlast       = maxi4_if.wlast  ;
  assign axi4_wr_wvalid      = maxi4_if.wvalid ;
  assign axi4_wr_bready      = maxi4_if.bready ;

  assign maxi4_if.awready    = axi4_wr_awready;
  assign maxi4_if.wready     = axi4_wr_wready;
  assign maxi4_if.bid        = axi4_wr_bid;
  assign maxi4_if.bresp      = axi4_wr_bresp;
  assign maxi4_if.bvalid     = axi4_wr_bvalid;

  // Read channel
  assign maxi4_if.arready    = 1'b0;
  assign maxi4_if.rid        = '0;
  assign maxi4_if.rdata      = 'x  ;
  assign maxi4_if.rresp      = '0 ;
  assign maxi4_if.rlast      = '0;
  assign maxi4_if.rvalid     = 1'b0;

// ============================================================================================== --
// Scenario
// ============================================================================================== --
  initial begin
    gid_offset = '0;
    gid_offset[AXI4_DATA_BYTES_W+:START_ADD_RANGE_W] = $urandom_range(0,START_ADD_RANGE-1);
    $display("> INFO: gid_offset=0x%0x", gid_offset);
  end

//---------------------------------
// FSM
//---------------------------------
  typedef enum {ST_IDLE,
                ST_FILL_MEM,
                ST_PROCESS,
                ST_DONE} state_e;

  state_e state;
  state_e next_state;
  logic st_idle;
  logic st_fill_mem;
  logic st_process;
  logic st_done;

  logic start;
  logic fill_mem_done;
  logic proc_done;

  always_comb
    case (state)
      ST_IDLE:
        next_state = start ? ST_FILL_MEM : state;
      ST_FILL_MEM:
        next_state = fill_mem_done ? ST_PROCESS : state;
      ST_PROCESS:
        next_state = proc_done ? ST_DONE : state;
      ST_DONE:
        next_state = state;
    endcase

  always_ff @(posedge clk)
    if (!s_rst_n) state <= ST_IDLE;
    else          state <= next_state;

  assign st_idle     = state == ST_IDLE;
  assign st_fill_mem = state == ST_FILL_MEM;
  assign st_process  = state == ST_PROCESS;
  assign st_done     = state == ST_DONE;

//---------------------------------
// Start reading
//---------------------------------
  integer proc_cnt;
  always_ff @(posedge clk)
    if (!s_rst_n) proc_cnt <= '0;
    else          proc_cnt <= (!st_process || proc_cnt == PROC_CYCLE_NB) ? proc_cnt : proc_cnt + 1;

  assign start_rd = proc_cnt == PROC_CYCLE_NB;

//---------------------------------
// Fill memory
//---------------------------------
  initial begin
    data2_t glwe_q[$];
    data2_t ct_data;
    logic [AXI4_DATA_W-1:0] axi_q[$];
    logic [GLWE_COEF_PER_AXI4_WORD-1:0][GLWE_ACS_W-1:0] g_axi_word;

    maxi4_if.init();
    fill_mem_done <= 1'b0;

    wait (st_fill_mem);
    @(posedge clk);
    $display("%t > INFO: Load ciphertexts in memory.", $time);

    // Write GLWE
    axi_q.delete();
    for (int p=0; p<TOTAL_GID_NB; p=p+1)
      for (int i=0; i<AXI4_WORD_PER_GLWE_BODY*GLWE_COEF_PER_AXI4_WORD; i=i+1) begin
        ct_data.d0.gid      = p;
        ct_data.d0.coef_id  = i;
        ct_data.d0.part     = 0;
        ct_data.d1.gid      = p;
        ct_data.d1.coef_id  = i;
        ct_data.d1.part     = 1;
        glwe_q.push_back(ct_data);
      end
    while (glwe_q.size() > 0) begin
      g_axi_word = '0;
      for (int i=0; i<GLWE_COEF_PER_AXI4_WORD; i=i+1) begin
        if (glwe_q.size() == 0)
          $fatal(1,"> ERROR: glwe ct number mismatch!");
        g_axi_word[i][0+:LSB_W]     = get_data(glwe_q[0].d0);
        g_axi_word[i][LSB_W+:MSB_W] = get_data(glwe_q[0].d1);
        glwe_q.pop_front();
        //$display("INFO > IN : [%0d] MSB=0x%0x LSB=0x%0x", i, g_axi_word[i][0+:LSB_W], g_axi_word[i][LSB_W+:MSB_W]);
      end
      axi_q.push_back(g_axi_word);
    end

    maxi4_if.write_trans(gid_offset, axi_q);

    @(posedge clk) begin
      fill_mem_done <= 1'b1;
    end
    $display("%t > INFO: Start process.", $time);
  end // initial

//---------------------------------
// Process
//---------------------------------
  integer         cmd_gid;
  load_glwe_cmd_t cmd;

  assign cmd.gid      = cmd_gid % TOTAL_GID_NB;
  assign cmd.pid.pid  = cmd.gid % TOTAL_PBS_NB;
  assign cmd.pid.grid = cmd.pid.pid % GRAM_NB;
  assign cmd.pid.grof = cmd.pid.pid / GRAM_NB;
  assign seq_ldg_cmd  = cmd;
  stream_source
  #(
    .FILENAME   ("counter"),
    .DATA_TYPE  ("ascii_hex"),
    .DATA_W     (32),
    .RAND_RANGE (RAND_RANGE),
    .KEEP_VLD   (1'b0),
    .MASK_DATA  ("x")
  ) cmd_stream_source (
      .clk       (clk),
      .s_rst_n   (s_rst_n),

      .data      (cmd_gid),
      .vld       (seq_ldg_vld),
      .rdy       (seq_ldg_rdy),

      .throughput(INST_THROUGHPUT)
  );

  logic in_cmd_done;
  assign proc_done = in_cmd_done;
  initial begin
    integer dummy;
    in_cmd_done = 1'b0;
    dummy = cmd_stream_source.open();
    wait(st_process);
    @(posedge clk);
    cmd_stream_source.start(SAMPLE_NB);
    wait (cmd_stream_source.running);
    wait (!cmd_stream_source.running);

    in_cmd_done = 1'b1;
  end

  // Arbiter
  always_ff @(posedge clk)
    if (!s_rst_n) garb_ldg_avail_1h <= '0;
    else          garb_ldg_avail_1h <= 1 << $urandom_range(0,GRAM_NB-1);

// ============================================================================================== --
// Check
// ============================================================================================== --

  generate
      for (genvar gen_g=0; gen_g < GRAM_NB; gen_g = gen_g + 1) begin : gen_gram_loop
        for (genvar gen_p=0; gen_p < PSI; gen_p = gen_p + 1) begin : gen_psi_loop
          for (genvar gen_r=0; gen_r < R; gen_r = gen_r + 1) begin : gen_r_loop

            integer glwe_stg_iter;
            integer glwe_stg_iterD;
            integer glwe_gid;
            integer glwe_gidD;
            integer glwe_pid;
            logic   glwe_last_stg_iter;
            logic   wr_en;

            assign wr_en              = glwe_ram_wr_en[gen_g][gen_p][gen_r];
            assign glwe_last_stg_iter = glwe_stg_iter == STG_ITER_NB-1;
            assign glwe_stg_iterD     = wr_en ? glwe_last_stg_iter ? '0 : glwe_stg_iter + 1 : glwe_stg_iter;
            assign glwe_gidD          = wr_en && glwe_last_stg_iter ? (glwe_gid + GRAM_NB)%TOTAL_GID_NB : glwe_gid;
            assign glwe_pid           = glwe_gid % TOTAL_PBS_NB;

            always_ff @(posedge clk)
              if (!s_rst_n) begin
                glwe_stg_iter <= '0;
                glwe_gid      <= gen_g;
              end
              else begin
                glwe_stg_iter <= glwe_stg_iterD;
                glwe_gid      <= glwe_gidD;
              end

            // Check
            logic   error_data_l;
            logic   error_add_l;

            assign error_data[gen_g][gen_p][gen_r] = error_data_l;
            assign error_add[gen_g][gen_p][gen_r]  = error_add_l;

            always_ff @(posedge clk)
              if (!s_rst_n) begin
                error_data_l <= 1'b0;
                error_add_l  <= 1'b0;
              end
              else begin
                //== Check GLWE
                if (glwe_ram_wr_en[gen_g][gen_p][gen_r]) begin
                  data2_t ct_d;
                  logic [MOD_Q_W-1:0]        ref_data;
                  logic [GLWE_RAM_ADD_W-1:0] ref_add;

                  // check data
                  ct_d.d0.gid     = glwe_gid;
                  ct_d.d0.coef_id = glwe_stg_iter *(R*PSI) + gen_p*R + gen_r;
                  ct_d.d0.part    = 0;
                  ct_d.d1.gid     = ct_d.d0.gid;
                  ct_d.d1.coef_id = ct_d.d0.coef_id;
                  ct_d.d1.part    = 1;

                  ref_data = '0;
                  ref_data[0+:LSB_W]     = get_data(ct_d.d0);
                  ref_data[LSB_W+:MSB_W] = get_data(ct_d.d1);

                  assert(glwe_ram_wr_data[gen_g][gen_p][gen_r] == ref_data)
                  else begin
                    $display("%t > ERROR: Data mismatch GLWE grid=%0d gid=%0d  psi=%0d r=%0d exp=0x%0x seen=0x%0x.",
                          $time, gen_g, glwe_gid, gen_p, gen_r, ref_data, glwe_ram_wr_data[gen_g][gen_p][gen_r]);
                    error_data_l <= 1'b1;
                  end

                  // check address
                  // Write only body
                  ref_add = (STG_ITER_NB * ((glwe_pid / GRAM_NB) * GLWE_K_P1 + GLWE_K)) + glwe_stg_iter;
                  //$display("%t > INFO: GRID=%0d, psi=%0d r=%0d, stg_iter=%0d, pid=%0d, ref_add=0x%0x r=%0d PSI=%0d",
                  //          $time, gen_g,gen_p,gen_r,glwe_stg_iter, glwe_pid, ref_add, gen_r, PSI);
                  assert(ref_add == glwe_ram_wr_add[gen_g][gen_p][gen_r])
                  else begin
                    $display("%t > ERROR: Address mismatch GLWE grid=%0d pid=%0d psi=%0d r=%0d exp=0x%0x seen=0x%0x",
                          $time, gen_g, glwe_pid, gen_p, gen_r, ref_add, glwe_ram_wr_add[gen_g][gen_p][gen_r]);
                    error_add_l <= 1'b1;
                  end

                end // if glwe_ram_wr_en
              end // else

          end // gen_r_loop
        end // gen_psi_loop
      end // gen_gram_loop
  endgenerate

// ============================================================================================== --
// Control
// ============================================================================================== --
  always_ff @(posedge clk) begin
    if (!s_rst_n) start <= 1'b0;
    else          start <= 1'b1;
  end

  integer cmd_done_nb;
  always_ff @(posedge clk)
    if (!s_rst_n) cmd_done_nb <= '0;
    else          cmd_done_nb <= ldg_seq_done ? cmd_done_nb + 1 : cmd_done_nb;

  initial begin
    end_of_test = 1'b0;
    wait (st_done);
    $display("%t > INFO: All commands have been sent.", $time);
    wait (cmd_done_nb == SAMPLE_NB);
    $display("%t > INFO: All done have been received.", $time);

    @(posedge clk);
    end_of_test = 1'b1;
  end

endmodule
