#!/bin/bash

N_VALUES=(28800 57600 115000 230000 518000 864000 2950000)
NNZ_PER_ROW=30
RANDOM_FACTORS=(0.0 0.5 1.0)
MATRIX_PATH="../matrices/itertest"

mkdir -p "$MATRIX_PATH"

for N in "${N_VALUES[@]}"; do
    for R in "${RANDOM_FACTORS[@]}"; do
        # Format: 0.5 -> 0-5
        R_NAME=$(echo "$R" | tr '.' '-')
        FILENAME="$MATRIX_PATH/${R_NAME}_N${N}.bin"
        
        echo "Generating: N=$N | Randomness=$R"
        echo "Target Path: $FILENAME"
        
        ../build/synthgen "$N" "$NNZ_PER_ROW" "$R" "$FILENAME"
    done
done

echo "----------------------------------------------------"
echo "Done. Generated in $MATRIX_PATH."
ls -lh "$MATRIX_PATH"