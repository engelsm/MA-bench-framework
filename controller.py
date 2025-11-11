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
from datetime import datetime
import json
import os
import subprocess
import sys
import time

import yaml

# --------------------------------------------------------------
# System information
# --------------------------------------------------------------
def detect_system_environment():
    """
    Detects the system environment for amd-secure-bench:
      - Verifies Linux platform
      - Detects CPU model and vendor
      - Checks AMD SME and SEV secure memory modes
    Returns:
      dict: {
        "platform": str,
        "cpu_model": str,
        "is_amd": bool,
        "sme_active": bool,
        "sev_active": bool
      }
    """

    # --- platform check ---
    if not sys.platform.startswith("linux"):
        print(f"[ERROR] amd-secure-bench is intended for Linux/HPC environments only. "
              f"You are running on: {sys.platform}")
        sys.exit(1)

    # --- CPU model detection ---
    cpu_model = "Unknown CPU Model"
    try:
        with open("/proc/cpuinfo") as f:
            for line in f:
                if line.strip().startswith("model name"):
                    cpu_model = line.strip().split(": ")[1]
                    break
    except Exception:
        pass

    is_amd = cpu_model.lower().startswith("amd")

    if not is_amd:
        print(f"[WARNING] amd-secure-bench is intended for AMD hardware only. "
              f"Program might not work as intended. Detected CPU model: {cpu_model}")

    # --- secure mode detection ---
    sme_active = False
    sev_active = False

    sme_path = "/sys/kernel/mm/mem_encrypt/active"
    sev_path = "/sys/module/kvm_amd/parameters/sev"

    try:
        if os.path.exists(sme_path):
            with open(sme_path) as f:
                sme_active = f.read().strip() == "1"
        else:
            dmesg_out = subprocess.run(["dmesg"], capture_output=True, text=True).stdout
            sme_active = "SME active" in dmesg_out
    except Exception:
        pass

    try:
        if os.path.exists(sev_path):
            with open(sev_path) as f:
                sev_active = f.read().strip() == "1"
        else:
            dmesg_out = subprocess.run(["dmesg"], capture_output=True, text=True).stdout
            sev_active = "SEV" in dmesg_out and "enabled" in dmesg_out
    except Exception:
        pass

    print("[INFO] AMD Security Mode Detection")
    print(f"  SME active: {'Yes' if sme_active else 'No'}")
    print(f"  SEV active: {'Yes' if sev_active else 'No'}")

    return {
        "platform": sys.platform,
        "cpu_model": cpu_model,
        "is_amd": is_amd,
        "sme_active": sme_active,
        "sev_active": sev_active,
    }


# --------------------------------------------------------------
# Compilation function
# --------------------------------------------------------------
def compile_source(source_path, compiler_flags=None, output_dir="workloads/builds"):
    """Compiles a C/C++ source file with optional compiler flags."""
    if not os.path.exists(source_path):
        print(f"[ERROR] Source file not found: {source_path}")
        sys.exit(1)

    os.makedirs(output_dir, exist_ok=True)

    ext = os.path.splitext(source_path)[1]
    output_name = os.path.splitext(os.path.basename(source_path))[0]
    binary_path = os.path.join(output_dir, output_name)

    if ext == ".c":
        compiler = "gcc"
    elif ext in (".cc", ".cpp", ".cxx"):
        compiler = "g++"
    else:
        print(f"[ERROR] Only C/C++ source files are supported. Invalid source path: {source_path}")
        sys.exit(1)

    # skip recompilation if binary is up-to-date
    if os.path.exists(binary_path):
        if os.path.getmtime(binary_path) > os.path.getmtime(source_path):
            print(f"[INFO] Using cached binary (up to date): {binary_path}")
            return binary_path

    cmd = [compiler] + compiler_flags + ["-o", binary_path, source_path]
    print(f"[INFO] Compiling: {' '.join(cmd)}")

    try:
        subprocess.run(cmd, check=True)
        print(f"[INFO] Compilation successful: {binary_path}")
        return binary_path
    except Exception as e:
        print(f"[ERROR] Compilation failed: {e}")
        sys.exit(1)


# --------------------------------------------------------------
# Benchmark runner
# --------------------------------------------------------------
def run_benchmark(exec_path, iter_total=1):
    """
    Coordinates benchmark execution and aggregation.
    """
    print(f"[INFO] Starting benchmark run: {exec_path}")

    runtime_start = time.perf_counter()
    runs_results = [run_single_benchmark(exec_path, i + 1, iter_total) for i in range(iter_total)]
    runtime_end = time.perf_counter()

    runtime_total = runtime_end - runtime_start
    runtime_avg = sum(r["runtime"] for r in runs_results) / iter_total

    print(f"[INFO] Finished {iter_total} run(s). "
          f"Total time: {runtime_total} s. Average per run: {runtime_avg} s")

    return {
        "runs_results": runs_results,
        "runtime_total": runtime_total,
        "runtime_avg": runtime_avg,
    }

def run_single_benchmark(exec_path, iter_current, iter_total):
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

    print(f"[INFO] Running iteration {iter_current}/{iter_total}")
    runtime_start = time.perf_counter()
    proc = subprocess.run(cmd, capture_output=True, text=True)
    runtime_end = time.perf_counter()

    return {
        "iteration": iter_current,
        "returncode": proc.returncode,
        "stdout": proc.stdout.strip(),
        "perf": parse_perf_output(proc.stderr),
        "runtime": runtime_end - runtime_start,
    }


# --------------------------------------------------------------
# Perf parsing and aggregation
# --------------------------------------------------------------
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
            "avg": sum(values) / len(values),
            "min": min(values),
            "max": max(values),
        }

    return agg

# --------------------------------------------------------------
# Config handling
# --------------------------------------------------------------

def load_config(path):
    """Loads YAML config file and returns (compiler_flags, benchmarks)."""
    if not os.path.exists(path):
        print(f"[ERROR] Config file not found: {path}")
        sys.exit(1)

    try:
        with open(path, "r") as f:
            config = yaml.safe_load(f) or {}
    except Exception as e:
        print(f"[ERROR] Failed to load config file: {e}")
        sys.exit(1)

    compiler_flags = config.get("compiler_flags", [])
    benchmarks = config.get("benchmarks", [])

    if not benchmarks:
        print("[ERROR] No benchmarks defined in config file.")
        sys.exit(1)

    return compiler_flags, benchmarks


# --------------------------------------------------------------
# Printing & saving
# --------------------------------------------------------------
def print_perf_summary(agg):
    """Prints aggregated perf results (avg, min, max) in a clean format."""
    print("\n[PERF SUMMARY]")
    for event, stats in agg.items():
        print(f"{event:20s}: avg={stats['avg']:<10.2f} "  #formatting arguments
              f"min={stats['min']:<10.2f} max={stats['max']:<10.2f}")

def save_results(data, output_dir="results"):
    """
    Saves benchmark results (already structured) to a JSON file.
    Returns the full path to the saved file.
    """
    os.makedirs(output_dir, exist_ok=True)

    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    filename = f"results_{timestamp}.json"
    file_path = os.path.join(output_dir, filename)

    try:
        with open(file_path, "w") as f:
            json.dump(data, f, indent=2)
        print(f"[INFO] Results saved to {file_path}")
        return file_path
    except Exception as e:
        print(f"[ERROR] Failed to save results: {e}")
        return None
    
    
# --------------------------------------------------------------
# Main entry
# --------------------------------------------------------------
if __name__ == "__main__":
    sys_info = detect_system_environment()

    parser = argparse.ArgumentParser(description="Run the amd-secure-bench benchmarking tool.")
    parser.add_argument("source", nargs="?", help="Path to C/C++ source file.")
    parser.add_argument("--runs", type=int, default=1, help="Number of runs.")
    parser.add_argument("--args", nargs="*", default=[], help="Arguments to pass to executable.")
    parser.add_argument("--config", help="Path to YAML configuration file.")
    args = parser.parse_args()

    if args.config:
    # Config-mode
        compiler_flags, benchmarks = load_config(args.config)
        all_results = [] 

        for bench in benchmarks:
            src = bench["source"]
            runs = bench.get("runs", 1)
            b_args = bench.get("args", [])
            flags = bench.get("compiler_flags", compiler_flags)

            print(f"\n[CONFIG] Running {src} ({runs} runs) with flags {flags}")
            binary_path = compile_source(src, flags)
            results = run_benchmark(binary_path, runs)

            # store structured results per benchmark
            all_results.append({
                "source": src,
                "runs": runs,
                "args": b_args,
                "compiler_flags": flags,
                "results": results,
                "aggregate": aggregate_perf_results(results["runs_results"]),
            })

            # print summary for each benchmark to console
            print_perf_summary(all_results[-1]["aggregate"])

        # save everything to one file
        combined_data = {
            "system_info": sys_info,
            "benchmarks": all_results
        }
        save_results(combined_data)
    else:
        # CLI-mode
        binary_path = compile_source(args.source)
        results = run_benchmark(binary_path, args.runs)
        save_results(results, sys_info)
        print_perf_summary(aggregate_perf_results(results["runs_results"]))
