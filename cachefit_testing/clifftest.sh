#!/bin/bash

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTDIR="./outputs/spmv_$TIMESTAMP"
mkdir -p "$OUTDIR"
CSV="$OUTDIR/summary.csv"

export OMP_PROC_BIND=true
export OMP_PLACES=cores
export OMP_NUM_THREADS=1

echo "N,Run,Runtime_s,L3_Hit,L3_Miss,Clks,Inst" > "$CSV"

RUNS=5
ITER=500

for file in $(ls ./matrices/*.bin | sort -V); do
    N=$(basename "$file" | sed 's/[^0-9]*//g')
    
    echo "Processing N=$N..."
    
    for i in $(seq 1 $RUNS); do
        TMP_OUT="$OUTDIR/tmp.out"
        
        likwid-perfctr -C 0 -g L3_LOOKUP_STATE_HIT:CPMC0,L3_LOOKUP_STATE_MISS:CPMC1,CPU_CLOCKS_UNHALTED:PMC0,RETIRED_INSTRUCTIONS:PMC1 -o "$TMP_OUT" -m ../build/spmv_likwid "$file" $ITER
        
        RT=$(grep "RDTSC Runtime \[s\]" "$TMP_OUT" | cut -d, -f2)
        HIT=$(grep "L3_LOOKUP_STATE_HIT" "$TMP_OUT" | cut -d, -f3)
        MISS=$(grep "L3_LOOKUP_STATE_MISS" "$TMP_OUT" | cut -d, -f3)
        CLK=$(grep "CPU_CLOCKS_UNHALTED" "$TMP_OUT" | cut -d, -f3)
        INST=$(grep "RETIRED_INSTRUCTIONS" "$TMP_OUT" | cut -d, -f3)
        
        echo "$N,$i,$RT,$HIT,$MISS,$CLK,$INST" >> "$CSV"
        
        mv "$TMP_OUT" "$OUTDIR/spmv_N${N}_run${i}.out"
    done
done

echo "Fertig! Alles steht in $CSV"