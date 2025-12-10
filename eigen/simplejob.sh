#!/bin/bash

module load lang/SciPy-bundle/2024.05-gfbf-2024a

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTDIR="outputs/$TIMESTAMP"
mkdir -p "$OUTDIR"

echo "Output folder: $OUTDIR"

# -------------------
# Run Lanczos and time it
# -------------------
LANCZOS_OUT="$OUTDIR/lanczos_top_vecs.npy"
/usr/bin/time -v python3 lanczos.py matrix_sparse.npz "$LANCZOS_OUT" \
    > "$OUTDIR/lanczos.out" 2> "$OUTDIR/lanczos.time"

# -------------------
# Run RQI using that output
# -------------------
/usr/bin/time -v python3 rqi.py matrix_dense.npy "$LANCZOS_OUT" \
    > "$OUTDIR/rqi.out" 2> "$OUTDIR/rqi.time"