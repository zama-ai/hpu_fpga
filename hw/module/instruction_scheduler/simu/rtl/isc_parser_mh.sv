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

module isc_parser_mh
  import instruction_scheduler_pkg::*;
  import hpu_common_instruction_pkg::*;
  import regf_common_param_pkg::*;
(
    input  logic [PE_INST_W-1: 0]   insn,
    output insn_kind_e              kind_1h,
    output logic [REGF_REG_NB-1: 0] wr_reg_mh,
    output logic [REGF_REG_NB-1: 0] rd_reg_mh,
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

logic [REGF_REGID_W-1: 0] srca_rid, srcb_rid, dst_range;
logic [REGF_REG_NB-1: 0] dst_rid_mh, srca_rid_1h, srcb_rid_1h;

pea_mac_inst_t insn_as_pea_mac;
pep_inst_t     insn_as_pep;

logic is_st_insn, is_sync_insn;
logic has_srca_field, has_srcb_field;

// ============================================================================================== //
// Parsing logic
// ============================================================================================== //
//NB: here to easily extract insn fields. Use the format that define all rid
//   Should rely on opcode field to discard some fields
assign insn_as_pea_mac = insn;
assign insn_as_pep     = insn;
assign is_st_insn = (insn_as_pea_mac.dop == DOP_ST);
assign is_sync_insn = insn_as_pea_mac.dop == DOP_SYNC;

// ============================================================================================== //
// Destination RID
// ============================================================================================== //
// Extract Destination RID and convert it in 1h
// NB: dst_rid is a field shared by all instructions format and its always at the same position
// -> Don't care of the current opcode
assign dst_range = (insn_as_pep.dop.kind == DOPT_PBS) ?
                      REGF_REGID_W'(1) << insn_as_pep.dop.log_lut_nb :
                      REGF_REGID_W'(1);
assign dst_rid_mh = (~({REGF_REG_NB{1'b1}} << dst_range)) << insn_as_pep.dst_rid;

//NB: dst_rid is always a wr_reg except with Store in which case its a read_reg
// -> filter out wr_reg with ST insn
assign wr_reg_mh = {REGF_REG_NB{!is_st_insn & !is_sync_insn}} & dst_rid_mh;

// ============================================================================================== //
// Source RID
// ============================================================================================== //
// Extract Source RID and convert it in 1h if any
// NB: src_rid are field that aren't present in all insn format. However, when present, they always
//   have same position.
// -> Use opcode to filtered out unused field

assign srca_rid = REGF_REGID_W'(insn_as_pea_mac.src0_rid); // is truncated to the correct size
common_lib_bin_to_one_hot #(
  .ONE_HOT_W(REGF_REG_NB)
) srca_to_1h
(
  .in_value(srca_rid),
  .out_1h(srca_rid_1h)
);

assign has_srca_field = (insn_as_pea_mac.dop != DOP_LD)
                      & (insn_as_pea_mac.dop != DOP_ST);

assign srcb_rid = REGF_REGID_W'(insn_as_pea_mac.src1_rid); // is truncated to the correct size
common_lib_bin_to_one_hot #(
  .ONE_HOT_W(REGF_REG_NB)
) srcb_to_1h
(
  .in_value(srcb_rid),
  .out_1h(srcb_rid_1h)
);
assign has_srcb_field = (insn_as_pea_mac.dop == DOP_ADD)
                     || (insn_as_pea_mac.dop == DOP_SUB)
                     || (insn_as_pea_mac.dop == DOP_MAC);

assign rd_reg_mh =  {REGF_REG_NB{!is_sync_insn}}
                & ( {REGF_REG_NB{has_srca_field}} & srca_rid_1h
                   |{REGF_REG_NB{has_srcb_field}} & srcb_rid_1h
                   |{REGF_REG_NB{is_st_insn}} & dst_rid_mh
                  );

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

assign kind_1h = kind_e;

endmodule
