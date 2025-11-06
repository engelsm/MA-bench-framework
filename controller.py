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
import subprocess

def run_benchmark(exec_path):
    """Runs benchmark subprocess with given parameters and collects results."""
    print(f"Executing: {exec_path}")
    result = subprocess.run([exec_path], capture_output=True, text=True)
    print(f"Execution finished. Return code: {result.returncode}")
    if result.stdout:
        print("\n---- Captured STDOUT ----")
        print(result.stdout.strip())
        print("-------------------------\n")
    
    if result.stderr:
        print("\n---- Captured STDERR ----")
        print(result.stderr.strip())
        print("-------------------------\n")
        
    return result

def compile_benchmark(source_file, output_file, flags=[]):
	"""Depending on the input compiles the uncompiled benchmark source file into an executable."""
     
def save_results(results):
	"""Saves the benchmark results to a file. Maybe support automated analysis later in a separate function."""

if __name__ == "__main__":
    # Later on add config file support, for now keep it simple
    parser = argparse.ArgumentParser(description="Run the amd-secure-bench tool for benchmarking secure AMD hardware.")
    parser.add_argument("exec", help="Path to executable file.")

    args = parser.parse_args()

    results = run_benchmark(args.exec)
    save_results(results)