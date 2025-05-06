// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  : Instruction decoding logic
// ----------------------------------------------------------------------------------------------
//
// Extract registers information from instruction code.
//
// ==============================================================================================

module isc_parser
  import instruction_scheduler_pkg::*;
  import hpu_common_instruction_pkg::*;
  import regf_common_param_pkg::*;
(
    input  logic [PE_INST_W-1: 0]   insn,
    output insn_kind_e              kind,
    output dstn_id_t                dst_id,
    output insn_id_t                srcA_id,
    output insn_id_t                srcB_id,
    output logic                    flush
);


// ============================================================================================== //
// localparam
// ============================================================================================== //
localparam int KIND_W = 2;

// ============================================================================================== //
// Signals
// ============================================================================================== //
logic [KIND_W-1:0] kind_id;
insn_kind_e kind_e;

pea_mac_inst_t insn_as_pea_mac;
pem_inst_t     insn_as_pem;
pep_inst_t     insn_as_pep;

// ============================================================================================== //
// Parsing logic
// ============================================================================================== //
// Use 2 insn formats to have all available fields. Then based on opcode, select the correct one.
assign insn_as_pea_mac = insn;
assign insn_as_pem = insn;
assign insn_as_pep = insn;

// ============================================================================================== //
// Kind field
// ============================================================================================== //
assign kind_id = insn[PE_INST_W-1: PE_INST_W-KIND_W];
always_comb begin
  case (kind_id)
     2'b00:  kind_e = ARITH;
     2'b01:  kind_e = SYNC;
     2'b10:  kind_e = insn_as_pea_mac.dop[0]? MEM_ST: MEM_LD;
     2'b11:  kind_e = PBS;
  endcase
end
assign kind = kind_e;

// ============================================================================================== //
// Destination ID
// ============================================================================================== //
// Extract Destination RID of MID based on kind
always_comb begin 
  case (kind_e)
     SYNC   : dst_id = '{isc: '{mode: UNUSED, id: '0}, mask: {MAX_RID_MID{1'b1}}};
     MEM_ST : dst_id = '{isc: '{mode: MEMORY, id: insn_as_pem.cid}, mask: {MAX_RID_MID{1'b1}}};
     MEM_LD : dst_id = '{isc: '{mode: REGISTER, id: insn_as_pem.rid}, mask: {MAX_RID_MID{1'b1}}};
     PBS    : dst_id = '{isc: '{mode: REGISTER, id: insn_as_pep.dst_rid},
                         mask: {MAX_RID_MID{1'b1}} << insn_as_pep.dop.log_lut_nb};
     default: dst_id ='{isc: '{mode: REGISTER, id: insn_as_pea_mac.dst_rid}, mask: {MAX_RID_MID{1'b1}}};
  endcase
end

// ============================================================================================== //
// Source RID
// ============================================================================================== //
// Extract Destination RID of MID based on kind
always_comb begin 
  case (kind_e)
     SYNC   : srcA_id = '{mode: UNUSED, id: '0};
     MEM_ST : srcA_id = '{mode: REGISTER, id: insn_as_pem.rid};
     MEM_LD : srcA_id = '{mode: MEMORY, id: insn_as_pem.cid};
     default: srcA_id = '{mode: REGISTER, id: insn_as_pea_mac.src0_rid};
  endcase
end

always_comb begin 
  if ((insn_as_pea_mac.dop == DOP_ADD)
   || (insn_as_pea_mac.dop == DOP_SUB)
   || (insn_as_pea_mac.dop == DOP_MAC)) begin
      srcB_id = '{mode: REGISTER, id: insn_as_pea_mac.src1_rid};
  end else begin
      srcB_id = '{mode: UNUSED, id: '0};
  end
end

// ============================================================================================== //
// Extract Flush
// ============================================================================================== //
// Extract Destination RID of MID based on kind
always_comb begin 
  case (kind_e)
     PBS    : flush = insn_as_pep.dop.flush_pbs;
     default: flush = 1'b0;
  endcase
end

endmodule
