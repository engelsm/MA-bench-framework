#!/bin/bash
#SBATCH --cpus-per-task=16

module load lang/SciPy-bundle/2024.05-gfbf-2024a

CORES=(1 2 4 8 16) 

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
MASTER_OUTDIR="outputs/benchmark_$TIMESTAMP"
mkdir -p "$MASTER_OUTDIR"

echo "Master Output folder: $MASTER_OUTDIR"

MATRIX="matrices/bcsstk13.mtx"
FORMATTED_DIR="matrices/formatted"

BASENAME=$(basename "$MATRIX" .mtx)
DENSE="$FORMATTED_DIR/${BASENAME}_dense.npy"
SPARSE="$FORMATTED_DIR/${BASENAME}_sparse.npz"

python3 src/load_matrix.py "$MATRIX" 

for N_CORES in "${CORES[@]}"; do
    
    export OMP_NUM_THREADS=$N_CORES
    
    OUTDIR="$MASTER_OUTDIR/${N_CORES}_cores"
    mkdir -p "$OUTDIR"

    echo "--- Testing with $N_CORES Core(s) (OMP_NUM_THREADS=$N_CORES) ---"

    LANCZOS_OUT="$OUTDIR/${BASENAME}_lanczos_top_vecs.npy"

    echo "\n--- LANCZOS ---" >> "$OUTDIR/output.out"
    echo "\n--- LANCZOS ---" >> "$OUTDIR/perf.time"

    /usr/bin/time -v python3 src/lanczos.py "$SPARSE" "$LANCZOS_OUT" \
        > "$OUTDIR/output.out" 2> "$OUTDIR/perf.time"

    echo "\n--- RQI ---" >> "$OUTDIR/output.out"
    echo "\n--- RQI ---" >> "$OUTDIR/perf.time"

    /usr/bin/time -v python3 src/rqi.py "$DENSE" "$LANCZOS_OUT" \
        >> "$OUTDIR/output.out" 2>> "$OUTDIR/perf.time"

done

echo "=== DONE BENCHMARKING ==="
echo "Saved in $MASTER_OUTDIR"