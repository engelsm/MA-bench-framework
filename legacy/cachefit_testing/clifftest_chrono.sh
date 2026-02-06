#!/bin/bash

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTDIR="./outputs/spmv_comparison_$TIMESTAMP"
mkdir -p "$OUTDIR"
CSV="$OUTDIR/summary.csv"
echo $CSV
TMP_OUT="$OUTDIR/tmp_output.txt"

export OMP_PROC_BIND=true
export OMP_PLACES=cores
export OMP_NUM_THREADS=1

echo "N,Randomness,Run,File,Iterations,Runtime,Gflops" > "$CSV"

RUNS=5
ITERATIONS=500
NUMA_CMD="numactl -C 0 -m 0" 

files=$(find ./matrices -name "*.bin" | sort -V)

for file in $files; do
    BASE=$(basename "$file")
    RAND=$(echo "$BASE" | cut -d'_' -f1 | sed 's/-/\./')
    N=$(echo "$BASE" | sed 's/.*_N\([0-9]*\).*/\1/')
    
    echo "[$(date +%H:%M:%S)] Processing: $BASE" 
    
    for i in $(seq 1 $RUNS); do
        $NUMA_CMD ../build/spmv "$file" "$ITERATIONS" > "$TMP_OUT"

        EXTRA_LINE=$(grep "EXTRA_DATA" "$TMP_OUT")
        
        T_SPMV=$(echo "$EXTRA_LINE" | cut -d',' -f2)
        GFLOPS=$(echo "$EXTRA_LINE" | cut -d',' -f3)

        echo "$N,$RAND,$i,$BASE,$ITERATIONS,$T_SPMV,$GFLOPS" >> "$CSV"
        
        echo "Run $i: $T_SPMV s, $GFLOPS GFLOPS"
    done
done

rm -f "$TMP_OUT"

echo "Fertig! Ergebnisse in: $CSV."