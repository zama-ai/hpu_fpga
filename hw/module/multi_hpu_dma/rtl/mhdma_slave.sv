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
  parameter                int CDC_SYNC_STAGES = 2,
  parameter                int MAX_BURST_SIZE  = PAGE_BYTES/AXI4_DATA_BYTES,
  parameter [ETH_PC-1:0][15:0] PC_CT_BYTES     = '{'h2000, 'h2020},
  parameter             [15:0] PC_STRIDE       = 'h3000
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
  input  logic             [  MAC_ADDR_W-1:0] rx_dst_mac_addr,
  input  logic             [   SEQ_NUM_W-1:0] rx_sec_num,
  input  logic             [    HPU_ID_W-1:0] rx_hpu_id,
  input  logic             [    REQ_ID_W-1:0] rx_req_id,
  input  logic             [  MAC_ADDR_W-1:0] rx_src_mac_addr,
  input  logic             [    SIZE_B_W-1:0] rx_size_b,
  input  logic             [    IOP_ID_W-1:0] rx_iop_id,
  input  logic             [  SRC_ADDR_W-1:0] rx_ct_src_addr,
  input  logic             [  DST_ADDR_W-1:0] rx_ct_dst_addr,
  input  logic                                rx_header_valid,
  // Command interface --------------------------------------------------------
  input  logic                                notify_request_received,
  input  logic                                read_request_received,

  output logic                                new_notify_read_pending,
  output logic                                new_notify_ack_pending,

  input  logic                                notify_ack_allowed,
  input  logic                                ct_emission_allowed,
  // format interface ---------------------------------------------------------
  output logic             [   NRX_WIDTH-1:0] nrx_cmd_payload,
  output logic                                nrx_valid,
  input  logic                                notify_ack_sent,
  // Axi4 interface for NMU ---------------------------------------------------
  output logic [ETH_PC-1:0][   AXI4_ID_W-1:0] m_axi4_arid,
  output logic [ETH_PC-1:0][  AXI4_ADD_W-1:0] m_axi4_araddr,
  output logic [ETH_PC-1:0][  AXI4_LEN_W-1:0] m_axi4_arlen,
  output logic [ETH_PC-1:0][ AXI4_SIZE_W-1:0] m_axi4_arsize,
  output logic [ETH_PC-1:0][AXI4_BURST_W-1:0] m_axi4_arburst,
  output logic [ETH_PC-1:0]                   m_axi4_arvalid,
  input  logic [ETH_PC-1:0]                   m_axi4_arready,
  input  logic [ETH_PC-1:0][  AXI4_ID_W-1:0]  m_axi4_rid,
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
  localparam [AXI4_SIZE_W-1:0] MHDMA_ARSIZE = $clog2(AXI4_DATA_BYTES);
  localparam NB_MRMRAC_WORDS_PER_READ = AXI4_DATA_W/MRMAC_AXIS_W;

  // generate cannot be in packages
  // PC_NB_READS: how many reads are needed per PCs
  // TOREVIEW: if ever ciphertexts are not aligned to a page, this will induce stalls
  // How to enforce ? / should it be enforced ?
  generate
    for (genvar gen_i = 0; gen_i < ETH_PC; gen_i = gen_i + 1) begin : gen_localparam
      localparam int PC_NB_READS = (PC_CT_BYTES[gen_i]/AXI4_DATA_BYTES) / MAX_BURST_SIZE;
      localparam int PC_NB_WORDS = PC_NB_READS*MAX_BURST_SIZE;
    end
  endgenerate

  // ==============================================================================================
  // Notify RX (NRX)
  // ==============================================================================================
  // => must transmit to regfile IOP_ID, HPU_ID and src_addr
  // => must trigger interrupt signal when registers are ready to be read
  typedef enum {
    NTX_WAIT_REQUEST,
    NTX_TRANSMIT_ACK
  } st_nrx;

  st_nrx nrx_state;
  st_nrx nrx_next_state;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) nrx_state <= NTX_WAIT_REQUEST;
    else nrx_state <= nrx_next_state;
  end

  always_comb begin
    case (nrx_state)
      NTX_WAIT_REQUEST:
        nrx_next_state = notify_request_received ? NTX_TRANSMIT_ACK : NTX_WAIT_REQUEST;
      NTX_TRANSMIT_ACK:
        nrx_next_state = notify_ack_sent ? NTX_WAIT_REQUEST : NTX_TRANSMIT_ACK;
    endcase
  end

  assign new_notify_ack_pending =  (nrx_state == NTX_TRANSMIT_ACK) ? 1'b1 : 1'b0;

  // Notify command queue -----------------------------------------------------
  logic                 nrx_cmd_in_we;
  logic                 nrx_cmd_in_rdy;
  logic [NRX_WIDTH-1:0] nrx_cmd_data;
  logic                 nrx_cmd_valid;
  logic                 nrx_cmd_rdy;
  logic                 nrx_cmd_rdy_tmp;

  // we temp rx_header_valid in order to read, at next clock cycle the fifo
  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      nrx_cmd_rdy_tmp <= 1'b0;
    end else begin
      if (~notify_ack_allowed & rx_header_valid) begin
        nrx_cmd_rdy_tmp <= rx_header_valid;
      end else if (notify_ack_allowed) begin
        nrx_cmd_rdy_tmp <= rx_header_valid;
      end
    end
  end

  assign nrx_cmd_in_we = notify_request_received & rx_header_valid & nrx_cmd_in_rdy;
  assign nrx_cmd_rdy   = notify_ack_allowed & nrx_cmd_rdy_tmp;

  // in order to not lose any commands if we receive several notify
  fifo_ram_rdy_vld # (
    .WIDTH      (NRX_WIDTH),
    .DEPTH      (NRX_DEPTH),
    .RAM_LATENCY(NRX_DATA_COUNT_W)
  ) fifo_nrx_commands (
    .clk    (clk_mrmac),
    .s_rst_n(resetn_mrmac),

    .in_data({rx_ct_src_addr, rx_hpu_id, rx_iop_id}),
    .in_vld (nrx_cmd_in_we),
    .in_rdy (nrx_cmd_in_rdy),

    .out_data(nrx_cmd_data),
    .out_vld (nrx_cmd_valid),
    .out_rdy (nrx_cmd_rdy)
  );

  // signals that will be propagated to format module
  assign nrx_cmd_payload = nrx_cmd_valid ? nrx_cmd_data : 'h0;
  assign nrx_valid       = nrx_cmd_valid;

  // NRX REGF queue ----------------------------------------------------------
  // === MRMAC domain
  logic nrxq_wr_en;
  logic nrxq_full;
  logic nrxq_wr_rst_busy;

  logic [SRC_ADDR_W-1:0] nrx_ct_src_addr;
  logic [HPU_ID_W-1:0]   nrx_hpu_id;
  logic [IOP_ID_W-1:0]   nrx_iop_id;

  // === CFG domain
  logic [NRX_DATA_COUNT_W-1:0] nrxq_rd_data_count;
  logic                        nrxq_empty;
  logic                        nrxq_rd_rst_busy;
  logic                        nrxq_data_valid;
  logic                        nrxq_rd_en;
  logic                        itr_notify;

  // enable when are sure that we have received a notify request + all words of the frames have been received
  // payload data will ready before last pulse will be triggered
  assign nrxq_wr_en      = nrx_valid & ~nrxq_full & ~nrxq_wr_rst_busy;
  assign nrx_ct_src_addr = nrx_cmd_data[NRX_SRC_ADDR_OFS-1:NRX_HPU_ID_OFS];
  assign nrx_hpu_id      = nrx_cmd_data[NRX_HPU_ID_OFS-1:NRX_IOP_ID_OFS];
  assign nrx_iop_id      = nrx_cmd_data[NRX_IOP_ID_OFS-1:0];

  assign new_notify_read_pending = (nrxq_rd_data_count == 0) ? 1'b0 : 1'b1;
  assign nrxq_rd_en = new_notify_read_pending & ~nrxq_rd_rst_busy & ~nrxq_empty;

  // this fifo transforms rx commands into a 32 bit readable word for regfile
  fifo_ram_rdy_vld_2clk # (
    .CDC_SYNC_STAGES (CDC_SYNC_STAGES),
    .WIDTH           (NRX_REGF_WIDTH),
    // tweak theses parameters in package
    .DEPTH           (XPM_MIN_FIFO_DEPTH),
    .FIFO_MEMORY_TYPE(NRX_REGF_MEMORY_TYPE)
  ) nrx_fifo_ram_rdy_vld_2clk (
    // Write Domain ports: MRMAC domain
    .wr_rstn      (resetn_mrmac),
    .wr_clk       (clk_mrmac),
    .wr_en        (nrxq_wr_en),
    .wr_data      ({nrx_ct_src_addr, 4'b0, nrx_hpu_id, nrx_iop_id}),
    .full         (nrxq_full),
    .wr_rst_busy  (nrxq_wr_rst_busy),
    // Read Domain ports: CFG domain
    .rd_clk       (clk_cfg),
    .rd_en        (nrxq_rd_en),
    .rd_data      (regf_notify_payload),
    .rd_data_count(nrxq_rd_data_count),
    .empty        (nrxq_empty),
    .rd_rst_busy  (nrxq_rd_rst_busy),
    .data_valid   (nrxq_data_valid)
  );

  // TODO: check what to do
  always_ff @(posedge clk_cfg) begin
    if (~resetn_cfg) begin
      itr_notify <= 1'b0;
    end else begin
      if(nrxq_data_valid) begin
        itr_notify <= 1'b1;
      end else if (clear_interrupt_notify) begin
        itr_notify <= 1'b0;
      end
    end
  end
  assign interrupt_notify = itr_notify;


  // ==============================================================================================
  // Ciphertext EMission (CEM)
  // ==============================================================================================
  // FSM ------------------------------------------------------------------------------------------
  logic cem_over;

  typedef enum {
    CEM_WAIT_REQUEST,
    CEM_READ_N_SEND
  } st_cem;

  st_cem cem_state;
  st_cem cem_next_state;

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) cem_state <= CEM_WAIT_REQUEST;
    else cem_state <= cem_next_state;
  end

  always_comb begin
    case (cem_state)
      CEM_WAIT_REQUEST:
        cem_next_state = new_ct_emission_request_pending ? CEM_READ_N_SEND : CEM_WAIT_REQUEST;
      CEM_READ_N_SEND:
        cem_next_state = cem_over ? CEM_WAIT_REQUEST : CEM_READ_N_SEND;
    endcase
  end

  assign ct_emission_request_in_use = (cem_state == CEM_READ_N_SEND) ? 1'b1: 1'b0;

  // TODO:
  assign cem_over = 1'b0;

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

  assign rreq_cmd_data_in = {rx_hpu_id, rx_iop_id, rx_ct_dst_addr, rx_ct_src_addr};
  assign rreq_cmd_we = rreq_cmd_ready & read_request_received; //TODO:add when payload is ready
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

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      rreq_cnt <= 'h0;
    end else begin
      if (rreq_cmd_we) begin
        rreq_cnt <= rreq_cnt + 1;
      end else if (rreq_cmd_out_valid & rreq_cmd_out_ready) begin
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


  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      read_request_cmd <= 'h0;
    end else begin
      if (rreq_cmd_out_valid & rreq_cmd_out_ready) begin
        read_request_cmd <= rreq_cmd_out_data;
      end
    end
  end

  assign rr_hpu_id      = read_request_cmd[RR_HPU_ID_OFS-1:RR_IOP_ID_OFS];
  assign rr_iop_id      = read_request_cmd[RR_IOP_ID_OFS-1:RR_DST_ID_OFS];
  assign rr_ct_dst_addr = read_request_cmd[RR_DST_ID_OFS-1:RR_SRC_ID_OFS];
  assign rr_ct_src_addr = (rreq_cmd_out_valid & rreq_cmd_out_ready) ? rreq_cmd_out_data[RR_SRC_ID_OFS-1:0] : 0;

  // phys_addr = hbm_pc_offset + ctId * ciphertext_size
  logic [ETH_PC-1:0] [AXI4_ADD_W-1:0] phy_addr;
  generate
    for (genvar gen_p=0; gen_p<ETH_PC; gen_p=gen_p+1)
      always_ff @(posedge clk_mrmac) begin
        if (~resetn_mrmac) begin
          phy_addr[gen_p] <= 'h0;
        end else begin
          if (rreq_cmd_out_valid & rreq_cmd_out_ready) begin
            phy_addr[gen_p] <= regf_ct_mem_addr[gen_p] + rr_ct_src_addr * PC_STRIDE;
          end
        end
      end
  endgenerate

  // flag that states that read request is ready
  logic rreq_ready;
  always_ff @(posedge clk_mrmac)
    rreq_ready <= rreq_cmd_out_valid & rreq_cmd_out_ready;

  // let's start ciphertext emission when its flag is up and we are not changing command values
  logic [ETH_PC-1:0] axi4_read_pc;
  logic [ETH_PC-1:0] axi4_read_last;

  // process an axi4-read on each PC
  //  - arlen the burst size is dictated from parameter MAX_BURST_SIZE
  //  - arburst whould be INCR
  //  - arsize the size of each data transfer, fixed to MHDMA_ARSIZE
  generate
    for (genvar gen_rd=0; gen_rd<ETH_PC; gen_rd++) begin : gen_ce_reads
      logic [$clog2(gen_localparam[gen_rd].PC_NB_READS):0] axi_read_cnt;
      logic                                                axi_read;

      // Counts the number of clock cycles that must perform reads taking account bursts
      // because we decrement from axi4_read_pc we add one to count all words
      always_ff @(posedge clk_mrmac) begin
        if (~resetn_mrmac) begin
          axi_read_cnt <= gen_localparam[gen_rd].PC_NB_READS;
          axi_read <= 1'b0;
        end else begin
          if ((axi_read_cnt > 0) & axi4_read_pc[gen_rd] & m_axi4_arready[gen_rd]) begin
            axi_read <= 1'b1;
            axi_read_cnt <= axi_read_cnt - 1;
          end else begin
            axi_read <= 1'b0;
            axi_read_cnt <= gen_localparam[gen_rd].PC_NB_READS;
          end
        end
      end

      logic [AXI4_ADD_W-1:0] mhdma_read_addr;
      // read address takes the physical address computed earlier as soon as the value is ready
      // when starting the reading process we compute the offset accounting burst sequence
      always_ff @(posedge clk_mrmac) begin
        if (~resetn_mrmac) begin
          mhdma_read_addr <= 'h0;
        end else begin
          if (axi_read_cnt == gen_localparam[gen_rd].PC_NB_READS) begin
            mhdma_read_addr <= phy_addr[gen_rd];
          end else begin
            mhdma_read_addr <= mhdma_read_addr + (NB_MRMRAC_WORDS_PER_READ*MAX_BURST_SIZE);
          end
        end
      end

      // m_axi4_arid[gen_rd]
      assign m_axi4_araddr[gen_rd]  = (axi_read) ? mhdma_read_addr :'h0;
      assign m_axi4_arlen[gen_rd]   = (axi_read) ? MAX_BURST_SIZE-1:'h0;
      assign m_axi4_arsize[gen_rd]  = (axi_read) ? MHDMA_ARSIZE    :'h0;
      assign m_axi4_arburst[gen_rd] = (axi_read) ? 2'b01           :'h0; // incr
      assign m_axi4_arvalid[gen_rd] = (axi_read) ? 1'b1            :'h0;
      // there is not arlast, this is only an intermediate signal
      assign axi4_read_last[gen_rd] = (axi_read & (axi_read_cnt == 0)) ? 1'b1 : 1'b0;

      // we read if and only if we are in ciphertext emission mode
      assign m_axi4_rready[gen_rd]  = ct_emission_request_in_use;

    end
  endgenerate

  // prc_read_one_at_a_time must much change if ETH_PC != 0 or we wand to read two PCs in parallel
  always_ff @(posedge clk_mrmac) begin : prc_read_one_at_a_time
    if (~resetn_mrmac) begin
      axi4_read_pc <= 'h0;
    end else begin
      // when read request registers are ready we can trigger the shift register.
      // when the last signal is fired we can trigger the second PC
      if (rreq_ready | (axi4_read_last[0])) begin
        axi4_read_pc <= {axi4_read_pc[ETH_PC-2:0], rreq_ready};
      end else if (axi4_read_last[1]) begin
        axi4_read_pc <= 'h0;
      end
    end
  end

  // one hot value that selects wich PC is selected to be read and sent to QSFP lane
  // always start with PC0
  logic [ETH_PC-1:0] reading_which_pc;

  logic [ETH_PC-1:0]                fifo_ce_pc_in_rdy;
  logic [ETH_PC-1:0][CE_DATA_W-1:0] fifo_ce_pc_in_data;
  logic [ETH_PC-1:0]                fifo_ce_pc_in_vld;

  // separate generate block for read fifo and its misc
  // add a backpressure to the read requests
  generate
    for (genvar gen_rd=0; gen_rd<ETH_PC; gen_rd++) begin : gen_read_fifo
      // input part
      logic                   read_fifo_we;
      logic                   read_fifo_ready; // ~full
      // output part
      logic [AXI4_DATA_W-1:0] read_fifo_out_data;
      logic [AXI4_DATA_W-1:0] read_fifo_out_dataD;
      logic                   read_fifo_out_valid;
      logic                   read_fifo_out_ready;
      logic                   all_words_have_arrived;

      assign read_fifo_we = m_axi4_rvalid[gen_rd] & read_fifo_ready & ct_emission_request_in_use;

      fifo_ram_rdy_vld # (
        .WIDTH      (READ_PC_DATA_W),
        .DEPTH      (READ_PC_DEPTH),
        .RAM_LATENCY(READ_PC_RAM_LATENCY)
      ) fifo_read_pc (
        .clk    (clk_mrmac),
        .s_rst_n(resetn_mrmac),

        .in_data(m_axi4_rdata[gen_rd]),
        .in_vld (read_fifo_we),
        .in_rdy (read_fifo_ready),

        .out_data(read_fifo_out_data),
        .out_vld (read_fifo_out_valid),
        .out_rdy (read_fifo_out_ready)
      );

      logic [$clog2(gen_localparam[gen_rd].PC_NB_WORDS):0] read_fifo_how_much_words_arrived;

      always_ff @(posedge clk_mrmac) begin
        if (~resetn_mrmac) begin
          read_fifo_how_much_words_arrived <= 'h0;
        end else begin
          if (read_fifo_we) begin
            read_fifo_how_much_words_arrived <= read_fifo_how_much_words_arrived + 1;
          end else begin
            read_fifo_how_much_words_arrived <= 'h0;
          end
        end
      end

      assign all_words_have_arrived = (read_fifo_how_much_words_arrived == gen_localparam[gen_rd].PC_NB_WORDS - 1);

      // we are going to read 4 times slower the fifo than we are feeding it
      logic [$clog2(NB_MRMRAC_WORDS_PER_READ)-1:0] slow_pace_count;
      logic [$clog2(gen_localparam[gen_rd].PC_NB_WORDS):0] read_fifo_out_cnt;
      logic pc_read_finished;

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
          end else if (read_fifo_out_cnt == gen_localparam[gen_rd].PC_NB_WORDS)  begin
            read_fifo_out_cnt <= 'h0;
          end
        end
      end
      always_ff @(posedge clk_mrmac) begin
        if(~resetn_mrmac) begin
          pc_read_finished <= 1'b0;
        end else begin
          if (read_fifo_out_cnt == gen_localparam[gen_rd].PC_NB_WORDS) begin
            pc_read_finished <= 1'b1;
          end else begin
            pc_read_finished <= 1'b0;
          end
        end
      end

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

    always_ff @(posedge clk_mrmac)
      fifo_ce_pc_in_data[gen_rd] <= ce_data_out[slow_pace_count];

    always_ff @(posedge clk_mrmac) begin
      if (~resetn_mrmac) begin
        fifo_ce_pc_in_vld[gen_rd] <= 1'b0;
      end else begin
        if (slow_pace_count == NB_MRMRAC_WORDS_PER_READ-1) begin
          fifo_ce_pc_in_vld[gen_rd] <= 1'b1;
        end else if (pc_read_finished) begin
        fifo_ce_pc_in_vld[gen_rd] <= 1'b0;
        end
      end
    end
    end
  endgenerate

  // we only have one QSFP lane interface, we will read each FIFO independantly, one at a time
  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      reading_which_pc <= 'h0;
    end else begin
      // at initialization we insert rreq_ready when read request is ready to be performed
      // once the whole fifo has been fully read
      if (rreq_ready | (gen_read_fifo[0].pc_read_finished) | (gen_read_fifo[1].pc_read_finished)) begin
        reading_which_pc <= {reading_which_pc[ETH_PC-2:0], rreq_ready};
      end
    end
  end

  // Fifo Ciphertext Emission ---------------------------------------------------------------------
  logic [ $clog2(CE_DATA_COUNT_W)+1:0] fifo_ce_cnt;
  logic [            MRMAC_AXIS_W-1:0] fifo_ce_out_data;
  logic                                fifo_ce_out_vld;
  logic                                fifo_ce_out_rdy;

  // data in input are already in the correct form for sending directly to the lane
  assign  fifo_ce_in_data = (reading_which_pc[0] == 1) ? fifo_ce_pc_in_data[0] : fifo_ce_pc_in_data[1];
  assign  fifo_ce_in_vld  = (reading_which_pc[0] == 1) ? fifo_ce_pc_in_vld[0] : fifo_ce_pc_in_vld[1];

  // TODO: do something clearer/simpler
  always_comb begin
    if(reading_which_pc == 1) begin
      fifo_ce_pc_in_rdy[0] = fifo_ce_in_rdy;
      fifo_ce_pc_in_rdy[1] = 1'b0;
    end else if (reading_which_pc == 2) begin
      fifo_ce_pc_in_rdy[0] = 1'b0;
      fifo_ce_pc_in_rdy[1] = fifo_ce_in_rdy;
    end else begin
      fifo_ce_pc_in_rdy[0] =  1'b0;
      fifo_ce_pc_in_rdy[1] = 1'b0;
    end
  end

  always_ff @(posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      fifo_ce_cnt <= 'h0;
    end else begin
      if (fifo_ce_in_vld) begin
        fifo_ce_cnt <= fifo_ce_cnt + 1;
      end else if (fifo_ce_out_vld) begin
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
    .out_rdy (1'b0)
  );

  // counter of output words and control for starting header & payload emission
  logic [$clog2(NB_WORDS_PAYLOAD)+1:0] ce_nb_words_cnt;
  logic                                ce_payload_start;
  logic                                ce_header_start;

  always_ff @ (posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      ce_payload_start <= 1'b0;
    end else begin
      if (fifo_ce_cnt == NB_WORDS_PAYLOAD) begin
        ce_payload_start <= 1'b1;
      end else if (ce_nb_words_cnt  == NB_WORDS_PAYLOAD) begin
        ce_payload_start <= 1'b0;
      end
    end
  end

  always_ff @ (posedge clk_mrmac) begin
    if (~resetn_mrmac) begin
      ce_header_start <= 1'b0;
    end else begin
      if (fifo_ce_cnt == (NB_WORDS_PAYLOAD-ETH_HEADER_SIZE)) begin
        ce_header_start <= 1'b1;
      end else if (fifo_ce_cnt == NB_WORDS_PAYLOAD) begin
        ce_header_start <= 1'b0;
      end
    end
  end

  always_ff @(posedge clk_mrmac) begin
    if(~resetn_mrmac) begin
      ce_nb_words_cnt <= 'h0;
    end else begin
      if (ce_payload_start) begin
        ce_nb_words_cnt <= ce_nb_words_cnt +1;
      end else begin
        ce_nb_words_cnt <= 'h0;
      end
    end
  end
endmodule
