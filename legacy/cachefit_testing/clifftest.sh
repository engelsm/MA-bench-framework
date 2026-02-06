#!/bin/bash

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTDIR="./outputs/spmv_comparison_$TIMESTAMP"
mkdir -p "$OUTDIR"
CSV="$OUTDIR/summary.csv"

export OMP_PROC_BIND=true
export OMP_PLACES=cores
export OMP_NUM_THREADS=1

# Header schreiben
echo "N,Randomness,Run,Runtime_s,L3_Hit,L3_Miss,Clks,Inst" > "$CSV"

RUNS=5
ITER=250

# Alle Bin-Dateien im Ordner suchen
SEARCH_PATH="./matrices/*.bin"

for file in $(ls $SEARCH_PATH | sort -V); do
    BASE=$(basename "$file")
    
    # Extrahiere Randomness und N aus dem Dateinamen
    RAND=$(echo "$BASE" | cut -d'_' -f1)
    N=$(echo "$BASE" | sed 's/.*_N\([0-9]*\).*/\1/')
    
    echo "Processing Matrix: N=$N, Randomness=$RAND..."
    
    for i in $(seq 1 $RUNS); do
        # Temporäre Datei im aktuellen Verzeichnis (wird gleich wieder gelöscht)
        TMP_OUT="likwid_temp.out"
        
        # LIKWID Aufruf
        likwid-perfctr -C 0 -g L3_LOOKUP_STATE_HIT:CPMC0,L3_LOOKUP_STATE_MISS:CPMC1,CPU_CLOCKS_UNHALTED:PMC0,RETIRED_INSTRUCTIONS:PMC1 -o "$TMP_OUT" -m ../build/spmv_likwid "$file" $ITER
        
        # Daten extrahieren
        RT=$(grep "RDTSC Runtime \[s\]" "$TMP_OUT" | cut -d, -f2)
        HIT=$(grep "L3_LOOKUP_STATE_HIT" "$TMP_OUT" | cut -d, -f3)
        MISS=$(grep "L3_LOOKUP_STATE_MISS" "$TMP_OUT" | cut -d, -f3)
        CLK=$(grep "CPU_CLOCKS_UNHALTED" "$TMP_OUT" | cut -d, -f3)
        INST=$(grep "RETIRED_INSTRUCTIONS" "$TMP_OUT" | cut -d, -f3)
        
        # Nur in CSV schreiben, wenn wir auch Daten erhalten haben
        if [[ -n "$RT" ]]; then
            echo "$N,$RAND,$i,$RT,$HIT,$MISS,$CLK,$INST" >> "$CSV"
        else
            echo "Warning: No data for $BASE Run $i"
        fi
        
        # Datei sofort löschen
        rm -f "$TMP_OUT"
    done
done

echo "Fertig! Einzige Ausgabedatei: $CSV"