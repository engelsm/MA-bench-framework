#!/bin/bash

STREAM_ARRAY_SIZE=430080000
NTIMES=100
ml mpi/OpenMPI/4.1.5-GCC-12.3.0
gcc -o stream.out -O -DSTREAM_ARRAY_SIZE=$STREAM_ARRAY_SIZE -DNTIMES=$NTIMES -fopenmp -mcmodel=medium ./stream.c

CSV_FILE="stream_results.csv"
echo "Threads,Boost,VM,Host,Function,BestRate_MBs,AvgTime,MinTime,MaxTime" > "$CSV_FILE"

declare -A VMS
VMS=( ["ramses2007"]="ramses11002" ["ramses2004"]="ramses11041" )

THREADS_LIST=(24 48 96)
BOOST_STATES=("on" "off")

for VM in "${!VMS[@]}"; do
    HOST="${VMS[$VM]}"
    
    for BOOST in "${BOOST_STATES[@]}"; do
        echo "== Running $VM on $HOST with CPU boost $BOOST =="

        ssh "$HOST" "sudo /usr/local/bin/cpu-boost-toggle.sh $BOOST"

        for N in "${THREADS_LIST[@]}"; do
            ssh "$VM" "
                export OMP_NUM_THREADS=$N
                export OMP_PROC_BIND=close
                export OMP_PLACES=cores
                ~/MA-bench-framework/benchmark/stream/stream.out
            " | awk -v threads="$N" -v boost="$BOOST" -v vm="$VM" -v host="$HOST" '
                /Copy:|Scale:|Add:|Triad:/ {
                    sub(/:/, "", $1);
                    print threads "," boost "," vm "," host "," $1 "," $2 "," $3 "," $4 "," $5
                }' >> "$CSV_FILE"
        done
    done
done

echo "All results saved to $CSV_FILE"