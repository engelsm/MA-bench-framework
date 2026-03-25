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

RUNS=10

export OMP_PROC_BIND=close
export OMP_PLACES=cores

if [ ! -f "$RESULTS_CSV" ]; then
    echo "Matrix,Cores,Run,Iterations,IO_Time,SpMV_Time,SpMV_GFLOPS,Perf_Cycles,Perf_Instructions,Perf_CacheMisses,Perf_dTLBMisses,Voluntary_CtxSwitches,Involuntary_CtxSwitches" > "$RESULTS_CSV"
fi

TOTAL_STEPS=$(grep -vE '^(Matrix|#|$)' "$PLAN" | wc -l)
CURRENT_STEP=0

echo "Starting $ENV SpMV Benchmark. Plan: $PLAN | Output: $OUTDIR"

while IFS=, read -r raw_matrix raw_cores raw_numa raw_iter || [ -n "$raw_matrix" ]; do
    
    # Trim whitespace
    matrix=$(echo "$raw_matrix" | xargs)
    cores=$(echo "$raw_cores" | xargs)
    numa=$(echo "$raw_numa" | xargs)
    iter=$(echo "$raw_iter" | xargs)

    [[ "$matrix" == "Matrix" || -z "$matrix" ]] && continue

    ((CURRENT_STEP++))

    CURRENT_RUNS=$(awk -F',' -v m="$matrix" -v c="$cores" '$1==m && $2==c {count++} END{print count+0}' "$RESULTS_CSV")

    if (( CURRENT_RUNS >= RUNS )); then
        echo "Skipping $matrix | cores=$cores (already completed)"
        continue
    fi

    EXTRA_SUBDIR="$EXTRA_DIR/${matrix%.*}_c${cores}"
    mkdir -p "$EXTRA_SUBDIR"
    NUMA_LOG="$EXTRA_SUBDIR/numa.log"
    ITER_CSV="$EXTRA_SUBDIR/iter.csv"
    echo "Run,Iter,Time,GFLOPS" > "$ITER_CSV"

    FULL_MATRIX_PATH="$MATRIX_DIR/$matrix"

    CORE_RANGE="0-$(($cores - 1))"

    if [[ "$numa" == "default" ]]; then
        if [ "$cores" -le 24 ]; then
            TARGET_NODE=0
        elif [ "$cores" -le 48 ]; then
            TARGET_NODE=0,1
        fi
        NUMA_FLAG="--membind=$TARGET_NODE"
    elif [[ "$numa" == "interleave" ]]; then
        NUMA_FLAG="--interleave=all"
    fi

    echo "=== [$CURRENT_STEP/$TOTAL_STEPS] $matrix | Cores: $cores ==="

    for ((run_nr=CURRENT_RUNS+1; run_nr<=RUNS; run_nr++)); do
        
        echo -n "[$(date +%H:%M:%S)] Run $run_nr/$RUNS ... "


        setarch $(uname -m) -R numactl -C $CORE_RANGE $NUMA_FLAG "$BINARY" "$FULL_MATRIX_PATH" "$iter" 0 "$run_nr" "$cores" "$RESULTS_CSV" "$ITER_CSV" &
        
        PID=$!

        if [ "$run_nr" -eq 1 ]; then    
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
echo "Results: $RESULTS_CSV"
echo "Iterations: $ITER_CSV"
echo "NUMA-Logs: $OUTDIR/numa_logs/"