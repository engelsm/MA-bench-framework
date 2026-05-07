#!/bin/bash

ml tools/numactl/2.0.19-GCCcore-14.2.0

ENV=$1
BASE_DIR="$HOME/MA-bench-framework"
OUTDIR="$BASE_DIR/outputs/krylov/test/$ENV"
mkdir -p "$OUTDIR"

RESULTS_CSV="$OUTDIR/results.csv"
PLAN="$BASE_DIR/benchmark/krylov/bench_plan.csv"
MATRIX_BASE_DIR="$BASE_DIR/matrices/binary_spmc"
BINARY="$BASE_DIR/build/krylov"

RUNS=15

export OMP_PROC_BIND=close
export OMP_PLACES=cores

if [ ! -f "$RESULTS_CSV" ]; then
    echo "Matrix,Cores,Process_NUMA_Policy,Algo,Arg1,Arg2,Arg3,Run,SpMV_Time,Mgmt_Time,N_Ops,Perf_Cycles,Perf_Instructions,Perf_CacheMisses,Perf_dTLBMisses" > "$RESULTS_CSV"
fi

TOTAL_STEPS=$(grep -vE '^(Matrix|#|$)' "$PLAN" | wc -l)
CURRENT_STEP=0

echo "Starting $ENV Krylov Benchmark. Plan: $PLAN | Output: $OUTDIR"

while IFS=, read -r raw_matrix raw_cores raw_numa raw_algo raw_arg1 raw_arg2 raw_arg3 || [ -n "$raw_matrix" ]; do
    
    # Trim whitespace
    MATRIX=$(echo "$raw_matrix" | xargs)
    CORES=$(echo "$raw_cores" | xargs)
    NUMA=$(echo "$raw_numa" | xargs)
    ALGO=$(echo "$raw_algo" | xargs)
    ARG1=$(echo "$raw_arg1" | xargs)
    ARG2=$(echo "$raw_arg2" | xargs)
    ARG3=$(echo "$raw_arg3" | xargs)

    [[ "$MATRIX" == "Matrix" || -z "$MATRIX" ]] && continue

    ((CURRENT_STEP++))

    CURRENT_RUNS=$(awk -F',' -v m="$MATRIX" -v c="$CORES" -v n="$NUMA" -v a="$ALGO" -v a1="$ARG1" -v a2="$ARG2" -v a3="$ARG3" '$1==m && $2==c && $3==n && $4==a && $5==a1 && $6==a2 && $7==a3 {count++} END{print count+0}' "$RESULTS_CSV")

    if (( CURRENT_RUNS >= RUNS )); then
        echo "Skipping $MATRIX | cores=$CORES | policy=$NUMA | algo=$ALGO | arg1=$ARG1 | arg2=$ARG2 | arg3=$ARG3 (already completed)"
        continue
    fi

    if [[ "$ALGO" == "cg" || "$ALGO" == "lanczos" ]]; then
        FULL_MATRIX_PATH="$MATRIX_BASE_DIR/symmetric/$MATRIX"
    else
        FULL_MATRIX_PATH="$MATRIX_BASE_DIR/unsymmetric/$MATRIX"
    fi

    CORE_RANGE="0-$(($CORES - 1))"

    if [ "$CORES" -le 24 ]; then
        TARGET_NODE=0
    elif [ "$CORES" -le 48 ]; then
        TARGET_NODE=0,1
    fi

    if [[ "$NUMA" == "membind" ]]; then
        NUMA_FLAG="--membind=$TARGET_NODE"
    elif [[ "$NUMA" == "interleave" ]]; then
        NUMA_FLAG="--interleave=0,1"
    fi

    echo "=== [$CURRENT_STEP/$TOTAL_STEPS] $MATRIX | Cores: $CORES | Policy: $NUMA | Algo: $ALGO | Arg1: $ARG1 | Arg2: $ARG2 | Arg3: $ARG3 ==="

    for ((RUN_NR=CURRENT_RUNS+1; RUN_NR<=RUNS; RUN_NR++)); do
        
        echo -n "[$(date +%H:%M:%S)] Run $RUN_NR/$RUNS ... "

        setarch $(uname -m) -R numactl -C $CORE_RANGE $NUMA_FLAG "$BINARY" "$FULL_MATRIX_PATH" "$ALGO" "$ARG1" "$ARG2" "$ARG3" "$RUN_NR" "$CORES" "$NUMA" "$RESULTS_CSV"

        echo "done."
    done
done < "$PLAN"

echo "Benchmark finished."
echo "Results directory: $OUTDIR"