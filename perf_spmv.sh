#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --nodes=1
#SBATCH --cpus-per-task=48
#SBATCH --distribution=block:block:block,Pack
#SBATCH --job-name=SpMV_SME_Bench

#Slurm on RAMSES uses SelectTypeParameter = CR_CORE_MEMORY,CR_ONE_TASK_PER_CORE,CR_CORE_DEFAULT_DIST_BLOCK
#This is pretty unfortunate as NUMA boundaries are hard to control with this setting.
#For actual benchmarking, we need to use --exclusive.
ml load math/Eigen/3.4.0-GCCcore-13.3.0

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTDIR="outputs/spmv_$TIMESTAMP"
mkdir -p "$OUTDIR"
CSV="$OUTDIR/spmv_results.csv"

export OMP_PROC_BIND=close
export OMP_PLACES=cores

CORES=(1 4 8 16 24 36 48)
SAMPLE_RATE=5
ITERATIONS=100

declare -a MATRICES=(
    "matrices/binary_gen/low_N100000.bin"
    "matrices/binary_gen/med_N100000.bin"
    "matrices/binary_gen/high_N100000.bin"
    "matrices/binary_gen/low_N500000.bin"
    "matrices/binary_gen/med_N500000.bin"
    "matrices/binary_gen/high_N500000.bin"
    "matrices/binary_gen/low_N2000000.bin"
    "matrices/binary_gen/med_N2000000.bin"
    "matrices/binary_gen/high_N2000000.bin"
)

echo "Cores (Slurm):   $SLURM_CPUS_ON_NODE"
echo "Affinity Mask:   $(taskset -cp $$)"
lscpu | grep -E "Thread\(s\) per core|L3 cache"

echo "n_cores,run,matrix_path,iterations,perf_walltime_ns,perf_cache_misses,perf_instructions,perf_cycles,spmv_total_s,spmv_avg_s,gflops" > "$CSV"

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
            EXTRA_LINE=$(grep "EXTRA_DATA" "$TMP_OUT")
            SPMV_TOTAL=$(echo "$EXTRA_LINE" | cut -d',' -f2)
            SPMV_AVG=$(echo "$EXTRA_LINE" | cut -d',' -f3)
            GFLOPS=$(echo "$EXTRA_LINE" | cut -d',' -f4)

            # Save to CSV
            echo "$C,$R,$M,$ITERATIONS,$REAL,$MISS,$INST,$CYCL,$SPMV_TOTAL,$SPMV_AVG,$GFLOPS" >> "$CSV"
            
            rm "$TMP_OUT"
        done
    done
done

echo "Benchmark complete. Results saved in $CSV"