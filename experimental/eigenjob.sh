#!/bin/bash
#SBATCH --cpus-per-task=16

module load lang/SciPy-bundle/2024.05-gfbf-2024a
# module load AMDuProfCLI/VERSION
CORES=(1 2 4 8 16)
SAMPLE_RATE=1
ALGORITHMS=("lanczos" "lobpcg")

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTDIR="outputs/uprof_benchmark_$TIMESTAMP"
mkdir -p "$OUTDIR"

MATRIX="matrices/bcsstk13.mtx"
FORMATTED="matrices/formatted"
BASE=$(basename "$MATRIX" .mtx)
#DENSE="$FORMATTED/${BASE}_dense.npy"
SPARSE="$FORMATTED/${BASE}_sparse.npz"

python3 src/load_matrix.py "$MATRIX"

for C in "${CORES[@]}"; do
    export OMP_NUM_THREADS=$C

    echo "--- Cores: $C ---"
    for R in $(seq 1 $SAMPLE_RATE); do
        echo "  Run $R"

        for ALGO in "${ALGORITHMS[@]}"; do
            UPROF_RUN_DIR="$OUTDIR/$ALGO\_C${C}_R${R}"
            mkdir -p "$UPROF_RUN_DIR"
            
            ALGO_OUT_FILE="$UPROF_RUN_DIR/algo_results.npy"

            echo "    > Profiling $ALGO (Saving to $UPROF_RUN_DIR)"
            
            AMDuProfCLI profile -o "$UPROF_RUN_DIR" --config overview python3 "src/$ALGO.py" "$SPARSE" "$ALGO_OUT_FILE"

        done 
    done
done

echo "DONE"