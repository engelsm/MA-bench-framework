#!/bin/bash

SYM_DIR="../../matrices/binary_spmc/symmetric"
ASYM_DIR="../../matrices/binary_spmc/unsymmetric"
OUT="itertest_krylov.csv"

MAX_ITER_LINEAR=1000
MAX_RESTARTS_EIGEN=5

CORES=(1 4 8 16 24 32 48)
ALGOS=("cg" "bicgstab" "lanczos" "arnoldi")

echo "Algo,Matrix,Cores,MemoryPolicy,Arg1,Arg2,Arg3,SpMV_Time,Mgmt_Time,N_OPS" > "$OUT"

for algo in "${ALGOS[@]}"; do
    if [[ "$algo" == "cg" || "$algo" == "lanczos" ]]; then
        DIRS=("symmetric")
        echo "--- Algo: $algo (Symmetric Only) ---"
    else
        DIRS=("symmetric" "unsymmetric")
        echo "--- Algo: $algo (General) ---"
    fi

    for sub_dir in "${DIRS[@]}"; do
        current_full_path="../../matrices/binary_spmc/$sub_dir"
        
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
                    ARG1=$(( (MAX_RESTARTS_EIGEN * c / 48) + 5 ))
                    ARG2=2 #For stress test k=10, m=20
                    ARG3=10
                fi

                export OMP_NUM_THREADS=$c
                export OMP_PROC_BIND=close
                export OMP_PLACES=cores
                
                if [ "$c" -eq 1 ]; then
                    CPUS="1" 
                else
                    CPUS="0-$((c - 1))"
                fi

                if [ "$c" -gt 24 ]; then
                    MEM_STR="interleave"
                    MEM_POLICY="--interleave=0,1"
                else
                    MEM_STR="localalloc"
                    MEM_POLICY="--localalloc"
                fi

                RES=$(numactl -C $CPUS $MEM_POLICY ../../build/solve "$file" "$algo" "$ARG1" "$ARG2" "$ARG3" | grep "EXTRA_DATA")
                
                if [[ -z "$RES" ]]; then
                    echo "     ERROR: No output for $FILE_REF"
                    continue
                fi

                T_SPMV=$(echo "$RES" | cut -d',' -f2)
                T_MGMT=$(echo "$RES" | cut -d',' -f3)
                N_OPS=$(echo "$RES" | cut -d',' -f4)

                echo "$algo,$FILE_REF,$c,$MEM_STR,$ARG1,$ARG2,$ARG3,$T_SPMV,$T_MGMT,$N_OPS" >> "$OUT"
                echo "     Cores $c Done: $T_SPMV s"
            done
        done
    done
done

echo "Benchmark finished. Results in $OUT"