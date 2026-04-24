# Generates synthetic sparse matrix binary files for predefined matrix sizes and randomness factors.
# Purpose: Automate batch creation of benchmark input matrices in a target output directory.
# What it does: Creates the output directory, iterates over fixed N values and randomness factors, builds output filenames, and calls `synthgen` with N, NNZ-per-row, randomness, and output path.
# Outputs: `.bin` files named like `<randomness>_N<size>.bin` in `MATRIX_PATH`, then prints a completion message and directory listing.

#!/bin/bash

MATRIX_PATH=$1
mkdir -p "$MATRIX_PATH"

N_VALUES=(28807 201649 432105 1440352 8642110)  
NNZ_PER_ROW=30
RANDOM_FACTORS=(0.0 1.0)

for N in "${N_VALUES[@]}"; do
    for R in "${RANDOM_FACTORS[@]}"; do
        # Format: 0.5 -> 0-5
        R_NAME=$(echo "$R" | tr '.' '-')
        FILENAME="$MATRIX_PATH/${R_NAME}_N${N}.bin"
        
        echo "Generating: N=$N | Randomness=$R"
        echo "Target Path: $FILENAME"
        
        /home/mengelsl/MA-bench-framework/build/synthgen "$N" "$NNZ_PER_ROW" "$R" "$FILENAME"
    done
done

echo "Done. Generated in $MATRIX_PATH."
ls -lh "$MATRIX_PATH"