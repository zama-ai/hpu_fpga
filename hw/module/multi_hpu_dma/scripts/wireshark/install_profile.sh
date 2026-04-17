#!/bin/bash
# Install MHDMA Wireshark profile and Lua dissector
#
# Usage: ./install_profile.sh
#
# This script:
#   1. Copies the MHDMA profile to ~/.config/wireshark/profiles/MHDMA/
#   2. Installs the Lua dissector to ~/.local/lib/wireshark/plugins/
#
# After installation:
#   - Open Wireshark
#   - Select profile: Edit > Configuration Profiles > MHDMA
#   - Open your pcap file
#   - All columns, colors, filters, and I/O graph presets are ready

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE_SRC="${SCRIPT_DIR}/profiles/MHDMA"
LUA_SRC="${SCRIPT_DIR}/mhdma.lua"

# Wireshark config directories
WS_CONFIG="${HOME}/.config/wireshark"
WS_PROFILE_DST="${WS_CONFIG}/profiles/MHDMA"
WS_PLUGIN_DIR="${HOME}/.local/lib/wireshark/plugins"

echo "=== MHDMA Wireshark Profile Installer ==="
echo ""

# Install profile
echo "[1/2] Installing MHDMA profile to ${WS_PROFILE_DST}"
mkdir -p "${WS_PROFILE_DST}"
cp -v "${PROFILE_SRC}/colorfilters"    "${WS_PROFILE_DST}/"
cp -v "${PROFILE_SRC}/dfilter_buttons" "${WS_PROFILE_DST}/"
cp -v "${PROFILE_SRC}/preferences"     "${WS_PROFILE_DST}/"
cp -v "${PROFILE_SRC}/recent"          "${WS_PROFILE_DST}/"
cp -v "${PROFILE_SRC}/io_graphs"       "${WS_PROFILE_DST}/"
echo ""

# Install Lua dissector
echo "[2/2] Installing Lua dissector to ${WS_PLUGIN_DIR}"
mkdir -p "${WS_PLUGIN_DIR}"
cp -v "${LUA_SRC}" "${WS_PLUGIN_DIR}/"
echo ""

echo "=== Done ==="
echo ""
echo "To use:"
echo "  1. Open Wireshark"
echo "  2. Select profile: Edit > Configuration Profiles > MHDMA"
echo "     (or bottom-right status bar > right-click > MHDMA)"
echo "  3. Open your pcap file"
echo ""
echo "Or from command line:"
echo "  wireshark -C MHDMA -r your_capture.pcap"
echo ""
echo "Pre-configured features:"
echo "  - Custom columns: Req ID, HPU, Seq, Src/Dst Addr, CE Delta"
echo "  - Color rules: green=EMISSION, blue=READ_REQ, yellow=NOTIFY, red=CE gaps"
echo "  - Filter buttons: quick filter by packet type"
echo "  - I/O Graphs: Statistics > I/O Graphs (presets loaded)"
