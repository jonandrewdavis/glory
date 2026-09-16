#!/usr/bin/env bash
set -euo pipefail

# Usage: GODOT=/path/to/godot bash tools/prepare_playflow.sh
cd "$(dirname "$0")/.."
godot_bin="${GODOT:-godot}"
if ! command -v "$godot_bin" >/dev/null 2>&1; then
  echo 'Set GODOT to the Godot 4.7 executable.' >&2
  exit 1
fi
command -v zip >/dev/null
mkdir -p builds
# A fresh staging directory keeps old exports out of the archive.
stage_dir="$(mktemp -d "$PWD/builds/playflow-stage.XXXXXX")"
"$godot_bin" --headless --path "$PWD" --editor --import
"$godot_bin" --headless --path "$PWD" --export-release 'PlayFlow Server' "$stage_dir/Server.x86_64"
chmod +x "$stage_dir/Server.x86_64"
archive="$stage_dir/playflow-server.zip"
(cd "$stage_dir" && zip -qr "$archive" .)
mv "$archive" builds/playflow-server.zip
echo 'Ready: builds/playflow-server.zip'
echo 'PlayFlow executable: Server.x86_64'
echo 'Configure port godot_websocket: TCP 8080, TLS enabled.'
echo "Export staging files retained at: $stage_dir"
