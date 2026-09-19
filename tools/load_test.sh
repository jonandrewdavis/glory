#!/bin/bash
# Usage: tools/load_test.sh [bots=10] [seconds=60]
# Each process uses in-memory test settings; the user's configuration is untouched.
set -euo pipefail
export GODOT="${GODOT_BIN:-/Applications/Godot_v4.7.app/Contents/MacOS/Godot}"
exec python3 tools/profile_multiplayer.py --clients "${1:-10}" --seconds "${2:-60}"
