#!/bin/bash

ml tools/numactl/2.0.19-GCCcore-14.2.0

ENV=$1

BASE_DIR="$HOME/MA-bench-framework"
MATRIX_DIR="$BASE_DIR/matrices/spmv"
BINARIES=("$BASE_DIR/build/spmv" "$BASE_DIR/build/spmv_DYNAMIC")

CSV="$BASE_DIR/benchmark/spmv_numa_investigation/${ENV}.csv"
DEBUG_LOG="$BASE_DIR/benchmark/spmv_numa_investigation/${ENV}_numa_details.log"

MATRICES=(0-0_N432105.bin) 
CORES=8
NODES=(0 1 2 3)
RUNS=50
ITER=1500

echo "Binary,Node,Run,Time" > "$CSV"

echo "--- LOG: $(date) ---" > "$DEBUG_LOG"

export OMP_PROC_BIND=close
export OMP_PLACES=cores

for NODE in "${NODES[@]}"; do
    if [ "$NODE" -eq 0 ]; then
        CORE_RANGE="0-7"
    elif [ "$NODE" -eq 1 ]; then
        CORE_RANGE="24-31"
    elif [ "$NODE" -eq 2 ]; then
        CORE_RANGE="48-55"
    elif [ "$NODE" -eq 3 ]; then
        CORE_RANGE="72-79"
    fi
    for BINARY in "${BINARIES[@]}"; do
        echo "=== Testing Binary: $(basename $BINARY) | Node: $NODE ==="
        for MATRIX_FILE in "${MATRICES[@]}"; do
            MATRIX_PATH="$MATRIX_DIR/$MATRIX_FILE"
            export OMP_NUM_THREADS=$CORES

            for ((RUN_ID=1; RUN_ID<=RUNS; RUN_ID++)); do
                echo "[$(date +%H:%M:%S)] Run $RUN_ID | Matrix: $MATRIX_FILE | Cores: $CORES | Binary: $(basename $BINARY) | Node: $NODE"

                numactl -C $CORE_RANGE --membind=$NODE $BINARY "$MATRIX_PATH" $ITER 0 $RUN_ID $CORES "membind" --cout > "${CSV}.tmp" &
                PID=$!

                sleep 1
                {
                    echo "--- RUN $RUN_ID | $(basename $BINARY) | $MATRIX_FILE ---"
                    
                    if [ -d "/proc/$PID" ]; then
                        grep "N[0-3]=" "/proc/$PID/numa_maps" 
                        echo ">> NUMA Stats:"
                        numastat -p $PID
                    fi
                    
                    echo -e "-----------------------------------\n"
                } >> "$DEBUG_LOG"

                wait $PID

                awk -F',' -v binary="$(basename $BINARY)" -v node="$NODE" -v run="$RUN_ID" '{print binary","node","run","$7}' "${CSV}.tmp" >> "$CSV"

                rm -f "${CSV}.tmp" 
            done
        done
    done
done