#!/bin/bash

# Start via: ssh ramses2004 "cd ~/MA-bench-framework/benchmark/spmv && nohup bash spmv_bench.sh sev > benchmark.log 2>&1"

ml tools/numactl/2.0.19-GCCcore-14.2.0

ENV=$1
BASE_DIR="$HOME/MA-bench-framework"
OUTDIR="$BASE_DIR/outputs/spmv/v3/$ENV"
mkdir -p "$OUTDIR"

EXTRA_DIR="$OUTDIR/extra"
mkdir -p "$EXTRA_DIR"

RESULTS_CSV="$OUTDIR/results.csv"
PLAN="$BASE_DIR/benchmark/spmv/bench_plan.csv"
MATRIX_DIR="$BASE_DIR/matrices/spmv"
BINARY="$BASE_DIR/build/spmv"

RUNS=15

export OMP_PROC_BIND=close
export OMP_PLACES=cores

if [ ! -f "$RESULTS_CSV" ]; then
    echo "Matrix,Cores,Process_NUMA_Policy,Run,Iterations,IO_Time,SpMV_Time,Perf_Cycles,Perf_Instructions,Perf_CacheMisses,Perf_dTLBMisses" > "$RESULTS_CSV"
fi

TOTAL_STEPS=$(grep -vE '^(Matrix|#|$)' "$PLAN" | wc -l)
CURRENT_STEP=0

echo "Starting $ENV SpMV Benchmark. Plan: $PLAN | Output: $OUTDIR"

while IFS=, read -r raw_matrix raw_cores raw_numa raw_iter || [ -n "$raw_matrix" ]; do
    
    # Trim whitespace
    MATRIX=$(echo "$raw_matrix" | xargs)
    CORES=$(echo "$raw_cores" | xargs)
    PROCESS_NUMA_POLICY=$(echo "$raw_numa" | xargs)
    MAX_ITERATIONS=$(echo "$raw_iter" | xargs)

    [[ "$MATRIX" == "Matrix" || -z "$MATRIX" ]] && continue

    ((CURRENT_STEP++))

    CURRENT_RUNS=$(awk -F',' -v m="$MATRIX" -v c="$CORES" -v n="$PROCESS_NUMA_POLICY" '$1==m && $2==c && $3==n {count++} END{print count+0}' "$RESULTS_CSV")

    if (( CURRENT_RUNS >= RUNS )); then
        echo "Skipping $MATRIX | cores=$CORES | policy=$PROCESS_NUMA_POLICY (already completed)"
        continue
    fi

    EXTRA_SUBDIR="$EXTRA_DIR/${MATRIX%.*}_c${CORES}_${PROCESS_NUMA_POLICY}"
    mkdir -p "$EXTRA_SUBDIR"
    NUMA_LOG="$EXTRA_SUBDIR/numa.log"
    ITER_CSV="$EXTRA_SUBDIR/iter.csv"
    echo "Run,Iter,Time" > "$ITER_CSV"

    FULL_MATRIX_PATH="$MATRIX_DIR/$MATRIX"

    CORE_RANGE="0-$(($CORES - 1))"

    if [ "$CORES" -le 24 ]; then
        TARGET_NODE=0
    elif [ "$CORES" -le 48 ]; then
        TARGET_NODE=0,1
    fi

    if [[ "$PROCESS_NUMA_POLICY" == "membind" ]]; then
        NUMA_FLAG="--membind=$TARGET_NODE"
    elif [[ "$PROCESS_NUMA_POLICY" == "interleave" ]]; then
        NUMA_FLAG="--interleave=0,1"
    fi

    echo "=== [$CURRENT_STEP/$TOTAL_STEPS] $MATRIX | Cores: $CORES | Policy: $PROCESS_NUMA_POLICY ==="

    for ((RUN_NR=CURRENT_RUNS+1; RUN_NR<=RUNS; RUN_NR++)); do
        
        echo -n "[$(date +%H:%M:%S)] Run $RUN_NR/$RUNS ... "

        setarch $(uname -m) -R numactl -C $CORE_RANGE $NUMA_FLAG "$BINARY" "$FULL_MATRIX_PATH" "$MAX_ITERATIONS" "$RUN_NR" "$CORES" "$PROCESS_NUMA_POLICY" "$RESULTS_CSV" "$ITER_CSV" &
        
        PID=$!

        if [ "$RUN_NR" -eq 1 ]; then    
            sleep 1
            if ps -p $PID > /dev/null; then
                {
                    echo "TIMESTAMP: $(date +%H:%M:%S)"
                    echo "--- /proc/$PID/numa_maps ---"
                    cat "/proc/$PID/numa_maps" 2>/dev/null
                    echo -e "\n--- numastat -p $PID ---"
                    numastat -p $PID 2>/dev/null
                } > "$NUMA_LOG"
            fi
        fi

        wait $PID
        echo "done."
    done
done < "$PLAN"

echo "Benchmark finished."
echo "Results directory: $OUTDIR"