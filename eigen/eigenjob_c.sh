#!/bin/bash
#SBATCH --cpus-per-task=16

ml load math/Eigen/3.4.0-GCCcore-13.3.0
# Spectra ist header-only → liegt im Repo

CORES=(1 2 4 8 16)
SAMPLE_RATE=1
ALGORITHMS=("lanczos")

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTDIR="outputs/uprof_benchmark_$TIMESTAMP"
mkdir -p "$OUTDIR"

MATRIX="matrices/binary/bcsstk13.dat"

for C in "${CORES[@]}"; do #Scheinbar ist ARPACK nicht thread safe? hier weitermachen
export OMP_NUM_THREADS=$C

echo "--- Cores: $C ---"
for R in $(seq 1 $SAMPLE_RATE); do
    echo "  Run $R"

    for ALGO in "${ALGORITHMS[@]}"; do
        UPROF_RUN_DIR="$OUTDIR/${ALGO}_C${C}_R${R}"
        mkdir -p "$UPROF_RUN_DIR"

        OUTFILE="$UPROF_RUN_DIR/eigenvectors.npy"

        echo "    > Profiling Spectra $ALGO"

        AMDuProfCLI profile --config threading\
            -o "$UPROF_RUN_DIR" \
            ./src_c/uproftester
    done
done
done

echo "DONE"