#!/bin/bash

# Start via: ssh ramses2004 "cd ~/MA-bench-framework/benchmark/spmv && nohup bash benchmark_spmv.sh sev > benchmark.log 2>&1"

ml tools/numactl/2.0.19-GCCcore-14.2.0

ENV=$1

EXISTING_DIR=""

if [ -n "$EXISTING_DIR" ] && [ -d "$EXISTING_DIR" ]; then
    OUTDIR="$EXISTING_DIR"
else
    # Output directory for results and NUMA logs
    OUTDIR="$HOME/MA-bench-framework/outputs/spmv/v2/$ENV"
    mkdir -p "$OUTDIR"
fi

BASE_DIR="$HOME/MA-bench-framework"
PLAN="$BASE_DIR/benchmark/spmv_v2/bench_plan.csv"
MATRIX_DIR="$BASE_DIR/matrices/spmv"
BINARY="$BASE_DIR/build/spmv"
CSV="$OUTDIR/results.csv"
TMP_OUT="$OUTDIR/tmp_output.txt"
PERF_TMP="$OUTDIR/perf_raw.tmp"

RUNS=15

# Thread pinning settings for NUMA consistency
export OMP_PROC_BIND=close
export OMP_PLACES=cores

mkdir -p "$OUTDIR"

# Initialize CSV header if file doesn't exist
if [ ! -f "$CSV" ]; then
    echo "Matrix,Cores,Run,Iterations,Intern_Runtime,Intern_Gflops,Perf_DurationTime,Perf_Insn,Perf_Cycl,Perf_CacheMisses,Perf_dTLBLoadMisses" > "$CSV"
fi

TOTAL_CONFIGS=$(grep -vE '^(Matrix|#|$|[[:space:]]*$)' "$PLAN" | wc -l)
CONFIG_NR=0

echo "Starting $ENV SpMV Benchmark. Plan: $PLAN | Output: $CSV"

while IFS=, read -r raw_matrix raw_cores raw_iter || [ -n "$raw_matrix" ]; do
    
    # Trim whitespace
    matrix=$(echo "$raw_matrix" | xargs)
    cores=$(echo "$raw_cores" | xargs)
    iter=$(echo "$raw_iter" | xargs)

    # Skip header or empty lines
    [[ "$matrix" == "Matrix" || -z "$matrix" ]] && continue

    ((CONFIG_NR++))

    # Check how many runs are already completed for this config
    CURRENT_RUNS=$(awk -F',' -v m="$matrix" -v c="$cores" \
    '$1==m && $2==c {count++} END{print count+0}' "$CSV")

    if (( CURRENT_RUNS >= RUNS )); then
        echo "Skipping $matrix | cores=$cores (already completed)"
        continue
    fi

    FULL_MATRIX_PATH="$MATRIX_DIR/$matrix"
    
    echo "=== [$CONFIG_NR/$TOTAL_CONFIGS] $matrix | Cores: $cores ==="

    for ((run_nr=CURRENT_RUNS+1; run_nr<=RUNS; run_nr++)); do
        
        export OMP_NUM_THREADS=$cores
        echo -n "[$(date +%H:%M:%S)] Run $run_nr/$RUNS ... "

        # Define NUMA log file for this specific run
        NUMA_LOG="$OUTDIR/${matrix}_c${cores}_r${run_nr}.numa"

        # Execute benchmark in background to capture PID for NUMA mapping
        # 1 = NUMA_optimize flag enabled in the C++ binary
        ~/perf_for_vm stat -x ',' \
            -e duration_time,instructions,cycles,cache-misses,dTLB-load-misses \
            -- numactl -C 0-$(($cores - 1)) --localalloc \
            "$BINARY" "$FULL_MATRIX_PATH" "$iter" 1 > "$TMP_OUT" 2> "$PERF_TMP" &
        
        PERF_PID=$!

        # Wait briefly to ensure the binary has finished loading and "touching" memory
        sleep 1 

        BENCH_PID=$(pgrep -P $PERF_PID)

        # Capture NUMA distribution while the process is actively calculating
        if ps -p $BENCH_PID > /dev/null; then
            {
                echo "--- Benchmarking: $matrix | Cores: $cores | Run: $run_nr ---"
                echo "--- /proc/$BENCH_PID/numa_maps ---"
                cat "/proc/$BENCH_PID/numa_maps" 2>/dev/null
                echo -e "\n--- numastat -p $BENCH_PID ---"
                numastat -p $BENCH_PID 2>/dev/null
            } > "$NUMA_LOG"
        fi

        # Wait for the benchmark process to finish
        wait $PERF_PID
        PERF_RAW=$(cat "$PERF_TMP")

        # Extract internal metrics from binary output
        OUT_Intern_Runtime=$(grep "EXTRA_DATA" "$TMP_OUT" | cut -d',' -f2)
        OUT_Intern_Gflops=$(grep "EXTRA_DATA" "$TMP_OUT" | cut -d',' -f3)
        
        # Extract hardware metrics from perf output
        OUT_Perf_DurationTime=$(echo "$PERF_RAW" | grep "duration_time" | cut -d',' -f1 | head -n1)
        OUT_Perf_Instructions=$(echo "$PERF_RAW" | grep "instructions" | cut -d',' -f1 | head -n1)
        OUT_Perf_Cycles=$(echo "$PERF_RAW" | grep "cycles" | cut -d',' -f1 | head -n1)
        OUT_Perf_CacheMisses=$(echo "$PERF_RAW" | grep "cache-misses" | cut -d',' -f1 | head -n1)
        OUT_Perf_dTLBLoadMisses=$(echo "$PERF_RAW" | grep "dTLB-load-misses" | cut -d',' -f1 | head -n1)

        # Append results to CSV
        echo "$matrix,$cores,$run_nr,$iter,$OUT_Intern_Runtime,$OUT_Intern_Gflops,$OUT_Perf_DurationTime,$OUT_Perf_Instructions,$OUT_Perf_Cycles,$OUT_Perf_CacheMisses,$OUT_Perf_dTLBLoadMisses" >> "$CSV"
        
        # Ensure file system sync for the CSV
        sync "$CSV"

        echo "done."
    done
done < "$PLAN"

# Cleanup temporary files
rm -f "$TMP_OUT" "$PERF_TMP"
echo "Benchmark finished. Results stored in $CSV"