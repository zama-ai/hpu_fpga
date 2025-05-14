// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the request / acknowledge signals, that are exposed on the register
// interface.
// ==============================================================================================

module hpu_regif_req_ack
#(
  parameter int IN_NB      = 2,
  parameter int REG_DATA_W = 32
) (
  input  logic                             clk,
  input  logic                             s_rst_n,

  // reg_if
  output logic [IN_NB-1:0][REG_DATA_W-1:0] r_req_ack_upd,
  input  logic [IN_NB-1:0]                 r_req_ack_wr_en,
  input  logic [REG_DATA_W-1:0]            r_wr_data,

  // from module
  output logic [IN_NB-1:0]                 req_cmd,
  input  logic [IN_NB-1:0]                 ack_rsp // pulse
);

// ============================================================================================== //
// localparam
// ============================================================================================== //
  localparam int REQ_OFS = 0;
  localparam int ACK_OFS = REG_DATA_W-1;

// ============================================================================================== //
// Register
// ============================================================================================== //
  generate
    for (genvar gen_i=0; gen_i<IN_NB; gen_i=gen_i+1) begin : gen_loop
      logic req;
      logic reqD;
      logic ack;
      logic ackD;
      logic [REG_DATA_W-1:0] r_req_ack_l;

      assign reqD = r_req_ack_wr_en[gen_i] ? r_wr_data[REQ_OFS] : req;
      assign ackD = r_req_ack_wr_en[gen_i] ? r_wr_data[ACK_OFS] : ack_rsp[gen_i] | ack;

      always_ff @(posedge clk)
        if (!s_rst_n) begin
          req <= 1'b0;
          ack <= 1'b0;
        end
        else begin
          req <= reqD;
          ack <= ackD;
        end

      assign req_cmd[gen_i] = req;

      always_comb begin
        r_req_ack_l = '0;
        r_req_ack_l[REQ_OFS] = req;
        r_req_ack_l[ACK_OFS] = ack;
      end

      assign r_req_ack_upd[gen_i] = r_req_ack_l;
    end
  endgenerate
endmodule
