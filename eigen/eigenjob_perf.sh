#!/bin/bash
#SBATCH --cpus-per-task=16
#SBATCH --job-name=Eigen_Spectra_Benchmark

# Load the required module (Eigen library)
ml load math/Eigen/3.4.0-GCCcore-13.3.0

# Define the number of cores to test
CORES=(1 2 4 8 16)
# Number of times to run each configuration
SAMPLE_RATE=5

# Setup output directory and CSV file
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTDIR="outputs/benchmark_$TIMESTAMP"
mkdir -p "$OUTDIR"
CSV="$OUTDIR/benchmark_results.csv"

# Write CSV header
echo "cores,run,algorithm,task_duration_ms,cycles,instructions,cache_refs,cache_misses,cpu_migrations,context_switches" > "$CSV"

# Define the matrix file
MATRIX="matrices/binary/bcsstk13.dat"

# Start the benchmark loop
for C in "${CORES[@]}"; do
    # Set the number of threads for OpenMP
    export OMP_NUM_THREADS=$C
    echo "--- Cores: $C, OMP_NUM_THREADS: $OMP_NUM_THREADS ---"

    for R in $(seq 1 $SAMPLE_RATE); do
        echo "  Run $R"

        # Capture perf stat output into the PERF variable (stderr is redirected to stdout, which is then captured)
        # The program's stdout is redirected to /dev/null
        PERF=$(perf stat -x, \
            -e task-clock,cycles,instructions,cache-references,cache-misses,cpu-migrations,context-switches \
            ./src_c/spectra_solver "$MATRIX" \
            2>&1 >/dev/null # This part is key: send stderr (perf output) to stdout, then capture stdout. The solver's stdout goes to /dev/null
        )

        # Parse perf output and append to CSV
        # Note: The algorithm is hardcoded as LANCZOS based on typical use case for Eigen's spectral solvers
        echo "$PERF" | awk -F, -v c="$C" -v r="$R" -v a="SPECTRA_ALGO" '
            /task-clock/       {td=$1}
            /cycles/           {cy=$1}
            /instructions/     {ins=$1}
            /cache-references/ {cr=$1}
            /cache-misses/     {cm=$1}
            /cpu-migrations/   {mig=$1}
            /context-switches/ {cs=$1}
            END {print c","r","a","td","cy","ins","cr","cm","mig","cs}
        ' >> "$CSV"
    done
done

echo "DONE → $CSV"