-- =================================================================================================
-- MHDMA Wireshark Lua Dissector
-- Multi-HPU DMA custom Ethernet protocol dissector
--
-- Installation:
--   Option 1: Copy to ~/.local/lib/wireshark/plugins/ (Linux)
--   Option 2: wireshark -X lua_script:/path/to/mhdma.lua -r capture.pcap
--   Option 3: tshark  -X lua_script:/path/to/mhdma.lua -r capture.pcap
--
-- The protocol uses IEEE 802.3 + LLC with DSAP/SSAP = 0xF8.
-- This dissector overrides the built-in hpext dissector for DSAP 0xF8.
--
-- Filterable fields:
--   mhdma.req_id, mhdma.hpu_id, mhdma.seq_num, mhdma.src_addr,
--   mhdma.dst_addr, mhdma.iop_id, mhdma.rsvd, mhdma.flag, mhdma.mode,
--   mhdma.ce_delta, mhdma.payload
--
-- Example filters:
--   mhdma                        -- all MHDMA packets
--   mhdma.req_id == 7            -- EMISSION only
--   mhdma.req_id == 2            -- NOTIFY only
--   mhdma.hpu_id == 6            -- specific HPU
--   mhdma.ce_delta > 0.001       -- emission gaps > 1ms
--
-- Example tshark CSV export:
--   tshark -X lua_script:mhdma.lua -r capture.pcap -T fields \
--     -e frame.time_relative -e mhdma.req_id -e mhdma.hpu_id \
--     -e mhdma.seq_num -e mhdma.src_addr -e mhdma.dst_addr \
--     -e mhdma.ce_delta -e frame.len -E separator=,
-- =================================================================================================

-- Protocol declaration
local mhdma = Proto("mhdma", "Multi-HPU DMA Protocol")

-- req_id value strings
local req_id_names = {
    [0x2] = "NOTIFY",
    [0x3] = "NOTIFY_ACK",
    [0x6] = "READ_REQ",
    [0x7] = "EMISSION",
}

-- Protocol fields
-- The buffer passed to us starts after LLC header (DSAP+SSAP+Control),
-- so offset 0 = frame byte 17 = req_id[7:4] | hpu_id[3:0]
-- req_id and hpu_id are manually extracted (no bitmask) so filters use intuitive values:
--   mhdma.req_id == 7  (not 0x70)
--   mhdma.hpu_id == 6  (not 0x06 masked)
local f_req_id   = ProtoField.uint8 ("mhdma.req_id",   "Request ID",    base.DEC, req_id_names)
local f_hpu_id   = ProtoField.uint8 ("mhdma.hpu_id",   "HPU ID",        base.DEC)
local f_seq_num  = ProtoField.uint8 ("mhdma.seq_num",  "Sequence Number", base.DEC)
local f_src_addr = ProtoField.uint16("mhdma.src_addr", "Source Address", base.HEX)
local f_dst_addr = ProtoField.uint16("mhdma.dst_addr", "Destination Address", base.HEX)
local f_iop_id   = ProtoField.uint8 ("mhdma.iop_id",   "IOP ID",        base.DEC)
local f_rsvd     = ProtoField.uint8 ("mhdma.rsvd",     "Reserved",      base.HEX)
local f_flag     = ProtoField.uint8 ("mhdma.flag",     "Flag",          base.HEX)
local f_mode     = ProtoField.uint8 ("mhdma.mode",     "Mode",          base.DEC)
local f_ce_delta = ProtoField.float ("mhdma.ce_delta", "CE Inter-packet Delta (s)")
local f_payload  = ProtoField.bytes ("mhdma.payload",  "Payload")

mhdma.fields = {
    f_req_id, f_hpu_id, f_seq_num, f_src_addr, f_dst_addr,
    f_iop_id, f_rsvd, f_flag, f_mode, f_ce_delta, f_payload
}

-- State for CE inter-packet timing
local prev_emission_time = nil

-- Called when Wireshark reloads/opens a new file
function mhdma.init()
    prev_emission_time = nil
end

-- Dissector function
-- tvb starts after LLC header: offset 0 = req_id|hpu_id byte
function mhdma.dissector(tvb, pinfo, tree)
    local buf_len = tvb:len()
    if buf_len < 9 then return end  -- minimum: 2 header words (16 bytes) after LLC

    pinfo.cols.protocol = "MHDMA"

    local subtree = tree:add(mhdma, tvb(), "MHDMA Protocol")

    -- Word 3 fields (header byte 0-6, i.e. tvb offset 0-6)
    local raw_byte0 = tvb(0, 1):uint()
    local req_id_val = bit.rshift(bit.band(raw_byte0, 0xF0), 4)
    local hpu_id_val = bit.band(raw_byte0, 0x0F)
    local seq_num_val = tvb(1, 1):uint()

    subtree:add(f_req_id,   tvb(0, 1), req_id_val)
    subtree:add(f_hpu_id,   tvb(0, 1), hpu_id_val)
    subtree:add(f_seq_num,  tvb(1, 1))
    subtree:add(f_src_addr, tvb(2, 2))
    subtree:add(f_dst_addr, tvb(4, 2))
    subtree:add(f_iop_id,   tvb(6, 1))

    local src_addr_val = tvb(2, 2):uint()
    local dst_addr_val = tvb(4, 2):uint()

    -- Word 4 fields (tvb offset 7-14)
    if buf_len >= 15 then
        local raw_byte8 = tvb(8, 1):uint()
        local flag_val = bit.rshift(bit.band(raw_byte8, 0xFC), 2)
        local mode_val = bit.band(raw_byte8, 0x03)
        subtree:add(f_rsvd, tvb(7, 1))
        subtree:add(f_flag, tvb(8, 1), flag_val)
        subtree:add(f_mode, tvb(8, 1), mode_val)
    end

    -- CE inter-packet timing for EMISSION packets
    local req_name = req_id_names[req_id_val] or string.format("UNKNOWN(0x%X)", req_id_val)
    if req_id_val == 0x7 then  -- EMISSION
        local cur_time = pinfo.abs_ts
        if prev_emission_time ~= nil and seq_num_val ~= 0 then
            local delta = cur_time - prev_emission_time
            subtree:add(f_ce_delta, delta):set_generated()
        end
        prev_emission_time = cur_time
    end

    -- Payload (after 15 bytes of custom header = 2 x 64-bit words minus LLC ctrl which is already consumed)
    local payload_offset = 15  -- 7 bytes (word3 after LLC ctrl) + 8 bytes (word4)
    if buf_len > payload_offset then
        subtree:add(f_payload, tvb(payload_offset))
    end

    -- Info column
    local info = string.format("%s hpu=%d seq=%d src=0x%04X dst=0x%04X",
        req_name, hpu_id_val, seq_num_val, src_addr_val, dst_addr_val)
    pinfo.cols.info = info
end

-- Register in the LLC DSAP dissector table
-- DSAP 0xF8 = 248 decimal; LLC uses the SAP value without the IG bit = 0xF8 >> 1 = 124
-- Wireshark's LLC dissector table "llc.dsap" uses the full byte value
local llc_dsap_table = DissectorTable.get("llc.dsap")
llc_dsap_table:add(0xF8, mhdma)
