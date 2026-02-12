#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --time=08:00:00
#SBATCH --exclusive

EXISTING_DIR=""
if [ -n "$EXISTING_DIR" ] && [ -d "$EXISTING_DIR" ]; then
    OUTDIR="$EXISTING_DIR"
else
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    OUTDIR="../../outputs/krylov/$TIMESTAMP"
    mkdir -p "$OUTDIR"
fi

CSV="$OUTDIR/summary_krylov.csv"
TMP_OUT="$OUTDIR/tmp_output.txt"
PLAN="bench_plan.csv"
MATRIX_DIR="../../matrices/binary_spmc"

[ ! -f "$CSV" ] && echo "Algo,Matrix,Cores,NUMA,Run,Arg1,Arg2,Arg3,SpMVTime,MgmtTime,N_Ops,Insn,Cycl,RefCycl,Cache_Miss,Stalls,PgFault" > "$CSV"

MIN_RUNS=5
MAX_RUNS=25
CORE_OFFSET=0 #0 for 0-47, 48 for 48-95
NUMA_NODES=0,1
export OMP_PROC_BIND=close #no thread migration
export OMP_PLACES=cores #no hyperthreading

check_convergence() {
    local m=$1 c=$2 p=$3 algo=$4
    local tmp_file="$OUTDIR/series_check.tmp"
    
    grep "^${algo},${m},${c},${p}," "$CSV" > "$tmp_file"
    
    local n=$(wc -l < "$tmp_file")
    if [ "$n" -lt 5 ]; then echo "fail"; rm -f "$tmp_file"; return; fi

    awk -F, '
    BEGIN {
        t[5]=2.776; t[6]=2.571; t[7]=2.447; t[8]=2.365; t[9]=2.306;
        t[10]=2.262; t[11]=2.228; t[12]=2.201; t[13]=2.179; t[14]=2.160;
        t[15]=2.145; t[16]=2.131; t[17]=2.120; t[18]=2.110; t[19]=2.101;
        t[20]=2.093; t[21]=2.086; t[22]=2.080; t[23]=2.074; t[24]=2.069;
        t[25]=2.064;
    }
    { 
        total_time = $9 + $10; 
        sum += total_time; 
        sumsq += total_time * total_time; 
        count++; 
    }
    END {
        if (count < 5) { print "fail"; exit; }
        mean = sum / count; if (mean == 0) { print "fail"; exit; }
        variance = (sumsq - (sum*sum/count)) / (count - 1);
        std = sqrt(variance > 0 ? variance : 0);
        stderr = std / sqrt(count);
        t_val = (count <= 25) ? t[count] : 1.96;
        if (!t_val) t_val = 2.0; 
        rel_error = (t_val * stderr) / mean;
        if (rel_error <= 0.01) printf "%.4f", rel_error; else print "fail";
    }' "$tmp_file"
    rm -f "$tmp_file"
}

echo "Starting Krylov Benchmarking... Plan: $PLAN, Output: $CSV, Cores: $CORE_OFFSET to $((CORE_OFFSET + 47)), NUMA Nodes: $NUMA_NODES"

for (( run_idx=1; run_idx<=MAX_RUNS; run_idx++ )); do
    echo "=== ROUND $run_idx ==="

    while IFS=, read -r raw_algo raw_matrix raw_cores raw_mem raw_arg1 raw_arg2 raw_arg3 || [ -n "$raw_algo" ]; do
        
        algo=$(echo "$raw_algo" | tr -d '\r' | xargs)
        matrix=$(echo "$raw_matrix" | tr -d '\r' | xargs)
        cores=$(echo "$raw_cores" | tr -d '\r' | xargs)
        mem_policy=$(echo "$raw_mem" | tr -d '\r' | xargs)
        arg1=$(echo "$raw_arg1" | tr -d '\r' | xargs)
        arg2=$(echo "$raw_arg2" | tr -d '\r' | xargs)
        arg3=$(echo "$raw_arg3" | tr -d '\r' | xargs)

        [[ "$algo" == "Algo" || -z "$algo" ]] && continue

        CURRENT_COUNT=$(grep -c "^${algo},${matrix},${cores},${mem_policy}," "$CSV")
        if (( CURRENT_COUNT >= MAX_RUNS )); then continue; fi
        if (( CURRENT_COUNT >= MIN_RUNS )); then
            CONV=$(check_convergence "$matrix" "$cores" "$mem_policy" "$algo")
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

        echo -n "[$(date +%H:%M:%S)] $algo | $matrix | C: $cores | $mem_policy | Run: $((CURRENT_COUNT+1)) ... "

        if [ ! -f "$MATRIX_DIR/$matrix" ]; then echo "MISSING FILE: $MATRIX_DIR/$matrix"; continue; fi

        PERF_RAW=$( { perf stat -x ',' \
            -e instructions:u,cycles:u,ref-cycles:u,cache-misses:u,stalled-cycles-frontend:u,page-faults \
            $NUMA_CMD ../../build/solve "$MATRIX_DIR/$matrix" "$algo" "$arg1" "$arg2" "$arg3" 1> "$TMP_OUT"; } 2>&1 )

        T_SPMV=$(grep "EXTRA_DATA" "$TMP_OUT" | cut -d',' -f2)
        T_MGMT=$(grep "EXTRA_DATA" "$TMP_OUT" | cut -d',' -f3)
        N_OPS=$(grep "EXTRA_DATA" "$TMP_OUT" | cut -d',' -f4)

        INST=$(echo "$PERF_RAW" | grep "instructions:u" | cut -d',' -f1 | head -n1)
        CYCL=$(echo "$PERF_RAW" | grep "cycles:u" | grep -v "ref" | cut -d',' -f1 | head -n1)
        REFC=$(echo "$PERF_RAW" | grep "ref-cycles:u" | cut -d',' -f1 | head -n1)
        CMIS=$(echo "$PERF_RAW" | grep "cache-misses:u" | cut -d',' -f1 | head -n1)
        STAL=$(echo "$PERF_RAW" | grep "stalled-cycles-frontend:u" | cut -d',' -f1 | head -n1)
        FAUL=$(echo "$PERF_RAW" | grep "page-faults" | cut -d',' -f1 | head -n1)

        echo "$algo,$matrix,$cores,$mem_policy,$((CURRENT_COUNT+1)),$arg1,$arg2,$arg3,$T_SPMV,$T_MGMT,$N_OPS,$INST,$CYCL,$REFC,$CMIS,$STAL,$FAUL" >> "$CSV"
        sync "$CSV"
        echo "done."
        sleep 0.1

    done < "$PLAN"
done
rm -f "$TMP_OUT"