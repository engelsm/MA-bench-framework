#!/bin/bash

SYM_DIR="../../matrices/binary_spmc/symmetric"
ASYM_DIR="../../matrices/binary_spmc/unsymmetric"
OUT="itertest_krylov.csv"

MAX_ITER_LINEAR=1000
MAX_RESTARTS_EIGEN=5
N_EIGVALS=2 #For stress test k=10, m=20
N_BVECS=10

CORES=(1 4 8 24 48 96)
ALGOS=("cg" "bicgstab" "lanczos" "arnoldi")

echo "Algo,Matrix,Cores,Arg1,Arg2,Arg3,SpMV_Time,Mgmt_Time,N_OPS" > "$OUT"

for algo in "${ALGOS[@]}"; do
    if [[ "$algo" == "cg" || "$algo" == "lanczos" ]]; then
        DIRS=("symmetric")
        echo "--- Algo: $algo (Symmetric Only) ---"
    else
        DIRS=("symmetric" "unsymmetric")
        echo "--- Algo: $algo (General) ---"
    fi

    for sub_dir in "${DIRS[@]}"; do
        current_full_path="/home/mengelsl/MA-bench-framework/matrices/binary_spmc/$sub_dir"
        
        for file in "$current_full_path"/*.bin; do
            [ -f "$file" ] || continue
            
            base_name=$(basename "$file")
            FILE_REF="${sub_dir}/${base_name}"

            echo "Starting Matrix: $FILE_REF"

            for c in "${CORES[@]}"; do
                if [[ "$algo" == "cg" || "$algo" == "bicgstab" ]]; then
                    BASE_VAL=$MAX_ITER_LINEAR
                    [[ "$algo" == "bicgstab" ]] && BASE_VAL=$((MAX_ITER_LINEAR / 2))
                    ARG1=$(( (BASE_VAL * c / 48) + 20 ))
                    ARG2=0
                    ARG3=0
                else
                    ARG1=$(( (BASE_VAL * (c + 48) / 96) + 20 ))
                    ARG2="$N_EIGVALS" 
                    ARG3="$N_BVECS"
                fi

                export OMP_NUM_THREADS=$c
                export OMP_PROC_BIND=close
                export OMP_PLACES=cores
                
                CPUS="0-$((c - 1))"

                RES=$(/home/mengelsl/MA-bench-framework/build/solve "$file" "$algo" "$ARG1" "$ARG2" "$ARG3" | grep "EXTRA_DATA")
                
                if [[ -z "$RES" ]]; then
                    echo "     ERROR: No output for $FILE_REF"
                    continue
                fi

                T_SPMV=$(echo "$RES" | cut -d',' -f2)
                T_MGMT=$(echo "$RES" | cut -d',' -f3)
                N_OPS=$(echo "$RES" | cut -d',' -f4)

                echo "$algo,$FILE_REF,$c,$ARG1,$ARG2,$ARG3,$T_SPMV,$T_MGMT,$N_OPS" >> "$OUT"
                echo "     Cores $c Done: $T_SPMV s (SpMV), $T_MGMT s (Mgmt), $N_OPS Ops"
            done
        done
    done
done

echo "Benchmark finished. Results in $OUT"