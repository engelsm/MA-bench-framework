#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --time=04:00:00
#SBATCH --exclusive

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTDIR="outputs/spmv_$TIMESTAMP"
mkdir -p "$OUTDIR"
CSV="$OUTDIR/spmv_results.csv"
echo $CSV

export OMP_PROC_BIND=close
export OMP_PLACES=cores

CORE_OFFSET=0
NUMA_NODES="0,1"
CORES=(24 48)
SAMPLE_RATE=7

# --- ZENTRALE KONFIGURATION IM ARRAY ---
# Format: ["Pfad"]=Iterationen
declare -A MATRICES=(
    ["matrices/gen1/sym_band.bin"]=200000
    ["matrices/gen1/sym_mesh.bin"]=200000
    ["matrices/gen2/sym_band.bin"]=150000
    ["matrices/gen2/sym_mesh.bin"]=150000
)

echo "n_cores,config,run,matrix_path,iterations,perf_walltime_ns,perf_instructions,perf_cycles,perf_cache_misses,perf_cache_refs,perf_l1_loads,spmv_total_s,gflops" > "$CSV"

# Wir loopen über die Keys (Pfade) des Arrays
for M in "${!MATRICES[@]}"; do
    if [ ! -f "$M" ]; then
        echo "Skip: $M nicht gefunden"
        continue
    fi

    ITERATIONS=${MATRICES[$M]}
    echo "Processing: $M mit $ITERATIONS Iterationen"

    for C in "${CORES[@]}"; do
        export OMP_NUM_THREADS=$C
        
        # Konfigurations-Logik
        if [ $C -le 24 ]; then
            CONFIGS=("DEFAULT") 
        else
            CONFIGS=("DEFAULT" "LOCAL" "INTERLEAVE")
        fi

        for CFG in "${CONFIGS[@]}"; do
            case $CFG in
                "DEFAULT")    NUMA_CMD="numactl --physcpubind=$CORE_OFFSET-$((C+CORE_OFFSET-1))" ;;
                "LOCAL")      NUMA_CMD="numactl --physcpubind=$CORE_OFFSET-$((C+CORE_OFFSET-1)) --localalloc" ;;
                "INTERLEAVE") NUMA_CMD="numactl --physcpubind=$CORE_OFFSET-$((C+CORE_OFFSET-1)) --interleave=$NUMA_NODES" ;;
            esac

            for R in $(seq 1 $SAMPLE_RATE); do
                echo "Run: $R | Matrix: $(basename $M) | Cores: $C | Config: $CFG"
                TMP_OUT="/dev/shm/spmv_tmp_${TIMESTAMP}_${R}.txt"

                # Warmup
                $NUMA_CMD ./build/spmv "$M" 10 > /dev/null

                # Messung
                PERF_RAW=$( { perf stat -x ',' \
                    -e duration_time,instructions,cycles,cache-misses,cache-references,L1-dcache-loads \
                    $NUMA_CMD ./build/spmv "$M" "$ITERATIONS" \
                    1> "$TMP_OUT"; } 2>&1 )

                # Werte extrahieren
                REAL=$(echo "$PERF_RAW" | grep "duration_time" | cut -d',' -f1)
                INST=$(echo "$PERF_RAW" | grep -w "instructions" | cut -d',' -f1)
                CYCL=$(echo "$PERF_RAW" | grep -w "cycles" | cut -d',' -f1)
                CMIS=$(echo "$PERF_RAW" | grep -w "cache-misses" | cut -d',' -f1)
                CREF=$(echo "$PERF_RAW" | grep -w "cache-references" | cut -d',' -f1)
                L1LD=$(echo "$PERF_RAW" | grep -w "L1-dcache-loads" | cut -d',' -f1)

                EXTRA_LINE=$(grep "EXTRA_DATA" "$TMP_OUT")
                SPMV_TOTAL=$(echo "$EXTRA_LINE" | cut -d',' -f2)
                GFLOPS=$(echo "$EXTRA_LINE" | cut -d',' -f3)

                echo "$C,$CFG,$R,$M,$ITERATIONS,$REAL,$INST,$CYCL,$CMIS,$CREF,$L1LD,$SPMV_TOTAL,$GFLOPS" >> "$CSV"
                rm -f "$TMP_OUT"
            done
        done
    done
done

echo "Fertig! Ergebnisse unter: $CSV"