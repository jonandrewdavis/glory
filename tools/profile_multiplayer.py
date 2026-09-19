#!/usr/bin/env python3
"""Local WebSocket capacity probe. CPU is one-core percent, not PlayFlow quota percent.

Example: python3 tools/profile_multiplayer.py --clients 30 --seconds 60
Use --seconds 1800 for a full soak. Load clients share this machine: this is not
a substitute for a separate-generator PlayFlow/browser capacity measurement.
"""
import argparse
from collections import deque
import json
import os
from pathlib import Path
import queue
import subprocess
import threading
import time

ROOT = Path(__file__).resolve().parent.parent
GODOT = os.environ.get("GODOT", "/Applications/Godot_v4.7.app/Contents/MacOS/Godot")


def cpu_seconds(pid):
    value = subprocess.check_output(["ps", "-o", "time=", "-p", str(pid)], text=True).strip()
    result = 0.0
    for part in value.split(":"):
        result = result * 60 + float(part)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--clients", type=int, default=10, choices=range(31))
    parser.add_argument("--seconds", type=int, default=60)
    parser.add_argument("--workload", choices=["idle", "move", "combat"], default="combat")
    parser.add_argument("--server-arg", action="append", default=[])
    args = parser.parse_args()
    processes = []
    errors = deque(maxlen=30)
    metrics = deque(maxlen=5)

    def launch(scene, extra):
        process = subprocess.Popen([GODOT, "--headless", "--path", str(ROOT), *scene, "--", "--isolated-settings", *extra], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        processes.append(process)
        events = queue.Queue()

        def read():
            for line in process.stdout:
                line = line.rstrip()
                if "READY" in line or "PlayFlow ready:" in line:
                    events.put(line)
                if line.startswith("NETWORK_METRICS "):
                    metrics.append(json.loads(line.removeprefix("NETWORK_METRICS ")))
                if line.startswith("ERROR:") or "SCRIPT ERROR:" in line:
                    errors.append(line)
        threading.Thread(target=read, daemon=True).start()
        return process, events

    def ready(probe, marker):
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            try:
                if marker in probe[1].get(timeout=0.2):
                    return
            except queue.Empty:
                if probe[0].poll() is not None:
                    break
        raise RuntimeError(f"Missing {marker}: {list(errors)}")

    try:
        server = launch([], ["--playflow-server", "--network-metrics", *args.server_arg])
        ready(server, "PlayFlow ready:")
        for _ in range(args.clients):
            ready(launch(["tools/load_bot.tscn"], [f"--workload={args.workload}"]), "LOAD_BOT_READY")
        print(f"Ready: {args.clients} clients; warming up for 5 seconds", flush=True)
        time.sleep(5)
        begin = time.monotonic()
        cpu_begin = cpu_seconds(server[0].pid)
        metric_begin = dict(metrics[-1]) if metrics else {}
        rss = []
        while time.monotonic() - begin < args.seconds:
            time.sleep(1)
            if any(p.poll() is not None for p in processes):
                raise RuntimeError("A workload process exited")
            rss.append(int(subprocess.check_output(["ps", "-o", "rss=", "-p", str(server[0].pid)], text=True).strip()))
            if errors:
                raise RuntimeError("\n".join(errors))
        elapsed = time.monotonic() - begin
        latest = dict(metrics[-1]) if metrics else {}
        report = {"clients": args.clients, "workload": args.workload, "seconds": round(elapsed, 1),
                  "server_cpu_one_core_percent": round(100 * (cpu_seconds(server[0].pid) - cpu_begin) / elapsed, 2),
                  "rss_start_kib": rss[0], "rss_end_kib": rss[-1], "rss_peak_kib": max(rss),
                  "metrics": latest, "errors": list(errors)}
        for name in ("snapshots", "snapshot_bytes", "owner_samples", "events"):
            report[name + "_per_second"] = round((latest.get(name, 0) - metric_begin.get(name, 0)) / elapsed, 2)
        print(json.dumps(report, indent=2), flush=True)
    finally:
        for process in reversed(processes):
            if process.poll() is None:
                process.terminate()
        for process in processes:
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()


if __name__ == "__main__":
    main()
