#!/bin/bash

MATRIX_DIR="../../matrices/itertest2"
TEST_FILES=($(ls $MATRIX_DIR/*.bin))
OUT="itertest_spmv10.csv"

export OMP_PROC_BIND=close
export OMP_PLACES=cores

declare -A BASE_ITERS
BASE_ITERS=(
    [28800]=5000
    [57600]=2500
    [115000]=1250
    [230000]=500
    [518000]=250
    [864000]=125
    [2200000]=40
    [5500000]=15
)

CORES=(1 4 8 16 24 32 48)

echo "Matrix,Cores,MemoryPolicy,Iterations,Runtime,Gflops" > "$OUT"

for file in "${TEST_FILES[@]}"; do
    [ -f "$file" ] || continue
    file_basename=$(basename "$file")

    N=$(echo "$file_basename" | grep -oP 'N\K\d+')
    B_ITER=${BASE_ITERS[$N]}
    
    if [ -z "$B_ITER" ]; then B_ITER=10; fi

    echo "Starting measurement: $file_basename (N=$N, BaseIter=$B_ITER)"

    for c in "${CORES[@]}"; do
        ITER=$(( B_ITER * c ))
        
        export OMP_NUM_THREADS=$c
        
        CPUS="0-$((c - 1))"

        if [ "$c" -ge 32 ]; then
            MEM_STR="interleave"
            MEM_POLICY="--interleave=0,1"
        else
            MEM_STR="localalloc"
            MEM_POLICY="--localalloc"
        fi

        echo "  -> Cores: $c ($MEM_STR) | Iter: $ITER"
        
        RES=$(numactl -C $CPUS $MEM_POLICY ../../build/spmv "$file" "$ITER" | grep "EXTRA_DATA")
        
        if [[ -z "$RES" ]]; then
            echo "    No output. Skipping."
            continue
        fi

        T=$(echo "$RES" | cut -d',' -f2)
        G=$(echo "$RES" | cut -d',' -f3)

        echo "$file_basename,$c,$MEM_STR,$ITER,$T,$G" >> "$OUT"
        echo "     Gflops: $G | Zeit: $T s"
    done
done

echo "----------------------------------------"
echo "Done. Results saved in $OUT"