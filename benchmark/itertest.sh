#!/bin/bash

MATRIX_DIR="../matrices/itertest"
TEST_FILES=($(ls $MATRIX_DIR/*.bin))
OUT="itertest.csv"

# Guessed iterations
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

echo "Matrix,Cores,MemoryPolicy,Iterations,Runtime,Gflops" > "$OUT"

for file in "${TEST_FILES[@]}"; do
    [ -f "$file" ] || continue
    BASE=$(basename "$file")

    echo "Starting measurement: $BASE"

    for c in "${CORES[@]}"; do
        ITER=${CORE_ITERATIONS[$c]}
        
        export OMP_NUM_THREADS=$c
        export OMP_PROC_BIND=close
        
        if [ "$c" -eq 1 ]; then
        #0 is polluted sometimes
            CPUS="1"
        else
            CPUS="0-$((c - 1))"
        fi

        if [ "$c" -ge 32 ]; then
            MEM_STR="interleave"
            MEM_POLICY="--interleave=0,1"
        else
            MEM_STR="localalloc"
            MEM_POLICY="--localalloc"
        fi

        echo "  -> Cores: $c ($MEM_STR) | Iter: $ITER | CPUs: $CPUS"
        
        RES=$(numactl -C $CPUS $MEM_POLICY ../build/spmv "$file" "$ITER" | grep "EXTRA_DATA")
        
        if [[ -z "$RES" ]]; then
            echo "No output for $BASE with $c cores. Skipping."
            continue
        fi

        T=$(echo "$RES" | cut -d',' -f2)
        G=$(echo "$RES" | cut -d',' -f3)

        echo "$BASE,$c,$MEM_STR,$ITER,$T,$G" >> "$OUT"
        echo "      Gflops: $G | Zeit: $T s"
    done
done

echo "----------------------------------------"
echo "Done. Results saved in $OUT"