#!/bin/bash

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTDIR="./outputs/spmv_comparison_$TIMESTAMP"
mkdir -p "$OUTDIR"
CSV="$OUTDIR/summary.csv"


# 2. Thread-Pinning (Sehr wichtig für SpmV Performance)
export OMP_PROC_BIND=true
export OMP_PLACES=cores
export OMP_NUM_THREADS=1

# CSV Header (Achte auf die korrekten Spalten für dein Python-Skript)
echo "N,Randomness,Run,File,Iterations,Runtime_ns,Instructions,Cycles,Cache_Misses,Cache_Refs,L1_Loads,Task_Clock" > "$CSV"

RUNS=5
ITERATIONS=1000
# -C 0 bindet an Core 0. Stelle sicher, dass der RAM lokal ist!
NUMA_CMD="numactl -C 0 -m 0" 

files=$(find ./matrices -name "*.bin" | sort -V)

for file in $files; do
    BASE=$(basename "$file")
    RAND=$(echo "$BASE" | cut -d'_' -f1 | sed 's/-/\./')
    N=$(echo "$BASE" | sed 's/.*_N\([0-9]*\).*/\1/')
    
    echo "[$(date +%H:%M:%S)] Processing: $BASE" 
    
    for i in $(seq 1 $RUNS); do
        # WICHTIG: Alle Events im -e Block müssen mit den Variablen unten übereinstimmen!
        # Wir messen hier die stabilsten VM-Events.
        PERF_RAW=$( { perf stat -x ',' \
            -e duration_time,instructions,cycles,cache-misses,cache-references,L1-dcache-loads,task-clock \
            $NUMA_CMD ../build/spmv "$file" "$ITERATIONS" \
            1> /dev/null; } 2>&1 )

        # Extraktion (Achte auf exakte Strings von perf)
        REAL=$(echo "$PERF_RAW" | grep "duration_time" | cut -d',' -f1)
        INST=$(echo "$PERF_RAW" | grep "instructions" | cut -d',' -f1)
        CYCL=$(echo "$PERF_RAW" | grep "cycles" | cut -d',' -f1)
        CMIS=$(echo "$PERF_RAW" | grep "cache-misses" | cut -d',' -f1)
        CREF=$(echo "$PERF_RAW" | grep "cache-references" | cut -d',' -f1)
        L1LD=$(echo "$PERF_RAW" | grep "L1-dcache-loads" | cut -d',' -f1)
        TASK=$(echo "$PERF_RAW" | grep "task-clock" | cut -d',' -f1)

        echo "$N,$RAND,$i,$BASE,$ITERATIONS,$REAL,$INST,$CYCL,$CMIS,$CREF,$L1LD,$TASK" >> "$CSV"
    done
done

echo "Fertig! Ergebnisse in: $CSV."