// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ==============================================================================================
// Description  : Handshake Synchronizer using XPM module
// ----------------------------------------------------------------------------------------------
//
// Wrapper around XPM_CDC_HANDSHAKE for multi-bit bus CDC using a full handshake protocol.
// The source side continuously re-samples and transfers the input bus to the destination
// clock domain. The handshake guarantees data coherency across all bits.
//
// Documentation about XPM module can be found here :
// https://docs.amd.com/r/en-US/ug974-vivado-ultrascale-libraries/XPM_CDC_HANDSHAKE
//
// ==============================================================================================

module xpm_cdc_handshake_wrapper #(
  // Data width ---------------------------------------------------------------------------------
  // Specifies the width of the bus to be transferred.
  // Valid range: 1-1024
  parameter int WIDTH = 1,

  // Synchronization stages ---------------------------------------------------------------------
  // Specifies the number of synchronization stages on the CDC path.
  // Valid range: 2-10
  parameter int CDC_SYNC_STAGES = 4,

  // Behavioral simulation ----------------------------------------------------------------------
  // 0 = disable simulation init values
  // 1 = enable simulation init values
  // Unlike simple synchronizers, the handshake feedback loop requires initialized FFs
  // to avoid X propagation through the request/acknowledge control path in simulation.
  parameter int INIT_SYNC_FF = 1,

  // Simulation asserts flag --------------------------------------------------------------------
  // 0 = disable simulation messages
  // 1 = enable simulation messages
  parameter int SIM_ASSERT_CHK = 0
)(
  // Source clock domain
  input  logic             src_clk,
  input  logic             src_rst_n,
  input  logic [WIDTH-1:0] src_in,

  // Destination clock domain
  input  logic             dest_clk,
  output logic [WIDTH-1:0] dest_out
);

  // ============================================================================================
  // Source-side handshake FSM
  // ============================================================================================
  // Continuously captures src_in and initiates transfers whenever the handshake is idle.
  // Protocol:
  //   1. Capture src_in, assert src_send
  //   2. Wait for src_rcv (destination acknowledged)
  //   3. Deassert src_send, wait for src_rcv to deassert
  //   4. Repeat
  // ============================================================================================
  typedef enum logic [1:0] {
    HSK_XXX          = 'x,
    HSK_CAPTURE      = 2'b00,
    HSK_SENDING      = 2'b01,
    HSK_WAIT_DEASSRT = 2'b10
  } st_hsk;

  st_hsk             hsk_state;
  st_hsk             hsk_next_state;
  logic              src_send;
  logic              src_rcv;
  logic [WIDTH-1:0]  src_in_reg;

  // -- State register --
  always_ff @(posedge src_clk) begin
    if (~src_rst_n) hsk_state <= HSK_CAPTURE;
    else            hsk_state <= hsk_next_state;
  end

  // -- Next state logic --
  always_comb begin
    hsk_next_state = HSK_XXX;
    case (hsk_state)
      HSK_CAPTURE:
        hsk_next_state = HSK_SENDING;
      HSK_SENDING:
        hsk_next_state = src_rcv ? HSK_WAIT_DEASSRT : HSK_SENDING;
      HSK_WAIT_DEASSRT:
        hsk_next_state = ~src_rcv ? HSK_SENDING : HSK_WAIT_DEASSRT;
    endcase
  end

  // source clock logic depending on FSM
  always_ff @(posedge src_clk) begin
    if (~src_rst_n) begin
      src_send <= 1'b0;
    end else begin
      case (hsk_state)
        HSK_CAPTURE: begin
          src_in_reg <= src_in;
          src_send   <= 1'b1;
        end
        HSK_SENDING: begin
          if (src_rcv)
            src_send <= 1'b0;
        end
        HSK_WAIT_DEASSRT: begin
          if (~src_rcv) begin
            src_in_reg <= src_in;
            src_send   <= 1'b1;
          end
        end
        default: begin
          src_send <= 1'b0;
        end
      endcase
    end
  end

  // ============================================================================================
  // XPM CDC Handshake instantiation
  // ============================================================================================
  xpm_cdc_handshake #(
    .DEST_EXT_HSK  (0              ),
    .DEST_SYNC_FF  (CDC_SYNC_STAGES),
    .INIT_SYNC_FF  (INIT_SYNC_FF   ),
    .SIM_ASSERT_CHK(SIM_ASSERT_CHK ),
    .SRC_SYNC_FF   (CDC_SYNC_STAGES),
    .WIDTH         (WIDTH          )
  ) xpm_cdc_handshake_inst (
    .dest_out (dest_out ),
    .dest_req (/* UNUSED */),
    .src_rcv  (src_rcv  ),
    .dest_ack (1'b0     ),
    .dest_clk (dest_clk ),
    .src_clk  (src_clk  ),
    .src_in   (src_in_reg),
    .src_send (src_send )
  );

endmodule
