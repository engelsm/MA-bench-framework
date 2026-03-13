#!/bin/bash

# Start via: ssh ramses2004 "cd ~/MA-bench-framework/benchmark/spmv && nohup bash benchmark_spmv.sh sev > benchmark.log 2>&1"

ENV=$1

EXISTING_DIR=""

if [ -n "$EXISTING_DIR" ] && [ -d "$EXISTING_DIR" ]; then
    OUTDIR="$EXISTING_DIR"
else
    OUTDIR="$HOME/MA-bench-framework/outputs/spmv/postPRES2/$ENV"
    mkdir -p "$OUTDIR"
fi

BASE_DIR="$HOME/MA-bench-framework"
PLAN="$BASE_DIR/benchmark/spmv/bench_plan.csv"
MATRIX_DIR="$BASE_DIR/matrices/spmv"
BINARY="$BASE_DIR/build/spmv"
CSV="$OUTDIR/results.csv"
TMP_OUT="$OUTDIR/tmp_output.txt"

RUNS=15

export OMP_PROC_BIND=close
export OMP_PLACES=cores

mkdir -p "$OUTDIR"

if [ ! -f "$CSV" ]; then
    echo "Matrix,Cores,Run,Iterations,Intern_Runtime,Intern_Gflops" > "$CSV"
fi

TOTAL_CONFIGS=$(grep -vE '^(Matrix|#|$|[[:space:]]*$)' "$PLAN" | wc -l)
CONFIG_NR=0

echo "Starting $ENV SpMV Benchmark. Plan: $PLAN | Output: $CSV"


while IFS=, read -r raw_matrix raw_cores raw_iter || [ -n "$raw_matrix" ]; do
    
    matrix=$(echo "$raw_matrix" | xargs)
    cores=$(echo "$raw_cores" | xargs)
    iter=$(echo "$raw_iter" | xargs)

    [[ "$matrix" == "Matrix" || -z "$matrix" ]] && continue

	((CONFIG_NR++))

	CURRENT_RUNS=$(awk -F',' -v m="$matrix" -v c="$cores" \
	'$1==m && $2==c {count++} END{print count+0}' "$CSV")

	if (( CURRENT_RUNS >= RUNS )); then
		echo "Skipping $matrix | cores=$cores (already done)"
		continue
	fi

    FULL_MATRIX_PATH="$MATRIX_DIR/$matrix"
    
	echo "=== [$CONFIG_NR/$TOTAL_CONFIGS] $matrix | Cores: $cores ==="

    for ((run_nr=CURRENT_RUNS+1; run_nr<=RUNS; run_nr++)); do
        
        export OMP_NUM_THREADS=$cores
        echo -n "[$(date +%H:%M:%S)] Run $run_nr/$RUNS ... "

        taskset -c 0-$((cores-1)) "$BINARY" "$FULL_MATRIX_PATH" "$iter" > "$TMP_OUT"

        OUT_Runtime=$(grep "EXTRA_DATA" "$TMP_OUT" | cut -d',' -f2)
        OUT_Gflops=$(grep "EXTRA_DATA" "$TMP_OUT" | cut -d',' -f3)

        printf "%s,%s,%s,%s,%s,%s\n" \
            "$matrix" "$cores" "$run_nr" "$iter" \
            "$OUT_Runtime" "$OUT_Gflops" >> "$CSV"

        sync "$CSV"

        echo "done."
    done
done < "$PLAN"

rm -f "$TMP_OUT"
echo "Benchmark finished. Results in $CSV"