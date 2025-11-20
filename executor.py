import argparse
import json
import os
import subprocess
import sys
import time

# Running on Red Hat Enterprise Linux 9.6 (kernel 5.14) on a dual-socket AMD EPYC 9654 system (192 CPUs, 8 NUMA nodes).
# Sysfs paths may differ on other distros, kernels, or hardware setups.

NUMA_FLAGS = {
    "local": "--localalloc",
    "interleave": "--interleave=all",
}


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
def run_warmup(cmd, runs):
    """
    Executes warmup runs for the benchmark.
    """
    cmd_printable = " ".join(warmup_cmd)
    print(f"[INFO] Starting warmup run(s) with command: {cmd_printable}")

    for i in range(runs):
        print(f"[INFO] Running warmup iteration {i+1}/{runs}")
        subprocess.run(
            cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )  # mute output


def run_benchmark(cmd, runs):
    """
    Executes a given benchmark executable one or more times.
    """

    results = []
    for i in range(runs):
        print(f"[INFO] Running benchmark iteration {i+1}/{runs}")
        runtime_start = time.perf_counter()
        proc = subprocess.run(cmd, capture_output=True, text=True)
        runtime_end = time.perf_counter()
        result = {
            "iteration": i,
            "returncode": proc.returncode,
            "stdout": proc.stdout.strip(),
            "stderr": proc.stderr.strip(),
            "perf": parse_perf_output(proc.stderr),
            "runtime": runtime_end - runtime_start,
        }
        results.append(result)

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


def append_json(path, data_old, results):
    data_old["results"] = results

    try:
        with open(path, "w") as f:
            json.dump(data_old, f, indent=2)
        return path
    except:
        return None


# --------------------------------------------------------------
# Main entry
# --------------------------------------------------------------
if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Run the amd-secure-bench benchmarking tool."
    )
    parser.add_argument("json_path", nargs="?", help="Path to the benchmark JSON file.")
    args = parser.parse_args()

    json_path = args.json_path  # todo error handling

    with open(json_path, "r") as f:
        json_obj = json.load(f)

    params = json_obj["b_infos"]

    num_cores = params["num_cores"]
    max_memory_mb = params["max_memory_mb"]
    numa_policy = params["numa_policy"]
    source = params["source"]
    compiler_flags = params["compiler_flags"]
    runs = params["runs"]
    warmup_runs = params["warmup_runs"]
    cli_args = params["cli_args"]
    perf_counters = params["perf_counters"]

    print(
        f"\n[INFO] Running {source} ({runs} runs) with flags {compiler_flags} on resources: {num_cores} core(s), {max_memory_mb}MB memory, NUMA policy: {numa_policy}"
    )
    binary_path = compile_source(source, compiler_flags)

    if warmup_runs > 0:
        warmup_cmd = build_exec_command(
            binary_path, numa_policy, None, cli_args, use_perf=False
        )
        run_warmup(warmup_cmd, warmup_runs)

    cmd = build_exec_command(binary_path, numa_policy, perf_counters, cli_args)
    results = run_benchmark(cmd, runs)

    append_json(json_path, json_obj, results)
