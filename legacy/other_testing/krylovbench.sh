#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --time=06:00:00
#SBATCH --exclusive

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTDIR="outputs/krylov_$TIMESTAMP"
mkdir -p "$OUTDIR"
CSV="$OUTDIR/krylov_results.csv"

# Header: Alle Hardware-Counter + deine EXTRA_DATA Felder
echo "mode,n_cores,config,run,matrix_path,arg1,arg2,arg3,perf_walltime_ns,perf_instructions,perf_cycles,perf_cache_misses,t_spmv,t_mgmt,n_ops" > "$CSV"

export OMP_PROC_BIND=close
export OMP_PLACES=cores

# --- ZENTRALE PARAMETER-KONFIGURATION ---
# Syntax: PARAMS["matrix_name:mode"]="arg1 arg2 arg3"
# arg1: Iterationen (Solver) / Max Restarts (Eigen)
# arg2: Eigenwerte (nur für lanczos/arnoldi)
# arg3: Basis-Vektoren (nur für lanczos/arnoldi)

declare -A PARAMS

# Konfiguration für sym_band.bin
PARAMS["sym_band.bin:cg"]="2000 0 0"
PARAMS["sym_band.bin:bicgstab"]="1000 0 0"
PARAMS["sym_band.bin:lanczos"]="100 20 40"
PARAMS["sym_band.bin:arnoldi"]="100 20 40"

# Konfiguration für sym_mesh.bin
PARAMS["sym_mesh.bin:cg"]="4000 0 0"
PARAMS["sym_mesh.bin:bicgstab"]="2000 0 0"
PARAMS["sym_mesh.bin:lanczos"]="200 20 40"
PARAMS["sym_mesh.bin:arnoldi"]="200 20 40"

# Weitere Matrizen hier einfach ergänzen...

CORES=(24 48)
SAMPLE_RATE=5
MATRICES=("matrices/gen1/sym_band.bin" "matrices/gen1/sym_mesh.bin")
MODES=("cg" "bicgstab" "lanczos" "arnoldi")

for M in "${MATRICES[@]}"; do
    M_BASE=$(basename "$M")
    if [ ! -f "$M" ]; then
        echo "Skip: $M nicht gefunden"
        continue
    fi

    for MODE in "${MODES[@]}"; do
        # Parameter-String holen oder Default setzen
        PARAM_STR=${PARAMS["$M_BASE:$MODE"]:-"100 20 40"}
        read -r A1 A2 A3 <<< "$PARAM_STR"

        for C in "${CORES[@]}"; do
            export OMP_NUM_THREADS=$C
            
            # NUMA Configs festlegen
            if [ $C -le 24 ]; then
                CONFIGS=("DEFAULT")
            else
                CONFIGS=("DEFAULT" "LOCAL" "INTERLEAVE")
            fi

            for CFG in "${CONFIGS[@]}"; do
                # NUMA-Kommando zusammenbauen
                case $CFG in
                    "DEFAULT")    NUMA_CMD="numactl --physcpubind=0-$((C-1))" ;;
                    "LOCAL")      NUMA_CMD="numactl --physcpubind=0-$((C-1)) --localalloc" ;;
                    "INTERLEAVE") NUMA_CMD="numactl --physcpubind=0-$((C-1)) --interleave=0,1" ;;
                esac

                for R in $(seq 1 $SAMPLE_RATE); do
                    echo "Run: $R | $MODE | $M_BASE | Cores: $C | Config: $CFG | Params: $A1 $A2 $A3"
                    TMP_OUT="/dev/shm/krylov_tmp_${TIMESTAMP}.txt"

                    # Messung mit perf stat (Hardware-Counter)
                    # Wir fangen duration_time, instructions, cycles und cache-misses ein
                    PERF_RAW=$( { perf stat -x ',' \
                        -e duration_time,instructions,cycles,cache-misses \
                        $NUMA_CMD ./build/spmv "$M" "$MODE" "$A1" "$A2" "$A3" \
                        1> "$TMP_OUT"; } 2>&1 )

                    # Extraktion Hardware-Daten
                    REAL=$(echo "$PERF_RAW" | grep "duration_time" | cut -d',' -f1)
                    INST=$(echo "$PERF_RAW" | grep -w "instructions" | cut -d',' -f1)
                    CYCL=$(echo "$PERF_RAW" | grep -w "cycles" | cut -d',' -f1)
                    CMIS=$(echo "$PERF_RAW" | grep -w "cache-misses" | cut -d',' -f1)

                    # Extraktion Anwendungs-Daten aus deinem print_output
                    EXTRA_LINE=$(grep "EXTRA_DATA" "$TMP_OUT")
                    T_SPMV=$(echo "$EXTRA_LINE" | cut -d',' -f2)
                    T_MGMT=$(echo "$EXTRA_LINE" | cut -d',' -f3)
                    N_OPS=$(echo "$EXTRA_LINE" | cut -d',' -f4)

                    # Alles in die CSV schreiben
                    echo "$MODE,$C,$CFG,$R,$M,$A1,$A2,$A3,$REAL,$INST,$CYCL,$CMIS,$T_SPMV,$T_MGMT,$N_OPS" >> "$CSV"
                    
                    rm -f "$TMP_OUT"
                done
            done
        done
    done
done

echo "------------------------------------------------"
echo "Benchmark abgeschlossen!"
echo "Ergebnisse gespeichert in: $CSV"