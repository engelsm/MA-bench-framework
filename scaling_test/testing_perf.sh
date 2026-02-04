#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --time=04:00:00
#SBATCH --exclusive

# 1. Setup & Verzeichnisse
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTDIR="/home/mengelsl/MA-bench-framework/outputs_testing/$TIMESTAMP" 
mkdir -p "$OUTDIR"
CSV="$OUTDIR/summary_final.csv"
TMP_OUT="$OUTDIR/tmp_output.txt"
PLAN="bench_plan.csv"

if [ ! -f "$PLAN" ]; then
    echo "Fehler: $PLAN nicht gefunden!"
    exit 1
fi

# Header mit NUMA-Spalte und allen Hardware-Metriken
if [ ! -f "$CSV" ]; then
    echo "Matrix,Cores,NUMA,Run,Iterations,Runtime,Gflops,Insn,Cycl,RefCycl,dTLB_Miss,Cache_Miss,Stalls,CtxSwitch,PgFault" > "$CSV"
fi

# Konfiguration
RUNS=7
MATRIX_DIR="./scaling_test/matrices/itertest"
NUMA_MODES=("localalloc" "interleave=0,1")

export OMP_PROC_BIND=close
export OMP_PLACES=cores

echo "Starte SME/SEV Jitter-Check | Plan: $PLAN"
echo "--------------------------------------------------------"

# 2. Den Plan abarbeiten
tail -n +2 "$PLAN" | while IFS=, read -r matrix cores iter
do
    FILE_PATH="$MATRIX_DIR/$matrix"
    [ -f "$FILE_PATH" ] || continue

    # Threads und Core-Pinning setzen (wir bleiben auf den ersten 48 Cores)
    export OMP_NUM_THREADS=$cores
    if [ "$cores" -eq 1 ]; then CPUS="0"; else CPUS="0-$((cores - 1))"; fi

    for mode in "${NUMA_MODES[@]}"; do
        # NUMA Kommando vorbereiten
        if [ "$mode" == "localalloc" ]; then
            NUMA_CMD="numactl -C $CPUS --localalloc"
        else
            NUMA_CMD="numactl -C $CPUS --interleave=0,1"
        fi

        for i in $(seq 1 $RUNS); do
            # Resume Logik
            if [ -f "$CSV" ] && grep -q "^$matrix,$cores,$mode,$i," "$CSV"; then
                continue
            fi

            echo "[$(date +%H:%M:%S)] $matrix | Cores: $cores | NUMA: $mode | Run: $i"

            # Ausführung mit perf stat (6 HW-Events + 2 SW-Events)
            PERF_RAW=$( { perf stat -x ',' \
                -e instructions,cycles,ref-cycles,dTLB-load-misses,cache-misses,stalled-cycles-frontend,context-switches,page-faults \
                $NUMA_CMD ../build/spmv "$FILE_PATH" "$iter" 1> "$TMP_OUT"; } 2>&1 )

            # 1. Extraktion SpMV-Daten
            EXTRA_LINE=$(grep "EXTRA_DATA" "$TMP_OUT")
            T_SPMV=$(echo "$EXTRA_LINE" | cut -d',' -f2)
            GFLOPS=$(echo "$EXTRA_LINE" | cut -d',' -f3)

            # 2. Extraktion Hardware-Daten (Robustes Parsing mit :u Filter)
            INST=$(echo "$PERF_RAW" | grep "instructions:u" | cut -d',' -f1)
            CYCL=$(echo "$PERF_RAW" | grep "cycles:u" | grep -v "ref-cycles" | cut -d',' -f1)
            REFC=$(echo "$PERF_RAW" | grep "ref-cycles:u" | cut -d',' -f1)
            DTLB=$(echo "$PERF_RAW" | grep "dTLB-load-misses:u" | cut -d',' -f1)
            CMIS=$(echo "$PERF_RAW" | grep "cache-misses:u" | cut -d',' -f1)
            STAL=$(echo "$PERF_RAW" | grep "stalled-cycles-frontend:u" | cut -d',' -f1)
            CTXS=$(echo "$PERF_RAW" | grep "context-switches:u" | cut -d',' -f1)
            FAUL=$(echo "$PERF_RAW" | grep "page-faults:u" | cut -d',' -f1)

            # In CSV schreiben
            echo "$matrix,$cores,$mode,$i,$iter,$T_SPMV,$GFLOPS,$INST,$CYCL,$REFC,$DTLB,$CMIS,$STAL,$CTXS,$FAUL" >> "$CSV"
            
            sync "$CSV"
            
            # Kurzes Feedback im Terminal
            if [ "$CYCL" -gt 0 ]; then
                IPC=$(echo "scale=2; $INST / $CYCL" | bc -l)
                echo "  -> $GFLOPS Gflops | IPC: $IPC | Stalls: $STAL"
            else
                echo "  -> $GFLOPS Gflops | Measurement Error"
            fi
        done
    done
done

rm -f "$TMP_OUT"
echo "--------------------------------------------------------"
echo "Fertig. Ergebnisse in: $CSV"