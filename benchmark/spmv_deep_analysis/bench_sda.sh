#!/bin/bash
ENV=$1

BASE_DIR="$HOME/MA-bench-framework"
MATRIX_DIR="$BASE_DIR/matrices/spmv"
BINARY="$BASE_DIR/build/spmv_deep_analysis"
CSV="$BASE_DIR/benchmark/spmv_deep_analysis/$ENV.csv"


MATRICES=( 0-0_N28807.bin 1-0_N432105.bin 0-0_N1008246.bin 1-0_N8642110.bin 0-0_N17284220.bin)
CORE_CONFIGS=(8 24 48 72)
RUNS=5
ITER=500

if [ ! -f "$CSV" ]; then
    echo "Matrix,Cores,Run,Type,Iteration,Runtime,Gflops" > "$CSV"
fi

for MATRIX_FILE in "${MATRICES[@]}"; do
    MATRIX_PATH="$MATRIX_DIR/$MATRIX_FILE"
    for CORES in "${CORE_CONFIGS[@]}"; do
        
        export OMP_NUM_THREADS=$CORES
        export OMP_PROC_BIND=close
        export OMP_PLACES=cores
        
        for ((RUN=1; RUN<=RUNS; RUN++)); do
            echo "[$(date +%H:%M:%S)] Testing Matrix: $MATRIX_FILE | Cores: $CORES | Run: $RUN/$RUNS"
            taskset -c 0-$((CORES-1)) $BINARY "$MATRIX_PATH" $ITER | \
            awk -v mat="$MATRIX_FILE" -v c="$CORES" -v r="$RUN" -F',' \
            'BEGIN {OFS=","} {
                print mat, c, r, $1, $2, $3, $4
            }' >> "$CSV"
        done
    done
done