import argparse
import json
import os
import subprocess
import sys
import yaml
from datetime import datetime

# Running the script only works by calling src/controller.py from the parent dir at the moment. This will change with bundling.

# Testing on Red Hat Enterprise Linux 9.6 (kernel 5.14) on a dual-socket AMD EPYC 9654 system (192 CPUs, 8 NUMA nodes).
# Sysfs paths and commands used to gather system information may differ on other distros, kernels, or hardware setups.


def main():
    parser = argparse.ArgumentParser(description="Run the benchmarking tool.")
    parser.add_argument(
        "config_path", nargs="?", help="Path to YAML configuration file."
    )
    args = parser.parse_args()

    config_params, project_name = load_config(args.config_path)

    output_dir = mk_output_dir(project_name)

    write_jsons(get_system_info(), config_params, output_dir)

    dispatch_slurm_script(config_params, project_name, output_dir)

    print("[INFO] SLURM jobs submitted. Exiting local process.")


def get_system_info():
    if not sys.platform.startswith("linux"):
        return {"error": f"Linux only, running on {sys.platform}"}

    cpu_model = "Unknown"
    sockets = cores_per_socket = threads_per_core = total_cores = total_threads = 0
    numa_nodes = 0
    amd_sme = amd_sev = False

    # --- CPU info ---
    try:
        out = subprocess.check_output(["lscpu"], text=True)
        for line in out.splitlines():
            if ":" not in line:
                continue
            key, value = map(str.strip, line.split(":", 1))
            if key == "Model name":
                cpu_model = value
            elif key == "Socket(s)":
                sockets = int(value)
            elif key == "Core(s) per socket":
                cores_per_socket = int(value)
            elif key == "Thread(s) per core":
                threads_per_core = int(value)
            elif key == "CPU(s)":
                total_threads = int(value)
            elif key == "NUMA node(s)":
                numa_nodes = int(value)
        total_cores = cores_per_socket * sockets
    except Exception:
        pass

    # --- AMD Secure Modes ---
    def read_flag(path):
        try:
            return os.path.isfile(path) and open(path).read().strip() == "1"
        except:
            return False

    amd_sme = read_flag("/sys/kernel/mm/mem_encrypt/active")
    amd_sev = read_flag("/sys/module/kvm_amd/parameters/sev")

    return {
        "cpu_model": cpu_model,
        "sockets": sockets,
        "cores_per_socket": cores_per_socket,
        "threads_per_core": threads_per_core,
        "total_cores": total_cores,
        "total_threads": total_threads,
        "numa_nodes": numa_nodes,
        "amd_SME": amd_sme,
        "amd_SEV": amd_sev,
    }


def dispatch_slurm_script(
    b_params,
    project_name,
    output_dir,
    exclusive_node=False,
):
    # max resources across all benchmarks
    max_cores = max(b["num_cores"] for b in b_params)
    max_mem = max(b["max_memory_mb"] for b in b_params)

    job_script = build_slurm_script(
        job_name=project_name,
        max_num_cores=max_cores,
        max_memory_mb=max_mem,
        b_params=b_params,
        exclusive_node=exclusive_node,
        output_dir=output_dir,
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
    b_params,
    exclusive_node,
    output_dir,
):
    script_header = f"""#!/bin/bash
#SBATCH --job-name={job_name}
#SBATCH --cpus-per-task={max_num_cores}
#SBATCH --mem={max_memory_mb}MB
#SBATCH --output={output_dir}/slurm-%j.out
"""
    script_exclusive_node = """#SBATCH --exclusive
"""

    script_start_msg = f"""
echo "[INFO] Starting SLURM job with max resources: {max_num_cores} cores and {max_memory_mb}MB on node $(hostname)"
"""

    srun_commands = []
    for b in b_params:
        ulimit_kb = b["max_memory_mb"] * 1024
        execution_command = (
            f"ulimit -v {ulimit_kb}; python3 src/executor.py '{b['json_path']}'"
        )

        srun_command = f"""
export OMP_NUM_THREADS={b['num_cores']}

srun --ntasks=1 --cpus-per-task={b['num_cores']} bash -c '{execution_command}'
"""
        srun_commands.append(srun_command)

    script_benchmarks = "\n".join(srun_commands)

    script_benchmarks_done_msg = """
echo "[INFO] All benchmarks completed."
"""

    script_html_report = f"""
echo "[INFO] Generating HTML report."
python3 src/create_report.py {output_dir}/*.json --output "{output_dir}"
"""

    return (
        script_header
        + (script_exclusive_node if exclusive_node else "")
        + script_start_msg
        + script_benchmarks
        + script_benchmarks_done_msg
        + script_html_report
    )


class ConfigError(Exception):
    """Custom exception for config-related errors."""


def load_config(path):
    """Loads YAML config file and returns parsed parameters."""

    NUMA_POLICY = {
        "local": "--localalloc",
        "interleave": "--interleave=all",
    }

    path = os.path.abspath(path)
    with open(path, "r") as f:
        config = yaml.safe_load(f) or {}

    default_params = {
        "project_name": "sample-bench-project",
        "num_cores": 1,
        "numa_policy": "interleave",
        "max_memory_mb": 8192,
        "perf_counters": [],
        "compiler_flags": [],
        "args": [],
        "runs": 1,
        "warmup_runs": 0,
    }

    global_params = config.get("global", {})
    benchmarks = config.get("benchmarks")
    if not benchmarks:
        raise ConfigError("No benchmarks defined in config file.")

    project_name = config.get("project_name", default_params["project_name"])

    b_params_all = []
    for b in benchmarks:
        if not b.get("source"):
            raise ConfigError("Each benchmark entry must have a 'source' field.")
        b_params = {
            "source": os.path.abspath(b["source"]),
            "args": b.get("args", global_params.get("args", default_params["args"])),
            "runs": b.get("runs", global_params.get("runs", default_params["runs"])),
            "warmup_runs": b.get(
                "warmup_runs",
                global_params.get("warmup_runs", default_params["warmup_runs"]),
            ),
            "num_cores": b.get(
                "num_cores", global_params.get("num_cores", default_params["num_cores"])
            ),
            "numa_policy": b.get(
                "numa_policy",
                global_params.get("numa_policy", default_params["numa_policy"]),
            ),
            "max_memory_mb": b.get(
                "max_memory_mb",
                global_params.get("max_memory_mb", default_params["max_memory_mb"]),
            ),
            "perf_counters": b.get(
                "perf_counters",
                global_params.get("perf_counters", default_params["perf_counters"]),
            ),
            "compiler_flags": b.get(
                "compiler_flags",
                global_params.get("compiler_flags", default_params["compiler_flags"]),
            ),
        }

        if not isinstance(b_params["num_cores"], int) or b_params["num_cores"] <= 0:
            raise ConfigError(
                f"num_cores must be a positive integer, got: {b_params['num_cores']}"
            )

        if b_params["numa_policy"] not in NUMA_POLICY:
            raise ConfigError(
                f"Invalid numa_policy, got: {b_params['numa_policy']}, expected one of: {list(NUMA_POLICY.keys())}"
            )
        b_params["numa_policy"] = NUMA_POLICY[b_params["numa_policy"]]

        if (
            not isinstance(b_params["max_memory_mb"], int)
            or b_params["max_memory_mb"] <= 0
        ):
            raise ConfigError(
                f"max_memory_mb must be a positive integer, got: {b_params['max_memory_mb']}"
            )

        if not isinstance(b_params["args"], list):
            raise ConfigError(
                f"'args' field must be a list in benchmark: {b_params['args']}"
            )

        if not isinstance(b_params["runs"], int) or b_params["runs"] <= 0:
            raise ConfigError(
                f"'runs' must be a positive integer in benchmark: {b_params['runs']}"
            )

        if not isinstance(b_params["warmup_runs"], int) or b_params["warmup_runs"] < 0:
            raise ConfigError(
                f"'warmup_runs' must be a non-negative integer in benchmark: {b_params['warmup_runs']}"
            )

        if not isinstance(b_params["compiler_flags"], list):
            raise ConfigError(
                f"'compiler_flags' field must be a list in benchmark: {b_params['compiler_flags']}"
            )

        if not isinstance(b_params["perf_counters"], list):
            raise ConfigError(
                f"'perf_counters' field must be a list in benchmark: {b_params['perf_counters']}"
            )

        b_params_all.append(b_params)

    return b_params_all, project_name


def mk_output_dir(project_name):
    timestamp = datetime.now().strftime("_%Y%m%d-%H%M%S")
    dir_name = f"output/{project_name}{timestamp}"
    os.makedirs(dir_name, exist_ok=True)
    return os.path.abspath(dir_name)


def write_jsons(sysinfo, config_params, output_dir):
    for i, b in enumerate(config_params):
        json_path = os.path.join(output_dir, f"benchmark_{i}.json")
        b["json_path"] = json_path

        with open(json_path, "w") as f:
            json.dump({"sys_info": sysinfo, "b_infos": b}, f, indent=4)


if __name__ == "__main__":
    main()
