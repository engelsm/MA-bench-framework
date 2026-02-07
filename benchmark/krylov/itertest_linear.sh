#!/bin/bash

MATRIX_DIR="../../matrices/itertest"
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
MODES=("cg" "bicgstab")

echo "Mode,Matrix,Cores,MemoryPolicy,Iterations,SpMV_Runtime,Total_Runtime,N_OPS" > "$OUT"

for mode in "${MODES[@]}"; do
    for file in "${TEST_FILES[@]}"; do
        [ -f "$file" ] || continue
        BASE=$(basename "$file")

        echo "Starting measurement: $BASE | Mode: $mode"

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

            echo "  -> Cores: $c ($MEM_STR) | Iter: $ITER | CPUs: $CPUS | Mode: $mode"
            
            RES=$(numactl -C $CPUS $MEM_POLICY ../../build/solve "$file" "$mode" "$ITER" | grep "EXTRA_DATA")
            
            if [[ -z "$RES" ]]; then
                echo "No output for $BASE with $c cores. Skipping."
                continue
            fi

            T_SPMV=$(echo "$RES" | cut -d',' -f2)
            T_MGMT=$(echo "$RES" | cut -d',' -f3)
            N_OPS=$(echo "$RES" | cut -d',' -f4)

            echo "$mode,$BASE,$c,$MEM_STR,$ITER,$T_SPMV,$T_MGMT,$N_OPS" >> "$OUT"
            echo "      Time SpMV: $T_SPMV s | Time Total: $T_MGMT s | N_OPS: $N_OPS"
        done
    done
done
