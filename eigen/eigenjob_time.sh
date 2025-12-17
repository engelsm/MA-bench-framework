#!/bin/bash
#SBATCH --cpus-per-task=16
#SBATCH --job-name=Eigen_Spectra_Time_f

ml load math/Eigen/3.4.0-GCCcore-13.3.0

CORES=(1 2 4 8 16)
SAMPLE_RATE=5

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTDIR="outputs/benchmark_time_f_$TIMESTAMP"
mkdir -p "$OUTDIR"
CSV="$OUTDIR/time_f_results.csv"

TIME_FORMAT="%e,%U,%S"

echo "cores,run,algorithm,real_time_s,user_time_s,sys_time_s" > "$CSV"

MATRIX="matrices/binary/pkustk10.dat"

for C in "${CORES[@]}"; do #todo prüfen ob openmp wirklich genutzt wird und schauen ob matrix store optimiert werden kann
    export OMP_NUM_THREADS=$C
    echo "--- Cores: $C, OMP_NUM_THREADS: $OMP_NUM_THREADS ---"

    for R in $(seq 1 $SAMPLE_RATE); do
        echo "  Run $R"

        TIMES_CSV=$(/usr/bin/time -f "$TIME_FORMAT" \
            -o /dev/stdout \
            ./src_c/spectra_solver "$MATRIX" \
            2>/dev/null
        )
        
        echo "$C,$R,SPECTRA_ALGO_$MATRIX,$TIMES_CSV" >> "$CSV"
    done
done

echo "DONE → $CSV"