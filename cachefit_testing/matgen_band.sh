#!/bin/bash
MATGEN="../build/matgen"
BASE_DIR="./matrices"
mkdir -p "$BASE_DIR"

SEED=42
TARGET_AVG_NNZ=30

START=10000
STEP=10000
END=200000

for N in $(seq $START $STEP $END); do
    BW_PERFECT=$(echo "scale=10; (($TARGET_AVG_NNZ / 2) - 0.5) / $N" | bc)
    FILENAME="$BASE_DIR/band_N${N}.bin"

    echo "N=$N: Generating..."
    $MATGEN $N 0 0 "normal" $SEED "perfect" $BW_PERFECT 0 0 0 0 "$FILENAME"
done

echo "Done. Check sizes with: du -sh $BASE_DIR/*"