"""
controller.py
----------

This script serves as the main entry point of the amd-secure-bench framework.
- Runs C/C++ benchmark executables via subprocess
- Collects stdout, stderr, and runtime
- Saves results to 'results/results.json'

Usage:
    ...
"""

import argparse
import os
import pprint
import subprocess
import sys
import time

def run_benchmark(exec_path):
    """Runs a Linux benchmark executable under perf stat and collects stdout, stderr, return code, and runtime."""
    print(f"[INFO] Running benchmark with perf: {exec_path}")

    perf_events = ["cycles", "instructions", "branches", "branch-misses"]
    cmd = ["perf", "stat", "-x,", "-e", ",".join(perf_events), exec_path]

    start_time = time.perf_counter()
    proc = subprocess.run(cmd, capture_output=True, text=True)
    end_time = time.perf_counter()

    results = {
        "executable": exec_path,
        "returncode": proc.returncode,
        "stdout": proc.stdout.strip(),
        "stderr": proc.stderr.strip(),
        "runtime_seconds_perf": round(end_time - start_time, 6),
        "runtime_seconds_python": time.perf_counter() - start_time
    }

    print(f"[INFO] Finished running benchmark")
    return results
     
def save_results(results):
	"""Saves the benchmark results to a file. Maybe support automated analysis later in a separate function."""

if __name__ == "__main__":
    # Later on add config file support, for now keep it simple

    if not sys.platform.startswith("linux"):
        print("[ERROR] amd-secure-bench is intended for Linux/HPC environments only. You are running on:", sys.platform)
        sys.exit(1)

    parser = argparse.ArgumentParser(description="Run the amd-secure-bench tool for benchmarking secure AMD hardware.")
    parser.add_argument("exec", help="Path to executable file.")

    args = parser.parse_args()

    if not os.path.exists(args.exec):
        print(f"[ERROR] Executable not found at path: {args.exec}")
    else:
        results = run_benchmark(args.exec)
        print("\n[RESULTS]")
        pprint.pprint(results, sort_dicts=False)