#!/bin/bash

# Konfiguration
STREAM_ARRAY_SIZE=430080000
NTIMES=100
CSV_FILE="stream_results.csv"
THREADS_LIST=(24 48 96)

ENV=$1
BOOST=$2
NUMA=$3

if [ ! -f "$CSV_FILE" ]; then
    echo "Threads,Env,Boost,Numa,Function,BestRate_MBs,AvgTime,MinTime,MaxTime" > "$CSV_FILE"
fi

for N in "${THREADS_LIST[@]}"; do
    echo "== Running STREAM with $N threads ($ENV, Numa: $NUMA) =="
    
    export OMP_NUM_THREADS=$N
    export OMP_PROC_BIND=close
    export OMP_PLACES=cores
    
    if [ "$ENV" == "native" ]; then
        if [ "$NUMA" == "interleave" ]; then
            # Bestimme Nodes basierend auf Thread-Anzahl
            case $N in
                24) NODES="0" ;;
                48) NODES="0,1" ;;
                96) NODES="0,1,2,3" ;;
                *)  NODES="all" ;; # Fallback
            esac
            CMD="numactl --interleave=$NODES -C 0-$((N-1)) ./stream.out"
        else
            # Standard: Nur CPU-Binding, Memory bleibt lokal (default)
            CMD="numactl -C 0-$((N-1)) ./stream.out"
        fi
    else
        # In der VM (SEV/SME) lassen wir das OS/Hypervisor entscheiden
        CMD="./stream.out"
    fi

    echo "Executing: $CMD"
    $CMD | awk -v threads="$N" -v env="$ENV" -v boost="$BOOST" -v numa="$NUMA" '
        /Copy:|Scale:|Add:|Triad:/ {
            sub(/:/, "", $1);
            print threads "," env "," boost "," numa "," $1 "," $2 "," $3 "," $4 "," $5
        }' >> "$CSV_FILE"
done

echo "Done. Results appended to $CSV_FILE"