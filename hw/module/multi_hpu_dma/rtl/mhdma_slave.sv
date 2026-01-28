// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Multi-HPU-DMA Slave module
// ----------------------------------------------------------------------------------------------
// Must react to decoded commands
//
// This module handles the logic around ciphertext emission and Notify ack
// ==============================================================================================

module mhdma_slave
  import mhdma_pkg::*;               // for all mhdma modules
  import axi_if_eth_axi_pkg::*;      // AXI4
  import axi_if_shell_axil_pkg::*;   // REG_DATA_W
  import axi_if_common_param_pkg::*; // HBM page
#(
  parameter int   CDC_SYNC_STAGES = 2,
  parameter int   MAX_BURST_SIZE  = PAGE_BYTES/AXI4_DATA_BYTES,
  parameter [3:0] PC_STRIDE       = 'hB,
  // must not add default values to theses parameters, coming from bridge module
  parameter int   PC_NB_WORDS    [ETH_PC],
  parameter int   PC_REMAINS     [ETH_PC],
  parameter int   PC_NB_READS    [ETH_PC]
) (
  // Ethernet configuration interface -----------------------------------------
  input  logic                                clk_cfg,
  input  logic                                resetn_cfg,
  // Ethernet fast clock interface --------------------------------------------
  input  logic                                clk_mrmac,
  input  logic                                resetn_mrmac,
  // Axi4 interface for NMU ---------------------------------------------------
  output logic [ETH_PC-1:0][  AXI4_ADD_W-1:0]                  m_axi4_araddr,
  output logic [ETH_PC-1:0][  AXI4_LEN_W-1:0]                  m_axi4_arlen,
  output logic [ETH_PC-1:0][ AXI4_SIZE_W-1:0]                  m_axi4_arsize,
  output logic [ETH_PC-1:0][AXI4_BURST_W-1:0]                  m_axi4_arburst,
  output logic [ETH_PC-1:0]                                    m_axi4_arvalid,
  input  logic [ETH_PC-1:0]                                    m_axi4_arready,
  output logic [ETH_PC-1:0][axi_if_eth_axi_pkg::AXI4_ID_W-1:0] m_axi4_arid,

  input  logic [ETH_PC-1:0][AXI4_DATA_W-1:0]                   m_axi4_rdata,
  input  logic [ETH_PC-1:0]                                    m_axi4_rlast,
  input  logic [ETH_PC-1:0]                                    m_axi4_rvalid,
  output logic [ETH_PC-1:0]                                    m_axi4_rready,
  // regf interface -----------------------------------------------------------
  input  logic [ETH_PC-1:0][2*REG_DATA_W-1:0] regf_ct_mem_addr,
  output logic             [  REG_DATA_W-1:0] regf_notify_payload,
  // interrupt ----------------------------------------------------------------
  input  logic                                clear_interrupt_notify,
  output logic                                interrupt_notify,
  // decoder interface --------------------------------------------------------
  input  command_t                            decoded_command,
  input  logic                                decoded_command_vld,
  output logic                                decoded_command_rdy,
  // format interface ---------------------------------------------------------
  output command_t                            slave_command,
  output command_t                            slave_command_vld,
  input  command_t                            slave_command_rdy,

  output logic             [MRMAC_AXIS_W-1:0] ce_payload,
  output logic                                ce_vld,
  input  logic                                ce_rdy,

  input  logic                                ciphertext_sent,
  input  logic                                notify_ack_sent,
  // statistics ---------------------------------------------------------------
  // counters
  output logic             [  REG_DATA_W-1:0] stat_nb_read_to_hbm,
  output logic [ETH_PC-1:0][  REG_DATA_W-1:0] stat_nb_words_received_pc,
  output logic [ETH_PC-1:0][  REG_DATA_W-1:0] stat_t_rr_wait_words_pc,
  // rst
  input  logic                                rst_nb_read_to_hbm,
  input  logic [ETH_PC-1:0]                   rst_nb_words_received_pc,
  // register
  output logic [1:0]                          stat_fsm_notify_rx,
  output logic [1:0]                          stat_fsm_cem,
  output logic [ETH_PC-1:0][2*REG_DATA_W-1:0] stat_rr_phy_addr
);

  // =========================================================================================== //
  // localparam
  // =========================================================================================== //
  localparam NB_MRMRAC_WORDS_PER_READ = AXI4_DATA_W/MRMAC_AXIS_W;

  logic error_fifo_nrx_commands_ovf;

  // =========================================================================================== //
  // localparam
  // =========================================================================================== //
  logic received_notify;
  logic received_read_request;

  assign received_notify       = decoded_command_vld & (decoded_command.req_id == REQ_ID_NOTIFY);
  assign received_read_request = decoded_command_vld & (decoded_command.req_id == REQ_ID_READ);

  // ==============================================================================================
  // Notify RX (NRX)
  // ==============================================================================================
  logic start_notify_ack;
  logic st_wait_notify;
  logic st_transmit_ack;

  // => must transmit to regfile IOP_ID, HPU_ID and src_addr
  // => must trigger interrupt signal when registers are ready to be read
  typedef enum logic [1:0] {
    NTW_XXX          = 'x,
    NRX_WAIT_REQUEST = 2'b01,
    NRX_TRANSMIT_ACK = 2'b10
  } st_nrx;

  st_nrx nrx_state;
  st_nrx nrx_next_state;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) nrx_state <= NRX_WAIT_REQUEST;
    else nrx_state <= nrx_next_state;
  end

  assign start_notify_ack = decoded_command_rdy & received_notify;

  always_comb begin
    nrx_next_state = NTW_XXX;
    case (nrx_state)
      NRX_WAIT_REQUEST:
        nrx_next_state = start_notify_ack ? NRX_TRANSMIT_ACK : NRX_WAIT_REQUEST;
      NRX_TRANSMIT_ACK:
        nrx_next_state = notify_ack_sent ? NRX_WAIT_REQUEST : NRX_TRANSMIT_ACK;
    endcase
  end

  assign st_wait_notify = (nrx_state == NRX_WAIT_REQUEST);
  assign st_transmit_ack = (nrx_state == NRX_TRANSMIT_ACK);

  // Notify RX command queue --------------------------------------------------
  logic                 nrx_cmd_in_vld;
  logic                 nrx_cmd_in_rdy;

  assign nrx_cmd_in_vld = received_notify & nrx_cmd_in_rdy;

  // erreur notify lost
  logic    nrx_cmd_out_vld;
  logic    nrx_cmd_out_rdy;
  command_t nrx_cmd_fifo;

  // command fifo for notify RX, received from decoder
  fifo_ram_rdy_vld # (
    .WIDTH      (SRC_ADDR_W+HPU_ID_W+IOP_ID_W+REQ_ID_W),
    .DEPTH      (NRX_DEPTH),
    .RAM_LATENCY(NRX_RAM_LATENCY)
  ) fifo_nrx_commands (
    .clk         (clk_mrmac),
    .s_rst_n     (resetn_mrmac),

    .in_data     ({decoded_command.src_addr, decoded_command.hpu_id, decoded_command.iop_id, REQ_ID_NOTIFY_ACK}),
    .in_vld      (nrx_cmd_in_vld),
    .in_rdy      (nrx_cmd_in_rdy),

    .out_data    ({nrx_cmd_fifo.src_addr, nrx_cmd_fifo.hpu_id, nrx_cmd_fifo.iop_id, nrx_cmd_fifo.req_id}),
    .out_vld     (nrx_cmd_out_vld),
    .out_rdy     (nrx_cmd_out_rdy),

    .almost_full (/* UNUSED */)
  );

  assign error_fifo_nrx_commands_ovf = received_notify & ~nrx_cmd_in_rdy;

  // Notify RX regfile interface --------------------------------------------------------
  logic nrx_regf_in_rdy;
  logic nrx_regf_in_vld;

  assign nrx_cmd_out_rdy = st_transmit_ack & slave_command_rdy & nrx_regf_in_rdy;
  assign nrx_regf_in_vld = nrx_cmd_out_vld & nrx_cmd_out_rdy;

  // === CFG domain
  logic [REG_DATA_W-1:0] nrx_regf_out_data;
  logic                  nrx_regf_out_rdy;
  logic                  nrx_regf_out_vld;

  // this fifo transforms rx commands into a 32 bit readable word for regfile
  fifo_ram_rdy_vld_2clk # (
    .CDC_SYNC_STAGES (CDC_SYNC_STAGES),
    // tweak theses parameters in package
    .WIDTH           (REG_DATA_W),
    .DEPTH           (REQ_FIFO_DEPTH),
    .FIFO_MEMORY_TYPE(REQ_MEMORY_TYPE)
  ) fifo_nrx_regf (
    // Write Domain ports: MRMAC domain
    .in_clk      (clk_mrmac),
    .in_rstn     (resetn_mrmac),
    .in_data     ({nrx_cmd_fifo.src_addr, 4'b0, nrx_cmd_fifo.hpu_id, nrx_cmd_fifo.iop_id}),
    .in_rdy      (nrx_regf_in_rdy),
    .in_vld      (nrx_regf_in_vld),
    .almost_full (/* UNUSED */),
    // Read Domain ports: CFG domain
    .out_clk     (clk_cfg),
    .out_rstn    (resetn_cfg),
    .out_data    (nrx_regf_out_data),
    .out_rdy     (nrx_regf_out_rdy),
    .out_vld     (nrx_regf_out_vld)
  );

  assign nrx_regf_out_rdy = clear_interrupt_notify;

  // directly to regif interface
  assign regf_notify_payload = nrx_regf_out_data;
  assign interrupt_notify = nrx_regf_out_vld;

  // ==============================================================================================
  // Ciphertext EMission (CEM)
  // ==============================================================================================
  // FSM ------------------------------------------------------------------------------------------
  logic start_of_ct_emission;
  logic st_wait_rr;
  logic st_read_send;

  typedef enum logic [1:0] {
    CEM_XXX           = 'x,
    CEM_WAIT_REQUEST  = 2'b01,
    CEM_READ_N_SEND   = 2'b10
  } st_cem;

  st_cem cem_state;
  st_cem cem_next_state;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) cem_state <= CEM_WAIT_REQUEST;
    else cem_state <= cem_next_state;
  end

  assign start_of_ct_emission  = decoded_command_rdy & received_read_request;

  always_comb begin
    cem_next_state = CEM_XXX;
    case (cem_state)
      CEM_WAIT_REQUEST:
        cem_next_state = start_of_ct_emission ? CEM_READ_N_SEND : CEM_WAIT_REQUEST;
      CEM_READ_N_SEND:
        cem_next_state = ciphertext_sent ? CEM_WAIT_REQUEST : CEM_READ_N_SEND;
    endcase
  end

  assign st_read_send = (cem_state == CEM_READ_N_SEND);
  assign st_wait_rr   = (cem_state == CEM_WAIT_REQUEST);

  // sending command to read request command queue ------------------------------------------------
  // when qsfp tlast is ready we are sure that all commands have been correctly received
  // we need to pass along:
  //    > HPU ID
  //    > IOP ID
  //    > DST ADDR
  //    > SRC ADDR
  //   => REQ ID must be switched from read request to ciphertext emission

  logic    rreq_cmd_in_vld;
  logic    rreq_cmd_in_rdy; // ~full

  command_t rreq_cmd_fifo;
  logic    rreq_cmd_out_vld;
  logic    rreq_cmd_out_rdy;

  assign rreq_cmd_in_vld = start_of_ct_emission & rreq_cmd_in_rdy;

  fifo_ram_rdy_vld # (
    .WIDTH      (HPU_ID_W+IOP_ID_W+DST_ADDR_W+SRC_ADDR_W+REQ_ID_W),
    .DEPTH      (RREQ_CMD_DEPTH),
    .RAM_LATENCY(RREQ_CMD_RAM_LATENCY)
  ) rreq_command_queue (
    .clk         (clk_mrmac),
    .s_rst_n     (resetn_mrmac),

    .in_data     ({decoded_command.hpu_id, decoded_command.iop_id, decoded_command.dst_addr, decoded_command.src_addr, REQ_ID_EMISSION}),
    .in_vld      (rreq_cmd_in_vld),
    .in_rdy      (rreq_cmd_in_rdy),

    .out_data    ({rreq_cmd_fifo.hpu_id, rreq_cmd_fifo.iop_id, rreq_cmd_fifo.dst_addr, rreq_cmd_fifo.src_addr, rreq_cmd_fifo.req_id}),
    .out_vld     (rreq_cmd_out_vld),
    .out_rdy     (rreq_cmd_out_rdy),

    .almost_full (/* UNUSED */)
  );

  logic error_rreq_command_queue_ovf;
  assign error_rreq_command_queue_ovf = start_of_ct_emission & ~rreq_cmd_in_rdy;

  always_ff @(posedge clk_mrmac)
    rreq_cmd_out_rdy <= st_read_send & slave_command_rdy; /// !!! TODO

  logic [RQQ_CMD_DATA_COUNT_W-1:0] rreq_cnt;
  logic                            rreq_cnt_down;
  logic                            rreq_cnt_up;

  assign rreq_cnt_down = rreq_cmd_out_vld & rreq_cmd_out_rdy;
  assign rreq_cnt_up   = rreq_cmd_in_vld & rreq_cmd_in_rdy;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      rreq_cnt <= 'h0;
    end else begin
      if (rreq_cnt_up & ~rreq_cnt_down) begin
        rreq_cnt <= rreq_cnt + 1;
      end else if (rreq_cnt_down & ~rreq_cnt_up) begin
        rreq_cnt <= rreq_cnt - 1;
      end
    end
  end

  logic error_rreq_cmd_full_packet_drop;
  // assign error_rreq_cmd_full_packet_drop = qsfp_rx_tlast & ~rreq_cmd_in_rdy;

  // ==============================================================================================
  // Consuming Decoded commands
  // ==============================================================================================
  assign decoded_command_rdy =  (st_wait_notify & ~st_read_send & received_notify & nrx_cmd_in_rdy) | (st_wait_rr & ~st_transmit_ack & received_read_request & rreq_cmd_in_rdy);

  // =========================================================================================== //
  // Read into HBM
  // all @mrmac domain
  // =========================================================================================== //
  logic [SRC_ADDR_W-1:0] rr_ct_src_addr;
  logic [DST_ADDR_W-1:0] rr_ct_dst_addr;

  assign rr_ct_dst_addr = rreq_cmd_fifo.dst_addr;
  assign rr_ct_src_addr = rreq_cmd_fifo.src_addr;

  // phys_addr = hbm_pc_offset + ctId * ciphertext_size
  logic [ETH_PC-1:0] [AXI4_ADD_W-1:0] phy_addr;
  logic [ETH_PC-1:0]                  phy_addr_valid;
  generate
    for (genvar gen_p=0; gen_p<ETH_PC; gen_p=gen_p+1) begin
      always_ff @(posedge clk_mrmac)
        if (rreq_cmd_out_rdy & rreq_cmd_out_vld)
          phy_addr[gen_p] <= regf_ct_mem_addr[gen_p] + (rr_ct_dst_addr << PC_STRIDE);

      always_ff @(posedge clk_mrmac) begin
        if (~resetn_mrmac) begin
          phy_addr_valid[gen_p] <= 'h0;
        end else begin
          phy_addr_valid[gen_p] <= rreq_cmd_out_rdy & rreq_cmd_out_vld;
        end
      end
    end
  endgenerate

  // Is read request ready ------------------------------------------------------------------------
  // flag that states that read request is ready
  logic rreq_ready;
  logic rreq_ready_tmp;
  always_ff @(posedge clk_mrmac)
    rreq_ready <= rreq_cmd_out_vld & rreq_cmd_out_rdy;
  always_ff @(posedge clk_mrmac)
    rreq_ready_tmp <= rreq_ready;

  logic rreq_ready_pulse;
  assign rreq_ready_pulse = rreq_ready & ~rreq_ready_tmp;

  // process an axi4-read on each PC --------------------------------------------------------------
  //  - arlen the burst size is dictated from parameter MAX_BURST_SIZE
  //  - arburst would be INCR
  //  - arsize the size of each data transfer, fixed to MHDMA_ARSIZE
  // let's start ciphertext emission when its flag is up and we are not changing command values
  // We must read each PC one by one
  logic [ETH_PC-1:0] axi4_read_pc;        // this signal is a one hot selecting PC that we want to use
  logic [ETH_PC-1:0] axi4_read_last;      // intermediary signal that states when to change from pc to next
  logic [ETH_PC-1:0] finished_reading_pc;
  logic [ETH_PC-1:0] read_fifo_ready;     // ready from receiving FIFO
  generate
    for (genvar gen_rd=0; gen_rd<ETH_PC; gen_rd++) begin : gen_ce_reads
      logic [$clog2(PC_NB_READS[gen_rd]):0] axi_read_cnt;
      axi4_ar_if_t axi_ar;
      axi4_ar_if_t axi_arvalid;
      axi4_ar_if_t axi_arready;

      // Counts the number of clock cycles that must perform reads taking account bursts
      // because we decrement from axi4_read_pc we add one to count all words
      always_ff @(posedge clk_mrmac) begin
        if (~resetn_mrmac) begin
          axi_read_cnt <= PC_NB_READS[gen_rd];
        end else begin
          if ( axi_arready & axi_arvalid & (axi_read_cnt > 0) & axi4_read_pc[gen_rd]) begin
            axi_read_cnt <= axi_read_cnt - 1;
          end else if (ciphertext_sent) begin
            axi_read_cnt <= PC_NB_READS[gen_rd];
          end
        end
      end

      logic [AXI4_ADD_W-1:0] mhdma_read_addr;
      // read address takes the physical address computed earlier as soon as the value is ready
      // when starting the reading process we compute the offset accounting burst sequence
      always_ff @(posedge clk_mrmac) begin
        if (phy_addr_valid[gen_rd]) begin
          mhdma_read_addr <= phy_addr[gen_rd];
        end else begin
          // incrementation occurs only if read is consumed
          if (axi_arready & axi_arvalid) begin
            mhdma_read_addr <= mhdma_read_addr + (AXI4_DATA_BYTES*MAX_BURST_SIZE);
          end
        end
      end

      assign axi_arvalid = (axi_read_cnt > 0) & axi4_read_pc[gen_rd];

      assign axi_ar.arid    = MHDMA_AXI_ARID;
      assign axi_ar.araddr  = axi_arvalid ? mhdma_read_addr :'h0;
      assign axi_ar.arsize  = axi_arvalid ? MHDMA_ARSIZE    :'h0;
      assign axi_ar.arburst = axi_arvalid ? 2'b01           :'h0; // incr
      // there is not arlast, this is only an intermediate signal
      assign axi4_read_last[gen_rd] = axi_arready & axi_arvalid & (axi_read_cnt == 1);

      always_comb begin
        if ((PC_REMAINS[gen_rd] !=0) & axi4_read_last[gen_rd]) begin
          axi_ar.arlen = axi_arvalid ? PC_REMAINS[gen_rd]-1 : 'h0;
        end else begin
          axi_ar.arlen = axi_arvalid ? MAX_BURST_SIZE-1 : 'h0;
        end
      end

      axi4_ar_if_t m_axi4_a;

      fifo_element #(
        .WIDTH          ($bits(axi4_ar_if_t)),
        .DEPTH          (1),
        .TYPE_ARRAY     (4'h3),
        .DO_RESET_DATA  (1'b0),
        .RESET_DATA_VAL (0)
      ) fifo_element_address_read (
        .clk     (clk_mrmac   ),
        .s_rst_n (resetn_mrmac),

        .in_data (axi_ar),
        .in_vld  (axi_arvalid),
        .in_rdy  (axi_arready),

        .out_data(m_axi4_a),
        .out_vld (m_axi4_arvalid[gen_rd]),
        .out_rdy (m_axi4_arready[gen_rd])
      );

      assign m_axi4_arid[gen_rd]    = m_axi4_a.arid;
      assign m_axi4_araddr[gen_rd]  = m_axi4_a.araddr;
      assign m_axi4_arlen[gen_rd]   = m_axi4_a.arlen;
      assign m_axi4_arsize[gen_rd]  = m_axi4_a.arsize;
      assign m_axi4_arburst[gen_rd] = m_axi4_a.arburst;

    end
  endgenerate

  // Reception FIFOs for both PC ports ------------------------------------------------------------
  // one hot value that selects which PC is selected to be read and sent to QSFP lane
  // always start with PC0
  logic [ETH_PC-1:0]                   reading_which_pc;
  logic [ETH_PC-1:0]                   fifo_ce_pc_in_rdy;
  logic [ETH_PC-1:0][MRMAC_AXIS_W-1:0] fifo_ce_pc_in_data;
  logic [ETH_PC-1:0]                   fifo_ce_pc_in_vld;

  generate
    for (genvar gen_rd=0; gen_rd<ETH_PC; gen_rd++) begin : gen_read_fifo
      // input part
      logic                   read_fifo_we;
      // output part
      logic [AXI4_DATA_W-1:0] read_fifo_out_data;
      logic                   read_fifo_out_valid;
      logic                   read_fifo_out_ready;

      // we read if and only if we are in ciphertext emission mode
      assign m_axi4_rready[gen_rd] = read_fifo_ready[gen_rd] & st_read_send;

      assign read_fifo_we = m_axi4_rvalid[gen_rd] & m_axi4_rready[gen_rd];

      fifo_ram_rdy_vld # (
        .WIDTH      (AXI4_DATA_W),
        .DEPTH      (FIFO_PC_DEPTH),
        .RAM_LATENCY(FIFO_PC_RAM_LATENCY)
      ) fifo_pc_read (
        .clk         (clk_mrmac),
        .s_rst_n     (resetn_mrmac),

        .in_data     (m_axi4_rdata[gen_rd]),
        .in_vld      (read_fifo_we),
        .in_rdy      (read_fifo_ready[gen_rd]),

        .out_data    (read_fifo_out_data),
        .out_vld     (read_fifo_out_valid),
        .out_rdy     (read_fifo_out_ready),

        .almost_full (/* UNUSED */)
      );

      // we are going to read 4 times slower the fifo than we are feeding it
      logic [$clog2(NB_MRMRAC_WORDS_PER_READ)-1:0] slow_pace_count;
      logic [$clog2(PC_NB_WORDS[gen_rd]):0]        read_fifo_out_cnt;
      logic                                        pc_read_finished;

      always_ff @(posedge clk_mrmac) begin
        if (~resetn_mrmac) begin
          slow_pace_count <= 'h0;
        end else begin
          // If we want to read to this PC & the fifo is not empty
          if (reading_which_pc[gen_rd]) begin
            if (read_fifo_out_valid) begin
              slow_pace_count <= slow_pace_count + 1;
            end
          end else begin
            slow_pace_count <= 'h0;
          end
        end
      end

      always_ff @(posedge clk_mrmac) begin
        if(~resetn_mrmac) begin
          read_fifo_out_cnt <= 'h0;
        end else begin
          if (read_fifo_out_ready & read_fifo_out_valid) begin
            read_fifo_out_cnt <= read_fifo_out_cnt + 1;
          end else if (read_fifo_out_cnt == PC_NB_WORDS[gen_rd]) begin
            read_fifo_out_cnt <= 'h0;
          end
        end
      end

      // because in one read we have NB_MRMRAC_WORDS_PER_READ, we must delay the signal pc_read_finished
      logic [NB_MRMRAC_WORDS_PER_READ-1:0] temp_finished_flag;
      always_ff @(posedge clk_mrmac)
        temp_finished_flag[0] <= (read_fifo_out_cnt == PC_NB_WORDS[gen_rd]);

      for (genvar gen_i = 1; gen_i<NB_MRMRAC_WORDS_PER_READ; gen_i++) begin
        always_ff @(posedge clk_mrmac)
          temp_finished_flag[gen_i] <= temp_finished_flag[gen_i-1];
      end

      assign pc_read_finished = temp_finished_flag[NB_MRMRAC_WORDS_PER_READ-1];

      // read word each 4 clock cycles, we trigger at 1 as slow_pace_count default is 0
      assign read_fifo_out_ready = (slow_pace_count == 1) && reading_which_pc[gen_rd] & fifo_ce_pc_in_rdy[gen_rd];

      logic [NB_MRMRAC_WORDS_PER_READ-1:0][MRMAC_AXIS_W-1:0] ce_data_out;
      for (genvar gen_i=0; gen_i<NB_MRMRAC_WORDS_PER_READ; gen_i++) begin
        always_ff @(posedge clk_mrmac) begin
          if(read_fifo_out_ready & read_fifo_out_valid) begin
            ce_data_out[gen_i] <= read_fifo_out_data[(gen_i+1)*MRMAC_AXIS_W-1:gen_i*MRMAC_AXIS_W];
          end
        end
      end

      logic [NB_MRMRAC_WORDS_PER_READ-1:0] temp_rdy_vld;
      always_ff @(posedge clk_mrmac)
        temp_rdy_vld[0] <= read_fifo_out_ready & read_fifo_out_valid;

      for (genvar gen_i = 1; gen_i<NB_MRMRAC_WORDS_PER_READ; gen_i++) begin
        always_ff @(posedge clk_mrmac)
          temp_rdy_vld[gen_i] <= temp_rdy_vld[gen_i-1];
      end

      logic [$clog2(NB_MRMRAC_WORDS_PER_READ)-1:0] realign_cnt;
      logic                                        start_deserialize;

      always_ff @(posedge clk_mrmac) begin
        if(~resetn_mrmac)begin
          start_deserialize <= 1'b0;
        end else begin
          if (reading_which_pc[gen_rd] & (read_fifo_out_valid & read_fifo_out_ready)) begin
            start_deserialize <= 1'b1;
          end else if (temp_rdy_vld[NB_MRMRAC_WORDS_PER_READ-1]) begin
            start_deserialize <= 1'b0;
          end
        end
      end

      always_ff @(posedge clk_mrmac) begin
        if(~resetn_mrmac) begin
          realign_cnt <= 'h0;
        end else begin
          if (start_deserialize) begin
            realign_cnt <= realign_cnt + 1;
            // we need to take into account that ce_data_out arrives one cc later
          end else begin
            realign_cnt <= 'h0;
          end
        end
      end

      // always_ff @(posedge clk_mrmac)
      assign fifo_ce_pc_in_data[gen_rd] = ce_data_out[realign_cnt];

      // always_ff @(posedge clk_mrmac)
      assign fifo_ce_pc_in_vld[gen_rd] = start_deserialize;

    end
  endgenerate

  // which PC must be read ------------------------------------------------------------------------
  // those two processes are defined for two PCS only.
  generate
    for (genvar gen_rd=0; gen_rd<ETH_PC; gen_rd++) begin : gen_control_pc
      logic [$clog2(PC_NB_READS[gen_rd]):0] nb_read;
      // when do I finished reading ?
      always_ff @(posedge clk_mrmac) begin
        if (~resetn_mrmac)begin
          nb_read <= 'h0;
        end else begin
          if (m_axi4_rlast[gen_rd] & m_axi4_rvalid[gen_rd]) begin
            nb_read <= nb_read + 1;
          end else if (nb_read == PC_NB_READS[gen_rd]) begin
            nb_read <= 'h0;
          end
        end
      end

      assign finished_reading_pc[gen_rd] = (nb_read == PC_NB_READS[gen_rd]);
    end
  endgenerate

  // launch reads over the two PCs independently
  always_ff @(posedge clk_mrmac) begin : prc_read_one_at_a_time
    if (~resetn_mrmac) begin
      axi4_read_pc <= 'h0;
    end else begin
      // when read request registers are ready we can trigger the shift register.
      // when the last signal is fired we can trigger the second PC
      if (rreq_ready_pulse |  axi4_read_last[0]) begin
        axi4_read_pc <= {axi4_read_pc[ETH_PC-2:0], rreq_ready_pulse};
      end else if (finished_reading_pc[1]) begin
        axi4_read_pc <= 'h0;
      end
    end
  end

  // we only have one QSFP lane interface, we will read each PC FIFO independently, one at a time
  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      reading_which_pc <= 'h0;
    end else begin
      // at initialization we insert rreq_ready when read request is ready to be performed
      // once the whole fifo has been fully read
      if (rreq_ready_pulse | (gen_read_fifo[0].pc_read_finished) | (gen_read_fifo[1].pc_read_finished)) begin
        reading_which_pc <= {reading_which_pc[ETH_PC-2:0], rreq_ready_pulse};
      end
    end
  end

  // Fifo Ciphertext Emission ---------------------------------------------------------------------
  logic [MRMAC_AXIS_W-1:0]  fifo_ce_in_data;
  logic                     fifo_ce_in_vld;
  logic                     fifo_ce_in_rdy;

  // data in input are already in the correct form for sending directly to the lane
  assign  fifo_ce_in_vld  = (reading_which_pc[0] == 1) ? fifo_ce_pc_in_vld[0]  : (reading_which_pc[1] == 1) ? fifo_ce_pc_in_vld[1] : 1'b0;
  assign  fifo_ce_in_data = fifo_ce_in_vld & (reading_which_pc[0] == 1) ? fifo_ce_pc_in_data[0] : fifo_ce_in_vld & (reading_which_pc[1] == 1) ? fifo_ce_pc_in_data[1] : 'h0;

  // backpressure over ready for each fifo
  assign fifo_ce_pc_in_rdy[0] = (reading_which_pc == 1) ? fifo_ce_in_rdy : 1'b0;
  assign fifo_ce_pc_in_rdy[1] = (reading_which_pc == 2) ? fifo_ce_in_rdy : 1'b0;

  fifo_ram_rdy_vld # (
    .WIDTH      (MRMAC_AXIS_W   ),
    .DEPTH      (CT_NB_COEF     ),
    .RAM_LATENCY(CE_RAM_LATENCY ),
    .ALMOST_FULL_REMAIN (0)
  ) fifo_ce (
    .clk         (clk_mrmac),
    .s_rst_n     (resetn_mrmac),

    .in_data     (fifo_ce_in_data),
    .in_vld      (fifo_ce_in_vld),
    .in_rdy      (fifo_ce_in_rdy),

    .out_data    (ce_payload),
    .out_vld     (ce_vld),
    .out_rdy     (ce_rdy),
    .almost_full (/* UNUSED */)
  );

  // =========================================================================================== //
  // Interface to formatter
  // =========================================================================================== //
  // acks takes precedence in from of read request
  always_ff @(posedge clk_mrmac) begin
    if (nrx_cmd_out_vld)  begin
      slave_command         <= nrx_cmd_fifo;
      slave_command_vld     <= nrx_cmd_out_vld;
      slave_command.size_b  <= 'h0;
    end else if (rreq_cmd_out_vld) begin
      slave_command         <= rreq_cmd_fifo;
      slave_command.size_b  <= SIZE_B; // Fixed for now
      slave_command_vld     <= rreq_cmd_out_vld;
    end else begin
      slave_command         <= 'h0;
      slave_command.size_b  <= 'h0;
      slave_command_vld     <= 'h0;
    end
  end

  // =========================================================================================== //
  // Statistics
  // =========================================================================================== //
  assign stat_fsm_notify_rx  = nrx_state;
  assign stat_fsm_cem        = cem_state;

  logic [REG_DATA_W-1:0] nb_read_to_hbm;
  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      nb_read_to_hbm <= 'h0;
    end else begin
      if (rst_nb_read_to_hbm) begin
        nb_read_to_hbm <= 'h0;
      end else begin
        if ((m_axi4_arready[0] & m_axi4_arvalid[0]) | (m_axi4_arready[1] & m_axi4_arvalid[1])) begin
          nb_read_to_hbm <= nb_read_to_hbm + 1;
        end
      end
    end
  end

  logic [ETH_PC-1:0][REG_DATA_W-1:0] nb_words_received_pc;
  generate
    for (genvar gen_i=0; gen_i<ETH_PC; gen_i++) begin : gen_i_nb_words_received
      always_ff @(posedge clk_mrmac) begin
        if (~resetn_mrmac) begin
          nb_words_received_pc[gen_i] <= 'h0;
        end else begin
          if (rst_nb_words_received_pc[gen_i]) begin
            nb_words_received_pc[gen_i] <= 'h0;
          end else begin
            if (m_axi4_rready[gen_i] & m_axi4_rvalid[gen_i]) begin
              nb_words_received_pc[gen_i] <= nb_words_received_pc[gen_i] + 1;
            end
          end
        end
      end
    end
  endgenerate

  // time waiting for words per pc
  // temps entre arvalid et rvalid
  logic [ETH_PC-1:0]                 t_wait_words_en;
  logic [ETH_PC-1:0][REG_DATA_W-1:0] t_rr_wait_words_pc;
  generate
    for (genvar gen_i=0; gen_i<ETH_PC; gen_i++) begin : gen_i_t_wait_for_words_pc

      // note that if we read several times we will include it in the counter
      always_ff @(posedge clk_mrmac) begin
        if(~resetn_mrmac) begin
          t_wait_words_en[gen_i] <= 1'b0;
        end else begin
          if (m_axi4_arvalid[gen_i]) begin
            t_wait_words_en[gen_i] <= 1'b1;
          end else if (m_axi4_rvalid[gen_i]) begin
            t_wait_words_en[gen_i] <= 1'b0;
          end
        end
      end


      always_ff @(posedge clk_mrmac) begin
        if (~resetn_mrmac) begin
          t_rr_wait_words_pc[gen_i] <= 'h0;
        end else begin
          if(t_wait_words_en[gen_i]) begin
            t_rr_wait_words_pc[gen_i] <= t_rr_wait_words_pc[gen_i] +1;
          end
        end
      end
    end
  endgenerate

  logic [ETH_PC-1:0][2*REG_DATA_W-1:0] rr_phy_addr;
  generate
    for (genvar gen_i=0; gen_i<ETH_PC; gen_i++) begin : gen_i_phy_addr
      assign rr_phy_addr[gen_i] = phy_addr[gen_i];
    end
  endgenerate

  assign stat_rr_phy_addr[0]          = rr_phy_addr[0];
  assign stat_rr_phy_addr[1]          = rr_phy_addr[1];
  assign stat_nb_read_to_hbm          = nb_read_to_hbm;
  assign stat_nb_words_received_pc[0] = nb_words_received_pc[0];
  assign stat_nb_words_received_pc[1] = nb_words_received_pc[1];
  assign stat_t_rr_wait_words_pc[0] = t_rr_wait_words_pc[0];
  assign stat_t_rr_wait_words_pc[1] = t_rr_wait_words_pc[1];

endmodule
