#!/bin/bash

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTDIR="./outputs/spmv_comparison_$TIMESTAMP"
mkdir -p "$OUTDIR"
CSV="$OUTDIR/summary.csv"

export OMP_PROC_BIND=true
export OMP_PLACES=cores
export OMP_NUM_THREADS=1

echo "N,Randomness,Run,Runtime_s,L2_PF_Hit_L3,L2_PF_Miss_L3,Clks,Inst" > "$CSV"

RUNS=5
ITER=250

files=$(find ./matrices -name "*.bin" | sort -V)

for file in $files; do
    BASE=$(basename "$file")
    RAND=$(echo "$BASE" | cut -d'_' -f1 | sed 's/-/\./')
    N=$(echo "$BASE" | sed 's/.*_N\([0-9]*\).*/\1/')
    
    echo "[$(date +%H:%M:%S)] Processing: $BASE (N=$N, R=$RAND)" 
    
    for i in $(seq 1 $RUNS); do
        TMP_OUT="likwid_temp_$TIMESTAMP.out"
        
        likwid-perfctr -C 0 -g L2_PF_HIT_IN_L3:PMC2,L2_PF_MISS_IN_L3:PMC3,CPU_CLOCKS_UNHALTED:PMC0,RETIRED_INSTRUCTIONS:PMC1 -o "$TMP_OUT" -m ../build/spmv_likwid "$file" $ITER > /dev/null 2>&1
        
        RT=$(grep "RDTSC Runtime \[s\]" "$TMP_OUT" | cut -d, -f2)
        HIT=$(grep "L2_PF_HIT_IN_L3" "$TMP_OUT" | cut -d, -f3)
        MISS=$(grep "L2_PF_MISS_IN_L3" "$TMP_OUT" | cut -d, -f3)
        CLK=$(grep "CPU_CLOCKS_UNHALTED" "$TMP_OUT" | cut -d, -f3)
        INST=$(grep "RETIRED_INSTRUCTIONS" "$TMP_OUT" | cut -d, -f3)
        
        echo "$N,$RAND,$i,$RT,$HIT,$MISS,$CLK,$INST" >> "$CSV"
        
        rm -f "$TMP_OUT"
    done
done

echo "Fertig! Ergebnisse in: $CSV."