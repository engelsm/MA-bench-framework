#!/bin/bash
#SBATCH --cpus-per-task=16
#SBATCH --job-name=Eigen_Spectra_Time_f

ml load math/Eigen/3.4.0-GCCcore-13.3.0

CORES=(1 2 4 8 16)
ALGOS=("lanczos" "davidson")
SAMPLE_RATE=2

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTDIR="outputs/benchmark_comparison_$TIMESTAMP"
mkdir -p "$OUTDIR"
CSV="$OUTDIR/comparison_results.csv"

echo "cores,run,algorithm,real_time_s,user_time_s,sys_time_s" > "$CSV"

MATRIX="matrices/binary/venturiLevel3.dat"

# g++ -O3 -march=znver4 -fopenmp -I$EBROOTEIGEN -I$HOME/libs/spectra/include ./src_c/spectra_multi_solver.cpp -o ./src_c/spectra_multi_solver

for C in "${CORES[@]}"; do
    export OMP_NUM_THREADS=$C
    echo "--- Cores: $C ---"

    for ALGO in "${ALGOS[@]}"; do
        echo "  Testing Algorithm: $ALGO"
        
        for R in $(seq 1 $SAMPLE_RATE); do
            echo "    Run $R"

            CURRENT_FORMAT="$C,$R,$ALGO,$MATRIX,%e,%U,%S"
            
            /usr/bin/time -f "$CURRENT_FORMAT" -o "$CSV" -a ./src_c/spectra_multi_solver "$ALGO" "$MATRIX"
        done
    done
done

echo "DONE → $CSV"