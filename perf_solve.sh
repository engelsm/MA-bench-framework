#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=48
#SBATCH --distribution=block:block:block,Pack
#SBATCH --job-name=Spectra_Perf

ml load math/Eigen/3.4.0-GCCcore-13.3.0

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTDIR="outputs/perf_$TIMESTAMP"
mkdir -p "$OUTDIR"
CSV="$OUTDIR/perf_results.csv"

export OMP_PROC_BIND=close
export OMP_PLACES=cores

CORES=(1 8 24 48)
SAMPLE_RATE=5
N_EIGVALS=10
N_BVECS=21

declare -A MATRICES
MATRICES["matrices/binary/Bump2911.bin"]="lanczos"

echo "=== SLURM DIAGNOSE ==="
echo "Job ID:          $SLURM_JOB_ID"
echo "Kerne (Slurm):   $SLURM_CPUS_ON_NODE"
echo "Affinity Mask:   $(taskset -cp $$)"
lscpu | grep -E "Thread\(s\) per core|L3 cache"
echo "======================"

echo "n_cores,run,algorithm,matrix_path,n_eigvals,n_bvecs,perf_walltime_ns,perf_usertime_ns,perf_systime_ns,perf_instructions,perf_cycles,perf_cache_misses,intern_spmvtime_s,intern_mgmttime_s,intern_n_ops" > "$CSV"

for M in "${!MATRICES[@]}"; do
    ALGO=${MATRICES[$M]}
    echo "=== Matrix: $M (ALGO: $ALGO)==="

    for C in "${CORES[@]}"; do
        echo "--- Cores: $C ---"
        export OMP_NUM_THREADS=$C
        
        for R in $(seq 1 $SAMPLE_RATE); do
            echo "  Matrix: $M, Run: $R"
            
            TMP_OUT="$OUTDIR/tmp_stdout.txt"

             # Extract the value thats before the metric name, as perf stat -x ',' outputs CSV lines with this structure
            PERF_RAW=$( { perf stat -x ',' \
            -e duration_time,user_time,system_time,instructions,cycles,cache-misses \
            ./build/solve "$M" "$ALGO" "$N_EIGVALS" "$N_BVECS" \
                1> "$TMP_OUT"; } 2>&1 )
            REAL=$(echo "$PERF_RAW" | awk -F',' '/duration_time/ {print $1}')
            USER=$(echo "$PERF_RAW" | awk -F',' '/user_time/ {print $1}')
            SYS=$(echo "$PERF_RAW" | awk -F',' '/system_time/ {print $1}')
            INST=$(echo "$PERF_RAW" | awk -F',' '/instructions/ {print $1}')
            CYCL=$(echo "$PERF_RAW" | awk -F',' '/cycles/ {print $1}')
            MISS=$(echo "$PERF_RAW" | awk -F',' '/cache-misses/ {print $1}')

            EXTRA_LINE=$(grep "EXTRA_DATA" "$TMP_OUT")
            SPMV_T=$(echo "$EXTRA_LINE" | cut -d',' -f2)
            MGMT_T=$(echo "$EXTRA_LINE" | cut -d',' -f3)
            NUM_OPS=$(echo "$EXTRA_LINE" | cut -d',' -f4)

            echo "$C,$R,$ALGO,$M,$N_EIGVALS,$N_BVECS,$REAL,$USER,$SYS,$INST,$CYCL,$MISS,$SPMV_T,$MGMT_T,$NUM_OPS" >> "$CSV"
            
            rm "$TMP_OUT"
        done
    done
done