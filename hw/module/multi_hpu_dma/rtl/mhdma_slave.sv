// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Multi-HPU-DMA slave module
// ----------------------------------------------------------------------------------------------
// Must react to decoded commands
//  -> Notify RX
//  -> Ciphertext emission
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
  // must not add default values to theses parameters, comming from bridge module
  parameter int PC_NB_WORDS       [ETH_PC],
  parameter int PC_REMAINS        [ETH_PC],
  parameter int PC_NB_READS       [ETH_PC]
) (
  // Ethernet configuration interface -----------------------------------------
  input  logic                                clk_cfg,
  input  logic                                resetn_cfg,
  // Ethernet fast clock interface --------------------------------------------
  input  logic                                clk_mrmac,
  input  logic                                resetn_mrmac,
  // regf interface -----------------------------------------------------------
  input  logic [ETH_PC-1:0][2*REG_DATA_W-1:0] regf_ct_mem_addr,
  output logic             [  REG_DATA_W-1:0] regf_notify_payload,
  // Received header ----------------------------------------------------------
  input  header_t                             decoded_header,
  // Command interface --------------------------------------------------------
  input  logic                                notify_request_received,
  input  logic                                read_request_received,

  output logic                                new_notify_ack_pending,
  output logic                                new_ct_emission_request_pending,

  input  logic                                notify_ack_allowed,
  input  logic                                ct_emission_allowed,

  input  logic                                ct_emission_finished,
  // format interface ---------------------------------------------------------
  output logic             [   NRX_WIDTH-1:0] nrx_cmd_payload,
  output logic                                nrx_valid,
  input  logic                                notify_ack_sent,
  output logic             [   CEH_WIDTH-1:0] ce_header_payload,
  output logic             [MRMAC_AXIS_W-1:0] ce_payload,
  output logic                                ce_valid,
  input  logic                                ce_ready,
  // Axi4 interface for NMU ---------------------------------------------------
  output logic [ETH_PC-1:0][  AXI4_ADD_W-1:0] m_axi4_araddr,
  output logic [ETH_PC-1:0][  AXI4_LEN_W-1:0] m_axi4_arlen,
  output logic [ETH_PC-1:0][ AXI4_SIZE_W-1:0] m_axi4_arsize,
  output logic [ETH_PC-1:0][AXI4_BURST_W-1:0] m_axi4_arburst,
  output logic [ETH_PC-1:0]                   m_axi4_arvalid,
  input  logic [ETH_PC-1:0]                   m_axi4_arready,

  input  logic [ETH_PC-1:0][AXI4_DATA_W-1:0]  m_axi4_rdata,
  input  logic [ETH_PC-1:0][AXI4_RESP_W-1:0]  m_axi4_rresp,
  input  logic [ETH_PC-1:0]                   m_axi4_rlast,
  input  logic [ETH_PC-1:0]                   m_axi4_rvalid,
  output logic [ETH_PC-1:0]                   m_axi4_rready,
  // interrupt ----------------------------------------------------------------
  input  logic                                clear_interrupt_notify,
  output logic                                interrupt_notify
);

  // =========================================================================================== //
  // localparam
  // =========================================================================================== //
  localparam NB_MRMRAC_WORDS_PER_READ = AXI4_DATA_W/MRMAC_AXIS_W;

  // ==============================================================================================
  // Notify RX (NRX)
  // ==============================================================================================
  // => must transmit to regfile IOP_ID, HPU_ID and src_addr
  // => must trigger interrupt signal when registers are ready to be read
  typedef enum logic [1:0] {
    NTW_XXX          = 'x,
    NTX_WAIT_REQUEST = 2'b00,
    NTX_TRANSMIT_ACK = 2'b1
  } st_nrx;

  st_nrx nrx_state;
  st_nrx nrx_next_state;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) nrx_state <= NTX_WAIT_REQUEST;
    else nrx_state <= nrx_next_state;
  end

  always_comb begin
    nrx_next_state = NTW_XXX;
    case (nrx_state)
      NTX_WAIT_REQUEST:
        nrx_next_state = notify_request_received ? NTX_TRANSMIT_ACK : NTX_WAIT_REQUEST;
      NTX_TRANSMIT_ACK:
        nrx_next_state = notify_ack_sent ? NTX_WAIT_REQUEST : NTX_TRANSMIT_ACK;
    endcase
  end

  assign new_notify_ack_pending =  (nrx_state == NTX_TRANSMIT_ACK) ? 1'b1 : 1'b0;

  // Notify command queue -----------------------------------------------------
  logic                 nrx_cmd_in_vld;
  logic                 nrx_cmd_in_rdy;
  logic [NRX_WIDTH-1:0] nrx_cmd_data;
  logic                 nrx_cmd_vld;
  logic                 nrx_cmd_rdy;
  logic                 fifo_2clk_rdy;

  assign nrx_cmd_in_vld = (nrx_state == NTX_TRANSMIT_ACK) & decoded_header.valid & nrx_cmd_in_rdy;

  // in order to not lose any commands if we receive several notify
  // nrx_cmd_data is redirected as well to notify ack and to regif interface via 2clk fifo
  fifo_ram_rdy_vld # (
    .WIDTH      (NRX_WIDTH),
    .DEPTH      (NRX_DEPTH),
    .RAM_LATENCY(NRX_DATA_COUNT_W)
  ) fifo_nrx_commands (
    .clk    (clk_mrmac),
    .s_rst_n(resetn_mrmac),

    .in_data({decoded_header.src_addr, decoded_header.hpu_id, decoded_header.iop_id}),
    .in_vld (nrx_cmd_in_vld),
    .in_rdy (nrx_cmd_in_rdy),

    .out_data(nrx_cmd_data),
    .out_vld (nrx_cmd_vld),
    .out_rdy (nrx_cmd_rdy)
  );

  logic notify_ack_allowed_tmp;
  logic notify_ack_front_edge;
  always_ff @(posedge clk_mrmac)
    notify_ack_allowed_tmp <= notify_ack_allowed;

  assign notify_ack_front_edge = notify_ack_allowed & ~ notify_ack_allowed_tmp;

  // backpressure from both 2clk fifo and nack
  assign nrx_cmd_rdy = fifo_2clk_rdy & notify_ack_front_edge;

  // signals that will be propagated to format module for ack
  assign nrx_cmd_payload = nrx_cmd_vld ? nrx_cmd_data : 'h0;
  assign nrx_valid       = nrx_cmd_vld & nrx_cmd_rdy;

  // regfile interface --------------------------------------------------------
  // === MRMAC domain
  logic [SRC_ADDR_W-1:0]     nrx_ct_src_addr;
  logic [HPU_ID_W-1:0]       nrx_hpu_id;
  logic [IOP_ID_W-1:0]       nrx_iop_id;
  logic [NRX_REGF_WIDTH-1:0] nrxq_in_data;
  // === CFG domain
  logic                      nrqq_out_vld;
  logic                      nrqq_out_rdy;

  assign nrx_ct_src_addr = nrx_cmd_data[NRX_SRC_ADDR_OFS-1:NRX_HPU_ID_OFS];
  assign nrx_hpu_id      = nrx_cmd_data[NRX_HPU_ID_OFS-1:NRX_IOP_ID_OFS];
  assign nrx_iop_id      = nrx_cmd_data[NRX_IOP_ID_OFS-1:0];

  assign nrxq_in_data = {nrx_ct_src_addr, 4'b0, nrx_hpu_id, nrx_iop_id};

  // this fifo transforms rx commands into a 32 bit readable word for regfile
  fifo_ram_rdy_vld_2clk # (
    .CDC_SYNC_STAGES (CDC_SYNC_STAGES),
    // tweak theses parameters in package
    .WIDTH           (NRX_REGF_WIDTH),
    .DEPTH           (XPM_MIN_FIFO_DEPTH),
    .FIFO_MEMORY_TYPE(NRX_REGF_MEMORY_TYPE)
  ) nrx_fifo_ram_rdy_vld_2clk (
    // Write Domain ports: MRMAC domain
    .in_clk   (clk_mrmac),
    .in_rstn  (resetn_mrmac),
    .in_data  (nrxq_in_data),
    .in_rdy   (fifo_2clk_rdy),
    .in_vld   (nrx_valid),
    // Read Domain ports: CFG domain
    .out_clk  (clk_cfg),
    .out_rstn (resetn_cfg),
    .out_data (regf_notify_payload),
    .out_rdy  (nrqq_out_rdy),
    .out_vld  (nrqq_out_vld)
  );

  assign interrupt_notify = nrqq_out_vld;
  assign nrqq_out_rdy = interrupt_notify & clear_interrupt_notify;

  // ==============================================================================================
  // Ciphertext EMission (CEM)
  // ==============================================================================================
  // FSM ------------------------------------------------------------------------------------------
  typedef enum logic [1:0] {
    CEM_XXX           = 'x,
    CEM_WAIT_REQUEST  = 2'b0,
    CEM_READ_N_SEND   = 2'b1
  } st_cem;

  st_cem cem_state;
  st_cem cem_next_state;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) cem_state <= CEM_WAIT_REQUEST;
    else cem_state <= cem_next_state;
  end

  always_comb begin
    cem_next_state = CEM_XXX;
    case (cem_state)
      CEM_WAIT_REQUEST:
        cem_next_state = ct_emission_allowed ? CEM_READ_N_SEND : CEM_WAIT_REQUEST;
      CEM_READ_N_SEND:
        cem_next_state = ct_emission_finished ? CEM_WAIT_REQUEST : CEM_READ_N_SEND;
    endcase
  end

  assign ct_emission_request_in_use = (cem_state == CEM_READ_N_SEND) ? 1'b1: 1'b0;

  // sending command to read request command queue ------------------------------------------------
  // when qsfp tlast is ready we are sure that all commands have been correctly received
  // we need to pass along:
  //    > IOP ID
  //    > HPU ID
  //    > DST ADDR
  //    > SRC ADDR
  // RREQ_CMD_DATA_W is defined in the package

  logic [RREQ_CMD_DATA_W-1:0] rreq_cmd_data_in;
  logic [RREQ_CMD_DATA_W-1:0] rreq_cmd_out_data;
  logic                       rreq_cmd_ready; // ~full
  logic                       rreq_cmd_we;
  logic                       rreq_cmd_out_valid;
  logic                       rreq_cmd_out_ready;

  assign rreq_cmd_data_in = {decoded_header.hpu_id, decoded_header.iop_id, decoded_header.dst_addr, decoded_header.src_addr};
  assign rreq_cmd_we = rreq_cmd_ready & read_request_received; //TODO: add when payload is ready
  assign rreq_cmd_out_ready = ct_emission_request_in_use;

  fifo_ram_rdy_vld # (
    .WIDTH      (RREQ_CMD_DATA_W),
    .DEPTH      (RREQ_CMD_DEPTH),
    .RAM_LATENCY(RREQ_CMD_RAM_LATENCY)
  ) rreq_command_queue (
    .clk    (clk_mrmac),
    .s_rst_n(resetn_mrmac),

    .in_data(rreq_cmd_data_in),
    .in_vld (rreq_cmd_we),
    .in_rdy (rreq_cmd_ready),

    .out_data(rreq_cmd_out_data),
    .out_vld (rreq_cmd_out_valid),
    .out_rdy (rreq_cmd_out_ready)
  );

  logic [RQQ_CMD_DATA_COUNT_W-1:0] rreq_cnt;
  logic                            rreq_cnt_down;

  assign rreq_cnt_down = rreq_cmd_out_valid & rreq_cmd_out_ready;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      rreq_cnt <= 'h0;
    end else begin
      if (rreq_cmd_we & ~rreq_cnt_down) begin
        rreq_cnt <= rreq_cnt + 1;
      end else if (rreq_cnt_down & ~rreq_cmd_we) begin
        rreq_cnt <= rreq_cnt - 1;
      end
    end
  end
  assign new_ct_emission_request_pending = (rreq_cnt != 0) ? 1'b1 : 1'b0;

  logic error_rreq_cmd_full_packet_drop;
  // assign error_rreq_cmd_full_packet_drop = qsfp_rx_tlast & ~rreq_cmd_ready;

  // =========================================================================================== //
  // Read into HBM
  // all @mrmac domain
  // TODO add status signals to know how much time we are not reading into fifo
  // TODO add status signals to know how much time we are not reading into fifo
  // TODO add status signals to know how much time we are not reading into fifo
  // =========================================================================================== //
  logic [RREQ_CMD_DATA_W-1:0] read_request_cmd;
  // logic [       SIZE_B_W-1:0] ;
  logic [       HPU_ID_W-1:0] rr_hpu_id;
  logic [       IOP_ID_W-1:0] rr_iop_id;
  logic [     SRC_ADDR_W-1:0] rr_ct_src_addr;
  logic [     DST_ADDR_W-1:0] rr_ct_dst_addr;


  always_ff @(posedge clk_mrmac)
    if (rreq_cmd_out_valid & rreq_cmd_out_ready)
      read_request_cmd <= rreq_cmd_out_data;

  assign rr_hpu_id      = read_request_cmd[RR_HPU_ID_OFS-1:RR_IOP_ID_OFS];
  assign rr_iop_id      = read_request_cmd[RR_IOP_ID_OFS-1:RR_DST_ID_OFS];
  assign rr_ct_dst_addr = read_request_cmd[RR_DST_ID_OFS-1:RR_SRC_ID_OFS];
  assign rr_ct_src_addr = (rreq_cmd_out_valid & rreq_cmd_out_ready) ? rreq_cmd_out_data[RR_SRC_ID_OFS-1:0] : 0;

  // phys_addr = hbm_pc_offset + ctId * ciphertext_size
  logic [ETH_PC-1:0] [AXI4_ADD_W-1:0] phy_addr;
  generate
    for (genvar gen_p=0; gen_p<ETH_PC; gen_p=gen_p+1)
      always_ff @(posedge clk_mrmac)
          if (rreq_cmd_out_valid & rreq_cmd_out_ready)
            phy_addr[gen_p] <= regf_ct_mem_addr[gen_p] + (rr_ct_src_addr << PC_STRIDE);
  endgenerate

  // Is read request ready ------------------------------------------------------------------------
  // flag that states that read request is ready
  logic rreq_ready;
  logic rreq_ready_tmp;
  always_ff @(posedge clk_mrmac)
    rreq_ready <= rreq_cmd_out_valid & rreq_cmd_out_ready;
  always_ff @(posedge clk_mrmac)
    rreq_ready_tmp <= rreq_ready;

  logic rreq_ready_pulse;
  assign rreq_ready_pulse = rreq_ready & ~rreq_ready_tmp;

  // process an axi4-read on each PC --------------------------------------------------------------
  //  - arlen the burst size is dictated from parameter MAX_BURST_SIZE
  //  - arburst would be INCR
  //  - arsize the size of each data transfer, fixed to MHDMA_ARSIZE
  // let's start ciphertext emission when its flag is up and we are not changing command values
  logic [ETH_PC-1:0] axi4_read_pc;
  logic [ETH_PC-1:0] axi4_read_last;
  // TODO: TOREVIEW :: we probably could read at the same time the two PCs and not one by one
  generate
    for (genvar gen_rd=0; gen_rd<ETH_PC; gen_rd++) begin : gen_ce_reads
      logic [$clog2(PC_NB_READS[gen_rd]):0] axi_read_cnt;
      logic                                                axi_read;

      // Counts the number of clock cycles that must perform reads taking account bursts
      // because we decrement from axi4_read_pc we add one to count all words
      always_ff @(posedge clk_mrmac) begin
        if (~resetn_mrmac) begin
          axi_read_cnt <= PC_NB_READS[gen_rd];
          axi_read <= 1'b0;
        end else begin
          if ((axi_read_cnt > 0) && axi4_read_pc[gen_rd] && m_axi4_arready[gen_rd]) begin
            axi_read <= 1'b1;
            axi_read_cnt <= axi_read_cnt - 1;
          end else if (axi4_read_last[gen_rd]) begin
            axi_read <= 1'b0;
            axi_read_cnt <= PC_NB_READS[gen_rd];
          end
        end
      end

      logic [AXI4_ADD_W-1:0] mhdma_read_addr;
      // read address takes the physical address computed earlier as soon as the value is ready
      // when starting the reading process we compute the offset accounting burst sequence
      always_ff @(posedge clk_mrmac) begin
        if (axi_read_cnt == PC_NB_READS[gen_rd]) begin
          mhdma_read_addr <= phy_addr[gen_rd];
        end else begin
          mhdma_read_addr <= mhdma_read_addr + (AXI4_DATA_BYTES*MAX_BURST_SIZE);
        end
      end

      // m_axi4_arid[gen_rd] not used
      assign m_axi4_araddr[gen_rd]  = (axi_read && m_axi4_arready[gen_rd]) ? mhdma_read_addr :'h0;
      assign m_axi4_arsize[gen_rd]  = (axi_read && m_axi4_arready[gen_rd]) ? MHDMA_ARSIZE    :'h0;
      assign m_axi4_arburst[gen_rd] = (axi_read && m_axi4_arready[gen_rd]) ? 2'b01           :'h0; // incr
      assign m_axi4_arvalid[gen_rd] = (axi_read && m_axi4_arready[gen_rd]) ? 1'b1            :'h0;
      // there is not arlast, this is only an intermediate signal
      assign axi4_read_last[gen_rd] = ((axi_read && m_axi4_arready[gen_rd]) & (axi_read_cnt == 0)) ? 1'b1 : 1'b0;

      always_comb begin
        if ((PC_REMAINS[gen_rd] !=0) && (axi_read_cnt == 0)) begin
          m_axi4_arlen[gen_rd] = (axi_read && m_axi4_arready[gen_rd]) ? PC_REMAINS[gen_rd]-1 : 'h0;
        end else begin
          m_axi4_arlen[gen_rd] = (axi_read && m_axi4_arready[gen_rd]) ? MAX_BURST_SIZE-1 : 'h0;
        end
      end

      // we read if and only if we are in ciphertext emission mode
      assign m_axi4_rready[gen_rd]  = ct_emission_request_in_use;
    end
  endgenerate

  // Reception FIFOs for both PC ports ------------------------------------------------------------
  // one hot value that selects which PC is selected to be read and sent to QSFP lane
  // always start with PC0
  logic [ETH_PC-1:0]                reading_which_pc;
  logic [ETH_PC-1:0]                fifo_ce_pc_in_rdy;
  logic [ETH_PC-1:0][CE_DATA_W-1:0] fifo_ce_pc_in_data;
  logic [ETH_PC-1:0]                fifo_ce_pc_in_vld;

  generate
    for (genvar gen_rd=0; gen_rd<ETH_PC; gen_rd++) begin : gen_read_fifo
      // input part
      logic                   read_fifo_we;
      logic                   read_fifo_ready; // ~full
      // output part
      logic [AXI4_DATA_W-1:0] read_fifo_out_data;
      logic                   read_fifo_out_valid;
      logic                   read_fifo_out_ready;

      assign read_fifo_we = m_axi4_rvalid[gen_rd] & read_fifo_ready & ct_emission_request_in_use;

      fifo_ram_rdy_vld # (
        .WIDTH      (FIFO_PC_DATA_W),
        .DEPTH      (FIFO_PC_DEPTH),
        .RAM_LATENCY(FIFO_PC_RAM_LATENCY)
      ) fifo_pc_read (
        .clk    (clk_mrmac),
        .s_rst_n(resetn_mrmac),

        .in_data(m_axi4_rdata[gen_rd]),
        .in_vld (read_fifo_we),
        .in_rdy (read_fifo_ready),

        .out_data(read_fifo_out_data),
        .out_vld (read_fifo_out_valid),
        .out_rdy (read_fifo_out_ready)
      );

      // we are going to read 4 times slower the fifo than we are feeding it
      logic [$clog2(NB_MRMRAC_WORDS_PER_READ)-1:0]         slow_pace_count;
      logic [$clog2(PC_NB_WORDS[gen_rd]):0] read_fifo_out_cnt;
      logic                                                pc_read_finished;

      always_ff @(posedge clk_mrmac) begin
        if (~resetn_mrmac) begin
          slow_pace_count <= 'h0;
        end else begin
          // If we want to read to this PC & the fifo is not empty
          if (reading_which_pc[gen_rd] & read_fifo_out_valid) begin
            slow_pace_count <= slow_pace_count + 1;
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
            read_fifo_out_cnt <= read_fifo_out_cnt +1;
          end else if (read_fifo_out_cnt == PC_NB_WORDS[gen_rd])  begin
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
          if(read_fifo_out_valid & read_fifo_out_ready) begin
            ce_data_out[gen_i] <= read_fifo_out_data[(gen_i+1)*MRMAC_AXIS_W-1:gen_i*MRMAC_AXIS_W];
          end
        end
      end

      logic [$clog2(NB_MRMRAC_WORDS_PER_READ)-1:0] realign_cnt;
      logic                                        start_deserialize;

      always_ff @(posedge clk_mrmac) begin
        if(~resetn_mrmac)begin
          start_deserialize <= 1'b0;
        end else begin
          if (reading_which_pc[gen_rd] & (read_fifo_out_valid & read_fifo_out_ready)) begin
            start_deserialize <= 1'b1;
          end else if (~reading_which_pc[gen_rd]) begin
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

      always_ff @(posedge clk_mrmac)
        fifo_ce_pc_in_data[gen_rd] <= ce_data_out[realign_cnt];

      always_ff @(posedge clk_mrmac)
          fifo_ce_pc_in_vld[gen_rd] <= start_deserialize;

    end
  endgenerate

  // which PC must be read ------------------------------------------------------------------------
  // those two processes are defined for two PCS only.

  // launch reads over the two PCs independently
  always_ff @(posedge clk_mrmac) begin : prc_read_one_at_a_time
    if (~resetn_mrmac) begin
      axi4_read_pc <= 'h0;
    end else begin
      // when read request registers are ready we can trigger the shift register.
      // when the last signal is fired we can trigger the second PC
      if (rreq_ready_pulse | axi4_read_last[0]) begin
        axi4_read_pc <= {axi4_read_pc[ETH_PC-2:0], rreq_ready_pulse};
      end else if (axi4_read_last[1]) begin
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
  logic [CE_DATA_COUNT_W:0] fifo_ce_cnt;
  logic [    CE_DATA_W-1:0] fifo_ce_in_data;
  logic                     fifo_ce_in_vld;
  logic                     fifo_ce_in_rdy;
  logic [    CE_DATA_W-1:0] fifo_ce_out_data;
  logic                     fifo_ce_out_vld;

  // data in input are already in the correct form for sending directly to the lane
  assign  fifo_ce_in_vld  = (reading_which_pc[0] == 1) ? fifo_ce_pc_in_vld[0]  : (reading_which_pc[1] == 1) ? fifo_ce_pc_in_vld[1] : 1'b0;
  assign  fifo_ce_in_data = fifo_ce_in_vld & (reading_which_pc[0] == 1) ? fifo_ce_pc_in_data[0] : fifo_ce_in_vld & (reading_which_pc[1] == 1)  ? fifo_ce_pc_in_data[1] : 'h0;

  // backpressure over ready for each fifo
  assign fifo_ce_pc_in_rdy[0] = (reading_which_pc == 1) ? fifo_ce_in_rdy : 1'b0;
  assign fifo_ce_pc_in_rdy[1] = (reading_which_pc == 2) ? fifo_ce_in_rdy : 1'b0;

  logic cnt_fifo_up;
  logic cnt_fifo_down;

  assign cnt_fifo_up   = fifo_ce_in_vld & fifo_ce_in_rdy;
  assign cnt_fifo_down = ce_valid & ce_ready;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      fifo_ce_cnt <= 'h0;
    end else begin
      if (cnt_fifo_up & ~cnt_fifo_down) begin
        fifo_ce_cnt <= fifo_ce_cnt + 1;
      end else if (cnt_fifo_down & ~cnt_fifo_up) begin
        fifo_ce_cnt <= fifo_ce_cnt - 1;
      end
    end
  end

  fifo_ram_rdy_vld # (
    .WIDTH      (CE_DATA_W),
    .DEPTH      (CE_DEPTH),
    .RAM_LATENCY(CE_DATA_COUNT_W)
  ) fifo_ce (
    .clk    (clk_mrmac),
    .s_rst_n(resetn_mrmac),

    .in_data(fifo_ce_in_data),
    .in_vld (fifo_ce_in_vld),
    .in_rdy (fifo_ce_in_rdy),

    .out_data(fifo_ce_out_data),
    .out_vld (fifo_ce_out_vld),
    .out_rdy (ce_ready)
  );

  assign ce_valid = fifo_ce_out_vld;
  assign ce_payload = ce_valid ? fifo_ce_out_data : 'h0;

  // header propagation ---------------------------------------------------------------------------
  // TODO: can be simplified ?
  logic [MAC_ADDR_W-1:0] src_mac_addr;
  logic [  HPU_ID_W-1:0] hpu_id;
  logic [  SIZE_B_W-1:0] size_b;
  logic [  IOP_ID_W-1:0] iop_id;
  logic [DST_ADDR_W-1:0] ct_dst_addr;
  logic [SRC_ADDR_W-1:0] ct_src_addr;

  always_ff @(posedge clk_mrmac) begin
    if (decoded_header.valid) begin
      src_mac_addr <= decoded_header.src_mac_addr;
      hpu_id       <= decoded_header.hpu_id;
      size_b       <= decoded_header.size_b;
      iop_id       <= decoded_header.iop_id;
      ct_src_addr  <= decoded_header.src_addr;
      ct_dst_addr  <= decoded_header.dst_addr;
    end
  end

  // our destination mac address was the source of what we received
  assign ce_header_payload = {src_mac_addr, iop_id, hpu_id, size_b, ct_dst_addr, ct_src_addr};

endmodule
