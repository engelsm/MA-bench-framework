#!/bin/bash
#SBATCH --nodes=1
#SBATCH --exclusive
#SBATCH --job-name=SpMV_bench

# Load required modules
ml load math/Eigen/3.4.0-GCCcore-13.3.0

# Setup Output Directory
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTDIR="outputs/spmv_$TIMESTAMP"
mkdir -p "$OUTDIR"
CSV="$OUTDIR/spmv_results.csv"

# --- Hardware Configuration ---
# Based on numactl -H: Node 0 (CPUs 0-23), Node 1 (CPUs 24-47)
# Pinning threads to physical cores across the first two NUMA domains
export OMP_PLACES="{0:24},{24:24}"
export OMP_PROC_BIND=close

CORES=(1 4 8 16 24 36 48)
SAMPLE_RATE=5
ITERATIONS=75

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

# Initialize CSV Header
echo "n_cores,run,numa_config,matrix_path,iterations,perf_walltime_ns,perf_cache_misses,perf_instructions,perf_cycles,spmv_total_s,spmv_avg_s,gflops" > "$CSV"

echo "Starting Benchmark on $(hostname)"

for M in "${MATRICES[@]}"; do
    [ ! -f "$M" ] && continue
    echo "Processing: $M"

    for C in "${CORES[@]}"; do
        export OMP_NUM_THREADS=$C
        
        # Determine which NUMA configurations to run for this core count
        CONFIGS=()
        if [ $C -le 24 ]; then
            CONFIGS=("NUMA_LOCAL") # For <= 24, Optimized is just local membind
        else
            CONFIGS=("NUMA_LOCAL" "NUMA_REMOTE") # For > 24, test Interleaved vs. Forced Node 0
        fi

        for CFG in "${CONFIGS[@]}"; do
            
            # Set the numactl strategy based on core count and config type
            if [ "$CFG" == "NUMA_LOCAL" ]; then
                if [ $C -le 24 ]; then
                    NUMA_CMD="numactl --cpunodebind=0 --membind=0"
                else
                    NUMA_CMD="numactl --cpunodebind=0,1 --interleave=0,1"
                fi
            elif [ "$CFG" == "NUMA_REMOTE" ]; then
                # Threads on 0 & 1, but ALL memory forced to Node 0
                NUMA_CMD="numactl --cpunodebind=0,1 --membind=0"
            fi

            NUMA_STATUS=$($NUMA_CMD numactl --show | grep -E "policy|nodebind" | xargs echo)
            echo "Cores: $C | Config: $CFG | Cmd: $NUMA_CMD | Real: $NUMA_STATUS"

            for R in $(seq 1 $SAMPLE_RATE); do
                TMP_OUT="$OUTDIR/tmp_stdout.txt"

                # Execution
				PERF_RAW=$( { perf stat -x ',' \
                    -e duration_time,instructions,cycles,cache-misses \
                    $NUMA_CMD ./build/spmv "$M" "$ITERATIONS" \
                        1> "$TMP_OUT"; } 2>&1 )

                # Parsing Perf
                REAL=$(echo "$PERF_RAW" | awk -F',' '/duration_time/ {print $1}')
                INST=$(echo "$PERF_RAW" | awk -F',' '/instructions/ {print $1}')
                CYCL=$(echo "$PERF_RAW" | awk -F',' '/cycles/ {print $1}')
                MISS=$(echo "$PERF_RAW" | awk -F',' '/cache-misses/ {print $1}')

                # Parsing App Data
                EXTRA_LINE=$(grep "EXTRA_DATA" "$TMP_OUT")
                SPMV_TOTAL=$(echo "$EXTRA_LINE" | cut -d',' -f2)
                SPMV_AVG=$(echo "$EXTRA_LINE" | cut -d',' -f3)
                GFLOPS=$(echo "$EXTRA_LINE" | cut -d',' -f4)

                # Append to CSV including the NUMA flag
                echo "$C,$R,$CFG,$M,$ITERATIONS,$REAL,$MISS,$INST,$CYCL,$SPMV_TOTAL,$SPMV_AVG,$GFLOPS" >> "$CSV"
                
                rm "$TMP_OUT"
            done
        done
    done
done

echo "Done. File saved to: $CSV"