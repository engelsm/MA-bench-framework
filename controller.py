"""
controller.py
----------

This script serves as the main entry point of the amd-secure-bench framework.
- Runs C/C++ benchmark executables via subprocess
- Collects stdout, stderr, and runtime
- Saves results to 'results/results.json'

Usage:
    ...
"""

import argparse
import os
import subprocess
import sys
import time

def run_benchmark(exec_path):
    """Runs benchmark subprocess with given parameters and collects results."""

    is_linux = sys.platform.startswith('linux')
    # TODO: Add linux perf support

    results = {
        "executable": exec_path,
        "returncode": -1,
        "stdout": "",
        "stderr": "Execution failed or timed out.",
        "runtime_seconds": -1.0,
    }

    if not is_linux:
        start_time = time.perf_counter()

        print(f"Executing: {exec_path}")
        result = subprocess.run([exec_path], capture_output=True, text=True)
        results['runtime_seconds'] = time.perf_counter() - start_time
        results['returncode'] = result.returncode
        results['stdout'] = result.stdout.strip()
        results['stderr'] = result.stderr.strip()
        
    return results

def compile_benchmark(source_file, output_file, flags=[]):
	"""Depending on the input compiles the uncompiled benchmark source file into an executable."""
     
def save_results(results):
	"""Saves the benchmark results to a file. Maybe support automated analysis later in a separate function."""

if __name__ == "__main__":
    # Later on add config file support, for now keep it simple
    parser = argparse.ArgumentParser(description="Run the amd-secure-bench tool for benchmarking secure AMD hardware.")
    parser.add_argument("exec", help="Path to executable file.")

    args = parser.parse_args()

    if not os.path.exists(args.exec):
        print(f"ERROR: Executable not found at path: {args.exec}")
    else:
        results = run_benchmark(args.exec)
        print(results)