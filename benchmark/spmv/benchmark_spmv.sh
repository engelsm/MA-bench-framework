#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --time=24:00:00
#SBATCH --exclusive

# Start via: ssh ramses2004 "cd ~/MA-bench-framework/benchmark/spmv && nohup bash benchmark_spmv.sh > benchmark.log 2>&1"

# Parameter von der Kommandozeile
ENV=$1
NUMA_POLICY=$2
BOOST=$3
NUMA_BALANCING=$4

# Verzeichnis-Struktur sicherstellen
if [ -n "$EXISTING_DIR" ] && [ -d "$EXISTING_DIR" ]; then
    OUTDIR="$EXISTING_DIR"
else
    OUTDIR="$HOME/MA-bench-framework/outputs/spmv/again/$ENV"
    mkdir -p "$OUTDIR"
fi

CSV="$OUTDIR/summary_final.csv"
TMP_OUT="$OUTDIR/tmp_output.txt"
PLAN="$HOME/MA-bench-framework/benchmark/spmv/bench_plan.csv"
MATRIX_DIR="$HOME/MA-bench-framework/matrices/spmv_synthetic"
BINARY="$HOME/MA-bench-framework/build/spmv"

MAX_RUNS=20
MIN_RUNS=5
CORE_OFFSET=0
export OMP_PROC_BIND=close
export OMP_PLACES=cores

# Funktion zur Konvergenzprüfung (t-Verteilung)
check_convergence() {
    local m=$1 c=$2 p=$3
    local tmp_file="$OUTDIR/series_check.tmp"
    
    # Grep nur auf Matrix (Spalte 4) und Cores (Spalte 5)
    awk -F, -v m="$m" -v c="$c" '$4==m && $5==c {print $0}' "$CSV" > "$tmp_file"
    
    local n=$(wc -l < "$tmp_file")
    if [ "$n" -lt 5 ]; then 
        echo "fail"
        rm -f "$tmp_file"
        return
    fi

    awk -F, '
    BEGIN { 
        t[5]=2.776; t[6]=2.571; t[7]=2.447; t[8]=2.365; t[9]=2.306; t[10]=2.262; 
        t[11]=2.228; t[12]=2.201; t[13]=2.179; t[14]=2.160; t[15]=2.145;
        t[16]=2.131; t[17]=2.120; t[18]=2.110; t[19]=2.101; t[20]=2.086;
        t[21]=2.080; t[22]=2.074; t[23]=2.069; t[24]=2.064; t[25]=2.060;
    }
    { sum += $8; sumsq += $8*$8; count++ }
    END {
        if (count < 5) { print "fail"; exit }
        mean = sum / count; if (mean == 0) { print "fail"; exit }
        variance = (sumsq - (sum*sum/count)) / (count - 1);
        std = sqrt(variance > 0 ? variance : 0);
        stderr = std / sqrt(count);
        t_val = (count <= 25) ? t[count] : 1.96;
        rel_error = (t_val * stderr) / mean;
        if (rel_error <= 0.01) printf "%.4f", rel_error; else print "fail";
    }' "$tmp_file"
    rm -f "$tmp_file"
}

# Initialisiere CSV mit Header falls nicht vorhanden
if [ ! -f "$CSV" ]; then
    echo "NUMA_Policy,Boost,NUMA_Balancing,Matrix,Cores,Run,Iterations,Intern_Runtime,Intern_Gflops,Perf_DurationTime,Perf_Insn,Perf_Cycl,Perf_CacheMisses,Perf_dTLBLoadMisses" > "$CSV"
fi

echo "Starting SpMV Benchmark. Plan: $PLAN | Output: $CSV"

for (( run_idx=1; run_idx<=MAX_RUNS; run_idx++ )); do
    echo "=== ROUND $run_idx ==="

    while IFS=, read -r raw_matrix raw_cores raw_iter || [ -n "$raw_matrix" ]; do
        # 1. CLEANUP (WICHTIG gegen stoi-Fehler)
        matrix=$(echo "$raw_matrix" | tr -d '\r\n' | xargs)
        cores=$(echo "$raw_cores" | tr -d '\r\n' | xargs)
        iter=$(echo "$raw_iter" | tr -d '\r\n' | xargs)

        # Skip Header oder leere Zeilen
        [[ "$matrix" == "Matrix" || -z "$matrix" || -z "$iter" ]] && continue

        # 2. VALIDIERUNG
        FULL_MATRIX_PATH="$MATRIX_DIR/$matrix"
        if [ ! -f "$FULL_MATRIX_PATH" ]; then
            echo "ERROR: Matrix file not found: $FULL_MATRIX_PATH"
            continue
        fi

        # Zähle bisherige Runs für diese Config
        CURRENT_COUNT=$(awk -F, -v m="$matrix" -v c="$cores" '$4==m && $5==c {count++} END {print count+0}' "$CSV")

        # Prüfe ob wir diesen Run machen müssen
        if (( CURRENT_COUNT >= MAX_RUNS )); then continue; fi
        if (( CURRENT_COUNT >= MIN_RUNS )); then
            CONV=$(check_convergence "$matrix" "$cores" "$iter")
            [[ "$CONV" != "fail" ]] && continue
        fi
        # Verhindere doppelte Runs im gleichen Schleifendurchgang
        if (( run_idx <= CURRENT_COUNT )); then continue; fi

        export OMP_NUM_THREADS=$cores
        RUN_NR=$((CURRENT_COUNT + 1))

        echo -n "[$(date +%H:%M:%S)] $matrix | Cores: $cores | Run: $RUN_NR ... "

        # 3. PERF AUFRUF (mit -- Trenner für das Binary)
        PERF_RAW=$( { ~/perf_for_vm stat -x ',' \
            -e duration_time,instructions,cycles,cache-misses,dTLB-load-misses \
            -- "$BINARY" "$FULL_MATRIX_PATH" "$iter" 1> "$TMP_OUT"; } 2>&1 )

        # Check auf C++ Crash (stoi Fehler abfangen)
        if [[ "$PERF_RAW" == *"terminate"* || "$PERF_RAW" == *"Aborted"* ]]; then
            echo "FAILED (C++ Crash). Matrix: $matrix, Iter: $iter"
            echo "Perf Error Output: $PERF_RAW"
            continue
        fi

        # Daten-Extraktion
        OUT_Intern_Runtime=$(grep "EXTRA_DATA" "$TMP_OUT" | cut -d',' -f2)
        OUT_Intern_Gflops=$(grep "EXTRA_DATA" "$TMP_OUT" | cut -d',' -f3)
        
        # Falls EXTRA_DATA leer ist, gab es ein Problem im Programm
        if [ -z "$OUT_Intern_Runtime" ]; then
            echo "FAILED (No EXTRA_DATA in output)."
            continue
        fi

        OUT_Perf_DurationTime=$(echo "$PERF_RAW" | grep "duration_time" | cut -d',' -f1 | head -n1)
        OUT_Perf_Instructions=$(echo "$PERF_RAW" | grep "instructions" | cut -d',' -f1 | head -n1)
        OUT_Perf_Cycles=$(echo "$PERF_RAW" | grep "cycles" | cut -d',' -f1 | head -n1)
        OUT_Perf_CacheMisses=$(echo "$PERF_RAW" | grep "cache-misses" | cut -d',' -f1 | head -n1)
        OUT_Perf_dTLBLoadMisses=$(echo "$PERF_RAW" | grep "dTLB-load-misses" | cut -d',' -f1 | head -n1)

        # In CSV schreiben
        echo "$NUMA_POLICY,$BOOST,$NUMA_BALANCING,$matrix,$cores,$RUN_NR,$iter,$OUT_Intern_Runtime,$OUT_Intern_Gflops,$OUT_Perf_DurationTime,$OUT_Perf_Instructions,$OUT_Perf_Cycles,$OUT_Perf_CacheMisses,$OUT_Perf_dTLBLoadMisses" >> "$CSV"
        sync "$CSV"
        echo "done."

    done < "$PLAN"
done

rm -f "$TMP_OUT" series_check.tmp
echo "Benchmark finished successfully."