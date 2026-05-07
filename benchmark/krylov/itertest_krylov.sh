#!/bin/bash

ml tools/numactl/2.0.19-GCCcore-14.2.0

BASE_DIR="/home/mengelsl/MA-bench-framework/matrices/binary_spmc"
SUBDIRS=("symmetric" "unsymmetric")
OUT="itertest.csv"
BINARY="/home/mengelsl/MA-bench-framework/build/krylov"

export OMP_PROC_BIND=close
export OMP_PLACES=cores

CORES=(1 8 24 48)
N_EIGVALS=2 
N_BVECS=10

FIXED_OPS_LINEAR=60   
FIXED_RESTARTS_EIGEN=5 

echo "Matrix,Type,Cores,NUMA_Policy,Algo,Arg1,Arg2,Arg3,SpMV_Time,Mgmt_Time,N_OPS" > "$OUT"

for subdir in "${SUBDIRS[@]}"; do
    MATRIX_DIR="$BASE_DIR/$subdir"
    
    if [ ! -d "$MATRIX_DIR" ]; then continue; fi
    TEST_FILES=($(ls $MATRIX_DIR/*.bin 2>/dev/null))

    if [ "$subdir" == "symmetric" ]; then
        CURRENT_ALGOS=("cg" "lanczos")
    else
        CURRENT_ALGOS=("bicgstab" "arnoldi")
    fi

    for file in "${TEST_FILES[@]}"; do
        file_basename=$(basename "$file")

        for algo in "${CURRENT_ALGOS[@]}"; do
            if [[ "$algo" == "cg" || "$algo" == "bicgstab" ]]; then
                ARG1=$FIXED_OPS_LINEAR
                ARG2=0
                ARG3=0
            else
                ARG1=$FIXED_RESTARTS_EIGEN
                ARG2="$N_EIGVALS" 
                ARG3="$N_BVECS"
            fi

            for c in "${CORES[@]}"; do
                POLICIES=("membind" "interleave")
                for pol in "${POLICIES[@]}"; do
                        echo "-Threads: $c | Policy: $pol | Algo: $algo | File: $file_basename"

                    CORE_RANGE="0-$((c-1))"
                    
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

                    RES=$(setarch $(uname -m) -R numactl -C $CORE_RANGE $NUMA_FLAG "$BINARY" "$file" "$algo" "$ARG1" "$ARG2" "$ARG3" 0 "$c" "$pol" --cout) 

                    T_SPMV=$(echo "$RES" | cut -d',' -f9)
                    T_MGMT=$(echo "$RES" | cut -d',' -f10)
                    N_OPS=$(echo "$RES" | cut -d',' -f11)

                    echo "$file_basename,$subdir,$c,$pol,$algo,$ARG1,$ARG2,$ARG3,$T_SPMV,$T_MGMT,$N_OPS" >> "$OUT"

                    echo "Done: $file_basename ($subdir) | Algo: $algo | Cores: $c | Policy: $pol"
                done
            done
        done
    done
done

echo "Benchmark abgeschlossen. Ergebnisse in $OUT"