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

from datetime import datetime
import argparse
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
    Detects the system environment:
      - Verifies Linux platform
      - Detects CPU model and vendor
      - Checks AMD SME and SEV secure memory modes
    """

    if not sys.platform.startswith("linux"):
        print(f"[ERROR] amd-secure-bench is intended for Linux environments only. "
              f"You are running on: {sys.platform}")
        sys.exit(1)

    cpu_model = detect_cpu_model()
    amd_secure_modes = detect_amd_secure_modes()
    numa_topology = detect_numa_topology()

    return {
        "platform": sys.platform,
        "cpu_model": cpu_model,
        "sme_active": amd_secure_modes["sme_active"],
        "sev_active": amd_secure_modes["sev_active"],
        "numa_topology": numa_topology,
    }

def detect_cpu_model():
    cpu_model = "Unknown CPU Model"
    try:
        with open("/proc/cpuinfo") as f:
            for line in f:
                if line.strip().startswith("model name"):
                    cpu_model = line.strip().split(": ")[1]
                    break
    except Exception:
        pass

    return cpu_model

def detect_amd_secure_modes():
    def read_flag(path):
        if not os.path.isfile(path):
            return False
        try:
            return open(path).read().strip() == "1"
        except:
            return False

    sme_active = read_flag("/sys/kernel/mm/mem_encrypt/active")
    sev_active = read_flag("/sys/module/kvm_amd/parameters/sev")

    return {"sme_active":sme_active, "sev_active": sev_active }

def detect_numa_topology():
    base = "/sys/devices/system/node/"
    nodes = {}

    for entry in os.listdir(base):
        if not entry.startswith("node"):
            continue
        
        node_id = entry[4:]  # extract number from "nodeX"
        node_path = os.path.join(base, entry)
        cpulist_path = os.path.join(node_path, "cpulist")
        meminfo_path = os.path.join(node_path, "meminfo")

        # --- CPUs ---
        cpus = []
        if os.path.isfile(cpulist_path):
            try:
                raw = open(cpulist_path).read().strip()
                for part in raw.split(","):
                    if "-" in part:
                        start, end = map(int, part.split("-"))
                        cpus.extend(range(start, end + 1))
                    else:
                        cpus.append(int(part))
            except:
                cpus = []

        # --- Memory ---
        mem_total = 0
        if os.path.isfile(meminfo_path):
            try:
                with open(meminfo_path) as f:
                    for line in f:
                        if line.startswith("MemTotal"):
                            mem_total = int(line.split()[1])
                            break
            except:
                mem_total = 0

        nodes[int(node_id)] = {"cpus": cpus, "mem_total_kb": mem_total}
    return dict(sorted(nodes.items()))


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
    if os.path.exists(binary_path) and os.path.getmtime(binary_path) > os.path.getmtime(source_path):
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
# Command builder
# --------------------------------------------------------------

def build_exec_command(exec_path, resources=None, perf_counters=None):
    """Builds the full subprocess command using numactl and perf options."""

    base_cmd = ["perf", "stat", "-x,"]
    if perf_counters:
        base_cmd += ["-e", ",".join(perf_counters)]
    base_cmd.append(exec_path)

    if not resources:
        return base_cmd

    num_cores = resources.get("num_cores")
    policy = resources.get("numa_policy")

    if num_cores is None or num_cores <= 0:
        print(f"[ERROR] Invalid num_cores in config: {num_cores}. Must be >= 1")
        sys.exit(1)

    core_list = "0" if num_cores == 1 else f"0-{num_cores-1}"
    cpu_flag = f"--physcpubind={core_list}"

    NUMA_FLAGS = {
        "local": "--localalloc",
        "interleave": "--interleave=all",
    }

    if policy not in NUMA_FLAGS:
        print(f"[ERROR] Invalid numa_policy in config: {policy}. Must be 'local' or 'interleave'.")
        sys.exit(1)

    numa_flags = NUMA_FLAGS.get(policy)

    return ["numactl", cpu_flag, numa_flags, *base_cmd]

# --------------------------------------------------------------
# Benchmark runner
# --------------------------------------------------------------
def run_benchmark(exec_path, iter_total=1, resources=None, perf_counters=None):
    """
    Executes a given benchmark executable one or more times and aggregates performance results.
    Each iteration runs the binary by calling `run_single_benchmark`.
    After all iterations complete, average and total runtimes are computed.
    """
    print(f"[INFO] Starting benchmark run: {exec_path}")

    runtime_start = time.perf_counter()
    runs_results = [run_single_benchmark(exec_path, i + 1, iter_total, resources, perf_counters) for i in range(iter_total)]
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

def run_single_benchmark(exec_path, iter_current, iter_total, resources, perf_counters):
    """
    Executes one iteration of a benchmark under `perf stat` and parses results.
    """
    cmd = build_exec_command(exec_path, resources, perf_counters)

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
    """Loads YAML config file and returns parsed parameters."""
    if not os.path.exists(path):
        print(f"[ERROR] Config file not found: {path}")
        sys.exit(1)

    try:
        with open(path, "r") as f:
            config = yaml.safe_load(f) or {}
    except Exception as e:
        print(f"[ERROR] Failed to load config file: {e}")
        sys.exit(1)

    resources = config.get("resources")
    compiler_flags = config.get("compiler_flags")
    perf_counters = config.get("performance_counters") 
    benchmarks = config.get("benchmarks")

    if not benchmarks:
        print("[ERROR] No benchmarks defined in config file.")
        sys.exit(1)

    return resources, compiler_flags, perf_counters, benchmarks


# --------------------------------------------------------------
# Printing & saving
# --------------------------------------------------------------
def print_perf_summary(agg):
    """Prints aggregated perf results in a clean format."""
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

    print("[INFO] System Information")
    print(f"  Platform: {sys_info['platform']}")
    print(f"  CPU Model: {sys_info['cpu_model']}")
    print(f"  SME active: {'Yes' if sys_info['sme_active'] else 'No'}")
    print(f"  SEV active: {'Yes' if sys_info['sev_active'] else 'No'}")
    print(f"  NUMA Topology: {sys_info['numa_topology']}")

    parser = argparse.ArgumentParser(description="Run the amd-secure-bench benchmarking tool.")
    parser.add_argument("config", nargs="?", help="Path to YAML configuration file")
    args = parser.parse_args()

    config_path = args.config
    if not config_path or not os.path.exists(config_path):
        print(f"[ERROR] Config file not found: {config_path}")
        sys.exit(1)

    resources, compiler_flags, perf_counters, benchmarks = load_config(config_path)
    all_results = []

    for bench in benchmarks:
        source = bench["source"]
        runs = bench.get("runs", 1)
        b_args = bench.get("args", [])
        flags = bench.get("compiler_flags", compiler_flags)

        print(f"\n[INFO] Running {source} ({runs} runs) with compiler flags {flags} on resources {resources}")
        binary_path = compile_source(source, flags)
        results = run_benchmark(binary_path, runs, resources, perf_counters)

        all_results.append({
            "source": source,
            "runs": runs,
            "args": b_args,
            "compiler_flags": flags,
            "results": results,
            "aggregate": aggregate_perf_results(results["runs_results"]),
        })

        print_perf_summary(all_results[-1]["aggregate"])

    save_results({
        "system_info": sys_info,
        "numa_mode": resources,
        "compiler_flags": compiler_flags,
        "benchmarks": all_results
    })
