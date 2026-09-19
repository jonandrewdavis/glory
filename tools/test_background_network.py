#!/usr/bin/env python3
"""Run the real WebSocket suspend/resume probe; no external services required."""
import os
import queue
import subprocess
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GODOT = os.environ.get("GODOT", "godot")
SCENE = "tools/check_background_network.tscn"


def launch(*args, experiment=True):
    args = list(args)
    if "--" not in args:
        args.append("--")
    if experiment:
        args.append("--background-networking")
    process = subprocess.Popen(
        [GODOT, "--headless", "--path", str(ROOT), SCENE, *args],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
    )
    lines = []
    events = queue.Queue()

    def read():
        for line in process.stdout:
            lines.append(line.rstrip())
            events.put(line.rstrip())
            if line.startswith("PASS:") or "SCRIPT ERROR:" in line:
                print(line.rstrip(), flush=True)

    threading.Thread(target=read, daemon=True).start()
    return process, lines, events


def wait_marker(probe, marker, seconds):
    process, lines, events = probe
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        try:
            if marker in events.get(timeout=0.2):
                return
        except queue.Empty:
            if process.poll() is not None:
                break
    raise AssertionError(f"Missing {marker}:\n" + "\n".join(lines[-70:]))


probes = []
try:
    server = launch("--", "--playflow-server")
    probes.append(server)
    wait_marker(server, "PlayFlow ready:", 15)
    default_client = launch("--", "--default-probe", experiment=False)
    probes.append(default_client)
    wait_marker(default_client, "BACKGROUND_DEFAULT_PASSED", 15)
    assert default_client[0].wait(timeout=5) == 0
    observer = launch("--", "--observer")
    probes.append(observer)
    wait_marker(observer, "BACKGROUND_OBSERVER_READY", 15)
    client = launch()
    probes.append(client)
    wait_marker(client, "BACKGROUND_NETWORK_PASSED", 65)
    assert client[0].wait(timeout=5) == 0
    wait_marker(server, "BACKGROUND_SERVER_PASSED", 5)
    wait_marker(observer, "BACKGROUND_AUDIT_PASSED", 5)
    assert any("application stalled; reserved player" in line for line in server[1])
    for _, lines, _ in probes:
        errors = [line for line in lines if "SCRIPT ERROR:" in line or (
            line.startswith("ERROR:") and "resources still in use at exit" not in line)]
        context = []
        for index, line in enumerate(lines):
            if line in errors:
                context.extend(lines[max(0, index - 2):index + 12])
        assert not errors, "\n".join(context)
    print("PASS: WebSocket background/resume integration")
finally:
    for process, lines, _ in probes:
        if process.poll() is None:
            process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
