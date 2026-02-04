#!/bin/bash

MATRIX_DIR="./matrices/itertest"

TEST_FILES=($(ls $MATRIX_DIR/*.bin))

CORES=(1 4 8 16 24 32 48)

ITER=100
OUT="matrix_scaling_simple.csv"

echo "Matrix,Cores,Iterations,Runtime,Gflops" > "$OUT"

for file in "${TEST_FILES[@]}"; do
    [ -f "$file" ] || continue
    BASE=$(basename "$file")

    echo "Starte Messung für: $BASE"

    for c in "${CORES[@]}"; do
        export OMP_NUM_THREADS=$c
        export OMP_PROC_BIND=close
        
        if [ "$c" -eq 1 ]; then
            CPUS="0"
        else
            CPUS="0-$((c - 1))"
        fi

        echo "  -> Cores: $c (CPUs: $CPUS)"
        
        RES=$(numactl -C $CPUS ../build/spmv "$file" "$ITER" | grep "EXTRA_DATA")
        
        if [[ -z "$RES" ]]; then
            echo "     !! FEHLER: Kein Output bei $BASE"
            continue
        fi

        T=$(echo "$RES" | cut -d',' -f2)
        G=$(echo "$RES" | cut -d',' -f3)

        echo "$BASE,$c,$ITER,$T,$G" >> "$OUT"
        echo "     Gflops: $G | Zeit: $T s"
    done
done

echo "----------------------------------------"
echo "Fertig! Ergebnisse liegen in $OUT"