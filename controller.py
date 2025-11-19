"""
controller.py
----------

This script serves as the main entry point of the amd-secure-bench framework.

Usage:
    python3 controller.py ./workloads/a.exe --runs 5
"""

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
# SLURM
# --------------------------------------------------------------


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


def dispatch_slurm_script(
    benchmark_args,
    config_path,
    results_folder_name,
    exclusive_node=False,
):
    # max resources across all benchmarks
    max_cores = max(b["num_cores"] for b in benchmark_args)
    max_mem = max(b["max_memory_mb"] for b in benchmark_args)

    job_script = build_slurm_script(
        job_name=benchmark_args[0][
            "project_name"
        ],  # todo change project name usage here
        max_num_cores=max_cores,
        max_memory_mb=max_mem,
        config_path=config_path,
        benchmark_args=benchmark_args,
        exclusive_node=exclusive_node,
        results_folder_name=results_folder_name,
    )

    result = subprocess.run(
        ["sbatch"], input=job_script, capture_output=True, text=True
    )
    print(f"[INFO] Submitted SLURM job: {result.stdout.strip()}")
    if result.stderr:
        print(f"[WARNING] SLURM stderr: {result.stderr.strip()}")


def build_slurm_script(
    job_name,
    max_num_cores,
    max_memory_mb,
    config_path,
    benchmark_args,
    exclusive_node,
    results_folder_name,
):
    script_header = f"""#!/bin/bash
#SBATCH --job-name={job_name}
#SBATCH --cpus-per-task={max_num_cores}
#SBATCH --mem={max_memory_mb}MB
#SBATCH --output={results_folder_name}/slurm-%j.out
"""
    script_exclusive_node = """#SBATCH --exclusive
"""

    script_start_msg = f"""
echo "[INFO] Starting SLURM job with max resources: {max_num_cores} cores and {max_memory_mb}MB on node $(hostname)"
"""

    srun_commands = []
    for idx, b in enumerate(benchmark_args):
        ulimit_kb = b["max_memory_mb"] * 1024
        execution_command = f'ulimit -v {ulimit_kb}; python3 executor.py "{config_path}" --benchmark-index {idx} --temp_output "{results_folder_name}"'

        srun_command = f"""
export OMP_NUM_THREADS={b['num_cores']}

echo "[INFO] Executing benchmark index {idx} with {b['num_cores']} cores"

srun --ntasks=1 --cpus-per-task={b['num_cores']} bash -c '{execution_command}'
"""
        srun_commands.append(srun_command)

    script_benchmarks = "\n".join(srun_commands)

    script_benchmarks_done_msg = """
echo "[INFO] All benchmarks completed."
"""

    script_html_report = f"""
echo "[INFO] Generating HTML report."
python3 create_report.py {results_folder_name}/*.json --output "{results_folder_name}"
"""

    return (
        script_header
        + (script_exclusive_node if exclusive_node else "")
        + script_start_msg
        + script_benchmarks
        + script_benchmarks_done_msg
        + script_html_report
    )


# --------------------------------------------------------------
# Config handling
# --------------------------------------------------------------


def load_config(path):  # simpler and better error handling
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
# Main entry
# --------------------------------------------------------------
if __name__ == "__main__":

    parser = argparse.ArgumentParser(
        description="Run the amd-secure-bench benchmarking tool."
    )
    parser.add_argument("config", nargs="?", help="Path to YAML configuration file.")

    args = parser.parse_args()

    config_path = args.config
    if not config_path or not os.path.exists(config_path):
        print(f"[ERROR] Config file not found: {config_path}")
        sys.exit(1)

    benchmark_args = load_config(config_path)

    results_folder_name = (
        "output/"
        + benchmark_args[0]["project_name"]
        + datetime.now().strftime("_%Y%m%d-%H%M%S")
    )
    os.makedirs(results_folder_name, exist_ok=True)
    dispatch_slurm_script(benchmark_args, config_path, results_folder_name)
    print("[INFO] SLURM jobs submitted. Exiting local process.")
