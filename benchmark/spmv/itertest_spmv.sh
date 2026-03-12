#!/bin/bash

MATRIX_DIR="/home/mengelsl/MA-bench-framework/matrices/spmv"
TEST_FILES=($(ls $MATRIX_DIR/*.bin))
OUT="itertest_72.csv"

export OMP_PROC_BIND=close
export OMP_PLACES=cores

N_VALUES=(28807 201649 432105 1008246 2880703 8642110 17284220)

declare -A BASE_ITERS
BASE_ITERS=(
    [28807]=1000
    [201649]=400
    [432105]=150
    [1008246]=80
    [2880703]=30
    [8642110]=10
    [17284220]=5
)

CORES=(72)

echo "Matrix,Cores,Iterations,Runtime" > "$OUT"

for file in "${TEST_FILES[@]}"; do
    file_basename=$(basename "$file")

    N=$(echo "$file_basename" | grep -oP 'N\K\d+')
    B_ITER=${BASE_ITERS[$N]}
    
    echo "Starting measurement: $file_basename (N=$N, BaseIter=$B_ITER)"

    for c in "${CORES[@]}"; do
        ITER=$(( B_ITER * ((c+1)/2) ))
        export OMP_NUM_THREADS=$c
        
        echo "-Threads: $c | Iter: $ITER"
        
        RES=$(taskset -c 0-$((c-1)) /home/mengelsl/MA-bench-framework/build/spmv "$file" "$ITER" | grep "EXTRA_DATA")

        T=$(echo "$RES" | cut -d',' -f2)

        echo "$file_basename,$c,$ITER,$T" >> "$OUT"
        echo "Time: $T s"
    done
done

echo "Done. Results saved in $OUT"