#!/bin/bash
ml tools/numactl/2.0.19-GCCcore-14.2.0

ENV=$1
if [ -z "$ENV" ]; then
    echo "Usage: $0 <env_name>"
    exit 1
fi

BASE_DIR="$HOME/MA-bench-framework"
MATRIX_DIR="$BASE_DIR/matrices/spmv"
BINARY="$BASE_DIR/build/spmv_deep_analysis"

CSV_A="$BASE_DIR/benchmark/spmv_deep_analysis/${ENV}a.csv"
DEBUG_LOG="$BASE_DIR/benchmark/spmv_deep_analysis/${ENV}_numa_details.log"

MATRICES=(0-0_N1008246.bin) 
CORE_CONFIGS=(24)
RUNS=15
ITER=1000

mkdir -p "$BASE_DIR/benchmark/spmv_deep_analysis"

echo "Matrix,Cores,Run,Type,Iteration,Runtime,Gflops" > "$CSV_A"
echo "--- NUMA ERROR LOG: $(date) ---" > "$DEBUG_LOG"

export OMP_PROC_BIND=close
export OMP_PLACES=cores

for MATRIX_FILE in "${MATRICES[@]}"; do
    MATRIX_PATH="$MATRIX_DIR/$MATRIX_FILE"
    for CORES in "${CORE_CONFIGS[@]}"; do
        export OMP_NUM_THREADS=$CORES

        if [ "$CORES" -eq 24 ]; then
            M_A=0; T_A="N0"
            M_B=1; T_B="N1"
        else
            M_A=0-1; T_A="N[01]"
            M_B=2-3; T_B="N[23]"
        fi

        T_A="N1"

        for ((RUN_ID=1; RUN_ID<=RUNS; RUN_ID++)); do
            echo "[$(date +%H:%M:%S)] Run $RUN_ID | Matrix: $MATRIX_FILE | Cores: $CORES"

            numactl --physcpubind=24-47 --membind=1 $BINARY "$MATRIX_PATH" $ITER > "${CSV_A}.tmp" &
            PID_A=$!

            sleep 1.2
            {
                echo "--- RUN $RUN_ID | $MATRIX_FILE ---"
                if [ -d "/proc/$PID_A" ]; then
                    echo ">> Instanz A Misallocs (Target $T_A):"
                    grep "N[0-3]=" "/proc/$PID_A/numa_maps" | grep -v "$T_A="
                    echo ">> Instanz A NUMA Stats:"
                    numastat -p $PID_A
                fi
                echo -e "-----------------------------------\n"
            } >> "$DEBUG_LOG"

            wait $PID_A 

            awk -v mat="$MATRIX_FILE" -v c="$CORES" -v r="$RUN_ID" -F',' 'BEGIN {OFS=","} { if(NF==4) print mat, c, r, $1, $2, $3, $4 }' "${CSV_A}.tmp" >> "$CSV_A"

            rm -f "${CSV_A}.tmp"
            sleep 0.2
        done
    done
done