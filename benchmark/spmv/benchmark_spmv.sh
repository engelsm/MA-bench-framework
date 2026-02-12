#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --time=06:00:00
#SBATCH --exclusive

EXISTING_DIR=""

if [ -n "$EXISTING_DIR" ] && [ -d "$EXISTING_DIR" ]; then
    OUTDIR="$EXISTING_DIR"
else
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    OUTDIR="../../outputs/spmv/$TIMESTAMP"
    mkdir -p "$OUTDIR"
fi

CSV="$OUTDIR/summary_final.csv"
TMP_OUT="$OUTDIR/tmp_output.txt"
PLAN="bench_plan.csv"
MATRIX_DIR="../../matrices/itertest"

[ ! -f "$CSV" ] && echo "Matrix,Cores,NUMA,Run,Iterations,Runtime,Gflops,Insn,Cycl,RefCycl,Cache_Miss,Stalls,PgFault" > "$CSV"

check_convergence() {
    local m=$1 c=$2 p=$3
    local tmp_file="$OUTDIR/series_check.tmp"
    
    grep "^${m},${c},${p}," "$CSV" > "$tmp_file"
    
    local n=$(wc -l < "$tmp_file")
    if [ "$n" -lt 5 ]; then 
        echo "fail"
        rm -f "$tmp_file"
        return
    fi

    awk -F, '
    BEGIN { 
        t[5]=2.776; t[6]=2.571; t[7]=2.447; t[8]=2.365; t[9]=2.306; t[10]=2.262; 
        t[11]=2.228; t[12]=2.201; t[13]=2.179; t[14]=2.160; t[15]=2.145;
        t[16]=2.131; t[17]=2.120; t[18]=2.110; t[19]=2.101; t[20]=2.086;
        t[21]=2.080; t[22]=2.074; t[23]=2.069; t[24]=2.064; t[25]=2.060;
    }
    { sum += $7; sumsq += $7*$7; count++ }
    END {
        if (count < 5) { print "fail"; exit }
        mean = sum / count; if (mean == 0) { print "fail"; exit }
        variance = (sumsq - (sum*sum/count)) / (count - 1);
        std = sqrt(variance > 0 ? variance : 0);
        stderr = std / sqrt(count);
        
        # After 25 use default value
        t_val = (count <= 25) ? t[count] : 1.96;
        
        rel_error = (t_val * stderr) / mean;
        if (rel_error <= 0.01) printf "%.4f", rel_error; else print "fail";
    }' "$tmp_file"
    
    rm -f "$tmp_file"
}

MAX_RUNS=25
MIN_RUNS=5
CORE_OFFSET=0
NUMA_NODES=0,1
export OMP_PROC_BIND=close
export OMP_PLACES=cores

echo "Starting Benchmarking... Output: $CSV"

for (( run_idx=1; run_idx<=MAX_RUNS; run_idx++ )); do
    echo "=== ROUND $run_idx ==="

    while IFS=, read -r raw_matrix raw_cores raw_mem raw_iter || [ -n "$raw_matrix" ]; do
        # Cleanup (removes \r, trailing whitespace) MANDATORY!!
        matrix=$(echo "$raw_matrix" | tr -d '\r' | xargs)
        cores=$(echo "$raw_cores" | tr -d '\r' | xargs)
        mem_policy=$(echo "$raw_mem" | tr -d '\r' | xargs)
        iter=$(echo "$raw_iter" | tr -d '\r' | xargs)

        # Skip Header or Empty Lines
        [[ "$matrix" == "Matrix" || -z "$matrix" ]] && continue

        # NUMA Fix (Can probably be removed)
        FINAL_MODE="$mem_policy"
        if [[ "$mem_policy" == "interleave" && "$cores" -le 24 ]]; then FINAL_MODE="localalloc"; fi

        # Check runs for this config
        CURRENT_COUNT=$(grep -c "^${matrix},${cores},${FINAL_MODE}," "$CSV" | awk '{print $1}')
        : ${CURRENT_COUNT:=0} # Fallback to 0

        # Skip if there are already enough runs or if convergence is reached
        if (( CURRENT_COUNT >= MAX_RUNS )); then continue; fi
        if (( CURRENT_COUNT >= MIN_RUNS )); then
            CONV=$(check_convergence "$matrix" "$cores" "$FINAL_MODE")
            [[ "$CONV" != "fail" ]] && continue
        fi
        if (( run_idx <= CURRENT_COUNT )); then continue; fi

        export OMP_NUM_THREADS=$cores
        CPUS=$CORE_OFFSET"-$((CORE_OFFSET + cores - 1))"
        if [[ "$mem_policy" == "interleave" ]]; then
            NUMA_CMD="numactl -C $CPUS --interleave=$NUMA_NODES"
        else
            NUMA_CMD="numactl -C $CPUS --membind=$NUMA_NODES"
        fi

        echo -n "[$(date +%H:%M:%S)] $matrix | Cores: $cores | $FINAL_MODE | Run: $((CURRENT_COUNT+1)) ... "

        if [ ! -f "$MATRIX_DIR/$matrix" ]; then echo "MISSING"; continue; fi

        PERF_RAW=$( { perf stat -x ',' \
            -e instructions:u,cycles:u,ref-cycles:u,cache-misses:u,stalled-cycles-frontend:u,page-faults \
            $NUMA_CMD ../../build/spmv "$MATRIX_DIR/$matrix" "$iter" 1> "$TMP_OUT"; } 2>&1 )

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