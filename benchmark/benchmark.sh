#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --time=04:00:00
#SBATCH --exclusive

EXISTING_DIR=""

if [ -n "$EXISTING_DIR" ] && [ -d "$EXISTING_DIR" ]; then
    OUTDIR="$EXISTING_DIR"
else
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    OUTDIR="/home/mengelsl/MA-bench-framework/outputs/$TIMESTAMP"
    mkdir -p "$OUTDIR"
fi

CSV="$OUTDIR/summary_final.csv"
TMP_OUT="$OUTDIR/tmp_output.txt"
PLAN="bench_plan.csv"
MATRIX_DIR="../matrices/itertest"

[ ! -f "$CSV" ] && echo "Matrix,Cores,NUMA,Run,Iterations,Runtime,Gflops,Insn,Cycl,RefCycl,Cache_Miss,Stalls,PgFault" > "$CSV"

check_convergence() {
    local m=$1 c=$2 p=$3
    grep "^${m},${c},${p}," "$CSV" > series_check.tmp
    local n=$(wc -l < series_check.tmp)
    if [ "$n" -lt 5 ]; then echo "fail"; rm -f series_check.tmp; return; fi

    awk -F, '
    BEGIN { t[5]=2.776; t[6]=2.571; t[7]=2.447; t[8]=2.365; t[9]=2.306; t[10]=2.262; 
            t[11]=2.228; t[12]=2.201; t[13]=2.179; t[14]=2.160; t[15]=2.145; }
    { sum += $7; sumsq += $7*$7; count++ }
    END {
        if (count < 5) { print "fail"; exit }
        mean = sum / count; if (mean == 0) { print "fail"; exit }
        variance = (sumsq - (sum*sum/count)) / (count - 1);
        std = sqrt(variance > 0 ? variance : 0);
        stderr = std / sqrt(count);
        t_val = (count <= 15) ? t[count] : 1.96;
        rel_error = (t_val * stderr) / mean;
        if (rel_error <= 0.01) printf "%.4f", rel_error; else print "fail";
    }' series_check.tmp
    rm -f series_check.tmp
}

MAX_RUNS=20
MIN_RUNS=5
export OMP_PROC_BIND=close
export OMP_PLACES=cores

echo "Interleaved Round-Robin Benchmark gestartet..."

for (( run_idx=1; run_idx<=MAX_RUNS; run_idx++ )); do
    echo "=== RUNDE $run_idx ==="

    # Plan einlesen und Header überspringen
    while IFS=, read -r raw_matrix raw_cores raw_mem raw_iter || [ -n "$raw_matrix" ]; do
        # Cleanup (entfernt \r, führende/anhängende Leerzeichen) MANDATORY!!
        matrix=$(echo "$raw_matrix" | tr -d '\r' | xargs)
        cores=$(echo "$raw_cores" | tr -d '\r' | xargs)
        mem_policy=$(echo "$raw_mem" | tr -d '\r' | xargs)
        iter=$(echo "$raw_iter" | tr -d '\r' | xargs)

        # Header oder Leerzeilen skippen
        [[ "$matrix" == "Matrix" || -z "$matrix" ]] && continue

        # NUMA Fix
        FINAL_MODE="$mem_policy"
        if [[ "$mem_policy" == "interleave" && "$cores" -le 24 ]]; then FINAL_MODE="localalloc"; fi

        # Wir erzwingen, dass CURRENT_COUNT nur eine einzige Zahl ist
        CURRENT_COUNT=$(grep -c "^${matrix},${cores},${FINAL_MODE}," "$CSV" | awk '{print $1}')
        : ${CURRENT_COUNT:=0} # Fallback auf 0 falls leer

        # Skip Logik
        if (( CURRENT_COUNT >= MAX_RUNS )); then continue; fi
        if (( CURRENT_COUNT >= MIN_RUNS )); then
            CONV=$(check_convergence "$matrix" "$cores" "$FINAL_MODE")
            [[ "$CONV" != "fail" ]] && continue
        fi
        if (( run_idx <= CURRENT_COUNT )); then continue; fi

        # EXECUTION
        export OMP_NUM_THREADS=$cores
        #Core 0 is often polluted with OS tasks, so we start from 1 if we have more than 1 core
        if [ "$cores" -eq 1 ]; then CPUS="1"; else CPUS="0-$((cores - 1))"; fi
        NUMA_CMD="numactl -C $CPUS --$( [[ "$FINAL_MODE" == "interleave" ]] && echo "interleave=0,1" || echo "localalloc" )"

        echo -n "[$(date +%H:%M:%S)] $matrix | Cores: $cores | $FINAL_MODE | Run: $((CURRENT_COUNT+1)) ... "

        if [ ! -f "$MATRIX_DIR/$matrix" ]; then echo "MISSING"; continue; fi

        PERF_RAW=$( { perf stat -x ',' \
            -e instructions:u,cycles:u,ref-cycles:u,cache-misses:u,stalled-cycles-frontend:u,page-faults \
            $NUMA_CMD ../build/spmv "$MATRIX_DIR/$matrix" "$iter" 1> "$TMP_OUT"; } 2>&1 )

        # Parsing
        GFLOPS=$(grep "EXTRA_DATA" "$TMP_OUT" | cut -d',' -f3)
        T_SPMV=$(grep "EXTRA_DATA" "$TMP_OUT" | cut -d',' -f2)
        INST=$(echo "$PERF_RAW" | grep "instructions:u" | cut -d',' -f1 | head -n1)
        CYCL=$(echo "$PERF_RAW" | grep "cycles:u" | grep -v "ref" | cut -d',' -f1 | head -n1)
        REFC=$(echo "$PERF_RAW" | grep "ref-cycles:u" | cut -d',' -f1 | head -n1)
        CMIS=$(echo "$PERF_RAW" | grep "cache-misses:u" | cut -d',' -f1 | head -n1)
        STAL=$(echo "$PERF_RAW" | grep "stalled-cycles-frontend:u" | cut -d',' -f1 | head -n1)
        FAUL=$(echo "$PERF_RAW" | grep "page-faults" | cut -d',' -f1 | head -n1)

        echo "$matrix,$cores,$FINAL_MODE,$((CURRENT_COUNT+1)),$iter,$T_SPMV,$GFLOPS,$INST,$CYCL,$REFC,$CMIS,$STAL,$FAUL" >> "$CSV"
        sync "$CSV"
        echo "done."
        sleep 0.1

    done < "$PLAN"
done
rm -f "$TMP_OUT" series_check.tmp