#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --time=24:00:00
#SBATCH --exclusive

# Start via: ssh ramses2004 "cd ~/MA-bench-framework/benchmark/spmv && nohup bash benchmark_spmv.sh sev default off off > benchmark.log 2>&1"

ENV=$1

EXISTING_DIR=""

if [ -n "$EXISTING_DIR" ] && [ -d "$EXISTING_DIR" ]; then
    OUTDIR="$EXISTING_DIR"
else
    OUTDIR="$HOME/MA-bench-framework/outputs/spmv/_new/$ENV"
    mkdir -p "$OUTDIR"
fi

CSV="$OUTDIR/summary_final.csv"
TMP_OUT="$OUTDIR/tmp_output.txt"
PLAN="$HOME/MA-bench-framework/benchmark/spmv/bench_plan.csv"
MATRIX_DIR="$HOME/MA-bench-framework/matrices/spmv_synth"
BINARY="$HOME/MA-bench-framework/build/spmv"

MAX_RUNS=5
MIN_RUNS=5 #awk logic breaks if this is < 2, as divison by 0 occurs
export OMP_PROC_BIND=close
export OMP_PLACES=cores

if [ ! -f "$CSV" ]; then
    echo "Matrix,Cores,Run,Iterations,Intern_Runtime,Intern_Gflops,Perf_DurationTime,Perf_Insn,Perf_Cycl,Perf_CacheMisses,Perf_dTLBLoadMisses" > "$CSV"
fi

echo "Starting SpMV Benchmark. Plan: $PLAN | Output: $CSV"

for (( run_idx=1; run_idx<=MAX_RUNS; run_idx++ )); do
    echo "=== ROUND $run_idx ==="

    while IFS=, read -r raw_matrix raw_cores raw_iter || [ -n "$raw_matrix" ]; do
        matrix=$(echo "$raw_matrix" | tr -d '\r\n' | xargs)
        cores=$(echo "$raw_cores" | tr -d '\r\n' | xargs)
        iter=$(echo "$raw_iter" | tr -d '\r\n' | xargs)

        # Skip Header oder leere Zeilen
        [[ "$matrix" == "Matrix" || -z "$matrix" || -z "$iter" ]] && continue

        RUNTIMES=$(awk -F, -v m="$matrix" -v c="$cores" '$1==m && $2==c {print $5}' "$CSV")
        CURRENT_COUNT=$(echo "$RUNTIMES" | grep -c -v "^$")

        if (( CURRENT_COUNT >= MAX_RUNS )); then continue; fi
        if (( CURRENT_COUNT >= MIN_RUNS )); then
            CONV=$(echo "$RUNTIMES" | awk "
            BEGIN { 
                t[5]=2.776; t[6]=2.571; t[7]=2.447; t[8]=2.365; t[9]=2.306; t[10]=2.262; 
                t[11]=2.228; t[12]=2.201; t[13]=2.179; t[14]=2.160; t[15]=2.145;
                t[16]=2.131; t[17]=2.120; t[18]=2.110; t[19]=2.101; t[20]=2.086;
                t[21]=2.080; t[22]=2.074; t[23]=2.069; t[24]=2.064; t[25]=2.060;
            }
            { sum += $1; sumsq += $1*$1; count++ }
            END {
                mean = sum / count;
                variance = (sumsq - (sum*sum/count)) / (count - 1);
                stderr = sqrt(variance > 0 ? variance : 0) / sqrt(count);
                t_val = (count <= 25) ? t[count] : 1.96;
                rel_error = (t_val * stderr) / mean;
                if (rel_error <= 0.01) print "done"; else print "fail";
            }")
            [[ "$CONV" == "done" ]] && continue
        fi

        export OMP_NUM_THREADS=$cores
        run_nr=$((CURRENT_COUNT + 1))

        echo -n "[$(date +%H:%M:%S)] $matrix | Cores: $cores | Run: $run_nr ... "

        FULL_MATRIX_PATH="$MATRIX_DIR/$matrix"
        CPU_RANGE="0-$((cores-1))"

        PERF_RAW=$( { ~/perf_for_vm stat -x ',' \
            -e duration_time,instructions,cycles,cache-misses,dTLB-load-misses \
            -- taskset -c $CPU_RANGE \
            "$BINARY" "$FULL_MATRIX_PATH" "$iter" 1> "$TMP_OUT"; } 2>&1 )

        OUT_Intern_Runtime=$(grep "EXTRA_DATA" "$TMP_OUT" | cut -d',' -f2)
        OUT_Intern_Gflops=$(grep "EXTRA_DATA" "$TMP_OUT" | cut -d',' -f3)
        
        OUT_Perf_DurationTime=$(echo "$PERF_RAW" | grep "duration_time" | cut -d',' -f1 | head -n1)
        OUT_Perf_Instructions=$(echo "$PERF_RAW" | grep "instructions" | cut -d',' -f1 | head -n1)
        OUT_Perf_Cycles=$(echo "$PERF_RAW" | grep "cycles" | cut -d',' -f1 | head -n1)
        OUT_Perf_CacheMisses=$(echo "$PERF_RAW" | grep "cache-misses" | cut -d',' -f1 | head -n1)
        OUT_Perf_dTLBLoadMisses=$(echo "$PERF_RAW" | grep "dTLB-load-misses" | cut -d',' -f1 | head -n1)

        # In CSV schreiben
        echo "$matrix,$cores,$run_nr,$iter,$OUT_Intern_Runtime,$OUT_Intern_Gflops,$OUT_Perf_DurationTime,$OUT_Perf_Instructions,$OUT_Perf_Cycles,$OUT_Perf_CacheMisses,$OUT_Perf_dTLBLoadMisses" >> "$CSV"
        sync "$CSV"
        echo "done."

    done < "$PLAN"
done

rm -f "$TMP_OUT" series_check.tmp
echo "Benchmark done."