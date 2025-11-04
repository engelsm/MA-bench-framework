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

def run_benchmark(cmd, args=[]):
    """Runs benchmark subprocess with given parameters and collects results."""

def compile_benchmark(source_file, output_file, flags=[]):
	"""Depending on the input compiles the uncompiled benchmark source file into an executable."""
     
def save_results(results):
	"""Saves the benchmark results to a file."""

if __name__ == "__main__":
   """Call run_benchmark with supplied flags/configs and handle results saving."""
   pass