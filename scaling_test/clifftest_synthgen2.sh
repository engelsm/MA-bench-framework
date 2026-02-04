#!/bin/bash

N_VALUES=(28800 57600 115000 230000 518000 864000 2950000)
NNZ_PER_ROW=30
RANDOM_FACTORS=(0.0 0.5 1.0)

mkdir -p ./matrices/itertest2

for N in "${N_VALUES[@]}"; do
    for R in "${RANDOM_FACTORS[@]}"; do
        # Formatierung: 0.5 -> 0-5
        R_NAME=$(echo "$R" | tr '.' '-')
        FILENAME="./matrices/itertest/${R_NAME}_N${N}.bin"
        
        echo "----------------------------------------------------"
        echo "Generating: N=$N | Randomness=$R"
        echo "Target Path: $FILENAME"
        
        ../build/synthgen "$N" "$NNZ_PER_ROW" "$R" "$FILENAME"
    done
done

echo "----------------------------------------------------"
echo "Done. Alle Matrizen wurden in ./matrices/itertest2/ generiert."
ls -lh ./matrices/itertest2/