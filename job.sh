#!/bin/bash
#SBATCH --job-name=amd-secure-bench
#SBATCH --cpus-per-task=1
#SBATCH --mem=8192MB

# Run the tool inside the job and create step for proper cgroup cpu assignment
srun python3 controller.py basic_config.yaml
