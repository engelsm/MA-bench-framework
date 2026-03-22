#!/bin/bash

# Start via: ssh ramses2004 "cd ~/MA-bench-framework/benchmark/spmv && nohup bash benchmark_spmv.sh sev > benchmark.log 2>&1"

ml tools/numactl/2.0.19-GCCcore-14.2.0

ENV=$1
BASE_DIR="$HOME/MA-bench-framework"
OUTDIR="$BASE_DIR/outputs/spmv/v2/$ENV"

mkdir -p "$OUTDIR"
RESULTS_CSV="$OUTDIR/results.csv"
ITER_CSV="$OUTDIR/iter.csv"

PLAN="$BASE_DIR/benchmark/spmv_v2/bench_plan.csv"
MATRIX_DIR="$BASE_DIR/matrices/spmv"
BINARY="$BASE_DIR/build/spmv_deep_analysis"

RUNS=15

export OMP_PROC_BIND=close
export OMP_PLACES=cores

if [ ! -f "$RESULTS_CSV" ]; then
    echo "Matrix,Cores,Run,Iterations,IO_Time,SpMV_Time,SpMV_GFLOPS,Perf_Cycles,Perf_Instructions,Perf_CacheMisses,Perf_dTLBMisses" > "$RESULTS_CSV"
fi
if [ ! -f "$ITER_CSV" ]; then
    echo "Run,Iter,Time,GFLOPS" > "$ITER_CSV"
fi

echo "Starting $ENV SpMV Benchmark. Plan: $PLAN | Output: $OUTDIR"

while IFS=, read -r raw_matrix raw_cores raw_numa raw_iter || [ -n "$raw_matrix" ]; do
    
    # Trim whitespace
    matrix=$(echo "$raw_matrix" | xargs)
    cores=$(echo "$raw_cores" | xargs)
    numa=$(echo "$raw_numa" | xargs)
    iter=$(echo "$raw_iter" | xargs)

    [[ "$matrix" == "Matrix" || -z "$matrix" ]] && continue

    CURRENT_RUNS=$(awk -F',' -v m="$matrix" -v c="$cores" '$1==m && $2==c {count++} END{print count+0}' "$RESULTS_CSV")

    if (( CURRENT_RUNS >= RUNS )); then
        echo "Skipping $matrix | cores=$cores (already completed)"
        continue
    fi

    FULL_MATRIX_PATH="$MATRIX_DIR/$matrix"

    CORE_RANGE="0-$(($cores - 1))"

    if [[ "$numa" == "default" ]]; then
        NUMA_FLAG=""
    elif [[ "$numa" == "interleave" ]]; then
        NUMA_FLAG="--interleave=all"
    elif [[ "$numa" == "localalloc" ]]; then
        NUMA_FLAG="--localalloc"
    fi

    NUMA_MAPS_DIR="$OUTDIR/numa_logs/${matrix}_c${cores}"
    
    mkdir -p "$NUMA_MAPS_DIR"

    echo "=== $matrix | Cores: $cores ==="

    for ((run_nr=CURRENT_RUNS+1; run_nr<=RUNS; run_nr++)); do
        
        echo -n "[$(date +%H:%M:%S)] Run $run_nr/$RUNS ... "

        NUMA_LOG="$NUMA_MAPS_DIR/run_${run_nr}.numa"

        # 1:Matrix, 2:Iters, 3:NUMA_opt(0/1), 4:Run_ID, 5:Cores, 6:Stats_CSV, 7:Output_Dir
        numactl -C $CORE_RANGE $NUMA_FLAG \
            "$BINARY" "$FULL_MATRIX_PATH" "$iter" 0 "$run_nr" "$cores" "$OUTDIR" &
        
        PID=$!

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

        wait $PID
        echo "done."
    done
done < "$PLAN"

echo "Benchmark finished."
echo "Results: $RESULTS_CSV"
echo "Iterations: $ITER_CSV"
echo "NUMA-Logs: $OUTDIR/numa_logs/"