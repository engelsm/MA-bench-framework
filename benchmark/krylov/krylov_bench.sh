#!/bin/bash

# Start via: ssh ramses2004 "cd ~/MA-bench-framework/benchmark/krylov && nohup bash krylov_bench.sh sev > benchmark.log 2>&1"

ml tools/numactl/2.0.19-GCCcore-14.2.0

ENV=$1
BASE_DIR="$HOME/MA-bench-framework"
OUTDIR="$BASE_DIR/outputs/krylov/$ENV"
mkdir -p "$OUTDIR"

RESULTS_CSV="$OUTDIR/results.csv"
PLAN="$BASE_DIR/benchmark/krylov/bench_plan.csv"
MATRIX_DIR="$BASE_DIR/matrices/krylov"
BINARY="$BASE_DIR/build/krylov"

RUNS=15

export OMP_PROC_BIND=close
export OMP_PLACES=cores

if [ ! -f "$RESULTS_CSV" ]; then
    echo "Matrix,Cores,NUMA_Policy,Arg1,Arg2,Arg3,Run,SpMV_Time,Mgmt_Time,N_Ops,Perf_Cycles,Perf_Instructions,Perf_CacheMisses,Perf_dTLBMisses,Voluntary_CtxSwitches,Involuntary_CtxSwitches,Minor_Faults,Major_Faults,Peak_RSS" > "$RESULTS_CSV"
fi

TOTAL_STEPS=$(grep -vE '^(Matrix|#|$)' "$PLAN" | wc -l)
CURRENT_STEP=0

echo "Starting $ENV Krylov Benchmark. Plan: $PLAN | Output: $OUTDIR"

while IFS=, read -r raw_matrix raw_cores raw_numa raw_algo raw_arg1 raw_arg2 raw_arg3 || [ -n "$raw_matrix" ]; do
    
    # Trim whitespace
    matrix=$(echo "$raw_matrix" | xargs)
    cores=$(echo "$raw_cores" | xargs)
    numa=$(echo "$raw_numa" | xargs)
    algo=$(echo "$raw_algo" | xargs)
    arg1=$(echo "$raw_arg1" | xargs)
    arg2=$(echo "$raw_arg2" | xargs)
    arg3=$(echo "$raw_arg3" | xargs)

    [[ "$matrix" == "Matrix" || -z "$matrix" ]] && continue

    ((CURRENT_STEP++))

    CURRENT_RUNS=$(awk -F',' -v m="$matrix" -v c="$cores" -v n="$numa" -v a="$algo" -v a1="$arg1" -v a2="$arg2" -v a3="$arg3" '$1==m && $2==c && $3==n && $4==a && $5==a1 && $6==a2 && $7==a3 {count++} END{print count+0}' "$RESULTS_CSV")

    if (( CURRENT_RUNS >= RUNS )); then
        echo "Skipping $matrix | cores=$cores | policy=$numa | algo=$algo | arg1=$arg1 | arg2=$arg2 | arg3=$arg3 (already completed)"
        continue
    fi

    FULL_MATRIX_PATH="$MATRIX_DIR/$matrix"

    CORE_RANGE="0-$(($cores - 1))"

    if [ "$cores" -le 24 ]; then
        TARGET_NODE=0
    elif [ "$cores" -le 48 ]; then
        TARGET_NODE=0,1
    fi

    if [[ "$numa" == "membind" ]]; then
        NUMA_FLAG="--membind=$TARGET_NODE"
    elif [[ "$numa" == "interleave" ]]; then
        NUMA_FLAG="--interleave=0,1"
    fi

    echo "=== [$CURRENT_STEP/$TOTAL_STEPS] $matrix | Cores: $cores | Policy: $numa | Algo: $algo | Arg1: $arg1 | Arg2: $arg2 | Arg3: $arg3 ==="

    for ((run_nr=CURRENT_RUNS+1; run_nr<=RUNS; run_nr++)); do
        
        echo -n "[$(date +%H:%M:%S)] Run $run_nr/$RUNS ... "

        setarch $(uname -m) -R numactl -C $CORE_RANGE $NUMA_FLAG "$BINARY" "$FULL_MATRIX_PATH" "$algo" "$arg1" "$arg2" "$arg3" "$run_nr" "$cores" "$numa" "$RESULTS_CSV"

        echo "done."
    done
done < "$PLAN"

echo "Benchmark finished."
echo "Results directory: $OUTDIR"