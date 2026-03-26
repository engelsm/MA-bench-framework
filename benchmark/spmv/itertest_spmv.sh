#!/bin/bash

ml tools/numactl/2.0.19-GCCcore-14.2.0

MATRIX_DIR="/home/mengelsl/MA-bench-framework/matrices/spmv"
TEST_FILES=($(ls $MATRIX_DIR/*.bin))
OUT="itertest.csv"

BINARY="/home/mengelsl/MA-bench-framework/build/spmv"

export OMP_PROC_BIND=close
export OMP_PLACES=cores

N_VALUES=(28807 201649 432105 1440352 8642110)

declare -A BASE_ITERS
BASE_ITERS=(
    [28807]=1000
    [201649]=400
    [432105]=150
    [1440352]=50
    [8642110]=10
)

CORES=(1 8 24 48)

echo "Matrix,Cores,NUMA_Policy,Iterations,Runtime" > "$OUT"

for file in "${TEST_FILES[@]}"; do
    file_basename=$(basename "$file")

    N=$(echo "$file_basename" | grep -oP 'N\K\d+')
    B_ITER=${BASE_ITERS[$N]}
    
    echo "Starting measurement: $file_basename (N=$N, BaseIter=$B_ITER)"

    for c in "${CORES[@]}"; do
        ITER=$(( B_ITER * ((c+1)/2) ))

        POLICIES=("membind" "interleave")
        for pol in "${POLICIES[@]}"; do
            echo "-Threads: $c | Iter: $ITER | Policy: $pol"
            
            if [ "$c" -le 24 ]; then
                TARGET_NODE=0
            else
                TARGET_NODE=0,1
            fi

            if [ "$pol" == "membind" ]; then
                NUMA_FLAG="--membind=$TARGET_NODE"
            else
                NUMA_FLAG="--interleave=0,1"
            fi

            RES=$(setarch $(uname -m) -R numactl -C 0-$((c-1)) $NUMA_FLAG $BINARY "$file" "$ITER" 0 0 $c $pol --cout)

            T=$(echo "$RES" | cut -d',' -f7)

            echo "$file_basename,$c,$pol,$ITER,$T" >> "$OUT"
            echo "Time: $T s"
        done
    done
done

echo "Done. Results saved in $OUT"