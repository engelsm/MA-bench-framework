#!/bin/bash
#SBATCH --cpus-per-task=16

module load lang/SciPy-bundle/2024.05-gfbf-2024a

CORES=(1 2 4 8 16)

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
MASTER_OUTDIR="outputs/benchmark_$TIMESTAMP"
mkdir -p "$MASTER_OUTDIR"

echo "Master Output folder: $MASTER_OUTDIR"

MATRIX="matrices/bcsstk13.mtx"
FORMATTED_DIR="matrices/formatted"

BASENAME=$(basename "$MATRIX" .mtx)
DENSE="$FORMATTED_DIR/${BASENAME}_dense.npy"
SPARSE="$FORMATTED_DIR/${BASENAME}_sparse.npz"

python3 src/load_matrix.py "$MATRIX"

# ----- SINGLE GLOBAL CSV -----
CSV_FILE="$MASTER_OUTDIR/benchmark_perf.csv"
echo "cores,method,event,value" > "$CSV_FILE"

# Perf events to collect
EVENTS="task-clock,cycles,instructions,branches,faults"

for N_CORES in "${CORES[@]}"; do
    
    export OMP_NUM_THREADS=$N_CORES

    echo "--- Testing with $N_CORES Core(s) ---"

    LANCZOS_OUT="$MASTER_OUTDIR/lanczos_${N_CORES}.npy"

    ########################################
    # LANCZOS RUN
    ########################################
    perf stat -x, -e $EVENTS \
        python3 src/lanczos.py "$SPARSE" "$LANCZOS_OUT" \
        > /dev/null 2> perf.tmp

    # Append perf results to ONE CSV
    while IFS=, read -r value event _; do
        echo "$N_CORES,LANCZOS,$event,$value" >> "$CSV_FILE"
    done < perf.tmp

    ########################################
    # RQI RUN
    ########################################
    perf stat -x, -e $EVENTS \
        python3 src/rqi.py "$DENSE" "$LANCZOS_OUT" \
        > /dev/null 2> perf.tmp

    while IFS=, read -r value event _; do
        echo "$N_CORES,RQI,$event,$value" >> "$CSV_FILE"
    done < perf.tmp

done

rm perf.tmp

echo "=== DONE BENCHMARKING ==="
echo "CSV saved at: $CSV_FILE"