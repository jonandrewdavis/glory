#!/bin/bash
# Usage: tools/load_test.sh [bots=10] [seconds=30] [extra server args...]
# Starts a local headless PlayFlow server plus N load bots and prints server CPU%.
GODOT_BIN="${GODOT_BIN:-/Applications/Godot_v4.7.app/Contents/MacOS/Godot}"
BOTS="${1:-10}"; SECS="${2:-30}"; shift 2 2>/dev/null
# Concurrent instances race on user://settings.cfg and can truncate it; keep a copy.
SETTINGS="$HOME/Library/Application Support/Godot/app_userdata/Glory/settings.cfg"
[ -f "$SETTINGS" ] && cp "$SETTINGS" /tmp/glory_settings_backup.cfg
"$GODOT_BIN" --headless --path . "$@" -- --playflow-server > /tmp/glory_load_server.log 2>&1 &
SERVER=$!
PIDS=()
python3 -c "import time; time.sleep(3)"
for i in $(seq 1 "$BOTS"); do
  "$GODOT_BIN" --headless --path . res://tools/load_bot.tscn > "/tmp/glory_load_bot_$i.log" 2>&1 &
  PIDS+=($!)
done
python3 -c "import time; time.sleep(8)"
echo "bots ready: $(grep -l LOAD_BOT_READY /tmp/glory_load_bot_*.log 2>/dev/null | wc -l | tr -d ' ')/$BOTS"
START=$(ps -o cputime= -p $SERVER)
python3 -c "import time; time.sleep($SECS)"
END=$(ps -o cputime= -p $SERVER)
python3 - "$START" "$END" "$SECS" <<'PY'
import sys
def secs(t):
    parts = t.strip().split(':'); v = 0.0
    for p in parts: v = v * 60 + float(p)
    return v
print("server CPU: %.1f%% of one core" % ((secs(sys.argv[2]) - secs(sys.argv[1])) / float(sys.argv[3]) * 100))
PY
kill "${PIDS[@]}" $SERVER 2>/dev/null; wait 2>/dev/null
[ -f /tmp/glory_settings_backup.cfg ] && cp /tmp/glory_settings_backup.cfg "$SETTINGS"
grep -E "SCRIPT ERROR|ERROR" /tmp/glory_load_server.log | sort | uniq -c | head -5
