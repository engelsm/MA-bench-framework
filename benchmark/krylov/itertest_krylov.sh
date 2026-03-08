#!/bin/bash

OUT="itertest_krylov_fixed.csv"

FIXED_OPS_LINEAR=60   
FIXED_RESTARTS_EIGEN=5 

N_EIGVALS=2 
N_BVECS=10

CORES=(1 4 8 24 48 96)
ALGOS=("cg" "bicgstab" "lanczos" "arnoldi")

echo "Algo,Matrix,Cores,Arg1,Arg2,Arg3,SpMV_Time,Mgmt_Time,N_OPS" > "$OUT"

for algo in "${ALGOS[@]}"; do
    if [[ "$algo" == "cg" || "$algo" == "lanczos" ]]; then
        DIRS=("symmetric")
    else
        DIRS=("symmetric" "unsymmetric")
    fi

    for sub_dir in "${DIRS[@]}"; do
        current_full_path="/home/mengelsl/MA-bench-framework/matrices/binary_spmc/$sub_dir"
        for file in "$current_full_path"/*.bin; do
            [ -f "$file" ] || continue
            FILE_REF="${sub_dir}/$(basename "$file")"

            for c in "${CORES[@]}"; do
                if [[ "$algo" == "cg" || "$algo" == "bicgstab" ]]; then
                    ARG1=$FIXED_OPS_LINEAR
                    ARG2=0
                    ARG3=0
                else
                    ARG1=$FIXED_RESTARTS_EIGEN
                    ARG2="$N_EIGVALS" 
                    ARG3="$N_BVECS"
                fi

                export OMP_NUM_THREADS=$c
                export OMP_PROC_BIND=close
                export OMP_PLACES=cores
                
                RES=$(/home/mengelsl/MA-bench-framework/build/solve "$file" "$algo" "$ARG1" "$ARG2" "$ARG3" | grep "EXTRA_DATA")

                T_SPMV=$(echo "$RES" | cut -d',' -f2)
                T_MGMT=$(echo "$RES" | cut -d',' -f3)
                N_OPS=$(echo "$RES" | cut -d',' -f4)

                echo "$algo,$FILE_REF,$c,$ARG1,$ARG2,$ARG3,$T_SPMV,$T_MGMT,$N_OPS" >> "$OUT"
                
                TOTAL_TIME=$(awk "BEGIN {print $T_SPMV + $T_MGMT}")
                echo "     Cores $c Done: ${TOTAL_TIME}s total (SpMV: ${T_SPMV}s, Mgmt: ${T_MGMT}s)"
            done
        done
    done
done