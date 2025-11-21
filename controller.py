import argparse
import json
import os
import subprocess
import sys
import yaml
from datetime import datetime

# Running on Red Hat Enterprise Linux 9.6 (kernel 5.14) on a dual-socket AMD EPYC 9654 system (192 CPUs, 8 NUMA nodes).
# Sysfs paths may differ on other distros, kernels, or hardware setups.


def main():
    parser = argparse.ArgumentParser(
        description="Run the amd-secure-bench benchmarking tool."
    )
    parser.add_argument(
        "config_path", nargs="?", help="Path to YAML configuration file."
    )
    args = parser.parse_args()

    config_params, project_name = load_config(args.config_path)

    output_dir = mk_output_dir(project_name)

    write_jsons(detect_system_environment(), config_params, output_dir)

    dispatch_slurm_script(config_params, project_name, output_dir)

    print("[INFO] SLURM jobs submitted. Exiting local process.")


def detect_system_environment():
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
            f"ulimit -v {ulimit_kb}; python3 executor.py '{b['json_path']}'"
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
python3 create_report.py {output_dir}/*.json --output "{output_dir}"
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

    with open(path, "r") as f:
        config = yaml.safe_load(f) or {}

    default_params = {
        "project_name": "amd-secure-bench",
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
            "source": b["source"],
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
    return dir_name


def write_jsons(sysinfo, config_params, output_dir):
    for i, b in enumerate(config_params):
        json_path = os.path.join(output_dir, f"benchmark_{i}.json")
        b["json_path"] = json_path

        with open(json_path, "w") as f:
            json.dump({"sys_info": sysinfo, "b_infos": b}, f, indent=4)


if __name__ == "__main__":
    main()
