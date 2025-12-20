#!/bin/bash
#SBATCH --cpus-per-task=16
#SBATCH --job-name=Spectra_Perf

ml load math/Eigen/3.4.0-GCCcore-13.3.0

CORES=(1 2 4 8 16)
SAMPLE_RATE=3

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTDIR="outputs/perf_$TIMESTAMP"
mkdir -p "$OUTDIR"
CSV="$OUTDIR/perf_results.csv"

MATRICES=("matrices/symmetric/binary/ct20stif.dat"
          "matrices/general/binary/ct20stif.dat")

N_EIGVALS=2
N_BVECS=100

# Header erweitert um SpMV-Zeit, Management-Zeit und Anzahl der Operationen
echo "cores,run,algorithm,matrix,real_time_s,user_time_s,sys_time_s,instructions,cycles,cache_misses,spmv_time_s,mgmt_time_s,num_ops" > "$CSV"

for M in "${MATRICES[@]}"; do
# This is very specific to the current file & folder structure
    echo "=== Matrix: $M ==="
    if [[ $M == *"symmetric"* ]]; then
        ALGO="lanczos"
    else
        ALGO="arnoldi"
    fi

    for C in "${CORES[@]}"; do
        echo "--- Cores: $C ---"
        export OMP_NUM_THREADS=$C

        for R in $(seq 1 $SAMPLE_RATE); do
            echo "  Matrix: $M, Run: $R"
            
            TMP_OUT="$OUTDIR/tmp_stdout.txt"

             # Extract the value thats before the metric name, as perf stat -x ',' outputs CSV lines with this structure
            PERF_RAW=$( { perf stat -x ',' \
                -e duration_time,user_time,system_time,instructions,cycles,cache-misses \
                ./build/spectra_omp "$M" "$ALGO" "$N_EIGVALS" "$N_BVECS" \
                1> "$TMP_OUT"; } 2>&1 )

            REAL=$(echo "$PERF_RAW" | awk -F',' '$3=="duration_time" {print $1}')
            USER=$(echo "$PERF_RAW" | awk -F',' '$3=="user_time" {print $1}')
            SYS=$(echo "$PERF_RAW" | awk -F',' '$3=="system_time" {print $1}')
            INST=$(echo "$PERF_RAW" | awk -F',' '$3=="instructions" {print $1}')
            CYCL=$(echo "$PERF_RAW" | awk -F',' '$3=="cycles" {print $1}')
            MISS=$(echo "$PERF_RAW" | awk -F',' '$3=="cache-misses" {print $1}')

            EXTRA_LINE=$(grep "EXTRA_DATA" "$TMP_OUT")
            SPMV_T=$(echo "$EXTRA_LINE" | cut -d',' -f2)
            MGMT_T=$(echo "$EXTRA_LINE" | cut -d',' -f3)
            NUM_OPS=$(echo "$EXTRA_LINE" | cut -d',' -f4)

            echo "$C,$R,$ALGO,$M,$REAL,$USER,$SYS,$INST,$CYCL,$MISS,$SPMV_T,$MGMT_T,$NUM_OPS" >> "$CSV"
            
            rm "$TMP_OUT"
        done
    done
done