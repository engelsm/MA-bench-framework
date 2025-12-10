#!/bin/bash

module load lang/SciPy-bundle/2024.05-gfbf-2024a

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTDIR="outputs/$TIMESTAMP"
mkdir -p "$OUTDIR"

echo "Output folder: $OUTDIR"

MATRIX="matrices/bcsstk13.mtx"
FORMATTED_DIR="matrices/formatted"

BASENAME=$(basename "$MATRIX" .mtx)
DENSE="$FORMATTED_DIR/${BASENAME}_dense.npy"
SPARSE="$FORMATTED_DIR/${BASENAME}_sparse.npz"

LANCZOS_OUT="$OUTDIR/${BASENAME}_lanczos_top_vecs.npy"

python3 src/load_matrix.py "$MATRIX"

/usr/bin/time -v python3 src/lanczos.py "$SPARSE" "$LANCZOS_OUT" \
    > "$OUTDIR/lanczos.out" 2> "$OUTDIR/lanczos.time"

/usr/bin/time -v python3 src/rqi.py "$DENSE" "$LANCZOS_OUT" \
    > "$OUTDIR/rqi.out" 2> "$OUTDIR/rqi.time"

echo "=== DONE ==="