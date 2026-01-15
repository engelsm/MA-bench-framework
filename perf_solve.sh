#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=48
#SBATCH --job-name=solve_bench
#SBATCH --time=04:00:00
#SBATCH --exclusive

ml purge
ml load math/Eigen/3.4.0-GCCcore-13.3.0

echo "Cores (Slurm):    $SLURM_CPUS_ON_NODE"
lscpu | grep -E "node[0-1] CPU"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTDIR="outputs/bench_$TIMESTAMP"
mkdir -p "$OUTDIR"
CSV="$OUTDIR/results_complete.csv"

export OMP_PLACES="{0:24},{24:24}"
export OMP_PROC_BIND=close

CORES=(1 4 8 16 24 36 48)
SAMPLE_RATE=3
ITERATIONS=100      
SIZES=(20000 200000 2000000)
BASE_MAT_DIR="matrices/cgen"

echo "n_cores,run,numa_config,algorithm,matrix_name,matrix_size,perf_walltime_ns,perf_cache_misses,perf_instructions,perf_cycles,intern_spmvtime_s,intern_mgmttime_s,intern_n_ops" > "$CSV"

for N in "${SIZES[@]}"; do
    MAT_DIR="$BASE_MAT_DIR/size_$N"
    
    declare -A WORKLOAD
    WORKLOAD["$MAT_DIR/001_perfect_band.bin"]="cg lanczos bicgstab arnoldi"
    WORKLOAD["$MAT_DIR/002_sym_clusters.bin"]="cg lanczos bicgstab arnoldi"
    WORKLOAD["$MAT_DIR/003_asym_clusters.bin"]="bicgstab arnoldi"
    WORKLOAD["$MAT_DIR/004_sym_random.bin"]="cg lanczos bicgstab arnoldi"
    WORKLOAD["$MAT_DIR/005_asym_random.bin"]="bicgstab arnoldi"

    for M in "${!WORKLOAD[@]}"; do
        ALGOS=${WORKLOAD[$M]}
        M_NAME=$(basename "$M")

        for ALGO in $ALGOS; do
            for C in "${CORES[@]}"; do
                export OMP_NUM_THREADS=$C
                
                # NUMA Strategies
                CONFIGS=("NUMA_LOCAL")
                if [ $C -gt 24 ]; then CONFIGS=("NUMA_LOCAL" "NUMA_REMOTE"); fi

                for CFG in "${CONFIGS[@]}"; do
                    if [ "$CFG" == "NUMA_LOCAL" ]; then
                        if [ $C -le 24 ]; then NUMA_CMD="numactl --cpunodebind=0 --membind=0"
                        else NUMA_CMD="numactl --cpunodebind=0,1 --interleave=0,1"; fi
                    elif [ "$CFG" == "NUMA_REMOTE" ]; then
                        NUMA_CMD="numactl --cpunodebind=0,1 --membind=0"
                    fi

                    for R in $(seq 1 $SAMPLE_RATE); do
                        echo "Size: $N | $M_NAME | $ALGO | Cores: $C | $CFG | Run: $R"

                        TMP_OUT="$OUTDIR/tmp_stdout.txt"
                        PERF_OUT=$( { perf stat -x ',' \
                                -e duration_time,instructions,cycles,cache-misses \
                                $NUMA_CMD ./build/solve "$M" "$ALGO" "$ITERATIONS" \
                                1> "$TMP_OUT"; } 2>&1 )

                        REAL=$(echo "$PERF_OUT" | awk -F',' '/duration_time/ {print $1}')
                        INST=$(echo "$PERF_OUT" | awk -F',' '/instructions/ {print $1}')
                        CYCL=$(echo "$PERF_OUT" | awk -F',' '/cycles/ {print $1}')
                        MISS=$(echo "$PERF_OUT" | awk -F',' '/cache-misses/ {print $1}')

                        EXTRA_LINE=$(grep "EXTRA_DATA" "$TMP_OUT")
                        SPMV_T=$(echo "$EXTRA_LINE" | cut -d',' -f2)
                        MGMT_T=$(echo "$EXTRA_LINE" | cut -d',' -f3)
                        NUM_OPS=$(echo "$EXTRA_LINE" | cut -d',' -f4)

                        echo "$C,$R,$CFG,$ALGO,$M_NAME,$N,$REAL,$MISS,$INST,$CYCL,$SPMV_T,$MGMT_T,$NUM_OPS" >> "$CSV"
                        rm -f "$TMP_OUT"
                    done
                done
            done
        done
    done
    unset WORKLOAD
done