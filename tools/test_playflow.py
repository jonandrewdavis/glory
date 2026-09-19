#!/usr/bin/env python3
"""Real Godot process integration: 30 admitted clients, full rejection, slot reuse."""
import os
import queue
import subprocess
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GODOT = os.environ.get("GODOT", "godot")
processes = []
errors = []
diagnostics = []
disconnect_test = False


def launch(args):
    args = list(args)
    if "--" not in args:
        args.append("--")
    args.append("--isolated-settings")
    process = subprocess.Popen(
        [GODOT, "--headless", "--path", str(ROOT), *args],
        cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
    )
    processes.append(process)
    lines = queue.Queue()

    def read():
        for line in process.stdout:
            lines.put(line.rstrip())
            if "SCRIPT ERROR:" in line or line.startswith("ERROR:"):
                # Existing native addon reports resources at process exit. Godot's
                # WebSocket transport may report sends racing an abrupt disconnect.
                if "resources still in use at exit" in line or (
                    disconnect_test and 'ready_state != STATE_OPEN' in line
                ):
                    diagnostics.append(line.rstrip())
                else:
                    errors.append(line.rstrip())

    threading.Thread(target=read, daemon=True).start()
    return process, lines


def wait_for(probe, marker, timeout=25):
    process, lines = probe
    deadline = time.monotonic() + timeout
    seen = []
    while time.monotonic() < deadline:
        try:
            line = lines.get(timeout=0.2)
        except queue.Empty:
            if process.poll() is not None:
                break
            continue
        seen.append(line)
        if marker in line:
            return
    raise RuntimeError(f"Missing {marker}: " + "\n".join(seen[-20:]))


try:
    server = launch(["--", "--playflow-server"])
    wait_for(server, "PlayFlow ready:")
    clients = []
    for number in range(30):
        probe = launch(["tools/test_playflow_client.tscn"])
        wait_for(probe, "PROBE_READY:")
        clients.append(probe)
        print(f"Admitted {number + 1}/30", flush=True)
    wait_for(clients[-1], "PROBE_BALANCED: 15 vs 15")
    rejected = launch(["tools/test_playflow_client.tscn", "--", "--expect-full"])
    wait_for(rejected, "PROBE_REJECTED: Server is full (30/30 players).")
    assert rejected[0].wait(timeout=10) == 0
    disconnect_test = True
    clients[0][0].terminate()
    clients[0][0].wait(timeout=10)
    time.sleep(1)
    replacement = launch(["tools/test_playflow_client.tscn"])
    wait_for(replacement, "PROBE_READY:")
    wait_for(replacement, "PROBE_BALANCED: 15 vs 15")
    assert server[0].poll() is None
    assert all(probe[0].poll() is None for probe in clients[1:])
    if errors:
        raise RuntimeError("Godot errors: " + "\n".join(errors[:20]))
    print("PASS: 30 real clients, 31st rejected before spawn, disconnected slot reused.")
    if diagnostics:
        print(f"Diagnostics: {len(diagnostics)} addon-exit / forced-disconnect messages (see docs).")
finally:
    for process in processes:
        if process.poll() is None:
            process.terminate()
    for process in processes:
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
