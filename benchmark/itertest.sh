#!/bin/bash

MATRIX_DIR="../matrices/itertest"
TEST_FILES=($(ls $MATRIX_DIR/*.bin))
OUT="itertest.csv"

# 1. Iterationen pro Core-Zahl
declare -A CORE_ITERATIONS
CORE_ITERATIONS=(
    [1]=30
    [4]=120
    [8]=150
    [16]=200
    [24]=300
    [32]=350
    [48]=400
)

CORES=(1 4 8 16 24 32 48)

# Header: MemoryPolicy jetzt hinter Cores
echo "Matrix,Cores,MemoryPolicy,Iterations,Runtime,Gflops" > "$OUT"

for file in "${TEST_FILES[@]}"; do
    [ -f "$file" ] || continue
    BASE=$(basename "$file")

    echo "Starte Messung für: $BASE"

    for c in "${CORES[@]}"; do
        ITER=${CORE_ITERATIONS[$c]}
        
        export OMP_NUM_THREADS=$c
        export OMP_PROC_BIND=close
        
        # CPU Binding
        if [ "$c" -eq 1 ]; then
            CPUS="1"
        else
            CPUS="0-$((c - 1))"
        fi

        # NUMA Memory Policy: Interleave ab 32 Cores, sonst Local
        if [ "$c" -ge 32 ]; then
            MEM_STR="interleave"
            MEM_POLICY="--interleave=0,1"
        else
            MEM_STR="localalloc"
            MEM_POLICY="--localalloc"
        fi

        echo "  -> Cores: $c ($MEM_STR) | Iter: $ITER | CPUs: $CPUS"
        
        # Benchmark Aufruf
        RES=$(numactl -C $CPUS $MEM_POLICY ../build/spmv "$file" "$ITER" | grep "EXTRA_DATA")
        
        if [[ -z "$RES" ]]; then
            echo "      !! FEHLER: Kein Output bei $BASE"
            continue
        fi

        T=$(echo "$RES" | cut -d',' -f2)
        G=$(echo "$RES" | cut -d',' -f3)

        echo "$BASE,$c,$MEM_STR,$ITER,$T,$G" >> "$OUT"
        echo "      Gflops: $G | Zeit: $T s"
    done
done

echo "----------------------------------------"
echo "Fertig! Ergebnisse liegen in $OUT"