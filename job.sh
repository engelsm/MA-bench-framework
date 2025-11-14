#!/bin/bash
#SBATCH --job-name=amd-secure-bench
#SBATCH --mem=8192MB

# Run the tool inside the job
python3 controller.py basic_config.yaml
