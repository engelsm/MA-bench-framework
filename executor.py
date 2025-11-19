from datetime import date, datetime
import argparse
import json
import os
import subprocess
import sys
import time
import yaml

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
        print(
            f"[ERROR] amd-secure-bench is intended for Linux environments only. "
            f"You are running on: {sys.platform}"
        )
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

    return {"sme_active": sme_active, "sev_active": sev_active}


def detect_numa_topology():  # todo why does this generate such a long list, maybe threading stuff
    return None  # disable until fixed
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


# --------------------------------------------------------------
# Compilation function
# --------------------------------------------------------------
def compile_source(source_path, compiler_flags=None, output_dir="workloads/builds"):
    """Compiles a C/C++ source file with optional compiler flags."""
    if not os.path.exists(source_path):
        print(f"[ERROR] Source file not found: {source_path}")
        sys.exit(1)

    ext = os.path.splitext(source_path)[1]
    output_name = os.path.splitext(os.path.basename(source_path))[0]
    binary_path = os.path.join(output_dir, output_name)

    if ext == ".c":
        compiler = "gcc"
    elif ext in (".cc", ".cpp", ".cxx"):
        compiler = "g++"
    else:
        print(
            f"[ERROR] Only C/C++ source files are supported. Invalid source path: {source_path}"
        )
        sys.exit(1)

    # skip recompilation if binary is up-to-date
    if os.path.exists(binary_path) and os.path.getmtime(binary_path) > os.path.getmtime(
        source_path
    ):
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
def build_exec_command(
    exec_path, numa_policy, perf_counters_custom, args, use_perf=True
):
    """
    Build the full subprocess command.
    """
    exec_path_abs = os.path.abspath(exec_path)
    args_abs = [os.path.abspath(arg) for arg in args]

    base_cmd = [exec_path_abs, *args_abs]

    if use_perf:
        perf_cmd = ["perf", "stat", "-x,"]
        if perf_counters_custom:
            perf_cmd += ["-e", ",".join(perf_counters_custom)]
        base_cmd = perf_cmd + base_cmd

    if numa_policy:
        #    cpu_list = get_slurm_cpu_list()
        #    cpu_flag = f"--physcpubind={','.join(map(str, cpu_list))}"
        numa_flag = NUMA_FLAGS[numa_policy]

        base_cmd = ["numactl", numa_flag] + base_cmd

    return base_cmd


# --------------------------------------------------------------
# Benchmark runner
# --------------------------------------------------------------
def run_benchmark(exec_path, args, iter_total, warmup_runs, numa_policy, perf_counters):
    """
    Executes a given benchmark executable one or more times.
    """

    cmd = build_exec_command(exec_path, numa_policy, perf_counters, args)
    printable_cmd = " ".join(cmd)

    print(f"[INFO] Starting benchmark run: {printable_cmd}")

    results = []
    for i in range(warmup_runs):
        print(f"[INFO] Running warmup iteration {i+1}/{warmup_runs}")
        subprocess.run(
            build_exec_command(exec_path, numa_policy, None, args, use_perf=False)
        )
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


# --------------------------------------------------------------
# Config handling
# --------------------------------------------------------------


def load_config(path):  # simpler and better error handling, put into utils.py
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

    global_params = config["global"]
    project_name = global_params.get("project_name", "amd-secure-bench")
    num_cores = global_params.get("num_cores", 1)
    numa_policy = global_params.get("numa_policy", "interleave")
    max_memory_mb = global_params.get("max_memory_mb", 8192)
    perf_counters = global_params.get("perf_counters", [])
    compiler_flags = global_params.get("compiler_flags", [])

    if not isinstance(num_cores, int):
        print(f"[ERROR] num_cores must be an integer, got: {num_cores}")
        sys.exit(1)
    if num_cores <= 0:
        print(f"[ERROR] Invalid num_cores in config: {num_cores}. Must be >= 1")
        sys.exit(1)

    if numa_policy not in NUMA_FLAGS:
        print(
            f"[ERROR] Invalid numa_policy in config: {numa_policy}. Must be 'local' or 'interleave'."
        )
        sys.exit(1)

    if not isinstance(max_memory_mb, int) or max_memory_mb <= 0:
        print(
            f"[ERROR] Invalid max_memory_mb in config: {max_memory_mb}. Must be a positive integer."
        )
        sys.exit(1)

    global_params = {
        "project_name": project_name,
        "num_cores": num_cores,
        "numa_policy": numa_policy,
        "max_memory_mb": max_memory_mb,
        "perf_counters": perf_counters,
        "compiler_flags": compiler_flags,
    }

    benchmarks = config["benchmarks"]
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
            print(
                f"[ERROR] 'runs' field must be a positive integer in benchmark: {b['source']}"
            )
            sys.exit(1)
        if "warmup_runs" in b and (
            not isinstance(b["warmup_runs"], int) or b["warmup_runs"] < 0
        ):
            print(
                f"[ERROR] 'warmup_runs' field must be a non-negative integer in benchmark: {b['source']}"
            )
            sys.exit(1)
        if "compiler_flags" in b and not isinstance(b["compiler_flags"], list):
            print(
                f"[ERROR] 'compiler_flags' field must be a list in benchmark: {b['source']}"
            )
            sys.exit(1)
        benchmark_args.append(
            {
                "project_name": project_name,
                "source": b["source"],
                "args": b.get("args", []),
                "runs": b.get("runs", 1),
                "warmup_runs": b.get("warmup_runs", 0),
                "num_cores": b.get("num_cores", num_cores),
                "numa_policy": b.get("numa_policy", numa_policy),
                "max_memory_mb": b.get("max_memory_mb", max_memory_mb),
                "perf_counters": b.get("perf_counters", perf_counters),
                "compiler_flags": b.get("compiler_flags", compiler_flags),
            }
        )

    return benchmark_args


# --------------------------------------------------------------
# Printing & saving
# --------------------------------------------------------------
def print_perf_summary(agg):  # Currently not used as unformatted json is saved
    """Prints aggregated perf results in a clean format."""
    print("\n[PERF SUMMARY]")
    for event, stats in agg.items():
        print(
            f"{event:20s}: avg={stats['avg']:<10.2f} "  # formatting arguments
            f"min={stats['min']:<10.2f} max={stats['max']:<10.2f}"
        )


def save_results(data, output_dir, index):
    """
    Saves benchmark results (already structured) to a JSON file.
    Returns the full path to the saved file.
    """
    filename = f"results_{index}.json"
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
# Main entry
# --------------------------------------------------------------
if __name__ == "__main__":
    sys_info = detect_system_environment()
    parser = argparse.ArgumentParser(
        description="Run the amd-secure-bench benchmarking tool."
    )
    parser.add_argument("config", nargs="?", help="Path to YAML configuration file.")
    parser.add_argument(
        "--benchmark-index",
        type=str,
        help="Comma-separated index to run (used by SLURM jobs)",
    )
    parser.add_argument(
        "--temp_output",
        type=str,
        nargs="?",
    )

    args = parser.parse_args()

    config_path = args.config
    if not config_path or not os.path.exists(config_path):
        print(f"[ERROR] Config file not found: {config_path}")
        sys.exit(1)

    benchmark_args = load_config(config_path)

    # pick those particular benchmark infos from the config
    benchmark_args = benchmark_args[int(args.benchmark_index)]

    b_project_name = benchmark_args["project_name"]
    b_num_cores = benchmark_args["num_cores"]
    b_max_memory_mb = benchmark_args["max_memory_mb"]
    b_numa_policy = benchmark_args["numa_policy"]
    b_source = benchmark_args["source"]
    b_flags = benchmark_args["compiler_flags"]
    b_runs = benchmark_args["runs"]
    b_warmup_runs = benchmark_args["warmup_runs"]
    b_args = benchmark_args["args"]
    b_perf_counters = benchmark_args["perf_counters"]

    print(
        f"\n[INFO] Running {b_source} ({b_runs} runs) with flags {b_flags} on resources {b_num_cores} cores, {b_max_memory_mb}MB memory, NUMA policy: {b_numa_policy}"
    )
    binary_path = compile_source(b_source, b_flags)
    results = run_benchmark(
        binary_path,
        b_args,
        b_runs,
        b_warmup_runs,
        b_numa_policy,
        b_perf_counters,
    )

    compiled_results = {
        "project_name": b_project_name,
        "source": b_source,
        "runs": b_runs,
        "warmup_runs": b_warmup_runs,
        "compiler_flags": b_flags,
        "args": b_args,
        "results": results,
    }

    save_results(
        {
            "system_info": sys_info,
            "benchmarks": compiled_results,
        },
        output_dir=args.temp_output,
        index=args.benchmark_index,
    )
