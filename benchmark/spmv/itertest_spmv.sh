#!/bin/bash

MATRIX_DIR="/home/mengelsl/MA-bench-framework/matrices/spmv_synth"
TEST_FILES=($(ls $MATRIX_DIR/*.bin))
OUT="itertest_spmv5.csv"

export OMP_PROC_BIND=close
export OMP_PLACES=cores

N_VALUES=(28800 230000 432000 979200 2880000 14400000)
declare -A BASE_ITERS
BASE_ITERS=(
    [28800]=1000
    [230000]=400
    [432000]=150
    [979200]=80
    [2880000]=40
    [14400000]=10
)

CORES=(1 4 8 24 48 96)

echo "Matrix,Cores,Iterations,Runtime,Gflops" > "$OUT"

for file in "${TEST_FILES[@]}"; do
    file_basename=$(basename "$file")

    N=$(echo "$file_basename" | grep -oP 'N\K\d+')
    B_ITER=${BASE_ITERS[$N]}
    
    echo "Starting measurement: $file_basename (N=$N, BaseIter=$B_ITER)"

    for c in "${CORES[@]}"; do
        ITER=$(( B_ITER * ((c+1)/2) ))
        export OMP_NUM_THREADS=$c
        
        echo "-Threads: $c | Iter: $ITER"
        
        RES=$(/home/mengelsl/MA-bench-framework/build/spmv "$file" "$ITER" | grep "EXTRA_DATA")

        T=$(echo "$RES" | cut -d',' -f2)

        echo "$file_basename,$c,$ITER,$T" >> "$OUT"
        echo "Time: $T s"
    done
done

echo "Done. Results saved in $OUT"