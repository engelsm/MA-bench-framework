#!/bin/bash

START=200000
STEP=200000
END=800000

NNZ_PER_ROW=30

RANDOM_FACTORS=(0.0 0.5 1.0)

mkdir -p ./matrices_new

for N in $(seq $START $STEP $END); do
    for R in "${RANDOM_FACTORS[@]}"; do
        R_NAME=$(echo "$R" | tr '.' '-')
        FILENAME="./matrices_new/${R_NAME}_N${N}.bin"
        echo "Generating matrix N=$N with randomness=$R -> $FILENAME"
        ../build/synthgen $N $NNZ_PER_ROW $R "$FILENAME"
    done
done

echo "Done. Matrices stored in ./matrices"