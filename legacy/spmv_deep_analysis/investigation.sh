#!/bin/bash
ml tools/numactl/2.0.19-GCCcore-14.2.0

ENV=$1
if [ -z "$ENV" ]; then
    echo "Usage: $0 <env_name>"
    exit 1
fi

BASE_DIR="$HOME/MA-bench-framework"
MATRIX_DIR="$BASE_DIR/matrices/spmv"
BINARY="$BASE_DIR/build/spmv"

CSV_A="$BASE_DIR/benchmark/spmv/${ENV}a.csv"
CSV_B="$BASE_DIR/benchmark/spmv/${ENV}b.csv"
DEBUG_LOG="$BASE_DIR/benchmark/spmv/${ENV}_numa_details.log"

MATRICES=(0-0_N201649.bin) 
CORE_CONFIGS=(24)
RUNS=15
ITER=1000

mkdir -p "$BASE_DIR/benchmark/spmv_numa_investigation"

echo "Matrix,Cores,Run,Type,Iteration,Runtime,Gflops" > "$CSV_A"
echo "Matrix,Cores,Run,Type,Iteration,Runtime,Gflops" > "$CSV_B"
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

        for ((RUN_ID=1; RUN_ID<=RUNS; RUN_ID++)); do
            echo "[$(date +%H:%M:%S)] Run $RUN_ID | Matrix: $MATRIX_FILE | Cores: $CORES"

            numactl --physcpubind=0-$((CORES - 1)) --membind=$M_A $BINARY "$MATRIX_PATH" $ITER 0 $RUN_ID $CORES "membind" --cout > "${CSV_A}.tmp" &
            PID_A=$!

            numactl --physcpubind=$((CORES))-$((2 * CORES - 1)) --membind=$M_B $BINARY "$MATRIX_PATH" $ITER 0 $RUN_ID $CORES "membind" --cout > "${CSV_B}.tmp" &
            PID_B=$!

            sleep 1
            {
                echo "--- RUN $RUN_ID | $MATRIX_FILE ---"
                
                # Instanz A Check
                if [ -d "/proc/$PID_A" ]; then
                    echo ">> Instanz A Misallocs (Target $T_A):"
                    grep "N[0-3]=" "/proc/$PID_A/numa_maps" | grep -v "$T_A="
                    echo ">> Instanz A NUMA Stats:"
                    numastat -p $PID_A
                fi
                
                echo -e "\n"
                
                # Instanz B Check
                if [ -d "/proc/$PID_B" ]; then
                    echo ">> Instanz B Misallocs (Target $T_B):"
                    grep "N[0-3]=" "/proc/$PID_B/numa_maps" | grep -v "$T_B="
                    echo ">> Instanz B NUMA Stats:"
                    numastat -p $PID_B
                fi
                echo -e "-----------------------------------\n"
            } >> "$DEBUG_LOG"

            wait $PID_A $PID_B

            awk -v mat="$MATRIX_FILE" -v c="$CORES" -v r="$RUN_ID" -F',' 'BEGIN {OFS=","} { if(NF==4) print mat, c, r, $1, $2, $3, $4 }' "${CSV_A}.tmp" >> "$CSV_A"
            awk -v mat="$MATRIX_FILE" -v c="$CORES" -v r="$RUN_ID" -F',' 'BEGIN {OFS=","} { if(NF==4) print mat, c, r, $1, $2, $3, $4 }' "${CSV_B}.tmp" >> "$CSV_B"

            rm -f "${CSV_A}.tmp" "${CSV_B}.tmp"
            sleep 0.2
        done
    done
done