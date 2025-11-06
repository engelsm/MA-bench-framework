"""
controller.py
----------

This script serves as the main entry point of the amd-secure-bench framework.
- Runs C/C++ benchmark executables via subprocess
- Collects stdout, stderr, and runtime
- Saves results to 'results/results.json'

Usage:
    python3 controller.py ./workloads/a.exe --runs 5
"""

import argparse
import os
import subprocess
import sys
import time

# --------------------------------------------------------------
# Benchmark runner
# --------------------------------------------------------------
def run_benchmark(exec_path, runs=1):
    """
    Coordinates benchmark execution and aggregation.
    """
    print(f"[INFO] Running benchmark with perf: {exec_path}")

    run_start_total = time.perf_counter()
    runs_results = [run_single_benchmark(exec_path, i + 1, runs) for i in range(runs)]
    run_end_total = time.perf_counter()

    agg = aggregate_perf_results(runs_results)
    total_runtime = round(run_end_total - run_start_total, 6)
    avg_runtime = round(sum(r["runtime_seconds"] for r in runs_results) / runs, 6)

    results = {
        "executable": exec_path,
        "runs": runs,
        "perf_aggregate": agg,
        "returncodes": [r["returncode"] for r in runs_results],
        "total_runtime_seconds": total_runtime,
        "average_runtime_seconds": avg_runtime,
    }

    print(f"[INFO] Finished {runs} run(s). "
          f"Total time: {total_runtime} s. Average per-run: {avg_runtime} s")

    return results

def run_single_benchmark(exec_path, iteration, total_runs):
    """
    Executes one iteration of a benchmark under `perf stat` and parses results.
    """
    perf_events = [
        "cycles", "instructions", "branches", "branch-misses",
        "cache-references", "cache-misses",
        "dTLB-loads", "dTLB-load-misses",
        "iTLB-loads", "iTLB-load-misses",
        "page-faults", "context-switches", "cpu-migrations", "task-clock"
    ]

    cmd = ["perf", "stat", "-x,", "-e", ",".join(perf_events), exec_path]

    print(f"[INFO] Running iteration {iteration}/{total_runs}")
    run_start = time.perf_counter()
    proc = subprocess.run(cmd, capture_output=True, text=True)
    run_end = time.perf_counter()

    return {
        "iteration": iteration,
        "returncode": proc.returncode,
        "stdout": proc.stdout.strip(),
        "perf": parse_perf_output(proc.stderr),
        "runtime_seconds": round(run_end - run_start, 6),
    }


# --------------------------------------------------------------
# Perf parsing and aggregation
# --------------------------------------------------------------
def aggregate_perf_results(runs_results):
    """
    Aggregates performance counters across multiple runs.
    Returns average, min, and max for each event.
    """
    agg = {}
    all_events = {event for r in runs_results for event in r["perf"].keys()}

    for event in sorted(all_events):
        values = [float(r["perf"][event]) for r in runs_results if event in r["perf"]]
        if not values:
            continue
        agg[event] = {
            "values": values,
            "avg": round(sum(values) / len(values), 6),
            "min": min(values),
            "max": max(values),
        }

    return agg

def parse_perf_output(perf_stderr):
    """
    Parses 'perf stat -x,' CSV-style stderr output into a structured dictionary.
    Example line:
        893718,,cycles:u,1477536,100.00,0.525,GHz
    Returns:
        dict: { "cycles": 893718.0, "instructions": 542645.0, ... }
    """
    perf_data = {}

    for line in perf_stderr.strip().splitlines():
        parts = line.split(",")
        if len(parts) < 3:
            continue

        value, _, event = parts[:3]
        event = event.split(":")[0]  # remove :u, :k and other suffixes

        if not value.strip() or value == "<not supported>":
            continue

        try:
            perf_data[event] = float(value.replace(",", ""))
        except ValueError:
            continue

    return perf_data


# --------------------------------------------------------------
# System information
# --------------------------------------------------------------
def detect_cpu_model():
    with open("/proc/cpuinfo") as f:
        for line in f:
            if line.strip().startswith("model name"):
                return line.strip().split(": ")[1]
    return "Unknown CPU Model"

def detect_secure_modes():
    """
    Detects whether AMD Secure Memory Encryption (SME) and
    Secure Encrypted Virtualization (SEV) are active on the system.
    """
    sme_active = False
    sev_active = False

    # SME status
    sme_path = "/sys/kernel/mm/mem_encrypt/active"
    if os.path.exists(sme_path):
        try:
            with open(sme_path) as f:
                sme_active = f.read().strip() == "1"
        except Exception:
            pass
    else:
        try:
            dmesg_out = subprocess.run(["dmesg"], capture_output=True, text=True).stdout
            sme_active = "SME active" in dmesg_out
        except Exception:
            pass

    # SEV status
    sev_path = "/sys/module/kvm_amd/parameters/sev"
    if os.path.exists(sev_path):
        try:
            with open(sev_path) as f:
                sev_active = f.read().strip() == "1"
        except Exception:
            pass
    else:
        try:
            dmesg_out = subprocess.run(["dmesg"], capture_output=True, text=True).stdout
            sev_active = "SEV" in dmesg_out and "enabled" in dmesg_out
        except Exception:
            pass

    print("[INFO] AMD Security Mode Detection")
    print(f"  SME active: {'Yes' if sme_active else 'No'}")
    print(f"  SEV active: {'Yes' if sev_active else 'No'}")

    return {"sme": sme_active, "sev": sev_active}

# --------------------------------------------------------------
# Printing & saving
# --------------------------------------------------------------
def print_perf_summary(agg):
    """Prints aggregated perf results (avg, min, max) in a clean format."""
    print("\n[PERF SUMMARY]")
    for event, stats in agg.items():
        print(f"{event:20s}: avg={stats['avg']:<10.2f} "  #formatting arguments
              f"min={stats['min']:<10.2f} max={stats['max']:<10.2f}")

def save_results(results):
    """Placeholder for saving benchmark results to file."""
    pass


# --------------------------------------------------------------
# Main entry
# --------------------------------------------------------------
if __name__ == "__main__":
    if not sys.platform.startswith("linux"):
        print("[ERROR] amd-secure-bench is intended for Linux/HPC environments only. "
              f"You are running on: {sys.platform}")
        sys.exit(1)

    cpu_model = detect_cpu_model()
    if not cpu_model.lower().startswith("amd"):
        print("[WARNING] amd-secure-bench is intended for AMD hardware only. "
              f"Program might not work as intended. Detected CPU model: {cpu_model}")

    detect_secure_modes()

    parser = argparse.ArgumentParser(description="Run the amd-secure-bench tool for benchmarking secure AMD hardware.")
    parser.add_argument("exec", help="Path to executable file.")
    parser.add_argument("--runs", type=int, default=1, help="Number of benchmark runs to perform.")
    args = parser.parse_args()

    if not os.path.exists(args.exec):
        print(f"[ERROR] Executable not found at path: {args.exec}")
        sys.exit(1)

    results = run_benchmark(args.exec, args.runs)

    print_perf_summary(results["perf_aggregate"])
