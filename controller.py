import argparse
from datetime import datetime
import json
import os
import subprocess
import sys
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
    b_params,
    exclusive_node=False,
):
    # max resources across all benchmarks
    max_cores = max(b["num_cores"] for b in b_params)
    max_mem = max(b["max_memory_mb"] for b in b_params)

    job_script = build_slurm_script(
        job_name=b_params[0]["project_name"],  # todo change project name usage here
        max_num_cores=max_cores,
        max_memory_mb=max_mem,
        b_params=b_params,
        exclusive_node=exclusive_node,
        output_folder=os.path.dirname(b_params[0]["json_path"]),
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
    output_folder,
):
    script_header = f"""#!/bin/bash
#SBATCH --job-name={job_name}
#SBATCH --cpus-per-task={max_num_cores}
#SBATCH --mem={max_memory_mb}MB
#SBATCH --output={output_folder}/slurm-%j.out
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
python3 create_report.py {output_folder}/*.json --output "{output_folder}"
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

    b_params = []
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
        b_params.append(
            {
                "project_name": project_name,
                "source": b["source"],
                "cli_args": b.get("args", []),
                "runs": b.get("runs", 1),
                "warmup_runs": b.get("warmup_runs", 0),
                "num_cores": b.get("num_cores", num_cores),
                "numa_policy": b.get("numa_policy", numa_policy),
                "max_memory_mb": b.get("max_memory_mb", max_memory_mb),
                "perf_counters": b.get("perf_counters", perf_counters),
                "compiler_flags": b.get("compiler_flags", compiler_flags),
            }
        )

    return b_params


def create_output_subfolder(project_name):
    timestamp = datetime.now().strftime("_%Y%m%d-%H%M%S")
    folder_name = f"output/{project_name}{timestamp}"
    os.makedirs(folder_name, exist_ok=True)
    return folder_name


def write_jsons(sysinfo, config_params, output_folder):
    for i, b in enumerate(config_params):
        json_path = os.path.join(output_folder, f"benchmark_{i}.json")
        b["json_path"] = json_path

        with open(json_path, "w") as f:
            json.dump({"sys_info": sysinfo, "b_infos": b}, f, indent=4)


# --------------------------------------------------------------
# Main entry
# --------------------------------------------------------------
if __name__ == "__main__":
    sysinfo = detect_system_environment()
    parser = argparse.ArgumentParser(
        description="Run the amd-secure-bench benchmarking tool."
    )
    parser.add_argument(
        "config_path", nargs="?", help="Path to YAML configuration file."
    )
    args = parser.parse_args()
    config_path = args.config_path

    if not config_path or not os.path.exists(config_path):
        print(f"[ERROR] Config file not found: {config_path}")
        sys.exit(1)

    config_params = load_config(config_path)

    output_subfolder_name = create_output_subfolder(config_params[0]["project_name"])

    write_jsons(sysinfo, config_params, output_subfolder_name)

    dispatch_slurm_script(config_params)

    print("[INFO] SLURM jobs submitted. Exiting local process.")
