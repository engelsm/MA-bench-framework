"""
controller.py
----------

This script serves as the main entry point of the amd-secure-bench framework.

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
import html

# Running on Red Hat Enterprise Linux 9.6 (kernel 5.14) on a dual-socket AMD EPYC 9654 system (192 CPUs, 8 NUMA nodes).
# Sysfs paths may differ on other distros, kernels, or hardware setups.

NUMA_FLAGS = { 
    "local": "--localalloc",
    "interleave": "--interleave=all",
}

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
            with open(meminfo_path) as f:
                for line in f:
                    if "MemTotal:" in line:
                        parts = line.split()
                        mem_total = int(parts[3])  
                        break

        nodes[int(node_id)] = {"cpus": cpus, "mem_total_kb": mem_total}

    return dict(sorted(nodes.items()))

def get_slurm_cpu_list():
    job_id = os.environ.get("SLURM_JOB_ID")
    if not job_id: 
        print("[ERROR] SLURM_JOB_ID not found in environment.")
        sys.exit(1)

    cpuset_path = f"/sys/fs/cgroup/system.slice/slurmstepd.scope/job_{job_id}/step_0/cpuset.cpus.effective"

    if not os.path.exists(cpuset_path):
        print(f"[ERROR] cpuset file not found: {cpuset_path}")
        sys.exit(1)

    with open(cpuset_path, "r") as f:
        spec = f.read().strip()

    if not spec:
        print(f"[ERROR] Empty cpuset specification in: {cpuset_path}")
        sys.exit(1)

    # Expand list like '0-3,8,10-12' into [0,1,2,3,8,10,11,12]
    cpu_list = []
    for part in spec.split(","):
        if "-" in part:
            start, end = map(int, part.split("-"))
            cpu_list.extend(range(start, end + 1))
        else:
            cpu_list.append(int(part))

    return cpu_list


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
def build_exec_command(exec_path, resources, perf_counters_custom, args, use_perf=True):
    """
    Build the full subprocess command.
    """

    base_cmd = [exec_path, *args]

    if use_perf:
        perf_cmd = ["perf", "stat", "-x,"]
        if perf_counters_custom:
            perf_cmd += ["-e", ",".join(perf_counters_custom)]
        base_cmd = perf_cmd + base_cmd

    if resources:
        cpu_list = get_slurm_cpu_list()
        cpu_flag = f"--physcpubind={','.join(map(str, cpu_list))}"
        numa_flag = NUMA_FLAGS[resources["numa_policy"]]

        base_cmd = ["numactl", cpu_flag, numa_flag] + base_cmd

    return base_cmd

# --------------------------------------------------------------
# Benchmark runner
# --------------------------------------------------------------
def run_benchmark(exec_path, args, iter_total=1, warmup_runs=0, resources=None, perf_counters=None):
    """
    Executes a given benchmark executable one or more times and aggregates performance results.
    Each iteration runs the binary by calling `run_single_benchmark`.
    After all iterations complete, average and total runtimes are computed.
    """

    print(args)
    cmd = build_exec_command(exec_path, resources, perf_counters, args) 
    printable_cmd = ' '.join(cmd)

    print(f"[INFO] Starting benchmark run: {printable_cmd}")

    results = []
    for i in range(warmup_runs):
        print(f"[INFO] Running warmup iteration {i+1}/{warmup_runs}") 
        subprocess.run(build_exec_command(exec_path,resources, None, args, use_perf=False)) 
    for i in range(iter_total):
        print(f"[INFO] Running iteration {i}/{iter_total}")
        runtime_start = time.perf_counter()
        proc = subprocess.run(cmd, capture_output=True, text=True)
        runtime_end = time.perf_counter()
        result = {
            "iteration": i,
            "command": printable_cmd,
            "returncode": proc.returncode,
            "stdout": proc.stdout.strip(),
            "stderr": proc.stderr.strip(),
            "perf": parse_perf_output(proc.stderr),
            "runtime": runtime_end - runtime_start,
        }
        results.append(result)

    print(f"[INFO] Finished {iter_total} run(s). ")

    return results


# --------------------------------------------------------------
# SLURM
# --------------------------------------------------------------
def dispatch_slurm_script(config_path, resources, output_dir="output"):
    os.makedirs(output_dir, exist_ok=True)

    job_script = f"""#!/bin/bash
#SBATCH --job-name=amd-secure-bench
#SBATCH --cpus-per-task={resources["num_cores"]}
#SBATCH --mem={resources["max_memory_mb"]}MB
#SBATCH --output={output_dir}/slurm-%j.out

srun python3 controller.py {config_path}
"""

    result = subprocess.run(["sbatch"], input=job_script, capture_output=True, text=True)
    print(f"[INFO] {result.stdout.strip()}")


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
    #It is possible that perf sometimes misses events unfortunately, for aggregation we only consider runs where the event was recorded
    agg = {}
    all_events = {event for r in runs_results for event in r["perf"].keys()}

    for event in sorted(all_events):
        values = [float(r["perf"][event]) for r in runs_results if event in r["perf"]]
        if not values:
            continue
        agg[event] = {
            "values": values,
            "count": len(values),
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

    resources = config.get("resources", {})
    compiler_flags = config.get("compiler_flags", [])
    perf_counters = config.get("performance_counters", []) 
    benchmarks = config["benchmarks"]
    
    num_cores = resources.get("num_cores", 1)
    numa_policy = resources.get("numa_policy", "interleave")
    max_memory_mb = resources.get("max_memory_mb", 8192)

    if not isinstance(num_cores, int):
        print(f"[ERROR] num_cores must be an integer, got: {num_cores}")
        sys.exit(1)
    if num_cores <= 0:
        print(f"[ERROR] Invalid num_cores in config: {num_cores}. Must be >= 1")
        sys.exit(1)

    if numa_policy not in NUMA_FLAGS:
        print(f"[ERROR] Invalid numa_policy in config: {numa_policy}. Must be 'local' or 'interleave'.")
        sys.exit(1)

    if not isinstance(max_memory_mb, int) or max_memory_mb <= 0:
        print(f"[ERROR] Invalid max_memory_mb in config: {max_memory_mb}. Must be a positive integer.")
        sys.exit(1)
    
    resources = { "num_cores": num_cores, "numa_policy": numa_policy, "max_memory_mb": max_memory_mb }

    if not benchmarks:
        print("[ERROR] No benchmarks defined in config file.")
        sys.exit(1)

    benchmark_args = []
    for b in benchmarks:
        if not "source" in b:
            print("[ERROR] Each benchmark entry must have a 'source' field.")
            sys.exit(1)
        if "args" in b and not isinstance(b["args"], list):
            print(f"[ERROR] 'args' field must be a list in benchmark: {b['source']}")
            sys.exit(1)
        if "runs" in b and (not isinstance(b["runs"], int) or b["runs"] <= 0):
            print(f"[ERROR] 'runs' field must be a positive integer in benchmark: {b['source']}")
            sys.exit(1)
        if "warmup_runs" in b and (not isinstance(b["warmup_runs"], int) or b["warmup_runs"] < 0):
            print(f"[ERROR] 'warmup_runs' field must be a non-negative integer in benchmark: {b['source']}")
            sys.exit(1)
        if "compiler_flags" in b and not isinstance(b["compiler_flags"], list):
            print(f"[ERROR] 'compiler_flags' field must be a list in benchmark: {b['source']}")
            sys.exit(1)
        benchmark_args.append({"source": b["source"],
                                "args": b.get("args", []),
                                "runs": b.get("runs", 1),
                                "warmup_runs": b.get("warmup_runs", 0),
                                "compiler_flags": b.get("compiler_flags", compiler_flags) #fall back to global
                            })

    return resources, perf_counters, benchmark_args


# --------------------------------------------------------------
# Printing & saving
# --------------------------------------------------------------
def print_perf_summary(agg): #Currently not used as unformatted json is saved
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
        print(f"\n[INFO] Results saved to {file_path}")
        return file_path
    except Exception as e:
        print(f"[ERROR] Failed to save results: {e}")
        return None
    
# --------------------------------------------------------------
# HTML Report
# --------------------------------------------------------------
def create_html_report(results_collection, output_dir="results"):
    import statistics

    os.makedirs(output_dir, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    report_path = os.path.join(output_dir, f"report_{timestamp}.html")

    html_content = """
<html>
<head>
    <title>amd-secure-bench Report</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 40px;
        }
        h1 {
            text-align: center;
        }
        h2 {
            border-left: 5px solid #007acc;
            padding-left: 10px;
            margin-top: 40px;
        }
        table {
            border-collapse: collapse;
            width: 100%;
            margin-bottom: 20px;
            font-size: 13px;
            table-layout: fixed;
        }
        table th, table td {
            border: 1px solid #bbb;
            padding: 4px 6px;
            line-height: 1.2;
        }
        table th {
            background: #007acc;
            color: white;
        }
        .meta {
            background: #eef6ff;
            padding: 10px;
            border-radius: 4px;
            margin-bottom: 20px;
        }
        .perf-data {
            font-family: monospace;
            white-space: pre;
            background: #f2f2f2;
            padding: 4px 6px;
            border-radius: 4px;
        }
        .details {
            display: none;
            margin-top: 10px;
        }
        .show-btn {
            background: #007acc;
            color: white;
            border: none;
            padding: 6px 10px;
            border-radius: 4px;
            cursor: pointer;
            margin-bottom: 10px;
        }
        .show-btn:hover {
            background: #005c99;
        }
    </style>

    <script>
    function toggleDetails(id) {
        const el = document.getElementById(id);
        el.style.display = (el.style.display === "none" || el.style.display === "") 
            ? "block" 
            : "none";
    }
    </script>
</head>
<body>
    <h1>amd-secure-bench Benchmark Report</h1>
"""

    for b_i, b in enumerate(results_collection):

        html_content += f"<h2>Benchmark: {html.escape(b['source'])}</h2>"

        html_content += "<div class='meta'>"
        html_content += f"<b>Compiler Flags:</b> {html.escape(' '.join(b['compiler_flags']))}<br>"
        html_content += f"<b>Runs:</b> {b['runs']} &nbsp;&nbsp; "
        html_content += f"<b>Warmup:</b> {b['warmup_runs']}<br>"
        html_content += f"<b>Args:</b> {html.escape(' '.join(b['args'])) if b['args'] else 'None'}<br>"
        html_content += "</div>"

        runtimes = [r["runtime"] for r in b["results"]]
        runtime_avg = sum(runtimes) / len(runtimes)
        runtime_min = min(runtimes)
        runtime_max = max(runtimes)
        runtime_std = statistics.stdev(runtimes) if len(runtimes) > 1 else 0.0

        html_content += "<h3>Runtime Summary</h3>"
        html_content += """
        <table>
            <tr><th>Average (s)</th><th>Min (s)</th><th>Max (s)</th><th>Stddev (s)</th></tr>
        """
        html_content += f"""
            <tr>
                <td>{runtime_avg:.6f}</td>
                <td>{runtime_min:.6f}</td>
                <td>{runtime_max:.6f}</td>
                <td>{runtime_std:.6f}</td>
            </tr>
        </table>
        """

        agg_perf = aggregate_perf_results(b["results"])

        html_content += "<h3>Performance Counter Summary</h3>"
        html_content += """
        <table>
            <tr><th>Event</th><th>Average</th><th>Min</th><th>Max</th></tr>
        """

        for event, stats in agg_perf.items():
            html_content += f"""
            <tr>
                <td>{html.escape(event)}</td>
                <td>{stats['avg']:.2f}</td>
                <td>{stats['min']:.2f}</td>
                <td>{stats['max']:.2f}</td>
            </tr>
            """

        html_content += "</table>"


        detail_id = f"details_{b_i}"

        html_content += f"""
        <button class="show-btn" onclick="toggleDetails('{detail_id}')">
            Show per-run details
        </button>
        """

        html_content += f"<div class='details' id='{detail_id}'>"

        # per-run table
        html_content += """
        <h3>Per-Run Results</h3>
        <table>
            <tr><th>Iteration</th><th>Runtime (s)</th><th>Perf Counters</th></tr>
        """

        for r in b["results"]:
            perf_data_str = "<br>".join(f"{k}: {v}" for k, v in r["perf"].items())

            html_content += f"""
            <tr>
                <td>{r['iteration']}</td>
                <td>{r['runtime']:.6f}</td>
                <td><div class="perf-data">{perf_data_str}</div></td>
            </tr>
            """

        html_content += "</table>"
        html_content += "</div>"  # end details

    html_content += "</body></html>"

    with open(report_path, "w") as f:
        f.write(html_content)

    print(f"[INFO] HTML report generated: {report_path}")

# Main entry
# --------------------------------------------------------------
if __name__ == "__main__":
    sys_info = detect_system_environment()

    parser = argparse.ArgumentParser(description="Run the amd-secure-bench benchmarking tool.")
    parser.add_argument("config", nargs="?", help="Path to YAML configuration file.")
    parser.add_argument("--slurm", action="store_true", help="Wether to create a SLURM job script instead of running locally.")
    args = parser.parse_args()

    config_path = args.config
    if not config_path or not os.path.exists(config_path):
        print(f"[ERROR] Config file not found: {config_path}")
        sys.exit(1)

    resources, perf_counters, benchmark_args = load_config(config_path)

    if args.slurm:
        dispatch_slurm_script(config_path, resources)
        sys.exit(0) 

    results_collection = []
    for b in benchmark_args:
        b_source = b["source"]
        b_flags = b["compiler_flags"]
        b_runs = b["runs"] 
        b_warmup_runs = b["warmup_runs"]
        b_args = b["args"]

        print(f"\n[INFO] Running {b_source} ({b_runs} runs) with compiler flags {b_flags} on resources {resources}")
        binary_path = compile_source(b_source, b_flags)
        results = run_benchmark(binary_path, b_args, b_runs, b_warmup_runs, resources, perf_counters)

        results_collection.append({
            "source": b_source,
            "runs": b_runs,
            "compiler_flags": b_flags,
            "warmup_runs": b_warmup_runs,
            "args": b_args,
            "results": results,
        })

    create_html_report(results_collection)

    save_results({
        "system_info": sys_info,
        "resources": resources,
        "benchmarks": results_collection
    })
