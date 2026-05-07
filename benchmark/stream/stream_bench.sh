#!/bin/bash

ml tools/numactl/2.0.19-GCCcore-14.2.0

CSV_FILE="stream_out.csv"
THREADS_LIST=(48)

ENV=$1

if [ ! -f "$CSV_FILE" ]; then
    echo "Threads,Env,Function,BestRate_MBs,AvgTime,MinTime,MaxTime" > "$CSV_FILE"
fi

for N in "${THREADS_LIST[@]}"; do
    echo "== Running STREAM with $N threads ($ENV) =="
    
   export OMP_NUM_THREADS=$N
    
   OUT=$(setarch $(uname -m) -R numactl -C 0-$((N - 1)) --membind=0,1 /home/mengelsl/MA-bench-framework/build/stream)

    echo "$OUT" | awk -F'[[:space:]]+' -v threads="$N" -v env="$ENV" '
        /Copy:|Scale:|Add:|Triad:/ {
            # $1: Name (z.B. Copy:), $2: Rate, $3: Avg, $4: Min, $5: Max
            name = $1;
            sub(/:/, "", name);
            print threads "," env "," name "," $2 "," $3 "," $4 "," $5
        }' >> "$CSV_FILE"
done

echo "Done. Results appended to $CSV_FILE"