#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --time=04:00:00
#SBATCH --exclusive

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTDIR="outputs/spmv_$TIMESTAMP"
mkdir -p "$OUTDIR"
CSV="$OUTDIR/spmv_results.csv"

# Optimierte Umgebungsvariablen für OpenMP & LIKWID
export OMP_PROC_BIND=true
export OMP_PLACES=cores

CORE_OFFSET=47
NUMA_NODES="2,3"
CORES=(24 48)
SAMPLE_RATE=7
GROUP="MEM" # Standardmäßig Memory-Bandbreite messen

# Header angepasst auf LIKWID-Metriken (Region: spmv_kernel)
echo "n_cores,config,run,matrix,iterations,runtime_s,mbyte_s,gbyte_volume" > "$CSV"

declare -A MATRICES=(
    ["matrices/gen1/sym_band.bin"]=100000
    ["matrices/gen1/sym_mesh.bin"]=100000
    ["matrices/gen2/sym_band.bin"]=750000
    ["matrices/gen2/sym_mesh.bin"]=750000
)

for M in "${!MATRICES[@]}"; do
    if [ ! -f "$M" ]; then
        echo "Skip: $M nicht gefunden"
        continue
    fi

    ITERATIONS=${MATRICES[$M]}
    MATRIX_NAME=$(basename "$M")
    echo "Processing: $MATRIX_NAME mit $ITERATIONS Iterationen"

    for C in "${CORES[@]}"; do
        export OMP_NUM_THREADS=$C
        
        # Konfigurations-Logik für NUMA
        if [ $C -le 24 ]; then
            CONFIGS=("LOCAL") 
        else
            CONFIGS=("LOCAL" "INTERLEAVE")
        fi

        for CFG in "${CONFIGS[@]}"; do
            case $CFG in
                "LOCAL")      NUMA_CMD="--localalloc" ;;
                "INTERLEAVE") NUMA_CMD="--interleave=$NUMA_NODES" ;;
            esac

            # CPU-Liste für LIKWID (z.B. 0-23 oder 0-47)
            CPU_LIST="0-$((C-1))"

            for R in $(seq 1 $SAMPLE_RATE); do
                echo "Run: $R | Matrix: $MATRIX_NAME | Cores: $C | Config: $CFG"

                # LIKWID Messung
                # -C: CPU Liste
                # -g: Gruppe (MEM)
                # -m: Marker API nutzen
                # -o: CSV-Tabelle erzeugen
                # numactl wird nur für Memory-Policy genutzt, da LIKWID die CPUs pinnt
                RAW_LOG=$(likwid-perfctr -C $CPU_LIST -g $GROUP -m -t csv numactl $NUMA_CMD ./build/spmv_likwid "$M" "$ITERATIONS")

                # Extraktion mittels awk aus der LIKWID-Tabelle (Region spmv_kernel)
                # Wir suchen die Tabelle für unsere Region und extrahieren die Werte
                K_TIME=$(echo "$RAW_LOG" | awk -F, '/TABLE/ && /spmv_kernel/ && /Runtime \(RDTSC\) \[s\]/ {print $5}')
                K_MBPS=$(echo "$RAW_LOG" | awk -F, '/TABLE/ && /spmv_kernel/ && /Memory bandwidth \[MByte\/s\]/ {print $5}')
                K_VOL=$(echo "$RAW_LOG" | awk -F, '/TABLE/ && /spmv_kernel/ && /Memory data volume \[GByte\]/ {print $5}')

                # Speichern in CSV
                echo "$C,$CFG,$R,$MATRIX_NAME,$ITERATIONS,$K_TIME,$K_MBPS,$K_VOL" >> "$CSV"
            done
        done
    done
done

echo "Fertig! Ergebnisse unter: $CSV"