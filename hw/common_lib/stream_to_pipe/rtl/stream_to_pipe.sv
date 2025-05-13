// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module deals with the conversion of a stream rdy/vld type bus into a pipe type bus.
// It is also able to synchronize the input paths. To do that, it needs a small buffer.
// An error is triggered if the buffer is full.
// In this latter case data are lost, and the inputs are desynchronized.
//
// This module can be used for example after a CDC.
// ==============================================================================================

module stream_to_pipe #(
  parameter int WIDTH    = 1,
  parameter int DEPTH    = 2, // set to the max desynchronization between the paths.
  parameter int IN_NB    = 2  // > 1
)
(
  input  logic                        clk,        // clock
  input  logic                        s_rst_n,    // synchronous reset

  input  logic [IN_NB-1:0][WIDTH-1:0] in_data,
  input  logic [IN_NB-1:0]            in_vld,
  output logic [IN_NB-1:0]            in_rdy,

  output logic [IN_NB*WIDTH-1:0]      out_data,
  output logic                        out_avail,

  output logic                        error_full
);


// ============================================================================================== --
// Buffers
// ============================================================================================== --
  logic [IN_NB-1:0]            buf_out_vld;
  logic [IN_NB-1:0]            buf_out_rdy;
  logic [IN_NB-1:0]            buf_overflow;
  logic [IN_NB-1:0][WIDTH-1:0] out_d_data;
  logic                        out_d_avail;

  assign in_rdy = '1;

  generate
    for (genvar gen_i=0; gen_i<IN_NB; gen_i=gen_i+1) begin : gen_loop
      logic [DEPTH-1:0][WIDTH-1:0] buf_data;
      logic [DEPTH:0]  [WIDTH-1:0] buf_data_ext;
      logic [DEPTH-1:0][WIDTH-1:0] buf_dataD;
      logic [DEPTH-1:0]            buf_en;
      logic [DEPTH-1:0]            buf_enD;
      logic [DEPTH:0]              buf_en_ext;
      logic                        buf_in_avail;
      logic [WIDTH-1:0]            buf_in_data;
      logic [DEPTH-1:0]            buf_in_wren_1h;
      logic [DEPTH-1:0]            buf_in_wren_1h_tmp;
      logic [DEPTH-1:0]            buf_in_wren_1h_tmp2;
      logic                        buf_shift;

      assign buf_shift          = buf_out_vld[gen_i] & buf_out_rdy[gen_i];
      assign buf_out_vld[gen_i] = buf_en[0];
      assign out_d_data[gen_i]  = buf_data[0];
      assign buf_in_avail       = in_vld[gen_i];
      assign buf_in_data        = in_data[gen_i];
      assign buf_overflow[gen_i]= buf_in_avail & (buf_in_wren_1h == 0);

      // Add 1 element to avoid warning, while selecting out of range.
      assign buf_data_ext        = {{WIDTH{1'bx}}, buf_data};
      assign buf_en_ext          = {1'b0, buf_en};
      assign buf_in_wren_1h_tmp  = buf_shift ? {1'b0, buf_en[DEPTH-1:1]} : buf_en;
      // Find first bit = 0
      assign buf_in_wren_1h_tmp2 = buf_in_wren_1h_tmp ^ {buf_in_wren_1h_tmp[DEPTH-2:0], 1'b1};
      assign buf_in_wren_1h      = buf_in_wren_1h_tmp2 & {DEPTH{buf_in_avail}};

      always_comb begin
        for (int i = 0; i<DEPTH; i=i+1) begin
          buf_dataD[i] = buf_in_wren_1h[i] ? buf_in_data :
                         buf_shift         ? buf_data_ext[i+1] : buf_data[i];
          buf_enD[i] = buf_in_wren_1h[i] | (buf_shift ? buf_en_ext[i+1] : buf_en[i]);
        end
      end

      always_ff @(posedge clk) begin
        buf_data <= buf_dataD;
      end

      always_ff @(posedge clk)
        if (!s_rst_n) buf_en <= '0;
        else          buf_en <= buf_enD;

// pragma translate_off
      always_ff @(posedge clk)
        if (!s_rst_n) begin
          // do nothing
        end
        else begin
          if (buf_in_avail) begin
            assert(buf_in_wren_1h != 0)
            else $fatal(1, "%t > ERROR: Buffer overflow!", $time);
          end
        end
// pragma translate_on
    end
  endgenerate

// ============================================================================================== --
// Synchronization
// ============================================================================================== --
  assign out_d_avail = &buf_out_vld;

  always_comb begin
    var [IN_NB-1:0] mask;
    for (int i=0; i<IN_NB; i=i+1) begin
      mask = 1 << i;
      buf_out_rdy[i] = &(buf_out_vld | mask); // for a given i, the mask avoids the dependence with the corresponding vld
    end
  end

// ============================================================================================== --
// Output
// ============================================================================================== --
  always_ff @(posedge clk)
    if (!s_rst_n) out_avail <= 1'b0;
    else          out_avail <= out_d_avail;

  always_ff @(posedge clk)
    out_data <= out_d_data;

// ============================================================================================== --
// Error
// ============================================================================================== --
  always_ff @(posedge clk)
    if (!s_rst_n) error_full <= 1'b0;
    else          error_full <= |buf_overflow;

endmodule
