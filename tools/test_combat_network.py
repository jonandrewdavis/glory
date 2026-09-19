#!/usr/bin/env python3
"""Run isolated Godot checks, including real two-process ENet/WS tests."""
import argparse
import os
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GODOT = os.environ.get("GODOT", "/Applications/Godot_v4.7.app/Contents/MacOS/Godot")


def run(scene, network=False, transport="enet"):
    base = [GODOT, "--headless", "--path", str(ROOT), f"tools/{scene}.tscn", "--", "--isolated-settings"]
    processes = []
    try:
        if network:
            processes.append(subprocess.Popen(base + ["--server", f"--transport={transport}"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True))
            time.sleep(1)
            processes.append(subprocess.Popen(base + ["--client", f"--transport={transport}"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True))
        else:
            processes.append(subprocess.Popen(base, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True))
        passed = True
        for index, process in enumerate(processes):
            try:
                output, _ = process.communicate(timeout=55)
            except subprocess.TimeoutExpired:
                process.kill()
                output, _ = process.communicate()
                output += "\nERROR: test timed out"
            errors = [line for line in output.splitlines() if "SCRIPT ERROR:" in line or line.startswith(("ERROR:", "FAIL:"))]
            ok = process.returncode == 0 and not errors
            passed &= ok
            print(f"{'PASS' if ok else 'FAIL'} {scene} {transport if network else ''} process={index}", flush=True)
            if not ok:
                print(output, flush=True)
        return passed
    finally:
        for process in processes:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("scenes", nargs="*")
    parser.add_argument("--network", action="store_true")
    parser.add_argument("--transport", choices=["enet", "ws"], default="enet")
    args = parser.parse_args()
    results = [run(scene, args.network, args.transport) for scene in args.scenes]
    raise SystemExit(0 if results and all(results) else 1)
