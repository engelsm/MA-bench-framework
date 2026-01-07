#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=48
#SBATCH --distribution=block:block:block,Pack
#SBATCH --job-name=SpMV_SME_Bench

ml load math/Eigen/3.4.0-GCCcore-13.3.0

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTDIR="outputs/spmv_$TIMESTAMP"
mkdir -p "$OUTDIR"
CSV="$OUTDIR/spmv_results.csv"

# Force threads to stay on their assigned cores to measure SME/Cache latency accurately
export OMP_PROC_BIND=close
export OMP_PLACES=cores

CORES=(1 8 24 48)
SAMPLE_RATE=5
# Higher iterations to ensure we are out of the "noise" range
ITERATIONS=1000

# Define your synthetic matrices here
declare -a MATRICES=(
    "matrices/binary_iso/low_N100000.bin"
    "matrices/binary_iso/med_N100000.bin"
    "matrices/binary_iso/high_N100000.bin"
)

echo "=== SLURM DIAGNOSE ==="
echo "Job ID:          $SLURM_JOB_ID"
echo "Cores (Slurm):   $SLURM_CPUS_ON_NODE"
echo "Affinity Mask:   $(taskset -cp $$)"
lscpu | grep -E "Thread\(s\) per core|L3 cache"
echo "======================"

# New CSV Header tailored for SpMV metrics
echo "n_cores,run,matrix_path,iterations,perf_walltime_ns,perf_cache_misses,perf_instructions,perf_cycles,spmv_total_s,spmv_avg_s,gflops,throughput_gb_s" > "$CSV"

for M in "${MATRICES[@]}"; do
    if [ ! -f "$M" ]; then
        echo "Warning: Matrix $M not found, skipping..."
        continue
    fi

    echo "=== Matrix: $M ==="

    for C in "${CORES[@]}"; do
        echo "--- Cores: $C ---"
        export OMP_NUM_THREADS=$C
        
        for R in $(seq 1 $SAMPLE_RATE); do
            echo "  Run: $R"
            
            TMP_OUT="$OUTDIR/tmp_stdout.txt"

            # Run with perf stat
            # We track cache-misses specifically as they are the primary driver of SME decryption overhead
            PERF_RAW=$( { perf stat -x ',' \
                -e duration_time,instructions,cycles,cache-misses \
                ./build/spmv "$M" "$ITERATIONS" \
                    1> "$TMP_OUT"; } 2>&1 )

            # Parse Perf Metrics
            REAL=$(echo "$PERF_RAW" | awk -F',' '/duration_time/ {print $1}')
            INST=$(echo "$PERF_RAW" | awk -F',' '/instructions/ {print $1}')
            CYCL=$(echo "$PERF_RAW" | awk -F',' '/cycles/ {print $1}')
            MISS=$(echo "$PERF_RAW" | awk -F',' '/cache-misses/ {print $1}')

            # Parse SpMV Internal Data
            # Format from our spmv_bench: matrix, total_time, time_per_spmv, gflops, (optional gb/s)
            EXTRA_LINE=$(grep "EXTRA_DATA" "$TMP_OUT")
            SPMV_TOTAL=$(echo "$EXTRA_LINE" | cut -d',' -f2)
            SPMV_AVG=$(echo "$EXTRA_LINE" | cut -d',' -f3)
            GFLOPS=$(echo "$EXTRA_LINE" | cut -d',' -f4)
            THROUGHPUT=$(echo "$EXTRA_LINE" | cut -d',' -f5) # Depends on if you added the GB/s field

            # Save to CSV
            echo "$C,$R,$M,$ITERATIONS,$REAL,$MISS,$INST,$CYCL,$SPMV_TOTAL,$SPMV_AVG,$GFLOPS,$THROUGHPUT" >> "$CSV"
            
            rm "$TMP_OUT"
        done
    done
done

echo "Benchmark complete. Results saved in $CSV"